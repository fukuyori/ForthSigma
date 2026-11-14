const std = @import("std");
const support = @import("support.zig");
const map = @import("../core/memory_map.zig");

test "P09b clear words preserve independent stacks and live return frames" {
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try m.interpretLine(": T 123 >R 1 2 CLEARSTACK R> ; T");
    try support.expectStack(m, &.{123});
    try m.interpretLine(": U 456 >R 1 2 CLEARSTACKS R> ; U");
    try support.expectStack(m, &.{456});
    if (!@import("build_options").float) return;
    try m.interpretLine("1.25E CLEARSTACK FDEPTH FCLEARSTACK 2.5E 7 FCLEARSTACK FDEPTH");
    try support.expectStack(m, &.{ 1, 7, 0 });
    try m.interpretLine("9E CLEARSTACKS DEPTH FDEPTH");
    try support.expectStack(m, &.{ 0, 0 });
}

test "P09b dot-s display limits are non-destructive bounded and independent of BASE" {
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try m.interpretLine("1 2 3 4 2 MAXDEPTH-.S ! .S HEX .S DECIMAL");
    try std.testing.expectEqualStrings("<4> 3 4 <4> 3 4 ", out.written());
    try support.expectStack(m, &.{ 1, 2, 3, 4 });
    out.len = 0;
    try m.interpretLine("0 MAXDEPTH-.S ! .S 9223372036854775807 MAXDEPTH-.S ! .S");
    try std.testing.expectEqualStrings("<4> <4> 1 2 3 4 ", out.written());
    out.len = 0;
    try std.testing.expectError(error.InvalidNumber, m.interpretLine("-1 MAXDEPTH-.S ! .S"));
    try std.testing.expectEqualStrings("", out.written());
    try support.expectStack(m, &.{ 1, 2, 3, 4 });
}

test "P09b floating display setting is a TO value and validates before output" {
    try support.skipWithoutFloat();
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try m.interpretLine("F.S-PRECISION : WIDTH 8 TO F.S-PRECISION ; WIDTH F.S-PRECISION 1E 2E 1 MAXDEPTH-.S ! F.S");
    try support.expectStack(m, &.{ 14, 8 });
    try std.testing.expectEqualStrings("<2> 2.0000E0 ", out.written());
    try std.testing.expectEqual(@as(usize, 2), m.float_depth);
    out.len = 0;
    try std.testing.expectError(error.InvalidNumber, m.interpretLine("0 TO F.S-PRECISION F.S"));
    try std.testing.expectEqualStrings("", out.written());
    try std.testing.expectError(error.StringTooLong, m.interpretLine("4097 TO F.S-PRECISION F.S"));
    try std.testing.expectEqualStrings("", out.written());
}

test "P09b display settings persist on restore and remain local on both append routes" {
    try support.skipWithout(&.{.image});
    try support.skipWithoutFloat();
    var out = support.Output{};
    const source = try support.createMachine(&out);
    defer support.destroyMachine(source);
    try source.interpretLine("2 MAXDEPTH-.S ! 8 TO F.S-PRECISION : GET F.S-PRECISION ; : SET 12 TO F.S-PRECISION ;");
    const image = try std.testing.allocator.alloc(u8, try source.encodedSize());
    defer std.testing.allocator.free(image);
    _ = try source.encodeImage(image);
    for (0..3) |mode| {
        const m = try support.createMachine(&out);
        defer support.destroyMachine(m);
        try m.interpretLine("CREATE BEFORE 24 ALLOT");
        switch (mode) {
            0 => try m.restoreImage(image),
            1 => try m.appendImage(source),
            else => {
                var work: @import("../core/image_append.zig").Workspace = undefined;
                try @import("../core/image_append.zig").append(m, image, &work);
            },
        }
        try m.interpretLine("GET SET F.S-PRECISION");
        try support.expectStack(m, &.{ if (mode == 0) 8 else 14, 12 });
        try std.testing.expectEqual(@as(map.Cell, if (mode == 0) 2 else 9), m.readCellConst(map.maxdepth_dot_s_address));
    }
}

test "P09b source windows share LOCATE state and page in both directions" {
    try support.skipWithout(&.{ .tools, .files });
    var out = support.Output{};
    support.setFakeFile(&out, 0, "\\ one\n\\ two\n: NAV 11 ;\n\\ four\n\\ five\n\\ six\n\\ seven\n\\ eight\n");
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try m.interpretLine("INCLUDE a.txt 1 TO BEFORE-LOCATE 1 TO AFTER-LOCATE LOCATE NAV");
    try std.testing.expectEqualStrings("a.txt:3\n: NAV 11 ;\n", out.written());
    out.len = 0;
    try m.interpretLine("L N B B L");
    try std.testing.expectEqualStrings("a.txt:2\n\\ two\n: NAV 11 ;\n\\ four\na.txt:5\n\\ five\n\\ six\n\\ seven\na.txt:2\n\\ two\n: NAV 11 ;\n\\ four\na.txt:1\n\\ one\n\\ two\n: NAV 11 ;\na.txt:1\n\\ one\n\\ two\n: NAV 11 ;\n", out.written());
    out.len = 0;
    try m.interpretLine("' NAV XT-LOCATE L");
    try std.testing.expectEqualStrings("a.txt:3\n: NAV 11 ;\na.txt:2\n\\ two\n: NAV 11 ;\n\\ four\n", out.written());
    try std.testing.expectEqual(@as(usize, 0), m.data_depth);
}

test "P09b missing current source follows warnings and invalid windows are bounded" {
    try support.skipWithout(&.{.tools});
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try m.interpretLine("0 WARNINGS ! L N B -4 WARNINGS !");
    try std.testing.expectEqualStrings("", out.written());
    try std.testing.expectError(error.WarningError, m.interpretLine("L"));
    try m.interpretLine("0 WARNINGS ! -1 TO BEFORE-LOCATE");
    out.len = 0;
    try std.testing.expectError(error.InvalidNumber, m.interpretLine("L"));
    try std.testing.expectEqualStrings("", out.written());
    try m.interpretLine("255 TO BEFORE-LOCATE 1 TO AFTER-LOCATE");
    try std.testing.expectError(error.InvalidNumber, m.interpretLine("N"));
    try std.testing.expectError(error.InvalidExecutionToken, m.interpretLine("-1 XT-LOCATE"));
}

test "P09b source selection survives FORGET table reuse without aliasing and stops at EOF" {
    try support.skipWithout(&.{ .tools, .files });
    var out = support.Output{};
    support.setFakeFile(&out, 0, ": FROM-A 1 ;\n");
    support.setFakeFile(&out, 1, ": FROM-B 2 ;\n");
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try m.interpretLine("INCLUDE a.txt 0 TO BEFORE-LOCATE 0 TO AFTER-LOCATE LOCATE FROM-A FORGET FROM-A INCLUDE b.txt");
    out.len = 0;
    try m.interpretLine("L N B");
    try std.testing.expectEqualStrings("a.txt:1\n: FROM-A 1 ;\na.txt:2\na.txt:1\n: FROM-A 1 ;\n", out.written());
    out.len = 0;
    try m.interpretLine(": NO-FILE ; LOCATE NO-FILE 0 WARNINGS ! L");
    try std.testing.expectEqualStrings("NO-FILE: NO FILE INFORMATION\n", out.written());
}

test "P09b source window settings survive image routes and full restore invalidates the cursor" {
    try support.skipWithout(&.{ .tools, .files, .image });
    var out = support.Output{};
    support.setFakeFile(&out, 0, ": NAV-SOURCE 11 ;\n");
    const source = try support.createMachine(&out);
    defer support.destroyMachine(source);
    try source.interpretLine("INCLUDE a.txt 1 TO BEFORE-LOCATE 2 TO AFTER-LOCATE : CONTEXT BEFORE-LOCATE AFTER-LOCATE ; : RESET-CONTEXT 3 TO BEFORE-LOCATE 12 TO AFTER-LOCATE ;");
    const image = try std.testing.allocator.alloc(u8, try source.encodedSize());
    defer std.testing.allocator.free(image);
    _ = try source.encodeImage(image);
    for (0..3) |mode| {
        const m = try support.createMachine(&out);
        defer support.destroyMachine(m);
        try m.interpretLine("INCLUDE a.txt LOCATE NAV-SOURCE");
        switch (mode) {
            0 => try m.restoreImage(image),
            1 => try m.appendImage(source),
            else => {
                var work: @import("../core/image_append.zig").Workspace = undefined;
                try @import("../core/image_append.zig").append(m, image, &work);
            },
        }
        out.len = 0;
        try m.interpretLine("0 WARNINGS ! CONTEXT L");
        try support.expectStack(m, if (mode == 0) &.{ 1, 2 } else &.{ 3, 12 });
        if (mode == 0) try std.testing.expectEqualStrings("", out.written()) else try std.testing.expect(std.mem.startsWith(u8, out.written(), "a.txt:1\n"));
        try m.interpretLine("CLEARSTACK RESET-CONTEXT CONTEXT");
        try support.expectStack(m, &.{ 3, 12 });
    }
}

test "P09b errors select the failing source for subsequent browsing" {
    try support.skipWithout(&.{ .tools, .files });
    var out = support.Output{};
    support.setFakeFile(&out, 0, "\\ line one\nUNKNOWN-P09B\n");
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try std.testing.expectError(error.UnknownWord, m.interpretLine("INCLUDE a.txt"));
    m.report(error.UnknownWord);
    out.len = 0;
    try m.interpretLine("0 TO BEFORE-LOCATE 0 TO AFTER-LOCATE L");
    try std.testing.expectEqualStrings("a.txt:2\nUNKNOWN-P09B\n", out.written());
}

test "P09b documentation comments are immediate and discard only the current line" {
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try m.interpretLine("1 \\G ignored 2\n3");
    try support.expectStack(m, &.{ 1, 3 });
    try m.interpretLine(": DOC 4 \\G ignored ;");
    try std.testing.expect(m.compiling);
    try m.interpretLine("5 ; DOC");
    try support.expectStack(m, &.{ 1, 3, 4, 5 });
}

test "P09b embedded navigation works without file operations and saturates line arithmetic" {
    try support.skipWithout(&.{ .tools, .graphics });
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    const name = @import("../core/words_graphics.zig").library_name;
    m.graphics_library = "\\ before\n: NAV-EMBEDDED 11 ;\n\\ after\n";
    try m.includeEmbedded(name, m.graphics_library);
    const original_writer = m.writer;
    m.writer.file_ops = null;
    defer m.writer = original_writer;
    try m.interpretLine("1 TO BEFORE-LOCATE 1 TO AFTER-LOCATE LOCATE NAV-EMBEDDED L");
    try std.testing.expect(std.mem.endsWith(u8, out.written(), ":1\n\\ before\n: NAV-EMBEDDED 11 ;\n\\ after\n"));
    m.source_navigation.first = std.math.maxInt(u32);
    out.len = 0;
    try m.interpretLine("N");
    try std.testing.expectEqual(@as(?u32, std.math.maxInt(u32)), m.source_navigation.first);
    try std.testing.expect(std.mem.endsWith(u8, out.written(), ":4294967295\n"));
}
