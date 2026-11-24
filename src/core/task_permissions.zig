//! Internal worker admission policy. Inspect only the immutable, restored and optimized VM.
const std = @import("std");
const forth = @import("../forth.zig");
const defs = @import("defs.zig");
const inlining = @import("inline_calls.zig");
pub const Error = error{ InvalidCode, Denied, SynonymCycle, MemoryChecksRequired, DirtyVm, CountedMode };

/// Check the executing thread, not a caller-supplied VM or worker flag.
pub fn requireHostSubmission() error{Denied}!void {
    if (@import("task_context.zig").isWorkerThread()) return error.Denied;
}
pub const Options = struct {
    /// Explicit opt-in for deterministic host boundary tests only.
    test_host_probes: bool = false,
    /// Worker must install this exact gate before executing admitted code.
    memory_gate: ?*const MemoryGate = null,
    /// Proposal, not a public limit. Worker native operations must enforce this.
    max_native_bytes: usize = 64 * 1024,
};
pub const Requirements = struct {
    memory_gate: ?*const MemoryGate = null,
    max_native_bytes: usize,
};
/// Runtime integration contract for 1384/1373. Gate/context must outlive execution
/// and describe this VM only. Inspect does not install the gate in State.
/// Worker must reject execution unless EVERY logical access (primitive/string
/// paths included) goes through Requirements.memory_gate. Validate all ranges
/// together BEFORE any read/write. native_bytes includes total native work.
/// false denies the operation; no fallback to unchecked dispatch is permitted.
pub const Access = struct { address: forth.Cell, length: forth.Cell, write: bool };
pub const MemoryGate = struct {
    context: *const anyopaque,
    check: *const fn (*const anyopaque, []const Access, usize) bool,

    pub fn permits(self: *const MemoryGate, accesses: []const Access, native_bytes: usize, limit: usize) bool {
        return native_bytes <= limit and self.check(self.context, accesses, native_bytes);
    }
};
/// Runtime checker contract: no permissions for system/block/header/local storage.
/// Grants must describe payloads only, never broad enclosing allocation ranges.
pub const RegionKind = enum { input, dictionary_payload, heap_payload, system, block_buffer, heap_header, local_frame };
pub const Region = struct { start: usize, length: usize, writable: bool, kind: RegionKind };

pub fn checkAccess(grants: []const Region, address: forth.Cell, length: forth.Cell, write: bool, limit: usize) bool {
    if (address < 0 or length < 0) return false;
    const start = std.math.cast(usize, address) orelse return false;
    const size = std.math.cast(usize, length) orelse return false;
    if (size > limit) return false;
    // Protected ranges override payload grants, independent of order.
    for (grants) |grant| {
        switch (grant.kind) {
            .system, .block_buffer, .heap_header, .local_frame => {
                // Subtraction avoids overflowing either range's end.
                const intersects = if (start >= grant.start)
                    start - grant.start < grant.length
                else
                    grant.start - start < size;
                if (size != 0 and grant.length != 0 and intersects) return false;
            },
            else => {},
        }
    }
    for (grants) |grant| {
        switch (grant.kind) {
            .system, .block_buffer, .heap_header, .local_frame => continue,
            else => {},
        }
        if (write and !grant.writable) continue;
        if (start >= grant.start and start - grant.start <= grant.length and size <= grant.length - (start - grant.start)) return true;
    }
    return false;
}
pub const Policy = enum { allow, memory, deny };
pub fn policy(b: defs.Builtin) Policy {
    if (defs.isExcludedBuiltin(b)) return .deny;
    return switch (b) {
        .add => .allow,
        .sub => .allow,
        .mul => .allow,
        .div => .allow,
        .mod => .allow,
        .max => .allow,
        .min => .allow,
        .equal => .allow,
        .not_equal => .allow,
        .less => .allow,
        .greater => .allow,
        .less_equal => .allow,
        .greater_equal => .allow,
        .bit_and => .allow,
        .bit_or => .allow,
        .bit_xor => .allow,
        .bit_nand => .allow,
        .bit_nor => .allow,
        .lshift => .allow,
        .rshift => .allow,
        .div_mod => .allow,
        .swap_bytes => .allow,
        .negate => .allow,
        .abs => .allow,
        .one_plus => .allow,
        .one_minus => .allow,
        .two_star => .allow,
        .two_slash => .allow,
        .logical_not => .allow,
        .zero_equal => .allow,
        .zero_less => .allow,
        .zero_greater => .allow,
        .zero_greater_equal => .allow,
        .under_plus => .allow,
        .zero_not_equal => .allow,
        .bit_complement => .allow,
        .true_value => .allow,
        .false_value => .allow,
        .s_to_d => .allow,
        .d_to_s => .allow,
        .d_add => .allow,
        .d_sub => .allow,
        .d_negate => .allow,
        .d_abs => .allow,
        .d_zero_equal => .allow,
        .d_zero_less => .allow,
        .d_equal => .allow,
        .d_less => .allow,
        .within => .allow,
        .u_less => .allow,
        .u_greater => .allow,
        .star_slash => .allow,
        .star_slash_mod => .allow,
        .m_star => .allow,
        .um_star => .allow,
        .um_slash_mod => .allow,
        .fm_slash_mod => .allow,
        .sm_slash_rem => .allow,
        .d_two_star => .allow,
        .d_two_slash => .allow,
        .d_max => .allow,
        .d_min => .allow,
        .m_plus => .allow,
        .du_less => .allow,
        .m_star_slash => .allow,
        .rol => .allow,
        .ror => .allow,
        .arshift => .allow,
        .darshift => .allow,
        .dlshift => .allow,
        .drshift => .allow,
        .star_slash_f => .allow,
        .star_slash_mod_f => .allow,
        .star_slash_mod_s => .allow,
        .star_slash_s => .allow,
        .slash_f => .allow,
        .slash_mod_f => .allow,
        .slash_mod_s => .allow,
        .slash_s => .allow,
        .to_pow2 => .allow,
        .ctz => .allow,
        .drol => .allow,
        .dror => .allow,
        .du_slash_mod => .allow,
        .log2 => .allow,
        .lrol => .allow,
        .lror => .allow,
        .mod_f => .allow,
        .mod_s => .allow,
        .mux => .allow,
        .pow2_query => .allow,
        .u_star_slash => .allow,
        .u_star_slash_mod => .allow,
        .u_slash => .allow,
        .u_slash_mod => .allow,
        .ud_slash_mod => .allow,
        .u_mod => .allow,
        .wrol => .allow,
        .wror => .allow,
        .zero_less_equal => .allow,
        .d_zero_less_equal => .allow,
        .d_zero_not_equal => .allow,
        .d_zero_greater => .allow,
        .d_zero_greater_equal => .allow,
        .d_less_equal => .allow,
        .d_not_equal => .allow,
        .d_greater => .allow,
        .d_greater_equal => .allow,
        .du_less_equal => .allow,
        .du_greater => .allow,
        .du_greater_equal => .allow,
        .u_less_equal => .allow,
        .u_greater_equal => .allow,
        .u_max => .allow,
        .u_min => .allow,
        .drop => .allow,
        .dup => .allow,
        .swap => .allow,
        .over => .allow,
        .rot => .allow,
        .minus_rot => .allow,
        .nip => .allow,
        .tuck => .allow,
        .pick => .allow,
        .roll => .allow,
        .two_dup => .allow,
        .two_drop => .allow,
        .two_swap => .allow,
        .two_over => .allow,
        .depth => .allow,
        .to_r => .allow,
        .from_r => .allow,
        .r_fetch => .allow,
        .two_to_r => .allow,
        .two_r_from => .allow,
        .two_r_fetch => .allow,
        .question_dup => .allow,
        .two_rot => .allow,
        .n_to_r => .allow,
        .n_r_from => .allow,
        .two_nip => .allow,
        .two_r_drop => .allow,
        .two_tuck => .allow,
        .fourth => .allow,
        .r_drop => .allow,
        .third => .allow,
        .blank => .allow,
        .cell => .allow,
        .cells => .allow,
        .cell_plus => .allow,
        .cell_minus => .allow,
        .aligned => .allow,
        .fetch => .memory,
        .store => .memory,
        .cfetch => .memory,
        .cstore => .memory,
        .add_store => .memory,
        .inc_store => .memory,
        .dec_store => .memory,
        .zero_store => .memory,
        .off => .memory,
        .on => .memory,
        .array_fetch => .memory,
        .array_store => .memory,
        .erase => .memory,
        .fill => .memory,
        .move => .memory,
        .cmove => .memory,
        .two_fetch => .memory,
        .two_store => .memory,
        .count => .memory,
        .place => .memory,
        .compare => .memory,
        .search => .memory,
        .slash_string => .allow,
        .minus_trailing => .memory,
        .char_plus => .allow,
        .chars => .allow,
        .bounds => .allow,
        .blank_fill => .memory,
        .cmove_up => .memory,
        .scan => .memory,
        .skip => .memory,
        .str_equal => .memory,
        .string_prefix_query => .memory,
        .plus_place => .memory,
        .array_to_mem => .allow,
        .f_add => .allow,
        .f_sub => .allow,
        .f_mul => .allow,
        .f_div => .allow,
        .f_dup => .allow,
        .f_drop => .allow,
        .f_swap => .allow,
        .f_over => .allow,
        else => .deny,
    };
}
const Dictionary = struct {
    words: []align(1) const defs.Word,
    code: []align(1) const defs.Op,
    memory: []const u8,
    word_count: usize,
    code_count: usize,
    builtin_count: usize,
    image_memory: bool = false,
    fn stringValid(self: *const Dictionary, raw: forth.Cell) bool {
        const map = @import("memory_map.zig");
        if (raw < 0) return false;
        var address: usize = @intCast(raw);
        if (self.image_memory) {
            if (raw < map.data_start) return false;
            address = address - @as(usize, @intCast(map.data_start)) + @as(usize, @intCast(map.system_end));
        }
        if (address >= self.memory.len) return false;
        return self.memory[address] <= self.memory.len - address - 1;
    }
};
const Inspector = struct {
    vm: *const Dictionary,
    options: Options,
    requirements: Requirements,
    marks: []u8,
    pending: []u16,
    pending_count: usize = 0,
    fn enqueue(self: *Inspector, target: u16) Error!void {
        if (target >= self.vm.word_count) return error.InvalidCode;
        if (self.marks[target] != 0) return;
        self.marks[target] = 1;
        self.pending[self.pending_count] = target;
        self.pending_count += 1;
    }
    fn builtin(self: *Inspector, b: defs.Builtin) Error!void {
        switch (policy(b)) {
            .allow => {},
            .deny => return error.Denied,
            .memory => {
                if (self.options.memory_gate == null) return error.MemoryChecksRequired;
                self.requirements.memory_gate = self.options.memory_gate;
            },
        }
    }
    fn id(self: *Inspector, value: forth.Cell) Error!u16 {
        if (value < 0 or value >= self.vm.word_count) return error.InvalidCode;
        return @intCast(value);
    }
    fn word(self: *Inspector, target: u16) Error!void {
        if (target >= self.vm.word_count) return error.InvalidCode;
        const w = self.vm.words[target];
        if (w.has_does) return error.Denied;
        if (w.kind == .synonym) {
            // Resolve separately: recursive colon calls are valid; synonym cycles are not.
            var at = target;
            var steps: usize = 0;
            while (self.vm.words[at].kind == .synonym) : (steps += 1) {
                if (steps >= self.vm.word_count) return error.SynonymCycle;
                if (self.vm.words[at].has_does) return error.Denied;
                at = try self.id(self.vm.words[at].value);
            }
            return self.enqueue(at);
        }
        switch (w.kind) {
            .builtin => try self.builtin(w.builtin),
            .colon => try self.code(w.code_start, w.code_end),
            .constant, .array, .variable, .created, .field => {},
            .fconstant => if (!defs.float_enabled) return error.Denied,
            else => return error.Denied,
        }
    }
    fn code(self: *Inspector, start: usize, end: usize) Error!void {
        if (start > end or end > self.vm.code_count) return error.InvalidCode;
        // Conservative whole-body scan, including both branch arms and dead slots.
        for (self.vm.code[start..end], start..) |op, pc| {
            switch (op.kind) {
                .call => try self.enqueue(try self.id(op.value)),
                .call_colon => {
                    if (inlining.isInline(op)) {
                        const target = try self.id(inlining.wordId(op.value));
                        if (self.vm.words[target].kind != .colon) return error.InvalidCode;
                        if (self.vm.words[target].has_does) return error.Denied;
                        const span = inlining.span(op.value);
                        if (span == 0 or span > end - pc or inlining.depth(op.value) == 0) return error.InvalidCode;
                        // VM executes the copied body, not the current original definition.
                    } else {
                        const target = try self.id(op.value);
                        if (self.vm.words[target].kind != .colon) return error.InvalidCode;
                        try self.enqueue(target);
                    }
                },
                .call_builtin => {
                    if (op.value < 0 or op.value >= self.vm.builtin_count or op.value >= self.vm.word_count) return error.InvalidCode;
                    try self.builtin(self.vm.words[@intCast(op.value)].builtin);
                },
                .builtin => {
                    if (op.value < 0 or op.value >= @typeInfo(defs.Builtin).@"enum".field_names.len) return error.InvalidCode;
                    try self.builtin(@fromBackingInt(@intCast(op.value)));
                },
                .literal, .exit => {},
                .execution_token => {
                    _ = try self.id(op.value);
                },
                .counted_string, .string_literal => {
                    if (!self.vm.stringValid(op.value)) return error.InvalidCode;
                    if (self.options.memory_gate == null) return error.MemoryChecksRequired;
                    self.requirements.memory_gate = self.options.memory_gate;
                },
                .float_literal => if (!defs.float_enabled) return error.Denied,
                .branch, .branch_zero => if (op.value < start or op.value > end) return error.InvalidCode,
                inline else => |kind| {
                    if (comptime defs.isPrimitiveOp(kind)) {
                        try self.builtin(comptime defs.primitiveBuiltin(kind));
                    } else return error.Denied;
                },
            }
        }
    }
};
/// Call after restore/specialize/inline; do not mutate VM before/during worker execution.
/// This is admission analysis, not a capability token or a replacement for runtime checks.
pub fn inspect(allocator: std.mem.Allocator, vm: *const forth.State, entry: u16, options: Options) (Error || std.mem.Allocator.Error)!Requirements {
    // Recheck execution state after restore even if 1361 checked the fresh VM.
    // Data/float inputs are allowed; return/control stacks must be empty.
    if (vm.halted or vm.compiling or vm.defining or vm.pending != .none or
        vm.return_depth != 0 or vm.loop_depth != 0 or vm.catch_depth != 0 or
        vm.frame_depth != 0 or vm.call_depth != 0 or vm.control_depth != 0 or
        vm.interpret_loop_depth != 0 or vm.quote_depth != 0 or vm.output_error != null)
        return error.DirtyVm;
    // Reject settings even in debug=false to keep admission independent of it.
    if (vm.step_limit != 0 or vm.tracing or vm.profile != null or
        vm.keep_counting or vm.in_counted or vm.stepper != .off or vm.cell_watch_count != 0)
        return error.CountedMode;
    if (comptime defs.debug_enabled) {
        if (vm.execution.depth != 0) return error.CountedMode;
    }
    if (vm.word_count > vm.words.len or vm.code_count > vm.code.len or vm.builtin_count > vm.word_count) return error.InvalidCode;
    const dictionary = Dictionary{ .words = vm.words[0..vm.word_count], .code = vm.code[0..vm.code_count], .memory = vm.memory, .word_count = vm.word_count, .code_count = vm.code_count, .builtin_count = vm.builtin_count };
    return inspectDictionary(allocator, &dictionary, entry, options);
}

/// Admission analysis of immutable serialized code; does not instantiate a VM.
/// Actual restored/specialized code is checked again by task_job before execution.
pub fn inspectImage(allocator: std.mem.Allocator, view: @import("image_format.zig").View, entry: u16, options: Options) (Error || std.mem.Allocator.Error)!Requirements {
    const dictionary = Dictionary{ .words = std.mem.bytesAsSlice(defs.Word, view.words), .code = std.mem.bytesAsSlice(defs.Op, view.code), .memory = view.memory, .word_count = view.header.word_count, .code_count = view.header.code_count, .builtin_count = view.header.builtin_count, .image_memory = true };
    return inspectDictionary(allocator, &dictionary, entry, options);
}
fn inspectDictionary(allocator: std.mem.Allocator, vm: *const Dictionary, entry: u16, options: Options) (Error || std.mem.Allocator.Error)!Requirements {
    const marks = try allocator.alloc(u8, vm.word_count);
    defer allocator.free(marks);
    @memset(marks, 0);
    const pending = try allocator.alloc(u16, vm.word_count);
    defer allocator.free(pending);
    var inspector = Inspector{ .vm = vm, .options = options, .requirements = .{ .max_native_bytes = options.max_native_bytes }, .marks = marks, .pending = pending };
    try inspector.enqueue(entry);
    while (inspector.pending_count != 0) {
        inspector.pending_count -= 1;
        try inspector.word(inspector.pending[inspector.pending_count]);
    }
    return inspector.requirements;
}
