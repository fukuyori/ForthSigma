//! Floating-point stack, arithmetic, memory, conversion, and output words.

const std = @import("std");
const defs = @import("defs.zig");
const float_format = @import("float_format.zig");
const float_math = @import("float_math.zig");
const forth = @import("../forth.zig");
const integer_math = @import("integer_math.zig");
const memory_map = @import("memory_map.zig");
const number_io = @import("number_io.zig");
const Builtin = defs.Builtin;
const Cell = memory_map.Cell;
const Float = memory_map.Float;
const RuntimeError = defs.RuntimeError;
const State = forth.State;
const cr_acos = float_math.cr_acos;
const cr_acosh = float_math.cr_acosh;
const cr_asin = float_math.cr_asin;
const cr_asinh = float_math.cr_asinh;
const cr_atan = float_math.cr_atan;
const cr_atan2 = float_math.cr_atan2;
const cr_atanh = float_math.cr_atanh;
const cr_cos = float_math.cr_cos;
const cr_cosh = float_math.cr_cosh;
const cr_exp = float_math.cr_exp;
const cr_exp10 = float_math.cr_exp10;
const cr_expm1 = float_math.cr_expm1;
const cr_log = float_math.cr_log;
const cr_log10 = float_math.cr_log10;
const cr_log1p = float_math.cr_log1p;
const cr_sin = float_math.cr_sin;
const cr_sinh = float_math.cr_sinh;
const cr_tan = float_math.cr_tan;
const cr_tanh = float_math.cr_tanh;
const floatToCell = integer_math.floatToCell;
const floatToDouble = integer_math.floatToDouble;
const float_size = memory_map.float_size;
const formatRdp = float_format.formatRdp;
const hold_bottom = memory_map.hold_bottom;
const max_dot_s_items = memory_map.max_dot_s_items;
const max_rdp_width = float_format.max_rdp_width;
const parseFloat = number_io.parseFloat;
const power = float_math.power;
const precision_address = memory_map.precision_address;
const roundHalfEven = float_math.roundHalfEven;
const trig = float_math.trig;
const true_flag = memory_map.true_flag;
const truth = integer_math.truth;
const unary = float_math.unary;

/// The built-in words this file executes; executeBuiltin dispatches by this list.
pub const words = [_]Builtin{
    .f_input, .f_drop, .f_dup, .f_swap, .f_over, .f_rot, .f_minus_rot, .f_nip, .f_tuck, .f_pick,
    .f_depth, .f_dot_s, .f_add, .f_sub, .f_mul, .f_div, .f_max, .f_min, .f_negate, .f_abs, .f_sqrt,
    .f_exp, .f_ln, .f_sin, .f_cos, .f_tan, .f_equal, .f_not_equal, .f_less, .f_greater,
    .f_less_equal, .f_greater_equal, .f_zero_equal, .f_zero_not_equal, .f_zero_less,
    .f_zero_greater, .f_zero_less_equal, .f_zero_greater_equal, .f_fetch, .f_store, .f_comma,
    .f_array_fetch, .f_array_store, .f_add_store, .f_question, .floats, .float_plus, .s_to_f,
    .f_to_s, .pi, .f_dot, .d_to_f, .f_to_d, .to_float, .f_dot_rdp, .f_to_str_rdp, .f_to_buf_rdp,
    .f_floor, .f_trunc, .f_round, .f_e_dot, .f_s_dot, .precision, .set_precision, .f_proximate,
    .sf_fetch, .sf_store, .df_fetch, .df_store, .sfloats, .dfloats, .sfloat_plus, .dfloat_plus,
    .f_align, .f_aligned, .sf_align, .sf_aligned, .df_align, .df_aligned, .f_sincos, .f_asin,
    .f_acos, .f_atan, .f_atan2, .f_sinh, .f_cosh, .f_tanh, .f_asinh, .f_acosh, .f_atanh,
    .f_expm1, .f_lnp1, .f_log, .f_alog, .f_power,
};

pub fn execute(self: *State, comptime builtin: Builtin) RuntimeError!void {
    switch (builtin) {
        .f_input => {
            var line: [4096]u8 = undefined;
            while (true) {
                const token = try self.readInputToken(&line) orelse continue;
                const parsed = parseFloat(token, false) orelse {
                    self.write(" ?\n");
                    continue;
                };
                try self.fpush(parsed);
                break;
            }
        },
        .f_drop => _ = try self.fpop(),
        .f_dup => try self.fpush(try self.fpeek(0)),
        .f_swap => {
            try self.requireFloatDepth(2);
            std.mem.swap(Float, &self.float_stack[self.float_depth - 1], &self.float_stack[self.float_depth - 2]);
        },
        .f_over => try self.fpush(try self.fpeek(1)),
        .f_rot, .f_minus_rot => {
            try self.requireFloatDepth(3);
            const items = self.float_stack[self.float_depth - 3 .. self.float_depth];
            if (builtin == .f_rot) std.mem.rotate(Float, items, 1) else std.mem.rotate(Float, items, 2);
        },
        .f_nip => {
            const top = try self.fpop();
            _ = try self.fpop();
            try self.fpush(top);
        },
        .f_tuck => {
            try self.requireFloatDepth(2);
            const top = try self.fpeek(0);
            std.mem.swap(Float, &self.float_stack[self.float_depth - 1], &self.float_stack[self.float_depth - 2]);
            try self.fpush(top);
        },
        .f_pick => {
            const depth = try self.pop();
            if (depth < 0) return error.FloatStackUnderflow;
            try self.fpush(try self.fpeek(@intCast(depth)));
        },
        .f_depth => try self.push(@intCast(self.float_depth)),
        .f_dot_s => {
            self.writeDepth(self.float_depth);
            // gforth shows each item as 14 0 17 F.RDP does: exponential notation
            // filling 14 characters (3.0000000000E0).
            var field: [max_rdp_width]u8 = undefined;
            for (self.float_stack[self.float_depth -| max_dot_s_items .. self.float_depth]) |value| {
                self.write(formatRdp(value, 14, 0, 17, &field) catch unreachable);
                self.write(" ");
            }
        },
        .f_add, .f_sub, .f_mul, .f_div, .f_max, .f_min => {
            const b = try self.fpop();
            const a = try self.fpop();
            try self.fpush(switch (builtin) {
                .f_add => a + b,
                .f_sub => a - b,
                .f_mul => a * b,
                .f_div => a / b,
                .f_max => @max(a, b),
                .f_min => @min(a, b),
                else => unreachable,
            });
        },
        .f_negate, .f_abs, .f_sqrt, .f_exp, .f_ln, .f_sin, .f_cos, .f_tan, .f_floor, .f_trunc, .f_round, .f_asin, .f_acos, .f_atan, .f_sinh, .f_cosh, .f_tanh, .f_asinh, .f_acosh, .f_atanh, .f_expm1, .f_lnp1, .f_log, .f_alog => {
            const a = try self.fpop();
            try self.fpush(switch (builtin) {
                .f_negate => -a,
                .f_abs => @abs(a),
                .f_sqrt => @sqrt(a),
                .f_exp => cr_exp(a),
                .f_ln => cr_log(a),
                .f_sin => trig(cr_sin, a),
                .f_cos => trig(cr_cos, a),
                .f_tan => trig(cr_tan, a),
                .f_floor => @floor(a),
                .f_trunc => @trunc(a),
                .f_round => roundHalfEven(a),
                .f_asin => unary(cr_asin, a, .positive),
                .f_acos => unary(cr_acos, a, .positive),
                .f_atan => unary(cr_atan, a, .default),
                .f_sinh => unary(cr_sinh, a, .default),
                .f_cosh => unary(cr_cosh, a, .default),
                .f_tanh => unary(cr_tanh, a, .default),
                .f_asinh => unary(cr_asinh, a, .default),
                .f_acosh => unary(cr_acosh, a, .default),
                .f_atanh => unary(cr_atanh, a, .default),
                .f_expm1 => unary(cr_expm1, a, .default),
                .f_lnp1 => unary(cr_log1p, a, .default),
                .f_log => unary(cr_log10, a, .positive),
                .f_alog => unary(cr_exp10, a, .default),
                else => unreachable,
            });
        },
        .f_sincos => {
            const a = try self.fpop();
            try self.fpush(trig(cr_sin, a));
            try self.fpush(trig(cr_cos, a));
        },
        // FATAN2 ( F: y x -- r ) and F** ( F: x y -- r ).
        .f_atan2 => {
            const x = try self.fpop();
            const y = try self.fpop();
            try self.fpush(cr_atan2(y, x));
        },
        .f_power => {
            const y = try self.fpop();
            const x = try self.fpop();
            try self.fpush(power(x, y));
        },
        // F~ ( F: r1 r2 r3 -- ) ( -- flag ): r3 > 0 compares the difference with r3, a zero
        // r3 the bits (so 0e and -0e differ and a NaN equals itself), and r3 < 0 the
        // difference with |r3| times |r1| + |r2|, as gforth does.
        .f_proximate => {
            const r3 = try self.fpop();
            const r2 = try self.fpop();
            const r1 = try self.fpop();
            const close = if (r3 > 0)
                @abs(r1 - r2) < r3
            else if (r3 == 0)
                @as(u64, @bitCast(r1)) == @as(u64, @bitCast(r2))
            else
                @abs(r1 - r2) < -r3 * (@abs(r1) + @abs(r2));
            try self.push(truth(close));
        },
        .f_e_dot, .f_s_dot => {
            if (self.writeFloatScientific(try self.fpop(), builtin == .f_e_dot)) self.write(" ");
        },
        .precision => try self.push(try self.readCell(precision_address)),
        .set_precision => try self.writeCell(precision_address, try self.pop()),
        // SF@ and SF! use 32-bit IEEE floats; DF@ and DF! are F@ and F!.
        .sf_fetch => {
            const at = try self.memoryAddress(try self.pop(), 4);
            const bits = std.mem.readInt(u32, self.memory[at..][0..4], .little);
            try self.fpush(@as(f32, @bitCast(bits)));
        },
        .sf_store => {
            const at = try self.memoryAddress(try self.pop(), 4);
            const value: f32 = @floatCast(try self.fpop());
            std.mem.writeInt(u32, self.memory[at..][0..4], @bitCast(value), .little);
        },
        .df_fetch => try self.fpush(try self.readFloat(try self.pop())),
        .df_store => {
            const address = try self.pop();
            try self.writeFloat(address, try self.fpop());
        },
        .sfloats => try self.push((try self.pop()) *% 4),
        .dfloats => try self.push((try self.pop()) *% float_size),
        .sfloat_plus => try self.push((try self.pop()) +% 4),
        .dfloat_plus => try self.push((try self.pop()) +% float_size),
        .f_align, .df_align, .sf_align => {
            const size: Cell = if (builtin == .sf_align) 4 else float_size;
            const aligned = (self.data_here + (size - 1)) & ~(size - 1);
            try self.reserveData(aligned - self.data_here);
        },
        .f_aligned, .df_aligned, .sf_aligned => {
            const size: Cell = if (builtin == .sf_aligned) 4 else float_size;
            try self.push(((try self.pop()) +% (size - 1)) & ~(size - 1));
        },
        .f_equal, .f_not_equal, .f_less, .f_greater, .f_less_equal, .f_greater_equal => {
            const b = try self.fpop();
            const a = try self.fpop();
            try self.push(truth(switch (builtin) {
                .f_equal => a == b,
                .f_not_equal => a != b,
                .f_less => a < b,
                .f_greater => a > b,
                .f_less_equal => a <= b,
                .f_greater_equal => a >= b,
                else => unreachable,
            }));
        },
        .f_zero_equal, .f_zero_not_equal, .f_zero_less, .f_zero_greater, .f_zero_less_equal, .f_zero_greater_equal => {
            const a = try self.fpop();
            try self.push(truth(switch (builtin) {
                .f_zero_equal => a == 0,
                .f_zero_not_equal => a != 0,
                .f_zero_less => a < 0,
                .f_zero_greater => a > 0,
                .f_zero_less_equal => a <= 0,
                .f_zero_greater_equal => a >= 0,
                else => unreachable,
            }));
        },
        .f_fetch => try self.fpush(try self.readFloat(try self.pop())),
        .f_store => {
            const address = try self.pop();
            try self.writeFloat(address, try self.fpop());
        },
        .f_comma => {
            const value = try self.fpop();
            const address = self.data_here;
            try self.reserveData(float_size);
            try self.writeFloat(address, value);
        },
        .f_array_fetch => try self.fpush(try self.readFloat(try self.arrayAddress())),
        .f_array_store => {
            const address = try self.arrayAddress();
            try self.writeFloat(address, try self.fpop());
        },
        .f_add_store => {
            const address = try self.pop();
            const value = try self.fpop();
            try self.writeFloat(address, (try self.readFloat(address)) + value);
        },
        .f_question => {
            self.writeFloatFixed(try self.readFloat(try self.pop()));
            self.write(" ");
        },
        .floats => try self.push((try self.pop()) *% float_size),
        .float_plus => try self.push((try self.pop()) +% float_size),
        .s_to_f => try self.fpush(@floatFromInt(try self.pop())),
        .f_to_s => try self.push(floatToCell(try self.fpop())),
        .pi => try self.fpush(std.math.pi),
        .f_dot => {
            self.writeFloatFixed(try self.fpop());
            self.write(" ");
        },
        .d_to_f => try self.fpush(@floatFromInt(try self.popDouble())),
        .f_to_d => try self.pushDouble(floatToDouble(try self.fpop())),
        .to_float => {
            const bytes = try self.memoryRange();
            const blank = std.mem.indexOfNone(u8, bytes, " ") == null;
            if (if (blank) 0 else parseFloat(bytes, false)) |value| {
                try self.fpush(value);
                try self.push(true_flag);
            } else try self.push(0);
        },
        .f_dot_rdp, .f_to_str_rdp, .f_to_buf_rdp => {
            const np = try self.pop();
            const nd = try self.pop();
            const nr = try self.pop();
            const destination: ?Cell = if (builtin == .f_to_buf_rdp) try self.pop() else null;
            const value = try self.fpop();
            var text: [max_rdp_width]u8 = undefined;
            const formatted = try formatRdp(value, nr, nd, np, &text);
            switch (builtin) {
                .f_dot_rdp => self.write(formatted),
                .f_to_buf_rdp => {
                    const start = try self.memoryAddress(destination.?, formatted.len);
                    @memcpy(self.memory[start .. start + formatted.len], formatted);
                },
                else => {
                    // Like gforth, the text goes just below the pictured numeric output
                    // in the hold area and is overwritten by the next conversion.
                    const length: Cell = @intCast(formatted.len);
                    if (self.hold_ptr - hold_bottom < length) return error.PicturedNumericOverflow;
                    const start: usize = @intCast(self.hold_ptr - length);
                    @memcpy(self.memory[start .. start + formatted.len], formatted);
                    try self.push(self.hold_ptr - length);
                    try self.push(length);
                },
            }
        },
        else => @compileError(@tagName(builtin) ++ " is not in the words of this file"),
    }
}
