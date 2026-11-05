//! Tests of REQUIRE-GRAPHICS, the GFX- words, and dictionary images with them.

const std = @import("std");
const forth = @import("../forth.zig");
const memory_map = @import("../core/memory_map.zig");
const words_graphics = @import("../core/words_graphics.zig");
const support = @import("support.zig");
const Output = support.Output;
const createMachine = support.createMachine;
const destroyMachine = support.destroyMachine;
const expectStack = support.expectStack;
const repeat = support.repeat;
const skipWithout = support.skipWithout;

fn saveImage(machine: *forth.State) ![]u8 {
    const image = try std.testing.allocator.alloc(u8, forth.State.imageCapacity());
    errdefer std.testing.allocator.free(image);
    const length = try machine.encodeImage(image);
    return image[0..length];
}

fn freeImage(image: []u8) void {
    std.testing.allocator.free(image.ptr[0..forth.State.imageCapacity()]);
}

test "REQUIRE-GRAPHICS is refused in a build without graphics" {
    if (@import("build_options").graphics) return error.SkipZigTest;
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    const words_before = machine.word_count;
    try std.testing.expectError(error.GraphicsUnavailable, machine.interpretLine("REQUIRE-GRAPHICS"));
    try std.testing.expectEqual(words_before, machine.word_count);
    try machine.interpretLine(": T S\" REQUIRE-GRAPHICS\" EVALUATE ; ' T CATCH");
    try expectStack(machine, &.{-270});
}

test "REQUIRE-GRAPHICS loads the GRAPHICS vocabulary once and keeps the search order" {
    try skipWithout(&.{.graphics});
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    const builtins = machine.builtin_count;
    const words_before = machine.word_count;
    try machine.interpretLine("ORDER");
    const order_before = try std.testing.allocator.dupe(u8, output.written());
    defer std.testing.allocator.free(order_before);
    output.len = 0;

    try machine.interpretLine("REQUIRE-GRAPHICS");
    // The built-in words every dictionary starts with do not change.
    try std.testing.expectEqual(builtins, machine.builtin_count);
    // GRAPHICS, then the GFX- words, then the words of the library.
    try std.testing.expectEqual(@import("../core/defs.zig").WordKind.vocabulary, machine.words[words_before].kind);
    for (words_graphics.definitions, 1..) |definition, offset| {
        try std.testing.expectEqual(definition[1], machine.words[words_before + offset].builtin);
    }
    try std.testing.expect(machine.word_count > words_before + 1 + words_graphics.definitions.len);
    try machine.interpretLine("ORDER");
    try std.testing.expectEqualStrings(order_before, output.written());
    try std.testing.expect(machine.lookup("GFX-INIT") == null);
    try std.testing.expect(machine.lookup("GRAPHICS") != null);

    const words_after = machine.word_count;
    try machine.interpretLine("REQUIRE-GRAPHICS require-graphics");
    try std.testing.expectEqual(words_after, machine.word_count);

    try machine.interpretLine("ALSO GRAPHICS 2 3 GFX-INIT GFX-WIDTH GFX-HEIGHT PREVIOUS");
    try expectStack(machine, &.{ 2, 3 });
    try std.testing.expect(machine.lookup("GFX-INIT") == null);

    try std.testing.expectError(error.InvalidDefinition, machine.interpretLine(": X REQUIRE-GRAPHICS ;"));
}

test "GFX-INIT checks the size, clears the image, and keeps the old one when the host fails" {
    try skipWithout(&.{.graphics});
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    try machine.interpretLine("REQUIRE-GRAPHICS ALSO GRAPHICS GFX-WIDTH GFX-HEIGHT");
    try expectStack(machine, &.{ 0, 0 });
    machine.data_depth = 0;
    try std.testing.expectError(error.NoCanvas, machine.interpretLine("1 1 $FF GFX-PSET"));
    try std.testing.expectError(error.NoCanvas, machine.interpretLine("1 1 GFX-PGET"));
    try std.testing.expectError(error.NoCanvas, machine.interpretLine("0 0 0 0 GFX-HLINE"));
    try std.testing.expectError(error.NoCanvas, machine.interpretLine("0 GFX-CLS"));
    try std.testing.expectError(error.NoCanvas, machine.interpretLine("S\" a.txt\" GFX-SAVE-PPM"));
    try machine.interpretLine("0 ' GFX-CLS CATCH NIP");
    try expectStack(machine, &.{-271});
    machine.data_depth = 0;

    try std.testing.expectError(error.InvalidNumber, machine.interpretLine("0 1 GFX-INIT"));
    try std.testing.expectError(error.InvalidNumber, machine.interpretLine("1 -1 GFX-INIT"));
    try std.testing.expectError(error.InvalidNumber, machine.interpretLine("8193 1 GFX-INIT"));
    try std.testing.expectError(error.InvalidNumber, machine.interpretLine("1 8193 GFX-INIT"));
    // 8192 × 8192 pixels are 256 MiB, over the 64 MiB limit.
    try std.testing.expectError(error.InvalidNumber, machine.interpretLine("8192 8192 GFX-INIT"));
    try std.testing.expectEqual(@as(usize, 4096 * 4096), try words_graphics.imagePixels(4096, 4096));
    try std.testing.expectEqual(@as(usize, 8192 * 2048), try words_graphics.imagePixels(8192, 2048));
    try std.testing.expectError(error.InvalidNumber, words_graphics.imagePixels(4097, 4096));
    try std.testing.expectEqual(@as(usize, 1), try words_graphics.imagePixels(1, 1));

    try machine.interpretLine("4 2 GFX-INIT 3 1 GFX-PGET 0 0 GFX-PGET");
    try expectStack(machine, &.{ 0, 0 });
    try std.testing.expect(std.mem.allEqual(u32, machine.gfx_pixels, 0xff00_0000));
    machine.data_depth = 0;
    try machine.interpretLine("3 1 $ABCDEF GFX-PSET");
    // The host cannot give more pixels than it has: the 4 × 2 image stays.
    try std.testing.expectError(error.MemoryExhausted, machine.interpretLine("1601 1 GFX-INIT"));
    output.framebuffer_fails = true;
    try std.testing.expectError(error.MemoryExhausted, machine.interpretLine("2 2 GFX-INIT"));
    try machine.interpretLine("GFX-WIDTH GFX-HEIGHT 3 1 GFX-PGET");
    try expectStack(machine, &.{ 4, 2, 0xABCDEF });
}

test "GFX-PSET, GFX-PGET, GFX-HLINE, and GFX-CLS stay inside the image" {
    try skipWithout(&.{.graphics});
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    try machine.interpretLine("REQUIRE-GRAPHICS ALSO GRAPHICS 5 3 GFX-INIT");
    // Only the low 24 bits are the color.
    try machine.interpretLine("0 0 $7F112233 GFX-PSET 0 0 GFX-PGET 4 2 -1 GFX-PSET 4 2 GFX-PGET");
    try expectStack(machine, &.{ 0x112233, 0xFFFFFF });
    machine.data_depth = 0;
    try machine.interpretLine("-1 0 1 GFX-PSET 5 0 1 GFX-PSET 0 3 1 GFX-PSET -1 -1 GFX-PGET 5 0 GFX-PGET 0 3 GFX-PGET");
    try expectStack(machine, &.{ -1, -1, -1 });
    machine.data_depth = 0;
    // Of the 15 pixels, only the two set inside the image are not black.
    try std.testing.expectEqual(@as(usize, 13), std.mem.count(u32, machine.gfx_pixels, &.{0xff00_0000}));

    // A line runs from either end, both ends included, and is cut at the edges.
    try machine.interpretLine("$00FF00 GFX-CLS 3 1 1 $0000FF GFX-HLINE -10 100 2 $FF0000 GFX-HLINE");
    try machine.interpretLine("0 1 GFX-PGET 1 1 GFX-PGET 3 1 GFX-PGET 4 1 GFX-PGET 0 2 GFX-PGET 4 2 GFX-PGET 0 0 GFX-PGET");
    try expectStack(machine, &.{ 0x00FF00, 0x0000FF, 0x0000FF, 0x00FF00, 0xFF0000, 0xFF0000, 0x00FF00 });
    machine.data_depth = 0;
    // Rows and columns outside the image draw nothing.
    var before: [15]u32 = undefined;
    @memcpy(&before, machine.gfx_pixels);
    try machine.interpretLine("0 4 -1 1 GFX-HLINE 0 4 3 1 GFX-HLINE 5 9 0 1 GFX-HLINE -5 -1 0 1 GFX-HLINE");
    try std.testing.expectEqualSlices(u32, &before, machine.gfx_pixels);
    try expectStack(machine, &.{});
}

test "GFX-SAVE-PPM and GFX-SAVE-BMP write the image, and return the ior of a failure" {
    try skipWithout(&.{.graphics});
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    try machine.interpretLine("REQUIRE-GRAPHICS ALSO GRAPHICS 3 2 GFX-INIT 0 0 $FF0000 GFX-PSET 2 1 $0080FF GFX-PSET");
    try machine.interpretLine("S\" a.txt\" GFX-SAVE-PPM S\" b.txt\" GFX-SAVE-BMP");
    try expectStack(machine, &.{ 0, 0 });
    const black = "\x00\x00\x00";
    const ppm = "P6\n3 2\n255\n" ++ "\xff\x00\x00" ++ black ++ black ++ black ++ black ++ "\x00\x80\xff";
    try std.testing.expectEqualSlices(u8, ppm, output.files[0].data[0..output.files[0].len]);
    // Rows of 3 pixels take 9 bytes and 3 bytes of padding; the bottom row comes first.
    const bmp = "BM" ++ "\x4e\x00\x00\x00" ++ "\x00\x00\x00\x00" ++ "\x36\x00\x00\x00" ++
        "\x28\x00\x00\x00" ++ "\x03\x00\x00\x00" ++ "\x02\x00\x00\x00" ++ "\x01\x00" ++ "\x18\x00" ++
        "\x00\x00\x00\x00" ++ "\x18\x00\x00\x00" ++ "\x13\x0b\x00\x00" ++ "\x13\x0b\x00\x00" ++
        "\x00\x00\x00\x00" ++ "\x00\x00\x00\x00" ++
        black ++ black ++ "\xff\x80\x00" ++ "\x00\x00\x00" ++
        "\x00\x00\xff" ++ black ++ black ++ "\x00\x00\x00";
    try std.testing.expectEqualSlices(u8, bmp, output.files[1].data[0..output.files[1].len]);

    // A name the host cannot create, and a failing close, give their ior.
    try machine.interpretLine("S\" missing\" GFX-SAVE-BMP");
    try expectStack(machine, &.{ 0, 0, forth.errnoIor(2) });
    output.close_fails = true;
    try machine.interpretLine("S\" a.txt\" GFX-SAVE-PPM");
    try expectStack(machine, &.{ 0, 0, forth.errnoIor(2), forth.errnoIor(5) });
}

test "the graphics library loads into GRAPHICS, and a failure removes everything it added" {
    try skipWithout(&.{.graphics});
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    machine.graphics_library = ": GLIB 42 ;\n: GLIB2\n  GLIB GFX-WIDTH + ;\n";
    try machine.interpretLine("REQUIRE-GRAPHICS GRAPHICS GLIB2 FORTH");
    try expectStack(machine, &.{42});
    try std.testing.expect(machine.lookup("GLIB") == null);

    const failing = try createMachine(&output);
    defer destroyMachine(failing);
    const words_before = failing.word_count;
    const names_before = failing.names_used;
    const here_before = failing.data_here;
    const wordlists_before = failing.wordlistCount();
    failing.graphics_library = ": GOOD 1 ;\nCREATE BUFFER 100 ALLOT\nVOCABULARY INNER\nNO-SUCH-WORD\n";
    try failing.interpretLine("ORDER");
    const order_before = try std.testing.allocator.dupe(u8, output.written());
    defer std.testing.allocator.free(order_before);
    output.len = 0;
    try std.testing.expectError(error.UnknownWord, failing.interpretLine("REQUIRE-GRAPHICS"));
    try std.testing.expectEqual(words_before, failing.word_count);
    try std.testing.expectEqual(names_before, failing.names_used);
    try std.testing.expectEqual(here_before, failing.data_here);
    try std.testing.expectEqual(wordlists_before, failing.wordlistCount());
    try std.testing.expect(!words_graphics.graphicsLoaded(failing));
    try failing.interpretLine("ORDER");
    try std.testing.expectEqualStrings(order_before, output.written());
    const image = try saveImage(failing);
    defer freeImage(image);
    try std.testing.expectEqualStrings("SIGIMG33", image[0..8]);

    // The built-in library loads after the failure.
    failing.graphics_library = words_graphics.library;
    try failing.interpretLine("REQUIRE-GRAPHICS");
    try std.testing.expect(words_graphics.graphicsLoaded(failing));
}

test "an image is SIGIMG33 until the graphics words are loaded, and SIGIMG34 from then on" {
    try skipWithout(&.{ .graphics, .image });
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    try machine.interpretLine(": BEFORE 7 ; MARKER -GFX");
    const plain = try saveImage(machine);
    defer freeImage(plain);
    try std.testing.expectEqualStrings("SIGIMG33", plain[0..8]);

    try machine.interpretLine("REQUIRE-GRAPHICS ALSO GRAPHICS : DRAW 2 2 GFX-INIT 1 1 $123456 GFX-PSET 1 1 GFX-PGET ; PREVIOUS");
    const with_graphics = try saveImage(machine);
    defer freeImage(with_graphics);
    try std.testing.expectEqualStrings("SIGIMG34", with_graphics[0..8]);

    // Restored, the words run, the image is made again, and REQUIRE-GRAPHICS adds nothing.
    const restored = try createMachine(&output);
    defer destroyMachine(restored);
    try restored.restoreImage(with_graphics);
    try std.testing.expectEqual(@as(usize, 0), restored.gfx_pixels.len);
    const words_restored = restored.word_count;
    try restored.interpretLine("REQUIRE-GRAPHICS BEFORE DRAW");
    try std.testing.expectEqual(words_restored, restored.word_count);
    try expectStack(restored, &.{ 7, 0x123456 });

    // After the marker removes the graphics words they load again, at a new place, and
    // images stay SIGIMG34.
    try machine.interpretLine("-GFX");
    try std.testing.expect(!words_graphics.graphicsLoaded(machine));
    const forgotten = try saveImage(machine);
    defer freeImage(forgotten);
    try std.testing.expectEqualStrings("SIGIMG34", forgotten[0..8]);
    try machine.interpretLine(": PAD-WORD ; REQUIRE-GRAPHICS");
    try std.testing.expect(words_graphics.graphicsLoaded(machine));

    // A SIGIMG33 image restores as before and can load the graphics words.
    const old = try createMachine(&output);
    defer destroyMachine(old);
    try old.restoreImage(plain);
    try old.interpretLine("BEFORE REQUIRE-GRAPHICS GRAPHICS 1 1 GFX-INIT GFX-WIDTH");
    try expectStack(old, &.{ 7, 1 });
}

test "LOAD of an image with the graphics words adds them, renumbered, as loaded" {
    try skipWithout(&.{ .graphics, .image });
    var output = Output{};
    const source = try createMachine(&output);
    defer destroyMachine(source);
    try source.interpretLine("REQUIRE-GRAPHICS GRAPHICS DEFINITIONS : SIDE 3 3 GFX-INIT GFX-WIDTH ; FORTH DEFINITIONS");
    const image = try saveImage(source);
    defer freeImage(image);
    const loaded = try createMachine(&output);
    defer destroyMachine(loaded);
    try loaded.restoreImage(image);

    const target = try createMachine(&output);
    defer destroyMachine(target);
    try target.interpretLine(": EXISTING 99 ; VOCABULARY OTHER");
    const plain = try saveImage(target);
    defer freeImage(plain);
    try std.testing.expectEqualStrings("SIGIMG33", plain[0..8]);
    try target.appendImage(loaded);
    try std.testing.expect(words_graphics.graphicsLoaded(target));
    const words_after = target.word_count;
    try target.interpretLine("REQUIRE-GRAPHICS GRAPHICS SIDE EXISTING");
    try std.testing.expectEqual(words_after, target.word_count);
    try expectStack(target, &.{ 3, 99 });
    const appended = try saveImage(target);
    defer freeImage(appended);
    try std.testing.expectEqualStrings("SIGIMG34", appended[0..8]);
    try std.testing.expectEqual(@as(forth.Cell, 1), target.readCellConst(memory_map.graphics_image_address));
}

/// What a failed REQUIRE-GRAPHICS must leave as it was.
const Snapshot = struct {
    words: u16,
    names: u32,
    code: u16,
    here: forth.Cell,
    wordlists: forth.Cell,
    current: forth.Cell,

    fn take(machine: *forth.State) Snapshot {
        return .{ .words = machine.word_count, .names = machine.names_used, .code = machine.code_count, .here = machine.data_here, .wordlists = machine.wordlistCount(), .current = machine.currentWordlist() };
    }

    fn expectSame(self: Snapshot, machine: *forth.State) !void {
        try std.testing.expectEqual(self, take(machine));
        try std.testing.expect(!machine.defining);
        try std.testing.expect(!machine.compiling);
        try std.testing.expectEqual(@as(usize, 0), machine.control_depth);
        try std.testing.expect(machine.lookup("GRAPHICS") == null);
        try std.testing.expect(!words_graphics.graphicsLoaded(machine));
        try std.testing.expectEqual(@as(forth.Cell, 0), machine.readCellConst(memory_map.graphics_image_address));
    }
};

test "a library that fails inside a definition leaves nothing behind, also after the error is reported or caught" {
    try skipWithout(&.{ .graphics, .image });
    var output = Output{};
    // An unknown word, an unclosed IF, and the end of the library inside a definition.
    const libraries = [_][]const u8{ ": BROKEN NO-SUCH-WORD\n", ": OPEN IF ;\n", "VARIABLE V\n: UNFINISHED 1\n" };
    const errors = [_]forth.RuntimeError{ error.UnknownWord, error.ControlMismatch, error.InvalidDefinition };
    for (libraries, errors) |library, expected| {
        const machine = try createMachine(&output);
        defer destroyMachine(machine);
        machine.graphics_library = library;
        const before = Snapshot.take(machine);
        try std.testing.expectError(expected, machine.interpretLine("REQUIRE-GRAPHICS"));
        try before.expectSame(machine);
        // Reporting the error must not bring the removed words back.
        machine.report(expected);
        try before.expectSame(machine);
        output.len = 0;
        const image = try saveImage(machine);
        defer freeImage(image);
        try std.testing.expectEqualStrings("SIGIMG33", image[0..8]);
        try machine.interpretLine(": AFTER 5 ; AFTER");
        try expectStack(machine, &.{5});

        // The same through CATCH and EVALUATE.
        const caught = try createMachine(&output);
        defer destroyMachine(caught);
        caught.graphics_library = library;
        try caught.interpretLine(": TRY-GFX S\" REQUIRE-GRAPHICS\" EVALUATE ;");
        const before_catch = Snapshot.take(caught);
        try caught.interpretLine("' TRY-GFX CATCH 0<>");
        try expectStack(caught, &.{-1});
        try before_catch.expectSame(caught);
        output.len = 0;
    }
}

test "restoring an image into a used machine drops its graphics image, and a failed restore keeps it" {
    try skipWithout(&.{ .graphics, .image });
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    try machine.interpretLine("REQUIRE-GRAPHICS");
    const image = try saveImage(machine);
    defer freeImage(image);
    try machine.interpretLine("GRAPHICS 2 2 GFX-INIT 1 1 $ABCDEF GFX-PSET FORTH");
    try std.testing.expectError(error.InvalidImage, machine.restoreImage(image[0 .. image.len - 1]));
    try machine.interpretLine("GRAPHICS GFX-WIDTH 1 1 GFX-PGET FORTH");
    try expectStack(machine, &.{ 2, 0xABCDEF });
    machine.data_depth = 0;
    try machine.restoreImage(image);
    try std.testing.expectEqual(@as(usize, 0), machine.gfx_pixels.len);
    try machine.interpretLine("GRAPHICS GFX-WIDTH GFX-HEIGHT");
    try expectStack(machine, &.{ 0, 0 });
    try std.testing.expectError(error.NoCanvas, machine.interpretLine("0 GFX-CLS"));
}

test "any value in the cell of the GRAPHICS vocabulary is safe, and a host buffer of the wrong length is not used" {
    try skipWithout(&.{.graphics});
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    const values = [_]forth.Cell{ std.math.maxInt(forth.Cell), std.math.minInt(forth.Cell), -1, machine.word_count, @as(forth.Cell, machine.word_count) - 1, machine.builtin_count };
    for (values) |value| {
        try machine.writeCell(memory_map.graphics_vocabulary_address, value);
        try std.testing.expect(!words_graphics.graphicsLoaded(machine));
    }
    try machine.writeCell(memory_map.graphics_vocabulary_address, 0);
    try machine.interpretLine("REQUIRE-GRAPHICS ALSO GRAPHICS 2 2 GFX-INIT");
    output.framebuffer_short = true;
    try std.testing.expectError(error.HostFailed, machine.interpretLine("3 3 GFX-INIT"));
    try std.testing.expectEqual(@as(usize, 0), machine.gfx_pixels.len);
    try machine.interpretLine("GFX-WIDTH GFX-HEIGHT");
    try expectStack(machine, &.{ 0, 0 });
    try std.testing.expectError(error.NoCanvas, machine.interpretLine("0 0 0 GFX-PSET"));
}

test "the library is read line by line: CR LF, empty lines, the last line without LF, [DO] over lines, REFILL, SOURCE-ID" {
    try skipWithout(&.{.graphics});
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    // SOURCELINE# is one of the file words (not in -Dfiles=false).
    const line_number = if (@import("build_options").files) "SOURCELINE#" else "8";
    machine.graphics_library = "VARIABLE N\r\n3 0 [DO]\r\n1 N +!\r\n[LOOP]\r\n\r\n: NV N @ ;\nSOURCE-ID CONSTANT SID\n" ++ line_number ++ " CONSTANT LINE#\nREFILL DROP\n77 CONSTANT R1\n: LAST 5 ;";
    try machine.interpretLine("REQUIRE-GRAPHICS GRAPHICS NV SID LINE# R1 LAST FORTH");
    // As in a file, REFILL replaces the line, so the DROP after it does not run and its
    // flag stays.
    try expectStack(machine, &.{ -1, 3, -2, 8, 77, 5 });

    // A line longer than the input buffer is an error, and everything is removed.
    const long = try createMachine(&output);
    defer destroyMachine(long);
    long.graphics_library = ": OK 1 ;\n" ++ repeat(" ", forth.tib_size + 1) ++ "\n";
    const before = Snapshot.take(long);
    try std.testing.expectError(error.StringTooLong, long.interpretLine("REQUIRE-GRAPHICS"));
    try before.expectSame(long);
}

test "saving an image larger than the write buffer, and the first ior when a write or the close fails" {
    try skipWithout(&.{.graphics});
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    // 40 × 40 pixels are 4813 bytes of PPM: two writes of the 4096-byte buffer.
    try machine.interpretLine("REQUIRE-GRAPHICS ALSO GRAPHICS 40 40 GFX-INIT $102030 GFX-CLS 39 39 $FFFFFF GFX-PSET S\" a.txt\" GFX-SAVE-PPM");
    try expectStack(machine, &.{0});
    const file = output.files[0].data[0..output.files[0].len];
    try std.testing.expectEqual(@as(usize, 13 + 40 * 40 * 3), file.len);
    try std.testing.expectEqualSlices(u8, "\x10\x20\x30", file[13..16]);
    try std.testing.expectEqualSlices(u8, "\xff\xff\xff", file[file.len - 3 ..]);
    try std.testing.expectEqual(@as(usize, 2), output.file_writes);
    for ([_]usize{ 1, 2 }) |failing| {
        machine.data_depth = 0;
        output.file_writes = 0;
        output.write_fails_at = failing;
        output.close_fails = failing == 2;
        try machine.interpretLine("S\" b.txt\" GFX-SAVE-BMP");
        // The write's ior comes first, the file is closed, and nothing is written after it.
        try expectStack(machine, &.{forth.errnoIor(28)});
        try std.testing.expect(!output.files[1].open);
        try std.testing.expectEqual(failing, output.file_writes);
    }
}

test "a build without graphics loads a SIGIMG34 image and refuses to run its GFX- words" {
    if (@import("build_options").graphics) return error.SkipZigTest;
    try skipWithout(&.{.image});
    var output = Output{};
    const source = try createMachine(&output);
    defer destroyMachine(source);
    // What REQUIRE-GRAPHICS leaves in a build with graphics.
    _ = try source.appendWord("GFX-INIT", .builtin, .gfx_init, 0);
    try source.interpretLine(": USE 1 1 GFX-INIT ;");
    try source.writeCell(memory_map.graphics_image_address, 1);
    const image = try saveImage(source);
    defer freeImage(image);
    try std.testing.expectEqualStrings("SIGIMG34", image[0..8]);
    const restored = try createMachine(&output);
    defer destroyMachine(restored);
    try restored.restoreImage(image);
    try std.testing.expectError(error.InvalidExecutionToken, restored.interpretLine("1 1 GFX-INIT"));
    restored.data_depth = 0;
    try std.testing.expectError(error.InvalidExecutionToken, restored.interpretLine("USE"));
    restored.data_depth = 0;
    try restored.interpretLine("' USE CATCH");
    try std.testing.expectEqual(@as(forth.Cell, -261), restored.data_stack[restored.data_depth - 1]);
}

// ---- The graphics library (G2) ----

/// A machine with the graphics words in the search order and a w × h image.
fn libraryMachine(output: *Output, comptime size: []const u8) !*forth.State {
    const machine = try createMachine(output);
    errdefer destroyMachine(machine);
    try machine.interpretLine("REQUIRE-GRAPHICS ALSO GRAPHICS " ++ size ++ " GFX-INIT");
    return machine;
}

fn pixel(machine: *const forth.State, x: usize, y: usize) u32 {
    return machine.gfx_pixels[y * @as(usize, @intCast(machine.gfx_width)) + x] & 0xffffff;
}

/// The pixels that are not black, as rows of '#' and '.', for comparing shapes.
fn picture(machine: *const forth.State, buffer: []u8) []const u8 {
    const width: usize = @intCast(machine.gfx_width);
    const height: usize = @intCast(machine.gfx_height);
    var at: usize = 0;
    for (0..height) |y| {
        for (0..width) |x| {
            buffer[at] = if (pixel(machine, x, y) != 0) '#' else '.';
            at += 1;
        }
        buffer[at] = '\n';
        at += 1;
    }
    return buffer[0..at];
}

fn expectPicture(machine: *const forth.State, expected: []const u8) !void {
    var buffer: [2048]u8 = undefined;
    try std.testing.expectEqualStrings(expected, picture(machine, &buffer));
}

test "the color words, and the library loads in any BASE and leaves BASE as it was" {
    try skipWithout(&.{.graphics});
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    try machine.interpretLine("HEX REQUIRE-GRAPHICS BASE @ DECIMAL ALSO GRAPHICS COLOR@ 18 52 86 RGB 256 -1 0 RGB");
    try expectStack(machine, &.{ 16, 0xFFFFFF, 0x123456, 0x00FF00 });
    machine.data_depth = 0;
    try machine.interpretLine("1 2 3 COLOR COLOR@ $7F654321 COLOR! COLOR@");
    try expectStack(machine, &.{ 0x010203, 0x654321 });
    machine.data_depth = 0;
    if (!@import("build_options").help) return;
    try machine.interpretLine("HELP RGB");
    try std.testing.expectEqualStrings("RGB ( r g b -- rgb )\n  The color $RRGGBB of red, green, and blue, each 0 to 255 (FORTH/Sigma graphics).\n", output.written());
}

test "the drawing words need an image, as the GFX- words do" {
    try skipWithout(&.{.graphics});
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    try machine.interpretLine("REQUIRE-GRAPHICS ALSO GRAPHICS");
    const words = [_][]const u8{ "0 0 PSET", "CLS", "0 0 1 1 LINE", "0 0 1 1 RECT", "0 0 1 1 FILL-RECT", "0 0 1 CIRCLE", "0 0 1 FILL-CIRCLE", "0 0 PAINT", "S\" a.txt\" SAVE-BMP" };
    for (words) |word| {
        machine.data_depth = 0;
        var line: [64]u8 = undefined;
        const text = try std.fmt.bufPrint(&line, ": T {s} ; ' T CATCH", .{word});
        try machine.interpretLine(text);
        try std.testing.expectEqual(@as(forth.Cell, -271), machine.data_stack[machine.data_depth - 1]);
    }
}

test "LINE draws both ends, in every direction, and cuts lines at the edges" {
    try skipWithout(&.{.graphics});
    var output = Output{};
    const machine = try libraryMachine(&output, "8 6");
    defer destroyMachine(machine);
    try machine.interpretLine("1 1 6 1 LINE 0 5 0 2 LINE 7 0 3 4 LINE 2 2 2 2 LINE");
    try expectPicture(machine,
        \\.......#
        \\.######.
        \\#.#..#..
        \\#...#...
        \\#..#....
        \\#.......
        \\
    );
    // A steep line and its reverse cover the same pixels here.
    try machine.interpretLine("CLS 1 0 3 5 LINE");
    var forward: [64]u8 = undefined;
    const drawn = picture(machine, &forward);
    try machine.interpretLine("CLS 3 5 1 0 LINE");
    try expectPicture(machine, drawn);

    // The part inside the image of a line with far ends is the same as of a short one.
    try machine.interpretLine("CLS 0 0 5 5 LINE");
    var short: [64]u8 = undefined;
    const diagonal = picture(machine, &short);
    try machine.interpretLine("CLS -1000000000000 -1000000000000 1000000000000 1000000000000 LINE");
    try expectPicture(machine, diagonal);
    try machine.interpretLine("CLS -9223372036854775807 0 9223372036854775807 0 LINE");
    try expectPicture(machine, "########\n" ++ repeat("........\n", 5));
    // Lines wholly outside draw nothing.
    try machine.interpretLine("CLS -5 -5 -1 100 LINE 8 0 8 5 LINE 0 6 7 9 LINE");
    try expectPicture(machine, repeat("........\n", 6));
    try expectStack(machine, &.{});
}

test "RECT and FILL-RECT draw w by h pixels from the top left corner, cut at the edges" {
    try skipWithout(&.{.graphics});
    var output = Output{};
    const machine = try libraryMachine(&output, "8 6");
    defer destroyMachine(machine);
    try machine.interpretLine("1 1 4 3 RECT 6 4 1 1 RECT");
    try expectPicture(machine,
        \\........
        \\.####...
        \\.#..#...
        \\.####...
        \\......#.
        \\........
        \\
    );
    try machine.interpretLine("CLS 5 3 10 10 FILL-RECT -3 -3 5 5 RECT 2 2 0 5 FILL-RECT 2 2 5 -1 RECT");
    try expectPicture(machine,
        \\.#......
        \\##......
        \\........
        \\.....###
        \\.....###
        \\.....###
        \\
    );
    // Far corners and huge sizes are limited to 2^61, which still covers the image.
    try machine.interpretLine("CLS -1000000000000000000 -1000000000000000000 9223372036854775807 9223372036854775807 FILL-RECT");
    try std.testing.expect(std.mem.allEqual(u32, machine.gfx_pixels, 0xffffffff));
    try expectStack(machine, &.{});
}

test "CIRCLE and FILL-CIRCLE: small radii, symmetry, the outline inside the disc, and far circles" {
    try skipWithout(&.{.graphics});
    var output = Output{};
    const machine = try libraryMachine(&output, "11 11");
    defer destroyMachine(machine);
    try machine.interpretLine("5 5 0 CIRCLE 1 1 1 CIRCLE 8 8 -1 CIRCLE 8 8 -1 FILL-CIRCLE");
    try expectPicture(machine,
        \\.#.........
        \\#.#........
        \\.#.........
        \\...........
        \\...........
        \\.....#.....
        \\...........
        \\...........
        \\...........
        \\...........
        \\...........
        \\
    );
    // The shapes of the midpoint circle algorithm.
    try machine.interpretLine("CLS 5 5 3 FILL-CIRCLE 5 5 2 CIRCLE");
    try expectPicture(machine,
        \\...........
        \\...........
        \\....###....
        \\...#####...
        \\..#######..
        \\..#######..
        \\..#######..
        \\...#####...
        \\....###....
        \\...........
        \\...........
        \\
    );
    try machine.interpretLine("CLS 5 5 5 CIRCLE");
    try expectPicture(machine,
        \\...#####...
        \\..#.....#..
        \\.#.......#.
        \\#.........#
        \\#.........#
        \\#.........#
        \\#.........#
        \\#.........#
        \\.#.......#.
        \\..#.....#..
        \\...#####...
        \\
    );
    try machine.interpretLine("CLS 5 5 5 CIRCLE");
    // Symmetric about both axes and the diagonal.
    for (0..11) |y| {
        for (0..11) |x| {
            const on = pixel(machine, x, y) != 0;
            try std.testing.expectEqual(on, pixel(machine, 10 - x, y) != 0);
            try std.testing.expectEqual(on, pixel(machine, x, 10 - y) != 0);
            try std.testing.expectEqual(on, pixel(machine, y, x) != 0);
        }
    }
    // Every outline pixel is in the disc, and the outline is closed: painting inside
    // does not reach the corners.
    try machine.interpretLine("0 0 255 COLOR 5 5 PAINT 255 255 255 COLOR 5 5 5 FILL-CIRCLE");
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u32, machine.gfx_pixels, &.{0xff0000ff}));
    try machine.interpretLine("CLS 5 5 5 CIRCLE 0 0 255 COLOR 5 5 PAINT");
    try std.testing.expectEqual(@as(u32, 0), pixel(machine, 0, 0));
    try std.testing.expectEqual(@as(u32, 0x0000FF), pixel(machine, 5, 5));

    // Circles far away or with huge radii cost one step a row. The lowest point of this
    // circle is on row 0, where its flat bottom covers the whole row; the disc far below
    // (its center is limited to 2^30) draws nothing.
    try machine.interpretLine("CLS 255 255 255 COLOR 5 -1000000000 1000000000 CIRCLE 5 5000000000 10 FILL-CIRCLE");
    try std.testing.expect(std.mem.allEqual(u32, machine.gfx_pixels[0..11], 0xffffffff));
    try std.testing.expectEqual(@as(usize, 11), std.mem.count(u32, machine.gfx_pixels, &.{0xffffffff}));
    try machine.interpretLine("CLS 5 5 100000000000 FILL-CIRCLE");
    try std.testing.expect(std.mem.allEqual(u32, machine.gfx_pixels, 0xffffffff));
    try expectStack(machine, &.{});
}

test "PAINT fills the area of one color, grows its stack, and does nothing on the same color or outside" {
    try skipWithout(&.{.graphics});
    var output = Output{};
    const machine = try libraryMachine(&output, "200 8");
    defer destroyMachine(machine);
    // A comb: 100 teeth on every other column below row 0, so row 1 has 100 runs to do,
    // more than the 64 the stack starts with.
    try machine.interpretLine(": TEETH 200 1 DO I 1 I 7 LINE 2 +LOOP ; TEETH");
    const black = std.mem.count(u32, machine.gfx_pixels, &.{0xff000000});
    try machine.interpretLine("255 0 0 COLOR 0 0 PAINT");
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u32, machine.gfx_pixels, &.{0xff000000}));
    try std.testing.expectEqual(black, std.mem.count(u32, machine.gfx_pixels, &.{0xffff0000}));
    // The heap is free again.
    try machine.interpretLine("1000 ALLOCATE THROW FREE THROW");
    // Same color, outside, and a single pixel area.
    try machine.interpretLine("0 0 PAINT -1 0 PAINT 0 40 PAINT 0 255 0 COLOR 1 5 PAINT");
    try std.testing.expectEqual(@as(usize, 7), std.mem.count(u32, machine.gfx_pixels, &.{0xff00ff00}));
    try expectStack(machine, &.{});
}

test "SAVE-BMP and SAVE-PPM throw the ior of a failure" {
    try skipWithout(&.{.graphics});
    var output = Output{};
    const machine = try libraryMachine(&output, "2 2");
    defer destroyMachine(machine);
    try machine.interpretLine("S\" a.txt\" SAVE-PPM S\" b.txt\" SAVE-BMP");
    try expectStack(machine, &.{});
    try machine.interpretLine(": T S\" missing\" SAVE-BMP ; ' T CATCH");
    try expectStack(machine, &.{forth.errnoIor(2)});
}

test "LOCATE and WHERE show the lines of the embedded library, without a file" {
    try skipWithout(&.{ .graphics, .tools });
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    machine.graphics_library = "\\ test library\r\n: G1 1 ;\r\n: G2\r\n  G1 G1 ;\r\n";
    try machine.interpretLine("REQUIRE-GRAPHICS ALSO GRAPHICS LOCATE G2 WHERE G1");
    try std.testing.expectEqualStrings("*graphics library*:3\n: G2\n  G1 G1 ;\n" ++
        "\n*graphics library*:4:3: G1 G1 ;" ++ repeat(" ", 79 - 31) ++ "0" ++
        "\n*graphics library*:4:6: G1 G1 ;" ++ repeat(" ", 79 - 31) ++ "1", output.written());

    // The built-in library: LOCATE shows the definition from this build's text.
    const built_in = try createMachine(&output);
    defer destroyMachine(built_in);
    output.len = 0;
    try built_in.interpretLine("REQUIRE-GRAPHICS ALSO GRAPHICS LOCATE PSET");
    try std.testing.expect(std.mem.startsWith(u8, output.written(), "*graphics library*:"));
    try std.testing.expect(std.mem.indexOf(u8, output.written(), ": PSET ( x y -- )") != null);
}

// ---- The library against independent references ----

const ref_size = 40;
const Bitmap = [ref_size][ref_size]bool;

fn setRef(bitmap: *Bitmap, x: i64, y: i64) void {
    if (x < 0 or y < 0 or x >= ref_size or y >= ref_size) return;
    bitmap[@intCast(y)][@intCast(x)] = true;
}

/// The midpoint circle algorithm, walking the first octant and mirroring it.
fn midpointCircle(bitmap: *Bitmap, cx: i64, cy: i64, r: i64, fill: bool) void {
    var x: i64 = 0;
    var y: i64 = r;
    var d: i64 = 1 - r;
    while (x <= y) {
        const points = [_][2]i64{ .{ x, y }, .{ y, x } };
        for (points) |p| {
            for ([_]i64{ -1, 1 }) |sy| {
                if (fill) {
                    var column = cx - p[0];
                    while (column <= cx + p[0]) : (column += 1) setRef(bitmap, column, cy + sy * p[1]);
                } else for ([_]i64{ -1, 1 }) |sx| setRef(bitmap, cx + sx * p[0], cy + sy * p[1]);
            }
        }
        if (d < 0) {
            d += 2 * x + 3;
        } else {
            d += 2 * (x - y) + 5;
            y -= 1;
        }
        x += 1;
    }
}

/// Bresenham's line, as an independent reference.
fn bresenham(bitmap: *Bitmap, x1_in: i64, y1_in: i64, x2: i64, y2: i64) void {
    var x1 = x1_in;
    var y1 = y1_in;
    const dx: i64 = @intCast(@abs(x2 - x1));
    const dy: i64 = -@as(i64, @intCast(@abs(y2 - y1)));
    const sx: i64 = if (x1 < x2) 1 else -1;
    const sy: i64 = if (y1 < y2) 1 else -1;
    var err = dx + dy;
    while (true) {
        setRef(bitmap, x1, y1);
        if (x1 == x2 and y1 == y2) return;
        const e2 = 2 * err;
        if (e2 >= dy) {
            err += dy;
            x1 += sx;
        }
        if (e2 <= dx) {
            err += dx;
            y1 += sy;
        }
    }
}

fn expectBitmap(machine: *const forth.State, expected: *const Bitmap, what: []const u8) !void {
    for (0..ref_size) |y| {
        for (0..ref_size) |x| {
            if ((pixel(machine, x, y) != 0) != expected[y][x]) {
                std.debug.print("{s}: pixel {d} {d} differs\n", .{ what, x, y });
                return error.TestExpectedEqual;
            }
        }
    }
}

test "CIRCLE and FILL-CIRCLE have the pixels of the midpoint circle algorithm, also cut at the edges" {
    try skipWithout(&.{.graphics});
    var output = Output{};
    const machine = try libraryMachine(&output, "40 40");
    defer destroyMachine(machine);
    const centers = [_][2]i64{ .{ 20, 20 }, .{ 0, 0 }, .{ -10, 25 }, .{ 39, 45 }, .{ 17, -30 } };
    for (centers) |center| {
        var r: i64 = 0;
        while (r <= 64) : (r += 1) {
            for ([_]bool{ false, true }) |fill| {
                var line: [80]u8 = undefined;
                const text = try std.fmt.bufPrint(&line, "CLS {d} {d} {d} {s}", .{ center[0], center[1], r, if (fill) "FILL-CIRCLE" else "CIRCLE" });
                try machine.interpretLine(text);
                var expected: Bitmap = @splat(@splat(false));
                midpointCircle(&expected, center[0], center[1], r, fill);
                try expectBitmap(machine, &expected, text);
            }
        }
    }
    try expectStack(machine, &.{});
}

test "LINE between any two points of the image is Bresenham's line from the first point" {
    try skipWithout(&.{.graphics});
    var output = Output{};
    const machine = try libraryMachine(&output, "40 40");
    defer destroyMachine(machine);
    // Ends on a coarse grid cover the eight directions, both orders, and steep, flat,
    // and diagonal lines.
    const ends = [_]i64{ 0, 1, 7, 20, 38, 39 };
    for (ends) |x1| {
        for (ends) |y1| {
            for (ends) |x2| {
                for (ends) |y2| {
                    var line: [64]u8 = undefined;
                    const text = try std.fmt.bufPrint(&line, "CLS {d} {d} {d} {d} LINE", .{ x1, y1, x2, y2 });
                    try machine.interpretLine(text);
                    var expected: Bitmap = @splat(@splat(false));
                    bresenham(&expected, x1, y1, x2, y2);
                    try expectBitmap(machine, &expected, text);
                }
            }
        }
    }
    try expectStack(machine, &.{});
}

test "PAINT gives CANNOT ALLOCATE MEMORY when its stack cannot be made or grown, and frees it" {
    try skipWithout(&.{.graphics});
    var output = Output{};
    const machine = try libraryMachine(&output, "200 8");
    defer destroyMachine(machine);
    // The heap is 917504 bytes, and each block takes 16 bytes more. Leaving 1000 bytes,
    // the 1024-byte stack cannot be made.
    try machine.interpretLine("916488 ALLOCATE THROW VALUE BIG : T 0 0 PAINT ; ' T CATCH");
    try expectStack(machine, &.{-524});
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u32, machine.gfx_pixels, &.{0xffffffff}));
    machine.data_depth = 0;
    // Leaving 1600 bytes, the stack is made but cannot grow past its 64 entries for the
    // 100 runs of the comb: part of the area is filled, and the stack is freed.
    try machine.interpretLine("BIG FREE THROW 915888 ALLOCATE THROW TO BIG");
    try machine.interpretLine(": TEETH 200 1 DO I 1 I 7 LINE 2 +LOOP ; TEETH 255 0 0 COLOR ' T CATCH");
    try expectStack(machine, &.{-524});
    try std.testing.expect(std.mem.count(u32, machine.gfx_pixels, &.{0xffff0000}) > 0);
    machine.data_depth = 0;
    try machine.interpretLine("1500 ALLOCATE THROW FREE THROW");
    try expectStack(machine, &.{});
}

test "BASE is restored when the library fails to load" {
    try skipWithout(&.{.graphics});
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    machine.graphics_library = "10 CONSTANT TEN\nNO-SUCH-WORD\n";
    try machine.interpretLine("HEX");
    try std.testing.expectError(error.UnknownWord, machine.interpretLine("REQUIRE-GRAPHICS"));
    try machine.interpretLine("BASE @ DECIMAL");
    try expectStack(machine, &.{16});
}

// ---- Showing the image (G3) ----

test "GFX-SHOW-BLOCKS writes two pixels a cell in 24-bit colors, as UTF-8 the host is told of" {
    try skipWithout(&.{.graphics});
    var output = Output{};
    const machine = try libraryMachine(&output, "2 3");
    defer destroyMachine(machine);
    try machine.interpretLine("$FF0000 COLOR! 0 0 PSET $00FF00 COLOR! 0 1 PSET $0000FF COLOR! 1 1 PSET $FFFFFF COLOR! 0 2 PSET");
    output.len = 0;
    try machine.interpretLine("GFX-SHOW-BLOCKS");
    try std.testing.expectEqualStrings("\x1b[38;2;255;0;0m\x1b[48;2;0;255;0m\u{2580}\x1b[38;2;0;0;0m\x1b[48;2;0;0;255m\u{2580}\x1b[0m\n" ++
        "\x1b[38;2;255;255;255m\x1b[49m\u{2580}\x1b[38;2;0;0;0m\u{2580}\x1b[0m\n", output.written());
    try std.testing.expectEqualStrings("+-", output.utf8_calls[0..output.utf8_count]);
}

test "an image larger than the terminal is made smaller, keeping its proportions, by averaging" {
    try skipWithout(&.{.graphics});
    var output = Output{ .terminal_columns = 2, .terminal_rows = 2 };
    const machine = try libraryMachine(&output, "4 2");
    defer destroyMachine(machine);
    // Two columns and one row for the image: 2 × 2 pixels, from blocks of 2 × 2.
    try machine.interpretLine("$FF0000 COLOR! 0 0 PSET 0 1 PSET $0000FF COLOR! 1 0 PSET 1 1 PSET $FFFFFF COLOR! 2 1 PSET 3 1 PSET");
    output.len = 0;
    try machine.interpretLine("GFX-SHOW-BLOCKS");
    try std.testing.expectEqualStrings("\x1b[38;2;128;0;128m\x1b[49m\u{2580}\x1b[38;2;128;128;128m\u{2580}\x1b[0m\n", output.written());
    // A tall image is limited by the rows: 2 rows (4 pixels) of the 2-row terminal less
    // the line for the prompt.
    output.terminal_columns = 80;
    output.terminal_rows = 3;
    try machine.interpretLine("1 9 GFX-INIT");
    output.len = 0;
    try machine.interpretLine("GFX-SHOW-BLOCKS");
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, output.written(), "\u{2580}"));
}

test "GFX-SHOW-SIXEL writes the image as Sixel graphics with the colors of a 6 x 6 x 6 cube" {
    try skipWithout(&.{.graphics});
    var output = Output{};
    const machine = try libraryMachine(&output, "2 1");
    defer destroyMachine(machine);
    try machine.interpretLine("$FF0000 COLOR! 0 0 PSET $0000FF COLOR! 1 0 PSET");
    output.len = 0;
    try machine.interpretLine("GFX-SHOW-SIXEL");
    var expected: [4096]u8 = undefined;
    var at: usize = 0;
    at += (try std.fmt.bufPrint(expected[at..], "\x1bPq\"1;1;2;1", .{})).len;
    for (0..216) |register| at += (try std.fmt.bufPrint(expected[at..], "#{d};2;{d};{d};{d}", .{ register, register / 36 * 20, register / 6 % 6 * 20, register % 6 * 20 })).len;
    // Blue is register 5 and red register 180; each paints its own column of the band.
    at += (try std.fmt.bufPrint(expected[at..], "#5?@$#180@?$-\x1b\\", .{})).len;
    try std.testing.expectEqualStrings(expected[0..at], output.written());
}

test "SHOW goes to the window when the host has one, or to the terminal, as chosen" {
    try skipWithout(&.{.graphics});
    var output = Output{ .has_window = true };
    const machine = try libraryMachine(&output, "3 2");
    defer destroyMachine(machine);
    try machine.interpretLine("$123456 GFX-CLS GFX-WINDOW? SHOW");
    try expectStack(machine, &.{-1});
    try std.testing.expectEqual(@as(usize, 1), output.window_shows);
    try std.testing.expectEqual(@as(u32, 3), output.window_width);
    try std.testing.expectEqual(@as(u32, 2), output.window_height);
    try std.testing.expectEqual(@as(u32, 0xff123456), output.window_first_pixel);
    output.len = 0;
    try machine.interpretLine("DISPLAY-TERMINAL SHOW");
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "\u{2580}") != null);
    output.len = 0;
    try machine.interpretLine("TERMINAL-SIXEL SHOW");
    try std.testing.expect(std.mem.startsWith(u8, output.written(), "\x1bPq"));
    try machine.interpretLine("TERMINAL-BLOCKS DISPLAY-WINDOW SHOW");
    try std.testing.expectEqual(@as(usize, 2), output.window_shows);
    machine.data_depth = 0;

    // Without a window, SHOW uses the terminal and DISPLAY-WINDOW is refused.
    var plain = Output{};
    const terminal = try libraryMachine(&plain, "3 2");
    defer destroyMachine(terminal);
    plain.len = 0;
    try terminal.interpretLine("GFX-WINDOW? SHOW");
    try std.testing.expect(std.mem.indexOf(u8, plain.written(), "\u{2580}") != null);
    try terminal.interpretLine("' DISPLAY-WINDOW CATCH");
    try expectStack(terminal, &.{ 0, -21 });
    try std.testing.expectError(error.HostUnavailable, terminal.interpretLine("GFX-SHOW-WINDOW"));
    // No image: the same error as the other words.
    const empty = try createMachine(&plain);
    defer destroyMachine(empty);
    try std.testing.expectError(error.NoCanvas, empty.interpretLine("REQUIRE-GRAPHICS ALSO GRAPHICS SHOW"));
}

/// Decodes Sixel graphics into color registers (0xff where nothing is drawn), as an
/// independent check of GFX-SHOW-SIXEL.
fn decodeSixel(text: []const u8, grid: [][16]u8, width: *usize, height: *usize) !void {
    if (!std.mem.startsWith(u8, text, "\x1bPq\"1;1;") or !std.mem.endsWith(u8, text, "\x1b\\")) return error.TestUnexpectedResult;
    var at: usize = 8;
    const readNumber = struct {
        fn read(bytes: []const u8, cursor: *usize) usize {
            var value: usize = 0;
            while (cursor.* < bytes.len and std.ascii.isDigit(bytes[cursor.*])) : (cursor.* += 1) value = value * 10 + bytes[cursor.*] - '0';
            return value;
        }
    }.read;
    width.* = readNumber(text, &at);
    at += 1;
    height.* = readNumber(text, &at);
    for (grid) |*row| row.* = @splat(0xff);
    var color: u8 = 0;
    var x: usize = 0;
    var band: usize = 0;
    while (at < text.len - 2) {
        const char = text[at];
        at += 1;
        switch (char) {
            '#' => {
                const register = readNumber(text, &at);
                if (at < text.len and text[at] == ';') {
                    // A color definition: #n;2;r;g;b.
                    while (at < text.len and (text[at] == ';' or std.ascii.isDigit(text[at]))) at += 1;
                } else color = @intCast(register);
            },
            '$' => x = 0,
            '-' => {
                x = 0;
                band += 1;
            },
            '!' => {
                const count = readNumber(text, &at);
                const sixel = text[at];
                at += 1;
                for (0..count) |_| {
                    paintSixel(grid, x, band, sixel - 63, color);
                    x += 1;
                }
            },
            '?'...'~' => {
                paintSixel(grid, x, band, char - 63, color);
                x += 1;
            },
            else => return error.TestUnexpectedResult,
        }
    }
}

fn paintSixel(grid: [][16]u8, x: usize, band: usize, bits: u8, color: u8) void {
    for (0..6) |line| {
        if (bits & (@as(u8, 1) << @intCast(line)) != 0) grid[band * 6 + line][x] = color;
    }
}

test "the Sixel output decodes to the image's colors for heights of 1, 5, 6, 7, and 13, with runs" {
    try skipWithout(&.{.graphics});
    var output = Output{};
    const machine = try libraryMachine(&output, "1 1");
    defer destroyMachine(machine);
    for ([_]u32{ 1, 5, 6, 7, 13 }) |image_height| {
        var line: [64]u8 = undefined;
        try machine.interpretLine(try std.fmt.bufPrint(&line, "16 {d} GFX-INIT", .{image_height}));
        // Runs of one color on the left, a different color for every pixel on the right.
        for (0..image_height) |y| for (0..16) |x| {
            const rgb: u32 = if (x < 6) 0x33cc99 else @as(u32, @intCast((x * 37) & 0xff)) << 16 | @as(u32, @intCast((y * 53) & 0xff)) << 8 | @as(u32, @intCast(((x + y) * 29) & 0xff));
            machine.gfx_pixels[y * 16 + x] = 0xff000000 | rgb;
        };
        output.len = 0;
        try machine.interpretLine("GFX-SHOW-SIXEL");
        var grid: [18][16]u8 = undefined;
        var width: usize = 0;
        var height: usize = 0;
        try decodeSixel(output.written(), &grid, &width, &height);
        try std.testing.expectEqual(@as(usize, 16), width);
        try std.testing.expectEqual(@as(usize, image_height), height);
        for (0..image_height) |y| for (0..16) |x| {
            const rgb = machine.gfx_pixels[y * 16 + x];
            const r = (((rgb >> 16) & 0xff) * 5 + 127) / 255;
            const g = (((rgb >> 8) & 0xff) * 5 + 127) / 255;
            const b = ((rgb & 0xff) * 5 + 127) / 255;
            try std.testing.expectEqual(@as(u8, @intCast(r * 36 + g * 6 + b)), grid[y][x]);
        };
        // Nothing below the image.
        for (image_height..18) |y| try std.testing.expect(std.mem.allEqual(u8, &grid[y], 0xff));
        try std.testing.expect(std.mem.indexOf(u8, output.written(), "!6") != null);
    }
}

test "half block output longer than the output buffer comes out whole" {
    try skipWithout(&.{.graphics});
    var output = Output{};
    const machine = try libraryMachine(&output, "80 10");
    defer destroyMachine(machine);
    // Every pixel differs from its neighbors, so every cell has two color escapes.
    for (machine.gfx_pixels, 0..) |*value, index| value.* = 0xff000000 | @as(u32, @intCast(index * 2654435761 & 0xffffff));
    output.len = 0;
    try machine.interpretLine("GFX-SHOW-BLOCKS");
    const text = output.written();
    try std.testing.expect(text.len > 4096);
    try std.testing.expectEqual(@as(usize, 400), std.mem.count(u8, text, "\u{2580}"));
    try std.testing.expectEqual(@as(usize, 5), std.mem.count(u8, text, "\x1b[0m\n"));
    try std.testing.expectEqual(@as(usize, 400), std.mem.count(u8, text, "\x1b[38;2;"));
    try std.testing.expectEqual(@as(usize, 400), std.mem.count(u8, text, "\x1b[48;2;"));
    try std.testing.expect(std.mem.endsWith(u8, text, "\x1b[0m\n"));
}

test "GFX-SAVE-PNG writes a PNG whose chunks, stored blocks, Adler-32, and pixels check out" {
    try skipWithout(&.{.graphics});
    var output = Output{};
    const machine = try libraryMachine(&output, "20 20");
    defer destroyMachine(machine);
    for (machine.gfx_pixels, 0..) |*value, index| value.* = 0xff000000 | @as(u32, @intCast(index * 40503 & 0xffffff));
    try machine.interpretLine("S\" a.txt\" GFX-SAVE-PNG S\" b.txt\" SAVE-PNG");
    try expectStack(machine, &.{0});
    const file = output.files[0].data[0..output.files[0].len];
    try std.testing.expectEqualSlices(u8, output.files[0].data[0..output.files[0].len], output.files[1].data[0..output.files[1].len]);
    try std.testing.expectEqualSlices(u8, "\x89PNG\r\n\x1a\n", file[0..8]);
    var at: usize = 8;
    var kinds: [3][4]u8 = undefined;
    var count: usize = 0;
    var idat: []const u8 = &.{};
    while (at < file.len) : (count += 1) {
        const length = std.mem.readInt(u32, file[at..][0..4], .big);
        const kind = file[at + 4 ..][0..4];
        const body = file[at + 8 ..][0..length];
        const crc = std.mem.readInt(u32, file[at + 8 + length ..][0..4], .big);
        var check = std.hash.Crc32.init();
        check.update(kind);
        check.update(body);
        try std.testing.expectEqual(check.final(), crc);
        kinds[count] = kind.*;
        if (std.mem.eql(u8, kind, "IHDR")) {
            try std.testing.expectEqualSlices(u8, &.{ 0, 0, 0, 20, 0, 0, 0, 20, 8, 2, 0, 0, 0 }, body);
        }
        if (std.mem.eql(u8, kind, "IDAT")) idat = body;
        at += 12 + length;
    }
    try std.testing.expectEqual(file.len, at);
    try std.testing.expectEqualStrings("IHDRIDATIEND", std.mem.sliceAsBytes(kinds[0..count]));
    // zlib: header, one stored block with BFINAL, the data, and the Adler-32 of the data.
    try std.testing.expectEqualSlices(u8, &.{ 0x78, 0x01, 1 }, idat[0..3]);
    const length = std.mem.readInt(u16, idat[3..5], .little);
    try std.testing.expectEqual(@as(u16, 20 * (1 + 3 * 20)), length);
    try std.testing.expectEqual(~length, std.mem.readInt(u16, idat[5..7], .little));
    const raw = idat[7..][0..length];
    var a: u32 = 1;
    var b: u32 = 0;
    for (raw) |value| {
        a = (a + value) % 65521;
        b = (b + a) % 65521;
    }
    try std.testing.expectEqual((b << 16) | a, std.mem.readInt(u32, idat[7 + length ..][0..4], .big));
    try std.testing.expectEqual(idat.len, 7 + length + 4);
    for (0..20) |y| {
        try std.testing.expectEqual(@as(u8, 0), raw[y * 61]);
        for (0..20) |x| {
            const value = machine.gfx_pixels[y * 20 + x];
            const at_pixel = y * 61 + 1 + 3 * x;
            try std.testing.expectEqualSlices(u8, &.{ @truncate(value >> 16), @truncate(value >> 8), @truncate(value) }, raw[at_pixel..][0..3]);
        }
    }
    try machine.interpretLine(": T S\" missing\" SAVE-PNG ; ' T CATCH");
    try expectStack(machine, &.{ 0, forth.errnoIor(2) });
}

test "X-RANGE, Y-RANGE, MPSET, MLINE, AXES, and PLOT draw in mathematical coordinates" {
    try skipWithout(&.{.graphics});
    try support.skipWithoutFloat();
    var output = Output{};
    const machine = try libraryMachine(&output, "9 5");
    defer destroyMachine(machine);
    // At first x and y go from -1 to 1, with y upward.
    try machine.interpretLine("AXES");
    try expectPicture(machine,
        \\....#....
        \\....#....
        \\#########
        \\....#....
        \\....#....
        \\
    );
    // A coordinate that is NaN draws nothing; far and infinite ones are limited.
    try machine.interpretLine("CLS 1e0 1e0 MPSET -1e0 -1e0 MPSET 0e0 0e0 F/ 0e0 MPSET 0e0 0e0 0e0 0e0 0e0 F/ MLINE");
    try expectPicture(machine,
        \\........#
        \\.........
        \\.........
        \\.........
        \\#........
        \\
    );
    // Pixel positions beyond 2^61 are moved there, as LINE does with integers: the ends
    // of this line go to (-2^61, 2^61) and (2^61, -2^61), so that only 0 0 is drawn.
    try machine.interpretLine("CLS -1e300 -1e300 1e300 1e300 MLINE 1e0 0e0 F/ FDUP MPSET");
    try expectPicture(machine, "#........\n" ++ repeat(".........\n", 4));
    try machine.interpretLine("CLS -1e0 -1e0 1e0 -1e0 MLINE");
    try expectPicture(machine, repeat(".........\n", 4) ++ "#########\n");
    // The graph joins the columns with lines, and has a gap where y is NaN.
    try machine.interpretLine("CLS : SQ ( F: x -- y ) FDUP F* ; ' SQ PLOT");
    try expectPicture(machine,
        \\#.......#
        \\.#.....#.
        \\..#####..
        \\.........
        \\.........
        \\
    );
    try machine.interpretLine("CLS : GAP ( F: x -- y ) FDUP F0< IF FDROP 0e0 0e0 F/ THEN ; ' GAP PLOT");
    try expectPicture(machine,
        \\.......##
        \\......#..
        \\....##...
        \\.........
        \\.........
        \\
    );
    try machine.interpretLine("CLS 0e0 4e0 X-RANGE 0e0 2e0 Y-RANGE ' FSQRT PLOT");
    try expectPicture(machine,
        \\.......##
        \\....###..
        \\..##.....
        \\.#.......
        \\#........
        \\
    );
    // An axis outside the range is not drawn, and one at the edge is.
    try machine.interpretLine("CLS 1e0 2e0 X-RANGE 0e0 1e0 Y-RANGE AXES");
    try expectPicture(machine, repeat(".........\n", 4) ++ "#########\n");
    try expectStack(machine, &.{});
    try support.expectFloatStack(machine, &.{});

    // An empty, reversed, or infinite range is a NUMBER ERROR, and the range stays.
    const ranges = [_][]const u8{ "1e0 1e0 X-RANGE", "2e0 1e0 Y-RANGE", "-1e0 0e0 F/ 1e0 0e0 F/ X-RANGE", "0e0 0e0 0e0 F/ Y-RANGE" };
    for (ranges) |range| {
        var line: [96]u8 = undefined;
        machine.data_depth = 0;
        machine.float_depth = 0;
        try machine.interpretLine(try std.fmt.bufPrint(&line, ": T {s} ; ' T CATCH", .{range}));
        try expectStack(machine, &.{-24});
    }
    machine.data_depth = 0;
    machine.float_depth = 0;
    try machine.interpretLine("CLS AXES");
    try expectPicture(machine, repeat(".........\n", 4) ++ "#########\n");

    // In an image one pixel wide, the graph has the y at the left end of the range.
    try machine.interpretLine("1 3 GFX-INIT -1e0 1e0 X-RANGE -1e0 1e0 Y-RANGE ' SQ PLOT");
    try expectPicture(machine, "#\n.\n.\n");
    // The words need an image, and are described by HELP.
    const words = [_][]const u8{ "0e0 0e0 MPSET", "0e0 0e0 1e0 1e0 MLINE", "AXES", "['] SQ PLOT" };
    for (words) |word| {
        var fresh_output = Output{};
        const fresh = try createMachine(&fresh_output);
        defer destroyMachine(fresh);
        try fresh.interpretLine("REQUIRE-GRAPHICS ALSO GRAPHICS : SQ FDUP F* ;");
        var line: [64]u8 = undefined;
        try fresh.interpretLine(try std.fmt.bufPrint(&line, ": T {s} ; ' T CATCH", .{word}));
        try expectStack(fresh, &.{-271});
    }
    if (!@import("build_options").help) return;
    // Only HELP's text, not the warnings about T defined again.
    output.len = 0;
    try machine.interpretLine("HELP PLOT");
    try std.testing.expectEqualStrings("PLOT ( xt -- )\n  Draw the graph of xt ( F: x -- y ) across the image, joining the columns with lines; NaN leaves a gap (FORTH/Sigma graphics).\n", output.written());
}

/// The bytes of `text` as input events from a terminal.
fn byteEvents(comptime text: []const u8) [text.len]forth.InputEvent {
    var events: [text.len]forth.InputEvent = undefined;
    for (text, 0..) |byte, index| events[index] = .{ .byte = byte };
    return events;
}

fn inkeys(machine: *forth.State, comptime count: usize) !void {
    try machine.interpretLine(comptime repeat("INKEY ", count));
}

test "INKEY decodes keys and escape sequences from the terminal, and Ctrl+C throws -28" {
    try skipWithout(&.{.graphics});
    var output = Output{};
    const machine = try libraryMachine(&output, "4 4");
    defer destroyMachine(machine);
    // Arrows (CSI, SS3, with a modifier), Delete, F5, F12, F1, LF and DEL as Enter and
    // Backspace, an unknown sequence (dropped), a UTF-8 character, Esc before a key,
    // and Esc alone at the end, which waits for what may follow it.
    const events = byteEvents("a\x1b[A\x1bOB\x1b[1;5C\x1b[3~\x1b[15~\x1b[24~\x1bOP\n\x7f\x1b[Zb\xc3\xa9\x1bx\x1b");
    output.events = &events;
    try inkeys(machine, 16);
    try expectStack(machine, &.{ 'a', 256, 257, 259, 265, 270, 277, 266, 13, 8, 'b', 0xc3, 0xa9, 27, 'x', -1 });
    machine.data_depth = 0;
    // 49 ms later it still waits; at 50 ms it is the Esc key.
    output.time += 49_000;
    try inkeys(machine, 1);
    output.time += 1_000;
    try inkeys(machine, 2);
    try expectStack(machine, &.{ -1, 27, -1 });
    machine.data_depth = 0;
    // A sequence that comes in parts, also a mouse report, is one key or report.
    const part1 = byteEvents("\x1b");
    const part2 = byteEvents("[");
    const part3 = byteEvents("A");
    const part4 = byteEvents("\x1b[<0;");
    const part5 = byteEvents("3;");
    const part6 = byteEvents("9M");
    const parts = [_][]const forth.InputEvent{ &part1, &part2, &part3, &part4, &part5, &part6 };
    for (parts) |part| {
        output.events = part;
        output.event_index = 0;
        try inkeys(machine, 1);
    }
    try expectStack(machine, &.{ -1, -1, 256, -1, -1, -1 });
    machine.data_depth = 0;
    try std.testing.expectEqual(@as(forth.Cell, 1), machine.gfx_input.mouse_buttons);
    // A restart of the terminal's raw input drops the keys and the sequence kept.
    const restart = [_]forth.InputEvent{ .{ .byte = 'k' }, .{ .byte = 0x1b }, .restarted, .{ .byte = 'n' } };
    output.events = &restart;
    output.event_index = 0;
    try machine.interpretLine("MOUSE 2DROP DROP INKEY INKEY");
    try expectStack(machine, &.{ 'n', -1 });
    machine.data_depth = 0;
    try std.testing.expectEqual(@as(forth.Cell, 0), machine.gfx_input.mouse_buttons);
    try machine.interpretLine("K-UP K-LEFT K-F1 K-F12 K-DELETE K-NEXT");
    try expectStack(machine, &.{ 256, 258, 266, 277, 265, 263 });
    machine.data_depth = 0;

    // A sequence that does not end is given as the keys of its bytes.
    const long = byteEvents("\x1b[" ++ repeat("1", 40));
    output.events = &long;
    output.event_index = 0;
    try machine.interpretLine("INKEY INKEY INKEY");
    try expectStack(machine, &.{ 27, '[', '1' });
    machine.data_depth = 0;
    output.events = &.{};
    output.event_index = 0;
    while (machine.gfx_input.key_count != 0) _ = try @import("../core/graphics_input.zig").inkey(machine);

    // Ctrl+C, from the terminal or from the host's own keys.
    for ([_]forth.InputEvent{ .{ .byte = 3 }, .{ .key = 3 } }) |event| {
        const one = [_]forth.InputEvent{ event, .{ .byte = 'z' } };
        output.events = &one;
        output.event_index = 0;
        try machine.interpretLine("' INKEY CATCH INKEY");
        try expectStack(machine, &.{ -28, 'z' });
        machine.data_depth = 0;
    }
    // Keys that the host decoded pass through.
    const decoded = [_]forth.InputEvent{ .{ .key = 258 }, .{ .key = 'q' } };
    output.events = &decoded;
    output.event_index = 0;
    try inkeys(machine, 3);
    try expectStack(machine, &.{ 258, 'q', -1 });
}

test "MOUSE gives the pixel under the mouse on the terminal and in the window, and keys wait for INKEY" {
    try skipWithout(&.{.graphics});
    var output = Output{ .terminal_columns = 80, .terminal_rows = 24 };
    const machine = try libraryMachine(&output, "8 4");
    defer destroyMachine(machine);
    // Before SHOW the place of the image is not known.
    const early = byteEvents("\x1b[<0;3;9M");
    output.events = &early;
    try machine.interpretLine("MOUSE");
    try expectStack(machine, &.{ -1, -1, 1 });
    machine.data_depth = 0;

    // The image takes 2 rows; the cursor is on row 10 after it, so it starts on row 8.
    output.cursor_row = 10;
    try machine.interpretLine("MOUSE-ON DISPLAY-TERMINAL SHOW");
    try std.testing.expectEqualStrings("+", output.mouse_calls[0..output.mouse_count]);
    try std.testing.expectEqual(@as(usize, 1), output.cursor_queries);
    // Drawn over the same place, the image's place is known without asking.
    try machine.interpretLine("SHOW");
    try std.testing.expectEqual(@as(usize, 1), output.cursor_queries);
    // Pressed at column 2 row 8, a key, moved with no button to column 7 row 9, and
    // released at column 0 row 0 (above the image).
    const pressed = "\x1b[<0;3;9M";
    const events = byteEvents(pressed ++ "k" ++ "\x1b[<35;8;10M" ++ "\x1b[<0;1;1m");
    output.events = events[0..pressed.len];
    output.event_index = 0;
    try machine.interpretLine("MOUSE");
    try expectStack(machine, &.{ 2, 1, 1 });
    machine.data_depth = 0;
    output.events = events[pressed.len .. pressed.len + 1 + 11];
    output.event_index = 0;
    try machine.interpretLine("MOUSE INKEY");
    try expectStack(machine, &.{ 7, 3, 0, 'k' });
    machine.data_depth = 0;
    output.events = events[pressed.len + 1 + 11 ..];
    output.event_index = 0;
    try machine.interpretLine("MOUSE");
    try expectStack(machine, &.{ 0, -15, 0 });
    machine.data_depth = 0;
    // The right and middle buttons, and the wheel, which changes no button.
    const buttons = byteEvents("\x1b[<2;1;9M\x1b[<1;1;9M\x1b[<64;1;9M\x1b[<2;1;9m");
    output.events = &buttons;
    output.event_index = 0;
    try machine.interpretLine("MOUSE NIP NIP");
    try expectStack(machine, &.{4});
    machine.data_depth = 0;

    // Without the cursor's place, the position is not known.
    output.cursor_row = null;
    try machine.interpretLine("CR SHOW");
    output.events = events[0..pressed.len];
    output.event_index = 0;
    try machine.interpretLine("MOUSE");
    try expectStack(machine, &.{ -1, -1, 5 });
    machine.data_depth = 0;
    // The window gives the pixel itself; MOUSE-OFF stops the reports.
    const window = [_]forth.InputEvent{.{ .window_mouse = .{ .x = 5, .y = 3, .buttons = 2 } }};
    output.events = &window;
    output.event_index = 0;
    try machine.interpretLine("MOUSE MOUSE-OFF");
    try expectStack(machine, &.{ 5, 3, 2 });
    try std.testing.expectEqualStrings("+-", output.mouse_calls[0..output.mouse_count]);
}

test "SHOW on the terminal draws over the image it drew last when nothing was written since" {
    try skipWithout(&.{.graphics});
    var output = Output{ .terminal_columns = 80, .terminal_rows = 24 };
    const machine = try libraryMachine(&output, "8 4");
    defer destroyMachine(machine);
    try machine.interpretLine("DISPLAY-TERMINAL SHOW");
    const first = output.len;
    try std.testing.expect(!std.mem.startsWith(u8, output.written(), "\r"));
    try machine.interpretLine("SHOW");
    const again = output.written()[first..];
    try std.testing.expect(std.mem.startsWith(u8, again, "\r\x1b[2A"));
    try std.testing.expect(std.mem.endsWith(u8, again, "\n\x1b[J"));
    // The same picture after the return, each row ending by clearing the rest of its
    // line (a narrower picture leaves nothing of the last one).
    var cleared: [1024]u8 = undefined;
    const kept = again[5 .. again.len - 3];
    const length = std.mem.replacementSize(u8, kept, "\x1b[0m\x1b[K", "\x1b[0m");
    _ = std.mem.replace(u8, kept, "\x1b[0m\x1b[K", "\x1b[0m", &cleared);
    try std.testing.expectEqualStrings(output.written()[0..first], cleared[0..length]);
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, again, "\x1b[K"));
    // Output in between starts a new picture.
    const before = output.len;
    try machine.interpretLine("1 . SHOW");
    try std.testing.expect(!std.mem.startsWith(u8, output.written()[before + 2 ..], "\r"));
    try machine.interpretLine("TERMINAL-SIXEL SHOW");
    try std.testing.expect(std.mem.indexOf(u8, output.written()[before..], "\r\x1b[2A\x1b[J\x1bPq") != null);
    // A Sixel picture 4 pixels high takes 1 row of the assumed 20 pixels.
    const sixel = output.len;
    try machine.interpretLine("SHOW");
    try std.testing.expect(std.mem.startsWith(u8, output.written()[sixel..], "\r\x1b[1A\x1b[J\x1bPq"));

    // Not on a terminal: always a new picture.
    output.terminal_columns = 0;
    const piped = output.len;
    try machine.interpretLine("SHOW");
    try std.testing.expect(std.mem.startsWith(u8, output.written()[piped..], "\x1bPq"));
}

test "FRAME waits for the rest of the frame time, does not wait when late, and shows the image" {
    try skipWithout(&.{.graphics});
    var output = Output{ .terminal_columns = 80, .terminal_rows = 24 };
    const machine = try libraryMachine(&output, "2 2");
    defer destroyMachine(machine);
    // The first FRAME has no frame before it.
    try machine.interpretLine("DISPLAY-TERMINAL 50 FRAME");
    try std.testing.expectEqual(@as(forth.Cell, -1), output.slept);
    try std.testing.expect(output.len != 0);
    // 20 ms have passed of the next 50.
    output.time += 20_000;
    try machine.interpretLine("50 FRAME");
    try std.testing.expectEqual(@as(forth.Cell, 30), output.slept);
    // 80 ms of the next 50: late, so no wait, and the next one counts from now.
    output.slept = -1;
    output.time += 30_000 + 80_000;
    try machine.interpretLine("50 FRAME");
    try std.testing.expectEqual(@as(forth.Cell, -1), output.slept);
    output.time += 10_000;
    try machine.interpretLine("50 FRAME");
    try std.testing.expectEqual(@as(forth.Cell, 40), output.slept);
    try expectStack(machine, &.{});
}

test "the built-in font has the ASCII characters, and the glyph words give their boxes and coverage" {
    try skipWithout(&.{.graphics});
    const font = @import("../graphics/font_misaki.zig");
    // The printable ASCII characters, in order, each 4 pixels wide.
    try std.testing.expectEqual(@as(usize, 95), font.glyphs.len);
    for (font.glyphs, 0x20..) |glyph, code| {
        try std.testing.expectEqual(code, glyph.code);
        try std.testing.expectEqual(@as(u8, 4), glyph.width);
    }
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    // A: advancing 4, its box the 3 columns it uses; a space has an empty box.
    try machine.interpretLine("REQUIRE-GRAPHICS ALSO GRAPHICS GFX-FONT-HEIGHT CHAR A GFX-GLYPH-LOAD GFX-GLYPH-BOX 1 0 GFX-GLYPH-ALPHA 0 0 GFX-GLYPH-ALPHA 2 1 GFX-GLYPH-ALPHA 3 0 GFX-GLYPH-ALPHA");
    try expectStack(machine, &.{ 8, 4, 0, 3, 8, 255, 0, 255, 0 });
    machine.data_depth = 0;
    try machine.interpretLine("BL GFX-GLYPH-LOAD GFX-GLYPH-BOX DROP NIP $1F GFX-GLYPH-LOAD $7F GFX-GLYPH-LOAD $3042 GFX-GLYPH-LOAD -1 GFX-GLYPH-LOAD $110000 GFX-GLYPH-LOAD");
    try expectStack(machine, &.{ 4, 0, -1, -1, -1, -1, -1 });
}

test "TEXT draws UTF-8 strings with the font, ? for a character it lacks, and TEXT-SCALE and TEXT-WIDTH" {
    try skipWithout(&.{.graphics});
    var output = Output{};
    const machine = try libraryMachine(&output, "14 9");
    defer destroyMachine(machine);
    // A, then あ, which the font lacks, as ?, from 1 1; a control character draws nothing.
    try machine.interpretLine("S\\\" A\\tあ\" 1 1 TEXT");
    try expectPicture(machine,
        \\..............
        \\..#...#.......
        \\.#.#.#.#......
        \\.#.#...#......
        \\.###..#.......
        \\.#.#..........
        \\.#.#..#.......
        \\..............
        \\..............
        \\
    );
    // A kanji, an invalid byte, and a sequence cut short are drawn as ? each.
    try machine.interpretLine("CLS S\\\" 漢\\xff\\xe3\\x81\" 0 0 TEXT");
    var question: [256]u8 = undefined;
    const drawn = picture(machine, &question);
    try machine.interpretLine("CLS S\" ????\" 0 0 TEXT");
    try expectPicture(machine, drawn);
    // Twice as large, cut at the edges, and far away.
    try machine.interpretLine("CLS 2 TEXT-SCALE S\" A\" 7 3 TEXT 1 TEXT-SCALE S\" A\" -100000000000000000 0 TEXT");
    try expectPicture(machine,
        \\..............
        \\..............
        \\..............
        \\.........##...
        \\.........##...
        \\.......##..##.
        \\.......##..##.
        \\.......##..##.
        \\.......##..##.
        \\
    );
    try machine.interpretLine("S\" Aあ\" TEXT-WIDTH 3 TEXT-SCALE S\" Aあ\" TEXT-WIDTH 1 TEXT-SCALE S\" \" TEXT-WIDTH");
    try expectStack(machine, &.{ 8, 24, 0 });
    machine.data_depth = 0;
    // TEXT-SCALE takes 1 to 256.
    try machine.interpretLine(": T0 0 TEXT-SCALE ; : T257 257 TEXT-SCALE ; ' T0 CATCH ' T257 CATCH 256 TEXT-SCALE 1 TEXT-SCALE");
    try expectStack(machine, &.{ -24, -24 });
    machine.data_depth = 0;

    // TEXT needs an image; TEXT-WIDTH does not.
    var fresh_output = Output{};
    const fresh = try createMachine(&fresh_output);
    defer destroyMachine(fresh);
    try fresh.interpretLine("REQUIRE-GRAPHICS ALSO GRAPHICS S\" ab\" TEXT-WIDTH : T S\" a\" 0 0 TEXT ; ' T CATCH");
    try expectStack(fresh, &.{ 8, -271 });
}

/// A small BDF font: X (a box 3 by 3 from 1 right of the pen), g (below the baseline),
/// a glyph with no code point, and U+3042 (9 pixels wide: two bytes a row). The glyphs
/// are not in order, and the font has no "?".
const test_bdf =
    \\STARTFONT 2.1
    \\FONT -test-
    \\SIZE 6 75 75
    \\FONTBOUNDINGBOX 9 6 0 -1
    \\STARTPROPERTIES 2
    \\FONT_ASCENT 5
    \\FONT_DESCENT 1
    \\ENDPROPERTIES
    \\CHARS 4
    \\STARTCHAR g
    \\ENCODING 103
    \\DWIDTH 3 0
    \\BBX 2 2 0 -1
    \\BITMAP
    \\C0
    \\C0
    \\ENDCHAR
    \\STARTCHAR X
    \\ENCODING 88
    \\DWIDTH 5 0
    \\BBX 3 3 1 0
    \\BITMAP
    \\A0
    \\40
    \\A0
    \\ENDCHAR
    \\STARTCHAR unencoded
    \\ENCODING -1
    \\DWIDTH 4 0
    \\BBX 1 1 0 0
    \\BITMAP
    \\80
    \\ENDCHAR
    \\STARTCHAR a
    \\ENCODING 12354
    \\DWIDTH 10 0
    \\BBX 9 1 0 4
    \\BITMAP
    \\FF80
    \\ENDCHAR
    \\ENDFONT
    \\
;

test "LOAD-FONT reads a BDF font for TEXT, TEXT-WIDTH, and TEXT-HEIGHT, and BUILTIN-FONT goes back" {
    try skipWithout(&.{.graphics});
    var output = Output{};
    support.setFakeFile(&output, 0, test_bdf);
    const machine = try libraryMachine(&output, "20 6");
    defer destroyMachine(machine);
    // Z and "?" are not in the font, so Z draws nothing and takes no width.
    try machine.interpretLine("TEXT-HEIGHT S\" a.txt\" LOAD-FONT TEXT-HEIGHT S\\\" XgZ\\xe3\\x81\\x82\" 0 0 TEXT S\\\" XgZ\\xe3\\x81\\x82\" TEXT-WIDTH");
    try expectStack(machine, &.{ 8, 6, 18 });
    machine.data_depth = 0;
    try expectPicture(machine,
        \\........#########...
        \\....................
        \\.#.#................
        \\..#.................
        \\.#.#.##.............
        \\.....##.............
        \\
    );
    try machine.interpretLine("2 TEXT-SCALE TEXT-HEIGHT 1 TEXT-SCALE BUILTIN-FONT TEXT-HEIGHT");
    try expectStack(machine, &.{ 12, 8 });
    machine.data_depth = 0;
    // The glyph words underneath: X's box and coverage, and a glyph the font lacks.
    try machine.interpretLine("S\" a.txt\" LOAD-FONT CHAR X GFX-GLYPH-LOAD GFX-GLYPH-BOX 0 2 GFX-GLYPH-ALPHA 1 3 GFX-GLYPH-ALPHA 1 2 GFX-GLYPH-ALPHA 9 9 GFX-GLYPH-ALPHA CHAR ? GFX-GLYPH-LOAD");
    try expectStack(machine, &.{ 5, 1, 3, 6, 255, 255, 0, 0, -1 });
    machine.data_depth = 0;

    // Files that are not BDF fonts it can read give FONT ERROR, and the font stays.
    const broken = [_][]const u8{
        "STARTFONT 2.1\nFONT_ASCENT 5\nFONT_DESCENT 1\nENDFONT\n", // no glyph
        "FONT_ASCENT 5\nFONT_DESCENT 1\nSTARTCHAR A\nENCODING 65\nBBX 8 2 0 0\nBITMAP\nFF\nENDCHAR\n", // a row missing
        "FONT_ASCENT 5\nFONT_DESCENT 1\nSTARTCHAR A\nENCODING 65\nBBX 9 1 0 0\nBITMAP\nFF\nENDCHAR\n", // a row too short
        "FONT_ASCENT 5\nFONT_DESCENT 1\nSTARTCHAR A\nENCODING 65\nBBX 8 1 0 0\nBITMAP\nZZ\nENDCHAR\n", // not hexadecimal
        "FONT_ASCENT 200\nFONT_DESCENT 100\nSTARTCHAR A\nENCODING 65\nBBX 8 1 0 0\nBITMAP\nFF\nENDCHAR\n", // too high
        "FONT_ASCENT 5\nFONT_DESCENT 1\nSTARTCHAR A\nENCODING 65\nBBX 600 1 0 0\nBITMAP\nFF\nENDCHAR\n", // too wide
        "FONT_ASCENT 5\nFONT_DESCENT 1\nSTARTCHAR A\nENCODING 65\nBBX 8 1 0 0\nBITMAP\nFF\n", // not ended
    };
    for (broken) |text| {
        support.setFakeFile(&output, 1, text);
        try machine.interpretLine(": T S\" b.txt\" LOAD-FONT ; ' T CATCH TEXT-HEIGHT");
        try expectStack(machine, &.{ -272, 6 });
        machine.data_depth = 0;
    }
    // A file that cannot be opened gives its ior, and a buffer the host cannot give OUT
    // OF MEMORY; the font stays.
    try machine.interpretLine(": T2 S\" none.txt\" LOAD-FONT ; ' T2 CATCH 0<> TEXT-HEIGHT");
    try expectStack(machine, &.{ -1, 6 });
    machine.data_depth = 0;
    output.font_fails = true;
    try machine.interpretLine(": T3 S\" a.txt\" LOAD-FONT ; ' T3 CATCH TEXT-HEIGHT");
    try expectStack(machine, &.{ -257, 6 });
    machine.data_depth = 0;
}

test "SYSTEM-FONT draws the host's glyphs, mixing the current color by coverage" {
    try skipWithout(&.{.graphics});
    var output = Output{ .has_system_fonts = true };
    const machine = try libraryMachine(&output, "8 4");
    defer destroyMachine(machine);
    // Red over white: coverage 255, 128, and 64; 0 leaves the pixel. ~, which the font
    // lacks, is drawn as ?.
    try machine.interpretLine("$FFFFFF GFX-CLS $FF0000 COLOR! S\" Fake\" 4 SYSTEM-FONT TEXT-HEIGHT S\" A~B\" 2 1 TEXT S\" A~B\" TEXT-WIDTH");
    try expectStack(machine, &.{ 4, 9 });
    machine.data_depth = 0;
    try machine.interpretLine("1 1 GFX-PGET 2 1 GFX-PGET 1 2 GFX-PGET 2 2 GFX-PGET 4 1 GFX-PGET");
    try expectStack(machine, &.{ 0xFF0000, 0xFF7F7F, 0xFFFFFF, 0xFFBFBF, 0xFF0000 });
    machine.data_depth = 0;
    // Twice as large: each pixel of the glyph is 2 by 2.
    try machine.interpretLine("$FFFFFF GFX-CLS 2 TEXT-SCALE S\" A\" 2 0 TEXT 1 TEXT-SCALE 0 0 GFX-PGET 1 1 GFX-PGET 2 1 GFX-PGET 3 0 GFX-PGET");
    try expectStack(machine, &.{ 0xFF0000, 0xFF0000, 0xFF7F7F, 0xFF7F7F });
    machine.data_depth = 0;
    // A name the host has no font of, and heights outside 1 to 256.
    try machine.interpretLine(": T1 S\" Other\" 4 SYSTEM-FONT ; : T2 S\" Fake\" 0 SYSTEM-FONT ; : T3 S\" Fake\" 257 SYSTEM-FONT ; ' T1 CATCH ' T2 CATCH ' T3 CATCH");
    try expectStack(machine, &.{ -272, -24, -24 });
    machine.data_depth = 0;

    // A host without system fonts.
    var plain_output = Output{};
    const plain = try createMachine(&plain_output);
    defer destroyMachine(plain);
    try plain.interpretLine("REQUIRE-GRAPHICS ALSO GRAPHICS : T S\" Fake\" 8 SYSTEM-FONT ; ' T CATCH");
    try expectStack(plain, &.{-21});
}

test "the palettes of DISPLAY-COLORS: black and white, the 16 ANSI colors, xterm's 256, and the Bayer dither" {
    const palette = @import("../core/graphics_palette.zig");
    const mono = palette.ColorMode{ .colors = 2 };
    const ansi = palette.ColorMode{ .colors = 16 };
    const xterm = palette.ColorMode{ .colors = 256 };
    // Black and white by brightness, 128 and up white.
    try std.testing.expectEqual(@as(u8, 15), palette.paletteIndex(mono, 0, 0, 0xffffff));
    try std.testing.expectEqual(@as(u8, 0), palette.paletteIndex(mono, 0, 0, 0x000000));
    try std.testing.expectEqual(@as(u8, 15), palette.paletteIndex(mono, 0, 0, 0x808080));
    try std.testing.expectEqual(@as(u8, 0), palette.paletteIndex(mono, 0, 0, 0x7f7f7f));
    // The nearest of the 16 colors as xterm shows them.
    try std.testing.expectEqual(@as(u8, 9), palette.paletteIndex(ansi, 0, 0, 0xff0000));
    try std.testing.expectEqual(@as(u8, 1), palette.paletteIndex(ansi, 0, 0, 0xc80000));
    try std.testing.expectEqual(@as(u8, 8), palette.paletteIndex(ansi, 0, 0, 0x808080));
    try std.testing.expectEqual(@as(u8, 7), palette.paletteIndex(ansi, 0, 0, 0xe0e0e0));
    try std.testing.expectEqual(@as(u8, 4), palette.paletteIndex(ansi, 0, 0, 0x0000ff));
    // The cube and the grays of the 256 colors.
    try std.testing.expectEqual(@as(u8, 196), palette.paletteIndex(xterm, 0, 0, 0xff0000));
    try std.testing.expectEqual(@as(u8, 67), palette.paletteIndex(xterm, 0, 0, 0x5f87af));
    try std.testing.expectEqual(@as(u8, 244), palette.paletteIndex(xterm, 0, 0, 0x808080));
    try std.testing.expectEqual(@as(u8, 16), palette.paletteIndex(xterm, 0, 0, 0x000000));
    try std.testing.expectEqual(@as(u8, 231), palette.paletteIndex(xterm, 0, 0, 0xffffff));
    try std.testing.expectEqual(@as(u32, 0xff0000), palette.paletteColor(196));
    try std.testing.expectEqual(@as(u32, 0x808080), palette.paletteColor(244));
    try std.testing.expectEqual(@as(u32, 0x5f87af), palette.paletteColor(67));
    try std.testing.expectEqual(@as(u32, 0x5c5cff), palette.paletteColor(12));
    try std.testing.expectEqual(@as(u32, 0x123456), palette.convert(.{}, 3, 4, 0xff123456));
    try std.testing.expectEqual(@as(u32, 0xffffff), palette.convert(mono, 0, 0, 0xc0c0c0));
    // Dithered to 2 colors, a middle gray is white in half of each 4 by 4 block, and
    // black and white stay. With 16, black stays, and white mixes xterm's two whites.
    const mono_dither = palette.ColorMode{ .colors = 2, .dither = true };
    const ansi_dither = palette.ColorMode{ .colors = 16, .dither = true };
    var white: usize = 0;
    for (0..4) |y| for (0..4) |x| {
        if (palette.convert(mono_dither, x, y, 0x808080) == 0xffffff) white += 1;
        try std.testing.expectEqual(@as(u32, 0), palette.convert(mono_dither, x, y, 0));
        try std.testing.expectEqual(@as(u32, 0xffffff), palette.convert(mono_dither, x, y, 0xffffff));
        try std.testing.expectEqual(@as(u32, 0), palette.convert(ansi_dither, x, y, 0));
        const light = palette.convert(ansi_dither, x, y, 0xffffff);
        try std.testing.expect(light == 0xffffff or light == 0xe5e5e5);
    };
    try std.testing.expectEqual(@as(usize, 8), white);
    // Dithering a color between two of the cube gives both.
    const dithered = palette.ColorMode{ .colors = 256, .dither = true };
    var seen = [2]bool{ false, false };
    for (0..4) |y| for (0..4) |x| {
        const index = palette.paletteIndex(dithered, x, y, 0x730000);
        if (index == 16 + 36 * 1) seen[0] = true;
        if (index == 16 + 36 * 2) seen[1] = true;
    };
    try std.testing.expect(seen[0] and seen[1]);
}

test "DISPLAY-COLORS and DITHER change what SHOW shows on the terminal and in the window, not the image" {
    try skipWithout(&.{.graphics});
    var output = Output{ .has_window = true };
    const machine = try libraryMachine(&output, "2 3");
    defer destroyMachine(machine);
    try machine.interpretLine("$FF0000 COLOR! 0 0 PSET $00FF00 COLOR! 0 1 PSET $0000FF COLOR! 1 1 PSET $FFFFFF COLOR! 0 2 PSET DISPLAY-TERMINAL");
    output.len = 0;
    try machine.interpretLine("256 DISPLAY-COLORS SHOW");
    try std.testing.expectEqualStrings("\x1b[38;5;196m\x1b[48;5;46m\u{2580}\x1b[38;5;16m\x1b[48;5;21m\u{2580}\x1b[0m\n" ++
        "\x1b[38;5;231m\x1b[49m\u{2580}\x1b[38;5;16m\u{2580}\x1b[0m\n", output.written());
    output.len = 0;
    try machine.interpretLine("CR 16 DISPLAY-COLORS SHOW");
    try std.testing.expectEqualStrings("\n\x1b[91m\x1b[102m\u{2580}\x1b[30m\x1b[44m\u{2580}\x1b[0m\n" ++
        "\x1b[97m\x1b[49m\u{2580}\x1b[30m\u{2580}\x1b[0m\n", output.written());
    output.len = 0;
    try machine.interpretLine("CR 2 DISPLAY-COLORS SHOW");
    try std.testing.expectEqualStrings("\n\x1b[30m\x1b[107m\u{2580}\x1b[40m\u{2580}\x1b[0m\n" ++
        "\x1b[97m\x1b[49m\u{2580}\x1b[30m\u{2580}\x1b[0m\n", output.written());
    // Sixel defines the palette's registers: 2 for black and white, 240 for 256 colors.
    output.len = 0;
    try machine.interpretLine("CR TERMINAL-SIXEL SHOW");
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "#0;2;0;0;0#1;2;100;100;100") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "#2;2;") == null);
    output.len = 0;
    try machine.interpretLine("CR 256 DISPLAY-COLORS SHOW");
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "#239;2;93;93;93") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "#240;2;") == null);
    // The image keeps its colors, and the window gets the mode.
    try machine.interpretLine("0 0 GFX-PGET 1 DITHER 16 DISPLAY-COLORS DISPLAY-WINDOW SHOW");
    try expectStack(machine, &.{0xFF0000});
    try std.testing.expectEqual(forth.ColorMode{ .colors = 16, .dither = true }, output.window_mode);
    // SHOW sets the mode each time, also after GFX-COLOR-MODE.
    try machine.interpretLine("0 DITHER 0 DISPLAY-COLORS 256 -1 GFX-COLOR-MODE SHOW");
    try std.testing.expectEqual(forth.ColorMode{}, output.window_mode);
    machine.data_depth = 0;
    // Only 0, 2, 16, and 256.
    try machine.interpretLine(": T8 8 DISPLAY-COLORS ; : T-1 -1 DISPLAY-COLORS ; ' T8 CATCH ' T-1 CATCH 16 DISPLAY-COLORS (COLORS) @");
    try expectStack(machine, &.{ -24, -24, 16 });
}

// ---- The review of stage G4 ----

test "BDF numbers too large to add give FONT ERROR, and an empty glyph draws nothing" {
    try skipWithout(&.{.graphics});
    var output = Output{};
    const machine = try libraryMachine(&output, "8 4");
    defer destroyMachine(machine);
    const extreme = [_][]const u8{
        "FONT_ASCENT -9223372036854775808\nFONT_DESCENT 1\nSTARTCHAR A\nENCODING 65\nBBX 1 1 0 0\nBITMAP\n80\nENDCHAR\n",
        "FONT_ASCENT 5\nFONT_DESCENT 9223372036854775807\nSTARTCHAR A\nENCODING 65\nBBX 1 1 0 0\nBITMAP\n80\nENDCHAR\n",
        "FONTBOUNDINGBOX 1 9223372036854775807 0 -9223372036854775808\nSTARTCHAR A\nENCODING 65\nBBX 1 1 0 0\nBITMAP\n80\nENDCHAR\n",
        "FONT_ASCENT 5\nFONT_DESCENT 1\nSTARTCHAR A\nENCODING 65\nBBX 1 1 0 -9223372036854775808\nBITMAP\n80\nENDCHAR\n",
        "FONT_ASCENT 5\nFONT_DESCENT 1\nSTARTCHAR A\nENCODING 9223372036854775807\nBBX 1 1 0 0\nBITMAP\n80\nENDCHAR\n",
    };
    for (extreme) |text| {
        support.setFakeFile(&output, 0, text);
        try machine.interpretLine(": T S\" a.txt\" LOAD-FONT ; ' T CATCH TEXT-HEIGHT");
        try expectStack(machine, &.{ -272, 8 });
        machine.data_depth = 0;
    }
    // A, all of its box; then a space with an empty box, after which A's coverage
    // must not show through.
    support.setFakeFile(&output, 0, "FONT_ASCENT 2\nFONT_DESCENT 0\nSTARTCHAR A\nENCODING 65\nDWIDTH 2 0\nBBX 2 2 0 0\nBITMAP\nC0\nC0\nENDCHAR\nSTARTCHAR space\nENCODING 32\nDWIDTH 3 0\nBBX 0 0 0 0\nBITMAP\nENDCHAR\n");
    try machine.interpretLine("S\" a.txt\" LOAD-FONT CHAR A GFX-GLYPH-LOAD DROP BL GFX-GLYPH-LOAD GFX-GLYPH-BOX 0 0 GFX-GLYPH-ALPHA");
    try expectStack(machine, &.{ 3, 0, 0, 2, 0 });
    machine.data_depth = 0;
    try machine.interpretLine("S\"  A\" 0 0 TEXT S\"  A\" TEXT-WIDTH");
    try expectStack(machine, &.{5});
    try expectPicture(machine, "...##...\n...##...\n........\n........\n");
}

test "LOAD-FONT keeps the font it had when the file changes between its two readings" {
    try skipWithout(&.{.graphics});
    var output = Output{};
    const machine = try libraryMachine(&output, "8 4");
    defer destroyMachine(machine);
    const two_lines = "FONT_ASCENT 2\nFONT_DESCENT 0\nSTARTCHAR A\nENCODING 65\nBBX 1 1 0 0\nBITMAP\n80\nENDCHAR\n";
    const three_lines = "FONT_ASCENT 3\nFONT_DESCENT 0\nSTARTCHAR A\nENCODING 65\nBBX 1 1 0 0\nBITMAP\n80\nENDCHAR\n";
    support.setFakeFile(&output, 0, two_lines);
    support.setFakeFile(&output, 1, three_lines);
    // A second font replaces the first, whose buffer is given back.
    try machine.interpretLine("S\" a.txt\" LOAD-FONT TEXT-HEIGHT S\" b.txt\" LOAD-FONT TEXT-HEIGHT");
    try expectStack(machine, &.{ 2, 3 });
    machine.data_depth = 0;
    try std.testing.expectEqual(@as(usize, 1), output.fontsInUse());
    // Between the readings the file gets another glyph, or another height: the font
    // stays, and the new buffer is given back.
    const changed = [_][]const u8{
        two_lines ++ "STARTCHAR B\nENCODING 66\nBBX 1 1 0 0\nBITMAP\n80\nENDCHAR\n",
        "FONT_ASCENT 4\nFONT_DESCENT 0\nSTARTCHAR A\nENCODING 65\nBBX 1 1 0 0\nBITMAP\n80\nENDCHAR\n",
        "FONT_ASCENT 2\nFONT_DESCENT 0\nSTARTCHAR A\nENCODING 65\nBBX 1 1 0 0\nBITMAP\n80\n",
    };
    for (changed) |text| {
        support.setFakeFile(&output, 0, two_lines);
        output.swap_file = .{ .index = 0, .text = text };
        try machine.interpretLine(": T S\" a.txt\" LOAD-FONT ; ' T CATCH TEXT-HEIGHT");
        try expectStack(machine, &.{ -272, 3 });
        machine.data_depth = 0;
        try std.testing.expectEqual(@as(usize, 1), output.fontsInUse());
    }
}

test "MOUSE goes on reading the mouse and Ctrl+C when the queue of keys is full" {
    try skipWithout(&.{.graphics});
    var output = Output{};
    const machine = try libraryMachine(&output, "8 4");
    defer destroyMachine(machine);
    const events = byteEvents(repeat("a", 70) ++ "\x1b[<0;1;1M" ++ "\x03");
    output.events = &events;
    try machine.interpretLine("' MOUSE CATCH");
    try expectStack(machine, &.{-28});
    try std.testing.expectEqual(@as(forth.Cell, 1), machine.gfx_input.mouse_buttons);
    try std.testing.expectEqual(@as(usize, 64), machine.gfx_input.key_count);
}

test "TEXT takes overlong forms, surrogates, and values above U+10FFFF as bytes that are not UTF-8" {
    try skipWithout(&.{.graphics});
    var output = Output{};
    const machine = try libraryMachine(&output, "8 4");
    defer destroyMachine(machine);
    // Each byte of a wrong sequence is a ? (4 pixels); a right one, missing from the
    // font, one ?.
    try machine.interpretLine("S\\\" \\xC1\\x81\" TEXT-WIDTH S\\\" \\xC0\\x80\" TEXT-WIDTH S\\\" \\xED\\xA0\\x80\" TEXT-WIDTH S\\\" \\xF4\\x90\\x80\\x80\" TEXT-WIDTH S\\\" \\xF0\\x9F\\x98\\x80\" TEXT-WIDTH S\\\" \\xEF\\xBF\\xBF\" TEXT-WIDTH");
    try expectStack(machine, &.{ 8, 8, 12, 16, 4, 4 });
}

test "PLOT gives its function finite x across a range as wide as the floats allow" {
    try skipWithout(&.{.graphics});
    try support.skipWithoutFloat();
    var output = Output{};
    const machine = try libraryMachine(&output, "4 4");
    defer destroyMachine(machine);
    try machine.interpretLine("VARIABLE BAD 0 BAD ! FVARIABLE LAST : REC ( F: x -- y ) FDUP LAST F! FDUP FDUP F- 0e0 F= 0= IF 1 BAD +! THEN FDROP 0e0 ;");
    try machine.interpretLine("0e0 1e308 X-RANGE ' REC PLOT BAD @ LAST F@ 1e308 F=");
    try expectStack(machine, &.{ 0, -1 });
}
