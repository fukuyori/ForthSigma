//! Optional process dispatch. Validate stack and memory before host effects.
const defs = @import("defs.zig");
const forth = @import("../forth.zig");

pub fn execute(self: *forth.State, comptime word: defs.Builtin) forth.RuntimeError!void {
    const inputs = switch (word) {
        .proc_new => 0,
        .proc_arg, .proc_cwd, .proc_env, .proc_io => 3,
        .proc_wait => 2,
        else => 1,
    };
    const outputs = switch (word) {
        .proc_new, .proc_stdin, .proc_stdout, .proc_stderr => 2,
        .proc_status, .proc_wait => 3,
        else => 1,
    };
    try self.requireDepth(inputs);
    if (self.data_depth - inputs + outputs > self.data_stack.len) return error.StackOverflow;
    if (!defs.files_enabled or !defs.extension_enabled) return error.HostUnavailable;
    const ops = self.writer.process_ops orelse return error.HostUnavailable;
    const context = self.writer.context;
    switch (word) {
        .proc_new => {
            const result = ops.new(context);
            try self.push(@bitCast(result.value));
            try self.push(result.ior);
        },
        .proc_arg, .proc_cwd, .proc_env => {
            const address = try self.peek(2);
            const length = try self.peek(1);
            if (length < 0) return self.throwCode(-24);
            const start = try self.memoryAddress(address, @intCast(length));
            const result = ops.text(context, try self.peek(0), switch (word) {
                .proc_arg => .argument,
                .proc_cwd => .cwd,
                .proc_env => .environment,
                else => unreachable,
            }, self.memory[start..][0..@intCast(length)]);
            self.data_depth -= 3;
            try self.push(result);
        },
        .proc_io => {
            const result = ops.io(context, try self.peek(0), try self.peek(1), try self.peek(2));
            self.data_depth -= 3;
            try self.push(result);
        },
        .proc_stdin, .proc_stdout, .proc_stderr => {
            const result = ops.stream(context, try self.peek(0), switch (word) {
                .proc_stdin => 0,
                .proc_stdout => 1,
                .proc_stderr => 2,
                else => unreachable,
            });
            self.data_depth -= 1;
            try self.push(@bitCast(result.value));
            try self.push(result.ior);
        },
        .proc_status, .proc_wait => {
            const result = if (word == .proc_status) ops.status(context, try self.peek(0)) else try ops.wait(context, try self.peek(1), try self.peek(0));
            self.data_depth -= inputs;
            try self.push(result.state);
            try self.push(result.code);
            try self.push(result.ior);
        },
        .proc_start, .proc_term, .proc_kill, .proc_free => {
            const id = try self.peek(0);
            const result = switch (word) {
                .proc_start => try ops.start(context, id),
                .proc_term, .proc_kill => ops.signal(context, id, word == .proc_kill),
                .proc_free => ops.free(context, id),
                else => unreachable,
            };
            self.data_stack[self.data_depth - 1] = result;
        },
        else => unreachable,
    }
}
