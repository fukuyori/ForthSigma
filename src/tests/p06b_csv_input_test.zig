const std = @import("std");
const support = @import("support.zig");
const forth = @import("../forth.zig");
const map = @import("../core/memory_map.zig");

const define_field = ": CSV-FIELD . . TYPE 124 EMIT ;";

test "P06b CSV decodes quoted multiline fields logical rows and omitted trailing empties" {
    try support.skipWithout(&.{.files});
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    support.setFakeFile(&out, 0, "\"a\nb\",\"c\"\"d\"\nx,\n,,\n\n");
    try m.interpretLine(define_field);
    try m.interpretLine("S\" a.txt\" ' CSV-FIELD READ-CSV 123");
    try std.testing.expectEqualStrings("1 0 a\nb|1 1 c\"d|2 0 x|3 0 |3 1 |4 0 |", out.written());
    try support.expectStack(m, &.{123});
    try std.testing.expect(!out.files[0].open);
    try std.testing.expect(m.findSourceEntry("a.txt") != null);
    try std.testing.expect(m.findSourceFile("a.txt") == null);
    try std.testing.expectEqual(@as(usize, 0), m.include_depth);
}

test "P06b CSV callbacks see file source and THROW closes file frees field and restores parser" {
    try support.skipWithout(&.{.files});
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    support.setFakeFile(&out, 0, "data,more\n");
    try m.interpretLine(": CSV-BAD 2DROP 2DROP SOURCE-ID 0> 0= IF -999 THROW THEN -123 THROW ; : CSV-RUN S\" a.txt\" ['] CSV-BAD READ-CSV ;");
    const top = m.heapTop();
    try m.interpretLine("' CSV-RUN CATCH SOURCE-ID");
    try support.expectStack(m, &.{ -123, 0 });
    try std.testing.expectEqual(top, m.heapTop());
    try std.testing.expect(!out.files[0].open and m.include_depth == 0);
}

test "P06b nested CSV readers preserve outer borrowed field and parser buffers" {
    try support.skipWithout(&.{.files});
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    support.setFakeFile(&out, 0, "a,b\n");
    support.setFakeFile(&out, 1, "X,Y\n");
    try m.interpretLine(": CSV-INNER 2DROP TYPE ; : CSV-OUTER 2DROP 2DUP TYPE S\" b.txt\" ['] CSV-INNER READ-CSV TYPE ; S\" a.txt\" ' CSV-OUTER READ-CSV");
    try std.testing.expectEqualStrings("aXYabXYb", out.written());
    try std.testing.expect(!out.files[0].open and !out.files[1].open);
}

test "P06b CSV matches permissive quote endings and unterminated multiline EOF" {
    try support.skipWithout(&.{.files});
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    support.setFakeFile(&out, 0, "a\"b,\"a\"x\n\"unclosed\nend");
    try m.interpretLine(define_field);
    try m.interpretLine("S\" a.txt\" ' CSV-FIELD READ-CSV");
    try std.testing.expectEqualStrings("1 0 a\"b|1 1 a\"x|2 0 unclosed\nend\n|", out.written());
}

fn prefixedOpen(context: ?*anyopaque, name: []const u8, access: forth.FileAccess, create: bool) forth.FileResult {
    if (std.mem.startsWith(u8, name, "lib/")) return support.fakeOpen(context, name[4..], access, create);
    return support.fakeOpen(context, name, access, create);
}

test "P06b CSV configured paths custom settings and callback setting changes" {
    try support.skipWithout(&.{.files});
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    var ops = support.fake_file_ops;
    ops.open = prefixedOpen;
    m.writer.file_ops = &ops;
    support.setFakeFile(&out, 0, "'a;b';c\n");
    try m.interpretLine(define_field);
    try m.interpretLine("FPATH PATH= lib 39 TO CSV-QUOTE 59 TO CSV-SEPARATOR S\" a.txt\" ' CSV-FIELD READ-CSV");
    try std.testing.expectEqualStrings("1 0 a;b|1 1 c|", out.written());
    try std.testing.expect(m.findSourceEntry("lib/a.txt") != null);
    try std.testing.expect(m.findSourceFile("lib/a.txt") == null);
    out.len = 0;
    support.setFakeFile(&out, 0, "a,b;c\n");
    try m.interpretLine(": CSV-CHANGE 2DROP TYPE 124 EMIT 59 TO CSV-SEPARATOR ; 44 TO CSV-SEPARATOR S\" a.txt\" ' CSV-CHANGE READ-CSV");
    try std.testing.expectEqualStrings("a|b|c|", out.written());
}

fn failedRead(_: ?*anyopaque, _: forth.Cell, _: []u8) forth.LineResult {
    return .{ .ior = map.errnoIor(5) };
}

test "P06b CSV I/O failures allocation failures stack preflight and nesting close all owned resources" {
    try support.skipWithout(&.{.files});
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    support.setFakeFile(&out, 0, "a,b\n");
    try m.interpretLine(": CSV-IGNORE 2DROP 2DROP ; : CSV-RUN S\" a.txt\" ['] CSV-IGNORE READ-CSV ;");
    var ops = support.fake_file_ops;
    ops.read_line = failedRead;
    m.writer.file_ops = &ops;
    try m.interpretLine("' CSV-RUN CATCH");
    try support.expectStack(m, &.{map.errnoIor(5)});
    try std.testing.expect(!out.files[0].open and m.include_depth == 0);
    m.data_depth = 0;
    ops.read_line = support.fakeReadLine;
    _ = (try m.heapAllocate(@intCast(m.sizes.heapEnd() - m.heapTop() - 16))).?;
    const top = m.heapTop();
    try m.interpretLine("' CSV-RUN CATCH");
    try std.testing.expect(m.data_stack[m.data_depth - 1] != 0);
    try std.testing.expectEqual(top, m.heapTop());
    try std.testing.expect(!out.files[0].open and m.include_depth == 0);
    m.data_depth = 0;
    m.include_depth = map.max_include_depth;
    try std.testing.expectError(error.IncludeNesting, m.executeWord(m.lookup("CSV-RUN").?));
    m.include_depth = 0;
}

test "P06b CSV close errors oversized lines and full-stack preflight retain ownership rules" {
    try support.skipWithout(&.{.files});
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    support.setFakeFile(&out, 0, "a\n");
    try m.interpretLine(": CSV-IGNORE 2DROP 2DROP ; : CSV-RUN S\" a.txt\" ['] CSV-IGNORE READ-CSV ;");
    out.close_fails = true;
    try m.interpretLine("' CSV-RUN CATCH");
    try support.expectStack(m, &.{map.errnoIor(5)});
    try std.testing.expect(!out.files[0].open and m.include_depth == 0);
    out.close_fails = false;
    m.data_depth = 0;
    @memset(out.files[0].data[0 .. map.tib_size + 1], 'x');
    out.files[0].len = map.tib_size + 1;
    try std.testing.expectError(error.StringTooLong, m.executeWord(m.lookup("CSV-RUN").?));
    try std.testing.expect(!out.files[0].open and m.include_depth == 0);
    m.data_depth = m.data_stack.len;
    m.data_stack[m.data_depth - 1] = m.lookup("CSV-IGNORE").?;
    try std.testing.expectError(error.StackOverflow, m.executeBuiltin(.read_csv));
    try std.testing.expect(!out.files[0].open);
}
