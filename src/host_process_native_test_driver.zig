//! Controlled small-input fixture driver for native preparation/launch tests.
const std = @import("std");
const builtin = @import("builtin");
const Native = @import("host_process_native.zig").Native;
const Config = @import("host_process_table.zig").Config;
const c = struct {
    extern "c" fn getchar() c_int;
    extern "c" fn fread([*]u8, usize, usize, *anyopaque) usize;
    extern "c" fn fwrite([*]const u8, usize, usize, *anyopaque) usize;
    extern "c" fn fclose(*anyopaque) c_int;
    extern "c" fn ferror(*anyopaque) c_int;
    extern "c" fn _setmode(c_int, c_int) c_int;
    extern "c" fn _write(c_int, [*]const u8, c_uint) c_int;
    extern "kernel32" fn Sleep(u32) callconv(.winapi) void;
};
fn output(fd: c_int, bytes: []const u8) bool {
    var rest = bytes;
    while (rest.len != 0) {
        const n = if (builtin.os.tag == .windows) c._write(fd, rest.ptr, @intCast(rest.len)) else std.c.write(fd, rest.ptr, rest.len);
        if (n <= 0) return false;
        rest = rest[@intCast(n)..];
    }
    return true;
}
fn forward(file: *anyopaque, fd: c_int) void {
    var bytes: [4096]u8 = undefined;
    while (true) {
        const n = c.fread(&bytes, 1, bytes.len, file);
        if (n == 0) break;
        if (!output(fd, bytes[0..n])) break;
    }
}
fn pause() void {
    if (builtin.os.tag == .windows) c.Sleep(5) else {
        var duration: std.c.timespec = .{ .sec = 0, .nsec = 5000000 };
        _ = std.c.nanosleep(&duration, null);
    }
}
pub fn main(init: std.process.Init.Minimal) u8 {
    return run(init) catch |err| {
        var buffer: [256]u8 = undefined;
        _ = output(2, std.fmt.bufPrint(&buffer, "DRIVER-ERROR {s}\n", .{@errorName(err)}) catch "DRIVER-ERROR\n");
        return 1;
    };
}
fn run(init: std.process.Init.Minimal) !u8 {
    const allocator = std.heap.page_allocator;
    if (builtin.os.tag == .windows) for (0..3) |fd| {
        _ = c._setmode(@intCast(fd), 0x8000);
    };
    var arguments = try std.process.Args.Iterator.initAllocator(init.args, allocator);
    defer arguments.deinit();
    _ = arguments.next();
    var config: Config = .{};
    defer config.deinit(allocator);
    var program = false;
    while (arguments.next()) |argument| {
        if (program) try config.addArgument(allocator, argument) else if (std.mem.eql(u8, argument, "--")) {
            program = true;
        } else if (std.mem.startsWith(u8, argument, "--cwd=")) {
            try config.setCwd(allocator, argument[6..]);
        } else if (std.mem.startsWith(u8, argument, "--env=")) {
            try config.addEnvironment(allocator, argument[6..]);
        } else return error.BadOption;
    }
    var environment = try std.process.Environ.createMap(init.environ, allocator);
    defer environment.deinit();
    // These fixtures use <=4096 input bytes, fully supplied before launch.
    var input: [4096]u8 = undefined;
    var used: usize = 0;
    while (true) {
        const byte = c.getchar();
        if (byte < 0) break;
        if (used == input.len) return error.InputTooLarge;
        input[used] = @intCast(byte);
        used += 1;
    }
    var native: Native = .{};
    defer {
        if (native.abort(3000) != 0) _ = output(2, "DRIVER-CLEANUP-ERROR\n");
    }
    const started = native.start(allocator, &config, &environment);
    var message: [128]u8 = undefined;
    if (started != 0) {
        _ = output(2, try std.fmt.bufPrint(&message, "NATIVE-START {d}\n", .{started}));
        return 2;
    }
    const input_file = native.take(0) orelse return error.MissingInput;
    if (used != 0 and c.fwrite(&input, 1, used, input_file) != used) {
        _ = c.fclose(input_file);
        return error.WriteFailed;
    }
    if (c.fclose(input_file) != 0) return error.WriteFailed;
    const errors = native.stream(2) orelse return error.MissingErrors;
    const error_thread = try std.Thread.spawn(.{}, forward, .{ errors, @as(c_int, 2) });
    forward(native.stream(1) orelse unreachable, 1);
    error_thread.join();
    var status = native.status();
    for (0..1000) |_| {
        if (status.err != 0 or status.state != 1) break;
        pause();
        status = native.status();
    }
    if (status.err != 0 or status.state == 1) return error.WaitFailed;
    _ = output(2, try std.fmt.bufPrint(&message, "NATIVE-STATUS {d} {d}\n", .{ status.state, status.code }));
    const released = native.destroy();
    if (released != 0) return error.ReleaseFailed;
    return 0;
}
