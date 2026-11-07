//! The header of a WAV file of 16-bit PCM samples (RIFF, "fmt " and "data" chunks).

pub const header_size = 44;

/// The 44 bytes before `frames` frames of `channels` 16-bit samples at `sample_rate`.
pub fn header(sample_rate: u32, channels: u16, frames: u32) [header_size]u8 {
    var bytes: [header_size]u8 = undefined;
    const block: u32 = @as(u32, channels) * 2;
    const data_size = frames * block;
    @memcpy(bytes[0..4], "RIFF");
    put32(bytes[4..8], 36 + data_size);
    @memcpy(bytes[8..16], "WAVEfmt ");
    put32(bytes[16..20], 16);
    put16(bytes[20..22], 1); // PCM
    put16(bytes[22..24], channels);
    put32(bytes[24..28], sample_rate);
    put32(bytes[28..32], sample_rate * block);
    put16(bytes[32..34], @intCast(block));
    put16(bytes[34..36], 16);
    @memcpy(bytes[36..40], "data");
    put32(bytes[40..44], data_size);
    return bytes;
}

/// The samples as the file stores them (little-endian).
pub fn putSamples(out: []u8, samples: []const i16) void {
    for (samples, 0..) |s, i| put16(out[i * 2 ..][0..2], @bitCast(s));
}

fn put16(out: *[2]u8, value: u16) void {
    out[0] = @truncate(value);
    out[1] = @truncate(value >> 8);
}

fn put32(out: *[4]u8, value: u32) void {
    out[0] = @truncate(value);
    out[1] = @truncate(value >> 8);
    out[2] = @truncate(value >> 16);
    out[3] = @truncate(value >> 24);
}
