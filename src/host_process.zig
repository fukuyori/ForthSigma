//! The Tcl program of the TCL words (wish): started with the script the core gives,
//! written to a file in the temporary directory, and pipes to its standard input and
//! output. Windows uses CreateProcessW and anonymous pipes; Linux and macOS fork and
//! exec, finding the program on the PATH. The program is SIGMA_WISH when that is set,
//! else wish (on Windows, Git for Windows's when the PATH has none), unless
//! TCL-PROGRAM named one.

const std = @import("std");
const builtin = @import("builtin");
const forth = @import("forth.zig");

const is_windows = builtin.os.tag == .windows;

pub const start = if (is_windows) windows.startProgram else posix.startProgram;
pub const write = if (is_windows) windows.writeProgram else posix.writeProgram;
pub const read = if (is_windows) windows.readProgram else posix.readProgram;
pub const stop = if (is_windows) windows.stopProgram else posix.stopProgram;

const windows = struct {
    const Handle = *anyopaque;
    const SecurityAttributes = extern struct { length: u32 = @sizeOf(SecurityAttributes), descriptor: ?*anyopaque = null, inherit: i32 = 1 };
    const StartupInfo = extern struct {
        cb: u32 = @sizeOf(StartupInfo),
        reserved: ?[*:0]u16 = null,
        desktop: ?[*:0]u16 = null,
        title: ?[*:0]u16 = null,
        x: u32 = 0,
        y: u32 = 0,
        x_size: u32 = 0,
        y_size: u32 = 0,
        x_count_chars: u32 = 0,
        y_count_chars: u32 = 0,
        fill_attribute: u32 = 0,
        flags: u32 = 0,
        show_window: u16 = 0,
        reserved2_size: u16 = 0,
        reserved2: ?*u8 = null,
        std_input: ?Handle = null,
        std_output: ?Handle = null,
        std_error: ?Handle = null,
    };
    const ProcessInformation = extern struct { process: ?Handle, thread: ?Handle, process_id: u32, thread_id: u32 };

    extern "kernel32" fn CreatePipe(*?Handle, *?Handle, *const SecurityAttributes, u32) callconv(.winapi) i32;
    extern "kernel32" fn SetHandleInformation(Handle, u32, u32) callconv(.winapi) i32;
    extern "kernel32" fn CreateProcessW(?[*:0]const u16, [*:0]u16, ?*anyopaque, ?*anyopaque, i32, u32, ?*anyopaque, ?[*:0]const u16, *StartupInfo, *ProcessInformation) callconv(.winapi) i32;
    extern "kernel32" fn CreateFileW([*:0]const u16, u32, u32, ?*const SecurityAttributes, u32, u32, ?Handle) callconv(.winapi) Handle;
    extern "kernel32" fn WriteFile(Handle, [*]const u8, u32, ?*u32, ?*anyopaque) callconv(.winapi) i32;
    extern "kernel32" fn ReadFile(Handle, [*]u8, u32, ?*u32, ?*anyopaque) callconv(.winapi) i32;
    extern "kernel32" fn PeekNamedPipe(Handle, ?*anyopaque, u32, ?*u32, ?*u32, ?*u32) callconv(.winapi) i32;
    extern "kernel32" fn CloseHandle(Handle) callconv(.winapi) i32;
    extern "kernel32" fn WaitForSingleObject(Handle, u32) callconv(.winapi) u32;
    extern "kernel32" fn TerminateProcess(Handle, u32) callconv(.winapi) i32;
    extern "kernel32" fn GetTempPathW(u32, [*]u16) callconv(.winapi) u32;
    extern "kernel32" fn GetCurrentProcessId() callconv(.winapi) u32;
    extern "kernel32" fn DeleteFileW([*:0]const u16) callconv(.winapi) i32;
    extern "kernel32" fn GetEnvironmentVariableW([*:0]const u16, ?[*]u16, u32) callconv(.winapi) u32;
    extern "kernel32" fn GetLastError() callconv(.winapi) u32;
    extern "kernel32" fn GetTickCount64() callconv(.winapi) u64;
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

    var process: ?Handle = null;
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

    /// The program: TCL-PROGRAM's, SIGMA_WISH, wish on the PATH, or Git for Windows's
    /// wish; wish (which then fails to start) when none is found. In UTF-16.
    fn programName(program: []const u8, buffer: []u16) ?[]const u16 {
        if (program.len != 0) {
            const length = std.unicode.utf8ToUtf16Le(buffer, program) catch return null;
            return buffer[0..length];
        }
        const variable = std.unicode.utf8ToUtf16LeStringLiteral("SIGMA_WISH");
        const length = GetEnvironmentVariableW(variable, buffer.ptr, @intCast(buffer.len));
        if (length != 0 and length < buffer.len) return buffer[0..length];
        const default = std.unicode.utf8ToUtf16LeStringLiteral("wish");
        var found: [512]u16 = undefined;
        const on_path = SearchPathW(null, default, std.unicode.utf8ToUtf16LeStringLiteral(".exe"), found.len, &found, null);
        if (on_path == 0 or on_path >= found.len) {
            for (git_places) |place| {
                const base = GetEnvironmentVariableW(place.variable, buffer.ptr, @intCast(buffer.len));
                if (base == 0 or base + place.path.len + 1 > buffer.len) continue;
                @memcpy(buffer[base..][0..place.path.len], place.path);
                buffer[base + place.path.len] = 0;
                if (isFile(@ptrCast(buffer.ptr))) return buffer[0 .. base + place.path.len];
            }
        }
        @memcpy(buffer[0..default.len], default);
        return buffer[0..default.len];
    }

    fn startProgram(_: ?*anyopaque, program: []const u8, script: []const u8) forth.RuntimeError!void {
        _ = stopProgram(null);
        if (!writeScript(script)) return error.HostFailed;
        errdefer removeScript();
        var name_buffer: [512]u16 = undefined;
        const name = programName(program, &name_buffer) orelse return error.HostFailed;
        // "program" "script"
        var command: [1600:0]u16 = undefined;
        var at: usize = 0;
        const script_length = std.mem.indexOfScalar(u16, &script_name, 0).?;
        if (name.len + script_length + 6 > command.len) return error.HostFailed;
        for ([_][]const u16{ name, script_name[0..script_length] }) |part| {
            command[at] = '"';
            @memcpy(command[at + 1 ..][0..part.len], part);
            command[at + 1 + part.len] = '"';
            command[at + 2 + part.len] = ' ';
            at += part.len + 3;
        }
        command[at - 1] = 0;
        const inherit = SecurityAttributes{};
        var child_input: ?Handle = null;
        var child_output: ?Handle = null;
        var input_writer: ?Handle = null;
        var output_reader: ?Handle = null;
        if (CreatePipe(&child_input, &input_writer, &inherit, 0) == 0) return error.HostFailed;
        if (CreatePipe(&output_reader, &child_output, &inherit, 0) == 0) {
            _ = CloseHandle(child_input.?);
            _ = CloseHandle(input_writer.?);
            return error.HostFailed;
        }
        // Sigma's own ends are not inherited: else the program would hold its own input
        // open, and never see it end.
        if (SetHandleInformation(input_writer.?, handle_flag_inherit, 0) == 0 or SetHandleInformation(output_reader.?, handle_flag_inherit, 0) == 0) {
            for ([_]?Handle{ child_input, input_writer, output_reader, child_output }) |handle| _ = CloseHandle(handle.?);
            return error.HostFailed;
        }
        // What the program writes to standard error goes nowhere, not into the messages.
        const nul = CreateFileW(std.unicode.utf8ToUtf16LeStringLiteral("NUL"), generic_write, 3, &inherit, open_existing, 0, null);
        var startup = StartupInfo{ .flags = use_std_handles, .std_input = child_input, .std_output = child_output, .std_error = if (@intFromPtr(nul) == invalid_handle) null else nul };
        var information: ProcessInformation = undefined;
        const created = CreateProcessW(null, &command, null, null, 1, no_window, null, null, &startup, &information);
        _ = CloseHandle(child_input.?);
        _ = CloseHandle(child_output.?);
        if (@intFromPtr(nul) != invalid_handle) _ = CloseHandle(nul);
        if (created == 0) {
            _ = CloseHandle(input_writer.?);
            _ = CloseHandle(output_reader.?);
            return error.HostFailed;
        }
        _ = CloseHandle(information.thread.?);
        process = information.process;
        to_program = input_writer;
        from_program = output_reader;
    }

    fn writeProgram(_: ?*anyopaque, bytes: []const u8) forth.RuntimeError!void {
        const handle = to_program orelse return error.HostFailed;
        var rest = bytes;
        while (rest.len != 0) {
            var written: u32 = 0;
            const amount: u32 = @intCast(@min(rest.len, 1 << 20));
            if (WriteFile(handle, rest.ptr, amount, &written, null) == 0 or written == 0) return error.HostFailed;
            rest = rest[written..];
        }
    }

    fn readProgram(_: ?*anyopaque, buffer: []u8, wait: bool) forth.RuntimeError!usize {
        const handle = from_program orelse return error.HostFailed;
        var wanted: u32 = @intCast(@min(buffer.len, 1 << 20));
        if (!wait) {
            var available: u32 = 0;
            if (PeekNamedPipe(handle, null, 0, null, &available, null) == 0) return error.HostFailed;
            if (available == 0) return 0;
            wanted = @min(wanted, available);
        }
        var count: u32 = 0;
        if (ReadFile(handle, buffer.ptr, wanted, &count, null) == 0 or count == 0) return error.HostFailed;
        return count;
    }

    /// Returns whether the program was seen to end.
    fn stopProgram(_: ?*anyopaque) bool {
        // Closing its standard input ends the program's script; it is ended if it
        // goes on for 2 seconds. Its output is closed too, so that it does not wait
        // to write what Sigma will not read.
        if (to_program) |handle| _ = CloseHandle(handle);
        to_program = null;
        if (from_program) |handle| _ = CloseHandle(handle);
        from_program = null;
        var stopped = true;
        if (process) |handle| {
            if (WaitForSingleObject(handle, 2000) != 0) {
                // TerminateProcess fails when the program has just ended, too.
                if (TerminateProcess(handle, 1) == 0) {
                    stopped = WaitForSingleObject(handle, 0) == 0;
                } else {
                    stopped = WaitForSingleObject(handle, 5000) == 0;
                }
            }
            _ = CloseHandle(handle);
        }
        process = null;
        removeScript();
        return stopped;
    }
};

const posix = struct {
    extern "c" fn fork() c_int;
    extern "c" fn execvp([*:0]const u8, [*:null]const ?[*:0]const u8) c_int;
    extern "c" fn _exit(c_int) noreturn;
    extern "c" fn dup2(c_int, c_int) c_int;
    extern "c" fn fcntl(c_int, c_int, ...) c_int;
    extern "c" fn pipe(*[2]c_int) c_int;
    extern "c" fn waitpid(c_int, ?*c_int, c_int) c_int;
    extern "c" fn kill(c_int, c_int) c_int;
    extern "c" fn unlink([*:0]const u8) c_int;
    extern "c" fn getpid() c_int;
    extern "c" fn signal(c_int, usize) usize;
    extern "c" fn getenv([*:0]const u8) ?[*:0]const u8;

    const sigpipe = 13;
    const sigkill = 9;
    const sigterm = 15;
    const ignore: usize = 1; // SIG_IGN
    const no_hang = 1; // WNOHANG
    const duplicate_from = 0; // F_DUPFD

    var child: c_int = 0;
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
                if (std.c._errno().* == @intFromEnum(std.c.E.EXIST)) continue;
                return false;
            }
            var rest = text;
            var ok = true;
            while (rest.len != 0) {
                const written = std.c.write(file, rest.ptr, rest.len);
                if (written < 0 and std.c._errno().* == @intFromEnum(std.c.E.INTR)) continue;
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

    /// A descriptor numbered 3 or more for the same file, so that putting the pipes at
    /// 0 and 1 cannot close one of them (when Sigma started with 0 or 1 closed, a pipe
    /// may have one of those numbers).
    fn aboveStandard(descriptor: c_int) c_int {
        return if (descriptor > 2) descriptor else fcntl(descriptor, duplicate_from, @as(c_int, 3));
    }

    fn startProgram(_: ?*anyopaque, program: []const u8, script: []const u8) forth.RuntimeError!void {
        _ = stopProgram(null);
        if (!writeScript(script)) return error.HostFailed;
        errdefer removeScript();
        var name_buffer: [512:0]u8 = undefined;
        const name: [*:0]const u8 = if (program.len != 0) blk: {
            if (program.len >= name_buffer.len) return error.HostFailed;
            @memcpy(name_buffer[0..program.len], program);
            name_buffer[program.len] = 0;
            break :blk &name_buffer;
        } else getenv("SIGMA_WISH") orelse "wish";
        var input: [2]c_int = undefined;
        var output: [2]c_int = undefined;
        if (pipe(&input) != 0) return error.HostFailed;
        if (pipe(&output) != 0) {
            _ = std.c.close(input[0]);
            _ = std.c.close(input[1]);
            return error.HostFailed;
        }
        const pid = fork();
        if (pid < 0) {
            for ([_]c_int{ input[0], input[1], output[0], output[1] }) |descriptor| _ = std.c.close(descriptor);
            return error.HostFailed;
        }
        if (pid == 0) {
            const reading = aboveStandard(input[0]);
            const writing = aboveStandard(output[1]);
            if (reading < 0 or writing < 0 or dup2(reading, 0) < 0 or dup2(writing, 1) < 0) _exit(126);
            for ([_]c_int{ input[0], input[1], output[0], output[1], reading, writing }) |descriptor| {
                // 0 and 1 are the pipes now; 2 is closed only if it was a pipe's end.
                if (descriptor > 2) _ = std.c.close(descriptor);
                if (descriptor == 2) _ = std.c.close(2);
            }
            const arguments = [_:null]?[*:0]const u8{ name, &script_name };
            _ = execvp(name, &arguments);
            _exit(127);
        }
        _ = std.c.close(input[0]);
        _ = std.c.close(output[1]);
        child = pid;
        to_program = input[1];
        from_program = output[0];
    }

    fn writeProgram(_: ?*anyopaque, bytes: []const u8) forth.RuntimeError!void {
        if (to_program < 0) return error.HostFailed;
        // A write after the program ended gives an error, not the end of Sigma; only
        // while writing here, so that the commands SYSTEM runs keep SIGPIPE.
        const previous = signal(sigpipe, ignore);
        defer _ = signal(sigpipe, previous);
        var rest = bytes;
        while (rest.len != 0) {
            const written = std.c.write(to_program, rest.ptr, rest.len);
            if (written < 0) {
                if (std.c._errno().* == @intFromEnum(std.c.E.INTR)) continue;
                return error.HostFailed;
            }
            if (written == 0) return error.HostFailed;
            rest = rest[@intCast(written)..];
        }
    }

    fn readProgram(_: ?*anyopaque, buffer: []u8, wait: bool) forth.RuntimeError!usize {
        if (from_program < 0) return error.HostFailed;
        if (!wait) {
            var descriptor = [_]std.c.pollfd{.{ .fd = from_program, .events = std.c.POLL.IN, .revents = 0 }};
            if (std.c.poll(&descriptor, 1, 0) <= 0) return 0;
        }
        while (true) {
            const count = std.c.read(from_program, buffer.ptr, buffer.len);
            if (count < 0 and std.c._errno().* == @intFromEnum(std.c.E.INTR)) continue;
            // 0 is the end of the program's output.
            if (count <= 0) return error.HostFailed;
            return @intCast(count);
        }
    }

    /// Waits up to `steps` times 10 ms for the program to end; whether it did.
    fn ended(steps: u32) bool {
        for (0..steps) |_| {
            const result = waitpid(child, null, no_hang);
            if (result == child) return true;
            if (result < 0 and std.c._errno().* != @intFromEnum(std.c.E.INTR)) return true;
            var pause: std.c.timespec = .{ .sec = 0, .nsec = 10 * std.time.ns_per_ms };
            _ = std.c.nanosleep(&pause, null);
        }
        return false;
    }

    /// Returns whether the program was seen to end.
    fn stopProgram(_: ?*anyopaque) bool {
        // Its output is closed too, so that it does not wait to write what Sigma will
        // not read.
        if (to_program >= 0) _ = std.c.close(to_program);
        to_program = -1;
        if (from_program >= 0) _ = std.c.close(from_program);
        from_program = -1;
        if (child > 0) {
            // The program ends when its input closes; after 2 s it is asked to end, and
            // after 1 s more it is ended.
            if (!ended(200)) {
                _ = kill(child, sigterm);
                if (!ended(100)) {
                    _ = kill(child, sigkill);
                    while (waitpid(child, null, 0) < 0 and std.c._errno().* == @intFromEnum(std.c.E.INTR)) {}
                }
            }
        }
        child = 0;
        removeScript();
        return true;
    }
};
