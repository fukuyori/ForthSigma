const std = @import("std");
const support = @import("support.zig");
const forth = @import("../forth.zig");
const io = @import("../core/host_interface.zig");
const control = @import("../core/execution_control.zig");
const Fake = struct {
    var begins: usize = 0;
    var ends: usize = 0;
    var fail_begin = false;
    var fail_end = false;
    var interrupt = false;
    var end_interrupt = false;
    fn begin(_: ?*anyopaque, _: *forth.State) forth.RuntimeError!void {
        if (fail_begin) return error.HostFailed;
        begins += 1;
    }
    fn poll(_: ?*anyopaque, _: *forth.State) forth.RuntimeError!void {
        if (interrupt) return error.UserInterrupt;
    }
    fn end(_: ?*anyopaque, _: *forth.State) forth.RuntimeError!void {
        ends += 1;
        if (fail_end) return error.HostFailed;
        if (end_interrupt) return error.UserInterrupt;
    }
    const ops = io.ExecutionOps{ .begin = begin, .poll = poll, .end = end };
    fn reset() void {
        begins = 0;
        ends = 0;
        fail_begin = false;
        fail_end = false;
        interrupt = false;
        end_interrupt = false;
    }
};

test "EXEC-LIMITED owns nested budgets restores depths and does not swallow THROW" {
    if (comptime !@import("build_options").debug) return error.SkipZigTest;
    try support.skipWithout(&.{ .extension, .debug });
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    machine.writer.execution_ops = &Fake.ops;
    Fake.reset();
    try machine.interpretLine("REQUIRE-EXTENSION ALSO EXTENSION : FOREVER BEGIN 1 DROP AGAIN ; : INNER ['] FOREVER 0 EXEC-LIMITED 999 ; : SHORT 42 ;");
    try machine.interpretLine("17 ' FOREVER 20 EXEC-LIMITED");
    try support.expectStack(machine, &.{ 17, -280 });
    try std.testing.expectEqual(@as(usize, 0), machine.execution.depth);
    machine.data_depth = 0;
    try machine.interpretLine("' INNER 40 EXEC-LIMITED");
    try support.expectStack(machine, &.{-280});
    try std.testing.expectEqual(Fake.begins, Fake.ends);
    machine.data_depth = 0;
    try machine.interpretLine("' SHORT 0 EXEC-LIMITED");
    try support.expectStack(machine, &.{ 42, 0 });
    machine.data_depth = 0;
    try machine.interpretLine(": BAD -123 THROW ;");
    try std.testing.expectError(error.Thrown, machine.interpretLine("' BAD 100 EXEC-LIMITED"));
    try std.testing.expectEqual(@as(usize, 0), machine.execution.depth);
    try std.testing.expectEqual(Fake.begins, Fake.ends);
}

test "EXEC-LIMITED host errors preserve arguments before begin and cleanup after interrupt" {
    if (comptime !@import("build_options").debug) return error.SkipZigTest;
    try support.skipWithout(&.{ .extension, .debug });
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    machine.writer.execution_ops = &Fake.ops;
    Fake.reset();
    try machine.interpretLine("REQUIRE-EXTENSION ALSO EXTENSION : NOTHING ; ' NOTHING 10");
    Fake.fail_begin = true;
    try std.testing.expectError(error.HostFailed, machine.executeBuiltin(.exec_limited));
    try std.testing.expectEqual(@as(usize, 2), machine.data_depth);
    Fake.fail_begin = false;
    Fake.interrupt = true;
    try std.testing.expectError(error.UserInterrupt, machine.executeBuiltin(.exec_limited));
    try std.testing.expectEqual(@as(usize, 0), machine.execution.depth);
    try std.testing.expectEqual(Fake.begins, Fake.ends);
    Fake.fail_end = true;
    try machine.interpretLine("' NOTHING 10");
    try std.testing.expectError(error.HostFailed, machine.executeBuiltin(.exec_limited));
    try std.testing.expectEqual(@as(usize, 0), machine.execution.depth);
    control.clearStop(machine);
}

test "EXEC-LIMITED keeps CLI and explicit -280 THROW fatal and charges interpreted loops" {
    if (comptime !@import("build_options").debug) return error.SkipZigTest;
    try support.skipWithout(&.{ .extension, .debug });
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    machine.writer.execution_ops = &Fake.ops;
    Fake.reset();
    try machine.interpretLine("REQUIRE-EXTENSION ALSO EXTENSION : FOREVER BEGIN AGAIN ; : EXPLICIT -280 THROW ; : INTERPRETED S\" [BEGIN] [AGAIN]\" EVALUATE ;");
    try machine.interpretLine("' FOREVER 1");
    machine.step_limit = 1;
    machine.steps_left = 0;
    try std.testing.expectError(error.StepLimit, machine.executeBuiltin(.exec_limited));
    try std.testing.expect(machine.execution.stop == .cli);
    machine.step_limit = 0;
    machine.data_depth = 0;
    try machine.interpretLine("' EXPLICIT 100");
    try std.testing.expectError(error.StepLimit, machine.executeBuiltin(.exec_limited));
    try std.testing.expect(machine.execution.stop == .none);
    machine.data_depth = 0;
    try machine.interpretLine("' INTERPRETED 100 EXEC-LIMITED");
    try support.expectStack(machine, &.{-280});
    try std.testing.expectEqual(@as(usize, 0), machine.interpret_loop_depth);
    try std.testing.expectEqual(Fake.begins, Fake.ends);
}

test "runtime execution budgets survive image append and are not encoded" {
    if (comptime !@import("build_options").debug) return error.SkipZigTest;
    try support.skipWithout(&.{ .extension, .debug, .image });
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    const source = try support.createMachine(&output);
    defer support.destroyMachine(source);
    try source.interpretLine(": FROM-IMAGE 7 ;");
    machine.execution.depth = 1;
    machine.execution.stack[0] = .{ .remaining = 12, .unlimited = false };
    try machine.appendImage(source);
    try std.testing.expectEqual(@as(usize, 1), machine.execution.depth);
    try std.testing.expectEqual(@as(u64, 12), machine.execution.stack[0].remaining);
    machine.execution.depth = 0;
    const encoder = @import("../core/image_encoder.zig");
    var work: encoder.Workspace = undefined;
    const bytes = try std.testing.allocator.alloc(u8, try encoder.measure(machine, &work));
    defer std.testing.allocator.free(bytes);
    _ = try encoder.encode(machine, bytes, &work);
    machine.execution.depth = 1;
    machine.execution.stack[0].remaining = 999;
    const other = try std.testing.allocator.alloc(u8, bytes.len);
    defer std.testing.allocator.free(other);
    _ = try encoder.encode(machine, other, &work);
    try std.testing.expectEqualSlices(u8, bytes, other);
    machine.execution.depth = 0;
}

test "EXEC finish priority is restoration failure then body exception then pending interrupt" {
    if (comptime !@import("build_options").debug) return error.SkipZigTest;
    try support.skipWithout(&.{.extension});
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    machine.writer.execution_ops = &Fake.ops;
    Fake.reset();
    try machine.interpretLine("REQUIRE-EXTENSION ALSO EXTENSION : BAD -123 THROW ; : NOTHING ; : FOREVER BEGIN AGAIN ;");
    Fake.end_interrupt = true;
    try std.testing.expectError(error.Thrown, machine.interpretLine("' BAD 100 EXEC-LIMITED"));
    machine.data_depth = 0;
    try std.testing.expectError(error.UserInterrupt, machine.interpretLine("' NOTHING 0 EXEC-LIMITED"));
    machine.data_depth = 0;
    try std.testing.expectError(error.UserInterrupt, machine.interpretLine("' FOREVER 20 EXEC-LIMITED"));
    machine.data_depth = 0;
    Fake.fail_end = true;
    try std.testing.expectError(error.HostFailed, machine.interpretLine("' BAD 100 EXEC-LIMITED"));
    try std.testing.expectEqual(@as(usize, 0), machine.execution.depth);
    try std.testing.expectEqual(Fake.begins, Fake.ends);
}

test "native FAXPY checkpoints limit partial side effects and restore data float depths" {
    if (comptime !@import("build_options").debug) return error.SkipZigTest;
    try support.skipWithout(&.{.extension});
    try support.skipWithoutFloat();
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    machine.writer.execution_ops = &Fake.ops;
    Fake.reset();
    for (0..1024) |i| {
        try machine.writeFloat(@intCast(0x10000 + i * 8), 1);
        try machine.writeFloat(@intCast(0x14000 + i * 8), 0);
    }
    try machine.interpretLine("REQUIRE-EXTENSION ALSO EXTENSION 2E 65536 8 81920 8 1024 ' FAXPY 2 EXEC-LIMITED");
    try std.testing.expectEqual(@as(usize, 6), machine.data_depth);
    try std.testing.expectEqual(@as(forth.Cell, -280), try machine.peek(0));
    try std.testing.expectEqual(@as(usize, 1), machine.float_depth);
    try std.testing.expectEqual(@as(forth.Float, 2), try machine.readFloat(0x14000));
    try std.testing.expectEqual(@as(forth.Float, 2), try machine.readFloat(0x14000 + 255 * 8));
    try std.testing.expectEqual(@as(forth.Float, 0), try machine.readFloat(0x14000 + 256 * 8));
    try std.testing.expectEqual(Fake.begins, Fake.ends);
}
