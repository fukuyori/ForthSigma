//! Terminal input and parsing words.

const std = @import("std");
const defs = @import("defs.zig");
const forth = @import("../forth.zig");
const integer_math = @import("integer_math.zig");
const memory_map = @import("memory_map.zig");
const Builtin = defs.Builtin;
const ParsedNumber = defs.ParsedNumber;
const RuntimeError = defs.RuntimeError;
const State = forth.State;
const UCell = memory_map.UCell;
const doubleCells = defs.doubleCells;
const max_gforth_string = memory_map.max_gforth_string;
const truth = integer_math.truth;
const word_buffer_address = memory_map.word_buffer_address;

pub fn execute(self: *State, builtin: Builtin) RuntimeError!void {
    switch (builtin) {
        .input => {
            var line: [4096]u8 = undefined;
            while (true) {
                const token = try self.readInputToken(&line) orelse continue;
                const parsed = try self.parseNumber(token) orelse ParsedNumber{ .value = 0, .double = true };
                if (parsed.double) {
                    self.write(" ?\n");
                    continue;
                }
                try self.push(doubleCells(parsed.value).low);
                break;
            }
        },
        .accept => {
            const capacity = try self.pop();
            const address = try self.pop();
            const read_fn = self.writer.read_fn orelse return error.InputUnavailable;
            var line: [4096]u8 = undefined;
            const input = read_fn(self.writer.context, &line) orelse &.{};
            const length: usize = @min(input.len, @as(usize, @intCast(@max(capacity, 0))));
            const start = try self.memoryAddress(address, length);
            @memcpy(self.memory[start .. start + length], input[0..length]);
            try self.push(@intCast(length));
        },
        .evaluate => try self.interpretSource(try self.memoryRange(), .evaluate),
        .key => {
            const key_fn = self.writer.key_fn orelse return error.InputUnavailable;
            try self.push(key_fn(self.writer.context) orelse return error.InputUnavailable);
        },
        .key_question => {
            const ready = if (self.writer.key_ready_fn) |ready_fn| ready_fn(self.writer.context) else false;
            try self.push(truth(ready));
        },
        .word_parse => {
            const delimiter: u8 = @truncate(@as(UCell, @bitCast(try self.pop())));
            const text = self.parseWordText(delimiter);
            if (text.len > max_gforth_string) return error.StringTooLong;
            const start: usize = @intCast(word_buffer_address);
            // The text may lie in the buffer of an earlier WORD result.
            std.mem.copyForwards(u8, self.memory[start + 1 .. start + 1 + text.len], text);
            self.memory[start] = @intCast(text.len);
            try self.push(word_buffer_address);
        },
        .parse => {
            const delimiter: u8 = @truncate(@as(UCell, @bitCast(try self.pop())));
            if (!self.sourceInMemory()) {
                try self.push(0);
                try self.push(0);
                return;
            }
            const address = self.sourceAddress();
            const rest = self.remainingSource();
            const length = for (rest, 0..) |byte, index| {
                if (byte == delimiter) break index;
            } else rest.len;
            self.source_cursor += if (length < rest.len) length + 1 else length;
            try self.push(address);
            try self.push(@intCast(length));
        },
        else => unreachable,
    }
}
