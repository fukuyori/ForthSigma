//! Optional host I/O: snapshot IDs and validate memory before host side effects.
const defs = @import("defs.zig");
const forth = @import("../forth.zig");
const map = @import("memory_map.zig");

pub fn execute(self: *forth.State, comptime word: defs.Builtin) forth.RuntimeError!void {
    try self.requireDepth(3);
    if (!defs.files_enabled) return error.HostUnavailable;
    const files = try self.fileOps();
    const check = files.io_check orelse return error.HostUnavailable;
    switch (word) {
        .wait_files, .wait_writable => {
            const callback = files.wait_files orelse return error.HostUnavailable;
            const address = try self.peek(2);
            const count = try self.peek(1);
            const timeout = try self.peek(0);
            if (count < 1 or count > 64) return self.throwCode(-24);
            const length: usize = @intCast(count);
            _ = try self.memoryAddress(address, length * map.cell_size);
            var ids: [64]forth.Cell = undefined;
            for (ids[0..length], 0..) |*id, index| id.* = try self.readCell(address + @as(forth.Cell, @intCast(index * map.cell_size)));
            const writing = word == .wait_writable;
            // Check every entry before preparing stdin or starting any worker.
            for (ids[0..length], 0..) |id, index| {
                const ior = check(self.writer.context, id, writing);
                if (ior != 0) {
                    self.data_depth -= 3;
                    try self.push(@intCast(index));
                    try self.push(ior);
                    return;
                }
            }
            if (!writing) for (ids[0..length]) |id| {
                if (id == map.stdin_fileid) try @import("event_input.zig").beforeFileRead(self, id);
            };
            const result = try callback(self.writer.context, ids[0..length], timeout, writing);
            if (result.index < -1 or result.index >= count) return error.HostFailed;
            self.data_depth -= 3;
            try self.push(result.index);
            try self.push(result.ior);
        },
        .read_available, .write_available => {
            const address = try self.peek(2);
            const count = try self.peek(1);
            const id = try self.peek(0);
            if (count < 0) return self.throwCode(-24);
            const length: usize = @intCast(count);
            const start = try self.memoryAddress(address, length);
            const buffer = self.memory[start..][0..length];
            if (word == .read_available) {
                const callback = files.read_available orelse return error.HostUnavailable;
                const ior = check(self.writer.context, id, false);
                if (ior != 0) {
                    self.data_depth -= 3;
                    try self.push(0);
                    try self.push(0);
                    try self.push(ior);
                    return;
                }
                if (length != 0) try @import("event_input.zig").beforeFileRead(self, id);
                const result = try callback(self.writer.context, id, buffer);
                if (result.count > length) return error.HostFailed;
                @import("address_registry.zig").written(self, address, result.count, false);
                self.data_depth -= 3;
                try self.push(@intCast(result.count));
                try self.push(if (result.eof) -1 else 0);
                try self.push(result.ior);
            } else {
                const callback = files.write_available orelse return error.HostUnavailable;
                const ior = check(self.writer.context, id, true);
                if (ior != 0) {
                    self.data_depth -= 3;
                    try self.push(0);
                    try self.push(ior);
                    return;
                }
                const result = try callback(self.writer.context, id, buffer);
                if (result.value > length) return error.HostFailed;
                self.data_depth -= 3;
                try self.push(@intCast(result.value));
                try self.push(result.ior);
            }
        },
        else => unreachable,
    }
}
