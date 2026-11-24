//! Internal retained drawing condition; no public Forth ABI. Lock order: backend -> Source.
const std = @import("std");
const base = @import("runtime_base.zig");
pub const Error = base.Error || error{ UnsupportedBackend, NoWindow, InvalidTarget, NotRegistered };
pub const Registration = struct { index: usize, generation: u64, target: u64, capability_generation: u64, active: bool = true };
pub const Result = enum { pending, painted, released, capability_lost };
pub const Source = struct {
    guard: std.atomic.Value(u8) = .init(0),
    wake: ?base.WakeOps = null,
    failed: bool = false, // Irrecoverable generation exhaustion.
    notification_failed: bool = false,
    selected: bool = true,
    capable: bool = false,
    open: bool = false,
    generation: u64 = 0,
    capability_generation: u64 = 0,
    first_shown: u64 = 1,
    shown: u64 = 0,
    painted: u64 = 0,
    fn lock(self: *Source) void {
        while (self.guard.cmpxchgWeak(0, 1, .acquire, .monotonic) != null) std.atomic.spinLoopHint();
    }
    fn unlock(self: *Source) void {
        self.guard.store(0, .release);
    }
    fn notify(self: *Source) void {
        if (self.wake) |wake| wake.notify_fn(wake.context) catch {
            self.notification_failed = true;
        };
    }
    /// Binding/unbinding serializes with callbacks. The owner keeps Wake stable until unbound.
    pub fn bind(self: *Source, wake: ?base.WakeOps) void {
        self.lock();
        defer self.unlock();
        self.wake = wake;
        // Only a live rebind retries notification; unbind never hides a failure.
        if (wake != null) {
            self.notification_failed = false;
            self.notify();
        }
    }
    /// Owner refreshes selection from the VM before registration and each probe.
    /// Backend publications cannot restore a deselected display's capability.
    pub fn select(self: *Source, selected: bool) void {
        self.lock();
        defer self.unlock();
        if (self.selected == selected) return;
        if (!selected) {
            if (self.capability_generation == std.math.maxInt(u64)) {
                self.failed = true;
            } else self.capability_generation += 1;
        }
        self.selected = selected;
        self.notify();
    }
    pub fn input(self: *Source) void {
        self.lock();
        defer self.unlock();
        self.notify();
    }
    /// Called only at a backend publication boundary, not by probe.
    pub fn publish(self: *Source, capable: bool, open: bool, shown: u64, painted: u64) void {
        self.lock();
        defer self.unlock();
        if (self.open and !open) {
            if (shown == std.math.maxInt(u64)) {
                self.failed = true;
            } else self.first_shown = shown + 1;
        }
        if (open and !self.open) {
            if (self.generation == std.math.maxInt(u64)) {
                self.failed = true;
                self.notify();
                return;
            }
            self.generation += 1;
        }
        if (self.capable and !capable) {
            if (self.capability_generation == std.math.maxInt(u64)) {
                self.failed = true;
            } else self.capability_generation += 1;
        }
        const changed = self.capable != capable or self.open != open or self.painted != painted;
        self.capable = capable;
        self.open = open;
        self.shown = shown;
        self.painted = painted;
        if (changed) self.notify();
    }
    /// null captures the latest submitted number exactly once; explicit older targets are allowed.
    pub fn register(self: *Source, index: usize, target: ?u64) Error!Registration {
        self.lock();
        defer self.unlock();
        if (self.failed or self.notification_failed) return error.HostFailed;
        if (!self.capable or !self.selected) return error.UnsupportedBackend;
        if (!self.open) return error.NoWindow;
        const number = target orelse self.shown;
        if (number < self.first_shown or number > self.shown) return error.InvalidTarget;
        return .{ .index = index, .generation = self.generation, .target = number, .capability_generation = self.capability_generation };
    }
    pub fn probe(self: *Source, registration: Registration) Error!Result {
        self.lock();
        defer self.unlock();
        if (!registration.active) return error.NotRegistered;
        if (self.failed or self.notification_failed) return error.HostFailed;
        if (!self.open or self.generation != registration.generation) return .released;
        if (!self.capable or !self.selected or self.capability_generation != registration.capability_generation) return .capability_lost;
        return if (self.painted >= registration.target) .painted else .pending;
    }
    pub fn unregister(_: *Source, registration: *Registration) void {
        registration.active = false;
    }
};
