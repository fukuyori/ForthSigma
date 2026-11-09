//! Konami's SCC for SCC-SOUND: five voices, each playing a wave of 32 signed samples
//! from its instrument (SCC-WAVE), with the instruments' ADSR.
//!
//! The behavior follows the description in docs/SOUND_RESEARCH.md; no emulator's code
//! is used. A note's pitch is rounded to the chip's 12-bit period, frequency
//! 3579545 / (32 × (period + 1)), and the volume to its 16 steps. The samples are
//! played as steps, as on the chip. Unlike the first SCC, whose voices 4 and 5 share
//! one wave, every voice has its own (as on the SCC+).

const std = @import("std");
const parts = @import("sound_parts.zig");

/// The MSX's clock, which the SCC counts.
pub const clock: u32 = 3_579_545;

/// The chip's voices, which set its level in the mix; `Scc.voices` has a place for every
/// voice of PLAY.
pub const voice_count = 5;

/// The period register for a note.
pub fn periodRegister(note: u8) u32 {
    return parts.chipPeriod(note, clock, 32, 1, 4095);
}

const Voice = struct {
    phase: f32 = 0,
    increment: f32 = 0,
    table: [32]f32 = @splat(0),
    /// MML's V, 0 to 15.
    volume: f32 = 0,
    adsr: parts.Adsr = .{},
};

pub const Scc = struct {
    sample_rate: u32,
    voices: [parts.voice_slots]Voice = @splat(.{}),

    pub fn init(sample_rate: u32) Scc {
        return .{ .sample_rate = sample_rate };
    }

    /// `volume` is 0 to 15.
    pub fn noteOn(self: *Scc, v: usize, note: u8, volume: u8, instrument: parts.Instrument) void {
        const voice = &self.voices[v];
        const period = periodRegister(note);
        const frequency = @as(f32, @floatFromInt(clock)) / (32.0 * @as(f32, @floatFromInt(period + 1)));
        voice.increment = frequency / @as(f32, @floatFromInt(self.sample_rate));
        for (&voice.table, instrument.table()) |*value, sample_value| value.* = @as(f32, @floatFromInt(sample_value)) / 128.0;
        voice.volume = @floatFromInt(@min(volume, 15));
        voice.adsr.start(instrument, self.sample_rate);
    }

    pub fn noteOff(self: *Scc, v: usize) void {
        self.voices[v].adsr.stop();
    }

    /// The next sample, about -1 to 1.
    pub fn sample(self: *Scc) f32 {
        var sum: f32 = 0;
        for (&self.voices) |*voice| {
            // The chip's 4-bit volume: V by the envelope, rounded to its steps.
            const volume = @round(voice.volume * voice.adsr.next());
            const step: usize = @intFromFloat(voice.phase * 32);
            sum += voice.table[@min(step, 31)] * volume / 15.0;
            voice.phase += voice.increment;
            if (voice.phase >= 1) voice.phase -= 1;
        }
        return sum / voice_count;
    }
};
