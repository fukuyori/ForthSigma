//! Smart stack output and retained, bounded VM exception locations.
const std = @import("std");
const forth = @import("../forth.zig");
const defs = @import("defs.zig");
const map = @import("memory_map.zig");
const navigation = @import("source_navigation.zig");
const editor = @import("source_editor.zig");
const inline_calls = @import("inline_calls.zig");
pub const trace_words = [_]defs.Builtin{ .trace_select, .trace_next, .trace_back };
pub const words = trace_words ++ [_]defs.Builtin{ .smart_stacks, .fancy_after_l };
pub const Entry = struct { word: u16, line: u32 };
pub const History = struct {
    entries: [forth.State.max_backtrace]Entry = undefined,
    count: usize = 0,
    total: usize = 0,
    current: ?usize = null,
    generation: u64 = 0,
};
fn append(self: *forth.State, word: u16, line: u32) void {
    const history = &self.source_trace;
    if (history.count < history.entries.len) {
        history.entries[history.count] = .{ .word = word, .line = line };
        history.count += 1;
    }
    history.total += 1;
}
pub fn retain(self: *forth.State) void {
    if (!defs.debug_enabled or !defs.tools_enabled or self.throw_nobt or self.backtrace_suppression != 0) {
        self.source_trace = .{ .generation = self.image_generation };
        return;
    }
    // A source-browser input/host error must not erase the VM exception being
    // inspected. Replace history only when a new VM trace was actually captured.
    if (self.backtrace_count == 0) return;
    self.source_trace = .{ .generation = self.image_generation };
    if (comptime defs.debug_enabled and defs.tools_enabled) for (self.backtrace[0..self.backtrace_count]) |pc| {
        const owner = @import("error_reporting.zig").codeOwner(self, pc) orelse continue;
        const word = self.words[owner];
        var guards: [16]struct { word: u16, pc: u16 } = undefined;
        var count: usize = 0;
        for (self.code[word.code_start..pc], word.code_start..) |op, at| {
            if (inline_calls.isInline(op) and pc - at < inline_calls.span(op.value) and count < guards.len) {
                guards[count] = .{ .word = inline_calls.wordId(op.value), .pc = @intCast(at) };
                count += 1;
            }
        }
        var place = pc;
        while (count != 0) {
            count -= 1;
            append(self, guards[count].word, self.code_lines[place]);
            place = guards[count].pc;
        }
        append(self, owner, self.code_lines[place]);
    };
    self.source_trace.total += self.backtrace_total -| self.backtrace_count;
}
pub fn execute(self: *forth.State, comptime word: defs.Builtin) forth.RuntimeError!void {
    switch (word) {
        .smart_stacks => try smart(self),
        // Sigma's plain source browser needs no additional terminal decoration.
        // This presentation hook has no stack or cursor effects, matching the
        // designated reference's observed plain and pseudo-terminal behavior.
        .fancy_after_l => {},
        .trace_select => {
            const index = try self.peek(0);
            if (index < 0) return error.InvalidNumber;
            _ = try self.pop();
            try choose(self, std.math.cast(usize, index), editor.takeDestination(self));
        },
        .trace_next, .trace_back => {
            const history = current(self);
            const index: ?usize = if (history.current) |at|
                (if (word == .trace_next) (if (at + 1 < history.count) at + 1 else null) else (if (at != 0) at - 1 else null))
            else if (history.count != 0)
                (if (word == .trace_next) 0 else history.count - 1)
            else
                null;
            try choose(self, index, editor.takeDestination(self));
        },
        else => unreachable,
    }
}
fn current(self: *forth.State) *History {
    if (self.source_trace.generation != self.image_generation) self.source_trace = .{ .generation = self.image_generation };
    return &self.source_trace;
}
fn choose(self: *forth.State, requested: ?usize, destination: editor.Destination) forth.RuntimeError!void {
    const history = current(self);
    const at = requested orelse return missing(self);
    if (at >= history.count) return missing(self);
    history.current = at;
    const entry = history.entries[at];
    if (entry.word >= self.word_count) return missing(self);
    const word = self.words[entry.word];
    self.source_navigation.length = 0;
    if (word.source_file != 0) navigation.select(self, word.source_file - 1, if (entry.line != 0) entry.line else word.source_line);
    if (self.source_navigation.length == 0) return navigation.noLocation(self);
    if (destination == .editor) try editor.open(self) else try navigation.execute(self, .source_l);
}
fn missing(self: *forth.State) forth.RuntimeError!void {
    self.source_trace.current = null;
    self.source_navigation.length = 0;
    return navigation.noLocation(self);
}
fn string(self: *forth.State, address: map.Cell, count: map.Cell) ?[]const u8 {
    const length = std.math.cast(usize, count) orelse return null;
    if (length > 4096 or address < 0) return null;
    var valid = false;
    if (address >= self.sizes.heapBase() and address < self.heapTop()) {
        if (self.findBlock(address) catch null) |block| {
            valid = (self.blockUsed(block) catch false) and length <= (self.blockSize(block) catch return null);
        }
    } else if (address > map.data_start and address <= self.data_here) {
        for (self.code[0..self.code_count]) |op| {
            if (op.kind == .string_literal and op.value + 1 == address and self.memory[@intCast(op.value)] == length) {
                valid = true;
                break;
            }
        }
    }
    if (!valid) return null;
    const at = self.memoryAddress(address, length) catch return null;
    const bytes = self.memory[at..][0..length];
    return if (std.unicode.utf8ValidateSlice(bytes)) bytes else null;
}
fn quoted(self: *forth.State, text: []const u8) void {
    var output: [328]u8 = undefined;
    output[0] = '"';
    var n: usize = 1;
    var at: usize = 0;
    while (at < text.len and at < 80) {
        const byte = text[at];
        if (byte >= 128) {
            const length = std.unicode.utf8ByteSequenceLength(byte) catch unreachable;
            if (at + length > 80) break;
            @memcpy(output[n..][0..length], text[at..][0..length]);
            at += length;
            n += length;
            continue;
        }
        const escape: ?[]const u8 = switch (byte) {
            '"' => "\\\"",
            '\\' => "\\\\",
            '\n' => "\\n",
            '\r' => "\\r",
            '\t' => "\\t",
            else => null,
        };
        if (escape) |part| {
            @memcpy(output[n..][0..part.len], part);
            n += part.len;
        } else if (byte < 32 or byte == 127) {
            const hex = "0123456789abcdef";
            @memcpy(output[n..][0..4], &[4]u8{ '\\', 'x', hex[byte >> 4], hex[byte & 15] });
            n += 4;
        } else {
            output[n] = byte;
            n += 1;
        }
        at += 1;
    }
    if (at < text.len) {
        @memcpy(output[n..][0..3], "...");
        n += 3;
    }
    output[n] = '"';
    output[n + 1] = ' ';
    self.write(output[0 .. n + 2]);
}
fn smart(self: *forth.State) forth.RuntimeError!void {
    const shown = try @import("words_stack_display.zig").visibleItems(self, self.data_depth);
    const floats = try @import("words_stack_display.zig").visibleItems(self, self.float_depth);
    self.writeDepth(self.data_depth);
    var at = self.data_depth - shown;
    while (at < self.data_depth) {
        if (at + 1 < self.data_depth) if (string(self, self.data_stack[at], self.data_stack[at + 1])) |text| {
            quoted(self, text);
            at += 2;
            continue;
        };
        self.write("#");
        self.writeNumberDecimal(self.data_stack[at]);
        self.write(" ");
        at += 1;
    }
    if (comptime defs.float_enabled) if (self.float_depth != 0) {
        self.write("\nF:");
        self.writeDepth(self.float_depth);
        for (self.float_stack[self.float_depth - floats .. self.float_depth]) |value| {
            try @import("words_float.zig").writeCompactFloat(self, value, .e_dot, 0);
            self.write(" ");
        }
    };
}
