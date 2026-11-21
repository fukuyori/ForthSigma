//! The effects on all the voices together (tque 1198, 3.7 of
//! docs/SOUND_CORE_DESIGN_STUDY.md): the reverb (a delay with feedback and FIR
//! coefficients), a fixed filter, the bass and treble, and the volume. They take
//! effect at once and stay over BEEP and stops, as the instruments do.

const std = @import("std");

/// The longest delay: 16384 frames, about 341 ms at 48 kHz.
pub const max_delay_frames = 16384;

/// The most REVERB-FIR coefficients.
pub const max_fir = 8;

pub const FilterMode = enum(u8) { none = 0, low_pass = 1, high_pass = 3 };

/// A two-pole state-variable filter of Q 0.707 for both sides.
const Svf = struct {
    a1: f32 = 0,
    a2: f32 = 0,
    a3: f32 = 0,
    ic1: [2]f32 = .{ 0, 0 },
    ic2: [2]f32 = .{ 0, 0 },

    fn set(self: *Svf, hz: f32, rate: f32) void {
        const cutoff = std.math.clamp(hz, @min(10, rate * 0.45), rate * 0.45);
        const g = std.math.tan(std.math.pi * cutoff / rate);
        const k: f32 = std.math.sqrt2;
        self.a1 = 1.0 / (1.0 + g * (g + k));
        self.a2 = g * self.a1;
        self.a3 = g * self.a2;
        self.ic1 = .{ 0, 0 };
        self.ic2 = .{ 0, 0 };
    }

    /// The low-pass and the high-pass of x on `side`.
    fn run(self: *Svf, side: usize, x: f32) [2]f32 {
        const v3 = x - self.ic2[side];
        const v1 = self.a1 * self.ic1[side] + self.a2 * v3;
        const v2 = self.ic2[side] + self.a2 * self.ic1[side] + self.a3 * v3;
        self.ic1[side] = 2 * v1 - self.ic1[side];
        self.ic2[side] = 2 * v2 - self.ic2[side];
        return .{ v2, x - std.math.sqrt2 * v1 - v2 };
    }
};

/// A one-pole low-pass for both sides, for the bass and the treble, in the
/// topology-preserving form: 1 at 0 Hz and 0 at half the rate, so that x minus it is a
/// high-pass of exactly 1 there.
const OnePole = struct {
    g: f32 = 0,
    s: [2]f32 = .{ 0, 0 },

    fn set(self: *OnePole, hz: f32, rate: f32) void {
        const t = std.math.tan(std.math.pi * std.math.clamp(hz, 1, rate * 0.45) / rate);
        self.g = t / (1 + t);
    }

    fn run(self: *OnePole, side: usize, x: f32) f32 {
        const v = (x - self.s[side]) * self.g;
        const low = v + self.s[side];
        self.s[side] = low + v;
        return low;
    }
};

pub const Master = struct {
    rate: f32,
    delay: [max_delay_frames][2]f32 = @splat(.{ 0, 0 }),
    delay_frames: u32 = 0,
    position: u32 = 0,
    feedback: f32 = 0,
    reverb_volume: f32 = 0,
    fir: [max_fir]f32 = @splat(0),
    fir_count: u8 = 0,
    history: [max_fir][2]f32 = @splat(.{ 0, 0 }),
    filter: FilterMode = .none,
    svf: Svf = .{},
    bass_gain: f32 = 1,
    treble_gain: f32 = 1,
    bass: OnePole = .{},
    treble: OnePole = .{},
    volume: f32 = 1,
    /// OUTPUT-BITS: the bits (0 for none) and the rate (0 for every frame) of the output.
    output_bits: u8 = 0,
    output_rate: u32 = 0,
    hold_phase: f32 = 1,
    held: [2]f32 = .{ 0, 0 },

    pub fn init(sample_rate: u32) Master {
        var m: Master = .{ .rate = @floatFromInt(@max(sample_rate, 1)) };
        m.bass.set(200, m.rate);
        m.treble.set(4000, m.rate);
        return m;
    }

    /// The delay frames `ms` takes at this rate, or null when it does not fit.
    pub fn delayFrames(self: *const Master, ms: u32) ?u32 {
        const frames = @round(@as(f64, @floatFromInt(ms)) * @as(f64, self.rate) / 1000.0);
        if (frames > max_delay_frames) return null;
        return @intFromFloat(frames);
    }

    /// REVERB: the delay, the feedback (-65535 to 65535), and the volume (0 to 65535).
    /// A volume of 0 turns the reverb off and empties it.
    pub fn setReverb(self: *Master, ms: u32, feedback: i32, volume: u16) void {
        const frames = self.delayFrames(ms) orelse max_delay_frames;
        if (frames != self.delay_frames or volume == 0) {
            self.delay = @splat(.{ 0, 0 });
            self.history = @splat(.{ 0, 0 });
            self.position = 0;
        }
        self.delay_frames = frames;
        self.feedback = @as(f32, @floatFromInt(feedback)) / 65535.0;
        self.reverb_volume = @as(f32, @floatFromInt(volume)) / 65535.0;
    }

    /// REVERB-FIR: coefficients with 128 as 1, or none.
    pub fn setFir(self: *Master, coefficients: []const i32) void {
        self.fir_count = @intCast(coefficients.len);
        for (coefficients, 0..) |c, i| self.fir[i] = @as(f32, @floatFromInt(c)) / 128.0;
        self.history = @splat(.{ 0, 0 });
    }

    pub fn setFilter(self: *Master, mode: FilterMode, hz: u32) void {
        self.filter = mode;
        self.svf.set(@floatFromInt(hz), self.rate);
    }

    /// TONE-CONTROL: decibels, -12 to 12, below about 200 Hz and above about 4 kHz.
    pub fn setTone(self: *Master, bass_db: i32, treble_db: i32) void {
        self.bass_gain = std.math.pow(f32, 10, @as(f32, @floatFromInt(bass_db)) / 20.0);
        self.treble_gain = std.math.pow(f32, 10, @as(f32, @floatFromInt(treble_db)) / 20.0);
    }

    pub fn setOutput(self: *Master, bits: u8, output_rate: u32) void {
        self.output_bits = bits;
        self.output_rate = output_rate;
        self.hold_phase = 1;
    }

    pub fn setVolume(self: *Master, ratio: u16) void {
        self.volume = @as(f32, @floatFromInt(ratio)) / 65535.0;
    }

    /// One frame: the voices' mix and what they send to the reverb.
    pub fn process(self: *Master, left: f32, right: f32, send_left: f32, send_right: f32) [2]f32 {
        var out: [2]f32 = .{ left, right };
        if (self.reverb_volume > 0 and self.delay_frames > 0) {
            const sends: [2]f32 = .{ send_left, send_right };
            const delayed = self.delay[self.position];
            // The FIR is on the feedback (3.7 of the study): what is heard is the delay.
            var echo: [2]f32 = delayed;
            if (self.fir_count > 0) {
                var i: usize = self.fir_count - 1;
                while (i > 0) : (i -= 1) self.history[i] = self.history[i - 1];
                self.history[0] = delayed;
                for (0..2) |side| {
                    var sum: f32 = 0;
                    for (0..self.fir_count) |k| sum += self.fir[k] * self.history[k][side];
                    echo[side] = sum;
                }
            }
            for (0..2) |side| {
                out[side] += delayed[side] * self.reverb_volume;
                // Bounded, so that a feedback of 1 or more cannot grow without end.
                self.delay[self.position][side] = std.math.clamp(sends[side] + echo[side] * self.feedback, -4, 4);
            }
            self.position += 1;
            if (self.position >= self.delay_frames) self.position = 0;
        }
        for (0..2) |side| {
            var x = out[side];
            switch (self.filter) {
                .none => {},
                .low_pass => x = self.svf.run(side, x)[0],
                .high_pass => x = self.svf.run(side, x)[1],
            }
            // The filters run always, so that turning the control on starts from now.
            const low = self.bass.run(side, x);
            const high = x - self.treble.run(side, x);
            x += (self.bass_gain - 1) * low + (self.treble_gain - 1) * high;
            out[side] = x * self.volume;
        }
        return out;
    }

    /// OUTPUT-BITS on the final output (-1 to 1, the full scale of the 16-bit output):
    /// held at its own rate and rounded to its bits as a signed number, -2^(bits-1) to
    /// 2^(bits-1) - 1 steps.
    pub fn finish(self: *Master, sides: [2]f32) [2]f32 {
        if (self.output_bits == 0 and self.output_rate == 0) return sides;
        const step: f32 = if (self.output_rate == 0) 1 else @as(f32, @floatFromInt(self.output_rate)) / self.rate;
        defer self.hold_phase += step;
        if (self.hold_phase >= 1) {
            self.hold_phase -= @floor(self.hold_phase);
            for (0..2) |side| {
                var x = std.math.clamp(sides[side], -1, 1);
                if (self.output_bits > 0) {
                    const levels = std.math.pow(f32, 2, @as(f32, @floatFromInt(self.output_bits - 1)));
                    x = std.math.clamp(@round(x * levels), -levels, levels - 1) / levels;
                }
                self.held[side] = x;
            }
        }
        return self.held;
    }
};
