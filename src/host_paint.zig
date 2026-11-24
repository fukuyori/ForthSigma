//! Single native window source. Tk and graphics-disabled paths have no capability.
pub const Source = @import("core/task_paint.zig").Source;
const builtin = @import("builtin");
const options = @import("build_options");
pub var source: Source = .{ .capable = options.graphics and
    (builtin.os.tag == .windows or builtin.os.tag == .macos or
        (builtin.os.tag == .linux and options.x11)) };

/// Read the actual GRAPHICS (DISPLAY), independent of the caller's search order.
/// No Forth is executed and an unresolved automatic selection has no capability.
pub fn selectedNative(state: *@import("forth.zig").State) bool {
    if (!options.graphics) return false;
    const graphics = @import("core/words_graphics.zig");
    if (!@import("core/library_loading.zig").isLoaded(state, graphics.group)) return false;
    const vocabulary = state.readCellConst(@import("core/memory_map.zig").graphics_vocabulary_address);
    const id = state.lookupIn("(DISPLAY)", state.words[@intCast(vocabulary)].value) orelse return false;
    const word = state.words[id];
    if (word.kind != .variable) return false;
    const display = state.readCell(word.value) catch return false;
    return (if (display == 0) state.gfx_auto_display else display) == 2;
}
