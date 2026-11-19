const std = @import("std");
const forth = @import("../forth.zig");
const support = @import("support.zig");
const Fake = struct {
    var calls: usize = 0;
    fn new(_: ?*anyopaque) forth.FileResult {
        calls += 1;
        return .{ .value = 123 };
    }
    fn text(_: ?*anyopaque, id: forth.Cell, kind: forth.ProcessText, bytes: []const u8) forth.Cell {
        calls += 1;
        return if (id == 123 and kind == .argument and std.mem.eql(u8, bytes, "tool")) 0 else -1;
    }
    fn io(_: ?*anyopaque, id: forth.Cell, which: forth.Cell, mode: forth.Cell) forth.Cell {
        calls += 1;
        return if (id == 123 and which == 2 and mode == 3) 0 else -1;
    }
    fn start(_: ?*anyopaque, _: forth.Cell) forth.RuntimeError!forth.Cell {
        calls += 1;
        return error.UserInterrupt;
    }
    fn stream(_: ?*anyopaque, id: forth.Cell, which: u2) forth.FileResult {
        calls += 1;
        return .{ .value = if (id == 123) @as(forth.UCell, which) + 10 else 0 };
    }
    fn status(_: ?*anyopaque, _: forth.Cell) forth.ProcessStatus {
        calls += 1;
        return .{ .state = 2, .code = 259 };
    }
    fn wait(_: ?*anyopaque, _: forth.Cell, _: i64) forth.RuntimeError!forth.ProcessStatus {
        calls += 1;
        return error.UserInterrupt;
    }
    fn signal(_: ?*anyopaque, _: forth.Cell, force: bool) forth.Cell {
        calls += 1;
        return if (force) 0 else -1;
    }
    fn free(_: ?*anyopaque, _: forth.Cell) forth.Cell {
        calls += 1;
        return 0;
    }
    const ops: forth.ProcessOps = .{ .new = new, .text = text, .io = io, .start = start, .stream = stream, .status = status, .wait = wait, .signal = signal, .free = free };
};
test "process words dispatch arguments and retain stack on interruption or invalid memory" {
    try support.skipWithout(&.{ .files, .extension });
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    machine.writer.process_ops = &Fake.ops;
    Fake.calls = 0;
    try machine.interpretLine("REQUIRE-EXTENSION ALSO EXTENSION PROC-NEW");
    try support.expectStack(machine, &.{ 123, 0 });
    machine.data_depth = 0;
    try machine.interpretLine("S\" tool\" 123 PROC-ARG 3 2 123 PROC-IO 123 PROC-STDERR 123 PROC-STATUS");
    try support.expectStack(machine, &.{ 0, 0, 12, 0, 2, 259, 0 });
    machine.data_depth = 0;
    try machine.push(123);
    try std.testing.expectError(error.UserInterrupt, machine.executeBuiltin(.proc_start));
    try support.expectStack(machine, &.{123});
    try machine.push(42);
    try std.testing.expectError(error.UserInterrupt, machine.executeBuiltin(.proc_wait));
    try support.expectStack(machine, &.{ 123, 42 });
    machine.data_depth = 0;
    const calls = Fake.calls;
    try machine.push(-1);
    try machine.push(4);
    try machine.push(123);
    try std.testing.expectError(error.InvalidAddress, machine.executeBuiltin(.proc_arg));
    try std.testing.expectEqual(calls, Fake.calls);
    machine.data_depth = machine.data_stack.len;
    try std.testing.expectError(error.StackOverflow, machine.executeBuiltin(.proc_new));
    try std.testing.expectEqual(calls, Fake.calls);
}
test "missing process host leaves arguments untouched" {
    try support.skipWithout(&.{ .files, .extension });
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try machine.push(123);
    try machine.push(-1);
    try std.testing.expectError(error.HostUnavailable, machine.executeBuiltin(.proc_wait));
    try support.expectStack(machine, &.{ 123, -1 });
}
