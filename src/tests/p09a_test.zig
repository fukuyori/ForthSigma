const std = @import("std");
const forth = @import("../forth.zig");
const support = @import("support.zig");
const map = @import("../core/memory_map.zig");
const registry = @import("../core/exception_registry.zig");

test "P09a assertion levels are compile-time decisions with nested and quoted delimiters" {
    try support.skipWithout(&.{.debug});
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try m.interpretLine("0 ASSERT-LEVEL ! : A 10 ASSERT1( UNKNOWN ) ASSERT0( ( comment \" ) 1+ ASSERT0( TRUE ) S\" )\" 2DROP TRUE ) ; 3 ASSERT-LEVEL ! A");
    try support.expectStack(m, &.{11});
    try m.interpretLine(": BAD ASSERT3( FALSE ) ; ' BAD CATCH");
    try std.testing.expectEqual(@as(map.Cell, -2), try m.pop());
    try std.testing.expectEqual(@as(usize, 0), m.assert_depth);
    try std.testing.expectError(error.ControlMismatch, m.interpretLine(")"));
}

test "P09a catch variants fast throw and suppression restore on success and failure" {
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try m.interpretLine(": BAD -123 THROW ; : INNER ['] BAD CATCH-NOBT ; 7 ' INNER CATCH : F -124 FAST-THROW ; ' F CATCH 0 FAST-THROW NOTHROW");
    try support.expectStack(m, &.{ 7, -123, 0, -124 });
    try std.testing.expectEqual(@as(usize, 0), m.backtrace_suppression);
    try std.testing.expect(!m.throw_nobt);
    try m.interpretLine("SYNONYM CN CATCH-NOBT : NORMAL 8 ; : T ['] NORMAL CN ; T");
    try std.testing.expectEqual(@as(map.Cell, 0), try m.pop());
    try std.testing.expectEqual(@as(map.Cell, 8), try m.pop());
    if (!@import("build_options").debug) return;
    m.step_limit = 20;
    m.resetSteps();
    try std.testing.expectError(error.StepLimit, m.interpretLine(": FOREVER BEGIN AGAIN ; : LIMIT ['] FOREVER CATCH-NOBT ; LIMIT"));
    try std.testing.expectEqual(@as(usize, 0), m.backtrace_suppression);
}

const ErrnoHost = struct {
    value: map.Cell = 2,
    fn write(_: ?*anyopaque, _: []const u8) void {}
    fn get(ctx: ?*anyopaque) map.Cell {
        const self: *@This() = @ptrCast(@alignCast(ctx.?));
        return self.value;
    }
};
test "P09a errno adapters use host errno only on their documented triggers" {
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try m.interpretLine("0 ?ERRNO-THROW 0 ?IOR 1 ?IOR -2 ?IOR");
    try std.testing.expectError(error.HostUnavailable, m.interpretLine("-1 ?IOR"));
    var host = ErrnoHost{};
    m.writer = .{ .context = &host, .write_fn = ErrnoHost.write, .errno_fn = ErrnoHost.get };
    try m.interpretLine(": A -1 ?IOR ; : B 1 ?ERRNO-THROW ; ' A CATCH ' B CATCH");
    try support.expectStack(m, &.{ -514, -514 });
    host.value = 0;
    try m.interpretLine("-1 ?IOR 1 ?ERRNO-THROW");
}

test "P09a warning policy suppresses output and warning errors preserve old definitions" {
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try m.interpretLine("0 WARNINGS ! : X 1 ; : X 2 ; : W TRUE WARNING\" sample\" ; W X");
    try std.testing.expectEqualStrings("", out.written());
    try std.testing.expectEqual(@as(map.Cell, 2), try m.pop());
    try m.interpretLine("-4 WARNINGS ! ' W CATCH");
    try std.testing.expectEqual(@as(map.Cell, -281), try m.pop());
    try std.testing.expectError(error.WarningError, m.interpretLine(": X 3 ;"));
    m.report(error.WarningError);
    try m.interpretLine("X");
    try std.testing.expectEqual(@as(map.Cell, 2), try m.pop());
}

test "P09a exception messages are copied with monotonic codes and invisible records" {
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try m.interpretLine(": PREVIOUS-WORD 9 ; LATEST S\" alpha-custom\" 2DUP EXCEPTION >R 0 FILL R> CONSTANT E LATEST");
    _ = try m.pop();
    _ = try m.pop();
    try registry.validateState(m);
    try m.interpretLine("E");
    const code = try m.pop();
    try std.testing.expect(registry.writeMessage(m, code));
    try std.testing.expectEqualStrings("alpha-custom\n", out.written());
    try m.interpretLine(": MSG DROP S\" group-custom\" ; ' MSG 3 EXCEPTIONS CONSTANT G S\" next\" EXCEPTION G SWAP -");
    try std.testing.expectEqual(@as(map.Cell, 3), try m.pop());
    try m.interpretLine("G 1-");
    try std.testing.expect(registry.writeMessage(m, try m.pop()));
    try m.interpretLine("' MSG 0 EXCEPTIONS S\" zero\" EXCEPTION =");
    try std.testing.expectEqual(@as(map.Cell, -1), try m.pop());
    try std.testing.expectError(error.InvalidNumber, m.interpretLine("' MSG -1 EXCEPTIONS"));
}

test "P09a exception records relocate through restore and both append routes" {
    try support.skipWithout(&.{.image});
    var out = support.Output{};
    const source = try support.createMachine(&out);
    defer support.destroyMachine(source);
    try source.interpretLine("S\" saved-custom\" EXCEPTION CONSTANT E : MSG DROP S\" group-saved\" ; ' MSG 3 EXCEPTIONS CONSTANT G 0 WARNINGS !");
    const image = try std.testing.allocator.alloc(u8, try source.encodedSize());
    defer std.testing.allocator.free(image);
    _ = try source.encodeImage(image);
    for (0..3) |mode| {
        const m = try support.createMachine(&out);
        defer support.destroyMachine(m);
        try m.interpretLine("CREATE PAD-BEFORE 24 ALLOT : BEFORE 8 ;");
        switch (mode) {
            0 => try m.restoreImage(image),
            1 => try m.appendImage(source),
            else => {
                var work: @import("../core/image_append.zig").Workspace = undefined;
                try @import("../core/image_append.zig").append(m, image, &work);
            },
        }
        try registry.validateState(m);
        try m.interpretLine("E G 1-");
        try std.testing.expect(registry.writeMessage(m, try m.pop()));
        try std.testing.expect(registry.writeMessage(m, try m.pop()));
        try std.testing.expectEqual(@as(map.Cell, if (mode == 0) 0 else -1), m.readCellConst(map.warnings_address));
        try m.interpretLine("S\" added\" EXCEPTION G SWAP -");
        try std.testing.expectEqual(@as(map.Cell, 3), try m.pop());
    }
}

test "P09a exception code collisions reject appends before mutation" {
    try support.skipWithout(&.{.image});
    var out = support.Output{};
    const source = try support.createMachine(&out);
    defer support.destroyMachine(source);
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try source.interpretLine("S\" source\" EXCEPTION DROP");
    try m.interpretLine("S\" destination\" EXCEPTION DROP");
    const words = m.word_count;
    const here = m.data_here;
    try std.testing.expectError(error.InvalidImage, m.appendImage(source));
    const image = try std.testing.allocator.alloc(u8, try source.encodedSize());
    defer std.testing.allocator.free(image);
    _ = try source.encodeImage(image);
    var work: @import("../core/image_append.zig").Workspace = undefined;
    try std.testing.expectError(error.InvalidImage, @import("../core/image_append.zig").append(m, image, &work));
    try std.testing.expectEqual(words, m.word_count);
    try std.testing.expectEqual(here, m.data_here);
}

test "P09a malformed exception records are rejected before image restoration" {
    try support.skipWithout(&.{.image});
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try m.interpretLine("S\" custom\" EXCEPTION DROP");
    const record = m.words[m.word_count - 1];
    const image = try std.testing.allocator.alloc(u8, try m.encodedSize());
    defer std.testing.allocator.free(image);
    _ = try m.encodeImage(image);
    const format = @import("../core/image_format.zig");
    const data_offset = format.header_size + @as(usize, m.word_count) * @sizeOf(@import("../core/defs.zig").Word) + @as(usize, m.code_count) * @sizeOf(@import("../core/defs.zig").Op) + m.names_used + @as(usize, @intCast(map.system_end + record.value - map.data_start));
    std.mem.writeInt(map.Cell, image[data_offset + 8 ..][0..8], -1, .little);
    try format.finish(image);
    const words = m.word_count;
    try std.testing.expectError(error.InvalidImage, m.restoreImage(image));
    try std.testing.expectEqual(words, m.word_count);
    try m.writeCell(record.value + 16, 123);
    try std.testing.expectError(error.InvalidImage, m.encodedSize());
}

test "P09a failing exception converters retain the original error and forgetting never reuses codes" {
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try m.interpretLine(": MSG -123 THROW ; ' MSG 2 EXCEPTIONS CONSTANT E E");
    const code = try m.pop();
    m.throw_code = code;
    try std.testing.expect(!registry.writeMessage(m, code));
    try std.testing.expectEqual(code, m.throw_code);
    try std.testing.expectEqual(@as(usize, 0), m.data_depth);
    try std.testing.expectEqual(@as(usize, 0), m.backtrace_suppression);
    const next = m.readCellConst(map.exception_next_address);
    try m.interpretLine("FORGET MSG S\" new\" EXCEPTION");
    try std.testing.expectEqual(next, try m.pop());
    try std.testing.expect(!registry.writeMessage(m, code));
}
