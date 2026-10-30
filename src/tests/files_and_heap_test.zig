//! Tests of the file words, ALLOCATE, and the dynamic strings.

const std = @import("std");
const forth = @import("../forth.zig");
const support = @import("support.zig");
const Output = support.Output;
const createMachine = support.createMachine;
const destroyMachine = support.destroyMachine;
const expectStack = support.expectStack;

test "file access methods and standard stream ids follow gforth" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("R/O W/O R/W STDIN STDOUT STDERR");
    try expectStack(machine, &.{ 0, 4, 2, 1, 2, 3 });
}

test "files are created, written, sized, repositioned, read by line, and closed" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    const newline = if (@import("builtin").os.tag == .windows) "\r\n" else "\n";

    try machine.interpretLine("S\" a.txt\" W/O CREATE-FILE THROW VALUE F");
    try machine.interpretLine("S\" abc\" F WRITE-LINE S\" de\" F WRITE-FILE F FILE-SIZE F CLOSE-FILE");
    try expectStack(machine, &.{ 0, 0, @intCast(5 + newline.len), 0, 0, 0 });
    try std.testing.expectEqualStrings("abc" ++ newline ++ "de", output.files[0].data[0..output.files[0].len]);

    machine.data_depth = 0;
    try machine.interpretLine("S\" a.txt\" R/O OPEN-FILE THROW TO F PAD 2 F READ-LINE PAD 10 F READ-LINE PAD 10 F READ-LINE PAD 10 F READ-LINE");
    try expectStack(machine, &.{ 2, -1, 0, 1, -1, 0, 2, -1, 0, 0, 0, 0 });
    machine.data_depth = 0;
    try machine.interpretLine("0. F REPOSITION-FILE PAD 10 F READ-LINE DROP DROP PAD SWAP TYPE F CLOSE-FILE F CLOSE-FILE");
    try std.testing.expectEqualStrings("abc", output.written());
    try expectStack(machine, &.{ 0, 0, forth.errnoIor(forth.errno_bad_file) });
}

test "file errors are returned as iors without changing the stack shape" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    const bad = forth.errnoIor(forth.errno_bad_file);
    const invalid = forth.errnoIor(forth.errno_invalid);

    try machine.interpretLine("S\" b.txt\" R/O OPEN-FILE S\" a.txt\" 99 OPEN-FILE 99 FILE-SIZE PAD 4 99 READ-LINE");
    try expectStack(machine, &.{ 0, forth.errnoIor(2), 0, invalid, 0, 0, bad, 0, 0, bad });
    machine.data_depth = 0;
    try machine.interpretLine("S\" a.txt\" W/O CREATE-FILE DROP -1 0 2 PICK REPOSITION-FILE NIP");
    try expectStack(machine, &.{invalid});
}

test "WRITE-LINE to STDOUT reaches the host" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    const newline = if (@import("builtin").os.tag == .windows) "\r\n" else "\n";

    try machine.interpretLine("S\" hi\" STDOUT WRITE-LINE");
    try expectStack(machine, &.{0});
    try std.testing.expectEqualStrings("hi" ++ newline, output.stdout_bytes[0..output.stdout_len]);
}

test "file words report an error when the host has no file support" {
    var output = Output{};
    const machine = try std.testing.allocator.create(forth.State);
    defer destroyMachine(machine);
    machine.init(.{ .context = @ptrCast(&output), .write_fn = Output.write });

    try std.testing.expectError(error.HostUnavailable, machine.interpretLine("S\" a.txt\" R/O OPEN-FILE"));
}

test "ALLOCATE FREE and RESIZE manage the heap and reuse freed blocks" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    const no_memory = forth.errnoIor(forth.errno_no_memory);
    const invalid = forth.errnoIor(forth.errno_invalid);

    try machine.interpretLine("100 ALLOCATE THROW VALUE A 77 A ! A 1000 RESIZE THROW TO A A @ A FREE 100 ALLOCATE THROW A =");
    try expectStack(machine, &.{ 77, 0, -1 });
    machine.data_depth = 0;
    try machine.interpretLine("-1 ALLOCATE 2000000 ALLOCATE 12345 FREE 0 FREE A 8 + FREE");
    try expectStack(machine, &.{ 0, no_memory, 0, no_memory, invalid, 0, invalid });
    machine.data_depth = 0;
    try machine.interpretLine("0 16 RESIZE NIP A 2000000 RESIZE SWAP A =");
    try expectStack(machine, &.{ 0, no_memory, -1 });
}

test "freeing every block returns the heap to its start" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("16 ALLOCATE THROW 32 ALLOCATE THROW 64 ALLOCATE THROW ROT DUP >R FREE THROW FREE THROW FREE THROW 900000 ALLOCATE THROW R> =");
    try expectStack(machine, &.{-1});
}

test "dynamic string words follow the book's Level 14 example" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("VARIABLE S S\" Hello, World!\" S $! S $@ TYPE SPACE S $. SPACE S $@LEN . 7 S $!LEN S $. CR");
    try machine.interpretLine("S\" land\" S $+! '!' S C$+! S $. CR S\" new \" S 7 $INS S $. CR S 7 4 $DEL S $. CR S\" world\" S 7 $OVER S $. CR");
    try std.testing.expectEqualStrings("Hello, World! Hello, World! 13 Hello, \nHello, land!\nHello, new land!\nHello, land!\nHello, world\n", output.written());
    try machine.interpretLine("VARIABLE E E $@ E $@LEN S $FREE S @");
    try expectStack(machine, &.{ 0, 0, 0, 0 });
}

test "dynamic strings handle sources inside themselves and out-of-range edits" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("VARIABLE S S\" abc\" S $! S $@ S $+! S $@ DROP 1+ 2 S 0 $INS S $. SPACE");
    try machine.interpretLine("S 2 100 $DEL S $. SPACE S 99 0 $DEL S\" xy\" S 99 $INS S $. SPACE S\" Z\" S 4 $OVER S $@ TYPE");
    try std.testing.expectEqualStrings("bcabcabc bc bcxy bcxyZ", output.written());
    output.len = 0;
    try machine.interpretLine("S\" ab\" S $! S\" Z\" S 4 $OVER S $@ TYPE");
    try std.testing.expectEqualStrings("ab  Z", output.written());
}

test "$SPLIT and $ITER divide strings at a separator" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("S\" name=value\" '=' $SPLIT TYPE SPACE TYPE SPACE S\" novalue\" '=' $SPLIT NIP . TYPE CR");
    try machine.interpretLine(": PART TYPE [CHAR] | EMIT ; VARIABLE S S\" 1234,567,,890\" S $! S ',' ' PART $ITER");
    try std.testing.expectEqualStrings("value name 0 novalue\n1234|567||890|", output.written());
}

test "$TMP captures output, nests, and restores output after an error" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine(": INNER .\" in\" 7 . ; : OUTER .\" <\" ['] INNER $TMP TYPE .\" >\" ; ' OUTER $TMP SPACE TYPE");
    try std.testing.expectEqualStrings(" <in7 >", output.written());
    try std.testing.expectError(error.UnknownWord, machine.interpretLine(": BAD .\" x\" MISSING ;"));
    machine.report(error.UnknownWord);
    try std.testing.expectError(error.StackUnderflow, machine.interpretLine(": FAIL .\" hidden\" DROP ; ' FAIL $TMP"));
    machine.report(error.StackUnderflow);
    try std.testing.expectEqualStrings(" <in7 >MISSING ?\nSTACK UNDER FLOW !\n", output.written());
}

test "string arrays store, fetch, count, map, print, and free elements" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("VARIABLE N S\" Alice\" 0 N $[]! S\" Bob\" 1 N $[]! S\" Charlie\" 3 N $[]! 1 N $[]@ TYPE SPACE N $[]# . 2 N $[]@ . DROP 9 N $[]@ . DROP N $[]# . CR");
    try machine.interpretLine(": SHOW TYPE [CHAR] ; EMIT ; N ' SHOW $[]MAP CR N $[]. N $[]FREE N @ .");
    try std.testing.expectEqualStrings("Bob 4 0 0 4 \nAlice;Bob;;Charlie;\nAlice\nBob\n\nCharlie\n0 ", output.written());
}

test "$[]SLURP and $[]SLURP-FILE read a file line by line" {
    var output = Output{};
    const long = "x" ** 300;
    const text = "one\n\n" ++ long ++ "\nlast";
    @memcpy(output.files[1].data[0..text.len], text);
    output.files[1].len = text.len;
    output.files[1].exists = true;
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("VARIABLE L S\" b.txt\" R/O OPEN-FILE THROW DUP L $[]SLURP CLOSE-FILE THROW L $[]# 0 L $[]@ TYPE 1 L $[]@ NIP 2 L $[]@ NIP 3 L $[]@ TYPE");
    try expectStack(machine, &.{ 4, 0, 300 });
    try std.testing.expectEqualStrings("onelast", output.written());
    machine.data_depth = 0;
    try machine.interpretLine("S\" b.txt\" L $[]SLURP-FILE L $[]#");
    try expectStack(machine, &.{4});
    try std.testing.expectError(error.Thrown, machine.interpretLine("S\" none.txt\" L $[]SLURP-FILE"));
    try std.testing.expectEqual(forth.errnoIor(2), machine.throw_code);
}

test "SLURP-FILE and $SLURP-FILE read a whole file as it is and close it" {
    var output = Output{};
    const text = "one\r\ntwo\n\x00end";
    @memcpy(output.files[1].data[0..text.len], text);
    output.files[1].len = text.len;
    output.files[1].exists = true;
    output.files[2].exists = true;
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("S\" b.txt\" SLURP-FILE 2DUP TYPE DROP FREE . S\" c.txt\" SLURP-FILE NIP .");
    try std.testing.expectEqualStrings(text ++ "0 0 ", output.written());
    try std.testing.expect(!output.files[1].open and !output.files[2].open);
    // $SLURP-FILE replaces the text of the string.
    try machine.interpretLine("VARIABLE S S\" old text that is longer\" S $! S\" b.txt\" S $SLURP-FILE S $@ NIP S\" b.txt\" S $SLURP-FILE S $@ NIP S\" c.txt\" S $SLURP-FILE S $@ NIP");
    try expectStack(machine, &.{ text.len, text.len, 0 });
    try std.testing.expect(!output.files[1].open);
    try std.testing.expectError(error.Thrown, machine.interpretLine("S\" none.txt\" SLURP-FILE"));
    try std.testing.expectEqual(forth.errnoIor(2), machine.throw_code);
    try std.testing.expectError(error.Thrown, machine.interpretLine("S\" none.txt\" S $SLURP-FILE"));
    try std.testing.expectEqual(forth.errnoIor(2), machine.throw_code);

    // When closing fails, SLURP-FILE throws and frees the block it allocated: the next
    // ALLOCATE of the same size gets the same address.
    machine.data_depth = 0;
    try machine.interpretLine("VARIABLE SLOT S\" b.txt\" SLURP-FILE DROP DUP SLOT ! FREE THROW");
    output.close_fails = true;
    try std.testing.expectError(error.Thrown, machine.interpretLine("S\" b.txt\" SLURP-FILE"));
    try std.testing.expectEqual(forth.errnoIor(5), machine.throw_code);
    output.close_fails = false;
    try std.testing.expect(!output.files[1].open);
    machine.data_depth = 0;
    try machine.interpretLine("13 ALLOCATE THROW SLOT @ =");
    try expectStack(machine, &.{-1});
}

test "RESTORE-INPUT goes back to a saved line of a file or place in a string, as in gforth" {
    var output = Output{};
    support.setFakeFile(&output, 0,
        \\VARIABLE C 0 C !
        \\CREATE SAVED 10 CELLS ALLOT
        \\: KEEP DUP 1+ 0 DO SAVED I CELLS + ! LOOP ;
        \\: BACK SAVED @ 0 SWAP DO SAVED I CELLS + @ -1 +LOOP ;
        \\: MARK SAVE-INPUT KEEP ;
        \\MARK
        \\C @ 1+ DUP C ! .
        \\C @ 3 < [IF] BACK RESTORE-INPUT DROP [THEN]
        \\.( done)
        \\0 C ! : M2 SAVE-INPUT KEEP ; S" M2 C @ 1+ DUP C ! . C @ 4 < [IF] BACK RESTORE-INPUT DROP [THEN]" EVALUATE
        \\BACK RESTORE-INPUT .
        \\
    );
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("INCLUDE a.txt");
    // The last RESTORE-INPUT fails: the saved place is in an EVALUATE string, not the file.
    try std.testing.expectEqualStrings("1 2 3 done1 2 3 4 -1 ", output.written());
    // The terminal goes back within the same line only.
    output.len = 0;
    try machine.interpretLine("M2 C @ 1+ DUP C ! . C @ 7 < [IF] BACK RESTORE-INPUT DROP [THEN]");
    try machine.interpretLine("BACK RESTORE-INPUT . 1 2 3 4 5 RESTORE-INPUT . 0 RESTORE-INPUT .");
    try std.testing.expectEqualStrings("5 6 7 -1 -1 -1 ", output.written());
}

test "SOURCE-ID gives the file id and REFILL the next line of an included file" {
    var output = Output{};
    support.setFakeFile(&output, 0, ": NL REFILL . SOURCE TYPE SOURCE NIP >IN ! ; SOURCE-ID 0> . NL\nthis line is read by REFILL\nSOURCE-ID 0> .\n");
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("INCLUDE a.txt SOURCE-ID .");
    try std.testing.expectEqualStrings("-1 -1 this line is read by REFILL-1 0 ", output.written());
}

test "PARSE-NAME reads the next name from a file being included" {
    var output = Output{};
    support.setFakeFile(&output, 0, ": NEXT-NAME PARSE-NAME ; : LAST-NAME NEXT-NAME NIP . ;\nNEXT-NAME \t  abc TYPE\nLAST-NAME\n");
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("INCLUDE a.txt");
    try std.testing.expectEqualStrings("abc0 ", output.written());
}

test "FILE-POSITION RESIZE-FILE FLUSH-FILE FILE-STATUS RENAME-FILE DELETE-FILE BIN and INCLUDE-FILE work as in gforth" {
    var output = Output{};
    support.setFakeFile(&output, 2, "1 2 + .\n");
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("R/O BIN . R/W BIN . W/O BIN .");
    try machine.interpretLine("S\" a.txt\" W/O BIN CREATE-FILE THROW VALUE F S\" hello world\" F WRITE-FILE . F FILE-POSITION . . . F FLUSH-FILE .");
    try machine.interpretLine("5 0 F RESIZE-FILE . F FILE-SIZE . . . F FILE-POSITION . . . F CLOSE-FILE .");
    try machine.interpretLine("S\" a.txt\" FILE-STATUS . . S\" b.txt\" FILE-STATUS . .");
    try machine.interpretLine("S\" a.txt\" S\" b.txt\" RENAME-FILE . S\" a.txt\" FILE-STATUS . DROP S\" b.txt\" FILE-STATUS . DROP");
    // RENAME-FILE moved the contents, cut to five bytes, to b.txt.
    try std.testing.expectEqualStrings("hello", output.files[1].data[0..output.files[1].len]);
    try machine.interpretLine("S\" b.txt\" DELETE-FILE . S\" b.txt\" DELETE-FILE .");
    try machine.interpretLine("S\" c.txt\" R/O OPEN-FILE THROW INCLUDE-FILE 99 F FILE-POSITION . . .");
    try std.testing.expectEqualStrings("1 3 5 0 0 0 11 0 0 0 0 5 0 0 11 0 0 2 -514 0 0 -514 0 0 -514 3 -521 -1 -1 ", output.written());
    try std.testing.expect(!output.files[1].exists and !output.files[2].open);
}

test "READ-FILE reads bytes as they are and gives 0 at the end of the file" {
    var output = Output{};
    support.setFakeFile(&output, 1, "abcd\r\nef");
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("S\" b.txt\" R/O OPEN-FILE THROW VALUE F PAD 4 F READ-FILE PAD 4 TYPE PAD 20 F READ-FILE PAD 4 TYPE PAD 20 F READ-FILE PAD 0 F READ-FILE F CLOSE-FILE");
    try expectStack(machine, &.{ 4, 0, 4, 0, 0, 0, 0, 0, 0 });
    try std.testing.expectEqualStrings("abcd\r\nef", output.written());
    machine.data_depth = 0;
    try machine.interpretLine("PAD 4 F READ-FILE");
    try expectStack(machine, &.{ 0, forth.errnoIor(forth.errno_bad_file) });
}

test "heap strings survive a full image restore" {
    var output = Output{};
    const source = try createMachine(&output);
    defer destroyMachine(source);
    try source.interpretLine("VARIABLE S S\" kept\" S $!");
    const image = try std.testing.allocator.alloc(u8, forth.State.imageCapacity());
    defer std.testing.allocator.free(image);
    const length = try source.encodeImage(image);

    const loaded = try createMachine(&output);
    defer destroyMachine(loaded);
    try loaded.restoreImage(image[0..length]);
    try loaded.interpretLine("S $. S\" !\" S $+! S $.");
    try std.testing.expectEqualStrings("keptkept!", output.written());
}
