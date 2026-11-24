//! Pinned execution payload for task_queue's worker callback. Host owns buffers.
const std = @import("std");
const queue = @import("task_queue.zig");
const snapshot = @import("task_snapshot.zig");
const job = @import("task_job.zig");
pub const Execution = struct {
    allocator: std.mem.Allocator,
    admission: ?snapshot.Admission,
    entry: []const u8,
    input: []const u8,
    limits: @import("task_transfer.zig").Limits = .{},
    max_native_bytes: usize = 64 * 1024,
    result: ?[]u8 = null,
    failure: ?anyerror = null,

    /// Bind after pinning Execution. Keep input/entry alive through publication.
    pub fn queued(self: *Execution) queue.Job {
        return .{ .context = self, .cleanup_fn = cleanup };
    }
    pub fn runner() queue.JobRunner {
        return .{ .run_fn = run };
    }
    fn cast(raw: ?*anyopaque) *Execution {
        return @ptrCast(@alignCast(raw.?));
    }
    fn run(_: ?*anyopaque, item: *queue.Job) queue.Result {
        const self = cast(item.context);
        var admission = self.admission orelse return .{ .kind = .failed, .reason = .runner };
        self.admission = null; // synchronous job consumes on every exit
        self.result = job.runWithOptions(self.allocator, &admission, self.entry, self.input, &item.cancellation, self.limits, .{ .max_native_bytes = self.max_native_bytes }) catch |err| {
            self.failure = err;
            return .{ .kind = if (err == error.TaskCancelled) .cancelled else .failed, .reason = if (err == error.TaskCancelled) .none else .runner };
        };
        // D04: never replace successful return/copy with a late token check.
        return .{ .kind = .succeeded };
    }
    fn cleanup(raw: ?*anyopaque) void {
        const self = cast(raw);
        if (self.admission) |*admission| admission.deinit();
        self.admission = null;
    }
    /// Only after queue publication and all result consumers have stopped.
    pub fn deinit(self: *Execution) void {
        cleanup(self);
        if (self.result) |bytes| self.allocator.free(bytes);
        self.result = null;
    }
};
