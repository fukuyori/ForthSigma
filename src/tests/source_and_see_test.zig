//! Tests of parsing words, SEE, INCLUDE, REQUIRE, MARKER, and LOCATE.

const std = @import("std");
const forth = @import("../forth.zig");
const support = @import("support.zig");
const Output = support.Output;
const setFakeFile = support.setFakeFile;
const createMachine = support.createMachine;
const destroyMachine = support.destroyMachine;
const expectStack = support.expectStack;

test "a token consumes one following separator, so PARSE keeps further spaces" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine(": P [CHAR] | PARSE TYPE .\" |\" ; P  x y| : Q [CHAR] ) PARSE TYPE ; Q in parens) .\" after\"");
    try machine.interpretLine("S\"  two\" TYPE .\" |\" .\"glued text\" .\" |\" ");
    try std.testing.expectEqualStrings(" x y|in parensafter two|glued text|", output.written());
}

test "WORD returns a counted string and FIND reports immediacy" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine(": NEXT-NAME BL WORD COUNT ; NEXT-NAME    spaced NEXT-NAME");
    try std.testing.expectEqual(@as(usize, 4), machine.data_depth);
    try std.testing.expectEqual(@as(forth.Cell, 6), machine.data_stack[1]);
    try std.testing.expectEqual(@as(forth.Cell, 0), machine.data_stack[3]);
    machine.data_depth = 0;
    try machine.interpretLine(": LOOKUP BL WORD FIND NIP ; LOOKUP DUP LOOKUP IF LOOKUP NOSUCH : SHOW BL WORD FIND IF EXECUTE ELSE COUNT TYPE THEN ; 7 SHOW . SHOW MISSING");
    try expectStack(machine, &.{ -1, 1, 0 });
    try std.testing.expectEqualStrings("7 MISSING", output.written());
}

test "FIND-NAME NAME>INT and NAME>STRING follow the book's Level 10 example" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("S\" DUP\" FIND-NAME DUP 0<> SWAP NAME>INT ' DUP = S\" dup\" FIND-NAME NAME>STRING TYPE S\" NOSUCH\" FIND-NAME");
    try expectStack(machine, &.{ -1, -1, 0 });
    try std.testing.expectEqualStrings("DUP", output.written());
    try std.testing.expectError(error.InvalidExecutionToken, machine.interpretLine("0 NAME>INT"));
    machine.report(error.InvalidExecutionToken);
    try std.testing.expectError(error.InvalidExecutionToken, machine.interpretLine("100000 NAME>STRING"));
}

test "SEE shows definitions with their control structures" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine(": SQUARE ( n -- n^2 ) DUP * ; SEE SQUARE SEE IF 42 CONSTANT C SEE C");
    try machine.interpretLine(": T DUP 0< IF NEGATE ELSE 1+ THEN 3 0 DO I LOOP BEGIN DUP WHILE 1- REPEAT BEGIN 1+ DUP 5 > UNTIL BEGIN AGAIN ; SEE T");
    try machine.interpretLine(": M CREATE , DOES> @ ; 5 M FIVE SEE FIVE : S S\" hi\" TYPE .\" x\" ['] DUP DROP ; IMMEDIATE SEE S");
    try std.testing.expectEqualStrings(
        ": SQUARE\n  DUP *\n;\nBUILT-IN IF IMMEDIATE\n42 CONSTANT C\n" ++
            ": T\n  DUP 0< IF NEGATE ELSE 1+ THEN 3 0 DO I LOOP BEGIN DUP WHILE 1- REPEAT\n  BEGIN 1+ DUP 5 > UNTIL BEGIN AGAIN\n;\n" ++
            "CREATE FIVE\nDOES>\n  @\n;\n: S\n  S\" hi\" TYPE .\" x\" ['] DUP DROP\n; IMMEDIATE\n",
        output.written(),
    );
}

test "EVALUATE does not read further terminal lines and input lines are limited to the TIB" {
    var output = Output{};
    output.input_lines[0] = "NAME";
    output.input_count = 1;
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try std.testing.expectError(error.InvalidDefinition, machine.interpretLine("S\" CREATE\" EVALUATE"));
    machine.report(error.InvalidDefinition);
    try std.testing.expectEqual(@as(usize, 0), output.input_index);
    try machine.interpretLine("CREATE");
    try std.testing.expectEqual(@as(usize, 1), output.input_index);
    const long = [_]u8{' '} ** (forth.tib_size + 1);
    try std.testing.expectError(error.StringTooLong, machine.interpretLine(&long));
}

test "INCLUDE interprets a file across lines and reports its name and line" {
    var output = Output{};
    setFakeFile(&output, 0, ": SQUARE ( n -- n^2 )\n\tDUP * ;\nSOURCEFILENAME TYPE SPACE SOURCELINE# .\nCREATE\n  TABLE 7 ,\n");
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("INCLUDE a.txt 3 SQUARE TABLE @ S\" a.txt\" INCLUDED? S\" b.txt\" INCLUDED? SOURCELINE#");
    try expectStack(machine, &.{ 9, 7, -1, 0, 0 });
    try machine.interpretLine("SPACE SOURCEFILENAME TYPE SPACE S\" SOURCEFILENAME TYPE\" EVALUATE");
    try std.testing.expectEqualStrings("a.txt 3  *the terminal* *evaluated string*", output.written());
    try std.testing.expect(!output.files[0].open);
}

test "REQUIRE loads a file once, even when it requires itself" {
    var output = Output{};
    setFakeFile(&output, 0, "REQUIRE a.txt\n.\" once\"\n");
    setFakeFile(&output, 1, "DUP CONSTANT SIZE\n");
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("REQUIRE a.txt NEEDS a.txt S\" a.txt\" REQUIRED 1024 REQUIRE b.txt DROP 2048 REQUIRE b.txt DROP SIZE");
    try expectStack(machine, &.{1024});
    try std.testing.expectEqualStrings("once", output.written());
}

test "errors in included files name the innermost file and line and close every file" {
    var output = Output{};
    setFakeFile(&output, 0, "1\nINCLUDE b.txt\n2\n");
    setFakeFile(&output, 1, "3\n: BAD MISSING ;\n");
    setFakeFile(&output, 2, ": HALF 1\n");
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    const words = machine.word_count;

    try std.testing.expectError(error.UnknownWord, machine.interpretLine("INCLUDE a.txt"));
    machine.report(error.UnknownWord);
    try std.testing.expectError(error.InvalidDefinition, machine.interpretLine("INCLUDE c.txt"));
    machine.report(error.InvalidDefinition);
    try std.testing.expectError(error.Thrown, machine.interpretLine("INCLUDE none.txt"));
    machine.report(error.Thrown);
    try std.testing.expectEqualStrings("b.txt:2: MISSING ?\nc.txt:1: DEFINITION ERROR !\nNO SUCH FILE OR DIRECTORY !\n", output.written());
    try std.testing.expectEqual(words, machine.word_count);
    for (output.files) |file| try std.testing.expect(!file.open);
    try machine.interpretLine("STATE @");
    try expectStack(machine, &.{0});
}

test "CATCH around INCLUDED lets the rest of the line run" {
    var output = Output{};
    setFakeFile(&output, 0, "1 2\nMISSING\n");
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("S\" a.txt\" ' INCLUDED CATCH NIP NIP 42");
    try expectStack(machine, &.{ -13, 42 });
    machine.report(error.Aborted);
    try std.testing.expectEqualStrings("", output.written());
    try std.testing.expect(!output.files[0].open);
}

test "INCLUDE nesting is limited" {
    var output = Output{};
    setFakeFile(&output, 0, "INCLUDE a.txt\n");
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try std.testing.expectError(error.IncludeNesting, machine.interpretLine("INCLUDE a.txt"));
    machine.report(error.IncludeNesting);
    try std.testing.expectEqualStrings("a.txt:1: INCLUDE NESTING ERROR !\n", output.written());
}

test "MARKER forgets later words and the files required after it" {
    var output = Output{};
    setFakeFile(&output, 0, "DUP CONSTANT SIZE\n");
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    const words = machine.word_count;

    try machine.interpretLine("MARKER SAFE : TEMP 1 ; 5 REQUIRE a.txt DROP SIZE SAFE 7 REQUIRE a.txt DROP SIZE S\" TEMP\" FIND-NAME");
    try expectStack(machine, &.{ 5, 7, 0 });
    try std.testing.expectEqual(words + 1, machine.word_count);
    try machine.interpretLine("MARKER M SEE M");
    try std.testing.expectEqualStrings("MARKER M\n", output.written());
}

test "LOCATE prints the file, line, and the lines of the definition" {
    var output = Output{};
    setFakeFile(&output, 0, "\\ library\n: SUM\n  BEGIN DEPTH 1 > WHILE + REPEAT ;\n: OTHER ;\n");
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("INCLUDE a.txt : HERE-ONLY ; LOCATE SUM LOCATE HERE-ONLY");
    try std.testing.expectEqualStrings("a.txt:2\n: SUM\n  BEGIN DEPTH 1 > WHILE + REPEAT ;\nHERE-ONLY: NO FILE INFORMATION\n", output.written());
}

test "source locations and the REQUIRE history survive image restore and LOAD" {
    var output = Output{};
    setFakeFile(&output, 0, ": FROM-A 1 ;\n");
    setFakeFile(&output, 1, ": FROM-B\n  2 ;\n");
    const source = try createMachine(&output);
    defer destroyMachine(source);
    try source.interpretLine("INCLUDE b.txt");
    const image = try std.testing.allocator.alloc(u8, forth.State.imageCapacity());
    defer std.testing.allocator.free(image);
    const length = try source.encodeImage(image);

    const loaded = try createMachine(&output);
    defer destroyMachine(loaded);
    try loaded.restoreImage(image[0..length]);
    try loaded.interpretLine("S\" b.txt\" INCLUDED? LOCATE FROM-B");

    const target = try createMachine(&output);
    defer destroyMachine(target);
    try target.interpretLine("INCLUDE a.txt");
    try target.appendImage(loaded);
    try target.interpretLine("S\" b.txt\" INCLUDED? LOCATE FROM-B LOCATE FROM-A");
    try expectStack(loaded, &.{-1});
    try expectStack(target, &.{-1});
    try std.testing.expectEqualStrings("b.txt:1\n: FROM-B\n  2 ;\nb.txt:1\n: FROM-B\n  2 ;\na.txt:1\n: FROM-A 1 ;\n", output.written());
}

test "a parsing word left waiting at the end of an EVALUATE string is an error" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    const words = machine.word_count;

    try std.testing.expectError(error.InvalidDefinition, machine.interpretLine("S\" VARIABLE\" EVALUATE LEAK"));
    machine.report(error.InvalidDefinition);
    try std.testing.expectError(error.InvalidDefinition, machine.interpretLine("S\" :\" EVALUATE NAME"));
    machine.report(error.InvalidDefinition);
    try std.testing.expectEqual(words, machine.word_count);
    try machine.interpretLine("S\" 5 CONSTANT\" ' EVALUATE CATCH NIP NIP S\" LEAK\" FIND-NAME");
    try expectStack(machine, &.{ -259, 0 });
}

test "INCLUDE between CREATE and DOES> keeps the word being created" {
    var output = Output{};
    setFakeFile(&output, 0, "\\ only a comment\n");
    setFakeFile(&output, 1, "MISSING\n");
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine(": M1 CREATE , S\" a.txt\" INCLUDED DOES> @ ; 5 M1 FIVE FIVE");
    try machine.interpretLine(": M2 CREATE , S\" b.txt\" ['] INCLUDED CATCH NIP NIP DROP DOES> @ ; 6 M2 SIX SIX");
    try machine.interpretLine(": M3 CREATE , S\" 1 DROP\" EVALUATE DOES> @ ; 7 M3 SEVEN SEVEN");
    try expectStack(machine, &.{ 5, 6, 7 });
}

test "MARKER inside an included file keeps the names that frames and words refer to" {
    var output = Output{};
    setFakeFile(&output, 0, ": FROM-A ;\nM\nINCLUDE c.txt\nSOURCEFILENAME TYPE\n");
    setFakeFile(&output, 2, ": FROM-C ;\n");
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("MARKER M INCLUDE a.txt S\" a.txt\" INCLUDED? S\" c.txt\" INCLUDED? LOCATE FROM-C");
    try expectStack(machine, &.{ 0, -1 });
    try std.testing.expectEqualStrings("a.txtc.txt:1\n: FROM-C ;\n", output.written());
    machine.data_depth = 0;
    try machine.interpretLine("MARKER M2 REQUIRE c.txt M2 S\" c.txt\" INCLUDED?");
    try expectStack(machine, &.{-1});
}

test "a MARKER loaded with LOAD restores the history it was made with" {
    var output = Output{};
    setFakeFile(&output, 0, ": FROM-A 1 ;\n");
    setFakeFile(&output, 1, ": FROM-B 2 ;\n");
    setFakeFile(&output, 2, ": FROM-C 3 ;\n");
    const source = try createMachine(&output);
    defer destroyMachine(source);
    try source.interpretLine("INCLUDE a.txt MARKER M");
    const image = try std.testing.allocator.alloc(u8, forth.State.imageCapacity());
    defer std.testing.allocator.free(image);
    const length = try source.encodeImage(image);
    const loaded = try createMachine(&output);
    defer destroyMachine(loaded);
    try loaded.restoreImage(image[0..length]);

    const target = try createMachine(&output);
    defer destroyMachine(target);
    try target.interpretLine("INCLUDE b.txt");
    try target.appendImage(loaded);
    try target.interpretLine("REQUIRE c.txt M S\" a.txt\" INCLUDED? S\" b.txt\" INCLUDED? S\" c.txt\" INCLUDED? INCLUDE c.txt LOCATE FROM-A");
    try expectStack(target, &.{ -1, -1, 0 });
    try std.testing.expectEqualStrings("a.txt:1\n: FROM-A 1 ;\n", output.written());
}

test "a file that ends the caller's definition and starts another is an error" {
    var output = Output{};
    setFakeFile(&output, 3, "] ; : HALF 1\n");
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try std.testing.expectError(error.InvalidDefinition, machine.interpretLine(": OUTER 1 [ S\" d.txt\" INCLUDED"));
    machine.report(error.InvalidDefinition);
    try std.testing.expectEqualStrings("d.txt:1: DEFINITION ERROR !\n", output.written());
    try machine.interpretLine("S\" HALF\" FIND-NAME");
    try expectStack(machine, &.{0});
}

test "a failing close is reported at the file that failed" {
    var output = Output{};
    output.close_fails = true;
    setFakeFile(&output, 0, "1\n");
    setFakeFile(&output, 1, "INCLUDE a.txt\n2\n");
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try std.testing.expectError(error.Thrown, machine.interpretLine("INCLUDE a.txt"));
    machine.report(error.Thrown);
    try std.testing.expectError(error.Thrown, machine.interpretLine("INCLUDE b.txt"));
    machine.report(error.Thrown);
    try machine.interpretLine("S\" a.txt\" ' INCLUDED CATCH NIP NIP");
    try expectStack(machine, &.{forth.errnoIor(5)});
    try std.testing.expectEqualStrings("a.txt:1: INPUT/OUTPUT ERROR !\na.txt:1: INPUT/OUTPUT ERROR !\n", output.written());
    for (output.files) |file| try std.testing.expect(!file.open);
}

test "WORD and NAME>STRING buffers have the documented limits" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    var line: [300]u8 = undefined;
    @memcpy(line[0..16], ": W BL WORD ; W ");
    @memset(line[16 .. 16 + 255], 'x');

    try machine.interpretLine(line[0 .. 16 + 255]);
    try std.testing.expectEqual(@as(u8, 255), machine.memory[@intCast(machine.data_stack[0])]);
    line[16 + 255] = 'x';
    try std.testing.expectError(error.StringTooLong, machine.interpretLine(line[0 .. 16 + 256]));
    machine.report(error.StringTooLong);
    try machine.interpretLine(": NS 9 0 DO S\" DUP\" FIND-NAME NAME>STRING DROP LOOP ; NS");
    try std.testing.expectEqual(@as(usize, 9), machine.data_depth);
    try std.testing.expectEqual(machine.data_stack[0], machine.data_stack[8]);
    for (1..8) |index| try std.testing.expect(machine.data_stack[index] != machine.data_stack[0]);
}

test "SEE handles nested and empty branches and CASE" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine(": N IF IF 1 THEN ELSE THEN ; SEE N : E IF THEN BEGIN UNTIL ; SEE E : C CASE 1 OF 10 ENDOF 20 SWAP ENDCASE ; SEE C");
    try std.testing.expectEqualStrings(
        ": N\n  IF IF 1 THEN ELSE THEN\n;\n: E\n  IF THEN BEGIN UNTIL\n;\n: C\n  1 OVER = IF DROP 10 ELSE 20 SWAP DROP THEN\n;\n",
        output.written(),
    );
}
