//! The terminal's input for INKEY and MOUSE: keys without waiting and without echo,
//! and the mouse. The first read switches the terminal from its line input (raw mode,
//! without signals, so that Ctrl+C reaches INKEY as a key); `leave` switches it back,
//! dropping what was typed for the program, before Sigma next reads a line or a KEY,
//! runs a SYSTEM command, or ends.
//!
//! On Linux and macOS the bytes come as the terminal sends them, and the core decodes
//! the escape sequences and the SGR mouse reports (asked for with `ESC [ ? 1003 h` and
//! `ESC [ ? 1006 h`); the cursor's place comes from a DSR request (`ESC [ 6 n`). A
//! Windows console gives its keys and mouse as input records, decoded here.

const std = @import("std");
const builtin = @import("builtin");
const forth = @import("forth.zig");

const InputEvent = forth.InputEvent;
const is_windows = builtin.os.tag == .windows;

/// Set at start-up: whether standard input and output are terminals.
pub var input_is_terminal = false;
pub var output_is_terminal = false;
/// Writes the host's buffered output, before anything here writes to the terminal.
pub var flush_output: *const fn () void = noFlush;

fn noFlush() void {}

/// Whether the terminal is in raw mode, whether MOUSE-ON asked for the mouse, and
/// whether the terminal is reporting it now (only in raw mode).
var raw = false;
var standard_keyboard = false;
var mouse_wanted = false;
var mouse_reporting = false;

/// Whether the terminal went to raw mode since next last gave an event: next tells the
/// core first, which then drops what it kept of the input before.
var restarted = false;

/// Bytes read while waiting for the reply to a DSR request, given before new ones (more
/// than fit are dropped, as keys pressed while the host is busy may be).
var queued: [256]u8 = undefined;
var queued_head: usize = 0;
var queued_len: usize = 0;

fn queue(byte: u8) void {
    if (queued_len == queued.len) return;
    queued[(queued_head + queued_len) % queued.len] = byte;
    queued_len += 1;
}

/// The next event from the terminal without waiting, or null.
pub fn next() ?InputEvent {
    if (!enter()) return null;
    if (restarted) {
        restarted = false;
        return .restarted;
    }
    if (takePendingByte()) |byte| return .{ .byte = byte };
    if (is_windows) {
        return windows.next(false);
    } else {
        var byte: [1]u8 = undefined;
        if (std.c.read(0, &byte, 1) == 1) return .{ .byte = byte[0] };
        return null;
    }
}

/// Bytes already read from the terminal must also precede canonical KEY/ACCEPT.
pub fn takePendingByte() ?u8 {
    if (queued_len == 0) return null;
    const byte = queued[queued_head];
    queued_head = (queued_head + 1) % queued.len;
    queued_len -= 1;
    return byte;
}

/// A standard keyboard byte or event, without changing GRAPHICS key values.
pub fn nextStandard() ?forth.Cell {
    standard_keyboard = true;
    if (!enter()) return null;
    if (is_windows) {
        if (takePendingByte()) |byte| return byte;
        while (windows.next(true)) |event| {
            switch (event) { .key => |code| return code, else => {} }
        }
        return null;
    }
    while (next()) |event| switch (event) { .byte => |byte| return byte, else => {} };
    return null;
}

/// MOUSE-ON and MOUSE-OFF: the terminal reports the mouse while it is in raw mode.
pub fn setMouse(on: bool) void {
    mouse_wanted = on;
    // A terminal that did not answer may be asked again after a new MOUSE-ON.
    if (on) cursor_unanswered = false;
    if (raw) report(on);
}

/// The cursor's place on the screen (column and row from 0), or null.
pub fn cursor() ?forth.CursorPosition {
    if (!output_is_terminal or cursor_unanswered or !enter()) return null;
    flush_output();
    const position = if (is_windows) windows.cursor() else posix.cursor();
    // A terminal that does not answer DSR is not asked again (each try waits 200 ms).
    if (position == null) cursor_unanswered = true;
    return position;
}

var cursor_unanswered = false;

/// Gives the terminal back its line input.
pub fn leave() void {
    if (!raw) return;
    if (mouse_reporting) report(false);
    if (is_windows) windows.leave() else posix.leave();
    raw = false;
    if (!standard_keyboard) queued_len = 0;
    standard_keyboard = false;
}

/// Whether the terminal gives single keys now (Ctrl+C is then a key, not a signal).
pub fn isRaw() bool {
    return raw;
}

fn enter() bool {
    if (raw) return true;
    if (!input_is_terminal) return false;
    if (!(if (is_windows) windows.enter() else posix.enter())) return false;
    raw = true;
    restarted = true;
    if (mouse_wanted) report(true);
    return true;
}

fn report(on: bool) void {
    mouse_reporting = on;
    if (is_windows) {
        windows.setMouse(on);
    } else if (output_is_terminal) {
        flush_output();
        // Any motion (1003) in the SGR form (1006), which has no limit on the position.
        posix.writeAll(if (on) "\x1b[?1003h\x1b[?1006h" else "\x1b[?1006l\x1b[?1003l");
    }
}

/// The terminal's settings of Linux and macOS (termios), with the room the C library's
/// structure needs. On Linux, std.c.termios is the kernel's structure (44 bytes), but
/// the C library's is 60 bytes: glibc's tcgetattr writes them all, over what follows a
/// std.c.termios, and its tcsetattr reads the speeds there. The fields used here are at
/// the same places in both. The room is copied with the settings, so that tcsetattr
/// gets back what tcgetattr gave.
pub const TerminalSettings = extern struct {
    termios: std.c.termios,
    room: [64]u8 = @splat(0),

    /// Reads the settings of standard input; whether it did.
    pub fn get(self: *TerminalSettings) bool {
        self.room = @splat(0);
        return std.c.tcgetattr(0, &self.termios) == 0;
    }

    /// Sets them at once; whether it did.
    pub fn set(self: *const TerminalSettings) bool {
        return std.c.tcsetattr(0, .NOW, &self.termios) == 0;
    }
};

const posix = struct {
    extern "c" fn tcflush(c_int, c_int) c_int;
    const input_flush: c_int = if (builtin.os.tag.isDarwin()) 1 else 0;

    var saved: TerminalSettings = undefined;

    fn enter() bool {
        if (!saved.get()) return false;
        var changed = saved;
        const settings = &changed.termios;
        settings.lflag.ICANON = false;
        settings.lflag.ECHO = false;
        settings.lflag.ISIG = false;
        settings.lflag.IEXTEN = false;
        settings.iflag.IXON = false;
        settings.cc[@intFromEnum(std.c.V.MIN)] = 0;
        settings.cc[@intFromEnum(std.c.V.TIME)] = 0;
        return changed.set();
    }

    fn leave() void {
        if (!standard_keyboard) _ = tcflush(0, input_flush);
        _ = saved.set();
    }

    fn writeAll(bytes: []const u8) void {
        var rest = bytes;
        while (rest.len != 0) {
            const written = std.c.write(1, rest.ptr, rest.len);
            if (written <= 0) {
                if (written < 0 and std.c._errno().* == @intFromEnum(std.c.E.INTR)) continue;
                return;
            }
            rest = rest[@intCast(written)..];
        }
    }

    /// Milliseconds of a clock that does not go back.
    fn milliseconds() i64 {
        var time: std.c.timespec = undefined;
        if (std.c.clock_gettime(std.c.CLOCK.MONOTONIC, &time) != 0) return 0;
        return @as(i64, time.sec) * 1000 + @divTrunc(@as(i64, time.nsec), 1_000_000);
    }

    /// Sends a DSR request and reads the reply `ESC [ row ; column R` for at most 200 ms,
    /// however much other input comes meanwhile; that input is queued for next.
    fn cursor() ?forth.CursorPosition {
        writeAll("\x1b[6n");
        var reply: [32]u8 = undefined;
        var length: usize = 0;
        const deadline = milliseconds() + 200;
        while (true) {
            const left = deadline - milliseconds();
            if (left <= 0) break;
            var descriptor = [_]std.c.pollfd{.{ .fd = 0, .events = std.c.POLL.IN, .revents = 0 }};
            if (std.c.poll(&descriptor, 1, @intCast(@min(left, 200))) <= 0) continue;
            var byte: [1]u8 = undefined;
            if (std.c.read(0, &byte, 1) != 1) continue;
            if (length == reply.len) {
                for (reply) |kept| queue(kept);
                length = 0;
            }
            reply[length] = byte[0];
            length += 1;
            if (byte[0] != 'R') continue;
            const start = std.mem.lastIndexOfScalar(u8, reply[0..length], 0x1b) orelse continue;
            if (parseReply(reply[start..length])) |position| {
                for (reply[0..start]) |kept| queue(kept);
                return position;
            }
        }
        for (reply[0..length]) |kept| queue(kept);
        return null;
    }

    fn parseReply(bytes: []const u8) ?forth.CursorPosition {
        if (bytes.len < 6 or bytes[1] != '[') return null;
        const body = bytes[2 .. bytes.len - 1];
        const separator = std.mem.indexOfScalar(u8, body, ';') orelse return null;
        const row = std.fmt.parseInt(i32, body[0..separator], 10) catch return null;
        const column = std.fmt.parseInt(i32, body[separator + 1 ..], 10) catch return null;
        // A terminal counts from 1; far larger values are not a reply.
        if (row < 1 or column < 1 or row > 100_000 or column > 100_000) return null;
        return .{ .column = column - 1, .row = row - 1 };
    }
};

const windows = struct {
    const Handle = *anyopaque;
    const Coord = extern struct { x: i16, y: i16 };
    const ScreenInfo = extern struct { size: Coord, cursor: Coord, attributes: u16, window: [4]i16, maximum_size: Coord };
    const InputRecord = extern struct { event_type: u16, padding: u16, data: [16]u8 };
    extern "kernel32" fn GetStdHandle(u32) callconv(.winapi) ?Handle;
    extern "kernel32" fn GetConsoleMode(Handle, *u32) callconv(.winapi) c_int;
    extern "kernel32" fn SetConsoleMode(Handle, u32) callconv(.winapi) c_int;
    extern "kernel32" fn GetNumberOfConsoleInputEvents(Handle, *u32) callconv(.winapi) c_int;
    extern "kernel32" fn ReadConsoleInputW(Handle, *InputRecord, u32, *u32) callconv(.winapi) c_int;
    extern "kernel32" fn FlushConsoleInputBuffer(Handle) callconv(.winapi) c_int;
    extern "kernel32" fn GetConsoleScreenBufferInfo(Handle, *ScreenInfo) callconv(.winapi) c_int;

    const processed_input: u32 = 0x0001;
    const line_input: u32 = 0x0002;
    const echo_input: u32 = 0x0004;
    const mouse_input: u32 = 0x0010;
    const quick_edit: u32 = 0x0040;
    const extended_flags: u32 = 0x0080;
    const virtual_terminal_input: u32 = 0x0200;
    const key_event: u16 = 0x0001;
    const mouse_event: u16 = 0x0002;
    const focus_event: u16 = 0x0010;
    const mouse_wheeled: u32 = 0x0004;
    const mouse_hwheeled: u32 = 0x0008;

    var input: ?Handle = null;
    var saved_mode: u32 = 0;
    var raw_mode: u32 = 0;
    /// The UTF-8 bytes of a character after the first, which next gives in turn.
    var pending: [3]u8 = undefined;
    var pending_len: usize = 0;
    var high_surrogate: u16 = 0;
    /// The key code each virtual key gave when it went down, plus 1 (0: not down), so
    /// that its release can be told (KEY-HELD?); whether the keys down are being
    /// released, one each call, after the console lost the focus; and an event to give
    /// after the release of another code of the same key.
    var down: [256]u32 = @splat(0);
    var releasing = false;
    var after: ?InputEvent = null;

    /// The event of a key pressed, remembering its code; when the key was down with
    /// another code (a held key that gives another character), the release of that one
    /// comes first.
    fn press(virtual_key: u16, code: u32, event: InputEvent) InputEvent {
        if (virtual_key >= down.len or !(code < 0x80 or code >= 256)) return event;
        const old = down[virtual_key];
        down[virtual_key] = code + 1;
        if (old == 0 or old == code + 1) return event;
        after = event;
        return .{ .key_release = old - 1 };
    }

    fn handle(which: i32) ?Handle {
        return GetStdHandle(@bitCast(which));
    }

    fn enter() bool {
        const console = handle(-10) orelse return false;
        if (GetConsoleMode(console, &saved_mode) == 0) return false;
        // Without line input, echo, and Ctrl+C handling (it comes as a key); without
        // the selection by the mouse, which would take the mouse's input.
        raw_mode = (saved_mode & ~(processed_input | line_input | echo_input | quick_edit | virtual_terminal_input)) | extended_flags;
        if (SetConsoleMode(console, raw_mode) == 0) return false;
        input = console;
        return true;
    }

    fn leave() void {
        const console = input orelse return;
        if (!standard_keyboard) _ = FlushConsoleInputBuffer(console) else {
            for (pending[0..pending_len]) |byte| queue(byte);
        }
        _ = SetConsoleMode(console, saved_mode);
        pending_len = 0;
        high_surrogate = 0;
        down = @splat(0);
        releasing = false;
        after = null;
    }

    fn setMouse(on: bool) void {
        const console = input orelse return;
        raw_mode = if (on) raw_mode | mouse_input else raw_mode & ~mouse_input;
        _ = SetConsoleMode(console, raw_mode);
    }

    fn screen() ?ScreenInfo {
        var info: ScreenInfo = undefined;
        if (GetConsoleScreenBufferInfo(handle(-11) orelse return null, &info) == 0) return null;
        return info;
    }

    fn cursor() ?forth.CursorPosition {
        const info = screen() orelse return null;
        return .{ .column = @as(i32, info.cursor.x) - info.window[0], .row = @as(i32, info.cursor.y) - info.window[1] };
    }

    fn keyCode(virtual_key: u16) ?u32 {
        return switch (virtual_key) {
            0x26 => 256,
            0x28 => 257,
            0x25 => 258,
            0x27 => 259,
            0x24 => 260,
            0x23 => 261,
            0x21 => 262,
            0x22 => 263,
            0x2D => 264,
            0x2E => 265,
            0x70...0x7B => 266 + @as(u32, virtual_key - 0x70),
            else => null,
        };
    }

    fn next(standard: bool) ?InputEvent {
        if (after) |event| {
            after = null;
            return event;
        }
        if (pending_len != 0) {
            const byte = pending[0];
            std.mem.copyForwards(u8, pending[0 .. pending_len - 1], pending[1..pending_len]);
            pending_len -= 1;
            return .{ .key = byte };
        }
        if (releasing) {
            for (&down) |*code| {
                if (code.* == 0) continue;
                const old = code.* - 1;
                code.* = 0;
                return .{ .key_release = old };
            }
            releasing = false;
        }
        const console = input orelse return null;
        while (true) {
            var count: u32 = 0;
            if (GetNumberOfConsoleInputEvents(console, &count) == 0 or count == 0) return null;
            var record: InputRecord = undefined;
            var read: u32 = 0;
            if (ReadConsoleInputW(console, &record, 1, &read) == 0 or read == 0) return null;
            const data = &record.data;
            switch (record.event_type) {
                key_event => {
                    const virtual_key = std.mem.readInt(u16, data[6..8], .little);
                    if (std.mem.readInt(i32, data[0..4], .little) == 0) {
                        if (virtual_key >= down.len or down[virtual_key] == 0) continue;
                        const code = down[virtual_key] - 1;
                        down[virtual_key] = 0;
                        return .{ .key_release = code };
                    }
                    const unit = std.mem.readInt(u16, data[10..12], .little);
                    if (keyCode(virtual_key)) |key| {
                        if (standard) {
                            const base: u32 = switch (key) {
                                256 => 0x80000002, 257 => 0x80000003,
                                258 => 0x80000000, 259 => 0x80000001,
                                266...277 => 0x8000000b + key - 266,
                                else => 0x80000004 + key - 260,
                            };
                            const control = std.mem.readInt(u32, data[12..16], .little);
                            const masks: u32 = (if (control & 0x10 != 0) @as(u32, 0x10000000) else 0) |
                                (if (control & 0x03 != 0) @as(u32, 0x20000000) else 0) |
                                (if (control & 0x0c != 0) @as(u32, 0x40000000) else 0);
                            return .{ .key = base | masks };
                        }
                        return press(virtual_key, key, .{ .key = key });
                    }
                    if (unit == 0) continue;
                    if (unit >= 0xD800 and unit < 0xDC00) {
                        high_surrogate = unit;
                        continue;
                    }
                    var code_point: u21 = unit;
                    if (unit >= 0xDC00 and unit < 0xE000) {
                        if (high_surrogate == 0) continue;
                        code_point = 0x10000 + ((@as(u21, high_surrogate) - 0xD800) << 10) + (unit - 0xDC00);
                    }
                    high_surrogate = 0;
                    var bytes: [4]u8 = undefined;
                    const length = std.unicode.utf8Encode(code_point, &bytes) catch continue;
                    @memcpy(pending[0 .. length - 1], bytes[1..length]);
                    pending_len = length - 1;
                    return press(virtual_key, if (code_point < 0x80) code_point else 0x80, .{ .key = bytes[0] });
                },
                mouse_event => {
                    const flags = std.mem.readInt(u32, data[12..16], .little);
                    if (flags & mouse_hwheeled != 0) continue;
                    const x = std.mem.readInt(i16, data[0..2], .little);
                    const y = std.mem.readInt(i16, data[2..4], .little);
                    const state = std.mem.readInt(u32, data[4..8], .little);
                    // 1 left, 2 right, 4 the second from the left (middle), as in InputEvent.
                    const buttons: u8 = @truncate(state & 7);
                    // The wheel: the high word of the button state is the distance, above
                    // 0 up (away from the user).
                    const distance: i16 = @bitCast(@as(u16, @truncate(state >> 16)));
                    const wheel: i8 = if (flags & mouse_wheeled == 0 or distance == 0) 0 else if (distance > 0) 1 else -1;
                    const info = screen() orelse return null;
                    return .{ .terminal_mouse = .{ .column = @as(i32, x) - info.window[0], .row = @as(i32, y) - info.window[1], .buttons = buttons, .wheel = wheel } };
                },
                // The console lost the focus: the keys down will not tell their release.
                focus_event => {
                    if (std.mem.readInt(i32, data[0..4], .little) != 0) continue;
                    releasing = true;
                    return windows.next(standard);
                },
                else => continue,
            }
        }
    }
};

test "a DSR reply gives the cursor's place only for positions from 1" {
    const place = posix.parseReply("\x1b[12;5R") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(i32, 11), place.row);
    try std.testing.expectEqual(@as(i32, 4), place.column);
    const wrong = [_][]const u8{ "\x1b[0;5R", "\x1b[12;0R", "\x1b[-2147483648;1R", "\x1b[99999999999;1R", "\x1b[100001;1R", "\x1b[12R", "\x1b[a;bR", "\x1b[;R" };
    for (wrong) |reply| try std.testing.expect(posix.parseReply(reply) == null);
}

test "terminal read-ahead is shared in FIFO order with canonical input" {
    queued_head = 0;
    queued_len = 0;
    defer { queued_head = 0; queued_len = 0; }
    queue(0xe6);
    queue(0x97);
    queue(0xa5);
    try std.testing.expectEqual(@as(?u8, 0xe6), takePendingByte());
    try std.testing.expectEqual(@as(?u8, 0x97), takePendingByte());
    try std.testing.expectEqual(@as(?u8, 0xa5), takePendingByte());
    try std.testing.expect(takePendingByte() == null);
}
