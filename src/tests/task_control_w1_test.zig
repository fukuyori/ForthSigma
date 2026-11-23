const std = @import("std");
const forth = @import("../forth.zig");
const support = @import("support.zig");
const Cancellation = @import("../core/runtime_base.zig").Cancellation;
const defs = @import("../core/defs.zig");
const inline_calls = @import("../core/inline_calls.zig");

// Test-only rendezvous and fail-fast watchdog; no performance measurement.
const Rendezvous = struct {
    entered: std.atomic.Value(bool) = .init(false),
    finished: std.atomic.Value(bool) = .init(false),
    cancellation: Cancellation = .{},
    machine: *forth.State,
    entry: u16,
    worker_on_entry: bool,

    fn write(context: ?*anyopaque, _: []const u8) void {
        const self: *Rendezvous = @ptrCast(@alignCast(context.?));
        self.entered.store(true, .release);
    }
    fn request(self: *Rendezvous) void {
        const clock = @import("../host_clock.zig");
        const deadline = (clock.now() catch @panic("W1 watchdog clock failed")) + 30 * std.time.ns_per_s;
        while (!self.finished.load(.acquire)) {
            if (self.entered.load(.acquire)) self.cancellation.request();
            if ((clock.now() catch @panic("W1 watchdog clock failed")) >= deadline)
                @panic("W1 worker did not finish before watchdog deadline");
            std.atomic.spinLoopHint();
        }
    }
    // Test-only native reentry from an outer ordinary CATCH to a worker loop.
    fn key(context: ?*anyopaque) forth.RuntimeError!@import("../core/host_interface.zig").FileKeyResult {
        const self: *Rendezvous = @ptrCast(@alignCast(context.?));
        if (self.worker_on_entry) {
            if (self.machine.workerCancellation() != &self.cancellation) return error.HostFailed;
        }
        const previous = self.machine.workerCancellation();
        const result = self.machine.runAsWorker(self.entry, &self.cancellation);
        if (self.machine.workerCancellation() != previous) return error.HostFailed;
        try result;
        return error.HostFailed;
    }
};

fn cancelled(source: []const u8, outer: ?[]const u8, expected_inline: bool, expected_specialized: bool, check_counted: bool) !void {
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try machine.interpretLine(source);
    const entry = machine.lookup("JOB").?;
    const word = machine.words[entry];
    if (expected_inline) {
        var found = false;
        for (machine.code[word.code_start..word.code_end]) |op| found = found or inline_calls.isInline(op);
        try std.testing.expect(found);
    }
    if (expected_specialized) {
        var found = false;
        for (machine.code[0..machine.code_count]) |op| found = found or op.kind == .one_plus;
        try std.testing.expect(found);
    }
    var rendezvous: Rendezvous = .{ .machine = machine, .entry = machine.lookup("SPIN") orelse entry, .worker_on_entry = outer == null };
    machine.writer = .{ .context = &rendezvous, .write_fn = Rendezvous.write, .key_ior_fn = Rendezvous.key };
    // These would stop the counted loop; worker execution must ignore them.
    machine.step_limit = if (check_counted) 1 else 0;
    machine.steps_left = machine.step_limit;
    machine.keep_counting = check_counted;
    const requester = try std.Thread.spawn(.{}, Rendezvous.request, .{&rendezvous});
    const result = if (outer) |line| machine.interpretLine(line) else machine.runAsWorker(entry, &rendezvous.cancellation);
    // Also releases the requester on unexpected failure before reaching the writer.
    rendezvous.finished.store(true, .release);
    requester.join();
    try std.testing.expectError(error.TaskCancelled, result);
    try std.testing.expect(rendezvous.cancellation.isRequested());
    try std.testing.expectEqual(@as(usize, 0), machine.call_depth);
    try std.testing.expectEqual(@as(usize, 0), machine.frame_depth);
    try std.testing.expectEqual(@as(usize, 0), machine.catch_depth);
    try std.testing.expectEqual(machine.step_limit, machine.steps_left);
    try std.testing.expect(machine.workerCancellation() == null);
    machine.step_limit = 0;
    machine.keep_counting = false;
    machine.data_depth = 0;
    try machine.interpretLine("40 2 +");
    try support.expectStack(machine, &.{42});
}

test "W1 cross-thread cancellation of BEGIN AGAIN without counted execution" {
    try cancelled(": JOB 1 . BEGIN AGAIN ;", null, false, false, false);
}

test "W1 worker ignores step_limit and keep_counting in debug configuration" {
    if (!defs.debug_enabled) return error.SkipZigTest;
    try cancelled(": JOB 1 . BEGIN AGAIN ;", null, false, false, true);
}

test "W1 cancellation survives nested colon frames and specialized operations" {
    try cancelled(": INNER 1 . 0 BEGIN 1+ DUP DROP AGAIN ; : MIDDLE INNER ; : JOB MIDDLE ;", null, false, true, false);
}

test "W1 cancellation survives inline expansion inside a loop" {
    try cancelled(": INC 1+ ; : JOB 1 . 0 BEGIN INC AGAIN ;", null, true, true, false);
}

test "W1 native reentry retains an already active worker context" {
    try cancelled(": SPIN 1 . BEGIN AGAIN ; : JOB KEY-IOR ;", null, false, false, false);
}

test "W1 cancellation propagates through interpreted and compiled outer CATCH" {
    try cancelled(": JOB 1 . BEGIN AGAIN ; : CALLER KEY-IOR ; : WRAPPER ['] CALLER CATCH ;", "' CALLER CATCH", false, false, false);
    try cancelled(": JOB 1 . BEGIN AGAIN ; : CALLER KEY-IOR ; : WRAPPER ['] CALLER CATCH ;", "WRAPPER", false, false, false);
}

test "W1 pending cancellation is checked at loop entry and has a registered code" {
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try machine.interpretLine(": JOB 99 ;");
    var cancellation: Cancellation = .{};
    cancellation.request();
    try std.testing.expectError(error.TaskCancelled, machine.runAsWorker(machine.lookup("JOB").?, &cancellation));
    try support.expectStack(machine, &.{});
    try std.testing.expectEqual(@as(forth.Cell, -282), machine.throwCodeOf(error.TaskCancelled));
    try std.testing.expect(machine.workerCancellation() == null);
    const context = @import("../core/words_system.zig").CatchContext.init(machine);
    try std.testing.expectError(error.TaskCancelled, context.handleError(machine, error.TaskCancelled));
    machine.report(error.TaskCancelled);
    try std.testing.expect(std.mem.find(u8, output.written(), "TASK CANCELLED !") != null);
}

test "W1 provisional exclusions reject dynamic execution and PAD" {
    const cases = [_][]const u8{
        ": TARGET 1 ; : JOB ['] TARGET EXECUTE ;",
        ": JOB { XT: x } x ;",
        "DEFER D : JOB D ;",
        ": MAKER CREATE DOES> 1 ; MAKER D : JOB D ;",
        ": JOB ['] DROP CATCH ;",
        ": JOB 0 THROW ;",
        ": JOB PAD ;",
    };
    for (cases) |source| {
        var output = support.Output{};
        const machine = try support.createMachine(&output);
        defer support.destroyMachine(machine);
        try machine.interpretLine(source);
        var cancellation: Cancellation = .{};
        // XT local must get far enough to encounter .local_execute.
        try machine.push(0);
        try std.testing.expectError(error.InvalidExecutionToken, machine.runAsWorker(machine.lookup("JOB").?, &cancellation));
        try std.testing.expect(machine.workerCancellation() == null);
    }
}

test "W1 worker diagnostic registry refuses callbacks" {
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try machine.interpretLine("VARIABLE SEEN : MESSAGE 1 SEEN ! DROP S\" message\" ; ' MESSAGE 1 EXCEPTIONS");
    const code = try machine.pop();
    const seen = machine.words[machine.lookup("SEEN").?].value;
    const Probe = struct {
        machine: *forth.State,
        code: forth.Cell,
        fn key(context: ?*anyopaque) forth.RuntimeError!@import("../core/host_interface.zig").FileKeyResult {
            const self: *@This() = @ptrCast(@alignCast(context.?));
            if (self.machine.workerCancellation() == null or @import("../core/exception_registry.zig").writeMessage(self.machine, self.code)) return error.InvalidExecutionToken;
            return error.HostFailed;
        }
    };
    var probe: Probe = .{ .machine = machine, .code = code };
    machine.writer.context = &probe;
    machine.writer.key_ior_fn = Probe.key;
    var cancellation: Cancellation = .{};
    try machine.interpretLine(": JOB KEY-IOR ;");
    try std.testing.expectError(error.HostFailed, machine.runAsWorker(machine.lookup("JOB").?, &cancellation));
    try std.testing.expect(machine.workerCancellation() == null);
    try std.testing.expectEqual(@as(forth.Cell, 0), try machine.readCell(seen));
    machine.writer = output.writer();
    try std.testing.expect(@import("../core/exception_registry.zig").writeMessage(machine, code));
    try std.testing.expectEqual(@as(forth.Cell, 1), try machine.readCell(seen));
}

test "W1 rejects source interpretation and FAST-THROW at word and compiled boundaries" {
    const builtins = [_]defs.Builtin{ .evaluate, .include, .included, .require, .required, .include_file, .load_block, .thru, .assert_paren, .assert_zero, .assert_one, .assert_two, .assert_three, .fast_throw, .pad, .execute };
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try machine.interpretLine(": JOB 123 ;");
    const job = machine.lookup("JOB").?;
    const at = machine.words[job].code_start;
    var cancellation: Cancellation = .{};
    for (builtins) |builtin| {
        const id: u16 = @intCast(machine.builtinWord(builtin));
        try std.testing.expectError(error.InvalidExecutionToken, machine.runAsWorker(id, &cancellation));
        for ([_]defs.OpKind{ .call, .call_builtin, .builtin }) |kind| {
            machine.code[at] = .{ .kind = kind, .value = if (kind == .builtin) @backingInt(machine.words[id].builtin) else id };
            try std.testing.expectError(error.InvalidExecutionToken, machine.runAsWorker(job, &cancellation));
        }
        try std.testing.expect(machine.workerCancellation() == null);
        try support.expectStack(machine, &.{});
    }
    // There is no public INTERPRET word in the current dictionary.
    try std.testing.expect(machine.lookup("INTERPRET") == null);
}

test "W1 ordinary numeric minus 282 THROW remains catchable" {
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try machine.interpretLine(": RAISE -282 THROW ; ' RAISE CATCH : WRAPPER ['] RAISE CATCH ; WRAPPER : FAST -282 FAST-THROW ; ' FAST CATCH");
    try support.expectStack(machine, &.{ -282, -282, -282 });
}

test "W1 successful worker entry restores ordinary VM context" {
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try machine.interpretLine(": JOB 42 ;");
    var cancellation: Cancellation = .{};
    try machine.runAsWorker(machine.lookup("JOB").?, &cancellation);
    try std.testing.expect(machine.workerCancellation() == null);
    try support.expectStack(machine, &.{42});
}
