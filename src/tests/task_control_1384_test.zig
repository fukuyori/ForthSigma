const std = @import("std");
const forth = @import("../forth.zig");
const support = @import("support.zig");
const Cancellation = @import("../core/runtime_base.zig").Cancellation;
const scopes = @import("../core/task_context.zig");
const defs = @import("../core/defs.zig");

test "1384 native executeWord reentry keeps worker mode and token" {
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try machine.interpretLine(": INNER 99 ; : JOB KEY-IOR ;");
    const Probe = struct {
        machine: *forth.State,
        token: *Cancellation,
        target: u16,
        fn key(raw: ?*anyopaque) forth.RuntimeError!forth.FileKeyResult {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.token.request();
            // A native callback does not call runAsWorker again.
            try self.machine.executeWord(self.target);
            return error.HostFailed;
        }
    };
    var token: Cancellation = .{};
    var probe: Probe = .{ .machine = machine, .token = &token, .target = machine.lookup("INNER").? };
    machine.writer.context = &probe;
    machine.writer.key_ior_fn = Probe.key;
    try std.testing.expectError(error.TaskCancelled, machine.runAsWorkerWithMemory(machine.lookup("JOB").?, &token, .{ .test_host_probes = true }));
    try support.expectStack(machine, &.{});
    try std.testing.expect(machine.workerCancellation() == null);
    try std.testing.expectEqual(@as(usize, 0), machine.call_depth);
    try std.testing.expectEqual(@as(usize, 0), machine.frame_depth);
}

test "1384 worker wordInLoop fallback and synonym keep restrictions" {
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try machine.interpretLine("7 CONSTANT C SYNONYM ALIAS C : JOB ALIAS ; : SLOT 1 ; : BAD PAD ;");
    var token: Cancellation = .{};
    try machine.runAsWorker(machine.lookup("JOB").?, &token);
    try support.expectStack(machine, &.{7});
    machine.data_depth = 0;
    // The synonym passes checkWord; PAD must be rejected inside the colon target.
    const alias = machine.lookup("ALIAS").?;
    machine.words[alias].value = machine.lookup("BAD").?;
    const slot = machine.lookup("SLOT").?;
    machine.code[machine.words[slot].code_start] = .{ .kind = .call, .value = alias };
    try std.testing.expectError(error.InvalidExecutionToken, machine.runAsWorker(slot, &token));
    try std.testing.expect(machine.workerCancellation() == null);
    try support.expectStack(machine, &.{});
    try machine.executeWord(slot);
    try std.testing.expectEqual(@as(usize, 1), machine.data_depth);
}

test "1384 pending cancellation prevents native and data entry effects" {
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try machine.interpretLine("7 CONSTANT C 10");
    var token: Cancellation = .{};
    token.request();
    for ([_]u16{ @intCast(machine.builtinWord(.dup)), machine.lookup("C").? }) |entry| {
        try std.testing.expectError(error.TaskCancelled, machine.runAsWorker(entry, &token));
        try support.expectStack(machine, &.{10});
        try std.testing.expect(machine.workerCancellation() == null);
    }
}

test "1384 scopes restore tokens across nested VMs and calling threads" {
    const Probe = struct {
        machine: usize = 0,
        token: Cancellation = .{},
        fn run(self: *@This()) !void {
            // A parent thread's active scope must never be inherited.
            try std.testing.expect(scopes.cancellation(&self.machine) == null);
            var scope: scopes.Context = undefined;
            scope.enter(&self.machine, &self.token);
            defer scope.leave();
            try std.testing.expect(scopes.cancellation(&self.machine) == &self.token);
        }
    };
    var first: Probe = .{};
    var second: Probe = .{};
    var replacement: Cancellation = .{};
    var outer: scopes.Context = undefined;
    outer.enter(&first.machine, &first.token);
    defer outer.leave();
    {
        var middle: scopes.Context = undefined;
        middle.enter(&second.machine, &second.token);
        defer middle.leave();
        try std.testing.expect(scopes.cancellation(&first.machine) == &first.token);
        try std.testing.expect(scopes.cancellation(&second.machine) == &second.token);
        {
            var inner: scopes.Context = undefined;
            inner.enter(&first.machine, &replacement);
            defer inner.leave();
            try std.testing.expect(scopes.cancellation(&first.machine) == &replacement);
            try std.testing.expect(scopes.cancellation(&second.machine) == &second.token);
        }
        try std.testing.expect(scopes.cancellation(&first.machine) == &first.token);
    }
    try std.testing.expect(scopes.cancellation(&second.machine) == null);
    const thread = try std.Thread.spawn(.{}, Probe.run, .{&first});
    thread.join();
    try std.testing.expect(scopes.cancellation(&first.machine) == &first.token);
}

test "1384 worker rejects unverified DO family before operand consumption" {
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try machine.interpretLine(": JOB 1 ;");
    const job = machine.lookup("JOB").?;
    const at = machine.words[job].code_start;
    var token: Cancellation = .{};
    const kinds = [_]defs.OpKind{ .do_loop, .q_do_loop, .loop, .plus_loop, .leave, .positive_do, .unsigned_positive_do, .negative_do, .unsigned_negative_do, .inclusive_negative_do, .unsigned_inclusive_negative_do, .for_loop, .memory_up_do, .memory_down_do, .negative_loop, .next_loop };
    for (kinds) |kind| {
        machine.code[at] = .{ .kind = kind };
        try std.testing.expectError(error.InvalidExecutionToken, machine.runAsWorker(job, &token));
    }
    for ([_]defs.Builtin{ .index, .index_2, .index_3, .leave, .unloop, .question_leave, .compile_do, .compile_q_do, .compile_loop, .compile_plus_loop }) |builtin| {
        try std.testing.expectError(error.InvalidExecutionToken, machine.runAsWorker(@intCast(machine.builtinWord(builtin)), &token));
    }
    try support.expectStack(machine, &.{});
    try std.testing.expect(machine.workerCancellation() == null);
}
