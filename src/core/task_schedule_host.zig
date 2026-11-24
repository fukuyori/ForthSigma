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
    };
    copy_bytes: usize = schedule.Limits.copy_bytes,
    queue: *queue_mod.DefaultQueue,
    ledger: ledger_mod.DefaultLedger,
    entries: [16]?Entry = @splat(null),
    // Monotonic host-wide stamps avoid reusing a stream's generation after collect.
    generation: u64 = 0,

    pub fn init(queue: *queue_mod.DefaultQueue, epoch: u64) !Host {
        return .{ .queue = queue, .ledger = try ledger_mod.DefaultLedger.init(epoch) };
    }
    fn find(self: *Host, id: base.Handle, owner: u64) !*Entry {
        _ = try self.ledger.lookup(id, owner);
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
                    self.ledger.cancel(entry.id, entry.owner) catch unreachable;
                    self.queue.cancel(entry.job);
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
    /// Queue acquire-load handback proves the runner/cleanup no longer uses job.
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
                    try self.ledger.cancel(entry.id, entry.owner);
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
                self.ledger.checkWorkerAvailable() catch return;
                try self.ledger.start(entry.id, entry.owner);
            }
        }
    }
    fn finishAcquired(self: *Host, entry: *Entry) !void {
        const result = entry.job.terminal.?;
        _ = try self.ledger.finish(entry.id, entry.owner, switch (result.kind) {
            .succeeded => .succeeded,
            .failed => .failed,
            .cancelled => .cancelled,
        });
        try self.ledger.executionStopped(entry.id, entry.owner);
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
    pub fn markUnresponsive(self: *Host, id: base.Handle, owner: u64) !void {
        try self.poll();
        const entry = try self.find(id, owner);
        if (!(try self.ledger.inspect(id, owner)).execution_ref) return error.InvalidTransition;
        if (!self.queue.markUnresponsiveFor(entry.job)) return error.InvalidTransition;
        try self.ledger.markStopUnconfirmed(id, owner);
    }
    pub fn collect(self: *Host, id: base.Handle, owner: u64) !void {
        try self.poll();
        const entry = try self.find(id, owner);
        if (!(try self.ledger.inspect(id, owner)).state.terminal()) return error.ReferencesRemain;
        try self.ledger.release(id, owner);
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
        return decision;
    }
};
