//! Integer and double-cell arithmetic, comparison, and logic words.

const std = @import("std");
const defs = @import("defs.zig");
const forth = @import("../forth.zig");
const integer_math = @import("integer_math.zig");
const memory_map = @import("memory_map.zig");
const Builtin = defs.Builtin;
const Double = memory_map.Double;
const RuntimeError = defs.RuntimeError;
const State = forth.State;
const UCell = memory_map.UCell;
const UDouble = memory_map.UDouble;
const doubleDivision = integer_math.doubleDivision;
const flooredDivision = integer_math.flooredDivision;
const true_flag = memory_map.true_flag;
const truth = integer_math.truth;

/// The built-in words this file executes; executeBuiltin dispatches by this list.
pub const words = [_]Builtin{
    .add, .sub, .mul, .div, .mod, .max, .min, .equal, .not_equal, .less, .greater, .less_equal,
    .greater_equal, .bit_and, .bit_or, .bit_xor, .bit_nand, .bit_nor, .lshift, .rshift, .div_mod,
    .swap_bytes, .negate, .abs, .one_plus, .one_minus, .two_star, .two_slash, .logical_not,
    .zero_equal, .zero_less, .zero_greater, .zero_not_equal, .bit_complement, .true_value,
    .false_value, .s_to_d, .d_to_s, .d_add, .d_sub, .d_negate, .d_abs, .d_zero_equal, .d_zero_less,
    .d_equal, .d_less, .within, .u_less, .u_greater, .star_slash, .star_slash_mod, .m_star, .um_star,
    .um_slash_mod, .fm_slash_mod, .sm_slash_rem, .d_two_star, .d_two_slash, .d_max, .d_min, .m_plus,
    .du_less,
};

pub fn execute(self: *State, comptime builtin: Builtin) RuntimeError!void {
    switch (builtin) {
        .add, .sub, .mul, .div, .mod, .max, .min, .equal, .not_equal, .less, .greater, .less_equal, .greater_equal, .bit_and, .bit_or, .bit_xor, .bit_nand, .bit_nor, .lshift, .rshift, .u_less, .u_greater => try self.binary(builtin),
        .div_mod => {
            const divisor = try self.pop();
            const dividend = try self.pop();
            const result = try flooredDivision(dividend, divisor);
            try self.push(result.remainder);
            try self.push(result.quotient);
        },
        // The product is kept in a double cell, so n1 n2 */ does not overflow before n3 divides it.
        .star_slash, .star_slash_mod => {
            const divisor = try self.pop();
            const b = try self.pop();
            const a = try self.pop();
            const result = try doubleDivision(@as(Double, a) * b, divisor, true);
            if (builtin == .star_slash_mod) try self.push(result.remainder);
            try self.push(result.quotient);
        },
        .m_star => {
            const b = try self.pop();
            const a = try self.pop();
            try self.pushDouble(@as(Double, a) * b);
        },
        .um_star => {
            const b: UCell = @bitCast(try self.pop());
            const a: UCell = @bitCast(try self.pop());
            try self.pushDouble(@bitCast(@as(UDouble, a) * b));
        },
        .um_slash_mod => {
            const divisor: UCell = @bitCast(try self.pop());
            const dividend: UDouble = @bitCast(try self.popDouble());
            if (divisor == 0) return error.DivisionByZero;
            const quotient = dividend / divisor;
            if (quotient > std.math.maxInt(UCell)) return error.ResultOutOfRange;
            try self.push(@bitCast(@as(UCell, @intCast(dividend % divisor))));
            try self.push(@bitCast(@as(UCell, @intCast(quotient))));
        },
        .d_two_star => try self.pushDouble((try self.popDouble()) *% 2),
        .d_two_slash => try self.pushDouble((try self.popDouble()) >> 1),
        .d_max, .d_min => {
            const b = try self.popDouble();
            const a = try self.popDouble();
            try self.pushDouble(if (builtin == .d_max) @max(a, b) else @min(a, b));
        },
        .m_plus => {
            const n = try self.pop();
            try self.pushDouble((try self.popDouble()) +% n);
        },
        .du_less => {
            const b: UDouble = @bitCast(try self.popDouble());
            const a: UDouble = @bitCast(try self.popDouble());
            try self.push(truth(a < b));
        },
        .fm_slash_mod, .sm_slash_rem => {
            const divisor = try self.pop();
            const result = try doubleDivision(try self.popDouble(), divisor, builtin == .fm_slash_mod);
            try self.push(result.remainder);
            try self.push(result.quotient);
        },
        .swap_bytes => try self.push(@byteSwap(try self.pop())),
        .negate => try self.push(0 -% try self.pop()),
        .abs => {
            const a = try self.pop();
            try self.push(if (a < 0) 0 -% a else a);
        },
        .one_plus => try self.push((try self.pop()) +% 1),
        .one_minus => try self.push((try self.pop()) -% 1),
        .two_star => try self.push((try self.pop()) *% 2),
        .two_slash => try self.push((try self.pop()) >> 1),
        .logical_not, .zero_equal => try self.push(truth(try self.pop() == 0)),
        .zero_less => try self.push(truth(try self.pop() < 0)),
        .zero_greater => try self.push(truth(try self.pop() > 0)),
        .zero_not_equal => try self.push(truth(try self.pop() != 0)),
        .bit_complement => try self.push(~(try self.pop())),
        .true_value => try self.push(true_flag),
        .false_value => try self.push(0),
        .s_to_d => try self.pushDouble(try self.pop()),
        .d_to_s => {
            _ = try self.pop();
        },
        .d_add, .d_sub => {
            const b = try self.popDouble();
            const a = try self.popDouble();
            try self.pushDouble(if (builtin == .d_add) a +% b else a -% b);
        },
        .d_negate => try self.pushDouble(0 -% try self.popDouble()),
        .d_abs => {
            const d = try self.popDouble();
            try self.pushDouble(if (d < 0) 0 -% d else d);
        },
        .d_zero_equal => try self.push(truth(try self.popDouble() == 0)),
        .d_zero_less => try self.push(truth(try self.popDouble() < 0)),
        .d_equal, .d_less => {
            const b = try self.popDouble();
            const a = try self.popDouble();
            try self.push(truth(if (builtin == .d_equal) a == b else a < b));
        },
        .within => {
            const upper = try self.pop();
            const lower = try self.pop();
            const value = try self.pop();
            try self.push(truth(@as(UCell, @bitCast(value -% lower)) < @as(UCell, @bitCast(upper -% lower))));
        },
        else => @compileError(@tagName(builtin) ++ " is not in the words of this file"),
    }
}
