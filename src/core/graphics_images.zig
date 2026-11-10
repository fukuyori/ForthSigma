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

pub const words = [_]Builtin{ .gfx_image_new, .gfx_image_free, .gfx_image_size, .gfx_target, .gfx_target_query, .gfx_copy, .gfx_image_load };

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
};

/// An image to draw on or to copy from: the screen or an image of the pool.
pub const Canvas = struct {
    pixels: []u32,
    width: usize,
    height: usize,

    /// The place of pixel x y, or null outside the image.
    pub fn index(canvas: Canvas, x: Cell, y: Cell) ?usize {
        if (x < 0 or y < 0 or x >= canvas.width or y >= canvas.height) return null;
        return @as(usize, @intCast(y)) * canvas.width + @as(usize, @intCast(x));
    }
};

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
            const flip = try self.pop();
            const key = try self.pop();
            const dy = try self.pop();
            const dx = try self.pop();
            const h = try self.pop();
            const w = try self.pop();
            const sy = try self.pop();
            const sx = try self.pop();
            const source = try self.pop();
            try copyRect(self, source, sx, sy, w, h, dx, dy, key, flip);
        },
        .gfx_image_load => {
            const key = try self.pop();
            const name = try self.memoryRange();
            for (try @import("graphics_decode.zig").loadImage(self, name, key)) |value| try self.push(value);
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

/// The image the drawing words draw on.
pub fn target(self: *State) RuntimeError!Canvas {
    return canvasOf(self, self.gfx_target);
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

/// Copies the w × h rectangle at sx sy of image `source` to dx dy of the image drawn on.
/// `key` is the transparent color (pixels of that color are not copied) or negative for
/// none; `flip` 1 flips left and right, 2 top and bottom, 3 both. Parts outside either
/// image are left out. Within one image the rectangles may overlap, but not when flipped.
fn copyRect(self: *State, source: Cell, sx: Cell, sy: Cell, w: Cell, h: Cell, dx: Cell, dy: Cell, key: Cell, flip: Cell) RuntimeError!void {
    if (flip < 0 or flip > 3) return error.InvalidNumber;
    const from = try canvasOf(self, source);
    const to = try target(self);
    if (w <= 0 or h <= 0) return;
    const flip_x = flip & 1 != 0;
    const flip_y = flip & 2 != 0;
    const same = from.pixels.ptr == to.pixels.ptr;
    if (same and flip != 0 and overlaps(sx, sy, dx, dy, w, h)) return error.InvalidNumber;
    // The columns i (0 to w) whose places in both images are inside them; in 128 bits,
    // since the numbers come from the program.
    const columns = range(w, dx, to.width, sx, from.width, flip_x) orelse return;
    const rows = range(h, dy, to.height, sy, from.height, flip_y) orelse return;
    const transparent: ?u32 = if (key < 0) null else @as(u32, @truncate(@as(u64, @bitCast(key)))) & rgb_mask;
    // Within one image, rows and columns go the way that reads each pixel before it is
    // written over, as memmove does.
    const rows_backward = same and dy > sy;
    const columns_backward = same and dx > sx;
    var step: usize = 0;
    while (step < rows.count) : (step += 1) {
        const j = rows.offset(if (rows_backward) rows.count - 1 - step else step);
        const source_y = coordinate(sy, h, j, flip_y);
        // Inside the image, so it fits a usize also on a 32-bit host.
        const target_y: usize = @intCast(dy + j);
        const source_row = from.pixels[source_y * from.width ..][0..from.width];
        const target_row = to.pixels[target_y * to.width ..][0..to.width];
        if (!flip_x and transparent == null) {
            const first_x: usize = @intCast(dx + columns.first);
            const first_source = coordinate(sx, w, columns.first, false);
            const into = target_row[first_x..][0..columns.count];
            const out_of = source_row[first_source..][0..columns.count];
            if (columns_backward) std.mem.copyBackwards(u32, into, out_of) else std.mem.copyForwards(u32, into, out_of);
            continue;
        }
        var column: usize = 0;
        while (column < columns.count) : (column += 1) {
            const i = columns.offset(if (columns_backward and !flip_x) columns.count - 1 - column else column);
            const pixel = source_row[coordinate(sx, w, i, flip_x)];
            if (transparent) |color| {
                if (pixel & rgb_mask == color) continue;
            }
            target_row[@intCast(dx + i)] = pixel;
        }
    }
}

/// Offsets of the rectangle, from `first`; `first` may be as large as the rectangle (near
/// 2^63), but `count` is at most a side of an image.
const Span = struct {
    first: Cell,
    count: usize,

    fn offset(span: Span, step: usize) Cell {
        return span.first + @as(Cell, @intCast(step));
    }
};

/// The source column (or row) that offset i of the rectangle copies.
fn coordinate(start: Cell, size: Cell, i: Cell, flipped: bool) usize {
    return @intCast(if (flipped) @as(i128, start) + size - 1 - i else @as(i128, start) + i);
}

/// The offsets i, from 0 to `size`, with `to_start + i` inside 0 to `to_size` and the
/// source place inside 0 to `from_size`; null when there are none.
fn range(size: Cell, to_start: Cell, to_size: usize, from_start: Cell, from_size: usize, flipped: bool) ?Span {
    const n: i128 = size;
    var first: i128 = @max(0, -@as(i128, to_start));
    var last: i128 = @min(n, @as(i128, @intCast(to_size)) - to_start);
    if (flipped) {
        // from_start + size - 1 - i inside 0 to from_size.
        first = @max(first, @as(i128, from_start) + n - @as(i128, @intCast(from_size)));
        last = @min(last, @as(i128, from_start) + n);
    } else {
        first = @max(first, -@as(i128, from_start));
        last = @min(last, @as(i128, @intCast(from_size)) - from_start);
    }
    if (first >= last) return null;
    return .{ .first = @intCast(first), .count = @intCast(last - first) };
}

fn overlaps(sx: Cell, sy: Cell, dx: Cell, dy: Cell, w: Cell, h: Cell) bool {
    const apart_x = @as(i128, dx) >= @as(i128, sx) + w or @as(i128, sx) >= @as(i128, dx) + w;
    const apart_y = @as(i128, dy) >= @as(i128, sy) + h or @as(i128, sy) >= @as(i128, dy) + h;
    return !apart_x and !apart_y;
}
