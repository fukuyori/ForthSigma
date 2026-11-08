//! The xchar words of gforth (Forth 2012's XCHAR word set and gforth's XC@ and
//! X@+/STRING): characters as UTF-8 in memory and as code points on the stack.
//!
//! Well-formed UTF-8, overlong forms, and surrogates decode to the same values as in
//! gforth. Anything else follows one rule for every word: a byte that cannot start a
//! character, a character cut short (by a byte that does not continue it or by the end
//! of the string), or a value above U+10FFFF is U+FFFD, and only the start byte and the
//! bytes that continue it are taken (one byte for a byte that cannot start a character).
//! Code points above U+10FFFF are written as U+FFFD (3 bytes).

const std = @import("std");
const char_width = @import("char_width.zig");
const defs = @import("defs.zig");
const forth = @import("../forth.zig");
const integer_math = @import("integer_math.zig");
const memory_map = @import("memory_map.zig");
const Builtin = defs.Builtin;
const Cell = memory_map.Cell;
const RuntimeError = defs.RuntimeError;
const State = forth.State;
const UCell = memory_map.UCell;
const truth = integer_math.truth;

pub const replacement: u21 = 0xFFFD;

/// The built-in words this file executes; executeBuiltin dispatches by this list.
pub const words = [_]Builtin{
    .xc_size,     .x_size,         .xc_fetch_plus, .xc_fetch,  .xc_store_plus,          .xc_store_plus_question,
    .xc_comma,    .xchar_plus,     .xchar_minus,   .xemit,     .xkey,                   .xkey_question,
    .x_width,     .xc_width,       .plus_x_string, .x_string_minus, .minus_trailing_garbage, .xhold,
    .ekey_to_xchar, .x_fetch_plus_string,
};

pub const Decoded = struct { code: u21, length: usize, valid: bool };

/// The character at the start of `bytes`, which is not empty.
pub fn decode(bytes: []const u8) Decoded {
    const first = bytes[0];
    if (first < 0x80) return .{ .code = first, .length = 1, .valid = true };
    const more: usize, const bits: u21 = switch (first) {
        0xC0...0xDF => .{ 1, first & 0x1F },
        0xE0...0xEF => .{ 2, first & 0x0F },
        0xF0...0xF7 => .{ 3, first & 0x07 },
        else => return .{ .code = replacement, .length = 1, .valid = false },
    };
    var code: u32 = bits;
    var length: usize = 1;
    while (length <= more) : (length += 1) {
        if (length == bytes.len or bytes[length] & 0xC0 != 0x80) return .{ .code = replacement, .length = length, .valid = false };
        code = (code << 6) | (bytes[length] & 0x3F);
    }
    if (code > 0x10FFFF) return .{ .code = replacement, .length = length, .valid = false };
    return .{ .code = @intCast(code), .length = length, .valid = true };
}

/// The code point to write for `value`: itself, or U+FFFD above U+10FFFF.
fn writable(value: Cell) u21 {
    const code: UCell = @bitCast(value);
    return if (code > 0x10FFFF) replacement else @intCast(code);
}

/// The UTF-8 bytes of `value` (see `writable`), in `buffer`.
pub fn encode(value: Cell, buffer: *[4]u8) []const u8 {
    const code = writable(value);
    const length = std.unicode.utf8CodepointSequenceLength(code) catch unreachable;
    // Surrogates are written as gforth writes them, in the 3-byte form.
    buffer[0] = switch (length) {
        1 => @intCast(code),
        2 => @intCast(0xC0 | (code >> 6)),
        3 => @intCast(0xE0 | (code >> 12)),
        else => @intCast(0xF0 | (code >> 18)),
    };
    var at: usize = 1;
    while (at < length) : (at += 1) {
        const shift: u5 = @intCast(6 * (length - 1 - at));
        buffer[at] = @intCast(0x80 | ((code >> shift) & 0x3F));
    }
    return buffer[0..length];
}

/// XC-SIZE: the bytes `encode` writes.
fn size(value: Cell) usize {
    return std.unicode.utf8CodepointSequenceLength(writable(value)) catch unreachable;
}

/// The bytes from `address` to the end of memory, at most 4: what a character there
/// can take when no length is given (XC@+, XC@, XCHAR+).
fn bytesAt(self: *State, address: Cell) RuntimeError![]const u8 {
    const start = try self.memoryAddress(address, 1);
    return self.memory[start..@min(start + 4, self.memory.len)];
}

fn decodeAt(self: *State, address: Cell) RuntimeError!Decoded {
    return decode(try bytesAt(self, address));
}

/// The bytes of the string `address count`, checked to lie in memory.
fn stringBytes(self: *State, address: Cell, count: Cell) RuntimeError![]const u8 {
    const length = std.math.cast(usize, count) orelse return error.InvalidAddress;
    const start = try self.memoryAddress(address, length);
    return self.memory[start .. start + length];
}

/// X-SIZE: the bytes of the first character of a string; 1 for an empty string, as in
/// gforth.
fn firstSize(bytes: []const u8) usize {
    return if (bytes.len == 0) 1 else decode(bytes).length;
}

/// Where the last character of a non-empty string starts, and whether it is a whole
/// character that ends the string.
fn lastCharacter(bytes: []const u8) struct { start: usize, whole: bool } {
    var start = bytes.len - 1;
    while (start > 0 and bytes.len - start < 4 and bytes[start] & 0xC0 == 0x80) start -= 1;
    const found = decode(bytes[start..]);
    if (found.length == bytes.len - start) return .{ .start = start, .whole = found.valid };
    return .{ .start = bytes.len - 1, .whole = decode(bytes[bytes.len - 1 ..]).valid };
}

/// The next byte of the terminal input: first a byte XKEY left when the host cannot
/// take it back (see `unread_fn`), else from the host.
fn nextKey(self: *State) RuntimeError!u8 {
    if (self.pending_key) |byte| {
        self.pending_key = null;
        return byte;
    }
    const key_fn = self.writer.key_fn orelse return error.InputUnavailable;
    return key_fn(self.writer.context) orelse error.InputUnavailable;
}

/// KEY, which gives first the byte XKEY left.
pub fn key(self: *State) RuntimeError!u8 {
    return nextKey(self);
}

/// XKEY: the bytes of one character from KEY. A byte that does not continue the
/// character is given back for the next read of the input.
fn xkey(self: *State) RuntimeError!u21 {
    var bytes: [4]u8 = undefined;
    bytes[0] = try nextKey(self);
    const more: usize = switch (bytes[0]) {
        0xC0...0xDF => 1,
        0xE0...0xEF => 2,
        0xF0...0xF7 => 3,
        else => 0,
    };
    var length: usize = 1;
    while (length <= more) : (length += 1) {
        const byte = nextKey(self) catch break;
        if (byte & 0xC0 != 0x80) {
            if (self.writer.unread_fn) |unread| unread(self.writer.context, byte) else self.pending_key = byte;
            break;
        }
        bytes[length] = byte;
    }
    return decode(bytes[0..length]).code;
}

pub fn execute(self: *State, comptime builtin: Builtin) RuntimeError!void {
    switch (builtin) {
        .xc_size => try self.push(@intCast(size(try self.pop()))),
        .x_size => {
            const count = try self.pop();
            try self.push(@intCast(firstSize(try stringBytes(self, try self.pop(), count))));
        },
        .xc_fetch_plus => {
            const address = try self.pop();
            const found = try decodeAt(self, address);
            try self.push(address + @as(Cell, @intCast(found.length)));
            try self.push(found.code);
        },
        .xc_fetch => try self.push((try decodeAt(self, try self.pop())).code),
        .xc_store_plus => {
            const address = try self.pop();
            var buffer: [4]u8 = undefined;
            const bytes = encode(try self.pop(), &buffer);
            const start = try self.memoryAddress(address, bytes.len);
            @memcpy(self.memory[start .. start + bytes.len], bytes);
            try self.push(address + @as(Cell, @intCast(bytes.len)));
        },
        .xc_store_plus_question => {
            const room = try self.pop();
            const address = try self.pop();
            var buffer: [4]u8 = undefined;
            const bytes = encode(try self.pop(), &buffer);
            if (room < 0 or @as(UCell, @intCast(room)) < bytes.len) {
                try self.push(address);
                try self.push(room);
                return self.push(0);
            }
            const start = try self.memoryAddress(address, bytes.len);
            @memcpy(self.memory[start .. start + bytes.len], bytes);
            try self.push(address + @as(Cell, @intCast(bytes.len)));
            try self.push(room - @as(Cell, @intCast(bytes.len)));
            try self.push(memory_map.true_flag);
        },
        .xc_comma => {
            var buffer: [4]u8 = undefined;
            const bytes = encode(try self.pop(), &buffer);
            const address = self.data_here;
            try self.reserveData(@intCast(bytes.len));
            const start: usize = @intCast(address);
            @memcpy(self.memory[start .. start + bytes.len], bytes);
        },
        .xchar_plus => {
            const address = try self.pop();
            try self.push(address + @as(Cell, @intCast((try decodeAt(self, address)).length)));
        },
        // Back over the bytes that continue a character (at most 3) to the one before.
        .xchar_minus => {
            const address = try self.pop();
            var back: Cell = 1;
            while (back <= 4) : (back += 1) {
                const at = try self.memoryAddress(address - back, 1);
                if (self.memory[at] & 0xC0 != 0x80) break;
            } else back = 1;
            try self.push(address - back);
        },
        .xemit => {
            var buffer: [4]u8 = undefined;
            self.write(encode(try self.pop(), &buffer));
        },
        .xkey => try self.push(try xkey(self)),
        .xkey_question => {
            const ready = self.pending_key != null or if (self.writer.key_ready_fn) |ready_fn| ready_fn(self.writer.context) else false;
            try self.push(truth(ready));
        },
        // Characters that are not shown (width -1) count as 0 columns, as in gforth.
        .x_width => {
            const count = try self.pop();
            var bytes = try stringBytes(self, try self.pop(), count);
            var columns: Cell = 0;
            while (bytes.len != 0) {
                const found = decode(bytes);
                columns += @max(char_width.width(found.code), 0);
                bytes = bytes[found.length..];
            }
            try self.push(columns);
        },
        .xc_width => try self.push(char_width.width(@bitCast(try self.pop()))),
        .plus_x_string => {
            const count = try self.pop();
            const address = try self.pop();
            const step: Cell = @intCast(firstSize(try stringBytes(self, address, count)));
            try self.push(address + step);
            try self.push(count - step);
        },
        .x_string_minus => {
            const count = try self.pop();
            const address = try self.pop();
            const bytes = try stringBytes(self, address, count);
            try self.push(address);
            try self.push(if (bytes.len == 0) 0 else @intCast(lastCharacter(bytes).start));
        },
        .minus_trailing_garbage => {
            const count = try self.pop();
            const address = try self.pop();
            const bytes = try stringBytes(self, address, count);
            try self.push(address);
            if (bytes.len == 0) return self.push(0);
            const last = lastCharacter(bytes);
            try self.push(@intCast(if (last.whole) bytes.len else last.start));
        },
        .xhold => {
            var buffer: [4]u8 = undefined;
            try self.holdBytes(encode(try self.pop(), &buffer));
        },
        // EKEY gives the bytes of a character one by one, so only an ASCII byte is a
        // whole character; other events above 0xFF (none from the terminal) are taken
        // as code points.
        .ekey_to_xchar => {
            const event = try self.pop();
            try self.push(event);
            try self.push(truth(event >= 0 and (event < 0x80 or (event > 0xFF and event <= 0x10FFFF))));
        },
        .x_fetch_plus_string => {
            const count = try self.pop();
            const address = try self.pop();
            const bytes = try stringBytes(self, address, count);
            const found: Decoded = if (bytes.len == 0) .{ .code = replacement, .length = 1, .valid = false } else decode(bytes);
            try self.push(address + @as(Cell, @intCast(found.length)));
            try self.push(count - @as(Cell, @intCast(found.length)));
            try self.push(found.code);
        },
        else => unreachable,
    }
}
