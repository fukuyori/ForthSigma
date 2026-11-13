//! Saving the dictionary as an image, restoring it, and appending it with LOAD-DICTIONARY.

const std = @import("std");
const inline_calls = @import("inline_calls.zig");
const defs = @import("defs.zig");
const forth = @import("../forth.zig");
const memory_map = @import("memory_map.zig");
const words_graphics = @import("words_graphics.zig");
const words_audio = @import("words_audio.zig");
const library_loading = @import("library_loading.zig");
const wordlists = @import("wordlists.zig");
const Cell = memory_map.Cell;
const Op = defs.Op;
const RuntimeError = defs.RuntimeError;
const State = forth.State;
const UCell = memory_map.UCell;
const Word = defs.Word;
const Builtin = defs.Builtin;
const WordKind = defs.WordKind;
const cell_size = memory_map.cell_size;
const data_start = memory_map.data_start;
const heap_top_address = memory_map.heap_top_address;
const graphics_image_address = memory_map.graphics_image_address;
const graphics_image_magic = memory_map.graphics_image_magic;
const graphics_vocabulary_address = memory_map.graphics_vocabulary_address;
const image_magic = memory_map.image_magic;
const max_code = memory_map.max_code;
const max_search_order = memory_map.max_search_order;
const max_source_files = memory_map.max_source_files;
const max_wordlists = memory_map.max_wordlists;
const max_words = memory_map.max_words;
const names_capacity = memory_map.names_capacity;
const root_wordlist = memory_map.root_wordlist;
const source_file_count_address = memory_map.source_file_count_address;
const source_file_loaded_flags = memory_map.source_file_loaded_flags;
const source_file_table = memory_map.source_file_table;
const wordlist_count_address = memory_map.wordlist_count_address;

pub fn writeU32(output: []u8, value: anytype) void {
    const number: u32 = @intCast(value);
    output[0] = @truncate(number);
    output[1] = @truncate(number >> 8);
    output[2] = @truncate(number >> 16);
    output[3] = @truncate(number >> 24);
}

pub fn readU32(input: []const u8) u32 {
    return @as(u32, input[0]) | (@as(u32, input[1]) << 8) | (@as(u32, input[2]) << 16) | (@as(u32, input[3]) << 24);
}

/// The header: the magic, then the word count, the operation count, HERE, the bytes of
/// names, and the layout's `m` and `l`, four bytes each.
const header_size = @import("image_format.zig").header_size;

/// The image ends with the CRC-32 of all the bytes before it, four bytes. It finds
/// accidental damage only; an image is trusted to come from SAVE or SAVESYS.
const checksum_size = 4;

/// The most bytes an image of a machine with these sizes can have.
pub fn imageCapacity(sizes: memory_map.Sizes) usize {
    return @import("image_format.zig").header_size + max_words * @sizeOf(Word) + max_code * @sizeOf(Op) + names_capacity + sizes.memorySize() + 2048 * 56 + checksum_size;
}
pub fn encodedSize(self: *State) usize {
    var workspace: @import("image_encoder.zig").Workspace = undefined;
    return @import("image_encoder.zig").measure(self, &workspace) catch imageCapacity(self.sizes);
}

/// The layout an image was saved with, as `m` and `l`; null when the bytes are not an
/// image this build reads, or the layout is not one a machine can have. It does not
/// check the rest of the image: `restoreImage` does.
pub fn imageLayout(image: []const u8) ?[2]usize {
    if (image.len < header_size + checksum_size or !knownMagic(image)) return null;
    const m: usize = readU32(image[24..28]);
    const l: usize = readU32(image[28..32]);
    return if (memory_map.Sizes.validLayout(m, l)) .{ m, l } else null;
}

fn knownMagic(image: []const u8) bool {
    return for ([_]*const [8]u8{ image_magic, graphics_image_magic, memory_map.audio_image_magic }) |magic| {
        if (std.mem.eql(u8, image[0..8], magic)) break true;
    } else false;
}

pub fn encodeImage(self: *State, output: []u8) RuntimeError!usize {
    var workspace: @import("image_encoder.zig").Workspace = undefined;
    return @import("image_encoder.zig").encode(self, output, &workspace);
}
pub fn restoreImage(self: *State, image: []const u8) RuntimeError!void {
    var plan: @import("image_restore_plan.zig").Plan = undefined;
    return @import("image_restore.zig").restore(self, image, &plan);
}
pub fn restoreFreshImage(self: *State, image: []const u8) RuntimeError!void {
    var plan: @import("image_restore_plan.zig").Plan = undefined;
    return @import("image_restore.zig").restoreFresh(self, image, &plan);
}

pub fn appendImage(self: *State, source: *const State) RuntimeError!void {
    if (self == source) return error.InvalidImage;
    const registry = @import("address_registry.zig");
    try registry.validate(self);
    var graph: @import("image_graph.zig").Graph = undefined;
    try @import("image_graph.zig").collect(@constCast(source), &graph);
    if (graph.record_count > registry.capacity - self.addresses.count) return error.MemoryExhausted;
    var heap_addresses: [registry.capacity]Cell = undefined;
    var new_top = self.heapTop();
    for (graph.objects[0..graph.object_count], 0..) |object, i| {
        const need: Cell = @intCast(memory_map.heap_header + object.bytes.len);
        if (need > self.sizes.heapEnd() - new_top) return error.MemoryExhausted;
        heap_addresses[i] = new_top + memory_map.heap_header;
        new_top += need;
    }
    for (graph.records[0..graph.record_count]) |record| {
        if (record.storage != .system) continue;
        for (self.addresses.records[0..self.addresses.count]) |own| {
            if (own.kind == .memory and @as(i128, own.slot) < @as(i128, record.slot_offset) + 8 and @as(i128, record.slot_offset) < @as(i128, own.slot) + 8) return error.InvalidImage;
        }
    }
    if (source.builtin_count == 0 or source.builtin_count != self.builtin_count or source.word_count < source.builtin_count) return error.InvalidImage;
    const added_words: usize = source.word_count - source.builtin_count;
    const word_base: usize = self.word_count;
    const graphics_loaded = words_graphics.graphicsLoaded(self);
    const audio_loaded = words_audio.audioLoaded(self);
    const gui_loaded = @import("words_gui.zig").guiLoaded(self);
    const game_loaded = @import("words_game.zig").gameLoaded(self);
    const code_base: usize = self.code_count;
    const code_count: usize = source.code_count;
    if (word_base + added_words > max_words) return error.DictionaryFull;
    if (code_base + code_count > max_code) return error.CodeFull;
    // The added words' names follow the built-in names in the source; they go after
    // this dictionary's names.
    const last_builtin = source.words[source.builtin_count - 1];
    const source_names_start: usize = last_builtin.name_start + last_builtin.name_len;
    const names_len = source.names_used - source_names_start;
    if (names_len > names_capacity - self.names_used) return error.DictionaryFull;
    const name_base: usize = self.names_used;
    if (source.data_here < data_start) return error.InvalidImage;
    const data_len = source.data_here - data_start;
    if (self.data_here + data_len > self.sizes.dataLimit()) return error.MemoryExhausted;
    const data_delta = self.data_here - data_start;
    // User word lists of the loaded image get new ids after this dictionary's.
    const source_wordlists = std.math.clamp(source.readCellConst(wordlist_count_address), memory_map.ekeys_wordlist, max_wordlists);
    const wordlist_base = self.wordlistCount();
    if (wordlist_base + source_wordlists - memory_map.ekeys_wordlist > max_wordlists) return error.DictionaryFull;
    const mapWordlist = struct {
        fn map(wid: Cell, base: Cell) Cell {
            return if (wid <= memory_map.ekeys_wordlist) wid else base +% wid -% memory_map.ekeys_wordlist;
        }
    }.map;

    // Merge the loaded image's source files into this table, keeping their loaded
    // flags; a file that does not fit loses its location information (index 0).
    const loaded_before = self.loadedSourceFiles();
    var file_map: [max_source_files]u8 = @splat(0);
    const source_files: usize = @intCast(std.math.clamp(source.readCellConst(source_file_count_address), 0, max_source_files));
    for (0..source_files) |index| {
        const mapped = self.sourceFileEntryIndex(source.sourceFileName(index)) catch continue;
        file_map[index] = mapped + 1;
        if (source.sourceFileLoaded(index)) self.setSourceFileLoaded(mapped, true);
    }

    for (source.words[source.builtin_count..source.word_count], 0..) |original, offset| {
        var word = original;
        word.name_start = @intCast(name_base + (word.name_start - source_names_start));
        word.data_here_before += data_delta;
        if (word.source_file != 0) word.source_file = if (word.source_file <= source_files) file_map[word.source_file - 1] else 0;
        word.wordlist = @intCast(mapWordlist(word.wordlist, wordlist_base));
        if (word.kind == .vocabulary) word.value = mapWordlist(word.value, wordlist_base);
        if (word.kind == .synonym and word.value >= source.builtin_count)
            word.value = @intCast(word_base + @as(usize, @intCast(word.value - source.builtin_count)));
        if (word.kind == .colon) {
            word.code_start = @intCast(@as(usize, word.code_start) + code_base);
            word.code_end = @intCast(@as(usize, word.code_end) + code_base);
        }
        if (word.has_does) {
            word.does_code_start = @intCast(@as(usize, word.does_code_start) + code_base);
            word.does_code_end = @intCast(@as(usize, word.does_code_end) + code_base);
        }
        if (word.kind == .variable or word.kind == .array or word.kind == .created or word.kind == .value or word.kind == .fvalue or word.kind == .two_constant or word.kind == .two_value or word.kind == .marker or word.kind == .deferred)
            word.value += data_delta;
        self.words[word_base + offset] = word;
    }

    for (source.code[0..source.code_count], 0..) |original, offset| {
        var op = original;
        switch (op.kind) {
            .call_colon => if (inline_calls.isInline(op)) {
                const id = inline_calls.wordId(op.value);
                const relocated: u16 = if (id >= source.builtin_count) @intCast(word_base + id - source.builtin_count) else id;
                op.value = inline_calls.operand(relocated, inline_calls.span(op.value), inline_calls.depth(op.value));
            } else if (op.value >= source.builtin_count) {
                op.value = @intCast(word_base + @as(usize, @intCast(op.value - source.builtin_count)));
            },
            .call, .compile_call, .execution_token, .store_value, .add_value, .local_frame => if (op.value >= source.builtin_count) {
                op.value = @intCast(word_base + @as(usize, @intCast(op.value - source.builtin_count)));
            },
            .branch, .branch_zero, .do_loop, .q_do_loop, .loop, .plus_loop => {
                op.value += @intCast(code_base);
            },
            .print_string, .string_literal, .counted_string, .abort_string => {
                op.value += data_delta;
            },
            .builtin, .call_builtin, .literal, .float_literal, .leave, .does, .exit, .local_store, .local_fetch, .local_address, .local_execute => {},
            inline else => |kind| {
                _ = comptime defs.primitiveBuiltin(kind);
            },
        }
        self.code[code_base + offset] = op;
        // The lines the code was compiled from are not in an image; the ones here
        // would be those of code that FORGET or a MARKER removed.
        if (defs.debug_enabled) {
            self.code_lines[code_base + offset] = 0;
            self.code_columns[code_base + offset] = 0;
            if (self.profile) |profile| profile.op_counts[code_base + offset] = 0;
        }
    }
    const data_from: usize = @intCast(data_start);
    const data_to: usize = @intCast(self.data_here);
    const length: usize = @intCast(data_len);
    @memcpy(self.memory[data_to .. data_to + length], source.memory[data_from .. data_from + length]);
    // A loaded DEFER whose action is a loaded word follows that word's new number.
    for (self.words[word_base .. word_base + added_words]) |word| {
        if (word.kind != .deferred) continue;
        const action = self.readCellConst(word.value);
        if (action >= source.builtin_count and action < source.word_count)
            try self.writeCell(word.value, @intCast(word_base + @as(usize, @intCast(action - source.builtin_count))));
    }
    // A loaded MARKER keeps this dictionary's REQUIRE history plus the files the saved
    // one had loaded, and its word lists are renumbered like the words.
    for (self.words[word_base .. word_base + added_words]) |word| {
        if (word.kind != .marker) continue;
        const saved: UCell = @bitCast(self.readCellConst(word.value));
        var mask = loaded_before;
        for (0..source_files) |index| {
            if (saved & (@as(UCell, 1) << @intCast(index)) != 0 and file_map[index] != 0) mask |= @as(UCell, 1) << @intCast(file_map[index] - 1);
        }
        try self.writeCell(word.value, @bitCast(mask));
        // Only the current list and the recorded order entries hold word-list ids.
        const current_at = word.value + cell_size;
        try self.writeCell(current_at, mapWordlist(try self.readCell(current_at), wordlist_base));
        const depth: usize = @intCast(std.math.clamp(try self.readCell(word.value + 2 * cell_size), 0, max_search_order));
        for (0..depth) |index| {
            const at = word.value + @as(Cell, @intCast(3 + index)) * cell_size;
            try self.writeCell(at, mapWordlist(try self.readCell(at), wordlist_base));
        }
    }
    try self.writeCell(wordlist_count_address, wordlist_base + source_wordlists - memory_map.ekeys_wordlist);
    @memcpy(self.names[name_base .. name_base + names_len], source.names[source_names_start..source.names_used]);
    self.names_used = @intCast(name_base + names_len);
    self.word_count = @intCast(word_base + added_words);
    // The added words are the newest, so they go at the heads of their chains in order.
    for (word_base..self.word_count) |id| wordlists.indexWord(self, @intCast(id));
    self.code_count = @intCast(code_base + code_count);
    self.data_here += data_len;
    self.last_created_word = null;
    // The loaded image's graphics words count as loaded here too, unless this dictionary
    // has its own; either way, images saved from now on are SIGIMG43.
    try library_loading.appendLoaded(self, source, words_graphics.group, graphics_loaded, word_base);
    try library_loading.appendLoaded(self, source, words_audio.group, audio_loaded, word_base);
    try library_loading.appendLoaded(self, source, @import("words_gui.zig").group, gui_loaded, word_base);
    try library_loading.appendLoaded(self, source, @import("words_game.zig").group, game_loaded, word_base);
    for (graph.objects[0..graph.object_count], 0..) |object, i| {
        const at = heap_addresses[i];
        self.setBlock(at - memory_map.heap_header, @intCast(object.bytes.len), true);
        @memcpy(self.memory[@intCast(at)..][0..object.bytes.len], object.bytes);
    }
    try self.writeCell(heap_top_address, new_top);
    for (graph.records[0..graph.record_count]) |wire| {
        const slot: Cell = switch (wire.storage) {
            .word => @intCast(word_base + wire.word_id - source.builtin_count),
            .system => @intCast(wire.slot_offset),
            .data => data_start + data_delta + @as(Cell, @intCast(wire.slot_offset)),
            .heap => mappedHeap(&graph, &heap_addresses, wire.slot_offset),
        };
        const value: Cell = switch (wire.target) {
            .null_address => 0,
            .system => @intCast(wire.target_offset),
            .data => data_start + data_delta + @as(Cell, @intCast(wire.target_offset)),
            .heap => mappedHeap(&graph, &heap_addresses, wire.target_offset),
        };
        if (wire.storage == .word) {
            self.words[@intCast(slot)].value = value;
            try registry.registerWord(self, @intCast(slot));
        } else {
            try self.writeCell(slot, value);
            try registry.registerMemory(self, slot);
        }
    }
    if (defs.debug_enabled and source.keep_counting) self.keep_counting = true;
}

fn mappedHeap(graph: *const @import("image_graph.zig").Graph, addresses: *const [2048]Cell, offset: u64) Cell {
    for (graph.objects[0..graph.object_count], 0..) |object, i| {
        if (offset >= object.payload_offset and offset - object.payload_offset < object.bytes.len) return addresses[i] + @as(Cell, @intCast(offset - object.payload_offset));
    }
    unreachable;
}
