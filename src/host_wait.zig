//! NS uses a monotonic deadline without reading input. Temporarily enable terminal
//! interrupt generation, keeping ordinary keys in their existing OS/host queues.
const std = @import("std");
const builtin = @import("builtin");
const forth = @import("forth.zig");
const input = @import("host_input.zig");
const clock = @import("host_clock.zig");
const base = @import("core/runtime_base.zig");
const signal_broker = @import("host_signal_broker.zig");
const host_runtime = @import("host_runtime.zig");
const max_duration = @import("core/nanosecond_wait.zig").max_duration;
const is_windows = builtin.os.tag == .windows;
var active = std.atomic.Value(bool).init(false);
var interrupted = std.atomic.Value(bool).init(false);
var accepting_interrupts = std.atomic.Value(bool).init(false);

const win = struct {
    extern "kernel32" fn GetStdHandle(u32) callconv(.winapi) ?*anyopaque;
    extern "kernel32" fn GetConsoleMode(*anyopaque, *u32) callconv(.winapi) c_int;
    extern "kernel32" fn SetConsoleMode(*anyopaque, u32) callconv(.winapi) c_int;
    extern "kernel32" fn SetConsoleCtrlHandler(?*const fn (u32) callconv(.winapi) c_int, c_int) callconv(.winapi) c_int;
    extern "kernel32" fn Sleep(u32) callconv(.winapi) void;
    extern "kernel32" fn GetCurrentThreadId() callconv(.winapi) u32;
    extern "kernel32" fn OpenThread(u32, c_int, u32) callconv(.winapi) ?*anyopaque;
    extern "kernel32" fn CloseHandle(*anyopaque) callconv(.winapi) c_int;
    extern "kernel32" fn CancelSynchronousIo(*anyopaque) callconv(.winapi) c_int;
    var read_lock = std.atomic.Value(bool).init(false);
    var read_thread: ?*anyopaque = null;
    var read_generation: u64 = 0;
    fn lockRead() void {
        while (read_lock.swap(true, .acquire)) std.atomic.spinLoopHint();
    }
    fn unlockRead() void {
        read_lock.store(false, .release);
    }
    fn beginConsoleRead() base.Error!void {
        const handle = OpenThread(1, 0, GetCurrentThreadId()) orelse return error.HostFailed;
        lockRead();
        defer unlockRead();
        if (read_thread != null) {
            _ = CloseHandle(handle);
            return error.HostFailed;
        }
        if (read_generation == std.math.maxInt(u64)) {
            _ = CloseHandle(handle);
            return error.HostFailed;
        }
        read_generation += 1;
        read_thread = handle;
    }
    fn endConsoleRead() void {
        lockRead();
        defer unlockRead();
        if (read_thread) |handle| {
            read_thread = null;
            _ = CloseHandle(handle);
        }
    }
    fn cancelConsoleRead() void {
        // Retry the small publication-to-ReadConsoleW race. The handle is used
        // under the same lock as close, and only while a console read owns it.
        lockRead();
        const generation = read_generation;
        unlockRead();
        for (0..250) |_| {
            lockRead();
            const reading = read_thread != null and generation == read_generation;
            if (reading) {
                _ = CancelSynchronousIo(read_thread.?);
            }
            unlockRead();
            if (!reading or !accepting_interrupts.load(.acquire)) return;
            Sleep(1);
        }
    }
    fn onControl(event: u32) callconv(.winapi) c_int {
        if (event != 0 or !accepting_interrupts.load(.acquire)) return 0;
        interrupted.store(true, .seq_cst);
        cancelConsoleRead();
        return 1;
    }
    const Scope = struct {
        console: ?*anyopaque = null,
        mode: u32 = 0,
        installed: bool = false,
        fn begin(scope: *Scope, with_terminal: bool) base.Error!void {
            if (SetConsoleCtrlHandler(&onControl, 1) == 0) return error.HostFailed;
            scope.installed = true;
            if (with_terminal and input.input_is_terminal) {
                const console = GetStdHandle(@bitCast(@as(i32, -10))) orelse return error.HostFailed;
                if (GetConsoleMode(console, &scope.mode) == 0) return error.HostFailed;
                scope.console = console;
                if (SetConsoleMode(console, scope.mode | 1) == 0) return error.HostFailed;
            }
        }
        fn end(scope: *Scope) base.Error!void {
            var success = true;
            if (scope.console) |console| {
                if (SetConsoleMode(console, scope.mode) != 0) scope.console = null else success = false;
            }
            if (scope.installed) {
                if (SetConsoleCtrlHandler(&onControl, 0) != 0) scope.installed = false else success = false;
            }
            if (!success) return error.HostFailed;
        }
    };
};
const posix = if (is_windows) struct {} else struct {
    fn onSignal(_: std.c.SIG) callconv(.c) void {
        interrupted.store(true, .seq_cst);
    }
    const Scope = struct {
        previous: std.c.Sigaction = undefined,
        installed: bool = false,
        terminal: ?input.TerminalSettings = null,
        fn begin(scope: *Scope, with_terminal: bool) base.Error!void {
            var action = std.mem.zeroes(std.c.Sigaction);
            action.handler.handler = &onSignal;
            if (std.c.sigemptyset(&action.mask) != 0) return error.HostFailed;
            if (std.c.sigaction(.INT, &action, &scope.previous) != 0) return error.HostFailed;
            scope.installed = true;
            if (with_terminal and input.input_is_terminal) {
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
        }
        fn end(scope: *Scope) base.Error!void {
            var success = true;
            if (scope.terminal) |*terminal| {
                var restored = true;
                while (!terminal.set()) {
                    if (std.c._errno().* != @backingInt(std.c.E.INTR)) {
                        success = false;
                        restored = false;
                        break;
                    }
                }
                if (restored) scope.terminal = null;
            }
            if (scope.installed) {
                if (std.c.sigaction(.INT, &scope.previous, null) == 0) scope.installed = false else success = false;
            }
            if (!success) return error.HostFailed;
        }
    };
};
const WaitScope = if (is_windows) win.Scope else posix.Scope;

const NativeScope = struct {
    with_terminal: bool,
    scope: ?WaitScope = null,
    mode_generation: u64 = 0,
    fn begin(context: ?*anyopaque) signal_broker.HookError!void {
        const self: *@This() = @ptrCast(@alignCast(context.?));
        interrupted.store(false, .seq_cst);
        accepting_interrupts.store(true, .release);
        self.mode_generation = input.modeGeneration();
        self.scope = .{};
        self.scope.?.begin(self.with_terminal) catch |err| {
            accepting_interrupts.store(false, .release);
            self.scope.?.end() catch return error.SignalRestoreFailed;
            self.scope = null;
            return err;
        };
    }
    fn end(context: ?*anyopaque) base.Error!void {
        const self: *@This() = @ptrCast(@alignCast(context.?));
        accepting_interrupts.store(false, .release);
        self.discardStaleTerminal();
        try self.scope.?.end();
        self.scope = null;
    }
    fn discardStaleTerminal(self: *@This()) void {
        // An authoritative enter/leave has superseded the saved terminal mode.
        // Still retry handler restoration, but never reapply an obsolete raw mode.
        if (self.mode_generation != input.modeGeneration()) {
            if (is_windows) self.scope.?.console = null else self.scope.?.terminal = null;
        }
    }
    fn beginTerminal(context: ?*anyopaque) signal_broker.HookError!void {
        const self: *@This() = @ptrCast(@alignCast(context.?));
        self.* = .{ .with_terminal = true };
        try begin(context);
    }
    fn beginAudio(context: ?*anyopaque) signal_broker.HookError!void {
        const self: *@This() = @ptrCast(@alignCast(context.?));
        self.* = .{ .with_terminal = false };
        try begin(context);
    }
    fn hooks(self: *@This()) signal_broker.Hooks {
        return .{ .context = self, .begin_fn = begin, .end_fn = end };
    }
};

// Native signal state is process-owned, including after a caller returns an error.
// A failed restoration therefore never leaves a ticket pointing at a dead stack.
var native_scope = NativeScope{ .with_terminal = false };
var recovery_broker: ?*signal_broker.Broker = null;

pub fn recover() base.Error!void {
    if (recovery_broker) |broker| {
        try broker.recover();
        recovery_broker = null;
        interrupted.store(false, .seq_cst);
    }
}
pub fn beforeInputModeChange() bool {
    recover() catch return false;
    return true;
}
fn beginNative(broker: *signal_broker.Broker, with_terminal: bool) base.Error!signal_broker.Ticket {
    try recover();
    if (broker.isActive()) return error.HostFailed;
    return broker.begin(.{
        .context = &native_scope,
        .begin_fn = if (with_terminal) NativeScope.beginTerminal else NativeScope.beginAudio,
        .end_fn = NativeScope.end,
    }) catch |err| {
        if (broker.failed_scope != null) recovery_broker = broker;
        return err;
    };
}
fn finishNative(broker: *signal_broker.Broker, ticket: signal_broker.Ticket) base.Error!void {
    broker.end(ticket) catch |err| {
        recovery_broker = broker;
        return err;
    };
}

// Nested cooked input on the host thread shares one interrupt-only native scope.
var input_depth: u32 = 0;
var input_ticket: ?signal_broker.Ticket = null;
pub fn beginInput() base.Error!void {
    if (input_depth == std.math.maxInt(u32)) return error.HostFailed;
    if (input_depth == 0) input_ticket = try beginNative(&signal_broker.fallback, false);
    input_depth += 1;
}
pub fn inputInterrupted() bool {
    return input_depth != 0 and interrupted.load(.seq_cst);
}
pub fn endInput() forth.RuntimeError!void {
    if (input_depth == 0) return error.HostFailed;
    input_depth -= 1;
    if (input_depth != 0) return;
    const ticket = input_ticket orelse return error.HostFailed;
    input_ticket = null;
    try finishNative(&signal_broker.fallback, ticket);
    if (interrupted.swap(false, .acq_rel)) return error.UserInterrupt;
}

/// An interrupt-only input scope can cancel synchronous ReadConsoleW without
/// switching the console to VT/raw input or losing its line editor.
pub fn beginConsoleRead() base.Error!void {
    if (is_windows and input_depth != 0) try win.beginConsoleRead();
}
pub fn endConsoleRead() void {
    if (is_windows and input_depth != 0) win.endConsoleRead();
}
/// Native Ctrl+C may complete ReadConsoleW before its handler thread runs.
/// Keep the scope installed briefly so a zero-length read is not made into EOF.
pub fn awaitConsoleInterrupt() bool {
    if (!is_windows or input_depth == 0) return false;
    for (0..100) |_| {
        if (inputInterrupted()) return true;
        win.Sleep(1);
    }
    return inputInterrupted();
}
pub fn inputGuardActive() bool {
    return input_depth != 0;
}

fn now() forth.RuntimeError!forth.Double {
    return clock.now();
}
fn loop(duration: forth.Double, source: base.Clock) forth.RuntimeError!void {
    const sum = @addWithOverflow(try source.now(), duration);
    if (sum[1] != 0) return error.ResultOutOfRange;
    const deadline = sum[0];
    while (true) {
        if (interrupted.load(.seq_cst)) return error.UserInterrupt;
        const current = try source.now();
        if (current >= deadline) return;
        const difference = @subWithOverflow(deadline, current);
        // Bound interrupt latency even if a signal is handled by another process thread.
        const part = if (difference[1] != 0) 20_000_000 else @min(difference[0], 20_000_000);
        if (is_windows) {
            win.Sleep(@intCast(@divTrunc(part + 999_999, 1_000_000)));
        } else {
            const request = std.c.timespec{ .sec = 0, .nsec = @intCast(part) };
            if (std.c.nanosleep(&request, null) != 0 and std.c._errno().* != @backingInt(std.c.E.INTR)) return error.HostFailed;
        }
    }
}
pub fn wait(duration: forth.Double) forth.RuntimeError!void {
    return waitUsing(&signal_broker.fallback, clock.clock, duration);
}
pub fn waitWithRuntime(runtime: *host_runtime.Runtime, duration: forth.Double) forth.RuntimeError!void {
    if (duration <= 0) return;
    return waitUsing(try runtime.signalBroker(), runtime.clock, duration);
}
fn waitUsing(broker: *signal_broker.Broker, source: base.Clock, duration: forth.Double) forth.RuntimeError!void {
    if (duration <= 0) return;
    if (duration > max_duration) return error.ResultOutOfRange;
    // Terminal modes and signal dispositions are process-global, so do not nest waits.
    if (active.swap(true, .seq_cst)) return error.HostFailed;
    defer active.store(false, .seq_cst);
    const scope = try beginNative(broker, true);
    const outcome = loop(duration, source);
    // Restoring the console/handler takes priority over an interrupted wait.
    try finishNative(broker, scope);
    try outcome;
}

/// Audio keeps raw mode unchanged; it uses the same process signal owner as NS.
pub fn audioWait(runtime: ?*host_runtime.Runtime) forth.AudioWait {
    const broker = if (runtime) |value| value.signalBroker() catch return .host_failed else &signal_broker.fallback;
    const scope = beginNative(broker, false) catch return .host_failed;
    if (is_windows) {
        win.Sleep(3);
    } else {
        const request = std.c.timespec{ .sec = 0, .nsec = 3_000_000 };
        _ = std.c.nanosleep(&request, null);
    }
    finishNative(broker, scope) catch return .host_failed;
    if (interrupted.swap(false, .acq_rel)) return .interrupted;
    return if (input.isRaw()) .read_input else .waited;
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

test "runtime NS and audio scopes reject nesting and release ownership on clock failure" {
    const saved_input = input.input_is_terminal;
    input.input_is_terminal = false;
    defer input.input_is_terminal = saved_input;
    var runtime = try host_runtime.Runtime.init();
    defer runtime.deinit() catch |err| std.debug.print("runtime cleanup: {s}\n", .{@errorName(err)});
    const Fake = struct {
        fn noOp(_: ?*anyopaque) base.Error!void {}
        fn fail(_: ?*anyopaque) base.Error!base.Instant {
            return error.HostFailed;
        }
    };
    const held = try runtime.signals.begin(.{ .context = null, .begin_fn = Fake.noOp, .end_fn = Fake.noOp });
    defer if (runtime.signals.isActive() and runtime.signals.scopes.stack[runtime.signals.scopes.depth - 1].serial == held.scope.serial) {
        runtime.signals.end(held) catch |err| std.debug.print("scope cleanup: {s}\n", .{@errorName(err)});
    };
    try std.testing.expectError(error.HostFailed, waitWithRuntime(&runtime, 1));
    try std.testing.expectEqual(forth.AudioWait.host_failed, audioWait(&runtime));
    try runtime.signals.end(held);
    runtime.clock = .{ .context = null, .now_fn = Fake.fail };
    try std.testing.expectError(error.HostFailed, waitWithRuntime(&runtime, 1));
    try std.testing.expect(!runtime.signals.isActive());
    runtime.clock = clock.clock;
    try waitWithRuntime(&runtime, 1);
    try std.testing.expect(audioWait(&runtime) != .host_failed);
    try std.testing.expect(!runtime.signals.isActive());
}

test "failed signal restoration survives the wait caller and recovers before audio" {
    const saved_input = input.input_is_terminal;
    input.input_is_terminal = false;
    defer input.input_is_terminal = saved_input;
    var runtime = try host_runtime.Runtime.init();
    defer runtime.deinit() catch |err| std.debug.print("runtime cleanup: {s}\n", .{@errorName(err)});
    const Fake = struct {
        ends: usize = 0,
        fn begin(_: ?*anyopaque) signal_broker.HookError!void {}
        fn end(context: ?*anyopaque) base.Error!void {
            const self: *@This() = @ptrCast(@alignCast(context.?));
            self.ends += 1;
            if (self.ends == 1) return error.HostFailed;
        }
    };
    var fake = Fake{};
    const ticket = try runtime.signals.begin(.{ .context = &fake, .begin_fn = Fake.begin, .end_fn = Fake.end });
    defer recover() catch |err| std.debug.print("restoration cleanup: {s}\n", .{@errorName(err)});
    try std.testing.expectError(error.HostFailed, finishNative(&runtime.signals, ticket));
    try std.testing.expectError(error.ResourceBusy, runtime.deinit());
    interrupted.store(true, .seq_cst);
    try std.testing.expect(audioWait(&runtime) != .host_failed);
    try std.testing.expectEqual(@as(usize, 2), fake.ends);
    try std.testing.expect(recovery_broker == null);
    try std.testing.expect(!runtime.signals.isActive());
    try waitWithRuntime(&runtime, 1);
}

test "a superseded terminal snapshot is discarded without reapplying raw mode" {
    var saved = NativeScope{
        .with_terminal = true,
        .mode_generation = input.modeGeneration() +% 1,
        .scope = if (is_windows) .{ .console = @ptrFromInt(1) } else .{ .terminal = std.mem.zeroes(input.TerminalSettings) },
    };
    // Inspect invalidation directly: a broken test must never apply zero termios
    // to the real terminal of the person running the suite.
    saved.discardStaleTerminal();
    if (is_windows) {
        try std.testing.expect(saved.scope.?.console == null);
    } else {
        try std.testing.expect(saved.scope.?.terminal == null);
    }
}
test "nested cooked input shares its ticket and excludes other runtime scopes" {
    const saved_input = input.input_is_terminal;
    input.input_is_terminal = false;
    defer input.input_is_terminal = saved_input;
    var runtime = try host_runtime.Runtime.init();
    defer runtime.deinit() catch unreachable;
    try beginInput();
    defer if (input_depth != 0) endInput() catch unreachable;
    const ticket = input_ticket.?;
    try beginInput();
    try std.testing.expectEqual(ticket, input_ticket.?);
    try std.testing.expectError(error.HostFailed, waitWithRuntime(&runtime, 1));
    try endInput();
    try std.testing.expect(input_ticket != null);
    try endInput();
    try std.testing.expect(input_ticket == null);
    try waitWithRuntime(&runtime, 1);
}
