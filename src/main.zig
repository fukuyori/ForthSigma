const std = @import("std");
const builtin = @import("builtin");
const forth = @import("forth.zig");

extern "c" fn getchar() c_int;
extern "c" fn putchar(c_int) c_int;
extern "c" fn fflush(?*anyopaque) c_int;
extern "c" fn fopen([*:0]const u8, [*:0]const u8) ?*anyopaque;
extern "c" fn fclose(?*anyopaque) c_int;
extern "c" fn fseek(?*anyopaque, c_long, c_int) c_int;
extern "c" fn ftell(?*anyopaque) c_long;
extern "c" fn fread([*]u8, usize, usize, ?*anyopaque) usize;
extern "c" fn fwrite([*]const u8, usize, usize, ?*anyopaque) usize;
extern "c" fn system(?[*:0]const u8) c_int;
extern "c" fn getc(?*anyopaque) c_int;
extern "c" fn ungetc(c_int, ?*anyopaque) c_int;
extern "c" fn ferror(?*anyopaque) c_int;
extern "c" fn clearerr(?*anyopaque) void;
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
extern "kernel32" fn GetStdHandle(u32) callconv(.winapi) ?*anyopaque;
extern "kernel32" fn GetConsoleMode(*anyopaque, *u32) callconv(.winapi) c_int;
extern "kernel32" fn SetConsoleMode(*anyopaque, u32) callconv(.winapi) c_int;

const image_footer_size = 20;
const image_footer_magic = "SIGEND01";
const HostContext = struct { allocator: std.mem.Allocator, executable_path: [:0]const u8, io: std.Io, environ_map: *std.process.Environ.Map };

fn hostContext(context: ?*anyopaque) forth.RuntimeError!*HostContext {
    return @ptrCast(@alignCast(context orelse return error.HostUnavailable));
}

fn sleepMilliseconds(context: ?*anyopaque, milliseconds: forth.Cell) forth.RuntimeError!void {
    const host = try hostContext(context);
    std.Io.sleep(host.io, .fromMilliseconds(milliseconds), .awake) catch return error.HostFailed;
}

fn microsecondsSinceEpoch(context: ?*anyopaque) forth.RuntimeError!forth.Double {
    const host = try hostContext(context);
    const now = std.Io.Timestamp.now(host.io, .real);
    return @divFloor(now.nanoseconds, std.time.ns_per_us);
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
fn runShellCommand(_: ?*anyopaque, command: []const u8) forth.RuntimeError!void {
    var terminated: [4096:0]u8 = undefined;
    if (command.len >= terminated.len) return error.StringTooLong;
    // `system` would stop at an embedded NUL and run only the text before it.
    if (std.mem.indexOfScalar(u8, command, 0) != null) return error.HostFailed;
    @memcpy(terminated[0..command.len], command);
    terminated[command.len] = 0;
    if (system(&terminated) == -1) return error.HostFailed;
}

const max_open_files = 64;
const errno_io = 5;
const errno_too_many_files = 24;
var open_files: [max_open_files]?*anyopaque = @splat(null);

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

fn fileOpen(_: ?*anyopaque, name: []const u8, access: forth.FileAccess, create: bool) forth.FileResult {
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
    const file = fopen(&path, mode) orelse return .{ .ior = lastIor() };
    open_files[slot] = file;
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

    fn get(self: LineSource) c_int {
        return if (self.file) |file| getc(file) else readByte();
    }

    fn unget(self: LineSource, byte: c_int) void {
        if (self.file) |file| {
            _ = ungetc(byte, file);
        } else lookahead = @intCast(byte);
    }
};

fn fileReadLine(_: ?*anyopaque, fileid: forth.Cell, buffer: []u8) forth.LineResult {
    const source = LineSource{ .file = if (fileid == forth.stdin_fileid) null else openedFile(fileid) orelse return .{ .ior = badFileIor() } };
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

fn fileWrite(context: ?*anyopaque, fileid: forth.Cell, bytes: []const u8) forth.Cell {
    if (fileid == forth.stdout_fileid) {
        terminalWrite(context, bytes);
        return 0;
    }
    if (fileid == forth.stderr_fileid) {
        const host = hostContext(context) catch return forth.errnoIor(errno_io);
        std.Io.File.stderr().writeStreamingAll(host.io, bytes) catch return forth.errnoIor(errno_io);
        return 0;
    }
    const file = openedFile(fileid) orelse return badFileIor();
    clearErrno();
    return if (fwrite(bytes.ptr, 1, bytes.len, file) == bytes.len) 0 else lastIor();
}

fn fileSize(_: ?*anyopaque, fileid: forth.Cell) forth.FileResult {
    const file = openedFile(fileid) orelse return .{ .ior = badFileIor() };
    clearErrno();
    const position = tell64(file);
    if (position < 0 or seek64(file, 0, 2) != 0) return .{ .ior = lastIor() };
    const end = tell64(file);
    if (end < 0 or seek64(file, position, 0) != 0) return .{ .ior = lastIor() };
    return .{ .value = @intCast(end) };
}

fn fileReposition(_: ?*anyopaque, fileid: forth.Cell, position: forth.UCell) forth.Cell {
    const file = openedFile(fileid) orelse return badFileIor();
    clearErrno();
    return if (seek64(file, @intCast(position), 0) == 0) 0 else lastIor();
}

fn closeAllFiles() void {
    for (&open_files) |*slot| {
        if (slot.*) |file| _ = fclose(file);
        slot.* = null;
    }
}

const file_ops = forth.FileOps{ .open = fileOpen, .close = fileClose, .read_line = fileReadLine, .write = fileWrite, .size = fileSize, .reposition = fileReposition };

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

fn loadEmbeddedImage(path: [:0]const u8, machine: *forth.State, allocator: std.mem.Allocator) void {
    const file = fopen(path.ptr, "rb") orelse return;
    defer _ = fclose(file);
    if (fseek(file, 0, 2) != 0) return;
    const end = ftell(file);
    if (end < image_footer_size or fseek(file, end - image_footer_size, 0) != 0) return;
    var footer: [image_footer_size]u8 = undefined;
    if (fread(&footer, 1, footer.len, file) != footer.len or !std.mem.eql(u8, footer[0..8], image_footer_magic)) return;
    const image_len = readU32(footer[8..12]);
    const base_len = readU64(footer[12..20]);
    if (base_len + image_len + image_footer_size != end or image_len > forth.State.imageCapacity()) return;
    if (fseek(file, @intCast(base_len), 0) != 0) return;
    const image = allocator.alloc(u8, image_len) catch return;
    defer allocator.free(image);
    if (fread(image.ptr, 1, image.len, file) != image.len) return;
    machine.restoreImage(image) catch machine.write("INVALID IMAGE !\n");
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
    if (file_len_signed < 0 or file_len_signed > forth.State.imageCapacity() or fseek(file, 0, 0) != 0) return error.InvalidImage;
    const file_len: usize = @intCast(file_len_signed);
    const bytes = host.allocator.alloc(u8, file_len) catch return error.MemoryExhausted;
    defer host.allocator.free(bytes);
    if (fread(bytes.ptr, 1, bytes.len, file) != bytes.len) return error.FileUnavailable;
    const loaded = host.allocator.create(forth.State) catch return error.MemoryExhausted;
    defer host.allocator.destroy(loaded);
    loaded.* = forth.State.init(machine.writer);
    try loaded.restoreImage(bytes);
    try machine.appendImage(loaded);
}

fn saveDictionary(context: ?*anyopaque, output_path: []const u8, machine: *forth.State) forth.RuntimeError!void {
    const host: *HostContext = @ptrCast(@alignCast(context orelse return error.FileUnavailable));
    if (output_path.len >= 4096) return error.FileUnavailable;
    var terminated_path: [4096:0]u8 = undefined;
    @memcpy(terminated_path[0..output_path.len], output_path);
    terminated_path[output_path.len] = 0;
    const file = fopen(&terminated_path, "wb") orelse return error.FileUnavailable;
    defer _ = fclose(file);
    const image = host.allocator.alloc(u8, forth.State.imageCapacity()) catch return error.MemoryExhausted;
    defer host.allocator.free(image);
    const length = try machine.encodeImage(image);
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
    const image = allocator.alloc(u8, forth.State.imageCapacity()) catch return error.MemoryExhausted;
    defer allocator.free(image);
    const image_len = try machine.encodeImage(image);
    if (fwrite(image.ptr, 1, image_len, destination) != image_len) return error.FileUnavailable;
    var footer: [image_footer_size]u8 = undefined;
    @memcpy(footer[0..8], image_footer_magic);
    writeU32(footer[8..12], @intCast(image_len));
    writeU64(footer[12..20], base_len);
    if (fwrite(&footer, 1, footer.len, destination) != footer.len) return error.FileUnavailable;
}

fn terminalWrite(_: ?*anyopaque, bytes: []const u8) void {
    for (bytes) |byte| _ = putchar(byte);
    _ = fflush(null);
}

/// One byte read ahead by KEY? and returned by the next read.
var lookahead: ?u8 = null;

fn readByte() c_int {
    if (lookahead) |byte| {
        lookahead = null;
        return byte;
    }
    return getchar();
}

fn terminalKey(_: ?*anyopaque) ?u8 {
    const ch = readByte();
    return if (ch < 0) null else @intCast(ch);
}

fn terminalKeyReady(_: ?*anyopaque) bool {
    if (lookahead != null) return true;
    const ch = getchar();
    if (ch < 0) return false;
    lookahead = @intCast(ch);
    return true;
}

fn terminalRead(_: ?*anyopaque, buffer: []u8) ?[]const u8 {
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

fn interpretAndPrompt(machine: *forth.State, line: []const u8) void {
    machine.interpretLine(line) catch |err| {
        machine.report(err);
        return;
    };
    if (!machine.defining) machine.write(" OK\n");
}

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const executable_path = try std.process.executablePathAlloc(init.io, allocator);
    defer allocator.free(executable_path);
    var host = HostContext{ .allocator = allocator, .executable_path = executable_path, .io = init.io, .environ_map = init.environ_map };
    const machine = try allocator.create(forth.State);
    defer allocator.destroy(machine);

    enableVirtualTerminal();
    machine.* = forth.State.init(.{ .context = @ptrCast(&host), .write_fn = terminalWrite, .read_fn = terminalRead, .load_fn = loadDictionary, .save_fn = saveDictionary, .savesys_fn = saveExecutableImage, .key_fn = terminalKey, .key_ready_fn = terminalKeyReady, .sleep_fn = sleepMilliseconds, .utime_fn = microsecondsSinceEpoch, .getenv_fn = environmentValue, .system_fn = runShellCommand, .file_ops = &file_ops });
    defer closeAllFiles();
    loadEmbeddedImage(executable_path, machine, allocator);
    machine.write("FORTH/Sigma Zig portable core\n");

    var arguments = try std.process.Args.Iterator.initAllocator(init.minimal.args, allocator);
    defer arguments.deinit();
    _ = arguments.next();
    var argument_line: [4096]u8 = undefined;
    var argument_length: usize = 0;
    var has_arguments = false;
    while (arguments.next()) |argument| {
        if (has_arguments) {
            if (argument_length == argument_line.len) return;
            argument_line[argument_length] = ' ';
            argument_length += 1;
        }
        if (argument.len > argument_line.len - argument_length) {
            machine.write("ARGUMENT TOO LONG\n");
            return;
        }
        @memcpy(argument_line[argument_length .. argument_length + argument.len], argument);
        argument_length += argument.len;
        has_arguments = true;
    }
    if (has_arguments) {
        machine.interpretLine(argument_line[0..argument_length]) catch |err| machine.report(err);
        return;
    }

    var line: [4096]u8 = undefined;
    var used: usize = 0;
    var discarding_line = false;
    while (!machine.halted) {
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
}

// Host tests: these exercise the real callbacks, which the core tests replace with fakes.

fn discardOutput(_: ?*anyopaque, _: []const u8) void {}

test "GETENV through the host accepts 3072 bytes and rejects 3073" {
    var map = std.process.Environ.Map.init(std.testing.allocator);
    defer map.deinit();
    try map.put("SIGMA_FIT", &([_]u8{'x'} ** 3072));
    try map.put("SIGMA_LONG", &([_]u8{'y'} ** 3073));
    try map.put("SIGMA_EMPTY", "");
    var host = HostContext{ .allocator = std.testing.allocator, .executable_path = "", .io = undefined, .environ_map = &map };
    const machine = try std.testing.allocator.create(forth.State);
    defer std.testing.allocator.destroy(machine);
    machine.* = forth.State.init(.{ .context = @ptrCast(&host), .write_fn = discardOutput, .getenv_fn = environmentValue });

    try machine.interpretLine("S\" SIGMA_FIT\" GETENV NIP S\" SIGMA_EMPTY\" GETENV NIP S\" SIGMA_UNSET\" GETENV S\" A=B\" GETENV");
    try std.testing.expectEqualSlices(forth.Cell, &.{ 3072, 0, 0, 0, 0, 0 }, machine.data_stack[0..machine.data_depth]);
    try std.testing.expectError(error.StringTooLong, machine.interpretLine("S\" SIGMA_LONG\" GETENV"));
}

test "SYSTEM through the host checks length and embedded NUL before running" {
    var command: [4096]u8 = @splat(' ');
    @memcpy(command[0..6], "exit 0");
    try runShellCommand(null, command[0..4095]);
    try std.testing.expectError(error.StringTooLong, runShellCommand(null, command[0..4096]));
    try std.testing.expectError(error.HostFailed, runShellCommand(null, "exit 0\x00 & exit 1"));
    // A command that runs but exits with a non-zero status is not an error.
    try runShellCommand(null, "exit 3");
}
fn writeTestFile(path: [*:0]const u8, bytes: []const u8) !void {
    const file = fopen(path, "wb") orelse return error.TestUnexpectedResult;
    defer _ = fclose(file);
    if (fwrite(bytes.ptr, 1, bytes.len, file) != bytes.len) return error.TestUnexpectedResult;
}

test "INCLUDE through the host reads CR LF lines and limits a line to 4096 bytes" {
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

    var host = HostContext{ .allocator = allocator, .executable_path = "", .io = undefined, .environ_map = undefined };
    const machine = try allocator.create(forth.State);
    defer allocator.destroy(machine);
    machine.* = forth.State.init(.{ .context = @ptrCast(&host), .write_fn = discardOutput, .file_ops = &file_ops });
    defer closeAllFiles();

    try machine.interpretLine("INCLUDE .zig-cache/sigma-include-fit.fs SOURCELINE#");
    try std.testing.expectEqualSlices(forth.Cell, &.{ 1, 2, 3, 4, 0 }, machine.data_stack[0..machine.data_depth]);
    try std.testing.expectError(error.StringTooLong, machine.interpretLine("INCLUDE .zig-cache/sigma-include-long.fs"));
    for (open_files) |slot| try std.testing.expect(slot == null);
}