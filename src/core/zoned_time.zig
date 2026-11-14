const forth = @import("../forth.zig");
const defs = @import("defs.zig");
const map = @import("memory_map.zig");
const registry = @import("address_registry.zig");
pub fn execute(self: *forth.State) defs.RuntimeError!void {
    try self.requireDepth(2);
    if (self.data_stack.len - self.data_depth < 8) return error.StackOverflow;
    const seconds = defs.cellsDouble(try self.peek(1), try self.peek(0));
    const convert = self.writer.zoned_time_fn orelse return error.HostUnavailable;
    // Host errors and malformed results must not alter the previous borrowed name.
    var name: [map.timezone_buffer_size]u8 = undefined;
    const value = try convert(self.writer.context, seconds, &name);
    const date = value.local;
    if (value.zone_length > name.len or date.second < 0 or date.second > 60 or date.minute < 0 or date.minute > 59 or date.hour < 0 or date.hour > 23 or date.day < 1 or date.day > 31 or date.month < 1 or date.month > 12) return error.InvalidAddress;
    const at: usize = @intCast(map.timezone_buffer_address);
    @memcpy(self.memory[at..][0..value.zone_length], name[0..value.zone_length]);
    registry.written(self, map.timezone_buffer_address, value.zone_length, false);
    const base = self.data_depth - 2;
    const cells = [_]map.Cell{ date.second, date.minute, date.hour, date.day, date.month, date.year, if (value.dst) -1 else 0, value.offset, map.timezone_buffer_address, @intCast(value.zone_length) };
    @memcpy(self.data_stack[base..][0..cells.len], &cells);
    self.data_depth = base + cells.len;
}
