//! Public grapheme words: memory, stack, strict UTF-8 and image contracts.
const std = @import("std");
const support = @import("support.zig");
const defs = @import("../core/defs.zig");

test "grapheme words keep input stack on errors and reject strict UTF-8 failures" {
    try support.skipWithout(&.{.extension});
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try machine.interpretLine("REQUIRE-EXTENSION ALSO EXTENSION");
    const address = 0x10000;
    const invalid = [_][]const u8{ "\x80", "\xC0\x80", "\xC1\xBF", "\xE0\x80\x80", "\xED\xA0\x80", "\xF0\x80\x80\x80", "\xF4\x90\x80\x80", "\xF5\x80\x80\x80", "\xE2\x82", "\xE2x", "a\xFF", "\xE2\x28\xA1", "\xF0\x9F\x98x" };
    inline for (.{ defs.Builtin.x_grapheme, defs.Builtin.x_grapheme_last }) |word| {
        for (invalid) |bytes| {
            @memcpy(machine.memory[address..][0..bytes.len], bytes);
            machine.data_depth = 0;
            try machine.push(address);
            try machine.push(@intCast(bytes.len));
            try std.testing.expectError(error.InvalidNumber, machine.executeBuiltin(word));
            try support.expectStack(machine, &.{ address, @intCast(bytes.len) });
        }
        machine.data_depth = 0;
        try std.testing.expectError(error.StackUnderflow, machine.executeBuiltin(word));
        try machine.push(address);
        try std.testing.expectError(error.StackUnderflow, machine.executeBuiltin(word));
        try support.expectStack(machine, &.{address});
        try machine.push(-1);
        try std.testing.expectError(error.InvalidAddress, machine.executeBuiltin(word));
        try support.expectStack(machine, &.{ address, -1 });
        machine.data_depth = 0;
        try machine.push(-1);
        try machine.push(1);
        try std.testing.expectError(error.InvalidAddress, machine.executeBuiltin(word));
        try support.expectStack(machine, &.{ -1, 1 });
    }
}

test "grapheme long combining sequence and terminal controls" {
    try support.skipWithout(&.{.extension});
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try machine.interpretLine("REQUIRE-EXTENSION ALSO EXTENSION");
    const address = 0x10000;
    machine.memory[address] = 'a';
    for (0..10000) |i| @memcpy(machine.memory[address + 1 + 2 * i ..][0..2], "\xCC\x81");
    inline for (.{ defs.Builtin.x_grapheme, defs.Builtin.x_grapheme_last }) |word| {
        machine.data_depth = 0;
        try machine.push(address);
        try machine.push(20001);
        try machine.executeBuiltin(word);
        try support.expectStack(machine, &.{20001});
    }
    machine.data_depth = 0;
    try machine.interpretLine("0 0 X-GRAPHEME 0 0 X-GRAPHEME-LAST S\" abc\" X-GRAPHEME S\" abc\" X-GRAPHEME-LAST");
    try support.expectStack(machine, &.{ 0, 0, 1, 1 });
}

test "grapheme builtin execution excluded with extension" {
    if (defs.extension_enabled) return error.SkipZigTest;
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try std.testing.expectError(error.InvalidExecutionToken, machine.executeBuiltin(.x_grapheme));
    try std.testing.expectError(error.InvalidExecutionToken, machine.executeBuiltin(.x_grapheme_last));
    try std.testing.expect(@import("../core/words_help.zig").entry("X-GRAPHEME") == null);
    try std.testing.expect(machine.lookup("X-GRAPHEME") == null);
    try std.testing.expect(machine.lookup("X-GRAPHEME-LAST") == null);
    // Inspect all vocabularies, not only the active search order.
    for (machine.words[0..machine.word_count]) |word| {
        try std.testing.expect(!std.mem.eql(u8, machine.wordName(word), "X-GRAPHEME"));
        try std.testing.expect(!std.mem.eql(u8, machine.wordName(word), "X-GRAPHEME-LAST"));
    }
}

test "Unicode 18 official extended grapheme conformance all cases" {
    const grapheme = @import("../core/grapheme.zig");
    const fixture = @embedFile("grapheme_break_test");
    var lines = std.mem.splitScalar(u8, fixture, '\n');
    var cases: usize = 0;
    while (lines.next()) |line| {
        const body = line[0 .. std.mem.indexOfScalar(u8, line, '#') orelse line.len];
        var tokens = std.mem.tokenizeAny(u8, body, " \t\r");
        var bytes: [4096]u8 = undefined;
        var length: usize = 0;
        var boundaries: [1024]usize = undefined;
        var count: usize = 0;
        while (tokens.next()) |token| {
            if (std.mem.eql(u8, token, "÷")) {
                if (count == boundaries.len) return error.FixtureTooLarge;
                boundaries[count] = length;
                count += 1;
            } else if (!std.mem.eql(u8, token, "×")) {
                const code = try std.fmt.parseInt(u21, token, 16);
                var encoded: [4]u8 = undefined;
                const n = try std.unicode.utf8Encode(code, &encoded);
                if (n > bytes.len - length) return error.FixtureTooLarge;
                @memcpy(bytes[length..][0..n], encoded[0..n]);
                length += n;
            }
        }
        if (count == 0) continue;
        try std.testing.expectEqual(@as(usize, 0), boundaries[0]);
        try std.testing.expectEqual(length, boundaries[count - 1]);
        for (boundaries[0 .. count - 1], boundaries[1..count]) |start, end| {
            try std.testing.expectEqual(end - start, try grapheme.size(bytes[start..length], false));
            try std.testing.expectEqual(end - start, try grapheme.size(bytes[0..end], true));
        }
        cases += 1;
    }
    try std.testing.expectEqual(@as(usize, 853), cases);
}

test "grapheme lookahead policy scalar limits and intersecting properties" {
    const grapheme = @import("../core/grapheme.zig");
    try std.testing.expectEqual(@as(usize, 1), try grapheme.size("ab\xFF", false));
    try std.testing.expectError(error.InvalidNumber, grapheme.size("ab\xFF", true));
    try std.testing.expectError(error.InvalidNumber, grapheme.size("a\xFF", false));
    const scalars = [_][]const u8{ "\x7F", "\xC2\x80", "\xDF\xBF", "\xE0\xA0\x80", "\xED\x9F\xBF", "\xEE\x80\x80", "\xEF\xBF\xBF", "\xF0\x90\x80\x80", "\xF4\x8F\xBF\xBF", "\x00", "\r\n" };
    for (scalars) |bytes| {
        try std.testing.expectEqual(bytes.len, try grapheme.size(bytes, false));
        try std.testing.expectEqual(bytes.len, try grapheme.size(bytes, true));
    }
    const cases = [_]struct { text: []const u8, first: usize, last: usize }{
        .{ .text = "\u{094D}\u{200D}\u{0915}", .first = 9, .last = 9 },
        .{ .text = "\u{094D}\u{200C}\u{0915}", .first = 6, .last = 3 },
        .{ .text = "\u{1F600}\u{094D}\u{200D}\u{1F600}", .first = 14, .last = 14 },
        .{ .text = "\u{1F600}\u{1CF5}\u{200D}\u{1F600}", .first = 4, .last = 4 },
        .{ .text = "\u{094D}\u{1CF5}\u{0915}", .first = 3, .last = 6 },
    };
    for (cases) |case| {
        try std.testing.expectEqual(case.first, try grapheme.size(case.text, false));
        try std.testing.expectEqual(case.last, try grapheme.size(case.text, true));
    }
}

test "grapheme compiled words survive image restore" {
    try support.skipWithout(&.{ .extension, .image });
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try machine.interpretLine("REQUIRE-EXTENSION ALSO EXTENSION : GB-TEST S\" abc\" X-GRAPHEME S\" abc\" X-GRAPHEME-LAST ; PREVIOUS");
    const image = try std.testing.allocator.alloc(u8, try machine.encodedSize());
    defer std.testing.allocator.free(image);
    _ = try machine.encodeImage(image);
    const restored = try support.createMachine(&output);
    defer support.destroyMachine(restored);
    try restored.restoreImage(image);
    try restored.interpretLine("GB-TEST");
    try support.expectStack(restored, &.{ 1, 1 });
}
