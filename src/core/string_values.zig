//! String-valued data words with owned heap storage and borrowed execution results.
const std = @import("std");
const defs = @import("defs.zig");
const forth = @import("../forth.zig");
const map = @import("memory_map.zig");
const strings = @import("dynamic_strings.zig");
const registry = @import("address_registry.zig");
const RuntimeError = defs.RuntimeError;
const State = forth.State;
pub const words = [_]defs.Builtin{.define_string_value};
pub fn execute(self: *State, comptime builtin: defs.Builtin) RuntimeError!void {
    _ = builtin;
    try self.runDefiningWord(.define_string_value);
}
pub fn define(self: *State, name: []const u8, source: map.Cell, count: map.Cell) RuntimeError!void {
    const length = std.math.cast(usize, count) orelse return error.InvalidAddress;
    _ = try self.memoryAddress(source, length);
    try registry.ensureRoom(self, .memory, self.data_here);
    const old_words = self.word_count;
    const old_names = self.names_used;
    const old_here = self.data_here;
    const old_created = self.last_created_word;
    const id = try self.appendDataWord(name, .string_value, 8);
    errdefer {
        registry.discardRange(self, old_here, self.data_here, .data, false);
        registry.forgetWords(self, old_words);
        self.word_count = old_words;
        self.names_used = old_names;
        self.data_here = old_here;
        self.last_created_word = old_created;
        @import("wordlists.zig").rebuildIndex(self);
    }
    try self.writeCell(self.words[id].value, 0);
    try strings.storeString(self, source, length, self.words[id].value);
}
pub fn fetch(self: *State, owner: map.Cell) RuntimeError!void {
    if (self.data_depth > self.data_stack.len - 2) return error.StackOverflow;
    const text = try self.fetchString(owner);
    try self.push(text.address);
    try self.push(@intCast(text.length));
}
pub fn store(self: *State, id: u16, append: bool) RuntimeError!void {
    try self.requireDepth(2);
    const source = try self.peek(1);
    const length = std.math.cast(usize, try self.peek(0)) orelse return error.InvalidAddress;
    _ = try self.memoryAddress(source, length);
    const owner = self.words[id].value;
    if (append) {
        const old = try self.fetchString(owner);
        try self.insertString(owner, old.length, source, length, false);
    } else try strings.storeString(self, source, length, owner);
    self.data_depth -= 2;
}
