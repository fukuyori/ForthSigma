//! SIGIMG45/46/47 wire framing and read-only structural validation.
//! This codec does not install a dictionary or infer address types. A loader must
//! additionally match its own builtin table before committing any State changes.
const std = @import("std");
const defs = @import("defs.zig");
const map = @import("memory_map.zig");
const native_endian = @import("builtin").cpu.arch.endian();
const RuntimeError = defs.RuntimeError;
const max_records = @import("address_registry.zig").capacity;
pub const header_size = 112;
pub const record_size = 32;
pub const object_header_size = 24;
pub const checksum_size = 4;
pub const FileKind = enum { normal, graphics, audio };
pub const Storage = enum(u8) { system = 1, data = 2, heap = 3, word = 4 };
pub const Target = enum(u8) { null_address = 0, system = 1, data = 2, heap = 3 };
pub const no_object = std.math.maxInt(u16);
const word_fields = .{ "name_start", "name_len", "kind", "builtin", "immediate", "compile_only", "has_does", "value", "code_start", "code_end", "does_code_start", "does_code_end", "data_here_before", "locals_size", "source_file", "source_line", "source_end_line", "wordlist" };
pub const abi_signature = layoutSignature();

pub fn magic(kind: FileKind) *const [8]u8 {
    return switch (kind) {
        .normal => "SIGIMG45",
        .graphics => "SIGIMG46",
        .audio => "SIGIMG47",
    };
}

pub const Header = struct {
    kind: FileKind = .normal,
    word_count: u32 = 0,
    code_count: u32 = 0,
    data_here: u32 = @intCast(map.data_start),
    names_used: u32 = 0,
    m: u32 = @intCast(map.Sizes.small.m),
    l: u32 = @intCast(map.Sizes.small.l),
    relocation_count: u32 = 0,
    object_count: u32 = 0,
    word_bytes: u64 = 0,
    code_bytes: u64 = 0,
    name_bytes: u64 = 0,
    memory_bytes: u64 = memoryLength(@intCast(map.data_start)),
    relocation_bytes: u64 = 0,
    heap_bytes: u64 = 0,
    builtin_count: u32 = 0,
};

pub const Relocation = struct {
    storage: Storage,
    target: Target,
    word_id: u32 = 0,
    slot_offset: u64 = 0,
    target_offset: u64 = 0,
};

pub const Object = struct { payload_offset: u64, bytes: []const u8 };
pub const Workspace = struct {
    objects: [max_records]Object = undefined,
    source_objects: [max_records]u16 = undefined,
    target_objects: [max_records]u16 = undefined,
    slots: [max_records]u64 = undefined,
    reached: [max_records]bool = undefined,
};
pub const View = struct {
    header: Header,
    words: []const u8,
    code: []const u8,
    names: []const u8,
    memory: []const u8,
    relocations: []const u8,
    heap: []const u8,
    /// Borrows Workspace; the other slices borrow the input image.
    objects: []const Object,

    pub fn relocation(self: View, index: usize) RuntimeError!Relocation {
        if (index >= self.header.relocation_count) return error.InvalidImage;
        return readRelocation(self.relocations[index * record_size ..][0..record_size]);
    }
};

pub fn memoryLength(data_here: u32) u64 {
    return @as(u64, map.system_end) + (data_here - @as(u32, @intCast(map.data_start))) + sourceLength();
}
fn sourceLength() u64 {
    return @intCast(map.source_file_loaded_flags + map.max_source_files - map.source_file_table);
}

pub fn writeHeader(output: *[header_size]u8, h: Header) void {
    @memset(output, 0);
    @memcpy(output[0..8], magic(h.kind));
    put(u32, output[8..], h.word_count);
    put(u32, output[12..], h.code_count);
    put(u32, output[16..], h.data_here);
    put(u32, output[20..], h.names_used);
    put(u32, output[24..], h.m);
    put(u32, output[28..], h.l);
    put(u16, output[32..], header_size);
    output[34] = 8;
    output[35] = if (native_endian == .little) 1 else 2;
    put(u32, output[40..], h.relocation_count);
    put(u32, output[44..], h.object_count);
    put(u64, output[48..], h.word_bytes);
    put(u64, output[56..], h.code_bytes);
    put(u64, output[64..], h.name_bytes);
    put(u64, output[72..], h.memory_bytes);
    put(u64, output[80..], h.relocation_bytes);
    put(u64, output[88..], h.heap_bytes);
    put(u32, output[96..], h.builtin_count);
    put(u16, output[100..], @sizeOf(defs.Word));
    put(u16, output[102..], @sizeOf(defs.Op));
    put(u64, output[104..], abi_signature);
}

pub fn writeRelocation(output: *[record_size]u8, record: Relocation) void {
    @memset(output, 0);
    output[0] = @backingInt(record.storage);
    output[1] = @backingInt(record.target);
    put(u32, output[4..], record.word_id);
    put(u64, output[8..], record.slot_offset);
    put(u64, output[16..], record.target_offset);
    put(u64, output[24..], 8);
}

/// Native Word/Op ABI is identified by the header. Padding is always zeroed;
/// enum storage is widened explicitly rather than copying undefined padding bits.
pub fn writeWord(output: *[@sizeOf(defs.Word)]u8, word: defs.Word) void {
    @memset(output, 0);
    inline for (word_fields) |name| {
        const value = @field(word, name);
        const T = @TypeOf(value);
        const at = @offsetOf(defs.Word, name);
        switch (@typeInfo(T)) {
            .@"enum" => std.mem.writeInt(@Int(.unsigned, @sizeOf(T) * 8), output[at..][0..@sizeOf(T)], @backingInt(value), native_endian),
            .bool => output[at] = @intFromBool(value),
            .int => std.mem.writeInt(T, output[at..][0..@sizeOf(T)], value, native_endian),
            else => @compileError("unhandled Word field"),
        }
    }
}
pub fn writeOperation(output: *[@sizeOf(defs.Op)]u8, op: defs.Op) RuntimeError!void {
    if (@backingInt(op.kind) > @backingInt(defs.OpKind.call_builtin)) return error.InvalidImage;
    @memset(output, 0);
    output[@offsetOf(defs.Op, "kind")] = @backingInt(op.kind);
    std.mem.writeInt(map.Cell, output[@offsetOf(defs.Op, "value")..][0..8], op.value, native_endian);
}
pub fn writeObjectHeader(output: *[object_header_size]u8, id: u32, payload_offset: u64, size: u64) void {
    @memset(output, 0);
    put(u32, output[0..], id);
    put(u64, output[8..], payload_offset);
    put(u64, output[16..], size);
}

pub fn readRelocation(bytes: []const u8) RuntimeError!Relocation {
    if (bytes.len != record_size or bytes[0] < 1 or bytes[0] > 4 or bytes[1] > 3) return error.InvalidImage;
    if (get(u16, bytes[2..]) != 0 or get(u64, bytes[24..]) != 8) return error.InvalidImage;
    const record = Relocation{ .storage = @fromBackingInt(@intCast(bytes[0])), .target = @fromBackingInt(@intCast(bytes[1])), .word_id = get(u32, bytes[4..]), .slot_offset = get(u64, bytes[8..]), .target_offset = get(u64, bytes[16..]) };
    if (record.storage == .word) {
        if (record.slot_offset != 0) return error.InvalidImage;
    } else if (record.word_id != 0) return error.InvalidImage;
    if (record.target == .null_address and record.target_offset != 0) return error.InvalidImage;
    if (record.target == .system and record.target_offset == 0) return error.InvalidImage;
    return record;
}

pub fn finish(output: []u8) RuntimeError!void {
    if (output.len < header_size + checksum_size) return error.InvalidImage;
    put(u32, output[output.len - checksum_size ..], std.hash.Crc32.hash(output[0 .. output.len - checksum_size]));
}

pub fn parse(image: []const u8, workspace: *Workspace) RuntimeError!View {
    if (image.len < header_size + checksum_size) return error.InvalidImage;
    const kind: FileKind = if (std.mem.eql(u8, image[0..8], magic(.normal))) .normal else if (std.mem.eql(u8, image[0..8], magic(.graphics))) .graphics else if (std.mem.eql(u8, image[0..8], magic(.audio))) .audio else return error.InvalidImage;
    if (get(u16, image[32..]) != header_size or image[34] != 8 or image[35] != (if (native_endian == .little) @as(u8, 1) else 2) or get(u32, image[36..]) != 0 or get(u64, image[104..]) != abi_signature) return error.InvalidImage;
    if (get(u16, image[100..]) != @sizeOf(defs.Word) or get(u16, image[102..]) != @sizeOf(defs.Op)) return error.InvalidImage;
    const h = Header{ .kind = kind, .word_count = get(u32, image[8..]), .code_count = get(u32, image[12..]), .data_here = get(u32, image[16..]), .names_used = get(u32, image[20..]), .m = get(u32, image[24..]), .l = get(u32, image[28..]), .relocation_count = get(u32, image[40..]), .object_count = get(u32, image[44..]), .word_bytes = get(u64, image[48..]), .code_bytes = get(u64, image[56..]), .name_bytes = get(u64, image[64..]), .memory_bytes = get(u64, image[72..]), .relocation_bytes = get(u64, image[80..]), .heap_bytes = get(u64, image[88..]), .builtin_count = get(u32, image[96..]) };
    if (!map.Sizes.validLayout(h.m, h.l) or h.data_here < map.data_start or h.data_here > h.m) return error.InvalidImage;
    if (h.word_count > map.max_words or h.builtin_count > h.word_count or h.code_count > map.max_code or h.names_used > map.names_capacity or h.relocation_count > max_records or h.object_count > max_records) return error.InvalidImage;
    if (h.word_bytes != @as(u64, h.word_count) * @sizeOf(defs.Word) or h.code_bytes != @as(u64, h.code_count) * @sizeOf(defs.Op) or h.name_bytes != h.names_used or h.memory_bytes != memoryLength(h.data_here) or h.relocation_bytes != @as(u64, h.relocation_count) * record_size) return error.InvalidImage;
    var cursor: usize = header_size;
    const body = image[0 .. image.len - checksum_size];
    const words = try section(body, &cursor, h.word_bytes);
    const code = try section(body, &cursor, h.code_bytes);
    const names = try section(body, &cursor, h.name_bytes);
    const memory = try section(body, &cursor, h.memory_bytes);
    const relocations = try section(body, &cursor, h.relocation_bytes);
    const heap = try section(body, &cursor, h.heap_bytes);
    if (cursor != body.len or get(u32, image[body.len..]) != std.hash.Crc32.hash(body)) return error.InvalidImage;
    const top = get(u64, memory[@intCast(map.heap_top_address)..]);
    if (top < h.m or top > 2 * @as(u64, h.m)) return error.InvalidImage;
    var object_cursor: usize = 0;
    var previous_end: u64 = 0;
    for (0..h.object_count) |i| {
        const raw = try section(heap, &object_cursor, object_header_size);
        const offset = get(u64, raw[8..]);
        const size = get(u64, raw[16..]);
        if (get(u32, raw) != i or get(u32, raw[4..]) != 0 or offset < map.heap_header or offset % 8 != 0 or size % 8 != 0 or offset - map.heap_header < previous_end or offset > top - h.m or size > top - h.m - offset) return error.InvalidImage;
        workspace.objects[i] = .{ .payload_offset = offset, .bytes = try section(heap, &object_cursor, size) };
        workspace.reached[i] = false;
        previous_end = offset + size;
    }
    if (object_cursor != heap.len) return error.InvalidImage;
    const view = View{ .header = h, .words = words, .code = code, .names = names, .memory = memory, .relocations = relocations, .heap = heap, .objects = workspace.objects[0..h.object_count] };
    try validateWords(view);
    try validateCode(view);
    for (0..h.relocation_count) |i| {
        const record = try view.relocation(i);
        const source = try sourceCell(view, record);
        workspace.slots[i] = source.key;
        workspace.source_objects[i] = source.object;
        const target = try targetAddress(view, record);
        workspace.target_objects[i] = target.object;
        if (source.value != target.value) return error.InvalidImage;
        for (workspace.slots[0..i]) |old| {
            if (source.key >> 63 != 0 or old >> 63 != 0) {
                if (source.key == old) return error.InvalidImage;
            } else if (source.key < old + 8 and old < source.key + 8) return error.InvalidImage;
        }
        if (source.object == no_object and target.object != no_object) workspace.reached[target.object] = true;
    }
    var changed = true;
    while (changed) {
        changed = false;
        for (0..h.relocation_count) |i| {
            const from = workspace.source_objects[i];
            const to = workspace.target_objects[i];
            if (from != no_object and to != no_object and workspace.reached[from] and !workspace.reached[to]) {
                workspace.reached[to] = true;
                changed = true;
            }
        }
    }
    for (workspace.reached[0..h.object_count]) |reached| if (!reached) return error.InvalidImage;
    try validateStringValues(view, workspace);
    return view;
}

const CellSource = struct { key: u64, value: u64, object: u16 = no_object };
const Address = struct { value: u64, object: u16 = no_object };
fn sourceCell(v: View, r: Relocation) RuntimeError!CellSource {
    const length = @as(u64, v.header.data_here) - @as(u64, map.data_start);
    switch (r.storage) {
        .word => {
            if (r.word_id < v.header.builtin_count or r.word_id >= v.header.word_count) return error.InvalidImage;
            const bytes = v.words[r.word_id * @sizeOf(defs.Word) ..][0..@sizeOf(defs.Word)];
            if (enumTag(defs.WordKind, bytes[@offsetOf(defs.Word, "kind")..]) != @backingInt(defs.WordKind.constant)) return error.InvalidImage;
            return .{ .key = (@as(u64, 1) << 63) | r.word_id, .value = std.mem.readInt(u64, bytes[@offsetOf(defs.Word, "value")..][0..8], native_endian) };
        },
        .system => {
            const at = try systemOffset(r.slot_offset, 8, length);
            return .{ .key = r.slot_offset, .value = get(u64, v.memory[at..]) };
        },
        .data => {
            if (r.slot_offset > length or 8 > length - r.slot_offset) return error.InvalidImage;
            const at: usize = @intCast(@as(u64, map.system_end) + r.slot_offset);
            return .{ .key = @as(u64, map.data_start) + r.slot_offset, .value = get(u64, v.memory[at..]) };
        },
        .heap => {
            const id = findObject(v.objects, r.slot_offset, 8) orelse return error.InvalidImage;
            const at: usize = @intCast(r.slot_offset - v.objects[id].payload_offset);
            return .{ .key = @as(u64, v.header.m) + r.slot_offset, .value = get(u64, v.objects[id].bytes[at..]), .object = id };
        },
    }
}
fn targetAddress(v: View, r: Relocation) RuntimeError!Address {
    return switch (r.target) {
        .null_address => .{ .value = 0 },
        .system => blk: {
            _ = try systemOffset(r.target_offset, 1, @as(u64, v.header.data_here) - @as(u64, map.data_start));
            break :blk .{ .value = r.target_offset };
        },
        .data => blk: {
            if (r.target_offset > @as(u64, v.header.data_here) - @as(u64, map.data_start)) return error.InvalidImage;
            break :blk .{ .value = @as(u64, map.data_start) + r.target_offset };
        },
        .heap => blk: {
            const id = findObject(v.objects, r.target_offset, 1) orelse return error.InvalidImage;
            break :blk .{ .value = @as(u64, v.header.m) + r.target_offset, .object = id };
        },
    };
}
fn findObject(objects: []const Object, offset: u64, width: u64) ?u16 {
    for (objects, 0..) |object, i| if (offset >= object.payload_offset and offset - object.payload_offset <= object.bytes.len and width <= object.bytes.len - (offset - object.payload_offset)) return @intCast(i);
    return null;
}
fn systemOffset(address: u64, width: u64, data_length: u64) RuntimeError!usize {
    if (address <= map.system_end and width <= @as(u64, map.system_end) - address) return @intCast(address);
    const start: u64 = @intCast(map.source_file_table);
    const length = sourceLength();
    if (address >= start and address - start <= length and width <= length - (address - start)) return @intCast(@as(u64, map.system_end) + data_length + address - start);
    return error.InvalidImage;
}

fn validateWords(v: View) RuntimeError!void {
    const wordlists = get(u64, v.memory[@intCast(map.wordlist_count_address)..]);
    const files = get(u64, v.memory[@intCast(map.source_file_count_address)..]);
    if (wordlists < map.ekeys_wordlist or wordlists > map.max_wordlists or files > map.max_source_files) return error.InvalidImage;
    var next: usize = 0;
    for (0..v.header.word_count) |i| {
        const bytes = v.words[i * @sizeOf(defs.Word) ..][0..@sizeOf(defs.Word)];
        if (enumTag(defs.WordKind, bytes[@offsetOf(defs.Word, "kind")..]) >= @typeInfo(defs.WordKind).@"enum".field_names.len or enumTag(defs.Builtin, bytes[@offsetOf(defs.Word, "builtin")..]) >= @typeInfo(defs.Builtin).@"enum".field_names.len) return error.InvalidImage;
        if (bytes[@offsetOf(defs.Word, "immediate")] > 1 or bytes[@offsetOf(defs.Word, "compile_only")] > 1 or bytes[@offsetOf(defs.Word, "has_does")] > 1) return error.InvalidImage;
        const word = std.mem.bytesToValue(defs.Word, bytes);
        if (word.name_start != next or word.name_len > v.names.len - next) return error.InvalidImage;
        next += word.name_len;
        if ((word.wordlist != map.macros_wordlist and (word.wordlist < 1 or word.wordlist > wordlists)) or word.source_file > files or word.locals_size > v.header.l) return error.InvalidImage;
        if (word.data_here_before < map.data_start or word.data_here_before > v.header.data_here) return error.InvalidImage;
        if (word.kind == .colon and (word.code_start > word.code_end or word.code_end > v.header.code_count)) return error.InvalidImage;
        if (word.has_does and (word.does_code_start > word.does_code_end or word.does_code_end > v.header.code_count)) return error.InvalidImage;
        switch (word.kind) {
            .value => {
                if (i < v.header.builtin_count and (word.builtin == .csv_quote or word.builtin == .csv_separator)) {
                    const expected = if (word.builtin == .csv_quote) map.csv_quote_address else map.csv_separator_address;
                    if (word.value != expected) return error.InvalidImage;
                } else try dataCell(v, word.value, 8);
            },
            .variable, .fvalue, .deferred, .string_value => try dataCell(v, word.value, 8),
            .two_constant, .two_value => try dataCell(v, word.value, 16),
            .marker => try dataCell(v, word.value, map.marker_snapshot_size),
            .created, .array => try dataCell(v, word.value, 0),
            .synonym => if (word.value < 0 or word.value >= v.header.word_count) return error.InvalidImage,
            .vocabulary => if ((word.value != map.macros_wordlist and (word.value < 1 or word.value > wordlists))) return error.InvalidImage,
            else => {},
        }
    }
    if (next != v.names.len) return error.InvalidImage;
}
fn validateCode(v: View) RuntimeError!void {
    for (0..v.header.code_count) |i| {
        const bytes = v.code[i * @sizeOf(defs.Op) ..][0..@sizeOf(defs.Op)];
        if (enumTag(defs.OpKind, bytes[@offsetOf(defs.Op, "kind")..]) > @backingInt(defs.OpKind.call_builtin)) return error.InvalidImage;
        const op = std.mem.bytesToValue(defs.Op, bytes);
        switch (op.kind) {
            .call, .compile_call, .execution_token, .store_value, .add_value, .local_frame => if (op.value < 0 or op.value >= v.header.word_count) return error.InvalidImage,
            .call_builtin => if (op.value < 0 or op.value >= v.header.builtin_count) return error.InvalidImage,
            .builtin => if (op.value < 0 or op.value >= @typeInfo(defs.Builtin).@"enum".field_names.len) return error.InvalidImage,
            .branch, .branch_zero, .do_loop, .q_do_loop, .loop, .plus_loop => if (op.value < 0 or op.value > v.header.code_count) return error.InvalidImage,
            .print_string, .string_literal, .counted_string, .abort_string => {
                try dataCell(v, op.value, 1);
                const at: usize = @intCast(@as(map.Cell, map.system_end) + op.value - map.data_start);
                try dataCell(v, op.value, @as(usize, v.memory[at]) + 1);
            },
            .local_store, .local_fetch, .local_address, .local_execute => {
                if (op.value < 0 or @as(u64, @bitCast(op.value)) >> 40 != 0 or ((@as(u64, @bitCast(op.value)) >> 32) & 255) > @backingInt(defs.LocalKind.xt)) return error.InvalidImage;
            },
            else => {},
        }
    }
}
/// A string value is an explicit owning structure, not an arbitrary raw cell.
/// Its owner must be registered and name either NULL or a complete length-prefixed
/// heap allocation; otherwise a forged image could silently lose its contents.
fn validateStringValues(v: View, workspace: *Workspace) RuntimeError!void {
    const keys = workspace.slots[0..v.header.relocation_count];
    std.mem.sort(u64, keys, {}, struct {
        fn before(_: void, a: u64, b: u64) bool {
            return a < b;
        }
    }.before);
    for (0..v.header.word_count) |i| {
        const word = std.mem.bytesToValue(defs.Word, v.words[i * @sizeOf(defs.Word) ..][0..@sizeOf(defs.Word)]);
        if (word.kind != .string_value) continue;
        const key: u64 = @intCast(word.value);
        var low: usize = 0;
        var high = keys.len;
        while (low < high) {
            const mid = low + (high - low) / 2;
            if (keys[mid] < key) low = mid + 1 else high = mid;
        }
        if (low == keys.len or keys[low] != key) return error.InvalidImage;
        const at: usize = @intCast(@as(map.Cell, map.system_end) + word.value - map.data_start);
        const owner = get(u64, v.memory[at..]);
        if (owner == 0) continue;
        if (owner < v.header.m) return error.InvalidImage;
        const offset = owner - v.header.m;
        low = 0;
        high = v.objects.len;
        while (low < high) {
            const mid = low + (high - low) / 2;
            if (v.objects[mid].payload_offset < offset) low = mid + 1 else high = mid;
        }
        if (low == v.objects.len or v.objects[low].payload_offset != offset) return error.InvalidImage;
        const bytes = v.objects[low].bytes;
        if (bytes.len < 8 or get(u64, bytes) > bytes.len - 8) return error.InvalidImage;
    }
}

fn dataCell(v: View, address: map.Cell, width: usize) RuntimeError!void {
    if (address < map.data_start or address > v.header.data_here or width > @as(u64, @intCast(@as(map.Cell, v.header.data_here) - address))) return error.InvalidImage;
}
fn enumTag(comptime E: type, bytes: []const u8) u64 {
    return std.mem.readInt(@Int(.unsigned, @sizeOf(E) * 8), bytes[0..@sizeOf(E)], native_endian);
}
fn section(input: []const u8, cursor: *usize, length: u64) RuntimeError![]const u8 {
    const len = std.math.cast(usize, length) orelse return error.InvalidImage;
    const end = std.math.add(usize, cursor.*, len) catch return error.InvalidImage;
    if (end > input.len) return error.InvalidImage;
    const result = input[cursor.*..end];
    cursor.* = end;
    return result;
}
fn get(comptime T: type, bytes: []const u8) T {
    return std.mem.readInt(T, bytes[0..@sizeOf(T)], .little);
}
fn put(comptime T: type, bytes: []u8, value: T) void {
    std.mem.writeInt(T, bytes[0..@sizeOf(T)], value, .little);
}

// Sizes alone do not identify a native struct ABI: two targets can reorder fields
// differently while retaining the same total size. Hash field offsets and widths.
fn layoutSignature() u64 {
    @setEvalBranchQuota(1000000);
    var hash: u64 = 14695981039346656037;
    for ([_]u64{ @sizeOf(defs.Word), @alignOf(defs.Word), @sizeOf(defs.Op), @alignOf(defs.Op) }) |value| hashValue(&hash, value);
    inline for (word_fields) |name| {
        hashValue(&hash, @offsetOf(defs.Word, name));
        hashValue(&hash, @sizeOf(@FieldType(defs.Word, name)));
    }
    hashValue(&hash, @offsetOf(defs.Op, "kind"));
    hashValue(&hash, @offsetOf(defs.Op, "value"));
    inline for (.{ defs.WordKind, defs.OpKind, defs.Builtin }) |E| {
        inline for (@typeInfo(E).@"enum".field_names) |name| {
            hashValue(&hash, @backingInt(@field(E, name)));
            for (name) |byte| hashValue(&hash, byte);
            hashValue(&hash, 0);
        }
    }
    return hash;
}
fn hashValue(hash: *u64, value: u64) void {
    for (0..8) |i| hash.* = (hash.* ^ @as(u8, @truncate(value >> @as(u6, @intCast(i * 8))))) *% 1099511628211;
}
