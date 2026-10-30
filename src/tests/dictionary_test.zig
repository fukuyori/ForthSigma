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
        source.names_used + @as(usize, @intCast(source.data_here)) + @as(usize, @intCast(source.heapTop() - forth.data_limit)) + source_table_bytes + 4;
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

test "an FVALUE and a TO of it keep working after LOAD, a second LOAD, and a full restore" {
    var output = Output{};
    const source = try createMachine(&output);
    defer destroyMachine(source);
    try source.interpretLine("1.5E FVALUE FV : SETFV 2.5E TO FV ; : GETFV FV ;");
    const image = try saveImage(source);
    defer freeImage(image);

    // Appended twice after data of the dictionary's own, so the address of the value moves.
    const target = try createMachine(&output);
    defer destroyMachine(target);
    try target.interpretLine("CREATE FILLER 100 ALLOT 7E FVALUE OWN : EARLIER 1 ;");
    const loaded = try createMachine(&output);
    defer destroyMachine(loaded);
    try loaded.restoreImage(image);
    try target.appendImage(loaded);
    try target.interpretLine("FV F. SETFV FV F. GETFV F. 3.5E TO FV GETFV F.");
    try target.appendImage(loaded);
    try target.interpretLine("FV F. SETFV GETFV F. OWN F.");
    try std.testing.expectEqualStrings("1.5 2.5 2.5 3.5 1.5 2.5 7. ", output.written());

    // A full restore, as SAVESYS starts, keeps the value and the word that stores it.
    output.len = 0;
    const restored = try createMachine(&output);
    defer destroyMachine(restored);
    try source.interpretLine("4.5E TO FV");
    const image2 = try saveImage(source);
    defer freeImage(image2);
    try restored.restoreImage(image2);
    try restored.interpretLine("FV F. SETFV GETFV F. SEE FV");
    try std.testing.expectEqualStrings("4.5 2.5 2.5e FVALUE FV\n", output.written());
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

fn saveImage(machine: *forth.State) ![]u8 {
    const image = try std.testing.allocator.alloc(u8, forth.State.imageCapacity());
    errdefer std.testing.allocator.free(image);
    const length = try machine.encodeImage(image);
    return image[0..length];
}

fn freeImage(image: []u8) void {
    std.testing.allocator.free(image.ptr[0..forth.State.imageCapacity()]);
}

/// Writes the checksum again after a test has changed an image, so that the checks
/// behind it are reached.
fn resealImage(image: []u8) void {
    const body = image[0 .. image.len - 4];
    std.mem.writeInt(u32, image[body.len..][0..4], std.hash.Crc32.hash(body), .little);
}

test "a damaged image, or one whose names are out of order or out of range, is rejected before anything changes" {
    var output = Output{};
    const source = try createMachine(&output);
    defer destroyMachine(source);
    try source.interpretLine(": FIRST-WORD 1 ; :NONAME 2 ; DROP : SECOND-WORD 3 ;");
    const image = try saveImage(source);
    defer freeImage(image);
    const Word = @TypeOf(source.words[0]);
    const builtins: usize = source.builtin_count;

    const loaded = try createMachine(&output);
    defer destroyMachine(loaded);
    const before_words = loaded.word_count;
    const before_names = loaded.names_used;
    // Each byte is flipped with the mask, so the corruption changes it whatever it was
    // (a fixed value can equal the byte already there as the built-in names grow).
    const corruptions = [_]struct { usize, usize, u8 }{
        // A user word's name moved by one byte, into the built-in names or past them.
        .{ builtins, @offsetOf(Word, "name_start"), 0x01 },
        // The last built-in name given another length.
        .{ builtins - 1, @offsetOf(Word, "name_len"), 0xff },
        // The last word's name moved far past the end of the used names.
        .{ source.word_count - 1, @offsetOf(Word, "name_start") + 2, 0x04 },
    };
    for (corruptions) |corruption| {
        const at = 24 + corruption[0] * @sizeOf(Word) + corruption[1];
        const saved = image[at];
        image[at] = saved ^ corruption[2];
        resealImage(image);
        try std.testing.expectError(error.InvalidImage, loaded.restoreImage(image));
        image[at] = saved;
        resealImage(image);
        try std.testing.expectEqual(before_words, loaded.word_count);
        try std.testing.expectEqual(before_names, loaded.names_used);
    }
    // The previous format is not read either.
    @memcpy(image[0..8], "SIGIMG31");
    resealImage(image);
    try std.testing.expectError(error.InvalidImage, loaded.restoreImage(image));
    @memcpy(image[0..8], "SIGIMG32");
    resealImage(image);
    // One damaged byte anywhere, here in the saved memory or in the checksum itself,
    // fails the checksum, and the dictionary, code, and memory stay as they were.
    const memory_before = try std.testing.allocator.dupe(u8, &loaded.memory);
    defer std.testing.allocator.free(memory_before);
    const code_before = loaded.code_count;
    const here_before = loaded.data_here;
    for ([_]usize{ image.len - 100, image.len - 1 }) |at| {
        image[at] ^= 0x01;
        try std.testing.expectError(error.InvalidImage, loaded.restoreImage(image));
        image[at] ^= 0x01;
        try std.testing.expectEqual(before_words, loaded.word_count);
        try std.testing.expectEqual(before_names, loaded.names_used);
        try std.testing.expectEqual(code_before, loaded.code_count);
        try std.testing.expectEqual(here_before, loaded.data_here);
        try std.testing.expectEqualSlices(u8, memory_before, &loaded.memory);
    }
    try loaded.restoreImage(image);
    try loaded.interpretLine("FIRST-WORD SECOND-WORD");
    try expectStack(loaded, &.{ 1, 3 });
}

test "a VARIABLE without room for its name and a definition CATCH abandons leave HERE and the names as they were" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    const names_before = machine.names_used;
    try machine.interpretLine(": START S\" : BROKEN NO-SUCH-WORD ;\" EVALUATE ; ' START CATCH .");
    try std.testing.expectEqualStrings("-13 ", output.written());
    try std.testing.expectEqual(names_before + "START".len, machine.names_used);

    var line: [300]u8 = undefined;
    var count: usize = 0;
    while (true) : (count += 1) {
        machine.interpretLine(try std.fmt.bufPrint(&line, ": {s}{d:0>6} ;", .{ "N" ** 249, count })) catch |err| {
            machine.report(err);
            break;
        };
    }
    const here = machine.data_here;
    const names = machine.names_used;
    const words = machine.word_count;
    try std.testing.expectError(error.DictionaryFull, machine.interpretLine("VARIABLE " ++ "V" ** 255));
    machine.report(error.DictionaryFull);
    try std.testing.expectEqual(here, machine.data_here);
    try std.testing.expectEqual(names, machine.names_used);
    try std.testing.expectEqual(words, machine.word_count);
}

test "LOAD into a dictionary without room changes nothing, and unnamed words keep LOAD and FORGET in step" {
    var output = Output{};
    const source = try createMachine(&output);
    defer destroyMachine(source);
    try source.interpretLine(": AAA 1 ; :NONAME 2 ; DROP : BBB 3 ;");
    const image = try saveImage(source);
    defer freeImage(image);
    const loaded = try createMachine(&output);
    defer destroyMachine(loaded);
    try loaded.restoreImage(image);

    const target = try createMachine(&output);
    defer destroyMachine(target);
    try target.interpretLine(":NONAME 9 ; DROP : CCC 4 ;");
    const names_before = target.names_used;
    try target.appendImage(loaded);
    try target.interpretLine("AAA BBB CCC");
    try expectStack(target, &.{ 1, 3, 4 });
    try target.interpretLine("FORGET AAA : DDD 5 ; DDD CCC");
    try std.testing.expectEqual(names_before + "DDD".len, target.names_used);
    try expectStack(target, &.{ 1, 3, 4, 5, 4 });

    // A full name area: the appended image does not fit and nothing changes.
    const full = try createMachine(&output);
    defer destroyMachine(full);
    var line: [300]u8 = undefined;
    var count: usize = 0;
    while (true) : (count += 1) {
        full.interpretLine(try std.fmt.bufPrint(&line, ": {s}{d:0>6} ;", .{ "N" ** 249, count })) catch |err| {
            full.report(err);
            break;
        };
    }
    const words = full.word_count;
    const names = full.names_used;
    const code = full.code_count;
    const here = full.data_here;
    // Names longer than the room left (less than one 255-byte name).
    const long_source = try createMachine(&output);
    defer destroyMachine(long_source);
    try long_source.interpretLine(": " ++ "A" ** 200 ++ " 1 ; : " ++ "B" ** 200 ++ " 2 ;");
    const long_image = try saveImage(long_source);
    defer freeImage(long_image);
    const long_loaded = try createMachine(&output);
    defer destroyMachine(long_loaded);
    try long_loaded.restoreImage(long_image);
    try std.testing.expectError(error.DictionaryFull, full.appendImage(long_loaded));
    try std.testing.expectEqual(words, full.word_count);
    try std.testing.expectEqual(names, full.names_used);
    try std.testing.expectEqual(code, full.code_count);
    try std.testing.expectEqual(here, full.data_here);
}

test "LOAD keeps a DEFER's action pointing to the loaded word" {
    var output = Output{};
    const source = try createMachine(&output);
    defer destroyMachine(source);
    try source.interpretLine(": TWICE 2 * ; DEFER ACT ' TWICE IS ACT DEFER BUILTIN-ACT ' DUP IS BUILTIN-ACT");
    const image = try std.testing.allocator.alloc(u8, forth.State.imageCapacity());
    defer std.testing.allocator.free(image);
    const length = try source.encodeImage(image);

    const target = try createMachine(&output);
    defer destroyMachine(target);
    try target.interpretLine(": ALREADY-HERE 5 ; : MORE 6 ;");
    const loaded = try createMachine(&output);
    defer destroyMachine(loaded);
    try loaded.restoreImage(image[0..length]);
    try target.appendImage(loaded);
    try target.interpretLine("4 ACT 3 BUILTIN-ACT ACTION-OF ACT ' TWICE =");
    try expectStack(target, &.{ 8, 3, 3, -1 });
}
