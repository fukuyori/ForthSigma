const std = @import("std");
const support = @import("support.zig");
const registry = @import("../core/address_registry.zig");
const graph = @import("../core/image_graph.zig");
const strings = @import("../core/dynamic_strings.zig");
const map = @import("../core/memory_map.zig");

test "internal string owners register on store resize replacement and free" {
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try machine.interpretLine("VARIABLE TEXT S\" abc\" TEXT $!");
    const owner = machine.words[machine.lookup("TEXT").?].value;
    try std.testing.expect(registry.index(machine, .memory, owner) != null);
    _ = (try machine.heapAllocate(24)).?; // Force a later growth to move the buffer.
    const before = try machine.readCell(owner);
    _ = try machine.setStringLength(owner, 200);
    try std.testing.expect(before != try machine.readCell(owner));
    try registry.validate(machine);
    try machine.interpretLine("S\" replaced\" TEXT $!");
    try registry.validate(machine);
    var collected: graph.Graph = undefined;
    try graph.collect(machine, &collected);
    try std.testing.expectEqual(@as(usize, 1), collected.object_count);
    try machine.freeString(owner);
    try registry.validate(machine);
    try graph.collect(machine, &collected);
    try std.testing.expectEqual(@as(usize, 0), collected.object_count);
}

test "string array owners survive heap moves and shrink removes element slots" {
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try machine.interpretLine("VARIABLE ARRAY S\" one\" 0 ARRAY $[]! S\" two\" 1 ARRAY $[]!");
    const owner = machine.words[machine.lookup("ARRAY").?].value;
    const before = try machine.readCell(owner);
    _ = (try machine.heapAllocate(24)).?;
    _ = try machine.stringArrayElement(owner, 40);
    try std.testing.expect(before != try machine.readCell(owner));
    try registry.validate(machine);
    var collected: graph.Graph = undefined;
    try graph.collect(machine, &collected);
    try std.testing.expectEqual(@as(usize, 3), collected.object_count);
    try machine.freeString(try machine.stringArrayElement(owner, 1));
    _ = try machine.setStringLength(owner, 8);
    try registry.validate(machine);
    try graph.collect(machine, &collected);
    try std.testing.expectEqual(@as(usize, 2), collected.object_count);
    try machine.interpretLine("ARRAY $[]FREE");
    try registry.validate(machine);
    try graph.collect(machine, &collected);
    try std.testing.expectEqual(@as(usize, 0), collected.object_count);
}

test "transient input owners do not register image roots and full registry fails before allocation" {
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try std.testing.expectEqual(registry.Region.invalid, registry.classify(machine, machine.sizes.localsBase()));
    try std.testing.expectEqual(registry.Region.invalid, registry.classify(machine, std.math.maxInt(map.Cell)));
    try machine.writeCell(map.tib_address, 0);
    _ = try machine.setStringLength(map.tib_address, 16);
    try std.testing.expectEqual(@as(usize, 0), machine.addresses.count);
    try machine.freeString(map.tib_address);
    try machine.interpretLine("VARIABLE TEXT CREATE TYPES : FILL-TYPES 2048 0 DO 0 A, LOOP ; FILL-TYPES");
    const owner = machine.words[machine.lookup("TEXT").?].value;
    const top = machine.heapTop();
    try std.testing.expectError(error.MemoryExhausted, strings.preparePointer(machine, owner));
    try std.testing.expectError(error.MemoryExhausted, machine.setStringLength(owner, 16));
    try std.testing.expectEqual(top, machine.heapTop());
    try std.testing.expectEqual(@as(map.Cell, 0), try machine.readCell(owner));
}

test "macro string values and temporary string owners are explicit graph roots" {
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try machine.interpretLine("S\" first\" S\" name\" REPLACES S\" second\" S\" other\" REPLACES S\" new\" S\" name\" REPLACES");
    try registry.validate(machine);
    var collected: graph.Graph = undefined;
    try graph.collect(machine, &collected);
    try std.testing.expectEqual(@as(usize, 2), collected.object_count);
    try machine.interpretLine("S\" a%b\" $UNESCAPE 2DROP");
    try registry.validate(machine);
    try graph.collect(machine, &collected);
    try std.testing.expectEqual(@as(usize, 3), collected.object_count);
    try std.testing.expect(registry.index(machine, .memory, map.tmp_string_base) != null);
}
