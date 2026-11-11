//! Tests of the single-step debugger: DBG, BREAK:, and BREAK", with the keys given
//! as KEY reads them.

const std = @import("std");
const forth = @import("../forth.zig");
const support = @import("support.zig");
const Output = support.Output;
const createMachine = support.createMachine;
const destroyMachine = support.destroyMachine;
const expectStack = support.expectStack;

const words =
    ": INNER 1+ ; : BADWORD 0 DO I INNER . LOOP ; " ++
    ": LONG 1+ 2* 1- 3 + 2 - ; : CALLS LONG 1+ ; " ++
    ": WITHBREAK 1+ BREAK: 2* ; : WITHMSG 1+ BREAK\" here\" 2* ;";

var plain_buffer: [4096]u8 = undefined;

/// `text` without the blanks at the ends of its lines: a step's line ends in "-> ",
/// which the expected texts of these tests do not keep.
fn plain(text: []const u8) []const u8 {
    var length: usize = 0;
    for (text) |byte| {
        if (byte == '\n') {
            while (length > 0 and plain_buffer[length - 1] == ' ') length -= 1;
        }
        plain_buffer[length] = byte;
        length += 1;
    }
    while (length > 0 and (plain_buffer[length - 1] == ' ' or plain_buffer[length - 1] == '\n')) length -= 1;
    return plain_buffer[0..length];
}

/// Interprets `line` with `keys` waiting for KEY, and gives what was written, without
/// the blanks at the ends of the lines.
fn stepped(machine: *forth.State, output: *Output, keys: []const u8, line: []const u8) ![]const u8 {
    output.len = 0;
    output.keys = keys;
    output.key_index = 0;
    try machine.interpretLine(line);
    return plain(output.written());
}

test "DBG stops before each operation and shows the stack it leaves" {
    try support.skipWithout(&.{.debug});
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    try machine.interpretLine(words);

    // INNER, a short definition copied into BADWORD, is one step, as a call is.
    try std.testing.expectEqualStrings(
        \\: BADWORD
        \\[ 1 ] 2
        \\0              -> [ 2 ] 2 0
        \\DO             -> [ 0 ]
        \\I              -> [ 1 ] 0
        \\INNER          -> [ 1 ] 1
        \\.              -> 1 [ 0 ]
        \\LOOP           -> [ 0 ]
        \\I              -> [ 1 ] 1
        \\INNER          -> [ 1 ] 2
        \\.              -> 2 [ 0 ]
        \\LOOP           -> [ 0 ]
        \\;              ->
    , try stepped(machine, &output, "\n\r\n\r\n\n\n\n\n\n\n\n\n", "2 DBG BADWORD"));
    try expectStack(machine, &.{});
    try std.testing.expectEqual(@as(usize, 13), output.key_index);

    // After it, the word runs as before.
    try std.testing.expectEqualStrings("1", try stepped(machine, &output, "", "1 BADWORD"));
}

test "n goes into the word an operation calls, and u out of it" {
    try support.skipWithout(&.{.debug});
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    try machine.interpretLine(words);

    try std.testing.expectEqualStrings(
        \\: CALLS
        \\[ 1 ] 5
        \\LONG           ->
        \\: LONG
        \\[ 1 ] 5
        \\1+             -> [ 1 ] 6
        \\2*             -> [ 1 ] 12
        \\1-             -> [ 1 ] 11
        \\3              -> [ 2 ] 11 3
        \\+              -> [ 1 ] 14
        \\2              -> [ 2 ] 14 2
        \\-              -> [ 1 ] 12
        \\;              ->
        \\[ 1 ] 12
        \\1+             -> [ 1 ] 13
        \\;              ->
    , try stepped(machine, &output, "n\n\n\n\n\n\n\n\n\n\n", "5 DBG CALLS"));
    try expectStack(machine, &.{13});

    try std.testing.expectEqualStrings(
        \\: CALLS
        \\[ 1 ] 5
        \\LONG           ->
        \\: LONG
        \\[ 1 ] 5
        \\1+             -> [ 1 ] 6
        \\2*             ->
        \\[ 1 ] 12
        \\1+             -> [ 1 ] 13
        \\;              ->
    , try stepped(machine, &output, "n\nu\n\n", "DROP 5 DBG CALLS"));

    // Into the copied code of a short definition, and out of it.
    try std.testing.expectEqualStrings(
        \\: BADWORD
        \\[ 1 ] 1
        \\0              -> [ 2 ] 1 0
        \\DO             -> [ 0 ]
        \\I              -> [ 1 ] 0
        \\INNER          ->
        \\: INNER
        \\[ 1 ] 0
        \\1+             ->
        \\[ 1 ] 1
        \\.              -> 1 [ 0 ]
        \\LOOP           -> [ 0 ]
        \\;              ->
    , try stepped(machine, &output, "\n\n\nnu\n\n\n", "DROP 1 DBG BADWORD"));

    // u in the word the steps started in runs the rest of it.
    try std.testing.expectEqualStrings(
        \\: BADWORD
        \\[ 1 ] 2
        \\0              -> [ 2 ] 2 0
        \\DO             ->
        \\1 2
    , try stepped(machine, &output, "\nu", "2 DBG BADWORD"));
}

test "d runs the rest, s ends the run with an error, and the end of the keys is as d" {
    try support.skipWithout(&.{.debug});
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    try machine.interpretLine(words);

    try std.testing.expectEqualStrings(
        \\: BADWORD
        \\[ 1 ] 2
        \\0              -> [ 2 ] 2 0
        \\DO             ->
        \\Done...
        \\1 2
    , try stepped(machine, &output, "\nd", "2 DBG BADWORD"));

    try std.testing.expectEqualStrings(
        \\: BADWORD
        \\[ 1 ] 2
        \\0              -> [ 2 ] 2 0
        \\DO             -> 1 2
    , try stepped(machine, &output, "\n", "2 DBG BADWORD"));

    output.len = 0;
    output.keys = "\ns";
    output.key_index = 0;
    try std.testing.expectError(error.Thrown, machine.interpretLine("2 DBG BADWORD"));
    machine.report(error.Thrown);
    try std.testing.expectEqualStrings(
        \\: BADWORD
        \\[ 1 ] 2
        \\0              -> [ 2 ] 2 0
        \\DO             ->
        \\debugger aborted
        \\BACKTRACE:
        \\  BADWORD
        \\STACK: <2> 2 0
    , plain(output.written()));
    try std.testing.expect(machine.stepper == .off);

    // Not a colon definition.
    try std.testing.expectError(error.InvalidDefinition, machine.interpretLine("DBG DUP"));
    try std.testing.expectError(error.UnknownWord, machine.interpretLine("DBG MISSING"));
}

test "BREAK: and BREAK\" start the steps in the middle of a definition" {
    try support.skipWithout(&.{.debug});
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    try machine.interpretLine(words);

    try std.testing.expectEqualStrings(
        \\[ 1 ] 6
        \\2*             -> [ 1 ] 12
        \\;              ->
    , try stepped(machine, &output, "\n\n", "5 WITHBREAK"));
    try expectStack(machine, &.{12});

    try std.testing.expectEqualStrings(
        \\BREAK AT: here
        \\[ 1 ] 6
        \\2*             -> [ 1 ] 12
        \\;              ->
    , try stepped(machine, &output, "\n\n", "DROP 5 WITHMSG"));

    // A definition called from one that is stepped through runs without stopping,
    // also when it has a BREAK: of its own.
    try std.testing.expectEqualStrings(
        \\: OUTER
        \\[ 1 ] 5
        \\WITHBREAK      -> [ 1 ] 12
        \\;              ->
    , try stepped(machine, &output, "\n\n", "DROP : OUTER WITHBREAK ; 5 DBG OUTER"));
    try std.testing.expectError(error.CompileOnly, machine.interpretLine("BREAK:"));
}

test "a BREAK: of a loaded image stops as one compiled here" {
    try support.skipWithout(&.{ .debug, .image });
    var output = Output{};
    const source = try createMachine(&output);
    defer destroyMachine(source);
    try source.interpretLine(": T BREAK: 123 . ; : U BREAK\" there\" 7 . ;");
    const image = try std.testing.allocator.alloc(u8, forth.State.imageCapacity(.small));
    defer std.testing.allocator.free(image);
    const length = try source.encodeImage(image);

    // As LOAD does: restored in a State of its own, then added.
    const loaded = try createMachine(&output);
    defer destroyMachine(loaded);
    try loaded.restoreImage(image[0..length]);
    const target = try createMachine(&output);
    defer destroyMachine(target);
    try target.appendImage(loaded);
    try std.testing.expectEqualStrings(
        \\[ 0 ]
        \\123            -> [ 1 ] 123
        \\.              -> 123 [ 0 ]
        \\;              ->
    , try stepped(target, &output, "\n\n\n", "T"));
    try std.testing.expectEqual(@as(usize, 3), output.key_index);

    // And as a saved program starts: restored in the State that runs it.
    const fresh = try createMachine(&output);
    defer destroyMachine(fresh);
    try fresh.restoreImage(image[0..length]);
    try std.testing.expectEqualStrings(
        \\BREAK AT: there
        \\[ 0 ]
        \\7              -> [ 1 ] 7
        \\.              -> 7 [ 0 ]
        \\;              ->
    , try stepped(fresh, &output, "\n\n\n", "U"));
}

test "the steps that a BREAK: after DOES> started end with that code" {
    try support.skipWithout(&.{.debug});
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine(": MK CREATE DOES> BREAK: DROP 1 ; MK X : OTHER 42 . ;");
    try std.testing.expectEqualStrings(
        \\[ 1 ]
    , (try stepped(machine, &output, "\n\n\n", "X"))[0..5]);
    try std.testing.expect(machine.stepper == .off);
    // OTHER asks for no key.
    try std.testing.expectEqualStrings("42", try stepped(machine, &output, "", "OTHER"));
}

test "n goes into copied definitions inside copied definitions, and u out of each" {
    try support.skipWithout(&.{.debug});
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine(": A 1+ ; : B A 2* ; : C B 3 + ;");
    // Into B, into A, 1+, then u at 2* runs the rest of B; the steps go on in C.
    try std.testing.expectEqualStrings(
        \\: C
        \\[ 1 ] 4
        \\B              ->
        \\: B
        \\[ 1 ] 4
        \\A              ->
        \\: A
        \\[ 1 ] 4
        \\1+             -> [ 1 ] 5
        \\2*             ->
        \\[ 1 ] 10
        \\3              -> [ 2 ] 10 3
        \\+              -> [ 1 ] 13
        \\;              ->
    , try stepped(machine, &output, "nn\nu\n\n\n", "4 DBG C"));
    try std.testing.expectEqual(@as(usize, 7), output.key_index);
}

test "n goes into a colon definition called by another name" {
    try support.skipWithout(&.{.debug});
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine(": LONG 1+ 2* 1- 3 + 2 - ; SYNONYM ALSO-LONG LONG : C ALSO-LONG ;");
    try std.testing.expectEqualStrings(
        \\: C
        \\[ 1 ] 4
        \\ALSO-LONG      ->
        \\: LONG
        \\[ 1 ] 4
        \\1+             -> [ 1 ] 5
        \\2*             ->
        \\[ 1 ] 10
        \\;              ->
    , try stepped(machine, &output, "n\nu\n", "4 DBG C"));
}
