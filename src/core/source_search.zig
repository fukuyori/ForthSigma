//! Non-owning, bounded snapshots of WHERE/BROWSE result sets.
const std = @import("std");
const forth = @import("../forth.zig");
const defs = @import("defs.zig");
const map = @import("memory_map.zig");
const navigation = @import("source_navigation.zig");
const input = @import("source_input.zig");
const editor = @import("source_editor.zig");
pub const words = [_]defs.Builtin{ .where_select, .where_next, .where_back, .browse };
pub const Search = struct {
    kind: enum { none, uses, definitions } = .none,
    generation: u64 = 0,
    limit: usize = 0,
    count: usize = 0,
    current: ?usize = null,
    target: u16 = 0,
    wordlist: map.Cell = 0,
    pattern: [map.max_name]u8 = undefined,
    length: usize = 0,
    last_file: ?usize = null,
};

pub fn beginUses(self: *forth.State, id: u16) void {
    self.source_search = .{ .kind = .uses, .generation = self.image_generation, .limit = self.use_count, .target = id };
    for (self.uses[0..self.use_count]) |use| if (use.word == id) {
        self.source_search.count += 1;
    };
}
fn matches(self: *forth.State, id: usize) bool {
    const query = &self.source_search;
    const word = self.words[id];
    const name = self.wordName(word);
    return word.wordlist == query.wordlist and name.len != 0 and std.mem.indexOf(u8, name, query.pattern[0..query.length]) != null;
}

pub fn execute(self: *forth.State, comptime word: defs.Builtin) forth.RuntimeError!void {
    switch (word) {
        .browse => try browse(self),
        .where_select => {
            const index = try self.peek(0);
            if (index < 0) return error.InvalidNumber;
            _ = try self.pop();
            try choose(self, std.math.cast(usize, index), editor.takeDestination(self));
        },
        .where_next, .where_back => {
            if (self.source_search.generation != self.image_generation) self.source_search = .{};
            const query = &self.source_search;
            const index: ?usize = if (query.current) |current|
                (if (word == .where_next) (if (current + 1 < query.count) current + 1 else null) else (if (current != 0) current - 1 else null))
            else if (query.count != 0)
                (if (word == .where_next) 0 else query.count - 1)
            else
                null;
            try choose(self, index, editor.takeDestination(self));
        },
        else => unreachable,
    }
}

fn browse(self: *forth.State) forth.RuntimeError!void {
    const pattern = (try self.nextSourceToken()) orelse return error.InputUnavailable;
    if (pattern.len > map.max_name) return error.NameTooLong;
    var query = Search{ .kind = .definitions, .generation = self.image_generation, .limit = self.word_count, .wordlist = if (self.searchOrderDepth() == 0) map.forth_wordlist else self.searchOrderEntry(0) };
    @memcpy(query.pattern[0..pattern.len], pattern);
    query.length = pattern.len;
    self.source_search = query;
    for (0..query.limit) |id| {
        if (!matches(self, id)) continue;
        const word = self.words[id];
        const number = self.source_search.count;
        self.source_search.count += 1;
        if (word.source_file != 0 and word.source_file <= self.sourceFileCount() and word.source_line != 0) {
            try input.listLocation(self, word.source_file - 1, word.source_line, 1, number);
        } else {
            self.source_search.last_file = null;
            self.write("\n");
            self.write(self.wordName(word));
            self.write(": NO FILE INFORMATION ");
            var text: [24]u8 = undefined;
            self.write(std.fmt.bufPrint(&text, "{d}", .{number}) catch unreachable);
        }
    }
}

fn choose(self: *forth.State, requested: ?usize, destination: editor.Destination) forth.RuntimeError!void {
    if (self.source_search.generation != self.image_generation) self.source_search = .{};
    const query = &self.source_search;
    const index = requested orelse return noResult(self);
    if (index >= query.count) return noResult(self);
    var number: usize = 0;
    switch (query.kind) {
        .uses => for (self.uses[0..query.limit]) |use| {
            if (use.word != query.target) continue;
            if (number == index) {
                query.current = index;
                navigation.select(self, use.file_index, use.line);
                return showSelected(self, destination);
            }
            number += 1;
        },
        .definitions => for (0..query.limit) |id| {
            if (!matches(self, id)) continue;
            if (number == index) {
                query.current = index;
                const word = self.words[id];
                if (word.source_file == 0) return noLocation(self);
                navigation.select(self, word.source_file - 1, word.source_line);
                return showSelected(self, destination);
            }
            number += 1;
        },
        .none => {},
    }
    return noResult(self);
}
fn showSelected(self: *forth.State, destination: editor.Destination) forth.RuntimeError!void {
    if (self.source_navigation.length == 0) return navigation.noLocation(self);
    if (destination == .editor) try editor.open(self) else try navigation.execute(self, .source_l);
}
fn noLocation(self: *forth.State) forth.RuntimeError!void {
    self.source_navigation.length = 0;
    return navigation.noLocation(self);
}
fn noResult(self: *forth.State) forth.RuntimeError!void {
    self.source_search.current = null;
    return noLocation(self);
}
