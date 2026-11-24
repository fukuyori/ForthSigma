const std = @import("std");
const q = @import("../core/task_queue.zig");
const base = @import("../core/runtime_base.zig");
const real = @import("../host_clock.zig").clock;
const Wake = @import("../host_wake.zig").Wake;
const t = std.testing;
const Fake = struct {
    ticks: std.atomic.Value(i64) = .init(0),
    fail_clock: std.atomic.Value(bool) = .init(false),
    calls: std.atomic.Value(usize) = .init(0),
    cleans: std.atomic.Value(usize) = .init(0),
    entered: std.atomic.Value(bool) = .init(false),
    proceed: std.atomic.Value(bool) = .init(false),
    block: bool = false,
    outcome: q.Result = .{ .kind = .succeeded, .value = 42 },
    fail_notify: bool = false,
    notices: std.atomic.Value(usize) = .init(0),
    fn cast(p: ?*anyopaque) *Fake {
        return @ptrCast(@alignCast(p.?));
    }
    fn now(p: ?*anyopaque) base.Error!base.Instant {
        const self = cast(p);
        if (self.fail_clock.load(.acquire)) return error.HostFailed;
        return self.ticks.load(.acquire);
    }
    fn observe(_: ?*anyopaque) u64 {
        return 0;
    } // deliberately coalesced
    fn notify(p: ?*anyopaque) base.Error!void {
        const self = cast(p);
        _ = self.notices.fetchAdd(1, .monotonic);
        if (self.fail_notify) return error.HostFailed;
    }
    fn wait(_: ?*anyopaque, _: u64, _: base.Deadline, _: ?*const base.Cancellation, _: base.Clock) base.Error!base.WakeOutcome {
        return .timeout;
    }
    fn clock(self: *Fake) base.Clock {
        return .{ .context = self, .now_fn = now };
    }
    fn ops(self: *Fake) base.WakeOps {
        return .{ .context = self, .observe_fn = observe, .notify_fn = notify, .wait_fn = wait };
    }
    fn run(p: ?*anyopaque, _: *q.Job) q.Result {
        const self = cast(p);
        _ = self.calls.fetchAdd(1, .monotonic);
        self.entered.store(true, .release);
        while (self.block and !self.proceed.load(.acquire)) std.atomic.spinLoopHint();
        return self.outcome;
    }
    fn cleanup(p: ?*anyopaque) void {
        _ = cast(p).cleans.fetchAdd(1, .monotonic);
    }
    fn runner(self: *Fake) q.JobRunner {
        return .{ .context = self, .run_fn = run };
    }
    fn job(self: *Fake) q.Job {
        return .{ .context = self, .cleanup_fn = cleanup };
    }
};
// Independent watchdog terminates the test process even if join or a gate hangs.
const Guard = struct {
    wake: Wake,
    done: std.atomic.Value(bool) = .init(false),
    thread: ?std.Thread = null,
    fn start(self: *Guard) !void {
        self.* = .{ .wake = try Wake.init() };
        self.thread = try std.Thread.spawn(.{}, watch, .{self});
    }
    fn watch(self: *Guard) void {
        const deadline = base.Deadline.afterMilliseconds(real.now() catch @panic("watchdog clock"), 20_000) catch unreachable;
        while (!self.done.load(.acquire)) {
            const observed = self.wake.observe();
            if (self.done.load(.acquire)) return;
            _ = self.wake.waitWithClock(observed, deadline, null, real) catch @panic("watchdog wait");
            if (deadline.expired(real.now() catch @panic("watchdog clock"))) @panic("task queue watchdog expired");
        }
    }
    fn end(self: *Guard) void {
        self.done.store(true, .release);
        self.wake.notify() catch {};
        self.thread.?.join();
        self.wake.deinit() catch {};
    }
};
fn finished(queue: anytype, job: *q.Job) q.Result {
    while (true) {
        if (queue.poll(job)) |result| return result;
        std.atomic.spinLoopHint();
    }
}
// Keep watchdog armed while unwinding an assertion failure with a live worker.
fn cleanupQueue(queue: anytype, fake: *Fake) void {
    if (queue.thread == null and queue.exited.load(.acquire)) return;
    fake.proceed.store(true, .release);
    queue.stop();
    while (!queue.joinIfStopped()) std.atomic.spinLoopHint();
    queue.deinit() catch {};
}
fn shutdown(queue: anytype) !void {
    queue.stop();
    while (!queue.joinIfStopped()) std.atomic.spinLoopHint();
    try queue.deinit();
}

test "task queue bounded waiting cancellation release expiry and next sweep publication" {
    var guard: Guard = undefined;
    try guard.start();
    defer guard.end();
    var fake = Fake{};
    var queue = try q.DefaultQueue.init(fake.clock(), fake.ops(), fake.runner());
    defer cleanupQueue(&queue, &fake);
    var jobs: [5]q.Job = undefined;
    for (&jobs) |*job| job.* = fake.job();
    for (jobs[0..4], 0..) |_, i| try queue.submit(&jobs[i], q.defaultWait(.g1));
    try t.expectError(error.QueueFull, queue.submit(&jobs[4], 50));
    queue.cancel(&jobs[0]);
    try t.expect(!jobs[0].ready.load(.acquire));
    try t.expectEqual(.cancelled, queue.poll(&jobs[0]).?.kind);
    queue.release(&jobs[1]);
    try t.expect(!jobs[1].external_valid);
    try t.expectEqual(.cancelled, finished(&queue, &jobs[1]).kind);
    fake.ticks.store(50_000_000, .release);
    try t.expectEqual(.queue_expired, finished(&queue, &jobs[2]).reason);
    try t.expectEqual(.queue_expired, finished(&queue, &jobs[3]).reason);
    try t.expectEqual(@as(usize, 4), fake.cleans.load(.acquire));
    try t.expectEqual(@as(usize, 0), fake.calls.load(.acquire));
    try queue.start();
    try shutdown(&queue);
}

test "task queue deterministic host win and worker win repeated; notification recovery and join" {
    var guard: Guard = undefined;
    try guard.start();
    defer guard.end();
    var fake = Fake{ .block = true, .fail_notify = true };
    var queue = try q.Queue(1).init(fake.clock(), fake.ops(), fake.runner());
    defer cleanupQueue(&queue, &fake);
    try queue.start();
    for (0..256) |_| {
        fake.entered.store(false, .release);
        fake.proceed.store(false, .release);
        var running = fake.job();
        try queue.submit(&running, 100);
        while (!fake.entered.load(.acquire)) std.atomic.spinLoopHint();
        // Running holds worker; host always wins the second item's dequeue.
        var waiting = fake.job();
        try queue.submit(&waiting, 100);
        queue.cancel(&waiting);
        try t.expectEqual(.cancelled, finished(&queue, &waiting).kind);
        queue.cancel(&running); // worker won: request must not replace success
        try t.expect(running.cancellation.isRequested());
        try t.expect(queue.poll(&running) == null);
        fake.proceed.store(true, .release);
        try t.expectEqual(@as(usize, 42), finished(&queue, &running).value);
        queue.cancel(&running);
        try t.expectEqual(.succeeded, queue.poll(&running).?.kind);
    }
    try shutdown(&queue);
    try t.expect(queue.notification_failed.load(.acquire));
    try t.expectEqual(@as(usize, 256), fake.calls.load(.acquire));
    try t.expectEqual(@as(usize, 512), fake.cleans.load(.acquire));
}

test "task queue deterministic cancellation before receipt and after runner entry" {
    var guard: Guard = undefined;
    try guard.start();
    defer guard.end();
    var fake = Fake{ .block = true };
    var queue = try q.Queue(1).init(fake.clock(), fake.ops(), fake.runner());
    defer cleanupQueue(&queue, &fake);
    var before = fake.job();
    try queue.submit(&before, 100);
    queue.cancel(&before);
    try t.expectEqual(.cancelled, finished(&queue, &before).kind);
    try queue.start();
    var after = fake.job();
    try queue.submit(&after, 100);
    while (!fake.entered.load(.acquire)) std.atomic.spinLoopHint();
    queue.cancel(&after);
    fake.proceed.store(true, .release);
    try t.expectEqual(.succeeded, finished(&queue, &after).kind);
    try shutdown(&queue);
    try t.expectEqual(@as(usize, 2), fake.cleans.load(.acquire));
    try t.expectEqual(@as(usize, 1), fake.calls.load(.acquire));
}

test "task queue unresponsive retains worker slot and stop retains running completion" {
    var guard: Guard = undefined;
    try guard.start();
    defer guard.end();
    var fake = Fake{ .block = true };
    var queue = try q.DefaultQueue.init(fake.clock(), fake.ops(), fake.runner());
    defer cleanupQueue(&queue, &fake);
    var job = fake.job();
    var waiting = fake.job();
    var accepted = fake.job();
    try queue.submit(&job, 100);
    try queue.start();
    while (!fake.entered.load(.acquire)) std.atomic.spinLoopHint();
    try queue.submit(&waiting, 200);
    queue.markUnresponsive();
    try queue.submit(&accepted, 50);
    try t.expect(!queue.wasAcquired(&accepted));
    queue.stop();
    try t.expect(!waiting.external_valid);
    try t.expect(!job.external_valid);
    try t.expectEqual(.cancelled, finished(&queue, &waiting).kind);
    try t.expect(!queue.joinIfStopped());
    try t.expectError(error.WorkerUnresponsive, queue.deinit());
    try t.expect(queue.poll(&job) == null);
    fake.proceed.store(true, .release);
    try t.expectEqual(.succeeded, finished(&queue, &job).kind);
    try shutdown(&queue);
}

test "task queue clock fault and per item deadlines are distinguishable" {
    var guard: Guard = undefined;
    try guard.start();
    defer guard.end();
    var fake = Fake{};
    var queue = try q.DefaultQueue.init(fake.clock(), fake.ops(), fake.runner());
    defer cleanupQueue(&queue, &fake);
    var first = fake.job();
    var second = fake.job();
    try t.expectError(error.ResultOutOfRange, queue.submit(&first, -1));
    try queue.submit(&first, 200);
    try queue.submit(&second, 0);
    try t.expectEqual(@as(?base.Instant, 0), queue.nextDeadline().at);
    try t.expectEqual(.queue_expired, finished(&queue, &second).reason);
    try t.expect(queue.poll(&first) == null);
    fake.fail_clock.store(true, .release);
    try t.expectEqual(.clock_failed, finished(&queue, &first).reason);
    fake.fail_clock.store(false, .release);
    try queue.start();
    try shutdown(&queue);
    try t.expectEqual(@as(i64, 50), q.defaultWait(.g1));
    try t.expectEqual(@as(i64, 100), q.defaultWait(.g2));
    try t.expectEqual(@as(i64, 100), q.defaultWait(.t1));
    try t.expectEqual(@as(i64, 200), q.defaultWait(.i1));
}

test "task queue worker expiry and runner failure cancellation preserve diagnostics" {
    var guard: Guard = undefined;
    try guard.start();
    defer guard.end();
    var fake = Fake{};
    var queue = try q.DefaultQueue.init(fake.clock(), fake.ops(), fake.runner());
    defer cleanupQueue(&queue, &fake);
    var expired = fake.job();
    try queue.submit(&expired, 50);
    fake.ticks.store(50_000_000, .release);
    try queue.start();
    // Wait on producer publication without a host expiry sweep.
    while (!expired.ready.load(.acquire)) std.atomic.spinLoopHint();
    try t.expectEqual(.queue_expired, finished(&queue, &expired).reason);
    try t.expectEqual(@as(usize, 0), fake.calls.load(.acquire));
    try shutdown(&queue);
    for ([_]q.Result{ .{ .kind = .failed, .reason = .runner, .value = 17 }, .{ .kind = .cancelled } }) |outcome| {
        var controlled = Fake{ .block = true, .outcome = outcome };
        var other = try q.DefaultQueue.init(controlled.clock(), controlled.ops(), controlled.runner());
        defer cleanupQueue(&other, &controlled);
        var job = controlled.job();
        try other.submit(&job, 100);
        try other.start();
        while (!controlled.entered.load(.acquire)) std.atomic.spinLoopHint();
        other.release(&job);
        controlled.proceed.store(true, .release);
        const result = finished(&other, &job);
        try t.expectEqualDeep(outcome, result);
        try shutdown(&other);
    }
}

const FaultWake = struct {
    wake: Wake,
    fake: *Fake,
    entered: std.atomic.Value(bool) = .init(false),
    proceed: std.atomic.Value(bool) = .init(false),
    fail_wait: bool = false,
    fn cast(p: ?*anyopaque) *FaultWake {
        return @ptrCast(@alignCast(p.?));
    }
    fn observe(p: ?*anyopaque) u64 {
        return cast(p).wake.observe();
    }
    fn notify(_: ?*anyopaque) base.Error!void {
        return error.HostFailed;
    }
    fn wait(p: ?*anyopaque, observed: u64, deadline: base.Deadline, token: ?*const base.Cancellation, clock: base.Clock) base.Error!base.WakeOutcome {
        const self = cast(p);
        self.entered.store(true, .release);
        if (self.fail_wait) {
            while (!self.proceed.load(.acquire)) std.atomic.spinLoopHint();
            return error.HostFailed;
        }
        return self.wake.waitWithClock(observed, deadline, token, clock);
    }
    fn ops(self: *FaultWake) base.WakeOps {
        return .{ .context = self, .observe_fn = observe, .notify_fn = notify, .wait_fn = wait };
    }
    fn hostNow(p: ?*anyopaque) base.Error!base.Instant {
        // Called by the real Wake wait after its generation check.
        cast(p).fake.proceed.store(true, .release);
        return real.now();
    }
};

test "task queue failed completion notify recovers from real host Wake wait" {
    var guard: Guard = undefined;
    try guard.start();
    defer guard.end();
    var fake = Fake{ .block = true };
    var host = FaultWake{ .wake = try Wake.init(), .fake = &fake };
    defer host.wake.deinit() catch {};
    var queue = try q.Queue(1).init(real, host.ops(), fake.runner());
    defer cleanupQueue(&queue, &fake);
    var job = fake.job();
    try queue.submit(&job, 1000);
    try queue.start();
    while (!fake.entered.load(.acquire)) std.atomic.spinLoopHint();
    const observed = host.wake.observe();
    try t.expect(queue.poll(&job) == null);
    const deadline = queue.nextDeadline();
    try t.expect(deadline.at != null);
    const wait_clock = base.Clock{ .context = &host, .now_fn = FaultWake.hostNow };
    try t.expectEqual(.timeout, try host.wake.waitWithClock(observed, deadline, null, wait_clock));
    try t.expectEqual(.succeeded, finished(&queue, &job).kind);
    while (!queue.notificationFailed()) std.atomic.spinLoopHint();
    try t.expect(queue.nextDeadline().at != null);
    try shutdown(&queue);
}

test "task queue private kick failure recovers and unstarted join succeeds" {
    var guard: Guard = undefined;
    try guard.start();
    defer guard.end();
    var fake = Fake{};
    var private = FaultWake{ .wake = try Wake.init(), .fake = &fake };
    defer private.wake.deinit() catch {};
    var queue = try q.Queue(1).init(fake.clock(), fake.ops(), fake.runner());
    defer cleanupQueue(&queue, &fake);
    try t.expect(queue.joinIfStopped());
    queue.worker_wake = private.ops();
    try queue.start();
    while (!private.entered.load(.acquire)) std.atomic.spinLoopHint();
    var job = fake.job();
    try queue.submit(&job, 100);
    try t.expectEqual(.succeeded, finished(&queue, &job).kind);
    try t.expect(queue.notificationFailed());
    try shutdown(&queue);
}

test "task queue worker clock and wait faults retain cause and fail queued work" {
    var guard: Guard = undefined;
    try guard.start();
    defer guard.end();
    for ([_]bool{ false, true }) |clock_failure| {
        var fake = Fake{};
        var private = FaultWake{ .wake = try Wake.init(), .fake = &fake, .fail_wait = true };
        defer private.wake.deinit() catch {};
        defer private.proceed.store(true, .release);
        var queue = try q.Queue(1).init(fake.clock(), fake.ops(), fake.runner());
        defer cleanupQueue(&queue, &fake);
        queue.worker_wake = private.ops();
        try queue.start();
        while (!private.entered.load(.acquire)) std.atomic.spinLoopHint();
        var job = fake.job();
        var rejected = fake.job();
        try queue.submit(&job, 100);
        private.proceed.store(true, .release);
        while (!queue.exited.load(.acquire)) std.atomic.spinLoopHint();
        try t.expectEqual(.worker_failed, finished(&queue, &job).reason);
        try t.expectEqual(error.HostFailed, queue.worker_failed.?);
        try t.expectError(error.WorkerFailed, queue.submit(&rejected, 100));
        try shutdown(&queue);
        if (clock_failure) {
            var other = try q.Queue(1).init(fake.clock(), fake.ops(), fake.runner());
            defer cleanupQueue(&other, &fake);
            var broken = Fake{};
            broken.fail_clock.store(true, .release);
            other.worker_clock = broken.clock();
            try other.start();
            while (!other.exited.load(.acquire)) std.atomic.spinLoopHint();
            try t.expectEqual(error.HostFailed, other.worker_failed.?);
            try t.expectError(error.WorkerFailed, other.submit(&rejected, 100));
            try shutdown(&other);
        }
    }
}
