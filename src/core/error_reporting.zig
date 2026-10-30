//! Error messages, THROW codes, and the state CATCH restores.

const std = @import("std");
const defs = @import("defs.zig");
const forth = @import("../forth.zig");
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
const locals_base = memory_map.locals_base;
const throw_code_undefined_word = defs.throw_code_undefined_word;

pub fn report(self: *State, err: anyerror) void {
    self.capture_target = null;
    self.local_count = 0;
    self.locals_top = locals_base;
    if (self.defining) {
        self.code_count = self.words[self.current_word].code_start;
        self.names_used = self.words[self.current_word].name_start;
        self.word_count = self.current_word;
        self.data_here = self.current_data_start;
    }
    self.setCompiling(false);
    self.defining = false;
    self.pending = .none;
    self.control_depth = 0;
    self.data_depth = 0;
    self.return_depth = 0;
    self.float_depth = 0;
    self.loop_depth = 0;
    self.resetHold();
    if (err == error.Aborted) {
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
    const message: []const u8 = if (err == error.StackUnderflow) "STACK UNDER FLOW !" else if (err == error.ReturnStackUnderflow) "RETURN STACK UNDER FLOW !" else if (err == error.StackOverflow) "STACK OVER FLOW !" else if (err == error.ReturnStackOverflow) "RETURN STACK OVER FLOW !" else if (err == error.FloatStackUnderflow) "FLOATING-POINT STACK UNDER FLOW !" else if (err == error.FloatStackOverflow) "FLOATING-POINT STACK OVER FLOW !" else if (err == error.DictionaryFull) "OUT OF DICTIONARY !" else if (err == error.CodeFull) "OUT OF CODE SPACE !" else if (err == error.InvalidDefinition) "DEFINITION ERROR !" else if (err == error.CommentUnclosed) "END OF COMMENT MUST BE \")\" !" else if (err == error.ControlMismatch) "CONTROL STRUCTURE ERROR !" else if (err == error.CompileOnly) "COMPILE MODE ERROR !" else if (err == error.UnknownWord) "?" else if (err == error.InvalidNumber) "NUMBER ERROR !" else if (err == error.DivisionByZero) "DIVISION BY ZERO !" else if (err == error.ResultOutOfRange) "RESULT OUT OF RANGE !" else if (err == error.LoopMismatch) "LOOP ERROR !" else if (err == error.InvalidBase) "BASE ERROR !" else if (err == error.InvalidExecutionToken) "INVALID EXECUTION TOKEN !" else if (err == error.InvalidAddress) "INVALID MEMORY ADDRESS !" else if (err == error.PicturedNumericOverflow) "PICTURED NUMERIC OUTPUT ERROR !" else if (err == error.MemoryExhausted) "OUT OF MEMORY !" else if (err == error.InputUnavailable) "INPUT ERROR !" else if (err == error.FileUnavailable) "FILE ERROR !" else if (err == error.InvalidImage) "INVALID IMAGE !" else if (err == error.HostUnavailable) "HOST FUNCTION UNAVAILABLE !" else if (err == error.HostFailed) "HOST FUNCTION ERROR !" else if (err == error.StringTooLong) "STRING TOO LONG !" else if (err == error.IncludeNesting) "INCLUDE NESTING ERROR !" else if (err == error.TooManySourceFiles) "TOO MANY SOURCE FILES !" else if (err == error.SearchOrderOverflow) "SEARCH ORDER OVER FLOW !" else if (err == error.SearchOrderUnderflow) "SEARCH ORDER UNDER FLOW !" else if (err == error.InvalidWordlist) "INVALID WORDLIST !" else "FORTH ERROR !";
    self.write(message);
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
        self.word_count = self.current_word;
        self.data_here = self.current_data_start;
        self.defining = false;
    }
    self.data_depth = frame.data_depth;
    self.float_depth = frame.float_depth;
    self.return_depth = frame.return_depth;
    self.loop_depth = frame.loop_depth;
    self.control_depth = frame.control_depth;
    self.pending = frame.pending;
    self.local_count = frame.local_count;
    self.setCompiling(frame.compiling);
    self.last_unknown_word = null;
    self.error_location = null;
}
