//! Integer division, powers, multiplexing, and double rotations at cell boundaries.
const std = @import("std");
const support = @import("support.zig");
const map = @import("../core/memory_map.zig");

test "P02a divisions distinguish floor and truncation and preserve full unsigned magnitudes" {
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try machine.interpretLine("-7 3 /MODF -7 3 /MODS -7 2 3 */MODF -7 2 3 */MODS");
    try support.expectStack(machine, &.{ 2, -3, -1, -2, 1, -5, -2, -4 });
    machine.data_depth = 0;
    try machine.interpretLine("-1 2 U/MOD -10. 3 DU/MOD -1. -1 UD/MOD");
    try support.expectStack(machine, &.{ 1, std.math.maxInt(map.Cell), 2, -4, 0, 1, 1 });
    machine.data_depth = 0;
    // The unsigned remainder can have its sign bit set even for a signed dividend.
    try machine.interpretLine("-1. -1 DU/MOD");
    try support.expectStack(machine, &.{ -2, -1 });
}

test "P02a zero divisors and oversized cell quotients throw without host traps" {
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    const cases = [_]struct { source: []const u8, expected: anyerror }{
        .{ .source = "1 0 /F", .expected = error.DivisionByZero },
        .{ .source = "1 0 /S", .expected = error.DivisionByZero },
        .{ .source = "1 0 MODF", .expected = error.DivisionByZero },
        .{ .source = "1 0 MODS", .expected = error.DivisionByZero },
        .{ .source = "1 0 /MODF", .expected = error.DivisionByZero },
        .{ .source = "1 0 /MODS", .expected = error.DivisionByZero },
        .{ .source = "1 2 0 */F", .expected = error.DivisionByZero },
        .{ .source = "1 2 0 */S", .expected = error.DivisionByZero },
        .{ .source = "1 2 0 */MODF", .expected = error.DivisionByZero },
        .{ .source = "1 2 0 */MODS", .expected = error.DivisionByZero },
        .{ .source = "1 0 U/", .expected = error.DivisionByZero },
        .{ .source = "1 0 UMOD", .expected = error.DivisionByZero },
        .{ .source = "1 0 U/MOD", .expected = error.DivisionByZero },
        .{ .source = "1 2 0 U*/", .expected = error.DivisionByZero },
        .{ .source = "1 2 0 U*/MOD", .expected = error.DivisionByZero },
        .{ .source = "1. 0 DU/MOD", .expected = error.DivisionByZero },
        .{ .source = "1. 0 UD/MOD", .expected = error.DivisionByZero },
        .{ .source = "$8000000000000000 -1 /S", .expected = error.ResultOutOfRange },
        .{ .source = "$8000000000000000 -1 MODF", .expected = error.ResultOutOfRange },
        .{ .source = "-1 -1 1 U*/", .expected = error.ResultOutOfRange },
        .{ .source = "-1 -1 1 U*/MOD", .expected = error.ResultOutOfRange },
        .{ .source = "0 1 1 DU/MOD", .expected = error.ResultOutOfRange },
    };
    for (cases) |case| {
        machine.data_depth = 0;
        try std.testing.expectError(case.expected, machine.interpretLine(case.source));
    }
    // UD/MOD returns a double quotient, so it can represent the whole unsigned range.
    machine.data_depth = 0;
    try machine.interpretLine("-1 -1 1 UD/MOD");
    try support.expectStack(machine, &.{ 0, -1, -1 });
}

test "P02a powers and double rotations cover zero and unsigned high bits" {
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try machine.interpretLine("0 CTZ 0 LOG2 0 >POW2 1 >POW2 $8000000000000001 >POW2 $8000000000000000 POW2?");
    try support.expectStack(machine, &.{ 64, -1, 0, 1, 0, -1 });
    machine.data_depth = 0;
    try machine.interpretLine(": P02A-ROT DROL ; 1 0 64 P02A-ROT 1 0 127 DROR 3 12 10 MUX");
    try support.expectStack(machine, &.{ 0, 1, 2, 0, 6 });
}

test "P02a words reject incomplete inputs" {
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    for ([_][]const u8{ "/F", "*/MODS", "U*/", "UD/MOD", "DU/MOD", "DROL", "DROR", "CTZ", "MUX", "WROL", "LROR" }) |word| {
        machine.data_depth = 0;
        try std.testing.expectError(error.StackUnderflow, machine.interpretLine(word));
    }
}

test "P02a agreed shifts saturate and narrow rotations mask both input and count" {
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    for ([_]map.Cell{ 64, 65, 128, -1 }) |count| {
        try machine.push(-8);
        try machine.push(count);
        try machine.interpretLine("ARSHIFT");
        try support.expectStack(machine, &.{-1});
        machine.data_depth = 0;
    }
    for ([_]map.Cell{ 128, 129, -1 }) |count| {
        for ([_][]const u8{ "DARSHIFT", "DLSHIFT", "DRSHIFT" }) |name| {
            try machine.pushDouble(-8);
            try machine.push(count);
            try machine.interpretLine(name);
            const expected: map.Double = if (std.mem.eql(u8, name, "DARSHIFT")) -1 else 0;
            try std.testing.expectEqual(expected, try machine.popDouble());
        }
    }
    try machine.interpretLine("-1 16 WROL -1 32 WROR -1 32 LROL -1 64 LROR 1 -1 WROL 1 -1 LROR");
    try support.expectStack(machine, &.{ 65535, 65535, 4294967295, 4294967295, 32768, 2 });
}
