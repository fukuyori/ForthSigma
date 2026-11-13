const std = @import("std");
const support = @import("support.zig");
const graph = @import("../core/image_graph.zig");
const registry = @import("../core/address_registry.zig");
const map = @import("../core/memory_map.zig");

test "image graph follows rooted cycles and interior references but never raw values" {
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    const a = (try machine.heapAllocate(16)).?;
    const b = (try machine.heapAllocate(24)).?;
    const orphan = (try machine.heapAllocate(8)).?;
    try machine.writeCell(a, b + 3);
    try registry.registerMemory(machine, a);
    try machine.writeCell(b, a);
    try registry.registerMemory(machine, b);
    try machine.writeCell(orphan, orphan);
    try registry.registerMemory(machine, orphan);
    registry.written(machine, orphan, 1, false); // Unreachable damaged slots are excluded too.
    try machine.interpretLine("AVARIABLE ROOT CREATE RAW 0 ,");
    const root = machine.words[machine.lookup("ROOT").?].value;
    try machine.writeCell(root, b);
    try machine.writeCell(machine.words[machine.lookup("RAW").?].value, orphan);
    var collected: graph.Graph = undefined;
    const top = machine.heapTop();
    const here = machine.data_here;
    try graph.collect(machine, &collected);
    try std.testing.expectEqual(@as(usize, 2), collected.object_count);
    try std.testing.expectEqual(@as(usize, 3), collected.record_count);
    try std.testing.expectEqual(@as(u64, @intCast(a - machine.sizes.heapBase())), collected.objects[0].payload_offset);
    try std.testing.expectEqual(@as(u64, @intCast(b - machine.sizes.heapBase())), collected.objects[1].payload_offset);
    try std.testing.expectEqual(@as(usize, 24), collected.objects[1].bytes.len);
    try std.testing.expectEqual(top, machine.heapTop());
    try std.testing.expectEqual(here, machine.data_here);
    try std.testing.expectEqual(orphan, try machine.readCell(orphan));
}

test "image graph accepts null system data and constant roots without heap allocation" {
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try machine.interpretLine("CREATE DATA 8 ALLOT DATA ACONSTANT ROOT AVARIABLE ZERO CREATE REFS DATA A, 8 A,");
    var collected: graph.Graph = undefined;
    try graph.collect(machine, &collected);
    try std.testing.expectEqual(@as(usize, 0), collected.object_count);
    try std.testing.expectEqual(@as(usize, 4), collected.record_count);
}

test "image graph rejects freed damaged and transient references without changing State" {
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try machine.interpretLine("AVARIABLE ROOT");
    const root = machine.words[machine.lookup("ROOT").?].value;
    var collected: graph.Graph = undefined;
    try machine.writeCell(root, map.tib_address);
    try std.testing.expectError(error.InvalidAddress, graph.collect(machine, &collected));
    const a = (try machine.heapAllocate(8)).?;
    try machine.writeCell(root, a);
    _ = try machine.heapFree(a);
    try std.testing.expectError(error.InvalidAddress, graph.collect(machine, &collected));
    try machine.writeCell(root, 0);
    registry.written(machine, root, 1, false);
    try std.testing.expectError(error.InvalidAddress, graph.collect(machine, &collected));
    try std.testing.expectEqual(@as(map.Cell, 0), try machine.readCell(root));
}

test "typed references into host-owned Tcl buffers fail before save releases resources" {
    if (comptime !@import("../core/defs.zig").graphics_enabled) return error.SkipZigTest;
    try support.skipWithout(&.{ .graphics, .image });
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try machine.interpretLine("AVARIABLE ROOT");
    const buffer = (try machine.heapAllocate(16)).?;
    machine.tcl.result = .{ .address = buffer, .length = 8 };
    const root = machine.words[machine.lookup("ROOT").?].value;
    try machine.writeCell(root, buffer + 1);
    var collected: graph.Graph = undefined;
    try std.testing.expectError(error.InvalidAddress, graph.collect(machine, &collected));
    try std.testing.expectError(error.InvalidAddress, machine.interpretLine("SAVE unused.sigma"));
    try std.testing.expectEqual(buffer, machine.tcl.result.address);
    try std.testing.expectEqual(@as(usize, 0), output.saves);
}
