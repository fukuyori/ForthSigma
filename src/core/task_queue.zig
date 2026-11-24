//! One host, one worker. Pin Queue and runner/wake contexts until joined.
//! Pin each accepted Job through terminal observation AND !isCleaning(job); retain
//! its result buffers until their consumers finish. Never reset a Job in place.
//! This module owns no VM or public handles; their owner supplies cleanup/runner.
const std = @import("std");
const base = @import("runtime_base.zig");
const Wake = @import("../host_wake.zig").Wake;
pub const Result = struct {
    kind: enum { succeeded, failed, cancelled },
    reason: enum { none, runner, queue_expired, clock_failed, worker_failed } = .none,
    value: usize = 0,
};
pub const JobRunner = struct {
    context: ?*anyopaque = null,
    run_fn: *const fn (?*anyopaque, *Job) Result,
};
pub const Use = enum { g1, g2, t1, i1 };
pub fn defaultWait(use: Use) i64 {
    return switch (use) {
        .g1 => 50,
        .g2, .t1 => 100,
        .i1 => 200,
    };
}
pub const Retirement = struct {
    context: ?*anyopaque,
    destroy: *const fn (?*anyopaque) void,
};
pub const Job = struct {
    /// Independent owner, detached by worker before publication. Never borrows Job.
    after_publication: ?Retirement = null,
    worker_retirement: bool = false, // only work() enables deferred destruction
    context: ?*anyopaque = null,
    /// Drop the input/Snapshot execution references exactly once, not this Job.
    cleanup_fn: ?*const fn (?*anyopaque) void = null,
    cancellation: base.Cancellation = .{},
    trace_storage: @import("task_trace.zig").Storage = .{},
    acceptance: @import("task_acceptance.zig").Storage = .{},
    acquired: std.atomic.Value(bool) = .init(false), // set under queue gate on physical worker acquisition; atomic for host readers
    deadline: base.Deadline = .{ .at = null },
    phase: enum { fresh, queued, running, sealed, terminal } = .fresh, // queue gate
    result: Result = undefined, // immutable after ready release-store
    ready: std.atomic.Value(bool) = .init(false),
    terminal: ?Result = null, // host only
    external_valid: bool = true, // host only; handle table belongs to caller
    fn seal(self: *Job, result: Result) void {
        if (self.cleanup_fn) |cleanup| cleanup(self.context);
        self.result = result;
        self.cancellation.stamp(.sealed);
    }
};
pub fn Queue(comptime capacity: usize) type {
    return struct {
        const Self = @This();
        pub const Error = base.Error || error{ QueueFull, Closed, WorkerUnresponsive, WorkerFailed, InvalidJob };
        gate: std.atomic.Value(bool) = .init(false),
        waiting: [capacity]*Job = undefined,
        count: usize = 0,
        active: ?*Job = null,
        cleaning: ?*Job = null, // gate; prevents host collection and VM overlap
        closing: bool = false,
        notifying: bool = false, // covers publication-to-notify failure window
        unresponsive: bool = false,
        worker_failed: ?base.Error = null, // gate; original wait/clock error
        worker_clock: base.Clock = @import("../host_clock.zig").clock,
        worker_wake: ?base.WakeOps = null, // set before start; internal injection backend
        clock: base.Clock,
        common: base.WakeOps,
        runner: JobRunner,
        wake: Wake,
        thread: ?std.Thread = null,
        exited: std.atomic.Value(bool) = .init(false),
        notification_failed: std.atomic.Value(bool) = .init(false),

        pub fn init(clock: base.Clock, common: base.WakeOps, runner: JobRunner) Error!Self {
            return .{ .clock = clock, .common = common, .runner = runner, .wake = try Wake.init() };
        }
        /// Call exactly once, after placing Self at its permanent address.
        pub fn start(self: *Self) !void {
            if (self.thread != null or self.exited.load(.acquire)) return error.Closed;
            self.thread = try std.Thread.spawn(.{ .stack_size = 1024 * 1024 }, work, .{self});
        }
        fn lock(self: *Self) void {
            while (self.gate.cmpxchgWeak(false, true, .acquire, .monotonic) != null) std.atomic.spinLoopHint();
        }
        fn unlock(self: *Self) void {
            self.gate.store(false, .release);
        }
        fn notify(self: *Self) void {
            self.common.notify_fn(self.common.context) catch self.notification_failed.store(true, .release);
        }
        fn kick(self: *Self) void {
            const ops = self.worker_wake orelse self.wake.operations();
            ops.notify_fn(ops.context) catch self.notification_failed.store(true, .release);
        }
        pub fn submit(self: *Self, job: *Job, milliseconds: i64) Error!void {
            return self.submitReplacing(job, milliseconds, null);
        }
        /// Atomic FIFO replacement. If worker won acquisition, append instead.
        /// Every fallible check precedes mutation; failure preserves the old job.
        pub fn submitReplacing(self: *Self, job: *Job, milliseconds: i64, old: ?*Job) Error!void {
            if (milliseconds < 0) return error.ResultOutOfRange;
            const deadline = try base.Deadline.afterMilliseconds(try self.clock.now(), milliseconds);
            self.lock();
            errdefer self.unlock();
            if (self.worker_failed != null) return error.WorkerFailed;
            if (self.closing) return error.Closed;
            if (job.phase != .fresh) return error.InvalidJob;
            var replace: ?usize = null;
            if (old) |previous| {
                for (self.waiting[0..self.count], 0..) |candidate, i| {
                    if (candidate == previous) {
                        replace = i;
                        break;
                    }
                }
            }
            if (replace == null and self.count == capacity) return error.QueueFull;
            job.cancellation.attachTrace(&job.trace_storage);
            if (comptime @import("task_acceptance.zig").enabled) job.cancellation.acceptance = &job.acceptance;
            job.deadline = deadline;
            job.phase = .queued;
            if (replace) |index| {
                self.waiting[index] = job;
                old.?.cancellation.request();
                old.?.phase = .sealed;
            } else {
                self.waiting[self.count] = job;
                self.count += 1;
            }
            self.unlock();
            if (replace != null) old.?.seal(.{ .kind = .cancelled });
            self.kick();
        }
        pub const View = struct { waiting: [capacity]*Job = undefined, count: usize, active: ?*Job };
        pub fn isCleaning(self: *Self, job: *Job) bool {
            self.lock();
            defer self.unlock();
            return self.cleaning == job;
        }
        pub fn view(self: *Self) View {
            self.lock();
            defer self.unlock();
            var out: View = .{ .count = self.count, .active = self.active };
            @memcpy(out.waiting[0..self.count], self.waiting[0..self.count]);
            return out;
        }
        pub fn wasAcquired(self: *Self, job: *Job) bool {
            self.lock();
            defer self.unlock();
            return job.acquired.load(.acquire);
        }
        fn remove(self: *Self, index: usize) *Job {
            const job = self.waiting[index];
            for (index + 1..self.count) |i| self.waiting[i - 1] = self.waiting[i];
            self.count -= 1;
            return job;
        }
        /// Host only. A lost dequeue race only requests cancellation.
        pub fn cancel(self: *Self, job: *Job) void {
            self.lock();
            if (job.phase == .terminal) {
                self.unlock();
                return;
            }
            job.cancellation.request();
            if (job.phase == .sealed) {
                self.unlock();
                return;
            }
            for (self.waiting[0..self.count], 0..) |candidate, i| {
                if (candidate == job) {
                    _ = self.remove(i);
                    if (comptime @import("task_acceptance.zig").enabled) job.acceptance.queued = true;
                    job.phase = .sealed;
                    self.unlock();
                    job.seal(.{ .kind = .cancelled });
                    // Host's next poll performs release publication and notify.
                    return;
                }
            }
            self.unlock();
            self.kick();
        }
        /// Synchronized host observation; never read a running Job.phase directly.
        pub fn phaseOf(self: *Self, job: *Job) @FieldType(Job, "phase") {
            self.lock();
            defer self.unlock();
            return job.phase;
        }
        pub fn release(self: *Self, job: *Job) void {
            job.external_valid = false;
            self.cancel(job);
        }
        /// Host sweep, even without notifications. Returns immutable terminal data.
        pub fn poll(self: *Self, job: *Job) ?Result {
            self.expire();
            self.lock();
            if (job.phase == .sealed and !job.ready.load(.acquire)) {
                job.cancellation.stamp(.published);
                job.ready.store(true, .release);
                self.unlock();
                self.notify();
            } else self.unlock();
            if (!job.ready.load(.acquire)) return null;
            if (job.terminal == null) {
                job.cancellation.stamp(.observed);
                job.terminal = job.result;
                self.lock();
                job.phase = .terminal;
                self.unlock();
                job.cancellation.dumpTrace("observed");
            }
            return job.terminal;
        }
        /// Sticky diagnostic; host must use finite waits while true.
        pub fn notificationFailed(self: *const Self) bool {
            return self.notification_failed.load(.acquire);
        }
        /// Host scheduler includes this absolute deadline in its common wait.
        pub fn nextDeadline(self: *Self) base.Deadline {
            self.lock();
            defer self.unlock();
            var earliest: ?base.Instant = null;
            for (self.waiting[0..self.count]) |job| {
                if (job.deadline.at) |at| {
                    if (earliest == null or at < earliest.?) earliest = at;
                }
            }
            if (self.active != null or self.notifying or self.notificationFailed()) {
                const now = self.clock.now() catch return .{ .at = 0 };
                const retry = base.Deadline.afterMilliseconds(now, 10) catch return .{ .at = now };
                if (earliest == null or retry.at.? < earliest.?) earliest = retry.at;
            }
            return .{ .at = earliest };
        }
        /// Host only. Also removes expired jobs behind a nonexpired front item.
        pub fn expire(self: *Self) void {
            const now = self.clock.now() catch {
                self.failWaiting(.clock_failed);
                return;
            };
            while (true) {
                self.lock();
                var found: ?*Job = null;
                for (self.waiting[0..self.count], 0..) |job, i| {
                    if (job.deadline.expired(now)) {
                        found = self.remove(i);
                        found.?.phase = .sealed;
                        break;
                    }
                }
                self.unlock();
                const job = found orelse return;
                job.seal(.{ .kind = .failed, .reason = .queue_expired });
                job.cancellation.stamp(.published);
                job.ready.store(true, .release);
                self.notify();
            }
        }
        fn failWaiting(self: *Self, reason: @FieldType(Result, "reason")) void {
            while (true) {
                self.lock();
                if (self.count == 0) {
                    self.unlock();
                    return;
                }
                const job = self.remove(0);
                job.phase = .running;
                self.unlock();
                job.seal(.{ .kind = .failed, .reason = reason });
                self.lock();
                job.phase = .sealed;
                job.cancellation.stamp(.published);
                job.ready.store(true, .release);
                self.unlock();
                self.notify();
            }
        }
        /// Compatibility helper: idle queues acquire no unresponsive mark.
        pub fn markUnresponsive(self: *Self) void {
            if (self.view().active) |job| _ = self.markUnresponsiveFor(job);
        }
        /// A timeout for an old job must not retire/cancel a newer acquisition.
        pub fn markUnresponsiveFor(self: *Self, expected: *Job) bool {
            self.lock();
            if (self.active != expected) {
                self.unlock();
                return false;
            }
            self.unresponsive = true;
            if (self.active) |job| job.cancellation.request();
            self.unlock();
            self.kick();
            return true;
        }
        /// Host owner exit: caller invalidates its external handle table too.
        pub fn stop(self: *Self) void {
            self.lock();
            self.closing = true;
            if (self.active) |job| {
                job.external_valid = false;
                job.cancellation.request();
            }
            self.unlock();
            while (true) {
                self.lock();
                const job = if (self.count != 0) self.waiting[0] else null;
                self.unlock();
                self.release(job orelse break);
            }
            self.kick();
        }
        /// Nonblocking until worker exit is observed. Retain all storage on false.
        pub fn joinIfStopped(self: *Self) bool {
            if (self.thread == null) return true;
            if (!self.exited.load(.acquire)) return false;
            if (self.thread) |thread| {
                const acceptance = @import("task_acceptance.zig");
                const started = if (comptime acceptance.diagnostics) acceptance.now() else 0;
                thread.join();
                if (comptime acceptance.diagnostics) acceptance.interval("worker_join_ns", started);
                self.thread = null;
            }
            return true;
        }
        /// Only before start, or after successful join. Never detach.
        pub fn deinit(self: *Self) Error!void {
            if (self.thread != null or self.count != 0 or self.active != null or self.cleaning != null) return error.WorkerUnresponsive;
            try self.wake.deinit();
        }
        fn workerFailure(self: *Self, err: base.Error) void {
            self.lock();
            self.worker_failed = err;
            self.closing = true;
            self.unlock();
            self.failWaiting(.worker_failed);
        }
        fn work(self: *Self) void {
            var worker_scope: @import("task_context.zig").WorkerScope = .{};
            worker_scope.enter();
            defer worker_scope.leave();
            defer {
                self.lock();
                self.closing = true;
                self.unlock();
                self.exited.store(true, .release);
                self.notify();
            }
            while (true) {
                const ops = self.worker_wake orelse self.wake.operations();
                const observed = ops.observe_fn(ops.context);
                self.lock();
                if (self.closing) {
                    self.unlock();
                    return;
                }
                if (!self.unresponsive and self.count != 0) {
                    const job = self.remove(0);
                    self.active = job;
                    job.cancellation.stamp(.acquired);
                    job.acquired.store(true, .release);
                    job.phase = .running;
                    job.worker_retirement = true;
                    self.unlock();
                    const now = self.clock.now();
                    const result: Result = if (now) |instant|
                        if (job.deadline.expired(instant)) .{ .kind = .failed, .reason = .queue_expired } else if (job.cancellation.checkpoint()) .{ .kind = .cancelled } else self.runner.run_fn(self.runner.context, job)
                    else |_|
                        .{ .kind = .failed, .reason = .clock_failed };
                    job.cancellation.stamp(.runner_return);
                    const retirement = job.after_publication;
                    job.after_publication = null;
                    job.seal(result);
                    self.lock();
                    job.phase = .sealed;
                    if (retirement != null) self.cleaning = job;
                    job.cancellation.stamp(.published);
                    job.ready.store(true, .release);
                    self.active = null;
                    // Execution has stopped. The sole worker cannot acquire the next
                    // VM until its independent retirement has completed.
                    self.unresponsive = false;
                    self.notifying = true;
                    self.unlock();
                    self.notify();
                    // No production Job/token/input access after publication. Host
                    // retains the entry until cleaning clears; diagnostics alone
                    // write timestamps before that gate-protected handback.
                    const acceptance = @import("task_acceptance.zig");
                    if (comptime acceptance.diagnostics) {
                        if (retirement != null) job.acceptance.retirement_start = acceptance.now();
                    }
                    if (retirement) |owned| owned.destroy(owned.context);
                    if (comptime acceptance.diagnostics) {
                        if (retirement != null) job.acceptance.retirement_end = acceptance.now();
                    }
                    self.lock();
                    if (comptime acceptance.diagnostics) {
                        if (retirement != null) job.acceptance.handback_end = acceptance.now();
                    }
                    self.cleaning = null;
                    self.notifying = false;
                    self.unlock();
                    if (retirement != null) self.notify();
                    continue;
                }
                self.unlock();
                // Private wake never consumes the common host wake. Finite wait
                // recovers even if the OS signal operation failed.
                const now = self.worker_clock.now() catch |err| {
                    self.workerFailure(err);
                    return;
                };
                const deadline = base.Deadline.afterMilliseconds(now, 10) catch |err| {
                    self.workerFailure(err);
                    return;
                };
                _ = ops.wait_fn(ops.context, observed, deadline, null, self.worker_clock) catch |err| {
                    self.workerFailure(err);
                    return;
                };
            }
        }
    };
}
pub const DefaultQueue = Queue(4);
