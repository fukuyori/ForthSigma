const std = @import("std");
const support = @import("support.zig");
const forth = @import("../forth.zig");
const map = @import("../core/memory_map.zig");

fn open(context: ?*anyopaque, command: []const u8, access: forth.FileAccess) forth.FileResult {
    return support.fakeOpen(context, command, access, access == .write_only);
}
fn close(context: ?*anyopaque, id: forth.Cell) forth.FileResult {
    const ior = support.fakeClose(context, id);
    return .{ .value = @bitCast(@as(forth.Cell, if (ior == 0) 768 else -1)), .ior = ior };
}
fn setup(m: *forth.State, ops: *forth.FileOps) void {
    ops.* = support.fake_file_ops;
    ops.open_pipe = open;
    ops.close_pipe = close;
    m.writer.file_ops = ops;
}

test "P06b read pipes integrate with byte input and return close status without changing system status" {
    try support.skipWithout(&.{.files});
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    var ops: forth.FileOps = undefined;
    setup(m, &ops);
    support.setFakeFile(&out, 0, "ABC");
    m.system_status = 99;
    try m.interpretLine("S\" a.txt\" R/O BIN OPEN-PIPE THROW DUP KEY-FILE SWAP CLOSE-PIPE $?");
    try support.expectStack(m, &.{ 65, 768, 0, 99 });
    try std.testing.expect(!out.files[0].open);
}

test "P06b write pipes integrate with output selection and EPIPE constant" {
    try support.skipWithout(&.{.files});
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    var ops: forth.FileOps = undefined;
    setup(m, &ops);
    try m.interpretLine("S\" a.txt\" W/O OPEN-PIPE THROW CONSTANT P : TXT S\" pipe\" TYPE ; ' TXT P OUTFILE-EXECUTE P CLOSE-PIPE BROKEN-PIPE-ERROR");
    try support.expectStack(m, &.{ 768, 0, -544 });
    try std.testing.expectEqualStrings("pipe", out.files[0].data[0..out.files[0].len]);
    try std.testing.expect(!out.files[0].open);
}

test "P06b pipe invalid modes open errors and missing capabilities have defined stack effects" {
    try support.skipWithout(&.{.files});
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    var ops: forth.FileOps = undefined;
    setup(m, &ops);
    try m.interpretLine("S\" a.txt\" R/W OPEN-PIPE S\" missing\" R/O OPEN-PIPE");
    try support.expectStack(m, &.{ 0, map.errnoIor(map.errno_invalid), 0, map.errnoIor(2) });
    try std.testing.expect(!out.files[0].open);
    m.data_depth = 0;
    ops.open_pipe = null;
    try m.interpretLine("S\" a.txt\" R/O");
    const depth = m.data_depth;
    try std.testing.expectError(error.FileUnavailable, m.executeBuiltin(.open_pipe));
    try std.testing.expectEqual(depth, m.data_depth);
    ops.open_pipe = open;
    ops.close_pipe = null;
    try std.testing.expectError(error.FileUnavailable, m.executeBuiltin(.open_pipe));
    try std.testing.expectEqual(depth, m.data_depth);
    try std.testing.expect(!out.files[0].open);
}

test "P06b CLOSE-PIPE preflights stack capacity before releasing a handle and propagates close errors" {
    try support.skipWithout(&.{.files});
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    var ops: forth.FileOps = undefined;
    setup(m, &ops);
    support.setFakeFile(&out, 0, "A");
    try m.interpretLine("S\" a.txt\" R/O OPEN-PIPE THROW");
    const id = try m.pop();
    m.data_depth = m.data_stack.len;
    m.data_stack[m.data_depth - 1] = id;
    try std.testing.expectError(error.StackOverflow, m.executeBuiltin(.close_pipe));
    try std.testing.expect(out.files[0].open);
    m.data_depth = 0;
    out.close_fails = true;
    try m.push(id);
    try m.executeBuiltin(.close_pipe);
    try support.expectStack(m, &.{ -1, map.errnoIor(5) });
    try std.testing.expect(!out.files[0].open);
}
