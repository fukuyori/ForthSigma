//! The graphics words: REQUIRE-GRAPHICS, which loads them, and the GFX- words, which
//! draw on one 32-bit image that the host keeps outside logical memory.
//!
//! The GFX- words are not among the built-in words every dictionary starts with:
//! REQUIRE-GRAPHICS appends them, with the GRAPHICS vocabulary and the graphics library
//! written in Forth, after the words already defined. A dictionary that never loads them
//! keeps the numbers of its words, and its images stay SIGIMG33.

const std = @import("std");
const defs = @import("defs.zig");
const forth = @import("../forth.zig");
const graphics_terminal = @import("graphics_terminal.zig");
const memory_map = @import("memory_map.zig");
const Builtin = defs.Builtin;
const Cell = memory_map.Cell;
const RuntimeError = defs.RuntimeError;
const State = forth.State;
const base_address = memory_map.base_address;
const current_wordlist_address = memory_map.current_wordlist_address;
const forth_wordlist = memory_map.forth_wordlist;
const graphics_image_address = memory_map.graphics_image_address;
const graphics_vocabulary_address = memory_map.graphics_vocabulary_address;
const max_search_order = memory_map.max_search_order;
const max_wordlists = memory_map.max_wordlists;
const wordlist_count_address = memory_map.wordlist_count_address;

/// The built-in words this file executes; executeBuiltin dispatches by this list.
pub const words = [_]Builtin{ .gfx_init, .gfx_width, .gfx_height, .gfx_pset, .gfx_pget, .gfx_hline, .gfx_cls, .gfx_save_ppm, .gfx_save_bmp, .gfx_show_blocks, .gfx_show_sixel, .gfx_show_window, .gfx_window_query };

/// The GFX- words in the order REQUIRE-GRAPHICS appends them, right after the GRAPHICS
/// vocabulary. The order is part of the dictionary that images keep: add new words at
/// the end.
pub const definitions = [_]struct { []const u8, Builtin }{
    .{ "GFX-INIT", .gfx_init },     .{ "GFX-WIDTH", .gfx_width }, .{ "GFX-HEIGHT", .gfx_height },
    .{ "GFX-PSET", .gfx_pset },     .{ "GFX-PGET", .gfx_pget },   .{ "GFX-HLINE", .gfx_hline },
    .{ "GFX-CLS", .gfx_cls },       .{ "GFX-SAVE-PPM", .gfx_save_ppm }, .{ "GFX-SAVE-BMP", .gfx_save_bmp },
    .{ "GFX-SHOW-BLOCKS", .gfx_show_blocks }, .{ "GFX-SHOW-SIXEL", .gfx_show_sixel }, .{ "GFX-SHOW-WINDOW", .gfx_show_window },
    .{ "GFX-WINDOW?", .gfx_window_query },
};

/// The words of the graphics library that HELP describes; the help test checks that the
/// library defines each of them.
pub const library_words = [_][]const u8{ "RGB", "COLOR", "COLOR!", "COLOR@", "PSET", "CLS", "LINE", "RECT", "FILL-RECT", "CIRCLE", "FILL-CIRCLE", "PAINT", "SAVE-PPM", "SAVE-BMP", "SHOW", "DISPLAY-TERMINAL", "DISPLAY-WINDOW", "TERMINAL-BLOCKS", "TERMINAL-SIXEL" };

/// The graphics library, which REQUIRE-GRAPHICS interprets after appending the GFX- words.
pub const library = @embedFile("../graphics/graphics.fs");

/// The name the library has in the source file table, for LOCATE and error messages.
pub const library_name = "*graphics library*";

/// Limits of an image: each side 1 to 8192 pixels and at most 64 MiB in all.
pub const max_side = 8192;
pub const max_bytes = 64 * 1024 * 1024;

/// Every pixel is opaque: the alpha byte above the red, green, and blue bytes is 255.
const opaque_alpha: u32 = 0xff00_0000;
const rgb_mask: u32 = 0x00ff_ffff;

pub fn execute(self: *State, builtin: Builtin) RuntimeError!void {
    switch (builtin) {
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
        .gfx_width => try self.push(self.gfx_width),
        .gfx_height => try self.push(self.gfx_height),
        .gfx_pset => {
            const rgb = try self.pop();
            const y = try self.pop();
            const x = try self.pop();
            try requireImage(self);
            if (pixelIndex(self, x, y)) |index| self.gfx_pixels[index] = color(rgb);
        },
        .gfx_pget => {
            const y = try self.pop();
            const x = try self.pop();
            try requireImage(self);
            const index = pixelIndex(self, x, y) orelse return self.push(-1);
            try self.push(self.gfx_pixels[index] & rgb_mask);
        },
        .gfx_hline => {
            const rgb = try self.pop();
            const y = try self.pop();
            const x2 = try self.pop();
            const x1 = try self.pop();
            try requireImage(self);
            if (y < 0 or y >= self.gfx_height) return;
            const left = @max(@min(x1, x2), 0);
            const right = @min(@max(x1, x2), self.gfx_width - 1);
            if (left > right) return;
            const row: usize = @intCast(y * self.gfx_width);
            @memset(self.gfx_pixels[row + @as(usize, @intCast(left)) .. row + @as(usize, @intCast(right)) + 1], color(rgb));
        },
        .gfx_cls => {
            const rgb = try self.pop();
            try requireImage(self);
            @memset(self.gfx_pixels, color(rgb));
        },
        .gfx_save_ppm, .gfx_save_bmp => {
            const name = try self.memoryRange();
            try requireImage(self);
            try self.push(try saveImage(self, name, if (builtin == .gfx_save_ppm) .ppm else .bmp));
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
            try window_fn(self.writer.context, self.gfx_pixels, @intCast(self.gfx_width), @intCast(self.gfx_height));
        },
        .gfx_window_query => try self.push(if (self.writer.window_fn != null) -1 else 0),
        else => unreachable,
    }
}

/// The pixel count of a width × height image, or NUMBER ERROR when a side is outside
/// 1 to 8192 or the image is over 64 MiB.
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
}

fn requireImage(self: *const State) RuntimeError!void {
    if (self.gfx_pixels.len == 0) return error.NoCanvas;
}

fn pixelIndex(self: *const State, x: Cell, y: Cell) ?usize {
    if (x < 0 or y < 0 or x >= self.gfx_width or y >= self.gfx_height) return null;
    return @intCast(y * self.gfx_width + x);
}

/// A pixel from a color cell: its low 24 bits are 0xRRGGBB, the rest is ignored.
fn color(rgb: Cell) u32 {
    return opaque_alpha | (@as(u32, @truncate(@as(u64, @bitCast(rgb)))) & rgb_mask);
}

const ImageFormat = enum { ppm, bmp };

/// Writes the image to a new file and returns the ior: 0, or the first failure of
/// opening, writing, or closing the file.
fn saveImage(self: *State, name: []const u8, format: ImageFormat) RuntimeError!Cell {
    const files = try self.fileOps();
    const opened = files.open(self.writer.context, name, .write_only, true);
    if (opened.ior != 0) return opened.ior;
    const fileid: Cell = @bitCast(opened.value);
    var output = FileOutput{ .self = self, .fileid = fileid };
    switch (format) {
        .ppm => writePpm(self, &output),
        .bmp => writeBmp(self, &output),
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

    fn flush(output: *FileOutput) void {
        if (output.used != 0 and output.ior == 0) {
            const files = output.self.writer.file_ops.?;
            output.ior = files.write(output.self.writer.context, output.fileid, output.buffer[0..output.used]);
        }
        output.used = 0;
    }
};

/// Binary PPM (P6): a text header, then red, green, and blue bytes, top row first.
fn writePpm(self: *const State, output: *FileOutput) void {
    var header: [32]u8 = undefined;
    output.bytes(std.fmt.bufPrint(&header, "P6\n{d} {d}\n255\n", .{ self.gfx_width, self.gfx_height }) catch unreachable);
    for (self.gfx_pixels) |pixel| {
        output.byte(@truncate(pixel >> 16));
        output.byte(@truncate(pixel >> 8));
        output.byte(@truncate(pixel));
    }
}

/// A 24-bit BMP without compression: blue, green, and red bytes, bottom row first, each
/// row padded to a multiple of 4 bytes.
fn writeBmp(self: *const State, output: *FileOutput) void {
    const width: u32 = @intCast(self.gfx_width);
    const height: u32 = @intCast(self.gfx_height);
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
        for (self.gfx_pixels[row * width ..][0..width]) |pixel| {
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
    if (word.kind == .builtin) return true;
    const files = self.readCellConst(memory_map.source_file_count_address);
    if (word.source_file == 0 or word.source_file > files) return false;
    return std.mem.eql(u8, self.sourceFileName(word.source_file - 1), library_name);
}

/// Whether REQUIRE-GRAPHICS has loaded the graphics words and they are still in the
/// dictionary (FORGET and MARKER can remove them).
pub fn graphicsLoaded(self: *const State) bool {
    const recorded = self.readCellConst(graphics_vocabulary_address);
    // Compared before adding 1, since the cell may hold any value.
    if (recorded < self.builtin_count or recorded >= @as(Cell, self.word_count) - 1) return false;
    const vocabulary = self.words[@intCast(recorded)];
    const first = self.words[@intCast(recorded + 1)];
    return vocabulary.kind == .vocabulary and first.kind == .builtin and first.builtin == definitions[0][1];
}

/// REQUIRE-GRAPHICS: the first time, appends the GRAPHICS vocabulary to the Forth word
/// list and the GFX- words and the graphics library to GRAPHICS; later it does nothing.
/// The search order and the current word list stay as they were. When the library fails
/// to load, everything it added is removed again.
pub fn requireGraphics(self: *State) RuntimeError!void {
    if (!defs.graphics_enabled) return error.GraphicsUnavailable;
    if (self.defining) return error.InvalidDefinition;
    if (graphicsLoaded(self)) return;
    const wordlists = self.wordlistCount();
    if (wordlists == max_wordlists) return error.DictionaryFull;
    var order_buffer: [max_search_order]Cell = undefined;
    const saved_order = self.searchOrder(&order_buffer);
    var order: [max_search_order]Cell = undefined;
    @memcpy(order[0..saved_order.len], saved_order);
    const depth = saved_order.len;
    const current = self.currentWordlist();
    const loaded_files = self.loadedSourceFiles();
    const first_word = self.word_count;
    const wid = wordlists + 1;
    const pending = self.pending;
    const control_depth = self.control_depth;
    const interpret_loop_depth = self.interpret_loop_depth;
    // The library is written in decimal, whatever BASE the caller has.
    const base = self.readCellConst(base_address);
    self.writeCell(base_address, 10) catch unreachable;
    defer self.writeCell(base_address, base) catch unreachable;

    loadGraphicsWords(self, wid) catch |err| {
        // A definition the library started is dropped with the rest, so that the error
        // handling after this does not bring the removed words back.
        if (self.defining) {
            self.defining = false;
            self.setCompiling(false);
            self.local_count = 0;
            self.locals_frame_size = 0;
        }
        self.pending = pending;
        self.control_depth = control_depth;
        self.interpret_loop_depth = interpret_loop_depth;
        if (self.last_created_word) |created| {
            if (created >= first_word) self.last_created_word = null;
        }
        if (self.word_count > first_word) self.forgetFrom(first_word);
        self.writeCell(wordlist_count_address, wordlists) catch unreachable;
        self.writeCell(current_wordlist_address, current) catch unreachable;
        self.setSearchOrder(order[0..depth]);
        self.restoreLoadedSourceFiles(loaded_files);
        return err;
    };
    self.writeCell(current_wordlist_address, current) catch unreachable;
    self.setSearchOrder(order[0..depth]);
    self.writeCell(graphics_vocabulary_address, first_word) catch unreachable;
    self.writeCell(graphics_image_address, 1) catch unreachable;
}

fn loadGraphicsWords(self: *State, wid: Cell) RuntimeError!void {
    try self.writeCell(current_wordlist_address, forth_wordlist);
    _ = try self.appendWord("GRAPHICS", .vocabulary, .drop, wid);
    try self.writeCell(wordlist_count_address, wid);
    try self.writeCell(current_wordlist_address, wid);
    for (definitions) |definition| _ = try self.appendWord(definition[0], .builtin, definition[1], 0);
    // The library defines into GRAPHICS and finds the GFX- words first.
    var order_buffer: [max_search_order]Cell = undefined;
    const order = self.searchOrder(&order_buffer);
    if (order.len == max_search_order) return error.SearchOrderOverflow;
    var library_order: [max_search_order]Cell = undefined;
    library_order[0] = wid;
    @memcpy(library_order[1 .. order.len + 1], order);
    self.setSearchOrder(library_order[0 .. order.len + 1]);
    try self.includeEmbedded(library_name, self.graphics_library);
}
