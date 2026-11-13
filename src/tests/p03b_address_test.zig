//! Explicit address typing and lifetime tracking; persistence is guarded until P03b/617.
const std = @import("std");
const support = @import("support.zig");
const registry = @import("../core/address_registry.zig");
const map = @import("../core/memory_map.zig");

test "P03b explicit memory and constant address registrations coexist with raw cells" {
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try machine.interpretLine("CREATE TARGET 16 ALLOT HERE TARGET , TARGET ACONSTANT AP AVARIABLE AV TARGET AV ! CREATE AA TARGET A,");
    try std.testing.expectEqual(@as(usize, 3), machine.addresses.count);
    try registry.validate(machine);
    try machine.interpretLine("AP TARGET = AV @ TARGET = AA @ TARGET =");
    try support.expectStack(machine, &.{ machine.words[machine.lookup("AA").?].data_here_before - 16, -1, -1, -1 });
}

test "P03b partial writes damage registrations and exact cell stores repair them" {
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try machine.interpretLine("CREATE TARGET 32 ALLOT AVARIABLE AV TARGET AV !");
    for ([_][]const u8{ "AV DUP C@ SWAP C!", "0 AV W!", "0 AV L!", "AV 8 ERASE", "AV 8 0 FILL" }) |source| {
        try machine.interpretLine(source);
        try std.testing.expectError(error.InvalidAddress, registry.validate(machine));
        try machine.interpretLine("TARGET AV !");
        try registry.validate(machine);
    }
    try machine.interpretLine("TARGET AV X!");
    try registry.validate(machine);
    try machine.interpretLine("TARGET 99 AV XD!");
    try registry.validate(machine);
}

test "P03b MOVE and directional CMOVEs transfer pre-copy registrations and partial cells damage" {
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try machine.interpretLine("CREATE TARGET 32 ALLOT CREATE CELLS4 TARGET A, TARGET 1+ A, 0 , 0 , CELLS4 CELLS4 8 + 16 MOVE");
    try std.testing.expectEqual(@as(usize, 3), machine.addresses.count);
    try registry.validate(machine);
    try machine.interpretLine("CELLS4 @ CELLS4 8 + @ = CELLS4 16 + @ TARGET 1+ =");
    try support.expectStack(machine, &.{ -1, -1 });
    machine.data_depth = 0;
    try machine.interpretLine("CELLS4 CELLS4 24 + 8 CMOVE CELLS4 24 + CELLS4 16 + 8 CMOVE>");
    try registry.validate(machine);
    try machine.interpretLine("CELLS4 CELLS4 8 + 1 MOVE");
    try std.testing.expectError(error.InvalidAddress, registry.validate(machine));
}

test "P03b freeing referenced heap never revives a type by reusing the same address" {
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try machine.interpretLine("16 ALLOCATE THROW CONSTANT P AVARIABLE AV P 3 + AV !");
    try registry.validate(machine);
    try machine.interpretLine("P FREE THROW 16 ALLOCATE THROW P =");
    try support.expectStack(machine, &.{-1});
    try std.testing.expectError(error.InvalidAddress, registry.validate(machine));
    machine.data_depth = 0;
    try machine.interpretLine("P AV !");
    try registry.validate(machine);
    // Typed storage inside a freed block is removed, rather than attached to its next owner.
    try machine.interpretLine("0 P !");
    try registry.registerMemory(machine, try machine.readCell(machine.words[machine.lookup("AV").?].value));
    try machine.interpretLine("P FREE THROW");
    try std.testing.expectEqual(@as(usize, 1), machine.addresses.count);
}

test "P03b FORGET and HERE rollback remove source registrations and invalidate surviving targets" {
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try machine.interpretLine("AVARIABLE AV MARKER BACK CREATE TARGET 32 ALLOT TARGET AV ! TARGET ACONSTANT AP TARGET A,");
    try registry.validate(machine);
    try machine.interpretLine("BACK");
    try std.testing.expectEqual(@as(usize, 1), machine.addresses.count);
    try std.testing.expectError(error.InvalidAddress, registry.validate(machine));
    try machine.interpretLine("0 AV ! HERE 16 ALLOT CONSTANT TOP TOP AV ! TOP ->HERE");
    try std.testing.expectError(error.InvalidAddress, registry.validate(machine));
    try machine.interpretLine("0 AV !");
    try registry.validate(machine);
}

test "P03b typed metadata cannot silently pass through the legacy image format" {
    try support.skipWithout(&.{.image});
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    const bytes = try std.testing.allocator.alloc(u8, machine.encodedSize() + 64);
    defer std.testing.allocator.free(bytes);
    _ = try machine.encodeImage(bytes);
    try machine.interpretLine("AVARIABLE AV");
    const count = machine.word_count;
    try std.testing.expectError(error.InvalidImage, machine.encodeImage(bytes));
    try std.testing.expectError(error.InvalidImage, machine.restoreImage(bytes));
    try std.testing.expectEqual(count, machine.word_count);
    try std.testing.expectError(error.InvalidImage, machine.interpretLine("SAVE ignored.sigma"));
    try std.testing.expectEqual(@as(usize, 0), output.saves);
    try machine.interpretLine("AV DUP C@ SWAP C!");
    try std.testing.expectError(error.InvalidAddress, machine.encodeImage(bytes));
}

test "P03b definitions work in compiled definers and across input lines" {
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try machine.interpretLine(": MAKE ACONSTANT ; : VAR AVARIABLE ; HERE MAKE AP VAR AV");
    try machine.interpretLine("0 ACONSTANT");
    try machine.interpretLine("ZERO-ADDRESS");
    try machine.interpretLine("ZERO-ADDRESS AV @ AP 0>=");
    try support.expectStack(machine, &.{ 0, 0, -1 });
    try registry.validate(machine);
}

test "P03b bounded metadata preflights A comma and MOVE without partial mutation" {
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    const base = machine.data_here;
    for (0..registry.capacity) |_| try machine.interpretLine("0 A,");
    const before = machine.data_here;
    try machine.push(0);
    try std.testing.expectError(error.MemoryExhausted, machine.interpretLine("A,"));
    try std.testing.expectEqual(before, machine.data_here);
    try support.expectStack(machine, &.{0});
    machine.data_depth = 0;
    try machine.interpretLine("CREATE DEST 16 ALLOT DEST 16 170 FILL");
    const dest = machine.words[machine.lookup("DEST").?].value;
    try machine.push(base);
    try machine.push(dest);
    try machine.push(8);
    try std.testing.expectError(error.MemoryExhausted, machine.interpretLine("MOVE"));
    for (machine.memory[@intCast(dest)..][0..16]) |byte| try std.testing.expectEqual(@as(u8, 170), byte);
}

test "P03b heap shrink invalidates truncated sources and targets" {
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try machine.interpretLine("64 ALLOCATE THROW CONSTANT P AVARIABLE AV P 48 + AV ! P 8 RESIZE THROW DROP");
    try std.testing.expectError(error.InvalidAddress, registry.validate(machine));
    try machine.interpretLine("P AV !");
    try registry.validate(machine);
}

test "P03b failed compilation discards new registrations and preserves surviving variables" {
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try machine.interpretLine("AVARIABLE AV : BAD [ 0 A, ]");
    try std.testing.expectError(error.UnknownWord, machine.interpretLine("UNKNOWN-P03-NAME"));
    machine.report(error.UnknownWord);
    try std.testing.expectEqual(@as(usize, 1), machine.addresses.count);
    try registry.validate(machine);
}

test "P03b copied types in unallocated storage do not attach to a later heap owner" {
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try machine.interpretLine("AVARIABLE AV AV");
    try machine.push(machine.sizes.heapBase() + map.heap_header);
    try machine.push(8);
    try machine.interpretLine("MOVE 8 ALLOCATE THROW CONSTANT P");
    try std.testing.expectError(error.InvalidAddress, registry.validate(machine));
    try machine.interpretLine("0 P !");
    try registry.validate(machine);
}
