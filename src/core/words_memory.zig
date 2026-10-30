//! Memory access, data space, and ALLOCATE words.

const std = @import("std");
const defs = @import("defs.zig");
const forth = @import("../forth.zig");
const memory_map = @import("memory_map.zig");
const Builtin = defs.Builtin;
const Cell = memory_map.Cell;
const RuntimeError = defs.RuntimeError;
const State = forth.State;
const UCell = memory_map.UCell;
const cell_size = memory_map.cell_size;
const errnoIor = memory_map.errnoIor;
const errno_invalid = memory_map.errno_invalid;
const errno_no_memory = memory_map.errno_no_memory;
const pad_address = memory_map.pad_address;
const true_flag = memory_map.true_flag;

/// The built-in words this file executes; executeBuiltin dispatches by this list.
pub const words = [_]Builtin{
    .blank, .cell, .cells, .cell_plus, .aligned, .fetch, .store, .cfetch, .cstore, .add_store,
    .inc_store, .dec_store, .zero_store, .off, .on, .question, .array_fetch, .array_store, .erase,
    .fill, .move, .cmove, .here, .allot, .comma, .c_comma, .two_fetch, .two_store, .count, .pad,
    .place, .allocate, .free, .resize,
};

pub fn execute(self: *State, comptime builtin: Builtin) RuntimeError!void {
    switch (builtin) {
        .blank => try self.push(' '),
        .cell => try self.push(cell_size),
        .cells => try self.push((try self.pop()) *% cell_size),
        .cell_plus => try self.push((try self.pop()) +% cell_size),
        .aligned => {
            const address = try self.pop();
            try self.push((address +% (cell_size - 1)) & ~@as(Cell, cell_size - 1));
        },
        .fetch => {
            const address = try self.pop();
            try self.push(try self.readCell(address));
        },
        .store => {
            const address = try self.pop();
            const value = try self.pop();
            try self.writeCell(address, value);
        },
        .cfetch => {
            const address = try self.memoryAddress(try self.pop(), 1);
            try self.push(self.memory[address]);
        },
        .cstore => {
            const address = try self.memoryAddress(try self.pop(), 1);
            const value = try self.pop();
            self.memory[address] = @truncate(@as(UCell, @bitCast(value)));
        },
        .add_store => {
            const address = try self.pop();
            const value = try self.pop();
            try self.writeCell(address, (try self.readCell(address)) +% value);
        },
        .inc_store, .dec_store => {
            const address = try self.pop();
            const old = try self.readCell(address);
            try self.writeCell(address, if (builtin == .inc_store) old +% 1 else old -% 1);
        },
        .zero_store, .off => try self.writeCell(try self.pop(), 0),
        .on => try self.writeCell(try self.pop(), true_flag),
        .question => {
            const address = try self.pop();
            self.writeNumber(try self.readCell(address));
            self.write(" ");
        },
        .array_fetch => {
            const address = try self.arrayAddress();
            try self.push(try self.readCell(address));
        },
        .array_store => {
            const address = try self.arrayAddress();
            const value = try self.pop();
            try self.writeCell(address, value);
        },
        .erase, .fill => {
            const byte: u8 = if (builtin == .fill) @truncate(@as(UCell, @bitCast(try self.pop()))) else 0;
            const bytes = try self.memoryRange();
            @memset(bytes, byte);
        },
        .move, .cmove => {
            const count = try self.pop();
            const destination = try self.pop();
            const source = try self.pop();
            if (count <= 0) return;
            const length: usize = @intCast(count);
            const to = try self.memoryAddress(destination, length);
            const from = try self.memoryAddress(source, length);
            if (builtin == .cmove or to <= from) {
                for (0..length) |offset| self.memory[to + offset] = self.memory[from + offset];
            } else {
                std.mem.copyBackwards(u8, self.memory[to .. to + length], self.memory[from .. from + length]);
            }
        },
        .here => try self.push(self.data_here),
        .allot => try self.reserveData(try self.pop()),
        .comma => {
            const value = try self.pop();
            const address = self.data_here;
            try self.reserveData(cell_size);
            try self.writeCell(address, value);
        },
        .c_comma => {
            const value = try self.pop();
            const address = self.data_here;
            try self.reserveData(1);
            self.memory[@intCast(address)] = @truncate(@as(UCell, @bitCast(value)));
        },
        .two_fetch => try self.pushDouble(try self.readDouble(try self.pop())),
        .two_store => {
            const address = try self.pop();
            try self.writeDouble(address, try self.popDouble());
        },
        .count => {
            const address = try self.pop();
            const at = try self.memoryAddress(address, 1);
            try self.push(address + 1);
            try self.push(self.memory[at]);
        },
        .pad => try self.push(pad_address),
        .place => {
            const destination = try self.pop();
            const count = try self.pop();
            const source = try self.pop();
            // Like gforth, at most 255 bytes are stored; the length byte is written
            // after the copy so an overlapping source is read intact.
            const length: usize = @intCast(std.math.clamp(count, 0, 255));
            const to = try self.memoryAddress(destination, length + 1);
            const from = try self.memoryAddress(source, length);
            const target = self.memory[to + 1 .. to + 1 + length];
            const bytes = self.memory[from .. from + length];
            if (to + 1 <= from) std.mem.copyForwards(u8, target, bytes) else std.mem.copyBackwards(u8, target, bytes);
            self.memory[to] = @intCast(length);
        },
        .allocate => {
            const size: UCell = @bitCast(try self.pop());
            const address = try self.heapAllocate(size);
            try self.push(address orelse 0);
            try self.push(if (address == null) errnoIor(errno_no_memory) else 0);
        },
        .free => {
            const freed = try self.heapFree(try self.pop());
            try self.push(if (freed) 0 else errnoIor(errno_invalid));
        },
        .resize => {
            const size: UCell = @bitCast(try self.pop());
            const address = try self.pop();
            switch (try self.heapResize(address, size)) {
                .address => |moved| {
                    try self.push(moved);
                    try self.push(0);
                },
                .no_memory, .bad_pointer => |_, tag| {
                    try self.push(address);
                    try self.push(errnoIor(if (tag == .no_memory) errno_no_memory else errno_invalid));
                },
            }
        },
        else => @compileError(@tagName(builtin) ++ " is not in the words of this file"),
    }
}
