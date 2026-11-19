//! Bounded standard-event decoding. Pure state; native ownership stays at the host.
const std = @import("std");
const map = @import("memory_map.zig");
const defs = @import("defs.zig");
const base = @import("runtime_base.zig");
const keys = @import("standard_keys.zig");
const xchar = @import("words_xchar.zig");
const Cell = map.Cell;
pub const Mouse = struct { column: Cell = 0, row: Cell = 0, buttons: Cell = 0, wheel: Cell = 0 };
pub const Packet = struct { value: Cell, mouse: ?Mouse = null, reset: bool = false };
pub const Result = union(enum) { event: Packet, timeout, eof, restart, failure: Cell };
pub const Source = struct {
    context: ?*anyopaque,
    read_fn: *const fn (?*anyopaque, i32) defs.RuntimeError!Result,
    clock: base.Clock,
    interrupts: bool = true,
    controls: bool = true,
};
pub const Legacy = struct { key: ?u8 = null, bytes: [32]u8 = undefined, count: usize = 0, event: ?Cell = null };
pub const Decoder = struct {
    legacy: Legacy = .{},
    bytes: [32]u8 = undefined,
    length: usize = 0,
    deferred: ?Packet = null,
    eof: bool = false,
    paste: bool = false,
    buttons: u8 = 0,
    last_mouse: Mouse = .{},
    escape_at: ?base.Instant = null,

    pub fn takeByte(self: *Decoder) ?u8 {
        if (self.length == 0) return null;
        const value = self.bytes[0];
        self.consume(1);
        return value;
    }
    pub fn putByte(self: *Decoder, byte: u8) defs.RuntimeError!void {
        if (self.length == self.bytes.len) return error.HostFailed;
        std.mem.copyBackwards(u8, self.bytes[1 .. self.length + 1], self.bytes[0..self.length]);
        self.bytes[0] = byte;
        self.length += 1;
        self.escape_at = null;
    }
    fn consume(self: *Decoder, count: usize) void {
        std.mem.copyForwards(u8, self.bytes[0 .. self.length - count], self.bytes[count..self.length]);
        self.length -= count;
        self.escape_at = null;
    }
    fn finish(self: *Decoder, parsed: Parsed, peek: bool) Packet {
        if (!peek) {
            self.consume(parsed.count);
            if (parsed.paste) |value| self.paste = value;
            if (parsed.buttons) |value| self.buttons = value;
            if (parsed.packet.mouse) |mouse| self.last_mouse = mouse;
        }
        return parsed.packet;
    }
};
const Parsed = struct { packet: Packet, count: usize, paste: ?bool = null, buttons: ?u8 = null, ignored: bool = false };
fn scalar(value: Cell, count: usize) Parsed {
    return .{ .packet = .{ .value = value }, .count = count };
}
fn decodeMouse(bytes: []const u8, before: u8) ?Parsed {
    if (bytes.len < 9 or !std.mem.startsWith(u8, bytes, "\x1b[<")) return null;
    const final = bytes[bytes.len - 1];
    if (final != 'M' and final != 'm') return null;
    var parts = std.mem.splitScalar(u8, bytes[3 .. bytes.len - 1], ';');
    var values: [3]u32 = undefined;
    for (&values) |*value| value.* = std.fmt.parseInt(u32, parts.next() orelse return null, 10) catch return null;
    if (parts.next() != null or values[1] == 0 or values[2] == 0 or values[1] > 1 << 20 or values[2] > 1 << 20) return null;
    const code = values[0];
    const bit: u8 = switch (code & 3) {
        0 => 1,
        1 => 4,
        2 => 2,
        else => 0,
    };
    var buttons = before;
    if (code & (64 | 32) == 0) {
        if (final == 'M') buttons |= bit else buttons &= ~bit;
    } else if (code & 64 == 0) {
        if (code & 3 == 3) buttons = 0 else buttons |= bit;
    }
    const wheel: Cell = if (code & 64 == 0 or final != 'M') 0 else switch (code & 3) {
        0 => 1,
        1 => -1,
        else => 0,
    };
    const mods: Cell = (if (code & 4 != 0) keys.shift else 0) | (if (code & 8 != 0) keys.alt else 0) | (if (code & 16 != 0) keys.ctrl else 0);
    return .{ .ignored = (code & 64 != 0 and code & 3 >= 2) or code & 128 != 0, .packet = .{ .value = keys.mouse | mods, .mouse = .{ .column = values[1] - 1, .row = values[2] - 1, .buttons = buttons, .wheel = wheel } }, .count = bytes.len, .buttons = buttons };
}
fn parse(self: *Decoder, now: base.Instant, ended: bool) ?Parsed {
    if (self.length == 0) return null;
    const bytes = self.bytes[0..self.length];
    if (bytes[0] == 27) {
        const end_paste = "\x1b[201~";
        if (self.paste) {
            const count = @min(bytes.len, end_paste.len);
            if (!std.mem.eql(u8, bytes[0..count], end_paste[0..count])) return scalar(27, 1);
            if (bytes.len == end_paste.len) return .{ .packet = .{ .value = keys.paste_end }, .count = bytes.len, .paste = false };
            return if (ended) scalar(27, 1) else null;
        }
        if (self.escape_at == null) self.escape_at = now;
        const elapsed = @subWithOverflow(now, self.escape_at.?);
        const expired = elapsed[1] != 0 or elapsed[0] >= 50_000_000;
        if (bytes.len == 1) return if (ended or expired) scalar(27, 1) else null;
        if (bytes[1] != '[' and bytes[1] != 'O') return scalar(27, 1);
        if (bytes.len >= 3 and bytes[bytes.len - 1] >= 0x40 and bytes[bytes.len - 1] <= 0x7e) {
            if (std.mem.eql(u8, bytes, "\x1b[201~")) return .{ .packet = .{ .value = keys.paste_end }, .count = bytes.len, .paste = false };
            if (std.mem.eql(u8, bytes, "\x1b[200~")) return .{ .packet = .{ .value = keys.paste_begin }, .count = bytes.len, .paste = true };
            if (decodeMouse(bytes, self.buttons)) |event| return event;
            if (@import("standard_sequence.zig").decode(bytes)) |value| return scalar(value, bytes.len);
            return scalar(27, 1);
        }
        return if (ended or expired or self.length == self.bytes.len) scalar(27, 1) else null;
    }
    const count: usize = switch (bytes[0]) {
        0xc0...0xdf => 2,
        0xe0...0xef => 3,
        0xf0...0xf7 => 4,
        else => 1,
    };
    var length: usize = 1;
    while (length < @min(count, bytes.len) and bytes[length] & 0xc0 == 0x80) : (length += 1) {}
    if (length == bytes.len and length < count and !ended) return null;
    return scalar(xchar.decode(bytes[0..length]).code, length);
}

/// A call owns one deadline. Peek buffers raw input but commits no semantic state.
pub fn read(self: *Decoder, source: Source, milliseconds: i64, peek: bool) defs.RuntimeError!Result {
    const initial = try source.clock.now();
    const deadline = try base.Deadline.afterMilliseconds(initial, milliseconds);
    var work: usize = 0;
    while (true) {
        const now = try source.clock.now();
        if (self.length != 0 and self.bytes[0] == 3 and !self.paste and source.interrupts) {
            self.consume(1);
            return error.UserInterrupt;
        }
        const parsed_value = if (!source.controls and self.length != 0 and self.bytes[0] == 27) scalar(27, 1) else parse(self, now, self.eof);
        if (parsed_value) |parsed| {
            if (parsed.ignored) {
                self.consume(parsed.count);
                continue;
            }
            return .{ .event = self.finish(parsed, peek) };
        }
        if (self.deferred) |packet| {
            if (!peek) {
                self.deferred = null;
                if (packet.mouse) |value| self.last_mouse = value;
            }
            return .{ .event = packet };
        }
        if (self.length == 0) {
            if (self.eof) {
                if (!peek) self.paste = false;
                if (!peek) self.eof = false;
                return .eof;
            }
        }
        if (milliseconds > 0 and deadline.expired(now)) return .timeout;
        var wait_ms: u32 = if (milliseconds == 0) 0 else deadline.remainingMilliseconds(now, std.math.maxInt(i32));
        if (self.escape_at) |started| {
            if (!self.paste) {
                const escape = try base.Deadline.afterMilliseconds(started, 50);
                wait_ms = @min(wait_ms, escape.remainingMilliseconds(now, std.math.maxInt(i32)));
            }
        }
        const waiting: i32 = if (milliseconds < 0 and self.escape_at == null) -1 else @intCast(wait_ms);
        if (milliseconds == 0 and work == 64) return .timeout;
        work += 1;
        const result = try source.read_fn(source.context, waiting);
        switch (result) {
            .event => |packet| {
                self.eof = false;
                if (packet.value >= 0 and packet.value <= 255 and packet.mouse == null) {
                    if (packet.value == 3 and !self.paste and source.interrupts) return error.UserInterrupt;
                    std.debug.assert(self.length < self.bytes.len);
                    // Match the legacy reader: unsigned intermediate avoids a
                    // signed-narrowing no-wrap bug in Zig 0.17 fast builds.
                    const unsigned: map.UCell = @intCast(packet.value);
                    self.bytes[self.length] = @intCast(unsigned);
                    self.length += 1;
                } else self.deferred = packet;
            },
            .eof => self.eof = true,
            .restart => {
                self.paste = false;
                self.buttons = 0;
            },
            .failure => return result,
            .timeout => {
                if (milliseconds == 0) return .timeout;
            },
        }
    }
}
