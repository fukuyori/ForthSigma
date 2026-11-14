//! Source listing presentation and recorded-use diagnostics.
const std = @import("std");
const forth = @import("../forth.zig");
const defs = @import("defs.zig");
const map = @import("memory_map.zig");
const paths = @import("paths.zig");
pub const words = [_]defs.Builtin{ .short_where, .expand_where, .prepend_where, .unused_words };
pub const Style = enum { short, expanded, prepend };
pub fn style(self: *const forth.State) forth.RuntimeError!Style {
    return switch (self.readCellConst(map.where_style_address)) {
        0 => .short,
        1 => .expanded,
        2 => .prepend,
        else => error.InvalidNumber,
    };
}
pub fn execute(self: *forth.State, comptime word: defs.Builtin) forth.RuntimeError!void {
    switch (word) {
        .short_where => try self.writeCell(map.where_style_address, 0),
        .expand_where => try self.writeCell(map.where_style_address, 1),
        .prepend_where => try self.writeCell(map.where_style_address, 2),
        .unused_words => try unused(self),
        else => unreachable,
    }
}
fn unused(self: *forth.State) forth.RuntimeError!void {
    // Saturation means later name uses may have been lost. Match the linter's
    // conservative treatment, rather than incorrectly declaring words unused.
    if (self.use_count == self.uses.len) return error.InvalidDefinition;
    const wid = try self.validWordlist(self.currentWordlist());
    var used: [(map.max_words + 63) / 64]u64 = @splat(0);
    for (self.uses[0..self.use_count]) |use| {
        if (use.word < self.word_count) used[use.word / 64] |= @as(u64, 1) << @intCast(use.word % 64);
    }
    self.write("\n");
    for (self.words[0..self.word_count], 0..) |word, id| {
        if (word.wordlist != wid or word.name_len == 0 or used[id / 64] & (@as(u64, 1) << @intCast(id % 64)) != 0) continue;
        self.write(self.wordName(word));
        self.write(" ");
    }
}

/// Fully qualify ordinary file names without changing cwd or resolving symlinks.
/// Expanded display requires the optional get_dir callback for relative paths.
pub fn expanded(self: *forth.State, name: []const u8) forth.RuntimeError!paths.Buffer {
    const native = try paths.openedName(self, name);
    const text = native.text();
    if (std.mem.indexOfScalar(u8, text, 0) != null) return error.InvalidAddress;
    if (rooted(text)) return native;
    // A drive-relative path requires per-drive cwd state, which this host API does
    // not provide. Do not silently manufacture a different file name.
    if ((text.len >= 2 and text[1] == ':') or std.mem.startsWith(u8, text, "\\")) return error.FileUnavailable;
    const files = try self.fileOps();
    const get = files.get_dir orelse return error.FileUnavailable;
    var result = paths.Buffer{};
    const cwd = get(self.writer.context, &result.bytes);
    if (cwd.ior != 0) return self.throwCode(cwd.ior);
    if (cwd.value >= result.bytes.len or result.bytes[@intCast(cwd.value)] != 0) return error.InvalidAddress;
    result.len = @intCast(cwd.value);
    if (!rooted(result.text()) or std.mem.indexOfScalar(u8, result.text(), 0) != null) return error.InvalidAddress;
    const separator = result.bytes[result.len - 1] != '/' and result.bytes[result.len - 1] != '\\';
    if (@intFromBool(separator) + text.len > result.bytes.len - result.len) return error.StringTooLong;
    if (separator) {
        result.bytes[result.len] = '/';
        result.len += 1;
    }
    @memcpy(result.bytes[result.len..][0..text.len], text);
    result.len += text.len;
    return result;
}
fn rooted(name: []const u8) bool {
    return std.mem.startsWith(u8, name, "/") or std.mem.startsWith(u8, name, "\\\\") or
        (name.len >= 3 and std.ascii.isAlphabetic(name[0]) and name[1] == ':' and (name[2] == '/' or name[2] == '\\'));
}
