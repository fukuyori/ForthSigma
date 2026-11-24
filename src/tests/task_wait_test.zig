const std = @import("std");
const base = @import("../core/runtime_base.zig");
const wait = @import("../core/task_wait.zig");
const Fake = struct {
    generation: u64 = 0,
    instant: base.Instant = 0,
    ready: bool = false,
    attach_ready: bool = false,
    fail_attach: bool = false,
    detaches: usize = 0,
    fn get(context: ?*anyopaque) *@This() {
        return @ptrCast(@alignCast(context.?));
    }
    fn now(context: ?*anyopaque) base.Error!base.Instant {
        return get(context).instant;
    }
    fn observe(context: ?*anyopaque) u64 {
        return get(context).generation;
    }
    fn notify(context: ?*anyopaque) base.Error!void {
        get(context).generation += 1;
    }
    fn sleep(_: ?*anyopaque, _: u64, _: base.Deadline, _: ?*const base.Cancellation, _: base.Clock) base.Error!base.WakeOutcome {
        return error.HostFailed;
    }
    fn validate(_: ?*anyopaque) base.Error!void {}
    fn attach(context: ?*anyopaque) base.Error!void {
        const self = get(context);
        if (self.fail_attach) return error.HostFailed;
        if (self.attach_ready) {
            self.ready = true;
            try notify(context);
        }
    }
    fn probe(context: ?*anyopaque) base.Error!wait.State {
        return .{ .reason = if (get(context).ready) .readable else null };
    }
    fn detach(context: ?*anyopaque) void {
        const self = get(context);
        self.detaches += 1;
        self.ready = true;
        self.generation += 1;
    }
    fn source(self: *@This()) wait.Source {
        return .{ .context = self, .validate = validate, .attach = attach, .probe = probe, .detach = detach };
    }
    fn registration(self: *@This()) wait.Registration {
        return .{ .wake = .{ .context = self, .observe_fn = observe, .notify_fn = notify, .wait_fn = sleep }, .clock = .{ .context = self, .now_fn = now }, .deadline = .{ .at = 100 } };
    }
};
const identity = base.Handle{ .epoch = 1, .serial = 1 };
test "wait observes before registration and preserves state across detach" {
    for ([_]bool{ false, true }) |during| {
        var fake = Fake{ .ready = !during, .attach_ready = during };
        var registration = fake.registration();
        const targets = [_]wait.Target{.{ .kind = .io, .identity = identity, .source = fake.source() }};
        try registration.open(&targets);
        try std.testing.expectEqual(@as(usize, 1), registration.poll().count);
        fake.ready = false;
        registration.close();
        try std.testing.expectEqual(@as(usize, 1), fake.detaches);
        try registration.open(&targets);
        try std.testing.expectEqual(@as(usize, 1), registration.poll().count);
        registration.close();
    }
}
test "wait keeps all simultaneous targets cancellation and absolute deadlines" {
    var fake = Fake{ .ready = true, .instant = 50 };
    var token = base.Cancellation{};
    var registration = fake.registration();
    registration.cancellation = &token;
    const targets = [_]wait.Target{
        .{ .kind = .io, .identity = identity, .source = fake.source() },
        .{ .kind = .clock, .identity = identity, .at = 75 },
        .{ .kind = .input, .identity = identity, .source = fake.source() },
    };
    try registration.open(&targets);
    defer registration.close();
    const before = registration.poll();
    try std.testing.expectEqual(@as(usize, 2), before.count);
    try std.testing.expectEqual(@as(?base.Instant, 75), before.next.at);
    try registration.requestCancellation();
    fake.instant = 100;
    for (0..1000) |_| try Fake.notify(&fake);
    const after = registration.poll();
    try std.testing.expectEqual(@as(usize, 3), after.count);
    try std.testing.expect(after.cancelled and !after.interrupted and after.expired);
    try std.testing.expectEqual(@as(?base.Instant, 100), registration.deadline.at);
}
test "wait validates all targets and unwinds partial attachment" {
    var first = Fake{};
    var bad = Fake{ .fail_attach = true };
    var registration = first.registration();
    const targets = [_]wait.Target{ .{ .kind = .io, .identity = identity, .source = first.source() }, .{ .kind = .io, .identity = identity, .source = bad.source() } };
    try std.testing.expectError(error.HostFailed, registration.open(&targets));
    try std.testing.expectEqual(@as(usize, 1), first.detaches);
    try std.testing.expect(!registration.active);
    var too_many: [wait.capacity + 1]wait.Target = @splat(targets[0]);
    try std.testing.expectError(error.ResultOutOfRange, registration.open(&too_many));
}

test "registration metadata and returned collection fit reserved notification budget" {
    // Static sizes, not resident memory or speed measurements.
    try std.testing.expect(@sizeOf(wait.Registration) + @sizeOf(wait.Result) < 32 * 1024);
}
test "notification after probe is not absorbed into a fresh observed generation" {
    var fake = Fake{};
    const Late = struct {
        fn probe(context: ?*anyopaque) base.Error!wait.State {
            const self = Fake.get(context);
            const previous = self.ready;
            self.ready = true;
            try Fake.notify(context);
            return .{ .reason = if (previous) .readable else null };
        }
    };
    var source = fake.source();
    source.probe = Late.probe;
    var registration = fake.registration();
    try registration.open(&.{.{ .kind = .io, .identity = identity, .source = source }});
    defer registration.close();
    const result = registration.poll();
    try std.testing.expectEqual(@as(usize, 0), result.count);
    try std.testing.expect(registration.observed != fake.generation);
    try std.testing.expectEqual(@as(usize, 1), registration.poll().count);
}
