//! Host-only binding of schedule decisions to the real queue and ledger.
//! Pin this object, queue, jobs and runner contexts until collection/join.
//! One serialized owner thread; never call host methods from runner/cleanup.
const std = @import("std");
const base = @import("runtime_base.zig");
const schedule = @import("task_schedule.zig");
const ledger_mod = @import("task_ledger.zig");
const queue_mod = @import("task_queue.zig");
const permissions = @import("task_permissions.zig");

pub const Host = struct {
    pub const StopDiagnostic = struct {
        id: base.Handle,
        owner: u64,
        requested_at: base.Instant,
        stop_deadline: base.Instant,
        collection_deadline: base.Instant,
        stop_exceeded: bool = false,
        collection_exceeded: bool = false,
        stopped: bool = false,
        last_state: ledger_mod.State = .queued,
        cancel_requested: bool = true,
        // No worker instruction sampling; VM retirement belongs to collection.
        location: enum { runner_or_cleanup, host_collection } = .runner_or_cleanup,
    };
    /// Borrow sealed, task-owned bytes and a separately reserved host copy.
    /// Both slices stay pinned until collect; diagnostics follow result bytes.
    pub const Publication = struct {
        result: []const u8,
        result_copy: []u8,
        diagnostic: []const u8 = &.{},
        diagnostic_copy: []u8 = &.{},
        // Worker output, primary, secondary and writer failure: four independent
        // 1365 buffers. Do not concatenate them outside the per-turn copy budget.
        extra_diagnostics: [3][]const u8 = @splat(&.{}),
        extra_diagnostic_copies: [3][]u8 = @splat(&.{}),
        cursor: usize = 0,
        fn sources(self: Publication) [5][]const u8 {
            return .{ self.result, self.diagnostic, self.extra_diagnostics[0], self.extra_diagnostics[1], self.extra_diagnostics[2] };
        }
        fn destinations(self: Publication) [5][]u8 {
            return .{ self.result_copy, self.diagnostic_copy, self.extra_diagnostic_copies[0], self.extra_diagnostic_copies[1], self.extra_diagnostic_copies[2] };
        }
        fn length(self: Publication) usize {
            var size: usize = 0;
            for (self.sources()) |source| size += source.len;
            return size;
        }
    };
    const Entry = struct {
        id: base.Handle,
        owner: u64,
        job: *queue_mod.Job,
        kind: schedule.Kind,
        stream: u64,
        generation: u64,
        current_generation: u64,
        applied: bool = false,
        publication: ?Publication = null,
        stop: ?StopDiagnostic = null,
    };
    copy_bytes: usize = schedule.Limits.copy_bytes,
    queue: *queue_mod.DefaultQueue,
    ledger: ledger_mod.DefaultLedger,
    entries: [16]?Entry = @splat(null),
    // Monotonic host-wide stamps avoid reusing a stream's generation after collect.
    generation: u64 = 0,
    accepting: bool = true,
    shutdown_deadline: ?base.Deadline = null,
    ended_owners: [16]u64 = @splat(0),

    /// Owner identities are never reused. Exhausting this tombstone set closes
    /// admission rather than allowing an ended owner to submit again.
    pub fn endOwner(self: *Host, owner: u64) !void {
        try permissions.requireHostSubmission();
        if (owner == 0) return error.WrongOwner;
        for (self.ended_owners) |ended| if (ended == owner) return;
        for (&self.ended_owners) |*ended| if (ended.* == 0) {
            ended.* = owner;
            break;
        };
        var recorded = false;
        for (self.ended_owners) |ended| recorded = recorded or ended == owner;
        if (!recorded) self.accepting = false;
        const requested_at = try self.queue.clock.now();
        _ = try self.ledger.endOwner(owner);
        // Remove waiting work first; a dequeue race becomes a token request.
        const view = self.queue.view();
        for (view.waiting[0..view.count]) |job| {
            const entry = try self.byJob(job);
            if (entry.owner == owner) self.queue.release(job);
        }
        for (self.entries) |slot| if (slot) |entry| {
            if (entry.owner == owner) {
                try self.requestCancel(entry.id, owner, requested_at);
                self.queue.release(entry.job);
            }
        };
    }

    /// RELEASE retains the internal entry through physical handback.
    pub fn release(self: *Host, id: base.Handle, owner: u64) !void {
        try permissions.requireHostSubmission();
        const entry = try self.find(id, owner);
        try self.ledger.release(id, owner);
        self.queue.release(entry.job);
    }

    pub fn init(queue: *queue_mod.DefaultQueue, epoch: u64) !Host {
        return .{ .queue = queue, .ledger = try ledger_mod.DefaultLedger.init(epoch) };
    }
    fn find(self: *Host, id: base.Handle, owner: u64) !*Entry {
        _ = try self.ledger.lookup(id, owner);
        return self.findInternal(id, owner);
    }
    fn findInternal(self: *Host, id: base.Handle, owner: u64) !*Entry {
        _ = try self.ledger.inspect(id, owner);
        for (&self.entries) |*slot| if (slot.*) |*entry| {
            if (std.meta.eql(entry.id, id)) return entry;
        };
        return error.InvalidHandle;
    }
    fn byJob(self: *Host, job: *queue_mod.Job) !*Entry {
        for (&self.entries) |*slot| if (slot.*) |*entry| {
            if (entry.job == job) return entry;
        };
        return error.InvalidJob; // queue is exclusively submitted through this Host
    }
    pub const Request = struct {
        owner: u64,
        kind: schedule.Kind,
        stream: u64,
        input: schedule.InputSource,
        job: *queue_mod.Job,
        milliseconds: i64,
    };
    /// Input/job resources must already be reserved by the caller. Success pins
    /// job until collect; failure leaves resources with caller and old work intact.
    /// Runner still creates a fresh VM and performs task_job permission checks.
    pub fn submit(self: *Host, request: Request) !base.Handle {
        try permissions.requireHostSubmission();
        if (request.owner == 0) return error.WrongOwner;
        const requested_at = try self.queue.clock.now();
        _ = try base.Deadline.afterMilliseconds(requested_at, 100);
        if (!self.accepting) return error.Closed;
        for (self.ended_owners) |owner| if (owner == request.owner) return error.Closed;
        const view = self.queue.view();
        var waiting: [4]schedule.Waiting = undefined;
        for (view.waiting[0..view.count], 0..) |job, i| {
            const e = try self.byJob(job);
            waiting[i] = .{ .id = e.id.serial, .kind = e.kind, .owner = e.owner, .stream = e.stream, .deadline = 0 };
        }
        const running: ?schedule.Running = if (view.active) |job| blk: {
            const e = try self.byJob(job);
            break :blk .{ .id = e.id.serial, .kind = e.kind, .stream = e.stream, .owner = e.owner };
        } else null;
        const decision = try schedule.admit(waiting[0..view.count], .{
            .kind = request.kind,
            .stream = request.stream,
            .current_generation = self.generation,
            .running = running,
        }, &self.ledger, request.owner, request.input);
        const old: ?*queue_mod.Job = switch (decision.placement) {
            .forbidden => return error.Denied,
            .backpressure => return error.ResourceFull,
            .append => null,
            .replace => |replacement| view.waiting[replacement.index],
        };
        // No fallible work after queue acceptance. Publish a private created
        // record only after the exclusive queue insertion/replacement succeeds.
        const id = try self.ledger.register(request.owner);
        errdefer _ = self.ledger.collect(id, request.owner) catch unreachable;
        try self.queue.submitReplacing(request.job, request.milliseconds, old);
        self.ledger.publish(id, request.owner) catch unreachable;
        if (decision.generation) |generation| {
            self.generation = generation;
            for (&self.entries) |*slot| if (slot.*) |*entry| {
                if (entry.owner == request.owner and entry.kind == request.kind and entry.stream == request.stream) {
                    entry.current_generation = generation;
                    self.requestCancel(entry.id, entry.owner, requested_at) catch unreachable;
                }
            };
        }
        for (&self.entries) |*slot| if (slot.* == null) {
            slot.* = .{ .id = id, .owner = request.owner, .job = request.job, .kind = request.kind, .stream = request.stream, .generation = decision.generation orelse 0, .current_generation = decision.generation orelse 0 };
            return id;
        };
        unreachable;
    }
    /// Reconcile sealed results before recording the next physical acquisition.
    /// Queue acquire-load proves execution no longer uses job/input/token.
    /// Independent VM retirement can remain until queue.isCleaning clears.
    pub fn poll(self: *Host) !void {
        try permissions.requireHostSubmission();
        for (&self.entries) |*slot| if (slot.*) |*entry| {
            const result = self.queue.poll(entry.job) orelse continue;
            const record = try self.ledger.inspect(entry.id, entry.owner);
            if (record.state.terminal()) continue;
            if (self.queue.wasAcquired(entry.job)) {
                // Other completed jobs may still hold their ledger execution ref.
                // Their physical handback is reconciled by the first pass below.
                continue;
            }
            switch (result.reason) {
                .queue_expired => _ = try self.ledger.failQueued(entry.id, entry.owner, .queue_expired),
                .clock_failed => _ = try self.ledger.failQueued(entry.id, entry.owner, .clock_failed),
                .worker_failed => _ = try self.ledger.failQueued(entry.id, entry.owner, .worker_failed),
                else => {
                    try self.ledger.latchCancellation(entry.id, entry.owner);
                    _ = try self.ledger.finish(entry.id, entry.owner, .cancelled);
                },
            }
        };
        // Stop existing execution refs first (at most one).
        for (&self.entries) |*slot| if (slot.*) |*entry| {
            const record = try self.ledger.inspect(entry.id, entry.owner);
            if (record.execution_ref) {
                // A later job's sealed result proves an earlier acquisition has
                // returned, even if its first poll just missed publication.
                _ = self.queue.poll(entry.job);
                if (entry.job.terminal != null) try self.finishAcquired(entry);
            }
        };
        // Completed-but-never-observed acquisitions, then the still-running job.
        for (&self.entries) |*slot| if (slot.*) |*entry| {
            const record = try self.ledger.inspect(entry.id, entry.owner);
            if (record.state == .queued and entry.job.terminal != null and self.queue.wasAcquired(entry.job)) {
                self.ledger.checkWorkerAvailable() catch continue;
                try self.ledger.start(entry.id, entry.owner);
                try self.finishAcquired(entry);
            }
        };
        if (self.queue.view().active) |job| {
            const entry = try self.byJob(job);
            const record = try self.ledger.inspect(entry.id, entry.owner);
            if (record.state == .queued) {
                if (self.ledger.checkWorkerAvailable()) |_| {
                    try self.ledger.start(entry.id, entry.owner);
                } else |_| {}
            }
        }
        try self.checkStopDeadlines(try self.queue.clock.now());
    }
    /// Timestamp is API-entry time in the queue clock domain, not token-set time.
    /// Repeated requests retain the original deadlines. No allocation or VM access.
    pub fn requestCancel(self: *Host, id: base.Handle, owner: u64, requested_at: base.Instant) !void {
        try permissions.requireHostSubmission();
        const entry = try self.findInternal(id, owner);
        entry.job.cancellation.stampAt(.api_entry, requested_at);
        entry.job.cancellation.stamp(.request);
        if (entry.stop == null) {
            const stop = try base.Deadline.afterMilliseconds(requested_at, 10);
            const collection = try base.Deadline.afterMilliseconds(requested_at, 100);
            entry.stop = .{ .id = id, .owner = owner, .requested_at = requested_at, .stop_deadline = stop.at.?, .collection_deadline = collection.at.? };
        }
        try self.ledger.latchCancellation(id, owner);
        self.queue.cancel(entry.job);
    }
    fn checkStopDeadlines(self: *Host, now: base.Instant) !void {
        for (&self.entries) |*slot| if (slot.*) |*entry| {
            if (entry.stop) |*diagnostic| {
                const record = try self.ledger.inspect(entry.id, entry.owner);
                diagnostic.last_state = record.state;
                diagnostic.stopped = record.state.terminal() and !record.execution_ref;
                if (diagnostic.stopped) diagnostic.location = .host_collection;
                if (!diagnostic.stopped and now > diagnostic.stop_deadline) {
                    if (!diagnostic.stop_exceeded) {
                        entry.job.cancellation.stampAt(.deadline_check, now);
                        entry.job.cancellation.stamp(.deadline);
                        entry.job.cancellation.dumpTrace("deadline");
                    }
                    diagnostic.stop_exceeded = true;
                    if (record.execution_ref and self.queue.markUnresponsiveFor(entry.job))
                        try self.ledger.markStopUnconfirmed(entry.id, entry.owner);
                }
                if (now > diagnostic.collection_deadline) diagnostic.collection_exceeded = true;
            }
        };
    }
    /// Internal inspection survives RELEASE. Kept until explicit collection.
    pub fn stopDiagnostic(self: *Host, id: base.Handle, owner: u64) !?StopDiagnostic {
        _ = try self.ledger.inspect(id, owner);
        for (self.entries) |slot| if (slot) |entry| {
            if (std.meta.eql(entry.id, id)) return entry.stop;
        };
        return error.InvalidHandle;
    }
    /// Invalidate external IDs but retain every internal entry and borrowed object.
    pub fn beginShutdown(self: *Host, requested_at: base.Instant) !void {
        try permissions.requireHostSubmission();
        self.accepting = false;
        if (self.shutdown_deadline == null)
            self.shutdown_deadline = try base.Deadline.afterMilliseconds(requested_at, 100);
        const view = self.queue.view();
        for (view.waiting[0..view.count]) |job| self.queue.release(job);
        for (self.entries) |slot| if (slot) |entry| {
            try self.requestCancel(entry.id, entry.owner, requested_at);
            try self.endOwner(entry.owner);
        };
        self.queue.stop();
    }
    pub const Shutdown = enum { waiting, joined, resources_active };
    /// Caller may destroy queue/storage only after joined AND collecting entries.
    /// resources_active requires process termination through host_task_stop.abort.
    pub fn shutdownStatus(self: *Host) !Shutdown {
        try self.poll();
        if (self.queue.joinIfStopped()) {
            // Worker can publish between the first sweep and the exit load.
            try self.poll();
            return .joined;
        }
        if (self.shutdown_deadline) |deadline| {
            if (deadline.expired(try self.queue.clock.now())) {
                for (self.entries) |slot| if (slot) |entry| {
                    const record = try self.ledger.inspect(entry.id, entry.owner);
                    if (record.execution_ref or !record.state.terminal() or self.queue.isCleaning(entry.job)) return .resources_active;
                };
            }
        }
        return .waiting;
    }
    fn finishAcquired(self: *Host, entry: *Entry) !void {
        const result = entry.job.terminal.?;
        _ = try self.ledger.finish(entry.id, entry.owner, switch (result.kind) {
            .succeeded => .succeeded,
            .failed => .failed,
            .cancelled => .cancelled,
        });
        try self.ledger.executionStopped(entry.id, entry.owner);
        entry.job.cancellation.stamp(.host_stopped);
        entry.job.cancellation.dumpTrace("reconciled");
    }
    /// Sole application boundary. Late success remains success in the ledger,
    /// but superseded results never reach the host consumer. At most once.
    pub fn takeResult(self: *Host, id: base.Handle, owner: u64) !?queue_mod.Result {
        try self.poll();
        const entry = try self.find(id, owner);
        const result = entry.job.terminal orelse return null;
        if (!(try self.ledger.inspect(id, owner)).state.terminal()) return null;
        if (!schedule.resultIsCurrent(entry.generation, entry.current_generation) or entry.applied) return null;
        if (entry.publication) |p| if (p.cursor != p.length()) return null;
        entry.applied = true;
        return result;
    }
    /// Install only after physical handback/validation. Caller reserves BOTH
    /// allocations against task_results budgets before calling this method.
    /// Result.value is metadata only; application of bytes uses takeResult too.
    pub fn stage(self: *Host, id: base.Handle, owner: u64, publication: Publication) !void {
        try self.poll();
        const entry = try self.find(id, owner);
        if (!schedule.resultIsCurrent(entry.generation, entry.current_generation)) return error.InvalidTransition;
        if (entry.job.terminal == null or !(try self.ledger.inspect(id, owner)).state.terminal() or entry.applied or entry.publication != null or publication.cursor != 0)
            return error.InvalidTransition;
        for (publication.sources(), publication.destinations(), 0..) |source, destination, i| {
            const limit: usize = if (i == 0) @import("task_transfer.zig").default_result_limit else @import("task_results.zig").diagnostic_limit;
            if (source.len > limit or destination.len != source.len) return error.InvalidInput;
        }
        if (entry.job.terminal.?.kind != .succeeded and publication.result.len != 0) return error.InvalidInput;
        entry.publication = publication;
    }
    /// One host turn, oldest first. Copies result AND diagnostics under the
    /// scheduler's configurable (default 96 KiB) budget. No callback can reenter acceptance here.
    pub fn copyTurn(self: *Host) !usize {
        try self.poll();
        var records: [16]schedule.Completion = undefined;
        var selected: [16]*Entry = undefined;
        var count: usize = 0;
        for (&self.entries) |*slot| if (slot.*) |*entry| {
            if (!schedule.resultIsCurrent(entry.generation, entry.current_generation)) continue;
            if (entry.publication) |p| {
                const remaining = p.length() - p.cursor;
                if (remaining == 0) continue;
                var index = count;
                while (index > 0 and selected[index - 1].id.serial > entry.id.serial) : (index -= 1) {
                    selected[index] = selected[index - 1];
                }
                selected[index] = entry;
                count += 1;
            }
        };
        for (selected[0..count], 0..) |entry, i| {
            const p = entry.publication.?;
            records[i] = .{ .id = entry.id.serial, .remaining = p.length() - p.cursor };
        }
        const decision = try schedule.decide(.{ .completions = records[0..count], .copy_bytes = self.copy_bytes }, 0, 0);
        var total: usize = 0;
        for (decision.copies[0..decision.copy_count], 0..) |copy, i| {
            const p = &selected[i].publication.?;
            var bytes = copy.bytes;
            var offset = p.cursor;
            for (p.sources(), p.destinations()) |source, destination| {
                if (offset >= source.len) {
                    offset -= source.len;
                    continue;
                }
                const n = @min(bytes, source.len - offset);
                @memcpy(destination[offset..][0..n], source[offset..][0..n]);
                p.cursor += n;
                bytes -= n;
                offset = 0;
                if (bytes == 0) break;
            }
            total += copy.bytes;
        }
        return total;
    }
    pub fn collect(self: *Host, id: base.Handle, owner: u64) !void {
        try self.poll();
        const record = try self.ledger.inspect(id, owner);
        var found: ?*Entry = null;
        for (&self.entries) |*slot| if (slot.*) |*entry| {
            if (std.meta.eql(entry.id, id)) found = entry;
        };
        const entry = found orelse return error.InvalidHandle;
        if (!record.state.terminal() or self.queue.isCleaning(entry.job)) return error.ReferencesRemain;
        if (record.external_valid) try self.ledger.release(id, owner);
        _ = try self.ledger.collect(id, owner);
        for (&self.entries) |*slot| if (slot.*) |*e| {
            if (e == entry) {
                slot.* = null;
                return;
            }
        };
        unreachable;
    }
    pub fn decide(self: *Host, input: schedule.Input, now: base.Instant, start: usize) !schedule.Decision {
        try permissions.requireHostSubmission();
        var observed = input;
        observed.copy_bytes = self.copy_bytes;
        observed.ledger_full = self.ledger.count() == 16;
        const view = self.queue.view();
        var waiting: [4]schedule.Waiting = undefined;
        for (view.waiting[0..view.count], 0..) |job, i| {
            const e = try self.byJob(job);
            waiting[i] = .{ .id = e.id.serial, .kind = e.kind, .owner = e.owner, .stream = e.stream, .deadline = job.deadline.at orelse std.math.maxInt(base.Instant), .cancel_requested = job.cancellation.isRequested() };
        }
        observed.waiting = waiting[0..view.count];
        observed.worker_available = false; // the real queue worker owns dispatch
        // Do not sleep while bounded byte-publication work remains.
        var completions: [16]schedule.Completion = undefined;
        var count: usize = 0;
        for (self.entries) |slot| if (slot) |e| {
            if (!schedule.resultIsCurrent(e.generation, e.current_generation)) continue;
            if (e.publication) |p| {
                const remaining = p.length() - p.cursor;
                if (remaining != 0) {
                    completions[count] = .{ .id = e.id.serial, .remaining = remaining };
                    count += 1;
                }
            }
        };
        observed.completions = completions[0..count];
        var decision = try schedule.decide(observed, now, start);
        // Pure decide predicts the state AFTER its copy proposals. This adapter
        // copies in copyTurn, so a still-unexecuted final fragment must wake again.
        if (count != 0) decision.next = .run_again;
        // Also wake for collection timeout after physical execution has ended.
        for (self.entries) |slot| if (slot) |entry| {
            if (entry.stop) |diagnostic| {
                const at = if (!diagnostic.stopped and !diagnostic.stop_exceeded)
                    diagnostic.stop_deadline +| 1
                else if (!diagnostic.collection_exceeded)
                    diagnostic.collection_deadline +| 1
                else
                    continue;
                if (at <= now) {
                    decision.next = .run_again;
                } else switch (decision.next) {
                    .run_again => {},
                    .sleep_until => |existing| decision.next = .{ .sleep_until = @min(at, existing) },
                    .wait_for_wake => decision.next = .{ .sleep_until = at },
                }
            }
        };
        return decision;
    }
};
