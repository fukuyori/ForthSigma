//! SH's parsing front end to the existing host SYSTEM service.
const std = @import("std");
const forth = @import("../forth.zig");
const map = @import("memory_map.zig");

pub fn run(self: *forth.State) forth.RuntimeError!void {
    const callback = self.writer.system_fn orelse return error.HostUnavailable;
    const rest = self.remainingSource();
    const length = std.mem.indexOfScalar(u8, rest, 0) orelse rest.len;
    var command = rest[0..length];
    var snapshot: ?map.Cell = null;
    defer if (snapshot) |copy| {
        _ = self.heapFree(copy) catch {};
    };
    // The newline may resize an output owner that also contains an EVALUATE source.
    if (length != 0 and (self.capture_sink != null or self.capture_target != null)) {
        const copy = try self.heapAllocate(length) orelse return self.throwIor(map.errno_no_memory);
        snapshot = copy;
        @memcpy(self.memory[@intCast(copy)..][0..length], command);
        command = self.memory[@intCast(copy)..][0..length];
    }
    self.setSourceCursor(self.sourceCursor() + length + @intFromBool(length < rest.len));
    self.write("\n");
    try self.checkOutputError();
    self.system_status = try callback(self.writer.context, command);
}
