//! The debugging words taken from gforth (+LTRACE, -LTRACE, ONCE, ~~BT, ~~1BT, ~~VALUE,
//! and the single-step debugger of DBG, BREAK:, and BREAK") and the trace of --trace. A build with -Ddebug=false has none of them. Their output
//! goes to standard error, as that of ~~ does.

const std = @import("std");
const defs = @import("defs.zig");
const forth = @import("../forth.zig");
const memory_map = @import("memory_map.zig");
const error_reporting = @import("error_reporting.zig");
const words_tools = @import("words_tools.zig");
const words_xchar = @import("words_xchar.zig");
const decompiler = @import("decompiler.zig");
const debug_log = @import("debug_log.zig");
const coverage = @import("coverage.zig");
const inline_calls = @import("inline_calls.zig");
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
    .dbg,       .break_colon, .break_run, .break_quote, .break_quote_run,
    .cover_raw, .cov_percent, .coverage,
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
        // ~~VALUE ( x "name" -- ): a VALUE whose every TO is shown. As the other
        // defining words, it reads the name at once when a definition runs it.
        .define_watched_value => try self.runDefiningWord(builtin),
        // (~~TO) ( x c-addr u xt -- x ): c-addr u is where the TO is, xt the value.
        .watch_run => {
            const id = try self.wordId(try self.pop());
            const place = try self.memoryRange();
            var copy: [max_name + 64]u8 = undefined;
            const length = @min(place.len, copy.len);
            @memcpy(copy[0..length], place[0..length]);
            try words_tools.showPlace(self, copy[0..length], self.wordName(self.words[id]));
        },
        // The words of gforth's coverage.fs, on the counts of --coverage.
        .cover_raw => try coverage.coverRaw(self),
        .cov_percent => try coverage.covPercent(self),
        .coverage => try coverage.coverage(self),
        .dbg => try runDbg(self),
        // BREAK: ( -- ): from here on, the definition is stepped through as with DBG.
        .break_colon => {
            try self.requireCompiling();
            self.keep_counting = true;
            try self.compileCall(@intCast(self.builtinWord(.break_run)));
        },
        .break_run => startStepping(self),
        // BREAK" text" ( -- ): as BREAK:, after showing `BREAK AT: text`.
        .break_quote => {
            try self.requireCompiling();
            const line = self.source_line;
            const start = self.sourceCursor();
            const close = std.mem.indexOfScalarPos(u8, line, start, '"') orelse return error.InvalidDefinition;
            self.setSourceCursor(close + 1);
            self.keep_counting = true;
            try self.compileCountedString(line[start..close], .string_literal);
            try self.compileCall(@intCast(self.builtinWord(.break_quote_run)));
        },
        .break_quote_run => {
            const text = try self.memoryRange();
            self.write("BREAK AT: ");
            self.write(text);
            self.write("\n");
            startStepping(self);
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
        // The loop that counts goes on running the code, so that one that does not
        // count never runs inside it (see `in_counted`).
        self.keep_counting = true;
        if (debug_log.enabled(self)) debug_log.logTraceLimit(self) else words_tools.writeError(self, "TRACE LIMIT\n");
        return;
    }
    self.trace_lines += 1;
    if (!enter) self.trace_depth -|= 1;
    // With a log (--debug-log), the trace goes there, as lines of JSON.
    if (debug_log.enabled(self)) {
        debug_log.logTrace(self, id, enter, self.trace_depth);
        if (enter) self.trace_depth += 1;
        return;
    }
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

// ---- The single-step debugger (DBG, BREAK:, BREAK") ----

/// DBG ( "name" -- ): runs the colon definition `name`, stopping before each of its
/// operations.
fn runDbg(self: *State) RuntimeError!void {
    const name = (try self.nextSourceToken()) orelse return error.InvalidDefinition;
    const id = self.synonymTarget(try self.lookupOrFail(name));
    if (self.words[id].kind != .colon) return error.InvalidDefinition;
    self.keep_counting = true;
    self.stepper = .armed;
    self.step_word = id;
    defer self.stepper = .off;
    try self.executeWord(id);
}

/// After an image is restored: when its code has a BREAK: or a BREAK", compiled code
/// runs in the loop that can stop for them, as after one is compiled here.
pub fn noteBreakpoints(self: *State) void {
    for (self.code[0..self.code_count]) |op| {
        if (op.kind != .call and op.kind != .call_builtin) continue;
        if (op.value < 0 or op.value >= self.builtin_count) continue;
        const word = self.words[@intCast(op.value)];
        if (word.kind == .builtin and (word.builtin == .break_run or word.builtin == .break_quote_run)) {
            self.keep_counting = true;
            return;
        }
    }
}

/// BREAK: and BREAK" compile this call; from here on the definition is stepped through.
fn startStepping(self: *State) void {
    // A definition that was running before the first BREAK: or DBG was met runs in the
    // loop that does not stop.
    if (!self.in_counted) return;
    // Inside the steps, a BREAK: is one more step.
    if (self.stepper == .on) return;
    self.stepper = .on;
    self.step_base = self.call_depth;
    self.step_depth = self.call_depth;
    self.step_result = false;
    self.step_skip_end = 0;
    self.step_inline_count = 0;
    showStepStack(self);
}

/// The definition `id` starts: the one DBG named is stepped through from here.
pub fn stepEnter(self: *State, id: u16) void {
    if (self.stepper != .armed or id != self.step_word) return;
    self.stepper = .on;
    self.step_base = self.call_depth;
    self.step_depth = self.call_depth;
    self.step_result = false;
    self.step_skip_end = 0;
    self.step_inline_count = 0;
    self.write(": ");
    self.write(decompiler.seeName(self, id));
    self.write("\n");
    showStepStack(self);
}

/// The running definition ends: one entered with `n` gives the steps back to its
/// caller, and the one the steps started in ends them.
pub fn stepLeave(self: *State) void {
    if (self.stepper != .on or self.call_depth != self.step_depth) return;
    if (self.step_depth > self.step_base) {
        self.step_depth -= 1;
        self.write("\n");
        showStepStack(self);
        self.step_result = false;
    } else self.stepper = .off;
}

/// Before the operation at `pc` of the definition that is stepped through: shows what
/// the last one left, then this one, and waits for a key.
///
///     DUP            -> [ 2 ] 3 3
///     *              -> [ 1 ] 9
///     ;              ->
///
/// (each line ends where the key is awaited, after `-> `; what the operation writes and
/// the stack follow it)
///
/// Enter goes on; `n` goes into the definition the operation calls; `u` runs the rest
/// without stopping, back to the caller when `n` led here; `d` ends the steps and runs
/// the rest; `s` ends the program's run with an error. The end of the input is as `d`.
///
/// A short definition whose code was copied into this one is one step, as a call is:
/// its copied operations run without stopping, unless `n` goes into them.
pub fn step(self: *State, pc: u16, end_pc: u16) RuntimeError!void {
    if (pc < self.step_skip_end) return;
    self.step_skip_end = 0;
    // The copied code that this operation is past has ended.
    while (self.step_inline_count > 0 and pc >= self.step_inline_ends[self.step_inline_count - 1]) self.step_inline_count -= 1;
    if (self.step_result) showStepStack(self);
    self.step_result = true;
    var text: [max_name + 16]u8 = undefined;
    const name = operationName(self, pc, end_pc, &text);
    self.write(name);
    for (name.len..@max(name.len, 14)) |_| self.write(" ");
    self.write(" -> ");
    while (true) {
        const key = words_xchar.key(self) catch {
            self.stepper = .off;
            return;
        };
        // The line feed after a carriage return is the same Enter.
        const after_cr = self.step_after_cr;
        self.step_after_cr = key == '\r';
        switch (key) {
            '\n', '\r' => {
                if (key == '\n' and after_cr) continue;
                const op = self.code[pc];
                if (inline_calls.isInline(op)) self.step_skip_end = pc + inline_calls.span(op.value);
                return;
            },
            'n', 'N' => {
                const op = self.code[pc];
                if (inline_calls.isInline(op)) {
                    // The copied operations follow in this definition. Deeper than the
                    // ends that are kept, it is one step.
                    if (self.step_inline_count == self.step_inline_ends.len) {
                        self.step_skip_end = pc + inline_calls.span(op.value);
                        return;
                    }
                    self.step_inline_ends[self.step_inline_count] = pc + inline_calls.span(op.value);
                    self.step_inline_count += 1;
                    self.step_result = false;
                    self.write("\n: ");
                    self.write(decompiler.seeName(self, inline_calls.wordId(op.value)));
                    self.write("\n");
                    showStepStack(self);
                    return;
                }
                // A name made by SYNONYM or ALIAS stands for its word.
                const callee: ?u16 = switch (op.kind) {
                    .call, .call_colon => if (!inline_calls.isInline(op) and op.value >= 0 and op.value < self.word_count) blk: {
                        const target = self.synonymTarget(@intCast(op.value));
                        break :blk if (self.words[target].kind == .colon) target else null;
                    } else null,
                    else => null,
                };
                if (callee) |id| {
                    self.step_skip_end = 0;
                    self.step_inline_count = 0;
                    self.step_depth += 1;
                    self.step_result = false;
                    self.write("\n: ");
                    self.write(decompiler.seeName(self, id));
                    self.write("\n");
                    showStepStack(self);
                }
                return;
            },
            'u', 'U' => {
                self.write("\n");
                if (self.step_inline_count != 0) {
                    // Out of the copied code of a short definition that `n` went into.
                    self.step_skip_end = self.step_inline_ends[self.step_inline_count - 1];
                } else if (self.step_depth > self.step_base) {
                    self.step_depth -= 1;
                } else self.stepper = .off;
                return;
            },
            'd', 'D' => {
                self.write("\nDone...\n");
                self.stepper = .off;
                return;
            },
            's', 'S' => {
                self.write("\n");
                self.stepper = .off;
                return words_tools.abortWith(self, "debugger aborted");
            },
            else => {},
        }
    }
}

/// `[ depth ] items` and the end of the line: the data stack between two steps.
fn showStepStack(self: *State) void {
    var text: [32]u8 = undefined;
    self.write(std.fmt.bufPrint(&text, "[ {d} ]", .{self.data_depth}) catch unreachable);
    for (self.data_stack[self.data_depth -| trace_items..self.data_depth]) |value| {
        self.write(" ");
        self.writeNumber(value);
    }
    self.write("\n");
}

/// What the operation at `pc` is called in a step: the word it runs, the number it
/// pushes, or the control word it came from.
fn operationName(self: *State, pc: u16, end_pc: u16, buffer: []u8) []const u8 {
    const op = self.code[pc];
    const named: struct { []const u8, ?Cell } = switch (op.kind) {
        .call, .call_builtin, .call_colon => .{ "", if (inline_calls.isInline(op)) inline_calls.wordId(op.value) else op.value },
        .compile_call => .{ "POSTPONE ", op.value },
        .execution_token => .{ "['] ", op.value },
        .store_value => .{ "TO ", op.value },
        .add_value => .{ "+TO ", op.value },
        .builtin => {
            const builtin: Builtin = @enumFromInt(op.value);
            for (self.words[0..self.builtin_count]) |*word| {
                if (word.builtin == builtin and word.name_len != 0) return self.wordName(word.*);
            }
            return "<BUILT-IN>";
        },
        .literal => return std.fmt.bufPrint(buffer, "{d}", .{op.value}) catch "LITERAL",
        .float_literal => .{ "FLITERAL", null },
        .branch => .{ "BRANCH", null },
        .branch_zero => .{ "?BRANCH", null },
        .do_loop => .{ "DO", null },
        .q_do_loop => .{ "?DO", null },
        .loop => .{ "LOOP", null },
        .plus_loop => .{ "+LOOP", null },
        .leave => .{ "LEAVE", null },
        .print_string => .{ ".\"", null },
        .string_literal => .{ "S\"", null },
        .counted_string => .{ "C\"", null },
        .abort_string => .{ "ABORT\"", null },
        .does => .{ "DOES>", null },
        .exit => .{ if (pc + 1 == end_pc) ";" else "EXIT", null },
        .local_frame => .{ "{", null },
        .local_store => .{ "TO (LOCAL)", null },
        .local_fetch => .{ "(LOCAL)", null },
        .local_address => .{ "ADDR (LOCAL)", null },
        .local_execute => .{ "EXECUTE (LOCAL)", null },
        // The operations of the frequent built-in words keep the word's id.
        else => .{ "", op.value },
    };
    const id = named[1] orelse return named[0];
    return std.fmt.bufPrint(buffer, "{s}{s}", .{ named[0], decompiler.seeName(self, id) }) catch named[0];
}
