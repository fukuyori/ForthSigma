const std = @import("std");
const support = @import("support.zig");
const forth = @import("../forth.zig");
const map = @import("../core/memory_map.zig");

fn open(context: ?*anyopaque, command: []const u8, access: forth.FileAccess) forth.FileResult {
    return support.fakeOpen(context, command, access, false);
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
fn bytes(m: *forth.State) []const u8 {
    const result = m.sh_get_result.?;
    return m.memory[@intCast(result.address)..][0..result.length];
}

test "P06b SH-GET borrows binary and empty output and stores close status" {
    try support.skipWithout(&.{.files});
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    var ops: forth.FileOps = undefined;
    setup(m, &ops);
    support.setFakeFile(&out, 0, "A\x00日本語\n");
    try m.interpretLine("S\" a.txt\" SH-GET 2DROP $?");
    try support.expectStack(m, &.{768});
    try std.testing.expectEqualStrings("A\x00日本語\n", bytes(m));
    try std.testing.expect(!out.files[0].open);
    support.setFakeFile(&out, 1, "");
    try m.interpretLine("S\" b.txt\" SH-GET");
    try std.testing.expectEqual(@as(usize, 0), m.sh_get_result.?.length);
    try std.testing.expect((try m.findBlock(m.sh_get_result.?.address)) != null);
    try std.testing.expect(!out.files[1].open);
}

test "P06b SH-GET reuses previous storage and accepts its previous result as a command" {
    try support.skipWithout(&.{.files});
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    var ops: forth.FileOps = undefined;
    setup(m, &ops);
    support.setFakeFile(&out, 0, "b.txt");
    support.setFakeFile(&out, 1, "result");
    try m.interpretLine(": GET-AGAIN S\" b.txt\" SH-GET 2DROP ; S\" a.txt\" SH-GET SH-GET 2DROP");
    try std.testing.expectEqualStrings("result", bytes(m));
    const top = m.heapTop();
    for (0..20) |_| try m.interpretLine("GET-AGAIN");
    try std.testing.expectEqual(top, m.heapTop());
    try std.testing.expect(!out.files[0].open and !out.files[1].open);
}

fn failedRead(_: ?*anyopaque, _: forth.Cell, _: []u8) forth.FileResult {
    return .{ .ior = -999 };
}

test "P06b SH-GET read close and open failures release output and owned pipes and preserve status" {
    try support.skipWithout(&.{.files});
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    var ops: forth.FileOps = undefined;
    setup(m, &ops);
    support.setFakeFile(&out, 0, "data");
    try m.interpretLine(": GET-OUTPUT S\" a.txt\" SH-GET ;");
    const baseline = m.heapTop();
    try m.interpretLine("GET-OUTPUT 2DROP");
    m.system_status = 99;
    ops.read = failedRead;
    try m.interpretLine("' GET-OUTPUT CATCH");
    try support.expectStack(m, &.{-999});
    try std.testing.expect(m.sh_get_result == null and !out.files[0].open);
    try std.testing.expectEqual(baseline, m.heapTop());
    m.data_depth = 0;
    ops.read = support.fakeRead;
    out.close_fails = true;
    try m.interpretLine("' GET-OUTPUT CATCH");
    try support.expectStack(m, &.{map.errnoIor(5)});
    try std.testing.expect(m.sh_get_result == null and !out.files[0].open);
    try std.testing.expectEqual(baseline, m.heapTop());
    try std.testing.expectEqual(@as(forth.Cell, 99), m.system_status);
    out.close_fails = false;
    m.data_depth = 0;
    try m.interpretLine("GET-OUTPUT 2DROP");
    try m.interpretLine(": FAILED-OPEN S\" missing\" SH-GET ;");
    try std.testing.expectError(error.Thrown, m.interpretLine("FAILED-OPEN"));
    try std.testing.expect(m.sh_get_result == null);
    try std.testing.expectEqual(baseline, m.heapTop());
}

test "P06b SH-GET image restore invalidates runtime borrow while both append routes preserve it" {
    try support.skipWithout(&.{.files});
    const append = @import("../core/image_append.zig");
    var out = support.Output{};
    const source = try support.createMachine(&out);
    defer support.destroyMachine(source);
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    var ops: forth.FileOps = undefined;
    setup(m, &ops);
    source.writer.file_ops = &ops;
    support.setFakeFile(&out, 0, "target");
    support.setFakeFile(&out, 1, "source");
    try source.interpretLine("S\" b.txt\" SH-GET 2DROP : IMPORTED 42 ;");
    const image = try std.testing.allocator.alloc(u8, try source.encodedSize());
    defer std.testing.allocator.free(image);
    _ = try source.encodeImage(image);
    try m.interpretLine("S\" a.txt\" SH-GET 2DROP");
    const before = m.sh_get_result.?;
    const top = m.heapTop();
    try m.appendImage(source);
    var work: append.Workspace = undefined;
    try append.append(m, image, &work);
    try std.testing.expectEqual(before.address, m.sh_get_result.?.address);
    try std.testing.expectEqual(top, m.heapTop());
    try std.testing.expectEqualStrings("target", bytes(m));
    image[image.len - 1] ^= 1;
    try std.testing.expectError(error.InvalidImage, m.restoreImage(image));
    try std.testing.expectEqual(before.address, m.sh_get_result.?.address);
    image[image.len - 1] ^= 1;
    try m.restoreImage(image);
    try std.testing.expect(m.sh_get_result == null);
    try m.interpretLine("S\" a.txt\" SH-GET 2DROP");
    try std.testing.expectEqualStrings("target", bytes(m));
}

test "P06b SH-GET preflight preserves previous output and supports a full data stack" {
    try support.skipWithout(&.{.files});
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    var ops: forth.FileOps = undefined;
    setup(m, &ops);
    support.setFakeFile(&out, 0, "data");
    try m.interpretLine("S\" a.txt\" SH-GET 2DROP S\" a.txt\"");
    const previous = m.sh_get_result.?;
    ops.close_pipe = null;
    try std.testing.expectError(error.FileUnavailable, m.executeBuiltin(.sh_get));
    try std.testing.expectEqual(previous.address, m.sh_get_result.?.address);
    try std.testing.expect(!out.files[0].open);
    ops.close_pipe = close;
    const addr = try m.peek(1);
    const length = try m.peek(0);
    m.data_depth = m.data_stack.len;
    m.data_stack[m.data_depth - 2] = addr;
    m.data_stack[m.data_depth - 1] = length;
    try m.executeBuiltin(.sh_get);
    try std.testing.expectEqual(m.data_stack.len, m.data_depth);
    try std.testing.expectEqualStrings("data", bytes(m));
}

test "P06b SH-GET allocation and work-limit failures close the pipe and release partial output" {
    try support.skipWithout(&.{.files});
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    var ops: forth.FileOps = undefined;
    setup(m, &ops);
    @memset(out.files[0].data[0..2048], 'x');
    out.files[0].len = 2048;
    out.files[0].exists = true;
    @memcpy(m.memory[@intCast(map.string_buffer_base)..][0..5], "a.txt");
    m.system_status = 99;
    if (@import("build_options").debug) {
        const baseline = m.heapTop();
        try m.push(map.string_buffer_base);
        try m.push(5);
        m.step_limit = 1;
        m.steps_left = 1;
        try std.testing.expectError(error.StepLimit, m.executeBuiltin(.sh_get));
        try std.testing.expectEqual(baseline, m.heapTop());
        try std.testing.expect(m.sh_get_result == null and !out.files[0].open);
        m.step_limit = 0;
        m.data_depth = 0;
    }
    _ = (try m.heapAllocate(@intCast(m.sizes.heapEnd() - m.heapTop() - 16))).?;
    const baseline = m.heapTop();
    try m.push(map.string_buffer_base);
    try m.push(5);
    try std.testing.expectError(error.Thrown, m.executeBuiltin(.sh_get));
    try std.testing.expectEqual(baseline, m.heapTop());
    try std.testing.expect(m.sh_get_result == null and !out.files[0].open);
    try std.testing.expectEqual(@as(forth.Cell, 99), m.system_status);
}
