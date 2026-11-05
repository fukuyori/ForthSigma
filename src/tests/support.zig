//! Helpers shared by the core tests: a fake host with output capture and files.

const std = @import("std");

/// Skips a test that uses floating-point words in a build without them (-Dfloat=false).
pub fn skipWithoutFloat() error{SkipZigTest}!void {
    if (!@import("build_options").float) return error.SkipZigTest;
}

/// Skips a test that uses a word group the build leaves out (-Dfiles=false, -Dhelp=false,
/// -Dtools=false, or -Dimage=false); several groups may be named.
pub fn skipWithout(comptime groups: []const enum { files, help, tools, image, graphics }) error{SkipZigTest}!void {
    const options = @import("build_options");
    inline for (groups) |group| {
        if (!@field(options, @tagName(group))) return error.SkipZigTest;
    }
}

/// `text` in a build with SEE, LOCATE, and WHERE, and nothing in one without them
/// (-Dtools=false): a test puts its SEE and what SEE prints in it, so that the rest of
/// the test still runs without the tools.
pub inline fn see(comptime text: []const u8) []const u8 {
    return if (@import("build_options").tools) text else "";
}
const forth = @import("../forth.zig");

/// `text` written `count` times, which Zig 0.17 no longer has an operator for.
pub fn repeat(comptime text: []const u8, comptime count: usize) *const [text.len * count]u8 {
    return comptime blk: {
        @setEvalBranchQuota(count * 10 + 1000);
        var result: [text.len * count]u8 = undefined;
        for (0..count) |index| @memcpy(result[index * text.len ..][0..text.len], text);
        const final = result;
        break :blk &final;
    };
}

pub const Output = struct {
    bytes: [32768]u8 = undefined,
    len: usize = 0,
    input_lines: [4][]const u8 = undefined,
    input_count: usize = 0,
    input_index: usize = 0,
    keys: []const u8 = "",
    key_index: usize = 0,
    slept: forth.Cell = -1,
    host_fails: bool = false,
    close_fails: bool = false,
    command: [64]u8 = undefined,
    command_len: usize = 0,
    files: [5]FakeFile = .{ .{}, .{}, .{}, .{}, .{} },
    stdout_bytes: [64]u8 = undefined,
    stdout_len: usize = 0,
    /// Two graphics images in turn, so that a new one is given while the old one stays;
    /// an image of more than `framebuffer_capacity` pixels fails, as does any image when
    /// `framebuffer_fails` is set.
    framebuffers: [2][framebuffer_capacity]u32 = undefined,
    framebuffer_index: usize = 0,
    framebuffer_fails: bool = false,
    /// Gives one pixel less than asked, as a host that breaks its contract would.
    framebuffer_short: bool = false,
    /// When not 0, the write to a file (not STDOUT) with this number, counted from 1,
    /// fails with the ior of errno 28 (no space).
    write_fails_at: usize = 0,
    file_writes: usize = 0,
    /// The terminal size the host reports; 0 columns reports none (not a terminal).
    terminal_columns: u32 = 0,
    terminal_rows: u32 = 0,
    /// The calls of the UTF-8 hook, as "+" (begin) and "-" (end).
    utf8_calls: [8]u8 = undefined,
    utf8_count: usize = 0,
    /// Whether the host has a window; set before createMachine. The last image shown in
    /// it: its size and the first pixel, and how many times SHOW used it.
    has_window: bool = false,
    window_shows: usize = 0,
    window_width: u32 = 0,
    window_height: u32 = 0,
    window_first_pixel: u32 = 0,

    pub const framebuffer_capacity = 1600;

    pub fn terminalSize(context: ?*anyopaque) ?forth.TerminalSize {
        const output: *Output = @ptrCast(@alignCast(context.?));
        if (output.terminal_columns == 0) return null;
        return .{ .columns = output.terminal_columns, .rows = output.terminal_rows };
    }

    pub fn terminalUtf8(context: ?*anyopaque, begin: bool) void {
        const output: *Output = @ptrCast(@alignCast(context.?));
        if (output.utf8_count == output.utf8_calls.len) return;
        output.utf8_calls[output.utf8_count] = if (begin) '+' else '-';
        output.utf8_count += 1;
    }

    pub fn window(context: ?*anyopaque, pixels: []const u32, width: u32, height: u32) forth.RuntimeError!void {
        const output: *Output = @ptrCast(@alignCast(context.?));
        output.window_shows += 1;
        output.window_width = width;
        output.window_height = height;
        output.window_first_pixel = pixels[0];
    }

    pub fn framebuffer(context: ?*anyopaque, pixels: usize) ?[]u32 {
        const output: *Output = @ptrCast(@alignCast(context.?));
        if (output.framebuffer_fails or pixels > framebuffer_capacity) return null;
        output.framebuffer_index = 1 - output.framebuffer_index;
        // Old contents, so that a test sees GFX-INIT clear the image.
        const buffer = output.framebuffers[output.framebuffer_index][0..pixels];
        @memset(buffer, 0x12345678);
        return if (output.framebuffer_short) buffer[0 .. pixels - 1] else buffer;
    }

    pub fn write(context: ?*anyopaque, bytes: []const u8) void {
        const output: *Output = @ptrCast(@alignCast(context.?));
        const count = @min(bytes.len, output.bytes.len - output.len);
        @memcpy(output.bytes[output.len .. output.len + count], bytes[0..count]);
        output.len += count;
    }

    pub fn writer(self: *Output) forth.Writer {
        return .{ .context = @ptrCast(self), .write_fn = write, .read_fn = read, .key_fn = key, .key_ready_fn = keyReady, .sleep_fn = sleep, .utime_fn = utime, .local_time_fn = localTime, .getenv_fn = getenv, .system_fn = system, .file_ops = &fake_file_ops, .framebuffer_fn = framebuffer, .terminal_size_fn = terminalSize, .terminal_utf8_fn = terminalUtf8, .window_fn = if (self.has_window) window else null };
    }

    pub fn sleep(context: ?*anyopaque, milliseconds: forth.Cell) forth.RuntimeError!void {
        const output: *Output = @ptrCast(@alignCast(context.?));
        if (output.host_fails) return error.HostFailed;
        output.slept = milliseconds;
    }

    pub fn localTime(context: ?*anyopaque) forth.RuntimeError!forth.LocalTime {
        const output: *Output = @ptrCast(@alignCast(context.?));
        if (output.host_fails) return error.HostFailed;
        return .{ .second = 14, .minute = 39, .hour = 18, .day = 30, .month = 10, .year = 2026 };
    }

    pub fn utime(context: ?*anyopaque) forth.RuntimeError!forth.Double {
        const output: *Output = @ptrCast(@alignCast(context.?));
        if (output.host_fails) return error.HostFailed;
        return 1_700_000_000_000_000;
    }

    pub fn getenv(_: ?*anyopaque, name: []const u8, buffer: []u8) forth.RuntimeError!?usize {
        const value: []const u8 = if (std.mem.eql(u8, name, "HOME")) "/home/lemon" else if (std.mem.eql(u8, name, "EMPTY")) "" else if (std.mem.eql(u8, name, "LONG")) &@as([4000]u8, @splat('x')) else return null;
        if (value.len > buffer.len) return error.StringTooLong;
        @memcpy(buffer[0..value.len], value);
        return value.len;
    }

    pub fn system(context: ?*anyopaque, command: []const u8) forth.RuntimeError!forth.Cell {
        const output: *Output = @ptrCast(@alignCast(context.?));
        if (std.mem.eql(u8, command, "fail")) return error.HostFailed;
        @memcpy(output.command[0..command.len], command);
        output.command_len = command.len;
        return if (std.mem.eql(u8, command, "exit 3")) 768 else 0;
    }

    pub fn key(context: ?*anyopaque) ?u8 {
        const output: *Output = @ptrCast(@alignCast(context.?));
        if (output.key_index == output.keys.len) return null;
        output.key_index += 1;
        return output.keys[output.key_index - 1];
    }

    pub fn keyReady(context: ?*anyopaque) bool {
        const output: *Output = @ptrCast(@alignCast(context.?));
        return output.key_index < output.keys.len;
    }

    pub fn read(context: ?*anyopaque, buffer: []u8) ?[]const u8 {
        const output: *Output = @ptrCast(@alignCast(context.?));
        if (output.input_index == output.input_count) return null;
        const line = output.input_lines[output.input_index];
        output.input_index += 1;
        if (line.len > buffer.len) return null;
        @memcpy(buffer[0..line.len], line);
        return buffer[0..line.len];
    }

    pub fn written(self: *const Output) []const u8 {
        return self.bytes[0..self.len];
    }
};

/// An in-memory file for the fake host; "a.txt" and "b.txt" are the only names.
pub const FakeFile = struct {
    data: [8192]u8 = undefined,
    len: usize = 0,
    position: usize = 0,
    open: bool = false,
    exists: bool = false,
};

/// The last name is long, for WHERE lines whose place takes more than 80 columns.
pub const fake_file_names = [_][]const u8{ "a.txt", "b.txt", "c.txt", "d.txt", repeat("f", 75) ++ ".txt" };

pub fn setFakeFile(output: *Output, index: usize, text: []const u8) void {
    @memcpy(output.files[index].data[0..text.len], text);
    output.files[index].len = text.len;
    output.files[index].exists = true;
}

pub const fake_file_ops = forth.FileOps{ .open = fakeOpen, .close = fakeClose, .read_line = fakeReadLine, .read = fakeRead, .write = fakeWrite, .size = fakeSize, .reposition = fakeReposition, .position = fakePosition, .resize = fakeResize, .flush = fakeFlush, .delete = fakeDelete, .rename = fakeRename, .status = fakeStatus };

pub fn fakeOutput(context: ?*anyopaque) *Output {
    return @ptrCast(@alignCast(context.?));
}

pub fn fakeFile(context: ?*anyopaque, fileid: forth.Cell) ?*FakeFile {
    const output = fakeOutput(context);
    if (fileid < forth.first_file_id or fileid - forth.first_file_id >= output.files.len) return null;
    const file = &output.files[@intCast(fileid - forth.first_file_id)];
    return if (file.open) file else null;
}

pub fn fakeOpen(context: ?*anyopaque, name: []const u8, _: forth.FileAccess, create: bool) forth.FileResult {
    const index: usize = for (fake_file_names, 0..) |known, position| {
        if (std.mem.eql(u8, name, known)) break position;
    } else return .{ .ior = forth.errnoIor(2) };
    const file = &fakeOutput(context).files[index];
    if (!create and !file.exists) return .{ .ior = forth.errnoIor(2) };
    if (create) file.len = 0;
    file.exists = true;
    file.open = true;
    file.position = 0;
    return .{ .value = @intCast(forth.first_file_id + @as(forth.Cell, @intCast(index))) };
}

pub fn fakeClose(context: ?*anyopaque, fileid: forth.Cell) forth.Cell {
    const file = fakeFile(context, fileid) orelse return forth.errnoIor(forth.errno_bad_file);
    file.open = false;
    return if (fakeOutput(context).close_fails) forth.errnoIor(5) else 0;
}

pub fn fakeReadLine(context: ?*anyopaque, fileid: forth.Cell, buffer: []u8) forth.LineResult {
    const file = fakeFile(context, fileid) orelse return .{ .ior = forth.errnoIor(forth.errno_bad_file) };
    if (file.position >= file.len) return .{};
    var length: usize = 0;
    while (length < buffer.len and file.position < file.len) {
        const byte = file.data[file.position];
        file.position += 1;
        if (byte == '\n') break;
        if (byte == '\r') continue;
        buffer[length] = byte;
        length += 1;
    }
    return .{ .length = length, .found = true };
}

pub fn fakeRead(context: ?*anyopaque, fileid: forth.Cell, buffer: []u8) forth.FileResult {
    const file = fakeFile(context, fileid) orelse return .{ .ior = forth.errnoIor(forth.errno_bad_file) };
    const count = @min(buffer.len, file.len -| file.position);
    @memcpy(buffer[0..count], file.data[file.position .. file.position + count]);
    file.position += count;
    return .{ .value = count };
}

pub fn fakeWrite(context: ?*anyopaque, fileid: forth.Cell, bytes: []const u8) forth.Cell {
    if (fileid == forth.stdout_fileid) {
        const output = fakeOutput(context);
        @memcpy(output.stdout_bytes[output.stdout_len .. output.stdout_len + bytes.len], bytes);
        output.stdout_len += bytes.len;
        return 0;
    }
    const file = fakeFile(context, fileid) orelse return forth.errnoIor(forth.errno_bad_file);
    const output = fakeOutput(context);
    output.file_writes += 1;
    if (output.file_writes == output.write_fails_at) return forth.errnoIor(28);
    @memcpy(file.data[file.position .. file.position + bytes.len], bytes);
    file.position += bytes.len;
    file.len = @max(file.len, file.position);
    return 0;
}

pub fn fakeSize(context: ?*anyopaque, fileid: forth.Cell) forth.FileResult {
    const file = fakeFile(context, fileid) orelse return .{ .ior = forth.errnoIor(forth.errno_bad_file) };
    return .{ .value = file.len };
}

pub fn fakePosition(context: ?*anyopaque, fileid: forth.Cell) forth.FileResult {
    const file = fakeFile(context, fileid) orelse return .{ .ior = forth.errnoIor(forth.errno_bad_file) };
    return .{ .value = file.position };
}

pub fn fakeResize(context: ?*anyopaque, fileid: forth.Cell, size: forth.UCell) forth.Cell {
    const file = fakeFile(context, fileid) orelse return forth.errnoIor(forth.errno_bad_file);
    if (size > file.data.len) return forth.errnoIor(28);
    const length: usize = @intCast(size);
    if (length > file.len) @memset(file.data[file.len..length], 0);
    file.len = length;
    return 0;
}

pub fn fakeFlush(context: ?*anyopaque, fileid: forth.Cell) forth.Cell {
    _ = fakeFile(context, fileid) orelse return forth.errnoIor(forth.errno_bad_file);
    return 0;
}

fn fakeIndex(name: []const u8) ?usize {
    for (fake_file_names, 0..) |known, index| {
        if (std.mem.eql(u8, name, known)) return index;
    }
    return null;
}

pub fn fakeDelete(context: ?*anyopaque, name: []const u8) forth.Cell {
    const index = fakeIndex(name) orelse return forth.errnoIor(2);
    const file = &fakeOutput(context).files[index];
    if (!file.exists) return forth.errnoIor(2);
    file.exists = false;
    file.len = 0;
    return 0;
}

pub fn fakeRename(context: ?*anyopaque, old: []const u8, new: []const u8) forth.Cell {
    const from = fakeIndex(old) orelse return forth.errnoIor(2);
    const to = fakeIndex(new) orelse return forth.errnoIor(13);
    const files = &fakeOutput(context).files;
    if (!files[from].exists) return forth.errnoIor(2);
    files[to] = files[from];
    files[from] = .{};
    return 0;
}

pub fn fakeStatus(context: ?*anyopaque, name: []const u8) forth.FileResult {
    const index = fakeIndex(name) orelse return .{ .ior = forth.errnoIor(2) };
    if (!fakeOutput(context).files[index].exists) return .{ .ior = forth.errnoIor(2) };
    return .{ .value = @bitCast(forth.fam_read_write) };
}

pub fn fakeReposition(context: ?*anyopaque, fileid: forth.Cell, position: forth.UCell) forth.Cell {
    const file = fakeFile(context, fileid) orelse return forth.errnoIor(forth.errno_bad_file);
    file.position = @intCast(position);
    return 0;
}

pub fn createMachine(output: *Output) !*forth.State {
    const machine = try std.testing.allocator.create(forth.State);
    machine.init(output.writer());
    return machine;
}

/// Feeds a definition of `count` literals over several lines, since one input line holds
/// at most `forth.tib_size` bytes.
pub fn interpretLiteralDefinition(machine: *forth.State, prefix: []const u8, count: usize) !void {
    try machine.interpretLine(prefix);
    var line: [2000]u8 = undefined;
    var remaining = count;
    while (remaining > 0) {
        const batch: usize = @min(remaining, line.len / 2);
        for (0..batch) |index| @memcpy(line[index * 2 ..][0..2], "1 ");
        try machine.interpretLine(line[0 .. batch * 2]);
        remaining -= batch;
    }
    try machine.interpretLine(";");
}

pub fn destroyMachine(machine: *forth.State) void {
    std.testing.allocator.destroy(machine);
}

pub fn expectStack(machine: *const forth.State, expected: []const forth.Cell) !void {
    try std.testing.expectEqual(expected.len, machine.data_depth);
    try std.testing.expectEqualSlices(forth.Cell, expected, machine.data_stack[0..machine.data_depth]);
}

pub fn expectFloatStack(machine: *const forth.State, expected: []const forth.Float) !void {
    try std.testing.expectEqual(expected.len, machine.float_depth);
    try std.testing.expectEqualSlices(forth.Float, expected, machine.float_stack[0..machine.float_depth]);
}

pub fn expectOutput(line: []const u8, expected: []const u8) !void {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    try machine.interpretLine(line);
    try std.testing.expectEqualStrings(expected, output.written());
}
