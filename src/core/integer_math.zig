//! Integer operations shared by the words: floored division, flags, and conversions.

const std = @import("std");
const defs = @import("defs.zig");
const forth = @import("../forth.zig");
const memory_map = @import("memory_map.zig");
const Builtin = defs.Builtin;
const Cell = memory_map.Cell;
const Double = memory_map.Double;
const Float = memory_map.Float;
const RuntimeError = defs.RuntimeError;
const State = forth.State;
const UCell = memory_map.UCell;
const true_flag = memory_map.true_flag;

pub const Division = struct { quotient: Cell, remainder: Cell };

pub fn binary(self: *State, builtin: Builtin) RuntimeError!void {
    const b = try self.pop();
    const a = try self.pop();
    const result: Cell = switch (builtin) {
        .add => a +% b,
        .sub => a -% b,
        .mul => a *% b,
        .div => (try flooredDivision(a, b)).quotient,
        .mod => (try flooredDivision(a, b)).remainder,
        .max => @max(a, b),
        .min => @min(a, b),
        .equal => truth(a == b),
        .not_equal => truth(a != b),
        .less => truth(a < b),
        .greater => truth(a > b),
        .less_equal => truth(a <= b),
        .greater_equal => truth(a >= b),
        .u_less => truth(@as(UCell, @bitCast(a)) < @as(UCell, @bitCast(b))),
        .u_greater => truth(@as(UCell, @bitCast(a)) > @as(UCell, @bitCast(b))),
        .bit_and => a & b,
        .bit_or => a | b,
        .bit_xor => a ^ b,
        .bit_nand => ~(a & b),
        .bit_nor => ~(a | b),
        .lshift, .rshift => blk: {
            const bits: UCell = @bitCast(a);
            if (b < 0 or b >= 64) break :blk 0;
            const amount: u6 = @intCast(b);
            break :blk @bitCast(if (builtin == .lshift) bits << amount else bits >> amount);
        },
        else => unreachable,
    };
    try self.push(result);
}

pub fn flooredDivision(dividend: Cell, divisor: Cell) RuntimeError!Division {
    if (divisor == 0) return error.DivisionByZero;
    // The quotient does not fit in a cell; gforth reports it for MOD as well.
    if (dividend == std.math.minInt(Cell) and divisor == -1) return error.ResultOutOfRange;
    return .{ .quotient = @divFloor(dividend, divisor), .remainder = @mod(dividend, divisor) };
}

/// Divides a double-cell number by a cell for FM/MOD and */ (quotient rounded toward
/// minus infinity) or SM/REM (toward zero). As in gforth, a quotient that does not fit
/// in a cell is an error rather than a wrapped value.
pub fn doubleDivision(dividend: Double, divisor: Cell, floored: bool) RuntimeError!Division {
    if (divisor == 0) return error.DivisionByZero;
    // The one quotient Double division itself cannot hold is out of range for a cell too.
    if (dividend == std.math.minInt(Double) and divisor == -1) return error.ResultOutOfRange;
    const wide: Double = divisor;
    const quotient = if (floored) @divFloor(dividend, wide) else @divTrunc(dividend, wide);
    const remainder = if (floored) @mod(dividend, wide) else @rem(dividend, wide);
    if (quotient < std.math.minInt(Cell) or quotient > std.math.maxInt(Cell)) return error.ResultOutOfRange;
    return .{ .quotient = @intCast(quotient), .remainder = @intCast(remainder) };
}

/// Whether +LOOP's step takes the index across the boundary between limit-1 and limit,
/// counting with wrapping cells as the standard does: the loop ends when index - limit
/// changes sign in the direction of the step. A step of 0 never ends the loop.
pub fn loopCrossed(index: Cell, limit: Cell, step: Cell) bool {
    const before = index -% limit;
    const after = before +% step;
    return ((before ^ after) & (before ^ step)) < 0;
}

pub fn truth(value: bool) Cell {
    return if (value) true_flag else 0;
}

pub fn floatToCell(value: Float) Cell {
    if (std.math.isNan(value)) return 0;
    if (value >= 0x1p63) return std.math.maxInt(Cell);
    if (value < -0x1p63) return std.math.minInt(Cell);
    return @intFromFloat(value);
}

pub fn floatToDouble(value: Float) Double {
    if (std.math.isNan(value)) return 0;
    if (value >= 0x1p127) return std.math.maxInt(Double);
    if (value < -0x1p127) return std.math.minInt(Double);
    return @intFromFloat(value);
}
