//! Tests of REQUIRE-GAME: sprites, their animation and hits, tile maps, and the two GFX-
//! words under them.

const std = @import("std");
const forth = @import("../forth.zig");
const graphics_images = @import("../core/graphics_images.zig");
const words_game = @import("../core/words_game.zig");
const words_graphics = @import("../core/words_graphics.zig");
const support = @import("support.zig");
const Output = support.Output;
const createMachine = support.createMachine;
const destroyMachine = support.destroyMachine;
const expectStack = support.expectStack;
const skipWithout = support.skipWithout;

/// A machine with the game words, drawing on a 16 by 8 image, and a sheet of 4 by 4 tiles:
/// tile 0 red with a black corner pixel, 1 green, 2 blue, 3 white, two rows of two.
fn gameMachine(output: *Output) !*forth.State {
    const machine = try createMachine(output);
    errdefer destroyMachine(machine);
    try machine.interpretLine("REQUIRE-GAME ALSO GRAPHICS ALSO GAME 8 8 GFX-INIT");
    try machine.interpretLine("8 8 NEW-IMAGE CONSTANT SHEET  SHEET DRAW-TO $FF0000 COLOR! 0 0 4 4 FILL-RECT $00FF00 COLOR! 4 0 4 4 FILL-RECT");
    try machine.interpretLine("$0000FF COLOR! 0 4 4 4 FILL-RECT $FFFFFF COLOR! 4 4 4 4 FILL-RECT 0 0 0 GFX-PSET");
    try machine.interpretLine("16 8 NEW-IMAGE CONSTANT VIEW  VIEW DRAW-TO");
    return machine;
}

/// The colors of the image drawn on, row by row.
fn expectPixels(machine: *forth.State, expected: []const forth.Cell) !void {
    const canvas = try graphics_images.target(machine);
    try std.testing.expectEqual(expected.len, canvas.pixels.len);
    for (canvas.pixels, expected, 0..) |pixel, color, index| {
        if (@as(forth.Cell, pixel & 0xffffff) != color) {
            std.debug.print("pixel {d}: {x:0>6}, not {x:0>6}\n", .{ index, pixel & 0xffffff, color });
            return error.TestExpectedEqual;
        }
    }
}

const R = 0xFF0000;
const G = 0x00FF00;
const B = 0x0000FF;
const W = 0xFFFFFF;
const K = 0x000000;

test "REQUIRE-GAME loads the graphics words first, once" {
    try skipWithout(&.{.graphics});
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    try machine.interpretLine("REQUIRE-GAME");
    try std.testing.expect(words_graphics.graphicsLoaded(machine));
    try std.testing.expect(words_game.gameLoaded(machine));
    try std.testing.expect(machine.lookup("DRAW-SPRITE") == null);
    const words = machine.word_count;
    try machine.interpretLine("REQUIRE-GAME GAME /SPRITE /TILEMAP FORTH");
    try expectStack(machine, &.{ 14 * 8, 6 * 8 });
    try std.testing.expectEqual(words, machine.word_count);
}

test "GFX-PIXEL reads any image, -1 outside it" {
    try skipWithout(&.{.graphics});
    var output = Output{};
    const machine = try gameMachine(&output);
    defer destroyMachine(machine);
    try machine.interpretLine("SHEET 5 1 GFX-PIXEL SHEET 0 0 GFX-PIXEL SHEET 8 0 GFX-PIXEL SHEET -1 0 GFX-PIXEL SCREEN 0 0 GFX-PIXEL");
    try expectStack(machine, &.{ G, K, -1, -1, 0 });
    machine.data_depth = 0;
    try std.testing.expectError(error.InvalidImageHandle, machine.interpretLine("12345 0 0 GFX-PIXEL"));
}

test "a sprite is drawn with its frame, flip, and transparent color, and animates" {
    try skipWithout(&.{.graphics});
    var output = Output{};
    const machine = try gameMachine(&output);
    defer destroyMachine(machine);
    // Two frames of 4 by 4: the red tile and the green one.
    try machine.interpretLine("SHEET 0 0 4 4 SPRITE: S  2 3 S SPRITE-ANIM  1 2 S PUT-SPRITE  0 GFX-CLS S DRAW-SPRITE");
    try expectPixels(machine, &.{
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, K, R, R, R, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, R, R, R, R, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, R, R, R, R, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, R, R, R, R, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    });
    // Three steps of ANIMATE show the next frame; three more, the first again.
    try machine.interpretLine("S ANIMATE S ANIMATE S SPRITE-FRAME @ S ANIMATE S SPRITE-FRAME @ S ANIMATE S ANIMATE S ANIMATE S SPRITE-FRAME @");
    try expectStack(machine, &.{ 0, 1, 0 });
    machine.data_depth = 0;
    // Flipped both ways with black transparent: the corner pixel goes to the far corner
    // and is not drawn; hidden, nothing is drawn.
    try machine.interpretLine("$777777 GFX-CLS 3 S SPRITE-FLIP ! 0 S SPRITE-KEY ! 0 0 S PUT-SPRITE S DRAW-SPRITE 3 3 GFX-PGET 0 0 GFX-PGET");
    try expectStack(machine, &.{ 0x777777, R });
    machine.data_depth = 0;
    try machine.interpretLine("$777777 GFX-CLS FALSE S SPRITE-SHOWN ! S DRAW-SPRITE 0 0 GFX-PGET");
    try expectStack(machine, &.{0x777777});
}

test "HIT? tests the rectangles and PIXEL-HIT? the pixels that are shown" {
    try skipWithout(&.{.graphics});
    var output = Output{};
    const machine = try gameMachine(&output);
    defer destroyMachine(machine);
    // An array of two sprites, made by INIT-SPRITE.
    try machine.interpretLine("CREATE TWO 2 /SPRITE * ALLOT : SP ( n -- spr ) /SPRITE * TWO + ;");
    try machine.interpretLine("SHEET 0 0 4 4 0 SP INIT-SPRITE SHEET 0 0 4 4 1 SP INIT-SPRITE 0 1 SP SPRITE-KEY !");
    // The second overlaps the first only at its black corner pixel, which is transparent.
    try machine.interpretLine("0 0 0 SP PUT-SPRITE 3 3 1 SP PUT-SPRITE 0 SP 1 SP HIT? 0 SP 1 SP PIXEL-HIT?");
    try expectStack(machine, &.{ -1, 0 });
    machine.data_depth = 0;
    try machine.interpretLine("2 2 1 SP PUT-SPRITE 0 SP 1 SP PIXEL-HIT? 4 0 1 SP PUT-SPRITE 0 SP 1 SP HIT?");
    try expectStack(machine, &.{ -1, 0 });
    machine.data_depth = 0;
    // Flipped, the black pixel is at its far corner; a hidden sprite hits nothing.
    try machine.interpretLine("3 1 SP SPRITE-FLIP ! 3 3 1 SP PUT-SPRITE 0 SP 1 SP PIXEL-HIT? 0 1 SP SPRITE-SHOWN ! 0 SP 1 SP HIT?");
    try expectStack(machine, &.{ -1, 0 });
    machine.data_depth = 0;
    try machine.interpretLine("0 0 0 SP SPRITE-PIXEL? 1 0 0 SP SPRITE-PIXEL? 4 0 0 SP SPRITE-PIXEL?");
    try expectStack(machine, &.{ -1, -1, 0 });
}

test "a tile map is drawn as far as the view and the map go, over another with a key" {
    try skipWithout(&.{.graphics});
    var output = Output{};
    const machine = try gameMachine(&output);
    defer destroyMachine(machine);
    // A map of 3 by 2 tiles: 1 2 3 / 0 1 2.
    try machine.interpretLine("SHEET 4 4 3 2 TILEMAP: M  1 0 0 M TILE! 2 1 0 M TILE! 3 2 0 M TILE! 1 1 1 M TILE! 2 2 1 M TILE!");
    try machine.interpretLine("2 1 M TILE@ 1 0 M TILE@ 5 6 M >TILE -1 -1 M >TILE");
    try expectStack(machine, &.{ 2, 2, 1, 1, -1, -1 });
    machine.data_depth = 0;
    try std.testing.expectError(error.InvalidNumber, machine.interpretLine("3 0 M TILE@"));
    machine.data_depth = 0;
    try std.testing.expectError(error.InvalidNumber, machine.interpretLine("0 0 -1 M TILE!"));
    machine.data_depth = 0;
    // Seen from 2 1, in the view 1 0 12 by 8: the map ends 10 pixels to the right of
    // the view's left edge and 7 below its top.
    try machine.interpretLine("$777777 GFX-CLS 2 1 1 0 12 8 M DRAW-TILEMAP");
    const S = 0x777777;
    try expectPixels(machine, &.{
        S, G, G, B, B, B, B, W, W, W, W, S, S, S, S, S,
        S, G, G, B, B, B, B, W, W, W, W, S, S, S, S, S,
        S, G, G, B, B, B, B, W, W, W, W, S, S, S, S, S,
        S, R, R, G, G, G, G, B, B, B, B, S, S, S, S, S,
        S, R, R, G, G, G, G, B, B, B, B, S, S, S, S, S,
        S, R, R, G, G, G, G, B, B, B, B, S, S, S, S, S,
        S, R, R, G, G, G, G, B, B, B, B, S, S, S, S, S,
        S, S, S, S, S, S, S, S, S, S, S, S, S, S, S, S,
    });
    // A second map over the first, with green transparent: only its other colors show.
    try machine.interpretLine("SHEET 4 4 4 2 TILEMAP: FRONT  2 1 0 FRONT TILE!  1 0 0 FRONT TILE!  0 FRONT TILEMAP-KEY ! $00FF00 FRONT TILEMAP-KEY !");
    try machine.interpretLine("0 0 0 0 16 8 FRONT DRAW-TILEMAP 1 1 GFX-PGET 5 1 GFX-PGET 1 5 GFX-PGET");
    // Tile 1 (green) is transparent, tile 2 (blue) at col 1, tile 0 (red) below.
    try expectStack(machine, &.{ G, B, R });
    machine.data_depth = 0;
    // A view far outside the image, and an empty one, draw nothing and do not fail.
    try machine.interpretLine("-1000000 -1000000 -9223372036854775807 0 9223372036854775807 8 M DRAW-TILEMAP 0 0 0 0 0 0 M DRAW-TILEMAP");
    // The map's bytes must be in memory; tiles must have a size.
    try std.testing.expectError(error.InvalidAddress, machine.interpretLine("-8 2 2 SHEET 4 4 0 0 0 0 8 8 -1 GFX-TILEMAP"));
    machine.data_depth = 0;
    try std.testing.expectError(error.InvalidNumber, machine.interpretLine("M TILEMAP-DATA 3 2 SHEET 0 4 0 0 0 0 8 8 -1 GFX-TILEMAP"));
    machine.data_depth = 0;
    try std.testing.expectError(error.InvalidNumber, machine.interpretLine("SHEET 4 0 3 2 TILEMAP: BAD"));
}

test "sprites and maps are data in the dictionary, which an image keeps" {
    try skipWithout(&.{ .graphics, .image });
    var output = Output{};
    const machine = try gameMachine(&output);
    defer destroyMachine(machine);
    try machine.interpretLine("SHEET 0 0 4 4 SPRITE: S 5 6 S PUT-SPRITE SHEET 4 4 3 2 TILEMAP: M 3 2 1 M TILE!");
    const image = try std.testing.allocator.alloc(u8, machine.encodedSize());
    defer std.testing.allocator.free(image);
    _ = try machine.encodeImage(image);
    const restored = try createMachine(&output);
    defer destroyMachine(restored);
    try restored.restoreImage(image);
    try restored.interpretLine("S SPRITE-X @ S SPRITE-Y @ 2 1 M TILE@");
    try expectStack(restored, &.{ 5, 6, 3 });
}
