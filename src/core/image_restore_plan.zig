//! Non-mutating preflight for a complete typed-image restore.
//! Applying this plan and append semantics are implemented separately.
const std = @import("std");
const forth = @import("../forth.zig");
const defs = @import("defs.zig");
const map = @import("memory_map.zig");
const format = @import("image_format.zig");
const registry = @import("address_registry.zig");
const RuntimeError = defs.RuntimeError;

pub const Plan = struct {
    validation: format.Workspace = undefined,
    view: format.View = undefined,
    own_names: usize = 0,
    image_names: usize = 0,
    names_used: usize = 0,
    heap_top: map.Cell = 0,
    object_addresses: [registry.capacity]map.Cell = undefined,
    records: [registry.capacity]registry.Record = undefined,
};

/// The plan borrows image and its own validation workspace. It must not be copied
/// or consumed after State changes. No target resource or dictionary is modified.
pub fn prepare(state: *const forth.State, image: []const u8, plan: *Plan) RuntimeError!void {
    plan.view = try format.parse(image, &plan.validation);
    const view = plan.view;
    const h = view.header;
    if (h.m != state.sizes.m or h.l != state.sizes.l or h.builtin_count != state.builtin_count) return error.InvalidImage;
    for (state.words[0..state.builtin_count], 0..) |own, i| {
        const saved = wordAt(view, i);
        if (saved.kind != own.kind or saved.builtin != own.builtin) return error.InvalidImage;
    }
    plan.own_names = namesEnd(state.words[0..state.builtin_count]);
    plan.image_names = if (state.builtin_count == 0) 0 else blk: {
        const last = wordAt(view, state.builtin_count - 1);
        break :blk @as(usize, last.name_start) + last.name_len;
    };
    const added_names = h.names_used - plan.image_names;
    if (plan.own_names > state.names.len or added_names > state.names.len - plan.own_names) return error.DictionaryFull;
    if (h.word_count > state.words.len) return error.DictionaryFull;
    if (h.code_count > state.code.len) return error.CodeFull;
    plan.names_used = plan.own_names + added_names;
    var top = state.sizes.heapBase();
    for (view.objects, 0..) |object, i| {
        const needed: map.Cell = @intCast(map.heap_header + object.bytes.len);
        if (needed > state.sizes.heapEnd() - top) return error.MemoryExhausted;
        plan.object_addresses[i] = top + map.heap_header;
        top += needed;
    }
    plan.heap_top = top;
    for (0..h.relocation_count) |i| {
        const record = try view.relocation(i);
        const slot: map.Cell = switch (record.storage) {
            .word => record.word_id,
            .system => @intCast(record.slot_offset),
            .data => map.data_start + @as(map.Cell, @intCast(record.slot_offset)),
            .heap => try relocateHeap(plan, record.slot_offset, 8),
        };
        const value: map.Cell = switch (record.target) {
            .null_address => 0,
            .system => @intCast(record.target_offset),
            .data => map.data_start + @as(map.Cell, @intCast(record.target_offset)),
            .heap => try relocateHeap(plan, record.target_offset, 1),
        };
        plan.records[i] = .{
            .kind = if (record.storage == .word) .word else .memory,
            .slot = slot,
            .value = value,
            .target = switch (record.target) {
                .null_address => .null_address,
                .system => .system,
                .data => .data,
                .heap => .heap,
            },
            .status = .valid,
        };
    }
}

fn wordAt(view: format.View, i: usize) defs.Word {
    return std.mem.bytesToValue(defs.Word, view.words[i * @sizeOf(defs.Word) ..][0..@sizeOf(defs.Word)]);
}
fn namesEnd(words: []const defs.Word) usize {
    if (words.len == 0) return 0;
    const last = words[words.len - 1];
    return @as(usize, last.name_start) + last.name_len;
}
fn relocateHeap(plan: *const Plan, offset: u64, width: usize) RuntimeError!map.Cell {
    for (plan.view.objects, 0..) |object, i| {
        if (offset >= object.payload_offset and offset - object.payload_offset <= object.bytes.len and width <= object.bytes.len - (offset - object.payload_offset)) return plan.object_addresses[i] + @as(map.Cell, @intCast(offset - object.payload_offset));
    }
    return error.InvalidImage;
}
