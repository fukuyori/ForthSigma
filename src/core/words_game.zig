//! The game words: REQUIRE-GAME, which loads them. They are Forth (src/graphics/game.fs)
//! over two GFX- words, GFX-PIXEL and GFX-TILEMAP: the group has no built-in words of
//! its own, so a dictionary with them is saved as one with the graphics words, and
//! REQUIRE-GAME loads the graphics words first.

const defs = @import("defs.zig");
const forth = @import("../forth.zig");
const library_loading = @import("library_loading.zig");
const memory_map = @import("memory_map.zig");
const words_graphics = @import("words_graphics.zig");
const RuntimeError = defs.RuntimeError;
const State = forth.State;

/// The game library, which REQUIRE-GAME interprets into the GAME vocabulary.
pub const library = @embedFile("../graphics/game.fs");

/// The name the library has in the source file table, for LOCATE and error messages.
pub const library_name = "*game library*";

/// The words of the library that HELP describes; the help test checks that the library
/// defines each of them.
pub const library_words = [_][]const u8{ "/SPRITE", "SPRITE-X", "SPRITE-Y", "SPRITE-IMAGE", "SPRITE-SX", "SPRITE-SY", "SPRITE-W", "SPRITE-H", "SPRITE-FRAMES", "SPRITE-FRAME", "SPRITE-DELAY", "SPRITE-TICK", "SPRITE-FLIP", "SPRITE-KEY", "SPRITE-SHOWN", "INIT-SPRITE", "SPRITE:", "PUT-SPRITE", "SPRITE-ANIM", "ANIMATE", "DRAW-SPRITE", "HIT?", "SPRITE-PIXEL?", "PIXEL-HIT?", "/TILEMAP", "TILEMAP-IMAGE", "TILEMAP-TW", "TILEMAP-TH", "TILEMAP-COLS", "TILEMAP-ROWS", "TILEMAP-KEY", "TILEMAP-DATA", "TILEMAP:", "TILE@", "TILE!", ">TILE", "DRAW-TILEMAP" };

pub const group: library_loading.Group(@TypeOf(words_graphics.definitions[0])) = .{
    .vocabulary = "GAME",
    .definitions = &.{},
    .library_name = library_name,
    .vocabulary_address = memory_map.game_vocabulary_address,
    .prerequisites = &.{.{ .require = words_graphics.requireGraphics, .vocabulary_address = memory_map.graphics_vocabulary_address }},
};

/// REQUIRE-GAME: the first time, loads the graphics words if they are not loaded, then
/// appends the GAME vocabulary and the game library; later it does nothing.
pub fn requireGame(self: *State) RuntimeError!void {
    if (!defs.graphics_enabled) return error.GraphicsUnavailable;
    return library_loading.require(self, group, self.game_library);
}

/// Whether REQUIRE-GAME has loaded the game words and they are still in the dictionary.
pub fn gameLoaded(self: *const State) bool {
    return library_loading.isLoaded(self, group);
}

/// Whether a word is one the game library defined (HELP describes these).
pub fn isGameWord(self: *const State, word: defs.Word) bool {
    return word.kind != .builtin and library_loading.isGroupWord(self, word, library_name);
}
