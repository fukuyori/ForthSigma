//! Opt-in fixed per-token storage. No worker I/O or allocation.
const std = @import("std");
pub const enabled = @import("build_options").task_trace and @import("builtin").os.tag != .freestanding;
pub const Stage = enum { api_entry, request, token_before, token_after, acquired, vm_start, snapshot_retained, state_reserved, state_chunk, zero_chunk, state_initialized_chunk, allocation_chunk, memory_allocated, data_allocated, return_allocated, float_allocated, loops_allocated, frames_allocated, catches_allocated, storage_zeroed, state_allocated, storage_allocated, initialized, plan_allocated, restore_validated, restore_applied, restored, plan_released, fresh_checked, resolved, grants_ready, permissions_checked, input_ready, prepared, executing, forth_return, detected, runner_return, sealed, published, observed, host_stopped, deadline_check, deadline, native_before, native_running, native_after };
pub const Storage = if (enabled) struct {
    times: [@typeInfo(Stage).@"enum".field_names.len]std.atomic.Value(i64) = @splat(.init(0)),
    pub fn stamp(self: *@This(), stage: Stage) void {
        const now = @import("../host_clock.zig").now() catch return;
        self.stampAt(stage, now);
    }
    pub fn stampAt(self: *@This(), stage: Stage, now: i128) void {
        const value = std.math.cast(i64, now) orelse return;
        _ = self.times[@backingInt(stage)].cmpxchgStrong(0, value, .release, .monotonic);
    }
    pub fn dump(self: *const @This(), token: usize, event: []const u8) void {
        std.debug.print("TASKTRACE token={x} event={s}", .{ token, event });
        inline for (@typeInfo(Stage).@"enum".field_names, 0..) |name, index| {
            std.debug.print(" {s}={d}", .{ name, self.times[index].load(.acquire) });
        }
        std.debug.print("\n", .{});
    }
} else struct {};

// Startup-only configuration. Read by the host; never modified after workers start.
pub var cancel_at: ?Stage = null;
pub fn configure(value: ?[]const u8) !void {
    if (!enabled) return;
    cancel_at = if (value) |name| std.meta.stringToEnum(Stage, name) orelse return error.InvalidTaskTraceStage else null;
}
