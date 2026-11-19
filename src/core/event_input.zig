//! Standard EKEY decoding, independent of GRAPHICS event values.
const std = @import("std");
const forth = @import("../forth.zig");
const keys = @import("standard_keys.zig");
const xchar = @import("words_xchar.zig");
const Cell = forth.Cell;

// Zig 0.17.0 attaches a signed no-wrap flag when narrowing Cell directly to u8
// in fast builds. Convert to an unsigned cell first so bytes 0x80..0xff survive
// UTF-8 decoding; both casts retain their range checks in checked builds.
fn eventByte(value: Cell) u8 {
    const unsigned: forth.UCell = @intCast(value);
    return @intCast(unsigned);
}

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
        const ready_key = poll_key(self.writer.context);
        if (self.writer.input_error_fn) |check| try check(self.writer.context);
        if (!ready_key) return null;
    }
    const callback = self.writer.key_fn orelse return null;
    const byte = callback(self.writer.context);
    if (self.writer.input_error_fn) |check| try check(self.writer.context);
    return @as(Cell, byte orelse return null);
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

pub fn ready(self: *forth.State) forth.RuntimeError!bool {
    if (self.writer.standard_event_fn != null and @import("input_redirect.zig").selected(self) == null) return switch (try modern(self, 0, true)) {
        .event => true,
        .failure => error.HostFailed,
        else => false,
    };
    if (@import("input_redirect.zig").selected(self) != null) return @import("input_redirect.zig").ready(self);
    if (self.pending_key != null or self.pending_event_count != 0 or self.pending_standard_event != null) return true;
    const event = (try next(self, 0)) orelse return false;
    if (event >= 0 and event <= 255) {
        const byte = [_]u8{eventByte(event)};
        try unread(self, &byte);
    } else self.pending_standard_event = event;
    return true;
}

pub fn read(self: *forth.State) forth.RuntimeError!Cell {
    if (self.writer.standard_event_fn != null and @import("input_redirect.zig").selected(self) == null) return switch (try modern(self, -1, false)) {
        .event => |packet| packet.value,
        .eof => keys.eof,
        .failure => error.HostFailed,
        .timeout, .restart => error.HostFailed,
    };
    const first = (try next(self, -1)) orelse return keys.eof;
    if (first > 255) return first;
    var bytes: [32]u8 = undefined;
    bytes[0] = eventByte(first);
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
            bytes[length] = eventByte(value);
            length += 1;
            if (length == 2 and value != '[' and value != 'O') break;
            if (length >= 3 and value >= 0x40 and value <= 0x7e) {
                if (@import("standard_sequence.zig").decode(bytes[0..length])) |event| return event;
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
            const byte = [_]u8{eventByte(value)};
            try unread(self, &byte);
            break;
        }
        bytes[length] = eventByte(value);
        length += 1;
    }
    return xchar.decode(bytes[0..length]).code;
}

const standard = @import("standard_event.zig");
fn sourceRead(context: ?*anyopaque, timeout: i32) forth.RuntimeError!standard.Result {
    const self: *forth.State = @ptrCast(@alignCast(context.?));
    if (self.pending_key) |byte| {
        self.pending_key = null;
        return .{ .event = .{ .value = byte } };
    }
    if (self.pending_event_count != 0) {
        self.pending_event_count -= 1;
        return .{ .event = .{ .value = self.pending_event_bytes[self.pending_event_count] } };
    }
    if (self.pending_standard_event) |value| {
        self.pending_standard_event = null;
        return .{ .event = .{ .value = value } };
    }
    const callback = self.writer.standard_event_fn orelse return error.HostUnavailable;
    return callback(self.writer.context, timeout);
}
pub fn modern(self: *forth.State, timeout: i64, peek: bool) forth.RuntimeError!standard.Result {
    if (@import("input_redirect.zig").selected(self)) |id| {
        const callback = (try self.fileOps()).event_wait orelse return error.HostUnavailable;
        return callback(self.writer.context, id, timeout);
    }
    if (self.writer.standard_event_fn == null) return error.HostUnavailable;
    const clock = self.writer.standard_clock orelse return error.HostUnavailable;
    return standard.read(&self.standard_input, .{ .context = self, .read_fn = sourceRead, .clock = clock, .interrupts = self.writer.standard_interrupts and @import("input_redirect.zig").selected(self) == null, .controls = @import("input_redirect.zig").selected(self) == null }, timeout, peek);
}

/// Change to a byte API without hiding bytes already fetched by EKEY?.
pub fn beforeBytes(self: *forth.State) forth.RuntimeError!void {
    if (@import("input_redirect.zig").selected(self) != null) return;
    if (self.writer.standard_event_fn != null and self.writer.unread_byte_fn != null) return beforeFileRead(self, @import("memory_map.zig").stdin_fileid);
    if (self.standard_input.length != 0 and (self.pending_key != null or self.pending_event_count != 0)) return;
    try beforeStdinBytes(self);
}
pub fn beforeStdinBytes(self: *forth.State) forth.RuntimeError!void {
    if (self.standard_input.length == 0) {
        self.standard_input.paste = false;
        return;
    }
    if (self.writer.input_error_fn) |check| try check(self.writer.context);
    if (self.writer.unread_byte_fn) |callback| {
        while (self.standard_input.length != 0) {
            const at = self.standard_input.length - 1;
            try callback(self.writer.context, self.standard_input.bytes[at]);
            self.standard_input.length = at;
            self.standard_input.eof = false;
        }
        self.standard_input.escape_at = null;
        self.standard_input.paste = false;
    } else if (self.writer.unread_fn) |callback| {
        // Legacy void pushback has no rejection result: acceptance is its contract.
        while (self.standard_input.length != 0) {
            const at = self.standard_input.length - 1;
            callback(self.writer.context, self.standard_input.bytes[at]);
            self.standard_input.length = at;
            self.standard_input.eof = false;
            if (at == 0) self.standard_input.escape_at = null;
            if (self.writer.input_error_fn) |check| try check(self.writer.context);
        }
        self.standard_input.paste = false;
    }
}

/// Explicit STDIN file operations share its host byte queue too.
pub fn beforeFileRead(self: *forth.State, fileid: Cell) forth.RuntimeError!void {
    if (fileid != @import("memory_map.zig").stdin_fileid or self.writer.standard_event_fn == null) return;
    if (self.writer.input_error_fn) |check| try check(self.writer.context);
    const selected = @import("input_redirect.zig").selected(self) != null;
    var legacy: standard.Legacy = if (selected) self.standard_input.legacy else .{ .key = self.pending_key, .bytes = self.pending_event_bytes, .count = self.pending_event_count, .event = self.pending_standard_event };
    defer {
        if (selected) self.standard_input.legacy = legacy else {
            self.pending_key = legacy.key;
            self.pending_event_bytes = legacy.bytes;
            self.pending_event_count = legacy.count;
            self.pending_standard_event = legacy.event;
        }
    }
    if (legacy.key != null or legacy.count != 0) {
        const push = self.writer.unread_byte_fn orelse return error.HostUnavailable;
        // Legacy storage is a stack: its lowest index is the latest byte.
        while (legacy.count != 0) {
            try push(self.writer.context, legacy.bytes[0]);
            self.standard_input.eof = false;
            std.mem.copyForwards(u8, legacy.bytes[0 .. legacy.count - 1], legacy.bytes[1..legacy.count]);
            legacy.count -= 1;
        }
        if (legacy.key) |byte| {
            try push(self.writer.context, byte);
            self.standard_input.eof = false;
            legacy.key = null;
        }
    }
    try beforeStdinBytes(self);
    if (self.standard_input.length != 0) return error.HostUnavailable;
}

pub fn unreadByte(self: *forth.State, byte: u8) forth.RuntimeError!void {
    if (@import("input_redirect.zig").selected(self) != null) return @import("input_redirect.zig").unread(self, byte);
    if (self.writer.standard_event_fn != null) return self.standard_input.putByte(byte);
    if (self.writer.unread_fn) |callback| callback(self.writer.context, byte) else self.pending_key = byte;
}

pub fn hasStdinBytes(self: *const forth.State) bool {
    if (self.standard_input.length != 0) return true;
    if (@import("input_redirect.zig").selected(self)) |_| return self.standard_input.legacy.key != null or self.standard_input.legacy.count != 0;
    return self.pending_key != null or self.pending_event_count != 0;
}
