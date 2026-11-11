//! Tests of the checks of --lint.

const std = @import("std");
const forth = @import("../forth.zig");
const support = @import("support.zig");
const Output = support.Output;
const createMachine = support.createMachine;
const destroyMachine = support.destroyMachine;
const setFakeFile = support.setFakeFile;

/// Includes a.txt with the checks on, and gives the report of the checks.
fn findings(source: []const u8, output: *Output, lint: *forth.Lint) ![]const u8 {
    setFakeFile(output, 0, source);
    const machine = try createMachine(output);
    defer destroyMachine(machine);
    lint.reset();
    machine.lint = lint;
    try machine.interpretLine("INCLUDE a.txt");
    output.len = 0;
    lint.report(machine);
    return output.written();
}

test "each check finds what it is for" {
    try support.skipWithout(&.{ .debug, .files, .help });
    var output = Output{};
    const lint = try std.testing.allocator.create(forth.Lint);
    defer std.testing.allocator.destroy(lint);

    // USES, which calls them all, has no finding of its own: UNEVEN is taken at its
    // stack comment, and what KEEPS leaves on the return stack is the finding of KEEPS.
    try std.testing.expectEqualStrings(
        \\a.txt:1: UNUSED: SQUARE is not used in the files
        \\a.txt:2: REDEFINED: SQUARE was defined at a.txt:1
        \\a.txt:3: REDEFINED: NIP is a built-in word
        \\a.txt:4: UNREACHABLE: code in AFTER that is never reached
        \\a.txt:5: STACK DEPTH: paths in UNEVEN meet with different stack depths
        \\a.txt:6: RETURN STACK: KEEPS ends with 1 more on the return stack
        \\a.txt:7: STACK EFFECT: WRONG is declared ( 2 -- 1 ) but its code is ( 2 -- 2 )
        \\a.txt:8: STACK EFFECT: NEEDS-MORE is declared ( 1 -- 1 ) but its code is ( 2 -- 1 )
        \\a.txt:9: UNUSED: SPARE is not used in the files
        \\LINT: 9 FINDINGS
        \\
    , try findings(
        \\: SQUARE ( n -- n ) DUP * ;
        \\: SQUARE ( n -- n ) DUP DUP * * ;
        \\: NIP ( a b -- b ) SWAP DROP ;
        \\: AFTER ( -- n ) 1 EXIT 2 ;
        \\: UNEVEN ( flag -- ) IF 1 THEN ;
        \\: KEEPS ( n -- ) >R ;
        \\: WRONG ( a b -- c ) + DUP ;
        \\: NEEDS-MORE ( a -- b ) + ;
        \\VARIABLE SPARE
        \\: USES 3 SQUARE 1 2 NIP AFTER UNEVEN KEEPS WRONG NEEDS-MORE ;
        \\USES
        \\
    , &output, lint));
    try std.testing.expectEqual(@as(usize, 9), lint.findings);
}

test "code that keeps to its stack comments has no findings" {
    try support.skipWithout(&.{ .debug, .files, .help });
    var output = Output{};
    const lint = try std.testing.allocator.create(forth.Lint);
    defer std.testing.allocator.destroy(lint);

    // Loops, both sides of an IF, LEAVE, the return stack, doubles, strings, values,
    // locals, words that call words, paths that THROW or ABORT ends, a comment whose d
    // is not a double, CASE, and a loop without an end. FOREVER never ends, so
    // it has no stack effect of its own; USES, which calls it, takes it at its comment.
    try std.testing.expectEqualStrings("LINT: 1 DEFINITIONS WITHOUT A FIXED STACK EFFECT WERE NOT CHECKED FOR IT\nLINT: NO FINDINGS\n", try findings(
        \\VARIABLE COUNTER
        \\7 VALUE LIMIT
        \\: GOOD ( a b -- sum ) + ;
        \\: LOOPS ( n -- ) 0 ?DO I DROP LOOP ;
        \\: STEPS ( n -- ) 0 DO I 5 = IF LEAVE THEN 2 +LOOP ;
        \\: CHOOSES ( flag -- n ) IF 1 ELSE 2 THEN ;
        \\: WHILES ( n -- ) BEGIN DUP WHILE 1- REPEAT DROP ;
        \\: UNTILS ( n -- ) BEGIN 1- DUP 0= UNTIL DROP ;
        \\: SAVES ( a b -- b a ) >R >R 2R> SWAP ;
        \\: DOUBLES ( d1 d2 -- d3 ) D+ ;
        \\: TEXT ( -- c-addr u ) S" hello" ;
        \\: SETS ( n -- ) TO LIMIT ;
        \\: PASSES ( a b c -- a n ) GOOD ;
        \\: NAMED { a b -- sum } a b + ;
        \\: CHECKED ( n -- n ) DUP 0< IF DROP 1 THROW THEN ;
        \\: STOPS ( flag -- ) IF ABORT THEN ;
        \\: OPPOSITE ( n -- -n ) S>D DNEGATE DROP ;
        \\: DISTANCE ( i -- d ) DUP * ;
        \\: PICKS ( char -- n ) CASE [CHAR] A OF 1 ENDOF [CHAR] B OF 2 ENDOF 0 SWAP ENDCASE ;
        \\: FOREVER ( -- ) BEGIN COUNTER @ DROP AGAIN ;
        \\: USES 1 2 GOOD LOOPS 3 STEPS 0 CHOOSES WHILES 4 UNTILS 5 6 SAVES 2DROP 1. 2. DOUBLES 2DROP TEXT 2DROP 8 SETS 1 2 3 PASSES 2DROP 1 2 NAMED DROP
        \\  1 CHECKED 0 STOPS OPPOSITE DISTANCE PICKS DROP FOREVER ;
        \\' USES DROP
        \\
    , &output, lint));
}

test "definitions without a fixed stack effect are counted, and floats are checked when named" {
    try support.skipWithout(&.{ .debug, .files, .help });
    try support.skipWithoutFloat();
    var output = Output{};
    const lint = try std.testing.allocator.create(forth.Lint);
    defer std.testing.allocator.destroy(lint);

    // DYNAMIC and MAYBE have no fixed effect; VIA, which calls DYNAMIC, takes it at its
    // stack comment and is checked. A comment without ( F: ... ) says nothing of the
    // floating-point stack.
    try std.testing.expectEqualStrings(
        \\a.txt:4: STACK EFFECT: MIXED is declared ( F: 2 -- 1 ) but its code is ( F: 2 -- 2 )
        \\LINT: 2 DEFINITIONS WITHOUT A FIXED STACK EFFECT WERE NOT CHECKED FOR IT
        \\LINT: 1 FINDINGS
        \\
    , try findings(
        \\: DYNAMIC ( xt -- ) EXECUTE ;
        \\: MAYBE ( x -- 0 | x x ) ?DUP ;
        \\: VIA ( xt -- n ) DYNAMIC 1 ;
        \\: MIXED ( n -- ) ( F: r1 r2 -- r3 ) DROP F+ FDUP ;
        \\: QUIET ( n -- n ) 1.5E FDROP ;
        \\: SUMS ( F: r1 r2 -- r3 ) F+ ;
        \\: USES ['] DYNAMIC DROP ['] MAYBE DROP ['] VIA DROP 1 MIXED 2 QUIET DROP SUMS FDROP ;
        \\' USES DROP
        \\
    , &output, lint));
}

test "an effect too large to count is not known, and does not end the checks" {
    try support.skipWithout(&.{ .debug, .files, .help });
    var output = Output{};
    const lint = try std.testing.allocator.create(forth.Lint);
    defer std.testing.allocator.destroy(lint);

    // G15 would leave 32768 cells: each G calls the one before it twice.
    var source: [1024]u8 = undefined;
    var length: usize = 0;
    length += (try std.fmt.bufPrint(source[length..], ": G0 1 ;\n", .{})).len;
    for (1..16) |index| {
        length += (try std.fmt.bufPrint(source[length..], ": G{d} G{d} G{d} ;\n", .{ index, index - 1, index - 1 })).len;
    }
    length += (try std.fmt.bufPrint(source[length..], "' G15 DROP\n", .{})).len;
    const report = try findings(source[0..length], &output, lint);
    try std.testing.expect(std.mem.endsWith(u8, report, "LINT: 1 DEFINITIONS WITHOUT A FIXED STACK EFFECT WERE NOT CHECKED FOR IT\nLINT: NO FINDINGS\n"));
    try std.testing.expectEqualStrings("LINT: 1 DEFINITIONS WITHOUT A FIXED STACK EFFECT WERE NOT CHECKED FOR IT\nLINT: NO FINDINGS\n", report);
}

test "a definition that takes from the return stack what it did not put there is found" {
    try support.skipWithout(&.{ .debug, .files, .help });
    var output = Output{};
    const lint = try std.testing.allocator.create(forth.Lint);
    defer std.testing.allocator.destroy(lint);

    try std.testing.expectEqualStrings(
        \\a.txt:1: RETURN STACK: POPPER takes a cell from the return stack that it did not put there
        \\LINT: 1 FINDINGS
        \\
    , try findings(
        \\: POPPER ( -- n ) R> ;
        \\: FINE ( n -- n ) >R R> ;
        \\' POPPER DROP ' FINE DROP
        \\
    , &output, lint));
}

test "words that move a number of cells that is not fixed are not counted" {
    try support.skipWithout(&.{ .debug, .files, .help });
    var output = Output{};
    const lint = try std.testing.allocator.create(forth.Lint);
    defer std.testing.allocator.destroy(lint);

    // N>R and NR> are ( x1 .. xn n -- ) in their HELP texts.
    try std.testing.expectEqualStrings("LINT: 1 DEFINITIONS WITHOUT A FIXED STACK EFFECT WERE NOT CHECKED FOR IT\nLINT: NO FINDINGS\n", try findings(
        \\: SAVEONE ( n -- n ) 1 N>R NR> DROP ;
        \\' SAVEONE DROP
        \\
    , &output, lint));
}

test "a word that takes the place of a removed one has its own stack comment" {
    try support.skipWithout(&.{ .debug, .files, .help });
    var output = Output{};
    const lint = try std.testing.allocator.create(forth.Lint);
    defer std.testing.allocator.destroy(lint);

    try std.testing.expectEqualStrings("LINT: NO FINDINGS\n", try findings(
        \\: OLD ( -- n ) 1 ;
        \\FORGET OLD
        \\: NEW ( -- ) ;
        \\' NEW DROP
        \\
    , &output, lint));
}
