//! One synchronous job, with a fresh VM on every call. No queue or public ABI.
const std = @import("std");
const snapshot = @import("task_snapshot.zig");
const permissions = @import("task_permissions.zig");
const transfer = @import("task_transfer.zig");
const Cancellation = @import("runtime_base.zig").Cancellation;
pub const Options = struct { max_native_bytes: usize = 64 * 1024 };

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
    return runWithOptions(allocator, admission, entry_name, input, cancellation, limits, .{});
}

pub fn runWithOptions(allocator: std.mem.Allocator, admission: *snapshot.Admission, entry_name: []const u8, input: []const u8, cancellation: *const Cancellation, limits: transfer.Limits, options: Options) ![]u8 {
    defer admission.deinit();
    try limits.validate();
    if (cancellation.isRequested()) return error.TaskCancelled;
    var vm = try snapshot.FreshVm.create(allocator, admission);
    defer vm.deinit();
    if (cancellation.isRequested()) return error.TaskCancelled;
    try transfer.checkFresh(vm.state);
    const entry = try vm.resolve(entry_name);
    var grants = try @import("task_memory.zig").Grants.init(allocator, vm.state);
    defer grants.deinit(allocator);
    const gate = grants.gate();
    const installed: permissions.Options = .{ .memory_gate = &gate, .max_native_bytes = options.max_native_bytes };
    _ = try permissions.inspect(allocator, vm.state, entry, installed);
    try transfer.prepareInput(vm.state, input, limits);
    // No image export/relocation or heap allocation is admitted in a worker.
    // Results are raw bytes and the VM is destroyed, so retaining relocation
    // tracking would add unbounded metadata work to ordinary memory writes.
    vm.state.addresses = .{};
    try vm.state.runAsWorkerWithMemory(entry, cancellation, installed);
    return transfer.copyResult(vm.state, allocator, limits);
}
