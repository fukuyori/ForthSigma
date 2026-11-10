//! Tests of the backtrace that follows an error, and of the step limit (--max-steps).

const std = @import("std");
const forth = @import("../forth.zig");
const support = @import("support.zig");
const Output = support.Output;
const createMachine = support.createMachine;
const destroyMachine = support.destroyMachine;
const expectStack = support.expectStack;
const setFakeFile = support.setFakeFile;

/// Interprets `line`, which must end in `expected`, and reports that error as the host does.
fn fail(machine: *forth.State, line: []const u8, expected: anyerror) !void {
    try std.testing.expectError(expected, machine.interpretLine(line));
    machine.report(expected);
}

test "an error in compiled code shows the words that were running and the stack" {
    try support.skipWithout(&.{.debug});
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine(": AVG / ; : REP 10 20 2SWAP AVG ; : VIA ['] REP EXECUTE ;");
    try fail(machine, "7 30 0 VIA", error.DivisionByZero);
    try std.testing.expectEqualStrings("DIVISION BY ZERO !\nBACKTRACE:\n  AVG\n  REP\n  VIA\nSTACK: <3> 7 10 20 \n", output.written());
    try expectStack(machine, &.{});

    // An error outside compiled code has no backtrace, also after one that had.
    output.len = 0;
    try fail(machine, "1 0 /", error.DivisionByZero);
    try std.testing.expectEqualStrings("DIVISION BY ZERO !\n", output.written());

    // ABORT says nothing, as before.
    output.len = 0;
    try fail(machine, ": STOP 1 ABORT ; STOP", error.Aborted);
    try std.testing.expectEqualStrings("", output.written());
}

test "the backtrace names inlined words, :NONAME definitions, and the definer of DOES> code" {
    try support.skipWithout(&.{.debug});
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try fail(machine, ": SQUARE DUP * ; : TWICE SQUARE SQUARE ; TWICE", error.StackUnderflow);
    try std.testing.expectEqualStrings("STACK UNDER FLOW !\nBACKTRACE:\n  SQUARE (INLINE)\n  TWICE\nSTACK: <0> \n", output.written());

    output.len = 0;
    try fail(machine, ":NONAME 1 0 / ; EXECUTE", error.DivisionByZero);
    try std.testing.expectEqualStrings("DIVISION BY ZERO !\nBACKTRACE:\n  :NONAME\nSTACK: <0> \n", output.written());

    output.len = 0;
    try fail(machine, ": DOER CREATE , DOES> @ 0 / ; 5 DOER FIVE : USE FIVE ; USE", error.DivisionByZero);
    try std.testing.expectEqualStrings("DIVISION BY ZERO !\nBACKTRACE:\n  DOER\n  USE\nSTACK: <0> \n", output.written());
}

test "the backtrace shows the floating-point stack when it holds something" {
    try support.skipWithoutFloat();
    try support.skipWithout(&.{.debug});
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try fail(machine, ": T 1.5E 1 0 / ; T", error.DivisionByZero);
    try std.testing.expectEqualStrings("DIVISION BY ZERO !\nBACKTRACE:\n  T\nSTACK: <0> \nFLOAT STACK: <1> 1.5000000000E0 \n", output.written());
    try std.testing.expectEqual(@as(usize, 0), machine.float_depth);
}

test "the backtrace gives the file and line of code compiled from a file" {
    try support.skipWithout(&.{ .files, .debug });
    var output = Output{};
    setFakeFile(&output, 0, ": AVERAGE ( sum n -- avg )\n  DUP DROP\n  / ;\n: REPORT\n  AVERAGE\n  . ;\n");
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try fail(machine, "INCLUDE a.txt : TYPED REPORT ; 30 0 TYPED", error.DivisionByZero);
    try std.testing.expectEqualStrings("DIVISION BY ZERO !\nBACKTRACE:\n  AVERAGE a.txt:3\n  REPORT a.txt:5\n  TYPED\nSTACK: <0> \n", output.written());
}

test "a recursion is one line of the backtrace, and the callers that do not fit are counted" {
    try support.skipWithout(&.{.debug});
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try fail(machine, ": DEEP DEEP ; DEEP", error.ReturnStackOverflow);
    try std.testing.expect(std.mem.startsWith(u8, output.written(), "RETURN STACK OVER FLOW !\nBACKTRACE:\n  DEEP *32\n  ... "));
    try std.testing.expect(std.mem.endsWith(u8, output.written(), " MORE\nSTACK: <0> \n"));
}

test "CATCH drops the backtrace of the error it catches, and show_backtrace turns it off" {
    try support.skipWithout(&.{.debug});
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine(": BAD 1 0 / ; : TRY ['] BAD CATCH ; TRY");
    try expectStack(machine, &.{-10});
    try fail(machine, "DROP DROP", error.StackUnderflow);
    try std.testing.expectEqualStrings("STACK UNDER FLOW !\n", output.written());

    // An error after a caught one shows only its own words.
    output.len = 0;
    try fail(machine, ": AFTER TRY DROP DROP ; AFTER", error.StackUnderflow);
    try std.testing.expectEqualStrings("STACK UNDER FLOW !\nBACKTRACE:\n  AFTER\nSTACK: <0> \n", output.written());

    output.len = 0;
    machine.show_backtrace = false;
    try fail(machine, "BAD", error.DivisionByZero);
    try std.testing.expectEqualStrings("DIVISION BY ZERO !\n", output.written());
}

test "the step limit ends compiled code that CATCH would keep running" {
    try support.skipWithout(&.{.debug});
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine(": SPIN BEGIN AGAIN ; : GUARD ['] SPIN CATCH ; : ADD + ;");
    machine.step_limit = 100;
    machine.resetSteps();
    try machine.interpretLine("1 2 ADD");
    try expectStack(machine, &.{3});
    try fail(machine, "GUARD", error.StepLimit);
    try std.testing.expectEqualStrings("STEP LIMIT !\nBACKTRACE:\n  SPIN\n  GUARD\nSTACK: <1> 3 \n", output.written());

    // Nothing more runs until the host lets it.
    try std.testing.expectError(error.StepLimit, machine.interpretLine("1 2 ADD"));
    machine.report(error.StepLimit);
    machine.resetSteps();
    try machine.interpretLine("1 2 ADD");
    try expectStack(machine, &.{3});

    // Without a limit the count is not kept.
    machine.step_limit = 0;
    machine.resetSteps();
    try machine.interpretLine(": MANY 1000 0 DO LOOP ; MANY");
}

test "code that LOAD adds has no lines, also where removed code had them" {
    try support.skipWithout(&.{ .files, .debug, .image });
    var output = Output{};
    setFakeFile(&output, 0, ": OLD\n\n\n  1 2 3 4 5 6 7 8 2DROP 2DROP 2DROP 2DROP ;\n");
    setFakeFile(&output, 1, ": BAD\n  1 0 / ;\n");
    const source = try createMachine(&output);
    defer destroyMachine(source);
    try source.interpretLine("INCLUDE b.txt");
    const image = try std.testing.allocator.alloc(u8, forth.State.imageCapacity(.small));
    defer std.testing.allocator.free(image);
    const length = try source.encodeImage(image);
    const loaded = try createMachine(&output);
    defer destroyMachine(loaded);
    try loaded.restoreImage(image[0..length]);

    // OLD is compiled from line 4 of a.txt and removed; BAD takes its place.
    const target = try createMachine(&output);
    defer destroyMachine(target);
    try target.interpretLine("MARKER M INCLUDE a.txt M");
    try target.appendImage(loaded);
    try fail(target, "BAD", error.DivisionByZero);
    try std.testing.expectEqualStrings("DIVISION BY ZERO !\nBACKTRACE:\n  BAD\nSTACK: <0> \n", output.written());
}
