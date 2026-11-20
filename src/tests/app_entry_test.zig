const std = @import("std");
const support = @import("support.zig");
const entry = @import("../core/app_entry.zig");
const map = @import("../core/memory_map.zig");
const encoder = @import("../core/image_encoder.zig");

test "app entry registration validation query and clear are atomic" {
    try support.skipWithout(&.{.image});
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try machine.interpretLine("APP-ENTRY@");
    try support.expectStack(machine, &.{ 0, 0 });
    machine.data_depth = 0;
    try machine.interpretLine(": ENTRY 7 ; ' ENTRY APP-ENTRY! APP-ENTRY@");
    const id = machine.lookup("ENTRY").?;
    try support.expectStack(machine, &.{ id, -1 });
    machine.data_depth = 0;
    try machine.push(machine.builtinWord(.dup));
    try std.testing.expectError(error.InvalidExecutionToken, machine.executeBuiltin(.app_entry_set));
    try std.testing.expectEqual(@as(usize, 1), machine.data_depth);
    try std.testing.expectEqual(@as(?u16, id), try entry.get(machine));
    machine.data_depth = 0;
    try machine.interpretLine(": UNFINISHED [");
    try machine.push(id);
    try std.testing.expectError(error.InvalidDefinition, machine.executeBuiltin(.app_entry_set));
    try std.testing.expectEqual(@as(usize, 1), machine.data_depth);
    try machine.interpretLine("] ;");
    machine.data_depth = 0;
    try machine.interpretLine("APP-ENTRY-OFF APP-ENTRY@");
    try support.expectStack(machine, &.{ 0, 0 });
}

test "app identity survives names and invalidates deleted words without marker snapshot" {
    try support.skipWithout(&.{.image});
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try machine.interpretLine(": ENTRY 1 ; ' ENTRY APP-ENTRY! : ENTRY 2 ;");
    const newer = machine.lookup("ENTRY").?;
    const original = (try entry.get(machine)).?;
    try std.testing.expect(original != newer);
    try machine.interpretLine("FORGET ENTRY");
    try std.testing.expectEqual(@as(?u16, original), try entry.get(machine));
    try machine.interpretLine("MARKER CUT : NEW ; ' NEW APP-ENTRY! CUT");
    try std.testing.expectEqual(@as(?u16, null), try entry.get(machine));
    try machine.interpretLine(": REUSED ;");
    try std.testing.expectEqual(@as(?u16, null), try entry.get(machine));
    try machine.interpretLine("' REUSED APP-ENTRY! COMPILE-ONLY");
    try std.testing.expectError(error.InvalidExecutionToken, entry.get(machine));
    try machine.executeBuiltin(.app_entry_off);
    try std.testing.expectEqual(@as(?u16, null), try entry.get(machine));
}

test "app root roundtrip append policy and corrupt image fail before mutation" {
    try support.skipWithout(&.{.image});
    var output = support.Output{};
    const source = try support.createMachine(&output);
    defer support.destroyMachine(source);
    const target = try support.createMachine(&output);
    defer support.destroyMachine(target);
    try source.interpretLine(": SAVED-ENTRY 42 ; ' SAVED-ENTRY APP-ENTRY!");
    try target.appendImage(source);
    try std.testing.expectEqual(@as(?u16, null), try entry.get(target));
    try target.interpretLine(": FILLER ; : OWN-ENTRY 9 ; ' OWN-ENTRY APP-ENTRY!");
    const own = try entry.get(target);
    try target.appendImage(source);
    try std.testing.expectEqual(own, try entry.get(target));
    var workspace: encoder.Workspace = undefined;
    const bytes = try std.testing.allocator.alloc(u8, try encoder.measure(source, &workspace));
    defer std.testing.allocator.free(bytes);
    _ = try encoder.encode(source, bytes, &workspace);
    try target.restoreFreshImage(bytes);
    try std.testing.expectEqual(try entry.get(source), try entry.get(target));
    const before = target.word_count;
    const format = @import("../core/image_format.zig");
    // The system payload follows words, code and names. Change root but repair CRC
    // to verify semantic validation rather than only the checksum check.
    const offset = format.header_size + std.mem.readInt(u64, bytes[48..56], .little) + std.mem.readInt(u64, bytes[56..64], .little) + std.mem.readInt(u64, bytes[64..72], .little);
    std.mem.writeInt(map.Cell, bytes[@intCast(offset + map.app_entry_address)..][0..8], -1, .little);
    try format.finish(bytes);
    try std.testing.expectError(error.InvalidImage, target.restoreFreshImage(bytes));
    try std.testing.expectEqual(before, target.word_count);
    try std.testing.expectEqual(try entry.get(source), try entry.get(target));
}

test "host entry has an empty terminal source and restores caller context" {
    try support.skipWithout(&.{.image});
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    const blk = if (@import("build_options").files) "BLK @ " else "0 ";
    try machine.interpretLine(": ENTRY SOURCE NIP >IN @ " ++ blk ++ "SOURCE-ID PARSE-NAME NIP ;");
    const previous = machine.source_kind;
    try machine.runEntry(machine.lookup("ENTRY").?);
    try support.expectStack(machine, &.{ 0, 0, 0, 0, 0 });
    try std.testing.expectEqual(previous, machine.source_kind);
}
