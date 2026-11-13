const std = @import("std");
const builtin = @import("builtin");
const forth = @import("forth.zig");

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
    extern "c" fn fopen([*:0]const u8, [*:0]const u8) ?*anyopaque;
    extern "c" fn remove([*:0]const u8) c_int;
    extern "c" fn system(?[*:0]const u8) c_int;
};

const wide_c = struct {
    extern "c" fn _wfopen([*:0]const u16, [*:0]const u16) ?*anyopaque;
    extern "c" fn _wremove([*:0]const u16) c_int;
    extern "c" fn _wsystem(?[*:0]const u16) c_int;
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
const HostContext = struct { allocator: std.mem.Allocator, executable_path: [:0]const u8, environ_map: *std.process.Environ.Map, framebuffer: []u32 = &.{}, fonts: [2][]u64 = .{ &.{}, &.{} } };

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

/// Runs the command through the C library's `system`, which uses `cmd.exe /c` on
/// Windows and `/bin/sh -c` elsewhere.
fn runShellCommand(_: ?*anyopaque, command: []const u8) forth.RuntimeError!forth.Cell {
    var terminated: [4096:0]u8 = undefined;
    if (command.len >= terminated.len) return error.StringTooLong;
    // `system` would stop at an embedded NUL and run only the text before it.
    if (std.mem.indexOfScalar(u8, command, 0) != null) return error.HostFailed;
    @memcpy(terminated[0..command.len], command);
    terminated[command.len] = 0;
    // The command gets the terminal with its line input.
    host_input.leave();
    // The command's output comes after what Forth wrote before it.
    flushOutput();
    // On POSIX systems this is the wait status, as gforth's $? gives; on Windows, the exit code.
    utf8_console.pause();
    const status = system(&terminated);
    output_cursor.unknown();
    utf8_console.@"resume"();
    if (status == -1) return error.HostFailed;
    return status;
}

const max_open_files = 64;
const errno_io = 5;
const errno_too_many_files = 24;
var open_files: [max_open_files]?*anyopaque = @splat(null);
// Semantic EOF is independent of temporary seek/peek operations on C streams.
var file_eof: [max_open_files]bool = @splat(false);
var file_peeked: [max_open_files]bool = @splat(false);
var stdin_eof: bool = false;

fn fileSlot(fileid: forth.Cell) usize {
    return @intCast(fileid - forth.first_file_id);
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
    return open_files[@intCast(fileid - forth.first_file_id)];
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
        break :created c._wopen(name, @as(c_int, flags), native_mode);
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
    const slot = for (open_files, 0..) |file, index| {
        if (file == null) break index;
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
    if (builtin.os.tag == .windows) {
        const native = _get_osfhandle(file_number(file));
        if (native == -1) {
            _ = fclose(file);
            return .{ .ior = badFileIor() };
        }
        const handle: *anyopaque = @ptrFromInt(@as(usize, @bitCast(native)));
        if (GetFileType(handle) == 3 and setvbuf(file, null, @import("c_file")._IONBF, 0) != 0) {
            _ = fclose(file);
            return .{ .ior = forth.errnoIor(errno_io) };
        }
    }
    open_files[slot] = file;
    file_eof[slot] = false;
    file_peeked[slot] = false;
    return .{ .value = @intCast(forth.first_file_id + @as(forth.Cell, @intCast(slot))) };
}

fn fileClose(_: ?*anyopaque, fileid: forth.Cell) forth.Cell {
    if (fileid == forth.stdin_fileid or fileid == forth.stdout_fileid or fileid == forth.stderr_fileid) return 0;
    const file = openedFile(fileid) orelse return badFileIor();
    open_files[@intCast(fileid - forth.first_file_id)] = null;
    clearErrno();
    return if (fclose(file) == 0) 0 else lastIor();
}

/// Reads bytes from an open C stream, or from the terminal input for STDIN so that
/// the byte read ahead by KEY? is not lost.
const LineSource = struct {
    file: ?*anyopaque,
    fileid: forth.Cell,

    fn get(self: LineSource) c_int {
        if (self.file) |file| {
            if (file_eof[fileSlot(self.fileid)]) return -1;
            file_peeked[fileSlot(self.fileid)] = false;
            const byte = getc(file);
            file_eof[fileSlot(self.fileid)] = feof(file) != 0;
            return byte;
        }
        return readByte();
    }

    fn unget(self: LineSource, byte: c_int) void {
        if (self.file) |file| {
            _ = ungetc(byte, file);
            file_peeked[fileSlot(self.fileid)] = true;
            file_eof[fileSlot(self.fileid)] = false;
        } else terminalUnread(null, @intCast(byte));
    }
};

fn fileReadLine(_: ?*anyopaque, fileid: forth.Cell, buffer: []u8) forth.LineResult {
    const source = LineSource{ .fileid = fileid, .file = if (fileid == forth.stdin_fileid) null else openedFile(fileid) orelse return .{ .ior = badFileIor() } };
    clearErrno();
    var length: usize = 0;
    while (length < buffer.len) {
        const byte = source.get();
        if (byte < 0) {
            if (source.file) |file| {
                if (ferror(file) != 0) {
                    clearerr(file);
                    return .{ .ior = lastIor() };
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
    return .{ .length = length, .found = true };
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
    if (buffer.len == 0 or file_eof[fileSlot(fileid)]) return .{};
    file_peeked[fileSlot(fileid)] = false;
    const count = fread(buffer.ptr, 1, buffer.len, file);
    file_eof[fileSlot(fileid)] = feof(file) != 0;
    if (count < buffer.len and ferror(file) != 0) {
        clearerr(file);
        return .{ .ior = lastIor() };
    }
    return .{ .value = count };
}

fn fileWrite(context: ?*anyopaque, fileid: forth.Cell, bytes: []const u8) forth.Cell {
    if (fileid == forth.stdout_fileid) {
        terminalWrite(context, bytes);
        return 0;
    }
    if (fileid == forth.stderr_fileid) return if (writeStandardError(bytes)) 0 else forth.errnoIor(errno_io);
    const file = openedFile(fileid) orelse return badFileIor();
    clearErrno();
    return if (fwrite(bytes.ptr, 1, bytes.len, file) == bytes.len) 0 else lastIor();
}

fn fileSize(_: ?*anyopaque, fileid: forth.Cell) forth.FileResult {
    const file = openedFile(fileid) orelse return .{ .ior = badFileIor() };
    clearErrno();
    const position = tell64(file);
    if (position < 0 or seek64(file, 0, 2) != 0) return .{ .ior = lastIor() };
    file_peeked[fileSlot(fileid)] = false; // seek discards libc query pushback
    const end = tell64(file);
    if (end < 0 or seek64(file, position, 0) != 0) return .{ .ior = lastIor() };
    return .{ .value = @intCast(end) };
}

fn fileReposition(_: ?*anyopaque, fileid: forth.Cell, position: forth.UCell) forth.Cell {
    const file = openedFile(fileid) orelse return badFileIor();
    clearErrno();
    if (seek64(file, @intCast(position), 0) != 0) return lastIor();
    file_eof[fileSlot(fileid)] = false;
    file_peeked[fileSlot(fileid)] = false;
    return 0;
}

fn filePosition(_: ?*anyopaque, fileid: forth.Cell) forth.FileResult {
    const file = openedFile(fileid) orelse return .{ .ior = badFileIor() };
    clearErrno();
    const position = tell64(file);
    return if (position < 0) .{ .ior = lastIor() } else .{ .value = @intCast(position) };
}

fn fileResize(_: ?*anyopaque, fileid: forth.Cell, size: forth.UCell) forth.Cell {
    const file = openedFile(fileid) orelse return badFileIor();
    if (size > std.math.maxInt(i64)) return forth.errnoIor(forth.errno_invalid);
    clearErrno();
    if (fflush(file) != 0) return lastIor();
    // _chsize_s returns the error number itself; ftruncate returns -1 and sets errno.
    const result = resizeDescriptor(file_number(file), @intCast(size));
    if (result == 0) return 0;
    return if (builtin.os.tag == .windows) forth.errnoIor(result) else lastIor();
}

fn fileFlush(_: ?*anyopaque, fileid: forth.Cell) forth.Cell {
    if (fileid == forth.stdout_fileid) flushOutput();
    if (fileid == forth.stdout_fileid or fileid == forth.stderr_fileid) return 0;
    const file = openedFile(fileid) orelse return badFileIor();
    clearErrno();
    return if (fflush(file) == 0) 0 else lastIor();
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
    for (&open_files) |*slot| {
        if (slot.*) |file| _ = fclose(file);
        slot.* = null;
    }
}

/// Return a byte without changing the caller's ownership of the stream.
fn fileKey(_: ?*anyopaque, fileid: forth.Cell) forth.RuntimeError!forth.FileKeyResult {
    flushOutput();
    if (fileid == forth.stdin_fileid) return .{ .byte = try fileStdinByte(true) };
    const file = openedFile(fileid) orelse return .{ .ior = badFileIor() };
    clearErrno();
    if (file_eof[fileSlot(fileid)]) return .{};
    file_peeked[fileSlot(fileid)] = false;
    const byte = getc(file);
    file_eof[fileSlot(fileid)] = feof(file) != 0;
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

fn fileEof(_: ?*anyopaque, fileid: forth.Cell) forth.FileResult {
    if (fileid == forth.stdin_fileid) return .{ .value = @intFromBool(stdin_eof) };
    if (fileid == forth.stdout_fileid or fileid == forth.stderr_fileid) return .{};
    _ = openedFile(fileid) orelse return .{ .ior = badFileIor() };
    return .{ .value = @intFromBool(file_eof[fileSlot(fileid)]) };
}

/// Probe the C stream itself, including bytes it prefetched before this query.
/// Keep semantic EOF unchanged and return every peeked byte with ungetc.
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
    const file = openedFile(fileid) orelse return .{ .ior = badFileIor() };
    const slot = fileSlot(fileid);
    if (file_eof[slot]) return .{};
    clearErrno();
    if (builtin.os.tag == .windows) {
        if (file_peeked[slot]) return .{ .value = 1 };
        const native = _get_osfhandle(file_number(file));
        if (native == -1) return .{ .ior = badFileIor() };
        const handle: *anyopaque = @ptrFromInt(@as(usize, @bitCast(native)));
        switch (GetFileType(handle)) {
            1 => {}, // A disk-file read cannot wait for a producer.
            3 => {
                var available: u32 = 0;
                if (PeekNamedPipe(handle, null, 0, null, &available, null) == 0) {
                    if (GetLastError() != 109) return .{ .ior = forth.errnoIor(errno_io) };
                } else if (available == 0) return .{};
            },
            else => return .{ .ior = forth.errnoIor(forth.errno_invalid) },
        }
    }
    const old_flags = if (builtin.os.tag == .windows) 0 else fcntl(file_number(file), @import("c_file").F_GETFL);
    if (builtin.os.tag != .windows) {
        if (old_flags < 0 or fcntl(file_number(file), @import("c_file").F_SETFL, @as(c_int, old_flags | @import("c_file").O_NONBLOCK)) < 0) return .{ .ior = lastIor() };
    }
    const byte = getc(file);
    const failed = ferror(file) != 0;
    const read_errno = std.c._errno().*;
    // A query must not leave a speculative EOF/error on the underlying stream.
    if (byte < 0) clearerr(file);
    const restored = builtin.os.tag == .windows or fcntl(file_number(file), @import("c_file").F_SETFL, @as(c_int, old_flags)) >= 0;
    const restore_ior = if (restored) 0 else lastIor();
    if (byte >= 0) {
        if (ungetc(byte, file) < 0) return .{ .ior = forth.errnoIor(errno_io) };
        file_peeked[slot] = true;
    }
    if (!restored) return .{ .ior = restore_ior };
    if (byte >= 0) return .{ .value = 1 };
    if (failed) {
        if (read_errno == 0) return .{ .ior = forth.errnoIor(errno_io) };
        if (builtin.os.tag != .windows and (read_errno == @import("c_file").EAGAIN or read_errno == @import("c_file").EINTR)) return .{};
        return .{ .ior = forth.errnoIor(read_errno) };
    }
    return .{};
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
            if (!redirectedInputReady()) break :next null;
            clearErrno();
            const read = rawStandardInputByte();
            if (read < 0) {
                if (std.c._errno().* != 0) {
                    if (builtin.os.tag != .windows and std.c._errno().* == @intFromEnum(std.c.E.INTR)) break :next null;
                    return error.HostFailed;
                }
                if (wait) stdin_eof = true;
                return null;
            }
            break :next @intCast(read);
        };
        if (byte) |value| {
            if (host_input.input_is_terminal and value == 3) return error.UserInterrupt;
            if (wait) stdin_eof = false;
            return value;
        }
        if (!wait) return null;
        try sleepMilliseconds(null, 1);
    }
}

const host_directories = @import("host_directories.zig");
const file_ops = forth.FileOps{ .open_dir = host_directories.open, .read_dir = host_directories.read, .close_dir = host_directories.close, .mkdir = makeDirectory, .get_dir = getDirectory, .set_dir = setDirectory, .user_home = userHome, .open = fileOpen, .close = fileClose, .read_line = fileReadLine, .read = fileRead, .write = fileWrite, .size = fileSize, .reposition = fileReposition, .position = filePosition, .resize = fileResize, .flush = fileFlush, .delete = fileDelete, .rename = fileRename, .status = fileStatus, .key = fileKey, .ready = fileReady, .eof = fileEof, .create_mode = fileCreateMode };

/// Lets the Windows console interpret the ANSI sequences written by PAGE.
fn enableVirtualTerminal() void {
    if (builtin.os.tag == .windows) {
        const std_output_handle: u32 = @bitCast(@as(i32, -11));
        const handle = GetStdHandle(std_output_handle) orelse return;
        var mode: u32 = 0;
        if (GetConsoleMode(handle, &mode) == 0) return;
        _ = SetConsoleMode(handle, mode | std.os.windows.ENABLE_VIRTUAL_TERMINAL_PROCESSING);
    }
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
        return -1;
    }
} else struct {
    extern "kernel32" fn SetConsoleCP(u32) callconv(.winapi) c_int;
    extern "kernel32" fn GetConsoleCP() callconv(.winapi) u32;
    extern "kernel32" fn ReadConsoleW(*anyopaque, [*]u16, u32, *u32, ?*anyopaque) callconv(.winapi) c_int;
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
        while (start == end) {
            if (ended or !fill()) {
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
        if (ReadConsoleW(input.?, &wide, wide.len, &read, null) == 0 or read == 0) return false;
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
    if (byte >= 0) stdin_eof = false else if (std.c._errno().* == 0) stdin_eof = true;
    return byte;
}

fn rawStandardInputByte() c_int {
    if (builtin.os.tag == .windows and utf8_console.input != null) return utf8_console.readByte();
    if (!host_input.input_is_terminal) {
        var byte: [1]u8 = undefined;
        if (builtin.os.tag == .windows) {
            const handle = GetStdHandle(@bitCast(@as(i32, -10))) orelse {
                std.c._errno().* = forth.errno_bad_file;
                return -1;
            };
            var count: u32 = 0;
            if (ReadFile(handle, &byte, 1, &count, null) == 0) {
                const code = GetLastError();
                if (code != 109 and code != 38) std.c._errno().* = errno_io; // broken pipe / EOF
                return -1;
            }
            return if (count == 1) byte[0] else -1;
        }
        return if (std.c.read(0, &byte, 1) == 1) byte[0] else -1;
    }
    // POSIX terminal and EKEY must share the descriptor: getchar's read-ahead
    // would hide the rest of a canonical line from the raw EKEY reader.
    if (builtin.os.tag != .windows) {
        var byte: [1]u8 = undefined;
        while (true) {
            clearErrno();
            const count = std.c.read(0, &byte, 1);
            if (count == 1) return byte[0];
            if (count < 0 and std.c._errno().* == @backingInt(std.c.E.INTR)) continue;
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
fn readEmbeddedImage(path: [:0]const u8, allocator: std.mem.Allocator) ?[]u8 {
    const file = fopen(path.ptr, "rb") orelse return null;
    defer _ = fclose(file);
    if (fseek(file, 0, 2) != 0) return null;
    const end = ftell(file);
    if (end < image_footer_size or fseek(file, end - image_footer_size, 0) != 0) return null;
    var footer: [image_footer_size]u8 = undefined;
    if (fread(&footer, 1, footer.len, file) != footer.len or !std.mem.eql(u8, footer[0..8], image_footer_magic)) return null;
    const image_len = readU32(footer[8..12]);
    const base_len = readU64(footer[12..20]);
    if (base_len + image_len + image_footer_size != end) return null;
    if (fseek(file, @intCast(base_len), 0) != 0) return null;
    const image = allocator.alloc(u8, image_len) catch return null;
    if (fread(image.ptr, 1, image.len, file) != image.len) {
        allocator.free(image);
        return null;
    }
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
fn parseStartOptions(args: []const []const u8, failed: *[]const u8) error{ MissingValue, InvalidSize, InvalidNumber }!StartOptions {
    var options = StartOptions{};
    var index: usize = 1;
    while (index < args.len) {
        const argument = args[index];
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
        const option = found orelse break;
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

fn saveExecutableImage(context: ?*anyopaque, output_path: []const u8, machine: *forth.State) forth.RuntimeError!void {
    const host: *HostContext = @ptrCast(@alignCast(context orelse return error.FileUnavailable));
    const allocator = host.allocator;
    const executable_path = host.executable_path;
    if (output_path.len >= 4096 or std.ascii.eqlIgnoreCase(output_path, executable_path)) return error.FileUnavailable;
    var terminated_output: [4096:0]u8 = undefined;
    @memcpy(terminated_output[0..output_path.len], output_path);
    terminated_output[output_path.len] = 0;
    const source = fopen(executable_path.ptr, "rb") orelse return error.FileUnavailable;
    defer _ = fclose(source);
    if (fseek(source, 0, 2) != 0) return error.FileUnavailable;
    var base_len: u64 = @intCast(ftell(source));
    if (base_len >= image_footer_size and fseek(source, @intCast(base_len - image_footer_size), 0) == 0) {
        var previous_footer: [image_footer_size]u8 = undefined;
        if (fread(&previous_footer, 1, previous_footer.len, source) == previous_footer.len and std.mem.eql(u8, previous_footer[0..8], image_footer_magic)) {
            const prior_base = readU64(previous_footer[12..20]);
            if (prior_base <= base_len) base_len = prior_base;
        }
    }
    if (fseek(source, 0, 0) != 0) return error.FileUnavailable;
    const image = allocator.alloc(u8, try machine.encodedSize()) catch return error.MemoryExhausted;
    defer allocator.free(image);
    const image_len = try machine.encodeImage(image);
    const destination = fopen(&terminated_output, "wb") orelse return error.FileUnavailable;
    defer _ = fclose(destination);
    var buffer: [8192]u8 = undefined;
    var copied: u64 = 0;
    while (copied < base_len) {
        const wanted: usize = @intCast(@min(buffer.len, base_len - copied));
        const amount = fread(&buffer, 1, wanted, source);
        if (amount != wanted or fwrite(&buffer, 1, amount, destination) != amount) return error.FileUnavailable;
        copied += amount;
    }

    if (fwrite(image.ptr, 1, image_len, destination) != image_len) return error.FileUnavailable;
    var footer: [image_footer_size]u8 = undefined;
    @memcpy(footer[0..8], image_footer_magic);
    writeU32(footer[8..12], @intCast(image_len));
    writeU64(footer[12..20], base_len);
    if (fwrite(&footer, 1, footer.len, destination) != footer.len) return error.FileUnavailable;
    // A C stream makes the file without the permission to run it; as a linker does, the
    // executable gets every permission the umask lets through (usually rwxr-xr-x).
    if (builtin.os.tag != .windows) {
        const mask = std.c.umask(0);
        _ = std.c.umask(mask);
        if (std.c.chmod(&terminated_output, 0o777 & ~mask) != 0) return error.FileUnavailable;
    }
}

/// Writes to the standard error handle directly, as std.Io did: it is not buffered, so it
/// does not wait for a flush of the C library's stderr stream.
fn writeStandardError(bytes: []const u8) bool {
    // Standard output written before keeps its place when both go to one terminal.
    flushOutput();
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
fn executablePathAlloc(allocator: std.mem.Allocator, argv0: ?[*:0]const u8) ![:0]u8 {
    switch (builtin.os.tag) {
        .windows => {
            const name = std.os.windows.peb().ProcessParameters.ImagePathName;
            return std.unicode.wtf16LeToWtf8AllocZ(allocator, name.Buffer.?[0 .. name.Length / 2]);
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
        if (output_used == output_buffer.len) flushOutput();
        const amount = @min(rest.len, output_buffer.len - output_used);
        @memcpy(output_buffer[output_used..][0..amount], rest[0..amount]);
        output_used += amount;
        rest = rest[amount..];
    }
    if (output_is_terminal and std.mem.indexOfScalar(u8, bytes, '\n') != null) flushOutput();
}

/// PLAY waiting for room in its queues: what was written before shows during the wait.
fn audioWait(_: ?*anyopaque) forth.AudioWait {
    flushOutput();
    return host_audio.wait();
}

/// Writes the buffered output through the C library, as before, so that the C library
/// still turns LF into CR LF where it did.
fn flushOutput() void {
    if (output_used == 0) return;
    for (output_buffer[0..output_used]) |byte| _ = putchar(byte);
    output_used = 0;
    _ = fflush(null);
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
    return standardInputByte();
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
    flushOutput();
    output_cursor.unknown();
    if (try terminalBufferedKey(null)) |byte| return byte;
    if (builtin.os.tag == .windows) if (utf8_console.takePendingByte()) |byte| {
        if (byte == 3) return error.UserInterrupt;
        stdin_eof = false;
        return byte;
    };
    const start = monotonicMilliseconds(null);

    while (true) {
        if (host_input.input_is_terminal) {
            if (host_input.nextStandard()) |event| {
                if (event == 3) return error.UserInterrupt;
                stdin_eof = false;
                return event;
            }
        } else if (redirectedInputReady()) {
            const byte = standardInputByte();
            return if (byte < 0) null else byte;
        }
        if (timeout_ms >= 0) {
            const now = monotonicMilliseconds(null);
            if (now - start >= timeout_ms) return null;
        }
        try sleepMilliseconds(null, 1);
    }
}

/// XKEY gives back a byte it read: it becomes the byte read ahead, as KEY? leaves one.
fn terminalUnread(_: ?*anyopaque, byte: u8) void {
    stdin_eof = false;
    if (lookahead) |old| {
        // EKEY restores at most 31 consumed bytes; XKEY and READ-LINE restore
        // one consumed byte. They cannot grow this stack beyond that read-ahead.
        std.debug.assert(unread_count < unread_bytes.len);
        unread_bytes[unread_count] = old;
        unread_count += 1;
    }
    lookahead = byte;
}

fn terminalBufferedKey(_: ?*anyopaque) forth.RuntimeError!?u8 {
    const byte = popLookahead() orelse return null;
    if (host_input.input_is_terminal and byte == 3) return error.UserInterrupt;
    stdin_eof = false;
    return byte;
}

fn terminalKeyReady(_: ?*anyopaque) bool {
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

fn mouseMode(_: ?*anyopaque, on: bool) void {
    host_input.setMouse(on);
}

fn cursorPosition(_: ?*anyopaque) ?forth.CursorPosition {
    return host_input.cursor();
}

fn terminalRead(_: ?*anyopaque, buffer: []u8) ?[]const u8 {
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

fn interpretAndPrompt(machine: *forth.State, line: []const u8) void {
    machine.resetSteps();
    machine.interpretLine(line) catch |err| {
        machine.report(err);
        return;
    };
    if (!machine.defining) machine.write(" OK\n");
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
    const status = run(init) catch |err| {
        // As the standard library reports an error returned from main.
        var message: [128]u8 = undefined;
        _ = writeStandardError(std.fmt.bufPrint(&message, "error: {s}\n", .{@errorName(err)}) catch "error\n");
        return 1;
    };
    return if (status == 0 and lint_findings != 0) 2 else status;
}

/// Returns the exit status: 1 when an argument fails, as in gforth, and 0 otherwise.
fn run(init: std.process.Init.Minimal) !u8 {
    // The C library's allocator, which std.process.Init also gives in a release build
    // that links the C library.
    const allocator = std.heap.c_allocator;
    var environ_map = try std.process.Environ.createMap(init.environ, allocator);
    defer environ_map.deinit();
    const argv0: ?[*:0]const u8 = if (builtin.os.tag == .windows or init.args.vector.len == 0) null else init.args.vector[0];
    const executable_path = try executablePathAlloc(allocator, argv0);
    defer allocator.free(executable_path);
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
    // The output kept in the buffer goes out however the session ends.
    defer flushOutput();

    enableVirtualTerminal();
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
    var failed_option: []const u8 = "";
    const start = parseStartOptions(argument_list.items, &failed_option) catch |err| {
        terminalWrite(null, failed_option);
        terminalWrite(null, switch (err) {
            error.MissingValue => ": OPTION REQUIRES AN ARGUMENT !\n",
            error.InvalidSize => ": INVALID SIZE !\n",
            error.InvalidNumber => ": INVALID NUMBER !\n",
        });
        return 1;
    };
    // --format and --format-check read the files as text; nothing is run.
    if (start.format != .none) return formatFiles(allocator, argument_list.items[start.next..], start.format == .check, @intCast(start.format_indent));
    const embedded = readEmbeddedImage(executable_path, allocator);
    defer if (embedded) |image| allocator.free(image);
    var sizes = startSizes(start, &failed_option) orelse {
        terminalWrite(null, failed_option);
        terminalWrite(null, ": INVALID SIZE !\n");
        return 1;
    };
    // A saved program keeps addresses, so it runs with the layout it was saved with.
    if (embedded) |image| if (forth.State.imageLayout(image)) |layout| {
        if (start.m != null or start.l != null) {
            terminalWrite(null, if (start.m != null) "-m" else "-l");
            terminalWrite(null, ": A SAVED PROGRAM KEEPS ITS MEMORY LAYOUT !\n");
            return 1;
        }
        sizes.m = layout[0];
        sizes.l = layout[1];
    };
    const storage = forth.Storage.allocate(std.heap.page_allocator, true, sizes) catch {
        terminalWrite(null, "OUT OF MEMORY !\n");
        return 1;
    };
    defer storage.free(std.heap.page_allocator);
    machine.init(.{ .gamepad_ops = if (graphics) &host_gamepad.ops else null, .context = @ptrCast(&host), .write_fn = terminalWrite, .read_fn = terminalRead, .load_fn = loadDictionary, .save_fn = saveDictionary, .savesys_fn = saveExecutableImage, .key_fn = terminalKey, .event_key_fn = terminalEventKey, .monotonic_ms_fn = monotonicMilliseconds, .key_ready_fn = terminalKeyReady, .buffered_key_fn = terminalBufferedKey, .unread_fn = terminalUnread, .sleep_fn = sleepMilliseconds, .utime_fn = microsecondsSinceEpoch, .ntime_fn = nanosecondsSinceEpoch, .cputime_fn = processCpuTimes, .local_time_fn = localTime, .getenv_fn = environmentValue, .system_fn = runShellCommand, .file_ops = &file_ops, .framebuffer_fn = graphicsBuffer, .image_alloc_fn = if (graphics) imageAlloc else null, .image_free_fn = if (graphics) imageFree else null, .terminal_size_fn = terminalSize, .terminal_utf8_fn = terminalUtf8, .window_fn = if (host_window.available) host_window.show else null, .input_fn = inputEvent, .mouse_fn = mouseMode, .cursor_fn = cursorPosition, .font_buffer_fn = if (graphics) fontBuffer else null, .font_free_fn = if (graphics) fontFree else null, .system_font_fn = if (graphics and host_font.available) host_font.select else null, .system_glyph_fn = if (graphics and host_font.available) host_font.glyph else null, .process_start_fn = if (graphics) host_process.start else null, .process_write_fn = if (graphics) host_process.write else null, .process_read_fn = if (graphics) host_process.read else null, .process_stop_fn = if (graphics) host_process.stop else null, .audio_fn = if (audio) host_audio.start else null, .audio_device_fn = if (audio) host_audio.hasDevice else null, .audio_wait_fn = if (audio) audioWait else null }, storage);
    defer closeAllFiles();
    defer host_directories.closeAll();
    // The images of the pool, when the session ends without BYE.
    defer forth.releaseImages(machine);
    defer host_window.close();
    defer if (graphics) host_gamepad.close();
    // The terminal gets its line input back (and stops reporting the mouse) at the end.
    defer host_input.leave();
    // The Tcl program of TCL, if it was started, ends with Sigma.
    defer if (graphics) {
        _ = host_process.stop(null);
    };
    // Before the image: with the trace, its short definitions stay calls.
    machine.step_limit = start.max_steps;
    machine.tracing = start.trace;
    machine.trace_limit = start.trace_limit;
    machine.plain_calls = start.trace or start.profile or start.coverage;
    machine.cover_blocks = start.coverage;
    if (start.debug_log) |path| {
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
    const lint: ?*forth.Lint = if (start.lint) std.heap.page_allocator.create(forth.Lint) catch {
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
    const profile: ?*forth.Profile = if (start.profile or start.coverage) std.heap.page_allocator.create(forth.Profile) catch {
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
    if (embedded) |image| machine.restoreFreshImage(image) catch machine.write("INVALID IMAGE !\n");

    // The other arguments go into Forth memory, where ARGC, ARGV, ARG, and NEXT-ARG see
    // them, after the program's name. This comes after the image is restored, since
    // restoring clears that area.
    const kept_arguments = argument_list.items[start.next - 1 ..];
    kept_arguments[0] = argument_list.items[0];
    machine.setArguments(kept_arguments) catch |err| {
        machine.report(err);
        return 1;
    };
    // As in gforth: each argument names a file to include, in order, and `-e` (or
    // `--evaluate`) interprets the next argument. Each is removed from the arguments
    // before it runs, so a file sees only the ones after it, and the ones it takes with
    // NEXT-ARG are not processed here. The first error ends the program with status 1;
    // BYE ends it with status 0; otherwise the interactive session follows.
    var argument_text: [4096]u8 = undefined;
    while (true) {
        machine.resetSteps();
        const option = nextArgument(machine, &argument_text) catch |err| {
            machine.report(err);
            return 1;
        } orelse break;
        if (std.mem.eql(u8, option, "-e") or std.mem.eql(u8, option, "--evaluate")) {
            var option_name: [16]u8 = undefined;
            const name = option_name[0..option.len];
            @memcpy(name, option);
            const source = nextArgument(machine, &argument_text) catch |err| {
                machine.report(err);
                return 1;
            } orelse {
                machine.write(name);
                machine.write(": OPTION REQUIRES AN ARGUMENT !\n");
                return 1;
            };
            machine.interpretLine(source) catch |err| {
                machine.report(err);
                return 1;
            };
        } else {
            machine.includeFile(option) catch |err| {
                // An error inside the file names the file and line; one opening it does not.
                if (machine.error_location == null) {
                    machine.write(option);
                    machine.write(": ");
                }
                machine.report(err);
                return 1;
            };
        }
        if (machine.halted) return finishBlocks(machine);
    }

    // With --lint, the findings take the place of the interactive session.
    if (start.lint) return finishBlocks(machine);
    // The banner comes after the arguments, as in gforth.
    machine.write(banner);
    var line: [4096]u8 = undefined;
    var used: usize = 0;
    var discarding_line = false;
    while (!machine.halted) {
        if (editedLine(&line, &line_history)) |result| {
            const text = result.line orelse break;
            if (result.overflow) machine.write("LINE TOO LONG\n") else interpretAndPrompt(machine, text);
            continue;
        }
        const ch = readByte();
        if (ch < 0) {
            if (!discarding_line and used != 0) interpretAndPrompt(machine, line[0..used]);
            break;
        }
        const byte: u8 = @intCast(ch);
        if (byte == '\r' or byte == '\n') {
            if (!discarding_line and used != 0) interpretAndPrompt(machine, line[0..used]);
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
    @import("core/blocks.zig").saveAll(machine) catch |err| {
        machine.report(err);
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
    for (open_files) |slot| try std.testing.expect(slot == null);
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
    for (open_files) |slot| try std.testing.expect(slot == null);
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
    for (open_files) |slot| try std.testing.expect(slot == null);

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
    machine.init(.{ .context = @ptrCast(&host), .write_fn = discardOutput, .file_ops = &file_ops, .system_fn = runShellCommand }, storage);
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
    _ = host_input;
    _ = host_line;
    _ = host_process;
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
