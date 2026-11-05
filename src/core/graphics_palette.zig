//! The colors SHOW uses (DISPLAY-COLORS): full color, or a palette of 2, 16, or 256
//! colors for terminals and displays that show fewer, with each pixel the nearest color
//! of the palette or, with DITHER, mixed by a 4 × 4 Bayer matrix. The image keeps its
//! 24-bit colors; only what SHOW shows changes.
//!
//! The palettes are those of the terminals' color escapes: 2 is black and white by
//! brightness, 16 the 16 ANSI colors (as xterm shows them by default; other terminals
//! may show them differently), and 256 the 6 × 6 × 6 cube and the 24 grays of xterm's
//! 256 colors (16 to 255; the first 16 are left out because terminals differ in them).

/// The colors SHOW uses: 0 (full color), 2, 16, or 256, and whether it dithers.
pub const ColorMode = struct { colors: u16 = 0, dither: bool = false };

pub fn validColors(colors: i64) bool {
    return colors == 0 or colors == 2 or colors == 16 or colors == 256;
}

/// xterm's default colors for the 16 ANSI colors.
pub const ansi = [16]u32{
    0x000000, 0xcd0000, 0x00cd00, 0xcdcd00, 0x0000ee, 0xcd00cd, 0x00cdcd, 0xe5e5e5,
    0x7f7f7f, 0xff0000, 0x00ff00, 0xffff00, 0x5c5cff, 0xff00ff, 0x00ffff, 0xffffff,
};

const cube_levels = [6]u32{ 0, 95, 135, 175, 215, 255 };

const bayer = [4][4]u8{ .{ 0, 8, 2, 10 }, .{ 12, 4, 14, 6 }, .{ 3, 11, 1, 9 }, .{ 15, 7, 13, 5 } };

/// The color of a palette index: 0 to 15 the ANSI colors, 16 to 255 xterm's cube and
/// grays.
pub fn paletteColor(index: u8) u32 {
    if (index < 16) return ansi[index];
    if (index >= 232) {
        const gray: u32 = 8 + 10 * @as(u32, index - 232);
        return gray << 16 | gray << 8 | gray;
    }
    const cube = index - 16;
    return cube_levels[cube / 36] << 16 | cube_levels[cube / 6 % 6] << 8 | cube_levels[cube % 6];
}

fn channel(rgb: u32, shift: u5) i32 {
    return @intCast((rgb >> shift) & 0xff);
}

fn distance(a: u32, b: u32) i32 {
    const dr = channel(a, 16) - channel(b, 16);
    const dg = channel(a, 8) - channel(b, 8);
    const db = channel(a, 0) - channel(b, 0);
    return dr * dr + dg * dg + db * db;
}

/// The offset the Bayer matrix gives at x y, from about -spread/2 to spread/2.
fn offset(x: usize, y: usize, spread: i32) i32 {
    const value: i32 = bayer[y % 4][x % 4];
    return @divFloor((2 * value + 1) * spread, 32) - @divFloor(spread, 2);
}

fn clampChannel(value: i32) u32 {
    return @intCast(@min(@max(value, 0), 255));
}

/// The color with `amount` added to each channel, kept within 0 to 255.
fn shifted(rgb: u32, amount: i32) u32 {
    return clampChannel(channel(rgb, 16) + amount) << 16 | clampChannel(channel(rgb, 8) + amount) << 8 | clampChannel(channel(rgb, 0) + amount);
}

fn nearestLevel(value: i32) u32 {
    var best: u32 = 0;
    for (cube_levels, 0..) |level, index| {
        if (@abs(value - @as(i32, @intCast(level))) < @abs(value - @as(i32, @intCast(cube_levels[best])))) best = @intCast(index);
    }
    return best;
}

fn nearest256(rgb: u32) u8 {
    const r = nearestLevel(channel(rgb, 16));
    const g = nearestLevel(channel(rgb, 8));
    const b = nearestLevel(channel(rgb, 0));
    const cube: u8 = @intCast(16 + 36 * r + 6 * g + b);
    const average = @divTrunc(channel(rgb, 16) + channel(rgb, 8) + channel(rgb, 0), 3);
    const step: i32 = @min(@max(@divTrunc(average - 3, 10), 0), 23);
    const gray: u8 = @intCast(232 + step);
    return if (distance(rgb, paletteColor(gray)) < distance(rgb, paletteColor(cube))) gray else cube;
}

fn nearest16(rgb: u32) u8 {
    var best: u8 = 0;
    for (ansi, 0..) |color, index| {
        if (distance(rgb, color) < distance(rgb, ansi[best])) best = @intCast(index);
    }
    return best;
}

/// The palette index a pixel at x y of the output shows: black 0 or white 15 for 2
/// colors, 0 to 15 for 16, and 16 to 255 for 256. Not for full color.
pub fn paletteIndex(mode: ColorMode, x: usize, y: usize, rgb: u32) u8 {
    switch (mode.colors) {
        2 => {
            // Brightness as television weighs it.
            const brightness = @divTrunc(299 * channel(rgb, 16) + 587 * channel(rgb, 8) + 114 * channel(rgb, 0), 1000);
            const threshold: i32 = if (mode.dither) @divTrunc((2 * @as(i32, bayer[y % 4][x % 4]) + 1) * 255, 32) else 128;
            return if (brightness >= threshold) 15 else 0;
        },
        16 => return nearest16(if (mode.dither) shifted(rgb, offset(x, y, 128)) else rgb),
        else => return nearest256(if (mode.dither) shifted(rgb, offset(x, y, 40)) else rgb),
    }
}

/// The color a pixel at x y of the output shows, 0xRRGGBB.
pub fn convert(mode: ColorMode, x: usize, y: usize, rgb: u32) u32 {
    if (mode.colors == 0) return rgb & 0xffffff;
    return paletteColor(paletteIndex(mode, x, y, rgb));
}
