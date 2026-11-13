const std = @import("std");
const support = @import("support.zig");
const glob = @import("../core/filename_match.zig");
const map = @import("../core/memory_map.zig");

test "P05b glob wildcard and bracket semantics are portable and case sensitive" {
    try support.skipWithout(&.{.files});
    var output = support.Output{};
    const m = try support.createMachine(&output);
    defer support.destroyMachine(m);
    const cases = [_]struct { name: []const u8, pattern: []const u8, expected: bool }{
        .{ .name = "", .pattern = "*", .expected = true },
        .{ .name = "", .pattern = "", .expected = true },
        .{ .name = "", .pattern = "?", .expected = false },
        .{ .name = "a/b", .pattern = "a?b", .expected = true },
        .{ .name = ".hidden", .pattern = "*", .expected = true },
        .{ .name = "ABC", .pattern = "abc", .expected = false },
        .{ .name = "aaabaaaac", .pattern = "*a*b*a*c", .expected = true },
        .{ .name = "aaabaaaad", .pattern = "*a*b*a*c", .expected = false },
        .{ .name = "abc", .pattern = "a**?c", .expected = true },
        .{ .name = "*?[]\\", .pattern = "\\*\\?\\[\\]\\\\", .expected = true },
        .{ .name = "a", .pattern = "a\\", .expected = false },
        .{ .name = "[", .pattern = "[", .expected = false },
        .{ .name = "]", .pattern = "[]]", .expected = true },
        .{ .name = "-", .pattern = "[-a]", .expected = true },
        .{ .name = "-", .pattern = "[a-]", .expected = true },
        .{ .name = "b", .pattern = "[a-c]", .expected = true },
        .{ .name = "b", .pattern = "[!a-c]", .expected = false },
        .{ .name = "d", .pattern = "[^a-c]", .expected = true },
        .{ .name = "b", .pattern = "[c-a]", .expected = false },
        .{ .name = "-", .pattern = "[a\\-c]", .expected = true },
        .{ .name = "5", .pattern = "[a-c[:digit:]]", .expected = true },
        .{ .name = "x", .pattern = "[![:unknown:]]", .expected = false },
        .{ .name = "x", .pattern = "[[.x.]]", .expected = false },
        .{ .name = "x", .pattern = "[[=x=]]", .expected = false },
    };
    for (cases) |case| try std.testing.expectEqual(case.expected, try glob.matches(m, case.name, case.pattern));
}

test "P05b glob decodes codepoints and distinguishes invalid bytes from Unicode" {
    try support.skipWithout(&.{.files});
    var output = support.Output{};
    const m = try support.createMachine(&output);
    defer support.destroyMachine(m);
    try std.testing.expect(try glob.matches(m, "日本語", "???"));
    try std.testing.expect(!try glob.matches(m, "日本語", "?????????"));
    try std.testing.expect(try glob.matches(m, "名", "[名-語]"));
    try std.testing.expect(try glob.matches(m, "😀", "?"));
    try std.testing.expect(try glob.matches(m, "e\xcc\x81", "??"));
    try std.testing.expect(!try glob.matches(m, "é", "e\xcc\x81"));
    try std.testing.expect(!try glob.matches(m, "é", "[[:alpha:]]"));
    try std.testing.expect(try glob.matches(m, "\xff\xc0\x80", "???"));
    try std.testing.expect(try glob.matches(m, "\xed\xa0\x80", "???"));
    try std.testing.expect(try glob.matches(m, "\xf0\x9f", "??"));
    try std.testing.expect(try glob.matches(m, "\xff", "\xff"));
    try std.testing.expect(!try glob.matches(m, "\xff", "ÿ"));
}

test "P05b glob implements the twelve named classes on ASCII only" {
    try support.skipWithout(&.{.files});
    var output = support.Output{};
    const m = try support.createMachine(&output);
    defer support.destroyMachine(m);
    const cases = .{
        .{ "alnum", "Az0", "_-" },   .{ "alpha", "Az", "0_" },
        .{ "blank", " \t", "\nA" },  .{ "cntrl", "\x01\x7f", " A" },
        .{ "digit", "09", "a-" },    .{ "graph", "A!", " \x7f" },
        .{ "lower", "az", "AZ" },    .{ "print", " A!", "\x01\x7f" },
        .{ "punct", "!_-", "Aa0 " }, .{ "space", " \t\n\r\x0b\x0c", "A0" },
        .{ "upper", "AZ", "az" },    .{ "xdigit", "09aAfF", "gG" },
    };
    inline for (cases) |case| {
        const pattern = "[[:" ++ case[0] ++ ":]]";
        for (case[1]) |c| try std.testing.expect(try glob.matches(m, &.{c}, pattern));
        for (case[2]) |c| try std.testing.expect(!try glob.matches(m, &.{c}, pattern));
        try std.testing.expect(!try glob.matches(m, "é", pattern));
    }
}

test "P05b glob validates ranges NUL and stack before changing inputs" {
    try support.skipWithout(&.{.files});
    var output = support.Output{};
    const m = try support.createMachine(&output);
    defer support.destroyMachine(m);
    try m.push(1);
    try std.testing.expectError(error.StackUnderflow, m.executeBuiltin(.filename_match));
    try support.expectStack(m, &.{1});
    m.data_depth = 0;
    try m.push(@intCast(m.memory.len));
    try m.push(1);
    try m.push(0);
    try m.push(0);
    try std.testing.expectError(error.InvalidAddress, m.executeBuiltin(.filename_match));
    try support.expectStack(m, &.{ @intCast(m.memory.len), 1, 0, 0 });
    m.data_depth = 0;
    m.memory[@intCast(map.pad_address)] = 0;
    try m.push(map.pad_address);
    try m.push(1);
    try m.push(0);
    try m.push(0);
    try std.testing.expectError(error.Thrown, m.executeBuiltin(.filename_match));
    try support.expectStack(m, &.{ map.pad_address, 1, 0, 0 });
    m.data_depth = 0;
    try m.push(0);
    try m.push(0);
    try m.push(map.pad_address);
    try m.push(1);
    try std.testing.expectError(error.Thrown, m.executeBuiltin(.filename_match));
    try support.expectStack(m, &.{ 0, 0, map.pad_address, 1 });
    m.data_depth = 0;
    try m.push(0);
    try m.push(0);
    try m.push(0);
    try m.push(-1);
    try std.testing.expectError(error.InvalidAddress, m.executeBuiltin(.filename_match));
    try support.expectStack(m, &.{ 0, 0, 0, -1 });
    m.data_depth = m.data_stack.len;
    m.data_stack[m.data_depth - 4] = @intCast(m.memory.len);
    m.data_stack[m.data_depth - 3] = 0;
    m.data_stack[m.data_depth - 2] = @intCast(m.memory.len);
    m.data_stack[m.data_depth - 1] = 0;
    try m.executeBuiltin(.filename_match);
    try std.testing.expectEqual(m.data_stack.len - 3, m.data_depth);
    try std.testing.expectEqual(@as(map.Cell, -1), try m.peek(0));
}

test "P05b glob works without host hooks or heap and respects the work budget" {
    try support.skipWithout(&.{.files});
    var output = support.Output{};
    const m = try support.createMachine(&output);
    defer support.destroyMachine(m);
    m.writer.file_ops = null;
    try m.interpretLine(": MATCH FILENAME-MATCH ; S\" 日本語.txt\" S\" ???.txt\"");
    _ = (try m.heapAllocate(@intCast(m.sizes.heapEnd() - m.heapTop() - 16))).?;
    const top = m.heapTop();
    try m.executeWord(m.lookup("MATCH").?);
    try support.expectStack(m, &.{-1});
    try std.testing.expectEqual(top, m.heapTop());
    if (@import("build_options").debug) {
        m.step_limit = 2;
        m.steps_left = 2;
        try std.testing.expectError(error.StepLimit, glob.matches(m, "aaaaaaaaaaaaab", "*aaaaac"));
    }
}
