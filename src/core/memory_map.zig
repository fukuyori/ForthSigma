//! Cell types, limits, and the layout of the logical memory.

const builtin_info = @import("builtin");
const build_options = @import("build_options");

pub const Cell = i64;

pub const UCell = u64;

pub const Double = i128;

pub const UDouble = u128;

pub const Float = f64;

pub const cell_size = 8;

pub const float_size = 8;

/// The dictionary's entries (-Dwords); word numbers are 16 bits.
pub const max_words = build_options.max_words;
/// Uses of words read from files that WHERE can list; later uses are not recorded.
pub const max_uses = 65536;

pub const max_code = 65535;

pub const max_controls = 128;

pub const max_name = 255;
/// Bytes for the names of all dictionary entries, which are kept in one area (-Dnames-kib).
pub const names_capacity = build_options.names_kib << 10;

// The layout of the logical memory:
//   0 .. system_end         the system area (see the addresses below)
//   system_end .. input_area_end  the input area (a fixed size)
//   input_area_end .. data_start  runtime block buffers and source snapshots
//   data_start .. m         the data area (HERE)
//   m .. 2m                 the ALLOCATE heap
//   2m .. 2m + l            the frames of local variables
// The first two have fixed addresses. The rest follow from `m` and `l` in `Sizes`.

pub const system_end: Cell = 0x4000;

pub const input_area_size = 0x10000;

pub const min_memory_m = 1 << 20;
pub const min_memory_l = 4096;
/// Images keep HERE in four bytes, so the whole memory stays below 4 GiB.
pub const memory_limit = 1 << 32;
pub const min_stack = 16;
pub const max_stack_limit = 1 << 27;

/// The sizes a State runs with. `m` and `l` are in bytes; the stacks are in elements.
pub const Sizes = struct {
    /// Where the data area ends, and the size of the heap.
    m: usize,
    /// The size of the area for the frames of local variables.
    l: usize,
    data_stack: usize,
    return_stack: usize,
    float_stack: usize,

    /// The smallest usual sizes, which the tests and a freestanding host use.
    pub const small: Sizes = .{ .m = 1 << 20, .l = 0x10000, .data_stack = 1024, .return_stack = 1024, .float_stack = 1024 };

    /// The sizes of the program when the command line does not give others.
    pub const default: Sizes = .{
        .m = build_options.memory_mib << 20,
        .l = build_options.locals_kib << 10,
        .data_stack = build_options.stack_cells,
        .return_stack = build_options.stack_cells,
        .float_stack = build_options.stack_cells,
    };

    pub fn memorySize(self: Sizes) usize {
        return 2 * self.m + self.l;
    }

    /// The data area ends where the ALLOCATE heap begins.
    pub fn dataLimit(self: Sizes) Cell {
        return @intCast(self.m);
    }

    pub fn heapBase(self: Sizes) Cell {
        return @intCast(self.m);
    }

    pub fn heapEnd(self: Sizes) Cell {
        return @intCast(2 * self.m);
    }

    /// The frames of local variables come last, so variable-flavoured locals (`W^`,
    /// `F^`, ...) have addresses in logical memory.
    pub fn localsBase(self: Sizes) Cell {
        return self.heapEnd();
    }

    pub fn localsEnd(self: Sizes) Cell {
        return @intCast(self.memorySize());
    }

    pub fn validLayout(m: usize, l: usize) bool {
        if (m < min_memory_m or l < min_memory_l) return false;
        if (m % cell_size != 0 or l % cell_size != 0) return false;
        // In 64 bits, so that the sum cannot wrap on a 32-bit host; a valid layout then
        // fits a usize.
        return 2 * @as(u64, m) + @as(u64, l) < memory_limit;
    }

    pub fn validStack(elements: usize) bool {
        return elements >= min_stack and elements <= max_stack_limit;
    }

    pub fn valid(self: Sizes) bool {
        return validLayout(self.m, self.l) and validStack(self.data_stack) and validStack(self.return_stack) and validStack(self.float_stack);
    }
};

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
    if (data_start != block_source_end or data_start % cell_size != 0) @compileError("the data area must follow the input area, aligned to a cell");
    if (blk_address < evaluate_source_name_address + evaluate_source_name.len or scr_address != blk_address + cell_size or scr_address + cell_size > hold_bottom) @compileError("block variables overlap system buffers");
    if (newline_address < evaluate_source_name_address + 1 + evaluate_source_name.len or newline_address + 1 > blk_address) @compileError("NEWLINE overlaps system variables or source names");
    if (data_start >= min_memory_m) @compileError("the smallest data area is empty");
    if (!Sizes.small.valid()) @compileError("the small sizes are not valid");
    if (!Sizes.default.valid()) @compileError("the default sizes are not valid");
    if (max_words < 1024 or max_words > 65535) @compileError("-Dwords must be 1024 to 65535");
    if (names_capacity < 64 << 10 or names_capacity > 1 << 31) @compileError("-Dnames-kib must be 64 to 2097152");
}

/// Word lists: ids 1 (Forth) and 2 (Root) exist from the start; WORDLIST and
/// VOCABULARY allocate more. The count, the current list, and the search order are
/// kept in memory so images restore them. `search_order` holds the first-searched
/// list at index 0.
pub const forth_wordlist: Cell = 1;

pub const root_wordlist: Cell = 2;

/// Standard keyboard constants; user wordlists start after this fixed list.
pub const ekeys_wordlist: Cell = 3;
/// Fixed, case-sensitive macro namespace; does not consume a user WORDLIST id.
pub const macros_wordlist: Cell = 0xff;

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

/// The word numbers of the GUI and GAME vocabularies that REQUIRE-GUI and REQUIRE-GAME
/// make, or 0. Their libraries are Forth only, so no cell marks the image's format.
pub const gui_vocabulary_address: Cell = 0x02f0;
pub const game_vocabulary_address: Cell = 0x02f8;

/// Words that are also in the Root word list, so they stay usable after ONLY.
pub const root_word_names = [_][]const u8{ "FORTH", "FORTH-WORDLIST", "ONLY", "ALSO", "PREVIOUS", "ORDER", "DEFINITIONS", "GET-ORDER", "SET-ORDER", "WORDS" };

/// Bytes a MARKER keeps: the loaded-file mask, the current list, the order depth, and the order.
pub const marker_snapshot_size = (3 + max_search_order) * cell_size;

/// SOURCEFILENAME results outside files, as in gforth.
pub const terminal_source_name = "*the terminal*";

pub const evaluate_source_name = "*evaluated string*";

pub const terminal_source_name_address: Cell = 0x0d00;

pub const evaluate_source_name_address: Cell = 0x0d20;

/// Borrowed LF returned by NEWLINE; below BLK/SCR and after source-name text.
pub const newline_address: Cell = 0x0d38;

/// The first of the replacements REPLACES made (0 for none), a list in the heap that
/// SUBSTITUTE reads: each block holds the next one, the name's length, the text's length,
/// the name, and the text. In memory, so that images keep it.
pub const replacements_address: Cell = 0x0380;

/// The counted string ASSERT( gives THROW -2 ("assertion failed").
pub const assert_message_address: Cell = 0x0388;

/// Results of NAME>STRING, eight 256-byte buffers used in turn, and the WORD buffer.
pub const name_buffer_base: Cell = 0x0400;

pub const name_buffer_count = 8;

pub const word_buffer_address: Cell = 0x0c00;

pub const max_locals = 64;

/// Each heap block starts with its payload size and a used flag, one cell each.
pub const heap_header = 2 * cell_size;

pub const base_address: Cell = 0x0200;

/// Decimal places of the latest integer conversion (-1 for a single-cell number).
pub const dpl_address: Cell = 0x0d50;

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

/// Runtime block buffers are outside the ranges serialized by dictionary images.
pub const block_buffer_base: Cell = input_area_end;
pub const block_buffer_end: Cell = block_buffer_base + 32 * 1024;
pub const block_source_base: Cell = block_buffer_end;
pub const block_source_end: Cell = block_source_base + max_include_depth * 1024;
pub const data_start: Cell = block_source_end;
pub const blk_address: Cell = 0x0d40;
pub const scr_address: Cell = 0x0d48;

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

/// SIGIMG45 records the layout of the logical memory (`m` and `l`) in its header. An image
/// keeps addresses, so it runs only with the layout it was saved with. Images before it
/// are not read.
pub const image_magic = "SIGIMG45";
/// The same layout as `image_magic`, for an image that has had the graphics words; builds
/// that only know SIGIMG45 reject it.
pub const graphics_image_magic = "SIGIMG46";
/// The same layout again, for an image that has had the audio words (with or without the
/// graphics words); builds that only know SIGIMG45 and SIGIMG46 reject it.
pub const audio_image_magic = "SIGIMG47";

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
