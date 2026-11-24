//! Internal contracts shared by optional word groups. No Forth ABI or OS resources.
const std = @import("std");

pub const Instant = i128;
pub const Error = error{ HostFailed, ResultOutOfRange };
pub const Clock = struct {
    context: ?*anyopaque,
    now_fn: *const fn (?*anyopaque) Error!Instant,

    pub fn now(self: Clock) Error!Instant {
        return self.now_fn(self.context);
    }
};

pub const WakeOutcome = enum { notified, timeout, cancelled };
pub const WakeOps = struct {
    context: ?*anyopaque,
    observe_fn: *const fn (?*anyopaque) u64,
    notify_fn: *const fn (?*anyopaque) Error!void,
    wait_fn: *const fn (?*anyopaque, u64, Deadline, ?*const Cancellation, Clock) Error!WakeOutcome,
};

/// null is an unbounded deadline. A call calculates its deadline only once.
pub const Deadline = struct {
    at: ?Instant,

    pub fn afterMilliseconds(now: Instant, milliseconds: i64) Error!Deadline {
        if (milliseconds < 0) return .{ .at = null };
        const sum = @addWithOverflow(now, @as(Instant, milliseconds) * 1_000_000);
        if (sum[1] != 0) return error.ResultOutOfRange;
        return .{ .at = sum[0] };
    }

    pub fn expired(self: Deadline, now: Instant) bool {
        return if (self.at) |at| now >= at else false;
    }

    /// Ceil to milliseconds without overflowing, bounded for the OS wait call.
    pub fn remainingMilliseconds(self: Deadline, now: Instant, limit: u32) u32 {
        const at = self.at orelse return limit;
        if (now >= at) return 0;
        const difference = @subWithOverflow(at, now);
        if (difference[1] != 0) return limit;
        const remaining = difference[0];
        const whole = @divTrunc(remaining, 1_000_000);
        const rounded = whole + @as(Instant, @intFromBool(@mod(remaining, 1_000_000) != 0));
        return @intCast(@min(rounded, limit));
    }
};

/// Sticky for one operation. Create a fresh token only after its users have joined.
pub const Cancellation = struct {
    requested: std.atomic.Value(bool) = .init(false),
    trace: if (@import("task_trace.zig").enabled) ?*@import("task_trace.zig").Storage else void = if (@import("task_trace.zig").enabled) null else {},

    acceptance: if (@import("task_acceptance.zig").enabled) ?*@import("task_acceptance.zig").Storage else void = if (@import("task_acceptance.zig").enabled) null else {},

    pub inline fn attachTrace(self: *Cancellation, storage: *@import("task_trace.zig").Storage) void {
        if (comptime @import("task_trace.zig").enabled) self.trace = storage;
    }
    pub inline fn stamp(self: *const Cancellation, stage: @import("task_trace.zig").Stage) void {
        if (comptime @import("task_trace.zig").enabled) if (self.trace) |trace| trace.stamp(stage);
        if (comptime @import("task_acceptance.zig").enabled) if (self.acceptance) |probe| {
            probe.stage(stage);
            probe.hold(stage, &self.requested);
        };
    }
    pub fn stampAt(self: *const Cancellation, stage: @import("task_trace.zig").Stage, at: Instant) void {
        if (comptime @import("task_trace.zig").enabled) if (self.trace) |trace| trace.stampAt(stage, at);
    }
    /// Worker checkpoints only; host token inspection must not count as detection.
    pub inline fn checkpoint(self: *const Cancellation) bool {
        const requested = self.isRequested();
        if (requested) self.stamp(.detected);
        return requested;
    }
    pub fn dumpTrace(self: *const Cancellation, event: []const u8) void {
        if (comptime @import("task_trace.zig").enabled) if (self.trace) |trace| trace.dump(@intFromPtr(self), event);
    }

    pub fn request(self: *Cancellation) void {
        self.stamp(.token_before);
        self.requested.store(true, .release);
        self.stamp(.token_after);
    }
    pub fn isRequested(self: *const Cancellation) bool {
        return self.requested.load(.acquire);
    }
};

/// Internal identity. Epoch identifies a table incarnation, not merely a process.
/// The host allocates epochs AND owner IDs without reuse within the process.
/// The future Forth cell representation and cross-process uniqueness are unset.
pub const Handle = struct { epoch: u64, serial: u64 };
pub const ResourceKind = enum { process, task, display_snapshot, frame, pcm };
pub const ResourceError = error{ InvalidHandle, WrongOwner, WrongKind, ResourceFull, IdentityExhausted };

/// Single-owner-thread metadata. Producers must not mutate this table concurrently.
/// Removing metadata does not close the payload: the owner first stops its users.
/// A failed insert never takes ownership of payload; the caller must close it.
pub fn ResourceTable(comptime Payload: type, comptime capacity: usize) type {
    return struct {
        const Self = @This();
        const Entry = struct { serial: u64, owner: u64, kind: ResourceKind, payload: Payload };
        epoch: u64,
        next_serial: u64 = 1,
        entries: [capacity]?Entry = @splat(null),

        pub fn init(epoch: u64) ResourceError!Self {
            if (epoch == 0) return error.InvalidHandle;
            return .{ .epoch = epoch };
        }
        pub fn insert(self: *Self, owner: u64, kind: ResourceKind, payload: Payload) ResourceError!Handle {
            if (owner == 0) return error.WrongOwner;
            if (self.next_serial == 0) return error.IdentityExhausted;
            for (&self.entries) |*slot| if (slot.* == null) {
                const serial = self.next_serial;
                // Exhaust rather than wrapping an old identity into validity.
                self.next_serial = if (serial == std.math.maxInt(u64)) 0 else serial + 1;
                slot.* = .{ .serial = serial, .owner = owner, .kind = kind, .payload = payload };
                return .{ .epoch = self.epoch, .serial = serial };
            };
            return error.ResourceFull;
        }
        fn entry(self: *Self, handle: Handle, owner: u64, kind: ResourceKind) ResourceError!*Entry {
            if (handle.epoch != self.epoch or handle.serial == 0) return error.InvalidHandle;
            for (&self.entries) |*slot| if (slot.*) |*item| {
                if (item.serial != handle.serial) continue;
                if (item.kind != kind) return error.WrongKind;
                if (item.owner != owner) return error.WrongOwner;
                return item;
            };
            return error.InvalidHandle;
        }
        pub fn get(self: *Self, handle: Handle, owner: u64, kind: ResourceKind) ResourceError!*Payload {
            return &(try self.entry(handle, owner, kind)).payload;
        }
        pub fn remove(self: *Self, handle: Handle, owner: u64, kind: ResourceKind) ResourceError!Payload {
            const found = try self.entry(handle, owner, kind);
            const payload = found.payload;
            for (&self.entries) |*slot| if (slot.*) |item| {
                if (item.serial == handle.serial) {
                    slot.* = null;
                    return payload;
                }
            };
            unreachable;
        }
        pub fn count(self: *const Self) usize {
            var total: usize = 0;
            for (self.entries) |slot| if (slot != null) {
                total += 1;
            };
            return total;
        }
    };
}

/// Host-thread scope ownership, separate from installing any signal handlers.
/// Only the same owner may nest; leaving must be LIFO. Tokens are never reused.
pub fn SignalOwnership(comptime max_depth: usize) type {
    return struct {
        const Self = @This();
        pub const Scope = struct { owner: u64, serial: u64 };
        pub const ScopeError = error{ WrongOwner, ScopeFull, InvalidScope, IdentityExhausted };
        stack: [max_depth]Scope = undefined,
        depth: usize = 0,
        next_serial: u64 = 1,

        pub fn enter(self: *Self, owner: u64) ScopeError!Scope {
            if (owner == 0 or (self.depth != 0 and self.stack[0].owner != owner)) return error.WrongOwner;
            if (self.depth == max_depth) return error.ScopeFull;
            if (self.next_serial == 0) return error.IdentityExhausted;
            const scope = Scope{ .owner = owner, .serial = self.next_serial };
            self.next_serial = if (scope.serial == std.math.maxInt(u64)) 0 else scope.serial + 1;
            self.stack[self.depth] = scope;
            self.depth += 1;
            return scope;
        }
        pub fn leave(self: *Self, scope: Scope) ScopeError!void {
            if (self.depth == 0) return error.InvalidScope;
            const current = self.stack[self.depth - 1];
            if (scope.owner != current.owner or scope.serial != current.serial) return error.InvalidScope;
            self.depth -= 1;
        }
    };
}
