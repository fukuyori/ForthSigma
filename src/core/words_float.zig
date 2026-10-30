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
const cr_cos = float_math.cr_cos;
const cr_exp = float_math.cr_exp;
const cr_log = float_math.cr_log;
const cr_sin = float_math.cr_sin;
const cr_tan = float_math.cr_tan;
const floatToCell = integer_math.floatToCell;
const floatToDouble = integer_math.floatToDouble;
const float_size = memory_map.float_size;
const formatRdp = float_format.formatRdp;
const hold_bottom = memory_map.hold_bottom;
const max_dot_s_items = memory_map.max_dot_s_items;
const max_rdp_width = float_format.max_rdp_width;
const parseFloat = number_io.parseFloat;
const trig = float_math.trig;
const true_flag = memory_map.true_flag;
const truth = integer_math.truth;

pub fn execute(self: *State, builtin: Builtin) RuntimeError!void {
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
        .f_negate, .f_abs, .f_sqrt, .f_exp, .f_ln, .f_sin, .f_cos, .f_tan => {
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
                else => unreachable,
            });
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
        else => unreachable,
    }
}
