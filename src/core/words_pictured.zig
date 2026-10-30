//! Pictured numeric output and number conversion words.

const defs = @import("defs.zig");
const forth = @import("../forth.zig");
const integer_math = @import("integer_math.zig");
const memory_map = @import("memory_map.zig");
const number_io = @import("number_io.zig");
const Builtin = defs.Builtin;
const RuntimeError = defs.RuntimeError;
const State = forth.State;
const UCell = memory_map.UCell;
const UDouble = memory_map.UDouble;
const digitValue = number_io.digitValue;
const max_gforth_string = memory_map.max_gforth_string;
const max_hold_nesting = memory_map.max_hold_nesting;
const truth = integer_math.truth;

pub fn execute(self: *State, builtin: Builtin) RuntimeError!void {
    switch (builtin) {
        .hold_start => self.resetHold(),
        .hold_nest => {
            if (self.hold_depth == max_hold_nesting) return error.PicturedNumericOverflow;
            self.hold_stack[self.hold_depth] = self.hold_end;
            self.hold_depth += 1;
            self.hold_end = self.hold_ptr;
        },
        .hold_release => {
            if (self.hold_depth == 0) return error.PicturedNumericOverflow;
            self.hold_depth -= 1;
            self.hold_ptr = self.hold_end;
            self.hold_end = self.hold_stack[self.hold_depth];
        },
        .hold_digit => try self.pushDouble(@bitCast(try self.holdDigit(@bitCast(try self.popDouble())))),
        .hold_digits => {
            var value: UDouble = @bitCast(try self.popDouble());
            while (true) {
                value = try self.holdDigit(value);
                if (value == 0) break;
            }
            try self.pushDouble(0);
        },
        .hold_finish => {
            _ = try self.popDouble();
            try self.push(self.hold_ptr);
            try self.push(self.hold_end - self.hold_ptr);
        },
        .hold => try self.holdBytes(&.{@truncate(@as(UCell, @bitCast(try self.pop())))}),
        .holds => {
            const bytes = try self.memoryRange();
            var copy: [max_gforth_string]u8 = undefined;
            if (bytes.len > copy.len) return error.PicturedNumericOverflow;
            @memcpy(copy[0..bytes.len], bytes);
            try self.holdBytes(copy[0..bytes.len]);
        },
        .sign => {
            if (try self.pop() < 0) try self.holdBytes("-");
        },
        .to_number => {
            const count = try self.pop();
            var address = try self.pop();
            var value: UDouble = @bitCast(try self.popDouble());
            const base = try self.validBase();
            var remaining = count;
            while (remaining > 0) : (remaining -= 1) {
                const at = try self.memoryAddress(address, 1);
                const digit = digitValue(self.memory[at]) orelse break;
                if (digit >= base) break;
                value = value *% @as(UDouble, @intCast(base)) +% @as(UDouble, @intCast(digit));
                address += 1;
            }
            try self.pushDouble(@bitCast(value));
            try self.push(address);
            try self.push(remaining);
        },
        .string_to_number => {
            const parsed = try self.parseNumber(try self.memoryRange());
            try self.pushDouble(if (parsed) |number| number.value else 0);
            try self.push(truth(parsed != null));
        },
        else => unreachable,
    }
}
