//! Explicit address types. Values are never inferred to be pointers from raw cells.
const std = @import("std");
const forth = @import("../forth.zig");
const map = @import("memory_map.zig");
const defs = @import("defs.zig");
const Cell = map.Cell;
const State = forth.State;
const RuntimeError = defs.RuntimeError;
pub const capacity = 2048;
pub const Kind = enum { memory, word };
pub const Status = enum { valid, damaged, invalid };
pub const Region = enum { null_address, system, data, heap, invalid };
pub const Record = struct {
    kind: Kind = .memory,
    slot: Cell = 0,
    value: Cell = 0,
    target: Region = .null_address,
    status: Status = .valid,
};
pub const Registry = struct {
    records: [capacity]Record = undefined,
    count: usize = 0,
    memory_order: [capacity]u16 = undefined,
    memory_count: usize = 0,
    index_dirty: bool = true,
    stable_writes: usize = 0,
};
pub const Direction = enum { move, forward, backward };

pub fn index(self: *const State, kind: Kind, slot: Cell) ?usize {
    for (self.addresses.records[0..self.addresses.count], 0..) |record, i| {
        if (record.kind == kind and record.slot == slot) return i;
    }
    return null;
}

pub fn ensureRoom(self: *const State, kind: Kind, slot: Cell) RuntimeError!void {
    if (index(self, kind, slot) == null and self.addresses.count == capacity) return error.MemoryExhausted;
}

/// The target's lifetime is tracked separately from its numerical value. An invalidated
/// target stays invalid until an explicit full-cell update, even if memory is reused.
pub fn classify(self: *State, value: Cell) Region {
    if (value == 0) return .null_address;
    if (value < 0) return .invalid;
    if (value < map.system_end) return .system;
    if (value >= map.source_file_table and value < map.source_file_loaded_flags + map.max_source_files) return .system;
    // HERE itself may be registered before a following allocation fills that location.
    if (value >= map.data_start and value <= self.data_here) return .data;
    if (heapContains(self, value, 1)) return .heap;
    return .invalid;
}

fn heapContains(self: *State, address: Cell, width: usize) bool {
    if (address < self.sizes.heapBase() or address >= self.heapTop()) return false;
    var block = self.sizes.heapBase();
    const top = self.heapTop();
    while (block < top) {
        const size = self.blockSize(block) catch return false;
        const start = block + map.heap_header;
        if (address >= start and address <= start + size) {
            if (!(self.blockUsed(block) catch return false)) return false;
            return @as(u64, @intCast(width)) <= @as(u64, @intCast(start + size - address));
        }
        block = start + size;
    }
    return false;
}

pub fn storageValid(self: *State, slot: Cell) bool {
    const in_system = slot >= 0 and slot <= map.system_end - 8;
    const in_sources = slot >= map.source_file_table and slot <= map.source_file_loaded_flags + map.max_source_files - 8;
    const in_data = slot >= map.data_start and slot <= self.data_here - 8;
    return in_system or in_sources or in_data or heapContains(self, slot, 8);
}

fn currentRecord(self: *State, kind: Kind, slot: Cell, value: Cell) Record {
    const target = classify(self, value);
    return .{ .kind = kind, .slot = slot, .value = value, .target = target, .status = if (target == .invalid or (kind == .memory and !storageValid(self, slot))) .invalid else .valid };
}

pub fn registerMemory(self: *State, slot: Cell) RuntimeError!void {
    _ = try self.memoryAddress(slot, 8);
    try put(self, currentRecord(self, .memory, slot, try self.readCell(slot)));
}

pub fn registerWord(self: *State, id: u16) RuntimeError!void {
    try put(self, currentRecord(self, .word, id, self.words[id].value));
}

fn put(self: *State, record: Record) RuntimeError!void {
    if (index(self, record.kind, record.slot)) |i| {
        self.addresses.records[i] = record;
    } else {
        if (self.addresses.count == capacity) return error.MemoryExhausted;
        self.addresses.records[self.addresses.count] = record;
        self.addresses.count += 1;
        self.addresses.index_dirty = true;
        self.addresses.stable_writes = 0;
    }
}

fn overlaps(a: Cell, length: usize, slot: Cell) bool {
    // Callers already validated the write range against logical memory.
    return @as(i128, a) < @as(i128, slot) + 8 and @as(i128, a) + length > slot;
}

/// Called after writes. Only an exact full-cell replacement repairs a typed slot.
pub fn written(self: *State, address: Cell, length: usize, full_cell: bool) void {
    if (length == 0 or self.addresses.count == 0) return;
    // Frequent mutations should cost a linear notification, not a fresh sort.
    // Build the binary-search index only after a run of stable writes.
    if (self.addresses.index_dirty and self.addresses.stable_writes < 32) {
        self.addresses.stable_writes += 1;
        for (self.addresses.records[0..self.addresses.count]) |*record| notifyRecord(self, record, address, length, full_cell);
        return;
    }
    ensureIndex(&self.addresses);
    var low: usize = 0;
    var high = self.addresses.memory_count;
    while (low < high) {
        const mid = low + (high - low) / 2;
        const slot = self.addresses.records[self.addresses.memory_order[mid]].slot;
        if (@as(i128, slot) + 8 <= address) low = mid + 1 else high = mid;
    }
    for (self.addresses.memory_order[low..self.addresses.memory_count]) |id| {
        const record = &self.addresses.records[id];
        if (@as(i128, record.slot) >= @as(i128, address) + length) break;
        notifyRecord(self, record, address, length, full_cell);
    }
}

fn notifyRecord(self: *State, record: *Record, address: Cell, length: usize, full_cell: bool) void {
    if (record.kind != .memory or !overlaps(address, length, record.slot)) return;
    if (full_cell and length == 8 and address == record.slot) {
        const value = self.readCell(address) catch {
            record.status = .invalid;
            return;
        };
        record.* = currentRecord(self, .memory, address, value);
    } else record.status = .damaged;
}

/// Drops registrations whose storage disappeared, and invalidates surviving references.
pub fn discardRange(self: *State, start: Cell, end: Cell, region: Region, include_end: bool) void {
    if (end <= start) return;
    var out: usize = 0;
    for (self.addresses.records[0..self.addresses.count]) |original| {
        var record = original;
        if (record.kind == .memory and @as(i128, record.slot) < end and @as(i128, record.slot) + 8 > start) continue;
        if (record.target == region and record.value >= start and (record.value < end or (include_end and record.value == end))) record.status = .invalid;
        self.addresses.records[out] = record;
        out += 1;
    }
    if (out != self.addresses.count) {
        self.addresses.index_dirty = true;
        self.addresses.stable_writes = 0;
    }
    self.addresses.count = out;
}

pub fn forgetWords(self: *State, first: u16) void {
    var out: usize = 0;
    for (self.addresses.records[0..self.addresses.count]) |record| {
        if (record.kind == .word and record.slot >= first) continue;
        self.addresses.records[out] = record;
        out += 1;
    }
    if (out != self.addresses.count) {
        self.addresses.index_dirty = true;
        self.addresses.stable_writes = 0;
    }
    self.addresses.count = out;
}

/// Copy registrations from a pre-copy snapshot. Byte order follows the specific MOVE
/// operation; destructive CMOVE overlap must not invent a valid pointer after smearing.
pub fn copy(self: *State, destination: Cell, source: Cell, length: usize, direction: Direction) RuntimeError!void {
    if (length == 0) return;
    if (self.addresses.count == 0) return copyBytes(self, destination, source, length, direction);
    return @call(.never_inline, copyTracked, .{ self, destination, source, length, direction });
}

fn copyTracked(self: *State, destination: Cell, source: Cell, length: usize, direction: Direction) RuntimeError!void {
    if (length == 0) return;
    var saved: [capacity]Record = undefined;
    var count: usize = 0;
    var needed: usize = 0;
    for (self.addresses.records[0..self.addresses.count]) |record| {
        if (record.kind != .memory or record.slot < source or @as(i128, record.slot) + 8 > @as(i128, source) + length) continue;
        var moved = record;
        moved.slot = destination + (record.slot - source);
        saved[count] = moved;
        count += 1;
        if (index(self, .memory, moved.slot) == null) needed += 1;
    }
    if (needed > capacity - self.addresses.count) return error.MemoryExhausted;
    copyBytes(self, destination, source, length, direction);
    // A partial destination slot is damaged, even if its bytes happened not to change.
    written(self, destination, length, false);
    for (self.addresses.records[0..self.addresses.count]) |*record| {
        if (record.kind == .memory and record.slot >= destination and @as(i128, record.slot) + 8 <= @as(i128, destination) + length)
            record.* = currentRecord(self, .memory, record.slot, self.readCell(record.slot) catch unreachable);
    }
    for (saved[0..count]) |original| {
        var record = original;
        if (!storageValid(self, record.slot)) record.status = .invalid else if ((self.readCell(record.slot) catch unreachable) != record.value) record.status = .damaged;
        try put(self, record); // Capacity was checked before any byte was copied.
    }
}

fn copyBytes(self: *State, destination: Cell, source: Cell, length: usize, direction: Direction) void {
    const to: usize = @intCast(destination);
    const from: usize = @intCast(source);
    if (direction == .forward) {
        for (0..length) |i| self.memory[to + i] = self.memory[from + i];
    } else if (direction == .backward) {
        var i = length;
        while (i > 0) {
            i -= 1;
            self.memory[to + i] = self.memory[from + i];
        }
    } else if (to <= from) std.mem.copyForwards(u8, self.memory[to..][0..length], self.memory[from..][0..length]) else std.mem.copyBackwards(u8, self.memory[to..][0..length], self.memory[from..][0..length]);
}

pub fn validate(self: *State) RuntimeError!void {
    for (self.addresses.records[0..self.addresses.count], 0..) |record, i| {
        if (record.status != .valid) return error.InvalidAddress;
        if (record.kind == .memory) {
            for (self.addresses.records[i + 1 .. self.addresses.count]) |other| {
                if (other.kind == .memory and overlaps(record.slot, 8, other.slot)) return error.InvalidAddress;
            }
        }
        try validateRecord(self, record);
    }
}

/// Validate one selected graph edge without scanning unreachable heap records.
pub fn validateRecord(self: *State, record: Record) RuntimeError!void {
    if (record.status != .valid) return error.InvalidAddress;
    const actual = if (record.kind == .word) blk: {
        if (record.slot < 0 or record.slot >= self.word_count) return error.InvalidAddress;
        break :blk self.words[@intCast(record.slot)].value;
    } else blk: {
        if (!storageValid(self, record.slot)) return error.InvalidAddress;
        break :blk try self.readCell(record.slot);
    };
    if (actual != record.value or classify(self, actual) != record.target) return error.InvalidAddress;
}

fn ensureIndex(registry: *Registry) void {
    if (!registry.index_dirty) return;
    registry.memory_count = 0;
    for (registry.records[0..registry.count], 0..) |record, i| {
        if (record.kind != .memory) continue;
        registry.memory_order[registry.memory_count] = @intCast(i);
        registry.memory_count += 1;
    }
    std.mem.sort(u16, registry.memory_order[0..registry.memory_count], registry, struct {
        fn before(r: *Registry, a: u16, b: u16) bool {
            return r.records[a].slot < r.records[b].slot;
        }
    }.before);
    registry.index_dirty = false;
}

/// RESIZE owns and discards the old block. Move its registrations instead of
/// temporarily duplicating them and consuming twice the registry capacity.
pub fn relocateBlock(self: *State, destination: Cell, source: Cell, length: usize) RuntimeError!void {
    _ = try self.memoryAddress(destination, length);
    _ = try self.memoryAddress(source, length);
    if (length == 0) return;
    if (@as(i128, destination) < @as(i128, source) + length and @as(i128, source) < @as(i128, destination) + length) return error.InvalidAddress;
    copyBytes(self, destination, source, length, .move);
    written(self, destination, length, false);
    var out: usize = 0;
    for (self.addresses.records[0..self.addresses.count]) |original| {
        var record = original;
        if (record.kind == .memory and record.slot >= destination and @as(i128, record.slot) + 8 <= @as(i128, destination) + length) continue;
        if (record.kind == .memory and record.slot >= source and @as(i128, record.slot) + 8 <= @as(i128, source) + length) record.slot += destination - source;
        self.addresses.records[out] = record;
        out += 1;
    }
    self.addresses.count = out;
    self.addresses.index_dirty = true;
    self.addresses.stable_writes = 0;
}
