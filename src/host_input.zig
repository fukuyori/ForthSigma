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
/// The host's signal service restores pending temporary modes before raw/cooked
/// changes. False prevents enter from capturing a temporary NS mode as its baseline.
pub var before_mode_change: *const fn () bool = noModeRecovery;
fn noModeRecovery() bool {
    return true;
}
var mode_generation: u64 = 0;
pub fn modeGeneration() u64 {
    return mode_generation;
}

fn noFlush() void {}

test "input mode changes consult pending recovery before taking a raw baseline" {
    const saved_hook = before_mode_change;
    const saved_raw = raw;
    const saved_terminal = input_is_terminal;
    defer before_mode_change = saved_hook;
    defer raw = saved_raw;
    defer input_is_terminal = saved_terminal;
    const Fake = struct {
        var calls: usize = 0;
        fn fail() bool {
            calls += 1;
            return false;
        }
    };
    Fake.calls = 0;
    before_mode_change = Fake.fail;
    input_is_terminal = false;
    raw = false;
    try std.testing.expect(!enter());
    raw = true;
    try std.testing.expect(!enter());
    raw = false;
    leave();
    try std.testing.expectEqual(@as(usize, 3), Fake.calls);
}

/// Whether the terminal is in raw mode, whether MOUSE-ON asked for the mouse, and
/// whether the terminal is reporting it now (only in raw mode).
var raw = false;
var standard_keyboard = false;
const presentation = @import("host_terminal.zig");
pub var modes = presentation.Manager{ .backend = .{ .apply = applyPresentation } };
pub var presentation_changed: *const fn () void = noFlush;
var presentation_error: ?forth.RuntimeError = null;
pub fn takePresentationError() forth.RuntimeError!void {
    if (presentation_error) |err| {
        presentation_error = null;
        return err;
    }
}
fn failed(err: anyerror) void {
    presentation_error = if (err == error.HostUnavailable) error.HostUnavailable else error.HostFailed;
}
pub fn configurePresentation(available: bool) void {
    modes.available = available;
    modes.supported = if (available) (if (is_windows) presentation.all & ~presentation.paste else presentation.all) else if (is_windows and input_is_terminal) presentation.mouse else 0;
}
pub fn setPresentation(mask: u8) presentation.Error!void {
    if (!before_mode_change()) return error.HostFailed;
    try modes.set(mask);
    if (mask & presentation.mouse != 0) cursor_unanswered = false;
}
pub fn pausePresentation() presentation.Error!void {
    if (!before_mode_change()) return error.HostFailed;
    try modes.suspendModes();
}
pub fn resumePresentation() presentation.Error!void {
    try modes.resumeModes();
}
pub fn finishPresentation() presentation.Error!void {
    try modes.finish();
}
fn applyPresentation(_: ?*anyopaque, bit: u8, on: bool) error{HostFailed}!void {
    if (bit == presentation.mouse and is_windows) return windows.setMouse(on);
    const bytes: []const u8 = switch (bit) {
        presentation.alternate => if (on) "\x1b[?1049h" else "\x1b[?1049l",
        presentation.paste => if (on) "\x1b[?2004h" else "\x1b[?2004l",
        presentation.hidden_cursor => if (on) "\x1b[?25l" else "\x1b[?25h",
        presentation.mouse => if (on) "\x1b[?1003h\x1b[?1006h" else "\x1b[?1006l\x1b[?1003l",
        else => unreachable,
    };
    flush_output();
    presentation_changed();
    var rest = bytes;
    while (rest.len != 0) {
        if (is_windows) {
            const console = windows.handle(-11) orelse return error.HostFailed;
            var written: u32 = 0;
            if (windows.WriteFile(console, rest.ptr, @intCast(rest.len), &written, null) == 0 or written == 0) return error.HostFailed;
            rest = rest[written..];
        } else {
            const written = std.c.write(1, rest.ptr, rest.len);
            if (written < 0 and std.c._errno().* == @backingInt(std.c.E.INTR)) continue;
            if (written <= 0) return error.HostFailed;
            rest = rest[@intCast(written)..];
        }
    }
}

/// Whether the terminal went to raw mode since next last gave an event: next tells the
/// core first, which then drops what it kept of the input before.
var restarted = false;
var standard_seen_generation: u64 = 0;

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

// EXEC captures only already-raw input and never changes terminal modes.
var execution_captured = false;
pub const ExecutionOrigin = union(enum) { queued: usize, record: usize, after };
pub const ExecutionView = struct {
    const Packet = @import("core/standard_event.zig").Packet;
    packets: [320]Packet = undefined,
    origins: [320]?ExecutionOrigin = @splat(null),
    length: usize = 0,
    fn add(self: *@This(), packet: Packet, origin: ?ExecutionOrigin) void {
        std.debug.assert(self.length < self.packets.len);
        self.packets[self.length] = packet;
        self.origins[self.length] = origin;
        self.length += 1;
    }
    pub fn candidate(self: *const @This()) bool {
        for (self.packets[0..self.length]) |packet| if (packet.value == 3) return true;
        return false;
    }
};
pub fn captureExecution() forth.RuntimeError!void {
    if (!raw or !input_is_terminal) return;
    if (is_windows) return windows.captureExecution();
    // Reserve a complete cursor reply so DSR cannot overflow this queue.
    while (queued_len + 32 < queued.len) {
        var byte: [1]u8 = undefined;
        const count = std.c.read(0, &byte, 1);
        if (count == 1) {
            queue(byte[0]);
            execution_captured = true;
            continue;
        }
        if (count == 0) return;
        const code = std.c._errno().*;
        if (code == @backingInt(std.c.E.INTR)) continue;
        if (code == @backingInt(std.c.E.AGAIN)) return;
        return error.HostFailed;
    }
}
pub fn executionView() ExecutionView {
    var view = ExecutionView{};
    if (standard_seen_generation != mode_generation) view.add(.{ .value = 0, .reset = true }, null);
    for (0..queued_len) |index| view.add(.{ .value = queued[(queued_head + index) % queued.len] }, .{ .queued = index });
    if (is_windows) windows.executionView(&view);
    return view;
}
pub fn cancelExecution(origin: ExecutionOrigin) void {
    switch (origin) {
        .queued => |index| {
            std.debug.assert(index < queued_len and queued[(queued_head + index) % queued.len] == 3);
            for (index..queued_len - 1) |at| queued[(queued_head + at) % queued.len] = queued[(queued_head + at + 1) % queued.len];
            queued_len -= 1;
        },
        .record => |index| if (is_windows) {
            windows.records[(windows.record_head + index) % windows.records.len].cancelled = true;
        },
        .after => if (is_windows) {
            windows.after = null;
        },
    }
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
pub fn nextStandardPacket() ?@import("core/standard_event.zig").Packet {
    standard_keyboard = true;
    if (!enter()) return null;
    if (standard_seen_generation != mode_generation) {
        standard_seen_generation = mode_generation;
        return .{ .value = 0, .reset = true };
    }
    if (@import("host_resize.zig").take()) return .{ .value = @import("core/standard_keys.zig").winch };
    if (is_windows) {
        if (takePendingByte()) |byte| return .{ .value = byte };
        for (0..32) |_| {
            const event = windows.next(true) orelse return null;
            switch (event) {
                .key => |code| return .{ .value = code },
                .terminal_mouse => |value| return .{ .value = @import("core/standard_keys.zig").mouse | @as(forth.Cell, value.modifiers), .mouse = .{ .column = value.column, .row = value.row, .buttons = value.buttons, .wheel = value.wheel } },
                else => {},
            }
        }
        return null;
    }
    if (takePendingByte()) |byte| return .{ .value = byte };
    var byte: [1]u8 = undefined;
    return if (std.c.read(0, &byte, 1) == 1) .{ .value = byte[0] } else null;
}

pub fn nextStandard() ?forth.Cell {
    while (nextStandardPacket()) |packet| if (packet.mouse == null and !packet.reset) return packet.value;
    return null;
}

/// One terminal byte in raw mode. Extended Windows key events are not bytes;
/// ignore them just as mouse/release events are ignored by character input.
pub fn nextByte() ?u8 {
    standard_keyboard = true;
    if (!enter()) return null;
    if (is_windows) {
        if (takePendingByte()) |byte| return byte;
        for (0..32) |_| {
            const event = windows.next(true) orelse return null;
            switch (event) {
                .key => |code| if (code <= 255) {
                    return @intCast(code);
                },
                else => {},
            }
        }
        return null;
    }
    while (next()) |event| switch (event) {
        .byte => |byte| return byte,
        else => {},
    };
    return null;
}

/// MOUSE-ON and MOUSE-OFF: the terminal reports the mouse while it is in raw mode.
pub fn setMouse(on: bool) void {
    // Legacy MOUSE-ON works on a Windows input console even with redirected output.
    // TERM-MODE! remains strict about a VT-capable stdout.
    if (!before_mode_change()) {
        failed(error.HostFailed);
        return;
    }
    modes.setLegacyMouse(on) catch |err| {
        failed(err);
        return;
    };
    if (on) cursor_unanswered = false;
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
    _ = before_mode_change();
    if (!raw) return;
    mode_generation +%= 1;
    modes.setRaw(false) catch |err| failed(err);
    if (!(if (is_windows) windows.leave() else posix.leave())) {
        failed(error.HostFailed);
        return;
    }
    raw = false;
    if (!standard_keyboard and !execution_captured) queued_len = 0;
    execution_captured = false;
    standard_keyboard = false;
}

/// Whether the terminal gives single keys now (Ctrl+C is then a key, not a signal).
pub fn isRaw() bool {
    return raw;
}

fn enter() bool {
    if (!before_mode_change()) return false;
    if (raw) {
        modes.setRaw(true) catch |err| {
            failed(err);
            return false;
        };
        return true;
    }
    if (!input_is_terminal) return false;
    if (!(if (is_windows) windows.enter() else posix.enter())) return false;
    mode_generation +%= 1;
    raw = true;
    restarted = true;
    modes.setRaw(true) catch |err| {
        failed(err);
        if (if (is_windows) windows.leave() else posix.leave()) raw = false;
        modes.setRaw(false) catch |cleanup| failed(cleanup);
        return false;
    };
    return true;
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
        settings.cc[@backingInt(std.c.V.MIN)] = 0;
        settings.cc[@backingInt(std.c.V.TIME)] = 0;
        return changed.set();
    }

    fn leave() bool {
        if (!saved.set()) return false;
        if (!standard_keyboard) _ = tcflush(0, input_flush);
        return true;
    }

    fn writeAll(bytes: []const u8) void {
        var rest = bytes;
        while (rest.len != 0) {
            const written = std.c.write(1, rest.ptr, rest.len);
            if (written <= 0) {
                if (written < 0 and std.c._errno().* == @backingInt(std.c.E.INTR)) continue;
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
            if (queued_len + length == queued.len) break;
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

fn standardExtraKey(virtual_key: u16, control: u32) ?u32 {
    const keys = @import("core/standard_keys.zig");
    const masks: u32 = (if (control & 0x10 != 0) @as(u32, @intCast(keys.shift)) else 0) |
        (if (control & 0x03 != 0) @as(u32, @intCast(keys.alt)) else 0) |
        (if (control & 0x0c != 0) @as(u32, @intCast(keys.ctrl)) else 0);
    const offset: u32 = switch (virtual_key) {
        8 => if (masks != 0) 28 else return null,
        9 => if (masks != 0) 29 else return null,
        13 => if (masks != 0) 10 else return null,
        0x13 => 24,
        0x29 => 30,
        0xad => 25,
        0xae => 27,
        0xaf => 26,
        else => return null,
    };
    return @as(u32, @intCast(keys.special)) + offset | masks;
}

const windows = struct {
    const Handle = *anyopaque;
    const Coord = extern struct { x: i16, y: i16 };
    const ScreenInfo = extern struct { size: Coord, cursor: Coord, attributes: u16, window: [4]i16, maximum_size: Coord };
    const InputRecord = extern struct { event_type: u16, padding: u16, data: [16]u8 };
    extern "kernel32" fn GetStdHandle(u32) callconv(.winapi) ?Handle;
    extern "kernel32" fn WriteFile(Handle, [*]const u8, u32, *u32, ?*anyopaque) callconv(.winapi) c_int;
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
    const size_event: u16 = 0x0004;
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

    const Retained = struct { record: InputRecord, cancelled: bool = false };
    var records: [64]Retained = undefined;
    var record_head: usize = 0;
    var record_len: usize = 0;
    fn captureExecution() forth.RuntimeError!void {
        const console = input orelse return error.HostFailed;
        while (record_len < records.len and queued_len + 4 * (record_len + 1) + 32 <= queued.len) {
            var count: u32 = 0;
            if (GetNumberOfConsoleInputEvents(console, &count) == 0) return error.HostFailed;
            if (count == 0) return;
            var record: InputRecord = undefined;
            var read: u32 = 0;
            if (ReadConsoleInputW(console, &record, 1, &read) == 0 or read == 0) return error.HostFailed;
            records[(record_head + record_len) % records.len] = .{ .record = record };
            record_len += 1;
            execution_captured = true;
        }
    }
    fn executionView(view: *ExecutionView) void {
        if (after) |event| switch (event) {
            .key => |code| view.add(.{ .value = code }, .after),
            else => {},
        };
        for (pending[0..pending_len]) |byte| view.add(.{ .value = byte }, null);
        var high = high_surrogate;
        for (0..record_len) |index| {
            const kept = records[(record_head + index) % records.len];
            if (kept.cancelled) {
                high = 0;
                continue;
            }
            if (kept.record.event_type != key_event) continue;
            const data = &kept.record.data;
            if (std.mem.readInt(i32, data[0..4], .little) == 0) continue;
            const virtual = std.mem.readInt(u16, data[6..8], .little);
            const mods = std.mem.readInt(u32, data[12..16], .little);
            if (standardExtraKey(virtual, mods)) |key| {
                view.add(.{ .value = key }, null);
                continue;
            }
            if (keyCode(virtual) != null) {
                view.add(.{ .value = 0x80000000 }, null);
                continue;
            }
            const unit = std.mem.readInt(u16, data[10..12], .little);
            if (unit == 0) continue;
            if (unit >= 0xd800 and unit < 0xdc00) {
                high = unit;
                continue;
            }
            var point: u21 = unit;
            if (unit >= 0xdc00 and unit < 0xe000) {
                if (high == 0) continue;
                point = 0x10000 + ((@as(u21, high) - 0xd800) << 10) + (unit - 0xdc00);
            }
            high = 0;
            var bytes: [4]u8 = undefined;
            const length = std.unicode.utf8Encode(point, &bytes) catch continue;
            for (bytes[0..length]) |byte| view.add(.{ .value = byte }, .{ .record = index });
        }
    }

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
        raw_mode = (saved_mode & ~(processed_input | line_input | echo_input | quick_edit | virtual_terminal_input | mouse_input)) | extended_flags | (if (standard_keyboard) @as(u32, 0x0008) else 0);
        if (SetConsoleMode(console, raw_mode) == 0) return false;
        input = console;
        return true;
    }

    fn leave() bool {
        const console = input orelse return false;
        if (SetConsoleMode(console, saved_mode) == 0) return false;
        if (execution_captured) {
            var view = ExecutionView{};
            windows.executionView(&view);
            for (view.packets[0..view.length]) |packet| if (packet.value >= 0 and packet.value <= 255) {
                queue(@intCast(packet.value));
            };
        } else if (standard_keyboard) {
            for (pending[0..pending_len]) |byte| queue(byte);
        }
        if (!standard_keyboard) _ = FlushConsoleInputBuffer(console);
        record_len = 0;
        record_head = 0;
        pending_len = 0;
        high_surrogate = 0;
        down = @splat(0);
        releasing = false;
        after = null;
        return true;
    }

    fn setMouse(on: bool) error{HostFailed}!void {
        // A completed cooked restore supersedes old raw mouse flags.
        if (!raw) {
            if (on) return error.HostFailed;
            return;
        }
        const console = input orelse return error.HostFailed;
        raw_mode = if (on) raw_mode | mouse_input else raw_mode & ~mouse_input;
        if (SetConsoleMode(console, raw_mode) == 0) return error.HostFailed;
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

    fn releaseNext() ?InputEvent {
        for (&down) |*code| {
            if (code.* == 0) continue;
            const old = code.* - 1;
            code.* = 0;
            return .{ .key_release = old };
        }
        releasing = false;
        return null;
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
        if (releasing) if (releaseNext()) |event| return event;
        const console = input orelse return null;
        if (standard and raw_mode & 0x0008 == 0) {
            const updated = raw_mode | 0x0008;
            if (SetConsoleMode(console, updated) == 0) return null;
            raw_mode = updated;
        }
        for (0..32) |_| {
            var record: InputRecord = undefined;
            if (record_len != 0) {
                const kept = records[record_head];
                record_head = (record_head + 1) % records.len;
                record_len -= 1;
                if (kept.cancelled) {
                    high_surrogate = 0;
                    continue;
                }
                record = kept.record;
            } else {
                var count: u32 = 0;
                if (GetNumberOfConsoleInputEvents(console, &count) == 0 or count == 0) return null;
                var read: u32 = 0;
                if (ReadConsoleInputW(console, &record, 1, &read) == 0 or read == 0) return null;
            }
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
                    if (standard) {
                        const control = std.mem.readInt(u32, data[12..16], .little);
                        if (standardExtraKey(virtual_key, control)) |event| return .{ .key = event };
                    }
                    if (keyCode(virtual_key)) |key| {
                        if (standard) {
                            const base: u32 = switch (key) {
                                256 => 0x80000002,
                                257 => 0x80000003,
                                258 => 0x80000000,
                                259 => 0x80000001,
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
                size_event => {
                    // Deliver the notification before consuming the next key.
                    // Deferring it here lets next() return that key first.
                    if (standard) return .{ .key = @intCast(@import("core/standard_keys.zig").winch) };
                    continue;
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
                    const control = std.mem.readInt(u32, data[8..12], .little);
                    const mods: u32 = (if (control & 0x10 != 0) @as(u32, 0x10000000) else 0) | (if (control & 3 != 0) @as(u32, 0x20000000) else 0) | (if (control & 12 != 0) @as(u32, 0x40000000) else 0);
                    return .{ .terminal_mouse = .{ .modifiers = mods, .column = @as(i32, x) - info.window[0], .row = @as(i32, y) - info.window[1], .buttons = buttons, .wheel = wheel } };
                },
                // The console lost the focus: the keys down will not tell their release.
                focus_event => {
                    if (std.mem.readInt(i32, data[0..4], .little) != 0) continue;
                    releasing = true;
                    if (releaseNext()) |event| return event;
                    continue;
                },
                else => continue,
            }
        }
        return null;
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
    defer {
        queued_head = 0;
        queued_len = 0;
    }
    queue(0xe6);
    queue(0x97);
    queue(0xa5);
    try std.testing.expectEqual(@as(?u8, 0xe6), takePendingByte());
    try std.testing.expectEqual(@as(?u8, 0x97), takePendingByte());
    try std.testing.expectEqual(@as(?u8, 0xa5), takePendingByte());
    try std.testing.expect(takePendingByte() == null);
}

test "standard extra keys preserve plain controls and map modifiers media and pause" {
    const keys = @import("core/standard_keys.zig");
    try std.testing.expect(standardExtraKey(13, 0) == null);
    try std.testing.expect(standardExtraKey(9, 0) == null);
    try std.testing.expectEqual(@as(?u32, @intCast(keys.tab | keys.shift)), standardExtraKey(9, 0x10));
    try std.testing.expectEqual(@as(?u32, @intCast(keys.special + 10 | keys.ctrl)), standardExtraKey(13, 0x08));
    try std.testing.expectEqual(@as(?u32, @intCast(keys.special + 24)), standardExtraKey(0x13, 0));
    try std.testing.expectEqual(@as(?u32, @intCast(keys.special + 25)), standardExtraKey(0xad, 0));
    try std.testing.expectEqual(@as(?u32, @intCast(keys.special + 27)), standardExtraKey(0xae, 0));
    try std.testing.expectEqual(@as(?u32, @intCast(keys.special + 26)), standardExtraKey(0xaf, 0));
}

test "standard restart notification leaves graphics restart available" {
    const saved_raw = raw;
    const saved_standard = standard_keyboard;
    const saved_terminal = input_is_terminal;
    const saved_modes = modes;
    const saved_restart = restarted;
    const saved_generation = mode_generation;
    const saved_seen = standard_seen_generation;
    const saved_hook = before_mode_change;
    defer {
        raw = saved_raw;
        standard_keyboard = saved_standard;
        input_is_terminal = saved_terminal;
        modes = saved_modes;
        restarted = saved_restart;
        mode_generation = saved_generation;
        standard_seen_generation = saved_seen;
        before_mode_change = saved_hook;
    }
    raw = true;
    input_is_terminal = true;
    modes = .{ .backend = .{ .apply = applyPresentation } };
    restarted = true;
    mode_generation = 42;
    standard_seen_generation = 41;
    before_mode_change = noModeRecovery;
    const packet = nextStandardPacket() orelse return error.TestUnexpectedResult;
    try std.testing.expect(packet.reset);
    try std.testing.expect(restarted);
    const event = next() orelse return error.TestUnexpectedResult;
    try std.testing.expect(event == .restarted);
}

test "EXEC raw queued cancellation preserves all surrounding bytes without committing input" {
    queued_head = 254;
    queued_len = 0;
    defer {
        queued_head = 0;
        queued_len = 0;
    }
    for ("a\x1b[200~\x03\x1b[201~\x03z") |byte| queue(byte);
    const before = queued_len;
    const view = executionView();
    try std.testing.expect(view.candidate());
    try std.testing.expectEqual(before, queued_len);
    const origin = view.origins[view.length - 2].?;
    cancelExecution(origin);
    var actual: [32]u8 = undefined;
    var length: usize = 0;
    while (takePendingByte()) |byte| {
        actual[length] = byte;
        length += 1;
    }
    try std.testing.expectEqualStrings("a\x1b[200~\x03\x1b[201~z", actual[0..length]);
}

test "EXEC Windows retains raw records and clears surrogate across cancelled Ctrl+C" {
    if (comptime !is_windows) return error.SkipZigTest;
    const saved_after = windows.after;
    const saved_high = windows.high_surrogate;
    const saved_pending = windows.pending_len;
    const saved_queued = queued_len;
    defer {
        windows.after = saved_after;
        windows.high_surrogate = saved_high;
        windows.pending_len = saved_pending;
        windows.record_len = 0;
        windows.record_head = 0;
        queued_len = saved_queued;
    }
    windows.after = null;
    windows.high_surrogate = 0;
    windows.pending_len = 0;
    queued_len = 0;
    windows.record_head = 0;
    windows.record_len = 4;
    for ([_]u16{ 0xd83d, 3, 0xde00, 'z' }, 0..) |unit, index| {
        var record = std.mem.zeroes(windows.InputRecord);
        record.event_type = windows.key_event;
        std.mem.writeInt(i32, record.data[0..4], 1, .little);
        std.mem.writeInt(u16, record.data[10..12], unit, .little);
        windows.records[index] = .{ .record = record };
    }
    const view = executionView();
    try std.testing.expectEqual(@as(forth.Cell, 3), view.packets[view.length - 2].value);
    cancelExecution(view.origins[view.length - 2].?);
    const after = executionView();
    try std.testing.expectEqual(@as(usize, 1), after.length - @intFromBool(standard_seen_generation != mode_generation));
    try std.testing.expectEqual(@as(forth.Cell, 'z'), after.packets[after.length - 1].value);
    try std.testing.expectEqual(@as(usize, 4), windows.record_len);
}
