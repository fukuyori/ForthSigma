//! The FORTH/Sigma core: the State, the outer interpreter, the inner interpreter, and the dispatch of
//! built-in words. The other parts live in src/core, one subject per file.

const std = @import("std");
const control_flow = @import("core/control_flow.zig");
const decompiler = @import("core/decompiler.zig");
const definers = @import("core/definers.zig");
const defs = @import("core/defs.zig");
const dictionary_image = @import("core/dictionary_image.zig");
const dynamic_strings = @import("core/dynamic_strings.zig");
const error_reporting = @import("core/error_reporting.zig");
const heap_memory = @import("core/heap_memory.zig");
const host_interface = @import("core/host_interface.zig");
const integer_math = @import("core/integer_math.zig");
const local_variables = @import("core/local_variables.zig");
const memory_map = @import("core/memory_map.zig");
const number_io = @import("core/number_io.zig");
const source_input = @import("core/source_input.zig");
const text_input = @import("core/text_input.zig");
const wordlists = @import("core/wordlists.zig");
const words_arithmetic = @import("core/words_arithmetic.zig");
const words_compiling = @import("core/words_compiling.zig");
const words_dictionary = @import("core/words_dictionary.zig");
const words_files = @import("core/words_files.zig");
const words_float = @import("core/words_float.zig");
const words_help = @import("core/words_help.zig");
const words_input = @import("core/words_input.zig");
const words_memory = @import("core/words_memory.zig");
const words_output = @import("core/words_output.zig");
const words_pictured = @import("core/words_pictured.zig");
const words_stack = @import("core/words_stack.zig");
const words_strings = @import("core/words_strings.zig");
const words_system = @import("core/words_system.zig");
const Builtin = defs.Builtin;
pub const Cell = memory_map.Cell;
const Control = defs.Control;
pub const Double = memory_map.Double;
const ErrorLocation = defs.ErrorLocation;
pub const FileAccess = host_interface.FileAccess;
pub const FileOps = host_interface.FileOps;
pub const FileResult = host_interface.FileResult;
pub const Float = memory_map.Float;
const IncludeFrame = defs.IncludeFrame;
const InputPlace = defs.InputPlace;
const InterpretLoop = defs.InterpretLoop;
pub const LineResult = host_interface.LineResult;
const Local = defs.Local;
const LocalKind = defs.LocalKind;
const Loop = defs.Loop;
const Op = defs.Op;
const Pending = defs.Pending;
pub const RuntimeError = defs.RuntimeError;
const SourceKind = defs.SourceKind;
const StringWord = defs.StringWord;
pub const UCell = memory_map.UCell;
pub const UDouble = memory_map.UDouble;
const Word = defs.Word;
const WordKind = defs.WordKind;
pub const LocalTime = host_interface.LocalTime;
pub const Writer = host_interface.Writer;
const base_address = memory_map.base_address;
const bitsFloat = defs.bitsFloat;
const cell_size = memory_map.cell_size;
const cellsDouble = defs.cellsDouble;
const current_wordlist_address = memory_map.current_wordlist_address;
pub const data_limit = memory_map.data_limit;
pub const data_start = memory_map.data_start;
const dot_precision = memory_map.dot_precision;
const doubleCells = defs.doubleCells;
pub const errnoIor = memory_map.errnoIor;
pub const errno_bad_file = memory_map.errno_bad_file;
pub const errno_invalid = memory_map.errno_invalid;
pub const fam_read_only = memory_map.fam_read_only;
pub const fam_read_write = memory_map.fam_read_write;
pub const fam_write_only = memory_map.fam_write_only;
pub const errno_no_memory = memory_map.errno_no_memory;
const evaluate_source_name = memory_map.evaluate_source_name;
const evaluate_source_name_address = memory_map.evaluate_source_name_address;
pub const first_file_id = memory_map.first_file_id;
const floatBits = defs.floatBits;
const forth_wordlist = memory_map.forth_wordlist;
const heap_base = memory_map.heap_base;
const heap_top_address = memory_map.heap_top_address;
const hold_top = memory_map.hold_top;
const in_address = memory_map.in_address;
pub const ior_errno_base = memory_map.ior_errno_base;
const locals_base = memory_map.locals_base;
const locals_end = memory_map.locals_end;
const max_code = memory_map.max_code;
const max_controls = memory_map.max_controls;
const max_float_stack = memory_map.max_float_stack;
const max_hold_nesting = memory_map.max_hold_nesting;
const max_include_depth = memory_map.max_include_depth;
const max_locals = memory_map.max_locals;
const max_name = memory_map.max_name;
const max_search_order = memory_map.max_search_order;
const max_stack = memory_map.max_stack;
const max_words = memory_map.max_words;
const max_uses = memory_map.max_uses;
pub const memory_size = memory_map.memory_size;
const names_capacity = memory_map.names_capacity;
pub const pad_address = memory_map.pad_address;
const precision_address = memory_map.precision_address;
const root_word_names = memory_map.root_word_names;
const root_wordlist = memory_map.root_wordlist;
const state_address = memory_map.state_address;
pub const stderr_fileid = memory_map.stderr_fileid;
pub const stdin_fileid = memory_map.stdin_fileid;
pub const stdout_fileid = memory_map.stdout_fileid;
const terminal_source_name = memory_map.terminal_source_name;
const terminal_source_name_address = memory_map.terminal_source_name_address;
const tib_address = memory_map.tib_address;
pub const tib_size = memory_map.tib_size;
const wordlist_count_address = memory_map.wordlist_count_address;

pub const State = struct {
    writer: Writer,
    memory: [memory_size]u8 = @splat(0),
    words: [max_words]Word = undefined,
    word_count: u16 = 0,
    builtin_count: u16 = 0,
    code: [max_code]Op = undefined,
    code_count: u16 = 0,
    /// The names of the dictionary entries, one after another.
    names: [names_capacity]u8 = undefined,
    names_used: u32 = 0,
    data_stack: [max_stack]Cell = @splat(0),
    data_depth: usize = 0,
    return_stack: [max_stack]Cell = @splat(0),
    return_depth: usize = 0,
    float_stack: [max_float_stack]Float = @splat(0),
    float_depth: usize = 0,
    control_stack: [max_controls]Control = undefined,
    control_depth: usize = 0,
    /// The loops of [DO], [FOR], and [BEGIN] that are running.
    interpret_loops: [16]InterpretLoop = undefined,
    interpret_loop_depth: usize = 0,
    /// The number of the current terminal line or EVALUATE string, so that SAVE-INPUT
    /// and the interpreted loops can tell it from a later line in the same buffer.
    input_line_serial: Cell = 0,
    input_lines_read: Cell = 0,
    /// Where the last token read starts in the source line, for WHERE.
    token_start: usize = 0,
    uses: [max_uses]defs.WordUse = undefined,
    use_count: usize = 0,
    loop_stack: [max_stack]Loop = undefined,
    loop_depth: usize = 0,
    data_here: Cell = data_start,
    compiling: bool = false,
    defining: bool = false,
    current_word: u16 = 0,
    current_data_start: Cell = 0,
    pending: Pending = .none,
    pending_constant: Cell = 0,
    pending_float: Float = 0,
    pending_double: Double = 0,
    pending_array_size: Cell = 0,
    hold_ptr: Cell = hold_top,
    hold_end: Cell = hold_top,
    hold_stack: [max_hold_nesting]Cell = undefined,
    hold_depth: usize = 0,
    string_buffer_index: usize = 0,
    source_line: []const u8 = &.{},
    /// Where the current input came from; only terminal input reads further lines.
    source_kind: SourceKind = .terminal,
    include_stack: [max_include_depth]IncludeFrame = undefined,
    include_depth: usize = 0,
    error_location: ?ErrorLocation = null,
    name_buffer_index: usize = 0,
    last_created_word: ?u16 = null,
    halted: bool = false,
    call_depth: usize = 0,
    last_unknown_word: ?[]const u8 = null,
    throw_code: Cell = 0,
    /// The counted string of the ABORT" that threw -2, for its message.
    abort_message: ?Cell = null,
    capture_target: ?Cell = null,
    /// The status of the last SYSTEM, for $?.
    system_status: Cell = 0,
    capture_failed: bool = false,
    tmp_string_index: usize = 0,
    locals: [max_locals]Local = undefined,
    local_count: usize = 0,
    /// Frame bytes used so far by the definition being compiled.
    locals_frame_size: u16 = 0,
    locals_top: Cell = locals_base,

    /// Sets up a State where it lies. The State is a few megabytes, so it is built in
    /// place rather than returned by value, which could need copies on the stack.
    pub fn init(self: *State, writer: Writer) void {
        self.* = .{ .writer = writer };
        self.writeCell(base_address, 10) catch unreachable;
        self.writeCell(precision_address, dot_precision) catch unreachable;
        self.writeCell(heap_top_address, heap_base) catch unreachable;
        self.storeSourceName(terminal_source_name_address, terminal_source_name);
        self.storeSourceName(evaluate_source_name_address, evaluate_source_name);
        // gforth starts with the search order Forth Forth Root and defines into Forth.
        self.writeCell(wordlist_count_address, root_wordlist) catch unreachable;
        self.writeCell(current_wordlist_address, forth_wordlist) catch unreachable;
        self.setSearchOrder(&.{ forth_wordlist, forth_wordlist, root_wordlist });
        self.installBuiltins();
    }

    /// Writes interpreter output, or appends it to the string being built by $TMP.
    pub fn write(self: *State, bytes: []const u8) void {
        if (self.capture_target) |target| {
            self.appendString(target, bytes) catch {
                self.capture_failed = true;
            };
            return;
        }
        self.writer.write(bytes);
    }

    pub const imageCapacity = dictionary_image.imageCapacity;
    pub const encodeImage = dictionary_image.encodeImage;
    pub const restoreImage = dictionary_image.restoreImage;
    pub const appendImage = dictionary_image.appendImage;

    pub const report = error_reporting.report;
    pub const writeThrowMessage = error_reporting.writeThrowMessage;
    pub const throwCode = error_reporting.throwCode;
    pub const throwIor = error_reporting.throwIor;
    pub const throwCodeOf = error_reporting.throwCodeOf;
    pub const restoreCatchFrame = error_reporting.restoreCatchFrame;

    /// >IN: kept in logical memory so that Forth code can read and set it. An offset past
    /// the end of the source counts as the end, and a negative one as the start.
    pub fn sourceCursor(self: *const State) usize {
        const offset = self.readCellConst(in_address);
        return @intCast(std.math.clamp(offset, 0, @as(Cell, @intCast(self.source_line.len))));
    }

    /// Where the current line or EVALUATE string lies in logical memory (0 if it does not).
    pub fn sourceLineAddress(self: *const State) Cell {
        const start = @intFromPtr(&self.memory);
        const address = @intFromPtr(self.source_line.ptr);
        if (self.source_line.len == 0 or address < start or address >= start + memory_size) return 0;
        return @intCast(address - start);
    }

    pub fn setSourceCursor(self: *State, offset: usize) void {
        self.writeCell(in_address, @intCast(offset)) catch unreachable;
    }

    /// Interprets one line of terminal input. The line is copied to the terminal input
    /// buffer so PARSE and WORD can return addresses in logical memory.
    pub fn interpretLine(self: *State, input: []const u8) RuntimeError!void {
        if (input.len > tib_size) return error.StringTooLong;
        const start: usize = @intCast(tib_address);
        std.mem.copyForwards(u8, self.memory[start .. start + input.len], input);
        return self.interpretSource(self.memory[start .. start + input.len], .terminal);
    }

    /// Interprets `input`, which lies in logical memory.
    pub fn interpretSource(self: *State, input: []const u8, source_kind: SourceKind) RuntimeError!void {
        const previous_line = self.source_line;
        const previous_cursor = self.sourceCursor();
        const previous_kind = self.source_kind;
        const previous_serial = self.input_line_serial;
        self.source_line = input;
        self.setSourceCursor(0);
        self.source_kind = source_kind;
        self.numberInputLine();
        // A nested file or EVALUATE string runs inside the caller's work, so it must not
        // drop the word that a pending DOES> will attach to.
        if (source_kind == .terminal) self.last_created_word = null;
        const pending_before = self.pending;
        defer {
            self.source_line = previous_line;
            self.setSourceCursor(previous_cursor);
            self.source_kind = previous_kind;
            self.input_line_serial = previous_serial;
        }
        self.last_unknown_word = null;
        var line = input;
        var cursor: usize = 0;
        while (true) {
            const token = nextToken(line, &cursor) orelse break;
            self.source_line = line;
            self.token_start = @intFromPtr(token.ptr) - @intFromPtr(line.ptr);
            self.setSourceCursor(cursor);
            if (self.pending != .none) {
                try self.finishPending(token);
                continue;
            }
            if (std.mem.eql(u8, token, "(")) {
                const close = std.mem.indexOfScalarPos(u8, line, cursor, ')') orelse return error.CommentUnclosed;
                cursor = close + 1;
                continue;
            }
            if (std.mem.eql(u8, token, "\\")) break;
            if (std.mem.eql(u8, token, "\"")) {
                try self.handleStringToken(token, line, &cursor, false);
                self.setSourceCursor(cursor);
                continue;
            }
            const string_word: ?StringWord = if (asciiEqlIgnoreCase(token, "S\"")) .s_quote else if (asciiEqlIgnoreCase(token, "S\\\"")) .s_escape_quote else if (std.mem.eql(u8, token, ".\\\"")) .print_escape else if (std.mem.eql(u8, token, ".(")) .print_paren else if (asciiEqlIgnoreCase(token, "C\"")) .c_quote else if (asciiEqlIgnoreCase(token, "ABORT\"")) .abort_quote else null;
            if (string_word) |kind| {
                try self.handleParsedString(kind, line, &cursor);
                self.setSourceCursor(cursor);
                continue;
            }
            if (std.mem.startsWith(u8, token, ".\"")) {
                try self.handleStringToken(token, line, &cursor, true);
                self.setSourceCursor(cursor);
                continue;
            }
            try self.handleToken(token);
            // gforth reports a negative >IN as a parsed string overflow; going back to
            // the start instead would run the line again and again.
            if (self.readCellConst(in_address) < 0) return error.StringTooLong;
            line = self.source_line;
            cursor = self.sourceCursor();
            if (self.halted) break;
        }
        // An EVALUATE string cannot read past its end, so a parsing word such as
        // VARIABLE or : left waiting for its name must not take the caller's next word.
        if (source_kind == .evaluate and pending_before == .none and self.pending != .none) {
            self.pending = .none;
            return error.InvalidDefinition;
        }
    }

    fn installBuiltins(self: *State) void {
        const definitions = [_]struct { []const u8, Builtin }{
            .{ "DROP", .drop },              .{ "DUP", .dup },                .{ "SWAP", .swap },             .{ "OVER", .over },                .{ "ROT", .rot },
            .{ "-ROT", .minus_rot },         .{ "NIP", .nip },                .{ "TUCK", .tuck },             .{ "PICK", .pick },                .{ "ROLL", .roll },
            .{ "2DUP", .two_dup },           .{ "2DROP", .two_drop },         .{ "2SWAP", .two_swap },        .{ "2OVER", .two_over },           .{ "DEPTH", .depth },
            .{ ">R", .to_r },                .{ "R>", .from_r },              .{ "R@", .r_fetch },            .{ "+", .add },                    .{ "-", .sub },
            .{ "*", .mul },                  .{ "/", .div },                  .{ "MOD", .mod },               .{ "/MOD", .div_mod },             .{ "MINUS", .negate },
            .{ "NEGATE", .negate },          .{ "ABS", .abs },                .{ "1+", .one_plus },           .{ "1-", .one_minus },             .{ "2*", .two_star },
            .{ "2/", .two_slash },           .{ "MAX", .max },                .{ "MIN", .min },               .{ "=", .equal },                  .{ "<>", .not_equal },
            .{ "<", .less },                 .{ ">", .greater },              .{ "<=", .less_equal },         .{ ">=", .greater_equal },         .{ "NOT", .logical_not },
            .{ "0=", .zero_equal },          .{ "0<", .zero_less },           .{ "0>", .zero_greater },       .{ "0<>", .zero_not_equal },       .{ "AND", .bit_and },
            .{ "OR", .bit_or },              .{ "XOR", .bit_xor },            .{ "COM", .bit_complement },    .{ "INVERT", .bit_complement },    .{ "NAND", .bit_nand },
            .{ "NOR", .bit_nor },            .{ "SWAB", .swap_bytes },        .{ "LSHIFT", .lshift },         .{ "RSHIFT", .rshift },            .{ "TRUE", .true_value },
            .{ "FALSE", .false_value },      .{ "BL", .blank },               .{ "CELL", .cell },             .{ "CELLS", .cells },              .{ "CELL+", .cell_plus },
            .{ "ALIGNED", .aligned },        .{ "@", .fetch },                .{ "!", .store },               .{ ",", .comma },                  .{ "C,", .c_comma },
            .{ "EXECUTE", .execute },        .{ "C@", .cfetch },              .{ "C!", .cstore },             .{ "+!", .add_store },             .{ "1+!", .inc_store },
            .{ "1-!", .dec_store },          .{ "OSET", .zero_store },        .{ "ON", .on },                 .{ "OFF", .off },                  .{ "?", .question },
            .{ "A@", .array_fetch },         .{ "A!", .array_store },         .{ "ERASE", .erase },           .{ "FILL", .fill },                .{ "MOVE", .move },
            .{ "CMOVE", .cmove },            .{ ".", .dot },                  .{ "U.", .u_dot },              .{ "C.", .c_dot },                 .{ ".S", .dot_s },
            .{ "ECHO", .echo },              .{ "EMIT", .echo },              .{ "CR", .cr },                 .{ "SPACE", .space },              .{ "SPCES", .spaces },
            .{ "SPACES", .spaces },          .{ "TYPE", .type },              .{ "HEX", .hex },               .{ "DEC", .dec },                  .{ "DECIMAL", .dec },
            .{ "OCT", .oct },                .{ "BASE", .base },              .{ "HERE", .here },             .{ "ALLOT", .allot },              .{ "I", .index },
            .{ "J", .index_2 },              .{ "K", .index_3 },              .{ "LEAVE", .leave },           .{ "UNLOOP", .unloop },            .{ "WORDS", .words },
            .{ "BYE", .bye },                .{ "INPUT", .input },            .{ "<BUILDS", .builds },        .{ "CREATE", .builds },            .{ "IMMEDIATE", .immediate },
            .{ "LOAD", .load },              .{ "SAVE", .save },              .{ "SAVESYS", .savesys },       .{ "IF", .compile_if },            .{ "ELSE", .compile_else },
            .{ "THEN", .compile_then },      .{ "BEGIN", .compile_begin },    .{ "END", .compile_end },       .{ "UNTIL", .compile_end },        .{ "AGAIN", .compile_again },
            .{ "WHILE", .compile_while },    .{ "REPEAT", .compile_repeat },  .{ "DO", .compile_do },         .{ "?DO", .compile_q_do },         .{ "LOOP", .compile_loop },
            .{ "+LOOP", .compile_plus_loop }, .{ "DOES>", .compile_does },    .{ "CASE", .compile_case },     .{ "OF", .compile_of },            .{ "ENDOF", .compile_endof },
            .{ "ENDCASE", .compile_endcase }, .{ "EXIT", .compile_exit },     .{ "RECURSE", .compile_recurse }, .{ "FDROP", .f_drop },           .{ "FDUP", .f_dup },
            .{ "FSWAP", .f_swap },           .{ "FOVER", .f_over },           .{ "FROT", .f_rot },            .{ "F-ROT", .f_minus_rot },        .{ "FNIP", .f_nip },
            .{ "FTUCK", .f_tuck },           .{ "FPICK", .f_pick },           .{ "FDEPTH", .f_depth },        .{ "F.S", .f_dot_s },              .{ "F+", .f_add },
            .{ "F-", .f_sub },               .{ "F*", .f_mul },               .{ "F/", .f_div },              .{ "FNEGATE", .f_negate },         .{ "FMINUS", .f_negate },
            .{ "FABS", .f_abs },             .{ "FMAX", .f_max },             .{ "FMIN", .f_min },            .{ "FSQRT", .f_sqrt },             .{ "FEXP", .f_exp },
            .{ "FLN", .f_ln },               .{ "FSIN", .f_sin },             .{ "FCOS", .f_cos },            .{ "FTAN", .f_tan },               .{ "F=", .f_equal },
            .{ "F<>", .f_not_equal },        .{ "F<", .f_less },              .{ "F>", .f_greater },          .{ "F<=", .f_less_equal },         .{ "F>=", .f_greater_equal },
            .{ "F0=", .f_zero_equal },       .{ "F0<>", .f_zero_not_equal },  .{ "F0<", .f_zero_less },       .{ "F0>", .f_zero_greater },       .{ "F0<=", .f_zero_less_equal },
            .{ "F0>=", .f_zero_greater_equal }, .{ "F@", .f_fetch },          .{ "F!", .f_store },            .{ "F,", .f_comma },               .{ "FA@", .f_array_fetch },
            .{ "FA!", .f_array_store },      .{ "F+!", .f_add_store },        .{ "F?", .f_question },         .{ "FLOATS", .floats },            .{ "FLOAT+", .float_plus },
            .{ "S>F", .s_to_f },             .{ "F>S", .f_to_s },             .{ "F.", .f_dot },              .{ "FINPUT", .f_input },           .{ "S>D", .s_to_d },
            .{ "D>S", .d_to_s },             .{ "D+", .d_add },               .{ "D-", .d_sub },              .{ "DNEGATE", .d_negate },         .{ "DABS", .d_abs },
            .{ "D0=", .d_zero_equal },       .{ "D0<", .d_zero_less },        .{ "D=", .d_equal },            .{ "D<", .d_less },                .{ "D.", .d_dot },
            .{ "2@", .two_fetch },           .{ "2!", .two_store },           .{ "D>F", .d_to_f },            .{ "F>D", .f_to_d },               .{ "COUNT", .count },
            .{ "PAD", .pad },                .{ "ACCEPT", .accept },          .{ "EVALUATE", .evaluate },     .{ "KEY", .key },                  .{ "KEY?", .key_question },
            .{ "<#", .hold_start },          .{ "<<#", .hold_nest },          .{ "#", .hold_digit },          .{ "#S", .hold_digits },           .{ "#>", .hold_finish },
            .{ "#>>", .hold_release },       .{ "HOLD", .hold },              .{ "HOLDS", .holds },           .{ "SIGN", .sign },                .{ ">NUMBER", .to_number },
            .{ "S>NUMBER?", .string_to_number }, .{ ">FLOAT", .to_float },   .{ "WITHIN", .within },         .{ "2>R", .two_to_r },             .{ "2R>", .two_r_from },
            .{ "ENDIF", .compile_then },     .{ "PLACE", .place },            .{ "ABORT", .abort },           .{ "MS", .ms },                    .{ "UTIME", .utime },
            .{ "PAGE", .page },              .{ "GETENV", .getenv },          .{ "SYSTEM", .system },         .{ "STATE", .state },              .{ "THROW", .throw },
            .{ "R/O", .read_only },          .{ "W/O", .write_only },         .{ "R/W", .read_write },        .{ "STDIN", .stdin },              .{ "STDOUT", .stdout },
            .{ "STDERR", .stderr },          .{ "OPEN-FILE", .open_file },    .{ "CREATE-FILE", .create_file }, .{ "CLOSE-FILE", .close_file },  .{ "READ-LINE", .read_line },
            .{ "WRITE-LINE", .write_line },  .{ "WRITE-FILE", .write_file },  .{ "FILE-SIZE", .file_size },   .{ "REPOSITION-FILE", .reposition_file }, .{ "ALLOCATE", .allocate },
            .{ "FREE", .free },              .{ "RESIZE", .resize },          .{ "$!", .string_store },       .{ "$@", .string_fetch },          .{ "$@LEN", .string_fetch_len },
            .{ "$!LEN", .string_store_len }, .{ "$+!", .string_append },      .{ "C$+!", .char_append },      .{ "$.", .string_dot },            .{ "$DEL", .string_delete },
            .{ "$INS", .string_insert },     .{ "$OVER", .string_over },      .{ "$FREE", .string_free },     .{ "$INIT", .string_init },        .{ "$SPLIT", .string_split },
            .{ "$ITER", .string_iter },      .{ "$TMP", .string_tmp },        .{ "$[]", .string_array },      .{ "$[]!", .string_array_store },  .{ "$[]@", .string_array_fetch },
            .{ "$[]#", .string_array_count }, .{ "$[].", .string_array_dot }, .{ "$[]MAP", .string_array_map }, .{ "$[]FREE", .string_array_free }, .{ "$[]SLURP", .string_array_slurp },
            .{ "$[]SLURP-FILE", .string_array_slurp_file }, .{ "CATCH", .catch_word },      .{ "WORD", .word_parse },     .{ "FIND", .find_word },
            .{ "PARSE", .parse },            .{ "FIND-NAME", .find_name },    .{ "NAME>INT", .name_to_int },  .{ "NAME>STRING", .name_to_string }, .{ "SEE", .see },
            .{ "INCLUDE", .include },        .{ "INCLUDED", .included },      .{ "REQUIRE", .require },       .{ "NEEDS", .require },            .{ "REQUIRED", .required },
            .{ "INCLUDED?", .included_query }, .{ "SOURCEFILENAME", .source_file_name }, .{ "SOURCELINE#", .source_line_number }, .{ "MARKER", .marker }, .{ "LOCATE", .locate }, .{ "WHERE", .where },
            .{ "ONLY", .only },              .{ "ALSO", .also },              .{ "PREVIOUS", .previous },     .{ "FORTH", .forth },              .{ "DEFINITIONS", .definitions },
            .{ "ORDER", .order },            .{ "GET-ORDER", .get_order },    .{ "SET-ORDER", .set_order },   .{ ">ORDER", .to_order },          .{ "GET-CURRENT", .get_current },
            .{ "SET-CURRENT", .set_current }, .{ "VOCABULARY", .vocabulary }, .{ "WORDLIST", .wordlist },    .{ "FORTH-WORDLIST", .forth_wordlist_word }, .{ "SEARCH-WORDLIST", .search_wordlist },
            .{ "[IF]", .bracket_if },        .{ "[ELSE]", .bracket_else },    .{ "[THEN]", .bracket_then },   .{ "[DEFINED]", .bracket_defined }, .{ "[UNDEFINED]", .bracket_undefined },
            .{ "F.RDP", .f_dot_rdp },        .{ "F>STR-RDP", .f_to_str_rdp }, .{ "F>BUF-RDP", .f_to_buf_rdp },
            .{ ":", .define_colon },         .{ ";", .end_definition },       .{ "VARIABLE", .define_variable }, .{ "VAR", .define_variable },  .{ "FVARIABLE", .define_fvariable },
            .{ "CONSTANT", .define_constant }, .{ "CONST", .define_constant }, .{ "VALUE", .define_value },  .{ "2VARIABLE", .define_two_variable }, .{ "2CONSTANT", .define_two_constant },
            .{ "FCONSTANT", .define_fconstant }, .{ "ARRAY", .define_array }, .{ "FARRAY", .define_array }, .{ "PI", .pi },
            .{ "'", .tick },                 .{ ">BODY", .to_body },          .{ "LITERAL", .literal },       .{ "FLITERAL", .fliteral },
            .{ "HELP", .help },              .{ "LICENSE", .license },
            .{ "COMPARE", .compare },        .{ "SEARCH", .search },          .{ "/STRING", .slash_string },  .{ "-TRAILING", .minus_trailing },
            .{ "CHAR+", .char_plus },        .{ "CHARS", .chars },            .{ "BOUNDS", .bounds },         .{ "BLANK", .blank_fill },         .{ "CMOVE>", .cmove_up },
            .{ "SCAN", .scan },              .{ "SKIP", .skip },              .{ "STR=", .str_equal },        .{ "STRING-PREFIX?", .string_prefix_query }, .{ "+PLACE", .plus_place },
            .{ "SLITERAL", .sliteral },      .{ "PARSE-NAME", .parse_name },  .{ "SLURP-FILE", .slurp_file }, .{ "$SLURP-FILE", .string_slurp_file },
            .{ "$SLURP", .string_slurp },     .{ "$+SLURP", .string_plus_slurp }, .{ "$+SLURP-FILE", .string_plus_slurp_file }, .{ "$SLURP-LINE", .string_slurp_line },
            .{ "$+!LEN", .string_plus_store_len }, .{ "$[]+!", .string_array_append }, .{ "$+[]!", .string_append_array }, .{ "$EXEC", .string_exec },
            .{ "$?", .system_status },       .{ "$OFF", .string_free },       .{ "$VARIABLE", .define_variable }, .{ "$[]VARIABLE", .define_variable },
            .{ "?DUP", .question_dup },      .{ "2R@", .two_r_fetch },        .{ "U<", .u_less },             .{ "U>", .u_greater },             .{ "ALIGN", .align_here },
            .{ ".R", .dot_r },               .{ "U.R", .u_dot_r },            .{ "UNUSED", .unused },         .{ "*/", .star_slash },            .{ "*/MOD", .star_slash_mod },
            .{ "M*", .m_star },              .{ "UM*", .um_star },            .{ "UM/MOD", .um_slash_mod },   .{ "FM/MOD", .fm_slash_mod },      .{ "SM/REM", .sm_slash_rem },
            .{ "READ-FILE", .read_file },
            .{ "FLOOR", .f_floor },          .{ "FTRUNC", .f_trunc },         .{ "FROUND", .f_round },         .{ "FE.", .f_e_dot },            .{ "FS.", .f_s_dot },
            .{ "PRECISION", .precision },    .{ "SET-PRECISION", .set_precision }, .{ "F~", .f_proximate },         .{ "SF@", .sf_fetch },           .{ "SF!", .sf_store },
            .{ "DF@", .df_fetch },           .{ "DF!", .df_store },           .{ "SFLOATS", .sfloats },        .{ "DFLOATS", .dfloats },        .{ "SFLOAT+", .sfloat_plus },
            .{ "DFLOAT+", .dfloat_plus },    .{ "FALIGN", .f_align },         .{ "FALIGNED", .f_aligned },     .{ "SFALIGN", .sf_align },       .{ "SFALIGNED", .sf_aligned },
            .{ "DFALIGN", .df_align },       .{ "DFALIGNED", .df_aligned },   .{ "FSINCOS", .f_sincos },       .{ "FASIN", .f_asin },           .{ "FACOS", .f_acos },
            .{ "FATAN", .f_atan },           .{ "FATAN2", .f_atan2 },         .{ "FSINH", .f_sinh },           .{ "FCOSH", .f_cosh },           .{ "FTANH", .f_tanh },
            .{ "FASINH", .f_asinh },         .{ "FACOSH", .f_acosh },         .{ "FATANH", .f_atanh },         .{ "FEXPM1", .f_expm1 },         .{ "FLNP1", .f_lnp1 },
            .{ "FLOG", .f_log },             .{ "FALOG", .f_alog },           .{ "F**", .f_power },            .{ "FVALUE", .define_fvalue },         .{ "2VALUE", .define_two_value },     .{ "BUFFER:", .define_buffer },       .{ "2LITERAL", .two_literal },
            .{ "D.R", .d_dot_r },                  .{ "D2*", .d_two_star },              .{ "D2/", .d_two_slash },             .{ "DMAX", .d_max },                  .{ "DMIN", .d_min },
            .{ ">IN", .to_in },                    .{ "SOURCE", .source },               .{ "SOURCE-ID", .source_id },         .{ "REFILL", .refill },
            .{ "AHEAD", .compile_ahead },          .{ "N>R", .n_to_r },                  .{ "NR>", .n_r_from },                .{ "AT-XY", .at_xy },                 .{ "TIME&DATE", .time_and_date },
            .{ "SYNONYM", .synonym },              .{ "TRAVERSE-WORDLIST", .traverse_wordlist }, .{ "NAME>INTERPRET", .name_to_int }, .{ "CS-PICK", .cs_pick },     .{ "CS-ROLL", .cs_roll },
            .{ "EKEY", .key },                     .{ "EKEY?", .key_question },          .{ "EKEY>CHAR", .ekey_to_char },      .{ "ENVIRONMENT?", .environment_query }, .{ "QUIT", .quit },
            .{ "BIN", .bin },                      .{ "FILE-POSITION", .file_position }, .{ "RESIZE-FILE", .resize_file },     .{ "FLUSH-FILE", .flush_file },       .{ "DELETE-FILE", .delete_file },
            .{ "RENAME-FILE", .rename_file },      .{ "FILE-STATUS", .file_status },     .{ "INCLUDE-FILE", .include_file },
            .{ "SAVE-INPUT", .save_input },        .{ "RESTORE-INPUT", .restore_input },
            .{ "M*/", .m_star_slash },              .{ "REPRESENT", .represent },
            .{ "[IFDEF]", .bracket_ifdef },        .{ "[IFUNDEF]", .bracket_ifundef },   .{ "[ENDIF]", .bracket_then },        .{ "[DO]", .bracket_do },             .{ "[?DO]", .bracket_q_do },
            .{ "[LOOP]", .bracket_loop },          .{ "[+LOOP]", .bracket_plus_loop },   .{ "[I]", .bracket_i },               .{ "[BEGIN]", .bracket_begin },       .{ "[UNTIL]", .bracket_until },
            .{ "[AGAIN]", .bracket_again },        .{ "[WHILE]", .bracket_while },       .{ "[REPEAT]", .bracket_repeat },     .{ "[FOR]", .bracket_for },           .{ "[NEXT]", .bracket_next },
            .{ "M+", .m_plus },                    .{ "DU<", .du_less },                 .{ "2ROT", .two_rot },                .{ "DUMP", .dump },
        };
        for (definitions) |definition| self.addBuiltin(definition[0], definition[1]) catch unreachable;
        // The Root list repeats the words needed to rebuild the search order after ONLY.
        self.writeCell(current_wordlist_address, root_wordlist) catch unreachable;
        for (root_word_names) |name| {
            const builtin = for (definitions) |definition| {
                if (std.mem.eql(u8, definition[0], name)) break definition[1];
            } else unreachable;
            self.addBuiltin(name, builtin) catch unreachable;
        }
        self.writeCell(current_wordlist_address, forth_wordlist) catch unreachable;
        self.builtin_count = self.word_count;
    }

    fn isImmediateBuiltin(builtin: Builtin) bool {
        return switch (builtin) {
            .compile_if, .compile_else, .compile_ahead, .compile_then, .compile_begin, .compile_end, .compile_again, .compile_while, .compile_repeat, .compile_do, .compile_q_do, .compile_loop, .compile_plus_loop, .compile_does, .compile_case, .compile_of, .compile_endof, .compile_endcase, .compile_exit, .compile_recurse, .leave, .bracket_if, .bracket_else, .bracket_then, .bracket_defined, .bracket_undefined, .bracket_ifdef, .bracket_ifundef, .bracket_do, .bracket_q_do, .bracket_loop, .bracket_plus_loop, .bracket_i, .bracket_begin, .bracket_until, .bracket_again, .bracket_while, .bracket_repeat, .bracket_for, .bracket_next, .end_definition, .literal, .fliteral, .sliteral, .two_literal => true,
            else => false,
        };
    }

    fn addBuiltin(self: *State, name: []const u8, builtin: Builtin) RuntimeError!void {
        const id = try self.appendWord(name, .builtin, builtin, 0);
        self.words[id].immediate = isImmediateBuiltin(builtin);
    }

    pub fn appendWord(self: *State, name: []const u8, kind: WordKind, builtin: Builtin, value: Cell) RuntimeError!u16 {
        if (self.word_count == max_words) return error.DictionaryFull;
        if (name.len == 0 or name.len > max_name) return error.NameTooLong;
        if (kind != .builtin and self.lookup(name) != null) {
            self.write("WARNING: SAME NAME WORD EXISTS\n");
        }
        return self.appendEntry(name, kind, builtin, value);
    }

    /// Appends a colon definition without a name (`:NONAME`); lookup never finds it.
    fn appendAnonymousColon(self: *State) RuntimeError!u16 {
        if (self.word_count == max_words) return error.DictionaryFull;
        return self.appendEntry("", .colon, .drop, 0);
    }

    fn appendEntry(self: *State, name: []const u8, kind: WordKind, builtin: Builtin, value: Cell) RuntimeError!u16 {
        if (name.len > names_capacity - self.names_used) return error.DictionaryFull;
        const id = self.word_count;
        var word = Word{ .kind = kind, .builtin = builtin, .value = value, .name_start = self.names_used, .name_len = @intCast(name.len), .data_here_before = self.data_here, .wordlist = @intCast(self.currentWordlist()) };
        if (self.currentFileFrame()) |frame| {
            word.source_file = frame.file_index + 1;
            word.source_line = frame.line;
            word.source_end_line = frame.line;
        }
        @memcpy(self.names[self.names_used..][0..name.len], name);
        self.names_used += @intCast(name.len);
        if (kind == .colon) word.code_start = self.code_count;
        self.words[id] = word;
        self.word_count += 1;
        return id;
    }

    pub const lookup = wordlists.lookup;
    pub const lookupIn = wordlists.lookupIn;
    pub const wordlistCount = wordlists.wordlistCount;
    pub const validWordlist = wordlists.validWordlist;
    pub const currentWordlist = wordlists.currentWordlist;
    pub const searchOrderDepth = wordlists.searchOrderDepth;
    pub const searchOrderEntry = wordlists.searchOrderEntry;
    pub const setSearchOrder = wordlists.setSearchOrder;
    pub const searchOrder = wordlists.searchOrder;
    pub const writeWordlistName = wordlists.writeWordlistName;
    pub const snapshotMarker = wordlists.snapshotMarker;
    pub const restoreMarker = wordlists.restoreMarker;

    pub fn lookupOrFail(self: *State, name: []const u8) RuntimeError!u16 {
        const id = self.lookup(name) orelse {
            self.last_unknown_word = name;
            return error.UnknownWord;
        };
        self.recordUse(id);
        return id;
    }

    /// Whether the name is found, recording the use: [DEFINED] and [IFDEF].
    pub fn lookupRecorded(self: *State, name: []const u8) bool {
        const id = self.lookup(name) orelse return false;
        self.recordUse(id);
        return true;
    }

    /// Gives the line that has just become the input a number of its own.
    pub fn numberInputLine(self: *State) void {
        self.input_lines_read +%= 1;
        self.input_line_serial = self.input_lines_read;
    }

    /// Records that a word was found by name while reading a file, at the last token
    /// read, as gforth does for WHERE.
    pub fn recordUse(self: *State, id: u16) void {
        const frame = self.currentFileFrame() orelse return;
        if (self.use_count == max_uses) return;
        const column = @min(self.token_start + 1, std.math.maxInt(u16));
        self.uses[self.use_count] = .{ .word = id, .file_index = frame.file_index, .column = @intCast(column), .line = frame.line };
        self.use_count += 1;
    }

    /// Drops the recorded uses of word `id` and every later word.
    pub fn dropUsesFrom(self: *State, id: u16) void {
        var kept: usize = 0;
        for (self.uses[0..self.use_count]) |use| {
            if (use.word >= id) continue;
            self.uses[kept] = use;
            kept += 1;
        }
        self.use_count = kept;
    }

    pub const appendDataWord = definers.appendDataWord;
    pub const finishPending = definers.finishPending;
    pub const endDefinition = definers.endDefinition;
    pub const bodyAddress = definers.bodyAddress;
    pub const isDefiningBuiltin = definers.isDefiningBuiltin;
    pub const runDefiningWord = definers.runDefiningWord;
    pub const definingPending = definers.definingPending;
    pub const startInterpretPending = definers.startInterpretPending;

    /// Removes word `id` and every later word, reclaiming their code and data areas.
    pub fn forgetFrom(self: *State, id: u16) void {
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
        self.names_used = self.words[id].name_start;
        self.word_count = id;
        self.dropUsesFrom(id);
    }

    pub fn pushInterpretLoop(self: *State, loop: InterpretLoop) RuntimeError!void {
        if (self.interpret_loop_depth == self.interpret_loops.len) return error.ControlStackOverflow;
        self.interpret_loops[self.interpret_loop_depth] = loop;
        self.interpret_loop_depth += 1;
    }

    pub fn topInterpretLoop(self: *State, kind: @FieldType(InterpretLoop, "kind")) RuntimeError!*InterpretLoop {
        if (self.interpret_loop_depth == 0) return error.ControlMismatch;
        const loop = &self.interpret_loops[self.interpret_loop_depth - 1];
        if (loop.kind != kind) return error.ControlMismatch;
        return loop;
    }

    /// Goes back to the start of the innermost interpreted loop, or ends it.
    pub fn repeatInterpretLoop(self: *State, again: bool) RuntimeError!void {
        const loop = self.interpret_loops[self.interpret_loop_depth - 1];
        if (!again) {
            self.interpret_loop_depth -= 1;
            return;
        }
        // A loop on the terminal cannot go back to an earlier line.
        if (!try self.restoreInputPlace(loop.place)) return error.ControlMismatch;
    }

    /// The word a SYNONYM stands for (itself for any other word).
    pub fn synonymTarget(self: *const State, id: u16) u16 {
        var target = id;
        while (self.words[target].kind == .synonym) target = @intCast(self.words[target].value);
        return target;
    }

    /// The name of a dictionary entry, kept in `names`.
    pub fn wordName(self: *const State, word: Word) []const u8 {
        return self.names[word.name_start..][0..word.name_len];
    }

    fn handleToken(self: *State, token: []const u8) RuntimeError!void {
        // Local variables shadow every dictionary word inside their definition.
        if (self.compiling) {
            if (self.findLocal(token)) |local| return self.compileLocalReference(local);
        }
        const found = self.lookup(token);
        if (found) |id| {
            self.recordUse(id);
            if (id >= self.builtin_count) return self.handleWord(id);
            // Defining words are dictionary words, found through the search order. One
            // compiled into a definition reads its name when that runs; interpreted, it
            // takes the next name, which may be on a later line.
            if (isDefiningBuiltin(self.words[id].builtin)) {
                if (self.compiling) return self.handleWord(id);
                self.pending = try self.definingPending(self.words[id].builtin);
                return;
            }
            // ' in a definition reads the name when the definition runs, as in standard
            // Forth; ['] takes it at compile time.
            if (self.words[id].builtin == .tick) {
                if (self.compiling) return self.handleWord(id);
                self.pending = .tick_name;
                return;
            }
        }
        if (std.mem.eql(u8, token, "{") or std.mem.eql(u8, token, "{:")) {
            return self.compileLocals(if (token.len == 1) "}" else ":}");
        }
        if (asciiEqlIgnoreCase(token, "LOCALS|")) {
            return self.compileAnsLocals();
        }
        if (asciiEqlIgnoreCase(token, ":NONAME")) {
            if (self.defining) return error.InvalidDefinition;
            // Check the stack first so a failure cannot leave an unterminated definition behind.
            if (self.data_depth == max_stack) return error.StackOverflow;
            const id = try self.appendAnonymousColon();
            self.beginDefinition(id);
            self.push(id) catch unreachable;
            return;
        }
        if (std.mem.eql(u8, token, "[")) {
            // As in gforth, [ while interpreting leaves the interpreter as it is.
            if (self.compiling) self.setCompiling(false);
            return;
        }
        if (std.mem.eql(u8, token, "]")) {
            if (!self.defining or self.compiling) return error.CompileOnly;
            self.setCompiling(true);
            return;
        }
        if (std.mem.eql(u8, token, "[']")) {
            self.pending = .tick_name;
            return;
        }
        if (asciiEqlIgnoreCase(token, "CHAR") or asciiEqlIgnoreCase(token, "[CHAR]")) {
            self.pending = .char_name;
            return;
        }
        if (asciiEqlIgnoreCase(token, "POSTPONE")) {
            if (!self.compiling) return error.CompileOnly;
            self.pending = .postpone_name;
            return;
        }
        if (asciiEqlIgnoreCase(token, "TO")) {
            self.pending = .to_name;
            return;
        }
        if (asciiEqlIgnoreCase(token, "FORGET")) {
            return self.startInterpretPending(.forget_name);
        }
        if (found) |id| return self.handleWord(id);
        if (try self.parseNumber(token)) |number| {
            const cells = doubleCells(number.value);
            if (self.compiling) {
                _ = try self.emit(.{ .kind = .literal, .value = cells.low });
                if (number.double) _ = try self.emit(.{ .kind = .literal, .value = cells.high });
            } else {
                try self.push(cells.low);
                if (number.double) try self.push(cells.high);
            }
            return;
        }
        const float_literal = if (self.currentBase() == 10) parseFloat(token, true) else null;
        if (float_literal) |number| {
            if (self.compiling) {
                _ = try self.emit(.{ .kind = .float_literal, .value = floatBits(number) });
            } else {
                try self.fpush(number);
            }
            return;
        }
        self.last_unknown_word = token;
        return error.UnknownWord;
    }

    pub fn beginDefinition(self: *State, id: u16) void {
        self.local_count = 0;
        self.locals_frame_size = 0;
        self.current_word = id;
        self.current_data_start = self.words[id].data_here_before;
        self.setCompiling(true);
        self.defining = true;
    }

    /// Changes the compiler state and mirrors it in the STATE cell, so a saved
    /// `STATE` address always reads the current value.
    pub fn setCompiling(self: *State, compiling: bool) void {
        self.compiling = compiling;
        self.writeCell(state_address, truth(compiling)) catch unreachable;
    }

    pub const findLocal = local_variables.findLocal;
    pub const localOperand = local_variables.localOperand;
    pub const compileLocalReference = local_variables.compileLocalReference;
    pub const addLocal = local_variables.addLocal;
    pub const compileLocalInitialization = local_variables.compileLocalInitialization;
    pub const compileLocals = local_variables.compileLocals;
    pub const compileAnsLocals = local_variables.compileAnsLocals;
    pub const storeLocal = local_variables.storeLocal;
    pub const fetchLocal = local_variables.fetchLocal;

    fn handleWord(self: *State, id: u16) RuntimeError!void {
        if (self.compiling and !self.words[id].immediate) {
            _ = try self.emit(.{ .kind = .call, .value = id });
        } else {
            try self.executeWord(id);
        }
    }

    pub const requireCompiling = control_flow.requireCompiling;
    pub const pushControl = control_flow.pushControl;
    pub const popControl = control_flow.popControl;
    pub const topControl = control_flow.topControl;
    pub const compileIf = control_flow.compileIf;
    pub const compileElse = control_flow.compileElse;
    pub const compileAhead = control_flow.compileAhead;
    pub const skipInterpretLoop = control_flow.skipInterpretLoop;
    pub const compileThen = control_flow.compileThen;
    pub const compileBegin = control_flow.compileBegin;
    pub const compileEnd = control_flow.compileEnd;
    pub const compileWhile = control_flow.compileWhile;
    pub const compileRepeat = control_flow.compileRepeat;
    pub const compileDo = control_flow.compileDo;
    pub const compileLoop = control_flow.compileLoop;
    pub const compileLeave = control_flow.compileLeave;
    pub const compileDoes = control_flow.compileDoes;
    pub const compileCase = control_flow.compileCase;
    pub const compileOf = control_flow.compileOf;
    pub const compileEndof = control_flow.compileEndof;
    pub const compileEndcase = control_flow.compileEndcase;
    pub const skipConditional = control_flow.skipConditional;

    pub const storeSourceName = source_input.storeSourceName;
    pub const currentFileFrame = source_input.currentFileFrame;
    pub const sourceFileCount = source_input.sourceFileCount;
    pub const setSourceFileCount = source_input.setSourceFileCount;
    pub const sourceFileEntry = source_input.sourceFileEntry;
    pub const sourceFileName = source_input.sourceFileName;
    pub const sourceFileLoadedFlag = source_input.sourceFileLoadedFlag;
    pub const sourceFileLoaded = source_input.sourceFileLoaded;
    pub const setSourceFileLoaded = source_input.setSourceFileLoaded;
    pub const findSourceEntry = source_input.findSourceEntry;
    pub const findSourceFile = source_input.findSourceFile;
    pub const sourceFileEntryIndex = source_input.sourceFileEntryIndex;
    pub const recordSourceFile = source_input.recordSourceFile;
    pub const loadedSourceFiles = source_input.loadedSourceFiles;
    pub const restoreLoadedSourceFiles = source_input.restoreLoadedSourceFiles;
    pub const readIncludeLine = source_input.readIncludeLine;
    pub const includeOpenFile = source_input.includeOpenFile;
    pub const saveInputPlace = source_input.saveInputPlace;
    pub const restoreInputPlace = source_input.restoreInputPlace;
    pub const includeFile = source_input.includeFile;
    pub const interpretIncludedFile = source_input.interpretIncludedFile;
    pub const requireFile = source_input.requireFile;
    pub const locateWord = source_input.locateWord;
    pub const listUses = source_input.listUses;
    pub const sourceAddress = source_input.sourceAddress;

    pub fn emit(self: *State, op: Op) RuntimeError!u16 {
        if (self.code_count == max_code) return error.CodeFull;
        const at = self.code_count;
        self.code[at] = op;
        self.code_count += 1;
        return at;
    }

    pub fn patch(self: *State, at: u16, target: u16) void {
        self.code[at].value = target;
    }

    pub fn executeWord(self: *State, id: u16) RuntimeError!void {
        const word = self.words[id];
        switch (word.kind) {
            .synonym => try self.executeWord(try self.wordId(word.value)),
            .builtin => try self.executeBuiltin(word.builtin),
            .constant, .array => try self.push(word.value),
            .value => try self.push(try self.readCell(word.value)),
            .fconstant => try self.fpush(bitsFloat(word.value)),
            .fvalue => try self.fpush(try self.readFloat(word.value)),
            .two_constant, .two_value => try self.pushDouble(try self.readDouble(word.value)),
            .variable, .created => {
                try self.push(word.value);
                if (word.has_does) {
                    if (self.call_depth == max_stack) return error.ReturnStackOverflow;
                    self.call_depth += 1;
                    defer self.call_depth -= 1;
                    try self.executeOperations(word.does_code_start, word.does_code_end, null);
                }
            },
            .colon => try self.executeColon(id, word),
            // A MARKER removes itself and everything after it, and forgets the source
            // files included since, so REQUIRE loads them again.
            .marker => {
                // Read the snapshot first: forgetting releases its data area.
                const address = word.value;
                self.forgetFrom(id);
                try self.restoreMarker(address);
            },
            // A VOCABULARY replaces the first-searched word list with its own.
            .vocabulary => {
                var order: [max_search_order]Cell = undefined;
                const current = self.searchOrder(&order);
                if (current.len == 0) self.setSearchOrder(&.{word.value}) else {
                    current[0] = word.value;
                    self.setSearchOrder(current);
                }
            },
        }
    }

    fn executeColon(self: *State, id: u16, word: Word) RuntimeError!void {
        if (self.call_depth == max_stack) return error.ReturnStackOverflow;
        self.call_depth += 1;
        defer self.call_depth -= 1;
        try self.executeOperations(word.code_start, word.code_end, id);
    }

    pub fn wordId(self: *State, value: Cell) RuntimeError!u16 {
        if (value < 0 or value >= self.word_count) return error.InvalidExecutionToken;
        return @intCast(value);
    }

    fn executeOperations(self: *State, start_pc: u16, end_pc: u16, defining_word: ?u16) RuntimeError!void {
        var pc = start_pc;
        // The local-variable frame of this invocation, released on every exit path.
        var locals_frame: ?Cell = null;
        defer if (locals_frame) |base| {
            self.locals_top = base;
        };
        while (pc < end_pc and !self.halted) {
            const op = self.code[pc];
            pc += 1;
            switch (op.kind) {
                .call => try self.executeWord(try self.wordId(op.value)),
                .compile_call => {
                    try self.requireCompiling();
                    _ = try self.emit(.{ .kind = .call, .value = op.value });
                },
                .builtin => try self.executeBuiltin(@enumFromInt(op.value)),
                .literal, .execution_token => try self.push(op.value),
                .float_literal => try self.fpush(bitsFloat(op.value)),
                .store_value => {
                    const word = self.words[try self.wordId(op.value)];
                    switch (word.kind) {
                        .fvalue => try self.writeFloat(word.value, try self.fpop()),
                        .two_value => try self.writeDouble(word.value, try self.popDouble()),
                        else => try self.writeCell(word.value, try self.pop()),
                    }
                },
                .branch => pc = @intCast(op.value),
                .branch_zero => {
                    if (try self.pop() == 0) pc = @intCast(op.value);
                },
                .do_loop, .q_do_loop => {
                    const start = try self.pop();
                    const limit = try self.pop();
                    const exit_pc: u16 = @intCast(op.value);
                    if (op.kind == .q_do_loop and start == limit) {
                        pc = exit_pc;
                        continue;
                    }
                    if (self.loop_depth == max_stack) return error.StackOverflow;
                    self.loop_stack[self.loop_depth] = .{ .index = start, .limit = limit, .exit_pc = exit_pc, .exit_after_first = start == limit };
                    self.loop_depth += 1;
                },
                .loop, .plus_loop => {
                    if (self.loop_depth == 0) return error.LoopMismatch;
                    const step: Cell = if (op.kind == .plus_loop) try self.pop() else 1;
                    const frame = &self.loop_stack[self.loop_depth - 1];
                    const crossed = integer_math.loopCrossed(frame.index, frame.limit, step);
                    frame.index +%= step;
                    const again = if (frame.exit_after_first) false else if (op.kind == .loop) frame.index != frame.limit else !crossed;
                    if (again) {
                        pc = @intCast(op.value);
                    } else {
                        self.loop_depth -= 1;
                    }
                },
                .leave => {
                    if (self.loop_depth == 0) return error.LoopMismatch;
                    self.loop_depth -= 1;
                    pc = self.loop_stack[self.loop_depth].exit_pc;
                },
                .print_string => {
                    const address = try self.memoryAddress(op.value, 1);
                    const length = self.memory[address];
                    const start = try self.memoryAddress(op.value + 1, length);
                    self.write(self.memory[start .. start + length]);
                },
                .counted_string => try self.push(op.value),
                .abort_string => {
                    if (try self.pop() != 0) {
                        self.abort_message = op.value;
                        return self.throwCode(-2);
                    }
                },
                .string_literal => {
                    const address = try self.memoryAddress(op.value, 1);
                    try self.push(op.value + 1);
                    try self.push(self.memory[address]);
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
                .local_frame => if (locals_frame == null) {
                    const size = self.words[try self.wordId(op.value)].locals_size;
                    if (locals_end - self.locals_top < size) return error.ReturnStackOverflow;
                    const start: usize = @intCast(self.locals_top);
                    @memset(self.memory[start .. start + size], 0);
                    locals_frame = self.locals_top;
                    self.locals_top += size;
                },
                .local_store, .local_fetch, .local_address, .local_execute => {
                    const base = locals_frame orelse return error.InvalidAddress;
                    const address = base + (op.value & 0xffff_ffff);
                    const kind: LocalKind = @enumFromInt(op.value >> 32);
                    switch (op.kind) {
                        .local_store => try self.storeLocal(address, kind),
                        .local_fetch => try self.fetchLocal(address, kind),
                        .local_address => try self.push(address),
                        .local_execute => try self.executeWord(try self.wordId(try self.readCell(address))),
                        else => unreachable,
                    }
                },
            }
        }
    }

    /// Runs a built-in word: each `words_*` file in src/core lists the words it executes,
    /// and every word must be in exactly one list.
    pub fn executeBuiltin(self: *State, builtin: Builtin) RuntimeError!void {
        switch (builtin) {
            inline else => |word| try word_modules[word_owner[@intFromEnum(word)]].execute(self, word),
        }
    }

    const word_modules = .{ words_stack, words_arithmetic, words_memory, words_output, words_input, words_compiling, words_float, words_pictured, words_dictionary, words_system, words_files, words_strings, words_help };

    /// For each built-in word, the index in `word_modules` of the file that executes it.
    const word_owner = blk: {
        @setEvalBranchQuota(100_000);
        const count = @typeInfo(Builtin).@"enum".fields.len;
        var owner = [_]?usize{null} ** count;
        for (word_modules, 0..) |module, index| {
            for (module.words) |word| {
                if (owner[@intFromEnum(word)] != null) @compileError(@tagName(word) ++ " is in two words_* lists");
                owner[@intFromEnum(word)] = index;
            }
        }
        var result: [count]usize = undefined;
        for (owner, 0..) |index, slot| {
            result[slot] = index orelse @compileError(@tagName(@as(Builtin, @enumFromInt(slot))) ++ " is in no words_* list");
        }
        break :blk result;
    };
    /// Pops a byte count; negative counts are treated as 0 and huge ones as memory-sized.
    pub fn popLength(self: *State) RuntimeError!usize {
        const count = try self.pop();
        return if (count < 0) 0 else @intCast(@min(count, memory_size));
    }

    pub fn writeMemory(self: *State, address: Cell, length: usize) void {
        const start: usize = @intCast(address);
        self.write(self.memory[start .. start + length]);
    }

    pub fn copyMemory(self: *State, destination: Cell, source: Cell, length: usize) void {
        const to: usize = @intCast(destination);
        const from: usize = @intCast(source);
        if (to <= from) {
            std.mem.copyForwards(u8, self.memory[to .. to + length], self.memory[from .. from + length]);
        } else std.mem.copyBackwards(u8, self.memory[to .. to + length], self.memory[from .. from + length]);
    }

    // ALLOCATE heap: blocks laid out from `heap_base` to the top stored at
    // `heap_top_address`, each preceded by a size cell and a used cell.

    pub const heapTop = heap_memory.heapTop;
    pub const blockSize = heap_memory.blockSize;
    pub const blockUsed = heap_memory.blockUsed;
    pub const setBlock = heap_memory.setBlock;
    pub const splitBlock = heap_memory.splitBlock;
    pub const heapNeed = heap_memory.heapNeed;
    pub const heapAllocate = heap_memory.heapAllocate;
    pub const findBlock = heap_memory.findBlock;
    pub const coalesceHeap = heap_memory.coalesceHeap;
    pub const heapFree = heap_memory.heapFree;
    pub const heapResize = heap_memory.heapResize;

    // Dynamic strings, as in gforth: a string variable holds 0 or the address of a heap
    // buffer that starts with the length cell followed by the characters.

    pub const StringRef = dynamic_strings.StringRef;
    pub const fetchString = dynamic_strings.fetchString;
    pub const setStringLength = dynamic_strings.setStringLength;
    pub const freeString = dynamic_strings.freeString;
    pub const insertString = dynamic_strings.insertString;
    pub const appendString = dynamic_strings.appendString;
    pub const stringArrayCount = dynamic_strings.stringArrayCount;
    pub const stringArrayElement = dynamic_strings.stringArrayElement;
    pub const slurpLines = dynamic_strings.slurpLines;
    pub const slurpFile = dynamic_strings.slurpFile;
    pub const slurpLine = dynamic_strings.slurpLine;
    pub const slurpRest = dynamic_strings.slurpRest;
    pub const executeStringInit = dynamic_strings.executeStringInit;

    pub const SeeRole = decompiler.SeeRole;
    pub const SeeOutput = decompiler.SeeOutput;
    pub const seeWord = decompiler.seeWord;
    pub const seeBody = decompiler.seeBody;
    pub const seeName = decompiler.seeName;
    pub const seeOperation = decompiler.seeOperation;

    pub const remainingSource = text_input.remainingSource;
    pub const sourceInMemory = text_input.sourceInMemory;
    pub const isDelimiter = text_input.isDelimiter;
    pub const parseWordText = text_input.parseWordText;
    pub const validNameToken = text_input.validNameToken;
    pub const readInputToken = text_input.readInputToken;
    pub const handleStringToken = text_input.handleStringToken;
    pub const handleParsedString = text_input.handleParsedString;
    pub const compileCountedString = text_input.compileCountedString;
    pub const parseDelimited = text_input.parseDelimited;
    pub const asciiEqlIgnoreCase = text_input.asciiEqlIgnoreCase;
    pub const isSeparator = text_input.isSeparator;
    pub const nextToken = text_input.nextToken;
    pub const nextSourceToken = text_input.nextSourceToken;

    pub fn fileOps(self: *State) RuntimeError!*const FileOps {
        return self.writer.file_ops orelse error.HostUnavailable;
    }

    pub const resetHold = number_io.resetHold;
    pub const holdBytes = number_io.holdBytes;
    pub const holdDigit = number_io.holdDigit;
    pub const validBase = number_io.validBase;
    pub const digitValue = number_io.digitValue;
    pub const currentBase = number_io.currentBase;
    pub const parseNumber = number_io.parseNumber;
    pub const parseFloat = number_io.parseFloat;
    pub const writeDepth = number_io.writeDepth;
    pub const writeNumber = number_io.writeNumber;
    pub const numberWidth = number_io.numberWidth;
    pub const writeZeros = number_io.writeZeros;
    pub const writeFloatFixed = number_io.writeFloatFixed;
    pub const writeFloatScientific = number_io.writeFloatScientific;
    pub const floatPrecision = number_io.floatPrecision;
    pub const writeFloatExponent = number_io.writeFloatExponent;
    pub const writeNonFinite = number_io.writeNonFinite;
    pub const writeNumberDecimal = number_io.writeNumberDecimal;

    pub const Division = integer_math.Division;
    pub const binary = integer_math.binary;
    pub const flooredDivision = integer_math.flooredDivision;
    pub const truth = integer_math.truth;
    pub const floatToCell = integer_math.floatToCell;
    pub const floatToDouble = integer_math.floatToDouble;

    /// Pops a double-cell number; the high cell is on top of the stack.
    pub fn popDouble(self: *State) RuntimeError!Double {
        try self.requireDepth(2);
        const high = try self.pop();
        const low = try self.pop();
        return cellsDouble(low, high);
    }

    pub fn pushDouble(self: *State, value: Double) RuntimeError!void {
        const cells = doubleCells(value);
        try self.push(cells.low);
        try self.push(cells.high);
    }

    /// 2@ / 2! layout: the high cell at `address`, the low cell in the next cell.
    pub fn readDouble(self: *State, address: Cell) RuntimeError!Double {
        const high = try self.readCell(address);
        return cellsDouble(try self.readCell(address +% cell_size), high);
    }

    pub fn writeDouble(self: *State, address: Cell, value: Double) RuntimeError!void {
        _ = try self.memoryAddress(address, 2 * cell_size);
        const cells = doubleCells(value);
        try self.writeCell(address, cells.high);
        try self.writeCell(address + cell_size, cells.low);
    }

    pub fn requireDepth(self: *State, depth: usize) RuntimeError!void {
        if (self.data_depth < depth) return error.StackUnderflow;
    }

    pub fn peek(self: *State, depth: usize) RuntimeError!Cell {
        if (depth >= self.data_depth) return error.StackUnderflow;
        return self.data_stack[self.data_depth - depth - 1];
    }

    pub fn pop(self: *State) RuntimeError!Cell {
        if (self.data_depth == 0) return error.StackUnderflow;
        self.data_depth -= 1;
        return self.data_stack[self.data_depth];
    }

    pub fn push(self: *State, value: Cell) RuntimeError!void {
        if (self.data_depth == max_stack) return error.StackOverflow;
        self.data_stack[self.data_depth] = value;
        self.data_depth += 1;
    }

    pub fn requireFloatDepth(self: *State, depth: usize) RuntimeError!void {
        if (self.float_depth < depth) return error.FloatStackUnderflow;
    }

    pub fn fpeek(self: *State, depth: usize) RuntimeError!Float {
        if (depth >= self.float_depth) return error.FloatStackUnderflow;
        return self.float_stack[self.float_depth - depth - 1];
    }

    pub fn fpop(self: *State) RuntimeError!Float {
        if (self.float_depth == 0) return error.FloatStackUnderflow;
        self.float_depth -= 1;
        return self.float_stack[self.float_depth];
    }

    pub fn fpush(self: *State, value: Float) RuntimeError!void {
        if (self.float_depth == max_float_stack) return error.FloatStackOverflow;
        self.float_stack[self.float_depth] = value;
        self.float_depth += 1;
    }

    pub fn loopFrame(self: *State, nesting: usize) RuntimeError!Loop {
        if (self.loop_depth < nesting) return error.LoopMismatch;
        return self.loop_stack[self.loop_depth - nesting];
    }

    /// Validates that `length` bytes starting at `address` lie inside logical memory.
    pub fn memoryAddress(self: *State, address: Cell, length: usize) RuntimeError!usize {
        _ = self;
        if (address < 0 or address > memory_size) return error.InvalidAddress;
        const start: usize = @intCast(address);
        if (length > memory_size - start) return error.InvalidAddress;
        return start;
    }

    /// Pops ( addr u ) and returns the addressed bytes. A negative u counts as an empty
    /// string; a u past the end of memory is an error, not cut short.
    pub fn memoryRange(self: *State) RuntimeError![]u8 {
        const count = try self.pop();
        const address = try self.pop();
        const length = std.math.cast(usize, @max(count, 0)) orelse return error.InvalidAddress;
        const start = try self.memoryAddress(address, length);
        return self.memory[start .. start + length];
    }

    /// Pops ( index base ) and returns the address of the indexed cell.
    pub fn arrayAddress(self: *State) RuntimeError!Cell {
        const base = try self.pop();
        const index = try self.pop();
        return base +% (index *% cell_size);
    }

    /// Reads a cell at a fixed system address of another machine (always in memory).
    pub fn readCellConst(self: *const State, address: Cell) Cell {
        const start: usize = @intCast(address);
        return std.mem.readInt(Cell, self.memory[start..][0..cell_size], .little);
    }

    pub fn readCell(self: *State, address: Cell) RuntimeError!Cell {
        const start = try self.memoryAddress(address, cell_size);
        return std.mem.readInt(Cell, self.memory[start..][0..cell_size], .little);
    }

    pub fn writeCell(self: *State, address: Cell, value: Cell) RuntimeError!void {
        const start = try self.memoryAddress(address, cell_size);
        std.mem.writeInt(Cell, self.memory[start..][0..cell_size], value, .little);
    }

    pub fn readFloat(self: *State, address: Cell) RuntimeError!Float {
        return bitsFloat(try self.readCell(address));
    }

    pub fn writeFloat(self: *State, address: Cell, value: Float) RuntimeError!void {
        try self.writeCell(address, floatBits(value));
    }

    pub fn reserveData(self: *State, amount: Cell) RuntimeError!void {
        const next, const overflow = @addWithOverflow(self.data_here, amount);
        if (overflow != 0 or next < data_start or next > data_limit) return error.MemoryExhausted;
        self.data_here = next;
    }

};
