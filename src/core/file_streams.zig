//! File-handle helpers. These never close a handle owned by the caller.
const std = @import("std");
const forth = @import("../forth.zig");
const defs = @import("defs.zig");
const map = @import("memory_map.zig");
const registry = @import("address_registry.zig");
const checkWork = @import("words_numeric.zig").checkWorkBlock;

/// Read from the current position until a zero-byte read, without requiring size
/// or seek support. A short read alone does not mean EOF in the host interface.
pub fn slurp(self: *forth.State, fileid: map.Cell) defs.RuntimeError!@import("dynamic_strings.zig").StringRef {
    const files = try self.fileOps();
    var buffer: map.Cell = 0;
    var length: usize = 0;
    var capacity: usize = 0;
    errdefer _ = self.heapFree(buffer) catch false;
    var chunk: [1024]u8 = undefined;
    while (true) {
        try checkWork(self);
        const result = files.read(self.writer.context, fileid, &chunk);
        if (result.ior != 0) return self.throwCode(result.ior);
        if (result.value > chunk.len) return error.InvalidAddress;
        const count: usize = @intCast(result.value);
        if (count == 0) break;
        const next = std.math.add(usize, length, count) catch return self.throwIor(map.errno_no_memory);
        if (next > capacity) {
            var wanted = @max(next, capacity *| 2);
            var resized = try self.heapResize(buffer, wanted);
            if (resized == .no_memory and wanted != next) {
                wanted = next;
                resized = try self.heapResize(buffer, wanted);
            }
            buffer = switch (resized) {
                .address => |address| address,
                .no_memory => return self.throwIor(map.errno_no_memory),
                .bad_pointer => return error.InvalidAddress,
            };
            capacity = wanted;
        }
        const address = buffer + @as(map.Cell, @intCast(length));
        @memcpy(self.memory[@intCast(address)..][0..count], chunk[0..count]);
        registry.written(self, address, count, false);
        length = next;
    }
    // Includes empty files: return a real, FREE-able allocation.
    buffer = switch (try self.heapResize(buffer, length)) {
        .address => |address| address,
        .no_memory => return self.throwIor(map.errno_no_memory),
        .bad_pointer => return error.InvalidAddress,
    };
    return .{ .address = buffer, .length = length };
}
