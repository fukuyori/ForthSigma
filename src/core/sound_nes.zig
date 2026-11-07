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

pub const voice_count = 4;

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
};

pub const Nes = struct {
    sample_rate: u32,
    voices: [voice_count]Voice = @splat(.{}),
    /// 15 bits; the input is bit 0 XOR bit 1, the output (inverted) bit 0.
    lfsr: u16 = 1,
    noise_period: u32 = noise_periods[0],
    /// CPU cycles towards the next shift, in units of 1 / sample_rate.
    noise_fraction: u64 = 0,
    /// The triangle's output while it is stopped: it keeps its step, as the chip does.
    triangle_level: f32 = 15,

    pub fn init(sample_rate: u32) Nes {
        return .{ .sample_rate = sample_rate };
    }

    /// Voice 0 and 1 are pulses, 2 the triangle, 3 the noise. `volume` is 0 to 15.
    pub fn noteOn(self: *Nes, v: usize, note: u8, volume: u8, instrument: parts.Instrument) void {
        const voice = &self.voices[v];
        const rate: f32 = @floatFromInt(self.sample_rate);
        voice.on = true;
        voice.volume = @floatFromInt(@min(volume, 15));
        switch (v) {
            0, 1 => {
                const timer = parts.chipPeriod(note, cpu_clock, 16, 1, 2047);
                voice.muted = timer < 8;
                voice.increment = @as(f32, @floatFromInt(cpu_clock)) / (16.0 * @as(f32, @floatFromInt(timer + 1))) / rate;
                voice.duty = nearestDuty(instrument);
            },
            2 => {
                const timer = parts.chipPeriod(note, cpu_clock, 32, 1, 2047);
                voice.increment = @as(f32, @floatFromInt(cpu_clock)) / (32.0 * @as(f32, @floatFromInt(timer + 1))) / rate;
            },
            else => self.noise_period = noise_periods[noiseIndex(note)],
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
        for (self.voices[0..2]) |*voice| {
            const volume = level(voice);
            const wave = voice.pulse.next(voice.increment, voice.duty);
            if (!voice.muted) pulses += wave * volume;
        }
        const triangle = self.triangleSample();
        const noise = self.noiseSample();
        // The APU's mixer; at most about 0.49, so twice that is the sample.
        const pulse_out: f32 = if (pulses <= 0) 0 else 95.88 / (8128.0 / pulses + 100.0);
        const tnd_in = triangle / 8227.0 + noise / 12241.0;
        const tnd_out: f32 = if (tnd_in <= 0) 0 else 159.79 / (1.0 / tnd_in + 100.0);
        return (pulse_out + tnd_out) * 2;
    }

    /// The triangle has no volume: it plays while the note is on, and keeps its step when
    /// it stops (a constant level, which the output's high-pass takes away).
    fn triangleSample(self: *Nes) f32 {
        const voice = &self.voices[2];
        if (voice.on and voice.volume > 0) {
            voice.phase += voice.increment;
            if (voice.phase >= 1) voice.phase -= 1;
            const step: usize = @intFromFloat(voice.phase * 32);
            self.triangle_level = @floatFromInt(triangle_steps[@min(step, 31)]);
        }
        return self.triangle_level;
    }

    /// The noise: the mean of its output over the shifts this sample covers.
    fn noiseSample(self: *Nes) f32 {
        const voice = &self.voices[3];
        const volume = level(voice);
        const unit = @as(u64, self.noise_period) * self.sample_rate;
        self.noise_fraction += cpu_clock;
        var sum: f32 = 0;
        var count: f32 = 0;
        while (self.noise_fraction >= unit) {
            self.noise_fraction -= unit;
            const bit = (self.lfsr ^ (self.lfsr >> 1)) & 1;
            self.lfsr = (self.lfsr >> 1) | (bit << 14);
            sum += if (self.lfsr & 1 == 0) 1 else 0;
            count += 1;
        }
        const high: f32 = if (count > 0) sum / count else if (self.lfsr & 1 == 0) 1 else 0;
        return high * volume;
    }
};
