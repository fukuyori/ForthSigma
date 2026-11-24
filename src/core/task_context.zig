//! Synchronous worker scopes, owned by the executing thread, not by State.
//! Tokens and contexts must outlive every nested call. No allocation or VM reuse.
const Cancellation = @import("runtime_base.zig").Cancellation;

threadlocal var current: ?*Context = null;
threadlocal var worker_thread: bool = false;

/// Covers worker initialization, runner and cleanup, outside runAsWorker too.
pub const WorkerScope = struct {
    previous: bool = false,
    pub fn enter(self: *WorkerScope) void {
        self.previous = worker_thread;
        worker_thread = true;
    }
    pub fn leave(self: *WorkerScope) void {
        worker_thread = self.previous;
    }
};

/// Includes native reentry into another VM on this worker thread.
pub fn isWorkerThread() bool {
    return worker_thread or current != null;
}

pub const Context = struct {
    machine: *const anyopaque,
    token: *const Cancellation,
    previous: ?*Context,
    memory: @import("task_permissions.zig").Options = .{},

    pub fn enter(self: *Context, machine: *const anyopaque, token: *const Cancellation) void {
        self.* = .{ .machine = machine, .token = token, .previous = current };
        current = self;
    }

    pub fn leave(self: *Context) void {
        @import("std").debug.assert(current == self);
        current = self.previous;
    }
};

pub fn cancellation(machine: *const anyopaque) ?*const Cancellation {
    var cursor = current;
    while (cursor) |context| : (cursor = context.previous) {
        if (context.machine == machine) return context.token;
    }
    return null;
}

pub fn options(machine: *const anyopaque) @import("task_permissions.zig").Options {
    var cursor = current;
    while (cursor) |context| : (cursor = context.previous) {
        if (context.machine == machine) return context.memory;
    }
    return .{};
}
