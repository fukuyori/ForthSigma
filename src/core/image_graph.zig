//! Collects the explicitly typed, rooted heap graph without changing State.
//! Internal pointer producers must register their slots before calling collect.
const forth = @import("../forth.zig");
const map = @import("memory_map.zig");
const registry = @import("address_registry.zig");
const format = @import("image_format.zig");
const RuntimeError = @import("defs.zig").RuntimeError;
const Cell = map.Cell;
const capacity = registry.capacity;

pub const Graph = struct {
    objects: [capacity]format.Object = undefined,
    object_count: usize = 0,
    records: [capacity]format.Relocation = undefined,
    record_count: usize = 0,
};

/// The output borrows State.memory. The caller must keep State unchanged while
/// consuming it. All temporary traversal state lives in the caller's Graph.
pub fn collect(state: *forth.State, output: *Graph) RuntimeError!void {
    return collectInternal(state, output, false);
}
/// Dictionary addition imports definitions, not the source VM's global setting.
pub fn collectForAppend(state: *forth.State, output: *Graph) RuntimeError!void {
    return collectInternal(state, output, true);
}
fn collectInternal(state: *forth.State, output: *Graph, preserve_fpath: bool) RuntimeError!void {
    if (state.quote_depth != 0 or state.postponing or state.colon_is_word != null) return error.InvalidDefinition;
    output.object_count = 0;
    output.record_count = 0;
    // Roots are typed slots outside the heap; raw cells are never scanned.
    for (state.addresses.records[0..state.addresses.count]) |record| {
        if (preserve_fpath and record.kind == .memory and record.slot == map.fpath_address) {
            try validateRecord(state, record);
            continue;
        }
        if (record.kind == .memory and record.slot >= state.sizes.heapBase() and record.slot < state.heapTop()) continue;
        try appendRecord(state, output, record);
    }
    // Newly discovered objects extend this work list, so cycles terminate.
    var visited: usize = 0;
    while (visited < output.object_count) : (visited += 1) {
        const object = output.objects[visited];
        const start = state.sizes.heapBase() + @as(Cell, @intCast(object.payload_offset));
        for (state.addresses.records[0..state.addresses.count]) |record| {
            if (record.kind == .memory and record.slot >= start and record.slot < start + @as(Cell, @intCast(object.bytes.len))) try appendRecord(state, output, record);
        }
    }
    // File object IDs follow original address order, independent of discovery.
    var i: usize = 1;
    while (i < output.object_count) : (i += 1) {
        var j = i;
        while (j > 0 and output.objects[j].payload_offset < output.objects[j - 1].payload_offset) : (j -= 1) {
            const temporary = output.objects[j];
            output.objects[j] = output.objects[j - 1];
            output.objects[j - 1] = temporary;
        }
    }
}

fn validateRecord(state: *forth.State, record: registry.Record) RuntimeError!void {
    try registry.validateRecord(state, record);
    for (state.addresses.records[0..state.addresses.count]) |other| {
        if (record.kind == .memory and other.kind == .memory and record.slot != other.slot and @as(i128, record.slot) < @as(i128, other.slot) + 8 and @as(i128, other.slot) < @as(i128, record.slot) + 8) return error.InvalidAddress;
    }
}
fn appendRecord(state: *forth.State, graph: *Graph, record: registry.Record) RuntimeError!void {
    try validateRecord(state, record);
    if (graph.record_count == capacity) return error.MemoryExhausted;
    const source: format.Storage = if (record.kind == .word) .word else switch (registry.classify(state, record.slot)) {
        .system => .system,
        .data => .data,
        .heap => .heap,
        else => return error.InvalidAddress,
    };
    if (source == .word) {
        if (record.slot < state.builtin_count or state.words[@intCast(record.slot)].kind != .constant) return error.InvalidAddress;
    }
    const target: format.Target = switch (record.target) {
        .null_address => .null_address,
        .system => .system,
        .data => .data,
        .heap => .heap,
        .invalid => return error.InvalidAddress,
    };
    graph.records[graph.record_count] = .{
        .storage = source,
        .target = target,
        .word_id = if (source == .word) @intCast(record.slot) else 0,
        .slot_offset = if (source == .word) 0 else @intCast(record.slot - base(state, source)),
        .target_offset = @intCast(record.value - switch (target) {
            .null_address, .system => @as(Cell, 0),
            .data => map.data_start,
            .heap => state.sizes.heapBase(),
        }),
    };
    graph.record_count += 1;
    if (target == .heap) try discover(state, graph, record.value);
}

fn base(state: *forth.State, storage: format.Storage) Cell {
    return switch (storage) {
        .system, .word => 0,
        .data => map.data_start,
        .heap => state.sizes.heapBase(),
    };
}

fn discover(state: *forth.State, graph: *Graph, address: Cell) RuntimeError!void {
    var block = state.sizes.heapBase();
    while (block < state.heapTop()) {
        const size = try state.blockSize(block);
        const payload = block + map.heap_header;
        if (address >= payload and address < payload + size and try state.blockUsed(block)) {
            if (@import("defs.zig").graphics_enabled) {
                const tcl = &state.tcl;
                if (payload == tcl.result.address or payload == tcl.error_text.address or payload == tcl.event.address) return error.InvalidAddress;
                if (tcl.partial) |message| if (payload == message.text.address) return error.InvalidAddress;
                for (0..tcl.event_count) |i| {
                    if (payload == tcl.events[(tcl.event_head + i) % tcl.events.len].address) return error.InvalidAddress;
                }
            }
            const offset: u64 = @intCast(payload - state.sizes.heapBase());
            for (graph.objects[0..graph.object_count]) |object| if (object.payload_offset == offset) return;
            if (graph.object_count == capacity) return error.MemoryExhausted;
            graph.objects[graph.object_count] = .{ .payload_offset = offset, .bytes = state.memory[@intCast(payload)..@intCast(payload + size)] };
            graph.object_count += 1;
            return;
        }
        block = payload + size;
    }
    return error.InvalidAddress;
}
