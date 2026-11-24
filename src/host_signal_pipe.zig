//! POSIX SIGINT bridge. Only lock-free atomics and write are used in handler.
const std = @import("std");
const builtin = @import("builtin");
const base = @import("core/runtime_base.zig");
const enabled = builtin.os.tag != .windows;
const native = struct {
    extern "c" fn fcntl(c_int, c_int, ...) c_int;
};
var writer: std.atomic.Value(c_int) = .init(-1);
var handlers: std.atomic.Value(u32) = .init(0);
var failed: std.atomic.Value(bool) = .init(false);
var reader: c_int = -1; // single host owner
pub fn open() base.Error!void {
    if (comptime !enabled) return;
    if (reader >= 0) return error.HostFailed;
    var fds: [2]c_int = undefined;
    if (builtin.os.tag == .linux) {
        if (std.c.pipe2(&fds, .{ .CLOEXEC = true, .NONBLOCK = true }) != 0) return error.HostFailed;
    } else {
        if (std.c.pipe(&fds) != 0) return error.HostFailed;
        errdefer {
            _ = std.c.close(fds[0]);
            _ = std.c.close(fds[1]);
        }
        const nonblock: c_int = @bitCast(@as(u32, @bitCast(std.c.O{ .NONBLOCK = true })));
        for (fds) |fd| {
            const flags = native.fcntl(fd, std.c.F.GETFL);
            const fdflags = native.fcntl(fd, std.c.F.GETFD);
            if (flags < 0 or fdflags < 0 or native.fcntl(fd, std.c.F.SETFL, flags | nonblock) < 0 or native.fcntl(fd, std.c.F.SETFD, fdflags | @import("c_file").FD_CLOEXEC) < 0) return error.HostFailed;
        }
    }
    reader = fds[0];
    failed.store(false, .release);
    writer.store(fds[1], .seq_cst);
}
pub fn signal() void {
    if (comptime !enabled) return;
    const saved = std.c._errno().*;
    _ = handlers.fetchAdd(1, .seq_cst);
    const fd = writer.load(.seq_cst);
    if (fd >= 0) {
        const byte = [_]u8{1};
        while (std.c.write(fd, &byte, 1) != 1) {
            const code = std.c._errno().*;
            if (code == @backingInt(std.c.E.INTR)) continue;
            if (code != @backingInt(std.c.E.AGAIN)) failed.store(true, .release);
            break;
        }
    }
    _ = handlers.fetchSub(1, .seq_cst);
    std.c._errno().* = saved;
}
pub fn descriptor() c_int {
    return reader;
}
pub fn pump() base.Error!bool {
    if (comptime !enabled) return false;
    if (failed.load(.acquire)) return error.HostFailed;
    if (reader < 0) return false;
    var bytes: [256]u8 = undefined;
    const count = std.c.read(reader, &bytes, bytes.len);
    if (count == 0) return error.HostFailed;
    if (count < 0) {
        const code = std.c._errno().*;
        if (code != @backingInt(std.c.E.AGAIN) and code != @backingInt(std.c.E.INTR)) return error.HostFailed;
    }
    return count > 0;
}
/// Restore the previous signal handler before closing. Late handlers observe -1;
/// handlers already borrowing the old fd finish before it can be reused.
pub fn close() base.Error!void {
    if (comptime !enabled) return;
    const fd = writer.swap(-1, .seq_cst);
    while (handlers.load(.seq_cst) != 0) std.atomic.spinLoopHint();
    var failure = false;
    if (fd >= 0 and std.c.close(fd) != 0) failure = true;
    const old = reader;
    reader = -1;
    if (old >= 0 and std.c.close(old) != 0) failure = true;
    if (failure) return error.HostFailed;
}
