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
//! terminal would. Arrows, Home/End, Delete, Ctrl+A/E/K and in-memory command history
//! provide line editing; Tab is kept and shown as one space.
//!
//! On Windows the console edits the line itself and shows the widths right.

const std = @import("std");
const builtin = @import("builtin");
const forth = @import("forth.zig");
const TerminalSettings = @import("host_input.zig").TerminalSettings;

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

/// Track the column of Sigma's own output without reading terminal replies from stdin.
/// Untracked output or cursor controls invalidate the position until a fresh row.
pub const OutputCursor = struct {
    column: ?usize = 0,
    columns: usize = 80,
    escape: enum { none, start, csi } = .none,
    pending: [4]u8 = undefined,
    pending_len: usize = 0,
    pending_expected: usize = 0,

    pub fn position(self: *const OutputCursor) ?usize {
        return if (self.pending_len == 0 and self.escape == .none) self.column else null;
    }

    pub fn unknown(self: *OutputCursor) void {
        self.column = null;
        self.pending_len = 0;
        self.escape = .none;
    }

    pub fn newline(self: *OutputCursor) void {
        self.* = .{ .columns = self.columns };
    }

    pub fn resize(self: *OutputCursor, columns: usize) void {
        const width = if (columns < 2) 80 else columns;
        if (width != self.columns and self.column != 0) self.unknown();
        self.columns = width;
    }

    pub fn feed(self: *OutputCursor, bytes: []const u8) void {
        for (bytes) |byte| {
            if (self.pending_len != 0) {
                if (byte & 0xc0 == 0x80) {
                    self.pending[self.pending_len] = byte;
                    self.pending_len += 1;
                    if (self.pending_len == self.pending_expected) {
                        const decoded = forth.decodeXchar(self.pending[0..self.pending_len]);
                        self.pending_len = 0;
                        if (decoded.valid) {
                            const width = forth.charWidth(decoded.code);
                            if (width >= 0) self.advance(@intCast(width)) else self.unknown();
                        } else self.unknown();
                    }
                    continue;
                }
                self.unknown();
            }
            if (byte == '\r' or byte == '\n') {
                self.newline();
                continue;
            }
            if (byte == 0x1b) {
                self.escape = .start;
                continue;
            }
            switch (self.escape) {
                .start => {
                    if (byte == '[') self.escape = .csi else self.unknown();
                    continue;
                },
                .csi => {
                    if (byte >= 0x40 and byte <= 0x7e) {
                        self.escape = .none;
                        // SGR changes color, without moving the cursor.
                        if (byte != 'm') self.unknown();
                    }
                    continue;
                },
                .none => {},
            }
            if (byte == 7) continue; // Bell does not move the cursor.
            if (byte >= 0x20 and byte < 0x7f) {
                self.advance(1);
            } else if (byte >= 0xc2 and byte <= 0xf4) {
                self.pending[0] = byte;
                self.pending_len = 1;
                self.pending_expected = if (byte < 0xe0) 2 else if (byte < 0xf0) 3 else 4;
            } else self.unknown();
        }
    }

    fn advance(self: *OutputCursor, width: usize) void {
        const column = self.column orelse return;
        if (width > self.columns) {
            self.unknown();
            return;
        }
        // Keep the pending right-margin position distinct from column zero.
        self.column = if (column > self.columns - width) width else column + width;
    }
};

/// Recent interactive lines, kept only in this process. The input buffer limits each
/// entry to 4096 bytes; when full, the oldest of 128 entries is replaced.
pub const History = struct {
    pub const capacity = 128;
    pub const line_capacity = 4096;
    lines: [capacity][line_capacity]u8 = undefined,
    lengths: [capacity]usize = undefined,
    start: usize = 0,
    count: usize = 0,

    pub fn remember(self: *History, line: []const u8) void {
        if (line.len == 0 or line.len > line_capacity) return;
        if (self.count != 0 and std.mem.eql(u8, self.get(self.count - 1), line)) return;
        const at = (self.start + self.count) % capacity;
        @memcpy(self.lines[at][0..line.len], line);
        self.lengths[at] = line.len;
        if (self.count == capacity) self.start = (self.start + 1) % capacity else self.count += 1;
    }

    pub fn get(self: *const History, index: usize) []const u8 {
        std.debug.assert(index < self.count);
        const at = (self.start + index) % capacity;
        return self.lines[at][0..self.lengths[at]];
    }
};

/// The line, its byte cursor, and what to show for each key, apart from terminal I/O.
pub const Editor = struct {
    buffer: []u8,
    used: usize = 0,
    cursor: usize = 0,
    overflow: bool = false,
    keys: Keys = .{},
    history: ?*History = null,
    history_index: ?usize = null,
    draft: [History.line_capacity]u8 = undefined,
    draft_len: usize = 0,
    draft_cursor: usize = 0,
    draft_overflow: bool = false,
    /// Input columns available after the prompt. Reserve the right margin and scroll
    /// horizontally, so editing long lines never depends on terminal wrapping.
    /// Zero preserves ordinary echo for callers that do not supply a screen width.
    columns: usize = 0,
    view_start: usize = 0,
    shown_columns: usize = 0,
    shown_cursor: usize = 0,
    escape: enum { none, start, csi, ss3 } = .none,
    parameter: u16 = 0,
    modified: bool = false,
    pending: [4]u8 = undefined,
    pending_len: usize = 0,
    pending_expected: usize = 0,

    pub fn feed(self: *Editor, byte: u8, echo: *Echo) Action {
        // Redraw only complete UTF-8 characters when inserting before other text.
        // Otherwise an incomplete character followed by the suffix would be displayed
        // as replacement characters before its remaining bytes arrived.
        if (self.pending_len != 0) {
            if (byte & 0xc0 == 0x80) {
                self.pending[self.pending_len] = byte;
                self.pending_len += 1;
                if (self.pending_len == self.pending_expected) self.finish(echo);
                return .more;
            }
            self.finish(echo);
        }
        switch (self.escape) {
            .none => {},
            .start => {
                self.escape = switch (byte) {
                    '[' => .csi,
                    'O' => .ss3,
                    else => .none,
                };
                self.parameter = 0;
                self.modified = false;
                return .more;
            },
            .csi => {
                if (byte >= '0' and byte <= '9') {
                    self.parameter = self.parameter *| 10 +| (byte - '0');
                } else if (byte >= 0x40 and byte <= 0x7e) {
                    self.escape = .none;
                    if (!self.modified) self.navigation(byte, echo);
                } else self.modified = true;
                return .more;
            },
            .ss3 => {
                self.escape = .none;
                self.navigation(byte, echo);
                return .more;
            },
        }
        if (byte == '\r' or byte == '\n') {
            self.setCursor(self.used, echo);
            echo.add("\n");
            self.shown_columns = 0;
            self.shown_cursor = 0;
            if (self.used == 0) return .more;
            if (!self.overflow) if (self.history) |history| history.remember(self.buffer[0..self.used]);
            return .done;
        }
        if (byte == self.keys.erase or byte == 0x08 or byte == 0x7f) {
            self.eraseCharacter(echo);
            return .more;
        }
        if (byte == self.keys.kill) {
            if (self.columns != 0) self.remove(0, self.used, echo) else {
                self.setCursor(self.used, echo);
                while (self.used != 0) self.eraseCharacter(echo);
            }
            return .more;
        }
        if (byte == self.keys.word_erase) {
            while (self.cursor != 0 and isSpace(self.buffer[self.cursor - 1])) self.eraseCharacter(echo);
            while (self.cursor != 0 and !isSpace(self.buffer[self.cursor - 1])) self.eraseCharacter(echo);
            return .more;
        }
        if (byte == self.keys.end_of_file) {
            if (self.used == 0) return .end;
            self.deleteCharacter(echo);
            return .more;
        }
        if (byte == self.keys.interrupt or byte == self.keys.quit or byte == self.keys.stop) {
            if (byte < 0x20 or byte == 0x7f) echo.add(&.{ '^', byte ^ 0x40 });
            return .{ .signal = if (byte == self.keys.interrupt) .interrupt else if (byte == self.keys.quit) .quit else .stop };
        }
        if (byte == 0x1b) {
            self.escape = .start;
            return .more;
        }
        if (byte == 0x01) {
            self.setCursor(0, echo);
            return .more;
        }
        if (byte == 0x05) {
            self.setCursor(self.used, echo);
            return .more;
        }
        if (byte == 0x0b) {
            self.remove(self.cursor, self.used, echo);
            return .more;
        }
        if (byte < 0x20 and byte != '\t') return .more;
        if ((self.columns != 0 or self.cursor != self.used) and byte >= 0xc2 and byte <= 0xf4) {
            self.pending[0] = byte;
            self.pending_len = 1;
            self.pending_expected = if (byte < 0xe0) 2 else if (byte < 0xf0) 3 else 4;
            return .more;
        }
        self.insert(&.{byte}, echo);
        return .more;
    }

    /// Preserve even a partial character when the stream ends or a control key follows.
    pub fn finish(self: *Editor, echo: *Echo) void {
        const len = self.pending_len;
        self.pending_len = 0;
        if (len != 0) self.insert(self.pending[0..len], echo);
    }

    fn navigation(self: *Editor, final: u8, echo: *Echo) void {
        switch (final) {
            'A' => self.browse(true, echo),
            'B' => self.browse(false, echo),
            'C' => self.setCursor(characterEnd(self.buffer[0..self.used], self.cursor), echo),
            'D' => if (self.cursor != 0) {
                self.setCursor(characterStart(self.buffer[0..self.cursor]), echo);
            },
            'H' => self.setCursor(0, echo),
            'F' => self.setCursor(self.used, echo),
            '~' => switch (self.parameter) {
                1, 7 => self.setCursor(0, echo),
                4, 8 => self.setCursor(self.used, echo),
                3 => self.deleteCharacter(echo),
                else => {},
            },
            else => {},
        }
    }

    fn insert(self: *Editor, text: []const u8, echo: *Echo) void {
        if (text.len > self.buffer.len - self.used) {
            self.overflow = true;
            return;
        }
        const at_end = self.cursor == self.used;
        std.mem.copyBackwards(u8, self.buffer[self.cursor + text.len .. self.used + text.len], self.buffer[self.cursor..self.used]);
        @memcpy(self.buffer[self.cursor .. self.cursor + text.len], text);
        self.used += text.len;
        self.cursor += text.len;
        if (at_end and self.columns == 0) {
            showText(echo, text);
            self.shown_columns = textWidth(self.buffer[0..self.used]);
            self.shown_cursor = self.shown_columns;
        } else {
            self.refresh(echo);
        }
    }

    fn remove(self: *Editor, start: usize, end: usize, echo: *Echo) void {
        if (start == end) return;
        std.mem.copyForwards(u8, self.buffer[start .. self.used - (end - start)], self.buffer[end..self.used]);
        self.used -= end - start;
        self.cursor = start;
        self.view_start = @min(self.view_start, start);
        self.refresh(echo);
    }

    fn deleteCharacter(self: *Editor, echo: *Echo) void {
        self.remove(self.cursor, characterEnd(self.buffer[0..self.used], self.cursor), echo);
    }

    fn setCursor(self: *Editor, cursor: usize, echo: *Echo) void {
        if (cursor == self.cursor) return;
        self.cursor = cursor;
        self.refresh(echo);
    }

    fn browse(self: *Editor, older: bool, echo: *Echo) void {
        const history = self.history orelse return;
        if (history.count == 0) return;
        var index: ?usize = self.history_index;
        if (older) {
            if (index) |at| {
                if (at == 0) return;
                index = at - 1;
            } else {
                if (self.used > self.draft.len) return;
                @memcpy(self.draft[0..self.used], self.buffer[0..self.used]);
                self.draft_len = self.used;
                self.draft_cursor = self.cursor;
                self.draft_overflow = self.overflow;
                index = history.count - 1;
            }
        } else if (index) |at| {
            index = if (at + 1 < history.count) at + 1 else null;
        } else return;
        const text = if (index) |at| history.get(at) else self.draft[0..self.draft_len];
        if (text.len > self.buffer.len) return;
        @memcpy(self.buffer[0..text.len], text);
        self.used = text.len;
        self.cursor = if (index != null) text.len else self.draft_cursor;
        self.overflow = if (index != null) false else self.draft_overflow;
        self.history_index = index;
        self.view_start = 0;
        self.refresh(echo);
    }

    /// Write only a window of a long line and keep the physical cursor inside it.
    fn refresh(self: *Editor, echo: *Echo) void {
        var count = self.shown_cursor;
        while (count != 0) : (count -= 1) echo.add("\x08");
        if (self.view_start > self.cursor) self.view_start = self.cursor;
        const limit: usize = if (self.columns > 1) self.columns - 1 else if (self.columns == 1) 0 else std.math.maxInt(usize);
        var cursor_width = textWidth(self.buffer[self.view_start..self.cursor]);
        while (self.view_start < self.cursor and cursor_width > limit) {
            const next = characterEnd(self.buffer[0..self.used], self.view_start);
            cursor_width -= characterWidth(self.buffer[self.view_start..next]);
            self.view_start = next;
        }
        var end = self.view_start;
        var width: usize = 0;
        while (end < self.used) {
            const next = characterEnd(self.buffer[0..self.used], end);
            const columns = characterWidth(self.buffer[end..next]);
            if (columns > limit - width) break;
            width += columns;
            end = next;
        }
        showText(echo, self.buffer[self.view_start..end]);
        const padded = @max(width, self.shown_columns);
        count = padded - width;
        while (count != 0) : (count -= 1) echo.add(" ");
        self.shown_cursor = textWidth(self.buffer[self.view_start..self.cursor]);
        count = padded - self.shown_cursor;
        while (count != 0) : (count -= 1) echo.add("\x08");
        self.shown_columns = width;
    }

    pub fn redraw(self: *Editor, echo: *Echo) void {
        self.shown_columns = 0;
        self.shown_cursor = 0;
        self.refresh(echo);
    }

    fn eraseCharacter(self: *Editor, echo: *Echo) void {
        if (self.cursor == 0) return;
        const start = characterStart(self.buffer[0..self.cursor]);
        if (self.cursor != self.used or self.columns != 0) {
            self.remove(start, self.cursor, echo);
            return;
        }
        // Keep the traditional echo for ACCEPT at the end of a line, including
        // repainting the base character after deleting a combining mark.
        const columns = characterWidth(self.buffer[start..self.used]);
        self.used = start;
        self.cursor = start;
        self.shown_columns = textWidth(self.buffer[0..self.used]);
        self.shown_cursor = self.shown_columns;
        if (columns != 0) {
            backOver(echo, columns);
            return;
        }
        if (start == 0) return;
        const before = characterStart(self.buffer[0..start]);
        const before_columns = characterWidth(self.buffer[before..start]);
        if (before_columns == 0) return;
        backOver(echo, before_columns);
        echo.add(self.buffer[before..start]);
    }
};

fn characterEnd(bytes: []const u8, at: usize) usize {
    if (at == bytes.len) return at;
    const decoded = forth.decodeXchar(bytes[at..]);
    return at + if (decoded.valid) decoded.length else @as(usize, 1);
}

fn textWidth(bytes: []const u8) usize {
    var at: usize = 0;
    var columns: usize = 0;
    while (at < bytes.len) {
        const end = characterEnd(bytes, at);
        columns += characterWidth(bytes[at..end]);
        at = end;
    }
    return columns;
}

fn showText(echo: *Echo, text: []const u8) void {
    for (text) |byte| echo.add(if (byte == '\t') " " else &.{byte});
}

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
    var saved: TerminalSettings = undefined;

    fn enter(keys: *Keys) bool {
        if (!saved.get()) return false;
        var changed = saved;
        const settings = &changed.termios;
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
        return changed.set();
    }

    /// A key of the line input, or the usual one when it is turned off.
    fn character(cc: anytype, comptime which: std.c.V, usual: u8) u8 {
        const value = cc[@intFromEnum(which)];
        return if (value == 0 or value == 0xff) usual else value;
    }

    fn leave() void {
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
pub fn read(buffer: []u8, readByte: *const fn () ?u8, flushOutput: *const fn () void, history: ?*History, columns: usize) ?Result {
    if (builtin.os.tag == .windows) return null;
    var editor = Editor{ .buffer = buffer, .history = history, .columns = columns };
    if (!posix.enter(&editor.keys)) return null;
    defer posix.leave();
    // A prompt or a question is out before the line is typed.
    flushOutput();
    while (true) {
        const byte = readByte() orelse {
            var tail = Echo{ .sink = posix.writeAll };
            editor.finish(&tail);
            posix.writeAll(tail.slice());
            if (history) |saved| if (!editor.overflow) {
                saved.remember(buffer[0..editor.used]);
            };
            return .{ .line = if (editor.used == 0) null else buffer[0..editor.used], .overflow = editor.overflow };
        };
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
                var again = Echo{ .sink = posix.writeAll };
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

test "unsupported sequences and control characters are dropped; Tab is shown as a space" {
    var buffer: [64]u8 = undefined;
    var editor = Editor{ .buffer = &buffer };
    var shown: std.ArrayList(u8) = .empty;
    defer shown.deinit(std.testing.allocator);
    _ = try typeInto(&editor, "a\x1b[99~\x1b[1;5C\x1bOPb\x02\tc", &shown);
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

test "arrows insert in the middle, Delete removes forward, Home and End move the cursor" {
    var buffer: [64]u8 = undefined;
    var editor = Editor{ .buffer = &buffer };
    var shown: std.ArrayList(u8) = .empty;
    defer shown.deinit(std.testing.allocator);
    _ = try typeInto(&editor, "abc\x1b[D\x1b[DX\x1b[3~", &shown);
    try std.testing.expectEqualStrings("aXc", buffer[0..editor.used]);
    try std.testing.expectEqual(@as(usize, 2), editor.cursor);
    _ = try typeInto(&editor, "\x1b[H0\x1b[F9", &shown);
    try std.testing.expectEqualStrings("0aXc9", buffer[0..editor.used]);
    _ = try typeInto(&editor, "\x1bOH\x1bOC\x1bOF\x7f", &shown);
    try std.testing.expectEqualStrings("0aXc", buffer[0..editor.used]);
    _ = try typeInto(&editor, "\x01\x1b[D\x7f\x1b[C\x04", &shown);
    try std.testing.expectEqualStrings("0Xc", buffer[0..editor.used]);
    _ = try typeInto(&editor, "\x05\x1b[C\x1b[3~", &shown);
    try std.testing.expectEqual(editor.used, editor.cursor);
    try std.testing.expectEqualStrings("0Xc", buffer[0..editor.used]);
}

test "insertion and movement preserve UTF-8 in the middle of Japanese and emoji" {
    var buffer: [64]u8 = undefined;
    var editor = Editor{ .buffer = &buffer, .columns = 80 };
    var shown: std.ArrayList(u8) = .empty;
    defer shown.deinit(std.testing.allocator);
    _ = try typeInto(&editor, "ab\x1b[D日😀\x1b[D\x1b[3~", &shown);
    try std.testing.expectEqualStrings("a日b", buffer[0..editor.used]);
    try std.testing.expectEqual(@as(usize, 4), editor.cursor);
    _ = try typeInto(&editor, "\x7f", &shown);
    try std.testing.expectEqualStrings("ab", buffer[0..editor.used]);
    try std.testing.expectEqual(@as(usize, 1), editor.cursor);
    try std.testing.expect(std.unicode.utf8ValidateSlice(shown.items));
}

test "Ctrl+W erases before the cursor and Ctrl+K erases after it" {
    var buffer: [64]u8 = undefined;
    var editor = Editor{ .buffer = &buffer, .columns = 80 };
    var shown: std.ArrayList(u8) = .empty;
    defer shown.deinit(std.testing.allocator);
    _ = try typeInto(&editor, "one two tail\x1b[D\x1b[D\x1b[D\x1b[D\x17", &shown);
    try std.testing.expectEqualStrings("one tail", buffer[0..editor.used]);
    _ = try typeInto(&editor, "\x0b", &shown);
    try std.testing.expectEqualStrings("one ", buffer[0..editor.used]);
    _ = try typeInto(&editor, "\x15", &shown);
    try std.testing.expectEqual(@as(usize, 0), editor.used);
}

test "history navigation restores the unfinished line and its cursor without changing history" {
    var history = History{};
    history.remember("first");
    history.remember("second");
    var buffer: [64]u8 = undefined;
    var editor = Editor{ .buffer = &buffer, .history = &history, .columns = 80 };
    var shown: std.ArrayList(u8) = .empty;
    defer shown.deinit(std.testing.allocator);
    _ = try typeInto(&editor, "draft\x1b[D\x1b[A", &shown);
    try std.testing.expectEqualStrings("second", buffer[0..editor.used]);
    _ = try typeInto(&editor, "!\x1b[A\x1b[A", &shown);
    try std.testing.expectEqualStrings("first", buffer[0..editor.used]);
    _ = try typeInto(&editor, "\x1b[B\x1b[B\x1b[B", &shown);
    try std.testing.expectEqualStrings("draft", buffer[0..editor.used]);
    try std.testing.expectEqual(@as(usize, 4), editor.cursor);
    try std.testing.expectEqualStrings("second", history.get(1));
    _ = try typeInto(&editor, "X\n", &shown);
    try std.testing.expectEqualStrings("drafXt", history.get(2));
}

test "history is bounded, skips empty lines and adjacent duplicates, and starts empty" {
    var history = History{};
    history.remember("");
    try std.testing.expectEqual(@as(usize, 0), history.count);
    for (0..History.capacity + 2) |index| {
        var line: [32]u8 = undefined;
        const text = try std.fmt.bufPrint(&line, "line-{d}", .{index});
        history.remember(text);
        history.remember(text);
    }
    try std.testing.expectEqual(@as(usize, History.capacity), history.count);
    try std.testing.expectEqualStrings("line-2", history.get(0));
    try std.testing.expectEqualStrings("line-129", history.get(history.count - 1));
    const another_session = History{};
    try std.testing.expectEqual(@as(usize, 0), another_session.count);
}

test "history does not remember overflowing lines or truncate a recalled line" {
    var history = History{};
    var buffer: [3]u8 = undefined;
    var editor = Editor{ .buffer = &buffer, .history = &history };
    var shown: std.ArrayList(u8) = .empty;
    defer shown.deinit(std.testing.allocator);
    _ = try typeInto(&editor, "abcde\n", &shown);
    try std.testing.expectEqual(@as(usize, 0), history.count);
    history.remember("too long");
    _ = try typeInto(&editor, "\x1b[A", &shown);
    try std.testing.expectEqualStrings("abc", buffer[0..editor.used]);
}

test "long lines scroll horizontally within the available terminal width" {
    var buffer: [64]u8 = undefined;
    var editor = Editor{ .buffer = &buffer, .columns = 6 };
    var shown: std.ArrayList(u8) = .empty;
    defer shown.deinit(std.testing.allocator);
    _ = try typeInto(&editor, "ab日本cd", &shown);
    try std.testing.expect(editor.shown_columns < editor.columns);
    try std.testing.expect(editor.shown_cursor < editor.columns);
    try std.testing.expect(editor.view_start != 0);
    _ = try typeInto(&editor, "\x01X\x05\x7f", &shown);
    try std.testing.expectEqualStrings("Xab日本c", buffer[0..editor.used]);
    try std.testing.expect(editor.shown_columns < editor.columns);
    try std.testing.expect(editor.shown_cursor < editor.columns);
    try std.testing.expect(std.unicode.utf8ValidateSlice(shown.items));
}

test "incomplete UTF-8 input is retained at EOF and complete inserted characters fit atomically" {
    var buffer: [4]u8 = undefined;
    var editor = Editor{ .buffer = &buffer, .columns = 80 };
    var shown: std.ArrayList(u8) = .empty;
    defer shown.deinit(std.testing.allocator);
    _ = try typeInto(&editor, "a\xe6\x97", &shown);
    var tail = Echo{};
    editor.finish(&tail);
    try std.testing.expectEqualStrings("a\xe6\x97", buffer[0..editor.used]);
    var full = Editor{ .buffer = &buffer, .columns = 80 };
    _ = try typeInto(&full, "ab日", &shown);
    try std.testing.expectEqualStrings("ab", buffer[0..full.used]);
    try std.testing.expect(full.overflow);
}

test "output cursor tracks prompts, split UTF-8, colors and pending right margins" {
    var cursor = OutputCursor{};
    cursor.resize(12);
    cursor.feed("ASK ");
    try std.testing.expectEqual(@as(?usize, 4), cursor.position());
    cursor.feed("\x1b[");
    try std.testing.expectEqual(@as(?usize, null), cursor.position());
    cursor.feed("31m日\x1b[0m");
    try std.testing.expectEqual(@as(?usize, 6), cursor.position());
    cursor.feed("\xf0\x9f");
    try std.testing.expectEqual(@as(?usize, null), cursor.position());
    cursor.feed("\x98\x80");
    try std.testing.expectEqual(@as(?usize, 8), cursor.position());
    cursor.feed("1234");
    try std.testing.expectEqual(@as(?usize, 12), cursor.position());
    cursor.feed("X");
    try std.testing.expectEqual(@as(?usize, 1), cursor.position());
    cursor.feed("\r\n");
    try std.testing.expectEqual(@as(?usize, 0), cursor.position());
}

test "unknown output controls and resizing invalidate origin until a new row" {
    var cursor = OutputCursor{};
    cursor.feed("prompt\t");
    try std.testing.expectEqual(@as(?usize, null), cursor.position());
    cursor.feed("more\r\n");
    try std.testing.expectEqual(@as(?usize, 0), cursor.position());
    cursor.feed("\x1b[2;3Htext");
    try std.testing.expectEqual(@as(?usize, null), cursor.position());
    cursor.newline();
    cursor.feed("prompt");
    cursor.resize(40);
    try std.testing.expectEqual(@as(?usize, null), cursor.position());
    cursor.newline();
    cursor.resize(20);
    try std.testing.expectEqual(@as(?usize, 0), cursor.position());
    cursor.feed("\xff");
    try std.testing.expectEqual(@as(?usize, null), cursor.position());
}
