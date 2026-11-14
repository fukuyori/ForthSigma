//! Borrowed command output with scoped pipe ownership.
const std = @import("std");
const forth = @import("../forth.zig");
const map = @import("memory_map.zig");

pub fn run(self: *forth.State) forth.RuntimeError!void {
    try self.requireDepth(2);
    const length = std.math.cast(usize, @max(try self.peek(0), 0)) orelse return error.InvalidAddress;
    const at = try self.memoryAddress(try self.peek(1), length);
    const files = try self.fileOps();
    const open = files.open_pipe orelse return error.FileUnavailable;
    const close = files.close_pipe orelse return error.FileUnavailable;
    // The command may itself be the previous borrowed result. The host consumes
    // this span during open, before that result is released for the new read.
    const opened = open(self.writer.context, self.memory[at..][0..length], .read_only);
    const id: map.Cell = @bitCast(opened.value);
    var owned = opened.ior == 0;
    defer if (owned) {
        _ = close(self.writer.context, id);
    };
    if (self.sh_get_result) |previous| {
        self.sh_get_result = null;
        if (!try self.heapFree(previous.address)) return error.InvalidAddress;
    }
    if (opened.ior != 0) return self.throwCode(opened.ior);
    const text = try @import("file_streams.zig").slurp(self, id);
    errdefer _ = self.heapFree(text.address) catch {};
    const closed = close(self.writer.context, id);
    owned = false;
    if (closed.ior != 0) return self.throwCode(closed.ior);
    self.system_status = @bitCast(closed.value);
    self.sh_get_result = text;
    // Input and result both occupy two cells; no fallible operation after commit.
    self.data_stack[self.data_depth - 2] = text.address;
    self.data_stack[self.data_depth - 1] = @intCast(text.length);
}
