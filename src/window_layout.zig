//! Sizes of the native window that do not depend on the OS, so that Windows, macOS, and
//! Linux give the same numbers (docs/NATIVE_WINDOW_STUDY.md 10.10).

const std = @import("std");

/// The largest client area `WINDOW-SIZE 0 0` gives, in the backend's raster pixels.
pub const auto_max_width = 1600;
pub const auto_max_height = 1200;

/// The client area for `WINDOW-SIZE 0 0`: the image's own size when it fits, otherwise
/// the largest size with its proportions that fits. It fits in 1600 by 1200 and in the
/// room the screen's work area leaves for the client area (`room`; a side of 0 means
/// that side of the work area is not known). Each side is at least 1.
pub fn autoClientSize(image_width: u32, image_height: u32, room: [2]u32) [2]u32 {
    const iw: u64 = @max(image_width, 1);
    const ih: u64 = @max(image_height, 1);
    const lw: u64 = if (room[0] == 0) auto_max_width else @min(auto_max_width, room[0]);
    const lh: u64 = if (room[1] == 0) auto_max_height else @min(auto_max_height, room[1]);
    if (iw <= lw and ih <= lh) return .{ @intCast(iw), @intCast(ih) };
    if (lw * ih <= lh * iw) return .{ @intCast(lw), @intCast(@max(1, ih * lw / iw)) };
    return .{ @intCast(@max(1, iw * lh / ih)), @intCast(lh) };
}

/// Where the image is drawn in a client area: the largest whole rectangle with its
/// proportions, in the middle (an odd pixel left over goes right or below). x and y are
/// its top left corner; the rest of the client area is black.
pub const Place = struct { x: u32, y: u32, w: u32, h: u32 };

pub fn place(image_width: u32, image_height: u32, client_width: u32, client_height: u32) Place {
    const iw: u64 = @max(image_width, 1);
    const ih: u64 = @max(image_height, 1);
    const cw: u64 = @max(client_width, 1);
    const ch: u64 = @max(client_height, 1);
    var rw = cw;
    var rh = ch;
    if (cw * ih <= ch * iw) rh = @max(1, ih * cw / iw) else rw = @max(1, iw * ch / ih);
    return .{ .x = @intCast((cw - rw) / 2), .y = @intCast((ch - rh) / 2), .w = @intCast(rw), .h = @intCast(rh) };
}

/// WINDOW-FIT: how the image is laid out in the client area. `aspect` is `place`. `whole`
/// draws each pixel of the image as a square of a whole number of pixels, the largest
/// that fits, in the middle; where not even one fits (the client area is smaller than
/// the image) it is `aspect`. `stretch` fills the client area, whatever its proportions.
pub const Fit = enum(u8) { aspect = 0, whole = 1, stretch = 2 };

pub fn placeFit(fit: Fit, image_width: u32, image_height: u32, client_width: u32, client_height: u32) Place {
    const cw: u32 = @max(client_width, 1);
    const ch: u32 = @max(client_height, 1);
    switch (fit) {
        .aspect => {},
        .stretch => return .{ .x = 0, .y = 0, .w = cw, .h = ch },
        .whole => {
            const iw: u32 = @max(image_width, 1);
            const ih: u32 = @max(image_height, 1);
            const factor = @min(cw / iw, ch / ih);
            if (factor >= 1) return .{ .x = (cw - iw * factor) / 2, .y = (ch - ih * factor) / 2, .w = iw * factor, .h = ih * factor };
        },
    }
    return place(image_width, image_height, client_width, client_height);
}

test "placeFit lays the image out by whole factors, or fills the client area" {
    // 320 by 200 in 1000 by 700: 3 times fits (960 by 600), 4 times does not.
    try std.testing.expectEqual(Place{ .x = 20, .y = 50, .w = 960, .h = 600 }, placeFit(.whole, 320, 200, 1000, 700));
    // Exactly once, and an odd pixel left over goes right or below.
    try std.testing.expectEqual(Place{ .x = 0, .y = 0, .w = 320, .h = 200 }, placeFit(.whole, 320, 200, 321, 201));
    // Smaller than the image: as aspect.
    try std.testing.expectEqual(place(320, 200, 300, 300), placeFit(.whole, 320, 200, 300, 300));
    try std.testing.expectEqual(Place{ .x = 0, .y = 0, .w = 1000, .h = 700 }, placeFit(.stretch, 320, 200, 1000, 700));
    try std.testing.expectEqual(place(320, 200, 1000, 700), placeFit(.aspect, 320, 200, 1000, 700));
    try std.testing.expectEqual(Place{ .x = 0, .y = 0, .w = 1, .h = 1 }, placeFit(.whole, 0, 0, 0, 0));
    try std.testing.expectEqual(Place{ .x = 0, .y = 0, .w = 1, .h = 1 }, placeFit(.stretch, 0, 0, 0, 0));
    // The largest sizes stay inside the client area.
    try std.testing.expectEqual(Place{ .x = 8191, .y = 8191, .w = 49152, .h = 49152 }, placeFit(.whole, 16384, 16384, 65535, 49152 + 16383));
}

/// The image's pixel (along one side) that output pixel d of the drawn rectangle shows:
/// nearest neighbour, floor(d × image / drawn), the same for enlarging and shrinking.
pub fn source(d: u32, image: u32, drawn: u32) u32 {
    return @intCast(@as(u64, d) * image / @max(drawn, 1));
}

/// The image's pixel under a point of the client area, from where the image is drawn:
/// floor((p - start) × image / drawn), outside the image beyond its edges (not clamped).
pub fn imagePixel(p: i64, start: u32, image: u32, drawn: u32) i64 {
    return @divFloor((p - start) * @as(i64, image), @max(drawn, 1));
}

/// The image's column for each output column of a drawn width: `columns` gets
/// drawn_width entries.
pub fn sourceColumns(columns: []u32, image_width: u32, drawn_width: u32) void {
    for (columns[0..drawn_width], 0..) |*column, dx| column.* = source(@intCast(dx), image_width, drawn_width);
}

/// Draws output rows first_row up to first_row + rows of the image shown at
/// drawn_width × drawn_height into `out` (rows × drawn_width pixels), by the
/// nearest-neighbour rule of `source`; `columns` comes from sourceColumns. Drawing a
/// band of rows at a time keeps the memory small however large the window is.
pub fn scaleRows(image: []const u32, image_width: u32, image_height: u32, out: []u32, drawn_width: u32, drawn_height: u32, columns: []const u32, first_row: u32, rows: u32) void {
    for (0..rows) |index| {
        const dy: u32 = first_row + @as(u32, @intCast(index));
        const row = image[@as(usize, source(dy, image_height, drawn_height)) * image_width ..][0..image_width];
        const target = out[index * drawn_width ..][0..drawn_width];
        for (target, columns[0..drawn_width]) |*pixel, column| pixel.* = row[column];
    }
}

/// A client area moved from a screen of one DPI to another: each side scaled by
/// new / old, rounded to the nearest pixel, at least 1 and at most 16384 × 4.
pub fn dpiScaled(client: [2]u32, old_dpi: u32, new_dpi: u32) [2]u32 {
    var result: [2]u32 = undefined;
    for (&result, client) |*side, value| {
        const scaled = (@as(u64, value) * new_dpi + @max(old_dpi, 1) / 2) / @max(old_dpi, 1);
        side.* = @intCast(std.math.clamp(scaled, 1, 16384 * 4));
    }
    return result;
}

test "dpiScaled scales the client area by the DPIs' ratio" {
    try std.testing.expectEqual([2]u32{ 960, 600 }, dpiScaled(.{ 640, 400 }, 96, 144));
    try std.testing.expectEqual([2]u32{ 640, 400 }, dpiScaled(.{ 960, 600 }, 144, 96));
    // 1365 × 96 / 144 = 910, 1024 × 96 / 144 = 682.7 → 683.
    try std.testing.expectEqual([2]u32{ 910, 683 }, dpiScaled(.{ 1365, 1024 }, 144, 96));
    try std.testing.expectEqual([2]u32{ 1, 1 }, dpiScaled(.{ 0, 0 }, 96, 144));
}

test "place centres the largest rectangle with the image's proportions" {
    try std.testing.expectEqual(Place{ .x = 0, .y = 0, .w = 640, .h = 400 }, place(320, 200, 640, 400));
    try std.testing.expectEqual(Place{ .x = 0, .y = 50, .w = 640, .h = 400 }, place(320, 200, 640, 500));
    try std.testing.expectEqual(Place{ .x = 80, .y = 0, .w = 640, .h = 400 }, place(320, 200, 800, 400));
    // An odd pixel left over goes right.
    try std.testing.expectEqual(Place{ .x = 0, .y = 0, .w = 3, .h = 3 }, place(1, 1, 4, 3));
    // cw × ih > ch × iw by a little: the height limits it, though floor(ih × cw / iw)
    // would also be ch.
    try std.testing.expectEqual(Place{ .x = 0, .y = 0, .w = 99, .h = 100 }, place(100, 101, 100, 100));
    try std.testing.expectEqual(Place{ .x = 0, .y = 0, .w = 1, .h = 1 }, place(0, 0, 0, 0));
}

test "source and imagePixel use the nearest neighbour both ways" {
    // 3 pixels drawn in 7: 0 0 0 1 1 2 2.
    const expected = [_]u32{ 0, 0, 0, 1, 1, 2, 2 };
    for (expected, 0..) |e, d| try std.testing.expectEqual(e, source(@intCast(d), 3, 7));
    // 7 pixels drawn in 3: 0 2 4.
    for ([_]u32{ 0, 2, 4 }, 0..) |e, d| try std.testing.expectEqual(e, source(@intCast(d), 7, 3));
    try std.testing.expectEqual(@as(i64, 0), imagePixel(10, 10, 3, 7));
    try std.testing.expectEqual(@as(i64, 2), imagePixel(16, 10, 3, 7));
    try std.testing.expectEqual(@as(i64, 3), imagePixel(17, 10, 3, 7));
    try std.testing.expectEqual(@as(i64, -1), imagePixel(9, 10, 3, 7));
}

test "scaleRows draws each output pixel from its source pixel, a band at a time" {
    const image = [_]u32{ 1, 2, 3, 4, 5, 6 }; // 3 by 2
    var columns: [5]u32 = undefined;
    sourceColumns(&columns, 3, 5);
    var out: [5 * 3]u32 = undefined;
    scaleRows(&image, 3, 2, &out, 5, 3, &columns, 0, 3);
    try std.testing.expectEqualSlices(u32, &.{ 1, 1, 2, 2, 3, 1, 1, 2, 2, 3, 4, 4, 5, 5, 6 }, &out);
    // The last row alone gives the same as in the whole.
    var band: [5]u32 = undefined;
    scaleRows(&image, 3, 2, &band, 5, 3, &columns, 2, 1);
    try std.testing.expectEqualSlices(u32, out[10..15], &band);
    // Shrinking: 4 by 4 shown at 2 by 2 takes pixels 0 and 2 of each side.
    const big = [_]u32{ 0, 1, 2, 3, 10, 11, 12, 13, 20, 21, 22, 23, 30, 31, 32, 33 };
    var small_columns: [2]u32 = undefined;
    sourceColumns(&small_columns, 4, 2);
    var small: [4]u32 = undefined;
    scaleRows(&big, 4, 4, &small, 2, 2, &small_columns, 0, 2);
    try std.testing.expectEqualSlices(u32, &.{ 0, 2, 20, 22 }, &small);
}

test "place stays within the client area at the largest sizes" {
    const p = place(1, 1, 16384, 16384);
    try std.testing.expectEqual(Place{ .x = 0, .y = 0, .w = 16384, .h = 16384 }, p);
    const q = place(16384, 1, std.math.maxInt(i32), 3);
    try std.testing.expectEqual(Place{ .x = (std.math.maxInt(i32) - 49152) / 2, .y = 0, .w = 49152, .h = 3 }, q);
}

test "autoClientSize keeps an image that fits and shrinks one that does not" {
    const unknown = [2]u32{ 0, 0 };
    try std.testing.expectEqual([2]u32{ 320, 200 }, autoClientSize(320, 200, unknown));
    try std.testing.expectEqual([2]u32{ 1600, 1200 }, autoClientSize(1600, 1200, unknown));
    try std.testing.expectEqual([2]u32{ 1600, 900 }, autoClientSize(3200, 1800, unknown));
    try std.testing.expectEqual([2]u32{ 900, 1200 }, autoClientSize(1800, 2400, unknown));
    // 1600 * 1201 > 1200 * 1601: the height limits it.
    try std.testing.expectEqual([2]u32{ 1599, 1200 }, autoClientSize(1601, 1201, unknown));
    try std.testing.expectEqual([2]u32{ 1600, 1 }, autoClientSize(100000, 1, unknown));
    try std.testing.expectEqual([2]u32{ 1, 1200 }, autoClientSize(1, 100000, unknown));
    try std.testing.expectEqual([2]u32{ 1, 1 }, autoClientSize(0, 0, unknown));
}

test "autoClientSize also fits in the work area's room" {
    // A 1920 by 1080 screen at 150%: about 1904 by 993 for the client area.
    try std.testing.expectEqual([2]u32{ 1324, 993 }, autoClientSize(1600, 1200, .{ 1904, 993 }));
    try std.testing.expectEqual([2]u32{ 640, 480 }, autoClientSize(640, 480, .{ 1904, 993 }));
    try std.testing.expectEqual([2]u32{ 800, 450 }, autoClientSize(1600, 900, .{ 800, 0 }));
    try std.testing.expectEqual([2]u32{ 1066, 600 }, autoClientSize(1600, 900, .{ 0, 600 }));
    try std.testing.expectEqual([2]u32{ 1, 1 }, autoClientSize(1000, 1000, .{ 1, 1 }));
}

/// Root-coordinate rectangles; origins may be negative on multi-monitor desktops.
pub const ScreenRect = struct { x: i64, y: i64, w: u32, h: u32 };

fn overlap(a: ScreenRect, b: ScreenRect) [2]u32 {
    return .{
        @intCast(@max(0, @min(a.x + a.w, b.x + b.w) - @max(a.x, b.x))),
        @intCast(@max(0, @min(a.y + a.h, b.y + b.h) - @max(a.y, b.y))),
    };
}

pub fn selectMonitor(monitors: []const ScreenRect, target: ScreenRect) ?ScreenRect {
    var selected: ?ScreenRect = null;
    var largest: u64 = 0;
    for (monitors) |monitor| {
        const size = overlap(monitor, target);
        const area = @as(u64, size[0]) * size[1];
        if (area > largest) {
            selected = monitor;
            largest = area;
        }
    }
    return selected;
}

pub fn workRoom(monitor: ScreenRect, work: ScreenRect) [2]u32 {
    const size = overlap(monitor, work);
    // Zero means unknown to autoClientSize; a monitor with no usable intersection
    // must instead be limited to the smallest possible client area.
    return .{ @max(1, size[0]), @max(1, size[1]) };
}

test "monitor selection and work area on unequal and negative-origin displays" {
    const monitors = [_]ScreenRect{
        .{ .x = -1280, .y = 0, .w = 1280, .h = 720 },
        .{ .x = 0, .y = 0, .w = 2560, .h = 1440 },
    };
    const work: ScreenRect = .{ .x = -1280, .y = 30, .w = 3840, .h = 1410 };
    const small = selectMonitor(&monitors, .{ .x = -1000, .y = 100, .w = 600, .h = 400 }).?;
    try std.testing.expectEqual(monitors[0], small);
    try std.testing.expectEqual([2]u32{ 1280, 690 }, workRoom(small, work));
    try std.testing.expectEqual([2]u32{ 920, 690 }, autoClientSize(1600, 1200, workRoom(small, work)));
    try std.testing.expectEqual(monitors[1], selectMonitor(&monitors, .{ .x = -100, .y = 100, .w = 600, .h = 400 }).?);
    try std.testing.expectEqual(monitors[0], selectMonitor(&monitors, .{ .x = -1, .y = 0, .w = 1, .h = 1 }).?);
    try std.testing.expectEqual(monitors[1], selectMonitor(&monitors, .{ .x = 0, .y = 0, .w = 1, .h = 1 }).?);
    try std.testing.expectEqual(@as(?ScreenRect, null), selectMonitor(&monitors, .{ .x = 3000, .y = 0, .w = 1, .h = 1 }));
    try std.testing.expectEqual([2]u32{ 1, 1 }, workRoom(small, .{ .x = 3000, .y = 2000, .w = 100, .h = 100 }));
}
