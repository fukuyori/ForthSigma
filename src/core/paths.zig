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
        .basename, .dirname => {
            try self.requireDepth(2);
            const count = std.math.cast(usize, try self.peek(0)) orelse return error.InvalidAddress;
            const address = try self.peek(1);
            const at = try self.memoryAddress(address, count);
            const text = self.memory[at..][0..count];
            const prefix = if (std.mem.lastIndexOfScalar(u8, text, '/')) |index| index + 1 else 0;
            self.data_stack[self.data_depth - 2] = if (builtin == .basename) address + @as(map.Cell, @intCast(prefix)) else address;
            self.data_stack[self.data_depth - 1] = @intCast(if (builtin == .basename) count - prefix else prefix);
        },
        .open_path_file, .file_to_path => try search(self, builtin == .file_to_path),
        .absolute_file_query => {
            try self.requireDepth(2);
            const count = std.math.cast(usize, try self.peek(0)) orelse return error.InvalidAddress;
            const address = try self.peek(1);
            const at = try self.memoryAddress(address, count);
            const text = self.memory[at..][0..count];
            const is_absolute = absolute(text);
            self.data_depth -= 2;
            try self.push(if (is_absolute) -1 else 0);
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

const capacity = map.string_buffer_count * map.string_buffer_size;
pub const Buffer = struct {
    bytes: [capacity]u8 = undefined,
    len: usize = 0,
    fn append(b: *Buffer, value: []const u8) RuntimeError!void {
        if (value.len > b.bytes.len - b.len) return error.StringTooLong;
        @memcpy(b.bytes[b.len..][0..value.len], value);
        b.len += value.len;
    }
    pub fn text(b: *const Buffer) []const u8 {
        return b.bytes[0..b.len];
    }
};

fn absolute(text: []const u8) bool {
    return text.len != 0 and (text[0] == '/' or text[0] == '~' or std.mem.startsWith(u8, text, "./") or (text.len > 2 and text[1] == ':'));
}

// Lexical compaction deliberately does not resolve symlinks or require existence.
fn normalize(input: []const u8) RuntimeError!Buffer {
    var result = Buffer{};
    var starts: [capacity]usize = undefined;
    var parents: [capacity]bool = undefined;
    var depth: usize = 0;
    const rooted = std.mem.startsWith(u8, input, "/");
    if (rooted) try result.append("/");
    var parts = std.mem.splitScalar(u8, input, '/');
    while (parts.next()) |part| {
        const terminal = @intFromPtr(part.ptr) + part.len == @intFromPtr(input.ptr) + input.len;
        if (part.len == 0 or (!terminal and std.mem.eql(u8, part, "."))) continue;
        if (!terminal and std.mem.eql(u8, part, "..") and depth > 0 and !parents[depth - 1]) {
            depth -= 1;
            result.len = starts[depth];
            continue;
        }
        starts[depth] = result.len;
        parents[depth] = std.mem.eql(u8, part, "..");
        depth += 1;
        if (result.len > 0 and result.bytes[result.len - 1] != '/') try result.append("/");
        try result.append(part);
    }
    if (input.len > 0 and input[input.len - 1] == '/' and result.len > 0 and result.bytes[result.len - 1] != '/') try result.append("/");
    return result;
}

fn candidate(self: *State, directory: ?[]const u8, name: []const u8) RuntimeError!Buffer {
    var joined = Buffer{};
    if (directory) |dir| {
        try joined.append(dir);
        if (dir.len != 0 and dir[dir.len - 1] != '/' and dir[dir.len - 1] != '\\') try joined.append("/");
    }
    try joined.append(name);
    var expanded = Buffer{};
    if (std.mem.startsWith(u8, joined.text(), "./")) {
        if (self.currentFileFrame()) |frame| {
            const source = self.sourceFileName(frame.file_index);
            if (std.mem.lastIndexOfAny(u8, source, "/\\")) |end| try expanded.append(source[0 .. end + 1]);
        }
        try expanded.append(joined.text()[2..]);
    } else if (std.mem.startsWith(u8, joined.text(), "~+/")) {
        try expanded.append(joined.text()[3..]);
    } else try expanded.append(joined.text());
    return normalize(expanded.text());
}

pub fn openedName(self: *State, text: []const u8) RuntimeError!Buffer {
    var result = Buffer{};
    if (text.len == 0 or text[0] != '~') {
        try result.append(text);
        return result;
    }
    const end = std.mem.indexOfScalar(u8, text, '/') orelse text.len;
    const user = text[1..end];
    if (std.mem.eql(u8, user, "+")) {
        if (end < text.len) try result.append(text[end + 1 ..]);
        return result;
    }
    var home: [capacity]u8 = undefined;
    const length = if ((try self.fileOps()).user_home) |lookup|
        try lookup(self.writer.context, user, &home)
    else if (user.len == 0) home: {
        const getenv = self.writer.getenv_fn orelse return error.HostUnavailable;
        if (try getenv(self.writer.context, "HOME", &home)) |n| break :home n;
        if (comptime @import("builtin").os.tag == .windows) {
            if (try getenv(self.writer.context, "HOMEDRIVE", &home)) |drive| {
                if (drive > home.len) return error.InvalidAddress;
                if (try getenv(self.writer.context, "HOMEPATH", home[drive..])) |tail| {
                    if (tail > home.len - drive) return error.InvalidAddress;
                    break :home drive + tail;
                }
            }
            if (try getenv(self.writer.context, "TEMP", &home)) |n| break :home n;
            if (try getenv(self.writer.context, "TMP", &home)) |n| break :home n;
        }
        break :home null;
    } else null;
    if (length) |n| {
        if (n > home.len) return error.InvalidAddress;
        var trimmed = n;
        if (trimmed > 1 and home[trimmed - 1] == '/') trimmed -= 1;
        try result.append(home[0..trimmed]);
        try result.append(text[end..]);
    } else if (user.len == 0) {
        try result.append(text[end..]);
    } else try result.append(text);
    return result;
}

fn search(self: *State, close: bool) RuntimeError!void {
    try self.requireDepth(3);
    if (!close and self.data_depth == self.data_stack.len) return error.StackOverflow;
    const count = std.math.cast(usize, try self.peek(1)) orelse return error.InvalidAddress;
    const at = try self.memoryAddress(try self.peek(2), count);
    const name = self.memory[at..][0..count];
    const result = try openInPath(self, name, try self.peek(0));
    self.data_depth -= 3;
    if (result.file.ior != 0) {
        if (close) return self.throwCode(result.file.ior);
        return self.push(result.file.ior);
    }
    const fid: map.Cell = @bitCast(result.file.value);
    if (close) {
        const ior = (try self.fileOps()).close(self.writer.context, fid);
        if (ior != 0) return self.throwCode(ior);
    }
    const destination: usize = @intCast(map.string_buffer_base);
    @memcpy(self.memory[destination..][0..result.name.len], result.name.text());
    registry.written(self, map.string_buffer_base, result.name.len, false);
    if (!close) try self.push(fid);
    try self.push(map.string_buffer_base);
    try self.push(@intCast(result.name.len));
    if (!close) try self.push(0);
}

/// Opens without using the Forth stack or publishing a transient string buffer.
/// On success the caller owns the file handle.
pub fn openInPath(self: *State, name: []const u8, owner: map.Cell) RuntimeError!struct { file: forth.FileResult, name: Buffer } {
    const files = try self.fileOps();
    const bypass = absolute(name);
    var remaining: []const u8 = "";
    if (!bypass) {
        const path = try self.fetchString(owner);
        remaining = self.memory[@intCast(path.address)..][0..path.length];
    }
    var last: map.Cell = -37;
    while (true) {
        try @import("words_numeric.zig").checkWorkBlock(self);
        var directory: ?[]const u8 = null;
        if (!bypass) {
            const end = std.mem.indexOfScalar(u8, remaining, 0) orelse remaining.len;
            if (end == 0) break;
            directory = remaining[0..end];
            remaining = if (end < remaining.len) remaining[end + 1 ..] else remaining[remaining.len..];
        }
        const resolved = try candidate(self, directory, name);
        const native = try openedName(self, resolved.text());
        // Reject embedded NUL rather than opening a silently truncated filename.
        const opened = if (std.mem.indexOfScalar(u8, native.text(), 0) != null)
            forth.FileResult{ .ior = forth.errnoIor(map.errno_invalid) }
        else
            files.open(self.writer.context, native.text(), .read_only, false);
        last = opened.ior;
        if (last == 0) return .{ .file = opened, .name = resolved };
        if (bypass) break;
    }
    return .{ .file = .{ .ior = last }, .name = .{} };
}
