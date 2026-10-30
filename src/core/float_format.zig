const std = @import("std");
const defs = @import("defs.zig");
const memory_map = @import("memory_map.zig");
const Cell = memory_map.Cell;
const Float = memory_map.Float;
const RuntimeError = defs.RuntimeError;
const dot_precision = memory_map.dot_precision;

/// Decimal significand of a float, in the manner of Forth's REPRESENT.
pub const Representation = struct {
    digits: [dot_precision + 1]u8 = undefined,
    len: usize = 0,
    exponent: i32 = 0,
    negative: bool = false,
    finite: bool = true,
};

/// `digit_count` significant digits of `value`, rounded exactly from the binary value
/// (std.fmt rounds its shortest decimal form, so 0.5e FTAN would print a 1 too many).
pub fn represent(value: Float, digit_count: usize) Representation {
    var result = Representation{ .len = digit_count, .negative = std.math.signbit(value) };
    if (std.math.isNan(value) or std.math.isInf(value)) {
        result.finite = false;
        return result;
    }
    var buffer: [max_rdp_width + 400]u8 = undefined;
    // A few digits of a double need only a small exact computation.
    const decimal = representDecimal(@abs(value), digit_count, &buffer) catch unreachable;
    @memcpy(result.digits[0..digit_count], decimal.digits);
    result.exponent = decimal.exponent;
    return result;
}

/// Widest field F.RDP and its relatives format.
pub const max_rdp_width = 4096;

/// Decimal digits of round-half-even(|value| * 10^scale), computed exactly from the
/// binary value. std.fmt rounds the shortest decimal form instead, which differs from
/// gforth for values such as 2.675 or 0.95.
pub fn scaledDecimal(value: Float, scale: i32, output: []u8) RuntimeError![]const u8 {
    return scaledDecimalRounded(value, scale, true, output);
}

/// Like scaledDecimal, but truncating: the digits of floor(|value| * 10^scale).
pub fn truncatedDecimal(value: Float, scale: i32, output: []u8) RuntimeError![]const u8 {
    return scaledDecimalRounded(value, scale, false, output);
}

pub fn scaledDecimalRounded(value: Float, scale: i32, round: bool, output: []u8) RuntimeError![]const u8 {
    const magnitude = @abs(value);
    if (magnitude == 0) {
        output[0] = '0';
        return output[0..1];
    }
    const bits: u64 = @bitCast(magnitude);
    const exponent_field: i32 = @intCast(bits >> 52);
    const fraction = bits & ((@as(u64, 1) << 52) - 1);
    const mantissa = if (exponent_field == 0) fraction else fraction | (@as(u64, 1) << 52);
    const binary_exponent: i32 = (if (exponent_field == 0) -1074 else exponent_field - 1075);

    var scratch: [32768]u8 = undefined;
    var fixed = std.heap.FixedBufferAllocator.init(&scratch);
    const allocator = fixed.allocator();
    return scaledDecimalWith(allocator, mantissa, binary_exponent, scale, round, output) catch error.StringTooLong;
}

pub fn scaledDecimalWith(allocator: std.mem.Allocator, mantissa: u64, binary_exponent: i32, scale: i32, round: bool, output: []u8) ![]const u8 {
    const Big = std.math.big.int.Managed;
    var numerator = try Big.initSet(allocator, mantissa);
    var denominator = try Big.initSet(allocator, 1);
    if (binary_exponent > 0) try numerator.shiftLeft(&numerator, @intCast(binary_exponent));
    if (binary_exponent < 0) try denominator.shiftLeft(&denominator, @intCast(-binary_exponent));
    var power = try Big.initSet(allocator, 10);
    try power.pow(&power, @intCast(@abs(scale)));
    if (scale > 0) try numerator.mul(&numerator, &power) else if (scale < 0) try denominator.mul(&denominator, &power);
    var quotient = try Big.init(allocator);
    var remainder = try Big.init(allocator);
    try quotient.divTrunc(&remainder, &numerator, &denominator);
    try remainder.shiftLeft(&remainder, 1);
    const half = remainder.order(denominator);
    if (round and (half == .gt or (half == .eq and !quotient.isEven()))) try quotient.addScalar(&quotient, 1);
    const text = try quotient.toString(allocator, 10, .lower);
    if (text.len > output.len) return error.NoSpaceLeft;
    @memcpy(output[0..text.len], text);
    return output[0..text.len];
}

/// `count` significant decimal digits of `magnitude`, rounded half to even, and the
/// exponent e with magnitude ~= 0.d1d2... * 10^e. Zero gives zeros with e = 1, so that
/// it has one integer digit. Beyond 800 digits a double has no more nonzero digits, so
/// the rest is padded with zeros.
pub const Represented = struct { digits: []const u8, exponent: i32 };

pub fn representDecimal(magnitude: Float, count: usize, buffer: *[max_rdp_width + 400]u8) RuntimeError!Represented {
    if (magnitude == 0) {
        @memset(buffer[0..count], '0');
        return .{ .digits = buffer[0..count], .exponent = 1 };
    }
    const exact: usize = @min(count, 800);
    // log10 can be off by one near powers of ten, so the exponent comes from the
    // truncated digits: with this scale they number 1 to 4, and their count fixes it.
    const estimate: i32 = @as(i32, @intFromFloat(@floor(@log10(magnitude)))) + 1;
    const probe_scale = 2 - estimate;
    var exponent: i32 = @as(i32, @intCast((try truncatedDecimal(magnitude, probe_scale, buffer)).len)) - probe_scale;
    const scale = @as(i32, @intCast(exact)) - exponent;
    const rounded = try scaledDecimal(magnitude, scale, buffer);
    // A carry (9.99 -> 10.0) adds a digit; the digits after its 1 are zeros.
    if (rounded.len > exact) exponent += 1;
    if (exact < count) @memset(buffer[exact..count], '0');
    return .{ .digits = buffer[0..count], .exponent = exponent };
}

/// Whether F.RDP uses fixed-point notation for a value with decimal exponent
/// `exponent`, and how many significant digits that layout shows.
pub const RdpLayout = struct { fixed: bool, digits: i64 };

pub fn rdpLayout(exponent: i32, width: usize, fraction: usize, precision: i64, sign_width: usize) RdpLayout {
    const width_i: i64 = @intCast(width);
    const fraction_i: i64 = @intCast(fraction);
    const sign_i: i64 = @intCast(sign_width);
    const before_point = width_i - fraction_i - 1;
    const enough_precision = precision == 0 or fraction_i + exponent >= precision;
    if (before_point >= 0 and enough_precision and before_point - sign_i >= @max(exponent, 0))
        return .{ .fixed = true, .digits = std.math.clamp(exponent + fraction_i, 1, width_i) };
    return .{ .fixed = false, .digits = mantissaDigits(exponent, width, sign_width) };
}

/// Digits of an exponential-notation mantissa that fill `width`, counting the point
/// once there are at least one; 0 means a single digit and no point, and a negative
/// count means the field is too narrow.
pub fn mantissaDigits(exponent: i32, width: usize, sign_width: usize) i64 {
    var exponent_text: [16]u8 = undefined;
    const etext = std.fmt.bufPrint(&exponent_text, "{d}", .{exponent - 1}) catch unreachable;
    return @as(i64, @intCast(width)) - @as(i64, @intCast(etext.len)) - 2 - @as(i64, @intCast(sign_width));
}

/// F.RDP formatting of `value` into a field of `width` characters with `fraction`
/// digits after the point in fixed-point notation, which is used when it shows at least
/// `precision` significant digits and its integer part fits; otherwise exponential
/// notation (`1.23E5`), and asterisks when even that does not fit. The value is
/// rounded to the field width, the layout chosen, then rounded again to the digits
/// that layout shows and the layout chosen again, since rounding can change the
/// exponent (0.09999 -> 0.10, 9.999E-10 -> 1E-9). The rules follow gforth's
/// documentation and the outputs observed from gforth.
pub fn formatRdp(value: Float, width_cell: Cell, fraction_cell: Cell, precision_cell: Cell, output: *[max_rdp_width]u8) RuntimeError![]const u8 {
    if (width_cell > max_rdp_width) return error.StringTooLong;
    const width: usize = @intCast(@max(width_cell, 0));
    const fraction: usize = @intCast(std.math.clamp(fraction_cell, 0, max_rdp_width));
    const precision: i64 = @max(precision_cell, 0);
    const field = output[0..width];
    if (width == 0) return field;
    @memset(field, ' ');
    if (std.math.isNan(value) or std.math.isInf(value)) {
        const name: []const u8 = if (std.math.isNan(value)) "NaN" else if (value < 0) "-infinity" else "infinity";
        const shown = @min(name.len, width);
        @memcpy(field[0..shown], name[0..shown]);
        return field;
    }
    const negative = std.math.signbit(value);
    const sign_width: usize = @intFromBool(negative);
    const magnitude = @abs(value);
    var buffer: [max_rdp_width + 400]u8 = undefined;

    const first = try representDecimal(magnitude, width, &buffer);
    const first_layout = rdpLayout(first.exponent, width, fraction, precision, sign_width);
    const count: usize = @intCast(std.math.clamp(first_layout.digits, 1, @as(i64, @intCast(width))));
    const rep = try representDecimal(magnitude, count, &buffer);
    const layout = rdpLayout(rep.exponent, width, fraction, precision, sign_width);

    if (layout.fixed) {
        const fraction_i: i64 = @intCast(fraction);
        // When the first digit lies beyond the last place, gforth rounds up to one unit
        // only if twice the value exceeds that unit (so 0.0005 shows as 0.000).
        const tiny = magnitude != 0 and rep.exponent + fraction_i <= 0;
        const round_up = tiny and 2 * magnitude > std.math.pow(Float, 0.1, @floatFromInt(fraction));
        const room = width - fraction - 1;
        // The layout leaves room for the integer digits; a unit rounded up from a tiny
        // value is left out when it does not fit (0.7 in a field of 1 shows ".").
        const integer_len: usize = if (rep.exponent > 0) @intCast(rep.exponent) else @intFromBool(round_up and fraction == 0 and room > sign_width);
        var at = width - fraction;
        field[at - 1] = '.';
        var index: usize = 0;
        while (index < fraction) : (index += 1) {
            const place = rep.exponent + @as(i64, @intCast(index));
            field[at + index] = if (tiny)
                (if (round_up and index + 1 == fraction) '1' else '0')
            else if (place >= 0 and place < rep.digits.len) rep.digits[@intCast(place)] else '0';
        }
        at -= 1;
        if (integer_len > 0) {
            var digit: usize = 0;
            while (digit < integer_len) : (digit += 1)
                field[at - integer_len + digit] = if (tiny) '1' else if (digit < rep.digits.len) rep.digits[digit] else '0';
            at -= integer_len;
        } else if (room > sign_width) {
            at -= 1;
            field[at] = '0';
        }
        if (negative) field[at - 1] = '-';
        return field;
    }

    // Exponential notation: d.ddddEe filling the field exactly.
    const mantissa_len = mantissaDigits(rep.exponent, width, sign_width);
    if (mantissa_len < 0) {
        @memset(field, '*');
        return field;
    }
    var exponent_text: [16]u8 = undefined;
    const etext = std.fmt.bufPrint(&exponent_text, "{d}", .{rep.exponent - 1}) catch unreachable;
    var at: usize = 0;
    if (negative) {
        field[0] = '-';
        at = 1;
    }
    field[at] = rep.digits[0];
    at += 1;
    if (mantissa_len >= 1) {
        field[at] = '.';
        at += 1;
        const rest: usize = @intCast(mantissa_len - 1);
        var index: usize = 0;
        while (index < rest) : (index += 1) field[at + index] = if (index + 1 < rep.digits.len) rep.digits[index + 1] else '0';
        at += rest;
    }
    field[at] = 'E';
    @memcpy(field[at + 1 .. at + 1 + etext.len], etext);
    return field;
}

pub fn withoutTrailingZeros(digits: []const u8) []const u8 {
    var len = digits.len;
    while (len > 0 and digits[len - 1] == '0') len -= 1;
    return digits[0..len];
}
