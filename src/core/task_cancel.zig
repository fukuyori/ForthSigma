//! Host-only association of ledger identity and a pinned queue job.
//! The worker sees only Job.cancellation, never the ledger or this binding.
const ledger = @import("task_ledger.zig");
const queue = @import("task_queue.zig");
pub const Binding = struct {
    id: ledger.Handle,
    owner: u64,
    job: *queue.Job,

    pub fn cancel(self: Binding, table: anytype, work: anytype) !void {
        try table.cancel(self.id, self.owner);
        work.cancel(self.job);
    }
    pub fn release(self: Binding, table: anytype, work: anytype) !void {
        try table.release(self.id, self.owner);
        work.release(self.job);
    }
    /// Call on every host sweep, including after lost/coalesced notifications.
    /// Host metadata follows exclusive queue acquisition, not a guessed request.
    pub fn poll(self: Binding, table: anytype, work: anytype) !?queue.Result {
        const result = work.poll(self.job);
        if (self.job.cancellation.isRequested()) try table.latchCancellation(self.id, self.owner);
        var record = try table.inspect(self.id, self.owner);
        if (record.state == .queued and self.job.acquired.load(.acquire)) {
            try table.observeStart(self.id, self.owner);
            record = try table.inspect(self.id, self.owner);
        }
        const sealed = result orelse return null;
        if (record.state.terminal()) return sealed;
        if (record.state == .queued) {
            switch (sealed.reason) {
                .queue_expired => {
                    _ = try table.failQueued(self.id, self.owner, .queue_expired);
                    return sealed;
                },
                .clock_failed, .worker_failed => {
                    _ = try table.failQueued(self.id, self.owner, .clock_failed);
                    return sealed;
                },
                else => {},
            }
            if (sealed.kind == .cancelled and record.cancel_requested) {
                _ = try table.finish(self.id, self.owner, .cancelled);
                return sealed;
            }
            try table.observeStart(self.id, self.owner);
        }
        _ = try table.finish(self.id, self.owner, switch (sealed.kind) {
            .succeeded => .succeeded,
            .failed => .failed,
            .cancelled => .cancelled,
        });
        try table.executionStopped(self.id, self.owner);
        return sealed;
    }
};
