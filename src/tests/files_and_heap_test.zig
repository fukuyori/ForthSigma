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
    machine.* = forth.State.init(.{ .context = @ptrCast(&output), .write_fn = Output.write });

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
