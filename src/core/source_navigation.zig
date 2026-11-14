//! Transient source browsing state, independent of dictionary handles.
const std = @import("std");
const forth = @import("../forth.zig");
const defs = @import("defs.zig");
const map = @import("memory_map.zig");
const input = @import("source_input.zig");
pub const tool_words = [_]defs.Builtin{ .before_locate, .after_locate, .xt_locate, .source_l, .source_n, .source_b };
pub const words = tool_words ++ [_]defs.Builtin{.documentation_comment};
pub const Navigation = struct {
    path: [255]u8 = undefined,
    length: u8 = 0,
    line: u32 = 1,
    first: ?u32 = null,
    generation: u64 = 0,
};

pub fn select(self: *forth.State, file_index: usize, line: u32) void {
    self.source_navigation.length = 0;
    if (file_index >= self.sourceFileCount() or line == 0) return;
    const name = self.sourceFileName(file_index);
    if (name.len == 0 or name.len > 255) return;
    self.source_navigation = .{ .length = @intCast(name.len), .line = line, .generation = self.image_generation };
    @memcpy(self.source_navigation.path[0..name.len], name);
}

pub fn execute(self: *forth.State, comptime word: defs.Builtin) forth.RuntimeError!void {
    switch (word) {
        .before_locate => try self.push(self.readCellConst(map.before_locate_address)),
        .after_locate => try self.push(self.readCellConst(map.after_locate_address)),
        .xt_locate => try self.locateWord(try self.wordId(try self.pop())),
        .source_l, .source_n, .source_b => try show(self, word),
        .documentation_comment => {
            const end = std.mem.indexOfScalarPos(u8, self.source_line, self.sourceCursor(), '\n');
            self.setSourceCursor(if (end) |at| at + 1 else self.source_line.len);
        },
        else => unreachable,
    }
}

fn show(self: *forth.State, comptime word: defs.Builtin) forth.RuntimeError!void {
    const before = self.readCellConst(map.before_locate_address);
    const after = self.readCellConst(map.after_locate_address);
    // A view is bounded to 256 physical lines; avoid accidental unbounded output.
    if (before < 0 or after < 0 or before > 255 or after > 255 or before + after > 255) return error.InvalidNumber;
    const nav = &self.source_navigation;
    if (nav.length == 0 or nav.generation != self.image_generation) {
        nav.length = 0;
        if (self.readCellConst(map.warnings_address) != 0) {
            @import("words_tools.zig").writeError(self, "WARNING: NO CURRENT LOCATION\n");
            if (self.readCellConst(map.warnings_address) == -4) return error.WarningError;
        }
        return;
    }
    const count: u32 = @intCast(before + 1 + after);
    var first = nav.first orelse @max(1, nav.line -| @as(u32, @intCast(before)));
    first = switch (word) {
        .source_n => first +| count,
        .source_b => @max(1, first -| count),
        else => first,
    };
    nav.first = first;
    const name = nav.path[0..nav.length];
    var text: [24]u8 = undefined;
    self.write(name);
    self.write(std.fmt.bufPrint(&text, ":{d}\n", .{first}) catch unreachable);
    try input.listSourceLines(self, name, first, first +| (count - 1));
}
