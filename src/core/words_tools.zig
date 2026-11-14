//! The rest of gforth's words that FORTH/Sigma takes (#417): text substitution
//! (SUBSTITUTE, REPLACES, UNESCAPE, $SUBSTITUTE, $UNESCAPE), the tools for names and
//! debugging (LATEST, LATESTXT, >NAME, ID., .NAME, ALIAS, ~~, ASSERT( ), EMIT?, and
//! (LOCAL). Their behavior follows gforth 0.7.9; EMIT?, which gforth lacks, follows the
//! standard.

const std = @import("std");
const registry = @import("address_registry.zig");
const strings = @import("dynamic_strings.zig");
const defs = @import("defs.zig");
const forth = @import("../forth.zig");
const memory_map = @import("memory_map.zig");
const truth = @import("integer_math.zig").truth;
const Builtin = defs.Builtin;
const Cell = memory_map.Cell;
const RuntimeError = defs.RuntimeError;
const State = forth.State;
const cell_size = memory_map.cell_size;
const errno_no_memory = memory_map.errno_no_memory;
const max_name = memory_map.max_name;
const macros = @import("macro_substitute.zig");
const assert_message_address = memory_map.assert_message_address;
const tmp_string_base = memory_map.tmp_string_base;
const tmp_string_count = memory_map.tmp_string_count;

/// The built-in words this file executes; executeBuiltin dispatches by this list.
pub const words = [_]Builtin{
    .substitute,     .replaces,   .unescape,      .string_substitute, .string_unescape, .latest,
    .latestxt,       .to_name,    .id_dot,        .alias,             .debug_tilde,     .debug_tilde_run,
    .assert_paren,   .assert_run, .emit_question, .paren_local,       .macros_wordlist, .define_replacer,
    .dot_substitute,
};

/// The THROW code of SUBSTITUTE when the result does not fit (as gforth gives).
const substitute_overflow: Cell = -78;

pub fn execute(self: *State, comptime builtin: Builtin) RuntimeError!void {
    switch (builtin) {
        // REPLACES ( c-addr1 u1 c-addr2 u2 -- ): %name% (c-addr2 u2) stands for the text
        // c-addr1 u1 in SUBSTITUTE. A name given again takes its new text.
        .replaces => try macros.replaces(self),
        .macros_wordlist => try self.push(memory_map.macros_wordlist),
        .define_replacer => try self.runDefiningWord(.define_replacer),
        .dot_substitute => {
            const source = try self.memoryRange();
            try self.push(try macros.print(self, source));
        },
        .substitute => {
            const room = try self.popLength();
            const buffer = try self.pop();
            const source = try self.memoryRange();
            _ = try self.memoryAddress(buffer, room);
            const result = try macros.capture(self, source);
            defer result.free(self);
            // Revalidate: a callback may have changed host/heap state.
            const out_at = try self.memoryAddress(buffer, room);
            const length = @min(result.length, room);
            @memmove(self.memory[out_at..][0..length], result.bytes(self)[0..length]);
            registry.written(self, buffer, length, false);
            try self.push(buffer);
            try self.push(@intCast(length));
            try self.push(if (result.length > room) substitute_overflow else result.count);
        },
        .string_substitute => {
            const source = try self.memoryRange();
            if (self.data_depth > self.data_stack.len - 3) return error.StackOverflow;
            const result = try macros.capture(self, source);
            errdefer result.free(self);
            // Callbacks can rotate the temporary slots, so reserve the final slot now.
            const slot = tmp_string_base + @as(Cell, @intCast(self.tmp_string_index % tmp_string_count)) * cell_size;
            try strings.preparePointer(self, slot);
            try self.push(try takeSlot(self, result.buffer));
            try self.push(@intCast(result.length));
            try self.push(result.count);
        },
        // UNESCAPE ( c-addr1 u1 c-addr2 -- c-addr2 u2 ): the text with each % doubled, so
        // that SUBSTITUTE gives it back.
        .unescape => {
            const buffer = try self.pop();
            const source = try self.memoryRange();
            const length = unescapedLength(source);
            const out_at = try self.memoryAddress(buffer, length);
            const input = try Input.of(self, source, out_at, length);
            defer input.free(self);
            unescapeInto(input.bytes, self.memory[out_at..][0..length]);
            registry.written(self, buffer, length, false);
            try self.push(buffer);
            try self.push(@intCast(length));
        },
        // $UNESCAPE ( c-addr1 u1 -- c-addr2 u2 ): the same, into a string of its own.
        .string_unescape => {
            const source = try self.memoryRange();
            const length = unescapedLength(source);
            const buffer = try newString(self, length);
            unescapeInto(source, try stringBytes(self, buffer, length));
            try self.push(try takeSlot(self, buffer));
            try self.push(@intCast(length));
        },
        // LATEST ( -- nt ): the name token of the newest word, 0 when the newest
        // definition has no name (:NONAME).
        .latest => {
            const last = self.latestWord();
            try self.push(if (self.words[last].name_len == 0) 0 else @as(Cell, last) + 1);
        },
        // LATESTXT ( -- xt ): the execution token of the newest definition, with or
        // without a name.
        .latestxt => try self.push(self.latestWord()),
        // >NAME ( xt -- nt | 0 ): the name token of the word with that execution token.
        .to_name => {
            const xt = try self.pop();
            const named = xt >= 0 and xt < self.word_count and self.words[@intCast(xt)].name_len != 0;
            try self.push(if (named) xt + 1 else 0);
        },
        // ID. and .NAME ( nt -- ): the name, and a space.
        .id_dot => {
            const id = try self.validNameToken(try self.pop());
            self.write(self.wordName(self.words[id]));
            self.write(" ");
        },
        // ALIAS ( xt "name" -- ): name does what xt does, and ' name gives xt; it is not
        // immediate, even when xt's word is.
        .alias => {
            const target = self.synonymTarget(try self.wordId(try self.pop()));
            const name = (try @import("quotations.zig").definitionName(self)) orelse return error.InvalidDefinition;
            _ = try self.appendWord(name, .synonym, .drop, target);
        },
        // ~~ ( -- ): shows on standard error where it is (file:line:column:) and the data
        // stack, when the definition runs, or at once outside one.
        .debug_tilde => {
            var place: [max_name + 64]u8 = undefined;
            const text = try placeText(self, &place, 2);
            if (self.compiling) {
                try self.compileCountedString(text, .string_literal);
                try self.compileCall(@intCast(self.builtinWord(.debug_tilde_run)));
            } else try showPlace(self, text, null);
        },
        .debug_tilde_run => {
            const place = try self.memoryRange();
            var copy: [max_name + 64]u8 = undefined;
            const length = @min(place.len, copy.len);
            @memcpy(copy[0..length], place[0..length]);
            try showPlace(self, copy[0..length], null);
        },
        // ASSERT( code ) ( -- ): the code up to ) must leave true; when it leaves false,
        // where the ) is (file:line:column: failed assertion) is shown and THROW -2 with
        // "assertion failed" follows.
        .assert_paren => {
            const line = self.source_line;
            const start = self.sourceCursor();
            const close = std.mem.indexOfScalarPos(u8, line, start, ')') orelse return error.InvalidDefinition;
            self.setSourceCursor(close + 1);
            var place: [max_name + 64]u8 = undefined;
            const text = try placeText(self, &place, 1);
            var code: [512]u8 = undefined;
            if (close - start > code.len) return error.StringTooLong;
            @memcpy(code[0 .. close - start], line[start..close]);
            const cursor = self.sourceCursor();
            try self.interpretSource(code[0 .. close - start], .evaluate);
            self.setSourceCursor(cursor);
            if (self.compiling) {
                try self.compileCountedString(text, .string_literal);
                try self.compileCall(@intCast(self.builtinWord(.assert_run)));
            } else {
                try self.push(try placeAddress(self, text));
                try self.push(@intCast(text.len));
                try assertRun(self);
            }
        },
        .assert_run => try assertRun(self),
        // EMIT? ( -- flag ): whether EMIT can go on without waiting; it always can here.
        .emit_question => try self.push(truth(true)),
        // (LOCAL) ( c-addr u -- ): while a definition is compiled, declares a local
        // variable of that name; 0 0 ends the declarations. The first name declared takes
        // the top of the stack, as with LOCALS|.
        .paren_local => {
            if (!self.defining) return error.CompileOnly;
            const length = try self.popLength();
            const address = try self.pop();
            if (length == 0) return;
            const at = try self.memoryAddress(address, length);
            var name: [max_name]u8 = undefined;
            if (length > max_name) return error.NameTooLong;
            @memcpy(name[0..length], self.memory[at..][0..length]);
            // Its store is compiled at once: the first declared takes the top of the stack,
            // and the declarations work without 0 0 too, as in gforth.
            const local = try self.addLocal(name[0..length], .cell, false);
            try self.compileLocalInitialization(&.{local});
        },
        else => unreachable,
    }
}

/// The input of UNESCAPE: the string itself, or a copy in the heap when
/// the output (out_length bytes at out_at) overlaps it.
const Input = struct {
    bytes: []const u8,
    copy: ?Cell,

    fn of(self: *State, source: []const u8, out_at: usize, out_length: usize) RuntimeError!Input {
        const start = @intFromPtr(source.ptr) - @intFromPtr(self.memory.ptr);
        const overlaps = source.len != 0 and out_length != 0 and start < out_at + out_length and out_at < start + source.len;
        if (!overlaps) return .{ .bytes = source, .copy = null };
        const copy = try self.heapAllocate(source.len) orelse return self.throwIor(errno_no_memory);
        const at = try self.memoryAddress(copy, source.len);
        @memmove(self.memory[at..][0..source.len], source);
        return .{ .bytes = self.memory[at..][0..source.len], .copy = copy };
    }

    fn free(input: Input, self: *State) void {
        if (input.copy) |copy| _ = self.heapFree(copy) catch {};
    }
};

fn unescapedLength(text: []const u8) usize {
    return text.len + std.mem.count(u8, text, "%");
}

fn unescapeInto(text: []const u8, out: []u8) void {
    var at: usize = 0;
    for (text) |c| {
        out[at] = c;
        at += 1;
        if (c == '%') {
            out[at] = '%';
            at += 1;
        }
    }
}

/// A new string of `length` bytes in the heap (its length cell, then the bytes).
fn newString(self: *State, length: usize) RuntimeError!Cell {
    const slot = tmp_string_base + @as(Cell, @intCast(self.tmp_string_index % tmp_string_count)) * cell_size;
    try strings.preparePointer(self, slot);
    const size = std.math.add(usize, cell_size, length) catch return self.throwIor(errno_no_memory);
    const buffer = try self.heapAllocate(size) orelse return self.throwIor(errno_no_memory);
    try self.writeCell(buffer, @intCast(length));
    return buffer;
}

/// Makes a new string the next of $TMP's, freeing the one that was there (after the new
/// one is made, which may have been read from it), and gives its bytes' address.
fn takeSlot(self: *State, buffer: Cell) RuntimeError!Cell {
    const slot = tmp_string_base + @as(Cell, @intCast(self.tmp_string_index % tmp_string_count)) * cell_size;
    self.tmp_string_index += 1;
    try self.freeString(slot);
    try self.writeCell(slot, buffer);
    try strings.registerPointer(self, slot);
    return buffer + cell_size;
}

fn stringBytes(self: *State, buffer: Cell, length: usize) RuntimeError![]u8 {
    const at = try self.memoryAddress(buffer + cell_size, length);
    return self.memory[at..][0..length];
}

/// "file:line:column:" of the word that ends `back` characters before >IN.
pub fn placeText(self: *State, buffer: []u8, back: usize) RuntimeError![]const u8 {
    const name: []const u8 = if (self.currentFileFrame()) |frame|
        self.sourceFileName(frame.file_index)
    else if (self.source_kind == .evaluate) memory_map.evaluate_source_name else memory_map.terminal_source_name;
    const line: Cell = if (self.currentFileFrame()) |frame| frame.line else 0;
    // >IN is past the blank that ended the word, when one did.
    var end = self.sourceCursor();
    if (end > 0 and end <= self.source_line.len and std.ascii.isWhitespace(self.source_line[end - 1])) end -= 1;
    const column = end + 1 - back;
    const shown = name[0..@min(name.len, buffer.len - 48)];
    return std.fmt.bufPrint(buffer, "{s}:{d}:{d}:", .{ shown, line, column }) catch return error.StringTooLong;
}

/// The place text in logical memory, for (ASSERT) run outside a definition.
fn placeAddress(self: *State, text: []const u8) RuntimeError!Cell {
    const buffer = try newString(self, text.len);
    @memcpy(try stringBytes(self, buffer, text.len), text);
    return takeSlot(self, buffer);
}

/// ~~'s line on standard error: the place and the data stack, as <n> #a #b, and after
/// them `name for the value that a TO of a ~~VALUE is about to change.
pub fn showPlace(self: *State, place: []const u8, name: ?[]const u8) RuntimeError!void {
    var line: [256]u8 = undefined;
    writeError(self, std.fmt.bufPrint(&line, "\n{s}<{d}> ", .{ place, self.data_depth }) catch place);
    for (self.data_stack[0..self.data_depth]) |value| {
        writeError(self, std.fmt.bufPrint(&line, "#{d} ", .{value}) catch "");
    }
    if (name) |text| {
        writeError(self, "`");
        writeError(self, text);
        writeError(self, " ");
    }
    writeError(self, "\n");
}

pub fn writeError(self: *State, bytes: []const u8) void {
    if (self.writer.file_ops) |files| {
        _ = files.write(self.writer.context, memory_map.stderr_fileid, bytes);
    } else self.write(bytes);
}

/// (ASSERT) ( flag c-addr u -- ): c-addr u is where the assertion is.
fn assertRun(self: *State) RuntimeError!void {
    const place = try self.memoryRange();
    var copy: [max_name + 64]u8 = undefined;
    const length = @min(place.len, copy.len);
    @memcpy(copy[0..length], place[0..length]);
    if (try self.pop() != 0) return;
    self.write(copy[0..length]);
    self.write(" failed assertion");
    return abortWith(self, "assertion failed");
}

/// THROW -2 with `message` as its text, as an ABORT" would have it.
pub fn abortWith(self: *State, comptime message: []const u8) RuntimeError {
    const at = self.memoryAddress(assert_message_address, message.len + 1) catch |err| return err;
    self.memory[at] = message.len;
    @memcpy(self.memory[at + 1 ..][0..message.len], message);
    @import("address_registry.zig").written(self, @intCast(at), message.len + 1, false);
    self.abort_message = assert_message_address;
    return self.throwCode(-2);
}
