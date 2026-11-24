const std = @import("std");
const t = std.testing;
const Host = @import("../core/task_schedule_host.zig").Host;
const q = @import("../core/task_queue.zig");
const base = @import("../core/runtime_base.zig");
const context = @import("../core/task_context.zig");
const schedule = @import("../core/task_schedule.zig");

const Fake = struct {
    entered: std.atomic.Value(bool) = .init(false),
    proceed: std.atomic.Value(bool) = .init(false),
    submission_host: ?*Host = null,
    worker_denied: std.atomic.Value(bool) = .init(false),
    worker_job: q.Job = .{},
    instant: base.Instant = 0,
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
        while (!queue.joinIfStopped()) std.atomic.spinLoopHint();
        queue.deinit() catch unreachable;
    }
};
fn request(job: *q.Job, kind: schedule.Kind, stream: u64) Host.Request {
    return .{ .owner = 1, .kind = kind, .stream = stream, .input = .{ .bytes = "input" }, .job = job, .milliseconds = 50 };
}
fn awaitResult(host: *Host, job: *q.Job) !void {
    while (job.terminal == null) {
        try host.poll();
        std.atomic.spinLoopHint();
    }
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
    while (!fake.entered.load(.acquire)) std.atomic.spinLoopHint();
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
    while (!fake.entered.load(.acquire)) std.atomic.spinLoopHint();
    try host.markUnresponsive(id, 1);
    const waiting = try host.submit(request(&b, .game, 2));
    try t.expectEqual(@as(usize, 2), host.ledger.count());
    try t.expectError(error.WorkerOccupied, host.ledger.start(waiting, 1));
    try t.expect(!queue.wasAcquired(&b));
    fake.instant = 50 * std.time.ns_per_ms;
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
    while (!fake.entered.load(.acquire)) std.atomic.spinLoopHint();
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
