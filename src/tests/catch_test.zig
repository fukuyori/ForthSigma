//! Tests of CATCH and THROW.

const std = @import("std");
const forth = @import("../forth.zig");
const support = @import("support.zig");
const Output = support.Output;
const createMachine = support.createMachine;
const destroyMachine = support.destroyMachine;
const expectStack = support.expectStack;
const expectFloatStack = support.expectFloatStack;

test "CATCH returns 0 or the THROW code and restores the stack depths like gforth" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine(": T 1 2 3 5 THROW ; 9 ' T CATCH");
    try expectStack(machine, &.{ 9, 5 });
    machine.data_depth = 0;
    try machine.interpretLine(": U DROP DROP DROP DROP ; 1 2 ' U CATCH");
    try expectStack(machine, &.{ 1, 2, -4 });
    machine.data_depth = 0;
    try machine.interpretLine("1 2 ' + CATCH : V 1 0 / ; ' V CATCH ' ABORT CATCH S\" NOSUCHWORD\" ' EVALUATE CATCH NIP NIP");
    try expectStack(machine, &.{ 3, 0, -10, -1, -13 });
    machine.data_depth = 0;
    try machine.interpretLine("1E 2E : X FDROP FDROP 3 THROW ; ' X CATCH : W 1 >R 2 >R 7 THROW ; ' W CATCH : L 10 0 DO I 5 = IF 8 THROW THEN LOOP ; ' L CATCH");
    try expectStack(machine, &.{ 3, 7, 8 });
    try expectFloatStack(machine, &.{ 1, 2 });
    try std.testing.expectEqual(@as(usize, 0), machine.return_depth);
    try std.testing.expectEqual(@as(usize, 0), machine.loop_depth);
    try std.testing.expectEqualStrings("", output.written());
}

test "CATCH works with file iors, nested catches, locals, and $TMP" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    const locals_top = machine.locals_top;

    try machine.interpretLine(": OPEN S\" none.txt\" R/O OPEN-FILE THROW ; ' OPEN CATCH");
    try machine.interpretLine(": INNER 4 THROW ; : OUTER ['] INNER CATCH 10 + THROW ; ' OUTER CATCH");
    try machine.interpretLine(": LOC 5 { a } a 9 THROW ; ' LOC CATCH : NOISY .\" hidden\" 6 THROW ; : CAP ['] NOISY $TMP ; ' CAP CATCH");
    try expectStack(machine, &.{ forth.errnoIor(2), 14, 9, 6 });
    try std.testing.expectEqual(locals_top, machine.locals_top);
    try machine.interpretLine(".\" shown\"");
    try std.testing.expectEqualStrings("shown", output.written());
}

test "a THROWn interpreter code is reported like the original error" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    const lines = [_][]const u8{ ": V 1 0 / ; ' V CATCH THROW", "-1 ' THROW CATCH THROW", "-13 THROW", "S\" MISSING\" ' EVALUATE CATCH THROW" };
    const errors = [_]anyerror{ error.DivisionByZero, error.Aborted, error.Thrown, error.Thrown };
    for (lines, errors) |line, expected| {
        try std.testing.expectError(expected, machine.interpretLine(line));
        machine.report(expected);
    }
    try std.testing.expectEqualStrings("DIVISION BY ZERO !\nUNDEFINED WORD !\nUNDEFINED WORD !\n", output.written());
}

test "CATCH abandons a definition started by the caught word" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    const words = machine.word_count;
    const code = machine.code_count;

    try machine.interpretLine("S\" : HALF 1 MISSING\" ' EVALUATE CATCH NIP NIP STATE @");
    try expectStack(machine, &.{ -13, 0 });
    try std.testing.expectEqual(words, machine.word_count);
    try std.testing.expectEqual(code, machine.code_count);
    try std.testing.expect(!machine.defining);
    try machine.interpretLine(": AFTER 3 ; AFTER");
    try expectStack(machine, &.{ -13, 0, 3 });
}
