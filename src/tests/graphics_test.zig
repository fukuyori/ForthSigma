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
