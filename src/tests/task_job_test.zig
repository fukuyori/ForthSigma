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
