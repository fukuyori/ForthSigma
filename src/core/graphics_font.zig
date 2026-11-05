//! The fonts of TEXT: the built-in ASCII font, a BDF file that LOAD-FONT read, or a font
//! of the system that SYSTEM-FONT chose and the host draws (Windows). GFX-GLYPH-LOAD puts
//! one glyph here, as coverage from 0 (none) to 255 (full) for each pixel of its box,
//! and TEXT's Forth code reads it with GFX-GLYPH-BOX and GFX-GLYPH-ALPHA.

const std = @import("std");
const defs = @import("defs.zig");
const forth = @import("../forth.zig");
const host_interface = @import("host_interface.zig");
const builtin_font = @import("../graphics/font_misaki.zig");
const Cell = forth.Cell;
const RuntimeError = defs.RuntimeError;
const State = forth.State;

/// The highest font, and the widest box of one glyph, in pixels.
pub const max_height = 256;
pub const max_box_width = 512;
/// The largest BDF font LOAD-FONT keeps: its table of glyphs and their pixels.
const max_font_bytes = 16 * 1024 * 1024;
/// The THROW code (and ior) of a font that cannot be used: a file that is not a BDF
/// font LOAD-FONT can read, or a name the system has no font of.
pub const font_error: Cell = -272;

pub const Kind = enum { builtin, bdf, system };

/// A glyph of a BDF font: where its rows of bits start in `bits`, its advance, and its
/// box against the pen (left) and the top of the line (top).
const Entry = extern struct {
    code: u32,
    offset: u32,
    advance: i16,
    left: i16,
    top: i16,
    width: u16,
    height: u16,
    padding: [6]u8 = @splat(0),
};

comptime {
    std.debug.assert(@sizeOf(Entry) == 24);
}

pub const FontState = struct {
    kind: Kind = .builtin,
    /// The BDF font, in the host's buffer: its glyphs sorted by code point, the rows of
    /// bits after them, and the height of its lines. The buffer stays after BUILTIN-FONT
    /// until another font is read.
    buffer: []u64 = &.{},
    entries: []const Entry = &.{},
    bits: []const u8 = &.{},
    bdf_height: u32 = 0,
    system_height: u32 = 0,
    /// The glyph GFX-GLYPH-LOAD loaded last: `width` × `height` pixels from `left`
    /// pixels right of the pen, taken from columns `first` on of rows `stride` long of
    /// State.gfx_glyph_alpha (kept there, not here, so that the default value of the
    /// State does not carry it into the program).
    left: i32 = 0,
    width: u32 = 0,
    height: u32 = 0,
    stride: u32 = 0,
    first: u32 = 0,
};

/// The coverage of the loaded glyph, row after row.
pub const Alpha = [max_box_width * max_height]u8;

/// The height of a line of the current font.
pub fn fontHeight(self: *const State) u32 {
    const font = &self.gfx_font;
    return switch (font.kind) {
        .builtin => 8,
        .bdf => font.bdf_height,
        .system => font.system_height,
    };
}

/// BUILTIN-FONT, and the font after an image is restored.
pub fn selectBuiltin(self: *State) void {
    self.gfx_font.kind = .builtin;
}

/// GFX-GLYPH-LOAD: loads the glyph of a code point and gives its advance, or -1 when
/// the font has none.
pub fn loadGlyph(self: *State, code: Cell) Cell {
    const font = &self.gfx_font;
    if (code < 0 or code > 0x10FFFF) return -1;
    const alpha = &self.gfx_glyph_alpha;
    const advance: Cell = switch (font.kind) {
        .builtin => builtinGlyph(font, alpha, code) orelse return -1,
        .bdf => bdfGlyph(font, alpha, code) orelse return -1,
        .system => systemGlyph(self, @intCast(code)) orelse return -1,
    };
    trimBox(font, alpha);
    return advance;
}

fn builtinGlyph(font: *FontState, alpha: *Alpha, code: Cell) ?Cell {
    const first_code = builtin_font.glyphs[0].code;
    if (code < first_code or code >= first_code + builtin_font.glyphs.len) return null;
    const glyph = builtin_font.glyphs[@intCast(code - first_code)];
    font.left = 0;
    font.width = glyph.width;
    font.height = 8;
    font.stride = glyph.width;
    for (0..8) |row| {
        const bits: u8 = @truncate(glyph.rows >> @intCast(8 * (7 - row)));
        for (0..glyph.width) |column| {
            alpha[row * glyph.width + column] = if (bits & (@as(u8, 0x80) >> @intCast(column)) != 0) 255 else 0;
        }
    }
    return glyph.width;
}

fn bdfGlyph(font: *FontState, alpha: *Alpha, code: Cell) ?Cell {
    var low: usize = 0;
    var high: usize = font.entries.len;
    const entry = while (low < high) {
        const middle = low + (high - low) / 2;
        const middle_code: Cell = font.entries[middle].code;
        if (middle_code == code) break font.entries[middle];
        if (middle_code < code) low = middle + 1 else high = middle;
    } else return null;
    // The box is the line's height, with the glyph's rows where they lie in the line.
    const height = font.bdf_height;
    font.left = entry.left;
    font.width = entry.width;
    font.height = height;
    font.stride = entry.width;
    @memset(alpha[0 .. @as(usize, entry.width) * height], 0);
    const row_bytes = (@as(usize, entry.width) + 7) / 8;
    for (0..entry.height) |row| {
        const line = @as(i64, entry.top) + @as(i64, @intCast(row));
        if (line < 0 or line >= height) continue;
        const bits = font.bits[entry.offset + row * row_bytes ..][0..row_bytes];
        for (0..entry.width) |column| {
            if (bits[column / 8] & (@as(u8, 0x80) >> @intCast(column % 8)) != 0) {
                alpha[@as(usize, @intCast(line)) * entry.width + column] = 255;
            }
        }
    }
    return entry.advance;
}

fn systemGlyph(self: *State, code: u21) ?Cell {
    const font = &self.gfx_font;
    const glyph_fn = self.writer.system_glyph_fn orelse return null;
    const glyph = glyph_fn(self.writer.context, code, &self.gfx_glyph_alpha, max_box_width) orelse return null;
    // A host that gives a box larger than it may is not believed.
    if (glyph.width > max_box_width or glyph.height > max_height) return null;
    font.left = glyph.left;
    font.width = glyph.width;
    font.height = glyph.height;
    font.stride = glyph.width;
    return glyph.advance;
}

/// Leaves out the columns at the left and right of the box that have no pixel, so that
/// TEXT visits fewer pixels.
fn trimBox(font: *FontState, alpha: *const Alpha) void {
    font.first = 0;
    // An empty box (a space of a BDF font may have one): nothing to draw.
    if (font.width == 0 or font.height == 0) {
        font.width = 0;
        return;
    }
    var first: u32 = font.width;
    var last: u32 = 0;
    for (0..font.height) |row| {
        const line = alpha[row * font.stride ..][0..font.width];
        for (line, 0..) |value, column| {
            if (value == 0) continue;
            first = @min(first, @as(u32, @intCast(column)));
            last = @max(last, @as(u32, @intCast(column)));
        }
    }
    if (first > last) {
        font.width = 0;
        return;
    }
    font.first = first;
    font.left += @intCast(first);
    font.width = last - first + 1;
}

/// GFX-GLYPH-ALPHA: the coverage of a pixel of the loaded glyph's box, 0 outside it.
pub fn alphaAt(self: *const State, x: Cell, y: Cell) Cell {
    const font = &self.gfx_font;
    if (x < 0 or y < 0 or x >= font.width or y >= font.height) return 0;
    return self.gfx_glyph_alpha[@as(usize, @intCast(y)) * font.stride + font.first + @as(usize, @intCast(x))];
}

/// GFX-FONT-SYSTEM: the system's font of that name, `height` pixels a line.
pub fn selectSystem(self: *State, name: []const u8, height: Cell) RuntimeError!Cell {
    if (height < 1 or height > max_height) return error.InvalidNumber;
    const select = self.writer.system_font_fn orelse return error.HostUnavailable;
    if (!try select(self.writer.context, name, @intCast(height))) return font_error;
    self.gfx_font.kind = .system;
    self.gfx_font.system_height = @intCast(height);
    return 0;
}

const Counts = struct { glyphs: usize = 0, bit_bytes: usize = 0, height: u32 = 0 };
const Output = struct { entries: []Entry, bits: []u8 };
const ScanError = error{ BadFont, ReadFailed };

/// GFX-FONT-LOAD: reads a BDF font, once to measure it and once to keep it in a buffer
/// the host gives. Returns 0, the ior of the file, or `font_error`.
pub fn loadBdf(self: *State, name: []const u8) RuntimeError!Cell {
    const files = try self.fileOps();
    if (self.writer.font_buffer_fn == null or self.writer.font_free_fn == null) return error.HostUnavailable;
    const context = self.writer.context;
    const opened = files.open(context, name, .read_only, false);
    if (opened.ior != 0) return opened.ior;
    const fileid: Cell = @bitCast(opened.value);
    var ior: Cell = 0;
    const result = loadOpenBdf(self, fileid, &ior);
    const closed = files.close(context, fileid);
    result catch |err| switch (err) {
        error.ReadFailed => return ior,
        error.BadFont => return font_error,
        error.MemoryExhausted => return error.MemoryExhausted,
        error.HostFailed => return error.HostFailed,
    };
    return closed;
}

/// Reads the font into a new buffer, and only when it has all been read gives up the
/// old font's buffer: a font that fails, also on the second reading, leaves the font
/// as it was.
fn loadOpenBdf(self: *State, fileid: Cell, ior: *Cell) error{ BadFont, ReadFailed, MemoryExhausted, HostFailed }!void {
    const counts = try scan(self, fileid, null, ior);
    if (counts.glyphs == 0) return error.BadFont;
    const table_bytes = counts.glyphs * @sizeOf(Entry);
    const total = table_bytes + counts.bit_bytes;
    const files = self.writer.file_ops.?;
    const repositioned = files.reposition(self.writer.context, fileid, 0);
    if (repositioned != 0) {
        ior.* = repositioned;
        return error.ReadFailed;
    }
    const words = (total + 7) / 8;
    const font = &self.gfx_font;
    const context = self.writer.context;
    const buffer = self.writer.font_buffer_fn.?(context, words) orelse return error.MemoryExhausted;
    errdefer self.writer.font_free_fn.?(context, buffer);
    if (buffer.len != words) return error.HostFailed;
    const entries_start: [*]Entry = @ptrCast(buffer.ptr);
    const bytes_start: [*]u8 = @ptrCast(buffer.ptr);
    const output = Output{ .entries = entries_start[0..counts.glyphs], .bits = bytes_start[table_bytes..total] };
    const again = try scan(self, fileid, output, ior);
    // The file changed between the two readings.
    if (again.glyphs != counts.glyphs or again.bit_bytes != counts.bit_bytes or again.height != counts.height) return error.BadFont;
    std.sort.pdq(Entry, output.entries, {}, struct {
        fn less(_: void, a: Entry, b: Entry) bool {
            return a.code < b.code;
        }
    }.less);
    if (font.buffer.len != 0) self.writer.font_free_fn.?(context, font.buffer);
    font.buffer = buffer;
    font.entries = output.entries;
    font.bits = output.bits;
    font.bdf_height = counts.height;
    font.kind = .bdf;
}

/// The largest size a number of a BDF file may have: above every code point (0x10FFFF),
/// far beyond any real font's sizes, and small enough that the sums and differences of
/// a few of them cannot overflow.
const max_bdf_number = 0x200000;

/// A number of a BDF file; FONT ERROR when it is missing, not a number, or beyond
/// ±0x200000.
fn number(token: ?[]const u8) ScanError!i64 {
    const value = std.fmt.parseInt(i64, token orelse return error.BadFont, 10) catch return error.BadFont;
    if (value < -max_bdf_number or value > max_bdf_number) return error.BadFont;
    return value;
}

/// One reading of a BDF file: counts its glyphs and the bytes of their rows and, with
/// `output`, keeps them. Glyphs with no code point (ENCODING -1) are left out.
fn scan(self: *State, fileid: Cell, output: ?Output, ior: *Cell) ScanError!Counts {
    const files = self.writer.file_ops.?;
    var counts = Counts{};
    var ascent: ?i64 = null;
    var descent: ?i64 = null;
    var box_height: ?i64 = null;
    var box_bottom: ?i64 = null;
    // The glyph being read.
    var in_glyph = false;
    var code: i64 = -1;
    var advance: ?i64 = null;
    var box: ?[4]i64 = null;
    var rows_read: ?usize = null;
    var line_buffer: [512]u8 = undefined;
    while (true) {
        const result = files.read_line(self.writer.context, fileid, &line_buffer);
        if (result.ior != 0) {
            ior.* = result.ior;
            return error.ReadFailed;
        }
        if (!result.found) break;
        const line = std.mem.trim(u8, line_buffer[0..@min(result.length, line_buffer.len)], " \t\r");
        if (rows_read) |rows| {
            const glyph_box = box.?;
            if (!std.mem.eql(u8, line, "ENDCHAR")) {
                // A row of the bitmap: its bytes in hexadecimal.
                const row_bytes: usize = @intCast(@divTrunc(glyph_box[0] + 7, 8));
                if (rows >= glyph_box[1] or line.len < 2 * row_bytes) return error.BadFont;
                if (code >= 0 and code <= 0x10FFFF) {
                    if (output) |out| {
                        // The file grew since it was measured.
                        if (counts.bit_bytes + (rows + 1) * row_bytes > out.bits.len) return error.BadFont;
                        for (0..row_bytes) |index| {
                            out.bits[counts.bit_bytes + rows * row_bytes + index] = std.fmt.parseInt(u8, line[2 * index ..][0..2], 16) catch return error.BadFont;
                        }
                    } else {
                        for (0..row_bytes) |index| _ = std.fmt.parseInt(u8, line[2 * index ..][0..2], 16) catch return error.BadFont;
                    }
                }
                rows_read = rows + 1;
                continue;
            }
            if (rows != glyph_box[1]) return error.BadFont;
        }
        var tokens = std.mem.tokenizeAny(u8, line, " \t");
        const key = tokens.next() orelse continue;
        if (std.mem.eql(u8, key, "FONT_ASCENT")) {
            ascent = try number(tokens.next());
        } else if (std.mem.eql(u8, key, "FONT_DESCENT")) {
            descent = try number(tokens.next());
        } else if (std.mem.eql(u8, key, "FONTBOUNDINGBOX")) {
            _ = try number(tokens.next());
            box_height = try number(tokens.next());
            _ = try number(tokens.next());
            box_bottom = try number(tokens.next());
        } else if (std.mem.eql(u8, key, "STARTCHAR")) {
            in_glyph = true;
            code = -1;
            advance = null;
            box = null;
            rows_read = null;
        } else if (std.mem.eql(u8, key, "ENCODING")) {
            code = try number(tokens.next());
        } else if (std.mem.eql(u8, key, "DWIDTH")) {
            advance = try number(tokens.next());
        } else if (std.mem.eql(u8, key, "BBX")) {
            var values: [4]i64 = undefined;
            for (&values) |*value| value.* = try number(tokens.next());
            if (values[0] < 0 or values[0] > max_box_width or values[1] < 0 or values[1] > max_height) return error.BadFont;
            if (values[2] < -max_box_width or values[2] > max_box_width or values[3] < -max_height or values[3] > max_height) return error.BadFont;
            box = values;
        } else if (std.mem.eql(u8, key, "BITMAP")) {
            if (!in_glyph or box == null) return error.BadFont;
            rows_read = 0;
        } else if (std.mem.eql(u8, key, "ENDCHAR")) {
            if (!in_glyph) return error.BadFont;
            const glyph_box = box orelse return error.BadFont;
            in_glyph = false;
            if (rows_read == null and glyph_box[1] != 0) return error.BadFont;
            rows_read = null;
            if (code < 0 or code > 0x10FFFF) continue;
            const line_ascent = ascent orelse if (box_height) |h| h + (box_bottom orelse 0) else return error.BadFont;
            const glyph_advance = advance orelse glyph_box[0];
            if (glyph_advance < -max_box_width or glyph_advance > max_box_width) return error.BadFont;
            const top = line_ascent - (glyph_box[3] + glyph_box[1]);
            if (top < -4 * max_height or top > 4 * max_height) return error.BadFont;
            const row_bytes: usize = @intCast(@divTrunc(glyph_box[0] + 7, 8));
            const bytes = row_bytes * @as(usize, @intCast(glyph_box[1]));
            if (output) |out| {
                if (counts.glyphs >= out.entries.len) return error.BadFont;
                out.entries[counts.glyphs] = .{
                    .code = @intCast(code),
                    .offset = @intCast(counts.bit_bytes),
                    .advance = @intCast(glyph_advance),
                    .left = @intCast(glyph_box[2]),
                    .top = @intCast(top),
                    .width = @intCast(glyph_box[0]),
                    .height = @intCast(glyph_box[1]),
                };
            }
            counts.glyphs += 1;
            counts.bit_bytes += bytes;
            if (counts.glyphs * @sizeOf(Entry) + counts.bit_bytes > max_font_bytes) return error.BadFont;
        } else if (std.mem.eql(u8, key, "ENDFONT")) {
            break;
        }
    }
    if (in_glyph) return error.BadFont;
    const line_ascent = ascent orelse if (box_height) |h| h + (box_bottom orelse 0) else return error.BadFont;
    const line_descent = descent orelse if (box_bottom) |bottom| -bottom else return error.BadFont;
    const height = line_ascent + line_descent;
    if (height < 1 or height > max_height) return error.BadFont;
    counts.height = @intCast(height);
    return counts;
}
