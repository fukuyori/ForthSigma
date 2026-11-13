//! Fixed-width access to little-endian logical memory. These exchanges are not atomic.
const std = @import("std");
const defs = @import("defs.zig");
const forth = @import("../forth.zig");
const map = @import("memory_map.zig");
const State = forth.State;
const Builtin = defs.Builtin;
const RuntimeError = defs.RuntimeError;
const Cell = map.Cell;
const UCell = map.UCell;

pub const words = [_]Builtin{
    .exchange_store, .star_align, .star_aligned, .add_exchange, .slash_l,         .slash_w,     .slash_x,
    .c_to_s,         .cell_slash, .char_minus,   .dfloat_slash, .float_size_word, .float_slash, .l_store,
    .l_to_s,         .l_fetch,    .l_align,      .l_aligned,    .l_be,            .l_le,        .max_aligned,
    .sfloat_slash,   .th,         .th_store,     .th_fetch,     .w_store,         .w_to_s,      .w_fetch,
    .w_align,        .w_aligned,  .w_be,         .w_le,         .x_store,         .x_to_s,      .x_fetch,
    .x_align,        .x_aligned,  .x_be,         .xd_store,     .xd_to_s,         .xd_fetch,    .xd_be,
    .xd_le,          .x_le,
};

pub fn execute(self: *State, comptime builtin: Builtin) RuntimeError!void {
    switch (builtin) {
        .slash_w => try self.push(2),
        .slash_l => try self.push(4),
        .slash_x, .float_size_word => try self.push(8),
        .cell_slash, .float_slash, .dfloat_slash => try self.push((try self.pop()) >> 3),
        .sfloat_slash => try self.push((try self.pop()) >> 2),
        .char_minus => try self.push((try self.pop()) -% 1),
        .c_to_s => try self.push(@as(i8, @bitCast(@as(u8, @truncate(@as(UCell, @bitCast(try self.pop()))))))),
        .w_to_s => try self.push(@as(i16, @bitCast(@as(u16, @truncate(@as(UCell, @bitCast(try self.pop()))))))),
        .l_to_s => try self.push(@as(i32, @bitCast(@as(u32, @truncate(@as(UCell, @bitCast(try self.pop()))))))),
        .x_to_s => {
            const value = try self.pop();
            try self.push(value);
        },
        // On the designated 64-bit Gforth XD>S consumes one cell, like S>D.
        .xd_to_s => try self.pushDouble(try self.pop()),
        .w_fetch, .l_fetch, .x_fetch, .xd_fetch => {
            const width = comptime accessWidth(builtin);
            const at = try self.memoryAddress(try self.pop(), width);
            const value: UCell = std.mem.readInt((if (width == 2) u16 else if (width == 4) u32 else u64), self.memory[at..][0..width], .little);
            if (builtin == .xd_fetch) try self.pushDouble(@as(map.Double, value)) else try self.push(@bitCast(value));
        },
        .w_store, .l_store, .x_store, .xd_store => {
            try self.requireDepth(if (builtin == .xd_store) 3 else 2);
            const width = comptime accessWidth(builtin);
            const at = try self.memoryAddress(try self.pop(), width);
            const value: UCell = if (builtin == .xd_store) @truncate(@as(map.UDouble, @bitCast(try self.popDouble()))) else @bitCast(try self.pop());
            std.mem.writeInt((if (width == 2) u16 else if (width == 4) u32 else u64), self.memory[at..][0..width], @truncate(value), .little);
            @import("address_registry.zig").written(self, @intCast(at), width, width == 8);
        },
        .exchange_store, .add_exchange => {
            try self.requireDepth(2);
            const address = try self.pop();
            const value = try self.pop();
            const old = try self.readCell(address);
            try self.writeCell(address, if (builtin == .add_exchange) old +% value else value);
            try self.push(old);
        },
        .th, .th_fetch, .th_store => {
            const index = try self.pop();
            const address = (try self.pop()) +% (index *% 8);
            if (builtin == .th) try self.push(address) else if (builtin == .th_fetch)
                try self.push(try self.readCell(address))
            else
                try self.writeCell(address, try self.pop());
        },
        .w_le, .l_le, .x_le => {
            const value = try self.pop();
            try self.push(value);
        },
        .w_be, .l_be, .x_be => {
            const value: UCell = @bitCast(try self.pop());
            const result: UCell = switch (builtin) {
                .w_be => @byteSwap(@as(u16, @truncate(value))),
                .l_be => @byteSwap(@as(u32, @truncate(value))),
                .x_be => @byteSwap(value),
                else => unreachable,
            };
            try self.push(@bitCast(result));
        },
        .xd_le => try self.pushDouble(try self.popDouble()),
        .xd_be => {
            const value: UCell = @truncate(@as(map.UDouble, @bitCast(try self.popDouble())));
            try self.pushDouble(@as(map.Double, @byteSwap(value)));
        },
        .star_aligned, .w_aligned, .l_aligned, .x_aligned, .max_aligned => {
            const alignment: UCell = if (builtin == .star_aligned) @bitCast(try self.pop()) else if (builtin == .w_aligned) 2 else if (builtin == .l_aligned) 4 else 8;
            const address = try self.pop();
            try self.push(try aligned(address, alignment));
        },
        .star_align, .w_align, .l_align, .x_align => {
            const alignment: UCell = if (builtin == .star_align) @bitCast(try self.pop()) else if (builtin == .w_align) 2 else if (builtin == .l_align) 4 else 8;
            const next = try aligned(self.data_here, alignment);
            // reserveData validates the whole increment before changing HERE.
            const amount = std.math.sub(Cell, next, self.data_here) catch return error.MemoryExhausted;
            if (amount < 0) return error.MemoryExhausted;
            try self.reserveData(amount);
        },
        else => @compileError(@tagName(builtin) ++ " is not a width word"),
    }
}

fn accessWidth(comptime builtin: Builtin) comptime_int {
    return switch (builtin) {
        .w_fetch, .w_store => 2,
        .l_fetch, .l_store => 4,
        else => 8,
    };
}
fn aligned(address: Cell, alignment: UCell) RuntimeError!Cell {
    if (alignment == 0 or alignment & (alignment - 1) != 0) return error.ResultOutOfRange;
    const bits: UCell = @bitCast(address);
    return @bitCast((bits +% (alignment - 1)) & ~(alignment - 1));
}
