//! Parent-side native launcher. Failed starts retain their opaque cleanup token.
const std = @import("std");
const builtin = @import("builtin");
const table = @import("host_process_table.zig");
const spec = @import("host_process_spec.zig");
const Allocator = std.mem.Allocator;
const Env = std.process.Environ.Map;
const windows = builtin.os.tag == .windows;
pub const available = windows or builtin.os.tag == .linux or builtin.os.tag == .macos;
const Opaque = opaque {};
const c = struct {
    extern "c" fn sigma_proc_new() ?*Opaque;
    extern "c" fn sigma_proc_start_windows(*Opaque, [*:0]const u16, [*:0]u16, [*:0]const u16, [*:0]const u16, *const [3]c_int) c_int;
    extern "c" fn sigma_proc_start_posix(*Opaque, [*:0]const u8, [*:null]const ?[*:0]const u8, [*:null]const ?[*:0]const u8, [*:0]const u8, *const [3]c_int) c_int;
    extern "c" fn sigma_proc_check_cwd_windows([*:0]const u16) c_int;
    extern "c" fn sigma_proc_check_cwd_posix([*:0]const u8) c_int;
    extern "c" fn sigma_proc_probe_windows([*:0]const u16, *c_int) c_int;
    extern "c" fn sigma_proc_probe_posix([*:0]const u8, *c_int) c_int;
    extern "c" fn sigma_proc_status(*Opaque, *u32, *u32) c_int;
    extern "c" fn sigma_proc_signal(*Opaque, c_int) c_int;
    extern "c" fn sigma_proc_wait_slice(*Opaque, c_uint) c_int;
    extern "c" fn sigma_proc_destroy(*Opaque) c_int;
    extern "c" fn sigma_proc_abort(*Opaque, c_uint) c_int;
    extern "c" fn sigma_proc_stream(*Opaque, c_uint) ?*anyopaque;
    extern "c" fn sigma_proc_take_stream(*Opaque, c_uint) ?*anyopaque;
    extern "c" fn getcwd(?[*]u8, usize) ?[*:0]u8;
    extern "c" fn _wgetcwd(?[*]u16, c_int) ?[*:0]u16;
    extern "c" fn free(?*anyopaque) void;
};
pub const Status = struct { state: u32 = 0, code: u32 = 0, err: c_int = 0 };
const Error = spec.Error || error{ TooLarge, InvalidUtf8, InvalidWtf8 };
fn errorNumber(err: anyerror, native_error: c_int) c_int {
    return switch (err) {
        error.OutOfMemory => 12,
        error.TooLarge => 7,
        error.NotFound => 2,
        error.AccessDenied => 13,
        error.BadExecutable => 8,
        error.Io => if (native_error == 0) 5 else native_error,
        else => 22,
    };
}
fn currentDirectory(allocator: Allocator, native_error: *c_int) Error![:0]u8 {
    if (windows) {
        const text = c._wgetcwd(null, 0) orelse {
            native_error.* = std.c._errno().*;
            return error.Io;
        };
        defer c.free(@ptrCast(text));
        const utf8 = try std.unicode.wtf16LeToWtf8Alloc(allocator, std.mem.span(text));
        defer allocator.free(utf8);
        return allocator.dupeSentinel(u8, utf8, 0);
    }
    const text = c.getcwd(null, 0) orelse {
        native_error.* = std.c._errno().*;
        return error.Io;
    };
    defer c.free(@ptrCast(text));
    return allocator.dupeSentinel(u8, std.mem.span(text), 0);
}
const ProbeContext = struct {
    allocator: Allocator,
    native_error: c_int = 0,
    fn check(context: ?*anyopaque, path: []const u8) spec.Error!spec.ProbeResult {
        const self: *@This() = @ptrCast(@alignCast(context.?));
        var kind: c_int = 0;
        if (windows) {
            const wide = std.unicode.wtf8ToWtf16LeAllocZ(self.allocator, path) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidText;
            defer self.allocator.free(wide);
            self.native_error = c.sigma_proc_probe_windows(wide.ptr, &kind);
        } else {
            const terminated = try self.allocator.dupeSentinel(u8, path, 0);
            defer self.allocator.free(terminated);
            self.native_error = c.sigma_proc_probe_posix(terminated.ptr, &kind);
        }
        if (self.native_error != 0) return error.Io;
        return switch (kind) {
            0 => .missing,
            1 => .denied,
            2 => .executable,
            3 => .invalid_format,
            else => error.Io,
        };
    }
};
fn checkCwd(allocator: Allocator, cwd: [:0]const u8) Error!c_int {
    if (!windows) return c.sigma_proc_check_cwd_posix(cwd.ptr);
    const wide = try std.unicode.wtf8ToWtf16LeAllocZ(allocator, cwd);
    defer allocator.free(wide);
    return c.sigma_proc_check_cwd_windows(wide.ptr);
}
fn windowsBlock(allocator: Allocator, environment: *const Env) Error!std.process.Environ.WindowsBlock {
    const Name = struct { key: []const u8, wide: []u16 };
    const names = try allocator.alloc(Name, environment.count());
    var initialized: usize = 0;
    defer {
        for (names[0..initialized]) |name| allocator.free(name.wide);
        allocator.free(names);
    }
    var iterator = environment.iterator();
    while (iterator.next()) |item| {
        names[initialized] = .{ .key = item.key_ptr.*, .wide = try std.unicode.wtf8ToWtf16LeAlloc(allocator, item.key_ptr.*) };
        initialized += 1;
    }
    const Compare = struct {
        fn less(_: void, left: Name, right: Name) bool {
            for (left.wide[0..@min(left.wide.len, right.wide.len)], right.wide[0..@min(left.wide.len, right.wide.len)]) |a, b| {
                const upper_a = std.os.windows.toUpperWtf16(a);
                const upper_b = std.os.windows.toUpperWtf16(b);
                if (upper_a != upper_b) return upper_a < upper_b;
            }
            return left.wide.len < right.wide.len;
        }
    };
    std.mem.sort(Name, names, {}, Compare.less);
    var ordered = Env.init(allocator);
    defer ordered.deinit();
    for (names) |name| try ordered.put(name.key, environment.get(name.key).?);
    return ordered.createWindowsBlock(allocator, .{});
}

pub const Native = struct {
    pointer: ?*Opaque = null,
    pub fn start(self: *Native, allocator: Allocator, config: *const table.Config, inherited: *const Env) c_int {
        if (!available) return 38;
        if (self.pointer != null) return 16;
        if (config.arguments.items.len == 0) return 22;
        var native_error: c_int = 0;
        const parent = currentDirectory(allocator, &native_error) catch |err| return errorNumber(err, native_error);
        defer allocator.free(parent);
        const cwd = cwd: {
            const requested = config.cwd orelse break :cwd allocator.dupeSentinel(u8, parent, 0) catch return 12;
            if (windows) {
                const path = std.fs.path.resolve(allocator, &.{ parent, requested }) catch return 12;
                defer allocator.free(path);
                break :cwd allocator.dupeSentinel(u8, path, 0) catch return 12;
            }
            break :cwd (if (std.fs.path.isAbsolute(requested)) allocator.dupeSentinel(u8, requested, 0) else std.fs.path.joinZ(allocator, &.{ parent, requested })) catch return 12;
        };
        defer allocator.free(cwd);
        const cwd_error = checkCwd(allocator, cwd) catch |err| return errorNumber(err, 0);
        if (cwd_error != 0) return cwd_error;
        var environment = spec.environment(allocator, inherited, config) catch return 12;
        defer environment.deinit();
        if (windows and cwd.len >= 3 and cwd[1] == ':') {
            const drive = [_]u8{ '=', std.ascii.toUpper(cwd[0]), ':' };
            environment.put(&drive, cwd) catch return 12;
        }
        var probe: ProbeContext = .{ .allocator = allocator };
        const executable = spec.resolveProgram(allocator, config.arguments.items[0], cwd, &environment, .{ .context = &probe, .check = ProbeContext.check }) catch |err| return errorNumber(err, probe.native_error);
        defer allocator.free(executable);
        var modes: [3]c_int = undefined;
        for (config.modes, 0..) |mode, index| modes[index] = @backingInt(mode);
        if (windows) {
            var views: [table.max_arguments][]const u8 = undefined;
            for (config.arguments.items, 0..) |arg, index| views[index] = arg;
            const command = spec.quoteWindows(allocator, views[0..config.arguments.items.len]) catch |err| return errorNumber(err, 0);
            defer allocator.free(command);
            const wide_exe = std.unicode.wtf8ToWtf16LeAllocZ(allocator, executable) catch |err| return errorNumber(err, 0);
            defer allocator.free(wide_exe);
            const wide_cwd = std.unicode.wtf8ToWtf16LeAllocZ(allocator, cwd) catch |err| return errorNumber(err, 0);
            defer allocator.free(wide_cwd);
            const block = windowsBlock(allocator, &environment) catch |err| return errorNumber(err, 0);
            defer block.deinit(allocator);
            self.pointer = c.sigma_proc_new() orelse return 12;
            return c.sigma_proc_start_windows(self.pointer.?, wide_exe.ptr, command.ptr, block.slice.ptr, wide_cwd.ptr, &modes);
        }
        const block = environment.createPosixBlock(allocator, .{}) catch return 12;
        defer block.deinit(allocator);
        var arguments: [table.max_arguments + 1]?[*:0]const u8 = @splat(null);
        for (config.arguments.items, 0..) |arg, index| arguments[index] = arg.ptr;
        self.pointer = c.sigma_proc_new() orelse return 12;
        return c.sigma_proc_start_posix(self.pointer.?, executable.ptr, @ptrCast(&arguments), block.slice.ptr, cwd.ptr, &modes);
    }
    pub fn status(self: *Native) Status {
        const pointer = self.pointer orelse return .{};
        var result: Status = .{};
        result.err = c.sigma_proc_status(pointer, &result.state, &result.code);
        return result;
    }
    pub fn signal(self: *Native, force: bool) c_int {
        return c.sigma_proc_signal(self.pointer orelse return 22, @intFromBool(force));
    }
    pub fn waitSlice(self: *Native, milliseconds: u32) c_int {
        return c.sigma_proc_wait_slice(self.pointer orelse return 0, milliseconds);
    }
    pub fn stream(self: *Native, which: u2) ?*anyopaque {
        return c.sigma_proc_stream(self.pointer orelse return null, which);
    }
    pub fn take(self: *Native, which: u2) ?*anyopaque {
        return c.sigma_proc_take_stream(self.pointer orelse return null, which);
    }
    pub fn destroy(self: *Native) c_int {
        const pointer = self.pointer orelse return 0;
        const err = c.sigma_proc_destroy(pointer);
        if (err == 0) self.pointer = null;
        return err;
    }
    pub fn abort(self: *Native, milliseconds: u32) c_int {
        const pointer = self.pointer orelse return 0;
        const err = c.sigma_proc_abort(pointer, milliseconds);
        if (err == 0) self.pointer = null;
        return err;
    }
};

test "native preparation failure frees every Zig allocation before starting a child" {
    if (!available) return error.SkipZigTest;
    const Scenario = struct {
        fn run(allocator: Allocator) !void {
            var config: table.Config = .{};
            defer config.deinit(allocator);
            try config.addArgument(allocator, "./sigma-643-intentionally-not-present.exe");
            var environment = Env.init(allocator);
            defer environment.deinit();
            var native: Native = .{};
            defer std.debug.assert(native.abort(1000) == 0);
            const err = native.start(allocator, &config, &environment);
            if (err == 12) return error.OutOfMemory;
            try std.testing.expectEqual(@as(c_int, 2), err);
            try std.testing.expect(native.pointer == null);
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Scenario.run, .{});
}

test "Windows environment block orders names and preserves empty values" {
    if (!windows) return error.SkipZigTest;
    var environment = Env.init(std.testing.allocator);
    defer environment.deinit();
    try environment.put("z", "last");
    try environment.put("A0", "middle");
    try environment.put("a", "");
    const block = try windowsBlock(std.testing.allocator, &environment);
    defer block.deinit(std.testing.allocator);
    const expected = std.unicode.utf8ToUtf16LeStringLiteral("a=\x00A0=middle\x00z=last\x00");
    try std.testing.expectEqualSlices(u16, expected, block.slice);
}
