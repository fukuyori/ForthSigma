//! Reading tokens, names, and strings from the input.

const std = @import("std");
const defs = @import("defs.zig");
const forth = @import("../forth.zig");
const memory_map = @import("memory_map.zig");
const Cell = memory_map.Cell;
const OpKind = defs.OpKind;
const RuntimeError = defs.RuntimeError;
const State = forth.State;
const StringWord = defs.StringWord;
const max_gforth_string = memory_map.max_gforth_string;
const memory_size = memory_map.memory_size;
const string_buffer_base = memory_map.string_buffer_base;
const string_buffer_count = memory_map.string_buffer_count;
const string_buffer_size = memory_map.string_buffer_size;
const tib_address = memory_map.tib_address;
const tib_size = memory_map.tib_size;

/// The rest of the current input line, and whether it lies in logical memory.
pub fn remainingSource(self: *State) []const u8 {
    return self.source_line[self.sourceCursor()..];
}

pub fn sourceInMemory(self: *State) bool {
    const start = @intFromPtr(&self.memory);
    const address = @intFromPtr(self.source_line.ptr);
    return self.source_line.len != 0 and address >= start and address < start + memory_size;
}

pub fn isDelimiter(byte: u8, delimiter: u8) bool {
    return if (delimiter == ' ') isSeparator(byte) else byte == delimiter;
}

/// WORD: skips leading delimiters, then returns the text up to the next delimiter
/// and consumes that delimiter. A blank delimiter also matches tabs and line ends.
pub fn parseWordText(self: *State, delimiter: u8) []const u8 {
    const rest = self.remainingSource();
    var index: usize = 0;
    while (index < rest.len and isDelimiter(rest[index], delimiter)) index += 1;
    const start = index;
    while (index < rest.len and !isDelimiter(rest[index], delimiter)) index += 1;
    const text = rest[start..index];
    if (index < rest.len) index += 1;
    self.setSourceCursor(self.sourceCursor() + index);
    return text;
}

pub fn validNameToken(self: *State, nt: Cell) RuntimeError!u16 {
    if (nt < 1 or nt > self.word_count) return error.InvalidExecutionToken;
    return @intCast(nt - 1);
}

pub fn readInputToken(self: *State, line: *[4096]u8) RuntimeError!?[]const u8 {
    const read_fn = self.writer.read_fn orelse return error.InputUnavailable;
    const input = read_fn(self.writer.context, line) orelse return error.InputUnavailable;
    var cursor: usize = 0;
    const token = nextToken(input, &cursor) orelse {
        self.write(" ?\n");
        return null;
    };
    if (nextToken(input, &cursor) != null) {
        self.write(" ?\n");
        return null;
    }
    return token;
}

/// `token` is `"` or a token starting with `."`; text glued to `."` belongs to the string.
pub fn handleStringToken(self: *State, token: []const u8, input: []const u8, cursor: *usize, immediate: bool) RuntimeError!void {
    var literal: [127]u8 = undefined;
    var length: usize = 0;
    const inline_prefix: []const u8 = if (immediate) token[2..] else &.{};
    const closed_inline = inline_prefix.len > 0 and inline_prefix[inline_prefix.len - 1] == '"';
    if (closed_inline) {
        const content = inline_prefix[0 .. inline_prefix.len - 1];
        if (content.len > literal.len) return error.MemoryExhausted;
        @memcpy(literal[0..content.len], content);
        length = content.len;
    } else {
        if (inline_prefix.len > literal.len) return error.MemoryExhausted;
        @memcpy(literal[0..inline_prefix.len], inline_prefix);
        length = inline_prefix.len;
        // A separator after the glued text is part of the string; the one after a bare
        // token was already consumed by nextToken.
        if (inline_prefix.len > 0 and cursor.* > 0 and isSeparator(input[cursor.* - 1])) {
            if (length == literal.len) return error.MemoryExhausted;
            literal[length] = input[cursor.* - 1];
            length += 1;
        }
        while (cursor.* < input.len and input[cursor.*] != '"') {
            if (length == literal.len) return error.MemoryExhausted;
            literal[length] = input[cursor.*];
            length += 1;
            cursor.* += 1;
        }
        if (cursor.* == input.len) return error.InvalidDefinition;
        cursor.* += 1;
    }
    const bytes = literal[0..length];
    if (!immediate and !self.compiling) return error.CompileOnly;
    if (!immediate or self.compiling) {
        const address = self.data_here;
        try self.reserveData(@intCast(bytes.len + 1));
        const start: usize = @intCast(address);
        self.memory[start] = @intCast(bytes.len);
        @memcpy(self.memory[start + 1 .. start + 1 + bytes.len], bytes);
        _ = try self.emit(.{ .kind = if (immediate) .print_string else .string_literal, .value = address });
    } else self.write(bytes);
}

/// Handles the gforth string words `S"`, `S\"`, `.\"`, and `.(`.
pub fn handleParsedString(self: *State, kind: StringWord, input: []const u8, cursor: *usize) RuntimeError!void {
    var text: [max_gforth_string]u8 = undefined;
    const escapes = kind == .s_escape_quote or kind == .print_escape;
    const bytes = try parseDelimited(input, cursor, if (kind == .print_paren) ')' else '"', escapes, &text);
    switch (kind) {
        .print_paren => self.write(bytes),
        .print_escape => {
            if (self.compiling) try self.compileCountedString(bytes, .print_string) else self.write(bytes);
        },
        // C" and ABORT" are compile-only, as in gforth.
        .c_quote, .abort_quote => {
            if (!self.compiling) return error.CompileOnly;
            try self.compileCountedString(bytes, if (kind == .c_quote) .counted_string else .abort_string);
        },
        .s_quote, .s_escape_quote => {
            if (self.compiling) return self.compileCountedString(bytes, .string_literal);
            const slot = string_buffer_base + @as(Cell, @intCast(self.string_buffer_index * string_buffer_size));
            self.string_buffer_index = (self.string_buffer_index + 1) % string_buffer_count;
            const start: usize = @intCast(slot);
            @memcpy(self.memory[start .. start + bytes.len], bytes);
            try self.push(slot);
            try self.push(@intCast(bytes.len));
        },
    }
}

pub fn compileCountedString(self: *State, bytes: []const u8, kind: OpKind) RuntimeError!void {
    const address = self.data_here;
    try self.reserveData(@intCast(bytes.len + 1));
    const start: usize = @intCast(address);
    self.memory[start] = @intCast(bytes.len);
    @memcpy(self.memory[start + 1 .. start + 1 + bytes.len], bytes);
    _ = try self.emit(.{ .kind = kind, .value = address });
}

/// Reads text after a parsing word up to `delimiter`. The separator after the parsing
/// word itself was consumed with the word.
pub fn parseDelimited(input: []const u8, cursor: *usize, delimiter: u8, escapes: bool, output: []u8) RuntimeError![]const u8 {
    var length: usize = 0;
    while (true) {
        if (cursor.* == input.len) return error.InvalidDefinition;
        var c = input[cursor.*];
        cursor.* += 1;
        if (c == delimiter) break;
        if (escapes and c == '\\') {
            if (cursor.* == input.len) return error.InvalidDefinition;
            const code = input[cursor.*];
            cursor.* += 1;
            c = switch (code) {
                'a' => 7,
                'b' => 8,
                'e' => 27,
                'f' => 12,
                'l', 'n' => '\n',
                'q' => '"',
                'r' => '\r',
                't' => '\t',
                'v' => 11,
                'z' => 0,
                'm' => blk: {
                    if (length == output.len) return error.MemoryExhausted;
                    output[length] = '\r';
                    length += 1;
                    break :blk '\n';
                },
                'x' => blk: {
                    if (input.len - cursor.* < 2) return error.InvalidDefinition;
                    const value = std.fmt.parseInt(u8, input[cursor.* .. cursor.* + 2], 16) catch return error.InvalidDefinition;
                    cursor.* += 2;
                    break :blk value;
                },
                else => code,
            };
        }
        if (length == output.len) return error.MemoryExhausted;
        output[length] = c;
        length += 1;
    }
    return output[0..length];
}

pub fn asciiEqlIgnoreCase(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |left, right| {
        const upper_left = if (left >= 'a' and left <= 'z') left - 'a' + 'A' else left;
        const upper_right = if (right >= 'a' and right <= 'z') right - 'a' + 'A' else right;
        if (upper_left != upper_right) return false;
    }
    return true;
}

/// Token delimiters. Tabs separate tokens as in gforth, so tab-indented sources work.
pub fn isSeparator(byte: u8) bool {
    return byte == ' ' or byte == '\t' or byte == '\r' or byte == '\n';
}

/// Reads the next blank-delimited token and, as gforth does, consumes the one separator
/// that ends it, so PARSE starts right after that separator.
pub fn nextToken(input: []const u8, cursor: *usize) ?[]const u8 {
    while (cursor.* < input.len and isSeparator(input[cursor.*])) cursor.* += 1;
    if (cursor.* == input.len) return null;
    const start = cursor.*;
    while (cursor.* < input.len and !isSeparator(input[cursor.*])) cursor.* += 1;
    const token = input[start..cursor.*];
    if (cursor.* < input.len) cursor.* += 1;
    return token;
}

/// Reads the next token, refilling from the terminal or the file being included when
/// the line is used up. An EVALUATE string never reads past its end.
pub fn nextSourceToken(self: *State) RuntimeError!?[]const u8 {
    while (true) {
        var cursor = self.sourceCursor();
        const token = nextToken(self.source_line, &cursor);
        self.setSourceCursor(cursor);
        if (token) |found| return found;
        const line = switch (self.source_kind) {
            .evaluate => return null,
            .file => try self.readIncludeLine() orelse return null,
            .terminal => blk: {
                const read_fn = self.writer.read_fn orelse return null;
                const start: usize = @intCast(tib_address);
                break :blk read_fn(self.writer.context, self.memory[start .. start + tib_size]) orelse return null;
            },
        };
        self.source_line = line;
        self.setSourceCursor(0);
    }
}
