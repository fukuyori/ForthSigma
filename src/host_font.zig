//! The system's fonts for TEXT on Windows (SYSTEM-FONT): GDI draws one character at a
//! time, white on black and smoothed in shades of gray, into a bitmap in memory, whose
//! green values are the coverage TEXT mixes the current color with. Other hosts have no
//! system fonts (`available` is false).

const std = @import("std");
const builtin = @import("builtin");
const forth = @import("forth.zig");

pub const available = builtin.os.tag == .windows;

/// The host's system_font_fn and system_glyph_fn.
pub const select = if (available) gdi.select else unsupportedSelect;
pub const glyph = if (available) gdi.glyph else unsupportedGlyph;

fn unsupportedSelect(_: ?*anyopaque, _: []const u8, _: u32) forth.RuntimeError!bool {
    return error.HostUnavailable;
}

fn unsupportedGlyph(_: ?*anyopaque, _: u21, _: []u8, _: u32) ?forth.SystemGlyph {
    return null;
}

const gdi = struct {
    const Handle = *anyopaque;
    const LogFont = extern struct {
        height: i32 = 0,
        width: i32 = 0,
        escapement: i32 = 0,
        orientation: i32 = 0,
        weight: i32 = 400,
        italic: u8 = 0,
        underline: u8 = 0,
        strike_out: u8 = 0,
        char_set: u8 = 1, // DEFAULT_CHARSET
        out_precision: u8 = 0,
        clip_precision: u8 = 0,
        quality: u8 = 4, // ANTIALIASED_QUALITY: shades of gray, not ClearType's colors
        pitch_and_family: u8 = 0,
        face_name: [32]u16 = @splat(0),
    };
    const Size = extern struct { cx: i32, cy: i32 };
    const BitmapInfoHeader = extern struct {
        size: u32 = @sizeOf(BitmapInfoHeader),
        width: i32,
        height: i32,
        planes: u16 = 1,
        bit_count: u16 = 32,
        compression: u32 = 0,
        size_image: u32 = 0,
        x_pels_per_meter: i32 = 0,
        y_pels_per_meter: i32 = 0,
        colors_used: u32 = 0,
        colors_important: u32 = 0,
    };
    const BitmapInfo = extern struct { header: BitmapInfoHeader, colors: [1]u32 = .{0} };
    const EnumProc = *const fn (*const LogFont, ?*const anyopaque, u32, isize) callconv(.winapi) i32;

    extern "gdi32" fn CreateCompatibleDC(?Handle) callconv(.winapi) ?Handle;
    extern "gdi32" fn CreateDIBSection(?Handle, *const BitmapInfo, u32, *?[*]u8, ?Handle, u32) callconv(.winapi) ?Handle;
    extern "gdi32" fn SelectObject(Handle, Handle) callconv(.winapi) ?Handle;
    extern "gdi32" fn DeleteObject(Handle) callconv(.winapi) i32;
    extern "gdi32" fn DeleteDC(Handle) callconv(.winapi) i32;
    extern "gdi32" fn CreateFontIndirectW(*const LogFont) callconv(.winapi) ?Handle;
    extern "gdi32" fn EnumFontFamiliesExW(Handle, *const LogFont, EnumProc, isize, u32) callconv(.winapi) i32;
    extern "gdi32" fn SetTextColor(Handle, u32) callconv(.winapi) u32;
    extern "gdi32" fn SetBkColor(Handle, u32) callconv(.winapi) u32;
    extern "gdi32" fn SetBkMode(Handle, i32) callconv(.winapi) i32;
    extern "gdi32" fn TextOutW(Handle, i32, i32, [*]const u16, i32) callconv(.winapi) i32;
    extern "gdi32" fn GetTextExtentPoint32W(Handle, [*]const u16, i32, *Size) callconv(.winapi) i32;
    extern "gdi32" fn GetGlyphIndicesW(Handle, [*]const u16, i32, [*]u16, u32) callconv(.winapi) u32;
    extern "gdi32" fn GdiFlush() callconv(.winapi) i32;

    /// The bitmap GDI draws in: wide enough for the widest box TEXT takes, as high as
    /// the highest font, rows from the top.
    const bitmap_width = 512;
    const bitmap_height = 256;
    const mark_missing: u32 = 1; // GGI_MARK_NONEXISTING_GLYPHS
    const missing_glyph: u16 = 0xFFFF;
    const gdi_error: u32 = 0xFFFF_FFFF;

    var dc: ?Handle = null;
    var bits: ?[*]u8 = null;
    var font: ?Handle = null;

    fn setUp() bool {
        if (dc != null) return true;
        const memory = CreateCompatibleDC(null) orelse return false;
        const info = BitmapInfo{ .header = .{ .width = bitmap_width, .height = -bitmap_height } };
        var pixels: ?[*]u8 = null;
        const bitmap = CreateDIBSection(memory, &info, 0, &pixels, null, 0) orelse {
            _ = DeleteDC(memory);
            return false;
        };
        if (SelectObject(memory, bitmap) == null) {
            _ = DeleteObject(bitmap);
            _ = DeleteDC(memory);
            return false;
        }
        _ = SetTextColor(memory, 0x00FF_FFFF);
        _ = SetBkColor(memory, 0);
        _ = SetBkMode(memory, 2); // OPAQUE
        dc = memory;
        bits = pixels;
        return true;
    }

    fn found(_: *const LogFont, _: ?*const anyopaque, _: u32, result: isize) callconv(.winapi) i32 {
        const flag: *bool = @ptrFromInt(@as(usize, @bitCast(result)));
        flag.* = true;
        return 0;
    }

    fn select(_: ?*anyopaque, name: []const u8, height: u32) forth.RuntimeError!bool {
        if (!setUp()) return error.HostFailed;
        var logical = LogFont{ .height = @intCast(height) };
        // A face name has at most 31 UTF-16 units.
        const length = std.unicode.utf8ToUtf16Le(&logical.face_name, name) catch return false;
        if (length == 0 or length > 31) return false;
        logical.face_name[length] = 0;
        // CreateFont gives some font for any name, so the name is looked up first.
        var exists = false;
        _ = EnumFontFamiliesExW(dc.?, &logical, found, @bitCast(@intFromPtr(&exists)), 0);
        if (!exists) return false;
        const created = CreateFontIndirectW(&logical) orelse return error.HostFailed;
        if (SelectObject(dc.?, created) == null) {
            _ = DeleteObject(created);
            return error.HostFailed;
        }
        if (font) |old| _ = DeleteObject(old);
        font = created;
        return true;
    }

    fn glyph(_: ?*anyopaque, code: u21, alpha: []u8, max_width: u32) ?forth.SystemGlyph {
        const memory = dc orelse return null;
        if (font == null) return null;
        // GetGlyphIndicesW tells whether the font has a glyph only for the characters of
        // one UTF-16 unit; the others (U+10000 and up) are taken as missing (drawn as ?),
        // rather than as whatever glyph GDI would put in their place.
        if (code >= 0x10000 or (code >= 0xD800 and code < 0xE000)) return null;
        var units = [1]u16{@intCast(code)};
        const count: i32 = 1;
        var index: [1]u16 = undefined;
        if (GetGlyphIndicesW(memory, &units, 1, &index, mark_missing) == gdi_error or index[0] == missing_glyph) return null;
        var size: Size = undefined;
        if (GetTextExtentPoint32W(memory, &units, count, &size) == 0) return null;
        // Room on both sides for strokes past the advance (italics, accents).
        const height: u32 = @intCast(std.math.clamp(size.cy, 1, bitmap_height));
        const margin: u32 = height / 2;
        const width: u32 = @min(@as(u32, @intCast(@max(size.cx, 0))) + 2 * margin, max_width, bitmap_width);
        const pixels = bits.?;
        for (0..height) |row| @memset(pixels[row * bitmap_width * 4 ..][0 .. width * 4], 0);
        if (TextOutW(memory, @intCast(margin), 0, &units, count) == 0) return null;
        _ = GdiFlush();
        if (alpha.len < @as(usize, width) * height) return null;
        for (0..height) |row| {
            for (0..width) |column| {
                // Blue, green, red, unused: white text gives the same value in each.
                alpha[row * width + column] = pixels[(row * bitmap_width + column) * 4 + 1];
            }
        }
        return .{ .advance = size.cx, .left = -@as(i32, @intCast(margin)), .width = width, .height = height };
    }
};
