//! One consumer, many producers. Update state before notify; observe before checking
//! the state. A changed generation covers notifications that precede OS registration.
//! Join all producers/consumers before deinit. This object must not move after sharing.
const std = @import("std");
const builtin = @import("builtin");
const base = @import("core/runtime_base.zig");
const host_clock = @import("host_clock.zig");
const is_windows = builtin.os.tag == .windows;

const windows = struct {
    const Handle = *anyopaque;
    extern "kernel32" fn CreateEventW(?*anyopaque, i32, i32, ?[*:0]const u16) callconv(.winapi) ?Handle;
    extern "kernel32" fn GetConsoleMode(Handle, *u32) callconv(.winapi) i32;
    extern "kernel32" fn SetEvent(Handle) callconv(.winapi) i32;
    extern "kernel32" fn WaitForMultipleObjects(u32, [*]const Handle, i32, u32) callconv(.winapi) u32;
    extern "kernel32" fn WaitForSingleObject(Handle, u32) callconv(.winapi) u32;
    extern "kernel32" fn CloseHandle(Handle) callconv(.winapi) i32;
    extern "kernel32" fn GetHandleInformation(Handle, *u32) callconv(.winapi) i32;
};
const posix = struct {
    extern "c" fn fcntl(c_int, c_int, ...) c_int;
};
const Native = if (is_windows) struct { handle: ?windows.Handle = null } else struct { fds: [2]c_int = .{ -1, -1 } };
pub const Outcome = base.WakeOutcome;

pub const Wake = struct {
    native: Native = .{},
    generation: std.atomic.Value(u64) = .init(0),
    pending: std.atomic.Value(bool) = .init(false),

    /// On non-Linux POSIX, initialize before concurrent child creation: pipe+fcntl
    /// cannot atomically set CLOEXEC. Later process integration must serialize it.
    pub fn init() base.Error!Wake {
        var self = Wake{};
        if (is_windows) {
            // Auto reset: consuming an old event never erases a later generation.
            self.native.handle = windows.CreateEventW(null, 0, 0, null) orelse return error.HostFailed;
        } else {
            if (builtin.os.tag == .linux) {
                if (std.c.pipe2(&self.native.fds, .{ .CLOEXEC = true, .NONBLOCK = true }) != 0) return error.HostFailed;
            } else {
                if (std.c.pipe(&self.native.fds) != 0) return error.HostFailed;
                errdefer for (self.native.fds) |fd| {
                    _ = std.c.close(fd);
                };
                const nonblock: c_int = @bitCast(@as(u32, @bitCast(std.c.O{ .NONBLOCK = true })));
                for (self.native.fds) |fd| {
                    const flags = posix.fcntl(fd, std.c.F.GETFL);
                    const fd_flags = posix.fcntl(fd, std.c.F.GETFD);
                    if (flags < 0 or fd_flags < 0 or
                        posix.fcntl(fd, std.c.F.SETFL, flags | nonblock) < 0 or
                        posix.fcntl(fd, std.c.F.SETFD, fd_flags | @import("c_file").FD_CLOEXEC) < 0) return error.HostFailed;
                }
            }
        }
        return self;
    }

    pub fn deinit(self: *Wake) base.Error!void {
        if (is_windows) {
            const handle = self.native.handle orelse return;
            self.native.handle = null;
            if (windows.CloseHandle(handle) == 0) return error.HostFailed;
        } else {
            const descriptors = self.native.fds;
            self.native.fds = .{ -1, -1 };
            var failed = false;
            for ([_]c_int{ descriptors[1], descriptors[0] }) |fd| if (fd >= 0) {
                if (std.c.close(fd) != 0) failed = true;
            };
            if (failed) return error.HostFailed;
        }
    }

    pub fn observe(self: *const Wake) u64 {
        return self.generation.load(.acquire);
    }

    pub fn operations(self: *Wake) base.WakeOps {
        return .{ .context = self, .observe_fn = observeContext, .notify_fn = notifyContext, .wait_fn = waitContext };
    }
    fn observeContext(context: ?*anyopaque) u64 {
        const self: *Wake = @ptrCast(@alignCast(context.?));
        return self.observe();
    }
    fn notifyContext(context: ?*anyopaque) base.Error!void {
        const self: *Wake = @ptrCast(@alignCast(context.?));
        return self.notify();
    }
    fn waitContext(context: ?*anyopaque, observed: u64, deadline: base.Deadline, token: ?*const base.Cancellation, clock: base.Clock) base.Error!Outcome {
        const self: *Wake = @ptrCast(@alignCast(context.?));
        return self.waitWithClock(observed, deadline, token, clock);
    }

    pub fn notify(self: *Wake) base.Error!void {
        if (!self.isOpen()) return error.HostFailed;
        var previous = self.observe();
        while (true) {
            if (previous == std.math.maxInt(u64)) return error.ResultOutOfRange;
            previous = self.generation.cmpxchgWeak(previous, previous + 1, .acq_rel, .acquire) orelse break;
        }
        if (is_windows) {
            if (windows.SetEvent(self.native.handle.?) == 0) return error.HostFailed;
        } else {
            // A single byte represents all generations until the consumer drains it.
            if (self.pending.swap(true, .acq_rel)) return;
            const byte = [_]u8{1};
            while (std.c.write(self.native.fds[1], &byte, 1) != 1) {
                const err = std.c._errno().*;
                if (err == @backingInt(std.c.E.AGAIN)) return; // Pipe already wakes us.
                if (err != @backingInt(std.c.E.INTR)) {
                    _ = self.pending.swap(false, .acq_rel);
                    return error.HostFailed;
                }
            }
        }
    }

    fn isOpen(self: *const Wake) bool {
        return if (is_windows) self.native.handle != null else self.native.fds[0] >= 0;
    }

    pub fn wait(self: *Wake, observed: u64, deadline: base.Deadline, cancellation: ?*const base.Cancellation) base.Error!Outcome {
        return self.waitWithClock(observed, deadline, cancellation, host_clock.clock);
    }

    pub fn waitWithClock(self: *Wake, observed: u64, deadline: base.Deadline, cancellation: ?*const base.Cancellation, clock: base.Clock) base.Error!Outcome {
        return self.waitReadableWithClock(observed, deadline, cancellation, clock, -1);
    }

    /// Single consumer only. POSIX extra_fd is borrowed, never read here; its owner
    /// must pump it after .notified. Wake consumption retains read -> clear -> recheck order.
    pub fn waitReadableWithClock(self: *Wake, observed: u64, deadline: base.Deadline, cancellation: ?*const base.Cancellation, clock: base.Clock, extra_fd: c_int) base.Error!Outcome {
        if (is_windows and extra_fd >= 0) return error.HostFailed;
        const extra = [_]Interest{.{ .fd = extra_fd }};
        return self.waitMany(observed, deadline, cancellation, clock, if (extra_fd >= 0) &extra else &.{});
    }

    /// Only level-triggered native sources; never pass another auto-reset event.
    pub const Interest = struct { fd: c_int = -1, writing: bool = false, console: ?*anyopaque = null };
    pub fn waitMany(self: *Wake, observed: u64, deadline: base.Deadline, cancellation: ?*const base.Cancellation, clock: base.Clock, interests: []const Interest) base.Error!Outcome {
        if (interests.len > (if (is_windows) @as(usize, 63) else 129)) return error.ResultOutOfRange;
        if (is_windows) for (interests) |interest| {
            var mode: u32 = 0;
            // Restrict additional handles to consoles, excluding auto-reset events.
            if (windows.GetConsoleMode(interest.console orelse return error.HostFailed, &mode) == 0) return error.HostFailed;
        };
        if (!self.isOpen()) return error.HostFailed;
        while (true) {
            if (cancellation) |token| if (token.isRequested()) return .cancelled;
            if (self.observe() != observed) return .notified;
            const now = try clock.now();
            if (deadline.expired(now)) return .timeout;
            // A standalone cancellation token does not signal the OS object.
            // Bound each OS wait; scheduling latency is not guaranteed.
            const milliseconds = deadline.remainingMilliseconds(now, 20);
            if (is_windows) {
                var handles: [65]windows.Handle = undefined;
                handles[0] = self.native.handle.?;
                for (interests, 1..) |interest, index| handles[index] = interest.console orelse return error.HostFailed;
                // Windows supports at most 64 handles including the common wake.
                if (interests.len > 63) return error.ResultOutOfRange;
                const result = if (interests.len == 0) windows.WaitForSingleObject(self.native.handle.?, milliseconds) else windows.WaitForMultipleObjects(@intCast(interests.len + 1), &handles, 0, milliseconds);
                if (result > 0 and result < interests.len + 1) {
                    if (cancellation) |token| if (token.isRequested()) return .cancelled;
                    return .notified;
                }
                if (result != 0 and result != 258) return error.HostFailed;
            } else {
                var descriptors: [130]std.c.pollfd = undefined;
                descriptors[0] = .{ .fd = self.native.fds[0], .events = std.c.POLL.IN, .revents = 0 };
                for (interests, 1..) |interest, index| descriptors[index] = .{ .fd = interest.fd, .events = if (interest.writing) std.c.POLL.OUT else std.c.POLL.IN, .revents = 0 };
                const result = std.c.poll(&descriptors, @intCast(interests.len + 1), @intCast(milliseconds));
                if (result < 0) {
                    if (std.c._errno().* == @backingInt(std.c.E.INTR)) continue;
                    return error.HostFailed;
                }
                if (result > 0) {
                    if ((descriptors[0].revents & (std.c.POLL.ERR | std.c.POLL.HUP | std.c.POLL.NVAL)) != 0) return error.HostFailed;
                    if (descriptors[0].revents == 0) {
                        if (cancellation) |token| if (token.isRequested()) return .cancelled;
                        return .notified;
                    }
                    var bytes: [256]u8 = undefined;
                    const count = std.c.read(self.native.fds[0], &bytes, bytes.len);
                    if (count == 0) return error.HostFailed;
                    if (count < 0) {
                        const err = std.c._errno().*;
                        if (err != @backingInt(std.c.E.AGAIN) and err != @backingInt(std.c.E.INTR)) return error.HostFailed;
                        if (err == @backingInt(std.c.E.INTR)) continue;
                    }
                    _ = self.pending.swap(false, .acq_rel);
                    // Re-enter cancellation -> generation -> deadline order.
                    if (self.observe() != observed) continue;
                    var extra_ready = false;
                    for (descriptors[1 .. interests.len + 1]) |descriptor| extra_ready = extra_ready or descriptor.revents != 0;
                    if (extra_ready) {
                        if (cancellation) |token| if (token.isRequested()) return .cancelled;
                        return .notified;
                    }
                    // One bounded read per pass: producers cannot starve cancellation.
                }
            }
        }
    }
};

test "runtime wake retains early and coalesced notifications" {
    var wake = try Wake.init();
    defer wake.deinit() catch unreachable;
    const before = wake.observe();
    for (0..1000) |_| try wake.notify();
    const deadline = try base.Deadline.afterMilliseconds(try host_clock.now(), 0);
    try std.testing.expectEqual(Outcome.notified, try wake.wait(before, deadline, null));
    // A stale OS signal is not a new logical notification.
    try std.testing.expectEqual(Outcome.timeout, try wake.wait(wake.observe(), deadline, null));
    var token = base.Cancellation{};
    token.request();
    try std.testing.expectEqual(Outcome.cancelled, try wake.wait(wake.observe(), .{ .at = null }, &token));
    try wake.deinit();
    try std.testing.expectError(error.HostFailed, wake.notify());
    try std.testing.expectError(error.HostFailed, wake.wait(0, deadline, null));
}

test "runtime wake handles a concurrent producer before or during registration" {
    var wake = try Wake.init();
    defer wake.deinit() catch unreachable;
    const observed = wake.observe();
    const Producer = struct {
        fn run(target: *Wake) void {
            target.notify() catch unreachable;
        }
    };
    const deadline = try base.Deadline.afterMilliseconds(try host_clock.now(), 5000);
    const producer = try std.Thread.spawn(.{}, Producer.run, .{&wake});
    defer producer.join();
    try std.testing.expectEqual(Outcome.notified, try wake.wait(observed, deadline, null));
}

test "runtime wake rechecks stale OS signals without extending its deadline" {
    const FakeClock = struct {
        instant: base.Instant = 0,
        reads: usize = 0,
        fn now(context: ?*anyopaque) base.Error!base.Instant {
            const self: *@This() = @ptrCast(@alignCast(context.?));
            const value = self.instant;
            self.instant += 1_000_000;
            self.reads += 1;
            return value;
        }
        fn fail(_: ?*anyopaque) base.Error!base.Instant {
            return error.HostFailed;
        }
    };
    var wake = try Wake.init();
    defer wake.deinit() catch unreachable;
    try wake.notify();
    var clock = FakeClock{};
    const deadline = try base.Deadline.afterMilliseconds(0, 1);
    try std.testing.expectEqual(Outcome.timeout, try wake.waitWithClock(wake.observe(), deadline, null, .{ .context = &clock, .now_fn = FakeClock.now }));
    try std.testing.expectEqual(@as(usize, 2), clock.reads);
    try std.testing.expectError(error.HostFailed, wake.waitWithClock(wake.observe(), .{ .at = null }, null, .{ .context = null, .now_fn = FakeClock.fail }));
    wake.generation.store(std.math.maxInt(u64), .release);
    try std.testing.expectError(error.ResultOutOfRange, wake.notify());
}

test "POSIX wake handles a full pipe and retries after a failed write" {
    if (is_windows) return error.SkipZigTest;
    var wake = try Wake.init();
    defer wake.deinit() catch |err| std.debug.print("wake cleanup: {s}\n", .{@errorName(err)});
    const fd = wake.native.fds[1];
    wake.native.fds[1] = -1;
    const failure = wake.notify();
    wake.native.fds[1] = fd;
    try std.testing.expectError(error.HostFailed, failure);
    try std.testing.expect(!wake.pending.load(.acquire));
    const byte = [_]u8{1};
    while (true) {
        if (std.c.write(fd, &byte, 1) == 1) continue;
        const err = std.c._errno().*;
        if (err == @backingInt(std.c.E.INTR)) continue;
        try std.testing.expectEqual(@backingInt(std.c.E.AGAIN), err);
        break;
    }
    const observed = wake.observe();
    try wake.notify();
    try std.testing.expectEqual(Outcome.notified, try wake.wait(observed, .{ .at = 0 }, null));
}

test "wake handles are noninheritable and POSIX descriptors are nonblocking" {
    var wake = try Wake.init();
    defer wake.deinit() catch |err| std.debug.print("wake cleanup: {s}\n", .{@errorName(err)});
    if (is_windows) {
        var flags: u32 = undefined;
        try std.testing.expect(windows.GetHandleInformation(wake.native.handle.?, &flags) != 0);
        try std.testing.expectEqual(@as(u32, 0), flags & 1); // HANDLE_FLAG_INHERIT
    } else {
        const nonblock: c_int = @bitCast(@as(u32, @bitCast(std.c.O{ .NONBLOCK = true })));
        for (wake.native.fds) |fd| {
            const flags = posix.fcntl(fd, std.c.F.GETFL);
            const fd_flags = posix.fcntl(fd, std.c.F.GETFD);
            try std.testing.expect(flags >= 0 and fd_flags >= 0);
            try std.testing.expect(flags & nonblock != 0);
            try std.testing.expect(fd_flags & @import("c_file").FD_CLOEXEC != 0);
        }
    }
}
