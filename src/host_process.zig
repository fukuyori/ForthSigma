//! The Tcl program of the TCL words (wish): started with the script the core gives,
//! written to a file in the temporary directory, and pipes to its standard input and
//! output. Windows uses CreateProcessW and anonymous pipes; Linux and macOS fork and
//! exec, finding the program on the PATH. The program is SIGMA_WISH when that is set,
//! else wish, unless TCL-PROGRAM named one.

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

    const invalid_handle: usize = std.math.maxInt(usize);
    const handle_flag_inherit: u32 = 1;
    const use_std_handles: u32 = 0x100;
    const generic_read: u32 = 0x8000_0000;
    const generic_write: u32 = 0x4000_0000;
    const create_always: u32 = 2;
    const open_existing: u32 = 3;
    const no_window: u32 = 0x0800_0000;

    var process: ?Handle = null;
    var to_program: ?Handle = null;
    var from_program: ?Handle = null;
    /// The temporary file of the script, removed when the program stops; empty before.
    var script_name: [1024:0]u16 = @splat(0);

    fn writeScript(text: []const u8) bool {
        var directory: [512]u16 = undefined;
        const length = GetTempPathW(directory.len, &directory);
        if (length == 0 or length >= directory.len) return false;
        var name_buffer: [64]u8 = undefined;
        const name = std.fmt.bufPrint(&name_buffer, "sigma-tk-{d}.tcl", .{GetCurrentProcessId()}) catch return false;
        @memcpy(script_name[0..length], directory[0..length]);
        for (name, 0..) |byte, index| script_name[length + index] = byte;
        script_name[length + name.len] = 0;
        const file = CreateFileW(&script_name, generic_write, 0, null, create_always, 0, null);
        if (@intFromPtr(file) == invalid_handle) return false;
        defer _ = CloseHandle(file);
        var written: u32 = 0;
        return WriteFile(file, text.ptr, @intCast(text.len), &written, null) != 0 and written == text.len;
    }

    /// The program: TCL-PROGRAM's, SIGMA_WISH, or wish, in UTF-16.
    fn programName(program: []const u8, buffer: []u16) ?[]const u16 {
        if (program.len != 0) {
            const length = std.unicode.utf8ToUtf16Le(buffer, program) catch return null;
            return buffer[0..length];
        }
        const variable = std.unicode.utf8ToUtf16LeStringLiteral("SIGMA_WISH");
        const length = GetEnvironmentVariableW(variable, buffer.ptr, @intCast(buffer.len));
        if (length != 0 and length < buffer.len) return buffer[0..length];
        const default = std.unicode.utf8ToUtf16LeStringLiteral("wish");
        @memcpy(buffer[0..default.len], default);
        return buffer[0..default.len];
    }

    fn startProgram(_: ?*anyopaque, program: []const u8, script: []const u8) forth.RuntimeError!void {
        stopProgram(null);
        if (!writeScript(script)) return error.HostFailed;
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
        // Sigma's own ends are not inherited.
        _ = SetHandleInformation(input_writer.?, handle_flag_inherit, 0);
        _ = SetHandleInformation(output_reader.?, handle_flag_inherit, 0);
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
            _ = DeleteFileW(&script_name);
            script_name[0] = 0;
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

    fn stopProgram(_: ?*anyopaque) void {
        // Closing its standard input ends the program's script; it is ended if it
        // goes on for 2 seconds.
        if (to_program) |handle| _ = CloseHandle(handle);
        to_program = null;
        if (process) |handle| {
            if (WaitForSingleObject(handle, 2000) != 0) _ = TerminateProcess(handle, 1);
            _ = CloseHandle(handle);
        }
        process = null;
        if (from_program) |handle| _ = CloseHandle(handle);
        from_program = null;
        if (script_name[0] != 0) _ = DeleteFileW(&script_name);
        script_name[0] = 0;
    }
};

const posix = struct {
    extern "c" fn fork() c_int;
    extern "c" fn execvp([*:0]const u8, [*:null]const ?[*:0]const u8) c_int;
    extern "c" fn _exit(c_int) noreturn;
    extern "c" fn dup2(c_int, c_int) c_int;
    extern "c" fn pipe(*[2]c_int) c_int;
    extern "c" fn waitpid(c_int, ?*c_int, c_int) c_int;
    extern "c" fn kill(c_int, c_int) c_int;
    extern "c" fn unlink([*:0]const u8) c_int;
    extern "c" fn getpid() c_int;
    extern "c" fn signal(c_int, usize) usize;
    extern "c" fn getenv([*:0]const u8) ?[*:0]const u8;
    extern "c" fn fopen([*:0]const u8, [*:0]const u8) ?*anyopaque;
    extern "c" fn fwrite([*]const u8, usize, usize, ?*anyopaque) usize;
    extern "c" fn fclose(?*anyopaque) c_int;

    const sigpipe = 13;
    const sigterm = 15;
    const ignore: usize = 1; // SIG_IGN
    const no_hang = 1; // WNOHANG

    var child: c_int = 0;
    var to_program: c_int = -1;
    var from_program: c_int = -1;
    /// The temporary file of the script, removed when the program stops; empty before.
    var script_name: [1024:0]u8 = @splat(0);

    fn writeScript(text: []const u8) bool {
        const directory: []const u8 = if (getenv("TMPDIR")) |value| std.mem.span(value) else "/tmp";
        const name = std.fmt.bufPrint(script_name[0 .. script_name.len - 1], "{s}/sigma-tk-{d}.tcl", .{ std.mem.trimEnd(u8, directory, "/"), getpid() }) catch return false;
        script_name[name.len] = 0;
        const file = fopen(&script_name, "wb") orelse return false;
        const written = fwrite(text.ptr, 1, text.len, file);
        return fclose(file) == 0 and written == text.len;
    }

    fn startProgram(_: ?*anyopaque, program: []const u8, script: []const u8) forth.RuntimeError!void {
        stopProgram(null);
        if (!writeScript(script)) return error.HostFailed;
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
        // A write after the program ended gives an error, not the end of Sigma.
        _ = signal(sigpipe, ignore);
        const pid = fork();
        if (pid < 0) {
            for ([_]c_int{ input[0], input[1], output[0], output[1] }) |descriptor| _ = std.c.close(descriptor);
            return error.HostFailed;
        }
        if (pid == 0) {
            _ = dup2(input[0], 0);
            _ = dup2(output[1], 1);
            for ([_]c_int{ input[0], input[1], output[0], output[1] }) |descriptor| _ = std.c.close(descriptor);
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

    fn stopProgram(_: ?*anyopaque) void {
        if (to_program >= 0) _ = std.c.close(to_program);
        to_program = -1;
        if (child > 0) {
            // The program ends when its input closes; it is ended if it goes on for 2 s.
            var waited: u32 = 0;
            while (waitpid(child, null, no_hang) == 0) : (waited += 1) {
                if (waited == 200) {
                    _ = kill(child, sigterm);
                    _ = waitpid(child, null, 0);
                    break;
                }
                var pause: std.c.timespec = .{ .sec = 0, .nsec = 10 * std.time.ns_per_ms };
                _ = std.c.nanosleep(&pause, null);
            }
        }
        child = 0;
        if (from_program >= 0) _ = std.c.close(from_program);
        from_program = -1;
        if (script_name[0] != 0) _ = unlink(&script_name);
        script_name[0] = 0;
    }
};
