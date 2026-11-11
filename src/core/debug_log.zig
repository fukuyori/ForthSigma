//! The log of --debug-log: what the debugging features show, as lines of JSON (JSON
//! Lines) in a file of the host's, for programs to read. With it, the trace and the
//! profile go to the log instead of standard error, and each error that reaches the
//! host is logged besides being shown. A build with -Ddebug=false has none of this.
//!
//!     {"event":"start","version":"0.9.0"}
//!     {"event":"enter","word":"SUMSQ","depth":0,"stack_depth":2,"stack":[3,4]}
//!     {"event":"exit","word":"SUMSQ","depth":0,"stack_depth":1,"stack":[25]}
//!     {"event":"trace_limit","lines":200}
//!     {"event":"error","message":"DIVISION BY ZERO !","code":-10,"file":"top.fs","line":3,
//!      "backtrace":[{"word":"AVERAGE","file":"bt.fs","line":3}],"more":0,
//!      "stack_depth":2,"stack":[10,20],"float_stack_depth":0,"float_stack":[]}
//!     {"event":"profile","operations":177}
//!     {"event":"profile_word","word":"SQUARE","file":"tr.fs","line":1,"calls":21,"self":63,"total":63}
//!
//! Each event is one line. `stack` holds the top items, the top last: nine in the trace,
//! 64 in an error; `stack_depth` is the depth of the whole stack.

const std = @import("std");
const defs = @import("defs.zig");
const forth = @import("../forth.zig");
const memory_map = @import("memory_map.zig");
const error_reporting = @import("error_reporting.zig");
const inline_calls = @import("inline_calls.zig");
const profiler = @import("profiler.zig");
const Cell = memory_map.Cell;
const State = forth.State;

const trace_items = 9;
const error_items = 64;

/// Whether the host gave a log to write to.
pub fn enabled(self: *const State) bool {
    return defs.debug_enabled and self.writer.log_fn != null;
}

/// One event, written to the log piece by piece.
const Event = struct {
    machine: *State,
    buffer: [512]u8 = undefined,
    len: usize = 0,
    /// Whether the next member of the object or array being written needs a comma.
    comma: bool = false,

    fn begin(machine: *State, name: []const u8) Event {
        var event = Event{ .machine = machine };
        event.raw("{\"event\":");
        event.quoted(name);
        event.comma = true;
        return event;
    }

    fn end(self: *Event) void {
        self.raw("}\n");
        self.flush();
    }

    fn flush(self: *Event) void {
        if (self.len == 0) return;
        if (self.machine.writer.log_fn) |log_fn| log_fn(self.machine.writer.context, self.buffer[0..self.len]);
        self.len = 0;
    }

    fn raw(self: *Event, bytes: []const u8) void {
        var rest = bytes;
        while (rest.len > 0) {
            if (self.len == self.buffer.len) self.flush();
            const count = @min(rest.len, self.buffer.len - self.len);
            @memcpy(self.buffer[self.len..][0..count], rest[0..count]);
            self.len += count;
            rest = rest[count..];
        }
    }

    /// `text` as a JSON string. The characters of UTF-8 are written as they are; a byte
    /// that is not part of one (a name may hold any bytes, and a long message is cut
    /// where it no longer fits) becomes U+FFFD, so that the log is always UTF-8.
    fn quoted(self: *Event, text: []const u8) void {
        self.raw("\"");
        var index: usize = 0;
        while (index < text.len) {
            const byte = text[index];
            const length = characterLength(text[index..]);
            if (length > 1) {
                self.raw(text[index..][0..length]);
                index += length;
                continue;
            }
            index += 1;
            switch (byte) {
                '"' => self.raw("\\\""),
                '\\' => self.raw("\\\\"),
                '\n' => self.raw("\\n"),
                '\r' => self.raw("\\r"),
                '\t' => self.raw("\\t"),
                0...8, 11, 12, 14...31, 127 => {
                    var escape: [6]u8 = undefined;
                    self.raw(std.fmt.bufPrint(&escape, "\\u{x:0>4}", .{byte}) catch unreachable);
                },
                0x80...0xff => self.raw("\xef\xbf\xbd"),
                else => self.raw(&.{byte}),
            }
        }
        self.raw("\"");
    }

    fn separator(self: *Event) void {
        if (self.comma) self.raw(",");
        self.comma = true;
    }

    fn key(self: *Event, name: []const u8) void {
        self.separator();
        self.quoted(name);
        self.raw(":");
    }

    fn string(self: *Event, name: []const u8, text: []const u8) void {
        self.key(name);
        self.quoted(text);
    }

    fn number(self: *Event, name: []const u8, value: anytype) void {
        self.key(name);
        self.plain(value);
    }

    fn plain(self: *Event, value: anytype) void {
        var digits: [24]u8 = undefined;
        self.raw(std.fmt.bufPrint(&digits, "{d}", .{value}) catch unreachable);
    }

    fn open(self: *Event, name: []const u8, bracket: []const u8) void {
        self.key(name);
        self.raw(bracket);
        self.comma = false;
    }

    fn close(self: *Event, bracket: []const u8) void {
        self.raw(bracket);
        self.comma = true;
    }

    /// "name":[the top `limit` cells, the top last]
    fn cells(self: *Event, name: []const u8, items: []const Cell, limit: usize) void {
        self.open(name, "[");
        for (items[items.len -| limit..]) |value| {
            self.separator();
            self.plain(value);
        }
        self.close("]");
    }

    /// The name of the word `id`, and where it or the operation at `pc` is in a file.
    fn word(self: *Event, id: u16, line: u32) void {
        const machine = self.machine;
        const entry = machine.words[id];
        const name = machine.wordName(entry);
        self.string("word", if (name.len == 0) ":NONAME" else name);
        if (entry.source_file != 0 and line != 0) {
            self.string("file", machine.sourceFileName(entry.source_file - 1));
            self.number("line", line);
        }
    }
};

/// The bytes of the UTF-8 character that `text` starts with: 1 for an ASCII character,
/// and also for a byte that starts no well-formed character (too short, a wrong
/// continuation, an overlong form, a surrogate, or past U+10FFFF).
fn characterLength(text: []const u8) usize {
    const first = text[0];
    const length: usize = switch (first) {
        0xc2...0xdf => 2,
        0xe0...0xef => 3,
        0xf0...0xf4 => 4,
        else => return 1,
    };
    if (text.len < length) return 1;
    for (text[1..length]) |byte| {
        if (byte & 0xc0 != 0x80) return 1;
    }
    const second = text[1];
    const well_formed = switch (first) {
        0xe0 => second >= 0xa0,
        0xed => second <= 0x9f,
        0xf0 => second >= 0x90,
        0xf4 => second <= 0x8f,
        else => true,
    };
    return if (well_formed) length else 1;
}

/// `text` without the character that was cut at its end, when it filled the `capacity`
/// bytes it was kept in.
fn wholeCharacters(text: []const u8, capacity: usize) []const u8 {
    if (text.len < capacity) return text;
    // The last character starts at most three bytes before the end.
    var start = text.len;
    while (start > 0 and text.len - start < 4) {
        start -= 1;
        if (text[start] & 0xc0 != 0x80) break;
    }
    if (text[start] < 0x80) return text;
    return if (characterLength(text[start..]) == text.len - start) text else text[0..start];
}

/// The first line of the log.
pub fn logStart(self: *State, version: []const u8) void {
    var event = Event.begin(self, "start");
    event.string("version", version);
    event.end();
}

/// A word of the trace starts or ends; `depth` is how deep the traced words are nested.
pub fn logTrace(self: *State, id: u16, enter: bool, depth: usize) void {
    var event = Event.begin(self, if (enter) "enter" else "exit");
    const name = if (id < self.word_count) self.wordName(self.words[id]) else "?";
    event.string("word", if (name.len == 0) ":NONAME" else name);
    event.number("depth", depth);
    event.number("stack_depth", self.data_depth);
    event.cells("stack", self.data_stack[0..self.data_depth], trace_items);
    event.end();
}

pub fn logTraceLimit(self: *State) void {
    var event = Event.begin(self, "trace_limit");
    event.number("lines", self.trace_lines);
    event.end();
}

/// An error that reached the host: `message` is what `report` wrote for it (with the
/// file and line of the input before it, when there are any), `location` that file and
/// line, and the stacks are as the error left them.
pub fn logError(self: *State, err: anyerror, message: []const u8, location: ?defs.ErrorLocation, data_depth: usize, float_depth: usize) void {
    var event = Event.begin(self, "error");
    event.string("message", std.mem.trimEnd(u8, wholeCharacters(message, self.report_text.len), "\n"));
    if (throwCode(self, err)) |code| event.number("code", code);
    if (location) |place| {
        event.string("file", self.sourceFileName(place.file_index));
        event.number("line", place.line);
    }
    event.open("backtrace", "[");
    var index: usize = 0;
    while (index < self.backtrace_count) {
        const pc = self.backtrace[index];
        var times: usize = 1;
        while (index + times < self.backtrace_count and self.backtrace[index + times] == pc) times += 1;
        index += times;
        const owner = error_reporting.codeOwner(self, pc) orelse continue;
        const entry = self.words[owner];
        // The words whose copied code holds the operation, innermost first.
        var guards: [16]u16 = undefined;
        var guard_count: usize = 0;
        for (self.code[entry.code_start..pc], entry.code_start..) |op, at| {
            if (inline_calls.isInline(op) and pc - at < inline_calls.span(op.value) and guard_count < guards.len) {
                guards[guard_count] = inline_calls.wordId(op.value);
                guard_count += 1;
            }
        }
        while (guard_count > 0) {
            guard_count -= 1;
            event.separator();
            event.raw("{");
            event.comma = false;
            const guard = guards[guard_count];
            const name = if (guard < self.word_count) self.wordName(self.words[guard]) else "?";
            event.string("word", if (name.len == 0) ":NONAME" else name);
            if (entry.source_file != 0 and self.code_lines[pc] != 0) {
                event.string("file", self.sourceFileName(entry.source_file - 1));
                event.number("line", self.code_lines[pc]);
            }
            event.key("inline");
            event.raw("true");
            if (times > 1) event.number("times", times);
            event.close("}");
        }
        event.separator();
        event.raw("{");
        event.comma = false;
        event.word(owner, self.code_lines[pc]);
        if (times > 1) event.number("times", times);
        event.close("}");
    }
    event.close("]");
    event.number("more", self.backtrace_total - self.backtrace_count);
    event.number("stack_depth", data_depth);
    event.cells("stack", self.data_stack[0..data_depth], error_items);
    if (defs.float_enabled) {
        event.number("float_stack_depth", float_depth);
        event.open("float_stack", "[");
        for (self.float_stack[float_depth -| error_items..float_depth]) |value| {
            event.separator();
            // JSON has no number for these.
            if (std.math.isNan(value)) event.quoted("nan") else if (std.math.isInf(value)) event.quoted(if (value > 0) "inf" else "-inf") else {
                var digits: [400]u8 = undefined;
                event.raw(std.fmt.bufPrint(&digits, "{d}", .{value}) catch "0");
            }
        }
        event.close("]");
    }
    event.end();
}

/// The THROW code of an error that `report` was given, when it has one.
fn throwCode(self: *const State, err: anyerror) ?Cell {
    if (err == error.Thrown) return self.throw_code;
    if (err == error.UnknownWord) return defs.throw_code_undefined_word;
    for (defs.error_codes) |entry| {
        if (entry[0] == err) return entry[1];
    }
    return null;
}

/// The profile: a line of the whole and a line for each word, in the order of the
/// report (see `Profile.show`).
pub fn logProfile(self: *State, profile: *const profiler.Profile, order: []const u16) void {
    {
        var event = Event.begin(self, "profile");
        event.number("operations", profile.operations);
        event.end();
    }
    for (order) |id| {
        var event = Event.begin(self, "profile_word");
        event.word(id, self.words[id].source_line);
        event.number("calls", profile.calls[id]);
        event.number("self", profiler.selfOperations(profile, self, id));
        event.number("total", profile.total[id]);
        event.end();
    }
}
