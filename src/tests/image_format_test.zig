//! Read-only validation of the future format; no State image path uses it yet.
const std = @import("std");
const format = @import("../core/image_format.zig");
const defs = @import("../core/defs.zig");
const map = @import("../core/memory_map.zig");
const support = @import("support.zig");
const native_endian = @import("builtin").cpu.arch.endian();

const Fixture = struct {
    bytes: []u8,
    word_at: usize,
    code_at: usize,
    memory_at: usize,
    records_at: usize,
    heap_at: usize,
    fn free(self: Fixture) void {
        std.testing.allocator.free(self.bytes);
    }
};
fn put(comptime T: type, bytes: []u8, value: T) void {
    std.mem.writeInt(T, bytes[0..@sizeOf(T)], value, .little);
}
fn fixture(kind: format.FileKind) !Fixture {
    const h = format.Header{
        .kind = kind,
        .word_count = 1,
        .code_count = 1,
        .data_here = @intCast(map.data_start + 16),
        .names_used = 1,
        .word_bytes = @sizeOf(defs.Word),
        .code_bytes = @sizeOf(defs.Op),
        .name_bytes = 1,
        .memory_bytes = format.memoryLength(@intCast(map.data_start + 16)),
        .relocation_count = 4,
        .relocation_bytes = 4 * format.record_size,
        .object_count = 2,
        .heap_bytes = 2 * (format.object_header_size + 16),
    };
    const length: usize = @intCast(format.header_size + h.word_bytes + h.code_bytes + h.name_bytes + h.memory_bytes + h.relocation_bytes + h.heap_bytes + format.checksum_size);
    const bytes = try std.testing.allocator.alloc(u8, length);
    @memset(bytes, 0);
    format.writeHeader(bytes[0..format.header_size], h);
    const word_at = format.header_size;
    const word = defs.Word{ .name_len = 1, .kind = .constant, .value = map.data_start + 8, .data_here_before = map.data_start };
    format.writeWord(bytes[word_at..][0..@sizeOf(defs.Word)], word);
    const code_at = word_at + @sizeOf(defs.Word);
    const op = defs.Op{ .kind = .literal, .value = 123 };
    try format.writeOperation(bytes[code_at..][0..@sizeOf(defs.Op)], op);
    bytes[code_at + @sizeOf(defs.Op)] = 'A';
    const memory_at = code_at + @sizeOf(defs.Op) + 1;
    put(u64, bytes[memory_at + @as(usize, @intCast(map.heap_top_address)) ..], @as(u64, h.m) + 64);
    put(u64, bytes[memory_at + @as(usize, @intCast(map.system_end)) ..], @as(u64, h.m) + 16);
    // A raw cell with an address-looking value deliberately has no record.
    put(u64, bytes[memory_at + @as(usize, @intCast(map.system_end)) + 8 ..], @intCast(map.data_start + 8));
    put(u64, bytes[memory_at + @as(usize, @intCast(map.wordlist_count_address)) ..], @intCast(map.ekeys_wordlist));
    put(map.Cell, bytes[memory_at + @as(usize, @intCast(map.exception_next_address)) ..], @import("../core/exception_registry.zig").first_code);
    const records_at = memory_at + @as(usize, @intCast(h.memory_bytes));
    const records = [_]format.Relocation{
        .{ .storage = .word, .target = .data, .word_id = 0, .target_offset = 8 },
        .{ .storage = .data, .target = .heap, .slot_offset = 0, .target_offset = 16 },
        .{ .storage = .heap, .target = .heap, .slot_offset = 16, .target_offset = 48 },
        .{ .storage = .heap, .target = .heap, .slot_offset = 48, .target_offset = 16 },
    };
    for (records, 0..) |record, i| format.writeRelocation(bytes[records_at + i * format.record_size ..][0..format.record_size], record);
    const heap_at = records_at + @as(usize, @intCast(h.relocation_bytes));
    for (0..2) |i| {
        const at = heap_at + i * (format.object_header_size + 16);
        put(u32, bytes[at..], @intCast(i));
        put(u64, bytes[at + 8 ..], 16 + i * 32);
        put(u64, bytes[at + 16 ..], 16);
        put(u64, bytes[at + format.object_header_size ..], @as(u64, h.m) + (if (i == 0) @as(u64, 48) else 16));
    }
    try format.finish(bytes);
    return .{ .bytes = bytes, .word_at = word_at, .code_at = code_at, .memory_at = memory_at, .records_at = records_at, .heap_at = heap_at };
}
fn rejected(bytes: []u8, scratch: *format.Workspace) !void {
    try format.finish(bytes);
    if (format.parse(bytes, scratch)) |_| return error.TestExpectedError else |err| try std.testing.expectEqual(error.InvalidImage, err);
}

test "image45 codec parses all three magics and reachable heap cycles without touching State" {
    const scratch = try std.testing.allocator.create(format.Workspace);
    defer std.testing.allocator.destroy(scratch);
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try machine.interpretLine("77 CONSTANT KEEP");
    const count = machine.word_count;
    const here = machine.data_here;
    for ([_]format.FileKind{ .normal, .graphics, .audio }) |kind| {
        const f = try fixture(kind);
        defer f.free();
        const view = try format.parse(f.bytes, scratch);
        try std.testing.expectEqual(kind, view.header.kind);
        try std.testing.expectEqual(@as(usize, 2), view.objects.len);
        try std.testing.expectEqual(@as(usize, 16), view.objects[0].bytes.len);
        try std.testing.expectEqual(@as(u64, 48), (try view.relocation(2)).target_offset);
        try std.testing.expectEqual(@as(u8, 'A'), view.names[0]);
    }
    try std.testing.expectEqual(count, machine.word_count);
    try std.testing.expectEqual(here, machine.data_here);
    try machine.interpretLine("KEEP");
    try support.expectStack(machine, &.{77});
}

test "image45 framing rejects old magic truncated sections CRC and unchecked length overflow" {
    const scratch = try std.testing.allocator.create(format.Workspace);
    defer std.testing.allocator.destroy(scratch);
    const f = try fixture(.normal);
    defer f.free();
    for ([_]usize{ 0, 8, 32, 111, 112, f.bytes.len - 1 }) |length| try std.testing.expectError(error.InvalidImage, format.parse(f.bytes[0..length], scratch));
    const original = try std.testing.allocator.dupe(u8, f.bytes);
    defer std.testing.allocator.free(original);
    @memcpy(f.bytes[0..8], "SIGIMG42");
    try rejected(f.bytes, scratch);
    @memcpy(f.bytes, original);
    f.bytes[f.memory_at + 100] ^= 1;
    try std.testing.expectError(error.InvalidImage, format.parse(f.bytes, scratch));
    for ([_]usize{ 48, 56, 64, 72, 80, 88 }) |at| {
        @memcpy(f.bytes, original);
        put(u64, f.bytes[at..], std.math.maxInt(u64));
        try rejected(f.bytes, scratch);
    }
    for ([_]usize{ 32, 34, 35, 36, 100, 102, 104 }) |at| {
        @memcpy(f.bytes, original);
        f.bytes[at] ^= 0x80;
        try rejected(f.bytes, scratch);
    }
}

test "image45 records reject invalid kinds reserved bits widths ids duplicates and bad targets" {
    const scratch = try std.testing.allocator.create(format.Workspace);
    defer std.testing.allocator.destroy(scratch);
    const f = try fixture(.normal);
    defer f.free();
    const original = try std.testing.allocator.dupe(u8, f.bytes);
    defer std.testing.allocator.free(original);
    for ([_]usize{ 0, 1, 2, 4, 8, 16, 24 }) |field| {
        @memcpy(f.bytes, original);
        f.bytes[f.records_at + field] = 0xff;
        try rejected(f.bytes, scratch);
    }
    @memcpy(f.bytes, original);
    @memcpy(f.bytes[f.records_at + 3 * format.record_size ..][0..format.record_size], f.bytes[f.records_at + 2 * format.record_size ..][0..format.record_size]);
    try rejected(f.bytes, scratch);
    // A target in a heap header rather than a payload is not an object reference.
    @memcpy(f.bytes, original);
    put(u64, f.bytes[f.records_at + format.record_size + 16 ..], 8);
    try rejected(f.bytes, scratch);
    // The recorded target must agree with the actual cell, even when CRC is repaired.
    @memcpy(f.bytes, original);
    put(u64, f.bytes[f.memory_at + @as(usize, @intCast(map.system_end)) ..], 0);
    try rejected(f.bytes, scratch);
    // A complete typed source cell may not straddle the end of dictionary data.
    @memcpy(f.bytes, original);
    put(u64, f.bytes[f.records_at + format.record_size + 8 ..], 12);
    try rejected(f.bytes, scratch);
}

test "image45 heap objects must be ordered disjoint reachable and within saved heap bounds" {
    const scratch = try std.testing.allocator.create(format.Workspace);
    defer std.testing.allocator.destroy(scratch);
    const f = try fixture(.normal);
    defer f.free();
    const original = try std.testing.allocator.dupe(u8, f.bytes);
    defer std.testing.allocator.free(original);
    for ([_]usize{ 0, 4, 8, 16 }) |field| {
        @memcpy(f.bytes, original);
        f.bytes[f.heap_at + field] = 0xff;
        try rejected(f.bytes, scratch);
    }
    @memcpy(f.bytes, original);
    put(u64, f.bytes[f.heap_at + 40 + 8 ..], 24);
    try rejected(f.bytes, scratch);
    // A cycle with no root in a word/system/data cell is unreachable and rejected.
    @memcpy(f.bytes, original);
    const root = f.records_at + format.record_size;
    format.writeRelocation(f.bytes[root..][0..format.record_size], .{ .storage = .data, .target = .null_address });
    put(u64, f.bytes[f.memory_at + @as(usize, @intCast(map.system_end)) ..], 0);
    try rejected(f.bytes, scratch);
}

test "image45 native word and operation tags are checked before enum decoding" {
    const scratch = try std.testing.allocator.create(format.Workspace);
    defer std.testing.allocator.destroy(scratch);
    const f = try fixture(.normal);
    defer f.free();
    const original = try std.testing.allocator.dupe(u8, f.bytes);
    defer std.testing.allocator.free(original);
    for ([_]usize{ @offsetOf(defs.Word, "kind"), @offsetOf(defs.Word, "builtin"), @offsetOf(defs.Word, "immediate"), @offsetOf(defs.Word, "has_does"), @offsetOf(defs.Word, "name_start"), @offsetOf(defs.Word, "wordlist") }) |field| {
        @memcpy(f.bytes, original);
        f.bytes[f.word_at + field] = if (field == @offsetOf(defs.Word, "wordlist")) 0xfe else 0xff;
        if (field == @offsetOf(defs.Word, "builtin")) @memset(f.bytes[f.word_at + field ..][0..@sizeOf(defs.Builtin)], 0xff);
        try rejected(f.bytes, scratch);
    }
    @memcpy(f.bytes, original);
    f.bytes[f.code_at + @offsetOf(defs.Op, "kind")] = 0xff;
    try rejected(f.bytes, scratch);
    @memcpy(f.bytes, original);
    const invalid = defs.Op{ .kind = .call, .value = 999 };
    @memcpy(f.bytes[f.code_at..][0..@sizeOf(defs.Op)], std.mem.asBytes(&invalid));
    try rejected(f.bytes, scratch);
}

test "image45 validates system null one-past-data and interior heap targets without inference" {
    const scratch = try std.testing.allocator.create(format.Workspace);
    defer std.testing.allocator.destroy(scratch);
    const f = try fixture(.normal);
    defer f.free();
    const original = try std.testing.allocator.dupe(u8, f.bytes);
    defer std.testing.allocator.free(original);
    const cases = [_]struct { target: format.Target, offset: u64, value: u64 }{
        .{ .target = .null_address, .offset = 0, .value = 0 },
        .{ .target = .system, .offset = @intCast(map.base_address), .value = @intCast(map.base_address) },
        .{ .target = .system, .offset = @intCast(map.source_file_table), .value = @intCast(map.source_file_table) },
        .{ .target = .data, .offset = 16, .value = @intCast(map.data_start + 16) },
        .{ .target = .heap, .offset = 17, .value = @as(u64, map.Sizes.small.m) + 17 },
    };
    for (cases) |case| {
        @memcpy(f.bytes, original);
        format.writeRelocation(f.bytes[f.records_at..][0..format.record_size], .{ .storage = .word, .target = case.target, .target_offset = case.offset });
        std.mem.writeInt(u64, f.bytes[f.word_at + @offsetOf(defs.Word, "value") ..][0..8], case.value, native_endian);
        try format.finish(f.bytes);
        _ = try format.parse(f.bytes, scratch);
    }
    @memcpy(f.bytes, original);
    format.writeRelocation(f.bytes[f.records_at..][0..format.record_size], .{ .storage = .word, .target = .system, .target_offset = @intCast(map.tib_address) });
    std.mem.writeInt(u64, f.bytes[f.word_at + @offsetOf(defs.Word, "value") ..][0..8], @intCast(map.tib_address), native_endian);
    try rejected(f.bytes, scratch);
}

test "image45 rejects overlapping memory registrations independently of reachability" {
    const scratch = try std.testing.allocator.create(format.Workspace);
    defer std.testing.allocator.destroy(scratch);
    const f = try fixture(.normal);
    defer f.free();
    const m: u64 = map.Sizes.small.m;
    std.mem.writeInt(u64, f.bytes[f.word_at + @offsetOf(defs.Word, "value") ..][0..8], m + 16, native_endian);
    format.writeRelocation(f.bytes[f.records_at..][0..format.record_size], .{ .storage = .word, .target = .heap, .target_offset = 16 });
    @memset(f.bytes[f.memory_at + @as(usize, @intCast(map.system_end)) ..][0..16], 0);
    format.writeRelocation(f.bytes[f.records_at + format.record_size ..][0..format.record_size], .{ .storage = .data, .target = .null_address });
    format.writeRelocation(f.bytes[f.records_at + 3 * format.record_size ..][0..format.record_size], .{ .storage = .data, .target = .null_address, .slot_offset = 4 });
    try rejected(f.bytes, scratch);
}

test "image45 rejects count limits and protected builtin value registrations before installation" {
    const scratch = try std.testing.allocator.create(format.Workspace);
    defer std.testing.allocator.destroy(scratch);
    const f = try fixture(.normal);
    defer f.free();
    const original = try std.testing.allocator.dupe(u8, f.bytes);
    defer std.testing.allocator.free(original);
    for ([_]usize{ 8, 12, 16, 20, 24, 28, 40, 44, 96 }) |at| {
        @memcpy(f.bytes, original);
        put(u32, f.bytes[at..], std.math.maxInt(u32));
        try rejected(f.bytes, scratch);
    }
    @memcpy(f.bytes, original);
    put(u32, f.bytes[96..], 1);
    try rejected(f.bytes, scratch);
    @memcpy(f.bytes, original);
    f.bytes[f.records_at + 1] = 0;
    put(u64, f.bytes[f.records_at + 16 ..], 1);
    try rejected(f.bytes, scratch);
}

// Deterministic malformed-byte exercise: verify the parser never mutates a dictionary
// and handles arbitrary native enum/offset changes even after a checksum is repaired.
test "image45 bounded mutation corpus does not panic or alter input bytes" {
    const scratch = try std.testing.allocator.create(format.Workspace);
    defer std.testing.allocator.destroy(scratch);
    const f = try fixture(.normal);
    defer f.free();
    const original = try std.testing.allocator.dupe(u8, f.bytes);
    defer std.testing.allocator.free(original);
    const positions = [_]usize{ 0, 8, 16, 32, 35, 40, 48, 72, 88, 96, 104, f.word_at, f.code_at, f.memory_at + @as(usize, @intCast(map.heap_top_address)), f.records_at, f.heap_at };
    for (positions) |at| for (0..8) |bit| {
        @memcpy(f.bytes, original);
        f.bytes[at] ^= @as(u8, 1) << @as(u3, @intCast(bit));
        try format.finish(f.bytes);
        const before = std.hash.Crc32.hash(f.bytes);
        _ = format.parse(f.bytes, scratch) catch {};
        try std.testing.expectEqual(before, std.hash.Crc32.hash(f.bytes));
    };
}

test "image45 canonical writers zero native padding and keep the specified 32 byte record" {
    var word_a: [@sizeOf(defs.Word)]u8 = @splat(0xaa);
    var word_b: [@sizeOf(defs.Word)]u8 = @splat(0x55);
    const word = defs.Word{ .kind = .constant, .name_len = 1, .value = 123, .data_here_before = map.data_start };
    format.writeWord(&word_a, word);
    format.writeWord(&word_b, word);
    try std.testing.expectEqualSlices(u8, &word_a, &word_b);
    const decoded = std.mem.bytesToValue(defs.Word, &word_a);
    try std.testing.expectEqual(@as(map.Cell, 123), decoded.value);
    try std.testing.expectEqual(defs.WordKind.constant, decoded.kind);
    var op: [@sizeOf(defs.Op)]u8 = @splat(0xaa);
    try format.writeOperation(&op, .{ .kind = .literal, .value = -1 });
    try std.testing.expectEqual(@as(map.Cell, -1), std.mem.bytesToValue(defs.Op, &op).value);
    try std.testing.expectError(error.InvalidImage, format.writeOperation(&op, .{ .kind = .call_colon, .value = 1 }));
    var object: [format.object_header_size]u8 = @splat(0xaa);
    format.writeObjectHeader(&object, 7, 256, 16);
    try std.testing.expectEqualSlices(u8, &.{ 7, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 16, 0, 0, 0, 0, 0, 0, 0 }, &object);
    var record: [32]u8 = undefined;
    format.writeRelocation(&record, .{ .storage = .data, .target = .heap, .slot_offset = 16, .target_offset = 48 });
    try std.testing.expectEqualSlices(u8, &.{ 2, 3, 0, 0, 0, 0, 0, 0, 16, 0, 0, 0, 0, 0, 0, 0, 48, 0, 0, 0, 0, 0, 0, 0, 8, 0, 0, 0, 0, 0, 0, 0 }, &record);
}
