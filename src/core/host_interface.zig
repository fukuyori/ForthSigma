//! What the host provides to the core: output, input, files, and other services.

const defs = @import("defs.zig");
const forth = @import("../forth.zig");
const memory_map = @import("memory_map.zig");
const Cell = memory_map.Cell;
const Double = memory_map.Double;
const RuntimeError = defs.RuntimeError;
const State = forth.State;
const UCell = memory_map.UCell;

pub const FileAccess = enum { read_only, write_only, read_write };

pub const FileResult = struct { value: UCell = 0, ior: Cell = 0 };
/// null byte means EOF; an I/O error has a nonzero ior instead.
pub const FileKeyResult = struct { byte: ?u8 = null, ior: Cell = 0 };

/// `found` is false only at the end of the file with nothing read.
pub const LineResult = struct { length: usize = 0, found: bool = false, ior: Cell = 0 };

/// Host file operations. Ids are opaque cells; the standard streams use the fixed ids above.
pub const FileOps = struct {
    /// Create one directory. POSIX applies mode at creation subject to umask;
    /// Windows CRT ignores it. Existing names return errnoIor(17).
    mkdir: ?*const fn (?*anyopaque, []const u8, Cell) Cell = null,
    /// Writes a NUL-terminated cwd; value excludes NUL. Failure uses a nonzero ior.
    get_dir: ?*const fn (?*anyopaque, []u8) FileResult = null,
    /// Changes process cwd to the supplied expanded byte path.
    set_dir: ?*const fn (?*anyopaque, []const u8) Cell = null,
    /// Home directory (empty user means current); null means unknown/unsupported.
    user_home: ?*const fn (?*anyopaque, []const u8, []u8) RuntimeError!?usize = null,
    /// Opens an existing file, or creates and truncates one when `create` is set.
    open: *const fn (?*anyopaque, []const u8, FileAccess, bool) FileResult,
    close: *const fn (?*anyopaque, Cell) Cell,
    /// Reads up to `buffer.len` bytes of one line, without the LF, CR or CRLF terminator.
    read_line: *const fn (?*anyopaque, Cell, []u8) LineResult,
    /// Reads up to `buffer.len` bytes as they are; the value is the count, 0 at the end.
    read: *const fn (?*anyopaque, Cell, []u8) FileResult,
    write: *const fn (?*anyopaque, Cell, []const u8) Cell,
    size: *const fn (?*anyopaque, Cell) FileResult,
    reposition: *const fn (?*anyopaque, Cell, UCell) Cell,
    /// The read and write position.
    position: *const fn (?*anyopaque, Cell) FileResult,
    /// Cuts the file to the size or extends it with zero bytes; the position stays.
    resize: *const fn (?*anyopaque, Cell, UCell) Cell,
    flush: *const fn (?*anyopaque, Cell) Cell,
    delete: *const fn (?*anyopaque, []const u8) Cell,
    rename: *const fn (?*anyopaque, []const u8, []const u8) Cell,
    /// Whether the named file exists; the value is R/O, W/O, or R/W, as it can be opened.
    status: *const fn (?*anyopaque, []const u8) FileResult,
    /// CREATE-FILE with explicit nine-bit permissions, subject to the host umask.
    /// This must apply during creation, not chmod an existing file after truncation.
    create_mode: ?*const fn (?*anyopaque, []const u8, FileAccess, u16) FileResult = null,
    /// STDIN is raw byte input; terminal Ctrl+C may return UserInterrupt.
    key: ?*const fn (?*anyopaque, Cell) RuntimeError!FileKeyResult = null,
    /// Nonblocking byte readiness, including unread/library-buffered data.
    /// Querying must not consume a byte or change the EOF indication.
    ready: ?*const fn (?*anyopaque, Cell) RuntimeError!FileResult = null,
    /// The observed EOF indication, not an offset/size comparison.
    eof: ?*const fn (?*anyopaque, Cell) FileResult = null,
};

/// A terminal's size in characters, and in pixels when the host knows it (0 otherwise).
pub const TerminalSize = struct { columns: u32, rows: u32, x_pixels: u32 = 0, y_pixels: u32 = 0 };

/// The mouse buttons in InputEvent: 1 left, 2 right, 4 middle.
pub const MouseButtons = u8;

pub const ColorMode = @import("graphics_palette.zig").ColorMode;

/// One thing the user did, as the host's input gives it without waiting (INKEY, MOUSE).
pub const InputEvent = union(enum) {
    /// A byte from the terminal as it came, escape sequences included; the graphics
    /// words decode the keys and the mouse reports in it.
    byte: u8,
    /// A key the host decoded itself from the terminal (a Windows console): a byte of
    /// UTF-8 text, or one of the key codes of graphics_input from 256 up.
    key: u32,
    /// The same, pressed in the window: it stays when the terminal restarts.
    window_key: u32,
    /// A key of `key` was released (a Windows console tells when, and when it loses the
    /// focus): KEY-HELD? no longer holds it.
    key_release: u32,
    /// The same for `window_key`.
    window_key_release: u32,
    /// The mouse on the terminal: its character cell (column and row from 0, counted on
    /// the screen as `cursor_fn` counts them) and the buttons held.
    /// `wheel` is 1 for a notch of the wheel up (away from the user), -1 down, else 0.
    terminal_mouse: struct { column: i32, row: i32, buttons: MouseButtons, wheel: i8 = 0 },
    /// The mouse in the window: the pixel of the image under it, the buttons held, and
    /// the wheel as above. A host gives each press and release, also when the program
    /// reads them later (MOUSE-EVENT); moves may be given only as the last place.
    window_mouse: struct { x: i32, y: i32, buttons: MouseButtons, wheel: i8 = 0 },
    /// The terminal gives single keys again after its line input: what the graphics
    /// words kept of the terminal's input before (keys not yet read, a sequence not
    /// ended, buttons held) is dropped, as the host dropped its own.
    restarted,
};

/// A glyph the host drew for TEXT (system_glyph_fn): its advance, and its box of
/// `width` × `height` pixels from `left` pixels right of the pen (negative: to the left)
/// and from the top of the line.
pub const SystemGlyph = struct { advance: i32, left: i32, width: u32, height: u32 };

/// A position on the terminal's screen: column and row from 0.
pub const CursorPosition = struct { column: i32, row: i32 };

/// The local date and time, for TIME&DATE: month 1 to 12, the full year.
pub const LocalTime = struct { second: Cell, minute: Cell, hour: Cell, day: Cell, month: Cell, year: Cell };

/// What audio_wait_fn saw while it waited.
pub const AudioWait = enum {
    /// Only the time passed.
    waited,
    /// Ctrl+C was pressed (as a signal: the terminal has its line input).
    interrupted,
    /// The time passed, and the terminal gives single keys (input_fn has been used):
    /// Ctrl+C then comes as an input event, which the core reads itself.
    read_input,
};

pub const Writer = struct {
    gamepad_ops: ?*const @import("gamepad.zig").Ops = null,
    context: ?*anyopaque,
    write_fn: *const fn (?*anyopaque, []const u8) void,
    /// Writes to the log of --debug-log (lines of JSON); null without one.
    log_fn: ?*const fn (?*anyopaque, []const u8) void = null,
    read_fn: ?*const fn (?*anyopaque, []u8) ?[]const u8 = null,
    load_fn: ?*const fn (?*anyopaque, []const u8, *State) RuntimeError!void = null,
    save_fn: ?*const fn (?*anyopaque, []const u8, *State) RuntimeError!void = null,
    savesys_fn: ?*const fn (?*anyopaque, []const u8, *State) RuntimeError!void = null,
    key_fn: ?*const fn (?*anyopaque) ?u8 = null,
    /// Monotonic milliseconds for the total escape-sequence deadline.
    monotonic_ms_fn: ?*const fn (?*anyopaque) i64 = null,
    /// A byte or standard special key. timeout_ms < 0 waits; 0 polls.
    event_key_fn: ?*const fn (?*anyopaque, i32) RuntimeError!?Cell = null,
    /// Take only bytes held by unread_fn, without polling/reading the device.
    /// These bytes precede any deferred special event from EKEY.
    buffered_key_fn: ?*const fn (?*anyopaque) RuntimeError!?u8 = null,
    key_ready_fn: ?*const fn (?*anyopaque) bool = null,
    /// Gives back a byte that key_fn gave and XKEY did not take (one that does not
    /// continue a character): the next read of the terminal input, by any word, gets it
    /// first. Repeated calls push bytes back in reverse order.
    /// Without it, only KEY, XKEY and EKEY get the bytes back.
    unread_fn: ?*const fn (?*anyopaque, u8) void = null,
    sleep_fn: ?*const fn (?*anyopaque, Cell) RuntimeError!void = null,
    /// Microseconds since the Unix epoch.
    utime_fn: ?*const fn (?*anyopaque) RuntimeError!Double = null,
    local_time_fn: ?*const fn (?*anyopaque) RuntimeError!LocalTime = null,
    /// Copies the variable's value into the buffer and returns its length, or null when unset.
    getenv_fn: ?*const fn (?*anyopaque, []const u8, []u8) RuntimeError!?usize = null,
    /// Runs a shell command and returns the status `system` gave; a non-zero status is not an error.
    system_fn: ?*const fn (?*anyopaque, []const u8) RuntimeError!Cell = null,
    file_ops: ?*const FileOps = null,
    /// Gives a graphics image of that many 32-bit pixels, outside logical memory. On
    /// success the host releases the buffer it gave before and returns the new one; on
    /// failure it returns null and keeps the buffer it gave before. A buffer of another
    /// length is an error, after which the core uses no image.
    framebuffer_fn: ?*const fn (?*anyopaque, usize) ?[]u32 = null,
    /// Gives an image of the pool (NEW-IMAGE), that many 32-bit pixels outside logical
    /// memory, or null when there is none. It stays until image_free_fn frees it; the host
    /// frees what is left when the program ends.
    image_alloc_fn: ?*const fn (?*anyopaque, usize) ?[]u32 = null,
    /// Frees an image image_alloc_fn gave.
    image_free_fn: ?*const fn (?*anyopaque, []u32) void = null,
    /// The size of the terminal that output goes to, or null when it is not a terminal
    /// (the graphics words then assume 80 columns and 24 rows).
    terminal_size_fn: ?*const fn (?*anyopaque) ?TerminalSize = null,
    /// Called with true before the graphics words write UTF-8 text to the terminal, and
    /// with false after it, for a host whose terminal needs to be told (a Windows
    /// console with another code page). The output written before the call must have
    /// reached the terminal first.
    terminal_utf8_fn: ?*const fn (?*anyopaque, bool) void = null,
    /// Shows the 32-bit pixels (0xAARRGGBB, rows from the top) of a width × height
    /// image in a window, which the host keeps open. The host copies the pixels, each
    /// as graphics_palette.convert gives it in the color mode (DISPLAY-COLORS). The
    /// last argument is the size of the part of the window that shows the image
    /// (WINDOW-SIZE), 0 0 for the image's size; the image keeps its proportions in it,
    /// and the rest is black.
    window_fn: ?*const fn (?*anyopaque, []const u32, u32, u32, ColorMode, [2]u32) RuntimeError!void = null,
    /// The next input event without waiting, or null when there is none. The first call
    /// lets the terminal give each key at once, without echo; the host gives it back its
    /// line input when the program next reads a line or a KEY, and at the end. The host
    /// does not stop the program at Ctrl+C here: it gives the byte 3, which INKEY throws.
    input_fn: ?*const fn (?*anyopaque) ?InputEvent = null,
    /// Asks the terminal to report the mouse (true) or to stop (false). The host stops
    /// the reports while the terminal has its line input, and at the end.
    mouse_fn: ?*const fn (?*anyopaque, bool) void = null,
    /// Where the cursor is on the terminal's screen, or null when it cannot tell. The
    /// output written before the call must have reached the terminal first.
    cursor_fn: ?*const fn (?*anyopaque) ?CursorPosition = null,
    /// Gives memory for a font LOAD-FONT reads, that many 64-bit words, outside logical
    /// memory, or null when there is none. The buffers given before stay until
    /// font_free_fn frees them (the core has at most two at a time).
    font_buffer_fn: ?*const fn (?*anyopaque, usize) ?[]u64 = null,
    /// Frees a buffer font_buffer_fn gave.
    font_free_fn: ?*const fn (?*anyopaque, []u64) void = null,
    /// Starts the Tcl program (TCL): `program` (when empty, the host's choice: the
    /// SIGMA_WISH environment variable, else a wish the host finds) with `script` as its
    /// script, with pipes to its standard input and output. One program at a time.
    process_start_fn: ?*const fn (?*anyopaque, []const u8, []const u8) RuntimeError!void = null,
    /// Writes to the program's standard input.
    process_write_fn: ?*const fn (?*anyopaque, []const u8) RuntimeError!void = null,
    /// Reads what the program wrote to its standard output: waits for at least one
    /// byte when `wait`, and otherwise gives 0 when there is none. HostFailed when the
    /// program has ended.
    process_read_fn: ?*const fn (?*anyopaque, []u8, bool) RuntimeError!usize = null,
    /// Ends the program, closing its standard input first. False when the host could
    /// not see it end (it was asked to, and its handles are closed all the same).
    process_stop_fn: ?*const fn (?*anyopaque) bool = null,
    /// Chooses the system's font of that name for TEXT, `height` pixels from the top of
    /// a line to its bottom. False when the system has no font of the name.
    system_font_fn: ?*const fn (?*anyopaque, []const u8, u32) RuntimeError!bool = null,
    /// Draws one character of the font system_font_fn chose: its coverage, 0 to 255 for
    /// each pixel, row after row of `width` bytes in the buffer, the box at most the
    /// given width wide and as high as the font. Null when the font has no glyph for it.
    system_glyph_fn: ?*const fn (?*anyopaque, u21, []u8, u32) ?SystemGlyph = null,
    /// The sound engine that the host's audio thread plays (REQUIRE-AUDIO's words), which
    /// the first call starts. The thread runs even without an audio device, in time, so
    /// that PLAY and PLAY? behave the same; null when the host cannot start it.
    audio_fn: ?*const fn (?*anyopaque) ?*@import("sound_engine.zig").Engine = null,
    /// Whether the audio thread's samples reach an audio device.
    audio_device_fn: ?*const fn (?*anyopaque) bool = null,
    /// Waits a few milliseconds for the audio thread (PLAY with its queues full). Until
    /// it returns, Ctrl+C does not end the program.
    audio_wait_fn: ?*const fn (?*anyopaque) AudioWait = null,

    pub fn write(self: Writer, bytes: []const u8) void {
        self.write_fn(self.context, bytes);
    }
};
