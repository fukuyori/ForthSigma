//! Borrowed string sources, owned file sources, and explicit forward bindings.
const std = @import("std");
const forth = @import("../forth.zig");
const defs = @import("defs.zig");
const map = @import("memory_map.zig");
pub const words = [_]defs.Builtin{ .execute_parsing, .execute_parsing_file, .string_parse, .parse_word, .name_word, .forward_word, .dot_unresolved, .recursive_word };
const Source = struct {
    line: []const u8,
    cursor: map.Cell,
    kind: defs.SourceKind,
    serial: map.Cell,
    blk: map.Cell,
    token_start: usize,
    fn save(self: *forth.State) @This() {
        return .{ .line = self.source_line, .cursor = self.readCellConst(map.in_address), .kind = self.source_kind, .serial = self.input_line_serial, .blk = self.readCellConst(map.blk_address), .token_start = self.token_start };
    }
    fn restore(old: @This(), self: *forth.State) void {
        self.source_line = old.line;
        self.source_kind = old.kind;
        self.input_line_serial = old.serial;
        self.token_start = old.token_start;
        self.writeCell(map.in_address, old.cursor) catch unreachable;
        self.writeCell(map.blk_address, old.blk) catch unreachable;
    }
};
pub fn unresolved(self: *forth.State, name: []const u8, wid: map.Cell) ?u16 {
    const id = self.lookupIn(name, wid) orelse return null;
    const word = self.words[id];
    return if (word.kind == .forward and word.value == -1) id else null;
}
pub fn resolve(self: *forth.State, id: u16) void {
    const word = self.words[id];
    if (word.name_len == 0) return;
    for (self.words[0..id], 0..) |*old, index| {
        if (old.kind != .forward or old.value != -1 or old.wordlist != word.wordlist or !(if (word.wordlist == map.macros_wordlist) std.mem.eql(u8, self.wordName(old.*), self.wordName(word)) else std.ascii.eqlIgnoreCase(self.wordName(old.*), self.wordName(word)))) continue;
        old.value = id;
        for (self.code[0..self.code_count]) |*op| {
            if ((op.kind == .call or op.kind == .compile_call) and op.value == index) op.value = id;
        }
    }
}
pub fn forgetTargets(self: *forth.State, removed: u16) void {
    for (self.words[0..@min(removed, self.word_count)], 0..) |*old, index| {
        if (old.kind != .forward or old.value < removed) continue;
        const target = old.value;
        old.value = -1;
        for (self.code[0..self.code_count]) |*op| {
            if ((op.kind == .call or op.kind == .call_colon or op.kind == .compile_call) and op.value == target) {
                if (op.kind == .call_colon) op.kind = .call;
                op.value = @intCast(index);
            }
        }
    }
}
pub fn execute(self: *forth.State, comptime word: defs.Builtin) forth.RuntimeError!void {
    switch (word) {
        .parse_word, .name_word => try self.executeBuiltin(.parse_name),
        .recursive_word => {
            if (!self.defining or !self.compiling) return error.CompileOnly;
        },
        .forward_word => {
            const name = (try @import("quotations.zig").definitionName(self)) orelse return error.InvalidDefinition;
            if (name.len == 0) return error.InvalidDefinition;
            _ = try self.appendWord(name, .forward, .drop, -1);
        },
        .dot_unresolved => {
            var i = self.word_count;
            while (i > self.builtin_count) {
                i -= 1;
                const entry = self.words[i];
                if (entry.kind == .forward and entry.value == -1) {
                    @import("words_tools.zig").writeError(self, self.wordName(entry));
                    @import("words_tools.zig").writeError(self, " is unresolved\n");
                }
            }
        },
        .string_parse => {
            try self.requireDepth(2);
            const n = std.math.cast(usize, @max(try self.peek(0), 0)) orelse return error.InvalidAddress;
            const at = try self.memoryAddress(try self.peek(1), n);
            const delimiter = self.memory[at..][0..n];
            const rest = self.remainingSource();
            const length = if (n == 0) 0 else std.mem.indexOf(u8, rest, delimiter) orelse rest.len;
            const address = self.sourceAddress();
            self.setSourceCursor(self.sourceCursor() + length + if (n != 0 and length < rest.len) n else @as(usize, 0));
            self.data_stack[self.data_depth - 2] = address;
            self.data_stack[self.data_depth - 1] = @intCast(length);
        },
        .execute_parsing => {
            try self.requireDepth(3);
            const xt = try self.wordId(try self.peek(0));
            const n = std.math.cast(usize, @max(try self.peek(1), 0)) orelse return error.InvalidAddress;
            const at = try self.memoryAddress(try self.peek(2), n);
            const old = Source.save(self);
            defer old.restore(self);
            self.source_line = self.memory[at..][0..n];
            self.source_kind = .evaluate;
            self.setSourceCursor(0);
            self.token_start = 0;
            self.numberInputLine();
            try self.writeCell(map.blk_address, 0);
            self.data_depth -= 3;
            try self.executeWord(xt);
        },
        .execute_parsing_file => {
            try self.requireDepth(2);
            const xt = try self.wordId(try self.peek(0));
            const id = try self.peek(1);
            const files = try self.fileOps();
            if (self.include_depth == map.max_include_depth) return error.IncludeNesting;
            const file_index = try self.sourceFileEntryIndex("*file*");
            const old = Source.save(self);
            defer old.restore(self);
            self.include_stack[self.include_depth] = .{ .fileid = id, .file_index = file_index, .line = 0 };
            self.include_depth += 1;
            defer self.include_depth -= 1;
            errdefer if (self.error_location == null) {
                const frame = self.include_stack[self.include_depth - 1];
                self.error_location = .{ .file_index = frame.file_index, .line = frame.line };
            };
            self.source_line = self.memory[0..0];
            self.source_kind = .file;
            self.setSourceCursor(0);
            self.token_start = 0;
            self.numberInputLine();
            try self.writeCell(map.blk_address, 0);
            self.data_depth -= 2;
            var owned = true;
            defer if (owned) {
                _ = files.close(self.writer.context, id);
            };
            try self.executeWord(xt);
            const ior = files.close(self.writer.context, id);
            owned = false;
            if (ior != 0) return self.throwCode(ior);
        },
        else => unreachable,
    }
}
