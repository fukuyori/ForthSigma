//! Tests of the interpreter, the compiler, and the core words.

const std = @import("std");
const forth = @import("../forth.zig");
const support = @import("support.zig");
const Output = support.Output;
const createMachine = support.createMachine;
const interpretLiteralDefinition = support.interpretLiteralDefinition;
const destroyMachine = support.destroyMachine;
const expectStack = support.expectStack;
const expectOutput = support.expectOutput;

test "64-bit arithmetic wraps and division floors toward negative infinity" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("9223372036854775807 1 + -7 3 /MOD -7 2 / -7 2 MOD 7 -2 MOD");

    const expected = [_]forth.Cell{ std.math.minInt(forth.Cell), 2, -3, -4, 1, -1 };
    try expectStack(machine, &expected);
}

test "true flags are all bits set and zero remains false" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("1 1 = 0 0= AND 0 1 = OR 1 2 < 2 1 < NOT TRUE FALSE");

    const expected = [_]forth.Cell{ -1, -1, -1, -1, 0 };
    try expectStack(machine, &expected);
}

test "dictionary uses case-insensitive full-name identity" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine(": ABCDE1 1 ; : ABCDE2 2 ; abcde1 abcde2");

    const expected = [_]forth.Cell{ 1, 2 };
    try expectStack(machine, &expected);
}

test "compiled nested loops and outer indices produce expected result" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine(": TOTAL 0 3 0 DO 2 0 DO I J + + LOOP LOOP ; TOTAL");

    const expected = [_]forth.Cell{9};
    try expectStack(machine, &expected);
}

test "q-do skips an empty range and do enters an equal range once" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine(": SKIP 0 5 5 ?DO 1 + LOOP ; : ONCE 0 5 5 DO 1 + LOOP ; SKIP ONCE");

    const expected = [_]forth.Cell{ 0, 1 };
    try expectStack(machine, &expected);
}

test "variable array and string operations use the portable data area" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("VARIABLE V 123 V ! V @ 2 ARRAY A 42 1 A A! 1 A A@ : MESSAGE \" OK\" TYPE ; MESSAGE");

    const expected = [_]forth.Cell{ 123, 42 };
    try expectStack(machine, &expected);
    try std.testing.expectEqualStrings("OK", output.written());
}

test "number output is followed by a space and CR emits a newline" {
    try expectOutput("3 . -3 . CR", "3 -3 \n");
}

test "number output uses signed digits without zero padding in every base" {
    try expectOutput("HEX FF . -1 . 10 U. DECIMAL -1 U. 8 OCT . DECIMAL 300 C.", "FF -1 10 18446744073709551615 10 44 ");
}

test "dot-s shows depth and items without consuming them" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("1 -2 3 .S");

    try std.testing.expectEqualStrings("<3> 1 -2 3 ", output.written());
    const expected = [_]forth.Cell{ 1, -2, 3 };
    try expectStack(machine, &expected);
}

test "error reporting resets the stack and reports the unknown token" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    machine.interpretLine("1 MISSING") catch |err| machine.report(err);

    try expectStack(machine, &.{});
    try std.testing.expectEqualStrings("MISSING ?\n", output.written());
}

test "forget removes later words and reclaims their data allocation" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine(": KEEP 11 ; 2 ARRAY RECLAIM FORGET RECLAIM HERE KEEP");

    const expected = [_]forth.Cell{ 0x4000, 11 };
    try expectStack(machine, &expected);
    try std.testing.expectEqual(@as(forth.Cell, 0x4000), machine.data_here);

    const missing = machine.interpretLine("RECLAIM");
    try std.testing.expectError(error.UnknownWord, missing);
    machine.report(error.UnknownWord);
    try std.testing.expectEqualStrings("RECLAIM ?\n", output.written());
}

test "forget reclaims compiled code for later definitions" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine(": KEEP 11 ; : REMOVE 22 ; FORGET REMOVE KEEP");
    const before_redefinition = [_]forth.Cell{11};
    try expectStack(machine, &before_redefinition);

    try machine.interpretLine(": REMOVE 33 ; REMOVE");
    const expected = [_]forth.Cell{ 11, 33 };
    try expectStack(machine, &expected);
}

test "failed definition is rolled back and the interpreter recovers" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    const initial_words = machine.word_count;
    const initial_code = machine.code_count;

    const invalid = machine.interpretLine(": BROKEN 1 MISSING");
    try std.testing.expectError(error.UnknownWord, invalid);
    machine.report(error.UnknownWord);
    try std.testing.expectEqual(initial_words, machine.word_count);
    try std.testing.expectEqual(initial_code, machine.code_count);

    try machine.interpretLine(": GOOD 9 ; GOOD");
    const expected = [_]forth.Cell{9};
    try expectStack(machine, &expected);
}

test "data allocation stops at the start of the heap without moving the allocation pointer" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("1032192 ALLOT HERE");
    const expected = [_]forth.Cell{forth.data_limit};
    try expectStack(machine, &expected);
    try std.testing.expectEqual(@as(forth.Cell, forth.data_limit), machine.data_here);

    const overflow = machine.interpretLine("1 ALLOT");
    try std.testing.expectError(error.MemoryExhausted, overflow);
    machine.report(error.MemoryExhausted);
    try std.testing.expectEqual(@as(forth.Cell, forth.data_limit), machine.data_here);
}

test "cell access is 64-bit little-endian and rejects addresses outside logical memory" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("-2 2097144 ! 2097144 @ 2097144 C@ 2097151 C@");
    const expected = [_]forth.Cell{ -2, 0xfe, 0xff };
    try expectStack(machine, &expected);

    try std.testing.expectError(error.InvalidAddress, machine.interpretLine("2097145 @"));
    machine.report(error.InvalidAddress);
    try std.testing.expectError(error.InvalidAddress, machine.interpretLine("-1 C@"));
    machine.report(error.InvalidAddress);
    try std.testing.expectEqualStrings("INVALID MEMORY ADDRESS !\nINVALID MEMORY ADDRESS !\n", output.written());
}

test "division by zero is reported as an error" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try std.testing.expectError(error.DivisionByZero, machine.interpretLine("7 0 /"));
    machine.report(error.DivisionByZero);
    try std.testing.expectError(error.DivisionByZero, machine.interpretLine("7 0 MOD"));
    machine.report(error.DivisionByZero);
    try std.testing.expectError(error.DivisionByZero, machine.interpretLine("7 0 /MOD"));
    machine.report(error.DivisionByZero);
    try expectStack(machine, &.{});
    try std.testing.expectEqualStrings("DIVISION BY ZERO !\nDIVISION BY ZERO !\nDIVISION BY ZERO !\n", output.written());
}

test "C\" ABORT\" BUFFER: 2LITERAL 2VALUE and the double-cell words work as in gforth" {
    try expectOutput(": T1 C\" hello\" ; T1 COUNT TYPE T1 C@ . : T2 C\" \" ; T2 C@ .", "hello5 0 ");
    try expectOutput(": CHK ABORT\" bad value\" ; 0 CHK .\" after0\" : T3 1 ABORT\" first\" ; ' T3 CATCH . : T4 0 ABORT\" never\" 5 ; T4 .", "after0-2 5 ");
    try expectOutput("16 BUFFER: BUF BUF 16 ERASE 7 BUF C! BUF C@ . HERE BUF - . : T5 [ 12345678901234567890. ] 2LITERAL ; T5 D.", "7 16 12345678901234567890 ");
    try expectOutput(
        "CHAR | EMIT 12345. 10 D.R CHAR | EMIT -12345. 10 D.R CHAR | EMIT 123456789012. 3 D.R CHAR | EMIT 12345. -3 D.R CHAR | EMIT 0. 0 D.R CHAR | EMIT",
        "|     12345|    -12345|123456789012|12345|0|",
    );
    try expectOutput("5. D2* D. -5. D2* D. -5. D2/ D. 5. D2/ D. -1. D2/ D. 1. 2. DMAX D. -1. 2. DMIN D. 5. 7 M+ D. -5. -7 M+ D.", "10 -10 -3 2 -1 2 -1 12 -12 ");
    try expectOutput("1. 2. DU< . -1. 1. DU< . 1. -1. DU< . 1. 2. 3. 2ROT D. D. D.", "-1 0 -1 1 3 2 ");
    try expectOutput("5. 2VALUE DV DV D. 7. TO DV DV D. : T6 9. TO DV ; T6 DV D. SEE DV SEE T6", "5 7 9 9. 2VALUE DV\n: T6\n  9 0 TO DV\n;\n");

    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    // Without CATCH, ABORT" shows its text, as gforth does.
    try std.testing.expectError(error.Thrown, machine.interpretLine(": CHK ABORT\" bad value\" ; 1 CHK 2"));
    machine.report(error.Thrown);
    try std.testing.expectEqualStrings("bad value\n", output.written());
    try std.testing.expectError(error.CompileOnly, machine.interpretLine("C\" x\""));
    try std.testing.expectError(error.CompileOnly, machine.interpretLine("1 ABORT\" x\""));
    output.len = 0;
    try machine.interpretLine(": T C\" ab\" ABORT\" msg\" ; SEE T");
    try std.testing.expectEqualStrings(": T\n  C\" ab\" ABORT\" msg\"\n;\n", output.written());
}

test "DUMP shows 16 bytes a line in hexadecimal and as characters, as gforth does" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    const here: usize = @intCast(machine.data_here);
    try machine.interpretLine("CREATE DD 40 ALLOT DD 40 ERASE S\" AB\" DD SWAP MOVE 1 DD 2 + C! 127 DD 3 + C! 200 DD 4 + C! 32 DD 5 + C! 126 DD 6 + C! DD 20 DUMP DD 0 DUMP DD 3 DUMP");
    var expected: [512]u8 = undefined;
    const text = try std.fmt.bufPrint(&expected, "\n{X}: 41 42 01 7F  C8 20 7E 00 - 00 00 00 00  00 00 00 00  AB... ~.........\n" ++
        "{X}: 00 00 00 00              -                           ....\n\n\n{X}: 41 42 01                 -                           AB.\n", .{ here, here + 16, here });
    try std.testing.expectEqualStrings(text, output.written());
}

test "WHILE follows the standard control-flow order, so CS-ROLL idioms and several WHILEs work" {
    try expectOutput(": MYWHILE POSTPONE IF 1 CS-ROLL ; IMMEDIATE : T2 0 BEGIN DUP 3 < MYWHILE 1+ REPEAT . ; T2", "3 ");
    try expectOutput(": T8 0 BEGIN DUP 10 < WHILE DUP 5 <> WHILE 1+ REPEAT .\" five\" THEN . ; T8", "five5 ");
    try expectOutput(": T9 0 BEGIN 1+ DUP 3 < WHILE DUP 7 = UNTIL .\" seven\" THEN . ; T9", "3 ");
    try expectOutput(": T7 0 BEGIN [ 0 CS-PICK ] 1+ DUP 3 > UNTIL . EXIT AGAIN ; T7", "4 ");

    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    try std.testing.expectError(error.ControlMismatch, machine.interpretLine(": BAD [ 5 CS-ROLL ] ;"));
}

test "SYNONYM TRAVERSE-WORDLIST NAME>INTERPRET EKEY>CHAR and ENVIRONMENT? work as in gforth" {
    try expectOutput(": SQ DUP * ; SYNONYM SQUARE SQ 5 SQUARE . VARIABLE V SYNONYM W V 7 W ! V @ .", "25 7 ");
    try expectOutput(": IM .\" immediate!\" ; IMMEDIATE SYNONYM IM2 IM : T IM2 ; 5 VALUE VV SYNONYM VV2 VV 9 TO VV2 VV .", "immediate!9 ");
    try expectOutput(
        "WORDLIST CONSTANT WL GET-CURRENT WL SET-CURRENT : AAA ; : BBB ; : CCC ; SET-CURRENT " ++
            ": SHOW NAME>STRING TYPE SPACE TRUE ; ' SHOW WL TRAVERSE-WORDLIST : FIRST NAME>STRING TYPE SPACE FALSE ; ' FIRST WL TRAVERSE-WORDLIST",
        "CCC BBB AAA CCC ",
    );
    try expectOutput("S\" DUP\" FIND-NAME NAME>INTERPRET S\" DUP\" FIND-NAME NAME>INT = . 65 EKEY>CHAR . . 300 EKEY>CHAR . .", "-1 -1 65 0 300 ");
    try expectOutput(
        "S\" NOSUCH\" ENVIRONMENT? . S\" ADDRESS-UNIT-BITS\" ENVIRONMENT? . . S\" floored\" ENVIRONMENT? . . S\" MAX-CHAR\" ENVIRONMENT? . . S\" MAX-N\" ENVIRONMENT? . . S\" MAX-U\" ENVIRONMENT? . . S\" MAX-D\" ENVIRONMENT? . D.",
        "0 -1 8 -1 -1 -1 255 -1 9223372036854775807 -1 -1 -1 170141183460469231731687303715884105727 ",
    );
    // The sizes are this system's.
    try expectOutput("S\" /HOLD\" ENVIRONMENT? . . S\" /PAD\" ENVIRONMENT? . . S\" STACK-CELLS\" ENVIRONMENT? . . S\" WORDLISTS\" ENVIRONMENT? . .", "-1 4096 -1 4096 -1 1024 -1 64 ");
    try expectOutput(": SQ DUP * ; SYNONYM SQUARE SQ SEE SQUARE 3 ' SQUARE EXECUTE .", "SYNONYM SQUARE SQ\n9 ");
}

test "QUIT keeps both data stacks, stops the line and the file, and CATCH does not stop it" {
    var output = Output{};
    support.setFakeFile(&output, 0, ": TQ 1 2 QUIT 3 ; TQ .S\n4 .\n");
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try std.testing.expectError(error.Quit, machine.interpretLine("1.5E 1 2 : T 3 QUIT 4 . ; T 99 ."));
    machine.report(error.Quit);
    try expectStack(machine, &.{ 1, 2, 3 });
    try std.testing.expectEqual(@as(usize, 1), machine.float_depth);
    machine.data_depth = 0;
    try std.testing.expectError(error.Quit, machine.interpretLine(": U 5 QUIT ; : V 1 ['] U CATCH ; V"));
    machine.report(error.Quit);
    try expectStack(machine, &.{ 1, 5 });
    machine.data_depth = 0;
    try std.testing.expectError(error.Quit, machine.interpretLine("INCLUDE a.txt"));
    machine.report(error.Quit);
    try expectStack(machine, &.{ 1, 2 });
    try std.testing.expectEqualStrings("", output.written());
}

test "M*/ works as in gforth" {
    try expectOutput("10. 3 4 M*/ D. -10. 3 4 M*/ D. 10. -3 4 M*/ D. -10. -3 4 M*/ D. 7. 1 2 M*/ D. -7. 1 2 M*/ D.", "7 -8 -8 7 3 -4 ");
    // The product has three cells, so this does not overflow before the division.
    try expectOutput("170141183460469231731687303715884105727. 2 3 M*/ D.", "113427455640312821154458202477256070484 ");
    // As in gforth, a quotient too big for two cells wraps and the divisor is unsigned.
    try expectOutput("170141183460469231731687303715884105727. 3 2 M*/ D. 1. 1 -2 M*/ D. -1. 1 -2 M*/ D.", "-85070591730234615865843651857942052866 0 -1 ");

    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    try std.testing.expectError(error.DivisionByZero, machine.interpretLine("1. 1 0 M*/"));
}

test "AHEAD N>R and NR> work as in gforth" {
    try expectOutput(": T1 AHEAD 111 . THEN 222 . ; T1 : T2 1 2 3 3 N>R 99 . NR> . . . . ; T2 : T3 0 N>R NR> . ; T3", "222 99 3 3 2 1 0 ");

    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    try std.testing.expectError(error.CompileOnly, machine.interpretLine("AHEAD"));
    machine.report(error.CompileOnly);
    try std.testing.expectError(error.StackUnderflow, machine.interpretLine("1 2 5 N>R"));
    machine.report(error.StackUnderflow);
    try std.testing.expectError(error.ReturnStackUnderflow, machine.interpretLine("NR>"));
}

test "?DUP U< U> 2R@ ALIGN UNUSED .R and U.R work as in gforth" {
    try expectOutput("5 ?DUP . . 0 ?DUP . DEPTH .", "5 5 0 0 ");
    try expectOutput("1 2 U< . -1 1 U< . 1 -1 U< . 2 2 U< . 1 2 U> . -1 1 U> .", "-1 0 -1 0 0 -1 ");
    try expectOutput(": T2 1 2 2>R 2R@ 2R> ; T2 . . . .", "2 1 2 1 ");
    try expectOutput("HERE 1 ALLOT ALIGN HERE SWAP - . HERE ALIGN HERE SWAP - . UNUSED 0> .", "8 0 -1 ");
    try expectOutput(
        "CHAR | EMIT 42 5 .R CHAR | EMIT -42 5 .R CHAR | EMIT 123456 3 .R CHAR | EMIT 7 0 .R CHAR | EMIT 7 -3 .R CHAR | EMIT " ++
            "42 5 U.R CHAR | EMIT -1 3 U.R CHAR | EMIT 7 -9223372036854775808 .R CHAR | EMIT HEX 255 6 .R",
        "|   42|  -42|123456|7|7|   42|18446744073709551615|7|   255",
    );

    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    try std.testing.expectError(error.ReturnStackUnderflow, machine.interpretLine("1 >R 2R@"));
    machine.report(error.ReturnStackUnderflow);
    // UNUSED is what is left of the data space.
    try machine.interpretLine("UNUSED HERE + UNUSED 1000 ALLOT UNUSED - ");
    try expectStack(machine, &.{ forth.data_limit, 1000 });
}

test "*/ */MOD M* UM* UM/MOD FM/MOD and SM/REM work as in gforth" {
    try expectOutput("10 3 4 */ . -10 3 4 */ . 10 -3 4 */ . 7 2 -3 */ . 10 3 4 */MOD . . -10 3 4 */MOD . .", "7 -8 -8 -5 7 2 -8 2 ");
    // The product of */ is a double cell, so it does not overflow before the division.
    try expectOutput("9223372036854775807 2 3 */ .", "6148914691236517204 ");
    try expectOutput(
        "3 -4 M* . . -1 -1 UM* . . 9223372036854775807 9223372036854775807 M* D. 9223372036854775807 -9223372036854775808 M* D.",
        "-1 -12 -2 1 85070591730234615847396907784232501249 -85070591730234615856620279821087277056 ",
    );
    try expectOutput("7 0 1 UM/MOD . . -1 1 2 UM/MOD . .", "7 0 -1 1 ");
    try expectOutput(
        "-7 S>D 2 FM/MOD . . -7 S>D 2 SM/REM . . 7 S>D -2 FM/MOD . . 7 S>D -2 SM/REM . . 5 S>D -5 FM/MOD . . 0 S>D 3 FM/MOD . .",
        "-4 1 -3 -1 -4 -1 -3 1 -1 0 0 0 ",
    );

    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    const zero = [_][]const u8{ "1 2 0 */", "1 2 0 */MOD", "1 0 0 UM/MOD", "1 S>D 0 FM/MOD", "1 S>D 0 SM/REM" };
    for (zero) |line| try std.testing.expectError(error.DivisionByZero, machine.interpretLine(line));
    // A quotient that does not fit in a cell is an error, as in gforth (also for MOD).
    const out_of_range = [_][]const u8{
        "9223372036854775807 9223372036854775807 1 */",
        "0 5 5 UM/MOD",
        "-9223372036854775808 S>D -1 SM/REM",
        "-9223372036854775808 S>D -1 FM/MOD",
        "-9223372036854775808 -1 1 */",
        "-9223372036854775808 1 -1 */",
        "-9223372036854775808 -1 /",
        "-9223372036854775808 -1 MOD",
        "-9223372036854775808 -1 /MOD",
    };
    for (out_of_range) |line| try std.testing.expectError(error.ResultOutOfRange, machine.interpretLine(line));
    machine.data_depth = 0;
    try machine.interpretLine(": T 9223372036854775807 9223372036854775807 1 */ ; ' T CATCH");
    try expectStack(machine, &.{-11});
    machine.report(error.ResultOutOfRange);
    try std.testing.expectEqualStrings("RESULT OUT OF RANGE !\n", output.written());
}

test "stack overflow is reported and subsequent input can run" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    var input: [2050]u8 = undefined;
    for (0..1024) |index| {
        input[index * 2] = '0';
        input[index * 2 + 1] = ' ';
    }
    input[2048] = '0';
    input[2049] = ' ';

    const overflow = machine.interpretLine(&input);
    try std.testing.expectError(error.StackOverflow, overflow);
    machine.report(error.StackOverflow);
    try expectStack(machine, &.{});

    try machine.interpretLine("2 3 +");
    const expected = [_]forth.Cell{5};
    try expectStack(machine, &expected);
}

test "return stack overflow and underflow reset cleanly" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    for (0..1024) |_| try machine.interpretLine("0 >R");
    try std.testing.expectEqual(@as(usize, 1024), machine.return_depth);
    const overflow = machine.interpretLine("0 >R");
    try std.testing.expectError(error.ReturnStackOverflow, overflow);
    machine.report(error.ReturnStackOverflow);
    try std.testing.expectEqual(@as(usize, 0), machine.return_depth);
    try expectStack(machine, &.{});

    const underflow = machine.interpretLine("R>");
    try std.testing.expectError(error.ReturnStackUnderflow, underflow);
    machine.report(error.ReturnStackUnderflow);
    try std.testing.expectEqual(@as(usize, 0), machine.return_depth);
}

test "dictionary capacity failure preserves existing words" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    var definition: [32]u8 = undefined;

    const limit: u16 = @intCast(machine.words.len);
    while (machine.word_count < limit) {
        const text = try std.fmt.bufPrint(&definition, ": W{d} 1 ;", .{machine.word_count});
        try machine.interpretLine(text);
    }
    try std.testing.expectEqual(limit, machine.word_count);

    const overflow = machine.interpretLine(": EXTRA 2 ;");
    try std.testing.expectError(error.DictionaryFull, overflow);
    machine.report(error.DictionaryFull);
    try std.testing.expectEqual(limit, machine.word_count);
    try machine.interpretLine(try std.fmt.bufPrint(&definition, "W{d}", .{limit - 1}));
    const expected = [_]forth.Cell{1};
    try expectStack(machine, &expected);
}

test "control nesting overflow rolls back the incomplete definition" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    const initial_words = machine.word_count;
    const initial_code = machine.code_count;
    var input: [400]u8 = undefined;
    var used: usize = 0;
    const prefix = ": TOO-DEEP ";
    @memcpy(input[used .. used + prefix.len], prefix);
    used += prefix.len;
    for (0..129) |_| {
        @memcpy(input[used .. used + 3], "IF ");
        used += 3;
    }

    const overflow = machine.interpretLine(input[0..used]);
    try std.testing.expectError(error.ControlStackOverflow, overflow);
    machine.report(error.ControlStackOverflow);
    try std.testing.expectEqualStrings("NESTING ERROR !\n", output.written());
    try std.testing.expectEqual(initial_words, machine.word_count);
    try std.testing.expectEqual(initial_code, machine.code_count);
}

test "compiled code capacity failure rolls back the incomplete definition" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    const initial_words = machine.word_count;
    const initial_code = machine.code_count;
    const overflow = interpretLiteralDefinition(machine, ": TOO-LONG", machine.code.len);
    try std.testing.expectError(error.CodeFull, overflow);
    machine.report(error.CodeFull);
    try std.testing.expectEqual(initial_words, machine.word_count);
    try std.testing.expectEqual(initial_code, machine.code_count);
}

test "nested IF ELSE THEN selects every branch" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine(": SELECT DUP 0= IF DROP 10 ELSE DUP 1 = IF DROP 20 ELSE DROP 30 THEN THEN ; 0 SELECT 1 SELECT 2 SELECT");

    const expected = [_]forth.Cell{ 10, 20, 30 };
    try expectStack(machine, &expected);
}

test "BEGIN WHILE REPEAT and BEGIN END compile and run" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine(": COUNT-UP 0 BEGIN DUP 3 < WHILE 1 + REPEAT ;");
    try machine.interpretLine(": COUNT-TO 0 BEGIN 1 + DUP 3 = END ;");
    try machine.interpretLine("COUNT-UP COUNT-TO");

    const expected = [_]forth.Cell{ 3, 3 };
    try expectStack(machine, &expected);
}

test "+LOOP handles positive and negative increments at the boundary" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine(": COUNT-UP 0 5 0 DO 1 + 2 +LOOP ; : COUNT-DOWN 0 0 3 DO 1 + -1 +LOOP ; COUNT-UP COUNT-DOWN");

    const expected = [_]forth.Cell{ 3, 4 };
    try expectStack(machine, &expected);
}

test "+LOOP ends when the index crosses the limit also across the largest cell, as in gforth" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine(": UP 9223372036854775807 9223372036854775806 DO I 2 +LOOP ; : DOWN -9223372036854775808 -9223372036854775807 DO I -2 +LOOP ; UP DOWN");
    try machine.interpretLine(": EDGE 0 1 DO I -1 +LOOP ; EDGE");
    // A step of 0 does not end the loop; LEAVE does.
    try machine.interpretLine("VARIABLE N 0 N ! : STILL 5 0 DO I N @ 1+ DUP N ! 3 = IF LEAVE THEN 0 +LOOP ; STILL");
    try expectStack(machine, &.{ 9223372036854775806, -9223372036854775807, 1, 0, 0, 0, 0 });
    machine.data_depth = 0;
    try machine.interpretLine("9223372036854775807 9223372036854775806 [DO] [I] 2 [+LOOP] -9223372036854775808 -9223372036854775807 [DO] [I] -2 [+LOOP] 0 1 [DO] [I] -1 [+LOOP]");
    try expectStack(machine, &.{ 9223372036854775806, -9223372036854775807, 1, 0 });
}

test "LEAVE exits the active loop without losing the outer result" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine(": SUM-UNTIL-FIVE 0 10 0 DO I 5 = IF LEAVE ELSE I + THEN LOOP ; SUM-UNTIL-FIVE");

    const expected = [_]forth.Cell{10};
    try expectStack(machine, &expected);
}

test "multiline definitions and immediate string output preserve compiler state" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine(": GREET");
    try machine.interpretLine("\" HELLO\" TYPE ;");
    try machine.interpretLine("GREET : SAY .\" SIGMA\" ; SAY");

    try std.testing.expectEqualStrings("HELLOSIGMA", output.written());
}

test "quoted string length is limited to 127 bytes" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    var input: [256]u8 = undefined;
    var used: usize = 0;
    const prefix = ": TEXT \" ";
    @memcpy(input[used .. used + prefix.len], prefix);
    used += prefix.len;
    @memset(input[used .. used + 127], 'X');
    used += 127;
    const suffix = "\" TYPE ; TEXT";
    @memcpy(input[used .. used + suffix.len], suffix);
    used += suffix.len;
    try machine.interpretLine(input[0..used]);
    try std.testing.expectEqual(@as(usize, 127), output.len);
    try std.testing.expect(std.mem.allEqual(u8, output.written(), 'X'));

    var oversized: [256]u8 = undefined;
    var oversized_len: usize = 0;
    const oversized_prefix = ": TOO-LONG \" ";
    @memcpy(oversized[oversized_len .. oversized_len + oversized_prefix.len], oversized_prefix);
    oversized_len += oversized_prefix.len;
    @memset(oversized[oversized_len .. oversized_len + 128], 'Y');
    oversized_len += 128;
    oversized[oversized_len] = '"';
    oversized_len += 1;

    const too_long = machine.interpretLine(oversized[0..oversized_len]);
    try std.testing.expectError(error.MemoryExhausted, too_long);
    machine.report(error.MemoryExhausted);
    try std.testing.expectEqual(@as(forth.Cell, 0x4000 + 128), machine.data_here);
}

test "redefinition warns and subsequent lookup uses the newest definition" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine(": TWICE 1 ; : TWICE 2 ; TWICE");

    const expected = [_]forth.Cell{2};
    try expectStack(machine, &expected);
    try std.testing.expectEqualStrings("WARNING: SAME NAME WORD EXISTS\n", output.written());
}

test "<BUILDS and DOES> attach a compiled behavior to created words" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine(": CELL <BUILDS , DOES> @ ; 42 CELL ANSWER 43 CELL OTHER ANSWER OTHER");

    const expected = [_]forth.Cell{ 42, 43 };
    try expectStack(machine, &expected);
    try std.testing.expectEqual(@as(forth.Cell, forth.data_start + 16), machine.data_here);
}

test "<BUILDS reads a created word name from the next input line" {
    var output = Output{};
    output.input_lines[0] = "ACROSS-LINE";
    output.input_count = 1;
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine(": CELL <BUILDS , DOES> @ ;");
    try machine.interpretLine("73 CELL");
    try machine.interpretLine("ACROSS-LINE");

    const expected = [_]forth.Cell{73};
    try expectStack(machine, &expected);
}

test "FORGET removes created words and their data can be reused" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine(": CELL <BUILDS , DOES> @ ; 42 CELL FIRST 43 CELL SECOND FORGET SECOND 44 CELL THIRD FIRST THIRD");

    const expected = [_]forth.Cell{ 42, 44 };
    try expectStack(machine, &expected);
    try std.testing.expectEqual(@as(forth.Cell, forth.data_start + 16), machine.data_here);
}

test "LEAVE exits immediately and UNLOOP allows EXIT from a loop" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine(": STOP-AT-3 0 10 0 DO I 3 = IF LEAVE THEN 1+ LOOP ;");
    try machine.interpretLine(": FIND-4 10 0 DO I 4 = IF I UNLOOP EXIT THEN LOOP -1 ;");
    try machine.interpretLine("STOP-AT-3 FIND-4");

    const expected = [_]forth.Cell{ 3, 4 };
    try expectStack(machine, &expected);
    try std.testing.expectEqual(@as(usize, 0), machine.loop_depth);
}

test "stack words follow the standard stack effects" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("1 2 3 -ROT NIP 4 TUCK 2DUP 2DROP DEPTH 9 8 7 2 PICK 3 ROLL 5 >R R@ R> 2SWAP 2OVER");

    const expected = [_]forth.Cell{ 3, 4, 2, 4, 4, 8, 7, 5, 5, 9, 9, 5, 5 };
    try expectStack(machine, &expected);
}

test "basic standard words cover bit shifts, cells, characters, and number prefixes" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("1 4 LSHIFT -1 60 RSHIFT 3 CELLS 0 CELL+ 9 ALIGNED BL CHAR A : Z [CHAR] Z ; Z $FF #10 %101 'a' -7 2/ 1 \\ 2 3");

    const expected = [_]forth.Cell{ 16, 15, 24, 8, 16, 32, 65, 90, 255, 10, 5, 97, -4, 1 };
    try expectStack(machine, &expected);
}

test "memory words fill, erase, move, and switch flags on and off" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("CREATE BUF 16 ALLOT BUF 4 65 FILL BUF BUF 1+ 3 MOVE BUF 3 + 1 ERASE BUF 4 TYPE VARIABLE F F ON F @ F OFF F @");

    const expected = [_]forth.Cell{ -1, 0 };
    try expectStack(machine, &expected);
    try std.testing.expectEqualStrings("AAA\x00", output.written());
}

test "UNTIL AGAIN EXIT and RECURSE compile structured definitions" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine(": U 0 BEGIN 1+ DUP 3 = UNTIL ; : A 0 BEGIN 1+ DUP 5 = IF EXIT THEN AGAIN ;");
    try machine.interpretLine(": FACT DUP 1 > IF DUP 1- RECURSE * THEN ; U A 20 FACT");

    const expected = [_]forth.Cell{ 3, 5, 2432902008176640000 };
    try expectStack(machine, &expected);
}

test "CASE OF ENDOF ENDCASE selects a branch and drops the selector" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine(": PICK-ONE CASE 1 OF 10 ENDOF 2 OF 20 ENDOF 99 SWAP ENDCASE ; 1 PICK-ONE 2 PICK-ONE 3 PICK-ONE");

    const expected = [_]forth.Cell{ 10, 20, 99 };
    try expectStack(machine, &expected);
}

test "VALUE and TO work interpreted and compiled" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("5 VALUE X X 7 TO X X : SETX TO X ; 9 SETX X");

    const expected = [_]forth.Cell{ 5, 7, 9 };
    try expectStack(machine, &expected);
}

test "IMMEDIATE and POSTPONE extend the compiler" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine(": MY-IF POSTPONE IF ; IMMEDIATE : SIGNED MY-IF 1 ELSE 2 THEN ; -1 SIGNED 0 SIGNED");
    try machine.interpretLine(": FIVE 5 ; : COMPILE-FIVE POSTPONE FIVE ; IMMEDIATE : USE-FIVE COMPILE-FIVE ; USE-FIVE");

    const expected = [_]forth.Cell{ 1, 2, 5 };
    try expectStack(machine, &expected);
}

test "compile-only words are rejected while interpreting" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try std.testing.expectError(error.CompileOnly, machine.interpretLine("1 IF"));
    machine.report(error.CompileOnly);
    try std.testing.expectError(error.CompileOnly, machine.interpretLine("EXIT"));
    machine.report(error.CompileOnly);
    try std.testing.expectError(error.CompileOnly, machine.interpretLine("LEAVE"));
    machine.report(error.CompileOnly);
}
