//! The Amiga's sound (Paula, on a PAL machine) for AMIGA-SOUND: four voices that play
//! samples, voices 1 and 4 on the left and 2 and 3 on the right, through the A500's
//! fixed low-pass and the "LED" filter that AMIGA-FILTER turns on.
//!
//! The behavior follows the descriptions in docs/SOUND_RESEARCH.md; no emulator's code
//! is used. A note's rate is rounded to Paula's period (clock / period samples a second,
//! the period at least 124), the volume to its 65 steps (0 to 64), and each sample value
//! is held until the next, as the chip does. An instrument without a sample plays its
//! wave (as the SCC does) as a loop of 32 samples.

const std = @import("std");
const parts = @import("sound_parts.zig");
const pcm = @import("sound_pcm.zig");

/// Paula's clock on a PAL Amiga.
pub const clock: u32 = 3_546_895;
/// The shortest period the chip's DMA keeps up with.
pub const min_period = 124;

pub const voice_count = 4;

/// The note a sample plays at its recorded rate: O4's C.
pub const sample_note = 48;

/// Paula's period for playing `frequency` samples a second.
pub fn period(frequency: f64) u32 {
    const exact = @as(f64, @floatFromInt(clock)) / frequency;
    return @intFromFloat(std.math.clamp(@round(exact), min_period, 65535));
}

const Voice = struct {
    player: pcm.Player = .{},
    /// The instrument's wave, when it has no sample.
    table: [32]i16 = @splat(0),
    uses_table: bool = false,
    /// MML's V as Paula's volume, 0 to 64.
    volume: f32 = 0,
    adsr: parts.Adsr = .{},
    /// Whether the voice is on the left.
    left: bool = false,
};

/// A two-pole low-pass (a biquad), for the LED filter.
const LowPass = struct {
    b0: f32 = 1,
    b1: f32 = 0,
    b2: f32 = 0,
    a1: f32 = 0,
    a2: f32 = 0,
    x1: f32 = 0,
    x2: f32 = 0,
    y1: f32 = 0,
    y2: f32 = 0,

    fn init(cutoff: f32, q: f32, sample_rate: u32) LowPass {
        const w = 2 * std.math.pi * cutoff / @as(f32, @floatFromInt(sample_rate));
        const alpha = @sin(w) / (2 * q);
        const cos = @cos(w);
        const a0 = 1 + alpha;
        return .{
            .b0 = (1 - cos) / 2 / a0,
            .b1 = (1 - cos) / a0,
            .b2 = (1 - cos) / 2 / a0,
            .a1 = -2 * cos / a0,
            .a2 = (1 - alpha) / a0,
        };
    }

    fn process(self: *LowPass, x: f32) f32 {
        const y = self.b0 * x + self.b1 * self.x1 + self.b2 * self.x2 - self.a1 * self.y1 - self.a2 * self.y2;
        self.x2 = self.x1;
        self.x1 = x;
        self.y2 = self.y1;
        self.y1 = y;
        return y;
    }
};

/// The A500's output filters, for the left and the right: the fixed one-pole low-pass
/// at about 4.9 kHz, and the LED filter (Butterworth, about 3.3 kHz) when it is on.
pub const Filters = struct {
    fixed_factor: f32,
    fixed: [2]f32 = .{ 0, 0 },
    led: [2]LowPass,

    pub fn init(sample_rate: u32) Filters {
        const rate: f32 = @floatFromInt(sample_rate);
        const filter = LowPass.init(3275, 0.7071, sample_rate);
        return .{ .fixed_factor = 1 - @exp(-2 * std.math.pi * 4900 / rate), .led = .{ filter, filter } };
    }

    pub fn process(self: *Filters, sides: [2]f32, led: bool) [2]f32 {
        var out = sides;
        for (&out, 0..) |*side, i| {
            self.fixed[i] += self.fixed_factor * (side.* - self.fixed[i]);
            side.* = if (led) self.led[i].process(self.fixed[i]) else self.fixed[i];
        }
        return out;
    }
};

pub const Amiga = struct {
    sample_rate: u32,
    voices: [parts.voice_slots]Voice = @splat(.{}),
    filters: Filters,

    pub fn init(sample_rate: u32) Amiga {
        var amiga: Amiga = .{ .sample_rate = sample_rate, .filters = Filters.init(sample_rate) };
        amiga.place(0);
        return amiga;
    }

    /// Sets the sides, left, right, right, left from voice `first` (from voice 0 when
    /// the chip has no voices of its own), and so on round.
    pub fn place(self: *Amiga, first: ?usize) void {
        const start = first orelse 0;
        for (&self.voices, 0..) |*voice, v| {
            const position = (v + parts.voice_slots * 4 - start) % voice_count;
            voice.left = position == 0 or position == 3;
        }
    }

    /// `volume` is MML's V, 0 to 15.
    pub fn noteOn(self: *Amiga, v: usize, note: u8, volume: u8, instrument: parts.Instrument, samples: *const [pcm.sample_count]pcm.Sample) void {
        const voice = &self.voices[v];
        const ratio = parts.noteFrequency(note) / parts.noteFrequency(sample_note);
        voice.volume = @round(@as(f32, @floatFromInt(@min(volume, 15))) * 64.0 / 15.0);
        const rate: f64 = @floatFromInt(self.sample_rate);
        if (instrument.sample) |n| {
            const recorded = samples[n];
            if (recorded.length > 0) {
                const played = @as(f64, @floatFromInt(clock)) / @as(f64, @floatFromInt(period(@as(f64, @floatFromInt(recorded.rate)) * ratio)));
                voice.uses_table = false;
                voice.player.start(recorded, played / rate);
                voice.adsr.start(instrument, self.sample_rate);
                return;
            }
        }
        // The wave as a loop, the note's frequency times a second round. A high note
        // would need a period below Paula's shortest: as trackers do, the wave is then
        // played with every second sample (16, 8, ... of them).
        const frequency = parts.noteFrequency(note);
        var length: u32 = 32;
        while (length > 2 and @as(f64, @floatFromInt(clock)) / (frequency * @as(f64, @floatFromInt(length))) < min_period) length /= 2;
        const wave = instrument.table();
        for (voice.table[0..length], 0..) |*value, i| value.* = @as(i16, wave[i * (32 / length)]) * 256;
        const played = @as(f64, @floatFromInt(clock)) / @as(f64, @floatFromInt(period(frequency * @as(f64, @floatFromInt(length)))));
        voice.uses_table = true;
        voice.player.start(.{ .length = length, .rate = 0, .loop_start = 0, .loop_end = length }, played / rate);
        voice.adsr.start(instrument, self.sample_rate);
    }

    pub fn noteOff(self: *Amiga, v: usize) void {
        self.voices[v].adsr.stop();
    }

    /// The next left and right samples, about -1 to 1, with the LED filter when `led`.
    pub fn sample(self: *Amiga, pool: []const i16, led: bool) [2]f32 {
        var sides: [2]f32 = .{ 0, 0 };
        for (&self.voices) |*voice| {
            const data: []const i16 = if (voice.uses_table) &voice.table else pool;
            const value = voice.player.next(data) * @round(voice.volume * voice.adsr.next()) / 64.0;
            sides[if (voice.left) 0 else 1] += value / 2;
        }
        return self.filters.process(sides, led);
    }
};
