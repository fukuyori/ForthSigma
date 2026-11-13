//! Path descriptors use ordinary dynamic-string owner cells and NUL separators.
const std = @import("std");
const forth = @import("../forth.zig");
const defs = @import("defs.zig");
const map = @import("memory_map.zig");
const strings = @import("dynamic_strings.zig");
const registry = @import("address_registry.zig");
const RuntimeError = defs.RuntimeError;
const State = forth.State;

pub fn execute(self: *State, comptime builtin: defs.Builtin) RuntimeError!void {
    switch (builtin) {
        .absolute_file_query => {
            try self.requireDepth(2);
            const count = std.math.cast(usize, try self.peek(0)) orelse return error.InvalidAddress;
            const address = try self.peek(1);
            const at = try self.memoryAddress(address, count);
            const text = self.memory[at..][0..count];
            const absolute = count > 0 and (text[0] == '/' or text[0] == '~' or std.mem.startsWith(u8, text, "./") or (count > 2 and text[1] == ':'));
            self.data_depth -= 2;
            try self.push(if (absolute) -1 else 0);
        },
        .clear_path => {
            const owner = try self.peek(0);
            try strings.storeString(self, 0, 0, owner);
            self.data_depth -= 1;
        },
        .also_path => {
            try self.requireDepth(3);
            const owner = try self.peek(0);
            const length = std.math.cast(usize, try self.peek(1)) orelse return error.InvalidAddress;
            const at = try self.memoryAddress(try self.peek(2), length);
            try store(self, owner, self.memory[at..][0..length], false);
            self.data_depth -= 3;
        },
        .path_plus, .path_equals => {
            const owner = try self.peek(0);
            const token = (try self.nextSourceToken()) orelse return error.InvalidDefinition;
            try store(self, owner, token, builtin == .path_equals);
            self.data_depth -= 1;
        },
        .dot_path => {
            const owner = try self.peek(0);
            const text = try self.fetchString(owner);
            var bytes: []const u8 = self.memory[@intCast(text.address)..][0..text.length];
            var snapshot: ?map.Cell = null;
            defer if (snapshot) |copy| {
                _ = self.heapFree(copy) catch {};
            };
            // Capturing output may grow the very owner being displayed.
            if (self.capture_target != null and bytes.len != 0) {
                const copy = try self.heapAllocate(bytes.len) orelse return self.throwIor(map.errno_no_memory);
                snapshot = copy;
                @memcpy(self.memory[@intCast(copy)..][0..bytes.len], bytes);
                bytes = self.memory[@intCast(copy)..][0..bytes.len];
            }
            self.data_depth -= 1;
            var offset: usize = 0;
            while (offset < bytes.len) {
                const end = std.mem.indexOfScalarPos(u8, bytes, offset, 0) orelse bytes.len;
                if (end == offset) break;
                self.write(bytes[offset..end]);
                self.write(" ");
                offset = end + 1;
            }
        },
        else => unreachable,
    }
}

/// Assemble privately, then replace the owned string once. Aliases and allocation
/// failures cannot leave a half-appended separator or modify the parse source.
fn store(self: *State, owner: map.Cell, input: []const u8, replace: bool) RuntimeError!void {
    const reserved = try strings.reservePointer(self, owner);
    errdefer strings.cancelPointer(self, owner, reserved);
    const old = if (replace) strings.StringRef{ .address = 0, .length = 0 } else try self.fetchString(owner);
    const separator: usize = @intFromBool(old.length != 0);
    const prefix = std.math.add(usize, old.length, separator) catch return self.throwIor(map.errno_no_memory);
    const total = std.math.add(usize, prefix, input.len) catch return self.throwIor(map.errno_no_memory);
    const temporary = try self.heapAllocate(total) orelse return self.throwIor(map.errno_no_memory);
    defer _ = self.heapFree(temporary) catch {};
    const at: usize = @intCast(temporary);
    const source: map.Cell = @intCast(@intFromPtr(input.ptr) - @intFromPtr(self.memory.ptr));
    try registry.preflightCopies(self, &.{
        .{ .destination = temporary, .source = old.address, .length = old.length },
        .{ .destination = temporary + @as(map.Cell, @intCast(prefix)), .source = source, .length = input.len },
    });
    try self.copyMemory(temporary, old.address, old.length);
    if (separator != 0) {
        self.memory[at + old.length] = 0;
        registry.written(self, temporary + @as(map.Cell, @intCast(old.length)), 1, false);
    }
    try self.copyMemory(temporary + @as(map.Cell, @intCast(prefix)), source, input.len);
    if (replace) for (self.memory[at..][0..total], 0..) |*byte, i| {
        if (byte.* == '|') {
            byte.* = 0;
            registry.written(self, temporary + @as(map.Cell, @intCast(i)), 1, false);
        }
    };
    try strings.storeString(self, temporary, total, owner);
}
