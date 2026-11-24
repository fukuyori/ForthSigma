//! Host-owned bounded registration. Sources retain storage until detach; producers
//! publish persistent state then notify the one common Wake, never this stack.
const base = @import("runtime_base.zig");
pub const capacity = 64;
pub const Kind = enum { input, io, task, clock, paint };
pub const Reason = enum { input, readable, writable, eof, failure, closed, succeeded, failed, cancelled, released, deadline, painted, capability_lost };
pub const State = struct { reason: ?Reason = null, detail: i128 = 0, mask: u16 = 0, again: bool = false, interrupted: bool = false, next: base.Deadline = .{ .at = null } };
pub const Source = struct {
    context: ?*anyopaque,
    // Validation must not acquire resources. Attach failure rolls itself back.
    validate: *const fn (?*anyopaque) base.Error!void,
    attach: *const fn (?*anyopaque) base.Error!void,
    prepare: ?*const fn (?*anyopaque) base.Error!void = null,
    probe: *const fn (?*anyopaque) base.Error!State,
    detach: *const fn (?*anyopaque) void,
};
pub const Target = struct { kind: Kind, identity: base.Handle, source: ?Source = null, at: ?base.Instant = null };
pub const Item = struct { index: usize, kind: Kind, identity: base.Handle, reason: Reason, mask: u16 = 0, detail: i128 };
pub const Result = struct {
    items: [capacity]Item = undefined,
    count: usize = 0,
    interrupted: bool = false,
    cancelled: bool = false,
    expired: bool = false,
    failed: bool = false,
    again: bool = false,
    next: base.Deadline = .{ .at = null },
    pub fn finished(self: Result) bool {
        return self.count != 0 or self.cancelled or self.interrupted or self.expired or self.failed;
    }
};
pub fn earlier(a: base.Deadline, b: base.Deadline) base.Deadline {
    return if (b.at != null and (a.at == null or b.at.? < a.at.?)) b else a;
}
pub const Registration = struct {
    targets: [capacity]Target = undefined,
    count: usize = 0,
    active: bool = false,
    observed: u64 = 0,
    generation: u64 = 0,
    wake: base.WakeOps,
    clock: base.Clock,
    deadline: base.Deadline,
    cancellation: ?*base.Cancellation = null,

    pub fn open(self: *Registration, targets: []const Target) base.Error!void {
        if (self.active or targets.len == 0 or targets.len > capacity) return error.ResultOutOfRange;
        for (targets) |target| {
            if (target.kind == .clock) {
                if (target.at == null or target.source != null) return error.HostFailed;
            } else {
                if (target.identity.epoch == 0 or target.identity.serial == 0) return error.HostFailed;
                const source = target.source orelse return error.HostFailed;
                try source.validate(source.context);
            }
        }
        if (self.generation == @import("std").math.maxInt(u64)) return error.ResultOutOfRange;
        self.generation += 1;
        self.observed = self.wake.observe_fn(self.wake.context);
        self.count = 0;
        errdefer self.close();
        for (targets) |target| {
            if (target.source) |source| try source.attach(source.context);
            self.targets[self.count] = target;
            self.count += 1;
        }
        self.active = true;
    }
    pub fn close(self: *Registration) void {
        while (self.count != 0) {
            self.count -= 1;
            if (self.targets[self.count].source) |source| source.detach(source.context);
        }
        self.active = false;
    }
    /// Call once per host turn, including after every native wake. Observe BEFORE
    /// probing; do not refresh observed between this call and native wait.
    pub fn poll(self: *Registration) Result {
        var result = Result{ .next = self.deadline };
        if (!self.active) {
            result.failed = true;
            return result;
        }
        self.observed = self.wake.observe_fn(self.wake.context);
        // Acquire all task publications/queue expiry before probing any source.
        for (self.targets[0..self.count]) |target| if (target.source) |source| {
            if (source.prepare) |prepare| prepare(source.context) catch {
                result.failed = true;
            };
        };
        for (self.targets[0..self.count], 0..) |target, index| {
            if (target.source) |source| {
                const state = source.probe(source.context) catch {
                    result.failed = true;
                    continue;
                };
                result.again = result.again or state.again;
                result.interrupted = result.interrupted or state.interrupted;
                result.next = earlier(result.next, state.next);
                if (state.reason) |reason| {
                    result.items[result.count] = .{ .index = index, .kind = target.kind, .identity = target.identity, .reason = reason, .mask = state.mask, .detail = state.detail };
                    result.count += 1;
                }
            }
        }
        if (self.cancellation) |token| result.cancelled = token.isRequested();
        const now = self.clock.now() catch {
            result.failed = true;
            return result;
        };
        for (self.targets[0..self.count], 0..) |target, index| if (target.kind == .clock) {
            result.next = earlier(result.next, .{ .at = target.at });
            if (now >= target.at.?) {
                result.items[result.count] = .{ .index = index, .kind = .clock, .identity = target.identity, .reason = .deadline, .detail = target.at.? };
                result.count += 1;
            }
        };
        result.expired = self.deadline.expired(now);
        return result;
    }
    pub fn requestCancellation(self: *Registration) base.Error!void {
        const token = self.cancellation orelse return error.HostFailed;
        token.request();
        try self.wake.notify_fn(self.wake.context);
    }
};
