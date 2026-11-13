const std = @import("std");
const support = @import("support.zig");
const forth = @import("../forth.zig");
const map = @import("../core/memory_map.zig");
const registry = @import("../core/address_registry.zig");

fn searchOpen(context: ?*anyopaque, name: []const u8, access: forth.FileAccess, create: bool) forth.FileResult {
    const output: *support.Output = @ptrCast(@alignCast(context.?));
    output.file_writes += 1;
    if (name.len > output.command.len) return .{ .ior = forth.errnoIor(36) };
    @memcpy(output.command[0..name.len], name);
    output.command_len = name.len;
    if (access != .read_only or create) return .{ .ior = forth.errnoIor(22) };
    if (std.mem.startsWith(u8, name, "denied/")) return .{ .ior = forth.errnoIor(13) };
    if (std.mem.eql(u8, name, "second/name") or std.mem.eql(u8, name, "/home/lemon/name") or std.mem.eql(u8, name, "/named/name")) return support.fakeOpen(context, "a.txt", access, create);
    return support.fakeOpen(context, name, access, create);
}
fn home(_: ?*anyopaque, user: []const u8, buffer: []u8) forth.RuntimeError!?usize {
    if (user.len == 0) {
        @memcpy(buffer[0..11], "/home/lemon");
        return 11;
    }
    if (!std.mem.eql(u8, user, "known")) return null;
    @memcpy(buffer[0..6], "/named");
    return 6;
}
const ops = blk: {
    var value = support.fake_file_ops;
    value.open = searchOpen;
    value.user_home = home;
    break :blk value;
};
fn setup(output: *support.Output) !*forth.State {
    try support.skipWithout(&.{.files});
    const m = try support.createMachine(output);
    m.writer.file_ops = &ops;
    output.files[0].exists = true;
    return m;
}

test "P05a search tries ordered candidates read only and returns a borrowed name" {
    var output = support.Output{};
    const m = try setup(&output);
    defer support.destroyMachine(m);
    try m.interpretLine("VARIABLE P P PATH= missing|second S\" name\" P OPEN-PATH-FILE");
    try std.testing.expectEqual(@as(usize, 2), output.file_writes);
    try support.expectStack(m, &.{ forth.first_file_id, map.string_buffer_base, 11, 0 });
    try std.testing.expectEqualStrings("second/name", m.memory[@intCast(map.string_buffer_base)..][0..11]);
    try std.testing.expect(output.files[0].open);
    m.data_depth = 0;
    try m.interpretLine("S\" ~+/a.txt\" P FILE>PATH");
    try support.expectStack(m, &.{ map.string_buffer_base, 5 });
    try std.testing.expectEqualStrings("a.txt", m.memory[@intCast(map.string_buffer_base)..][0..5]);
    try std.testing.expect(!output.files[0].open);
    try registry.validate(m);
}

test "P05a search stops at empty entries and reports last open error" {
    var output = support.Output{};
    const m = try setup(&output);
    defer support.destroyMachine(m);
    try m.interpretLine("VARIABLE P P PATH= missing|denied S\" name\" P OPEN-PATH-FILE");
    try support.expectStack(m, &.{forth.errnoIor(13)});
    m.data_depth = 0;
    try m.interpretLine("P PATH= missing||second S\" name\" P OPEN-PATH-FILE");
    try support.expectStack(m, &.{forth.errnoIor(2)});
    m.data_depth = 0;
    output.file_writes = 0;
    try m.interpretLine("P CLEAR-PATH S\" a.txt\" P OPEN-PATH-FILE");
    try support.expectStack(m, &.{-37});
    try std.testing.expectEqual(@as(usize, 0), output.file_writes);
    m.data_depth = 0;
    try std.testing.expectError(error.Thrown, m.interpretLine("S\" a.txt\" P FILE>PATH"));
    try support.expectStack(m, &.{});
}

test "P05a tilde expansion is native only and leaves the returned spelling" {
    var output = support.Output{};
    const m = try setup(&output);
    defer support.destroyMachine(m);
    try m.interpretLine("VARIABLE P S\" ~/name\" -1 FILE>PATH TYPE");
    try std.testing.expectEqualStrings("~/name", output.written());
    try std.testing.expectEqualStrings("/home/lemon/name", output.command[0..output.command_len]);
    output.len = 0;
    try m.interpretLine("S\" ~known/name\" P FILE>PATH TYPE");
    try std.testing.expectEqualStrings("~known/name", output.written());
    try std.testing.expectEqualStrings("/named/name", output.command[0..output.command_len]);
    try std.testing.expect(!output.files[0].open);
}

test "P05a file to path propagates close failure without leaking its handle" {
    var output = support.Output{};
    const m = try setup(&output);
    defer support.destroyMachine(m);
    output.close_fails = true;
    try std.testing.expectError(error.Thrown, m.interpretLine("VARIABLE P S\" ./a.txt\" P FILE>PATH"));
    try std.testing.expect(!output.files[0].open);
    try support.expectStack(m, &.{});
}

test "P05a search preflights stack ranges and path length before host access" {
    var output = support.Output{};
    const m = try setup(&output);
    defer support.destroyMachine(m);
    try m.interpretLine("VARIABLE P P PATH= second");
    const owner = m.words[m.lookup("P").?].value;
    m.data_depth = m.data_stack.len;
    m.data_stack[m.data_depth - 3] = 0;
    m.data_stack[m.data_depth - 2] = 0;
    m.data_stack[m.data_depth - 1] = owner;
    try std.testing.expectError(error.StackOverflow, m.executeBuiltin(.open_path_file));
    m.data_depth = 0;
    try m.push(@intCast(m.memory.len));
    try m.push(1);
    try m.push(owner);
    try std.testing.expectError(error.InvalidAddress, m.executeBuiltin(.open_path_file));
    m.data_depth = 0;
    const long = (try m.heapAllocate(1025)).?;
    @memset(m.memory[@intCast(long)..][0..1025], 'x');
    try m.push(long);
    try m.push(1025);
    try m.push(owner);
    try std.testing.expectError(error.StringTooLong, m.executeBuiltin(.open_path_file));
    try support.expectStack(m, &.{ long, 1025, owner });
    try std.testing.expectEqual(@as(usize, 0), output.file_writes);
    if (@import("build_options").debug) {
        m.data_depth = 0;
        try m.interpretLine("P PATH= missing|second S\" name\" P");
        m.step_limit = 1;
        m.steps_left = 1;
        try std.testing.expectError(error.StepLimit, m.executeBuiltin(.open_path_file));
        try std.testing.expectEqual(@as(usize, 1), output.file_writes);
        try std.testing.expect(!output.files[0].open);
    }
}

test "P05a search handles a previous result as input and survives image restoration" {
    var output = support.Output{};
    const m = try setup(&output);
    defer support.destroyMachine(m);
    try m.interpretLine("VARIABLE P S\" ./a.txt\" P FILE>PATH P PATH= ~+ P FILE>PATH TYPE");
    try std.testing.expectEqualStrings("a.txt", output.written());
    const image = try std.testing.allocator.alloc(u8, try m.encodedSize());
    defer std.testing.allocator.free(image);
    _ = try m.encodeImage(image);
    try m.restoreImage(image);
    output.len = 0;
    try m.interpretLine("S\" a.txt\" P FILE>PATH TYPE");
    try std.testing.expectEqualStrings("a.txt", output.written());
    try registry.validate(m);
}

test "P05a search rejects embedded NUL without opening truncated names" {
    var output = support.Output{};
    const m = try setup(&output);
    defer support.destroyMachine(m);
    try m.interpretLine("VARIABLE P P PATH= ~+ S\" a.txtX\" 2DUP + 1- 0 SWAP C! P OPEN-PATH-FILE");
    try support.expectStack(m, &.{forth.errnoIor(map.errno_invalid)});
    try std.testing.expectEqual(@as(usize, 0), output.file_writes);
}

test "P05a path lookup needs no free heap and leaves no persistent owner root" {
    var output = support.Output{};
    const m = try setup(&output);
    defer support.destroyMachine(m);
    try m.interpretLine("VARIABLE P S\" ./a.txt\" P");
    const top = m.heapTop();
    _ = (try m.heapAllocate(@intCast(m.sizes.heapEnd() - top - 16))).?;
    const full = m.heapTop();
    const roots = m.addresses.count;
    try m.executeBuiltin(.file_to_path);
    try support.expectStack(m, &.{ map.string_buffer_base, 5 });
    try std.testing.expectEqual(full, m.heapTop());
    try std.testing.expectEqual(roots, m.addresses.count);
    try std.testing.expect(!output.files[0].open);
    try registry.validate(m);
}
