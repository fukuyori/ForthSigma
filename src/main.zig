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
    @memcpy(terminated[0..command.len], command);
    terminated[command.len] = 0;
    if (system(&terminated) == -1) return error.HostFailed;
}

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
    machine.* = forth.State.init(.{ .context = @ptrCast(&host), .write_fn = terminalWrite, .read_fn = terminalRead, .load_fn = loadDictionary, .save_fn = saveDictionary, .savesys_fn = saveExecutableImage, .key_fn = terminalKey, .key_ready_fn = terminalKeyReady, .sleep_fn = sleepMilliseconds, .utime_fn = microsecondsSinceEpoch, .getenv_fn = environmentValue, .system_fn = runShellCommand });
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
