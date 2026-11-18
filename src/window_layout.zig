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
