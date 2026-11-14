//! Defining words: the names they wait for and the words they make.

const defs = @import("defs.zig");
const words_debug = @import("words_debug.zig");
const forth = @import("../forth.zig");
const local_variables = @import("local_variables.zig");
const memory_map = @import("memory_map.zig");
const words_xchar = @import("words_xchar.zig");
const Builtin = defs.Builtin;
const Cell = memory_map.Cell;
const Pending = defs.Pending;
const RuntimeError = defs.RuntimeError;
const State = forth.State;
const WordKind = defs.WordKind;
const cell_size = memory_map.cell_size;
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
        .replacer_name => {
            const previous = self.currentWordlist();
            try self.writeCell(memory_map.current_wordlist_address, memory_map.macros_wordlist);
            defer self.writeCell(memory_map.current_wordlist_address, previous) catch unreachable;
            self.beginDefinition(try self.appendWord(token, .colon, .drop, 0));
        },
        .colon_name => {
            self.beginDefinition(try self.appendWord(token, .colon, .drop, 0));
        },
        .variable_name, .value_name, .watched_value_name, .watched_variable_name => {
            const variable = pending == .variable_name or pending == .watched_variable_name;
            const id = try self.appendDataWord(token, if (variable) .variable else .value, cell_size);
            try self.writeCell(self.words[id].value, if (variable) 0 else self.pending_constant);
            // ~~VALUE: the TOs of this value are shown; ~~VARIABLE: the uses of its name.
            if (defs.debug_enabled and (pending == .watched_value_name or pending == .watched_variable_name)) try words_debug.watch(self, id);
            // A variable can take a DOES> part, as in gforth, where VARIABLE is CREATE 0 ,.
            if (variable) self.last_created_word = id;
        },
        .fvariable_name => {
            const id = try self.appendDataWord(token, .variable, float_size);
            try self.writeFloat(self.words[id].value, 0);
            self.last_created_word = id;
        },
        .constant_name => {
            _ = try self.appendWord(token, .constant, .drop, self.pending_constant);
        },
        .aconstant_name => {
            const id = try self.appendWord(token, .constant, .drop, self.pending_constant);
            try @import("address_registry.zig").registerWord(self, id);
        },
        .avariable_name => {
            const id = try self.appendDataWord(token, .variable, cell_size);
            try self.writeCell(self.words[id].value, 0);
            try @import("address_registry.zig").registerMemory(self, self.words[id].value);
            self.last_created_word = id;
        },
        .fconstant_name => {
            _ = try self.appendWord(token, .fconstant, .drop, floatBits(self.pending_float));
        },
        .fvalue_name => {
            const id = try self.appendDataWord(token, .fvalue, float_size);
            try self.writeFloat(self.words[id].value, self.pending_float);
        },
        .string_value_name => {
            const cells = defs.doubleCells(self.pending_double);
            try @import("string_values.zig").define(self, token, cells.low, cells.high);
        },
        .two_value_name => {
            const id = try self.appendDataWord(token, .two_value, 2 * cell_size);
            try self.writeDouble(self.words[id].value, self.pending_double);
        },
        .buffer_name => {
            if (self.pending_array_size < 0 or self.pending_array_size > self.sizes.dataLimit()) return error.MemoryExhausted;
            _ = try self.appendDataWord(token, .created, self.pending_array_size);
        },
        .two_variable_name, .two_constant_name => {
            const id = try self.appendDataWord(token, if (pending == .two_constant_name) .two_constant else .variable, 2 * cell_size);
            try self.writeDouble(self.words[id].value, if (pending == .two_constant_name) self.pending_double else 0);
            if (pending == .two_variable_name) self.last_created_word = id;
        },
        .array_name => {
            if (self.pending_array_size < 0 or self.pending_array_size > @divTrunc(self.sizes.dataLimit(), cell_size)) return error.MemoryExhausted;
            _ = try self.appendDataWord(token, .array, self.pending_array_size * cell_size);
        },
        .forget_name => {
            const id = try self.lookupOrFail(token);
            if (id < self.builtin_count) return error.InvalidDefinition;
            self.forgetFrom(id);
        },
        .tick_name => {
            const id = @import("word_semantics.zig").interpretation(self, try self.lookupOrFail(token));
            if (self.compiling) {
                _ = try self.emit(.{ .kind = .execution_token, .value = id });
            } else try self.push(id);
        },
        .to_name, .plus_to_name, .action_of_name => try finishAssignment(self, pending, token, self.compiling),
        // The code point of the first character, as in gforth (CHAR 日 is 26085).
        .char_name => {
            const code = words_xchar.decode(token).code;
            if (self.compiling) {
                _ = try self.emit(.{ .kind = .literal, .value = code });
            } else try self.push(code);
        },
        .postpone_name => {
            if (!self.compiling) return error.CompileOnly;
            const action = @import("word_semantics.zig").compilation(self, try self.lookupOrFail(token));
            _ = try self.emit(.{ .kind = if (action.execute) .call else .compile_call, .value = action.target });
        },
    }
}

pub fn endDefinition(self: *State) RuntimeError!void {
    if (self.quote_depth != 0 and !self.quote_closing) return error.ControlMismatch;
    if (!self.defining or !self.compiling) return error.CompileOnly;
    if (self.current_word >= self.word_count) return error.InvalidDefinition;
    if (self.control_depth != 0) return error.ControlMismatch;
    _ = try self.emit(.{ .kind = .exit });
    self.words[self.current_word].code_end = self.code_count;
    self.words[self.current_word].locals_size = self.locals_frame_size;
    if (self.currentFileFrame()) |frame| {
        if (self.words[self.current_word].source_file == frame.file_index + 1) self.words[self.current_word].source_end_line = frame.line;
    }
    @import("words_parsing.zig").resolve(self, self.current_word);
    try @import("words_value_extensions.zig").finishColon(self, self.current_word);
    self.local_count = 0;
    self.setCompiling(false);
    self.defining = false;
}

/// >BODY: the data area of a word that has one. CONSTANT and FCONSTANT keep their
/// value in the dictionary entry, so they have none here (gforth gives an address).
pub fn bodyAddress(self: *State, id: u16) RuntimeError!Cell {
    const word = self.words[self.synonymTarget(id)];
    return switch (word.kind) {
        .variable, .array, .created, .value, .fvalue, .two_constant, .two_value, .deferred, .string_value => word.value,
        else => error.InvalidExecutionToken,
    };
}

pub fn isDefiningBuiltin(builtin: Builtin) bool {
    return switch (builtin) {
        .define_colon, .define_variable, .define_fvariable, .define_constant, .define_value, .define_two_variable, .define_two_constant, .define_fconstant, .define_fvalue, .define_two_value, .define_buffer, .define_array, .define_watched_value, .define_watched_variable, .define_aconstant, .define_avariable, .define_string_value, .define_replacer => true,
        else => false,
    };
}

/// Runs a defining word from a definition: takes its value from the stack, then
/// reads the new word's name from the input, as interpreting the word would.
pub fn runDefiningWord(self: *State, builtin: Builtin) RuntimeError!void {
    const pending = try self.definingPending(builtin);
    const name = (try @import("quotations.zig").definitionName(self)) orelse return error.InvalidDefinition;
    self.pending = pending;
    try self.finishPending(name);
}

/// Takes a defining word's value from the stack and returns what its name makes.
pub fn definingPending(self: *State, builtin: Builtin) RuntimeError!Pending {
    return switch (builtin) {
        .define_replacer => blk: {
            if (self.defining) return error.InvalidDefinition;
            break :blk .replacer_name;
        },
        .define_colon => blk: {
            if (self.defining) return error.InvalidDefinition;
            break :blk .colon_name;
        },
        .define_aconstant => blk: {
            try @import("address_registry.zig").ensureRoom(self, .word, self.word_count);
            self.pending_constant = try self.pop();
            break :blk .aconstant_name;
        },
        .define_avariable => blk: {
            try @import("address_registry.zig").ensureRoom(self, .memory, self.data_here);
            break :blk .avariable_name;
        },
        .define_variable => .variable_name,
        .define_fvariable => .fvariable_name,
        .define_constant => blk: {
            self.pending_constant = try self.pop();
            break :blk .constant_name;
        },
        .define_string_value => blk: {
            self.pending_double = try self.popDouble();
            break :blk .string_value_name;
        },
        .define_value => blk: {
            self.pending_constant = try self.pop();
            break :blk .value_name;
        },
        .define_watched_value => blk: {
            self.pending_constant = try self.pop();
            break :blk .watched_value_name;
        },
        .define_watched_variable => .watched_variable_name,
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

/// Shared assignment mechanics; an EXECUTEd interpretation token never compiles.
pub fn finishAssignment(self: *State, pending: Pending, token: []const u8, compile: bool) RuntimeError!void {
    switch (pending) {
        .to_name => {
            if (compile) {
                if (self.findLocal(token)) |local| {
                    if (local.variable) return error.InvalidDefinition;
                    _ = try self.emit(.{ .kind = .local_store, .value = localOperand(local) });
                    return;
                }
            }
            const id = self.synonymTarget(try self.lookupOrFail(token));
            const kind = self.words[id].kind;
            if (kind != .value and kind != .fvalue and kind != .two_value and kind != .string_value and kind != .deferred) return error.InvalidDefinition;
            if (defs.debug_enabled and words_debug.isWatched(self, id)) try words_debug.watchStoreAction(self, id, token.len, compile);
            if (compile) {
                _ = try self.emit(.{ .kind = .store_value, .value = id });
            } else switch (kind) {
                .fvalue => try self.writeFloat(self.words[id].value, try self.fpop()),
                .two_value => try self.writeDouble(self.words[id].value, try self.popDouble()),
                .string_value => try @import("string_values.zig").store(self, id, false),
                else => try self.writeCell(self.words[id].value, try self.pop()),
            }
        },
        .plus_to_name => {
            if (compile) {
                if (self.findLocal(token)) |local| {
                    if (local.variable) return error.InvalidDefinition;
                    const add: Builtin = switch (local.kind) {
                        .float => .f_add,
                        .double => .d_add,
                        else => .add,
                    };
                    _ = try self.emit(.{ .kind = .local_fetch, .value = localOperand(local) });
                    _ = try self.emit(.{ .kind = .builtin, .value = @backingInt(add) });
                    _ = try self.emit(.{ .kind = .local_store, .value = localOperand(local) });
                    return;
                }
            }
            const id = self.synonymTarget(try self.lookupOrFail(token));
            const kind = self.words[id].kind;
            if (kind != .value and kind != .fvalue and kind != .two_value and kind != .string_value) return error.InvalidDefinition;
            if (compile) {
                _ = try self.emit(.{ .kind = .add_value, .value = id });
            } else try self.addToValue(id);
        },
        // ACTION-OF name gives the DEFER's action; compiled, as DEFER@ when the definition runs.
        .action_of_name => {
            const id = self.synonymTarget(try self.lookupOrFail(token));
            if (self.words[id].kind != .deferred) return error.InvalidDefinition;
            if (compile) {
                _ = try self.emit(.{ .kind = .execution_token, .value = id });
                _ = try self.emit(.{ .kind = .builtin, .value = @backingInt(Builtin.defer_fetch) });
            } else try self.push(try self.readCell(self.words[id].value));
        },
        else => unreachable,
    }
}
