//! Default extended grapheme boundaries: Unicode 18.0.0, UAX #29 rev 49.
const std = @import("std");
const data = @import("grapheme_data.zig");

const Gcb = enum(u4) { other, cr, lf, control, extend, zwj, ri, prepend, spacing, l, v, t, lv, lvt };
const InCB = enum(u2) { none, consonant, extend, linker };
const Properties = struct {
    gcb: Gcb,
    incb: InCB,
    pictographic: bool,
    fn get(code: u21) Properties {
        const bits = data.properties(code);
        return .{ .gcb = @fromBackingInt(@intCast(@as(u4, @truncate(bits)))), .incb = @fromBackingInt(@intCast(@as(u2, @truncate(bits >> 5)))), .pictographic = bits & 16 != 0 };
    }
};

const Cursor = struct {
    previous: Gcb = .other,
    ri_odd: bool = false,
    pictographic_extend: bool = false,
    pictographic_zwj: bool = false,
    linker_extend: bool = false,

    fn boundary(self: Cursor, next: Properties) bool {
        const a = self.previous;
        const b = next.gcb;
        if (a == .cr and b == .lf) return false; // GB3
        if (control(a) or control(b)) return true; // GB4/5
        if (a == .l and (b == .l or b == .v or b == .lv or b == .lvt)) return false;
        if ((a == .lv or a == .v) and (b == .v or b == .t)) return false;
        if ((a == .lvt or a == .t) and b == .t) return false;
        if (b == .extend or b == .zwj or b == .spacing or a == .prepend) return false;
        if (self.linker_extend and next.incb == .consonant) return false; // GB9c rev49
        if (self.pictographic_zwj and next.pictographic) return false; // GB11
        if (a == .ri and b == .ri and self.ri_odd) return false;
        return true;
    }

    fn consume(self: *Cursor, p: Properties) void {
        self.pictographic_zwj = self.pictographic_extend and p.gcb == .zwj;
        self.pictographic_extend = p.pictographic or (self.pictographic_extend and p.gcb == .extend);
        self.linker_extend = p.incb == .linker or (self.linker_extend and p.incb == .extend);
        self.ri_odd = p.gcb == .ri and (self.previous != .ri or !self.ri_odd);
        self.previous = p.gcb;
    }
};

fn control(p: Gcb) bool {
    return p == .cr or p == .lf or p == .control;
}

fn decode(bytes: []const u8) error{InvalidNumber}!struct { properties: Properties, length: usize } {
    const length = std.unicode.utf8ByteSequenceLength(bytes[0]) catch return error.InvalidNumber;
    if (length > bytes.len) return error.InvalidNumber;
    const code = std.unicode.utf8Decode(bytes[0..length]) catch return error.InvalidNumber;
    return .{ .properties = Properties.get(code), .length = length };
}

/// First scans the cluster plus one lookahead scalar; last scans the whole text.
/// No allocation, recursion or backwards rescans within a call.
pub fn size(bytes: []const u8, last: bool) error{InvalidNumber}!usize {
    if (bytes.len == 0) return 0;
    var cursor = Cursor{};
    var at: usize = 0;
    var last_start: usize = 0;
    while (at < bytes.len) {
        const next = try decode(bytes[at..]);
        if (at != 0 and cursor.boundary(next.properties)) {
            if (!last) return at;
            last_start = at;
        }
        cursor.consume(next.properties);
        at += next.length;
    }
    return bytes.len - last_start;
}
