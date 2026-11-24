//! Native connections for the bounded, host-only registration API.
const base = @import("core/runtime_base.zig");
const wait = @import("core/task_wait.zig");
const Wake = @import("host_wake.zig").Wake;
const forth = @import("forth.zig");
const input = @import("host_input.zig");
pub const noop = struct {
    pub fn check(_: ?*anyopaque) base.Error!void {}
    pub fn detach(_: ?*anyopaque) void {}
};
pub const Input = struct {
    machine: *forth.State,
    /// Redirected input must use the file adapter, never modern's consuming path.
    redirected: ?wait.Source = null,
    /// Redirected sources supply their own interest through the I/O adapter.
    pub fn interest(_: *Input) ?Wake.Interest {
        if (@import("builtin").os.tag == .windows) {
            const console = input.waitConsole() orelse return null;
            return .{ .console = console };
        }
        return .{ .fd = 0 };
    }
    pub fn source(self: *Input) wait.Source {
        return .{ .context = self, .validate = validate, .attach = attach, .probe = probe, .detach = detach };
    }
    fn attach(context: ?*anyopaque) base.Error!void {
        const self: *Input = @ptrCast(@alignCast(context.?));
        if (self.redirected) |source_| try source_.attach(source_.context);
    }
    fn detach(context: ?*anyopaque) void {
        const self: *Input = @ptrCast(@alignCast(context.?));
        if (self.redirected) |source_| source_.detach(source_.context);
    }
    fn validate(context: ?*anyopaque) base.Error!void {
        const self: *Input = @ptrCast(@alignCast(context.?));
        if (@import("core/input_redirect.zig").selected(self.machine) != null) {
            const redirected = self.redirected orelse return error.HostFailed;
            try redirected.validate(redirected.context);
        } else if (self.machine.writer.standard_event_fn == null or self.machine.writer.standard_clock == null) return error.HostFailed;
    }
    fn probe(context: ?*anyopaque) base.Error!wait.State {
        const self: *Input = @ptrCast(@alignCast(context.?));
        if (@import("core/event_input.zig").modern_depth != 0) return error.HostFailed;
        if (@import("core/input_redirect.zig").selected(self.machine) != null) {
            const redirected = self.redirected orelse return error.HostFailed;
            var state = try redirected.probe(redirected.context);
            if (state.reason == .readable) state.reason = .input;
            return state;
        }
        const pending = try input.retainWaitRecords();
        const result = @import("core/event_input.zig").modern(self.machine, 0, true) catch |err| {
            if (err == error.UserInterrupt) return .{ .interrupted = true };
            return error.HostFailed;
        };
        const escape = self.machine.standard_input.escape_at;
        const next = if (escape) |at| try base.Deadline.afterMilliseconds(at, 50) else base.Deadline{ .at = null };
        return .{ .reason = switch (result) {
            .event => .input,
            .eof => .eof,
            .failure => .failure,
            else => null,
        }, .detail = if (result == .failure) result.failure else 0, .again = pending, .next = next };
    }
};
pub fn Task(comptime Queue: type) type {
    return struct {
        queue: *Queue,
        job: *@import("core/task_queue.zig").Job,
        pub fn source(self: *@This()) wait.Source {
            return .{ .context = self, .validate = noop.check, .attach = noop.check, .prepare = prepare, .probe = probe, .detach = noop.detach };
        }
        fn prepare(context: ?*anyopaque) base.Error!void {
            const self: *@This() = @ptrCast(@alignCast(context.?));
            _ = self.queue.poll(self.job);
        }
        fn probe(context: ?*anyopaque) base.Error!wait.State {
            const self: *@This() = @ptrCast(@alignCast(context.?));
            // Drain even RELEASEd completion before inspecting external validity.
            const terminal = self.queue.poll(self.job);
            const next = self.queue.nextDeadline();
            if (!self.job.external_valid) return .{ .reason = .released, .next = next };
            return .{ .reason = if (terminal) |value| switch (value.kind) {
                .succeeded => .succeeded,
                .failed => .failed,
                .cancelled => .cancelled,
            } else null, .detail = if (terminal) |value| @backingInt(value.reason) else 0, .next = next };
        }
    };
}
/// Use this host entry so signal interruption is retained independently of
/// input readiness and call timeout, even when no input target was requested.
pub fn poll(registration: *wait.Registration, interrupted: bool) wait.Result {
    var result = registration.poll();
    result.interrupted = result.interrupted or interrupted;
    return result;
}

/// Caller owns one signal scope, pumps children and all host deadlines each turn.
/// Never wait when poll returned again. OS wake reasons are only retry hints.
pub fn sleep(registration: *wait.Registration, result: wait.Result, wake: *Wake, interests: []const Wake.Interest) base.Error!void {
    if (result.finished() or result.again) return;
    const ops = wake.operations();
    if (registration.wake.context != ops.context or registration.wake.observe_fn != ops.observe_fn or
        registration.wake.notify_fn != ops.notify_fn or registration.wake.wait_fn != ops.wait_fn) return error.HostFailed;
    try @import("host_wait.zig").bindInterruptWake(wake);
    defer @import("host_wait.zig").unbindInterruptWake();
    var all: [64]Wake.Interest = undefined;
    if (interests.len > 64) return error.ResultOutOfRange;
    var count: usize = 0;
    for (interests) |interest| {
        var duplicate = false;
        for (all[0..count]) |previous| {
            if (@import("builtin").os.tag == .windows) {
                duplicate = duplicate or previous.console == interest.console;
            } else duplicate = duplicate or (previous.fd == interest.fd and previous.writing == interest.writing);
        }
        if (!duplicate) {
            if (count == all.len) return error.ResultOutOfRange;
            all[count] = interest;
            count += 1;
        }
    }
    const pipe = @import("host_signal_pipe.zig");
    if (pipe.descriptor() >= 0) {
        if (count == all.len) return error.ResultOutOfRange;
        all[count] = .{ .fd = pipe.descriptor() };
        count += 1;
    }
    _ = try wake.waitMany(registration.observed, result.next, registration.cancellation, registration.clock, all[0..count]);
    if (try pipe.pump()) try wake.notify();
}
