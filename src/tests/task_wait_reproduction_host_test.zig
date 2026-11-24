const std = @import("std");
const t = std.testing;
const base = @import("../core/runtime_base.zig");
const wait = @import("../core/task_wait.zig");
const host_wait = @import("../host_task_wait.zig");
const q = @import("../core/task_queue.zig");
const Host = @import("../core/task_schedule_host.zig").Host;
const Wake = @import("../host_wake.zig").Wake;
const real = @import("../host_clock.zig").clock;

// Independent of the fake clock; covers native wait and cleanup on failures.
const Guard = struct {
    wake: Wake,
    done: base.Cancellation = .{},
    thread: ?std.Thread = null,
    fn start(self: *Guard) !void {
        self.* = .{ .wake = try Wake.init() };
        errdefer self.wake.deinit() catch {};
        self.thread = try std.Thread.spawn(.{}, watch, .{self});
    }
    fn watch(self: *Guard) void {
        const deadline = base.Deadline.afterMilliseconds(real.now() catch @panic("watchdog clock"), 20_000) catch unreachable;
        while (!self.done.isRequested()) {
            const observed = self.wake.observe();
            if (self.done.isRequested()) return;
            _ = self.wake.waitWithClock(observed, deadline, &self.done, real) catch @panic("watchdog wait");
            if (!self.done.isRequested() and deadline.expired(real.now() catch @panic("watchdog clock"))) @panic("1372 wait watchdog expired");
        }
    }
    fn end(self: *Guard) void {
        self.done.request();
        self.wake.notify() catch {};
        self.thread.?.join();
        self.wake.deinit() catch unreachable;
    }
};
const Clock = struct {
    instant: base.Instant = 0,
    fn now(p: ?*anyopaque) base.Error!base.Instant {
        const self: *Clock = @ptrCast(@alignCast(p.?));
        return self.instant;
    }
    fn clock(self: *Clock) base.Clock {
        return .{ .context = self, .now_fn = now };
    }
};
fn forbiddenRunner(_: ?*anyopaque, _: *q.Job) q.Result {
    @panic("test must not dispatch worker");
}

test "1372 T09 T10 production WAIT timeout interruption leave queue and ledger unchanged" {
    var guard: Guard = undefined;
    try guard.start();
    defer guard.end();
    var wake = try Wake.init();
    defer wake.deinit() catch unreachable;
    var clock = Clock{};
    var queue = try q.DefaultQueue.init(clock.clock(), wake.operations(), .{ .run_fn = forbiddenRunner });
    defer {
        queue.stop();
        queue.deinit() catch unreachable;
    }
    var host = try Host.init(&queue, 19);
    var job = q.Job{};
    const id = try host.submit(.{ .owner = 1, .kind = .io, .stream = 0, .input = .{ .bytes = "input" }, .job = &job, .milliseconds = 200 });
    var adapter = host_wait.Task(q.DefaultQueue){ .queue = &queue, .job = &job };
    var token = base.Cancellation{};
    var registration = wait.Registration{ .wake = wake.operations(), .clock = clock.clock(), .deadline = .{ .at = 100 }, .cancellation = &token };
    try registration.open(&.{.{ .kind = .task, .identity = id, .source = adapter.source() }});
    defer registration.close();
    const before = try host.ledger.inspect(id, 1);
    var result = host_wait.poll(&registration, false);
    try t.expect(!result.finished());
    // 1387 binding uses the real queue's deadline and preserves every source quota.
    const decision = try host.decide(.{ .events = @splat(100), .deadlines = &.{result.next.at.?} }, clock.instant, 3);
    try t.expect(decision.next == .run_again);
    try t.expectEqual(@import("../core/task_schedule.zig").Source.completion, decision.order[0]);
    for (decision.take) |count| try t.expect(count > 0);
    // Publish unrelated/coalesced notifications after probe, before native entry.
    for (0..64) |_| try wake.notify();
    try host_wait.sleep(&registration, result, &wake, &.{});
    result = host_wait.poll(&registration, false);
    try t.expect(!result.finished());
    clock.instant = 100;
    result = host_wait.poll(&registration, false);
    try t.expect(result.expired and !result.cancelled and !result.interrupted);
    try t.expectEqual(@as(usize, 0), result.count);
    registration.close();
    registration.deadline = .{ .at = 200 };
    try registration.open(&.{.{ .kind = .task, .identity = id, .source = adapter.source() }});
    result = host_wait.poll(&registration, true);
    try t.expect(result.interrupted and !result.cancelled and !result.expired);
    try registration.requestCancellation();
    clock.instant = 200;
    result = host_wait.poll(&registration, true);
    try t.expect(result.interrupted and result.cancelled and result.expired);
    try host.poll();
    const after = try host.ledger.inspect(id, 1);
    try t.expectEqual(before.state, after.state);
    try t.expectEqual(before.execution_ref, after.execution_ref);
    try t.expect(!job.cancellation.isRequested());
    try t.expect(job.terminal == null);
    try t.expectEqual(@as(usize, 1), queue.view().count);
    // Actual task cancellation (not WAIT cancellation) is terminal on this turn.
    queue.cancel(&job);
    result = host_wait.poll(&registration, false);
    try t.expectEqual(@as(usize, 1), result.count);
    try t.expectEqual(wait.Reason.cancelled, result.items[0].reason);
    try host.poll();
    try t.expectEqual(@import("../core/task_ledger.zig").State.cancelled, (try host.ledger.inspect(id, 1)).state);
}

test "1372 W07 W08 real queue expiry and released publication survive absent common notify" {
    var guard: Guard = undefined;
    try guard.start();
    defer guard.end();
    var wake = try Wake.init();
    defer wake.deinit() catch unreachable;
    var clock = Clock{};
    const Silent = struct {
        fn notify(_: ?*anyopaque) base.Error!void {}
    };
    var common = wake.operations();
    common.notify_fn = Silent.notify;
    var queue = try q.DefaultQueue.init(clock.clock(), common, .{ .run_fn = forbiddenRunner });
    defer {
        queue.stop();
        queue.deinit() catch unreachable;
    }
    var job = q.Job{};
    try queue.submit(&job, 1);
    var adapter = host_wait.Task(q.DefaultQueue){ .queue = &queue, .job = &job };
    var registration = wait.Registration{ .wake = wake.operations(), .clock = clock.clock(), .deadline = .{ .at = null } };
    try registration.open(&.{.{ .kind = .task, .identity = .{ .epoch = 1, .serial = 1 }, .source = adapter.source() }});
    defer registration.close();
    const before = registration.poll();
    try t.expectEqual(@as(?base.Instant, 1_000_000), before.next.at);
    const generation = wake.observe();
    clock.instant = 1_000_000;
    const result = registration.poll();
    try t.expect(!result.expired);
    try t.expectEqual(@as(usize, 1), result.count);
    try t.expectEqual(wait.Reason.failed, result.items[0].reason);
    try t.expectEqual(@as(i128, @backingInt((q.Result{ .kind = .failed, .reason = .queue_expired }).reason)), result.items[0].detail);
    try t.expectEqual(generation, wake.observe());
    queue.release(&job);
    try t.expectEqual(wait.Reason.released, registration.poll().items[0].reason);
    try t.expectEqual(wait.Reason.released, registration.poll().items[0].reason);
    try t.expectEqual(q.Result{ .kind = .failed, .reason = .queue_expired }, job.terminal.?);
    registration.close();
    try t.expect(!registration.active and registration.count == 0);
    const rejected_generation = registration.generation;
    const rejected_observed = registration.observed;
    const rejected_wake = wake.observe();
    try t.expectError(error.HostFailed, registration.open(&.{.{ .kind = .task, .identity = .{ .epoch = 1, .serial = 1 }, .source = adapter.source() }}));
    try t.expect(!registration.active and registration.count == 0);
    try t.expectEqual(rejected_generation, registration.generation);
    try t.expectEqual(rejected_observed, registration.observed);
    try t.expectEqual(rejected_wake, wake.observe());
}

test "1372 W01 W04 W06 production input task clock and paint retain simultaneous state" {
    var guard: Guard = undefined;
    try guard.start();
    defer guard.end();
    var wake = try Wake.init();
    defer wake.deinit() catch unreachable;
    var clock = Clock{ .instant = 50 };
    var queue = try q.DefaultQueue.init(clock.clock(), wake.operations(), .{ .run_fn = forbiddenRunner });
    defer queue.deinit() catch unreachable;
    const support = @import("support.zig");
    const input = @import("../host_input.zig");
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    const saved = input.input_is_terminal;
    input.input_is_terminal = false;
    defer input.input_is_terminal = saved;
    const Read = struct {
        fn read(_: ?*anyopaque, _: i32) @import("../forth.zig").RuntimeError!@import("../core/standard_event.zig").Result {
            return .timeout;
        }
    };
    machine.writer.standard_event_fn = Read.read;
    machine.writer.standard_clock = clock.clock();
    try machine.standard_input.putByte('Z');
    var input_adapter = host_wait.Input{ .machine = machine };
    var job = q.Job{ .phase = .sealed, .result = .{ .kind = .succeeded, .value = 42 } };
    job.ready.store(true, .release);
    var task_adapter = host_wait.Task(q.DefaultQueue){ .queue = &queue, .job = &job };
    var drawing = @import("../core/task_paint.zig").Source{};
    drawing.bind(wake.operations());
    defer drawing.bind(null);
    drawing.publish(true, true, 2, 0);
    var painted = try drawing.register(3, null);
    defer drawing.unregister(&painted);
    try t.expectEqual(@import("../core/task_paint.zig").Result.pending, try drawing.probe(painted));
    var token = base.Cancellation{};
    var registration = wait.Registration{ .wake = wake.operations(), .clock = clock.clock(), .deadline = .{ .at = 50 }, .cancellation = &token };
    const id = base.Handle{ .epoch = 1, .serial = 1 };
    try registration.open(&.{
        .{ .kind = .input, .identity = id, .source = input_adapter.source() },
        .{ .kind = .task, .identity = id, .source = task_adapter.source() },
        .{ .kind = .clock, .identity = id, .at = 50 },
    });
    defer registration.close();
    try t.expectEqual(@import("../core/task_paint.zig").Result.pending, try drawing.probe(painted));
    drawing.publish(true, true, 2, 2);
    try registration.requestCancellation();
    const result = host_wait.poll(&registration, true);
    try t.expectEqual(@as(usize, 3), result.count);
    try t.expectEqual(wait.Reason.input, result.items[0].reason);
    try t.expectEqual(wait.Reason.succeeded, result.items[1].reason);
    try t.expectEqual(wait.Reason.deadline, result.items[2].reason);
    try t.expect(result.cancelled and result.interrupted and result.expired);
    try t.expectEqual(@import("../core/task_paint.zig").Result.painted, try drawing.probe(painted));
    try t.expectEqual(@as(u8, 'Z'), machine.standard_input.takeByte().?);
    try t.expectEqual(@as(usize, 42), queue.poll(&job).?.value);
    try t.expectEqual(@as(usize, 42), queue.poll(&job).?.value);
    try t.expect(!job.cancellation.isRequested());
}

test "1372 T10 W08 release before terminal return reports released and reconciles cancelled" {
    var wake = try Wake.init();
    defer wake.deinit() catch unreachable;
    var clock = Clock{};
    var queue = try q.DefaultQueue.init(clock.clock(), wake.operations(), .{ .run_fn = forbiddenRunner });
    defer {
        queue.stop();
        queue.deinit() catch unreachable;
    }
    var host = try Host.init(&queue, 19);
    var job = q.Job{};
    const id = try host.submit(.{ .owner = 1, .kind = .io, .stream = 0, .input = .{ .bytes = "input" }, .job = &job, .milliseconds = 200 });
    var adapter = host_wait.Task(q.DefaultQueue){ .queue = &queue, .job = &job };
    var registration = wait.Registration{ .wake = wake.operations(), .clock = clock.clock(), .deadline = .{ .at = null } };
    try registration.open(&.{.{ .kind = .task, .identity = id, .source = adapter.source() }});
    defer registration.close();
    try t.expect(!registration.poll().finished());
    try t.expect(job.terminal == null);
    queue.release(&job);
    const result = registration.poll();
    try t.expectEqual(@as(usize, 1), result.count);
    try t.expectEqual(wait.Reason.released, result.items[0].reason);
    try t.expect(job.terminal.?.kind == .cancelled);
    try host.poll();
    try t.expectEqual(@import("../core/task_ledger.zig").State.cancelled, (try host.ledger.inspect(id, 1)).state);
}
