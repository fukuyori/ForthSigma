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
    for ([_][]const u8{ "6 IMAGE-MODE", "-1 IMAGE-MODE", "256 IMAGE-ALPHA", "-1 IMAGE-ALPHA", "S 0 0 1 1 0 0 -1 0 6 0 1 GFX-COPY", "S 0 0 1 1 0 0 -1 0 0 256 1 GFX-COPY" }) |line| {
        try std.testing.expectError(error.InvalidNumber, machine.interpretLine(line));
        machine.data_depth = 0;
    }
}

test "IMAGE-MODE 4 and 5 put each pixel over by its own alpha, and the screen stays opaque" {
    try skipWithout(&.{.graphics});
    var output = Output{};
    const machine = try imageMachine(&output, "3 1");
    defer destroyMachine(machine);
    // An image of white pixels with the alphas 255, 128, and 0.
    try machine.interpretLine("3 1 NEW-IMAGE CONSTANT S  S DRAW-TO  $FFFFFF GFX-CLS  1 0 128 GFX-ALPHA-PSET  2 0 0 GFX-ALPHA-PSET");
    try machine.interpretLine("S 0 0 GFX-IMAGE-ALPHA@ S 1 0 GFX-IMAGE-ALPHA@ S 2 0 GFX-IMAGE-ALPHA@ S 3 0 GFX-IMAGE-ALPHA@ S 1 0 GFX-PIXEL SCREEN 0 0 GFX-IMAGE-ALPHA@");
    try expectStack(machine, &.{ 255, 128, 0, -1, 0xFFFFFF, 255 });
    machine.data_depth = 0;
    // Over black: all of it, half of it (255 × 128 / 255), none of it.
    try machine.interpretLine("SCREEN DRAW-TO 0 GFX-CLS 4 IMAGE-MODE S 0 0 PUT-IMAGE");
    try expectPixels(machine, &.{ 0xFFFFFF, 0x808080, 0x000000 });
    // Over a color: (255 × 128 + under × 127 + 127) / 255 for each.
    try machine.interpretLine("$204060 GFX-CLS S 0 0 PUT-IMAGE");
    try expectPixels(machine, &.{ 0xFFFFFF, 0x90A0B0, 0x204060 });
    // Mode 5: the alpha times IMAGE-ALPHA / 255. With 128: 128, 64, and 0 of 255.
    try machine.interpretLine("0 GFX-CLS 5 IMAGE-MODE 128 IMAGE-ALPHA S 0 0 PUT-IMAGE");
    try expectPixels(machine, &.{ 0x808080, 0x404040, 0x000000 });
    try machine.interpretLine("0 GFX-CLS 255 IMAGE-ALPHA S 0 0 PUT-IMAGE");
    try expectPixels(machine, &.{ 0xFFFFFF, 0x808080, 0x000000 });
    try machine.interpretLine("$204060 GFX-CLS 0 IMAGE-ALPHA S 0 0 PUT-IMAGE");
    try expectPixels(machine, &.{ 0x204060, 0x204060, 0x204060 });
    // The transparent color is left out before the alpha, and the modes before keep
    // their results with such an image: mode 3 mixes by IMAGE-ALPHA alone.
    try machine.interpretLine("0 GFX-CLS 4 IMAGE-MODE $FFFFFF TRANSPARENT S 0 0 PUT-IMAGE -1 TRANSPARENT");
    try expectPixels(machine, &.{ 0, 0, 0 });
    try machine.interpretLine("0 GFX-CLS 3 IMAGE-MODE 255 IMAGE-ALPHA S 0 0 PUT-IMAGE");
    try expectPixels(machine, &.{ 0xFFFFFF, 0xFFFFFF, 0xFFFFFF });
    // Mode 0 copies the pixels as they are; on the screen they are opaque all the same.
    try machine.interpretLine("0 GFX-CLS 0 IMAGE-MODE S 0 0 PUT-IMAGE SCREEN 0 0 GFX-IMAGE-ALPHA@ SCREEN 1 0 GFX-IMAGE-ALPHA@ SCREEN 2 0 GFX-IMAGE-ALPHA@");
    try expectStack(machine, &.{ 255, 255, 255 });
    machine.data_depth = 0;
    try expectPixels(machine, &.{ 0xFFFFFF, 0xFFFFFF, 0xFFFFFF });
    for (machine.gfx_pixels) |pixel| try std.testing.expectEqual(@as(u32, 0xff), pixel >> 24);
    // To another image of the pool the alpha goes with the pixels (mode 0), and mode 4
    // over a wholly transparent image gives the pixels with their alpha.
    try machine.interpretLine("3 1 NEW-IMAGE CONSTANT T  T DRAW-TO S 0 0 PUT-IMAGE T 0 0 GFX-IMAGE-ALPHA@ T 1 0 GFX-IMAGE-ALPHA@ T 2 0 GFX-IMAGE-ALPHA@");
    try expectStack(machine, &.{ 255, 128, 0 });
    machine.data_depth = 0;
    try machine.interpretLine("0 GFX-CLS 0 GFX-ALPHA-CLS 4 IMAGE-MODE S 0 0 PUT-IMAGE T 0 0 GFX-IMAGE-ALPHA@ T 1 0 GFX-IMAGE-ALPHA@ T 2 0 GFX-IMAGE-ALPHA@ T 1 0 GFX-PIXEL");
    try expectStack(machine, &.{ 255, 128, 0, 0xFFFFFF });
    machine.data_depth = 0;
    // GFX-ALPHA-PSET and GFX-ALPHA-CLS keep the colors, follow CLIP!, and are not for the screen.
    try machine.interpretLine("$123456 GFX-CLS 1 0 1 1 CLIP! 77 GFX-ALPHA-CLS 0 0 5 GFX-ALPHA-PSET 1 0 9 GFX-ALPHA-PSET NO-CLIP T 0 0 GFX-IMAGE-ALPHA@ T 1 0 GFX-IMAGE-ALPHA@ T 2 0 GFX-IMAGE-ALPHA@ T 1 0 GFX-PIXEL");
    try expectStack(machine, &.{ 255, 9, 255, 0x123456 });
    machine.data_depth = 0;
    try machine.interpretLine("5 5 9 GFX-ALPHA-PSET -1 0 9 GFX-ALPHA-PSET");
    for ([_][]const u8{ "0 0 256 GFX-ALPHA-PSET", "0 0 -1 GFX-ALPHA-PSET", "256 GFX-ALPHA-CLS", "-1 GFX-ALPHA-CLS" }) |line| {
        try std.testing.expectError(error.InvalidNumber, machine.interpretLine(line));
        machine.data_depth = 0;
    }
    try machine.interpretLine("SCREEN DRAW-TO");
    for ([_][]const u8{ "0 0 128 GFX-ALPHA-PSET", "128 GFX-ALPHA-CLS" }) |line| {
        try std.testing.expectError(error.InvalidImageHandle, machine.interpretLine(line));
        machine.data_depth = 0;
    }
    // Mode 5 rounds the alpha it uses first: alpha 1 times 128 / 255 is 1 (0.5 up), and
    // white over black by 1 of 255 is 1.
    try machine.interpretLine("S DRAW-TO 1 0 1 GFX-ALPHA-PSET SCREEN DRAW-TO 0 GFX-CLS 5 IMAGE-MODE 128 IMAGE-ALPHA S 0 0 PUT-IMAGE");
    try expectPixels(machine, &.{ 0x808080, 0x010101, 0x000000 });
    // The modes 1 to 3 do not look at the alpha of either pixel, and give opaque
    // pixels: on an image of the pool whose pixels are half transparent too.
    try machine.interpretLine("S DRAW-TO 1 0 128 GFX-ALPHA-PSET T DRAW-TO $103090 GFX-CLS 100 GFX-ALPHA-CLS 1 IMAGE-MODE S 0 0 PUT-IMAGE");
    try machine.interpretLine("T 0 0 GFX-PIXEL T 1 0 GFX-PIXEL T 2 0 GFX-PIXEL T 0 0 GFX-IMAGE-ALPHA@ T 1 0 GFX-IMAGE-ALPHA@ T 2 0 GFX-IMAGE-ALPHA@");
    try expectStack(machine, &.{ 0xFFFFFF ^ 0x103090, 0xFFFFFF ^ 0x103090, 0xFFFFFF ^ 0x103090, 255, 255, 255 });
    machine.data_depth = 0;
    try machine.interpretLine("$103090 GFX-CLS 100 GFX-ALPHA-CLS 2 IMAGE-MODE S 0 0 PUT-IMAGE T 1 0 GFX-PIXEL T 1 0 GFX-IMAGE-ALPHA@");
    try expectStack(machine, &.{ 0xFFFFFF, 255 });
    machine.data_depth = 0;
    try machine.interpretLine("$103090 GFX-CLS 100 GFX-ALPHA-CLS 3 IMAGE-MODE 128 IMAGE-ALPHA S 0 0 PUT-IMAGE T 1 0 GFX-PIXEL T 1 0 GFX-IMAGE-ALPHA@");
    // (255 × 128 + under × 127 + 127) / 255 for each color, as on an opaque image.
    try expectStack(machine, &.{ 0x8898C8, 255 });
    machine.data_depth = 0;
    // Flipped, enlarged, and with a transparent color: on the screen every pixel
    // written is opaque, by mode 0 and by mode 4.
    try machine.interpretLine("SCREEN DRAW-TO 0 GFX-CLS 0 IMAGE-MODE 1 IMAGE-FLIP S 0 0 PUT-IMAGE 0 IMAGE-FLIP");
    for (machine.gfx_pixels) |pixel| try std.testing.expectEqual(@as(u32, 0xff), pixel >> 24);
    try machine.interpretLine("0 GFX-CLS 2 IMAGE-SCALE S 1 0 1 1 0 0 COPY-RECT 1 IMAGE-SCALE");
    for (machine.gfx_pixels) |pixel| try std.testing.expectEqual(@as(u32, 0xff), pixel >> 24);
    try expectPixels(machine, &.{ 0xFFFFFF, 0xFFFFFF, 0x000000 });
    try machine.interpretLine("0 GFX-CLS 4 IMAGE-MODE $123456 TRANSPARENT 2 IMAGE-SCALE S 1 0 1 1 0 0 COPY-RECT 1 IMAGE-SCALE -1 TRANSPARENT");
    for (machine.gfx_pixels) |pixel| try std.testing.expectEqual(@as(u32, 0xff), pixel >> 24);
    try expectPixels(machine, &.{ 0x808080, 0x808080, 0x000000 });
    // Within one image, pixels with different alphas moved over each other keep theirs.
    try machine.interpretLine("S DRAW-TO 0 IMAGE-MODE S 0 0 2 1 1 0 COPY-RECT S 0 0 GFX-IMAGE-ALPHA@ S 1 0 GFX-IMAGE-ALPHA@ S 2 0 GFX-IMAGE-ALPHA@");
    try expectStack(machine, &.{ 255, 255, 128 });
    machine.data_depth = 0;
    try machine.interpretLine("SCREEN DRAW-TO 0 IMAGE-MODE 128 IMAGE-ALPHA");
}

test "COPY-ROTATED-RECT turns a rectangle around its middle and makes it larger or smaller" {
    try skipWithout(&.{.graphics});
    var output = Output{};
    const machine = try imageMachine(&output, "5 5");
    defer destroyMachine(machine);
    const A = 0x112233;
    const B = 0x445566;
    const X = 0x777777;
    // A row of two pixels, A then B. Its middle pixel (the one at 2 / 2 = 1) is B.
    try machine.interpretLine("2 1 NEW-IMAGE CONSTANT S  S DRAW-TO  0 0 $112233 GFX-PSET  1 0 $445566 GFX-PSET  SCREEN DRAW-TO");
    // Not turned, as large as it is: B at 2 2 and A left of it, as COPY-RECT draws it.
    try machine.interpretLine("$777777 GFX-CLS S 0 0 2 1 2 2 0 1000 1000 COPY-ROTATED-RECT");
    try expectPixels(machine, &.{ X, X, X, X, X, X, X, X, X, X, X, A, B, X, X, X, X, X, X, X, X, X, X, X, X });
    // A quarter turn clockwise: what was left of the middle is above it.
    try machine.interpretLine("$777777 GFX-CLS S 2 2 9000 1000 PUT-ROTATED");
    try expectPixels(machine, &.{ X, X, X, X, X, X, X, A, X, X, X, X, B, X, X, X, X, X, X, X, X, X, X, X, X });
    // A half turn: right of it. Three quarters, and a quarter back: below it.
    try machine.interpretLine("$777777 GFX-CLS S 2 2 18000 1000 PUT-ROTATED");
    try expectPixels(machine, &.{ X, X, X, X, X, X, X, X, X, X, X, X, B, A, X, X, X, X, X, X, X, X, X, X, X });
    try machine.interpretLine("$777777 GFX-CLS S 2 2 27000 1000 PUT-ROTATED");
    try expectPixels(machine, &.{ X, X, X, X, X, X, X, X, X, X, X, X, B, X, X, X, X, A, X, X, X, X, X, X, X });
    try machine.interpretLine("$777777 GFX-CLS S 2 2 -9000 1000 PUT-ROTATED");
    try expectPixels(machine, &.{ X, X, X, X, X, X, X, X, X, X, X, X, B, X, X, X, X, A, X, X, X, X, X, X, X });
    // A whole turn and more is the angle that is left.
    try machine.interpretLine("$777777 GFX-CLS S 2 2 36000 9000 + 1000 PUT-ROTATED");
    try expectPixels(machine, &.{ X, X, X, X, X, X, X, A, X, X, X, X, B, X, X, X, X, X, X, X, X, X, X, X, X });
    // Twice as large: each pixel 2 by 2, the middle pixel's middle staying at 2 2's.
    try machine.interpretLine("$777777 GFX-CLS S 3 2 0 2000 PUT-ROTATED");
    try expectPixels(machine, &.{ X, X, X, X, X, A, A, B, B, X, A, A, B, B, X, X, X, X, X, X, X, X, X, X, X });
    // Twice as wide only, and turned a quarter: the width runs down. The middle pixel's
    // middle stays at 2 2's, so B is at 2 1 and 2 2, and A above them (its upper half
    // is off the image).
    try machine.interpretLine("$777777 GFX-CLS S 0 0 2 1 2 2 9000 2000 1000 COPY-ROTATED-RECT");
    try expectPixels(machine, &.{ X, X, A, X, X, X, X, B, X, X, X, X, B, X, X, X, X, X, X, X, X, X, X, X, X });
    // Half as large: one pixel of the two shows.
    try machine.interpretLine("$777777 GFX-CLS S 2 2 0 500 PUT-ROTATED");
    try std.testing.expectEqual(@as(usize, 24), std.mem.count(u32, machine.gfx_pixels, &.{0xff00_0000 | X}));
    // The transparent color is left out, and the mode holds: XOR of B and the ground.
    try machine.interpretLine("$777777 GFX-CLS $112233 TRANSPARENT 1 IMAGE-MODE S 2 2 0 1000 PUT-ROTATED -1 TRANSPARENT 0 IMAGE-MODE");
    try expectPixels(machine, &.{ X, X, X, X, X, X, X, X, X, X, X, X, B ^ X, X, X, X, X, X, X, X, X, X, X, X, X });
    // CLIP! cuts it, and a middle far away draws nothing and does not fail.
    try machine.interpretLine("$777777 GFX-CLS 2 0 3 5 CLIP! S 2 2 0 1000 PUT-ROTATED NO-CLIP");
    try expectPixels(machine, &.{ X, X, X, X, X, X, X, X, X, X, X, X, B, X, X, X, X, X, X, X, X, X, X, X, X });
    try machine.interpretLine("$777777 GFX-CLS S $7FFFFFFFFFFFFFFF $8000000000000000 4500 64000 PUT-ROTATED S 0 0 $7FFFFFFFFFFFFFFF $7FFFFFFFFFFFFFFF $8000000000000000 0 1234 1 1 COPY-ROTATED-RECT");
    try std.testing.expectEqual(@as(usize, 25), std.mem.count(u32, machine.gfx_pixels, &.{0xff00_0000 | X}));
    // A part of the source outside the image is left out: only its pixel 1 0 is there.
    try machine.interpretLine("$777777 GFX-CLS S 1 0 3 3 2 2 0 1000 1000 COPY-ROTATED-RECT");
    try expectPixels(machine, &.{ X, X, X, X, X, X, B, X, X, X, X, X, X, X, X, X, X, X, X, X, X, X, X, X, X });
    // Refused: factors of 0, below 0, and above 64 times; a mode that is not there; an
    // image turned onto itself.
    for ([_][]const u8{
        "S 2 2 0 0 PUT-ROTATED",              "S 2 2 0 -1000 PUT-ROTATED", "S 2 2 0 64001 PUT-ROTATED",
        "S 0 0 2 1 2 2 0 1000 0 COPY-ROTATED-RECT", "SCREEN 2 2 0 1000 PUT-ROTATED",
        "S 0 0 2 1 2 2 0 1000 1000 -1 6 0 0 GFX-ROTATE", "S 0 0 2 1 2 2 0 1000 1000 -1 0 256 0 GFX-ROTATE",
    }) |line| {
        try std.testing.expectError(error.InvalidNumber, machine.interpretLine(line));
        machine.data_depth = 0;
    }
    // Nothing of an empty rectangle.
    try machine.interpretLine("$777777 GFX-CLS S 0 0 0 1 2 2 0 1000 1000 COPY-ROTATED-RECT S 0 0 2 -1 2 2 0 1000 1000 COPY-ROTATED-RECT");
    try std.testing.expectEqual(@as(usize, 25), std.mem.count(u32, machine.gfx_pixels, &.{0xff00_0000 | X}));
}

test "COPY-ROTATED-RECT reaches as far as the rectangle goes, and puts each pixel where it belongs" {
    try skipWithout(&.{.graphics});
    var output = Output{};
    const machine = try imageMachine(&output, "200 1");
    defer destroyMachine(machine);
    const A = 0x112233;
    const B = 0x445566;
    const X = 0x777777;
    try machine.interpretLine("2 1 NEW-IMAGE CONSTANT S  S DRAW-TO  0 0 $112233 GFX-PSET  1 0 $445566 GFX-PSET  SCREEN DRAW-TO");
    // 64 times as wide around the middle of its second pixel, which is at 100: the
    // first pixel covers 4 to 67 and the second 68 to 131.
    try machine.interpretLine("$777777 GFX-CLS S 0 0 2 1 100 0 0 64000 1000 COPY-ROTATED-RECT");
    try machine.interpretLine("3 0 GFX-PGET 4 0 GFX-PGET 67 0 GFX-PGET 68 0 GFX-PGET 131 0 GFX-PGET 132 0 GFX-PGET");
    try expectStack(machine, &.{ X, A, A, B, B, X });
    machine.data_depth = 0;
    try std.testing.expectEqual(@as(usize, 64), std.mem.count(u32, machine.gfx_pixels, &.{0xff00_0000 | A}));
    try std.testing.expectEqual(@as(usize, 64), std.mem.count(u32, machine.gfx_pixels, &.{0xff00_0000 | B}));
    // Smoothed, it reaches half a pixel of the source (32 pixels here) farther on each
    // side, fading: the pixel 0 shows a part of the first color over the ground. The
    // first color is whole at 36 (the middle of its pixel), and the second at 100; at
    // 99 the two are mixed 4 to 252 of 256.
    try machine.interpretLine("$777777 GFX-CLS TRUE IMAGE-SMOOTH 4 IMAGE-MODE S 0 0 2 1 100 0 0 64000 1000 COPY-ROTATED-RECT 0 IMAGE-MODE FALSE IMAGE-SMOOTH");
    try machine.interpretLine("0 0 GFX-PGET $777777 <> 199 0 GFX-PGET 36 0 GFX-PGET 99 0 GFX-PGET 100 0 GFX-PGET 164 0 GFX-PGET");
    try expectStack(machine, &.{ -1, X, A, 0x435465, B, X });
    machine.data_depth = 0;
    // 6 times as wide: the places are thirds that do not come out even, and each pixel
    // still gets its own. Around 5, the first pixel covers -4 to 1 and the second 2 to 7.
    try machine.interpretLine("$777777 GFX-CLS S 0 0 2 1 5 0 0 6000 1000 COPY-ROTATED-RECT 0 0 GFX-PGET 1 0 GFX-PGET 2 0 GFX-PGET 7 0 GFX-PGET 8 0 GFX-PGET");
    try expectStack(machine, &.{ A, A, B, B, X });
    machine.data_depth = 0;
    // The same pixels whatever CLIP! cuts off before them.
    try machine.interpretLine("$777777 GFX-CLS 1 0 199 1 CLIP! S 0 0 2 1 5 0 0 6000 1000 COPY-ROTATED-RECT NO-CLIP 0 0 GFX-PGET 1 0 GFX-PGET 2 0 GFX-PGET 7 0 GFX-PGET 8 0 GFX-PGET");
    try expectStack(machine, &.{ X, A, B, B, X });
    machine.data_depth = 0;
    // Without smoothing a pixel is put as COPY-RECT puts it: to another image mode 0
    // keeps its alpha, and the modes 1 to 3 take its color whatever its alpha.
    try machine.interpretLine("S DRAW-TO 0 0 0 GFX-ALPHA-PSET 1 0 128 GFX-ALPHA-PSET 2 1 NEW-IMAGE CONSTANT T T DRAW-TO S 1 0 0 1000 PUT-ROTATED");
    try machine.interpretLine("T 0 0 GFX-IMAGE-ALPHA@ T 1 0 GFX-IMAGE-ALPHA@ T 0 0 GFX-PIXEL T 1 0 GFX-PIXEL");
    try expectStack(machine, &.{ 0, 128, A, B });
    machine.data_depth = 0;
    try machine.interpretLine("$103090 GFX-CLS 1 IMAGE-MODE S 1 0 0 1000 PUT-ROTATED 0 IMAGE-MODE T 0 0 GFX-PIXEL T 1 0 GFX-PIXEL T 0 0 GFX-IMAGE-ALPHA@");
    try expectStack(machine, &.{ A ^ 0x103090, B ^ 0x103090, 255 });
    machine.data_depth = 0;
    try machine.interpretLine("SCREEN DRAW-TO");
}

test "IMAGE-SMOOTH mixes the pixels around each place, by their alpha" {
    try skipWithout(&.{.graphics});
    var output = Output{};
    const machine = try imageMachine(&output, "6 1");
    defer destroyMachine(machine);
    const X = 0xFF0000;
    // Black then white.
    try machine.interpretLine("2 1 NEW-IMAGE CONSTANT S  S DRAW-TO  0 0 0 GFX-PSET  1 0 $FFFFFF GFX-PSET  SCREEN DRAW-TO TRUE IMAGE-SMOOTH");
    // As large as it is, a place is the middle of one pixel: the same as without.
    try machine.interpretLine("$FF0000 GFX-CLS S 3 0 0 1000 PUT-ROTATED");
    try expectPixels(machine, &.{ X, X, 0x000000, 0xFFFFFF, X, X });
    // Twice as wide: at the left edge half of black and nothing (it shows half, and is
    // drawn), black, black and white half and half, white, and at the right edge half
    // of white and nothing.
    try machine.interpretLine("$FF0000 GFX-CLS S 0 0 2 1 3 0 0 2000 1000 COPY-ROTATED-RECT");
    try expectPixels(machine, &.{ 0x000000, 0x000000, 0x808080, 0xFFFFFF, 0xFFFFFF, X });
    // By mode 4 the halves that show are put over the ground by half.
    try machine.interpretLine("$FF0000 GFX-CLS 4 IMAGE-MODE S 0 0 2 1 3 0 0 2000 1000 COPY-ROTATED-RECT 0 IMAGE-MODE");
    try expectPixels(machine, &.{ 0x7F0000, 0x000000, 0x808080, 0xFFFFFF, 0xFF8080, X });
    // A pixel with alpha 0 gives no color to its neighbors: white with alpha 0 beside
    // black stays black where they mix, half as strong.
    try machine.interpretLine("S DRAW-TO 1 0 0 GFX-ALPHA-PSET SCREEN DRAW-TO $FF0000 GFX-CLS 4 IMAGE-MODE S 0 0 2 1 3 0 0 2000 1000 COPY-ROTATED-RECT 0 IMAGE-MODE");
    try expectPixels(machine, &.{ 0x7F0000, 0x000000, 0x7F0000, X, X, X });
    for (machine.gfx_pixels) |pixel| try std.testing.expectEqual(@as(u32, 0xff), pixel >> 24);
    try machine.interpretLine("FALSE IMAGE-SMOOTH");
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