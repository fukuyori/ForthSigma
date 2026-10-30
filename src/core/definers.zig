//! Defining words: the names they wait for and the words they make.

const defs = @import("defs.zig");
const forth = @import("../forth.zig");
const local_variables = @import("local_variables.zig");
const memory_map = @import("memory_map.zig");
const Builtin = defs.Builtin;
const Cell = memory_map.Cell;
const Pending = defs.Pending;
const RuntimeError = defs.RuntimeError;
const State = forth.State;
const WordKind = defs.WordKind;
const cell_size = memory_map.cell_size;
const data_limit = memory_map.data_limit;
const floatBits = defs.floatBits;
const float_size = memory_map.float_size;
const localOperand = local_variables.localOperand;

/// Allocates a data-area word that owns `size` bytes, rolling back on failure.
pub fn appendDataWord(self: *State, name: []const u8, kind: WordKind, size: Cell) RuntimeError!u16 {
    const address = self.data_here;
    try self.reserveData(size);
    const id = self.appendWord(name, kind, .drop, address) catch |err| {
        self.data_here = address;
        return err;
    };
    self.words[id].data_here_before = address;
    return id;
}

pub fn finishPending(self: *State, token: []const u8) RuntimeError!void {
    const pending = self.pending;
    self.pending = .none;
    switch (pending) {
        .none => unreachable,
        .colon_name => {
            self.beginDefinition(try self.appendWord(token, .colon, .drop, 0));
        },
        .variable_name, .value_name => {
            const id = try self.appendDataWord(token, if (pending == .value_name) .value else .variable, cell_size);
            try self.writeCell(self.words[id].value, if (pending == .value_name) self.pending_constant else 0);
            // A variable can take a DOES> part, as in gforth, where VARIABLE is CREATE 0 ,.
            if (pending == .variable_name) self.last_created_word = id;
        },
        .fvariable_name => {
            const id = try self.appendDataWord(token, .variable, float_size);
            try self.writeFloat(self.words[id].value, 0);
            self.last_created_word = id;
        },
        .constant_name => {
            _ = try self.appendWord(token, .constant, .drop, self.pending_constant);
        },
        .fconstant_name => {
            _ = try self.appendWord(token, .fconstant, .drop, floatBits(self.pending_float));
        },
        .fvalue_name => {
            const id = try self.appendDataWord(token, .fvalue, float_size);
            try self.writeFloat(self.words[id].value, self.pending_float);
        },
        .two_value_name => {
            const id = try self.appendDataWord(token, .two_value, 2 * cell_size);
            try self.writeDouble(self.words[id].value, self.pending_double);
        },
        .buffer_name => {
            if (self.pending_array_size < 0 or self.pending_array_size > data_limit) return error.MemoryExhausted;
            _ = try self.appendDataWord(token, .created, self.pending_array_size);
        },
        .two_variable_name, .two_constant_name => {
            const id = try self.appendDataWord(token, if (pending == .two_constant_name) .two_constant else .variable, 2 * cell_size);
            try self.writeDouble(self.words[id].value, if (pending == .two_constant_name) self.pending_double else 0);
            if (pending == .two_variable_name) self.last_created_word = id;
        },
        .array_name => {
            if (self.pending_array_size < 0 or self.pending_array_size > data_limit / cell_size) return error.MemoryExhausted;
            _ = try self.appendDataWord(token, .array, self.pending_array_size * cell_size);
        },
        .forget_name => {
            const id = try self.lookupOrFail(token);
            if (id < self.builtin_count) return error.InvalidDefinition;
            self.forgetFrom(id);
        },
        .tick_name => {
            const id = try self.lookupOrFail(token);
            if (self.compiling) {
                _ = try self.emit(.{ .kind = .execution_token, .value = id });
            } else try self.push(id);
        },
        .to_name => {
            if (self.compiling) {
                if (self.findLocal(token)) |local| {
                    if (local.variable) return error.InvalidDefinition;
                    _ = try self.emit(.{ .kind = .local_store, .value = localOperand(local) });
                    return;
                }
            }
            const id = try self.lookupOrFail(token);
            const kind = self.words[id].kind;
            if (kind != .value and kind != .fvalue and kind != .two_value) return error.InvalidDefinition;
            if (self.compiling) {
                _ = try self.emit(.{ .kind = .store_value, .value = id });
            } else switch (kind) {
                .fvalue => try self.writeFloat(self.words[id].value, try self.fpop()),
                .two_value => try self.writeDouble(self.words[id].value, try self.popDouble()),
                else => try self.writeCell(self.words[id].value, try self.pop()),
            }
        },
        .char_name => {
            if (self.compiling) {
                _ = try self.emit(.{ .kind = .literal, .value = token[0] });
            } else try self.push(token[0]);
        },
        .postpone_name => {
            if (!self.compiling) return error.CompileOnly;
            const id = try self.lookupOrFail(token);
            _ = try self.emit(.{ .kind = if (self.words[id].immediate) .call else .compile_call, .value = id });
        },
    }
}

pub fn endDefinition(self: *State) RuntimeError!void {
    if (!self.defining or !self.compiling) return error.CompileOnly;
    if (self.control_depth != 0) return error.ControlMismatch;
    _ = try self.emit(.{ .kind = .exit });
    self.words[self.current_word].code_end = self.code_count;
    self.words[self.current_word].locals_size = self.locals_frame_size;
    if (self.currentFileFrame()) |frame| {
        if (self.words[self.current_word].source_file == frame.file_index + 1) self.words[self.current_word].source_end_line = frame.line;
    }
    self.local_count = 0;
    self.setCompiling(false);
    self.defining = false;
}

/// >BODY: the data area of a word that has one. CONSTANT and FCONSTANT keep their
/// value in the dictionary entry, so they have none here (gforth gives an address).
pub fn bodyAddress(self: *State, id: u16) RuntimeError!Cell {
    const word = self.words[id];
    return switch (word.kind) {
        .variable, .array, .created, .value, .fvalue, .two_constant, .two_value => word.value,
        else => error.InvalidExecutionToken,
    };
}

pub fn isDefiningBuiltin(builtin: Builtin) bool {
    return switch (builtin) {
        .define_colon, .define_variable, .define_fvariable, .define_constant, .define_value, .define_two_variable, .define_two_constant, .define_fconstant, .define_fvalue, .define_two_value, .define_buffer, .define_array => true,
        else => false,
    };
}

/// Runs a defining word from a definition: takes its value from the stack, then
/// reads the new word's name from the input, as interpreting the word would.
pub fn runDefiningWord(self: *State, builtin: Builtin) RuntimeError!void {
    const pending = try self.definingPending(builtin);
    const name = (try self.nextSourceToken()) orelse return error.InvalidDefinition;
    self.pending = pending;
    try self.finishPending(name);
}

/// Takes a defining word's value from the stack and returns what its name makes.
pub fn definingPending(self: *State, builtin: Builtin) RuntimeError!Pending {
    return switch (builtin) {
        .define_colon => blk: {
            if (self.defining) return error.InvalidDefinition;
            break :blk .colon_name;
        },
        .define_variable => .variable_name,
        .define_fvariable => .fvariable_name,
        .define_constant => blk: {
            self.pending_constant = try self.pop();
            break :blk .constant_name;
        },
        .define_value => blk: {
            self.pending_constant = try self.pop();
            break :blk .value_name;
        },
        .define_two_variable => .two_variable_name,
        .define_two_constant => blk: {
            self.pending_double = try self.popDouble();
            break :blk .two_constant_name;
        },
        .define_fconstant => blk: {
            self.pending_float = try self.fpop();
            break :blk .fconstant_name;
        },
        .define_fvalue => blk: {
            self.pending_float = try self.fpop();
            break :blk .fvalue_name;
        },
        .define_two_value => blk: {
            self.pending_double = try self.popDouble();
            break :blk .two_value_name;
        },
        .define_buffer => blk: {
            self.pending_array_size = try self.pop();
            break :blk .buffer_name;
        },
        .define_array => blk: {
            self.pending_array_size = try self.pop();
            break :blk .array_name;
        },
        else => unreachable,
    };
}

pub fn startInterpretPending(self: *State, pending: Pending) RuntimeError!void {
    if (self.compiling) return error.CompileOnly;
    self.pending = pending;
}
