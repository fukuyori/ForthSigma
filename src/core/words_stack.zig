//! Data and return stack words.

const std = @import("std");
const defs = @import("defs.zig");
const forth = @import("../forth.zig");
const memory_map = @import("memory_map.zig");
const Builtin = defs.Builtin;
const Cell = memory_map.Cell;
const RuntimeError = defs.RuntimeError;
const State = forth.State;
const max_stack = memory_map.max_stack;

/// The built-in words this file executes; executeBuiltin dispatches by this list.
pub const words = [_]Builtin{
    .drop, .dup, .swap, .over, .rot, .minus_rot, .nip, .tuck, .pick, .roll, .two_dup, .two_drop,
    .two_swap, .two_over, .depth, .to_r, .from_r, .r_fetch, .two_to_r, .two_r_from, .two_r_fetch,
    .question_dup, .two_rot,
};

pub fn execute(self: *State, comptime builtin: Builtin) RuntimeError!void {
    switch (builtin) {
        .drop => _ = try self.pop(),
        .dup => try self.push(try self.peek(0)),
        .swap => {
            try self.requireDepth(2);
            std.mem.swap(Cell, &self.data_stack[self.data_depth - 1], &self.data_stack[self.data_depth - 2]);
        },
        .over => try self.push(try self.peek(1)),
        .rot, .minus_rot => {
            try self.requireDepth(3);
            const items = self.data_stack[self.data_depth - 3 .. self.data_depth];
            if (builtin == .rot) std.mem.rotate(Cell, items, 1) else std.mem.rotate(Cell, items, 2);
        },
        .nip => {
            const top = try self.pop();
            _ = try self.pop();
            try self.push(top);
        },
        .tuck => {
            try self.requireDepth(2);
            const top = try self.peek(0);
            std.mem.swap(Cell, &self.data_stack[self.data_depth - 1], &self.data_stack[self.data_depth - 2]);
            try self.push(top);
        },
        .pick => {
            const depth = try self.pop();
            if (depth < 0) return error.StackUnderflow;
            try self.push(try self.peek(@intCast(depth)));
        },
        .roll => {
            const depth = try self.pop();
            if (depth < 0) return error.StackUnderflow;
            const count: usize = @intCast(depth);
            try self.requireDepth(count + 1);
            std.mem.rotate(Cell, self.data_stack[self.data_depth - count - 1 .. self.data_depth], 1);
        },
        .two_dup => {
            const second = try self.peek(1);
            const top = try self.peek(0);
            try self.push(second);
            try self.push(top);
        },
        .two_drop => {
            try self.requireDepth(2);
            self.data_depth -= 2;
        },
        .two_swap => {
            try self.requireDepth(4);
            std.mem.rotate(Cell, self.data_stack[self.data_depth - 4 .. self.data_depth], 2);
        },
        .two_over => {
            const fourth = try self.peek(3);
            const third = try self.peek(2);
            try self.push(fourth);
            try self.push(third);
        },
        .depth => try self.push(@intCast(self.data_depth)),
        .to_r => {
            const value = try self.pop();
            if (self.return_depth == max_stack) return error.ReturnStackOverflow;
            self.return_stack[self.return_depth] = value;
            self.return_depth += 1;
        },
        .from_r => {
            if (self.return_depth == 0) return error.ReturnStackUnderflow;
            self.return_depth -= 1;
            try self.push(self.return_stack[self.return_depth]);
        },
        .r_fetch => {
            if (self.return_depth == 0) return error.ReturnStackUnderflow;
            try self.push(self.return_stack[self.return_depth - 1]);
        },
        // Copies the pair 2>R moved, in the same order, and leaves it on the return stack.
        .two_r_fetch => {
            if (self.return_depth < 2) return error.ReturnStackUnderflow;
            if (max_stack - self.data_depth < 2) return error.StackOverflow;
            try self.push(self.return_stack[self.return_depth - 2]);
            try self.push(self.return_stack[self.return_depth - 1]);
        },
        // ( x1 x2 x3 x4 x5 x6 -- x3 x4 x5 x6 x1 x2 )
        .two_rot => {
            try self.requireDepth(6);
            const base = self.data_depth - 6;
            const first = self.data_stack[base];
            const second = self.data_stack[base + 1];
            std.mem.copyForwards(Cell, self.data_stack[base .. base + 4], self.data_stack[base + 2 .. base + 6]);
            self.data_stack[base + 4] = first;
            self.data_stack[base + 5] = second;
        },
        .question_dup => {
            const value = try self.peek(0);
            if (value != 0) try self.push(value);
        },
        .two_to_r => {
            try self.requireDepth(2);
            if (max_stack - self.return_depth < 2) return error.ReturnStackOverflow;
            const second = try self.pop();
            const first = try self.pop();
            self.return_stack[self.return_depth] = first;
            self.return_stack[self.return_depth + 1] = second;
            self.return_depth += 2;
        },
        .two_r_from => {
            if (self.return_depth < 2) return error.ReturnStackUnderflow;
            if (max_stack - self.data_depth < 2) return error.StackOverflow;
            self.return_depth -= 2;
            try self.push(self.return_stack[self.return_depth]);
            try self.push(self.return_stack[self.return_depth + 1]);
        },
        else => @compileError(@tagName(builtin) ++ " is not in the words of this file"),
    }
}
