//! One synchronous job, with a fresh VM on every call. No queue or public ABI.
const std = @import("std");
const forth = @import("../forth.zig");
const snapshot = @import("task_snapshot.zig");
const permissions = @import("task_permissions.zig");
const transfer = @import("task_transfer.zig");
const Cancellation = @import("runtime_base.zig").Cancellation;
const setup = @import("task_setup.zig");
pub const Options = struct {
    max_native_bytes: usize = 64 * 1024,
    diagnostic_code: ?*forth.Cell = null,
    storage_zeroed: bool = false,
    retired_vm: ?*?snapshot.FreshVm = null,
    setup_hook: if (@import("builtin").is_test) ?setup.Hook else void = if (@import("builtin").is_test) null else {},
};

/// Consumes `admission` on ALL exits, including allocation/validation failure.
/// Caller must not reuse or deinit that reference. Admission must have been made
/// under main-owner serialization; an already admitted old version stays valid.
/// Entry/input/token are borrowed until return, without host callbacks or threads.
/// Input is copied directly into the VM-owned data area; no second input buffer.
/// Success returns an independent allocation, freed with `allocator` by caller.
/// Errors return no result. By default all resources are released on return;
/// a queue retirement owner may instead retain the private VM through collection.
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
    cancellation.stamp(.vm_start);
    try limits.validate();
    if (cancellation.checkpoint()) return error.TaskCancelled;
    const control: setup.Control = .{ .cancellation = cancellation, .hook = options.setup_hook };
    var vm = try snapshot.FreshVm.createWithOptions(allocator, admission, .{ .storage_zeroed = options.storage_zeroed, .control = control, .retired_vm = options.retired_vm });
    defer {
        if (options.retired_vm) |retired| retired.* = vm else vm.deinit();
    }
    try transfer.checkFresh(vm.state);
    try control.check(.fresh_checked);
    const entry = try vm.resolve(entry_name);
    try control.check(.resolved);
    var grants = try @import("task_memory.zig").Grants.init(allocator, vm.state);
    defer grants.deinit(allocator);
    try control.check(.grants_ready);
    const gate = grants.gate();
    const installed: permissions.Options = .{ .memory_gate = &gate, .max_native_bytes = options.max_native_bytes };
    _ = try permissions.inspect(allocator, vm.state, entry, installed);
    try control.check(.permissions_checked);
    try transfer.prepareInput(vm.state, input, limits);
    try control.check(.input_ready);
    // No image export/relocation or heap allocation is admitted in a worker.
    // Results are raw bytes and the VM is destroyed, so retaining relocation
    // tracking would add unbounded metadata work to ordinary memory writes.
    vm.state.addresses = .{};
    cancellation.stamp(.prepared);
    vm.state.runAsWorkerWithMemory(entry, cancellation, installed) catch |err| {
        cancellation.stamp(.forth_return);
        if (options.diagnostic_code) |code| code.* = if (err == error.TaskCancelled) 0 else vm.state.throwCodeOf(err);
        return err;
    };
    cancellation.stamp(.forth_return);
    return transfer.copyResult(vm.state, allocator, limits);
}
