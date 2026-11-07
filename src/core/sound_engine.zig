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
const parts = @import("sound_parts.zig");
const nes_module = @import("sound_nes.zig");

pub const Event = mml.Event;
pub const Psg = psg_module.Psg;
pub const Instrument = parts.Instrument;

/// The chip PLAY plays on (MSX-SOUND and the others). The PSG runs with every chip, for
/// SOUND and BEEP.
pub const Chip = enum(u8) {
    msx,
    atari_st,
    nes,

    pub fn voiceCount(chip: Chip) usize {
        return switch (chip) {
            .msx, .atari_st => 3,
            .nes => nes_module.voice_count,
        };
    }
};

/// The most voices a chip has; each has its queue.
pub const max_voices = 5;

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
    /// the MSX starts it. With `chip`, PLAY plays on that chip from now on.
    reset: struct { tails: [max_voices]u32, plays: u32, beep: bool, chip: ?Chip = null },
    /// INSTRUMENT and the words after it: the instrument's settings, which the notes
    /// that start from now on use.
    instrument: struct { index: u8, value: Instrument },
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
    nes: nes_module.Nes,
    sample_rate: u32,
    chip: Chip = .msx,
    instruments: [mml.instrument_count]Instrument = @splat(.{}),
    voices: [max_voices]Ring(Event, voice_queue_size) = @splat(.{}),
    commands: Ring(Command, 64) = .{},
    /// The PLAYs put in; only the producer writes it.
    plays_put: std.atomic.Value(u32) = .init(0),
    /// The PLAYs started; only the consumer writes it.
    plays_started: std.atomic.Value(u32) = .init(0),
    /// Bit n: voice n plays a note of the current PLAY; only the consumer writes it.
    sounding: std.atomic.Value(u8) = .init(0),

    // The consumer's own state.
    remaining: [max_voices]u16 = @splat(0),
    at_end: [max_voices]bool = @splat(true),
    tick_fraction: u32 = 0,
    beep_samples: u32 = 0,
    dc_input: f32 = 0,
    dc_output: f32 = 0,

    pub fn init(model: psg_module.Model, clock: u32, sample_rate: u32) Engine {
        var engine: Engine = .{ .psg = Psg.init(model, clock, sample_rate), .nes = nes_module.Nes.init(sample_rate), .sample_rate = sample_rate };
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
        var tails: [max_voices]u32 = undefined;
        for (&tails, &self.voices) |*tail, *queue| tail.* = queue.tail.raw;
        return .{ .reset = .{ .tails = tails, .plays = self.plays_put.raw, .beep = beep } };
    }

    /// The command for MSX-SOUND and the others: a stop that also chooses the chip.
    pub fn chipCommand(self: *const Engine, chip: Chip) Command {
        var command = self.resetCommand(false);
        command.reset.chip = chip;
        return command;
    }

    /// PLAY(n): whether voice n - 1 (or any voice, for n = 0) still has notes to play.
    pub fn isPlaying(self: *const Engine, n: usize) bool {
        if (n == 0) {
            for (1..max_voices + 1) |voice| {
                if (self.isPlaying(voice)) return true;
            }
            return false;
        }
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
            var level = self.psg.sample();
            if (self.chip == .nes) level += self.nes.sample();
            const value = self.filtered(level);
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
                .instrument => |i| self.instruments[i.index] = i.value,
                .reset => |b| {
                    for (&self.voices, b.tails) |*queue, tail| queue.dropUntil(tail);
                    self.plays_started.store(b.plays, .release);
                    self.remaining = @splat(0);
                    self.at_end = @splat(true);
                    self.sounding.store(0, .release);
                    if (b.chip) |chip| {
                        self.chip = chip;
                        // The Atari ST's YM2149 runs at 2 MHz; the MSX's PSG is an AY.
                        self.psg = if (chip == .atari_st)
                            Psg.init(.ym2149, psg_module.atari_st_clock, self.sample_rate)
                        else
                            Psg.init(.ay8910, psg_module.msx_clock, self.sample_rate);
                    }
                    self.nes = nes_module.Nes.init(self.sample_rate);
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
        for (0..max_voices) |v| {
            if (self.remaining[v] > 0) self.remaining[v] -= 1;
            if (self.remaining[v] == 0 and !self.at_end[v]) self.nextEvent(v);
        }
        for (self.at_end) |at_end| {
            if (!at_end) return;
        }
        self.startPlay();
    }

    fn startPlay(self: *Engine) void {
        const started = self.plays_started.raw;
        if (self.plays_put.load(.acquire) == started) return;
        self.plays_started.store(started +% 1, .release);
        self.at_end = @splat(false);
        for (0..max_voices) |v| self.nextEvent(v);
    }

    fn nextEvent(self: *Engine, v: usize) void {
        // The producer puts a whole PLAY before it counts it, so the voice has an item.
        const event = self.voices[v].peek() orelse return;
        const bit = @as(u8, 1) << @intCast(v);
        switch (event.kind) {
            .end => {
                self.at_end[v] = true;
                self.silence(v);
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

    /// Ends voice v's note (at a rest or the end of a PLAY).
    fn silence(self: *Engine, v: usize) void {
        switch (self.chip) {
            .msx, .atari_st => if (v < 3) self.psg.write(@intCast(8 + v), 0),
            .nes => if (v < nes_module.voice_count) self.nes.noteOff(v),
        }
    }

    fn play(self: *Engine, v: usize, event: Event) void {
        self.remaining[v] = event.ticks;
        if (v >= self.chip.voiceCount()) return;
        if (event.period == 0) return self.silence(v);
        switch (self.chip) {
            .msx => self.playPsg(v, event, event.period),
            // The same note on the YM2149's 2 MHz clock.
            .atari_st => self.playPsg(v, event, @intCast(parts.chipPeriod(event.note, psg_module.atari_st_clock, 16, 0, 4095))),
            // S (the PSG's envelope) has no meaning here: such a note plays at full volume.
            .nes => self.nes.noteOn(v, event.note, @min(event.amplitude, 15), self.instruments[event.instrument]),
        }
    }

    fn playPsg(self: *Engine, v: usize, event: Event, period: u16) void {
        const reg: u8 = @intCast(v * 2);
        self.psg.write(reg, @truncate(period));
        self.psg.write(reg + 1, @truncate(period >> 8));
        if (event.amplitude == 16) {
            self.psg.write(11, @truncate(event.envelope_period));
            self.psg.write(12, @truncate(event.envelope_period >> 8));
            self.psg.write(@intCast(8 + v), 16);
            self.psg.write(13, event.shape);
        } else {
            self.psg.write(@intCast(8 + v), event.amplitude);
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
    std.debug.assert(texts.len <= max_voices and voices.len >= texts.len);
    for (texts, 0..) |text, v| try mml.check(voices[v], text);
    var parsers: [max_voices]?mml.Parser = @splat(null);
    for (texts, 0..) |text, v| parsers[v] = mml.Parser.init(&voices[v], text);
    var pending: [max_voices]?Event = @splat(null);
    var counted = false;
    while (true) {
        var left = false;
        var progressed = false;
        for (0..max_voices) |v| {
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
    while (!allHaveRoom(engine)) {
        if (!counted) {
            engine.countPlay();
            counted = true;
        }
        if (!waitFn(context)) return error.Interrupted;
    }
    engine.endPlay();
    if (!counted) engine.countPlay();
}

fn allHaveRoom(engine: *const Engine) bool {
    for (0..max_voices) |v| {
        if (engine.voiceFree(v) < 1) return false;
    }
    return true;
}
