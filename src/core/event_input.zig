//! Standard EKEY decoding, independent of GRAPHICS event values.
const std = @import("std");
const forth = @import("../forth.zig");
const keys = @import("standard_keys.zig");
const xchar = @import("words_xchar.zig");
const Cell = forth.Cell;

fn next(self: *forth.State, timeout: i32) forth.RuntimeError!?Cell {
    if (self.pending_key != null or self.pending_event_count != 0) return xchar.key(self) catch null;
    if (@import("input_redirect.zig").selected(self) != null) return if (timeout >= 0 and !try @import("input_redirect.zig").ready(self)) null else if (try @import("input_redirect.zig").byte(self)) |value| @as(Cell, value) else null;
    if (self.writer.buffered_key_fn) |buffered| {
        if (try buffered(self.writer.context)) |byte| return byte;
    }
    if (self.pending_standard_event) |event| {
        self.pending_standard_event = null;
        return event;
    }
    if (self.writer.event_key_fn) |callback| return callback(self.writer.context, timeout);
    if (timeout >= 0) {
        const poll_key = self.writer.key_ready_fn orelse return null;
        if (!poll_key(self.writer.context)) return null;
    }
    const callback = self.writer.key_fn orelse return null;
    return @as(Cell, callback(self.writer.context) orelse return null);
}

fn unread(self: *forth.State, bytes: []const u8) forth.RuntimeError!void {
    var index = bytes.len;
    while (index != 0) {
        index -= 1;
        if (@import("input_redirect.zig").selected(self) != null) {
            try @import("input_redirect.zig").unread(self, bytes[index]);
            continue;
        }
        const ordered_host = self.pending_standard_event == null or self.writer.buffered_key_fn != null;
        if (ordered_host and self.writer.unread_fn != null) self.writer.unread_fn.?(self.writer.context, bytes[index]) else {
            self.pending_event_bytes[self.pending_event_count] = bytes[index];
            self.pending_event_count += 1;
        }
    }
}

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

fn sequence(bytes: []const u8) ?Cell {
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

pub fn ready(self: *forth.State) forth.RuntimeError!bool {
    if (@import("input_redirect.zig").selected(self) != null) return @import("input_redirect.zig").ready(self);
    if (self.pending_key != null or self.pending_event_count != 0 or self.pending_standard_event != null) return true;
    const event = (try next(self, 0)) orelse return false;
    if (event >= 0 and event <= 255) {
        const byte = [_]u8{@intCast(event)};
        try unread(self, &byte);
    } else self.pending_standard_event = event;
    return true;
}

pub fn read(self: *forth.State) forth.RuntimeError!Cell {
    const first = (try next(self, -1)) orelse return keys.eof;
    if (first > 255) return first;
    var bytes: [32]u8 = undefined;
    bytes[0] = @intCast(first);
    if (first == 27 and @import("input_redirect.zig").selected(self) == null) {
        const clock = self.writer.monotonic_ms_fn;
        const deadline = if (clock) |now| now(self.writer.context) + 50 else 0;
        var length: usize = 1;
        while (length < bytes.len) {
            const remaining: i32 = if (clock) |now| @intCast(@max(0, deadline - now(self.writer.context))) else 50;
            const value = (next(self, remaining) catch |err| {
                try unread(self, bytes[0..length]);
                return err;
            }) orelse break;
            // Special events are never continuation bytes of a terminal sequence.
            if (value > 255) {
                self.pending_standard_event = value;
                break;
            }
            bytes[length] = @intCast(value);
            length += 1;
            if (length == 2 and value != '[' and value != 'O') break;
            if (length >= 3 and value >= 0x40 and value <= 0x7e) {
                if (sequence(bytes[0..length])) |event| return event;
                break;
            }
        }
        try unread(self, bytes[1..length]);
        return 27;
    }
    const count: usize = switch (first) {
        0xc0...0xdf => 2,
        0xe0...0xef => 3,
        0xf0...0xf7 => 4,
        else => 1,
    };
    var length: usize = 1;
    while (length < count) {
        const value = (next(self, -1) catch |err| {
            try unread(self, bytes[0..length]);
            return err;
        }) orelse break;
        if (value > 255) {
            self.pending_standard_event = value;
            break;
        }
        if (value & 0xc0 != 0x80) {
            const byte = [_]u8{@intCast(value)};
            try unread(self, &byte);
            break;
        }
        bytes[length] = @intCast(value);
        length += 1;
    }
    return xchar.decode(bytes[0..length]).code;
}
