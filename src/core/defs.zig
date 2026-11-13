//! Types shared by the core: built-in word ids, dictionary entries, operations, and errors.

const std = @import("std");
const memory_map = @import("memory_map.zig");
const Cell = memory_map.Cell;
const Double = memory_map.Double;
const Float = memory_map.Float;
const UCell = memory_map.UCell;
const UDouble = memory_map.UDouble;
const forth_wordlist = memory_map.forth_wordlist;
const max_name = memory_map.max_name;

const build_options = @import("build_options");

/// False in a build with -Dfloat=false, which leaves out the floating-point words.
pub const float_enabled = build_options.float;
/// False with -Dfiles=false, which leaves out the words that open, read, write, or include
/// files (also the $...SLURP words, which read a file or a file id).
pub const files_enabled = build_options.files;
/// False with -Dhelp=false, which leaves out HELP, LICENSE, and their texts.
pub const help_enabled = build_options.help;
/// False with -Dtools=false, which leaves out SEE, LOCATE, and WHERE.
pub const tools_enabled = build_options.tools;
/// False with -Ddebug=false, which leaves out the debugging features: the backtrace after
/// an error (and the lines of the code, which it shows), the step limit (--max-steps),
/// the trace (--trace), and the words of words_debug.zig.
pub const debug_enabled = build_options.debug;
/// False with -Dimage=false, which leaves out SAVE, LOAD-DICTIONARY, and SAVESYS.
pub const image_enabled = build_options.image;
/// False with -Dgraphics=false, which leaves out REQUIRE-GRAPHICS and the GFX- words.
pub const graphics_enabled = build_options.graphics;
/// False with -Daudio=false, which leaves out REQUIRE-AUDIO and the SND- words.
pub const audio_enabled = build_options.audio;

/// The built-in words of the floating-point word set: those of words_float.zig and the
/// float fields, sizes, and defining words of the other files.
pub fn isFloatBuiltin(builtin: Builtin) bool {
    return float_builtins[@intFromEnum(builtin)];
}

/// A built-in word of a group this build leaves out. Such a word is not in the dictionary
/// and its code is not compiled in.
pub fn isExcludedBuiltin(builtin: Builtin) bool {
    return excluded_builtins[@intFromEnum(builtin)];
}

const builtin_count = @typeInfo(Builtin).@"enum".field_names.len;

fn builtinSet(comptime lists: []const []const Builtin) [builtin_count]bool {
    var table: [builtin_count]bool = @splat(false);
    for (lists) |list| {
        for (list) |word| table[@intFromEnum(word)] = true;
    }
    return table;
}

const float_builtins = builtinSet(&.{ &@import("words_float.zig").words, &.{ .field_float, .field_sfloat, .field_dfloat, .float_percent, .sfloat_percent, .dfloat_percent, .define_fvariable, .define_fconstant, .define_fvalue, .fliteral } });
const file_builtins = builtinSet(&.{ &@import("words_files.zig").words, &@import("blocks.zig").words, &.{ .string_slurp, .string_plus_slurp, .string_slurp_file, .string_plus_slurp_file, .string_slurp_line, .string_array_slurp, .string_array_slurp_file } });
const help_builtins = builtinSet(&.{&.{ .help, .license }});
const tool_builtins = builtinSet(&.{&.{ .see, .locate, .where }});
const image_builtins = builtinSet(&.{&.{ .load, .save, .savesys }});
const graphics_builtins = builtinSet(&.{&@import("words_graphics.zig").words});
const audio_builtins = builtinSet(&.{&@import("words_audio.zig").words});
const debug_builtins = builtinSet(&.{&@import("words_debug.zig").words});

const excluded_builtins = blk: {
    var table: [builtin_count]bool = undefined;
    for (&table, 0..) |*excluded, index| {
        excluded.* = (!float_enabled and float_builtins[index]) or (!files_enabled and file_builtins[index]) or
            (!help_enabled and help_builtins[index]) or (!tools_enabled and tool_builtins[index]) or
            (!image_enabled and image_builtins[index]) or (!graphics_enabled and graphics_builtins[index]) or
            (!audio_enabled and audio_builtins[index]) or (!debug_enabled and debug_builtins[index]);
    }
    break :blk table;
};

pub const Builtin = enum {
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
    compare,
    search,
    slash_string,
    minus_trailing,
    char_plus,
    chars,
    bounds,
    blank_fill,
    cmove_up,
    scan,
    skip,
    str_equal,
    string_prefix_query,
    plus_place,
    align_here,
    unused,
    dump,
    time_and_date,
    synonym,
    traverse_wordlist,
    cs_pick,
    cs_roll,
    ekey_to_char,
    ekey_to_fkey,
    ekey_question,
    ekey,
    environment_query,
    quit,
    dot,
    u_dot,
    c_dot,
    dot_r,
    u_dot_r,
    d_dot_r,
    at_xy,
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
    compile_ahead,
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
    d_two_star,
    d_two_slash,
    d_max,
    d_min,
    m_plus,
    du_less,
    m_star_slash,
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
    u_less,
    u_greater,
    star_slash,
    star_slash_mod,
    m_star,
    um_star,
    um_slash_mod,
    fm_slash_mod,
    sm_slash_rem,
    two_to_r,
    two_r_from,
    two_r_fetch,
    two_rot,
    n_to_r,
    n_r_from,
    question_dup,
    place,
    abort,
    ms,
    utime,
    page,
    getenv,
    argc,
    argv,
    arg,
    shift_args,
    next_arg,
    xc_size,
    x_size,
    xc_fetch_plus,
    xc_fetch,
    xc_store_plus,
    xc_store_plus_question,
    xc_comma,
    xchar_plus,
    xchar_minus,
    xemit,
    xkey,
    xkey_question,
    x_width,
    xc_width,
    plus_x_string,
    x_string_minus,
    minus_trailing_garbage,
    xhold,
    ekey_to_xchar,
    x_fetch_plus_string,
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
    slurp_file,
    read_file,
    bin,
    file_position,
    resize_file,
    flush_file,
    delete_file,
    rename_file,
    file_status,
    include_file,
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
    string_slurp_file,
    string_slurp,
    string_plus_slurp,
    string_plus_slurp_file,
    string_slurp_line,
    string_plus_store_len,
    string_array_append,
    string_append_array,
    string_exec,
    system_status,
    catch_word,
    word_parse,
    find_word,
    parse,
    parse_name,
    to_in,
    source,
    source_id,
    refill,
    save_input,
    restore_input,
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
    where,
    define_defer,
    defer_store,
    defer_fetch,
    defers,
    compile_comma,
    bracket_compile,
    name_to_compile,
    begin_structure,
    end_structure,
    plus_field,
    field_cell,
    field_char,
    field_float,
    field_sfloat,
    field_dfloat,
    struct_start,
    end_struct,
    struct_field,
    cell_percent,
    char_percent,
    float_percent,
    double_percent,
    sfloat_percent,
    dfloat_percent,
    percent_size,
    percent_alignment,
    percent_align,
    percent_allot,
    percent_alloc,
    percent_allocate,
    question_exit,
    noop,
    perform,
    question_leave,
    cell_minus,
    under_plus,
    zero_greater_equal,
    compile_question_of,
    compile_contof,
    compile_next_case,
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
    bracket_ifdef,
    bracket_ifundef,
    bracket_do,
    bracket_q_do,
    bracket_loop,
    bracket_plus_loop,
    bracket_i,
    bracket_begin,
    bracket_until,
    bracket_again,
    bracket_while,
    bracket_repeat,
    bracket_for,
    bracket_next,
    f_dot_rdp,
    f_to_str_rdp,
    f_to_buf_rdp,
    f_floor,
    f_trunc,
    f_round,
    f_e_dot,
    f_s_dot,
    precision,
    set_precision,
    f_proximate,
    sf_fetch,
    sf_store,
    df_fetch,
    df_store,
    sfloats,
    dfloats,
    sfloat_plus,
    dfloat_plus,
    f_align,
    f_aligned,
    sf_align,
    sf_aligned,
    df_align,
    df_aligned,
    f_sincos,
    f_asin,
    f_acos,
    f_atan,
    f_atan2,
    f_sinh,
    f_cosh,
    f_tanh,
    f_asinh,
    f_acosh,
    f_atanh,
    f_expm1,
    f_lnp1,
    f_log,
    f_alog,
    f_power,
    represent,
    define_colon,
    end_definition,
    define_variable,
    define_fvariable,
    define_constant,
    define_value,
    define_two_variable,
    define_two_constant,
    define_fconstant,
    define_fvalue,
    define_two_value,
    define_buffer,
    define_array,
    pi,
    tick,
    to_body,
    literal,
    fliteral,
    sliteral,
    two_literal,
    help,
    license,
    // The GFX- words: REQUIRE-GRAPHICS puts them in the dictionary after the words that
    // are there, so they are not among the built-in words every dictionary starts with.
    gfx_init,
    gfx_width,
    gfx_height,
    gfx_pset,
    gfx_pget,
    gfx_hline,
    gfx_cls,
    gfx_save_ppm,
    gfx_save_bmp,
    gfx_show_blocks,
    gfx_show_sixel,
    gfx_show_window,
    gfx_window_query,
    gfx_save_png,
    gfx_inkey,
    gfx_mouse,
    gfx_mouse_mode,
    gfx_glyph_load,
    gfx_glyph_box,
    gfx_glyph_alpha,
    gfx_font_height,
    gfx_font_builtin,
    gfx_font_load,
    gfx_font_system,
    gfx_color_mode,
    gfx_tcl,
    gfx_tcl_error,
    gfx_tcl_event,
    gfx_tcl_program,
    gfx_tcl_stop,
    gfx_show_tk,
    gfx_key_held,
    gfx_window_size,
    gfx_gamepad_poll,
    gfx_gamepad_query,
    gfx_gamepad_name,
    gfx_gamepad_map,
    gfx_gamepad_guid,
    // The SND- words: REQUIRE-AUDIO puts them in the dictionary, as REQUIRE-GRAPHICS
    // does the GFX- words.
    snd_play,
    snd_sound,
    snd_beep,
    snd_playing,
    snd_device,
    snd_plays,
    snd_chip,
    snd_instrument,
    snd_wave,
    snd_duty,
    snd_adsr,
    snd_ring,
    snd_sync,
    snd_filter,
    snd_wavetable,
    snd_load_sample,
    snd_sample,
    snd_loop_sample,
    snd_sample_instrument,
    snd_sfx,
    snd_amiga_filter,
    snd_free_samples,
    snd_chips,
    snd_load_mod,
    snd_play_mod,
    snd_stop_mod,
    snd_mod_playing,
    snd_style,
    // The images of the pool (graphics_images.zig), added after the SND- words so that
    // the execution tokens of the words before stay as they were.
    gfx_image_new,
    gfx_image_free,
    gfx_image_size,
    gfx_target,
    gfx_target_query,
    gfx_copy,
    gfx_image_load,
    gfx_mouse_event,
    gfx_pixel,
    gfx_tilemap,
    gfx_indexed,
    gfx_row_shift,
    gfx_row_color,
    // The rest of gforth's words (#417): text substitution, tools, EMIT?, (LOCAL).
    substitute,
    replaces,
    unescape,
    string_substitute,
    string_unescape,
    latest,
    latestxt,
    to_name,
    id_dot,
    alias,
    debug_tilde,
    debug_tilde_run,
    assert_paren,
    assert_run,
    emit_question,
    paren_local,
    // The debugging words (not in a build with -Ddebug=false).
    ltrace_on,
    ltrace_off,
    once,
    once_run,
    debug_tilde_bt,
    debug_tilde_bt_run,
    debug_tilde_one_bt,
    define_watched_value,
    watch_run,
    dbg,
    break_colon,
    break_run,
    break_quote,
    break_quote_run,
    cover_raw,
    cov_percent,
    coverage,
    define_watched_variable,
    watch_cell,
    unwatch_cell,
    block, block_buffer, block_update, save_buffers, empty_buffers, flush_buffers, blk, scr, load_block, thru, list_block,
    // P01a: append tags so existing builtin enum values remain stable.
    zero_less_equal, d_zero_less_equal, d_zero_not_equal, d_zero_greater, d_zero_greater_equal, d_less_equal, d_not_equal, d_greater, d_greater_equal, du_less_equal, du_greater, du_greater_equal, u_less_equal, u_greater_equal, u_max, u_min,
    two_nip, two_r_drop, two_tuck, fourth, r_drop, third,
    two_comma, rol, ror,
    star_slash_f, star_slash_mod_f, star_slash_mod_s, star_slash_s, slash_f, slash_mod_f, slash_mod_s, slash_s, to_pow2, ctz, drol, dror, du_slash_mod, log2, lrol, lror, mod_f, mod_s, mux, pow2_query, u_star_slash, u_star_slash_mod, u_slash, u_slash_mod, ud_slash_mod, u_mod, wrol, wror,
    negative_inf, negative_infinity, f_reciprocal, f_mul_add, f_two_star, f_two_slash, faxpy, f_copysign, f_fourth, f_third, f_approx_abs, f_approx_rel, positive_inf, positive_infinity, nan_value, vector_dot,
    arshift, darshift, dlshift, drshift,
    random, rnd, seed_store, to_float1, base_execute, convert, decimal_dot, decimal_dot_r, dpl, e_dot, e_exact, e_precision, f_prefix_dot, h_dot, hex_dot, ud_dot, ud_dot_r,
};

pub const HeapResult = union(enum) { address: Cell, no_memory, bad_pointer };

pub const SourceKind = enum { terminal, evaluate, file, block };

/// `line_start` is the file position where the current line began, for RESTORE-INPUT.
/// A place in the input, as SAVE-INPUT gives it: the source id, >IN, the line's mark
/// (its address, or for a file where it started), and its number or length.
pub const InputPlace = struct { id: Cell, cursor: Cell, mark: Cell, number: Cell };

/// A loop of [DO], [?DO], [FOR], or [BEGIN]: the input goes back to `place` to repeat it.
pub const InterpretLoop = struct { kind: enum { counted, countdown, begin }, index: Cell = 0, limit: Cell = 0, place: InputPlace };

/// A place in a file where a word was found by name, for WHERE. The column counts from 1.
pub const WordUse = struct { word: u16, file_index: u8, column: u16, line: u32 };

/// `next_offset` is where the next line starts in an embedded source (the graphics
/// library), which has no file for the host to read.
pub const IncludeFrame = struct { fileid: Cell, file_index: u8, line: u32, line_start: UCell = 0, next_offset: UCell = 0 };

/// Where an error happened inside an included file, kept for `report`.
pub const ErrorLocation = struct { file_index: u8, line: u32 };

/// THROW codes for interpreter errors, so CATCH can return them and THROW can raise
/// them again with the original message. Standard Forth 2012 codes are used where one
/// fits; the rest are system codes from -256 down. UnknownWord stays a plain code
/// because its message needs the word that was not found.
pub const error_codes = [_]struct { RuntimeError, Cell }{
    .{ error.StackOverflow, -3 },           .{ error.StackUnderflow, -4 },          .{ error.ReturnStackOverflow, -5 },
    .{ error.ReturnStackUnderflow, -6 },    .{ error.DictionaryFull, -8 },          .{ error.InvalidAddress, -9 }, .{ error.InvalidBlockNumber, -35 },
    .{ error.DivisionByZero, -10 },         .{ error.ResultOutOfRange, -11 },       .{ error.CompileOnly, -14 },            .{ error.PicturedNumericOverflow, -17 },
    .{ error.StringTooLong, -18 },          .{ error.NameTooLong, -19 },            .{ error.HostUnavailable, -21 },
    .{ error.ControlMismatch, -22 },        .{ error.InvalidNumber, -24 },          .{ error.LoopMismatch, -26 },
    .{ error.FloatStackOverflow, -44 },     .{ error.FloatStackUnderflow, -45 },    .{ error.CodeFull, -256 },
    .{ error.MemoryExhausted, -257 },       .{ error.ControlStackOverflow, -258 },  .{ error.InvalidDefinition, -259 },
    .{ error.InvalidBase, -260 },           .{ error.InvalidExecutionToken, -261 }, .{ error.InputUnavailable, -262 },
    .{ error.FileUnavailable, -263 },       .{ error.InvalidImage, -264 },          .{ error.HostFailed, -265 },
    .{ error.CommentUnclosed, -266 },       .{ error.IncludeNesting, -267 },        .{ error.TooManySourceFiles, -268 },
    .{ error.SearchOrderOverflow, -49 },     .{ error.SearchOrderUnderflow, -50 },   .{ error.InvalidWordlist, -269 },
    .{ error.GraphicsUnavailable, -270 },   .{ error.NoCanvas, -271 },          .{ error.UserInterrupt, -28 },
    .{ error.FontUnavailable, -272 },     .{ error.TclFailed, -273 },        .{ error.InvalidMml, -274 },
    .{ error.AudioUnavailable, -275 },     .{ error.SampleInvalid, -276 },
    .{ error.ModInvalid, -277 },            .{ error.InvalidImageHandle, -278 }, .{ error.ImageInvalid, -279 },
    .{ error.StepLimit, -280 },
};

pub const throw_code_undefined_word: Cell = -13;

/// Interpreter state that CATCH restores when the executed word throws.
pub const CatchFrame = struct {
    data_depth: usize,
    float_depth: usize,
    return_depth: usize,
    loop_depth: usize,
    control_depth: usize,
    interpret_loop_depth: usize,
    pending: Pending,
    compiling: bool,
    defining: bool,
    local_count: usize,
};

pub const WordKind = enum { builtin, colon, variable, constant, array, created, value, fconstant, fvalue, two_constant, two_value, marker, vocabulary, synonym, deferred, field };

pub const Word = struct {
    /// Where the name is in `State.names`.
    name_start: u32 = 0,
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
// Execution-only specializations are normalized when saving an image. Everything
// from dup onward is a primitive operation named after its Builtin; value remains
// the original word id. Keep the serialized tags (call through call_builtin) stable.
pub const OpKind = enum {
    call, compile_call, builtin, literal, float_literal, execution_token, store_value, branch, branch_zero, do_loop, q_do_loop, loop, plus_loop, leave, print_string, string_literal, counted_string, abort_string, does, exit, local_frame, local_store, local_fetch, local_address, local_execute, add_value, call_builtin,
    call_colon,
    dup, drop, swap, over, rot, nip, tuck, two_dup, two_drop, add, sub, mul, equal, not_equal, less, greater, zero_equal, zero_less, bit_and, bit_or, bit_xor, bit_complement, negate, one_plus, one_minus, to_r, from_r, r_fetch, fetch, store, cfetch, cstore, add_store, index, index_2, cells, cell_plus,
    two_star, two_slash, lshift, rshift, f_add, f_sub, f_mul, f_div, f_dup, f_drop, f_swap, f_over,
    execute,
};

pub fn isPrimitiveOp(kind: OpKind) bool {
    return @intFromEnum(kind) >= @intFromEnum(OpKind.dup);
}

pub fn primitiveBuiltin(comptime kind: OpKind) Builtin {
    if (!isPrimitiveOp(kind)) @compileError("not a primitive operation");
    return @field(Builtin, @tagName(kind));
}

pub fn builtinOpKind(builtin: Builtin) OpKind {
    return switch (builtin) {
        inline .dup, .drop, .swap, .over, .rot, .nip, .tuck, .two_dup, .two_drop, .add, .sub, .mul, .equal, .not_equal, .less, .greater, .zero_equal, .zero_less, .bit_and, .bit_or, .bit_xor, .bit_complement, .negate, .one_plus, .one_minus, .to_r, .from_r, .r_fetch, .fetch, .store, .cfetch, .cstore, .add_store, .index, .index_2, .cells, .cell_plus, .two_star, .two_slash, .lshift, .rshift, .f_add, .f_sub, .f_mul, .f_div, .f_dup, .f_drop, .f_swap, .f_over, .execute => |hot| @field(OpKind, @tagName(hot)),
        else => .call_builtin,
    };
}

comptime {
    if (@sizeOf(OpKind) != 1) @compileError("operation tags must keep their image layout");
}

pub const LocalKind = enum(u8) { cell, double, float, char, xt };

pub const Local = struct {
    name: [max_name]u8 = undefined,
    name_len: u8 = 0,
    kind: LocalKind = .cell,
    /// Variable flavour (`W^` ...): the name pushes the slot address instead of its value.
    variable: bool = false,
    offset: u16 = 0,
};

pub const Op = struct { kind: OpKind, value: Cell = 0 };

pub const ControlKind = enum { if_branch, else_branch, begin_loop, while_branch, do_loop, case_start, of_branch, endof_branch };

/// `locals` is the number of local names visible where the structure starts; a DO loop
/// also keeps the fewest visible at any of its LEAVEs.
pub const Control = struct { kind: ControlKind, address: u16, locals: u16 = 0, leave_locals: u16 = std.math.maxInt(u16) };

pub const Loop = struct { index: Cell, limit: Cell, exit_pc: u16, exit_after_first: bool = false };

pub const Pending = enum { none, colon_name, variable_name, constant_name, array_name, forget_name, tick_name, value_name, watched_value_name, watched_variable_name, to_name, char_name, postpone_name, fconstant_name, fvalue_name, fvariable_name, two_constant_name, two_value_name, two_variable_name, buffer_name, plus_to_name, action_of_name };

pub const StringWord = enum { s_quote, s_escape_quote, print_escape, print_paren, c_quote, abort_quote };

pub const ParsedNumber = struct { value: Double, double: bool };

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
    ResultOutOfRange,
    /// QUIT: back to the terminal with the data stacks kept; CATCH does not catch it.
    Quit,
    LoopMismatch,
    InvalidBase,
    InvalidExecutionToken,
    InvalidAddress,
    InvalidBlockNumber,
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
    /// REQUIRE-GRAPHICS in a build without graphics (-Dgraphics=false).
    GraphicsUnavailable,
    /// A GFX- word that needs an image before GFX-INIT has made one.
    NoCanvas,
    /// Ctrl+C read by INKEY or MOUSE.
    UserInterrupt,
    /// A font LOAD-FONT cannot read, or a name the system has no font of.
    FontUnavailable,
    /// A Tcl script that failed (TCL, TCL-EVAL, DISPLAY-TK).
    TclFailed,
    /// A PLAY string that is not MSX BASIC's music macro language, or a number in it
    /// out of its range.
    InvalidMml,
    /// REQUIRE-AUDIO in a build without sound (-Daudio=false).
    AudioUnavailable,
    /// A file LOAD-SAMPLE cannot read: not a WAV file of 8- or 16-bit PCM.
    SampleInvalid,
    /// A file LOAD-MOD cannot read: not a ProTracker module of four channels.
    ModInvalid,
    /// A handle that names no image of the pool: never made, freed, or from before a restore.
    InvalidImageHandle,
    /// A file LOAD-IMAGE cannot read: not a PNG, BMP, or PPM/PGM file it knows, or damaged.
    ImageInvalid,
    /// Compiled code ran more operations than --max-steps allows; CATCH does not catch it.
    StepLimit,
};

pub fn floatBits(value: Float) Cell {
    return @bitCast(value);
}

pub fn bitsFloat(value: Cell) Float {
    return @bitCast(value);
}

pub const DoubleCells = struct { low: Cell, high: Cell };

pub fn doubleCells(value: Double) DoubleCells {
    const bits: UDouble = @bitCast(value);
    return .{ .low = @bitCast(@as(UCell, @truncate(bits))), .high = @bitCast(@as(UCell, @truncate(bits >> 64))) };
}

pub fn cellsDouble(low: Cell, high: Cell) Double {
    const bits = (@as(UDouble, @as(UCell, @bitCast(high))) << 64) | @as(UCell, @bitCast(low));
    return @bitCast(bits);
}
