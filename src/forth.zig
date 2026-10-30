const std = @import("std");
const builtin_info = @import("builtin");
const control_flow = @import("core/control_flow.zig");
const decompiler = @import("core/decompiler.zig");
const definers = @import("core/definers.zig");
const defs = @import("core/defs.zig");
const dictionary_image = @import("core/dictionary_image.zig");
const dynamic_strings = @import("core/dynamic_strings.zig");
const error_reporting = @import("core/error_reporting.zig");
const float_format = @import("core/float_format.zig");
const float_math = @import("core/float_math.zig");
const heap_memory = @import("core/heap_memory.zig");
const host_interface = @import("core/host_interface.zig");
const integer_math = @import("core/integer_math.zig");
const local_variables = @import("core/local_variables.zig");
const memory_map = @import("core/memory_map.zig");
const number_io = @import("core/number_io.zig");
const source_input = @import("core/source_input.zig");
const text_input = @import("core/text_input.zig");
const wordlists = @import("core/wordlists.zig");
const Builtin = defs.Builtin;
const CatchFrame = defs.CatchFrame;
pub const Cell = memory_map.Cell;
const Control = defs.Control;
pub const Double = memory_map.Double;
const ErrorLocation = defs.ErrorLocation;
pub const FileAccess = host_interface.FileAccess;
pub const FileOps = host_interface.FileOps;
pub const FileResult = host_interface.FileResult;
pub const Float = memory_map.Float;
const IncludeFrame = defs.IncludeFrame;
pub const LineResult = host_interface.LineResult;
const Local = defs.Local;
const LocalKind = defs.LocalKind;
const Loop = defs.Loop;
const Op = defs.Op;
const ParsedNumber = defs.ParsedNumber;
const Pending = defs.Pending;
pub const RuntimeError = defs.RuntimeError;
const SourceKind = defs.SourceKind;
const StringWord = defs.StringWord;
pub const UCell = memory_map.UCell;
pub const UDouble = memory_map.UDouble;
const Word = defs.Word;
const WordKind = defs.WordKind;
pub const Writer = host_interface.Writer;
const base_address = memory_map.base_address;
const bitsFloat = defs.bitsFloat;
const cell_size = memory_map.cell_size;
const cellsDouble = defs.cellsDouble;
const cr_cos = float_math.cr_cos;
const cr_exp = float_math.cr_exp;
const cr_log = float_math.cr_log;
const cr_sin = float_math.cr_sin;
const cr_tan = float_math.cr_tan;
const current_wordlist_address = memory_map.current_wordlist_address;
pub const data_limit = memory_map.data_limit;
pub const data_start = memory_map.data_start;
const doubleCells = defs.doubleCells;
const environment_buffer_base = memory_map.environment_buffer_base;
const environment_buffer_size = memory_map.environment_buffer_size;
pub const errnoIor = memory_map.errnoIor;
pub const errno_bad_file = memory_map.errno_bad_file;
pub const errno_invalid = memory_map.errno_invalid;
pub const errno_no_memory = memory_map.errno_no_memory;
const error_codes = defs.error_codes;
const evaluate_source_name = memory_map.evaluate_source_name;
const evaluate_source_name_address = memory_map.evaluate_source_name_address;
const fam_read_only = memory_map.fam_read_only;
const fam_read_write = memory_map.fam_read_write;
const fam_write_only = memory_map.fam_write_only;
pub const first_file_id = memory_map.first_file_id;
const floatBits = defs.floatBits;
const float_size = memory_map.float_size;
const formatRdp = float_format.formatRdp;
const forth_wordlist = memory_map.forth_wordlist;
const heap_base = memory_map.heap_base;
const heap_top_address = memory_map.heap_top_address;
const hold_bottom = memory_map.hold_bottom;
const hold_top = memory_map.hold_top;
pub const ior_errno_base = memory_map.ior_errno_base;
const line_terminator = memory_map.line_terminator;
const locals_base = memory_map.locals_base;
const locals_end = memory_map.locals_end;
const marker_snapshot_size = memory_map.marker_snapshot_size;
const max_code = memory_map.max_code;
const max_controls = memory_map.max_controls;
const max_dot_s_items = memory_map.max_dot_s_items;
const max_float_stack = memory_map.max_float_stack;
const max_gforth_string = memory_map.max_gforth_string;
const max_hold_nesting = memory_map.max_hold_nesting;
const max_host_name = memory_map.max_host_name;
const max_include_depth = memory_map.max_include_depth;
const max_locals = memory_map.max_locals;
const max_name = memory_map.max_name;
const max_rdp_width = float_format.max_rdp_width;
const max_search_order = memory_map.max_search_order;
const max_stack = memory_map.max_stack;
const max_wordlists = memory_map.max_wordlists;
const max_words = memory_map.max_words;
pub const memory_size = memory_map.memory_size;
const name_buffer_base = memory_map.name_buffer_base;
const name_buffer_count = memory_map.name_buffer_count;
pub const pad_address = memory_map.pad_address;
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
const tmp_string_base = memory_map.tmp_string_base;
const tmp_string_count = memory_map.tmp_string_count;
const trig = float_math.trig;
const true_flag = memory_map.true_flag;
const word_buffer_address = memory_map.word_buffer_address;
const wordlist_count_address = memory_map.wordlist_count_address;

pub const State = struct {
    writer: Writer,
    memory: [memory_size]u8 = @splat(0),
    words: [max_words]Word = undefined,
    word_count: u16 = 0,
    builtin_count: u16 = 0,
    code: [max_code]Op = undefined,
    code_count: u16 = 0,
    data_stack: [max_stack]Cell = @splat(0),
    data_depth: usize = 0,
    return_stack: [max_stack]Cell = @splat(0),
    return_depth: usize = 0,
    float_stack: [max_float_stack]Float = @splat(0),
    float_depth: usize = 0,
    control_stack: [max_controls]Control = undefined,
    control_depth: usize = 0,
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
    source_cursor: usize = 0,
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
    capture_target: ?Cell = null,
    capture_failed: bool = false,
    tmp_string_index: usize = 0,
    locals: [max_locals]Local = undefined,
    local_count: usize = 0,
    /// Frame bytes used so far by the definition being compiled.
    locals_frame_size: u16 = 0,
    locals_top: Cell = locals_base,

    pub fn init(writer: Writer) State {
        var state = State{ .writer = writer };
        state.writeCell(base_address, 10) catch unreachable;
        state.writeCell(heap_top_address, heap_base) catch unreachable;
        state.storeSourceName(terminal_source_name_address, terminal_source_name);
        state.storeSourceName(evaluate_source_name_address, evaluate_source_name);
        // gforth starts with the search order Forth Forth Root and defines into Forth.
        state.writeCell(wordlist_count_address, root_wordlist) catch unreachable;
        state.writeCell(current_wordlist_address, forth_wordlist) catch unreachable;
        state.setSearchOrder(&.{ forth_wordlist, forth_wordlist, root_wordlist });
        state.installBuiltins();
        return state;
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
        const previous_cursor = self.source_cursor;
        const previous_kind = self.source_kind;
        self.source_line = input;
        self.source_cursor = 0;
        self.source_kind = source_kind;
        // A nested file or EVALUATE string runs inside the caller's work, so it must not
        // drop the word that a pending DOES> will attach to.
        if (source_kind == .terminal) self.last_created_word = null;
        const pending_before = self.pending;
        defer {
            self.source_line = previous_line;
            self.source_cursor = previous_cursor;
            self.source_kind = previous_kind;
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
            if (std.mem.eql(u8, token, "\\")) break;
            if (std.mem.eql(u8, token, "\"")) {
                try self.handleStringToken(token, line, &cursor, false);
                self.source_cursor = cursor;
                continue;
            }
            const string_word: ?StringWord = if (asciiEqlIgnoreCase(token, "S\"")) .s_quote else if (asciiEqlIgnoreCase(token, "S\\\"")) .s_escape_quote else if (std.mem.eql(u8, token, ".\\\"")) .print_escape else if (std.mem.eql(u8, token, ".(")) .print_paren else null;
            if (string_word) |kind| {
                try self.handleParsedString(kind, line, &cursor);
                self.source_cursor = cursor;
                continue;
            }
            if (std.mem.startsWith(u8, token, ".\"")) {
                try self.handleStringToken(token, line, &cursor, true);
                self.source_cursor = cursor;
                continue;
            }
            try self.handleToken(token);
            line = self.source_line;
            cursor = self.source_cursor;
            if (self.halted) break;
        }
        // An EVALUATE string cannot read past its end, so a parsing word such as
        // VARIABLE or : left waiting for its name must not take the caller's next word.
        if (source_kind == .evaluate and pending_before == .none and self.pending != .none) {
            self.pending = .none;
            return error.InvalidDefinition;
        }
    }

    pub fn installBuiltins(self: *State) void {
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
            .{ "INCLUDED?", .included_query }, .{ "SOURCEFILENAME", .source_file_name }, .{ "SOURCELINE#", .source_line_number }, .{ "MARKER", .marker }, .{ "LOCATE", .locate },
            .{ "ONLY", .only },              .{ "ALSO", .also },              .{ "PREVIOUS", .previous },     .{ "FORTH", .forth },              .{ "DEFINITIONS", .definitions },
            .{ "ORDER", .order },            .{ "GET-ORDER", .get_order },    .{ "SET-ORDER", .set_order },   .{ ">ORDER", .to_order },          .{ "GET-CURRENT", .get_current },
            .{ "SET-CURRENT", .set_current }, .{ "VOCABULARY", .vocabulary }, .{ "WORDLIST", .wordlist },    .{ "FORTH-WORDLIST", .forth_wordlist_word }, .{ "SEARCH-WORDLIST", .search_wordlist },
            .{ "[IF]", .bracket_if },        .{ "[ELSE]", .bracket_else },    .{ "[THEN]", .bracket_then },   .{ "[DEFINED]", .bracket_defined }, .{ "[UNDEFINED]", .bracket_undefined },
            .{ "F.RDP", .f_dot_rdp },        .{ "F>STR-RDP", .f_to_str_rdp }, .{ "F>BUF-RDP", .f_to_buf_rdp },
            .{ ":", .define_colon },         .{ ";", .end_definition },       .{ "VARIABLE", .define_variable }, .{ "VAR", .define_variable },  .{ "FVARIABLE", .define_fvariable },
            .{ "CONSTANT", .define_constant }, .{ "CONST", .define_constant }, .{ "VALUE", .define_value },  .{ "2VARIABLE", .define_two_variable }, .{ "2CONSTANT", .define_two_constant },
            .{ "FCONSTANT", .define_fconstant }, .{ "ARRAY", .define_array }, .{ "FARRAY", .define_array }, .{ "PI", .pi },
            .{ "'", .tick },                 .{ ">BODY", .to_body },          .{ "LITERAL", .literal },       .{ "FLITERAL", .fliteral },
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

    pub fn isImmediateBuiltin(builtin: Builtin) bool {
        return switch (builtin) {
            .compile_if, .compile_else, .compile_then, .compile_begin, .compile_end, .compile_again, .compile_while, .compile_repeat, .compile_do, .compile_q_do, .compile_loop, .compile_plus_loop, .compile_does, .compile_case, .compile_of, .compile_endof, .compile_endcase, .compile_exit, .compile_recurse, .leave, .bracket_if, .bracket_else, .bracket_then, .bracket_defined, .bracket_undefined, .end_definition, .literal, .fliteral => true,
            else => false,
        };
    }

    pub fn addBuiltin(self: *State, name: []const u8, builtin: Builtin) RuntimeError!void {
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
    pub fn appendAnonymousColon(self: *State) RuntimeError!u16 {
        if (self.word_count == max_words) return error.DictionaryFull;
        return self.appendEntry("", .colon, .drop, 0);
    }

    pub fn appendEntry(self: *State, name: []const u8, kind: WordKind, builtin: Builtin, value: Cell) RuntimeError!u16 {
        const id = self.word_count;
        var word = Word{ .kind = kind, .builtin = builtin, .value = value, .name_len = @intCast(name.len), .data_here_before = self.data_here, .wordlist = @intCast(self.currentWordlist()) };
        if (self.currentFileFrame()) |frame| {
            word.source_file = frame.file_index + 1;
            word.source_line = frame.line;
            word.source_end_line = frame.line;
        }
        @memcpy(word.name[0..name.len], name);
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
        return self.lookup(name) orelse {
            self.last_unknown_word = name;
            return error.UnknownWord;
        };
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
        self.word_count = id;
    }

    pub fn handleToken(self: *State, token: []const u8) RuntimeError!void {
        // Local variables shadow every dictionary word inside their definition.
        if (self.compiling) {
            if (self.findLocal(token)) |local| return self.compileLocalReference(local);
        }
        const found = self.lookup(token);
        if (found) |id| {
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

    pub fn handleWord(self: *State, id: u16) RuntimeError!void {
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
    pub const includeFile = source_input.includeFile;
    pub const interpretIncludedFile = source_input.interpretIncludedFile;
    pub const requireFile = source_input.requireFile;
    pub const locateWord = source_input.locateWord;
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
            .builtin => try self.executeBuiltin(word.builtin),
            .constant, .array => try self.push(word.value),
            .value => try self.push(try self.readCell(word.value)),
            .fconstant => try self.fpush(bitsFloat(word.value)),
            .two_constant => try self.pushDouble(try self.readDouble(word.value)),
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

    pub fn executeColon(self: *State, id: u16, word: Word) RuntimeError!void {
        if (self.call_depth == max_stack) return error.ReturnStackOverflow;
        self.call_depth += 1;
        defer self.call_depth -= 1;
        try self.executeOperations(word.code_start, word.code_end, id);
    }

    pub fn wordId(self: *State, value: Cell) RuntimeError!u16 {
        if (value < 0 or value >= self.word_count) return error.InvalidExecutionToken;
        return @intCast(value);
    }

    pub fn executeOperations(self: *State, start_pc: u16, end_pc: u16, defining_word: ?u16) RuntimeError!void {
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
                    try self.writeCell(word.value, try self.pop());
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
                    const old = frame.index;
                    const limit = frame.limit;
                    frame.index +%= step;
                    const after = frame.index;
                    const crossed = if (step > 0) old <= limit and after >= limit else if (step < 0) old >= limit and after < limit else old == limit;
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

    pub fn executeBuiltin(self: *State, builtin: Builtin) RuntimeError!void {
        switch (builtin) {
            .drop => _ = try self.pop(),
            .dup => try self.push(try self.peek(0)),
            .swap => {
                try self.requireDepth(2);
                std.mem.swap(Cell, &self.data_stack[self.data_depth - 1], &self.data_stack[self.data_depth - 2]);
            },
            .over => try self.push(try self.peek(1)),
            .rot, .minus_rot => {
                try self.requireDepth(3);
                const items = self.data_stack[self.data_depth - 3 .. self.data_depth];
                if (builtin == .rot) std.mem.rotate(Cell, items, 1) else std.mem.rotate(Cell, items, 2);
            },
            .nip => {
                const top = try self.pop();
                _ = try self.pop();
                try self.push(top);
            },
            .tuck => {
                try self.requireDepth(2);
                const top = try self.peek(0);
                std.mem.swap(Cell, &self.data_stack[self.data_depth - 1], &self.data_stack[self.data_depth - 2]);
                try self.push(top);
            },
            .pick => {
                const depth = try self.pop();
                if (depth < 0) return error.StackUnderflow;
                try self.push(try self.peek(@intCast(depth)));
            },
            .roll => {
                const depth = try self.pop();
                if (depth < 0) return error.StackUnderflow;
                const count: usize = @intCast(depth);
                try self.requireDepth(count + 1);
                std.mem.rotate(Cell, self.data_stack[self.data_depth - count - 1 .. self.data_depth], 1);
            },
            .two_dup => {
                const second = try self.peek(1);
                const top = try self.peek(0);
                try self.push(second);
                try self.push(top);
            },
            .two_drop => {
                try self.requireDepth(2);
                self.data_depth -= 2;
            },
            .two_swap => {
                try self.requireDepth(4);
                std.mem.rotate(Cell, self.data_stack[self.data_depth - 4 .. self.data_depth], 2);
            },
            .two_over => {
                const fourth = try self.peek(3);
                const third = try self.peek(2);
                try self.push(fourth);
                try self.push(third);
            },
            .depth => try self.push(@intCast(self.data_depth)),
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
            .r_fetch => {
                if (self.return_depth == 0) return error.ReturnStackUnderflow;
                try self.push(self.return_stack[self.return_depth - 1]);
            },
            .add, .sub, .mul, .div, .mod, .max, .min, .equal, .not_equal, .less, .greater, .less_equal, .greater_equal, .bit_and, .bit_or, .bit_xor, .bit_nand, .bit_nor, .lshift, .rshift => try self.binary(builtin),
            .div_mod => {
                const divisor = try self.pop();
                const dividend = try self.pop();
                const result = try flooredDivision(dividend, divisor);
                try self.push(result.remainder);
                try self.push(result.quotient);
            },
            .swap_bytes => try self.push(@byteSwap(try self.pop())),
            .negate => try self.push(0 -% try self.pop()),
            .abs => {
                const a = try self.pop();
                try self.push(if (a < 0) 0 -% a else a);
            },
            .one_plus => try self.push((try self.pop()) +% 1),
            .one_minus => try self.push((try self.pop()) -% 1),
            .two_star => try self.push((try self.pop()) *% 2),
            .two_slash => try self.push((try self.pop()) >> 1),
            .logical_not, .zero_equal => try self.push(truth(try self.pop() == 0)),
            .zero_less => try self.push(truth(try self.pop() < 0)),
            .zero_greater => try self.push(truth(try self.pop() > 0)),
            .zero_not_equal => try self.push(truth(try self.pop() != 0)),
            .bit_complement => try self.push(~(try self.pop())),
            .true_value => try self.push(true_flag),
            .false_value => try self.push(0),
            .blank => try self.push(' '),
            .cell => try self.push(cell_size),
            .cells => try self.push((try self.pop()) *% cell_size),
            .cell_plus => try self.push((try self.pop()) +% cell_size),
            .aligned => {
                const address = try self.pop();
                try self.push((address +% (cell_size - 1)) & ~@as(Cell, cell_size - 1));
            },
            .fetch => {
                const address = try self.pop();
                try self.push(try self.readCell(address));
            },
            .store => {
                const address = try self.pop();
                const value = try self.pop();
                try self.writeCell(address, value);
            },
            .cfetch => {
                const address = try self.memoryAddress(try self.pop(), 1);
                try self.push(self.memory[address]);
            },
            .cstore => {
                const address = try self.memoryAddress(try self.pop(), 1);
                const value = try self.pop();
                self.memory[address] = @truncate(@as(UCell, @bitCast(value)));
            },
            .add_store => {
                const address = try self.pop();
                const value = try self.pop();
                try self.writeCell(address, (try self.readCell(address)) +% value);
            },
            .inc_store, .dec_store => {
                const address = try self.pop();
                const old = try self.readCell(address);
                try self.writeCell(address, if (builtin == .inc_store) old +% 1 else old -% 1);
            },
            .zero_store, .off => try self.writeCell(try self.pop(), 0),
            .on => try self.writeCell(try self.pop(), true_flag),
            .question => {
                const address = try self.pop();
                self.writeNumber(try self.readCell(address));
                self.write(" ");
            },
            .array_fetch => {
                const address = try self.arrayAddress();
                try self.push(try self.readCell(address));
            },
            .array_store => {
                const address = try self.arrayAddress();
                const value = try self.pop();
                try self.writeCell(address, value);
            },
            .erase, .fill => {
                const byte: u8 = if (builtin == .fill) @truncate(@as(UCell, @bitCast(try self.pop()))) else 0;
                const bytes = try self.memoryRange();
                @memset(bytes, byte);
            },
            .move, .cmove => {
                const count = try self.pop();
                const destination = try self.pop();
                const source = try self.pop();
                if (count <= 0) return;
                const length: usize = @intCast(count);
                const to = try self.memoryAddress(destination, length);
                const from = try self.memoryAddress(source, length);
                if (builtin == .cmove or to <= from) {
                    for (0..length) |offset| self.memory[to + offset] = self.memory[from + offset];
                } else {
                    std.mem.copyBackwards(u8, self.memory[to .. to + length], self.memory[from .. from + length]);
                }
            },
            .dot, .u_dot => {
                const value = try self.pop();
                self.writeNumber(if (builtin == .u_dot) @as(UCell, @bitCast(value)) else value);
                self.write(" ");
            },
            .c_dot => {
                self.writeNumber((try self.pop()) & 0xff);
                self.write(" ");
            },
            .dot_s => {
                self.writeDepth(self.data_depth);
                // Like gforth, only the top items are shown below the depth.
                for (self.data_stack[self.data_depth -| max_dot_s_items .. self.data_depth]) |value| {
                    self.writeNumber(value);
                    self.write(" ");
                }
            },
            .echo => {
                const byte: [1]u8 = .{@truncate(@as(UCell, @bitCast(try self.pop())))};
                self.write(&byte);
            },
            .cr => self.write("\n"),
            .space => self.write(" "),
            .spaces => {
                var count = try self.pop();
                while (count > 0) : (count -= 1) self.write(" ");
            },
            .type => {
                const bytes = try self.memoryRange();
                self.write(bytes);
            },
            .hex => try self.writeCell(base_address, 16),
            .dec => try self.writeCell(base_address, 10),
            .oct => try self.writeCell(base_address, 8),
            .base => try self.push(base_address),
            .here => try self.push(self.data_here),
            .allot => try self.reserveData(try self.pop()),
            .builds => {
                const name = (try self.nextSourceToken()) orelse return error.InvalidDefinition;
                const address = self.data_here;
                const id = try self.appendWord(name, .created, .drop, address);
                self.words[id].data_here_before = address;
                self.last_created_word = id;
            },
            .immediate => {
                if (self.word_count == self.builtin_count) return error.InvalidDefinition;
                self.words[self.word_count - 1].immediate = true;
            },
            .comma => {
                const value = try self.pop();
                const address = self.data_here;
                try self.reserveData(cell_size);
                try self.writeCell(address, value);
            },
            .c_comma => {
                const value = try self.pop();
                const address = self.data_here;
                try self.reserveData(1);
                self.memory[@intCast(address)] = @truncate(@as(UCell, @bitCast(value)));
            },
            .execute => try self.executeWord(try self.wordId(try self.pop())),
            .index => try self.push((try self.loopFrame(1)).index),
            .index_2 => try self.push((try self.loopFrame(2)).index),
            .index_3 => try self.push((try self.loopFrame(3)).index),
            .leave => try self.compileLeave(),
            .unloop => {
                if (self.loop_depth == 0) return error.LoopMismatch;
                self.loop_depth -= 1;
            },
            .words => {
                // Like gforth, WORDS lists the word list that is searched first.
                const wid = if (self.searchOrderDepth() == 0) forth_wordlist else self.searchOrderEntry(0);
                for (self.words[0..self.word_count]) |word| {
                    if (word.name_len == 0 or word.wordlist != wid) continue;
                    self.write(word.name[0..word.name_len]);
                    self.write(" ");
                }
                self.write("\n");
            },
            .input => {
                var line: [4096]u8 = undefined;
                while (true) {
                    const token = try self.readInputToken(&line) orelse continue;
                    const parsed = try self.parseNumber(token) orelse ParsedNumber{ .value = 0, .double = true };
                    if (parsed.double) {
                        self.write(" ?\n");
                        continue;
                    }
                    try self.push(doubleCells(parsed.value).low);
                    break;
                }
            },
            .f_input => {
                var line: [4096]u8 = undefined;
                while (true) {
                    const token = try self.readInputToken(&line) orelse continue;
                    const parsed = parseFloat(token, false) orelse {
                        self.write(" ?\n");
                        continue;
                    };
                    try self.fpush(parsed);
                    break;
                }
            },
            .bye => self.halted = true,
            .load => {
                const path = (try self.nextSourceToken()) orelse return error.InputUnavailable;
                const load_fn = self.writer.load_fn orelse return error.FileUnavailable;
                try load_fn(self.writer.context, path, self);
            },
            .save => {
                const path = (try self.nextSourceToken()) orelse return error.InputUnavailable;
                const save_fn = self.writer.save_fn orelse return error.FileUnavailable;
                try save_fn(self.writer.context, path, self);
            },
            .savesys => {
                const path = (try self.nextSourceToken()) orelse return error.InputUnavailable;
                const savesys_fn = self.writer.savesys_fn orelse return error.FileUnavailable;
                try savesys_fn(self.writer.context, path, self);
            },
            .compile_if => try self.compileIf(),
            .compile_else => try self.compileElse(),
            .compile_then => try self.compileThen(),
            .compile_begin => try self.compileBegin(),
            .compile_end => try self.compileEnd(false),
            .compile_again => try self.compileEnd(true),
            .compile_while => try self.compileWhile(),
            .compile_repeat => try self.compileRepeat(),
            .compile_do => try self.compileDo(false),
            .compile_q_do => try self.compileDo(true),
            .compile_loop => try self.compileLoop(false),
            .compile_plus_loop => try self.compileLoop(true),
            .compile_does => try self.compileDoes(),
            .compile_case => try self.compileCase(),
            .compile_of => try self.compileOf(),
            .compile_endof => try self.compileEndof(),
            .compile_endcase => try self.compileEndcase(),
            .compile_exit => {
                try self.requireCompiling();
                _ = try self.emit(.{ .kind = .exit });
            },
            .compile_recurse => {
                if (!self.compiling or !self.defining) return error.CompileOnly;
                _ = try self.emit(.{ .kind = .call, .value = self.current_word });
            },
            .f_drop => _ = try self.fpop(),
            .f_dup => try self.fpush(try self.fpeek(0)),
            .f_swap => {
                try self.requireFloatDepth(2);
                std.mem.swap(Float, &self.float_stack[self.float_depth - 1], &self.float_stack[self.float_depth - 2]);
            },
            .f_over => try self.fpush(try self.fpeek(1)),
            .f_rot, .f_minus_rot => {
                try self.requireFloatDepth(3);
                const items = self.float_stack[self.float_depth - 3 .. self.float_depth];
                if (builtin == .f_rot) std.mem.rotate(Float, items, 1) else std.mem.rotate(Float, items, 2);
            },
            .f_nip => {
                const top = try self.fpop();
                _ = try self.fpop();
                try self.fpush(top);
            },
            .f_tuck => {
                try self.requireFloatDepth(2);
                const top = try self.fpeek(0);
                std.mem.swap(Float, &self.float_stack[self.float_depth - 1], &self.float_stack[self.float_depth - 2]);
                try self.fpush(top);
            },
            .f_pick => {
                const depth = try self.pop();
                if (depth < 0) return error.FloatStackUnderflow;
                try self.fpush(try self.fpeek(@intCast(depth)));
            },
            .f_depth => try self.push(@intCast(self.float_depth)),
            .f_dot_s => {
                self.writeDepth(self.float_depth);
                // gforth shows each item as 14 0 17 F.RDP does: exponential notation
                // filling 14 characters (3.0000000000E0).
                var field: [max_rdp_width]u8 = undefined;
                for (self.float_stack[self.float_depth -| max_dot_s_items .. self.float_depth]) |value| {
                    self.write(formatRdp(value, 14, 0, 17, &field) catch unreachable);
                    self.write(" ");
                }
            },
            .f_add, .f_sub, .f_mul, .f_div, .f_max, .f_min => {
                const b = try self.fpop();
                const a = try self.fpop();
                try self.fpush(switch (builtin) {
                    .f_add => a + b,
                    .f_sub => a - b,
                    .f_mul => a * b,
                    .f_div => a / b,
                    .f_max => @max(a, b),
                    .f_min => @min(a, b),
                    else => unreachable,
                });
            },
            .f_negate, .f_abs, .f_sqrt, .f_exp, .f_ln, .f_sin, .f_cos, .f_tan => {
                const a = try self.fpop();
                try self.fpush(switch (builtin) {
                    .f_negate => -a,
                    .f_abs => @abs(a),
                    .f_sqrt => @sqrt(a),
                    .f_exp => cr_exp(a),
                    .f_ln => cr_log(a),
                    .f_sin => trig(cr_sin, a),
                    .f_cos => trig(cr_cos, a),
                    .f_tan => trig(cr_tan, a),
                    else => unreachable,
                });
            },
            .f_equal, .f_not_equal, .f_less, .f_greater, .f_less_equal, .f_greater_equal => {
                const b = try self.fpop();
                const a = try self.fpop();
                try self.push(truth(switch (builtin) {
                    .f_equal => a == b,
                    .f_not_equal => a != b,
                    .f_less => a < b,
                    .f_greater => a > b,
                    .f_less_equal => a <= b,
                    .f_greater_equal => a >= b,
                    else => unreachable,
                }));
            },
            .f_zero_equal, .f_zero_not_equal, .f_zero_less, .f_zero_greater, .f_zero_less_equal, .f_zero_greater_equal => {
                const a = try self.fpop();
                try self.push(truth(switch (builtin) {
                    .f_zero_equal => a == 0,
                    .f_zero_not_equal => a != 0,
                    .f_zero_less => a < 0,
                    .f_zero_greater => a > 0,
                    .f_zero_less_equal => a <= 0,
                    .f_zero_greater_equal => a >= 0,
                    else => unreachable,
                }));
            },
            .f_fetch => try self.fpush(try self.readFloat(try self.pop())),
            .f_store => {
                const address = try self.pop();
                try self.writeFloat(address, try self.fpop());
            },
            .f_comma => {
                const value = try self.fpop();
                const address = self.data_here;
                try self.reserveData(float_size);
                try self.writeFloat(address, value);
            },
            .f_array_fetch => try self.fpush(try self.readFloat(try self.arrayAddress())),
            .f_array_store => {
                const address = try self.arrayAddress();
                try self.writeFloat(address, try self.fpop());
            },
            .f_add_store => {
                const address = try self.pop();
                const value = try self.fpop();
                try self.writeFloat(address, (try self.readFloat(address)) + value);
            },
            .f_question => {
                self.writeFloatFixed(try self.readFloat(try self.pop()));
                self.write(" ");
            },
            .floats => try self.push((try self.pop()) *% float_size),
            .float_plus => try self.push((try self.pop()) +% float_size),
            .s_to_f => try self.fpush(@floatFromInt(try self.pop())),
            .f_to_s => try self.push(floatToCell(try self.fpop())),
            .define_colon, .define_variable, .define_fvariable, .define_constant, .define_value, .define_two_variable, .define_two_constant, .define_fconstant, .define_array => try self.runDefiningWord(builtin),
            .end_definition => try self.endDefinition(),
            .tick => {
                const name = (try self.nextSourceToken()) orelse return error.InvalidDefinition;
                try self.push(try self.lookupOrFail(name));
            },
            .to_body => try self.push(try self.bodyAddress(try self.wordId(try self.pop()))),
            // Compile the value on the stack into the definition (`[ 2 3 * ] LITERAL`).
            .literal => {
                try self.requireCompiling();
                _ = try self.emit(.{ .kind = .literal, .value = try self.pop() });
            },
            .fliteral => {
                try self.requireCompiling();
                _ = try self.emit(.{ .kind = .float_literal, .value = floatBits(try self.fpop()) });
            },
            .pi => try self.fpush(std.math.pi),
            .f_dot => {
                self.writeFloatFixed(try self.fpop());
                self.write(" ");
            },
            .s_to_d => try self.pushDouble(try self.pop()),
            .d_to_s => {
                _ = try self.pop();
            },
            .d_add, .d_sub => {
                const b = try self.popDouble();
                const a = try self.popDouble();
                try self.pushDouble(if (builtin == .d_add) a +% b else a -% b);
            },
            .d_negate => try self.pushDouble(0 -% try self.popDouble()),
            .d_abs => {
                const d = try self.popDouble();
                try self.pushDouble(if (d < 0) 0 -% d else d);
            },
            .d_zero_equal => try self.push(truth(try self.popDouble() == 0)),
            .d_zero_less => try self.push(truth(try self.popDouble() < 0)),
            .d_equal, .d_less => {
                const b = try self.popDouble();
                const a = try self.popDouble();
                try self.push(truth(if (builtin == .d_equal) a == b else a < b));
            },
            .d_dot => {
                self.writeNumber(try self.popDouble());
                self.write(" ");
            },
            .two_fetch => try self.pushDouble(try self.readDouble(try self.pop())),
            .two_store => {
                const address = try self.pop();
                try self.writeDouble(address, try self.popDouble());
            },
            .d_to_f => try self.fpush(@floatFromInt(try self.popDouble())),
            .f_to_d => try self.pushDouble(floatToDouble(try self.fpop())),
            .count => {
                const address = try self.pop();
                const at = try self.memoryAddress(address, 1);
                try self.push(address + 1);
                try self.push(self.memory[at]);
            },
            .pad => try self.push(pad_address),
            .accept => {
                const capacity = try self.pop();
                const address = try self.pop();
                const read_fn = self.writer.read_fn orelse return error.InputUnavailable;
                var line: [4096]u8 = undefined;
                const input = read_fn(self.writer.context, &line) orelse &.{};
                const length: usize = @min(input.len, @as(usize, @intCast(@max(capacity, 0))));
                const start = try self.memoryAddress(address, length);
                @memcpy(self.memory[start .. start + length], input[0..length]);
                try self.push(@intCast(length));
            },
            .evaluate => try self.interpretSource(try self.memoryRange(), .evaluate),
            .key => {
                const key_fn = self.writer.key_fn orelse return error.InputUnavailable;
                try self.push(key_fn(self.writer.context) orelse return error.InputUnavailable);
            },
            .key_question => {
                const ready = if (self.writer.key_ready_fn) |ready_fn| ready_fn(self.writer.context) else false;
                try self.push(truth(ready));
            },
            .hold_start => self.resetHold(),
            .hold_nest => {
                if (self.hold_depth == max_hold_nesting) return error.PicturedNumericOverflow;
                self.hold_stack[self.hold_depth] = self.hold_end;
                self.hold_depth += 1;
                self.hold_end = self.hold_ptr;
            },
            .hold_release => {
                if (self.hold_depth == 0) return error.PicturedNumericOverflow;
                self.hold_depth -= 1;
                self.hold_ptr = self.hold_end;
                self.hold_end = self.hold_stack[self.hold_depth];
            },
            .hold_digit => try self.pushDouble(@bitCast(try self.holdDigit(@bitCast(try self.popDouble())))),
            .hold_digits => {
                var value: UDouble = @bitCast(try self.popDouble());
                while (true) {
                    value = try self.holdDigit(value);
                    if (value == 0) break;
                }
                try self.pushDouble(0);
            },
            .hold_finish => {
                _ = try self.popDouble();
                try self.push(self.hold_ptr);
                try self.push(self.hold_end - self.hold_ptr);
            },
            .hold => try self.holdBytes(&.{@truncate(@as(UCell, @bitCast(try self.pop())))}),
            .holds => {
                const bytes = try self.memoryRange();
                var copy: [max_gforth_string]u8 = undefined;
                if (bytes.len > copy.len) return error.PicturedNumericOverflow;
                @memcpy(copy[0..bytes.len], bytes);
                try self.holdBytes(copy[0..bytes.len]);
            },
            .sign => {
                if (try self.pop() < 0) try self.holdBytes("-");
            },
            .to_number => {
                const count = try self.pop();
                var address = try self.pop();
                var value: UDouble = @bitCast(try self.popDouble());
                const base = try self.validBase();
                var remaining = count;
                while (remaining > 0) : (remaining -= 1) {
                    const at = try self.memoryAddress(address, 1);
                    const digit = digitValue(self.memory[at]) orelse break;
                    if (digit >= base) break;
                    value = value *% @as(UDouble, @intCast(base)) +% @as(UDouble, @intCast(digit));
                    address += 1;
                }
                try self.pushDouble(@bitCast(value));
                try self.push(address);
                try self.push(remaining);
            },
            .string_to_number => {
                const parsed = try self.parseNumber(try self.memoryRange());
                try self.pushDouble(if (parsed) |number| number.value else 0);
                try self.push(truth(parsed != null));
            },
            .to_float => {
                const bytes = try self.memoryRange();
                const blank = std.mem.indexOfNone(u8, bytes, " ") == null;
                if (if (blank) 0 else parseFloat(bytes, false)) |value| {
                    try self.fpush(value);
                    try self.push(true_flag);
                } else try self.push(0);
            },
            .within => {
                const upper = try self.pop();
                const lower = try self.pop();
                const value = try self.pop();
                try self.push(truth(@as(UCell, @bitCast(value -% lower)) < @as(UCell, @bitCast(upper -% lower))));
            },
            .two_to_r => {
                try self.requireDepth(2);
                if (max_stack - self.return_depth < 2) return error.ReturnStackOverflow;
                const second = try self.pop();
                const first = try self.pop();
                self.return_stack[self.return_depth] = first;
                self.return_stack[self.return_depth + 1] = second;
                self.return_depth += 2;
            },
            .two_r_from => {
                if (self.return_depth < 2) return error.ReturnStackUnderflow;
                if (max_stack - self.data_depth < 2) return error.StackOverflow;
                self.return_depth -= 2;
                try self.push(self.return_stack[self.return_depth]);
                try self.push(self.return_stack[self.return_depth + 1]);
            },
            .place => {
                const destination = try self.pop();
                const count = try self.pop();
                const source = try self.pop();
                // Like gforth, at most 255 bytes are stored; the length byte is written
                // after the copy so an overlapping source is read intact.
                const length: usize = @intCast(std.math.clamp(count, 0, 255));
                const to = try self.memoryAddress(destination, length + 1);
                const from = try self.memoryAddress(source, length);
                const target = self.memory[to + 1 .. to + 1 + length];
                const bytes = self.memory[from .. from + length];
                if (to + 1 <= from) std.mem.copyForwards(u8, target, bytes) else std.mem.copyBackwards(u8, target, bytes);
                self.memory[to] = @intCast(length);
            },
            .abort => return error.Aborted,
            .ms => {
                const milliseconds = try self.pop();
                const sleep_fn = self.writer.sleep_fn orelse return error.HostUnavailable;
                try sleep_fn(self.writer.context, @max(milliseconds, 0));
            },
            .utime => {
                const utime_fn = self.writer.utime_fn orelse return error.HostUnavailable;
                try self.pushDouble(try utime_fn(self.writer.context));
            },
            .page => self.write("\x1b[2J\x1b[1;1H"),
            .getenv => {
                const name = try self.memoryRange();
                const getenv_fn = self.writer.getenv_fn orelse return error.HostUnavailable;
                // The name may lie inside the result buffer, so copy it out first.
                if (name.len > max_host_name) return error.StringTooLong;
                var name_copy: [max_host_name]u8 = undefined;
                @memcpy(name_copy[0..name.len], name);
                const start: usize = @intCast(environment_buffer_base);
                const found = try getenv_fn(self.writer.context, name_copy[0..name.len], self.memory[start .. start + environment_buffer_size]);
                if (found) |length| {
                    try self.push(environment_buffer_base);
                    try self.push(@intCast(length));
                } else {
                    try self.push(0);
                    try self.push(0);
                }
            },
            .system => {
                const command = try self.memoryRange();
                const system_fn = self.writer.system_fn orelse return error.HostUnavailable;
                try system_fn(self.writer.context, command);
            },
            .state => try self.push(state_address),
            .throw => {
                const code = try self.pop();
                if (code == 0) return;
                if (code == -1) return error.Aborted;
                // Codes of interpreter errors raise that error again, with its own message.
                for (error_codes) |entry| {
                    if (entry[1] == code) return entry[0];
                }
                self.throw_code = code;
                return error.Thrown;
            },
            .catch_word => {
                const xt = try self.wordId(try self.pop());
                const frame = CatchFrame{
                    .data_depth = self.data_depth,
                    .float_depth = self.float_depth,
                    .return_depth = self.return_depth,
                    .loop_depth = self.loop_depth,
                    .control_depth = self.control_depth,
                    .pending = self.pending,
                    .compiling = self.compiling,
                    .defining = self.defining,
                    .local_count = self.local_count,
                };
                if (self.executeWord(xt)) |_| {
                    try self.push(0);
                } else |err| {
                    const code = self.throwCodeOf(err);
                    self.restoreCatchFrame(frame);
                    try self.push(code);
                }
            },
            .word_parse => {
                const delimiter: u8 = @truncate(@as(UCell, @bitCast(try self.pop())));
                const text = self.parseWordText(delimiter);
                if (text.len > max_gforth_string) return error.StringTooLong;
                const start: usize = @intCast(word_buffer_address);
                // The text may lie in the buffer of an earlier WORD result.
                std.mem.copyForwards(u8, self.memory[start + 1 .. start + 1 + text.len], text);
                self.memory[start] = @intCast(text.len);
                try self.push(word_buffer_address);
            },
            .find_word => {
                const address = try self.pop();
                const at = try self.memoryAddress(address, 1);
                const length = self.memory[at];
                _ = try self.memoryAddress(address + 1, length);
                if (self.lookup(self.memory[at + 1 .. at + 1 + length])) |id| {
                    try self.push(id);
                    try self.push(if (self.words[id].immediate) 1 else -1);
                } else {
                    try self.push(address);
                    try self.push(0);
                }
            },
            .parse => {
                const delimiter: u8 = @truncate(@as(UCell, @bitCast(try self.pop())));
                if (!self.sourceInMemory()) {
                    try self.push(0);
                    try self.push(0);
                    return;
                }
                const address = self.sourceAddress();
                const rest = self.remainingSource();
                const length = for (rest, 0..) |byte, index| {
                    if (byte == delimiter) break index;
                } else rest.len;
                self.source_cursor += if (length < rest.len) length + 1 else length;
                try self.push(address);
                try self.push(@intCast(length));
            },
            .find_name => {
                const name = try self.memoryRange();
                try self.push(if (self.lookup(name)) |id| @as(Cell, id) + 1 else 0);
            },
            .name_to_int => try self.push(try self.validNameToken(try self.pop())),
            .name_to_string => {
                const word = self.words[try self.validNameToken(try self.pop())];
                const slot = name_buffer_base + @as(Cell, @intCast(self.name_buffer_index)) * (max_name + 1);
                self.name_buffer_index = (self.name_buffer_index + 1) % name_buffer_count;
                const start: usize = @intCast(slot);
                @memcpy(self.memory[start .. start + word.name_len], word.name[0..word.name_len]);
                try self.push(slot);
                try self.push(word.name_len);
            },
            .see => {
                const name = (try self.nextSourceToken()) orelse return error.InputUnavailable;
                try self.seeWord(try self.lookupOrFail(name));
            },
            .include, .require => {
                const name = (try self.nextSourceToken()) orelse return error.InputUnavailable;
                if (builtin == .include) try self.includeFile(name) else try self.requireFile(name);
            },
            .included, .required => {
                const name = try self.memoryRange();
                if (builtin == .included) try self.includeFile(name) else try self.requireFile(name);
            },
            .included_query => try self.push(truth(self.findSourceFile(try self.memoryRange()) != null)),
            .source_file_name => {
                if (self.currentFileFrame()) |frame| {
                    try self.push(@intCast(sourceFileEntry(frame.file_index) + 1));
                    try self.push(@intCast(self.sourceFileName(frame.file_index).len));
                } else {
                    const evaluating = self.source_kind == .evaluate;
                    try self.push(if (evaluating) evaluate_source_name_address else terminal_source_name_address);
                    try self.push(@intCast(if (evaluating) evaluate_source_name.len else terminal_source_name.len));
                }
            },
            .source_line_number => try self.push(if (self.currentFileFrame()) |frame| frame.line else 0),
            .marker => {
                const name = (try self.nextSourceToken()) orelse return error.InvalidDefinition;
                const id = try self.appendDataWord(name, .marker, marker_snapshot_size);
                try self.snapshotMarker(self.words[id].value);
            },
            .locate => {
                const name = (try self.nextSourceToken()) orelse return error.InputUnavailable;
                try self.locateWord(try self.lookupOrFail(name));
            },
            .only => self.setSearchOrder(&.{ root_wordlist, root_wordlist }),
            .also, .previous, .forth => {
                var order: [max_search_order]Cell = undefined;
                const current = self.searchOrder(&order);
                switch (builtin) {
                    .also => {
                        if (current.len == 0) return error.SearchOrderUnderflow;
                        if (current.len == max_search_order) return error.SearchOrderOverflow;
                        std.mem.copyBackwards(Cell, order[1 .. current.len + 1], order[0..current.len]);
                        self.setSearchOrder(order[0 .. current.len + 1]);
                    },
                    .previous => {
                        if (current.len == 0) return error.SearchOrderUnderflow;
                        self.setSearchOrder(current[1..]);
                    },
                    else => {
                        if (current.len == 0) self.setSearchOrder(&.{forth_wordlist}) else {
                            current[0] = forth_wordlist;
                            self.setSearchOrder(current);
                        }
                    },
                }
            },
            .definitions => {
                if (self.searchOrderDepth() == 0) return error.SearchOrderUnderflow;
                try self.writeCell(current_wordlist_address, self.searchOrderEntry(0));
            },
            .order => {
                for (0..self.searchOrderDepth()) |index| {
                    self.writeWordlistName(self.searchOrderEntry(index));
                    self.write(" ");
                }
                self.write("    ");
                self.writeWordlistName(self.currentWordlist());
                self.write(" ");
            },
            .get_order => {
                const depth = self.searchOrderDepth();
                if (max_stack - self.data_depth < depth + 1) return error.StackOverflow;
                var index = depth;
                while (index > 0) {
                    index -= 1;
                    try self.push(self.searchOrderEntry(index));
                }
                try self.push(@intCast(depth));
            },
            .set_order => {
                const count = try self.pop();
                if (count == -1) {
                    self.setSearchOrder(&.{ root_wordlist, root_wordlist });
                    return;
                }
                if (count < 0) return error.SearchOrderUnderflow;
                if (count > max_search_order) return error.SearchOrderOverflow;
                const depth: usize = @intCast(count);
                try self.requireDepth(depth);
                var order: [max_search_order]Cell = undefined;
                for (0..depth) |index| order[index] = try self.validWordlist(try self.peek(index));
                self.data_depth -= depth;
                self.setSearchOrder(order[0..depth]);
            },
            .to_order => {
                const wid = try self.validWordlist(try self.pop());
                var order: [max_search_order]Cell = undefined;
                const current = self.searchOrder(&order);
                if (current.len == max_search_order) return error.SearchOrderOverflow;
                std.mem.copyBackwards(Cell, order[1 .. current.len + 1], order[0..current.len]);
                order[0] = wid;
                self.setSearchOrder(order[0 .. current.len + 1]);
            },
            .get_current => try self.push(self.currentWordlist()),
            .set_current => try self.writeCell(current_wordlist_address, try self.validWordlist(try self.pop())),
            .wordlist, .vocabulary => {
                const count = self.wordlistCount();
                if (count == max_wordlists) return error.DictionaryFull;
                const wid = count + 1;
                if (builtin == .vocabulary) {
                    const name = (try self.nextSourceToken()) orelse return error.InvalidDefinition;
                    _ = try self.appendWord(name, .vocabulary, .drop, wid);
                } else try self.push(wid);
                try self.writeCell(wordlist_count_address, wid);
            },
            .forth_wordlist_word => try self.push(forth_wordlist),
            .search_wordlist => {
                const wid = try self.validWordlist(try self.pop());
                const name = try self.memoryRange();
                if (self.lookupIn(name, wid)) |id| {
                    try self.push(id);
                    try self.push(if (self.words[id].immediate) 1 else -1);
                } else try self.push(0);
            },
            .bracket_if => {
                if (try self.pop() == 0) try self.skipConditional(true);
            },
            .bracket_else => try self.skipConditional(false),
            .bracket_then => {},
            .f_dot_rdp, .f_to_str_rdp, .f_to_buf_rdp => {
                const np = try self.pop();
                const nd = try self.pop();
                const nr = try self.pop();
                const destination: ?Cell = if (builtin == .f_to_buf_rdp) try self.pop() else null;
                const value = try self.fpop();
                var text: [max_rdp_width]u8 = undefined;
                const formatted = try formatRdp(value, nr, nd, np, &text);
                switch (builtin) {
                    .f_dot_rdp => self.write(formatted),
                    .f_to_buf_rdp => {
                        const start = try self.memoryAddress(destination.?, formatted.len);
                        @memcpy(self.memory[start .. start + formatted.len], formatted);
                    },
                    else => {
                        // Like gforth, the text goes just below the pictured numeric output
                        // in the hold area and is overwritten by the next conversion.
                        const length: Cell = @intCast(formatted.len);
                        if (self.hold_ptr - hold_bottom < length) return error.PicturedNumericOverflow;
                        const start: usize = @intCast(self.hold_ptr - length);
                        @memcpy(self.memory[start .. start + formatted.len], formatted);
                        try self.push(self.hold_ptr - length);
                        try self.push(length);
                    },
                }
            },
            .bracket_defined, .bracket_undefined => {
                const name = (try self.nextSourceToken()) orelse return error.InputUnavailable;
                // While compiling, a local variable in scope counts as defined, as in gforth.
                const found = (self.compiling and self.findLocal(name) != null) or self.lookup(name) != null;
                try self.push(truth(if (builtin == .bracket_defined) found else !found));
            },
            .read_only => try self.push(fam_read_only),
            .write_only => try self.push(fam_write_only),
            .read_write => try self.push(fam_read_write),
            .stdin => try self.push(stdin_fileid),
            .stdout => try self.push(stdout_fileid),
            .stderr => try self.push(stderr_fileid),
            .open_file, .create_file => {
                const fam = try self.pop();
                const name = try self.memoryRange();
                const files = try self.fileOps();
                const access: ?FileAccess = switch (fam) {
                    fam_read_only => .read_only,
                    fam_write_only => .write_only,
                    fam_read_write => .read_write,
                    else => null,
                };
                const result = if (access) |mode| files.open(self.writer.context, name, mode, builtin == .create_file) else FileResult{ .ior = errnoIor(errno_invalid) };
                try self.push(if (result.ior == 0) @bitCast(result.value) else 0);
                try self.push(result.ior);
            },
            .close_file => {
                const fileid = try self.pop();
                try self.push((try self.fileOps()).close(self.writer.context, fileid));
            },
            .read_line => {
                const fileid = try self.pop();
                const buffer = try self.memoryRange();
                const files = try self.fileOps();
                if (max_stack - self.data_depth < 3) return error.StackOverflow;
                const result = files.read_line(self.writer.context, fileid, buffer);
                try self.push(if (result.ior == 0) @intCast(result.length) else 0);
                try self.push(if (result.ior == 0) truth(result.found) else 0);
                try self.push(result.ior);
            },
            .write_line, .write_file => {
                const fileid = try self.pop();
                const bytes = try self.memoryRange();
                const files = try self.fileOps();
                var ior = files.write(self.writer.context, fileid, bytes);
                if (ior == 0 and builtin == .write_line) ior = files.write(self.writer.context, fileid, line_terminator);
                try self.push(ior);
            },
            .file_size => {
                const fileid = try self.pop();
                const result = (try self.fileOps()).size(self.writer.context, fileid);
                try self.pushDouble(if (result.ior == 0) result.value else 0);
                try self.push(result.ior);
            },
            .reposition_file => {
                const fileid = try self.pop();
                const position: UDouble = @bitCast(try self.popDouble());
                const files = try self.fileOps();
                try self.push(if (position > std.math.maxInt(i64)) errnoIor(errno_invalid) else files.reposition(self.writer.context, fileid, @intCast(position)));
            },
            .allocate => {
                const size: UCell = @bitCast(try self.pop());
                const address = try self.heapAllocate(size);
                try self.push(address orelse 0);
                try self.push(if (address == null) errnoIor(errno_no_memory) else 0);
            },
            .free => {
                const freed = try self.heapFree(try self.pop());
                try self.push(if (freed) 0 else errnoIor(errno_invalid));
            },
            .resize => {
                const size: UCell = @bitCast(try self.pop());
                const address = try self.pop();
                switch (try self.heapResize(address, size)) {
                    .address => |moved| {
                        try self.push(moved);
                        try self.push(0);
                    },
                    .no_memory, .bad_pointer => |_, tag| {
                        try self.push(address);
                        try self.push(errnoIor(if (tag == .no_memory) errno_no_memory else errno_invalid));
                    },
                }
            },
            .string_store => {
                const string_var = try self.pop();
                const length = try self.popLength();
                const source = try self.pop();
                _ = try self.memoryAddress(source, length);
                // A fresh buffer keeps the source intact even when it lies in the old string.
                const buffer = try self.heapAllocate(cell_size + length) orelse return self.throwIor(errno_no_memory);
                self.copyMemory(buffer + cell_size, source, length);
                try self.writeCell(buffer, @intCast(length));
                const old = try self.readCell(string_var);
                if (!try self.heapFree(old)) {
                    _ = try self.heapFree(buffer);
                    return self.throwIor(errno_invalid);
                }
                try self.writeCell(string_var, buffer);
            },
            .string_fetch => {
                const string = try self.fetchString(try self.pop());
                try self.push(string.address);
                try self.push(@intCast(string.length));
            },
            .string_fetch_len => try self.push(@intCast((try self.fetchString(try self.pop())).length)),
            .string_store_len => {
                const string_var = try self.pop();
                _ = try self.setStringLength(string_var, try self.popLength());
            },
            .string_append => {
                const string_var = try self.pop();
                const length = try self.popLength();
                const source = try self.pop();
                const end = (try self.fetchString(string_var)).length;
                try self.insertString(string_var, end, source, length, false);
            },
            .char_append => {
                const string_var = try self.pop();
                const char: u8 = @truncate(@as(UCell, @bitCast(try self.pop())));
                const length = (try self.fetchString(string_var)).length;
                const buffer = try self.setStringLength(string_var, length + 1);
                self.memory[@intCast(buffer + cell_size + @as(Cell, @intCast(length)))] = char;
            },
            .string_dot => {
                const string = try self.fetchString(try self.pop());
                self.writeMemory(string.address, string.length);
            },
            .string_delete => {
                const count = try self.popLength();
                const offset = try self.popLength();
                const string_var = try self.pop();
                const string = try self.fetchString(string_var);
                const start = @min(offset, string.length);
                const removed = @min(count, string.length - start);
                const base: usize = @intCast(string.address);
                std.mem.copyForwards(u8, self.memory[base + start .. base + string.length - removed], self.memory[base + start + removed .. base + string.length]);
                _ = try self.setStringLength(string_var, string.length - removed);
            },
            .string_insert, .string_over => {
                const offset = try self.popLength();
                const string_var = try self.pop();
                const length = try self.popLength();
                const source = try self.pop();
                try self.insertString(string_var, offset, source, length, builtin == .string_over);
            },
            .string_free => {
                const string_var = try self.pop();
                try self.freeString(string_var);
            },
            .string_init => {
                const string_var = try self.pop();
                const buffer = try self.heapAllocate(cell_size) orelse return self.throwIor(errno_no_memory);
                try self.writeCell(buffer, 0);
                try self.writeCell(string_var, buffer);
            },
            .string_split => {
                const separator: u8 = @truncate(@as(UCell, @bitCast(try self.pop())));
                const length = try self.popLength();
                const address = try self.pop();
                const start = try self.memoryAddress(address, length);
                const found = std.mem.indexOfScalar(u8, self.memory[start .. start + length], separator);
                const first = found orelse length;
                const rest = if (found != null) first + 1 else length;
                try self.push(address);
                try self.push(@intCast(first));
                try self.push(address + @as(Cell, @intCast(rest)));
                try self.push(@intCast(length - rest));
            },
            .string_iter => {
                const xt = try self.wordId(try self.pop());
                const separator: u8 = @truncate(@as(UCell, @bitCast(try self.pop())));
                const string = try self.fetchString(try self.pop());
                var address = string.address;
                var remaining = string.length;
                while (remaining != 0) {
                    const start: usize = @intCast(address);
                    const part = std.mem.indexOfScalar(u8, self.memory[start .. start + remaining], separator) orelse remaining;
                    const consumed = if (part < remaining) part + 1 else part;
                    try self.push(address);
                    try self.push(@intCast(part));
                    try self.executeWord(xt);
                    address += @intCast(consumed);
                    remaining -= consumed;
                }
            },
            .string_tmp => {
                const xt = try self.wordId(try self.pop());
                const slot = tmp_string_base + @as(Cell, @intCast(self.tmp_string_index % tmp_string_count)) * cell_size;
                self.tmp_string_index += 1;
                try self.freeString(slot);
                const previous_target = self.capture_target;
                const previous_failed = self.capture_failed;
                self.capture_target = slot;
                self.capture_failed = false;
                const result = self.executeWord(xt);
                const failed = self.capture_failed;
                self.capture_target = previous_target;
                self.capture_failed = previous_failed;
                try result;
                if (failed) return self.throwIor(errno_no_memory);
                const string = try self.fetchString(slot);
                try self.push(string.address);
                try self.push(@intCast(string.length));
            },
            .string_array => {
                const array_var = try self.pop();
                try self.push(try self.stringArrayElement(array_var, try self.popLength()));
            },
            .string_array_store => {
                const array_var = try self.pop();
                const index = try self.popLength();
                const element = try self.stringArrayElement(array_var, index);
                try self.push(element);
                try self.executeBuiltin(.string_store);
            },
            .string_array_fetch => {
                const array_var = try self.pop();
                const index: UCell = @bitCast(try self.pop());
                if (index < try self.stringArrayCount(array_var)) {
                    const string = try self.fetchString(try self.stringArrayElement(array_var, @intCast(index)));
                    try self.push(string.address);
                    try self.push(@intCast(string.length));
                } else {
                    try self.push(0);
                    try self.push(0);
                }
            },
            .string_array_count => try self.push(@intCast(try self.stringArrayCount(try self.pop()))),
            .string_array_dot, .string_array_map => {
                const xt: ?u16 = if (builtin == .string_array_map) try self.wordId(try self.pop()) else null;
                const array_var = try self.pop();
                const count = try self.stringArrayCount(array_var);
                for (0..count) |index| {
                    if (index >= try self.stringArrayCount(array_var)) break;
                    const string = try self.fetchString(try self.stringArrayElement(array_var, index));
                    if (xt) |id| {
                        try self.push(string.address);
                        try self.push(@intCast(string.length));
                        try self.executeWord(id);
                    } else {
                        self.writeMemory(string.address, string.length);
                        self.write("\n");
                    }
                }
            },
            .string_array_free => {
                const array_var = try self.pop();
                const count = try self.stringArrayCount(array_var);
                for (0..count) |index| try self.freeString(try self.stringArrayElement(array_var, index));
                try self.freeString(array_var);
            },
            .string_array_slurp => {
                const array_var = try self.pop();
                const fileid = try self.pop();
                try self.slurpLines(fileid, array_var);
            },
            .string_array_slurp_file => {
                const array_var = try self.pop();
                const name = try self.memoryRange();
                const files = try self.fileOps();
                const opened = files.open(self.writer.context, name, .read_only, false);
                if (opened.ior != 0) return self.throwCode(opened.ior);
                const fileid: Cell = @bitCast(opened.value);
                self.slurpLines(fileid, array_var) catch |err| {
                    _ = files.close(self.writer.context, fileid);
                    return err;
                };
                const closed = files.close(self.writer.context, fileid);
                if (closed != 0) return self.throwCode(closed);
            },
        }
    }

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

    /// Pops ( addr u ) and returns the addressed bytes.
    pub fn memoryRange(self: *State) RuntimeError![]u8 {
        const count = try self.pop();
        const address = try self.pop();
        const length: usize = if (count < 0) 0 else @intCast(@min(count, memory_size));
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
