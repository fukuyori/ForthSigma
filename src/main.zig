const std = @import("std");
const builtin = @import("builtin");
const forth = @import("forth.zig");
const host_runtime = @import("host_runtime.zig");

extern "c" fn getchar() c_int;
extern "c" fn ttyname(c_int) ?[*:0]const u8;
extern "c" fn putchar(c_int) c_int;
extern "c" fn fflush(?*anyopaque) c_int;
extern "c" fn fclose(?*anyopaque) c_int;
extern "c" fn fseek(?*anyopaque, c_long, c_int) c_int;
extern "c" fn ftell(?*anyopaque) c_long;
extern "c" fn fread([*]u8, usize, usize, ?*anyopaque) usize;
extern "c" fn fwrite([*]const u8, usize, usize, ?*anyopaque) usize;
extern "c" fn getc(?*anyopaque) c_int;
extern "c" fn ungetc(c_int, ?*anyopaque) c_int;
extern "c" fn ferror(?*anyopaque) c_int;
extern "c" fn sigma_file_is_pipe(c_int) c_int;
extern "c" fn sigma_write_stdout([*]const u8, usize, *usize, *c_ulong) c_int;
extern "c" fn feof(?*anyopaque) c_int;
extern "c" fn setvbuf(?*anyopaque, ?[*]u8, c_int, usize) c_int;
extern "c" fn fcntl(c_int, c_int, ...) c_int;
extern "c" fn _get_osfhandle(c_int) isize;
extern "c" fn clearerr(?*anyopaque) void;
extern "c" fn rename([*:0]const u8, [*:0]const u8) c_int;

/// The C library's functions that take a file name or a command. On Windows they would
/// take it in the ANSI code page (932 on a Japanese system), where UTF-8 names other
/// than ASCII fail; there the UTF-8 is turned into UTF-16 for their wide forms.
const libc = struct {
    extern "c" fn exit(c_int) noreturn;
    extern "c" fn fopen([*:0]const u8, [*:0]const u8) ?*anyopaque;
    extern "c" fn remove([*:0]const u8) c_int;
    extern "c" fn system(?[*:0]const u8) c_int;
    extern "c" fn popen([*:0]const u8, [*:0]const u8) ?*anyopaque;
    extern "c" fn pclose(?*anyopaque) c_int;
};

const wide_c = struct {
    extern "c" fn _wfopen([*:0]const u16, [*:0]const u16) ?*anyopaque;
    extern "c" fn _wremove([*:0]const u16) c_int;
    extern "c" fn _wsystem(?[*:0]const u16) c_int;
    extern "c" fn _wpopen([*:0]const u16, [*:0]const u16) ?*anyopaque;
    extern "c" fn _pclose(?*anyopaque) c_int;
    extern "kernel32" fn MoveFileExW([*:0]const u16, [*:0]const u16, u32) callconv(.winapi) c_int;
    const errno_illegal_sequence = 42;
    const errno_name_too_long = 38;

    /// The UTF-16 form of UTF-8 text, in `buffer`; null, with errno set, when the text is
    /// not UTF-8 or does not fit.
    fn from(text: [*:0]const u8, buffer: []u16) ?[*:0]const u16 {
        const bytes = std.mem.span(text);
        if (bytes.len >= buffer.len) {
            std.c._errno().* = errno_name_too_long;
            return null;
        }
        const length = std.unicode.utf8ToUtf16Le(buffer[0 .. buffer.len - 1], bytes) catch {
            std.c._errno().* = errno_illegal_sequence;
            return null;
        };
        buffer[length] = 0;
        return @ptrCast(buffer[0..length :0]);
    }
};

fn fopen(name: [*:0]const u8, mode: [*:0]const u8) ?*anyopaque {
    if (builtin.os.tag != .windows) return libc.fopen(name, mode);
    var name_buffer: [8192]u16 = undefined;
    var mode_buffer: [8]u16 = undefined;
    return wide_c._wfopen(wide_c.from(name, &name_buffer) orelse return null, wide_c.from(mode, &mode_buffer) orelse return null);
}

fn remove(name: [*:0]const u8) c_int {
    if (builtin.os.tag != .windows) return libc.remove(name);
    var buffer: [8192]u16 = undefined;
    return wide_c._wremove(wide_c.from(name, &buffer) orelse return -1);
}

fn system(command: [*:0]const u8) c_int {
    if (builtin.os.tag != .windows) return libc.system(command);
    var buffer: [8192]u16 = undefined;
    return wide_c._wsystem(wide_c.from(command, &buffer) orelse return -1);
}
/// Changing a file's size goes through its descriptor: _chsize_s on Windows, ftruncate
/// elsewhere (64-bit off_t on musl and macOS).
const file_number = if (builtin.os.tag == .windows) struct {
    extern "c" fn _fileno(?*anyopaque) c_int;
}._fileno else struct {
    extern "c" fn fileno(?*anyopaque) c_int;
}.fileno;
const resizeDescriptor = if (builtin.os.tag == .windows) struct {
    extern "c" fn _chsize_s(c_int, i64) c_int;
    fn call(descriptor: c_int, size: i64) c_int {
        return _chsize_s(descriptor, size);
    }
}.call else struct {
    extern "c" fn ftruncate(c_int, i64) c_int;
    fn call(descriptor: c_int, size: i64) c_int {
        return ftruncate(descriptor, size);
    }
}.call;
/// 64-bit file positions: `fseek`/`ftell` take a 32-bit `long` on Windows.
const seek64 = if (builtin.os.tag == .windows) struct {
    extern "c" fn _fseeki64(?*anyopaque, i64, c_int) c_int;
}._fseeki64 else struct {
    extern "c" fn fseeko(?*anyopaque, i64, c_int) c_int;
}.fseeko;
const tell64 = if (builtin.os.tag == .windows) struct {
    extern "c" fn _ftelli64(?*anyopaque) i64;
}._ftelli64 else struct {
    extern "c" fn ftello(?*anyopaque) i64;
}.ftello;
/// The Windows C library opens standard input in text mode, which turns CR LF into LF
/// and stops at Ctrl+Z.
const windows_stdin = struct {
    extern "c" fn _setmode(c_int, c_int) c_int;
    extern "c" fn _isatty(c_int) c_int;
    const binary_mode = 0x8000;
};
extern "kernel32" fn GetStdHandle(u32) callconv(.winapi) ?*anyopaque;
extern "kernel32" fn WriteFile(*anyopaque, [*]const u8, u32, ?*u32, ?*anyopaque) callconv(.winapi) c_int;
extern "kernel32" fn ReadFile(*anyopaque, [*]u8, u32, *u32, ?*anyopaque) callconv(.winapi) c_int;
extern "kernel32" fn PeekNamedPipe(*anyopaque, ?*anyopaque, u32, ?*u32, *u32, ?*u32) callconv(.winapi) c_int;
extern "kernel32" fn GetFileType(*anyopaque) callconv(.winapi) u32;
extern "kernel32" fn GetTickCount64() callconv(.winapi) u64;
extern "kernel32" fn Sleep(u32) callconv(.winapi) void;
extern "kernel32" fn GetSystemTimePreciseAsFileTime(*u64) callconv(.winapi) void;
extern "kernel32" fn GetCurrentProcess() callconv(.winapi) *anyopaque;
extern "kernel32" fn GetProcessTimes(*anyopaque, *u64, *u64, *u64, *u64) callconv(.winapi) c_int;
extern "kernel32" fn GetConsoleMode(*anyopaque, *u32) callconv(.winapi) c_int;
extern "kernel32" fn SetConsoleMode(*anyopaque, u32) callconv(.winapi) c_int;
extern "kernel32" fn GetConsoleScreenBufferInfo(*anyopaque, *ConsoleScreenBufferInfo) callconv(.winapi) c_int;
extern "kernel32" fn GetConsoleOutputCP() callconv(.winapi) u32;
extern "kernel32" fn SetConsoleOutputCP(u32) callconv(.winapi) c_int;
const ConsoleScreenBufferInfo = extern struct { size: [2]i16, cursor: [2]i16, attributes: u16, window: [4]i16, maximum_size: [2]i16 };
const posix_ioctl = struct {
    extern "c" fn ioctl(c_int, c_int, ...) c_int;
};
const host_window = @import("host_window.zig");
const host_gamepad = @import("host_gamepad.zig");
const host_display = @import("host_display.zig");
const host_input = @import("host_input.zig");
const host_line = @import("host_line.zig");
const host_font = @import("host_font.zig");
const host_process = @import("host_process.zig");
const host_audio = @import("host_audio.zig");
/// Whether the build has the audio words and their thread.
const audio = @import("build_options").audio;
/// Whether the build has the graphics words: a build without them leaves out the fonts.
const graphics = @import("build_options").graphics;
comptime {
    if (graphics) _ = host_gamepad;
}

const image_footer_size = 20;
const image_footer_magic = "SIGEND01";
/// The host keeps away from std.Io: a main that takes std.process.Init sets up std.Io's
/// threaded implementation, whose table of functions links in every file, network, and
/// process operation of the standard library (about 450 KB on Windows). Sigma does its
/// file work through the C library, and the few calls below go to the system directly.
/// `framebuffer` is the graphics image that GFX-INIT got last, and `fonts` the buffers of
/// the BDF fonts LOAD-FONT reads (the font in use, and one being read); all are freed
/// when Sigma ends.
const HostContext = struct { allocator: std.mem.Allocator, executable_path: [:0]const u8, environ_map: *std.process.Environ.Map, runtime: ?*host_runtime.Runtime = null, framebuffer: []u32 = &.{}, fonts: [2][]u64 = .{ &.{}, &.{} } };

fn hostContext(context: ?*anyopaque) forth.RuntimeError!*HostContext {
    return @ptrCast(@alignCast(context orelse return error.HostUnavailable));
}

/// The size of the terminal on standard output, for SHOW; null when it is not one.
fn terminalSize(_: ?*anyopaque) ?forth.TerminalSize {
    if (!output_is_terminal) return null;
    if (builtin.os.tag == .windows) {
        const std_output_handle: u32 = @bitCast(@as(i32, -11));
        const handle = GetStdHandle(std_output_handle) orelse return null;
        var info: ConsoleScreenBufferInfo = undefined;
        if (GetConsoleScreenBufferInfo(handle, &info) == 0) return null;
        const columns = @as(i32, info.window[2]) - info.window[0] + 1;
        const rows = @as(i32, info.window[3]) - info.window[1] + 1;
        if (columns < 1 or rows < 1) return null;
        return .{ .columns = @intCast(columns), .rows = @intCast(rows) };
    }
    var size: std.posix.winsize = undefined;
    if (posix_ioctl.ioctl(1, @intCast(std.c.T.IOCGWINSZ), &size) != 0) return null;
    return .{ .columns = size.col, .rows = size.row, .x_pixels = size.xpixel, .y_pixels = size.ypixel };
}

/// The code page the console had before SHOW switched it to UTF-8.
var saved_output_code_page: u32 = 0;

/// SHOW writes UTF-8 half blocks: a Windows console shows them only with the UTF-8
/// code page, which is set for that output and then put back. While the whole session
/// uses UTF-8 (see `utf8_console`), there is nothing to switch.
fn terminalUtf8(_: ?*anyopaque, begin: bool) void {
    if (builtin.os.tag != .windows or !output_is_terminal or utf8_console.active) return;
    flushOutput();
    if (begin) {
        saved_output_code_page = GetConsoleOutputCP();
        _ = SetConsoleOutputCP(65001);
    } else if (saved_output_code_page != 0) {
        _ = SetConsoleOutputCP(saved_output_code_page);
        saved_output_code_page = 0;
    }
}

/// GFX-INIT's image: a new buffer, replacing the previous one only when it is allocated.
fn graphicsBuffer(context: ?*anyopaque, pixels: usize) ?[]u32 {
    const host = hostContext(context) catch return null;
    const buffer = host.allocator.alloc(u32, pixels) catch return null;
    if (host.framebuffer.len != 0) host.allocator.free(host.framebuffer);
    host.framebuffer = buffer;
    return buffer;
}

/// An image of the pool (NEW-IMAGE), kept until imageFree; the core frees what is left
/// when the program ends (graphics_images.releaseAll).
fn imageAlloc(context: ?*anyopaque, pixels: usize) ?[]u32 {
    const host = hostContext(context) catch return null;
    return host.allocator.alloc(u32, pixels) catch null;
}

fn imageFree(context: ?*anyopaque, pixels: []u32) void {
    const host = hostContext(context) catch return;
    host.allocator.free(pixels);
}

/// A buffer for a font LOAD-FONT reads, kept until fontFree.
fn fontBuffer(context: ?*anyopaque, words: usize) ?[]u64 {
    const host = hostContext(context) catch return null;
    for (&host.fonts) |*slot| {
        if (slot.len != 0) continue;
        slot.* = host.allocator.alloc(u64, words) catch return null;
        return slot.*;
    }
    return null;
}

fn fontFree(context: ?*anyopaque, buffer: []u64) void {
    const host = hostContext(context) catch return;
    for (&host.fonts) |*slot| {
        if (slot.ptr != buffer.ptr or slot.len == 0) continue;
        host.allocator.free(slot.*);
        slot.* = &.{};
    }
}

fn sleepMilliseconds(_: ?*anyopaque, milliseconds: forth.Cell) forth.RuntimeError!void {
    // What was written before the wait shows during it, as a progress display expects.
    flushOutput();
    if (milliseconds <= 0) return;
    if (builtin.os.tag == .windows) {
        // Sleep takes a u32, and its largest value means forever, so longer waits go in parts.
        var left: u64 = @intCast(milliseconds);
        while (left > 0) {
            const part: u32 = @intCast(@min(left, std.math.maxInt(u32) - 1));
            Sleep(part);
            left -= part;
        }
        return;
    }
    var request: std.c.timespec = .{ .sec = @intCast(@divTrunc(milliseconds, 1000)), .nsec = @intCast(@rem(milliseconds, 1000) * std.time.ns_per_ms) };
    var remaining: std.c.timespec = undefined;
    // A signal can end the wait early; it goes on with the time that is left.
    while (std.c.nanosleep(&request, &remaining) != 0) {
        if (std.c._errno().* != @backingInt(std.c.E.INTR)) return error.HostFailed;
        request = remaining;
    }
}

fn sleepNanoseconds(context: ?*anyopaque, nanoseconds: forth.Double) forth.RuntimeError!void {
    flushOutput();
    if (context) |value| {
        const host: *HostContext = @ptrCast(@alignCast(value));
        if (host.runtime) |runtime| return @import("host_wait.zig").waitWithRuntime(runtime, nanoseconds);
    }
    try @import("host_wait.zig").wait(nanoseconds);
}

/// Microseconds since 1970-01-01 00:00 UTC.
fn microsecondsSinceEpoch(_: ?*anyopaque) forth.RuntimeError!forth.Double {
    if (builtin.os.tag == .windows) {
        // A FILETIME counts 100 ns from 1601-01-01; 11644473600 seconds lie before 1970.
        var ticks: u64 = 0;
        GetSystemTimePreciseAsFileTime(&ticks);
        return @divFloor(@as(forth.Double, ticks) - 116_444_736_000_000_000, 10);
    }
    var now: std.c.timespec = undefined;
    if (std.c.clock_gettime(std.c.CLOCK.REALTIME, &now) != 0) return error.HostFailed;
    return @as(forth.Double, now.sec) * std.time.us_per_s + @divFloor(@as(forth.Double, now.nsec), std.time.ns_per_us);
}

/// Nanoseconds since the Unix epoch, at the host wall clock's actual resolution.
fn nanosecondsSinceEpoch(_: ?*anyopaque) forth.RuntimeError!forth.Double {
    if (builtin.os.tag == .windows) {
        var ticks: u64 = 0;
        GetSystemTimePreciseAsFileTime(&ticks);
        return (@as(forth.Double, ticks) - 116_444_736_000_000_000) * 100;
    }
    var now: std.c.timespec = undefined;
    if (std.c.clock_gettime(std.c.CLOCK.REALTIME, &now) != 0) return error.HostFailed;
    return @as(forth.Double, now.sec) * std.time.ns_per_s + @as(forth.Double, now.nsec);
}

fn processCpuTimes(_: ?*anyopaque) forth.RuntimeError!forth.CpuTimes {
    if (builtin.os.tag == .windows) {
        var creation: u64 = undefined;
        var exit: u64 = undefined;
        var kernel: u64 = undefined;
        var user: u64 = undefined;
        if (GetProcessTimes(GetCurrentProcess(), &creation, &exit, &kernel, &user) == 0) return error.HostFailed;
        return .{ .user = @divTrunc(@as(forth.Double, user), 10), .system = @divTrunc(@as(forth.Double, kernel), 10) };
    }
    var usage: c_time.struct_rusage = undefined;
    if (c_time.getrusage(c_time.RUSAGE_SELF, &usage) != 0) return error.HostFailed;
    return .{
        .user = @as(forth.Double, usage.ru_utime.tv_sec) * std.time.us_per_s + usage.ru_utime.tv_usec,
        .system = @as(forth.Double, usage.ru_stime.tv_sec) * std.time.us_per_s + usage.ru_stime.tv_usec,
    };
}

/// The C library's time.h, translated by build.zig (see addCTime).
const c_time = @import("c_time");

fn localTime(_: ?*anyopaque) forth.RuntimeError!forth.LocalTime {
    const now = c_time.time(null);
    const parts = c_time.localtime(&now) orelse return error.HostFailed;
    return .{ .second = parts.*.tm_sec, .minute = parts.*.tm_min, .hour = parts.*.tm_hour, .day = parts.*.tm_mday, .month = parts.*.tm_mon + 1, .year = parts.*.tm_year + 1900 };
}

fn environmentValue(context: ?*anyopaque, name: []const u8, buffer: []u8) forth.RuntimeError!?usize {
    const host = try hostContext(context);
    // Names the environment can never hold are reported as unset instead of tripping
    // the map's key assertions.
    if (name.len == 0 or std.mem.indexOfAny(u8, name, &.{ 0, '=' }) != null) return null;
    if (!std.process.Environ.Map.validateKeyForFetch(name)) return null;
    const value = host.environ_map.get(name) orelse return null;
    if (value.len > buffer.len) return error.StringTooLong;
    @memcpy(buffer[0..value.len], value);
    return value.len;
}

/// Editor execution shares SYSTEM's cooked-terminal handoff and output flush.
fn editSource(context: ?*anyopaque, request: @import("core/host_interface.zig").EditorRequest) forth.RuntimeError!void {
    const host = try hostContext(context);
    const editor = host.environ_map.get("EDITOR") orelse return error.HostUnavailable;
    try @import("host_editor.zig").run(request, editor, host.environ_map.get("TMPDIR"), context, runShellCommand);
}

/// Runs the command through the C library's `system`, which uses `cmd.exe /c` on
/// Windows and `/bin/sh -c` elsewhere.
fn runShellCommand(_: ?*anyopaque, command: []const u8) forth.RuntimeError!forth.Cell {
    try pauseStdinReader();
    var terminated: [4096:0]u8 = undefined;
    if (command.len >= terminated.len) return error.StringTooLong;
    // `system` would stop at an embedded NUL and run only the text before it.
    if (std.mem.indexOfScalar(u8, command, 0) != null) return error.HostFailed;
    @memcpy(terminated[0..command.len], command);
    terminated[command.len] = 0;
    // Give the shell its normal screen for the entire subprocess call.
    host_input.pausePresentation() catch return error.HostFailed;
    var presentation_paused = true;
    defer if (presentation_paused) {
        host_input.resumePresentation() catch |err| latchInput(if (err == error.HostUnavailable) error.HostUnavailable else error.HostFailed);
    };
    host_input.leave();
    // A child cmd.exe may change shared console input/output mode bits even
    // for a silent command. Restore the cooked modes before re-entering raw input.
    var console_handles: [2]?*anyopaque = .{ null, null };
    var console_modes: [2]u32 = .{ 0, 0 };
    if (builtin.os.tag == .windows) {
        for ([_]i32{ -10, -11 }, 0..) |which, index| {
            if (GetStdHandle(@bitCast(which))) |handle| {
                if (GetConsoleMode(handle, &console_modes[index]) != 0) console_handles[index] = handle;
            }
        }
    }
    // The command's output comes after what Forth wrote before it.
    try flushProcessOutput();
    // On POSIX systems this is the wait status, as gforth's $? gives; on Windows, the exit code.
    utf8_console.pause();
    const status = system(&terminated);
    var restored = true;
    if (builtin.os.tag == .windows) {
        for (console_handles, console_modes) |handle, mode| {
            if (handle) |console| if (SetConsoleMode(console, mode) == 0) {
                restored = false;
            };
        }
    }
    output_cursor.unknown();
    utf8_console.@"resume"();
    presentation_paused = false;
    host_input.resumePresentation() catch return error.HostFailed;
    if (status == -1 or !restored) return error.HostFailed;
    return status;
}

const max_open_files = 64;
const errno_io = 5;
const errno_too_many_files = 24;
const PipeSignalScope = @import("host_pipe_signal.zig").Scope;
// Semantic EOF is independent of temporary seek/peek operations on C streams.
const file_event = @import("core/standard_event.zig");
const file_reader = @import("host_file_reader.zig");
const io_types = @import("core/host_interface.zig");
const host_fs = @import("host_filesystem.zig");
var file_wake: ?@import("host_wake.zig").Wake = null;
var stdin_reader: file_reader.Reader = .{};
var stdout_writer: file_reader.Writer = .{};
var stderr_writer: file_reader.Writer = .{};
var output_ior: forth.Cell = 0;
var output_nonblocking = false;
var closing_all_files = false;
var deferred_packets: [256]file_event.Packet = undefined;
var deferred_head: usize = 0;
var deferred_length: usize = 0;
const FileSlot = struct {
    stream: ?*anyopaque = null,
    pipe: bool = false, // popen ownership; independent of the native handle type.
    native_pipe: bool = false,
    proc_owner: forth.Cell = 0,
    access: forth.FileAccess = .read_only,
    eof: bool = false,
    last_read: bool = false,
    input: file_event.Decoder = .{},
    reader: file_reader.Reader = .{},
    writer: file_reader.Writer = .{},
};
var file_slots: [max_open_files]FileSlot = @splat(.{});
var stdin_eof: bool = false;
// Fault seams only exist in test binaries; no OS behavior is changed in production.
var test_file_restore_failure: bool = false;
var test_file_commit_interrupt: bool = false;
var test_file_read_failure: bool = false;

fn resetFileInput(slot: usize) void {
    file_slots[slot].last_read = false;
    file_slots[slot].input = .{};
    file_slots[slot].eof = false;
}

fn fileSlot(fileid: forth.Cell) usize {
    return @intCast(fileid - forth.first_file_id);
}

fn currentErrno(_: ?*anyopaque) forth.Cell {
    return std.c._errno().*;
}

fn clearErrno() void {
    std.c._errno().* = 0;
}

fn lastIor() forth.Cell {
    const errno = std.c._errno().*;
    return forth.errnoIor(if (errno == 0) errno_io else errno);
}

fn badFileIor() forth.Cell {
    return forth.errnoIor(forth.errno_bad_file);
}

fn openedFile(fileid: forth.Cell) ?*anyopaque {
    if (fileid < forth.first_file_id or fileid - forth.first_file_id >= max_open_files) return null;
    return file_slots[@intCast(fileid - forth.first_file_id)].stream;
}

fn copyWritableHome(value: []const u8, buffer: []u8) forth.RuntimeError!?usize {
    var path: [4096:0]u8 = undefined;
    if (value.len >= path.len or std.mem.indexOfScalar(u8, value, 0) != null) return null;
    @memcpy(path[0..value.len], value);
    path[value.len] = 0;
    const accessible = if (builtin.os.tag == .windows) native: {
        var wide: [8192]u16 = undefined;
        const name = wide_c.from(&path, &wide) orelse return null;
        break :native @import("c_file")._waccess(name, 2) == 0;
    } else @import("c_file").access(&path, 2) == 0;
    if (!accessible) return null;
    if (value.len > buffer.len) return error.StringTooLong;
    @memcpy(buffer[0..value.len], value);
    return value.len;
}

fn userHome(context: ?*anyopaque, user: []const u8, buffer: []u8) forth.RuntimeError!?usize {
    if (user.len == 0) {
        const host = try hostContext(context);
        if (host.environ_map.get("HOME")) |value| if (try copyWritableHome(value, buffer)) |n| return n;
        if (comptime builtin.os.tag == .windows) {
            if (host.environ_map.get("HOMEDRIVE")) |drive| {
                if (host.environ_map.get("HOMEPATH")) |tail| {
                    var joined: [4096]u8 = undefined;
                    if (drive.len + tail.len > joined.len) return error.StringTooLong;
                    @memcpy(joined[0..drive.len], drive);
                    @memcpy(joined[drive.len..][0..tail.len], tail);
                    if (try copyWritableHome(joined[0 .. drive.len + tail.len], buffer)) |n| return n;
                }
            }
            for ([_][]const u8{ "TEMP", "TMP" }) |key| {
                if (host.environ_map.get(key)) |value| if (try copyWritableHome(value, buffer)) |n| return n;
            }
        }
        return 0;
    }
    if (comptime builtin.os.tag == .windows) return null;
    var name: [1024:0]u8 = undefined;
    if (user.len >= name.len or std.mem.indexOfScalar(u8, user, 0) != null) return null;
    @memcpy(name[0..user.len], user);
    name[user.len] = 0;
    const entry = @import("c_file").getpwnam(&name);
    if (entry == null) return null;
    const home = std.mem.span(entry.*.pw_dir);
    if (home.len > buffer.len) return error.StringTooLong;
    @memcpy(buffer[0..home.len], home);
    return home.len;
}

fn getDirectory(_: ?*anyopaque, buffer: []u8) forth.FileResult {
    if (buffer.len == 0) return .{ .ior = forth.errnoIor(forth.errno_invalid) };
    clearErrno();
    if (builtin.os.tag == .windows) {
        var wide: [32768]u16 = undefined;
        const found = @import("c_file")._wgetcwd(&wide, wide.len);
        if (found == null) return .{ .ior = lastIor() };
        const text = std.mem.span(found);
        var iterator = std.unicode.Utf16LeIterator.init(text);
        var length: usize = 0;
        while (iterator.nextCodepoint() catch return .{ .ior = forth.errnoIor(wide_c.errno_illegal_sequence) }) |c| {
            length += std.unicode.utf8CodepointSequenceLength(c) catch unreachable;
        }
        if (length >= buffer.len) return .{ .ior = forth.errnoIor(34) };
        _ = std.unicode.utf16LeToUtf8(buffer[0..length], text) catch return .{ .ior = forth.errnoIor(wide_c.errno_illegal_sequence) };
        buffer[length] = 0;
        return .{ .value = @intCast(length) };
    }
    if (@import("c_file").getcwd(buffer.ptr, buffer.len) == null) return .{ .ior = lastIor() };
    const length = std.mem.indexOfScalar(u8, buffer, 0) orelse return .{ .ior = forth.errnoIor(forth.errno_invalid) };
    return .{ .value = @intCast(length) };
}

fn makeDirectory(_: ?*anyopaque, name: []const u8, mode: forth.Cell) forth.Cell {
    var path: [4096:0]u8 = undefined;
    if (name.len >= path.len or std.mem.indexOfScalar(u8, name, 0) != null) return forth.errnoIor(forth.errno_invalid);
    @memcpy(path[0..name.len], name);
    path[name.len] = 0;
    clearErrno();
    const status = if (builtin.os.tag == .windows) native: {
        var wide: [8192]u16 = undefined;
        const terminated = wide_c.from(&path, &wide) orelse return lastIor();
        break :native @import("c_file")._wmkdir(terminated);
    } else @import("c_file").mkdir(&path, @as(@import("c_file").mode_t, @truncate(@as(u64, @bitCast(mode)))));
    return if (status == 0) 0 else lastIor();
}

fn setDirectory(_: ?*anyopaque, name: []const u8) forth.Cell {
    var path: [4096:0]u8 = undefined;
    if (name.len >= path.len or std.mem.indexOfScalar(u8, name, 0) != null) return forth.errnoIor(forth.errno_invalid);
    @memcpy(path[0..name.len], name);
    path[name.len] = 0;
    clearErrno();
    const status = if (builtin.os.tag == .windows) native: {
        var wide: [8192]u16 = undefined;
        const terminated = wide_c.from(&path, &wide) orelse return lastIor();
        break :native @import("c_file")._wchdir(terminated);
    } else @import("c_file").chdir(&path);
    return if (status == 0) 0 else lastIor();
}

fn fileOpen(_: ?*anyopaque, name: []const u8, access: forth.FileAccess, create: bool) forth.FileResult {
    return fileOpenMode(name, access, create, null);
}

fn fileCreateMode(_: ?*anyopaque, name: []const u8, access: forth.FileAccess, permissions: u16) forth.FileResult {
    if (permissions > 0o777) return .{ .ior = forth.errnoIor(forth.errno_invalid) };
    return fileOpenMode(name, access, true, permissions);
}

// fdopen transfers descriptor ownership only on success.
const descriptorStream = if (builtin.os.tag == .windows) struct {
    extern "c" fn _fdopen(c_int, [*:0]const u8) ?*anyopaque;
}._fdopen else struct {
    extern "c" fn fdopen(c_int, [*:0]const u8) ?*anyopaque;
}.fdopen;

fn openCreatedMode(path: [*:0]const u8, mode: [*:0]const u8, access: forth.FileAccess, permissions: u16) ?*anyopaque {
    const c = @import("c_file");
    const descriptor = if (builtin.os.tag == .windows) created: {
        var wide: [8192]u16 = undefined;
        const name = wide_c.from(path, &wide) orelse return null;
        const flags = c._O_CREAT | c._O_TRUNC | c._O_BINARY | (if (access == .write_only) c._O_WRONLY else c._O_RDWR);
        // Windows CRT permissions represent owner read/write, not POSIX ACLs.
        const native_mode: c_int = (if (permissions & 0o400 != 0) @as(c_int, c._S_IREAD) else 0) |
            (if (permissions & 0o200 != 0) @as(c_int, c._S_IWRITE) else 0);
        // Applying O_CREAT permissions while truncating an existing file can
        // change its readonly attribute on Windows. Create exclusively first;
        // if it already exists, open it without a creation mode.
        const fresh = c._wopen(name, @as(c_int, flags | c._O_EXCL), native_mode);
        if (fresh >= 0 or std.c._errno().* != 17) break :created fresh; // Windows CRT EEXIST.
        break :created c._wopen(name, @as(c_int, flags & ~@as(c_int, c._O_CREAT)));
    } else c.open(path, @as(c_int, c.O_CREAT | c.O_TRUNC | (if (access == .write_only) c.O_WRONLY else c.O_RDWR)), @as(c_uint, permissions));
    if (descriptor < 0) return null;
    return descriptorStream(descriptor, mode) orelse {
        const saved_errno = std.c._errno().*;
        if (builtin.os.tag == .windows) _ = c._close(descriptor) else _ = std.c.close(descriptor);
        std.c._errno().* = saved_errno;
        return null;
    };
}

fn fileOpenMode(name: []const u8, access: forth.FileAccess, create: bool, permissions: ?u16) forth.FileResult {
    var path: [4096:0]u8 = undefined;
    if (name.len >= path.len or std.mem.indexOfScalar(u8, name, 0) != null) return .{ .ior = forth.errnoIor(forth.errno_invalid) };
    const slot = for (file_slots, 0..) |entry, index| {
        if (entry.stream == null) break index;
    } else return .{ .ior = forth.errnoIor(errno_too_many_files) };
    @memcpy(path[0..name.len], name);
    path[name.len] = 0;
    // C streams cannot be opened write-only without truncation, so W/O on an existing
    // file uses update mode.
    const mode: [*:0]const u8 = if (create) (if (access == .write_only) "wb" else "w+b") else switch (access) {
        .read_only => "rb",
        .write_only, .read_write => "r+b",
    };
    clearErrno();
    const file = (if (permissions) |bits| openCreatedMode(&path, mode, access, bits) else fopen(&path, mode)) orelse return .{ .ior = lastIor() };
    // POSIX probes preserve normal stdio buffering. Windows disk reads can be
    // probed directly; only pipe streams need unbuffered reads so PeekNamedPipe
    // plus explicit query pushback accounts for every unread byte.
    var native_pipe = false;
    if (builtin.os.tag == .windows) {
        const native = _get_osfhandle(file_number(file));
        if (native == -1) {
            _ = fclose(file);
            return .{ .ior = badFileIor() };
        }
        const handle: *anyopaque = @ptrFromInt(@as(usize, @bitCast(native)));
        native_pipe = GetFileType(handle) == 3;
        if (native_pipe and setvbuf(file, null, @import("c_file")._IONBF, 0) != 0) {
            _ = fclose(file);
            return .{ .ior = forth.errnoIor(errno_io) };
        }
    }
    if (builtin.os.tag != .windows) {
        const c = @import("c_file");
        const kind = sigma_file_is_pipe(file_number(file));
        if (kind < 0) {
            const ior = lastIor();
            _ = fclose(file);
            return .{ .ior = ior };
        }
        native_pipe = kind != 0;
        if (native_pipe and setvbuf(file, null, c._IONBF, 0) != 0) {
            _ = fclose(file);
            return .{ .ior = forth.errnoIor(errno_io) };
        }
    }
    file_slots[slot].stream = file;
    file_slots[slot].access = access;
    file_slots[slot].native_pipe = native_pipe;
    resetFileInput(slot);
    file_slots[slot].pipe = false;
    return .{ .value = @intCast(forth.first_file_id + @as(forth.Cell, @intCast(slot))) };
}

fn nativePipeClose(file: *anyopaque) c_int {
    return if (builtin.os.tag == .windows) wide_c._pclose(file) else libc.pclose(file);
}

fn fileOpenPipe(_: ?*anyopaque, command: []const u8, access: forth.FileAccess) forth.FileResult {
    pauseStdinReader() catch return .{ .ior = forth.errnoIor(errno_io) };
    if (access == .read_write) return .{ .ior = forth.errnoIor(forth.errno_invalid) };
    var path: [4096:0]u8 = undefined;
    const text = cPath(command, &path) orelse return .{ .ior = forth.errnoIor(forth.errno_invalid) };
    const slot = for (file_slots, 0..) |entry, index| {
        if (entry.stream == null) break index;
    } else return .{ .ior = forth.errnoIor(errno_too_many_files) };
    const prior = flushStandardOutput();
    if (prior != 0) return .{ .ior = prior };
    const errors = finishWriter(forth.stderr_fileid);
    if (errors != 0) return .{ .ior = errors };
    // A child may write inherited stdout/stderr without passing through us.
    output_cursor.unknown();
    clearErrno();
    const file = (if (builtin.os.tag == .windows) native: {
        var wide: [8192]u16 = undefined;
        break :native wide_c._wpopen(wide_c.from(text, &wide) orelse return .{ .ior = lastIor() }, if (access == .read_only) &[_:0]u16{ 'r', 'b' } else &[_:0]u16{ 'w', 'b' });
    } else libc.popen(text, if (access == .read_only) "r" else "w")) orelse return .{ .ior = lastIor() };
    // Nonblocking APIs and worker migration share an unbuffered pipe stream.
    if (setvbuf(file, null, @import("c_file")._IONBF, 0) != 0) {
        _ = nativePipeClose(file);
        return .{ .ior = forth.errnoIor(errno_io) };
    }
    file_slots[slot].stream = file;
    file_slots[slot].access = access;
    file_slots[slot].pipe = true;
    file_slots[slot].native_pipe = true;
    resetFileInput(slot);
    return .{ .value = @intCast(forth.first_file_id + @as(forth.Cell, @intCast(slot))) };
}

fn fileClosePipe(_: ?*anyopaque, fileid: forth.Cell) forth.FileResult {
    const failure: forth.FileResult = .{ .value = @bitCast(@as(forth.Cell, -1)), .ior = badFileIor() };
    const file = openedFile(fileid) orelse return failure;
    const slot = fileSlot(fileid);
    if (!file_slots[slot].pipe) return failure;
    const queued = finishWriter(fileid);
    if (queued == forth.errnoIor(4) and !closing_all_files) return .{ .value = failure.value, .ior = queued };
    if (builtin.os.tag == .windows) file_slots[slot].writer.deinit() catch return .{ .value = failure.value, .ior = forth.errnoIor(errno_io) };
    if (builtin.os.tag == .windows) file_slots[slot].reader.deinit() catch return .{ .value = failure.value, .ior = forth.errnoIor(errno_io) };
    var scope = PipeSignalScope.begin(true) catch return .{ .value = failure.value, .ior = forth.errnoIor(errno_io) };
    file_slots[slot].stream = null;
    resetFileInput(slot);
    file_slots[slot].pipe = false;
    clearErrno();
    const status = nativePipeClose(file);
    output_cursor.unknown();
    var ior: forth.Cell = if (status == -1) lastIor() else queued;
    if (!scope.end() and ior == 0) ior = forth.errnoIor(errno_io);
    return .{ .value = @bitCast(@as(forth.Cell, status)), .ior = ior };
}

fn fileClose(_: ?*anyopaque, fileid: forth.Cell) forth.Cell {
    if (fileid == forth.stdin_fileid) return 0;
    if (fileid == forth.stdout_fileid or fileid == forth.stderr_fileid) return fileFlush(null, fileid);
    const file = openedFile(fileid) orelse return badFileIor();
    if (file_slots[fileSlot(fileid)].pipe) return badFileIor();
    const queued = finishWriter(fileid);
    if (queued == forth.errnoIor(4) and !closing_all_files) return queued;
    if (builtin.os.tag == .windows) file_slots[fileSlot(fileid)].writer.deinit() catch return forth.errnoIor(errno_io);
    if (builtin.os.tag == .windows) file_slots[fileSlot(fileid)].reader.deinit() catch return forth.errnoIor(errno_io);
    file_slots[@intCast(fileid - forth.first_file_id)].stream = null;
    file_slots[fileSlot(fileid)].proc_owner = 0;
    resetFileInput(fileSlot(fileid));
    clearErrno();
    return if (fclose(file) == 0) queued else lastIor();
}

/// Reads bytes from an open C stream, or from the terminal input for STDIN so that
/// the byte read ahead by KEY? is not lost.
const LineSource = struct {
    file: ?*anyopaque,
    fileid: forth.Cell,
    ior: forth.Cell = 0,

    fn get(self: *LineSource) c_int {
        if (self.file) |file| {
            if (file_slots[fileSlot(self.fileid)].input.takeByte()) |byte| return byte;
            if (file_slots[fileSlot(self.fileid)].eof) return -1;
            if (managedReader(self.fileid) or nativePipe(self.fileid)) {
                const result = (if (managedReader(self.fileid)) readerByte(self.fileid) else directPipeByte(self.fileid)) catch |err| {
                    self.ior = forth.errnoIor(if (err == error.UserInterrupt) 4 else errno_io);
                    return -1;
                };
                self.ior = result.ior;
                return if (result.byte) |byte| byte else -1;
            }
            const prepared = prepareFileRead(self.fileid, file);
            if (prepared != 0) {
                self.ior = prepared;
                return -1;
            }
            const byte = getc(file);
            file_slots[fileSlot(self.fileid)].eof = feof(file) != 0;
            if (byte < 0 and ferror(file) != 0) {
                self.ior = lastIor();
                clearerr(file);
            }
            return byte;
        }
        return readByte();
    }

    fn unget(self: LineSource, byte: c_int) void {
        if (self.file) |file| {
            _ = file;
            // This just-consumed byte always fits in the bounded prefix buffer.
            file_slots[fileSlot(self.fileid)].input.putByte(@intCast(byte)) catch unreachable;
            file_slots[fileSlot(self.fileid)].input.eof = false;
            file_slots[fileSlot(self.fileid)].eof = false;
        } else terminalUnread(null, @intCast(byte));
    }
};

fn fileReadLine(_: ?*anyopaque, fileid: forth.Cell, buffer: []u8) forth.LineResult {
    var source = LineSource{ .fileid = fileid, .file = if (fileid == forth.stdin_fileid) null else openedFile(fileid) orelse return .{ .ior = badFileIor() } };
    clearErrno();
    var length: usize = 0;
    while (length < buffer.len) {
        const byte = source.get();
        if (byte < 0) {
            if (source.ior != 0) return .{ .length = length, .found = length != 0, .ior = source.ior };
            if (source.file) |file| {
                if (ferror(file) != 0) {
                    const ior = lastIor();
                    clearerr(file);
                    return .{ .length = length, .found = length != 0, .ior = ior };
                }
            }
            return .{ .length = length, .found = length != 0 };
        }
        if (byte == '\n') break;
        if (byte == '\r') {
            const next = source.get();
            if (next >= 0 and next != '\n') source.unget(next);
            break;
        }
        buffer[length] = @intCast(byte);
        length += 1;
    }
    return .{ .length = length, .found = true, .ior = source.ior };
}

fn fileRead(_: ?*anyopaque, fileid: forth.Cell, buffer: []u8) forth.FileResult {
    if (fileid == forth.stdin_fileid) {
        // Byte by byte from the terminal input, so the byte read ahead by KEY? comes first;
        // as in READ-LINE, the end of the input ends the read.
        var count: usize = 0;
        while (count < buffer.len) : (count += 1) {
            const byte = readByte();
            if (byte < 0) break;
            buffer[count] = @intCast(byte);
        }
        return .{ .value = count };
    }
    const file = openedFile(fileid) orelse return .{ .ior = badFileIor() };
    clearErrno();
    if (buffer.len == 0) return .{};
    const decoder = &file_slots[fileSlot(fileid)].input;
    const prefix = @min(buffer.len, decoder.length);
    @memcpy(buffer[0..prefix], decoder.bytes[0..prefix]);
    var count: usize = 0;
    if (prefix < buffer.len and !file_slots[fileSlot(fileid)].eof) {
        if (builtin.is_test and test_file_read_failure) return .{ .ior = forth.errnoIor(errno_io) };
        const prepared = prepareFileRead(fileid, file);
        if (prepared != 0) return .{ .ior = prepared };
        if (managedReader(fileid) or nativePipe(fileid)) {
            while (count < buffer.len - prefix) {
                const result = (if (managedReader(fileid)) readerByte(fileid) else directPipeByte(fileid)) catch |err| {
                    if (count != 0) for (0..prefix) |_| {
                        _ = decoder.takeByte();
                    };
                    return .{ .value = if (count == 0) 0 else prefix + count, .ior = forth.errnoIor(if (err == error.UserInterrupt) 4 else errno_io) };
                };
                if (result.ior != 0) {
                    if (count != 0) for (0..prefix) |_| {
                        _ = decoder.takeByte();
                    };
                    return .{ .value = if (count == 0) 0 else prefix + count, .ior = result.ior };
                }
                buffer[prefix + count] = result.byte orelse break;
                count += 1;
            }
        } else count = fread(buffer[prefix..].ptr, 1, buffer.len - prefix, file);
        if (!managedReader(fileid) and !nativePipe(fileid)) file_slots[fileSlot(fileid)].eof = feof(file) != 0;
        if (count < buffer.len - prefix and ferror(file) != 0) {
            const ior = lastIor();
            clearerr(file);
            if (count != 0) for (0..prefix) |_| {
                _ = decoder.takeByte();
            };
            return .{ .value = if (count == 0) 0 else prefix + count, .ior = ior };
        }
    }
    // Commit the copied prefix only after the remainder succeeds or reaches EOF.
    for (0..prefix) |_| _ = decoder.takeByte();
    return .{ .value = prefix + count };
}

fn prepareFileRead(fileid: forth.Cell, file: *anyopaque) forth.Cell {
    const slot = &file_slots[fileSlot(fileid)];
    if (!slot.native_pipe and slot.access == .read_write and !slot.last_read) {
        clearErrno();
        // ISO C update streams require a flush/position operation between output
        // and input. Waiting until SYNC-FILE would be too late on UCRT.
        if (fflush(file) != 0) return lastIor();
    }
    if (slot.access != .write_only) slot.last_read = true;
    return 0;
}

fn prepareFileWrite(fileid: forth.Cell, file: *anyopaque) forth.Cell {
    const slot = fileSlot(fileid);
    // A pipe has independent byte directions; writing does not reposition or
    // discard bytes prefetched by its read side.
    if (file_slots[slot].native_pipe) return 0;
    const pending = file_slots[slot].input.length;
    if (pending != 0) {
        clearErrno();
        const position = tell64(file);
        if (position < 0) return lastIor();
        if (position < @as(i64, @intCast(pending))) return forth.errnoIor(forth.errno_invalid);
        if (seek64(file, position - @as(i64, @intCast(pending)), 0) != 0) return lastIor();
        resetFileInput(slot);
    } else if (file_slots[slot].last_read) {
        clearErrno();
        if (seek64(file, 0, 1) != 0) {
            if (builtin.os.tag == .windows or std.c._errno().* != 29) return lastIor();
            clearerr(file);
        }
    }
    file_slots[slot].last_read = false;
    file_slots[slot].eof = false;
    return 0;
}

fn fileWrite(context: ?*anyopaque, fileid: forth.Cell, bytes: []const u8) forth.Cell {
    if (fileid == forth.stdout_fileid) {
        terminalWrite(context, bytes);
        return output_ior;
    }
    if (fileid == forth.stderr_fileid) {
        const queued = drainWriter(fileid) catch |err| return forth.errnoIor(if (err == error.UserInterrupt) 4 else errno_io);
        if (queued != 0) return queued;
        return if (writeStandardErrorDirect(bytes)) 0 else forth.errnoIor(errno_io);
    }
    const file = openedFile(fileid) orelse return badFileIor();
    const queued = drainWriter(fileid) catch |err| return forth.errnoIor(if (err == error.UserInterrupt) 4 else errno_io);
    if (queued != 0) return queued;
    const prepared = prepareFileWrite(fileid, file);
    if (prepared != 0) return prepared;
    var scope = PipeSignalScope.begin(file_slots[fileSlot(fileid)].native_pipe) catch return forth.errnoIor(errno_io);
    clearErrno();
    var ior: forth.Cell = 0;
    if (builtin.os.tag != .windows and file_slots[fileSlot(fileid)].native_pipe) {
        var rest = bytes;
        while (rest.len != 0) {
            const count = std.c.write(file_number(file), rest.ptr, rest.len);
            if (count <= 0) {
                ior = if (count == 0) forth.errnoIor(errno_io) else lastIor();
                break;
            }
            rest = rest[@intCast(count)..];
        }
    } else if (fwrite(bytes.ptr, 1, bytes.len, file) != bytes.len) ior = lastIor();
    if (!scope.end() and ior == 0) ior = forth.errnoIor(errno_io);
    return ior;
}

fn fileSize(_: ?*anyopaque, fileid: forth.Cell) forth.FileResult {
    const file = openedFile(fileid) orelse return .{ .ior = badFileIor() };
    if (file_slots[fileSlot(fileid)].native_pipe) return .{ .ior = forth.errnoIor(29) };
    clearErrno();
    const position = tell64(file);
    if (position < 0 or seek64(file, 0, 2) != 0) return .{ .ior = lastIor() };
    const end = tell64(file);
    if (end < 0 or seek64(file, position, 0) != 0) return .{ .ior = lastIor() };
    return .{ .value = @intCast(end) };
}

fn fileReposition(_: ?*anyopaque, fileid: forth.Cell, position: forth.UCell) forth.Cell {
    const file = openedFile(fileid) orelse return badFileIor();
    if (file_slots[fileSlot(fileid)].native_pipe) return forth.errnoIor(29);
    clearErrno();
    if (seek64(file, @intCast(position), 0) != 0) return lastIor();
    resetFileInput(fileSlot(fileid));
    file_slots[fileSlot(fileid)].eof = false;
    return 0;
}

fn filePosition(_: ?*anyopaque, fileid: forth.Cell) forth.FileResult {
    const file = openedFile(fileid) orelse return .{ .ior = badFileIor() };
    if (file_slots[fileSlot(fileid)].native_pipe) return .{ .ior = forth.errnoIor(29) };
    clearErrno();
    const position = tell64(file);
    if (position < 0) return .{ .ior = lastIor() };
    const pending: i64 = @intCast(file_slots[fileSlot(fileid)].input.length);
    if (position < pending) return .{ .ior = forth.errnoIor(forth.errno_invalid) };
    return .{ .value = @intCast(position - pending) };
}

fn fileResize(_: ?*anyopaque, fileid: forth.Cell, size: forth.UCell) forth.Cell {
    const file = openedFile(fileid) orelse return badFileIor();
    if (size > std.math.maxInt(i64)) return forth.errnoIor(forth.errno_invalid);
    if (file_slots[fileSlot(fileid)].native_pipe) return forth.errnoIor(29);
    clearErrno();
    if (fflush(file) != 0) return lastIor();
    // _chsize_s returns the error number itself; ftruncate returns -1 and sets errno.
    const result = resizeDescriptor(file_number(file), @intCast(size));
    if (result == 0) return 0;
    return if (builtin.os.tag == .windows) forth.errnoIor(result) else lastIor();
}

fn flushProcessOutput() forth.RuntimeError!void {
    const output = flushStandardOutput();
    const errors = finishWriter(forth.stderr_fileid);
    const ior = if (output != 0) output else errors;
    if (ior != 0) return if (ior == forth.errnoIor(4)) error.UserInterrupt else error.HostFailed;
}

fn finishWriter(id: forth.Cell) forth.Cell {
    return drainWriter(id) catch |err| forth.errnoIor(if (err == error.UserInterrupt) 4 else errno_io);
}

fn flushStandardOutput() forth.Cell {
    while (output_used != 0) {
        flushOutput();
        if (output_ior != 0) return output_ior;
        if (output_used != 0) {
            if (builtin.os.tag != .windows and output_nonblocking) {
                const result = fileWaitFiles(null, &.{forth.stdout_fileid}, -1, true) catch |err| return forth.errnoIor(if (err == error.UserInterrupt) 4 else errno_io);
                if (result.ior != 0) return result.ior;
            } else {
                const queued = finishWriter(forth.stdout_fileid);
                if (queued != 0) return queued;
            }
        }
    }
    return finishWriter(forth.stdout_fileid);
}

fn fileFlush(_: ?*anyopaque, fileid: forth.Cell) forth.Cell {
    if (fileid == forth.stdout_fileid) return flushStandardOutput();
    if (fileid != forth.stderr_fileid and openedFile(fileid) == null) return badFileIor();
    const queued = finishWriter(fileid);
    if (queued != 0) return queued;
    if (fileid == forth.stderr_fileid) return 0;
    const file = openedFile(fileid).?;
    var scope = PipeSignalScope.begin(file_slots[fileSlot(fileid)].native_pipe) catch return forth.errnoIor(errno_io);
    clearErrno();
    var ior: forth.Cell = if (fflush(file) == 0) 0 else lastIor();
    if (!scope.end() and ior == 0) ior = forth.errnoIor(errno_io);
    return ior;
}

fn fileSync(_: ?*anyopaque, fileid: forth.Cell) forth.Cell {
    if (fileid == forth.stdin_fileid or fileid == forth.stdout_fileid or fileid == forth.stderr_fileid) return forth.errnoIor(22);
    const file = openedFile(fileid) orelse return badFileIor();
    const slot = &file_slots[fileSlot(fileid)];
    if (slot.pipe or slot.native_pipe or slot.proc_owner != 0) return forth.errnoIor(22);
    const regular = host_fs.sigma_fs_regular(file_number(file));
    if (regular != 0) return forth.errnoIor(regular);
    if (slot.access == .read_only) return forth.errnoIor(13);
    // Regular files have no async workers. Positioning synchronizes a C input
    // stream without discarding the FileSlot's semantic EOF or pending bytes.
    clearErrno();
    if (slot.last_read) {
        if (seek64(file, 0, 1) != 0) return lastIor();
    } else if (fflush(file) != 0) return lastIor();
    const code = host_fs.sigma_fs_sync(file_number(file));
    return if (code == 0) 0 else forth.errnoIor(code);
}

test "filesystem sync preserves pending input EOF and ownership and rejects standard and readonly" {
    if (!host_fs.supported) return error.SkipZigTest;
    const path = ".zig-cache/sigma-filesystem-sync.bin";
    defer _ = fileDelete(null, path);
    const opened = fileOpen(null, path, .read_write, true);
    try std.testing.expectEqual(@as(forth.Cell, 0), opened.ior);
    const id: forth.Cell = @bitCast(opened.value);
    defer _ = fileClose(null, id);
    try std.testing.expectEqual(@as(forth.Cell, 0), fileWrite(null, id, "A\rB"));
    try std.testing.expectEqual(@as(forth.Cell, 0), fileReposition(null, id, 0));
    var line: [8]u8 = undefined;
    const read = fileReadLine(null, id, &line);
    try std.testing.expectEqual(@as(usize, 1), read.length);
    try std.testing.expectEqual(@as(usize, 1), file_slots[fileSlot(id)].input.length);
    const position = filePosition(null, id).value;
    try std.testing.expectEqual(@as(forth.Cell, 0), fileSync(null, id));
    try std.testing.expectEqual(position, filePosition(null, id).value);
    try std.testing.expectEqual(@as(usize, 1), file_slots[fileSlot(id)].input.length);
    try std.testing.expectEqual(@as(u8, 'B'), (try fileKey(null, id)).byte.?);
    try std.testing.expect((try fileKey(null, id)).byte == null);
    try std.testing.expectEqual(@as(forth.Cell, 0), fileSync(null, id));
    try std.testing.expectEqual(@as(forth.UCell, 1), fileEof(null, id).value);
    const ro = fileOpen(null, path, .read_only, false);
    try std.testing.expectEqual(@as(forth.Cell, 0), ro.ior);
    const readonly: forth.Cell = @bitCast(ro.value);
    try std.testing.expectEqual(forth.errnoIor(13), fileSync(null, readonly));
    try std.testing.expectEqual(@as(forth.Cell, 0), fileSize(null, readonly).ior);
    try std.testing.expectEqual(@as(forth.Cell, 0), fileClose(null, readonly));
    try std.testing.expectEqual(badFileIor(), fileSync(null, readonly));
    try std.testing.expectEqual(forth.errnoIor(22), fileSync(null, forth.stdin_fileid));
    try std.testing.expectEqual(forth.errnoIor(22), fileSync(null, forth.stdout_fileid));
}

/// The name as a C string, or null when it is too long or holds a NUL.
fn cPath(name: []const u8, path: *[4096:0]u8) ?[*:0]const u8 {
    if (name.len >= path.len or std.mem.indexOfScalar(u8, name, 0) != null) return null;
    @memcpy(path[0..name.len], name);
    path[name.len] = 0;
    return path;
}

fn fileDelete(_: ?*anyopaque, name: []const u8) forth.Cell {
    var path: [4096:0]u8 = undefined;
    const c_name = cPath(name, &path) orelse return forth.errnoIor(forth.errno_invalid);
    clearErrno();
    return if (remove(c_name) == 0) 0 else lastIor();
}

fn fileRename(_: ?*anyopaque, old: []const u8, new: []const u8) forth.Cell {
    var old_path: [4096:0]u8 = undefined;
    var new_path: [4096:0]u8 = undefined;
    const c_old = cPath(old, &old_path) orelse return forth.errnoIor(forth.errno_invalid);
    const c_new = cPath(new, &new_path) orelse return forth.errnoIor(forth.errno_invalid);
    // The Windows C library's rename does not replace an existing file, as POSIX rename
    // (and so gforth) does. MoveFileEx replaces it in one step, so a failure leaves the
    // file there as it was.
    if (builtin.os.tag == .windows) {
        var old_wide: [8192]u16 = undefined;
        var new_wide: [8192]u16 = undefined;
        const w_old = wide_c.from(c_old, &old_wide) orelse return lastIor();
        const w_new = wide_c.from(c_new, &new_wide) orelse return lastIor();
        if (wide_c.MoveFileExW(w_old, w_new, move_replace_existing | move_copy_allowed) != 0) return 0;
        return forth.errnoIor(switch (GetLastError()) {
            2, 3 => 2, // ERROR_FILE_NOT_FOUND, ERROR_PATH_NOT_FOUND: ENOENT
            5, 32 => 13, // ERROR_ACCESS_DENIED, ERROR_SHARING_VIOLATION: EACCES
            else => errno_io,
        });
    }
    clearErrno();
    if (rename(c_old, c_new) == 0) return 0;
    return lastIor();
}

extern "kernel32" fn GetLastError() callconv(.winapi) u32;
const move_replace_existing = 0x1;
const move_copy_allowed = 0x2;

fn fileStatus(_: ?*anyopaque, name: []const u8) forth.FileResult {
    var path: [4096:0]u8 = undefined;
    const c_name = cPath(name, &path) orelse return .{ .ior = forth.errnoIor(forth.errno_invalid) };
    clearErrno();
    const readable = fopen(c_name, "rb");
    if (readable) |file| _ = fclose(file);
    const read_ior = lastIor();
    clearErrno();
    const writable = fopen(c_name, "r+b");
    if (writable) |file| _ = fclose(file);
    if (readable == null and writable == null) return .{ .ior = read_ior };
    const fam: forth.Cell = if (readable != null and writable != null) forth.fam_read_write else if (readable != null) forth.fam_read_only else forth.fam_write_only;
    return .{ .value = @bitCast(fam) };
}

fn closeAllFiles() void {
    closing_all_files = true;
    defer closing_all_files = false;
    for (&file_slots, 0..) |*slot, index| {
        if (slot.stream != null) {
            const id = forth.first_file_id + @as(forth.Cell, @intCast(index));
            if (slot.pipe) {
                _ = fileClosePipe(null, id);
            } else {
                _ = fileClose(null, id);
            }
        }
    }
    const output_result = flushStandardOutput();
    _ = finishWriter(forth.stderr_fileid);
    if (output_result != 0) output_used = 0;
    if (builtin.os.tag == .windows) {
        var retained = false;
        stdout_writer.deinit() catch {
            retained = true;
        };
        stderr_writer.deinit() catch {
            retained = true;
        };
        stdin_reader.deinit() catch {
            retained = true;
        };
        if (retained) return;
    }
    for (0..file_slots.len) |index| if (managedReader(forth.first_file_id + @as(forth.Cell, @intCast(index))) or managedWriter(forth.first_file_id + @as(forth.Cell, @intCast(index)))) return;
    if (file_wake) |*wake| {
        wake.deinit() catch return;
        file_wake = null;
    }
}

/// Return a byte without changing the caller's ownership of the stream.
fn fileKey(_: ?*anyopaque, fileid: forth.Cell) forth.RuntimeError!forth.FileKeyResult {
    flushOutput();
    if (fileid == forth.stdin_fileid) return .{ .byte = fileStdinByte(true) catch |err| {
        if (err == error.HostFailed) return .{ .ior = lastIor() };
        return err;
    } };
    const file = openedFile(fileid) orelse return .{ .ior = badFileIor() };
    if (file_slots[fileSlot(fileid)].input.takeByte()) |byte| return .{ .byte = byte };
    clearErrno();
    if (file_slots[fileSlot(fileid)].eof) return .{};
    if (managedReader(fileid)) return readerByte(fileid);
    if (nativePipe(fileid)) return directPipeByte(fileid);
    const prepared = prepareFileRead(fileid, file);
    if (prepared != 0) return .{ .ior = prepared };
    const byte = getc(file);
    file_slots[fileSlot(fileid)].eof = feof(file) != 0;
    if (byte < 0) {
        if (ferror(file) != 0) {
            const ior = lastIor();
            clearerr(file);
            return .{ .ior = ior };
        }
        return .{};
    }
    return .{ .byte = @intCast(byte) };
}

fn fileUnread(_: ?*anyopaque, fileid: forth.Cell, byte: u8) forth.RuntimeError!void {
    if (fileid == forth.stdin_fileid) {
        terminalUnread(null, byte);
        stdin_eof = false;
        return;
    }
    _ = openedFile(fileid) orelse return error.InvalidAddress;
    try file_slots[fileSlot(fileid)].input.putByte(byte);
    file_slots[fileSlot(fileid)].input.eof = false;
    file_slots[fileSlot(fileid)].eof = false;
}

fn terminalKeyIor(context: ?*anyopaque) forth.RuntimeError!forth.FileKeyResult {
    return fileKey(context, forth.stdin_fileid);
}

fn fileEof(_: ?*anyopaque, fileid: forth.Cell) forth.FileResult {
    if (fileid == forth.stdin_fileid) return .{ .value = @intFromBool(stdin_eof) };
    if (fileid == forth.stdout_fileid or fileid == forth.stderr_fileid) return .{};
    _ = openedFile(fileid) orelse return .{ .ior = badFileIor() };
    if (file_slots[fileSlot(fileid)].input.length != 0) return .{};
    return .{ .value = @intFromBool(file_slots[fileSlot(fileid)].eof) };
}

fn ioWake() forth.RuntimeError!*@import("host_wake.zig").Wake {
    if (file_wake == null) file_wake = try @import("host_wake.zig").Wake.init();
    return &file_wake.?;
}

fn ioDescriptor(id: forth.Cell) ?c_int {
    if (id >= forth.stdin_fileid and id <= forth.stderr_fileid) return @intCast(id - forth.stdin_fileid);
    return file_number(openedFile(id) orelse return null);
}

fn ioNativeHandle(id: forth.Cell) ?*anyopaque {
    if (id >= forth.stdin_fileid and id <= forth.stderr_fileid) {
        const kind: i32 = if (id == forth.stdin_fileid) -10 else if (id == forth.stdout_fileid) -11 else -12;
        const handle = GetStdHandle(@bitCast(kind)) orelse return null;
        return if (@intFromPtr(handle) == std.math.maxInt(usize)) null else handle;
    }
    const native = _get_osfhandle(ioDescriptor(id) orelse return null);
    return if (native == -1) null else @ptrFromInt(@as(usize, @bitCast(native)));
}

fn fileIoCheck(_: ?*anyopaque, id: forth.Cell, writing: bool) forth.Cell {
    if (id == forth.stdin_fileid) {
        if (writing) return badFileIor();
    } else if (id == forth.stdout_fileid or id == forth.stderr_fileid) {
        if (!writing) return badFileIor();
    } else {
        _ = openedFile(id) orelse return badFileIor();
        const access = file_slots[fileSlot(id)].access;
        if ((writing and access == .read_only) or (!writing and access == .write_only)) return badFileIor();
    }
    if (builtin.os.tag == .windows) {
        const handle = ioNativeHandle(id) orelse return badFileIor();
        switch (GetFileType(handle)) {
            1 => {},
            2 => {
                var mode: u32 = 0;
                if (GetConsoleMode(handle, &mode) == 0) return forth.errnoIor(forth.errno_invalid);
            },
            3 => {
                const pipe_access = @import("host_pipe_access.zig");
                const access = pipe_access.query(handle) catch return forth.errnoIor(errno_io);
                if (access.read and access.write) return forth.errnoIor(forth.errno_invalid);
                if ((writing and !access.write) or (!writing and !access.read)) return badFileIor();
                if (writing and (id == forth.stdout_fileid or id == forth.stderr_fileid)) {
                    if (GetStdHandle(@bitCast(@as(i32, -10)))) |other| {
                        if (@intFromPtr(other) != std.math.maxInt(usize) and (pipe_access.same(handle, other) catch return forth.errnoIor(errno_io))) return forth.errnoIor(forth.errno_invalid);
                    }
                }
                if (id == forth.stdin_fileid) for ([_]i32{ -11, -12 }) |kind| {
                    if (GetStdHandle(@bitCast(kind))) |other| {
                        if (@intFromPtr(other) != std.math.maxInt(usize)) {
                            const same = pipe_access.same(handle, other) catch return forth.errnoIor(errno_io);
                            if (same) return forth.errnoIor(forth.errno_invalid);
                        }
                    }
                };
            },
            else => return forth.errnoIor(forth.errno_invalid),
        }
    } else {
        const descriptor = ioDescriptor(id) orelse return badFileIor();
        const flags = fcntl(descriptor, @import("c_file").F_GETFL);
        if (flags < 0) return lastIor();
        const access = flags & @import("c_file").O_ACCMODE;
        if ((writing and access == @import("c_file").O_RDONLY) or (!writing and access == @import("c_file").O_WRONLY)) return badFileIor();
    }
    return 0;
}

fn managedReader(id: forth.Cell) bool {
    if (builtin.os.tag == .windows) {
        if (id == forth.stdin_fileid) return stdin_reader.active();
        return file_slots[fileSlot(id)].reader.active();
    }
    return false;
}

fn ensureReader(id: forth.Cell) forth.RuntimeError!void {
    if (builtin.os.tag == .windows) {
        const handle = ioNativeHandle(id) orelse return error.HostFailed;
        if (GetFileType(handle) != 3) return;
        const reader = if (id == forth.stdin_fileid) &stdin_reader else &file_slots[fileSlot(id)].reader;
        try reader.start(handle, try ioWake());
    }
}

fn pauseStdinReader() forth.RuntimeError!void {
    if (builtin.os.tag == .windows) try stdin_reader.pause();
}

fn nativePipe(id: forth.Cell) bool {
    return id >= forth.first_file_id and file_slots[fileSlot(id)].native_pipe;
}

/// Do not let CRT getc/fread hide bytes before a later worker takes ownership.
fn directPipeByte(id: forth.Cell) forth.RuntimeError!forth.FileKeyResult {
    if (builtin.os.tag == .windows) {
        const handle = ioNativeHandle(id) orelse return .{ .ior = badFileIor() };
        const guard = @import("host_wait.zig");
        while (true) {
            var byte: [1]u8 = undefined;
            var count: u32 = 0;
            try guard.beginConsoleRead();
            const success = ReadFile(handle, &byte, 1, &count, null);
            const code = if (success == 0) GetLastError() else 0;
            guard.endConsoleRead();
            if (count != 0) return .{ .byte = byte[0] };
            if (code == 995 and guard.inputInterrupted()) return deliveredInterrupt();
            if (success != 0) continue;
            if (code == 109 or code == 38) {
                file_slots[fileSlot(id)].eof = true;
                return .{};
            }
            return .{ .ior = forth.errnoIor(errno_io) };
        }
    }
    var byte: [1]u8 = undefined;
    clearErrno();
    const count = std.c.read(ioDescriptor(id).?, &byte, 1);
    if (count > 0) return .{ .byte = byte[0] };
    if (count < 0) return .{ .ior = lastIor() };
    file_slots[fileSlot(id)].eof = true;
    return .{};
}

fn readerProbe(id: forth.Cell, destination: []u8) forth.RuntimeError!io_types.AvailableResult {
    if (builtin.os.tag == .windows) {
        try ensureReader(id);
        const reader = if (id == forth.stdin_fileid) &stdin_reader else &file_slots[fileSlot(id)].reader;
        const result = reader.read(destination);
        if (result.eof) {
            if (id == forth.stdin_fileid) stdin_eof = true else file_slots[fileSlot(id)].eof = true;
        }
        return .{ .count = result.count, .eof = result.eof, .ior = if (result.code == 0) 0 else forth.errnoIor(errno_io) };
    }
    return error.HostUnavailable;
}

fn readerByte(id: forth.Cell) forth.RuntimeError!forth.FileKeyResult {
    if (builtin.os.tag == .windows) {
        const guard = @import("host_wait.zig");
        try ensureReader(id);
        try guard.beginInput();
        var guarded = true;
        defer if (guarded) {
            guard.endInput() catch {};
        };
        const wake = try ioWake();
        const reader = if (id == forth.stdin_fileid) &stdin_reader else &file_slots[fileSlot(id)].reader;
        while (true) {
            if (guard.inputInterrupted()) return deliveredInterrupt();
            const observed = wake.observe();
            const state = reader.peek();
            if (state.count != 0 or state.eof or state.code != 0) {
                guarded = false;
                try guard.endInput();
                var byte: [1]u8 = undefined;
                const result = reader.read(&byte);
                if (result.eof) {
                    if (id == forth.stdin_fileid) stdin_eof = true else file_slots[fileSlot(id)].eof = true;
                }
                if (result.count != 0) return .{ .byte = byte[0] };
                if (result.eof) {
                    if (id == forth.stdin_fileid) stdin_eof = true else file_slots[fileSlot(id)].eof = true;
                }
                return .{ .ior = if (result.code == 0) 0 else forth.errnoIor(errno_io) };
            }
            const deadline = try @import("core/runtime_base.zig").Deadline.afterMilliseconds(try @import("host_clock.zig").now(), 20);
            _ = try wake.wait(observed, deadline, null);
        }
    }
    return error.HostUnavailable;
}

fn stdinProbeByte() forth.RuntimeError!file_event.Result {
    if (popLookahead()) |byte| return .{ .event = .{ .value = byte } };
    if (host_input.takePendingByte()) |byte| return .{ .event = .{ .value = byte } };
    if (builtin.os.tag == .windows) if (utf8_console.takePendingByte()) |byte| return .{ .event = .{ .value = byte } };
    if (host_input.input_is_terminal) {
        // Preserve non-byte events for standard EKEY rather than throwing them away.
        for (0..32) |_| {
            if (deferred_length == deferred_packets.len) return .{ .failure = forth.errnoIor(errno_io) };
            const packet = host_input.nextStandardPacket() orelse break;
            if (packet.value >= 0 and packet.value <= 255 and packet.mouse == null and !packet.reset) {
                if (packet.value == 3) return deliveredInterrupt();
                return .{ .event = packet };
            }
            deferred_packets[(deferred_head + deferred_length) % deferred_packets.len] = packet;
            deferred_length += 1;
        }
        try host_input.takePresentationError();
        if (!host_input.isRaw()) return error.HostFailed;
        if (builtin.os.tag != .windows) {
            var descriptors = [_]std.c.pollfd{.{ .fd = 0, .events = std.c.POLL.IN, .revents = 0 }};
            if (std.c.poll(&descriptors, 1, 0) > 0 and descriptors[0].revents & std.c.POLL.HUP != 0) return .eof;
        }
        return .timeout;
    }
    if (builtin.os.tag == .windows and managedReader(forth.stdin_fileid)) {
        var byte: [1]u8 = undefined;
        const result = try readerProbe(forth.stdin_fileid, &byte);
        if (result.count != 0) return .{ .event = .{ .value = byte[0] } };
        if (result.ior != 0) return .{ .failure = result.ior };
        return if (result.eof) .eof else .timeout;
    }
    if (builtin.os.tag != .windows) {
        const c = @import("c_file");
        const flags = fcntl(0, c.F_GETFL);
        if (flags < 0 or fcntl(0, c.F_SETFL, @as(c_int, flags | c.O_NONBLOCK)) < 0) return .{ .failure = lastIor() };
        var byte: [1]u8 = undefined;
        clearErrno();
        const count = std.c.read(0, &byte, 1);
        const read_errno = std.c._errno().*;
        if (fcntl(0, c.F_SETFL, flags) < 0) {
            const ior = lastIor();
            if (count == 1) try terminalUnreadChecked(null, byte[0]);
            return .{ .failure = ior };
        }
        if (count == 1) return .{ .event = .{ .value = byte[0] } };
        if (count == 0) return .eof;
        if (read_errno == c.EAGAIN) return .timeout;
        if (read_errno == c.EINTR) return .restart;
        return .{ .failure = forth.errnoIor(if (read_errno == 0) errno_io else read_errno) };
    }
    if (!redirectedInputReady()) return .timeout;
    clearErrno();
    const byte = rawStandardInputByte();
    if (byte < 0) return if (std.c._errno().* == 0) .eof else .{ .failure = lastIor() };
    return .{ .event = .{ .value = byte } };
}

fn fileReadAvailable(_: ?*anyopaque, id: forth.Cell, destination: []u8) forth.RuntimeError!io_types.AvailableResult {
    try inputError(null);
    const checked = fileIoCheck(null, id, false);
    if (checked != 0) return .{ .ior = checked };
    if (destination.len == 0) return .{ .eof = if (id == forth.stdin_fileid) stdin_eof else file_slots[fileSlot(id)].eof and file_slots[fileSlot(id)].input.length == 0 };
    var count: usize = 0;
    while (count < destination.len) {
        if (id != forth.stdin_fileid) {
            if (file_slots[fileSlot(id)].input.takeByte()) |byte| {
                destination[count] = byte;
                count += 1;
                continue;
            }
        }
        const result = (if (id == forth.stdin_fileid) stdinProbeByte() else filePollByte(id)) catch |err| {
            if (count == 0) return err;
            if (err == error.UserInterrupt) {
                latchInput(err);
                return .{ .count = count };
            }
            return .{ .count = count, .ior = forth.errnoIor(errno_io) };
        };
        switch (result) {
            .event => |packet| {
                destination[count] = @intCast(packet.value);
                count += 1;
            },
            .eof => {
                if (id == forth.stdin_fileid) stdin_eof = true;
                return .{ .count = count, .eof = true };
            },
            .failure => |ior| return .{ .count = count, .ior = ior },
            else => return .{ .count = count },
        }
    }
    return .{ .count = count, .eof = fileEof(null, id).value != 0 };
}

fn writerIor(code: u32) forth.Cell {
    return switch (code) {
        0 => 0,
        109, 232 => forth.errnoIor(32),
        995 => forth.errnoIor(4),
        else => forth.errnoIor(errno_io),
    };
}

fn managedWriter(id: forth.Cell) bool {
    if (builtin.os.tag == .windows) {
        if (id == forth.stdout_fileid) return stdout_writer.active();
        if (id == forth.stderr_fileid) return stderr_writer.active();
        if (id < forth.first_file_id) return false;
        return file_slots[fileSlot(id)].writer.active();
    }
    return false;
}

fn writerForId(id: forth.Cell) *file_reader.Writer {
    if (id == forth.stdout_fileid) return &stdout_writer;
    if (id == forth.stderr_fileid) return &stderr_writer;
    return &file_slots[fileSlot(id)].writer;
}

fn stdoutWorkerWrite(bytes: []const u8) file_reader.Result {
    var count: usize = 0;
    var native_error: c_ulong = 0;
    const ior = sigma_write_stdout(bytes.ptr, bytes.len, &count, &native_error);
    return .{ .count = count, .code = if (ior == 0) 0 else if (native_error == 995) 995 else if (ior == 32) 109 else 5 };
}

fn ensureWriter(id: forth.Cell) forth.RuntimeError!void {
    if (builtin.os.tag == .windows) {
        const handle = ioNativeHandle(id) orelse return error.HostFailed;
        if (GetFileType(handle) != 3) return;
        const writer = writerForId(id);
        if (writer.active()) return;
        if (id == forth.stdout_fileid) writer.write_callback = stdoutWorkerWrite;
        try writer.start(handle, try ioWake());
    }
}

fn drainWriter(id: forth.Cell) forth.RuntimeError!forth.Cell {
    if (builtin.os.tag == .windows) {
        if (!managedWriter(id)) return 0;
        const guard = @import("host_wait.zig");
        try guard.beginInput();
        var guarded = true;
        defer if (guarded) {
            guard.endInput() catch {};
        };
        const wake = try ioWake();
        const writer = writerForId(id);
        while (true) {
            if (guard.inputInterrupted()) return deliveredInterrupt();
            const observed = wake.observe();
            const state = writer.peek();
            if (state.code != 0 or state.count == 0) {
                guarded = false;
                try guard.endInput();
                return writerIor(state.code);
            }
            const deadline = try @import("core/runtime_base.zig").Deadline.afterMilliseconds(try @import("host_clock.zig").now(), 20);
            _ = try wake.wait(observed, deadline, null);
        }
    }
    return 0;
}

fn nonblockingDescriptorWrite(descriptor: c_int, bytes: []const u8) forth.RuntimeError!forth.FileResult {
    if (builtin.os.tag == .windows) return error.HostUnavailable;
    const c = @import("c_file");
    const flags = fcntl(descriptor, c.F_GETFL);
    if (flags < 0 or fcntl(descriptor, c.F_SETFL, @as(c_int, flags | c.O_NONBLOCK)) < 0) return .{ .ior = lastIor() };
    var scope = PipeSignalScope.begin(true) catch {
        _ = fcntl(descriptor, c.F_SETFL, flags);
        return .{ .ior = forth.errnoIor(errno_io) };
    };
    clearErrno();
    const written = std.c.write(descriptor, bytes.ptr, bytes.len);
    const read_errno = std.c._errno().*;
    var ior: forth.Cell = if (written >= 0 or read_errno == c.EAGAIN or read_errno == c.EINTR) 0 else forth.errnoIor(if (read_errno == 0) errno_io else read_errno);
    if (fcntl(descriptor, c.F_SETFL, flags) < 0) ior = lastIor();
    if (!scope.end() and ior == 0) ior = forth.errnoIor(errno_io);
    return .{ .value = if (written < 0) 0 else @intCast(written), .ior = ior };
}

fn pumpOutputNonblocking() forth.RuntimeError!forth.Cell {
    if (output_used == 0) return output_ior;
    const result = if (builtin.os.tag == .windows) result: {
        try ensureWriter(forth.stdout_fileid);
        const sent = stdout_writer.write(output_buffer[0..output_used]);
        break :result forth.FileResult{ .value = sent.count, .ior = writerIor(sent.code) };
    } else try nonblockingDescriptorWrite(1, output_buffer[0..output_used]);
    const count: usize = @intCast(result.value);
    std.mem.copyForwards(u8, output_buffer[0 .. output_used - count], output_buffer[count..output_used]);
    output_used -= count;
    if (result.ior != 0) output_ior = result.ior;
    return result.ior;
}

fn fileWriteAvailable(_: ?*anyopaque, id: forth.Cell, bytes: []const u8) forth.RuntimeError!forth.FileResult {
    try inputError(null);
    const checked = fileIoCheck(null, id, true);
    if (checked != 0) return .{ .ior = checked };
    if (id == forth.stdout_fileid and bytes.len != 0 and builtin.os.tag != .windows) output_nonblocking = true;
    if (bytes.len == 0) {
        if (id == forth.stdout_fileid and output_ior != 0) return .{ .ior = output_ior };
        if (builtin.os.tag == .windows and managedWriter(id)) return .{ .ior = writerIor(writerForId(id).peek().code) };
        return .{};
    }
    if (builtin.os.tag == .windows) {
        try ensureWriter(id);
        if (managedWriter(id)) {
            if (id == forth.stdout_fileid) {
                const pending = try pumpOutputNonblocking();
                if (pending != 0 or output_used != 0) return .{ .ior = pending };
            }
            const result = writerForId(id).write(bytes);
            return .{ .value = result.count, .ior = writerIor(result.code) };
        }
    }
    if (id == forth.stdout_fileid) {
        if (builtin.os.tag == .windows) {
            flushOutput();
            const result = stdoutWorkerWrite(bytes);
            return .{ .value = result.count, .ior = writerIor(result.code) };
        }
        const prior = try pumpOutputNonblocking();
        if (prior != 0 or output_used != 0) return .{ .ior = prior };
        return nonblockingDescriptorWrite(1, bytes);
    }
    if (id == forth.stderr_fileid) {
        if (builtin.os.tag == .windows) {
            const ok = writeStandardErrorDirect(bytes);
            return .{ .value = if (ok) bytes.len else 0, .ior = if (ok) 0 else forth.errnoIor(errno_io) };
        }
        return nonblockingDescriptorWrite(2, bytes);
    }
    const file = openedFile(id).?;
    const prepared = prepareFileWrite(id, file);
    if (prepared != 0) return .{ .ior = prepared };
    if (builtin.os.tag != .windows and file_slots[fileSlot(id)].native_pipe) return nonblockingDescriptorWrite(file_number(file), bytes);
    clearErrno();
    const written = fwrite(bytes.ptr, 1, bytes.len, file);
    return .{ .value = written, .ior = if (written == bytes.len) 0 else lastIor() };
}

fn writableProbe(id: forth.Cell) forth.RuntimeError!forth.FileResult {
    if (builtin.os.tag == .windows) {
        if (!managedWriter(id)) return .{ .value = 1 };
        const state = writerForId(id).peek();
        const reserved = if (id == forth.stdout_fileid) output_used else 0;
        return .{ .value = @intFromBool(state.code != 0 or file_reader.Writer.capacity - state.count > reserved), .ior = writerIor(state.code) };
    }
    if (id == forth.stdout_fileid and output_used != 0) {
        const ior = try pumpOutputNonblocking();
        if (ior != 0 or output_used != 0) return .{ .ior = ior };
    }
    var descriptors = [_]std.c.pollfd{.{ .fd = ioDescriptor(id).?, .events = std.c.POLL.OUT, .revents = 0 }};
    if (std.c.poll(&descriptors, 1, 0) < 0) return .{ .ior = lastIor() };
    const events = descriptors[0].revents;
    if (events & std.c.POLL.NVAL != 0) return .{ .value = 1, .ior = badFileIor() };
    if (events & (std.c.POLL.ERR | std.c.POLL.HUP) != 0) return .{ .value = 1, .ior = forth.errnoIor(32) };
    return .{ .value = @intFromBool(events & std.c.POLL.OUT != 0) };
}

fn fileWaitFiles(_: ?*anyopaque, ids: []const forth.Cell, milliseconds: i64, writing: bool) forth.RuntimeError!io_types.FileWaitResult {
    try inputError(null);
    if (ids.len == 0 or ids.len > 64) return .{ .ior = forth.errnoIor(forth.errno_invalid) };
    for (ids, 0..) |id, index| {
        const ior = fileIoCheck(null, id, writing);
        if (ior != 0) return .{ .index = @intCast(index), .ior = ior };
    }
    for (ids) |id| {
        if (writing) {
            try ensureWriter(id);
        } else if (milliseconds != 0 or managedReader(id)) {
            try ensureReader(id);
        }
    }
    const guard = @import("host_wait.zig");
    try guard.beginInput();
    var guarded = true;
    defer if (guarded) {
        guard.endInput() catch {};
    };
    const clock = @import("host_clock.zig").clock;
    const deadline = try @import("core/runtime_base.zig").Deadline.afterMilliseconds(try clock.now(), milliseconds);
    const wake: ?*@import("host_wake.zig").Wake = if (builtin.os.tag == .windows) try ioWake() else null;
    while (true) {
        if (guard.inputInterrupted()) return deliveredInterrupt();
        const observed = if (wake) |value| value.observe() else 0;
        for (ids, 0..) |id, index| {
            if (writing) {
                const ready = try writableProbe(id);
                if (ready.value != 0 or ready.ior != 0) {
                    guarded = false;
                    try guard.endInput();
                    return .{ .index = @intCast(index), .ior = ready.ior };
                }
                continue;
            }
            var result: file_event.Result = .timeout;
            if (id != forth.stdin_fileid and file_slots[fileSlot(id)].input.length != 0) {
                result = .{ .event = .{ .value = file_slots[fileSlot(id)].input.bytes[0] } };
            } else {
                result = if (id == forth.stdin_fileid) try stdinProbeByte() else try filePollByte(id);
                if (result == .event) {
                    const byte: u8 = @intCast(result.event.value);
                    if (id == forth.stdin_fileid) try terminalUnreadChecked(null, byte) else try file_slots[fileSlot(id)].input.putByte(byte);
                }
            }
            if (result != .timeout and result != .restart) {
                guarded = false;
                try guard.endInput();
                return .{ .index = @intCast(index), .ior = if (result == .failure) result.failure else 0 };
            }
        }
        const now = try clock.now();
        if (milliseconds == 0 or deadline.expired(now)) {
            guarded = false;
            try guard.endInput();
            return .{};
        }
        const remaining = deadline.remainingMilliseconds(now, 20);
        if (builtin.os.tag == .windows) {
            const value = wake.?;
            const slice = try @import("core/runtime_base.zig").Deadline.afterMilliseconds(now, remaining);
            _ = try value.wait(observed, slice, null);
        } else {
            var descriptors: [64]std.c.pollfd = undefined;
            for (descriptors[0..ids.len], ids) |*descriptor, id| descriptor.* = .{ .fd = ioDescriptor(id).?, .events = if (writing) std.c.POLL.OUT else std.c.POLL.IN, .revents = 0 };
            if (std.c.poll(descriptors[0..ids.len].ptr, @intCast(ids.len), @intCast(remaining)) < 0 and std.c._errno().* != @backingInt(std.c.E.INTR)) return error.HostFailed;
        }
    }
}

/// One nonblocking byte from the C stream, including its private stdio buffer.
/// EOF is recorded only for a real zero-byte read, never EAGAIN.
fn filePollByte(fileid: forth.Cell) forth.RuntimeError!file_event.Result {
    const file = openedFile(fileid) orelse return .{ .failure = badFileIor() };
    const slot = fileSlot(fileid);
    if (managedReader(fileid)) {
        var byte: [1]u8 = undefined;
        const result = try readerProbe(fileid, &byte);
        if (result.count != 0) return .{ .event = .{ .value = byte[0] } };
        if (result.ior != 0) return .{ .failure = result.ior };
        if (result.eof) {
            file_slots[slot].eof = true;
            return .eof;
        }
        return .timeout;
    }
    if (file_slots[slot].eof) return .eof;
    clearErrno();
    if (builtin.os.tag == .windows) {
        const native = _get_osfhandle(file_number(file));
        if (native == -1) return .{ .failure = badFileIor() };
        const handle: *anyopaque = @ptrFromInt(@as(usize, @bitCast(native)));
        switch (GetFileType(handle)) {
            1 => {},
            3 => {
                var available: u32 = 0;
                if (PeekNamedPipe(handle, null, 0, null, &available, null) == 0) {
                    if (GetLastError() != 109) return .{ .failure = forth.errnoIor(errno_io) };
                    file_slots[slot].eof = true;
                    return .eof;
                } else if (available == 0) return .timeout;
                const result = try directPipeByte(fileid);
                if (result.ior != 0) return .{ .failure = result.ior };
                return if (result.byte) |byte| .{ .event = .{ .value = byte } } else .eof;
            },
            else => return .{ .failure = forth.errnoIor(forth.errno_invalid) },
        }
    }
    const prepared = prepareFileRead(fileid, file);
    if (prepared != 0) return .{ .failure = prepared };
    const old_flags = if (builtin.os.tag == .windows) 0 else fcntl(file_number(file), @import("c_file").F_GETFL);
    if (builtin.os.tag != .windows) {
        if (old_flags < 0 or fcntl(file_number(file), @import("c_file").F_SETFL, @as(c_int, old_flags | @import("c_file").O_NONBLOCK)) < 0) return .{ .failure = lastIor() };
    }
    var raw_byte: [1]u8 = undefined;
    const raw_count = if (builtin.os.tag != .windows and file_slots[slot].native_pipe) std.c.read(file_number(file), &raw_byte, 1) else -2;
    const byte: c_int = if (raw_count == -2) getc(file) else if (raw_count == 1) raw_byte[0] else -1;
    const failed = if (raw_count == -2) ferror(file) != 0 else raw_count < 0;
    const read_errno = std.c._errno().*;
    const ended = if (raw_count == -2) feof(file) != 0 else raw_count == 0;
    if (byte < 0) clearerr(file);
    const restored = builtin.os.tag == .windows or fcntl(file_number(file), @import("c_file").F_SETFL, @as(c_int, old_flags)) >= 0;
    if (!restored or (builtin.is_test and test_file_restore_failure)) {
        // Keep a successfully fetched byte even if restoring descriptor flags failed.
        if (byte >= 0) {
            const decoder = &file_slots[slot].input;
            if (decoder.length == decoder.bytes.len) return error.HostFailed;
            decoder.bytes[decoder.length] = @intCast(byte);
            decoder.length += 1;
        }
        return .{ .failure = if (builtin.is_test and test_file_restore_failure) forth.errnoIor(errno_io) else lastIor() };
    }
    if (byte >= 0) return .{ .event = .{ .value = byte } };
    if (failed) {
        if (builtin.os.tag != .windows and (read_errno == @import("c_file").EAGAIN or read_errno == @import("c_file").EINTR)) return .timeout;
        return .{ .failure = forth.errnoIor(if (read_errno == 0) errno_io else read_errno) };
    }
    if (ended) {
        file_slots[slot].eof = true;
        return .eof;
    }
    return .timeout;
}

fn fileReady(_: ?*anyopaque, fileid: forth.Cell) forth.RuntimeError!forth.FileResult {
    flushOutput();
    if (fileid == forth.stdin_fileid) {
        const previous_eof = stdin_eof;
        defer stdin_eof = previous_eof;
        if (try fileStdinByte(false)) |byte| {
            terminalUnread(null, byte);
            return .{ .value = 1 };
        }
        return .{};
    }
    _ = openedFile(fileid) orelse return .{ .ior = badFileIor() };
    const slot = fileSlot(fileid);
    if (file_slots[slot].input.length != 0) return .{ .value = 1 };
    // A readiness query does not commit semantic EOF.
    const previous_eof = file_slots[slot].eof;
    defer file_slots[slot].eof = previous_eof;
    return switch (try filePollByte(fileid)) {
        .event => |packet| blk: {
            try file_slots[slot].input.putByte(@intCast(packet.value));
            break :blk .{ .value = 1 };
        },
        .failure => |ior| .{ .ior = ior },
        else => .{},
    };
}

const FileWaitSource = struct {
    id: forth.Cell,
    fn read(context: ?*anyopaque, milliseconds: i32) forth.RuntimeError!file_event.Result {
        const self: *FileWaitSource = @ptrCast(@alignCast(context.?));
        const clock = @import("host_clock.zig").clock;
        const deadline = try @import("core/runtime_base.zig").Deadline.afterMilliseconds(try clock.now(), milliseconds);
        while (true) {
            if (@import("host_wait.zig").inputInterrupted()) return deliveredInterrupt();
            const wake = if (managedReader(self.id)) try ioWake() else null;
            const observed = if (wake) |value| value.observe() else 0;
            const result = try filePollByte(self.id);
            if (result != .timeout) return result;
            if (milliseconds == 0 or deadline.expired(try clock.now())) return .timeout;
            if (wake) |value| {
                const now = try clock.now();
                const slice = try @import("core/runtime_base.zig").Deadline.afterMilliseconds(now, deadline.remainingMilliseconds(now, 20));
                _ = try value.wait(observed, slice, null);
            } else try sleepMilliseconds(null, 1);
        }
    }
};

fn fileEventWait(_: ?*anyopaque, fileid: forth.Cell, milliseconds: i64) forth.RuntimeError!file_event.Result {
    _ = openedFile(fileid) orelse return .{ .failure = badFileIor() };
    if (milliseconds != 0 and fileIoCheck(null, fileid, false) == 0) try ensureReader(fileid);
    var source = FileWaitSource{ .id = fileid };
    const callbacks = file_event.Source{ .context = &source, .read_fn = FileWaitSource.read, .clock = @import("host_clock.zig").clock, .controls = false, .interrupts = false };
    const guard = @import("host_wait.zig");
    try guard.beginInput();
    var guarded = true;
    defer if (guarded) {
        guard.endInput() catch {};
    };
    // Peek until cleanup succeeds: an interrupt or cleanup failure cannot consume
    // a completed character which the caller never receives.
    const result = try file_event.read(&file_slots[fileSlot(fileid)].input, callbacks, milliseconds, true);
    guarded = false;
    try guard.endInput();
    if (builtin.is_test and test_file_commit_interrupt) return deliveredInterrupt();
    return switch (result) {
        .event, .eof => file_event.read(&file_slots[fileSlot(fileid)].input, callbacks, 0, false),
        else => result,
    };
}

/// Shared ahead/pending bytes precede new raw input. Only terminal Ctrl+C is an
/// interrupt: redirected byte 3 remains ordinary binary input.
fn fileStdinByte(wait: bool) forth.RuntimeError!?u8 {
    output_cursor.unknown();
    while (true) {
        const byte: ?u8 = if (popLookahead()) |ahead| ahead else if (host_input.takePendingByte()) |queued| queued else next: {
            if (builtin.os.tag == .windows) if (utf8_console.takePendingByte()) |pending| break :next pending;
            if (host_input.input_is_terminal) {
                if (host_input.nextByte()) |raw| break :next raw;
                try host_input.takePresentationError();
                if (!host_input.isRaw()) return error.HostFailed;
                if (builtin.os.tag != .windows) {
                    var descriptor = [_]std.c.pollfd{.{ .fd = 0, .events = std.c.POLL.IN, .revents = 0 }};
                    if (std.c.poll(&descriptor, 1, 0) > 0 and descriptor[0].revents & std.c.POLL.HUP != 0) {
                        if (wait) stdin_eof = true;
                        return null;
                    }
                }
                break :next null;
            }
            if (wait and managedReader(forth.stdin_fileid)) {
                const result = try readerByte(forth.stdin_fileid);
                if (result.ior != 0) return error.HostFailed;
                if (result.byte == null) stdin_eof = true;
                return result.byte;
            }
            if (!redirectedInputReady()) break :next null;
            clearErrno();
            const read = rawStandardInputByte();
            if (read < 0) {
                if (std.c._errno().* != 0) {
                    if (builtin.os.tag != .windows and std.c._errno().* == @backingInt(std.c.E.INTR)) break :next null;
                    return error.HostFailed;
                }
                if (wait) stdin_eof = true;
                return null;
            }
            break :next @intCast(read);
        };
        if (byte) |value| {
            if (host_input.input_is_terminal and value == 3) return deliveredInterrupt();
            if (wait) stdin_eof = false;
            return value;
        }
        if (!wait) return null;
        try sleepMilliseconds(null, 1);
    }
}

fn processStart(context: ?*anyopaque, program: []const u8, script: []const u8) forth.RuntimeError!void {
    try flushProcessOutput();
    try pauseStdinReader();
    host_process.bind(.{ .context = context, .launch = tclLaunch, .raw = tclRaw, .close = tclClose, .status = tclStatus, .signal = tclSignal, .wait = tclWait, .free = tclFree });
    try host_process.start(context, program, script);
}

fn tclLaunch(context: ?*anyopaque, program: []const u8, script: []const u8, timeout: u32) forth.FileResult {
    const registry = processRegistry(context) catch return .{ .ior = -21 };
    const created = registry.create(true);
    if (created.ior != 0) return created;
    const id: forth.Cell = @bitCast(created.value);
    for ([_][]const u8{ program, script }) |argument| {
        const result = registry.text(id, true, .argument, argument);
        if (result != 0) return .{ .value = created.value, .ior = result };
    }
    const mode_error = registry.setIo(id, true, 2, if (builtin.os.tag == .windows) 2 else 1);
    if (mode_error != 0) return .{ .value = created.value, .ior = mode_error };
    return .{ .value = created.value, .ior = registry.startWithin(id, true, timeout) };
}
fn tclRaw(_: ?*anyopaque, id: forth.Cell, which: u2) isize {
    const registry = if (processes) |*value| value else return -1;
    const stream = registry.internalStream(id, which, false) orelse return -1;
    const fd = file_number(stream);
    return if (builtin.os.tag == .windows) _get_osfhandle(fd) else fd;
}
fn tclClose(_: ?*anyopaque, id: forth.Cell) forth.Cell {
    const registry = if (processes) |*value| value else return badFileIor();
    var first: forth.Cell = 0;
    for (0..3) |which| if (registry.internalStream(id, @intCast(which), true)) |stream| {
        clearErrno();
        if (fclose(stream) != 0 and first == 0) first = lastIor();
    };
    return first;
}
fn tclDetach(_: ?*anyopaque, id: forth.Cell) forth.Cell {
    host_process.detachInternal(id);
    return 0;
}
fn tclReleased(_: ?*anyopaque, id: forth.Cell) void {
    host_process.releasedInternal(id);
}
fn tclStatus(_: ?*anyopaque, id: forth.Cell) forth.ProcessStatus {
    return if (processes) |*registry| registry.status(id, true) else .{ .ior = badFileIor() };
}
fn tclSignal(_: ?*anyopaque, id: forth.Cell, force: bool) forth.Cell {
    return if (processes) |*registry| registry.signal(id, true, force) else badFileIor();
}
fn tclWait(_: ?*anyopaque, id: forth.Cell, milliseconds: u32) forth.Cell {
    return if (processes) |*registry| registry.waitSlice(id, true, milliseconds) else badFileIor();
}
fn tclFree(_: ?*anyopaque, id: forth.Cell, timeout: u32) forth.Cell {
    return if (processes) |*registry| registry.freeWithin(id, true, timeout) else badFileIor();
}

const process_registry_module = @import("host_process_registry.zig");
const process_native = @import("host_process_native.zig");
var processes: ?process_registry_module.Registry = null;
var next_process_id: forth.Cell = @import("host_process_table.zig").first_id;
var process_cleanup_error: forth.Cell = 0;
var audio_cleanup_failed = false;
var test_process_publish_fail_after: ?usize = null;
var test_process_published: usize = 0;
var test_process_close_error: bool = false;
fn processFileRoom(_: ?*anyopaque, count: usize) bool {
    var available: usize = 0;
    for (file_slots) |slot| if (slot.stream == null) {
        available += 1;
    };
    return available >= count;
}
fn processFilePublish(_: ?*anyopaque, owner: forth.Cell, which: u2, stream: *anyopaque) forth.FileResult {
    if (builtin.is_test) if (test_process_publish_fail_after) |limit| {
        if (test_process_published == limit) return .{ .ior = forth.errnoIor(errno_io) };
        test_process_published += 1;
    };
    const slot = for (&file_slots, 0..) |*entry, index| {
        if (entry.stream == null) break index;
    } else return .{ .ior = forth.errnoIor(errno_too_many_files) };
    file_slots[slot] = .{ .stream = stream, .native_pipe = true, .proc_owner = owner, .access = if (which == 0) .write_only else .read_only };
    return .{ .value = @intCast(forth.first_file_id + @as(forth.Cell, @intCast(slot))) };
}
fn processFileBelongs(_: ?*anyopaque, owner: forth.Cell, id: forth.Cell) bool {
    _ = openedFile(id) orelse return false;
    return file_slots[fileSlot(id)].proc_owner == owner;
}
fn processFileDiscard(_: ?*anyopaque, owner: forth.Cell, id: forth.Cell) forth.Cell {
    if (!processFileBelongs(null, owner, id)) return 0;
    const slot = &file_slots[fileSlot(id)];
    if (builtin.os.tag == .windows) {
        slot.writer.deinit() catch return forth.errnoIor(errno_io);
        slot.reader.deinit() catch return forth.errnoIor(errno_io);
    }
    const stream = slot.stream.?;
    slot.* = .{};
    clearErrno();
    const result = if (fclose(stream) == 0) @as(forth.Cell, 0) else lastIor();
    if (builtin.is_test and test_process_close_error) {
        test_process_close_error = false;
        return forth.errnoIor(errno_io);
    }
    return result;
}
fn processRegistry(context: ?*anyopaque) forth.RuntimeError!*process_registry_module.Registry {
    if (!process_native.available) return error.HostUnavailable;
    if (processes == null) {
        const host: *HostContext = @ptrCast(@alignCast(context orelse return error.HostUnavailable));
        processes = process_registry_module.Registry.init(host.allocator, host.environ_map, .{ .room = processFileRoom, .publish = processFilePublish, .belongs = processFileBelongs, .discard = processFileDiscard, .stop_internal = tclDetach, .released_internal = tclReleased });
        processes.?.table.next_id = next_process_id;
    }
    return &processes.?;
}
fn procNew(context: ?*anyopaque) forth.FileResult {
    const registry = processRegistry(context) catch return .{ .ior = -21 };
    return registry.create(false);
}
fn procText(context: ?*anyopaque, id: forth.Cell, kind: forth.ProcessText, text: []const u8) forth.Cell {
    const registry = processRegistry(context) catch return -21;
    return registry.text(id, false, kind, text);
}
fn procIo(context: ?*anyopaque, id: forth.Cell, which: forth.Cell, mode: forth.Cell) forth.Cell {
    const registry = processRegistry(context) catch return -21;
    return registry.setIo(id, false, which, mode);
}
fn procLaunch(context: ?*anyopaque, id: forth.Cell) forth.RuntimeError!forth.Cell {
    const registry = try processRegistry(context);
    const entry = registry.table.getPublic(id) catch return badFileIor();
    const config = entry.editable() catch return forth.errnoIor(16);
    if (config.arguments.items.len == 0) return forth.errnoIor(forth.errno_invalid);
    try flushProcessOutput();
    try pauseStdinReader();
    return registry.start(id, false);
}
fn procStream(context: ?*anyopaque, id: forth.Cell, which: u2) forth.FileResult {
    const registry = processRegistry(context) catch return .{ .ior = -21 };
    return registry.stream(id, false, which);
}
fn procStatus(context: ?*anyopaque, id: forth.Cell) forth.ProcessStatus {
    const registry = processRegistry(context) catch return .{ .ior = -21 };
    return registry.status(id, false);
}
fn procWait(context: ?*anyopaque, id: forth.Cell, milliseconds: i64) forth.RuntimeError!forth.ProcessStatus {
    const registry = try processRegistry(context);
    const guard = @import("host_wait.zig");
    try guard.beginInput();
    var active = true;
    defer if (active) {
        guard.endInput() catch {};
    };
    const clock = @import("host_clock.zig");
    const deadline = try @import("core/runtime_base.zig").Deadline.afterMilliseconds(try clock.now(), milliseconds);
    while (true) {
        if (guard.inputInterrupted()) return deliveredInterrupt();
        const result = registry.status(id, false);
        const now = try clock.now();
        if (result.state != 1 or result.ior != 0 or milliseconds == 0 or deadline.expired(now)) {
            active = false;
            try guard.endInput();
            return result;
        }
        const slice = deadline.remainingMilliseconds(now, if (builtin.os.tag == .windows) 20 else 10);
        const wait_error = registry.waitSlice(id, false, slice);
        if (wait_error != 0 and wait_error != forth.errnoIor(4)) {
            active = false;
            try guard.endInput();
            return .{ .state = result.state, .code = result.code, .ior = wait_error };
        }
    }
}
fn procSignal(context: ?*anyopaque, id: forth.Cell, force: bool) forth.Cell {
    const registry = processRegistry(context) catch return -21;
    return registry.signal(id, false, force);
}
fn procFree(context: ?*anyopaque, id: forth.Cell) forth.Cell {
    const registry = processRegistry(context) catch return -21;
    return registry.free(id, false);
}
fn closeAllProcesses() forth.Cell {
    const registry = if (processes) |*value| value else return 0;
    const result = registry.shutdown();
    next_process_id = registry.table.next_id;
    if (!registry.hasResources()) {
        registry.table.deinit();
        processes = null;
    }
    if (result != 0) {
        process_cleanup_error = result;
        var message: [128]u8 = undefined;
        _ = writeStandardError(std.fmt.bufPrint(&message, "error: process cleanup returned {d}\n", .{result}) catch "error: process cleanup failed\n");
    }
    return result;
}
const process_ops: forth.ProcessOps = .{ .new = procNew, .text = procText, .io = procIo, .start = procLaunch, .stream = procStream, .status = procStatus, .wait = procWait, .signal = procSignal, .free = procFree };

const host_directories = @import("host_directories.zig");
const file_ops = forth.FileOps{ .realpath = if (host_fs.supported) host_fs.realpath else null, .release_realpath = if (host_fs.supported) host_fs.release else null, .metadata = if (host_fs.supported) host_fs.metadata else null, .sync = if (host_fs.supported) fileSync else null, .io_check = fileIoCheck, .wait_files = fileWaitFiles, .read_available = fileReadAvailable, .write_available = fileWriteAvailable, .event_wait = fileEventWait, .open_pipe = fileOpenPipe, .close_pipe = fileClosePipe, .open_dir = host_directories.open, .read_dir = host_directories.read, .close_dir = host_directories.close, .mkdir = makeDirectory, .get_dir = getDirectory, .set_dir = setDirectory, .user_home = userHome, .open = fileOpen, .close = fileClose, .read_line = fileReadLine, .read = fileRead, .write = fileWrite, .size = fileSize, .reposition = fileReposition, .position = filePosition, .resize = fileResize, .flush = fileFlush, .delete = fileDelete, .rename = fileRename, .status = fileStatus, .key = fileKey, .unread = fileUnread, .ready = fileReady, .eof = fileEof, .create_mode = fileCreateMode };

/// Lets the Windows console interpret the ANSI sequences written by PAGE.
fn enableVirtualTerminal() bool {
    if (builtin.os.tag == .windows) {
        const std_output_handle: u32 = @bitCast(@as(i32, -11));
        const handle = GetStdHandle(std_output_handle) orelse return false;
        var mode: u32 = 0;
        if (GetConsoleMode(handle, &mode) == 0) return false;
        return SetConsoleMode(handle, mode | std.os.windows.ENABLE_VIRTUAL_TERMINAL_PROCESSING) != 0;
    }
    return output_is_terminal;
}

/// Strings are UTF-8, so a Windows console shows and gives text in UTF-8 for the whole
/// session: the output code page becomes UTF-8 (65001) and is put back at the end, also
/// when Ctrl+C ends the program; a console's input is read as UTF-16 with ReadConsoleW
/// and turned into UTF-8, as the C library would give it in text mode (CR LF as LF, a
/// line that starts with Ctrl+Z as the end of the input).
const utf8_console = if (builtin.os.tag != .windows) struct {
    const active = false;
    const input: ?*anyopaque = null;
    fn begin() void {}
    fn finish() void {}
    fn pause() void {}
    fn @"resume"() void {}
    fn readByte() c_int {
        const guarded = beginInputGuard() catch |err| {
            latchInput(err);
            return -1;
        };
        defer endInputGuard(guarded);
        if (@import("host_wait.zig").inputInterrupted()) {
            latchInput(error.UserInterrupt);
            return -1;
        }
        return -1;
    }
} else struct {
    extern "kernel32" fn SetConsoleCP(u32) callconv(.winapi) c_int;
    extern "kernel32" fn GetConsoleCP() callconv(.winapi) u32;
    extern "kernel32" fn ReadConsoleW(*anyopaque, [*]u16, u32, *u32, ?*anyopaque) callconv(.winapi) c_int;
    extern "kernel32" fn CreateFileW([*:0]const u16, u32, u32, ?*anyopaque, u32, u32, ?*anyopaque) callconv(.winapi) *anyopaque;
    extern "kernel32" fn CloseHandle(*anyopaque) callconv(.winapi) c_int;
    // A cancelled cooked read can remain pending in conhost. Closing our own
    // console handle also releases that server-side read, without closing stdin.
    var read_input: ?*anyopaque = null;
    var read_cancelled = false;
    fn closeReadInput() bool {
        if (read_input) |handle| {
            if (CloseHandle(handle) == 0) return false;
            read_input = null;
        }
        read_cancelled = false;
        return true;
    }
    extern "kernel32" fn SetConsoleCtrlHandler(?*const fn (u32) callconv(.winapi) c_int, c_int) callconv(.winapi) c_int;

    var active = false;
    var saved_output: u32 = 0;
    var saved_input: u32 = 0;
    /// Standard input, when it is a console.
    var input: ?*anyopaque = null;
    /// The UTF-16 units one ReadConsoleW reads at most.
    const units_per_read = 1024;
    /// UTF-8 bytes of the line read and not yet given. A unit gives at most 3 bytes, and
    /// a low surrogate whose high one came in the read before gives 4; each character is
    /// encoded into 4 bytes of room, so 4 bytes a unit always suffice.
    var bytes: [4 * units_per_read]u8 = undefined;
    var start: usize = 0;
    var end: usize = 0;
    var high_surrogate: u16 = 0;
    var ended = false;

    fn begin() void {
        const stdin_handle = GetStdHandle(@bitCast(@as(i32, -10)));
        var mode: u32 = 0;
        if (stdin_handle) |handle| {
            if (GetConsoleMode(handle, &mode) != 0) input = handle;
        }
        if (!output_is_terminal) return;
        saved_output = GetConsoleOutputCP();
        saved_input = GetConsoleCP();
        if (SetConsoleOutputCP(65001) == 0) return;
        _ = SetConsoleCP(65001);
        active = true;
        _ = SetConsoleCtrlHandler(&restoreOnSignal, 1);
    }

    fn finish() void {
        if (!closeReadInput()) _ = writeStandardError("console input cleanup failed\n");
        if (!active) return;
        flushOutput();
        _ = SetConsoleOutputCP(saved_output);
        _ = SetConsoleCP(saved_input);
        active = false;
    }

    /// A program that SYSTEM starts runs with the code pages the console had before, so
    /// that it shows its messages and its files as without Sigma.
    fn pause() void {
        if (!active) return;
        _ = SetConsoleOutputCP(saved_output);
        _ = SetConsoleCP(saved_input);
    }

    fn @"resume"() void {
        if (!active) return;
        _ = SetConsoleOutputCP(65001);
        _ = SetConsoleCP(65001);
    }

    /// Ctrl+C, Ctrl+Break, or the console closing: the code pages go back, and the
    /// default handling (the end of the program) follows.
    fn restoreOnSignal(_: u32) callconv(.winapi) c_int {
        if (active) {
            _ = SetConsoleOutputCP(saved_output);
            _ = SetConsoleCP(saved_input);
        }
        return 0;
    }

    /// The next byte of a console's input, or -1 at its end.
    fn takePendingByte() ?u8 {
        if (start == end) return null;
        const byte = bytes[start];
        start += 1;
        return byte;
    }

    fn readByte() c_int {
        const guarded = beginInputGuard() catch |err| {
            latchInput(err);
            return -1;
        };
        defer endInputGuard(guarded);
        if (@import("host_wait.zig").inputInterrupted()) {
            latchInput(error.UserInterrupt);
            return -1;
        }
        while (start == end) {
            if (ended) return -1;
            const filled = fill();
            if (!filled) {
                if (@import("host_wait.zig").inputInterrupted()) {
                    latchInput(error.UserInterrupt);
                    return -1;
                }
                if (input_failure != null) return -1;
                ended = true;
                return -1;
            }
        }
        const byte = bytes[start];
        start += 1;
        return byte;
    }

    fn fill() bool {
        var wide: [units_per_read]u16 = undefined;
        var read: u32 = 0;
        if (read_cancelled and !closeReadInput()) {
            latchInput(error.HostFailed);
            return false;
        }
        if (read_input == null) {
            const name = std.unicode.utf8ToUtf16LeStringLiteral("CONIN$");
            const handle = CreateFileW(name, 0xC0000000, 3, null, 3, 0, null);
            if (@intFromPtr(handle) == std.math.maxInt(usize)) {
                latchInput(error.HostFailed);
                return false;
            }
            read_input = handle;
        }
        @import("host_wait.zig").beginConsoleRead() catch |err| {
            latchInput(err);
            return false;
        };
        defer {
            // Stop the handler's cancellation loop before closing the handle.
            @import("host_wait.zig").endConsoleRead();
            if (@import("host_wait.zig").inputInterrupted()) {
                read_cancelled = true;
                if (!closeReadInput()) latchInput(error.HostFailed);
            }
        }
        if (@import("host_wait.zig").inputInterrupted()) return false;
        const success = ReadConsoleW(read_input.?, &wide, wide.len, &read, null) != 0;
        if (!success or read == 0) {
            if (@import("host_wait.zig").inputGuardActive()) {
                if (@import("host_wait.zig").awaitConsoleInterrupt()) {
                    latchInput(error.UserInterrupt);
                } else {
                    latchInput(error.HostFailed);
                }
            } else if (!success) latchInput(error.HostFailed);
            return false;
        }
        start = 0;
        end = 0;
        var at: usize = 0;
        if (wide[0] == 0x1A) return false;
        while (at < read) : (at += 1) {
            const unit = wide[at];
            if (unit == '\r' and at + 1 < read and wide[at + 1] == '\n') continue;
            var code: u21 = unit;
            if (unit >= 0xD800 and unit < 0xDC00) {
                high_surrogate = unit;
                continue;
            }
            if (unit >= 0xDC00 and unit < 0xE000) {
                if (high_surrogate == 0) continue;
                code = 0x10000 + ((@as(u21, high_surrogate) - 0xD800) << 10) + (unit - 0xDC00);
            }
            high_surrogate = 0;
            end += std.unicode.utf8Encode(code, bytes[end..][0..4]) catch continue;
        }
        return true;
    }
};

/// One byte of standard input: from the console as UTF-8, or from the C library.
fn standardInputByte() c_int {
    clearErrno();
    const byte = rawStandardInputByte();
    rememberStdinByte(byte);
    return byte;
}
fn rememberStdinByte(byte: c_int) void {
    if (byte >= 0) {
        stdin_eof = false;
    } else if (input_failure == null and !@import("host_wait.zig").inputInterrupted() and std.c._errno().* == 0) {
        stdin_eof = true;
    }
}

fn rawStandardInputByte() c_int {
    if (builtin.os.tag == .windows and managedReader(forth.stdin_fileid)) {
        const result = readerByte(forth.stdin_fileid) catch |err| {
            latchInput(err);
            std.c._errno().* = if (err == error.UserInterrupt) 4 else errno_io;
            return -1;
        };
        if (result.ior != 0) std.c._errno().* = errno_io;
        return if (result.byte) |byte| byte else -1;
    }
    if (builtin.os.tag == .windows and utf8_console.input != null) return utf8_console.readByte();
    if (!host_input.input_is_terminal) {
        var byte: [1]u8 = undefined;
        if (builtin.os.tag == .windows) {
            const handle = GetStdHandle(@bitCast(@as(i32, -10))) orelse {
                std.c._errno().* = forth.errno_bad_file;
                return -1;
            };
            while (true) {
                var count: u32 = 0;
                if (ReadFile(handle, &byte, 1, &count, null) == 0) {
                    const code = GetLastError();
                    if (code != 109 and code != 38) std.c._errno().* = errno_io; // broken pipe / EOF
                    return -1;
                }
                if (count == 1) return byte[0];
                if (GetFileType(handle) != 3) return -1;
            }
        }
        return if (std.c.read(0, &byte, 1) == 1) byte[0] else -1;
    }
    // POSIX terminal and EKEY must share the descriptor: getchar's read-ahead
    // would hide the rest of a canonical line from the raw EKEY reader.
    if (builtin.os.tag != .windows) {
        var byte: [1]u8 = undefined;
        while (true) {
            if (@import("host_wait.zig").inputGuardActive()) {
                // A bounded poll also catches SIGINT delivered just before read.
                if (@import("host_wait.zig").inputInterrupted()) return -1;
                var descriptor = [_]std.c.pollfd{.{ .fd = 0, .events = std.c.POLL.IN, .revents = 0 }};
                const ready = std.c.poll(&descriptor, 1, 20);
                if (@import("host_wait.zig").inputInterrupted()) return -1;
                if (ready == 0) continue;
                if (ready < 0) {
                    if (std.c._errno().* == @backingInt(std.c.E.INTR)) continue;
                    latchInput(error.HostFailed);
                    return -1;
                }
            }
            clearErrno();
            const count = std.c.read(0, &byte, 1);
            if (count == 1) return byte[0];
            if (count < 0 and std.c._errno().* == @backingInt(std.c.E.INTR)) {
                if (@import("host_wait.zig").inputInterrupted()) return -1;
                continue;
            }
            return -1;
        }
    }
    return getchar();
}

/// On Windows, piped or redirected standard input is read as bytes, as on the other
/// systems, so READ-FILE and KEY see CR, Ctrl+Z, and every other byte. A console keeps
/// text mode, where Enter gives a single LF to KEY.
fn useBinaryStdin() void {
    if (builtin.os.tag == .windows) {
        if (windows_stdin._isatty(0) == 0) _ = windows_stdin._setmode(0, windows_stdin.binary_mode);
    }
}

fn readU32(bytes: []const u8) u32 {
    return @as(u32, bytes[0]) | (@as(u32, bytes[1]) << 8) | (@as(u32, bytes[2]) << 16) | (@as(u32, bytes[3]) << 24);
}

fn readU64(bytes: []const u8) u64 {
    return @as(u64, readU32(bytes[0..4])) | (@as(u64, readU32(bytes[4..8])) << 32);
}

fn writeU32(bytes: []u8, value: u32) void {
    bytes[0] = @truncate(value);
    bytes[1] = @truncate(value >> 8);
    bytes[2] = @truncate(value >> 16);
    bytes[3] = @truncate(value >> 24);
}

fn writeU64(bytes: []u8, value: u64) void {
    writeU32(bytes[0..4], @truncate(value));
    writeU32(bytes[4..8], @truncate(value >> 32));
}

/// The image `SAVESYS` put at the end of the executable, in a new allocation; null when
/// there is none.
fn readEmbeddedImage(path: [:0]const u8, allocator: std.mem.Allocator) forth.RuntimeError!?[]u8 {
    const saved = @import("host_saved_image.zig");
    const file = fopen(path.ptr, "rb") orelse return error.InvalidImage;
    defer _ = fclose(file);
    if (seek64(file, 0, 2) != 0) return error.InvalidImage;
    const position = tell64(file);
    if (position < 0) return error.InvalidImage;
    const end: u64 = @intCast(position);
    if (end < saved.footer_size) return null;
    if (seek64(file, @intCast(end - saved.footer_size), 0) != 0) return error.InvalidImage;
    var bytes: [saved.footer_size]u8 = undefined;
    if (fread(&bytes, 1, bytes.len, file) != bytes.len) return error.InvalidImage;
    const info = (try saved.footer(&bytes, end)) orelse return null;
    if (seek64(file, @intCast(info.base_len), 0) != 0) return error.InvalidImage;
    const image = allocator.alloc(u8, info.image_len) catch return error.MemoryExhausted;
    errdefer allocator.free(image);
    if (fread(image.ptr, 1, image.len, file) != image.len) return error.InvalidImage;
    return image;
}

/// The sizes the command line asks for; null keeps the default. `next` is the index of
/// the first argument after them.
const StartOptions = struct {
    m: ?usize = null,
    l: ?usize = null,
    data_stack: ?usize = null,
    return_stack: ?usize = null,
    float_stack: ?usize = null,
    /// --max-steps: how many operations compiled code may run for each argument and each
    /// line of input; 0 is any number.
    max_steps: u64 = 0,
    /// --trace and --trace-limit: whether the words are shown as they start and end, and
    /// how many lines of that are shown; 0 is any number.
    trace: bool = false,
    trace_limit: u64 = 0,
    /// --profile: the calls and the operations of each word are shown at the end.
    profile: bool = false,
    /// --coverage: the operations are counted, for the words .COVER-RAW, COV%, and
    /// .COVERAGE; nothing is shown at the end.
    coverage: bool = false,
    /// --lint: the definitions of the files are checked when the arguments are done,
    /// and there is no interactive session.
    lint: bool = false,
    /// --format and --format-check: the files after the options are not run; their
    /// indentation is set, or only compared with what it would be set to.
    /// --format-indent is the number of blanks of one step.
    format: enum { none, write, check } = .none,
    format_indent: u64 = formatter.default_width,
    /// --debug-log: the file that the errors, the trace, and the profile are written
    /// to as lines of JSON.
    debug_log: ?[]const u8 = null,
    next: usize = 1,
    no_app: bool = false,
    layout_seen: bool = false,
};

const debug_log_option = "--debug-log";
const formatter = @import("format.zig");

/// --format and --format-check: sets the indentation of each file, or says whether it
/// is set. The files are read as text and not run. The exit status is 0, 1 when a
/// file cannot be read or written, and with --format-check 2 when a file is not as
/// --format would make it.
fn formatFiles(allocator: std.mem.Allocator, paths: []const []const u8, check: bool, width: usize) u8 {
    var status: u8 = 0;
    for (paths) |path| {
        const outcome = formatFile(allocator, path, check, width) catch {
            terminalWrite(null, path);
            terminalWrite(null, ": FILE ERROR !\n");
            status = 1;
            continue;
        };
        var text: [48]u8 = undefined;
        terminalWrite(null, path);
        if (outcome == 0) {
            terminalWrite(null, ": FORMATTED ALREADY\n");
        } else {
            terminalWrite(null, std.fmt.bufPrint(&text, ": {d} LINES {s}\n", .{ outcome, if (check) "TO FORMAT" else "FORMATTED" }) catch unreachable);
            if (check and status == 0) status = 2;
        }
    }
    flushOutput();
    return status;
}

/// Formats one file; gives the number of lines that change. The file is written only
/// when lines change and `check` is false, as bytes, so that its line ends stay.
fn formatFile(allocator: std.mem.Allocator, path: []const u8, check: bool, width: usize) !usize {
    var terminated_path: [4096:0]u8 = undefined;
    if (path.len >= terminated_path.len) return error.FileUnavailable;
    @memcpy(terminated_path[0..path.len], path);
    terminated_path[path.len] = 0;
    const source = blk: {
        const file = fopen(&terminated_path, "rb") orelse return error.FileUnavailable;
        defer _ = fclose(file);
        if (fseek(file, 0, 2) != 0) return error.FileUnavailable;
        const size = ftell(file);
        if (size < 0 or fseek(file, 0, 0) != 0) return error.FileUnavailable;
        const bytes = try allocator.alloc(u8, @intCast(size));
        errdefer allocator.free(bytes);
        if (fread(bytes.ptr, 1, bytes.len, file) != bytes.len) return error.FileUnavailable;
        break :blk bytes;
    };
    defer allocator.free(source);
    const result = try formatter.format(allocator, source, width);
    defer allocator.free(result.buffer);
    if (result.changed != 0 and !check) {
        const file = fopen(&terminated_path, "wb") orelse return error.FileUnavailable;
        defer _ = fclose(file);
        if (fwrite(result.text.ptr, 1, result.text.len, file) != result.text.len or fflush(file) != 0) return error.FileUnavailable;
    }
    return result.changed;
}

/// The findings of --lint, for the exit status: 2 when there are any and nothing else
/// went wrong.
var lint_findings: usize = 0;

/// The file of --debug-log, open while the program runs.
var debug_log_file: ?*anyopaque = null;

/// Writes to the log; each event ends its line, and is then given to the system, so
/// that the log is whole also when the program ends badly.
fn debugLogWrite(_: ?*anyopaque, bytes: []const u8) void {
    const file = debug_log_file orelse return;
    _ = fwrite(bytes.ptr, 1, bytes.len, file);
    if (bytes.len != 0 and bytes[bytes.len - 1] == '\n') _ = fflush(file);
}

/// The options that take a plain decimal number (not in a build with -Ddebug=false).
const number_options = [_]struct { name: []const u8, field: enum { max_steps, trace_limit, format_indent } }{
    .{ .name = "--max-steps", .field = .max_steps },
    .{ .name = "--trace-limit", .field = .trace_limit },
    .{ .name = "--format-indent", .field = .format_indent },
};

const StartOption = struct { short: []const u8, long: []const u8, field: enum { m, l, data_stack, return_stack, float_stack } };

const start_options = [_]StartOption{
    .{ .short = "-m", .long = "--dictionary-size", .field = .m },
    .{ .short = "-l", .long = "--locals-stack-size", .field = .l },
    .{ .short = "-d", .long = "--data-stack-size", .field = .data_stack },
    .{ .short = "-r", .long = "--return-stack-size", .field = .return_stack },
    .{ .short = "-f", .long = "--fp-stack-size", .field = .float_stack },
};

/// The bytes of a size as gforth takes it: a decimal number and a unit, `b` (bytes), `e`
/// (elements; also without a unit), `k`, `M`, `G`, or `T`. Null when it is not one.
fn parseSize(text: []const u8, element: usize) ?usize {
    var end: usize = 0;
    while (end < text.len and std.ascii.isDigit(text[end])) end += 1;
    if (end == 0) return null;
    // In 64 bits, so that `T` can be written also on a 32-bit host.
    const value = std.fmt.parseUnsigned(u64, text[0..end], 10) catch return null;
    const unit = text[end..];
    const scale: u64 = if (unit.len == 0 or std.mem.eql(u8, unit, "e"))
        element
    else if (std.mem.eql(u8, unit, "b"))
        1
    else if (std.mem.eql(u8, unit, "k"))
        1 << 10
    else if (std.mem.eql(u8, unit, "M"))
        1 << 20
    else if (std.mem.eql(u8, unit, "G"))
        1 << 30
    else if (std.mem.eql(u8, unit, "T"))
        1 << 40
    else
        return null;
    const bytes = std.math.mul(u64, value, scale) catch return null;
    return std.math.cast(usize, bytes);
}

/// Reads the size options at the start of the arguments, as gforth does: `-d SIZE`,
/// `-dSIZE`, `--data-stack-size SIZE`, and `--data-stack-size=SIZE`; `--` ends them, and
/// so does anything else. A size of 0 keeps the default. On an error, `failed` is the
/// option at fault.
const StartError = error{ MissingValue, InvalidSize, InvalidNumber, UnknownOption, DiagnosticRequiresNoApp };
fn parseStartOptions(args: []const []const u8, failed: *[]const u8) StartError!StartOptions {
    return parseStartOptionsPolicy(args, failed, false);
}
fn parseStartOptionsPolicy(args: []const []const u8, failed: *[]const u8, strict: bool) StartError!StartOptions {
    var options = StartOptions{};
    var index: usize = 1;
    while (index < args.len) {
        const argument = args[index];
        if (strict and std.mem.eql(u8, argument, "--no-app")) {
            options.no_app = true;
            index += 1;
            continue;
        }

        if (std.mem.eql(u8, argument, "--")) {
            index += 1;
            break;
        }
        // --max-steps N or --max-steps=N, and --trace-limit: a decimal number, not a
        // size. --trace and --profile take no value. A build without the debugging features
        // (-Ddebug=false) has none of them.
        if (@import("build_options").debug) {
            if (std.mem.eql(u8, argument, "--trace")) {
                options.trace = true;
                index += 1;
                continue;
            }
            if (std.mem.eql(u8, argument, "--profile")) {
                options.profile = true;
                index += 1;
                continue;
            }
            if (std.mem.eql(u8, argument, "--coverage")) {
                options.coverage = true;
                index += 1;
                continue;
            }
            if (std.mem.eql(u8, argument, "--lint")) {
                options.lint = true;
                index += 1;
                continue;
            }
            if (std.mem.eql(u8, argument, "--format") or std.mem.eql(u8, argument, "--format-check")) {
                options.format = if (argument.len == "--format".len) .write else .check;
                index += 1;
                continue;
            }
            // --debug-log FILE or --debug-log=FILE.
            if (std.mem.eql(u8, argument, debug_log_option)) {
                failed.* = debug_log_option;
                if (index + 1 >= args.len) return error.MissingValue;
                options.debug_log = args[index + 1];
                index += 2;
                continue;
            }
            if (std.mem.startsWith(u8, argument, debug_log_option ++ "=")) {
                failed.* = debug_log_option;
                if (argument.len == debug_log_option.len + 1) return error.MissingValue;
                options.debug_log = argument[debug_log_option.len + 1 ..];
                index += 1;
                continue;
            }
            const number_option = for (number_options) |option| {
                if (std.mem.eql(u8, argument, option.name) or (std.mem.startsWith(u8, argument, option.name) and argument.len > option.name.len and argument[option.name.len] == '=')) break option;
            } else null;
            if (number_option) |option| {
                failed.* = option.name;
                var text: []const u8 = undefined;
                if (argument.len == option.name.len) {
                    if (index + 1 >= args.len) return error.MissingValue;
                    index += 1;
                    text = args[index];
                } else text = argument[option.name.len + 1 ..];
                const value = std.fmt.parseUnsigned(u64, text, 10) catch return error.InvalidNumber;
                switch (option.field) {
                    .max_steps => options.max_steps = value,
                    .trace_limit => options.trace_limit = value,
                    // More than 16 blanks a step is not an indentation.
                    .format_indent => options.format_indent = if (value <= 16) value else return error.InvalidNumber,
                }
                index += 1;
                continue;
            }
        }
        var value: ?[]const u8 = null;
        var needs_next = false;
        const found: ?StartOption = for (start_options) |option| {
            if (std.mem.eql(u8, argument, option.short) or std.mem.eql(u8, argument, option.long)) {
                needs_next = true;
                break option;
            }
            if (std.mem.startsWith(u8, argument, option.long) and argument.len > option.long.len and argument[option.long.len] == '=') {
                value = argument[option.long.len + 1 ..];
                break option;
            }
            if (argument.len > 2 and !std.mem.startsWith(u8, argument, "--") and std.mem.startsWith(u8, argument, option.short)) {
                value = argument[2..];
                break option;
            }
        } else null;
        const option = found orelse {
            if (strict) {
                failed.* = argument;
                return error.UnknownOption;
            }
            break;
        };
        failed.* = argument;
        if (needs_next) {
            if (index + 1 >= args.len) return error.MissingValue;
            index += 1;
            value = args[index];
        }
        const bytes = parseSize(value.?, 8) orelse return error.InvalidSize;
        index += 1;
        // Memory is kept in whole cells, and stacks in whole elements.
        const in_bytes = std.mem.alignForward(usize, bytes, 8);
        const elements = in_bytes / 8;
        if (option.field == .m or option.field == .l) options.layout_seen = true;
        if (bytes == 0) continue;
        switch (option.field) {
            .m => options.m = in_bytes,
            .l => options.l = in_bytes,
            .data_stack => options.data_stack = elements,
            .return_stack => options.return_stack = elements,
            .float_stack => options.float_stack = elements,
        }
    }
    options.next = index;
    return options;
}

const ApplicationStart = struct { start: StartOptions, args_start: usize, app_mode: bool, prefix: bool };
fn applicationStart(args: []const []const u8, registered: bool, failed: *[]const u8) StartError!ApplicationStart {
    if (args.len > 1 and std.mem.eql(u8, args[1], "--sigma")) {
        const start = try parseStartOptionsPolicy(args[1..], failed, true);
        if (registered and !start.no_app and (start.format != .none or start.lint)) {
            failed.* = if (start.format != .none) "--format" else "--lint";
            return error.DiagnosticRequiresNoApp;
        }
        return .{ .start = start, .args_start = start.next + 1, .app_mode = registered and !start.no_app, .prefix = true };
    }
    if (registered) return .{ .start = .{}, .args_start = 1, .app_mode = true, .prefix = false };
    const start = try parseStartOptions(args, failed);
    return .{ .start = start, .args_start = start.next, .app_mode = false, .prefix = false };
}

/// The sizes to run with; null, with `failed` naming the option, when an option asks for
/// a size that cannot be.
fn startSizes(options: StartOptions, failed: *[]const u8) ?forth.Sizes {
    var sizes = forth.Sizes.default;
    if (options.m) |m| sizes.m = m;
    if (options.l) |l| sizes.l = l;
    if (options.data_stack) |value| sizes.data_stack = value;
    if (options.return_stack) |value| sizes.return_stack = value;
    if (options.float_stack) |value| sizes.float_stack = value;
    if (!forth.Sizes.validLayout(sizes.m, sizes.l)) {
        failed.* = if (options.m != null) "-m" else "-l";
        return null;
    }
    if (!forth.Sizes.validStack(sizes.data_stack)) {
        failed.* = "-d";
        return null;
    }
    if (!forth.Sizes.validStack(sizes.return_stack)) {
        failed.* = "-r";
        return null;
    }
    if (!forth.Sizes.validStack(sizes.float_stack)) {
        failed.* = "-f";
        return null;
    }
    return sizes;
}

fn loadDictionary(context: ?*anyopaque, input_path: []const u8, machine: *forth.State) forth.RuntimeError!void {
    const host: *HostContext = @ptrCast(@alignCast(context orelse return error.FileUnavailable));
    if (input_path.len >= 4096) return error.FileUnavailable;
    var terminated_path: [4096:0]u8 = undefined;
    @memcpy(terminated_path[0..input_path.len], input_path);
    terminated_path[input_path.len] = 0;
    const file = fopen(&terminated_path, "rb") orelse return error.FileUnavailable;
    defer _ = fclose(file);
    if (fseek(file, 0, 2) != 0) return error.FileUnavailable;
    const file_len_signed = ftell(file);
    if (file_len_signed < 0 or file_len_signed > std.math.maxInt(u32) or fseek(file, 0, 0) != 0) return error.InvalidImage;
    const file_len: usize = @intCast(file_len_signed);
    const bytes = host.allocator.alloc(u8, file_len) catch return error.MemoryExhausted;
    defer host.allocator.free(bytes);
    if (fread(bytes.ptr, 1, bytes.len, file) != bytes.len) return error.FileUnavailable;
    // The image is restored with the layout it was saved with; LOAD then moves its data
    // to the end of this dictionary, whatever the layouts are.
    const layout = forth.State.imageLayout(bytes) orelse return error.InvalidImage;
    var sizes = machine.sizes;
    sizes.m = layout[0];
    sizes.l = layout[1];
    const loaded = host.allocator.create(forth.State) catch return error.MemoryExhausted;
    defer host.allocator.destroy(loaded);
    const loaded_storage = forth.Storage.allocate(std.heap.page_allocator, true, sizes) catch return error.MemoryExhausted;
    defer loaded_storage.free(std.heap.page_allocator);
    loaded.init(machine.writer, loaded_storage);
    // With the trace or the profile, the short definitions of the image stay calls too.
    loaded.plain_calls = machine.plain_calls;
    try loaded.restoreFreshImage(bytes);
    try machine.appendImage(loaded);
}

fn saveDictionary(context: ?*anyopaque, output_path: []const u8, machine: *forth.State) forth.RuntimeError!void {
    const host: *HostContext = @ptrCast(@alignCast(context orelse return error.FileUnavailable));
    if (output_path.len >= 4096) return error.FileUnavailable;
    var terminated_path: [4096:0]u8 = undefined;
    @memcpy(terminated_path[0..output_path.len], output_path);
    terminated_path[output_path.len] = 0;
    const image = host.allocator.alloc(u8, try machine.encodedSize()) catch return error.MemoryExhausted;
    defer host.allocator.free(image);
    const length = try machine.encodeImage(image);
    const file = fopen(&terminated_path, "wb") orelse return error.FileUnavailable;
    defer _ = fclose(file);

    if (fwrite(image.ptr, 1, length, file) != length or fflush(file) != 0) return error.FileUnavailable;
}

const saved_native = struct {
    extern "c" fn sigma_saved_target_safe(?*anyopaque, [*:0]const u8) c_int;
    extern "c" fn sigma_saved_temp([*:0]const u8, [*]u8, usize, *c_uint) ?*anyopaque;
    extern "c" fn sigma_saved_mode(?*anyopaque, c_uint) c_int;
    extern "c" fn sigma_saved_publish(?*anyopaque, [*:0]const u8, [*:0]const u8) c_int;
};
const SaveFault = enum { none, base, image, footer, flush, mode, close, publish };
var test_save_fault: SaveFault = .none;
fn saveFault(stage: SaveFault) bool {
    return builtin.is_test and test_save_fault == stage;
}
fn saveExecutableImage(context: ?*anyopaque, output_path: []const u8, machine: *forth.State) forth.RuntimeError!void {
    const host: *HostContext = @ptrCast(@alignCast(context orelse return error.FileUnavailable));
    const allocator = host.allocator;
    const executable_path = host.executable_path;
    if (output_path.len == 0 or output_path.len >= 4096 or std.mem.indexOfScalar(u8, output_path, 0) != null) return error.FileUnavailable;
    var terminated_output: [4096:0]u8 = undefined;
    @memcpy(terminated_output[0..output_path.len], output_path);
    terminated_output[output_path.len] = 0;
    const source = fopen(executable_path.ptr, "rb") orelse return error.FileUnavailable;
    defer _ = fclose(source);
    if (saved_native.sigma_saved_target_safe(source, &terminated_output) == 0) return error.FileUnavailable;
    if (seek64(source, 0, 2) != 0) return error.FileUnavailable;
    const position = tell64(source);
    if (position < 0) return error.FileUnavailable;
    var base_len: u64 = @intCast(position);
    if (base_len >= image_footer_size) {
        if (seek64(source, @intCast(base_len - image_footer_size), 0) != 0) return error.FileUnavailable;
        var previous_footer: [image_footer_size]u8 = undefined;
        if (fread(&previous_footer, 1, previous_footer.len, source) != previous_footer.len) return error.FileUnavailable;
        if (try @import("host_saved_image.zig").footer(&previous_footer, base_len)) |info| base_len = info.base_len;
    }
    if (seek64(source, 0, 0) != 0) return error.FileUnavailable;
    const image = allocator.alloc(u8, try machine.encodedSize()) catch return error.MemoryExhausted;
    defer allocator.free(image);
    const image_len = try machine.encodeImage(image);
    if (image_len > std.math.maxInt(u32)) return error.FileUnavailable;
    var temporary: [4096:0]u8 = undefined;
    var final_mode: c_uint = 0;
    const destination = saved_native.sigma_saved_temp(&terminated_output, &temporary, temporary.len, &final_mode) orelse return error.FileUnavailable;
    var open = true;
    var published = false;
    defer {
        if (open) _ = fclose(destination);
        if (!published) _ = remove(&temporary);
    }
    var buffer: [8192]u8 = undefined;
    var copied: u64 = 0;
    while (copied < base_len) {
        const wanted: usize = @intCast(@min(buffer.len, base_len - copied));
        const amount = fread(&buffer, 1, wanted, source);
        if (amount != wanted or fwrite(&buffer, 1, amount, destination) != amount) return error.FileUnavailable;
        copied += amount;
    }
    if (saveFault(.base)) return error.FileUnavailable;
    if (fwrite(image.ptr, 1, image_len, destination) != image_len or saveFault(.image)) return error.FileUnavailable;
    var footer: [image_footer_size]u8 = undefined;
    @memcpy(footer[0..8], image_footer_magic);
    writeU32(footer[8..12], @intCast(image_len));
    writeU64(footer[12..20], base_len);
    if (fwrite(&footer, 1, footer.len, destination) != footer.len or saveFault(.footer)) return error.FileUnavailable;
    if (fflush(destination) != 0 or saveFault(.flush)) return error.FileUnavailable;
    if (saved_native.sigma_saved_mode(destination, final_mode) != 0 or saveFault(.mode)) return error.FileUnavailable;
    const close_result = fclose(destination);
    open = false;
    if (close_result != 0 or saveFault(.close)) return error.FileUnavailable;
    if (saveFault(.publish)) return error.FileUnavailable;
    if (saved_native.sigma_saved_publish(source, &temporary, &terminated_output) != 0) return error.FileUnavailable;
    published = true;
}

/// Writes to the standard error handle directly, as std.Io did: it is not buffered, so it
/// does not wait for a flush of the C library's stderr stream.
fn writeStandardError(bytes: []const u8) bool {
    _ = flushStandardOutput();
    if (builtin.os.tag == .windows and managedWriter(forth.stderr_fileid)) {
        var rest = bytes;
        while (rest.len != 0) {
            const accepted = stderr_writer.write(rest);
            rest = rest[accepted.count..];
            if (accepted.code != 0) return false;
            if (rest.len != 0 and finishWriter(forth.stderr_fileid) != 0) return false;
        }
        return finishWriter(forth.stderr_fileid) == 0;
    }
    return writeStandardErrorDirect(bytes);
}

fn writeStandardErrorDirect(bytes: []const u8) bool {
    // Preserve legacy stdout-before-stderr ordering even after queue migration.
    _ = flushStandardOutput();
    var rest = bytes;
    while (rest.len > 0) {
        if (builtin.os.tag == .windows) {
            const std_error_handle: u32 = @bitCast(@as(i32, -12));
            const handle = GetStdHandle(std_error_handle) orelse return false;
            var written: u32 = 0;
            const wanted: u32 = @intCast(@min(rest.len, std.math.maxInt(u32)));
            if (WriteFile(handle, rest.ptr, wanted, &written, null) == 0) return false;
            rest = rest[written..];
        } else {
            const written = std.c.write(2, rest.ptr, rest.len);
            if (written < 0) {
                if (std.c._errno().* == @backingInt(std.c.E.INTR)) continue;
                if (stderr_shares_output) output_cursor.unknown();
                return false;
            }
            if (stderr_shares_output) output_cursor.feed(rest[0..@intCast(written)]);
            rest = rest[@intCast(written)..];
        }
    }
    return true;
}

/// The path of the running executable, for the image a SAVESYS executable carries, as
/// std.process.executablePath gives it: WTF-8 on Windows, with symbolic links resolved
/// on Linux and macOS. Other systems resolve the program name the shell passed.
/// The file a symbolic link at `path` names, in `buffer` without the `\\?\` prefix, or
/// null when `path` is not a link or cannot be followed (the caller then keeps `path`).
/// Only a link is followed, so that any other path stays as Windows gave it.
fn windowsLinkTarget(allocator: std.mem.Allocator, path: []const u16, buffer: []u16) ?[]const u16 {
    if (builtin.os.tag != .windows) return null;
    const w = struct {
        extern "kernel32" fn GetFileAttributesW([*:0]const u16) callconv(.winapi) u32;
        extern "kernel32" fn CreateFileW([*:0]const u16, u32, u32, ?*anyopaque, u32, u32, ?*anyopaque) callconv(.winapi) ?*anyopaque;
        extern "kernel32" fn GetFinalPathNameByHandleW(*anyopaque, [*]u16, u32, u32) callconv(.winapi) u32;
        extern "kernel32" fn CloseHandle(*anyopaque) callconv(.winapi) c_int;
    };
    const invalid_attributes: u32 = 0xFFFF_FFFF;
    const reparse_point: u32 = 0x400;
    const share_all: u32 = 7;
    const open_existing: u32 = 3;
    const invalid_handle: usize = std.math.maxInt(usize);
    const name = allocator.dupeSentinel(u16, path, 0) catch return null;
    defer allocator.free(name);
    const attributes = w.GetFileAttributesW(name.ptr);
    if (attributes == invalid_attributes or attributes & reparse_point == 0) return null;
    // No access is asked for: the name is all that is wanted. Opening follows the link.
    const handle = w.CreateFileW(name.ptr, 0, share_all, null, open_existing, 0, null) orelse return null;
    if (@intFromPtr(handle) == invalid_handle) return null;
    defer _ = w.CloseHandle(handle);
    const length = w.GetFinalPathNameByHandleW(handle, buffer.ptr, @intCast(buffer.len), 0);
    if (length == 0 or length >= buffer.len) return null;
    return stripWindowsLongPrefix(buffer[0..length]);
}

/// `\\?\C:\dir\file` as `C:\dir\file`, and `\\?\UNC\server\share\file` as
/// `\\server\share\file` (in place); any other path as it is.
fn stripWindowsLongPrefix(path: []u16) []u16 {
    const L = std.unicode.utf8ToUtf16LeStringLiteral;
    if (!std.mem.startsWith(u16, path, L("\\\\?\\"))) return path;
    if (std.mem.startsWith(u16, path[4..], L("UNC\\"))) {
        // `\\?\UNC\server` becomes `\\server`: the `C` gives its place to a backslash.
        path[6] = '\\';
        return path[6..];
    }
    return path[4..];
}

test "a Windows long path loses its prefix, a share keeps its two backslashes" {
    const L = std.unicode.utf8ToUtf16LeStringLiteral;
    var drive = L("\\\\?\\C:\\dir\\sigma.exe").*;
    try std.testing.expectEqualSlices(u16, L("C:\\dir\\sigma.exe"), stripWindowsLongPrefix(&drive));
    var share = L("\\\\?\\UNC\\server\\share\\sigma.exe").*;
    try std.testing.expectEqualSlices(u16, L("\\\\server\\share\\sigma.exe"), stripWindowsLongPrefix(&share));
    var plain = L("C:\\dir\\sigma.exe").*;
    try std.testing.expectEqualSlices(u16, L("C:\\dir\\sigma.exe"), stripWindowsLongPrefix(&plain));
}

fn executablePathAlloc(allocator: std.mem.Allocator, argv0: ?[*:0]const u8) ![:0]u8 {
    switch (builtin.os.tag) {
        .windows => {
            const name = std.os.windows.peb().ProcessParameters.ImagePathName;
            const image = name.Buffer.?[0 .. name.Length / 2];
            // A symbolic link to the executable: the file it names, as on Linux and
            // macOS, so that `include` beside the executable is found (tque 1243).
            var resolved: [32768]u16 = undefined;
            if (windowsLinkTarget(allocator, image, &resolved)) |target| return std.unicode.wtf16LeToWtf8AllocZ(allocator, target);
            return std.unicode.wtf16LeToWtf8AllocZ(allocator, image);
        },
        .linux, .serenity, .illumos => {
            const link = if (builtin.os.tag == .illumos) "/proc/self/path/a.out" else "/proc/self/exe";
            var buffer: [std.c.PATH_MAX]u8 = undefined;
            const length = std.c.readlink(link, &buffer, buffer.len);
            if (length < 0) return error.FileNotFound;
            return allocator.dupeSentinel(u8, buffer[0..@intCast(length)], 0);
        },
        else => {
            var named: [std.c.PATH_MAX + 1]u8 = undefined;
            const path: [*:0]const u8 = if (builtin.os.tag.isDarwin()) path: {
                // _NSGetExecutablePath may give a symbolic link to the executable.
                var size: u32 = named.len;
                if (std.c._NSGetExecutablePath(&named, &size) != 0) return error.NameTooLong;
                break :path @ptrCast(&named);
            } else argv0 orelse return error.FileNotFound;
            var resolved: [std.c.PATH_MAX]u8 = undefined;
            const real = std.c.realpath(path, &resolved) orelse return error.FileNotFound;
            return allocator.dupeSentinel(u8, std.mem.span(real), 0);
        },
    }
}

/// Standard output is kept here and written out in pieces: writing each EMIT at once cost
/// a system call per character, which made output-heavy programs many times slower.
/// The buffer is written before any input is read, before MS, SYSTEM, and STDERR output,
/// on FLUSH-FILE of STDOUT, and at the end; on a terminal also at the end of each line.
var output_buffer: [4096]u8 = undefined;
var output_used: usize = 0;
/// Whether standard output is a terminal (set at start-up).
var output_is_terminal = false;
/// Tracks output without issuing cursor queries that would interleave with keyboard input.
var output_cursor = host_line.OutputCursor{};
var stderr_shares_output = false;

fn stderrSharesOutput() bool {
    if (builtin.os.tag == .windows or !output_is_terminal) return false;
    const output_name = std.mem.span(ttyname(1) orelse return false);
    var copy: [4096]u8 = undefined;
    if (output_name.len > copy.len) return false;
    // ttyname may reuse its buffer, so retain stdout's name before asking for stderr.
    @memcpy(copy[0..output_name.len], output_name);
    const length = output_name.len;
    const error_name = std.mem.span(ttyname(2) orelse return false);
    return std.mem.eql(u8, copy[0..length], error_name);
}

fn terminalWrite(_: ?*anyopaque, bytes: []const u8) void {
    if (builtin.os.tag != .windows and output_is_terminal) output_cursor.feed(bytes);
    var rest = bytes;
    while (rest.len > 0) {
        if (output_used == output_buffer.len) {
            flushOutput();
            if (output_used == output_buffer.len and output_ior == 0) {
                if (builtin.os.tag != .windows and output_nonblocking) {
                    const ready = fileWaitFiles(null, &.{forth.stdout_fileid}, -1, true) catch |err| {
                        latchInput(err);
                        return;
                    };
                    output_ior = ready.ior;
                } else output_ior = finishWriter(forth.stdout_fileid);
            }
            if (output_ior != 0) return;
            if (output_used == output_buffer.len) continue;
        }
        const amount = @min(rest.len, output_buffer.len - output_used);
        @memcpy(output_buffer[output_used..][0..amount], rest[0..amount]);
        output_used += amount;
        rest = rest[amount..];
    }
    if (output_is_terminal and std.mem.indexOfScalar(u8, bytes, '\n') != null) flushOutput();
}

/// PLAY waiting for room in its queues: what was written before shows during the wait.
fn audioWait(context: ?*anyopaque) forth.AudioWait {
    flushOutput();
    if (context) |value| {
        const host: *HostContext = @ptrCast(@alignCast(value));
        if (host.runtime) |runtime| return host_audio.waitWithRuntime(runtime);
    }
    return host_audio.wait();
}

/// Writes the buffered output through the C library, as before, so that the C library
/// still turns LF into CR LF where it did.
fn flushOutput() void {
    if ((builtin.os.tag == .windows and managedWriter(forth.stdout_fileid)) or (builtin.os.tag != .windows and output_nonblocking)) {
        _ = pumpOutputNonblocking() catch |err| {
            latchInput(err);
            return;
        };
        return;
    }
    if (output_used == 0) return;
    for (output_buffer[0..output_used]) |byte| _ = putchar(byte);
    output_used = 0;
    var count: usize = 0;
    var native_error: c_ulong = 0;
    if (sigma_write_stdout("".ptr, 0, &count, &native_error) != 0) output_ior = lastIor();
}

fn isTerminal(descriptor: c_int) bool {
    return if (builtin.os.tag == .windows) windows_stdin._isatty(descriptor) != 0 else std.c.isatty(descriptor) != 0;
}

/// One byte read ahead by KEY? and returned by the next read.
var lookahead: ?u8 = null;
var unread_bytes: [64]u8 = undefined;
var unread_count: usize = 0;

fn popLookahead() ?u8 {
    const result = lookahead;
    if (unread_count != 0) {
        unread_count -= 1;
        lookahead = unread_bytes[unread_count];
    } else lookahead = null;
    return result;
}

fn readByte() c_int {
    const guarded = beginInputGuard() catch |err| {
        latchInput(err);
        return -1;
    };
    defer endInputGuard(guarded);
    if (@import("host_wait.zig").inputInterrupted()) {
        latchInput(error.UserInterrupt);
        return -1;
    }
    // A prompt or a question is out before the program takes the answer, also when KEY?
    // has read the byte ahead and the program wrote in between.
    flushOutput();
    host_input.leave();
    output_cursor.unknown();
    if (lookahead) |byte| {
        _ = popLookahead();
        stdin_eof = false;
        return byte;
    }
    if (host_input.takePendingByte()) |byte| {
        stdin_eof = false;
        return byte;
    }
    const result = standardInputByte();
    if (@import("host_wait.zig").inputInterrupted()) {
        latchInput(error.UserInterrupt);
        return -1;
    }
    return result;
}

fn terminalKey(_: ?*anyopaque) ?u8 {
    const ch = readByte();
    return if (ch < 0) null else @intCast(ch);
}

fn monotonicMilliseconds(_: ?*anyopaque) i64 {
    if (builtin.os.tag == .windows) return @intCast(GetTickCount64());
    var time: std.c.timespec = undefined;
    if (std.c.clock_gettime(std.c.CLOCK.MONOTONIC, &time) != 0) return 0;
    return @as(i64, time.sec) * 1000 + @divTrunc(@as(i64, time.nsec), 1_000_000);
}

fn redirectedInputReady() bool {
    if (builtin.os.tag == .windows and managedReader(forth.stdin_fileid)) {
        ensureReader(forth.stdin_fileid) catch |err| {
            latchInput(err);
            return false;
        };
        const result = stdin_reader.peek();
        return result.count != 0 or result.eof or result.code != 0;
    }
    if (builtin.os.tag == .windows) {
        const handle = GetStdHandle(@bitCast(@as(i32, -10))) orelse return true;
        if (GetFileType(handle) != 3) return true;
        var count: u32 = 0;
        return PeekNamedPipe(handle, null, 0, null, &count, null) == 0 or count != 0;
    }
    var descriptor = [_]std.c.pollfd{.{ .fd = 0, .events = std.c.POLL.IN, .revents = 0 }};
    return std.c.poll(&descriptor, 1, 0) > 0;
}

/// EKEY uses the raw terminal, with a bounded wait for escape continuations.
fn terminalEventKey(_: ?*anyopaque, timeout_ms: i32) forth.RuntimeError!?forth.Cell {
    try inputError(null);
    flushOutput();
    output_cursor.unknown();
    if (try terminalBufferedKey(null)) |byte| return byte;
    if (builtin.os.tag == .windows) if (utf8_console.takePendingByte()) |byte| {
        if (byte == 3) return deliveredInterrupt();
        stdin_eof = false;
        return byte;
    };
    const start = monotonicMilliseconds(null);

    while (true) {
        if (host_input.input_is_terminal and @import("host_resize.zig").take()) return @import("core/standard_keys.zig").winch;
        if (host_input.input_is_terminal) {
            if (host_input.nextStandard()) |event| {
                if (event == 3) return deliveredInterrupt();
                stdin_eof = false;
                return event;
            }
            try host_input.takePresentationError();
            if (!host_input.isRaw()) return error.HostFailed;
        } else if (redirectedInputReady()) {
            clearErrno();
            const byte = standardInputByte();
            if (byte < 0 and std.c._errno().* != 0) return error.HostFailed;
            return if (byte < 0) null else byte;
        }
        if (timeout_ms >= 0) {
            const now = monotonicMilliseconds(null);
            if (now - start >= timeout_ms) return null;
        }
        try sleepMilliseconds(null, 1);
    }
}

/// Typed input for the standard decoder: null is never confused with EOF.
fn terminalStandardEvent(_: ?*anyopaque, timeout_ms: i32) forth.RuntimeError!@import("core/standard_event.zig").Result {
    try inputError(null);
    flushOutput();
    output_cursor.unknown();
    if (deferred_length != 0) {
        const packet = deferred_packets[deferred_head];
        deferred_head = (deferred_head + 1) % deferred_packets.len;
        deferred_length -= 1;
        return if (packet.reset) .restart else .{ .event = packet };
    }
    if (lookahead != null) {
        const byte = popLookahead().?;
        stdin_eof = false;
        return .{ .event = .{ .value = byte } };
    }
    if (builtin.os.tag == .windows) if (utf8_console.takePendingByte()) |byte| {
        stdin_eof = false;
        return .{ .event = .{ .value = byte } };
    };
    const deadline = try @import("core/runtime_base.zig").Deadline.afterMilliseconds(try @import("host_clock.zig").now(), timeout_ms);
    while (true) {
        if (host_input.input_is_terminal) {
            if (host_input.nextStandardPacket()) |packet| {
                if (packet.reset) return .restart;
                stdin_eof = false;
                return .{ .event = packet };
            }
            try host_input.takePresentationError();
            if (!host_input.isRaw()) return error.HostFailed;
        } else if (redirectedInputReady()) {
            clearErrno();
            const byte = standardInputByte();
            try inputError(null);
            if (byte < 0 and std.c._errno().* != 0) return .{ .failure = lastIor() };
            return if (byte < 0) .eof else .{ .event = .{ .value = byte } };
        }
        if (timeout_ms >= 0 and deadline.expired(try @import("host_clock.zig").now())) return .timeout;
        try sleepMilliseconds(null, 1);
    }
}

/// XKEY gives back a byte it read: it becomes the byte read ahead, as KEY? leaves one.
fn terminalUnreadChecked(_: ?*anyopaque, byte: u8) forth.RuntimeError!void {
    if (lookahead) |old| {
        // EKEY restores at most 32 consumed bytes; XKEY and READ-LINE restore
        // one consumed byte. They cannot grow this stack beyond that read-ahead.
        if (unread_count == unread_bytes.len) {
            return error.HostFailed;
        }
        unread_bytes[unread_count] = old;
        unread_count += 1;
    }
    stdin_eof = false;
    lookahead = byte;
}

fn terminalUnread(context: ?*anyopaque, byte: u8) void {
    terminalUnreadChecked(context, byte) catch |err| latchInput(err);
}

fn terminalBufferedKey(_: ?*anyopaque) forth.RuntimeError!?u8 {
    const byte = popLookahead() orelse return null;
    if (host_input.input_is_terminal and byte == 3) return deliveredInterrupt();
    stdin_eof = false;
    return byte;
}

fn terminalKeyReady(_: ?*anyopaque) bool {
    const guarded = beginInputGuard() catch |err| {
        latchInput(err);
        return false;
    };
    defer endInputGuard(guarded);
    flushOutput();
    host_input.leave();
    if (lookahead != null) return true;
    if (host_input.takePendingByte()) |byte| {
        lookahead = byte;
        return true;
    }
    output_cursor.unknown();
    const ch = standardInputByte();
    if (ch < 0) return false;
    lookahead = @intCast(ch);
    return true;
}

/// INKEY's and MOUSE's input: a byte KEY? read ahead, then the terminal, then the window.
fn inputEvent(_: ?*anyopaque) ?forth.InputEvent {
    if (lookahead) |byte| {
        _ = popLookahead();
        return .{ .byte = byte };
    }
    return host_input.next() orelse host_window.poll();
}

const execution_host_ops = @import("core/host_interface.zig").ExecutionOps{
    .begin = executionBegin,
    .poll = executionPoll,
    .end = executionEnd,
};
fn executionBegin(_: ?*anyopaque, machine: *forth.State) forth.RuntimeError!void {
    try @import("host_wait.zig").beginExecution(machine, executionRawPoll);
}
fn executionPoll(_: ?*anyopaque, _: *forth.State) forth.RuntimeError!void {
    try @import("host_wait.zig").pollExecution();
}
fn executionEnd(_: ?*anyopaque, machine: *forth.State) forth.RuntimeError!void {
    try @import("host_wait.zig").endExecution(machine);
}
const ExecutionReplay = struct {
    const standard = @import("core/standard_event.zig");
    packets: [5120]standard.Packet = undefined,
    origins: [5120]?host_input.ExecutionOrigin = undefined,
    // Each byte supplied to the cloned decoder retains its source tag.
    byte_origins: [5120]?host_input.ExecutionOrigin = undefined,
    length: usize = 0,
    index: usize = 0,
    bytes: usize = 0,
    last_three: bool = false,
    fn add(self: *@This(), packet: standard.Packet, origin: ?host_input.ExecutionOrigin) void {
        std.debug.assert(self.length < self.packets.len);
        self.packets[self.length] = packet;
        self.origins[self.length] = origin;
        self.length += 1;
    }
    fn read(context: ?*anyopaque, _: i32) forth.RuntimeError!standard.Result {
        const self: *@This() = @ptrCast(@alignCast(context.?));
        if (self.index == self.length) return .timeout;
        const at = self.index;
        const packet = self.packets[at];
        self.last_three = false;
        self.index += 1;
        if (packet.reset) return .restart;
        if (packet.mouse == null and packet.value >= 0 and packet.value <= 255) {
            self.last_three = packet.value == 3;
            self.byte_origins[self.bytes] = self.origins[at];
            self.bytes += 1;
        }
        return .{ .event = packet };
    }
};
// Process-owned and used only by the host thread; replay has no reentrant callbacks.
var execution_replay_workspace = ExecutionReplay{};
fn executionRawPoll(machine: *forth.State) forth.RuntimeError!void {
    try host_input.captureExecution();
    if (@import("core/event_input.zig").modern_depth != 0) return;
    const view = host_input.executionView();
    if (!view.candidate()) return;
    const replay = &execution_replay_workspace;
    replay.length = 0;
    replay.index = 0;
    replay.bytes = 0;
    if (machine.pending_key) |byte| replay.add(.{ .value = byte }, null);
    var pending = machine.pending_event_count;
    while (pending != 0) {
        pending -= 1;
        replay.add(.{ .value = machine.pending_event_bytes[pending] }, null);
    }
    if (machine.pending_standard_event) |value| replay.add(.{ .value = value }, null);
    for (0..deferred_length) |index| replay.add(deferred_packets[(deferred_head + index) % deferred_packets.len], null);
    if (lookahead) |byte| replay.add(.{ .value = byte }, null);
    var unread = unread_count;
    while (unread != 0) {
        unread -= 1;
        replay.add(.{ .value = unread_bytes[unread] }, null);
    }
    if (comptime builtin.os.tag == .windows) for (utf8_console.bytes[utf8_console.start..utf8_console.end]) |byte| replay.add(.{ .value = byte }, null);
    for (view.packets[0..view.length], view.origins[0..view.length]) |packet, origin| replay.add(packet, origin);
    var shadow = machine.standard_input;
    const initial = shadow.length;
    const source = ExecutionReplay.standard.Source{ .context = replay, .read_fn = ExecutionReplay.read, .clock = @import("host_clock.zig").clock };
    // A read has a work bound; keep replaying after timeout if it made progress.
    while (true) {
        const before = replay.index;
        replay.last_three = false;
        const result = ExecutionReplay.standard.read(&shadow, source, 0, false) catch |err| {
            if (err != error.UserInterrupt) return err;
            const consumed = initial + replay.bytes - 1 - (if (replay.last_three) @as(usize, 0) else shadow.length);
            if (consumed < initial) return;
            if (replay.byte_origins[consumed - initial]) |origin| {
                host_input.cancelExecution(origin);
                return deliveredInterrupt();
            }
            // Earlier core input retains its existing delivery contract.
            return;
        };
        if (result == .timeout and replay.index == before) return;
    }
}

var input_failure: ?forth.RuntimeError = null;
fn deliveredInterrupt() forth.RuntimeError {
    _ = @import("host_wait.zig").takeInterrupt();
    return error.UserInterrupt;
}
fn latchInput(err: forth.RuntimeError) void {
    if (err == error.UserInterrupt) _ = @import("host_wait.zig").takeInterrupt();
    if (input_failure == null) input_failure = err;
}
fn inputError(_: ?*anyopaque) forth.RuntimeError!void {
    if (input_failure) |err| {
        input_failure = null;
        return err;
    }
    try host_input.takePresentationError();
}
fn presentationChanged() void {
    output_cursor.unknown();
}
fn terminalModeSet(_: ?*anyopaque, mask: u8) forth.Cell {
    host_input.setPresentation(mask) catch |err| return switch (err) {
        error.HostUnavailable => -21,
        error.InvalidMode => -24,
        else => -265,
    };
    return 0;
}
fn terminalModeGet(_: ?*anyopaque) u8 {
    return host_input.modes.get();
}
fn beginInputGuard() forth.RuntimeError!bool {
    if (!host_input.input_is_terminal or host_input.modes.wanted & 5 == 0) return false;
    try @import("host_wait.zig").beginInput();
    return true;
}
fn endInputGuard(active: bool) void {
    if (active) @import("host_wait.zig").endInput() catch |err| latchInput(err);
}
fn clearForDiagnostics() void {
    @import("host_wait.zig").recover() catch {
        _ = writeStandardError("error: signal recovery before terminal cleanup\n");
    };
    host_input.finishPresentation() catch {
        _ = writeStandardError("error: terminal presentation restoration failed\n");
    };
    host_input.leave();
}
fn reportDiagnostic(machine: *forth.State, err: anyerror) void {
    clearForDiagnostics();
    machine.gfx_input.mouse_on = false;
    machine.standard_input.paste = false;
    machine.report(err);
}

fn mouseMode(_: ?*anyopaque, on: bool) void {
    host_input.setMouse(on);
}

fn cursorPosition(_: ?*anyopaque) ?forth.CursorPosition {
    return host_input.cursor();
}

fn terminalRead(_: ?*anyopaque, buffer: []u8) ?[]const u8 {
    const guarded = beginInputGuard() catch |err| {
        latchInput(err);
        return null;
    };
    defer endInputGuard(guarded);
    if (editedLine(buffer, null)) |result| return result.line;
    var used: usize = 0;
    while (true) {
        const ch = readByte();
        if (ch < 0) return if (used == 0) null else buffer[0..used];
        const byte: u8 = @intCast(ch);
        if (byte == '\r' or byte == '\n') {
            if (used == 0) continue;
            return buffer[0..used];
        }
        if (used < buffer.len) {
            buffer[used] = byte;
            used += 1;
        }
    }
}

/// Whether lines typed on the terminal are edited by Sigma; cleared if the terminal cannot
/// be set for it.
var line_editing = true;
var line_history = host_line.History{};

/// On a terminal on Linux and macOS, Sigma edits the line itself, so that Backspace takes
/// back as many columns as the character is wide (see host_line.zig). Null when the line
/// is to be read as it comes. The terminal's line input is given back first if INKEY had
/// taken it.
fn editedLine(buffer: []u8, history: ?*host_line.History) ?host_line.Result {
    const guarded = beginInputGuard() catch |err| {
        latchInput(err);
        return .{ .line = null };
    };
    defer endInputGuard(guarded);
    if (builtin.os.tag == .windows or !line_editing or !output_is_terminal or !host_input.input_is_terminal) return null;
    host_input.leave();
    const width = editingWidth(terminalSize(null));
    output_cursor.resize(width);
    var columns = width;
    if (output_cursor.position()) |column| {
        // Keep room for a full-width character plus the reserved right margin.
        if (column <= width - @min(width, @as(usize, 3))) {
            columns -= column;
        } else terminalWrite(null, "\n");
    } else {
        // External output and unsupported cursor controls make the origin unknown.
        terminalWrite(null, "\n");
    }
    if (host_line.read(buffer, lineByte, flushOutput, history, columns)) |result| {
        if (result.line != null) output_cursor.newline() else output_cursor.unknown();
        return result;
    }
    line_editing = false;
    return null;
}

fn editingWidth(size: ?forth.TerminalSize) usize {
    const columns = if (size) |value| value.columns else 0;
    return if (columns < 2) 80 else columns;
}

fn lineByte() ?u8 {
    const ch = readByte();
    return if (ch < 0) null else @intCast(ch);
}

fn pauseForRepl() forth.RuntimeError!void {
    host_input.pausePresentation() catch return error.HostFailed;
}
fn interpretAndPrompt(machine: *forth.State, line: []const u8) forth.RuntimeError!void {
    host_input.resumePresentation() catch |err| {
        reportDiagnostic(machine, err);
        try pauseForRepl();
        return;
    };
    machine.resetSteps();
    machine.interpretLine(line) catch |err| {
        reportDiagnostic(machine, err);
        try pauseForRepl();
        return;
    };
    if (!machine.defining) machine.write(" OK\n");
    try pauseForRepl();
}

const version = std.mem.trimEnd(u8, @embedFile("version"), " \t\r\n");
/// Without HELP (-Dhelp=false) the banner does not point to it.
const banner = "FORTH/Sigma " ++ version ++ "  MIT License\n" ++ (if (@import("build_options").help) "Type `help' for basic help\n" else "");

/// NEXT-ARG for the command-line loop: argument 1, copied into `buffer` (Forth code may
/// change the memory it lies in) and removed, or null when there is none left.
fn nextArgument(machine: *forth.State, buffer: []u8) !?[]const u8 {
    const found = try machine.argument(1);
    if (found[0] == 0) return null;
    if (found[1] > buffer.len) return error.StringTooLong;
    const start = try machine.memoryAddress(found[0], found[1]);
    @memcpy(buffer[0..found[1]], machine.memory[start .. start + found[1]]);
    try machine.shiftArguments();
    return buffer[0..found[1]];
}

/// Init.Minimal gives the arguments and the environment, decoded from UTF-16 on Windows,
/// without setting up std.Io (see HostContext).
pub fn main(init: std.process.Init.Minimal) u8 {
    process_cleanup_error = 0;
    audio_cleanup_failed = false;
    const status = run(init) catch |err| failed: {
        // As the standard library reports an error returned from main.
        var message: [128]u8 = undefined;
        _ = writeStandardError(std.fmt.bufPrint(&message, "error: {s}\n", .{@errorName(err)}) catch "error\n");
        break :failed @as(u8, 1);
    };
    if (audio_cleanup_failed) {
        flushOutput();
        host_audio.abortIncomplete();
    }
    if (process_cleanup_error != 0 or audio_cleanup_failed) return 1;
    return if (status == 0 and lint_findings != 0) 2 else status;
}

/// Returns the exit status: 1 when an argument fails, as in gforth, and 0 otherwise.
fn run(init: std.process.Init.Minimal) !u8 {
    // The private AppKit child runs before Sigma sets up its terminal, Forth state, or
    // saved-image path. It must receive the protocol greeting before opening AppKit.
    if (builtin.os.tag == .macos and init.args.vector.len == 2 and
        std.mem.eql(u8, std.mem.span(init.args.vector[1]), host_window.internal_child_argument))
    {
        if (!graphics) return 1;
        return try host_window.runChild();
    }
    if (builtin.os.tag == .macos and graphics and init.args.vector.len == 2 and
        std.mem.eql(u8, std.mem.span(init.args.vector[1]), host_display.internal_child_argument))
    {
        return try host_display.runProbeChild();
    }
    // The C library's allocator, which std.process.Init also gives in a release build
    // that links the C library.
    const allocator = std.heap.c_allocator;
    var environ_map = try std.process.Environ.createMap(init.environ, allocator);
    defer environ_map.deinit();
    const argv0: ?[*:0]const u8 = if (builtin.os.tag == .windows or init.args.vector.len == 0) null else init.args.vector[0];
    const executable_path = try executablePathAlloc(allocator, argv0);
    defer allocator.free(executable_path);
    if (graphics and builtin.os.tag == .macos) host_window.initMac(executable_path, init.environ.block.slice);
    if (graphics and builtin.os.tag == .macos) host_display.initMac(executable_path, init.environ.block.slice);
    var host = HostContext{ .allocator = allocator, .executable_path = executable_path, .environ_map = &environ_map };
    defer if (host.framebuffer.len != 0) allocator.free(host.framebuffer);
    defer for (host.fonts) |font| {
        if (font.len != 0) allocator.free(font);
    };
    const machine = try allocator.create(forth.State);
    defer allocator.destroy(machine);
    output_is_terminal = isTerminal(1);
    stderr_shares_output = stderrSharesOutput();
    output_cursor = .{};
    output_cursor.resize(editingWidth(terminalSize(null)));
    host_input.output_is_terminal = output_is_terminal;
    host_input.input_is_terminal = isTerminal(0);
    host_input.flush_output = flushOutput;
    var resize_scope = try @import("host_resize.zig").Scope.begin(host_input.input_is_terminal);
    defer _ = resize_scope.end();
    // The output kept in the buffer goes out however the session ends.
    defer flushOutput();

    const vt_available = enableVirtualTerminal();
    const terminal_kind = host.environ_map.get("TERM") orelse "";
    host_input.configurePresentation(output_is_terminal and host_input.input_is_terminal and vt_available and
        (builtin.os.tag == .windows or (terminal_kind.len != 0 and !std.mem.eql(u8, terminal_kind, "dumb"))));
    host_input.presentation_changed = presentationChanged;
    useBinaryStdin();
    utf8_console.begin();
    defer utf8_console.finish();
    // The size options at the start of the arguments, as gforth reads them, come before
    // anything else: the memory and the stacks are made from them.
    var arguments = try std.process.Args.Iterator.initAllocator(init.args, allocator);
    defer arguments.deinit();
    var argument_list: std.ArrayList([]const u8) = .empty;
    defer argument_list.deinit(allocator);
    while (arguments.next()) |argument| try argument_list.append(allocator, argument);
    if (argument_list.items.len == 0) {
        terminalWrite(null, "INVALID ARGUMENTS !\n");
        return 1;
    }
    const embedded = readEmbeddedImage(executable_path, allocator) catch |err| {
        terminalWrite(null, if (err == error.MemoryExhausted) "OUT OF MEMORY !\n" else "INVALID IMAGE !\n");
        return 1;
    };
    defer if (embedded) |image| allocator.free(image);
    const saved_info: ?@import("host_saved_image.zig").Info = if (embedded) |image|
        @import("host_saved_image.zig").inspect(image, allocator) catch |err| {
            terminalWrite(null, if (err == error.MemoryExhausted) "OUT OF MEMORY !\n" else "INVALID IMAGE !\n");
            return 1;
        }
    else
        null;
    var failed_option: []const u8 = "";
    const selection = applicationStart(argument_list.items, if (saved_info) |info| info.entry != null else false, &failed_option) catch |err| {
        terminalWrite(null, failed_option);
        terminalWrite(null, switch (err) {
            error.MissingValue => ": OPTION REQUIRES AN ARGUMENT !\n",
            error.InvalidSize => ": INVALID SIZE !\n",
            error.InvalidNumber => ": INVALID NUMBER !\n",
            error.UnknownOption => ": UNKNOWN OPTION !\n",
            error.DiagnosticRequiresNoApp => ": DIAGNOSTIC OPTION REQUIRES --no-app !\n",
        });
        return 1;
    };
    const start = selection.start;
    if (start.format != .none and saved_info == null) return formatFiles(allocator, argument_list.items[selection.args_start..], start.format == .check, @intCast(start.format_indent));
    var sizes = startSizes(start, &failed_option) orelse {
        terminalWrite(null, failed_option);
        terminalWrite(null, ": INVALID SIZE !\n");
        return 1;
    };
    if (saved_info) |info| {
        if (start.m != null or start.l != null or (selection.prefix and start.layout_seen)) {
            terminalWrite(null, "-m/-l: A SAVED PROGRAM KEEPS ITS MEMORY LAYOUT !\n");
            return 1;
        }
        sizes.m = info.m;
        sizes.l = info.l;
    }
    const storage = forth.Storage.allocate(std.heap.page_allocator, true, sizes) catch {
        terminalWrite(null, "OUT OF MEMORY !\n");
        return 1;
    };
    defer storage.free(std.heap.page_allocator);
    var runtime = try host_runtime.Runtime.init();
    defer {
        // Retry retained native restoration while the runtime still exists.
        const restoration = @import("host_wait.zig").recover();
        const teardown = if (restoration) |_| runtime.deinit() else |_| @as(host_runtime.Error!void, error.HostFailed);
        teardown catch {
            // These older defers would otherwise be skipped by the fatal path.
            // None of them access VM Storage or the retained runtime resources.
            flushOutput();
            utf8_console.finish();
            _ = resize_scope.end();
            _ = writeStandardError("error: runtime resources or signal restoration remain active\n");
            if (audio and audio_cleanup_failed) host_audio.abortIncomplete();
            libc.exit(1);
        };
    }
    host.runtime = &runtime;
    const previous_mode_recovery = host_input.before_mode_change;
    host_input.before_mode_change = @import("host_wait.zig").beforeInputModeChange;
    defer host_input.before_mode_change = previous_mode_recovery;
    machine.init(.{ .execution_ops = if (@import("build_options").debug and @import("build_options").extension) &execution_host_ops else null, .process_ops = if (process_native.available) &process_ops else null, .physical_key_ops = if (graphics and host_window.available) &host_window.physical_ops else null, .gamepad_ops = if (graphics) &host_gamepad.ops else null, .context = @ptrCast(&host), .write_fn = terminalWrite, .read_fn = terminalRead, .load_fn = loadDictionary, .save_fn = saveDictionary, .savesys_fn = saveExecutableImage, .key_fn = terminalKey, .key_ior_fn = terminalKeyIor, .event_key_fn = terminalEventKey, .standard_event_fn = terminalStandardEvent, .standard_clock = @import("host_clock.zig").clock, .standard_interrupts = host_input.input_is_terminal, .monotonic_ms_fn = monotonicMilliseconds, .key_ready_fn = terminalKeyReady, .buffered_key_fn = terminalBufferedKey, .unread_fn = terminalUnread, .unread_byte_fn = terminalUnreadChecked, .sleep_fn = sleepMilliseconds, .sleep_ns_fn = sleepNanoseconds, .utime_fn = microsecondsSinceEpoch, .ntime_fn = nanosecondsSinceEpoch, .cputime_fn = processCpuTimes, .local_time_fn = localTime, .zoned_time_fn = @import("host_timezone.zig").convert, .getenv_fn = environmentValue, .errno_fn = currentErrno, .system_fn = runShellCommand, .editor_fn = if (@import("build_options").tools) editSource else null, .file_ops = &file_ops, .framebuffer_fn = graphicsBuffer, .image_alloc_fn = if (graphics) imageAlloc else null, .image_free_fn = if (graphics) imageFree else null, .terminal_size_fn = terminalSize, .terminal_mode_set_fn = terminalModeSet, .terminal_mode_get_fn = terminalModeGet, .input_error_fn = inputError, .terminal_utf8_fn = terminalUtf8, .display_budget_fn = if (graphics and (builtin.os.tag == .windows or (builtin.os.tag == .linux and @import("build_options").x11))) @import("host_display_budget.zig").scope else null, .window_fn = if (graphics and host_window.available) host_window.show else null, .ime_preedit_fn = if (graphics and (builtin.os.tag == .windows or builtin.os.tag == .macos or (builtin.os.tag == .linux and @import("build_options").x11))) host_window.imePreedit else null, .ime_caret_fn = if (graphics and (builtin.os.tag == .windows or builtin.os.tag == .macos or (builtin.os.tag == .linux and @import("build_options").x11))) host_window.imeCaret else null, .window_fullscreen_fn = if (graphics and (builtin.os.tag == .windows or builtin.os.tag == .macos or (builtin.os.tag == .linux and @import("build_options").x11))) host_window.fullscreen else null, .window_cursor_fn = if (graphics and (builtin.os.tag == .windows or builtin.os.tag == .macos or (builtin.os.tag == .linux and @import("build_options").x11))) host_window.mouseCursor else null, .displays_fn = if (graphics and host_display.available) host_display.snapshot else null, .window_display_fn = if (graphics and (host_window.state_available or builtin.os.tag == .macos)) host_window.windowDisplay else null, .window_state_fn = if (graphics and host_window.state_available) host_window.windowState else null, .window_size_fn = if (graphics and host_display.available) host_display.windowSize else null, .window_minimized_fn = if (graphics and builtin.os.tag == .linux and @import("build_options").x11) host_display.windowMinimized else null, .window_fit_fn = if (graphics and host_window.state_available) host_window.windowFit else null, .window_smooth_fn = if (graphics and host_window.state_available) host_window.windowSmooth else null, .window_close_fn = if (graphics and host_window.state_available) host_window.windowClose else null, .window_wait_fn = if (graphics and host_window.state_available) host_window.windowWait else null, .input_fn = inputEvent, .mouse_fn = mouseMode, .cursor_fn = cursorPosition, .font_buffer_fn = if (graphics) fontBuffer else null, .font_free_fn = if (graphics) fontFree else null, .system_font_fn = if (graphics and host_font.available) host_font.select else null, .system_glyph_fn = if (graphics and host_font.available) host_font.glyph else null, .process_start_fn = if (graphics) processStart else null, .process_write_fn = if (graphics) host_process.write else null, .process_read_fn = if (graphics) host_process.read else null, .process_stop_fn = if (graphics) host_process.stop else null, .audio_scope_ops = if (audio) &execution_host_ops else null, .audio_fn = if (audio) host_audio.start else null, .audio_device_fn = if (audio) host_audio.hasDevice else null, .audio_wait_fn = if (audio) audioWait else null }, storage);
    defer closeAllFiles();
    defer _ = closeAllProcesses();
    defer host_directories.closeAll();
    // The images of the pool, when the session ends without BYE.
    defer forth.releaseImages(machine);
    defer host_window.close();
    defer if (graphics) host_gamepad.close();
    defer if (audio) {
        if (!host_audio.shutdown(1000)) {
            _ = writeStandardError("error: audio shutdown incomplete\n");
            audio_cleanup_failed = true;
        }
    };
    // The terminal gets its line input back (and stops reporting the mouse) at the end.
    defer {
        @import("host_wait.zig").recover() catch {
            _ = writeStandardError("error: pending signal restoration before terminal leave\n");
        };
        host_input.finishPresentation() catch {
            _ = writeStandardError("error: terminal cleanup failed\n");
        };
        host_input.leave();
    }
    // Shared process shutdown also kills Tcl's retained group/job descendants.
    defer runtime.beginShutdown() catch {
        _ = writeStandardError("error: runtime shutdown notification failed\n");
    };
    // Before the image: with the trace, its short definitions stay calls.
    machine.step_limit = start.max_steps;
    machine.tracing = start.trace;
    machine.trace_limit = start.trace_limit;
    machine.plain_calls = start.trace or start.profile or start.coverage;
    machine.cover_blocks = start.coverage;
    if (if (start.format == .none) start.debug_log else null) |path| {
        var terminated_path: [4096:0]u8 = undefined;
        if (path.len >= terminated_path.len) {
            terminalWrite(null, debug_log_option ++ ": FILE ERROR !\n");
            return 1;
        }
        @memcpy(terminated_path[0..path.len], path);
        terminated_path[path.len] = 0;
        debug_log_file = fopen(&terminated_path, "wb") orelse {
            terminalWrite(null, debug_log_option ++ ": FILE ERROR !\n");
            return 1;
        };
        machine.writer.log_fn = debugLogWrite;
        forth.logStart(machine, version);
    }
    // The checks of --lint are made however the program ends, as the profile is shown.
    const lint: ?*forth.Lint = if (start.format == .none and start.lint) std.heap.page_allocator.create(forth.Lint) catch {
        terminalWrite(null, "OUT OF MEMORY !\n");
        return 1;
    } else null;
    if (lint) |checks| {
        checks.reset();
        machine.lint = checks;
    }
    // After the profile and the findings have been written to it.
    defer if (debug_log_file) |file| {
        _ = fclose(file);
        debug_log_file = null;
    };
    defer if (lint) |checks| {
        checks.report(machine);
        lint_findings = checks.findings;
        std.heap.page_allocator.destroy(checks);
    };
    // The profile is shown however the program ends: BYE, an error, or the end of input.
    // --coverage keeps the same counts, for its words, and shows nothing at the end.
    const profile: ?*forth.Profile = if (start.format == .none and (start.profile or start.coverage)) std.heap.page_allocator.create(forth.Profile) catch {
        terminalWrite(null, "OUT OF MEMORY !\n");
        return 1;
    } else null;
    defer if (profile) |counts| {
        if (start.profile) counts.show(machine);
        std.heap.page_allocator.destroy(counts);
    };
    if (profile) |counts| {
        counts.reset();
        machine.profile = counts;
    }
    defer clearForDiagnostics();
    if (embedded) |image| machine.restoreFreshImage(image) catch |err| {
        reportDiagnostic(machine, err);
        return 1;
    };
    // FPATH starts as the working directory, then `include` beside the executable, so
    // the libraries load wherever Sigma starts. A SAVESYS executable keeps the FPATH of
    // its image instead (tque 1191).
    if (@import("build_options").files and embedded == null) {
        const directory = std.fs.path.dirname(host.executable_path) orelse ".";
        machine.setDefaultIncludePath(directory) catch |err| {
            reportDiagnostic(machine, err);
            return 1;
        };
    }
    if (saved_info) |info| {
        const restored = @import("core/app_entry.zig").get(machine) catch |err| {
            reportDiagnostic(machine, err);
            return 1;
        };
        if (restored != info.entry) {
            reportDiagnostic(machine, error.InvalidImage);
            return 1;
        }
    }
    if (start.format != .none) return formatFiles(allocator, argument_list.items[selection.args_start..], start.format == .check, @intCast(start.format_indent));

    // The other arguments go into Forth memory, where ARGC, ARGV, ARG, and NEXT-ARG see
    // them, after the program's name. This comes after the image is restored, since
    // restoring clears that area.
    var kept_arguments: std.ArrayList([]const u8) = .empty;
    defer kept_arguments.deinit(allocator);
    if (argument_list.items.len == 0) return 1;
    try kept_arguments.append(allocator, argument_list.items[0]);
    try kept_arguments.appendSlice(allocator, argument_list.items[selection.args_start..]);
    machine.setArguments(kept_arguments.items) catch |err| {
        reportDiagnostic(machine, err);
        return 1;
    };
    if (selection.app_mode) {
        machine.resetSteps();
        const root = @import("core/app_entry.zig").get(machine) catch |err| {
            reportDiagnostic(machine, err);
            return 1;
        };
        const id = root orelse {
            reportDiagnostic(machine, error.InvalidImage);
            return 1;
        };
        machine.runEntry(id) catch |err| {
            reportDiagnostic(machine, err);
            return 1;
        };
        return finishBlocks(machine);
    }
    // As in gforth: each argument names a file to include, in order, and `-e` (or
    // `--evaluate`) interprets the next argument. Each is removed from the arguments
    // before it runs, so a file sees only the ones after it, and the ones it takes with
    // NEXT-ARG are not processed here. The first error ends the program with status 1;
    // BYE ends it with status 0; otherwise the interactive session follows.
    var argument_text: [4096]u8 = undefined;
    while (true) {
        machine.resetSteps();
        const option = nextArgument(machine, &argument_text) catch |err| {
            reportDiagnostic(machine, err);
            return 1;
        } orelse break;
        if (std.mem.eql(u8, option, "-e") or std.mem.eql(u8, option, "--evaluate")) {
            var option_name: [16]u8 = undefined;
            const name = option_name[0..option.len];
            @memcpy(name, option);
            const source = nextArgument(machine, &argument_text) catch |err| {
                reportDiagnostic(machine, err);
                return 1;
            } orelse {
                machine.write(name);
                machine.write(": OPTION REQUIRES AN ARGUMENT !\n");
                return 1;
            };
            machine.interpretLine(source) catch |err| {
                reportDiagnostic(machine, err);
                return 1;
            };
        } else {
            machine.includeFile(option) catch |err| {
                // An error inside the file names the file and line; one opening it does not.
                if (machine.error_location == null) {
                    machine.write(option);
                    machine.write(": ");
                }
                reportDiagnostic(machine, err);
                return 1;
            };
        }
        if (machine.halted) return finishBlocks(machine);
    }

    // With --lint, the findings take the place of the interactive session.
    if (start.lint) return finishBlocks(machine);
    // REPL prompts are outside application presentation. Restore only while a line runs.
    host_input.pausePresentation() catch |err| {
        reportDiagnostic(machine, err);
        return 1;
    };
    // The banner comes after the arguments, as in gforth.
    machine.write(banner);
    var line: [4096]u8 = undefined;
    var used: usize = 0;
    var discarding_line = false;
    while (!machine.halted) {
        if (editedLine(&line, &line_history)) |result| {
            inputError(null) catch |err| {
                reportDiagnostic(machine, err);
                return 1;
            };
            const text = result.line orelse break;
            if (result.overflow) machine.write("LINE TOO LONG\n") else interpretAndPrompt(machine, text) catch |err| {
                reportDiagnostic(machine, err);
                return 1;
            };
            continue;
        }
        inputError(null) catch |err| {
            reportDiagnostic(machine, err);
            return 1;
        };
        const ch = readByte();
        inputError(null) catch |err| {
            reportDiagnostic(machine, err);
            return 1;
        };
        if (ch < 0) {
            if (!discarding_line and used != 0) interpretAndPrompt(machine, line[0..used]) catch |err| {
                reportDiagnostic(machine, err);
                return 1;
            };
            break;
        }
        const byte: u8 = @intCast(ch);
        if (byte == '\r' or byte == '\n') {
            if (!discarding_line and used != 0) interpretAndPrompt(machine, line[0..used]) catch |err| {
                reportDiagnostic(machine, err);
                return 1;
            };
            used = 0;
            discarding_line = false;
            continue;
        }
        if (discarding_line) continue;
        if (used == line.len) {
            machine.write("LINE TOO LONG\n");
            used = 0;
            discarding_line = true;
            continue;
        }
        line[used] = byte;
        used += 1;
    }
    return finishBlocks(machine);
}

/// Successful termination shares the block writeback path, including EOF and
/// saved executables. Errors remain visible and make the process fail.
fn finishBlocks(machine: *forth.State) u8 {
    if (machine.defining or machine.quote_depth != 0 or machine.postponing) {
        reportDiagnostic(machine, error.InvalidDefinition);
        return 1;
    }
    @import("core/blocks.zig").saveAll(machine) catch |err| {
        reportDiagnostic(machine, err);
        return 1;
    };
    return 0;
}

// Host tests: these exercise the real callbacks, which the core tests replace with fakes.

fn discardOutput(_: ?*anyopaque, _: []const u8) void {}

test "GETENV through the host accepts 3072 bytes and rejects 3073" {
    var map = std.process.Environ.Map.init(std.testing.allocator);
    defer map.deinit();
    try map.put("SIGMA_FIT", &@as([3072]u8, @splat('x')));
    try map.put("SIGMA_LONG", &@as([3073]u8, @splat('y')));
    try map.put("SIGMA_EMPTY", "");
    var host = HostContext{ .allocator = std.testing.allocator, .executable_path = "", .environ_map = &map };
    const machine = try std.testing.allocator.create(forth.State);
    defer std.testing.allocator.destroy(machine);
    const storage = try forth.Storage.allocate(std.testing.allocator, false, .small);
    defer storage.free(std.testing.allocator);
    machine.init(.{ .context = @ptrCast(&host), .write_fn = discardOutput, .getenv_fn = environmentValue }, storage);

    try machine.interpretLine("S\" SIGMA_FIT\" GETENV NIP S\" SIGMA_EMPTY\" GETENV NIP S\" SIGMA_UNSET\" GETENV S\" A=B\" GETENV");
    try std.testing.expectEqualSlices(forth.Cell, &.{ 3072, 0, 0, 0, 0, 0 }, machine.data_stack[0..machine.data_depth]);
    try std.testing.expectError(error.StringTooLong, machine.interpretLine("S\" SIGMA_LONG\" GETENV"));
}

test "SYSTEM through the host checks length and embedded NUL before running" {
    var command: [4096]u8 = @splat(' ');
    @memcpy(command[0..6], "exit 0");
    try std.testing.expectEqual(@as(forth.Cell, 0), try runShellCommand(null, command[0..4095]));
    try std.testing.expectError(error.StringTooLong, runShellCommand(null, command[0..4096]));
    try std.testing.expectError(error.HostFailed, runShellCommand(null, "exit 0\x00 & exit 1"));
    // A command that runs but exits with a non-zero status is not an error; its status
    // is the exit code on Windows and the wait status elsewhere, as gforth's $? gives.
    const status: forth.Cell = if (builtin.os.tag == .windows) 3 else 3 << 8;
    try std.testing.expectEqual(status, try runShellCommand(null, "exit 3"));
}
fn writeTestFile(path: [*:0]const u8, bytes: []const u8) !void {
    const file = fopen(path, "wb") orelse return error.TestUnexpectedResult;
    defer _ = fclose(file);
    if (fwrite(bytes.ptr, 1, bytes.len, file) != bytes.len) return error.TestUnexpectedResult;
}

test "INCLUDE through the host reads CR LF lines and limits a line to 4096 bytes" {
    if (!@import("build_options").files) return error.SkipZigTest;
    const allocator = std.testing.allocator;
    const fit = try allocator.alloc(u8, 4096 + 7);
    defer allocator.free(fit);
    @memset(fit, ' ');
    @memcpy(fit[0..2], "1 ");
    @memcpy(fit[4094..4096], " 2");
    @memcpy(fit[4096..4103], "\r\n3\r\n4\n");
    try writeTestFile(".zig-cache/sigma-include-fit.fs", fit);
    const long = try allocator.alloc(u8, 4097);
    defer allocator.free(long);
    @memset(long, ' ');
    try writeTestFile(".zig-cache/sigma-include-long.fs", long);

    var host = HostContext{ .allocator = allocator, .executable_path = "", .environ_map = undefined };
    const machine = try allocator.create(forth.State);
    defer allocator.destroy(machine);
    const storage = try forth.Storage.allocate(allocator, false, .small);
    defer storage.free(allocator);
    machine.init(.{ .context = @ptrCast(&host), .write_fn = discardOutput, .file_ops = &file_ops }, storage);
    defer closeAllFiles();
    defer host_directories.closeAll();

    try machine.interpretLine("INCLUDE .zig-cache/sigma-include-fit.fs SOURCELINE#");
    try std.testing.expectEqualSlices(forth.Cell, &.{ 1, 2, 3, 4, 0 }, machine.data_stack[0..machine.data_depth]);
    try std.testing.expectError(error.StringTooLong, machine.interpretLine("INCLUDE .zig-cache/sigma-include-long.fs"));
    for (file_slots) |slot| try std.testing.expect(slot.stream == null);
}

test "SLURP-FILE through the host reads every byte as it is" {
    if (!@import("build_options").files) return error.SkipZigTest;
    const allocator = std.testing.allocator;
    const text = try allocator.alloc(u8, 10000);
    defer allocator.free(text);
    for (text, 0..) |*byte, index| byte.* = @truncate(index);
    @memcpy(text[0..5], "a\r\nb\n");
    try writeTestFile(".zig-cache/sigma-slurp.txt", text);
    try writeTestFile(".zig-cache/sigma-slurp-empty.txt", "");

    var host = HostContext{ .allocator = allocator, .executable_path = "", .environ_map = undefined };
    const machine = try allocator.create(forth.State);
    defer allocator.destroy(machine);
    const storage = try forth.Storage.allocate(allocator, false, .small);
    defer storage.free(allocator);
    machine.init(.{ .context = @ptrCast(&host), .write_fn = discardOutput, .file_ops = &file_ops }, storage);
    defer closeAllFiles();
    defer host_directories.closeAll();

    try machine.interpretLine("S\" .zig-cache/sigma-slurp.txt\" SLURP-FILE S\" .zig-cache/sigma-slurp-empty.txt\" SLURP-FILE NIP");
    try std.testing.expectEqual(@as(usize, 3), machine.data_depth);
    const address: usize = @intCast(machine.data_stack[0]);
    try std.testing.expectEqual(@as(forth.Cell, 10000), machine.data_stack[1]);
    try std.testing.expectEqualSlices(u8, text, machine.memory[address .. address + text.len]);
    try std.testing.expectEqual(@as(forth.Cell, 0), machine.data_stack[2]);
    for (file_slots) |slot| try std.testing.expect(slot.stream == null);
}

test "file words through the host: position, resize, flush, status, rename over a file, delete" {
    if (!@import("build_options").files) return error.SkipZigTest;
    const allocator = std.testing.allocator;
    try writeTestFile(".zig-cache/sigma-files-b.txt", "old");
    var host = HostContext{ .allocator = allocator, .executable_path = "", .environ_map = undefined };
    const machine = try allocator.create(forth.State);
    defer allocator.destroy(machine);
    const storage = try forth.Storage.allocate(allocator, false, .small);
    defer storage.free(allocator);
    machine.init(.{ .context = @ptrCast(&host), .write_fn = discardOutput, .file_ops = &file_ops }, storage);
    defer closeAllFiles();
    defer host_directories.closeAll();

    try machine.interpretLine("S\" .zig-cache/sigma-files-a.txt\" W/O BIN CREATE-FILE THROW VALUE F S\" hello world\" F WRITE-FILE F FILE-POSITION F FLUSH-FILE");
    try machine.interpretLine("5 0 F RESIZE-FILE F FILE-SIZE F FILE-POSITION F CLOSE-FILE");
    try machine.interpretLine("S\" .zig-cache/sigma-files-a.txt\" FILE-STATUS S\" .zig-cache/sigma-files-a.txt\" S\" .zig-cache/sigma-files-b.txt\" RENAME-FILE");
    try machine.interpretLine("S\" .zig-cache/sigma-files-a.txt\" FILE-STATUS NIP S\" .zig-cache/sigma-files-b.txt\" SLURP-FILE NIP");
    try machine.interpretLine("S\" .zig-cache/sigma-files-b.txt\" DELETE-FILE S\" .zig-cache/sigma-files-b.txt\" DELETE-FILE");
    // WRITE-FILE, FILE-POSITION, FLUSH-FILE; RESIZE-FILE, FILE-SIZE, FILE-POSITION (it stays),
    // CLOSE-FILE; FILE-STATUS (R/W), RENAME-FILE over b; a is gone, b holds the five bytes;
    // the first DELETE-FILE works and the second finds no file.
    try std.testing.expectEqualSlices(forth.Cell, &.{ 0, 11, 0, 0, 0, 0, 5, 0, 0, 11, 0, 0, 0, forth.fam_read_write, 0, 0, forth.errnoIor(2), 5, 0, forth.errnoIor(2) }, machine.data_stack[0..machine.data_depth]);
    for (file_slots) |slot| try std.testing.expect(slot.stream == null);

    // A rename that fails leaves the file it would have replaced as it was.
    machine.data_depth = 0;
    try writeTestFile(".zig-cache/sigma-files-b.txt", "old");
    try machine.interpretLine("S\" .zig-cache/sigma-files-none.txt\" S\" .zig-cache/sigma-files-b.txt\" RENAME-FILE S\" .zig-cache/sigma-files-b.txt\" SLURP-FILE NIP");
    try machine.interpretLine("S\" .zig-cache/sigma-files-b.txt\" DELETE-FILE");
    try std.testing.expectEqualSlices(forth.Cell, &.{ forth.errnoIor(2), 3, 0 }, machine.data_stack[0..machine.data_depth]);
}

test "file names and commands other than ASCII: create, include, status, rename, delete, SYSTEM" {
    if (!@import("build_options").files) return error.SkipZigTest;
    const allocator = std.testing.allocator;
    var host = HostContext{ .allocator = allocator, .executable_path = "", .environ_map = undefined };
    const machine = try allocator.create(forth.State);
    defer allocator.destroy(machine);
    const storage = try forth.Storage.allocate(allocator, false, .small);
    defer storage.free(allocator);
    machine.init(.{ .context = @ptrCast(&host), .write_fn = discardOutput, .file_ops = &file_ops, .errno_fn = currentErrno, .system_fn = runShellCommand }, storage);
    defer closeAllFiles();
    defer host_directories.closeAll();

    try machine.interpretLine("S\" .zig-cache/sigma-日本語.fs\" W/O CREATE-FILE THROW VALUE F S\" 6 7 *\" F WRITE-FILE F CLOSE-FILE");
    try machine.interpretLine("S\" .zig-cache/sigma-日本語.fs\" INCLUDED S\" .zig-cache/sigma-日本語.fs\" FILE-STATUS NIP");
    try machine.interpretLine("S\" .zig-cache/sigma-日本語.fs\" S\" .zig-cache/sigma-漢字.fs\" RENAME-FILE S\" .zig-cache/sigma-漢字.fs\" DELETE-FILE S\" .zig-cache/sigma-漢字.fs\" FILE-STATUS NIP");
    // The shell gets the command in UTF-8 as it was written (a name with no file is not found).
    try machine.interpretLine("S\" exit 0 & echo 日本語 > " ++ (if (builtin.os.tag == .windows) "NUL" else "/dev/null") ++ "\" SYSTEM $?");
    // WRITE-FILE, CLOSE-FILE; 42 from the file, FILE-STATUS; RENAME-FILE, DELETE-FILE, no file; SYSTEM's status.
    try std.testing.expectEqualSlices(forth.Cell, &.{ 0, 0, 42, 0, 0, 0, forth.errnoIor(2), 0 }, machine.data_stack[0..machine.data_depth]);
}

test "the banner names the version from VERSION and the license" {
    const expected = comptime std.mem.trimEnd(u8, @embedFile("version"), " \t\r\n");
    try std.testing.expect(std.mem.startsWith(u8, banner, "FORTH/Sigma " ++ expected ++ "  MIT License\n"));
    if (@import("build_options").help) {
        try std.testing.expect(std.mem.endsWith(u8, banner, "Type `help' for basic help\n"));
    } else {
        try std.testing.expect(std.mem.indexOf(u8, banner, "help") == null);
    }
    try std.testing.expect(std.mem.indexOfScalar(u8, banner, '\r') == null);
}

test "SAVE and LOAD through the host keep the words, also when loaded twice" {
    if (!@import("build_options").image) return error.SkipZigTest;
    const allocator = std.testing.allocator;
    var host = HostContext{ .allocator = allocator, .executable_path = "", .environ_map = undefined };
    const writer: forth.Writer = .{ .context = @ptrCast(&host), .write_fn = discardOutput, .load_fn = loadDictionary, .save_fn = saveDictionary };
    const source = try allocator.create(forth.State);
    defer allocator.destroy(source);
    const source_storage = try forth.Storage.allocate(allocator, false, .small);
    defer source_storage.free(allocator);
    source.init(writer, source_storage);
    try source.interpretLine(": SQ DUP * ; :NONAME 7 ; DROP VARIABLE V 11 V ! SAVE .zig-cache/sigma-load-test.sigma");

    // LOAD builds a second State of several megabytes; it must not need a copy on the stack.
    const target = try allocator.create(forth.State);
    defer allocator.destroy(target);
    const target_storage = try forth.Storage.allocate(allocator, false, .small);
    defer target_storage.free(allocator);
    target.init(writer, target_storage);
    try target.interpretLine(": EARLIER 1 ; LOAD-DICTIONARY .zig-cache/sigma-load-test.sigma LOAD-DICTIONARY .zig-cache/sigma-load-test.sigma 6 SQ V @ EARLIER");
    try std.testing.expectEqualSlices(forth.Cell, &.{ 36, 11, 1 }, target.data_stack[0..target.data_depth]);
}
test {
    // The tests of the host's terminal input and of the Tcl program it starts.
    _ = @import("host_wait.zig");
    _ = @import("host_terminal.zig");
    _ = host_input;
    _ = host_audio;
    _ = host_line;
    _ = host_font;
    _ = host_process;
    _ = @import("window_layout.zig");
    _ = @import("display_randr.zig");
    _ = host_display;
    if (builtin.os.tag == .windows) _ = host_window;
    if (builtin.os.tag == .macos and @import("build_options").graphics) {
        _ = @import("host_window_macos.zig");
        _ = @import("host_display_macos.zig");
    }
    if (builtin.os.tag == .linux and @import("build_options").graphics) _ = @import("host_evdev.zig");
    if (builtin.os.tag == .linux and @import("build_options").graphics and @import("build_options").x11) {
        _ = @import("host_window_linux.zig");
        _ = @import("host_x11.zig");
        _ = @import("host_xim.zig");
    }
}

test "parseSize reads sizes as gforth does" {
    try std.testing.expectEqual(@as(?usize, 8000), parseSize("1000", 8));
    try std.testing.expectEqual(@as(?usize, 8000), parseSize("1000e", 8));
    try std.testing.expectEqual(@as(?usize, 1000), parseSize("1000b", 8));
    try std.testing.expectEqual(@as(?usize, 64 << 10), parseSize("64k", 8));
    try std.testing.expectEqual(@as(?usize, 1 << 20), parseSize("1M", 8));
    try std.testing.expectEqual(@as(?usize, 1 << 30), parseSize("1G", 8));
    // A size a 32-bit host cannot hold is not a size there.
    try std.testing.expectEqual(std.math.cast(usize, @as(u64, 1) << 40), parseSize("1T", 8));
    for ([_][]const u8{ "1K", "1m", "1g", "1.5k", "abc", "", "-5", "1kb" }) |bad| {
        try std.testing.expectEqual(@as(?usize, null), parseSize(bad, 8));
    }
}

test "the size options are read at the start of the arguments" {
    var failed: []const u8 = "";
    const all = try parseStartOptions(&.{ "sigma", "-d", "1000", "-r2000", "--fp-stack-size=3000", "--locals-stack-size", "1M", "-m", "8M", "--", "-e", "BYE" }, &failed);
    try std.testing.expectEqual(@as(?usize, 1000), all.data_stack);
    try std.testing.expectEqual(@as(?usize, 2000), all.return_stack);
    try std.testing.expectEqual(@as(?usize, 3000), all.float_stack);
    try std.testing.expectEqual(@as(?usize, 1 << 20), all.l);
    try std.testing.expectEqual(@as(?usize, 8 << 20), all.m);
    try std.testing.expectEqual(@as(usize, 10), all.next);

    // Anything else ends them, as it does in gforth.
    const stopped = try parseStartOptions(&.{ "sigma", "-e", "1", "-d", "1000" }, &failed);
    try std.testing.expectEqual(@as(?usize, null), stopped.data_stack);
    try std.testing.expectEqual(@as(usize, 1), stopped.next);
    const file = try parseStartOptions(&.{ "sigma", "x.fs", "-d", "1000" }, &failed);
    try std.testing.expectEqual(@as(usize, 1), file.next);

    // 0 keeps the default, and a part of an element counts as a whole one.
    const zero = try parseStartOptions(&.{ "sigma", "-d", "0", "-r", "7b" }, &failed);
    try std.testing.expectEqual(@as(?usize, null), zero.data_stack);
    try std.testing.expectEqual(@as(?usize, 1), zero.return_stack);

    // --max-steps takes a plain number, in either form.
    if (@import("build_options").debug) {
        const steps = try parseStartOptions(&.{ "sigma", "--max-steps", "5000", "-d", "1000", "x.fs" }, &failed);
        try std.testing.expectEqual(@as(u64, 5000), steps.max_steps);
        try std.testing.expectEqual(@as(?usize, 1000), steps.data_stack);
        try std.testing.expectEqual(@as(usize, 5), steps.next);
        try std.testing.expectEqual(@as(u64, 70), (try parseStartOptions(&.{ "sigma", "--max-steps=70" }, &failed)).max_steps);
        try std.testing.expectError(error.InvalidNumber, parseStartOptions(&.{ "sigma", "--max-steps=1k" }, &failed));
        try std.testing.expectEqualStrings("--max-steps", failed);
        try std.testing.expectError(error.MissingValue, parseStartOptions(&.{ "sigma", "--max-steps" }, &failed));
        const traced = try parseStartOptions(&.{ "sigma", "--trace", "--trace-limit=200", "x.fs" }, &failed);
        try std.testing.expect(traced.trace);
        try std.testing.expectEqual(@as(u64, 200), traced.trace_limit);
        try std.testing.expectEqual(@as(usize, 3), traced.next);
        try std.testing.expect(!steps.trace);
        try std.testing.expect(!traced.profile);
        try std.testing.expect((try parseStartOptions(&.{ "sigma", "--profile", "x.fs" }, &failed)).profile);
        const logged = try parseStartOptions(&.{ "sigma", "--debug-log", "log.jsonl", "--debug-log=other.jsonl", "x.fs" }, &failed);
        try std.testing.expectEqualStrings("other.jsonl", logged.debug_log.?);
        try std.testing.expectEqual(@as(usize, 4), logged.next);
        try std.testing.expectError(error.MissingValue, parseStartOptions(&.{ "sigma", "--debug-log" }, &failed));
        try std.testing.expectError(error.MissingValue, parseStartOptions(&.{ "sigma", "--debug-log=" }, &failed));
        try std.testing.expectEqual(@as(?[]const u8, null), traced.debug_log);
        try std.testing.expect(!traced.lint);
        try std.testing.expect(!traced.coverage);
        try std.testing.expect((try parseStartOptions(&.{ "sigma", "--coverage", "x.fs" }, &failed)).coverage);
        try std.testing.expect((try parseStartOptions(&.{ "sigma", "--lint", "x.fs" }, &failed)).lint);
        const formats = try parseStartOptions(&.{ "sigma", "--format", "--format-indent", "2", "x.fs", "y.fs" }, &failed);
        try std.testing.expect(formats.format == .write);
        try std.testing.expectEqual(@as(u64, 2), formats.format_indent);
        try std.testing.expectEqual(@as(usize, 4), formats.next);
        try std.testing.expect((try parseStartOptions(&.{ "sigma", "--format-check", "x.fs" }, &failed)).format == .check);
        try std.testing.expectError(error.InvalidNumber, parseStartOptions(&.{ "sigma", "--format-indent=40" }, &failed));
        try std.testing.expect(traced.format == .none);
    }

    try std.testing.expectError(error.MissingValue, parseStartOptions(&.{ "sigma", "-d" }, &failed));
    try std.testing.expectEqualStrings("-d", failed);
    try std.testing.expectError(error.InvalidSize, parseStartOptions(&.{ "sigma", "-m", "abc" }, &failed));
    try std.testing.expectEqualStrings("-m", failed);
}

test "startSizes keeps the defaults and refuses sizes that cannot be" {
    var failed: []const u8 = "";
    try std.testing.expectEqual(forth.Sizes.default, startSizes(.{}, &failed).?);
    const chosen = startSizes(.{ .m = 8 << 20, .l = 1 << 20, .data_stack = 100 }, &failed).?;
    try std.testing.expectEqual(@as(usize, 8 << 20), chosen.m);
    try std.testing.expectEqual(@as(usize, 100), chosen.data_stack);
    try std.testing.expectEqual(forth.Sizes.default.return_stack, chosen.return_stack);

    try std.testing.expectEqual(@as(?forth.Sizes, null), startSizes(.{ .m = 4096 }, &failed));
    try std.testing.expectEqualStrings("-m", failed);
    try std.testing.expectEqual(@as(?forth.Sizes, null), startSizes(.{ .l = 8 }, &failed));
    try std.testing.expectEqualStrings("-l", failed);
    try std.testing.expectEqual(@as(?forth.Sizes, null), startSizes(.{ .m = 3 << 30 }, &failed));
    try std.testing.expectEqual(@as(?forth.Sizes, null), startSizes(.{ .data_stack = 1 }, &failed));
    try std.testing.expectEqualStrings("-d", failed);
    try std.testing.expectEqual(@as(?forth.Sizes, null), startSizes(.{ .return_stack = 1 << 28 }, &failed));
    try std.testing.expectEqualStrings("-r", failed);
}

test "line editing uses a bounded default for missing or unusable terminal widths" {
    try std.testing.expectEqual(@as(usize, 80), editingWidth(null));
    try std.testing.expectEqual(@as(usize, 80), editingWidth(.{ .columns = 0, .rows = 24 }));
    try std.testing.expectEqual(@as(usize, 80), editingWidth(.{ .columns = 1, .rows = 24 }));
    try std.testing.expectEqual(@as(usize, 12), editingWidth(.{ .columns = 12, .rows = 24 }));
}

test "normal termination reports block writeback failure with nonzero status" {
    const support = @import("tests/support.zig");
    try support.skipWithout(&.{.files});
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    output.files[0].open = true;
    output.files[0].exists = true;
    machine.block_storage.file = forth.first_file_id;
    try machine.interpretLine("1 BLOCK DROP UPDATE");
    output.write_fails_at = 1;
    try std.testing.expectEqual(@as(u8, 1), finishBlocks(machine));
    try std.testing.expect(machine.block_storage.buffers[1].modified);
    output.write_fails_at = 0;
    try std.testing.expectEqual(@as(u8, 0), finishBlocks(machine));
}

test "file key readiness sees stdio buffered bytes and preserves flags and EOF" {
    const path = ".zig-cache/sigma-file-key-ready.bin";
    defer _ = fileDelete(null, path);
    const opened = fileOpen(null, path, .read_write, true);
    try std.testing.expectEqual(@as(forth.Cell, 0), opened.ior);
    const id: forth.Cell = @bitCast(opened.value);
    defer _ = fileClose(null, id);
    try std.testing.expectEqual(@as(forth.Cell, 0), fileWrite(null, id, "AB"));
    try std.testing.expectEqual(@as(forth.Cell, 0), fileReposition(null, id, 0));
    const file = openedFile(id).?;
    const flags = if (builtin.os.tag == .windows) 0 else fcntl(file_number(file), @import("c_file").F_GETFL);
    try std.testing.expectEqual(@as(u8, 'A'), (try fileKey(null, id)).byte.?);
    for (0..2) |_| {
        try std.testing.expectEqual(@as(forth.UCell, 1), (try fileReady(null, id)).value);
        try std.testing.expectEqual(@as(forth.UCell, 1), filePosition(null, id).value);
        try std.testing.expectEqual(@as(forth.UCell, 0), fileEof(null, id).value);
    }
    if (builtin.os.tag != .windows) try std.testing.expectEqual(flags, fcntl(file_number(file), @import("c_file").F_GETFL));
    try std.testing.expectEqual(@as(u8, 'B'), (try fileKey(null, id)).byte.?);
    try std.testing.expectEqual(@as(forth.UCell, 0), (try fileReady(null, id)).value);
    try std.testing.expectEqual(@as(forth.UCell, 0), fileEof(null, id).value);
    try std.testing.expect((try fileKey(null, id)).byte == null);
    try std.testing.expectEqual(@as(forth.UCell, 1), fileEof(null, id).value);
    try std.testing.expectEqual(@as(forth.Cell, 0), fileSize(null, id).ior);
    var empty: [0]u8 = .{};
    try std.testing.expectEqual(@as(forth.Cell, 0), fileRead(null, id, &empty).ior);
    try std.testing.expectEqual(@as(forth.UCell, 1), fileEof(null, id).value);
    try std.testing.expectEqual(@as(forth.UCell, 0), (try fileReady(null, id)).value);
    try std.testing.expect((try fileKey(null, id)).byte == null);
    try std.testing.expectEqual(@as(forth.Cell, 0), fileReposition(null, id, 0));
    try std.testing.expectEqual(@as(forth.UCell, 0), fileEof(null, id).value);
}

test "file key readiness mixes with READ-FILE READ-LINE and file size" {
    const path = ".zig-cache/sigma-file-key-mixed.bin";
    defer _ = fileDelete(null, path);
    const opened = fileOpen(null, path, .read_write, true);
    try std.testing.expectEqual(@as(forth.Cell, 0), opened.ior);
    const id: forth.Cell = @bitCast(opened.value);
    defer _ = fileClose(null, id);
    try std.testing.expectEqual(@as(forth.Cell, 0), fileWrite(null, id, "AB\nC"));
    try std.testing.expectEqual(@as(forth.Cell, 0), fileReposition(null, id, 0));
    try std.testing.expectEqual(@as(forth.UCell, 1), (try fileReady(null, id)).value);
    try std.testing.expectEqual(@as(forth.UCell, 4), fileSize(null, id).value);
    var byte: [1]u8 = undefined;
    try std.testing.expectEqual(@as(forth.UCell, 1), fileRead(null, id, &byte).value);
    try std.testing.expectEqual(@as(u8, 'A'), byte[0]);
    try std.testing.expectEqual(@as(forth.UCell, 1), (try fileReady(null, id)).value);
    var line: [8]u8 = undefined;
    const result = fileReadLine(null, id, &line);
    try std.testing.expectEqual(@as(usize, 1), result.length);
    try std.testing.expectEqualStrings("B", line[0..result.length]);
    try std.testing.expectEqual(@as(u8, 'C'), (try fileKey(null, id)).byte.?);
    try std.testing.expectEqual(@as(forth.UCell, 0), fileEof(null, id).value);
    try std.testing.expect(!fileReadLine(null, id, &line).found);
    try std.testing.expectEqual(@as(forth.UCell, 1), fileEof(null, id).value);
}

test "P05b native clocks have Unix ns units and nondecreasing process CPU counters" {
    const before = try microsecondsSinceEpoch(null);
    const now = try nanosecondsSinceEpoch(null);
    const after = try microsecondsSinceEpoch(null);
    try std.testing.expect(now >= before * 1000);
    try std.testing.expect(now < (after + 1) * 1000);
    const first = try processCpuTimes(null);
    try std.testing.expect(first.user >= 0 and first.system >= 0);
    var result: u64 = 1;
    for (0..100000) |i| {
        result = result *% 6364136223846793005 +% @as(u64, @intCast(i));
        std.mem.doNotOptimizeAway(result);
    }
    const second = try processCpuTimes(null);
    try std.testing.expect(second.user >= first.user);
    try std.testing.expect(second.system >= first.system);
}

test "native process CPU includes a busy worker thread" {
    if (builtin.os.tag != .windows and builtin.os.tag != .linux) return error.SkipZigTest;
    const Worker = struct {
        extern "kernel32" fn GetCurrentThread() callconv(.winapi) *anyopaque;
        extern "kernel32" fn GetThreadTimes(*anyopaque, *u64, *u64, *u64, *u64) callconv(.winapi) c_int;
        fn cpu() ?u64 {
            if (builtin.os.tag == .linux) {
                var instant: std.c.timespec = undefined;
                if (std.c.clock_gettime(.THREAD_CPUTIME_ID, &instant) != 0) return null;
                return @as(u64, @intCast(instant.sec)) * 1_000_000 + @as(u64, @intCast(instant.nsec)) / 1000;
            }
            var creation: u64 = 0;
            var exit: u64 = 0;
            var kernel: u64 = 0;
            var user: u64 = 0;
            if (GetThreadTimes(GetCurrentThread(), &creation, &exit, &kernel, &user) == 0) return null;
            return (kernel + user) / 10;
        }
        fn milliseconds() u64 {
            if (builtin.os.tag == .windows) return GetTickCount64();
            var instant: std.c.timespec = undefined;
            if (std.c.clock_gettime(.MONOTONIC, &instant) != 0) return 0;
            return @as(u64, @intCast(instant.sec)) * 1000 + @as(u64, @intCast(instant.nsec)) / 1_000_000;
        }
        fn run(result: *u64) void {
            const before = cpu() orelse return;
            const start = milliseconds();
            var value: u64 = 1;
            while (milliseconds() - start < 200) {
                for (0..10000) |i| {
                    value = value *% 6364136223846793005 +% i;
                    std.mem.doNotOptimizeAway(value);
                }
            }
            result.* = (cpu() orelse return) - before;
        }
    };
    const before = try processCpuTimes(null);
    var worker_us: u64 = 0;
    const thread = try std.Thread.spawn(.{}, Worker.run, .{&worker_us});
    thread.join();
    const after = try processCpuTimes(null);
    try std.testing.expect(worker_us > 0);
    try std.testing.expect(after.user + after.system - before.user - before.system + 1000 >= worker_us);
}

test "native one-way pipes read status ownership and invalid modes" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;
    const opened = fileOpenPipe(null, "printf ABC; exit 3", .read_only);
    try std.testing.expectEqual(@as(forth.Cell, 0), opened.ior);
    const id: forth.Cell = @bitCast(opened.value);
    defer closeAllFiles();
    try std.testing.expectEqual(badFileIor(), fileClose(null, id));
    var text: [8]u8 = undefined;
    const read = fileRead(null, id, &text);
    try std.testing.expectEqual(@as(forth.UCell, 3), read.value);
    try std.testing.expectEqualStrings("ABC", text[0..3]);
    const closed = fileClosePipe(null, id);
    try std.testing.expectEqual(@as(forth.Cell, 0), closed.ior);
    try std.testing.expectEqual(@as(forth.Cell, if (builtin.os.tag == .windows) 3 else 768), @as(forth.Cell, @bitCast(closed.value)));
    try std.testing.expectEqual(badFileIor(), fileClosePipe(null, id).ior);
    try std.testing.expectEqual(forth.errnoIor(forth.errno_invalid), fileOpenPipe(null, "exit 0", .read_write).ior);
    try std.testing.expectEqual(forth.errnoIor(forth.errno_invalid), fileOpenPipe(null, "exit 0\x00bad", .read_only).ior);
}

test "native pipe write after child exit reports EPIPE and restores SIGPIPE disposition" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;
    var before = std.mem.zeroes(std.c.Sigaction);
    try std.testing.expectEqual(@as(c_int, 0), std.c.sigaction(.PIPE, null, &before));
    const opened = fileOpenPipe(null, "exit 0", .write_only);
    try std.testing.expectEqual(@as(forth.Cell, 0), opened.ior);
    const id: forth.Cell = @bitCast(opened.value);
    defer closeAllFiles();
    var saw_broken = false;
    for (0..100) |_| {
        const ior = fileWrite(null, id, "x");
        if (ior == forth.errnoIor(32)) {
            saw_broken = true;
            break;
        }
        try std.testing.expectEqual(@as(forth.Cell, 0), ior);
        try sleepMilliseconds(null, 10);
    }
    try std.testing.expect(saw_broken);
    var after = std.mem.zeroes(std.c.Sigaction);
    try std.testing.expectEqual(@as(c_int, 0), std.c.sigaction(.PIPE, null, &after));
    try std.testing.expectEqual(before.handler.handler, after.handler.handler);
    try std.testing.expectEqual(before.flags, after.flags);
    // Linux libc's sigset_t reserves more space than the kernel uses. glibc can
    // return unspecified bytes there, so compare only the actual signal bits.
    const mask_bytes = if (builtin.os.tag == .linux) @sizeOf(std.os.linux.sigset_t) else @sizeOf(@TypeOf(before.mask));
    try std.testing.expectEqualSlices(u8, std.mem.asBytes(&before.mask)[0..mask_bytes], std.mem.asBytes(&after.mask)[0..mask_bytes]);
    try std.testing.expectEqual(@as(forth.Cell, 0), fileFlush(null, id));
    try std.testing.expectEqual(@as(forth.Cell, 0), fileClosePipe(null, id).ior);
}

test "native pipe shutdown reaps writers and rejects foreign closes and seeks" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;
    defer closeAllFiles();
    const path = ".zig-cache/p06b-pipe-cleanup.txt";
    defer _ = fileDelete(null, path);
    const opened = fileOpenPipe(null, "cat > .zig-cache/p06b-pipe-cleanup.txt", .write_only);
    try std.testing.expectEqual(@as(forth.Cell, 0), opened.ior);
    const id: forth.Cell = @bitCast(opened.value);
    try std.testing.expectEqual(forth.errnoIor(29), fileSize(null, id).ior);
    try std.testing.expectEqual(forth.errnoIor(29), filePosition(null, id).ior);
    try std.testing.expectEqual(forth.errnoIor(29), fileReposition(null, id, 0));
    try std.testing.expectEqual(forth.errnoIor(29), fileResize(null, id, 0));
    try std.testing.expectEqual(@as(forth.Cell, 0), fileWrite(null, id, "kept"));
    closeAllFiles();
    for (file_slots) |slot| try std.testing.expect(slot.stream == null);
    const regular = fileOpen(null, path, .read_only, false);
    try std.testing.expectEqual(@as(forth.Cell, 0), regular.ior);
    const regular_id: forth.Cell = @bitCast(regular.value);
    try std.testing.expectEqual(badFileIor(), fileClosePipe(null, regular_id).ior);
    var bytes: [8]u8 = undefined;
    const read = fileRead(null, regular_id, &bytes);
    try std.testing.expectEqual(@as(forth.UCell, 4), read.value);
    try std.testing.expectEqualStrings("kept", bytes[0..4]);
    try std.testing.expectEqual(@as(forth.Cell, 0), fileClose(null, regular_id));
}

test "native pipe lifetime invalidates untracked child output cursor positions" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;
    const previous = output_cursor;
    defer output_cursor = previous;
    defer closeAllFiles();
    output_cursor.newline();
    output_cursor.feed("parent");
    const opened = fileOpenPipe(null, "printf x", .read_only);
    try std.testing.expectEqual(@as(forth.Cell, 0), opened.ior);
    try std.testing.expect(output_cursor.position() == null);
    // Parent output can establish a fresh row while the child is still live.
    output_cursor.newline();
    output_cursor.feed("new prompt");
    var byte: [1]u8 = undefined;
    const id: forth.Cell = @bitCast(opened.value);
    try std.testing.expectEqual(@as(forth.UCell, 1), fileRead(null, id, &byte).value);
    try std.testing.expectEqual(@as(forth.Cell, 0), fileClosePipe(null, id).ior);
    try std.testing.expect(output_cursor.position() == null);
}

// Keep native editor argument tests in the host test root even when main() is not called.
test {
    _ = @import("host_editor.zig");
}

test "interrupted or failed stdin reads do not become EOF" {
    const saved_eof = stdin_eof;
    const saved_error = input_failure;
    const saved_errno = std.c._errno().*;
    defer {
        stdin_eof = saved_eof;
        input_failure = saved_error;
        std.c._errno().* = saved_errno;
    }
    stdin_eof = false;
    std.c._errno().* = 0;
    input_failure = error.UserInterrupt;
    rememberStdinByte(-1);
    try std.testing.expect(!stdin_eof);
    input_failure = error.HostFailed;
    rememberStdinByte(-1);
    try std.testing.expect(!stdin_eof);
    input_failure = null;
    rememberStdinByte(-1);
    try std.testing.expect(stdin_eof);
    rememberStdinByte('Q');
    try std.testing.expect(!stdin_eof);
}

test "file timed input shares UTF-8 prefix with byte reads positions and CR pushback" {
    const path = ".zig-cache/sigma-file-timed-prefix.bin";
    defer _ = fileDelete(null, path);
    const opened = fileOpen(null, path, .read_write, true);
    try std.testing.expectEqual(@as(forth.Cell, 0), opened.ior);
    const id: forth.Cell = @bitCast(opened.value);
    defer _ = fileClose(null, id);
    try std.testing.expectEqual(@as(forth.Cell, 0), fileWrite(null, id, "\xe3\x81\x82\rxZ"));
    try std.testing.expectEqual(@as(forth.Cell, 0), fileReposition(null, id, 0));
    // Model a timed decoder's unconsumed prefix, using actual C-stream reads.
    for (0..6) |_| {
        const packet = (try filePollByte(id)).event;
        const d = &file_slots[fileSlot(id)].input;
        d.bytes[d.length] = @intCast(packet.value);
        d.length += 1;
    }
    try std.testing.expectEqual(@as(forth.UCell, 0), filePosition(null, id).value);
    try std.testing.expectEqual(@as(forth.UCell, 6), fileSize(null, id).value);
    var empty: [0]u8 = .{};
    try std.testing.expectEqual(@as(forth.UCell, 0), fileRead(null, id, &empty).value);
    try std.testing.expectEqual(@as(usize, 6), file_slots[fileSlot(id)].input.length);
    var line: [8]u8 = undefined;
    const result = fileReadLine(null, id, &line);
    try std.testing.expectEqualStrings("\xe3\x81\x82", line[0..result.length]);
    try std.testing.expectEqual(@as(u8, 'x'), (try fileKey(null, id)).byte.?);
    var tail: [1]u8 = undefined;
    try std.testing.expectEqual(@as(forth.UCell, 1), fileRead(null, id, &tail).value);
    try std.testing.expectEqual(@as(u8, 'Z'), tail[0]);
}

test "file timed input decodes scalars but leaves ESC and CtrlC as file characters" {
    const path = ".zig-cache/sigma-file-timed-scalar.bin";
    defer _ = fileDelete(null, path);
    const opened = fileOpen(null, path, .read_write, true);
    const id: forth.Cell = @bitCast(opened.value);
    defer _ = fileClose(null, id);
    try std.testing.expectEqual(@as(forth.Cell, 0), opened.ior);
    try std.testing.expectEqual(@as(forth.Cell, 0), fileWrite(null, id, "\xe3\x81\x82\x1b[A\x03"));
    try std.testing.expectEqual(@as(forth.Cell, 0), fileReposition(null, id, 0));
    for ([_]forth.Cell{ 0x3042, 27, '[', 'A', 3 }) |expected| {
        try std.testing.expectEqual(expected, (try fileEventWait(null, id, 0)).event.value);
    }
    try std.testing.expect((try fileEventWait(null, id, 0)) == .eof);
    try std.testing.expect((try fileEventWait(null, id, -1)) == .eof);
    try std.testing.expectEqual(badFileIor(), (try fileEventWait(null, -99, 0)).failure);
}

test "file prefix precedes observed EOF and is cleared on seek close and ID reuse" {
    const path = ".zig-cache/sigma-file-timed-life.bin";
    defer _ = fileDelete(null, path);
    const opened = fileOpen(null, path, .read_write, true);
    const id: forth.Cell = @bitCast(opened.value);
    var live = true;
    defer if (live) {
        _ = fileClose(null, id);
    };
    try std.testing.expectEqual(@as(forth.Cell, 0), fileWrite(null, id, "A"));
    try std.testing.expectEqual(@as(forth.Cell, 0), fileReposition(null, id, 0));
    try std.testing.expectEqual(@as(forth.UCell, 1), (try fileReady(null, id)).value);
    try std.testing.expect((try filePollByte(id)) == .eof);
    try std.testing.expectEqual(@as(forth.UCell, 0), fileEof(null, id).value);
    try std.testing.expectEqual(@as(u8, 'A'), (try fileKey(null, id)).byte.?);
    try std.testing.expectEqual(@as(forth.UCell, 1), fileEof(null, id).value);
    try std.testing.expectEqual(@as(forth.Cell, 0), fileReposition(null, id, 0));
    _ = try fileReady(null, id);
    try std.testing.expectEqual(@as(forth.Cell, 0), fileWrite(null, id, "B"));
    try std.testing.expectEqual(@as(forth.UCell, 1), filePosition(null, id).value);
    try std.testing.expectEqual(@as(forth.Cell, 0), fileReposition(null, id, 0));
    _ = try fileReady(null, id);
    try std.testing.expectEqual(@as(forth.Cell, 0), fileClose(null, id));
    live = false;
    const next = fileOpen(null, path, .read_only, false);
    try std.testing.expectEqual(@as(forth.Cell, 0), next.ior);
    try std.testing.expectEqual(opened.value, next.value);
    defer _ = fileClose(null, @bitCast(next.value));
    try std.testing.expectEqual(@as(usize, 0), file_slots[fileSlot(id)].input.length);
    try std.testing.expectEqual(@as(u8, 'B'), (try fileKey(null, id)).byte.?);
}

test "file wait cleanup interruption and fetched-byte restoration failure preserve prefix order" {
    const path = ".zig-cache/sigma-file-wait-fault.bin";
    defer _ = fileDelete(null, path);
    const opened = fileOpen(null, path, .read_write, true);
    const id: forth.Cell = @bitCast(opened.value);
    defer _ = fileClose(null, id);
    try std.testing.expectEqual(@as(forth.Cell, 0), opened.ior);
    try std.testing.expectEqual(@as(forth.Cell, 0), fileWrite(null, id, "\xe3\x81\x82"));
    try std.testing.expectEqual(@as(forth.Cell, 0), fileReposition(null, id, 0));
    test_file_commit_interrupt = true;
    defer test_file_commit_interrupt = false;
    try std.testing.expectError(error.UserInterrupt, fileEventWait(null, id, 0));
    try std.testing.expectEqual(@as(usize, 3), file_slots[fileSlot(id)].input.length);
    test_file_commit_interrupt = false;
    try std.testing.expectEqual(@as(forth.Cell, 0x3042), (try fileEventWait(null, id, 0)).event.value);
    try std.testing.expectEqual(@as(forth.Cell, 0), fileReposition(null, id, 0));
    const first = (try filePollByte(id)).event.value;
    try file_slots[fileSlot(id)].input.putByte(@intCast(first));
    test_file_restore_failure = true;
    defer test_file_restore_failure = false;
    try std.testing.expect((try filePollByte(id)) == .failure);
    test_file_restore_failure = false;
    try std.testing.expectEqualStrings("\xe3\x81", file_slots[fileSlot(id)].input.bytes[0..file_slots[fileSlot(id)].input.length]);
    var buffer: [8]u8 = undefined;
    test_file_read_failure = true;
    defer test_file_read_failure = false;
    try std.testing.expect(fileRead(null, id, &buffer).ior != 0);
    try std.testing.expectEqualStrings("\xe3\x81", file_slots[fileSlot(id)].input.bytes[0..file_slots[fileSlot(id)].input.length]);
    test_file_read_failure = false;
    const combined = fileRead(null, id, &buffer);
    try std.testing.expectEqual(@as(forth.Cell, 0), combined.ior);
    try std.testing.expectEqual(@as(forth.UCell, 3), combined.value);
    try std.testing.expectEqualStrings("\xe3\x81\x82", buffer[0..3]);
}

test "update stream reading then writing preserves logical position without an unread prefix" {
    const path = ".zig-cache/sigma-update-read-write.bin";
    defer _ = fileDelete(null, path);
    const opened = fileOpen(null, path, .read_write, true);
    const id: forth.Cell = @bitCast(opened.value);
    defer _ = fileClose(null, id);
    try std.testing.expectEqual(@as(forth.Cell, 0), opened.ior);
    try std.testing.expectEqual(@as(forth.Cell, 0), fileWrite(null, id, "ABC"));
    try std.testing.expectEqual(@as(forth.Cell, 0), fileReposition(null, id, 0));
    try std.testing.expectEqual(@as(u8, 'A'), (try fileKey(null, id)).byte.?);
    try std.testing.expectEqual(@as(usize, 0), file_slots[fileSlot(id)].input.length);
    try std.testing.expectEqual(@as(forth.Cell, 0), fileWrite(null, id, "X"));
    try std.testing.expectEqual(@as(forth.UCell, 2), filePosition(null, id).value);
    try std.testing.expectEqual(@as(forth.Cell, 0), fileReposition(null, id, 0));
    var result: [3]u8 = undefined;
    try std.testing.expectEqual(@as(forth.UCell, 3), fileRead(null, id, &result).value);
    try std.testing.expectEqualStrings("AXC", &result);
    // Appending after EOF also preserves position, including query-cleared EOF.
    try std.testing.expect((try fileKey(null, id)).byte == null);
    try std.testing.expectEqual(@as(forth.Cell, 0), fileWrite(null, id, "D"));
    try std.testing.expectEqual(@as(forth.UCell, 4), filePosition(null, id).value);
    try std.testing.expectEqual(@as(forth.Cell, 0), fileReposition(null, id, 4));
    _ = try fileReady(null, id); // EOF probe clears the C EOF indicator.
    try std.testing.expectEqual(@as(forth.Cell, 0), fileWrite(null, id, "E"));
    try std.testing.expectEqual(@as(forth.UCell, 5), filePosition(null, id).value);
}

test {
    _ = @import("host_file_reader.zig");
    _ = @import("host_pipe_access.zig");
}

test "native process pipes share FILE slots and stale proc references cannot close a reused file" {
    if (!@import("build_options").files or !process_native.available) return error.SkipZigTest;
    const allocator = std.testing.allocator;
    var environment = try std.process.Environ.createMap(std.testing.environ, allocator);
    defer environment.deinit();
    var host: HostContext = .{ .allocator = allocator, .executable_path = "", .environ_map = &environment };
    const context: ?*anyopaque = @ptrCast(&host);
    defer closeAllFiles();
    defer std.debug.assert(closeAllProcesses() == 0);
    const created = procNew(context);
    try std.testing.expectEqual(@as(forth.Cell, 0), created.ior);
    const id: forth.Cell = @bitCast(created.value);
    const executable = if (builtin.os.tag == .windows)
        try std.fs.path.join(allocator, &.{ environment.get("SystemRoot") orelse return error.SkipZigTest, "System32", "hostname.exe" })
    else
        try allocator.dupe(u8, "/bin/echo");
    defer allocator.free(executable);
    try std.testing.expectEqual(@as(forth.Cell, 0), procText(context, id, .argument, executable));
    if (builtin.os.tag != .windows) try std.testing.expectEqual(@as(forth.Cell, 0), procText(context, id, .argument, "R"));
    try std.testing.expectEqual(@as(forth.Cell, 0), try procLaunch(context, id));
    const out = procStream(context, id, 1);
    try std.testing.expectEqual(@as(forth.Cell, 0), out.ior);
    const output_id: forth.Cell = @bitCast(out.value);
    const ready = try fileWaitFiles(null, &.{output_id}, 3000, false);
    try std.testing.expectEqual(@as(forth.Cell, 0), ready.ior);
    try std.testing.expect((try fileKey(null, output_id)).byte != null);
    const ended = try procWait(context, id, 3000);
    try std.testing.expectEqual(@as(forth.Cell, 2), ended.state);
    try std.testing.expectEqual(@as(forth.Cell, 0), ended.code);
    try std.testing.expectEqual(@as(forth.Cell, 0), fileClose(null, output_id));
    const reused = fileOpen(null, ".zig-cache/proc-reused-file.tmp", .read_write, true);
    try std.testing.expectEqual(out.value, reused.value);
    try std.testing.expectEqual(badFileIor(), procStream(context, id, 1).ior);
    try std.testing.expectEqual(@as(forth.Cell, 0), procFree(context, id));
    try std.testing.expectEqual(@as(forth.Cell, 0), fileWrite(null, output_id, "K"));
    try std.testing.expectEqual(@as(forth.Cell, 0), fileClose(null, output_id));
    try std.testing.expectEqual(badFileIor(), procStatus(context, id).ior);
}

test "process publication rollback is retryable and closed-stream errors still reap the child" {
    if (!@import("build_options").files or !process_native.available) return error.SkipZigTest;
    const allocator = std.testing.allocator;
    var environment = try std.process.Environ.createMap(std.testing.environ, allocator);
    defer environment.deinit();
    var host: HostContext = .{ .allocator = allocator, .executable_path = "", .environ_map = &environment };
    const context: ?*anyopaque = @ptrCast(&host);
    defer closeAllFiles();
    defer std.debug.assert(closeAllProcesses() == 0);
    const executable = if (builtin.os.tag == .windows)
        try std.fs.path.join(allocator, &.{ environment.get("SystemRoot") orelse return error.SkipZigTest, "System32", "hostname.exe" })
    else
        try allocator.dupe(u8, "/bin/echo");
    defer allocator.free(executable);
    for (0..3) |failure_point| {
        const created = procNew(context);
        try std.testing.expectEqual(@as(forth.Cell, 0), created.ior);
        const id: forth.Cell = @bitCast(created.value);
        try std.testing.expectEqual(@as(forth.Cell, 0), procText(context, id, .argument, executable));
        test_process_published = 0;
        test_process_publish_fail_after = failure_point;
        defer test_process_publish_fail_after = null;
        try std.testing.expectEqual(forth.errnoIor(errno_io), try procLaunch(context, id));
        test_process_publish_fail_after = null;
        try std.testing.expectEqual(@as(forth.Cell, 0), procStatus(context, id).state);
        try std.testing.expectEqual(@as(forth.Cell, 0), procStatus(context, id).ior);
        for (file_slots) |slot| try std.testing.expect(slot.proc_owner != id);
        try std.testing.expectEqual(@as(forth.Cell, 0), try procLaunch(context, id));
        const ended = try procWait(context, id, 3000);
        try std.testing.expectEqual(@as(forth.Cell, 2), ended.state);
        test_process_close_error = true;
        defer test_process_close_error = false;
        try std.testing.expectEqual(forth.errnoIor(errno_io), procFree(context, id));
        try std.testing.expectEqual(badFileIor(), procStatus(context, id).ior);
        for (file_slots) |slot| try std.testing.expect(slot.proc_owner != id);
    }
}

test "saved app argv grammar preserves app options and isolates explicit host prefix" {
    var failed: []const u8 = "";
    const raw = try applicationStart(&.{ "app", "-e", "NOT-FORTH", "", "--trace" }, true, &failed);
    try std.testing.expect(raw.app_mode and !raw.prefix and !raw.start.trace);
    try std.testing.expectEqual(@as(usize, 1), raw.args_start);
    const escape = try applicationStart(&.{ "app", "--sigma", "--", "--sigma" }, true, &failed);
    try std.testing.expectEqual(@as(usize, 3), escape.args_start);
    const bypass = try applicationStart(&.{ "app", "--sigma", "--no-app", "--", "-e", "BYE" }, true, &failed);
    try std.testing.expect(!bypass.app_mode and bypass.start.no_app);
    try std.testing.expectEqual(@as(usize, 4), bypass.args_start);
    try std.testing.expectError(error.UnknownOption, applicationStart(&.{ "app", "--sigma", "--unknown=1" }, true, &failed));
    if (@import("build_options").debug) {
        try std.testing.expectError(error.DiagnosticRequiresNoApp, applicationStart(&.{ "app", "--sigma", "--format" }, true, &failed));
        const trace = try applicationStart(&.{ "app", "--sigma", "--trace", "--", "-e" }, true, &failed);
        try std.testing.expect(trace.app_mode and trace.start.trace);
    } else try std.testing.expectError(error.UnknownOption, applicationStart(&.{ "app", "--sigma", "--trace" }, true, &failed));
    const zero = try applicationStart(&.{ "app", "--sigma", "-m", "0" }, true, &failed);
    try std.testing.expect(zero.start.layout_seen and zero.start.m == null);
}

test "SAVESYS atomic publication retains prior output at every injected failure" {
    if (!@import("build_options").image) return error.SkipZigTest;
    const allocator = std.testing.allocator;
    const source = ".zig-cache/sigma-app-source-" ++ @tagName(builtin.os.tag) ++ ".bin";
    const output = ".zig-cache/sigma-app-output-" ++ @tagName(builtin.os.tag) ++ ".bin";
    try writeTestFile(source, "private program bytes without a saved image footer");
    defer _ = remove(source);
    defer _ = remove(output);
    var host = HostContext{ .allocator = allocator, .executable_path = source, .environ_map = undefined };
    const machine = try allocator.create(forth.State);
    defer allocator.destroy(machine);
    const storage = try forth.Storage.allocate(allocator, false, .small);
    defer storage.free(allocator);
    machine.init(.{ .context = null, .write_fn = discardOutput }, storage);
    defer test_save_fault = .none;
    for ([_]SaveFault{ .base, .image, .footer, .flush, .mode, .close, .publish }) |stage| {
        try writeTestFile(output, "OLD");
        test_save_fault = stage;
        try std.testing.expectError(error.FileUnavailable, saveExecutableImage(&host, output, machine));
        const file = fopen(output, "rb") orelse return error.TestUnexpectedResult;
        defer _ = fclose(file);
        var bytes: [4]u8 = undefined;
        try std.testing.expectEqual(@as(usize, 3), fread(&bytes, 1, bytes.len, file));
        try std.testing.expectEqualStrings("OLD", bytes[0..3]);
    }
    test_save_fault = .none;
    try std.testing.expectError(error.FileUnavailable, saveExecutableImage(&host, source, machine));
    try saveExecutableImage(&host, output, machine);
    const encoded = (try readEmbeddedImage(output, allocator)).?;
    defer allocator.free(encoded);
    const info = try @import("host_saved_image.zig").inspect(encoded, allocator);
    try std.testing.expectEqual(@as(?u16, null), info.entry);
}

test "PCM uses real native interrupt scope across waits and preserves the outer owner" {
    if (!audio) return error.SkipZigTest;
    const AudioEngine = @import("core/sound_engine.zig");
    const Scope = @import("host_wait.zig");
    const Fake = struct {
        engine: *AudioEngine.Engine,
        saw_guard: bool = false,
        inject_at_end: bool = false,
        fn get(context: ?*anyopaque) ?*AudioEngine.Engine {
            const f: *@This() = @ptrCast(@alignCast(context.?));
            return f.engine;
        }
        fn step(context: ?*anyopaque) forth.AudioWait {
            const f: *@This() = @ptrCast(@alignCast(context.?));
            if (!Scope.inputGuardActive()) return .host_failed;
            f.saw_guard = true;
            const outcome = Scope.audioWait(null);
            var samples: [960]i16 = undefined;
            f.engine.render(&samples);
            return outcome;
        }
        fn finish(context: ?*anyopaque, machine: *forth.State) forth.RuntimeError!void {
            const f: *@This() = @ptrCast(@alignCast(context.?));
            if (builtin.os.tag != .windows and f.inject_at_end) {
                f.inject_at_end = false;
                if (std.c.raise(.INT) != 0) return error.HostFailed;
            }
            try executionEnd(context, machine);
        }
        const ops = @import("core/host_interface.zig").ExecutionOps{ .begin = executionBegin, .poll = executionPoll, .end = finish };
    };
    const saved_terminal = host_input.input_is_terminal;
    host_input.input_is_terminal = false;
    defer host_input.input_is_terminal = saved_terminal;
    var engine = AudioEngine.Engine.init(48000);
    var frames: [4096]AudioEngine.stream.Frame = undefined;
    engine.pcm_session.storage = &frames;
    var fake = Fake{ .engine = &engine };
    const allocator = std.testing.allocator;
    const machine = try allocator.create(forth.State);
    defer allocator.destroy(machine);
    const storage = try forth.Storage.allocate(allocator, false, .small);
    defer storage.free(allocator);
    machine.init(.{ .context = &fake, .write_fn = discardOutput, .audio_fn = Fake.get, .audio_wait_fn = Fake.step, .audio_scope_ops = &Fake.ops, .standard_clock = @import("host_clock.zig").clock }, storage);
    try machine.interpretLine("REQUIRE-AUDIO ALSO AUDIO 48000 2 4096 PCM-OPEN THROW PCM-CLOSE");
    try std.testing.expectEqual(@as(i64, 0), try machine.pop());
    try std.testing.expect(fake.saw_guard);
    try std.testing.expect(!Scope.inputGuardActive());
    try machine.interpretLine("48000 2 4096 PCM-OPEN THROW");
    const id = try machine.pop();
    try Scope.beginExecution(machine, executionRawPoll);
    defer if (Scope.inputGuardActive()) {
        Scope.endExecution(machine) catch {};
    };
    fake.inject_at_end = true;
    try machine.push(id);
    try machine.interpretLine("PCM-CLOSE");
    try std.testing.expectEqual(@as(i64, 0), try machine.pop());
    try std.testing.expect(Scope.inputGuardActive());
    if (builtin.os.tag != .windows) {
        try std.testing.expectError(error.UserInterrupt, Scope.endExecution(machine));
    } else try Scope.endExecution(machine);
    try std.testing.expect(!Scope.inputGuardActive());
}
