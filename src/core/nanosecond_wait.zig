const forth = @import("../forth.zig");
const defs = @import("defs.zig");
// Keep the same public range on every host, including 32-bit time_t targets.
pub const max_duration: forth.Double = @as(forth.Double, 0x7fffffffffffffff) * 1_000_000_000 + 999_999_999;
pub fn execute(self: *forth.State) defs.RuntimeError!void {
    try self.requireDepth(2);
    const duration = defs.cellsDouble(try self.peek(1), try self.peek(0));
    if (duration > max_duration) return error.ResultOutOfRange;
    if (duration > 0) {
        const sleep = self.writer.sleep_ns_fn orelse return error.HostUnavailable;
        try sleep(self.writer.context, duration);
    }
    self.data_depth -= 2;
}
