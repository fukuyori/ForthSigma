//! Host-thread-only task metadata. Never pass this ledger or its records to workers.
const base = @import("runtime_base.zig");
pub const Handle = base.Handle;
pub const Error = base.ResourceError || error{ InvalidTransition, ConflictingTerminal, ReferencesRemain, WorkerOccupied, ReferenceOverflow };
pub const State = enum {
    created,
    queued,
    running,
    succeeded,
    failed,
    cancelled,
    pub fn terminal(self: State) bool {
        return self == .succeeded or self == .failed or self == .cancelled;
    }
};
pub const Record = struct {
    state: State = .created,
    cancel_requested: bool = false,
    external_valid: bool = false,
    execution_ref: bool = false,
    // Includes queue, completion, WAIT, copy and cleanup ownership, not execution_ref.
    internal_refs: usize = 0,
    stop_unconfirmed: bool = false,
};
pub const DefaultLedger = Ledger(16);

pub fn Ledger(comptime capacity: usize) type {
    return LedgerWithConcurrency(capacity, 1);
}

pub fn LedgerWithConcurrency(comptime capacity: usize, comptime workers: usize) type {
    if (workers == 0) @compileError("task ledger requires at least one worker");
    return struct {
        const Self = @This();
        const Table = base.ResourceTable(Record, capacity);
        /// Direct mutation is for invariant/identity fault injection in tests only.
        table_for_testing: Table,

        pub fn init(epoch: u64) Error!Self {
            return .{ .table_for_testing = try Table.init(epoch) };
        }
        pub fn count(self: *const Self) usize {
            return self.table_for_testing.count();
        }
        /// Host must stop submissions for an ending owner before calling endOwner.
        /// Priority: invalid owner, then ResourceTable exhaustion/full.
        pub fn register(self: *Self, owner: u64) Error!Handle {
            if (owner == 0) return error.WrongOwner;
            return self.table_for_testing.insert(owner, .task, .{});
        }
        fn record(self: *Self, id: Handle, owner: u64) Error!*Record {
            return self.table_for_testing.get(id, owner, .task);
        }
        /// Value copy prevents callers mutating a terminal state through a pointer.
        pub fn lookup(self: *Self, id: Handle, owner: u64) Error!Record {
            const r = try self.record(id, owner);
            if (!r.external_valid) return error.InvalidHandle;
            return r.*;
        }
        /// Internal host completion/cleanup path, including RELEASEd records.
        pub fn inspect(self: *Self, id: Handle, owner: u64) Error!Record {
            return (try self.record(id, owner)).*;
        }
        /// Call only after the queue reservation has succeeded; publication boundary.
        pub fn publish(self: *Self, id: Handle, owner: u64) Error!void {
            const r = try self.record(id, owner);
            if (r.state != .created) return error.InvalidTransition;
            r.state = .queued;
            r.external_valid = true;
        }
        /// Host has observed exclusive worker acquisition of the queued item.
        pub fn start(self: *Self, id: Handle, owner: u64) Error!void {
            const r = try self.record(id, owner);
            if (r.state != .queued) return error.InvalidTransition;
            try self.checkWorkerAvailable();
            r.state = .running;
            r.execution_ref = true;
        }
        pub fn cancel(self: *Self, id: Handle, owner: u64) Error!void {
            _ = try self.lookup(id, owner);
            const r = try self.record(id, owner);
            if (!r.state.terminal()) r.cancel_requested = true;
        }
        /// Caller forwards the latched request to the task's atomic token and wakes it.
        pub fn release(self: *Self, id: Handle, owner: u64) Error!void {
            _ = try self.lookup(id, owner);
            invalidate(try self.record(id, owner));
        }
        fn invalidate(r: *Record) void {
            r.external_valid = false;
            if (!r.state.terminal()) r.cancel_requested = true;
        }
        /// Accept only a sealed execution result. No resource ownership is dropped here.
        /// queued cancellation requires the caller's exclusive queue removal proof.
        pub fn finish(self: *Self, id: Handle, owner: u64, outcome: State) Error!bool {
            const r = try self.record(id, owner);
            if (!outcome.terminal()) return error.InvalidTransition;
            if (r.state.terminal()) {
                if (r.state != outcome) return error.ConflictingTerminal;
                return false;
            }
            if (r.state != .running and !(r.state == .queued and outcome == .cancelled)) return error.InvalidTransition;
            if (r.state == .queued and !r.cancel_requested) return error.InvalidTransition;
            r.state = outcome;
            return true;
        }
        pub const QueueFailure = enum { queue_expired, clock_failed };
        /// Host has exclusively removed the queued item and sealed a failure.
        /// Mirrors queue Result.reason; never invents a cancellation request.
        pub fn failQueued(self: *Self, id: Handle, owner: u64, reason: QueueFailure) Error!bool {
            _ = reason;
            const r = try self.record(id, owner);
            if (r.state == .failed) return false;
            if (r.state.terminal()) return error.ConflictingTerminal;
            if (r.state != .queued) return error.InvalidTransition;
            r.state = .failed;
            return true;
        }
        /// Only after physical return/join or equivalent ownership handoff is confirmed.
        pub fn executionStopped(self: *Self, id: Handle, owner: u64) Error!void {
            const r = try self.record(id, owner);
            if (!r.execution_ref or !r.state.terminal()) return error.InvalidTransition;
            r.execution_ref = false;
            r.stop_unconfirmed = false;
        }
        pub fn retain(self: *Self, id: Handle, owner: u64) Error!void {
            const r = try self.record(id, owner);
            if (r.internal_refs == @import("std").math.maxInt(usize)) return error.ReferenceOverflow;
            r.internal_refs += 1;
        }
        pub fn drop(self: *Self, id: Handle, owner: u64) Error!void {
            const r = try self.record(id, owner);
            if (r.internal_refs == 0) return error.InvalidTransition;
            r.internal_refs -= 1;
        }
        pub fn markStopUnconfirmed(self: *Self, id: Handle, owner: u64) Error!void {
            const r = try self.record(id, owner);
            if (!r.execution_ref) return error.InvalidTransition;
            r.stop_unconfirmed = true;
        }
        pub fn checkWorkerAvailable(self: *const Self) Error!void {
            var occupied: usize = 0;
            for (self.table_for_testing.entries) |slot| if (slot) |entry| {
                if (entry.kind != .task) continue;
                if (entry.payload.stop_unconfirmed) return error.WorkerOccupied;
                if (entry.payload.execution_ref) occupied += 1;
            };
            if (occupied >= workers) return error.WorkerOccupied;
        }
        /// Returns metadata only. Caller owns destruction of all associated resources.
        pub fn collect(self: *Self, id: Handle, owner: u64) Error!Record {
            const r = try self.record(id, owner);
            if (r.external_valid or r.execution_ref or r.internal_refs != 0) return error.ReferencesRemain;
            if (!r.state.terminal() and r.state != .created) return error.InvalidTransition;
            return self.table_for_testing.remove(id, owner, .task);
        }
        /// Invalidates all owned IDs, including already RELEASEd records. Does not
        /// invent terminal results, remove queue items, drop refs or destroy resources.
        pub fn endOwner(self: *Self, owner: u64) Error!usize {
            if (owner == 0) return error.WrongOwner;
            var affected: usize = 0;
            for (&self.table_for_testing.entries) |*slot| if (slot.*) |*entry| {
                if (entry.kind == .task and entry.owner == owner) {
                    invalidate(&entry.payload);
                    affected += 1;
                }
            };
            return affected;
        }
    };
}
