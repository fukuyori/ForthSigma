//! Tests of the rest of gforth's words taken in #417: SUBSTITUTE and its relatives, the
//! tools for names and debugging, EMIT?, and (LOCAL). The expected results are those of
//! gforth 0.7.9, run on the same text.

const std = @import("std");
const forth = @import("../forth.zig");
const support = @import("support.zig");
const Output = support.Output;
const createMachine = support.createMachine;
const destroyMachine = support.destroyMachine;
const expectStack = support.expectStack;
const skipWithout = support.skipWithout;

/// Runs a line that leaves c-addr u on the stack, and gives the string.
fn stringResult(machine: *forth.State, line: []const u8) ![]const u8 {
    try machine.interpretLine(line);
    const length: usize = @intCast(machine.data_stack[machine.data_depth - 1]);
    const address: usize = @intCast(machine.data_stack[machine.data_depth - 2]);
    machine.data_depth -= 2;
    return machine.memory[address..][0..length];
}

test "SUBSTITUTE replaces %name%, keeps what it does not know, and tells an overflow" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    try machine.interpretLine("CREATE BUF 80 ALLOT  S\" Sunday\" S\" day\" REPLACES  S\" Jan\" S\" month\" REPLACES");
    const cases = [_]struct { []const u8, []const u8, forth.Cell }{
        .{ "Today is %day% in %month%, 100%% %x% %", "Today is Sunday in Jan, 100% %x% %", 2 },
        .{ "[%DAY%|%Day%|%day%]", "[%DAY%|%Day%|Sunday]", 1 },
        .{ "x%%y", "x%y", 0 },
        .{ "%x%day%", "%x%day%", 0 },
        .{ "%%%day%", "%Sunday", 1 },
        .{ "%day", "%day", 0 },
        .{ "%day%%day%", "SundaySunday", 2 },
        .{ "%%day%x", "%day%x", 0 },
        .{ "%", "%", 0 },
        .{ "%%%", "%%", 0 },
        .{ "%a b%", "%a b%", 0 },
        .{ "", "", 0 },
    };
    for (cases) |case| {
        var line: [200]u8 = undefined;
        const text = try std.fmt.bufPrint(&line, "S\" {s}\" BUF 80 SUBSTITUTE", .{case[0]});
        try machine.interpretLine(text);
        try std.testing.expectEqual(case[2], machine.data_stack[machine.data_depth - 1]);
        machine.data_depth -= 1;
        const length: usize = @intCast(machine.data_stack[machine.data_depth - 1]);
        const address: usize = @intCast(machine.data_stack[machine.data_depth - 2]);
        machine.data_depth -= 2;
        try std.testing.expectEqualStrings(case[1], machine.memory[address..][0..length]);
    }
    // A name given again takes its new text; the result is cut at the buffer's end.
    try machine.interpretLine("S\" Monday\" S\" day\" REPLACES");
    try std.testing.expectEqualStrings("[Monday]", try stringResult(machine, "S\" [%day%]\" BUF 80 SUBSTITUTE DROP"));
    try machine.interpretLine("S\" %day%\" BUF 5 SUBSTITUTE NIP NIP  S\" %day%\" BUF 6 SUBSTITUTE NIP NIP  S\" ab\" BUF 0 SUBSTITUTE NIP NIP");
    try expectStack(machine, &.{ -78, 1, -78 });
    machine.data_depth = 0;
    // The output over the input: the input is read from a copy (gforth gives the same).
    try machine.interpretLine("S\" Sunday\" S\" day\" REPLACES  S\" a%day%b\" BUF SWAP MOVE");
    try std.testing.expectEqualStrings("aSundayb", try stringResult(machine, "BUF 7 BUF 80 SUBSTITUTE DROP"));
    try machine.interpretLine("S\" x%y\" BUF SWAP MOVE");
    try std.testing.expectEqualStrings("x%%y", try stringResult(machine, "BUF 3 BUF UNESCAPE"));
}

test "UNESCAPE doubles %, and the $ words give strings of their own" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    try machine.interpretLine("CREATE BUF 80 ALLOT  S\" Sunday\" S\" day\" REPLACES");
    try std.testing.expectEqualStrings("ab%%c%%%%", try stringResult(machine, "S\" ab%c%%\" BUF UNESCAPE"));
    try std.testing.expectEqualStrings("x%%y", try stringResult(machine, "S\" x%y\" $UNESCAPE"));
    try std.testing.expectEqualStrings("[Sunday]", try stringResult(machine, "S\" [%day%]\" $SUBSTITUTE DROP"));
    try machine.interpretLine("S\" [%day%]\" $SUBSTITUTE NIP NIP");
    try expectStack(machine, &.{1});
    machine.data_depth = 0;
    // What UNESCAPE gives, SUBSTITUTE gives back.
    try std.testing.expectEqualStrings("100% %day%", try stringResult(machine, "S\" 100% %day%\" $UNESCAPE BUF 80 SUBSTITUTE DROP"));
}

test "typed replacement links survive public image restore" {
    try skipWithout(&.{.image});
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    try machine.interpretLine("S\" Sunday\" S\" day\" REPLACES");
    const image = try std.testing.allocator.alloc(u8, try machine.encodedSize());
    defer std.testing.allocator.free(image);
    const length = try machine.encodeImage(image);
    try machine.restoreImage(image[0..length]);
    try std.testing.expectEqualStrings("Sunday", try stringResult(machine, "S\" %day%\" PAD 80 SUBSTITUTE DROP"));
}

test "LATEST, LATESTXT, >NAME, ID., and .NAME" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    try std.testing.expectEqualStrings("W", try stringResult(machine, ": W ; LATEST NAME>STRING"));
    try machine.interpretLine(":NONAME ; DROP LATEST  :NONAME 3 ; DROP LATESTXT EXECUTE");
    try expectStack(machine, &.{ 0, 3 });
    machine.data_depth = 0;
    try std.testing.expectEqualStrings("DUP", try stringResult(machine, "' DUP >NAME NAME>STRING"));
    output.len = 0;
    try machine.interpretLine("' DUP >NAME ID. : V ; LATEST .NAME");
    try std.testing.expectEqualStrings("DUP V ", output.written());
    // An execution token without a name, and one out of range.
    try machine.interpretLine(":NONAME ; >NAME  -5 >NAME");
    try expectStack(machine, &.{ 0, 0 });
}

test "ALIAS and SYNONYM give the word's execution token to ' and NAME>INT, as gforth" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    try machine.interpretLine("' DUP ALIAS MYDUP 3 MYDUP ' MYDUP ' DUP =  : TK ['] MYDUP ; TK ' DUP =");
    try expectStack(machine, &.{ 3, 3, -1, -1 });
    machine.data_depth = 0;
    try machine.interpretLine(": X 1 ; SYNONYM Y X ' Y ' X =  S\" Y\" FIND-NAME NAME>INT ' X =  S\" Y\" FIND-NAME S\" X\" FIND-NAME =");
    try expectStack(machine, &.{ -1, -1, 0 });
    machine.data_depth = 0;
    try std.testing.expectEqualStrings("X", try stringResult(machine, "' Y >NAME NAME>STRING"));
    // An alias of an immediate word is not immediate.
    try machine.interpretLine(": IMM 7 ; IMMEDIATE  ' IMM ALIAS IMM2  : USE IMM2 ; USE");
    try expectStack(machine, &.{7});
}

test "~~ shows the place and the data stack on standard error" {
    try skipWithout(&.{.files});
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    try machine.interpretLine(": T4 1 2 3 ~~ 2DROP DROP ; T4");
    try std.testing.expectEqualStrings("\n*the terminal*:0:12:<3> #1 #2 #3 \n", output.stderr_bytes[0..output.stderr_len]);
    output.stderr_len = 0;
    try machine.interpretLine("~~");
    try std.testing.expectEqualStrings("\n*the terminal*:0:1:<0> \n", output.stderr_bytes[0..output.stderr_len]);
}

test "ASSERT( lets true through and throws -2 at false, showing where" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    try machine.interpretLine(": T1 ASSERT( 1 1 = ) 5 ; T1  ASSERT( TRUE )");
    try expectStack(machine, &.{5});
    machine.data_depth = 0;
    output.len = 0;
    try machine.interpretLine(": T3 ASSERT( 1 2 = ) ; ' T3 CATCH");
    try expectStack(machine, &.{-2});
    try std.testing.expectEqualStrings("*the terminal*:0:20: failed assertion", output.written());
}

test "EMIT? is true, and (LOCAL) declares locals as LOCALS| does" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    try machine.interpretLine("EMIT?");
    try machine.interpretLine(": T [ S\" X\" (LOCAL) S\" Y\" (LOCAL) 0 0 (LOCAL) ] X Y ; 1 2 T");
    try machine.interpretLine(": T2 [ S\" A\" (LOCAL) 0 0 (LOCAL) ] A 1+ TO A A ; 5 T2");
    // Without 0 0 the declarations work too, as in gforth.
    try machine.interpretLine(": T3 [ S\" Q\" (LOCAL) ] Q ; 5 T3");
    try expectStack(machine, &.{ -1, 2, 1, 6, 5 });
    machine.data_depth = 0;
    try std.testing.expectError(error.CompileOnly, machine.interpretLine("S\" Z\" (LOCAL)"));
}
