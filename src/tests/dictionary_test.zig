//! Tests of the dictionary's name area and of the size and contents of images.

const std = @import("std");
const forth = @import("../forth.zig");
const support = @import("support.zig");
const Output = support.Output;
const createMachine = support.createMachine;
const destroyMachine = support.destroyMachine;
const expectStack = support.expectStack;

test "FORGET, MARKER, and a failed definition give back the space of their names" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    const start = machine.names_used;
    try machine.interpretLine(": A-LONG-NAME 1 ; VARIABLE ANOTHER-NAME");
    try std.testing.expectEqual(start + "A-LONG-NAME".len + "ANOTHER-NAME".len, machine.names_used);
    try machine.interpretLine("FORGET A-LONG-NAME");
    try std.testing.expectEqual(start, machine.names_used);
    try machine.interpretLine("MARKER GONE : FIRST-WORD 1 ; : SECOND-WORD 2 ; GONE");
    try std.testing.expectEqual(start, machine.names_used);
    try std.testing.expectError(error.UnknownWord, machine.interpretLine(": BROKEN-DEFINITION NO-SUCH-WORD ;"));
    machine.report(error.UnknownWord);
    try std.testing.expectEqual(start, machine.names_used);
    try machine.interpretLine(": SHORT 7 ; SHORT");
    try expectStack(machine, &.{7});
}

test "a full name area is a full dictionary, and the words before still work" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    // Names of 255 characters fill the name area long before the word limit.
    var line: [300]u8 = undefined;
    var count: usize = 0;
    while (true) : (count += 1) {
        const text = try std.fmt.bufPrint(&line, ": {s}{d:0>6} {d} ;", .{ "N" ** 249, count, count });
        machine.interpretLine(text) catch |err| {
            try std.testing.expectEqual(error.DictionaryFull, err);
            machine.report(err);
            break;
        };
    }
    try std.testing.expect(count > 1000 and count < machine.words.len);
    try std.testing.expect(machine.names_used <= machine.names.len);
    try machine.interpretLine(try std.fmt.bufPrint(&line, "{s}{d:0>6}", .{ "N" ** 249, count - 1 }));
    try expectStack(machine, &.{@as(forth.Cell, @intCast(count - 1))});
}

test "an image keeps HERE's data, the used heap, and the source table, and nothing else" {
    var output = Output{};
    const source = try createMachine(&output);
    defer destroyMachine(source);
    try source.interpretLine("VARIABLE S S\" kept on the heap\" S $! : SHOW S $@ TYPE ; CREATE BUF 4 ALLOT 1 BUF C!");
    // Bytes above HERE are not part of the image.
    try source.interpretLine("HERE 100 + 99 SWAP C!");
    const image = try std.testing.allocator.alloc(u8, forth.State.imageCapacity());
    defer std.testing.allocator.free(image);
    const length = try source.encodeImage(image);

    const source_table_bytes = 64 * 256 + 64;
    const expected = 24 + @as(usize, source.word_count) * @sizeOf(@TypeOf(source.words[0])) + @as(usize, source.code_count) * @sizeOf(@TypeOf(source.code[0])) +
        source.names_used + @as(usize, @intCast(source.data_here)) + @as(usize, @intCast(source.heapTop() - forth.data_limit)) + source_table_bytes;
    try std.testing.expectEqual(expected, length);
    try std.testing.expect(length < 200_000);

    const loaded = try createMachine(&output);
    defer destroyMachine(loaded);
    try loaded.restoreImage(image[0..length]);
    try loaded.interpretLine("SHOW BUF C@ HERE 100 + C@");
    try std.testing.expectEqualStrings("kept on the heap", output.written());
    try expectStack(loaded, &.{ 1, 0 });
    try std.testing.expectError(error.InvalidImage, loaded.restoreImage(image[0 .. length - 1]));
}

test "LOAD gives the added words their names after the dictionary's own" {
    var output = Output{};
    const source = try createMachine(&output);
    defer destroyMachine(source);
    try source.interpretLine(": FIRST-LOADED 10 ; : SECOND-LOADED FIRST-LOADED 1+ ;");
    const image = try std.testing.allocator.alloc(u8, forth.State.imageCapacity());
    defer std.testing.allocator.free(image);
    const length = try source.encodeImage(image);

    const target = try createMachine(&output);
    defer destroyMachine(target);
    try target.interpretLine(": ALREADY-HERE 5 ;");
    const loaded = try createMachine(&output);
    defer destroyMachine(loaded);
    try loaded.restoreImage(image[0..length]);
    try target.appendImage(loaded);
    try target.interpretLine("ALREADY-HERE SECOND-LOADED FIRST-LOADED SEE SECOND-LOADED");
    try expectStack(target, &.{ 5, 11, 10 });
    try std.testing.expectEqualStrings(": SECOND-LOADED\n  FIRST-LOADED 1+\n;\n", output.written());
    try target.interpretLine("FORGET FIRST-LOADED : AFTER-FORGET 3 ; AFTER-FORGET");
    try expectStack(target, &.{ 5, 11, 10, 3 });
}
