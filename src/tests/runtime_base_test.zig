const std = @import("std");
const base = @import("../core/runtime_base.zig");

test "runtime deadlines keep a single deadline and handle the whole signed range" {
    const deadline = try base.Deadline.afterMilliseconds(100, 2);
    try std.testing.expect(!deadline.expired(2_000_099));
    try std.testing.expect(deadline.expired(2_000_100));
    try std.testing.expectEqual(@as(u32, 1), deadline.remainingMilliseconds(2_000_099, 20));
    try std.testing.expectEqual(@as(u32, 0), deadline.remainingMilliseconds(2_000_100, 20));
    try std.testing.expectEqual(@as(u32, 20), (base.Deadline{ .at = std.math.maxInt(i128) }).remainingMilliseconds(std.math.minInt(i128), 20));
    try std.testing.expectError(error.ResultOutOfRange, base.Deadline.afterMilliseconds(std.math.maxInt(i128), 1));
    const unbounded = try base.Deadline.afterMilliseconds(0, -1);
    try std.testing.expect(!unbounded.expired(std.math.maxInt(i128)));
    try std.testing.expectEqual(@as(u32, 20), unbounded.remainingMilliseconds(0, 20));
}

test "runtime clock failures and sticky cancellation are observable" {
    const Fake = struct {
        fn fail(_: ?*anyopaque) base.Error!base.Instant {
            return error.HostFailed;
        }
    };
    try std.testing.expectError(error.HostFailed, (base.Clock{ .context = null, .now_fn = Fake.fail }).now());
    var token = base.Cancellation{};
    try std.testing.expect(!token.isRequested());
    token.request();
    token.request();
    try std.testing.expect(token.isRequested());
}

test "runtime resource identity rejects stale, foreign, wrong-kind and exhausted handles" {
    const Table = base.ResourceTable(u32, 1);
    var table = try Table.init(7);
    try std.testing.expectError(error.InvalidHandle, Table.init(0));
    const first = try table.insert(2, .task, 42);
    try std.testing.expectEqual(@as(u32, 42), (try table.get(first, 2, .task)).*);
    try std.testing.expectError(error.WrongOwner, table.get(first, 3, .task));
    try std.testing.expectError(error.WrongKind, table.get(first, 2, .frame));
    try std.testing.expectError(error.InvalidHandle, table.get(.{ .epoch = 8, .serial = first.serial }, 2, .task));
    try std.testing.expectError(error.ResourceFull, table.insert(2, .task, 0));
    try std.testing.expectEqual(@as(u32, 42), try table.remove(first, 2, .task));
    try std.testing.expectError(error.InvalidHandle, table.remove(first, 2, .task));
    const second = try table.insert(2, .task, 43);
    try std.testing.expect(second.serial != first.serial);
    try std.testing.expectError(error.InvalidHandle, table.get(first, 2, .task));
    _ = try table.remove(second, 2, .task);
    table.next_serial = std.math.maxInt(u64);
    const last = try table.insert(2, .task, 44);
    _ = try table.remove(last, 2, .task);
    try std.testing.expectError(error.IdentityExhausted, table.insert(2, .task, 45));
}

test "runtime signal ownership rejects cross-owner and out-of-order releases" {
    var scopes = base.SignalOwnership(2){};
    const outer = try scopes.enter(1);
    try std.testing.expectError(error.WrongOwner, scopes.enter(2));
    const inner = try scopes.enter(1);
    try std.testing.expectError(error.ScopeFull, scopes.enter(1));
    try std.testing.expectError(error.InvalidScope, scopes.leave(outer));
    try scopes.leave(inner);
    try scopes.leave(outer);
    const next = try scopes.enter(1);
    try std.testing.expectError(error.InvalidScope, scopes.leave(outer));
    try scopes.leave(next);
    try std.testing.expectError(error.InvalidScope, scopes.leave(next));
}
