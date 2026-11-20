//! Synchronous borrowed-buffer S-DSP entry. No host audio capability required.
const std = @import("std");
const forth = @import("../forth.zig");
const dsp = @import("sound_snes_dsp.zig");
const Cell = forth.Cell;
const Error = forth.RuntimeError;
const sizes = [_]usize{ 128, 65536, 112 * 8, 10 * 8, 16 * 8 };
fn between(n: i64, low: i64, high: i64) bool {
    return n >= low and n <= high;
}
fn readCells(comptime n: usize, memory: []const u8) [n]i64 {
    var result: [n]i64 = undefined;
    for (&result, 0..) |*value, i| value.* = std.mem.readInt(i64, memory[i * 8 ..][0..8], .little);
    return result;
}
fn valid(model: *const dsp.Model, count: Cell) bool {
    for (0..8) |i| {
        const v = model.voices[i * 14 ..][0..14];
        if (!between(v[1], 0, 65535) or !between(v[2], 0, 15) or !between(v[3], 0, 255) or
            !between(v[4], -16384, 16383) or !between(v[5], -16384, 16383) or
            !between(v[6], 0, 4095) or !between(v[7], 0, 2047) or !between(v[8], 0, 3) or !between(v[9], 0, 5)) return false;
        for (v[10..14]) |h| if (!between(h, -16384, 16383)) return false;
    }
    const g = model.globals;
    if (g[0] < 0 or !between(g[1], 0, 31) or g[2] < 0 or !between(g[3], 0, 255) or !between(g[4], 0, 32767) or
        !between(g[6], 4, 30720) or (g[6] != 4 and @mod(g[6], 2048) != 0) or
        !between(g[5], 0, g[6] - 1) or @mod(g[5], 4) != 0 or !between(g[7], 0, 7) or
        !between(g[8], -32768, 32767) or !between(g[9], -32768, 32767)) return false;
    for (model.history) |h| if (!between(h, -16384, 16383)) return false;
    const maximum = std.math.maxInt(i64);
    if (@as(i128, g[2]) + count > maximum) return false;
    const ticks = if (count == 0) @as(i128, 0) else @as(i128, count) * 32 - g[1];
    return @as(i128, g[0]) + ticks <= maximum;
}
fn commit(self: *forth.State, addresses: [5]usize, model: *const dsp.Model) Error!void {
    for (model.voices, 0..) |value, i| try self.writeCell(@intCast(addresses[2] + i * 8), value);
    for (model.globals, 0..) |value, i| try self.writeCell(@intCast(addresses[3] + i * 8), value);
    for (model.history, 0..) |value, i| try self.writeCell(@intCast(addresses[4] + i * 8), value);
    const registry = @import("address_registry.zig");
    for (model.reg_writes, 0..) |written, i| if (written) registry.written(self, @intCast(addresses[0] + i), 1, false);
    for (model.ram_writes[0..model.ram_write_count]) |address| registry.written(self, @intCast(addresses[1] + address), 1, false);
}
pub fn execute(self: *forth.State) Error!void {
    try self.requireDepth(7);
    const layout = try self.peek(0);
    const count = try self.peek(1);
    if (layout != 1 or count < 0) return error.InvalidNumber;
    var addresses: [5]usize = undefined;
    for (&addresses, 0..) |*address, i| address.* = try self.memoryAddress(try self.peek(6 - i), sizes[i]);
    for (addresses, 0..) |a, i| for (addresses[0..i], 0..) |b, j| {
        if (a < b + sizes[j] and b < a + sizes[i]) return error.InvalidNumber;
    };
    var model = dsp.Model{
        .regs = self.memory[addresses[0]..][0..sizes[0]],
        .ram = self.memory[addresses[1]..][0..sizes[1]],
        .voices = readCells(112, self.memory[addresses[2]..]),
        .globals = readCells(10, self.memory[addresses[3]..]),
        .history = readCells(16, self.memory[addresses[4]..]),
    };
    if (!valid(&model, count)) return error.InvalidNumber;
    self.data_depth -= 7;
    var done: Cell = 0;
    while (done < count) : (done += 1) {
        // A native checkpoint precedes every complete frame. No partial frame escapes.
        try @import("words_numeric.zig").checkWorkBlock(self);
        model.step();
        try commit(self, addresses, &model);
    }
}
