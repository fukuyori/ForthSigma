//! Extended counted loops; VM loop frames remain independent of the return stack.
const forth = @import("../forth.zig");
const defs = @import("defs.zig");
const map = @import("memory_map.zig");
pub const done_flag: map.Cell = 1 << 32;
pub fn target(value: map.Cell) map.Cell {
    return value & ~done_flag;
}
pub fn isEntry(kind: defs.OpKind) bool {
    return switch (kind) {
        .do_loop, .q_do_loop, .positive_do, .unsigned_positive_do, .negative_do, .unsigned_negative_do, .inclusive_negative_do, .unsigned_inclusive_negative_do, .for_loop, .memory_up_do, .memory_down_do => true,
        else => false,
    };
}
pub fn isMemory(kind: defs.OpKind) bool {
    return kind == .memory_up_do or kind == .memory_down_do;
}
pub const words = [_]defs.Builtin{ .positive_do, .unsigned_positive_do, .negative_do, .unsigned_negative_do, .inclusive_negative_do, .unsigned_inclusive_negative_do, .negative_loop, .for_word, .next_word, .memory_up_do, .memory_down_do, .array_to_mem, .index_limit, .delta_index, .cs_drop, .done, .question_dup_if, .question_dup_zero_if };
fn entryKind(word: defs.Builtin) defs.OpKind {
    return switch (word) {
        .positive_do => .positive_do,
        .unsigned_positive_do => .unsigned_positive_do,
        .negative_do => .negative_do,
        .unsigned_negative_do => .unsigned_negative_do,
        .inclusive_negative_do => .inclusive_negative_do,
        .unsigned_inclusive_negative_do => .unsigned_inclusive_negative_do,
        .for_word => .for_loop,
        .memory_up_do => .memory_up_do,
        .memory_down_do => .memory_down_do,
        else => unreachable,
    };
}
pub fn execute(self: *forth.State, comptime word: defs.Builtin) forth.RuntimeError!void {
    switch (word) {
        .positive_do, .unsigned_positive_do, .negative_do, .unsigned_negative_do, .inclusive_negative_do, .unsigned_inclusive_negative_do, .for_word, .memory_up_do, .memory_down_do => {
            try self.requireCompiling();
            const at = try self.emit(.{ .kind = entryKind(word) });
            try self.pushControl(.do_loop, at);
        },
        .negative_loop, .next_word => {
            try self.requireCompiling();
            if (self.topControl() != .do_loop) return error.ControlMismatch;
            const control = self.control_stack[self.control_depth - 1];
            const kind = self.code[control.address].kind;
            if (isMemory(kind) or (word == .next_word) != (kind == .for_loop)) return error.ControlMismatch;
            self.control_depth -= 1;
            _ = try self.emit(.{ .kind = if (word == .next_word) .next_loop else .negative_loop, .value = control.address + 1 });
            self.patch(control.address, self.code_count);
            self.local_count = if (kind == .do_loop or kind == .for_loop) @min(self.local_count, control.leave_locals) else control.locals;
        },
        .done => {
            const control = try self.popControl(.do_loop);
            self.code[control.address].value = @as(map.Cell, self.code_count) | done_flag;
            self.local_count = @min(self.local_count, control.leave_locals);
        },
        .array_to_mem => {
            try self.requireDepth(2);
            const size: map.UCell = @bitCast(try self.peek(0));
            const count: map.UCell = @bitCast(try self.peek(1));
            self.data_stack[self.data_depth - 2] = @bitCast(count *% size);
        },
        .index_limit => try self.push((try self.loopFrame(1)).limit),
        .delta_index => {
            const frame = try self.loopFrame(1);
            try self.push(frame.limit -% frame.index);
        },
        .cs_drop => {
            if (!self.defining) return error.CompileOnly;
            const kind = self.topControl() orelse return error.ControlMismatch;
            if (kind == .do_loop or kind == .case_start) return error.ControlMismatch;
            self.control_depth -= 1;
        },
        .question_dup_if, .question_dup_zero_if => {
            try self.requireCompiling();
            _ = try self.emit(.{ .kind = .builtin, .value = @backingInt(defs.Builtin.question_dup) });
            if (word == .question_dup_zero_if) _ = try self.emit(.{ .kind = .builtin, .value = @backingInt(defs.Builtin.zero_equal) });
            try self.compileIf();
        },
        else => unreachable,
    }
}

/// Returns true when the entry skips directly to its exit target.
pub fn enter(self: *forth.State, kind: defs.OpKind, encoded: map.Cell) forth.RuntimeError!bool {
    const count: usize = if (isMemory(kind)) 3 else if (kind == .for_loop) 1 else 2;
    try self.requireDepth(count);
    const keep = encoded & done_flag != 0;
    var frame = defs.Loop{ .index = 0, .limit = 0, .exit_pc = @intCast(target(encoded)), .leave_keeps_frame = keep };
    var skip = false;
    if (isMemory(kind)) {
        const stride = try self.peek(0);
        if (stride <= 0) return error.InvalidNumber;
        const length: map.UCell = @bitCast(try self.peek(1));
        const base: map.UCell = @bitCast(try self.peek(2));
        const sum = @addWithOverflow(base, length);
        if (sum[1] != 0) return error.InvalidNumber;
        frame.stride = @intCast(stride);
        if (kind == .memory_up_do) {
            frame.mode = .memory_up;
            frame.index = @bitCast(base);
            frame.limit = @bitCast(sum[0]);
            skip = length == 0;
        } else {
            frame.mode = .memory_down;
            frame.limit = @bitCast(base);
            skip = length < frame.stride;
            frame.index = @bitCast(if (skip) base else sum[0] - frame.stride);
        }
    } else if (kind == .for_loop) {
        frame.mode = .countdown;
        frame.index = try self.peek(0);
    } else {
        const start = try self.peek(0);
        const limit = try self.peek(1);
        frame.index = start;
        frame.limit = limit;
        const us: map.UCell = @bitCast(start);
        const ul: map.UCell = @bitCast(limit);
        skip = switch (kind) {
            .positive_do => start >= limit,
            .unsigned_positive_do => us >= ul,
            .negative_do => start <= limit,
            .unsigned_negative_do => us <= ul,
            .inclusive_negative_do => start < limit,
            .unsigned_inclusive_negative_do => us < ul,
            else => unreachable,
        };
    }
    if ((!skip or keep) and self.loop_depth == self.loop_stack.len) return error.StackOverflow;
    self.data_depth -= count;
    if (!skip or keep) {
        self.loop_stack[self.loop_depth] = frame;
        self.loop_depth += 1;
    }
    return skip;
}

pub fn finish(self: *forth.State, kind: defs.OpKind) forth.RuntimeError!bool {
    if (self.loop_depth == 0) return error.LoopMismatch;
    const step: map.UCell = if (kind == .negative_loop) @bitCast(try self.pop()) else 0;
    const frame = &self.loop_stack[self.loop_depth - 1];
    var again: bool = undefined;
    switch (frame.mode) {
        .countdown => {
            if (kind != .next_loop) return error.LoopMismatch;
            again = frame.index != 0;
            frame.index -%= 1;
        },
        .memory_up => {
            const distance = @as(map.UCell, @bitCast(frame.limit)) -% @as(map.UCell, @bitCast(frame.index));
            again = frame.stride < distance;
            frame.index +%= @bitCast(frame.stride);
        },
        .memory_down => {
            const distance = @as(map.UCell, @bitCast(frame.index)) -% @as(map.UCell, @bitCast(frame.limit));
            again = frame.stride <= distance;
            frame.index -%= @bitCast(frame.stride);
        },
        .normal => {
            if (kind != .negative_loop) return error.LoopMismatch;
            const distance = @as(map.UCell, @bitCast(frame.index)) -% @as(map.UCell, @bitCast(frame.limit));
            again = !frame.exit_after_first and (step == 0 or step < distance);
            frame.index -%= @bitCast(step);
        },
    }
    if (!again) self.loop_depth -= 1;
    return again;
}
