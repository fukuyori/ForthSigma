//! Shared internal monotonic clock. No word-group or terminal-mode dependency.
const std = @import("std");
const builtin = @import("builtin");
const runtime = @import("core/runtime_base.zig");
pub const clock = runtime.Clock{ .context = null, .now_fn = read };

const windows = struct {
    extern "kernel32" fn QueryPerformanceCounter(*i64) callconv(.winapi) c_int;
    extern "kernel32" fn QueryPerformanceFrequency(*i64) callconv(.winapi) c_int;
};

pub fn now() runtime.Error!runtime.Instant {
    return read(null);
}
fn read(_: ?*anyopaque) runtime.Error!runtime.Instant {
    if (builtin.os.tag == .windows) {
        var counter: i64 = undefined;
        var frequency: i64 = undefined;
        if (windows.QueryPerformanceCounter(&counter) == 0 or windows.QueryPerformanceFrequency(&frequency) == 0 or frequency <= 0) return error.HostFailed;
        return @divFloor(@as(runtime.Instant, counter) * 1_000_000_000, frequency);
    }
    var instant: std.c.timespec = undefined;
    if (std.c.clock_gettime(std.c.CLOCK.MONOTONIC, &instant) != 0) return error.HostFailed;
    return @as(runtime.Instant, instant.sec) * 1_000_000_000 + instant.nsec;
}

// Resolution is metadata, sampled once before acceptance endpoints, not overhead
// subtracted from intervals. Darwin uses the same CLOCK_MONOTONIC as read().
extern "c" fn clock_getres(std.c.clockid_t, *std.c.timespec) c_int;
pub fn resolutionNs() runtime.Error!u64 {
    if (builtin.os.tag == .windows) {
        var frequency: i64 = undefined;
        if (windows.QueryPerformanceFrequency(&frequency) == 0 or frequency <= 0) return error.HostFailed;
        return @intCast(@divTrunc(@as(i128, 1_000_000_000) + frequency - 1, frequency));
    }
    var resolution: std.c.timespec = undefined;
    if (clock_getres(std.c.CLOCK.MONOTONIC, &resolution) != 0) return error.HostFailed;
    const ns = @as(i128, resolution.sec) * 1_000_000_000 + resolution.nsec;
    if (ns <= 0) return error.HostFailed;
    return std.math.cast(u64, ns) orelse error.HostFailed;
}
