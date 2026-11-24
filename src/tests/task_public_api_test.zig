const std = @import("std");
const t = std.testing;
const support = @import("support.zig");
const api = @import("../host_task_api.zig");
const forth = @import("../forth.zig");

test "public Forth task lifecycle copies, short retry, nonconsuming and stale IDs" {
    try support.skipWithout(&.{.extension});
    var output: support.Output = .{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    var service: api.Service = .{};
    defer service.finish(.owner_exit) catch @panic("public test cleanup");
    machine.writer.task_fn = api.execute;
    machine.writer.task_context = &service;
    try machine.interpretLine("REQUIRE-EXTENSION ALSO EXTENSION TASK-SUCCEEDED TASK-E-SHORT");
    try support.expectStack(machine, &.{ 3, -307 });
    try t.expect(!service.initialized);
    machine.data_depth = 0;
    try machine.interpretLine(": ECHO ; CREATE OUT 32 ALLOT TASK-SNAPSHOT THROW CONSTANT SNAP");
    try t.expect(service.initialized);
    try machine.interpretLine("SNAP S\" ECHO\" S\" abc\" TASK-I1 0 TASK-SUBMIT THROW CONSTANT JOB");
    try machine.interpretLine("JOB -1 TASK-WAIT THROW DROP");
    try support.expectStack(machine, &.{3});
    machine.data_depth = 0;
    try machine.interpretLine("JOB OUT 0 TASK-RESULT");
    try support.expectStack(machine, &.{ 3, 3, -307 });
    machine.data_depth = 0;
    try machine.interpretLine("JOB OUT 32 TASK-RESULT");
    try support.expectStack(machine, &.{ 3, 3, 0 });
    machine.data_depth = 0;
    service.jobs.notification_failed.store(true, .release);
    try machine.interpretLine("JOB OUT 32 TASK-RESULT JOB TASK-CANCEL JOB TASK-RELEASE JOB TASK-STATE SNAP TASK-SNAPSHOT-RELEASE SNAP TASK-SNAPSHOT-RELEASE");
    try support.expectStack(machine, &.{ 3, 3, 0, 0, 0, 0, 0, 0, 0, -300, 0, -300 });
}

test "public submission rejects missing and forbidden entries before acceptance" {
    try support.skipWithout(&.{.extension});
    var output: support.Output = .{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    var service: api.Service = .{};
    defer service.finish(.owner_exit) catch @panic("cleanup");
    machine.writer.task_fn = api.execute;
    machine.writer.task_context = &service;
    try machine.interpretLine("REQUIRE-EXTENSION ALSO EXTENSION : BAD TYPE ; TASK-SNAPSHOT THROW CONSTANT SNAP");
    try machine.interpretLine("SNAP S\" MISSING\" 0 0 TASK-I1 0 TASK-SUBMIT SNAP S\" BAD\" 0 0 TASK-I1 0 TASK-SUBMIT");
    try support.expectStack(machine, &.{ 0, -303, 0, -304 });
    try t.expectEqual(@as(usize, 0), service.host.ledger.count());
    machine.data_depth = 0;
    try machine.interpretLine("MARKER M M SNAP S\" BAD\" 0 0 TASK-I1 0 TASK-SUBMIT");
    try support.expectStack(machine, &.{ 0, -302 });
}

test "public argument THROW preserves inputs and does not initialize host" {
    try support.skipWithout(&.{.extension});
    var output: support.Output = .{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    var service: api.Service = .{};
    machine.writer.task_fn = api.execute;
    machine.writer.task_context = &service;
    try machine.interpretLine("REQUIRE-EXTENSION ALSO EXTENSION");
    try machine.push(0);
    try machine.push(0);
    try machine.push(-1);
    try t.expectError(error.Thrown, api.execute(&service, machine, .task_result));
    try support.expectStack(machine, &.{ 0, 0, -1 });
    try t.expectEqual(@as(forth.Cell, -24), machine.throw_code);
    machine.data_depth = 0;
    try machine.push(0);
    try machine.push(std.math.maxInt(forth.Cell));
    try machine.push(1);
    try t.expectError(error.InvalidAddress, api.execute(&service, machine, .task_result));
    try support.expectStack(machine, &.{ 0, std.math.maxInt(forth.Cell), 1 });
    machine.data_depth = 0;
    inline for (.{ .task_snapshot_release, .task_submit, .task_state, .task_cancel, .task_wait, .task_result, .task_diagnostic, .task_release, .task_wait_many }) |word| {
        try t.expectError(error.StackUnderflow, @import("../core/words_task.zig").execute(machine, word));
    }
    machine.data_depth = machine.data_stack.len;
    try t.expectError(error.StackOverflow, @import("../core/words_task.zig").execute(machine, .task_snapshot));
    machine.data_depth = 0;
    try t.expect(!service.initialized);
}

test "public handles are process unique and bound to the source VM" {
    try support.skipWithout(&.{.extension});
    var out1: support.Output = .{};
    var out2: support.Output = .{};
    const one = try support.createMachine(&out1);
    defer support.destroyMachine(one);
    const two = try support.createMachine(&out2);
    defer support.destroyMachine(two);
    var first: api.Service = .{};
    defer first.finish(.owner_exit) catch @panic("cleanup");
    var second: api.Service = .{};
    defer second.finish(.owner_exit) catch @panic("cleanup");
    try api.execute(&first, one, .task_snapshot);
    const id = one.data_stack[0];
    try two.push(id);
    try api.execute(&second, two, .task_snapshot_release);
    try support.expectStack(two, &.{-300});
    two.data_depth = 0;
    try api.execute(&second, two, .task_snapshot);
    try t.expect(id != two.data_stack[0]);
    two.data_depth = 0;
    try two.push(id);
    try api.execute(&first, two, .task_snapshot_release);
    try support.expectStack(two, &.{-300});
}

test "public many wait returns duplicate clock events in index order and timeout together" {
    try support.skipWithout(&.{.extension});
    var output: support.Output = .{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    var service: api.Service = .{};
    defer service.finish(.owner_exit) catch @panic("cleanup");
    machine.writer.task_fn = api.execute;
    machine.writer.task_context = &service;
    try machine.interpretLine("REQUIRE-EXTENSION ALSO EXTENSION CREATE TARGETS 4 , 0 , 0 , 0 , 71 , 4 , 0 , 0 , 0 , 72 , CREATE EVENTS 64 ALLOT TARGETS 2 EVENTS 1 0 TASK-WAIT-MANY");
    try support.expectStack(machine, &.{ 2, 0, -307 });
    try t.expect(!service.initialized);
    machine.data_depth = 0;
    try machine.interpretLine("TARGETS 2 EVENTS 2 0 TASK-WAIT-MANY");
    try support.expectStack(machine, &.{ 2, 1, 0 });
    machine.data_depth = 0;
    try machine.interpretLine("EVENTS @ EVENTS CELL+ @ EVENTS 2 CELLS + @ EVENTS 4 CELLS + @ EVENTS 5 CELLS + @");
    try support.expectStack(machine, &.{ 0, 71, 1024, 1, 72 });
}

test "public failed ABI has nonconsuming diagnostics and no successful result" {
    try support.skipWithout(&.{.extension});
    var output: support.Output = .{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    var service: api.Service = .{};
    defer service.finish(.owner_exit) catch @panic("cleanup");
    machine.writer.task_fn = api.execute;
    machine.writer.task_context = &service;
    try machine.interpretLine("REQUIRE-EXTENSION ALSO EXTENSION : BAD DEPTH ; CREATE OUT 128 ALLOT TASK-SNAPSHOT THROW CONSTANT SNAP SNAP S\" BAD\" 0 0 TASK-I1 0 TASK-SUBMIT THROW CONSTANT JOB JOB -1 TASK-WAIT THROW DROP");
    try support.expectStack(machine, &.{4});
    machine.data_depth = 0;
    try machine.interpretLine("JOB 0 OUT 0 TASK-DIAGNOSTIC");
    try t.expect(machine.data_stack[0] > 0);
    try t.expectEqual(@as(forth.Cell, -308), machine.data_stack[1]);
    try t.expectEqual(@as(forth.Cell, -307), machine.data_stack[2]);
    machine.data_depth = 0;
    try machine.interpretLine("JOB 0 OUT 128 TASK-DIAGNOSTIC THROW DROP DROP JOB 0 OUT 128 TASK-DIAGNOSTIC THROW DROP DROP JOB OUT 128 TASK-RESULT");
    try support.expectStack(machine, &.{ 0, 4, 0 });
}

test "public cancellation and release retain resources until worker handback" {
    try support.skipWithout(&.{.extension});
    var output: support.Output = .{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    var service: api.Service = .{};
    defer service.finish(.owner_exit) catch @panic("cleanup");
    machine.writer.task_fn = api.execute;
    machine.writer.task_context = &service;
    try machine.interpretLine("REQUIRE-EXTENSION ALSO EXTENSION : FOREVER BEGIN AGAIN ; CREATE OUT 1 ALLOT TASK-SNAPSHOT THROW CONSTANT SNAP SNAP S\" FOREVER\" 0 0 TASK-I1 0 TASK-SUBMIT THROW CONSTANT JOB JOB OUT 1 TASK-RESULT");
    try support.expectStack(machine, &.{ 0, 0, -306 });
    machine.data_depth = 0;
    try machine.interpretLine("JOB 3 OUT 1 TASK-DIAGNOSTIC");
    try support.expectStack(machine, &.{ 0, 0, -306 });
    machine.data_depth = 0;
    try machine.interpretLine("JOB TASK-CANCEL THROW JOB -1 TASK-WAIT THROW DROP");
    try support.expectStack(machine, &.{5});
    machine.data_depth = 0;
    try machine.interpretLine("JOB OUT 1 TASK-RESULT JOB TASK-RELEASE THROW SNAP TASK-SNAPSHOT-RELEASE THROW");
    try support.expectStack(machine, &.{ 0, 5, 0 });
    try service.poll();
    try t.expectEqual(@as(usize, 0), service.host.ledger.count());
}

test "public limits, busy capture, unavailable capability and exhausted identities" {
    try support.skipWithout(&.{.extension});
    var output: support.Output = .{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    var service: api.Service = .{};
    defer service.finish(.owner_exit) catch @panic("cleanup");
    machine.writer.task_fn = api.execute;
    machine.writer.task_context = &service;
    try api.execute(&service, machine, .task_snapshot);
    machine.data_depth = 0;
    try api.execute(&service, machine, .task_snapshot);
    machine.data_depth = 0;
    try api.execute(&service, machine, .task_snapshot);
    machine.data_depth = 0;
    try api.execute(&service, machine, .task_snapshot);
    try support.expectStack(machine, &.{ 0, -301 });
    // Drop one captured external reference, then test a parser transaction.
    machine.data_depth = 0;
    try machine.push(service.snapshots[0].?.id);
    try api.execute(&service, machine, .task_snapshot_release);
    machine.data_depth = 0;
    machine.defining = true;
    try api.execute(&service, machine, .task_snapshot);
    machine.defining = false;
    try support.expectStack(machine, &.{ 0, -309 });
    machine.data_depth = 0;
    const saved_limit = service.manager.max_image_bytes;
    service.manager.max_image_bytes = 0;
    try api.execute(&service, machine, .task_snapshot);
    service.manager.max_image_bytes = saved_limit;
    try support.expectStack(machine, &.{ 0, -305 });
    machine.data_depth = 0;
    machine.task_structure_epoch = std.math.maxInt(u64);
    try api.execute(&service, machine, .task_snapshot);
    try support.expectStack(machine, &.{ 0, -310 });
    var ids: api.Identities = .{ .serial = .init(std.math.maxInt(i64) - 1) };
    try t.expectEqual(@as(u64, std.math.maxInt(i64)), try ids.take());
    try t.expectError(error.IdentityExhausted, ids.take());
}

test "public task operations reject the worker thread and missing host" {
    try support.skipWithout(&.{.extension});
    var output: support.Output = .{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    var service: api.Service = .{};
    var worker: @import("../core/task_context.zig").WorkerScope = .{};
    worker.enter();
    try api.execute(&service, machine, .task_snapshot);
    worker.leave();
    try support.expectStack(machine, &.{ 0, -304 });
    try t.expect(!service.initialized);
    machine.data_depth = 0;
    try machine.interpretLine("REQUIRE-EXTENSION ALSO EXTENSION");
    try t.expectError(error.HostUnavailable, machine.interpretLine("TASK-SNAPSHOT"));
    try support.expectStack(machine, &.{});
}

test "public many wait preserves inputs on Ctrl-C equivalent and combines IO reasons" {
    try support.skipWithout(&.{ .extension, .files });
    const Fake = struct {
        var interrupt = true;
        var failure = false;
        fn check(_: forth.Cell, _: bool) forth.Cell {
            return 0;
        }
        fn attach(_: forth.Cell, _: bool) forth.RuntimeError!void {}
        fn probe(_: forth.Cell, writing: bool) forth.RuntimeError!@import("../core/task_wait.zig").State {
            if (interrupt) return error.UserInterrupt;
            if (failure and !writing) return .{ .reason = .failure, .detail = -521 };
            return .{ .reason = if (writing) .writable else .readable };
        }
        fn interest(_: forth.Cell, _: bool) ?@import("../host_wake.zig").Wake.Interest {
            return null;
        }
        const ops: api.IoOps = .{ .check = check, .attach = attach, .probe = probe, .interest = interest };
    };
    var output: support.Output = .{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    var service: api.Service = .{ .io = &Fake.ops };
    defer service.finish(.owner_exit) catch @panic("cleanup");
    machine.writer.task_fn = api.execute;
    machine.writer.task_context = &service;
    try machine.interpretLine("REQUIRE-EXTENSION ALSO EXTENSION CREATE T 2 , 123 , 3 , 0 , 42 , CREATE E 32 ALLOT T 1 E 1 -1");
    const before = machine.data_depth;
    Fake.interrupt = true;
    Fake.failure = false;
    try t.expectError(error.UserInterrupt, api.execute(&service, machine, .task_wait_many));
    try t.expectEqual(before, machine.data_depth);
    try t.expect(!service.waiting);
    Fake.interrupt = false;
    try api.execute(&service, machine, .task_wait_many);
    try support.expectStack(machine, &.{ 1, 0, 0 });
    machine.data_depth = 0;
    try machine.interpretLine("E 2 CELLS + @");
    try support.expectStack(machine, &.{6});
    machine.data_depth = 0;
    Fake.failure = true;
    try machine.interpretLine("T 1 E 1 0 TASK-WAIT-MANY THROW 2DROP E 2 CELLS + @ E 3 CELLS + @");
    try support.expectStack(machine, &.{ 20, -521 });
    Fake.failure = false;
}

test "public host errors retain fixed outputs; capability absence does not register" {
    try support.skipWithout(&.{.extension});
    const Failure = struct {
        fn now(_: ?*anyopaque) @import("../core/runtime_base.zig").Error!i128 {
            return error.HostFailed;
        }
    };
    var output: support.Output = .{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    var service: api.Service = .{};
    defer service.finish(.owner_exit) catch @panic("cleanup");
    machine.writer.task_fn = api.execute;
    machine.writer.task_context = &service;
    try machine.interpretLine("REQUIRE-EXTENSION ALSO EXTENSION CREATE T 5 , 0 , 0 , 0 , 0 , CREATE E 32 ALLOT T 1 E 1 0 TASK-WAIT-MANY");
    try support.expectStack(machine, &.{ 0, 0, -311 });
    try t.expect(!service.initialized);
    machine.data_depth = 0;
    try api.execute(&service, machine, .task_snapshot);
    machine.data_depth = 0;
    const saved = service.jobs.clock;
    service.jobs.clock = .{ .context = null, .now_fn = Failure.now };
    try machine.push(0);
    try api.execute(&service, machine, .task_state);
    service.jobs.clock = saved;
    try support.expectStack(machine, &.{ 0, 0, 0, 0, -312 });
    machine.data_depth = 0;
    service.jobs.clock = .{ .context = null, .now_fn = Failure.now };
    try machine.push(0);
    try machine.push(0);
    try api.execute(&service, machine, .task_wait);
    service.jobs.clock = saved;
    try support.expectStack(machine, &.{ 0, 8, -312 });
}

test "public old snapshot values survive ordinary writes and REPL recovery" {
    try support.skipWithout(&.{.extension});
    var output: support.Output = .{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    var service: api.Service = .{};
    defer service.finish(.owner_exit) catch @panic("cleanup");
    machine.writer.task_fn = api.execute;
    machine.writer.task_context = &service;
    try machine.interpretLine("REQUIRE-EXTENSION ALSO EXTENSION VARIABLE V 7 V ! : VALUE-RESULT 2DROP V 8 ; CREATE OUT 8 ALLOT TASK-SNAPSHOT THROW CONSTANT SNAP 9 V ! SNAP S\" VALUE-RESULT\" 0 0 TASK-I1 0 TASK-SUBMIT THROW CONSTANT JOB JOB -1 TASK-WAIT THROW 2DROP");
    machine.report(error.Aborted);
    machine.report(error.Quit);
    try machine.interpretLine("JOB OUT 8 TASK-RESULT THROW 2DROP OUT @");
    try support.expectStack(machine, &.{7});
}

test "public allocation failure distinguishes exhausted budget from allocator failure" {
    try support.skipWithout(&.{.extension});
    var output: support.Output = .{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    var service: api.Service = .{};
    defer service.finish(.owner_exit) catch @panic("cleanup");
    var failing = t.FailingAllocator.init(t.allocator, .{ .fail_index = 0 });
    service.allocations.backing = failing.allocator();
    try api.execute(&service, machine, .task_snapshot);
    try support.expectStack(machine, &.{ 0, -257 });
    try t.expectEqual(@as(usize, 0), service.manager.live_versions.load(.acquire));
    machine.data_depth = 0;
    service.allocations.limit = 0;
    try api.execute(&service, machine, .task_snapshot);
    try support.expectStack(machine, &.{ 0, -305 });
    try t.expectEqual(@as(usize, 0), service.allocations.used.load(.acquire));
}

test "public diagnostic adapters preserve queue expiry and stop codes without changing terminal state" {
    try support.skipWithout(&.{.extension});
    var output: support.Output = .{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    var service: api.Service = .{};
    defer service.finish(.owner_exit) catch @panic("cleanup");
    machine.writer.task_fn = api.execute;
    machine.writer.task_context = &service;
    try machine.interpretLine("REQUIRE-EXTENSION ALSO EXTENSION : BAD DEPTH ; CREATE OUT 128 ALLOT TASK-SNAPSHOT THROW CONSTANT SNAP SNAP S\" BAD\" 0 0 TASK-I1 0 TASK-SUBMIT THROW CONSTANT JOB JOB -1 TASK-WAIT THROW 2DROP");
    const task = service.tasks[0].?;
    // Inject host-owned sealed metadata only after physical worker handback.
    // Real queue-expiry/stop transitions are covered by queue/schedule tests.
    task.job.terminal.?.reason = .queue_expired;
    try machine.interpretLine("JOB 0 OUT 128 TASK-DIAGNOSTIC THROW");
    try t.expectEqual(@as(forth.Cell, -313), try machine.pop());
    _ = try machine.pop();
    const now = try service.jobs.clock.now();
    try service.host.requestCancel(task.handle, service.owner, now);
    for (&service.host.entries) |*slot| if (slot.*) |*entry| {
        entry.stop.?.stop_exceeded = true;
    };
    try machine.interpretLine("JOB 3 OUT 128 TASK-DIAGNOSTIC THROW");
    try t.expectEqual(@as(forth.Cell, -314), try machine.pop());
    _ = try machine.pop();
    try machine.interpretLine("JOB TASK-STATE THROW 2DROP DROP");
    try support.expectStack(machine, &.{4});
}

test "public VM execution exception is a diagnostic, not a failed state query" {
    try support.skipWithout(&.{.extension});
    var output: support.Output = .{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    var service: api.Service = .{};
    defer service.finish(.owner_exit) catch @panic("cleanup");
    machine.writer.task_fn = api.execute;
    machine.writer.task_context = &service;
    try machine.interpretLine("REQUIRE-EXTENSION ALSO EXTENSION : BAD 1 0 / ; CREATE OUT 128 ALLOT TASK-SNAPSHOT THROW CONSTANT SNAP SNAP S\" BAD\" 0 0 TASK-I1 0 TASK-SUBMIT THROW CONSTANT JOB JOB -1 TASK-WAIT THROW 2DROP JOB 0 OUT 128 TASK-DIAGNOSTIC THROW");
    try t.expectEqual(@as(forth.Cell, -10), try machine.pop());
    _ = try machine.pop();
    try machine.interpretLine("JOB TASK-STATE THROW 2DROP DROP");
    try support.expectStack(machine, &.{4});
}

test "public worker VM partition counts State and every Storage allocation" {
    try t.expect(api.vmBytes(.small) <= 76 * 1024 * 1024);
    var sizes = forth.Sizes.small;
    sizes.m = 64 * 1024 * 1024;
    try t.expect(api.vmBytes(sizes) > 76 * 1024 * 1024);
}

// Exercise the public wait and its real task_paint adapter without an OS window.
// I/O probe publishes after registration, so close/completion occur while waiting.
test "public paint many validates arguments, backend, lifetime and simultaneous events" {
    try support.skipWithout(&.{.extension});
    const options = @import("build_options");
    const window = @import("../host_window.zig");
    const paint = &@import("../host_paint.zig").source;
    const Fake = struct {
        var shown: u64 = 0;
        var closing = false;
        fn check(_: forth.Cell, _: bool) forth.Cell {
            return 0;
        }
        fn attach(_: forth.Cell, _: bool) forth.RuntimeError!void {}
        fn probe(_: forth.Cell, _: bool) forth.RuntimeError!@import("../core/task_wait.zig").State {
            @import("../host_paint.zig").source.publish(true, !closing, shown, shown);
            return .{ .reason = .readable };
        }
        fn interest(_: forth.Cell, _: bool) ?@import("../host_wake.zig").Wake.Interest {
            return null;
        }
        const ops: api.IoOps = .{ .check = check, .attach = attach, .probe = probe, .interest = interest };
    };
    var output: support.Output = .{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    var service: api.Service = .{ .io = &Fake.ops };
    defer service.finish(.owner_exit) catch @panic("cleanup");
    machine.writer.task_fn = api.execute;
    machine.writer.task_context = &service;
    try machine.interpretLine("REQUIRE-EXTENSION ALSO EXTENSION CREATE T 5 , 0 , 1 , 0 , 91 , CREATE E 96 ALLOT");
    try machine.interpretLine("1 T 3 CELLS + ! : INVALID T 1 E 1 0 TASK-WAIT-MANY ; ' INVALID CATCH");
    try support.expectStack(machine, &.{-24});
    try t.expect(!service.initialized);
    machine.data_depth = 0;
    try machine.interpretLine("0 T 3 CELLS + ! 1 T CELL+ ! T 1 E 1 0 TASK-WAIT-MANY");
    try support.expectStack(machine, &.{ 0, 0, -300 });
    machine.data_depth = 0;
    try machine.interpretLine("0 T CELL+ ! T 1 E 1 0 TASK-WAIT-MANY");
    try support.expectStack(machine, &.{ 0, 0, -311 });
    if (!options.graphics or !window.available) return;
    machine.data_depth = 0;
    try machine.interpretLine("REQUIRE-GRAPHICS ALSO GRAPHICS 2 GFX-AUTO-DISPLAY!");
    // This synthetic test has no OS window or backend publisher. Restore its
    // invented frame numbers before the subsequent real-window smoke runs.
    const saved_paint = paint.*;
    defer paint.* = saved_paint;
    const number = paint.shown + 1;
    // No native window, explicit Tk, and AUTO selecting Tk all reject registration.
    paint.publish(true, false, number - 1, number - 1);
    try machine.interpretLine("T 1 E 1 0 TASK-WAIT-MANY");
    try support.expectStack(machine, &.{ 0, 0, -311 });
    paint.publish(true, true, number, number - 1);
    for ([_][]const u8{ "DISPLAY-TK", "DISPLAY-AUTO 3 GFX-AUTO-DISPLAY!" }) |select| {
        machine.data_depth = 0;
        try machine.interpretLine(select);
        try machine.interpretLine("T 1 E 1 0 TASK-WAIT-MANY");
        try support.expectStack(machine, &.{ 0, 0, -311 });
    }
    machine.data_depth = 0;
    try machine.interpretLine("DISPLAY-AUTO 2 GFX-AUTO-DISPLAY!");
    // 0, a future number, and the previous lifetime's number are invalid targets.
    for ([_]u64{ 0, number + 1, number - 1 }) |invalid| {
        try machine.push(@bitCast(invalid));
        try machine.interpretLine("T 2 CELLS + ! T 1 E 1 0 TASK-WAIT-MANY");
        try support.expectStack(machine, &.{ 0, 0, -300 });
        machine.data_depth = 0;
    }
    try machine.push(@intCast(number));
    try machine.interpretLine("T 2 CELLS + ! T 1 E 1 0 TASK-WAIT-MANY");
    try support.expectStack(machine, &.{ 0, 1, 0 }); // pending, zero call timeout
    machine.data_depth = 0;
    paint.publish(true, true, number, number);
    try machine.interpretLine("T 1 E 1 0 TASK-WAIT-MANY THROW 2DROP E 2 CELLS + @");
    try support.expectStack(machine, &.{2048}); // already achieved
    if (!options.files) return;
    // I/O is index 0 so its probe publishes before paint index 1 is probed.
    machine.data_depth = 0;
    try machine.interpretLine("ALIGN CREATE MANY 2 , 1 , 1 , 0 , 90 , 5 , 0 , 0 , 0 , 91 , 4 , 0 , 0 , 0 , 92 ,");
    try machine.push(@intCast(number));
    try machine.interpretLine("MANY 7 CELLS + !");
    Fake.shown = number;
    for ([_]bool{ false, true }) |closing| {
        paint.publish(true, true, number, number - 1);
        Fake.closing = closing;
        try machine.interpretLine("MANY 3 E 3 0 TASK-WAIT-MANY THROW DROP E 2 CELLS + @ E 6 CELLS + @ E 10 CELLS + @");
        try support.expectStack(machine, &.{ 3, 2, if (closing) 512 else 2048, 1024 });
        machine.data_depth = 0;
    }
}

const paint_smoke_env = struct {
    extern "c" fn getenv([*:0]const u8) ?[*:0]const u8;
};
test "public paint real native window wait (opt in)" {
    try support.skipWithout(&.{ .extension, .graphics });
    const window = @import("../host_window.zig");
    if (!window.available or @import("builtin").os.tag == .macos or paint_smoke_env.getenv("FORTHZ_PAINT_SMOKE") == null) return error.SkipZigTest;
    var output: support.Output = .{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    var wake = try @import("../host_wake.zig").Wake.init();
    defer wake.deinit() catch unreachable;
    const paint = &@import("../host_paint.zig").source;
    paint.bind(wake.operations());
    defer paint.bind(null);
    var service: api.Service = .{ .common_wake = &wake };
    defer service.finish(.owner_exit) catch @panic("cleanup");
    machine.writer.task_fn = api.execute;
    machine.writer.task_context = &service;
    machine.writer.window_state_fn = window.windowState;
    window.close();
    defer window.close();
    try machine.interpretLine("REQUIRE-EXTENSION ALSO EXTENSION REQUIRE-GRAPHICS ALSO GRAPHICS DISPLAY-AUTO 2 GFX-AUTO-DISPLAY! ALIGN CREATE T 5 , 0 , 0 , 0 , 77 , CREATE E 32 ALLOT");
    const pixels = [_]u32{ 0xff0000, 0x00ff00, 0x0000ff, 0xffffff };
    try window.show(null, &pixels, 2, 2, .{}, .{ 128, 128 });
    try machine.interpretLine("GFX-WINDOW-FRAMES DROP T 2 CELLS + ! T 1 E 1 5000 TASK-WAIT-MANY");
    try support.expectStack(machine, &.{ 1, 0, 0 });
    machine.data_depth = 0;
    try machine.interpretLine("E 2 CELLS + @");
    try support.expectStack(machine, &.{2048});
    machine.data_depth = 0;
    try machine.interpretLine("T 1 E 1 0 TASK-WAIT-MANY THROW 2DROP E 2 CELLS + @");
    try support.expectStack(machine, &.{2048});
}
