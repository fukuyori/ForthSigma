const std = @import("std");
const support = @import("support.zig");
const snapshot = @import("../core/task_snapshot.zig");
const job = @import("../core/task_job.zig");
const transfer = @import("../core/task_transfer.zig");
const Cancellation = @import("../core/runtime_base.zig").Cancellation;
const a = std.testing.allocator;

const Case = struct {
    entry: []const u8 = "ECHO",
    input: []const u8 = "owned result",
    cancelled: bool = false,
    expected: ?anyerror = null,
    limits: transfer.Limits = .{},
};

// The fixture and owner reference are outside fault injection. Every allocation
// in the job (including restore workspace, inspection and result copy) is inside.
fn exercise(allocator: std.mem.Allocator, main: *@import("../forth.zig").State, version: *snapshot.Snapshot, case: Case) !void {
    const baseline = version.references.load(.monotonic);
    var admission = try version.admit(main);
    var token: Cancellation = .{};
    if (case.cancelled) token.request();
    const outcome = job.run(allocator, &admission, case.entry, case.input, &token, case.limits);
    try std.testing.expectEqual(baseline, version.references.load(.monotonic));
    if (outcome) |bytes| {
        defer allocator.free(bytes);
        try std.testing.expect(case.expected == null);
        try std.testing.expectEqualStrings(case.input, bytes);
    } else |err| {
        if (err == error.OutOfMemory) return err;
        try std.testing.expectEqual(case.expected.?, err);
    }
}

test "task job releases every allocation on success failure and requested cancellation" {
    var output = support.Output{};
    const main = try support.createMachine(&output);
    defer support.destroyMachine(main);
    try main.interpretLine(": ECHO ; : BEGIN-ECHO 3 BEGIN 1- DUP 0= UNTIL DROP ; : BAD-ABI DROP ; : BAD-RANGE DROP -1 ; : DENIED PAD ; : MEMORY C@ ; : INDIRECT MEMORY ; : RUNTIME 0 0 / ;");
    var manager = snapshot.Manager{};
    const version = try manager.capture(a, main);
    defer version.release();
    const cases = [_]Case{
        .{},
        .{ .input = "" },
        .{ .entry = "BEGIN-ECHO" },
        .{ .limits = .{ .input = transfer.default_input_limit + 1 }, .expected = error.InvalidLimits },
        .{ .limits = .{ .input = 0 }, .expected = error.InputTooLarge },
        .{ .limits = .{ .result = 0 }, .expected = error.ResultTooLarge },
        .{ .entry = "BAD-ABI", .expected = error.ResultStackDepth },
        .{ .entry = "BAD-RANGE", .expected = error.NegativeResultLength },
        .{ .entry = "DENIED", .expected = error.Denied },
        .{ .entry = "MEMORY", .expected = error.InvalidAddress },
        .{ .entry = "INDIRECT", .expected = error.InvalidAddress },
        .{ .entry = "MISSING", .expected = error.EntryNotFound },
        .{ .entry = "RUNTIME", .expected = error.DivisionByZero },
        .{ .cancelled = true, .expected = error.TaskCancelled },
    };
    for (cases) |case| {
        try exercise(a, main, version, case);
        try std.testing.checkAllAllocationFailures(a, exercise, .{ main, version, case });
    }
    try std.testing.expectEqual(@as(usize, 1), manager.live_versions.load(.monotonic));
}

test "task job results outlive final snapshot reference and jobs do not share state" {
    var output = support.Output{};
    const main = try support.createMachine(&output);
    defer support.destroyMachine(main);
    // Failed execution leaves an extra return/data-stack value in its own VM.
    try main.interpretLine(": ECHO ; : DIRTY 99 >R 0 0 / ; : SHRINK 1- ;");
    var manager = snapshot.Manager{};
    const version = try manager.capture(a, main);
    var owner_live = true;
    defer if (owner_live) version.release();
    var token: Cancellation = .{};
    var first = try version.admit(main);
    const bytes = try job.run(a, &first, "SHRINK", "first", &token, .{});
    defer a.free(bytes);
    try std.testing.expectEqualStrings("firs", bytes);
    var failed = try version.admit(main);
    try std.testing.expectError(error.DivisionByZero, job.run(a, &failed, "DIRTY", "dirty", &token, .{}));
    var last = try version.admit(main);
    version.release();
    owner_live = false;
    const next = try job.run(a, &last, "ECHO", "second", &token, .{});
    defer a.free(next);
    try std.testing.expectEqual(@as(usize, 0), manager.live_versions.load(.monotonic));
    try std.testing.expectEqualStrings("second", next);
    try std.testing.expectEqualStrings("firs", bytes);
    try support.expectStack(main, &.{});
}

const setup = @import("../core/task_setup.zig");
const CancelAt = struct {
    token: *Cancellation,
    target: setup.Stage,
    reached: bool = false,
    fn visit(raw: ?*anyopaque, stage: setup.Stage) void {
        const self: *@This() = @ptrCast(@alignCast(raw.?));
        // A checkpoint must return before reaching ANY later setup boundary.
        std.debug.assert(!self.reached);
        if (stage == self.target) {
            self.reached = true;
            self.token.request();
        }
    }
};
fn cancelDuringSetup(allocator: std.mem.Allocator, main: *@import("../forth.zig").State, version: *snapshot.Snapshot, stage: setup.Stage, deferred: bool) !void {
    const baseline = version.references.load(.monotonic);
    var admission = try version.admit(main);
    var token: Cancellation = .{};
    var probe: CancelAt = .{ .token = &token, .target = stage };
    var retired: ?snapshot.FreshVm = null;
    const outcome = job.runWithOptions(allocator, &admission, "ECHO", "bytes", &token, .{}, .{ .retired_vm = if (deferred) &retired else null, .setup_hook = .{ .context = &probe, .visit = CancelAt.visit } });
    if (retired) |*vm| vm.deinit();
    try std.testing.expectEqual(baseline, version.references.load(.monotonic));
    if (outcome) |bytes| {
        allocator.free(bytes);
        return error.ExpectedCancellation;
    } else |err| {
        if (err == error.OutOfMemory) return err;
        try std.testing.expectEqual(error.TaskCancelled, err);
        try std.testing.expect(probe.reached);
    }
}
test "cancellation at every setup boundary stops before the next stage without leaks" {
    var output = support.Output{};
    const main = try support.createMachine(&output);
    defer support.destroyMachine(main);
    try main.interpretLine(": ECHO ;");
    var manager = snapshot.Manager{};
    const version = try manager.capture(a, main);
    defer version.release();
    inline for (@typeInfo(setup.Stage).@"enum".field_names) |name| {
        const stage = @field(setup.Stage, name);
        if (!std.debug.runtime_safety and (stage == .allocation_chunk or stage == .state_chunk or stage == .state_initialized_chunk)) continue;
        inline for (.{ false, true }) |deferred| {
            try cancelDuringSetup(a, main, version, stage, deferred);
            try std.testing.checkAllAllocationFailures(a, cancelDuringSetup, .{ main, version, stage, deferred });
        }
    }
}

fn queuedRetirement(allocator: std.mem.Allocator, main: *@import("../forth.zig").State, version: *snapshot.Snapshot, entry: []const u8) !void {
    const Execution = @import("../core/task_job_queue.zig").Execution;
    const baseline = version.references.load(.monotonic);
    var execution: Execution = .{ .allocator = allocator, .admission = try version.admit(main), .entry = entry, .input = "bytes" };
    var item = execution.queued();
    item.worker_retirement = true; // deterministic queue-owned return boundary
    const result = Execution.runner().run_fn(null, &item);
    // Exactly the queue order: runner returns, references sealed, independent
    // retirement destroyed, then host destroys Execution/result buffers.
    item.cleanup_fn.?(item.context);
    // Snapshot ownership must be gone before publication, while bulky VM
    // storage is still retained. This also covers failure and OOM exits.
    try std.testing.expectEqual(baseline, version.references.load(.monotonic));
    if (item.after_publication) |retired| retired.destroy(retired.context);
    const failure = execution.failure;
    if (result.kind == .succeeded) try std.testing.expectEqualStrings("bytes", execution.result.?);
    execution.deinit();
    try std.testing.expectEqual(baseline, version.references.load(.monotonic));
    if (failure) |err| if (err == error.OutOfMemory) return error.OutOfMemory;
    try std.testing.expectEqual(@as(@TypeOf(result.kind), if (std.mem.eql(u8, entry, "ECHO")) .succeeded else .failed), result.kind);
}
test "queue retirement owner releases every allocation on success failure and OOM" {
    var output = support.Output{};
    const main = try support.createMachine(&output);
    defer support.destroyMachine(main);
    try main.interpretLine(": ECHO ; : FAIL 0 0 / ;");
    var manager = snapshot.Manager{};
    const version = try manager.capture(a, main);
    defer version.release();
    for ([_][]const u8{ "ECHO", "FAIL", "MISSING" }) |entry| {
        try queuedRetirement(a, main, version, entry);
        try std.testing.checkAllAllocationFailures(a, queuedRetirement, .{ main, version, entry });
    }
}

const ChunkCancel = struct {
    token: *Cancellation,
    visits: usize = 0,
    target: setup.Stage,
    fn visit(raw: ?*anyopaque, stage: setup.Stage) void {
        const self: *@This() = @ptrCast(@alignCast(raw.?));
        if (stage != self.target) return;
        self.visits += 1;
        if (self.visits == 2) self.token.request();
    }
};
fn cancelSecondChunk(allocator: std.mem.Allocator, main: *@import("../forth.zig").State, version: *snapshot.Snapshot, stage: setup.Stage, deferred: bool) !void {
    const baseline = version.references.load(.monotonic);
    var admission = try version.admit(main);
    var token: Cancellation = .{};
    var probe: ChunkCancel = .{ .token = &token, .target = stage };
    var retired: ?snapshot.FreshVm = null;
    const outcome = job.runWithOptions(allocator, &admission, "ECHO", "bytes", &token, .{}, .{ .retired_vm = if (deferred) &retired else null, .setup_hook = .{ .context = &probe, .visit = ChunkCancel.visit } });
    if (retired) |*vm| vm.deinit();
    try std.testing.expectEqual(baseline, version.references.load(.monotonic));
    if (outcome) |bytes| {
        allocator.free(bytes);
        return error.ExpectedCancellation;
    } else |err| {
        if (err == error.OutOfMemory) return err;
        try std.testing.expectEqual(error.TaskCancelled, err);
        try std.testing.expectEqual(@as(usize, 2), probe.visits);
    }
}
test "second allocation zeroing and State initialization chunks cancel without leaks" {
    var output = support.Output{};
    const main = try support.createMachine(&output);
    defer support.destroyMachine(main);
    try main.interpretLine(": ECHO ;");
    var manager = snapshot.Manager{};
    const version = try manager.capture(a, main);
    defer version.release();
    for ([_]setup.Stage{ .allocation_chunk, .state_chunk, .zero_chunk, .state_initialized_chunk }) |stage| {
        if (!std.debug.runtime_safety and stage != .zero_chunk) continue;
        inline for (.{ false, true }) |deferred| {
            try cancelSecondChunk(a, main, version, stage, deferred);
            try std.testing.checkAllAllocationFailures(a, cancelSecondChunk, .{ main, version, stage, deferred });
        }
    }
}

test "snapshot version slot is reusable with retirement destruction withheld" {
    const Execution = @import("../core/task_job_queue.zig").Execution;
    var output = support.Output{};
    const main = try support.createMachine(&output);
    defer support.destroyMachine(main);
    try main.interpretLine(": ECHO ;");
    var manager = snapshot.Manager{};
    const version = try manager.capture(a, main);
    var owner_live = true;
    defer if (owner_live) version.release();
    const second = try manager.capture(a, main);
    defer second.release();
    const third = try manager.capture(a, main);
    defer third.release();
    var execution: Execution = .{ .allocator = a, .admission = try version.admit(main), .entry = "ECHO", .input = "bytes" };
    defer execution.deinit();
    var item = execution.queued();
    item.worker_retirement = true;
    const result = Execution.runner().run_fn(null, &item);
    defer if (item.after_publication) |retired| retired.destroy(retired.context);
    item.cleanup_fn.?(item.context);
    try std.testing.expectEqual(@as(@TypeOf(result.kind), .succeeded), result.kind);
    version.release();
    owner_live = false;
    // No retirement destruction, sleeps or race-dependent polling before capture.
    const replacement = try manager.capture(a, main);
    defer replacement.release();
    try std.testing.expectEqual(@as(usize, 3), manager.live_versions.load(.acquire));
}
