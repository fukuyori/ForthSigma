//! Deferred words, COMPILE, and its relatives, and the words that define structures.

const defs = @import("defs.zig");
const forth = @import("../forth.zig");
const memory_map = @import("memory_map.zig");
const Builtin = defs.Builtin;
const Cell = memory_map.Cell;
const RuntimeError = defs.RuntimeError;
const State = forth.State;
const cellsDouble = defs.cellsDouble;
const cell_size = memory_map.cell_size;
const errno_no_memory = memory_map.errno_no_memory;
const float_size = memory_map.float_size;

/// The action of a DEFER word that IS has not set yet.
pub const uninitialized_defer: Cell = -1;

/// The built-in words this file executes; executeBuiltin dispatches by this list.
pub const words = [_]Builtin{
    .define_defer, .defer_store, .defer_fetch, .defers, .compile_comma, .bracket_compile,
    .name_to_compile, .begin_structure, .end_structure, .plus_field, .field_cell, .field_char,
    .field_float, .field_sfloat, .field_dfloat, .struct_start, .end_struct, .struct_field,
    .cell_percent, .char_percent, .float_percent, .double_percent, .sfloat_percent,
    .dfloat_percent, .percent_size, .percent_alignment, .percent_align, .percent_allot,
    .percent_alloc, .percent_allocate,
};

pub fn execute(self: *State, comptime builtin: Builtin) RuntimeError!void {
    switch (builtin) {
        .define_defer => {
            const name = (try self.nextSourceToken()) orelse return error.InvalidDefinition;
            const id = try self.appendDataWord(name, .deferred, cell_size);
            try self.writeCell(self.words[id].value, uninitialized_defer);
        },
        // DEFER! ( xt2 xt1 -- ) and DEFER@ ( xt1 -- xt2 ) set and give a DEFER's action.
        .defer_store => {
            const action = try deferAction(self, try self.pop());
            try self.writeCell(action, try self.pop());
        },
        .defer_fetch => try self.push(try self.readCell(try deferAction(self, try self.pop()))),
        // DEFERS name compiles the action that the DEFER has now.
        .defers => {
            try self.requireCompiling();
            const name = (try self.nextSourceToken()) orelse return error.InputUnavailable;
            const action = try self.readCell(try deferAction(self, try self.lookupOrFail(name)));
            // gforth compiles the word that warns; Sigma has no such word, so it is an error.
            if (action == uninitialized_defer) return error.InvalidDefinition;
            _ = try self.emit(.{ .kind = .call, .value = try self.wordId(action) });
        },
        // COMPILE, ( xt -- ) appends xt's execution to the definition being made. gforth
        // also compiles outside a definition, with a warning; Sigma has no code to add to.
        .compile_comma => {
            if (!self.defining) return error.CompileOnly;
            _ = try self.emit(.{ .kind = .call, .value = try self.wordId(try self.pop()) });
        },
        // [COMPILE] name appends name's execution, for an immediate word as for any other.
        .bracket_compile => {
            try self.requireCompiling();
            const name = (try self.nextSourceToken()) orelse return error.InputUnavailable;
            // A local variable is not a dictionary word; gforth does not compile one either.
            if (self.findLocal(name) != null) return error.InvalidDefinition;
            _ = try self.emit(.{ .kind = .call, .value = try self.lookupOrFail(name) });
        },
        // NAME>COMPILE ( nt -- xt1 xt2 ): xt2 is EXECUTE for an immediate word, COMPILE, for others.
        .name_to_compile => {
            const id = try self.validNameToken(try self.pop());
            try self.push(id);
            try self.push(self.builtinWord(if (self.words[id].immediate) .execute else .compile_comma));
        },
        // BEGIN-STRUCTURE name ( -- addr 0 ): name is a VALUE that END-STRUCTURE sets to
        // the size, as in gforth.
        .begin_structure => {
            const name = (try self.nextSourceToken()) orelse return error.InvalidDefinition;
            const id = try self.appendDataWord(name, .value, cell_size);
            try self.writeCell(self.words[id].value, 0);
            try self.push(self.words[id].value);
            try self.push(0);
        },
        .end_structure => {
            const size = try self.pop();
            try self.writeCell(try self.pop(), size);
        },
        // +FIELD ( n1 n2 "name" -- n3 ) and FIELD: and its relatives, which first align n1.
        .plus_field => {
            const size = try self.pop();
            const offset = try self.pop();
            try defineField(self, offset, size);
        },
        .field_cell, .field_char, .field_float, .field_sfloat, .field_dfloat => {
            const size: Cell = switch (builtin) {
                .field_cell => cell_size,
                .field_char => 1,
                .field_sfloat => 4,
                else => float_size,
            };
            try defineField(self, alignUp(try self.pop(), size), size);
        },
        // gforth's older structures: STRUCT ( -- align size ), FIELD ( align1 offset1
        // align size "name" -- align2 offset2 ), END-STRUCT ( align size "name" -- ).
        .struct_start => {
            try self.push(1);
            try self.push(0);
        },
        .struct_field => {
            const size = try self.pop();
            const alignment = try self.pop();
            const offset = alignUp(try self.pop(), alignment);
            const struct_alignment = try self.pop();
            try self.push(@max(struct_alignment, alignment));
            try defineField(self, offset, size);
        },
        .end_struct => {
            const size = try self.pop();
            const alignment = try self.pop();
            const name = (try self.nextSourceToken()) orelse return error.InvalidDefinition;
            const id = try self.appendDataWord(name, .two_constant, 2 * cell_size);
            try self.writeDouble(self.words[id].value, cellsDouble(alignment, alignUp(size, alignment)));
        },
        .cell_percent, .char_percent, .float_percent, .double_percent, .sfloat_percent, .dfloat_percent => {
            const alignment: Cell, const size: Cell = switch (builtin) {
                .cell_percent => .{ cell_size, cell_size },
                .char_percent => .{ 1, 1 },
                .double_percent => .{ cell_size, 2 * cell_size },
                .sfloat_percent => .{ 4, 4 },
                else => .{ float_size, float_size },
            };
            try self.push(alignment);
            try self.push(size);
        },
        .percent_size => {
            const size = try self.pop();
            _ = try self.pop();
            try self.push(size);
        },
        .percent_alignment => {
            _ = try self.pop();
        },
        // %ALIGN ( align size -- ) aligns HERE; %ALLOT ( align size -- addr ) then allots.
        .percent_align, .percent_allot => {
            const size = try self.pop();
            const alignment = try self.pop();
            try self.reserveData(alignUp(self.data_here, alignment) - self.data_here);
            if (builtin == .percent_allot) {
                try self.push(self.data_here);
                try self.reserveData(size);
            }
        },
        // %ALLOC ( align size -- addr ) throws when there is no memory; %ALLOCATE gives an ior.
        .percent_alloc, .percent_allocate => {
            const size = try self.pop();
            _ = try self.pop();
            const address = if (size < 0) null else try self.heapAllocate(@intCast(size));
            if (builtin == .percent_alloc) {
                try self.push(address orelse return self.throwIor(errno_no_memory));
            } else {
                try self.push(address orelse 0);
                try self.push(if (address == null) forth.errnoIor(errno_no_memory) else 0);
            }
        },
        else => @compileError(@tagName(builtin) ++ " is not in the words of this file"),
    }
}

/// The address of the action of a DEFER word given by its execution token.
pub fn deferAction(self: *State, xt: Cell) RuntimeError!Cell {
    const word = self.words[self.synonymTarget(try self.wordId(xt))];
    if (word.kind != .deferred) return error.InvalidExecutionToken;
    return word.value;
}

/// Makes a field named by the next word that adds `offset` to an address, and pushes
/// the offset after it.
fn defineField(self: *State, offset: Cell, size: Cell) RuntimeError!void {
    const name = (try self.nextSourceToken()) orelse return error.InvalidDefinition;
    _ = try self.appendWord(name, .field, .drop, offset);
    try self.push(offset +% size);
}

/// Rounds `value` up to a multiple of `alignment`; an alignment below 2 leaves it as it is.
fn alignUp(value: Cell, alignment: Cell) Cell {
    if (alignment < 2) return value;
    const over = @mod(value, alignment);
    return if (over == 0) value else value +% (alignment - over);
}
