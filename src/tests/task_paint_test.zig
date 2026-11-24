const std = @import("std");
const paint = @import("../core/task_paint.zig");
const Wake = @import("../host_wake.zig").Wake;
test "paint registration validates backend window and fixed target" {
    var source = paint.Source{};
    try std.testing.expectError(error.UnsupportedBackend, source.register(0, null));
    source.publish(true, false, 0, 0);
    try std.testing.expectError(error.NoWindow, source.register(0, null));
    source.publish(true, true, 3, 1);
    try std.testing.expectError(error.InvalidTarget, source.register(0, 0));
    try std.testing.expectError(error.InvalidTarget, source.register(0, 4));
    var registration = try source.register(17, null);
    try std.testing.expectEqual(@as(usize, 17), registration.index);
    source.publish(true, true, 5, 2);
    try std.testing.expectEqual(paint.Result.pending, try source.probe(registration));
    source.publish(true, true, 5, 4);
    try std.testing.expectEqual(paint.Result.painted, try source.probe(registration));
    source.unregister(&registration);
    source.unregister(&registration);
    try std.testing.expectError(error.NotRegistered, source.probe(registration));
}
test "paint close reopen capability loss and notifications are retained" {
    var wake = try Wake.init();
    defer wake.deinit() catch unreachable;
    var source = paint.Source{};
    source.bind(wake.operations());
    defer source.bind(null);
    var generation = wake.observe();
    source.publish(true, true, 1, 0);
    try std.testing.expect(wake.observe() > generation);
    const registration = try source.register(2, null);
    generation = wake.observe();
    source.input();
    try std.testing.expect(wake.observe() > generation);
    try std.testing.expectEqual(paint.Result.pending, try source.probe(registration));
    generation = wake.observe();
    source.publish(true, true, 1, 1);
    try std.testing.expect(wake.observe() > generation);
    generation = wake.observe();
    source.publish(true, false, 1, 1);
    try std.testing.expect(wake.observe() > generation);
    try std.testing.expectEqual(paint.Result.released, try source.probe(registration));
    // A SHOW queued while closed belongs to the next window, not the old lifetime.
    source.publish(true, false, 2, 1);
    source.publish(true, true, 2, 2);
    try std.testing.expectEqual(paint.Result.released, try source.probe(registration));
    try std.testing.expectError(error.InvalidTarget, source.register(3, 1));
    const next = try source.register(3, null);
    source.publish(false, true, 2, 2);
    try std.testing.expectEqual(paint.Result.capability_lost, try source.probe(next));
    try std.testing.expectError(error.UnsupportedBackend, source.register(4, null));
    source.publish(true, true, 2, 2);
    try std.testing.expectEqual(paint.Result.capability_lost, try source.probe(next));
    source.bind(null);
    generation = wake.observe();
    source.input();
    try std.testing.expectEqual(generation, wake.observe());
}
test "paint notification failure stays observable" {
    var wake = try Wake.init();
    var source = paint.Source{};
    source.bind(wake.operations());
    defer source.bind(null);
    source.publish(true, true, 1, 0);
    const registration = try source.register(0, null);
    try wake.deinit();
    source.publish(true, true, 1, 1);
    try std.testing.expectError(error.HostFailed, source.probe(registration));
    source.bind(null);
    try std.testing.expectError(error.HostFailed, source.probe(registration));
    source.bind(wake.operations()); // A failed retry must remain failed.
    try std.testing.expectError(error.HostFailed, source.probe(registration));
    var replacement = try Wake.init();
    defer replacement.deinit() catch unreachable;
    const observed = replacement.observe();
    source.bind(replacement.operations());
    try std.testing.expect(replacement.observe() > observed);
    try std.testing.expectEqual(paint.Result.painted, try source.probe(registration));
}

test "paint lifetime generation exhaustion refuses registration" {
    var source = paint.Source{ .generation = std.math.maxInt(u64) };
    source.publish(true, true, 1, 0);
    try std.testing.expectError(error.HostFailed, source.register(0, null));
    var wake = try Wake.init();
    defer wake.deinit() catch unreachable;
    source.bind(wake.operations());
    defer source.bind(null);
    try std.testing.expectError(error.HostFailed, source.register(0, null));
}

test "POSIX drawing child pipe shares wake without consuming child input" {
    if (@import("builtin").os.tag == .windows) return error.SkipZigTest;
    var wake = try Wake.init();
    defer wake.deinit() catch unreachable;
    var fds: [2]c_int = undefined;
    try std.testing.expectEqual(@as(c_int, 0), std.c.pipe(&fds));
    defer _ = std.c.close(fds[0]);
    defer _ = std.c.close(fds[1]);
    const Clock = struct {
        fn now(_: ?*anyopaque) @import("../core/runtime_base.zig").Error!i128 {
            return 0;
        }
    };
    // Both descriptors are ready. No sleep or elapsed-time observation is needed.
    try wake.notify();
    const observed = wake.observe();
    const byte = [_]u8{42};
    try std.testing.expectEqual(@as(isize, 1), std.c.write(fds[1], &byte, 1));
    try std.testing.expectEqual(@import("../core/runtime_base.zig").WakeOutcome.notified, try wake.waitReadableWithClock(observed, .{ .at = 1 }, null, .{ .context = null, .now_fn = Clock.now }, fds[0]));
    try std.testing.expect(!wake.pending.load(.acquire));
    var read: [1]u8 = undefined;
    try std.testing.expectEqual(@as(isize, 1), std.c.read(fds[0], &read, 1));
    try std.testing.expectEqualSlices(u8, &byte, &read);
    try wake.notify();
    try std.testing.expect(wake.observe() > observed);
}

test "POSIX extra fd alone and cancellation after wait precheck" {
    if (@import("builtin").os.tag == .windows) return error.SkipZigTest;
    const base = @import("../core/runtime_base.zig");
    var wake = try Wake.init();
    defer wake.deinit() catch unreachable;
    var fds: [2]c_int = undefined;
    try std.testing.expectEqual(@as(c_int, 0), std.c.pipe(&fds));
    defer _ = std.c.close(fds[0]);
    defer _ = std.c.close(fds[1]);
    const byte = [_]u8{42};
    try std.testing.expectEqual(@as(isize, 1), std.c.write(fds[1], &byte, 1));
    const Clock = struct {
        token: ?*base.Cancellation = null,
        wake: ?*Wake = null,
        fn now(context: ?*anyopaque) base.Error!base.Instant {
            const self: *@This() = @ptrCast(@alignCast(context.?));
            if (self.token) |token| token.request();
            if (self.wake) |target| try target.notify();
            return 0;
        }
    };
    var clock = Clock{};
    const operations: base.Clock = .{ .context = &clock, .now_fn = Clock.now };
    // Only the extra fd is ready; this operation must not consume it.
    try std.testing.expectEqual(base.WakeOutcome.notified, try wake.waitReadableWithClock(wake.observe(), .{ .at = 1 }, null, operations, fds[0]));
    var token = base.Cancellation{};
    clock.token = &token;
    // Request inside now(), after the loop's cancellation precheck, before poll.
    try std.testing.expectEqual(base.WakeOutcome.cancelled, try wake.waitReadableWithClock(wake.observe(), .{ .at = 1 }, &token, operations, fds[0]));
    token = .{};
    clock.wake = &wake;
    try std.testing.expectEqual(base.WakeOutcome.cancelled, try wake.waitReadableWithClock(wake.observe(), .{ .at = 1 }, &token, operations, fds[0]));
    // The original waitWithClock caller (no extra fd) also retains cancellation priority.
    token = .{};
    try std.testing.expectEqual(base.WakeOutcome.cancelled, try wake.waitWithClock(wake.observe(), .{ .at = 1 }, &token, operations));
    var read: [1]u8 = undefined;
    try std.testing.expectEqual(@as(isize, 1), std.c.read(fds[0], &read, 1));
    try std.testing.expectEqualSlices(u8, &byte, &read);
}
