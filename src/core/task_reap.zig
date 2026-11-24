//! Serialized host lifecycle. No process/audio/display ownership or waits.
const base = @import("runtime_base.zig");
const Host = @import("task_schedule_host.zig").Host;
const queue = @import("task_queue.zig");
const permissions = @import("task_permissions.zig");
pub const Cause = enum { owner_exit, bye, restore };
pub const Progress = enum { pending, collected, stop_unconfirmed };
pub const Disposal = struct {
    context: ?*anyopaque = null,
    /// Detach this scope's WAIT registrations and retire pending result copies.
    /// Drop ledger refs only after their consumers have stopped. Optional when
    /// the embedding has no registrations/copies; called once after invalidation.
    retire: ?*const fn (?*anyopaque, ?u64) void = null,
    /// Called after handback and zero internal refs, exactly once per entry.
    /// Receives sealed diagnostics/result before destroying buffers/Execution.
    /// Must not reenter Host or retain borrowed pointers. VM destruction
    /// finishes on the worker before collection; queued cleanup releases admission.
    destroy: *const fn (?*anyopaque, base.Handle, *queue.Job, queue.Result, ?Host.Publication) void,
};
pub const Reaper = struct {
    host: *Host,
    disposal: Disposal,
    owner: ?u64 = null, // null = complete host shutdown, including worker join
    cause: Cause = .owner_exit,
    begun: bool = false,
    owner_deadline: ?base.Deadline = null,

    fn matches(self: *const Reaper, owner: u64) bool {
        return self.owner == null or self.owner.? == owner;
    }
    /// Busy refuses restoration without invalidating IDs or cancelling work.
    /// Ended owners/hosts remain closed; use a fresh lifecycle for a new owner.
    pub fn begin(self: *Reaper, cause: Cause) !void {
        try permissions.requireHostSubmission();
        if (cause == .restore) {
            try self.requireRestoreIdle();
            return;
        }
        if (self.begun) return;
        const started = try self.host.queue.clock.now();
        const deadline = try base.Deadline.afterMilliseconds(started, 100);
        if (self.owner) |owner| {
            try self.host.endOwner(owner);
            self.owner_deadline = deadline;
        } else {
            try self.host.beginShutdown(started);
        }
        self.cause = cause;
        self.begun = true;
        if (self.disposal.retire) |retire| retire(self.disposal.context, self.owner);
    }
    pub fn requireRestoreIdle(self: *Reaper) !void {
        try permissions.requireHostSubmission();
        try self.host.poll();
        for (self.host.entries) |slot| if (slot) |entry| {
            const record = try self.host.ledger.inspect(entry.id, entry.owner);
            if (!record.state.terminal() or record.execution_ref or record.internal_refs != 0 or self.host.queue.isCleaning(entry.job)) return error.Busy;
        };
    }
    /// One bounded sweep. Caller waits on the common Wake up to deadline and
    /// calls again; late completions remain reclaimable after timeout.
    pub fn poll(self: *Reaper) !Progress {
        try permissions.requireHostSubmission();
        if (!self.begun) return error.InvalidTransition;
        try self.host.poll();
        var remaining = false;
        for (&self.host.entries) |*slot| if (slot.*) |entry| {
            if (!self.matches(entry.owner)) continue;
            const record = try self.host.ledger.inspect(entry.id, entry.owner);
            if (!record.state.terminal() or record.execution_ref or record.internal_refs != 0 or self.host.queue.isCleaning(entry.job)) {
                remaining = true;
                continue;
            }
            // Metadata removal proves reference exhaustion. No fallible work
            // after removal; callback may free Job and publication allocations.
            try self.host.collect(entry.id, entry.owner);
            self.disposal.destroy(self.disposal.context, entry.id, entry.job, entry.job.terminal.?, entry.publication);
        };
        const status = if (self.owner == null) try self.host.shutdownStatus() else Host.Shutdown.joined;
        if (!remaining and status == .joined) return .collected;
        if (status == .resources_active) return .stop_unconfirmed;
        // Terminal jobs retained by WAIT/result copies also remain resources.
        const deadline = if (self.owner != null) self.owner_deadline else self.host.shutdown_deadline;
        if (remaining) if (deadline) |limit| {
            if (limit.expired(try self.host.queue.clock.now())) return .stop_unconfirmed;
        };
        return .pending;
    }
    /// Finite host wait; does not pump or await independent host resources.
    pub fn finish(self: *Reaper, cause: Cause) !Progress {
        try self.begin(cause);
        if (cause == .restore) return .collected;
        while (true) {
            const ops = self.host.queue.common;
            const observed = ops.observe_fn(ops.context);
            const progress = try self.poll();
            if (progress != .pending) return progress;
            const now = try self.host.queue.clock.now();
            const retry = try base.Deadline.afterMilliseconds(now, 1);
            const next = retry;
            _ = try ops.wait_fn(ops.context, observed, next, null, self.host.queue.clock);
        }
    }
};
