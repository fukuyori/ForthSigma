//! Plays MSX BASIC's PLAY and SOUND on a PSG, for a host's audio thread.
//!
//! Two threads share an Engine: the Forth program (the producer) puts notes and commands
//! into one-way queues, and the audio thread (the consumer) takes them in `render`, which
//! makes the samples. Each queue has one writer of each index, so neither side locks or
//! waits. As on the MSX, a PLAY's voices start together: each PLAY ends every voice's
//! notes with an end mark, and the next PLAY starts only when all three voices reached
//! theirs (and the producer has put all of the next one in).

const std = @import("std");
const mml = @import("sound_mml.zig");
const psg_module = @import("sound_psg.zig");

pub const Event = mml.Event;
pub const Psg = psg_module.Psg;

/// A queue with one producer and one consumer. `capacity` must be a power of two.
pub fn Ring(comptime T: type, comptime capacity: u32) type {
    return struct {
        const Self = @This();
        items: [capacity]T = undefined,
        /// The next item to take; only the consumer writes it.
        head: std.atomic.Value(u32) = .init(0),
        /// The next free place; only the producer writes it.
        tail: std.atomic.Value(u32) = .init(0),

        pub const size = capacity;

        /// Producer: how many items fit now.
        pub fn free(self: *const Self) u32 {
            return capacity - (self.tail.raw -% self.head.load(.acquire));
        }

        /// Producer.
        pub fn push(self: *Self, item: T) bool {
            const tail = self.tail.raw;
            if (tail -% self.head.load(.acquire) >= capacity) return false;
            self.items[tail % capacity] = item;
            self.tail.store(tail +% 1, .release);
            return true;
        }

        /// Producer: whether the consumer has taken everything.
        pub fn isEmpty(self: *const Self) bool {
            return self.head.load(.acquire) == self.tail.raw;
        }

        /// Consumer: the next item, still in the queue.
        pub fn peek(self: *const Self) ?T {
            const head = self.head.raw;
            if (head == self.tail.load(.acquire)) return null;
            return self.items[head % capacity];
        }

        /// Consumer: takes the item `peek` gave.
        pub fn drop(self: *Self) void {
            self.head.store(self.head.raw +% 1, .release);
        }

        /// Consumer: takes everything before `position`, a tail the producer had.
        pub fn dropUntil(self: *Self, position: u32) void {
            self.head.store(position, .release);
        }
    };
}

/// Notes and end marks each voice can wait with.
pub const voice_queue_size = 32;

pub const Command = union(enum) {
    /// SOUND reg, value.
    write: struct { reg: u8, value: u8 },
    /// BEEP (with `beep`) or a stop: drops the notes put before it (up to these tails
    /// and this PLAY count), sounds 1316 Hz for 40 ms when `beep`, and sets the PSG as
    /// the MSX starts it.
    reset: struct { tails: [3]u32, plays: u32, beep: bool },
};

/// The PSG's registers as the MSX's BIOS sets them (GICINI): R0 = 55H, the tones on and
/// the noise off (R7 = B8H), R11 = 0BH, the others 0.
pub fn msxInitialRegisters() [16]u8 {
    var regs: [16]u8 = @splat(0);
    regs[0] = 0x55;
    regs[7] = 0xb8;
    regs[11] = 0x0b;
    return regs;
}

/// BEEP: about 1316 Hz (O6's E) at volume 7 for 40 ms.
pub const beep_period: u16 = 85;
pub const beep_volume: u8 = 7;
pub const beep_milliseconds: u32 = 40;

pub const Engine = struct {
    psg: Psg,
    sample_rate: u32,
    voices: [3]Ring(Event, voice_queue_size) = .{ .{}, .{}, .{} },
    commands: Ring(Command, 64) = .{},
    /// The PLAYs put in; only the producer writes it.
    plays_put: std.atomic.Value(u32) = .init(0),
    /// The PLAYs started; only the consumer writes it.
    plays_started: std.atomic.Value(u32) = .init(0),
    /// Bit n: voice n plays a note of the current PLAY; only the consumer writes it.
    sounding: std.atomic.Value(u8) = .init(0),

    // The consumer's own state.
    remaining: [3]u16 = .{ 0, 0, 0 },
    at_end: [3]bool = .{ true, true, true },
    tick_fraction: u32 = 0,
    beep_samples: u32 = 0,
    dc_input: f32 = 0,
    dc_output: f32 = 0,

    pub fn init(model: psg_module.Model, clock: u32, sample_rate: u32) Engine {
        var engine: Engine = .{ .psg = Psg.init(model, clock, sample_rate), .sample_rate = sample_rate };
        engine.setRegisters(msxInitialRegisters());
        return engine;
    }

    fn setRegisters(self: *Engine, regs: [16]u8) void {
        for (regs, 0..) |value, reg| self.psg.write(@intCast(reg), value);
    }

    // ---- The producer's side (the Forth program) ----

    /// How many more items voice `voice` can take now.
    pub fn voiceFree(self: *const Engine, voice: usize) u32 {
        return self.voices[voice].free();
    }

    pub fn putEvent(self: *Engine, voice: usize, event: Event) bool {
        return self.voices[voice].push(event);
    }

    /// Lets the audio thread start the PLAY being put.
    pub fn countPlay(self: *Engine) void {
        self.plays_put.store(self.plays_put.raw +% 1, .release);
    }

    /// Ends one PLAY with an end mark in each voice (the caller has checked they fit).
    pub fn endPlay(self: *Engine) void {
        for (&self.voices) |*queue| std.debug.assert(queue.push(.{ .kind = .end }));
    }

    pub fn putCommand(self: *Engine, command: Command) bool {
        return self.commands.push(command);
    }

    /// The command for BEEP (`beep`) or a stop, which drops every note put so far.
    pub fn resetCommand(self: *const Engine, beep: bool) Command {
        return .{ .reset = .{
            .tails = .{ self.voices[0].tail.raw, self.voices[1].tail.raw, self.voices[2].tail.raw },
            .plays = self.plays_put.raw,
            .beep = beep,
        } };
    }

    /// PLAY(n): whether voice n - 1 (or any voice, for n = 0) still has notes to play.
    pub fn isPlaying(self: *const Engine, n: usize) bool {
        if (n == 0) return self.isPlaying(1) or self.isPlaying(2) or self.isPlaying(3);
        const voice = n - 1;
        // The consumer sets `sounding` before it takes the note, so the voice never
        // looks idle between the two.
        if (self.sounding.load(.acquire) & (@as(u8, 1) << @intCast(voice)) != 0) return true;
        return !self.voices[voice].isEmpty();
    }

    // ---- The consumer's side (the audio thread) ----

    /// Fills `out` with stereo frames (left, right) of 16-bit samples.
    pub fn render(self: *Engine, out: []i16) void {
        self.runCommands();
        var i: usize = 0;
        while (i + 1 < out.len) : (i += 2) {
            if (self.beep_samples > 0) {
                self.beep_samples -= 1;
                if (self.beep_samples == 0) self.setRegisters(msxInitialRegisters());
            } else {
                self.tick_fraction += 50;
                if (self.tick_fraction >= self.sample_rate) {
                    self.tick_fraction -= self.sample_rate;
                    self.tick();
                }
            }
            const value = self.filtered(self.psg.sample());
            out[i] = value;
            out[i + 1] = value;
        }
    }

    /// The level without its constant part (as the coupling capacitor of a computer's
    /// audio output removes it), as a 16-bit sample.
    fn filtered(self: *Engine, x: f32) i16 {
        const y = x - self.dc_input + 0.9985 * self.dc_output;
        self.dc_input = x;
        self.dc_output = y;
        const scaled = std.math.clamp(y * 0.6, -1.0, 1.0) * 32767.0;
        return @intFromFloat(scaled);
    }

    fn runCommands(self: *Engine) void {
        while (self.commands.peek()) |command| {
            self.commands.drop();
            switch (command) {
                .write => |w| self.psg.write(w.reg, w.value),
                .reset => |b| {
                    for (&self.voices, b.tails) |*queue, tail| queue.dropUntil(tail);
                    self.plays_started.store(b.plays, .release);
                    self.remaining = .{ 0, 0, 0 };
                    self.at_end = .{ true, true, true };
                    self.sounding.store(0, .release);
                    self.setRegisters(msxInitialRegisters());
                    if (b.beep) {
                        self.psg.write(0, @truncate(beep_period));
                        self.psg.write(1, @truncate(beep_period >> 8));
                        self.psg.write(8, beep_volume);
                        self.beep_samples = @max(self.sample_rate * beep_milliseconds / 1000, 1);
                    }
                },
            }
        }
    }

    /// One tick of 1/50 second: each voice counts down its note and takes the next.
    fn tick(self: *Engine) void {
        for (0..3) |v| {
            if (self.remaining[v] > 0) self.remaining[v] -= 1;
            if (self.remaining[v] == 0 and !self.at_end[v]) self.nextEvent(v);
        }
        if (self.at_end[0] and self.at_end[1] and self.at_end[2]) self.startPlay();
    }

    fn startPlay(self: *Engine) void {
        const started = self.plays_started.raw;
        if (self.plays_put.load(.acquire) == started) return;
        self.plays_started.store(started +% 1, .release);
        self.at_end = .{ false, false, false };
        for (0..3) |v| self.nextEvent(v);
    }

    fn nextEvent(self: *Engine, v: usize) void {
        // The producer puts a whole PLAY before it counts it, so the voice has an item.
        const event = self.voices[v].peek() orelse return;
        const bit = @as(u8, 1) << @intCast(v);
        switch (event.kind) {
            .end => {
                self.at_end[v] = true;
                self.psg.write(@intCast(8 + v), 0);
                self.sounding.store(self.sounding.raw & ~bit, .release);
                self.voices[v].drop();
            },
            .note => {
                self.sounding.store(self.sounding.raw | bit, .release);
                self.voices[v].drop();
                self.play(v, event);
            },
        }
    }

    fn play(self: *Engine, v: usize, event: Event) void {
        self.remaining[v] = event.ticks;
        const reg: u8 = @intCast(v * 2);
        if (event.period != 0) {
            self.psg.write(reg, @truncate(event.period));
            self.psg.write(reg + 1, @truncate(event.period >> 8));
        }
        if (event.period != 0 and event.amplitude == 16) {
            self.psg.write(11, @truncate(event.envelope_period));
            self.psg.write(12, @truncate(event.envelope_period >> 8));
            self.psg.write(@intCast(8 + v), 16);
            self.psg.write(13, event.shape);
        } else {
            self.psg.write(@intCast(8 + v), if (event.period == 0) 0 else event.amplitude);
        }
    }
};

/// Puts one PLAY's voices (up to 3 texts) for `engine`, a note at a time, after checking
/// all of them, so that an error puts nothing. When the voices that still have notes are
/// all full, the PLAY is let start (as the MSX does, so that a long PLAY plays while it
/// is being put) and `waitFn(context)` is called until there is room; it returns false
/// to stop, and putPlay then returns error.Interrupted: the notes put so far stay, and
/// the caller drops them with a reset command.
pub fn putPlay(engine: *Engine, voices: []mml.Voice, texts: []const []const u8, context: anytype, comptime waitFn: fn (@TypeOf(context)) bool) (mml.Error || error{Interrupted})!void {
    std.debug.assert(texts.len <= 3 and voices.len >= texts.len);
    for (texts, 0..) |text, v| try mml.check(voices[v], text);
    var parsers: [3]?mml.Parser = .{ null, null, null };
    for (texts, 0..) |text, v| parsers[v] = mml.Parser.init(&voices[v], text);
    var pending: [3]?Event = .{ null, null, null };
    var counted = false;
    while (true) {
        var left = false;
        var progressed = false;
        for (0..3) |v| {
            if (parsers[v] == null) continue;
            while (true) {
                if (pending[v] == null) pending[v] = parsers[v].?.next() catch unreachable;
                const event = pending[v] orelse {
                    parsers[v] = null;
                    break;
                };
                // Keep one place for the end mark.
                if (engine.voiceFree(v) <= 1) break;
                std.debug.assert(engine.putEvent(v, event));
                pending[v] = null;
                progressed = true;
            }
            if (parsers[v] != null) left = true;
        }
        if (!left) break;
        if (!progressed) {
            if (!counted) {
                engine.countPlay();
                counted = true;
            }
            if (!waitFn(context)) return error.Interrupted;
        }
    }
    while (engine.voiceFree(0) < 1 or engine.voiceFree(1) < 1 or engine.voiceFree(2) < 1) {
        if (!counted) {
            engine.countPlay();
            counted = true;
        }
        if (!waitFn(context)) return error.Interrupted;
    }
    engine.endPlay();
    if (!counted) engine.countPlay();
}
