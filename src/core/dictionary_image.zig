//! Saving the dictionary as an image, restoring it, and appending it with LOAD.

const std = @import("std");
const inline_calls = @import("inline_calls.zig");
const native_endian = @import("builtin").cpu.arch.endian();
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
const header_size = 32;

/// The image ends with the CRC-32 of all the bytes before it, four bytes. It finds
/// accidental damage only; an image is trusted to come from SAVE or SAVESYS.
const checksum_size = 4;

/// The most bytes an image of a machine with these sizes can have.
pub fn imageCapacity(sizes: memory_map.Sizes) usize {
    return header_size + max_words * @sizeOf(Word) + max_code * @sizeOf(Op) + names_capacity + sizes.memorySize() + checksum_size;
}

/// The bytes `encodeImage` needs for this machine as it is now.
pub fn encodedSize(self: *State) usize {
    const ranges = memoryRanges(self.sizes, self.data_here, self.heapTop());
    return header_size + @as(usize, self.word_count) * @sizeOf(Word) + @as(usize, self.code_count) * @sizeOf(Op) + self.names_used + rangesLength(ranges) + checksum_size;
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

/// The parts of memory an image keeps: the system area, the data space up to HERE, the
/// used part of the heap, and the source file table with its loaded flags. The rest
/// (input buffers, local frames, free space) starts as zeros when the image is restored.
fn memoryRanges(sizes: memory_map.Sizes, data_here: Cell, heap_top: Cell) [4][2]usize {
    return .{
        .{ 0, @intCast(memory_map.system_end) },
        .{ @intCast(data_start), @intCast(data_here) },
        .{ @intCast(sizes.heapBase()), @intCast(heap_top) },
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

/// Whether the saved dictionary starts with this build's built-in words at the same
/// places, so that the image's execution tokens of built-in words mean the same words.
/// A word group a build leaves out keeps its places (installBuiltins), so builds with
/// other groups match; an image of a build that dropped those places does not.
fn builtinsMatch(self: *const State, word_bytes: []const u8) bool {
    if (word_bytes.len < @as(usize, self.builtin_count) * @sizeOf(Word)) return false;
    for (self.words[0..self.builtin_count], 0..) |own, index| {
        const at = index * @sizeOf(Word);
        if (savedTag(WordKind, word_bytes[at + @offsetOf(Word, "kind") ..]) != @intFromEnum(own.kind)) return false;
        if (savedTag(Builtin, word_bytes[at + @offsetOf(Word, "builtin") ..]) != @intFromEnum(own.builtin)) return false;
    }
    return true;
}

/// Where the names of this build's built-in words end; the names lie one after another.
fn builtinNamesEnd(self: *const State) usize {
    if (self.builtin_count == 0) return 0;
    const last = self.words[self.builtin_count - 1];
    return @as(usize, last.name_start) + last.name_len;
}

/// Where the names of the image's built-in words end, read from the saved words, which
/// namesAreConsecutive has checked.
fn savedBuiltinNamesEnd(word_bytes: []const u8, builtins: usize) usize {
    if (builtins == 0) return 0;
    const at = (builtins - 1) * @sizeOf(Word);
    const start = std.mem.readInt(u32, word_bytes[at + @offsetOf(Word, "name_start") ..][0..4], native_endian);
    return @as(usize, start) + word_bytes[at + @offsetOf(Word, "name_len")];
}

/// The tag of an enum field read from the bytes, without making an enum of a value the
/// bytes may not hold.
fn savedTag(comptime E: type, bytes: []const u8) @typeInfo(E).@"enum".tag_type {
    const Storage = @Int(.unsigned, @sizeOf(E) * 8);
    return @truncate(std.mem.readInt(Storage, bytes[0..@sizeOf(E)], native_endian));
}

fn rangesLength(ranges: [4][2]usize) usize {
    var total: usize = 0;
    for (ranges) |range| total += range[1] - range[0];
    return total;
}

pub fn encodeImage(self: *State, output: []u8) RuntimeError!usize {
    const ranges = memoryRanges(self.sizes, self.data_here, self.heapTop());
    const word_bytes = std.mem.sliceAsBytes(self.words[0..self.word_count]);
    const code_bytes = std.mem.sliceAsBytes(self.code[0..self.code_count]);
    const name_bytes = self.names[0..self.names_used];
    const required = header_size + word_bytes.len + code_bytes.len + name_bytes.len + rangesLength(ranges) + checksum_size;
    if (output.len < required) return error.InvalidImage;
    // A dictionary that has had the audio words is saved as SIGIMG44, one that has had
    // the graphics words (and not the audio words) as SIGIMG43, which older builds
    // reject; one that never had them stays SIGIMG42.
    const magic = if (self.readCellConst(memory_map.audio_image_address) != 0)
        memory_map.audio_image_magic
    else if (self.readCellConst(graphics_image_address) != 0)
        graphics_image_magic
    else
        image_magic;
    @memcpy(output[0..8], magic);
    writeU32(output[8..12], self.word_count);
    writeU32(output[12..16], self.code_count);
    writeU32(output[16..20], self.data_here);
    writeU32(output[20..24], self.names_used);
    writeU32(output[24..28], @as(u32, @intCast(self.sizes.m)));
    writeU32(output[28..32], @as(u32, @intCast(self.sizes.l)));
    var cursor: usize = header_size;
    for ([_][]const u8{ word_bytes, code_bytes, name_bytes }) |bytes| {
        @memcpy(output[cursor .. cursor + bytes.len], bytes);
        cursor += bytes.len;
    }
    // Save the operations unspecialized: the specialization is only an execution detail,
    // redone after restoring. Do not change the running machine's operations.
    var inline_end: usize = 0;
    for (self.code[0..self.code_count], 0..) |original, index| {
        var op = original;
        if (index < inline_end) {
            op = .{ .kind = .branch, .value = @intCast(inline_end) };
        } else if (inline_calls.isInline(op)) {
            inline_end = index + inline_calls.span(op.value);
            op = .{ .kind = .call, .value = inline_calls.wordId(op.value) };
        } else if (op.kind == .call_colon) {
            op.kind = .call;
        } else if (defs.isPrimitiveOp(op.kind)) {
            op.kind = .call_builtin;
        }
        const at = header_size + word_bytes.len + index * @sizeOf(Op);
        @memcpy(output[at + @offsetOf(Op, "kind") ..][0..@sizeOf(defs.OpKind)], std.mem.asBytes(&op.kind));
        @memcpy(output[at + @offsetOf(Op, "value") ..][0..@sizeOf(Cell)], std.mem.asBytes(&op.value));
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
    return restore(self, image, false);
}

/// `restoreImage` for a machine that has run nothing since `init`: its memory outside
/// what the image brings is zeros already, and stays untouched, so pages not in use take
/// no physical memory.
pub fn restoreFreshImage(self: *State, image: []const u8) RuntimeError!void {
    return restore(self, image, true);
}

fn restore(self: *State, image: []const u8, memory_is_fresh: bool) RuntimeError!void {
    if (image.len < header_size + checksum_size) return error.InvalidImage;
    if (!knownMagic(image)) return error.InvalidImage;
    const input = image[0 .. image.len - checksum_size];
    if (readU32(image[input.len..]) != std.hash.Crc32.hash(input)) return error.InvalidImage;
    // An image keeps addresses, so it runs only with the layout it was saved with.
    if (readU32(input[24..28]) != self.sizes.m or readU32(input[28..32]) != self.sizes.l) return error.InvalidImage;
    const word_count = readU32(input[8..12]);
    const code_count = readU32(input[12..16]);
    const data_here = readU32(input[16..20]);
    const names_used = readU32(input[20..24]);
    if (word_count < self.builtin_count or word_count > max_words or code_count > max_code or data_here < data_start or data_here > self.sizes.dataLimit() or names_used > names_capacity) return error.InvalidImage;
    const word_bytes_len = @as(usize, word_count) * @sizeOf(Word);
    const code_bytes_len = @as(usize, code_count) * @sizeOf(Op);
    const memory_at = header_size + word_bytes_len + code_bytes_len + names_used;
    // The heap's end is a cell of the saved system area; check it before changing anything.
    const heap_top_at = memory_at + @as(usize, @intCast(heap_top_address));
    if (input.len < heap_top_at + cell_size) return error.InvalidImage;
    const heap_top: Cell = @bitCast(std.mem.readInt(u64, input[heap_top_at..][0..8], .little));
    if (heap_top < self.sizes.heapBase() or heap_top > self.sizes.heapEnd()) return error.InvalidImage;
    const ranges = memoryRanges(self.sizes, data_here, heap_top);
    if (input.len != memory_at + rangesLength(ranges)) return error.InvalidImage;
    if (!namesAreConsecutive(input[header_size .. header_size + word_bytes_len], names_used)) return error.InvalidImage;
    const word_bytes = input[header_size .. header_size + word_bytes_len];
    if (!builtinsMatch(self, word_bytes)) return error.InvalidImage;
    // The built-in words stay this build's own, with their names: an image of a build with
    // other word groups has the same built-in words at the same places, but names only for
    // the groups that build has. The image's own words and names follow this build's
    // built-in names, so their name places move by the difference.
    const builtins: usize = self.builtin_count;
    const own_names = builtinNamesEnd(self);
    const image_names = savedBuiltinNamesEnd(word_bytes, builtins);
    const added_names = names_used - image_names;
    if (added_names > names_capacity - own_names) return error.DictionaryFull;
    var cursor: usize = header_size + builtins * @sizeOf(Word);
    @memcpy(std.mem.sliceAsBytes(self.words[builtins..word_count]), input[cursor .. header_size + word_bytes_len]);
    for (self.words[builtins..word_count]) |*word| word.name_start = @intCast(word.name_start - image_names + own_names);
    cursor = header_size + word_bytes_len;
    @memcpy(std.mem.sliceAsBytes(self.code[0..code_count]), input[cursor .. cursor + code_bytes_len]);
    cursor += code_bytes_len;
    @memcpy(self.names[own_names..][0..added_names], input[cursor + image_names .. cursor + names_used]);
    cursor += names_used;
    if (!memory_is_fresh) @memset(self.memory, 0);
    for (ranges) |range| {
        const length = range[1] - range[0];
        @memcpy(self.memory[range[0]..range[1]], input[cursor .. cursor + length]);
        cursor += length;
    }
    self.names_used = @intCast(own_names + added_names);
    self.word_count = @intCast(word_count);
    wordlists.rebuildIndex(self);
    // The recorded uses are not in the image.
    self.use_count = 0;
    // Nor are the lines the code was compiled from.
    if (defs.tools_enabled) @memset(&self.code_lines, 0);
    self.code_count = @intCast(code_count);
    // Old and new images store ordinary calls; rebuild dispatch information
    // only after the word entries and counts have been restored.
    for (self.code[0..self.code_count]) |*op| {
        op.* = self.specializeCall(op.*);
    }
    inline_calls.restore(self);
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
    // The image is not part of the dictionary: the restored program makes its own.
    words_graphics.clearImage(self);
    // The images of the pool go too, and drawing goes to the screen.
    @import("graphics_images.zig").releaseAll(self);
    // The Tcl strings were in the heap the image replaced.
    if (defs.graphics_enabled) @import("tcl.zig").forgetHeap(self);
}

pub fn appendImage(self: *State, source: *const State) RuntimeError!void {
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
        if (defs.tools_enabled) self.code_lines[code_base + offset] = 0;
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
    try self.writeCell(wordlist_count_address, wordlist_base + source_wordlists - root_wordlist);
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
}
