//! P01b stack order, bounds, and return-stack interaction.
const std = @import("std");
const forth = @import("../forth.zig");
const support = @import("support.zig");

test "P01b data words preserve the older stack and exact bit patterns" {
    const cases = [_]struct { name: []const u8, input: []const forth.Cell, expected: []const forth.Cell }{
        .{ .name = "2NIP", .input = &.{ 77, 1, 2, 3, 4 }, .expected = &.{ 77, 3, 4 } },
        .{ .name = "2TUCK", .input = &.{ 77, 1, 2, 3, 4 }, .expected = &.{ 77, 3, 4, 1, 2, 3, 4 } },
        .{ .name = "THIRD", .input = &.{ 77, -1, 0, std.math.minInt(forth.Cell) }, .expected = &.{ 77, -1, 0, std.math.minInt(forth.Cell), -1 } },
        .{ .name = "FOURTH", .input = &.{ 77, std.math.maxInt(forth.Cell), -1, 0, 1 }, .expected = &.{ 77, std.math.maxInt(forth.Cell), -1, 0, 1, std.math.maxInt(forth.Cell) } },
    };
    for (cases) |case| {
        var output = support.Output{};
        const machine = try support.createMachine(&output);
        defer support.destroyMachine(machine);
        var definition: [64]u8 = undefined;
        try machine.interpretLine(try std.fmt.bufPrint(&definition, ": P01B {s} ;", .{case.name}));
        for ([_][]const u8{ case.name, "P01B" }) |name| {
            machine.data_depth = 0;
            for (case.input) |value| try machine.push(value);
            try machine.interpretLine(name);
            try support.expectStack(machine, case.expected);
        }
    }
}

test "P01b underflow checks preserve both stacks" {
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    for ([_][]const u8{ "2NIP", "2TUCK", "THIRD", "FOURTH" }) |name| {
        const needed: usize = if (std.mem.eql(u8, name, "THIRD")) 3 else 4;
        for (0..needed) |count| {
            machine.data_depth = 0;
            for (0..count) |value| try machine.push(@intCast(value));
            try std.testing.expectError(error.StackUnderflow, machine.interpretLine(name));
            try std.testing.expectEqual(count, machine.data_depth);
        }
    }
    machine.data_depth = 0;
    try machine.push(91);
    for ([_][]const u8{ "RDROP", "2RDROP" }, 1..) |name, needed| {
        for (0..needed) |count| {
            machine.return_depth = count;
            if (count != 0) machine.return_stack[0] = 123;
            try std.testing.expectError(error.ReturnStackUnderflow, machine.interpretLine(name));
            try std.testing.expectEqual(count, machine.return_depth);
            try support.expectStack(machine, &.{91});
        }
    }
}

test "2TUCK overflow leaves the original four cells intact" {
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    const original = machine.data_stack;
    defer machine.data_stack = original;
    machine.data_stack = original[0..5];
    try machine.interpretLine("1 2 3 4");
    try std.testing.expectError(error.StackOverflow, machine.interpretLine("2TUCK"));
    try support.expectStack(machine, &.{ 1, 2, 3, 4 });
    machine.data_stack = original[0..6];
    try machine.interpretLine("2TUCK");
    try support.expectStack(machine, &.{ 3, 4, 1, 2, 3, 4 });
    machine.data_depth = 0;
    try machine.interpretLine("1 2 3 4");
    machine.data_stack = original[0..4];
    try std.testing.expectError(error.StackOverflow, machine.interpretLine("FOURTH"));
    try support.expectStack(machine, &.{ 1, 2, 3, 4 });
    machine.data_depth = 3;
    machine.data_stack = original[0..3];
    try std.testing.expectError(error.StackOverflow, machine.interpretLine("THIRD"));
    try support.expectStack(machine, &.{ 1, 2, 3 });
}

test "RDROP and 2RDROP discard user cells without disturbing loop indices" {
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try machine.interpretLine(": ONE 10 >R 20 >R RDROP R> ; : TWO 10 >R 20 30 2>R 2RDROP R> ; ONE TWO");
    try support.expectStack(machine, &.{ 10, 10 });
    machine.data_depth = 0;
    try machine.interpretLine(": LOOPS 3 0 DO I >R RDROP I LOOP ; LOOPS");
    try support.expectStack(machine, &.{ 0, 1, 2 });
    machine.data_depth = 0;
    try machine.interpretLine(": NESTED 2 0 DO 2 0 DO I J 2>R 2RDROP I J LOOP LOOP ; NESTED");
    try support.expectStack(machine, &.{ 0, 0, 1, 0, 0, 1, 1, 1 });
    try std.testing.expectEqual(@as(usize, 0), machine.return_depth);
}

test "return-stack drops work with CATCH THROW and locals" {
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try machine.interpretLine(": BAD 7 >R RDROP -99 THROW ; : OUTER 42 >R ['] BAD CATCH R> ; OUTER");
    try support.expectStack(machine, &.{ -99, 42 });
    machine.data_depth = 0;
    try machine.interpretLine(": LOCAL { a -- } a DUP 2>R 2RDROP a ; 5 LOCAL");
    try support.expectStack(machine, &.{5});
    try std.testing.expectEqual(@as(usize, 0), machine.return_depth);
}

test "compiled P01b words survive image restore and append" {
    try support.skipWithout(&.{.image});
    var output = support.Output{};
    const source = try support.createMachine(&output);
    defer support.destroyMachine(source);
    try source.interpretLine(": ST-P 1 2 3 4 2TUCK 2NIP THIRD FOURTH ; : ST-R 1 >R 2 >R 3 >R 2RDROP RDROP ;");
    const image = try std.testing.allocator.alloc(u8, source.encodedSize());
    defer std.testing.allocator.free(image);
    _ = try source.encodeImage(image);
    const restored = try support.createMachine(&output);
    defer support.destroyMachine(restored);
    try restored.restoreImage(image);
    try restored.interpretLine("ST-R ST-P");
    try support.expectStack(restored, &.{ 3, 4, 3, 4, 4, 4 });
    try std.testing.expectEqual(@as(usize, 0), restored.return_depth);
    const target = try support.createMachine(&output);
    defer support.destroyMachine(target);
    try target.interpretLine("99");
    try target.appendImage(restored);
    try target.interpretLine("ST-R ST-P");
    try support.expectStack(target, &.{ 99, 3, 4, 3, 4, 4, 4 });
    try std.testing.expectEqual(@as(usize, 0), target.return_depth);
}

test "DO-loop exit uses UNLOOP instead of deleting user return-stack cells" {
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try machine.interpretLine(": PORTABLE 3 0 DO UNLOOP EXIT LOOP ; PORTABLE 77");
    try support.expectStack(machine, &.{77});
    machine.data_depth = 0;
    try machine.interpretLine(": RAW 3 0 DO 2RDROP EXIT LOOP ; ' RAW CATCH");
    try support.expectStack(machine, &.{-6});
    try std.testing.expectEqual(@as(usize, 0), machine.return_depth);
    try std.testing.expectEqual(@as(usize, 0), machine.loop_depth);
}
