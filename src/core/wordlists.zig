//! Word lists, the search order, and MARKER snapshots.

const std = @import("std");
const defs = @import("defs.zig");
const forth = @import("../forth.zig");
const memory_map = @import("memory_map.zig");
const text_input = @import("text_input.zig");
const Cell = memory_map.Cell;
const RuntimeError = defs.RuntimeError;
const State = forth.State;
const UCell = memory_map.UCell;
const WordKind = defs.WordKind;
const asciiEqlIgnoreCase = text_input.asciiEqlIgnoreCase;
const cell_size = memory_map.cell_size;
const current_wordlist_address = memory_map.current_wordlist_address;
const forth_wordlist = memory_map.forth_wordlist;
const max_search_order = memory_map.max_search_order;
const root_wordlist = memory_map.root_wordlist;
const search_order_address = memory_map.search_order_address;
const search_order_depth_address = memory_map.search_order_depth_address;
const wordlist_count_address = memory_map.wordlist_count_address;

/// Finds a word through the search order, first-searched list first.
pub fn lookup(self: *State, name: []const u8) ?u16 {
    var order: [max_search_order]Cell = undefined;
    const entries = self.searchOrder(&order);
    for (entries, 0..) |wid, index| {
        // A list that appears earlier in the order was already searched.
        if (std.mem.indexOfScalar(Cell, entries[0..index], wid) != null) continue;
        if (self.lookupIn(name, wid)) |id| return id;
    }
    return null;
}

/// Finds the newest word named `name` in one word list.
pub fn lookupIn(self: *State, name: []const u8, wid: Cell) ?u16 {
    var id = self.name_heads[nameBucket(name)];
    while (id != no_word) : (id = self.name_next[id]) {
        const word = self.words[id];
        if (word.wordlist == wid and word.name_len != 0 and asciiEqlIgnoreCase(self.wordName(word), name)) return id;
    }
    return null;
}

// The index of the names: a hash table whose buckets are chains of word numbers, newest
// first, so that a chain gives the words of a name in the order the dictionary would
// be searched. Every word is in it, also one without a name. Word numbers are below
// 65535, so that value ends a chain.

pub const name_buckets = 1 << 14;
pub const no_word: u16 = std.math.maxInt(u16);

comptime {
    if (memory_map.max_words > no_word) @compileError("word numbers must stay below the end of a chain");
}

/// The bucket of a name; names that differ only in the case of ASCII letters share one,
/// as lookup does not tell them apart (FNV-1a of the upper-case bytes).
pub fn nameBucket(name: []const u8) usize {
    var hash: u32 = 2166136261;
    for (name) |byte| {
        hash ^= std.ascii.toUpper(byte);
        hash *%= 16777619;
    }
    return hash & (name_buckets - 1);
}

/// Puts word `id`, the newest word, at the head of its name's chain.
pub fn indexWord(self: *State, id: u16) void {
    const bucket = nameBucket(self.wordName(self.words[id]));
    self.name_next[id] = self.name_heads[bucket];
    self.name_heads[bucket] = id;
}

/// Takes word `id` and every later word out of the index, newest first, so that each
/// is the head of its chain when it goes.
pub fn unindexFrom(self: *State, id: u16) void {
    var word = self.word_count;
    while (word > id) {
        word -= 1;
        const bucket = nameBucket(self.wordName(self.words[word]));
        if (self.name_heads[bucket] == word) self.name_heads[bucket] = self.name_next[word];
    }
}

/// Makes the index again for the whole dictionary, after an image replaced or added words.
pub fn rebuildIndex(self: *State) void {
    @memset(&self.name_heads, no_word);
    for (0..self.word_count) |id| indexWord(self, @intCast(id));
}

pub fn wordlistCount(self: *State) Cell {
    return self.readCell(wordlist_count_address) catch unreachable;
}

pub fn validWordlist(self: *State, wid: Cell) RuntimeError!Cell {
    if (wid < forth_wordlist or wid > self.wordlistCount()) return error.InvalidWordlist;
    return wid;
}

pub fn currentWordlist(self: *State) Cell {
    return self.readCell(current_wordlist_address) catch unreachable;
}

pub fn searchOrderDepth(self: *State) usize {
    const depth = self.readCell(search_order_depth_address) catch unreachable;
    return @intCast(std.math.clamp(depth, 0, max_search_order));
}

pub fn searchOrderEntry(self: *State, index: usize) Cell {
    return self.readCell(search_order_address + @as(Cell, @intCast(index)) * cell_size) catch unreachable;
}

/// Sets the search order; `order[0]` is searched first.
pub fn setSearchOrder(self: *State, order: []const Cell) void {
    for (order, 0..) |wid, index| self.writeCell(search_order_address + @as(Cell, @intCast(index)) * cell_size, wid) catch unreachable;
    self.writeCell(search_order_depth_address, @intCast(order.len)) catch unreachable;
}

pub fn searchOrder(self: *State, buffer: *[max_search_order]Cell) []Cell {
    const depth = self.searchOrderDepth();
    for (0..depth) |index| buffer[index] = self.searchOrderEntry(index);
    return buffer[0..depth];
}

/// Writes a word list's name for ORDER: Forth and Root, the name of a VOCABULARY,
/// or of a constant holding the id (as gforth shows `WORDLIST CONSTANT X`), else the id.
pub fn writeWordlistName(self: *State, wid: Cell) void {
    if (wid == forth_wordlist) return self.write("Forth");
    if (wid == root_wordlist) return self.write("Root");
    for ([_]WordKind{ .vocabulary, .constant }) |kind| {
        var i = self.word_count;
        while (i > self.builtin_count) {
            i -= 1;
            const word = &self.words[i];
            if (word.kind == kind and word.value == wid and word.name_len != 0) return self.write(self.wordName(word.*));
        }
    }
    self.writeNumberDecimal(wid);
}

pub fn snapshotMarker(self: *State, address: Cell) RuntimeError!void {
    try self.writeCell(address, @bitCast(self.loadedSourceFiles()));
    try self.writeCell(address + cell_size, self.currentWordlist());
    const depth = self.searchOrderDepth();
    try self.writeCell(address + 2 * cell_size, @intCast(depth));
    // Unused slots are cleared, since the data area may hold old values.
    for (0..max_search_order) |index| try self.writeCell(address + @as(Cell, @intCast(3 + index)) * cell_size, if (index < depth) self.searchOrderEntry(index) else 0);
}

/// MARKER: restores the REQUIRE history, the current list, and the search order.
pub fn restoreMarker(self: *State, address: Cell) RuntimeError!void {
    const mask: UCell = @bitCast(try self.readCell(address));
    const current = try self.readCell(address + cell_size);
    const depth: usize = @intCast(std.math.clamp(try self.readCell(address + 2 * cell_size), 0, max_search_order));
    var order: [max_search_order]Cell = undefined;
    for (0..depth) |index| order[index] = try self.readCell(address + @as(Cell, @intCast(3 + index)) * cell_size);
    self.restoreLoadedSourceFiles(mask);
    try self.writeCell(current_wordlist_address, current);
    self.setSearchOrder(order[0..depth]);
}
