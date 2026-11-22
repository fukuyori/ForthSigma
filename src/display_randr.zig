//! The replies of the X RandR extension that tell of the displays (tque 1258), read as
//! bytes, without a connection: host_display_linux.zig asks the server and gives the
//! replies here. All numbers are little-endian: the connection of host_x11.zig asks the
//! server for that byte order on every machine.

const std = @import("std");
const display_info = @import("core/display_info.zig");

fn get16(bytes: []const u8, offset: usize) u16 {
    return std.mem.readInt(u16, bytes[offset..][0..2], .little);
}

fn get32(bytes: []const u8, offset: usize) u32 {
    return std.mem.readInt(u32, bytes[offset..][0..4], .little);
}

/// A monitor of RRGetMonitors: its name (an atom), its place and size in pixels of the X
/// screen, and its first output, by which its refresh rate is found.
pub const Monitor = struct {
    name: u32 = 0,
    primary: bool = false,
    x: i32 = 0,
    y: i32 = 0,
    w: u32 = 0,
    h: u32 = 0,
    output: ?u32 = null,
};

/// The monitors of an RRGetMonitors reply; how many were put into `out`. A reply cut
/// short gives those that are whole.
pub fn monitors(reply: []const u8, out: []Monitor) usize {
    if (reply.len < 32 or reply[0] != 1) return 0;
    const told = get32(reply, 12);
    var offset: usize = 32;
    var count: usize = 0;
    while (count < told and count < out.len and offset + 24 <= reply.len) {
        const outputs: usize = get16(reply, offset + 6);
        if (offset + 24 + outputs * 4 > reply.len) break;
        out[count] = .{
            .name = get32(reply, offset),
            .primary = reply[offset + 4] != 0,
            .x = @as(i16, @bitCast(get16(reply, offset + 8))),
            .y = @as(i16, @bitCast(get16(reply, offset + 10))),
            .w = get16(reply, offset + 12),
            .h = get16(reply, offset + 14),
            .output = if (outputs != 0) get32(reply, offset + 24) else null,
        };
        count += 1;
        offset += 24 + outputs * 4;
    }
    return count;
}

/// The CRTC an output shows by, of an RRGetOutputInfo reply; null when it shows by none
/// or the reply tells of a failure.
pub fn outputCrtc(reply: []const u8) ?u32 {
    if (reply.len < 36 or reply[0] != 1 or reply[1] != 0) return null;
    const crtc = get32(reply, 12);
    return if (crtc != 0) crtc else null;
}

/// The mode a CRTC shows, of an RRGetCrtcInfo reply; null when it shows none.
pub fn crtcMode(reply: []const u8) ?u32 {
    if (reply.len < 32 or reply[0] != 1 or reply[1] != 0) return null;
    const mode = get32(reply, 20);
    return if (mode != 0) mode else null;
}

/// The time the configuration was set, of an RRGetScreenResourcesCurrent reply, which
/// RRGetOutputInfo and RRGetCrtcInfo are asked with.
pub fn configTime(resources: []const u8) u32 {
    return if (resources.len >= 32) get32(resources, 12) else 0;
}

const double_scan: u32 = 0x20;
const interlace: u32 = 0x10;

/// The refresh rate of a mode as a fraction in its smallest terms: the dot clock by the
/// dots of a whole frame; a double-scanned mode draws each line twice, an interlaced one
/// half the lines a field. 0 0 when it cannot be told.
pub fn rate(dot_clock: u32, h_total: u16, v_total: u16, flags: u32) [2]u32 {
    var numerator: u64 = dot_clock;
    var denominator: u64 = @as(u64, h_total) * v_total;
    if (flags & double_scan != 0) denominator *= 2;
    if (flags & interlace != 0) numerator *= 2;
    if (numerator == 0 or denominator == 0) return .{ 0, 0 };
    const divisor = std.math.gcd(numerator, denominator);
    numerator /= divisor;
    denominator /= divisor;
    if (numerator > std.math.maxInt(u32) or denominator > std.math.maxInt(u32)) return .{ 0, 0 };
    return .{ @intCast(numerator), @intCast(denominator) };
}

/// The refresh rate of mode `id` among the modes of an RRGetScreenResourcesCurrent
/// reply; 0 0 when the mode is not there.
pub fn modeRate(resources: []const u8, id: u32) [2]u32 {
    if (resources.len < 32 or resources[0] != 1) return .{ 0, 0 };
    const crtcs: usize = get16(resources, 16);
    const outputs: usize = get16(resources, 18);
    const modes: usize = get16(resources, 20);
    var offset = 32 + (crtcs + outputs) * 4;
    for (0..modes) |_| {
        if (offset + 32 > resources.len) break;
        if (get32(resources, offset) == id) {
            return rate(get32(resources, offset + 8), get16(resources, offset + 16), get16(resources, offset + 24), get32(resources, offset + 28));
        }
        offset += 32;
    }
    return .{ 0, 0 };
}

/// Puts the monitors into the snapshot as DISPLAYS gives them: places from the top left
/// corner of the primary monitor (the first, when none is marked), the work area as the
/// part of `work` (the desktop's, in pixels of the X screen) inside each monitor (of no
/// width and height when none of it is inside), or the whole monitor when the window
/// manager tells none. `rates` holds a refresh rate for
/// each monitor. The scale is not told: the X server does not know it.
pub fn place(out: *display_info.Snapshot, list: []const Monitor, rates: []const [2]u32, work: ?[4]i32) void {
    if (list.len == 0) return;
    var first: usize = 0;
    for (list, 0..) |monitor, index| {
        if (monitor.primary) {
            first = index;
            break;
        }
    }
    const origin = [2]i32{ list[first].x, list[first].y };
    for (list, 0..) |monitor, index| {
        const rect = [4]i32{ monitor.x - origin[0], monitor.y - origin[1], @intCast(monitor.w), @intCast(monitor.h) };
        var area = rect;
        if (work) |desktop| {
            // In 64 bits: the window manager's numbers may be any 32 bits.
            const left = @max(@as(i64, monitor.x), desktop[0]);
            const top = @max(@as(i64, monitor.y), desktop[1]);
            const right = @min(@as(i64, monitor.x) + monitor.w, @as(i64, desktop[0]) + desktop[2]);
            const bottom = @min(@as(i64, monitor.y) + monitor.h, @as(i64, desktop[1]) + desktop[3]);
            // The ends are inside the monitor when the part is not empty, so they fit.
            area = if (right > left and bottom > top)
                .{ @intCast(left - origin[0]), @intCast(top - origin[1]), @intCast(right - left), @intCast(bottom - top) }
            else
                .{ rect[0], rect[1], 0, 0 };
        }
        out.add(.{
            // The monitor's name tells it apart; 0 names none, so the names start at 1.
            .id = @as(u64, monitor.name) + 1,
            .rect = rect,
            .work = area,
            .hz = if (index < rates.len) rates[index] else .{ 0, 0 },
            .primary = index == first,
        });
    }
}

fn put16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .little);
}

fn put32(bytes: []u8, offset: usize, value: u32) void {
    std.mem.writeInt(u32, bytes[offset..][0..4], value, .little);
}

test "the monitors of an RRGetMonitors reply" {
    // Two monitors: the second primary, left of the first, with two outputs.
    var reply: [32 + 28 + 32]u8 = @splat(0);
    reply[0] = 1;
    put32(&reply, 12, 2);
    put32(&reply, 16, 3);
    put32(&reply, 32, 0x101); // name
    put16(&reply, 32 + 6, 1); // one output
    put16(&reply, 32 + 8, 1920);
    put16(&reply, 32 + 10, 0);
    put16(&reply, 32 + 12, 2560);
    put16(&reply, 32 + 14, 1440);
    put32(&reply, 32 + 24, 0x55);
    const second = 32 + 28;
    put32(&reply, second, 0x102);
    reply[second + 4] = 1; // primary
    put16(&reply, second + 6, 2);
    put16(&reply, second + 8, @bitCast(@as(i16, -5)));
    put16(&reply, second + 10, 55);
    put16(&reply, second + 12, 1920);
    put16(&reply, second + 14, 1080);
    put32(&reply, second + 24, 0x66);
    put32(&reply, second + 28, 0x77);
    var list: [4]Monitor = undefined;
    try std.testing.expectEqual(@as(usize, 2), monitors(&reply, &list));
    try std.testing.expectEqual(Monitor{ .name = 0x101, .x = 1920, .y = 0, .w = 2560, .h = 1440, .output = 0x55 }, list[0]);
    try std.testing.expectEqual(Monitor{ .name = 0x102, .primary = true, .x = -5, .y = 55, .w = 1920, .h = 1080, .output = 0x66 }, list[1]);
    // Room for one, a reply cut short, and one that is no reply.
    try std.testing.expectEqual(@as(usize, 1), monitors(&reply, list[0..1]));
    try std.testing.expectEqual(@as(usize, 1), monitors(reply[0 .. reply.len - 4], &list));
    try std.testing.expectEqual(@as(usize, 0), monitors(reply[0..20], &list));
    reply[0] = 0;
    try std.testing.expectEqual(@as(usize, 0), monitors(&reply, &list));
}

test "the refresh rate of a mode" {
    // 1920 by 1080 at 148.5 MHz, 2200 by 1125 dots a frame: 60 Hz.
    try std.testing.expectEqual([2]u32{ 60, 1 }, rate(148_500_000, 2200, 1125, 0));
    // A rate that is no whole number stays a fraction: 60000/1001 is 59.94 Hz.
    try std.testing.expectEqual([2]u32{ 60000, 1001 }, rate(6_000_000, 1001, 100, 0));
    // Interlaced: two fields a frame. Double scan: each line twice.
    try std.testing.expectEqual([2]u32{ 60, 1 }, rate(74_250_000, 2200, 1125, interlace));
    try std.testing.expectEqual([2]u32{ 30, 1 }, rate(148_500_000, 2200, 1125, double_scan));
    try std.testing.expectEqual([2]u32{ 0, 0 }, rate(0, 2200, 1125, 0));
    try std.testing.expectEqual([2]u32{ 0, 0 }, rate(148_500_000, 0, 1125, 0));
}

test "a mode's rate among the screen's resources, and the replies of an output and a CRTC" {
    // One CRTC, two outputs, two modes.
    var resources: [32 + 12 + 64]u8 = @splat(0);
    resources[0] = 1;
    put32(&resources, 12, 0xABCD);
    put16(&resources, 16, 1);
    put16(&resources, 18, 2);
    put16(&resources, 20, 2);
    const modes = 32 + 12;
    put32(&resources, modes, 0x200);
    put32(&resources, modes + 8, 25_175_000);
    put16(&resources, modes + 16, 800);
    put16(&resources, modes + 24, 525);
    put32(&resources, modes + 32, 0x201);
    put32(&resources, modes + 32 + 8, 148_500_000);
    put16(&resources, modes + 32 + 16, 2200);
    put16(&resources, modes + 32 + 24, 1125);
    try std.testing.expectEqual(@as(u32, 0xABCD), configTime(&resources));
    try std.testing.expectEqual([2]u32{ 60, 1 }, modeRate(&resources, 0x201));
    try std.testing.expectEqual([2]u32{ 5035, 84 }, modeRate(&resources, 0x200)); // 59.94 Hz
    try std.testing.expectEqual([2]u32{ 0, 0 }, modeRate(&resources, 0x999));
    try std.testing.expectEqual([2]u32{ 0, 0 }, modeRate(resources[0 .. modes + 40], 0x201));

    var output: [36]u8 = @splat(0);
    output[0] = 1;
    put32(&output, 12, 0x40);
    try std.testing.expectEqual(@as(?u32, 0x40), outputCrtc(&output));
    put32(&output, 12, 0);
    try std.testing.expectEqual(@as(?u32, null), outputCrtc(&output));
    output[1] = 1; // a status that tells of a failure
    put32(&output, 12, 0x40);
    try std.testing.expectEqual(@as(?u32, null), outputCrtc(&output));

    var crtc: [32]u8 = @splat(0);
    crtc[0] = 1;
    put32(&crtc, 20, 0x201);
    try std.testing.expectEqual(@as(?u32, 0x201), crtcMode(&crtc));
    put32(&crtc, 20, 0);
    try std.testing.expectEqual(@as(?u32, null), crtcMode(&crtc));
}

test "the monitors are placed from the primary monitor's corner, with the work area inside each" {
    const list = [_]Monitor{
        .{ .name = 7, .x = 0, .y = 55, .w = 1920, .h = 1080 },
        .{ .name = 8, .primary = true, .x = 1920, .y = 0, .w = 2560, .h = 1440 },
    };
    const rates = [_][2]u32{ .{ 60, 1 }, .{ 5996, 100 } };
    var snapshot = display_info.Snapshot{};
    // The desktop's work area leaves 40 pixels at the bottom of the X screen (1495 high).
    place(&snapshot, &list, &rates, .{ 0, 0, 4480, 1455 });
    try std.testing.expectEqual(@as(usize, 2), snapshot.count);
    try std.testing.expectEqual([4]i32{ -1920, 55, 1920, 1080 }, snapshot.items[0].rect);
    try std.testing.expectEqual([4]i32{ -1920, 55, 1920, 1080 }, snapshot.items[0].work);
    try std.testing.expectEqual([4]i32{ 0, 0, 2560, 1440 }, snapshot.items[1].rect);
    try std.testing.expectEqual([4]i32{ 0, 0, 2560, 1440 }, snapshot.items[1].work);
    try std.testing.expect(!snapshot.items[0].primary and snapshot.items[1].primary);
    try std.testing.expectEqual([2]u32{ 60, 1 }, snapshot.items[0].hz);
    try std.testing.expectEqual([2]u32{ 0, 0 }, snapshot.items[0].scale);
    try std.testing.expectEqual(@as(u64, 8), snapshot.items[0].id);

    // A task bar of 48 pixels at the bottom of the lower monitor; no monitor marked
    // primary: the first is.
    const plain = [_]Monitor{ .{ .name = 1, .x = 0, .y = 0, .w = 800, .h = 600 }, .{ .name = 2, .x = 0, .y = 600, .w = 800, .h = 600 } };
    snapshot = .{};
    place(&snapshot, &plain, &.{}, .{ 0, 0, 800, 1152 });
    try std.testing.expect(snapshot.items[0].primary and !snapshot.items[1].primary);
    try std.testing.expectEqual([4]i32{ 0, 600, 800, 552 }, snapshot.items[1].work);
    try std.testing.expectEqual([2]u32{ 0, 0 }, snapshot.items[1].hz);
    // Without a work area: the whole monitor. A work area that misses a monitor: no
    // width and height there. Numbers at the ends of 32 bits do not overflow.
    snapshot = .{};
    place(&snapshot, &plain, &.{}, null);
    try std.testing.expectEqual([4]i32{ 0, 600, 800, 600 }, snapshot.items[1].work);
    snapshot = .{};
    place(&snapshot, &plain, &.{}, .{ 0, 0, 800, 600 });
    try std.testing.expectEqual([4]i32{ 0, 0, 800, 600 }, snapshot.items[0].work);
    try std.testing.expectEqual([4]i32{ 0, 600, 0, 0 }, snapshot.items[1].work);
    snapshot = .{};
    place(&snapshot, &plain, &.{}, .{ 2147483647, 2147483647, 2147483647, 2147483647 });
    try std.testing.expectEqual([4]i32{ 0, 0, 0, 0 }, snapshot.items[0].work);
    snapshot = .{};
    place(&snapshot, &plain, &.{}, .{ -2147483648, -2147483648, 2147483647, 2147483647 });
    try std.testing.expectEqual([4]i32{ 0, 600, 0, 0 }, snapshot.items[1].work);
    snapshot = .{};
    place(&snapshot, &plain, &.{}, .{ -100, 700, 2147483647, 100 });
    try std.testing.expectEqual([4]i32{ 0, 700, 800, 100 }, snapshot.items[1].work);
    snapshot = .{};
    place(&snapshot, &.{}, &.{}, null);
    try std.testing.expectEqual(@as(usize, 0), snapshot.count);
}
