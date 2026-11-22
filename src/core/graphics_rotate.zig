//! GFX-ROTATE (tque 1045): a rectangle of an image put on the image drawn on turned by
//! any angle and made larger or smaller by any factor, each way by its own.
//!
//! Every pixel of the image drawn on that the turned rectangle can reach is traced back
//! to the place of the source it shows (the inverse of the turn and of the scale), in
//! whole numbers: the angle is in hundredths of a degree, the factors in thousandths,
//! the sine and cosine come from a table of whole degrees (30 bits after the point) with
//! the hundredths between two of them in a straight line, and a place in the source has
//! 31 bits after the point. No floating-point number is used, so every host draws the
//! same pixels, and a build without the floating-point words draws them too.

const std = @import("std");
const defs = @import("defs.zig");
const forth = @import("../forth.zig");
const memory_map = @import("memory_map.zig");
const graphics_images = @import("graphics_images.zig");
const Cell = memory_map.Cell;
const RuntimeError = defs.RuntimeError;
const State = forth.State;
const Mode = graphics_images.Mode;

const rgb_mask: u32 = 0x00ff_ffff;
const opaque_black: u32 = 0xff00_0000;

/// A whole turn, in the angle's unit (a hundredth of a degree).
pub const turn = 36000;
/// The factor that leaves the size as it is (a thousandth each).
pub const unit_scale = 1000;
/// The largest factor: 64 times.
pub const max_scale = 64 * unit_scale;

/// sin of 0 to 90 whole degrees, times 2^30, to the nearest.
const sine_table: [91]i32 = blk: {
    @setEvalBranchQuota(10000);
    var table: [91]i32 = undefined;
    for (&table, 0..) |*entry, degree| {
        const x: comptime_float = @as(comptime_float, @floatFromInt(degree)) * std.math.pi / 180.0;
        entry.* = @intFromFloat(@round(@sin(x) * (1 << 30)));
    }
    break :blk table;
};

/// sin of an angle of 0 to 9000 hundredths of a degree, times 2^30.
fn quarterSine(angle: u32) i64 {
    const degree = angle / 100;
    const part = angle % 100;
    if (part == 0) return sine_table[degree];
    const low: i64 = sine_table[degree];
    const high: i64 = sine_table[degree + 1];
    return low + @divFloor((high - low) * part + 50, 100);
}

/// sin and cos of an angle in hundredths of a degree (any cell), each times 2^30. The
/// quarter turns are exact: 0, 2^30, or -2^30.
pub fn sineCosine(angle: Cell) [2]i64 {
    const a: u32 = @intCast(@mod(angle, turn));
    const quarter = a / 9000;
    const rest = a % 9000;
    const s = quarterSine(rest);
    const c = quarterSine(9000 - rest);
    return switch (quarter) {
        0 => .{ s, c },
        1 => .{ c, -s },
        2 => .{ -s, -c },
        else => .{ -c, s },
    };
}

pub const Request = struct {
    source: Cell,
    sx: Cell,
    sy: Cell,
    w: Cell,
    h: Cell,
    cx: Cell,
    cy: Cell,
    angle: Cell,
    xscale: Cell,
    yscale: Cell,
    key: Cell,
    mode: Cell,
    alpha: Cell,
    smooth: bool,
};

/// One place of the source, 31 bits after the point, as a 128-bit number: the numbers
/// come from the program, and a center far from the image must not wrap around.
const fraction_bits = 31;

/// The pixel of the source rectangle at column i, row j of it, or null outside the
/// rectangle or the image, or when it has the transparent color.
fn texel(from: graphics_images.Canvas, request: Request, transparent: ?u32, i: i128, j: i128) ?u32 {
    if (i < 0 or j < 0 or i >= request.w or j >= request.h) return null;
    const x = @as(i128, request.sx) + i;
    const y = @as(i128, request.sy) + j;
    if (x < 0 or y < 0 or x >= from.width or y >= from.height) return null;
    const pixel = from.pixels[@as(usize, @intCast(y)) * from.width + @as(usize, @intCast(x))];
    if (transparent) |color| {
        if (pixel & rgb_mask == color) return null;
    }
    return pixel;
}

/// The color and alpha the source shows at the place u v (31 bits after the point,
/// measured in pixels of the rectangle from its top left corner): the pixel the place is
/// in, or with `smooth` the four pixels around it weighed by how near each is, each
/// color weighed by its alpha as well, so that a pixel that is not there (outside the
/// rectangle, or of the transparent color) gives no color. Null when nothing shows.
fn sample(from: graphics_images.Canvas, request: Request, transparent: ?u32, u: i128, v: i128) ?u32 {
    if (!request.smooth) {
        return texel(from, request, transparent, u >> fraction_bits, v >> fraction_bits);
    }
    // The four pixels whose centers are around the place: half a pixel back, then the
    // part beyond the whole pixel in 256ths.
    const half: i128 = 1 << (fraction_bits - 1);
    const pu = u - half;
    const pv = v - half;
    const column = pu >> fraction_bits;
    const line = pv >> fraction_bits;
    const fx: u32 = @intCast((pu >> (fraction_bits - 8)) & 0xff);
    const fy: u32 = @intCast((pv >> (fraction_bits - 8)) & 0xff);
    const weights = [4]u32{ (256 - fx) * (256 - fy), fx * (256 - fy), (256 - fx) * fy, fx * fy };
    const places = [4][2]i128{ .{ column, line }, .{ column + 1, line }, .{ column, line + 1 }, .{ column + 1, line + 1 } };
    // The weights add up to 65536; an alpha is at most 255: the sums fit 64 bits.
    var alpha_sum: u64 = 0;
    var color_sum = [3]u64{ 0, 0, 0 };
    for (weights, places) |weight, place| {
        if (weight == 0) continue;
        const pixel = texel(from, request, transparent, place[0], place[1]) orelse continue;
        const share: u64 = @as(u64, weight) * (pixel >> 24);
        alpha_sum += share;
        inline for (.{ 0, 8, 16 }, 0..) |shift, index| color_sum[index] += share * ((pixel >> shift) & 0xff);
    }
    if (alpha_sum == 0) return null;
    const alpha: u32 = @intCast((alpha_sum + 32768) / 65536);
    if (alpha == 0) return null;
    var result: u32 = alpha << 24;
    inline for (.{ 0, 8, 16 }, 0..) |shift, index| {
        const color: u32 = @intCast(@min((color_sum[index] + alpha_sum / 2) / alpha_sum, 255));
        result |= color << shift;
    }
    return result;
}

/// The pixel `shown` (a color with its alpha) put on `under` in the mode, as GFX-COPY
/// puts a pixel of the source: the modes 4 and 5 by its alpha, mode 0 as it is with its
/// alpha, the modes 1 to 3 by its color alone. Without `smooth` the pixel is one of the
/// source's, so the result is GFX-COPY's. With it, a mixed pixel that shows less than
/// half (an edge, or beside the transparent color) is left out by the modes 0 to 3,
/// which cannot show a part of a pixel.
fn put(mode: Mode, alpha: u32, under: u32, shown: u32, smooth: bool) u32 {
    const by_alpha = mode == .over or mode == .over_scaled;
    if (smooth and !by_alpha and shown >> 24 < 128) return under;
    return graphics_images.combine(mode, alpha, under, shown);
}

/// A place of the source along one side while a row is drawn: floor(numerator / scale),
/// kept as the whole part and the rest, so that going one pixel on adds the step to
/// both without ever rounding: every pixel gets exactly the place the whole formula
/// gives it, wherever the row starts.
const Walk = struct {
    whole: i128,
    rest: i128,
    step_whole: i128,
    step_rest: i128,
    scale: i128,

    fn start(numerator: i128, step: i128, scale: i128) Walk {
        return .{
            .whole = @divFloor(numerator, scale),
            .rest = @mod(numerator, scale),
            .step_whole = @divFloor(step, scale),
            .step_rest = @mod(step, scale),
            .scale = scale,
        };
    }

    fn next(walk: *Walk) void {
        walk.whole += walk.step_whole;
        walk.rest += walk.step_rest;
        if (walk.rest >= walk.scale) {
            walk.rest -= walk.scale;
            walk.whole += 1;
        }
    }
};

/// GFX-ROTATE: see the file's head. The pixel of the rectangle at w/2 h/2 (halves
/// dropped) comes to the pixel cx cy of the image drawn on, and the rectangle is turned
/// around it clockwise by `angle` and made `xscale` and `yscale` thousandths as large
/// along its own width and height. With angle 0 and both factors 1000 it draws what
/// GFX-COPY draws at cx - w/2, cy - h/2.
pub fn draw(self: *State, request: Request) RuntimeError!void {
    if (request.mode < 0 or request.mode > 5 or request.alpha < 0 or request.alpha > 255) return error.InvalidNumber;
    if (request.xscale < 1 or request.xscale > max_scale or request.yscale < 1 or request.yscale > max_scale) return error.InvalidNumber;
    const from = try graphics_images.canvasOf(self, request.source);
    const to = try graphics_images.target(self);
    // Turning an image onto itself would read pixels already written.
    if (from.pixels.ptr == to.pixels.ptr) return error.InvalidNumber;
    if (request.w <= 0 or request.h <= 0) return;
    const mode: Mode = @enumFromInt(request.mode);
    const transparent: ?u32 = if (request.key < 0) null else @as(u32, @truncate(@as(u64, @bitCast(request.key)))) & rgb_mask;
    const alpha: u32 = @intCast(request.alpha);
    const forced = graphics_images.forcedAlpha(self);
    const turned = sineCosine(request.angle);
    const sine: i128 = turned[0];
    const cosine: i128 = turned[1];

    // The part of the image drawn on the turned rectangle can reach, inside CLIP!. The
    // rectangle is turned around the middle of its pixel at w/2 h/2, which is at most
    // w/2 + 1 pixels from either end of its width (a half more than the half, and for
    // an even width the two ends are not equally far); smoothing reaches a pixel beyond
    // the edge. Each as large as it is drawn, the two added hold the rectangle at any
    // angle in a square around cx cy.
    const part = to.bounds();
    const wide = @divFloor((@as(i128, @divFloor(request.w, 2)) + 2) * request.xscale + unit_scale - 1, unit_scale) + 2;
    const high = @divFloor((@as(i128, @divFloor(request.h, 2)) + 2) * request.yscale + unit_scale - 1, unit_scale) + 2;
    const reach = wide + high;
    const x0: i128 = @max(@as(i128, request.cx) - reach, @as(i128, @intCast(part.x0)));
    const x1: i128 = @min(@as(i128, request.cx) + reach + 1, @as(i128, @intCast(part.x1)));
    const y0: i128 = @max(@as(i128, request.cy) - reach, @as(i128, @intCast(part.y0)));
    const y1: i128 = @min(@as(i128, request.cy) + reach + 1, @as(i128, @intCast(part.y1)));
    if (x0 >= x1 or y0 >= y1) return;

    // The work is charged before a pixel is written, a unit for each 256 pixels looked at.
    var blocks: u64 = @intCast(@divFloor((x1 - x0) * (y1 - y0) + 255, 256));
    while (blocks > 0) : (blocks -= 1) try @import("words_numeric.zig").checkWorkBlock(self);

    // The center of the rectangle's pixel at w/2 h/2 is put on the center of the pixel
    // cx cy. For the pixel px py, dx = 2 (px - cx) and dy = 2 (py - cy) are its center
    // from that center in halves of a pixel; turning back gives dx cos + dy sin along
    // the rectangle's width and dy cos - dx sin along its height; dividing by the
    // factor and adding the place of that center in the rectangle (w/2 + a half) gives
    // the place in the source. Halves times 2^30 are pixels times 2^31.
    const center_u: i128 = (@as(i128, @divFloor(request.w, 2)) << fraction_bits) + (1 << (fraction_bits - 1));
    const center_v: i128 = (@as(i128, @divFloor(request.h, 2)) << fraction_bits) + (1 << (fraction_bits - 1));
    const xs: i128 = request.xscale;
    const ys: i128 = request.yscale;
    // One pixel to the right adds 2 to dx: that much to each numerator.
    const step_u = 2 * cosine * unit_scale;
    const step_v = -2 * sine * unit_scale;
    var py = y0;
    while (py < y1) : (py += 1) {
        const dy = 2 * (py - request.cy);
        const dx = 2 * (x0 - request.cx);
        var u = Walk.start((dx * cosine + dy * sine) * unit_scale, step_u, xs);
        var v = Walk.start((dy * cosine - dx * sine) * unit_scale, step_v, ys);
        const row = to.pixels[@as(usize, @intCast(py)) * to.width ..][0..to.width];
        var px = x0;
        while (px < x1) : (px += 1) {
            if (sample(from, request, transparent, center_u + u.whole, center_v + v.whole)) |shown| {
                const place: usize = @intCast(px);
                row[place] = put(mode, alpha, row[place], shown, request.smooth) | forced;
            }
            u.next();
            v.next();
        }
    }
}

test "Walk gives every pixel the place the whole formula gives" {
    // 6 times as wide, from a start that is not a whole place: each step is a third of
    // 2^31 that does not come out even.
    const steps = [_][3]i128{ .{ -6 * (1 << 31), 2 * (1 << 30) * 1000, 6000 }, .{ 12345678901234567, -987654321, 777 }, .{ -5, 3, 64000 }, .{ 0, -(1 << 40), 1 } };
    for (steps) |case| {
        var walk = Walk.start(case[0], case[1], case[2]);
        var n: i128 = 0;
        while (n < 20000) : (n += 1) {
            try std.testing.expectEqual(@divFloor(case[0] + n * case[1], case[2]), walk.whole);
            walk.next();
        }
    }
}

test "sineCosine is exact at the quarter turns and close between them" {
    const one: i64 = 1 << 30;
    try std.testing.expectEqual([2]i64{ 0, one }, sineCosine(0));
    try std.testing.expectEqual([2]i64{ one, 0 }, sineCosine(9000));
    try std.testing.expectEqual([2]i64{ 0, -one }, sineCosine(18000));
    try std.testing.expectEqual([2]i64{ -one, 0 }, sineCosine(27000));
    try std.testing.expectEqual([2]i64{ 0, one }, sineCosine(36000));
    try std.testing.expectEqual([2]i64{ -one, 0 }, sineCosine(-9000));
    // 30 degrees: a half, to the nearest of 2^30.
    try std.testing.expectEqual(@as(i64, one / 2), sineCosine(3000)[0]);
    // 45 degrees: sine and cosine are the same.
    try std.testing.expectEqual(sineCosine(4500)[0], sineCosine(4500)[1]);
    // Between two whole degrees the straight line is within 4 in 100000 of the sine.
    const got: f64 = @floatFromInt(sineCosine(3050)[0]);
    const want = @sin(30.5 * std.math.pi / 180.0) * @as(f64, @floatFromInt(one));
    try std.testing.expect(@abs(got - want) < 0.00004 * @as(f64, @floatFromInt(one)));
    // The largest and smallest cells are angles too.
    _ = sineCosine(std.math.maxInt(Cell));
    _ = sineCosine(std.math.minInt(Cell));
}
