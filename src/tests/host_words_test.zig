//! Tests of :NONAME and of the words that call the host (MS, UTIME, GETENV, SYSTEM, PAGE, THROW).

const std = @import("std");
const forth = @import("../forth.zig");
const support = @import("support.zig");
const Output = support.Output;
const createMachine = support.createMachine;
const destroyMachine = support.destroyMachine;
const expectStack = support.expectStack;
const expectOutput = support.expectOutput;

test ":NONAME compiles an unnamed definition and leaves its execution token" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    const initial_words = machine.word_count;

    try machine.interpretLine(":NONAME 2 * ; 21 SWAP EXECUTE :NONAME 42 ; CONSTANT ACTION ACTION EXECUTE");
    const expected = [_]forth.Cell{ 42, 42 };
    try expectStack(machine, &expected);

    try machine.interpretLine("WORDS");
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "  ") == null);

    try std.testing.expectError(error.InvalidDefinition, machine.interpretLine(": OUTER :NONAME ;"));
    machine.report(error.InvalidDefinition);
    try std.testing.expectError(error.UnknownWord, machine.interpretLine(":NONAME 1 MISSING"));
    machine.report(error.UnknownWord);
    // The two unnamed definitions and ACTION remain; OUTER and the failed one are rolled back.
    try std.testing.expectEqual(initial_words + 3, machine.word_count);
}

test "an execution token stored in a constant survives a full image restore" {
    var output = Output{};
    const source = try createMachine(&output);
    defer destroyMachine(source);
    try source.interpretLine(":NONAME 42 ; CONSTANT ACTION");
    const image = try std.testing.allocator.alloc(u8, forth.State.imageCapacity());
    defer std.testing.allocator.free(image);
    const length = try source.encodeImage(image);

    const loaded = try createMachine(&output);
    defer destroyMachine(loaded);
    try loaded.restoreImage(image[0..length]);
    try loaded.interpretLine("ACTION EXECUTE");
    try expectStack(loaded, &.{42});

    @memcpy(image[0..8], "SIGIMG02");
    try std.testing.expectError(error.InvalidImage, loaded.restoreImage(image[0..length]));
}

test "MS UTIME GETENV and SYSTEM call the host" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("250 MS UTIME S\" HOME\" GETENV TYPE S\" MISSING\" GETENV S\" EMPTY\" GETENV NIP S\" dir /b\" SYSTEM");
    try std.testing.expectEqual(@as(forth.Cell, 250), output.slept);
    try std.testing.expectEqualStrings("/home/lemon", output.written());
    try std.testing.expectEqualStrings("dir /b", output.command[0..output.command_len]);
    const expected = [_]forth.Cell{ 1_700_000_000_000_000, 0, 0, 0, 0 };
    try expectStack(machine, &expected);

    try std.testing.expectError(error.StringTooLong, machine.interpretLine("S\" LONG\" GETENV"));
    machine.report(error.StringTooLong);
    try std.testing.expectError(error.HostFailed, machine.interpretLine("S\" fail\" SYSTEM"));
    machine.report(error.HostFailed);
}

test "host words report an error when the host does not provide them" {
    var output = Output{};
    const machine = try std.testing.allocator.create(forth.State);
    defer destroyMachine(machine);
    machine.init(.{ .context = @ptrCast(&output), .write_fn = Output.write });

    try std.testing.expectError(error.HostUnavailable, machine.interpretLine("1 MS"));
    machine.report(error.HostUnavailable);
    try std.testing.expectError(error.HostUnavailable, machine.interpretLine("S\" X\" SYSTEM"));
    machine.report(error.HostUnavailable);
    try std.testing.expectError(error.HostUnavailable, machine.interpretLine("UTIME"));
    machine.report(error.HostUnavailable);
    try std.testing.expectError(error.HostUnavailable, machine.interpretLine("S\" X\" GETENV"));
    machine.report(error.HostUnavailable);
    try std.testing.expectEqualStrings("HOST FUNCTION UNAVAILABLE !\n" ** 4, output.written());
    try expectStack(machine, &.{});
}

test "host failures in MS and UTIME are reported and leave a clean stack" {
    var output = Output{};
    output.host_fails = true;
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try std.testing.expectError(error.HostFailed, machine.interpretLine("7 100 MS"));
    machine.report(error.HostFailed);
    try std.testing.expectError(error.HostFailed, machine.interpretLine(": T UTIME ; T"));
    machine.report(error.HostFailed);
    try std.testing.expectEqualStrings("HOST FUNCTION ERROR !\nHOST FUNCTION ERROR !\n", output.written());
    try std.testing.expectEqual(@as(forth.Cell, -1), output.slept);
    try expectStack(machine, &.{});
}

test "PAGE clears the screen with ANSI sequences" {
    try expectOutput("PAGE", "\x1b[2J\x1b[1;1H");
}

test "THROW ignores zero, aborts on -1, and reports other codes in decimal" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("1 2 0 THROW");
    try expectStack(machine, &.{ 1, 2 });
    try std.testing.expectError(error.Aborted, machine.interpretLine("-1 THROW"));
    machine.report(error.Aborted);
    try expectStack(machine, &.{});

    const codes = [_][]const u8{ "-4 THROW", "-514 THROW", ": T -37 THROW ; T", "HEX 5 THROW" };
    // -4 is the code of the interpreter's stack underflow, so THROW raises that error.
    const errors = [_]anyerror{ error.StackUnderflow, error.Thrown, error.Thrown, error.Thrown };
    for (codes, errors) |line, expected| {
        try std.testing.expectError(expected, machine.interpretLine(line));
        machine.report(expected);
    }
    try std.testing.expectEqualStrings("STACK UNDER FLOW !\nNO SUCH FILE OR DIRECTORY !\nFILE I/O EXCEPTION !\nERROR #5 !\n", output.written());
}
