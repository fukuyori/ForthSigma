const std = @import("std");
const support = @import("support.zig");
const defs = @import("../core/defs.zig");
const io = @import("../core/host_interface.zig");
const map = @import("../core/memory_map.zig");

test "COMPACT-FILENAME matches Gforth 1010 cases and keeps the source address" {
    try support.skipWithout(&.{.extension});
    const Fixture = struct { reference: []const u8, cases: []const [2][]const u8 };
    const data = try std.json.parseFromSlice(Fixture, std.testing.allocator, @embedFile("compact_filename_cases"), .{});
    defer data.deinit();
    try std.testing.expectEqual(@as(usize, 1010), data.value.cases.len);
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    for (data.value.cases) |case| {
        @memcpy(machine.memory[0x10000..][0..case[0].len], case[0]);
        machine.data_depth = 0;
        try machine.push(0x10000);
        try machine.push(@intCast(case[0].len));
        try machine.executeBuiltin(.compact_filename);
        try support.expectStack(machine, &.{ 0x10000, @intCast(case[1].len) });
        try std.testing.expectEqualStrings(case[1], machine.memory[0x10000..][0..case[1].len]);
    }
    @memset(machine.memory[0x10000..][0..8003], 'a');
    machine.data_depth = 0;
    try machine.push(0x10000);
    try machine.push(8003);
    try machine.executeBuiltin(.compact_filename);
    try support.expectStack(machine, &.{ 0x10000, 8003 });
}

const Fake = struct {
    var called: usize = 0;
    var released: usize = 0;
    var failure: bool = false;
    fn path(_: ?*anyopaque, _: []const u8) io.OwnedPath {
        called += 1;
        return .{ .bytes = "/resolved", .ior = if (failure) -514 else 0 };
    }
    fn release(_: ?*anyopaque, _: []const u8) void {
        released += 1;
    }
    fn metadata(_: ?*anyopaque, _: []const u8) io.FileMetadata {
        called += 1;
        return .{ .size = std.math.maxInt(u64), .seconds = -1, .nanoseconds = 900000000, .ior = if (failure) -514 else 0 };
    }
    fn sync(_: ?*anyopaque, _: map.Cell) map.Cell {
        called += 1;
        return -517;
    }
};

test "filesystem owned results alias short buffers errors and metadata shape" {
    try support.skipWithout(&.{ .extension, .files });
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    var ops = support.fake_file_ops;
    ops.realpath = Fake.path;
    ops.release_realpath = Fake.release;
    ops.metadata = Fake.metadata;
    ops.sync = Fake.sync;
    machine.writer.file_ops = &ops;
    Fake.called = 0;
    Fake.released = 0;
    Fake.failure = false;
    try machine.interpretLine("REQUIRE-EXTENSION ALSO EXTENSION CREATE FS-TEST-BUFFER 64 ALLOT FS-TEST-BUFFER 64 42 FILL");
    const buffer = machine.data_here - 64;
    try machine.interpretLine("FS-TEST-BUFFER 4 FS-TEST-BUFFER 0 FILE>REALPATH");
    try support.expectStack(machine, &.{ 9, map.errnoIor(34) });
    try std.testing.expectEqual(@as(u8, 42), machine.memory[@intCast(buffer)]);
    machine.data_depth = 0;
    try machine.interpretLine("FS-TEST-BUFFER 4 FS-TEST-BUFFER 64 FILE>REALPATH");
    try support.expectStack(machine, &.{ 9, 0 });
    try std.testing.expectEqualStrings("/resolved", machine.memory[@intCast(buffer)..][0..9]);
    try std.testing.expectEqual(@as(usize, 2), Fake.released);
    machine.data_depth = 0;
    Fake.failure = true;
    try machine.interpretLine("FS-TEST-BUFFER 4 FS-TEST-BUFFER 64 FILE>REALPATH");
    try support.expectStack(machine, &.{ 0, -514 });
    try std.testing.expectEqualStrings("/resolved", machine.memory[@intCast(buffer)..][0..9]);
    try std.testing.expectEqual(@as(usize, 3), Fake.released);
    machine.data_depth = 0;
    try machine.interpretLine("FS-TEST-BUFFER 4 FILE-METADATA");
    try support.expectStack(machine, &.{ 0, 0, 0, 0, -514 });
    machine.data_depth = 0;
    Fake.failure = false;
    try machine.interpretLine("FS-TEST-BUFFER 4 FILE-METADATA 123 SYNC-FILE");
    try support.expectStack(machine, &.{ -1, 0, -1, 900000000, 0, -517 });
    machine.data_depth = machine.data_stack.len - 2;
    machine.data_stack[machine.data_depth - 2] = buffer;
    machine.data_stack[machine.data_depth - 1] = 4;
    const before = Fake.called;
    try std.testing.expectError(error.StackOverflow, machine.executeBuiltin(.file_metadata));
    try std.testing.expectEqual(before, Fake.called);
    machine.data_depth = 0;
    try machine.push(buffer);
    try machine.push(-1);
    try std.testing.expectError(error.InvalidAddress, machine.executeBuiltin(.file_metadata));
    try support.expectStack(machine, &.{ buffer, -1 });
    try std.testing.expectEqual(before, Fake.called);
    ops.realpath = null;
    machine.data_depth = 0;
    try machine.interpretLine("FS-TEST-BUFFER 4 FS-TEST-BUFFER 64");
    try std.testing.expectError(error.HostUnavailable, machine.executeBuiltin(.file_realpath));
    try support.expectStack(machine, &.{ buffer, 4, buffer, 64 });
}

test "filesystem exclusions keep compact host-free and reject OS words" {
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    if (!defs.extension_enabled) {
        inline for (.{ defs.Builtin.compact_filename, .file_realpath, .file_metadata, .sync_file }) |word| try std.testing.expectError(error.InvalidExecutionToken, machine.executeBuiltin(word));
    } else if (!defs.files_enabled) {
        try machine.interpretLine("REQUIRE-EXTENSION ALSO EXTENSION S\" a/../b\" COMPACT-FILENAME TYPE");
        try std.testing.expectEqualStrings("b", output.written());
        try machine.push(0);
        try machine.push(0);
        try std.testing.expectError(error.HostUnavailable, machine.executeBuiltin(.file_metadata));
    } else return error.SkipZigTest;
}

test "filesystem compiled words survive image restore without OS resources" {
    try support.skipWithout(&.{ .extension, .files, .image });
    var output = support.Output{};
    const source = try support.createMachine(&output);
    defer support.destroyMachine(source);
    try source.interpretLine("REQUIRE-EXTENSION ALSO EXTENSION : FS-SAVED S\" a/../b\" COMPACT-FILENAME TYPE S\" file\" FILE-METADATA ; PREVIOUS");
    const image = try std.testing.allocator.alloc(u8, try source.encodedSize());
    defer std.testing.allocator.free(image);
    _ = try source.encodeImage(image);
    const restored = try support.createMachine(&output);
    defer support.destroyMachine(restored);
    try restored.restoreImage(image);
    var ops = support.fake_file_ops;
    ops.metadata = Fake.metadata;
    restored.writer.file_ops = &ops;
    Fake.failure = false;
    try restored.interpretLine("FS-SAVED");
    try std.testing.expectEqualStrings("b", output.written());
    try support.expectStack(restored, &.{ -1, 0, -1, 900000000, 0 });
}
