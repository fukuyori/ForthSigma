//! The C64's sound (the SID, on a PAL machine) for C64-SOUND: three voices, each a
//! triangle, sawtooth, pulse, or noise with its ADSR, ring modulation and hard sync by
//! the voice before it, and one filter the voices share.
//!
//! The behavior follows the SID's data sheet and the descriptions in
//! docs/SOUND_RESEARCH.md; no emulator's code is used. A note's pitch is rounded to the
//! SID's 16-bit frequency register and the pulse's width to its 12 bits. The waves are
//! made at the output's rate (the pulse and the sawtooth band-limited), so the sound is
//! near the chip's and not its copy: the 6581's filter curve, which differs from chip to
//! chip, is taken as the 8580's straight line, and the waves are not combined.

const std = @import("std");
const parts = @import("sound_parts.zig");

/// The clock of a PAL C64.
pub const clock: u32 = 985_248;

/// The chip's voices, which set its level in the mix; `C64.voices` has a place for every
/// voice of PLAY.
pub const voice_count = 3;

/// The frequency register for a note: frequency × 2^24 / clock, rounded, at most 65535.
pub fn frequencyRegister(note: u8) u16 {
    const exact = parts.noteFrequency(note) * 16_777_216.0 / @as(f64, @floatFromInt(clock));
    return @intFromFloat(@min(@round(exact), 65535));
}

/// The pulse's width register (12 bits) for an instrument's duty in percent.
pub fn pulseWidthRegister(duty: u8) u16 {
    return @intFromFloat(@round(@as(f32, @floatFromInt(@min(duty, 100))) / 100.0 * 4095.0));
}

/// The filter's cutoff in Hz for the register's 11 bits: the 8580's line, from about
/// 30 Hz to 12 kHz.
pub fn cutoffFrequency(cutoff: u16) f32 {
    return 30.0 + @as(f32, @floatFromInt(@min(cutoff, 2047))) * 5.8;
}

const Voice = struct {
    on: bool = false,
    /// The phase (0 to 1) and its step a sample.
    phase: f32 = 0,
    increment: f32 = 0,
    instrument: parts.Instrument = .{},
    /// The pulse's high part (0 to 1), from the 12-bit register.
    width: f32 = 0.5,
    /// MML's V as a factor, 0 to 1.
    volume: f32 = 0,
    adsr: parts.Adsr = .{},
    /// 23 bits; the input is bit 22 XOR bit 17. It shifts 16 times a cycle.
    lfsr: u32 = 0x7ffff8,
    noise_fraction: f32 = 0,
};

/// The state-variable filter, solved for each sample (stable at every cutoff).
const Filter = struct {
    mode: u8 = 0,
    a1: f32 = 0,
    a2: f32 = 0,
    a3: f32 = 0,
    k: f32 = 2,
    ic1: f32 = 0,
    ic2: f32 = 0,

    fn set(self: *Filter, mode: u8, cutoff: u16, resonance: u8, sample_rate: u32) void {
        const rate: f32 = @floatFromInt(sample_rate);
        const g = @tan(std.math.pi * @min(cutoffFrequency(cutoff), rate * 0.45) / rate);
        // Resonance 0 is Q 0.707; 15 is about Q 4.7.
        self.k = 1.414 - @as(f32, @floatFromInt(@min(resonance, 15))) / 15.0 * 1.2;
        self.a1 = 1.0 / (1.0 + g * (g + self.k));
        self.a2 = g * self.a1;
        self.a3 = g * self.a2;
        self.mode = mode;
    }

    fn process(self: *Filter, input: f32) f32 {
        const v3 = input - self.ic2;
        const v1 = self.a1 * self.ic1 + self.a2 * v3;
        const v2 = self.ic2 + self.a2 * self.ic1 + self.a3 * v3;
        self.ic1 = 2 * v1 - self.ic1;
        self.ic2 = 2 * v2 - self.ic2;
        return switch (self.mode) {
            1 => v2,
            2 => v1,
            else => input - self.k * v1 - v2,
        };
    }
};

pub const C64 = struct {
    sample_rate: u32,
    voices: [parts.voice_slots]Voice = @splat(.{}),
    filter: Filter = .{},
    /// The voice each voice's RING and SYNC listen to.
    before: [parts.voice_slots]u8 = undefined,

    pub fn init(sample_rate: u32) C64 {
        var c64: C64 = .{ .sample_rate = sample_rate };
        c64.place(0);
        return c64;
    }

    /// The three voices from `first` go round as the chip's do (the first listens to
    /// the third); every other voice listens to the one before it.
    pub fn place(self: *C64, first: ?usize) void {
        for (&self.before, 0..) |*before, v| {
            before.* = @intCast((v + parts.voice_slots - 1) % parts.voice_slots);
        }
        const at = first orelse return;
        if (at + voice_count <= parts.voice_slots) self.before[at] = @intCast(at + voice_count - 1);
    }

    /// `volume` is MML's V, 0 to 15 (the SID has one volume for all; here each voice's
    /// notes are scaled by theirs).
    pub fn noteOn(self: *C64, v: usize, note: u8, volume: u8, instrument: parts.Instrument) void {
        const voice = &self.voices[v];
        const actual = @as(f32, @floatFromInt(frequencyRegister(note))) * @as(f32, @floatFromInt(clock)) / 16_777_216.0;
        voice.on = true;
        voice.increment = actual / @as(f32, @floatFromInt(self.sample_rate));
        voice.instrument = instrument;
        voice.width = if (instrument.wave == .square) 0.5 else @as(f32, @floatFromInt(pulseWidthRegister(instrument.duty))) / 4096.0;
        voice.volume = @as(f32, @floatFromInt(@min(volume, 15))) / 15.0;
        voice.adsr.start(instrument, self.sample_rate);
        // As on the SID, the filter is one for all voices: the last note that uses it
        // sets it.
        if (instrument.filter != 0) self.filter.set(instrument.filter, instrument.cutoff, instrument.resonance, self.sample_rate);
    }

    pub fn noteOff(self: *C64, v: usize) void {
        self.voices[v].on = false;
        self.voices[v].adsr.stop();
    }

    /// The next sample, about -1 to 1.
    pub fn sample(self: *C64) f32 {
        // Each voice is synced and ring-modulated by the one before (voice 1 by voice 3),
        // from where that one was at the start of this sample.
        var modulator_high: [parts.voice_slots]bool = undefined;
        for (self.voices, 0..) |voice, v| modulator_high[v] = voice.phase >= 0.5;
        var wrapped: [parts.voice_slots]bool = undefined;
        for (&self.voices, 0..) |*voice, v| {
            voice.phase += voice.increment;
            wrapped[v] = voice.phase >= 1;
            if (wrapped[v]) voice.phase -= 1;
        }
        var direct: f32 = 0;
        var filtered: f32 = 0;
        for (&self.voices, 0..) |*voice, v| {
            const before = self.before[v];
            if (voice.instrument.sync and wrapped[before]) voice.phase = 0;
            const ring_high = voice.instrument.ring and modulator_high[before];
            const value = self.wave(voice, ring_high) * voice.adsr.next() * voice.volume;
            if (voice.instrument.filter != 0) filtered += value else direct += value;
        }
        if (self.filter.mode != 0) direct += self.filter.process(filtered) else direct += filtered;
        return direct / voice_count;
    }

    /// One voice's wave now, -1 to 1.
    fn wave(self: *C64, voice: *Voice, ring_high: bool) f32 {
        const phase = voice.phase;
        const increment = voice.increment;
        return switch (voice.instrument.wave) {
            .triangle => blk: {
                // The SID's triangle is the phase folded at its top bit; ring modulation
                // turns that bit over while the voice before is in its upper half.
                var high = phase >= 0.5;
                if (ring_high) high = !high;
                const lower = phase * 2 - @floor(phase * 2);
                break :blk (if (high) 1 - lower else lower) * 2 - 1;
            },
            .saw => phase * 2 - 1 - parts.polyBlep(phase, increment),
            .square, .pulse => blk: {
                var value: f32 = if (phase < voice.width) 1 else -1;
                value += parts.polyBlep(phase, increment);
                var fall = phase - voice.width;
                if (fall < 0) fall += 1;
                value -= parts.polyBlep(fall, increment);
                break :blk value;
            },
            .noise => self.noise(voice),
        };
    }

    /// The noise: its 8-bit output from the shift register's taps, as the SID's.
    fn noise(self: *C64, voice: *Voice) f32 {
        _ = self;
        voice.noise_fraction += voice.increment * 16;
        while (voice.noise_fraction >= 1) {
            voice.noise_fraction -= 1;
            const bit = ((voice.lfsr >> 22) ^ (voice.lfsr >> 17)) & 1;
            voice.lfsr = ((voice.lfsr << 1) | bit) & 0x7fffff;
        }
        const r = voice.lfsr;
        const taps = [8]u5{ 20, 18, 14, 11, 9, 5, 2, 0 };
        var value: u32 = 0;
        for (taps) |tap| value = (value << 1) | ((r >> tap) & 1);
        return @as(f32, @floatFromInt(value)) / 127.5 - 1;
    }
};
