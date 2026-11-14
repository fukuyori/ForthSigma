//! Task698: SHOW must not rewind over output outside the ordinary TYPE/EMIT path.
const std = @import("std");
const forth = @import("../forth.zig");
const support = @import("support.zig");
fn frame(m: *forth.State, out: *support.Output, renderer: []const u8, rewind: bool) !void {
    out.len = 0;
    try m.interpretLine(renderer);
    try std.testing.expectEqual(rewind, std.mem.indexOf(u8, out.written(), "\r\x1b[") != null);
}

test "698 direct STDOUT file writes separate terminal frames while private output does not" {
    try support.skipWithout(&.{ .files, .graphics });
    for ([_][]const u8{ "GFX-SHOW-BLOCKS", "GFX-SHOW-SIXEL" }) |renderer| {
        var out = support.Output{ .terminal_columns = 80, .terminal_rows = 24 };
        const m = try support.createMachine(&out);
        defer support.destroyMachine(m);
        try m.interpretLine("REQUIRE-GRAPHICS ALSO GRAPHICS 8 4 GFX-INIT");
        try frame(m, &out, renderer, false);
        try frame(m, &out, renderer, true);
        const mark = m.output_count;
        try m.interpretLine("S\" X\" STDOUT WRITE-FILE THROW");
        try std.testing.expectEqual(mark + 1, m.output_count);
        try frame(m, &out, renderer, false);
        try m.interpretLine("S\" \" STDOUT WRITE-LINE THROW");
        try frame(m, &out, renderer, false);
        try m.interpretLine("S\" \" STDOUT WRITE-FILE THROW");
        try frame(m, &out, renderer, true);
        try m.interpretLine("S\" a.txt\" W/O CREATE-FILE THROW CONSTANT PRIVATE-OUT S\" X\" PRIVATE-OUT WRITE-FILE THROW : PRIVATE-TEXT 65 EMIT ; ' PRIVATE-TEXT >STRING-EXECUTE DROP FREE THROW ' PRIVATE-TEXT PRIVATE-OUT OUTFILE-EXECUTE");
        try frame(m, &out, renderer, true);
    }
}
const Partial = struct {
    fn write(ctx: ?*anyopaque, file: forth.Cell, bytes: []const u8) forth.Cell {
        if (file != forth.stdout_fileid) return support.fakeWrite(ctx, file, bytes);
        if (bytes.len != 0) _ = support.fakeWrite(ctx, file, bytes[0..1]);
        return forth.errnoIor(5);
    }
};
test "698 failed direct STDOUT writes may have emitted a prefix" {
    try support.skipWithout(&.{ .files, .graphics });
    var out = support.Output{ .terminal_columns = 80, .terminal_rows = 24 };
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    var ops = support.fake_file_ops;
    ops.write = Partial.write;
    m.writer.file_ops = &ops;
    try m.interpretLine("REQUIRE-GRAPHICS ALSO GRAPHICS 8 4 GFX-INIT");
    try frame(m, &out, "GFX-SHOW-BLOCKS", false);
    try m.interpretLine("S\" XY\" STDOUT WRITE-LINE");
    try std.testing.expectEqual(forth.errnoIor(5), try m.pop());
    try std.testing.expectEqualStrings("X", out.stdout_bytes[0..out.stdout_len]);
    try frame(m, &out, "GFX-SHOW-BLOCKS", false);
}

test "698 external SYSTEM and captured SH invalidate terminal reuse on success and failure" {
    try support.skipWithout(&.{.graphics});
    var out = support.Output{ .terminal_columns = 80, .terminal_rows = 24 };
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try m.interpretLine("REQUIRE-GRAPHICS ALSO GRAPHICS 8 4 GFX-INIT");
    for ([_][]const u8{ "S\" command\" SYSTEM", "S\" exit 3\" SYSTEM" }) |code| {
        try frame(m, &out, "GFX-SHOW-BLOCKS", false);
        try m.interpretLine(code);
        try frame(m, &out, "GFX-SHOW-BLOCKS", false);
        // A later frame may again reuse its own location.
        try frame(m, &out, "GFX-SHOW-BLOCKS", true);
        m.write("reset");
    }
    try std.testing.expectEqual(@as(forth.Cell, 768), m.system_status);
    try frame(m, &out, "GFX-SHOW-BLOCKS", false);
    try std.testing.expectError(error.HostFailed, m.interpretLine("S\" fail\" SYSTEM"));
    try frame(m, &out, "GFX-SHOW-BLOCKS", false);
    m.writer.system_fn = null;
    const mark = m.output_count;
    try std.testing.expectError(error.HostUnavailable, m.interpretLine("S\" command\" SYSTEM"));
    try std.testing.expectEqual(mark, m.output_count);
    try frame(m, &out, "GFX-SHOW-BLOCKS", true);
    m.writer.system_fn = support.Output.system;
    try m.interpretLine(": CAPTURE-SHELL S\" SH command\" EVALUATE ; ' CAPTURE-SHELL >STRING-EXECUTE DROP FREE THROW");
    try frame(m, &out, "GFX-SHOW-BLOCKS", false);
}

const Editor = struct {
    fn run(_: ?*anyopaque, _: @import("../core/host_interface.zig").EditorRequest) forth.RuntimeError!void {}
};
test "698 editor host output separates terminal frames without requiring actual launch" {
    try support.skipWithout(&.{ .tools, .graphics });
    var out = support.Output{ .terminal_columns = 80, .terminal_rows = 24 };
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try m.interpretLine("REQUIRE-GRAPHICS ALSO GRAPHICS 8 4 GFX-INIT");
    try frame(m, &out, "GFX-SHOW-BLOCKS", false);
    const path = "/tmp/editor.fs";
    m.source_navigation = .{ .length = path.len, .generation = m.image_generation };
    @memcpy(m.source_navigation.path[0..path.len], path);
    m.writer.editor_fn = Editor.run;
    try m.interpretLine("G");
    try frame(m, &out, "GFX-SHOW-BLOCKS", false);
}
