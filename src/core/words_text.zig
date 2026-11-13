//! Basic characters and borrowed string operations. ASCII folding is bytewise.
const std = @import("std");
const defs = @import("defs.zig");
const forth = @import("../forth.zig");
const map = @import("memory_map.zig");
const truth = @import("integer_math.zig").truth;
const checkWork = @import("words_numeric.zig").checkWorkBlock;
const RuntimeError = defs.RuntimeError;
const State = forth.State;
pub const words = [_]defs.Builtin{
    .number_bell,  .number_bs, .number_cr,  .number_del,   .number_eof,  .number_esc,  .number_ff, .number_lf,     .number_tab,
    .invalid_char, .newline,   .to_upper,   .caps_compare, .caps_search, .caps_prefix, .str_less,  .string_suffix, .safe_slash_string,
    .scan_back,    .no_split,  .type_white,
};
pub fn execute(self: *State, comptime builtin: defs.Builtin) RuntimeError!void {
    switch (builtin) {
        .number_bell, .number_bs, .number_cr, .number_del, .number_eof, .number_esc, .number_ff, .number_lf, .number_tab, .invalid_char => try self.push(switch (builtin) {
            .number_bell => 7,
            .number_bs => 8,
            .number_cr => 13,
            .number_del => 127,
            .number_eof => 4,
            .number_esc => 27,
            .number_ff => 12,
            .number_lf => 10,
            .number_tab => 9,
            .invalid_char => 0xfffd,
            else => unreachable,
        }),
        .newline => {
            if (self.data_depth > self.data_stack.len - 2) return error.StackOverflow;
            try self.push(map.newline_address);
            try self.push(1);
        },
        .to_upper => {
            const value = try self.peek(0);
            self.data_stack[self.data_depth - 1] = if (value >= 'a' and value <= 'z') value - 32 else value;
        },
        .caps_compare, .caps_search, .caps_prefix, .str_less, .string_suffix => {
            try self.requireDepth(4);
            const first_address = try self.peek(3);
            const first = try bytes(self, first_address, try self.peek(2));
            const second = try bytes(self, try self.peek(1), try self.peek(0));
            var result: map.Cell = 0;
            if (builtin == .caps_search) {
                var offset: ?usize = null;
                if (second.len <= first.len) {
                    for (0..first.len - second.len + 1) |i| {
                        try work(self, i);
                        if (try compare(self, first[i..][0..second.len], second, true) == 0) {
                            offset = i;
                            break;
                        }
                    }
                }
                self.data_depth -= 4;
                const skipped = offset orelse 0;
                try self.push(first_address + @as(map.Cell, @intCast(skipped)));
                try self.push(@intCast(first.len - skipped));
                try self.push(truth(offset != null));
                return;
            }
            if (builtin == .caps_compare or builtin == .str_less) {
                result = try compare(self, first, second, builtin == .caps_compare);
                if (builtin == .str_less) result = truth(result < 0);
            } else if (second.len <= first.len) {
                const at = if (builtin == .string_suffix) first.len - second.len else 0;
                result = truth(try compare(self, first[at..][0..second.len], second, builtin == .caps_prefix) == 0);
            }
            self.data_depth -= 4;
            try self.push(result);
        },
        .safe_slash_string => {
            try self.requireDepth(3);
            const address = try self.peek(2);
            const text = try bytes(self, address, try self.peek(1));
            const n = try self.peek(0);
            const skipped: usize = if (n < 0) 0 else @intCast(@min(@as(map.UCell, @intCast(n)), text.len));
            self.data_depth -= 3;
            try self.push(address + @as(map.Cell, @intCast(skipped)));
            try self.push(@intCast(text.len - skipped));
        },
        .scan_back => {
            try self.requireDepth(3);
            const address = try self.peek(2);
            const text = try bytes(self, address, try self.peek(1));
            const needle = try self.peek(0);
            var length = text.len;
            while (length != 0) {
                try work(self, text.len - length);
                if (text[length - 1] == needle) break;
                length -= 1;
            }
            self.data_depth -= 3;
            try self.push(address);
            try self.push(@intCast(length));
        },
        .no_split => {
            try self.requireDepth(4);
            if (self.data_depth == self.data_stack.len) return error.StackOverflow;
            const at_end = (try self.peek(3)) +% (try self.peek(2)) == try self.peek(1);
            try self.push(truth((try self.peek(0)) == 0 and at_end));
        },
        .type_white => {
            try self.requireDepth(2);
            const text = try bytes(self, try self.peek(1), @max(0, try self.peek(0)));
            self.data_depth -= 2;
            for (text, 0..) |byte, i| {
                try work(self, i);
                self.write(if (byte == 9) "\t" else " ");
            }
        },
        else => @compileError("unexpected text word"),
    }
}
fn bytes(self: *State, address: map.Cell, count: map.Cell) RuntimeError![]const u8 {
    const length = std.math.cast(usize, @as(map.UCell, @bitCast(count))) orelse return error.InvalidAddress;
    const at = try self.memoryAddress(address, length);
    return self.memory[at..][0..length];
}
fn compare(self: *State, first: []const u8, second: []const u8, fold: bool) RuntimeError!map.Cell {
    for (0..@min(first.len, second.len)) |i| {
        try work(self, i);
        const a = if (fold) std.ascii.toUpper(first[i]) else first[i];
        const b = if (fold) std.ascii.toUpper(second[i]) else second[i];
        if (a != b) return if (a < b) -1 else 1;
    }
    return if (first.len < second.len) -1 else if (first.len > second.len) 1 else 0;
}
fn work(self: *State, i: usize) RuntimeError!void {
    if (i % 256 == 0) try checkWork(self);
}
