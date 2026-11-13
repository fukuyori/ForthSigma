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
    .add,              .sub,              .mul,              .div,             .mod,               .max,              .min,            .equal,                .not_equal,          .less,         .greater,        .less_equal,
    .greater_equal,    .bit_and,          .bit_or,           .bit_xor,         .bit_nand,          .bit_nor,          .lshift,         .rshift,               .div_mod,            .swap_bytes,   .negate,         .abs,
    .one_plus,         .one_minus,        .two_star,         .two_slash,       .logical_not,       .zero_equal,       .zero_less,      .zero_greater,         .zero_greater_equal, .under_plus,   .zero_not_equal, .bit_complement,
    .true_value,       .false_value,      .s_to_d,           .d_to_s,          .d_add,             .d_sub,            .d_negate,       .d_abs,                .d_zero_equal,       .d_zero_less,  .d_equal,        .d_less,
    .within,           .u_less,           .u_greater,        .star_slash,      .star_slash_mod,    .m_star,           .um_star,        .um_slash_mod,         .fm_slash_mod,       .sm_slash_rem, .d_two_star,     .d_two_slash,
    .d_max,            .d_min,            .m_plus,           .du_less,         .m_star_slash,      .rol,              .ror,            .arshift,              .darshift,           .dlshift,      .drshift,        .star_slash_f,
    .star_slash_mod_f, .star_slash_mod_s, .star_slash_s,     .slash_f,         .slash_mod_f,       .slash_mod_s,      .slash_s,        .to_pow2,              .ctz,                .drol,         .dror,           .du_slash_mod,
    .log2,             .lrol,             .lror,             .mod_f,           .mod_s,             .mux,              .pow2_query,     .u_star_slash,         .u_star_slash_mod,   .u_slash,      .u_slash_mod,    .ud_slash_mod,
    .u_mod,            .wrol,             .wror,             .zero_less_equal, .d_zero_less_equal, .d_zero_not_equal, .d_zero_greater, .d_zero_greater_equal, .d_less_equal,       .d_not_equal,  .d_greater,      .d_greater_equal,
    .du_less_equal,    .du_greater,       .du_greater_equal, .u_less_equal,    .u_greater_equal,   .u_max,            .u_min,
};

pub fn execute(self: *State, comptime builtin: Builtin) RuntimeError!void {
    switch (builtin) {
        .arshift => {
            const count: UCell = @bitCast(try self.pop());
            const value = try self.pop();
            try self.push(value >> @as(u6, @intCast(@min(count, 63))));
        },
        .darshift, .dlshift, .drshift => {
            const count: UCell = @bitCast(try self.pop());
            const value = try self.popDouble();
            const bits: UDouble = @bitCast(value);
            const result: Double = if (builtin == .darshift)
                value >> @as(u7, @intCast(@min(count, 127)))
            else if (count >= 128)
                0
            else if (builtin == .dlshift)
                @bitCast(bits << @as(u7, @intCast(count)))
            else
                @bitCast(bits >> @as(u7, @intCast(count)));
            try self.pushDouble(result);
        },
        .slash_f, .slash_s, .slash_mod_f, .slash_mod_s, .mod_f, .mod_s, .star_slash_f, .star_slash_s, .star_slash_mod_f, .star_slash_mod_s => {
            const divisor = try self.pop();
            const b = try self.pop();
            const product = switch (builtin) {
                .star_slash_f, .star_slash_s, .star_slash_mod_f, .star_slash_mod_s => @as(Double, try self.pop()) * b,
                else => @as(Double, b),
            };
            const floor = switch (builtin) {
                .slash_f, .slash_mod_f, .mod_f, .star_slash_f, .star_slash_mod_f => true,
                else => false,
            };
            const division = try doubleDivision(product, divisor, floor);
            switch (builtin) {
                .slash_mod_f, .slash_mod_s, .star_slash_mod_f, .star_slash_mod_s => {
                    try self.push(division.remainder);
                    try self.push(division.quotient);
                },
                .mod_f, .mod_s => try self.push(division.remainder),
                else => try self.push(division.quotient),
            }
        },
        .u_slash, .u_mod, .u_slash_mod, .u_star_slash, .u_star_slash_mod, .ud_slash_mod => {
            const divisor: UCell = @bitCast(try self.pop());
            const dividend: UDouble = switch (builtin) {
                .ud_slash_mod => @bitCast(try self.popDouble()),
                .u_star_slash, .u_star_slash_mod => blk: {
                    const b: UCell = @bitCast(try self.pop());
                    const a: UCell = @bitCast(try self.pop());
                    break :blk @as(UDouble, a) * b;
                },
                else => @as(UCell, @bitCast(try self.pop())),
            };
            if (divisor == 0) return error.DivisionByZero;
            const q = dividend / divisor;
            if (builtin != .ud_slash_mod and q > std.math.maxInt(UCell)) return error.ResultOutOfRange;
            const r: memory_map.Cell = @bitCast(@as(UCell, @intCast(dividend % divisor)));
            switch (builtin) {
                .ud_slash_mod => {
                    try self.push(r);
                    try self.pushDouble(@bitCast(q));
                },
                .u_slash_mod, .u_star_slash_mod => {
                    try self.push(r);
                    try self.push(@bitCast(@as(UCell, @intCast(q))));
                },
                .u_mod => try self.push(r),
                else => try self.push(@bitCast(@as(UCell, @intCast(q)))),
            }
        },
        .du_slash_mod => {
            const divisor: UCell = @bitCast(try self.pop());
            const dividend = try self.popDouble();
            if (divisor == 0) return error.DivisionByZero;
            const q = @divFloor(dividend, @as(Double, divisor));
            if (q < std.math.minInt(memory_map.Cell) or q > std.math.maxInt(memory_map.Cell)) return error.ResultOutOfRange;
            try self.push(@bitCast(@as(UCell, @intCast(@mod(dividend, @as(Double, divisor))))));
            try self.push(@intCast(q));
        },
        .mux => {
            const mask = try self.pop();
            const b = try self.pop();
            const a = try self.pop();
            try self.push((a & mask) | (b & ~mask));
        },
        .ctz, .log2, .to_pow2, .pow2_query => {
            const value: UCell = @bitCast(try self.pop());
            const answer: UCell = switch (builtin) {
                .ctz => @ctz(value),
                .log2 => if (value == 0) std.math.maxInt(UCell) else 63 - @as(UCell, @clz(value)),
                .pow2_query => if (value != 0 and (value & (value -% 1)) == 0) std.math.maxInt(UCell) else 0,
                .to_pow2 => if (value == 0 or value > (@as(UCell, 1) << 63)) 0 else @as(UCell, 1) << @as(u6, @intCast(64 - @as(UCell, @clz(value - 1)))),
                else => unreachable,
            };
            try self.push(@bitCast(answer));
        },
        .wrol, .wror, .lrol, .lror => {
            const count: UCell = @bitCast(try self.pop());
            const value: UCell = @bitCast(try self.pop());
            const result: UCell = switch (builtin) {
                .wrol => rotate(u16, value, count, true),
                .wror => rotate(u16, value, count, false),
                .lrol => rotate(u32, value, count, true),
                .lror => rotate(u32, value, count, false),
                else => unreachable,
            };
            try self.push(@bitCast(result));
        },
        .drol, .dror => {
            const count: UCell = @bitCast(try self.pop());
            const value: UDouble = @bitCast(try self.popDouble());
            const shift: u7 = @truncate(count);
            const reverse: u7 = 0 -% shift;
            try self.pushDouble(@bitCast(if (builtin == .drol)
                (value << shift) | (value >> reverse)
            else
                (value >> shift) | (value << reverse)));
        },
        .add, .sub, .mul, .div, .mod, .max, .min, .equal, .not_equal, .less, .greater, .less_equal, .greater_equal, .bit_and, .bit_or, .bit_xor, .bit_nand, .bit_nor, .lshift, .rshift, .u_less, .u_greater, .u_less_equal, .u_greater_equal, .u_max, .u_min, .rol, .ror => try self.binary(builtin),
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
        // M*/ ( d1 n1 +n2 -- d2 ): d1 times n1 in three cells, divided by n2 and floored. As
        // gforth does, n2 is taken as unsigned and a quotient too big for d2 wraps.
        .m_star_slash => {
            const divisor: UCell = @bitCast(try self.pop());
            const factor = try self.pop();
            const number = try self.popDouble();
            if (divisor == 0) return error.DivisionByZero;
            const product = @as(i256, number) * factor;
            try self.pushDouble(@truncate(@divFloor(product, @as(i256, divisor))));
        },
        .du_less, .du_less_equal, .du_greater, .du_greater_equal => {
            const b: UDouble = @bitCast(try self.popDouble());
            const a: UDouble = @bitCast(try self.popDouble());
            try self.push(truth(switch (builtin) {
                .du_less => a < b,
                .du_less_equal => a <= b,
                .du_greater => a > b,
                .du_greater_equal => a >= b,
                else => unreachable,
            }));
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
        .zero_less_equal => try self.push(truth(try self.pop() <= 0)),
        .zero_greater_equal => try self.push(truth(try self.pop() >= 0)),
        // UNDER+ ( n1 n2 n3 -- n1+n3 n2 )
        .under_plus => {
            const addend = try self.pop();
            const top = try self.pop();
            try self.push((try self.pop()) +% addend);
            try self.push(top);
        },
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
        .d_zero_less_equal => try self.push(truth(try self.popDouble() <= 0)),
        .d_zero_not_equal => try self.push(truth(try self.popDouble() != 0)),
        .d_zero_greater => try self.push(truth(try self.popDouble() > 0)),
        .d_zero_greater_equal => try self.push(truth(try self.popDouble() >= 0)),
        .d_equal, .d_less, .d_less_equal, .d_not_equal, .d_greater, .d_greater_equal => {
            const b = try self.popDouble();
            const a = try self.popDouble();
            try self.push(truth(switch (builtin) {
                .d_equal => a == b,
                .d_less => a < b,
                .d_less_equal => a <= b,
                .d_not_equal => a != b,
                .d_greater => a > b,
                .d_greater_equal => a >= b,
                else => unreachable,
            }));
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

/// Narrow rotations discard upper input bits and wrap the count at the operand width.
fn rotate(comptime T: type, value: UCell, count: UCell, left: bool) UCell {
    const bits: T = @truncate(value);
    const Shift = std.math.Log2Int(T);
    const shift: Shift = @truncate(count);
    const reverse: Shift = 0 -% shift;
    return if (left) (bits << shift) | (bits >> reverse) else (bits >> shift) | (bits << reverse);
}
