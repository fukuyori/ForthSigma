const std = @import("std");
const forth = @import("../forth.zig");
const support = @import("support.zig");

fn interrupt(_: ?*anyopaque, _: forth.Cell) forth.RuntimeError!forth.FileKeyResult {
    return error.UserInterrupt;
}
fn readyError(_: ?*anyopaque, _: forth.Cell) forth.RuntimeError!forth.FileResult {
    return .{ .ior = -999 };
}

test "P05a key file reads all byte values and distinguishes EOF from the last byte" {
    try support.skipWithout(&.{.files});
    var output = support.Output{};
    const m = try support.createMachine(&output);
    defer support.destroyMachine(m);
    for (0..256) |i| output.files[0].data[i] = @intCast(i);
    output.files[0].len = 256;
    output.files[0].open = true;
    for (0..256) |i| {
        try m.push(forth.first_file_id);
        try m.executeBuiltin(.key_file);
        try std.testing.expectEqual(@as(forth.Cell, @intCast(i)), try m.pop());
        try m.push(forth.first_file_id);
        try m.executeBuiltin(.file_eof_query);
        try std.testing.expectEqual(@as(forth.Cell, 0), try m.pop());
    }
    try m.push(forth.first_file_id);
    try m.executeBuiltin(.key_file);
    try std.testing.expectEqual(@as(forth.Cell, -1), try m.pop());
    try m.push(forth.first_file_id);
    try m.executeBuiltin(.file_eof_query);
    try std.testing.expectEqual(@as(forth.Cell, -1), try m.pop());
    try std.testing.expect(output.files[0].open);
}

test "P05a readiness neither consumes bytes nor sets an EOF indication" {
    try support.skipWithout(&.{.files});
    var output = support.Output{};
    const m = try support.createMachine(&output);
    defer support.destroyMachine(m);
    support.setFakeFile(&output, 0, "AB");
    output.files[0].open = true;
    try m.interpretLine(": READY KEY?-FILE ; : CHAR KEY-FILE ; : ENDED FILE-EOF? ;");
    for (0..2) |i| {
        for (0..2) |_| {
            try m.push(forth.first_file_id);
            try m.executeWord(m.lookup("READY").?);
            try std.testing.expectEqual(@as(forth.Cell, -1), try m.pop());
            try std.testing.expectEqual(i, output.files[0].position);
        }
        try m.push(forth.first_file_id);
        try m.executeWord(m.lookup("CHAR").?);
        try std.testing.expectEqual(@as(forth.Cell, @intCast('A' + i)), try m.pop());
    }
    try m.push(forth.first_file_id);
    try m.executeWord(m.lookup("READY").?);
    try std.testing.expectEqual(@as(forth.Cell, 0), try m.pop());
    try m.push(forth.first_file_id);
    try m.executeWord(m.lookup("ENDED").?);
    try std.testing.expectEqual(@as(forth.Cell, 0), try m.pop());
}

test "P05a EOF follows read file and successful reposition clears it" {
    try support.skipWithout(&.{.files});
    var output = support.Output{};
    const m = try support.createMachine(&output);
    defer support.destroyMachine(m);
    support.setFakeFile(&output, 0, "AB");
    output.files[0].open = true;
    try m.interpretLine("CREATE BUF 8 ALLOT");
    const buffer = m.words[m.lookup("BUF").?].value;
    try m.push(buffer);
    try m.push(8);
    try m.push(forth.first_file_id);
    try m.executeBuiltin(.read_file);
    try support.expectStack(m, &.{ 2, 0 });
    m.data_depth = 0;
    try m.push(forth.first_file_id);
    try m.executeBuiltin(.file_eof_query);
    try std.testing.expectEqual(@as(forth.Cell, -1), try m.pop());
    try std.testing.expectEqual(@as(forth.Cell, 0), support.fakeReposition(&output, forth.first_file_id, 0));
    try m.push(forth.first_file_id);
    try m.executeBuiltin(.file_eof_query);
    try std.testing.expectEqual(@as(forth.Cell, 0), try m.pop());
}

test "P05a missing hooks host errors and interrupt preserve the handle operand" {
    try support.skipWithout(&.{.files});
    var output = support.Output{};
    const m = try support.createMachine(&output);
    defer support.destroyMachine(m);
    var ops = support.fake_file_ops;
    m.writer.file_ops = &ops;
    ops.key = null;
    ops.ready = null;
    ops.eof = null;
    try m.push(forth.first_file_id);
    inline for (.{ .key_file, .key_query_file, .file_eof_query }) |word| {
        try std.testing.expectError(error.FileUnavailable, m.executeBuiltin(word));
        try support.expectStack(m, &.{forth.first_file_id});
    }
    ops.key = interrupt;
    ops.ready = readyError;
    try std.testing.expectError(error.UserInterrupt, m.executeBuiltin(.key_file));
    try std.testing.expectError(error.Thrown, m.executeBuiltin(.key_query_file));
    try std.testing.expectEqual(@as(forth.Cell, -999), m.throw_code);
    try support.expectStack(m, &.{forth.first_file_id});
}

test "P05a key helpers reject invalid handles and preflight input depth" {
    try support.skipWithout(&.{.files});
    var output = support.Output{};
    const m = try support.createMachine(&output);
    defer support.destroyMachine(m);
    inline for (.{ .key_file, .key_query_file, .file_eof_query }) |word| {
        try std.testing.expectError(error.StackUnderflow, m.executeBuiltin(word));
        try m.push(-1);
        try std.testing.expectError(error.Thrown, m.executeBuiltin(word));
        try support.expectStack(m, &.{-1});
        m.data_depth = 0;
    }
    support.setFakeFile(&output, 0, "A");
    output.files[0].open = true;
    m.data_depth = m.data_stack.len;
    m.data_stack[m.data_depth - 1] = forth.first_file_id;
    try m.executeBuiltin(.key_file);
    try std.testing.expectEqual(m.data_stack.len, m.data_depth);
    try std.testing.expectEqual(@as(forth.Cell, 'A'), m.data_stack[m.data_depth - 1]);
}
