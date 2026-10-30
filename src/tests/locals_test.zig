//! Tests of local variables.

const std = @import("std");
const forth = @import("../forth.zig");
const support = @import("support.zig");
const Output = support.Output;
const createMachine = support.createMachine;
const interpretLiteralDefinition = support.interpretLiteralDefinition;
const destroyMachine = support.destroyMachine;
const expectStack = support.expectStack;
const expectFloatStack = support.expectFloatStack;

test "locals take values in stack order and can be redefined mid-definition" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine(": T { a b -- c } 10 { c } a b < IF a b + c * ELSE a b - c * THEN ; 1 2 T 2 1 T");
    try machine.interpretLine(": E { a b c } c b a ; 10 20 30 E : L 3 0 DO I { k } k k * LOOP ; L");
    try expectStack(machine, &.{ 30, 10, 30, 20, 10, 0, 1, 4 });
}

test "TO changes value-flavoured locals and | starts locals at zero" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine(": C { n -- } BEGIN n n 1- TO n n 0= UNTIL ; 3 C : U { a | b c -- } b c a TO b b 2 * TO c b c ; 21 U");
    try expectStack(machine, &.{ 3, 2, 1, 0, 0, 21, 42 });
}

test "typed locals hold cells, doubles, floats, characters, and execution tokens" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine(": AREA { F: r -- F: a } r r F* ; 3E AREA : ADD { D: n -- D: r } n 1000. D+ ; 5000. ADD");
    try machine.interpretLine(": UP { C: ch } ch 32 - ; 'a' 256 + UP : RUN { XT: x } x ; : PASS { W: xt } xt EXECUTE ; 1 2 ' + RUN 3 4 ' * PASS");
    try expectFloatStack(machine, &.{9});
    try expectStack(machine, &.{ 6000, 0, 'A', 3, 12 });
}

test "variable-flavoured locals push addresses into the locals frame" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine(": SW { W^ a W^ b } a @ 2 * b @ 2 * a ! b ! a @ b @ ; 3 7 SW : FS { F^ a F^ b } a F@ b F@ a F! b F! a F@ b F@ ; 1.5E 2.5E FS");
    try machine.interpretLine(": CH { C^ p } p 1 TYPE ; 72 CH 73 CH : G 0 { W^ s } S\" Hi\" s $! S\" !\" s $+! s $. ; G");
    try expectStack(machine, &.{ 14, 6 });
    try expectFloatStack(machine, &.{ 2.5, 1.5 });
    try std.testing.expectEqualStrings("HIHi!", output.written());
}

test "LOCALS| binds the first name to the top of the stack and {: :} is accepted" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine(": M LOCALS| n2 n1 | n1 n2 > IF n1 ELSE n2 THEN ; 3 9 M 9 3 M : S {: a b -- d :} a b - ; 10 3 S");
    try expectStack(machine, &.{ 9, 9, 7 });
}

test "each recursive call gets its own locals frame and frames are released" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    const top = machine.locals_top;

    try machine.interpretLine(": FIB { n -- r } n 2 < IF n ELSE n 1- RECURSE n 2 - RECURSE + THEN ; 20 FIB : R { a b } a >R b 2 * R> + ; 1 2 R");
    try expectStack(machine, &.{ 6765, 5 });
    try std.testing.expectEqual(top, machine.locals_top);
    machine.data_depth = 0;
    try std.testing.expectError(error.StackUnderflow, machine.interpretLine("FIB"));
    machine.report(error.StackUnderflow);
    try std.testing.expectEqual(top, machine.locals_top);
}

test "local names are scoped to their definition and rejected outside one" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine(": DUP2 { DUP } DUP DUP ; 4 DUP2 : AFTER 5 DUP ; AFTER");
    try expectStack(machine, &.{ 4, 4, 5, 5 });
    try std.testing.expectError(error.CompileOnly, machine.interpretLine("1 { X }"));
    machine.report(error.CompileOnly);
    try std.testing.expectError(error.InvalidDefinition, machine.interpretLine(": BAD { F: } ;"));
    machine.report(error.InvalidDefinition);
    try std.testing.expectError(error.InvalidDefinition, machine.interpretLine(": BAD2 { W^ v } 1 TO v ;"));
    machine.report(error.InvalidDefinition);
}

test "locals survive a full image restore" {
    var output = Output{};
    const source = try createMachine(&output);
    defer destroyMachine(source);
    try source.interpretLine(": SUB { a b } a b - ; :NONAME { F: x } x x F* ; CONSTANT SQ");
    const image = try std.testing.allocator.alloc(u8, forth.State.imageCapacity());
    defer std.testing.allocator.free(image);
    const length = try source.encodeImage(image);

    const target = try createMachine(&output);
    defer destroyMachine(target);
    try target.interpretLine(": EARLIER 1 ;");
    const loaded = try createMachine(&output);
    defer destroyMachine(loaded);
    try loaded.restoreImage(image[0..length]);
    try target.appendImage(loaded);
    try target.interpretLine("10 3 SUB");
    try expectStack(target, &.{7});
}

test "tabs separate tokens like spaces" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine(": T\t{ a b -- c }\n\t10 { c }\ta b + c * ;\t1\t2 T");
    try machine.interpretLine("S\"\tx\" TYPE\t.\"\ty\"\tCHAR\tz EMIT");
    try expectStack(machine, &.{30});
    try std.testing.expectEqualStrings("xyz", output.written());
}

test ":NONAME failures restore code, data, stack, and STATE" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    const words = machine.word_count;
    const code = machine.code_count;
    const data = machine.data_here;

    try std.testing.expectError(error.UnknownWord, machine.interpretLine(":NONAME [ 16 ALLOT ] 1 MISSING"));
    machine.report(error.UnknownWord);
    try std.testing.expectEqual(words, machine.word_count);
    try std.testing.expectEqual(code, machine.code_count);
    try std.testing.expectEqual(data, machine.data_here);
    try expectStack(machine, &.{});
    try machine.interpretLine("STATE @ :NONAME 5 ; EXECUTE");
    try expectStack(machine, &.{ 0, 5 });

    // A full data stack fails before the definition starts.
    machine.data_depth = machine.data_stack.len;
    const words_before_overflow = machine.word_count;
    try std.testing.expectError(error.StackOverflow, machine.interpretLine(":NONAME 1 ;"));
    try std.testing.expect(!machine.defining);
    try std.testing.expectEqual(words_before_overflow, machine.word_count);
    machine.report(error.StackOverflow);
}

test ":NONAME rolls back when the code area fills at ; and fails cleanly on a full dictionary" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    const words = machine.word_count;
    const code = machine.code_count;
    try std.testing.expectError(error.CodeFull, interpretLiteralDefinition(machine, ":NONAME", 8192 - @as(usize, code)));
    machine.report(error.CodeFull);
    try std.testing.expectEqual(words, machine.word_count);
    try std.testing.expectEqual(code, machine.code_count);
    try expectStack(machine, &.{});
    try machine.interpretLine("STATE @ :NONAME 5 ; EXECUTE");
    try expectStack(machine, &.{ 0, 5 });

    machine.data_depth = 0;
    var definition: [32]u8 = undefined;
    while (machine.word_count < 1024) {
        try machine.interpretLine(try std.fmt.bufPrint(&definition, ": W{d} 1 ;", .{machine.word_count}));
    }
    try std.testing.expectError(error.DictionaryFull, machine.interpretLine(":NONAME 1 ;"));
    try std.testing.expect(!machine.defining);
    machine.report(error.DictionaryFull);
    try expectStack(machine, &.{});
    try machine.interpretLine("W1023 STATE @");
    try expectStack(machine, &.{ 1, 0 });
}

test "locals are visible only where every path passes their declaration, as in gforth" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    const visible = [_][]const u8{
        ": T1 1 IF 5 { x } x THEN ; T1",
        ": T4 BEGIN 5 { x } x 1 UNTIL ; T4",
        ": T5 BEGIN 5 { x } 1 UNTIL x ; T5",
        ": T7 3 0 DO I { x } LOOP x ; T7",
        ": T8 5 { x } 1 IF x THEN x ; T8",
        ": T11 1 IF 5 { dup } THEN 3 dup ; T11",
        ": T13 10 0 DO I { x } x 5 = IF LEAVE THEN LOOP x ; T13",
        ": T14 1 BEGIN 7 { y } DUP WHILE 1- REPEAT DROP y ; T14",
    };
    for (visible) |line| try machine.interpretLine(line);
    try expectStack(machine, &.{ 5, 5, 5, 2, 5, 5, 3, 3, 5, 7 });

    const hidden = [_][]const u8{
        ": T2 0 IF 5 { x } ELSE x THEN ;",
        ": T3 1 IF 5 { x } THEN x ;",
        ": T9 3 0 ?DO I { x } LOOP x ;",
        ": T10 1 BEGIN DUP WHILE 5 { x } 1- REPEAT DROP x ;",
        ": T12 10 0 DO I 5 = IF LEAVE THEN I { x } LOOP x ;",
        ": T15 2 CASE 1 OF 5 { z } ENDOF z ENDCASE ;",
    };
    for (hidden) |line| {
        try std.testing.expectError(error.UnknownWord, machine.interpretLine(line));
        machine.report(error.UnknownWord);
    }
    try std.testing.expectEqualStrings("x ?\nx ?\nx ?\nx ?\nx ?\nz ?\n", output.written());
}
