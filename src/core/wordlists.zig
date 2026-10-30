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
    var i = self.word_count;
    while (i > 0) {
        i -= 1;
        const word = self.words[i];
        if (word.wordlist == wid and word.name_len != 0 and asciiEqlIgnoreCase(word.name[0..word.name_len], name)) return i;
    }
    return null;
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
            if (word.kind == kind and word.value == wid and word.name_len != 0) return self.write(word.name[0..word.name_len]);
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
