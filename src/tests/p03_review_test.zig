const std = @import("std");
const support = @import("support.zig");
const registry = @import("../core/address_registry.zig");
const strings = @import("../core/dynamic_strings.zig");

test "P03 review RESIZE transfers more than half a registry without doubling entries" {
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try machine.interpretLine("AVARIABLE OWNER");
    const owner = machine.words[machine.lookup("OWNER").?].value;
    const block = (try machine.heapAllocate(1300 * 8)).?;
    for (0..1300) |i| {
        const slot = block + @as(i64, @intCast(i * 8));
        try machine.writeCell(slot, 0);
        try registry.registerMemory(machine, slot);
    }
    try machine.writeCell(owner, block);
    _ = (try machine.heapAllocate(32)).?;
    const moved = switch (try machine.heapResize(block, 1301 * 8)) {
        .address => |address| address,
        else => return error.TestUnexpectedResult,
    };
    try std.testing.expect(moved != block);
    try machine.writeCell(owner, moved);
    try std.testing.expectEqual(@as(usize, 1301), machine.addresses.count);
    try std.testing.expect(registry.index(machine, .memory, block) == null);
    try std.testing.expect(registry.index(machine, .memory, moved + 1299 * 8) != null);
    try registry.validate(machine);
}

test "P03 review identical SUBSTITUTE and UNESCAPE writes damage explicit cells" {
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try machine.interpretLine("CREATE SRC 8 ALLOT CREATE DEST 0 A, SRC 8 DEST UNESCAPE 2DROP");
    try std.testing.expectError(error.InvalidAddress, registry.validate(machine));
    try machine.interpretLine("0 DEST ! SRC 8 DEST 8 SUBSTITUTE DROP 2DROP");
    try std.testing.expectError(error.InvalidAddress, registry.validate(machine));
}

test "P03 review automatic owners reject HERE before allocating and zero blocks persist" {
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    const top = machine.heapTop();
    try std.testing.expectError(error.InvalidAddress, strings.preparePointer(machine, machine.data_here));
    try std.testing.expectEqual(top, machine.heapTop());
    try machine.interpretLine("0 ALLOCATE THROW ACONSTANT EMPTY");
    try registry.validate(machine);
    const bytes = try std.testing.allocator.alloc(u8, try machine.encodedSize());
    defer std.testing.allocator.free(bytes);
    const length = try machine.encodeImage(bytes);
    machine.last_created_word = machine.lookup("EMPTY").?;
    try machine.restoreImage(bytes[0..length]);
    try std.testing.expect(machine.last_created_word == null);
    try registry.validate(machine);
    try machine.interpretLine("EMPTY FREE THROW");
}

test "P03 review failed string copy frees new allocation and preserves previous owner" {
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try machine.interpretLine("VARIABLE TEXT S\" kept\" TEXT $! CREATE SRC 0 A, : FILL-TYPES 2046 0 DO 0 A, LOOP ; FILL-TYPES");
    const owner = machine.words[machine.lookup("TEXT").?].value;
    const before = try machine.readCell(owner);
    const top = machine.heapTop();
    try machine.push(machine.words[machine.lookup("SRC").?].value);
    try machine.push(8);
    try machine.push(owner);
    try std.testing.expectError(error.MemoryExhausted, machine.executeBuiltin(.string_store));
    try std.testing.expectEqual(before, try machine.readCell(owner));
    try std.testing.expectEqual(top, machine.heapTop());
    try registry.validate(machine);
}

test "P03 review sizing propagates invalid references without maximum-size fallback" {
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try machine.interpretLine("AVARIABLE A A DUP C@ SWAP C!");
    try std.testing.expectError(error.InvalidAddress, machine.encodedSize());
}

test "P03 review line read registry failure retains previous string and file position" {
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try machine.interpretLine("VARIABLE TEXT CREATE TYPES : FILL-TYPES 2048 0 DO 0 A, LOOP ; FILL-TYPES");
    const owner = machine.words[machine.lookup("TEXT").?].value;
    const buffer = (try machine.heapAllocate(16)).?;
    try machine.writeCell(buffer, 4);
    @memcpy(machine.memory[@intCast(buffer + 8)..][0..4], "kept");
    try machine.writeCell(owner, buffer); // Deliberately unregistered legacy owner.
    try std.testing.expectError(error.MemoryExhausted, strings.slurpLine(machine, 123, owner));
    try std.testing.expectEqual(buffer, try machine.readCell(owner));
    try std.testing.expectEqualStrings("kept", machine.memory[@intCast(buffer + 8)..][0..4]);
}

test "P03 review reserves an untyped owner before typed copies can fill registry" {
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try machine.interpretLine("VARIABLE TEXT CREATE SRC 0 A, : FILL-TYPES 2046 0 DO 0 A, LOOP ; FILL-TYPES");
    const owner = machine.words[machine.lookup("TEXT").?].value;
    const previous = (try machine.heapAllocate(16)).?;
    try machine.writeCell(previous, 4);
    @memcpy(machine.memory[@intCast(previous + 8)..][0..4], "kept");
    try machine.writeCell(owner, previous);
    const top = machine.heapTop();
    try machine.push(machine.words[machine.lookup("SRC").?].value);
    try machine.push(8);
    try machine.push(owner);
    try std.testing.expectError(error.MemoryExhausted, machine.executeBuiltin(.string_store));
    try std.testing.expectEqual(previous, try machine.readCell(owner));
    try std.testing.expectEqual(top, machine.heapTop());
    try std.testing.expectEqual(@as(usize, 2047), machine.addresses.count);
    try std.testing.expect(registry.index(machine, .memory, owner) == null);
}

test "P03 review TMP preflight preserves prior unregistered slot at registry limit" {
    const map = @import("../core/memory_map.zig");
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try machine.interpretLine(": SAY ; CREATE TYPES : FILL-TYPES 2048 0 DO 0 A, LOOP ; FILL-TYPES");
    const previous = (try machine.heapAllocate(16)).?;
    try machine.writeCell(previous, 4);
    @memcpy(machine.memory[@intCast(previous + 8)..][0..4], "kept");
    try machine.writeCell(map.tmp_string_base, previous);
    try machine.push(machine.lookup("SAY").?);
    try std.testing.expectError(error.MemoryExhausted, machine.executeBuiltin(.string_tmp));
    try std.testing.expectEqual(previous, try machine.readCell(map.tmp_string_base));
    try std.testing.expectEqual(@as(usize, 0), machine.tmp_string_index);
}

test "P03 review identical gamepad output damages registered destination" {
    if (comptime !@import("../core/defs.zig").graphics_enabled) return error.SkipZigTest;
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try machine.interpretLine("CREATE DEST 0 A,");
    const destination = machine.words[machine.lookup("DEST").?].value;
    machine.gamepads.count = 1;
    machine.gamepads.pads[0].name_len = 8;
    @memset(machine.gamepads.pads[0].name[0..8], 0);
    try machine.push(destination);
    try machine.push(8);
    try machine.push(0);
    try @import("../core/gamepad.zig").execute(machine, .gfx_gamepad_name);
    try std.testing.expectError(error.InvalidAddress, registry.validate(machine));
}

test "P03 review write notifications remain correct after warmup and registration removal" {
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try machine.interpretLine("VARIABLE X AVARIABLE A");
    const x = machine.words[machine.lookup("X").?].value;
    for (0..100) |i| try machine.writeCell(x, @intCast(i));
    try machine.interpretLine("A DUP C@ SWAP C!");
    try std.testing.expectError(error.InvalidAddress, registry.validate(machine));
    try machine.interpretLine("0 A !");
    const block = (try machine.heapAllocate(8)).?;
    try machine.writeCell(block, 0);
    try registry.registerMemory(machine, block);
    for (0..100) |i| try machine.writeCell(x, @intCast(i));
    try std.testing.expect(try machine.heapFree(block));
    for (0..100) |i| try machine.writeCell(x, @intCast(i));
    try machine.interpretLine("A DUP C@ SWAP C!");
    try std.testing.expectError(error.InvalidAddress, registry.validate(machine));
}
