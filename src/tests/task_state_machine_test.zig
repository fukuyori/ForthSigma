//! 1367: test-only host adapter, not a TaskManager or a public Forth API.
const std = @import("std");
const t = std.testing;
const a = t.allocator;
const base = @import("../core/runtime_base.zig");
const ledger = @import("../core/task_ledger.zig");
const queue = @import("../core/task_queue.zig");
const results = @import("../core/task_results.zig");
const job = @import("../core/task_job.zig");
const snapshot = @import("../core/task_snapshot.zig");
const support = @import("support.zig");
const Wake = @import("../host_wake.zig").Wake;
const real = @import("../host_clock.zig").clock;

// Independent watchdog remains armed through assertion unwinding and worker join.
// Real clock is used only for hang prevention, never for performance measurement.
const Guard = struct {
    wake: Wake,
    done: std.atomic.Value(bool) = .init(false),
    thread: ?std.Thread = null,
    fn start(self: *Guard) !void {
        self.* = .{ .wake = try Wake.init() };
        self.thread = try std.Thread.spawn(.{}, watch, .{self});
    }
    fn watch(self: *Guard) void {
        const deadline = base.Deadline.afterMilliseconds(real.now() catch @panic("watchdog clock"), 30_000) catch unreachable;
        while (!self.done.load(.acquire)) {
            const observed = self.wake.observe();
            if (self.done.load(.acquire)) return;
            _ = self.wake.waitWithClock(observed, deadline, null, real) catch @panic("watchdog wait");
            if (deadline.expired(real.now() catch @panic("watchdog clock"))) @panic("1367 watchdog expired");
        }
    }
    fn end(self: *Guard) void {
        self.done.store(true, .release);
        self.wake.notify() catch {};
        self.thread.?.join();
        self.wake.deinit() catch {};
    }
};
const Item = struct {
    queued: queue.Job = .{},
    id: base.Handle = undefined,
    admission: ?snapshot.Admission = null,
    entry: []const u8 = "ECHO",
    input: []const u8 = "owned",
    limits: @import("../core/task_transfer.zig").Limits = .{},
    bytes: ?[]u8 = null,
    failure: ?anyerror = null,
    vm_barrier: bool = false, // test-only execution path, bypasses job admission policy
    vm_entered: std.atomic.Value(bool) = .init(false),
    vm_proceed: std.atomic.Value(bool) = .init(false),
    entered: std.atomic.Value(bool) = .init(false),
    proceed: std.atomic.Value(bool) = .init(false),
    returned: std.atomic.Value(bool) = .init(false),
    seal: std.atomic.Value(bool) = .init(false),
    cleaned: std.atomic.Value(usize) = .init(0),
    fn from(p: ?*anyopaque) *Item {
        return @ptrCast(@alignCast(p.?));
    }
    fn write(p: ?*anyopaque, _: []const u8) void {
        const self = from(p);
        self.vm_entered.store(true, .release);
        while (!self.vm_proceed.load(.acquire)) std.atomic.spinLoopHint();
    }
    // DOT is an explicitly enabled test probe, not a task_job admission grant.
    fn runVm(self: *Item, admission: *snapshot.Admission) ![]u8 {
        defer admission.deinit();
        var vm = try snapshot.FreshVm.create(a, admission);
        defer vm.deinit();
        vm.state.writer = .{ .context = self, .write_fn = write };
        const transfer = @import("../core/task_transfer.zig");
        try transfer.prepareInput(vm.state, self.input, self.limits);
        try vm.state.runAsWorkerWithMemory(try vm.resolve(self.entry), &self.queued.cancellation, .{ .test_host_probes = true });
        return transfer.copyResult(vm.state, a, self.limits);
    }
    fn cleanup(p: ?*anyopaque) void {
        const self = from(p);
        if (self.admission) |*admission| admission.deinit();
        self.admission = null;
        _ = self.cleaned.fetchAdd(1, .release);
    }
};
const Host = struct {
    book: ledger.DefaultLedger,
    q: queue.DefaultQueue,
    ticks: base.Instant = 0, // changed only while worker is held at a test barrier
    clock_block: bool = false,
    clock_entered: std.atomic.Value(bool) = .init(false),
    clock_proceed: std.atomic.Value(bool) = .init(false),
    notices: std.atomic.Value(usize) = .init(0),
    lost: bool = true,
    budgets: results.Budgets = .{},
    fn from(p: ?*anyopaque) *Host {
        return @ptrCast(@alignCast(p.?));
    }
    fn now(p: ?*anyopaque) base.Error!base.Instant {
        const self = from(p);
        if (self.clock_block) {
            self.clock_entered.store(true, .release);
            while (!self.clock_proceed.load(.acquire)) std.atomic.spinLoopHint();
        }
        return self.ticks;
    }
    fn observe(_: ?*anyopaque) u64 {
        return 0;
    } // all notifications coalesce
    fn notify(p: ?*anyopaque) base.Error!void {
        const self = from(p);
        _ = self.notices.fetchAdd(1, .release);
        if (self.lost) return error.HostFailed;
    }
    fn wait(_: ?*anyopaque, _: u64, _: base.Deadline, _: ?*const base.Cancellation, _: base.Clock) base.Error!base.WakeOutcome {
        return .timeout;
    }
    fn init(self: *Host) !void {
        self.* = .{ .book = try ledger.DefaultLedger.init(1367), .q = undefined };
        self.q = try queue.DefaultQueue.init(.{ .context = self, .now_fn = now }, .{ .context = self, .observe_fn = observe, .notify_fn = notify, .wait_fn = wait }, .{ .run_fn = run });
    }
    fn run(_: ?*anyopaque, queued: *queue.Job) queue.Result {
        const item = Item.from(queued.context);
        item.entered.store(true, .release);
        while (!item.proceed.load(.acquire)) std.atomic.spinLoopHint();
        var admission = item.admission.?;
        item.admission = null;
        const outcome = if (item.vm_barrier) item.runVm(&admission) else job.run(a, &admission, item.entry, item.input, &queued.cancellation, item.limits);
        const result: queue.Result = if (outcome) |bytes| blk: {
            item.bytes = bytes;
            break :blk .{ .kind = .succeeded };
        } else |err| blk: {
            item.failure = err;
            break :blk .{ .kind = if (err == error.TaskCancelled) .cancelled else .failed, .reason = .runner };
        };
        item.returned.store(true, .release);
        while (!item.seal.load(.acquire)) std.atomic.spinLoopHint();
        return result;
    }
    fn submit(self: *Host, item: *Item, version: *snapshot.Snapshot, main: *@import("../forth.zig").State, ms: i64) !void {
        item.id = try self.book.register(1);
        errdefer _ = self.book.collect(item.id, 1) catch unreachable;
        item.admission = try version.admit(main);
        errdefer {
            item.admission.?.deinit();
            item.admission = null;
        }
        item.queued = .{ .context = item, .cleanup_fn = Item.cleanup };
        try self.q.submit(&item.queued, ms);
        try self.book.publish(item.id, 1);
    }
    fn acquired(self: *Host, item: *Item) !void {
        while (!item.entered.load(.acquire)) std.atomic.spinLoopHint();
        try self.book.start(item.id, 1);
    }
    fn cancel(self: *Host, item: *Item) !void {
        try self.book.cancel(item.id, 1);
        self.q.cancel(&item.queued);
    }
    fn release(self: *Host, item: *Item) !void {
        try self.book.release(item.id, 1);
        self.q.release(&item.queued);
    }
    fn accept(self: *Host, item: *Item) !results.Completion {
        var sealed: queue.Result = undefined;
        while (true) {
            if (self.q.poll(&item.queued)) |value| {
                sealed = value;
                break;
            }
            std.atomic.spinLoopHint();
        }
        const state: ledger.State = switch (sealed.kind) {
            .succeeded => .succeeded,
            .failed => .failed,
            .cancelled => .cancelled,
        };
        // Budget is host-only. Queue publication is the exclusive handback.
        var buffer: ?results.Buffer = null;
        if (item.bytes) |bytes| {
            defer a.free(bytes);
            item.bytes = null;
            buffer = try results.Buffer.copy(a, &self.budgets.transfer, bytes, results.result_limit);
        }
        const completion = results.Completion.init(switch (sealed.kind) {
            .succeeded => .succeeded,
            .failed => .failed,
            .cancelled => .cancelled,
        }, buffer, if (state == .succeeded) null else .{ .code = if (state == .cancelled) .cancelled else .execution }, null);
        if (sealed.reason == .queue_expired and (try self.book.inspect(item.id, 1)).state == .queued) {
            _ = try self.book.failQueued(item.id, 1, .queue_expired);
        } else _ = try self.book.finish(item.id, 1, state);
        return completion;
    }
    fn query(self: *Host, item: *Item, completion: *const results.Completion, destination: []u8) !?results.Read {
        _ = try self.book.lookup(item.id, 1);
        return completion.queryResult(destination);
    }
    fn dispose(self: *Host, items: []Item) void {
        self.clock_proceed.store(true, .release);
        for (items) |*item| {
            item.proceed.store(true, .release);
            item.vm_proceed.store(true, .release);
            item.seal.store(true, .release);
        }
        self.q.stop();
        while (!self.q.joinIfStopped()) std.atomic.spinLoopHint();
        for (items) |*item| {
            if (item.bytes) |bytes| a.free(bytes);
            if (item.admission) |*admission| admission.deinit();
        }
        self.q.deinit() catch @panic("queue cleanup");
    }
};
fn awaitFlag(flag: *std.atomic.Value(bool)) void {
    while (!flag.load(.acquire)) std.atomic.spinLoopHint();
}
fn awaitVm(item: *Item) !void {
    while (!item.vm_entered.load(.acquire)) {
        // A rejected probe must report its error instead of waiting for a
        // callback that can no longer run. returned publishes failure too.
        if (item.returned.load(.acquire)) return item.failure orelse error.VmBarrierNotReached;
        std.atomic.spinLoopHint();
    }
}

// Every case uses a real fresh VM. Boundaries include runner entry, VM output,
// job return, queue sealing, and host terminal acceptance.
test "1367 T02-T04 T06-T08 T11 T13 T18-T20 execution CANCEL RELEASE ordering matrix" {
    var guard: Guard = undefined;
    try guard.start();
    defer guard.end();
    var output = support.Output{};
    const main = try support.createMachine(&output);
    defer support.destroyMachine(main);
    try main.interpretLine(": ECHO ; : FAIL 0 0 / ; : HELD-ECHO 65 . ; : HELD-FAIL 65 . 0 0 / ;");
    var manager = snapshot.Manager{};
    const version = try manager.capture(a, main);
    defer version.release();

    // 0: before execution, 1: return before seal, 2: published before accept,
    // 3: after terminal acceptance, 4: inside VM DOT after entry checks.
    // Both cancel and release at every boundary.
    for ([_][]const u8{ "ECHO", "FAIL" }) |entry| {
        for (0..5) |point| {
            for ([_]bool{ false, true }) |release| {
                var host: Host = undefined;
                try host.init();
                var items = [_]Item{.{ .entry = if (point == 4) (if (std.mem.eql(u8, entry, "FAIL")) "HELD-FAIL" else "HELD-ECHO") else entry, .vm_barrier = point == 4 }};
                const item = &items[0];
                // Each queue lifetime is pinned and joined before stack reuse.
                defer host.dispose(&items);
                try host.submit(item, version, main, 100);
                try t.expectEqual(ledger.State.queued, (try host.book.lookup(item.id, 1)).state);
                try host.q.start();
                try host.acquired(item);
                if (point == 0) {
                    if (release) try host.release(item) else try host.cancel(item);
                }
                item.proceed.store(true, .release);
                if (point == 4) {
                    try awaitVm(item);
                    if (release) try host.release(item) else try host.cancel(item);
                    try t.expect(item.queued.cancellation.isRequested());
                    try t.expect((try host.book.inspect(item.id, 1)).cancel_requested);
                    item.vm_proceed.store(true, .release);
                }
                awaitFlag(&item.returned);
                if (point == 1) {
                    if (release) try host.release(item) else try host.cancel(item);
                }
                item.seal.store(true, .release);
                awaitFlag(&item.queued.ready);
                if (point == 2) {
                    if (release) try host.release(item) else try host.cancel(item);
                }
                var completion = try host.accept(item);
                defer {
                    completion.deinit();
                    t.expectEqual(@as(usize, 0), host.budgets.transfer.used) catch @panic("transfer budget leak");
                }
                if (point == 3) {
                    if (release) try host.release(item) else try host.cancel(item);
                }
                const expected: ledger.State = if (point == 0) .cancelled else if (std.mem.eql(u8, entry, "FAIL")) .failed else .succeeded;
                try t.expectEqual(expected, (try host.book.inspect(item.id, 1)).state);
                if (point == 0) try t.expectEqual(error.TaskCancelled, item.failure.?);
                if (expected == .failed) try t.expectEqual(error.DivisionByZero, item.failure.?);
                try t.expect(completion.secondary == null);
                if (point < 3 or point == 4) try t.expect((try host.book.inspect(item.id, 1)).cancel_requested);
                try t.expect(!try host.book.finish(item.id, 1, expected));
                try t.expectError(error.ConflictingTerminal, host.book.finish(item.id, 1, if (expected == .failed) .succeeded else .failed));
                if (!release) try host.release(item);
                try t.expectError(error.InvalidHandle, host.book.cancel(item.id, 1));
                try t.expectError(error.InvalidHandle, host.book.release(item.id, 1));
                // A copy/WAIT reference independently prevents reclamation.
                try host.book.retain(item.id, 1);
                try t.expectError(error.ReferencesRemain, host.book.collect(item.id, 1));
                try host.book.executionStopped(item.id, 1);
                try t.expectError(error.ReferencesRemain, host.book.collect(item.id, 1));
                if (expected == .succeeded) {
                    var short: [1]u8 = .{0x5a};
                    try t.expect(!completion.queryResult(&short).?.copied);
                    try t.expectEqual(@as(u8, 0x5a), short[0]);
                    var dest: [5]u8 = undefined;
                    for (0..2) |_| {
                        try t.expect(completion.queryResult(&dest).?.copied);
                        try t.expectEqualStrings("owned", &dest);
                    }
                } else try t.expect(completion.queryResult(&.{}) == null);
                try host.book.drop(item.id, 1);
                _ = try host.book.collect(item.id, 1);
                try t.expectEqual(@as(usize, 1), item.cleaned.load(.acquire));
                try t.expectEqual(@as(usize, 0), host.book.count());
                try t.expectEqual(@as(usize, 1), version.references.load(.acquire));
                // Deferred shutdown executes before reinitialization on the next iteration.
            }
        }
    }
}

test "1367 T01 T03 T07-T10 T12 T15-T17 queue host wins expiry identity and owner exit" {
    var guard: Guard = undefined;
    try guard.start();
    defer guard.end();
    var output = support.Output{};
    const main = try support.createMachine(&output);
    defer support.destroyMachine(main);
    try main.interpretLine(": ECHO ;");
    var manager = snapshot.Manager{};
    const version = try manager.capture(a, main);
    defer version.release();
    var host: Host = undefined;
    try host.init();
    var items: [5]Item = @splat(.{});
    defer host.dispose(&items);
    for (items[0..4], 0..) |_, i| try host.submit(&items[i], version, main, if (i == 3) 50 else 200);
    try t.expectError(error.QueueFull, host.submit(&items[4], version, main, 100));
    try t.expectEqual(@as(usize, 4), host.book.count());
    try t.expectEqual(@as(usize, 5), version.references.load(.acquire));
    try t.expect(items[4].admission == null);
    try t.expectEqualStrings("owned", items[4].input);
    const before = try host.book.lookup(items[0].id, 1);
    for ([_]base.Handle{ .{ .epoch = 1, .serial = items[0].id.serial }, .{ .epoch = 1367, .serial = 0 }, items[4].id }) |bad| {
        try t.expectError(error.InvalidHandle, host.book.cancel(bad, 1));
        try t.expectError(error.InvalidHandle, host.book.release(bad, 1));
    }
    try t.expectError(error.WrongOwner, host.book.cancel(items[0].id, 2));
    const other = try host.book.table_for_testing.insert(1, .process, .{});
    try t.expectError(error.WrongKind, host.book.cancel(other, 2));
    _ = try host.book.table_for_testing.remove(other, 1, .process);
    try t.expectEqualDeep(before, try host.book.lookup(items[0].id, 1));
    // WAIT is a test-side retained reference/recheck, not the future WAIT API.
    try host.book.retain(items[0].id, 1);
    try host.book.drop(items[0].id, 1); // waiter timeout/interruption alone
    try t.expectEqualDeep(before, try host.book.lookup(items[0].id, 1));
    try host.cancel(&items[0]);
    try host.cancel(&items[0]);
    var cancelled = try host.accept(&items[0]);
    defer cancelled.deinit();
    try host.release(&items[0]);
    try t.expectError(error.InvalidHandle, host.book.cancel(items[0].id, 1));
    try t.expectEqual(@as(usize, 4), version.references.load(.acquire));
    try host.release(&items[1]);
    try t.expectError(error.InvalidHandle, host.book.release(items[1].id, 1));
    var released = try host.accept(&items[1]);
    defer released.deinit();
    // Exact fake-clock boundary, including a nonexpired front item.
    host.ticks = 49_999_999;
    try t.expect(host.q.poll(&items[3].queued) == null);
    host.ticks = 50_000_000;
    var expired = try host.accept(&items[3]);
    defer expired.deinit();
    try t.expectEqual(.queue_expired, items[3].queued.terminal.?.reason);
    try t.expectEqual(ledger.State.failed, (try host.book.lookup(items[3].id, 1)).state);
    try t.expect(!(try host.book.lookup(items[3].id, 1)).cancel_requested);
    try t.expect(host.q.poll(&items[2].queued) == null);
    try t.expectEqual(@as(usize, 4), try host.book.endOwner(1));
    host.q.stop();
    var ended = try host.accept(&items[2]);
    defer ended.deinit();
    try t.expectEqual(ledger.State.cancelled, (try host.book.inspect(items[2].id, 1)).state);
    for (items[0..4]) |*item| {
        try t.expectError(error.InvalidHandle, host.book.lookup(item.id, 1));
        _ = try host.book.collect(item.id, 1);
        try t.expectEqual(@as(usize, 1), item.cleaned.load(.acquire));
        try t.expect(!item.entered.load(.acquire));
    }
    try t.expectEqual(@as(usize, 1), version.references.load(.acquire));
    // Slot reuse cannot make a deleted ID valid; capacity includes reservations.
    const reused = try host.book.register(1);
    try t.expectError(error.InvalidHandle, host.book.inspect(items[0].id, 1));
    _ = try host.book.collect(reused, 1);
    var ids: [16]base.Handle = undefined;
    for (&ids) |*id| id.* = try host.book.register(1);
    try t.expectError(error.ResourceFull, host.book.register(1));
    for (ids) |id| _ = try host.book.collect(id, 1);
    host.book.table_for_testing.next_serial = std.math.maxInt(u64);
    const last = try host.book.register(1);
    _ = try host.book.collect(last, 1);
    try t.expectError(error.IdentityExhausted, host.book.register(1));
    try t.expectEqual(@as(usize, 0), host.book.count());
    // Start after host removal: none of the four jobs may reach the runner.
    try host.q.start();
    host.q.stop();
    while (!host.q.joinIfStopped()) std.atomic.spinLoopHint();
    for (items[0..4]) |*item| try t.expect(!item.entered.load(.acquire));
}

test "1367 T08 T12-T14 T17-T18 worker wins owner exit retains released active and four waiting" {
    var guard: Guard = undefined;
    try guard.start();
    defer guard.end();
    var output = support.Output{};
    const main = try support.createMachine(&output);
    defer support.destroyMachine(main);
    try main.interpretLine(": ECHO ;");
    var manager = snapshot.Manager{};
    const version = try manager.capture(a, main);
    defer version.release();
    var host: Host = undefined;
    try host.init();
    var items: [6]Item = @splat(.{});
    defer host.dispose(&items);
    try host.submit(&items[0], version, main, 100);
    try host.q.start();
    try host.acquired(&items[0]);
    for (1..5) |i| try host.submit(&items[i], version, main, 100);
    try t.expectError(error.QueueFull, host.submit(&items[5], version, main, 100));
    try host.release(&items[0]);
    try host.book.markStopUnconfirmed(items[0].id, 1);
    host.q.markUnresponsive();
    try t.expectError(error.ReferencesRemain, host.book.collect(items[0].id, 1));
    try t.expectError(error.WorkerOccupied, host.book.checkWorkerAvailable());
    try t.expectEqual(ledger.State.running, (try host.book.inspect(items[0].id, 1)).state);
    try t.expectEqual(@as(usize, 6), version.references.load(.acquire));
    try t.expectEqual(@as(usize, 5), try host.book.endOwner(1));
    host.q.stop();
    try t.expect(!host.q.joinIfStopped());
    try t.expectError(error.WorkerUnresponsive, host.q.deinit());
    for (1..5) |i| {
        var completion = try host.accept(&items[i]);
        completion.deinit();
        _ = try host.book.collect(items[i].id, 1);
        try t.expect(!items[i].entered.load(.acquire));
    }
    try t.expectEqual(@as(usize, 2), version.references.load(.acquire));
    items[0].proceed.store(true, .release);
    awaitFlag(&items[0].returned);
    items[0].seal.store(true, .release);
    var completion = try host.accept(&items[0]);
    defer {
        completion.deinit();
        t.expectEqual(@as(usize, 0), host.budgets.transfer.used) catch @panic("transfer budget leak");
    }
    try t.expectEqual(results.Terminal.cancelled, completion.terminal);
    try t.expectError(error.ReferencesRemain, host.book.collect(items[0].id, 1));
    while (!host.q.joinIfStopped()) std.atomic.spinLoopHint();
    try host.book.executionStopped(items[0].id, 1);
    _ = try host.book.collect(items[0].id, 1);
    try t.expectEqual(@as(usize, 0), host.book.count());
    try t.expectEqual(@as(usize, 1), version.references.load(.acquire));
    try t.expect(host.q.notificationFailed());
}

test "1367 T19 result limit fails before publication while destination shortage preserves success" {
    var guard: Guard = undefined;
    try guard.start();
    defer guard.end();
    var output = support.Output{};
    const main = try support.createMachine(&output);
    defer support.destroyMachine(main);
    try main.interpretLine(": ECHO ;");
    var manager = snapshot.Manager{};
    const version = try manager.capture(a, main);
    defer version.release();
    var host: Host = undefined;
    try host.init();
    var items = [_]Item{.{ .limits = .{ .result = 0 } }};
    defer host.dispose(&items);
    try host.submit(&items[0], version, main, 100);
    try host.q.start();
    try host.acquired(&items[0]);
    items[0].proceed.store(true, .release);
    items[0].seal.store(true, .release);
    var completion = try host.accept(&items[0]);
    defer {
        completion.deinit();
        t.expectEqual(@as(usize, 0), host.budgets.transfer.used) catch @panic("transfer budget leak");
    }
    try t.expectEqual(error.ResultTooLarge, items[0].failure.?);
    try t.expectEqual(results.Terminal.failed, completion.terminal);
    try t.expectEqual(ledger.State.failed, (try host.book.lookup(items[0].id, 1)).state);
    try host.release(&items[0]);
    try host.book.executionStopped(items[0].id, 1);
    _ = try host.book.collect(items[0].id, 1);
}

// Minimal consumer of existing ledger references, intentionally test-only.
// Exercises ledger reference/recheck ordering only, not WAIT (1369/1372).
const Waiter = struct {
    id: base.Handle,
    held: bool = true,
    outcome: ?enum { terminal, released, timeout, interrupted } = null,
    fn begin(host: *Host, item: *Item) !Waiter {
        _ = try host.book.lookup(item.id, 1);
        try host.book.retain(item.id, 1);
        return .{ .id = item.id };
    }
    fn check(self: *Waiter, host: *Host, timed_out: bool, interrupted: bool) !void {
        if (!self.held) return;
        const record = host.book.lookup(self.id, 1) catch |err| {
            if (err != error.InvalidHandle) return err;
            self.outcome = .released;
            try self.drop(host);
            return;
        };
        if (record.state.terminal()) self.outcome = .terminal else if (interrupted) self.outcome = .interrupted else if (timed_out) self.outcome = .timeout;
        if (self.outcome != null) try self.drop(host);
    }
    fn drop(self: *Waiter, host: *Host) !void {
        if (self.held) try host.book.drop(self.id, 1);
        self.held = false;
    }
};

test "1367 T09-T11 coalesced lost repeated notifications ledger reference model and RELEASE recheck" {
    var guard: Guard = undefined;
    try guard.start();
    defer guard.end();
    var output = support.Output{};
    const main = try support.createMachine(&output);
    defer support.destroyMachine(main);
    try main.interpretLine(": ECHO ;");
    var manager = snapshot.Manager{};
    const version = try manager.capture(a, main);
    defer version.release();
    for (0..4) |order| {
        var host: Host = undefined;
        try host.init();
        var items = [_]Item{.{}};
        defer host.dispose(&items);
        const item = &items[0];
        try host.submit(item, version, main, 100);
        try host.q.start();
        try host.acquired(item);
        var timeout = try Waiter.begin(&host, item);
        defer timeout.drop(&host) catch unreachable;
        var interrupted = try Waiter.begin(&host, item);
        defer interrupted.drop(&host) catch unreachable;
        try timeout.check(&host, true, false);
        try interrupted.check(&host, false, true);
        try t.expectEqual(.timeout, timeout.outcome.?);
        try t.expectEqual(.interrupted, interrupted.outcome.?);
        try t.expectEqual(ledger.State.running, (try host.book.lookup(item.id, 1)).state);
        var waiter: ?Waiter = null;
        defer if (waiter) |*w| w.drop(&host) catch unreachable;
        if (order != 1) waiter = try Waiter.begin(&host, item);
        // Complete the real job before manipulating RELEASE: outcome is success.
        item.proceed.store(true, .release);
        awaitFlag(&item.returned);
        if (order == 2) try host.release(item);
        item.seal.store(true, .release);
        var completion = try host.accept(item);
        defer {
            completion.deinit();
            t.expectEqual(@as(usize, 0), host.budgets.transfer.used) catch @panic("transfer budget leak");
        }
        if (order == 1) waiter = try Waiter.begin(&host, item);
        if (order == 3) {
            try waiter.?.check(&host, false, false);
            try host.release(item); // already returned WAIT outcome stays terminal
        }
        // No notification count or generation is used as terminal evidence.
        try waiter.?.check(&host, false, false);
        try waiter.?.check(&host, false, false);
        if (order == 2) try t.expectEqual(.released, waiter.?.outcome.?) else try t.expectEqual(.terminal, waiter.?.outcome.?);
        const saved = try host.book.inspect(item.id, 1);
        for (0..3) |_| {
            try t.expectEqual(.succeeded, host.q.poll(&item.queued).?.kind);
            try t.expect(!try host.book.finish(item.id, 1, .succeeded));
        }
        try t.expectEqualDeep(saved, try host.book.inspect(item.id, 1));
        if (order < 2) {
            var small: [1]u8 = .{0x5a};
            const short = (try host.query(item, &completion, &small)).?;
            try t.expectEqual(@as(usize, 5), short.required);
            try t.expect(!short.copied);
            try t.expectEqual(@as(u8, 0x5a), small[0]);
            try host.book.retain(item.id, 1); // copy begins before RELEASE
            try host.release(item);
            try t.expectError(error.InvalidHandle, host.query(item, &completion, &small));
            try host.book.executionStopped(item.id, 1);
            try t.expectError(error.ReferencesRemain, host.book.collect(item.id, 1));
            var destination: [5]u8 = undefined;
            try t.expect(completion.queryResult(&destination).?.copied);
            try t.expectEqualStrings("owned", &destination);
            try host.book.drop(item.id, 1); // previously started copy finishes
        } else try host.book.executionStopped(item.id, 1);
        _ = try host.book.collect(item.id, 1);
        try t.expectEqual(@as(usize, 0), host.book.count());
    }
}

test "1367 T01 T17 stale admission rolls back while admitted queued snapshot executes" {
    var guard: Guard = undefined;
    try guard.start();
    defer guard.end();
    var output = support.Output{};
    const main = try support.createMachine(&output);
    defer support.destroyMachine(main);
    try main.interpretLine(": ECHO ;");
    var manager = snapshot.Manager{};
    const version = try manager.capture(a, main);
    defer version.release();
    var host: Host = undefined;
    try host.init();
    var items: [2]Item = @splat(.{});
    defer host.dispose(&items);
    try host.submit(&items[0], version, main, 100);
    try main.interpretLine("FORGET ECHO : ECHO DROP ;");
    try t.expectError(error.StaleSnapshot, host.submit(&items[1], version, main, 100));
    try t.expectEqual(@as(usize, 1), host.book.count());
    try t.expectEqual(@as(usize, 2), version.references.load(.acquire));
    try t.expectError(error.InvalidHandle, host.book.lookup(items[1].id, 1));
    try host.q.start();
    try host.acquired(&items[0]);
    items[0].proceed.store(true, .release);
    items[0].seal.store(true, .release);
    var completion = try host.accept(&items[0]);
    defer {
        completion.deinit();
        t.expectEqual(@as(usize, 0), host.budgets.transfer.used) catch @panic("transfer budget leak");
    }
    var dest: [5]u8 = undefined;
    try t.expect(completion.queryResult(&dest).?.copied);
    try t.expectEqualStrings("owned", &dest);
    try host.release(&items[0]);
    try host.book.executionStopped(items[0].id, 1);
    _ = try host.book.collect(items[0].id, 1);
    try t.expectEqual(@as(usize, 1), version.references.load(.acquire));
}

test "1367 T03 T08 worker acquisition before entry cancellation release owner exit and expiry" {
    var guard: Guard = undefined;
    try guard.start();
    defer guard.end();
    var output = support.Output{};
    const main = try support.createMachine(&output);
    defer support.destroyMachine(main);
    try main.interpretLine(": ECHO ;");
    var manager = snapshot.Manager{};
    const version = try manager.capture(a, main);
    defer version.release();
    for (0..4) |order| {
        var host: Host = undefined;
        try host.init();
        var items = [_]Item{.{}};
        defer host.dispose(&items);
        const item = &items[0];
        try host.submit(item, version, main, 50);
        host.clock_block = true;
        try host.q.start();
        awaitFlag(&host.clock_entered); // queue acquired; cancellation check not run
        try host.book.start(item.id, 1);
        switch (order) {
            0 => {
                try host.cancel(item);
                try host.cancel(item);
            },
            1 => try host.release(item),
            2 => {
                _ = try host.book.endOwner(1);
                host.q.stop();
            },
            3 => host.ticks = 50_000_000,
            else => unreachable,
        }
        try t.expect(!item.entered.load(.acquire));
        host.clock_proceed.store(true, .release);
        // Let the worker publish: do not let host expiry win the removal.
        awaitFlag(&item.queued.ready);
        // Worker-acquired expiry is a running failure, not failQueued.
        var completion = try host.accept(item);
        completion.deinit();
        t.expectEqual(@as(usize, 0), host.budgets.transfer.used) catch @panic("transfer budget leak");
        if (order == 3) {
            try t.expectEqual(.queue_expired, item.queued.result.reason);
            try t.expectEqual(ledger.State.failed, (try host.book.inspect(item.id, 1)).state);
        } else try t.expectEqual(ledger.State.cancelled, (try host.book.inspect(item.id, 1)).state);
        if (order == 0 or order == 3) try host.release(item);
        try host.book.executionStopped(item.id, 1);
        _ = try host.book.collect(item.id, 1);
        try t.expectEqual(@as(usize, 1), item.cleaned.load(.acquire));
        try t.expectEqual(@as(usize, 1), version.references.load(.acquire));
        try t.expect(!item.entered.load(.acquire));
    }
}
