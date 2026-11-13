//! Owned heap copies and growing buffers; numeric cells never imply pointer types.
const std = @import("std");
const defs = @import("defs.zig");
const forth = @import("../forth.zig");
const map = @import("memory_map.zig");
const pointers = @import("dynamic_strings.zig");
const RuntimeError = defs.RuntimeError;
pub const words = [_]defs.Builtin{ .save_mem, .extend_mem, .free_mem_var, .buffer_percent, .init_buffer, .adjust_buffer };

pub fn execute(self: *forth.State, comptime builtin: defs.Builtin) RuntimeError!void {
    switch (builtin) {
        .buffer_percent => {
            if (self.data_depth > self.data_stack.len - 2) return error.StackOverflow;
            try self.push(8);
            try self.push(24);
        },
        .save_mem => {
            try self.requireDepth(2);
            const length: map.UCell = @bitCast(try self.peek(0));
            const source = try self.peek(1);
            if (self.heapNeed(length) == null) return self.throwIor(map.errno_no_memory);
            _ = try self.memoryAddress(source, @intCast(length));
            const destination = try self.heapAllocate(length) orelse return self.throwIor(map.errno_no_memory);
            errdefer _ = self.heapFree(destination) catch false;
            try self.copyMemory(destination, source, @intCast(length));
            self.data_stack[self.data_depth - 2] = destination;
        },
        .extend_mem => {
            try self.requireDepth(3);
            const address = try self.peek(2);
            const old: map.UCell = @bitCast(try self.peek(1));
            const extra: map.UCell = @bitCast(try self.peek(0));
            const length = std.math.add(map.UCell, old, extra) catch return self.throwIor(map.errno_no_memory);
            if (self.heapNeed(length) == null) return self.throwIor(map.errno_no_memory);
            const moved = try resize(self, address, length);
            self.data_stack[self.data_depth - 3] = moved + @as(map.Cell, @intCast(old));
            self.data_stack[self.data_depth - 2] = moved;
            self.data_stack[self.data_depth - 1] = @intCast(length);
        },
        .free_mem_var => {
            const descriptor = try self.peek(0);
            _ = try self.memoryAddress(descriptor, 16);
            const address = try self.readCell(descriptor + 8);
            if (address != 0) {
                if (!try self.heapFree(address)) return self.throwIor(map.errno_invalid);
                try self.writeCell(descriptor, 0);
                try self.writeCell(descriptor + 8, 0);
            }
            _ = try self.pop();
        },
        .init_buffer => {
            const descriptor = try self.peek(0);
            _ = try self.memoryAddress(descriptor, 24);
            try pointers.preparePointer(self, descriptor + 8);
            try self.writeCell(descriptor, 0);
            try self.writeCell(descriptor + 8, 0);
            try self.writeCell(descriptor + 16, 0);
            try pointers.registerPointer(self, descriptor + 8);
            _ = try self.pop();
        },
        .adjust_buffer => {
            try self.requireDepth(2);
            const descriptor = try self.peek(0);
            const length: map.UCell = @bitCast(try self.peek(1));
            _ = try self.memoryAddress(descriptor, 24);
            if (self.heapNeed(length) == null) return self.throwIor(map.errno_no_memory);
            const reserved = try pointers.reservePointer(self, descriptor + 8);
            errdefer pointers.cancelPointer(self, descriptor + 8, reserved);
            const capacity = try self.readCell(descriptor + 16);
            if (capacity < 0) return error.InvalidAddress;
            if (length > @as(map.UCell, @intCast(capacity))) {
                const moved = try resize(self, try self.readCell(descriptor + 8), length);
                try self.writeCell(descriptor + 8, moved);
                try self.writeCell(descriptor + 16, @intCast(length));
            }
            try pointers.registerPointer(self, descriptor + 8);
            try self.writeCell(descriptor, @intCast(length));
            self.data_depth -= 2;
        },
        else => @compileError("unexpected buffer word"),
    }
}
fn resize(self: *forth.State, address: map.Cell, length: map.UCell) RuntimeError!map.Cell {
    return switch (try self.heapResize(address, length)) {
        .address => |moved| moved,
        .no_memory => self.throwIor(map.errno_no_memory),
        .bad_pointer => self.throwIor(map.errno_invalid),
    };
}
