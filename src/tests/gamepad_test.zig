const std = @import("std");
const gp = @import("../core/gamepad.zig");
const support = @import("support.zig");

var next: gp.Snapshot = .{};
var available = true;
fn poll(_: ?*anyopaque, out: *gp.Snapshot) bool {
    out.* = next;
    return available;
}
fn mapping(_: ?*anyopaque, value: []const u8) bool {
    return std.mem.eql(u8, value, "test mapping");
}
const ops: gp.Ops = .{ .poll = poll, .mapping = mapping };

test "gamepad snapshots distinguish missing backend, disconnection and mapped/raw input" {
    try support.skipWithout(&.{.graphics});
    var output = support.Output{};
    const m = try support.createMachine(&output);
    defer support.destroyMachine(m);
    try m.interpretLine("REQUIRE-GRAPHICS ALSO GRAPHICS GAMEPAD-POLL 0 GAMEPAD? 0 GAMEPAD-BUTTONS");
    try support.expectStack(m, &.{ -1, 0, 0 });
    try m.interpretLine("DROP DROP DROP");
    m.writer.gamepad_ops = &ops;
    next = .{};
    available = true;
    next.count = 2;
    next.pads[0] = .{ .id = 123, .mapped = true, .buttons = 1 | (1 << 14), .axis_count = 6, .button_count = 26, .hat_count = 1, .name_len = 3 };
    @memcpy(next.pads[0].name[0..3], "Pad");
    next.pads[0].axes[0] = -32768;
    next.pads[0].axes[5] = 32767;
    next.pads[0].hats[0] = 3;
    next.pads[1] = .{ .id = 456, .buttons = 0x80000000, .axis_count = 16, .button_count = 32, .hat_count = 4 };
    next.pads[1].axes[15] = -1234;
    try m.interpretLine("GAMEPAD-POLL 0 GAMEPAD-ID 0 GAMEPAD-MAPPED? 0 0 GAMEPAD-AXIS 5 0 GAMEPAD-AXIS 0 0 GAMEPAD-HAT 14 0 GAMEPAD-BUTTON?");
    try support.expectStack(m, &.{ 2, 123, -1, -32768, 32767, 3, -1 });
    try m.interpretLine("2DROP 2DROP 2DROP DROP 1 GAMEPAD-MAPPED? 31 1 GAMEPAD-BUTTON? 15 1 GAMEPAD-AXIS PAD 2 0 GAMEPAD-NAME PAD C@ PAD 1+ C@");
    try support.expectStack(m, &.{ 0, -1, -1234, 2, 'P', 'a' });
    try m.interpretLine("2DROP 2DROP 2DROP");
    next = .{};
    try m.interpretLine("GAMEPAD-POLL 0 GAMEPAD? 0 GAMEPAD-ID 0 GAMEPAD-BUTTONS 0 0 GAMEPAD-AXIS PAD 10 0 GAMEPAD-NAME");
    try support.expectStack(m, &.{ 0, 0, 0, 0, 0, 0 });
    try m.interpretLine("2DROP 2DROP 2DROP");
    available = false;
    next.count = 1;
    next.pads[0].buttons = 0xffffffff;
    try m.interpretLine("GAMEPAD-POLL 0 GAMEPAD-BUTTONS");
    try support.expectStack(m, &.{ -1, 0 });
}

test "gamepad rejects invalid indices and mapping failure without corrupting state" {
    try support.skipWithout(&.{.graphics});
    var output = support.Output{};
    const m = try support.createMachine(&output);
    defer support.destroyMachine(m);
    try m.interpretLine("REQUIRE-GRAPHICS ALSO GRAPHICS");
    for ([_][]const u8{ "-1 GAMEPAD?", "8 GAMEPAD?", "16 0 GAMEPAD-AXIS", "-1 0 GAMEPAD-AXIS", "32 0 GAMEPAD-BUTTON?", "4 0 GAMEPAD-HAT", "7 0 GFX-GAMEPAD-QUERY" }) |source| {
        try std.testing.expectError(error.InvalidNumber, m.interpretLine(source));
    }
    m.writer.gamepad_ops = &ops;
    try m.interpretLine("S\" test mapping\" GAMEPAD-MAP S\" bad\" GAMEPAD-MAP");
    try support.expectStack(m, &.{ -1, 0 });
}
