//! One-way shell streams, using host-owned file handles.
const std = @import("std");
const forth = @import("../forth.zig");
const defs = @import("defs.zig");
const map = @import("memory_map.zig");

pub fn execute(self: *forth.State, comptime word: defs.Builtin) forth.RuntimeError!void {
    switch (word) {
        .broken_pipe_error => try self.push(map.errnoIor(map.errno_broken_pipe)),
        .open_pipe => {
            try self.requireDepth(3);
            const fam = try self.peek(0);
            const length = std.math.cast(usize, @max(try self.peek(1), 0)) orelse return error.InvalidAddress;
            const at = try self.memoryAddress(try self.peek(2), length);
            const files = try self.fileOps();
            const callback = files.open_pipe orelse return error.FileUnavailable;
            _ = files.close_pipe orelse return error.FileUnavailable;
            const access: ?forth.FileAccess = switch (fam & ~@as(map.Cell, (0o777 << 4) | 1)) {
                map.fam_read_only => .read_only,
                map.fam_write_only => .write_only,
                else => null,
            };
            const result = if (access) |mode| callback(self.writer.context, self.memory[at..][0..length], mode) else forth.FileResult{ .ior = map.errnoIor(map.errno_invalid) };
            self.data_depth -= 3;
            try self.push(if (result.ior == 0) @bitCast(result.value) else 0);
            try self.push(result.ior);
        },
        .close_pipe => {
            const id = try self.peek(0);
            if (self.data_depth == self.data_stack.len) return error.StackOverflow;
            const callback = (try self.fileOps()).close_pipe orelse return error.FileUnavailable;
            const result = callback(self.writer.context, id);
            self.data_depth -= 1;
            try self.push(@bitCast(result.value));
            try self.push(result.ior);
        },
        else => unreachable,
    }
}
