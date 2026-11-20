//! Validated saved-image metadata before command-line grammar is selected.
const std = @import("std");
const format = @import("core/image_format.zig");
const defs = @import("core/defs.zig");
const entry = @import("core/app_entry.zig");
pub const footer_size = 20;
pub const magic = "SIGEND01";
pub const Footer = struct { image_len: u32, base_len: u64 };
pub const Info = struct { m: usize, l: usize, entry: ?u16 };
pub fn footer(bytes: *const [footer_size]u8, end: u64) defs.RuntimeError!?Footer {
    if (!std.mem.eql(u8, bytes[0..8], magic)) return null;
    const image_len = std.mem.readInt(u32, bytes[8..12], .little);
    const base_len = std.mem.readInt(u64, bytes[12..20], .little);
    const sum = @addWithOverflow(base_len, @as(u64, image_len));
    const total = @addWithOverflow(sum[0], footer_size);
    if (sum[1] != 0 or total[1] != 0 or total[0] != end or base_len == 0 or image_len < format.header_size + format.checksum_size) return error.InvalidImage;
    return .{ .image_len = image_len, .base_len = base_len };
}
pub fn inspect(bytes: []const u8, allocator: std.mem.Allocator) defs.RuntimeError!Info {
    const workspace = allocator.create(format.Workspace) catch return error.MemoryExhausted;
    defer allocator.destroy(workspace);
    const view = try format.parse(bytes, workspace);
    const root = try entry.imageEntry(view);
    for (0..view.header.word_count) |index| {
        const word = std.mem.bytesToValue(defs.Word, view.words[index * @sizeOf(defs.Word) ..][0..@sizeOf(defs.Word)]);
        try @import("core/image_features.zig").validateWord(word, index, view.header.builtin_count);
    }
    for (0..view.header.code_count) |index| {
        const op = std.mem.bytesToValue(defs.Op, view.code[index * @sizeOf(defs.Op) ..][0..@sizeOf(defs.Op)]);
        try @import("core/image_features.zig").validateOperation(op);
    }
    return .{ .m = view.header.m, .l = view.header.l, .entry = root };
}

test "saved footer differentiates absence and corrupt framing" {
    const t = std.testing;
    var bytes: [20]u8 = @splat(0);
    try t.expectEqual(@as(?Footer, null), try footer(&bytes, 1000));
    @memcpy(bytes[0..8], magic);
    std.mem.writeInt(u32, bytes[8..12], 200, .little);
    std.mem.writeInt(u64, bytes[12..20], 1000, .little);
    try t.expectEqual(@as(u64, 1000), (try footer(&bytes, 1220)).?.base_len);
    try t.expectError(error.InvalidImage, footer(&bytes, 1219));
    std.mem.writeInt(u64, bytes[12..20], std.math.maxInt(u64), .little);
    try t.expectError(error.InvalidImage, footer(&bytes, 0));
}
