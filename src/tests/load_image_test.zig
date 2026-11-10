//! Tests of LOAD-IMAGE with PNG, BMP, and PPM/PGM files of every kind it reads. The files
//! in images/ follow simple formulas; Pillow wrote or checked each of them, and
//! images/expected.zig has the colors each should give.

const std = @import("std");
const forth = @import("../forth.zig");
const graphics_images = @import("../core/graphics_images.zig");
const expected = @import("images/expected.zig");
const support = @import("support.zig");
const Output = support.Output;
const createMachine = support.createMachine;
const destroyMachine = support.destroyMachine;
const expectStack = support.expectStack;
const skipWithout = support.skipWithout;

fn imageMachine(output: *Output) !*forth.State {
    const machine = try createMachine(output);
    errdefer destroyMachine(machine);
    try machine.interpretLine("REQUIRE-GRAPHICS ALSO GRAPHICS");
    return machine;
}

fn embedded(comptime name: []const u8) []const u8 {
    return @embedFile("images/" ++ name);
}

test "LOAD-IMAGE reads every kind of PNG, BMP, and PPM/PGM file" {
    try skipWithout(&.{.graphics});
    var output = Output{};
    const machine = try imageMachine(&output);
    defer destroyMachine(machine);
    try machine.interpretLine("$123456 TRANSPARENT");
    inline for (expected.files) |file| {
        support.setFakeFile(&output, 0, embedded(file[0]));
        machine.interpretLine("S\" a.txt\" LOAD-IMAGE DUP DRAW-TO IMAGE-SIZE") catch |err| {
            std.debug.print("{s}: {s}\n", .{ file[0], @errorName(err) });
            return err;
        };
        try expectStack(machine, &.{ expected.width, expected.height });
        machine.data_depth = 0;
        const canvas = try graphics_images.target(machine);
        for (canvas.pixels, file[1], 0..) |pixel, color, index| {
            if (pixel != 0xff00_0000 | color) {
                std.debug.print("{s}: pixel {d} is {x:0>6}, not {x:0>6}\n", .{ file[0], index, pixel & 0xffffff, color });
                return error.TestExpectedEqual;
            }
        }
        try machine.interpretLine("DRAWING FREE-IMAGE");
    }
    try std.testing.expectEqual(@as(usize, 0), output.images_live);
}

test "LOAD-IMAGE gives black to transparent pixels when there is no transparent color" {
    try skipWithout(&.{.graphics});
    var output = Output{};
    const machine = try imageMachine(&output);
    defer destroyMachine(machine);
    support.setFakeFile(&output, 0, embedded("rgba8.png"));
    try machine.interpretLine("S\" a.txt\" LOAD-IMAGE DRAW-TO 0 0 GFX-PGET 1 0 GFX-PGET");
    // Pixel 0 0 has alpha 0, pixel 1 0 alpha 200.
    try expectStack(machine, &.{ 0, 0x240000 | 7 });
}

test "LOAD-IMAGE refuses damaged files and changes nothing" {
    try skipWithout(&.{.graphics});
    var output = Output{};
    const machine = try imageMachine(&output);
    defer destroyMachine(machine);
    const png = embedded("rgb8.png");
    const bmp = embedded("rgb24.bmp");
    var buffer: [1024]u8 = undefined;
    // Not an image, empty, cut short, a damaged IDAT, a BMP whose pixels are missing,
    // RLE compression, a PNM with a sample over its maximum.
    const cases = [_][]const u8{
        "hello",
        "",
        png[0..40],
        png[0 .. png.len - 30],
        "P5 2 2 15\n\x01\x02\x03\x10",
        "P3 1 1 255 1 2",
        "P6 0 3 255\n",
    };
    for (cases) |bytes| {
        support.setFakeFile(&output, 0, bytes);
        try std.testing.expectError(error.ImageInvalid, machine.interpretLine("S\" a.txt\" LOAD-IMAGE"));
        machine.data_depth = 0;
    }
    @memcpy(buffer[0..png.len], png);
    // A byte of the compressed data changed: the zlib checksum or the decoding fails.
    buffer[png.len - 20] ^= 0x55;
    support.setFakeFile(&output, 0, buffer[0..png.len]);
    try std.testing.expectError(error.ImageInvalid, machine.interpretLine("S\" a.txt\" LOAD-IMAGE"));
    machine.data_depth = 0;
    @memcpy(buffer[0..bmp.len], bmp);
    buffer[30] = 1;
    support.setFakeFile(&output, 0, buffer[0..bmp.len]);
    try std.testing.expectError(error.ImageInvalid, machine.interpretLine("S\" a.txt\" LOAD-IMAGE"));
    machine.data_depth = 0;
    support.setFakeFile(&output, 0, bmp[0 .. bmp.len - 10]);
    try std.testing.expectError(error.ImageInvalid, machine.interpretLine("S\" a.txt\" LOAD-IMAGE"));
    machine.data_depth = 0;
    try std.testing.expectEqual(@as(usize, 0), output.images_live);
    try machine.interpretLine("S\" a.txt\" ' LOAD-IMAGE CATCH NIP NIP");
    try expectStack(machine, &.{-279});
    machine.data_depth = 0;

    // A file that does not open gives the ior of the host.
    try machine.interpretLine("S\" z.txt\" ' LOAD-IMAGE CATCH NIP NIP S\" z.txt\" -1 GFX-IMAGE-LOAD");
    try expectStack(machine, &.{ forth.errnoIor(2), 0, forth.errnoIor(2) });
    machine.data_depth = 0;

    // A picture larger than an image may be.
    support.setFakeFile(&output, 0, "P6 16385 1 255\n");
    try std.testing.expectError(error.InvalidNumber, machine.interpretLine("S\" a.txt\" LOAD-IMAGE"));
    machine.data_depth = 0;
    // A BMP of 2147483647 by 2147483647 pixels of 32 bits: refused before the size of its
    // rows is reckoned, which would not fit in 64 bits.
    @memcpy(buffer[0..bmp.len], bmp);
    std.mem.writeInt(i32, buffer[18..22], std.math.maxInt(i32), .little);
    std.mem.writeInt(i32, buffer[22..26], std.math.maxInt(i32), .little);
    std.mem.writeInt(u16, buffer[28..30], 32, .little);
    support.setFakeFile(&output, 0, buffer[0..bmp.len]);
    try std.testing.expectError(error.InvalidNumber, machine.interpretLine("S\" a.txt\" LOAD-IMAGE"));
    machine.data_depth = 0;
    try std.testing.expectEqual(@as(usize, 0), output.images_live);
}
