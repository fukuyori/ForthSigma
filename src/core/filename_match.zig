//! Portable, case-sensitive filename globbing. No OS locale or filesystem access.
const std = @import("std");
const forth = @import("../forth.zig");
const defs = @import("defs.zig");
const map = @import("memory_map.zig");
const checkWork = @import("words_numeric.zig").checkWorkBlock;
const RuntimeError = defs.RuntimeError;

pub fn execute(self: *forth.State) RuntimeError!void {
    try self.requireDepth(4);
    const n = std.math.cast(usize, try self.peek(2)) orelse return error.InvalidAddress;
    const p = std.math.cast(usize, try self.peek(0)) orelse return error.InvalidAddress;
    const name_at = try self.memoryAddress(try self.peek(3), n);
    const pattern_at = try self.memoryAddress(try self.peek(1), p);
    const name = self.memory[name_at..][0..n];
    const pattern = self.memory[pattern_at..][0..p];
    if (std.mem.indexOfScalar(u8, name, 0) != null or std.mem.indexOfScalar(u8, pattern, 0) != null)
        return self.throwIor(map.errno_invalid);
    const result = try matches(self, name, pattern);
    self.data_depth -= 4;
    try self.push(if (result) -1 else 0);
}

const Character = struct { code: u32, end: usize };
fn character(text: []const u8, at: usize) Character {
    const fallback = Character{ .code = 0x110000 + @as(u32, text[at]), .end = at + 1 };
    const count = std.unicode.utf8ByteSequenceLength(text[at]) catch return fallback;
    if (count > text.len - at) return fallback;
    const code = std.unicode.utf8Decode(text[at..][0..count]) catch return fallback;
    return .{ .code = code, .end = at + count };
}

fn classMatches(name: []const u8, c: u32) ?bool {
    const ascii = c < 128;
    const alpha = (c >= 'A' and c <= 'Z') or (c >= 'a' and c <= 'z');
    const digit = c >= '0' and c <= '9';
    if (std.mem.eql(u8, name, "alnum")) return alpha or digit;
    if (std.mem.eql(u8, name, "alpha")) return alpha;
    if (std.mem.eql(u8, name, "blank")) return c == ' ' or c == '\t';
    if (std.mem.eql(u8, name, "cntrl")) return c < 32 or c == 127;
    if (std.mem.eql(u8, name, "digit")) return digit;
    if (std.mem.eql(u8, name, "graph")) return c >= 33 and c <= 126;
    if (std.mem.eql(u8, name, "lower")) return c >= 'a' and c <= 'z';
    if (std.mem.eql(u8, name, "print")) return c >= 32 and c <= 126;
    if (std.mem.eql(u8, name, "punct")) return ascii and c >= 33 and c <= 126 and !alpha and !digit;
    if (std.mem.eql(u8, name, "space")) return c == ' ' or (c >= 9 and c <= 13);
    if (std.mem.eql(u8, name, "upper")) return c >= 'A' and c <= 'Z';
    if (std.mem.eql(u8, name, "xdigit")) return digit or (c >= 'A' and c <= 'F') or (c >= 'a' and c <= 'f');
    return null;
}

const Atom = struct { code: ?u32 = null, end: usize, matched: bool, valid: bool = true };
fn atom(pattern: []const u8, at: usize, c: u32) Atom {
    if (std.mem.startsWith(u8, pattern[at..], "[:")) {
        if (std.mem.indexOf(u8, pattern[at + 2 ..], ":]")) |end| {
            const matched = classMatches(pattern[at + 2 ..][0..end], c);
            return .{ .end = at + 2 + end + 2, .matched = matched orelse false, .valid = matched != null };
        }
    }
    // Locale-specific collating/equivalence constructs are unsupported.
    if (std.mem.startsWith(u8, pattern[at..], "[.") or std.mem.startsWith(u8, pattern[at..], "[=")) {
        const delimiter = pattern[at + 1];
        var end = at + 2;
        while (end + 1 < pattern.len) : (end += 1) {
            if (pattern[end] == delimiter and pattern[end + 1] == ']') return .{ .end = end + 2, .matched = false, .valid = false };
        }
    }
    const escaped = pattern[at] == '\\' and at + 1 < pattern.len;
    const char = character(pattern, at + @as(usize, @intFromBool(escaped)));
    return .{ .code = char.code, .end = char.end, .matched = char.code == c };
}

const Token = struct { end: usize, matched: bool };
fn bracket(self: *forth.State, pattern: []const u8, at: usize, c: u32) RuntimeError!Token {
    var i = at + 1;
    var negate = false;
    if (i < pattern.len and (pattern[i] == '!' or pattern[i] == '^')) {
        negate = true;
        i += 1;
    }
    var first = true;
    var matched = false;
    var valid = true;
    while (i < pattern.len) {
        try checkWork(self);
        if (pattern[i] == ']' and !first) return .{ .end = i + 1, .matched = valid and (matched != negate) };
        first = false;
        const lower = atom(pattern, i, c);
        i = lower.end;
        valid = valid and lower.valid;
        if (lower.code != null and i + 1 < pattern.len and pattern[i] == '-' and pattern[i + 1] != ']') {
            const upper = atom(pattern, i + 1, c);
            valid = valid and upper.valid;
            if (upper.code) |end| {
                matched = matched or (lower.code.? <= c and c <= end);
            } else valid = false;
            i = upper.end;
        } else matched = matched or lower.matched;
    }
    // Malformed brackets do not match; escape an opening bracket for a literal.
    return .{ .end = pattern.len, .matched = false };
}

fn token(self: *forth.State, pattern: []const u8, at: usize, c: u32) RuntimeError!Token {
    if (pattern[at] == '?') return .{ .end = at + 1, .matched = true };
    if (pattern[at] == '[') return bracket(self, pattern, at, c);
    if (pattern[at] == '\\' and at + 1 == pattern.len) return .{ .end = at + 1, .matched = false };
    const char = character(pattern, at + @as(usize, @intFromBool(pattern[at] == '\\')));
    return .{ .end = char.end, .matched = char.code == c };
}

/// A single most-recent star checkpoint avoids recursion and exponential branching.
/// Worst-case repeated suffix comparisons are quadratic; the VM work budget applies.
pub fn matches(self: *forth.State, name: []const u8, pattern: []const u8) RuntimeError!bool {
    var n: usize = 0;
    var p: usize = 0;
    var star: ?usize = null;
    var retry: usize = 0;
    while (n < name.len) {
        try checkWork(self);
        if (p < pattern.len and pattern[p] == '*') {
            while (p < pattern.len and pattern[p] == '*') {
                try checkWork(self);
                p += 1;
            }
            if (p == pattern.len) return true;
            star = p;
            retry = n;
            continue;
        }
        const char = character(name, n);
        if (p < pattern.len) {
            const next = try token(self, pattern, p, char.code);
            if (next.matched) {
                n = char.end;
                p = next.end;
                continue;
            }
        }
        if (star) |checkpoint| {
            if (retry == name.len) return false;
            retry = character(name, retry).end;
            n = retry;
            p = checkpoint;
        } else return false;
    }
    while (p < pattern.len and pattern[p] == '*') {
        try checkWork(self);
        p += 1;
    }
    return p == pattern.len;
}
