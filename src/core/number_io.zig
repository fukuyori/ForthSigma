//! Number parsing and output, and the pictured numeric output area.

const std = @import("std");
const defs = @import("defs.zig");
const float_format = @import("float_format.zig");
const forth = @import("../forth.zig");
const memory_map = @import("memory_map.zig");
const Cell = memory_map.Cell;
const Double = memory_map.Double;
const Float = memory_map.Float;
const ParsedNumber = defs.ParsedNumber;
const RuntimeError = defs.RuntimeError;
const State = forth.State;
const UDouble = memory_map.UDouble;
const base_address = memory_map.base_address;
const dot_precision = memory_map.dot_precision;
const doubleCells = defs.doubleCells;
const hold_bottom = memory_map.hold_bottom;
const hold_top = memory_map.hold_top;
const represent = float_format.represent;
const withoutTrailingZeros = float_format.withoutTrailingZeros;

pub fn resetHold(self: *State) void {
    self.hold_ptr = hold_top;
    self.hold_end = hold_top;
    self.hold_depth = 0;
}

pub fn holdBytes(self: *State, bytes: []const u8) RuntimeError!void {
    const length: Cell = @intCast(bytes.len);
    if (self.hold_ptr - hold_bottom < length) return error.PicturedNumericOverflow;
    self.hold_ptr -= length;
    const start: usize = @intCast(self.hold_ptr);
    @memcpy(self.memory[start .. start + bytes.len], bytes);
}

/// `#`: prepends the least-significant digit of `value` and returns the remaining quotient.
pub fn holdDigit(self: *State, value: UDouble) RuntimeError!UDouble {
    const base: UDouble = @intCast(try self.validBase());
    const digit: u8 = @intCast(value % base);
    try self.holdBytes(&.{if (digit < 10) '0' + digit else 'A' + digit - 10});
    return value / base;
}

pub fn validBase(self: *State) RuntimeError!Cell {
    const base = self.currentBase();
    if (base < 2 or base > 36) return error.InvalidBase;
    return base;
}

pub fn digitValue(c: u8) ?Cell {
    return if (c >= '0' and c <= '9') c - '0' else if (c >= 'A' and c <= 'Z') c - 'A' + 10 else if (c >= 'a' and c <= 'z') c - 'a' + 10 else null;
}

pub fn currentBase(self: *State) Cell {
    return self.readCell(base_address) catch unreachable;
}

/// Recognizes an integer in the manner of gforth's number recognizer: optional `-`, an
/// optional base prefix (`$` `#` `&` `%`), digits, and `'c'` character literals. A `.`
/// anywhere among the digits makes the number double-cell (`123.` and `12.34` are doubles).
pub fn parseNumber(self: *State, token: []const u8) RuntimeError!?ParsedNumber {
    if (token.len == 3 and token[0] == '\'' and token[2] == '\'') return .{ .value = token[1], .double = false };
    var base = try self.validBase();
    var i: usize = 0;
    var negative = false;
    if (i < token.len and token[i] == '-') {
        negative = true;
        i += 1;
    }
    if (i < token.len) {
        const prefixed_base: ?Cell = switch (token[i]) {
            '$' => 16,
            '#', '&' => 10,
            '%' => 2,
            else => null,
        };
        if (prefixed_base) |prefixed| {
            base = prefixed;
            i += 1;
        }
    }
    if (!negative and i < token.len and token[i] == '-') {
        negative = true;
        i += 1;
    }
    var value: UDouble = 0;
    var digits: usize = 0;
    var double = false;
    while (i < token.len) : (i += 1) {
        if (token[i] == '.') {
            double = true;
            continue;
        }
        const digit = digitValue(token[i]) orelse return null;
        if (digit >= base) return null;
        value = value *% @as(UDouble, @intCast(base)) +% @as(UDouble, @intCast(digit));
        digits += 1;
    }
    if (digits == 0) return null;
    const signed: Double = @bitCast(value);
    const result = if (negative) 0 -% signed else signed;
    // A single-cell number wraps to 64 bits, as gforth's >NUMBER does with the high cell dropped.
    return .{ .value = if (double) result else doubleCells(result).low, .double = double };
}

/// Recognizes a decimal float. Source literals require an exponent marker (`1E`, `1.5e-3`);
/// FINPUT and >FLOAT also accept plain decimal numbers.
pub fn parseFloat(token: []const u8, require_exponent: bool) ?Float {
    var normalized: [80]u8 = undefined;
    var used: usize = 0;
    var i: usize = 0;
    if (i < token.len and (token[i] == '-' or token[i] == '+')) {
        normalized[used] = token[i];
        used += 1;
        i += 1;
    }
    const integer_start = i;
    while (i < token.len and std.ascii.isDigit(token[i])) i += 1;
    const integer_digits = token[integer_start..i];
    var fraction_digits: []const u8 = &.{};
    if (i < token.len and token[i] == '.') {
        i += 1;
        const fraction_start = i;
        while (i < token.len and std.ascii.isDigit(token[i])) i += 1;
        fraction_digits = token[fraction_start..i];
    }
    if (integer_digits.len + fraction_digits.len == 0) return null;
    var exponent_sign: []const u8 = "";
    var exponent_digits: []const u8 = "0";
    if (i < token.len and (token[i] == 'e' or token[i] == 'E')) {
        i += 1;
        if (i < token.len and (token[i] == '-' or token[i] == '+')) {
            exponent_sign = token[i .. i + 1];
            i += 1;
        }
        const exponent_start = i;
        while (i < token.len and std.ascii.isDigit(token[i])) i += 1;
        if (i > exponent_start) exponent_digits = token[exponent_start..i];
    } else if (require_exponent) return null;
    if (i != token.len) return null;
    const parts = [_][]const u8{ if (integer_digits.len == 0) "0" else integer_digits, ".", if (fraction_digits.len == 0) "0" else fraction_digits, "e", exponent_sign, exponent_digits };
    for (parts) |part| {
        if (used + part.len > normalized.len) return null;
        @memcpy(normalized[used .. used + part.len], part);
        used += part.len;
    }
    return std.fmt.parseFloat(Float, normalized[0..used]) catch null;
}

pub fn writeDepth(self: *State, depth: usize) void {
    self.write("<");
    self.writeNumber(depth);
    self.write("> ");
}

/// Writes a signed number in the current base; callers widen unsigned cells before passing them.
pub fn writeNumber(self: *State, value: Double) void {
    const base = self.currentBase();
    if (base < 2 or base > 36) {
        self.write("?BASE?");
        return;
    }
    const radix: UDouble = @intCast(base);
    const negative = value < 0;
    var n: UDouble = @bitCast(value);
    if (negative) n = 0 -% n;
    var digits: [128]u8 = undefined;
    var length: usize = 0;
    while (true) {
        const digit: u8 = @intCast(n % radix);
        digits[length] = if (digit < 10) '0' + digit else 'A' + digit - 10;
        length += 1;
        n /= radix;
        if (n == 0) break;
    }
    if (negative) self.write("-");
    while (length > 0) {
        length -= 1;
        self.write(digits[length .. length + 1]);
    }
}

/// Number of characters `writeNumber` prints for `value`.
pub fn numberWidth(self: *State, value: Double) usize {
    const base = self.currentBase();
    if (base < 2 or base > 36) return 6;
    var n: UDouble = @bitCast(value);
    if (value < 0) n = 0 -% n;
    var width: usize = if (value < 0) 1 else 0;
    while (true) {
        width += 1;
        n /= @intCast(base);
        if (n == 0) break;
    }
    return width;
}

pub fn writeZeros(self: *State, count: i64) void {
    var remaining = count;
    while (remaining > 0) : (remaining -= 1) self.write("0");
}

/// F. output: significand rounded to 15 digits, printed without an exponent.
pub fn writeFloatFixed(self: *State, value: Float) void {
    const rep = represent(value, dot_precision);
    if (!rep.finite) return self.writeNonFinite(value, "infinity");
    if (rep.negative) self.write("-");
    const exponent: i64 = rep.exponent;
    const digits = rep.digits[0..rep.len];
    if (exponent <= 0) {
        self.write("0");
    } else {
        self.write(digits[0..@intCast(@min(exponent, dot_precision))]);
        self.writeZeros(exponent - dot_precision);
    }
    self.write(".");
    self.writeZeros(-exponent);
    const fraction_start: usize = @intCast(std.math.clamp(exponent, 0, dot_precision));
    self.write(withoutTrailingZeros(digits[fraction_start..]));
}

/// F.S item output: up to `precision` significant digits with an `e` marker.
pub fn writeFloatExponent(self: *State, value: Float, precision: usize) void {
    if (std.math.isNan(value) or std.math.isInf(value)) return self.writeNonFinite(value, "inf");
    var digit_count = precision;
    const magnitude = @abs(value);
    const lower = std.math.pow(Float, 10, @floatFromInt(precision));
    if (magnitude >= lower and magnitude < lower * 10) digit_count += 1;
    const rep = represent(value, digit_count);
    if (rep.negative) self.write("-");
    const digits = withoutTrailingZeros(rep.digits[0..rep.len]);
    const exponent: i64 = rep.exponent;
    if (exponent >= 0 and exponent <= @as(i64, @intCast(digit_count))) {
        const point: usize = @intCast(exponent);
        if (point < digits.len) {
            self.write(digits[0..point]);
            self.write(".");
            self.write(digits[point..]);
        } else {
            self.write(digits);
            self.writeZeros(exponent - @as(i64, @intCast(digits.len)));
        }
        self.write("e");
    } else if (exponent < 0 and exponent > -5) {
        self.write(".");
        self.writeZeros(-exponent);
        self.write(digits);
        self.write("e");
    } else {
        self.write(digits[0..1]);
        if (digits.len > 1) {
            self.write(".");
            self.write(digits[1..]);
        }
        self.write("e");
        self.writeNumberDecimal(exponent - 1);
    }
}

pub fn writeNonFinite(self: *State, value: Float, infinity: []const u8) void {
    if (std.math.isNan(value)) return self.write("NaN");
    if (std.math.signbit(value)) self.write("-");
    self.write(infinity);
}

pub fn writeNumberDecimal(self: *State, value: i64) void {
    var buffer: [24]u8 = undefined;
    self.write(std.fmt.bufPrint(&buffer, "{d}", .{value}) catch unreachable);
}
