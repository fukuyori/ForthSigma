//! Read-only append preflight; commits are separate from this borrowed plan.
const forth = @import("../forth.zig");
const defs = @import("defs.zig");
const map = @import("memory_map.zig");
const registry = @import("address_registry.zig");
const full = @import("image_restore_plan.zig");
const RuntimeError = defs.RuntimeError;

pub const Plan = struct {
    image: full.Plan = undefined,
    word_base: usize = 0,
    code_base: usize = 0,
    name_base: usize = 0,
    data_delta: map.Cell = 0,
    data_here: map.Cell = 0,
    wordlist_base: map.Cell = 0,
};

/// Input must be separate from State. A successful plan borrows input and itself,
/// must not be copied, and is invalidated by any target State change.
pub fn prepare(state: *forth.State, bytes: []const u8, plan: *Plan) RuntimeError!void {
    try full.prepare(state, bytes, &plan.image);
    try registry.validate(state);
    const view = plan.image.view;
    const h = view.header;
    const added_words = h.word_count - h.builtin_count;
    const added_names = h.names_used - plan.image.image_names;
    const added_data = @as(map.Cell, h.data_here) - map.data_start;
    if (added_words > state.words.len - state.word_count) return error.DictionaryFull;
    if (h.code_count > state.code.len - state.code_count) return error.CodeFull;
    if (added_names > state.names.len - state.names_used) return error.DictionaryFull;
    if (added_data > state.sizes.dataLimit() - state.data_here) return error.MemoryExhausted;
    if (h.relocation_count > registry.capacity - state.addresses.count) return error.MemoryExhausted;
    const saved_lists = cell(view.memory, map.wordlist_count_address);
    const own_lists = state.wordlistCount();
    if (saved_lists - map.ekeys_wordlist > map.max_wordlists - own_lists) return error.DictionaryFull;
    plan.wordlist_base = own_lists;
    plan.word_base = state.word_count;
    plan.code_base = state.code_count;
    plan.name_base = state.names_used;
    plan.data_delta = state.data_here - map.data_start;
    plan.data_here = state.data_here + added_data;
    // Appends always allocate new blocks at the tail, never consume existing free
    // blocks, so the plan cannot perturb any target allocation or its lifetime.
    var top = state.heapTop();
    if (top < state.sizes.heapBase() or top > state.sizes.heapEnd()) return error.InvalidAddress;
    for (view.objects, 0..) |object, i| {
        const needed: map.Cell = @intCast(map.heap_header + object.bytes.len);
        if (needed > state.sizes.heapEnd() - top) return error.MemoryExhausted;
        plan.image.object_addresses[i] = top + map.heap_header;
        top += needed;
    }
    plan.image.heap_top = top;
    for (0..h.relocation_count) |i| {
        const wire = try view.relocation(i);
        var record = &plan.image.records[i];
        record.slot = switch (wire.storage) {
            .word => @intCast(plan.word_base + wire.word_id - h.builtin_count),
            .system => @intCast(wire.slot_offset),
            .data => state.data_here + @as(map.Cell, @intCast(wire.slot_offset)),
            .heap => try heapAddress(plan, wire.slot_offset, 8),
        };
        record.value = switch (wire.target) {
            .null_address => 0,
            .system => @intCast(wire.target_offset),
            .data => state.data_here + @as(map.Cell, @intCast(wire.target_offset)),
            .heap => try heapAddress(plan, wire.target_offset, 1),
        };
        // User decision: conflicting fixed slots fail before any mutation.
        // Overlapping cells conflict too, even when their start differs.
        if (wire.storage == .system) {
            for (state.addresses.records[0..state.addresses.count]) |existing| {
                if (existing.kind == .memory and @as(i128, existing.slot) < @as(i128, record.slot) + 8 and @as(i128, record.slot) < @as(i128, existing.slot) + 8) return error.InvalidImage;
            }
        }
    }
}
fn heapAddress(plan: *const Plan, offset: u64, width: usize) RuntimeError!map.Cell {
    for (plan.image.view.objects, 0..) |object, i| {
        if (offset >= object.payload_offset and offset - object.payload_offset <= object.bytes.len and width <= object.bytes.len - (offset - object.payload_offset)) return plan.image.object_addresses[i] + @as(map.Cell, @intCast(offset - object.payload_offset));
    }
    return error.InvalidImage;
}
fn cell(bytes: []const u8, address: map.Cell) map.Cell {
    return @import("std").mem.readInt(map.Cell, bytes[@intCast(address)..][0..8], .little);
}

/// Relocate an already structurally validated entry without touching target State.
/// Source-file IDs are mapped separately when merging the source-file table.
pub fn relocatedWord(plan: *const Plan, index: usize) RuntimeError!defs.Word {
    const view = plan.image.view;
    const h = view.header;
    if (index < h.builtin_count or index >= h.word_count) return error.InvalidImage;
    var word = @import("std").mem.bytesToValue(defs.Word, view.words[index * @sizeOf(defs.Word) ..][0..@sizeOf(defs.Word)]);
    word.name_start = @intCast(plan.name_base + word.name_start - plan.image.image_names);
    word.data_here_before += plan.data_delta;
    word.wordlist = @intCast(relocatedWordlist(plan, word.wordlist));
    if (word.kind == .vocabulary) word.value = relocatedWordlist(plan, word.value);
    if (word.kind == .synonym) word.value = relocatedId(plan, word.value);
    if (word.kind == .colon) {
        word.code_start += @intCast(plan.code_base);
        word.code_end += @intCast(plan.code_base);
    }
    if (word.has_does) {
        word.does_code_start += @intCast(plan.code_base);
        word.does_code_end += @intCast(plan.code_base);
    }
    switch (word.kind) {
        .variable, .array, .created, .value, .fvalue, .two_constant, .two_value, .marker, .deferred => word.value += plan.data_delta,
        else => {},
    }
    // Address constants use explicit type records; raw constants stay unchanged.
    for (plan.image.records[0..h.relocation_count]) |record| {
        if (record.kind == .word and record.slot == relocatedId(plan, @intCast(index))) word.value = record.value;
    }
    return word;
}

pub fn relocatedOperation(plan: *const Plan, index: usize) RuntimeError!defs.Op {
    const view = plan.image.view;
    if (index >= view.header.code_count) return error.InvalidImage;
    var op = @import("std").mem.bytesToValue(defs.Op, view.code[index * @sizeOf(defs.Op) ..][0..@sizeOf(defs.Op)]);
    switch (op.kind) {
        .call, .compile_call, .execution_token, .store_value, .add_value, .local_frame => op.value = relocatedId(plan, op.value),
        .branch, .branch_zero, .do_loop, .q_do_loop, .loop, .plus_loop => op.value += @intCast(plan.code_base),
        .print_string, .string_literal, .counted_string, .abort_string => op.value += plan.data_delta,
        else => {},
    }
    return op;
}

pub fn relocatedWordlist(plan: *const Plan, wid: map.Cell) map.Cell {
    return if (wid <= map.ekeys_wordlist) wid else plan.wordlist_base + wid - map.ekeys_wordlist;
}
fn relocatedId(plan: *const Plan, id: map.Cell) map.Cell {
    return if (id < plan.image.view.header.builtin_count) id else @as(map.Cell, @intCast(plan.word_base)) + id - plan.image.view.header.builtin_count;
}
