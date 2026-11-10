//! Recorded sound (PCM) for LOAD-SAMPLE, SAMPLE, SFX, and the Amiga: the samples' place
//! in the host's pool, the WAV files they come from, and a player that steps through
//! them.
//!
//! The pool is one block of 16-bit samples that the host gives once (64 MiB). Samples are
//! only added at its end, and FREE-SAMPLES empties it after the music has stopped, so the
//! audio thread never reads a part that changes.

const std = @import("std");

/// The samples LOAD-SAMPLE and SAMPLE can define (0 to 63).
pub const sample_count = 64;

/// The pool's size in 16-bit samples: 64 MiB.
pub const pool_samples = 32 * 1024 * 1024;

/// One sample in the pool: `length` frames from `start`, recorded at `rate` Hz, with a
/// loop from `loop_start` to `loop_end` (none when they are equal).
pub const Sample = struct {
    start: u32 = 0,
    length: u32 = 0,
    rate: u32 = 0,
    loop_start: u32 = 0,
    loop_end: u32 = 0,

    pub fn loops(self: Sample) bool {
        return self.loop_end > self.loop_start;
    }
};

/// What a WAV file's "fmt " chunk says, for the PCM this reads.
pub const Format = struct {
    channels: u16,
    rate: u32,
    /// 8 (unsigned) or 16 (signed, little-endian).
    bits: u16,

    pub fn frameBytes(self: Format) usize {
        return @as(usize, self.channels) * (self.bits / 8);
    }
};

pub const WavError = error{InvalidWav};

/// The format in a "fmt " chunk's bytes: PCM (1, or the extensible form 0xFFFE with
/// the PCM sub-format) of 1 or 2 channels, 8 or 16 bits.
pub fn parseFormat(body: []const u8) WavError!Format {
    if (body.len < 16) return error.InvalidWav;
    const tag = std.mem.readInt(u16, body[0..2], .little);
    const channels = std.mem.readInt(u16, body[2..4], .little);
    const rate = std.mem.readInt(u32, body[4..8], .little);
    const bits = std.mem.readInt(u16, body[14..16], .little);
    const pcm = tag == 1 or (tag == 0xfffe and body.len >= 26 and std.mem.readInt(u16, body[24..26], .little) == 1);
    if (!pcm or channels < 1 or channels > 2 or (bits != 8 and bits != 16) or rate < 1000 or rate > 192_000) return error.InvalidWav;
    return .{ .channels = channels, .rate = rate, .bits = bits };
}

/// Turns whole frames of `bytes` into mono 16-bit samples (the channels' mean) in
/// `out`, which has room for them; the number of frames.
pub fn convertFrames(format: Format, bytes: []const u8, out: []i16) usize {
    const frame = format.frameBytes();
    const frames = bytes.len / frame;
    for (0..frames) |f| {
        var sum: i32 = 0;
        for (0..format.channels) |c| {
            const at = f * frame + c * (format.bits / 8);
            sum += if (format.bits == 8)
                (@as(i32, bytes[at]) - 128) * 256
            else
                std.mem.readInt(i16, bytes[at..][0..2], .little);
        }
        out[f] = @intCast(@divTrunc(sum, format.channels));
    }
    return frames;
}

/// Plays a sample (or a short wave) from a step a sample, holding each value until the
/// next (as the Amiga's Paula does), looping where the sample says.
pub const Player = struct {
    active: bool = false,
    sample: Sample = .{},
    position: f64 = 0,
    step: f64 = 0,

    pub fn start(self: *Player, sample: Sample, step: f64) void {
        self.* = .{ .active = sample.length > 0, .sample = sample, .step = step };
    }

    /// The next value, -1 to 1, from the pool's data.
    pub fn next(self: *Player, data: []const i16) f32 {
        if (!self.active) return 0;
        const index: u32 = @intFromFloat(self.position);
        if (index >= self.sample.length or self.sample.start + index >= data.len) {
            self.active = false;
            return 0;
        }
        const value = @as(f32, @floatFromInt(data[self.sample.start + index])) / 32768.0;
        self.position += self.step;
        if (self.sample.loops() and self.position >= @as(f64, @floatFromInt(self.sample.loop_end))) {
            self.position -= @floatFromInt(self.sample.loop_end - self.sample.loop_start);
        }
        return value;
    }
};
