//! Dictionary byte allocation and fields. Raw storage never infers address types.
const std = @import("std");
const defs = @import("defs.zig");
const forth = @import("../forth.zig");
const map = @import("memory_map.zig");
const Builtin = defs.Builtin;
const State = forth.State;
const RuntimeError = defs.RuntimeError;
const Cell = map.Cell;
const UCell = map.UCell;

pub const words = [_]Builtin{
    .a_comma,
    .to_here,       .two_field, .l_comma, .l_field, .max_align, .mem_comma,
    .save_mem_dict, .w_comma,   .w_field, .x_comma, .xd_comma,  .x_field,
};

pub fn execute(self: *State, comptime builtin: Builtin) RuntimeError!void {
    switch (builtin) {
        .a_comma => {
            const value = try self.peek(0);
            const address = self.data_here;
            try @import("address_registry.zig").ensureRoom(self, .memory, address);
            try self.reserveData(8);
            try self.writeCell(address, value);
            try @import("address_registry.zig").registerMemory(self, address);
            _ = try self.pop();
        },
        .to_here => {
            const next = try self.peek(0);
            const amount = std.math.sub(Cell, next, self.data_here) catch return error.MemoryExhausted;
            try self.reserveData(amount);
            _ = try self.pop();
        },
        .max_align => {
            const next = (self.data_here + 7) & ~@as(Cell, 7);
            try self.reserveData(next - self.data_here);
        },
        .w_comma, .l_comma, .x_comma, .xd_comma => {
            const count = if (builtin == .xd_comma) 2 else 1;
            try self.requireDepth(count);
            const width = comptime switch (builtin) {
                .w_comma => 2,
                .l_comma => 4,
                else => 8,
            };
            const at: usize = @intCast(self.data_here);
            const value: UCell = @bitCast(try self.peek(count - 1));
            try self.reserveData(width);
            const T = if (width == 2) u16 else if (width == 4) u32 else u64;
            std.mem.writeInt(T, self.memory[at..][0..width], @truncate(value), .little);
            @import("address_registry.zig").written(self, @intCast(at), width, width == 8);
            self.data_depth -= count;
        },
        .mem_comma, .save_mem_dict => {
            try self.requireDepth(2);
            const count: UCell = @bitCast(try self.peek(0));
            if (count > @as(UCell, @intCast(self.sizes.dataLimit() - self.data_here))) return error.MemoryExhausted;
            const length: usize = @intCast(count);
            const from = try self.memoryAddress(try self.peek(1), length);
            const destination = self.data_here;

            try self.reserveData(@intCast(length));
            self.copyMemory(destination, @intCast(from), length) catch |err| {
                self.data_here = destination;
                return err;
            };
            self.data_depth -= 2;
            if (builtin == .save_mem_dict) {
                try self.push(destination);
                try self.push(@intCast(length));
            }
        },
        .two_field, .w_field, .l_field, .x_field => {
            const size: Cell = switch (builtin) {
                .two_field => 16,
                .w_field => 2,
                .l_field => 4,
                else => 8,
            };
            const mask: Cell = @min(size, 8) - 1;
            const old = try self.peek(0);
            const offset = (old +% mask) & ~mask;
            const name = (try self.nextSourceToken()) orelse return error.InvalidDefinition;
            _ = try self.appendWord(name, .field, .drop, offset);
            self.data_stack[self.data_depth - 1] = offset +% size;
        },
        else => @compileError(@tagName(builtin) ++ " is not a data word"),
    }
}
