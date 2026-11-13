const std = @import("std");
const forth = @import("../forth.zig");
const support = @import("support.zig");
const registry = @import("../core/address_registry.zig");

fn shortRead(context: ?*anyopaque, id: forth.Cell, bytes: []u8) forth.FileResult {
    return support.fakeRead(context, id, bytes[0..@min(3, bytes.len)]);
}
fn failingRead(context: ?*anyopaque, id: forth.Cell, bytes: []u8) forth.FileResult {
    const file = support.fakeFile(context, id) orelse return .{ .ior = -999 };
    if (file.position >= 3) return .{ .ior = -999 };
    return shortRead(context, id, bytes);
}
fn unavailable(_: ?*anyopaque, _: forth.Cell) forth.FileResult {
    return .{ .ior = -999 };
}

test "P05a EMIT-FILE truncates to one byte and returns host write errors" {
    try support.skipWithout(&.{.files});
    var output = support.Output{};
    const m = try support.createMachine(&output);
    defer support.destroyMachine(m);
    output.files[0].open = true;
    for ([_]forth.Cell{ -1, 0, 65, 256 }) |byte| {
        try m.push(byte);
        try m.push(forth.first_file_id);
        try m.executeBuiltin(.emit_file);
        try std.testing.expectEqual(@as(forth.Cell, 0), try m.pop());
    }
    try std.testing.expectEqualSlices(u8, &.{ 255, 0, 65, 0 }, output.files[0].data[0..4]);
    output.write_fails_at = output.file_writes + 1;
    try m.push(66);
    try m.push(forth.first_file_id);
    try m.executeBuiltin(.emit_file);
    try std.testing.expectEqual(forth.errnoIor(28), try m.pop());
    try std.testing.expectEqual(@as(usize, 4), output.files[0].position);
    try m.push(66);
    try m.push(-1);
    try m.executeBuiltin(.emit_file);
    try std.testing.expect((try m.pop()) != 0);
}

test "P05a SLURP-FID reads binary data from the current position and keeps the file open" {
    try support.skipWithout(&.{.files});
    var output = support.Output{};
    const m = try support.createMachine(&output);
    defer support.destroyMachine(m);
    for (output.files[0].data[0..2500], 0..) |*byte, i| byte.* = @truncate(i);
    output.files[0].len = 2500;
    output.files[0].position = 17;
    output.files[0].open = true;
    try m.push(forth.first_file_id);
    try m.executeBuiltin(.slurp_fid);
    try std.testing.expectEqual(@as(forth.Cell, 2483), try m.pop());
    const address = try m.pop();
    try std.testing.expectEqualSlices(u8, output.files[0].data[17..2500], m.memory[@intCast(address)..][0..2483]);
    try std.testing.expectEqual(@as(usize, 2500), output.files[0].position);
    try std.testing.expect(output.files[0].open);
    try std.testing.expect(try m.heapFree(address));
    try registry.validate(m);
}

test "P05a stream slurp continues after short reads without size or seek support" {
    try support.skipWithout(&.{.files});
    var output = support.Output{};
    const m = try support.createMachine(&output);
    defer support.destroyMachine(m);
    support.setFakeFile(&output, 0, "abcdefgh");
    output.files[0].open = true;
    var ops = support.fake_file_ops;
    ops.read = shortRead;
    ops.size = unavailable;
    ops.position = unavailable;
    m.writer.file_ops = &ops;
    try m.push(forth.first_file_id);
    try m.executeBuiltin(.slurp_fid);
    try std.testing.expectEqual(@as(forth.Cell, 8), try m.pop());
    const address = try m.pop();
    try std.testing.expectEqualStrings("abcdefgh", m.memory[@intCast(address)..][0..8]);
    try std.testing.expect(try m.heapFree(address));
    try m.push(forth.first_file_id);
    try m.executeBuiltin(.slurp_fid);
    try std.testing.expectEqual(@as(forth.Cell, 0), try m.pop());
    const empty = try m.pop();
    try std.testing.expect(empty != 0);
    try std.testing.expect(try m.heapFree(empty));
}

test "P05a stream read errors free partial data and preserve the caller handle" {
    try support.skipWithout(&.{.files});
    var output = support.Output{};
    const m = try support.createMachine(&output);
    defer support.destroyMachine(m);
    support.setFakeFile(&output, 0, "abcdefgh");
    output.files[0].open = true;
    var ops = support.fake_file_ops;
    ops.read = failingRead;
    m.writer.file_ops = &ops;
    const top = m.heapTop();
    try m.push(forth.first_file_id);
    try std.testing.expectError(error.Thrown, m.executeBuiltin(.slurp_fid));
    try std.testing.expectEqual(@as(forth.Cell, -999), m.throw_code);
    try std.testing.expectEqual(top, m.heapTop());
    try support.expectStack(m, &.{forth.first_file_id});
    try std.testing.expect(output.files[0].open);
    try std.testing.expectEqual(@as(usize, 3), output.files[0].position);
    try registry.validate(m);
}

test "P05a stream heap exhaustion leaves no partial allocation or closed file" {
    try support.skipWithout(&.{.files});
    var output = support.Output{};
    const m = try support.createMachine(&output);
    defer support.destroyMachine(m);
    support.setFakeFile(&output, 0, "abcdefgh");
    output.files[0].open = true;
    _ = (try m.heapAllocate(@intCast(m.sizes.heapEnd() - m.heapTop() - 16))).?;
    const top = m.heapTop();
    try m.push(forth.first_file_id);
    try std.testing.expectError(error.Thrown, m.executeBuiltin(.slurp_fid));
    try std.testing.expectEqual(top, m.heapTop());
    try support.expectStack(m, &.{forth.first_file_id});
    try std.testing.expect(output.files[0].open);
    try registry.validate(m);
}

test "P05a file helpers check data-stack room before host I/O" {
    try support.skipWithout(&.{.files});
    var output = support.Output{};
    const m = try support.createMachine(&output);
    defer support.destroyMachine(m);
    try std.testing.expectError(error.StackUnderflow, m.executeBuiltin(.emit_file));
    try std.testing.expectError(error.StackUnderflow, m.executeBuiltin(.slurp_fid));
    output.files[0].open = true;
    m.data_depth = m.data_stack.len;
    m.data_stack[m.data_depth - 1] = forth.first_file_id;
    try std.testing.expectError(error.StackOverflow, m.executeBuiltin(.slurp_fid));
    try std.testing.expectEqual(@as(usize, 0), output.files[0].position);
}

test "P05a native slurp checks the work budget and frees accumulated bytes" {
    try support.skipWithout(&.{ .files, .debug });
    var output = support.Output{};
    const m = try support.createMachine(&output);
    defer support.destroyMachine(m);
    support.setFakeFile(&output, 0, "abcdefgh");
    output.files[0].open = true;
    var ops = support.fake_file_ops;
    ops.read = shortRead;
    m.writer.file_ops = &ops;
    m.step_limit = 1;
    m.steps_left = 1;
    const top = m.heapTop();
    try m.push(forth.first_file_id);
    try std.testing.expectError(error.StepLimit, m.executeBuiltin(.slurp_fid));
    try std.testing.expectEqual(top, m.heapTop());
    try std.testing.expect(output.files[0].open);
    try registry.validate(m);
}
