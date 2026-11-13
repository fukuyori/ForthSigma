//! Native iterator resources. Opaque monotonic IDs never expose pointers or reuse a
//! closed handle in this process. The table is runtime-only, like file streams.
const std = @import("std");
const builtin = @import("builtin");
const c = @import("c_file");
const forth = @import("forth.zig");
const windows = builtin.os.tag == .windows;
const FindData = if (windows) @typeInfo(@typeInfo(@TypeOf(c._wfindfirst64)).@"fn".params[1].type.?).pointer.child else void;
const Stream = if (windows) struct { handle: isize, data: FindData, pending: bool, ended: bool } else *c.DIR;
const Slot = struct { id: forth.Cell = 0, stream: ?Stream = null };
const capacity = 64;
var slots: [capacity]Slot = @splat(.{});
// File IDs occupy a different namespace. Exhaustion fails instead of wrapping.
var next_id: forth.Cell = 0x4000000000000000;
fn errnoResult() forth.Cell {
    const err = std.c._errno().*;
    return forth.errnoIor(if (err == 0) 5 else err);
}
fn bad() forth.Cell {
    return forth.errnoIor(forth.errno_bad_file);
}
fn locate(id: forth.Cell) ?*Slot {
    if (id < 0x4000000000000000) return null;
    for (&slots) |*slot| if (slot.stream != null and slot.id == id) return slot;
    return null;
}
fn terminate(name: []const u8, buffer: *[4096:0]u8) bool {
    if (name.len >= buffer.len or std.mem.indexOfScalar(u8, name, 0) != null) return false;
    @memcpy(buffer[0..name.len], name);
    buffer[name.len] = 0;
    return true;
}
fn wide(name: [*:0]const u8, buffer: []u16) ?[*:0]const u16 {
    const text = std.mem.span(name);
    if (text.len >= buffer.len) {
        std.c._errno().* = 38;
        return null;
    }
    const n = std.unicode.utf8ToUtf16Le(buffer[0 .. buffer.len - 1], text) catch {
        std.c._errno().* = 42;
        return null;
    };
    buffer[n] = 0;
    return @ptrCast(buffer[0..n :0]);
}

pub fn open(_: ?*anyopaque, name: []const u8) forth.FileResult {
    const slot = for (&slots) |*candidate| {
        if (candidate.stream == null) break candidate;
    } else return .{ .ior = forth.errnoIor(24) };
    if (next_id == std.math.maxInt(forth.Cell)) return .{ .ior = forth.errnoIor(24) };
    var path: [4096:0]u8 = undefined;
    if (!terminate(name, &path)) return .{ .ior = forth.errnoIor(forth.errno_invalid) };
    std.c._errno().* = 0;
    const stream: Stream = if (windows) created: {
        var utf16: [8192]u16 = undefined;
        // CRT stat rejects some trailing separators; preserve drive and cwd roots.
        var stat_length = name.len;
        while (stat_length > 1 and (path[stat_length - 1] == '/' or path[stat_length - 1] == '\\') and !(stat_length == 3 and path[1] == ':')) stat_length -= 1;
        path[stat_length] = 0;
        const native = wide(&path, &utf16) orelse return .{ .ior = errnoResult() };
        const Stat = @typeInfo(@typeInfo(@TypeOf(c._wstat64)).@"fn".params[1].type.?).pointer.child;
        var info: Stat = undefined;
        if (c._wstat64(native, &info) != 0) return .{ .ior = errnoResult() };
        if (info.st_mode & c._S_IFDIR == 0) return .{ .ior = forth.errnoIor(20) };
        // Reserve room for / * and NUL; backslash is a native separator too.
        if (name.len + 2 >= path.len) return .{ .ior = forth.errnoIor(forth.errno_invalid) };
        _ = terminate(name, &path);
        var n = name.len;
        if (n != 0 and path[n - 1] != '/' and path[n - 1] != '\\' and !(n == 2 and path[1] == ':')) {
            path[n] = '/';
            n += 1;
        }
        path[n] = '*';
        path[n + 1] = 0;
        const search = wide(&path, &utf16) orelse return .{ .ior = errnoResult() };
        var iterator: Stream = undefined;
        iterator.handle = @intCast(c._wfindfirst64(search, &iterator.data));
        iterator.pending = iterator.handle != -1;
        iterator.ended = !iterator.pending;
        if (!iterator.pending and std.c._errno().* != 2) return .{ .ior = errnoResult() };
        break :created iterator;
    } else c.opendir(&path) orelse return .{ .ior = errnoResult() };
    slot.* = .{ .id = next_id, .stream = stream };
    next_id += 1;
    return .{ .value = @bitCast(slot.id) };
}

pub fn read(_: ?*anyopaque, id: forth.Cell, buffer: []u8) forth.LineResult {
    const slot = locate(id) orelse return .{ .ior = bad() };
    std.c._errno().* = 0;
    var encoded: [1024]u8 = undefined;
    const name: []const u8 = if (windows) item: {
        const stream = &slot.stream.?;
        if (stream.ended) return .{};
        if (stream.pending) stream.pending = false else if (c._wfindnext64(stream.handle, &stream.data) != 0) {
            if (std.c._errno().* == 2) {
                stream.ended = true;
                return .{};
            }
            return .{ .ior = errnoResult() };
        }
        const text = std.mem.sliceTo(&stream.data.name, 0);
        const length = std.unicode.utf16LeToUtf8(&encoded, text) catch return .{ .ior = forth.errnoIor(42) };
        break :item encoded[0..length];
    } else item: {
        const entry = c.readdir(slot.stream.?);
        if (entry == null) return if (std.c._errno().* == 0) .{} else .{ .ior = errnoResult() };
        break :item std.mem.sliceTo(&entry.*.d_name, 0);
    };
    const length = @min(name.len, buffer.len);
    @memcpy(buffer[0..length], name[0..length]);
    return .{ .length = length, .found = true, .ior = if (length == name.len) 0 else forth.errnoIor(if (windows) 38 else c.ENAMETOOLONG) };
}

fn closeStream(stream: Stream) forth.Cell {
    std.c._errno().* = 0;
    const result = if (windows) (if (stream.handle == -1) @as(c_int, 0) else c._findclose(stream.handle)) else c.closedir(stream);
    return if (result == 0) 0 else errnoResult();
}
pub fn close(_: ?*anyopaque, id: forth.Cell) forth.Cell {
    const slot = locate(id) orelse return bad();
    const stream = slot.stream.?;
    slot.* = .{}; // As with CLOSE-FILE, invalidate even if native close reports an error.
    return closeStream(stream);
}
pub fn closeAll() void {
    for (&slots) |*slot| {
        if (slot.stream) |stream| _ = closeStream(stream);
        slot.* = .{};
    }
}

test "directory IDs reject stale and foreign handles and exhaust without leaking" {
    if (!@import("build_options").files) return error.SkipZigTest;
    defer closeAll();
    const first = open(null, ".");
    try std.testing.expectEqual(@as(forth.Cell, 0), first.ior);
    const id: forth.Cell = @bitCast(first.value);
    try std.testing.expectEqual(@as(forth.Cell, 0), close(null, id));
    try std.testing.expectEqual(bad(), close(null, id));
    var buffer: [8]u8 = undefined;
    try std.testing.expectEqual(bad(), read(null, id, &buffer).ior);
    try std.testing.expectEqual(bad(), read(null, forth.first_file_id, &buffer).ior);
    var ids: [capacity]forth.Cell = undefined;
    for (&ids) |*next| {
        const opened = open(null, ".");
        try std.testing.expectEqual(@as(forth.Cell, 0), opened.ior);
        next.* = @bitCast(opened.value);
        try std.testing.expect(next.* > id);
    }
    try std.testing.expectEqual(forth.errnoIor(24), open(null, ".").ior);
    for (ids) |next| try std.testing.expectEqual(@as(forth.Cell, 0), close(null, next));
    const again = open(null, ".");
    try std.testing.expectEqual(@as(forth.Cell, 0), again.ior);
    try std.testing.expect(again.value > @as(u64, @bitCast(ids[capacity - 1])));
    closeAll();
    const last = open(null, ".");
    try std.testing.expectEqual(@as(forth.Cell, 0), last.ior);
    try std.testing.expect(last.value > again.value);
}

test "native directory reads consume truncation and preserve EOF buffers" {
    if (!@import("build_options").files) return error.SkipZigTest;
    defer closeAll();
    const opened = open(null, ".");
    try std.testing.expectEqual(@as(forth.Cell, 0), opened.ior);
    const id: forth.Cell = @bitCast(opened.value);
    var buffer: [4096]u8 = undefined;
    const truncated = read(null, id, buffer[0..0]);
    try std.testing.expect(truncated.found);
    try std.testing.expectEqual(@as(usize, 0), truncated.length);
    try std.testing.expect(truncated.ior != 0);
    var ended = false;
    for (0..10000) |_| {
        @memset(&buffer, 'X');
        const result = read(null, id, &buffer);
        try std.testing.expectEqual(@as(forth.Cell, 0), result.ior);
        if (!result.found) {
            ended = true;
            try std.testing.expectEqual(@as(usize, 0), result.length);
            for (buffer) |byte| try std.testing.expectEqual(@as(u8, 'X'), byte);
            break;
        }
        try std.testing.expect(result.length < buffer.len);
        try std.testing.expectEqual(@as(u8, 'X'), buffer[result.length]);
    }
    try std.testing.expect(ended);
    try std.testing.expect(!read(null, id, &buffer).found);
    try std.testing.expectEqual(@as(forth.Cell, 0), close(null, id));
}
