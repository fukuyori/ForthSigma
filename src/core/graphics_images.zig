//! The images of the pool: off-screen images that NEW-IMAGE makes outside logical
//! memory, the image the drawing words draw on (DRAW-TO), and copying a rectangle from
//! one image to the one drawn on (COPY-RECT), with a transparent color and flipping.
//!
//! An image is named by a handle, one cell: its generation times 65536 plus its place in
//! the table, counted from 1. 0 is the screen (the image of GFX-INIT). A place is used
//! again after FREE-IMAGE with the next generation, so that an old handle does not name
//! the new image. The host gives and frees the pixels (image_alloc_fn, image_free_fn);
//! images are not part of the dictionary, and restoring an image frees them all.

const std = @import("std");
const defs = @import("defs.zig");
const forth = @import("../forth.zig");
const memory_map = @import("memory_map.zig");
const words_graphics = @import("words_graphics.zig");
const Builtin = defs.Builtin;
const Cell = memory_map.Cell;
const RuntimeError = defs.RuntimeError;
const State = forth.State;

pub const words = [_]Builtin{ .gfx_image_new, .gfx_image_free, .gfx_image_size, .gfx_target, .gfx_target_query, .gfx_copy, .gfx_image_load, .gfx_pixel, .gfx_tilemap, .gfx_indexed, .gfx_row_shift, .gfx_row_color };

pub const max_side = words_graphics.max_side;

/// At most this many images, and this many bytes of them in all; the screen is not counted.
pub const max_images = 256;
pub const max_total_bytes = 1 << 30;

/// The handle of the screen.
pub const screen: Cell = 0;

const rgb_mask: u32 = 0x00ff_ffff;
const opaque_black: u32 = 0xff00_0000;

/// One place of the table: empty when `pixels` is.
pub const Slot = struct {
    pixels: []u32 = &.{},
    width: usize = 0,
    height: usize = 0,
    generation: u16 = 0,
    /// CLIP! for this image; null for the whole of it.
    clip: ?Clip = null,
};

/// CLIP! (tque 1044): the part of an image the drawing words draw in, the columns x0 up
/// to x1 and the rows y0 up to y1 (x1 and y1 not included), inside the image. It may be
/// empty: then nothing is drawn.
pub const Clip = struct {
    x0: usize,
    y0: usize,
    x1: usize,
    y1: usize,

    /// The part of the rectangle x y w h (w and h not negative) that is inside an image
    /// of this size.
    pub fn of(x: Cell, y: Cell, w: Cell, h: Cell, width: usize, height: usize) Clip {
        const x0: i128 = std.math.clamp(@as(i128, x), 0, width);
        const y0: i128 = std.math.clamp(@as(i128, y), 0, height);
        const x1: i128 = std.math.clamp(@as(i128, x) + w, x0, width);
        const y1: i128 = std.math.clamp(@as(i128, y) + h, y0, height);
        return .{ .x0 = @intCast(x0), .y0 = @intCast(y0), .x1 = @intCast(x1), .y1 = @intCast(y1) };
    }
};

/// An image to draw on or to copy from: the screen or an image of the pool.
pub const Canvas = struct {
    pixels: []u32,
    width: usize,
    height: usize,
    /// Where the drawing words may draw: set for the image drawn on (`target`), null
    /// (the whole image) for an image that is only read.
    clip: ?Clip = null,

    /// The place of pixel x y, or null outside the image.
    pub fn index(canvas: Canvas, x: Cell, y: Cell) ?usize {
        if (x < 0 or y < 0 or x >= canvas.width or y >= canvas.height) return null;
        return @as(usize, @intCast(y)) * canvas.width + @as(usize, @intCast(x));
    }

    /// The part that may be drawn in: the one CLIP! set, kept inside the image, or the whole image.
    pub fn bounds(canvas: Canvas) Clip {
        const clip = canvas.clip orelse return .{ .x0 = 0, .y0 = 0, .x1 = canvas.width, .y1 = canvas.height };
        const x1 = @min(clip.x1, canvas.width);
        const y1 = @min(clip.y1, canvas.height);
        return .{ .x0 = @min(clip.x0, x1), .y0 = @min(clip.y0, y1), .x1 = x1, .y1 = y1 };
    }

    /// The place of pixel x y for drawing, or null outside the part that may be drawn in.
    pub fn drawIndex(canvas: Canvas, x: Cell, y: Cell) ?usize {
        const b = canvas.bounds();
        if (x < 0 or y < 0 or x < b.x0 or x >= b.x1 or y < b.y0 or y >= b.y1) return null;
        return @as(usize, @intCast(y)) * canvas.width + @as(usize, @intCast(x));
    }
};

/// `range` for the image drawn on: the places p with `to_start + p` inside the columns
/// (or rows) `low` up to `high` that may be drawn in.
fn clippedRange(size: Cell, scale: i128, to_start: Cell, low: usize, high: usize, from_start: Cell, from_size: usize, flipped: bool) ?Span {
    if (low >= high) return null;
    // `range` reckons from 0: move the start left by `low`, in 128 bits, as a scaled
    // rectangle that starts at the smallest cell still reaches the image.
    return range(size, scale, @as(i128, to_start) - low, high - low, from_start, from_size, flipped);
}

pub fn execute(self: *State, builtin: Builtin) RuntimeError!void {
    switch (builtin) {
        .gfx_image_new => {
            const height = try self.pop();
            const width = try self.pop();
            try self.push(try newImage(self, width, height));
        },
        .gfx_image_free => try freeImage(self, try self.pop()),
        .gfx_image_size => {
            const handle = try self.pop();
            const size = try imageSize(self, handle);
            try self.push(@intCast(size[0]));
            try self.push(@intCast(size[1]));
        },
        .gfx_target => {
            const handle = try self.pop();
            if (handle != screen) _ = try slotOf(self, handle);
            self.gfx_target = handle;
        },
        .gfx_target_query => try self.push(self.gfx_target),
        .gfx_copy => {
            var style: Style = undefined;
            style.scale = try self.pop();
            style.alpha = try self.pop();
            style.mode = try self.pop();
            style.flip = try self.pop();
            style.key = try self.pop();
            const dy = try self.pop();
            const dx = try self.pop();
            const h = try self.pop();
            const w = try self.pop();
            const sy = try self.pop();
            const sx = try self.pop();
            const source = try self.pop();
            try copyRect(self, source, sx, sy, w, h, dx, dy, style);
        },
        .gfx_image_load => {
            const key = try self.pop();
            const name = try self.memoryRange();
            for (try @import("graphics_decode.zig").loadImage(self, name, key, false)) |value| try self.push(value);
        },
        // GFX-IMAGE-LOAD-ALPHA ( c-addr u -- img ior ): as GFX-IMAGE-LOAD, with the
        // file's alpha kept in the image's pixels.
        .gfx_image_load_alpha => {
            const name = try self.memoryRange();
            for (try @import("graphics_decode.zig").loadImage(self, name, -1, true)) |value| try self.push(value);
        },
        .gfx_pixel => {
            const y = try self.pop();
            const x = try self.pop();
            const canvas = try canvasOf(self, try self.pop());
            const index = canvas.index(x, y) orelse return self.push(-1);
            try self.push(canvas.pixels[index] & rgb_mask);
        },
        .gfx_tilemap => {
            var view: [13]Cell = undefined;
            var at: usize = view.len;
            while (at > 0) {
                at -= 1;
                view[at] = try self.pop();
            }
            try drawTilemap(self, view);
        },
        .gfx_indexed => {
            var args: [7]Cell = undefined;
            var at: usize = args.len;
            while (at > 0) {
                at -= 1;
                args[at] = try self.pop();
            }
            try drawIndexed(self, args);
        },
        .gfx_rgb => {
            var args: [7]Cell = undefined;
            var at: usize = args.len;
            while (at > 0) {
                at -= 1;
                args[at] = try self.pop();
            }
            try drawRgb(self, args);
        },
        .gfx_row_shift, .gfx_row_color => {
            const h = try self.pop();
            const w = try self.pop();
            const y = try self.pop();
            const x = try self.pop();
            const color: ?Cell = if (builtin == .gfx_row_color) try self.pop() else null;
            const table = try self.pop();
            try rowEffect(self, table, color, x, y, w, h);
        },
        else => unreachable,
    }
}

fn handleOf(place: usize, generation: u16) Cell {
    return @as(Cell, generation) * 65536 + @as(Cell, @intCast(place + 1));
}

/// The place of a handle of the pool, or INVALID IMAGE HANDLE.
fn slotOf(self: *State, handle: Cell) RuntimeError!*Slot {
    if (handle <= 0 or handle > 0xffff_ffff) return error.InvalidImageHandle;
    const place: usize = @intCast(handle & 0xffff);
    const generation: u16 = @intCast(handle >> 16);
    if (place == 0 or place > max_images) return error.InvalidImageHandle;
    const slot = &self.gfx_images[place - 1];
    if (slot.pixels.len == 0 or slot.generation != generation) return error.InvalidImageHandle;
    return slot;
}

/// The screen as a canvas, or NO GRAPHICS IMAGE before GFX-INIT.
pub fn screenCanvas(self: *State) RuntimeError!Canvas {
    if (self.gfx_pixels.len == 0) return error.NoCanvas;
    return .{ .pixels = self.gfx_pixels, .width = @intCast(self.gfx_width), .height = @intCast(self.gfx_height) };
}

/// The image a handle names.
pub fn canvasOf(self: *State, handle: Cell) RuntimeError!Canvas {
    if (handle == screen) return screenCanvas(self);
    const slot = try slotOf(self, handle);
    return .{ .pixels = slot.pixels, .width = slot.width, .height = slot.height };
}

/// The image the drawing words draw on, with the part of it CLIP! lets them draw in.
pub fn target(self: *State) RuntimeError!Canvas {
    var canvas = try canvasOf(self, self.gfx_target);
    canvas.clip = if (self.gfx_target == screen) self.gfx_clip else (try slotOf(self, self.gfx_target)).clip;
    return canvas;
}

/// GFX-ALPHA-PSET ( x y a -- ): gives pixel x y of the image drawn on the alpha a (0 to 255),
/// its color staying; nothing outside the part that may be drawn in. The screen has no
/// alpha to set: INVALID IMAGE HANDLE.
pub fn setAlpha(self: *State, x: Cell, y: Cell, a: Cell) RuntimeError!void {
    if (a < 0 or a > 255) return error.InvalidNumber;
    if (self.gfx_target == screen) return error.InvalidImageHandle;
    const canvas = try target(self);
    if (canvas.drawIndex(x, y)) |index| canvas.pixels[index] = (@as(u32, @intCast(a)) << 24) | (canvas.pixels[index] & rgb_mask);
}

/// GFX-ALPHA-CLS ( a -- ): gives every pixel of the part of the image drawn on that may
/// be drawn in the alpha a, their colors staying. Not for the screen, as setAlpha.
pub fn fillAlpha(self: *State, a: Cell) RuntimeError!void {
    if (a < 0 or a > 255) return error.InvalidNumber;
    if (self.gfx_target == screen) return error.InvalidImageHandle;
    const canvas = try target(self);
    const part = canvas.bounds();
    if (part.x0 >= part.x1) return;
    const alpha = @as(u32, @intCast(a)) << 24;
    for (part.y0..part.y1) |row| {
        for (canvas.pixels[row * canvas.width + part.x0 .. row * canvas.width + part.x1]) |*pixel| pixel.* = alpha | (pixel.* & rgb_mask);
    }
}

/// CLIP! for the image drawn on: the part of x y w h inside it. Negative sizes are refused.
pub fn setClip(self: *State, x: Cell, y: Cell, w: Cell, h: Cell) RuntimeError!void {
    if (w < 0 or h < 0) return error.InvalidNumber;
    const canvas = try canvasOf(self, self.gfx_target);
    const clip = Clip.of(x, y, w, h, canvas.width, canvas.height);
    // The whole image is no clip: so it stays the whole when nothing else is asked.
    const whole = clip.x0 == 0 and clip.y0 == 0 and clip.x1 == canvas.width and clip.y1 == canvas.height;
    const kept: ?Clip = if (whole) null else clip;
    if (self.gfx_target == screen) self.gfx_clip = kept else (try slotOf(self, self.gfx_target)).clip = kept;
}

/// The width and height of an image; 0 0 for the screen before GFX-INIT, as GFX-WIDTH
/// and GFX-HEIGHT give.
pub fn imageSize(self: *State, handle: Cell) RuntimeError![2]usize {
    if (handle == screen) return .{ @intCast(self.gfx_width), @intCast(self.gfx_height) };
    const slot = try slotOf(self, handle);
    return .{ slot.width, slot.height };
}

/// Makes a black image of the pool, as NEW-IMAGE does, and returns its handle.
pub fn createImage(self: *State, width: Cell, height: Cell) RuntimeError!Cell {
    return newImage(self, width, height);
}

/// Frees an image that was just made, when filling it failed.
pub fn freeHandle(self: *State, handle: Cell) void {
    freeImage(self, handle) catch {};
}

fn newImage(self: *State, width: Cell, height: Cell) RuntimeError!Cell {
    const pixels = try words_graphics.imagePixels(width, height);
    const alloc_fn = self.writer.image_alloc_fn orelse return error.HostUnavailable;
    const free_fn = self.writer.image_free_fn orelse return error.HostUnavailable;
    const bytes = pixels * 4;
    if (bytes > max_total_bytes - self.gfx_images_bytes) return error.MemoryExhausted;
    const place = for (self.gfx_images, 0..) |slot, place| {
        if (slot.pixels.len == 0) break place;
    } else return error.MemoryExhausted;
    const buffer = alloc_fn(self.writer.context, pixels) orelse return error.MemoryExhausted;
    if (buffer.len != pixels) {
        free_fn(self.writer.context, buffer);
        return error.HostFailed;
    }
    @memset(buffer, opaque_black);
    const slot = &self.gfx_images[place];
    slot.pixels = buffer;
    slot.width = @intCast(width);
    slot.height = @intCast(height);
    self.gfx_images_bytes += bytes;
    return handleOf(place, slot.generation);
}

fn freeImage(self: *State, handle: Cell) RuntimeError!void {
    const slot = try slotOf(self, handle);
    release(self, slot);
    // Drawing goes back to the screen when its image goes.
    if (self.gfx_target == handle) self.gfx_target = screen;
}

fn release(self: *State, slot: *Slot) void {
    if (self.writer.image_free_fn) |free_fn| free_fn(self.writer.context, slot.pixels);
    self.gfx_images_bytes -= slot.pixels.len * 4;
    slot.pixels = &.{};
    slot.width = 0;
    slot.height = 0;
    slot.clip = null;
    slot.generation +%= 1;
}

/// Frees every image of the pool and draws on the screen again: restoring an image, and
/// the end of the program.
pub fn releaseAll(self: *State) void {
    for (&self.gfx_images) |*slot| {
        if (slot.pixels.len != 0) release(self, slot);
    }
    self.gfx_target = screen;
}

/// How COPY-RECT puts the pixels: the transparent color (negative for none), the flip
/// (1 left and right, 2 top and bottom, 3 both), the mode, the opacity of mode 3 (0 to
/// 255), and the scale (1 to `max_scale`).
const Style = struct { key: Cell, flip: Cell, mode: Cell, alpha: Cell, scale: Cell };

pub const max_scale = 16;

/// IMAGE-MODE. `over` and `over_scaled` (tque 1046) put each pixel of the source over the
/// one there by the source pixel's own alpha, the second with that alpha times
/// IMAGE-ALPHA / 255.
pub const Mode = enum(u3) { copy, xor, add, blend, over, over_scaled };

/// The alpha the pixels of the image drawn on must have: the screen (the image of
/// GFX-INIT, which SHOW gives the host) stays opaque whatever is put on it; an image of
/// the pool keeps the alpha it is given.
pub fn forcedAlpha(self: *State) u32 {
    return if (self.gfx_target == screen) opaque_black else 0;
}

/// Copies the w × h rectangle at sx sy of image `source` to dx dy of the image drawn on,
/// made `scale` times as large. Parts outside either image are left out. Within one image
/// the rectangles may overlap, but not when flipped or scaled.
fn copyRect(self: *State, source: Cell, sx: Cell, sy: Cell, w: Cell, h: Cell, dx: Cell, dy: Cell, style: Style) RuntimeError!void {
    if (style.flip < 0 or style.flip > 3 or style.mode < 0 or style.mode > 5 or style.alpha < 0 or style.alpha > 255) return error.InvalidNumber;
    if (style.scale < 1 or style.scale > max_scale) return error.InvalidNumber;
    const from = try canvasOf(self, source);
    const to = try target(self);
    if (w <= 0 or h <= 0) return;
    const scale: i128 = style.scale;
    const flip_x = style.flip & 1 != 0;
    const flip_y = style.flip & 2 != 0;
    const mode: Mode = @enumFromInt(style.mode);
    const same = from.pixels.ptr == to.pixels.ptr;
    if (same and (style.flip != 0 or scale != 1) and overlaps(sx, sy, dx, dy, w, h, scale)) return error.InvalidNumber;
    // The places of the rectangle on the image drawn on, from 0 to w × scale, whose places
    // in both images are inside them; in 128 bits, since the numbers come from the program.
    const part = to.bounds();
    const columns = clippedRange(w, scale, dx, part.x0, part.x1, sx, from.width, flip_x) orelse return;
    const rows = clippedRange(h, scale, dy, part.y0, part.y1, sy, from.height, flip_y) orelse return;
    const transparent: ?u32 = if (style.key < 0) null else @as(u32, @truncate(@as(u64, @bitCast(style.key)))) & rgb_mask;
    const alpha: u32 = @intCast(style.alpha);
    // Within one image (not flipped, not scaled), rows and columns go the way that reads
    // each pixel before it is written over, as memmove does.
    const rows_backward = same and dy > sy;
    const columns_backward = same and dx > sx;
    const plain = !flip_x and scale == 1 and transparent == null and mode == .copy;
    const forced = forcedAlpha(self);
    var step: usize = 0;
    while (step < rows.count) : (step += 1) {
        const j = rows.offset(if (rows_backward) rows.count - 1 - step else step);
        const source_y = coordinate(sy, h, @divFloor(j, scale), flip_y);
        // Inside the image, so it fits a usize also on a 32-bit host.
        const target_y: usize = @intCast(dy + j);
        const source_row = from.pixels[source_y * from.width ..][0..from.width];
        const target_row = to.pixels[target_y * to.width ..][0..to.width];
        if (plain) {
            const first_x: usize = @intCast(dx + columns.first);
            const first_source = coordinate(sx, w, columns.first, false);
            const into = target_row[first_x..][0..columns.count];
            const out_of = source_row[first_source..][0..columns.count];
            if (columns_backward) std.mem.copyBackwards(u32, into, out_of) else std.mem.copyForwards(u32, into, out_of);
            if (forced != 0) for (into) |*pixel| {
                pixel.* |= forced;
            };
            continue;
        }
        var column: usize = 0;
        while (column < columns.count) : (column += 1) {
            const i = columns.offset(if (columns_backward and !flip_x and scale == 1) columns.count - 1 - column else column);
            const pixel = source_row[coordinate(sx, w, @divFloor(i, scale), flip_x)];
            if (transparent) |color| {
                if (pixel & rgb_mask == color) continue;
            }
            const place: usize = @intCast(dx + i);
            target_row[place] = combine(mode, alpha, target_row[place], pixel) | forced;
        }
    }
}

/// GFX-TILEMAP ( addr cols rows img tw th sx sy x y w h key -- ): draws the part of a
/// map that a view shows. The map is cols × rows bytes at addr in logical memory, a tile
/// number in each, row by row; tile n is the tw × th rectangle of image img that is n
/// tiles from its top left corner, counted along its rows. The view is the w × h
/// rectangle at x y of the image drawn on, showing the map from its pixel sx sy; what
/// lies outside the map is left as it is, and so are the pixels of color `key` (none when
/// it is negative), so that one map can be drawn over another. Only the pixels inside
/// both the view and the image drawn on are reckoned.
fn drawTilemap(self: *State, view: [13]Cell) RuntimeError!void {
    const address = view[0];
    const cols = view[1];
    const rows = view[2];
    const tw = view[4];
    const th = view[5];
    if (cols < 0 or rows < 0 or tw < 1 or tw > max_side or th < 1 or th > max_side) return error.InvalidNumber;
    const count = std.math.mul(u64, @intCast(cols), @intCast(rows)) catch return error.InvalidNumber;
    const start = try self.memoryAddress(address, std.math.cast(usize, count) orelse return error.InvalidAddress);
    const map = self.memory[start..][0..@intCast(count)];
    const from = try canvasOf(self, view[3]);
    const to = try target(self);
    const sheet_cols: usize = from.width / @as(usize, @intCast(tw));
    if (sheet_cols == 0 or map.len == 0) return;
    const transparent: ?u32 = if (view[12] < 0) null else @as(u32, @truncate(@as(u64, @bitCast(view[12])))) & rgb_mask;
    const x: i128 = view[8];
    const y: i128 = view[9];
    // The view inside the part of the image drawn on that may be drawn in.
    const part = to.bounds();
    const x0: i128 = @max(x, @as(i128, @intCast(part.x0)));
    const x1: i128 = @min(x + @max(view[10], 0), @as(i128, @intCast(part.x1)));
    const y0: i128 = @max(y, @as(i128, @intCast(part.y0)));
    const y1: i128 = @min(y + @max(view[11], 0), @as(i128, @intCast(part.y1)));
    if (x0 >= x1 or y0 >= y1) return;
    const forced = forcedAlpha(self);
    const map_w: i128 = @as(i128, cols) * tw;
    const map_h: i128 = @as(i128, rows) * th;
    var py = y0;
    while (py < y1) : (py += 1) {
        const wy = @as(i128, view[7]) + (py - y);
        if (wy < 0 or wy >= map_h) continue;
        const row: usize = @intCast(@divFloor(wy, th));
        const ty: usize = @intCast(@mod(wy, th));
        const target_row = to.pixels[@as(usize, @intCast(py)) * to.width ..][0..to.width];
        var px = x0;
        while (px < x1) : (px += 1) {
            const wx = @as(i128, view[6]) + (px - x);
            if (wx < 0 or wx >= map_w) continue;
            const col: usize = @intCast(@divFloor(wx, tw));
            const tile: usize = map[row * @as(usize, @intCast(cols)) + col];
            const source_x = (tile % sheet_cols) * @as(usize, @intCast(tw)) + @as(usize, @intCast(@mod(wx, tw)));
            const source_y = (tile / sheet_cols) * @as(usize, @intCast(th)) + ty;
            if (source_y >= from.height) continue;
            const pixel = from.pixels[source_y * from.width + source_x];
            if (transparent) |color| {
                if (pixel & rgb_mask == color) continue;
            }
            target_row[@intCast(px)] = pixel | forced;
        }
    }
}

/// GFX-INDEXED ( addr w h palette x y key -- ): draws a picture of w × h color numbers,
/// one byte each, row by row, at addr in logical memory, at x y of the image drawn on;
/// each number is the color in that cell of the 256 cells at `palette`. Pixels of the
/// number `key` are left out (none when it is negative); so is what falls outside.
fn drawIndexed(self: *State, args: [7]Cell) RuntimeError!void {
    const w = args[1];
    const h = args[2];
    if (w < 0 or w > max_side or h < 0 or h > max_side) return error.InvalidNumber;
    const width: usize = @intCast(w);
    const height: usize = @intCast(h);
    const start = try self.memoryAddress(args[0], width * height);
    const bytes = self.memory[start..][0 .. width * height];
    var palette: [256]u32 = undefined;
    const palette_start = try self.memoryAddress(args[3], 256 * memory_map.cell_size);
    for (&palette, 0..) |*color, index| {
        const cell = std.mem.readInt(i64, self.memory[palette_start + index * memory_map.cell_size ..][0..8], .little);
        color.* = opaque_black | (@as(u32, @truncate(@as(u64, @bitCast(cell)))) & rgb_mask);
    }
    const to = try target(self);
    const key: ?u8 = if (args[6] < 0 or args[6] > 255) null else @intCast(args[6]);
    const part = to.bounds();
    const columns = clippedRange(w, 1, args[4], part.x0, part.x1, 0, width, false) orelse return;
    const rows = clippedRange(h, 1, args[5], part.y0, part.y1, 0, height, false) orelse return;
    var step: usize = 0;
    while (step < rows.count) : (step += 1) {
        const j: usize = @intCast(rows.offset(step));
        const target_y: usize = @intCast(args[5] + @as(Cell, @intCast(j)));
        var column: usize = 0;
        while (column < columns.count) : (column += 1) {
            const i: usize = @intCast(columns.offset(column));
            const number = bytes[j * width + i];
            if (key) |left_out| {
                if (number == left_out) continue;
            }
            to.pixels[target_y * to.width + @as(usize, @intCast(args[4] + @as(Cell, @intCast(i))))] = palette[number];
        }
    }
}

/// The bytes of one pixel of GFX-RGB: a 32-bit number, low byte first (as L! stores it),
/// whose low 24 bits are the color $RRGGBB; the high byte is not used.
pub const rgb_pixel_bytes = 4;

/// GFX-RGB ( addr w h stride x y key -- ): draws a picture of w × h colors, four bytes
/// each (rgb_pixel_bytes), at addr in logical memory, at x y of the image drawn on. Each
/// row starts `stride` bytes after the one before; 0 stands for w × 4, and a smaller
/// number is refused. Pixels of the color `key` are left out (none when it is negative);
/// so is what falls outside. The whole picture must lie in memory, also the part that
/// falls outside. The work is charged to the execution limit before a pixel is written,
/// one unit for each 256 pixels drawn, so the picture is drawn whole or not at all.
fn drawRgb(self: *State, args: [7]Cell) RuntimeError!void {
    const w = args[1];
    const h = args[2];
    if (w < 0 or w > max_side or h < 0 or h > max_side) return error.InvalidNumber;
    const width: usize = @intCast(w);
    const height: usize = @intCast(h);
    const row_bytes = width * rgb_pixel_bytes;
    if (args[3] < 0) return error.InvalidNumber;
    const stride: usize = if (args[3] == 0) row_bytes else std.math.cast(usize, args[3]) orelse return error.InvalidNumber;
    if (stride < row_bytes) return error.InvalidNumber;
    const length: usize = if (height == 0) 0 else std.math.add(usize, std.math.mul(usize, height - 1, stride) catch return error.InvalidAddress, row_bytes) catch return error.InvalidAddress;
    const start = try self.memoryAddress(args[0], length);
    const bytes = self.memory[start..][0..length];
    const to = try target(self);
    const key: ?u32 = if (args[6] < 0) null else @as(u32, @truncate(@as(u64, @bitCast(args[6])))) & rgb_mask;
    const part = to.bounds();
    const columns = clippedRange(w, 1, args[4], part.x0, part.x1, 0, width, false) orelse return;
    const rows = clippedRange(h, 1, args[5], part.y0, part.y1, 0, height, false) orelse return;
    var blocks = (rows.count * columns.count + 255) / 256;
    while (blocks > 0) : (blocks -= 1) try @import("words_numeric.zig").checkWorkBlock(self);
    var step: usize = 0;
    while (step < rows.count) : (step += 1) {
        const j: usize = @intCast(rows.offset(step));
        const target_y: usize = @intCast(args[5] + @as(Cell, @intCast(j)));
        const row = bytes[j * stride ..][0..row_bytes];
        var column: usize = 0;
        while (column < columns.count) : (column += 1) {
            const i: usize = @intCast(columns.offset(column));
            const color = std.mem.readInt(u32, row[i * rgb_pixel_bytes ..][0..rgb_pixel_bytes], .little) & rgb_mask;
            if (key) |left_out| {
                if (color == left_out) continue;
            }
            to.pixels[target_y * to.width + @as(usize, @intCast(args[4] + @as(Cell, @intCast(i))))] = opaque_black | color;
        }
    }
}

/// GFX-ROW-SHIFT ( table x y w h -- ) and GFX-ROW-COLOR ( table rgb x y w h -- ): an
/// effect on each row of the w × h rectangle at x y of the image drawn on, after it is
/// drawn, with the cell of `table` for that row (the first cell for the top row): the
/// row moves that many pixels to the right inside the rectangle, those that leave it
/// coming in again on the left (a negative number moves it left), or, with a color, the
/// pixels of that color in the row take the color in the table. The rows and columns of
/// the rectangle outside the image are left out.
fn rowEffect(self: *State, table: Cell, color: ?Cell, x: Cell, y: Cell, w: Cell, h: Cell) RuntimeError!void {
    if (w <= 0 or h <= 0) return;
    if (h > max_side) return error.InvalidNumber;
    const table_start = try self.memoryAddress(table, @as(usize, @intCast(h)) * memory_map.cell_size);
    const to = try target(self);
    const x0: i128 = @max(x, 0);
    const x1: i128 = @min(@as(i128, x) + w, @as(i128, @intCast(to.width)));
    const y0: i128 = @max(y, 0);
    const y1: i128 = @min(@as(i128, y) + h, @as(i128, @intCast(to.height)));
    if (x0 >= x1 or y0 >= y1) return;
    const from: usize = @intCast(x0);
    const span: usize = @intCast(x1 - x0);
    const old: u32 = if (color) |value| @as(u32, @truncate(@as(u64, @bitCast(value)))) & rgb_mask else 0;
    // CLIP!: only the rows and columns that may be drawn in change. A row still moves
    // by the whole of its part of the rectangle; the pixels outside the part CLIP! set keep theirs.
    const part = to.bounds();
    const clip_from = @max(from, part.x0);
    const clip_to = @min(from + span, part.x1);
    if (clip_from >= clip_to) return;
    const clipped = clip_from != from or clip_to != from + span;
    var row = y0;
    while (row < y1) : (row += 1) {
        if (row < part.y0 or row >= part.y1) continue;
        const offset: usize = @intCast(row - y);
        const cell = std.mem.readInt(i64, self.memory[table_start + offset * memory_map.cell_size ..][0..8], .little);
        const pixels = to.pixels[@as(usize, @intCast(row)) * to.width + from ..][0..span];
        if (color != null) {
            const new = opaque_black | (@as(u32, @truncate(@as(u64, @bitCast(cell)))) & rgb_mask);
            for (pixels[clip_from - from .. clip_to - from]) |*pixel| {
                if (pixel.* & rgb_mask == old) pixel.* = new;
            }
        } else {
            // Moving right by n is turning the row left by span - n.
            const right: usize = @intCast(@mod(@as(i128, cell), @as(i128, @intCast(span))));
            const turn = (span - right) % span;
            if (!clipped) {
                std.mem.rotate(u32, pixels, turn);
            } else if (turn != 0) {
                // The pixel that comes to place i is the one at i + turn, around the
                // row. The places in the part CLIP! set take theirs from the row as it was: the first
                // `turn` pixels are kept aside, as the places near the end read them
                // after the places before were written.
                shiftClipped(pixels, turn, clip_from - from, clip_to - from);
            }
        }
    }
}

/// Turns a row left by `turn` as std.mem.rotate does, but changes only the places
/// `first` up to `last`: each takes the pixel `turn` places to its right, around the
/// row, as the row was before. A row is at most max_side pixels.
fn shiftClipped(pixels: []u32, turn: usize, first: usize, last: usize) void {
    var before: [max_side]u32 = undefined;
    @memcpy(before[0..pixels.len], pixels);
    for (first..last) |place| pixels[place] = before[(place + turn) % pixels.len];
}

/// A pixel of the source put on one of the image drawn on.
pub fn combine(mode: Mode, alpha: u32, under: u32, over: u32) u32 {
    return switch (mode) {
        .copy => over,
        .xor => opaque_black | ((under ^ over) & rgb_mask),
        .add => blk: {
            var result: u32 = opaque_black;
            inline for (.{ 0, 8, 16 }) |shift| {
                const sum = ((under >> shift) & 0xff) + ((over >> shift) & 0xff);
                result |= @as(u32, @min(sum, 255)) << shift;
            }
            break :blk result;
        },
        .blend => blk: {
            var result: u32 = opaque_black;
            inline for (.{ 0, 8, 16 }) |shift| {
                const mixed = (((over >> shift) & 0xff) * alpha + ((under >> shift) & 0xff) * (255 - alpha) + 127) / 255;
                result |= mixed << shift;
            }
            break :blk result;
        },
        .over => sourceOver(under, over, over >> 24),
        .over_scaled => sourceOver(under, over, ((over >> 24) * alpha + 127) / 255),
    };
}

/// `top` put over `under` with the alpha `a` (0 to 255) for `top`, both with their colors
/// as they are (not multiplied by their alpha): the alpha becomes a + under's × (255 − a)
/// / 255, and each color the two colors weighed by a and by under's alpha × (255 − a) /
/// 255, to the nearest. Over an opaque pixel that is top × a + under × (255 − a), opaque.
/// With a 0 the pixel under stays as it is; with 255 it becomes `top`'s color, opaque.
pub fn sourceOver(under: u32, top: u32, a: u32) u32 {
    if (a == 0) return under;
    if (a >= 255) return opaque_black | (top & rgb_mask);
    // Under's share, and the new alpha, both times 255.
    const rest = (under >> 24) * (255 - a);
    const total = a * 255 + rest;
    var result: u32 = ((total + 127) / 255) << 24;
    inline for (.{ 0, 8, 16 }) |shift| {
        const mixed = (((top >> shift) & 0xff) * a * 255 + ((under >> shift) & 0xff) * rest + total / 2) / total;
        result |= mixed << shift;
    }
    return result;
}

test "sourceOver puts a pixel over another by its alpha" {
    // Over an opaque pixel: the plain mix, opaque.
    try std.testing.expectEqual(@as(u32, 0xff80_8080), sourceOver(0xff00_0000, 0x80ff_ffff, 128));
    try std.testing.expectEqual(@as(u32, 0xff40_4040), sourceOver(0xff00_0000, 0x40ff_ffff, 64));
    try std.testing.expectEqual(@as(u32, 0xff7f_0080), sourceOver(0xffff_0000, 0x8000_00ff, 128));
    // Nothing of it, and all of it.
    try std.testing.expectEqual(@as(u32, 0xff12_3456), sourceOver(0xff12_3456, 0x00ff_ffff, 0));
    try std.testing.expectEqual(@as(u32, 0xffab_cdef), sourceOver(0x4012_3456, 0xffab_cdef, 255));
    // Over a wholly transparent pixel: the pixel itself, with its alpha.
    try std.testing.expectEqual(@as(u32, 0x80ab_cdef), sourceOver(0x0012_3456, 0x80ab_cdef, 128));
    // Over a half transparent one: alpha 128 + 128 × 127 / 255 = 192 (to the nearest),
    // and white over black weighed 128 × 255 to 128 × 127: 170.
    try std.testing.expectEqual(@as(u32, 0xc0aa_aaaa), sourceOver(0x8000_0000, 0x80ff_ffff, 128));
}

/// Places of the rectangle on the image drawn on, from `first`. `first` may be as large
/// as the rectangle (beyond 2^63 when scaled), but `count` is at most a side of an image.
const Span = struct {
    first: i128,
    count: usize,

    fn offset(span: Span, step: usize) i128 {
        return span.first + step;
    }
};

/// The source column (or row) that offset i of the rectangle copies.
fn coordinate(start: Cell, size: Cell, i: i128, flipped: bool) usize {
    return @intCast(if (flipped) @as(i128, start) + size - 1 - i else @as(i128, start) + i);
}

/// The places p, from 0 to `size` × `scale`, with `to_start + p` inside 0 to `to_size`
/// and the source place of p ÷ `scale` inside 0 to `from_size`; null when there are none.
fn range(size: Cell, scale: i128, to_start: i128, to_size: usize, from_start: Cell, from_size: usize, flipped: bool) ?Span {
    const n: i128 = size;
    var first: i128 = @max(0, -to_start);
    var last: i128 = @min(n * scale, @as(i128, @intCast(to_size)) - to_start);
    // The offsets q = p ÷ scale of the source that are inside it, from low to high.
    var low: i128 = undefined;
    var high: i128 = undefined;
    if (flipped) {
        // from_start + size - 1 - q inside 0 to from_size.
        low = @as(i128, from_start) + n - @as(i128, @intCast(from_size));
        high = @as(i128, from_start) + n;
    } else {
        low = -@as(i128, from_start);
        high = @as(i128, @intCast(from_size)) - from_start;
    }
    first = @max(first, low * scale);
    last = @min(last, high * scale);
    if (first >= last) return null;
    return .{ .first = first, .count = @intCast(last - first) };
}

/// Whether the source rectangle and the place it is copied to (`scale` times as large)
/// share a pixel.
fn overlaps(sx: Cell, sy: Cell, dx: Cell, dy: Cell, w: Cell, h: Cell, scale: i128) bool {
    const apart_x = @as(i128, dx) >= @as(i128, sx) + w or @as(i128, sx) >= @as(i128, dx) + w * scale;
    const apart_y = @as(i128, dy) >= @as(i128, sy) + h or @as(i128, sy) >= @as(i128, dy) + h * scale;
    return !apart_x and !apart_y;
}
