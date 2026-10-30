//! Source files: INCLUDE, REQUIRE, the file table, and LOCATE.

const std = @import("std");
const defs = @import("defs.zig");
const forth = @import("../forth.zig");
const memory_map = @import("memory_map.zig");
const Cell = memory_map.Cell;
const IncludeFrame = defs.IncludeFrame;
const InputPlace = defs.InputPlace;
const RuntimeError = defs.RuntimeError;
const State = forth.State;
const UCell = memory_map.UCell;
const include_buffer_base = memory_map.include_buffer_base;
const max_include_depth = memory_map.max_include_depth;
const max_source_files = memory_map.max_source_files;
const source_file_count_address = memory_map.source_file_count_address;
const source_file_entry_size = memory_map.source_file_entry_size;
const source_file_loaded_flags = memory_map.source_file_loaded_flags;
const source_file_table = memory_map.source_file_table;
const tib_size = memory_map.tib_size;

pub fn storeSourceName(self: *State, address: Cell, name: []const u8) void {
    const start: usize = @intCast(address);
    @memcpy(self.memory[start .. start + name.len], name);
}

pub fn currentFileFrame(self: *State) ?IncludeFrame {
    if (self.source_kind != .file or self.include_depth == 0) return null;
    return self.include_stack[self.include_depth - 1];
}

pub fn sourceFileCount(self: *State) usize {
    const count = self.readCell(source_file_count_address) catch unreachable;
    return @intCast(std.math.clamp(count, 0, max_source_files));
}

pub fn setSourceFileCount(self: *State, count: usize) void {
    self.writeCell(source_file_count_address, @intCast(count)) catch unreachable;
}

pub fn sourceFileEntry(index: usize) usize {
    return @intCast(source_file_table + @as(Cell, @intCast(index * source_file_entry_size)));
}

pub fn sourceFileName(self: *const State, index: usize) []const u8 {
    const at = sourceFileEntry(index);
    return self.memory[at + 1 .. at + 1 + self.memory[at]];
}

pub fn sourceFileLoadedFlag(index: usize) usize {
    return @intCast(source_file_loaded_flags + @as(Cell, @intCast(index)));
}

pub fn sourceFileLoaded(self: *const State, index: usize) bool {
    return self.memory[sourceFileLoadedFlag(index)] != 0;
}

pub fn setSourceFileLoaded(self: *State, index: usize, loaded: bool) void {
    self.memory[sourceFileLoadedFlag(index)] = @intFromBool(loaded);
}

pub fn findSourceEntry(self: *State, name: []const u8) ?u8 {
    for (0..self.sourceFileCount()) |index| {
        if (std.mem.eql(u8, self.sourceFileName(index), name)) return @intCast(index);
    }
    return null;
}

/// The table entry of a file in the REQUIRE history, or null when it is not loaded.
pub fn findSourceFile(self: *State, name: []const u8) ?u8 {
    const index = self.findSourceEntry(name) orelse return null;
    return if (self.sourceFileLoaded(index)) index else null;
}

/// The table entry for `name`, added when the name is new. Entries are never removed.
pub fn sourceFileEntryIndex(self: *State, name: []const u8) RuntimeError!u8 {
    if (self.findSourceEntry(name)) |index| return index;
    if (name.len >= source_file_entry_size) return error.StringTooLong;
    const count = self.sourceFileCount();
    if (count == max_source_files) return error.TooManySourceFiles;
    const at = sourceFileEntry(count);
    self.memory[at] = @intCast(name.len);
    @memcpy(self.memory[at + 1 .. at + 1 + name.len], name);
    self.setSourceFileLoaded(count, false);
    self.setSourceFileCount(count + 1);
    return @intCast(count);
}

/// Records an included file in the REQUIRE history.
pub fn recordSourceFile(self: *State, name: []const u8) RuntimeError!u8 {
    const index = try self.sourceFileEntryIndex(name);
    self.setSourceFileLoaded(index, true);
    return index;
}

/// The loaded flags as one bit per table entry, which a MARKER keeps in its value.
pub fn loadedSourceFiles(self: *const State) UCell {
    var mask: UCell = 0;
    const count: usize = @intCast(std.math.clamp(self.readCellConst(source_file_count_address), 0, max_source_files));
    for (0..count) |index| {
        if (self.sourceFileLoaded(index)) mask |= @as(UCell, 1) << @intCast(index);
    }
    return mask;
}

/// MARKER: the REQUIRE history returns to what it was when the marker was made.
pub fn restoreLoadedSourceFiles(self: *State, mask: UCell) void {
    for (0..self.sourceFileCount()) |index| self.setSourceFileLoaded(index, mask & (@as(UCell, 1) << @intCast(index)) != 0);
}

/// Reads the next physical line of the innermost included file into its line buffer,
/// or returns null at the end of the file.
pub fn readIncludeLine(self: *State) RuntimeError!?[]const u8 {
    const frame = &self.include_stack[self.include_depth - 1];
    const files = try self.fileOps();
    // One byte more than a line may hold shows whether the host stopped at a line end.
    var chunk: [tib_size + 1]u8 = undefined;
    const position = files.position(self.writer.context, frame.fileid);
    if (position.ior == 0) frame.line_start = position.value;
    const result = files.read_line(self.writer.context, frame.fileid, &chunk);
    if (result.ior != 0) return self.throwCode(result.ior);
    if (!result.found) return null;
    frame.line += 1;
    if (result.length > tib_size) return error.StringTooLong;
    const start: usize = @intCast(include_buffer_base + @as(Cell, @intCast((self.include_depth - 1) * tib_size)));
    @memcpy(self.memory[start .. start + result.length], chunk[0..result.length]);
    return self.memory[start .. start + result.length];
}

/// INCLUDED: interprets a source file line by line. The file is recorded in the
/// REQUIRE history when it opens (as gforth does), closed on every exit path, and an
/// error inside it is reported with the file name and line.
pub fn saveInputPlace(self: *State) InputPlace {
    const id: Cell, const mark: Cell, const number: Cell = switch (self.source_kind) {
        .terminal => .{ 0, self.sourceLineAddress(), self.input_line_serial },
        .evaluate => .{ -1, self.sourceLineAddress(), self.input_line_serial },
        .file => blk: {
            const frame = self.include_stack[self.include_depth - 1];
            break :blk .{ frame.fileid, @bitCast(frame.line_start), frame.line };
        },
    };
    return .{ .id = id, .cursor = @intCast(self.sourceCursor()), .mark = mark, .number = number };
}

/// Goes back to a saved place; false if it is not in this source. A file reads the
/// saved line again; the terminal and an EVALUATE string go back within the same line.
pub fn restoreInputPlace(self: *State, place: InputPlace) RuntimeError!bool {
    const current: Cell = switch (self.source_kind) {
        .terminal => 0,
        .evaluate => -1,
        .file => self.include_stack[self.include_depth - 1].fileid,
    };
    if (place.id != current or place.cursor < 0) return false;
    switch (self.source_kind) {
        .terminal, .evaluate => {
            // The terminal buffer holds each new line, so the line's number tells them apart.
            if (place.mark != self.sourceLineAddress() or place.number != self.input_line_serial) return false;
        },
        .file => {
            const frame = &self.include_stack[self.include_depth - 1];
            const files = try self.fileOps();
            if (place.number < 1 or files.reposition(self.writer.context, frame.fileid, @bitCast(place.mark)) != 0) return false;
            frame.line = @intCast(place.number - 1);
            self.source_line = try self.readIncludeLine() orelse return false;
        },
    }
    self.setSourceCursor(@intCast(place.cursor));
    return true;
}

pub fn includeFile(self: *State, name: []const u8) RuntimeError!void {
    if (self.include_depth == max_include_depth) return error.IncludeNesting;
    if (name.len >= source_file_entry_size) return error.StringTooLong;
    // The name may lie in a line buffer that the include overwrites.
    var name_copy: [source_file_entry_size - 1]u8 = undefined;
    @memcpy(name_copy[0..name.len], name);
    const file_name = name_copy[0..name.len];
    const files = try self.fileOps();
    const opened = files.open(self.writer.context, file_name, .read_only, false);
    if (opened.ior != 0) return self.throwCode(opened.ior);
    return self.includeOpenFile(@bitCast(opened.value), file_name);
}

/// Interprets a file that is open already, then closes it: INCLUDED after opening it,
/// and INCLUDE-FILE, whose file has no name (it is recorded as `*file*`).
pub fn includeOpenFile(self: *State, fileid: Cell, file_name: []const u8) RuntimeError!void {
    if (self.include_depth == max_include_depth) return error.IncludeNesting;
    const files = try self.fileOps();
    const file_index = self.recordSourceFile(file_name) catch |err| {
        _ = files.close(self.writer.context, fileid);
        return err;
    };
    self.include_stack[self.include_depth] = .{ .fileid = fileid, .file_index = file_index, .line = 0 };
    self.include_depth += 1;
    const result = self.interpretIncludedFile();
    const last_line = self.include_stack[self.include_depth - 1].line;
    self.include_depth -= 1;
    const closed = files.close(self.writer.context, fileid);
    try result;
    if (closed != 0) {
        // The file is out of the input stack now, so name it here.
        if (self.error_location == null) self.error_location = .{ .file_index = file_index, .line = last_line };
        return self.throwCode(closed);
    }
}

pub fn interpretIncludedFile(self: *State) RuntimeError!void {
    // The innermost file records where an error happened, before its frame goes away.
    errdefer if (self.error_location == null) {
        const frame = self.include_stack[self.include_depth - 1];
        self.error_location = .{ .file_index = frame.file_index, .line = frame.line };
    };
    const was_defining = self.defining;
    const word_before = self.current_word;
    const pending_before = self.pending;
    while (!self.halted) {
        const line = try self.readIncludeLine() orelse break;
        try self.interpretSource(line, .file);
    }
    if (self.halted) return;
    // A definition or parsing word started in this file must end in it. Comparing the
    // word also catches a file that ends the caller's definition and starts another.
    const started_here = self.defining and (!was_defining or self.current_word != word_before);
    if (started_here or (self.pending != .none and pending_before == .none)) return error.InvalidDefinition;
}

pub fn requireFile(self: *State, name: []const u8) RuntimeError!void {
    if (self.findSourceFile(name) == null) try self.includeFile(name);
}

/// LOCATE: prints where a word was defined and the lines of its definition.
pub fn locateWord(self: *State, id: u16) RuntimeError!void {
    const word = self.words[id];
    if (word.source_file == 0 or word.source_file > self.sourceFileCount()) {
        self.write(self.wordName(word));
        self.write(": NO FILE INFORMATION\n");
        return;
    }
    const name = self.sourceFileName(word.source_file - 1);
    var line_text: [24]u8 = undefined;
    self.write(name);
    self.write(std.fmt.bufPrint(&line_text, ":{d}\n", .{word.source_line}) catch unreachable);
    const files = try self.fileOps();
    const opened = files.open(self.writer.context, name, .read_only, false);
    if (opened.ior != 0) return;
    const fileid: Cell = @bitCast(opened.value);
    defer _ = files.close(self.writer.context, fileid);
    const last = @min(word.source_end_line, word.source_line + 19);
    var chunk: [tib_size + 1]u8 = undefined;
    var number: u32 = 0;
    while (number < last) {
        var result = files.read_line(self.writer.context, fileid, &chunk);
        if (result.ior != 0 or !result.found) return;
        // An over-long line comes in several pieces; count it as one physical line.
        const too_long = result.length > tib_size;
        while (result.length > tib_size) {
            result = files.read_line(self.writer.context, fileid, &chunk);
            if (result.ior != 0 or !result.found) return;
        }
        number += 1;
        if (too_long) continue;
        if (number >= word.source_line) {
            self.write(chunk[0..result.length]);
            self.write("\n");
        }
    }
}

/// The width of a WHERE line, as gforth's when its output is not a terminal.
const where_columns = 80;

/// WHERE: lists the recorded uses of a word as gforth does. Each line gives the place,
/// the source line without its leading blanks, cut or padded to 80 columns, and the
/// number of the use. A tab is written as it is, as gforth writes it.
pub fn listUses(self: *State, id: u16) RuntimeError!void {
    var number: usize = 0;
    for (0..self.use_count) |at| {
        const use = self.uses[at];
        if (use.word != id) continue;
        const name = self.sourceFileName(use.file_index);
        var place_text: [48]u8 = undefined;
        const place = std.fmt.bufPrint(&place_text, ":{d}:{d}: ", .{ use.line, use.column }) catch unreachable;
        var number_text: [24]u8 = undefined;
        const digits = std.fmt.bufPrint(&number_text, "{d}", .{number}) catch unreachable;
        const limit = where_columns -| digits.len;
        // As in gforth, each line starts with a newline, and the last one ends without.
        self.write("\n");
        self.write(name);
        self.write(place);
        var width = textColumns(name) + place.len;
        var chunk: [tib_size + 1]u8 = undefined;
        if (try readFileLine(self, name, use.line, &chunk)) |line| {
            const text = std.mem.trimStart(u8, line, " \t");
            // When the place alone is wider than the line, gforth writes all of the text.
            if (width > limit) self.write(text) else width = writeColumns(self, text, width, limit);
        }
        while (width < limit) : (width += 1) self.write(" ");
        self.write(digits);
        number += 1;
    }
}

/// Reads line `wanted` (counting from 1) of the named file into the buffer, or gives
/// null when the file cannot be read that far.
fn readFileLine(self: *State, name: []const u8, wanted: u32, buffer: *[tib_size + 1]u8) RuntimeError!?[]const u8 {
    const files = try self.fileOps();
    const opened = files.open(self.writer.context, name, .read_only, false);
    if (opened.ior != 0) return null;
    const fileid: Cell = @bitCast(opened.value);
    defer _ = files.close(self.writer.context, fileid);
    var number: u32 = 0;
    while (true) {
        var result = files.read_line(self.writer.context, fileid, buffer);
        if (result.ior != 0 or !result.found) return null;
        // An over-long line comes in several pieces; count it as one physical line.
        const too_long = result.length > tib_size;
        while (result.length > tib_size) {
            result = files.read_line(self.writer.context, fileid, buffer);
            if (result.ior != 0 or !result.found) return null;
        }
        number += 1;
        if (number == wanted) return if (too_long) "" else buffer[0..result.length];
    }
}

/// Writes as much of the text as fits up to column `limit`, starting at column `width`,
/// and returns the column reached. A wide character takes two columns, and a tab goes
/// to the next multiple of 8 counted from the start of the text.
fn writeColumns(self: *State, text: []const u8, start: usize, limit: usize) usize {
    var width = start;
    var at: usize = 0;
    while (at < text.len) {
        const piece = characterAt(text, at);
        const step = if (text[at] == '\t') 8 - (width - start) % 8 else piece.columns;
        if (width + step > limit) break;
        self.write(text[at .. at + piece.length]);
        width += step;
        at += piece.length;
    }
    return width;
}

fn textColumns(text: []const u8) usize {
    var width: usize = 0;
    var at: usize = 0;
    while (at < text.len) {
        const piece = characterAt(text, at);
        width += piece.columns;
        at += piece.length;
    }
    return width;
}

/// The UTF-8 character at `at`: its length in bytes and its width in columns. A byte
/// that does not start a valid character counts as one column.
fn characterAt(text: []const u8, at: usize) struct { length: usize, columns: usize } {
    const length = std.unicode.utf8ByteSequenceLength(text[at]) catch return .{ .length = 1, .columns = 1 };
    if (at + length > text.len) return .{ .length = 1, .columns = 1 };
    const code = std.unicode.utf8Decode(text[at .. at + length]) catch return .{ .length = 1, .columns = 1 };
    return .{ .length = length, .columns = if (isWide(code)) 2 else 1 };
}

/// East Asian wide and fullwidth characters, which a terminal shows in two columns.
fn isWide(code: u21) bool {
    const ranges = [_][2]u21{
        .{ 0x1100, 0x115F }, .{ 0x2E80, 0x303E }, .{ 0x3041, 0x33FF }, .{ 0x3400, 0x4DBF },
        .{ 0x4E00, 0x9FFF }, .{ 0xA000, 0xA4CF }, .{ 0xAC00, 0xD7A3 }, .{ 0xF900, 0xFAFF },
        .{ 0xFE30, 0xFE4F }, .{ 0xFF00, 0xFF60 }, .{ 0xFFE0, 0xFFE6 }, .{ 0x1F300, 0x1F64F },
        .{ 0x1F900, 0x1F9FF }, .{ 0x20000, 0x3FFFD },
    };
    for (ranges) |range| {
        if (code >= range[0] and code <= range[1]) return true;
    }
    return false;
}

/// Address in logical memory of the current input position.
pub fn sourceAddress(self: *State) Cell {
    return @intCast(@intFromPtr(self.source_line.ptr) - @intFromPtr(&self.memory) + self.sourceCursor());
}
