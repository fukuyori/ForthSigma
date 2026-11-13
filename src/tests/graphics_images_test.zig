//! Tests of the images of the pool: NEW-IMAGE, DRAW-TO, COPY-RECT, and the handles.

const std = @import("std");
const forth = @import("../forth.zig");
const graphics_images = @import("../core/graphics_images.zig");
const support = @import("support.zig");
const Output = support.Output;
const createMachine = support.createMachine;
const destroyMachine = support.destroyMachine;
const expectStack = support.expectStack;
const skipWithout = support.skipWithout;

/// A machine with the graphics words in the search order and a screen of w by h.
fn imageMachine(output: *Output, comptime size: []const u8) !*forth.State {
    const machine = try createMachine(output);
    errdefer destroyMachine(machine);
    try machine.interpretLine("REQUIRE-GRAPHICS ALSO GRAPHICS " ++ size ++ " GFX-INIT");
    return machine;
}

/// The colors of a w by h image, row by row, through GFX-PGET of the image drawn on.
fn expectPixels(machine: *forth.State, expected: []const forth.Cell) !void {
    const canvas = try graphics_images.target(machine);
    try std.testing.expectEqual(expected.len, canvas.pixels.len);
    for (canvas.pixels, expected) |pixel, color| try std.testing.expectEqual(color, @as(forth.Cell, pixel & 0xffffff));
}

test "NEW-IMAGE makes black images with handles that FREE-IMAGE makes invalid" {
    try skipWithout(&.{.graphics});
    var output = Output{};
    const machine = try imageMachine(&output, "4 4");
    defer destroyMachine(machine);
    try machine.interpretLine("3 2 NEW-IMAGE CONSTANT A  5 1 NEW-IMAGE CONSTANT B  A IMAGE-SIZE B IMAGE-SIZE SCREEN IMAGE-SIZE A B");
    // The first places of the table, generation 0.
    try expectStack(machine, &.{ 3, 2, 5, 1, 4, 4, 1, 2 });
    machine.data_depth = 0;
    try std.testing.expectEqual(@as(usize, 2), output.images_live);
    try machine.interpretLine("A DRAW-TO");
    try expectPixels(machine, &.{ 0, 0, 0, 0, 0, 0 });

    // Freed, the handle is invalid, also when freed again or drawn on; drawing goes back
    // to the screen.
    try machine.interpretLine("A FREE-IMAGE DRAWING");
    try expectStack(machine, &.{0});
    machine.data_depth = 0;
    try std.testing.expectEqual(@as(usize, 1), output.images_live);
    for ([_][]const u8{ "A FREE-IMAGE", "A DRAW-TO", "A IMAGE-SIZE", "A 0 0 1 1 0 0 COPY-RECT", "0 FREE-IMAGE", "-1 DRAW-TO", "257 DRAW-TO", "$100000000 DRAW-TO" }) |line| {
        try std.testing.expectError(error.InvalidImageHandle, machine.interpretLine(line));
        machine.data_depth = 0;
    }
    try machine.interpretLine("A ' FREE-IMAGE CATCH NIP");
    try expectStack(machine, &.{-278});
    machine.data_depth = 0;
    machine.report(error.InvalidImageHandle);
    try std.testing.expect(std.mem.endsWith(u8, output.written(), "INVALID IMAGE HANDLE !\n"));

    // The place is used again with the next generation, so the old handle stays invalid.
    try machine.interpretLine("1 1 NEW-IMAGE");
    try expectStack(machine, &.{65536 + 1});
    machine.data_depth = 0;
    try std.testing.expectError(error.InvalidImageHandle, machine.interpretLine("A IMAGE-SIZE"));
    machine.data_depth = 0;
}

test "the sizes and the number of images are limited, and a failure changes nothing" {
    try skipWithout(&.{.graphics});
    var output = Output{};
    const machine = try imageMachine(&output, "2 2");
    defer destroyMachine(machine);
    for ([_][]const u8{ "0 1 NEW-IMAGE", "1 0 NEW-IMAGE", "16385 1 NEW-IMAGE", "1 -5 NEW-IMAGE" }) |line| {
        try std.testing.expectError(error.InvalidNumber, machine.interpretLine(line));
        machine.data_depth = 0;
    }
    var count: usize = 0;
    while (count < graphics_images.max_images) : (count += 1) try machine.interpretLine("1 1 NEW-IMAGE DROP");
    try std.testing.expectError(error.MemoryExhausted, machine.interpretLine("1 1 NEW-IMAGE"));
    machine.data_depth = 0;
    try std.testing.expectEqual(graphics_images.max_images, output.images_live);
    forth.releaseImages(machine);
    try std.testing.expectEqual(@as(usize, 0), output.images_live);
    try std.testing.expectEqual(@as(usize, 0), machine.gfx_images_bytes);

    // The bytes of all images: 4 more than is left does not fit.
    machine.gfx_images_bytes = graphics_images.max_total_bytes - 4;
    try std.testing.expectError(error.MemoryExhausted, machine.interpretLine("2 1 NEW-IMAGE"));
    machine.data_depth = 0;
    try machine.interpretLine("1 1 NEW-IMAGE FREE-IMAGE");
    machine.gfx_images_bytes = 0;

    output.image_fails = true;
    try std.testing.expectError(error.MemoryExhausted, machine.interpretLine("1 1 NEW-IMAGE"));
    machine.data_depth = 0;
    try std.testing.expectEqual(@as(usize, 0), output.images_live);
}

test "the drawing words, GFX-WIDTH, and SAVE- use the image drawn on; SHOW the screen" {
    try skipWithout(&.{.graphics});
    var output = Output{ .has_window = true };
    const machine = try imageMachine(&output, "4 3");
    defer destroyMachine(machine);
    try machine.interpretLine("2 2 NEW-IMAGE CONSTANT A  A DRAW-TO GFX-WIDTH GFX-HEIGHT");
    try expectStack(machine, &.{ 2, 2 });
    machine.data_depth = 0;
    try machine.interpretLine("$112233 GFX-CLS $FF0000 COLOR! 1 0 PSET 0 1 9 1 LINE 5 5 PSET 1 1 GFX-PGET 9 9 GFX-PGET");
    try expectStack(machine, &.{ 0xff0000, -1 });
    machine.data_depth = 0;
    try expectPixels(machine, &.{ 0x112233, 0xff0000, 0xff0000, 0xff0000 });
    try machine.interpretLine("S\" a.txt\" SAVE-PPM");
    try std.testing.expectEqualStrings("P6\n2 2\n255\n" ++ "\x11\x22\x33\xff\x00\x00\xff\x00\x00\xff\x00\x00", output.files[0].data[0..output.files[0].len]);

    // The screen stays black, and SHOW shows it.
    try machine.interpretLine("SCREEN DRAW-TO GFX-WIDTH 0 0 GFX-PGET DISPLAY-WINDOW SHOW");
    try expectStack(machine, &.{ 4, 0 });
    machine.data_depth = 0;
    try std.testing.expectEqual(@as(u32, 4), output.window_width);
    try std.testing.expectEqual(@as(u32, 0xff00_0000), output.window_first_pixel);
    try machine.interpretLine("A DRAW-TO SHOW");
    try std.testing.expectEqual(@as(u32, 4), output.window_width);

    // GFX-INIT makes the screen again and leaves drawing where it was.
    try machine.interpretLine("6 5 GFX-INIT DRAWING A = GFX-WIDTH SCREEN IMAGE-SIZE");
    try expectStack(machine, &.{ -1, 2, 6, 5 });
    machine.data_depth = 0;
}

test "COPY-RECT copies a rectangle, leaving out what falls outside either image" {
    try skipWithout(&.{.graphics});
    var output = Output{};
    const machine = try imageMachine(&output, "4 3");
    defer destroyMachine(machine);
    // A source of 3 by 2 with a different color in each pixel.
    try machine.interpretLine("3 2 NEW-IMAGE CONSTANT S  S DRAW-TO  0 0 1 GFX-PSET 1 0 2 GFX-PSET 2 0 3 GFX-PSET 0 1 4 GFX-PSET 1 1 5 GFX-PSET 2 1 6 GFX-PSET  SCREEN DRAW-TO");
    try machine.interpretLine("S 1 1 PUT-IMAGE");
    try expectPixels(machine, &.{ 0, 0, 0, 0, 0, 1, 2, 3, 0, 4, 5, 6 });
    // Partly outside the screen on the left and the top, and partly outside the source.
    try machine.interpretLine("0 GFX-CLS S -1 -1 PUT-IMAGE");
    try expectPixels(machine, &.{ 5, 6, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 });
    try machine.interpretLine("0 GFX-CLS S 2 0 5 5 0 0 COPY-RECT");
    try expectPixels(machine, &.{ 3, 0, 0, 0, 6, 0, 0, 0, 0, 0, 0, 0 });
    try machine.interpretLine("0 GFX-CLS S -2 -1 3 2 0 0 COPY-RECT");
    try expectPixels(machine, &.{ 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0 });
    // Far away, empty, and huge rectangles copy nothing or only what fits.
    try machine.interpretLine("0 GFX-CLS S 0 0 3 2 100 100 COPY-RECT S 0 0 0 5 0 0 COPY-RECT S 0 0 -3 2 0 0 COPY-RECT");
    try expectPixels(machine, &.{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 });
    // Columns 2^63 - 4 to 2^63 - 2 of the rectangle are columns 0 to 2 of both images.
    try machine.interpretLine("S -9223372036854775804 0 9223372036854775807 2 -9223372036854775804 0 COPY-RECT");
    try expectPixels(machine, &.{ 1, 2, 3, 0, 4, 5, 6, 0, 0, 0, 0, 0 });
}

test "TRANSPARENT leaves out a color, and IMAGE-FLIP flips the copy" {
    try skipWithout(&.{.graphics});
    var output = Output{};
    const machine = try imageMachine(&output, "3 2");
    defer destroyMachine(machine);
    try machine.interpretLine("3 2 NEW-IMAGE CONSTANT S  S DRAW-TO  0 0 1 GFX-PSET 1 0 2 GFX-PSET 2 0 3 GFX-PSET 0 1 4 GFX-PSET 1 1 5 GFX-PSET 2 1 6 GFX-PSET  SCREEN DRAW-TO");
    try machine.interpretLine("$7 GFX-CLS 2 TRANSPARENT S 0 0 PUT-IMAGE");
    try expectPixels(machine, &.{ 1, 7, 3, 4, 5, 6 });
    // The color is the low 24 bits; a negative number is none.
    try machine.interpretLine("$7 GFX-CLS $FF000005 TRANSPARENT S 0 0 PUT-IMAGE");
    try expectPixels(machine, &.{ 1, 2, 3, 4, 7, 6 });
    try machine.interpretLine("-1 TRANSPARENT 1 IMAGE-FLIP S 0 0 PUT-IMAGE");
    try expectPixels(machine, &.{ 3, 2, 1, 6, 5, 4 });
    try machine.interpretLine("2 IMAGE-FLIP S 0 0 PUT-IMAGE");
    try expectPixels(machine, &.{ 4, 5, 6, 1, 2, 3 });
    try machine.interpretLine("3 IMAGE-FLIP S 0 0 PUT-IMAGE");
    try expectPixels(machine, &.{ 6, 5, 4, 3, 2, 1 });
    // A flipped part of the source: the rectangle flips, not the whole image.
    try machine.interpretLine("0 GFX-CLS 1 IMAGE-FLIP S 1 0 2 1 0 0 COPY-RECT");
    try expectPixels(machine, &.{ 3, 2, 0, 0, 0, 0 });
    // Flipped and cut at the right: the left part of the flipped rectangle stays.
    try machine.interpretLine("0 GFX-CLS S 0 0 3 1 1 1 COPY-RECT");
    try expectPixels(machine, &.{ 0, 0, 0, 0, 3, 2 });
    try machine.interpretLine("0 GFX-CLS 2 TRANSPARENT 3 IMAGE-FLIP S 0 0 PUT-IMAGE");
    try expectPixels(machine, &.{ 6, 5, 4, 3, 0, 1 });
    try std.testing.expectError(error.InvalidNumber, machine.interpretLine("4 IMAGE-FLIP"));
    machine.data_depth = 0;
    try std.testing.expectError(error.InvalidNumber, machine.interpretLine("-1 IMAGE-FLIP"));
    machine.data_depth = 0;
    try std.testing.expectError(error.InvalidNumber, machine.interpretLine("S 0 0 1 1 0 0 -1 4 0 128 1 GFX-COPY"));
    machine.data_depth = 0;
}

test "COPY-RECT within one image reads each pixel before writing over it" {
    try skipWithout(&.{.graphics});
    var output = Output{};
    const machine = try imageMachine(&output, "4 4");
    defer destroyMachine(machine);
    // Pixel x y has the color 10 y * x +.
    try machine.interpretLine(": FILL-XY 4 0 DO 4 0 DO I J 10 * I + J SWAP GFX-PSET LOOP LOOP ; FILL-XY");
    try machine.interpretLine("SCREEN 0 0 3 3 1 1 COPY-RECT");
    try expectPixels(machine, &.{ 0, 1, 2, 3, 10, 0, 1, 2, 20, 10, 11, 12, 30, 20, 21, 22 });
    try machine.interpretLine("FILL-XY SCREEN 1 1 3 3 0 0 COPY-RECT");
    try expectPixels(machine, &.{ 11, 12, 13, 3, 21, 22, 23, 13, 31, 32, 33, 23, 30, 31, 32, 33 });
    try machine.interpretLine("FILL-XY 1 TRANSPARENT SCREEN 0 0 3 1 1 0 COPY-RECT -1 TRANSPARENT");
    // The 1 is left out, so the 2 under it stays.
    try expectPixels(machine, &.{ 0, 0, 2, 2, 10, 11, 12, 13, 20, 21, 22, 23, 30, 31, 32, 33 });
    // Flipped onto an overlapping place is refused; apart, it is copied.
    try std.testing.expectError(error.InvalidNumber, machine.interpretLine("FILL-XY 1 IMAGE-FLIP SCREEN 0 0 2 2 1 1 COPY-RECT"));
    machine.data_depth = 0;
    try machine.interpretLine("SCREEN 0 0 2 1 2 3 COPY-RECT 0 IMAGE-FLIP");
    try expectPixels(machine, &.{ 0, 1, 2, 3, 10, 11, 12, 13, 20, 21, 22, 23, 30, 31, 1, 0 });
}

test "restoring an image frees the images of the pool" {
    try skipWithout(&.{ .graphics, .image });
    var output = Output{};
    const machine = try imageMachine(&output, "2 2");
    defer destroyMachine(machine);
    try machine.interpretLine("1 1 NEW-IMAGE CONSTANT A  A DRAW-TO  2 2 NEW-IMAGE DROP");
    const image = try std.testing.allocator.alloc(u8, try machine.encodedSize());
    defer std.testing.allocator.free(image);
    _ = try machine.encodeImage(image);
    try machine.restoreImage(image);
    try std.testing.expectEqual(@as(usize, 0), output.images_live);
    try std.testing.expectEqual(@as(forth.Cell, 0), machine.gfx_target);
    try std.testing.expectError(error.InvalidImageHandle, machine.interpretLine("A DRAW-TO"));
    machine.data_depth = 0;
}

test "a host without the pool refuses NEW-IMAGE" {
    try skipWithout(&.{.graphics});
    var output = Output{};
    const machine = try imageMachine(&output, "2 2");
    defer destroyMachine(machine);
    machine.writer.image_alloc_fn = null;
    try std.testing.expectError(error.HostUnavailable, machine.interpretLine("1 1 NEW-IMAGE"));
    machine.data_depth = 0;
}

test "IMAGE-MODE puts the pixels over, XORed, added, or mixed by IMAGE-ALPHA" {
    try skipWithout(&.{.graphics});
    var output = Output{};
    const machine = try imageMachine(&output, "2 1");
    defer destroyMachine(machine);
    try machine.interpretLine("2 1 NEW-IMAGE CONSTANT S  S DRAW-TO  0 0 $F0A050 GFX-PSET  1 0 $204060 GFX-PSET  SCREEN DRAW-TO");
    try machine.interpretLine("$103090 GFX-CLS 1 IMAGE-MODE S 0 0 PUT-IMAGE");
    try expectPixels(machine, &.{ 0xF0A050 ^ 0x103090, 0x204060 ^ 0x103090 });
    try machine.interpretLine("$103090 GFX-CLS 2 IMAGE-MODE S 0 0 PUT-IMAGE");
    // Each color at most 255.
    try expectPixels(machine, &.{ 0xFFD0E0, 0x3070F0 });
    try machine.interpretLine("$103090 GFX-CLS 3 IMAGE-MODE S 0 0 PUT-IMAGE");
    // 128 at the start: (over * 128 + under * 127 + 127) / 255 for each color.
    try expectPixels(machine, &.{ 0x806870, 0x183878 });
    try machine.interpretLine("$103090 GFX-CLS 0 IMAGE-ALPHA S 0 0 PUT-IMAGE");
    try expectPixels(machine, &.{ 0x103090, 0x103090 });
    try machine.interpretLine("255 IMAGE-ALPHA S 0 0 PUT-IMAGE");
    try expectPixels(machine, &.{ 0xF0A050, 0x204060 });
    // The transparent color is left out before the mode.
    try machine.interpretLine("$103090 GFX-CLS 2 IMAGE-MODE $204060 TRANSPARENT S 0 0 PUT-IMAGE -1 TRANSPARENT 0 IMAGE-MODE");
    try expectPixels(machine, &.{ 0xFFD0E0, 0x103090 });
    for ([_][]const u8{ "4 IMAGE-MODE", "-1 IMAGE-MODE", "256 IMAGE-ALPHA", "-1 IMAGE-ALPHA", "S 0 0 1 1 0 0 -1 0 4 0 1 GFX-COPY", "S 0 0 1 1 0 0 -1 0 0 256 1 GFX-COPY" }) |line| {
        try std.testing.expectError(error.InvalidNumber, machine.interpretLine(line));
        machine.data_depth = 0;
    }
}

test "IMAGE-SCALE draws each pixel n by n, also flipped and cut at the edges" {
    try skipWithout(&.{.graphics});
    var output = Output{};
    const machine = try imageMachine(&output, "5 4");
    defer destroyMachine(machine);
    try machine.interpretLine("2 1 NEW-IMAGE CONSTANT S  S DRAW-TO  0 0 1 GFX-PSET  1 0 2 GFX-PSET  SCREEN DRAW-TO");
    try machine.interpretLine("2 IMAGE-SCALE S 1 1 PUT-IMAGE");
    try expectPixels(machine, &.{ 0, 0, 0, 0, 0, 0, 1, 1, 2, 2, 0, 1, 1, 2, 2, 0, 0, 0, 0, 0 });
    // Flipped, the blocks change places; cut at the left and the bottom.
    try machine.interpretLine("0 GFX-CLS 1 IMAGE-FLIP 3 IMAGE-SCALE S -1 2 PUT-IMAGE 0 IMAGE-FLIP");
    try expectPixels(machine, &.{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 2, 1, 1, 1, 2, 2, 1, 1, 1 });
    // A part of the source, transparent, and mixed.
    try machine.interpretLine("7 GFX-CLS 1 TRANSPARENT 2 IMAGE-SCALE S 0 0 2 1 0 0 COPY-RECT -1 TRANSPARENT");
    try expectPixels(machine, &.{ 7, 7, 2, 2, 7, 7, 7, 2, 2, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7 });
    // Sizes near 2^63 scaled: the places beyond 2^63 are reckoned without overflow.
    try machine.interpretLine("0 GFX-CLS 16 IMAGE-SCALE S -9223372036854775804 0 9223372036854775807 1 -9223372036854775807 0 COPY-RECT 1 IMAGE-SCALE");
    try expectPixels(machine, &.{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 });
    for ([_][]const u8{ "0 IMAGE-SCALE", "17 IMAGE-SCALE", "S 0 0 1 1 0 0 -1 0 0 128 0 GFX-COPY", "S 0 0 1 1 0 0 -1 0 0 128 17 GFX-COPY" }) |line| {
        try std.testing.expectError(error.InvalidNumber, machine.interpretLine(line));
        machine.data_depth = 0;
    }
    // Scaled within one image onto an overlapping place is refused; apart, it is copied.
    try machine.interpretLine("0 GFX-CLS 0 0 5 GFX-PSET 2 IMAGE-SCALE");
    try std.testing.expectError(error.InvalidNumber, machine.interpretLine("SCREEN 0 0 1 1 0 0 COPY-RECT"));
    machine.data_depth = 0;
    try machine.interpretLine("SCREEN 0 0 1 1 3 2 COPY-RECT 1 IMAGE-SCALE");
    try expectPixels(machine, &.{ 5, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 5, 5, 0, 0, 0, 5, 5 });
}