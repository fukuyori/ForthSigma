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
const inline_calls = @import("core/inline_calls.zig");
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
const words_graphics = @import("core/words_graphics.zig");
const graphics_images = @import("core/graphics_images.zig");
const words_audio = @import("core/words_audio.zig");
const sound_mml = @import("core/sound_mml.zig");
const sound_engine = @import("core/sound_engine.zig");
const graphics_terminal = @import("core/graphics_terminal.zig");
const graphics_input = @import("core/graphics_input.zig");
const graphics_font = @import("core/graphics_font.zig");
const graphics_palette = @import("core/graphics_palette.zig");
const tcl = @import("core/tcl.zig");
const words_defining = @import("core/words_defining.zig");
const words_help = @import("core/words_help.zig");
const words_input = @import("core/words_input.zig");
const words_memory = @import("core/words_memory.zig");
const words_output = @import("core/words_output.zig");
const words_pictured = @import("core/words_pictured.zig");
const words_stack = @import("core/words_stack.zig");
const words_strings = @import("core/words_strings.zig");
const words_system = @import("core/words_system.zig");
const words_tools = @import("core/words_tools.zig");
const words_debug = @import("core/words_debug.zig");
pub const Profile = @import("core/profiler.zig").Profile;
pub const Lint = @import("core/lint.zig").Lint;
pub const logStart = @import("core/debug_log.zig").logStart;
const words_xchar = @import("core/words_xchar.zig");
const Builtin = defs.Builtin;
pub const Cell = memory_map.Cell;
const Control = defs.Control;
pub const Double = memory_map.Double;
const ErrorLocation = defs.ErrorLocation;
pub const CpuTimes = host_interface.CpuTimes;
pub const FileAccess = host_interface.FileAccess;
pub const FileOps = host_interface.FileOps;
pub const FileKeyResult = host_interface.FileKeyResult;
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
const OpKind = defs.OpKind;
const Pending = defs.Pending;
pub const RuntimeError = defs.RuntimeError;
const SourceKind = defs.SourceKind;
const StringWord = defs.StringWord;
pub const UCell = memory_map.UCell;
pub const UDouble = memory_map.UDouble;
const Word = defs.Word;
const WordKind = defs.WordKind;
pub const LocalTime = host_interface.LocalTime;
pub const ZonedTime = host_interface.ZonedTime;
pub const TerminalSize = host_interface.TerminalSize;
pub const InputEvent = host_interface.InputEvent;
pub const AudioWait = host_interface.AudioWait;
pub const CursorPosition = host_interface.CursorPosition;
pub const SystemGlyph = host_interface.SystemGlyph;
pub const ColorMode = host_interface.ColorMode;
pub const graphicsColor = graphics_palette.convert;
/// For the host's editing of a typed line: a character's UTF-8 decoding and its width in
/// columns, as XC@ and XC-WIDTH give them.
pub const decodeXchar = words_xchar.decode;
pub const charWidth = @import("core/char_width.zig").width;
pub const Writer = host_interface.Writer;
const base_address = memory_map.base_address;
const bitsFloat = defs.bitsFloat;
const cell_size = memory_map.cell_size;
const cellsDouble = defs.cellsDouble;
const current_wordlist_address = memory_map.current_wordlist_address;
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
const heap_top_address = memory_map.heap_top_address;
const hold_top = memory_map.hold_top;
const in_address = memory_map.in_address;
pub const ior_errno_base = memory_map.ior_errno_base;
const max_code = memory_map.max_code;
const max_controls = memory_map.max_controls;
const max_hold_nesting = memory_map.max_hold_nesting;
const max_include_depth = memory_map.max_include_depth;
const max_locals = memory_map.max_locals;
const max_name = memory_map.max_name;
const max_search_order = memory_map.max_search_order;
const max_words = memory_map.max_words;
const max_uses = memory_map.max_uses;
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

/// The logical memory and the stacks of a State, which its host allocates. Each has the
/// size of its limit, and starts as zeros.
pub const Storage = struct {
    sizes: Sizes,
    memory: []u8,
    data_stack: []Cell,
    return_stack: []Cell,
    float_stack: []Float,
    /// The DO loops and the callers of colon definitions nest as the return stack does,
    /// so they have the size of the return stack.
    loop_stack: []Loop,
    frames: []State.CallFrame,
    catches: []State.CatchContinuation,

    /// With `already_zero`, the allocator gives zeros by itself (fresh pages of the
    /// system), and they are not written, so pages never used take no physical memory.
    /// Zig's allocators mark new memory as undefined in the builds with safety checks,
    /// so those builds always write the zeros.
    pub fn allocate(allocator: std.mem.Allocator, already_zero: bool, sizes: Sizes) std.mem.Allocator.Error!Storage {
        const memory = try allocator.alloc(u8, sizes.memorySize());
        errdefer allocator.free(memory);
        const data = try allocator.alloc(Cell, sizes.data_stack);
        errdefer allocator.free(data);
        const ret = try allocator.alloc(Cell, sizes.return_stack);
        errdefer allocator.free(ret);
        const float = try allocator.alloc(Float, sizes.float_stack);
        errdefer allocator.free(float);
        const loops = try allocator.alloc(Loop, sizes.return_stack);
        errdefer allocator.free(loops);
        const frames = try allocator.alloc(State.CallFrame, sizes.return_stack);
        errdefer allocator.free(frames);
        const catches = try allocator.alloc(State.CatchContinuation, sizes.return_stack);
        if (!already_zero or std.debug.runtime_safety) {
            @memset(memory, 0);
            @memset(data, 0);
            @memset(ret, 0);
            @memset(float, 0);
        }
        return .{ .sizes = sizes, .memory = memory, .data_stack = data, .return_stack = ret, .float_stack = float, .loop_stack = loops, .frames = frames, .catches = catches };
    }

    pub fn free(self: Storage, allocator: std.mem.Allocator) void {
        allocator.free(self.catches);
        allocator.free(self.frames);
        allocator.free(self.loop_stack);
        allocator.free(self.float_stack);
        allocator.free(self.return_stack);
        allocator.free(self.data_stack);
        allocator.free(self.memory);
    }
};

pub const Sizes = memory_map.Sizes;

/// Frees the images of the pool through the host; the host calls it when the session ends.
pub const releaseImages = graphics_images.releaseAll;

pub const State = struct {
    writer: Writer,
    sizes: Sizes,
    memory: []u8,
    words: [max_words]Word = undefined,
    word_count: u16 = 0,
    /// The index of the names (wordlists.zig): for each bucket the newest word whose
    /// name falls in it, and for each word the next older word of its bucket.
    name_heads: [wordlists.name_buckets]u16 = @splat(wordlists.no_word),
    name_next: [max_words]u16 = undefined,
    builtin_count: u16 = 0,
    code: [max_code]Op = undefined,
    code_count: u16 = 0,
    /// The names of the dictionary entries, one after another.
    names: [names_capacity]u8 = undefined,
    names_used: u32 = 0,
    data_stack: []Cell,
    data_depth: usize = 0,
    return_stack: []Cell,
    return_depth: usize = 0,
    float_stack: []Float,
    float_depth: usize = 0,
    quote_frames: [16]@import("core/quotations.zig").Frame = undefined,
    quote_depth: usize = 0,
    quote_closing: bool = false,
    quote_root: u16 = 0,
    noname_next: bool = false,
    postponing: bool = false,
    control_stack: [max_controls]Control = undefined,
    control_depth: usize = 0,
    random_state: u64 = 0,
    addresses: @import("core/address_registry.zig").Registry = .{},
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
    loop_stack: []Loop,
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
    source_line: []const u8 = &.{},
    /// Where the current input came from; only terminal input reads further lines.
    source_kind: SourceKind = .terminal,
    block_depth: usize = 0,
    block_source_numbers: [memory_map.max_include_depth]Cell = @splat(0),
    include_stack: [max_include_depth]IncludeFrame = undefined,
    include_depth: usize = 0,
    error_location: ?ErrorLocation = null,
    name_buffer_index: usize = 0,
    last_created_word: ?u16 = null,
    halted: bool = false,
    /// A byte KEY read for XKEY that did not continue the character, kept here when the
    /// host has no unread_fn; KEY gives it next.
    pending_key: ?u8 = null,
    pending_event_bytes: [32]u8 = undefined,
    pending_event_count: usize = 0,
    pending_standard_event: ?Cell = null,
    block_storage: @import("core/blocks.zig").Storage = .{},
    call_depth: usize = 0,
    /// The callers of the colon definitions that compiled code is running, innermost last
    /// (see executeOperations).
    frames: []CallFrame,
    frame_depth: usize = 0,
    /// CATCH continuations, bounded by the same call limit as colon definitions.
    catches: []CatchContinuation,
    catch_depth: usize = 0,
    /// Where the compiled code was when the last error came up: the operation that
    /// failed and the calls that led to it, innermost first (see recordBacktrace).
    /// `backtrace_total` also counts the ones that did not fit, and `backtrace_level` is
    /// the nesting depth of the executeOperations that added the last ones.
    backtrace: [max_backtrace]u16 = undefined,
    backtrace_count: usize = 0,
    backtrace_total: usize = 0,
    backtrace_level: usize = 0,
    /// After the operation at which the innermost loop of compiled code failed.
    failed_pc: u16 = 0,
    /// Whether `report` shows the backtrace and the stack after the message.
    show_backtrace: bool = true,
    /// The line of the included file each operation was compiled from, 0 for the others,
    /// for the backtrace (none with -Ddebug=false). Not part of an image.
    code_lines: if (defs.debug_enabled) [max_code]u32 else void = if (defs.debug_enabled) @splat(0) else {},
    /// --coverage: an operation that does nothing is compiled where a block of the
    /// coverage words starts, as gforth compiles a counter there; how often it runs is
    /// the count of the block. `code_columns` has, for such an operation, the column of
    /// the block (that of the blank after the word that starts it, counted from 1; 1
    /// for the start of a line) and 0 for the other operations (none with
    /// -Ddebug=false). Not part of an image.
    cover_blocks: bool = false,
    code_columns: if (defs.debug_enabled) [max_code]u16 else void = if (defs.debug_enabled) @splat(0) else {},
    /// --max-steps: how many operations compiled code may run (0: any number), and how
    /// many are left. The host sets `steps_left` again with `resetSteps`.
    step_limit: u64 = 0,
    steps_left: u64 = 0,
    /// --trace: whether the words are shown as they start and end, how many lines the
    /// trace may have (--trace-limit, 0: any number) and has, and how deep the traced
    /// words are nested.
    tracing: bool = false,
    trace_limit: u64 = 0,
    trace_lines: u64 = 0,
    trace_depth: usize = 0,
    /// --profile: the counts of the run, in memory of the host's; null without it.
    profile: ?*Profile = null,
    /// --lint: what the checks keep, in memory of the host's; null without it.
    lint: ?*Lint = null,
    /// Short definitions are called instead of copied into their callers: the trace and
    /// the profile note a word when it is called and when it returns. The host sets it
    /// with --trace or --profile, also in the State that LOAD restores an image in.
    plain_calls: bool = false,
    /// The single-step debugger (DBG, BREAK:): `armed` until the word DBG named starts,
    /// `on` while a definition is stepped through. The steps are those of the
    /// definition running at the nesting depth `step_depth`, which `n` makes deeper
    /// than `step_base`, where they started. `step_result` is whether the stack the
    /// last operation left is still to be shown.
    stepper: enum { off, armed, on } = .off,
    step_word: u16 = 0,
    step_depth: usize = 0,
    step_base: usize = 0,
    step_result: bool = false,
    step_after_cr: bool = false,
    /// The end of the copied code of a short definition that the steps run through
    /// without stopping; 0 when there is none.
    step_skip_end: u16 = 0,
    /// The ends of the copied code of the short definitions that `n` went into, the
    /// innermost last, where `u` leads.
    step_inline_ends: [8]u16 = undefined,
    step_inline_count: usize = 0,
    /// Whether the loop that counts operations runs the innermost compiled code, and
    /// whether all compiled code is to run in it from now on (after a DBG or a BREAK:).
    /// With that, a loop that does not count never runs inside one that does.
    in_counted: bool = false,
    keep_counting: bool = false,
    /// What `report` writes for an error while it is kept for the log (--debug-log).
    report_text: [240]u8 = undefined,
    report_len: usize = 0,
    report_capturing: bool = false,
    /// The cells of WATCH, each with the value it had when it was last looked at. The
    /// loop that counts operations looks at them after each operation. Not part of an
    /// image.
    cell_watches: [8]struct { address: Cell, value: Cell } = undefined,
    cell_watch_count: usize = 0,
    /// +LTRACE: each line of an included file is shown before it is interpreted.
    line_trace: bool = false,
    /// The values of ~~VALUE, whose TOs are shown. Not part of an image.
    watched: [32]u16 = undefined,
    watched_count: usize = 0,
    /// After the operation of compiled code that last called a word or a built-in word
    /// through the host, 0 when the interpreter did: who starts an executeOperations.
    outer_pc: u16 = 0,
    last_unknown_word: ?[]const u8 = null,
    throw_code: Cell = 0,
    /// The counted string of the ABORT" that threw -2, for its message.
    abort_message: ?Cell = null,
    input_file: ?Cell = null,
    output_file: ?Cell = null,
    output_error: ?Cell = null,
    capture_target: ?Cell = null,
    /// Private, nestable macro output capture; never serialized.
    capture_sink: ?*@import("core/macro_substitute.zig").Captured = null,
    /// Borrowed SH-GET result; not an implicit image root.
    sh_get_result: ?@import("core/dynamic_strings.zig").StringRef = null,
    /// The status of the last successful SYSTEM/SH-GET, for $?.
    system_status: Cell = 0,
    capture_failed: bool = false,
    tmp_string_index: usize = 0,
    locals: [max_locals]Local = undefined,
    local_count: usize = 0,
    /// Frame bytes used so far by the definition being compiled.
    locals_frame_size: u16 = 0,
    locals_top: Cell = 0,
    /// The graphics image that GFX-INIT got from the host, and its size; empty until then.
    /// It is not part of the dictionary, so images do not keep it.
    gfx_pixels: []u32 = &.{},
    gfx_width: Cell = 0,
    gfx_height: Cell = 0,
    /// The images of the pool (graphics_images.zig), the bytes they have in all, and the
    /// handle of the image the drawing words draw on (0, the screen, at first). Not part
    /// of the dictionary either.
    gfx_images: [graphics_images.max_images]graphics_images.Slot = @splat(.{}),
    gfx_images_bytes: usize = 0,
    gfx_target: Cell = graphics_images.screen,
    /// The Forth source REQUIRE-GRAPHICS interprets; tests put other source here.
    /// Empty in a build without graphics, which leaves the library text out.
    graphics_library: []const u8 = if (defs.graphics_enabled) words_graphics.library else "",
    /// The Forth source REQUIRE-GUI interprets (empty in a build without graphics).
    gui_library: []const u8 = if (defs.graphics_enabled) @import("core/words_gui.zig").library else "",
    /// The Forth source REQUIRE-GAME interprets (empty in a build without graphics).
    game_library: []const u8 = if (defs.graphics_enabled) @import("core/words_game.zig").library else "",
    /// The Forth source REQUIRE-AUDIO interprets (empty in a build without audio).
    audio_library: []const u8 = if (defs.audio_enabled) words_audio.library else "",
    /// What each voice of PLAY keeps from one PLAY to the next; BEEP resets it.
    audio_voices: [sound_engine.max_voices]sound_mml.Voice = @splat(.{}),
    /// The instruments, as the audio thread has them, and the one INSTRUMENT chose to
    /// change.
    audio_instruments: [sound_mml.instrument_count]sound_engine.Instrument = @splat(.{}),
    audio_instrument: u8 = 0,
    /// The samples, as the audio thread has them, and how much of the host's pool they
    /// take (FREE-SAMPLES empties it).
    audio_samples: [sound_engine.pcm.sample_count]sound_engine.pcm.Sample = @splat(.{}),
    audio_pool_used: u32 = 0,
    /// One band of six rows of a Sixel image, as color registers (none in a build without
    /// graphics).
    gfx_band: if (defs.graphics_enabled) [6][graphics_terminal.max_sixel_width]u8 else void = undefined,
    /// The coverage of the glyph TEXT loaded last (none in a build without graphics).
    gfx_glyph_alpha: if (defs.graphics_enabled) graphics_font.Alpha else void = undefined,
    /// The source of the embedded file being included (the graphics library).
    embedded_source: []const u8 = &.{},
    /// Keys and the mouse for INKEY and MOUSE, and where SHOW put the image on the
    /// terminal.
    gfx_input: graphics_input.InputState = .{},
    /// The Tcl program of TCL and DISPLAY-TK (none in a build without graphics).
    tcl: if (defs.graphics_enabled) tcl.TclState else void = if (defs.graphics_enabled) .{} else {},
    /// The colors SHOW uses (GFX-COLOR-MODE).
    gfx_color_mode: graphics_palette.ColorMode = .{},
    /// WINDOW-SIZE: the size of the part of the window that shows the image, 0 0 for
    /// the image's own size.
    gfx_window_size: [2]u32 = .{ 0, 0 },
    gamepads: @import("core/gamepad.zig").Snapshot = .{},
    /// TEXT's font and the glyph it loaded last (none in a build without graphics).
    gfx_font: if (defs.graphics_enabled) graphics_font.FontState else void = if (defs.graphics_enabled) .{} else {},
    /// The bytes written to the host so far: SHOW draws over its last image on the
    /// terminal when nothing was written after it.
    output_count: u64 = 0,

    /// Sets up a State where it lies. The State is a few megabytes, so it is built in
    /// place rather than returned by value, which could need copies on the stack.
    pub fn init(self: *State, writer: Writer, given: Storage) void {
        self.* = .{ .writer = writer, .sizes = given.sizes, .locals_top = given.sizes.localsBase(), .memory = given.memory, .data_stack = given.data_stack, .return_stack = given.return_stack, .float_stack = given.float_stack, .loop_stack = given.loop_stack, .frames = given.frames, .catches = given.catches };
        // P00: use host epoch microseconds when available; a clockless/failing host uses 0.
        if (writer.utime_fn) |now| self.random_state = @truncate(@as(u128, @bitCast(now(writer.context) catch 0)));
        self.writeCell(base_address, 10) catch unreachable;
        self.writeCell(precision_address, dot_precision) catch unreachable;
        self.writeCell(memory_map.dpl_address, -1) catch unreachable;
        self.writeCell(memory_map.fpath_address, 0) catch unreachable;
        self.writeCell(memory_map.csv_quote_address, 34) catch unreachable;
        self.writeCell(memory_map.csv_separator_address, 44) catch unreachable;
        for (@import("core/standard_keys.zig").names, 0..) |name, index| {
            const at: usize = @intCast(memory_map.key_name_base + @as(Cell, @intCast(@import("core/standard_keys.zig").nameOffset(index))));
            @memcpy(self.memory[at..][0..name.len], name);
        }
        self.writeCell(heap_top_address, self.sizes.heapBase()) catch unreachable;
        self.storeSourceName(terminal_source_name_address, terminal_source_name);
        self.storeSourceName(evaluate_source_name_address, evaluate_source_name);
        self.memory[@intCast(memory_map.newline_address)] = 10;
        // gforth starts with the search order Forth Forth Root and defines into Forth.
        self.writeCell(wordlist_count_address, memory_map.ekeys_wordlist) catch unreachable;
        self.writeCell(current_wordlist_address, forth_wordlist) catch unreachable;
        self.setSearchOrder(&.{ forth_wordlist, forth_wordlist, memory_map.ekeys_wordlist, root_wordlist });
        self.installBuiltins();
    }

    /// The memory and the stacks given to `init`, for the host to free.
    pub fn storage(self: *const State) Storage {
        return .{ .sizes = self.sizes, .memory = self.memory, .data_stack = self.data_stack, .return_stack = self.return_stack, .float_stack = self.float_stack, .loop_stack = self.loop_stack, .frames = self.frames, .catches = self.catches };
    }

    /// Writes interpreter output, or appends it to the string being built by $TMP.
    pub fn write(self: *State, bytes: []const u8) void {
        if (self.capture_sink) |sink| {
            if (!self.capture_failed) sink.put(self, bytes) catch {
                self.capture_failed = true;
            };
            return;
        }
        if (self.capture_target) |target| {
            self.appendString(target, bytes) catch {
                self.capture_failed = true;
            };
            return;
        }
        if (self.output_file) |fileid| {
            if (self.output_error != null) return;
            const files = self.fileOps() catch {
                self.output_error = memory_map.errnoIor(memory_map.errno_bad_file);
                return;
            };
            const ior = files.write(self.writer.context, fileid, bytes);
            // Explicit STDOUT still changes the terminal that SHOW tracks.
            // Count even a failed write: the host may have emitted a prefix.
            if (fileid == memory_map.stdout_fileid) self.output_count +%= bytes.len;
            if (ior != 0) self.output_error = ior;
            return;
        }
        // The message of an error, for the log of --debug-log.
        if (defs.debug_enabled and self.report_capturing) {
            const count = @min(bytes.len, self.report_text.len - self.report_len);
            @memcpy(self.report_text[self.report_len..][0..count], bytes[0..count]);
            self.report_len += count;
        }
        self.output_count +%= bytes.len;
        self.writer.write(bytes);
    }

    pub const imageCapacity = dictionary_image.imageCapacity;
    pub const encodeImage = dictionary_image.encodeImage;
    pub const restoreImage = dictionary_image.restoreImage;
    pub const restoreFreshImage = dictionary_image.restoreFreshImage;
    pub const imageLayout = dictionary_image.imageLayout;
    pub const encodedSize = dictionary_image.encodedSize;
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
        const start = @intFromPtr(self.memory.ptr);
        const address = @intFromPtr(self.source_line.ptr);
        if (self.source_line.len == 0 or address < start or address >= start + self.memory.len) return 0;
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
        const previous_blk = self.readCellConst(memory_map.blk_address);
        if (source_kind != .block) try self.writeCell(memory_map.blk_address, 0);
        const previous_serial = self.input_line_serial;
        self.source_line = input;
        self.setSourceCursor(0);
        self.source_kind = source_kind;
        self.numberInputLine();
        // --coverage: a line of a file that goes on with a definition starts a block,
        // as in gforth.
        if (defs.debug_enabled and self.cover_blocks and source_kind == .file and self.compiling and self.defining) self.markBlock(1);
        // A nested file or EVALUATE string runs inside the caller's work, so it must not
        // drop the word that a pending DOES> will attach to.
        if (source_kind == .terminal) self.last_created_word = null;
        const pending_before = self.pending;
        const quote_before = self.quote_depth;
        errdefer @import("core/quotations.zig").abort(self);
        defer {
            self.source_line = previous_line;
            self.setSourceCursor(previous_cursor);
            self.source_kind = previous_kind;
            self.writeCell(memory_map.blk_address, previous_blk) catch unreachable;
            self.input_line_serial = previous_serial;
        }
        self.last_unknown_word = null;
        var line = input;
        var cursor: usize = 0;
        while (true) {
            // WATCH: what the word before this one changed, however it was handled
            // (a word of its own, a name that a defining word was waiting for, a
            // string).
            if (defs.debug_enabled and self.cell_watch_count != 0) words_debug.checkWatches(self, null);
            if (self.source_kind == .block) {
                self.source_line = try @import("core/blocks.zig").currentSource(self);
                line = self.source_line;
            }
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
                // --lint: the comment after the name of a colon definition is its
                // stack comment.
                if (defs.debug_enabled) if (self.lint) |lint| {
                    if (self.defining and self.compiling and self.words[self.current_word].kind == .colon and self.code_count == self.words[self.current_word].code_start + @intFromBool(self.cover_blocks)) lint.declare(self.current_word, line[cursor..close]);
                };
                cursor = close + 1;
                continue;
            }
            if (std.mem.eql(u8, token, "\\")) {
                if (self.source_kind != .block) break;
                cursor = @min(line.len, (self.token_start / 64 + 1) * 64);
                self.setSourceCursor(cursor);
                continue;
            }
            if (self.postponing) {
                try @import("core/quotations.zig").token(self, token);
                cursor = self.sourceCursor();
                continue;
            }
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
        if ((source_kind == .evaluate or source_kind == .block) and self.quote_depth > quote_before) return error.InvalidDefinition;
        // An EVALUATE string cannot read past its end, so a parsing word such as
        // VARIABLE or : left waiting for its name must not take the caller's next word.
        if ((source_kind == .evaluate or source_kind == .block) and pending_before == .none and self.pending != .none) {
            self.pending = .none;
            return error.InvalidDefinition;
        }
    }

    /// The names of the built-in words. A build without floating-point words skips those.
    pub const builtin_definitions = [_]struct { []const u8, Builtin }{
        .{ "DROP", .drop },                           .{ "DUP", .dup },                               .{ "SWAP", .swap },                                 .{ "OVER", .over },                            .{ "ROT", .rot },
        .{ "-ROT", .minus_rot },                      .{ "NIP", .nip },                               .{ "TUCK", .tuck },                                 .{ "PICK", .pick },                            .{ "ROLL", .roll },
        .{ "2DUP", .two_dup },                        .{ "2DROP", .two_drop },                        .{ "2SWAP", .two_swap },                            .{ "2OVER", .two_over },                       .{ "DEPTH", .depth },
        .{ ">R", .to_r },                             .{ "R>", .from_r },                             .{ "R@", .r_fetch },                                .{ "+", .add },                                .{ "-", .sub },
        .{ "*", .mul },                               .{ "/", .div },                                 .{ "MOD", .mod },                                   .{ "/MOD", .div_mod },                         .{ "MINUS", .negate },
        .{ "NEGATE", .negate },                       .{ "ABS", .abs },                               .{ "1+", .one_plus },                               .{ "1-", .one_minus },                         .{ "2*", .two_star },
        .{ "2/", .two_slash },                        .{ "MAX", .max },                               .{ "MIN", .min },                                   .{ "=", .equal },                              .{ "<>", .not_equal },
        .{ "<", .less },                              .{ ">", .greater },                             .{ "<=", .less_equal },                             .{ ">=", .greater_equal },                     .{ "NOT", .logical_not },
        .{ "0=", .zero_equal },                       .{ "0<", .zero_less },                          .{ "0>", .zero_greater },                           .{ "0<>", .zero_not_equal },                   .{ "AND", .bit_and },
        .{ "OR", .bit_or },                           .{ "XOR", .bit_xor },                           .{ "COM", .bit_complement },                        .{ "INVERT", .bit_complement },                .{ "NAND", .bit_nand },
        .{ "NOR", .bit_nor },                         .{ "SWAB", .swap_bytes },                       .{ "LSHIFT", .lshift },                             .{ "RSHIFT", .rshift },                        .{ "TRUE", .true_value },
        .{ "FALSE", .false_value },                   .{ "BL", .blank },                              .{ "CELL", .cell },                                 .{ "CELLS", .cells },                          .{ "CELL+", .cell_plus },
        .{ "ALIGNED", .aligned },                     .{ "@", .fetch },                               .{ "!", .store },                                   .{ ",", .comma },                              .{ "C,", .c_comma },
        .{ "EXECUTE", .execute },                     .{ "C@", .cfetch },                             .{ "C!", .cstore },                                 .{ "+!", .add_store },                         .{ "1+!", .inc_store },
        .{ "1-!", .dec_store },                       .{ "OSET", .zero_store },                       .{ "ON", .on },                                     .{ "OFF", .off },                              .{ "?", .question },
        .{ "A@", .array_fetch },                      .{ "A!", .array_store },                        .{ "ERASE", .erase },                               .{ "FILL", .fill },                            .{ "MOVE", .move },
        .{ "CMOVE", .cmove },                         .{ ".", .dot },                                 .{ "U.", .u_dot },                                  .{ "C.", .c_dot },                             .{ ".S", .dot_s },
        .{ "ECHO", .echo },                           .{ "EMIT", .echo },                             .{ "CR", .cr },                                     .{ "SPACE", .space },                          .{ "SPCES", .spaces },
        .{ "SPACES", .spaces },                       .{ "TYPE", .type },                             .{ "HEX", .hex },                                   .{ "DEC", .dec },                              .{ "DECIMAL", .dec },
        .{ "OCT", .oct },                             .{ "BASE", .base },                             .{ "HERE", .here },                                 .{ "ALLOT", .allot },                          .{ "I", .index },
        .{ "J", .index_2 },                           .{ "K", .index_3 },                             .{ "LEAVE", .leave },                               .{ "UNLOOP", .unloop },                        .{ "WORDS", .words },
        .{ "BYE", .bye },                             .{ "INPUT", .input },                           .{ "<BUILDS", .builds },                            .{ "CREATE", .builds },                        .{ "IMMEDIATE", .immediate },
        .{ "LOAD-DICTIONARY", .load },                .{ "SAVE", .save },                             .{ "SAVESYS", .savesys },                           .{ "IF", .compile_if },                        .{ "ELSE", .compile_else },
        .{ "THEN", .compile_then },                   .{ "BEGIN", .compile_begin },                   .{ "END", .compile_end },                           .{ "UNTIL", .compile_end },                    .{ "AGAIN", .compile_again },
        .{ "WHILE", .compile_while },                 .{ "REPEAT", .compile_repeat },                 .{ "DO", .compile_do },                             .{ "?DO", .compile_q_do },                     .{ "LOOP", .compile_loop },
        .{ "+LOOP", .compile_plus_loop },             .{ "DOES>", .compile_does },                    .{ "CASE", .compile_case },                         .{ "OF", .compile_of },                        .{ "ENDOF", .compile_endof },
        .{ "ENDCASE", .compile_endcase },             .{ "EXIT", .compile_exit },                     .{ "RECURSE", .compile_recurse },                   .{ "FDROP", .f_drop },                         .{ "FDUP", .f_dup },
        .{ "FSWAP", .f_swap },                        .{ "FOVER", .f_over },                          .{ "FROT", .f_rot },                                .{ "F-ROT", .f_minus_rot },                    .{ "FNIP", .f_nip },
        .{ "FTUCK", .f_tuck },                        .{ "FPICK", .f_pick },                          .{ "FDEPTH", .f_depth },                            .{ "F.S", .f_dot_s },                          .{ "F+", .f_add },
        .{ "F-", .f_sub },                            .{ "F*", .f_mul },                              .{ "F/", .f_div },                                  .{ "FNEGATE", .f_negate },                     .{ "FMINUS", .f_negate },
        .{ "FABS", .f_abs },                          .{ "FMAX", .f_max },                            .{ "FMIN", .f_min },                                .{ "FSQRT", .f_sqrt },                         .{ "FEXP", .f_exp },
        .{ "FLN", .f_ln },                            .{ "FSIN", .f_sin },                            .{ "FCOS", .f_cos },                                .{ "FTAN", .f_tan },                           .{ "F=", .f_equal },
        .{ "F<>", .f_not_equal },                     .{ "F<", .f_less },                             .{ "F>", .f_greater },                              .{ "F<=", .f_less_equal },                     .{ "F>=", .f_greater_equal },
        .{ "F0=", .f_zero_equal },                    .{ "F0<>", .f_zero_not_equal },                 .{ "F0<", .f_zero_less },                           .{ "F0>", .f_zero_greater },                   .{ "F0<=", .f_zero_less_equal },
        .{ "F0>=", .f_zero_greater_equal },           .{ "F@", .f_fetch },                            .{ "F!", .f_store },                                .{ "F,", .f_comma },                           .{ "FA@", .f_array_fetch },
        .{ "FA!", .f_array_store },                   .{ "F+!", .f_add_store },                       .{ "F?", .f_question },                             .{ "FLOATS", .floats },                        .{ "FLOAT+", .float_plus },
        .{ "S>F", .s_to_f },                          .{ "F>S", .f_to_s },                            .{ "F.", .f_dot },                                  .{ "FINPUT", .f_input },                       .{ "S>D", .s_to_d },
        .{ "D>S", .d_to_s },                          .{ "D+", .d_add },                              .{ "D-", .d_sub },                                  .{ "DNEGATE", .d_negate },                     .{ "DABS", .d_abs },
        .{ "D0=", .d_zero_equal },                    .{ "D0<", .d_zero_less },                       .{ "D=", .d_equal },                                .{ "D<", .d_less },                            .{ "D.", .d_dot },
        .{ "2@", .two_fetch },                        .{ "2!", .two_store },                          .{ "D>F", .d_to_f },                                .{ "F>D", .f_to_d },                           .{ "COUNT", .count },
        .{ "BLK", .blk },                             .{ "SCR", .scr },                               .{ "LOAD", .load_block },                           .{ "THRU", .thru },                            .{ "LIST", .list_block },
        .{ "BLOCK", .block },                         .{ "BUFFER", .block_buffer },                   .{ "UPDATE", .block_update },                       .{ "SAVE-BUFFERS", .save_buffers },            .{ "EMPTY-BUFFERS", .empty_buffers },
        .{ "FLUSH", .flush_buffers },                 .{ "PAD", .pad },                               .{ "ACCEPT", .accept },                             .{ "EVALUATE", .evaluate },                    .{ "KEY", .key },
        .{ "KEY?", .key_question },                   .{ "<#", .hold_start },                         .{ "<<#", .hold_nest },                             .{ "#", .hold_digit },                         .{ "#S", .hold_digits },
        .{ "#>", .hold_finish },                      .{ "#>>", .hold_release },                      .{ "HOLD", .hold },                                 .{ "HOLDS", .holds },                          .{ "SIGN", .sign },
        .{ ">NUMBER", .to_number },                   .{ "S>NUMBER?", .string_to_number },            .{ ">FLOAT", .to_float },                           .{ "WITHIN", .within },                        .{ "2>R", .two_to_r },
        .{ "2R>", .two_r_from },                      .{ "ENDIF", .compile_then },                    .{ "PLACE", .place },                               .{ "ABORT", .abort },                          .{ "MS", .ms },
        .{ "UTIME", .utime },                         .{ "PAGE", .page },                             .{ "GETENV", .getenv },                             .{ "SYSTEM", .system },                        .{ "STATE", .state },
        .{ "THROW", .throw },                         .{ "R/O", .read_only },                         .{ "W/O", .write_only },                            .{ "R/W", .read_write },                       .{ "STDIN", .stdin },
        .{ "STDOUT", .stdout },                       .{ "STDERR", .stderr },                         .{ "OPEN-FILE", .open_file },                       .{ "CREATE-FILE", .create_file },              .{ "CLOSE-FILE", .close_file },
        .{ "READ-LINE", .read_line },                 .{ "WRITE-LINE", .write_line },                 .{ "WRITE-FILE", .write_file },                     .{ "FILE-SIZE", .file_size },                  .{ "REPOSITION-FILE", .reposition_file },
        .{ "ALLOCATE", .allocate },                   .{ "FREE", .free },                             .{ "RESIZE", .resize },                             .{ "$!", .string_store },                      .{ "$@", .string_fetch },
        .{ "$@LEN", .string_fetch_len },              .{ "$!LEN", .string_store_len },                .{ "$+!", .string_append },                         .{ "C$+!", .char_append },                     .{ "$.", .string_dot },
        .{ "$DEL", .string_delete },                  .{ "$INS", .string_insert },                    .{ "$OVER", .string_over },                         .{ "$FREE", .string_free },                    .{ "$INIT", .string_init },
        .{ "$SPLIT", .string_split },                 .{ "$ITER", .string_iter },                     .{ "$TMP", .string_tmp },                           .{ "$[]", .string_array },                     .{ "$[]!", .string_array_store },
        .{ "$[]@", .string_array_fetch },             .{ "$[]#", .string_array_count },               .{ "$[].", .string_array_dot },                     .{ "$[]MAP", .string_array_map },              .{ "$[]FREE", .string_array_free },
        .{ "$[]SLURP", .string_array_slurp },         .{ "$[]SLURP-FILE", .string_array_slurp_file }, .{ "CATCH", .catch_word },                          .{ "WORD", .word_parse },                      .{ "FIND", .find_word },
        .{ "PARSE", .parse },                         .{ "FIND-NAME", .find_name },                   .{ "NAME>INT", .name_to_int },                      .{ "NAME>STRING", .name_to_string },           .{ "SEE", .see },
        .{ "INCLUDE", .include },                     .{ "INCLUDED", .included },                     .{ "REQUIRE", .require },                           .{ "NEEDS", .require },                        .{ "REQUIRED", .required },
        .{ "INCLUDED?", .included_query },            .{ "SOURCEFILENAME", .source_file_name },       .{ "SOURCELINE#", .source_line_number },            .{ "MARKER", .marker },                        .{ "LOCATE", .locate },
        .{ "WHERE", .where },                         .{ "DEFER", .define_defer },                    .{ "DEFER!", .defer_store },                        .{ "DEFER@", .defer_fetch },                   .{ "DEFERS", .defers },
        .{ "COMPILE,", .compile_comma },              .{ "[COMPILE]", .bracket_compile },             .{ "NAME>COMPILE", .name_to_compile },              .{ "BEGIN-STRUCTURE", .begin_structure },      .{ "END-STRUCTURE", .end_structure },
        .{ "+FIELD", .plus_field },                   .{ "FIELD:", .field_cell },                     .{ "CFIELD:", .field_char },                        .{ "FFIELD:", .field_float },                  .{ "SFFIELD:", .field_sfloat },
        .{ "DFFIELD:", .field_dfloat },               .{ "STRUCT", .struct_start },                   .{ "END-STRUCT", .end_struct },                     .{ "FIELD", .struct_field },                   .{ "CELL%", .cell_percent },
        .{ "CHAR%", .char_percent },                  .{ "FLOAT%", .float_percent },                  .{ "DOUBLE%", .double_percent },                    .{ "SFLOAT%", .sfloat_percent },               .{ "DFLOAT%", .dfloat_percent },
        .{ "%SIZE", .percent_size },                  .{ "%ALIGNMENT", .percent_alignment },          .{ "%ALIGN", .percent_align },                      .{ "%ALLOT", .percent_allot },                 .{ "%ALLOC", .percent_alloc },
        .{ "%ALLOCATE", .percent_allocate },          .{ "?EXIT", .question_exit },                   .{ "NOOP", .noop },                                 .{ "PERFORM", .perform },                      .{ "?LEAVE", .question_leave },
        .{ "CELL-", .cell_minus },                    .{ "UNDER+", .under_plus },                     .{ "0>=", .zero_greater_equal },                    .{ "?OF", .compile_question_of },              .{ "CONTOF", .compile_contof },
        .{ "NEXT-CASE", .compile_next_case },         .{ "ONLY", .only },                             .{ "ALSO", .also },                                 .{ "PREVIOUS", .previous },                    .{ "FORTH", .forth },
        .{ "DEFINITIONS", .definitions },             .{ "ORDER", .order },                           .{ "GET-ORDER", .get_order },                       .{ "SET-ORDER", .set_order },                  .{ ">ORDER", .to_order },
        .{ "GET-CURRENT", .get_current },             .{ "SET-CURRENT", .set_current },               .{ "VOCABULARY", .vocabulary },                     .{ "WORDLIST", .wordlist },                    .{ "FORTH-WORDLIST", .forth_wordlist_word },
        .{ "SEARCH-WORDLIST", .search_wordlist },     .{ "[IF]", .bracket_if },                       .{ "[ELSE]", .bracket_else },                       .{ "[THEN]", .bracket_then },                  .{ "[DEFINED]", .bracket_defined },
        .{ "[UNDEFINED]", .bracket_undefined },       .{ "F.RDP", .f_dot_rdp },                       .{ "F>STR-RDP", .f_to_str_rdp },                    .{ "F>BUF-RDP", .f_to_buf_rdp },               .{ ":", .define_colon },
        .{ ";", .end_definition },                    .{ "VARIABLE", .define_variable },              .{ "VAR", .define_variable },                       .{ "FVARIABLE", .define_fvariable },           .{ "CONSTANT", .define_constant },
        .{ "CONST", .define_constant },               .{ "VALUE", .define_value },                    .{ "2VARIABLE", .define_two_variable },             .{ "2CONSTANT", .define_two_constant },        .{ "FCONSTANT", .define_fconstant },
        .{ "ARRAY", .define_array },                  .{ "FARRAY", .define_array },                   .{ "PI", .pi },                                     .{ "'", .tick },                               .{ ">BODY", .to_body },
        .{ "LITERAL", .literal },                     .{ "FLITERAL", .fliteral },                     .{ "HELP", .help },                                 .{ "LICENSE", .license },                      .{ "COMPARE", .compare },
        .{ "SEARCH", .search },                       .{ "/STRING", .slash_string },                  .{ "-TRAILING", .minus_trailing },                  .{ "CHAR+", .char_plus },                      .{ "CHARS", .chars },
        .{ "BOUNDS", .bounds },                       .{ "BLANK", .blank_fill },                      .{ "CMOVE>", .cmove_up },                           .{ "SCAN", .scan },                            .{ "SKIP", .skip },
        .{ "STR=", .str_equal },                      .{ "STRING-PREFIX?", .string_prefix_query },    .{ "+PLACE", .plus_place },                         .{ "SLITERAL", .sliteral },                    .{ "PARSE-NAME", .parse_name },
        .{ "SLURP-FILE", .slurp_file },               .{ "$SLURP-FILE", .string_slurp_file },         .{ "$SLURP", .string_slurp },                       .{ "$+SLURP", .string_plus_slurp },            .{ "$+SLURP-FILE", .string_plus_slurp_file },
        .{ "$SLURP-LINE", .string_slurp_line },       .{ "$+!LEN", .string_plus_store_len },          .{ "$[]+!", .string_array_append },                 .{ "$+[]!", .string_append_array },            .{ "$EXEC", .string_exec },
        .{ "$?", .system_status },                    .{ "$OFF", .string_free },                      .{ "$VARIABLE", .define_variable },                 .{ "$[]VARIABLE", .define_variable },          .{ "?DUP", .question_dup },
        .{ "2R@", .two_r_fetch },                     .{ "U<", .u_less },                             .{ "U>", .u_greater },                              .{ "ALIGN", .align_here },                     .{ ".R", .dot_r },
        .{ "U.R", .u_dot_r },                         .{ "UNUSED", .unused },                         .{ "*/", .star_slash },                             .{ "*/MOD", .star_slash_mod },                 .{ "M*", .m_star },
        .{ "UM*", .um_star },                         .{ "UM/MOD", .um_slash_mod },                   .{ "FM/MOD", .fm_slash_mod },                       .{ "SM/REM", .sm_slash_rem },                  .{ "READ-FILE", .read_file },
        .{ "FLOOR", .f_floor },                       .{ "FTRUNC", .f_trunc },                        .{ "FROUND", .f_round },                            .{ "FE.", .f_e_dot },                          .{ "FS.", .f_s_dot },
        .{ "PRECISION", .precision },                 .{ "SET-PRECISION", .set_precision },           .{ "F~", .f_proximate },                            .{ "SF@", .sf_fetch },                         .{ "SF!", .sf_store },
        .{ "DF@", .df_fetch },                        .{ "DF!", .df_store },                          .{ "SFLOATS", .sfloats },                           .{ "DFLOATS", .dfloats },                      .{ "SFLOAT+", .sfloat_plus },
        .{ "DFLOAT+", .dfloat_plus },                 .{ "FALIGN", .f_align },                        .{ "FALIGNED", .f_aligned },                        .{ "SFALIGN", .sf_align },                     .{ "SFALIGNED", .sf_aligned },
        .{ "DFALIGN", .df_align },                    .{ "DFALIGNED", .df_aligned },                  .{ "FSINCOS", .f_sincos },                          .{ "FASIN", .f_asin },                         .{ "FACOS", .f_acos },
        .{ "FATAN", .f_atan },                        .{ "FATAN2", .f_atan2 },                        .{ "FSINH", .f_sinh },                              .{ "FCOSH", .f_cosh },                         .{ "FTANH", .f_tanh },
        .{ "FASINH", .f_asinh },                      .{ "FACOSH", .f_acosh },                        .{ "FATANH", .f_atanh },                            .{ "FEXPM1", .f_expm1 },                       .{ "FLNP1", .f_lnp1 },
        .{ "FLOG", .f_log },                          .{ "FALOG", .f_alog },                          .{ "F**", .f_power },                               .{ "FVALUE", .define_fvalue },                 .{ "2VALUE", .define_two_value },
        .{ "BUFFER:", .define_buffer },               .{ "2LITERAL", .two_literal },                  .{ "D.R", .d_dot_r },                               .{ "D2*", .d_two_star },                       .{ "D2/", .d_two_slash },
        .{ "DMAX", .d_max },                          .{ "DMIN", .d_min },                            .{ ">IN", .to_in },                                 .{ "SOURCE", .source },                        .{ "SOURCE-ID", .source_id },
        .{ "REFILL", .refill },                       .{ "AHEAD", .compile_ahead },                   .{ "N>R", .n_to_r },                                .{ "NR>", .n_r_from },                         .{ "AT-XY", .at_xy },
        .{ "TIME&DATE", .time_and_date },             .{ "SYNONYM", .synonym },                       .{ "TRAVERSE-WORDLIST", .traverse_wordlist },       .{ "NAME>INTERPRET", .name_to_int },           .{ "CS-PICK", .cs_pick },
        .{ "CS-ROLL", .cs_roll },                     .{ "EKEY", .ekey },                             .{ "EKEY?", .ekey_question },                       .{ "EKEY>CHAR", .ekey_to_char },               .{ "EKEY>FKEY", .ekey_to_fkey },
        .{ "ENVIRONMENT?", .environment_query },      .{ "QUIT", .quit },                             .{ "BIN", .bin },                                   .{ "FILE-POSITION", .file_position },          .{ "RESIZE-FILE", .resize_file },
        .{ "FLUSH-FILE", .flush_file },               .{ "DELETE-FILE", .delete_file },               .{ "RENAME-FILE", .rename_file },                   .{ "FILE-STATUS", .file_status },              .{ "INCLUDE-FILE", .include_file },
        .{ "SAVE-INPUT", .save_input },               .{ "RESTORE-INPUT", .restore_input },           .{ "M*/", .m_star_slash },                          .{ "REPRESENT", .represent },                  .{ "[IFDEF]", .bracket_ifdef },
        .{ "[IFUNDEF]", .bracket_ifundef },           .{ "[ENDIF]", .bracket_then },                  .{ "[DO]", .bracket_do },                           .{ "[?DO]", .bracket_q_do },                   .{ "[LOOP]", .bracket_loop },
        .{ "[+LOOP]", .bracket_plus_loop },           .{ "[I]", .bracket_i },                         .{ "[BEGIN]", .bracket_begin },                     .{ "[UNTIL]", .bracket_until },                .{ "[AGAIN]", .bracket_again },
        .{ "[WHILE]", .bracket_while },               .{ "[REPEAT]", .bracket_repeat },               .{ "[FOR]", .bracket_for },                         .{ "[NEXT]", .bracket_next },                  .{ "M+", .m_plus },
        .{ "DU<", .du_less },                         .{ "2ROT", .two_rot },                          .{ "DUMP", .dump },                                 .{ "ARGC", .argc },                            .{ "ARGV", .argv },
        .{ "ARG", .arg },                             .{ "SHIFT-ARGS", .shift_args },                 .{ "NEXT-ARG", .next_arg },                         .{ "XC-SIZE", .xc_size },                      .{ "X-SIZE", .x_size },
        .{ "XC@+", .xc_fetch_plus },                  .{ "XC@", .xc_fetch },                          .{ "XC!+", .xc_store_plus },                        .{ "XC!+?", .xc_store_plus_question },         .{ "XC,", .xc_comma },
        .{ "XCHAR+", .xchar_plus },                   .{ "XCHAR-", .xchar_minus },                    .{ "XEMIT", .xemit },                               .{ "XKEY", .xkey },                            .{ "XKEY?", .xkey_question },
        .{ "X-WIDTH", .x_width },                     .{ "XC-WIDTH", .xc_width },                     .{ "+X/STRING", .plus_x_string },                   .{ "X\\STRING-", .x_string_minus },            .{ "-TRAILING-GARBAGE", .minus_trailing_garbage },
        .{ "XHOLD", .xhold },                         .{ "EKEY>XCHAR", .ekey_to_xchar },              .{ "X@+/STRING", .x_fetch_plus_string },            .{ "SUBSTITUTE", .substitute },                .{ "REPLACES", .replaces },
        .{ "UNESCAPE", .unescape },                   .{ "$SUBSTITUTE", .string_substitute },         .{ "$UNESCAPE", .string_unescape },                 .{ "LATEST", .latest },                        .{ "LATESTXT", .latestxt },
        .{ ">NAME", .to_name },                       .{ "ID.", .id_dot },                            .{ ".NAME", .id_dot },                              .{ "ALIAS", .alias },                          .{ "~~", .debug_tilde },
        .{ "(~~)", .debug_tilde_run },                .{ "ASSERT(", .assert_paren },                  .{ "(ASSERT)", .assert_run },                       .{ "EMIT?", .emit_question },                  .{ "(LOCAL)", .paren_local },
        .{ "+LTRACE", .ltrace_on },                   .{ "-LTRACE", .ltrace_off },                    .{ "ONCE", .once },                                 .{ "(ONCE)", .once_run },                      .{ "~~BT", .debug_tilde_bt },
        .{ "(~~BT)", .debug_tilde_bt_run },           .{ "~~1BT", .debug_tilde_one_bt },              .{ "~~VALUE", .define_watched_value },              .{ "(~~TO)", .watch_run },                     .{ "DBG", .dbg },
        .{ "BREAK:", .break_colon },                  .{ "(BREAK:)", .break_run },                    .{ "BREAK\"", .break_quote },                       .{ "(BREAK\")", .break_quote_run },            .{ ".COVER-RAW", .cover_raw },
        .{ "COV%", .cov_percent },                    .{ ".COVERAGE", .coverage },                    .{ "~~VARIABLE", .define_watched_variable },        .{ "WATCH", .watch_cell },                     .{ "UNWATCH", .unwatch_cell },
        .{ "0<=", .zero_less_equal },                 .{ "D0<=", .d_zero_less_equal },                .{ "D0<>", .d_zero_not_equal },                     .{ "D0>", .d_zero_greater },                   .{ "D0>=", .d_zero_greater_equal },
        .{ "D<=", .d_less_equal },                    .{ "D<>", .d_not_equal },                       .{ "D>", .d_greater },                              .{ "D>=", .d_greater_equal },                  .{ "DU<=", .du_less_equal },
        .{ "DU>", .du_greater },                      .{ "DU>=", .du_greater_equal },                 .{ "U<=", .u_less_equal },                          .{ "U>=", .u_greater_equal },                  .{ "UMAX", .u_max },
        .{ "UMIN", .u_min },                          .{ "2NIP", .two_nip },                          .{ "2RDROP", .two_r_drop },                         .{ "2TUCK", .two_tuck },                       .{ "FOURTH", .fourth },
        .{ "RDROP", .r_drop },                        .{ "THIRD", .third },                           .{ "2,", .two_comma },                              .{ "ROL", .rol },                              .{ "ROR", .ror },
        .{ "*/F", .star_slash_f },                    .{ "*/MODF", .star_slash_mod_f },               .{ "*/MODS", .star_slash_mod_s },                   .{ "*/S", .star_slash_s },                     .{ "/F", .slash_f },
        .{ "/MODF", .slash_mod_f },                   .{ "/MODS", .slash_mod_s },                     .{ "/S", .slash_s },                                .{ ">POW2", .to_pow2 },                        .{ "CTZ", .ctz },
        .{ "DROL", .drol },                           .{ "DROR", .dror },                             .{ "DU/MOD", .du_slash_mod },                       .{ "LOG2", .log2 },                            .{ "LROL", .lrol },
        .{ "LROR", .lror },                           .{ "MODF", .mod_f },                            .{ "MODS", .mod_s },                                .{ "MUX", .mux },                              .{ "POW2?", .pow2_query },
        .{ "U*/", .u_star_slash },                    .{ "U*/MOD", .u_star_slash_mod },               .{ "U/", .u_slash },                                .{ "U/MOD", .u_slash_mod },                    .{ "UD/MOD", .ud_slash_mod },
        .{ "UMOD", .u_mod },                          .{ "WROL", .wrol },                             .{ "WROR", .wror },                                 .{ "-INF", .negative_inf },                    .{ "-INFINITY", .negative_infinity },
        .{ "1/F", .f_reciprocal },                    .{ "F*+", .f_mul_add },                         .{ "F2*", .f_two_star },                            .{ "F2/", .f_two_slash },                      .{ "FAXPY", .faxpy },
        .{ "FCOPYSIGN", .f_copysign },                .{ "FFOURTH", .f_fourth },                      .{ "FTHIRD", .f_third },                            .{ "F~ABS", .f_approx_abs },                   .{ "F~REL", .f_approx_rel },
        .{ "INF", .positive_inf },                    .{ "INFINITY", .positive_infinity },            .{ "NAN", .nan_value },                             .{ "V*", .vector_dot },                        .{ "ARSHIFT", .arshift },
        .{ "DARSHIFT", .darshift },                   .{ "DLSHIFT", .dlshift },                       .{ "DRSHIFT", .drshift },                           .{ "RANDOM", .random },                        .{ "RND", .rnd },
        .{ "SEED!", .seed_store },                    .{ ">FLOAT1", .to_float1 },                     .{ "BASE-EXECUTE", .base_execute },                 .{ "CONVERT", .convert },                      .{ "DEC.", .decimal_dot },
        .{ "DEC.R", .decimal_dot_r },                 .{ "DPL", .dpl },                               .{ "E.", .e_dot },                                  .{ "E.EXACT", .e_exact },                      .{ "E.P", .e_precision },
        .{ "FP.", .f_prefix_dot },                    .{ "H.", .h_dot },                              .{ "HEX.", .hex_dot },                              .{ "UD.", .ud_dot },                           .{ "UD.R", .ud_dot_r },
        .{ "!@", .exchange_store },                   .{ "*ALIGN", .star_align },                     .{ "*ALIGNED", .star_aligned },                     .{ "+!@", .add_exchange },                     .{ "/L", .slash_l },
        .{ "/W", .slash_w },                          .{ "/X", .slash_x },                            .{ "C>S", .c_to_s },                                .{ "CELL/", .cell_slash },                     .{ "CHAR-", .char_minus },
        .{ "DFLOAT/", .dfloat_slash },                .{ "FLOAT", .float_size_word },                 .{ "FLOAT/", .float_slash },                        .{ "L!", .l_store },                           .{ "L>S", .l_to_s },
        .{ "L@", .l_fetch },                          .{ "LALIGN", .l_align },                        .{ "LALIGNED", .l_aligned },                        .{ "LBE", .l_be },                             .{ "LLE", .l_le },
        .{ "MAXALIGNED", .max_aligned },              .{ "SFLOAT/", .sfloat_slash },                  .{ "TH", .th },                                     .{ "TH!", .th_store },                         .{ "TH@", .th_fetch },
        .{ "W!", .w_store },                          .{ "W>S", .w_to_s },                            .{ "W@", .w_fetch },                                .{ "WALIGN", .w_align },                       .{ "WALIGNED", .w_aligned },
        .{ "WBE", .w_be },                            .{ "WLE", .w_le },                              .{ "X!", .x_store },                                .{ "X>S", .x_to_s },                           .{ "X@", .x_fetch },
        .{ "XALIGN", .x_align },                      .{ "XALIGNED", .x_aligned },                    .{ "XBE", .x_be },                                  .{ "XD!", .xd_store },                         .{ "XD>S", .xd_to_s },
        .{ "XD@", .xd_fetch },                        .{ "XDBE", .xd_be },                            .{ "XDLE", .xd_le },                                .{ "XLE", .x_le },                             .{ "->HERE", .to_here },
        .{ "2FIELD:", .two_field },                   .{ "L,", .l_comma },                            .{ "LFIELD:", .l_field },                           .{ "MAXALIGN", .max_align },                   .{ "MEM,", .mem_comma },
        .{ "SAVE-MEM-DICT", .save_mem_dict },         .{ "W,", .w_comma },                            .{ "WFIELD:", .w_field },                           .{ "X,", .x_comma },                           .{ "XD,", .xd_comma },
        .{ "XFIELD:", .x_field },                     .{ "A,", .a_comma },                            .{ "ACONSTANT", .define_aconstant },                .{ "AVARIABLE", .define_avariable },           .{ "SAVE-MEM", .save_mem },
        .{ "EXTEND-MEM", .extend_mem },               .{ "FREE-MEM-VAR", .free_mem_var },             .{ "BUFFER%", .buffer_percent },                    .{ "INIT-BUFFER", .init_buffer },              .{ "ADJUST-BUFFER", .adjust_buffer },
        .{ "#BELL", .number_bell },                   .{ "#BS", .number_bs },                         .{ "#CR", .number_cr },                             .{ "#DEL", .number_del },                      .{ "#EOF", .number_eof },
        .{ "#ESC", .number_esc },                     .{ "#FF", .number_ff },                         .{ "#LF", .number_lf },                             .{ "#TAB", .number_tab },                      .{ "INVALID-CHAR", .invalid_char },
        .{ "NEWLINE", .newline },                     .{ "TOUPPER", .to_upper },                      .{ "CAPSCOMPARE", .caps_compare },                  .{ "CAPSSEARCH", .caps_search },               .{ "CAPSSTRING-PREFIX?", .caps_prefix },
        .{ "STR<", .str_less },                       .{ "STRING-SUFFIX?", .string_suffix },          .{ "SAFE/STRING", .safe_slash_string },             .{ "SCAN-BACK", .scan_back },                  .{ "NOSPLIT?", .no_split },
        .{ "TYPEWHITE", .type_white },                .{ "S+", .string_concat },                      .{ "APPEND", .string_append_owned },                .{ "CSTRING>SSTRING", .cstring_to_sstring },   .{ "DELETE", .delete_bytes },
        .{ "INSERT", .insert_bytes },                 .{ "STRING,", .string_comma },                  .{ "XC@+?", .xc_fetch_plus_query },                 .{ "$VALUE", .define_string_value },           .{ "MACRO:", .define_string_value },
        .{ "MACROS-WORDLIST", .macros_wordlist },     .{ "REPLACER:", .define_replacer },             .{ ".SUBSTITUTE", .dot_substitute },                .{ "EMIT-FILE", .emit_file },                  .{ "SLURP-FID", .slurp_fid },
        .{ "KEY-FILE", .key_file },                   .{ "KEY?-FILE", .key_query_file },              .{ "FILE-EOF?", .file_eof_query },                  .{ "+FMODE", .plus_fmode },                    .{ ".INCLUDED", .dot_included },
        .{ "ABSOLUTE-FILE?", .absolute_file_query },  .{ "CLEAR-PATH", .clear_path },                 .{ "ALSO-PATH", .also_path },                       .{ ".PATH", .dot_path },                       .{ "PATH+", .path_plus },
        .{ "PATH=", .path_equals },                   .{ "OPEN-PATH-FILE", .open_path_file },         .{ "FILE>PATH", .file_to_path },                    .{ "BASENAME", .basename },                    .{ "DIRNAME", .dirname },
        .{ "FILENAME-MATCH", .filename_match },       .{ "GET-DIR", .get_dir },                       .{ "SET-DIR", .set_dir },                           .{ "=MKDIR", .equals_mkdir },                  .{ "MKDIR-PARENTS", .mkdir_parents },
        .{ "OPEN-DIR", .open_dir },                   .{ "READ-DIR", .read_dir },                     .{ "CLOSE-DIR", .close_dir },                       .{ "NTIME", .ntime },                          .{ "CPUTIME", .cputime },
        .{ "NS", .ns },                               .{ ">TIME&DATE&TZ", .to_time_date_tz },         .{ "FPATH", .fpath },                               .{ ">STRING-EXECUTE", .to_string_execute },    .{ "OUTFILE-ID", .outfile_id },
        .{ "OUTFILE-EXECUTE", .outfile_execute },     .{ "INFILE-ID", .infile_id },                   .{ "INFILE-EXECUTE", .infile_execute },             .{ "CSV-QUOTE", .csv_quote },                  .{ "CSV-SEPARATOR", .csv_separator },
        .{ ".QUOTED-CSV", .dot_quoted_csv },          .{ "READ-CSV", .read_csv },                     .{ "SH", .sh },                                     .{ "OPEN-PIPE", .open_pipe },                  .{ "CLOSE-PIPE", .close_pipe },
        .{ "BROKEN-PIPE-ERROR", .broken_pipe_error }, .{ "SH-GET", .sh_get },                         .{ "KEY-IOR", .key_ior },                           .{ "FORM", .form },                            .{ "AT-DELTAXY", .at_deltaxy },
        .{ "FKEY.", .fkey_dot },                      .{ "SIMPLE-FKEY-STRING", .simple_fkey_string }, .{ "TO", .assign_to },                              .{ "IS", .assign_is },                         .{ "+TO", .assign_plus_to },
        .{ "ACTION-OF", .assignment_action_of },      .{ "", .compile_assign_to },                    .{ "", .compile_assign_is },                        .{ "", .compile_assign_plus_to },              .{ "", .compile_assignment_action_of },
        .{ "COMP'", .comp_tick },                     .{ "[COMP']", .bracket_comp_tick },             .{ "COMPILE-ONLY", .compile_only },                 .{ "RESTRICT", .restrict_word },               .{ "EXECUTE-EXIT", .execute_exit },
        .{ "POSTPONE,", .postpone_comma },            .{ "SELECT", .select_word },                    .{ "[NOOP]", .bracket_noop },                       .{ "[:", .quote_open },                        .{ ";]", .quote_close },
        .{ "NONAME", .noname },                       .{ "IN-COLON-DEF?", .in_colon_def },            .{ "]]", .postpone_open },                          .{ "", .postpone_s_quote },                    .{ "", .postpone_print_quote },
        .{ "", .postpone_left_bracket },              .{ "", .postpone_right_bracket },               .{ "", .postpone_parsed_string },

        // Extended counted loops and control-stack words (P07c).
                          .{ "+DO", .positive_do },                      .{ "U+DO", .unsigned_positive_do },
        .{ "-DO", .negative_do },                     .{ "U-DO", .unsigned_negative_do },             .{ "-[DO", .inclusive_negative_do },                .{ "U-[DO", .unsigned_inclusive_negative_do }, .{ "-LOOP", .negative_loop },
        .{ "FOR", .for_word },                        .{ "NEXT", .next_word },                        .{ "MEM+DO", .memory_up_do },                       .{ "MEM-DO", .memory_down_do },                .{ "ARRAY>MEM", .array_to_mem },
        .{ "I'", .index_limit },                      .{ "DELTA-I", .delta_index },                   .{ "CS-DROP", .cs_drop },                           .{ "DONE", .done },                            .{ "?DUP-IF", .question_dup_if },
        .{ "?DUP-0=-IF", .question_dup_zero_if },     .{ "EXECUTE-PARSING", .execute_parsing },       .{ "EXECUTE-PARSING-FILE", .execute_parsing_file }, .{ "STRING-PARSE", .string_parse },            .{ "PARSE-WORD", .parse_word },
        .{ "NAME", .name_word },                      .{ "FORWARD", .forward_word },                  .{ ".UNRESOLVED", .dot_unresolved },                .{ "RECURSIVE", .recursive_word },             .{ "\\\\\\", .triple_backslash },
    };

    fn installBuiltins(self: *State) void {
        const definitions = builtin_definitions;
        for (definitions) |definition| {
            // A word of a group the build leaves out keeps its place without a name, which
            // lookup never finds: every build gives each built-in word the same execution
            // token, so an image moves between builds and its excluded words do not run.
            if (definition[0].len == 0 or defs.isExcludedBuiltin(definition[1])) {
                const id = self.appendEntry("", .builtin, definition[1], 0) catch unreachable;
                self.words[id].immediate = isImmediateBuiltin(definition[1]);
                // Keep fixed VALUE shape stable across files-enabled/disabled images.
                if (definition[1] == .csv_quote or definition[1] == .csv_separator) {
                    self.words[id].kind = .value;
                    self.words[id].value = if (definition[1] == .csv_quote) memory_map.csv_quote_address else memory_map.csv_separator_address;
                }
                continue;
            }
            self.addBuiltin(definition[0], definition[1]) catch unreachable;
        }
        // The Root list repeats the words needed to rebuild the search order after ONLY.
        self.writeCell(current_wordlist_address, root_wordlist) catch unreachable;
        for (root_word_names) |name| {
            const builtin = for (definitions) |definition| {
                if (std.mem.eql(u8, definition[0], name)) break definition[1];
            } else unreachable;
            self.addBuiltin(name, builtin) catch unreachable;
        }
        _ = self.appendEntry("EKEYS", .vocabulary, .noop, memory_map.ekeys_wordlist) catch unreachable;
        self.writeCell(current_wordlist_address, forth_wordlist) catch unreachable;
        _ = self.appendEntry("EKEYS", .vocabulary, .noop, memory_map.ekeys_wordlist) catch unreachable;
        self.writeCell(current_wordlist_address, memory_map.ekeys_wordlist) catch unreachable;
        for (@import("core/standard_keys.zig").constants) |entry| {
            _ = self.appendWord(entry[0], .constant, .noop, entry[1]) catch unreachable;
        }
        self.writeCell(current_wordlist_address, forth_wordlist) catch unreachable;
        self.builtin_count = self.word_count;
    }

    fn isImmediateBuiltin(builtin: Builtin) bool {
        return switch (builtin) {
            .recursive_word, .positive_do, .unsigned_positive_do, .negative_do, .unsigned_negative_do, .inclusive_negative_do, .unsigned_inclusive_negative_do, .negative_loop, .for_word, .next_word, .memory_up_do, .memory_down_do, .done, .question_dup_if, .question_dup_zero_if, .quote_open, .quote_close, .postpone_open, .bracket_comp_tick, .execute_exit, .assign_to, .assign_is, .assign_plus_to, .assignment_action_of, .compile_if, .compile_else, .compile_ahead, .compile_then, .compile_begin, .compile_end, .compile_again, .compile_while, .compile_repeat, .compile_do, .compile_q_do, .compile_loop, .compile_plus_loop, .compile_does, .compile_case, .compile_of, .compile_endof, .compile_endcase, .compile_exit, .compile_recurse, .leave, .bracket_if, .bracket_else, .bracket_then, .bracket_defined, .bracket_undefined, .bracket_ifdef, .bracket_ifundef, .bracket_do, .bracket_q_do, .bracket_loop, .bracket_plus_loop, .bracket_i, .bracket_begin, .bracket_until, .bracket_again, .bracket_while, .bracket_repeat, .bracket_for, .bracket_next, .end_definition, .literal, .fliteral, .sliteral, .two_literal, .defers, .bracket_compile, .question_exit, .question_leave, .compile_question_of, .compile_contof, .compile_next_case, .debug_tilde, .assert_paren, .once, .debug_tilde_bt, .debug_tilde_one_bt, .break_colon, .break_quote, .triple_backslash => true,
            else => false,
        };
    }

    fn addBuiltin(self: *State, name: []const u8, builtin: Builtin) RuntimeError!void {
        const id = try self.appendWord(name, .builtin, builtin, 0);
        self.words[id].immediate = isImmediateBuiltin(builtin);
        self.words[id].compile_only = builtin == .bracket_comp_tick or builtin == .execute_exit;
        if (builtin == .csv_quote or builtin == .csv_separator) {
            self.words[id].kind = .value;
            self.words[id].value = if (builtin == .csv_quote) memory_map.csv_quote_address else memory_map.csv_separator_address;
        }
    }

    pub fn appendWord(self: *State, name: []const u8, kind: WordKind, builtin: Builtin, value: Cell) RuntimeError!u16 {
        if (self.word_count == max_words) return error.DictionaryFull;
        if (self.noname_next) {
            self.noname_next = false;
            return self.appendEntry("", kind, builtin, value);
        }
        if (name.len == 0 or name.len > max_name) return error.NameTooLong;
        const forward = @import("core/words_parsing.zig").unresolved(self, name, self.currentWordlist());
        if (forward != null and kind != .colon) return error.InvalidDefinition;
        if (forward == null and kind != .builtin and (if (self.currentWordlist() == memory_map.macros_wordlist) self.lookupIn(name, memory_map.macros_wordlist) else self.lookup(name)) != null) {
            self.write("WARNING: SAME NAME WORD EXISTS\n");
        }
        return self.appendEntry(name, kind, builtin, value);
    }

    /// Appends a colon definition without a name (`:NONAME`); lookup never finds it.
    pub fn appendAnonymousColon(self: *State) RuntimeError!u16 {
        if (self.word_count == max_words) return error.DictionaryFull;
        self.noname_next = false;
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
        wordlists.indexWord(self, id);
        return id;
    }

    pub const latestWord = @import("core/quotations.zig").latest;
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

    /// Drops what refers to word `id` and every later word, whose numbers new words
    /// will reuse: the recorded uses, and the actions of the DEFERs that are kept.
    pub fn dropUsesFrom(self: *State, id: u16) void {
        @import("core/words_parsing.zig").forgetTargets(self, id);
        for (self.words[0..@min(id, self.word_count)]) |word| {
            if (word.kind != .deferred) continue;
            const action = self.readCell(word.value) catch continue;
            if (action >= id) self.writeCell(word.value, words_defining.uninitialized_defer) catch {};
        }
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
        @import("core/address_registry.zig").discardRange(self, self.words[id].data_here_before, self.data_here, .data, true);
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
        self.dropWordsFrom(id);
        self.dropUsesFrom(id);
    }

    /// Takes word `id` and every later word out of the dictionary and the index of the
    /// names; the caller gives back their code, data, and names.
    pub fn dropWordsFrom(self: *State, id: u16) void {
        @import("core/address_registry.zig").forgetWords(self, id);
        if (defs.debug_enabled) {
            words_debug.unwatchFrom(self, id);
            // The words that take these places start their counts at 0.
            if (self.profile) |profile| profile.forgetWords(id, self.word_count);
            if (self.lint) |lint| lint.forgetWords(id, self.word_count);
        }
        wordlists.unindexFrom(self, id);
        self.word_count = id;
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
            if (!self.compiling and self.words[id].compile_only) return error.CompileOnly;
            if (@import("core/word_semantics.zig").pending(self, id)) |pending| {
                self.pending = pending;
                return;
            }
            if (id >= self.builtin_count) return self.handleWord(id);
            // Defining words are dictionary words, found through the search order. One
            // compiled into a definition reads its name when that runs; interpreted, it
            // takes the next name, which may be on a later line.
            if (isDefiningBuiltin(self.words[id].builtin)) {
                if (self.compiling) return self.handleWord(id);
                self.pending = try self.definingPending(self.words[id].builtin);
                if (self.noname_next) try self.finishPending("");
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
            if (self.data_depth == self.data_stack.len) return error.StackOverflow;
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
        if (asciiEqlIgnoreCase(token, "FORGET")) {
            return self.startInterpretPending(.forget_name);
        }
        // Not a dictionary word, so that a dictionary without the graphics words keeps
        // the same built-in words as older builds.
        if (asciiEqlIgnoreCase(token, "REQUIRE-GRAPHICS")) {
            return words_graphics.requireGraphics(self);
        }
        if (asciiEqlIgnoreCase(token, "REQUIRE-GAME")) {
            return @import("core/words_game.zig").requireGame(self);
        }
        if (asciiEqlIgnoreCase(token, "REQUIRE-GUI")) {
            return @import("core/words_gui.zig").requireGui(self);
        }
        if (asciiEqlIgnoreCase(token, "REQUIRE-AUDIO")) {
            return words_audio.requireAudio(self);
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
        const float_literal = if (defs.float_enabled and self.currentBase() == 10) parseFloat(token, true) else null;
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
        // The code after the name is the first block of the definition.
        self.markBlock(self.columnAfterWord());
    }

    /// --coverage: a block of the coverage words starts here. The operation that
    /// counts it is a branch to the operation after it, which changes nothing.
    pub fn markBlock(self: *State, column: u16) void {
        if (!defs.debug_enabled or !self.cover_blocks) return;
        const next: Cell = @as(Cell, self.code_count) + 1;
        const at = self.emit(.{ .kind = .branch, .value = next }) catch return;
        self.code_columns[at] = column;
    }

    /// The column of the blank after the word that was just read, counted from 1.
    fn columnAfterWord(self: *const State) u16 {
        // >IN is past the blank that ended the word, when one did.
        var end = self.sourceCursor();
        if (end > 0 and end <= self.source_line.len and std.ascii.isWhitespace(self.source_line[end - 1])) end -= 1;
        return @intCast(@min(end + 1, std.math.maxInt(u16)));
    }

    /// A word of a control structure after which a block starts, as in gforth.
    fn startsBlock(builtin: Builtin) bool {
        return switch (builtin) {
            .compile_if, .compile_else, .compile_then, .compile_begin, .compile_end, .compile_again, .compile_while, .compile_repeat, .compile_do, .compile_q_do, .compile_loop, .compile_plus_loop, .compile_does, .compile_case, .compile_of, .compile_question_of, .compile_endof, .compile_endcase, .compile_contof, .compile_next_case => true,
            else => false,
        };
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
        const action = @import("core/word_semantics.zig").compilation(self, id);
        if (self.compiling and !action.execute) {
            try self.compileCall(action.target);
        } else {
            // ~~VARIABLE: a use of the name outside a definition is shown at once.
            if (self.isWatchedVariable(id)) try words_debug.watchStore(self, id, self.words[id].name_len);
            // Compiled code that starts here has no caller for ~~BT to show, unless a
            // definition is interpreting this text (EVALUATE, INCLUDED): then the
            // caller is the one that called that word.
            if (defs.debug_enabled and self.call_depth == 0) self.outer_pc = 0;
            try self.executeWord(if (self.compiling) action.target else id);
        }
    }

    /// Whether the word is a variable of ~~VARIABLE.
    fn isWatchedVariable(self: *const State, id: u16) bool {
        return defs.debug_enabled and self.watched_count != 0 and self.words[id].kind == .variable and words_debug.isWatched(self, id);
    }

    /// Compiles known colon targets and frequent built-ins to direct operations.
    /// Inline guards pack the original word id with their span and depth; ordinary
    /// calls keep the word id directly. Both preserve SEE and image relocation.
    pub fn compileCall(self: *State, id: u16) RuntimeError!void {
        // ~~VARIABLE: a use compiled into a definition is shown when the definition
        // runs. It is compiled here, where every call is: for the name in the
        // definition, and for a word that POSTPONEs it.
        if (self.isWatchedVariable(id)) try words_debug.watchStore(self, id, self.words[id].name_len);
        if (try inline_calls.compile(self, id)) return;
        _ = try self.emit(self.specializeCall(.{ .kind = .call, .value = id }));
    }

    /// Cache immutable dispatch information, keeping the original word id for SEE.
    /// Images normalize these operations and rebuild them after restoring words.
    /// Existing word kinds do not change; FORGET also discards code belonging to
    /// the forgotten definitions. Redefinition appends a new dictionary entry.
    pub fn specializeCall(self: *const State, op: Op) Op {
        if (op.kind != .call and op.kind != .call_builtin) return op;
        if (op.value < 0 or op.value >= self.word_count) return op;
        const word = &self.words[@intCast(op.value)];
        if (word.kind == .builtin and op.value < self.builtin_count) {
            return .{ .kind = defs.builtinOpKind(word.builtin), .value = op.value };
        }
        if (op.kind == .call and word.kind == .colon) return .{ .kind = .call_colon, .value = op.value };
        return op;
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
    pub const compileQuestionOf = control_flow.compileQuestionOf;
    pub const compileContof = control_flow.compileContof;
    pub const compileNextCase = control_flow.compileNextCase;
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
    pub const includeEmbedded = source_input.includeEmbedded;
    pub const saveInputPlace = source_input.saveInputPlace;
    pub const restoreInputPlace = source_input.restoreInputPlace;
    pub const includeFile = source_input.includeFile;
    pub const interpretIncludedFile = source_input.interpretIncludedFile;
    pub const requireFile = source_input.requireFile;
    pub const locateWord = source_input.locateWord;
    pub const listUses = source_input.listUses;
    pub const sourceAddress = source_input.sourceAddress;
    pub const setArguments = words_system.setArguments;
    pub const argument = words_system.argument;
    pub const shiftArguments = words_system.shiftArguments;

    pub fn emit(self: *State, op: Op) RuntimeError!u16 {
        if (self.code_count == max_code) return error.CodeFull;
        const at = self.code_count;
        self.code[at] = op;
        if (defs.debug_enabled) {
            self.code_lines[at] = if (self.currentFileFrame()) |frame| frame.line else 0;
            self.code_columns[at] = 0;
            // The count of an operation that FORGET or a MARKER removed is not this one's.
            if (self.profile) |profile| profile.op_counts[at] = 0;
        }
        self.code_count += 1;
        return at;
    }

    pub fn patch(self: *State, at: u16, target: u16) void {
        self.code[at].value = target;
    }

    pub fn executeWord(self: *State, id: u16) RuntimeError!void {
        if (comptime defs.isExcludedBuiltin(.csv_quote)) {
            if (id < self.builtin_count and (self.words[id].builtin == .csv_quote or self.words[id].builtin == .csv_separator)) return error.InvalidExecutionToken;
        }
        const word = self.words[id];
        switch (word.kind) {
            .forward => {
                if (word.value < 0) return error.InvalidDefinition;
                try self.executeWord(try self.wordId(word.value));
            },
            .synonym => try self.executeWord(try self.wordId(word.value)),
            .builtin => try self.executeBuiltin(word.builtin),
            .constant, .array => try self.push(word.value),
            .value => try self.push(try self.readCell(word.value)),
            .string_value => try @import("core/string_values.zig").fetch(self, word.value),
            .fconstant => try self.fpush(bitsFloat(word.value)),
            .fvalue => try self.fpush(try self.readFloat(word.value)),
            .two_constant, .two_value => try self.pushDouble(try self.readDouble(word.value)),
            .variable, .created => {
                try self.push(word.value);
                if (word.has_does) {
                    if (self.call_depth == self.frames.len) return error.ReturnStackOverflow;
                    self.call_depth += 1;
                    defer self.call_depth -= 1;
                    try self.executeOperations(word.does_code_start, word.does_code_end, null);
                }
            },
            .colon => try self.executeColon(id, word),
            .deferred => {
                const action = try self.readCell(word.value);
                // gforth warns and goes on when a DEFER has no action yet.
                if (action == words_defining.uninitialized_defer) {
                    self.write("WARNING: DEFERRED WORD ");
                    self.write(self.wordName(word));
                    self.write(" IS UNINITIALIZED\n");
                    return;
                }
                // A DEFER that runs itself, directly or through other words, must end in
                // an error, not in the host's stack overflow (gforth loops for ever).
                if (self.call_depth == self.frames.len) return error.ReturnStackOverflow;
                self.call_depth += 1;
                defer self.call_depth -= 1;
                try self.executeWord(try self.wordId(action));
            },
            .field => try self.push((try self.pop()) +% word.value),
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
        if (self.call_depth == self.frames.len) return error.ReturnStackOverflow;
        self.call_depth += 1;
        defer self.call_depth -= 1;
        try self.executeOperations(word.code_start, word.code_end, id);
    }

    /// +TO: adds the top of the stack (or the float stack) to a VALUE, FVALUE, or 2VALUE.
    pub fn addToValue(self: *State, id: u16) RuntimeError!void {
        const word = self.words[id];
        if (comptime defs.isExcludedBuiltin(.csv_quote)) {
            if (word.builtin == .csv_quote or word.builtin == .csv_separator) return error.InvalidExecutionToken;
        }
        switch (word.kind) {
            .fvalue => try self.writeFloat(word.value, (try self.readFloat(word.value)) + try self.fpop()),
            .two_value => try self.writeDouble(word.value, (try self.readDouble(word.value)) +% try self.popDouble()),
            .value => try self.writeCell(word.value, (try self.readCell(word.value)) +% try self.pop()),
            .string_value => try @import("core/string_values.zig").store(self, id, true),
            else => return error.InvalidDefinition,
        }
    }

    /// The execution token of a built-in word.
    pub fn builtinWord(self: *const State, builtin: Builtin) Cell {
        for (self.words[0..self.builtin_count], 0..) |word, id| {
            if (word.kind == .builtin and word.builtin == builtin) return @intCast(id);
        }
        unreachable;
    }

    pub fn wordId(self: *State, value: Cell) RuntimeError!u16 {
        if (value < 0 or value >= self.word_count) return error.InvalidExecutionToken;
        return @intCast(value);
    }

    /// Where a colon definition that compiled code called goes on when the callee ends.
    pub const CallFrame = struct {
        pc: u16,
        end_pc: u16,
        defining_word: ?u16,
        /// Zero means no locals; the local-variable area has nonzero addresses.
        locals_frame: Cell = 0,
    };

    /// The definition that is running and its callers' frames, as executeOperations keeps them.
    const Running = CallFrame;

    pub const CatchContinuation = struct {
        context: words_system.CatchContext,
        frame_depth: usize,
        call_depth: usize,
        locals_top: Cell,
    };

    /// A CATCH of compiled code enters the existing loop, rather than nesting a host
    /// interpreter call (whose Debug stack frame alone can take several kilobytes).
    fn enterCatch(self: *State, comptime counted: bool, running: *Running) RuntimeError!bool {
        const xt = try self.pop();
        var id = self.synonymTarget(try self.wordId(xt));
        const context = words_system.CatchContext.init(self);
        var deferred_depth: usize = 0;
        while (self.words[id].kind == .deferred) {
            const action = self.readCell(self.words[id].value) catch |err| {
                try context.handleError(self, err);
                return true;
            };
            if (action == words_defining.uninitialized_defer) {
                try self.push(xt);
                return false;
            }
            if (self.call_depth + deferred_depth == self.frames.len) {
                try context.handleError(self, error.ReturnStackOverflow);
                return true;
            }
            deferred_depth += 1;
            id = self.synonymTarget(self.wordId(action) catch |err| {
                try context.handleError(self, err);
                return true;
            });
        }
        const word = self.words[id];
        const does = (word.kind == .created or word.kind == .variable) and word.has_does;
        if (word.kind != .colon and !does) {
            try self.push(xt);
            return false;
        }
        if (does) self.push(word.value) catch |err| {
            try context.handleError(self, err);
            return true;
        };
        if (self.call_depth + deferred_depth == self.frames.len) {
            try context.handleError(self, error.ReturnStackOverflow);
            return true;
        }
        self.catches[self.catch_depth] = .{
            .context = context,
            .frame_depth = self.frame_depth,
            .call_depth = self.call_depth,
            .locals_top = self.locals_top,
        };
        self.catch_depth += 1;
        self.frames[self.frame_depth] = running.*;
        self.frame_depth += 1;
        self.call_depth += deferred_depth + 1;
        running.* = if (does)
            .{ .pc = word.does_code_start, .end_pc = word.does_code_end, .defining_word = null }
        else
            .{ .pc = word.code_start, .end_pc = word.code_end, .defining_word = id };
        if (counted) self.traceRunning(running.*, true);
        return true;
    }

    fn builtinInLoop(self: *State, comptime counted: bool, builtin: Builtin, running: *Running) RuntimeError!void {
        if (builtin == .catch_word and try self.enterCatch(counted, running)) return;
        try self.executeBuiltin(builtin);
    }

    fn wordInLoop(self: *State, comptime counted: bool, id: u16, running: *Running) RuntimeError!void {
        var target_id = self.synonymTarget(id);
        var deferred_depth: usize = 0;
        while (self.words[target_id].kind == .deferred) {
            const action = try self.readCell(self.words[target_id].value);
            if (action == words_defining.uninitialized_defer) return self.executeWord(id);
            if (self.call_depth + deferred_depth == self.frames.len) return error.ReturnStackOverflow;
            deferred_depth += 1;
            target_id = self.synonymTarget(try self.wordId(action));
        }
        const target = self.words[target_id];
        if (target.kind == .builtin and target.builtin == .catch_word) {
            const call_depth = self.call_depth;
            const catch_depth = self.catch_depth;
            self.call_depth += deferred_depth;
            self.builtinInLoop(counted, target.builtin, running) catch |err| {
                self.call_depth = call_depth;
                return err;
            };
            // A deferred CATCH stays counted while its callee runs, then returns
            // directly to this caller, including the deferred calls it went through.
            if (self.catch_depth > catch_depth) {
                self.catches[self.catch_depth - 1].call_depth = call_depth;
            } else self.call_depth = call_depth;
        } else if (target.kind == .builtin and deferred_depth == 0) {
            try self.builtinInLoop(counted, target.builtin, running);
        } else {
            try self.executeWord(id);
        }
    }

    /// Discard the callee's frames and locals, and resume just after CATCH.
    fn resumeCatch(self: *State, running: *Running) words_system.CatchContext {
        self.catch_depth -= 1;
        const caught = self.catches[self.catch_depth];
        running.* = self.frames[caught.frame_depth];
        self.frame_depth = caught.frame_depth;
        self.call_depth = caught.call_depth;
        self.locals_top = caught.locals_top;
        return caught.context;
    }

    /// Ends the running definition and goes on in its caller; false when the definition
    /// executeOperations started with ends.
    inline fn returnToCaller(self: *State, running: *Running, entry_frames: usize) RuntimeError!bool {
        if (self.frame_depth == entry_frames) return false;
        if (running.locals_frame != 0) self.locals_top = running.locals_frame;
        self.frame_depth -= 1;
        running.* = self.frames[self.frame_depth];
        self.call_depth -= 1;
        if (self.catch_depth != 0 and self.catches[self.catch_depth - 1].frame_depth == self.frame_depth) {
            self.catch_depth -= 1;
            self.call_depth = self.catches[self.catch_depth].call_depth;
            try self.push(0);
        }
        return true;
    }

    pub const max_backtrace = 32;

    pub fn clearBacktrace(self: *State) void {
        self.backtrace_count = 0;
        self.backtrace_total = 0;
    }

    /// Lets compiled code run `step_limit` operations again.
    pub fn resetSteps(self: *State) void {
        self.steps_left = self.step_limit;
    }

    /// Keeps where an executeOperations was when an error ended it: `pc` is after the
    /// operation that failed, and `frames` from `entry_frames` up are its callers. An
    /// error passes from the innermost executeOperations to the ones around it, whose
    /// `level` (the nesting depth they were entered at) is lower each time; one that
    /// comes from the same level or a deeper one is a new error, after one that did not
    /// reach `report` or CATCH.
    fn recordBacktrace(self: *State, pc: u16, entry_frames: usize, level: usize) void {
        @branchHint(.cold);
        if (self.backtrace_total != 0 and level >= self.backtrace_level) self.clearBacktrace();
        self.backtrace_level = level;
        self.addBacktrace(pc -| 1);
        var index = self.frame_depth;
        while (index > entry_frames) {
            index -= 1;
            self.addBacktrace(self.frames[index].pc -| 1);
        }
    }

    /// --trace and --profile: shows or counts the definition that `running` runs as it
    /// starts or ends. Code after DOES> has no word of its own and is passed over.
    fn traceRunning(self: *State, running: Running, enter: bool) void {
        // The steps end with the code they started in, also code after DOES>.
        if (!enter and self.stepper != .off) words_debug.stepLeave(self);
        const id = running.defining_word orelse return;
        if (self.tracing) words_debug.traceWord(self, id, enter);
        if (self.profile) |profile| {
            if (enter) profile.enter(id) else profile.leave();
        }
        if (enter and self.stepper != .off) words_debug.stepEnter(self, id);
    }

    /// Whether short definitions are called instead of copied into their callers.
    pub fn keepsCalls(self: *const State) bool {
        return defs.debug_enabled and self.plain_calls;
    }

    fn addBacktrace(self: *State, pc: u16) void {
        if (self.backtrace_count < max_backtrace) {
            self.backtrace[self.backtrace_count] = pc;
            self.backtrace_count += 1;
        }
        self.backtrace_total += 1;
    }

    /// Runs compiled code. With a step limit (--max-steps), the trace (--trace), the
    /// profile (--profile), or the single-step debugger (DBG, BREAK:), the loop that
    /// counts the operations, notes the words, and stops for the steps runs it, so that
    /// the usual loop does not pay for them.
    fn executeOperations(self: *State, start_pc: u16, end_pc: u16, defining_word: ?u16) RuntimeError!void {
        // A colon definition that compiled code calls runs in the loop of runOperations,
        // its caller kept in `frames`, instead of in a host call of its own: three calls
        // and returns per call made word nesting slow. Whatever ends the loop, an error
        // included, leaves the nesting depth, the frames, and the local-variable area as
        // they were on entry, as the calls of their own did.
        const entry_frames = self.frame_depth;
        const entry_call_depth = self.call_depth;
        const entry_locals_top = self.locals_top;
        defer {
            self.frame_depth = entry_frames;
            self.call_depth = entry_call_depth;
            self.locals_top = entry_locals_top;
        }
        // For ~~BT, the place that started this code lies under its frames, marked by an
        // end of 0. There is room: the caller counted this nesting in `call_depth`, which
        // the frames never exceed.
        if (defs.debug_enabled) {
            self.frames[self.frame_depth] = .{ .pc = self.outer_pc, .end_pc = 0, .defining_word = null };
            self.frame_depth += 1;
        }
        const loop_frames = self.frame_depth;
        // Before the frames are given back: they are the callers of the backtrace.
        errdefer if (defs.debug_enabled) self.recordBacktrace(self.failed_pc, loop_frames, entry_call_depth);
        // The loops are called, not made a part of this function: as a part of it, with
        // what is done here before and after them, the usual loop ran slower than before
        // there were two (stack words 1.4 times as long; measured on 2026-11-11).
        if (defs.debug_enabled and (self.step_limit != 0 or self.tracing or self.profile != null or self.keep_counting)) return @call(.never_inline, runOperations, .{ self, true, start_pc, end_pc, defining_word });
        return @call(.never_inline, runOperations, .{ self, false, start_pc, end_pc, defining_word });
    }

    fn runOperations(self: *State, comptime counted: bool, start_pc: u16, end_pc: u16, defining_word: ?u16) RuntimeError!void {
        var running: Running = .{ .pc = start_pc, .end_pc = end_pc, .defining_word = defining_word };
        const entry_frames = self.frame_depth;
        const entry_catches = self.catch_depth;
        defer self.catch_depth = entry_catches;
        const was_counted = self.in_counted;
        if (counted) self.in_counted = true;
        defer if (counted) {
            self.in_counted = was_counted;
        };
        if (counted) self.traceRunning(running, true);
        while (true) {
            self.runOperationsLoop(counted, &running, entry_frames, entry_catches) catch |err| {
                var failure = err;
                while (true) {
                    if (failure == error.Quit or failure == error.StepLimit or self.catch_depth == entry_catches) return failure;
                    const context = self.resumeCatch(&running);
                    context.handleError(self, failure) catch |next| {
                        failure = next;
                        continue;
                    };
                    if (counted and self.cell_watch_count != 0) words_debug.checkWatches(self, running.pc -| 1);
                    break;
                }
                continue;
            };
            return;
        }
    }

    fn runOperationsLoop(self: *State, comptime counted: bool, running: *Running, entry_frames: usize, entry_catches: usize) RuntimeError!void {
        errdefer if (defs.debug_enabled) {
            self.failed_pc = running.pc;
        };
        // The operation that ran last in this loop, for WATCH.
        var ran: ?u16 = null;
        while (true) {
            if (self.halted) {
                if (self.catch_depth == entry_catches) return;
                _ = self.resumeCatch(running);
                try self.push(0);
                continue;
            }
            // WATCH: what the last operation changed.
            if (counted and self.cell_watch_count != 0) {
                if (ran) |pc| words_debug.checkWatches(self, pc);
            }
            if (running.pc >= running.end_pc) {
                if (counted) self.traceRunning(running.*, false);
                if (!try self.returnToCaller(running, entry_frames)) return;
                continue;
            }
            const op = self.code[running.pc];
            if (counted) ran = running.pc;
            running.pc += 1;
            if (counted and self.step_limit != 0) {
                if (self.steps_left == 0) return error.StepLimit;
                self.steps_left -= 1;
            }
            if (counted) if (self.profile) |profile| profile.countOperation(running.pc - 1);
            if (counted and self.stepper == .on and self.call_depth == self.step_depth) try words_debug.step(self, running.pc - 1, running.end_pc);
            switch (op.kind) {
                inline .call, .call_colon => |call_kind| {
                    if (call_kind == .call_colon and inline_calls.isInline(op)) {
                        // FORGET/MARKER may remove this word while its caller runs.
                        // Validate before the depth check, as an ordinary call does.
                        // The packed id is already u16; compare without widening to Cell.
                        if (inline_calls.wordId(op.value) >= self.word_count) return error.InvalidExecutionToken;
                        // The following straight-line operations are the copied
                        // body. Keep the original call-limit check without a frame.
                        if (self.call_depth + inline_calls.depth(op.value) > self.frames.len) return error.ReturnStackOverflow;
                        continue;
                    }
                    var id = try self.wordId(op.value);
                    var word = &self.words[id];
                    if (call_kind == .call_colon) std.debug.assert(word.kind == .colon);
                    if (call_kind == .call) switch (word.kind) {
                        .colon => {},
                        // A DEFER whose action is a colon definition is called in this
                        // loop, as that definition is, instead of in a loop of its own;
                        // any other action, and none, go the usual way.
                        .deferred => {
                            const action = try self.readCell(word.value);
                            const target: ?u16 = if (action == words_defining.uninitialized_defer or action < 0 or action >= self.word_count) null else self.synonymTarget(@intCast(action));
                            if (target == null or self.words[target.?].kind != .colon) {
                                if (defs.debug_enabled) self.outer_pc = running.pc;
                                try self.wordInLoop(counted, id, running);
                                continue;
                            }
                            id = target.?;
                            word = &self.words[id];
                        },
                        // Keep the word id in compiled code (SEE and image relocation
                        // use it), but avoid another dispatcher for simple data words.
                        .constant, .array => {
                            try self.push(word.value);
                            continue;
                        },
                        .variable, .created => {
                            if (word.has_does) {
                                if (defs.debug_enabled) self.outer_pc = running.pc;
                                try self.wordInLoop(counted, id, running);
                            } else try self.push(word.value);
                            continue;
                        },
                        else => {
                            if (defs.debug_enabled) self.outer_pc = running.pc;
                            try self.wordInLoop(counted, id, running);
                            continue;
                        },
                    };
                    if (self.call_depth == self.frames.len) return error.ReturnStackOverflow;
                    self.call_depth += 1;
                    self.frames[self.frame_depth] = running.*;
                    self.frame_depth += 1;
                    running.* = .{ .pc = word.code_start, .end_pc = word.code_end, .defining_word = id };
                    if (counted) self.traceRunning(running.*, true);
                },
                // EXECUTE of a colon definition is a call in this loop too: entering a
                // loop of its own for each one took a quarter longer than before there
                // were two loops.
                .execute => {
                    const id = self.synonymTarget(try self.wordId(try self.pop()));
                    const word = &self.words[id];
                    if (word.kind != .colon) {
                        if (defs.debug_enabled) self.outer_pc = running.pc;
                        try self.wordInLoop(counted, id, running);
                        continue;
                    }
                    if (self.call_depth == self.frames.len) return error.ReturnStackOverflow;
                    self.call_depth += 1;
                    self.frames[self.frame_depth] = running.*;
                    self.frame_depth += 1;
                    running.* = .{ .pc = word.code_start, .end_pc = word.code_end, .defining_word = id };
                    if (counted) self.traceRunning(running.*, true);
                },
                .call_builtin => {
                    if (op.value < 0 or op.value >= self.builtin_count) return error.InvalidExecutionToken;
                    if (defs.debug_enabled) self.outer_pc = running.pc;
                    try self.builtinInLoop(counted, self.words[@intCast(op.value)].builtin, running);
                },
                // These tags directly select the implementation: no dictionary
                // lookup or second runtime switch for frequent primitive words.
                inline else => |kind| {
                    const hot = comptime defs.primitiveBuiltin(kind);
                    if (comptime defs.isExcludedBuiltin(hot)) return error.InvalidExecutionToken;
                    try @call(.always_inline, word_modules[word_owner[@backingInt(hot)]].execute, .{ self, hot });
                },
                .compile_call => {
                    try self.requireCompiling();
                    try self.compileCall(try self.wordId(op.value));
                },
                .builtin => {
                    if (defs.debug_enabled) self.outer_pc = running.pc;
                    try self.builtinInLoop(counted, @fromBackingInt(@intCast(op.value)), running);
                },
                .literal, .execution_token => try self.push(op.value),
                .float_literal => try self.fpush(bitsFloat(op.value)),
                .store_value => {
                    const word = self.words[try self.wordId(op.value)];
                    if (comptime defs.isExcludedBuiltin(.csv_quote)) {
                        if (word.builtin == .csv_quote or word.builtin == .csv_separator) return error.InvalidExecutionToken;
                    }
                    switch (word.kind) {
                        .fvalue => try self.writeFloat(word.value, try self.fpop()),
                        .two_value => try self.writeDouble(word.value, try self.popDouble()),
                        .string_value => try @import("core/string_values.zig").store(self, try self.wordId(op.value), false),
                        else => try self.writeCell(word.value, try self.pop()),
                    }
                },
                .add_value => try self.addToValue(try self.wordId(op.value)),
                .branch => running.pc = @intCast(op.value),
                .branch_zero => {
                    if (try self.pop() == 0) running.pc = @intCast(op.value);
                },
                .do_loop, .q_do_loop => {
                    const start = try self.pop();
                    const limit = try self.pop();
                    const exit_pc: u16 = @intCast(@import("core/words_loops.zig").target(op.value));
                    const keep = op.value & @import("core/words_loops.zig").done_flag != 0;
                    if (op.kind == .q_do_loop and start == limit and !keep) {
                        running.pc = exit_pc;
                        continue;
                    }
                    if (self.loop_depth == self.loop_stack.len) return error.StackOverflow;
                    self.loop_stack[self.loop_depth] = .{ .index = start, .limit = limit, .exit_pc = exit_pc, .exit_after_first = start == limit, .leave_keeps_frame = keep };
                    self.loop_depth += 1;
                    if (op.kind == .q_do_loop and start == limit) running.pc = exit_pc;
                },
                .positive_do, .unsigned_positive_do, .negative_do, .unsigned_negative_do, .inclusive_negative_do, .unsigned_inclusive_negative_do, .for_loop, .memory_up_do, .memory_down_do => {
                    if (try @import("core/words_loops.zig").enter(self, op.kind, op.value)) running.pc = @intCast(@import("core/words_loops.zig").target(op.value));
                },
                .negative_loop, .next_loop => {
                    if (try @import("core/words_loops.zig").finish(self, op.kind)) running.pc = @intCast(op.value);
                },
                // Specialize the two loop endings: ordinary LOOP needs neither
                // a data-stack pop nor +LOOP's boundary-crossing calculation.
                inline .loop, .plus_loop => |loop_kind| {
                    if (self.loop_depth == 0) return error.LoopMismatch;
                    if (self.loop_stack[self.loop_depth - 1].mode != .normal) {
                        if (try @import("core/words_loops.zig").finish(self, op.kind)) running.pc = @intCast(op.value);
                        continue;
                    }
                    const step: Cell = if (loop_kind == .plus_loop) try self.pop() else 1;
                    const frame = &self.loop_stack[self.loop_depth - 1];
                    const crossed = if (loop_kind == .plus_loop) integer_math.loopCrossed(frame.index, frame.limit, step) else false;
                    frame.index +%= step;
                    const again = if (frame.exit_after_first) false else if (loop_kind == .loop) frame.index != frame.limit else !crossed;
                    if (again) {
                        running.pc = @intCast(op.value);
                    } else {
                        self.loop_depth -= 1;
                    }
                },
                .leave => {
                    if (self.loop_depth == 0) return error.LoopMismatch;
                    const frame = self.loop_stack[self.loop_depth - 1];
                    if (!frame.leave_keeps_frame) self.loop_depth -= 1;
                    running.pc = frame.exit_pc;
                },
                .print_string => {
                    const address = try self.memoryAddress(op.value, 1);
                    const length = self.memory[address];
                    const start = try self.memoryAddress(op.value + 1, length);
                    self.write(self.memory[start .. start + length]);
                    try self.checkOutputError();
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
                    const defining_id = running.defining_word orelse return error.InvalidDefinition;
                    self.words[created_id].does_code_start = running.pc;
                    self.words[created_id].does_code_end = self.words[defining_id].code_end;
                    self.words[created_id].has_does = true;
                    self.last_created_word = null;
                    // The defining word ends here, as at EXIT.
                    if (counted) self.traceRunning(running.*, false);
                    if (!try self.returnToCaller(running, entry_frames)) return;
                },
                .exit => {
                    if (counted) self.traceRunning(running.*, false);
                    if (!try self.returnToCaller(running, entry_frames)) return;
                },
                .local_frame => if (running.locals_frame == 0) {
                    const size = self.words[try self.wordId(op.value)].locals_size;
                    if (self.sizes.localsEnd() - self.locals_top < size) return error.ReturnStackOverflow;
                    const start: usize = @intCast(self.locals_top);
                    @memset(self.memory[start .. start + size], 0);
                    running.locals_frame = self.locals_top;
                    self.locals_top += size;
                },
                .local_store, .local_fetch, .local_address, .local_execute => {
                    if (running.locals_frame == 0) return error.InvalidAddress;
                    const base: Cell = running.locals_frame;
                    const address = base + (op.value & 0xffff_ffff);
                    const kind: LocalKind = @fromBackingInt(@intCast(op.value >> 32));
                    switch (op.kind) {
                        .local_store => try self.storeLocal(address, kind),
                        .local_fetch => try self.fetchLocal(address, kind),
                        .local_address => try self.push(address),
                        .local_execute => {
                            if (defs.debug_enabled) self.outer_pc = running.pc;
                            try self.wordInLoop(counted, try self.wordId(try self.readCell(address)), running);
                        },
                        else => unreachable,
                    }
                },
            }
        }
    }

    /// Runs a built-in word: each `words_*` file in src/core lists the words it executes,
    /// and every word must be in exactly one list.
    pub fn checkOutputError(self: *State) RuntimeError!void {
        if (self.output_error) |ior| {
            self.output_error = null;
            return self.throwCode(ior);
        }
    }

    pub fn executeBuiltin(self: *State, builtin: Builtin) RuntimeError!void {
        // The table of excluded words is computed while this switch is expanded.
        @setEvalBranchQuota(10_000);
        const result: RuntimeError!void = switch (builtin) {
            inline else => |word| if (comptime defs.isExcludedBuiltin(word))
                error.InvalidExecutionToken
            else
                word_modules[word_owner[@backingInt(word)]].execute(self, word),
        };
        // write() cannot throw; surface its first file error at the word boundary
        // so a callback's CATCH can handle it before continuing.
        try self.checkOutputError();
        try result;
        // --coverage: a block starts after a word of a control structure, however the
        // word was reached: by its name, by another name (SYNONYM), or from a word
        // that POSTPONEs it. The place is that of the word being read.
        if (defs.debug_enabled and self.cover_blocks and self.compiling and startsBlock(builtin)) self.markBlock(self.columnAfterWord());
    }

    const word_modules = .{ @import("core/words_parsing.zig"), @import("core/words_loops.zig"), @import("core/quotations.zig"), @import("core/words_compilation_tokens.zig"), @import("core/words_terminal.zig"), @import("core/string_values.zig"), @import("core/words_string_edit.zig"), @import("core/words_text.zig"), @import("core/words_buffers.zig"), @import("core/words_data.zig"), @import("core/words_width.zig"), words_stack, words_arithmetic, @import("core/words_numeric.zig"), words_memory, words_output, words_input, words_compiling, words_float, words_pictured, words_dictionary, words_system, @import("core/blocks.zig"), words_files, words_strings, words_help, words_defining, words_graphics, words_audio, words_xchar, words_tools, words_debug };

    /// For each built-in word, the index in `word_modules` of the file that executes it.
    const word_owner = blk: {
        @setEvalBranchQuota(100_000);
        const count = @typeInfo(Builtin).@"enum".field_names.len;
        var owner: [count]?usize = @splat(null);
        for (word_modules, 0..) |module, index| {
            for (module.words) |word| {
                if (owner[@backingInt(word)] != null) @compileError(@tagName(word) ++ " is in two words_* lists");
                owner[@backingInt(word)] = index;
            }
        }
        var result: [count]usize = undefined;
        for (owner, 0..) |index, slot| {
            result[slot] = index orelse @compileError(@tagName(@as(Builtin, @fromBackingInt(@intCast(slot)))) ++ " is in no words_* list");
        }
        break :blk result;
    };
    /// Pops a byte count; negative counts are treated as 0 and huge ones as memory-sized.
    pub fn popLength(self: *State) RuntimeError!usize {
        const count = try self.pop();
        return if (count < 0) 0 else @intCast(@min(count, self.memory.len));
    }

    pub fn writeMemory(self: *State, address: Cell, length: usize) void {
        const start: usize = @intCast(address);
        self.write(self.memory[start .. start + length]);
    }

    pub fn copyMemory(self: *State, destination: Cell, source: Cell, length: usize) RuntimeError!void {
        try @import("core/address_registry.zig").copy(self, destination, source, length, .move);
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
        if (self.data_depth == self.data_stack.len) return error.StackOverflow;
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
        if (self.float_depth == self.float_stack.len) return error.FloatStackOverflow;
        self.float_stack[self.float_depth] = value;
        self.float_depth += 1;
    }

    pub fn loopFrame(self: *State, nesting: usize) RuntimeError!Loop {
        if (self.loop_depth < nesting) return error.LoopMismatch;
        return self.loop_stack[self.loop_depth - nesting];
    }

    /// Validates that `length` bytes starting at `address` lie inside logical memory.
    pub fn memoryAddress(self: *State, address: Cell, length: usize) RuntimeError!usize {
        if (address < 0 or address > @as(Cell, @intCast(self.memory.len))) return error.InvalidAddress;
        const start: usize = @intCast(address);
        if (length > self.memory.len - start) return error.InvalidAddress;
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
        if (self.addresses.count != 0) @import("core/address_registry.zig").written(self, address, cell_size, true);
    }

    pub fn readFloat(self: *State, address: Cell) RuntimeError!Float {
        return bitsFloat(try self.readCell(address));
    }

    pub fn writeFloat(self: *State, address: Cell, value: Float) RuntimeError!void {
        try self.writeCell(address, floatBits(value));
    }

    pub fn reserveData(self: *State, amount: Cell) RuntimeError!void {
        const next, const overflow = @addWithOverflow(self.data_here, amount);
        if (overflow != 0 or next < data_start or next > self.sizes.dataLimit()) return error.MemoryExhausted;
        if (next < self.data_here) @import("core/address_registry.zig").discardRange(self, next, self.data_here, .data, true);
        self.data_here = next;
    }
};
