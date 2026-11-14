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
    machine.plain_calls = true;
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
    machine.plain_calls = true;
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
    machine.plain_calls = true;
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

test "~~VALUE in a definition reads its name at once, and a failed one leaves nothing" {
    try support.skipWithout(&.{.debug});
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    // As VALUE: the word exists when the rest of the definition runs.
    try machine.interpretLine(": MAKE ~~VALUE LATESTXT ; 7 MAKE V ' V = V");
    try expectStack(machine, &.{ -1, 7 });
    try machine.interpretLine("2DROP 8 TO V");
    try std.testing.expectEqualStrings("\n*the terminal*:0:12:<1> #8 `V \n", shown(&output));

    // A ~~VALUE without a name is an error, and the VALUE after it is an ordinary one.
    try machine.interpretLine(": BAD S\" 7 ~~VALUE\" EVALUATE ; ' BAD CATCH DROP 1 VALUE NORMAL 2 TO NORMAL NORMAL");
    try std.testing.expectEqual(@as(forth.Cell, 2), try machine.pop());
    try std.testing.expectEqualStrings("", shown(&output));
}

test "~~BT shows the callers beyond an EVALUATE" {
    try support.skipWithout(&.{.debug});
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine(": INNER ~~BT ; : OUTER S\" INNER\" EVALUATE ; : TOP OUTER ; TOP");
    try std.testing.expectEqualStrings("\n*the terminal*:0:9:<0> \nBACKTRACE:\n  OUTER\n  TOP\n", shown(&output));
    // The interpreter itself has no caller, also after that.
    try machine.interpretLine("INNER");
    try std.testing.expectEqualStrings("\n*the terminal*:0:9:<0> \nBACKTRACE:\n", shown(&output));
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

test "the profile counts the calls and the operations of each word" {
    try support.skipWithout(&.{.debug});
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    const profile = try std.testing.allocator.create(forth.Profile);
    defer std.testing.allocator.destroy(profile);
    profile.reset();
    machine.profile = profile;
    machine.plain_calls = true;

    // SQUARE is 3 operations (DUP, *, the end), SUMSQ 5 of its own, RUN 54.
    try machine.interpretLine(": SQUARE DUP * ; : SUMSQ SQUARE SWAP SQUARE + ; : RUN 10 0 DO I I SUMSQ DROP LOOP ; RUN");
    const square = machine.lookup("SQUARE").?;
    const sumsq = machine.lookup("SUMSQ").?;
    try std.testing.expectEqual(@as(u64, 20), profile.calls[square]);
    try std.testing.expectEqual(@as(u64, 60), profile.total[square]);
    try std.testing.expectEqual(@as(u64, 10), profile.calls[sumsq]);
    try std.testing.expectEqual(@as(u64, 110), profile.total[sumsq]);
    try std.testing.expectEqual(@as(u64, 164), profile.operations);

    profile.show(machine);
    try std.testing.expectEqualStrings(
        \\PROFILE: 164 OPERATIONS
        \\     CALLS        SELF       TOTAL  WORD
        \\        20          60          60  SQUARE
        \\         1          54         164  RUN
        \\        10          50         110  SUMSQ
        \\
    , shown(&output));
}

test "the profile counts a recursion once, and ends the words that an error ended" {
    try support.skipWithout(&.{.debug});
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    const profile = try std.testing.allocator.create(forth.Profile);
    defer std.testing.allocator.destroy(profile);
    profile.reset();
    machine.profile = profile;
    machine.plain_calls = true;

    try machine.interpretLine(": DOWN DUP IF 1- RECURSE THEN ; 5 DOWN DROP");
    const down = machine.lookup("DOWN").?;
    try std.testing.expectEqual(@as(u64, 6), profile.calls[down]);
    try std.testing.expectEqual(profile.operations, profile.total[down]);

    // BAD ends in an error that CATCH catches: its operations still count for TRY.
    try machine.interpretLine(": BAD 1 0 / ; : TRY ['] BAD CATCH DROP ; TRY");
    try std.testing.expectEqual(@as(usize, 0), profile.depth);
    try std.testing.expectEqual(@as(u64, 3), profile.total[machine.lookup("BAD").?]);
    try std.testing.expectEqual(@as(u64, 7), profile.total[machine.lookup("TRY").?]);

    // One that reaches the host is ended by its report.
    try std.testing.expectError(error.DivisionByZero, machine.interpretLine("BAD"));
    try std.testing.expectEqual(@as(usize, 1), profile.depth);
    machine.report(error.DivisionByZero);
    try std.testing.expectEqual(@as(usize, 0), profile.depth);
}

test "a word that takes the place of a removed one starts its profile at 0" {
    try support.skipWithout(&.{.debug});
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    const profile = try std.testing.allocator.create(forth.Profile);
    defer std.testing.allocator.destroy(profile);
    profile.reset();
    machine.profile = profile;
    machine.plain_calls = true;

    try machine.interpretLine(": OLD 1 DROP ; OLD FORGET OLD : NEW 2 DROP ; NEW");
    const new = machine.lookup("NEW").?;
    try std.testing.expectEqual(@as(u64, 1), profile.calls[new]);
    try std.testing.expectEqual(@as(u64, 3), profile.total[new]);
    // What OLD ran stays in the whole.
    try std.testing.expectEqual(@as(u64, 6), profile.operations);
    profile.show(machine);
    try std.testing.expect(std.mem.endsWith(u8, shown(&output), "         1           3           3  NEW\n"));
}

test "the short definitions of a loaded image stay calls for the trace" {
    try support.skipWithout(&.{ .debug, .image });
    var output = Output{};
    const source = try createMachine(&output);
    defer destroyMachine(source);
    try source.interpretLine(": SQUARE DUP * ; : RUN 3 SQUARE DROP ;");
    const image = try std.testing.allocator.alloc(u8, forth.State.imageCapacity(.small));
    defer std.testing.allocator.free(image);
    const length = try source.encodeImage(image);

    // As LOAD does: the image is restored in a State of its own, which the host gives
    // the setting of the one it is added to.
    const target = try createMachine(&output);
    defer destroyMachine(target);
    target.tracing = true;
    target.plain_calls = true;
    const loaded = try createMachine(&output);
    defer destroyMachine(loaded);
    loaded.plain_calls = target.plain_calls;
    try loaded.restoreImage(image[0..length]);
    try target.appendImage(loaded);
    try target.interpretLine("RUN");
    try std.testing.expectEqualStrings("> RUN <0>\n  > SQUARE <1> 3\n  < SQUARE <1> 9\n< RUN <0>\n", shown(&output));
}

test "the coverage words show the blocks of the code as gforth's do" {
    try support.skipWithout(&.{ .debug, .files });
    var output = Output{};
    // The program that gforth 0.7.9 was run with (after its `require coverage.fs`).
    setFakeFile(&output, 0,
        \\: square ( n -- n ) dup * ;
        \\: sumsq ( a b -- n ) square swap square + ;
        \\: pick-one ( f -- n ) if 1 else 2 then ;
        \\: run ( -- ) 10 0 do i i sumsq drop loop 0 pick-one drop ;
        \\run
        \\
    );
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    const profile = try std.testing.allocator.create(forth.Profile);
    defer std.testing.allocator.destroy(profile);
    profile.reset();
    machine.profile = profile;
    machine.plain_calls = true;
    machine.cover_blocks = true;

    try machine.interpretLine("INCLUDE a.txt .COVER-RAW");
    try std.testing.expectEqualStrings("a.txt:1:9: 20 \na.txt:2:8: 10 \na.txt:3:11: 1 \na.txt:3:25: 0 \na.txt:3:32: 1 \na.txt:3:39: 1 \na.txt:4:6: 1 \na.txt:4:21: 10 \na.txt:4:41: 1 \n", output.written());

    output.len = 0;
    try machine.interpretLine("COV%");
    try std.testing.expectEqualStrings("88.8% coverage", output.written());

    output.len = 0;
    try machine.interpretLine(".COVERAGE");
    try std.testing.expectEqualStrings("\n" ++
        ": square ( 20)  ( n -- n ) dup * ;\n" ++
        ": sumsq ( 10)  ( a b -- n ) square swap square + ;\n" ++
        ": pick-one ( 1)  ( f -- n ) if ( 0)  1 else ( 1)  2 then ( 1)  ;\n" ++
        ": run ( 1)  ( -- ) 10 0 do ( 10)  i i sumsq drop loop ( 1)  0 pick-one drop ;\n" ++
        "run\n", output.written());

    // The other structures start blocks too, and so does each further line of a
    // definition (gforth gives the same places and counts for this text, and the block
    // after endcase twice). A definition typed in has no file and is not shown.
    output.len = 0;
    setFakeFile(&output, 1, ": loops ( n -- )\n   begin dup while 1- repeat drop\n   3 case 1 of 10 endof 3 of 30 endof endcase drop ;\n2 loops\n");
    try machine.interpretLine(": TYPED IF 1 THEN ; INCLUDE b.txt .COVER-RAW");
    try std.testing.expect(std.mem.endsWith(u8, output.written(), "b.txt:1:8: 1 \nb.txt:2:1: 1 \nb.txt:2:9: 3 \nb.txt:2:19: 2 \nb.txt:2:29: 1 \nb.txt:3:1: 1 \nb.txt:3:10: 1 \nb.txt:3:15: 0 \nb.txt:3:24: 1 \nb.txt:3:29: 1 \nb.txt:3:38: 0 \nb.txt:3:46: 1 \n"));
    output.len = 0;
    try machine.interpretLine("COV%");
    // 18 of the 21 blocks of the two files.
    try std.testing.expectEqualStrings("85.7% coverage", output.written());
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "TYPED") == null);
}

test "the coverage words need the counts" {
    try support.skipWithout(&.{.debug});
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try std.testing.expectError(error.Thrown, machine.interpretLine("COV%"));
    machine.report(error.Thrown);
    try std.testing.expectEqualStrings("no coverage: start with --coverage\n", output.written());
    // Without the option no code is compiled for the blocks.
    try machine.interpretLine(": T IF 1 THEN ;");
    try std.testing.expectEqual(@as(u16, 3), machine.words[machine.lookup("T").?].code_end - machine.words[machine.lookup("T").?].code_start);
    try std.testing.expectError(error.Thrown, machine.interpretLine(".COVER-RAW"));
    try std.testing.expectError(error.Thrown, machine.interpretLine(".COVERAGE"));
}

test "a block starts after a word of a structure however the word is reached" {
    try support.skipWithout(&.{ .debug, .files });
    var output = Output{};
    // IF through a word that POSTPONEs it, and THEN by another name.
    setFakeFile(&output, 0, ": MYIF POSTPONE IF ; IMMEDIATE\nSYNONYM MYTHEN THEN\n: TEST MYIF 111 DROP MYTHEN ;\n0 TEST\n");
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    const profile = try std.testing.allocator.create(forth.Profile);
    defer std.testing.allocator.destroy(profile);
    profile.reset();
    machine.profile = profile;
    machine.plain_calls = true;
    machine.cover_blocks = true;

    // The blocks of TEST: after its name, after MYIF (not run), and after MYTHEN.
    try machine.interpretLine("INCLUDE a.txt .COVER-RAW");
    try std.testing.expectEqualStrings("a.txt:1:7: 1 \na.txt:3:7: 1 \na.txt:3:12: 0 \na.txt:3:28: 1 \n", output.written());
    output.len = 0;
    try machine.interpretLine("COV%");
    try std.testing.expectEqualStrings("75.0% coverage", output.written());
}

test ".COVERAGE shows every block of a line with many" {
    try support.skipWithout(&.{ .debug, .files });
    var output = Output{};
    setFakeFile(&output, 0, ": MANY " ++ support.repeat("1 IF THEN ", 17) ++ ";\nMANY\n");
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    const profile = try std.testing.allocator.create(forth.Profile);
    defer std.testing.allocator.destroy(profile);
    profile.reset();
    machine.profile = profile;
    machine.plain_calls = true;
    machine.cover_blocks = true;

    // The block after the name and two for each IF THEN: 35.
    try machine.interpretLine("INCLUDE a.txt .COVERAGE");
    try std.testing.expectEqual(@as(usize, 35), std.mem.count(u8, output.written(), " ( 1) "));
    try std.testing.expect(std.mem.startsWith(u8, output.written(), "\n: MANY ( 1)  1 IF ( 1)  THEN ( 1)  1 IF ( 1)  THEN ( 1)  "));
}

test "WATCH shows each change of a cell, with the word that made it" {
    try support.skipWithout(&.{ .debug, .files });
    var output = Output{};
    setFakeFile(&output, 0,
        \\VARIABLE SCORE
        \\CREATE WATCH-TABLE 4 CELLS ALLOT
        \\: BUMP ( -- ) 1 SCORE +! ;
        \\: CLOBBER ( -- ) WATCH-TABLE 4 CELLS -1 FILL ;
        \\: INDIRECT ( -- ) 9 WATCH-TABLE 2 CELLS + ! ;
        \\: UNTOUCHED ( -- ) SCORE @ DROP ;
        \\: MAIN ( -- ) BUMP UNTOUCHED BUMP INDIRECT CLOBBER ;
        \\
    );
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    try machine.interpretLine("INCLUDE a.txt SCORE WATCH-TABLE 2 CELLS +");
    const cell = try machine.pop();
    const score = try machine.pop();

    // A store through the name, one to an address worked out, and FILL over the cell.
    try machine.interpretLine("SCORE WATCH  WATCH-TABLE 2 CELLS + WATCH  MAIN");
    var expected: [512]u8 = undefined;
    try std.testing.expectEqualStrings(try std.fmt.bufPrint(&expected, "WATCH: {d} changed from 0 to 1\n  in BUMP a.txt:3\n" ++
        "WATCH: {d} changed from 1 to 2\n  in BUMP a.txt:3\n" ++
        "WATCH: {d} changed from 0 to 9\n  in INDIRECT a.txt:5\n" ++
        "WATCH: {d} changed from 9 to -1\n  in CLOBBER a.txt:4\n", .{ score, score, cell, cell }), shown(&output));

    // A word that the interpreter runs has no definition to name. After UNWATCH the
    // cell is not looked at, and the other one still is.
    try machine.interpretLine("7 SCORE !  SCORE UNWATCH  8 SCORE !  BUMP  INDIRECT");
    try std.testing.expectEqualStrings(try std.fmt.bufPrint(&expected, "WATCH: {d} changed from 2 to 7\n" ++
        "WATCH: {d} changed from -1 to 9\n  in INDIRECT a.txt:5\n", .{ score, cell }), shown(&output));
    try std.testing.expectEqualStrings("", output.written());

    // Eight cells at most, and an address that is one.
    try machine.interpretLine("WATCH-TABLE 2 CELLS + UNWATCH : W8 8 0 DO HERE WATCH 0 , LOOP ; W8");
    try std.testing.expectError(error.Thrown, machine.interpretLine("HERE WATCH"));
    machine.report(error.Thrown);
    try std.testing.expectEqualStrings("too many watched cells\n", output.written());
    try std.testing.expectError(error.InvalidAddress, machine.interpretLine("-8 WATCH"));
}

test "~~VARIABLE shows every use of its name" {
    try support.skipWithout(&.{.debug});
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    // At once outside a definition, and from a definition when it runs.
    try machine.interpretLine("~~VARIABLE SEEN 3 SEEN ! : USES 5 SEEN ! SEEN @ ; USES");
    try expectStack(machine, &.{5});
    try std.testing.expectEqualStrings("\n*the terminal*:0:19:<1> #3 `SEEN \n\n*the terminal*:0:35:<1> #5 `SEEN \n\n*the terminal*:0:42:<0> `SEEN \n", shown(&output));

    // In a definition its name is read at once, as that of VARIABLE. The name after '
    // is read, not used, and an ordinary VARIABLE says nothing.
    try machine.interpretLine("DROP : MAKE ~~VARIABLE LATESTXT ; MAKE V ' V = VARIABLE PLAIN 1 PLAIN !");
    try expectStack(machine, &.{-1});
    try std.testing.expectEqualStrings("", shown(&output));
    try machine.interpretLine("DROP 2 V !");
    try std.testing.expectEqualStrings("\n*the terminal*:0:8:<1> #2 `V \n", shown(&output));
}

test "WATCH sees what a defining word changes, before the next word runs" {
    try support.skipWithout(&.{.debug});
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    // VARIABLE V sets the cell at HERE to 0; UNWATCH comes right after it.
    try machine.interpretLine("HERE DUP DUP 7 SWAP ! WATCH VARIABLE V UNWATCH");
    var expected: [96]u8 = undefined;
    const address = machine.words[machine.lookup("V").?].value;
    try std.testing.expectEqualStrings(try std.fmt.bufPrint(&expected, "WATCH: {d} changed from 7 to 0\n", .{address}), shown(&output));

    // The last word of a line is looked at too.
    try machine.interpretLine("V WATCH 5 V !");
    try std.testing.expectEqualStrings(try std.fmt.bufPrint(&expected, "WATCH: {d} changed from 0 to 5\n", .{address}), shown(&output));
}

test "~~VARIABLE shows a use that a word made by POSTPONE compiles" {
    try support.skipWithout(&.{.debug});
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("~~VARIABLE V : M POSTPONE V ; IMMEDIATE : T 3 M ! ; T V @");
    try std.testing.expectEqual(@as(forth.Cell, 3), try machine.pop());
    // The use in T, where M stands, and the one outside a definition.
    const text = shown(&output);
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, text, "`V \n"));
    try std.testing.expect(std.mem.indexOf(u8, text, "<1> #3 `V \n") != null);
}
