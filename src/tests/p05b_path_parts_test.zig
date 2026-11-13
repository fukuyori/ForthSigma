const std = @import("std");
const support = @import("support.zig");
const map = @import("../core/memory_map.zig");

test "P05b basename and dirname return exact borrowed byte spans" {
    try support.skipWithout(&.{.files});
    var output = support.Output{};
    const m = try support.createMachine(&output);
    defer support.destroyMachine(m);
    const cases = [_]struct { name: []const u8, prefix: usize }{
        .{ .name = "", .prefix = 0 },         .{ .name = "file", .prefix = 0 },
        .{ .name = "/", .prefix = 1 },        .{ .name = "///", .prefix = 3 },
        .{ .name = "/one/two", .prefix = 5 }, .{ .name = "one/", .prefix = 4 },
        .{ .name = "./foo", .prefix = 2 },    .{ .name = "../foo", .prefix = 3 },
        .{ .name = "a//b", .prefix = 3 },     .{ .name = "C:\\one\\two", .prefix = 0 },
        .{ .name = "日本語/名前", .prefix = 10 },
        .{ .name = "a\x00/b", .prefix = 3 },  .{ .name = "\xff/\xfe", .prefix = 2 },
    };
    const address = map.pad_address;
    for (cases) |case| {
        @memcpy(m.memory[@intCast(address)..][0..case.name.len], case.name);
        inline for (.{ .basename, .dirname }) |word| {
            m.data_depth = 0;
            try m.push(address);
            try m.push(@intCast(case.name.len));
            try m.executeBuiltin(word);
            try support.expectStack(m, &.{
                address + @as(map.Cell, @intCast(if (word == .basename) case.prefix else 0)),
                @intCast(if (word == .basename) case.name.len - case.prefix else case.prefix),
            });
            try std.testing.expectEqualStrings(case.name, m.memory[@intCast(address)..][0..case.name.len]);
        }
    }
}

test "P05b path splitting validates before mutation and works with a full stack" {
    try support.skipWithout(&.{.files});
    var output = support.Output{};
    const m = try support.createMachine(&output);
    defer support.destroyMachine(m);
    inline for (.{ .basename, .dirname }) |word| {
        m.data_depth = 0;
        try m.push(42);
        try std.testing.expectError(error.StackUnderflow, m.executeBuiltin(word));
        try support.expectStack(m, &.{42});
        m.data_depth = 0;
        try m.push(@intCast(m.memory.len));
        try m.push(1);
        try std.testing.expectError(error.InvalidAddress, m.executeBuiltin(word));
        try support.expectStack(m, &.{ @intCast(m.memory.len), 1 });
        m.data_depth = 0;
        try m.push(0);
        try m.push(-1);
        try std.testing.expectError(error.InvalidAddress, m.executeBuiltin(word));
        try support.expectStack(m, &.{ 0, -1 });
        m.data_depth = m.data_stack.len;
        m.data_stack[m.data_depth - 2] = @intCast(m.memory.len);
        m.data_stack[m.data_depth - 1] = 0;
        try m.executeBuiltin(word);
        try std.testing.expectEqual(m.data_stack.len, m.data_depth);
        try std.testing.expectEqual(@as(map.Cell, @intCast(m.memory.len)), try m.peek(1));
        try std.testing.expectEqual(@as(map.Cell, 0), try m.peek(0));
    }
}

test "P05b path parts execute in compiled words without heap allocation" {
    try support.skipWithout(&.{.files});
    var output = support.Output{};
    const m = try support.createMachine(&output);
    defer support.destroyMachine(m);
    try m.interpretLine(": PARTS 2DUP DIRNAME TYPE [CHAR] | EMIT BASENAME TYPE ; S\" 日本語/名前\"");
    const top = m.heapTop();
    _ = (try m.heapAllocate(@intCast(m.sizes.heapEnd() - top - 16))).?;
    const full = m.heapTop();
    try m.executeWord(m.lookup("PARTS").?);
    try std.testing.expectEqualStrings("日本語/|名前", output.written());
    try std.testing.expectEqual(full, m.heapTop());
    try support.expectStack(m, &.{});
}
