const std = @import("std");
const support = @import("support.zig");
const registry = @import("../core/address_registry.zig");
const map = @import("../core/memory_map.zig");

test "P04a owned concatenation and APPEND self overlap preserve bytes across movement" {
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try machine.interpretLine("S\" abcd\" S\" efgh\" S+");
    try std.testing.expectEqual(@as(map.Cell, 8), try machine.pop());
    const original = try machine.pop();
    _ = (try machine.heapAllocate(32)).?; // Force APPEND to move the first block.
    try machine.push(original);
    try machine.push(8);
    try machine.push(original + 1);
    try machine.push(7);
    try machine.executeBuiltin(.string_append_owned);
    try std.testing.expectEqual(@as(map.Cell, 15), try machine.pop());
    const moved = try machine.pop();
    try std.testing.expect(moved != original);
    try std.testing.expectEqualStrings("abcdefghbcdefgh", machine.memory[@intCast(moved)..][0..15]);
    try std.testing.expect(try machine.heapFree(moved));
}

test "P04a INSERT observes preceding shift and DELETE clamps then blanks tail" {
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try machine.interpretLine("CREATE BUF 8 ALLOT S\" abcdef\" BUF SWAP MOVE BUF 1+ 2 BUF 6 INSERT BUF 6 TYPE");
    try std.testing.expectEqualStrings("baabcd", output.written());
    output.len = 0;
    try machine.interpretLine("BUF 6 2 DELETE BUF 6 TYPE");
    try std.testing.expectEqualStrings("abcd  ", output.written());
    output.len = 0;
    try machine.interpretLine("BUF 6 -1 DELETE BUF 6 TYPE");
    try std.testing.expectEqualStrings("      ", output.written());
}

test "P04a STRING comma counts low byte and follows prefix-before-copy overlap order" {
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    const here = machine.data_here;
    @memcpy(machine.memory[@intCast(here)..][0..3], "abc");
    try machine.push(here);
    try machine.push(3);
    try machine.executeBuiltin(.string_comma);
    try std.testing.expectEqualSlices(u8, &.{ 3, 3, 'b', 'c' }, machine.memory[@intCast(here)..][0..4]);
    try machine.interpretLine("CREATE SRC 300 ALLOT SRC 300 65 FILL HERE SRC 300 STRING, DUP C@ SWAP COUNT NIP");
    try support.expectStack(machine, &.{ 44, 44 });
}

test "P04a bounded zero terminated strings reject missing terminator without consuming input" {
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try machine.interpretLine("CREATE Z 97 C, 98 C, 0 C, Z CSTRING>SSTRING TYPE");
    try std.testing.expectEqualStrings("ab", output.written());
    const last: map.Cell = @intCast(machine.memory.len - 1);
    machine.memory[@intCast(last)] = 65;
    try machine.push(last);
    try std.testing.expectError(error.InvalidAddress, machine.executeBuiltin(.cstring_to_sstring));
    try support.expectStack(machine, &.{last});
}

test "P04a compound INSERT and STRING comma preflight registration capacity before writes" {
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try machine.interpretLine("CREATE BUF 0 A, 0 , 0 , CREATE SRC 0 A, : FILL-TYPES 2046 0 DO 0 A, LOOP ; FILL-TYPES");
    const src = machine.words[machine.lookup("SRC").?].value;
    const dest = machine.words[machine.lookup("BUF").?].value;
    try machine.push(src);
    try machine.push(8);
    try machine.push(dest);
    try machine.push(24);
    try std.testing.expectError(error.MemoryExhausted, machine.executeBuiltin(.insert_bytes));
    try support.expectStack(machine, &.{ src, 8, dest, 24 });
    try std.testing.expectEqualSlices(u8, &(@as([24]u8, @splat(0))), machine.memory[@intCast(dest)..][0..24]);
    machine.data_depth = 0;
    const here = machine.data_here;
    machine.memory[@intCast(here)] = 0xa5;
    try machine.push(src);
    try machine.push(8);
    try std.testing.expectError(error.MemoryExhausted, machine.executeBuiltin(.string_comma));
    try std.testing.expectEqual(here, machine.data_here);
    try std.testing.expectEqual(@as(u8, 0xa5), machine.memory[@intCast(here)]);
    try registry.validate(machine);
}

test "P04a APPEND metadata exhaustion preserves original allocation and operands" {
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try machine.interpretLine("CREATE SRC 0 A, : FILL-TYPES 2047 0 DO 0 A, LOOP ; FILL-TYPES");
    const source = machine.words[machine.lookup("SRC").?].value;
    const first = (try machine.heapAllocate(8)).?;
    @memcpy(machine.memory[@intCast(first)..][0..8], "original");
    const top = machine.heapTop();
    try machine.push(first);
    try machine.push(8);
    try machine.push(source);
    try machine.push(8);
    try std.testing.expectError(error.MemoryExhausted, machine.executeBuiltin(.string_append_owned));
    try support.expectStack(machine, &.{ first, 8, source, 8 });
    try std.testing.expectEqual(top, machine.heapTop());
    try std.testing.expectEqualStrings("original", machine.memory[@intCast(first)..][0..8]);
    try registry.validate(machine);
}

test "P04a INSERT capacity simulation includes registrations created by its first move" {
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try machine.interpretLine("CREATE BUF 0 , 0 A, 0 , 0 , 0 , 0 , : FILL-TYPES 2046 0 DO 0 A, LOOP ; FILL-TYPES");
    const dest = machine.words[machine.lookup("BUF").?].value;
    try machine.push(dest + 24);
    try machine.push(16);
    try machine.push(dest);
    try machine.push(32);
    try std.testing.expectError(error.MemoryExhausted, machine.executeBuiltin(.insert_bytes));
    try std.testing.expectEqual(@as(usize, 2047), machine.addresses.count);
    try std.testing.expect(registry.index(machine, .memory, dest + 24) == null);
    try registry.validate(machine);
    try support.expectStack(machine, &.{ dest + 24, 16, dest, 32 });
}

test "P04a S+ frees failed destination when two copies need more metadata than available" {
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try machine.interpretLine("CREATE SRC 0 A, : FILL-TYPES 2046 0 DO 0 A, LOOP ; FILL-TYPES");
    const src = machine.words[machine.lookup("SRC").?].value;
    const top = machine.heapTop();
    try machine.push(src);
    try machine.push(8);
    try machine.push(src);
    try machine.push(8);
    try std.testing.expectError(error.MemoryExhausted, machine.executeBuiltin(.string_concat));
    try std.testing.expectEqual(top, machine.heapTop());
    try std.testing.expectEqual(@as(usize, 2047), machine.addresses.count);
    try registry.validate(machine);
    try support.expectStack(machine, &.{ src, 8, src, 8 });
}
