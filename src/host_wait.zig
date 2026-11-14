//! NS uses a monotonic deadline without reading input. Temporarily enable terminal
//! interrupt generation, keeping ordinary keys in their existing OS/host queues.
const std = @import("std");
const builtin = @import("builtin");
const forth = @import("forth.zig");
const input = @import("host_input.zig");
const max_duration = @import("core/nanosecond_wait.zig").max_duration;
const is_windows = builtin.os.tag == .windows;
var active = std.atomic.Value(bool).init(false);
var interrupted = std.atomic.Value(bool).init(false);

const win = struct {
    extern "kernel32" fn GetStdHandle(u32) callconv(.winapi) ?*anyopaque;
    extern "kernel32" fn GetConsoleMode(*anyopaque, *u32) callconv(.winapi) c_int;
    extern "kernel32" fn SetConsoleMode(*anyopaque, u32) callconv(.winapi) c_int;
    extern "kernel32" fn SetConsoleCtrlHandler(?*const fn (u32) callconv(.winapi) c_int, c_int) callconv(.winapi) c_int;
    extern "kernel32" fn QueryPerformanceCounter(*i64) callconv(.winapi) c_int;
    extern "kernel32" fn QueryPerformanceFrequency(*i64) callconv(.winapi) c_int;
    extern "kernel32" fn Sleep(u32) callconv(.winapi) void;
    fn onControl(event: u32) callconv(.winapi) c_int {
        if (event != 0) return 0;
        interrupted.store(true, .seq_cst);
        return 1;
    }
    const Scope = struct {
        console: ?*anyopaque = null,
        mode: u32 = 0,
        fn begin() forth.RuntimeError!Scope {
            if (SetConsoleCtrlHandler(&onControl, 1) == 0) return error.HostFailed;
            var scope = Scope{};
            errdefer scope.end() catch {};
            if (input.input_is_terminal) {
                const console = GetStdHandle(@bitCast(@as(i32, -10))) orelse return error.HostFailed;
                if (GetConsoleMode(console, &scope.mode) == 0) return error.HostFailed;
                scope.console = console;
                if (SetConsoleMode(console, scope.mode | 1) == 0) return error.HostFailed;
            }
            return scope;
        }
        fn end(scope: *Scope) forth.RuntimeError!void {
            var success = true;
            if (scope.console) |console| success = SetConsoleMode(console, scope.mode) != 0;
            if (SetConsoleCtrlHandler(&onControl, 0) == 0) success = false;
            if (!success) return error.HostFailed;
        }
    };
};
const posix = if (is_windows) struct {} else struct {
    fn onSignal(_: std.c.SIG) callconv(.c) void {
        interrupted.store(true, .seq_cst);
    }
    const Scope = struct {
        previous: std.c.Sigaction,
        terminal: ?input.TerminalSettings = null,
        fn begin() forth.RuntimeError!Scope {
            var action = std.mem.zeroes(std.c.Sigaction);
            action.handler.handler = &onSignal;
            if (std.c.sigemptyset(&action.mask) != 0) return error.HostFailed;
            var scope: Scope = undefined;
            scope.terminal = null;
            if (std.c.sigaction(.INT, &action, &scope.previous) != 0) return error.HostFailed;
            errdefer scope.end() catch {};
            if (input.input_is_terminal) {
                var saved: input.TerminalSettings = undefined;
                if (!saved.get()) return error.HostFailed;
                scope.terminal = saved;
                var changed = saved;
                changed.termios.lflag.ISIG = true;
                changed.termios.lflag.NOFLSH = true;
                changed.termios.cc[@backingInt(std.c.V.INTR)] = 3;
                if (!saved.termios.lflag.ISIG) {
                    // Enabling ISIG in an existing raw session must not turn
                    // Ctrl-Z/Ctrl-\ into new signals instead of retained keys.
                    const disabled: u8 = @intCast(@import("c_file")._POSIX_VDISABLE);
                    changed.termios.cc[@backingInt(std.c.V.QUIT)] = disabled;
                    changed.termios.cc[@backingInt(std.c.V.SUSP)] = disabled;
                    if (comptime builtin.os.tag.isDarwin()) {
                        changed.termios.cc[@backingInt(std.c.V.DSUSP)] = disabled;
                        changed.termios.cc[@backingInt(std.c.V.STATUS)] = disabled;
                    }
                }
                if (!changed.set()) return error.HostFailed;
            }
            return scope;
        }
        fn end(scope: *Scope) forth.RuntimeError!void {
            var success = true;
            if (scope.terminal) |*terminal| {
                while (!terminal.set()) {
                    if (std.c._errno().* != @backingInt(std.c.E.INTR)) {
                        success = false;
                        break;
                    }
                }
            }
            if (std.c.sigaction(.INT, &scope.previous, null) != 0) success = false;
            if (!success) return error.HostFailed;
        }
    };
};
const WaitScope = if (is_windows) win.Scope else posix.Scope;

fn now() forth.RuntimeError!forth.Double {
    if (is_windows) {
        var counter: i64 = undefined;
        var frequency: i64 = undefined;
        if (win.QueryPerformanceCounter(&counter) == 0 or win.QueryPerformanceFrequency(&frequency) == 0 or frequency <= 0) return error.HostFailed;
        return @divFloor(@as(forth.Double, counter) * 1_000_000_000, frequency);
    }
    var instant: std.c.timespec = undefined;
    if (std.c.clock_gettime(std.c.CLOCK.MONOTONIC, &instant) != 0) return error.HostFailed;
    return @as(forth.Double, instant.sec) * 1_000_000_000 + instant.nsec;
}
fn loop(duration: forth.Double) forth.RuntimeError!void {
    const deadline = try now() + duration;
    while (true) {
        if (interrupted.load(.seq_cst)) return error.UserInterrupt;
        const remaining = deadline - try now();
        if (remaining <= 0) return;
        // Bound interrupt latency even if a signal is handled by another process thread.
        const part = @min(remaining, 20_000_000);
        if (is_windows) {
            win.Sleep(@intCast(@divTrunc(part + 999_999, 1_000_000)));
        } else {
            const request = std.c.timespec{ .sec = 0, .nsec = @intCast(part) };
            if (std.c.nanosleep(&request, null) != 0 and std.c._errno().* != @backingInt(std.c.E.INTR)) return error.HostFailed;
        }
    }
}
pub fn wait(duration: forth.Double) forth.RuntimeError!void {
    if (duration <= 0) return;
    if (duration > max_duration) return error.ResultOutOfRange;
    // Terminal modes and signal dispositions are process-global, so do not nest waits.
    if (active.swap(true, .seq_cst)) return error.HostFailed;
    defer active.store(false, .seq_cst);
    interrupted.store(false, .seq_cst);
    var scope = try WaitScope.begin();
    const outcome = loop(duration);
    const restored = scope.end();
    try outcome;
    try restored;
}

test "NS native wait is monotonic and restores the previous interrupt handler" {
    const saved_input = input.input_is_terminal;
    input.input_is_terminal = false;
    defer input.input_is_terminal = saved_input;
    if (!is_windows) {
        var before = std.mem.zeroes(std.c.Sigaction);
        var after = std.mem.zeroes(std.c.Sigaction);
        try std.testing.expectEqual(@as(c_int, 0), std.c.sigaction(.INT, null, &before));
        const start = try now();
        try wait(1_000_000);
        try std.testing.expect(try now() - start >= 1_000_000);
        try std.testing.expectEqual(@as(c_int, 0), std.c.sigaction(.INT, null, &after));
        try std.testing.expectEqual(before.handler.handler, after.handler.handler);
        try std.testing.expectEqual(before.flags, after.flags);
    } else {
        const start = try now();
        try wait(1_000_000);
        try std.testing.expect(try now() - start >= 1_000_000);
    }
    try std.testing.expectError(error.ResultOutOfRange, wait(max_duration + 1));
    try wait(0);
    try wait(-1);
    try wait(1);
    active.store(true, .seq_cst);
    defer active.store(false, .seq_cst);
    try std.testing.expectError(error.HostFailed, wait(1));
    try wait(0);
}
