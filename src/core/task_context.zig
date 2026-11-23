//! Synchronous worker scopes, owned by the executing thread, not by State.
//! Tokens and contexts must outlive every nested call. No allocation or VM reuse.
const Cancellation = @import("runtime_base.zig").Cancellation;

threadlocal var current: ?*Context = null;

pub const Context = struct {
    machine: *const anyopaque,
    token: *const Cancellation,
    previous: ?*Context,

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
