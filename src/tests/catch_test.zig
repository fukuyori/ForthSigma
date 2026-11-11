//! Tests of CATCH and THROW.

const std = @import("std");
const forth = @import("../forth.zig");
const support = @import("support.zig");
const Output = support.Output;
const createMachine = support.createMachine;
const destroyMachine = support.destroyMachine;
const expectStack = support.expectStack;
const expectFloatStack = support.expectFloatStack;

test "dynamic recursion reaches the call limit and recovers through CATCH" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    const locals_top = machine.locals_top;
    const cases = .{
        .{ "VARIABLE XT : X DUP IF 1- XT @ EXECUTE THEN ; ' X XT !", "X", @as(usize, 1023) },
        .{ "DEFER D : Y DUP IF 1- D THEN ; ' Y IS D", "Y", @as(usize, 1023) },
        .{ "VARIABLE ZXT : Z DUP IF 1- ZXT @ CATCH THROW THEN ; ' Z ZXT !", "Z", @as(usize, 1023) },
    };
    inline for (cases) |case| {
        try machine.interpretLine(case[0]);
        for ([_]usize{ case[2], case[2] + 1 }) |depth| {
            machine.data_depth = 0;
            var buffer: [80]u8 = undefined;
            try machine.interpretLine(try std.fmt.bufPrint(&buffer, "{d} ' {s} CATCH", .{ depth, case[1] }));
            const code = try machine.pop();
            try std.testing.expectEqual(@as(forth.Cell, if (depth == case[2]) 0 else -5), code);
            try std.testing.expectEqual(@as(usize, 1), machine.data_depth);
            if (code == 0) try expectStack(machine, &.{0});
            try std.testing.expectEqual(@as(usize, 0), machine.call_depth);
            try std.testing.expectEqual(@as(usize, 0), machine.frame_depth);
            try std.testing.expectEqual(@as(usize, 0), machine.return_depth);
            try std.testing.expectEqual(@as(usize, 0), machine.loop_depth);
            try std.testing.expectEqual(locals_top, machine.locals_top);
            try machine.interpretLine("DROP 40 2 +");
            try expectStack(machine, &.{42});
        }
        machine.data_depth = 0;
    }
}

test "CATCH returns 0 or the THROW code and restores the stack depths like gforth" {
    try support.skipWithoutFloat();
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
    try support.skipWithout(&.{ .files });
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

test "EXECUTE and a DEFER in compiled code run every kind of word" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    // A colon definition (called in the loop that runs the caller), a built-in word,
    // a constant, a word made by a DOES> definer, a name made by SYNONYM, and a DEFER.
    try machine.interpretLine(": TWICE 2* ; 7 CONSTANT SEVEN : ADDER CREATE , DOES> @ + ; 5 ADDER PLUS5 SYNONYM DOUBLE TWICE DEFER LATER ' TWICE IS LATER");
    try machine.interpretLine(": RUN ( x xt -- y ) EXECUTE 1+ ;");
    try machine.interpretLine("3 ' TWICE RUN  3 ' DUP RUN  ' SEVEN RUN  3 ' PLUS5 RUN  3 ' DOUBLE RUN  3 ' LATER RUN");
    try expectStack(machine, &.{ 7, 3, 4, 8, 9, 7, 7 });
    machine.data_depth = 0;

    // A DEFER called by its name: a colon definition, then a built-in word, then
    // another DEFER, then a name made by SYNONYM.
    try machine.interpretLine("DEFER OTHER ' TWICE IS OTHER : VIA ( x -- y ) LATER 1+ ;");
    try machine.interpretLine("3 VIA  ' NEGATE IS LATER 3 VIA  ' OTHER IS LATER 3 VIA  ' DOUBLE IS LATER 3 VIA");
    try expectStack(machine, &.{ 7, -2, 7, 7 });
    machine.data_depth = 0;

    // One without an action warns and goes on, as before.
    try machine.interpretLine("DEFER EMPTY : USES-EMPTY 1 EMPTY 2 ; USES-EMPTY");
    try expectStack(machine, &.{ 1, 2 });
    try std.testing.expectEqualStrings("WARNING: DEFERRED WORD EMPTY IS UNINITIALIZED\n", output.written());
    machine.data_depth = 0;

    // What is not an execution token is an error, and so is none.
    try std.testing.expectError(error.InvalidExecutionToken, machine.interpretLine("-1 ' TWICE DROP RUN"));
    machine.data_depth = 0;
    try std.testing.expectError(error.StackUnderflow, machine.interpretLine(": BARE EXECUTE ; BARE"));
    machine.data_depth = 0;

    // The words called this way return to where they were called, also from a loop
    // and with locals in the caller.
    try machine.interpretLine(": SUM-TWICE { n -- sum } 0 n 0 DO I ['] TWICE EXECUTE + LOOP n + ; 4 SUM-TWICE");
    try expectStack(machine, &.{16});
}

test "a definition with EXECUTE keeps it through SEE and a dictionary image" {
    try support.skipWithout(&.{.image});
    var output = Output{};
    const source = try createMachine(&output);
    defer destroyMachine(source);
    try source.interpretLine(": TWICE 2* ; : RUN ( x xt -- y ) EXECUTE 1+ ;" ++ support.see(" SEE RUN"));
    try std.testing.expectEqualStrings(support.see(": RUN\n  EXECUTE 1+\n;\n"), output.written());
    const image = try std.testing.allocator.alloc(u8, forth.State.imageCapacity(.small));
    defer std.testing.allocator.free(image);
    const length = try source.encodeImage(image);

    const loaded = try createMachine(&output);
    defer destroyMachine(loaded);
    try loaded.restoreImage(image[0..length]);
    try loaded.interpretLine("3 ' TWICE RUN");
    try expectStack(loaded, &.{7});
}
