//! Checked native local calendar conversion; no libc pointers escape to the VM.
const std = @import("std");
const builtin = @import("builtin");
const c = @import("c_time");
const forth = @import("forth.zig");
const map = @import("core/memory_map.zig");
const windows = builtin.os.tag == .windows;
fn ordinal(parts: c.struct_tm) forth.Double {
    const previous = @as(forth.Double, parts.tm_year) + 1899;
    return previous * 365 + @divFloor(previous, 4) - @divFloor(previous, 100) + @divFloor(previous, 400) + parts.tm_yday;
}
fn calendarOffset(local: c.struct_tm, utc: c.struct_tm) forth.RuntimeError!forth.Cell {
    const offset = (ordinal(local) - ordinal(utc)) * 86400 +
        (@as(forth.Double, local.tm_hour) - utc.tm_hour) * 3600 +
        (@as(forth.Double, local.tm_min) - utc.tm_min) * 60 +
        (@as(forth.Double, local.tm_sec) - utc.tm_sec);
    return std.math.cast(forth.Cell, offset) orelse error.ResultOutOfRange;
}
fn conversionFailure() forth.RuntimeError {
    return if (std.c._errno().* == c.EOVERFLOW) error.ResultOutOfRange else error.HostFailed;
}
pub fn convert(_: ?*anyopaque, seconds: forth.Double, buffer: []u8) forth.RuntimeError!forth.ZonedTime {
    const instant = std.math.cast(c.time_t, seconds) orelse return error.ResultOutOfRange;
    var local: c.struct_tm = undefined;
    var utc: c.struct_tm = undefined;
    if (windows) {
        const code = c.localtime_s(&local, &instant);
        if (code != 0) return if (code == 22 or code == 34) error.ResultOutOfRange else error.HostFailed;
    } else {
        std.c._errno().* = 0;
        if (c.localtime_r(&instant, &local) == null) return conversionFailure();
    }
    if (local.tm_isdst < 0) return error.HostFailed;
    const offset: forth.Cell = if (@hasField(c.struct_tm, "tm_gmtoff")) @intCast(local.tm_gmtoff) else if (@hasField(c.struct_tm, "__tm_gmtoff")) @intCast(local.__tm_gmtoff) else computed: {
        if (windows) {
            const code = c.gmtime_s(&utc, &instant);
            if (code != 0) return if (code == 22 or code == 34) error.ResultOutOfRange else error.HostFailed;
        } else {
            std.c._errno().* = 0;
            if (c.gmtime_r(&instant, &utc) == null) return conversionFailure();
        }
        break :computed try calendarOffset(local, utc);
    };
    const length = if (windows) formatted: {
        // A marker distinguishes an empty name from an insufficient buffer.
        var wide: [map.timezone_buffer_size + 2]u16 = undefined;
        const format = [3:0]u16{ '%', 'Z', '#' };
        const n = c.wcsftime(&wide, wide.len, &format, &local);
        if (n == 0) return error.StringTooLong;
        const text = wide[0 .. n - 1];
        var iterator = std.unicode.Utf16LeIterator.init(text);
        var needed: usize = 0;
        while (iterator.nextCodepoint() catch return error.HostFailed) |code| needed += std.unicode.utf8CodepointSequenceLength(code) catch return error.HostFailed;
        if (needed > buffer.len) return error.StringTooLong;
        break :formatted std.unicode.utf16LeToUtf8(buffer[0..needed], text) catch return error.HostFailed;
    } else formatted: {
        var temporary: [map.timezone_buffer_size + 2]u8 = undefined;
        const n = c.strftime(&temporary, temporary.len, "%Z#", &local);
        if (n == 0) return error.StringTooLong;
        const needed = n - 1;
        if (needed > buffer.len) return error.StringTooLong;
        @memcpy(buffer[0..needed], temporary[0..needed]);
        break :formatted needed;
    };
    return .{ .local = .{ .second = local.tm_sec, .minute = local.tm_min, .hour = local.tm_hour, .day = local.tm_mday, .month = @as(forth.Cell, local.tm_mon) + 1, .year = @as(forth.Cell, local.tm_year) + 1900 }, .dst = local.tm_isdst > 0, .offset = offset, .zone_length = length };
}

test "timezone fallback offset handles year boundaries Gregorian leap days and subhour offsets" {
    var utc = std.mem.zeroes(c.struct_tm);
    var local = utc;
    utc.tm_year = 70;
    utc.tm_yday = 0;
    local.tm_year = 69;
    local.tm_yday = 364;
    local.tm_hour = 19;
    try std.testing.expectEqual(@as(forth.Cell, -18000), try calendarOffset(local, utc));
    local = utc;
    local.tm_hour = 5;
    local.tm_min = 45;
    try std.testing.expectEqual(@as(forth.Cell, 20700), try calendarOffset(local, utc));
    utc.tm_year = 200;
    utc.tm_yday = 0;
    local.tm_year = 199;
    local.tm_yday = 364;
    local.tm_hour = 23;
    local.tm_min = 0;
    try std.testing.expectEqual(@as(forth.Cell, -3600), try calendarOffset(local, utc));
    utc.tm_year = 100;
    utc.tm_yday = 60;
    local = utc;
    local.tm_yday = 59;
    local.tm_hour = 23;
    try std.testing.expectEqual(@as(forth.Cell, -3600), try calendarOffset(local, utc));
}

test "timezone fallback offset distinguishes leap400 and nonleap100 year boundaries" {
    var utc = std.mem.zeroes(c.struct_tm);
    var local = utc;
    utc.tm_year = 101;
    local.tm_year = 100;
    local.tm_yday = 365;
    local.tm_hour = 23;
    try std.testing.expectEqual(@as(forth.Cell, -3600), try calendarOffset(local, utc));
    utc.tm_year = 201;
    local.tm_year = 200;
    local.tm_yday = 364;
    try std.testing.expectEqual(@as(forth.Cell, -3600), try calendarOffset(local, utc));
}
