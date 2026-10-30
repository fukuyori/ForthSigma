//! Dictionary search, word list, and search order words.

const std = @import("std");
const defs = @import("defs.zig");
const forth = @import("../forth.zig");
const memory_map = @import("memory_map.zig");
const Builtin = defs.Builtin;
const Cell = memory_map.Cell;
const RuntimeError = defs.RuntimeError;
const State = forth.State;
const current_wordlist_address = memory_map.current_wordlist_address;
const forth_wordlist = memory_map.forth_wordlist;
const marker_snapshot_size = memory_map.marker_snapshot_size;
const max_name = memory_map.max_name;
const max_search_order = memory_map.max_search_order;
const max_stack = memory_map.max_stack;
const max_wordlists = memory_map.max_wordlists;
const name_buffer_base = memory_map.name_buffer_base;
const name_buffer_count = memory_map.name_buffer_count;
const root_wordlist = memory_map.root_wordlist;
const wordlist_count_address = memory_map.wordlist_count_address;

/// The built-in words this file executes; executeBuiltin dispatches by this list.
pub const words = [_]Builtin{
    .words, .find_word, .find_name, .name_to_int, .name_to_string, .see, .marker, .locate, .only,
    .also, .previous, .forth, .definitions, .order, .get_order, .set_order, .to_order, .get_current,
    .set_current, .wordlist, .vocabulary, .forth_wordlist_word, .search_wordlist,
};

pub fn execute(self: *State, comptime builtin: Builtin) RuntimeError!void {
    switch (builtin) {
        .words => {
            // Like gforth, WORDS lists the word list that is searched first.
            const wid = if (self.searchOrderDepth() == 0) forth_wordlist else self.searchOrderEntry(0);
            for (self.words[0..self.word_count]) |word| {
                if (word.name_len == 0 or word.wordlist != wid) continue;
                self.write(word.name[0..word.name_len]);
                self.write(" ");
            }
            self.write("\n");
        },
        .find_word => {
            const address = try self.pop();
            const at = try self.memoryAddress(address, 1);
            const length = self.memory[at];
            _ = try self.memoryAddress(address + 1, length);
            if (self.lookup(self.memory[at + 1 .. at + 1 + length])) |id| {
                try self.push(id);
                try self.push(if (self.words[id].immediate) 1 else -1);
            } else {
                try self.push(address);
                try self.push(0);
            }
        },
        .find_name => {
            const name = try self.memoryRange();
            try self.push(if (self.lookup(name)) |id| @as(Cell, id) + 1 else 0);
        },
        .name_to_int => try self.push(try self.validNameToken(try self.pop())),
        .name_to_string => {
            const word = self.words[try self.validNameToken(try self.pop())];
            const slot = name_buffer_base + @as(Cell, @intCast(self.name_buffer_index)) * (max_name + 1);
            self.name_buffer_index = (self.name_buffer_index + 1) % name_buffer_count;
            const start: usize = @intCast(slot);
            @memcpy(self.memory[start .. start + word.name_len], word.name[0..word.name_len]);
            try self.push(slot);
            try self.push(word.name_len);
        },
        .see => {
            const name = (try self.nextSourceToken()) orelse return error.InputUnavailable;
            try self.seeWord(try self.lookupOrFail(name));
        },
        .marker => {
            const name = (try self.nextSourceToken()) orelse return error.InvalidDefinition;
            const id = try self.appendDataWord(name, .marker, marker_snapshot_size);
            try self.snapshotMarker(self.words[id].value);
        },
        .locate => {
            const name = (try self.nextSourceToken()) orelse return error.InputUnavailable;
            try self.locateWord(try self.lookupOrFail(name));
        },
        .only => self.setSearchOrder(&.{ root_wordlist, root_wordlist }),
        .also, .previous, .forth => {
            var order: [max_search_order]Cell = undefined;
            const current = self.searchOrder(&order);
            switch (builtin) {
                .also => {
                    if (current.len == 0) return error.SearchOrderUnderflow;
                    if (current.len == max_search_order) return error.SearchOrderOverflow;
                    std.mem.copyBackwards(Cell, order[1 .. current.len + 1], order[0..current.len]);
                    self.setSearchOrder(order[0 .. current.len + 1]);
                },
                .previous => {
                    if (current.len == 0) return error.SearchOrderUnderflow;
                    self.setSearchOrder(current[1..]);
                },
                else => {
                    if (current.len == 0) self.setSearchOrder(&.{forth_wordlist}) else {
                        current[0] = forth_wordlist;
                        self.setSearchOrder(current);
                    }
                },
            }
        },
        .definitions => {
            if (self.searchOrderDepth() == 0) return error.SearchOrderUnderflow;
            try self.writeCell(current_wordlist_address, self.searchOrderEntry(0));
        },
        .order => {
            for (0..self.searchOrderDepth()) |index| {
                self.writeWordlistName(self.searchOrderEntry(index));
                self.write(" ");
            }
            self.write("    ");
            self.writeWordlistName(self.currentWordlist());
            self.write(" ");
        },
        .get_order => {
            const depth = self.searchOrderDepth();
            if (max_stack - self.data_depth < depth + 1) return error.StackOverflow;
            var index = depth;
            while (index > 0) {
                index -= 1;
                try self.push(self.searchOrderEntry(index));
            }
            try self.push(@intCast(depth));
        },
        .set_order => {
            const count = try self.pop();
            if (count == -1) {
                self.setSearchOrder(&.{ root_wordlist, root_wordlist });
                return;
            }
            if (count < 0) return error.SearchOrderUnderflow;
            if (count > max_search_order) return error.SearchOrderOverflow;
            const depth: usize = @intCast(count);
            try self.requireDepth(depth);
            var order: [max_search_order]Cell = undefined;
            for (0..depth) |index| order[index] = try self.validWordlist(try self.peek(index));
            self.data_depth -= depth;
            self.setSearchOrder(order[0..depth]);
        },
        .to_order => {
            const wid = try self.validWordlist(try self.pop());
            var order: [max_search_order]Cell = undefined;
            const current = self.searchOrder(&order);
            if (current.len == max_search_order) return error.SearchOrderOverflow;
            std.mem.copyBackwards(Cell, order[1 .. current.len + 1], order[0..current.len]);
            order[0] = wid;
            self.setSearchOrder(order[0 .. current.len + 1]);
        },
        .get_current => try self.push(self.currentWordlist()),
        .set_current => try self.writeCell(current_wordlist_address, try self.validWordlist(try self.pop())),
        .wordlist, .vocabulary => {
            const count = self.wordlistCount();
            if (count == max_wordlists) return error.DictionaryFull;
            const wid = count + 1;
            if (builtin == .vocabulary) {
                const name = (try self.nextSourceToken()) orelse return error.InvalidDefinition;
                _ = try self.appendWord(name, .vocabulary, .drop, wid);
            } else try self.push(wid);
            try self.writeCell(wordlist_count_address, wid);
        },
        .forth_wordlist_word => try self.push(forth_wordlist),
        .search_wordlist => {
            const wid = try self.validWordlist(try self.pop());
            const name = try self.memoryRange();
            if (self.lookupIn(name, wid)) |id| {
                try self.push(id);
                try self.push(if (self.words[id].immediate) 1 else -1);
            } else try self.push(0);
        },
        else => @compileError(@tagName(builtin) ++ " is not in the words of this file"),
    }
}
