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
const c64_module = @import("sound_c64.zig");
const scc_module = @import("sound_scc.zig");
const amiga_module = @import("sound_amiga.zig");
pub const pcm = @import("sound_pcm.zig");
pub const mod_module = @import("sound_mod.zig");

pub const Event = mml.Event;
pub const Psg = psg_module.Psg;
pub const Instrument = parts.Instrument;

/// The chip a note sounds like. The PSG runs with every chip, for SOUND and BEEP.
pub const Chip = parts.Chip;

/// How many voices a chip has of its own.
fn chipVoices(chip: Chip) usize {
    return switch (chip) {
        .msx, .atari_st => 3,
        .nes => nes_module.voice_count,
        .c64 => c64_module.voice_count,
        .scc => scc_module.voice_count,
        .amiga => amiga_module.voice_count,
    };
}

/// The chips the voices have (CHIPS; MSX-SOUND and the others choose one), which an
/// instrument without STYLE sounds like. Their voices are numbered in the order of
/// `Chip`: with the MSX and the SCC, voices 1 to 3 are the PSG's and 4 to 8 the SCC's.
/// The voices after those of the last chip sound like the last chip.
pub const Chips = struct {
    mask: u8,

    pub fn one(chip: Chip) Chips {
        return .{ .mask = bit(chip) };
    }

    fn bit(chip: Chip) u8 {
        return @as(u8, 1) << @intCast(@backingInt(chip));
    }

    pub fn has(self: Chips, chip: Chip) bool {
        return self.mask & bit(chip) != 0;
    }

    /// The chip, when only one is chosen.
    pub fn only(self: Chips) ?Chip {
        if (@popCount(self.mask) != 1) return null;
        return @fromBackingInt(@intCast(@ctz(self.mask)));
    }

    /// A mask CHIPS takes: at least one chip, and no unknown bit.
    pub fn fromMask(mask: i64) ?Chips {
        const all = (@as(i64, 1) << chip_count) - 1;
        if (mask <= 0 or mask & ~all != 0) return null;
        return .{ .mask = @intCast(mask) };
    }

    pub fn voiceCount(self: Chips) usize {
        var count: usize = 0;
        for (0..chip_count) |c| {
            const chip: Chip = @fromBackingInt(@intCast(c));
            if (self.has(chip)) count += chipVoices(chip);
        }
        return count;
    }

    /// The chip whose own voice v (from 0) is, and the voice's number on that chip.
    pub fn place(self: Chips, v: usize) ?struct { chip: Chip, voice: usize } {
        var first: usize = 0;
        for (0..chip_count) |c| {
            const chip: Chip = @fromBackingInt(@intCast(c));
            if (!self.has(chip)) continue;
            if (v < first + chipVoices(chip)) return .{ .chip = chip, .voice = v - first };
            first += chipVoices(chip);
        }
        return null;
    }

    /// The chip voice v sounds like when its instrument has no STYLE.
    pub fn chipOf(self: Chips, v: usize) Chip {
        if (self.place(v)) |at| return at.chip;
        var last: Chip = .msx;
        for (0..chip_count) |c| {
            const chip: Chip = @fromBackingInt(@intCast(c));
            if (self.has(chip)) last = chip;
        }
        return last;
    }

    /// The voice (from 0) where a chip's own voices start, if it is one of these.
    pub fn firstVoice(self: Chips, wanted: Chip) ?usize {
        if (!self.has(wanted)) return null;
        var first: usize = 0;
        for (0..chip_count) |c| {
            const chip: Chip = @fromBackingInt(@intCast(c));
            if (chip == wanted) break;
            if (self.has(chip)) first += chipVoices(chip);
        }
        return if (first < max_voices) first else null;
    }
};

const chip_count = 6;

/// The voices PLAY has; each has its queue, and can sound like any chip.
pub const max_voices = parts.voice_slots;

/// The PSGs besides `Engine.psg`: each chip's voices go three to a PSG, so there are two
/// more of its kind and three of the other kind.
const extra_psgs = 5;

/// The SFX that can sound at once; a new one takes the place of the oldest.
pub const sfx_voices = 4;

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
    reset: struct { tails: [max_voices]u32, plays: u32, beep: bool, chips: ?Chips = null },
    /// INSTRUMENT and the words after it: the instrument's settings, which the notes
    /// that start from now on use.
    instrument: struct { index: u8, value: Instrument },
    /// LOAD-SAMPLE, SAMPLE, and LOOP-SAMPLE: where sample `index` is in the pool.
    sample: struct { index: u8, value: pcm.Sample },
    /// FREE-SAMPLES, after a stop: every sample is gone.
    free_samples,
    /// SFX: plays a sample once at its rate, at once and beside the music.
    sfx: u8,
    /// AMIGA-FILTER: the LED filter on or off.
    amiga_filter: bool,
    /// LOAD-MOD: the module whose song (sound_mod.Song) is in the pool from this place
    /// (in 16-bit units). A module that plays stops.
    mod_load: u32,
    /// PLAY-MOD: plays the module from its start, again after its end when true.
    mod_play: bool,
    /// STOP-MOD.
    mod_stop,
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
    /// The PSG of SOUND and BEEP, and of the first three voices.
    psg: Psg,
    /// The other PSGs, for the voices that use them.
    psg_extra: [extra_psgs]Psg,
    /// Bit n: `psg_extra[n]` has played since the last stop.
    psg_used: u8 = 0,
    nes: nes_module.Nes,
    c64: c64_module.C64,
    scc: scc_module.Scc,
    amiga: amiga_module.Amiga,
    sample_rate: u32,
    /// The host's pool of samples; the producer adds to its end (sound_pcm.zig).
    pool: []i16 = &.{},
    samples: [pcm.sample_count]pcm.Sample = @splat(.{}),
    amiga_led: bool = false,
    /// The voices of SFX, used in turn.
    sfx_players: [sfx_voices]pcm.Player = @splat(.{}),
    sfx_next: usize = 0,
    mod: mod_module.Mod,
    /// Whether the module plays; only the consumer writes it (MOD?).
    mod_playing: std.atomic.Value(bool) = .init(false),
    chips: Chips = Chips.one(.msx),
    /// The chips that make sound: `chips`, and those STYLE has used since the last stop.
    active: Chips = Chips.one(.msx),
    /// The chip each voice's last note played on, since the last stop.
    current: [max_voices]?Chip = @splat(null),
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
    dc_input: [2]f32 = .{ 0, 0 },
    dc_output: [2]f32 = .{ 0, 0 },

    pub fn init(model: psg_module.Model, clock: u32, sample_rate: u32) Engine {
        var engine: Engine = .{ .psg = Psg.init(model, clock, sample_rate), .psg_extra = undefined, .nes = nes_module.Nes.init(sample_rate), .c64 = c64_module.C64.init(sample_rate), .scc = scc_module.Scc.init(sample_rate), .amiga = amiga_module.Amiga.init(sample_rate), .mod = mod_module.Mod.init(sample_rate), .sample_rate = sample_rate };
        engine.setRegisters(msxInitialRegisters());
        engine.resetVoices();
        return engine;
    }

    fn setRegisters(self: *Engine, regs: [16]u8) void {
        for (regs, 0..) |value, reg| self.psg.write(@intCast(reg), value);
    }

    /// After a stop or a change of chips: no voice has played, the other PSGs are as at
    /// start, and each chip knows which voices are its own.
    fn resetVoices(self: *Engine) void {
        const main_is_ym = self.psg.model == .ym2149;
        for (&self.psg_extra, 0..) |*psg, i| {
            const is_ym = if (i < 2) main_is_ym else !main_is_ym;
            psg.* = if (is_ym)
                Psg.init(.ym2149, psg_module.atari_st_clock, self.sample_rate)
            else
                Psg.init(.ay8910, psg_module.msx_clock, self.sample_rate);
            for (msxInitialRegisters(), 0..) |value, reg| psg.write(@intCast(reg), value);
        }
        self.psg_used = 0;
        self.active = self.chips;
        self.current = @splat(null);
        self.nes.place(self.chips.firstVoice(.nes));
        self.c64.place(self.chips.firstVoice(.c64));
        self.amiga.place(self.chips.firstVoice(.amiga));
    }

    /// Which of `psg_extra` plays voice v as `chip`, or null for `psg`.
    fn psgIndex(self: *const Engine, chip: Chip, v: usize) ?usize {
        const bank = v / 3;
        if ((chip == .atari_st) == (self.psg.model == .ym2149)) {
            return if (bank == 0) null else bank - 1;
        }
        return 2 + bank;
    }

    fn psgOf(self: *Engine, chip: Chip, v: usize) *Psg {
        return if (self.psgIndex(chip, v)) |i| &self.psg_extra[i] else &self.psg;
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
        return self.chipsCommand(Chips.one(chip));
    }

    /// The command for CHIPS: a stop that also chooses the chips.
    pub fn chipsCommand(self: *const Engine, chips: Chips) Command {
        var command = self.resetCommand(false);
        command.reset.chips = chips;
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
            var center = self.psg.sample() + self.sfxSample();
            if (self.psg_used != 0) {
                for (&self.psg_extra, 0..) |*psg, n| {
                    if (self.psg_used & (@as(u8, 1) << @intCast(n)) != 0) center += psg.sample();
                }
            }
            if (self.active.has(.nes)) center += self.nes.sample();
            if (self.active.has(.c64)) center += self.c64.sample();
            if (self.active.has(.scc)) center += self.scc.sample();
            var sides: [2]f32 = .{ center, center };
            if (self.active.has(.amiga)) {
                const amiga = self.amiga.sample(self.pool, self.amiga_led);
                sides[0] += amiga[0];
                sides[1] += amiga[1];
            }
            if (self.mod.playing) {
                const module = self.mod.sample(self.pool, &self.amiga_led);
                sides[0] += module[0];
                sides[1] += module[1];
            }
            out[i] = self.filtered(0, sides[0]);
            out[i + 1] = self.filtered(1, sides[1]);
        }
        self.mod_playing.store(self.mod.playing, .release);
    }

    /// The level without its constant part (as the coupling capacitor of a computer's
    /// audio output removes it), as a 16-bit sample.
    fn filtered(self: *Engine, side: usize, x: f32) i16 {
        const y = x - self.dc_input[side] + 0.9985 * self.dc_output[side];
        self.dc_input[side] = x;
        self.dc_output[side] = y;
        const scaled = std.math.clamp(y * 0.6, -1.0, 1.0) * 32767.0;
        return @intFromFloat(scaled);
    }

    fn runCommands(self: *Engine) void {
        while (self.commands.peek()) |command| {
            self.commands.drop();
            switch (command) {
                .write => |w| self.psg.write(w.reg, w.value),
                .instrument => |i| self.instruments[i.index] = i.value,
                .sample => |s| self.samples[s.index] = s.value,
                .free_samples => {
                    self.samples = @splat(.{});
                    self.mod = mod_module.Mod.init(self.sample_rate);
                    self.mod_playing.store(false, .release);
                },
                .mod_load => |at| {
                    self.mod.stop();
                    const bytes = std.mem.sliceAsBytes(self.pool);
                    const start = @as(usize, at) * 2;
                    @memcpy(std.mem.asBytes(&self.mod.song), bytes[start..][0..@sizeOf(mod_module.Song)]);
                    self.mod_playing.store(false, .release);
                },
                .mod_play => |repeat| {
                    self.mod.start(repeat);
                    self.mod_playing.store(self.mod.playing, .release);
                },
                .mod_stop => {
                    self.mod.stop();
                    self.mod_playing.store(false, .release);
                },
                .amiga_filter => |on| self.amiga_led = on,
                .sfx => |n| {
                    self.sfx_players[self.sfx_next].start(self.samples[n], @as(f64, @floatFromInt(self.samples[n].rate)) / @as(f64, @floatFromInt(self.sample_rate)));
                    self.sfx_next = (self.sfx_next + 1) % sfx_voices;
                },
                .reset => |b| {
                    for (&self.voices, b.tails) |*queue, tail| queue.dropUntil(tail);
                    self.plays_started.store(b.plays, .release);
                    self.remaining = @splat(0);
                    self.at_end = @splat(true);
                    self.sounding.store(0, .release);
                    if (b.chips) |chips| {
                        self.chips = chips;
                        // The Atari ST's YM2149 runs at 2 MHz; the MSX's PSG is an AY.
                        self.psg = if (chips.has(.atari_st) and !chips.has(.msx))
                            Psg.init(.ym2149, psg_module.atari_st_clock, self.sample_rate)
                        else
                            Psg.init(.ay8910, psg_module.msx_clock, self.sample_rate);
                    }
                    self.nes = nes_module.Nes.init(self.sample_rate);
                    self.c64 = c64_module.C64.init(self.sample_rate);
                    self.scc = scc_module.Scc.init(self.sample_rate);
                    self.amiga = amiga_module.Amiga.init(self.sample_rate);
                    self.resetVoices();
                    self.sfx_players = @splat(.{});
                    self.mod.stop();
                    self.mod_playing.store(false, .release);
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

    /// The SFX voices together, each sample once at half the full level.
    fn sfxSample(self: *Engine) f32 {
        var sum: f32 = 0;
        for (&self.sfx_players) |*player| sum += player.next(self.pool) * 0.5;
        return sum;
    }

    /// Ends voice v's note (at a rest or the end of a PLAY).
    fn silence(self: *Engine, v: usize) void {
        self.silenceOn(self.current[v] orelse self.chips.chipOf(v), v);
    }

    fn silenceOn(self: *Engine, chip: Chip, v: usize) void {
        switch (chip) {
            .msx, .atari_st => self.psgOf(chip, v).write(@intCast(8 + v % 3), 0),
            .nes => self.nes.noteOff(v),
            .c64 => self.c64.noteOff(v),
            .scc => self.scc.noteOff(v),
            .amiga => self.amiga.noteOff(v),
        }
    }

    fn play(self: *Engine, v: usize, event: Event) void {
        self.remaining[v] = event.ticks;
        if (event.period == 0) return self.silence(v);
        const volume = @min(event.amplitude, 15);
        const instrument = self.instruments[event.instrument];
        const chip = instrument.style orelse self.chips.chipOf(v);
        // A voice sounds on one chip at a time.
        if (self.current[v]) |old| {
            if (old != chip) self.silenceOn(old, v);
        }
        self.current[v] = chip;
        self.active.mask |= Chips.one(chip).mask;
        switch (chip) {
            .msx, .atari_st => {
                if (self.psgIndex(chip, v)) |n| self.psg_used |= @as(u8, 1) << @intCast(n);
                // The same note on the YM2149's 2 MHz clock.
                const period: u16 = if (chip == .msx) event.period else @intCast(parts.chipPeriod(event.note, psg_module.atari_st_clock, 16, 0, 4095));
                playPsg(self.psgOf(chip, v), v % 3, event, period);
            },
            // S (the PSG's envelope) has no meaning here: such a note plays at full volume.
            .nes => {
                if (instrument.style != null) {
                    self.nes.noteOnWave(v, event.note, volume, instrument);
                } else {
                    self.nes.noteOn(v, event.note, volume, instrument);
                }
            },
            .c64 => self.c64.noteOn(v, event.note, volume, instrument),
            .scc => self.scc.noteOn(v, event.note, volume, instrument),
            .amiga => self.amiga.noteOn(v, event.note, volume, instrument, &self.samples),
        }
    }

    fn playPsg(psg: *Psg, channel: usize, event: Event, period: u16) void {
        const reg: u8 = @intCast(channel * 2);
        psg.write(reg, @truncate(period));
        psg.write(reg + 1, @truncate(period >> 8));
        if (event.amplitude == 16) {
            psg.write(11, @truncate(event.envelope_period));
            psg.write(12, @truncate(event.envelope_period >> 8));
            psg.write(@intCast(8 + channel), 16);
            psg.write(13, event.shape);
        } else {
            psg.write(@intCast(8 + channel), event.amplitude);
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
