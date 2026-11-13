//! P03b raw data placement. Typed address relocation is a separate unfinished stage.
const std = @import("std");
const support = @import("support.zig");
const map = @import("../core/memory_map.zig");

test "P03b fixed-width comma words reserve exact bytes without alignment" {
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try machine.interpretLine("1 ALLOT HERE -1 W, $12345678 L, $0123456789ABCDEF X, 11 22 XD, HERE");
    const end = try machine.pop();
    const start = try machine.pop();
    try std.testing.expectEqual(@as(map.Cell, 22), end - start);
    try std.testing.expectEqualSlices(u8, &.{ 0xff, 0xff, 0x78, 0x56, 0x34, 0x12, 0xef, 0xcd, 0xab, 0x89, 0x67, 0x45, 0x23, 0x01, 11, 0, 0, 0, 0, 0, 0, 0 }, machine.memory[@intCast(start)..][0..22]);
}

test "P03b allocation and input failure leave HERE inputs and bytes intact" {
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    const near = machine.sizes.dataLimit() - 1;
    machine.data_here = near;
    machine.memory[@intCast(near)] = 0xaa;
    for ([_][]const u8{ "W,", "L,", "X,", "XD," }) |word| {
        machine.data_depth = 0;
        try machine.push(11);
        const double = std.mem.eql(u8, word, "XD,");
        if (double) try machine.push(22);
        try std.testing.expectError(error.MemoryExhausted, machine.interpretLine(word));
        try std.testing.expectEqual(near, machine.data_here);
        try support.expectStack(machine, if (double) &.{ 11, 22 } else &.{11});
        try std.testing.expectEqual(@as(u8, 0xaa), machine.memory[@intCast(near)]);
    }
    machine.data_depth = 0;
    try std.testing.expectError(error.StackUnderflow, machine.interpretLine("XD,"));
    try std.testing.expectEqual(near, machine.data_here);
}

test "P03b MEM comma and SAVE MEM DICT copy overlapping ranges and preserve failure state" {
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try machine.interpretLine("CREATE B 32 ALLOT B 32 170 FILL B 65 SWAP C! B 1+ 66 SWAP C! B 2 + 67 SWAP C! B 3 + 68 SWAP C!");
    try machine.interpretLine("B 1+ ->HERE B 4 MEM, B 5 S\" AABCD\" COMPARE");
    try support.expectStack(machine, &.{0});
    machine.data_depth = 0;
    try machine.interpretLine("S\" xyz\" SAVE-MEM-DICT S\" xyz\" COMPARE");
    try support.expectStack(machine, &.{0});
    machine.data_depth = 0;
    const before = machine.data_here;
    try machine.push(-1);
    try machine.push(1);
    try std.testing.expectError(error.InvalidAddress, machine.interpretLine("MEM,"));
    try std.testing.expectEqual(before, machine.data_here);
    try support.expectStack(machine, &.{ -1, 1 });
    machine.data_depth = 0;
    try machine.push(-1);
    try std.testing.expectError(error.MemoryExhausted, machine.interpretLine("->HERE"));
    try std.testing.expectEqual(before, machine.data_here);
}

test "P03b field offsets align naturally and field definitions survive images" {
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try machine.interpretLine("3 WFIELD: FW 3 LFIELD: FL 3 XFIELD: FX 3 2FIELD: FD 100 FW 100 FL 100 FX 100 FD");
    try support.expectStack(machine, &.{ 6, 8, 16, 24, 104, 104, 108, 108 });
    machine.data_depth = 0;
    try machine.interpretLine("CREATE RAW HERE X, : GETFIELD 100 FD ;");
    const original = machine.words[machine.lookup("RAW").?].value;
    if (!@import("build_options").image) return;
    const bytes = try std.testing.allocator.alloc(u8, try machine.encodedSize());
    defer std.testing.allocator.free(bytes);
    _ = try machine.encodeImage(bytes);
    const restored = try support.createMachine(&output);
    defer support.destroyMachine(restored);
    try restored.restoreImage(bytes);
    const target = try support.createMachine(&output);
    defer support.destroyMachine(target);
    try target.interpretLine("CREATE BEFORE 64 ALLOT");
    try target.appendImage(restored);
    try target.interpretLine("GETFIELD RAW X@");
    try support.expectStack(target, &.{ 108, original });
}
