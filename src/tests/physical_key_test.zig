const std = @import("std");
const forth = @import("../forth.zig");
const support = @import("support.zig");
const keys = @import("../core/physical_keys.zig");
const words = @import("../core/words_graphics.zig");
var host: keys.Host = .{};
var snapshots: usize = 0;
var resets: usize = 0;
fn available(_: ?*anyopaque) bool {
    return host.available;
}
fn supported(_: ?*anyopaque, scan: u8) bool {
    return host.has(scan);
}
fn held(_: ?*anyopaque, scan: u8) bool {
    return host.has(scan) and host.tracker.held(scan);
}
fn next(_: ?*anyopaque) ?keys.Event {
    return host.tracker.next();
}
fn resync(_: ?*anyopaque, bitmap: *keys.Bitmap) void {
    snapshots += 1;
    bitmap.* = host.tracker.resync();
}
fn reset(_: ?*anyopaque) void {
    resets += 1;
    host.tracker.boundary();
}
const ops: keys.Ops = .{ .available = available, .supported = supported, .held = held, .next = next, .resync = resync, .reset = reset };
fn prepare() void {
    host = .{ .available = true };
    host.support(4);
    host.support(225);
    host.support(229);
    snapshots = 0;
    resets = 0;
}

test "physical public words preserve edges independently of text and both Shift keys" {
    if (!@import("build_options").graphics) return error.SkipZigTest;
    try support.skipWithout(&.{.graphics});
    prepare();
    var out: support.Output = .{};
    const machine = try support.createMachine(&out);
    defer support.destroyMachine(machine);
    machine.writer.physical_key_ops = &ops;
    try machine.interpretLine("REQUIRE-GRAPHICS GRAPHICS");
    host.update(225, true);
    host.update(229, true);
    host.update(4, true);
    host.update(4, false);
    try machine.interpretLine("SC-A SCAN-SUPPORTED? SC-LSHIFT SCAN-HELD? SC-RSHIFT SCAN-HELD? SC-A SCAN-HELD? SCAN-INPUT?");
    try support.expectStack(machine, &.{ -1, -1, -1, 0, -1 });
    machine.data_depth = 0;
    // Existing key state polling must not consume the four physical edges.
    try machine.interpretLine("65 KEY-HELD? DROP");
    try machine.interpretLine("KEY-EVENT KEY-EVENT KEY-EVENT KEY-EVENT KEY-EVENT");
    try support.expectStack(machine, &.{ 225, 1, -1, 229, 1, -1, 4, 1, -1, 4, 2, -1, 0 });
}
test "physical resync validates destination before ack and copies unaligned 32 bytes" {
    if (!@import("build_options").graphics) return error.SkipZigTest;
    try support.skipWithout(&.{.graphics});
    prepare();
    var out: support.Output = .{};
    const machine = try support.createMachine(&out);
    defer support.destroyMachine(machine);
    machine.writer.physical_key_ops = &ops;
    host.update(225, true);
    host.tracker.loseHistory();
    try machine.push(-1);
    try std.testing.expectError(error.InvalidAddress, words.execute(machine, .gfx_key_resync));
    try std.testing.expectEqual(@as(usize, 0), snapshots);
    try std.testing.expect(host.tracker.resync_required);
    try machine.interpretLine("CREATE PH-BITS 33 ALLOT PH-BITS 1+");
    const address = try machine.pop();
    const index = try machine.memoryAddress(address, 32);
    try machine.push(address);
    try words.execute(machine, .gfx_key_resync);
    try std.testing.expectEqual(@as(u8, 2), machine.memory[index + 28]);
    try std.testing.expectEqual(@as(usize, 1), snapshots);
    try std.testing.expect(!host.tracker.resync_required);
    for ([_]i64{ -1, 256 }) |scan| {
        try machine.push(scan);
        try std.testing.expectError(error.InvalidNumber, words.execute(machine, .gfx_scan_held));
    }
}
test "physical unavailable writer returns false and zero bitmap without opening window" {
    if (!@import("build_options").graphics) return error.SkipZigTest;
    try support.skipWithout(&.{.graphics});
    var out: support.Output = .{};
    const machine = try support.createMachine(&out);
    defer support.destroyMachine(machine);
    try words.execute(machine, .gfx_scan_input);
    try machine.push(4);
    try words.execute(machine, .gfx_scan_supported);
    try machine.push(4);
    try words.execute(machine, .gfx_scan_held);
    try words.execute(machine, .gfx_key_event);
    try support.expectStack(machine, &.{ 0, 0, 0, 0 });
    machine.data_depth = 0;
    try machine.interpretLine("CREATE PH-BITS 32 ALLOT PH-BITS");
    const address = try machine.pop();
    const index = try machine.memoryAddress(address, 32);
    @memset(machine.memory[index..][0..32], 255);
    try machine.push(address);
    try words.execute(machine, .gfx_key_resync);
    try std.testing.expectEqual(@as(keys.Bitmap, @splat(0)), machine.memory[index..][0..32].*);
}
test "physical KEY-EVENT reserves stack before consuming a host edge" {
    if (!@import("build_options").graphics) return error.SkipZigTest;
    try support.skipWithout(&.{.graphics});
    prepare();
    var out: support.Output = .{};
    const machine = try support.createMachine(&out);
    defer support.destroyMachine(machine);
    machine.writer.physical_key_ops = &ops;
    host.update(4, true);
    machine.data_depth = machine.data_stack.len - 2;
    try std.testing.expectError(error.StackOverflow, words.execute(machine, .gfx_key_event));
    machine.data_depth = 0;
    try words.execute(machine, .gfx_key_event);
    try support.expectStack(machine, &.{ 4, 1, -1 });
}
test "physical restore resets only after successful image preflight" {
    if (!@import("build_options").graphics) return error.SkipZigTest;
    try support.skipWithout(&.{ .graphics, .image });
    prepare();
    var out: support.Output = .{};
    const machine = try support.createMachine(&out);
    defer support.destroyMachine(machine);
    machine.writer.physical_key_ops = &ops;
    const bytes = try std.testing.allocator.alloc(u8, forth.State.imageCapacity(.small));
    defer std.testing.allocator.free(bytes);
    const length = try machine.encodeImage(bytes);
    host.update(4, true);
    try std.testing.expectError(error.InvalidImage, machine.restoreImage(bytes[0 .. length - 1]));
    try std.testing.expectEqual(@as(usize, 0), resets);
    try std.testing.expect(host.tracker.held(4));
    try machine.restoreImage(bytes[0..length]);
    try std.testing.expectEqual(@as(usize, 1), resets);
    try std.testing.expect(!host.tracker.held(4));
    try std.testing.expectEqual(keys.Event{ .scan = 0, .kind = .resync }, host.tracker.next().?);
}

test "physical constants are unique HID usages and cover every native map value" {
    if (!@import("build_options").graphics) return error.SkipZigTest;
    var out: support.Output = .{};
    const machine = try support.createMachine(&out);
    defer support.destroyMachine(machine);
    try machine.interpretLine("REQUIRE-GRAPHICS GRAPHICS");
    var present: [256]bool = @splat(false);
    for (words.library_words) |name| {
        if (!std.mem.startsWith(u8, name, "SC-") or std.mem.eql(u8, name, "SC-PRESS") or std.mem.eql(u8, name, "SC-RELEASE") or std.mem.eql(u8, name, "SC-RESYNC")) continue;
        try machine.interpretLine(name);
        const value = try machine.pop();
        try std.testing.expect(value >= 4 and value <= 255);
        const index: usize = @intCast(value);
        try std.testing.expect(!present[index]);
        present[index] = true;
    }
    const mapping = @import("../physical_key_map.zig");
    for (mapping.windows) |scan| if (scan >= 4) {
        try std.testing.expect(present[scan]);
    };
    for (mapping.darwin) |scan| if (scan >= 4) {
        try std.testing.expect(present[scan]);
    };
    for ([_][4]u8{ "AD01".*, "COMP".*, "LFSH".*, "RGHT".* }) |name| try std.testing.expect(present[mapping.xkbScan(name)]);
}
test "physical bitmap writes damage overlapping relocation records" {
    if (!@import("build_options").graphics) return error.SkipZigTest;
    prepare();
    var out: support.Output = .{};
    const machine = try support.createMachine(&out);
    defer support.destroyMachine(machine);
    machine.writer.physical_key_ops = &ops;
    try machine.interpretLine("CREATE PH-REG 32 ALLOT PH-REG");
    const address = try machine.pop();
    const registry = @import("../core/address_registry.zig");
    try registry.registerMemory(machine, address);
    const id = registry.index(machine, .memory, address).?;
    try std.testing.expectEqual(registry.Status.valid, machine.addresses.records[id].status);
    try machine.push(address);
    try words.execute(machine, .gfx_key_resync);
    try std.testing.expectEqual(registry.Status.damaged, machine.addresses.records[id].status);
}
