//! The graphics words: REQUIRE-GRAPHICS, which loads them, and the GFX- words, which
//! draw on one 32-bit image that the host keeps outside logical memory.
//!
//! The GFX- words are not among the built-in words every dictionary starts with:
//! REQUIRE-GRAPHICS appends them, with the GRAPHICS vocabulary and the graphics library
//! written in Forth, after the words already defined. A dictionary that never loads them
//! keeps the numbers of its words, and its images stay SIGIMG45.

const std = @import("std");
const defs = @import("defs.zig");
const forth = @import("../forth.zig");
const graphics_input = @import("graphics_input.zig");
const graphics_font = @import("graphics_font.zig");
const graphics_palette = @import("graphics_palette.zig");
const tcl = @import("tcl.zig");
const graphics_terminal = @import("graphics_terminal.zig");
const library_loading = @import("library_loading.zig");
const graphics_images = @import("graphics_images.zig");
const display_info = @import("display_info.zig");
const Canvas = graphics_images.Canvas;
const memory_map = @import("memory_map.zig");
const Builtin = defs.Builtin;
const Cell = memory_map.Cell;
const RuntimeError = defs.RuntimeError;
const State = forth.State;
const graphics_image_address = memory_map.graphics_image_address;
const graphics_vocabulary_address = memory_map.graphics_vocabulary_address;

/// The built-in words this file executes; executeBuiltin dispatches by this list.
pub const words = [_]Builtin{ .gfx_init, .gfx_width, .gfx_height, .gfx_pset, .gfx_pget, .gfx_hline, .gfx_cls, .gfx_save_ppm, .gfx_save_bmp, .gfx_show_blocks, .gfx_show_sixel, .gfx_show_window, .gfx_window_query, .gfx_save_png, .gfx_inkey, .gfx_mouse, .gfx_mouse_mode, .gfx_glyph_load, .gfx_glyph_box, .gfx_glyph_alpha, .gfx_font_height, .gfx_font_builtin, .gfx_font_load, .gfx_font_system, .gfx_color_mode, .gfx_tcl, .gfx_tcl_error, .gfx_tcl_event, .gfx_tcl_program, .gfx_tcl_stop, .gfx_show_tk, .gfx_key_held, .gfx_window_size, .gfx_gamepad_poll, .gfx_gamepad_query, .gfx_gamepad_name, .gfx_gamepad_map, .gfx_gamepad_guid, .gfx_mouse_event } ++ graphics_images.words ++ [_]Builtin{ .gfx_auto_display, .gfx_auto_display_set, .gfx_ime_preedit, .gfx_ime_caret, .gfx_auto_try, .gfx_fullscreen, .gfx_fullscreen_query, .gfx_mouse_cursor, .gfx_scan_input, .gfx_scan_supported, .gfx_scan_held, .gfx_key_event, .gfx_key_resync, .gfx_rgb, .gfx_displays, .gfx_display_info, .gfx_window_display, .gfx_window_state, .gfx_window_flags, .gfx_window_fit, .gfx_window_view, .gfx_window_frames, .gfx_frame_wait, .gfx_vsync_wait, .gfx_clip, .gfx_clip_query, .gfx_alpha_store, .gfx_alpha_cls, .gfx_alpha, .gfx_image_load_alpha, .gfx_rotate, .gfx_window_pixels, .gfx_tcl_running, .gfx_window_smooth, .gfx_window_keep_open, .gfx_window_close, .gfx_window_closes };

/// The GFX- words in the order REQUIRE-GRAPHICS appends them, right after the GRAPHICS
/// vocabulary. The order is part of the dictionary that images keep: add new words at
/// the end.
pub const definitions = [_]struct { []const u8, Builtin }{
    .{ "GFX-INIT", .gfx_init },                      .{ "GFX-WIDTH", .gfx_width },                    .{ "GFX-HEIGHT", .gfx_height },
    .{ "GFX-PSET", .gfx_pset },                      .{ "GFX-PGET", .gfx_pget },                      .{ "GFX-HLINE", .gfx_hline },
    .{ "GFX-CLS", .gfx_cls },                        .{ "GFX-SAVE-PPM", .gfx_save_ppm },              .{ "GFX-SAVE-BMP", .gfx_save_bmp },
    .{ "GFX-SHOW-BLOCKS", .gfx_show_blocks },        .{ "GFX-SHOW-SIXEL", .gfx_show_sixel },          .{ "GFX-SHOW-WINDOW", .gfx_show_window },
    .{ "GFX-WINDOW?", .gfx_window_query },           .{ "GFX-SAVE-PNG", .gfx_save_png },              .{ "GFX-INKEY", .gfx_inkey },
    .{ "GFX-MOUSE", .gfx_mouse },                    .{ "GFX-MOUSE-MODE", .gfx_mouse_mode },          .{ "GFX-GLYPH-LOAD", .gfx_glyph_load },
    .{ "GFX-GLYPH-BOX", .gfx_glyph_box },            .{ "GFX-GLYPH-ALPHA", .gfx_glyph_alpha },        .{ "GFX-FONT-HEIGHT", .gfx_font_height },
    .{ "GFX-FONT-BUILTIN", .gfx_font_builtin },      .{ "GFX-FONT-LOAD", .gfx_font_load },            .{ "GFX-FONT-SYSTEM", .gfx_font_system },
    .{ "GFX-COLOR-MODE", .gfx_color_mode },          .{ "GFX-TCL", .gfx_tcl },                        .{ "GFX-TCL-ERROR", .gfx_tcl_error },
    .{ "GFX-TCL-EVENT", .gfx_tcl_event },            .{ "GFX-TCL-PROGRAM", .gfx_tcl_program },        .{ "GFX-TCL-STOP", .gfx_tcl_stop },
    .{ "GFX-SHOW-TK", .gfx_show_tk },                .{ "GFX-KEY-HELD", .gfx_key_held },              .{ "GFX-WINDOW-SIZE", .gfx_window_size },
    .{ "GFX-GAMEPAD-POLL", .gfx_gamepad_poll },      .{ "GFX-GAMEPAD-QUERY", .gfx_gamepad_query },    .{ "GFX-GAMEPAD-NAME", .gfx_gamepad_name },
    .{ "GFX-GAMEPAD-MAP", .gfx_gamepad_map },        .{ "GFX-GAMEPAD-GUID", .gfx_gamepad_guid },      .{ "GFX-IMAGE-NEW", .gfx_image_new },
    .{ "GFX-IMAGE-FREE", .gfx_image_free },          .{ "GFX-IMAGE-SIZE", .gfx_image_size },          .{ "GFX-TARGET", .gfx_target },
    .{ "GFX-TARGET@", .gfx_target_query },           .{ "GFX-COPY", .gfx_copy },                      .{ "GFX-IMAGE-LOAD", .gfx_image_load },
    .{ "GFX-MOUSE-EVENT", .gfx_mouse_event },        .{ "GFX-PIXEL", .gfx_pixel },                    .{ "GFX-TILEMAP", .gfx_tilemap },
    .{ "GFX-INDEXED", .gfx_indexed },                .{ "GFX-ROW-SHIFT", .gfx_row_shift },            .{ "GFX-ROW-COLOR", .gfx_row_color },
    .{ "GFX-AUTO-DISPLAY", .gfx_auto_display },      .{ "GFX-AUTO-DISPLAY!", .gfx_auto_display_set }, .{ "GFX-IME-PREEDIT", .gfx_ime_preedit },
    .{ "GFX-IME-CARET", .gfx_ime_caret },            .{ "GFX-AUTO-TRY", .gfx_auto_try },              .{ "GFX-FULLSCREEN", .gfx_fullscreen },
    .{ "GFX-FULLSCREEN?", .gfx_fullscreen_query },   .{ "GFX-MOUSE-CURSOR", .gfx_mouse_cursor },      .{ "GFX-SCAN-INPUT?", .gfx_scan_input },
    .{ "GFX-SCAN-SUPPORTED?", .gfx_scan_supported }, .{ "GFX-SCAN-HELD?", .gfx_scan_held },           .{ "GFX-KEY-EVENT", .gfx_key_event },
    .{ "GFX-KEY-RESYNC", .gfx_key_resync },          .{ "GFX-RGB", .gfx_rgb },                        .{ "GFX-DISPLAYS", .gfx_displays },
    .{ "GFX-DISPLAY-INFO", .gfx_display_info },      .{ "GFX-WINDOW-DISPLAY", .gfx_window_display },  .{ "GFX-WINDOW-STATE", .gfx_window_state },
    .{ "GFX-WINDOW-FLAGS", .gfx_window_flags },      .{ "GFX-WINDOW-FIT", .gfx_window_fit },          .{ "GFX-WINDOW-VIEW", .gfx_window_view },
    .{ "GFX-WINDOW-FRAMES", .gfx_window_frames },    .{ "GFX-FRAME-WAIT", .gfx_frame_wait },          .{ "GFX-VSYNC-WAIT", .gfx_vsync_wait },
    .{ "GFX-CLIP", .gfx_clip },                      .{ "GFX-CLIP@", .gfx_clip_query },               .{ "GFX-ALPHA-PSET", .gfx_alpha_store },
    .{ "GFX-ALPHA-CLS", .gfx_alpha_cls },            .{ "GFX-IMAGE-ALPHA@", .gfx_alpha },                    .{ "GFX-IMAGE-LOAD-ALPHA", .gfx_image_load_alpha },
    .{ "GFX-ROTATE", .gfx_rotate },                  .{ "GFX-WINDOW-PIXELS", .gfx_window_pixels },    .{ "GFX-TCL?", .gfx_tcl_running },
    .{ "GFX-WINDOW-SMOOTH", .gfx_window_smooth },
    .{ "GFX-WINDOW-KEEP-OPEN", .gfx_window_keep_open }, .{ "GFX-WINDOW-CLOSE", .gfx_window_close },          .{ "GFX-WINDOW-CLOSES", .gfx_window_closes },
};

/// The words of the graphics library that HELP describes; the help test checks that the
/// library defines each of them.
pub const library_words = [_][]const u8{ "RGB", "COLOR", "COLOR!", "COLOR@", "PSET", "CLS", "LINE", "RECT", "FILL-RECT", "CIRCLE", "FILL-CIRCLE", "PAINT", "SAVE-PPM", "SAVE-BMP", "SAVE-PNG", "SHOW", "DISPLAY-TERMINAL", "DISPLAY-WINDOW", "DISPLAY-AUTO", "FULLSCREEN", "FULLSCREEN?", "MOUSE-CURSOR", "TERMINAL-BLOCKS", "TERMINAL-SIXEL", "DISPLAY-COLORS", "DITHER", "TCL", "TCL-EVAL", "TCL-ERROR$", "TCL-EVENT", "TCL-PROGRAM", "TCL-STOP", "DISPLAY-TK", "INKEY", "KEY-HELD?", "MOUSE", "WINDOW-SIZE", "MOUSE-ON", "MOUSE-OFF", "FRAME", "TEXT", "TEXT-SCALE", "TEXT-WIDTH", "TEXT-HEIGHT", "BUILTIN-FONT", "LOAD-FONT", "SYSTEM-FONT", "K-UP", "K-DOWN", "K-LEFT", "K-RIGHT", "K-HOME", "K-END", "K-PRIOR", "K-NEXT", "K-INSERT", "K-DELETE", "K-F1", "K-F2", "K-F3", "K-F4", "K-F5", "K-F6", "K-F7", "K-F8", "K-F9", "K-F10", "K-F11", "K-F12", "GAMEPAD-POLL", "GAMEPAD?", "GAMEPAD-ID", "GAMEPAD-BUTTONS", "GAMEPAD-MAPPED?", "GAMEPAD-AXES", "GAMEPAD-BUTTON-COUNT", "GAMEPAD-HATS", "GAMEPAD-AXIS", "GAMEPAD-HAT", "GAMEPAD-BUTTON?", "GAMEPAD-NAME", "GAMEPAD-MAP", "GAMEPAD-GUID", "SCREEN", "NEW-IMAGE", "FREE-IMAGE", "IMAGE-SIZE", "DRAW-TO", "DRAWING", "TRANSPARENT", "IMAGE-FLIP", "COPY-RECT", "PUT-IMAGE", "LOAD-IMAGE", "IMAGE-MODE", "IMAGE-ALPHA", "IMAGE-SCALE", "MOUSE-EVENT" } ++ [_][]const u8{ "SCAN-INPUT?", "SCAN-SUPPORTED?", "SCAN-HELD?", "KEY-EVENT", "KEY-RESYNC", "SC-A", "SC-B", "SC-C", "SC-D", "SC-E", "SC-F", "SC-G", "SC-H", "SC-I", "SC-J", "SC-K", "SC-L", "SC-M", "SC-N", "SC-O", "SC-P", "SC-Q", "SC-R", "SC-S", "SC-T", "SC-U", "SC-V", "SC-W", "SC-X", "SC-Y", "SC-Z", "SC-1", "SC-2", "SC-3", "SC-4", "SC-5", "SC-6", "SC-7", "SC-8", "SC-9", "SC-0", "SC-RETURN", "SC-ESCAPE", "SC-BACKSPACE", "SC-TAB", "SC-SPACE", "SC-MINUS", "SC-EQUALS", "SC-LEFTBRACKET", "SC-RIGHTBRACKET", "SC-BACKSLASH", "SC-NONUSHASH", "SC-SEMICOLON", "SC-APOSTROPHE", "SC-GRAVE", "SC-COMMA", "SC-PERIOD", "SC-SLASH", "SC-CAPSLOCK", "SC-F1", "SC-F2", "SC-F3", "SC-F4", "SC-F5", "SC-F6", "SC-F7", "SC-F8", "SC-F9", "SC-F10", "SC-F11", "SC-F12", "SC-PRINTSCREEN", "SC-SCROLLLOCK", "SC-PAUSE", "SC-INSERT", "SC-HOME", "SC-PAGEUP", "SC-DELETE", "SC-END", "SC-PAGEDOWN", "SC-RIGHT", "SC-LEFT", "SC-DOWN", "SC-UP", "SC-NUMLOCKCLEAR", "SC-KP-DIVIDE", "SC-KP-MULTIPLY", "SC-KP-MINUS", "SC-KP-PLUS", "SC-KP-ENTER", "SC-KP-1", "SC-KP-2", "SC-KP-3", "SC-KP-4", "SC-KP-5", "SC-KP-6", "SC-KP-7", "SC-KP-8", "SC-KP-9", "SC-KP-0", "SC-KP-PERIOD", "SC-NONUSBACKSLASH", "SC-APPLICATION", "SC-POWER", "SC-KP-EQUALS", "SC-F13", "SC-F14", "SC-F15", "SC-F16", "SC-F17", "SC-F18", "SC-F19", "SC-F20", "SC-F21", "SC-F22", "SC-F23", "SC-F24", "SC-EXECUTE", "SC-HELP", "SC-MENU", "SC-SELECT", "SC-STOP", "SC-AGAIN", "SC-UNDO", "SC-CUT", "SC-COPY", "SC-PASTE", "SC-FIND", "SC-MUTE", "SC-VOLUMEUP", "SC-VOLUMEDOWN", "SC-LOCKINGCAPSLOCK", "SC-LOCKINGNUMLOCK", "SC-LOCKINGSCROLLLOCK", "SC-KP-COMMA", "SC-KP-EQUALSAS400", "SC-INTERNATIONAL1", "SC-INTERNATIONAL2", "SC-INTERNATIONAL3", "SC-INTERNATIONAL4", "SC-INTERNATIONAL5", "SC-INTERNATIONAL6", "SC-INTERNATIONAL7", "SC-INTERNATIONAL8", "SC-INTERNATIONAL9", "SC-LANG1", "SC-LANG2", "SC-LANG3", "SC-LANG4", "SC-LANG5", "SC-LANG6", "SC-LANG7", "SC-LANG8", "SC-LANG9", "SC-ALTERASE", "SC-SYSREQ", "SC-CANCEL", "SC-CLEAR", "SC-PRIOR", "SC-RETURN2", "SC-SEPARATOR", "SC-OUT", "SC-OPER", "SC-CLEARAGAIN", "SC-CRSEL", "SC-EXSEL", "SC-KP-00", "SC-KP-000", "SC-THOUSANDSSEPARATOR", "SC-DECIMALSEPARATOR", "SC-CURRENCYUNIT", "SC-CURRENCYSUBUNIT", "SC-KP-LEFTPAREN", "SC-KP-RIGHTPAREN", "SC-KP-LEFTBRACE", "SC-KP-RIGHTBRACE", "SC-KP-TAB", "SC-KP-BACKSPACE", "SC-KP-A", "SC-KP-B", "SC-KP-C", "SC-KP-D", "SC-KP-E", "SC-KP-F", "SC-KP-XOR", "SC-KP-POWER", "SC-KP-PERCENT", "SC-KP-LESS", "SC-KP-GREATER", "SC-KP-AMPERSAND", "SC-KP-DBLAMPERSAND", "SC-KP-VERTICALBAR", "SC-KP-DBLVERTICALBAR", "SC-KP-COLON", "SC-KP-HASH", "SC-KP-SPACE", "SC-KP-AT", "SC-KP-EXCLAM", "SC-KP-MEMSTORE", "SC-KP-MEMRECALL", "SC-KP-MEMCLEAR", "SC-KP-MEMADD", "SC-KP-MEMSUBTRACT", "SC-KP-MEMMULTIPLY", "SC-KP-MEMDIVIDE", "SC-KP-PLUSMINUS", "SC-KP-CLEAR", "SC-KP-CLEARENTRY", "SC-KP-BINARY", "SC-KP-OCTAL", "SC-KP-DECIMAL", "SC-KP-HEXADECIMAL", "SC-LCTRL", "SC-LSHIFT", "SC-LALT", "SC-LGUI", "SC-RCTRL", "SC-RSHIFT", "SC-RALT", "SC-RGUI", "SC-PRESS", "SC-RELEASE", "SC-RESYNC" } ++ [_][]const u8{ "DISPLAYS", "DISPLAY-RECT", "DISPLAY-WORK", "DISPLAY-SCALE", "DISPLAY-HZ", "DISPLAY-PRIMARY", "WINDOW-DISPLAY", "WINDOW-PIXELS", "WINDOW-CHANGES", "WINDOW-OPEN?", "WINDOW-FOCUSED?", "WINDOW-MINIMIZED?", "WINDOW-CLOSES", "WINDOW-FIT", "WINDOW-IMAGE-RECT", "WINDOW-FRAMES", "WINDOW-PAINT-WAIT", "VSYNC-WAIT", "CLIP!", "CLIP@", "NO-CLIP", "IMAGE-KEEP-ALPHA", "IMAGE-SMOOTH", "WINDOW-SMOOTH", "WINDOW-KEEP-OPEN", "WINDOW-CLOSE", "FIT-ASPECT", "FIT-INTEGER", "FIT-STRETCH", "MODE-COPY", "MODE-XOR", "MODE-ADD", "MODE-BLEND", "MODE-SOURCE-OVER", "MODE-SOURCE-OVER-FADE", "COPY-ROTATED-RECT", "PUT-ROTATED" };

/// The words of the part of the library that uses floating-point numbers, which a build
/// without them leaves out.
pub const float_library_words = [_][]const u8{ "X-RANGE", "Y-RANGE", "MPSET", "MLINE", "AXES", "PLOT" };

/// The graphics library, which REQUIRE-GRAPHICS interprets after appending the GFX- words:
/// graphics.fs, followed by graphics_float.fs in a build with the floating-point words.
pub const library = @embedFile("../graphics/graphics.fs") ++
    (if (defs.float_enabled) @embedFile("../graphics/graphics_float.fs") else "");

/// The name the library has in the source file table, for LOCATE and error messages.
pub const library_name = "*graphics library*";

/// Limits of an image: each side 1 to 16384 pixels and at most 1 GiB in all.
pub const max_side = 16384;
pub const max_bytes = 1024 * 1024 * 1024;

/// Every pixel is opaque: the alpha byte above the red, green, and blue bytes is 255.
const opaque_alpha: u32 = 0xff00_0000;
const rgb_mask: u32 = 0x00ff_ffff;

pub fn execute(self: *State, builtin: Builtin) RuntimeError!void {
    switch (builtin) {
        .gfx_scan_input => {
            const ops = self.writer.physical_key_ops;
            try self.push(if (ops != null and ops.?.available(self.writer.context)) -1 else 0);
        },
        .gfx_scan_supported, .gfx_scan_held => {
            const value = try self.pop();
            if (value < 0 or value > 255) return error.InvalidNumber;
            const ops = self.writer.physical_key_ops;
            const flag = if (ops) |o| if (builtin == .gfx_scan_supported) o.supported(self.writer.context, @intCast(value)) else o.held(self.writer.context, @intCast(value)) else false;
            try self.push(if (flag) -1 else 0);
        },
        .gfx_key_event => {
            // Reserve before consuming a host event, including the three-cell case.
            if (self.data_stack.len - self.data_depth < 3) return error.StackOverflow;
            const event = if (self.writer.physical_key_ops) |ops| ops.next(self.writer.context) else null;
            if (event) |e| {
                try self.push(e.scan);
                try self.push(@backingInt(e.kind));
                try self.push(-1);
            } else try self.push(0);
        },
        .gfx_key_resync => {
            const address = try self.pop();
            const index = try self.memoryAddress(address, 32);
            var bitmap: @import("physical_keys.zig").Bitmap = @splat(0);
            if (self.writer.physical_key_ops) |ops| ops.resync(self.writer.context, &bitmap);
            @memcpy(self.memory[index..][0..32], &bitmap);
            @import("address_registry.zig").written(self, address, 32, false);
        },

        .gfx_gamepad_poll, .gfx_gamepad_query, .gfx_gamepad_name, .gfx_gamepad_map, .gfx_gamepad_guid => try @import("gamepad.zig").execute(self, builtin),
        .gfx_image_new, .gfx_image_free, .gfx_image_size, .gfx_target, .gfx_target_query, .gfx_copy, .gfx_image_load, .gfx_pixel, .gfx_tilemap, .gfx_indexed, .gfx_row_shift, .gfx_row_color, .gfx_rgb, .gfx_image_load_alpha => try graphics_images.execute(self, builtin),
        .gfx_init => {
            const height = try self.pop();
            const width = try self.pop();
            const pixels = try imagePixels(width, height);
            const framebuffer_fn = self.writer.framebuffer_fn orelse return error.HostUnavailable;
            // The host keeps the old image when it cannot give a new one.
            const buffer = framebuffer_fn(self.writer.context, pixels) orelse return error.MemoryExhausted;
            if (buffer.len != pixels) {
                // The host has let the old image go, so it cannot stay in use.
                clearImage(self);
                return error.HostFailed;
            }
            @memset(buffer, opaque_alpha);
            self.gfx_pixels = buffer;
            self.gfx_width = width;
            self.gfx_height = height;
            // A new image: all of it may be drawn in.
            self.gfx_clip = null;
        },
        // These draw on, and measure, the image drawn on: the screen or an image of the pool.
        .gfx_width => try self.push(@intCast((try graphics_images.imageSize(self, self.gfx_target))[0])),
        .gfx_height => try self.push(@intCast((try graphics_images.imageSize(self, self.gfx_target))[1])),
        .gfx_pset => {
            const rgb = try self.pop();
            const y = try self.pop();
            const x = try self.pop();
            const canvas = try graphics_images.target(self);
            if (canvas.drawIndex(x, y)) |index| canvas.pixels[index] = color(rgb);
        },
        .gfx_pget => {
            const y = try self.pop();
            const x = try self.pop();
            const canvas = try graphics_images.target(self);
            const index = canvas.index(x, y) orelse return self.push(-1);
            try self.push(canvas.pixels[index] & rgb_mask);
        },
        .gfx_hline => {
            const rgb = try self.pop();
            const y = try self.pop();
            const x2 = try self.pop();
            const x1 = try self.pop();
            const canvas = try graphics_images.target(self);
            const width: Cell = @intCast(canvas.width);
            // The part that may be drawn in (CLIP!), which is inside the image.
            const part = canvas.bounds();
            if (part.x0 >= part.x1 or y < part.y0 or y >= part.y1) return;
            const left = @max(@min(x1, x2), @as(Cell, @intCast(part.x0)));
            const right = @min(@max(x1, x2), @as(Cell, @intCast(part.x1)) - 1);
            if (left > right) return;
            const row: usize = @intCast(y * width);
            @memset(canvas.pixels[row + @as(usize, @intCast(left)) .. row + @as(usize, @intCast(right)) + 1], color(rgb));
        },
        .gfx_cls => {
            const rgb = try self.pop();
            const canvas = try graphics_images.target(self);
            // With CLIP!, only the part that may be drawn in.
            const part = canvas.bounds();
            if (part.x0 >= part.x1) return;
            for (part.y0..part.y1) |row| @memset(canvas.pixels[row * canvas.width + part.x0 .. row * canvas.width + part.x1], color(rgb));
        },
        .gfx_clip => {
            // ( x y w h -- ): the drawing words draw only in the part of this rectangle
            // inside the image drawn on, from now on, for that image.
            const h = try self.pop();
            const w = try self.pop();
            const y = try self.pop();
            const x = try self.pop();
            try graphics_images.setClip(self, x, y, w, h);
        },
        .gfx_alpha_store => {
            const a = try self.pop();
            const y = try self.pop();
            const x = try self.pop();
            try graphics_images.setAlpha(self, x, y, a);
        },
        .gfx_alpha_cls => try graphics_images.fillAlpha(self, try self.pop()),
        .gfx_alpha => {
            // ( img x y -- a | -1 ): the alpha of a pixel of any image, 255 for one that
            // is opaque (every pixel of the screen), -1 outside the image.
            const y = try self.pop();
            const x = try self.pop();
            const canvas = try graphics_images.canvasOf(self, try self.pop());
            const index = canvas.index(x, y) orelse return self.push(-1);
            try self.push(canvas.pixels[index] >> 24);
        },
        // ( -- flag ): whether the Tcl program (TCL, DISPLAY-TK) is running now; asking
        // does not start it.
        .gfx_tcl_running => try self.push(if (defs.graphics_enabled and self.tcl.running) -1 else 0),
        .gfx_window_pixels => {
            // ( id -- w h ): the size of the client area of the window with the window
            // system's identifier id, in physical pixels on Windows or X server pixels on
            // Linux (a compositor may scale them); 0 0 when there is none, for an
            // id of 0 or less, and on a host that cannot tell.
            const id = try self.pop();
            var size: [2]u32 = .{ 0, 0 };
            if (id > 0) if (self.writer.window_size_fn) |size_fn| {
                if (size_fn(self.writer.context, @intCast(id))) |told| size = told;
            };
            try self.push(size[0]);
            try self.push(size[1]);
        },
        .gfx_rotate => {
            // ( src sx sy w h cx cy angle100 xscale1000 yscale1000 key mode alpha smooth -- )
            var args: [14]Cell = undefined;
            var at: usize = args.len;
            while (at > 0) {
                at -= 1;
                args[at] = try self.pop();
            }
            try @import("graphics_rotate.zig").draw(self, .{
                .source = args[0],
                .sx = args[1],
                .sy = args[2],
                .w = args[3],
                .h = args[4],
                .cx = args[5],
                .cy = args[6],
                .angle = args[7],
                .xscale = args[8],
                .yscale = args[9],
                .key = args[10],
                .mode = args[11],
                .alpha = args[12],
                .smooth = args[13] != 0,
            });
        },
        .gfx_clip_query => {
            // ( -- x y w h ): the part of the image drawn on that may be drawn in.
            const canvas = try graphics_images.target(self);
            const part = canvas.bounds();
            try self.push(@intCast(part.x0));
            try self.push(@intCast(part.y0));
            try self.push(@intCast(part.x1 - part.x0));
            try self.push(@intCast(part.y1 - part.y0));
        },
        .gfx_save_ppm, .gfx_save_bmp, .gfx_save_png => {
            const name = try self.memoryRange();
            const canvas = try graphics_images.target(self);
            const format: ImageFormat = switch (builtin) {
                .gfx_save_ppm => .ppm,
                .gfx_save_bmp => .bmp,
                else => .png,
            };
            try self.push(try saveImage(self, canvas, name, format));
        },
        .gfx_show_blocks => {
            try requireImage(self);
            graphics_terminal.showBlocks(self);
        },
        .gfx_show_sixel => {
            try requireImage(self);
            graphics_terminal.showSixel(self);
        },
        .gfx_show_window => {
            try requireImage(self);
            const window_fn = self.writer.window_fn orelse return error.HostUnavailable;
            // The next SHOW on the terminal starts a new picture there.
            self.gfx_input.shown = null;
            try window_fn(self.writer.context, self.gfx_pixels, @intCast(self.gfx_width), @intCast(self.gfx_height), self.gfx_color_mode, self.gfx_window_size);
        },
        .gfx_window_query => try self.push(if (self.writer.window_fn != null) -1 else 0),
        .gfx_color_mode => {
            const dither = try self.pop() != 0;
            const colors = try self.pop();
            if (!graphics_palette.validColors(colors)) return error.InvalidNumber;
            self.gfx_color_mode = .{ .colors = @intCast(colors), .dither = dither };
        },
        .gfx_inkey => try self.push(try graphics_input.inkey(self)),
        .gfx_window_size => {
            const height = try self.pop();
            const width = try self.pop();
            // 0 0, or each side as GFX-INIT allows.
            const default = width == 0 and height == 0;
            if (!default and (width < 1 or width > max_side or height < 1 or height > max_side)) return error.InvalidNumber;
            self.gfx_window_size = .{ @intCast(width), @intCast(height) };
        },
        .gfx_auto_try => {
            const desktop = try self.pop() != 0;
            try requireImage(self);
            try self.push(try autoTry(self, desktop));
        },
        .gfx_auto_display => try self.push(self.gfx_auto_display),
        .gfx_auto_display_set => {
            const display = try self.pop();
            if (display < 0 or display > 3) return error.InvalidNumber;
            self.gfx_auto_display = @intCast(display);
        },
        .gfx_ime_preedit => {
            const destination = try self.memoryRange();
            const length = if (self.writer.ime_preedit_fn) |preedit_fn|
                try preedit_fn(self.writer.context, destination)
            else
                0;
            try self.push(@intCast(@min(length, destination.len)));
        },
        .gfx_fullscreen => {
            const wanted = try self.pop() != 0;
            self.gfx_fullscreen = wanted;
            if (self.writer.window_fullscreen_fn) |fullscreen_fn| self.gfx_fullscreen = try fullscreen_fn(self.writer.context, @intFromBool(wanted));
        },
        .gfx_fullscreen_query => {
            // The host's window may have left fullscreen by its key.
            if (self.writer.window_fullscreen_fn) |fullscreen_fn| self.gfx_fullscreen = try fullscreen_fn(self.writer.context, -1);
            try self.push(if (self.gfx_fullscreen) -1 else 0);
        },
        .gfx_displays => {
            // ( flag -- n ): with a true flag, takes the displays again first.
            if (try self.pop() != 0) {
                self.gfx_displays = .{};
                if (self.writer.displays_fn) |displays_fn| displays_fn(self.writer.context, &self.gfx_displays);
            }
            try self.push(@intCast(self.gfx_displays.count));
        },
        .gfx_display_info => {
            // ( i field -- n ): one field of display i as DISPLAYS took it last; a field
            // of -1 gives the number of the primary display (i is not used then).
            const number = try self.pop();
            const index = try self.pop();
            if (number == -1) return self.push(self.gfx_displays.primary());
            if (number < 0 or number >= display_info.field_count) return error.InvalidNumber;
            if (index < 0 or index >= self.gfx_displays.count) return error.InvalidNumber;
            try self.push(display_info.field(self.gfx_displays.items[@intCast(index)], @intCast(number)));
        },
        .gfx_window_display => {
            // ( id -- i ): the display of a window among those DISPLAYS took last, or -1
            // (no such window, or a display that was not there then). An id of 0 is the
            // host's own window; another is the window system's identifier of a window.
            const window = try self.pop();
            const window_fn = self.writer.window_display_fn orelse return self.push(-1);
            if (window < 0) return self.push(-1);
            const id = window_fn(self.writer.context, @intCast(window)) orelse return self.push(-1);
            try self.push(self.gfx_displays.find(id));
        },
        .gfx_window_state => {
            // ( -- w h n ): of the host's own window at one moment, the width and height
            // of the part it can draw in (0 0 without a window) and the count of its
            // changes. All are 0 on a host that cannot tell. The three are of one answer
            // of the host, so a width is never paired with the height of another moment.
            const state: display_info.WindowState = if (self.writer.window_state_fn) |state_fn| state_fn(self.writer.context) else .{};
            try self.push(state.width);
            try self.push(state.height);
            try self.push(@intCast(state.changes & std.math.maxInt(Cell)));
        },
        .gfx_window_flags => {
            // ( -- open focus minimized closes ): of the host's own window at one
            // moment, three flags and the count of the times the user closed it. All
            // are 0 on a host that cannot tell.
            const state: display_info.WindowState = if (self.writer.window_state_fn) |state_fn| state_fn(self.writer.context) else .{};
            try self.push(if (state.open) -1 else 0);
            try self.push(if (state.focused) -1 else 0);
            try self.push(if (state.minimized) -1 else 0);
            try self.push(@intCast(state.closes & std.math.maxInt(Cell)));
        },
        .gfx_window_fit => {
            // ( n -- ): 0 the image's proportions, 1 whole-number factors, 2 the whole
            // drawable part. The wish is kept also where the host has no such window.
            const fit = try self.pop();
            if (fit < 0 or fit > 2) return error.InvalidNumber;
            self.gfx_window_fit = @intCast(fit);
            if (self.writer.window_fit_fn) |fit_fn| fit_fn(self.writer.context, self.gfx_window_fit);
        },
        .gfx_window_keep_open => {
            // ( flag -- ): the wish is kept also where the host has no such window.
            self.gfx_window_keep_open = try self.pop() != 0;
            if (self.writer.window_close_fn) |close_fn| _ = close_fn(self.writer.context, @intFromBool(self.gfx_window_keep_open));
        },
        // ( -- ): the program closes the host's own window; nothing without one.
        .gfx_window_close => if (self.writer.window_close_fn) |close_fn| {
            _ = close_fn(self.writer.context, 2);
        },
        .gfx_window_closes => {
            // ( -- n ): the times the user closed, or asked to close, the host's own
            // window; the host takes the count as read in the same step. A host that
            // only tells its window's state gives the count of that; 0 without either.
            var closes: u64 = 0;
            if (self.writer.window_close_fn) |close_fn| {
                closes = close_fn(self.writer.context, 3);
            } else if (self.writer.window_state_fn) |state_fn| {
                closes = state_fn(self.writer.context).closes;
            }
            try self.push(@intCast(closes & std.math.maxInt(Cell)));
        },
        .gfx_window_smooth => {
            // ( flag -- ): the wish is kept also where the host has no such window.
            self.gfx_window_smooth = try self.pop() != 0;
            if (self.writer.window_smooth_fn) |smooth_fn| smooth_fn(self.writer.context, self.gfx_window_smooth);
        },
        .gfx_window_view => {
            // ( -- x y w h ): where the image is shown in the drawable part of the host's
            // own window now; four zeros without such a window.
            const state: display_info.WindowState = if (self.writer.window_state_fn) |state_fn| state_fn(self.writer.context) else .{};
            for (state.view) |value| try self.push(value);
        },
        .gfx_window_frames => {
            // ( -- shown painted-through ): the images SHOW gave the host's own window in this
            // run, and how many of them it had been given when it last drew; of one
            // answer of the host. Both 0 on a host that cannot tell.
            const state: display_info.WindowState = if (self.writer.window_state_fn) |state_fn| state_fn(self.writer.context) else .{};
            try self.push(@intCast(state.frames_shown & std.math.maxInt(Cell)));
            try self.push(@intCast(state.frames_painted & std.math.maxInt(Cell)));
        },
        .gfx_frame_wait => {
            // ( ms -- flag ): waits at most ms (0 to 60000) until the window has drawn
            // the image the last SHOW gave it. False at once on a host that cannot tell.
            const ms = try self.pop();
            if (ms < 0 or ms > 60000) return error.InvalidNumber;
            const wait_fn = self.writer.window_wait_fn orelse return self.push(0);
            try self.push(if (wait_fn(self.writer.context, 0, @intCast(ms))) -1 else 0);
        },
        .gfx_vsync_wait => {
            // ( -- flag ): waits for the display's next refresh; false when the host
            // cannot.
            const wait_fn = self.writer.window_wait_fn orelse return self.push(0);
            try self.push(if (wait_fn(self.writer.context, 1, 0)) -1 else 0);
        },
        .gfx_mouse_cursor => {
            const visible = try self.pop() != 0;
            self.gfx_cursor_visible = visible;
            if (self.writer.window_cursor_fn) |cursor_fn| try cursor_fn(self.writer.context, visible);
        },
        .gfx_ime_caret => {
            const height = try self.pop();
            const y = try self.pop();
            const x = try self.pop();
            const active = try self.pop() != 0;
            if (self.writer.ime_caret_fn) |caret_fn| try caret_fn(self.writer.context, active, x, y, height);
        },
        .gfx_key_held => {
            const key = try self.pop();
            try self.push(if (try graphics_input.keyHeld(self, key)) -1 else 0);
        },
        .gfx_mouse => {
            const state = try graphics_input.mouseState(self);
            for (state) |value| try self.push(value);
        },
        .gfx_mouse_mode => try graphics_input.setMouse(self, try self.pop() != 0),
        .gfx_mouse_event => if (try graphics_input.nextMouseEvent(self)) |event| {
            for ([_]Cell{ event.x, event.y, event.button, @backingInt(event.kind), -1 }) |value| try self.push(value);
        } else try self.push(0),
        else => {
            // The fonts are left out of a build without graphics.
            if (!defs.graphics_enabled) return error.GraphicsUnavailable;
            try executeFont(self, builtin);
        },
    }
}

// Only startup availability failures select another backend. Tcl script failures,
// allocation failures and interrupts must still reach the application's CATCH.
fn autoTry(self: *State, desktop: bool) RuntimeError!Cell {
    const budget = self.writer.display_budget_fn;
    if (budget) |scope| scope(self.writer.context, true);
    defer if (budget) |scope| scope(self.writer.context, false);
    if (self.writer.window_fn) |show| {
        self.gfx_input.shown = null;
        if (show(self.writer.context, self.gfx_pixels, @intCast(self.gfx_width), @intCast(self.gfx_height), self.gfx_color_mode, self.gfx_window_size)) |_| {
            return 2;
        } else |err| switch (err) {
            error.HostUnavailable, error.HostFailed => {},
            else => return err,
        }
    }
    if (desktop) {
        self.gfx_input.shown = null;
        if (tcl.showImage(self)) |_| {
            return 3;
        } else |err| switch (err) {
            error.HostUnavailable, error.HostFailed => {},
            else => return err,
        }
    }
    return 1;
}

fn executeFont(self: *State, builtin: Builtin) RuntimeError!void {
    switch (builtin) {
        .gfx_glyph_load => {
            const code = try self.pop();
            try self.push(graphics_font.loadGlyph(self, code));
        },
        .gfx_glyph_box => {
            const font = &self.gfx_font;
            try self.push(font.left);
            try self.push(font.width);
            try self.push(font.height);
        },
        .gfx_glyph_alpha => {
            const y = try self.pop();
            const x = try self.pop();
            try self.push(graphics_font.alphaAt(self, x, y));
        },
        .gfx_font_height => try self.push(graphics_font.fontHeight(self)),
        .gfx_font_builtin => graphics_font.selectBuiltin(self),
        .gfx_font_load => {
            const name = try self.memoryRange();
            try self.push(try graphics_font.loadBdf(self, name));
        },
        .gfx_font_system => {
            const height = try self.pop();
            const name = try self.memoryRange();
            try self.push(try graphics_font.selectSystem(self, name, height));
        },
        .gfx_tcl => {
            const source = try self.memoryRange();
            for (try tcl.eval(self, source)) |value| try self.push(value);
        },
        .gfx_tcl_error => for (tcl.errorText(self)) |value| try self.push(value),
        .gfx_tcl_event => {
            if (try tcl.nextEvent(self)) |text| {
                for (text) |value| try self.push(value);
                try self.push(-1);
            } else try self.push(0);
        },
        .gfx_tcl_program => try tcl.setProgram(self, try self.memoryRange()),
        .gfx_tcl_stop => try tcl.stop(self),
        .gfx_show_tk => {
            try requireImage(self);
            // The next SHOW on the terminal starts a new picture there.
            self.gfx_input.shown = null;
            try tcl.showImage(self);
        },
        else => unreachable,
    }
}

/// The pixel count of a width × height image, or NUMBER ERROR when a side is outside
/// 1 to 16384 or the image is over 1 GiB.
pub fn imagePixels(width: Cell, height: Cell) RuntimeError!usize {
    if (width < 1 or width > max_side or height < 1 or height > max_side) return error.InvalidNumber;
    const pixels = std.math.mul(u64, @intCast(width), @intCast(height)) catch return error.InvalidNumber;
    const bytes = std.math.mul(u64, pixels, 4) catch return error.InvalidNumber;
    if (bytes > max_bytes) return error.InvalidNumber;
    return @intCast(pixels);
}

/// Forgets the image without releasing it; the host owns the buffer.
pub fn clearImage(self: *State) void {
    self.gfx_pixels = &.{};
    self.gfx_width = 0;
    self.gfx_height = 0;
    self.gfx_clip = null;
    // A font is not part of the dictionary either.
    if (defs.graphics_enabled) {
        graphics_font.selectBuiltin(self);
    }
}

fn requireImage(self: *const State) RuntimeError!void {
    if (self.gfx_pixels.len == 0) return error.NoCanvas;
}

/// A pixel from a color cell: its low 24 bits are 0xRRGGBB, the rest is ignored.
fn color(rgb: Cell) u32 {
    return opaque_alpha | (@as(u32, @truncate(@as(u64, @bitCast(rgb)))) & rgb_mask);
}

const ImageFormat = enum { ppm, bmp, png };

/// Writes the image to a new file and returns the ior: 0, or the first failure of
/// opening, writing, or closing the file.
fn saveImage(self: *State, canvas: Canvas, name: []const u8, format: ImageFormat) RuntimeError!Cell {
    const files = try self.fileOps();
    const opened = files.open(self.writer.context, name, .write_only, true);
    if (opened.ior != 0) return opened.ior;
    const fileid: Cell = @bitCast(opened.value);
    var output = FileOutput{ .self = self, .fileid = fileid };
    switch (format) {
        .ppm => writePpm(canvas, &output),
        .bmp => writeBmp(canvas, &output),
        .png => writePng(canvas, output.sink(), null),
    }
    output.flush();
    const closed = files.close(self.writer.context, fileid);
    return if (output.ior != 0) output.ior else closed;
}

/// Bytes to a file through the host in pieces of a few kilobytes, keeping the first ior.
const FileOutput = struct {
    self: *State,
    fileid: Cell,
    buffer: [4096]u8 = undefined,
    used: usize = 0,
    ior: Cell = 0,

    fn bytes(output: *FileOutput, data: []const u8) void {
        var rest = data;
        while (rest.len != 0) {
            if (output.used == output.buffer.len) output.flush();
            const count = @min(rest.len, output.buffer.len - output.used);
            @memcpy(output.buffer[output.used..][0..count], rest[0..count]);
            output.used += count;
            rest = rest[count..];
        }
    }

    fn byte(output: *FileOutput, value: u8) void {
        output.bytes(&.{value});
    }

    fn le16(output: *FileOutput, value: u16) void {
        var data: [2]u8 = undefined;
        std.mem.writeInt(u16, &data, value, .little);
        output.bytes(&data);
    }

    fn le32(output: *FileOutput, value: u32) void {
        var data: [4]u8 = undefined;
        std.mem.writeInt(u32, &data, value, .little);
        output.bytes(&data);
    }

    fn be32(output: *FileOutput, value: u32) void {
        var data: [4]u8 = undefined;
        std.mem.writeInt(u32, &data, value, .big);
        output.bytes(&data);
    }

    fn sink(output: *FileOutput) ByteSink {
        return .{ .context = output, .write = struct {
            fn write(context: *anyopaque, data: []const u8) void {
                const file_output: *FileOutput = @ptrCast(@alignCast(context));
                file_output.bytes(data);
            }
        }.write };
    }

    fn flush(output: *FileOutput) void {
        if (output.used != 0 and output.ior == 0) {
            const files = output.self.writer.file_ops.?;
            output.ior = output.self.writeFile(files, output.fileid, output.buffer[0..output.used]);
        }
        output.used = 0;
    }
};

/// Where the bytes of a PNG go: a file, or the Tcl program as base64 (DISPLAY-TK).
pub const ByteSink = struct {
    context: *anyopaque,
    write: *const fn (*anyopaque, []const u8) void,
    cancelled: ?*const fn (*anyopaque) bool = null,

    fn bytes(sink: ByteSink, data: []const u8) void {
        sink.write(sink.context, data);
    }

    fn be32(sink: ByteSink, value: u32) void {
        var data: [4]u8 = undefined;
        std.mem.writeInt(u32, &data, value, .big);
        sink.bytes(&data);
    }
};

/// A PNG chunk being written: its length, then its type and data, which the CRC-32
/// at its end covers.
const Chunk = struct {
    output: ByteSink,
    crc: std.hash.Crc32,

    fn begin(output: ByteSink, kind: *const [4]u8, length: u32) Chunk {
        output.be32(length);
        var chunk = Chunk{ .output = output, .crc = std.hash.Crc32.init() };
        chunk.bytes(kind);
        return chunk;
    }

    fn bytes(chunk: *Chunk, data: []const u8) void {
        chunk.output.bytes(data);
        chunk.crc.update(data);
    }

    fn end(chunk: *Chunk) void {
        chunk.output.be32(chunk.crc.final());
    }
};

/// The image data of a PNG: a zlib stream of stored (not compressed) deflate blocks
/// of at most 65535 bytes, ended by the Adler-32 of the data.
const StoredStream = struct {
    chunk: *Chunk,
    /// Bytes of data still to come, and still to come in the current block.
    left: u64,
    block_left: u64 = 0,
    adler_a: u32 = 1,
    adler_b: u32 = 0,

    const max_block = 65535;

    fn bytes(stream: *StoredStream, data: []const u8) void {
        var rest = data;
        while (rest.len != 0) {
            if (stream.block_left == 0) {
                const length: u16 = @intCast(@min(stream.left, max_block));
                // The last block has BFINAL set; BTYPE 00 is a stored block.
                const header = [5]u8{ @intFromBool(length == stream.left), @truncate(length), @truncate(length >> 8), @truncate(~length), @truncate(~length >> 8) };
                stream.chunk.bytes(&header);
                stream.block_left = length;
            }
            const count: usize = @intCast(@min(rest.len, stream.block_left));
            stream.chunk.bytes(rest[0..count]);
            stream.adler(rest[0..count]);
            stream.block_left -= count;
            stream.left -= count;
            rest = rest[count..];
        }
    }

    fn adler(stream: *StoredStream, data: []const u8) void {
        for (data) |value| {
            stream.adler_a = (stream.adler_a + value) % 65521;
            stream.adler_b = (stream.adler_b + stream.adler_a) % 65521;
        }
    }
};

/// The bytes of the PNG writePng writes for a width × height image.
pub fn pngLength(width: u64, height: u64) u64 {
    const raw = height * (1 + 3 * width);
    const blocks = (raw + StoredStream.max_block - 1) / StoredStream.max_block;
    // The signature, IHDR, IDAT (zlib header, blocks, Adler-32), and IEND.
    return 8 + (12 + 13) + (12 + 2 + raw + 5 * blocks + 4) + 12;
}

/// PNG with 8-bit red, green, and blue and no compression; each row starts with
/// filter type 0 (none). With a color mode, each pixel as SHOW shows it.
pub fn writePng(canvas: Canvas, output: ByteSink, mode: ?graphics_palette.ColorMode) void {
    const width = canvas.width;
    const height = canvas.height;
    output.bytes("\x89PNG\r\n\x1a\n");
    var header: [13]u8 = undefined;
    std.mem.writeInt(u32, header[0..4], @intCast(width), .big);
    std.mem.writeInt(u32, header[4..8], @intCast(height), .big);
    header[8..13].* = .{ 8, 2, 0, 0, 0 };
    var ihdr = Chunk.begin(output, "IHDR", header.len);
    ihdr.bytes(&header);
    ihdr.end();
    const row_size = 1 + 3 * width;
    const raw: u64 = @as(u64, height) * row_size;
    const blocks = (raw + StoredStream.max_block - 1) / StoredStream.max_block;
    // The zlib header, the blocks with their 5-byte headers, and the Adler-32.
    var idat = Chunk.begin(output, "IDAT", @intCast(2 + raw + 5 * blocks + 4));
    // CMF 0x78 (deflate, 32K window) and FLG 0x01, whose check bits make 0x7801 a
    // multiple of 31.
    idat.bytes(&.{ 0x78, 0x01 });
    var stream = StoredStream{ .chunk = &idat, .left = raw };
    var row: [1 + 3 * max_side]u8 = undefined;
    for (0..height) |y| {
        if (output.cancelled) |cancelled| if (cancelled(output.context)) return;
        row[0] = 0;
        for (canvas.pixels[y * width ..][0..width], 0..) |source, x| {
            const pixel = if (mode) |colors| graphics_palette.convert(colors, x, y, source) else source;
            row[1 + 3 * x] = @truncate(pixel >> 16);
            row[2 + 3 * x] = @truncate(pixel >> 8);
            row[3 + 3 * x] = @truncate(pixel);
        }
        stream.bytes(row[0..row_size]);
    }
    var checksum: [4]u8 = undefined;
    std.mem.writeInt(u32, &checksum, (stream.adler_b << 16) | stream.adler_a, .big);
    idat.bytes(&checksum);
    idat.end();
    var iend = Chunk.begin(output, "IEND", 0);
    iend.end();
}

/// Binary PPM (P6): a text header, then red, green, and blue bytes, top row first.
fn writePpm(canvas: Canvas, output: *FileOutput) void {
    var header: [32]u8 = undefined;
    output.bytes(std.fmt.bufPrint(&header, "P6\n{d} {d}\n255\n", .{ canvas.width, canvas.height }) catch unreachable);
    for (canvas.pixels) |pixel| {
        output.byte(@truncate(pixel >> 16));
        output.byte(@truncate(pixel >> 8));
        output.byte(@truncate(pixel));
    }
}

/// A 24-bit BMP without compression: blue, green, and red bytes, bottom row first, each
/// row padded to a multiple of 4 bytes.
fn writeBmp(canvas: Canvas, output: *FileOutput) void {
    const width: u32 = @intCast(canvas.width);
    const height: u32 = @intCast(canvas.height);
    const row_size = (width * 3 + 3) & ~@as(u32, 3);
    const header_size = 14 + 40;
    output.bytes("BM");
    output.le32(header_size + row_size * height);
    output.le32(0);
    output.le32(header_size);
    output.le32(40);
    output.le32(width);
    output.le32(height);
    output.le16(1);
    output.le16(24);
    output.le32(0);
    output.le32(row_size * height);
    // 2835 pixels per metre is 72 dots per inch.
    output.le32(2835);
    output.le32(2835);
    output.le32(0);
    output.le32(0);
    var row = height;
    while (row > 0) {
        row -= 1;
        for (canvas.pixels[row * width ..][0..width]) |pixel| {
            output.byte(@truncate(pixel));
            output.byte(@truncate(pixel >> 8));
            output.byte(@truncate(pixel >> 16));
        }
        for (0..row_size - width * 3) |_| output.byte(0);
    }
}

/// Whether a word is one REQUIRE-GRAPHICS added: a GFX- word, or a word the graphics
/// library defined (and not a later word of the same name). HELP describes these.
pub fn isGraphicsWord(self: *const State, word: defs.Word) bool {
    return library_loading.isGroupWord(self, word, library_name);
}

/// Whether REQUIRE-GRAPHICS has loaded the graphics words and they are still in the
/// dictionary (FORGET and MARKER can remove them).
pub fn graphicsLoaded(self: *const State) bool {
    return library_loading.isLoaded(self, group);
}

pub const group: library_loading.Group(@TypeOf(definitions[0])) = .{
    .vocabulary = "GRAPHICS",
    .definitions = &definitions,
    .library_name = library_name,
    .vocabulary_address = graphics_vocabulary_address,
    .image_address = graphics_image_address,
};

/// REQUIRE-GRAPHICS: the first time, appends the GRAPHICS vocabulary to the Forth word
/// list and the GFX- words and the graphics library to GRAPHICS; later it does nothing.
/// The search order and the current word list stay as they were. When the library fails
/// to load, everything it added is removed again.
pub fn requireGraphics(self: *State) RuntimeError!void {
    if (!defs.graphics_enabled) return error.GraphicsUnavailable;
    return library_loading.require(self, group, self.graphics_library);
}
