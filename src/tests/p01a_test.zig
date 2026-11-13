//! P01a compares raw cell patterns at both signed and unsigned boundaries.
const std = @import("std");
const forth = @import("../forth.zig");
const support = @import("support.zig");
const map = @import("../core/memory_map.zig");
const Cell = map.Cell;
const Double = map.Double;
const UDouble = map.UDouble;
const low = std.math.minInt(Cell);
const high = std.math.maxInt(Cell);
const dlow = std.math.minInt(Double);
const dhigh = std.math.maxInt(Double);

fn compiled(machine: *forth.State, name: []const u8) !void {
    var source: [80]u8 = undefined;
    try machine.interpretLine(try std.fmt.bufPrint(&source, ": P01-COMPILED {s} ;", .{name}));
}

fn result(machine: *forth.State, value: Cell) !void {
    try support.expectStack(machine, &.{value});
    machine.data_depth = 0;
}

test "P01a zero tests consume a signed cell or double and return exact flags" {
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    const cases = [_]struct { name: []const u8, double: bool, flags: [5]Cell }{
        .{ .name = "0<=", .double = false, .flags = .{ -1, -1, -1, 0, 0 } },
        .{ .name = "D0<=", .double = true, .flags = .{ -1, -1, -1, 0, 0 } },
        .{ .name = "D0<>", .double = true, .flags = .{ -1, -1, 0, -1, -1 } },
        .{ .name = "D0>", .double = true, .flags = .{ 0, 0, 0, -1, -1 } },
        .{ .name = "D0>=", .double = true, .flags = .{ 0, 0, -1, -1, -1 } },
    };
    for (cases) |case| {
        try compiled(machine, case.name);
        for ([_][]const u8{ case.name, "P01-COMPILED" }) |word| {
            const values: [5]Double = if (case.double) .{ dlow, -1, 0, 1, dhigh } else .{ low, -1, 0, 1, high };
            for (values, case.flags) |value, flag| {
                if (case.double) try machine.pushDouble(value) else try machine.push(@intCast(value));
                try machine.interpretLine(word);
                try result(machine, flag);
            }
        }
    }
}

test "P01a unsigned cells compare the high bit as magnitude and preserve min max bits" {
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    const pairs = [_]struct { a: Cell, b: Cell, le: Cell, ge: Cell, min: Cell, max: Cell }{
        .{ .a = 0, .b = 0, .le = -1, .ge = -1, .min = 0, .max = 0 },
        .{ .a = 0, .b = -1, .le = -1, .ge = 0, .min = 0, .max = -1 },
        .{ .a = -1, .b = 0, .le = 0, .ge = -1, .min = 0, .max = -1 },
        .{ .a = low, .b = high, .le = 0, .ge = -1, .min = high, .max = low },
        .{ .a = high, .b = low, .le = -1, .ge = 0, .min = high, .max = low },
        .{ .a = -1, .b = -1, .le = -1, .ge = -1, .min = -1, .max = -1 },
        .{ .a = 4, .b = 3, .le = 0, .ge = -1, .min = 3, .max = 4 },
    };
    for ([_][]const u8{ "U<=", "U>=", "UMIN", "UMAX" }, 0..) |name, operation| {
        try compiled(machine, name);
        for ([_][]const u8{ name, "P01-COMPILED" }) |word| for (pairs) |pair| {
            try machine.push(pair.a);
            try machine.push(pair.b);
            try machine.interpretLine(word);
            const expected = switch (operation) {
                0 => pair.le,
                1 => pair.ge,
                2 => pair.min,
                else => pair.max,
            };
            try result(machine, expected);
        };
    }
}

test "P01a signed double comparisons preserve high-low cell order and avoid subtraction overflow" {
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    const pairs = [_]struct { a: Double, b: Double, le: Cell, ne: Cell, gt: Cell, ge: Cell }{
        .{ .a = 0, .b = 0, .le = -1, .ne = 0, .gt = 0, .ge = -1 },
        .{ .a = -1, .b = 0, .le = -1, .ne = -1, .gt = 0, .ge = 0 },
        .{ .a = dlow, .b = dhigh, .le = -1, .ne = -1, .gt = 0, .ge = 0 },
        .{ .a = dhigh, .b = dlow, .le = 0, .ne = -1, .gt = -1, .ge = -1 },
        .{ .a = 0xffffffffffffffff, .b = 0x10000000000000000, .le = -1, .ne = -1, .gt = 0, .ge = 0 },
        .{ .a = -0x10000000000000000, .b = -1, .le = -1, .ne = -1, .gt = 0, .ge = 0 },
    };
    for ([_][]const u8{ "D<=", "D<>", "D>", "D>=" }, 0..) |name, operation| {
        try compiled(machine, name);
        for ([_][]const u8{ name, "P01-COMPILED" }) |word| for (pairs) |pair| {
            try machine.pushDouble(pair.a);
            try machine.pushDouble(pair.b);
            try machine.interpretLine(word);
            const expected = switch (operation) {
                0 => pair.le,
                1 => pair.ne,
                2 => pair.gt,
                else => pair.ge,
            };
            try result(machine, expected);
        };
    }
}

test "P01a unsigned doubles order sign-bit boundaries by magnitude" {
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    const pairs = [_]struct { a: UDouble, b: UDouble, le: Cell, gt: Cell, ge: Cell }{
        .{ .a = 0, .b = 0, .le = -1, .gt = 0, .ge = -1 },
        .{ .a = 0, .b = std.math.maxInt(UDouble), .le = -1, .gt = 0, .ge = 0 },
        .{ .a = std.math.maxInt(UDouble), .b = 0, .le = 0, .gt = -1, .ge = -1 },
        .{ .a = @as(UDouble, 1) << 127, .b = dhigh, .le = 0, .gt = -1, .ge = -1 },
        .{ .a = 0xffffffffffffffff, .b = 0x10000000000000000, .le = -1, .gt = 0, .ge = 0 },
        .{ .a = std.math.maxInt(UDouble), .b = std.math.maxInt(UDouble), .le = -1, .gt = 0, .ge = -1 },
    };
    for ([_][]const u8{ "DU<=", "DU>", "DU>=" }, 0..) |name, operation| {
        try compiled(machine, name);
        for ([_][]const u8{ name, "P01-COMPILED" }) |word| for (pairs) |pair| {
            try machine.pushDouble(@bitCast(pair.a));
            try machine.pushDouble(@bitCast(pair.b));
            try machine.interpretLine(word);
            const expected = switch (operation) {
                0 => pair.le,
                1 => pair.gt,
                else => pair.ge,
            };
            try result(machine, expected);
        };
    }
}

test "all P01a words report insufficient input instead of reading past the stack" {
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    for ([_][]const u8{ "0<=", "D0<=", "D0<>", "D0>", "D0>=", "D<=", "D<>", "D>", "D>=", "DU<=", "DU>", "DU>=", "U<=", "U>=", "UMAX", "UMIN" }) |name| {
        const needed: usize = if (name[0] == 'D') (if (name[1] == '0') 2 else 4) else if (name[0] == '0') 1 else 2;
        for (0..needed) |count| {
            machine.data_depth = 0;
            for (0..count) |_| try machine.push(0);
            try std.testing.expectError(error.StackUnderflow, machine.interpretLine(name));
        }
    }
}

test "compiled P01a calls survive dictionary restore and append" {
    try support.skipWithout(&.{.image});
    var output = support.Output{};
    const source = try support.createMachine(&output);
    defer support.destroyMachine(source);
    try source.interpretLine(": P01-SAVED -1 0 U<= 0 -1 UMAX 1. 2. D<= -1. 0. DU> ;");
    const image = try std.testing.allocator.alloc(u8, try source.encodedSize());
    defer std.testing.allocator.free(image);
    _ = try source.encodeImage(image);
    const restored = try support.createMachine(&output);
    defer support.destroyMachine(restored);
    try restored.restoreImage(image);
    try restored.interpretLine("P01-SAVED");
    try support.expectStack(restored, &.{ 0, -1, -1, -1 });
    const target = try support.createMachine(&output);
    defer support.destroyMachine(target);
    try target.interpretLine(": BEFORE 7 ;");
    try target.appendImage(restored);
    try target.interpretLine("P01-SAVED BEFORE");
    try support.expectStack(target, &.{ 0, -1, -1, -1, 7 });
}
