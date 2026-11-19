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
