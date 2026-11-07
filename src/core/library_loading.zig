//! Loading a word group that is not among the built-in words every dictionary starts
//! with: REQUIRE-GRAPHICS and REQUIRE-AUDIO. The first time, the group's vocabulary is
//! appended to the Forth word list, and its built-in words and its library (written in
//! Forth and built into the program) to the vocabulary; later it does nothing. The
//! search order and the current word list stay as they were. When the library fails to
//! load, everything that was added is removed again.

const std = @import("std");
const defs = @import("defs.zig");
const forth = @import("../forth.zig");
const memory_map = @import("memory_map.zig");
const Builtin = defs.Builtin;
const Cell = memory_map.Cell;
const RuntimeError = defs.RuntimeError;
const State = forth.State;
const base_address = memory_map.base_address;
const current_wordlist_address = memory_map.current_wordlist_address;
const forth_wordlist = memory_map.forth_wordlist;
const max_search_order = memory_map.max_search_order;
const max_wordlists = memory_map.max_wordlists;
const wordlist_count_address = memory_map.wordlist_count_address;

/// One word group. `definitions` lists its built-in words, as { name, Builtin }, in the
/// order they are appended: the order is part of the dictionary that images keep.
pub fn Group(comptime Definition: type) type {
    return struct {
        vocabulary: []const u8,
        definitions: []const Definition,
        /// The library's name in the source file table, for LOCATE and error messages.
        library_name: []const u8,
        /// The cell that keeps the vocabulary's word number, and the cell that says the
        /// group was loaded (the image's format then changes).
        vocabulary_address: Cell,
        image_address: Cell,
    };
}

/// Whether the group was loaded and is still in the dictionary (FORGET and MARKER can
/// remove it): its vocabulary, followed by its first built-in word.
pub fn isLoaded(self: *const State, vocabulary_address: Cell, first: Builtin) bool {
    const recorded = self.readCellConst(vocabulary_address);
    // Compared before adding 1, since the cell may hold any value.
    if (recorded < self.builtin_count or recorded >= @as(Cell, self.word_count) - 1) return false;
    const vocabulary = self.words[@intCast(recorded)];
    const word = self.words[@intCast(recorded + 1)];
    return vocabulary.kind == .vocabulary and word.kind == .builtin and word.builtin == first;
}

/// Whether a word is one the group added: one of its built-in words (any built-in word
/// after the start-up dictionary), or a word its library defined (and not a later word
/// of the same name). HELP describes these.
pub fn isGroupWord(self: *const State, word: defs.Word, library_name: []const u8) bool {
    if (word.kind == .builtin) return true;
    const files = self.readCellConst(memory_map.source_file_count_address);
    if (word.source_file == 0 or word.source_file > files) return false;
    return std.mem.eql(u8, self.sourceFileName(word.source_file - 1), library_name);
}

pub fn require(self: *State, comptime group: anytype, library: []const u8) RuntimeError!void {
    if (self.defining) return error.InvalidDefinition;
    if (isLoaded(self, group.vocabulary_address, group.definitions[0][1])) return;
    const wordlists = self.wordlistCount();
    if (wordlists == max_wordlists) return error.DictionaryFull;
    var order_buffer: [max_search_order]Cell = undefined;
    const saved_order = self.searchOrder(&order_buffer);
    var order: [max_search_order]Cell = undefined;
    @memcpy(order[0..saved_order.len], saved_order);
    const depth = saved_order.len;
    const current = self.currentWordlist();
    const loaded_files = self.loadedSourceFiles();
    const first_word = self.word_count;
    const wid = wordlists + 1;
    const pending = self.pending;
    const control_depth = self.control_depth;
    const interpret_loop_depth = self.interpret_loop_depth;
    // The library is written in decimal, whatever BASE the caller has.
    const base = self.readCellConst(base_address);
    self.writeCell(base_address, 10) catch unreachable;
    defer self.writeCell(base_address, base) catch unreachable;

    loadWords(self, group, library, wid) catch |err| {
        // A definition the library started is dropped with the rest, so that the error
        // handling after this does not bring the removed words back.
        if (self.defining) {
            self.defining = false;
            self.setCompiling(false);
            self.local_count = 0;
            self.locals_frame_size = 0;
        }
        self.pending = pending;
        self.control_depth = control_depth;
        self.interpret_loop_depth = interpret_loop_depth;
        if (self.last_created_word) |created| {
            if (created >= first_word) self.last_created_word = null;
        }
        if (self.word_count > first_word) self.forgetFrom(first_word);
        self.writeCell(wordlist_count_address, wordlists) catch unreachable;
        self.writeCell(current_wordlist_address, current) catch unreachable;
        self.setSearchOrder(order[0..depth]);
        self.restoreLoadedSourceFiles(loaded_files);
        return err;
    };
    self.writeCell(current_wordlist_address, current) catch unreachable;
    self.setSearchOrder(order[0..depth]);
    self.writeCell(group.vocabulary_address, first_word) catch unreachable;
    self.writeCell(group.image_address, 1) catch unreachable;
}

fn loadWords(self: *State, comptime group: anytype, library: []const u8, wid: Cell) RuntimeError!void {
    try self.writeCell(current_wordlist_address, forth_wordlist);
    _ = try self.appendWord(group.vocabulary, .vocabulary, .drop, wid);
    try self.writeCell(wordlist_count_address, wid);
    try self.writeCell(current_wordlist_address, wid);
    for (group.definitions) |definition| _ = try self.appendWord(definition[0], .builtin, definition[1], 0);
    // The library defines into the vocabulary and finds the built-in words first.
    var order_buffer: [max_search_order]Cell = undefined;
    const order = self.searchOrder(&order_buffer);
    if (order.len == max_search_order) return error.SearchOrderOverflow;
    var library_order: [max_search_order]Cell = undefined;
    library_order[0] = wid;
    @memcpy(library_order[1 .. order.len + 1], order);
    self.setSearchOrder(library_order[0 .. order.len + 1]);
    try self.includeEmbedded(group.library_name, library);
}
