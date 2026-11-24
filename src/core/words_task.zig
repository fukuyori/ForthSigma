//! Public task dispatch. Constants never initialize the host subsystem.
const forth = @import("../forth.zig");
const defs = @import("defs.zig");
pub const Signature = struct { inputs: usize, outputs: usize };
pub fn signature(word: defs.Builtin) Signature {
    return .{ .inputs = switch (word) {
        .task_snapshot => 0,
        .task_submit => 7,
        .task_wait => 2,
        .task_result => 3,
        .task_diagnostic => 4,
        .task_wait_many => 5,
        else => 1,
    }, .outputs = switch (word) {
        .task_snapshot, .task_submit => 2,
        .task_state => 5,
        .task_wait, .task_result, .task_diagnostic, .task_wait_many => 3,
        else => 1,
    } };
}
pub fn execute(self: *forth.State, comptime word: defs.Builtin) forth.RuntimeError!void {
    switch (word) {
        .task_queued => try self.push(1),
        .task_running => try self.push(2),
        .task_succeeded => try self.push(3),
        .task_failed => try self.push(4),
        .task_cancelled => try self.push(5),
        .task_g1 => try self.push(0),
        .task_g2 => try self.push(1),
        .task_t1 => try self.push(2),
        .task_i1 => try self.push(3),
        .task_wait_target_cells => try self.push(5),
        .task_wait_event_cells => try self.push(4),
        .task_e_handle => try self.push(-300),
        .task_e_full => try self.push(-301),
        .task_e_stale => try self.push(-302),
        .task_e_entry => try self.push(-303),
        .task_e_denied => try self.push(-304),
        .task_e_limit => try self.push(-305),
        .task_e_not_ready => try self.push(-306),
        .task_e_short => try self.push(-307),
        .task_e_abi => try self.push(-308),
        .task_e_busy => try self.push(-309),
        .task_e_exhausted => try self.push(-310),
        .task_e_no_capability => try self.push(-311),
        .task_e_host => try self.push(-312),
        .task_e_queue_expired => try self.push(-313),
        .task_e_stop_unconfirmed => try self.push(-314),
        .task_wait_input => try self.push(1),
        .task_wait_io => try self.push(2),
        .task_wait_task => try self.push(3),
        .task_wait_clock => try self.push(4),
        .task_wait_paint => try self.push(5),
        .task_event_input => try self.push(1),
        .task_event_readable => try self.push(2),
        .task_event_writable => try self.push(4),
        .task_event_eof => try self.push(8),
        .task_event_failure => try self.push(16),
        .task_event_closed => try self.push(32),
        .task_event_succeeded => try self.push(64),
        .task_event_failed => try self.push(128),
        .task_event_cancelled => try self.push(256),
        .task_event_released => try self.push(512),
        .task_event_deadline => try self.push(1024),
        .task_event_painted => try self.push(2048),
        .task_event_capability_lost => try self.push(4096),
        .task_wait_expired => try self.push(1),
        .task_wait_cancelled => try self.push(2),
        .task_wait_interrupted => try self.push(4),
        .task_wait_host_failed => try self.push(8),
        else => {
            const shape = signature(word);
            try self.requireDepth(shape.inputs);
            if (self.data_depth - shape.inputs + shape.outputs > self.data_stack.len) return error.StackOverflow;
            const callback = self.writer.task_fn orelse return error.HostUnavailable;
            try callback(self.writer.task_context, self, word);
        },
    }
}
