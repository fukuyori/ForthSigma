//! Tests of HELP and LICENSE.

const std = @import("std");
const forth = @import("../forth.zig");
const help_text = @import("../core/help_text.zig");
const words_help = @import("../core/words_help.zig");
const support = @import("support.zig");
const Output = support.Output;
const createMachine = support.createMachine;
const destroyMachine = support.destroyMachine;
const expectStack = support.expectStack;

test "HELP has a description for every built-in word, and only for words that exist" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    for (machine.words[0..machine.builtin_count]) |word| {
        const name = machine.wordName(word);
        if (words_help.entry(name) == null) {
            std.debug.print("no help for {s}\n", .{name});
            return error.TestExpectedEqual;
        }
    }
    // The parser handles these without dictionary entries.
    const parser_words = [_][]const u8{ "(", "\\", ".(", "[", "]", "[']", "CHAR", "[CHAR]", "POSTPONE", "TO", ":NONAME", "{", "{:", "LOCALS|", "S\"", "S\\\"", ".\"", ".\\\"", "\"", "FORGET" };
    for (help_text.entries, 0..) |entry, index| {
        const known = machine.lookup(entry.name) != null or for (parser_words) |parser_word| {
            if (std.mem.eql(u8, parser_word, entry.name)) break true;
        } else false;
        if (!known) {
            std.debug.print("help for a word that does not exist: {s}\n", .{entry.name});
            return error.TestExpectedEqual;
        }
        for (help_text.entries[index + 1 ..]) |other| {
            if (std.ascii.eqlIgnoreCase(other.name, entry.name)) {
                std.debug.print("two help entries for {s}\n", .{entry.name});
                return error.TestExpectedEqual;
            }
        }
    }
}

test "HELP shows the basic help, a word's description, or where to look for a defined word" {
    var output = Output{};
    output.input_lines[0] = "DUP";
    output.input_count = 1;
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    // HELP alone does not read the next input line as a name.
    try machine.interpretLine("HELP");
    try std.testing.expectEqualStrings(help_text.basic, output.written());
    try std.testing.expectEqual(@as(usize, 0), output.input_index);
    output.len = 0;
    try machine.interpretLine("help dup HELP to : SQ DUP * ; HELP sq");
    try std.testing.expectEqualStrings("DUP ( x -- x x )\n  Copy the top cell.\nTO ( x \"name\" -- )\n  Change a VALUE or a local variable.\n" ++
        "SQ is a word defined after start-up; SEE SQ shows its definition.\n", output.written());
    try std.testing.expectError(error.UnknownWord, machine.interpretLine("HELP NO-SUCH-WORD"));
    machine.report(error.UnknownWord);
}

test "HELP takes a name only from its own line, also in EVALUATE, and in a definition when it runs" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    // The DUP on the next line of the string runs; HELP shows the basic help.
    try machine.interpretLine("7 S\\\" HELP\\nDUP\" EVALUATE");
    try std.testing.expectEqualStrings(help_text.basic, output.written());
    try expectStack(machine, &.{ 7, 7 });
    output.len = 0;
    try machine.interpretLine("S\\\" HELP  \\n SWAP\" EVALUATE S\\\" HELP DUP\\nOVER\" EVALUATE");
    try std.testing.expectEqualStrings(help_text.basic ++ "DUP ( x -- x x )\n  Copy the top cell.\n", output.written());
    try expectStack(machine, &.{ 7, 7, 7 });
    output.len = 0;
    try machine.interpretLine(": H HELP ; H SWAP H");
    try std.testing.expectEqualStrings("SWAP ( x1 x2 -- x2 x1 )\n  Exchange the top two cells.\n" ++ help_text.basic, output.written());
    try std.testing.expectError(error.UnknownWord, machine.interpretLine("H NO-SUCH-WORD 1"));
    machine.report(error.UnknownWord);
    try expectStack(machine, &.{});
}

test "LICENSE shows the MIT License and the CORE-MATH notices with LF line ends before the host" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("LICENSE");
    const text = output.written();
    try std.testing.expect(std.mem.startsWith(u8, text, "MIT License\n"));
    try std.testing.expect(std.mem.indexOf(u8, text, "Copyright (c) 2026 fukuyori") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "## CORE-MATH") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "Paul Zimmermann and Tom Hubrecht") != null);
    try std.testing.expect(std.mem.indexOfScalar(u8, text, '\r') == null);
}
