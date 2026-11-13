const std = @import("std");
const forth = @import("../forth.zig");
const support = @import("support.zig");
const skip = "\\\\\\";

fn badSize(_: ?*anyopaque, _: forth.Cell) forth.FileResult {
    return .{ .ior = -999 };
}
fn badSeek(_: ?*anyopaque, _: forth.Cell, _: forth.UCell) forth.Cell {
    return -888;
}
fn badRead(_: ?*anyopaque, _: forth.Cell, _: []u8) forth.FileResult {
    return .{ .ior = -777 };
}

test "P05a encoded creation modes reach the host while default creation and existing modes remain intact" {
    try support.skipWithout(&.{.files});
    var output = support.Output{};
    const m = try support.createMachine(&output);
    defer support.destroyMachine(m);
    try m.interpretLine(": MODE +FMODE ;");
    for ([_]u16{ 0, 0o600, 0o640, 0o755, 0o666 }) |permissions| {
        output.files[0] = .{};
        var text: [150]u8 = undefined;
        try m.interpretLine(try std.fmt.bufPrint(&text, "S\" a.txt\" W/O {d} MODE CREATE-FILE THROW CLOSE-FILE THROW", .{permissions}));
        try std.testing.expectEqual(permissions, output.files[0].permissions);
        try std.testing.expect(!output.files[0].open);
    }
    output.files[0].permissions = 0o555;
    try m.interpretLine("S\" a.txt\" W/O 384 +FMODE CREATE-FILE THROW CLOSE-FILE THROW");
    try std.testing.expectEqual(@as(u16, 0o555), output.files[0].permissions);
    try std.testing.expectEqual(@as(usize, 0), output.files[0].len);
}

test "P05a missing permission hook rejects explicit creation without truncation but allows OPEN-FILE" {
    try support.skipWithout(&.{.files});
    var output = support.Output{};
    const m = try support.createMachine(&output);
    defer support.destroyMachine(m);
    support.setFakeFile(&output, 0, "kept");
    var ops = support.fake_file_ops;
    ops.create_mode = null;
    m.writer.file_ops = &ops;
    try m.interpretLine("S\" a.txt\" W/O 384 +FMODE CREATE-FILE SWAP DROP");
    try std.testing.expect((try m.pop()) != 0);
    try std.testing.expectEqualStrings("kept", output.files[0].data[0..output.files[0].len]);
    try std.testing.expect(!output.files[0].open);
    try m.interpretLine("S\" a.txt\" R/O 384 +FMODE OPEN-FILE THROW CLOSE-FILE THROW");
    try std.testing.expectEqualStrings("kept", output.files[0].data[0..output.files[0].len]);
    try m.push(2);
    try std.testing.expectError(error.StackUnderflow, m.executeBuiltin(.plus_fmode));
    try support.expectStack(m, &.{2});
}

test "P05a included listing follows registration order deduplicates and honors MARKER" {
    try support.skipWithout(&.{.files});
    var output = support.Output{};
    const m = try support.createMachine(&output);
    defer support.destroyMachine(m);
    support.setFakeFile(&output, 0, "1 DROP\n");
    support.setFakeFile(&output, 1, "2 DROP\n");
    support.setFakeFile(&output, 2, "3 DROP\n");
    support.setFakeFile(&output, 3, "NOT-A-DEFINED-WORD\n");
    try m.interpretLine(".INCLUDED INCLUDE a.txt INCLUDE a.txt INCLUDE b.txt MARKER BACK INCLUDE c.txt BACK .INCLUDED");
    try std.testing.expectEqualStrings("\na.txt\nb.txt", output.written());
    try std.testing.expectError(error.UnknownWord, m.includeFile("d.txt"));
    output.len = 0;
    try m.interpretLine(".INCLUDED");
    try std.testing.expectEqualStrings("\na.txt\nb.txt\nd.txt", output.written());
    try support.expectStack(m, &.{});
}

test "P05a included listing retains load flags through append and restore" {
    try support.skipWithout(&.{.files});
    var output = support.Output{};
    support.setFakeFile(&output, 0, "1 DROP\n");
    support.setFakeFile(&output, 1, "2 DROP\n");
    const source = try support.createMachine(&output);
    defer support.destroyMachine(source);
    try source.interpretLine("INCLUDE a.txt");
    const target = try support.createMachine(&output);
    defer support.destroyMachine(target);
    try target.interpretLine("INCLUDE b.txt");
    try target.appendImage(source);
    const bytes = try std.testing.allocator.alloc(u8, try target.encodedSize());
    defer std.testing.allocator.free(bytes);
    _ = try target.encodeImage(bytes);
    try target.restoreImage(bytes);
    output.len = 0;
    try target.interpretLine(".INCLUDED");
    try std.testing.expectEqualStrings("\nb.txt\na.txt", output.written());
}

test "P05a triple backslash is immediate and a safe no-op outside a source file" {
    try support.skipWithout(&.{.files});
    var output = support.Output{};
    const m = try support.createMachine(&output);
    defer support.destroyMachine(m);
    try std.testing.expect(m.words[m.lookup(skip).?].immediate);
    try m.interpretLine("11 " ++ skip ++ " 22 S\" 33 " ++ skip ++ " 44\" EVALUATE 55 : K 66 " ++ skip ++ " 77 ; K");
    try support.expectStack(m, &.{ 11, 22, 33, 44, 55, 66, 77 });
    m.source_kind = .block;
    m.writer.file_ops = null;
    try m.executeBuiltin(.triple_backslash);
    try support.expectStack(m, &.{ 11, 22, 33, 44, 55, 66, 77 });
}

test "P05a triple backslash skips only the nested file closes it and resumes its caller" {
    try support.skipWithout(&.{.files});
    var output = support.Output{};
    const m = try support.createMachine(&output);
    defer support.destroyMachine(m);
    support.setFakeFile(&output, 0, "1 INCLUDE b.txt 2\n3\n");
    support.setFakeFile(&output, 1, "4 " ++ skip ++ " 999\nNOT-A-WORD\n");
    try m.interpretLine("INCLUDE a.txt 5");
    try support.expectStack(m, &.{ 1, 4, 2, 3, 5 });
    try std.testing.expectEqual(@as(usize, 0), m.include_depth);
    try std.testing.expect(!m.halted);
    try std.testing.expect(!output.files[0].open and !output.files[1].open);
    try std.testing.expect(output.files[1].eof);
}

test "P05a evaluated terminator leaves the containing file alive and embedded files can terminate" {
    try support.skipWithout(&.{.files});
    var output = support.Output{};
    const m = try support.createMachine(&output);
    defer support.destroyMachine(m);
    support.setFakeFile(&output, 0, "S\" 7 " ++ skip ++ " 8\" EVALUATE 9\n10\n");
    try m.interpretLine("INCLUDE a.txt");
    try support.expectStack(m, &.{ 7, 8, 9, 10 });
    m.writer.file_ops = null;
    try m.includeEmbedded("embedded-test.fs", "11 " ++ skip ++ " 99\nNOT-A-WORD\n");
    try support.expectStack(m, &.{ 7, 8, 9, 10, 11 });
    try std.testing.expectEqual(@as(usize, 0), m.include_depth);
}

test "P05a postponed terminator executes in the caller source context" {
    try support.skipWithout(&.{.files});
    var output = support.Output{};
    const m = try support.createMachine(&output);
    defer support.destroyMachine(m);
    try m.interpretLine(": SKIP-FILE POSTPONE " ++ skip ++ " ;");
    support.setFakeFile(&output, 0, "1 SKIP-FILE 999\nNOT-A-WORD\n");
    try m.interpretLine("INCLUDE a.txt 2");
    try support.expectStack(m, &.{ 1, 2 });
}

test "P05a skip failures propagate and close the included file on all paths" {
    try support.skipWithout(&.{.files});
    for (0..3) |stage| {
        var output = support.Output{};
        const m = try support.createMachine(&output);
        defer support.destroyMachine(m);
        support.setFakeFile(&output, 0, "11 " ++ skip ++ " 22\n33\n");
        var ops = support.fake_file_ops;
        if (stage == 0) ops.size = badSize else if (stage == 1) ops.reposition = badSeek else ops.read = badRead;
        m.writer.file_ops = &ops;
        try std.testing.expectError(error.Thrown, m.interpretLine("INCLUDE a.txt"));
        try std.testing.expectEqual(([_]forth.Cell{ -999, -888, -777 })[stage], m.throw_code);
        try std.testing.expect(!output.files[0].open);
        try std.testing.expectEqual(@as(usize, 0), m.include_depth);
    }
}
