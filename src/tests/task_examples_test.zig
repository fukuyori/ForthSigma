//! Host ownership checks supplement the public-only Forth/process examples.
const std = @import("std");
const t = std.testing;
const support = @import("support.zig");
const api = @import("../host_task_api.zig");

test "1380 public cancellation release and BYE reclaim every host allocation" {
    try support.skipWithout(&.{.extension});
    var output: support.Output = .{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    var service: api.Service = .{};
    defer service.finish(.owner_exit) catch @panic("1380 cleanup");
    machine.writer.task_fn = api.execute;
    machine.writer.task_context = &service;
    try machine.interpretLine("REQUIRE-EXTENSION ALSO EXTENSION : BUSY 2DROP BEGIN AGAIN ; TASK-SNAPSHOT THROW CONSTANT SNAP VARIABLE JOB");
    // More than the sixteen ledger slots: release invalidates the public ID
    // immediately; owner shutdown must also collect physically running work.
    for (0..20) |_| {
        try machine.interpretLine("SNAP S\" BUSY\" S\" x\" TASK-G1 1 TASK-SUBMIT THROW JOB ! JOB @ TASK-CANCEL THROW JOB @ 30000 TASK-WAIT THROW TASK-WAIT-EXPIRED AND 0= SWAP TASK-CANCELLED = JOB @ TASK-RELEASE THROW");
        try support.expectStack(machine, &.{ -1, -1 });
        _ = try machine.pop();
        _ = try machine.pop();
    }
    try machine.interpretLine("SNAP S\" BUSY\" S\" x\" TASK-G1 1 TASK-SUBMIT THROW JOB ! JOB @ TASK-RELEASE THROW");
    // Retain both a task ID and snapshot, just as the process BYE case does.
    try machine.interpretLine("SNAP S\" BUSY\" S\" x\" TASK-G1 1 TASK-SUBMIT THROW JOB !");
    try service.finish(.bye);
    try t.expect(service.closed);
    try t.expectEqual(@as(usize, 0), service.host.ledger.count());
    try t.expectEqual(@as(usize, 0), service.transfer_used);
    for (service.tasks) |slot| try t.expect(slot == null);
    for (service.snapshots) |slot| try t.expect(slot == null);
    try t.expectEqual(@as(usize, 0), service.allocations.used.load(.acquire));
}

// Exercise the public admission gate with real queue/ledger ownership. The fake
// runner holds physical handback; the fake host clock crosses the stop deadline
// without relying on Linux/Windows scheduling or elapsed wall time.
test "1380 public G1 replacement is accepted and expires while released runner is stop-unconfirmed" {
    try support.skipWithout(&.{.extension});
    const base = @import("../core/runtime_base.zig");
    const queue = @import("../core/task_queue.zig");
    const Barrier = struct {
        entered: std.atomic.Value(bool) = .init(false),
        proceed: std.atomic.Value(bool) = .init(false),
        instant: base.Instant = 0,
        fn now(raw: ?*anyopaque) base.Error!base.Instant {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            return self.instant;
        }
        fn run(raw: ?*anyopaque, _: *queue.Job) queue.Result {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.entered.store(true, .release);
            while (!self.proceed.load(.acquire)) std.atomic.spinLoopHint();
            return .{ .kind = .cancelled };
        }
    };
    var barrier: Barrier = .{};
    var output: support.Output = .{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    var service: api.Service = .{};
    defer service.finish(.owner_exit) catch @panic("1380 barrier cleanup");
    defer barrier.proceed.store(true, .release);
    machine.writer.task_fn = api.execute;
    machine.writer.task_context = &service;
    try machine.interpretLine("REQUIRE-EXTENSION ALSO EXTENSION : BUSY 2DROP BEGIN AGAIN ; TASK-SNAPSHOT THROW CONSTANT SNAP VARIABLE JOB");
    // No jobs exist yet; queue publication synchronizes the injected runner.
    service.jobs.runner = .{ .context = &barrier, .run_fn = Barrier.run };
    service.jobs.clock = .{ .context = &barrier, .now_fn = Barrier.now };
    try machine.interpretLine("SNAP S\" BUSY\" S\" x\" TASK-G1 7 TASK-SUBMIT THROW JOB !");
    for (0..10_000_000) |_| {
        if (barrier.entered.load(.acquire)) break;
        std.atomic.spinLoopHint();
    } else return error.Timeout;
    try machine.interpretLine("SNAP S\" BUSY\" S\" x\" TASK-G1 7 TASK-SUBMIT THROW JOB @ TASK-RELEASE THROW JOB !");
    const active = service.jobs.view().active.?;
    try t.expect(active.cancellation.isRequested());
    barrier.instant = 10 * std.time.ns_per_ms + 1;
    try machine.interpretLine("SNAP S\" BUSY\" S\" x\" TASK-G1 7 TASK-SUBMIT THROW JOB @ TASK-RELEASE THROW JOB ! JOB @ TASK-STATE THROW 2DROP DROP");
    try support.expectStack(machine, &.{1});
    _ = try machine.pop();
    try t.expectEqual(@as(usize, 2), service.host.ledger.count());
    try t.expectEqual(@as(usize, 1), service.jobs.view().count);
    try t.expectEqual(@as(u64, 3), service.host.generation);
    var retained = false;
    for (service.host.entries) |slot| if (slot) |entry| {
        if (entry.job != active) continue;
        const record = try service.host.ledger.inspect(entry.id, service.owner);
        try t.expect(record.stop_unconfirmed and record.execution_ref);
        try t.expectError(error.InvalidHandle, service.host.ledger.lookup(entry.id, service.owner));
        retained = true;
    };
    try t.expect(retained);
    // The old runner is still held: admission succeeds but execution cannot
    // start. The accepted G1 request fails at its 50 ms queue deadline.
    barrier.instant += 50 * std.time.ns_per_ms + 1;
    try machine.interpretLine("JOB @ TASK-STATE THROW 2DROP DROP");
    try support.expectStack(machine, &.{4});
    _ = try machine.pop();
    try t.expectEqual(@as(usize, 0), service.jobs.view().count);
    try machine.interpretLine("CREATE OUT 128 ALLOT JOB @ 0 OUT 128 TASK-DIAGNOSTIC THROW");
    try t.expectEqual(@as(i64, -313), try machine.pop());
    try t.expect((try machine.pop()) > 0);
    try t.expect(!barrier.proceed.load(.acquire));
    barrier.proceed.store(true, .release);
    try service.finish(.owner_exit);
    try t.expectEqual(@as(usize, 0), service.host.ledger.count());
    try t.expectEqual(@as(usize, 0), service.allocations.used.load(.acquire));
}
