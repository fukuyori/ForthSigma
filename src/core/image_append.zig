//! Typed-image append. Public host entry points are connected separately.
const std = @import("std");
const forth = @import("../forth.zig");
const defs = @import("defs.zig");
const map = @import("memory_map.zig");
const planner = @import("image_append_plan.zig");
const RuntimeError = defs.RuntimeError;
pub const Workspace = struct {
    plan: planner.Plan = undefined,
    file_map: [map.max_source_files]u8 = @splat(0),
    file_names: [map.max_source_files][]const u8 = undefined,
    file_loaded: [map.max_source_files]bool = @splat(false),
    file_count: usize = 0,
    loaded_before: map.UCell = 0,
    groups_loaded: [4]bool = @splat(false),
};

/// image and Workspace must be disjoint from State and remain stable throughout.
pub fn append(state: *forth.State, image: []const u8, work: *Workspace) RuntimeError!void {
    try planner.prepare(state, image, &work.plan);
    prepareFiles(state, work);
    inline for (.{ @import("words_graphics.zig").group, @import("words_audio.zig").group, @import("words_gui.zig").group, @import("words_game.zig").group }, 0..) |group, i| {
        work.groups_loaded[i] = @import("library_loading.zig").isLoaded(state, group);
    }
    apply(state, work);
}
fn prepareFiles(state: *forth.State, work: *Workspace) void {
    work.file_map = @splat(0);
    work.file_loaded = @splat(false);
    work.loaded_before = state.loadedSourceFiles();
    work.file_count = @intCast(state.readCellConst(map.source_file_count_address));
    for (0..work.file_count) |i| {
        work.file_names[i] = state.sourceFileName(i);
        work.file_loaded[i] = state.sourceFileLoaded(i);
    }
    const count: usize = @intCast(savedCell(work, map.source_file_count_address));
    for (0..count) |i| {
        const entry = savedBytes(work, map.source_file_table + @as(map.Cell, @intCast(i * map.source_file_entry_size)), map.source_file_entry_size);
        const name = entry[1..][0..entry[0]];
        var found: ?usize = null;
        for (work.file_names[0..work.file_count], 0..) |own, j| {
            if (std.mem.eql(u8, name, own)) {
                found = j;
                break;
            }
        }
        const target = found orelse blk: {
            if (work.file_count == map.max_source_files) continue;
            const j = work.file_count;
            work.file_names[j] = name;
            work.file_count += 1;
            break :blk j;
        };
        work.file_map[i] = @intCast(target + 1);
        if (savedBytes(work, map.source_file_loaded_flags + @as(map.Cell, @intCast(i)), 1)[0] != 0) work.file_loaded[target] = true;
    }
}
fn apply(state: *forth.State, work: *Workspace) void {
    const plan = &work.plan;
    const view = plan.image.view;
    const h = view.header;
    const data_length = h.data_here - @as(u32, @intCast(map.data_start));
    @memcpy(state.memory[@intCast(state.data_here)..][0..data_length], view.memory[@intCast(map.system_end)..][0..data_length]);
    for (view.objects, 0..) |object, i| {
        if (!plan.keep_objects[i]) continue;
        const at = plan.image.object_addresses[i];
        put(state, at - map.heap_header, @intCast(object.bytes.len));
        put(state, at - map.cell_size, 1);
        @memcpy(state.memory[@intCast(at)..][0..object.bytes.len], object.bytes);
    }
    put(state, map.heap_top_address, plan.image.heap_top);
    for (h.builtin_count..h.word_count) |i| {
        var word = planner.relocatedWord(plan, i) catch unreachable;
        if (word.source_file != 0) word.source_file = work.file_map[word.source_file - 1];
        const id = plan.word_base + i - h.builtin_count;
        state.words[id] = word;
        if (word.kind == .deferred) {
            const action = state.readCellConst(word.value);
            if (action >= h.builtin_count and action < h.word_count) put(state, word.value, @as(map.Cell, @intCast(plan.word_base)) + action - h.builtin_count);
        }
        if (word.kind == .marker) relocateMarker(state, work, word.value);
    }
    for (0..h.code_count) |i| {
        state.code[plan.code_base + i] = planner.relocatedOperation(plan, i) catch unreachable;
        if (defs.debug_enabled) {
            state.code_lines[plan.code_base + i] = 0;
            state.code_columns[plan.code_base + i] = 0;
            if (state.profile) |profile| profile.op_counts[plan.code_base + i] = 0;
        }
    }
    const new_names = view.names[plan.image.image_names..];
    @memcpy(state.names[plan.name_base..][0..new_names.len], new_names);
    for (0..work.file_count) |i| {
        const at: usize = @intCast(map.source_file_table + @as(map.Cell, @intCast(i * map.source_file_entry_size)));
        const name = work.file_names[i];
        // Existing names may already alias this exact table entry.
        @memmove(state.memory[at + 1 ..][0..name.len], name);
        state.memory[at] = @intCast(name.len);
        state.memory[@intCast(map.source_file_loaded_flags + @as(map.Cell, @intCast(i)))] = @intFromBool(work.file_loaded[i]);
    }
    put(state, map.source_file_count_address, @intCast(work.file_count));
    put(state, map.wordlist_count_address, plan.wordlist_base + savedCell(work, map.wordlist_count_address) - map.ekeys_wordlist);
    for (plan.image.records[0..h.relocation_count], 0..) |record, i| {
        if (!plan.keep_records[i]) continue;
        if (record.kind == .word) state.words[@intCast(record.slot)].value = record.value else put(state, record.slot, record.value);
        state.addresses.records[state.addresses.count] = record;
        state.addresses.count += 1;
    }
    state.addresses.index_dirty = true;
    state.addresses.stable_writes = 0;
    state.names_used = @intCast(plan.name_base + new_names.len);
    state.word_count = @intCast(plan.word_base + h.word_count - h.builtin_count);
    state.code_count = @intCast(plan.code_base + h.code_count);
    state.data_here = plan.data_here;
    state.last_created_word = null;
    @import("wordlists.zig").rebuildIndex(state);
    // Normalize first, then specialize against the newly installed word table.
    for (state.code[plan.code_base..state.code_count]) |*op| op.* = state.specializeCall(op.*);
    if (defs.debug_enabled) @import("words_debug.zig").noteBreakpoints(state);
    inline for (.{ @import("words_graphics.zig").group, @import("words_audio.zig").group, @import("words_gui.zig").group, @import("words_game.zig").group }, 0..) |group, i| {
        appendGroup(state, work, group, work.groups_loaded[i]);
    }
}
fn relocateMarker(state: *forth.State, work: *const Workspace, address: map.Cell) void {
    const saved: map.UCell = @bitCast(state.readCellConst(address));
    var mask = work.loaded_before;
    for (work.file_map, 0..) |mapped, i| {
        if (mapped != 0 and saved & (@as(map.UCell, 1) << @intCast(i)) != 0) mask |= @as(map.UCell, 1) << @intCast(mapped - 1);
    }
    put(state, address, @bitCast(mask));
    put(state, address + 8, planner.relocatedWordlist(&work.plan, state.readCellConst(address + 8)));
    const depth: usize = @intCast(std.math.clamp(state.readCellConst(address + 16), 0, map.max_search_order));
    for (0..depth) |i| {
        const at = address + @as(map.Cell, @intCast(3 + i)) * 8;
        put(state, at, planner.relocatedWordlist(&work.plan, state.readCellConst(at)));
    }
}
fn savedBytes(work: *const Workspace, address: map.Cell, length: usize) []const u8 {
    const data_length = work.plan.image.view.header.data_here - @as(u32, @intCast(map.data_start));
    const at: usize = @intCast(if (address < map.system_end) address else map.system_end + @as(map.Cell, data_length) + address - map.source_file_table);
    return work.plan.image.view.memory[at..][0..length];
}
fn savedCell(work: *const Workspace, address: map.Cell) map.Cell {
    return std.mem.readInt(map.Cell, savedBytes(work, address, 8)[0..8], .little);
}
fn put(state: *forth.State, address: map.Cell, value: map.Cell) void {
    std.mem.writeInt(map.Cell, state.memory[@intCast(address)..][0..8], value, .little);
}

fn appendGroup(state: *forth.State, work: *const Workspace, comptime group: anytype, was_loaded: bool) void {
    if (group.image_address) |address| {
        if (savedCell(work, address) != 0) put(state, address, 1);
    }
    const view = work.plan.image.view;
    const id = savedCell(work, group.vocabulary_address);
    if (was_loaded or id < view.header.builtin_count or id >= @as(map.Cell, view.header.word_count) - 1) return;
    const vocabulary = rawWord(work, @intCast(id));
    const first = rawWord(work, @intCast(id + 1));
    if (vocabulary.kind != .vocabulary) return;
    const loaded = if (comptime group.definitions.len != 0)
        first.kind == .builtin and first.builtin == group.definitions[0][1]
    else blk: {
        if (first.kind == .builtin or first.source_file == 0 or first.source_file > savedCell(work, map.source_file_count_address)) break :blk false;
        const entry = savedBytes(work, map.source_file_table + @as(map.Cell, first.source_file - 1) * map.source_file_entry_size, map.source_file_entry_size);
        break :blk std.mem.eql(u8, entry[1..][0..entry[0]], group.library_name);
    };
    if (loaded) put(state, group.vocabulary_address, @as(map.Cell, @intCast(work.plan.word_base)) + id - view.header.builtin_count);
}
fn rawWord(work: *const Workspace, id: usize) defs.Word {
    return std.mem.bytesToValue(defs.Word, work.plan.image.view.words[id * @sizeOf(defs.Word) ..][0..@sizeOf(defs.Word)]);
}
