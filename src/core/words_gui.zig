//! The GUI words: REQUIRE-GUI, which loads them. They are Forth only (src/graphics/gui.fs):
//! the group has no built-in words, so a dictionary with them is saved as one with the
//! graphics words, and REQUIRE-GUI loads the graphics words first.

const defs = @import("defs.zig");
const forth = @import("../forth.zig");
const library_loading = @import("library_loading.zig");
const memory_map = @import("memory_map.zig");
const words_graphics = @import("words_graphics.zig");
const RuntimeError = defs.RuntimeError;
const State = forth.State;

/// The GUI library, which REQUIRE-GUI interprets into the GUI vocabulary.
pub const library = @embedFile("../graphics/gui.fs");

/// The name the library has in the source file table, for LOCATE and error messages.
pub const library_name = "*gui library*";

/// The words of the library that HELP describes; the help test checks that the library
/// defines each of them.
pub const library_words = [_][]const u8{ "GUI-BACKGROUND", "GUI-FACE", "GUI-HOVER", "GUI-PRESSED", "GUI-TEXT", "GUI-DISABLED", "GUI-BORDER", "GUI-FIELD-FACE", "GUI-FOCUS", "GUI-SELECTION", "GUI-SELECTED-TEXT", "GUI-DEFAULT", "GUI-COLOR!", "GUI-COLOR@", "GUI-BORDER-WIDTH", "GUI-FOCUS-WIDTH", "GUI-KEY", "GUI-ENABLE", "GUI-BEGIN", "GUI-END", "GUI-TILES", "GUI-PANEL", "GUI-LABEL", "GUI-BUTTON-SIZE", "GUI-BUTTON", "GUI-CHECK", "GUI-FIELD", "GUI-LIST", "GUI-MENUBAR", "GUI-MENU", "GUI-FKEYS", "GUI-DIALOG", "GUI-YES-NO", "GUI-ASK", "GUI-MESSAGE", "GUI-CHOOSE" };

pub const group: library_loading.Group(@TypeOf(words_graphics.definitions[0])) = .{
    .vocabulary = "GUI",
    .definitions = &.{},
    .library_name = library_name,
    .vocabulary_address = memory_map.gui_vocabulary_address,
    .prerequisites = &.{.{ .require = words_graphics.requireGraphics, .vocabulary_address = memory_map.graphics_vocabulary_address }},
};

/// REQUIRE-GUI: the first time, loads the graphics words if they are not loaded, then
/// appends the GUI vocabulary and the GUI library; later it does nothing.
pub fn requireGui(self: *State) RuntimeError!void {
    if (!defs.graphics_enabled) return error.GraphicsUnavailable;
    return library_loading.require(self, group, self.gui_library);
}

/// Whether REQUIRE-GUI has loaded the GUI words and they are still in the dictionary.
pub fn guiLoaded(self: *const State) bool {
    return library_loading.isLoaded(self, group);
}

/// Whether a word is one the GUI library defined (HELP describes these).
pub fn isGuiWord(self: *const State, word: defs.Word) bool {
    return word.kind != .builtin and library_loading.isGroupWord(self, word, library_name);
}
