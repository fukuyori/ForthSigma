//! Debug-only bounded entry. The ordinary VM loop never calls this module.
const std = @import("std");
const defs = @import("defs.zig");
const forth = @import("../forth.zig");
const system = @import("words_system.zig");
pub const maximum_depth = 16;
pub const poll_interval: u16 = 1024;
pub const Stop = union(enum) { none, cli, entry: usize };
const Budget = struct { remaining: u64 = 0, unlimited: bool = true };
pub const Control = struct {
    stack: [maximum_depth]Budget = @splat(.{}),
    depth: usize = 0,
    stop: Stop = .none,
    until_poll: u16 = 0,
};
pub const Empty = struct {};
pub const Unit = enum { operation, native, entry, interpreted };

pub inline fn active(self: *const forth.State) bool {
    return if (comptime defs.debug_enabled) self.execution.depth != 0 else false;
}
pub fn clearStop(self: *forth.State) void {
    if (comptime defs.debug_enabled) self.execution.stop = .none;
}

pub inline fn charge(self: *forth.State, unit: Unit) defs.RuntimeError!void {
    if (comptime defs.debug_enabled) {
        const control = &self.execution;
        const cli = (unit == .operation or unit == .native) and self.step_limit != 0;
        if (cli and self.steps_left == 0) {
            control.stop = .cli;
            return error.StepLimit;
        }
        if (control.depth == 0) {
            if (cli) self.steps_left -= 1;
            return;
        }
        for (control.stack[0..control.depth], 0..) |budget, index| {
            if (!budget.unlimited and budget.remaining == 0) {
                control.stop = .{ .entry = index };
                return error.StepLimit;
            }
        }
        if (cli) self.steps_left -= 1;
        for (control.stack[0..control.depth]) |*budget| if (!budget.unlimited) {
            budget.remaining -= 1;
        };
        if (control.depth != 0) {
            if (unit == .native or unit == .entry or control.until_poll == 0) {
                control.until_poll = poll_interval - 1;
                const ops = self.writer.execution_ops orelse return error.HostUnavailable;
                try ops.poll(self.writer.context, self);
            } else control.until_poll -= 1;
        }
    }
}

pub fn run(self: *forth.State) defs.RuntimeError!void {
    if (comptime defs.debug_enabled) return runEnabled(self) else return error.InvalidExecutionToken;
}
fn runEnabled(self: *forth.State) defs.RuntimeError!void {
    try self.requireDepth(2);
    const id = try self.wordId(try self.peek(1));
    const limit: u64 = @bitCast(try self.peek(0));
    const control = &self.execution;
    if (control.depth == maximum_depth) return error.ReturnStackOverflow;
    const ops = self.writer.execution_ops orelse return error.HostUnavailable;
    try ops.begin(self.writer.context, self);
    self.data_depth -= 2;
    const context = system.CatchContext.init(self);
    const index = control.depth;
    control.stack[index] = .{ .remaining = limit, .unlimited = limit == 0 };
    control.depth += 1;
    var failure: ?defs.RuntimeError = null;
    if (charge(self, .entry)) |_| {
        self.executeWord(id) catch |err| {
            failure = err;
        };
    } else |err| failure = err;
    const own_limit = (if (failure) |err| err == error.StepLimit else false) and control.stop == .entry and control.stop.entry == index;
    if (own_limit) {
        control.stop = .none;
        context.restore(self);
    }
    // An outer exhausted owner remains live while all inner entries unwind.
    control.depth = index;
    var finishing: ?defs.RuntimeError = null;
    ops.end(self.writer.context, self) catch |err| {
        finishing = err;
    };
    if (finishing) |err| if (err != error.UserInterrupt) return err;
    if (failure) |err| if (!own_limit) return err;
    if (finishing) |err| return err;
    try self.push(if (own_limit) -280 else 0);
}
