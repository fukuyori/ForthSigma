//! Showing the graphics image on the terminal: with half block characters and 24-bit
//! color escapes, or as Sixel graphics. An image larger than the terminal is made
//! smaller, keeping its proportions, by averaging the pixels that make each new pixel.

const std = @import("std");
const forth = @import("../forth.zig");
const host_interface = @import("host_interface.zig");
const State = forth.State;
const TerminalSize = host_interface.TerminalSize;

/// The size assumed when the output is not a terminal.
const default_size = TerminalSize{ .columns = 80, .rows = 24 };

/// The pixel size of a character cell assumed for Sixel when the host does not know it.
const assumed_cell_width = 10;
const assumed_cell_height = 20;

/// The widest Sixel image: one band of it is kept in `State.gfx_band`.
pub const max_sixel_width = 4096;

fn terminalSize(self: *State) TerminalSize {
    const size_fn = self.writer.terminal_size_fn orelse return default_size;
    const size = size_fn(self.writer.context) orelse return default_size;
    if (size.columns == 0 or size.rows == 0) return default_size;
    return size;
}

/// The size of the image after making it fit max_width × max_height, keeping its
/// proportions; it is never made larger.
fn fitted(width: u64, height: u64, max_width: u64, max_height: u64) [2]u64 {
    if (width <= max_width and height <= max_height) return .{ width, height };
    if (width * max_height >= height * max_width) return .{ max_width, @max(1, height * max_width / width) };
    return .{ @max(1, width * max_height / height), max_height };
}

/// The image made smaller to out_width × out_height (each at most the image's size).
/// The sides are at most 8192, so their products fit a usize also on 32-bit hosts.
const Scaled = struct {
    self: *const State,
    width: usize,
    height: usize,
    out_width: usize,
    out_height: usize,

    /// The average color (0xRRGGBB) of the pixels that make the new pixel x y.
    fn pixel(scaled: Scaled, x: usize, y: usize) u32 {
        const x0 = x * scaled.width / scaled.out_width;
        const x1 = @max(x0 + 1, (x + 1) * scaled.width / scaled.out_width);
        const y0 = y * scaled.height / scaled.out_height;
        const y1 = @max(y0 + 1, (y + 1) * scaled.height / scaled.out_height);
        var red: u64 = 0;
        var green: u64 = 0;
        var blue: u64 = 0;
        var row = y0;
        while (row < y1) : (row += 1) {
            for (scaled.self.gfx_pixels[row * scaled.width + x0 .. row * scaled.width + x1]) |value| {
                red += (value >> 16) & 0xff;
                green += (value >> 8) & 0xff;
                blue += value & 0xff;
            }
        }
        const count: u64 = (x1 - x0) * (y1 - y0);
        const r: u32 = @intCast((red + count / 2) / count);
        const g: u32 = @intCast((green + count / 2) / count);
        const b: u32 = @intCast((blue + count / 2) / count);
        return (r << 16) | (g << 8) | b;
    }
};

fn scaledImage(self: *const State, max_width: u64, max_height: u64) Scaled {
    const width: usize = @intCast(self.gfx_width);
    const height: usize = @intCast(self.gfx_height);
    const size = fitted(width, height, @max(max_width, 1), @max(max_height, 1));
    return .{ .self = self, .width = width, .height = height, .out_width = @intCast(size[0]), .out_height = @intCast(size[1]) };
}

/// Text to the terminal in pieces of a few kilobytes.
const Output = struct {
    self: *State,
    buffer: [4096]u8 = undefined,
    used: usize = 0,

    fn text(output: *Output, bytes: []const u8) void {
        var rest = bytes;
        while (rest.len != 0) {
            if (output.used == output.buffer.len) output.flush();
            const count = @min(rest.len, output.buffer.len - output.used);
            @memcpy(output.buffer[output.used..][0..count], rest[0..count]);
            output.used += count;
            rest = rest[count..];
        }
    }

    fn number(output: *Output, value: u64) void {
        var digits: [20]u8 = undefined;
        output.text(std.fmt.bufPrint(&digits, "{d}", .{value}) catch unreachable);
    }

    fn flush(output: *Output) void {
        if (output.used == 0) return;
        output.self.write(output.buffer[0..output.used]);
        output.used = 0;
    }
};

/// One character cell for two pixels: the upper half block (U+2580) in the top
/// pixel's color over the bottom pixel's color. The last row of an image with an odd
/// height has the terminal's own background below.
pub fn showBlocks(self: *State) void {
    const size = terminalSize(self);
    // One line is left for the prompt after the image.
    const scaled = scaledImage(self, size.columns, @as(u64, @max(size.rows, 2) - 1) * 2);
    const utf8_fn = self.writer.terminal_utf8_fn;
    if (utf8_fn) |begin| begin(self.writer.context, true);
    defer if (utf8_fn) |end| end(self.writer.context, false);
    var output = Output{ .self = self };
    var row: usize = 0;
    while (row < scaled.out_height) : (row += 2) {
        var foreground: ?u32 = null;
        var background: ?u32 = null;
        var x: usize = 0;
        while (x < scaled.out_width) : (x += 1) {
            const top = scaled.pixel(x, row);
            if (foreground != top) {
                colorEscape(&output, "38", top);
                foreground = top;
            }
            if (row + 1 < scaled.out_height) {
                const bottom = scaled.pixel(x, row + 1);
                if (background != bottom) {
                    colorEscape(&output, "48", bottom);
                    background = bottom;
                }
            } else if (x == 0) output.text("\x1b[49m");
            output.text("\u{2580}");
        }
        output.text("\x1b[0m\n");
    }
    output.flush();
}

fn colorEscape(output: *Output, layer: []const u8, rgb: u32) void {
    output.text("\x1b[");
    output.text(layer);
    output.text(";2;");
    output.number((rgb >> 16) & 0xff);
    output.text(";");
    output.number((rgb >> 8) & 0xff);
    output.text(";");
    output.number(rgb & 0xff);
    output.text("m");
}

/// The register of the 6 × 6 × 6 color cube that a color is nearest to.
fn sixelColor(rgb: u32) u8 {
    const r = (((rgb >> 16) & 0xff) * 5 + 127) / 255;
    const g = (((rgb >> 8) & 0xff) * 5 + 127) / 255;
    const b = ((rgb & 0xff) * 5 + 127) / 255;
    return @intCast(r * 36 + g * 6 + b);
}

/// Sixel graphics: the colors are those of a 6 × 6 × 6 cube, and the image is made to
/// fit the terminal's size in pixels (or 10 × 20 pixels a character when the host does
/// not know it), at most 4096 pixels wide.
pub fn showSixel(self: *State) void {
    const size = terminalSize(self);
    const rows: u64 = @max(size.rows, 2);
    const max_width: u64 = if (size.x_pixels != 0) size.x_pixels else @as(u64, size.columns) * assumed_cell_width;
    const max_height: u64 = if (size.y_pixels != 0) size.y_pixels * (rows - 1) / rows else (rows - 1) * assumed_cell_height;
    const scaled = scaledImage(self, @min(max_width, max_sixel_width), max_height);
    var output = Output{ .self = self };
    output.text("\x1bPq\"1;1;");
    output.number(scaled.out_width);
    output.text(";");
    output.number(scaled.out_height);
    for (0..216) |register| {
        output.text("#");
        output.number(register);
        output.text(";2;");
        output.number(register / 36 * 20);
        output.text(";");
        output.number(register / 6 % 6 * 20);
        output.text(";");
        output.number(register % 6 * 20);
    }
    const band = &self.gfx_band;
    var top: usize = 0;
    while (top < scaled.out_height) : (top += 6) {
        var used: [216]bool = @splat(false);
        for (0..6) |line| {
            const y = top + line;
            for (0..scaled.out_width) |x| {
                if (y >= scaled.out_height) {
                    band[line][x] = 0xff;
                    continue;
                }
                const register = sixelColor(scaled.pixel(x, y));
                band[line][x] = register;
                used[register] = true;
            }
        }
        for (used, 0..) |is_used, register| {
            if (!is_used) continue;
            output.text("#");
            output.number(register);
            var run_char: u8 = 0;
            var run_length: u64 = 0;
            for (0..scaled.out_width) |x| {
                var bits: u8 = 0;
                for (0..6) |line| {
                    if (band[line][x] == register) bits |= @as(u8, 1) << @intCast(line);
                }
                const char = 63 + bits;
                if (char == run_char) {
                    run_length += 1;
                    continue;
                }
                sixelRun(&output, run_char, run_length);
                run_char = char;
                run_length = 1;
            }
            sixelRun(&output, run_char, run_length);
            // Back to the start of the band for the next color.
            output.text("$");
        }
        output.text("-");
    }
    output.text("\x1b\\");
    output.flush();
}

fn sixelRun(output: *Output, char: u8, length: u64) void {
    if (length == 0) return;
    if (length > 3) {
        output.text("!");
        output.number(length);
        output.text(&.{char});
    } else {
        for (0..@as(usize, @intCast(length))) |_| output.text(&.{char});
    }
}
