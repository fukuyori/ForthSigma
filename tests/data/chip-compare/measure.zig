//! What the chip comparison (tque 1206) measures of a rendered sound: the fundamental
//! from the rising zero crossings, the RMS, the peak, the harmonics 2 to 8 against the
//! first (Goertzel at multiples of the fundamental), and the zero crossings a second.
//! Copied next to old_probe.zig and new_probe.zig by tests/scripts/compare-chip-libraries.py.
const std = @import("std");

pub const rate = 48000;

pub const Stats = struct {
    f0: f64,
    rms: f64,
    peak: f64,
    harmonics_db: [7]f64,
    crossings: f64,
};

/// The left side of `stereo` (i16 pairs) from frame `skip` on.
pub fn measure(stereo: []const i16, skip: usize) Stats {
    const frames = stereo.len / 2 - skip;
    var mean: f64 = 0;
    for (0..frames) |i| mean += @floatFromInt(stereo[(skip + i) * 2]);
    mean /= @floatFromInt(frames);
    var sum: f64 = 0;
    var peak: f64 = 0;
    var rising: usize = 0;
    var crossings: usize = 0;
    var first: ?usize = null;
    var last: usize = 0;
    var previous: f64 = 0;
    for (0..frames) |i| {
        const x = @as(f64, @floatFromInt(stereo[(skip + i) * 2])) - mean;
        sum += x * x;
        peak = @max(peak, @abs(x));
        if (i > 0 and (previous < 0) != (x < 0)) crossings += 1;
        if (i > 0 and previous < 0 and x >= 0) {
            if (first == null) first = i;
            last = i;
            rising += 1;
        }
        previous = x;
    }
    const seconds = @as(f64, @floatFromInt(frames)) / rate;
    var f0: f64 = 0;
    if (first) |f| {
        if (rising > 1) f0 = @as(f64, @floatFromInt(rising - 1)) * rate / @as(f64, @floatFromInt(last - f));
    }
    var harmonics: [7]f64 = @splat(0);
    if (f0 > 0) {
        const h1 = goertzel(stereo, skip, frames, mean, f0);
        for (&harmonics, 2..) |*h, k| {
            const hk = goertzel(stereo, skip, frames, mean, f0 * @as(f64, @floatFromInt(k)));
            h.* = if (h1 > 0 and hk > 0) 20 * std.math.log10(hk / h1) else -200;
        }
    }
    return .{
        .f0 = f0,
        .rms = @sqrt(sum / @as(f64, @floatFromInt(frames))) / 32768.0,
        .peak = peak / 32768.0,
        .harmonics_db = harmonics,
        .crossings = @as(f64, @floatFromInt(crossings)) / seconds,
    };
}

/// The magnitude at `hz`, with a Hann window.
fn goertzel(stereo: []const i16, skip: usize, frames: usize, mean: f64, hz: f64) f64 {
    if (hz >= rate / 2) return 0;
    const w = 2 * std.math.pi * hz / rate;
    const c = 2 * @cos(w);
    var s1: f64 = 0;
    var s2: f64 = 0;
    for (0..frames) |i| {
        const window = 0.5 - 0.5 * @cos(2 * std.math.pi * @as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(frames - 1)));
        const x = (@as(f64, @floatFromInt(stereo[(skip + i) * 2])) - mean) * window;
        const s = x + c * s1 - s2;
        s2 = s1;
        s1 = s;
    }
    return @sqrt(@max(s1 * s1 + s2 * s2 - c * s1 * s2, 0));
}

pub extern "c" fn puts([*:0]const u8) c_int;

/// One line of JSON: "name": {...}.
pub fn print(name: []const u8, s: Stats, last: bool) void {
    var line: [1024]u8 = undefined;
    const text = std.fmt.bufPrint(&line, "  \"{s}\": {{\"f0\": {d:.3}, \"rms\": {d:.6}, \"peak\": {d:.6}, \"crossings\": {d:.1}, \"harmonics_db\": [{d:.2}, {d:.2}, {d:.2}, {d:.2}, {d:.2}, {d:.2}, {d:.2}]}}{s}\x00", .{
        name, s.f0, s.rms, s.peak, s.crossings,
        s.harmonics_db[0], s.harmonics_db[1], s.harmonics_db[2], s.harmonics_db[3], s.harmonics_db[4], s.harmonics_db[5], s.harmonics_db[6],
        if (last) "" else ",",
    }) catch return;
    _ = puts(@ptrCast(text.ptr));
}
