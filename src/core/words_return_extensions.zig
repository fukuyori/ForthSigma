//! User return-stack access; VM call frames, loops and locals remain separate.
const std = @import("std");
const defs = @import("defs.zig");
const forth = @import("../forth.zig");
pub const words = [_]defs.Builtin{ .f_to_r, .f_r_from, .f_r_fetch, .r_second_fetch, .r_pick };
pub const float_words = [_]defs.Builtin{ .f_to_r, .f_r_from, .f_r_fetch };
pub fn execute(self: *forth.State, comptime word: defs.Builtin) forth.RuntimeError!void {
    switch (word) {
        .f_to_r => {
            try self.requireFloatDepth(1);
            if (self.return_depth == self.return_stack.len) return error.ReturnStackOverflow;
            const value = defs.floatBits(try self.fpop());
            self.return_stack[self.return_depth] = value;
            self.return_depth += 1;
        },
        .f_r_from, .f_r_fetch => {
            if (self.return_depth == 0) return error.ReturnStackUnderflow;
            if (self.float_depth == self.float_stack.len) return error.FloatStackOverflow;
            try self.fpush(defs.bitsFloat(self.return_stack[self.return_depth - 1]));
            if (word == .f_r_from) self.return_depth -= 1;
        },
        .r_second_fetch => {
            if (self.return_depth < 2) return error.ReturnStackUnderflow;
            try self.push(self.return_stack[self.return_depth - 2]);
        },
        .r_pick => {
            const index = try self.peek(0);
            const at = std.math.cast(usize, index) orelse return error.ReturnStackUnderflow;
            if (at >= self.return_depth) return error.ReturnStackUnderflow;
            self.data_stack[self.data_depth - 1] = self.return_stack[self.return_depth - 1 - at];
        },
        else => unreachable,
    }
}
