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

test "P09b WHERE selection walks results with an empty boundary state" {
    try support.skipWithout(&.{ .tools, .files });
    var out = support.Output{};
    support.setFakeFile(&out, 0, ": TARGET 11 ;\n: USE-ONE TARGET ;\n: USE-TWO TARGET ;\n");
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try m.interpretLine("INCLUDE a.txt 0 TO BEFORE-LOCATE 0 TO AFTER-LOCATE WHERE TARGET");
    try std.testing.expectEqual(@as(usize, 2), m.source_search.count);
    out.len = 0;
    try m.interpretLine("0 WW NW 0 WARNINGS ! NW L NW BW L BW");
    try std.testing.expectEqualStrings("a.txt:2\n: USE-ONE TARGET ;\na.txt:3\n: USE-TWO TARGET ;\na.txt:2\n: USE-ONE TARGET ;\na.txt:3\n: USE-TWO TARGET ;\n", out.written());
    try std.testing.expectEqual(@as(?usize, 1), m.source_search.current);
    try std.testing.expectEqual(@as(usize, 0), m.data_depth);
    try std.testing.expectError(error.InvalidNumber, m.interpretLine("-1 WW"));
    try std.testing.expectEqual(@as(?usize, 1), m.source_search.current);
    try std.testing.expectEqual(@as(map.Cell, -1), try m.pop());
    try m.interpretLine("999999 WW");
    try std.testing.expect(m.source_search.current == null);
    try std.testing.expectEqual(@as(u8, 0), m.source_navigation.length);
}

test "P09b WHERE snapshots ignore later uses and invalidate on dictionary deletion" {
    try support.skipWithout(&.{ .tools, .files });
    var out = support.Output{};
    support.setFakeFile(&out, 0, ": TARGET 11 ;\n: USE-ONE TARGET ;\n");
    support.setFakeFile(&out, 1, ": USE-TWO TARGET ;\n");
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try m.interpretLine("INCLUDE a.txt WHERE TARGET INCLUDE b.txt 0 WARNINGS !");
    try std.testing.expectEqual(@as(usize, 1), m.source_search.count);
    try m.interpretLine("0 WW NW");
    try std.testing.expect(m.source_search.current == null);
    try m.interpretLine("WHERE TARGET");
    try std.testing.expectEqual(@as(usize, 2), m.source_search.count);
    try m.interpretLine("FORGET USE-TWO : USE-TWO 99 ; NW");
    try std.testing.expectEqual(@as(usize, 0), m.source_search.count);
    try std.testing.expectEqual(@as(u8, 0), m.source_navigation.length);
}

test "P09b BROWSE copies its pattern and selects definitions in the first search wordlist" {
    try support.skipWithout(&.{ .tools, .files });
    var out = support.Output{};
    support.setFakeFile(&out, 0, ": NAV-ONE 11 ;\n: NAV-TWO 22 ;\nVOCABULARY OTHER-NAV ALSO OTHER-NAV DEFINITIONS\n: NAV-OTHER 33 ;\nFORTH DEFINITIONS PREVIOUS\n");
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try m.interpretLine("INCLUDE a.txt 0 TO BEFORE-LOCATE 0 TO AFTER-LOCATE BROWSE NAV-");
    // Matching uses a case-sensitive substring, like Sigma MWORDS.
    try std.testing.expectEqual(@as(usize, 2), m.source_search.count);
    try std.testing.expect(std.mem.indexOf(u8, out.written(), ": NAV-ONE 11 ;") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.written(), ": NAV-OTHER 33 ;") == null);
    out.len = 0;
    try m.interpretLine("0 WW NW");
    try std.testing.expectEqualStrings("a.txt:1\n: NAV-ONE 11 ;\na.txt:2\n: NAV-TWO 22 ;\n", out.written());
    try m.interpretLine("ALSO OTHER-NAV BROWSE NAV-");
    try std.testing.expectEqual(@as(usize, 1), m.source_search.count);
    out.len = 0;
    try m.interpretLine("0 WW PREVIOUS");
    try std.testing.expectEqualStrings("a.txt:4\n: NAV-OTHER 33 ;\n", out.written());
    try m.interpretLine("BROWSE nav-");
    try std.testing.expectEqual(@as(usize, 0), m.source_search.count);
}

test "P09b BROWSE has explicit no-file rows and no-result warnings obey policy" {
    try support.skipWithout(&.{.tools});
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try m.interpretLine(": NAV-TERMINAL 11 ; BROWSE NAV-TERMINAL");
    try std.testing.expectEqualStrings("\nNAV-TERMINAL: NO FILE INFORMATION 0", out.written());
    try m.interpretLine("0 WARNINGS ! 0 WW L");
    try std.testing.expectEqual(@as(?usize, 0), m.source_search.current);
    try m.interpretLine("-4 WARNINGS !");
    try std.testing.expectError(error.WarningError, m.interpretLine("NW"));
    try std.testing.expect(m.source_search.current == null);
}

test "P09b full image restore invalidates WHERE snapshots before using old indices" {
    try support.skipWithout(&.{ .tools, .files, .image });
    var out = support.Output{};
    support.setFakeFile(&out, 0, ": TARGET 11 ;\n: USE-ONE TARGET ;\n");
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    const image = try std.testing.allocator.alloc(u8, try m.encodedSize());
    defer std.testing.allocator.free(image);
    _ = try m.encodeImage(image);
    try m.interpretLine("INCLUDE a.txt WHERE TARGET 0 WW");
    try m.restoreImage(image);
    out.len = 0;
    try m.interpretLine("0 WARNINGS ! 0 WW NW BW L");
    try std.testing.expectEqualStrings("", out.written());
    try std.testing.expectEqual(@as(usize, 0), m.source_search.count);
    try std.testing.expectEqual(@as(u8, 0), m.source_navigation.length);
}

test "P09b BROWSE snapshots remain bounded across definition growth and both append routes" {
    try support.skipWithout(&.{ .tools, .files, .image });
    var out = support.Output{};
    support.setFakeFile(&out, 0, ": QRY-OLD 11 ;\n");
    const source = try support.createMachine(&out);
    defer support.destroyMachine(source);
    try source.interpretLine(": QRY-IMPORTED 22 ;");
    const image = try std.testing.allocator.alloc(u8, try source.encodedSize());
    defer std.testing.allocator.free(image);
    _ = try source.encodeImage(image);
    for (0..2) |mode| {
        const m = try support.createMachine(&out);
        defer support.destroyMachine(m);
        try m.interpretLine("INCLUDE a.txt 0 TO BEFORE-LOCATE 0 TO AFTER-LOCATE 0 WARNINGS ! BROWSE QRY-");
        if (mode == 0) try m.appendImage(source) else {
            var work: @import("../core/image_append.zig").Workspace = undefined;
            try @import("../core/image_append.zig").append(m, image, &work);
        }
        try m.interpretLine(": QRY-NEW 33 ;");
        try std.testing.expectEqual(@as(usize, 1), m.source_search.count);
        out.len = 0;
        try m.interpretLine("0 WW NW");
        try std.testing.expectEqualStrings("a.txt:1\n: QRY-OLD 11 ;\n", out.written());
        try m.interpretLine("BROWSE QRY-");
        try std.testing.expectEqual(@as(usize, 3), m.source_search.count);
    }
}

fn listingCwd(context: ?*anyopaque, buffer: []u8) @import("../forth.zig").FileResult {
    const o = support.fakeOutput(context);
    if (o.host_fails) return .{ .ior = @import("../forth.zig").errnoIor(5) };
    const name = "/work";
    @memcpy(buffer[0..name.len], name);
    buffer[name.len] = 0;
    return .{ .value = name.len };
}
const listingOps = blk: {
    var ops = support.fake_file_ops;
    ops.get_dir = listingCwd;
    break :blk ops;
};

test "P09b WHERE format switching preserves rows and groups consecutive files" {
    try support.skipWithout(&.{ .tools, .files });
    var out = support.Output{};
    support.setFakeFile(&out, 0, ": Q-TARGET 11 ;\n: Q-ONE Q-TARGET ;\n: Q-TWO Q-TARGET ;\n");
    support.setFakeFile(&out, 1, ": Q-THREE Q-TARGET ;\n");
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    m.writer.file_ops = &listingOps;
    try m.interpretLine("INCLUDE a.txt INCLUDE b.txt SHORT-WHERE WHERE Q-TARGET");
    try std.testing.expect(std.mem.startsWith(u8, out.written(), "\na.txt:2:9: : Q-ONE Q-TARGET ;"));
    try std.testing.expect(std.mem.indexOf(u8, out.written(), "\nb.txt:1:11:") != null);
    out.len = 0;
    try m.interpretLine("EXPAND-WHERE WHERE Q-TARGET");
    try std.testing.expect(std.mem.startsWith(u8, out.written(), "\n/work/a.txt:2:9: : Q-ONE Q-TARGET ;"));
    try std.testing.expect(std.mem.indexOf(u8, out.written(), "\n/work/b.txt:1:11:") != null);
    try std.testing.expect(std.mem.endsWith(u8, out.written(), "2"));
    out.len = 0;
    try m.interpretLine("PREPEND-WHERE WHERE Q-TARGET");
    try std.testing.expect(std.mem.startsWith(u8, out.written(), "\na.txt:\n:2:9: : Q-ONE Q-TARGET ;"));
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, out.written(), "a.txt:"));
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, out.written(), "b.txt:"));
    out.len = 0;
    try m.interpretLine("WHERE Q-TARGET");
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, out.written(), "a.txt:"));
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, out.written(), "b.txt:"));
    out.len = 0;
    try m.interpretLine("SHORT-WHERE WHERE Q-TARGET");
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, out.written(), "a.txt:"));
}

test "P09b expanded listing errors are reported before emitting a partial row" {
    try support.skipWithout(&.{ .tools, .files });
    var out = support.Output{};
    support.setFakeFile(&out, 0, ": Q-TARGET 11 ;\n: Q-ONE Q-TARGET ;\n");
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try m.interpretLine("INCLUDE a.txt EXPAND-WHERE");
    try std.testing.expectError(error.FileUnavailable, m.interpretLine("WHERE Q-TARGET"));
    try std.testing.expectEqualStrings("", out.written());
    m.writer.file_ops = &listingOps;
    out.host_fails = true;
    try std.testing.expectError(error.Thrown, m.interpretLine("WHERE Q-TARGET"));
    try std.testing.expectEqual(@as(map.Cell, -517), m.throw_code);
    try std.testing.expectEqualStrings("", out.written());
    out.host_fails = false;
    const absolute = try @import("../core/source_listing.zig").expanded(m, "/already/absolute.fs");
    try std.testing.expectEqualStrings("/already/absolute.fs", absolute.text());
    try std.testing.expectError(error.FileUnavailable, @import("../core/source_listing.zig").expanded(m, "C:relative.fs"));
}

test "P09b UNUSED-WORDS uses CURRENT and excludes only recorded file uses and anonymous words" {
    try support.skipWithout(&.{ .tools, .files });
    var out = support.Output{};
    support.setFakeFile(&out, 0, "VOCABULARY Q-VOC ALSO Q-VOC DEFINITIONS\n: Q-USED 11 ;\n: Q-UNUSED 22 ;\n: Q-CALL Q-USED ;\n:NONAME 33 ; DROP\nFORTH DEFINITIONS\n");
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try m.interpretLine("INCLUDE a.txt Q-VOC DEFINITIONS");
    out.len = 0;
    try m.interpretLine("Q-UNUSED DROP UNUSED-WORDS");
    try std.testing.expectEqualStrings("\nQ-UNUSED Q-CALL ", out.written());
    // Source use recording has a finite capacity: do not infer absence after loss.
    const count = m.use_count;
    m.use_count = m.uses.len;
    out.len = 0;
    try std.testing.expectError(error.InvalidDefinition, m.interpretLine("UNUSED-WORDS"));
    try std.testing.expectEqualStrings("", out.written());
    m.use_count = count;
}

test "P09b BROWSE shares listing formats and keeps result selection independent" {
    try support.skipWithout(&.{ .tools, .files });
    var out = support.Output{};
    support.setFakeFile(&out, 0, ": Q-ONE 11 ;\n: Q-TWO 22 ;\n");
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    m.writer.file_ops = &listingOps;
    try m.interpretLine("INCLUDE a.txt PREPEND-WHERE BROWSE Q-");
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, out.written(), "a.txt:"));
    out.len = 0;
    try m.interpretLine("0 TO BEFORE-LOCATE 0 TO AFTER-LOCATE EXPAND-WHERE 1 WW");
    try std.testing.expectEqualStrings("a.txt:2\n: Q-TWO 22 ;\n", out.written());
    out.len = 0;
    try m.interpretLine("BROWSE Q-");
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, out.written(), "/work/a.txt:"));
}

test "P09b listing style survives full restore and stays local on append with malformed image rejection" {
    try support.skipWithout(&.{ .tools, .image });
    var out = support.Output{};
    const source = try support.createMachine(&out);
    defer support.destroyMachine(source);
    try source.interpretLine("PREPEND-WHERE : RESTORE-STYLE SHORT-WHERE ;");
    const image = try std.testing.allocator.alloc(u8, try source.encodedSize());
    defer std.testing.allocator.free(image);
    _ = try source.encodeImage(image);
    for (0..3) |mode| {
        const m = try support.createMachine(&out);
        defer support.destroyMachine(m);
        switch (mode) {
            0 => try m.restoreImage(image),
            1 => try m.appendImage(source),
            else => {
                var work: @import("../core/image_append.zig").Workspace = undefined;
                try @import("../core/image_append.zig").append(m, image, &work);
            },
        }
        try std.testing.expectEqual(@as(map.Cell, if (mode == 0) 2 else 0), m.readCellConst(map.where_style_address));
        try m.interpretLine("RESTORE-STYLE");
        try std.testing.expectEqual(@as(map.Cell, 0), m.readCellConst(map.where_style_address));
    }
    const format = @import("../core/image_format.zig");
    const at = format.header_size + @as(usize, source.word_count) * @sizeOf(@import("../core/defs.zig").Word) + @as(usize, source.code_count) * @sizeOf(@import("../core/defs.zig").Op) + source.names_used + @as(usize, @intCast(map.where_style_address));
    std.mem.writeInt(map.Cell, image[at..][0..8], 3, .little);
    try format.finish(image);
    try std.testing.expectError(error.InvalidImage, source.restoreImage(image));
    try source.writeCell(map.where_style_address, -1);
    try std.testing.expectError(error.InvalidImage, source.encodedSize());
}
