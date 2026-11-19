//! Host-thread-only signal scopes; the process gate also excludes other runtimes.
//! Hooks must roll back their own partial begin. A failed end retains ownership:
//! the caller may retry with its still-live ticket; nobody may overwrite the scope.
const std = @import("std");
const base = @import("core/runtime_base.zig");
const Scopes = base.SignalOwnership(16);
var process_owner = std.atomic.Value(u64).init(0);
pub const HookError = base.Error || error{SignalRestoreFailed};

pub const Hooks = struct {
    context: ?*anyopaque,
    begin_fn: *const fn (?*anyopaque) HookError!void,
    end_fn: *const fn (?*anyopaque) base.Error!void,
};
pub const Ticket = struct { scope: Scopes.Scope, hooks: Hooks };

pub const Broker = struct {
    owner: u64,
    scopes: Scopes = .{},
    failed_scope: ?Ticket = null,

    pub fn begin(self: *Broker, hooks: Hooks) base.Error!Ticket {
        if (self.failed_scope != null) return error.HostFailed;
        const scope = self.scopes.enter(self.owner) catch return error.HostFailed;
        if (self.scopes.depth == 1) {
            if (process_owner.cmpxchgStrong(0, self.owner, .acq_rel, .acquire) != null) {
                self.scopes.leave(scope) catch unreachable;
                return error.HostFailed;
            }
        }
        hooks.begin_fn(hooks.context) catch |err| {
            if (err == error.SignalRestoreFailed) {
                self.failed_scope = .{ .scope = scope, .hooks = hooks };
                return error.HostFailed;
            }
            self.scopes.leave(scope) catch unreachable;
            if (self.scopes.depth == 0) process_owner.store(0, .release);
            return if (err == error.ResultOutOfRange) error.ResultOutOfRange else error.HostFailed;
        };
        return .{ .scope = scope, .hooks = hooks };
    }

    pub fn end(self: *Broker, ticket: Ticket) base.Error!void {
        if (self.scopes.depth == 0) return error.HostFailed;
        const top = self.scopes.stack[self.scopes.depth - 1];
        if (top.owner != ticket.scope.owner or top.serial != ticket.scope.serial) return error.HostFailed;
        ticket.hooks.end_fn(ticket.hooks.context) catch |err| {
            self.failed_scope = ticket;
            return err;
        };
        self.scopes.leave(ticket.scope) catch unreachable;
        self.failed_scope = null;
        if (self.scopes.depth == 0) process_owner.store(0, .release);
    }

    /// Hook contexts must remain alive until recovery succeeds. Native wait scopes
    /// use process-owned storage rather than a returning call's stack for this.
    pub fn recover(self: *Broker) base.Error!void {
        if (self.failed_scope) |ticket| try self.end(ticket);
    }

    pub fn isActive(self: *const Broker) bool {
        return self.scopes.depth != 0;
    }
};

// Reserved owner: identities created by host_runtime start at 2.
pub var fallback = Broker{ .owner = 1 };

test "signal broker rolls back failed begin and retains failed restoration ownership" {
    const Fake = struct {
        begins: usize = 0,
        ends: usize = 0,
        fail_begin: bool = false,
        fail_end: bool = false,
        fn begin(context: ?*anyopaque) base.Error!void {
            const self: *@This() = @ptrCast(@alignCast(context.?));
            if (self.fail_begin) return error.HostFailed;
            self.begins += 1;
        }
        fn end(context: ?*anyopaque) base.Error!void {
            const self: *@This() = @ptrCast(@alignCast(context.?));
            if (self.fail_end) return error.HostFailed;
            self.ends += 1;
        }
        fn hooks(self: *@This()) Hooks {
            return .{ .context = self, .begin_fn = begin, .end_fn = end };
        }
    };
    var first = Broker{ .owner = 10 };
    var second = Broker{ .owner = 11 };
    var fake = Fake{ .fail_begin = true };
    try std.testing.expectError(error.HostFailed, first.begin(fake.hooks()));
    try std.testing.expect(!first.isActive());
    fake.fail_begin = false;
    const outer = try first.begin(fake.hooks());
    try std.testing.expectError(error.HostFailed, second.begin(fake.hooks()));
    const inner = try first.begin(fake.hooks());
    try std.testing.expectError(error.HostFailed, first.end(outer));
    fake.fail_end = true;
    try std.testing.expectError(error.HostFailed, first.end(inner));
    try std.testing.expectError(error.HostFailed, second.begin(fake.hooks()));
    fake.fail_end = false;
    try first.recover();
    try first.end(outer);
    try std.testing.expectEqual(@as(usize, 2), fake.begins);
    try std.testing.expectEqual(@as(usize, 2), fake.ends);
    const next = try second.begin(fake.hooks());
    try second.end(next);
}

test "signal broker retains a failed begin rollback until its stable context recovers" {
    const Fake = struct {
        ends: usize = 0,
        fn begin(_: ?*anyopaque) HookError!void {
            return error.SignalRestoreFailed;
        }
        fn end(context: ?*anyopaque) base.Error!void {
            const self: *@This() = @ptrCast(@alignCast(context.?));
            self.ends += 1;
        }
    };
    var fake = Fake{};
    var broker = Broker{ .owner = 99 };
    defer broker.recover() catch |err| std.debug.print("broker cleanup: {s}\n", .{@errorName(err)});
    try std.testing.expectError(error.HostFailed, broker.begin(.{ .context = &fake, .begin_fn = Fake.begin, .end_fn = Fake.end }));
    try std.testing.expect(broker.isActive());
    try broker.recover();
    try std.testing.expect(!broker.isActive());
    try std.testing.expectEqual(@as(usize, 1), fake.ends);
}
