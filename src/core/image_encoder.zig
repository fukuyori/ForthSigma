//! State-to-SIGIMG45/46/47 encoding. Not yet the public SAVE implementation.
const std = @import("std");
const forth = @import("../forth.zig");
const defs = @import("defs.zig");
const map = @import("memory_map.zig");
const format = @import("image_format.zig");
const graph = @import("image_graph.zig");
const inline_calls = @import("inline_calls.zig");
const RuntimeError = defs.RuntimeError;

pub const Workspace = struct {
    graph: graph.Graph = undefined,
    validation: format.Workspace = undefined,
};

/// Collects/validates references before calculating the exact buffer requirement.
/// The caller must not change State between measure and consuming the workspace.
pub fn measure(state: *forth.State, workspace: *Workspace) RuntimeError!usize {
    try graph.collect(state, &workspace.graph);
    const h = header(state, &workspace.graph);
    return @intCast(format.header_size + h.word_bytes + h.code_bytes + h.name_bytes + h.memory_bytes + h.relocation_bytes + h.heap_bytes + format.checksum_size);
}

pub fn encode(state: *forth.State, output: []u8, workspace: *Workspace) RuntimeError!usize {
    const required = try measure(state, workspace);
    if (output.len < required) return error.InvalidImage;
    const h = header(state, &workspace.graph);
    format.writeHeader(output[0..format.header_size], h);
    var cursor: usize = format.header_size;
    for (state.words[0..state.word_count]) |word| {
        format.writeWord(output[cursor..][0..@sizeOf(defs.Word)], word);
        cursor += @sizeOf(defs.Word);
    }
    var inline_end: usize = 0;
    for (state.code[0..state.code_count], 0..) |original, index| {
        var op = original;
        if (index < inline_end) {
            op = .{ .kind = .branch, .value = @intCast(inline_end) };
        } else if (inline_calls.isInline(op)) {
            const span = inline_calls.span(op.value);
            if (span > state.code_count - index) return error.InvalidImage;
            inline_end = index + span;
            op = .{ .kind = .call, .value = inline_calls.wordId(op.value) };
        } else if (op.kind == .call_colon) {
            op.kind = .call;
        } else if (defs.isPrimitiveOp(op.kind)) {
            op.kind = .call_builtin;
        }
        try format.writeOperation(output[cursor..][0..@sizeOf(defs.Op)], op);
        cursor += @sizeOf(defs.Op);
    }
    copy(output, &cursor, state.names[0..state.names_used]);
    copy(output, &cursor, state.memory[0..@intCast(map.system_end)]);
    copy(output, &cursor, state.memory[@intCast(map.data_start)..@intCast(state.data_here)]);
    copy(output, &cursor, state.memory[@intCast(map.source_file_table)..@intCast(map.source_file_loaded_flags + map.max_source_files)]);
    for (workspace.graph.records[0..workspace.graph.record_count]) |record| {
        format.writeRelocation(output[cursor..][0..format.record_size], record);
        cursor += format.record_size;
    }
    for (workspace.graph.objects[0..workspace.graph.object_count], 0..) |object, id| {
        format.writeObjectHeader(output[cursor..][0..format.object_header_size], @intCast(id), object.payload_offset, object.bytes.len);
        cursor += format.object_header_size;
        copy(output, &cursor, object.bytes);
    }
    try format.finish(output[0..required]);
    // Structural validation also checks engine-generated Word/Op values. State is
    // still untouched if these turn out not to be representable in the format.
    _ = try format.parse(output[0..required], &workspace.validation);
    return required;
}

fn copy(output: []u8, cursor: *usize, bytes: []const u8) void {
    @memcpy(output[cursor.*..][0..bytes.len], bytes);
    cursor.* += bytes.len;
}
fn header(state: *forth.State, collected: *const graph.Graph) format.Header {
    var heap_bytes: u64 = 0;
    for (collected.objects[0..collected.object_count]) |object| heap_bytes += format.object_header_size + object.bytes.len;
    return .{
        .kind = if (state.readCellConst(map.audio_image_address) != 0) .audio else if (state.readCellConst(map.graphics_image_address) != 0) .graphics else .normal,
        .word_count = state.word_count,
        .code_count = state.code_count,
        .data_here = @intCast(state.data_here),
        .names_used = @intCast(state.names_used),
        .m = @intCast(state.sizes.m),
        .l = @intCast(state.sizes.l),
        .relocation_count = @intCast(collected.record_count),
        .object_count = @intCast(collected.object_count),
        .word_bytes = @as(u64, state.word_count) * @sizeOf(defs.Word),
        .code_bytes = @as(u64, state.code_count) * @sizeOf(defs.Op),
        .name_bytes = state.names_used,
        .memory_bytes = format.memoryLength(@intCast(state.data_here)),
        .relocation_bytes = collected.record_count * format.record_size,
        .heap_bytes = heap_bytes,
        .builtin_count = state.builtin_count,
    };
}
