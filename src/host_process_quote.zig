//! CRT command-line quoting for CreateProcessW. argv[0] has separate rules.
//! See Microsoft "Parsing C command-line arguments"; no shell escaping occurs.
const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
pub const Error = error{ InvalidText, InvalidUtf8, TooLarge, OutOfMemory };
const max_units = 32767; // Includes the terminating NUL.
fn put(output: *std.ArrayList(u16), allocator: Allocator, unit: u16) Error!void {
    if (output.items.len == max_units - 1) return error.TooLarge;
    try output.append(allocator, unit);
}
fn slashes(output: *std.ArrayList(u16), allocator: Allocator, count: usize) Error!void {
    for (0..count) |_| try put(output, allocator, '\\');
}
pub fn encode(allocator: Allocator, arguments: []const []const u8) Error![:0]u16 {
    if (arguments.len == 0 or arguments[0].len == 0 or std.mem.indexOfScalar(u8, arguments[0], '"') != null) return error.InvalidText;
    var output: std.ArrayList(u16) = .empty;
    errdefer output.deinit(allocator);
    for (arguments, 0..) |argument, index| {
        if (std.mem.indexOfScalar(u8, argument, 0) != null) return error.InvalidText;
        // Even all 4-byte UTF-8 scalars cannot fit above this bound.
        if (argument.len > max_units * 4) return error.TooLarge;
        const units = try std.unicode.utf8ToUtf16LeAlloc(allocator, argument);
        defer allocator.free(units);
        if (index != 0) try put(&output, allocator, ' ');
        try put(&output, allocator, '"');
        if (index == 0) {
            // The CRT's argv[0] parser does not interpret backslash escapes.
            for (units) |unit| try put(&output, allocator, unit);
        } else {
            var pending: usize = 0;
            for (units) |unit| {
                if (unit == '\\') {
                    pending += 1;
                    continue;
                }
                try slashes(&output, allocator, if (unit == '"') pending * 2 + 1 else pending);
                pending = 0;
                try put(&output, allocator, unit);
            }
            try slashes(&output, allocator, pending * 2);
        }
        try put(&output, allocator, '"');
    }
    return try output.toOwnedSliceSentinel(allocator, 0);
}

test "Windows quoting preserves empty quoted Unicode and trailing slash arguments" {
    const arguments = [_][]const u8{ "C:\\Program Files\\tool.exe", "", "a b", "a\"b", "one\\", "日 本", "\\\"", "\\\\" };
    const output = try encode(std.testing.allocator, &arguments);
    defer std.testing.allocator.free(output);
    const expected = std.unicode.utf8ToUtf16LeStringLiteral("\"C:\\Program Files\\tool.exe\" \"\" \"a b\" \"a\\\"b\" \"one\\\\\" \"日 本\" \"\\\\\\\"\" \"\\\\\\\\\"");
    try std.testing.expectEqualSlices(u16, expected, output);
}

test "Windows native parser independently round trips quoted argument boundaries" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    const native = struct {
        extern "shell32" fn CommandLineToArgvW([*:0]const u16, *c_int) callconv(.winapi) ?[*][*:0]u16;
        extern "kernel32" fn LocalFree(*anyopaque) callconv(.winapi) ?*anyopaque;
    };
    const arguments = [_][]const u8{ "C:\\dir with spaces\\tool.exe", "", " ", "a\tb", "a\"b", "\\", "\\\\\"", "末尾\\", "日本語", "&|<>^%PATH%" };
    const output = try encode(std.testing.allocator, &arguments);
    defer std.testing.allocator.free(output);
    var count: c_int = 0;
    const decoded = native.CommandLineToArgvW(output.ptr, &count) orelse return error.TestUnexpectedResult;
    defer _ = native.LocalFree(@ptrCast(decoded));
    try std.testing.expectEqual(arguments.len, @as(usize, @intCast(count)));
    for (arguments, 0..) |argument, index| {
        const expected = try std.unicode.utf8ToUtf16LeAlloc(std.testing.allocator, argument);
        defer std.testing.allocator.free(expected);
        try std.testing.expectEqualSlices(u16, expected, std.mem.span(decoded[index]));
    }
}

test "Windows quoting rejects NUL invalid argv0 and command line overflow without leaking" {
    try std.testing.expectError(error.InvalidText, encode(std.testing.allocator, &.{}));
    try std.testing.expectError(error.InvalidText, encode(std.testing.allocator, &.{""}));
    try std.testing.expectError(error.InvalidText, encode(std.testing.allocator, &.{"bad\"name"}));
    try std.testing.expectError(error.InvalidText, encode(std.testing.allocator, &.{ "program", "a\x00b" }));
    try std.testing.expectError(error.InvalidUtf8, encode(std.testing.allocator, &.{ "program", "\xff" }));
    const long: [32767]u8 = @splat('a');
    try std.testing.expectError(error.TooLarge, encode(std.testing.allocator, &.{ "program", &long }));
}

test "Windows quoting releases allocations at every failed allocation point" {
    const Scenario = struct {
        fn run(allocator: Allocator) !void {
            const output = try encode(allocator, &.{ "C:\\space dir\\tool.exe", "", "a\"\\b", "日" });
            defer allocator.free(output);
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Scenario.run, .{});
}
