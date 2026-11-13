//! Owned concatenation and bounded in-place editing.
const std = @import("std");
const defs = @import("defs.zig");
const forth = @import("../forth.zig");
const map = @import("memory_map.zig");
const registry = @import("address_registry.zig");
const checkWork = @import("words_numeric.zig").checkWorkBlock;
const RuntimeError = defs.RuntimeError;
const State = forth.State;
const Cell = map.Cell;
pub const words = [_]defs.Builtin{ .string_concat, .string_append_owned, .cstring_to_sstring, .delete_bytes, .insert_bytes, .string_comma };
pub fn execute(self: *State, comptime builtin: defs.Builtin) RuntimeError!void {
    switch (builtin) {
        .cstring_to_sstring => {
            const address = try self.peek(0);
            if (self.data_depth == self.data_stack.len) return error.StackOverflow;
            const at = try self.memoryAddress(address, 1);
            var length: usize = 0;
            while (at + length < self.memory.len and self.memory[at + length] != 0) : (length += 1) {
                if (length % 256 == 0) try checkWork(self);
            }
            if (at + length == self.memory.len) return error.InvalidAddress;
            try self.push(@intCast(length));
        },
        .delete_bytes => {
            try self.requireDepth(3);
            const address = try self.peek(2);
            const length = try size(try self.peek(1));
            const deleted: usize = @intCast(@min(@as(map.UCell, @bitCast(try self.peek(0))), length));
            const at = try self.memoryAddress(address, length);
            const remaining = length - deleted;
            try self.copyMemory(address, address + @as(Cell, @intCast(deleted)), remaining);
            @memset(self.memory[at + remaining ..][0..deleted], ' ');
            registry.written(self, address + @as(Cell, @intCast(remaining)), deleted, false);
            self.data_depth -= 3;
        },
        .insert_bytes => {
            try self.requireDepth(4);
            const source = try self.peek(3);
            const destination = try self.peek(1);
            const length = try size(try self.peek(0));
            const inserted: usize = @intCast(@min(@as(map.UCell, @bitCast(try self.peek(2))), length));
            _ = try self.memoryAddress(source, inserted);
            _ = try self.memoryAddress(destination, length);
            try registry.preflightCopies(self, &.{
                .{ .destination = destination + @as(Cell, @intCast(inserted)), .source = destination, .length = length - inserted },
                .{ .destination = destination, .source = source, .length = inserted },
            });
            // Preserve the reference's ordering: source bytes inside the destination
            // observe the preceding right shift, rather than an invented snapshot.
            try self.copyMemory(destination + @as(Cell, @intCast(inserted)), destination, length - inserted);
            try self.copyMemory(destination, source, inserted);
            self.data_depth -= 4;
        },
        .string_comma => {
            try self.requireDepth(2);
            const source = try self.peek(1);
            const length = try size(try self.peek(0));
            const needed = std.math.add(usize, length, 1) catch return error.MemoryExhausted;
            if (needed > @as(usize, @intCast(self.sizes.dataLimit() - self.data_here))) return error.MemoryExhausted;
            _ = try self.memoryAddress(source, length);
            const destination = self.data_here;
            try registry.preflightCopies(self, &.{.{ .destination = destination + 1, .source = source, .length = length }});
            try self.reserveData(@intCast(needed));
            self.memory[@intCast(destination)] = @truncate(length);
            registry.written(self, destination, 1, false);
            try self.copyMemory(destination + 1, source, length);
            self.data_depth -= 2;
        },
        .string_concat, .string_append_owned => {
            try self.requireDepth(4);
            const first = try self.peek(3);
            const n1 = try size(try self.peek(2));
            const second = try self.peek(1);
            const n2 = try size(try self.peek(0));
            const total = std.math.add(usize, n1, n2) catch return self.throwIor(map.errno_no_memory);
            if (self.heapNeed(total) == null) return self.throwIor(map.errno_no_memory);
            _ = try self.memoryAddress(first, n1);
            _ = try self.memoryAddress(second, n2);
            const destination = if (builtin == .string_concat or (first == 0 and n1 == 0)) blk: {
                const allocated = try self.heapAllocate(total) orelse return self.throwIor(map.errno_no_memory);
                errdefer _ = self.heapFree(allocated) catch false;
                try registry.preflightCopies(self, &.{
                    .{ .destination = allocated, .source = first, .length = n1 },
                    .{ .destination = allocated + @as(Cell, @intCast(n1)), .source = second, .length = n2 },
                });
                try self.copyMemory(allocated, first, n1);
                try self.copyMemory(allocated + @as(Cell, @intCast(n1)), second, n2);
                break :blk allocated;
            } else try append(self, first, n1, second, n2, total);
            self.data_depth -= 4;
            try self.push(destination);
            try self.push(@intCast(total));
        },
        else => @compileError("unexpected string edit word"),
    }
}
fn append(self: *State, first: Cell, n1: usize, second: Cell, n2: usize, total: usize) RuntimeError!Cell {
    const block = try self.findBlock(first) orelse return self.throwIor(map.errno_invalid);
    const old_size: usize = @intCast(try self.blockSize(block));
    if (n1 > old_size) return error.InvalidAddress;
    var source = second;
    var temporary: ?Cell = null;
    defer if (temporary) |at| {
        _ = self.heapFree(at) catch false;
    };
    const overlaps = @as(i128, second) < @as(i128, first) + old_size and @as(i128, second) + n2 > first;
    const preserved = second >= first and @as(i128, second) + n2 <= @as(i128, first) + @min(old_size, @as(usize, @intCast(self.heapNeed(total).?)));
    if (overlaps and !preserved) {
        const copy = try self.heapAllocate(n2) orelse return self.throwIor(map.errno_no_memory);
        temporary = copy;
        try self.copyMemory(copy, second, n2);
        source = copy;
    }
    try registry.preflightCopies(self, &.{.{ .destination = first + @as(Cell, @intCast(n1)), .source = source, .length = n2 }});
    const moved = switch (try self.heapResize(first, total)) {
        .address => |address| address,
        .no_memory => return self.throwIor(map.errno_no_memory),
        .bad_pointer => return self.throwIor(map.errno_invalid),
    };
    if (overlaps and preserved) source = moved + (second - first);
    try self.copyMemory(moved + @as(Cell, @intCast(n1)), source, n2);
    return moved;
}
fn size(value: Cell) RuntimeError!usize {
    return std.math.cast(usize, @as(map.UCell, @bitCast(value))) orelse error.InvalidAddress;
}
