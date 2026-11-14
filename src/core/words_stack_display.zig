//! Stack-wide clearing and non-destructive display settings.
const defs = @import("defs.zig");
const forth = @import("../forth.zig");
const map = @import("memory_map.zig");
pub const words = [_]defs.Builtin{ .clear_stack, .clear_stacks, .f_clear_stack, .maxdepth_dot_s, .f_s_precision };
pub const float_words = [_]defs.Builtin{ .f_clear_stack, .f_s_precision };
pub fn execute(self: *forth.State, comptime word: defs.Builtin) forth.RuntimeError!void {
    switch (word) {
        .clear_stack => self.data_depth = 0,
        .clear_stacks => {
            self.data_depth = 0;
            self.float_depth = 0;
        },
        .f_clear_stack => self.float_depth = 0,
        .maxdepth_dot_s => try self.push(map.maxdepth_dot_s_address),
        .f_s_precision => try self.push(self.readCellConst(map.f_s_precision_address)),
        else => unreachable,
    }
}
pub fn visibleItems(self: *const forth.State, depth: usize) forth.RuntimeError!usize {
    const maximum = self.readCellConst(map.maxdepth_dot_s_address);
    // Negative limits caused an out-of-bounds read in the measured reference.
    if (maximum < 0) return error.InvalidNumber;
    return @min(depth, @as(usize, @intCast(maximum)));
}
