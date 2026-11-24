//! Scripted publication boundaries; the registration/scheduler/paint are production code.
const std = @import("std");
const t = std.testing;
const base = @import("../core/runtime_base.zig");
const wait = @import("../core/task_wait.zig");
const paint = @import("../core/task_paint.zig");
const schedule = @import("../core/task_schedule.zig");
const id = base.Handle{ .epoch = 1, .serial = 1 };

const Rig = struct {
    instant: base.Instant = 0,
    generation: u64 = 0,
    observations: usize = 0,
    publish_on_observe: usize = 0,
    sleep_calls: usize = 0,
    ready: bool = false,
    boundary: enum { none, attach, probe, detach } = .none,
    pins: usize = 0,
    probes: usize = 0,
    drawing: paint.Source = .{},
    paint_registration: ?paint.Registration = null,
    publication_was_pending: bool = true,
    fn get(p: ?*anyopaque) *Rig {
        return @ptrCast(@alignCast(p.?));
    }
    fn now(p: ?*anyopaque) base.Error!base.Instant {
        return get(p).instant;
    }
    fn notify(p: ?*anyopaque) base.Error!void {
        get(p).generation += 1;
    }
    fn publish(self: *Rig) void {
        if (!self.ready) if (self.paint_registration) |painted| {
            self.publication_was_pending = self.publication_was_pending and
                (self.drawing.probe(painted) catch unreachable) == .pending;
        };
        self.ready = true;
        self.drawing.publish(true, true, 3, 2);
        self.generation += 1;
    }
    fn observe(p: ?*anyopaque) u64 {
        const self = get(p);
        const old = self.generation;
        self.observations += 1;
        if (self.observations == self.publish_on_observe) self.publish();
        return old;
    }
    fn sleep(p: ?*anyopaque, observed: u64, _: base.Deadline, _: ?*const base.Cancellation, _: base.Clock) base.Error!base.WakeOutcome {
        const self = get(p);
        self.sleep_calls += 1;
        // A logical watchdog: unexpected blocking is an immediate failure.
        if (observed == self.generation or self.sleep_calls > 8) return error.HostFailed;
        return .notified;
    }
    fn check(_: ?*anyopaque) base.Error!void {}
    fn attach(p: ?*anyopaque) base.Error!void {
        const self = get(p);
        self.pins += 1;
        if (self.boundary == .attach) self.publish();
    }
    fn probe(p: ?*anyopaque) base.Error!wait.State {
        const self = get(p);
        self.probes += 1;
        const ready = self.ready;
        if (self.boundary == .probe) self.publish();
        return .{ .reason = if (ready) .readable else null };
    }
    fn detach(p: ?*anyopaque) void {
        const self = get(p);
        if (self.boundary == .detach) self.publish();
        self.pins -= 1;
    }
    fn source(self: *Rig) wait.Source {
        return .{ .context = self, .validate = check, .attach = attach, .probe = probe, .detach = detach };
    }
    fn registration(self: *Rig) wait.Registration {
        return .{ .clock = .{ .context = self, .now_fn = now }, .wake = .{ .context = self, .observe_fn = observe, .notify_fn = notify, .wait_fn = sleep }, .deadline = .{ .at = 100 } };
    }
    fn target(self: *Rig) wait.Target {
        return .{ .kind = .io, .identity = id, .source = self.source() };
    }
};

test "1372 W01 W02 W03 scripted publication boundaries retain readiness and paint" {
    for (0..6) |position| {
        var rig = Rig{};
        rig.drawing.publish(true, true, 2, 0);
        var drawing = try rig.drawing.register(17, null);
        defer rig.drawing.unregister(&drawing);
        rig.paint_registration = drawing;
        try t.expectEqual(paint.Result.pending, try rig.drawing.probe(drawing));
        switch (position) {
            0 => rig.publish(), // before initial observe
            1 => rig.publish_on_observe = 1, // observe -> attach
            2 => rig.boundary = .attach,
            3 => rig.publish_on_observe = 2, // reobserve -> probe
            4 => rig.boundary = .probe, // after state snapshot
            5 => {}, // after poll, immediately before wait
            else => unreachable,
        }
        var registration = rig.registration();
        try registration.open(&.{rig.target()});
        defer registration.close();
        var result = registration.poll();
        if (position == 5) rig.publish();
        if (!result.finished()) {
            try t.expect(registration.observed != rig.generation);
            _ = try registration.wake.wait_fn(registration.wake.context, registration.observed, result.next, null, registration.clock);
            result = registration.poll();
        }
        try t.expectEqual(@as(usize, 1), result.count);
        try t.expectEqual(@as(usize, 0), result.items[0].index);
        try t.expectEqual(wait.Reason.readable, result.items[0].reason);
        try t.expect(rig.publication_was_pending);
        try t.expectEqual(paint.Result.painted, try rig.drawing.probe(drawing));
        try t.expectEqual(@as(u64, 2), drawing.target); // later SHOW did not move target
        try t.expectEqual(@as(usize, if (position < 4) 0 else 1), rig.sleep_calls);
    }
}

test "1372 W09 sealed return excludes detach publication and next registration retains it" {
    var rig = Rig{ .boundary = .detach };
    rig.drawing.publish(true, true, 2, 0);
    var drawing = try rig.drawing.register(3, null);
    defer rig.drawing.unregister(&drawing);
    var registration = rig.registration();
    try registration.open(&.{rig.target()});
    const sealed = registration.poll();
    const generation = registration.generation;
    registration.close();
    try t.expectEqual(@as(usize, 0), sealed.count);
    try t.expectEqual(@as(usize, 0), rig.pins);
    try t.expectEqual(paint.Result.painted, try rig.drawing.probe(drawing));
    try registration.open(&.{rig.target()});
    defer registration.close();
    try t.expect(registration.generation > generation);
    try t.expectEqual(@as(usize, 1), registration.poll().count);
}

test "1372 W04 W05 W06 W14 coalesced hints preserve full set and independent flags" {
    var rig = Rig{};
    var token = base.Cancellation{};
    var registration = rig.registration();
    registration.cancellation = &token;
    try registration.open(&.{ rig.target(), rig.target(), .{ .kind = .clock, .identity = id, .at = 40 } });
    defer registration.close();
    for (0..8) |turn| {
        // Multiple publications, one retry hint. No notification count is used as work count.
        for (0..32) |_| try Rig.notify(&rig);
        rig.instant = @as(base.Instant, @intCast(turn)) * 10;
        const result = registration.poll();
        try t.expectEqual(@as(usize, if (turn < 4) 0 else 1), result.count);
        try t.expect(!result.expired);
        try t.expectEqual(@as(?base.Instant, 100), registration.deadline.at);
    }
    rig.ready = true;
    rig.instant = 100;
    try registration.requestCancellation();
    const result = registration.poll();
    try t.expect(result.cancelled and result.expired);
    try t.expectEqual(@as(usize, 3), result.count);
    try t.expectEqualSlices(usize, &.{ 0, 1, 2 }, &.{ result.items[0].index, result.items[1].index, result.items[2].index });
    try t.expectEqual(@as(usize, 18), rig.probes);
}

test "1372 W16 synthetic scheduler events retain quotas rotation and WAIT deadline" {
    var rig = Rig{};
    var registration = rig.registration();
    try registration.open(&.{rig.target()});
    defer registration.close();
    var start: usize = 0;
    var first: [schedule.source_count]bool = @splat(false);
    for (0..schedule.source_count) |turn| {
        rig.instant = @as(base.Instant, @intCast(turn)) * 20;
        const result = registration.poll();
        const decision = try schedule.turn(.{ .events = @splat(1000), .deadlines = &.{result.next.at.?} }, registration.clock, start);
        first[@backingInt(decision.order[0])] = true;
        for (decision.take, 0..) |n, index| try t.expectEqual(@as(usize, if (index == @backingInt(schedule.Source.completion)) 16 else 8), n);
        try t.expect(decision.next == .run_again); // Scheduler decision only; not connected to host_wait.sleep here
        try t.expectEqual(turn >= 5, result.expired);
        start = decision.next_start;
    }
    for (first) |visited| try t.expect(visited);
}
