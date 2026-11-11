//! The words of gforth's coverage.fs: how often each part of the code ran. The parts
//! are the basic blocks, as in gforth: the code after the name of a colon definition,
//! after IF, ELSE, THEN, BEGIN, WHILE, REPEAT, UNTIL, AGAIN, DO, ?DO, LOOP, +LOOP,
//! CASE, OF, ENDOF, ENDCASE, and DOES>, and from the start of each further line of a
//! definition. The place of a block is that of the blank after the word that starts
//! it (column 1 for a line), where .COVERAGE puts its count.
//!
//! gforth counts what is loaded after `require coverage.fs`; here the option
//! --coverage at the start says so. With it, an operation that does nothing is
//! compiled where a block starts (`markBlock` in forth.zig), and the loop that counts
//! operations counts it. A build with -Ddebug=false has none of this.
//!
//!     .COVER-RAW   file:line:column: count, one block on a line
//!     COV%         the part of the blocks that ran at least once, as 88.8% coverage
//!     .COVERAGE    the files, with ( count) after the word that starts each block

const std = @import("std");
const defs = @import("defs.zig");
const forth = @import("../forth.zig");
const memory_map = @import("memory_map.zig");
const words_tools = @import("words_tools.zig");
const Cell = memory_map.Cell;
const RuntimeError = defs.RuntimeError;
const State = forth.State;
const tib_size = memory_map.tib_size;

/// The counts, or the error of a run that keeps none.
fn counts(self: *State) RuntimeError!*const forth.Profile {
    if (!self.cover_blocks) return words_tools.abortWith(self, "no coverage: start with --coverage");
    return self.profile orelse words_tools.abortWith(self, "no coverage: start with --coverage");
}

/// A colon definition whose blocks are shown: one of a file of the user's (the
/// libraries that come with FORTH/Sigma have names in asterisks).
fn isShown(self: *State, word: defs.Word) bool {
    if (word.kind != .colon or word.source_file == 0) return false;
    if (word.code_end < word.code_start or word.code_end > self.code_count) return false;
    const file = self.sourceFileName(word.source_file - 1);
    return file.len != 0 and file[0] != '*';
}

/// .COVER-RAW ( -- ): each block as `file:line:column: count`.
pub fn coverRaw(self: *State) RuntimeError!void {
    const profile = try counts(self);
    for (self.words[self.builtin_count..self.word_count]) |word| {
        if (!isShown(self, word)) continue;
        const file = self.sourceFileName(word.source_file - 1);
        for (word.code_start..word.code_end) |pc| {
            const column = self.code_columns[pc];
            if (column == 0) continue;
            var text: [96]u8 = undefined;
            self.write(file);
            self.write(std.fmt.bufPrint(&text, ":{d}:{d}: {d} \n", .{ self.code_lines[pc], column, profile.op_counts[pc] }) catch unreachable);
        }
    }
}

/// COV% ( -- ): the part of the blocks that ran, in tenths of a percent, cut off as
/// gforth cuts it (8 of 9 blocks are 88.8%).
pub fn covPercent(self: *State) RuntimeError!void {
    const profile = try counts(self);
    var blocks: u64 = 0;
    var ran: u64 = 0;
    for (self.words[self.builtin_count..self.word_count]) |word| {
        if (!isShown(self, word)) continue;
        for (word.code_start..word.code_end) |pc| {
            if (self.code_columns[pc] == 0) continue;
            blocks += 1;
            if (profile.op_counts[pc] != 0) ran += 1;
        }
    }
    // Without a block there is nothing that did not run.
    const tenths = if (blocks == 0) 1000 else ran * 1000 / blocks;
    var text: [48]u8 = undefined;
    self.write(std.fmt.bufPrint(&text, "{d}.{d}% coverage", .{ tenths / 10, tenths % 10 }) catch unreachable);
}

/// The counts of the blocks of one line, by their columns.
const LineCounts = struct {
    columns: [32]u16 = undefined,
    counts: [32]u64 = undefined,
    len: usize = 0,

    fn add(self: *LineCounts, column: u16, count: u64) void {
        if (self.len == self.columns.len) return;
        // In the order of the columns.
        var at = self.len;
        while (at > 0 and self.columns[at - 1] > column) : (at -= 1) {
            self.columns[at] = self.columns[at - 1];
            self.counts[at] = self.counts[at - 1];
        }
        self.columns[at] = column;
        self.counts[at] = count;
        self.len += 1;
    }
};

/// .COVERAGE ( -- ): the text of each file that has blocks, with ` ( count) ` put in
/// after the word that starts each block, as gforth's BW-COVER form shows it.
pub fn coverage(self: *State) RuntimeError!void {
    const profile = try counts(self);
    const files = try self.fileOps();
    for (0..self.sourceFileCount()) |file_index| {
        const name = self.sourceFileName(file_index);
        if (name.len == 0 or name[0] == '*' or !hasBlocks(self, file_index)) continue;
        const opened = files.open(self.writer.context, name, .read_only, false);
        if (opened.ior != 0) continue;
        const fileid: Cell = @bitCast(opened.value);
        defer _ = files.close(self.writer.context, fileid);
        self.write("\n");
        var chunk: [tib_size + 1]u8 = undefined;
        var number: u32 = 0;
        while (true) {
            var result = files.read_line(self.writer.context, fileid, &chunk);
            if (result.ior != 0 or !result.found) break;
            // An over-long line comes in several pieces; it is one line, shown as it
            // is read.
            const too_long = result.length > tib_size;
            while (result.length > tib_size) {
                self.write(chunk[0..tib_size]);
                result = files.read_line(self.writer.context, fileid, &chunk);
                if (result.ior != 0 or !result.found) break;
            }
            number += 1;
            const line = chunk[0..@min(result.length, tib_size)];
            if (too_long) {
                self.write(line);
                self.write("\n");
                continue;
            }
            var blocks = LineCounts{};
            lineBlocks(self, profile, file_index, number, &blocks);
            var shown: usize = 0;
            for (blocks.columns[0..blocks.len], blocks.counts[0..blocks.len]) |column, count| {
                // The column is that of the blank after the word, counted from 1.
                const at = @min(@as(usize, column) - 1, line.len);
                if (at > shown) {
                    self.write(line[shown..at]);
                    shown = at;
                }
                var text: [32]u8 = undefined;
                self.write(std.fmt.bufPrint(&text, " ( {d}) ", .{count}) catch unreachable);
            }
            self.write(line[shown..]);
            self.write("\n");
        }
    }
}

/// Whether a definition of the file has a block.
fn hasBlocks(self: *State, file_index: usize) bool {
    for (self.words[self.builtin_count..self.word_count]) |word| {
        if (!isShown(self, word) or word.source_file - 1 != file_index) continue;
        for (word.code_start..word.code_end) |pc| {
            if (self.code_columns[pc] != 0) return true;
        }
    }
    return false;
}

/// The blocks of a line of a file.
fn lineBlocks(self: *State, profile: *const forth.Profile, file_index: usize, line: u32, blocks: *LineCounts) void {
    for (self.words[self.builtin_count..self.word_count]) |word| {
        if (!isShown(self, word) or word.source_file - 1 != file_index) continue;
        // A definition is on the lines from its first to its last.
        if (line < word.source_line or line > word.source_end_line) continue;
        for (word.code_start..word.code_end) |pc| {
            if (self.code_columns[pc] != 0 and self.code_lines[pc] == line) blocks.add(self.code_columns[pc], profile.op_counts[pc]);
        }
    }
}
