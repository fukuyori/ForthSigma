//! One synchronous job, with a fresh VM on every call. No queue or public ABI.
const std = @import("std");
const snapshot = @import("task_snapshot.zig");
const permissions = @import("task_permissions.zig");
const transfer = @import("task_transfer.zig");
const Cancellation = @import("runtime_base.zig").Cancellation;

// Analysis only. Never installed or used to authorize runtime memory access.
const unavailable_gate: permissions.MemoryGate = .{ .context = &gate_context, .check = denyMemory };
const gate_context: u8 = 0;
fn denyMemory(_: *const anyopaque, _: []const permissions.Access, _: usize) bool {
    return false;
}

/// Consumes `admission` on ALL exits, including allocation/validation failure.
/// Caller must not reuse or deinit that reference. Admission must have been made
/// under main-owner serialization; an already admitted old version stays valid.
/// Entry/input/token are borrowed until return, without host callbacks or threads.
/// Input is copied directly into the VM-owned data area; no second input buffer.
/// Success returns an independent allocation, freed with `allocator` by caller.
/// Errors (including TaskCancelled) return no result and release all job resources.
/// No late token check overrides successful execution; terminal publication and
/// shared byte accounting belong to 1364/1366, not this synchronous function.
/// Order: validate limits, create/restore VM, check freshness, resolve entry,
/// inspect permissions, copy input, execute, then validate/copy the result.
pub fn run(
    allocator: std.mem.Allocator,
    admission: *snapshot.Admission,
    entry_name: []const u8,
    input: []const u8,
    cancellation: *const Cancellation,
    limits: transfer.Limits,
) ![]u8 {
    defer admission.deinit();
    try limits.validate();
    var vm = try snapshot.FreshVm.create(allocator, admission);
    defer vm.deinit();
    try transfer.checkFresh(vm.state);
    const entry = try vm.resolve(entry_name);
    const requirements = try permissions.inspect(allocator, vm.state, entry, .{ .memory_gate = &unavailable_gate });
    // 1373 must connect EVERY memory path to the actual per-VM MemoryGate
    // before this restriction can be relaxed. A supplied dummy gate is no grant.
    if (requirements.memory_gate != null) return error.MemoryChecksRequired;
    try transfer.prepareInput(vm.state, input, limits);
    try vm.state.runAsWorker(entry, cancellation);
    return transfer.copyResult(vm.state, allocator, limits);
}
