//! P01c data layout, atomic allocation bounds, and cell rotations.
const std = @import("std");
const forth = @import("../forth.zig");
const support = @import("support.zig");

test "2, stores the top cell first and matches 2@ even at an unaligned HERE" {
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try machine.interpretLine("1 C,");
    const before = machine.data_here;
    try machine.push(std.math.minInt(forth.Cell));
    try machine.push(std.math.maxInt(forth.Cell));
    try machine.interpretLine("2,");
    try std.testing.expectEqual(before + 16, machine.data_here);
    try std.testing.expectEqual(@as(forth.Cell, std.math.maxInt(forth.Cell)), try machine.readCell(before));
    try std.testing.expectEqual(@as(forth.Cell, std.math.minInt(forth.Cell)), try machine.readCell(before + 8));
    try machine.push(before);
    try machine.interpretLine("2@");
    try support.expectStack(machine, &.{ std.math.minInt(forth.Cell), std.math.maxInt(forth.Cell) });
}

test "2, rejects one-cell space without partial writes and accepts exactly two cells" {
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    machine.data_here = machine.sizes.dataLimit() - 8;
    const before = machine.data_here;
    try machine.writeCell(before, 77);
    try machine.interpretLine("11 22");
    try std.testing.expectError(error.MemoryExhausted, machine.interpretLine("2,"));
    try std.testing.expectEqual(before, machine.data_here);
    try std.testing.expectEqual(@as(forth.Cell, 77), try machine.readCell(before));
    try support.expectStack(machine, &.{ 11, 22 });
    machine.data_here = machine.sizes.dataLimit() - 16;
    try machine.interpretLine("2,");
    try std.testing.expectEqual(machine.sizes.dataLimit(), machine.data_here);
    try std.testing.expectEqual(@as(forth.Cell, 22), try machine.readCell(machine.data_here - 16));
    try std.testing.expectEqual(@as(forth.Cell, 11), try machine.readCell(machine.data_here - 8));
    try support.expectStack(machine, &.{});
}

test "2, requires both inputs before allocating and MARKER reclaims its cells" {
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    const before = machine.data_here;
    try std.testing.expectError(error.StackUnderflow, machine.interpretLine("2,"));
    try machine.push(1);
    try std.testing.expectError(error.StackUnderflow, machine.interpretLine("2,"));
    try std.testing.expectEqual(before, machine.data_here);
    try support.expectStack(machine, &.{1});
    machine.data_depth = 0;
    try machine.interpretLine("MARKER GONE 11 22 2, GONE");
    try std.testing.expectEqual(before, machine.data_here);
    try std.testing.expect(machine.lookup("GONE") == null);
}

test "ROL ROR handle zero whole-cell and negative raw counts without signed shifts" {
    const Cases = struct { name: []const u8, bits: forth.UCell, count: forth.Cell, expected: forth.UCell };
    const cases = [_]Cases{
        .{ .name = "ROL", .bits = 1, .count = 0, .expected = 1 },
        .{ .name = "ROR", .bits = 1, .count = 0, .expected = 1 },
        .{ .name = "ROL", .bits = 1, .count = 63, .expected = 0x8000000000000000 },
        .{ .name = "ROR", .bits = 1, .count = 1, .expected = 0x8000000000000000 },
        .{ .name = "ROL", .bits = 0x8000000000000000, .count = 1, .expected = 1 },
        .{ .name = "ROR", .bits = 0x8000000000000000, .count = 63, .expected = 1 },
        .{ .name = "ROL", .bits = 1, .count = 64, .expected = 1 },
        .{ .name = "ROR", .bits = 1, .count = 128, .expected = 1 },
        .{ .name = "ROL", .bits = 1, .count = 65, .expected = 2 },
        .{ .name = "ROR", .bits = 1, .count = -1, .expected = 2 },
        .{ .name = "ROL", .bits = 1, .count = -65, .expected = 0x8000000000000000 },
        .{ .name = "ROR", .bits = 0xffffffffffffffff, .count = 31, .expected = 0xffffffffffffffff },
        .{ .name = "ROL", .bits = 0x0123456789abcdef, .count = std.math.minInt(forth.Cell), .expected = 0x0123456789abcdef },
    };
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try machine.interpretLine(": LEFT ROL ; : RIGHT ROR ;");
    for (cases) |case| {
        for ([_][]const u8{ case.name, if (std.mem.eql(u8, case.name, "ROL")) "LEFT" else "RIGHT" }) |word| {
            try machine.push(@bitCast(case.bits));
            try machine.push(case.count);
            try machine.interpretLine(word);
            try support.expectStack(machine, &.{@bitCast(case.expected)});
            machine.data_depth = 0;
        }
    }
    for ([_][]const u8{ "ROL", "ROR" }) |word| {
        try std.testing.expectError(error.StackUnderflow, machine.interpretLine(word));
        try machine.push(1);
        try std.testing.expectError(error.StackUnderflow, machine.interpretLine(word));
    }
}

test "2, data and rotation calls survive image restore and append" {
    try support.skipWithout(&.{.image});
    var output = support.Output{};
    const source = try support.createMachine(&output);
    defer support.destroyMachine(source);
    try source.interpretLine("CREATE PAIR 11 22 2, : GET PAIR 2@ ; : ROTATE 1 65 ROL 1 ROR ;");
    const raw_address = source.data_here;
    try source.interpretLine("CREATE RAW-PAIR HERE DUP 2,");
    const image = try std.testing.allocator.alloc(u8, try source.encodedSize());
    defer std.testing.allocator.free(image);
    _ = try source.encodeImage(image);
    const restored = try support.createMachine(&output);
    defer support.destroyMachine(restored);
    try restored.restoreImage(image);
    try restored.interpretLine("GET ROTATE");
    try support.expectStack(restored, &.{ 11, 22, 1 });
    const target = try support.createMachine(&output);
    defer support.destroyMachine(target);
    try target.interpretLine("CREATE BEFORE 64 ALLOT");
    try target.appendImage(restored);
    try target.interpretLine("GET ROTATE");
    try support.expectStack(target, &.{ 11, 22, 1 });
    target.data_depth = 0;
    try target.interpretLine("RAW-PAIR 2@");
    try support.expectStack(target, &.{ raw_address, raw_address });
}
