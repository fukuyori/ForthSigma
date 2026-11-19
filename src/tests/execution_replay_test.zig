//! Establish replay invariants using the existing standard parser, before wiring host polling.
const std = @import("std");
const ev = @import("../core/standard_event.zig");
const base = @import("../core/runtime_base.zig");
const defs = @import("../core/defs.zig");

const Feed = struct {
    packets: []const ev.Packet,
    index: usize = 0,
    bytes: usize = 0,
    last_three: bool = false,
    fn clock(_: ?*anyopaque) base.Error!i128 {
        return 0;
    }
    fn read(context: ?*anyopaque, _: i32) defs.RuntimeError!ev.Result {
        const self: *@This() = @ptrCast(@alignCast(context.?));
        if (self.index == self.packets.len) return .timeout;
        const packet = self.packets[self.index];
        self.last_three = packet.value == 3 and packet.mouse == null and !packet.reset;
        self.index += 1;
        if (packet.reset) return .restart;
        if (packet.mouse == null and packet.value >= 0 and packet.value <= 255) self.bytes += 1;
        return .{ .event = packet };
    }
};

fn probe(original: ev.Decoder, packets: []const ev.Packet) !?usize {
    var shadow = original;
    var feed = Feed{ .packets = packets };
    const source = ev.Source{ .context = &feed, .read_fn = Feed.read, .clock = .{ .context = &feed, .now_fn = Feed.clock } };
    for (0..packets.len + original.length + 2) |_| {
        const before = feed.index;
        feed.last_three = false;
        const result = ev.read(&shadow, source, 0, false) catch |err| {
            if (err != error.UserInterrupt) return err;
            return original.length + feed.bytes - 1 - (if (feed.last_three) @as(usize, 0) else shadow.length);
        };
        if (result == .timeout and feed.index == before) return null;
    }
    return null;
}

test "read-only replay accounts bytes across mouse events paste reset and partial input" {
    var original = ev.Decoder{};
    @memcpy(original.bytes[0..2], "ab");
    original.length = 2;
    original.last_mouse.column = 7;
    const packets = [_]ev.Packet{
        .{ .value = 'c' },
        .{ .value = @import("../core/standard_keys.zig").mouse, .mouse = .{ .column = 9, .row = 1, .buttons = 1, .wheel = 0 } },
        .{ .value = 3 },
    };
    try std.testing.expectEqual(@as(?usize, 3), try probe(original, &packets));
    try std.testing.expectEqual(@as(usize, 2), original.length);
    try std.testing.expectEqual(@as(i64, 7), original.last_mouse.column);
    const bytes = "\x1b[200~\x03\x1b[201~\x03";
    var paste: [bytes.len]ev.Packet = undefined;
    for (bytes, &paste) |byte, *packet| packet.* = .{ .value = byte };
    try std.testing.expectEqual(@as(?usize, bytes.len - 1), try probe(.{}, &paste));
    original = .{};
    @memcpy(original.bytes[0..4], "\x1b[20");
    original.length = 4;
    const tail = paste[4..];
    try std.testing.expectEqual(@as(?usize, bytes.len - 1), try probe(original, tail));
    original = .{ .paste = true };
    try std.testing.expectEqual(@as(?usize, null), try probe(original, &.{.{ .value = 3 }}));
    try std.testing.expectEqual(@as(?usize, 0), try probe(original, &.{ .{ .value = 0, .reset = true }, .{ .value = 3 } }));
    original = .{};
    original.bytes[0] = 3;
    original.length = 1;
    try std.testing.expectEqual(@as(?usize, 0), try probe(original, &.{}));
}

test "replay distinguishes source interrupt from buffered interrupt after incomplete prefixes" {
    for ([_][]const u8{ "\x1b\x03", "\x1b[\x03", "a\x1b\x03z", "\xe6\x03", "\xf0\x9f\x03" }) |bytes| {
        var packets: [16]ev.Packet = undefined;
        for (bytes, 0..) |byte, index| packets[index] = .{ .value = byte };
        try std.testing.expectEqual(@as(?usize, std.mem.indexOfScalar(u8, bytes, 3).?), try probe(.{}, packets[0..bytes.len]));
    }
}
