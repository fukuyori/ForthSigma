//! The PSG of the MSX and the Atari ST: General Instrument's AY-3-8910 and Yamaha's
//! YM2149, by their registers. Three square-wave tones, one noise, and one envelope that
//! the channels share.
//!
//! The behavior follows the data sheets and the MSX Technical Handbook (see
//! docs/SOUND_RESEARCH.md); no emulator's code is used. The chip is stepped at 1/8 of its
//! clock: a tone's output flips every `period` steps (clock / (16 × period) Hz), the
//! noise and the envelope advance every second step and every `period` steps, so a whole
//! envelope cycle is clock / (256 × period) on both chips (the AY's 16 levels last two
//! of the YM's 32 steps each). Each sample is the mean of the steps it covers, which
//! keeps the highest tones from folding back as audible noise.

pub const Model = enum { ay8910, ym2149 };

/// The MSX's clock (1.7897725 MHz) and the Atari ST's (2 MHz).
pub const msx_clock: u32 = 1_789_773;
pub const atari_st_clock: u32 = 2_000_000;

/// The AY's 16 volume levels, from Matthew Westcott's measurement of an AY-3-8910 (2001,
/// placed in the public domain): 1.147 V at level 0 up to 2.58 V at level 15, here less
/// level 0's voltage and scaled to 1.
const ay_levels = blk: {
    const volts = [16]f32{ 1.147, 1.162, 1.169, 1.178, 1.192, 1.213, 1.238, 1.299, 1.336, 1.457, 1.573, 1.707, 1.882, 2.06, 2.32, 2.58 };
    var levels: [16]f32 = undefined;
    for (volts, 0..) |v, i| levels[i] = (v - volts[0]) / (volts[15] - volts[0]);
    break :blk levels;
};

/// The YM's 32 levels: 1.5 dB apart, as the data sheet's figure shows (the fixed
/// volumes are every second level, 3 dB apart), and 0 at the bottom.
const ym_levels = blk: {
    @setEvalBranchQuota(10_000);
    var levels: [32]f32 = undefined;
    levels[0] = 0;
    for (1..32) |i| levels[i] = pow10(-1.5 * @as(f32, @floatFromInt(31 - i)) / 20.0);
    break :blk levels;
};

/// 10^x at compile time (exp of x ln 10, by its series), since @exp of a comptime float
/// is not available on every target.
fn pow10(x: f32) f32 {
    const y: f64 = @as(f64, x) * 2.302585092994046;
    var term: f64 = 1;
    var sum: f64 = 1;
    var n: f64 = 1;
    while (n < 60) : (n += 1) {
        term *= y / n;
        sum += term;
    }
    return @floatCast(sum);
}

pub const Psg = struct {
    model: Model,
    clock: u32,
    sample_rate: u32,
    regs: [16]u8 = @splat(0),
    tone_count: [3]u16 = .{ 0, 0, 0 },
    tone_high: [3]bool = .{ false, false, false },
    noise_count: u8 = 0,
    noise_half: bool = false,
    /// 17 bits; the input is bit 0 XOR bit 3, the output bit 0.
    lfsr: u32 = 1,
    env_count: u16 = 0,
    /// 31 down to 0; the level is this XOR `env_attack`.
    env_step: u8 = 31,
    env_attack: u8 = 0,
    env_hold: bool = true,
    env_alternate: bool = false,
    env_holding: bool = true,
    /// Steps (clock / 8) per sample, in units of 1 / (8 × sample_rate).
    fraction: u64 = 0,
    last: f32 = 0,

    pub fn init(model: Model, clock: u32, sample_rate: u32) Psg {
        var psg: Psg = .{ .model = model, .clock = clock, .sample_rate = sample_rate };
        psg.reset();
        return psg;
    }

    /// All registers 0 (tones and noise on, volumes 0), the noise and the envelope from
    /// their start.
    pub fn reset(self: *Psg) void {
        const model = self.model;
        const clock = self.clock;
        const rate = self.sample_rate;
        self.* = .{ .model = model, .clock = clock, .sample_rate = rate };
    }

    pub fn write(self: *Psg, reg: u8, value: u8) void {
        if (reg > 15) return;
        // The AY keeps only the bits each register has; the YM keeps all 8 (and reads
        // them back), but uses the same bits.
        const masks = [16]u8{ 0xff, 0x0f, 0xff, 0x0f, 0xff, 0x0f, 0x1f, 0xff, 0x1f, 0x1f, 0x1f, 0xff, 0xff, 0x0f, 0xff, 0xff };
        self.regs[reg] = if (self.model == .ay8910) value & masks[reg] else value;
        if (reg == 13) self.startEnvelope();
    }

    pub fn read(self: *const Psg, reg: u8) u8 {
        return if (reg > 15) 0xff else self.regs[reg];
    }

    /// Writing R13 starts the envelope again from its first step.
    fn startEnvelope(self: *Psg) void {
        const shape = self.regs[13] & 0x0f;
        self.env_attack = if (shape & 4 != 0) 0x1f else 0;
        if (shape & 8 == 0) {
            // Shapes 0 to 7: one ramp, then 0.
            self.env_hold = true;
            self.env_alternate = self.env_attack != 0;
        } else {
            self.env_hold = shape & 1 != 0;
            self.env_alternate = shape & 2 != 0;
        }
        self.env_step = 31;
        self.env_count = 0;
        self.env_holding = false;
    }

    fn tonePeriod(self: *const Psg, channel: usize) u16 {
        const period = @as(u16, self.regs[channel * 2 + 1] & 0x0f) << 8 | self.regs[channel * 2];
        return if (period == 0) 1 else period;
    }

    /// One step of 8 clocks.
    pub fn step(self: *Psg) void {
        for (0..3) |c| {
            self.tone_count[c] += 1;
            if (self.tone_count[c] >= self.tonePeriod(c)) {
                self.tone_count[c] = 0;
                self.tone_high[c] = !self.tone_high[c];
            }
        }
        self.noise_half = !self.noise_half;
        if (self.noise_half) {
            const period = @max(self.regs[6] & 0x1f, 1);
            self.noise_count += 1;
            if (self.noise_count >= period) {
                self.noise_count = 0;
                const bit = (self.lfsr ^ (self.lfsr >> 3)) & 1;
                self.lfsr = (self.lfsr >> 1) | (bit << 16);
            }
        }
        if (!self.env_holding) {
            const period = @max(@as(u16, self.regs[12]) << 8 | self.regs[11], 1);
            self.env_count += 1;
            if (self.env_count >= period) {
                self.env_count = 0;
                if (self.env_step > 0) {
                    self.env_step -= 1;
                } else {
                    if (self.env_alternate) self.env_attack ^= 0x1f;
                    if (self.env_hold) self.env_holding = true else self.env_step = 31;
                }
            }
        }
    }

    /// The envelope's level, 0 to 31.
    pub fn envelopeLevel(self: *const Psg) u8 {
        return self.env_step ^ self.env_attack;
    }

    /// One channel's output now, 0 to 1.
    pub fn channelLevel(self: *const Psg, channel: usize) f32 {
        const mixer = self.regs[7];
        const tone_off = mixer & (@as(u8, 1) << @intCast(channel)) != 0;
        const noise_off = mixer & (@as(u8, 8) << @intCast(channel)) != 0;
        const on = (self.tone_high[channel] or tone_off) and (self.lfsr & 1 != 0 or noise_off);
        if (!on) return 0;
        const amplitude = self.regs[8 + channel];
        // A fixed volume L is the envelope's level 2L + 1.
        const step_level: u8 = if (amplitude & 0x10 != 0) self.envelopeLevel() else (amplitude & 0x0f) * 2 + 1;
        return switch (self.model) {
            .ay8910 => ay_levels[step_level >> 1],
            .ym2149 => ym_levels[step_level],
        };
    }

    /// The three channels together, 0 to 1.
    pub fn level(self: *const Psg) f32 {
        return (self.channelLevel(0) + self.channelLevel(1) + self.channelLevel(2)) / 3.0;
    }

    /// The next sample: the mean of the steps it covers (0 to 1).
    pub fn sample(self: *Psg) f32 {
        const unit: u64 = @as(u64, self.sample_rate) * 8;
        self.fraction += self.clock;
        var sum: f32 = 0;
        var count: u32 = 0;
        while (self.fraction >= unit) {
            self.fraction -= unit;
            self.step();
            sum += self.level();
            count += 1;
        }
        if (count > 0) self.last = sum / @as(f32, @floatFromInt(count));
        return self.last;
    }
};
