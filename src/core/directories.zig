//! Working-directory words. Native resources stay behind optional host callbacks.
const std = @import("std");
const forth = @import("../forth.zig");
const defs = @import("defs.zig");
const map = @import("memory_map.zig");
const registry = @import("address_registry.zig");

pub fn execute(self: *forth.State, comptime builtin: defs.Builtin) defs.RuntimeError!void {
    if (builtin == .open_dir or builtin == .read_dir or builtin == .close_dir) return iterate(self, builtin);
    if (builtin == .equals_mkdir or builtin == .mkdir_parents) return create(self, builtin == .mkdir_parents);
    try self.requireDepth(2);
    const length = std.math.cast(usize, try self.peek(0)) orelse return error.InvalidAddress;
    const address = try self.peek(1);
    const at = try self.memoryAddress(address, length);
    const buffer = self.memory[at..][0..length];
    const files = try self.fileOps();
    switch (builtin) {
        .get_dir => {
            const get = files.get_dir orelse return error.FileUnavailable;
            const result = get(self.writer.context, buffer);
            // Even an error callback may have touched output; invalidate conservatively.
            const valid = result.ior == 0 and result.value < buffer.len and buffer[@intCast(result.value)] == 0;
            registry.written(self, address, if (valid) @as(usize, @intCast(result.value)) + 1 else buffer.len, false);
            if (result.ior == 0 and !valid) return error.InvalidAddress;
            self.data_stack[self.data_depth - 2] = if (valid) address else 0;
            self.data_stack[self.data_depth - 1] = if (valid) @intCast(result.value) else 0;
        },
        .set_dir => {
            const set = files.set_dir orelse return error.FileUnavailable;
            const ior = if (std.mem.indexOfScalar(u8, buffer, 0) != null) forth.errnoIor(map.errno_invalid) else changed: {
                const name = try @import("paths.zig").openedName(self, buffer);
                // A home provider can return NUL too; do not truncate at the host boundary.
                if (std.mem.indexOfScalar(u8, name.bytes[0..name.len], 0) != null) break :changed forth.errnoIor(map.errno_invalid);
                break :changed set(self.writer.context, name.bytes[0..name.len]);
            };
            self.data_depth -= 2;
            try self.push(ior);
        },
        else => unreachable,
    }
}

fn create(self: *forth.State, parents: bool) defs.RuntimeError!void {
    try self.requireDepth(3);
    const length = std.math.cast(usize, try self.peek(1)) orelse return error.InvalidAddress;
    const at = try self.memoryAddress(try self.peek(2), length);
    const name = self.memory[at..][0..length];
    const mode = try self.peek(0);
    const mkdir = (try self.fileOps()).mkdir orelse return error.FileUnavailable;
    const result = if (std.mem.indexOfScalar(u8, name, 0) != null) forth.errnoIor(map.errno_invalid) else created: {
        // Preflight the final expansion before any parent can be created.
        const final = try @import("paths.zig").openedName(self, name);
        if (std.mem.indexOfScalar(u8, final.bytes[0..final.len], 0) != null) break :created forth.errnoIor(map.errno_invalid);
        if (parents) {
            var start: usize = 1;
            while (start < name.len) {
                const end = std.mem.indexOfScalarPos(u8, name, start, '/') orelse break;
                const prefix = try @import("paths.zig").openedName(self, name[0..end]);
                if (std.mem.indexOfScalar(u8, prefix.bytes[0..prefix.len], 0) != null) break :created forth.errnoIor(map.errno_invalid);
                try @import("words_numeric.zig").checkWorkBlock(self);
                const ior = mkdir(self.writer.context, prefix.bytes[0..prefix.len], mode);
                if (ior != 0 and ior != forth.errnoIor(17)) break :created ior;
                start = end + 1;
            }
        }
        try @import("words_numeric.zig").checkWorkBlock(self);
        break :created mkdir(self.writer.context, final.bytes[0..final.len], mode);
    };
    self.data_depth -= 3;
    try self.push(result);
}

fn iterate(self: *forth.State, comptime builtin: defs.Builtin) defs.RuntimeError!void {
    try self.requireDepth(if (builtin == .read_dir) 3 else if (builtin == .open_dir) 2 else 1);
    switch (builtin) {
        .close_dir => {
            const close = (try self.fileOps()).close_dir orelse return error.FileUnavailable;
            const ior = close(self.writer.context, try self.peek(0));
            self.data_stack[self.data_depth - 1] = ior;
        },
        .open_dir => {
            const length = std.math.cast(usize, try self.peek(0)) orelse return error.InvalidAddress;
            const at = try self.memoryAddress(try self.peek(1), length);
            const text = self.memory[at..][0..length];
            const files = try self.fileOps();
            const open = files.open_dir orelse return error.FileUnavailable;
            _ = files.close_dir orelse return error.FileUnavailable;
            const result = if (std.mem.indexOfScalar(u8, text, 0) != null) forth.FileResult{ .ior = forth.errnoIor(map.errno_invalid) } else opened: {
                const name = try @import("paths.zig").openedName(self, text);
                if (std.mem.indexOfScalar(u8, name.bytes[0..name.len], 0) != null) break :opened forth.FileResult{ .ior = forth.errnoIor(map.errno_invalid) };
                break :opened open(self.writer.context, name.bytes[0..name.len]);
            };
            self.data_stack[self.data_depth - 2] = if (result.ior == 0) @bitCast(result.value) else 0;
            self.data_stack[self.data_depth - 1] = result.ior;
        },
        .read_dir => {
            const length = std.math.cast(usize, try self.peek(1)) orelse return error.InvalidAddress;
            const address = try self.peek(2);
            const at = try self.memoryAddress(address, length);
            const read = (try self.fileOps()).read_dir orelse return error.FileUnavailable;
            const result = read(self.writer.context, try self.peek(0), self.memory[at..][0..length]);
            const valid = result.length <= length and (result.found or result.length == 0);
            registry.written(self, address, if (valid) result.length else length, false);
            if (!valid) return error.InvalidAddress;
            self.data_stack[self.data_depth - 3] = @intCast(result.length);
            self.data_stack[self.data_depth - 2] = if (result.found) -1 else 0;
            self.data_stack[self.data_depth - 1] = result.ior;
        },
        else => unreachable,
    }
}
