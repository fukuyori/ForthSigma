//! Exception controls, errno adapters, assertion levels and warning policy.
const std = @import("std");
const forth = @import("../forth.zig");
const defs = @import("defs.zig");
const map = @import("memory_map.zig");
pub const words = [_]defs.Builtin{ .assert_close, .errno_throw, .question_ior, .assert_level, .assert_zero, .assert_one, .assert_two, .assert_three, .catch_nobt, .fast_throw, .nothrow, .warning_quote, .warnings, .warning_run };
pub fn execute(self: *forth.State, comptime word: defs.Builtin) forth.RuntimeError!void {
    switch (word) {
        .assert_close => return error.ControlMismatch,
        .assert_level => try self.push(map.assert_level_address),
        .warnings => try self.push(map.warnings_address),
        .assert_zero, .assert_one, .assert_two, .assert_three => {
            const level: map.Cell = switch (word) {
                .assert_zero => 0,
                .assert_one => 1,
                .assert_two => 2,
                .assert_three => 3,
                else => unreachable,
            };
            try @import("words_tools.zig").assertion(self, level);
        },
        .catch_nobt => try @import("words_system.zig").runCatch(self, true),
        .nothrow => self.clearBacktrace(),
        .fast_throw => {
            if (try self.peek(0) != 0) self.throw_nobt = true;
            try self.executeBuiltin(.throw);
        },
        .errno_throw, .question_ior => {
            const flag = try self.pop();
            if (if (word == .errno_throw) flag != 0 else flag == -1) {
                const get = self.writer.errno_fn orelse return error.HostUnavailable;
                const number = get(self.writer.context);
                if (number < 0 or number > std.math.maxInt(i32)) return error.InvalidNumber;
                if (number != 0) return self.throwCode(map.errnoIor(number));
            }
        },
        .warning_quote => {
            try self.requireCompiling();
            const start = self.sourceCursor();
            const end = std.mem.indexOfScalarPos(u8, self.source_line, start, '"') orelse return error.StringTooLong;
            try self.compileCountedString(self.source_line[start..end], .string_literal);
            _ = try self.emit(.{ .kind = .builtin, .value = @backingInt(defs.Builtin.warning_run) });
            self.setSourceCursor(end + 1);
        },
        .warning_run => {
            try self.requireDepth(3);
            const text = try self.memoryRange();
            if (try self.pop() == 0) return;
            const level = self.readCellConst(map.warnings_address);
            if (level == 0) return;
            const output = @import("words_tools.zig").writeError;
            output(self, "WARNING: ");
            output(self, text);
            output(self, "\n");
            if (level == -4) return error.WarningError;
        },
        else => unreachable,
    }
}
