//! Filesystem extension: validate all arguments before host effects or mutation.
const std = @import("std");
const forth = @import("../forth.zig");
const defs = @import("defs.zig");
const map = @import("memory_map.zig");
const registry = @import("address_registry.zig");

pub fn execute(self: *forth.State, comptime word: defs.Builtin) defs.RuntimeError!void {
    const inputs = if (word == .file_realpath) 4 else if (word == .sync_file) 1 else 2;
    const outputs = if (word == .file_metadata) 5 else if (word == .sync_file) 1 else 2;
    try self.requireDepth(inputs);
    if (self.data_depth - inputs + outputs > self.data_stack.len) return error.StackOverflow;
    if (word == .sync_file) {
        if (!defs.files_enabled) return error.HostUnavailable;
        const callback = (try self.fileOps()).sync orelse return error.HostUnavailable;
        const result = callback(self.writer.context, try self.peek(0));
        self.data_stack[self.data_depth - 1] = result;
        return;
    }
    const source_address = try self.peek(inputs - 1);
    const length = std.math.cast(usize, try self.peek(inputs - 2)) orelse return error.InvalidAddress;
    const start = try self.memoryAddress(source_address, length);
    const name = self.memory[start..][0..length];
    if (word == .compact_filename) {
        if (length == 0) return;
        const temporary = try self.heapAllocate(length) orelse return error.MemoryExhausted;
        defer _ = self.heapFree(temporary) catch {};
        const scratch = self.memory[@intCast(temporary)..][0..length];
        const count = try @import("paths.zig").compactInto(name, scratch);
        @memcpy(self.memory[start..][0..count], scratch[0..count]);
        registry.written(self, source_address, count, false);
        self.data_stack[self.data_depth - 1] = @intCast(count);
        return;
    }
    if (!defs.files_enabled) return error.HostUnavailable;
    const files = try self.fileOps();
    switch (word) {
        .file_realpath => {
            const capacity = std.math.cast(usize, try self.peek(0)) orelse return error.InvalidAddress;
            const destination = try self.peek(1);
            const at = try self.memoryAddress(destination, capacity);
            const callback = files.realpath orelse return error.HostUnavailable;
            const release = files.release_realpath orelse return error.HostUnavailable;
            const result = callback(self.writer.context, name);
            defer release(self.writer.context, result.bytes);
            if (result.bytes.len > std.math.maxInt(map.Cell)) return error.HostFailed;
            var ior = result.ior;
            const needed = if (ior == 0) result.bytes.len else 0;
            if (ior == 0) {
                if (needed > capacity) ior = map.errnoIor(34) else {
                    @memcpy(self.memory[at..][0..needed], result.bytes);
                    registry.written(self, destination, needed, false);
                }
            }
            self.data_depth -= 4;
            try self.push(@intCast(needed));
            try self.push(ior);
        },
        .file_metadata => {
            const callback = files.metadata orelse return error.HostUnavailable;
            const result = callback(self.writer.context, name);
            if (result.ior == 0 and result.nanoseconds >= 1000000000) return error.HostFailed;
            self.data_depth -= 2;
            try self.pushDouble(if (result.ior == 0) result.size else 0);
            try self.push(if (result.ior == 0) result.seconds else 0);
            try self.push(if (result.ior == 0) result.nanoseconds else 0);
            try self.push(result.ior);
        },
        else => unreachable,
    }
}
