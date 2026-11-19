//! Stable host-owned runtime. Construct before sharing; never copy/move it or its
//! owned tables after publication. All metadata mutation is on its host thread.
const std = @import("std");
const base = @import("core/runtime_base.zig");
const host_clock = @import("host_clock.zig");
const wake_module = @import("host_wake.zig");
const signal_module = @import("host_signal_broker.zig");
pub const Error = base.Error || base.ResourceError || error{ ResourceBusy, Closed };

pub const Identities = struct {
    next: std.atomic.Value(u64) = .init(2),
    pub fn take(self: *Identities) error{IdentityExhausted}!u64 {
        var value = self.next.load(.acquire);
        while (true) {
            if (value == 0) return error.IdentityExhausted;
            const following = if (value == std.math.maxInt(u64)) 0 else value + 1;
            value = self.next.cmpxchgWeak(value, following, .acq_rel, .acquire) orelse return value;
        }
    }
};
var identities = Identities{};
const Phase = enum(u8) { open, closing, closed };

pub const Runtime = struct {
    owner: u64,
    clock: base.Clock,
    native_wake: ?wake_module.Wake = null,
    injected_wake: ?base.WakeOps = null,
    signals: signal_module.Broker,
    cancellation: base.Cancellation = .{},
    tables: usize = 0,
    phase: std.atomic.Value(Phase) = .init(.open),

    pub fn init() Error!Runtime {
        const owner = try identities.take();
        return .{ .owner = owner, .clock = host_clock.clock, .native_wake = try wake_module.Wake.init(), .signals = .{ .owner = owner } };
    }
    /// The injector owns its context and must keep it alive through deinit.
    pub fn initWith(clock: base.Clock, wake: base.WakeOps) Error!Runtime {
        const owner = try identities.take();
        return .{ .owner = owner, .clock = clock, .injected_wake = wake, .signals = .{ .owner = owner } };
    }
    fn ops(self: *Runtime) base.WakeOps {
        return self.injected_wake orelse self.native_wake.?.operations();
    }
    pub fn observe(self: *Runtime) Error!u64 {
        if (self.phase.load(.acquire) == .closed) return error.Closed;
        const operations = self.ops();
        return operations.observe_fn(operations.context);
    }
    pub fn notify(self: *Runtime) Error!void {
        if (self.phase.load(.acquire) == .closed) return error.Closed;
        const operations = self.ops();
        try operations.notify_fn(operations.context);
    }
    pub fn wait(self: *Runtime, observed: u64, deadline: base.Deadline) Error!base.WakeOutcome {
        if (self.phase.load(.acquire) == .closed) return error.Closed;
        const operations = self.ops();
        return operations.wait_fn(operations.context, observed, deadline, &self.cancellation, self.clock);
    }
    /// Prefer this entry when the caller has no deadline from this runtime's clock.
    pub fn waitFor(self: *Runtime, observed: u64, milliseconds: i64) Error!base.WakeOutcome {
        if (self.phase.load(.acquire) == .closed) return error.Closed;
        if (self.cancellation.isRequested()) return .cancelled;
        return self.wait(observed, try base.Deadline.afterMilliseconds(try self.clock.now(), milliseconds));
    }
    pub fn signalBroker(self: *Runtime) base.Error!*signal_module.Broker {
        if (self.phase.load(.acquire) != .open) return error.HostFailed;
        return &self.signals;
    }
    pub fn beginShutdown(self: *Runtime) Error!void {
        if (self.phase.load(.acquire) == .closed) return error.Closed;
        self.phase.store(.closing, .release);
        self.cancellation.request();
        try self.notify();
    }
    /// Caller first joins every producer/consumer. Live metadata prevents teardown.
    /// ResourceBusy means this object must remain alive: retained signal recovery
    /// may still point at its broker. Recover/close users before destroying storage.
    pub fn deinit(self: *Runtime) Error!void {
        if (self.phase.load(.acquire) == .closed) return;
        if (self.tables != 0 or self.signals.isActive()) return error.ResourceBusy;
        // Closing an OS object may fail after invalidating its native identity.
        // Never present a second close as a fresh successful teardown.
        self.phase.store(.closed, .release);
        if (self.native_wake) |*wake| try wake.deinit();
    }
    /// out is fresh storage or a previously closed table. Bind its stable address.
    pub fn initTable(self: *Runtime, comptime Payload: type, comptime capacity: usize, out: *OwnedTable(Payload, capacity)) Error!void {
        if (self.phase.load(.acquire) != .open) return error.Closed;
        const epoch = try identities.take();
        const table = try base.ResourceTable(Payload, capacity).init(epoch);
        self.tables += 1;
        out.* = .{ .runtime = self, .table = table, .bound_address = @intFromPtr(out) };
    }
};

pub fn OwnedTable(comptime Payload: type, comptime capacity: usize) type {
    return struct {
        const Self = @This();
        runtime: *Runtime,
        table: base.ResourceTable(Payload, capacity),
        bound_address: usize,
        closed: bool = false,
        fn check(self: *const Self) Error!void {
            if (self.bound_address != @intFromPtr(self)) return error.InvalidHandle;
            if (self.closed or self.runtime.phase.load(.acquire) == .closed) return error.Closed;
        }
        pub fn insert(self: *Self, kind: base.ResourceKind, payload: Payload) Error!base.Handle {
            try self.check();
            if (self.runtime.phase.load(.acquire) != .open) return error.Closed;
            return self.table.insert(self.runtime.owner, kind, payload);
        }
        /// Borrowed until removal or deinit; never retain across slot reuse.
        pub fn get(self: *Self, handle: base.Handle, kind: base.ResourceKind) Error!*Payload {
            try self.check();
            return self.table.get(handle, self.runtime.owner, kind);
        }
        pub fn remove(self: *Self, handle: base.Handle, kind: base.ResourceKind) Error!Payload {
            try self.check();
            return self.table.remove(handle, self.runtime.owner, kind);
        }
        pub fn deinit(self: *Self) Error!void {
            if (self.bound_address != @intFromPtr(self)) return error.InvalidHandle;
            if (self.closed) return;
            if (self.table.count() != 0) return error.ResourceBusy;
            self.closed = true;
            self.runtime.tables -= 1;
        }
    };
}

test "runtime identities and table lifetimes reject foreign and previous incarnations" {
    var runtime = try Runtime.init();
    defer runtime.deinit() catch |err| std.debug.print("runtime cleanup: {s}\n", .{@errorName(err)});
    var first: OwnedTable(u32, 1) = undefined;
    var second: OwnedTable(u32, 1) = undefined;
    try runtime.initTable(u32, 1, &first);
    try runtime.initTable(u32, 1, &second);
    var copy = first;
    try std.testing.expectError(error.InvalidHandle, copy.insert(.task, 1));
    try std.testing.expectError(error.InvalidHandle, copy.deinit());
    const a = try first.insert(.task, 10);
    const b = try second.insert(.task, 20);
    try std.testing.expectError(error.InvalidHandle, second.get(a, .task));
    try std.testing.expectError(error.ResourceBusy, runtime.deinit());
    try std.testing.expectError(error.ResourceBusy, first.deinit());
    _ = try first.remove(a, .task);
    try first.deinit();
    var third: OwnedTable(u32, 1) = undefined;
    try runtime.initTable(u32, 1, &third);
    const c = try third.insert(.task, 30);
    try std.testing.expectError(error.InvalidHandle, third.get(a, .task));
    try runtime.beginShutdown();
    try std.testing.expectError(error.Closed, third.insert(.task, 40));
    try std.testing.expectEqual(base.WakeOutcome.cancelled, try runtime.wait(try runtime.observe(), .{ .at = null }));
    _ = try second.remove(b, .task);
    _ = try third.remove(c, .task);
    try second.deinit();
    try third.deinit();
    try runtime.deinit();
    try std.testing.expectError(error.Closed, runtime.observe());
    try std.testing.expectError(error.Closed, first.get(a, .task));
    var exhausted = Identities{};
    exhausted.next.store(std.math.maxInt(u64), .release);
    try std.testing.expectEqual(std.math.maxInt(u64), try exhausted.take());
    try std.testing.expectError(error.IdentityExhausted, exhausted.take());
}

test "runtime injected wake and clock preserve failures and ownership" {
    const Fake = struct {
        generation: u64 = 0,
        fail: bool = false,
        fn observe(context: ?*anyopaque) u64 {
            const self: *@This() = @ptrCast(@alignCast(context.?));
            return self.generation;
        }
        fn notify(context: ?*anyopaque) base.Error!void {
            const self: *@This() = @ptrCast(@alignCast(context.?));
            if (self.fail) return error.HostFailed;
            self.generation += 1;
        }
        fn now(_: ?*anyopaque) base.Error!base.Instant {
            return 12;
        }
        fn wait(context: ?*anyopaque, generation: u64, deadline: base.Deadline, token: ?*const base.Cancellation, clock: base.Clock) base.Error!base.WakeOutcome {
            const self: *@This() = @ptrCast(@alignCast(context.?));
            if (self.fail) return error.HostFailed;
            if (token.?.isRequested()) return .cancelled;
            if (generation != self.generation) return .notified;
            if (deadline.expired(try clock.now())) return .timeout;
            return error.HostFailed;
        }
    };
    var fake = Fake{};
    var runtime = try Runtime.initWith(.{ .context = null, .now_fn = Fake.now }, .{ .context = &fake, .observe_fn = Fake.observe, .notify_fn = Fake.notify, .wait_fn = Fake.wait });
    defer runtime.deinit() catch |err| std.debug.print("runtime cleanup: {s}\n", .{@errorName(err)});
    const observed = try runtime.observe();
    try runtime.notify();
    try std.testing.expectEqual(base.WakeOutcome.notified, try runtime.wait(observed, .{ .at = 12 }));
    try std.testing.expectEqual(base.WakeOutcome.timeout, try runtime.wait(try runtime.observe(), .{ .at = 12 }));
    try std.testing.expectEqual(base.WakeOutcome.timeout, try runtime.waitFor(try runtime.observe(), 0));
    fake.fail = true;
    try std.testing.expectError(error.HostFailed, runtime.beginShutdown());
    try std.testing.expect(runtime.cancellation.isRequested());
    fake.fail = false;
    try std.testing.expectEqual(base.WakeOutcome.cancelled, try runtime.wait(observed, .{ .at = null }));
}

test "runtime producers can notify while the owner begins shutdown" {
    var runtime = try Runtime.init();
    defer runtime.deinit() catch |err| std.debug.print("runtime cleanup: {s}\n", .{@errorName(err)});
    const Producer = struct {
        fn run(target: *Runtime) void {
            for (0..64) |_| target.notify() catch return;
        }
    };
    const producer = try std.Thread.spawn(.{}, Producer.run, .{&runtime});
    defer producer.join();
    try runtime.beginShutdown();
    try std.testing.expectEqual(base.WakeOutcome.cancelled, try runtime.waitFor(try runtime.observe(), -1));
}
