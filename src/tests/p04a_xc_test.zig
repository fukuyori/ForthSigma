const std = @import("std");
const support = @import("support.zig");
const map = @import("../core/memory_map.zig");

test "P04a XC query consumes valid and malformed UTF-8 using existing decoder rules" {
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    const Case = struct { bytes: []const u8, code: map.Cell, used: usize };
    const cases = [_]Case{
        .{ .bytes = "A", .code = 65, .used = 1 },
        .{ .bytes = "é!", .code = 233, .used = 2 },
        .{ .bytes = "日!", .code = 26085, .used = 3 },
        .{ .bytes = "😀!", .code = 128512, .used = 4 },
        .{ .bytes = "\xc2", .code = 65533, .used = 1 },
        .{ .bytes = "\xf0\x9f", .code = 65533, .used = 2 },
        .{ .bytes = "\xe6\x97A", .code = 65533, .used = 2 },
        .{ .bytes = "\x80", .code = 65533, .used = 1 },
        .{ .bytes = "\xf4\x90\x80\x80", .code = 65533, .used = 4 },
        .{ .bytes = "\xc0\x80", .code = 0, .used = 2 },
        .{ .bytes = "\xed\xa0\x80", .code = 55296, .used = 3 },
    };
    for (cases) |case| {
        const address = machine.data_here;
        @memcpy(machine.memory[@intCast(address)..][0..case.bytes.len], case.bytes);
        try machine.push(address);
        try machine.push(@intCast(case.bytes.len));
        try machine.executeBuiltin(.xc_fetch_plus_query);
        try support.expectStack(machine, &.{ address + @as(map.Cell, @intCast(case.used)), @as(map.Cell, @intCast(case.bytes.len - case.used)), case.code });
        machine.data_depth = 0;
    }
}

test "P04a XC query empty input advances without reading beyond logical memory" {
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    const end: map.Cell = @intCast(machine.memory.len);
    try machine.push(end);
    try machine.push(0);
    try machine.executeBuiltin(.xc_fetch_plus_query);
    try support.expectStack(machine, &.{ end + 1, -1, 65533 });
}

test "P04a XC query failures preserve range operands and output capacity" {
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try machine.push(-1);
    try machine.push(1);
    try std.testing.expectError(error.InvalidAddress, machine.executeBuiltin(.xc_fetch_plus_query));
    try support.expectStack(machine, &.{ -1, 1 });
    machine.data_depth = machine.data_stack.len;
    machine.data_stack[machine.data_depth - 2] = 0;
    machine.data_stack[machine.data_depth - 1] = 0;
    try std.testing.expectError(error.StackOverflow, machine.executeBuiltin(.xc_fetch_plus_query));
    try std.testing.expectEqual(machine.data_stack.len, machine.data_depth);
    try std.testing.expectEqual(@as(map.Cell, 0), machine.data_stack[machine.data_depth - 1]);
}

test "P04a XC query executes after compile save restore and append" {
    var output = support.Output{};
    const source = try support.createMachine(&output);
    defer support.destroyMachine(source);
    try source.interpretLine(": NEXTCHAR S\" 日!\" XC@+? ;");
    const bytes = try std.testing.allocator.alloc(u8, try source.encodedSize());
    defer std.testing.allocator.free(bytes);
    const length = try source.encodeImage(bytes);
    try source.restoreImage(bytes[0..length]);
    const target = try support.createMachine(&output);
    defer support.destroyMachine(target);
    try target.interpretLine(": BEFORE 99 ;");
    try target.appendImage(source);
    try target.interpretLine("NEXTCHAR NIP NIP");
    try support.expectStack(target, &.{26085});
}
