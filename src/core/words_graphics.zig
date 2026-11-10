//! The graphics words: REQUIRE-GRAPHICS, which loads them, and the GFX- words, which
//! draw on one 32-bit image that the host keeps outside logical memory.
//!
//! The GFX- words are not among the built-in words every dictionary starts with:
//! REQUIRE-GRAPHICS appends them, with the GRAPHICS vocabulary and the graphics library
//! written in Forth, after the words already defined. A dictionary that never loads them
//! keeps the numbers of its words, and its images stay SIGIMG42.

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
const Canvas = graphics_images.Canvas;
const memory_map = @import("memory_map.zig");
const Builtin = defs.Builtin;
const Cell = memory_map.Cell;
const RuntimeError = defs.RuntimeError;
const State = forth.State;
const graphics_image_address = memory_map.graphics_image_address;
const graphics_vocabulary_address = memory_map.graphics_vocabulary_address;

/// The built-in words this file executes; executeBuiltin dispatches by this list.
pub const words = [_]Builtin{ .gfx_init, .gfx_width, .gfx_height, .gfx_pset, .gfx_pget, .gfx_hline, .gfx_cls, .gfx_save_ppm, .gfx_save_bmp, .gfx_show_blocks, .gfx_show_sixel, .gfx_show_window, .gfx_window_query, .gfx_save_png, .gfx_inkey, .gfx_mouse, .gfx_mouse_mode, .gfx_glyph_load, .gfx_glyph_box, .gfx_glyph_alpha, .gfx_font_height, .gfx_font_builtin, .gfx_font_load, .gfx_font_system, .gfx_color_mode, .gfx_tcl, .gfx_tcl_error, .gfx_tcl_event, .gfx_tcl_program, .gfx_tcl_stop, .gfx_show_tk, .gfx_key_held, .gfx_window_size, .gfx_gamepad_poll, .gfx_gamepad_query, .gfx_gamepad_name, .gfx_gamepad_map, .gfx_gamepad_guid, .gfx_mouse_event } ++ graphics_images.words;

/// The GFX- words in the order REQUIRE-GRAPHICS appends them, right after the GRAPHICS
/// vocabulary. The order is part of the dictionary that images keep: add new words at
/// the end.
pub const definitions = [_]struct { []const u8, Builtin }{
    .{ "GFX-INIT", .gfx_init },     .{ "GFX-WIDTH", .gfx_width }, .{ "GFX-HEIGHT", .gfx_height },
    .{ "GFX-PSET", .gfx_pset },     .{ "GFX-PGET", .gfx_pget },   .{ "GFX-HLINE", .gfx_hline },
    .{ "GFX-CLS", .gfx_cls },       .{ "GFX-SAVE-PPM", .gfx_save_ppm }, .{ "GFX-SAVE-BMP", .gfx_save_bmp },
    .{ "GFX-SHOW-BLOCKS", .gfx_show_blocks }, .{ "GFX-SHOW-SIXEL", .gfx_show_sixel }, .{ "GFX-SHOW-WINDOW", .gfx_show_window },
    .{ "GFX-WINDOW?", .gfx_window_query }, .{ "GFX-SAVE-PNG", .gfx_save_png }, .{ "GFX-INKEY", .gfx_inkey },
    .{ "GFX-MOUSE", .gfx_mouse },           .{ "GFX-MOUSE-MODE", .gfx_mouse_mode }, .{ "GFX-GLYPH-LOAD", .gfx_glyph_load },
    .{ "GFX-GLYPH-BOX", .gfx_glyph_box },   .{ "GFX-GLYPH-ALPHA", .gfx_glyph_alpha }, .{ "GFX-FONT-HEIGHT", .gfx_font_height },
    .{ "GFX-FONT-BUILTIN", .gfx_font_builtin }, .{ "GFX-FONT-LOAD", .gfx_font_load }, .{ "GFX-FONT-SYSTEM", .gfx_font_system },
    .{ "GFX-COLOR-MODE", .gfx_color_mode },  .{ "GFX-TCL", .gfx_tcl },         .{ "GFX-TCL-ERROR", .gfx_tcl_error },
    .{ "GFX-TCL-EVENT", .gfx_tcl_event },    .{ "GFX-TCL-PROGRAM", .gfx_tcl_program }, .{ "GFX-TCL-STOP", .gfx_tcl_stop },
    .{ "GFX-SHOW-TK", .gfx_show_tk },        .{ "GFX-KEY-HELD", .gfx_key_held },
    .{ "GFX-WINDOW-SIZE", .gfx_window_size },
    .{ "GFX-GAMEPAD-POLL", .gfx_gamepad_poll },
    .{ "GFX-GAMEPAD-QUERY", .gfx_gamepad_query },
    .{ "GFX-GAMEPAD-NAME", .gfx_gamepad_name },
    .{ "GFX-GAMEPAD-MAP", .gfx_gamepad_map },
    .{ "GFX-GAMEPAD-GUID", .gfx_gamepad_guid },
    .{ "GFX-IMAGE-NEW", .gfx_image_new },
    .{ "GFX-IMAGE-FREE", .gfx_image_free },
    .{ "GFX-IMAGE-SIZE", .gfx_image_size },
    .{ "GFX-TARGET", .gfx_target },
    .{ "GFX-TARGET@", .gfx_target_query },
    .{ "GFX-COPY", .gfx_copy },
    .{ "GFX-IMAGE-LOAD", .gfx_image_load },
    .{ "GFX-MOUSE-EVENT", .gfx_mouse_event },
    .{ "GFX-PIXEL", .gfx_pixel },
    .{ "GFX-TILEMAP", .gfx_tilemap },
};

/// The words of the graphics library that HELP describes; the help test checks that the
/// library defines each of them.
pub const library_words = [_][]const u8{ "RGB", "COLOR", "COLOR!", "COLOR@", "PSET", "CLS", "LINE", "RECT", "FILL-RECT", "CIRCLE", "FILL-CIRCLE", "PAINT", "SAVE-PPM", "SAVE-BMP", "SAVE-PNG", "SHOW", "DISPLAY-TERMINAL", "DISPLAY-WINDOW", "TERMINAL-BLOCKS", "TERMINAL-SIXEL", "DISPLAY-COLORS", "DITHER", "TCL", "TCL-EVAL", "TCL-ERROR$", "TCL-EVENT", "TCL-PROGRAM", "TCL-STOP", "DISPLAY-TK", "INKEY", "KEY-HELD?", "MOUSE", "WINDOW-SIZE", "MOUSE-ON", "MOUSE-OFF", "FRAME", "TEXT", "TEXT-SCALE", "TEXT-WIDTH", "TEXT-HEIGHT", "BUILTIN-FONT", "LOAD-FONT", "SYSTEM-FONT", "K-UP", "K-DOWN", "K-LEFT", "K-RIGHT", "K-HOME", "K-END", "K-PRIOR", "K-NEXT", "K-INSERT", "K-DELETE", "K-F1", "K-F2", "K-F3", "K-F4", "K-F5", "K-F6", "K-F7", "K-F8", "K-F9", "K-F10", "K-F11", "K-F12", "GAMEPAD-POLL", "GAMEPAD?", "GAMEPAD-ID", "GAMEPAD-BUTTONS", "GAMEPAD-MAPPED?", "GAMEPAD-AXES", "GAMEPAD-BUTTON-COUNT", "GAMEPAD-HATS", "GAMEPAD-AXIS", "GAMEPAD-HAT", "GAMEPAD-BUTTON?", "GAMEPAD-NAME", "GAMEPAD-MAP", "GAMEPAD-GUID", "SCREEN", "NEW-IMAGE", "FREE-IMAGE", "IMAGE-SIZE", "DRAW-TO", "DRAWING", "TRANSPARENT", "IMAGE-FLIP", "COPY-RECT", "PUT-IMAGE", "LOAD-IMAGE", "IMAGE-MODE", "IMAGE-ALPHA", "IMAGE-SCALE", "MOUSE-EVENT" };

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
        .gfx_gamepad_poll, .gfx_gamepad_query, .gfx_gamepad_name, .gfx_gamepad_map, .gfx_gamepad_guid => try @import("gamepad.zig").execute(self, builtin),
        .gfx_image_new, .gfx_image_free, .gfx_image_size, .gfx_target, .gfx_target_query, .gfx_copy, .gfx_image_load, .gfx_pixel, .gfx_tilemap => try graphics_images.execute(self, builtin),
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
        },
        // These draw on, and measure, the image drawn on: the screen or an image of the pool.
        .gfx_width => try self.push(@intCast((try graphics_images.imageSize(self, self.gfx_target))[0])),
        .gfx_height => try self.push(@intCast((try graphics_images.imageSize(self, self.gfx_target))[1])),
        .gfx_pset => {
            const rgb = try self.pop();
            const y = try self.pop();
            const x = try self.pop();
            const canvas = try graphics_images.target(self);
            if (canvas.index(x, y)) |index| canvas.pixels[index] = color(rgb);
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
            if (y < 0 or y >= canvas.height) return;
            const left = @max(@min(x1, x2), 0);
            const right = @min(@max(x1, x2), width - 1);
            if (left > right) return;
            const row: usize = @intCast(y * width);
            @memset(canvas.pixels[row + @as(usize, @intCast(left)) .. row + @as(usize, @intCast(right)) + 1], color(rgb));
        },
        .gfx_cls => {
            const rgb = try self.pop();
            const canvas = try graphics_images.target(self);
            @memset(canvas.pixels, color(rgb));
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
        .gfx_key_held => {
            const key = try self.pop();
            try self.push(if (try graphics_input.keyHeld(self, key)) -1 else 0);
        },
        .gfx_mouse => {
            const state = try graphics_input.mouseState(self);
            for (state) |value| try self.push(value);
        },
        .gfx_mouse_mode => graphics_input.setMouse(self, try self.pop() != 0),
        .gfx_mouse_event => if (try graphics_input.nextMouseEvent(self)) |event| {
            for ([_]Cell{ event.x, event.y, event.button, @intFromEnum(event.kind), -1 }) |value| try self.push(value);
        } else try self.push(0),
        else => {
            // The fonts are left out of a build without graphics.
            if (!defs.graphics_enabled) return error.GraphicsUnavailable;
            try executeFont(self, builtin);
        },
    }
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
            output.ior = files.write(output.self.writer.context, output.fileid, output.buffer[0..output.used]);
        }
        output.used = 0;
    }
};

/// Where the bytes of a PNG go: a file, or the Tcl program as base64 (DISPLAY-TK).
pub const ByteSink = struct {
    context: *anyopaque,
    write: *const fn (*anyopaque, []const u8) void,

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
