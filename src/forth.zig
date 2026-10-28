const std = @import("std");

pub const Cell = u16;
const max_words = 1024;
const max_code = 8192;
const max_stack = 1024;
const max_controls = 128;
const max_name = 255;
const memory_size = 65536;
const base_address: Cell = 0x0200;

pub const Writer = struct {
    context: ?*anyopaque,
    write_fn: *const fn (?*anyopaque, []const u8) void,
    read_fn: ?*const fn (?*anyopaque, []u8) ?[]const u8 = null,
    load_fn: ?*const fn (?*anyopaque, []const u8, *State) RuntimeError!void = null,
    save_fn: ?*const fn (?*anyopaque, []const u8, *State) RuntimeError!void = null,
    savesys_fn: ?*const fn (?*anyopaque, []const u8, *State) RuntimeError!void = null,

    pub fn write(self: Writer, bytes: []const u8) void {
        self.write_fn(self.context, bytes);
    }
};

const Builtin = enum {
    drop,
    dup,
    swap,
    over,
    rot,
    to_r,
    from_r,
    add,
    sub,
    mul,
    div,
    mod,
    div_mod,
    negate,
    abs,
    one_minus,
    max,
    min,
    equal,
    not_equal,
    less,
    greater,
    less_equal,
    greater_equal,
    logical_not,
    zero_equal,
    bit_and,
    bit_or,
    bit_xor,
    bit_complement,
    bit_nand,
    bit_nor,
    swap_bytes,
    comma,
    c_comma,
    execute,
    fetch,
    store,
    cfetch,
    cstore,
    add_store,
    inc_store,
    dec_store,
    zero_store,
    question,
    array_fetch,
    array_store,
    dot,
    c_dot,
    echo,
    cr,
    space,
    spaces,
    type,
    hex,
    dec,
    oct,
    base,
    here,
    allot,
    index,
    index_2,
    index_3,
    leave,
    builds,
    words,
    input,
    bye,
    load,
    save,
    savesys,
};

const WordKind = enum { builtin, colon, variable, constant, array, created };
const Word = struct {
    name: [max_name]u8 = [_]u8{0} ** max_name,
    name_len: u8 = 0,
    kind: WordKind = .builtin,
    builtin: Builtin = .drop,
    value: Cell = 0,
    code_start: u16 = 0,
    code_end: u16 = 0,
    does_code_start: u16 = 0,
    does_code_end: u16 = 0,
    has_does: bool = false,
    data_here_before: Cell = 0,
};

const OpKind = enum { call, literal, execution_token, branch, branch_zero, do_loop, q_do_loop, loop, plus_loop, print_string, string_literal, does, exit };
const Op = struct { kind: OpKind, value: u16 = 0 };
const ControlKind = enum { if_branch, else_branch, begin_loop, while_branch, do_loop };
const Control = struct { kind: ControlKind, address: u16 };
const Loop = struct { index: Cell, limit: Cell, leave: bool = false, exit_after_first: bool = false };
const Pending = enum { none, colon_name, variable_name, constant_name, array_name, forget_name, tick_name };

pub const RuntimeError = error{
    StackUnderflow,
    ReturnStackUnderflow,
    StackOverflow,
    ReturnStackOverflow,
    DictionaryFull,
    CodeFull,
    NameTooLong,
    InvalidDefinition,
    CommentUnclosed,
    ControlMismatch,
    ControlStackOverflow,
    CompileOnly,
    UnknownWord,
    InvalidNumber,
    DivisionByZero,
    LoopMismatch,
    InvalidBase,
    InvalidExecutionToken,
    MemoryExhausted,
    InputUnavailable,
    FileUnavailable,
    InvalidImage,
};

fn writeU32(output: []u8, value: anytype) void {
    const number: u32 = @intCast(value);
    output[0] = @truncate(number);
    output[1] = @truncate(number >> 8);
    output[2] = @truncate(number >> 16);
    output[3] = @truncate(number >> 24);
}

fn readU32(input: []const u8) u32 {
    return @as(u32, input[0]) | (@as(u32, input[1]) << 8) | (@as(u32, input[2]) << 16) | (@as(u32, input[3]) << 24);
}

pub const State = struct {
    writer: Writer,
    memory: [memory_size]u8 = [_]u8{0} ** memory_size,
    words: [max_words]Word = undefined,
    word_count: u16 = 0,
    builtin_count: u16 = 0,
    code: [max_code]Op = undefined,
    code_count: u16 = 0,
    data_stack: [max_stack]Cell = [_]Cell{0} ** max_stack,
    data_depth: usize = 0,
    return_stack: [max_stack]Cell = [_]Cell{0} ** max_stack,
    return_depth: usize = 0,
    control_stack: [max_controls]Control = undefined,
    control_depth: usize = 0,
    loop_stack: [max_stack]Loop = undefined,
    loop_depth: usize = 0,
    data_here: Cell = 0x4000,
    compiling: bool = false,
    defining: bool = false,
    current_word: u16 = 0,
    current_data_start: Cell = 0,
    pending: Pending = .none,
    pending_constant: Cell = 0,
    pending_array_size: Cell = 0,
    source_line: []const u8 = &.{},
    source_cursor: usize = 0,
    source_buffer: [4096]u8 = undefined,
    last_created_word: ?u16 = null,
    halted: bool = false,
    call_depth: usize = 0,
    last_unknown_word: ?[]const u8 = null,

    pub fn init(writer: Writer) State {
        var state = State{ .writer = writer };
        state.memory[base_address] = 10;
        state.installBuiltins();
        return state;
    }

    pub fn write(self: *State, bytes: []const u8) void {
        self.writer.write(bytes);
    }

    pub fn imageCapacity() usize {
        return 20 + max_words * @sizeOf(Word) + max_code * @sizeOf(Op) + memory_size;
    }

    pub fn encodeImage(self: *State, output: []u8) RuntimeError!usize {
        const required = 20 + @as(usize, self.word_count) * @sizeOf(Word) + @as(usize, self.code_count) * @sizeOf(Op) + memory_size;
        if (output.len < required) return error.InvalidImage;
        @memcpy(output[0..8], "SIGIMG01");
        writeU32(output[8..12], self.word_count);
        writeU32(output[12..16], self.code_count);
        writeU32(output[16..20], self.data_here);
        var cursor: usize = 20;
        const word_bytes = std.mem.sliceAsBytes(self.words[0..self.word_count]);
        @memcpy(output[cursor .. cursor + word_bytes.len], word_bytes);
        cursor += word_bytes.len;
        const code_bytes = std.mem.sliceAsBytes(self.code[0..self.code_count]);
        @memcpy(output[cursor .. cursor + code_bytes.len], code_bytes);
        cursor += code_bytes.len;
        @memcpy(output[cursor .. cursor + memory_size], &self.memory);
        return required;
    }

    pub fn restoreImage(self: *State, input: []const u8) RuntimeError!void {
        if (input.len < 20 or !std.mem.eql(u8, input[0..8], "SIGIMG01")) return error.InvalidImage;
        const word_count = readU32(input[8..12]);
        const code_count = readU32(input[12..16]);
        const data_here = readU32(input[16..20]);
        if (word_count < self.builtin_count or word_count > max_words or code_count > max_code or data_here < 0x4000 or data_here > std.math.maxInt(Cell)) return error.InvalidImage;
        const word_bytes_len = @as(usize, word_count) * @sizeOf(Word);
        const code_bytes_len = @as(usize, code_count) * @sizeOf(Op);
        const required = 20 + word_bytes_len + code_bytes_len + memory_size;
        if (input.len != required) return error.InvalidImage;
        var cursor: usize = 20;
        @memcpy(std.mem.sliceAsBytes(self.words[0..word_count]), input[cursor .. cursor + word_bytes_len]);
        cursor += word_bytes_len;
        @memcpy(std.mem.sliceAsBytes(self.code[0..code_count]), input[cursor .. cursor + code_bytes_len]);
        cursor += code_bytes_len;
        @memcpy(&self.memory, input[cursor .. cursor + memory_size]);
        self.word_count = @intCast(word_count);
        self.code_count = @intCast(code_count);
        self.data_here = @intCast(data_here);
        self.data_depth = 0;
        self.return_depth = 0;
        self.control_depth = 0;
        self.loop_depth = 0;
        self.compiling = false;
        self.defining = false;
        self.pending = .none;
    }

    pub fn appendImage(self: *State, source: *const State) RuntimeError!void {
        if (source.builtin_count != self.builtin_count or source.word_count < source.builtin_count) return error.InvalidImage;
        const added_words: usize = source.word_count - source.builtin_count;
        const word_base: usize = self.word_count;
        const code_base: usize = self.code_count;
        const code_count: usize = source.code_count;
        const data_base: usize = self.data_here;
        if (word_base + added_words > max_words) return error.DictionaryFull;
        if (code_base + code_count > max_code) return error.CodeFull;
        if (source.data_here < 0x4000) return error.InvalidImage;
        const data_len: usize = source.data_here - 0x4000;
        if (data_base + data_len > std.math.maxInt(Cell)) return error.MemoryExhausted;
        const data_delta = data_base - 0x4000;

        for (source.words[source.builtin_count..source.word_count], 0..) |original, offset| {
            var word = original;
            word.data_here_before = @intCast(@as(usize, word.data_here_before) + data_delta);
            if (word.kind == .colon) {
                word.code_start = @intCast(@as(usize, word.code_start) + code_base);
                word.code_end = @intCast(@as(usize, word.code_end) + code_base);
            }
            if (word.has_does) {
                word.does_code_start = @intCast(@as(usize, word.does_code_start) + code_base);
                word.does_code_end = @intCast(@as(usize, word.does_code_end) + code_base);
            }
            if (word.kind == .variable or word.kind == .array or word.kind == .created)
                word.value = @intCast(@as(usize, word.value) + data_delta);
            self.words[word_base + offset] = word;
        }

        for (source.code[0..source.code_count], 0..) |original, offset| {
            var op = original;
            switch (op.kind) {
                .call, .execution_token => if (op.value >= source.builtin_count) {
                    op.value = @intCast(word_base + (op.value - source.builtin_count));
                },
                .branch, .branch_zero, .do_loop, .q_do_loop, .loop, .plus_loop => {
                    op.value = @intCast(@as(usize, op.value) + code_base);
                },
                .print_string, .string_literal => {
                    op.value = @intCast(@as(usize, op.value) + data_delta);
                },
                .literal, .does, .exit => {},
            }
            self.code[code_base + offset] = op;
        }
        @memcpy(self.memory[data_base .. data_base + data_len], source.memory[0x4000..source.data_here]);
        self.word_count = @intCast(word_base + added_words);
        self.code_count = @intCast(code_base + code_count);
        self.data_here = @intCast(data_base + data_len);
        self.last_created_word = null;
    }

    pub fn report(self: *State, err: anyerror) void {
        if (self.defining) {
            self.code_count = self.words[self.current_word].code_start;
            self.word_count = self.current_word;
            self.data_here = self.current_data_start;
        }
        self.compiling = false;
        self.defining = false;
        self.pending = .none;
        self.control_depth = 0;
        self.data_depth = 0;
        self.return_depth = 0;
        self.loop_depth = 0;
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
        const message: []const u8 = if (err == error.StackUnderflow) "STACK UNDER FLOW !" else if (err == error.ReturnStackUnderflow) "RETURN STACK UNDER FLOW !" else if (err == error.StackOverflow) "STACK OVER FLOW !" else if (err == error.ReturnStackOverflow) "RETURN STACK OVER FLOW !" else if (err == error.DictionaryFull) "OUT OF DICTIONARY !" else if (err == error.CodeFull) "OUT OF CODE SPACE !" else if (err == error.InvalidDefinition) "DEFINITION ERROR !" else if (err == error.CommentUnclosed) "END OF COMMENT MUST BE \")\" !" else if (err == error.ControlMismatch) "CONTROL STRUCTURE ERROR !" else if (err == error.CompileOnly) "COMPILE MODE ERROR !" else if (err == error.UnknownWord) "?" else if (err == error.InvalidNumber) "NUMBER ERROR !" else if (err == error.DivisionByZero) "DIVISION BY ZERO !" else if (err == error.LoopMismatch) "LOOP ERROR !" else if (err == error.InvalidBase) "BASE ERROR !" else if (err == error.InvalidExecutionToken) "INVALID EXECUTION TOKEN !" else if (err == error.MemoryExhausted) "OUT OF MEMORY !" else if (err == error.InputUnavailable) "INPUT ERROR !" else if (err == error.FileUnavailable) "FILE ERROR !" else if (err == error.InvalidImage) "INVALID IMAGE !" else "FORTH ERROR !";
        self.write(message);
        self.write("\n");
    }

    pub fn interpretLine(self: *State, input: []const u8) RuntimeError!void {
        const previous_line = self.source_line;
        const previous_cursor = self.source_cursor;
        self.source_line = input;
        self.source_cursor = 0;
        self.last_created_word = null;
        defer {
            self.source_line = previous_line;
            self.source_cursor = previous_cursor;
        }
        self.last_unknown_word = null;
        var line = input;
        var cursor: usize = 0;
        while (true) {
            const token = nextToken(line, &cursor) orelse break;
            self.source_line = line;
            self.source_cursor = cursor;
            if (self.pending != .none) {
                try self.finishPending(token);
                continue;
            }
            if (std.mem.eql(u8, token, "(")) {
                const close = std.mem.indexOfScalarPos(u8, line, cursor, ')') orelse return error.CommentUnclosed;
                cursor = close + 1;
                continue;
            }
            if (std.mem.eql(u8, token, "\"")) {
                try self.handleStringToken(line, &cursor, false);
                self.source_cursor = cursor;
                continue;
            }
            if (std.mem.startsWith(u8, token, ".\"")) {
                try self.handleStringToken(line, &cursor, true);
                self.source_cursor = cursor;
                continue;
            }
            try self.handleToken(token);
            line = self.source_line;
            cursor = self.source_cursor;
            if (self.halted) break;
        }
    }

    fn installBuiltins(self: *State) void {
        const definitions = [_]struct { []const u8, Builtin }{
            .{ "DROP", .drop },       .{ "DUP", .dup },         .{ "SWAP", .swap },        .{ "OVER", .over },          .{ "ROT", .rot },
            .{ ">R", .to_r },         .{ "R>", .from_r },       .{ "+", .add },            .{ "-", .sub },              .{ "*", .mul },
            .{ "/", .div },           .{ "MOD", .mod },         .{ "/MOD", .div_mod },     .{ "MINUS", .negate },       .{ "ABS", .abs },
            .{ "MAX", .max },         .{ "MIN", .min },         .{ "=", .equal },          .{ "<>", .not_equal },       .{ "<", .less },
            .{ ">", .greater },       .{ "<=", .less_equal },   .{ ">=", .greater_equal }, .{ "NOT", .logical_not },    .{ "0=", .zero_equal },
            .{ "AND", .bit_and },     .{ "OR", .bit_or },       .{ "XOR", .bit_xor },      .{ "COM", .bit_complement }, .{ "NAND", .bit_nand },
            .{ "NOR", .bit_nor },     .{ "SWAB", .swap_bytes }, .{ "1-", .one_minus },     .{ "@", .fetch },            .{ "!", .store },
            .{ ",", .comma },         .{ "C,", .c_comma },      .{ "EXECUTE", .execute },  .{ "C@", .cfetch },          .{ "C!", .cstore },
            .{ "+!", .add_store },    .{ "1+!", .inc_store },   .{ "1-!", .dec_store },    .{ "OSET", .zero_store },    .{ "?", .question },
            .{ "A@", .array_fetch },  .{ "A!", .array_store },  .{ ".", .dot },            .{ "C.", .c_dot },           .{ "ECHO", .echo },
            .{ "CR", .cr },           .{ "SPACE", .space },     .{ "SPCES", .spaces },     .{ "TYPE", .type },          .{ "HEX", .hex },
            .{ "DEC", .dec },         .{ "OCT", .oct },         .{ "BASE", .base },        .{ "HERE", .here },          .{ "ALLOT", .allot },
            .{ "I", .index },         .{ "J", .index_2 },       .{ "K", .index_3 },        .{ "LEAVE", .leave },        .{ "WORDS", .words },
            .{ "BYE", .bye },         .{ "INPUT", .input },     .{ "<BUILDS", .builds },   .{ "LOAD", .load },          .{ "SAVE", .save },
            .{ "SAVESYS", .savesys },
        };
        for (definitions) |definition| self.addBuiltin(definition[0], definition[1]) catch unreachable;
        self.builtin_count = self.word_count;
    }

    fn addBuiltin(self: *State, name: []const u8, builtin: Builtin) RuntimeError!void {
        _ = try self.appendWord(name, .builtin, builtin, 0);
    }

    fn appendWord(self: *State, name: []const u8, kind: WordKind, builtin: Builtin, value: Cell) RuntimeError!u16 {
        if (self.word_count == max_words) return error.DictionaryFull;
        if (name.len == 0 or name.len > max_name) return error.NameTooLong;
        if (kind != .builtin and self.lookup(name) != null) {
            self.write("WARNING: SAME NAME WORD EXISTS\n");
        }
        const id = self.word_count;
        var word = Word{ .kind = kind, .builtin = builtin, .value = value, .name_len = @intCast(name.len), .data_here_before = self.data_here };
        @memcpy(word.name[0..name.len], name);
        if (kind == .colon) word.code_start = self.code_count;
        self.words[id] = word;
        self.word_count += 1;
        return id;
    }

    fn lookup(self: *State, name: []const u8) ?u16 {
        var i = self.word_count;
        while (i > 0) {
            i -= 1;
            const word = self.words[i];
            const stored_name = word.name[0..word.name_len];
            const compared_len = @min(stored_name.len, 5);
            if (stored_name.len == name.len and asciiEqlIgnoreCase(stored_name[0..compared_len], name[0..compared_len])) return i;
        }
        return null;
    }

    fn finishPending(self: *State, token: []const u8) RuntimeError!void {
        const pending = self.pending;
        self.pending = .none;
        switch (pending) {
            .none => unreachable,
            .colon_name => {
                const id = try self.appendWord(token, .colon, .drop, 0);
                self.current_word = id;
                self.current_data_start = self.words[id].data_here_before;
                self.compiling = true;
                self.defining = true;
            },
            .variable_name => {
                const address = self.data_here;
                try self.reserveData(2);
                const id = self.appendWord(token, .variable, .drop, address) catch |err| {
                    self.data_here = address;
                    return err;
                };
                self.words[id].data_here_before = address;
                self.writeCell(address, 0);
            },
            .constant_name => {
                _ = try self.appendWord(token, .constant, .drop, self.pending_constant);
            },
            .array_name => {
                const address = self.data_here;
                if (self.pending_array_size > 32767) return error.MemoryExhausted;
                const amount = self.pending_array_size *% 2;
                try self.reserveData(amount);
                const id = self.appendWord(token, .array, .drop, address) catch |err| {
                    self.data_here = address;
                    return err;
                };
                self.words[id].data_here_before = address;
            },
            .forget_name => {
                const id = self.lookup(token) orelse {
                    self.last_unknown_word = token;
                    return error.UnknownWord;
                };
                if (id < self.builtin_count) return error.InvalidDefinition;
                self.data_here = self.words[id].data_here_before;
                var first_removed_code = self.code_count;
                for (self.words[id..self.word_count]) |word| {
                    if (word.kind == .colon and word.code_start < first_removed_code)
                        first_removed_code = word.code_start;
                }
                self.code_count = first_removed_code;
                if (self.last_created_word) |created_id| {
                    if (created_id >= id) self.last_created_word = null;
                }
                self.word_count = id;
            },
            .tick_name => {
                const id = self.lookup(token) orelse {
                    self.last_unknown_word = token;
                    return error.UnknownWord;
                };
                if (self.compiling) {
                    _ = try self.emit(.{ .kind = .execution_token, .value = id });
                } else try self.push(id);
            },
        }
    }

    fn handleToken(self: *State, token: []const u8) RuntimeError!void {
        if (std.mem.eql(u8, token, ":")) {
            if (self.defining) return error.InvalidDefinition;
            self.pending = .colon_name;
            return;
        }
        if (std.mem.eql(u8, token, ";")) {
            if (!self.defining or !self.compiling) return error.CompileOnly;
            if (self.control_depth != 0) return error.ControlMismatch;
            _ = try self.emit(.{ .kind = .exit });
            self.words[self.current_word].code_end = self.code_count;
            self.compiling = false;
            self.defining = false;
            return;
        }
        if (std.mem.eql(u8, token, "[")) {
            if (!self.defining or !self.compiling) return error.CompileOnly;
            self.compiling = false;
            return;
        }
        if (std.mem.eql(u8, token, "]")) {
            if (!self.defining or self.compiling) return error.CompileOnly;
            self.compiling = true;
            return;
        }
        if (std.mem.eql(u8, token, "'")) {
            self.pending = .tick_name;
            return;
        }
        if (asciiEqlIgnoreCase(token, "VARIABLE") or asciiEqlIgnoreCase(token, "VAR")) {
            if (self.compiling) return error.CompileOnly;
            self.pending = .variable_name;
            return;
        }
        if (asciiEqlIgnoreCase(token, "CONSTANT") or asciiEqlIgnoreCase(token, "CONST")) {
            if (self.compiling) return error.CompileOnly;
            self.pending_constant = try self.pop();
            self.pending = .constant_name;
            return;
        }
        if (asciiEqlIgnoreCase(token, "ARRAY")) {
            if (self.compiling) return error.CompileOnly;
            self.pending_array_size = try self.pop();
            self.pending = .array_name;
            return;
        }
        if (asciiEqlIgnoreCase(token, "FORGET")) {
            if (self.compiling) return error.CompileOnly;
            self.pending = .forget_name;
            return;
        }
        if (try self.handleControl(token)) return;

        if (self.lookup(token)) |id| {
            const word = self.words[id];
            if (self.compiling) {
                _ = try self.emit(.{ .kind = .call, .value = id });
            } else {
                try self.executeWord(id);
            }
            _ = word;
            return;
        }
        if (try self.parseNumber(token)) |number| {
            if (self.compiling) {
                _ = try self.emit(.{ .kind = .literal, .value = number });
            } else {
                try self.push(number);
            }
            return;
        }
        self.last_unknown_word = token;
        return error.UnknownWord;
    }

    fn handleControl(self: *State, token: []const u8) RuntimeError!bool {
        if (asciiEqlIgnoreCase(token, "IF")) {
            try self.compileIf();
        } else if (asciiEqlIgnoreCase(token, "ELSE")) {
            try self.compileElse();
        } else if (asciiEqlIgnoreCase(token, "THEN")) {
            try self.compileThen();
        } else if (asciiEqlIgnoreCase(token, "BEGIN")) {
            try self.compileBegin();
        } else if (asciiEqlIgnoreCase(token, "END")) {
            try self.compileEnd();
        } else if (asciiEqlIgnoreCase(token, "WHILE")) {
            try self.compileWhile();
        } else if (asciiEqlIgnoreCase(token, "REPEAT")) {
            try self.compileRepeat();
        } else if (asciiEqlIgnoreCase(token, "DO")) {
            try self.compileDo(false);
        } else if (asciiEqlIgnoreCase(token, "?DO")) {
            try self.compileDo(true);
        } else if (asciiEqlIgnoreCase(token, "LOOP")) {
            try self.compileLoop(false);
        } else if (asciiEqlIgnoreCase(token, "+LOOP")) {
            try self.compileLoop(true);
        } else if (asciiEqlIgnoreCase(token, "DOES>")) {
            try self.compileDoes();
        } else return false;
        return true;
    }

    fn pushControl(self: *State, kind: ControlKind, address: u16) RuntimeError!void {
        if (!self.compiling) return error.CompileOnly;
        if (self.control_depth == max_controls) return error.ControlStackOverflow;
        self.control_stack[self.control_depth] = .{ .kind = kind, .address = address };
        self.control_depth += 1;
    }

    fn popControl(self: *State, expected: ControlKind) RuntimeError!Control {
        if (self.control_depth == 0) return error.ControlMismatch;
        self.control_depth -= 1;
        const item = self.control_stack[self.control_depth];
        if (item.kind != expected) {
            self.control_depth += 1;
            return error.ControlMismatch;
        }
        return item;
    }

    fn compileIf(self: *State) RuntimeError!void {
        if (!self.compiling) return error.CompileOnly;
        const at = try self.emit(.{ .kind = .branch_zero });
        try self.pushControl(.if_branch, at);
    }

    fn compileElse(self: *State) RuntimeError!void {
        const old = try self.popControl(.if_branch);
        const at = try self.emit(.{ .kind = .branch });
        self.patch(old.address, self.code_count);
        try self.pushControl(.else_branch, at);
    }

    fn compileThen(self: *State) RuntimeError!void {
        if (self.control_depth == 0) return error.ControlMismatch;
        const kind = self.control_stack[self.control_depth - 1].kind;
        if (kind != .if_branch and kind != .else_branch) return error.ControlMismatch;
        self.control_depth -= 1;
        self.patch(self.control_stack[self.control_depth].address, self.code_count);
    }

    fn compileBegin(self: *State) RuntimeError!void {
        if (!self.compiling) return error.CompileOnly;
        try self.pushControl(.begin_loop, self.code_count);
    }

    fn compileEnd(self: *State) RuntimeError!void {
        const begin = try self.popControl(.begin_loop);
        _ = try self.emit(.{ .kind = .branch_zero, .value = begin.address });
    }

    fn compileWhile(self: *State) RuntimeError!void {
        if (!self.compiling or self.control_depth == 0 or self.control_stack[self.control_depth - 1].kind != .begin_loop)
            return error.ControlMismatch;
        const begin = self.control_stack[self.control_depth - 1];
        const at = try self.emit(.{ .kind = .branch_zero });
        try self.pushControl(.while_branch, begin.address);
        self.control_stack[self.control_depth - 1].address = at;
    }

    fn compileRepeat(self: *State) RuntimeError!void {
        const wh = try self.popControl(.while_branch);
        if (self.control_depth == 0 or self.control_stack[self.control_depth - 1].kind != .begin_loop)
            return error.ControlMismatch;
        self.control_depth -= 1;
        _ = try self.emit(.{ .kind = .branch, .value = self.control_stack[self.control_depth].address });
        self.patch(wh.address, self.code_count);
    }

    fn compileDo(self: *State, conditional: bool) RuntimeError!void {
        if (!self.compiling) return error.CompileOnly;
        const at = try self.emit(.{ .kind = if (conditional) .q_do_loop else .do_loop });
        try self.pushControl(.do_loop, at);
    }

    fn compileLoop(self: *State, plus: bool) RuntimeError!void {
        const loop = try self.popControl(.do_loop);
        const body: u16 = loop.address + 1;
        _ = try self.emit(.{ .kind = if (plus) .plus_loop else .loop, .value = body });
        self.patch(loop.address, self.code_count);
    }

    fn compileDoes(self: *State) RuntimeError!void {
        if (!self.compiling or !self.defining) return error.CompileOnly;
        _ = try self.emit(.{ .kind = .does });
    }

    fn nextSourceToken(self: *State) ?[]const u8 {
        while (true) {
            if (nextToken(self.source_line, &self.source_cursor)) |token| return token;
            const read_fn = self.writer.read_fn orelse return null;
            const line = read_fn(self.writer.context, &self.source_buffer) orelse return null;
            self.source_line = line;
            self.source_cursor = 0;
        }
    }

    fn emit(self: *State, op: Op) RuntimeError!u16 {
        if (self.code_count == max_code) return error.CodeFull;
        const at = self.code_count;
        self.code[at] = op;
        self.code_count += 1;
        return at;
    }

    fn patch(self: *State, at: u16, target: u16) void {
        self.code[at].value = target;
    }

    fn executeWord(self: *State, id: u16) RuntimeError!void {
        const word = self.words[id];
        switch (word.kind) {
            .builtin => try self.executeBuiltin(word.builtin),
            .variable, .constant, .array => try self.push(word.value),
            .created => {
                try self.push(word.value);
                if (word.has_does) {
                    if (self.call_depth == max_stack) return error.ReturnStackOverflow;
                    self.call_depth += 1;
                    defer self.call_depth -= 1;
                    try self.executeOperations(word.does_code_start, word.does_code_end, null);
                }
            },
            .colon => try self.executeColon(id, word),
        }
    }

    fn executeColon(self: *State, id: u16, word: Word) RuntimeError!void {
        if (self.call_depth == max_stack) return error.ReturnStackOverflow;
        self.call_depth += 1;
        defer self.call_depth -= 1;
        try self.executeOperations(word.code_start, word.code_end, id);
    }

    fn executeOperations(self: *State, start_pc: u16, end_pc: u16, defining_word: ?u16) RuntimeError!void {
        var pc = start_pc;
        while (pc < end_pc and !self.halted) {
            const op = self.code[pc];
            pc += 1;
            switch (op.kind) {
                .call => try self.executeWord(op.value),
                .literal, .execution_token => try self.push(op.value),
                .branch => pc = op.value,
                .branch_zero => {
                    if (try self.pop() == 0) pc = op.value;
                },
                .do_loop, .q_do_loop => {
                    const start = try self.pop();
                    const limit = try self.pop();
                    if (op.kind == .q_do_loop and start == limit) {
                        pc = op.value;
                        continue;
                    }
                    if (self.loop_depth == max_stack) return error.StackOverflow;
                    self.loop_stack[self.loop_depth] = .{ .index = start, .limit = limit, .exit_after_first = start == limit };
                    self.loop_depth += 1;
                },
                .loop, .plus_loop => {
                    if (self.loop_depth == 0) return error.LoopMismatch;
                    const step: Cell = if (op.kind == .plus_loop) try self.pop() else 1;
                    const frame = &self.loop_stack[self.loop_depth - 1];
                    const old: i16 = @bitCast(frame.index);
                    const limit: i16 = @bitCast(frame.limit);
                    frame.index +%= step;
                    const after: i16 = @bitCast(frame.index);
                    const step_signed: i16 = @bitCast(step);
                    const crossed = if (step_signed > 0) old <= limit and after >= limit else if (step_signed < 0) old >= limit and after < limit else old == limit;
                    const again = if (frame.leave or frame.exit_after_first) false else if (op.kind == .loop) frame.index != frame.limit else !crossed;
                    if (again) {
                        pc = op.value;
                    } else {
                        self.loop_depth -= 1;
                    }
                },
                .print_string => {
                    const address = op.value;
                    const length = self.memory[address];
                    const start: usize = @as(usize, address) + 1;
                    if (start + length > self.memory.len) return error.MemoryExhausted;
                    self.write(self.memory[start .. start + length]);
                },
                .string_literal => {
                    const address = op.value;
                    const length = self.memory[address];
                    try self.push(length);
                    try self.push(address +% 1);
                },
                .does => {
                    const created_id = self.last_created_word orelse return error.InvalidDefinition;
                    const defining_id = defining_word orelse return error.InvalidDefinition;
                    self.words[created_id].does_code_start = pc;
                    self.words[created_id].does_code_end = self.words[defining_id].code_end;
                    self.words[created_id].has_does = true;
                    self.last_created_word = null;
                    return;
                },
                .exit => return,
            }
        }
    }

    fn executeBuiltin(self: *State, builtin: Builtin) RuntimeError!void {
        switch (builtin) {
            .drop => _ = try self.pop(),
            .dup => try self.push(self.peek(0) catch return error.StackUnderflow),
            .swap => {
                if (self.data_depth < 2) return error.StackUnderflow;
                std.mem.swap(Cell, &self.data_stack[self.data_depth - 1], &self.data_stack[self.data_depth - 2]);
            },
            .over => {
                if (self.data_depth < 2) return error.StackUnderflow;
                try self.push(self.data_stack[self.data_depth - 2]);
            },
            .rot => {
                if (self.data_depth < 3) return error.StackUnderflow;
                const a = self.data_stack[self.data_depth - 3];
                self.data_stack[self.data_depth - 3] = self.data_stack[self.data_depth - 2];
                self.data_stack[self.data_depth - 2] = self.data_stack[self.data_depth - 1];
                self.data_stack[self.data_depth - 1] = a;
            },
            .to_r => {
                const value = try self.pop();
                if (self.return_depth == max_stack) return error.ReturnStackOverflow;
                self.return_stack[self.return_depth] = value;
                self.return_depth += 1;
            },
            .from_r => {
                if (self.return_depth == 0) return error.ReturnStackUnderflow;
                self.return_depth -= 1;
                try self.push(self.return_stack[self.return_depth]);
            },
            .add, .sub, .mul, .div, .mod, .max, .min, .equal, .not_equal, .less, .greater, .less_equal, .greater_equal, .bit_and, .bit_or, .bit_xor, .bit_nand, .bit_nor => try self.binary(builtin),
            .div_mod => {
                const divisor = try self.pop();
                const dividend = try self.pop();
                if (divisor == 0) {
                    self.write("DIVISION BY ZERO\n");
                    try self.push(0);
                    try self.push(0x7fff);
                } else {
                    const a: i16 = @bitCast(dividend);
                    const b: i16 = @bitCast(divisor);
                    const quotient: Cell = if (a == -32768 and b == -1) dividend else @bitCast(@divTrunc(a, b));
                    const remainder: Cell = if (a == -32768 and b == -1) 0 else @bitCast(@rem(a, b));
                    try self.push(remainder);
                    try self.push(quotient);
                }
            },
            .swap_bytes => {
                const value = try self.pop();
                try self.push((value << 8) | (value >> 8));
            },
            .negate => {
                const a = try self.pop();
                try self.push(0 -% a);
            },
            .one_minus => try self.push((try self.pop()) -% 1),
            .abs => {
                const a = try self.pop();
                const signed: i16 = @bitCast(a);
                try self.push(if (signed < 0) 0 -% a else a);
            },
            .logical_not, .zero_equal => {
                const a = try self.pop();
                try self.push(if (a == 0) 1 else 0);
            },
            .bit_complement => try self.push(~(try self.pop())),
            .fetch => {
                const address = try self.pop();
                try self.push(self.readCell(address));
            },
            .store => {
                const address = try self.pop();
                const value = try self.pop();
                self.writeCell(address, value);
            },
            .cfetch => {
                const address = try self.pop();
                try self.push(self.memory[address]);
            },
            .cstore => {
                const address = try self.pop();
                const value = try self.pop();
                self.memory[address] = @truncate(value);
            },
            .add_store => {
                const address = try self.pop();
                const value = try self.pop();
                self.writeCell(address, self.readCell(address) +% value);
            },
            .inc_store, .dec_store => {
                const address = try self.pop();
                const old = self.readCell(address);
                self.writeCell(address, if (builtin == .inc_store) old +% 1 else old -% 1);
            },
            .zero_store => {
                const address = try self.pop();
                self.writeCell(address, 0);
            },
            .question => {
                const address = try self.pop();
                self.writeNumber(self.readCell(address), false);
            },
            .array_fetch => {
                const base = try self.pop();
                const index = try self.pop();
                const address = base +% (index *% 2);
                try self.push(self.readCell(address));
            },
            .array_store => {
                const base = try self.pop();
                const index = try self.pop();
                const value = try self.pop();
                const address = base +% (index *% 2);
                self.writeCell(address, value);
            },
            .dot => {
                const value = try self.pop();
                self.writeNumber(value, false);
            },
            .c_dot => {
                const value = try self.pop();
                self.writeNumber(@truncate(value), true);
            },
            .echo => {
                const value = try self.pop();
                const byte: [1]u8 = .{@truncate(value)};
                self.write(&byte);
            },
            .cr => self.write("\n"),
            .space => self.write(" "),
            .spaces => {
                const count = try self.pop();
                const signed: i16 = @bitCast(count);
                var i: Cell = 0;
                while (signed > 0 and i < count and i < 4096) : (i += 1) self.write(" ");
            },
            .type => {
                const address = try self.pop();
                const count = try self.pop() & 0x00ff;
                var offset: Cell = 0;
                while (offset < count) : (offset += 1) {
                    const byte: [1]u8 = .{self.memory[address +% offset]};
                    self.write(&byte);
                }
            },
            .hex => self.memory[base_address] = 16,
            .dec => self.memory[base_address] = 10,
            .oct => self.memory[base_address] = 8,
            .base => try self.push(base_address),
            .here => try self.push(self.data_here),
            .allot => {
                const amount = try self.pop();
                try self.reserveData(amount);
            },
            .builds => {
                const name = self.nextSourceToken() orelse return error.InvalidDefinition;
                const address = self.data_here;
                const id = try self.appendWord(name, .created, .drop, address);
                self.words[id].data_here_before = address;
                self.last_created_word = id;
            },
            .comma => {
                const value = try self.pop();
                const address = self.data_here;
                try self.reserveData(2);
                self.writeCell(address, value);
            },
            .c_comma => {
                const value = try self.pop();
                const address = self.data_here;
                try self.reserveData(1);
                self.memory[address] = @truncate(value);
            },
            .execute => {
                const id = try self.pop();
                if (id >= self.word_count) return error.InvalidExecutionToken;
                try self.executeWord(id);
            },
            .index => {
                if (self.loop_depth == 0) return error.LoopMismatch;
                try self.push(self.loop_stack[self.loop_depth - 1].index);
            },
            .index_2 => {
                if (self.loop_depth < 2) return error.LoopMismatch;
                try self.push(self.loop_stack[self.loop_depth - 2].index);
            },
            .index_3 => {
                if (self.loop_depth < 3) return error.LoopMismatch;
                try self.push(self.loop_stack[self.loop_depth - 3].index);
            },
            .leave => {
                if (self.loop_depth == 0) return error.LoopMismatch;
                const frame = &self.loop_stack[self.loop_depth - 1];
                frame.index = frame.limit;
                frame.leave = true;
            },
            .words => {
                for (self.words[0..self.word_count]) |word| {
                    self.write(word.name[0..word.name_len]);
                    self.write(" ");
                }
                self.write("\n");
            },
            .input => {
                var line: [4096]u8 = undefined;
                const read_fn = self.writer.read_fn orelse return error.InputUnavailable;
                while (true) {
                    const input = read_fn(self.writer.context, &line) orelse return error.InputUnavailable;
                    var cursor: usize = 0;
                    const token = nextToken(input, &cursor) orelse {
                        self.write(" ?\n");
                        continue;
                    };
                    const parsed = try self.parseNumber(token);
                    var trailing = false;
                    if (nextToken(input, &cursor) != null) trailing = true;
                    if (parsed == null or trailing) {
                        self.write(" ?\n");
                        continue;
                    }
                    try self.push(parsed.?);
                    break;
                }
            },
            .bye => self.halted = true,
            .load => {
                const path = self.nextSourceToken() orelse return error.InputUnavailable;
                const load_fn = self.writer.load_fn orelse return error.FileUnavailable;
                try load_fn(self.writer.context, path, self);
            },
            .save => {
                const path = self.nextSourceToken() orelse return error.InputUnavailable;
                const save_fn = self.writer.save_fn orelse return error.FileUnavailable;
                try save_fn(self.writer.context, path, self);
            },
            .savesys => {
                const path = self.nextSourceToken() orelse return error.InputUnavailable;
                const savesys_fn = self.writer.savesys_fn orelse return error.FileUnavailable;
                try savesys_fn(self.writer.context, path, self);
            },
        }
    }

    fn binary(self: *State, builtin: Builtin) RuntimeError!void {
        const b = try self.pop();
        const a = try self.pop();
        const sa: i16 = @bitCast(a);
        const sb: i16 = @bitCast(b);
        const result: Cell = switch (builtin) {
            .add => a +% b,
            .sub => a -% b,
            .mul => a *% b,
            .div => blk: {
                if (b == 0) {
                    self.write("DIVISION BY ZERO\n");
                    break :blk 0x7fff;
                }
                if (sa == -32768 and sb == -1) break :blk a;
                break :blk @bitCast(@divTrunc(sa, sb));
            },
            .mod => blk: {
                if (b == 0) {
                    self.write("DIVISION BY ZERO\n");
                    break :blk 0;
                }
                if (sa == -32768 and sb == -1) break :blk 0;
                break :blk @bitCast(@rem(sa, sb));
            },
            .max => if (sa > sb) a else b,
            .min => if (sa < sb) a else b,
            .equal => truth(a == b),
            .not_equal => truth(a != b),
            .less => truth(sa < sb),
            .greater => truth(sa > sb),
            .less_equal => truth(sa <= sb),
            .greater_equal => truth(sa >= sb),
            .bit_and => a & b,
            .bit_or => a | b,
            .bit_xor => a ^ b,
            .bit_nand => ~(a & b),
            .bit_nor => ~(a | b),
            else => unreachable,
        };
        try self.push(result);
    }

    fn truth(value: bool) Cell {
        return if (value) 1 else 0;
    }

    fn peek(self: *State, depth: usize) RuntimeError!Cell {
        if (depth >= self.data_depth) return error.StackUnderflow;
        return self.data_stack[self.data_depth - depth - 1];
    }

    fn pop(self: *State) RuntimeError!Cell {
        if (self.data_depth == 0) return error.StackUnderflow;
        self.data_depth -= 1;
        return self.data_stack[self.data_depth];
    }

    fn push(self: *State, value: Cell) RuntimeError!void {
        if (self.data_depth == max_stack) return error.StackOverflow;
        self.data_stack[self.data_depth] = value;
        self.data_depth += 1;
    }

    fn readCell(self: *State, address: Cell) Cell {
        const next: Cell = address +% 1;
        return @as(Cell, self.memory[address]) | (@as(Cell, self.memory[next]) << 8);
    }

    fn writeCell(self: *State, address: Cell, value: Cell) void {
        self.memory[address] = @truncate(value);
        self.memory[address +% 1] = @truncate(value >> 8);
    }

    fn reserveData(self: *State, amount: Cell) RuntimeError!void {
        const next = self.data_here +% amount;
        if (next < self.data_here and amount != 0) return error.MemoryExhausted;
        self.data_here = next;
    }

    fn parseNumber(self: *State, token: []const u8) RuntimeError!?Cell {
        if (token.len == 0) return null;
        const base = self.memory[base_address];
        if (base < 2 or base > 16) return error.InvalidBase;
        var i: usize = 0;
        var negative = false;
        if (token[0] == '-') {
            negative = true;
            i = 1;
        }
        if (i == token.len) return null;
        var value: Cell = 0;
        while (i < token.len) : (i += 1) {
            const c = token[i];
            const digit: u8 = if (c >= '0' and c <= '9') c - '0' else if (c >= 'A' and c <= 'F') c - 'A' + 10 else if (c >= 'a' and c <= 'f') c - 'a' + 10 else return null;
            if (digit >= base) return null;
            value = value *% base +% digit;
        }
        return if (negative) 0 -% value else value;
    }

    fn writeNumber(self: *State, value: Cell, byte_value: bool) void {
        const base = self.memory[base_address];
        if (base < 2 or base > 16) {
            self.write("?BASE?");
            return;
        }
        var n = value;
        var negative = false;
        if (base == 10 and (@as(i16, @bitCast(value)) < 0)) {
            negative = true;
            n = 0 -% value;
        }
        var digits: [16]u8 = undefined;
        var length: usize = 0;
        while (true) {
            const digit: u8 = @intCast(n % base);
            digits[length] = if (digit < 10) '0' + digit else 'A' + digit - 10;
            length += 1;
            n /= base;
            if (n == 0) break;
        }
        const min_digits: usize = if (byte_value) (if (base == 16) 2 else if (base == 8) 3 else 0) else if (base == 16) 4 else if (base == 8) 6 else 0;
        while (length < min_digits) : (length += 1) digits[length] = '0';
        if (negative) self.write("-");
        while (length > 0) {
            length -= 1;
            self.write(digits[length .. length + 1]);
        }
    }

    fn handleStringToken(self: *State, input: []const u8, cursor: *usize, immediate: bool) RuntimeError!void {
        var literal: [127]u8 = undefined;
        var length: usize = 0;
        var inline_prefix: []const u8 = &.{};
        if (immediate and cursor.* > 0) {
            const token_start = cursor.*;
            var start = token_start;
            while (start > 0 and !isSeparator(input[start - 1])) start -= 1;
            const token = input[start..token_start];
            if (std.mem.startsWith(u8, token, ".\"")) inline_prefix = token[2..];
        }
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
            if (inline_prefix.len == 0 and cursor.* < input.len and isSeparator(input[cursor.*])) cursor.* += 1;
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
            self.memory[address] = @intCast(bytes.len);
            @memcpy(self.memory[@as(usize, address) + 1 .. @as(usize, address) + 1 + bytes.len], bytes);
            _ = try self.emit(.{ .kind = if (immediate) .print_string else .string_literal, .value = address });
        } else self.write(bytes);
    }

    fn asciiEqlIgnoreCase(a: []const u8, b: []const u8) bool {
        if (a.len != b.len) return false;
        for (a, b) |left, right| {
            const upper_left = if (left >= 'a' and left <= 'z') left - 'a' + 'A' else left;
            const upper_right = if (right >= 'a' and right <= 'z') right - 'a' + 'A' else right;
            if (upper_left != upper_right) return false;
        }
        return true;
    }

    fn isSeparator(byte: u8) bool {
        return byte == ' ' or byte == '\r' or byte == '\n';
    }

    fn nextToken(input: []const u8, cursor: *usize) ?[]const u8 {
        while (cursor.* < input.len and isSeparator(input[cursor.*])) cursor.* += 1;
        if (cursor.* == input.len) return null;
        const start = cursor.*;
        while (cursor.* < input.len and !isSeparator(input[cursor.*])) cursor.* += 1;
        return input[start..cursor.*];
    }
};
