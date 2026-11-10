//! Error messages, THROW codes, and the state CATCH restores.

const std = @import("std");
const defs = @import("defs.zig");
const forth = @import("../forth.zig");
const inline_calls = @import("inline_calls.zig");
const memory_map = @import("memory_map.zig");
const CatchFrame = defs.CatchFrame;
const Cell = memory_map.Cell;
const RuntimeError = defs.RuntimeError;
const State = forth.State;
const errnoIor = memory_map.errnoIor;
const errno_bad_file = memory_map.errno_bad_file;
const errno_invalid = memory_map.errno_invalid;
const errno_no_memory = memory_map.errno_no_memory;
const error_codes = defs.error_codes;
const ior_errno_base = memory_map.ior_errno_base;
const throw_code_undefined_word = defs.throw_code_undefined_word;

pub fn report(self: *State, err: anyerror) void {
    // QUIT keeps both data stacks and shows nothing, as gforth does.
    const kept_data = self.data_depth;
    const kept_floats = self.float_depth;
    defer self.clearBacktrace();
    self.trace_depth = 0;
    defer if (defs.debug_enabled and self.show_backtrace and self.backtrace_total != 0 and err != error.Aborted and err != error.Quit) showBacktrace(self, kept_data, kept_floats);
    defer if (err == error.Quit) {
        self.data_depth = kept_data;
        self.float_depth = kept_floats;
    };
    self.capture_target = null;
    self.local_count = 0;
    self.locals_top = self.sizes.localsBase();
    if (self.defining) {
        self.code_count = self.words[self.current_word].code_start;
        self.names_used = self.words[self.current_word].name_start;
        self.dropWordsFrom(self.current_word);
        self.dropUsesFrom(self.current_word);
        self.data_here = self.current_data_start;
    }
    self.setCompiling(false);
    self.defining = false;
    self.pending = .none;
    self.control_depth = 0;
    self.interpret_loop_depth = 0;
    self.data_depth = 0;
    self.return_depth = 0;
    self.float_depth = 0;
    self.loop_depth = 0;
    self.resetHold();
    if (err == error.Aborted or err == error.Quit) {
        self.error_location = null;
        return;
    }
    if (self.error_location) |location| {
        var line_text: [24]u8 = undefined;
        self.write(self.sourceFileName(location.file_index));
        self.write(std.fmt.bufPrint(&line_text, ":{d}: ", .{location.line}) catch unreachable);
        self.error_location = null;
    }
    if (err == error.Thrown) {
        self.writeThrowMessage(self.throw_code);
        return;
    }
    if (err == error.UnknownWord) {
        if (self.last_unknown_word) |name| {
            self.write(name);
            self.write(" ?\n");
            self.last_unknown_word = null;
            return;
        }
    }
    if (err == error.ControlStackOverflow) {
        self.write("NESTING ERROR !\n");
        return;
    }
    const message: []const u8 = if (err == error.StackUnderflow) "STACK UNDER FLOW !" else if (err == error.ReturnStackUnderflow) "RETURN STACK UNDER FLOW !" else if (err == error.StackOverflow) "STACK OVER FLOW !" else if (err == error.ReturnStackOverflow) "RETURN STACK OVER FLOW !" else if (err == error.FloatStackUnderflow) "FLOATING-POINT STACK UNDER FLOW !" else if (err == error.FloatStackOverflow) "FLOATING-POINT STACK OVER FLOW !" else if (err == error.DictionaryFull) "OUT OF DICTIONARY !" else if (err == error.CodeFull) "OUT OF CODE SPACE !" else if (err == error.InvalidDefinition) "DEFINITION ERROR !" else if (err == error.CommentUnclosed) "END OF COMMENT MUST BE \")\" !" else if (err == error.ControlMismatch) "CONTROL STRUCTURE ERROR !" else if (err == error.CompileOnly) "COMPILE MODE ERROR !" else if (err == error.UnknownWord) "?" else if (err == error.InvalidNumber) "NUMBER ERROR !" else if (err == error.DivisionByZero) "DIVISION BY ZERO !" else if (err == error.ResultOutOfRange) "RESULT OUT OF RANGE !" else if (err == error.LoopMismatch) "LOOP ERROR !" else if (err == error.InvalidBase) "BASE ERROR !" else if (err == error.InvalidExecutionToken) "INVALID EXECUTION TOKEN !" else if (err == error.InvalidAddress) "INVALID MEMORY ADDRESS !" else if (err == error.PicturedNumericOverflow) "PICTURED NUMERIC OUTPUT ERROR !" else if (err == error.MemoryExhausted) "OUT OF MEMORY !" else if (err == error.InputUnavailable) "INPUT ERROR !" else if (err == error.FileUnavailable) "FILE ERROR !" else if (err == error.InvalidImage) "INVALID IMAGE !" else if (err == error.HostUnavailable) "HOST FUNCTION UNAVAILABLE !" else if (err == error.HostFailed) "HOST FUNCTION ERROR !" else if (err == error.StringTooLong) "STRING TOO LONG !" else if (err == error.IncludeNesting) "INCLUDE NESTING ERROR !" else if (err == error.TooManySourceFiles) "TOO MANY SOURCE FILES !" else if (err == error.SearchOrderOverflow) "SEARCH ORDER OVER FLOW !" else if (err == error.SearchOrderUnderflow) "SEARCH ORDER UNDER FLOW !" else if (err == error.InvalidWordlist) "INVALID WORDLIST !" else if (err == error.GraphicsUnavailable) "GRAPHICS UNAVAILABLE !" else if (err == error.NoCanvas) "NO GRAPHICS IMAGE !" else if (err == error.UserInterrupt) "USER INTERRUPT !" else if (err == error.FontUnavailable) "FONT ERROR !" else if (err == error.TclFailed) "TCL ERROR !" else if (err == error.InvalidMml) "INVALID MML !" else if (err == error.AudioUnavailable) "AUDIO UNAVAILABLE !" else if (err == error.SampleInvalid) "SAMPLE ERROR !" else if (err == error.ModInvalid) "MOD ERROR !" else if (err == error.InvalidImageHandle) "INVALID IMAGE HANDLE !" else if (err == error.ImageInvalid) "IMAGE FORMAT ERROR !" else if (err == error.StepLimit) "STEP LIMIT !" else "FORTH ERROR !";
    self.write(message);
    self.write("\n");
}

/// After the message of an error that came up in compiled code: the words that were
/// running, innermost first, each with the file and line of the operation it was at when
/// that is known, and the stacks as the error left them (`report` has emptied them).
///
///     BACKTRACE:
///       AVERAGE prog.fs:12
///       REPORT prog.fs:30
///     STACK: <3> 10 20 0
///
/// A word whose body was copied into its caller instead of called is marked (INLINE),
/// and a place that follows itself, as in a recursion, is shown once with the number of
/// times (`DEEP prog.fs:4 *32`).
fn showBacktrace(self: *State, data_depth: usize, float_depth: usize) void {
    self.write("BACKTRACE:\n");
    var index: usize = 0;
    while (index < self.backtrace_count) {
        const pc = self.backtrace[index];
        var times: usize = 1;
        while (index + times < self.backtrace_count and self.backtrace[index + times] == pc) times += 1;
        index += times;
        const owner = codeOwner(self, pc) orelse {
            self.write("  ?\n");
            continue;
        };
        const word = self.words[owner];
        // The inline guards whose copied bodies hold the operation, outermost first.
        var guards: [16]u16 = undefined;
        var guard_count: usize = 0;
        for (self.code[word.code_start..pc], word.code_start..) |op, at| {
            if (inline_calls.isInline(op) and pc - at < inline_calls.span(op.value) and guard_count < guards.len) {
                guards[guard_count] = inline_calls.wordId(op.value);
                guard_count += 1;
            }
        }
        while (guard_count > 0) {
            guard_count -= 1;
            self.write("  ");
            writeWordName(self, guards[guard_count]);
            self.write(" (INLINE)");
            writePlace(self, word, pc, times);
        }
        self.write("  ");
        writeWordName(self, owner);
        writePlace(self, word, pc, times);
    }
    if (self.backtrace_total > self.backtrace_count) {
        var text: [40]u8 = undefined;
        self.write(std.fmt.bufPrint(&text, "  ... {d} MORE\n", .{self.backtrace_total - self.backtrace_count}) catch unreachable);
    }
    self.write("STACK: ");
    self.data_depth = data_depth;
    self.executeBuiltin(.dot_s) catch {};
    self.data_depth = 0;
    self.write("\n");
    if (defs.float_enabled and float_depth != 0) {
        self.write("FLOAT STACK: ");
        self.float_depth = float_depth;
        self.executeBuiltin(.f_dot_s) catch {};
        self.float_depth = 0;
        self.write("\n");
    }
}

/// "NAME file:line" of the operation at `pc`, for the callers that ~~BT shows.
pub fn describePlace(self: *State, pc: u16, writer: *@import("words_debug.zig").LineWriter) void {
    const owner = codeOwner(self, pc) orelse return writer.add("?");
    const word = self.words[owner];
    const name = self.wordName(word);
    writer.add(if (name.len == 0) ":NONAME" else name);
    if (word.source_file != 0 and self.code_lines[pc] != 0) {
        writer.add(" ");
        writer.add(self.sourceFileName(word.source_file - 1));
        writer.add(":");
        writer.number(self.code_lines[pc]);
    }
}

/// The colon definition whose code holds `pc`: the innermost one, and for the code after
/// DOES> the defining word.
fn codeOwner(self: *const State, pc: u16) ?u16 {
    var found: ?u16 = null;
    for (self.words[self.builtin_count..self.word_count], self.builtin_count..) |word, id| {
        if (word.kind != .colon or pc < word.code_start or pc >= word.code_end) continue;
        if (found == null or word.code_start >= self.words[found.?].code_start) found = @intCast(id);
    }
    return found;
}

fn writeWordName(self: *State, id: u16) void {
    const name = if (id < self.word_count) self.wordName(self.words[id]) else "?";
    self.write(if (name.len == 0) ":NONAME" else name);
}

/// " file:line" of the operation at `pc` when it was compiled from a file, " *n" when the
/// place came `times` times in a row, and the end of the line.
fn writePlace(self: *State, word: defs.Word, pc: u16, times: usize) void {
    var text: [24]u8 = undefined;
    if (word.source_file != 0 and self.code_lines[pc] != 0) {
        self.write(" ");
        self.write(self.sourceFileName(word.source_file - 1));
        self.write(std.fmt.bufPrint(&text, ":{d}", .{self.code_lines[pc]}) catch unreachable);
    }
    if (times > 1) self.write(std.fmt.bufPrint(&text, " *{d}", .{times}) catch unreachable);
    self.write("\n");
}

/// Reports an uncaught THROW code. Standard codes reuse the interpreter's messages;
/// I/O results (-512 minus errno) name the C error, as gforth does.
pub fn writeThrowMessage(self: *State, code: Cell) void {
    const message: ?[]const u8 = switch (code) {
        throw_code_undefined_word => "UNDEFINED WORD !",
        -37 => "FILE I/O EXCEPTION !",
        -38 => "NON-EXISTENT FILE !",
        ior_errno_base - 2 => "NO SUCH FILE OR DIRECTORY !",
        -59 => "ALLOCATE ERROR !",
        -60 => "FREE ERROR !",
        -61 => "RESIZE ERROR !",
        ior_errno_base - 5 => "INPUT/OUTPUT ERROR !",
        ior_errno_base - errno_no_memory => "CANNOT ALLOCATE MEMORY !",
        ior_errno_base - errno_bad_file => "BAD FILE DESCRIPTOR !",
        ior_errno_base - 13 => "PERMISSION DENIED !",
        ior_errno_base - 17 => "FILE EXISTS !",
        ior_errno_base - 21 => "IS A DIRECTORY !",
        ior_errno_base - errno_invalid => "INVALID ARGUMENT !",
        ior_errno_base - 24 => "TOO MANY OPEN FILES !",
        ior_errno_base - 28 => "NO SPACE LEFT ON DEVICE !",
        else => null,
    };
    if (message) |text| {
        self.write(text);
        self.write("\n");
        return;
    }
    // ABORT" shows its own text, as gforth does.
    if (code == -2) {
        if (self.abort_message) |address| {
            self.abort_message = null;
            const at = self.memoryAddress(address, 1) catch return;
            const length = self.memory[at];
            const text = self.memoryAddress(address + 1, length) catch return;
            self.write(self.memory[text .. text + length]);
            self.write("\n");
            return;
        }
    }
    var buffer: [48]u8 = undefined;
    self.write(std.fmt.bufPrint(&buffer, "ERROR #{d} !\n", .{code}) catch unreachable);
}

pub fn throwCode(self: *State, code: Cell) RuntimeError {
    self.throw_code = code;
    return error.Thrown;
}

pub fn throwIor(self: *State, errno: Cell) RuntimeError {
    return self.throwCode(errnoIor(errno));
}

pub fn throwCodeOf(self: *State, err: RuntimeError) Cell {
    if (err == error.Thrown) return self.throw_code;
    if (err == error.Aborted) return -1;
    if (err == error.UnknownWord) return throw_code_undefined_word;
    for (error_codes) |entry| {
        if (entry[0] == err) return entry[1];
    }
    unreachable;
}

/// Restores the stack depths and compiler state saved by CATCH. Stack contents below
/// the saved depths are left as they are, as in gforth. A definition that the caught
/// word started is abandoned the same way `report` abandons one.
pub fn restoreCatchFrame(self: *State, frame: CatchFrame) void {
    if (self.defining and !frame.defining) {
        self.code_count = self.words[self.current_word].code_start;
        self.names_used = self.words[self.current_word].name_start;
        self.dropWordsFrom(self.current_word);
        self.dropUsesFrom(self.current_word);
        self.data_here = self.current_data_start;
        self.defining = false;
    }
    self.data_depth = frame.data_depth;
    self.float_depth = frame.float_depth;
    self.return_depth = frame.return_depth;
    self.loop_depth = frame.loop_depth;
    self.control_depth = frame.control_depth;
    // Interpreted loops started inside the caught word end with it.
    self.interpret_loop_depth = @min(self.interpret_loop_depth, frame.interpret_loop_depth);
    self.pending = frame.pending;
    self.local_count = frame.local_count;
    self.setCompiling(frame.compiling);
    self.last_unknown_word = null;
    self.error_location = null;
    self.clearBacktrace();
}
