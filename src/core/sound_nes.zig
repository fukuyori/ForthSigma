//! The NES's sound (the 2A03's APU, NTSC) for NES-SOUND: two pulse voices, a triangle,
//! and a noise, made of the common parts (sound_parts.zig) at the output's rate.
//!
//! The behavior follows the NESdev Wiki's APU pages (see docs/SOUND_RESEARCH.md); no
//! emulator's code is used. A note's pitch is rounded to the chip's 11-bit timers, the
//! pulse's duty to the four the chip has, and the volume to its 16 steps, so the voices
//! keep the chip's tuning and its coarse fades. The voices are mixed with the APU's
//! formulas, which are not linear. What the chip does on its own (the sweep, the length
//! counter, the hardware envelope) and the DPCM are left out: the instruments' ADSR does
//! the fading.

const std = @import("std");
const parts = @import("sound_parts.zig");

/// The CPU's clock on an NTSC NES, which the APU's timers count.
pub const cpu_clock: u32 = 1_789_773;

/// The noise's periods in CPU cycles (NTSC), for the 16 values of its register.
pub const noise_periods = [16]u16{ 4, 8, 16, 32, 64, 96, 128, 160, 202, 254, 380, 508, 762, 1016, 2034, 4068 };

/// The triangle's 32 steps.
const triangle_steps = blk: {
    var steps: [32]u8 = undefined;
    for (0..16) |i| {
        steps[i] = 15 - i;
        steps[16 + i] = i;
    }
    break :blk steps;
};

/// The chip's voices; `Nes.voices` has a place for every voice of PLAY.
pub const voice_count = 4;

/// What a voice plays.
pub const Role = enum { none, pulse, triangle, noise };

/// The note of the lowest noise (O3's C); each semitone up to O4's D# chooses the next
/// shorter period.
pub const lowest_noise_note = 36;

/// The noise period's register for a note: 15 (the longest period) at O3's C down to 0
/// at O4's D#; the notes below and above take the ends.
pub fn noiseIndex(note: u8) usize {
    const steps = std.math.clamp(@as(i32, note) - lowest_noise_note, 0, noise_periods.len - 1);
    return noise_periods.len - 1 - @as(usize, @intCast(steps));
}

const Voice = struct {
    on: bool = false,
    role: Role = .none,
    /// The role a voice of the chip itself always has, or none for the others, whose
    /// instrument's wave chooses.
    fixed: Role = .none,
    /// The phase's step a sample, or for the noise the CPU cycles between shifts.
    increment: f32 = 0,
    duty: f32 = 0.5,
    /// MML's V, 0 to 15.
    volume: f32 = 0,
    adsr: parts.Adsr = .{},
    pulse: parts.Pulse = .{},
    phase: f32 = 0,
    /// Muted, as the chip mutes a pulse whose timer is below 8.
    muted: bool = false,
    /// 15 bits; the input is bit 0 XOR bit 1, the output (inverted) bit 0.
    lfsr: u16 = 1,
    noise_period: u32 = noise_periods[0],
    /// CPU cycles towards the next shift, in units of 1 / sample_rate.
    noise_fraction: u64 = 0,
    /// The triangle's output while it is stopped: it keeps its step, as the chip does.
    triangle_level: f32 = 0,
};

pub const Nes = struct {
    sample_rate: u32,
    voices: [parts.voice_slots]Voice = @splat(.{}),

    pub fn init(sample_rate: u32) Nes {
        var nes: Nes = .{ .sample_rate = sample_rate };
        nes.place(0);
        return nes;
    }

    /// The chip's four voices from `first`: two pulses, the triangle (which starts on
    /// its top step), and the noise. Without `first`, no voice is the chip's own.
    pub fn place(self: *Nes, first: ?usize) void {
        for (&self.voices) |*voice| {
            voice.role = .none;
            voice.fixed = .none;
            voice.triangle_level = 0;
        }
        const at = first orelse return;
        for ([voice_count]Role{ .pulse, .pulse, .triangle, .noise }, at..) |role, v| {
            if (v >= parts.voice_slots) break;
            self.voices[v].role = role;
            self.voices[v].fixed = role;
            if (role == .triangle) self.voices[v].triangle_level = 15;
        }
    }

    /// A note on a voice: one of the chip's own keeps its role, and for any other the
    /// instrument's wave chooses. `volume` is 0 to 15.
    pub fn noteOn(self: *Nes, v: usize, note: u8, volume: u8, instrument: parts.Instrument) void {
        const fixed = self.voices[v].fixed;
        self.start(v, if (fixed != .none) fixed else roleOf(instrument.wave), note, volume, instrument);
    }

    /// A note whose role the instrument's wave chooses, on any voice (STYLE).
    pub fn noteOnWave(self: *Nes, v: usize, note: u8, volume: u8, instrument: parts.Instrument) void {
        self.start(v, roleOf(instrument.wave), note, volume, instrument);
    }

    /// The wave the chip has nearest to the instrument's.
    fn roleOf(wave: parts.Wave) Role {
        return switch (wave) {
            .square, .pulse, .saw => .pulse,
            .triangle => .triangle,
            .noise => .noise,
        };
    }

    fn start(self: *Nes, v: usize, role: Role, note: u8, volume: u8, instrument: parts.Instrument) void {
        const voice = &self.voices[v];
        const rate: f32 = @floatFromInt(self.sample_rate);
        voice.on = true;
        voice.role = role;
        voice.volume = @floatFromInt(@min(volume, 15));
        switch (role) {
            .none => unreachable,
            .pulse => {
                const timer = parts.chipPeriod(note, cpu_clock, 16, 1, 2047);
                voice.muted = timer < 8;
                voice.increment = @as(f32, @floatFromInt(cpu_clock)) / (16.0 * @as(f32, @floatFromInt(timer + 1))) / rate;
                voice.duty = nearestDuty(instrument);
            },
            .triangle => {
                const timer = parts.chipPeriod(note, cpu_clock, 32, 1, 2047);
                voice.increment = @as(f32, @floatFromInt(cpu_clock)) / (32.0 * @as(f32, @floatFromInt(timer + 1))) / rate;
            },
            .noise => voice.noise_period = noise_periods[noiseIndex(note)],
        }
        voice.adsr.start(instrument, self.sample_rate);
    }

    pub fn noteOff(self: *Nes, v: usize) void {
        self.voices[v].on = false;
        self.voices[v].adsr.stop();
    }

    /// The four duties of the chip, the nearest to the instrument's (SQUARE is 50%).
    fn nearestDuty(instrument: parts.Instrument) f32 {
        if (instrument.wave == .square) return 0.5;
        const duty = @min(instrument.duty, 100);
        if (duty < 19) return 0.125;
        if (duty < 38) return 0.25;
        if (duty < 63) return 0.5;
        return 0.75;
    }

    /// A voice's 4-bit volume now: MML's V by the envelope, rounded to the chip's steps.
    fn level(voice: *Voice) f32 {
        return @round(voice.volume * voice.adsr.next());
    }

    /// The next sample, 0 to 1.
    pub fn sample(self: *Nes) f32 {
        var pulses: f32 = 0;
        var triangle: f32 = 0;
        var noise: f32 = 0;
        for (&self.voices) |*voice| {
            switch (voice.role) {
                .none => {},
                .pulse => {
                    const volume = level(voice);
                    const wave = voice.pulse.next(voice.increment, voice.duty);
                    if (!voice.muted) pulses += wave * volume;
                },
                .triangle => triangle += triangleSample(voice),
                .noise => noise += self.noiseSample(voice),
            }
        }
        // The APU's mixer; at most about 0.49, so twice that is the sample.
        const pulse_out: f32 = if (pulses <= 0) 0 else 95.88 / (8128.0 / pulses + 100.0);
        const tnd_in = triangle / 8227.0 + noise / 12241.0;
        const tnd_out: f32 = if (tnd_in <= 0) 0 else 159.79 / (1.0 / tnd_in + 100.0);
        return (pulse_out + tnd_out) * 2;
    }

    /// The triangle has no volume: it plays while the note is on, and keeps its step when
    /// it stops (a constant level, which the output's high-pass takes away).
    fn triangleSample(voice: *Voice) f32 {
        if (voice.on and voice.volume > 0) {
            voice.phase += voice.increment;
            if (voice.phase >= 1) voice.phase -= 1;
            const step: usize = @intFromFloat(voice.phase * 32);
            voice.triangle_level = @floatFromInt(triangle_steps[@min(step, 31)]);
        }
        return voice.triangle_level;
    }

    /// The noise: the mean of its output over the shifts this sample covers.
    fn noiseSample(self: *const Nes, voice: *Voice) f32 {
        const volume = level(voice);
        const unit = @as(u64, voice.noise_period) * self.sample_rate;
        voice.noise_fraction += cpu_clock;
        var sum: f32 = 0;
        var count: f32 = 0;
        while (voice.noise_fraction >= unit) {
            voice.noise_fraction -= unit;
            const bit = (voice.lfsr ^ (voice.lfsr >> 1)) & 1;
            voice.lfsr = (voice.lfsr >> 1) | (bit << 14);
            sum += if (voice.lfsr & 1 == 0) 1 else 0;
            count += 1;
        }
        const high: f32 = if (count > 0) sum / count else if (voice.lfsr & 1 == 0) 1 else 0;
        return high * volume;
    }
};
