const std = @import("std");
const support = @import("support.zig");
const registry = @import("../core/address_registry.zig");

test "P04 review APPEND capacity preflight cannot borrow a neighbouring block registration" {
    var output = support.Output{};
    const m = try support.createMachine(&output);
    defer support.destroyMachine(m);
    try m.interpretLine("CREATE SRC 0 , 0 , 0 A, 0 ,");
    const source = m.words[m.lookup("SRC").?].value;
    const first = (try m.heapAllocate(8)).?;
    const neighbour = (try m.heapAllocate(8)).?;
    try std.testing.expectEqual(first + 24, neighbour);
    try m.writeCell(neighbour, 0);
    try registry.registerMemory(m, neighbour);
    try m.interpretLine(": FILL-TYPES 2046 0 DO 0 A, LOOP ; FILL-TYPES");
    const top = m.heapTop();
    try m.push(first);
    try m.push(8);
    try m.push(source);
    try m.push(32);
    try std.testing.expectError(error.MemoryExhausted, m.executeBuiltin(.string_append_owned));
    try std.testing.expect(try m.findBlock(first) != null);
    try std.testing.expectEqual(top, m.heapTop());
    try support.expectStack(m, &.{ first, 8, source, 32 });
    try registry.validate(m);
}

test "P04 review APPEND shrink reuses capacity released by discarded registrations" {
    var output = support.Output{};
    const m = try support.createMachine(&output);
    defer support.destroyMachine(m);
    try m.interpretLine("CREATE SRC 0 A,");
    const source = m.words[m.lookup("SRC").?].value;
    const first = (try m.heapAllocate(64)).?;
    try m.writeCell(first + 48, 0);
    try registry.registerMemory(m, first + 48);
    try m.interpretLine(": FILL-TYPES 2046 0 DO 0 A, LOOP ; FILL-TYPES");
    try m.push(first);
    try m.push(8);
    try m.push(source);
    try m.push(8);
    try m.executeBuiltin(.string_append_owned);
    try support.expectStack(m, &.{ first, 16 });
    try std.testing.expectEqual(@as(usize, 2048), m.addresses.count);
    try std.testing.expect(registry.index(m, .memory, first + 48) == null);
    try std.testing.expect(registry.index(m, .memory, first + 8) != null);
    try registry.validate(m);
}

test "P04 review plus TO metadata exhaustion preserves string contents length and owner" {
    var output = support.Output{};
    const m = try support.createMachine(&output);
    defer support.destroyMachine(m);
    try m.interpretLine("S\" kept\" $VALUE TEXT CREATE SRC 0 A, : FILL-TYPES 2046 0 DO 0 A, LOOP ; FILL-TYPES");
    const id = m.lookup("TEXT").?;
    const owner = m.words[id].value;
    const pointer = try m.readCell(owner);
    const source = m.words[m.lookup("SRC").?].value;
    try m.push(source);
    try m.push(8);
    try std.testing.expectError(error.MemoryExhausted, @import("../core/string_values.zig").store(m, id, true));
    try std.testing.expectEqual(pointer, try m.readCell(owner));
    const text = try m.fetchString(owner);
    try std.testing.expectEqualStrings("kept", m.memory[@intCast(text.address)..][0..text.length]);
    try support.expectStack(m, &.{ source, 8 });
    try registry.validate(m);
}

test "P04 review capture retries exact size when geometric growth cannot fit" {
    var output = support.Output{};
    const m = try support.createMachine(&output);
    defer support.destroyMachine(m);
    _ = (try m.heapAllocate(@intCast(m.sizes.heapEnd() - m.heapTop() - 80))).?;
    const top = m.heapTop();
    const captured = try @import("../core/macro_substitute.zig").capture(m, "abc");
    try std.testing.expectEqualStrings("abc", captured.bytes(m));
    try std.testing.expectEqual(@as(usize, 3), captured.capacity);
    captured.free(m);
    try std.testing.expectEqual(top, m.heapTop());
}

test "P04 review VALUE definition snapshots source overlapping its new owner" {
    var output = support.Output{};
    const m = try support.createMachine(&output);
    defer support.destroyMachine(m);
    const source = m.data_here;
    @memcpy(m.memory[@intCast(source)..][0..12], "hello world!");
    try @import("../core/string_values.zig").define(m, "TEXT", source, 12);
    try m.interpretLine("TEXT TYPE");
    try std.testing.expectEqualStrings("hello world!", output.written());
    try registry.validate(m);
}

test "P04 review string stores reject self-owned owner cells before freeing their block" {
    var output = support.Output{};
    const m = try support.createMachine(&output);
    defer support.destroyMachine(m);
    const owner = (try m.heapAllocate(32)).?;
    try m.writeCell(owner, owner);
    const top = m.heapTop();
    try std.testing.expectError(error.Thrown, @import("../core/dynamic_strings.zig").storeString(m, 0, 0, owner));
    try std.testing.expectEqual(top, m.heapTop());
    try std.testing.expectEqual(owner, try m.readCell(owner));
    try std.testing.expect(try m.findBlock(owner) != null);
    try std.testing.expect(registry.index(m, .memory, owner) == null);
    try registry.validate(m);
}

test "P04 review self plus TO with full metadata frees its detached copy on failure" {
    var output = support.Output{};
    const m = try support.createMachine(&output);
    defer support.destroyMachine(m);
    try m.interpretLine("CREATE SRC 0 A, SRC 8 $VALUE TEXT : FILL-TYPES 2045 0 DO 0 A, LOOP ; FILL-TYPES");
    const id = m.lookup("TEXT").?;
    const owner = m.words[id].value;
    const pointer = try m.readCell(owner);
    const text = try m.fetchString(owner);
    const top = m.heapTop();
    try std.testing.expectEqual(registry.capacity, m.addresses.count);
    try m.push(text.address);
    try m.push(@intCast(text.length));
    try std.testing.expectError(error.MemoryExhausted, @import("../core/string_values.zig").store(m, id, true));
    try std.testing.expectEqual(top, m.heapTop());
    try std.testing.expectEqual(pointer, try m.readCell(owner));
    try std.testing.expectEqual(@as(usize, 8), (try m.fetchString(owner)).length);
    try std.testing.expectEqual(@as(@import("../core/memory_map.zig").Cell, 0), try m.readCell(text.address));
    try support.expectStack(m, &.{ text.address, @intCast(text.length) });
    try registry.validate(m);
}

test "P04 review APPEND can grow in place with a full registry and raw appended bytes" {
    var output = support.Output{};
    const m = try support.createMachine(&output);
    defer support.destroyMachine(m);
    try m.interpretLine("CREATE RAW 123 , : FILL-TYPES 2047 0 DO 0 A, LOOP ; FILL-TYPES");
    const source = m.words[m.lookup("RAW").?].value;
    const first = (try m.heapAllocate(8)).?;
    try m.writeCell(first, 0);
    try registry.registerMemory(m, first);
    try std.testing.expectEqual(registry.capacity, m.addresses.count);
    try m.push(first);
    try m.push(8);
    try m.push(source);
    try m.push(8);
    try m.executeBuiltin(.string_append_owned);
    try support.expectStack(m, &.{ first, 16 });
    try std.testing.expectEqual(@as(@import("../core/memory_map.zig").Cell, 123), try m.readCell(first + 8));
    try std.testing.expectEqual(registry.capacity, m.addresses.count);
    try registry.validate(m);
}
