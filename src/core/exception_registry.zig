//! Hidden dictionary records for copied messages and lazy message converters.
const std = @import("std");
const forth = @import("../forth.zig");
const defs = @import("defs.zig");
const map = @import("memory_map.zig");
const scopes = @import("words_value_extensions.zig");
pub const first_code: map.Cell = -4294967296;
pub const capacity: map.Cell = 4096;
pub const limit = first_code - capacity;
pub const header_size = 32;
pub const max_text = 4096;
pub const words = [_]defs.Builtin{ .exception_word, .exceptions_word };
pub const Record = struct { first: map.Cell, count: map.Cell, callback: map.Cell, length: usize, address: map.Cell };

pub fn read(self: *const forth.State, word: defs.Word) forth.RuntimeError!Record {
    if (word.kind != .exception_entry or word.name_len != 0 or word.value < map.data_start or word.value > self.data_here - header_size) return error.InvalidImage;
    const r = Record{ .first = self.readCellConst(word.value), .count = self.readCellConst(word.value + 8), .callback = self.readCellConst(word.value + 16), .length = std.math.cast(usize, self.readCellConst(word.value + 24)) orelse return error.InvalidImage, .address = word.value };
    const next = self.readCellConst(map.exception_next_address);
    if (r.first > first_code or r.first <= limit or r.count < 1 or r.count > capacity or r.first - r.count + 1 <= next or r.length > max_text or r.length > self.data_here - word.value - header_size) return error.InvalidImage;
    switch (word.builtin) {
        .exception_word => if (r.callback != -1 or r.count != 1) return error.InvalidImage,
        .exceptions_word => if (r.callback < 0 or r.callback >= self.word_count or r.length != 0) return error.InvalidImage,
        else => return error.InvalidImage,
    }
    return r;
}
pub fn overlaps(a: Record, first: map.Cell, count: map.Cell) bool {
    return a.first >= first - count + 1 and first >= a.first - a.count + 1;
}
pub fn validateState(self: *const forth.State) forth.RuntimeError!void {
    const next = self.readCellConst(map.exception_next_address);
    if (next > first_code or next < limit) return error.InvalidImage;
    for (self.words[0..self.word_count], 0..) |w, i| {
        if (w.kind != .exception_entry) continue;
        const r = try read(self, w);
        for (self.words[0..i]) |prior| if (prior.kind == .exception_entry) {
            const p = try read(self, prior);
            if (overlaps(p, r.first, r.count)) return error.InvalidImage;
        };
    }
}
pub fn checkRange(self: *const forth.State, first: map.Cell, count: map.Cell) forth.RuntimeError!void {
    for (self.words[0..self.word_count]) |w| if (w.kind == .exception_entry) {
        if (overlaps(try read(self, w), first, count)) return error.InvalidImage;
    };
}
/// Hidden records cannot be reclaimed by ALLOT while their dictionary entries
/// remain live. FORGET/MARKER remove those entries together with their storage.
pub fn checkRewind(self: *const forth.State, next: map.Cell) forth.RuntimeError!void {
    for (self.words[0..self.word_count]) |word| {
        if (word.kind != .exception_entry) continue;
        const record = try read(self, word);
        if (next < record.address + header_size + @as(map.Cell, @intCast(record.length))) return error.InvalidDefinition;
    }
}
pub fn execute(self: *forth.State, comptime builtin: defs.Builtin) forth.RuntimeError!void {
    try self.requireDepth(2);
    const callback: map.Cell = if (builtin == .exceptions_word) try self.wordId(try self.peek(1)) else -1;
    const count = if (builtin == .exceptions_word) try self.peek(0) else 1;
    if (count < 0 or count > capacity) return error.InvalidNumber;
    const length: usize = if (builtin == .exception_word) std.math.cast(usize, try self.peek(0)) orelse return error.StringTooLong else 0;
    if (length > max_text) return error.StringTooLong;
    const at = if (builtin == .exception_word) try self.memoryAddress(try self.peek(1), length) else 0;
    var copy: [max_text]u8 = undefined;
    if (length != 0) @memcpy(copy[0..length], self.memory[at..][0..length]);
    const first = self.readCellConst(map.exception_next_address);
    if (first > first_code or first < limit) return error.InvalidImage;
    if (count > first - limit) return error.MemoryExhausted;
    if (count != 0) {
        const id = try self.appendException(@intCast(header_size + length));
        self.words[id].builtin = builtin;
        const address = self.words[id].value;
        try self.writeCell(address, first);
        try self.writeCell(address + 8, count);
        try self.writeCell(address + 16, callback);
        try self.writeCell(address + 24, @intCast(length));
        if (length != 0) @memmove(self.memory[@intCast(address + header_size)..][0..length], copy[0..length]);
        try self.writeCell(map.exception_next_address, first - count);
    }
    self.data_depth -= 1;
    self.data_stack[self.data_depth - 1] = first;
}

/// Reporter callbacks are best-effort and never replace the original exception.
pub fn writeMessage(self: *forth.State, code: map.Cell) bool {
    for (self.words[0..self.word_count]) |w| {
        if (w.kind != .exception_entry) continue;
        const r = read(self, w) catch continue;
        if (code > r.first or code <= r.first - r.count) continue;
        if (r.callback == -1) {
            self.write(self.memory[@intCast(r.address + header_size)..][0..r.length]);
            self.write("\n");
            return true;
        }
        const data = self.data_depth;
        const floats = self.float_depth;
        const returns = self.return_depth;
        const loops = self.loop_depth;
        const old_throw = self.throw_code;
        const old_abort = self.abort_message;
        const old_halted = self.halted;
        const generation = self.image_generation;
        const suppression = self.backtrace_suppression;
        const no_trace = self.throw_nobt;
        const trace_count = self.backtrace_count;
        const trace_total = self.backtrace_total;
        const trace_level = self.backtrace_level;
        var trace: [forth.State.max_backtrace]u16 = undefined;
        @memcpy(trace[0..trace_count], self.backtrace[0..trace_count]);
        var guard: scopes.Guard = undefined;
        scopes.pushGuard(self, &guard, @intCast(r.callback)) catch return false;
        defer scopes.popGuard(self, &guard);
        self.backtrace_suppression += 1;
        defer {
            self.backtrace_suppression = suppression;
            self.throw_nobt = no_trace;
            self.throw_code = old_throw;
            self.abort_message = old_abort;
            if (self.image_generation == generation) {
                // CATCH/NOTHROW in a formatter may clear the active trace even
                // under suppression. It belongs to the original exception.
                @memcpy(self.backtrace[0..trace_count], trace[0..trace_count]);
                self.backtrace_count = trace_count;
                self.backtrace_total = trace_total;
                self.backtrace_level = trace_level;
                self.data_depth = data;
                self.float_depth = floats;
                self.return_depth = returns;
                self.loop_depth = loops;
                self.halted = old_halted;
            }
        }
        self.push(r.first - code) catch return false;
        self.executeWord(@intCast(r.callback)) catch return false;
        if (!guard.valid or self.data_depth != data + 2 or self.float_depth != floats or self.return_depth != returns or self.loop_depth != loops) return false;
        const length = std.math.cast(usize, self.peek(0) catch return false) orelse return false;
        const address = self.memoryAddress(self.peek(1) catch return false, length) catch return false;
        self.write(self.memory[address..][0..length]);
        self.write("\n");
        return true;
    }
    return false;
}
