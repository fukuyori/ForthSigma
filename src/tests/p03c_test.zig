const std = @import("std");
const support = @import("support.zig");
const registry = @import("../core/address_registry.zig");
const forth = @import("../forth.zig");

test "P03c heap copies and extension retain contents and return appended region" {
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try machine.interpretLine("S\" abc\" SAVE-MEM 5 EXTEND-MEM");
    const length = try machine.pop();
    const block = try machine.pop();
    const appended = try machine.pop();
    try std.testing.expectEqual(@as(forth.Cell, 8), length);
    try std.testing.expectEqual(block + 3, appended);
    try std.testing.expectEqualStrings("abc", machine.memory[@intCast(block)..][0..3]);
    try std.testing.expect(try machine.heapFree(block));
}

test "P03c buffers grow move shrink and persist with explicit owner registration" {
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try machine.interpretLine("CREATE B BUFFER% %SIZE ALLOT B INIT-BUFFER 8 B ADJUST-BUFFER 65 B CELL+ @ C!");
    const descriptor = machine.words[machine.lookup("B").?].value;
    const first = try machine.readCell(descriptor + 8);
    _ = (try machine.heapAllocate(32)).?;
    try machine.interpretLine("200 B ADJUST-BUFFER");
    const moved = try machine.readCell(descriptor + 8);
    try std.testing.expect(moved != first);
    try std.testing.expectEqual(@as(forth.Cell, 65), @as(forth.Cell, machine.memory[@intCast(moved)]));
    try machine.interpretLine("2 B ADJUST-BUFFER");
    try std.testing.expectEqual(@as(forth.Cell, 2), try machine.readCell(descriptor));
    try std.testing.expectEqual(@as(forth.Cell, 200), try machine.readCell(descriptor + 16));
    try std.testing.expectEqual(moved, try machine.readCell(descriptor + 8));
    try registry.validate(machine);
    const bytes = try std.testing.allocator.alloc(u8, machine.encodedSize());
    defer std.testing.allocator.free(bytes);
    const length = try machine.encodeImage(bytes);
    try machine.restoreImage(bytes[0..length]);
    try registry.validate(machine);
    try machine.interpretLine("B @ B CELL+ @ C@ B 2 CELLS + @");
    try support.expectStack(machine, &.{ 2, 65, 200 });
}

test "P03c failed buffer growth preserves descriptor contents ownership and input" {
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try machine.interpretLine("CREATE B 24 ALLOT B INIT-BUFFER 8 B ADJUST-BUFFER");
    const descriptor = machine.words[machine.lookup("B").?].value;
    const pointer = try machine.readCell(descriptor + 8);
    const top = machine.heapTop();
    try machine.push(-1);
    try machine.push(descriptor);
    try std.testing.expectError(error.Thrown, machine.executeBuiltin(.adjust_buffer));
    try support.expectStack(machine, &.{ -1, descriptor });
    try std.testing.expectEqual(pointer, try machine.readCell(descriptor + 8));
    try std.testing.expectEqual(@as(forth.Cell, 8), try machine.readCell(descriptor));
    try std.testing.expectEqual(@as(forth.Cell, 8), try machine.readCell(descriptor + 16));
    try std.testing.expectEqual(top, machine.heapTop());
    try registry.validate(machine);
    machine.data_depth = 0;
    const remaining: u64 = @intCast(machine.sizes.heapEnd() - machine.heapTop() - 16);
    _ = (try machine.heapAllocate(remaining)).?;
    const filled_top = machine.heapTop();
    try machine.push(2048);
    try machine.push(descriptor);
    try std.testing.expectError(error.Thrown, machine.executeBuiltin(.adjust_buffer));
    try support.expectStack(machine, &.{ 2048, descriptor });
    try std.testing.expectEqual(pointer, try machine.readCell(descriptor + 8));
    try std.testing.expectEqual(filled_top, machine.heapTop());
    try registry.validate(machine);
}

test "P03c descriptor freeing clears live owner but leaves null descriptor unchanged" {
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try machine.interpretLine("2VARIABLE V S\" abc\" SAVE-MEM V 2! V FREE-MEM-VAR V 2@ 0 7 V 2! V FREE-MEM-VAR V 2@");
    try support.expectStack(machine, &.{ 0, 0, 0, 7 });
}

test "P03c SAVE-MEM copies explicit cell types and FREE removes the copied storage" {
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try machine.interpretLine("CREATE TARGET 8 ALLOT CREATE SRC TARGET A, SRC 8 SAVE-MEM");
    try std.testing.expectEqual(@as(forth.Cell, 8), try machine.pop());
    const copied = try machine.pop();
    try std.testing.expect(registry.index(machine, .memory, copied) != null);
    try registry.validate(machine);
    try std.testing.expect(try machine.heapFree(copied));
    try std.testing.expect(registry.index(machine, .memory, copied) == null);
    try registry.validate(machine);
}

test "P03c descriptor registration capacity and invalid free fail before descriptor changes" {
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try machine.interpretLine("CREATE B 24 ALLOT 17 B ! CREATE TYPES : FILL-TYPES 2048 0 DO 0 A, LOOP ; FILL-TYPES");
    const descriptor = machine.words[machine.lookup("B").?].value;
    try machine.push(descriptor);
    try std.testing.expectError(error.MemoryExhausted, machine.executeBuiltin(.init_buffer));
    try support.expectStack(machine, &.{descriptor});
    try std.testing.expectEqual(@as(forth.Cell, 17), try machine.readCell(descriptor));
    try machine.writeCell(descriptor + 8, 123);
    try std.testing.expectError(error.Thrown, machine.executeBuiltin(.free_mem_var));
    try std.testing.expectEqual(@as(forth.Cell, 17), try machine.readCell(descriptor));
    try std.testing.expectEqual(@as(forth.Cell, 123), try machine.readCell(descriptor + 8));
}
