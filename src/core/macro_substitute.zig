//! Case-sensitive dictionary macros. Behavior follows the designated Gforth;
//! this is an independent implementation, not a translation of substitute.fs.
const std = @import("std");
const forth = @import("../forth.zig");
const defs = @import("defs.zig");
const map = @import("memory_map.zig");
const values = @import("string_values.zig");
const registry = @import("address_registry.zig");
const State = forth.State;
const Cell = map.Cell;
const RuntimeError = defs.RuntimeError;

pub fn replaces(self: *State) RuntimeError!void {
    const name = try self.memoryRange();
    const text = try self.memoryRange();
    // Dictionary creation can change the source/name buffers. Keep the name local.
    if (name.len == 0) return error.InvalidDefinition;
    if (name.len > map.max_name) return error.NameTooLong;
    var copy: [map.max_name]u8 = undefined;
    @memcpy(copy[0..name.len], name);
    const spelling = copy[0..name.len];
    const source: Cell = @intCast(@intFromPtr(text.ptr) - @intFromPtr(self.memory.ptr));
    if (self.lookupIn(spelling, map.macros_wordlist)) |found| {
        const id = self.synonymTarget(found);
        if (self.words[id].kind != .string_value) {
            self.write("WARNING: ");
            self.write(spelling);
            self.write(" is a hard-coded macro\n");
            return;
        }
        try @import("dynamic_strings.zig").storeString(self, source, text.len, self.words[id].value);
    } else {
        const previous = self.currentWordlist();
        try self.writeCell(map.current_wordlist_address, map.macros_wordlist);
        defer self.writeCell(map.current_wordlist_address, previous) catch unreachable;
        try values.define(self, spelling, source, @intCast(text.len));
    }
}

/// A private VM-heap output, promoted to a $TMP owner only after successful capture.
/// It is never visible to callbacks; errors and nested substitutions cannot leak it.
pub const Captured = struct {
    buffer: Cell = 0,
    length: usize = 0,
    capacity: usize = 0,
    count: Cell = 0,

    pub fn free(output: Captured, self: *State) void {
        _ = self.heapFree(output.buffer) catch {};
    }
    pub fn bytes(output: Captured, self: *State) []const u8 {
        return self.memory[@intCast(output.buffer + map.cell_size)..][0..output.length];
    }
    pub fn put(output: *Captured, self: *State, data: []const u8) RuntimeError!void {
        const length = std.math.add(usize, output.length, data.len) catch return self.throwIor(map.errno_no_memory);
        if (output.buffer == 0 or length > output.capacity) {
            const capacity = @max(length, @max(64, output.capacity *| 2));
            const size = std.math.add(usize, map.cell_size, capacity) catch return self.throwIor(map.errno_no_memory);
            var resized = try self.heapResize(output.buffer, size);
            if (resized == .no_memory and capacity != length) resized = try self.heapResize(output.buffer, std.math.add(usize, map.cell_size, length) catch return self.throwIor(map.errno_no_memory));
            output.buffer = switch (resized) {
                .address => |address| address,
                .no_memory => return self.throwIor(map.errno_no_memory),
                .bad_pointer => return error.InvalidAddress,
            };
            output.capacity = @intCast((try self.blockSize((try self.findBlock(output.buffer)).?)) - map.cell_size);
        }
        const at: usize = @intCast(output.buffer + map.cell_size + @as(Cell, @intCast(output.length)));
        @memmove(self.memory[at..][0..data.len], data);
        registry.written(self, @intCast(at), data.len, false);
        output.length = length;
    }
};

/// Both captured APIs run the callback once per occurrence, even when clipping output.
pub fn capture(self: *State, source: []const u8) RuntimeError!Captured {
    var output = Captured{};
    errdefer output.free(self);
    const previous_sink = self.capture_sink;
    const previous_target = self.capture_target;
    const previous_failed = self.capture_failed;
    self.capture_sink = &output;
    self.capture_target = null;
    self.capture_failed = false;
    defer {
        self.capture_sink = previous_sink;
        self.capture_target = previous_target;
        self.capture_failed = previous_failed;
    }
    output.count = try substitute(self, source);
    if (self.capture_failed) return self.throwIor(map.errno_no_memory);
    // Empty output still needs a valid length-prefixed buffer for $TMP.
    if (output.buffer == 0) try output.put(self, "");
    if (output.capacity != output.length) {
        output.buffer = switch (try self.heapResize(output.buffer, map.cell_size + output.length)) {
            .address => |address| address,
            .no_memory => return self.throwIor(map.errno_no_memory),
            .bad_pointer => return error.InvalidAddress,
        };
        output.capacity = output.length;
    }
    try self.writeCell(output.buffer, @intCast(output.length));
    return output;
}

pub fn print(self: *State, source: []const u8) RuntimeError!Cell {
    return substitute(self, source);
}

fn substitute(self: *State, source: []const u8) RuntimeError!Cell {
    // Callbacks may replace/free the original string or rotate all $TMP slots.
    // Snapshot before executing any callback, including in the streaming API.
    const snapshot = try self.heapAllocate(source.len) orelse return self.throwIor(map.errno_no_memory);
    defer _ = self.heapFree(snapshot) catch {};
    const at: usize = @intCast(snapshot);
    @memmove(self.memory[at..][0..source.len], source);
    const text = self.memory[at..][0..source.len];
    var count: Cell = 0;
    var i: usize = 0;
    while (i < text.len) {
        if (self.capture_failed) return self.throwIor(map.errno_no_memory);
        if (text[i] != '%') {
            const end = std.mem.indexOfScalarPos(u8, text, i, '%') orelse text.len;
            self.write(text[i..end]);
            i = end;
            continue;
        }
        if (i + 1 < text.len and text[i + 1] == '%') {
            self.write("%");
            i += 2;
            continue;
        }
        const close = std.mem.indexOfScalarPos(u8, text, i + 1, '%') orelse {
            self.write(text[i..]);
            break;
        };
        if (self.lookupIn(text[i + 1 .. close], map.macros_wordlist)) |id| {
            const depth = self.data_depth;
            try self.executeWord(id);
            if (self.capture_failed) return self.throwIor(map.errno_no_memory);
            if (self.data_depth != depth + 2) return error.InvalidDefinition;
            const value = try self.memoryRange();
            self.write(value);
            count += 1;
        } else self.write(text[i .. close + 1]);
        i = close + 1;
    }
    return count;
}
