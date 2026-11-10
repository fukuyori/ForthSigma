//! The debugging words taken from gforth (+LTRACE, -LTRACE, ONCE, ~~BT, ~~1BT, ~~VALUE)
//! and the trace of --trace. A build with -Ddebug=false has none of them. Their output
//! goes to standard error, as that of ~~ does.

const std = @import("std");
const defs = @import("defs.zig");
const forth = @import("../forth.zig");
const memory_map = @import("memory_map.zig");
const error_reporting = @import("error_reporting.zig");
const words_tools = @import("words_tools.zig");
const truth = @import("integer_math.zig").truth;
const Builtin = defs.Builtin;
const Cell = memory_map.Cell;
const RuntimeError = defs.RuntimeError;
const State = forth.State;
const cell_size = memory_map.cell_size;
const max_name = memory_map.max_name;

/// The built-in words this file executes; executeBuiltin dispatches by this list.
pub const words = [_]Builtin{
    .ltrace_on, .ltrace_off, .once, .once_run, .debug_tilde_bt, .debug_tilde_bt_run, .debug_tilde_one_bt, .define_watched_value, .watch_run,
};

/// How many of the top stack items a line of the trace shows, as .S.
const trace_items = 9;

pub fn execute(self: *State, comptime builtin: Builtin) RuntimeError!void {
    switch (builtin) {
        // +LTRACE ( -- ) and -LTRACE ( -- ): while it is on, each line of an included
        // file is shown as ~~ at its start would show it, before it is interpreted.
        .ltrace_on => self.line_trace = true,
        .ltrace_off => self.line_trace = false,
        // ONCE ( -- ): what follows, up to THEN, runs only the first time. It compiles
        // a cell of its own, 0 until then, and an IF.
        .once => try compileOnce(self),
        // (ONCE) ( a-addr -- flag ): true the first time for this cell.
        .once_run => {
            const address = try self.pop();
            const first = try self.readCell(address) == 0;
            if (first) try self.writeCell(address, -1);
            try self.push(truth(first));
        },
        // ~~BT ( -- ): as ~~, and then the words that called the definition.
        .debug_tilde_bt => try compileTildeBt(self, 4),
        .debug_tilde_bt_run => {
            const place = try self.memoryRange();
            var copy: [max_name + 64]u8 = undefined;
            const length = @min(place.len, copy.len);
            @memcpy(copy[0..length], place[0..length]);
            try words_tools.showPlace(self, copy[0..length], null);
            showCallers(self);
        },
        // ~~1BT ( -- ): ~~BT the first time only.
        .debug_tilde_one_bt => if (self.compiling) {
            try compileOnce(self);
            try compileTildeBt(self, 5);
            try self.compileThen();
        } else try compileTildeBt(self, 5),
        // ~~VALUE ( x "name" -- ): a VALUE whose every TO is shown.
        .define_watched_value => {
            self.pending_constant = try self.pop();
            self.pending_watched = true;
            self.pending = .value_name;
        },
        // (~~TO) ( x c-addr u xt -- x ): c-addr u is where the TO is, xt the value.
        .watch_run => {
            const id = try self.wordId(try self.pop());
            const place = try self.memoryRange();
            var copy: [max_name + 64]u8 = undefined;
            const length = @min(place.len, copy.len);
            @memcpy(copy[0..length], place[0..length]);
            try words_tools.showPlace(self, copy[0..length], self.wordName(self.words[id]));
        },
        else => @compileError(@tagName(builtin) ++ " is not in the words of this file"),
    }
}

fn compileOnce(self: *State) RuntimeError!void {
    try self.requireCompiling();
    const address = self.data_here;
    try self.reserveData(cell_size);
    try self.writeCell(address, 0);
    _ = try self.emit(.{ .kind = .literal, .value = address });
    try self.compileCall(@intCast(self.builtinWord(.once_run)));
    try self.compileIf();
}

/// `back` is the length of the word (~~BT or ~~1BT), for the column of its place.
fn compileTildeBt(self: *State, back: usize) RuntimeError!void {
    var place: [max_name + 64]u8 = undefined;
    const text = try words_tools.placeText(self, &place, back);
    if (self.compiling) {
        try self.compileCountedString(text, .string_literal);
        try self.compileCall(@intCast(self.builtinWord(.debug_tilde_bt_run)));
    } else {
        try words_tools.showPlace(self, text, null);
        showCallers(self);
    }
}

/// Whether TO of this value is shown (~~VALUE).
pub fn isWatched(self: *const State, id: u16) bool {
    return std.mem.indexOfScalar(u16, self.watched[0..self.watched_count], id) != null;
}

pub fn watch(self: *State, id: u16) RuntimeError!void {
    if (self.watched_count == self.watched.len) return error.DictionaryFull;
    self.watched[self.watched_count] = id;
    self.watched_count += 1;
}

/// Forgets the watched values from word `id` on, which FORGET or a MARKER removed.
pub fn unwatchFrom(self: *State, id: u16) void {
    var kept: usize = 0;
    for (self.watched[0..self.watched_count]) |word| {
        if (word >= id) continue;
        self.watched[kept] = word;
        kept += 1;
    }
    self.watched_count = kept;
}

/// What TO does for a watched value before it stores: shown at once outside a
/// definition, compiled inside one. `name_length` is the length of the name after TO.
pub fn watchStore(self: *State, id: u16, name_length: usize) RuntimeError!void {
    var place: [max_name + 64]u8 = undefined;
    const text = try words_tools.placeText(self, &place, name_length);
    if (self.compiling) {
        try self.compileCountedString(text, .string_literal);
        _ = try self.emit(.{ .kind = .execution_token, .value = id });
        try self.compileCall(@intCast(self.builtinWord(.watch_run)));
    } else try words_tools.showPlace(self, text, self.wordName(self.words[id]));
}

/// +LTRACE's line for the line of the included file that is about to be interpreted.
pub fn showLine(self: *State) void {
    // The line is not the current source yet, so currentFileFrame does not give it.
    if (self.include_depth == 0) return;
    const frame = self.include_stack[self.include_depth - 1];
    var place: [max_name + 64]u8 = undefined;
    const name = self.sourceFileName(frame.file_index);
    const text = std.fmt.bufPrint(&place, "{s}:{d}:1:", .{ name[0..@min(name.len, place.len - 48)], frame.line }) catch return;
    words_tools.showPlace(self, text, null) catch {};
}

/// The words that called the running definition, innermost first, as the backtrace of
/// an error shows them. `frames` holds the callers inside each executeOperations and,
/// between them, the place that started each one (see executeOperations).
fn showCallers(self: *State) void {
    words_tools.writeError(self, "BACKTRACE:\n");
    var index = self.frame_depth;
    while (index > 0) {
        index -= 1;
        const frame = self.frames[index];
        // Compiled code that the interpreter started has no caller.
        if (frame.pc == 0) continue;
        var line: [max_name + 96]u8 = undefined;
        var writer = LineWriter{ .buffer = &line };
        writer.add("  ");
        error_reporting.describePlace(self, frame.pc - 1, &writer);
        writer.add("\n");
        words_tools.writeError(self, writer.text());
    }
}

/// Text put together in a buffer; what does not fit is left out.
pub const LineWriter = struct {
    buffer: []u8,
    len: usize = 0,

    pub fn add(self: *LineWriter, bytes: []const u8) void {
        const count = @min(bytes.len, self.buffer.len - self.len);
        @memcpy(self.buffer[self.len..][0..count], bytes[0..count]);
        self.len += count;
    }

    pub fn number(self: *LineWriter, value: anytype) void {
        var digits: [24]u8 = undefined;
        self.add(std.fmt.bufPrint(&digits, "{d}", .{value}) catch unreachable);
    }

    pub fn text(self: *const LineWriter) []const u8 {
        return self.buffer[0..self.len];
    }
};

/// A line of --trace: `> NAME <depth> items` when the word `id` starts and `< NAME ...`
/// when it ends, indented by how deep the traced words are nested. After --trace-limit
/// lines the trace says so once and ends; the program goes on.
pub fn traceWord(self: *State, id: u16, enter: bool) void {
    if (self.trace_limit != 0 and self.trace_lines >= self.trace_limit) {
        self.tracing = false;
        words_tools.writeError(self, "TRACE LIMIT\n");
        return;
    }
    self.trace_lines += 1;
    if (!enter) self.trace_depth -|= 1;
    var line: [max_name + 400]u8 = undefined;
    var writer = LineWriter{ .buffer = line[0 .. line.len - 1] };
    for (0..@min(self.trace_depth, 40)) |_| writer.add("  ");
    writer.add(if (enter) "> " else "< ");
    const name = if (id < self.word_count) self.wordName(self.words[id]) else "?";
    writer.add(if (name.len == 0) ":NONAME" else name);
    writer.add(" <");
    writer.number(self.data_depth);
    writer.add(">");
    for (self.data_stack[self.data_depth -| trace_items..self.data_depth]) |value| {
        writer.add(" ");
        writer.number(value);
    }
    line[writer.len] = '\n';
    words_tools.writeError(self, line[0 .. writer.len + 1]);
    if (enter) self.trace_depth += 1;
}
