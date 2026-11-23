//! Internal byte ABI for a task-owned, freshly allocated VM. No public Forth ABI.
//! The caller exclusively owns the VM throughout preparation, execution and copying.
const std = @import("std");
const forth = @import("../forth.zig");

pub const default_input_limit = 2 * 1024 * 1024;
pub const default_result_limit = 512 * 1024;
pub const transfer_total_limit = 16 * 1024 * 1024;

/// The queue/collection owner (1364/1366) must reserve bytes against the shared
/// transfer_total_limit before allocating/copying and release on every exit,
/// including queue failure, cancellation and collection. Count concurrent copies.
/// This stateless module does not own that shared accounting.
pub const Limits = struct {
    input: usize = default_input_limit,
    result: usize = default_result_limit,

    pub fn validate(self: Limits) error{InvalidLimits}!void {
        if (self.input > default_input_limit or self.result > default_result_limit)
            return error.InvalidLimits;
    }
};

pub const PreflightError = error{
    HaltedVm,
    ActiveVm,
    NonEmptyStacks,
    CapturingVm,
    CountedVm,
    InvalidDataSpace,
};

/// Checks active state, not the contents of inactive/uninitialized storage slots.
/// This cannot prove fresh allocation, callback isolation or dictionary safety:
/// those remain obligations of the VM owner and the allowed-word validator.
pub fn checkFresh(vm: *const forth.State) PreflightError!void {
    if (vm.halted) return error.HaltedVm;
    if (vm.loop_depth != 0 or vm.catch_depth != 0 or vm.frame_depth != 0 or
        vm.call_depth != 0 or vm.compiling or vm.control_depth != 0 or
        vm.quote_depth != 0 or vm.interpret_loop_depth != 0 or
        vm.include_depth != 0 or vm.block_depth != 0 or vm.hold_depth != 0 or
        vm.defining or vm.pending != .none or vm.postponing or vm.quote_closing or
        vm.noname_next or vm.local_count != 0 or vm.locals_frame_size != 0 or
        vm.locals_top != vm.sizes.localsBase() or vm.assert_depth != 0 or
        vm.backtrace_suppression != 0 or vm.source_kind != .terminal or
        vm.source_line.len != 0 or vm.wrap_guard != null or vm.abort_message != null or
        vm.sh_get_result != null or !std.meta.eql(vm.block_storage, @as(@TypeOf(vm.block_storage), .{})))
        return error.ActiveVm;
    if (vm.data_depth != 0 or vm.return_depth != 0 or vm.float_depth != 0)
        return error.NonEmptyStacks;
    if (vm.capture_sink != null or vm.capture_target != null or
        vm.output_file != null or vm.input_file != null or vm.output_error != null or vm.report_capturing) return error.CapturingVm;
    if (vm.in_counted or vm.keep_counting or vm.step_limit != 0 or
        vm.tracing or vm.profile != null or vm.lint != null or vm.line_trace or
        vm.cell_watch_count != 0 or vm.watched_count != 0 or vm.stepper != .off or
        @import("execution_control.zig").active(vm))
        return error.CountedVm;
    if (vm.data_here < forth.data_start or vm.data_here > vm.sizes.dataLimit() or
        vm.sizes.m > vm.memory.len) return error.InvalidDataSpace;
}

pub const InputError = PreflightError || error{ InputTooLarge, InputSpaceExhausted, InputStackTooSmall, InvalidLimits };

/// Reserve HERE bytes and install (input-addr input-len), before publishing a job.
/// All failure checks precede mutation. `input` is borrowed and is never consumed.
/// On later queue failure the owner discards this fresh VM, retaining caller input.
/// No PAD, system buffer or host pointer is exposed to Forth. Both ends are cell
/// aligned, including empty input (which may reserve leading alignment padding).
/// REQUIRED: Storage.allocate(allocator, false, sizes), or an allocator guaranteed
/// to return zero-filled storage with already_zero=true, followed by State.init.
/// State carries no allocation provenance; checkFresh cannot verify this contract.
/// Snapshot restoration must preserve initialization of all data through dataLimit().
pub fn prepareInput(vm: *forth.State, input: []const u8, limits: Limits) InputError!void {
    try limits.validate();
    try checkFresh(vm);
    if (input.len > limits.input) return error.InputTooLarge;
    if (vm.data_stack.len < 2) return error.InputStackTooSmall;
    const here: usize = @intCast(vm.data_here);
    const limit: usize = @intCast(vm.sizes.dataLimit());
    const alignment = @import("memory_map.zig").cell_size;
    const leading = (alignment - here % alignment) % alignment;
    if (leading > limit - here) return error.InputSpaceExhausted;
    const start = here + leading;
    if (input.len > limit - start) return error.InputSpaceExhausted;
    const end = start + input.len;
    const trailing = (alignment - end % alignment) % alignment;
    if (trailing > limit - end) return error.InputSpaceExhausted;
    const aligned_end = end + trailing;
    // Bounds above prove both aligned additions cannot overflow.
    @memmove(vm.memory[start..end], input);
    @import("address_registry.zig").discardRange(vm, @intCast(start), @intCast(end), .data, false);
    vm.data_here = @intCast(aligned_end);
    vm.data_stack[0] = @intCast(start);
    vm.data_stack[1] = @intCast(input.len);
    vm.data_depth = 2;
}

pub const ResultError = error{
    InvalidLimits,
    ResultVmNotStopped,
    ResultStackDepth,
    ResultFloatStackNotEmpty,
    NegativeResultLength,
    ResultAddressOverflow,
    ResultOutsideDataSpace,
    ResultTooLarge,
};

/// Call only after successful execution has stopped. The VM must remain alive and
/// exclusively owned until copying completes. Heap payloads, locals and all lower
/// system/input/block areas are excluded by accepting only the data area.
/// HERE is not the upper bound: the ABI permits data anywhere up to dataLimit().
/// Even for zero bytes the address must be in [data_start, dataLimit()].
pub fn resultBytes(vm: *const forth.State, limits: Limits) ResultError![]const u8 {
    try limits.validate();
    if (vm.return_depth != 0 or vm.loop_depth != 0 or vm.compiling or
        vm.halted or vm.local_count != 0) return error.ResultVmNotStopped;
    if (vm.data_depth != 2 or vm.data_stack.len < 2) return error.ResultStackDepth;
    if (vm.float_depth != 0) return error.ResultFloatStackNotEmpty;
    const address = vm.data_stack[0];
    const length = vm.data_stack[1];
    if (length < 0) return error.NegativeResultLength;
    const sum = @addWithOverflow(address, length);
    if (sum[1] != 0) return error.ResultAddressOverflow;
    if (address < forth.data_start or sum[0] > vm.sizes.dataLimit() or
        vm.sizes.m > vm.memory.len) return error.ResultOutsideDataSpace;
    if (@as(u64, @intCast(length)) > limits.result) return error.ResultTooLarge;
    const start: usize = @intCast(address);
    const end: usize = @intCast(sum[0]);
    return vm.memory[start..end];
}

/// Returns a new allocation, freed by the caller with this same allocator.
/// Allocation failure and ABI failures leave the VM and its stacks unchanged.
/// The allocator must not use the worker's logical memory as its backing store.
pub fn copyResult(vm: *const forth.State, allocator: std.mem.Allocator, limits: Limits) (ResultError || std.mem.Allocator.Error)![]u8 {
    return allocator.dupe(u8, try resultBytes(vm, limits));
}
