//! Tests of double-cell numbers, pictured output, strings, and terminal input.

const std = @import("std");
const forth = @import("../forth.zig");
const support = @import("support.zig");
const Output = support.Output;
const createMachine = support.createMachine;
const destroyMachine = support.destroyMachine;
const expectStack = support.expectStack;
const expectFloatStack = support.expectFloatStack;
const expectOutput = support.expectOutput;

test "numbers containing a dot are double-cell integers" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("123. -5. 12345.123 #10. $FF.");

    const expected = [_]forth.Cell{ 123, 0, -5, -1, 12345123, 0, 10, 0, 255, 0 };
    try expectStack(machine, &expected);
}

test "double arithmetic, comparison, and output exceed a single cell" {
    try expectOutput("1234567890000000000. 9876543210000000000. D+ D. -1. D. 5 S>D D. -7 S>D DABS D. 3. DNEGATE D.", "11111111100000000000 -1 5 7 -3 ");
}

test "2! and 2@ store a double with the high cell first" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("CREATE BIGNUM 2 CELLS ALLOT 12345678901234567890 1 BIGNUM 2! BIGNUM 2@ D. BIGNUM @");
    try machine.interpretLine("2VARIABLE DV 7. DV 2! DV 2@ 42. 2CONSTANT ANSWER ANSWER D0= 0. D0= 1. 2. D< 3. 3. D= -1. D0< 9. D>S");

    try std.testing.expectEqualStrings("30792422974944119506 ", output.written());
    const expected = [_]forth.Cell{ 1, 7, 0, 0, -1, -1, -1, -1, 9 };
    try expectStack(machine, &expected);
}

test "pictured numeric output builds strings from the right" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine(": MY-U. 0 <<# #S #> TYPE SPACE #>> ;");
    try machine.interpretLine(": DOLLARS 0 <<# # # [CHAR] . HOLD #S [CHAR] $ HOLD #> TYPE SPACE #>> ;");
    try machine.interpretLine(": MY-. S>D SWAP OVER DABS <<# #S ROT SIGN #> TYPE SPACE #>> ;");
    try machine.interpretLine("123 MY-U. 1234 DOLLARS 5 DOLLARS -123 MY-. 456 MY-. 255 HEX MY-U. DECIMAL");
    try machine.interpretLine("<# 7 0 # # S\" ab\" HOLDS #> TYPE");

    try std.testing.expectEqualStrings("123 $12.34 $0.05 -123 456 FF ab07", output.written());
    try std.testing.expectEqual(@as(usize, 0), machine.data_depth);
}

test "nested hold areas keep the outer conversion" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("<<# 12 0 #S <<# 34 0 #S #> TYPE #>> #> TYPE #>>");

    try std.testing.expectEqualStrings("3412", output.written());
    try std.testing.expectError(error.PicturedNumericOverflow, machine.interpretLine("#>>"));
    machine.report(error.PicturedNumericOverflow);
}

test "S\" and S\\\" return strings while interpreting and compiling" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("S\" Hello, Forth!\" TYPE CR : GREET S\" compiled\" TYPE ; GREET CR");
    try machine.interpretLine("S\\\" a\\tb\\x41\\\"q\" TYPE .\\\" x\\ny\" : SAY .\\\" [\\q]\" ; SAY .( paren) CR");
    try machine.interpretLine("CREATE BUF 20 ALLOT S\" Forth\" TUCK BUF SWAP MOVE BUF SWAP TYPE");

    try std.testing.expectEqualStrings("Hello, Forth!\ncompiled\na\tbA\"qx\ny[\"]paren\nForth", output.written());
}

test "S\" keeps several interpreted strings alive" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("S\" one\" S\" two\" S\" three\" TYPE TYPE TYPE");

    try std.testing.expectEqualStrings("threetwoone", output.written());
}

test "COUNT and PAD give addressable buffers" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("3 PAD C! 65 PAD 1+ C! 66 PAD 2 + C! 67 PAD 3 + C! PAD COUNT TYPE PAD");

    try std.testing.expectEqualStrings("ABC", output.written());
    const expected = [_]forth.Cell{forth.pad_address};
    try expectStack(machine, &expected);
}

test ">NUMBER S>NUMBER? and >FLOAT convert strings" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("0. S\" 123x\" >NUMBER NIP S\" -42\" S>NUMBER? S\" 3.14\" S>NUMBER? S\" nope\" S>NUMBER?");
    const expected = [_]forth.Cell{ 123, 0, 1, -42, -1, -1, 314, 0, -1, 0, 0, 0 };
    try expectStack(machine, &expected);
}

test ">FLOAT accepts decimal text without an exponent" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("S\" 2.5\" >FLOAT S\" 1e3\" >FLOAT S\" x\" >FLOAT S\"  \" >FLOAT 7. D>F 2.9E F>D");

    const expected = [_]forth.Cell{ -1, -1, 0, -1, 2, 0 };
    try expectStack(machine, &expected);
    const floats = [_]forth.Float{ 2.5, 1000.0, 0.0, 7.0 };
    try expectFloatStack(machine, &floats);
}

test "ACCEPT and EVALUATE read and interpret a line" {
    var output = Output{};
    output.input_lines[0] = "2 3 + 4 *";
    output.input_count = 1;
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("PAD 80 ACCEPT PAD SWAP EVALUATE S\" : SQ DUP * ;\" EVALUATE 5 SQ");

    const expected = [_]forth.Cell{ 20, 25 };
    try expectStack(machine, &expected);
}

test "KEY and KEY? read single characters" {
    var output = Output{};
    output.keys = "hi";
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine(": ECHO-ALL BEGIN KEY? WHILE KEY EMIT REPEAT ; ECHO-ALL KEY?");

    try std.testing.expectEqualStrings("hi", output.written());
    const expected = [_]forth.Cell{0};
    try expectStack(machine, &expected);
}

test "WITHIN tests a half-open range with wrap-around like gforth" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("5 0 10 WITHIN 10 0 10 WITHIN -1 0 10 WITHIN 0 -5 -1 WITHIN 5 5 5 WITHIN 3 10 0 WITHIN 11 10 0 WITHIN");
    try machine.interpretLine("9223372036854775807 9223372036854775807 -9223372036854775808 WITHIN -9223372036854775808 9223372036854775807 -9223372036854775808 WITHIN");

    const expected = [_]forth.Cell{ -1, 0, 0, 0, 0, 0, -1, -1, 0 };
    try expectStack(machine, &expected);
}

test "2>R and 2R> move a cell pair and keep its order" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine(": T 1 2 2>R 3 2R> ; T");
    const expected = [_]forth.Cell{ 3, 1, 2 };
    try expectStack(machine, &expected);

    machine.data_depth = 0;
    try std.testing.expectError(error.StackUnderflow, machine.interpretLine("1 2>R"));
    machine.report(error.StackUnderflow);
    try std.testing.expectEqual(@as(usize, 0), machine.return_depth);
    try std.testing.expectError(error.ReturnStackUnderflow, machine.interpretLine("1 >R 2R>"));
    machine.report(error.ReturnStackUnderflow);
}

test "ENDIF is an alias of THEN" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine(": S 0< IF -1 ELSE 1 ENDIF ; -5 S 5 S");

    const expected = [_]forth.Cell{ -1, 1 };
    try expectStack(machine, &expected);
}

test "PLACE stores a counted string, handles overlap, and limits the length to 255" {
    try expectOutput("S\" hello\" PAD PLACE PAD COUNT TYPE", "hello");
    try expectOutput("S\" abcde\" PAD SWAP MOVE PAD 5 PAD PLACE PAD COUNT TYPE", "abcde");
    try expectOutput("S\" vwxyz\" PAD 10 + SWAP MOVE PAD 10 + 5 PAD 7 + PLACE PAD 7 + COUNT TYPE", "vwxyz");

    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    try machine.interpretLine("PAD 255 PAD 512 + PLACE PAD 512 + C@ PAD 256 PAD 1024 + PLACE PAD 1024 + C@ PAD 0 2097151 PLACE");
    const expected = [_]forth.Cell{ 255, 255 };
    try expectStack(machine, &expected);
    try std.testing.expectError(error.InvalidAddress, machine.interpretLine("PAD 1 2097151 PLACE"));
}

test "COMPARE SEARCH /STRING and -TRAILING work as in gforth" {
    try expectOutput(
        "S\" abc\" S\" abd\" COMPARE . S\" abd\" S\" abc\" COMPARE . S\" abc\" S\" abc\" COMPARE . " ++
            "S\" ab\" S\" abc\" COMPARE . S\" abc\" S\" ab\" COMPARE . S\" \" S\" \" COMPARE . " ++
            "200 PAD C! 65 PAD 1+ C! PAD 1 PAD 1+ 1 COMPARE .",
        "-1 1 0 -1 1 0 1 ",
    );
    try expectOutput(
        "S\" hello world\" S\" wor\" SEARCH . TYPE CR S\" hello world\" S\" xyz\" SEARCH . TYPE CR " ++
            "S\" hello world\" S\" \" SEARCH . TYPE CR S\" \" S\" a\" SEARCH . . DROP CR " ++
            "S\" aaa\" S\" aaaa\" SEARCH . TYPE CR S\" abcabc\" S\" bc\" SEARCH . TYPE",
        "-1 world\n0 hello world\n-1 hello world\n0 0 \n0 aaa\n-1 bcabc",
    );
    try expectOutput(
        "S\" hello\" 2 /STRING TYPE CR S\" hello\" 0 /STRING TYPE CR S\" hello\" 5 /STRING . DROP " ++
            "PAD 5 -1 /STRING SWAP PAD - . . S\" hello\" 7 /STRING . DROP",
        "llo\nhello\n0 -1 6 -2 ",
    );
    try expectOutput(
        "S\" hi   \" -TRAILING TYPE .\" |\" S\" hi\t\" -TRAILING . DROP S\"    \" -TRAILING . DROP " ++
            "S\" \" -TRAILING . DROP PAD -5 -TRAILING . DROP",
        "hi|3 0 0 -5 ",
    );
}

test "a string longer than memory is an error, not cut short" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    // The whole memory, 2097152 bytes from address 0, is still a valid string.
    try machine.interpretLine("0 2097152 0 2097152 STR= 0 2097152 0 2097152 COMPARE");
    try expectStack(machine, &.{ -1, 0 });
    const cases = [_][]const u8{
        "0 2097153 0 2097152 STR=",
        "0 2097153 0 2097152 COMPARE",
        "0 2097153 0 0 SEARCH",
        "0 2097153 -TRAILING",
        "0 2097153 0 SCAN",
        "0 2097153 0 SKIP",
        "0 2097153 S\" a\" STRING-PREFIX?",
        "0 2097153 BLANK",
        "0 2097153 TYPE",
    };
    for (cases) |case| {
        machine.data_depth = 0;
        try std.testing.expectError(error.InvalidAddress, machine.interpretLine(case));
    }
}

test "CHAR+ CHARS BOUNDS BLANK CMOVE> SCAN SKIP STR= STRING-PREFIX? and +PLACE work as in gforth" {
    try expectOutput("5 CHAR+ . 7 CHARS . -3 CHARS . PAD 4 BOUNDS PAD - SWAP PAD - . .", "6 7 -3 4 0 ");
    try expectOutput("PAD 10 ERASE PAD 3 BLANK PAD 4 TYPE .\" |\" PAD 0 BLANK PAD -1 BLANK PAD 3 + C@ .", "   \x00|0 ");
    // CMOVE> copies from the highest byte down, so an overlap below repeats the bytes.
    try expectOutput(
        "S\" abcdef\" PAD SWAP MOVE PAD PAD 2 + 4 CMOVE> PAD 6 TYPE SPACE " ++
            "S\" abcdef\" PAD SWAP MOVE PAD 2 + PAD 4 CMOVE> PAD 6 TYPE PAD PAD 1+ -3 CMOVE>",
        "ababcd efefef",
    );
    try expectOutput(
        "S\" hello world\" BL SCAN TYPE .\" |\" S\" hello\" CHAR z SCAN . DROP S\" hello\" CHAR h SCAN TYPE " ++
            "S\"    hi\" BL SKIP TYPE .\" |\" S\"    \" BL SKIP . DROP S\" a\tb\" BL SCAN . DROP S\" \t x\" BL SKIP . DROP " ++
            "S\" hello\" DROP -1 CHAR l SCAN . DROP",
        " world|0 hellohi|0 0 3 0 ",
    );
    try expectOutput(
        "S\" abc\" S\" abc\" STR= . S\" abc\" S\" abd\" STR= . S\" abc\" S\" ab\" STR= . S\" \" S\" \" STR= . " ++
            "S\" hello\" S\" he\" STRING-PREFIX? . S\" hello\" S\" lo\" STRING-PREFIX? . S\" he\" S\" hello\" STRING-PREFIX? . S\" hello\" S\" \" STRING-PREFIX? .",
        "-1 0 0 -1 -1 0 0 -1 ",
    );
    // +PLACE stops at 255 bytes; a negative length appends nothing.
    try expectOutput(
        "S\" ab\" PAD PLACE S\" cde\" PAD +PLACE PAD COUNT TYPE SPACE S\" xyz\" DROP -2 PAD +PLACE PAD C@ . " ++
            "PAD 1+ 255 ERASE 250 PAD C! S\" 0123456789\" PAD +PLACE PAD C@ . PAD 256 + C@ .",
        "abcde 5 255 0 ",
    );
}

test "SLITERAL compiles a string and PARSE-NAME reads the next name" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine(": T1 [ S\" hi there\" ] SLITERAL ; T1 TYPE : T2 [ S\" \" ] SLITERAL ; T2 . DROP : T3 [ PAD 255 ] SLITERAL NIP ; T3 .");
    try machine.interpretLine(": T4 PARSE-NAME ; T4    word1 TYPE .\" |\" PARSE-NAME \tabc TYPE .\" |\" : T5 PARSE-NAME NIP . ; T5");
    try machine.interpretLine("S\" PARSE-NAME\" EVALUATE NIP .");
    try std.testing.expectEqualStrings("hi there0 255 word1|abc|0 0 ", output.written());
    try std.testing.expectError(error.CompileOnly, machine.interpretLine("S\" x\" SLITERAL"));
    try std.testing.expectError(error.StringTooLong, machine.interpretLine(": T6 [ PAD 256 ] SLITERAL ;"));
}

test "STATE reflects the compiler state through a saved address" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("STATE @ STATE CONSTANT ST : CHECK ST @ ; IMMEDIATE : SAMPLE CHECK [ ST @ ] ; ST @");
    const expected = [_]forth.Cell{ 0, -1, 0, 0 };
    try expectStack(machine, &expected);

    try std.testing.expectError(error.UnknownWord, machine.interpretLine(": BROKEN MISSING"));
    machine.report(error.UnknownWord);
    try machine.interpretLine("ST @");
    try expectStack(machine, &.{0});
}

test "ABORT clears the stacks silently, even from EVALUATE" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try std.testing.expectError(error.Aborted, machine.interpretLine("1 2 ABORT 3"));
    machine.report(error.Aborted);
    try expectStack(machine, &.{});

    try std.testing.expectError(error.Aborted, machine.interpretLine("1E : STOP 1 ABORT 2 ; S\" STOP\" EVALUATE"));
    machine.report(error.Aborted);
    try expectStack(machine, &.{});
    try expectFloatStack(machine, &.{});
    try std.testing.expectEqualStrings("", output.written());
}
