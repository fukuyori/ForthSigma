const std = @import("std");
const support = @import("support.zig");
const map = @import("../core/memory_map.zig");

test "P04a control constants newline and ASCII uppercase execute and compile" {
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try machine.interpretLine("#BELL #BS #CR #DEL #EOF #ESC #FF #LF #TAB INVALID-CHAR : U TOUPPER ; 97 U 233 U NEWLINE DUP 1 = SWAP DROP SWAP C@");
    try support.expectStack(machine, &.{ 7, 8, 13, 127, 4, 27, 12, 10, 9, 65533, 65, 233, -1, 10 });
}

test "P04a ASCII compare prefix suffix and search preserve borrowed spans" {
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try machine.interpretLine("S\" Ab\" S\" aB\" CAPSCOMPARE S\" Abc\" S\" aB\" CAPSSTRING-PREFIX? S\" abcd\" S\" cd\" STRING-SUFFIX? S\" a\" S\" b\" STR<");
    try support.expectStack(machine, &.{ 0, -1, -1, -1 });
    machine.data_depth = 0;
    try machine.interpretLine("S\" Abc\" S\" B\" CAPSSEARCH");
    try std.testing.expectEqual(@as(map.Cell, -1), try machine.pop());
    try std.testing.expectEqual(@as(map.Cell, 2), try machine.pop());
    const address = try machine.pop();
    try std.testing.expectEqualStrings("bc", machine.memory[@intCast(address)..][0..2]);
    try machine.interpretLine("S\" Abc\" 2DUP S\" z\" CAPSSEARCH 0= >R ROT = >R = R> AND R> AND");
    try support.expectStack(machine, &.{-1});
}

test "P04a clamped slicing reverse scan and split predicate cover boundaries" {
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try machine.interpretLine("S\" abc\" -1 SAFE/STRING NIP S\" abc\" 9223372036854775807 SAFE/STRING NIP S\" abca\" 97 SCAN-BACK NIP S\" abc\" 122 SCAN-BACK NIP");
    try support.expectStack(machine, &.{ 3, 0, 4, 0 });
    machine.data_depth = 0;
    try machine.interpretLine("100 3 103 0 NOSPLIT? >R 2DROP 2DROP R> 100 3 102 0 NOSPLIT? >R 2DROP 2DROP R>");
    try support.expectStack(machine, &.{ -1, 0 });
}

test "P04a TYPEWHITE keeps tabs and emits spaces for bytes including newlines" {
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try machine.interpretLine("CREATE T 97 C, 9 C, 10 C, 195 C, 169 C, T 5 TYPEWHITE T -1 TYPEWHITE");
    try std.testing.expectEqualStrings(" \t   ", output.written());
}

test "P04a invalid ranges and output capacity preserve operands" {
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try machine.push(-1);
    try machine.push(4);
    try machine.push(0);
    try std.testing.expectError(error.InvalidAddress, machine.executeBuiltin(.safe_slash_string));
    try support.expectStack(machine, &.{ -1, 4, 0 });
    machine.data_depth = machine.data_stack.len - 1;
    try std.testing.expectError(error.StackOverflow, machine.executeBuiltin(.newline));
    try std.testing.expectEqual(machine.data_stack.len - 1, machine.data_depth);
}

test "P04a NEWLINE persists and native comparisons honor the step limit" {
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    const bytes = try std.testing.allocator.alloc(u8, try machine.encodedSize());
    defer std.testing.allocator.free(bytes);
    const length = try machine.encodeImage(bytes);
    try machine.restoreImage(bytes[0..length]);
    try machine.interpretLine("NEWLINE TYPE");
    try std.testing.expectEqualStrings("\n", output.written());
    if (comptime !@import("../core/defs.zig").debug_enabled) return;
    machine.step_limit = 1;
    machine.steps_left = 0;
    try machine.push(map.newline_address);
    try machine.push(1);
    try machine.push(map.newline_address);
    try machine.push(1);
    try std.testing.expectError(error.StepLimit, machine.executeBuiltin(.caps_compare));
    try support.expectStack(machine, &.{ map.newline_address, 1, map.newline_address, 1 });
}
