//! LOAD-IMAGE: reads a PNG, BMP, or PPM/PGM file into a new image of the pool.
//!
//! The whole file is read into memory the host gives for images (image_alloc_fn), so
//! nothing large is on the stack, and freed again at the end. PNG data is inflated with
//! the standard library's flate decompressor, one row at a time, into two row buffers
//! from the same memory. Images are opaque: a pixel whose alpha is below 128 (from an
//! alpha channel, a PNG tRNS chunk, or a BMP alpha mask) gets the transparent color the
//! caller gives, black when it gives none.

const std = @import("std");
const defs = @import("defs.zig");
const forth = @import("../forth.zig");
const memory_map = @import("memory_map.zig");
const graphics_images = @import("graphics_images.zig");
const Cell = memory_map.Cell;
const RuntimeError = defs.RuntimeError;
const State = forth.State;

const opaque_alpha: u32 = 0xff00_0000;

/// A file larger than this is not read.
const max_file_bytes: u64 = 1 << 31;

/// Reads the named file into a new image and returns its handle, or the ior of opening
/// or reading the file (the handle then 0). `key` is the color of the pixels that are
/// more than half transparent, negative for black.
pub fn loadImage(self: *State, name: []const u8, key: Cell) RuntimeError![2]Cell {
    const files = try self.fileOps();
    const alloc_fn = self.writer.image_alloc_fn orelse return error.HostUnavailable;
    const free_fn = self.writer.image_free_fn orelse return error.HostUnavailable;
    const opened = files.open(self.writer.context, name, .read_only, false);
    if (opened.ior != 0) return .{ 0, opened.ior };
    const fileid: Cell = @bitCast(opened.value);
    const sized = files.size(self.writer.context, fileid);
    if (sized.ior != 0) {
        _ = files.close(self.writer.context, fileid);
        return .{ 0, sized.ior };
    }
    if (sized.value > max_file_bytes) {
        _ = files.close(self.writer.context, fileid);
        return error.ImageInvalid;
    }
    const length: usize = @intCast(sized.value);
    const words = alloc_fn(self.writer.context, @max(1, (length + 3) / 4)) orelse {
        _ = files.close(self.writer.context, fileid);
        return error.MemoryExhausted;
    };
    defer free_fn(self.writer.context, words);
    const bytes = std.mem.sliceAsBytes(words)[0..length];
    var done: usize = 0;
    while (done < length) {
        const read = files.read(self.writer.context, fileid, bytes[done..]);
        if (read.ior != 0) {
            _ = files.close(self.writer.context, fileid);
            return .{ 0, read.ior };
        }
        if (read.value == 0) break;
        done += @intCast(read.value);
    }
    const closed = files.close(self.writer.context, fileid);
    if (closed != 0) return .{ 0, closed };
    if (done != length) return error.ImageInvalid;
    const transparent: u32 = if (key < 0) opaque_alpha else opaque_alpha | (@as(u32, @truncate(@as(u64, @bitCast(key)))) & 0xff_ffff);
    const handle = try decode(self, bytes, transparent);
    return .{ handle, 0 };
}

fn decode(self: *State, file: []u8, transparent: u32) RuntimeError!Cell {
    if (std.mem.startsWith(u8, file, "\x89PNG\r\n\x1a\n")) return decodePng(self, file, transparent);
    if (std.mem.startsWith(u8, file, "BM")) return decodeBmp(self, file, transparent);
    if (file.len >= 2 and file[0] == 'P' and (file[1] == '2' or file[1] == '3' or file[1] == '5' or file[1] == '6')) return decodePnm(self, file);
    return error.ImageInvalid;
}

/// Makes the image a decoder fills; the decoder frees it again when it fails later.
fn newImage(self: *State, width: u64, height: u64) RuntimeError!struct { Cell, graphics_images.Canvas } {
    // No file of a kind it reads has an empty picture; a larger one than an image may be
    // is NUMBER ERROR, as for NEW-IMAGE.
    if (width == 0 or height == 0) return error.ImageInvalid;
    if (width > graphics_images.max_side or height > graphics_images.max_side) return error.InvalidNumber;
    const handle = try graphics_images.createImage(self, @intCast(width), @intCast(height));
    return .{ handle, try graphics_images.canvasOf(self, handle) };
}

fn rgb(r: u32, g: u32, b: u32) u32 {
    return opaque_alpha | (r << 16) | (g << 8) | b;
}

// ---- PNG ----------------------------------------------------------------------------

const Png = struct {
    width: u32,
    height: u32,
    depth: u8,
    color_type: u8,
    interlaced: bool,
    palette: [256]u32 = @splat(opaque_alpha),
    palette_alpha: [256]u8 = @splat(255),
    palette_len: usize = 0,
    /// The color of a gray or RGB pixel that tRNS makes transparent, as 16-bit samples.
    key: ?[3]u16 = null,

    fn channels(png: Png) u32 {
        return switch (png.color_type) {
            0, 3 => 1,
            2 => 3,
            4 => 2,
            6 => 4,
            else => unreachable,
        };
    }

    fn bitsPerPixel(png: Png) u64 {
        return @as(u64, png.channels()) * png.depth;
    }

    /// The bytes of one filtered row of `width` pixels, without the filter byte.
    fn rowBytes(png: Png, width: u64) u64 {
        return (width * png.bitsPerPixel() + 7) / 8;
    }
};

fn readBig32(bytes: []const u8) u32 {
    return std.mem.readInt(u32, bytes[0..4], .big);
}

fn decodePng(self: *State, file: []u8, transparent: u32) RuntimeError!Cell {
    var cursor: usize = 8;
    var png: Png = undefined;
    var have_header = false;
    // The IDAT payloads are moved together at the front of the file's memory (only ever
    // leftwards, so nothing is overwritten before it is moved).
    var data_len: usize = 0;
    var seen_end = false;
    while (cursor + 12 <= file.len) {
        const length = readBig32(file[cursor..]);
        if (length > file.len - cursor - 12) return error.ImageInvalid;
        const kind = file[cursor + 4 .. cursor + 8];
        const body = file[cursor + 8 .. cursor + 8 + length];
        // Each chunk ends with the CRC-32 of its type and data.
        if (readBig32(file[cursor + 8 + length ..]) != std.hash.Crc32.hash(file[cursor + 4 .. cursor + 8 + length])) return error.ImageInvalid;
        if (std.mem.eql(u8, kind, "IHDR")) {
            if (length != 13 or have_header) return error.ImageInvalid;
            png = .{ .width = readBig32(body), .height = readBig32(body[4..]), .depth = body[8], .color_type = body[9], .interlaced = body[12] == 1 };
            if (body[10] != 0 or body[11] != 0 or body[12] > 1) return error.ImageInvalid;
            const valid_depth = switch (png.color_type) {
                0 => png.depth == 1 or png.depth == 2 or png.depth == 4 or png.depth == 8 or png.depth == 16,
                3 => png.depth == 1 or png.depth == 2 or png.depth == 4 or png.depth == 8,
                2, 4, 6 => png.depth == 8 or png.depth == 16,
                else => false,
            };
            if (!valid_depth) return error.ImageInvalid;
            have_header = true;
        } else if (!have_header) {
            return error.ImageInvalid;
        } else if (std.mem.eql(u8, kind, "PLTE")) {
            if (length % 3 != 0 or length / 3 > 256) return error.ImageInvalid;
            png.palette_len = length / 3;
            for (0..png.palette_len) |i| png.palette[i] = rgb(body[3 * i], body[3 * i + 1], body[3 * i + 2]);
        } else if (std.mem.eql(u8, kind, "tRNS")) {
            switch (png.color_type) {
                3 => for (body[0..@min(length, 256)], 0..) |alpha, i| {
                    png.palette_alpha[i] = alpha;
                },
                0 => if (length >= 2) {
                    const gray = std.mem.readInt(u16, body[0..2], .big);
                    png.key = .{ gray, gray, gray };
                },
                2 => if (length >= 6) {
                    png.key = .{ std.mem.readInt(u16, body[0..2], .big), std.mem.readInt(u16, body[2..4], .big), std.mem.readInt(u16, body[4..6], .big) };
                },
                else => {},
            }
        } else if (std.mem.eql(u8, kind, "IDAT")) {
            std.mem.copyForwards(u8, file[data_len .. data_len + length], body);
            data_len += length;
        } else if (std.mem.eql(u8, kind, "IEND")) {
            seen_end = true;
            break;
        } else if (kind[0] & 0x20 == 0) {
            // A critical chunk this reader does not know.
            return error.ImageInvalid;
        }
        cursor += 12 + length;
    }
    if (!have_header or !seen_end or data_len == 0) return error.ImageInvalid;
    if (png.color_type == 3 and png.palette_len == 0) return error.ImageInvalid;

    const made = try newImage(self, png.width, png.height);
    const handle = made[0];
    errdefer graphics_images.freeHandle(self, handle);
    // Room for the inflate window and two rows (the one before is needed by the filters).
    const row_capacity = png.rowBytes(png.width) + 1;
    const alloc_fn = self.writer.image_alloc_fn.?;
    const free_fn = self.writer.image_free_fn.?;
    const window = std.compress.flate.max_window_len;
    const scratch_bytes = window + 2 * row_capacity;
    const scratch_words = alloc_fn(self.writer.context, @intCast((scratch_bytes + 3) / 4)) orelse return error.MemoryExhausted;
    defer free_fn(self.writer.context, scratch_words);
    const scratch = std.mem.sliceAsBytes(scratch_words);
    var input: std.Io.Reader = .fixed(file[0..data_len]);
    var inflate: std.compress.flate.Decompress = .init(&input, .zlib, scratch[0..window]);
    const rows = scratch[window..][0..@intCast(2 * row_capacity)];
    const passes: []const [4]u8 = if (png.interlaced) &adam7 else &.{.{ 0, 0, 1, 1 }};
    for (passes) |pass| {
        // The pass's pixels: columns x0, x0 + dx, ..., rows y0, y0 + dy, ...
        const pass_width = (png.width + pass[2] - 1 - pass[0]) / pass[2];
        const pass_height = (png.height + pass[3] - 1 - pass[1]) / pass[3];
        if (png.width <= pass[0] or png.height <= pass[1]) continue;
        const row_len: usize = @intCast(png.rowBytes(pass_width));
        var previous: []u8 = rows[0 .. row_len + 1];
        var current: []u8 = rows[@intCast(row_capacity)..][0 .. row_len + 1];
        @memset(previous, 0);
        for (0..pass_height) |row| {
            inflate.reader.readSliceAll(current) catch return error.ImageInvalid;
            try unfilter(current[0], current[1..], previous[1..], @intCast(@max(1, png.bitsPerPixel() / 8)));
            const y = pass[1] + row * pass[3];
            for (0..pass_width) |column| {
                const x = pass[0] + column * pass[2];
                made[1].pixels[y * png.width + x] = pngPixel(png, current[1..], column, transparent);
            }
            const swap = previous;
            previous = current;
            current = swap;
        }
    }
    // The rest of the stream, so that the decompressor checks the Adler-32 at its end.
    _ = inflate.reader.discardRemaining() catch return error.ImageInvalid;
    return handle;
}

/// Adam7: the first column and row of each pass, and the steps between them.
const adam7 = [_][4]u8{ .{ 0, 0, 8, 8 }, .{ 4, 0, 8, 8 }, .{ 0, 4, 4, 8 }, .{ 2, 0, 4, 4 }, .{ 0, 2, 2, 4 }, .{ 1, 0, 2, 2 }, .{ 0, 1, 1, 2 } };

fn unfilter(kind: u8, row: []u8, previous: []const u8, bpp: usize) RuntimeError!void {
    switch (kind) {
        0 => {},
        1 => for (bpp..row.len) |i| {
            row[i] +%= row[i - bpp];
        },
        2 => for (row, previous) |*value, above| {
            value.* +%= above;
        },
        3 => for (row, 0..) |*value, i| {
            const left: u16 = if (i >= bpp) row[i - bpp] else 0;
            value.* +%= @intCast((left + previous[i]) / 2);
        },
        4 => for (row, 0..) |*value, i| {
            const left: i16 = if (i >= bpp) row[i - bpp] else 0;
            const above: i16 = previous[i];
            const corner: i16 = if (i >= bpp) previous[i - bpp] else 0;
            const p = left + above - corner;
            const pa = @abs(p - left);
            const pb = @abs(p - above);
            const pc = @abs(p - corner);
            const predicted = if (pa <= pb and pa <= pc) left else if (pb <= pc) above else corner;
            value.* +%= @intCast(predicted);
        },
        else => return error.ImageInvalid,
    }
}

/// Sample `index` of a row, as a 16-bit value (samples of fewer bits are not scaled).
fn sample(row: []const u8, depth: u8, index: usize) u16 {
    return switch (depth) {
        16 => std.mem.readInt(u16, row[2 * index ..][0..2], .big),
        8 => row[index],
        else => blk: {
            const per_byte = 8 / depth;
            const byte = row[index / per_byte];
            const shift: u3 = @intCast(8 - depth - (index % per_byte) * depth);
            break :blk (byte >> shift) & ((@as(u16, 1) << @intCast(depth)) - 1);
        },
    };
}

/// A sample as 8 bits.
fn eight(value: u16, depth: u8) u32 {
    return switch (depth) {
        16 => value >> 8,
        8 => value,
        else => @as(u32, value) * 255 / ((@as(u32, 1) << @intCast(depth)) - 1),
    };
}

fn pngPixel(png: Png, row: []const u8, x: usize, transparent: u32) u32 {
    const channels = png.channels();
    const base = x * channels;
    switch (png.color_type) {
        3 => {
            const index = sample(row, png.depth, x);
            if (index >= png.palette_len) return opaque_alpha;
            return if (png.palette_alpha[index] < 128) transparent else png.palette[index];
        },
        0 => {
            const gray = sample(row, png.depth, base);
            if (png.key) |key| if (gray == key[0]) return transparent;
            const g = eight(gray, png.depth);
            return rgb(g, g, g);
        },
        4 => {
            if (eight(sample(row, png.depth, base + 1), png.depth) < 128) return transparent;
            const g = eight(sample(row, png.depth, base), png.depth);
            return rgb(g, g, g);
        },
        2, 6 => {
            const r = sample(row, png.depth, base);
            const g = sample(row, png.depth, base + 1);
            const b = sample(row, png.depth, base + 2);
            if (png.color_type == 6 and eight(sample(row, png.depth, base + 3), png.depth) < 128) return transparent;
            if (png.key) |key| if (r == key[0] and g == key[1] and b == key[2]) return transparent;
            return rgb(eight(r, png.depth), eight(g, png.depth), eight(b, png.depth));
        },
        else => unreachable,
    }
}

// ---- BMP ----------------------------------------------------------------------------

fn readLittle(comptime T: type, bytes: []const u8, at: usize) RuntimeError!T {
    if (at + @sizeOf(T) > bytes.len) return error.ImageInvalid;
    return std.mem.readInt(T, bytes[at..][0..@sizeOf(T)], .little);
}

/// A channel of a BMP bit field: where its lowest bit is and how many bits it has.
const Mask = struct {
    shift: u5 = 0,
    bits: u6 = 0,

    fn of(mask: u32) Mask {
        if (mask == 0) return .{};
        const shift: u5 = @intCast(@ctz(mask));
        return .{ .shift = shift, .bits = @intCast(@popCount(mask)) };
    }

    fn take(mask: Mask, value: u32) u32 {
        if (mask.bits == 0) return 0;
        const raw = (value >> mask.shift) & ((@as(u64, 1) << mask.bits) - 1);
        return @intCast(raw * 255 / ((@as(u64, 1) << mask.bits) - 1));
    }
};

fn decodeBmp(self: *State, file: []u8, transparent: u32) RuntimeError!Cell {
    const pixel_offset = try readLittle(u32, file, 10);
    const header_size = try readLittle(u32, file, 14);
    var width: i64 = undefined;
    var height: i64 = undefined;
    var bits: u16 = undefined;
    var compression: u32 = 0;
    var colors_used: u32 = 0;
    var palette_entry: usize = 4;
    if (header_size == 12) {
        width = try readLittle(u16, file, 18);
        height = try readLittle(i16, file, 20);
        bits = try readLittle(u16, file, 24);
        palette_entry = 3;
    } else if (header_size >= 40) {
        width = try readLittle(i32, file, 18);
        height = try readLittle(i32, file, 22);
        bits = try readLittle(u16, file, 28);
        compression = try readLittle(u32, file, 30);
        colors_used = try readLittle(u32, file, 46);
    } else return error.ImageInvalid;
    // Height below 0: the rows go from the top.
    const top_down = height < 0;
    const rows: u64 = @abs(height);
    if (width <= 0 or rows == 0) return error.ImageInvalid;
    // Larger than an image may be is NUMBER ERROR, as for NEW-IMAGE; checked before the
    // size of the rows is reckoned, which then cannot overflow.
    if (width > graphics_images.max_side or rows > graphics_images.max_side) return error.InvalidNumber;
    var red = Mask{};
    var green = Mask{};
    var blue = Mask{};
    var alpha = Mask{};
    switch (compression) {
        0 => switch (bits) {
            16 => {
                red = Mask.of(0x7c00);
                green = Mask.of(0x03e0);
                blue = Mask.of(0x001f);
            },
            1, 4, 8, 24, 32 => {},
            else => return error.ImageInvalid,
        },
        // BI_BITFIELDS and BI_ALPHABITFIELDS: masks after the 40 bytes of the header (or
        // in it, for the larger headers).
        3, 6 => {
            if (bits != 16 and bits != 32) return error.ImageInvalid;
            red = Mask.of(try readLittle(u32, file, 54));
            green = Mask.of(try readLittle(u32, file, 58));
            blue = Mask.of(try readLittle(u32, file, 62));
            if (compression == 6 or header_size >= 56) alpha = Mask.of(try readLittle(u32, file, 66));
        },
        else => return error.ImageInvalid,
    }
    const stride = (@as(u64, @intCast(width)) * bits + 31) / 32 * 4;
    if (pixel_offset > file.len or stride * rows > file.len - pixel_offset) return error.ImageInvalid;
    var palette: [256]u32 = @splat(opaque_alpha);
    if (bits <= 8) {
        const count: usize = if (colors_used == 0 or colors_used > 256) @as(usize, 1) << @intCast(bits) else colors_used;
        const start = 14 + header_size;
        for (0..count) |i| {
            const at = start + i * palette_entry;
            if (at + 3 > pixel_offset) break;
            palette[i] = rgb(file[at + 2], file[at + 1], file[at]);
        }
    }
    const made = try newImage(self, @intCast(width), rows);
    const w: usize = @intCast(width);
    for (0..@intCast(rows)) |row| {
        const line = file[@intCast(pixel_offset + row * stride)..][0..@intCast(stride)];
        const y = if (top_down) row else @as(usize, @intCast(rows)) - 1 - row;
        const out = made[1].pixels[y * w ..][0..w];
        for (out, 0..) |*pixel, x| {
            pixel.* = switch (bits) {
                1, 4, 8 => palette[sample(line, @intCast(bits), x)],
                24 => rgb(line[3 * x + 2], line[3 * x + 1], line[3 * x]),
                16, 32 => blk: {
                    const value: u32 = if (bits == 16) std.mem.readInt(u16, line[2 * x ..][0..2], .little) else std.mem.readInt(u32, line[4 * x ..][0..4], .little);
                    if (compression == 0 and bits == 32) break :blk rgb(line[4 * x + 2], line[4 * x + 1], line[4 * x]);
                    if (alpha.bits != 0 and alpha.take(value) < 128) break :blk transparent;
                    break :blk rgb(red.take(value), green.take(value), blue.take(value));
                },
                else => unreachable,
            };
        }
    }
    return made[0];
}

// ---- PPM and PGM ----------------------------------------------------------------------

const PnmReader = struct {
    file: []const u8,
    cursor: usize,

    /// The next number of the header or of a plain (ASCII) file, after white space and
    /// comments from # to the end of the line.
    fn number(reader: *PnmReader) RuntimeError!u64 {
        while (reader.cursor < reader.file.len) {
            const byte = reader.file[reader.cursor];
            if (byte == '#') {
                while (reader.cursor < reader.file.len and reader.file[reader.cursor] != '\n') reader.cursor += 1;
            } else if (std.ascii.isWhitespace(byte)) {
                reader.cursor += 1;
            } else break;
        }
        const start = reader.cursor;
        while (reader.cursor < reader.file.len and std.ascii.isDigit(reader.file[reader.cursor])) reader.cursor += 1;
        if (reader.cursor == start) return error.ImageInvalid;
        return std.fmt.parseUnsigned(u64, reader.file[start..reader.cursor], 10) catch error.ImageInvalid;
    }
};

fn decodePnm(self: *State, file: []u8) RuntimeError!Cell {
    const kind = file[1];
    var reader = PnmReader{ .file = file, .cursor = 2 };
    const width = try reader.number();
    const height = try reader.number();
    const max = try reader.number();
    if (max == 0 or max > 65535) return error.ImageInvalid;
    const channels: usize = if (kind == '3' or kind == '6') 3 else 1;
    const binary = kind == '5' or kind == '6';
    const sample_bytes: usize = if (max < 256) 1 else 2;
    if (binary) {
        // One white space byte ends the header.
        if (reader.cursor >= file.len or !std.ascii.isWhitespace(file[reader.cursor])) return error.ImageInvalid;
        reader.cursor += 1;
        if (width > graphics_images.max_side or height > graphics_images.max_side) return error.InvalidNumber;
        if (width * height * channels * sample_bytes > file.len - reader.cursor) return error.ImageInvalid;
    }
    const made = try newImage(self, width, height);
    errdefer graphics_images.freeHandle(self, made[0]);
    for (made[1].pixels) |*pixel| {
        var values: [3]u32 = undefined;
        for (values[0..channels]) |*value| {
            const raw: u64 = if (!binary) try reader.number() else blk: {
                const at = reader.cursor;
                reader.cursor += sample_bytes;
                break :blk if (sample_bytes == 1) file[at] else std.mem.readInt(u16, file[at..][0..2], .big);
            };
            if (raw > max) return error.ImageInvalid;
            value.* = @intCast(raw * 255 / max);
        }
        pixel.* = if (channels == 3) rgb(values[0], values[1], values[2]) else rgb(values[0], values[0], values[0]);
    }
    return made[0];
}
