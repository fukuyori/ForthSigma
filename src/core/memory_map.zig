//! Cell types, limits, and the layout of the 2 MiB logical memory.

const builtin_info = @import("builtin");

pub const Cell = i64;

pub const UCell = u64;

pub const Double = i128;

pub const UDouble = u128;

pub const Float = f64;

pub const cell_size = 8;

pub const float_size = 8;

pub const max_words = 1024;

pub const max_code = 8192;

pub const max_stack = 1024;

pub const max_float_stack = 1024;

pub const max_controls = 128;

pub const max_name = 255;

pub const memory_size = 2 << 20;

/// The data area ends where the ALLOCATE heap begins; the heap runs to the end of memory.
pub const data_limit: Cell = 1 << 20;

pub const heap_base: Cell = data_limit;

/// The last 64 KiB hold the frames of local variables, so variable-flavoured locals
/// (`W^`, `F^`, ...) have addresses in logical memory.
pub const locals_base: Cell = memory_size - 0x10000;

pub const locals_end: Cell = memory_size;

/// Input buffers below the locals: the terminal input buffer first; the rest is kept
/// for the line buffers of nested INCLUDE files.
pub const input_area_base: Cell = locals_base - 0x10000;

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

/// Words that are also in the Root word list, so they stay usable after ONLY.
pub const root_word_names = [_][]const u8{ "FORTH", "FORTH-WORDLIST", "ONLY", "ALSO", "PREVIOUS", "ORDER", "DEFINITIONS", "GET-ORDER", "SET-ORDER", "WORDS" };

/// Bytes a MARKER keeps: the loaded-file mask, the current list, the order depth, and the order.
pub const marker_snapshot_size = (3 + max_search_order) * cell_size;

/// SOURCEFILENAME results outside files, as in gforth.
pub const terminal_source_name = "*the terminal*";

pub const evaluate_source_name = "*evaluated string*";

pub const terminal_source_name_address: Cell = 0x0d00;

pub const evaluate_source_name_address: Cell = 0x0d20;

pub const heap_end: Cell = input_area_base;

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

pub const string_buffer_base: Cell = 0x3000;

pub const string_buffer_size = 256;

pub const string_buffer_count = 4;

pub const environment_buffer_base: Cell = 0x3400;

pub const environment_buffer_size = 0x0c00;

pub const max_host_name = 1024;

pub const max_hold_nesting = 16;

pub const max_counted_string = 127;

pub const max_gforth_string = 255;

pub const data_start: Cell = 0x4000;

pub const true_flag: Cell = -1;

pub const dot_precision = 15;

/// Items .S and F.S show below the depth, as gforth's maxdepth-.s.
pub const max_dot_s_items = 9;

pub const fs_precision = 14;

pub const image_magic = "SIGIMG14";

/// File ids of the standard streams; the host numbers opened files from `first_file_id`.
pub const stdin_fileid: Cell = 1;

pub const stdout_fileid: Cell = 2;

pub const stderr_fileid: Cell = 3;

pub const first_file_id: Cell = 4;

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
