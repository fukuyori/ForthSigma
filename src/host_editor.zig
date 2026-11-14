//! Synchronous EDITOR launch. Only EDITOR itself is a trusted command prefix;
//! source paths are quoted separately and temporary text is exclusively created.
const std = @import("std");
const builtin = @import("builtin");
const forth = @import("forth.zig");
const Request = @import("core/host_interface.zig").EditorRequest;
const Run = *const fn (?*anyopaque, []const u8) forth.RuntimeError!forth.Cell;
const windows = builtin.os.tag == .windows;

pub fn run(request: Request, editor: []const u8, temporary_directory: ?[]const u8, context: ?*anyopaque, launch: Run) forth.RuntimeError!void {
    const prefix = std.mem.trim(u8, editor, " \t\r\n");
    if (prefix.len == 0) return error.HostUnavailable;
    if (std.mem.indexOfScalar(u8, prefix, 0) != null) return error.HostFailed;
    var temporary: Temporary = undefined;
    const line = switch (request) {
        .file => |file| file.line,
        .text => |text| text.line,
    };
    if (line == 0) return error.InvalidNumber;
    const path = switch (request) {
        .file => |file| file.path,
        .text => |text| created: {
            temporary = try Temporary.create(text.bytes, temporary_directory);
            break :created temporary.path[0..temporary.length];
        },
    };
    defer if (request == .text) temporary.remove();
    var command: [4095]u8 = undefined;
    const text = try commandLine(windows, prefix, path, line, &command);
    if (try launch(context, text) != 0) return error.HostFailed;
}

pub fn commandLine(is_windows: bool, prefix: []const u8, path: []const u8, line: u32, buffer: []u8) forth.RuntimeError![]const u8 {
    if (path.len == 0 or std.mem.indexOfScalar(u8, path, 0) != null) return error.InvalidAddress;
    var quoted: [4095]u8 = undefined;
    var n: usize = 0;
    if (is_windows) {
        // cmd.exe expands percent/exclamation sequences even inside quotes.
        // Reject these forms rather than run a different path. Other shell
        // metacharacters (including &) stay inside the quoted argument.
        if (std.mem.indexOfAny(u8, path, "\"%!\r\n") != null) return error.InvalidAddress;
        if (path.len > quoted.len - 2) return error.StringTooLong;
        quoted[0] = '"';
        @memcpy(quoted[1..][0..path.len], path);
        quoted[path.len + 1] = '"';
        n = path.len + 2;
    } else {
        quoted[0] = '\'';
        n = 1;
        for (path) |byte| {
            const piece: []const u8 = if (byte == '\'') "'\\''" else &.{byte};
            if (piece.len > quoted.len - n) return error.StringTooLong;
            @memcpy(quoted[n..][0..piece.len], piece);
            n += piece.len;
        }
        if (n == quoted.len) return error.StringTooLong;
        quoted[n] = '\'';
        n += 1;
    }
    return std.fmt.bufPrint(buffer, "{s} +{d} {s}", .{ prefix, line, quoted[0..n] }) catch error.StringTooLong;
}

const Temporary = struct {
    path: [2048:0]u8 = undefined,
    length: usize = 0,
    fn create(bytes: []const u8, directory: ?[]const u8) forth.RuntimeError!Temporary {
        return if (windows) win.create(bytes) else posix.create(bytes, directory);
    }
    fn remove(self: *const Temporary) void {
        if (windows) {
            var path: [2048:0]u16 = undefined;
            const n = std.unicode.utf8ToUtf16Le(&path, self.path[0..self.length]) catch return;
            path[n] = 0;
            _ = win.DeleteFileW(&path);
        } else _ = posix.unlink(&self.path);
    }
};
const posix = struct {
    extern "c" fn getpid() c_int;
    extern "c" fn unlink([*:0]const u8) c_int;
    fn writeAll(fd: c_int, bytes: []const u8) forth.RuntimeError!void {
        var rest = bytes;
        while (rest.len != 0) {
            const n = std.c.write(fd, rest.ptr, rest.len);
            if (n < 0 and std.c._errno().* == @backingInt(std.c.E.INTR)) continue;
            if (n <= 0) return error.HostFailed;
            rest = rest[@intCast(n)..];
        }
    }
    fn create(bytes: []const u8, directory: ?[]const u8) forth.RuntimeError!Temporary {
        const dir = if (directory) |d| (if (d.len != 0) d else "/tmp") else "/tmp";
        if (std.mem.indexOfScalar(u8, dir, 0) != null) return error.InvalidAddress;
        var time: std.c.timespec = .{ .sec = 0, .nsec = 0 };
        _ = std.c.clock_gettime(std.c.CLOCK.REALTIME, &time);
        for (0..16) |attempt| {
            var result = Temporary{};
            const tag = @as(u64, @bitCast(@as(i64, time.nsec))) *% 0x9E37_79B9_7F4A_7C15 +% attempt;
            const path = std.fmt.bufPrint(result.path[0..result.path.len], "{s}/sigma-editor-{d}-{x}.txt", .{ std.mem.trimEnd(u8, dir, "/"), getpid(), tag }) catch return error.StringTooLong;
            result.length = path.len;
            result.path[path.len] = 0;
            const fd = std.c.open(&result.path, .{ .ACCMODE = .WRONLY, .CREAT = true, .EXCL = true, .NOFOLLOW = true, .CLOEXEC = true }, @as(std.c.mode_t, 0o600));
            if (fd < 0) {
                if (std.c._errno().* == @backingInt(std.c.E.EXIST)) continue;
                return error.FileUnavailable;
            }
            errdefer result.remove();
            var closed = false;
            defer if (!closed) {
                _ = std.c.close(fd);
            };
            try writeAll(fd, bytes);
            if (bytes.len == 0 or bytes[bytes.len - 1] != '\n') try writeAll(fd, "\n");
            const status = std.c.close(fd);
            closed = true;
            if (status != 0) return error.HostFailed;
            return result;
        }
        return error.FileUnavailable;
    }
};
const win = struct {
    const Handle = *anyopaque;
    extern "kernel32" fn GetTempPathW(u32, [*]u16) callconv(.winapi) u32;
    extern "kernel32" fn GetCurrentProcessId() callconv(.winapi) u32;
    extern "kernel32" fn GetTickCount64() callconv(.winapi) u64;
    extern "kernel32" fn GetLastError() callconv(.winapi) u32;
    extern "kernel32" fn CreateFileW([*:0]const u16, u32, u32, ?*const anyopaque, u32, u32, ?Handle) callconv(.winapi) Handle;
    extern "kernel32" fn WriteFile(Handle, [*]const u8, u32, ?*u32, ?*anyopaque) callconv(.winapi) i32;
    extern "kernel32" fn CloseHandle(Handle) callconv(.winapi) i32;
    extern "kernel32" fn DeleteFileW([*:0]const u16) callconv(.winapi) i32;
    fn writeAll(fd: Handle, bytes: []const u8) forth.RuntimeError!void {
        var rest = bytes;
        while (rest.len != 0) {
            var n: u32 = 0;
            if (WriteFile(fd, rest.ptr, @intCast(@min(rest.len, std.math.maxInt(u32))), &n, null) == 0 or n == 0) return error.HostFailed;
            rest = rest[n..];
        }
    }
    fn create(bytes: []const u8) forth.RuntimeError!Temporary {
        var directory: [1024]u16 = undefined;
        const count = GetTempPathW(directory.len, &directory);
        if (count == 0 or count >= directory.len) return error.FileUnavailable;
        for (0..16) |attempt| {
            var path: [2048:0]u16 = undefined;
            @memcpy(path[0..count], directory[0..count]);
            var suffix: [96]u8 = undefined;
            const tag = GetTickCount64() *% 0x9E37_79B9_7F4A_7C15 +% attempt;
            const tail = std.fmt.bufPrint(&suffix, "sigma-editor-{d}-{x}.txt", .{ GetCurrentProcessId(), tag }) catch return error.StringTooLong;
            for (tail, 0..) |byte, i| path[count + i] = byte;
            path[count + tail.len] = 0;
            const fd = CreateFileW(&path, 0x40000000, 0, null, 1, 0, null);
            if (@intFromPtr(fd) == std.math.maxInt(usize)) {
                const failure = GetLastError();
                if (failure == 80 or failure == 183) continue;
                return error.FileUnavailable;
            }
            var result = Temporary{};
            errdefer {
                _ = DeleteFileW(&path);
            }
            var closed = false;
            defer if (!closed) {
                _ = CloseHandle(fd);
            };
            try writeAll(fd, bytes);
            if (bytes.len == 0 or bytes[bytes.len - 1] != '\n') try writeAll(fd, "\n");
            const status = CloseHandle(fd);
            closed = true;
            if (status == 0) return error.HostFailed;
            result.length = std.unicode.utf16LeToUtf8(&result.path, path[0 .. count + tail.len]) catch return error.InvalidAddress;
            result.path[result.length] = 0;
            return result;
        }
        return error.FileUnavailable;
    }
};

test "editor command quotes source paths independently from trusted editor arguments" {
    var buffer: [4095]u8 = undefined;
    try std.testing.expectEqualStrings("code --wait +12 '/tmp/a b'\\''$(echo nope).fs'", try commandLine(false, "code --wait", "/tmp/a b'$(echo nope).fs", 12, &buffer));
    try std.testing.expectEqualStrings("editor +3 \"C:\\a&b\\日本語.fs\"", try commandLine(true, "editor", "C:\\a&b\\日本語.fs", 3, &buffer));
    try std.testing.expectError(error.InvalidAddress, commandLine(true, "editor", "C:\\%NAME%.fs", 1, &buffer));
    try std.testing.expectError(error.InvalidAddress, commandLine(true, "editor", "C:\\x!y.fs", 1, &buffer));
    try std.testing.expectError(error.InvalidAddress, commandLine(false, "editor", "x\x00y", 1, &buffer));
    var short: [3]u8 = undefined;
    try std.testing.expectError(error.StringTooLong, commandLine(false, "editor", "/tmp/a.fs", 1, &short));
}
