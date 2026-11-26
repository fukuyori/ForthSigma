//! Checkout-independent bytes for embedded text. Binary assets must bypass this module.
const std = @import("std");

/// Removes CR bytes only; LF, UTF-8, and a missing final newline stay unchanged.
/// Two linear passes avoid repeated compile-time string concatenation.
pub fn withoutCarriageReturns(comptime text: []const u8) []const u8 {
    return comptime blk: {
        @setEvalBranchQuota(2_000_000);
        var size: usize = 0;
        for (text) |byte| {
            if (byte != '\r') size += 1;
        }
        var bytes: [size]u8 = undefined;
        var index: usize = 0;
        for (text) |byte| {
            if (byte != '\r') {
                bytes[index] = byte;
                index += 1;
            }
        }
        const result = bytes;
        break :blk &result;
    };
}

test "embedded text preserves LF bytes and removes CR at comptime" {
    try std.testing.expectEqualStrings("", withoutCarriageReturns(""));
    try std.testing.expectEqualStrings("a\nb\n", withoutCarriageReturns("a\nb\n"));
    try std.testing.expectEqualStrings("a\nb\n", withoutCarriageReturns("a\r\nb\r\n"));
    try std.testing.expectEqualStrings("ab", withoutCarriageReturns("a\rb\r"));
    try std.testing.expectEqualStrings("\xe6\x97\xa5\xe6\x9c\xac\xe8\xaa\x9e\n", withoutCarriageReturns("\xe6\x97\xa5\xe6\x9c\xac\xe8\xaa\x9e\r\n"));
}
