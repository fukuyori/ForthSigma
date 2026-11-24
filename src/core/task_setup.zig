//! Worker setup boundaries; hooks exist only in unit tests, never in a host VM.
const builtin = @import("builtin");
const Cancellation = @import("runtime_base.zig").Cancellation;
pub const Stage = enum { zero_chunk, allocation_chunk, state_reserved, state_chunk, state_initialized_chunk, snapshot_retained, memory_allocated, data_allocated, return_allocated, float_allocated, loops_allocated, frames_allocated, catches_allocated, storage_zeroed, state_allocated, storage_allocated, initialized, plan_allocated, restore_validated, restore_applied, restored, plan_released, fresh_checked, resolved, grants_ready, permissions_checked, input_ready };
pub const Hook = struct {
    context: ?*anyopaque,
    visit: *const fn (?*anyopaque, Stage) void,
};
pub const Control = struct {
    cancellation: *const Cancellation,
    hook: if (builtin.is_test) ?Hook else void = if (builtin.is_test) null else {},
    pub fn check(self: Control, stage: Stage) error{TaskCancelled}!void {
        if (comptime builtin.is_test) if (self.hook) |hook| hook.visit(hook.context, stage);
        self.cancellation.stamp(switch (stage) {
            .zero_chunk => .zero_chunk,
            .allocation_chunk => .allocation_chunk,
            .state_reserved => .state_reserved,
            .state_chunk => .state_chunk,
            .state_initialized_chunk => .state_initialized_chunk,
            .snapshot_retained => .snapshot_retained,
            .memory_allocated => .memory_allocated,
            .data_allocated => .data_allocated,
            .return_allocated => .return_allocated,
            .float_allocated => .float_allocated,
            .loops_allocated => .loops_allocated,
            .frames_allocated => .frames_allocated,
            .catches_allocated => .catches_allocated,
            .storage_zeroed => .storage_zeroed,
            .state_allocated => .state_allocated,
            .storage_allocated => .storage_allocated,
            .initialized => .initialized,
            .plan_allocated => .plan_allocated,
            .restore_validated => .restore_validated,
            .restore_applied => .restore_applied,
            .restored => .restored,
            .plan_released => .plan_released,
            .fresh_checked => .fresh_checked,
            .resolved => .resolved,
            .grants_ready => .grants_ready,
            .permissions_checked => .permissions_checked,
            .input_ready => .input_ready,
        });
        if (self.cancellation.checkpoint()) return error.TaskCancelled;
    }
};
