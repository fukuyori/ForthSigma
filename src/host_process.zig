//! The Tcl program of the TCL words (wish): started with the script the core gives,
//! written to a file in the temporary directory, and pipes to its standard input and
//! output. Native ownership uses the common process registry; this adapter keeps
//! wish discovery, private protocol I/O and the display budget. The program is SIGMA_WISH when that is set,
//! else wish (on Windows, Git for Windows's when the PATH has none; on macOS, not the
//! system's /usr/bin/wish, which macOS no longer lets start, but Homebrew's or
//! MacPorts's), unless TCL-PROGRAM named one.

const std = @import("std");
const builtin = @import("builtin");
const forth = @import("forth.zig");

const is_windows = builtin.os.tag == .windows;
const linux = builtin.os.tag == .linux;
const budget = @import("host_display_budget.zig");

pub const start = if (is_windows) windows.startProgram else posix.startProgram;
pub const write = if (is_windows) windows.writeProgram else posix.writeProgram;
pub const read = if (is_windows) windows.readProgram else posix.readProgram;
pub const stop = stopProgram;

pub const Shared = struct {
    context: ?*anyopaque,
    launch: *const fn (?*anyopaque, []const u8, []const u8, u32) forth.FileResult,
    raw: *const fn (?*anyopaque, forth.Cell, u2) isize,
    close: *const fn (?*anyopaque, forth.Cell) forth.Cell,
    status: *const fn (?*anyopaque, forth.Cell) forth.ProcessStatus,
    signal: *const fn (?*anyopaque, forth.Cell, bool) forth.Cell,
    wait: *const fn (?*anyopaque, forth.Cell, u32) forth.Cell,
    free: *const fn (?*anyopaque, forth.Cell, u32) forth.Cell,
};
var shared: ?Shared = null;
var shared_id: forth.Cell = 0;
pub fn bind(host: Shared) void {
    shared = host;
}
pub fn detachInternal(id: forth.Cell) void {
    if (id != shared_id) return;
    if (is_windows) {
        windows.to_program = null;
        windows.from_program = null;
    } else {
        posix.to_program = -1;
        posix.from_program = -1;
    }
}
pub fn releasedInternal(id: forth.Cell) void {
    if (id != shared_id) return;
    detachInternal(id);
    shared_id = 0;
    if (is_windows) windows.removeScript() else posix.removeScript();
}
fn cleanupLimit() u32 {
    return if (budget.active()) @intCast(std.math.clamp(budget.cleanupDeadline() - budget.now(), 0, 3000)) else 3000;
}
fn launchShared(program: []const u8, script: []const u8) forth.RuntimeError!void {
    const host = shared orelse return error.HostUnavailable;
    const result = host.launch(host.context, program, script, cleanupLimit());
    shared_id = @bitCast(result.value);
    if (result.ior != 0) {
        _ = stopProgram(null);
        return error.HostFailed;
    }
    errdefer {
        _ = stopProgram(null);
    }
    const input = host.raw(host.context, shared_id, 0);
    const output = host.raw(host.context, shared_id, 1);
    if (input < 0 or output < 0) return error.HostFailed;
    if (is_windows) {
        windows.to_program = @ptrFromInt(@as(usize, @intCast(input)));
        windows.from_program = @ptrFromInt(@as(usize, @intCast(output)));
    } else {
        posix.to_program = @intCast(input);
        posix.from_program = @intCast(output);
    }
}
fn ended(host: Shared, id: forth.Cell, milliseconds: u32) bool {
    const until = budget.now() + milliseconds;
    while (true) {
        const observed = host.status(host.context, id);
        if (observed.ior != 0) return false;
        if (observed.state != 1) return true;
        const remaining = until - budget.now();
        if (remaining <= 0) return false;
        if (host.wait(host.context, id, @intCast(@min(remaining, 10))) != 0) return false;
    }
}
fn stopProgram(_: ?*anyopaque) bool {
    if (shared_id == 0) return true;
    const host = shared orelse return false;
    const id = shared_id;
    detachInternal(id);
    const close_error = host.close(host.context, id);
    var observed = host.status(host.context, id);
    if (observed.ior == 0 and observed.state == 1) {
        if (budget.active()) {
            _ = host.signal(host.context, id, true);
            _ = ended(host, id, cleanupLimit());
        } else if (!ended(host, id, 2000)) {
            _ = host.signal(host.context, id, false);
            if (!ended(host, id, 1000)) {
                _ = host.signal(host.context, id, true);
                _ = ended(host, id, 3000);
            }
        }
    }
    observed = host.status(host.context, id);
    if (observed.ior == 0 and observed.state == 1) return false;
    const result = host.free(host.context, id, cleanupLimit());
    // releasedInternal is called only once the registry actually removes the ID.
    return result == 0 and close_error == 0 and shared_id == 0;
}

const windows = struct {
    const Handle = *anyopaque;
    const SecurityAttributes = extern struct { length: u32 = @sizeOf(SecurityAttributes), descriptor: ?*anyopaque = null, inherit: i32 = 1 };
    extern "kernel32" fn CreatePipe(*?Handle, *?Handle, *const SecurityAttributes, u32) callconv(.winapi) i32;
    extern "kernel32" fn CreateFileW([*:0]const u16, u32, u32, ?*const SecurityAttributes, u32, u32, ?Handle) callconv(.winapi) Handle;
    extern "kernel32" fn WriteFile(Handle, [*]const u8, u32, ?*u32, ?*anyopaque) callconv(.winapi) i32;
    extern "kernel32" fn ReadFile(Handle, [*]u8, u32, ?*u32, ?*anyopaque) callconv(.winapi) i32;
    extern "kernel32" fn PeekNamedPipe(Handle, ?*anyopaque, u32, ?*u32, ?*u32, ?*u32) callconv(.winapi) i32;
    extern "kernel32" fn CloseHandle(Handle) callconv(.winapi) i32;
    extern "kernel32" fn WaitForSingleObject(Handle, u32) callconv(.winapi) u32;
    extern "kernel32" fn GetTempPathW(u32, [*]u16) callconv(.winapi) u32;
    extern "kernel32" fn GetCurrentProcessId() callconv(.winapi) u32;
    extern "kernel32" fn DeleteFileW([*:0]const u16) callconv(.winapi) i32;
    extern "kernel32" fn GetEnvironmentVariableW([*:0]const u16, ?[*]u16, u32) callconv(.winapi) u32;
    extern "kernel32" fn GetLastError() callconv(.winapi) u32;
    extern "kernel32" fn GetTickCount64() callconv(.winapi) u64;
    extern "kernel32" fn Sleep(u32) callconv(.winapi) void;
    extern "kernel32" fn CreateThread(?*anyopaque, usize, *const fn (?*anyopaque) callconv(.winapi) u32, ?*anyopaque, u32, ?*u32) callconv(.winapi) ?Handle;
    extern "kernel32" fn CreateEventW(?*anyopaque, i32, i32, ?[*:0]const u16) callconv(.winapi) ?Handle;
    extern "kernel32" fn SetEvent(Handle) callconv(.winapi) i32;
    extern "kernel32" fn OpenThread(u32, i32, u32) callconv(.winapi) ?Handle;
    extern "kernel32" fn GetCurrentThreadId() callconv(.winapi) u32;
    extern "kernel32" fn CancelSynchronousIo(Handle) callconv(.winapi) i32;
    /// THREAD_TERMINATE, the access CancelSynchronousIo needs.
    const thread_terminate: u32 = 0x0001;
    const infinite: u32 = 0xFFFF_FFFF;
    extern "kernel32" fn SearchPathW(?[*:0]const u16, [*:0]const u16, ?[*:0]const u16, u32, [*]u16, ?*?[*]u16) callconv(.winapi) u32;
    extern "kernel32" fn GetFileAttributesW([*:0]const u16) callconv(.winapi) u32;

    const invalid_attributes: u32 = std.math.maxInt(u32);
    const attribute_directory: u32 = 0x10;

    const invalid_handle: usize = std.math.maxInt(usize);
    const handle_flag_inherit: u32 = 1;
    const use_std_handles: u32 = 0x100;
    const generic_read: u32 = 0x8000_0000;
    const generic_write: u32 = 0x4000_0000;
    const create_new: u32 = 1;
    const error_file_exists: u32 = 80;
    const open_existing: u32 = 3;
    const no_window: u32 = 0x0800_0000;

    var to_program: ?Handle = null;
    var from_program: ?Handle = null;
    /// The temporary file of the script, removed when the program stops; empty before.
    var script_name: [1024:0]u16 = @splat(0);

    /// Writes the script to a new file of the user's temporary directory, never over a
    /// file that is there already.
    fn writeScript(text: []const u8) bool {
        var directory: [512]u16 = undefined;
        const length = GetTempPathW(directory.len, &directory);
        if (length == 0 or length >= directory.len) return false;
        for (0..16) |attempt| {
            var name_buffer: [64]u8 = undefined;
            const tag = GetTickCount64() *% 0x9E37_79B9_7F4A_7C15 +% attempt;
            const name = std.fmt.bufPrint(&name_buffer, "sigma-tk-{d}-{x}.tcl", .{ GetCurrentProcessId(), tag }) catch return false;
            @memcpy(script_name[0..length], directory[0..length]);
            for (name, 0..) |byte, index| script_name[length + index] = byte;
            script_name[length + name.len] = 0;
            const file = CreateFileW(&script_name, generic_write, 0, null, create_new, 0, null);
            if (@intFromPtr(file) == invalid_handle) {
                script_name[0] = 0;
                if (GetLastError() == error_file_exists) continue;
                return false;
            }
            var written: u32 = 0;
            const ok = WriteFile(file, text.ptr, @intCast(text.len), &written, null) != 0 and written == text.len;
            _ = CloseHandle(file);
            if (!ok) removeScript();
            return ok;
        }
        return false;
    }

    fn removeScript() void {
        if (script_name[0] != 0) _ = DeleteFileW(&script_name);
        script_name[0] = 0;
    }

    /// Where Git for Windows puts its wish: under these directories, named by
    /// environment variables (the machine's programs, and a user's own install).
    const git_places = blk: {
        @setEvalBranchQuota(20_000);
        const L = std.unicode.utf8ToUtf16LeStringLiteral;
        break :blk [_]struct { variable: [:0]const u16, path: []const u16 }{
            .{ .variable = L("ProgramW6432"), .path = L("\\Git\\mingw64\\bin\\wish.exe") },
            .{ .variable = L("ProgramFiles"), .path = L("\\Git\\mingw64\\bin\\wish.exe") },
            .{ .variable = L("LOCALAPPDATA"), .path = L("\\Programs\\Git\\mingw64\\bin\\wish.exe") },
        };
    };

    /// Whether a file (not a directory) of that name exists.
    fn isFile(name: [*:0]const u16) bool {
        const attributes = GetFileAttributesW(name);
        return attributes != invalid_attributes and attributes & attribute_directory == 0;
    }

    /// The PATH, for looking wish up in its directories and nowhere else. A static
    /// buffer: an environment variable is at most 32767 characters.
    var path_value: [32768]u16 = undefined;

    /// The program: TCL-PROGRAM's, SIGMA_WISH, wish on the PATH, or Git for Windows's
    /// wish; none when it is not found. In UTF-16. The current directory and the
    /// program's own are not searched, so that a wish.exe lying in a directory the user
    /// happens to work in is never started.
    fn programName(program: []const u8, buffer: []u16) ?[]const u16 {
        if (program.len != 0) {
            const length = std.unicode.utf8ToUtf16Le(buffer, program) catch return null;
            return buffer[0..length];
        }
        const variable = std.unicode.utf8ToUtf16LeStringLiteral("SIGMA_WISH");
        const length = GetEnvironmentVariableW(variable, buffer.ptr, @intCast(buffer.len));
        // SIGMA_WISH set: that program, or none when it is too long to take (another
        // one is not looked for).
        if (length != 0) return if (length < buffer.len) buffer[0..length] else null;
        const default = std.unicode.utf8ToUtf16LeStringLiteral("wish");
        var found: [512]u16 = undefined;
        // With a null path SearchPathW looks in the current directory before the PATH;
        // given the PATH's value it looks in those directories only.
        const path_length = GetEnvironmentVariableW(std.unicode.utf8ToUtf16LeStringLiteral("PATH"), &path_value, path_value.len);
        const on_path = if (path_length != 0 and path_length < path_value.len)
            SearchPathW(@ptrCast(&path_value), default, std.unicode.utf8ToUtf16LeStringLiteral(".exe"), found.len, &found, null)
        else
            0;
        if (on_path != 0 and on_path < found.len) {
            if (on_path > buffer.len) return null;
            @memcpy(buffer[0..on_path], found[0..on_path]);
            return buffer[0..on_path];
        }
        // Not on the PATH (a longer path than `found` takes is there all the same).
        if (on_path == 0) {
            for (git_places) |place| {
                const base = GetEnvironmentVariableW(place.variable, buffer.ptr, @intCast(buffer.len));
                if (base == 0 or base + place.path.len + 1 > buffer.len) continue;
                @memcpy(buffer[base..][0..place.path.len], place.path);
                buffer[base + place.path.len] = 0;
                if (isFile(@ptrCast(buffer.ptr))) return buffer[0 .. base + place.path.len];
            }
        }
        // Not a bare name: CreateProcess would take it from the current directory.
        return null;
    }

    fn startProgram(_: ?*anyopaque, program: []const u8, script: []const u8) forth.RuntimeError!void {
        // Automatic display has one time for the window and Tk together.
        if (budget.expired()) return error.HostFailed;
        if (!stopProgram(null)) return error.HostFailed;
        if (budget.expired()) return error.HostFailed;
        if (!writeScript(script)) return error.HostFailed;
        errdefer if (shared_id == 0) removeScript();
        var name_buffer: [512]u16 = undefined;
        const name = programName(program, &name_buffer) orelse return error.HostFailed;
        const allocator = std.heap.page_allocator;
        const name_utf8 = std.unicode.wtf16LeToWtf8Alloc(allocator, name) catch return error.HostFailed;
        defer allocator.free(name_utf8);
        const script_utf8 = std.unicode.wtf16LeToWtf8Alloc(allocator, std.mem.sliceTo(&script_name, 0)) catch return error.HostFailed;
        defer allocator.free(script_utf8);
        try launchShared(name_utf8, script_utf8);
    }

    fn writeProgram(_: ?*anyopaque, bytes: []const u8) forth.RuntimeError!void {
        const handle = to_program orelse return error.HostFailed;
        // While automatic display looks for a display, a program that does not read
        // must not hold SHOW past the time: a watch cancels the write then.
        var watch: Watch = .{};
        const bounded = budget.active();
        if (bounded) {
            if (budget.expired()) return error.HostFailed;
            // Without the watch the write could not be bounded: it is not tried.
            if (!watch.start(@intCast(@max(0, budget.remaining())))) return error.HostFailed;
        }
        defer watch.stop();
        var rest = bytes;
        while (rest.len != 0) {
            if (bounded and budget.expired()) return error.HostFailed;
            var written: u32 = 0;
            const amount: u32 = @intCast(@min(rest.len, 1 << 20));
            if (WriteFile(handle, rest.ptr, amount, &written, null) == 0 or written == 0) return error.HostFailed;
            rest = rest[written..];
        }
    }

    /// Cancels the calling thread's blocked WriteFile when the display search's time
    /// runs out: from then on every 10 ms until stop, so that a write begun just after
    /// a cancel is cancelled too.
    const Watch = struct {
        target: ?Handle = null,
        done: ?Handle = null,
        thread: ?Handle = null,
        milliseconds: u32 = 0,

        /// False when a handle it needs could not be had.
        fn start(self: *Watch, milliseconds: u32) bool {
            self.target = OpenThread(thread_terminate, 0, GetCurrentThreadId()) orelse return false;
            self.done = CreateEventW(null, 1, 0, null) orelse {
                self.stop();
                return false;
            };
            self.milliseconds = milliseconds;
            self.thread = CreateThread(null, 0, run, self, 0, null) orelse {
                self.stop();
                return false;
            };
            return true;
        }

        fn run(parameter: ?*anyopaque) callconv(.winapi) u32 {
            const self: *Watch = @ptrCast(@alignCast(parameter.?));
            if (WaitForSingleObject(self.done.?, self.milliseconds) == 0) return 0;
            while (true) {
                _ = CancelSynchronousIo(self.target.?);
                if (WaitForSingleObject(self.done.?, 10) == 0) return 0;
            }
        }

        fn stop(self: *Watch) void {
            if (self.thread) |thread| {
                _ = SetEvent(self.done.?);
                _ = WaitForSingleObject(thread, infinite);
                _ = CloseHandle(thread);
            }
            if (self.done) |done| _ = CloseHandle(done);
            if (self.target) |target| _ = CloseHandle(target);
            self.* = .{};
        }
    };

    /// A pipe nobody reads: the write blocks once its buffer is full, and the watch
    /// cancels it after its time.
    fn testWatch() !void {
        const inherit = SecurityAttributes{};
        var reader: ?Handle = null;
        var writer: ?Handle = null;
        if (CreatePipe(&reader, &writer, &inherit, 4096) == 0) return error.SkipZigTest;
        defer _ = CloseHandle(reader.?);
        defer _ = CloseHandle(writer.?);
        const bytes = try std.testing.allocator.alloc(u8, 1 << 20);
        defer std.testing.allocator.free(bytes);
        @memset(bytes, 'x');
        var watch: Watch = .{};
        const before = GetTickCount64();
        try std.testing.expect(watch.start(200));
        defer watch.stop();
        var written: u32 = 0;
        try std.testing.expectEqual(@as(i32, 0), WriteFile(writer.?, bytes.ptr, @intCast(bytes.len), &written, null));
        const waited = GetTickCount64() - before;
        try std.testing.expect(waited >= 150 and waited < 5000);
    }

    fn readProgram(_: ?*anyopaque, buffer: []u8, wait: bool) forth.RuntimeError!usize {
        const handle = from_program orelse return error.HostFailed;
        var wanted: u32 = @intCast(@min(buffer.len, 1 << 20));
        // Waiting while automatic display looks for a display: only up to its time,
        // so a program that does not answer does not hold SHOW.
        const bounded = wait and budget.active();
        if (!wait or bounded) {
            var available: u32 = 0;
            while (true) {
                // Checked before each read too: a program that keeps sending other
                // messages must not hold the search past its time.
                if (bounded and budget.expired()) return error.HostFailed;
                if (PeekNamedPipe(handle, null, 0, null, &available, null) == 0) return error.HostFailed;
                if (available != 0 or !bounded) break;
                Sleep(1);
            }
            if (available == 0) return 0;
            wanted = @min(wanted, available);
        }
        var count: u32 = 0;
        if (ReadFile(handle, buffer.ptr, wanted, &count, null) == 0 or count == 0) return error.HostFailed;
        return count;
    }
};

const posix = struct {
    extern "c" fn fcntl(c_int, c_int, ...) c_int;
    extern "c" fn unlink([*:0]const u8) c_int;
    extern "c" fn getpid() c_int;
    extern "c" fn signal(c_int, usize) usize;
    extern "c" fn getenv([*:0]const u8) ?[*:0]const u8;
    extern "c" fn access([*:0]const u8, c_int) c_int;

    const sigpipe = 13;
    const ignore: usize = 1; // SIG_IGN
    const executable = 1; // X_OK

    fn waitReady(fd: c_int, events: i16, wait: bool) forth.RuntimeError!bool {
        while (true) {
            if (linux and budget.expired()) return error.HostFailed;
            var descriptors = [_]std.c.pollfd{.{ .fd = fd, .events = events, .revents = 0 }};
            const timeout: c_int = if (!wait) 0 else if (linux) budget.remaining() else -1;
            const result = std.c.poll(&descriptors, 1, timeout);
            if (result > 0) return true; // HUP/ERR proceed to read/write for EOF/error.
            if (result == 0) {
                if (!wait) return false;
                return error.HostFailed;
            }
            if (std.c._errno().* != @backingInt(std.c.E.INTR)) return error.HostFailed;
        }
    }
    var to_program: c_int = -1;
    var from_program: c_int = -1;
    /// The temporary file of the script, removed when the program stops; empty before.
    var script_name: [1024:0]u8 = @splat(0);

    /// Writes the script to a new file of the temporary directory, readable only by the
    /// user: it is created only when no file or link of the name is there, under a name
    /// that changes with each try.
    fn writeScript(text: []const u8) bool {
        const directory: []const u8 = if (getenv("TMPDIR")) |value| std.mem.span(value) else "/tmp";
        var time: std.c.timespec = undefined;
        _ = std.c.clock_gettime(std.c.CLOCK.REALTIME, &time);
        for (0..16) |attempt| {
            const tag = (@as(u64, @bitCast(@as(i64, time.nsec))) *% 0x9E37_79B9_7F4A_7C15) +% attempt;
            const name = std.fmt.bufPrint(script_name[0 .. script_name.len - 1], "{s}/sigma-tk-{d}-{x}.tcl", .{ std.mem.trimEnd(u8, directory, "/"), getpid(), tag }) catch return false;
            script_name[name.len] = 0;
            const file = std.c.open(&script_name, .{ .ACCMODE = .WRONLY, .CREAT = true, .EXCL = true, .NOFOLLOW = true, .CLOEXEC = true }, @as(std.c.mode_t, 0o600));
            if (file < 0) {
                script_name[0] = 0;
                if (std.c._errno().* == @backingInt(std.c.E.EXIST)) continue;
                return false;
            }
            var rest = text;
            var ok = true;
            while (rest.len != 0) {
                const written = std.c.write(file, rest.ptr, rest.len);
                if (written < 0 and std.c._errno().* == @backingInt(std.c.E.INTR)) continue;
                if (written <= 0) {
                    ok = false;
                    break;
                }
                rest = rest[@intCast(written)..];
            }
            if (std.c.close(file) != 0) ok = false;
            if (!ok) removeScript();
            return ok;
        }
        return false;
    }

    fn removeScript() void {
        if (script_name[0] != 0) _ = unlink(&script_name);
        script_name[0] = 0;
    }

    /// The wish that the system's Tk 8.5 is; macOS 27 kills it as it starts (a launch
    /// constraint), and it is the one the PATH usually finds first.
    const system_wish = "/usr/bin/wish";
    /// Where Homebrew (Apple silicon, then Intel) and MacPorts put wish, for when the
    /// PATH does not lead there, such as in a program started from the Finder.
    const mac_places = [_][]const u8{ "/opt/homebrew/bin/wish", "/usr/local/bin/wish", "/opt/local/bin/wish" };

    fn isExecutable(name: [*:0]const u8) bool {
        return access(name, executable) == 0;
    }

    /// The parts one after the other in `buffer`, ended by a zero; null when too long.
    fn join(buffer: *[512:0]u8, parts: []const []const u8) ?[:0]const u8 {
        var length: usize = 0;
        for (parts) |part| {
            if (part.len > buffer.len - length) return null;
            @memcpy(buffer[length..][0..part.len], part);
            length += part.len;
        }
        buffer[length] = 0;
        return buffer[0..length :0];
    }

    /// The wish to start on macOS: the first on the PATH other than the system's, else
    /// the first in mac_places, else wish (the system's, which then fails to start).
    /// The full name goes into `buffer`.
    fn macWish(path: []const u8, buffer: *[512:0]u8, exists: *const fn ([*:0]const u8) bool) [*:0]const u8 {
        var directories = std.mem.splitScalar(u8, path, ':');
        while (directories.next()) |directory| {
            // An empty entry is the current directory, which is not looked in for wish.
            if (directory.len == 0) continue;
            const name = join(buffer, &.{ std.mem.trimEnd(u8, directory, "/"), "/wish" }) orelse continue;
            if (std.mem.eql(u8, name, system_wish)) continue;
            if (exists(name.ptr)) return name.ptr;
        }
        for (mac_places) |place| {
            const name = join(buffer, &.{place}).?;
            if (exists(name.ptr)) return name.ptr;
        }
        return "wish";
    }

    fn startProgram(_: ?*anyopaque, program: []const u8, script: []const u8) forth.RuntimeError!void {
        if (linux and budget.expired()) return error.HostFailed;
        if (!stopProgram(null)) return error.HostFailed;
        if (linux and budget.expired()) return error.HostFailed;
        if (!writeScript(script)) return error.HostFailed;
        errdefer if (shared_id == 0) removeScript();
        var name_buffer: [512:0]u8 = undefined;
        const name: [*:0]const u8 = if (program.len != 0) blk: {
            if (program.len >= name_buffer.len) return error.HostFailed;
            @memcpy(name_buffer[0..program.len], program);
            name_buffer[program.len] = 0;
            break :blk &name_buffer;
        } else getenv("SIGMA_WISH") orelse if (builtin.os.tag == .macos)
            macWish(if (getenv("PATH")) |path| std.mem.span(path) else "", &name_buffer, isExecutable)
        else
            "wish";
        try launchShared(std.mem.span(name), std.mem.sliceTo(&script_name, 0));
        if (linux) {
            // Only the parent's ends are nonblocking; wish retains ordinary stdin/stdout.
            for ([_]c_int{ to_program, from_program }) |fd| {
                const flags = fcntl(fd, std.c.F.GETFL);
                const nonblock: c_int = @bitCast(@as(u32, @bitCast(std.c.O{ .NONBLOCK = true })));
                if (flags < 0 or fcntl(fd, std.c.F.SETFL, flags | nonblock) < 0) {
                    if (!stopProgram(null)) return error.HostFailed;
                    return error.HostFailed;
                }
            }
        }
    }

    fn writeProgram(_: ?*anyopaque, bytes: []const u8) forth.RuntimeError!void {
        if (to_program < 0) return error.HostFailed;
        // A write after the program ended gives an error, not the end of Sigma; only
        // while writing here, so that the commands SYSTEM runs keep SIGPIPE.
        const previous = signal(sigpipe, ignore);
        defer _ = signal(sigpipe, previous);
        var rest = bytes;
        while (rest.len != 0) {
            if (linux) _ = try waitReady(to_program, std.c.POLL.OUT, true);
            const written = std.c.write(to_program, rest.ptr, rest.len);
            if (written < 0) {
                if (std.c._errno().* == @backingInt(std.c.E.INTR) or (linux and std.c._errno().* == @backingInt(std.c.E.AGAIN))) continue;
                return error.HostFailed;
            }
            if (written == 0) return error.HostFailed;
            rest = rest[@intCast(written)..];
        }
    }

    fn readProgram(_: ?*anyopaque, buffer: []u8, wait: bool) forth.RuntimeError!usize {
        if (from_program < 0) return error.HostFailed;
        if (!linux and !wait) {
            var descriptor = [_]std.c.pollfd{.{ .fd = from_program, .events = std.c.POLL.IN, .revents = 0 }};
            if (std.c.poll(&descriptor, 1, 0) <= 0) return 0;
        }
        while (true) {
            if (linux and !try waitReady(from_program, std.c.POLL.IN, wait)) return 0;
            const count = std.c.read(from_program, buffer.ptr, buffer.len);
            if (count < 0) {
                if (std.c._errno().* == @backingInt(std.c.E.INTR)) continue;
                if (linux and std.c._errno().* == @backingInt(std.c.E.AGAIN)) {
                    if (!wait) return 0;
                    continue;
                }
            }
            // 0 is the end of the program's output.
            if (count <= 0) return error.HostFailed;
            return @intCast(count);
        }
    }
};

test "macOS: wish is the first on the PATH but the system's, else Homebrew's or MacPorts's" {
    const fake = struct {
        var present: []const []const u8 = &.{};
        fn exists(name: [*:0]const u8) bool {
            for (present) |file| if (std.mem.eql(u8, file, std.mem.span(name))) return true;
            return false;
        }
    };
    var buffer: [512:0]u8 = undefined;
    // The system's wish is passed over for one later on the PATH.
    fake.present = &.{ "/usr/bin/wish", "/opt/homebrew/bin/wish", "/Users/a/bin/wish" };
    try std.testing.expectEqualStrings("/Users/a/bin/wish", std.mem.span(posix.macWish("/usr/bin::/Users/a/bin/:/opt/homebrew/bin", &buffer, fake.exists)));
    // Not on the PATH: Homebrew's, then MacPorts's.
    try std.testing.expectEqualStrings("/opt/homebrew/bin/wish", std.mem.span(posix.macWish("/usr/bin:/bin", &buffer, fake.exists)));
    fake.present = &.{ "/usr/bin/wish", "/opt/local/bin/wish" };
    try std.testing.expectEqualStrings("/opt/local/bin/wish", std.mem.span(posix.macWish("", &buffer, fake.exists)));
    // None: plain wish, which the PATH then finds.
    fake.present = &.{"/usr/bin/wish"};
    try std.testing.expectEqualStrings("wish", std.mem.span(posix.macWish("/usr/bin", &buffer, fake.exists)));
}

test "a write the display search waits for is cancelled when its time runs out" {
    if (comptime builtin.os.tag == .windows) try windows.testWatch() else return error.SkipZigTest;
}

// The generic process configuration table is host-only; exercise its ownership
// invariants in the normal host test target before connecting native launchers.
test {
    _ = @import("host_process_spec.zig");
    _ = @import("host_process_native.zig");
}
