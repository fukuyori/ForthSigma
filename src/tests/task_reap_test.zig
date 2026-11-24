const std = @import("std");
const t = std.testing;
const q = @import("../core/task_queue.zig");
const Host = @import("../core/task_schedule_host.zig").Host;
const reap = @import("../core/task_reap.zig");
const base = @import("../core/runtime_base.zig");
const Fixture = struct {
    instant: base.Instant = 0,
    destroyed: usize = 0,
    cleaned: usize = 0,
    entered: std.atomic.Value(bool) = .init(false),
    proceed: std.atomic.Value(bool) = .init(false),
    fn now(raw: ?*anyopaque) base.Error!base.Instant {
        const self: *Fixture = @ptrCast(@alignCast(raw.?));
        return self.instant;
    }
    fn observe(_: ?*anyopaque) u64 {
        return 0;
    }
    fn notify(_: ?*anyopaque) base.Error!void {}
    fn wait(_: ?*anyopaque, _: u64, _: base.Deadline, _: ?*const base.Cancellation, _: base.Clock) base.Error!base.WakeOutcome {
        return .timeout;
    }
    fn cleanup(raw: ?*anyopaque) void {
        const self: *Fixture = @ptrCast(@alignCast(raw.?));
        self.cleaned += 1;
    }
    fn destroy(raw: ?*anyopaque, _: base.Handle, job: *q.Job, result: q.Result, _: ?Host.Publication) void {
        const self: *Fixture = @ptrCast(@alignCast(raw.?));
        t.expect(job.terminal != null) catch unreachable;
        t.expectEqual(result.kind, job.terminal.?.kind) catch unreachable;
        t.expect(self.cleaned > self.destroyed) catch unreachable;
        self.destroyed += 1;
    }
    fn run(raw: ?*anyopaque, _: *q.Job) q.Result {
        const self: *Fixture = @ptrCast(@alignCast(raw.?));
        self.entered.store(true, .release);
        while (!self.proceed.load(.acquire)) std.atomic.spinLoopHint();
        return .{ .kind = .succeeded }; // late success remains success
    }
    fn init(self: *Fixture) !q.DefaultQueue {
        return q.DefaultQueue.init(.{ .context = self, .now_fn = now }, .{ .context = null, .observe_fn = observe, .notify_fn = notify, .wait_fn = wait }, .{ .context = self, .run_fn = run });
    }
    fn dispose(self: *Fixture, queue: *q.DefaultQueue) void {
        self.proceed.store(true, .release);
        queue.stop();
        for (0..10_000_000) |_| {
            if (queue.joinIfStopped()) break;
            std.atomic.spinLoopHint();
        } else @panic("worker cleanup iteration limit");
        queue.deinit() catch unreachable;
    }
    fn item(self: *Fixture) q.Job {
        return .{ .context = self, .cleanup_fn = cleanup };
    }
    fn reaper(self: *Fixture, host: *Host) reap.Reaper {
        return .{ .host = host, .disposal = .{ .context = self, .destroy = destroy } };
    }
};
fn request(job: *q.Job, owner: u64) Host.Request {
    return .{ .owner = owner, .kind = .game, .stream = 1, .input = .{ .bytes = "" }, .job = job, .milliseconds = 200 };
}
test "reap every exit cause closes admission, releases queued records exactly once" {
    for ([_]reap.Cause{ .owner_exit, .bye }) |cause| {
        var f: Fixture = .{};
        var queue = try f.init();
        defer f.dispose(&queue);
        var host = try Host.init(&queue, 1);
        var a = f.item();
        const id = try host.submit(request(&a, 1));
        try host.release(id, 1); // already RELEASEd must remain discoverable
        var b = f.item();
        _ = try host.submit(request(&b, 1));
        var r = f.reaper(&host);
        try r.begin(cause);
        var extra = f.item();
        try t.expectError(error.Closed, host.submit(request(&extra, 1)));
        try t.expectEqual(reap.Progress.collected, try r.poll());
        try t.expectEqual(reap.Progress.collected, try r.poll());
        try t.expectEqual(@as(usize, 2), f.destroyed);
        try t.expectEqual(@as(usize, 0), host.ledger.count());
        try t.expectEqual(@as(usize, 0), queue.view().count);
    }
}
test "restore busy is nonmutating and retained references block collection" {
    var f: Fixture = .{};
    var queue = try f.init();
    defer f.dispose(&queue);
    var host = try Host.init(&queue, 1);
    var job = f.item();
    const id = try host.submit(request(&job, 1));
    var r = f.reaper(&host);
    try t.expectError(error.Busy, r.begin(.restore));
    try t.expect(host.accepting);
    try t.expect(!job.cancellation.isRequested());
    _ = try host.ledger.lookup(id, 1);
    try host.ledger.retain(id, 1); // WAIT/copy ownership
    try r.begin(.owner_exit);
    try t.expectEqual(reap.Progress.pending, try r.poll());
    try t.expectEqual(@as(usize, 0), f.destroyed);
    f.instant = 100_000_001;
    try t.expectEqual(reap.Progress.stop_unconfirmed, try r.poll());
    try host.ledger.drop(id, 1);
    try t.expectEqual(reap.Progress.collected, try r.poll());
    try t.expectEqual(@as(usize, 1), f.destroyed);
}
test "running timeout retains storage and late handback is joined and reclaimed" {
    var f: Fixture = .{};
    var queue = try f.init();
    defer f.dispose(&queue);
    var host = try Host.init(&queue, 1);
    var job = f.item();
    const id = try host.submit(request(&job, 1));
    try queue.start();
    for (0..10_000_000) |_| {
        if (f.entered.load(.acquire)) break;
        std.atomic.spinLoopHint();
    } else return error.Timeout;
    const Order = struct {
        running: *q.Job,
        fixture: *Fixture,
        fn cleanup(raw: ?*anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            t.expect(!self.running.cancellation.isRequested()) catch unreachable;
            self.fixture.cleaned += 1;
        }
    };
    var order: Order = .{ .running = &job, .fixture = &f };
    var waiting: q.Job = .{ .context = &order, .cleanup_fn = Order.cleanup };
    _ = try host.submit(request(&waiting, 2));
    var r = f.reaper(&host);
    try t.expectError(error.Busy, r.begin(.restore));
    try r.begin(.bye);
    try t.expectEqual(reap.Progress.pending, try r.poll());
    try t.expect(job.cancellation.isRequested());
    f.instant = 100_000_001;
    try t.expectEqual(reap.Progress.stop_unconfirmed, try r.poll());
    try t.expect((try host.ledger.inspect(id, 1)).execution_ref);
    try t.expectEqual(@as(usize, 1), f.destroyed); // waiting work collected first
    f.proceed.store(true, .release);
    for (0..10_000_000) |_| {
        if (try r.poll() == .collected) break;
        std.atomic.spinLoopHint();
    } else return error.Timeout;
    try t.expect(queue.thread == null);
    try t.expectEqual(@as(usize, 2), f.destroyed);
    try t.expectEqual(@as(usize, 0), host.ledger.count());
}
test "owner collection leaves other owners and shared worker available" {
    var f: Fixture = .{};
    var queue = try f.init();
    defer f.dispose(&queue);
    var host = try Host.init(&queue, 1);
    var a = f.item();
    _ = try host.submit(request(&a, 1));
    var b = f.item();
    const other = try host.submit(request(&b, 2));
    var r = f.reaper(&host);
    r.owner = 1;
    try r.begin(.owner_exit);
    try t.expectEqual(reap.Progress.collected, try r.poll());
    _ = try host.ledger.lookup(other, 2);
    try t.expect(!b.cancellation.isRequested());
    var extra = f.item();
    try t.expectError(error.Closed, host.submit(request(&extra, 1)));
    var all = f.reaper(&host);
    try all.begin(.owner_exit);
    try t.expectEqual(reap.Progress.collected, try all.poll());
}
test "idle complete restore keeps host and worker open" {
    var f: Fixture = .{};
    var queue = try f.init();
    defer f.dispose(&queue);
    var host = try Host.init(&queue, 1);
    try queue.start();
    var r = f.reaper(&host);
    try r.begin(.restore);
    try t.expect(host.accepting);
    try t.expect(queue.thread != null);
    const hook = @import("../host_task_reap.zig");
    const support = @import("support.zig");
    var output: support.Output = .{};
    const vm = try support.createMachine(&output);
    defer support.destroyMachine(vm);
    var manager: @import("../core/task_snapshot.zig").Manager = .{};
    const image = try manager.capture(t.allocator, vm);
    defer image.release();
    hook.bind(&r);
    defer hook.bind(null);
    try hook.restore(vm, image.image());
    try t.expect(host.accepting);
    try t.expect(!r.begun);
    var job = f.item();
    _ = try host.submit(request(&job, 1));
}

test "fresh VM result and shared Snapshot survive until reaper disposal" {
    const Execution = @import("../core/task_job_queue.zig").Execution;
    const snapshot = @import("../core/task_snapshot.zig");
    const support = @import("support.zig");
    const a = t.allocator;
    var output: support.Output = .{};
    const vm = try support.createMachine(&output);
    defer support.destroyMachine(vm);
    try vm.interpretLine(": JOB 2DUP 66 FILL ;");
    var manager: snapshot.Manager = .{};
    const version = try manager.capture(a, vm);
    defer version.release();
    var execution: Execution = .{ .allocator = a, .admission = try version.admit(vm), .entry = "JOB", .input = "abc" };
    var job = execution.queued();
    var f: Fixture = .{};
    var queue = try f.init();
    queue.runner = Execution.runner();
    defer f.dispose(&queue);
    var host = try Host.init(&queue, 1);
    _ = try host.submit(request(&job, 1));
    try queue.start();
    for (0..10_000_000) |_| {
        if (queue.poll(&job) != null) break;
        std.atomic.spinLoopHint();
    } else return error.Timeout;
    try t.expectEqualStrings("BBB", execution.result.?);
    try t.expectEqual(@as(usize, 1), version.references.load(.acquire));
    const Destroy = struct {
        fn call(_: ?*anyopaque, _: base.Handle, item: *q.Job, result: q.Result, _: ?Host.Publication) void {
            t.expectEqual(.succeeded, result.kind) catch unreachable;
            const payload: *Execution = @ptrCast(@alignCast(item.context.?));
            payload.deinit(); // testing allocator checks result/VM/Snapshot leaks
        }
    };
    var r: reap.Reaper = .{ .host = &host, .disposal = .{ .destroy = Destroy.call } };
    try r.begin(.restore); // validation does not close admission
    try t.expect(host.accepting);
    try r.begin(.bye);
    for (0..10_000_000) |_| {
        if (try r.poll() == .collected) break;
        std.atomic.spinLoopHint();
    } else return error.Timeout;
    try t.expect(execution.result == null);
    try t.expect(execution.admission == null);
    try t.expectEqual(@as(usize, 1), manager.live_versions.load(.acquire));
    try t.expectEqual(@as(usize, 1), version.references.load(.acquire));
}

test "main host hook handles QUIT ABORT BYE and rejects busy restoration" {
    const hook = @import("../host_task_reap.zig");
    const support = @import("support.zig");
    for ([_][]const u8{ "QUIT", "ABORT", "BYE" }) |source| {
        var output: support.Output = .{};
        const vm = try support.createMachine(&output);
        defer support.destroyMachine(vm);
        var f: Fixture = .{};
        var queue = try f.init();
        defer f.dispose(&queue);
        var host = try Host.init(&queue, 1);
        var job = f.item();
        _ = try host.submit(request(&job, 1));
        var r = f.reaper(&host);
        hook.bind(&r);
        defer hook.bind(null);
        try t.expectError(error.Busy, hook.restore(vm, "invalid image"));
        if (std.mem.eql(u8, source, "QUIT")) {
            try t.expectError(error.Quit, hook.interpret(vm, source));
        } else if (std.mem.eql(u8, source, "ABORT")) {
            try t.expectError(error.Aborted, hook.interpret(vm, source));
        } else try hook.interpret(vm, source);
        try t.expectEqual(@as(usize, if (std.mem.eql(u8, source, "BYE")) 1 else 0), f.destroyed);
        try hook.end(.owner_exit);
        try t.expectEqual(@as(usize, 1), f.destroyed);
    }
}

test "unbound hooks and REPL typo preserve tasks" {
    const hook = @import("../host_task_reap.zig");
    const support = @import("support.zig");
    var output: support.Output = .{};
    const vm = try support.createMachine(&output);
    defer support.destroyMachine(vm);
    var f: Fixture = .{};
    var queue = try f.init();
    defer f.dispose(&queue);
    var host = try Host.init(&queue, 1);
    var job = f.item();
    const id = try host.submit(request(&job, 1));
    hook.bind(null);
    try hook.end(.bye);
    try hook.interpret(vm, ": UNBOUND 42 ;");
    var manager: @import("../core/task_snapshot.zig").Manager = .{};
    const image = try manager.capture(t.allocator, vm);
    defer image.release();
    try hook.interpret(vm, ": AFTER-IMAGE 99 ;");
    try hook.restore(vm, image.image());
    try hook.interpret(vm, "UNBOUND");
    try t.expectEqual(@as(@import("../forth.zig").Cell, 42), try vm.pop());
    try t.expect(!job.cancellation.isRequested());
    try t.expect(host.accepting);
    var r = f.reaper(&host);
    hook.bind(&r);
    defer hook.bind(null);
    hook.interpret(vm, "NO-SUCH-TASK-WORD") catch {};
    try t.expect(!r.begun);
    try t.expect(!job.cancellation.isRequested());
    try r.begin(.bye);
    try host.ledger.retain(id, 1);
    try t.expectError(error.Busy, r.begin(.restore));
    try host.ledger.drop(id, 1);
    try t.expectEqual(reap.Progress.collected, try r.poll());
}

test "finish uses real common Wake" {
    var wake = try @import("../host_wake.zig").Wake.init();
    defer wake.deinit() catch unreachable;
    var f: Fixture = .{};
    f.proceed.store(true, .release);
    var queue = try q.DefaultQueue.init(@import("../host_clock.zig").clock, wake.operations(), .{ .context = &f, .run_fn = Fixture.run });
    defer f.dispose(&queue);
    var host = try Host.init(&queue, 1);
    var job = f.item();
    _ = try host.submit(request(&job, 1));
    try queue.start();
    var r = f.reaper(&host);
    try t.expectEqual(reap.Progress.collected, try r.finish(.bye));
    try t.expect(queue.thread == null);
}

test "owner exit grants a fresh collection deadline and retains terminal refs" {
    var f: Fixture = .{};
    var queue = try f.init();
    defer f.dispose(&queue);
    var host = try Host.init(&queue, 1);
    var job = f.item();
    const id = try host.submit(request(&job, 1));
    try host.requestCancel(id, 1, 0);
    try host.ledger.retain(id, 1);
    f.instant = 200_000_000;
    try host.poll();
    var r = f.reaper(&host);
    r.owner = 1;
    try r.begin(.owner_exit);
    try t.expectEqual(reap.Progress.pending, try r.poll());
    f.instant = 299_999_999;
    try t.expectEqual(reap.Progress.pending, try r.poll());
    f.instant = 300_000_000;
    try t.expectEqual(reap.Progress.stop_unconfirmed, try r.poll());
    try t.expectEqual(@as(usize, 0), f.destroyed);
    const hook = @import("../host_task_reap.zig");
    const support = @import("support.zig");
    var output: support.Output = .{};
    const vm = try support.createMachine(&output);
    defer support.destroyMachine(vm);
    hook.bind(&r);
    defer hook.bind(null);
    try t.expectError(error.HostFailed, hook.interpret(vm, "BYE"));
    try t.expect(hook.endFailed());
    try host.ledger.drop(id, 1);
    try t.expectEqual(reap.Progress.collected, try r.poll());
}
