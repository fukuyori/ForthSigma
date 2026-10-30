//! Integer and double-cell arithmetic, comparison, and logic words.

const defs = @import("defs.zig");
const forth = @import("../forth.zig");
const integer_math = @import("integer_math.zig");
const memory_map = @import("memory_map.zig");
const Builtin = defs.Builtin;
const RuntimeError = defs.RuntimeError;
const State = forth.State;
const UCell = memory_map.UCell;
const flooredDivision = integer_math.flooredDivision;
const true_flag = memory_map.true_flag;
const truth = integer_math.truth;

pub fn execute(self: *State, builtin: Builtin) RuntimeError!void {
    switch (builtin) {
        .add, .sub, .mul, .div, .mod, .max, .min, .equal, .not_equal, .less, .greater, .less_equal, .greater_equal, .bit_and, .bit_or, .bit_xor, .bit_nand, .bit_nor, .lshift, .rshift => try self.binary(builtin),
        .div_mod => {
            const divisor = try self.pop();
            const dividend = try self.pop();
            const result = try flooredDivision(dividend, divisor);
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
        else => unreachable,
    }
}
