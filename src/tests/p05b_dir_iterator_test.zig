const std = @import("std");
const support = @import("support.zig");
const forth = @import("../forth.zig");
const map = @import("../core/memory_map.zig");
const registry = @import("../core/address_registry.zig");
const names = [_][]const u8{ "日本語-file", "abc", "z" };
fn out(context: ?*anyopaque) *support.Output {
    return @ptrCast(@alignCast(context.?));
}
fn open(context: ?*anyopaque, name: []const u8) forth.FileResult {
    const o = out(context);
    o.file_writes += 1;
    if (o.host_fails) return .{ .ior = forth.errnoIor(13) };
    if (o.files[0].open) return .{ .ior = forth.errnoIor(24) };
    if (name.len > o.command.len) return .{ .ior = forth.errnoIor(36) };
    @memcpy(o.command[0..name.len], name);
    o.command_len = name.len;
    o.files[0].open = true;
    o.key_index = 0;
    return .{ .value = 99 };
}
fn read(context: ?*anyopaque, id: forth.Cell, buffer: []u8) forth.LineResult {
    const o = out(context);
    if (id != 99 or !o.files[0].open) return .{ .ior = forth.errnoIor(forth.errno_bad_file) };
    if (o.host_fails) return .{ .ior = forth.errnoIor(5) };
    if (o.key_index == names.len) return .{};
    const name = names[o.key_index];
    o.key_index += 1;
    const n = @min(buffer.len, name.len);
    @memcpy(buffer[0..n], name[0..n]);
    return .{ .length = n, .found = true, .ior = if (n < name.len) forth.errnoIor(63) else 0 };
}
fn close(context: ?*anyopaque, id: forth.Cell) forth.Cell {
    const o = out(context);
    if (id != 99 or !o.files[0].open) return forth.errnoIor(forth.errno_bad_file);
    o.files[0].open = false;
    return if (o.close_fails) forth.errnoIor(5) else 0;
}
const ops = blk: {
    var value = support.fake_file_ops;
    value.open_dir = open;
    value.read_dir = read;
    value.close_dir = close;
    break :blk value;
};
fn setup(o: *support.Output) !*forth.State {
    try support.skipWithout(&.{.files});
    const m = try support.createMachine(o);
    m.writer.file_ops = &ops;
    return m;
}

test "P05b directory words preserve byte truncation consume entries and require explicit close" {
    var o = support.Output{};
    const m = try setup(&o);
    defer support.destroyMachine(m);
    try m.interpretLine("S\" dir\" OPEN-DIR");
    try support.expectStack(m, &.{ 99, 0 });
    try std.testing.expect(o.files[0].open);
    m.data_depth = 0;
    @memset(m.memory[@intCast(map.pad_address)..][0..32], 'X');
    try m.interpretLine("PAD 2 99 READ-DIR");
    try support.expectStack(m, &.{ 2, -1, forth.errnoIor(63) });
    try std.testing.expectEqualSlices(u8, "日本語-file"[0..2], m.memory[@intCast(map.pad_address)..][0..2]);
    try std.testing.expectEqual(@as(u8, 'X'), m.memory[@intCast(map.pad_address + 2)]);
    m.data_depth = 0;
    try m.interpretLine("PAD 0 99 READ-DIR");
    try support.expectStack(m, &.{ 0, -1, forth.errnoIor(63) });
    m.data_depth = 0;
    try m.interpretLine("PAD 32 99 READ-DIR");
    try support.expectStack(m, &.{ 1, -1, 0 });
    m.data_depth = 0;
    @memset(m.memory[@intCast(map.pad_address)..][0..32], 'X');
    try m.interpretLine("PAD 32 99 READ-DIR PAD 32 99 READ-DIR");
    try support.expectStack(m, &.{ 0, 0, 0, 0, 0, 0 });
    for (m.memory[@intCast(map.pad_address)..][0..32]) |byte| try std.testing.expectEqual(@as(u8, 'X'), byte);
    try std.testing.expect(o.files[0].open);
    m.data_depth = 0;
    try m.interpretLine("99 CLOSE-DIR 99 CLOSE-DIR");
    try support.expectStack(m, &.{ 0, forth.errnoIor(forth.errno_bad_file) });
}

test "P05b directory hooks report errors and close failure still invalidates" {
    var o = support.Output{};
    const m = try setup(&o);
    defer support.destroyMachine(m);
    o.host_fails = true;
    try m.interpretLine("S\" missing\" OPEN-DIR");
    try support.expectStack(m, &.{ 0, forth.errnoIor(13) });
    m.data_depth = 0;
    o.host_fails = false;
    try m.interpretLine("S\" ~/dir\" OPEN-DIR");
    try std.testing.expectEqualStrings("/home/lemon/dir", o.command[0..o.command_len]);
    m.data_depth = 0;
    o.host_fails = true;
    try m.interpretLine("PAD 32 99 READ-DIR");
    try support.expectStack(m, &.{ 0, 0, forth.errnoIor(5) });
    try std.testing.expect(o.files[0].open);
    m.data_depth = 0;
    o.close_fails = true;
    try m.interpretLine("99 CLOSE-DIR 99 CLOSE-DIR");
    try support.expectStack(m, &.{ forth.errnoIor(5), forth.errnoIor(forth.errno_bad_file) });
}

test "P05b directory preflight rejects ranges NUL and missing hooks before resource access" {
    var o = support.Output{};
    const m = try setup(&o);
    defer support.destroyMachine(m);
    try m.push(0);
    try std.testing.expectError(error.StackUnderflow, m.executeBuiltin(.open_dir));
    try support.expectStack(m, &.{0});
    m.data_depth = 0;
    try m.push(@intCast(m.memory.len));
    try m.push(1);
    try std.testing.expectError(error.InvalidAddress, m.executeBuiltin(.open_dir));
    try support.expectStack(m, &.{ @intCast(m.memory.len), 1 });
    m.data_depth = 0;
    try m.interpretLine("S\" badX\" 2DUP + 1- 0 SWAP C! OPEN-DIR");
    try support.expectStack(m, &.{ 0, forth.errnoIor(map.errno_invalid) });
    try std.testing.expectEqual(@as(usize, 0), o.file_writes);
    var partial = ops;
    partial.close_dir = null;
    m.writer.file_ops = &partial;
    m.data_depth = 0;
    try m.push(0);
    try m.push(0);
    try std.testing.expectError(error.FileUnavailable, m.executeBuiltin(.open_dir));
    try std.testing.expectEqual(@as(usize, 0), o.file_writes);
    m.data_depth = 0;
    m.writer.file_ops = &support.fake_file_ops;
    try m.push(0);
    try m.push(0);
    try std.testing.expectError(error.FileUnavailable, m.executeBuiltin(.open_dir));
    try support.expectStack(m, &.{ 0, 0 });
    m.data_depth = 0;
    try m.push(0);
    try m.push(0);
    try m.push(99);
    try std.testing.expectError(error.FileUnavailable, m.executeBuiltin(.read_dir));
    try support.expectStack(m, &.{ 0, 0, 99 });
    m.data_depth = 0;
    try m.push(99);
    try std.testing.expectError(error.FileUnavailable, m.executeBuiltin(.close_dir));
    try support.expectStack(m, &.{99});
    m.writer.file_ops = &ops;
    m.data_depth = 0;
    try m.interpretLine("S\" dir\" OPEN-DIR 2DROP");
    try m.push(@intCast(m.memory.len));
    try m.push(1);
    try m.push(99);
    try std.testing.expectError(error.InvalidAddress, m.executeBuiltin(.read_dir));
    try std.testing.expectEqual(@as(usize, 0), o.key_index);
}

fn overreport(_: ?*anyopaque, _: forth.Cell, buffer: []u8) forth.LineResult {
    return .{ .length = buffer.len + 1, .found = true };
}
test "P05b directory writes notify typed memory and validate host results" {
    var o = support.Output{};
    const m = try setup(&o);
    defer support.destroyMachine(m);
    try m.interpretLine("CREATE DEST 0 A, S\" dir\" OPEN-DIR 2DROP DEST 2 99 READ-DIR");
    try std.testing.expectError(error.InvalidAddress, registry.validate(m));
    const dest = m.words[m.lookup("DEST").?].value;
    try m.writeCell(dest, 0);
    try registry.validate(m);
    var bad = ops;
    bad.read_dir = overreport;
    m.writer.file_ops = &bad;
    m.data_depth = 0;
    try m.push(map.pad_address);
    try m.push(16);
    try m.push(99);
    try std.testing.expectError(error.InvalidAddress, m.executeBuiltin(.read_dir));
    try support.expectStack(m, &.{ map.pad_address, 16, 99 });
}

test "P05b directory words need no spare stack or free heap in compiled execution" {
    var o = support.Output{};
    const m = try setup(&o);
    defer support.destroyMachine(m);
    try m.interpretLine(": OPEN OPEN-DIR ; : READ READ-DIR ; : CLOSE CLOSE-DIR ; S\" dir\"");
    _ = (try m.heapAllocate(@intCast(m.sizes.heapEnd() - m.heapTop() - 16))).?;
    const top = m.heapTop();
    try m.executeWord(m.lookup("OPEN").?);
    try support.expectStack(m, &.{ 99, 0 });
    m.data_depth = m.data_stack.len;
    m.data_stack[m.data_depth - 3] = map.pad_address;
    m.data_stack[m.data_depth - 2] = 32;
    m.data_stack[m.data_depth - 1] = 99;
    try m.executeBuiltin(.read_dir);
    try std.testing.expectEqual(m.data_stack.len, m.data_depth);
    try std.testing.expectEqual(@as(forth.Cell, 0), try m.peek(0));
    m.data_depth = 0;
    try m.push(map.pad_address);
    try m.push(32);
    try m.push(99);
    try m.executeWord(m.lookup("READ").?);
    m.data_depth = 0;
    try m.push(99);
    try m.executeWord(m.lookup("CLOSE").?);
    try support.expectStack(m, &.{0});
    try std.testing.expectEqual(top, m.heapTop());
}
