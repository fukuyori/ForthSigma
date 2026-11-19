const std = @import("std");
const forth = @import("../forth.zig");
const support = @import("support.zig");
const io = @import("../core/host_interface.zig");

const Fake = struct {
    var checked: usize = 0;
    var waited: usize = 0;
    var read_count: usize = 0;
    var written: usize = 0;
    fn check(_: ?*anyopaque, id: forth.Cell, _: bool) forth.Cell {
        checked += 1;
        return if (id == 99) -521 else 0;
    }
    fn wait(_: ?*anyopaque, ids: []const forth.Cell, ms: i64, writing: bool) forth.RuntimeError!io.FileWaitResult {
        if (ids.len != 2 or ids[0] != 10 or ids[1] != 11 or ms != 42) return error.HostFailed;
        waited += 1;
        return .{ .index = if (writing) 0 else 1 };
    }
    fn read(_: ?*anyopaque, _: forth.Cell, bytes: []u8) forth.RuntimeError!io.AvailableResult {
        read_count += 1;
        if (bytes.len < 2) return error.HostFailed;
        @memcpy(bytes[0..2], "AB");
        return .{ .count = 2, .eof = false, .ior = -517 };
    }
    fn write(_: ?*anyopaque, _: forth.Cell, bytes: []const u8) forth.RuntimeError!forth.FileResult {
        if (!std.mem.eql(u8, bytes, "AB")) return error.HostFailed;
        written += 1;
        return .{ .value = 1 };
    }
};

test "asynchronous file words validate all IDs and expose partial transfer errors" {
    try support.skipWithout(&.{ .files, .extension });
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    var ops = support.fake_file_ops;
    ops.io_check = Fake.check;
    ops.wait_files = Fake.wait;
    ops.read_available = Fake.read;
    ops.write_available = Fake.write;
    machine.writer.file_ops = &ops;
    Fake.checked = 0;
    Fake.waited = 0;
    Fake.read_count = 0;
    Fake.written = 0;
    try machine.interpretLine("REQUIRE-EXTENSION ALSO EXTENSION CREATE IDS 10 , 99 , IDS 2 42 WAIT-FILES");
    try support.expectStack(machine, &.{ 1, -521 });
    try std.testing.expectEqual(@as(usize, 2), Fake.checked);
    try std.testing.expectEqual(@as(usize, 0), Fake.waited);
    machine.data_depth = 0;
    try machine.interpretLine("11 IDS CELL+ ! IDS 2 42 WAIT-FILES IDS 2 42 WAIT-WRITABLE");
    try support.expectStack(machine, &.{ 1, 0, 0, 0 });
    machine.data_depth = 0;
    try machine.interpretLine("PAD 8 10 READ-AVAILABLE PAD 2 10 WRITE-AVAILABLE");
    try support.expectStack(machine, &.{ 2, 0, -517, 1, 0 });
    try std.testing.expectEqual(@as(usize, 1), Fake.read_count);
    try std.testing.expectEqual(@as(usize, 1), Fake.written);
    machine.data_depth = 0;
    const before = Fake.checked;
    try machine.push(-1);
    try machine.push(2);
    try machine.push(42);
    try std.testing.expectError(error.InvalidAddress, machine.executeBuiltin(.wait_files));
    try std.testing.expectEqual(before, Fake.checked);
}

test "old file hosts reject asynchronous operations before consuming arguments" {
    try support.skipWithout(&.{ .files, .extension });
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try machine.push(0);
    try machine.push(1);
    try machine.push(0);
    try std.testing.expectError(error.HostUnavailable, machine.executeBuiltin(.wait_files));
    try support.expectStack(machine, &.{ 0, 1, 0 });
}

test "ordinary file reads retain partial host counts with an I/O error" {
    try support.skipWithout(&.{.files});
    const Partial = struct {
        fn read(_: ?*anyopaque, _: forth.Cell, bytes: []u8) forth.FileResult {
            @memcpy(bytes[0..2], "AB");
            return .{ .value = 2, .ior = -516 };
        }
        fn line(_: ?*anyopaque, _: forth.Cell, bytes: []u8) forth.LineResult {
            @memcpy(bytes[0..2], "CD");
            return .{ .length = 2, .found = true, .ior = -516 };
        }
    };
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    var ops = support.fake_file_ops;
    ops.read = Partial.read;
    ops.read_line = Partial.line;
    machine.writer.file_ops = &ops;
    try machine.interpretLine("PAD 8 4 READ-FILE PAD 8 4 READ-LINE");
    try support.expectStack(machine, &.{ 2, -516, 2, -1, -516 });
}
