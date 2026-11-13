//! Working-directory words. Native resources stay behind optional host callbacks.
const std = @import("std");
const forth = @import("../forth.zig");
const defs = @import("defs.zig");
const map = @import("memory_map.zig");
const registry = @import("address_registry.zig");

pub fn execute(self: *forth.State, comptime builtin: defs.Builtin) defs.RuntimeError!void {
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
