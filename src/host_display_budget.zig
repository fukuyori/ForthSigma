//! One absolute deadline shared by the initial native/Tk display search (Linux and
//! Windows). Only the main VM thread changes this state; workers receive a copied
//! deadline.
const std = @import("std");
const builtin = @import("builtin");

extern "kernel32" fn GetTickCount64() callconv(.winapi) u64;

var until: ?i64 = null;

pub fn now() i64 {
    if (builtin.os.tag == .windows) return @intCast(GetTickCount64() & std.math.maxInt(i63));
    var time: std.c.timespec = undefined;
    if (std.c.clock_gettime(.MONOTONIC, &time) != 0) return std.math.maxInt(i64) - 10000;
    return @as(i64, time.sec) * 1000 + @divTrunc(@as(i64, time.nsec), 1_000_000);
}

pub fn scope(_: ?*anyopaque, begin: bool) void {
    until = if (begin) now() + 5000 else null;
}

pub fn active() bool {
    return until != null;
}

pub fn deadline() i64 {
    // Leave 50 ms for killing/reaping a failed Tcl child and returning to Forth.
    return if (until) |end| end - 50 else std.math.maxInt(i64);
}

pub fn expired() bool {
    return active() and now() >= deadline();
}

pub fn remaining() c_int {
    return if (active()) @intCast(@max(0, @min(deadline() - now(), std.math.maxInt(c_int)))) else -1;
}

pub fn cleanupDeadline() i64 {
    return until orelse now() + 50;
}
