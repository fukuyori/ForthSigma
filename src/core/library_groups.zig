//! Canonical list of lazy word groups, shared by both image-append paths.
pub const groups = .{
    @import("words_graphics.zig").group,
    @import("words_audio.zig").group,
    @import("words_gui.zig").group,
    @import("words_game.zig").group,
    @import("words_extension.zig").group,
};
