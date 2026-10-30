const std = @import("std");
const builtin_info = @import("builtin");

pub const Cell = i64;
pub const UCell = u64;
pub const Double = i128;
pub const UDouble = u128;
pub const Float = f64;
const cell_size = 8;
const float_size = 8;
const max_words = 1024;
const max_code = 8192;
const max_stack = 1024;
const max_float_stack = 1024;
const max_controls = 128;
const max_name = 255;
pub const memory_size = 2 << 20;
/// The data area ends where the ALLOCATE heap begins; the heap runs to the end of memory.
pub const data_limit: Cell = 1 << 20;
const heap_base: Cell = data_limit;
/// The last 64 KiB hold the frames of local variables, so variable-flavoured locals
/// (`W^`, `F^`, ...) have addresses in logical memory.
const locals_base: Cell = memory_size - 0x10000;
const locals_end: Cell = memory_size;
/// Input buffers below the locals: the terminal input buffer first; the rest is kept
/// for the line buffers of nested INCLUDE files.
const input_area_base: Cell = locals_base - 0x10000;
const tib_address: Cell = input_area_base;
pub const tib_size = 4096;
/// One line buffer per nested INCLUDE level after the TIB.
const max_include_depth = 8;
const include_buffer_base: Cell = tib_address + tib_size;
/// Names of the source files that have been included, which is also the REQUIRE
/// history: 64 entries of a length byte and up to 255 name bytes. The entry count
/// lives at `source_file_count_address`, so images keep the table.
const source_file_table: Cell = include_buffer_base + max_include_depth * tib_size;
const max_source_files = 64;
const source_file_entry_size = 256;
const source_file_count_address: Cell = 0x0218;
/// One byte per table entry: non-zero while the file counts as loaded for REQUIRE.
/// MARKER clears these flags instead of shortening the table, so names that words and
/// open input frames refer to stay valid.
const source_file_loaded_flags: Cell = source_file_table + max_source_files * source_file_entry_size;
/// Word lists: ids 1 (Forth) and 2 (Root) exist from the start; WORDLIST and
/// VOCABULARY allocate more. The count, the current list, and the search order are
/// kept in memory so images restore them. `search_order` holds the first-searched
/// list at index 0.
const forth_wordlist: Cell = 1;
const root_wordlist: Cell = 2;
const max_wordlists = 64;
const max_search_order = 16;
const wordlist_count_address: Cell = 0x0220;
const current_wordlist_address: Cell = 0x0228;
const search_order_depth_address: Cell = 0x0230;
const search_order_address: Cell = 0x0238;
/// Words that are also in the Root word list, so they stay usable after ONLY.
const root_word_names = [_][]const u8{ "FORTH", "FORTH-WORDLIST", "ONLY", "ALSO", "PREVIOUS", "ORDER", "DEFINITIONS", "GET-ORDER", "SET-ORDER", "WORDS" };
/// Bytes a MARKER keeps: the loaded-file mask, the current list, the order depth, and the order.
const marker_snapshot_size = (3 + max_search_order) * cell_size;

/// SOURCEFILENAME results outside files, as in gforth.
const terminal_source_name = "*the terminal*";
const evaluate_source_name = "*evaluated string*";
const terminal_source_name_address: Cell = 0x0d00;
const evaluate_source_name_address: Cell = 0x0d20;
const heap_end: Cell = input_area_base;
/// Results of NAME>STRING, eight 256-byte buffers used in turn, and the WORD buffer.
const name_buffer_base: Cell = 0x0400;
const name_buffer_count = 8;
const word_buffer_address: Cell = 0x0c00;
const max_locals = 64;
/// Each heap block starts with its payload size and a used flag, one cell each.
const heap_header = 2 * cell_size;
const base_address: Cell = 0x0200;
const state_address: Cell = 0x0208;
/// The end of the used part of the heap; kept in memory so images preserve it.
const heap_top_address: Cell = 0x0210;
/// Sixteen string variables holding the results of $TMP, reused in turn.
const tmp_string_base: Cell = 0x0300;
const tmp_string_count = 16;
const hold_bottom: Cell = 0x1000;
const hold_top: Cell = 0x2000;
pub const pad_address: Cell = 0x2000;
const string_buffer_base: Cell = 0x3000;
const string_buffer_size = 256;
const string_buffer_count = 4;
const environment_buffer_base: Cell = 0x3400;
const environment_buffer_size = 0x0c00;
const max_host_name = 1024;
const max_hold_nesting = 16;
const max_counted_string = 127;
const max_gforth_string = 255;
pub const data_start: Cell = 0x4000;
const true_flag: Cell = -1;
const dot_precision = 15;
const fs_precision = 14;
const image_magic = "SIGIMG11";

/// File ids of the standard streams; the host numbers opened files from `first_file_id`.
pub const stdin_fileid: Cell = 1;
pub const stdout_fileid: Cell = 2;
pub const stderr_fileid: Cell = 3;
pub const first_file_id: Cell = 4;
/// File access methods, with gforth's values for R/O, R/W and W/O.
const fam_read_only: Cell = 0;
const fam_read_write: Cell = 2;
const fam_write_only: Cell = 4;
/// I/O results follow gforth: 0 for success, otherwise -512 minus the C errno.
pub const ior_errno_base: Cell = -512;
pub const errno_bad_file: Cell = 9;
pub const errno_no_memory: Cell = 12;
pub const errno_invalid: Cell = 22;
const line_terminator = if (builtin_info.os.tag == .windows) "\r\n" else "\n";

pub fn errnoIor(errno: Cell) Cell {
    return ior_errno_base - errno;
}

pub const FileAccess = enum { read_only, write_only, read_write };
pub const FileResult = struct { value: UCell = 0, ior: Cell = 0 };
/// `found` is false only at the end of the file with nothing read.
pub const LineResult = struct { length: usize = 0, found: bool = false, ior: Cell = 0 };

/// Host file operations. Ids are opaque cells; the standard streams use the fixed ids above.
pub const FileOps = struct {
    /// Opens an existing file, or creates and truncates one when `create` is set.
    open: *const fn (?*anyopaque, []const u8, FileAccess, bool) FileResult,
    close: *const fn (?*anyopaque, Cell) Cell,
    /// Reads up to `buffer.len` bytes of one line, without the LF, CR or CRLF terminator.
    read_line: *const fn (?*anyopaque, Cell, []u8) LineResult,
    write: *const fn (?*anyopaque, Cell, []const u8) Cell,
    size: *const fn (?*anyopaque, Cell) FileResult,
    reposition: *const fn (?*anyopaque, Cell, UCell) Cell,
};

pub const Writer = struct {
    context: ?*anyopaque,
    write_fn: *const fn (?*anyopaque, []const u8) void,
    read_fn: ?*const fn (?*anyopaque, []u8) ?[]const u8 = null,
    load_fn: ?*const fn (?*anyopaque, []const u8, *State) RuntimeError!void = null,
    save_fn: ?*const fn (?*anyopaque, []const u8, *State) RuntimeError!void = null,
    savesys_fn: ?*const fn (?*anyopaque, []const u8, *State) RuntimeError!void = null,
    key_fn: ?*const fn (?*anyopaque) ?u8 = null,
    key_ready_fn: ?*const fn (?*anyopaque) bool = null,
    sleep_fn: ?*const fn (?*anyopaque, Cell) RuntimeError!void = null,
    /// Microseconds since the Unix epoch.
    utime_fn: ?*const fn (?*anyopaque) RuntimeError!Double = null,
    /// Copies the variable's value into the buffer and returns its length, or null when unset.
    getenv_fn: ?*const fn (?*anyopaque, []const u8, []u8) RuntimeError!?usize = null,
    /// Runs a shell command; a non-zero exit status is not an error.
    system_fn: ?*const fn (?*anyopaque, []const u8) RuntimeError!void = null,
    file_ops: ?*const FileOps = null,

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
    minus_rot,
    nip,
    tuck,
    pick,
    roll,
    two_dup,
    two_drop,
    two_swap,
    two_over,
    depth,
    to_r,
    from_r,
    r_fetch,
    add,
    sub,
    mul,
    div,
    mod,
    div_mod,
    negate,
    abs,
    one_plus,
    one_minus,
    two_star,
    two_slash,
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
    zero_less,
    zero_greater,
    zero_not_equal,
    bit_and,
    bit_or,
    bit_xor,
    bit_complement,
    bit_nand,
    bit_nor,
    swap_bytes,
    lshift,
    rshift,
    true_value,
    false_value,
    blank,
    cell,
    cells,
    cell_plus,
    aligned,
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
    on,
    off,
    question,
    array_fetch,
    array_store,
    erase,
    fill,
    move,
    cmove,
    dot,
    u_dot,
    c_dot,
    dot_s,
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
    unloop,
    builds,
    immediate,
    words,
    input,
    bye,
    load,
    save,
    savesys,
    compile_if,
    compile_else,
    compile_then,
    compile_begin,
    compile_end,
    compile_again,
    compile_while,
    compile_repeat,
    compile_do,
    compile_q_do,
    compile_loop,
    compile_plus_loop,
    compile_does,
    compile_case,
    compile_of,
    compile_endof,
    compile_endcase,
    compile_exit,
    compile_recurse,
    f_drop,
    f_dup,
    f_swap,
    f_over,
    f_rot,
    f_minus_rot,
    f_nip,
    f_tuck,
    f_pick,
    f_depth,
    f_dot_s,
    f_add,
    f_sub,
    f_mul,
    f_div,
    f_negate,
    f_abs,
    f_max,
    f_min,
    f_sqrt,
    f_exp,
    f_ln,
    f_sin,
    f_cos,
    f_tan,
    f_equal,
    f_not_equal,
    f_less,
    f_greater,
    f_less_equal,
    f_greater_equal,
    f_zero_equal,
    f_zero_not_equal,
    f_zero_less,
    f_zero_greater,
    f_zero_less_equal,
    f_zero_greater_equal,
    f_fetch,
    f_store,
    f_comma,
    f_array_fetch,
    f_array_store,
    f_add_store,
    f_question,
    floats,
    float_plus,
    s_to_f,
    f_to_s,
    f_dot,
    f_input,
    s_to_d,
    d_to_s,
    d_add,
    d_sub,
    d_negate,
    d_abs,
    d_zero_equal,
    d_zero_less,
    d_equal,
    d_less,
    d_dot,
    two_fetch,
    two_store,
    d_to_f,
    f_to_d,
    count,
    pad,
    accept,
    evaluate,
    key,
    key_question,
    hold_start,
    hold_nest,
    hold_digit,
    hold_digits,
    hold_finish,
    hold_release,
    hold,
    holds,
    sign,
    to_number,
    string_to_number,
    to_float,
    within,
    two_to_r,
    two_r_from,
    place,
    abort,
    ms,
    utime,
    page,
    getenv,
    system,
    state,
    throw,
    read_only,
    write_only,
    read_write,
    stdin,
    stdout,
    stderr,
    open_file,
    create_file,
    close_file,
    read_line,
    write_line,
    write_file,
    file_size,
    reposition_file,
    allocate,
    free,
    resize,
    string_store,
    string_fetch,
    string_fetch_len,
    string_store_len,
    string_append,
    char_append,
    string_dot,
    string_delete,
    string_insert,
    string_over,
    string_free,
    string_init,
    string_split,
    string_iter,
    string_tmp,
    string_array,
    string_array_store,
    string_array_fetch,
    string_array_count,
    string_array_dot,
    string_array_map,
    string_array_free,
    string_array_slurp,
    string_array_slurp_file,
    catch_word,
    word_parse,
    find_word,
    parse,
    find_name,
    name_to_int,
    name_to_string,
    see,
    include,
    included,
    require,
    required,
    included_query,
    source_file_name,
    source_line_number,
    marker,
    locate,
    only,
    also,
    previous,
    forth,
    definitions,
    order,
    get_order,
    set_order,
    to_order,
    get_current,
    set_current,
    vocabulary,
    wordlist,
    forth_wordlist_word,
    search_wordlist,
    bracket_if,
    bracket_else,
    bracket_then,
    bracket_defined,
    bracket_undefined,
    f_dot_rdp,
    f_to_str_rdp,
    f_to_buf_rdp,
};

const HeapResult = union(enum) { address: Cell, no_memory, bad_pointer };
const SourceKind = enum { terminal, evaluate, file };
const IncludeFrame = struct { fileid: Cell, file_index: u8, line: u32 };
/// Where an error happened inside an included file, kept for `report`.
const ErrorLocation = struct { file_index: u8, line: u32 };

/// THROW codes for interpreter errors, so CATCH can return them and THROW can raise
/// them again with the original message. Standard Forth 2012 codes are used where one
/// fits; the rest are system codes from -256 down. UnknownWord stays a plain code
/// because its message needs the word that was not found.
const error_codes = [_]struct { RuntimeError, Cell }{
    .{ error.StackOverflow, -3 },           .{ error.StackUnderflow, -4 },          .{ error.ReturnStackOverflow, -5 },
    .{ error.ReturnStackUnderflow, -6 },    .{ error.DictionaryFull, -8 },          .{ error.InvalidAddress, -9 },
    .{ error.DivisionByZero, -10 },         .{ error.CompileOnly, -14 },            .{ error.PicturedNumericOverflow, -17 },
    .{ error.StringTooLong, -18 },          .{ error.NameTooLong, -19 },            .{ error.HostUnavailable, -21 },
    .{ error.ControlMismatch, -22 },        .{ error.InvalidNumber, -24 },          .{ error.LoopMismatch, -26 },
    .{ error.FloatStackOverflow, -44 },     .{ error.FloatStackUnderflow, -45 },    .{ error.CodeFull, -256 },
    .{ error.MemoryExhausted, -257 },       .{ error.ControlStackOverflow, -258 },  .{ error.InvalidDefinition, -259 },
    .{ error.InvalidBase, -260 },           .{ error.InvalidExecutionToken, -261 }, .{ error.InputUnavailable, -262 },
    .{ error.FileUnavailable, -263 },       .{ error.InvalidImage, -264 },          .{ error.HostFailed, -265 },
    .{ error.CommentUnclosed, -266 },       .{ error.IncludeNesting, -267 },        .{ error.TooManySourceFiles, -268 },
    .{ error.SearchOrderOverflow, -49 },     .{ error.SearchOrderUnderflow, -50 },   .{ error.InvalidWordlist, -269 },
};
const throw_code_undefined_word: Cell = -13;

/// Interpreter state that CATCH restores when the executed word throws.
const CatchFrame = struct {
    data_depth: usize,
    float_depth: usize,
    return_depth: usize,
    loop_depth: usize,
    control_depth: usize,
    pending: Pending,
    compiling: bool,
    defining: bool,
    local_count: usize,
};

const WordKind = enum { builtin, colon, variable, constant, array, created, value, fconstant, two_constant, marker, vocabulary };
const Word = struct {
    name: [max_name]u8 = [_]u8{0} ** max_name,
    name_len: u8 = 0,
    kind: WordKind = .builtin,
    builtin: Builtin = .drop,
    immediate: bool = false,
    has_does: bool = false,
    value: Cell = 0,
    code_start: u16 = 0,
    code_end: u16 = 0,
    does_code_start: u16 = 0,
    does_code_end: u16 = 0,
    data_here_before: Cell = 0,
    /// Bytes of local-variable frame the definition needs when it runs.
    locals_size: u16 = 0,
    /// Source file table index + 1 (0 when not defined in a file) and the lines where
    /// the definition starts and ends, for LOCATE.
    source_file: u8 = 0,
    source_line: u32 = 0,
    source_end_line: u32 = 0,
    /// The word list the word belongs to.
    wordlist: u8 = @intCast(forth_wordlist),
};

/// Local operations other than `local_frame` encode the frame offset in the low 32 bits
/// of the value and the `LocalKind` above them; `local_frame` holds the word id.
const OpKind = enum { call, compile_call, builtin, literal, float_literal, execution_token, store_value, branch, branch_zero, do_loop, q_do_loop, loop, plus_loop, leave, print_string, string_literal, does, exit, local_frame, local_store, local_fetch, local_address, local_execute };
const LocalKind = enum(u8) { cell, double, float, char, xt };
const Local = struct {
    name: [max_name]u8 = undefined,
    name_len: u8 = 0,
    kind: LocalKind = .cell,
    /// Variable flavour (`W^` ...): the name pushes the slot address instead of its value.
    variable: bool = false,
    offset: u16 = 0,
};
const Op = struct { kind: OpKind, value: Cell = 0 };
const ControlKind = enum { if_branch, else_branch, begin_loop, while_branch, do_loop, case_start, of_branch, endof_branch };
/// `locals` is the number of local names visible where the structure starts; a DO loop
/// also keeps the fewest visible at any of its LEAVEs.
const Control = struct { kind: ControlKind, address: u16, locals: u16 = 0, leave_locals: u16 = std.math.maxInt(u16) };
const Loop = struct { index: Cell, limit: Cell, exit_pc: u16, exit_after_first: bool = false };
const Pending = enum { none, colon_name, variable_name, constant_name, array_name, forget_name, tick_name, value_name, to_name, char_name, postpone_name, fconstant_name, fvariable_name, two_constant_name, two_variable_name };
const StringWord = enum { s_quote, s_escape_quote, print_escape, print_paren };
const ParsedNumber = struct { value: Double, double: bool };

pub const RuntimeError = error{
    StackUnderflow,
    ReturnStackUnderflow,
    StackOverflow,
    ReturnStackOverflow,
    FloatStackUnderflow,
    FloatStackOverflow,
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
    InvalidAddress,
    PicturedNumericOverflow,
    MemoryExhausted,
    InputUnavailable,
    FileUnavailable,
    InvalidImage,
    Aborted,
    HostUnavailable,
    HostFailed,
    StringTooLong,
    /// A non-zero code passed to THROW; the code is kept in `State.throw_code`.
    Thrown,
    IncludeNesting,
    TooManySourceFiles,
    SearchOrderOverflow,
    SearchOrderUnderflow,
    InvalidWordlist,
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

fn floatBits(value: Float) Cell {
    return @bitCast(value);
}

fn bitsFloat(value: Cell) Float {
    return @bitCast(value);
}

const DoubleCells = struct { low: Cell, high: Cell };

fn doubleCells(value: Double) DoubleCells {
    const bits: UDouble = @bitCast(value);
    return .{ .low = @bitCast(@as(UCell, @truncate(bits))), .high = @bitCast(@as(UCell, @truncate(bits >> 64))) };
}

fn cellsDouble(low: Cell, high: Cell) Double {
    const bits = (@as(UDouble, @as(UCell, @bitCast(high))) << 64) | @as(UCell, @bitCast(low));
    return @bitCast(bits);
}

/// Decimal significand of a float, in the manner of Forth's REPRESENT.
const Representation = struct {
    digits: [dot_precision + 1]u8 = undefined,
    len: usize = 0,
    exponent: i32 = 0,
    negative: bool = false,
    finite: bool = true,
};

fn represent(value: Float, digit_count: usize) Representation {
    var result = Representation{ .len = digit_count, .negative = std.math.signbit(value) };
    if (std.math.isNan(value) or std.math.isInf(value)) {
        result.finite = false;
        return result;
    }
    var buffer: [64]u8 = undefined;
    const magnitude = @abs(value);
    const text = switch (digit_count) {
        fs_precision => std.fmt.bufPrint(&buffer, "{e:.13}", .{magnitude}),
        fs_precision + 1 => std.fmt.bufPrint(&buffer, "{e:.14}", .{magnitude}),
        dot_precision + 1 => std.fmt.bufPrint(&buffer, "{e:.15}", .{magnitude}),
        else => unreachable,
    } catch unreachable;
    var used: usize = 0;
    var cursor: usize = 0;
    while (cursor < text.len and text[cursor] != 'e') : (cursor += 1) {
        if (text[cursor] != '.') {
            result.digits[used] = text[cursor];
            used += 1;
        }
    }
    std.debug.assert(used == digit_count);
    const exponent = std.fmt.parseInt(i32, text[cursor + 1 ..], 10) catch unreachable;
    result.exponent = exponent + 1;
    return result;
}

/// Widest field F.RDP and its relatives format.
const max_rdp_width = 4096;

/// Decimal digits of round-half-even(|value| * 10^scale), computed exactly from the
/// binary value. std.fmt rounds the shortest decimal form instead, which differs from
/// gforth for values such as 2.675 or 0.95.
fn scaledDecimal(value: Float, scale: i32, output: []u8) RuntimeError![]const u8 {
    const magnitude = @abs(value);
    if (magnitude == 0) {
        output[0] = '0';
        return output[0..1];
    }
    const bits: u64 = @bitCast(magnitude);
    const exponent_field: i32 = @intCast(bits >> 52);
    const fraction = bits & ((@as(u64, 1) << 52) - 1);
    const mantissa = if (exponent_field == 0) fraction else fraction | (@as(u64, 1) << 52);
    const binary_exponent: i32 = (if (exponent_field == 0) -1074 else exponent_field - 1075);

    var scratch: [32768]u8 = undefined;
    var fixed = std.heap.FixedBufferAllocator.init(&scratch);
    const allocator = fixed.allocator();
    return scaledDecimalWith(allocator, mantissa, binary_exponent, scale, output) catch error.StringTooLong;
}

fn scaledDecimalWith(allocator: std.mem.Allocator, mantissa: u64, binary_exponent: i32, scale: i32, output: []u8) ![]const u8 {
    const Big = std.math.big.int.Managed;
    var numerator = try Big.initSet(allocator, mantissa);
    var denominator = try Big.initSet(allocator, 1);
    if (binary_exponent > 0) try numerator.shiftLeft(&numerator, @intCast(binary_exponent));
    if (binary_exponent < 0) try denominator.shiftLeft(&denominator, @intCast(-binary_exponent));
    var power = try Big.initSet(allocator, 10);
    try power.pow(&power, @intCast(@abs(scale)));
    if (scale > 0) try numerator.mul(&numerator, &power) else if (scale < 0) try denominator.mul(&denominator, &power);
    var quotient = try Big.init(allocator);
    var remainder = try Big.init(allocator);
    try quotient.divTrunc(&remainder, &numerator, &denominator);
    try remainder.shiftLeft(&remainder, 1);
    const half = remainder.order(denominator);
    if (half == .gt or (half == .eq and !quotient.isEven())) try quotient.addScalar(&quotient, 1);
    const text = try quotient.toString(allocator, 10, .lower);
    if (text.len > output.len) return error.NoSpaceLeft;
    @memcpy(output[0..text.len], text);
    return output[0..text.len];
}

/// `count` significant decimal digits of `magnitude`, rounded half to even, and the
/// exponent e with magnitude ~= 0.d1d2... * 10^e. Zero gives zeros with e = 1, so that
/// it has one integer digit. Beyond 800 digits a double has no more nonzero digits, so
/// the rest is padded with zeros.
const Represented = struct { digits: []const u8, exponent: i32 };

fn representDecimal(magnitude: Float, count: usize, buffer: *[max_rdp_width + 400]u8) RuntimeError!Represented {
    if (magnitude == 0) {
        @memset(buffer[0..count], '0');
        return .{ .digits = buffer[0..count], .exponent = 1 };
    }
    const exact: usize = @min(count, 800);
    const exact_i: i32 = @intCast(exact);
    var exponent: i32 = @as(i32, @intFromFloat(@floor(@log10(magnitude)))) + 1;
    var attempt: usize = 0;
    while (true) : (attempt += 1) {
        const scale = exact_i - exponent;
        const rounded = try scaledDecimal(magnitude, scale, buffer);
        exponent = @as(i32, @intCast(rounded.len)) - scale;
        // A wrong estimate or a carry (9.99 -> 10.0) changes the length; round again.
        if (rounded.len != exact and attempt < 3) continue;
        if (rounded.len < count) @memset(buffer[rounded.len..count], '0');
        return .{ .digits = buffer[0..count], .exponent = exponent };
    }
}

/// Whether F.RDP uses fixed-point notation for a value with decimal exponent
/// `exponent`, and how many significant digits that layout shows.
const RdpLayout = struct { fixed: bool, digits: i64 };

fn rdpLayout(exponent: i32, width: usize, fraction: usize, precision: i64, sign_width: usize) RdpLayout {
    const width_i: i64 = @intCast(width);
    const fraction_i: i64 = @intCast(fraction);
    const sign_i: i64 = @intCast(sign_width);
    const before_point = width_i - fraction_i - 1;
    const enough_precision = precision == 0 or fraction_i + exponent >= precision;
    if (before_point >= 0 and enough_precision and before_point - sign_i >= @max(exponent, 0))
        return .{ .fixed = true, .digits = std.math.clamp(exponent + fraction_i, 1, width_i) };
    return .{ .fixed = false, .digits = mantissaDigits(exponent, width, sign_width) };
}

/// Digits of an exponential-notation mantissa that fill `width`, counting the point
/// once there are at least one; 0 means a single digit and no point, and a negative
/// count means the field is too narrow.
fn mantissaDigits(exponent: i32, width: usize, sign_width: usize) i64 {
    var exponent_text: [16]u8 = undefined;
    const etext = std.fmt.bufPrint(&exponent_text, "{d}", .{exponent - 1}) catch unreachable;
    return @as(i64, @intCast(width)) - @as(i64, @intCast(etext.len)) - 2 - @as(i64, @intCast(sign_width));
}

/// F.RDP formatting of `value` into a field of `width` characters with `fraction`
/// digits after the point in fixed-point notation, which is used when it shows at least
/// `precision` significant digits and its integer part fits; otherwise exponential
/// notation (`1.23E5`), and asterisks when even that does not fit. The value is
/// rounded to the field width, the layout chosen, then rounded again to the digits
/// that layout shows and the layout chosen again, since rounding can change the
/// exponent (0.09999 -> 0.10, 9.999E-10 -> 1E-9). The rules follow gforth's
/// documentation and the outputs observed from gforth.
fn formatRdp(value: Float, width_cell: Cell, fraction_cell: Cell, precision_cell: Cell, output: *[max_rdp_width]u8) RuntimeError![]const u8 {
    if (width_cell > max_rdp_width) return error.StringTooLong;
    const width: usize = @intCast(@max(width_cell, 0));
    const fraction: usize = @intCast(std.math.clamp(fraction_cell, 0, max_rdp_width));
    const precision: i64 = @max(precision_cell, 0);
    const field = output[0..width];
    if (width == 0) return field;
    @memset(field, ' ');
    if (std.math.isNan(value) or std.math.isInf(value)) {
        const name: []const u8 = if (std.math.isNan(value)) "NaN" else if (value < 0) "-infinity" else "infinity";
        const shown = @min(name.len, width);
        @memcpy(field[0..shown], name[0..shown]);
        return field;
    }
    const negative = std.math.signbit(value);
    const sign_width: usize = @intFromBool(negative);
    const magnitude = @abs(value);
    var buffer: [max_rdp_width + 400]u8 = undefined;

    const first = try representDecimal(magnitude, width, &buffer);
    const first_layout = rdpLayout(first.exponent, width, fraction, precision, sign_width);
    const count: usize = @intCast(std.math.clamp(first_layout.digits, 1, @as(i64, @intCast(width))));
    const rep = try representDecimal(magnitude, count, &buffer);
    const layout = rdpLayout(rep.exponent, width, fraction, precision, sign_width);

    if (layout.fixed) {
        const fraction_i: i64 = @intCast(fraction);
        // When the first digit lies beyond the last place, gforth rounds up to one unit
        // only if twice the value exceeds that unit (so 0.0005 shows as 0.000).
        const tiny = magnitude != 0 and rep.exponent + fraction_i <= 0;
        const round_up = tiny and 2 * magnitude > std.math.pow(Float, 0.1, @floatFromInt(fraction));
        const room = width - fraction - 1;
        // The layout leaves room for the integer digits; a unit rounded up from a tiny
        // value is left out when it does not fit (0.7 in a field of 1 shows ".").
        const integer_len: usize = if (rep.exponent > 0) @intCast(rep.exponent) else @intFromBool(round_up and fraction == 0 and room > sign_width);
        var at = width - fraction;
        field[at - 1] = '.';
        var index: usize = 0;
        while (index < fraction) : (index += 1) {
            const place = rep.exponent + @as(i64, @intCast(index));
            field[at + index] = if (tiny)
                (if (round_up and index + 1 == fraction) '1' else '0')
            else if (place >= 0 and place < rep.digits.len) rep.digits[@intCast(place)] else '0';
        }
        at -= 1;
        if (integer_len > 0) {
            var digit: usize = 0;
            while (digit < integer_len) : (digit += 1)
                field[at - integer_len + digit] = if (tiny) '1' else if (digit < rep.digits.len) rep.digits[digit] else '0';
            at -= integer_len;
        } else if (room > sign_width) {
            at -= 1;
            field[at] = '0';
        }
        if (negative) field[at - 1] = '-';
        return field;
    }

    // Exponential notation: d.ddddEe filling the field exactly.
    const mantissa_len = mantissaDigits(rep.exponent, width, sign_width);
    if (mantissa_len < 0) {
        @memset(field, '*');
        return field;
    }
    var exponent_text: [16]u8 = undefined;
    const etext = std.fmt.bufPrint(&exponent_text, "{d}", .{rep.exponent - 1}) catch unreachable;
    var at: usize = 0;
    if (negative) {
        field[0] = '-';
        at = 1;
    }
    field[at] = rep.digits[0];
    at += 1;
    if (mantissa_len >= 1) {
        field[at] = '.';
        at += 1;
        const rest: usize = @intCast(mantissa_len - 1);
        var index: usize = 0;
        while (index < rest) : (index += 1) field[at + index] = if (index + 1 < rep.digits.len) rep.digits[index + 1] else '0';
        at += rest;
    }
    field[at] = 'E';
    @memcpy(field[at + 1 .. at + 1 + etext.len], etext);
    return field;
}

fn withoutTrailingZeros(digits: []const u8) []const u8 {
    var len = digits.len;
    while (len > 0 and digits[len - 1] == '0') len -= 1;
    return digits[0..len];
}

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

    pub fn imageCapacity() usize {
        return 20 + max_words * @sizeOf(Word) + max_code * @sizeOf(Op) + memory_size;
    }

    pub fn encodeImage(self: *State, output: []u8) RuntimeError!usize {
        const required = 20 + @as(usize, self.word_count) * @sizeOf(Word) + @as(usize, self.code_count) * @sizeOf(Op) + memory_size;
        if (output.len < required) return error.InvalidImage;
        @memcpy(output[0..8], image_magic);
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
        if (input.len < 20 or !std.mem.eql(u8, input[0..8], image_magic)) return error.InvalidImage;
        const word_count = readU32(input[8..12]);
        const code_count = readU32(input[12..16]);
        const data_here = readU32(input[16..20]);
        if (word_count < self.builtin_count or word_count > max_words or code_count > max_code or data_here < data_start or data_here > data_limit) return error.InvalidImage;
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
        self.data_here = data_here;
        self.data_depth = 0;
        self.return_depth = 0;
        self.float_depth = 0;
        self.control_depth = 0;
        self.loop_depth = 0;
        self.resetHold();
        self.setCompiling(false);
        self.defining = false;
        self.pending = .none;
    }

    pub fn appendImage(self: *State, source: *const State) RuntimeError!void {
        if (source.builtin_count != self.builtin_count or source.word_count < source.builtin_count) return error.InvalidImage;
        const added_words: usize = source.word_count - source.builtin_count;
        const word_base: usize = self.word_count;
        const code_base: usize = self.code_count;
        const code_count: usize = source.code_count;
        if (word_base + added_words > max_words) return error.DictionaryFull;
        if (code_base + code_count > max_code) return error.CodeFull;
        if (source.data_here < data_start) return error.InvalidImage;
        const data_len = source.data_here - data_start;
        if (self.data_here + data_len > data_limit) return error.MemoryExhausted;
        const data_delta = self.data_here - data_start;
        // User word lists of the loaded image get new ids after this dictionary's.
        const source_wordlists = std.math.clamp(source.readCellConst(wordlist_count_address), root_wordlist, max_wordlists);
        const wordlist_base = self.wordlistCount();
        if (wordlist_base + source_wordlists - root_wordlist > max_wordlists) return error.DictionaryFull;
        const mapWordlist = struct {
            fn map(wid: Cell, base: Cell) Cell {
                return if (wid <= root_wordlist) wid else base +% wid -% root_wordlist;
            }
        }.map;

        // Merge the loaded image's source files into this table, keeping their loaded
        // flags; a file that does not fit loses its location information (index 0).
        const loaded_before = self.loadedSourceFiles();
        var file_map: [max_source_files]u8 = @splat(0);
        const source_files: usize = @intCast(std.math.clamp(source.readCellConst(source_file_count_address), 0, max_source_files));
        for (0..source_files) |index| {
            const mapped = self.sourceFileEntryIndex(source.sourceFileName(index)) catch continue;
            file_map[index] = mapped + 1;
            if (source.sourceFileLoaded(index)) self.setSourceFileLoaded(mapped, true);
        }

        for (source.words[source.builtin_count..source.word_count], 0..) |original, offset| {
            var word = original;
            word.data_here_before += data_delta;
            if (word.source_file != 0) word.source_file = if (word.source_file <= source_files) file_map[word.source_file - 1] else 0;
            word.wordlist = @intCast(mapWordlist(word.wordlist, wordlist_base));
            if (word.kind == .vocabulary) word.value = mapWordlist(word.value, wordlist_base);
            if (word.kind == .colon) {
                word.code_start = @intCast(@as(usize, word.code_start) + code_base);
                word.code_end = @intCast(@as(usize, word.code_end) + code_base);
            }
            if (word.has_does) {
                word.does_code_start = @intCast(@as(usize, word.does_code_start) + code_base);
                word.does_code_end = @intCast(@as(usize, word.does_code_end) + code_base);
            }
            if (word.kind == .variable or word.kind == .array or word.kind == .created or word.kind == .value or word.kind == .two_constant or word.kind == .marker)
                word.value += data_delta;
            self.words[word_base + offset] = word;
        }

        for (source.code[0..source.code_count], 0..) |original, offset| {
            var op = original;
            switch (op.kind) {
                .call, .compile_call, .execution_token, .store_value, .local_frame => if (op.value >= source.builtin_count) {
                    op.value = @intCast(word_base + @as(usize, @intCast(op.value - source.builtin_count)));
                },
                .branch, .branch_zero, .do_loop, .q_do_loop, .loop, .plus_loop => {
                    op.value += @intCast(code_base);
                },
                .print_string, .string_literal => {
                    op.value += data_delta;
                },
                .builtin, .literal, .float_literal, .leave, .does, .exit, .local_store, .local_fetch, .local_address, .local_execute => {},
            }
            self.code[code_base + offset] = op;
        }
        const data_from: usize = @intCast(data_start);
        const data_to: usize = @intCast(self.data_here);
        const length: usize = @intCast(data_len);
        @memcpy(self.memory[data_to .. data_to + length], source.memory[data_from .. data_from + length]);
        // A loaded MARKER keeps this dictionary's REQUIRE history plus the files the saved
        // one had loaded, and its word lists are renumbered like the words.
        for (self.words[word_base .. word_base + added_words]) |word| {
            if (word.kind != .marker) continue;
            const saved: UCell = @bitCast(self.readCellConst(word.value));
            var mask = loaded_before;
            for (0..source_files) |index| {
                if (saved & (@as(UCell, 1) << @intCast(index)) != 0 and file_map[index] != 0) mask |= @as(UCell, 1) << @intCast(file_map[index] - 1);
            }
            try self.writeCell(word.value, @bitCast(mask));
            // Only the current list and the recorded order entries hold word-list ids.
            const current_at = word.value + cell_size;
            try self.writeCell(current_at, mapWordlist(try self.readCell(current_at), wordlist_base));
            const depth: usize = @intCast(std.math.clamp(try self.readCell(word.value + 2 * cell_size), 0, max_search_order));
            for (0..depth) |index| {
                const at = word.value + @as(Cell, @intCast(3 + index)) * cell_size;
                try self.writeCell(at, mapWordlist(try self.readCell(at), wordlist_base));
            }
        }
        try self.writeCell(wordlist_count_address, wordlist_base + source_wordlists - root_wordlist);
        self.word_count = @intCast(word_base + added_words);
        self.code_count = @intCast(code_base + code_count);
        self.data_here += data_len;
        self.last_created_word = null;
    }

    pub fn report(self: *State, err: anyerror) void {
        self.capture_target = null;
        self.local_count = 0;
        self.locals_top = locals_base;
        if (self.defining) {
            self.code_count = self.words[self.current_word].code_start;
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
        const message: []const u8 = if (err == error.StackUnderflow) "STACK UNDER FLOW !" else if (err == error.ReturnStackUnderflow) "RETURN STACK UNDER FLOW !" else if (err == error.StackOverflow) "STACK OVER FLOW !" else if (err == error.ReturnStackOverflow) "RETURN STACK OVER FLOW !" else if (err == error.FloatStackUnderflow) "FLOATING-POINT STACK UNDER FLOW !" else if (err == error.FloatStackOverflow) "FLOATING-POINT STACK OVER FLOW !" else if (err == error.DictionaryFull) "OUT OF DICTIONARY !" else if (err == error.CodeFull) "OUT OF CODE SPACE !" else if (err == error.InvalidDefinition) "DEFINITION ERROR !" else if (err == error.CommentUnclosed) "END OF COMMENT MUST BE \")\" !" else if (err == error.ControlMismatch) "CONTROL STRUCTURE ERROR !" else if (err == error.CompileOnly) "COMPILE MODE ERROR !" else if (err == error.UnknownWord) "?" else if (err == error.InvalidNumber) "NUMBER ERROR !" else if (err == error.DivisionByZero) "DIVISION BY ZERO !" else if (err == error.LoopMismatch) "LOOP ERROR !" else if (err == error.InvalidBase) "BASE ERROR !" else if (err == error.InvalidExecutionToken) "INVALID EXECUTION TOKEN !" else if (err == error.InvalidAddress) "INVALID MEMORY ADDRESS !" else if (err == error.PicturedNumericOverflow) "PICTURED NUMERIC OUTPUT ERROR !" else if (err == error.MemoryExhausted) "OUT OF MEMORY !" else if (err == error.InputUnavailable) "INPUT ERROR !" else if (err == error.FileUnavailable) "FILE ERROR !" else if (err == error.InvalidImage) "INVALID IMAGE !" else if (err == error.HostUnavailable) "HOST FUNCTION UNAVAILABLE !" else if (err == error.HostFailed) "HOST FUNCTION ERROR !" else if (err == error.StringTooLong) "STRING TOO LONG !" else if (err == error.IncludeNesting) "INCLUDE NESTING ERROR !" else if (err == error.TooManySourceFiles) "TOO MANY SOURCE FILES !" else if (err == error.SearchOrderOverflow) "SEARCH ORDER OVER FLOW !" else if (err == error.SearchOrderUnderflow) "SEARCH ORDER UNDER FLOW !" else if (err == error.InvalidWordlist) "INVALID WORDLIST !" else "FORTH ERROR !";
        self.write(message);
        self.write("\n");
    }

    /// Reports an uncaught THROW code. Standard codes reuse the interpreter's messages;
    /// I/O results (-512 minus errno) name the C error, as gforth does.
    fn writeThrowMessage(self: *State, code: Cell) void {
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
        var buffer: [48]u8 = undefined;
        self.write(std.fmt.bufPrint(&buffer, "ERROR #{d} !\n", .{code}) catch unreachable);
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
    fn interpretSource(self: *State, input: []const u8, source_kind: SourceKind) RuntimeError!void {
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
            .{ "INCLUDED?", .included_query }, .{ "SOURCEFILENAME", .source_file_name }, .{ "SOURCELINE#", .source_line_number }, .{ "MARKER", .marker }, .{ "LOCATE", .locate },
            .{ "ONLY", .only },              .{ "ALSO", .also },              .{ "PREVIOUS", .previous },     .{ "FORTH", .forth },              .{ "DEFINITIONS", .definitions },
            .{ "ORDER", .order },            .{ "GET-ORDER", .get_order },    .{ "SET-ORDER", .set_order },   .{ ">ORDER", .to_order },          .{ "GET-CURRENT", .get_current },
            .{ "SET-CURRENT", .set_current }, .{ "VOCABULARY", .vocabulary }, .{ "WORDLIST", .wordlist },    .{ "FORTH-WORDLIST", .forth_wordlist_word }, .{ "SEARCH-WORDLIST", .search_wordlist },
            .{ "[IF]", .bracket_if },        .{ "[ELSE]", .bracket_else },    .{ "[THEN]", .bracket_then },   .{ "[DEFINED]", .bracket_defined }, .{ "[UNDEFINED]", .bracket_undefined },
            .{ "F.RDP", .f_dot_rdp },        .{ "F>STR-RDP", .f_to_str_rdp }, .{ "F>BUF-RDP", .f_to_buf_rdp },
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
            .compile_if, .compile_else, .compile_then, .compile_begin, .compile_end, .compile_again, .compile_while, .compile_repeat, .compile_do, .compile_q_do, .compile_loop, .compile_plus_loop, .compile_does, .compile_case, .compile_of, .compile_endof, .compile_endcase, .compile_exit, .compile_recurse, .leave, .bracket_if, .bracket_else, .bracket_then, .bracket_defined, .bracket_undefined => true,
            else => false,
        };
    }

    fn addBuiltin(self: *State, name: []const u8, builtin: Builtin) RuntimeError!void {
        const id = try self.appendWord(name, .builtin, builtin, 0);
        self.words[id].immediate = isImmediateBuiltin(builtin);
    }

    fn appendWord(self: *State, name: []const u8, kind: WordKind, builtin: Builtin, value: Cell) RuntimeError!u16 {
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

    /// Finds a word through the search order, first-searched list first.
    fn lookup(self: *State, name: []const u8) ?u16 {
        var order: [max_search_order]Cell = undefined;
        const entries = self.searchOrder(&order);
        for (entries, 0..) |wid, index| {
            // A list that appears earlier in the order was already searched.
            if (std.mem.indexOfScalar(Cell, entries[0..index], wid) != null) continue;
            if (self.lookupIn(name, wid)) |id| return id;
        }
        return null;
    }

    /// Finds the newest word named `name` in one word list.
    fn lookupIn(self: *State, name: []const u8, wid: Cell) ?u16 {
        var i = self.word_count;
        while (i > 0) {
            i -= 1;
            const word = self.words[i];
            if (word.wordlist == wid and word.name_len != 0 and asciiEqlIgnoreCase(word.name[0..word.name_len], name)) return i;
        }
        return null;
    }

    fn wordlistCount(self: *State) Cell {
        return self.readCell(wordlist_count_address) catch unreachable;
    }

    fn validWordlist(self: *State, wid: Cell) RuntimeError!Cell {
        if (wid < forth_wordlist or wid > self.wordlistCount()) return error.InvalidWordlist;
        return wid;
    }

    fn currentWordlist(self: *State) Cell {
        return self.readCell(current_wordlist_address) catch unreachable;
    }

    fn searchOrderDepth(self: *State) usize {
        const depth = self.readCell(search_order_depth_address) catch unreachable;
        return @intCast(std.math.clamp(depth, 0, max_search_order));
    }

    fn searchOrderEntry(self: *State, index: usize) Cell {
        return self.readCell(search_order_address + @as(Cell, @intCast(index)) * cell_size) catch unreachable;
    }

    /// Sets the search order; `order[0]` is searched first.
    fn setSearchOrder(self: *State, order: []const Cell) void {
        for (order, 0..) |wid, index| self.writeCell(search_order_address + @as(Cell, @intCast(index)) * cell_size, wid) catch unreachable;
        self.writeCell(search_order_depth_address, @intCast(order.len)) catch unreachable;
    }

    fn searchOrder(self: *State, buffer: *[max_search_order]Cell) []Cell {
        const depth = self.searchOrderDepth();
        for (0..depth) |index| buffer[index] = self.searchOrderEntry(index);
        return buffer[0..depth];
    }

    /// Writes a word list's name for ORDER: Forth and Root, the name of a VOCABULARY,
    /// or of a constant holding the id (as gforth shows `WORDLIST CONSTANT X`), else the id.
    fn writeWordlistName(self: *State, wid: Cell) void {
        if (wid == forth_wordlist) return self.write("Forth");
        if (wid == root_wordlist) return self.write("Root");
        for ([_]WordKind{ .vocabulary, .constant }) |kind| {
            var i = self.word_count;
            while (i > self.builtin_count) {
                i -= 1;
                const word = &self.words[i];
                if (word.kind == kind and word.value == wid and word.name_len != 0) return self.write(word.name[0..word.name_len]);
            }
        }
        self.writeNumberDecimal(wid);
    }

    /// [IF] and [ELSE]: skips input words up to the matching [THEN], or to the matching
    /// [ELSE] when `to_else` is set, counting nested [IF]s. Skipping may read further lines.
    fn skipConditional(self: *State, to_else: bool) RuntimeError!void {
        var depth: usize = 0;
        while (true) {
            const token = (try self.nextSourceToken()) orelse return error.ControlMismatch;
            if (asciiEqlIgnoreCase(token, "[IF]")) {
                depth += 1;
            } else if (asciiEqlIgnoreCase(token, "[ELSE]")) {
                if (depth == 0 and to_else) return;
            } else if (asciiEqlIgnoreCase(token, "[THEN]")) {
                if (depth == 0) return;
                depth -= 1;
            }
        }
    }

    fn snapshotMarker(self: *State, address: Cell) RuntimeError!void {
        try self.writeCell(address, @bitCast(self.loadedSourceFiles()));
        try self.writeCell(address + cell_size, self.currentWordlist());
        const depth = self.searchOrderDepth();
        try self.writeCell(address + 2 * cell_size, @intCast(depth));
        // Unused slots are cleared, since the data area may hold old values.
        for (0..max_search_order) |index| try self.writeCell(address + @as(Cell, @intCast(3 + index)) * cell_size, if (index < depth) self.searchOrderEntry(index) else 0);
    }

    /// MARKER: restores the REQUIRE history, the current list, and the search order.
    fn restoreMarker(self: *State, address: Cell) RuntimeError!void {
        const mask: UCell = @bitCast(try self.readCell(address));
        const current = try self.readCell(address + cell_size);
        const depth: usize = @intCast(std.math.clamp(try self.readCell(address + 2 * cell_size), 0, max_search_order));
        var order: [max_search_order]Cell = undefined;
        for (0..depth) |index| order[index] = try self.readCell(address + @as(Cell, @intCast(3 + index)) * cell_size);
        self.restoreLoadedSourceFiles(mask);
        try self.writeCell(current_wordlist_address, current);
        self.setSearchOrder(order[0..depth]);
    }

    fn lookupOrFail(self: *State, name: []const u8) RuntimeError!u16 {
        return self.lookup(name) orelse {
            self.last_unknown_word = name;
            return error.UnknownWord;
        };
    }

    /// Allocates a data-area word that owns `size` bytes, rolling back on failure.
    fn appendDataWord(self: *State, name: []const u8, kind: WordKind, size: Cell) RuntimeError!u16 {
        const address = self.data_here;
        try self.reserveData(size);
        const id = self.appendWord(name, kind, .drop, address) catch |err| {
            self.data_here = address;
            return err;
        };
        self.words[id].data_here_before = address;
        return id;
    }

    fn finishPending(self: *State, token: []const u8) RuntimeError!void {
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
            },
            .fvariable_name => {
                const id = try self.appendDataWord(token, .variable, float_size);
                try self.writeFloat(self.words[id].value, 0);
            },
            .constant_name => {
                _ = try self.appendWord(token, .constant, .drop, self.pending_constant);
            },
            .fconstant_name => {
                _ = try self.appendWord(token, .fconstant, .drop, floatBits(self.pending_float));
            },
            .two_variable_name, .two_constant_name => {
                const id = try self.appendDataWord(token, if (pending == .two_constant_name) .two_constant else .variable, 2 * cell_size);
                try self.writeDouble(self.words[id].value, if (pending == .two_constant_name) self.pending_double else 0);
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
                if (self.words[id].kind != .value) return error.InvalidDefinition;
                if (self.compiling) {
                    _ = try self.emit(.{ .kind = .store_value, .value = id });
                } else try self.writeCell(self.words[id].value, try self.pop());
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

    /// Removes word `id` and every later word, reclaiming their code and data areas.
    fn forgetFrom(self: *State, id: u16) void {
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

    fn handleToken(self: *State, token: []const u8) RuntimeError!void {
        // Local variables shadow every dictionary word inside their definition.
        if (self.compiling) {
            if (self.findLocal(token)) |local| return self.compileLocalReference(local);
        }
        const found = self.lookup(token);
        if (found) |id| {
            if (id >= self.builtin_count) return self.handleWord(id);
        }
        if (std.mem.eql(u8, token, ":")) {
            if (self.defining) return error.InvalidDefinition;
            self.pending = .colon_name;
            return;
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
        if (std.mem.eql(u8, token, ";")) {
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
            return;
        }
        if (std.mem.eql(u8, token, "[")) {
            if (!self.defining or !self.compiling) return error.CompileOnly;
            self.setCompiling(false);
            return;
        }
        if (std.mem.eql(u8, token, "]")) {
            if (!self.defining or self.compiling) return error.CompileOnly;
            self.setCompiling(true);
            return;
        }
        if (std.mem.eql(u8, token, "'") or std.mem.eql(u8, token, "[']")) {
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
        if (asciiEqlIgnoreCase(token, "VARIABLE") or asciiEqlIgnoreCase(token, "VAR")) {
            return self.startInterpretPending(.variable_name);
        }
        if (asciiEqlIgnoreCase(token, "FVARIABLE")) {
            return self.startInterpretPending(.fvariable_name);
        }
        if (asciiEqlIgnoreCase(token, "CONSTANT") or asciiEqlIgnoreCase(token, "CONST")) {
            if (self.compiling) return error.CompileOnly;
            self.pending_constant = try self.pop();
            self.pending = .constant_name;
            return;
        }
        if (asciiEqlIgnoreCase(token, "VALUE")) {
            if (self.compiling) return error.CompileOnly;
            self.pending_constant = try self.pop();
            self.pending = .value_name;
            return;
        }
        if (asciiEqlIgnoreCase(token, "2VARIABLE")) {
            return self.startInterpretPending(.two_variable_name);
        }
        if (asciiEqlIgnoreCase(token, "2CONSTANT")) {
            if (self.compiling) return error.CompileOnly;
            self.pending_double = try self.popDouble();
            self.pending = .two_constant_name;
            return;
        }
        if (asciiEqlIgnoreCase(token, "FCONSTANT")) {
            if (self.compiling) return error.CompileOnly;
            self.pending_float = try self.fpop();
            self.pending = .fconstant_name;
            return;
        }
        if (asciiEqlIgnoreCase(token, "ARRAY") or asciiEqlIgnoreCase(token, "FARRAY")) {
            if (self.compiling) return error.CompileOnly;
            self.pending_array_size = try self.pop();
            self.pending = .array_name;
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

    fn beginDefinition(self: *State, id: u16) void {
        self.local_count = 0;
        self.locals_frame_size = 0;
        self.current_word = id;
        self.current_data_start = self.words[id].data_here_before;
        self.setCompiling(true);
        self.defining = true;
    }

    /// Changes the compiler state and mirrors it in the STATE cell, so a saved
    /// `STATE` address always reads the current value.
    fn setCompiling(self: *State, compiling: bool) void {
        self.compiling = compiling;
        self.writeCell(state_address, truth(compiling)) catch unreachable;
    }

    fn findLocal(self: *State, name: []const u8) ?Local {
        var index = self.local_count;
        while (index > 0) {
            index -= 1;
            const local = self.locals[index];
            if (asciiEqlIgnoreCase(local.name[0..local.name_len], name)) return local;
        }
        return null;
    }

    fn localOperand(local: Local) Cell {
        return @as(Cell, local.offset) | (@as(Cell, @intFromEnum(local.kind)) << 32);
    }

    fn compileLocalReference(self: *State, local: Local) RuntimeError!void {
        const kind: OpKind = if (local.variable) .local_address else if (local.kind == .xt) .local_execute else .local_fetch;
        _ = try self.emit(.{ .kind = kind, .value = localOperand(local) });
    }

    fn addLocal(self: *State, name: []const u8, kind: LocalKind, variable: bool) RuntimeError!Local {
        if (self.local_count == max_locals) return error.InvalidDefinition;
        if (name.len == 0 or name.len > max_name) return error.NameTooLong;
        const size: u16 = if (kind == .double) 2 * cell_size else cell_size;
        var local = Local{ .name_len = @intCast(name.len), .kind = kind, .variable = variable, .offset = self.locals_frame_size };
        @memcpy(local.name[0..name.len], name);
        self.locals[self.local_count] = local;
        self.local_count += 1;
        self.locals_frame_size += size;
        return local;
    }

    /// Emits the frame setup and the stores that take initial values off the stacks.
    /// `locals` is in the order the values are popped (top of stack first).
    fn compileLocalInitialization(self: *State, locals: []const Local) RuntimeError!void {
        _ = try self.emit(.{ .kind = .local_frame, .value = self.current_word });
        for (locals) |local| _ = try self.emit(.{ .kind = .local_store, .value = localOperand(local) });
    }

    /// gforth's `{ ... }` and the standard `{: ... :}`: typed names take their values from
    /// the stacks (the last name from the top), names after `|` start at zero, and
    /// everything after `--` is a comment.
    fn compileLocals(self: *State, closing: []const u8) RuntimeError!void {
        if (!self.compiling or !self.defining) return error.CompileOnly;
        var initialized: [max_locals]Local = undefined;
        var initialized_count: usize = 0;
        var uninitialized = false;
        var comment = false;
        const Flavor = struct { kind: LocalKind, variable: bool };
        var pending: ?Flavor = null;
        while (true) {
            const token = (try self.nextSourceToken()) orelse return error.InvalidDefinition;
            if (std.mem.eql(u8, token, closing)) break;
            if (comment) continue;
            if (std.mem.eql(u8, token, "--")) {
                comment = true;
                continue;
            }
            if (std.mem.eql(u8, token, "|")) {
                if (pending != null) return error.InvalidDefinition;
                uninitialized = true;
                continue;
            }
            const types = [_]struct { []const u8, LocalKind, bool }{
                .{ "W:", .cell, false }, .{ "W^", .cell, true },  .{ "D:", .double, false }, .{ "D^", .double, true },
                .{ "F:", .float, false }, .{ "F^", .float, true }, .{ "C:", .char, false },   .{ "C^", .char, true },
                .{ "XT:", .xt, false },  .{ "XT^", .xt, true },
            };
            const prefix = for (types) |entry| {
                if (asciiEqlIgnoreCase(token, entry[0])) break entry;
            } else null;
            if (prefix) |entry| {
                if (pending != null) return error.InvalidDefinition;
                pending = .{ .kind = entry[1], .variable = entry[2] };
                continue;
            }
            const flavor = pending orelse Flavor{ .kind = .cell, .variable = false };
            pending = null;
            const local = try self.addLocal(token, flavor.kind, flavor.variable);
            if (!uninitialized) {
                initialized[initialized_count] = local;
                initialized_count += 1;
            }
        }
        if (pending != null) return error.InvalidDefinition;
        std.mem.reverse(Local, initialized[0..initialized_count]);
        try self.compileLocalInitialization(initialized[0..initialized_count]);
    }

    /// The standard `LOCALS| a b |`: the first name takes the top of the stack.
    fn compileAnsLocals(self: *State) RuntimeError!void {
        if (!self.compiling or !self.defining) return error.CompileOnly;
        var names: [max_locals]Local = undefined;
        var count: usize = 0;
        while (true) {
            const token = (try self.nextSourceToken()) orelse return error.InvalidDefinition;
            if (std.mem.eql(u8, token, "|")) break;
            names[count] = try self.addLocal(token, .cell, false);
            count += 1;
        }
        try self.compileLocalInitialization(names[0..count]);
    }

    fn storeLocal(self: *State, address: Cell, kind: LocalKind) RuntimeError!void {
        switch (kind) {
            .cell, .xt => try self.writeCell(address, try self.pop()),
            .double => try self.writeDouble(address, try self.popDouble()),
            .float => try self.writeFloat(address, try self.fpop()),
            .char => self.memory[try self.memoryAddress(address, 1)] = @truncate(@as(UCell, @bitCast(try self.pop()))),
        }
    }

    fn fetchLocal(self: *State, address: Cell, kind: LocalKind) RuntimeError!void {
        switch (kind) {
            .cell, .xt => try self.push(try self.readCell(address)),
            .double => try self.pushDouble(try self.readDouble(address)),
            .float => try self.fpush(try self.readFloat(address)),
            .char => try self.push(self.memory[try self.memoryAddress(address, 1)]),
        }
    }

    fn startInterpretPending(self: *State, pending: Pending) RuntimeError!void {
        if (self.compiling) return error.CompileOnly;
        self.pending = pending;
    }

    fn handleWord(self: *State, id: u16) RuntimeError!void {
        if (self.compiling and !self.words[id].immediate) {
            _ = try self.emit(.{ .kind = .call, .value = id });
        } else {
            try self.executeWord(id);
        }
    }

    fn requireCompiling(self: *State) RuntimeError!void {
        if (!self.compiling) return error.CompileOnly;
    }

    fn pushControl(self: *State, kind: ControlKind, address: u16) RuntimeError!void {
        try self.requireCompiling();
        if (self.control_depth == max_controls) return error.ControlStackOverflow;
        self.control_stack[self.control_depth] = .{ .kind = kind, .address = address, .locals = @intCast(self.local_count) };
        self.control_depth += 1;
    }

    fn popControl(self: *State, expected: ControlKind) RuntimeError!Control {
        try self.requireCompiling();
        if (self.control_depth == 0) return error.ControlMismatch;
        self.control_depth -= 1;
        const item = self.control_stack[self.control_depth];
        if (item.kind != expected) {
            self.control_depth += 1;
            return error.ControlMismatch;
        }
        return item;
    }

    fn topControl(self: *State) ?ControlKind {
        if (self.control_depth == 0) return null;
        return self.control_stack[self.control_depth - 1].kind;
    }

    fn compileIf(self: *State) RuntimeError!void {
        try self.requireCompiling();
        const at = try self.emit(.{ .kind = .branch_zero });
        try self.pushControl(.if_branch, at);
    }

    fn compileElse(self: *State) RuntimeError!void {
        const old = try self.popControl(.if_branch);
        const at = try self.emit(.{ .kind = .branch });
        self.patch(old.address, self.code_count);
        // The ELSE part is reached without the locals declared in the IF part.
        self.local_count = old.locals;
        try self.pushControl(.else_branch, at);
    }

    fn compileThen(self: *State) RuntimeError!void {
        try self.requireCompiling();
        const kind = self.topControl() orelse return error.ControlMismatch;
        if (kind != .if_branch and kind != .else_branch) return error.ControlMismatch;
        self.control_depth -= 1;
        self.patch(self.control_stack[self.control_depth].address, self.code_count);
        // After THEN only the locals visible at the IF remain: the code can be reached
        // along a path that skipped the branch (gforth's rule).
        self.local_count = self.control_stack[self.control_depth].locals;
    }

    fn compileBegin(self: *State) RuntimeError!void {
        try self.pushControl(.begin_loop, self.code_count);
    }

    fn compileEnd(self: *State, unconditional: bool) RuntimeError!void {
        const begin = try self.popControl(.begin_loop);
        _ = try self.emit(.{ .kind = if (unconditional) .branch else .branch_zero, .value = begin.address });
    }

    fn compileWhile(self: *State) RuntimeError!void {
        try self.requireCompiling();
        if (self.topControl() != .begin_loop) return error.ControlMismatch;
        const begin = self.control_stack[self.control_depth - 1];
        const at = try self.emit(.{ .kind = .branch_zero });
        try self.pushControl(.while_branch, begin.address);
        self.control_stack[self.control_depth - 1].address = at;
    }

    fn compileRepeat(self: *State) RuntimeError!void {
        const wh = try self.popControl(.while_branch);
        if (self.topControl() != .begin_loop) return error.ControlMismatch;
        self.control_depth -= 1;
        _ = try self.emit(.{ .kind = .branch, .value = self.control_stack[self.control_depth].address });
        self.patch(wh.address, self.code_count);
        // The loop is left at WHILE, so the locals declared after it are not visible.
        self.local_count = wh.locals;
    }

    fn compileDo(self: *State, conditional: bool) RuntimeError!void {
        try self.requireCompiling();
        const at = try self.emit(.{ .kind = if (conditional) .q_do_loop else .do_loop });
        try self.pushControl(.do_loop, at);
    }

    fn compileLoop(self: *State, plus: bool) RuntimeError!void {
        const loop = try self.popControl(.do_loop);
        const body: u16 = loop.address + 1;
        _ = try self.emit(.{ .kind = if (plus) .plus_loop else .loop, .value = body });
        self.patch(loop.address, self.code_count);
        // DO always runs the body, so its locals stay visible, except those a LEAVE can
        // skip; ?DO may skip the whole body.
        if (self.code[loop.address].kind == .q_do_loop) {
            self.local_count = loop.locals;
        } else self.local_count = @min(self.local_count, loop.leave_locals);
    }

    fn compileLeave(self: *State) RuntimeError!void {
        try self.requireCompiling();
        var index = self.control_depth;
        while (index > 0) {
            index -= 1;
            const control = &self.control_stack[index];
            if (control.kind == .do_loop) {
                _ = try self.emit(.{ .kind = .leave });
                control.leave_locals = @min(control.leave_locals, @as(u16, @intCast(self.local_count)));
                return;
            }
        }
        return error.ControlMismatch;
    }

    fn compileDoes(self: *State) RuntimeError!void {
        if (!self.compiling or !self.defining) return error.CompileOnly;
        _ = try self.emit(.{ .kind = .does });
        // The DOES> part runs in its own invocation, so earlier locals are out of scope.
        self.local_count = 0;
    }

    fn compileCase(self: *State) RuntimeError!void {
        try self.pushControl(.case_start, 0);
    }

    fn compileOf(self: *State) RuntimeError!void {
        try self.requireCompiling();
        const kind = self.topControl() orelse return error.ControlMismatch;
        if (kind != .case_start and kind != .endof_branch) return error.ControlMismatch;
        _ = try self.emit(.{ .kind = .builtin, .value = @intFromEnum(Builtin.over) });
        _ = try self.emit(.{ .kind = .builtin, .value = @intFromEnum(Builtin.equal) });
        const at = try self.emit(.{ .kind = .branch_zero });
        _ = try self.emit(.{ .kind = .builtin, .value = @intFromEnum(Builtin.drop) });
        try self.pushControl(.of_branch, at);
    }

    fn compileEndof(self: *State) RuntimeError!void {
        const of = try self.popControl(.of_branch);
        const at = try self.emit(.{ .kind = .branch });
        self.patch(of.address, self.code_count);
        // The next OF test is reached without the locals declared in this OF branch.
        self.local_count = of.locals;
        try self.pushControl(.endof_branch, at);
    }

    fn compileEndcase(self: *State) RuntimeError!void {
        try self.requireCompiling();
        _ = try self.emit(.{ .kind = .builtin, .value = @intFromEnum(Builtin.drop) });
        while (true) {
            const kind = self.topControl() orelse return error.ControlMismatch;
            self.control_depth -= 1;
            switch (kind) {
                .case_start => {
                    self.local_count = self.control_stack[self.control_depth].locals;
                    return;
                },
                .endof_branch => self.patch(self.control_stack[self.control_depth].address, self.code_count),
                else => {
                    self.control_depth += 1;
                    return error.ControlMismatch;
                },
            }
        }
    }

    /// Reads the next token, refilling from the terminal or the file being included when
    /// the line is used up. An EVALUATE string never reads past its end.
    fn nextSourceToken(self: *State) RuntimeError!?[]const u8 {
        while (true) {
            if (nextToken(self.source_line, &self.source_cursor)) |token| return token;
            const line = switch (self.source_kind) {
                .evaluate => return null,
                .file => try self.readIncludeLine() orelse return null,
                .terminal => blk: {
                    const read_fn = self.writer.read_fn orelse return null;
                    const start: usize = @intCast(tib_address);
                    break :blk read_fn(self.writer.context, self.memory[start .. start + tib_size]) orelse return null;
                },
            };
            self.source_line = line;
            self.source_cursor = 0;
        }
    }

    fn storeSourceName(self: *State, address: Cell, name: []const u8) void {
        const start: usize = @intCast(address);
        @memcpy(self.memory[start .. start + name.len], name);
    }

    fn currentFileFrame(self: *State) ?IncludeFrame {
        if (self.source_kind != .file or self.include_depth == 0) return null;
        return self.include_stack[self.include_depth - 1];
    }

    fn sourceFileCount(self: *State) usize {
        const count = self.readCell(source_file_count_address) catch unreachable;
        return @intCast(std.math.clamp(count, 0, max_source_files));
    }

    fn setSourceFileCount(self: *State, count: usize) void {
        self.writeCell(source_file_count_address, @intCast(count)) catch unreachable;
    }

    fn sourceFileEntry(index: usize) usize {
        return @intCast(source_file_table + @as(Cell, @intCast(index * source_file_entry_size)));
    }

    fn sourceFileName(self: *const State, index: usize) []const u8 {
        const at = sourceFileEntry(index);
        return self.memory[at + 1 .. at + 1 + self.memory[at]];
    }

    fn sourceFileLoadedFlag(index: usize) usize {
        return @intCast(source_file_loaded_flags + @as(Cell, @intCast(index)));
    }

    fn sourceFileLoaded(self: *const State, index: usize) bool {
        return self.memory[sourceFileLoadedFlag(index)] != 0;
    }

    fn setSourceFileLoaded(self: *State, index: usize, loaded: bool) void {
        self.memory[sourceFileLoadedFlag(index)] = @intFromBool(loaded);
    }

    fn findSourceEntry(self: *State, name: []const u8) ?u8 {
        for (0..self.sourceFileCount()) |index| {
            if (std.mem.eql(u8, self.sourceFileName(index), name)) return @intCast(index);
        }
        return null;
    }

    /// The table entry of a file in the REQUIRE history, or null when it is not loaded.
    fn findSourceFile(self: *State, name: []const u8) ?u8 {
        const index = self.findSourceEntry(name) orelse return null;
        return if (self.sourceFileLoaded(index)) index else null;
    }

    /// The table entry for `name`, added when the name is new. Entries are never removed.
    fn sourceFileEntryIndex(self: *State, name: []const u8) RuntimeError!u8 {
        if (self.findSourceEntry(name)) |index| return index;
        if (name.len >= source_file_entry_size) return error.StringTooLong;
        const count = self.sourceFileCount();
        if (count == max_source_files) return error.TooManySourceFiles;
        const at = sourceFileEntry(count);
        self.memory[at] = @intCast(name.len);
        @memcpy(self.memory[at + 1 .. at + 1 + name.len], name);
        self.setSourceFileLoaded(count, false);
        self.setSourceFileCount(count + 1);
        return @intCast(count);
    }

    /// Records an included file in the REQUIRE history.
    fn recordSourceFile(self: *State, name: []const u8) RuntimeError!u8 {
        const index = try self.sourceFileEntryIndex(name);
        self.setSourceFileLoaded(index, true);
        return index;
    }

    /// The loaded flags as one bit per table entry, which a MARKER keeps in its value.
    fn loadedSourceFiles(self: *const State) UCell {
        var mask: UCell = 0;
        const count: usize = @intCast(std.math.clamp(self.readCellConst(source_file_count_address), 0, max_source_files));
        for (0..count) |index| {
            if (self.sourceFileLoaded(index)) mask |= @as(UCell, 1) << @intCast(index);
        }
        return mask;
    }

    /// MARKER: the REQUIRE history returns to what it was when the marker was made.
    fn restoreLoadedSourceFiles(self: *State, mask: UCell) void {
        for (0..self.sourceFileCount()) |index| self.setSourceFileLoaded(index, mask & (@as(UCell, 1) << @intCast(index)) != 0);
    }

    /// Reads the next physical line of the innermost included file into its line buffer,
    /// or returns null at the end of the file.
    fn readIncludeLine(self: *State) RuntimeError!?[]const u8 {
        const frame = &self.include_stack[self.include_depth - 1];
        const files = try self.fileOps();
        // One byte more than a line may hold shows whether the host stopped at a line end.
        var chunk: [tib_size + 1]u8 = undefined;
        const result = files.read_line(self.writer.context, frame.fileid, &chunk);
        if (result.ior != 0) return self.throwCode(result.ior);
        if (!result.found) return null;
        frame.line += 1;
        if (result.length > tib_size) return error.StringTooLong;
        const start: usize = @intCast(include_buffer_base + @as(Cell, @intCast((self.include_depth - 1) * tib_size)));
        @memcpy(self.memory[start .. start + result.length], chunk[0..result.length]);
        return self.memory[start .. start + result.length];
    }

    /// INCLUDED: interprets a source file line by line. The file is recorded in the
    /// REQUIRE history when it opens (as gforth does), closed on every exit path, and an
    /// error inside it is reported with the file name and line.
    fn includeFile(self: *State, name: []const u8) RuntimeError!void {
        if (self.include_depth == max_include_depth) return error.IncludeNesting;
        if (name.len >= source_file_entry_size) return error.StringTooLong;
        // The name may lie in a line buffer that the include overwrites.
        var name_copy: [source_file_entry_size - 1]u8 = undefined;
        @memcpy(name_copy[0..name.len], name);
        const file_name = name_copy[0..name.len];
        const files = try self.fileOps();
        const opened = files.open(self.writer.context, file_name, .read_only, false);
        if (opened.ior != 0) return self.throwCode(opened.ior);
        const fileid: Cell = @bitCast(opened.value);
        const file_index = self.recordSourceFile(file_name) catch |err| {
            _ = files.close(self.writer.context, fileid);
            return err;
        };
        self.include_stack[self.include_depth] = .{ .fileid = fileid, .file_index = file_index, .line = 0 };
        self.include_depth += 1;
        const result = self.interpretIncludedFile();
        const last_line = self.include_stack[self.include_depth - 1].line;
        self.include_depth -= 1;
        const closed = files.close(self.writer.context, fileid);
        try result;
        if (closed != 0) {
            // The file is out of the input stack now, so name it here.
            if (self.error_location == null) self.error_location = .{ .file_index = file_index, .line = last_line };
            return self.throwCode(closed);
        }
    }

    fn interpretIncludedFile(self: *State) RuntimeError!void {
        // The innermost file records where an error happened, before its frame goes away.
        errdefer if (self.error_location == null) {
            const frame = self.include_stack[self.include_depth - 1];
            self.error_location = .{ .file_index = frame.file_index, .line = frame.line };
        };
        const was_defining = self.defining;
        const word_before = self.current_word;
        const pending_before = self.pending;
        while (!self.halted) {
            const line = try self.readIncludeLine() orelse break;
            try self.interpretSource(line, .file);
        }
        if (self.halted) return;
        // A definition or parsing word started in this file must end in it. Comparing the
        // word also catches a file that ends the caller's definition and starts another.
        const started_here = self.defining and (!was_defining or self.current_word != word_before);
        if (started_here or (self.pending != .none and pending_before == .none)) return error.InvalidDefinition;
    }

    fn requireFile(self: *State, name: []const u8) RuntimeError!void {
        if (self.findSourceFile(name) == null) try self.includeFile(name);
    }

    /// LOCATE: prints where a word was defined and the lines of its definition.
    fn locateWord(self: *State, id: u16) RuntimeError!void {
        const word = self.words[id];
        if (word.source_file == 0 or word.source_file > self.sourceFileCount()) {
            self.write(word.name[0..word.name_len]);
            self.write(": NO FILE INFORMATION\n");
            return;
        }
        const name = self.sourceFileName(word.source_file - 1);
        var line_text: [24]u8 = undefined;
        self.write(name);
        self.write(std.fmt.bufPrint(&line_text, ":{d}\n", .{word.source_line}) catch unreachable);
        const files = try self.fileOps();
        const opened = files.open(self.writer.context, name, .read_only, false);
        if (opened.ior != 0) return;
        const fileid: Cell = @bitCast(opened.value);
        defer _ = files.close(self.writer.context, fileid);
        const last = @min(word.source_end_line, word.source_line + 19);
        var chunk: [tib_size + 1]u8 = undefined;
        var number: u32 = 0;
        while (number < last) {
            var result = files.read_line(self.writer.context, fileid, &chunk);
            if (result.ior != 0 or !result.found) return;
            // An over-long line comes in several pieces; count it as one physical line.
            const too_long = result.length > tib_size;
            while (result.length > tib_size) {
                result = files.read_line(self.writer.context, fileid, &chunk);
                if (result.ior != 0 or !result.found) return;
            }
            number += 1;
            if (too_long) continue;
            if (number >= word.source_line) {
                self.write(chunk[0..result.length]);
                self.write("\n");
            }
        }
    }

    /// Address in logical memory of the current input position.
    fn sourceAddress(self: *State) Cell {
        return @intCast(@intFromPtr(self.source_line.ptr) - @intFromPtr(&self.memory) + self.source_cursor);
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
            .value => try self.push(try self.readCell(word.value)),
            .fconstant => try self.fpush(bitsFloat(word.value)),
            .two_constant => try self.pushDouble(try self.readDouble(word.value)),
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

    fn wordId(self: *State, value: Cell) RuntimeError!u16 {
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

    fn executeBuiltin(self: *State, builtin: Builtin) RuntimeError!void {
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
                for (self.data_stack[0..self.data_depth]) |value| {
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
                for (self.float_stack[0..self.float_depth]) |value| {
                    self.writeFloatExponent(value, fs_precision);
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
                    .f_exp => @exp(a),
                    .f_ln => @log(a),
                    .f_sin => @sin(a),
                    .f_cos => @cos(a),
                    .f_tan => @tan(a),
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

    fn throwCode(self: *State, code: Cell) RuntimeError {
        self.throw_code = code;
        return error.Thrown;
    }

    fn throwIor(self: *State, errno: Cell) RuntimeError {
        return self.throwCode(errnoIor(errno));
    }

    /// Pops a byte count; negative counts are treated as 0 and huge ones as memory-sized.
    fn popLength(self: *State) RuntimeError!usize {
        const count = try self.pop();
        return if (count < 0) 0 else @intCast(@min(count, memory_size));
    }

    fn writeMemory(self: *State, address: Cell, length: usize) void {
        const start: usize = @intCast(address);
        self.write(self.memory[start .. start + length]);
    }

    fn copyMemory(self: *State, destination: Cell, source: Cell, length: usize) void {
        const to: usize = @intCast(destination);
        const from: usize = @intCast(source);
        if (to <= from) {
            std.mem.copyForwards(u8, self.memory[to .. to + length], self.memory[from .. from + length]);
        } else std.mem.copyBackwards(u8, self.memory[to .. to + length], self.memory[from .. from + length]);
    }

    // ALLOCATE heap: blocks laid out from `heap_base` to the top stored at
    // `heap_top_address`, each preceded by a size cell and a used cell.

    fn heapTop(self: *State) Cell {
        return self.readCell(heap_top_address) catch unreachable;
    }

    /// Reads a block size, rejecting headers that would leave the used heap.
    fn blockSize(self: *State, block: Cell) RuntimeError!Cell {
        const size = try self.readCell(block);
        if (size < 0 or @rem(size, cell_size) != 0 or size > self.heapTop() - block - heap_header) return error.InvalidAddress;
        return size;
    }

    fn blockUsed(self: *State, block: Cell) RuntimeError!bool {
        return try self.readCell(block + cell_size) != 0;
    }

    fn setBlock(self: *State, block: Cell, size: Cell, used: bool) void {
        self.writeCell(block, size) catch unreachable;
        self.writeCell(block + cell_size, @intFromBool(used)) catch unreachable;
    }

    /// Gives `block` exactly `need` bytes when the rest is large enough to form a free block.
    fn splitBlock(self: *State, block: Cell, size: Cell, need: Cell, used: bool) void {
        if (size - need < heap_header + cell_size) {
            self.setBlock(block, size, used);
            return;
        }
        self.setBlock(block, need, used);
        self.setBlock(block + heap_header + need, size - need - heap_header, false);
    }

    fn heapNeed(size: UCell) ?Cell {
        if (size > heap_end - heap_base - heap_header) return null;
        return @intCast((size + cell_size - 1) & ~@as(UCell, cell_size - 1));
    }

    fn heapAllocate(self: *State, size: UCell) RuntimeError!?Cell {
        const need = heapNeed(size) orelse return null;
        const top = self.heapTop();
        var block = heap_base;
        while (block < top) {
            const size_here = try self.blockSize(block);
            if (!try self.blockUsed(block) and size_here >= need) {
                self.splitBlock(block, size_here, need, true);
                return block + heap_header;
            }
            block += heap_header + size_here;
        }
        if (heap_end - top < heap_header + need) return null;
        self.setBlock(top, need, true);
        self.writeCell(heap_top_address, top + heap_header + need) catch unreachable;
        return top + heap_header;
    }

    /// Finds the used block whose payload starts at `address`.
    fn findBlock(self: *State, address: Cell) RuntimeError!?Cell {
        const top = self.heapTop();
        var block = heap_base;
        while (block < top and block + heap_header <= address) {
            const size = try self.blockSize(block);
            if (block + heap_header == address) return if (try self.blockUsed(block)) block else null;
            block += heap_header + size;
        }
        return null;
    }

    /// Merges neighbouring free blocks and gives a free last block back to the heap top.
    fn coalesceHeap(self: *State) RuntimeError!void {
        const top = self.heapTop();
        var block = heap_base;
        var last: ?Cell = null;
        while (block < top) {
            var size = try self.blockSize(block);
            if (!try self.blockUsed(block)) {
                var next = block + heap_header + size;
                while (next < top and !try self.blockUsed(next)) {
                    size += heap_header + try self.blockSize(next);
                    next = block + heap_header + size;
                }
                self.setBlock(block, size, false);
            }
            last = block;
            block += heap_header + size;
        }
        if (last) |block_at_end| {
            if (!try self.blockUsed(block_at_end)) self.writeCell(heap_top_address, block_at_end) catch unreachable;
        }
    }

    /// Frees an ALLOCATE address; 0 is accepted. Returns false for an unknown address.
    fn heapFree(self: *State, address: Cell) RuntimeError!bool {
        if (address == 0) return true;
        const block = try self.findBlock(address) orelse return false;
        self.setBlock(block, try self.blockSize(block), false);
        try self.coalesceHeap();
        return true;
    }

    fn heapResize(self: *State, address: Cell, size: UCell) RuntimeError!HeapResult {
        if (address == 0) return if (try self.heapAllocate(size)) |fresh| .{ .address = fresh } else .no_memory;
        const block = try self.findBlock(address) orelse return .bad_pointer;
        const need = heapNeed(size) orelse return .no_memory;
        const old_size = try self.blockSize(block);
        // Grow in place by absorbing following free blocks, or past the heap top.
        const top = self.heapTop();
        var available = old_size;
        var next = block + heap_header + available;
        while (available < need and next < top and !try self.blockUsed(next)) {
            available += heap_header + try self.blockSize(next);
            next = block + heap_header + available;
        }
        if (available >= need) {
            self.splitBlock(block, available, need, true);
            try self.coalesceHeap();
            return .{ .address = address };
        }
        if (next == top and heap_end - block - heap_header >= need) {
            self.setBlock(block, need, true);
            self.writeCell(heap_top_address, block + heap_header + need) catch unreachable;
            return .{ .address = address };
        }
        const moved = try self.heapAllocate(size) orelse return .no_memory;
        self.copyMemory(moved, address, @intCast(old_size));
        _ = try self.heapFree(address);
        return .{ .address = moved };
    }

    // Dynamic strings, as in gforth: a string variable holds 0 or the address of a heap
    // buffer that starts with the length cell followed by the characters.

    const StringRef = struct { address: Cell, length: usize };

    fn fetchString(self: *State, string_var: Cell) RuntimeError!StringRef {
        const buffer = try self.readCell(string_var);
        if (buffer == 0) return .{ .address = 0, .length = 0 };
        const length = try self.readCell(buffer);
        if (length < 0) return error.InvalidAddress;
        _ = try self.memoryAddress(buffer + cell_size, @intCast(length));
        return .{ .address = buffer + cell_size, .length = @intCast(length) };
    }

    /// Resizes the string buffer; new bytes are zero. Returns the (possibly moved) buffer.
    fn setStringLength(self: *State, string_var: Cell, length: usize) RuntimeError!Cell {
        const old_length = (try self.fetchString(string_var)).length;
        const buffer = switch (try self.heapResize(try self.readCell(string_var), cell_size + length)) {
            .address => |moved| moved,
            .no_memory => return self.throwIor(errno_no_memory),
            .bad_pointer => return self.throwIor(errno_invalid),
        };
        try self.writeCell(string_var, buffer);
        try self.writeCell(buffer, @intCast(length));
        if (length > old_length) {
            const start: usize = @intCast(buffer + cell_size);
            @memset(self.memory[start + old_length .. start + length], 0);
        }
        return buffer;
    }

    fn freeString(self: *State, string_var: Cell) RuntimeError!void {
        if (!try self.heapFree(try self.readCell(string_var))) return self.throwIor(errno_invalid);
        try self.writeCell(string_var, 0);
    }

    /// Inserts (or, for $OVER, overwrites) `length` bytes from `source` at `offset`.
    /// A source inside the same string is copied out first, since resizing may move it.
    fn insertString(self: *State, string_var: Cell, offset: usize, source: Cell, length: usize, overwrite: bool) RuntimeError!void {
        _ = try self.memoryAddress(source, length);
        const old = try self.fetchString(string_var);
        const inside = old.address != 0 and source + @as(Cell, @intCast(length)) > old.address - cell_size and source < old.address + @as(Cell, @intCast(old.length));
        var from = source;
        var detached: ?Cell = null;
        defer if (detached) |copy| {
            _ = self.heapFree(copy) catch {};
        };
        if (inside and length != 0) {
            const copy = try self.heapAllocate(length) orelse return self.throwIor(errno_no_memory);
            self.copyMemory(copy, source, length);
            detached = copy;
            from = copy;
        }
        const at = if (overwrite) offset else @min(offset, old.length);
        const new_length = if (overwrite) @max(old.length, at + length) else old.length + length;
        const buffer = try self.setStringLength(string_var, new_length);
        const text = buffer + cell_size;
        if (overwrite) {
            // $OVER past the end pads the gap with blanks, as gforth does.
            if (at > old.length) @memset(self.memory[@intCast(text + @as(Cell, @intCast(old.length)))..@intCast(text + @as(Cell, @intCast(at)))], ' ');
        } else {
            self.copyMemory(text + @as(Cell, @intCast(at + length)), text + @as(Cell, @intCast(at)), old.length - at);
        }
        self.copyMemory(text + @as(Cell, @intCast(at)), from, length);
    }

    /// Appends output bytes to a string (used while $TMP captures output).
    fn appendString(self: *State, string_var: Cell, bytes: []const u8) RuntimeError!void {
        const memory_start = @intFromPtr(&self.memory);
        const address = @intFromPtr(bytes.ptr);
        if (address >= memory_start and address < memory_start + memory_size) {
            const end = (try self.fetchString(string_var)).length;
            return self.insertString(string_var, end, @intCast(address - memory_start), bytes.len, false);
        }
        const end = (try self.fetchString(string_var)).length;
        const buffer = try self.setStringLength(string_var, end + bytes.len);
        const start: usize = @intCast(buffer + cell_size);
        @memcpy(self.memory[start + end .. start + end + bytes.len], bytes);
    }

    fn stringArrayCount(self: *State, array_var: Cell) RuntimeError!usize {
        return (try self.fetchString(array_var)).length / cell_size;
    }

    /// Address of element `index`, growing the array with empty strings as needed.
    fn stringArrayElement(self: *State, array_var: Cell, index: usize) RuntimeError!Cell {
        if (index >= (heap_end - heap_base) / cell_size) return self.throwIor(errno_no_memory);
        const needed = (index + 1) * cell_size;
        if ((try self.fetchString(array_var)).length < needed) _ = try self.setStringLength(array_var, needed);
        return (try self.fetchString(array_var)).address + @as(Cell, @intCast(index * cell_size));
    }

    /// Reads the file line by line into the string array, replacing its contents.
    fn slurpLines(self: *State, fileid: Cell, array_var: Cell) RuntimeError!void {
        const files = try self.fileOps();
        var chunk: [256]u8 = undefined;
        var count: usize = 0;
        while (true) {
            const element = try self.stringArrayElement(array_var, count);
            try self.freeString(element);
            var found = false;
            while (true) {
                const result = files.read_line(self.writer.context, fileid, &chunk);
                if (result.ior != 0) return self.throwCode(result.ior);
                if (!result.found) break;
                found = true;
                try self.appendString(element, chunk[0..result.length]);
                if (result.length < chunk.len) break;
            }
            if (!found) break;
            if ((try self.fetchString(element)).address == 0) try self.executeStringInit(element);
            count += 1;
        }
        const total = try self.stringArrayCount(array_var);
        for (count..total) |index| try self.freeString(try self.stringArrayElement(array_var, index));
        _ = try self.setStringLength(array_var, count * cell_size);
    }

    fn executeStringInit(self: *State, string_var: Cell) RuntimeError!void {
        try self.push(string_var);
        try self.executeBuiltin(.string_init);
    }

    const SeeRole = enum(u8) { plain, if_branch, else_branch, while_branch, repeat_branch, until_branch, again_branch };

    /// Writes the space-separated tokens of SEE, wrapping long bodies.
    const SeeOutput = struct {
        state: *State,
        column: usize = 0,

        fn token(self: *SeeOutput, width: usize) void {
            if (self.column != 0 and self.column + 1 + width > 72) {
                self.state.write("\n");
                self.column = 0;
            }
            if (self.column == 0) {
                self.state.write("  ");
                self.column = 2;
            } else {
                self.state.write(" ");
                self.column += 1;
            }
            self.column += width;
        }

        fn text(self: *SeeOutput, parts: []const []const u8) void {
            var width: usize = 0;
            for (parts) |part| width += part.len;
            self.token(width);
            for (parts) |part| self.state.write(part);
        }

        fn number(self: *SeeOutput, value: Double) void {
            self.token(self.state.numberWidth(value));
            self.state.writeNumber(value);
        }
    };

    /// SEE: shows how a word was defined. Colon definitions are decompiled from their
    /// operations; branches that form IF ELSE THEN, BEGIN UNTIL/AGAIN, or BEGIN WHILE
    /// REPEAT are shown as those words, and any other branch as BRANCH or ?BRANCH with
    /// its target offset.
    fn seeWord(self: *State, id: u16) RuntimeError!void {
        const word = self.words[id];
        const name = word.name[0..word.name_len];
        switch (word.kind) {
            .builtin => {
                self.write("BUILT-IN ");
                self.write(name);
            },
            .variable, .array => {
                self.write(if (word.kind == .array) "ARRAY " else "VARIABLE ");
                self.write(name);
            },
            .constant, .value => {
                self.writeNumber(if (word.kind == .value) try self.readCell(word.value) else word.value);
                self.write(if (word.kind == .value) " VALUE " else " CONSTANT ");
                self.write(name);
            },
            .fconstant => {
                self.writeFloatExponent(bitsFloat(word.value), fs_precision);
                self.write(" FCONSTANT ");
                self.write(name);
            },
            .two_constant => {
                self.writeNumber(try self.readDouble(word.value));
                self.write(". 2CONSTANT ");
                self.write(name);
            },
            .created => {
                self.write("CREATE ");
                self.write(name);
                if (word.has_does) {
                    self.write("\nDOES>");
                    try self.seeBody(word.does_code_start, word.does_code_end);
                }
            },
            .marker, .vocabulary => {
                self.write(if (word.kind == .marker) "MARKER " else "VOCABULARY ");
                self.write(name);
            },
            .colon => {
                if (name.len == 0) self.write(":NONAME") else {
                    self.write(": ");
                    self.write(name);
                }
                try self.seeBody(word.code_start, word.code_end);
            },
        }
        if (word.immediate) self.write(" IMMEDIATE");
        self.write("\n");
    }

    fn seeBody(self: *State, start: u16, end: u16) RuntimeError!void {
        var stop: usize = end;
        if (stop > start and self.code[stop - 1].kind == .exit) stop -= 1;
        var roles: [max_code]SeeRole = undefined;
        var thens: [max_code + 1]u16 = undefined;
        var begins: [max_code + 1]u16 = undefined;
        @memset(roles[start..stop], .plain);
        @memset(thens[start .. stop + 1], 0);
        @memset(begins[start .. stop + 1], 0);
        for (start..stop) |pc| {
            const op = self.code[pc];
            if (op.kind != .branch_zero) continue;
            const target: usize = @intCast(op.value);
            if (target < start or target > stop) continue;
            if (target <= pc) {
                roles[pc] = .until_branch;
                begins[target] += 1;
                continue;
            }
            const before = target - 1;
            if (before > pc and self.code[before].kind == .branch and roles[before] == .plain) {
                const other: usize = @intCast(self.code[before].value);
                if (other >= start and other <= pc) {
                    roles[pc] = .while_branch;
                    roles[before] = .repeat_branch;
                    begins[other] += 1;
                    continue;
                }
                if (other > before and other <= stop) {
                    roles[pc] = .if_branch;
                    roles[before] = .else_branch;
                    thens[other] += 1;
                    continue;
                }
            }
            roles[pc] = .if_branch;
            thens[target] += 1;
        }
        for (start..stop) |pc| {
            const op = self.code[pc];
            if (op.kind != .branch or roles[pc] != .plain) continue;
            const target: usize = @intCast(op.value);
            if (target >= start and target <= pc) {
                roles[pc] = .again_branch;
                begins[target] += 1;
            }
        }
        self.write("\n");
        var out = SeeOutput{ .state = self };
        var pc: usize = start;
        while (true) : (pc += 1) {
            for (0..thens[pc]) |_| out.text(&.{"THEN"});
            if (pc == stop) break;
            for (0..begins[pc]) |_| out.text(&.{"BEGIN"});
            try self.seeOperation(&out, pc, roles[pc], start);
        }
        if (out.column != 0) self.write("\n");
        self.write(";");
    }

    fn seeName(self: *State, id: Cell) []const u8 {
        if (id < 0 or id >= self.word_count) return "<INVALID>";
        const word = &self.words[@intCast(id)];
        return if (word.name_len == 0) "<NONAME>" else word.name[0..word.name_len];
    }

    fn seeOperation(self: *State, out: *SeeOutput, pc: usize, role: SeeRole, start: usize) RuntimeError!void {
        const op = self.code[pc];
        var offset_text: [24]u8 = undefined;
        switch (op.kind) {
            .call => out.text(&.{self.seeName(op.value)}),
            .compile_call => out.text(&.{ "POSTPONE ", self.seeName(op.value) }),
            .execution_token => out.text(&.{ "['] ", self.seeName(op.value) }),
            .store_value => out.text(&.{ "TO ", self.seeName(op.value) }),
            .builtin => {
                const builtin: Builtin = @enumFromInt(op.value);
                const name = for (self.words[0..self.builtin_count]) |*word| {
                    if (word.builtin == builtin) break word.name[0..word.name_len];
                } else "<BUILT-IN>";
                out.text(&.{name});
            },
            .literal => out.number(op.value),
            .float_literal => {
                // The width of a float is not measured, so a wrapped line may run a little long.
                out.token(1);
                self.writeFloatExponent(bitsFloat(op.value), fs_precision);
            },
            .branch, .branch_zero => switch (role) {
                .if_branch => out.text(&.{"IF"}),
                .else_branch => out.text(&.{"ELSE"}),
                .while_branch => out.text(&.{"WHILE"}),
                .repeat_branch => out.text(&.{"REPEAT"}),
                .until_branch => out.text(&.{"UNTIL"}),
                .again_branch => out.text(&.{"AGAIN"}),
                .plain => {
                    const relative: Cell = op.value - @as(Cell, @intCast(start));
                    const label = std.fmt.bufPrint(&offset_text, "{d}", .{relative}) catch unreachable;
                    out.text(&.{ if (op.kind == .branch) "BRANCH " else "?BRANCH ", label });
                },
            },
            .do_loop => out.text(&.{"DO"}),
            .q_do_loop => out.text(&.{"?DO"}),
            .loop => out.text(&.{"LOOP"}),
            .plus_loop => out.text(&.{"+LOOP"}),
            .leave => out.text(&.{"LEAVE"}),
            .print_string, .string_literal => {
                const at = try self.memoryAddress(op.value, 1);
                const length = self.memory[at];
                _ = try self.memoryAddress(op.value + 1, length);
                out.text(&.{ if (op.kind == .print_string) ".\" " else "S\" ", self.memory[at + 1 .. at + 1 + length], "\"" });
            },
            .does => out.text(&.{"DOES>"}),
            .exit => out.text(&.{"EXIT"}),
            .local_frame => {},
            .local_store, .local_fetch, .local_address, .local_execute => {
                const slot = std.fmt.bufPrint(&offset_text, "L#{d}", .{@divTrunc(op.value & 0xffff_ffff, cell_size)}) catch unreachable;
                const prefix: []const u8 = switch (op.kind) {
                    .local_store => "TO ",
                    .local_address => "ADDR ",
                    .local_execute => "EXECUTE ",
                    else => "",
                };
                out.text(&.{ prefix, slot });
            },
        }
    }

    /// The rest of the current input line, and whether it lies in logical memory.
    fn remainingSource(self: *State) []const u8 {
        return self.source_line[@min(self.source_cursor, self.source_line.len)..];
    }

    fn sourceInMemory(self: *State) bool {
        const start = @intFromPtr(&self.memory);
        const address = @intFromPtr(self.source_line.ptr);
        return self.source_line.len != 0 and address >= start and address < start + memory_size;
    }

    fn isDelimiter(byte: u8, delimiter: u8) bool {
        return if (delimiter == ' ') isSeparator(byte) else byte == delimiter;
    }

    /// WORD: skips leading delimiters, then returns the text up to the next delimiter
    /// and consumes that delimiter. A blank delimiter also matches tabs and line ends.
    fn parseWordText(self: *State, delimiter: u8) []const u8 {
        const rest = self.remainingSource();
        var index: usize = 0;
        while (index < rest.len and isDelimiter(rest[index], delimiter)) index += 1;
        const start = index;
        while (index < rest.len and !isDelimiter(rest[index], delimiter)) index += 1;
        const text = rest[start..index];
        if (index < rest.len) index += 1;
        self.source_cursor += index;
        return text;
    }

    fn validNameToken(self: *State, nt: Cell) RuntimeError!u16 {
        if (nt < 1 or nt > self.word_count) return error.InvalidExecutionToken;
        return @intCast(nt - 1);
    }

    fn throwCodeOf(self: *State, err: RuntimeError) Cell {
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
    fn restoreCatchFrame(self: *State, frame: CatchFrame) void {
        if (self.defining and !frame.defining) {
            self.code_count = self.words[self.current_word].code_start;
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

    fn fileOps(self: *State) RuntimeError!*const FileOps {
        return self.writer.file_ops orelse error.HostUnavailable;
    }

    fn resetHold(self: *State) void {
        self.hold_ptr = hold_top;
        self.hold_end = hold_top;
        self.hold_depth = 0;
    }

    fn holdBytes(self: *State, bytes: []const u8) RuntimeError!void {
        const length: Cell = @intCast(bytes.len);
        if (self.hold_ptr - hold_bottom < length) return error.PicturedNumericOverflow;
        self.hold_ptr -= length;
        const start: usize = @intCast(self.hold_ptr);
        @memcpy(self.memory[start .. start + bytes.len], bytes);
    }

    /// `#`: prepends the least-significant digit of `value` and returns the remaining quotient.
    fn holdDigit(self: *State, value: UDouble) RuntimeError!UDouble {
        const base: UDouble = @intCast(try self.validBase());
        const digit: u8 = @intCast(value % base);
        try self.holdBytes(&.{if (digit < 10) '0' + digit else 'A' + digit - 10});
        return value / base;
    }

    fn binary(self: *State, builtin: Builtin) RuntimeError!void {
        const b = try self.pop();
        const a = try self.pop();
        const result: Cell = switch (builtin) {
            .add => a +% b,
            .sub => a -% b,
            .mul => a *% b,
            .div => (try flooredDivision(a, b)).quotient,
            .mod => (try flooredDivision(a, b)).remainder,
            .max => @max(a, b),
            .min => @min(a, b),
            .equal => truth(a == b),
            .not_equal => truth(a != b),
            .less => truth(a < b),
            .greater => truth(a > b),
            .less_equal => truth(a <= b),
            .greater_equal => truth(a >= b),
            .bit_and => a & b,
            .bit_or => a | b,
            .bit_xor => a ^ b,
            .bit_nand => ~(a & b),
            .bit_nor => ~(a | b),
            .lshift, .rshift => blk: {
                const bits: UCell = @bitCast(a);
                if (b < 0 or b >= 64) break :blk 0;
                const amount: u6 = @intCast(b);
                break :blk @bitCast(if (builtin == .lshift) bits << amount else bits >> amount);
            },
            else => unreachable,
        };
        try self.push(result);
    }

    const Division = struct { quotient: Cell, remainder: Cell };

    fn flooredDivision(dividend: Cell, divisor: Cell) RuntimeError!Division {
        if (divisor == 0) return error.DivisionByZero;
        if (dividend == std.math.minInt(Cell) and divisor == -1) return .{ .quotient = dividend, .remainder = 0 };
        return .{ .quotient = @divFloor(dividend, divisor), .remainder = @mod(dividend, divisor) };
    }

    fn truth(value: bool) Cell {
        return if (value) true_flag else 0;
    }

    fn floatToCell(value: Float) Cell {
        if (std.math.isNan(value)) return 0;
        if (value >= 0x1p63) return std.math.maxInt(Cell);
        if (value < -0x1p63) return std.math.minInt(Cell);
        return @intFromFloat(value);
    }

    fn floatToDouble(value: Float) Double {
        if (std.math.isNan(value)) return 0;
        if (value >= 0x1p127) return std.math.maxInt(Double);
        if (value < -0x1p127) return std.math.minInt(Double);
        return @intFromFloat(value);
    }

    /// Pops a double-cell number; the high cell is on top of the stack.
    fn popDouble(self: *State) RuntimeError!Double {
        try self.requireDepth(2);
        const high = try self.pop();
        const low = try self.pop();
        return cellsDouble(low, high);
    }

    fn pushDouble(self: *State, value: Double) RuntimeError!void {
        const cells = doubleCells(value);
        try self.push(cells.low);
        try self.push(cells.high);
    }

    /// 2@ / 2! layout: the high cell at `address`, the low cell in the next cell.
    fn readDouble(self: *State, address: Cell) RuntimeError!Double {
        const high = try self.readCell(address);
        return cellsDouble(try self.readCell(address +% cell_size), high);
    }

    fn writeDouble(self: *State, address: Cell, value: Double) RuntimeError!void {
        _ = try self.memoryAddress(address, 2 * cell_size);
        const cells = doubleCells(value);
        try self.writeCell(address, cells.high);
        try self.writeCell(address + cell_size, cells.low);
    }

    fn requireDepth(self: *State, depth: usize) RuntimeError!void {
        if (self.data_depth < depth) return error.StackUnderflow;
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

    fn requireFloatDepth(self: *State, depth: usize) RuntimeError!void {
        if (self.float_depth < depth) return error.FloatStackUnderflow;
    }

    fn fpeek(self: *State, depth: usize) RuntimeError!Float {
        if (depth >= self.float_depth) return error.FloatStackUnderflow;
        return self.float_stack[self.float_depth - depth - 1];
    }

    fn fpop(self: *State) RuntimeError!Float {
        if (self.float_depth == 0) return error.FloatStackUnderflow;
        self.float_depth -= 1;
        return self.float_stack[self.float_depth];
    }

    fn fpush(self: *State, value: Float) RuntimeError!void {
        if (self.float_depth == max_float_stack) return error.FloatStackOverflow;
        self.float_stack[self.float_depth] = value;
        self.float_depth += 1;
    }

    fn loopFrame(self: *State, nesting: usize) RuntimeError!Loop {
        if (self.loop_depth < nesting) return error.LoopMismatch;
        return self.loop_stack[self.loop_depth - nesting];
    }

    /// Validates that `length` bytes starting at `address` lie inside logical memory.
    fn memoryAddress(self: *State, address: Cell, length: usize) RuntimeError!usize {
        _ = self;
        if (address < 0 or address > memory_size) return error.InvalidAddress;
        const start: usize = @intCast(address);
        if (length > memory_size - start) return error.InvalidAddress;
        return start;
    }

    /// Pops ( addr u ) and returns the addressed bytes.
    fn memoryRange(self: *State) RuntimeError![]u8 {
        const count = try self.pop();
        const address = try self.pop();
        const length: usize = if (count < 0) 0 else @intCast(@min(count, memory_size));
        const start = try self.memoryAddress(address, length);
        return self.memory[start .. start + length];
    }

    /// Pops ( index base ) and returns the address of the indexed cell.
    fn arrayAddress(self: *State) RuntimeError!Cell {
        const base = try self.pop();
        const index = try self.pop();
        return base +% (index *% cell_size);
    }

    /// Reads a cell at a fixed system address of another machine (always in memory).
    fn readCellConst(self: *const State, address: Cell) Cell {
        const start: usize = @intCast(address);
        return std.mem.readInt(Cell, self.memory[start..][0..cell_size], .little);
    }

    fn readCell(self: *State, address: Cell) RuntimeError!Cell {
        const start = try self.memoryAddress(address, cell_size);
        return std.mem.readInt(Cell, self.memory[start..][0..cell_size], .little);
    }

    fn writeCell(self: *State, address: Cell, value: Cell) RuntimeError!void {
        const start = try self.memoryAddress(address, cell_size);
        std.mem.writeInt(Cell, self.memory[start..][0..cell_size], value, .little);
    }

    fn readFloat(self: *State, address: Cell) RuntimeError!Float {
        return bitsFloat(try self.readCell(address));
    }

    fn writeFloat(self: *State, address: Cell, value: Float) RuntimeError!void {
        try self.writeCell(address, floatBits(value));
    }

    fn reserveData(self: *State, amount: Cell) RuntimeError!void {
        const next, const overflow = @addWithOverflow(self.data_here, amount);
        if (overflow != 0 or next < data_start or next > data_limit) return error.MemoryExhausted;
        self.data_here = next;
    }

    fn currentBase(self: *State) Cell {
        return self.readCell(base_address) catch unreachable;
    }

    fn readInputToken(self: *State, line: *[4096]u8) RuntimeError!?[]const u8 {
        const read_fn = self.writer.read_fn orelse return error.InputUnavailable;
        const input = read_fn(self.writer.context, line) orelse return error.InputUnavailable;
        var cursor: usize = 0;
        const token = nextToken(input, &cursor) orelse {
            self.write(" ?\n");
            return null;
        };
        if (nextToken(input, &cursor) != null) {
            self.write(" ?\n");
            return null;
        }
        return token;
    }

    fn validBase(self: *State) RuntimeError!Cell {
        const base = self.currentBase();
        if (base < 2 or base > 36) return error.InvalidBase;
        return base;
    }

    fn digitValue(c: u8) ?Cell {
        return if (c >= '0' and c <= '9') c - '0' else if (c >= 'A' and c <= 'Z') c - 'A' + 10 else if (c >= 'a' and c <= 'z') c - 'a' + 10 else null;
    }

    /// Recognizes an integer in the manner of gforth's number recognizer: optional `-`, an
    /// optional base prefix (`$` `#` `&` `%`), digits, and `'c'` character literals. A `.`
    /// anywhere among the digits makes the number double-cell (`123.` and `12.34` are doubles).
    fn parseNumber(self: *State, token: []const u8) RuntimeError!?ParsedNumber {
        if (token.len == 3 and token[0] == '\'' and token[2] == '\'') return .{ .value = token[1], .double = false };
        var base = try self.validBase();
        var i: usize = 0;
        var negative = false;
        if (i < token.len and token[i] == '-') {
            negative = true;
            i += 1;
        }
        if (i < token.len) {
            const prefixed_base: ?Cell = switch (token[i]) {
                '$' => 16,
                '#', '&' => 10,
                '%' => 2,
                else => null,
            };
            if (prefixed_base) |prefixed| {
                base = prefixed;
                i += 1;
            }
        }
        if (!negative and i < token.len and token[i] == '-') {
            negative = true;
            i += 1;
        }
        var value: UDouble = 0;
        var digits: usize = 0;
        var double = false;
        while (i < token.len) : (i += 1) {
            if (token[i] == '.') {
                double = true;
                continue;
            }
            const digit = digitValue(token[i]) orelse return null;
            if (digit >= base) return null;
            value = value *% @as(UDouble, @intCast(base)) +% @as(UDouble, @intCast(digit));
            digits += 1;
        }
        if (digits == 0) return null;
        const signed: Double = @bitCast(value);
        const result = if (negative) 0 -% signed else signed;
        // A single-cell number wraps to 64 bits, as gforth's >NUMBER does with the high cell dropped.
        return .{ .value = if (double) result else doubleCells(result).low, .double = double };
    }

    /// Recognizes a decimal float. Source literals require an exponent marker (`1E`, `1.5e-3`);
    /// FINPUT and >FLOAT also accept plain decimal numbers.
    fn parseFloat(token: []const u8, require_exponent: bool) ?Float {
        var normalized: [80]u8 = undefined;
        var used: usize = 0;
        var i: usize = 0;
        if (i < token.len and (token[i] == '-' or token[i] == '+')) {
            normalized[used] = token[i];
            used += 1;
            i += 1;
        }
        const integer_start = i;
        while (i < token.len and std.ascii.isDigit(token[i])) i += 1;
        const integer_digits = token[integer_start..i];
        var fraction_digits: []const u8 = &.{};
        if (i < token.len and token[i] == '.') {
            i += 1;
            const fraction_start = i;
            while (i < token.len and std.ascii.isDigit(token[i])) i += 1;
            fraction_digits = token[fraction_start..i];
        }
        if (integer_digits.len + fraction_digits.len == 0) return null;
        var exponent_sign: []const u8 = "";
        var exponent_digits: []const u8 = "0";
        if (i < token.len and (token[i] == 'e' or token[i] == 'E')) {
            i += 1;
            if (i < token.len and (token[i] == '-' or token[i] == '+')) {
                exponent_sign = token[i .. i + 1];
                i += 1;
            }
            const exponent_start = i;
            while (i < token.len and std.ascii.isDigit(token[i])) i += 1;
            if (i > exponent_start) exponent_digits = token[exponent_start..i];
        } else if (require_exponent) return null;
        if (i != token.len) return null;
        const parts = [_][]const u8{ if (integer_digits.len == 0) "0" else integer_digits, ".", if (fraction_digits.len == 0) "0" else fraction_digits, "e", exponent_sign, exponent_digits };
        for (parts) |part| {
            if (used + part.len > normalized.len) return null;
            @memcpy(normalized[used .. used + part.len], part);
            used += part.len;
        }
        return std.fmt.parseFloat(Float, normalized[0..used]) catch null;
    }

    fn writeDepth(self: *State, depth: usize) void {
        self.write("<");
        self.writeNumber(depth);
        self.write("> ");
    }

    /// Writes a signed number in the current base; callers widen unsigned cells before passing them.
    fn writeNumber(self: *State, value: Double) void {
        const base = self.currentBase();
        if (base < 2 or base > 36) {
            self.write("?BASE?");
            return;
        }
        const radix: UDouble = @intCast(base);
        const negative = value < 0;
        var n: UDouble = @bitCast(value);
        if (negative) n = 0 -% n;
        var digits: [128]u8 = undefined;
        var length: usize = 0;
        while (true) {
            const digit: u8 = @intCast(n % radix);
            digits[length] = if (digit < 10) '0' + digit else 'A' + digit - 10;
            length += 1;
            n /= radix;
            if (n == 0) break;
        }
        if (negative) self.write("-");
        while (length > 0) {
            length -= 1;
            self.write(digits[length .. length + 1]);
        }
    }

    /// Number of characters `writeNumber` prints for `value`.
    fn numberWidth(self: *State, value: Double) usize {
        const base = self.currentBase();
        if (base < 2 or base > 36) return 6;
        var n: UDouble = @bitCast(value);
        if (value < 0) n = 0 -% n;
        var width: usize = if (value < 0) 1 else 0;
        while (true) {
            width += 1;
            n /= @intCast(base);
            if (n == 0) break;
        }
        return width;
    }

    fn writeZeros(self: *State, count: i64) void {
        var remaining = count;
        while (remaining > 0) : (remaining -= 1) self.write("0");
    }

    /// F. output: significand rounded to 15 digits, printed without an exponent.
    fn writeFloatFixed(self: *State, value: Float) void {
        const rep = represent(value, dot_precision);
        if (!rep.finite) return self.writeNonFinite(value, "infinity");
        if (rep.negative) self.write("-");
        const exponent: i64 = rep.exponent;
        const digits = rep.digits[0..rep.len];
        if (exponent <= 0) {
            self.write("0");
        } else {
            self.write(digits[0..@intCast(@min(exponent, dot_precision))]);
            self.writeZeros(exponent - dot_precision);
        }
        self.write(".");
        self.writeZeros(-exponent);
        const fraction_start: usize = @intCast(std.math.clamp(exponent, 0, dot_precision));
        self.write(withoutTrailingZeros(digits[fraction_start..]));
    }

    /// F.S item output: up to `precision` significant digits with an `e` marker.
    fn writeFloatExponent(self: *State, value: Float, precision: usize) void {
        if (std.math.isNan(value) or std.math.isInf(value)) return self.writeNonFinite(value, "inf");
        var digit_count = precision;
        const magnitude = @abs(value);
        const lower = std.math.pow(Float, 10, @floatFromInt(precision));
        if (magnitude >= lower and magnitude < lower * 10) digit_count += 1;
        const rep = represent(value, digit_count);
        if (rep.negative) self.write("-");
        const digits = withoutTrailingZeros(rep.digits[0..rep.len]);
        const exponent: i64 = rep.exponent;
        if (exponent >= 0 and exponent <= @as(i64, @intCast(digit_count))) {
            const point: usize = @intCast(exponent);
            if (point < digits.len) {
                self.write(digits[0..point]);
                self.write(".");
                self.write(digits[point..]);
            } else {
                self.write(digits);
                self.writeZeros(exponent - @as(i64, @intCast(digits.len)));
            }
            self.write("e");
        } else if (exponent < 0 and exponent > -5) {
            self.write(".");
            self.writeZeros(-exponent);
            self.write(digits);
            self.write("e");
        } else {
            self.write(digits[0..1]);
            if (digits.len > 1) {
                self.write(".");
                self.write(digits[1..]);
            }
            self.write("e");
            self.writeNumberDecimal(exponent - 1);
        }
    }

    fn writeNonFinite(self: *State, value: Float, infinity: []const u8) void {
        if (std.math.isNan(value)) return self.write("NaN");
        if (std.math.signbit(value)) self.write("-");
        self.write(infinity);
    }

    fn writeNumberDecimal(self: *State, value: i64) void {
        var buffer: [24]u8 = undefined;
        self.write(std.fmt.bufPrint(&buffer, "{d}", .{value}) catch unreachable);
    }

    /// `token` is `"` or a token starting with `."`; text glued to `."` belongs to the string.
    fn handleStringToken(self: *State, token: []const u8, input: []const u8, cursor: *usize, immediate: bool) RuntimeError!void {
        var literal: [127]u8 = undefined;
        var length: usize = 0;
        const inline_prefix: []const u8 = if (immediate) token[2..] else &.{};
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
            // A separator after the glued text is part of the string; the one after a bare
            // token was already consumed by nextToken.
            if (inline_prefix.len > 0 and cursor.* > 0 and isSeparator(input[cursor.* - 1])) {
                if (length == literal.len) return error.MemoryExhausted;
                literal[length] = input[cursor.* - 1];
                length += 1;
            }
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
            const start: usize = @intCast(address);
            self.memory[start] = @intCast(bytes.len);
            @memcpy(self.memory[start + 1 .. start + 1 + bytes.len], bytes);
            _ = try self.emit(.{ .kind = if (immediate) .print_string else .string_literal, .value = address });
        } else self.write(bytes);
    }

    /// Handles the gforth string words `S"`, `S\"`, `.\"`, and `.(`.
    fn handleParsedString(self: *State, kind: StringWord, input: []const u8, cursor: *usize) RuntimeError!void {
        var text: [max_gforth_string]u8 = undefined;
        const escapes = kind == .s_escape_quote or kind == .print_escape;
        const bytes = try parseDelimited(input, cursor, if (kind == .print_paren) ')' else '"', escapes, &text);
        switch (kind) {
            .print_paren => self.write(bytes),
            .print_escape => {
                if (self.compiling) try self.compileCountedString(bytes, .print_string) else self.write(bytes);
            },
            .s_quote, .s_escape_quote => {
                if (self.compiling) return self.compileCountedString(bytes, .string_literal);
                const slot = string_buffer_base + @as(Cell, @intCast(self.string_buffer_index * string_buffer_size));
                self.string_buffer_index = (self.string_buffer_index + 1) % string_buffer_count;
                const start: usize = @intCast(slot);
                @memcpy(self.memory[start .. start + bytes.len], bytes);
                try self.push(slot);
                try self.push(@intCast(bytes.len));
            },
        }
    }

    fn compileCountedString(self: *State, bytes: []const u8, kind: OpKind) RuntimeError!void {
        const address = self.data_here;
        try self.reserveData(@intCast(bytes.len + 1));
        const start: usize = @intCast(address);
        self.memory[start] = @intCast(bytes.len);
        @memcpy(self.memory[start + 1 .. start + 1 + bytes.len], bytes);
        _ = try self.emit(.{ .kind = kind, .value = address });
    }

    /// Reads text after a parsing word up to `delimiter`. The separator after the parsing
    /// word itself was consumed with the word.
    fn parseDelimited(input: []const u8, cursor: *usize, delimiter: u8, escapes: bool, output: []u8) RuntimeError![]const u8 {
        var length: usize = 0;
        while (true) {
            if (cursor.* == input.len) return error.InvalidDefinition;
            var c = input[cursor.*];
            cursor.* += 1;
            if (c == delimiter) break;
            if (escapes and c == '\\') {
                if (cursor.* == input.len) return error.InvalidDefinition;
                const code = input[cursor.*];
                cursor.* += 1;
                c = switch (code) {
                    'a' => 7,
                    'b' => 8,
                    'e' => 27,
                    'f' => 12,
                    'l', 'n' => '\n',
                    'q' => '"',
                    'r' => '\r',
                    't' => '\t',
                    'v' => 11,
                    'z' => 0,
                    'm' => blk: {
                        if (length == output.len) return error.MemoryExhausted;
                        output[length] = '\r';
                        length += 1;
                        break :blk '\n';
                    },
                    'x' => blk: {
                        if (input.len - cursor.* < 2) return error.InvalidDefinition;
                        const value = std.fmt.parseInt(u8, input[cursor.* .. cursor.* + 2], 16) catch return error.InvalidDefinition;
                        cursor.* += 2;
                        break :blk value;
                    },
                    else => code,
                };
            }
            if (length == output.len) return error.MemoryExhausted;
            output[length] = c;
            length += 1;
        }
        return output[0..length];
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

    /// Token delimiters. Tabs separate tokens as in gforth, so tab-indented sources work.
    fn isSeparator(byte: u8) bool {
        return byte == ' ' or byte == '\t' or byte == '\r' or byte == '\n';
    }

    /// Reads the next blank-delimited token and, as gforth does, consumes the one separator
    /// that ends it, so PARSE starts right after that separator.
    fn nextToken(input: []const u8, cursor: *usize) ?[]const u8 {
        while (cursor.* < input.len and isSeparator(input[cursor.*])) cursor.* += 1;
        if (cursor.* == input.len) return null;
        const start = cursor.*;
        while (cursor.* < input.len and !isSeparator(input[cursor.*])) cursor.* += 1;
        const token = input[start..cursor.*];
        if (cursor.* < input.len) cursor.* += 1;
        return token;
    }
};
