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
    try std.testing.expectEqual(words_before + 1 + words_graphics.definitions.len, machine.word_count);
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
