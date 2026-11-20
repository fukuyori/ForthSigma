const std = @import("std");
const forth = @import("../forth.zig");
const support = @import("support.zig");
const kernel = @import("../core/words_snes_dsp.zig");
const dsp = @import("../core/sound_snes_dsp.zig");
const sizes = [_]usize{ 128, 65536, 896, 80, 128 };
const Fixture = struct {
    addresses: [5]forth.Cell,
    fn init(m: *forth.State) !Fixture {
        var f: Fixture = undefined;
        for (&f.addresses, sizes) |*a, size| {
            a.* = m.data_here;
            try m.reserveData(@intCast(size));
            @memset(m.memory[@intCast(a.*)..][0..size], 0);
        }
        for (0..8) |i| try m.writeCell(f.addresses[2] + @as(i64, @intCast((i * 14 + 8) * 8)), 3);
        try m.writeCell(f.addresses[3] + 6 * 8, 4);
        m.memory[@intCast(f.addresses[0] + 108)] = 224;
        return f;
    }
    fn arguments(f: Fixture, m: *forth.State, count: i64, layout: i64) !void {
        m.data_depth = 0;
        for (f.addresses) |a| try m.push(a);
        try m.push(count);
        try m.push(layout);
    }
};
fn expectRejected(m: *forth.State, first: forth.Cell, expected: forth.RuntimeError) !void {
    const memory = m.memory[@intCast(first)..@intCast(m.data_here)];
    const before = try std.testing.allocator.dupe(u8, memory);
    defer std.testing.allocator.free(before);
    const stack = try std.testing.allocator.dupe(forth.Cell, m.data_stack[0..m.data_depth]);
    defer std.testing.allocator.free(stack);
    try std.testing.expectError(expected, kernel.execute(m));
    try std.testing.expectEqualSlices(u8, before, memory);
    try support.expectStack(m, stack);
}
test "SNES borrowed kernel validates every scalar before stack or memory effects" {
    try support.skipWithout(&.{.audio});
    var output = support.Output{};
    const m = try support.createMachine(&output);
    defer support.destroyMachine(m);
    const f = try Fixture.init(m);
    // Boundary values for every voice field (ON is unrestricted).
    const lows = [_]i64{ 0, 0, 0, 0, -16384, -16384, 0, 0, 0, 0, -16384, -16384, -16384, -16384 };
    const highs = [_]i64{ 0, 65535, 15, 255, 16383, 16383, 4095, 2047, 3, 5, 16383, 16383, 16383, 16383 };
    for (0..8) |voice| for (1..14) |field| {
        const a = f.addresses[2] + @as(i64, @intCast((voice * 14 + field) * 8));
        const old = try m.readCell(a);
        for ([_]i64{ lows[field], highs[field] }) |value| {
            try m.writeCell(a, value);
            try f.arguments(m, 0, 1);
            try kernel.execute(m);
        }
        for ([_]i64{ lows[field] - 1, highs[field] + 1 }) |value| {
            try m.writeCell(a, value);
            try f.arguments(m, 0, 1);
            const before = try std.testing.allocator.dupe(u8, m.memory[@intCast(f.addresses[0])..@intCast(m.data_here)]);
            defer std.testing.allocator.free(before);
            try expectRejected(m, f.addresses[0], error.InvalidNumber);
            try std.testing.expectEqual(@as(usize, 7), m.data_depth);
            try std.testing.expectEqualSlices(u8, before, m.memory[@intCast(f.addresses[0])..@intCast(m.data_here)]);
        }
        try m.writeCell(a, old);
    };
    const invalid = [_]struct { usize, i64 }{ .{ 0, -1 }, .{ 1, -1 }, .{ 1, 32 }, .{ 2, -1 }, .{ 3, -1 }, .{ 3, 256 }, .{ 4, -1 }, .{ 4, 32768 }, .{ 5, -1 }, .{ 5, 1 }, .{ 5, 4 }, .{ 6, 0 }, .{ 6, 8 }, .{ 6, 32768 }, .{ 7, -1 }, .{ 7, 8 }, .{ 8, -32769 }, .{ 8, 32768 }, .{ 9, -32769 }, .{ 9, 32768 } };
    for (invalid) |v| {
        const a = f.addresses[3] + @as(i64, @intCast(v[0] * 8));
        const old = try m.readCell(a);
        try m.writeCell(a, v[1]);
        try f.arguments(m, 0, 1);
        try expectRejected(m, f.addresses[0], error.InvalidNumber);
        try std.testing.expectEqual(@as(usize, 7), m.data_depth);
        try std.testing.expectEqual(v[1], try m.readCell(a));
        try m.writeCell(a, old);
    }
    for (0..16) |i| {
        const a = f.addresses[4] + @as(i64, @intCast(i * 8));
        for ([_]i64{ -16385, 16384 }) |value| {
            try m.writeCell(a, value);
            try f.arguments(m, 0, 1);
            try expectRejected(m, f.addresses[0], error.InvalidNumber);
        }
        try m.writeCell(a, 0);
    }
    for ([_]i64{ 0, 2 }) |layout| {
        try f.arguments(m, 0, layout);
        try expectRejected(m, f.addresses[0], error.InvalidNumber);
    }
    try f.arguments(m, -1, 1);
    try expectRejected(m, f.addresses[0], error.InvalidNumber);
    for (0..5) |i| for (0..i) |j| {
        var overlapping = f;
        overlapping.addresses[i] = f.addresses[j] + @as(i64, @intCast(sizes[j] - 1));
        try overlapping.arguments(m, 0, 1);
        try expectRejected(m, f.addresses[0], error.InvalidNumber);
    };
    for (0..5) |i| {
        var bad = f;
        bad.addresses[i] = -1;
        try bad.arguments(m, 0, 1);
        try expectRejected(m, f.addresses[0], error.InvalidAddress);
        bad.addresses[i] = @intCast(m.memory.len - sizes[i] + 1);
        try bad.arguments(m, 0, 1);
        try expectRejected(m, f.addresses[0], error.InvalidAddress);
    }
    try f.arguments(m, 0, 1);
    try kernel.execute(m);
    try support.expectStack(m, &.{});
    m.data_depth = 0;
    try std.testing.expectError(error.StackUnderflow, kernel.execute(m));
}
test "SNES clock boundaries and interrupted completed frames need no audio host" {
    try support.skipWithout(&.{.audio});
    var output = support.Output{};
    const m = try support.createMachine(&output);
    defer support.destroyMachine(m);
    const f = try Fixture.init(m);
    m.writer.audio_fn = null;
    const maximum = std.math.maxInt(i64);
    try m.writeCell(f.addresses[3], maximum - 15);
    try m.writeCell(f.addresses[3] + 8, 17);
    try f.arguments(m, 1, 1);
    try kernel.execute(m);
    try std.testing.expectEqual(maximum, try m.readCell(f.addresses[3]));
    try f.arguments(m, 1, 1);
    try expectRejected(m, f.addresses[0], error.InvalidNumber);
    try m.writeCell(f.addresses[3], 0);
    try m.writeCell(f.addresses[3] + 16, maximum);
    try f.arguments(m, 1, 1);
    try expectRejected(m, f.addresses[0], error.InvalidNumber);
    try m.writeCell(f.addresses[3] + 16, 0);
    if (comptime @import("build_options").debug) {
        m.step_limit = 2;
        m.steps_left = 2;
        try f.arguments(m, 4, 1);
        try std.testing.expectError(error.StepLimit, kernel.execute(m));
        try std.testing.expectEqual(@as(i64, 64), try m.readCell(f.addresses[3]));
        try std.testing.expectEqual(@as(i64, 2), try m.readCell(f.addresses[3] + 16));
        try std.testing.expectEqual(@as(i64, 0), try m.readCell(f.addresses[3] + 8));
        try std.testing.expectEqual(@as(usize, 0), m.data_depth);
        m.step_limit = 0;
        try f.arguments(m, 2, 1);
        try kernel.execute(m);
        try std.testing.expectEqual(@as(i64, 128), try m.readCell(f.addresses[3]));
    }
}
test "SNES Gaussian independent overflow anchors and generated data hash" {
    try std.testing.expectEqual(@as(i64, 16376), dsp.gaussian(0, &.{ -16384, -16384, -16384, -16384 }));
    const table = @import("../core/snes_gauss.zig").values;
    var bytes: [1024]u8 = undefined;
    for (table, 0..) |value, i| std.mem.writeInt(u16, bytes[i * 2 ..][0..2], @intCast(value), .little);
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(&bytes, &digest, .{});
    var expected_bytes: [32]u8 = undefined;
    const expected = try std.fmt.hexToBytes(&expected_bytes, "0acd5077942f6cc6676829bc1954a05aeaad51be716f62d9ef4e8e7c94685af2");
    try std.testing.expectEqualSlices(u8, expected, &digest);
}
test "SNES byte-write notifications preserve unrelated registered ARAM slots" {
    try support.skipWithout(&.{.audio});
    const registry = @import("../core/address_registry.zig");
    var output = support.Output{};
    const m = try support.createMachine(&output);
    defer support.destroyMachine(m);
    const f = try Fixture.init(m);
    const touched = f.addresses[1];
    const untouched = touched + 8;
    try m.writeCell(touched, f.addresses[0]);
    try m.writeCell(untouched, f.addresses[0]);
    try registry.registerMemory(m, touched);
    try registry.registerMemory(m, untouched);
    m.memory[@intCast(f.addresses[0] + 108)] = 0;
    try f.arguments(m, 1, 1);
    try kernel.execute(m);
    try std.testing.expectEqual(registry.Status.damaged, m.addresses.records[registry.index(m, .memory, touched).?].status);
    try std.testing.expectEqual(registry.Status.valid, m.addresses.records[registry.index(m, .memory, untouched).?].status);
    try std.testing.expectEqual(f.addresses[0], try m.readCell(untouched));
}
