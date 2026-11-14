const std = @import("std");
const support = @import("support.zig");
const map = @import("../core/memory_map.zig");
const registry = @import("../core/address_registry.zig");

test "P05a path descriptors share dynamic string storage and display components" {
    try support.skipWithout(&.{.files});
    var output = support.Output{};
    const m = try support.createMachine(&output);
    defer support.destroyMachine(m);
    try m.interpretLine("VARIABLE P P CLEAR-PATH P PATH= foo|bar P PATH+ baz S\" 日本語 dir\" P ALSO-PATH P .PATH");
    try std.testing.expectEqualStrings("foo bar baz 日本語 dir ", output.written());
    const owner = m.words[m.lookup("P").?].value;
    const text = try m.fetchString(owner);
    try std.testing.expectEqualStrings("foo\x00bar\x00baz\x00日本語 dir", m.memory[@intCast(text.address)..][0..text.length]);
    try registry.validate(m);
    output.len = 0;
    try m.interpretLine("P CLEAR-PATH P .PATH P $@LEN");
    try support.expectStack(m, &.{0});
    try std.testing.expectEqualStrings("", output.written());
}

test "P05a path parsing works from compiled code and preserves the parsed source" {
    try support.skipWithout(&.{.files});
    var output = support.Output{};
    const m = try support.createMachine(&output);
    defer support.destroyMachine(m);
    try m.interpretLine("VARIABLE P : SET-PATH PATH= ; : ADD-PATH PATH+ ; P SET-PATH one|two P ADD-PATH three P .PATH");
    try std.testing.expectEqualStrings("one two three ", output.written());
    const program = "P PATH= one|two";
    try m.interpretLine(program);
    try std.testing.expectEqualStrings(program, m.memory[@intCast(map.tib_address)..][0..program.len]);
    try std.testing.expectError(error.InvalidDefinition, m.interpretLine("P PATH+"));
    m.data_depth = 0;
    output.len = 0;
    try m.interpretLine("P PATH= |hidden P .PATH");
    try std.testing.expectEqualStrings("", output.written());
}

test "P05a also path handles self aliases and failed allocation leaves owner intact" {
    try support.skipWithout(&.{.files});
    var output = support.Output{};
    const m = try support.createMachine(&output);
    defer support.destroyMachine(m);
    try m.interpretLine("VARIABLE P P PATH= dir P $@ P ALSO-PATH");
    const owner = m.words[m.lookup("P").?].value;
    const old = try m.readCell(owner);
    const text = try m.fetchString(owner);
    try std.testing.expectEqualStrings("dir\x00dir", m.memory[@intCast(text.address)..][0..text.length]);
    _ = (try m.heapAllocate(@intCast(m.sizes.heapEnd() - m.heapTop() - 16))).?;
    const top = m.heapTop();
    try m.push(text.address);
    try m.push(@intCast(text.length));
    try m.push(owner);
    try std.testing.expectError(error.Thrown, m.executeBuiltin(.also_path));
    try std.testing.expectEqual(old, try m.readCell(owner));
    try std.testing.expectEqual(top, m.heapTop());
    try support.expectStack(m, &.{ text.address, @intCast(text.length), owner });
    try registry.validate(m);
}

test "P05a dot path snapshots input when captured into its own owner" {
    try support.skipWithout(&.{.files});
    var output = support.Output{};
    const m = try support.createMachine(&output);
    defer support.destroyMachine(m);
    try m.interpretLine("VARIABLE P : SHOW S\" P PATH= foo|bar P .PATH\" EVALUATE ; ' SHOW P $EXEC");
    const owner = m.words[m.lookup("P").?].value;
    const text = try m.fetchString(owner);
    try std.testing.expectEqualStrings("foo\x00barfoo bar ", m.memory[@intCast(text.address)..][0..text.length]);
    try registry.validate(m);
}

test "P05a paths survive repeated append and image restore with independent owners" {
    try support.skipWithout(&.{.files});
    var output = support.Output{};
    const source = try support.createMachine(&output);
    defer support.destroyMachine(source);
    try source.interpretLine("VARIABLE P P PATH= one|two");
    const target = try support.createMachine(&output);
    defer support.destroyMachine(target);
    try target.appendImage(source);
    try target.appendImage(source);
    const image = try std.testing.allocator.alloc(u8, try target.encodedSize());
    defer std.testing.allocator.free(image);
    _ = try target.encodeImage(image);
    try target.restoreImage(image);
    try target.interpretLine("P PATH+ three P .PATH");
    try std.testing.expectEqualStrings("one two three ", output.written());
    try registry.validate(target);
}

test "P05a absolute names include Gforth explicit-relative forms and empty spans are safe" {
    try support.skipWithout(&.{.files});
    var output = support.Output{};
    const m = try support.createMachine(&output);
    defer support.destroyMachine(m);
    try m.interpretLine("S\" /x\" ABSOLUTE-FILE? S\" ~/x\" ABSOLUTE-FILE? S\" ./x\" ABSOLUTE-FILE? S\" C:x\" ABSOLUTE-FILE? S\" C:\" ABSOLUTE-FILE? S\" ../x\" ABSOLUTE-FILE? S\" a/b\" ABSOLUTE-FILE?");
    try support.expectStack(m, &.{ -1, -1, -1, -1, 0, 0, 0 });
    m.data_depth = 0;
    try m.push(@intCast(m.memory.len));
    try m.push(0);
    try m.executeBuiltin(.absolute_file_query);
    try support.expectStack(m, &.{0});
    m.data_depth = 0;
    try m.push(0);
    try std.testing.expectError(error.StackUnderflow, m.executeBuiltin(.absolute_file_query));
    try support.expectStack(m, &.{0});
}

test "P05a path metadata exhaustion is atomic and CLEAR-PATH needs no extra stack slot" {
    try support.skipWithout(&.{.files});
    var output = support.Output{};
    const m = try support.createMachine(&output);
    defer support.destroyMachine(m);
    try m.interpretLine("VARIABLE P VARIABLE Q P CLEAR-PATH : FILL-TYPES 2047 0 DO 0 A, LOOP ; FILL-TYPES");
    const owner = m.words[m.lookup("Q").?].value;
    const top = m.heapTop();
    try m.push(owner);
    try std.testing.expectError(error.MemoryExhausted, m.executeBuiltin(.clear_path));
    try std.testing.expectEqual(@as(map.Cell, 0), try m.readCell(owner));
    try std.testing.expectEqual(top, m.heapTop());
    try support.expectStack(m, &.{owner});
    m.data_depth = m.data_stack.len;
    m.data_stack[m.data_depth - 1] = m.words[m.lookup("P").?].value;
    try m.executeBuiltin(.clear_path);
    try std.testing.expectEqual(m.data_stack.len - 1, m.data_depth);
    try registry.validate(m);
}

test "FPATH images retain configuration but both append routes preserve destination without orphan copies" {
    try support.skipWithout(&.{.files});
    const append = @import("../core/image_append.zig");
    var output = support.Output{};
    const source = try support.createMachine(&output);
    defer support.destroyMachine(source);
    try source.interpretLine("FPATH PATH= source|lib : CONFIG FPATH ;");
    const image = try std.testing.allocator.alloc(u8, try source.encodedSize());
    defer std.testing.allocator.free(image);
    _ = try source.encodeImage(image);
    const target = try support.createMachine(&output);
    defer support.destroyMachine(target);
    try target.restoreImage(image);
    try target.interpretLine("FPATH .PATH");
    try std.testing.expectEqualStrings("source lib ", output.written());
    try target.interpretLine("FPATH PATH= destination");
    const owner = try target.readCell(map.fpath_address);
    const top = target.heapTop();
    var work: append.Workspace = undefined;
    for (0..3) |_| {
        try target.appendImage(source);
        try append.append(target, image, &work);
        try std.testing.expectEqual(owner, try target.readCell(map.fpath_address));
        try std.testing.expectEqual(top, target.heapTop());
        try target.interpretLine("CONFIG FPATH =");
        try support.expectStack(target, &.{-1});
        target.data_depth = 0;
        try registry.validate(target);
    }
}

test "FPATH append retains explicit aliases to source configuration independently" {
    try support.skipWithout(&.{.files});
    const append = @import("../core/image_append.zig");
    var output = support.Output{};
    const source = try support.createMachine(&output);
    defer support.destroyMachine(source);
    try source.interpretLine("FPATH PATH= source FPATH $@ DROP ACONSTANT SNAPSHOT");
    const image = try std.testing.allocator.alloc(u8, try source.encodedSize());
    defer std.testing.allocator.free(image);
    _ = try source.encodeImage(image);
    const target = try support.createMachine(&output);
    defer support.destroyMachine(target);
    var work: append.Workspace = undefined;
    try append.append(target, image, &work);
    try source.interpretLine("FPATH $FREE");
    try target.interpretLine("SNAPSHOT 6 TYPE FPATH $@LEN");
    try std.testing.expectEqualStrings("source", output.written());
    try support.expectStack(target, &.{0});
    try registry.validate(target);
}

fn includePathOpen(context: ?*anyopaque, name: []const u8, access: @import("../forth.zig").FileAccess, create: bool) @import("../forth.zig").FileResult {
    if (std.mem.startsWith(u8, name, "lib/")) return support.fakeOpen(context, name[4..], access, create);
    return support.fakeOpen(context, name, access, create);
}

test "FPATH configured includes normalize history and close duplicate and failed candidates" {
    try support.skipWithout(&.{.files});
    var output = support.Output{};
    const m = try support.createMachine(&output);
    defer support.destroyMachine(m);
    var ops = support.fake_file_ops;
    ops.open = includePathOpen;
    m.writer.file_ops = &ops;
    const source = "123\n";
    @memcpy(output.files[0].data[0..source.len], source);
    output.files[0].len = source.len;
    output.files[0].exists = true;
    try m.interpretLine("FPATH PATH= missing|lib REQUIRE a.txt REQUIRE lib/../a.txt");
    try support.expectStack(m, &.{123});
    try std.testing.expect(m.findSourceFile("lib/a.txt") != null);
    try std.testing.expect(m.findSourceFile("a.txt") == null);
    try std.testing.expect(!output.files[0].open);
    output.close_fails = true;
    try std.testing.expectError(error.Thrown, m.requireFile("a.txt"));
    try std.testing.expect(!output.files[0].open);
    output.close_fails = false;
    output.files[0].exists = false;
    try std.testing.expectError(error.Thrown, m.requireFile("a.txt"));
    try m.interpretLine("FPATH CLEAR-PATH");
    _ = try m.recordSourceFile("a.txt");
    try m.requireFile("a.txt"); // Legacy cached REQUIRE does not reopen.
}

test "FPATH source relative lookup and registration failures retain ownership and history" {
    try support.skipWithout(&.{.files});
    var output = support.Output{};
    const m = try support.createMachine(&output);
    defer support.destroyMachine(m);
    var ops = support.fake_file_ops;
    ops.open = includePathOpen;
    m.writer.file_ops = &ops;
    support.setFakeFile(&output, 0, "INCLUDE ./b.txt\n");
    support.setFakeFile(&output, 1, "41\n");
    try m.interpretLine("FPATH PATH= lib INCLUDE a.txt");
    try support.expectStack(m, &.{41});
    try std.testing.expect(m.findSourceFile("lib/b.txt") != null);
    try std.testing.expect(!output.files[0].open and !output.files[1].open);
    m.data_depth = 0;
    support.setFakeFile(&output, 2, "42\n");
    try m.interpretLine("MARKER BEFORE REQUIRE c.txt BEFORE");
    try std.testing.expect(m.findSourceFile("lib/c.txt") == null);
    try m.requireFile("c.txt");
    try support.expectStack(m, &.{ 42, 42 });
    m.include_depth = map.max_include_depth;
    const opened = support.fakeOpen(m.writer.context, "c.txt", .read_only, false);
    try std.testing.expectError(error.IncludeNesting, m.includeOpenFile(@bitCast(opened.value), "c.txt"));
    m.include_depth = 0;
    try std.testing.expect(!output.files[2].open);
    support.setFakeFile(&output, 3, "UNKNOWN-WORD\n");
    try std.testing.expectError(error.UnknownWord, m.includeFile("d.txt"));
    try std.testing.expect(!output.files[3].open);
    try std.testing.expect(m.findSourceFile("lib/d.txt") != null);
}

test "FPATH empty and configured append combinations preserve destination and slot aliases" {
    try support.skipWithout(&.{.files});
    const append = @import("../core/image_append.zig");
    for ([_]bool{ false, true }) |source_configured| {
        for ([_]bool{ false, true }) |target_configured| {
            var output = support.Output{};
            const source = try support.createMachine(&output);
            defer support.destroyMachine(source);
            const target = try support.createMachine(&output);
            defer support.destroyMachine(target);
            if (source_configured) try source.interpretLine("FPATH PATH= source");
            if (target_configured) try target.interpretLine("FPATH PATH= target");
            try source.interpretLine("FPATH ACONSTANT OWNER FPATH $@ DROP ACONSTANT SNAPSHOT");
            const image = try std.testing.allocator.alloc(u8, try source.encodedSize());
            defer std.testing.allocator.free(image);
            _ = try source.encodeImage(image);
            const own = try target.readCell(map.fpath_address);
            var work: append.Workspace = undefined;
            try target.appendImage(source);
            try target.interpretLine("OWNER FPATH =");
            try support.expectStack(target, &.{-1});
            target.data_depth = 0;
            try append.append(target, image, &work);
            try std.testing.expectEqual(own, try target.readCell(map.fpath_address));
            try target.interpretLine("OWNER FPATH =");
            try support.expectStack(target, &.{-1});
            try registry.validate(target);
        }
    }
}

test "FPATH full restore clears a previous configuration and rejects damaged source owner on append" {
    try support.skipWithout(&.{.files});
    var output = support.Output{};
    const source = try support.createMachine(&output);
    defer support.destroyMachine(source);
    const target = try support.createMachine(&output);
    defer support.destroyMachine(target);
    const image = try std.testing.allocator.alloc(u8, try source.encodedSize());
    defer std.testing.allocator.free(image);
    _ = try source.encodeImage(image);
    try target.interpretLine("FPATH PATH= target");
    try target.restoreImage(image);
    try std.testing.expectEqual(@as(map.Cell, 0), try target.readCell(map.fpath_address));
    try source.interpretLine("FPATH PATH= source 0 FPATH C!");
    const count = target.word_count;
    const top = target.heapTop();
    try std.testing.expectError(error.InvalidAddress, target.appendImage(source));
    try std.testing.expectEqual(count, target.word_count);
    try std.testing.expectEqual(top, target.heapTop());
}

fn longIncludeOpen(context: ?*anyopaque, _: []const u8, access: @import("../forth.zig").FileAccess, create: bool) @import("../forth.zig").FileResult {
    return support.fakeOpen(context, "a.txt", access, create);
}

test "FPATH rejects oversized names and full source tables after closing and needs no spare stack cells" {
    try support.skipWithout(&.{.files});
    var output = support.Output{};
    const m = try support.createMachine(&output);
    defer support.destroyMachine(m);
    var ops = support.fake_file_ops;
    ops.open = longIncludeOpen;
    m.writer.file_ops = &ops;
    support.setFakeFile(&output, 0, "");
    try m.interpretLine("FPATH PATH= ~+");
    const long_name: [256]u8 = @splat('x');
    try std.testing.expectError(error.StringTooLong, m.includeFile(&long_name));
    try std.testing.expect(!output.files[0].open);
    m.data_depth = m.data_stack.len;
    try m.includeFile("a.txt");
    try std.testing.expectEqual(m.data_stack.len, m.data_depth);
    m.data_depth = 0;
    var name_buffer: [32]u8 = undefined;
    for (m.sourceFileCount()..map.max_source_files) |i| {
        const name = try std.fmt.bufPrint(&name_buffer, "f{d}", .{i});
        _ = try m.recordSourceFile(name);
    }
    try std.testing.expectError(error.TooManySourceFiles, m.includeFile("new.txt"));
    try std.testing.expect(!output.files[0].open);
}
