//! Complete typed-image restore, staged separately from the public legacy entry.
const std = @import("std");
const forth = @import("../forth.zig");
const defs = @import("defs.zig");
const map = @import("memory_map.zig");
const preflight = @import("image_restore_plan.zig");
const inline_calls = @import("inline_calls.zig");
const RuntimeError = defs.RuntimeError;

/// image must be disjoint from State storage. The caller owns Plan so validation
/// and commit share one borrowed view without allocating during commit.
pub fn restore(state: *forth.State, image: []const u8, plan: *preflight.Plan) RuntimeError!void {
    try preflight.prepare(state, image, plan);
    apply(state, plan, false);
}

/// No fallible operations remain after successful preflight. Keep this private:
/// applying an out-of-date or failed plan is not supported.
pub fn restoreFresh(state: *forth.State, image: []const u8, plan: *preflight.Plan) RuntimeError!void {
    try preflight.prepare(state, image, plan);
    apply(state, plan, true);
}
fn apply(state: *forth.State, plan: *const preflight.Plan, memory_is_fresh: bool) void {
    const view = plan.view;
    const h = view.header;
    const builtins = state.builtin_count;
    state.addresses.count = 0;
    state.watched_count = 0;
    state.cell_watch_count = 0;
    for (builtins..h.word_count) |i| {
        var word = std.mem.bytesToValue(defs.Word, view.words[i * @sizeOf(defs.Word) ..][0..@sizeOf(defs.Word)]);
        word.name_start = @intCast(word.name_start - plan.image_names + plan.own_names);
        state.words[i] = word;
    }
    @memcpy(std.mem.sliceAsBytes(state.code[0..h.code_count]), view.code);
    @memcpy(state.names[plan.own_names..plan.names_used], view.names[plan.image_names..]);
    // Runtime block buffers survive restore, along with their host-side file state.
    if (!memory_is_fresh) {
        @memset(state.memory[0..@intCast(map.block_buffer_base)], 0);
        @memset(state.memory[@intCast(map.block_buffer_end)..], 0);
    }
    var cursor: usize = 0;
    for ([_][2]usize{
        .{ 0, @intCast(map.system_end) },
        .{ @intCast(map.data_start), h.data_here },
        .{ @intCast(map.source_file_table), @intCast(map.source_file_loaded_flags + map.max_source_files) },
    }) |range| {
        const length = range[1] - range[0];
        @memcpy(state.memory[range[0]..range[1]], view.memory[cursor..][0..length]);
        cursor += length;
    }
    for (view.objects, 0..) |object, i| {
        const address = plan.object_addresses[i];
        putCell(state, address - map.heap_header, @intCast(object.bytes.len));
        putCell(state, address - map.cell_size, 1);
        @memcpy(state.memory[@intCast(address)..][0..object.bytes.len], object.bytes);
    }
    putCell(state, map.heap_top_address, plan.heap_top);
    for (plan.records[0..h.relocation_count]) |record| {
        if (record.kind == .word) state.words[@intCast(record.slot)].value = record.value else putCell(state, record.slot, record.value);
    }
    putCell(state, map.blk_address, 0);
    state.names_used = @intCast(plan.names_used);
    state.word_count = @intCast(h.word_count);
    state.code_count = @intCast(h.code_count);
    state.data_here = h.data_here;
    @import("wordlists.zig").rebuildIndex(state);
    state.use_count = 0;
    if (defs.debug_enabled) {
        @memset(&state.code_lines, 0);
        @memset(&state.code_columns, 0);
    }
    for (state.code[0..state.code_count]) |*op| op.* = state.specializeCall(op.*);
    inline_calls.restore(state);
    if (defs.debug_enabled) @import("words_debug.zig").noteBreakpoints(state);
    state.data_depth = 0;
    state.return_depth = 0;
    state.float_depth = 0;
    state.control_depth = 0;
    state.loop_depth = 0;
    state.resetHold();
    state.setCompiling(false);
    state.defining = false;
    state.pending = .none;
    @import("words_graphics.zig").clearImage(state);
    @import("graphics_images.zig").releaseAll(state);
    if (defs.graphics_enabled) @import("tcl.zig").forgetHeap(state);
    @memcpy(state.addresses.records[0..h.relocation_count], plan.records[0..h.relocation_count]);
    state.addresses.count = h.relocation_count;
}
fn putCell(state: *forth.State, address: map.Cell, value: map.Cell) void {
    std.mem.writeInt(map.Cell, state.memory[@intCast(address)..][0..8], value, .little);
}
