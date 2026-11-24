const std = @import("std");
const q = @import("../core/task_queue.zig");
const base = @import("../core/runtime_base.zig");
const ledger = @import("../core/task_ledger.zig");
const Binding = @import("../core/task_cancel.zig").Binding;
const Execution = @import("../core/task_job_queue.zig").Execution;
const snapshot = @import("../core/task_snapshot.zig");
const support = @import("support.zig");
const a = std.testing.allocator;
const Fake = struct {
    fn now(_: ?*anyopaque) base.Error!base.Instant {
        return 0;
    }
    fn observe(_: ?*anyopaque) u64 {
        return 0;
    }
    fn notify(_: ?*anyopaque) base.Error!void {}
    fn wait(_: ?*anyopaque, _: u64, _: base.Deadline, _: ?*const base.Cancellation, _: base.Clock) base.Error!base.WakeOutcome {
        return .timeout;
    }
    fn ops() base.WakeOps {
        return .{ .context = null, .observe_fn = observe, .notify_fn = notify, .wait_fn = wait };
    }
};

test "1373 queued cancellation latches ledger and task token and consumes pending admission" {
    var output = support.Output{};
    const vm = try support.createMachine(&output);
    defer support.destroyMachine(vm);
    try vm.interpretLine(": JOB ;");
    var manager = snapshot.Manager{};
    const version = try manager.capture(a, vm);
    defer version.release();
    var execution: Execution = .{ .allocator = a, .admission = try version.admit(vm), .entry = "JOB", .input = "abc" };
    defer execution.deinit();
    var item = execution.queued();
    var queue = try q.DefaultQueue.init(.{ .context = null, .now_fn = Fake.now }, Fake.ops(), Execution.runner());
    defer queue.deinit() catch unreachable;
    var table = try ledger.DefaultLedger.init(1);
    const id = try table.register(1);
    try queue.submit(&item, 50);
    try table.publish(id, 1);
    const binding: Binding = .{ .id = id, .owner = 1, .job = &item };
    try binding.cancel(&table, &queue);
    try std.testing.expect(item.cancellation.isRequested());
    try std.testing.expect((try table.lookup(id, 1)).cancel_requested);
    try std.testing.expect(execution.admission == null);
    try std.testing.expectEqual(@as(usize, 1), version.references.load(.acquire));
    try std.testing.expectEqual(.cancelled, (try binding.poll(&table, &queue)).?.kind);
    try std.testing.expectEqual(ledger.State.cancelled, (try table.lookup(id, 1)).state);
    try binding.release(&table, &queue);
    _ = try table.collect(id, 1);
}

// Explicit fake publication boundary. The real synchronous job executes on the
// caller; only sealing/host observation is held back to exercise both D04 orders.
const Publication = struct {
    result: ?q.Result = null,
    phase: @FieldType(q.Job, "phase") = .running,
    pub fn poll(self: *@This(), _: *q.Job) ?q.Result {
        return self.result;
    }
    pub fn phaseOf(self: *@This(), _: *q.Job) @FieldType(q.Job, "phase") {
        return self.phase;
    }
    pub fn cancel(_: *@This(), item: *q.Job) void {
        item.cancellation.request();
    }
    pub fn release(self: *@This(), item: *q.Job) void {
        item.external_valid = false;
        self.cancel(item);
    }
};
test "1373 D04 real job success cancellation and failure keep sealed outcome in either request order" {
    var output = support.Output{};
    const vm = try support.createMachine(&output);
    defer support.destroyMachine(vm);
    try vm.interpretLine(": JOB ; : FAIL 0 0 / ;");
    var manager = snapshot.Manager{};
    const version = try manager.capture(a, vm);
    defer version.release();
    for (0..4) |order| {
        var execution: Execution = .{ .allocator = a, .admission = try version.admit(vm), .entry = if (order == 3) "FAIL" else "JOB", .input = "abc" };
        defer execution.deinit();
        var item = execution.queued();
        var table = try ledger.DefaultLedger.init(1);
        const id = try table.register(1);
        try table.publish(id, 1);
        const binding: Binding = .{ .id = id, .owner = 1, .job = &item };
        var publication: Publication = .{};
        item.acquired.store(true, .release);
        _ = try binding.poll(&table, &publication); // host observes worker acquisition
        if (order == 0) try binding.cancel(&table, &publication);
        const runner = Execution.runner();
        const result = runner.run_fn(null, &item);
        if (order == 1 or order == 3) try binding.release(&table, &publication);
        publication.result = result;
        publication.phase = .sealed;
        _ = try binding.poll(&table, &publication);
        if (order == 2) try binding.cancel(&table, &publication);
        const record = try table.inspect(id, 1);
        try std.testing.expectEqual(if (order == 0) ledger.State.cancelled else if (order == 3) ledger.State.failed else ledger.State.succeeded, record.state);
        try std.testing.expect(!record.execution_ref);
        if (order == 0) try std.testing.expectEqual(error.TaskCancelled, execution.failure.?);
        if (order == 3) try std.testing.expectEqual(error.DivisionByZero, execution.failure.?);
        _ = try binding.poll(&table, &publication); // idempotent terminal receipt
        if (record.external_valid) try binding.release(&table, &publication);
        _ = try table.collect(id, 1);
    }
}

test "1373 real queue worker executes fresh VM adapter and host publishes ledger result" {
    var output = support.Output{};
    const vm = try support.createMachine(&output);
    defer support.destroyMachine(vm);
    try vm.interpretLine(": JOB 2DUP 66 FILL ;");
    var manager = snapshot.Manager{};
    const version = try manager.capture(a, vm);
    defer version.release();
    var execution: Execution = .{ .allocator = a, .admission = try version.admit(vm), .entry = "JOB", .input = "abc" };
    defer execution.deinit();
    var item = execution.queued();
    const Wake = @import("../host_wake.zig").Wake;
    const clock = @import("../host_clock.zig").clock;
    var common = try Wake.init();
    defer common.deinit() catch unreachable;
    var queue = try q.DefaultQueue.init(clock, common.operations(), Execution.runner());
    defer queue.deinit() catch unreachable;
    var table = try ledger.DefaultLedger.init(1);
    const id = try table.register(1);
    try queue.submit(&item, 1000);
    try table.publish(id, 1);
    const binding: Binding = .{ .id = id, .owner = 1, .job = &item };
    try queue.start();
    const deadline = try base.Deadline.afterMilliseconds(try clock.now(), 20000); // fail-fast watchdog, not measurement
    while (true) {
        const observed = common.observe();
        if (try binding.poll(&table, &queue)) |result| {
            try std.testing.expectEqual(.succeeded, result.kind);
            break;
        }
        if (try common.waitWithClock(observed, deadline, null, clock) == .timeout) @panic("1373 queue watchdog");
    }
    try std.testing.expectEqualStrings("BBB", execution.result.?);
    try std.testing.expectEqual(ledger.State.succeeded, (try table.lookup(id, 1)).state);
    queue.stop();
    while (true) {
        const observed = common.observe();
        if (queue.joinIfStopped()) break;
        if (try common.waitWithClock(observed, deadline, null, clock) == .timeout) @panic("1373 join watchdog");
    }
    try binding.release(&table, &queue);
    _ = try table.collect(id, 1);
}

test "1373 B receipt precedes sealed A receipt with one worker" {
    var table = try ledger.DefaultLedger.init(1);
    var items = [_]q.Job{ .{}, .{} };
    var bindings: [2]Binding = undefined;
    var publication: Publication = .{};
    for (&items, 0..) |*item, index| {
        const id = try table.register(1);
        try table.publish(id, 1);
        bindings[index] = .{ .id = id, .owner = 1, .job = item };
        item.acquired.store(true, .release);
    }
    _ = try bindings[0].poll(&table, &publication);
    // A is sealed but unreceived; B has already acquired the sole worker.
    publication.phase = .sealed;
    publication.result = .{ .kind = .succeeded };
    var second: Publication = .{};
    _ = try bindings[1].poll(&table, &second);
    second.phase = .sealed;
    second.result = .{ .kind = .succeeded };
    _ = try bindings[1].poll(&table, &second);
    _ = try bindings[0].poll(&table, &publication);
    for (bindings) |binding| {
        const record = try table.inspect(binding.id, 1);
        try std.testing.expectEqual(ledger.State.succeeded, record.state);
        try std.testing.expect(!record.execution_ref);
    }
}

test "1373 first receipt of acquired cancelled job records execution stop" {
    const Observed = struct {
        inner: ledger.DefaultLedger,
        started: bool = false,
        stopped: bool = false,
        pub fn inspect(self: *@This(), id: ledger.Handle, owner: u64) !ledger.Record {
            return self.inner.inspect(id, owner);
        }
        pub fn latchCancellation(self: *@This(), id: ledger.Handle, owner: u64) !void {
            try self.inner.latchCancellation(id, owner);
        }
        pub fn observeStart(self: *@This(), id: ledger.Handle, owner: u64) !void {
            try self.inner.observeStart(id, owner);
            self.started = true;
        }
        pub fn finish(self: *@This(), id: ledger.Handle, owner: u64, outcome: ledger.State) !bool {
            return self.inner.finish(id, owner, outcome);
        }
        pub fn failQueued(self: *@This(), id: ledger.Handle, owner: u64, reason: anytype) !bool {
            return self.inner.failQueued(id, owner, reason);
        }
        pub fn executionStopped(self: *@This(), id: ledger.Handle, owner: u64) !void {
            try self.inner.executionStopped(id, owner);
            self.stopped = true;
        }
    };
    var table: Observed = .{ .inner = try ledger.DefaultLedger.init(1) };
    const id = try table.inner.register(1);
    try table.inner.publish(id, 1);
    var item: q.Job = .{};
    item.acquired.store(true, .release);
    item.cancellation.request();
    const binding: Binding = .{ .id = id, .owner = 1, .job = &item };
    var publication: Publication = .{ .phase = .sealed, .result = .{ .kind = .cancelled } };
    _ = try binding.poll(&table, &publication);
    try std.testing.expect(table.started and table.stopped);
    const record = try table.inspect(id, 1);
    try std.testing.expectEqual(ledger.State.cancelled, record.state);
    try std.testing.expect(!record.execution_ref);
}
