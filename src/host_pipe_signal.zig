//! Temporarily suppress SIGPIPE around a native pipe operation, preserving sigaction.
const std = @import("std");
const windows = @import("builtin").os.tag == .windows;
const forth = @import("forth.zig");

pub const Scope = if (windows) struct {
    pub fn begin(_: bool) forth.RuntimeError!@This() {
        return .{};
    }
    pub fn end(_: *@This()) bool {
        return true;
    }
} else struct {
    previous: std.c.Sigaction = undefined,
    active: bool = false,
    pub fn begin(enabled: bool) forth.RuntimeError!@This() {
        if (!enabled) return .{};
        var action = std.mem.zeroes(std.c.Sigaction);
        action.handler.handler = @ptrFromInt(1); // POSIX SIG_IGN.
        if (std.c.sigemptyset(&action.mask) != 0) return error.HostFailed;
        var scope = @This(){};
        if (std.c.sigaction(.PIPE, &action, &scope.previous) != 0) return error.HostFailed;
        scope.active = true;
        return scope;
    }
    pub fn end(self: *@This()) bool {
        if (!self.active) return true;
        self.active = false;
        return std.c.sigaction(.PIPE, &self.previous, null) == 0;
    }
};
