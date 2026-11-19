//! Native scan to USB keyboard page 0x07. Altered SDL mapping tables; no SDL dependency.
//
//   Simple DirectMedia Layer
//   Copyright (C) 1997-2026 Sam Lantinga <slouken@libsdl.org>
//
//   This software is provided 'as-is', without any express or implied
//   warranty.  In no event will the authors be held liable for any damages
//   arising from the use of this software.
//
//   Permission is granted to anyone to use this software for any purpose,
//   including commercial applications, and to alter it and redistribute it
//   freely, subject to the following restrictions:
//
//   1. The origin of this software must not be misrepresented; you must not
//      claim that you wrote the original software. If you use this software
//      in a product, an acknowledgment in the product documentation would be
//      appreciated but is not required.
//   2. Altered source versions must be plainly marked as such, and must not be
//      misrepresented as being the original software.
//   3. This notice may not be removed or altered from any source distribution.
const std = @import("std");
pub const windows = [256]u8{ 0, 41, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 45, 46, 42, 43, 20, 26, 8, 21, 23, 28, 24, 12, 18, 19, 47, 48, 40, 224, 4, 22, 7, 9, 10, 11, 13, 14, 15, 51, 52, 53, 225, 49, 29, 27, 6, 25, 5, 17, 16, 54, 55, 56, 229, 85, 226, 44, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 83, 71, 95, 96, 97, 86, 92, 93, 94, 87, 89, 90, 91, 98, 99, 0, 0, 100, 68, 69, 103, 0, 0, 140, 0, 0, 0, 0, 0, 0, 0, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 0, 136, 145, 144, 135, 0, 0, 115, 147, 146, 138, 0, 139, 0, 137, 133, 0, 0, 0, 0, 0, 0, 0, 0, 121, 122, 0, 125, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 123, 124, 0, 0, 0, 88, 228, 0, 0, 127, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 129, 0, 128, 0, 0, 0, 0, 84, 229, 70, 230, 0, 0, 117, 0, 0, 0, 0, 0, 0, 0, 0, 0, 83, 0, 74, 82, 75, 0, 80, 0, 79, 0, 77, 81, 78, 73, 76, 0, 0, 0, 0, 0, 0, 0, 227, 231, 101, 102, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 };
pub const darwin = [128]u8{ 4, 22, 7, 9, 11, 10, 29, 27, 6, 25, 100, 5, 20, 26, 8, 21, 28, 23, 30, 31, 32, 33, 35, 34, 46, 38, 36, 45, 37, 39, 48, 18, 24, 47, 12, 19, 40, 15, 13, 52, 14, 51, 49, 54, 56, 17, 16, 55, 43, 44, 53, 42, 88, 41, 231, 227, 225, 0, 226, 224, 229, 230, 228, 0, 108, 99, 0, 85, 0, 87, 0, 83, 128, 129, 127, 84, 88, 0, 86, 109, 110, 103, 98, 89, 90, 91, 92, 93, 94, 95, 0, 96, 97, 137, 135, 140, 62, 63, 64, 60, 65, 66, 145, 68, 144, 70, 107, 71, 0, 67, 101, 69, 0, 72, 73, 74, 75, 76, 61, 77, 59, 78, 58, 80, 79, 81, 82, 102 };
pub fn windowsScan(make: u8, extended: bool) u8 {
    if (make >= 128 or (make == 0x45 and !extended) or (make == 0x37 and extended)) return 0;
    return windows[@as(usize, make) + (if (extended) @as(usize, 128) else 0)];
}
pub fn darwinScan(code: usize) u8 {
    return if (code < darwin.len) darwin[code] else 0;
}
/// XKB key names describe positions rather than symbols for the current layout.
/// LWIN/RWIN stay unsupported: GNOME (overlay-key) consumes their release before X
/// sees it (tque1090), and the user decided not to use the Windows keys.
pub fn xkbScan(name: [4]u8) u8 {
    const rows = [_]struct { prefix: [2]u8, codes: []const u8 }{
        .{ .prefix = .{ 'A', 'E' }, .codes = &.{ 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 45, 46 } },
        .{ .prefix = .{ 'A', 'D' }, .codes = &.{ 20, 26, 8, 21, 23, 28, 24, 12, 18, 19, 47, 48 } },
        .{ .prefix = .{ 'A', 'C' }, .codes = &.{ 4, 22, 7, 9, 10, 11, 13, 14, 15, 51, 52 } },
        .{ .prefix = .{ 'A', 'B' }, .codes = &.{ 29, 27, 6, 25, 5, 17, 16, 54, 55, 56 } },
    };
    for (rows) |row| if (std.mem.eql(u8, name[0..2], &row.prefix)) {
        const n = std.fmt.parseInt(u8, name[2..], 10) catch return 0;
        if (n > 0 and n <= row.codes.len) return row.codes[n - 1];
    };
    if (name[0] == 'F' and name[1] == 'K') {
        const n = std.fmt.parseInt(u8, name[2..], 10) catch return 0;
        return if (n >= 1 and n <= 12) 57 + n else if (n >= 13 and n <= 24) 104 + n - 13 else 0;
    }
    const names = [_]struct { name: *const [4]u8, scan: u8 }{
        .{ .name = "ESC\x00", .scan = 41 }, .{ .name = "TLDE", .scan = 53 },       .{ .name = "BKSP", .scan = 42 },
        .{ .name = "TAB\x00", .scan = 43 }, .{ .name = "RTRN", .scan = 40 },       .{ .name = "BKSL", .scan = 49 },
        .{ .name = "CAPS", .scan = 57 },    .{ .name = "LFSH", .scan = 225 },      .{ .name = "RTSH", .scan = 229 },
        .{ .name = "LCTL", .scan = 224 },   .{ .name = "RCTL", .scan = 228 },      .{ .name = "LALT", .scan = 226 },
        .{ .name = "RALT", .scan = 230 },   .{ .name = "LWIN", .scan = 0 },        .{ .name = "RWIN", .scan = 0 },
        .{ .name = "SPCE", .scan = 44 },    .{ .name = "MENU", .scan = 101 },      .{ .name = "COMP", .scan = 101 },
        .{ .name = "LSGT", .scan = 100 },   .{ .name = "PRSC", .scan = 70 },       .{ .name = "SCLK", .scan = 71 },
        .{ .name = "PAUS", .scan = 0 },     .{ .name = "INS\x00", .scan = 73 },    .{ .name = "HOME", .scan = 74 },
        .{ .name = "PGUP", .scan = 75 },    .{ .name = "DELE", .scan = 76 },       .{ .name = "END\x00", .scan = 77 },
        .{ .name = "PGDN", .scan = 78 },    .{ .name = "RGHT", .scan = 79 },       .{ .name = "LEFT", .scan = 80 },
        .{ .name = "DOWN", .scan = 81 },    .{ .name = "UP\x00\x00", .scan = 82 }, .{ .name = "NMLK", .scan = 83 },
        .{ .name = "KPDV", .scan = 84 },    .{ .name = "KPMU", .scan = 85 },       .{ .name = "KPSU", .scan = 86 },
        .{ .name = "KPAD", .scan = 87 },    .{ .name = "KPEN", .scan = 88 },       .{ .name = "KP1\x00", .scan = 89 },
        .{ .name = "KP2\x00", .scan = 90 }, .{ .name = "KP3\x00", .scan = 91 },    .{ .name = "KP4\x00", .scan = 92 },
        .{ .name = "KP5\x00", .scan = 93 }, .{ .name = "KP6\x00", .scan = 94 },    .{ .name = "KP7\x00", .scan = 95 },
        .{ .name = "KP8\x00", .scan = 96 }, .{ .name = "KP9\x00", .scan = 97 },    .{ .name = "KP0\x00", .scan = 98 },
        .{ .name = "KPDL", .scan = 99 },    .{ .name = "KPEQ", .scan = 103 },      .{ .name = "AB11", .scan = 135 },
        .{ .name = "HKTG", .scan = 136 },   .{ .name = "AE13", .scan = 137 },      .{ .name = "HENK", .scan = 138 },
        .{ .name = "MUHE", .scan = 139 },
    };
    for (names) |entry| if (std.mem.eql(u8, &name, entry.name)) return entry.scan;
    return 0;
}
test "native positions distinguish sides and keypad without characters" {
    try std.testing.expectEqual(@as(u8, 0), windowsScan(0x45, false));
    try std.testing.expectEqual(@as(u8, 83), windowsScan(0x45, true));
    try std.testing.expectEqual(@as(u8, 0), windowsScan(0x37, true));
    try std.testing.expectEqual(@as(u8, 0), darwinScan(63));
    try std.testing.expectEqual(@as(u8, 4), windowsScan(0x1e, false));
    try std.testing.expectEqual(@as(u8, 224), windowsScan(0x1d, false));
    try std.testing.expectEqual(@as(u8, 228), windowsScan(0x1d, true));
    try std.testing.expectEqual(@as(u8, 88), windowsScan(0x1c, true));
    try std.testing.expectEqual(@as(u8, 4), darwinScan(0));
    try std.testing.expectEqual(@as(u8, 0), darwinScan(57));
    try std.testing.expectEqual(@as(u8, 135), xkbScan("AB11".*));
    try std.testing.expectEqual(@as(u8, 137), xkbScan("AE13".*));
    try std.testing.expectEqual(@as(u8, 101), xkbScan("COMP".*));
    try std.testing.expectEqual(@as(u8, 20), xkbScan("AD01".*));
    try std.testing.expectEqual(@as(u8, 225), xkbScan("LFSH".*));
    try std.testing.expectEqual(@as(u8, 0), xkbScan("XXXX".*));
    try std.testing.expectEqual(@as(u8, 0), xkbScan("LWIN".*));
    try std.testing.expectEqual(@as(u8, 0), xkbScan("RWIN".*));
}
