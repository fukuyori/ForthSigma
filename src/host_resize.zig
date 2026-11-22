//! Standard EKEY resize notifications; preserve prior SIGWINCH ownership.
const std = @import("std");
const forth = @import("forth.zig");
const windows = @import("builtin").os.tag == .windows;
var pending = std.atomic.Value(bool).init(false);
pub fn record() void {
    pending.store(true, .seq_cst);
}
pub fn take() bool {
    return pending.swap(false, .seq_cst);
}
const posix = if (windows) struct {} else struct {
    fn notify(_: std.c.SIG) callconv(.c) void {
        pending.store(true, .seq_cst);
    }
    const Scope = struct {
        previous: std.c.Sigaction = undefined,
        active: bool = false,
        pub fn begin(enabled: bool) forth.RuntimeError!@This() {
            if (!enabled) return .{};
            var action = std.mem.zeroes(std.c.Sigaction);
            action.handler.handler = &notify;
            action.flags = std.c.SA.RESTART;
            if (std.c.sigemptyset(&action.mask) != 0) return error.HostFailed;
            var scope = @This(){};
            if (std.c.sigaction(.WINCH, &action, &scope.previous) != 0) return error.HostFailed;
            scope.active = true;
            pending.store(false, .seq_cst);
            return scope;
        }
        pub fn end(self: *@This()) bool {
            if (!self.active) return true;
            self.active = false;
            pending.store(false, .seq_cst);
            return std.c.sigaction(.WINCH, &self.previous, null) == 0;
        }
    };
};
pub const Scope = if (windows) struct {
    pub fn begin(_: bool) forth.RuntimeError!@This() {
        return .{};
    }
    pub fn end(_: *@This()) bool {
        return true;
    }
} else posix.Scope;

test "resize notification coalesces and restores the previous SIGWINCH disposition" {
    if (windows) return error.SkipZigTest;
    var before = std.mem.zeroes(std.c.Sigaction);
    try std.testing.expectEqual(@as(c_int, 0), std.c.sigaction(.WINCH, null, &before));
    var scope = try Scope.begin(true);
    var ended = false;
    defer if (!ended) {
        _ = scope.end();
    };
    posix.notify(.WINCH);
    posix.notify(.WINCH);
    try std.testing.expect(take());
    try std.testing.expect(!take());
    try std.testing.expect(scope.end());
    ended = true;
    var after = std.mem.zeroes(std.c.Sigaction);
    try std.testing.expectEqual(@as(c_int, 0), std.c.sigaction(.WINCH, null, &after));
    try std.testing.expectEqual(before.handler.handler, after.handler.handler);
    // Linux libc supplies a sigreturn trampoline even when restoring SIG_DFL.
    // musl sigaction.c ORs SA_RESTORER; this ABI bit is not a disposition change.
    const restorer: @TypeOf(before.flags) = if (@hasDecl(std.c.SA, "RESTORER")) std.c.SA.RESTORER else 0;
    try std.testing.expectEqual(before.flags & ~restorer, after.flags & ~restorer);
    // Linux keeps 64 signals, 8 bytes; the C library's sigset_t is 128 bytes, and it
    // leaves what was in memory in bytes beyond those (seen at 104 to 127 on glibc),
    // so only the bytes the kernel keeps tell whether the mask is the same.
    const kept = if (@import("builtin").os.tag == .linux) 8 else @sizeOf(@TypeOf(before.mask));
    try std.testing.expectEqualSlices(u8, std.mem.asBytes(&before.mask)[0..kept], std.mem.asBytes(&after.mask)[0..kept]);
}
