//! Existing standard key escape decoding shared by both readers.
const std = @import("std");
const keys = @import("standard_keys.zig");
const Cell = @import("memory_map.zig").Cell;
fn letter(byte: u8) ?Cell {
    return switch (byte) {
        'D' => keys.special,
        'C' => keys.special + 1,
        'A' => keys.special + 2,
        'B' => keys.special + 3,
        'H' => keys.special + 4,
        'F' => keys.special + 5,
        'P'...'S' => keys.special + 11 + byte - 'P',
        else => null,
    };
}

pub fn decode(bytes: []const u8) ?Cell {
    if (bytes.len < 3) return null;
    const final = bytes[bytes.len - 1];
    if (bytes[1] == 'O') return if (bytes.len == 3) letter(final) else null;
    if (bytes[1] != '[') return null;
    var numbers = std.mem.splitScalar(u8, bytes[2 .. bytes.len - 1], ';');
    const first = numbers.next().?;
    const number = if (first.len == 0) 1 else std.fmt.parseInt(u32, first, 10) catch return null;
    var modifiers: Cell = 0;
    if (numbers.next()) |parameter| {
        const value = std.fmt.parseInt(u32, parameter, 10) catch return null;
        if (value < 1 or value > 8) return null;
        const bits = value - 1;
        if (bits & 1 != 0) modifiers |= keys.shift;
        if (bits & 2 != 0) modifiers |= keys.alt;
        if (bits & 4 != 0) modifiers |= keys.ctrl;
    }
    if (numbers.next() != null) return null;
    if (final == 'Z' and number == 1) return keys.tab | keys.shift | modifiers;
    const base: Cell = if (final == '~') switch (number) {
        1, 7 => keys.special + 4,
        4, 8 => keys.special + 5,
        5 => keys.special + 6,
        6 => keys.special + 7,
        2 => keys.special + 8,
        3 => keys.special + 9,
        11...15 => keys.special + 11 + number - 11,
        17...21 => keys.special + 16 + number - 17,
        23, 24 => keys.special + 21 + number - 23,
        else => return null,
    } else if (number == 1) letter(final) orelse return null else return null;
    return base | modifiers;
}
