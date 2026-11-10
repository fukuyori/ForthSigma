//! Tests of the trace (--trace) and of the debugging words taken from gforth: +LTRACE,
//! -LTRACE, ONCE, ~~BT, ~~1BT, and ~~VALUE.

const std = @import("std");
const forth = @import("../forth.zig");
const support = @import("support.zig");
const Output = support.Output;
const createMachine = support.createMachine;
const destroyMachine = support.destroyMachine;
const expectStack = support.expectStack;
const setFakeFile = support.setFakeFile;

/// What was written to standard error since the last call.
fn shown(output: *Output) []const u8 {
    const text = output.stderr_bytes[0..output.stderr_len];
    output.stderr_len = 0;
    return text;
}

test "the trace shows each word with the stack as it starts and as it ends" {
    try support.skipWithout(&.{.debug});
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    // With the trace on, SQUARE is called, not copied into SUMSQ.
    machine.tracing = true;
    try machine.interpretLine(": SQUARE DUP * ; : SUMSQ SQUARE SWAP SQUARE + ; 3 4 SUMSQ");
    try expectStack(machine, &.{25});
    try std.testing.expectEqualStrings(
        \\> SUMSQ <2> 3 4
        \\  > SQUARE <2> 3 4
        \\  < SQUARE <2> 3 16
        \\  > SQUARE <2> 16 3
        \\  < SQUARE <2> 16 9
        \\< SUMSQ <1> 25
        \\
    , shown(&output));

    // A word that an error ends has no line for its end, and CATCH keeps the nesting.
    try machine.interpretLine("DROP : BAD 1 0 / ; : TRY ['] BAD CATCH DROP 5 SQUARE DROP ; TRY");
    try std.testing.expectEqualStrings(
        \\> TRY <0>
        \\  > BAD <0>
        \\  > SQUARE <1> 5
        \\  < SQUARE <1> 25
        \\< TRY <0>
        \\
    , shown(&output));
    try std.testing.expectEqualStrings("", output.written());
}

test "the trace ends after the lines of its limit, and the program goes on" {
    try support.skipWithout(&.{.debug});
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    machine.tracing = true;
    machine.trace_limit = 3;
    try machine.interpretLine(": SQUARE DUP * ; : SUMSQ SQUARE SWAP SQUARE + ; 3 4 SUMSQ");
    try expectStack(machine, &.{25});
    try std.testing.expectEqualStrings(
        \\> SUMSQ <2> 3 4
        \\  > SQUARE <2> 3 4
        \\  < SQUARE <2> 3 16
        \\TRACE LIMIT
        \\
    , shown(&output));
    try std.testing.expect(!machine.tracing);
    try machine.interpretLine("DROP 3 4 SUMSQ");
    try expectStack(machine, &.{25});
    try std.testing.expectEqualStrings("", shown(&output));
}

test "the trace works together with the step limit" {
    try support.skipWithout(&.{.debug});
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    machine.tracing = true;
    machine.trace_limit = 2;
    machine.step_limit = 50;
    machine.resetSteps();
    try std.testing.expectError(error.StepLimit, machine.interpretLine(": SPIN BEGIN AGAIN ; SPIN"));
    machine.report(error.StepLimit);
    try std.testing.expectEqualStrings("> SPIN <0>\n", shown(&output));
    try std.testing.expectEqualStrings("STEP LIMIT !\nBACKTRACE:\n  SPIN\nSTACK: <0> \n", output.written());
}

test "ONCE runs what follows, up to THEN, only the first time" {
    try support.skipWithout(&.{.debug});
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine(": T 3 0 DO ONCE 7 THEN LOOP ; T");
    try expectStack(machine, &.{7});
    try machine.interpretLine("T : U ONCE 8 THEN ONCE 9 THEN ; U U");
    try expectStack(machine, &.{ 7, 8, 9 });
    try std.testing.expectError(error.CompileOnly, machine.interpretLine("ONCE"));
}

test "~~BT shows the place, the stack, and the callers; ~~1BT only the first time" {
    try support.skipWithout(&.{.debug});
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine(": INNER ~~BT ; : OUTER INNER ; : VIA ['] OUTER EXECUTE ; 5 VIA");
    try std.testing.expectEqualStrings("\n*the terminal*:0:9:<1> #5 \nBACKTRACE:\n  OUTER\n  VIA\n", shown(&output));

    // Outside a definition there are no callers, and CATCH is passed like EXECUTE.
    try machine.interpretLine("DROP ~~BT : GUARD ['] INNER CATCH DROP ; GUARD");
    try std.testing.expectEqualStrings("\n*the terminal*:0:6:<0> \nBACKTRACE:\n\n*the terminal*:0:9:<0> \nBACKTRACE:\n  GUARD\n", shown(&output));

    try machine.interpretLine(": THRICE 3 0 DO I ~~1BT DROP LOOP ; : CALLER THRICE ; CALLER CALLER");
    try std.testing.expectEqualStrings("\n*the terminal*:0:19:<1> #0 \nBACKTRACE:\n  CALLER\n", shown(&output));
    try std.testing.expectEqualStrings("", output.written());
}

test "~~BT gives the file and line of its callers" {
    try support.skipWithout(&.{ .debug, .files });
    var output = Output{};
    setFakeFile(&output, 0, ": INNER ~~BT ;\n: OUTER\n  INNER ;\n");
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("INCLUDE a.txt OUTER");
    try std.testing.expectEqualStrings("\na.txt:1:9:<0> \nBACKTRACE:\n  OUTER a.txt:3\n", shown(&output));
}

test "~~VALUE shows every TO of its value" {
    try support.skipWithout(&.{.debug});
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("7 ~~VALUE VV : BUMP VV 1+ TO VV ; BUMP VV");
    try expectStack(machine, &.{8});
    try std.testing.expectEqualStrings("\n*the terminal*:0:30:<1> #8 `VV \n", shown(&output));
    try machine.interpretLine("DROP 9 TO VV VV");
    try expectStack(machine, &.{9});
    try std.testing.expectEqualStrings("\n*the terminal*:0:11:<1> #9 `VV \n", shown(&output));

    // An ordinary VALUE says nothing, also one that takes the place of a removed ~~VALUE.
    try machine.interpretLine("DROP MARKER M 1 ~~VALUE W M 2 VALUE W 3 TO W W");
    try expectStack(machine, &.{3});
    try std.testing.expectEqualStrings("", shown(&output));
}

test "+LTRACE shows the lines of an included file before they are interpreted" {
    try support.skipWithout(&.{ .debug, .files });
    var output = Output{};
    setFakeFile(&output, 0, "1\n+LTRACE\n2\n-LTRACE\n3\n");
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("INCLUDE a.txt");
    try expectStack(machine, &.{ 1, 2, 3 });
    try std.testing.expectEqualStrings("\na.txt:3:1:<1> #1 \n\na.txt:4:1:<2> #1 #2 \n", shown(&output));
}
