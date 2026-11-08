//! Sigma's own editing of a line typed on a terminal, for ACCEPT and the interactive
//! session on Linux and macOS.
//!
//! The terminal's line input knows nothing of the width of a character: Backspace over
//! a full-width character takes away the character but moves the cursor back by one
//! column only, leaving half of it on the screen. While Sigma reads a line, the terminal
//! is therefore put in single-byte mode without echo, and Sigma echoes and erases by
//! itself, by the widths that X-WIDTH uses (as gforth, zsh, and bash do).
//!
//! The keys are those of the terminal's line input, taken from its settings: Erase
//! (Backspace, and also Ctrl+H), Kill (Ctrl+U), Word erase (Ctrl+W), End of file
//! (Ctrl+D on an empty line), and Interrupt, Quit, and Suspend (Ctrl+C, Ctrl+\, Ctrl+Z),
//! which give the terminal back its settings and then raise their signal, as the
//! terminal would. An escape sequence (a cursor key, for example) is dropped, as are the
//! other control characters; Tab is kept and shown as one space.
//!
//! On Windows the console edits the line itself and shows the widths right.

const std = @import("std");
const builtin = @import("builtin");
const forth = @import("forth.zig");

/// The keys of the terminal's line input, from its settings.
pub const Keys = struct {
    erase: u8 = 0x7f,
    kill: u8 = 0x15,
    word_erase: u8 = 0x17,
    end_of_file: u8 = 0x04,
    interrupt: u8 = 0x03,
    quit: u8 = 0x1c,
    stop: u8 = 0x1a,
};

pub const Signal = enum { interrupt, quit, stop };

/// What a byte does to the line.
pub const Action = union(enum) {
    /// Keep reading.
    more,
    /// The line is complete (Enter).
    done,
    /// End of file on an empty line.
    end,
    /// Raise this signal with the terminal's settings given back.
    signal: Signal,
};

/// The line being typed, and what to write to the terminal for each byte. Kept apart from
/// the terminal so that it can be tested.
pub const Editor = struct {
    buffer: []u8,
    used: usize = 0,
    /// Whether bytes were lost because the line did not fit.
    overflow: bool = false,
    keys: Keys = .{},
    escape: enum { none, start, csi, ss3 } = .none,

    /// Takes one byte and adds what the terminal should show to `echo`.
    pub fn feed(self: *Editor, byte: u8, echo: *Echo) Action {
        switch (self.escape) {
            .none => {},
            .start => {
                self.escape = switch (byte) {
                    '[' => .csi,
                    'O' => .ss3,
                    else => .none,
                };
                return .more;
            },
            .csi => {
                // Parameters and intermediates until a final byte.
                if (byte >= 0x40 and byte <= 0x7e) self.escape = .none;
                return .more;
            },
            .ss3 => {
                self.escape = .none;
                return .more;
            },
        }
        if (byte == '\r' or byte == '\n') {
            echo.add("\n");
            // As before, an empty line is not a line: reading goes on.
            return if (self.used == 0) .more else .done;
        }
        if (byte == self.keys.erase or byte == 0x08 or byte == 0x7f) {
            self.eraseCharacter(echo);
            return .more;
        }
        if (byte == self.keys.kill) {
            while (self.used != 0) self.eraseCharacter(echo);
            return .more;
        }
        if (byte == self.keys.word_erase) {
            while (self.used != 0 and isSpace(self.buffer[self.used - 1])) self.eraseCharacter(echo);
            while (self.used != 0 and !isSpace(self.buffer[self.used - 1])) self.eraseCharacter(echo);
            return .more;
        }
        if (byte == self.keys.end_of_file) return if (self.used == 0) .end else .more;
        // Shown as the terminal shows them, ^C for example.
        if (byte == self.keys.interrupt or byte == self.keys.quit or byte == self.keys.stop) {
            if (byte < 0x20 or byte == 0x7f) echo.add(&.{ '^', byte ^ 0x40 });
            return .{ .signal = if (byte == self.keys.interrupt) .interrupt else if (byte == self.keys.quit) .quit else .stop };
        }
        if (byte == 0x1b) {
            self.escape = .start;
            return .more;
        }
        if (byte < 0x20 and byte != '\t') return .more;
        // A line longer than the buffer loses the rest, as before.
        if (self.used == self.buffer.len) {
            self.overflow = true;
            return .more;
        }
        self.buffer[self.used] = byte;
        self.used += 1;
        echo.add(if (byte == '\t') " " else &.{byte});
        return .more;
    }

    /// Shows the line again after the program was suspended.
    pub fn redraw(self: *const Editor, echo: *Echo) void {
        for (self.buffer[0..self.used]) |byte| echo.add(if (byte == '\t') " " else &.{byte});
    }

    fn eraseCharacter(self: *Editor, echo: *Echo) void {
        if (self.used == 0) return;
        const start = characterStart(self.buffer[0..self.used]);
        const columns = characterWidth(self.buffer[start..self.used]);
        self.used = start;
        if (columns != 0) {
            backOver(echo, columns);
            return;
        }
        // A character of no width (a combining mark) is shown with the one before it:
        // that one is written again without it.
        if (start == 0) return;
        const before = characterStart(self.buffer[0..start]);
        const before_columns = characterWidth(self.buffer[before..start]);
        if (before_columns == 0) return;
        backOver(echo, before_columns);
        echo.add(self.buffer[before..start]);
    }
};

/// The bytes to write to the terminal for one key. When they do not fit (Ctrl+U on a
/// long line), what is kept goes to `sink` first.
pub const Echo = struct {
    bytes: [256]u8 = undefined,
    len: usize = 0,
    sink: ?*const fn ([]const u8) void = null,

    fn add(self: *Echo, text: []const u8) void {
        var rest = text;
        while (rest.len != 0) {
            if (self.len == self.bytes.len) {
                const sink = self.sink orelse return;
                sink(self.bytes[0..self.len]);
                self.len = 0;
            }
            const room = @min(rest.len, self.bytes.len - self.len);
            @memcpy(self.bytes[self.len .. self.len + room], rest[0..room]);
            self.len += room;
            rest = rest[room..];
        }
    }

    pub fn slice(self: *const Echo) []const u8 {
        return self.bytes[0..self.len];
    }
};

/// Moves back over `columns` columns and blanks them: Backspace, space, Backspace, which
/// every terminal understands.
fn backOver(echo: *Echo, columns: usize) void {
    var i: usize = 0;
    while (i < columns) : (i += 1) echo.add("\x08");
    i = 0;
    while (i < columns) : (i += 1) echo.add(" ");
    i = 0;
    while (i < columns) : (i += 1) echo.add("\x08");
}

fn isSpace(byte: u8) bool {
    return byte == ' ' or byte == '\t';
}

/// Where the last character of `bytes` (not empty) starts: a whole UTF-8 character, or
/// else the last byte alone.
fn characterStart(bytes: []const u8) usize {
    var start = bytes.len - 1;
    while (start > 0 and bytes.len - start < 4 and bytes[start] & 0xC0 == 0x80) start -= 1;
    const decoded = forth.decodeXchar(bytes[start..]);
    return if (decoded.valid and decoded.length == bytes.len - start) start else bytes.len - 1;
}

/// The columns a character takes on the terminal. Tab is shown as one space; a byte that
/// is not a character, or a character with no width of its own (not assigned), as one
/// column, as terminals show them.
fn characterWidth(character: []const u8) usize {
    if (character.len == 1 and character[0] == '\t') return 1;
    const decoded = forth.decodeXchar(character);
    if (!decoded.valid) return 1;
    const columns = forth.charWidth(decoded.code);
    return if (columns < 0) 1 else @intCast(columns);
}

// ---- The terminal ----

const posix = struct {
    var saved: std.c.termios = undefined;

    fn enter(keys: *Keys) bool {
        if (std.c.tcgetattr(0, &saved) != 0) return false;
        var settings = saved;
        const cc = &settings.cc;
        keys.* = .{
            .erase = character(cc, .ERASE, 0x7f),
            .kill = character(cc, .KILL, 0x15),
            .word_erase = character(cc, .WERASE, 0x17),
            .end_of_file = character(cc, .EOF, 0x04),
            .interrupt = character(cc, .INTR, 0x03),
            .quit = character(cc, .QUIT, 0x1c),
            .stop = character(cc, .SUSP, 0x1a),
        };
        settings.lflag.ICANON = false;
        settings.lflag.ECHO = false;
        settings.lflag.ISIG = false;
        settings.lflag.IEXTEN = false;
        settings.cc[@intFromEnum(std.c.V.MIN)] = 1;
        settings.cc[@intFromEnum(std.c.V.TIME)] = 0;
        return std.c.tcsetattr(0, .NOW, &settings) == 0;
    }

    /// A key of the line input, or the usual one when it is turned off.
    fn character(cc: anytype, comptime which: std.c.V, usual: u8) u8 {
        const value = cc[@intFromEnum(which)];
        return if (value == 0 or value == 0xff) usual else value;
    }

    fn leave() void {
        _ = std.c.tcsetattr(0, .NOW, &saved);
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

    extern "c" fn raise(c_int) c_int;

    fn raiseSignal(which: Signal) void {
        _ = raise(switch (which) {
            .interrupt => number(std.c.SIG.INT),
            .quit => number(std.c.SIG.QUIT),
            .stop => number(std.c.SIG.TSTP),
        });
    }

    /// A signal's number, from an enum or a plain number, as the C library gives it.
    fn number(value: anytype) c_int {
        return if (@typeInfo(@TypeOf(value)) == .@"enum") @intCast(@intFromEnum(value)) else @intCast(value);
    }
};

/// Reads a line into `buffer` with Sigma's editing, taking bytes from `readByte` (null at
/// the end of the input). Returns null at the end of the input before any byte of a line,
/// or when the terminal cannot be set, in which case nothing has been read.
pub fn read(buffer: []u8, readByte: *const fn () ?u8, flushOutput: *const fn () void) ?Result {
    if (builtin.os.tag == .windows) return null;
    var editor = Editor{ .buffer = buffer };
    if (!posix.enter(&editor.keys)) return null;
    defer posix.leave();
    // A prompt or a question is out before the line is typed.
    flushOutput();
    while (true) {
        const byte = readByte() orelse return .{ .line = if (editor.used == 0) null else buffer[0..editor.used], .overflow = editor.overflow };
        var echo = Echo{ .sink = posix.writeAll };
        const action = editor.feed(byte, &echo);
        posix.writeAll(echo.slice());
        switch (action) {
            .more => {},
            .done => return .{ .line = buffer[0..editor.used], .overflow = editor.overflow },
            .end => return .{ .line = null },
            .signal => |which| {
                // As the terminal would: its settings back, then the signal. When the
                // program goes on (after Ctrl+Z, or if the signal is caught), the line is
                // shown again on a new line and editing goes on.
                posix.leave();
                posix.raiseSignal(which);
                if (!posix.enter(&editor.keys)) return .{ .line = buffer[0..editor.used] };
                var again = Echo{};
                again.add("\n");
                editor.redraw(&again);
                posix.writeAll(again.slice());
            },
        }
    }
}

/// The line typed, or null at the end of the input, and whether it was longer than the
/// buffer (the rest is lost).
pub const Result = struct { line: ?[]const u8, overflow: bool = false };

// ---- Tests ----

/// `text` written `count` times, for the tests.
fn repeat(comptime text: []const u8, comptime count: usize) []const u8 {
    comptime var result: []const u8 = "";
    inline for (0..count) |_| result = result ++ text;
    return result;
}

fn typeInto(editor: *Editor, keys: []const u8, shown: *std.ArrayList(u8)) !Action {
    var last: Action = .more;
    for (keys) |byte| {
        var echo = Echo{};
        last = editor.feed(byte, &echo);
        try shown.appendSlice(std.testing.allocator, echo.slice());
    }
    return last;
}

test "Backspace takes away a whole character and as many columns as it is wide" {
    var buffer: [64]u8 = undefined;
    var editor = Editor{ .buffer = &buffer };
    var shown: std.ArrayList(u8) = .empty;
    defer shown.deinit(std.testing.allocator);
    _ = try typeInto(&editor, "a日😀\x7f", &shown);
    try std.testing.expectEqualStrings("a日", buffer[0..editor.used]);
    try std.testing.expectEqualStrings("a日😀\x08\x08  \x08\x08", shown.items);
    shown.clearRetainingCapacity();
    _ = try typeInto(&editor, "\x7f\x08", &shown);
    try std.testing.expectEqual(@as(usize, 0), editor.used);
    try std.testing.expectEqualStrings("\x08\x08  \x08\x08\x08 \x08", shown.items);
    shown.clearRetainingCapacity();
    // Nothing to take away: nothing is shown.
    _ = try typeInto(&editor, "\x7f", &shown);
    try std.testing.expectEqualStrings("", shown.items);
}

test "Backspace over half-width kana, accents, and bytes that are not UTF-8" {
    var buffer: [64]u8 = undefined;
    var editor = Editor{ .buffer = &buffer };
    var shown: std.ArrayList(u8) = .empty;
    defer shown.deinit(std.testing.allocator);
    _ = try typeInto(&editor, "ｶé\xff\xe6\x97", &shown);
    shown.clearRetainingCapacity();
    // The cut-short character is taken away a byte at a time, one column each.
    _ = try typeInto(&editor, "\x7f\x7f\x7f", &shown);
    try std.testing.expectEqualStrings("ｶé", buffer[0..editor.used]);
    try std.testing.expectEqualStrings(repeat("\x08 \x08", 3), shown.items);
    shown.clearRetainingCapacity();
    _ = try typeInto(&editor, "\x7f\x7f", &shown);
    try std.testing.expectEqual(@as(usize, 0), editor.used);
    try std.testing.expectEqualStrings(repeat("\x08 \x08", 2), shown.items);
}

test "Backspace over a combining mark writes the character before it again" {
    var buffer: [64]u8 = undefined;
    var editor = Editor{ .buffer = &buffer };
    var shown: std.ArrayList(u8) = .empty;
    defer shown.deinit(std.testing.allocator);
    _ = try typeInto(&editor, "e\u{301}", &shown);
    shown.clearRetainingCapacity();
    _ = try typeInto(&editor, "\x7f", &shown);
    try std.testing.expectEqualStrings("e", buffer[0..editor.used]);
    try std.testing.expectEqualStrings("\x08 \x08e", shown.items);
}

test "Enter ends a line that is not empty; Ctrl+U, Ctrl+W, and Ctrl+D as in the terminal" {
    var buffer: [64]u8 = undefined;
    var editor = Editor{ .buffer = &buffer };
    var shown: std.ArrayList(u8) = .empty;
    defer shown.deinit(std.testing.allocator);
    try std.testing.expectEqual(Action.more, try typeInto(&editor, "\r", &shown));
    try std.testing.expectEqual(Action.end, try typeInto(&editor, "\x04", &shown));
    _ = try typeInto(&editor, "1 日本 \x17", &shown);
    try std.testing.expectEqualStrings("1 ", buffer[0..editor.used]);
    _ = try typeInto(&editor, "語\x15", &shown);
    try std.testing.expectEqual(@as(usize, 0), editor.used);
    try std.testing.expectEqual(Action.more, try typeInto(&editor, "a\x04", &shown));
    try std.testing.expectEqual(Action.done, try typeInto(&editor, "\n", &shown));
    try std.testing.expectEqualStrings("a", buffer[0..editor.used]);
    var stopped = Editor{ .buffer = &buffer };
    shown.clearRetainingCapacity();
    try std.testing.expectEqual(Action{ .signal = .interrupt }, try typeInto(&stopped, "\x03", &shown));
    try std.testing.expectEqualStrings("^C", shown.items);
    try std.testing.expectEqual(Action{ .signal = .stop }, try typeInto(&stopped, "\x1a", &shown));
}

test "cursor keys and other control characters are dropped; Tab is kept and shown as a space" {
    var buffer: [64]u8 = undefined;
    var editor = Editor{ .buffer = &buffer };
    var shown: std.ArrayList(u8) = .empty;
    defer shown.deinit(std.testing.allocator);
    _ = try typeInto(&editor, "a\x1b[D\x1b[1;5C\x1bOAb\x01\tc", &shown);
    try std.testing.expectEqualStrings("ab\tc", buffer[0..editor.used]);
    try std.testing.expectEqualStrings("ab c", shown.items);
    shown.clearRetainingCapacity();
    _ = try typeInto(&editor, "\x7f\x7f", &shown);
    try std.testing.expectEqualStrings(repeat("\x08 \x08", 2), shown.items);
}

var sunk: std.ArrayList(u8) = .empty;

fn sinkForTest(bytes: []const u8) void {
    sunk.appendSlice(std.testing.allocator, bytes) catch unreachable;
}

test "Ctrl+U on a line longer than the echo buffer blanks every column" {
    var buffer: [512]u8 = undefined;
    var editor = Editor{ .buffer = &buffer };
    var shown: std.ArrayList(u8) = .empty;
    defer shown.deinit(std.testing.allocator);
    _ = try typeInto(&editor, repeat("日", 100), &shown);
    defer sunk.deinit(std.testing.allocator);
    var echo = Echo{ .sink = sinkForTest };
    _ = editor.feed(0x15, &echo);
    try sunk.appendSlice(std.testing.allocator, echo.slice());
    try std.testing.expectEqualStrings(repeat("\x08\x08  \x08\x08", 100), sunk.items);
}

test "a line longer than the buffer loses the rest" {
    var buffer: [3]u8 = undefined;
    var editor = Editor{ .buffer = &buffer };
    var shown: std.ArrayList(u8) = .empty;
    defer shown.deinit(std.testing.allocator);
    _ = try typeInto(&editor, "abcde", &shown);
    try std.testing.expectEqualStrings("abc", buffer[0..editor.used]);
    try std.testing.expectEqualStrings("abc", shown.items);
    try std.testing.expect(editor.overflow);
}
