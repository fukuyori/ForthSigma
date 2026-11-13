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
