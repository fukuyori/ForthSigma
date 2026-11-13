//! Logical fixed-width memory is little endian and permits unaligned accesses.
const std = @import("std");
const support = @import("support.zig");
const map = @import("../core/memory_map.zig");

test "P03a unaligned widths truncate stores zero extend reads and preserve neighboring bytes" {
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    const base = machine.data_here;
    try machine.interpretLine("CREATE B 32 ALLOT B 32 170 FILL -1 B 1+ W! B 1+ W@ -1 B 5 + L! B 5 + L@ $0123456789ABCDEF B 11 + X! B 11 + X@");
    try support.expectStack(machine, &.{ 65535, 4294967295, 0x0123456789abcdef });
    try std.testing.expectEqual(@as(u8, 0xaa), machine.memory[@intCast(base)]);
    try std.testing.expectEqualSlices(u8, &.{ 0xef, 0xcd, 0xab, 0x89, 0x67, 0x45, 0x23, 0x01 }, machine.memory[@intCast(base + 11)..][0..8]);
    try std.testing.expectEqual(@as(u8, 0xaa), machine.memory[@intCast(base + 19)]);
}

test "P03a XD accesses only eight bytes and uses double stack representation" {
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try machine.interpretLine("CREATE B -1 , 77 , B XD@ 11 22 B XD! B @ B CELL+ @ -1 XD>S");
    try support.expectStack(machine, &.{ -1, 0, 11, 77, -1, -1 });
    machine.data_depth = 0;
    try machine.interpretLine("1 0 XDBE 11 22 XDLE");
    try support.expectStack(machine, &.{ 0x0100000000000000, 0, 11, 22 });
}

test "P03a complete range checks precede writes including end of logical memory" {
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    const end: map.Cell = @intCast(machine.memory.len);
    const pairs = [_]struct { store: []const u8, fetch: []const u8, width: map.Cell }{
        .{ .store = "W!", .fetch = "W@", .width = 2 }, .{ .store = "L!", .fetch = "L@", .width = 4 },
        .{ .store = "X!", .fetch = "X@", .width = 8 }, .{ .store = "XD!", .fetch = "XD@", .width = 8 },
    };
    for (pairs) |pair| {
        @memset(machine.memory[machine.memory.len - 16 ..], 0xaa);
        machine.data_depth = 0;
        try machine.push(0);
        if (std.mem.eql(u8, pair.store, "XD!")) try machine.push(0);
        try machine.push(end - pair.width + 1);
        try std.testing.expectError(error.InvalidAddress, machine.interpretLine(pair.store));
        for (machine.memory[machine.memory.len - 16 ..]) |byte| try std.testing.expectEqual(@as(u8, 0xaa), byte);
        machine.data_depth = 0;
        try machine.push(end - pair.width + 1);
        try std.testing.expectError(error.InvalidAddress, machine.interpretLine(pair.fetch));
        machine.data_depth = 0;
        try machine.push(end - pair.width);
        try machine.interpretLine(pair.fetch);
        machine.data_depth = 0;
        try machine.push(-1);
        try std.testing.expectError(error.InvalidAddress, machine.interpretLine(pair.fetch));
    }
}

test "P03a alignment validates powers and allocation failures preserve HERE" {
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try machine.interpretLine("1 ALLOT WALIGN HERE 2 MOD 1 ALLOT LALIGN HERE 4 MOD 1 ALLOT XALIGN HERE 8 MOD 3 16 *ALIGNED -1 8 *ALIGNED");
    try support.expectStack(machine, &.{ 0, 0, 0, 16, 0 });
    for ([_]map.Cell{ 0, 3, -1 }) |alignment| {
        machine.data_depth = 0;
        const before = machine.data_here;
        try machine.push(alignment);
        try std.testing.expectError(error.ResultOutOfRange, machine.interpretLine("*ALIGN"));
        try std.testing.expectEqual(before, machine.data_here);
    }
    machine.data_here = machine.sizes.dataLimit() - 1;
    const before = machine.data_here;
    // Next 16-byte boundary is beyond the last byte when the data limit is unaligned.
    // A huge valid power always exceeds this small machine's capacity.
    try machine.push(1 << 40);
    try std.testing.expectError(error.MemoryExhausted, machine.interpretLine("*ALIGN"));
    try std.testing.expectEqual(before, machine.data_here);
}

test "P03a exchange indexed access and sign extension compose in compiled definitions" {
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try machine.interpretLine("VARIABLE V 4 V ! 7 V !@ 7 V +!@ V @ CREATE B 3 CELLS ALLOT 77 B 2 TH! B 2 TH@ B 2 TH B 16 + =");
    try support.expectStack(machine, &.{ 4, 7, 14, 77, -1 });
    machine.data_depth = 0;
    try machine.interpretLine(": EXTEND C>S W>S L>S X>S ; 255 EXTEND -1 W>S $80000000 L>S -1 CELL/ -1 SFLOAT/");
    try support.expectStack(machine, &.{ -1, -1, -2147483648, -1, -1 });
    machine.data_depth = 0;
    for ([_][]const u8{ "W@", "L!", "XD@", "XD!", "!@", "+!@", "TH@", "TH!", "*ALIGNED", "XD>S" }) |word| {
        try std.testing.expectError(error.StackUnderflow, machine.interpretLine(word));
        machine.data_depth = 0;
    }
}

test "P03a width word calls survive dictionary restore and append" {
    try support.skipWithout(&.{.image});
    var output = support.Output{};
    const source = try support.createMachine(&output);
    defer support.destroyMachine(source);
    try source.interpretLine(": WIDTHS /W /L /X FLOAT ; : SIGNED $FFFF W>S ;");
    // No logical addresses are embedded in these definitions.
    const image = try std.testing.allocator.alloc(u8, source.encodedSize());
    defer std.testing.allocator.free(image);
    _ = try source.encodeImage(image);
    const restored = try support.createMachine(&output);
    defer support.destroyMachine(restored);
    try restored.restoreImage(image);
    const target = try support.createMachine(&output);
    defer support.destroyMachine(target);
    try target.interpretLine("CREATE BEFORE 64 ALLOT");
    try target.appendImage(restored);
    for ([_]*@import("../forth.zig").State{ restored, target }) |machine| {
        try machine.interpretLine("WIDTHS SIGNED");
        try support.expectStack(machine, &.{ 2, 4, 8, 8, -1 });
    }
}
