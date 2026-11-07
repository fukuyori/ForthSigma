//! The parts the chips other than the PSG are made of: instruments, the ADSR envelope,
//! a pulse oscillator with its steps band-limited, and the pitch of a note.
//!
//! The chips' settings (sound_nes.zig and the others) use these parts with their own
//! ranges, clocks, and mixers. Everything works at the output's sample rate and gives
//! the same samples for the same input.

const std = @import("std");

/// What an instrument's oscillator plays, on a chip that lets it choose (C64); a chip
/// with fixed waves takes what fits (the NES's pulse voices take the duty).
pub const Wave = enum(u8) { square, pulse, triangle, saw, noise };

/// An instrument (INSTRUMENT and the words after it; MML's `@` chooses one).
pub const Instrument = struct {
    wave: Wave = .square,
    /// The pulse's high part, 0 to 100 percent (PULSE).
    duty: u8 = 50,
    /// ADSR as on the C64's SID: the attack, decay, and release times by the SID's
    /// table, and the sustain level, each 0 to 15.
    attack: u8 = 0,
    decay: u8 = 0,
    sustain: u8 = 15,
    release: u8 = 0,
};

/// The SID's attack times in milliseconds for the values 0 to 15; decay and release
/// take three times as long.
const attack_ms = [16]f32{ 2, 8, 16, 24, 38, 56, 68, 80, 100, 250, 500, 800, 1000, 3000, 5000, 8000 };

/// An ADSR envelope, from 0 to 1, a sample at a time: a straight attack, then a decay
/// and a release that slow down as they go (to 1% of their way in their time, near
/// enough to the SID's curve).
pub const Adsr = struct {
    stage: enum { idle, attack, decay, sustain, release } = .idle,
    level: f32 = 0,
    attack_step: f32 = 1,
    decay_factor: f32 = 0,
    release_factor: f32 = 0,
    sustain: f32 = 1,

    pub fn start(self: *Adsr, instrument: Instrument, sample_rate: u32) void {
        const rate: f32 = @floatFromInt(sample_rate);
        self.attack_step = 1.0 / (attack_ms[instrument.attack & 15] / 1000.0 * rate);
        self.decay_factor = factor(3 * attack_ms[instrument.decay & 15], rate);
        self.release_factor = factor(3 * attack_ms[instrument.release & 15], rate);
        self.sustain = @as(f32, @floatFromInt(instrument.sustain & 15)) / 15.0;
        // The attack goes on from the level the last note left (as the SID's does).
        self.stage = .attack;
    }

    pub fn stop(self: *Adsr) void {
        if (self.stage != .idle) self.stage = .release;
    }

    /// The factor that takes a level 99% of its way in `ms` milliseconds.
    fn factor(ms: f32, rate: f32) f32 {
        return @exp(@log(@as(f32, 0.01)) / (ms / 1000.0 * rate));
    }

    pub fn next(self: *Adsr) f32 {
        switch (self.stage) {
            .idle => {},
            .attack => {
                self.level += self.attack_step;
                if (self.level >= 1) {
                    self.level = 1;
                    self.stage = .decay;
                }
            },
            .decay => {
                self.level = self.sustain + (self.level - self.sustain) * self.decay_factor;
                if (self.level - self.sustain < 0.001) {
                    self.level = self.sustain;
                    self.stage = .sustain;
                }
            },
            .sustain => {},
            .release => {
                self.level *= self.release_factor;
                if (self.level < 0.0001) {
                    self.level = 0;
                    self.stage = .idle;
                }
            },
        }
        return self.level;
    }
};

/// The correction to a step of height 2 at phase 0 for an oscillator moving `increment`
/// of its cycle a sample (PolyBLEP): it spreads the step over two samples, which keeps
/// the high harmonics from folding back as audible tones.
pub fn polyBlep(phase: f32, increment: f32) f32 {
    if (phase < increment) {
        const x = phase / increment;
        return x + x - x * x - 1;
    }
    if (phase > 1 - increment) {
        const x = (phase - 1) / increment;
        return x * x + x + x + 1;
    }
    return 0;
}

/// A pulse from 0 to 1, high for `duty` (0 to 1) of each cycle, with its two steps
/// band-limited.
pub const Pulse = struct {
    phase: f32 = 0,

    pub fn next(self: *Pulse, increment: f32, duty: f32) f32 {
        const phase = self.phase;
        var value: f32 = if (phase < duty) 1 else 0;
        value += 0.5 * polyBlep(phase, increment);
        var fall = phase - duty;
        if (fall < 0) fall += 1;
        value -= 0.5 * polyBlep(fall, increment);
        self.phase += increment;
        if (self.phase >= 1) self.phase -= 1;
        return value;
    }
};

/// The 12 semitones from A up, as ratios of frequency.
const semitone_ratios = [12]f64{ 1.0, 1.0594630943592953, 1.122462048309373, 1.189207115002721, 1.2599210498948732, 1.3348398541700344, 1.4142135623730951, 1.4983070768766815, 1.5874010519681994, 1.681792830507429, 1.7817974362806785, 1.8877486253633868 };

/// The frequency of a note (octave × 12 + semitone, as sound_mml's Event.note) in equal
/// temperament with O4's A at 440 Hz.
pub fn noteFrequency(note: u8) f64 {
    const distance = @as(i32, note) - 57;
    var frequency = 440.0 * semitone_ratios[@intCast(@mod(distance, 12))];
    var octaves = @divFloor(distance, 12);
    while (octaves > 0) : (octaves -= 1) frequency *= 2;
    while (octaves < 0) : (octaves += 1) frequency /= 2;
    return frequency;
}

/// The period register a chip whose frequency is clock / (divider × (period + offset))
/// needs for a note, rounded, within 0 to `max`.
pub fn chipPeriod(note: u8, clock: u32, divider: u32, offset: u32, max: u32) u32 {
    const exact = @as(f64, @floatFromInt(clock)) / (@as(f64, @floatFromInt(divider)) * noteFrequency(note));
    const rounded: i64 = @intFromFloat(@round(exact));
    return @intCast(std.math.clamp(rounded - offset, 0, max));
}
