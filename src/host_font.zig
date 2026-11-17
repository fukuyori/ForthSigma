//! The system's fonts for TEXT (SYSTEM-FONT). On Windows GDI draws one character at a
//! time, white on black and smoothed in shades of gray, into a bitmap in memory, whose
//! green values are the coverage TEXT mixes the current color with. On macOS Core Text
//! draws it into a gray bitmap of Core Graphics; the frameworks are loaded when the
//! program first chooses a font, so that the macOS builds made on Linux need no SDK.
//! Linux has no drawing of text of its own, and the executables given out load no shared
//! library: stb_truetype (src/stb) reads the font file, found by the font's name under
//! the folders the system keeps its fonts in, and draws the glyphs.
//! Other hosts have no system fonts (`available` is false).

const std = @import("std");
const builtin = @import("builtin");
const forth = @import("forth.zig");

pub const available = builtin.os.tag == .windows or builtin.os.tag == .macos or builtin.os.tag == .linux;

/// The host's system_font_fn and system_glyph_fn.
pub const select = if (builtin.os.tag == .windows) gdi.select else if (builtin.os.tag == .macos) coretext.select else if (builtin.os.tag == .linux) truetype.select else unsupportedSelect;
pub const glyph = if (builtin.os.tag == .windows) gdi.glyph else if (builtin.os.tag == .macos) coretext.glyph else if (builtin.os.tag == .linux) truetype.glyph else unsupportedGlyph;

fn unsupportedSelect(_: ?*anyopaque, _: []const u8, _: u32) forth.RuntimeError!bool {
    return error.HostUnavailable;
}

fn unsupportedGlyph(_: ?*anyopaque, _: u21, _: []u8, _: u32) ?forth.SystemGlyph {
    return null;
}

/// Linux: src/stb/sigma_font.c, which the build adds when the graphics words are in.
const truetype = struct {
    extern fn sigma_font_select(name: [*]const u8, name_length: usize, height: c_uint) c_int;
    extern fn sigma_font_glyph(code: c_uint, alpha: [*]u8, alpha_length: usize, max_width: c_uint, out: *[4]c_int) c_int;

    fn select(_: ?*anyopaque, name: []const u8, height: u32) forth.RuntimeError!bool {
        if (name.len == 0) return false;
        return sigma_font_select(name.ptr, name.len, height) == 1;
    }

    fn glyph(_: ?*anyopaque, code: u21, alpha: []u8, max_width: u32) ?forth.SystemGlyph {
        if (code >= 0xD800 and code < 0xE000) return null;
        var out: [4]c_int = undefined;
        if (sigma_font_glyph(code, alpha.ptr, alpha.len, max_width, &out) != 1) return null;
        return .{ .advance = out[0], .left = out[1], .width = @intCast(out[2]), .height = @intCast(out[3]) };
    }
};

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

const coretext = struct {
    const Ref = *anyopaque;
    const Point = extern struct { x: f64, y: f64 };
    const Size = extern struct { width: f64, height: f64 };

    const CFStringCreateWithBytes = *const fn (?Ref, [*]const u8, isize, u32, u8) callconv(.c) ?Ref;
    const CFRelease = *const fn (Ref) callconv(.c) void;
    const CFStringCompare = *const fn (Ref, Ref, u64) callconv(.c) i64;
    const CFArrayGetCount = *const fn (Ref) callconv(.c) isize;
    const CFArrayGetValueAtIndex = *const fn (Ref, isize) callconv(.c) Ref;
    const CTFontCreateWithName = *const fn (Ref, f64, ?*const anyopaque) callconv(.c) ?Ref;
    const CTFontCopyName = *const fn (Ref) callconv(.c) ?Ref;
    const CTFontCopyLocalizedName = *const fn (Ref, Ref, ?*?Ref) callconv(.c) ?Ref;
    const CTFontGetMetric = *const fn (Ref) callconv(.c) f64;
    const CTFontGetGlyphsForCharacters = *const fn (Ref, [*]const u16, [*]u16, isize) callconv(.c) u8;
    const CTFontGetAdvancesForGlyphs = *const fn (Ref, u32, [*]const u16, ?[*]Size, isize) callconv(.c) f64;
    const CTFontDrawGlyphs = *const fn (Ref, [*]const u16, [*]const Point, usize, Ref) callconv(.c) void;
    const CTFontManagerCopyAvailableFontFamilyNames = *const fn () callconv(.c) ?Ref;
    const CGColorSpaceCreateDeviceGray = *const fn () callconv(.c) ?Ref;
    const CGBitmapContextCreate = *const fn (?*anyopaque, usize, usize, usize, usize, Ref, u32) callconv(.c) ?Ref;
    const CGContextSetGrayFillColor = *const fn (Ref, f64, f64) callconv(.c) void;
    const CGContextSetFlag = *const fn (Ref, bool) callconv(.c) void;

    const utf8: u32 = 0x0800_0100; // kCFStringEncodingUTF8
    const bitmap_width = 512;
    const bitmap_height = 256;

    var loaded = false;
    var ok = false;
    var string_create: CFStringCreateWithBytes = undefined;
    var release: CFRelease = undefined;
    var compare: CFStringCompare = undefined;
    var array_count: CFArrayGetCount = undefined;
    var array_at: CFArrayGetValueAtIndex = undefined;
    var create_font: CTFontCreateWithName = undefined;
    var copy_postscript_name: CTFontCopyName = undefined;
    var copy_family_name: CTFontCopyName = undefined;
    var copy_full_name: CTFontCopyName = undefined;
    var copy_localized_name: CTFontCopyLocalizedName = undefined;
    var ascent_of: CTFontGetMetric = undefined;
    var descent_of: CTFontGetMetric = undefined;
    var glyphs_for: CTFontGetGlyphsForCharacters = undefined;
    var advances_for: CTFontGetAdvancesForGlyphs = undefined;
    var draw_glyphs: CTFontDrawGlyphs = undefined;
    var family_names: CTFontManagerCopyAvailableFontFamilyNames = undefined;
    var family_key: Ref = undefined;
    var full_key: Ref = undefined;
    var context: Ref = undefined;
    var pixels: [bitmap_width * bitmap_height]u8 = undefined;

    var font: ?Ref = null;
    /// The font's ascent in pixels: the baseline's row from the top of the line.
    var ascent: f64 = 0;
    var line_height: u32 = 0;

    fn lookup(comptime T: type, lib: *std.DynLib, name: [:0]const u8) ?T {
        return lib.lookup(T, name);
    }

    /// Loads Core Foundation, Core Text, and Core Graphics, and makes the gray bitmap the
    /// glyphs are drawn in; false when they are not there.
    fn load() bool {
        if (loaded) return ok;
        loaded = true;
        var cf = std.DynLib.open("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation") catch return false;
        var ct = std.DynLib.open("/System/Library/Frameworks/CoreText.framework/CoreText") catch return false;
        var cg = std.DynLib.open("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics") catch return false;
        string_create = lookup(CFStringCreateWithBytes, &cf, "CFStringCreateWithBytes") orelse return false;
        release = lookup(CFRelease, &cf, "CFRelease") orelse return false;
        compare = lookup(CFStringCompare, &cf, "CFStringCompare") orelse return false;
        array_count = lookup(CFArrayGetCount, &cf, "CFArrayGetCount") orelse return false;
        array_at = lookup(CFArrayGetValueAtIndex, &cf, "CFArrayGetValueAtIndex") orelse return false;
        create_font = lookup(CTFontCreateWithName, &ct, "CTFontCreateWithName") orelse return false;
        copy_postscript_name = lookup(CTFontCopyName, &ct, "CTFontCopyPostScriptName") orelse return false;
        copy_family_name = lookup(CTFontCopyName, &ct, "CTFontCopyFamilyName") orelse return false;
        copy_full_name = lookup(CTFontCopyName, &ct, "CTFontCopyFullName") orelse return false;
        copy_localized_name = lookup(CTFontCopyLocalizedName, &ct, "CTFontCopyLocalizedName") orelse return false;
        ascent_of = lookup(CTFontGetMetric, &ct, "CTFontGetAscent") orelse return false;
        descent_of = lookup(CTFontGetMetric, &ct, "CTFontGetDescent") orelse return false;
        glyphs_for = lookup(CTFontGetGlyphsForCharacters, &ct, "CTFontGetGlyphsForCharacters") orelse return false;
        advances_for = lookup(CTFontGetAdvancesForGlyphs, &ct, "CTFontGetAdvancesForGlyphs") orelse return false;
        draw_glyphs = lookup(CTFontDrawGlyphs, &ct, "CTFontDrawGlyphs") orelse return false;
        family_names = lookup(CTFontManagerCopyAvailableFontFamilyNames, &ct, "CTFontManagerCopyAvailableFontFamilyNames") orelse return false;
        family_key = (lookup(*const Ref, &ct, "kCTFontFamilyNameKey") orelse return false).*;
        full_key = (lookup(*const Ref, &ct, "kCTFontFullNameKey") orelse return false).*;
        const gray = (lookup(CGColorSpaceCreateDeviceGray, &cg, "CGColorSpaceCreateDeviceGray") orelse return false)() orelse return false;
        const bitmap_create = lookup(CGBitmapContextCreate, &cg, "CGBitmapContextCreate") orelse return false;
        // 8 bits of gray, no alpha (kCGImageAlphaNone); rows from the top in memory.
        context = bitmap_create(&pixels, bitmap_width, bitmap_height, 8, bitmap_width, gray, 0) orelse return false;
        (lookup(CGContextSetGrayFillColor, &cg, "CGContextSetGrayFillColor") orelse return false)(context, 1, 1);
        // Shades of gray, not the colored subpixels of LCD smoothing.
        (lookup(CGContextSetFlag, &cg, "CGContextSetShouldAntialias") orelse return false)(context, true);
        (lookup(CGContextSetFlag, &cg, "CGContextSetShouldSmoothFonts") orelse return false)(context, false);
        ok = true;
        return true;
    }

    fn string(text: []const u8) ?Ref {
        return string_create(null, text.ptr, @intCast(text.len), utf8, 0);
    }

    fn sameName(name: Ref, found: ?Ref) bool {
        const other = found orelse return false;
        defer release(other);
        return compare(name, other, 0) == 0;
    }

    /// Whether the font is the one the name asks for: Core Text gives some font for any
    /// name, so the name must be one of the font's own (PostScript, family, or full
    /// name, also as the user's language shows them).
    fn named(candidate: Ref, name: Ref) bool {
        return sameName(name, copy_postscript_name(candidate)) or sameName(name, copy_family_name(candidate)) or
            sameName(name, copy_full_name(candidate)) or sameName(name, copy_localized_name(candidate, family_key, null)) or
            sameName(name, copy_localized_name(candidate, full_key, null));
    }

    /// The font of that name: directly, or by the families' names in the user's language
    /// (ヒラギノ角ゴシック for Hiragino Sans).
    fn find(name: Ref) ?Ref {
        if (create_font(name, 12, null)) |direct| {
            if (named(direct, name)) return direct;
            release(direct);
        }
        const families = family_names() orelse return null;
        defer release(families);
        var i: isize = 0;
        while (i < array_count(families)) : (i += 1) {
            const candidate = create_font(array_at(families, i), 12, null) orelse continue;
            if (named(candidate, name)) return candidate;
            release(candidate);
        }
        return null;
    }

    fn select(_: ?*anyopaque, name: []const u8, height: u32) forth.RuntimeError!bool {
        if (!load()) return error.HostFailed;
        if (name.len == 0) return false;
        const wanted = string(name) orelse return error.HostFailed;
        defer release(wanted);
        const sample = find(wanted) orelse return false;
        defer release(sample);
        // The size whose ascent and descent take `height` pixels, as GDI's height does.
        const unit = ascent_of(sample) + descent_of(sample);
        if (!(unit > 0)) return false;
        const size = 12 * @as(f64, @floatFromInt(height)) / unit;
        const postscript = copy_postscript_name(sample) orelse return error.HostFailed;
        defer release(postscript);
        const created = create_font(postscript, size, null) orelse return error.HostFailed;
        if (font) |old| release(old);
        font = created;
        ascent = ascent_of(created);
        line_height = @min(height, bitmap_height);
        return true;
    }

    fn glyph(_: ?*anyopaque, code: u21, alpha: []u8, max_width: u32) ?forth.SystemGlyph {
        const current = font orelse return null;
        if (code >= 0xD800 and code < 0xE000) return null;
        var units: [2]u16 = undefined;
        var count: usize = 1;
        if (code >= 0x10000) {
            const value = code - 0x10000;
            units = .{ @intCast(0xD800 + (value >> 10)), @intCast(0xDC00 + (value & 0x3FF)) };
            count = 2;
        } else {
            units[0] = @intCast(code);
        }
        var glyphs: [2]u16 = .{ 0, 0 };
        // False when the font has no glyph for the character: TEXT draws ? instead, as
        // with GDI, rather than a glyph of another font.
        if (glyphs_for(current, &units, &glyphs, @intCast(count)) == 0 or glyphs[0] == 0) return null;
        const advance = advances_for(current, 0, &glyphs, null, 1);
        const height = line_height;
        // Room on both sides for strokes past the advance (italics, accents).
        const margin: u32 = height / 2;
        const width: u32 = @min(@as(u32, @intFromFloat(@max(@ceil(advance), 0))) + 2 * margin, max_width, bitmap_width);
        if (alpha.len < @as(usize, width) * height) return null;
        for (0..height) |row| @memset(pixels[row * bitmap_width ..][0..width], 0);
        // Core Graphics counts y from the bottom of the bitmap; the line is its top rows.
        const position = [1]Point{.{ .x = @floatFromInt(margin), .y = @as(f64, @floatFromInt(bitmap_height)) - ascent }};
        draw_glyphs(current, &glyphs, &position, 1, context);
        for (0..height) |row| @memcpy(alpha[row * width ..][0..width], pixels[row * bitmap_width ..][0..width]);
        return .{ .advance = @intFromFloat(@round(advance)), .left = -@as(i32, @intCast(margin)), .width = width, .height = height };
    }
};

test "a font of macOS: chosen by its names, drawn in gray, and no glyph for a character it lacks" {
    if (builtin.os.tag != .macos) return error.SkipZigTest;
    try std.testing.expect(!try select(null, "No Such Font Name", 16));
    try std.testing.expect(try select(null, "Helvetica", 16));
    var alpha: [512 * 256]u8 = undefined;
    const a = glyph(null, 'A', &alpha, 512) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(u32, 16), a.height);
    try std.testing.expect(a.advance > 4 and a.advance < 16);
    var ink: usize = 0;
    var gray = false;
    for (alpha[0 .. a.width * a.height]) |value| {
        if (value != 0) ink += 1;
        if (value != 0 and value != 255) gray = true;
    }
    try std.testing.expect(ink > 10 and gray);
    // Helvetica has no kanji; Hiragino Sans has, also by its PostScript name.
    try std.testing.expect(glyph(null, 0x65E5, &alpha, 512) == null);
    try std.testing.expect(try select(null, "HiraginoSans-W3", 24));
    const kanji = glyph(null, 0x65E5, &alpha, 512) orelse return error.TestUnexpectedResult;
    try std.testing.expect(kanji.advance >= 20 and kanji.advance <= 26);
}

test "a font of Linux: chosen by its name or its path, drawn in gray, and no glyph for a character it lacks" {
    // Without the graphics words the build leaves src/stb out, and nothing may call it.
    if (builtin.os.tag != .linux or !@import("build_options").graphics) return error.SkipZigTest;
    try std.testing.expect(!try select(null, "No Such Font Name", 16));
    try std.testing.expect(!try select(null, "/no/such/font.ttf", 16));
    // The fonts a system has differ; without DejaVu Sans there is nothing to compare.
    if (!try select(null, "DejaVu Sans", 16)) return error.SkipZigTest;
    var alpha: [512 * 256]u8 = undefined;
    const a = glyph(null, 'A', &alpha, 512) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(u32, 16), a.height);
    try std.testing.expect(a.advance > 4 and a.advance < 16);
    var ink: usize = 0;
    var gray = false;
    for (alpha[0 .. a.width * a.height]) |value| {
        if (value != 0) ink += 1;
        if (value != 0 and value != 255) gray = true;
    }
    try std.testing.expect(ink > 10 and gray);
    // DejaVu Sans has no kanji; the names are found without regard to the letters' case.
    try std.testing.expect(glyph(null, 0x65E5, &alpha, 512) == null);
    try std.testing.expect(try select(null, "dejavu sans", 24));
    const larger = glyph(null, 'A', &alpha, 512) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(u32, 24), larger.height);
    try std.testing.expect(larger.advance > a.advance);
}
