//! Saving the dictionary as an image, restoring it, and appending it with LOAD.

const std = @import("std");
const native_endian = @import("builtin").cpu.arch.endian();
const defs = @import("defs.zig");
const forth = @import("../forth.zig");
const memory_map = @import("memory_map.zig");
const Cell = memory_map.Cell;
const Op = defs.Op;
const RuntimeError = defs.RuntimeError;
const State = forth.State;
const UCell = memory_map.UCell;
const Word = defs.Word;
const cell_size = memory_map.cell_size;
const data_limit = memory_map.data_limit;
const data_start = memory_map.data_start;
const heap_base = memory_map.heap_base;
const heap_end = memory_map.heap_end;
const heap_top_address = memory_map.heap_top_address;
const image_magic = memory_map.image_magic;
const max_code = memory_map.max_code;
const max_search_order = memory_map.max_search_order;
const max_source_files = memory_map.max_source_files;
const max_wordlists = memory_map.max_wordlists;
const max_words = memory_map.max_words;
const memory_size = memory_map.memory_size;
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

/// The header: the magic, then the word count, the operation count, HERE, and the bytes
/// of names, four bytes each.
const header_size = 24;

/// The image ends with the CRC-32 of all the bytes before it, four bytes. It finds
/// accidental damage only; an image is trusted to come from SAVE or SAVESYS.
const checksum_size = 4;

/// The most bytes an image can have.
pub fn imageCapacity() usize {
    return header_size + max_words * @sizeOf(Word) + max_code * @sizeOf(Op) + names_capacity + memory_size + checksum_size;
}

/// The parts of memory an image keeps: the system area and the data space up to HERE,
/// the used part of the heap, and the source file table with its loaded flags. The rest
/// (input buffers, local frames, free space) starts as zeros when the image is restored.
fn memoryRanges(data_here: Cell, heap_top: Cell) [3][2]usize {
    return .{
        .{ 0, @intCast(data_here) },
        .{ @intCast(heap_base), @intCast(heap_top) },
        .{ @intCast(source_file_table), @intCast(source_file_loaded_flags + max_source_files) },
    };
}

/// Whether the names of the saved words lie one after another from the start of the name
/// area to `names_used`, as appendEntry places them; FORGET and LOAD rely on that order.
/// A word without a name takes no bytes. The fields are read from the bytes, so nothing
/// is changed before an image is accepted.
fn namesAreConsecutive(word_bytes: []const u8, names_used: usize) bool {
    var next: usize = 0;
    var at: usize = 0;
    while (at < word_bytes.len) : (at += @sizeOf(Word)) {
        const start = std.mem.readInt(u32, word_bytes[at + @offsetOf(Word, "name_start") ..][0..4], native_endian);
        const length = word_bytes[at + @offsetOf(Word, "name_len")];
        if (start != next) return false;
        next += length;
    }
    return next == names_used;
}

fn rangesLength(ranges: [3][2]usize) usize {
    var total: usize = 0;
    for (ranges) |range| total += range[1] - range[0];
    return total;
}

pub fn encodeImage(self: *State, output: []u8) RuntimeError!usize {
    const ranges = memoryRanges(self.data_here, self.heapTop());
    const word_bytes = std.mem.sliceAsBytes(self.words[0..self.word_count]);
    const code_bytes = std.mem.sliceAsBytes(self.code[0..self.code_count]);
    const name_bytes = self.names[0..self.names_used];
    const required = header_size + word_bytes.len + code_bytes.len + name_bytes.len + rangesLength(ranges) + checksum_size;
    if (output.len < required) return error.InvalidImage;
    @memcpy(output[0..8], image_magic);
    writeU32(output[8..12], self.word_count);
    writeU32(output[12..16], self.code_count);
    writeU32(output[16..20], self.data_here);
    writeU32(output[20..24], self.names_used);
    var cursor: usize = header_size;
    for ([_][]const u8{ word_bytes, code_bytes, name_bytes }) |bytes| {
        @memcpy(output[cursor .. cursor + bytes.len], bytes);
        cursor += bytes.len;
    }
    for (ranges) |range| {
        const length = range[1] - range[0];
        @memcpy(output[cursor .. cursor + length], self.memory[range[0]..range[1]]);
        cursor += length;
    }
    writeU32(output[cursor..][0..checksum_size], std.hash.Crc32.hash(output[0..cursor]));
    return required;
}

pub fn restoreImage(self: *State, image: []const u8) RuntimeError!void {
    if (image.len < header_size + checksum_size or !std.mem.eql(u8, image[0..8], image_magic)) return error.InvalidImage;
    const input = image[0 .. image.len - checksum_size];
    if (readU32(image[input.len..]) != std.hash.Crc32.hash(input)) return error.InvalidImage;
    const word_count = readU32(input[8..12]);
    const code_count = readU32(input[12..16]);
    const data_here = readU32(input[16..20]);
    const names_used = readU32(input[20..24]);
    if (word_count < self.builtin_count or word_count > max_words or code_count > max_code or data_here < data_start or data_here > data_limit or names_used > names_capacity) return error.InvalidImage;
    const word_bytes_len = @as(usize, word_count) * @sizeOf(Word);
    const code_bytes_len = @as(usize, code_count) * @sizeOf(Op);
    const memory_at = header_size + word_bytes_len + code_bytes_len + names_used;
    // The heap's end is a cell of the saved system area; check it before changing anything.
    const heap_top_at = memory_at + @as(usize, @intCast(heap_top_address));
    if (input.len < heap_top_at + cell_size) return error.InvalidImage;
    const heap_top: Cell = @bitCast(std.mem.readInt(u64, input[heap_top_at..][0..8], .little));
    if (heap_top < heap_base or heap_top > heap_end) return error.InvalidImage;
    const ranges = memoryRanges(data_here, heap_top);
    if (input.len != memory_at + rangesLength(ranges)) return error.InvalidImage;
    if (!namesAreConsecutive(input[header_size .. header_size + word_bytes_len], names_used)) return error.InvalidImage;
    var cursor: usize = header_size;
    @memcpy(std.mem.sliceAsBytes(self.words[0..word_count]), input[cursor .. cursor + word_bytes_len]);
    cursor += word_bytes_len;
    @memcpy(std.mem.sliceAsBytes(self.code[0..code_count]), input[cursor .. cursor + code_bytes_len]);
    cursor += code_bytes_len;
    @memcpy(self.names[0..names_used], input[cursor .. cursor + names_used]);
    cursor += names_used;
    @memset(&self.memory, 0);
    for (ranges) |range| {
        const length = range[1] - range[0];
        @memcpy(self.memory[range[0]..range[1]], input[cursor .. cursor + length]);
        cursor += length;
    }
    self.names_used = names_used;
    self.word_count = @intCast(word_count);
    // The recorded uses are not in the image.
    self.use_count = 0;
    self.code_count = @intCast(code_count);
    self.data_here = data_here;
    self.data_depth = 0;
    self.return_depth = 0;
    self.float_depth = 0;
    self.control_depth = 0;
    self.loop_depth = 0;
    self.resetHold();
    self.setCompiling(false);
    self.defining = false;
    self.pending = .none;
}

pub fn appendImage(self: *State, source: *const State) RuntimeError!void {
    if (source.builtin_count == 0 or source.builtin_count != self.builtin_count or source.word_count < source.builtin_count) return error.InvalidImage;
    const added_words: usize = source.word_count - source.builtin_count;
    const word_base: usize = self.word_count;
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
    if (self.data_here + data_len > data_limit) return error.MemoryExhausted;
    const data_delta = self.data_here - data_start;
    // User word lists of the loaded image get new ids after this dictionary's.
    const source_wordlists = std.math.clamp(source.readCellConst(wordlist_count_address), root_wordlist, max_wordlists);
    const wordlist_base = self.wordlistCount();
    if (wordlist_base + source_wordlists - root_wordlist > max_wordlists) return error.DictionaryFull;
    const mapWordlist = struct {
        fn map(wid: Cell, base: Cell) Cell {
            return if (wid <= root_wordlist) wid else base +% wid -% root_wordlist;
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
        if (word.kind == .variable or word.kind == .array or word.kind == .created or word.kind == .value or word.kind == .fvalue or word.kind == .two_constant or word.kind == .two_value or word.kind == .marker)
            word.value += data_delta;
        self.words[word_base + offset] = word;
    }

    for (source.code[0..source.code_count], 0..) |original, offset| {
        var op = original;
        switch (op.kind) {
            .call, .compile_call, .execution_token, .store_value, .local_frame => if (op.value >= source.builtin_count) {
                op.value = @intCast(word_base + @as(usize, @intCast(op.value - source.builtin_count)));
            },
            .branch, .branch_zero, .do_loop, .q_do_loop, .loop, .plus_loop => {
                op.value += @intCast(code_base);
            },
            .print_string, .string_literal, .counted_string, .abort_string => {
                op.value += data_delta;
            },
            .builtin, .literal, .float_literal, .leave, .does, .exit, .local_store, .local_fetch, .local_address, .local_execute => {},
        }
        self.code[code_base + offset] = op;
    }
    const data_from: usize = @intCast(data_start);
    const data_to: usize = @intCast(self.data_here);
    const length: usize = @intCast(data_len);
    @memcpy(self.memory[data_to .. data_to + length], source.memory[data_from .. data_from + length]);
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
    try self.writeCell(wordlist_count_address, wordlist_base + source_wordlists - root_wordlist);
    @memcpy(self.names[name_base .. name_base + names_len], source.names[source_names_start..source.names_used]);
    self.names_used = @intCast(name_base + names_len);
    self.word_count = @intCast(word_base + added_words);
    self.code_count = @intCast(code_base + code_count);
    self.data_here += data_len;
    self.last_created_word = null;
}
