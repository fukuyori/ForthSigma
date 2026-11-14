//! Public name tokens and scoped definition/search-list extensions.
const std = @import("std");
const forth = @import("../forth.zig");
const defs = @import("defs.zig");
const map = @import("memory_map.zig");
const lists = @import("wordlists.zig");
pub const words = [_]defs.Builtin{ .dot_id, .dot_voc, .compile_only_query, .context_address, .cs_vocabulary, .cs_wordlist, .current_address, .find_name_in, .in_vocabulary, .in_wordlist, .latest_nt, .map_vocs, .mwords, .name_to_link, .nextname, .obsolete_query, .root_vocabulary, .seal, .table_wordlist, .vlist, .vocs, .wordlist_words, .xt_to_name };
fn displayWords(self: *forth.State, wid: map.Cell, pattern: ?[]const u8) void {
    // Keep Sigma WORDS ordering and layout; MWORDS is also oldest first.
    const count = self.word_count;
    for (self.words[0..count]) |entry| {
        const name = self.wordName(entry);
        if (entry.wordlist != wid or name.len == 0) continue;
        if (pattern) |p| if (std.mem.indexOf(u8, name, p) == null) continue;
        self.write(name);
        self.write(" ");
    }
    self.write("\n");
}
fn oneShot(self: *forth.State, wid: map.Cell) forth.RuntimeError!void {
    const token = (try self.nextSourceToken()) orelse return error.InvalidDefinition;
    const xt = try self.lookupOrFail(token);
    const old = self.currentWordlist();
    try self.writeCell(map.current_wordlist_address, wid);
    defer self.writeCell(map.current_wordlist_address, old) catch unreachable;
    try self.executeWord(xt);
}
pub fn execute(self: *forth.State, comptime word: defs.Builtin) forth.RuntimeError!void {
    switch (word) {
        .dot_id, .compile_only_query, .obsolete_query, .name_to_link => {
            try self.requireDepth(1);
            const id = try self.validNameToken(try self.peek(0));
            switch (word) {
                .dot_id => {
                    self.data_depth -= 1;
                    self.write(self.wordName(self.words[id]));
                    self.write(" ");
                },
                .compile_only_query => self.data_stack[self.data_depth - 1] = if (self.words[id].compile_only) -1 else 0,
                .obsolete_query => self.data_stack[self.data_depth - 1] = 0,
                .name_to_link => {
                    const wid = self.words[id].wordlist;
                    var previous: usize = id;
                    var nt: map.Cell = 0;
                    while (previous > 0) {
                        previous -= 1;
                        if (self.words[previous].wordlist == wid and self.words[previous].name_len != 0) {
                            nt = @intCast(previous + 1);
                            break;
                        }
                    }
                    self.data_stack[self.data_depth - 1] = nt;
                },
                else => unreachable,
            }
        },
        .latest_nt => try self.push(@as(map.Cell, self.latestWord()) + 1),
        .xt_to_name => {
            try self.requireDepth(1);
            const id = try self.wordId(try self.peek(0));
            self.data_stack[self.data_depth - 1] = @as(map.Cell, self.synonymTarget(id)) + 1;
        },
        .current_address => try self.push(map.current_wordlist_address),
        .context_address => try self.push(map.search_order_address),
        .find_name_in => {
            try self.requireDepth(3);
            const wid = try self.validWordlist(try self.peek(0));
            const n = std.math.cast(usize, @max(try self.peek(1), 0)) orelse return error.InvalidAddress;
            const at = try self.memoryAddress(try self.peek(2), n);
            const id = self.lookupIn(self.memory[at..][0..n], wid);
            if (id) |found| self.recordUse(found);
            self.data_depth -= 2;
            self.data_stack[self.data_depth - 1] = if (id) |found| @as(map.Cell, found) + 1 else 0;
        },
        .nextname => {
            try self.requireDepth(2);
            const length = try self.peek(0);
            if (length < 0 or length > map.max_name) return error.NameTooLong;
            const n: usize = @intCast(length);
            const at = try self.memoryAddress(try self.peek(1), n);
            @memcpy(self.next_name[0..n], self.memory[at..][0..n]);
            self.next_name_len = @intCast(n);
            self.noname_next = true;
            self.data_depth -= 2;
        },
        .cs_wordlist, .cs_vocabulary, .table_wordlist => {
            const count = self.wordlistCount();
            if (count < map.ekeys_wordlist or count >= map.max_wordlists) return error.DictionaryFull;
            const wid = count + 1;
            if (word == .cs_vocabulary) {
                const name = (try @import("quotations.zig").definitionName(self)) orelse return error.InvalidDefinition;
                _ = try self.appendWord(name, .vocabulary, .drop, wid);
            } else try self.push(wid);
            try self.writeCell(map.wordlist_count_address, wid);
            const bit = @as(map.UCell, 1) << @intCast(wid - 1);
            try self.writeCell(map.case_wordlists_address, @bitCast(@as(map.UCell, @bitCast(self.readCellConst(map.case_wordlists_address))) | bit));
            if (word == .table_wordlist) try self.writeCell(map.silent_wordlists_address, @bitCast(@as(map.UCell, @bitCast(self.readCellConst(map.silent_wordlists_address))) | bit));
        },
        .in_wordlist => {
            const wid = try self.validWordlist(try self.pop());
            try oneShot(self, wid);
        },
        .in_vocabulary => {
            const token = (try self.nextSourceToken()) orelse return error.InvalidDefinition;
            const id = self.synonymTarget(try self.lookupOrFail(token));
            if (self.words[id].kind != .vocabulary) return error.InvalidDefinition;
            try oneShot(self, try self.validWordlist(self.words[id].value));
        },
        .root_vocabulary => {
            var order: [map.max_search_order]map.Cell = undefined;
            const current = self.searchOrder(&order);
            if (current.len == 0) self.setSearchOrder(&.{map.root_wordlist}) else {
                current[0] = map.root_wordlist;
                self.setSearchOrder(current);
            }
        },
        .seal => {
            if (self.searchOrderDepth() == 0) return error.SearchOrderUnderflow;
            self.setSearchOrder(&.{try self.validWordlist(self.searchOrderEntry(0))});
        },
        .dot_voc => {
            const wid = try self.validWordlist(try self.pop());
            self.writeWordlistName(wid);
            self.write(" ");
        },
        .vocs, .map_vocs => {
            const xt = if (word == .map_vocs) try self.wordId(try self.pop()) else 0;
            const count = self.wordlistCount();
            if (count < map.ekeys_wordlist or count > map.max_wordlists) return error.InvalidWordlist;
            // Snapshot the bound; lists allocated by callbacks are for the next pass.
            var wid = count;
            while (wid > 0) : (wid -= 1) {
                if (word == .map_vocs) {
                    try self.push(wid);
                    try self.executeWord(xt);
                } else {
                    self.writeWordlistName(wid);
                    self.write(" ");
                }
            }
            if (word == .map_vocs) {
                try self.push(map.macros_wordlist);
                try self.executeWord(xt);
            } else self.write("Macros \n");
        },
        .wordlist_words => displayWords(self, try self.validWordlist(try self.pop()), null),
        .vlist, .mwords => {
            const wid = if (self.searchOrderDepth() == 0) map.forth_wordlist else try self.validWordlist(self.searchOrderEntry(0));
            var cursor = self.sourceCursor();
            const pattern = if (word == .mwords) forth.State.nextToken(self.source_line, &cursor) else null;
            if (word == .mwords) self.setSourceCursor(cursor);
            displayWords(self, wid, pattern);
        },
        else => unreachable,
    }
}
