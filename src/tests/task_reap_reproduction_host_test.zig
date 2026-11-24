const std = @import("std");
const t = std.testing;
const base = @import("../core/runtime_base.zig");
const q = @import("../core/task_queue.zig");
const Host = @import("../core/task_schedule_host.zig").Host;
const reap = @import("../core/task_reap.zig");
const Execution = @import("../core/task_job_queue.zig").Execution;
const snapshot = @import("../core/task_snapshot.zig");
const results = @import("../core/task_results.zig");
const support = @import("support.zig");

const Wake = @import("../host_wake.zig").Wake;
const real = @import("../host_clock.zig").clock;
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
            if (!self.done.isRequested() and deadline.expired(real.now() catch @panic("watchdog clock"))) @panic("1376 reap watchdog expired");
        }
    }
    fn end(self: *Guard) void {
        self.done.request();
        self.wake.notify() catch {};
        self.thread.?.join();
        self.wake.deinit() catch unreachable;
    }
};

// Only the runner boundary is held. Queue, cancellation, VM, ledger and reaper
// are production objects. Fake time is read only by the serialized host.
fn watchdogDeadline() base.Deadline {
    return base.Deadline.afterMilliseconds(real.now() catch @panic("watchdog clock"), 20_000) catch unreachable;
}

const Fixture = struct {
    instant: base.Instant = 123,
    entered: std.atomic.Value(bool) = .init(false),
    proceed: std.atomic.Value(bool) = .init(false),
    destroyed: usize = 0,
    input: ?results.Buffer = null,
    fn now(raw: ?*anyopaque) base.Error!base.Instant {
        const self: *@This() = @ptrCast(@alignCast(raw.?));
        return self.instant;
    }
    fn observe(_: ?*anyopaque) u64 {
        return 0;
    }
    fn notify(_: ?*anyopaque) base.Error!void {}
    fn wait(_: ?*anyopaque, _: u64, _: base.Deadline, _: ?*const base.Cancellation, _: base.Clock) base.Error!base.WakeOutcome {
        return .timeout;
    }
    fn run(raw: ?*anyopaque, item: *q.Job) q.Result {
        const self: *@This() = @ptrCast(@alignCast(raw.?));
        self.entered.store(true, .release);
        // A bounded watchdog also covers assertion/error unwinding on the host.
        const limit = watchdogDeadline();
        while (!limit.expired(real.now() catch @panic("watchdog clock"))) {
            if (self.proceed.load(.acquire)) {
                const runner = Execution.runner();
                return runner.run_fn(runner.context, item);
            }
            std.atomic.spinLoopHint();
        }
        @panic("1376 runner synchronization watchdog");
    }
    fn destroy(raw: ?*anyopaque, _: base.Handle, item: *q.Job, _: q.Result, _: ?Host.Publication) void {
        const self: *@This() = @ptrCast(@alignCast(raw.?));
        const execution: *Execution = @ptrCast(@alignCast(item.context.?));
        execution.deinit();
        if (self.input) |*input| input.deinit();
        self.input = null;
        self.destroyed += 1;
    }
    fn init(self: *@This()) !q.DefaultQueue {
        return q.DefaultQueue.init(.{ .context = self, .now_fn = now }, .{ .context = null, .observe_fn = observe, .notify_fn = notify, .wait_fn = wait }, .{ .context = self, .run_fn = run });
    }
    fn dispose(self: *@This(), queue: *q.DefaultQueue) void {
        self.proceed.store(true, .release);
        queue.stop();
        const limit = watchdogDeadline();
        while (!limit.expired(real.now() catch @panic("watchdog clock"))) {
            if (queue.joinIfStopped()) break;
            std.atomic.spinLoopHint();
        }
        if (!queue.joinIfStopped()) @panic("1376 join watchdog");
        queue.deinit() catch unreachable;
    }
    fn reaper(self: *@This(), host: *Host) reap.Reaper {
        return .{ .host = host, .disposal = .{ .context = self, .destroy = destroy } };
    }
};
// Pause at the real FreshVm.create Plan disposal, after restore has finished.
// This ensures cancellation tears down an allocated/restored VM, rather than
// merely exercising task_job's pre-allocation token check. No production seam.
const RestoreGate = struct {
    entered: std.atomic.Value(bool) = .init(false),
    proceed: std.atomic.Value(bool) = .init(false),
    plan: ?[*]u8 = null,
    live: usize = 0,
    fn allocator(self: *@This()) std.mem.Allocator {
        return .{ .ptr = self, .vtable = &.{ .alloc = alloc, .free = free, .resize = std.mem.Allocator.noResize, .remap = std.mem.Allocator.noRemap } };
    }
    fn alloc(raw: *anyopaque, len: usize, alignment: std.mem.Alignment, ret: usize) ?[*]u8 {
        const self: *@This() = @ptrCast(@alignCast(raw));
        const bytes = t.allocator.rawAlloc(len, alignment, ret) orelse return null;
        self.live += 1;
        if (len == @sizeOf(@import("../core/image_restore_plan.zig").Plan)) self.plan = bytes;
        return bytes;
    }
    fn free(raw: *anyopaque, bytes: []u8, alignment: std.mem.Alignment, ret: usize) void {
        const self: *@This() = @ptrCast(@alignCast(raw));
        const is_plan = if (self.plan) |p| p == bytes.ptr else false;
        t.allocator.rawFree(bytes, alignment, ret);
        self.live -= 1;
        if (is_plan) {
            self.plan = null;
            self.entered.store(true, .release);
            const limit = watchdogDeadline();
            while (!limit.expired(real.now() catch @panic("watchdog clock"))) {
                if (self.proceed.load(.acquire)) return;
                std.atomic.spinLoopHint();
            }
            @panic("1376 restore synchronization watchdog");
        }
    }
};
fn request(item: *q.Job) Host.Request {
    return .{ .owner = 7, .kind = .game, .stream = 1, .input = .{ .bytes = "abc" }, .job = item, .milliseconds = 200 };
}
fn openAfterCancel(f: *Fixture, item: *q.Job) void {
    const limit = watchdogDeadline();
    while (!item.cancellation.isRequested()) {
        if (limit.expired(real.now() catch @panic("watchdog clock"))) @panic("1376 BYE cancellation watchdog");
        std.atomic.spinLoopHint();
    }
    f.proceed.store(true, .release);
}
fn awaitEntered(f: *Fixture) !void {
    const limit = watchdogDeadline();
    while (!limit.expired(real.now() catch @panic("watchdog clock"))) {
        if (f.entered.load(.acquire)) return;
        std.atomic.spinLoopHint();
    }
    return error.Timeout;
}
fn awaitTerminal(host: *Host, item: *q.Job) !void {
    const limit = watchdogDeadline();
    while (!limit.expired(real.now() catch @panic("watchdog clock"))) {
        try host.poll();
        if (item.terminal != null) return;
        std.atomic.spinLoopHint();
    }
    return error.Timeout;
}
fn collect(r: *reap.Reaper) !void {
    const limit = watchdogDeadline();
    while (!limit.expired(real.now() catch @panic("watchdog clock"))) {
        if (try r.poll() == .collected) return;
        std.atomic.spinLoopHint();
    }
    return error.Timeout;
}

test "1376 actual Execution cancellation then fresh VM successes and failure on one Queue" {
    var guard: Guard = undefined;
    try guard.start();
    defer guard.end();
    var output: support.Output = .{};
    const vm = try support.createMachine(&output);
    defer support.destroyMachine(vm);
    try vm.interpretLine("VARIABLE V : JOB V @ IF 0 0 / THEN 1 V ! 2DUP 65 FILL ; : FAIL 1 V ! 0 0 / ;");
    try @import("../core/address_registry.zig").registerMemory(vm, vm.words[vm.lookup("V").?].value);
    var manager: snapshot.Manager = .{};
    const version = try manager.capture(t.allocator, vm);
    defer version.release();
    var f: Fixture = .{};
    var queue = try f.init();
    defer f.dispose(&queue);
    var host = try Host.init(&queue, 1);
    try queue.start();
    var restore_gate: RestoreGate = .{};
    defer restore_gate.proceed.store(true, .release);
    f.proceed.store(true, .release);
    // Cancel an acquired production Execution; follow with independent jobs on
    // one continuously started Queue. Failure also mutates its private dictionary first.
    for (0..5) |i| {
        var execution: Execution = .{ .allocator = if (i == 0) restore_gate.allocator() else t.allocator, .admission = try version.admit(vm), .entry = if (i == 2) "FAIL" else "JOB", .input = "abc" };
        defer execution.deinit();
        var item = execution.queued();
        const id = try host.submit(request(&item));
        if (i == 0) {
            const limit = watchdogDeadline();
            while (!limit.expired(real.now() catch @panic("watchdog clock"))) {
                if (restore_gate.entered.load(.acquire)) break;
                std.atomic.spinLoopHint();
            }
            if (!restore_gate.entered.load(.acquire)) return error.Timeout;
            try t.expect(restore_gate.live > 0);
            try t.expectEqual(@as(usize, 3), version.references.load(.acquire));
            const binding: @import("../core/task_cancel.zig").Binding = .{ .id = id, .owner = 7, .job = &item };
            try binding.cancel(&host.ledger, &queue);
            try host.requestCancel(id, 7, f.instant); // repeated host request stays idempotent
            restore_gate.proceed.store(true, .release);
        }
        try awaitTerminal(&host, &item);
        const cleanup_limit = watchdogDeadline();
        while (queue.isCleaning(&item)) {
            if (cleanup_limit.expired(try real.now())) return error.Timeout;
            std.atomic.spinLoopHint();
        }
        const expected: @FieldType(q.Result, "kind") = if (i == 0) .cancelled else if (i == 2) .failed else .succeeded;
        try t.expectEqual(expected, item.terminal.?.kind);
        if (i == 0) {
            try t.expectEqual(error.TaskCancelled, execution.failure.?);
            try t.expectEqual(@as(usize, 0), restore_gate.live);
        }
        if (i == 2) try t.expectEqual(error.DivisionByZero, execution.failure.?);
        if (i != 0 and i != 2) try t.expectEqualStrings("AAA", execution.result.?);
        try host.release(id, 7);
        try host.collect(id, 7);
        try t.expectEqual(@as(usize, 0), host.ledger.count());
        try t.expectEqual(@as(usize, 1), version.references.load(.acquire));
    }
    var r = f.reaper(&host);
    try r.begin(.bye);
    try collect(&r);
    try t.expect(queue.thread == null);
    try t.expect(queue.view().active == null);
    try t.expectEqual(@as(usize, 0), queue.view().count);
    try t.expectEqual(@as(@import("../forth.zig").Cell, 0), try vm.readCell(vm.words[vm.lookup("V").?].value));
}

test "1376 unreturned runner retains Budget Snapshot ledger and diagnostics until late return" {
    var guard: Guard = undefined;
    try guard.start();
    defer guard.end();
    var output: support.Output = .{};
    const vm = try support.createMachine(&output);
    defer support.destroyMachine(vm);
    try vm.interpretLine(": JOB ;");
    var manager: snapshot.Manager = .{};
    const version = try manager.capture(t.allocator, vm);
    defer version.release();
    var budget: results.Budget = .{ .limit = 16 * 1024 * 1024 };
    var f: Fixture = .{};
    f.input = try results.Buffer.copy(t.allocator, &budget, "abc", 3);
    var execution: Execution = .{ .allocator = t.allocator, .admission = try version.admit(vm), .entry = "JOB", .input = f.input.?.bytes };
    defer execution.deinit();
    var item = execution.queued();
    var queue = try f.init();
    defer f.dispose(&queue);
    var host = try Host.init(&queue, 1);
    const id = try host.submit(request(&item));
    try queue.start();
    try awaitEntered(&f);
    var r = f.reaper(&host);
    try t.expectError(error.Busy, r.begin(.restore));
    try t.expect(!item.cancellation.isRequested());
    try host.release(id, 7);
    try r.begin(.bye);
    // Never open the synchronization gate during these sweeps: no real time
    // delay is needed to reproduce a runner that does not return by the limit.
    f.instant = 100_000_124;
    for (0..3) |_| {
        try t.expectEqual(reap.Progress.stop_unconfirmed, try r.poll());
        const diagnostic = (try host.stopDiagnostic(id, 7)).?;
        try t.expect(std.meta.eql(id, diagnostic.id));
        try t.expectEqual(@as(u64, 7), diagnostic.owner);
        try t.expectEqual(@as(base.Instant, 123), diagnostic.requested_at);
        try t.expect(diagnostic.stop_exceeded and diagnostic.collection_exceeded);
        try t.expect(!diagnostic.stopped);
        try t.expect((try host.ledger.inspect(id, 7)).execution_ref);
        try t.expectEqual(@as(usize, 1), host.ledger.count());
        try t.expectEqual(@as(usize, 3), budget.used);
        try t.expectEqual(@as(usize, 2), version.references.load(.acquire));
        try t.expectEqual(@as(usize, 0), f.destroyed);
        try t.expect(queue.thread != null);
    }
    // The build driver runs this artifact in a separate child process.
    // It deliberately never opens the runner gate and must exit without defers.
    if (getenv("FORTHZ_1376_FATAL_CHILD") != null) {
        const Fatal = struct {
            independent_cleaned: bool = false,
            fn cleanup(raw: ?*anyopaque) void {
                const self: *@This() = @ptrCast(@alignCast(raw.?));
                self.independent_cleaned = true;
            }
            fn write(raw: ?*anyopaque, bytes: []const u8) void {
                const self: *@This() = @ptrCast(@alignCast(raw.?));
                if (!self.independent_cleaned or !std.mem.eql(u8, bytes, @import("../host_task_stop.zig").message)) @panic("fatal callback order/message");
                _ = puts("1376: retained runner; independent cleanup; fatal diagnostic; exit 1");
            }
        };
        var fatal: Fatal = .{};
        @import("../host_task_stop.zig").abort(&fatal, Fatal.cleanup, Fatal.write);
    }
    f.proceed.store(true, .release);
    try collect(&r);
    try t.expectEqual(reap.Progress.collected, try r.poll());
    try t.expectEqual(@as(@FieldType(q.Result, "kind"), .cancelled), item.terminal.?.kind);
    try t.expectEqual(error.TaskCancelled, execution.failure.?);
    try t.expectEqual(@as(usize, 1), f.destroyed);
    try t.expectEqual(@as(usize, 0), budget.used);
    try t.expectEqual(@as(usize, 0), host.ledger.count());
    try t.expectEqual(@as(usize, 1), version.references.load(.acquire));
    try t.expect(queue.thread == null);
    try t.expect(queue.view().active == null);
    try t.expect(execution.admission == null and execution.result == null);
}

test "1376 production disposal matrix seals success failure cancellation RELEASE owner and BYE once" {
    var guard: Guard = undefined;
    try guard.start();
    defer guard.end();
    const hook = @import("../host_task_reap.zig");
    for (0..6) |scenario| {
        var output: support.Output = .{};
        const vm = try support.createMachine(&output);
        defer support.destroyMachine(vm);
        try vm.interpretLine(": JOB ; : FAIL 0 0 / ;");
        var manager: snapshot.Manager = .{};
        const version = try manager.capture(t.allocator, vm);
        var released = false;
        defer if (!released) version.release();
        var budget: results.Budget = .{ .limit = 1024 };
        var f: Fixture = .{};
        f.input = try results.Buffer.copy(t.allocator, &budget, "abc", 3);
        var execution: Execution = .{ .allocator = t.allocator, .admission = try version.admit(vm), .entry = if (scenario == 1) "FAIL" else "JOB", .input = f.input.?.bytes };
        defer execution.deinit();
        var item = execution.queued();
        var queue = try f.init();
        defer f.dispose(&queue);
        var host = try Host.init(&queue, 1);
        const id = try host.submit(request(&item));
        try queue.start();
        try awaitEntered(&f);
        if (scenario < 2) {
            f.proceed.store(true, .release);
            try awaitTerminal(&host, &item);
        } else if (scenario == 2) try host.requestCancel(id, 7, f.instant) else if (scenario == 3) try host.release(id, 7);
        if (scenario == 2 or scenario == 3) {
            // Prove explicit cancellation/RELEASE works before shutdown starts.
            f.proceed.store(true, .release);
            try awaitTerminal(&host, &item);
        }
        var r = f.reaper(&host);
        if (scenario == 4) r.owner = 7;
        hook.bind(&r);
        defer hook.bind(null);
        if (scenario == 5) {
            // Decision A is checked through the same hooks as main, while an
            // active runner and its input/Snapshot remain retained.
            try t.expectError(error.Quit, hook.interpret(vm, "QUIT"));
            try t.expectError(error.Aborted, hook.interpret(vm, "ABORT"));
            var failed = false;
            hook.interpret(vm, "1376-NO-SUCH-WORD") catch {
                failed = true;
            };
            try t.expect(failed);
            try t.expect(!r.begun and !item.cancellation.isRequested());
            try t.expectEqual(@as(usize, 1), host.ledger.count());
            try t.expectEqual(@as(usize, 2), version.references.load(.acquire));
            try t.expectEqual(@as(usize, 3), budget.used);
            const epoch = vm.task_structure_epoch;
            const here = vm.data_here;
            const job_word = vm.lookup("JOB");
            try t.expectError(error.Busy, hook.restore(vm, "not an image"));
            try t.expectEqual(epoch, vm.task_structure_epoch);
            try t.expectEqual(here, vm.data_here);
            try t.expectEqual(job_word, vm.lookup("JOB"));
            try t.expect(!vm.halted and host.accepting);
            const opener = try std.Thread.spawn(.{}, openAfterCancel, .{ &f, &item });
            defer opener.join();
            try hook.interpret(vm, "BYE");
            try t.expect(vm.halted);
        } else {
            try r.begin(.owner_exit);
            f.proceed.store(true, .release);
            try collect(&r);
        }
        const expected: @FieldType(q.Result, "kind") = if (scenario == 0) .succeeded else if (scenario == 1) .failed else .cancelled;
        try t.expectEqual(expected, item.terminal.?.kind);
        if (scenario >= 2) try t.expectEqual(error.TaskCancelled, execution.failure.?);
        try t.expectEqual(reap.Progress.collected, try r.poll());
        if (scenario == 4) {
            try t.expect(host.accepting);
            try t.expect(queue.thread != null);
            var rejected: q.Job = .{};
            try t.expectError(error.Closed, host.submit(request(&rejected)));
        }
        try t.expectEqual(@as(usize, 1), f.destroyed);
        try t.expectEqual(@as(usize, 0), budget.used);
        try t.expectEqual(@as(usize, 0), host.ledger.count());
        try t.expectEqual(@as(usize, 0), queue.view().count);
        try t.expect(queue.view().active == null);
        if (scenario != 4) try t.expect(queue.thread == null);
        try t.expect(execution.result == null and execution.admission == null);
        try t.expectEqual(@as(usize, 1), version.references.load(.acquire));
        version.release();
        released = true;
        try t.expectEqual(@as(usize, 0), manager.live_versions.load(.acquire));
    }
}

extern "c" fn getenv([*:0]const u8) ?[*:0]u8;
extern "c" fn puts([*:0]const u8) c_int;
