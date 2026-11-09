//! Cell types, limits, and the layout of the 2 MiB logical memory.

const builtin_info = @import("builtin");

pub const Cell = i64;

pub const UCell = u64;

pub const Double = i128;

pub const UDouble = u128;

pub const Float = f64;

pub const cell_size = 8;

pub const float_size = 8;

pub const max_words = 8192;
/// Uses of words read from files that WHERE can list; later uses are not recorded.
pub const max_uses = 65536;

pub const max_code = 65535;

pub const max_stack = 1024;

pub const max_float_stack = 1024;

pub const max_controls = 128;

pub const max_name = 255;
/// Bytes for the names of all dictionary entries, which are kept in one area.
pub const names_capacity = 256 * 1024;

// The layout of the logical memory, all of it computed here from two sizes:
//   0 .. system_end         the system area (see the addresses below)
//   system_end .. data_start  the input area (a fixed size)
//   data_start .. m         the data area (HERE)
//   m .. 2m                 the ALLOCATE heap
//   2m .. 2m + l            the frames of local variables
// The checks after the input area's addresses keep the areas apart.

/// `m`: where the data area ends, and the size of the heap.
pub const layout_m = 1 << 20;

/// `l`: the size of the area for the frames of local variables.
pub const layout_l = 0x10000;

pub const system_end: Cell = 0x4000;

pub const input_area_size = 0x10000;

pub const memory_size = 2 * layout_m + layout_l;

/// The data area ends where the ALLOCATE heap begins.
pub const data_limit: Cell = layout_m;

pub const heap_base: Cell = data_limit;

pub const heap_end: Cell = 2 * layout_m;

/// The frames of local variables come last, so variable-flavoured locals (`W^`, `F^`,
/// ...) have addresses in logical memory.
pub const locals_base: Cell = heap_end;

pub const locals_end: Cell = memory_size;

/// Input buffers after the system area: the terminal input buffer first; the rest is
/// kept for the line buffers of nested INCLUDE files.
pub const input_area_base: Cell = system_end;

pub const input_area_end: Cell = input_area_base + input_area_size;

pub const tib_address: Cell = input_area_base;

pub const tib_size = 4096;

/// One line buffer per nested INCLUDE level after the TIB.
pub const max_include_depth = 8;

pub const include_buffer_base: Cell = tib_address + tib_size;

/// Names of the source files that have been included, which is also the REQUIRE
/// history: 64 entries of a length byte and up to 255 name bytes. The entry count
/// lives at `source_file_count_address`, so images keep the table.
pub const source_file_table: Cell = include_buffer_base + max_include_depth * tib_size;

pub const max_source_files = 64;

pub const source_file_entry_size = 256;

pub const source_file_count_address: Cell = 0x0218;

/// One byte per table entry: non-zero while the file counts as loaded for REQUIRE.
/// MARKER clears these flags instead of shortening the table, so names that words and
/// open input frames refer to stay valid.
pub const source_file_loaded_flags: Cell = source_file_table + max_source_files * source_file_entry_size;

/// The command-line arguments, as gforth keeps them: ARGC is a cell holding their count
/// and ARGV a cell holding the address of a vector of cells, each the address of a
/// NUL-terminated argument; argument 0 names the program. The host writes them at
/// startup; the area is in the input area, so images do not keep it.
pub const argc_address: Cell = source_file_loaded_flags + max_source_files;

pub const argv_address: Cell = argc_address + cell_size;

pub const max_arguments = 256;

pub const argument_vector: Cell = argv_address + cell_size;

pub const argument_strings: Cell = argument_vector + max_arguments * cell_size;

pub const argument_strings_end: Cell = input_area_end;

comptime {
    if (argc_address % cell_size != 0 or argument_strings_end - argument_strings < 8192) @compileError("the argument area does not fit");
    if (environment_buffer_base + environment_buffer_size > system_end) @compileError("the system area does not fit");
    if (data_start != input_area_end or data_start % cell_size != 0) @compileError("the data area must follow the input area, aligned to a cell");
    if (data_limit <= data_start or data_limit % cell_size != 0) @compileError("the data area is empty or not aligned");
    if (heap_base != data_limit or heap_end <= heap_base or heap_end % cell_size != 0) @compileError("the heap must follow the data area, aligned to a cell");
    if (locals_base != heap_end or locals_end <= locals_base or locals_end != memory_size) @compileError("the local variables must end the memory");
}

/// Word lists: ids 1 (Forth) and 2 (Root) exist from the start; WORDLIST and
/// VOCABULARY allocate more. The count, the current list, and the search order are
/// kept in memory so images restore them. `search_order` holds the first-searched
/// list at index 0.
pub const forth_wordlist: Cell = 1;

pub const root_wordlist: Cell = 2;

pub const max_wordlists = 64;

pub const max_search_order = 16;

pub const wordlist_count_address: Cell = 0x0220;

pub const current_wordlist_address: Cell = 0x0228;

pub const search_order_depth_address: Cell = 0x0230;

pub const search_order_address: Cell = 0x0238;

/// The digits F. FE. and FS. show, set by SET-PRECISION (after the search order's 16 cells).
pub const precision_address: Cell = 0x02c0;

/// >IN, the offset of the next character in the current input source.
pub const in_address: Cell = 0x02c8;

/// The word number of the GRAPHICS vocabulary that REQUIRE-GRAPHICS made, or 0. The
/// GFX- words follow it; REQUIRE-GRAPHICS loads again when FORGET or a MARKER removed it.
pub const graphics_vocabulary_address: Cell = 0x02d0;

/// Non-zero once REQUIRE-GRAPHICS has loaded the graphics words: images are then saved
/// as `graphics_image_magic`, even after the words are forgotten. Both cells are 0 in an
/// image of an older build, which never wrote them.
pub const graphics_image_address: Cell = 0x02d8;

/// The same two cells for REQUIRE-AUDIO: the word number of the AUDIO vocabulary, and
/// non-zero once the audio words were loaded (images are then saved as
/// `audio_image_magic`).
pub const audio_vocabulary_address: Cell = 0x02e0;
pub const audio_image_address: Cell = 0x02e8;

/// Words that are also in the Root word list, so they stay usable after ONLY.
pub const root_word_names = [_][]const u8{ "FORTH", "FORTH-WORDLIST", "ONLY", "ALSO", "PREVIOUS", "ORDER", "DEFINITIONS", "GET-ORDER", "SET-ORDER", "WORDS" };

/// Bytes a MARKER keeps: the loaded-file mask, the current list, the order depth, and the order.
pub const marker_snapshot_size = (3 + max_search_order) * cell_size;

/// SOURCEFILENAME results outside files, as in gforth.
pub const terminal_source_name = "*the terminal*";

pub const evaluate_source_name = "*evaluated string*";

pub const terminal_source_name_address: Cell = 0x0d00;

pub const evaluate_source_name_address: Cell = 0x0d20;

/// Results of NAME>STRING, eight 256-byte buffers used in turn, and the WORD buffer.
pub const name_buffer_base: Cell = 0x0400;

pub const name_buffer_count = 8;

pub const word_buffer_address: Cell = 0x0c00;

pub const max_locals = 64;

/// Each heap block starts with its payload size and a used flag, one cell each.
pub const heap_header = 2 * cell_size;

pub const base_address: Cell = 0x0200;

pub const state_address: Cell = 0x0208;

/// The end of the used part of the heap; kept in memory so images preserve it.
pub const heap_top_address: Cell = 0x0210;

/// Sixteen string variables holding the results of $TMP, reused in turn.
pub const tmp_string_base: Cell = 0x0300;

pub const tmp_string_count = 16;

pub const hold_bottom: Cell = 0x1000;

pub const hold_top: Cell = 0x2000;

pub const pad_address: Cell = 0x2000;

/// Four buffers of 256 bytes that S" outside a definition once used in turn. Since S"
/// keeps each string in the heap (as gforth), the area is not used; it stays, so that
/// PAD's size (/PAD) and the places after it do not change.
pub const string_buffer_base: Cell = 0x3000;

pub const string_buffer_size = 256;

pub const string_buffer_count = 4;

pub const environment_buffer_base: Cell = 0x3400;

pub const environment_buffer_size = 0x0c00;

pub const max_host_name = 1024;

pub const max_hold_nesting = 16;

pub const max_counted_string = 127;

pub const max_gforth_string = 255;

pub const data_start: Cell = input_area_end;

pub const true_flag: Cell = -1;

/// PRECISION at startup, as in gforth.
pub const dot_precision = 15;

/// Output uses at most this many digits (and at least one). gforth prints up to at least
/// 1000 and fails for zero or less and for 4000; a double's exact decimal form has at
/// most 767 significant digits, and zeros follow.
pub const max_float_precision = 1000;

/// Items .S and F.S show below the depth, as gforth's maxdepth-.s.
pub const max_dot_s_items = 9;

pub const fs_precision = 14;

/// SIGIMG39 moved the input area below the data area, which changed the addresses in the
/// data area and the parts of memory an image keeps, so SIGIMG38 and earlier images are
/// not read.
pub const image_magic = "SIGIMG39";
/// The same layout as `image_magic`, for an image that has had the graphics words; builds
/// that only know SIGIMG39 reject it.
pub const graphics_image_magic = "SIGIMG40";
/// The same layout again, for an image that has had the audio words (with or without the
/// graphics words); builds that only know SIGIMG39 and SIGIMG40 reject it.
pub const audio_image_magic = "SIGIMG41";

/// File ids of the standard streams; the host numbers opened files from `first_file_id`.
pub const stdin_fileid: Cell = 1;

pub const stdout_fileid: Cell = 2;

pub const stderr_fileid: Cell = 3;

pub const first_file_id: Cell = 4;

/// The file id of an embedded source, which the core reads itself (the graphics library;
/// SOURCE-ID gives it while the library loads).
pub const embedded_source_fileid: Cell = -2;

/// File access methods, with gforth's values for R/O, R/W and W/O.
pub const fam_read_only: Cell = 0;

pub const fam_read_write: Cell = 2;

pub const fam_write_only: Cell = 4;

/// I/O results follow gforth: 0 for success, otherwise -512 minus the C errno.
pub const ior_errno_base: Cell = -512;

pub const errno_bad_file: Cell = 9;

pub const errno_no_memory: Cell = 12;

pub const errno_invalid: Cell = 22;

pub const line_terminator = if (builtin_info.os.tag == .windows) "\r\n" else "\n";

pub fn errnoIor(errno: Cell) Cell {
    return ior_errno_base - errno;
}
