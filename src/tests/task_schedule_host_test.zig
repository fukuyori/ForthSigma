const std = @import("std");
const t = std.testing;
const Host = @import("../core/task_schedule_host.zig").Host;
const q = @import("../core/task_queue.zig");
const base = @import("../core/runtime_base.zig");
const context = @import("../core/task_context.zig");
const schedule = @import("../core/task_schedule.zig");

const Fake = struct {
    released: std.atomic.Value(usize) = .init(0),
    entered: std.atomic.Value(bool) = .init(false),
    proceed: std.atomic.Value(bool) = .init(false),
    submission_host: ?*Host = null,
    worker_denied: std.atomic.Value(bool) = .init(false),
    worker_job: q.Job = .{},
    instant: base.Instant = 0,
    fn releaseResources(p: ?*anyopaque) void {
        const self: *Fake = @ptrCast(@alignCast(p.?));
        _ = self.released.fetchAdd(1, .release);
    }
    fn now(p: ?*anyopaque) base.Error!base.Instant {
        const self: *Fake = @ptrCast(@alignCast(p.?));
        return self.instant;
    }
    fn observe(_: ?*anyopaque) u64 {
        return 0;
    }
    fn notify(_: ?*anyopaque) base.Error!void {}
    fn wait(_: ?*anyopaque, _: u64, _: base.Deadline, _: ?*const base.Cancellation, _: base.Clock) base.Error!base.WakeOutcome {
        return .timeout;
    }
    fn run(p: ?*anyopaque, _: *q.Job) q.Result {
        const self: *Fake = @ptrCast(@alignCast(p.?));
        if (self.submission_host) |host| {
            _ = host.submit(request(&self.worker_job, .game, 99)) catch |err| {
                self.worker_denied.store(err == error.Denied, .release);
                return .{ .kind = .succeeded, .value = 42 };
            };
        }
        self.entered.store(true, .release);
        while (!self.proceed.load(.acquire)) std.atomic.spinLoopHint();
        // Deliberately succeed even after a cancellation request.
        return .{ .kind = .succeeded, .value = 42 };
    }
    fn init(self: *Fake) !q.DefaultQueue {
        return q.DefaultQueue.init(.{ .context = self, .now_fn = now }, .{ .context = null, .observe_fn = observe, .notify_fn = notify, .wait_fn = wait }, .{ .context = self, .run_fn = run });
    }
    fn cleanup(self: *Fake, queue: *q.DefaultQueue) void {
        self.proceed.store(true, .release);
        queue.stop();
        for (0..10_000_000) |_| {
            if (queue.joinIfStopped()) break;
            std.atomic.spinLoopHint();
        } else @panic("worker cleanup iteration limit");
        queue.deinit() catch unreachable;
    }
};

test "stop deadlines retain resources and late handback restores worker" {
    var fake: Fake = .{};
    var queue = try fake.init();
    defer fake.cleanup(&queue);
    var host = try Host.init(&queue, 1);
    var a: q.Job = .{ .context = &fake, .cleanup_fn = Fake.releaseResources };
    var b: q.Job = .{};
    const id = try host.submit(request(&a, .game, 1));
    try queue.start();
    try awaitEntered(&fake);
    try host.requestCancel(id, 1, 0);
    fake.instant = 10 * std.time.ns_per_ms;
    try host.poll();
    try t.expect(!(try host.stopDiagnostic(id, 1)).?.stop_exceeded);
    fake.instant += 1;
    try host.poll();
    try host.requestCancel(id, 1, fake.instant);
    const diagnostic = (try host.stopDiagnostic(id, 1)).?;
    try t.expectEqual(@as(base.Instant, 0), diagnostic.requested_at);
    try t.expect(diagnostic.stop_exceeded and !diagnostic.stopped);
    try t.expectEqual(@as(usize, 0), fake.released.load(.acquire));
    try t.expect((try host.ledger.inspect(id, 1)).stop_unconfirmed);
    try t.expectError(error.ReferencesRemain, host.collect(id, 1));
    const next = try host.submit(request(&b, .game, 2));
    try t.expectError(error.WorkerOccupied, host.ledger.start(next, 1));
    try t.expect(!queue.wasAcquired(&b));
    fake.proceed.store(true, .release);
    try awaitResult(&host, &a);
    try awaitResult(&host, &b);
    try t.expectEqual(@as(usize, 1), fake.released.load(.acquire));
    try t.expect(!(try host.ledger.inspect(id, 1)).stop_unconfirmed);
    try t.expect((try host.stopDiagnostic(id, 1)).?.stopped);
    try host.collect(id, 1);
    try host.collect(next, 1);
    try host.ledger.checkWorkerAvailable();
}

test "shutdown preserves active storage and reports fatal exit until late return" {
    const fatal = @import("../host_task_stop.zig");
    var fake: Fake = .{};
    var queue = try fake.init();
    defer fake.cleanup(&queue);
    var host = try Host.init(&queue, 1);
    var job: q.Job = .{ .context = &fake, .cleanup_fn = Fake.releaseResources };
    const id = try host.submit(request(&job, .game, 1));
    try queue.start();
    try awaitEntered(&fake);
    try host.beginShutdown(0);
    try t.expectEqual(.waiting, try host.shutdownStatus());
    fake.instant = 100 * std.time.ns_per_ms + 1;
    try t.expectEqual(.resources_active, try host.shutdownStatus());
    try t.expect((try host.stopDiagnostic(id, 1)).?.collection_exceeded);
    try t.expectEqual(@as(usize, 0), fake.released.load(.acquire));
    try t.expectError(error.WorkerUnresponsive, queue.deinit());
    try t.expectEqual(@as(u8, 1), fatal.exit_code);
    try t.expect(std.mem.indexOf(u8, fatal.message, "runtime resources remain active") != null);
    fake.proceed.store(true, .release);
    for (0..10_000_000) |_| {
        if (try host.shutdownStatus() == .joined) break;
        std.atomic.spinLoopHint();
    } else return error.Timeout;
    try t.expectEqual(@as(usize, 1), fake.released.load(.acquire));
    try t.expectEqual(.succeeded, (try host.ledger.inspect(id, 1)).state);
    // RELEASEd metadata stays internal until all owners release their refs.
    try host.collect(id, 1);
}
fn request(job: *q.Job, kind: schedule.Kind, stream: u64) Host.Request {
    return .{ .owner = 1, .kind = kind, .stream = stream, .input = .{ .bytes = "input" }, .job = job, .milliseconds = 50 };
}

test "three rapid replacements survive coalesced wakes and cancelled runner handback" {
    // The runner barrier fixes acquisition before the three host submissions.
    // Fake.notify deliberately drops EVERY common notification: polling must
    // reconcile persistent state, not count wake events.
    for ([_]bool{ false, true }) |observe_running| {
        var fake: Fake = .{};
        var queue = try fake.init();
        defer fake.cleanup(&queue);
        var host = try Host.init(&queue, 1);
        var jobs: [4]q.Job = @splat(.{});
        for (&jobs) |*job| job.* = .{ .context = &fake, .cleanup_fn = Fake.releaseResources };
        var ids: [4]base.Handle = undefined;
        ids[0] = try host.submit(request(&jobs[0], .game, 7));
        try queue.start();
        try awaitEntered(&fake);
        if (observe_running) try host.poll();
        for (1..4) |i| {
            ids[i] = try host.submit(request(&jobs[i], .game, 7));
            // Same external-ID lifetime as TC-SUBMIT, including repeated
            // cancellation of the acquired generation during replacement.
            try host.release(ids[i - 1], 1);
        }
        try t.expectEqual(@as(u64, 4), host.generation);
        const view = queue.view();
        try t.expectEqual(@as(usize, 1), view.count);
        try t.expect(view.active == &jobs[0]);
        try t.expect(view.waiting[0] == &jobs[3]);
        try t.expectEqual(@as(usize, 2), fake.released.load(.acquire));
        for (jobs[0..3]) |*job| try t.expect(job.cancellation.isRequested());
        try t.expect(!jobs[3].cancellation.isRequested());
        fake.proceed.store(true, .release);
        try awaitResult(&host, &jobs[3]);
        // A queue result alone is insufficient: assert host reconciliation and
        // the application boundary too, before and after collecting old IDs.
        try host.poll();
        try t.expectEqual(.succeeded, (try host.ledger.lookup(ids[3], 1)).state);
        for (ids[0..3]) |id| try host.collect(id, 1);
        try t.expect((try host.takeResult(ids[3], 1)) != null);
        try t.expect((try host.takeResult(ids[3], 1)) == null);
        try host.ledger.checkWorkerAvailable();
        try t.expectEqual(@as(usize, 4), fake.released.load(.acquire));
        try host.collect(ids[3], 1);
    }
}

test "three replacements when worker acquires the proposed waiting replacement" {
    const Race = struct {
        entered: std.atomic.Value(usize) = .init(0),
        permits: std.atomic.Value(usize) = .init(0),
        host_reads: usize = 0,
        armed: bool = false,
        fn now(raw: ?*anyopaque) base.Error!base.Instant {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            if (!context.isWorkerThread() and self.armed) {
                self.host_reads += 1;
                // Host.submit has captured its View and proposed replacing B.
                // Queue.submitReplacing calls now before taking its gate.
                if (self.host_reads == 2) {
                    self.permits.store(1, .release);
                    for (0..10_000_000) |_| {
                        if (self.entered.load(.acquire) == 2) break;
                        std.atomic.spinLoopHint();
                    } else return error.HostFailed;
                }
            }
            return 0;
        }
        fn run(raw: ?*anyopaque, job: *q.Job) q.Result {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            const ticket = self.entered.fetchAdd(1, .acq_rel) + 1;
            while (self.permits.load(.acquire) < ticket) std.atomic.spinLoopHint();
            return .{ .kind = if (job.cancellation.isRequested()) .cancelled else .succeeded };
        }
    };
    var race: Race = .{};
    var queue = try q.DefaultQueue.init(.{ .context = &race, .now_fn = Race.now }, .{ .context = null, .observe_fn = Fake.observe, .notify_fn = Fake.notify, .wait_fn = Fake.wait }, .{ .context = &race, .run_fn = Race.run });
    // Suppress private notifications as well. A timeout is a legal coalescing
    // backend outcome; dispatch must always recheck the queue predicate.
    queue.worker_wake = .{ .context = null, .observe_fn = Fake.observe, .notify_fn = Fake.notify, .wait_fn = Fake.wait };
    defer {
        race.permits.store(std.math.maxInt(usize), .release);
        queue.stop();
        for (0..10_000_000) |_| {
            if (queue.joinIfStopped()) break;
            std.atomic.spinLoopHint();
        } else @panic("replacement race cleanup iteration limit");
        queue.deinit() catch unreachable;
    }
    var host = try Host.init(&queue, 1);
    var jobs: [4]q.Job = @splat(.{});
    var ids: [4]base.Handle = undefined;
    ids[0] = try host.submit(request(&jobs[0], .game, 7));
    try queue.start();
    for (0..10_000_000) |_| {
        if (race.entered.load(.acquire) == 1) break;
        std.atomic.spinLoopHint();
    } else return error.Timeout;
    try host.poll();
    ids[1] = try host.submit(request(&jobs[1], .game, 7));
    try host.release(ids[0], 1);
    race.armed = true;
    ids[2] = try host.submit(request(&jobs[2], .game, 7));
    race.armed = false;
    try host.release(ids[1], 1);
    ids[3] = try host.submit(request(&jobs[3], .game, 7));
    try host.release(ids[2], 1);
    try t.expect(queue.wasAcquired(&jobs[1]));
    try t.expect(!queue.wasAcquired(&jobs[2]));
    try t.expectEqual(@as(usize, 1), queue.view().count);
    try t.expect(queue.view().waiting[0] == &jobs[3]);
    try t.expect(!jobs[3].cancellation.isRequested());
    race.permits.store(std.math.maxInt(usize), .release);
    try awaitResult(&host, &jobs[3]);
    try host.poll();
    try t.expectEqual(.succeeded, (try host.ledger.lookup(ids[3], 1)).state);
    for (ids[0..3]) |id| try host.collect(id, 1);
    try t.expect((try host.takeResult(ids[3], 1)) != null);
    try host.collect(ids[3], 1);
    try host.ledger.checkWorkerAvailable();
}
fn awaitResult(host: *Host, job: *q.Job) !void {
    for (0..10_000_000) |_| {
        try host.poll();
        if (job.terminal != null) return;
        std.atomic.spinLoopHint();
    }
    return error.Timeout;
}
test "schedule binding derives worker and dependency denial without caller flags" {
    var fake: Fake = .{};
    var queue = try fake.init();
    defer fake.cleanup(&queue);
    var host = try Host.init(&queue, 1);
    var job: q.Job = .{};
    var token: base.Cancellation = .{};
    {
        var scope: context.Context = undefined;
        scope.enter(&job, &token);
        defer scope.leave();
        try t.expectError(error.Denied, host.submit(request(&job, .game, 1)));
    }
    try t.expectEqual(@as(usize, 0), host.ledger.count());
    const id = try host.submit(request(&job, .game, 1));
    var second: q.Job = .{};
    var dependent = request(&second, .game, 2);
    dependent.input = .{ .task_result = id };
    try t.expectError(error.Denied, host.submit(dependent));
    dependent.owner = 2;
    try t.expectError(error.WrongOwner, host.submit(dependent));
    dependent.owner = 1;
    dependent.input = .{ .task_result = .{ .epoch = 2, .serial = id.serial } };
    try t.expectError(error.InvalidHandle, host.submit(dependent));
    try t.expectEqual(@as(usize, 1), host.ledger.count());
}
test "schedule binding replaces FIFO cancels real queue and keeps failure atomic" {
    var fake: Fake = .{};
    var queue = try fake.init();
    defer fake.cleanup(&queue);
    var host = try Host.init(&queue, 1);
    var jobs: [6]q.Job = @splat(.{});
    const a = try host.submit(request(&jobs[0], .io, 0));
    const old = try host.submit(request(&jobs[1], .game, 1));
    _ = try host.submit(request(&jobs[2], .io, 0));
    _ = try host.submit(request(&jobs[3], .io, 0));
    const newest = try host.submit(request(&jobs[4], .game, 1));
    try t.expect(queue.view().waiting[1] == &jobs[4]);
    try t.expect(jobs[1].cancellation.isRequested());
    try host.poll();
    try t.expectEqual(@import("../core/task_ledger.zig").State.cancelled, (try host.ledger.lookup(old, 1)).state);
    var invalid = request(&jobs[5], .game, 1);
    invalid.milliseconds = -1;
    const generation = host.generation;
    try t.expectError(error.ResultOutOfRange, host.submit(invalid));
    try t.expectEqual(generation, host.generation);
    try t.expect(!jobs[4].cancellation.isRequested());
    try t.expect(queue.view().waiting[1] == &jobs[4]);
    try t.expectEqual(@as(usize, 5), host.ledger.count());
    _ = a;
    _ = newest;
}
test "schedule binding rejects stale late success and completed results after replacement" {
    var fake: Fake = .{};
    var queue = try fake.init();
    defer fake.cleanup(&queue);
    var host = try Host.init(&queue, 1);
    var jobs: [4]q.Job = @splat(.{});
    const old = try host.submit(request(&jobs[0], .game, 1));
    try queue.start();
    try awaitEntered(&fake);
    try host.poll();
    const newest = try host.submit(request(&jobs[1], .game, 1));
    try t.expect(jobs[0].cancellation.isRequested());
    try t.expect((try host.ledger.lookup(old, 1)).cancel_requested);
    fake.proceed.store(true, .release);
    try awaitResult(&host, &jobs[1]);
    try t.expectEqual(@import("../core/task_ledger.zig").State.succeeded, (try host.ledger.lookup(old, 1)).state);
    try t.expectError(error.InvalidTransition, host.stage(old, 1, .{ .result = &.{}, .result_copy = &.{} }));
    try t.expectEqual(@as(?q.Result, null), try host.takeResult(old, 1));
    try t.expectEqual(@as(usize, 42), (try host.takeResult(newest, 1)).?.value);
    try t.expectEqual(@as(?q.Result, null), try host.takeResult(newest, 1));
    const late = try host.submit(request(&jobs[2], .game, 1));
    try awaitResult(&host, &jobs[2]);
    const latest = try host.submit(request(&jobs[3], .game, 1));
    try t.expectEqual(@as(?q.Result, null), try host.takeResult(late, 1));
    try awaitResult(&host, &jobs[3]);
    try t.expect((try host.takeResult(latest, 1)) != null);
    try host.collect(latest, 1);
    try t.expectEqual(@as(?q.Result, null), try host.takeResult(late, 1));
}
test "schedule binding ledger exhaustion throttles reads and collection resumes admission" {
    var fake: Fake = .{};
    var queue = try fake.init();
    defer fake.cleanup(&queue);
    var host = try Host.init(&queue, 1);
    var jobs: [17]q.Job = @splat(.{});
    var ids: [16]base.Handle = undefined;
    // Replacement leaves cancelled terminal records unreclaimed, even with one waiting.
    for (&ids, 0..) |*id, i| {
        id.* = try host.submit(request(&jobs[i], .game, 1));
        try host.poll();
    }
    const generation = host.generation;
    try t.expectError(error.ResourceFull, host.submit(request(&jobs[16], .game, 1)));
    try t.expectEqual(generation, host.generation);
    var events: [schedule.source_count]usize = @splat(1);
    var d = try host.decide(.{ .events = events }, 0, 0);
    try t.expect(d.pause_compute_reads and d.io_read_bytes == 0 and d.io_drain_bytes != 0);
    try host.collect(ids[0], 1);
    events[@backingInt(schedule.Source.io_read)] = 1;
    d = try host.decide(.{ .events = events }, 0, 0);
    try t.expect(!d.pause_compute_reads and d.io_read_bytes != 0);
    _ = try host.submit(request(&jobs[16], .game, 1));
}
test "schedule binding stopped-unconfirmed VM accepts waiting work and expires it" {
    var fake: Fake = .{};
    var queue = try fake.init();
    defer fake.cleanup(&queue);
    var host = try Host.init(&queue, 1);
    var a: q.Job = .{};
    var b: q.Job = .{};
    const id = try host.submit(request(&a, .game, 1));
    try queue.start();
    try awaitEntered(&fake);
    try host.requestCancel(id, 1, 0);
    fake.instant = 10 * std.time.ns_per_ms + 1;
    try host.poll();
    const waiting = try host.submit(request(&b, .game, 2));
    try t.expectEqual(@as(usize, 2), host.ledger.count());
    try t.expectError(error.WorkerOccupied, host.ledger.start(waiting, 1));
    try t.expect(!queue.wasAcquired(&b));
    fake.instant += 50 * std.time.ns_per_ms;
    try host.poll();
    try t.expectEqual(.queue_expired, b.terminal.?.reason);
    try t.expectEqual(.failed, (try host.ledger.lookup(waiting, 1)).state);
}

test "schedule binding bounds combined copies and gates final publication by generation" {
    var fake: Fake = .{};
    fake.proceed.store(true, .release);
    var queue = try fake.init();
    defer fake.cleanup(&queue);
    var host = try Host.init(&queue, 1);
    var jobs: [3]q.Job = @splat(.{});
    const id = try host.submit(request(&jobs[0], .game, 1));
    try queue.start();
    try awaitResult(&host, &jobs[0]);
    const source = try t.allocator.alloc(u8, 512 * 1024);
    defer t.allocator.free(source);
    const target = try t.allocator.alloc(u8, source.len);
    defer t.allocator.free(target);
    @memset(source, 7);
    @memset(target, 0);
    const diagnostic: [16 * 1024]u8 = @splat(3);
    var diag_target: [16 * 1024]u8 = @splat(0);
    try host.stage(id, 1, .{ .result = source, .result_copy = target, .diagnostic = &diagnostic, .diagnostic_copy = &diag_target });
    for (0..5) |_| {
        try t.expectEqual(@as(usize, 96 * 1024), try host.copyTurn());
        try t.expectEqual(@as(?q.Result, null), try host.takeResult(id, 1));
    }
    try t.expectEqual(@as(usize, 48 * 1024), try host.copyTurn());
    try t.expectEqualSlices(u8, source, target);
    try t.expectEqualSlices(u8, &diagnostic, &diag_target);
    try t.expect((try host.takeResult(id, 1)) != null);

    const old = try host.submit(request(&jobs[1], .game, 1));
    try awaitResult(&host, &jobs[1]);
    @memset(target, 0);
    try host.stage(old, 1, .{ .result = source, .result_copy = target });
    _ = try host.copyTurn();
    _ = try host.submit(request(&jobs[2], .game, 1));
    try t.expectEqual(@as(usize, 0), try host.copyTurn());
    try t.expectEqual(@as(u8, 0), target[96 * 1024]);
    try t.expectEqual(@as(?q.Result, null), try host.takeResult(old, 1));
}

test "schedule binding owner kind and stream isolate replacement and copying" {
    var fake: Fake = .{};
    fake.proceed.store(true, .release);
    var queue = try fake.init();
    defer fake.cleanup(&queue);
    var host = try Host.init(&queue, 1);
    host.copy_bytes = 16 * 1024;
    var jobs: [4]q.Job = @splat(.{});
    const a = try host.submit(request(&jobs[0], .game, 1));
    var other = request(&jobs[1], .game, 1);
    other.owner = 2;
    const b = try host.submit(other);
    const c = try host.submit(request(&jobs[2], .tui, 1));
    const d = try host.submit(request(&jobs[3], .game, 2));
    for (jobs) |job| try t.expect(!job.cancellation.isRequested());
    try queue.start();
    for (&jobs) |*job| try awaitResult(&host, job);
    const source: [10 * 1024]u8 = @splat(4);
    var targets: [4][10 * 1024]u8 = @splat(@splat(0));
    const ids = [_]base.Handle{ a, b, c, d };
    for (ids, 0..) |id, i| try host.stage(id, if (i == 1) 2 else 1, .{ .result = &source, .result_copy = &targets[i] });
    try t.expectEqual(@as(usize, 16 * 1024), try host.copyTurn());
    try t.expectEqualSlices(u8, &source, &targets[0]);
    try t.expectEqual(@as(u8, 4), targets[1][6 * 1024 - 1]);
    try t.expectEqual(@as(u8, 0), targets[1][6 * 1024]);
    try t.expectEqual(@as(u8, 0), targets[2][0]);
}

test "schedule queue acquisition race preserves old work when append fails" {
    var fake: Fake = .{};
    var queue = try fake.init();
    defer fake.cleanup(&queue);
    var old: q.Job = .{};
    var jobs: [5]q.Job = @splat(.{});
    try queue.submit(&old, 50);
    try queue.start();
    try awaitEntered(&fake);
    for (jobs[0..4]) |*job| try queue.submit(job, 50);
    try t.expectError(error.QueueFull, queue.submitReplacing(&jobs[4], 50, &old));
    try t.expect(!old.cancellation.isRequested());
    try t.expect(jobs[4].phase == .fresh);
    try t.expect(!queue.markUnresponsiveFor(&jobs[4]));
    try t.expect(!old.cancellation.isRequested());
    queue.cancel(&jobs[1]);
    try queue.submitReplacing(&jobs[4], 50, &old);
    const view = queue.view();
    try t.expectEqual(@as(usize, 4), view.count);
    try t.expect(view.waiting[0] == &jobs[0] and view.waiting[1] == &jobs[2] and view.waiting[3] == &jobs[4]);
}

test "schedule binding splits result diagnostic boundary within shared copy budget" {
    var fake: Fake = .{};
    fake.proceed.store(true, .release);
    var queue = try fake.init();
    defer fake.cleanup(&queue);
    var host = try Host.init(&queue, 1);
    host.copy_bytes = 16 * 1024;
    var job: q.Job = .{};
    const id = try host.submit(request(&job, .tui, 1));
    try queue.start();
    try awaitResult(&host, &job);
    const source: [16 * 1024 - 1]u8 = @splat(5);
    var target: [source.len]u8 = @splat(0);
    var diag: [2]u8 = @splat(0);
    var extra: [3]u8 = @splat(0);
    try host.stage(id, 1, .{ .result = &source, .result_copy = &target, .diagnostic = &.{ 8, 9 }, .diagnostic_copy = &diag, .extra_diagnostics = .{ &.{10}, &.{11}, &.{12} }, .extra_diagnostic_copies = .{ extra[0..1], extra[1..2], extra[2..3] } });
    try t.expectEqual(@as(usize, 16 * 1024), try host.copyTurn());
    try t.expectEqualSlices(u8, &.{ 8, 0 }, &diag);
    try t.expectEqual(@as(?q.Result, null), try host.takeResult(id, 1));
    const decision = try host.decide(.{}, 0, 0);
    try t.expect(decision.next == .run_again);
    try t.expectEqual(@as(usize, 4), try host.copyTurn());
    try t.expectEqualSlices(u8, &.{ 8, 9 }, &diag);
    try t.expectEqualSlices(u8, &.{ 10, 11, 12 }, &extra);
    try t.expect((try host.takeResult(id, 1)) != null);
}

test "schedule binding rejects real worker runner outside any Forth execution scope" {
    var fake: Fake = .{};
    var queue = try fake.init();
    defer fake.cleanup(&queue);
    var host = try Host.init(&queue, 1);
    fake.submission_host = &host;
    var job: q.Job = .{};
    _ = try host.submit(request(&job, .game, 1));
    try queue.start();
    try awaitResult(&host, &job);
    try t.expect(fake.worker_denied.load(.acquire));
    try t.expectEqual(@as(usize, 1), host.ledger.count());
}

test "schedule binding rejects foreign queue jobs without undefined behavior" {
    var fake: Fake = .{};
    var queue = try fake.init();
    defer fake.cleanup(&queue);
    var host = try Host.init(&queue, 1);
    var foreign: q.Job = .{};
    var own: q.Job = .{};
    try queue.submit(&foreign, 50);
    try t.expectError(error.InvalidJob, host.submit(request(&own, .io, 0)));
    try t.expectError(error.InvalidJob, host.decide(.{}, 0, 0));
    try t.expectEqual(@as(usize, 0), host.ledger.count());
}

fn awaitEntered(fake: *Fake) !void {
    for (0..10_000_000) |_| {
        if (fake.entered.load(.acquire)) return;
        std.atomic.spinLoopHint();
    }
    return error.Timeout;
}

test "shutdown deadline ignores old stopped cancellation diagnostic" {
    var fake: Fake = .{};
    var queue = try fake.init();
    defer fake.cleanup(&queue);
    var host = try Host.init(&queue, 1);
    var old: q.Job = .{};
    const old_id = try host.submit(request(&old, .io, 0));
    try host.requestCancel(old_id, 1, 0);
    try host.poll();
    fake.instant = 200 * std.time.ns_per_ms;
    try host.poll();
    try t.expect((try host.stopDiagnostic(old_id, 1)).?.collection_exceeded);
    var active: q.Job = .{};
    const active_id = try host.submit(request(&active, .io, 0));
    try queue.start();
    try awaitEntered(&fake);
    try host.release(active_id, 1);
    try host.beginShutdown(fake.instant);
    try t.expectEqual(.waiting, try host.shutdownStatus());
    try t.expect((try host.stopDiagnostic(active_id, 1)) != null);
    fake.instant += 100 * std.time.ns_per_ms + 1;
    try t.expectEqual(.resources_active, try host.shutdownStatus());
    fake.proceed.store(true, .release);
    try awaitResult(&host, &active);
    try host.collect(old_id, 1);
    try host.collect(active_id, 1);
}

test "handback synchronization rejects stale unresponsive mark before collection" {
    var fake: Fake = .{};
    var queue = try fake.init();
    defer fake.cleanup(&queue);
    var host = try Host.init(&queue, 1);
    var old: q.Job = .{};
    var next: q.Job = .{};
    const id = try host.submit(request(&old, .io, 0));
    try queue.start();
    try awaitEntered(&fake); // deterministic runner barrier before handback
    try t.expect(queue.markUnresponsiveFor(&old));
    fake.proceed.store(true, .release);
    try awaitResult(&host, &old); // acquire handback before the second ordering
    fake.entered.store(false, .release);
    fake.proceed.store(false, .release);
    _ = try host.submit(request(&next, .io, 0));
    try awaitEntered(&fake); // newer acquisition held at the fake runner barrier
    try t.expect(!queue.markUnresponsiveFor(&old));
    try host.collect(id, 1);
    try t.expect(!next.cancellation.isRequested());
}
