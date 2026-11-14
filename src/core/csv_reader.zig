//! Independent CSV reader using public, behavior-tested field conventions.
const std = @import("std");
const forth = @import("../forth.zig");
const map = @import("memory_map.zig");
const paths = @import("paths.zig");
const Captured = @import("macro_substitute.zig").Captured;
const RuntimeError = forth.RuntimeError;

pub fn read(self: *forth.State) RuntimeError!void {
    try self.requireDepth(3);
    const xt = try self.wordId(try self.peek(0));
    if (self.data_depth == self.data_stack.len) return error.StackOverflow;
    const length = std.math.cast(usize, try self.peek(1)) orelse return error.InvalidAddress;
    const at = try self.memoryAddress(try self.peek(2), length);
    if (self.include_depth == map.max_include_depth) return error.IncludeNesting;
    const files = try self.fileOps();
    var name = paths.Buffer{};
    const opened = if ((try self.fetchString(map.fpath_address)).length != 0) search: {
        const result = try paths.openInPath(self, self.memory[at..][0..length], map.fpath_address);
        name = result.name;
        break :search result.file;
    } else direct: {
        if (length >= map.source_file_entry_size) return error.StringTooLong;
        @memcpy(name.bytes[0..length], self.memory[at..][0..length]);
        name.len = length;
        break :direct files.open(self.writer.context, name.text(), .read_only, false);
    };
    if (opened.ior != 0) return self.throwCode(opened.ior);
    const fileid: forth.Cell = @bitCast(opened.value);
    // READ-CSV records source identity but does not mark a data file REQUIRED.
    const index = self.sourceFileEntryIndex(name.text()) catch |err| {
        _ = files.close(self.writer.context, fileid);
        return err;
    };
    const previous_line = self.source_line;
    const previous_cursor = self.sourceCursor();
    const previous_kind = self.source_kind;
    const previous_serial = self.input_line_serial;
    const previous_blk = self.readCellConst(map.blk_address);
    self.include_stack[self.include_depth] = .{ .fileid = fileid, .file_index = index, .line = 0 };
    self.include_depth += 1;
    self.source_kind = .file;
    self.writeCell(map.blk_address, 0) catch unreachable;
    defer {
        self.include_depth -= 1;
        self.source_line = previous_line;
        self.source_kind = previous_kind;
        self.setSourceCursor(previous_cursor);
        self.input_line_serial = previous_serial;
        self.writeCell(map.blk_address, previous_blk) catch unreachable;
    }
    self.data_depth -= 3;
    const result = run(self, xt);
    if (result) |_| {} else |_| {
        if (self.error_location == null) self.error_location = .{ .file_index = index, .line = self.include_stack[self.include_depth - 1].line };
    }
    const closed = files.close(self.writer.context, fileid);
    try result;
    if (closed != 0) {
        if (self.error_location == null) self.error_location = .{ .file_index = index, .line = self.include_stack[self.include_depth - 1].line };
        return self.throwCode(closed);
    }
}

fn loadLine(self: *forth.State) RuntimeError!?[]const u8 {
    const line = try self.readIncludeLine() orelse return null;
    self.source_line = line;
    self.setSourceCursor(0);
    self.numberInputLine();
    return line;
}

/// Remove adjacent quote pairs within each physical fragment.
fn appendDecoded(self: *forth.State, output: *Captured, bytes: []const u8, quote: forth.Cell) RuntimeError!void {
    var start: usize = 0;
    var i: usize = 0;
    while (i < bytes.len) {
        if (i + 1 < bytes.len and @as(forth.Cell, bytes[i]) == quote and bytes[i + 1] == bytes[i]) {
            try output.put(self, bytes[start .. i + 1]);
            i += 2;
            start = i;
        } else i += 1;
    }
    try output.put(self, bytes[start..]);
}

fn run(self: *forth.State, xt: u16) RuntimeError!void {
    var line = (try loadLine(self)) orelse return;
    var offset: usize = 0;
    var row: forth.Cell = 1;
    var column: forth.Cell = 0;
    while (true) {
        try @import("words_numeric.zig").checkWorkBlock(self);
        const quote = self.readCellConst(map.csv_quote_address);
        const separator = self.readCellConst(map.csv_separator_address);
        var output = Captured{};
        defer output.free(self);
        var fragment = offset;
        var first = true;
        var quoted = offset < line.len and @as(forth.Cell, line[offset]) == quote;
        var inside = false;
        var eof = false;
        while (true) {
            try @import("words_numeric.zig").checkWorkBlock(self);
            var end = offset;
            while (end < line.len) : (end += 1) {
                if (@as(forth.Cell, line[end]) == separator and !inside) break;
                if (quoted and @as(forth.Cell, line[end]) == quote) inside = !inside;
            }
            var begin = fragment;
            if (first and begin < end and @as(forth.Cell, line[begin]) == quote) begin += 1;
            var finish = end;
            if (!inside and finish > begin and @as(forth.Cell, line[finish - 1]) == quote) finish -= 1;
            try appendDecoded(self, &output, line[begin..finish], quote);
            first = false;
            if (!inside) {
                offset = if (end < line.len) end + 1 else end;
                break;
            }
            try output.put(self, "\n");
            line = (try loadLine(self)) orelse {
                eof = true;
                offset = line.len;
                break;
            };
            offset = 0;
            fragment = 0;
            quoted = true;
        }
        if (self.data_stack.len - self.data_depth < 4) return error.StackOverflow;
        // Empty field still borrows a valid private allocation during the callback.
        if (output.buffer == 0) try output.put(self, "");
        try self.push(output.buffer + map.cell_size);
        try self.push(@intCast(output.length));
        try self.push(column);
        try self.push(row);
        try self.executeWord(try self.wordId(xt));
        if (self.halted or eof) return;
        if (offset < line.len) {
            column += 1;
            continue;
        }
        line = (try loadLine(self)) orelse return;
        offset = 0;
        column = 0;
        row += 1;
    }
}
