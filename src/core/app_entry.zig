//! Persistent saved-application entry. A word identity, never an address root.
const std = @import("std");
const forth = @import("../forth.zig");
const defs = @import("defs.zig");
const map = @import("memory_map.zig");
const format = @import("image_format.zig");
const Error = defs.RuntimeError;

fn idOf(raw: map.Cell, words: usize, builtins: usize) Error!?u16 {
    if (raw == 0) return null;
    if (!defs.image_enabled or raw <= builtins or raw > words) return error.InvalidExecutionToken;
    return @intCast(raw - 1);
}
fn checkWord(word: defs.Word, code_count: usize) Error!void {
    if (word.kind != .colon or word.compile_only or word.code_start > word.code_end or word.code_end > code_count) return error.InvalidExecutionToken;
}
pub fn get(state: *const forth.State) Error!?u16 {
    if (state.word_count > state.words.len or state.builtin_count > state.word_count or state.code_count > state.code.len) return error.InvalidExecutionToken;
    const id = (try idOf(state.readCellConst(map.app_entry_address), state.word_count, state.builtin_count)) orelse return null;
    if (state.defining and state.current_word == id) return error.InvalidExecutionToken;
    try checkWord(state.words[id], state.code_count);
    return id;
}
fn overlaps(slot: u64) bool {
    return @as(u128, slot) < @as(u128, map.app_entry_address) + 8 and @as(u128, slot) + 8 > map.app_entry_address;
}
pub fn validateState(state: *const forth.State) Error!void {
    _ = try get(state);
    for (state.addresses.records[0..state.addresses.count]) |record| {
        if (record.kind == .memory and record.slot >= 0 and overlaps(@intCast(record.slot))) return error.InvalidExecutionToken;
    }
}
pub fn imageEntry(view: format.View) Error!?u16 {
    const raw = std.mem.readInt(map.Cell, view.memory[@intCast(map.app_entry_address)..][0..8], .little);
    const id = idOf(raw, view.header.word_count, view.header.builtin_count) catch return error.InvalidImage;
    if (id) |value| {
        const word = std.mem.bytesToValue(defs.Word, view.words[@as(usize, value) * @sizeOf(defs.Word) ..][0..@sizeOf(defs.Word)]);
        checkWord(word, view.header.code_count) catch return error.InvalidImage;
    }
    for (0..view.header.relocation_count) |index| {
        const record = try view.relocation(index);
        if (record.storage == .system and overlaps(record.slot_offset)) return error.InvalidImage;
    }
    return id;
}
fn store(state: *forth.State, raw: map.Cell) void {
    // This reserved cell is an execution-token setting, not a typed address.
    // Remove only slots overlapping it; pointers to the stable system area survive.
    var count: usize = 0;
    for (state.addresses.records[0..state.addresses.count]) |record| {
        if (record.kind == .memory and record.slot >= 0 and overlaps(@intCast(record.slot))) continue;
        state.addresses.records[count] = record;
        count += 1;
    }
    if (count != state.addresses.count) {
        state.addresses.count = count;
        state.addresses.index_dirty = true;
        state.addresses.stable_writes = 0;
    }
    state.writeCell(map.app_entry_address, raw) catch unreachable;
}
pub fn forget(state: *forth.State, first: u16) void {
    const raw = state.readCellConst(map.app_entry_address);
    if (raw > first) store(state, 0);
}
pub fn execute(state: *forth.State, comptime builtin: defs.Builtin) Error!void {
    switch (builtin) {
        .app_entry_set => {
            try state.requireDepth(1);
            if (state.defining) return error.InvalidDefinition;
            const id = try state.wordId(try state.peek(0));
            if (id < state.builtin_count) return error.InvalidExecutionToken;
            try checkWord(state.words[id], state.code_count);
            state.data_depth -= 1;
            store(state, @as(map.Cell, id) + 1);
        },
        .app_entry_get => {
            if (state.data_stack.len - state.data_depth < 2) return error.StackOverflow;
            const id = try get(state);
            try state.push(if (id) |value| value else 0);
            try state.push(if (id != null) -1 else 0);
        },
        .app_entry_off => store(state, 0),
        else => @compileError("not an application-entry word"),
    }
}
