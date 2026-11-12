//! Standard block storage metadata. Runtime buffers are separate from dictionary data.
const std = @import("std");
const Cell = @import("memory_map.zig").Cell;
const RuntimeError = @import("defs.zig").RuntimeError;

pub const block_size = 1024;
pub const line_size = 64;
pub const buffer_count = 32;
pub const block_limit = 0x200000;
pub const default_file = "blocks.fb";

/// BLOCK/BUFFER allow zero; LOAD/THRU require positive block numbers.
pub fn number(value: Cell, executable: bool) RuntimeError!u32 {
    if (value < @as(Cell, if (executable) 1 else 0) or value >= block_limit) return error.InvalidBlockNumber;
    return @intCast(value);
}

pub const Buffer = struct {
    number: ?u32 = null,
    modified: bool = false,
};

pub fn slot(value: u32) usize {
    return value % buffer_count;
}

test "standard block numbers reject negative, limit and executable zero" {
    try std.testing.expectEqual(@as(u32, 0), try number(0, false));
    try std.testing.expectEqual(@as(u32, block_limit - 1), try number(block_limit - 1, true));
    try std.testing.expectError(error.InvalidBlockNumber, number(-1, false));
    try std.testing.expectError(error.InvalidBlockNumber, number(block_limit, false));
    try std.testing.expectError(error.InvalidBlockNumber, number(0, true));
    try std.testing.expectEqual(slot(1), slot(33));
}

const forth = @import("../forth.zig");
const map = @import("memory_map.zig");
const Builtin = @import("defs.zig").Builtin;
pub const words = [_]Builtin{ .block, .block_buffer, .block_update, .save_buffers, .empty_buffers, .flush_buffers, .blk, .scr, .load_block, .thru, .list_block };

pub const Storage = struct {
    file: ?Cell = null,
    read_only: bool = false,
    buffers: [buffer_count]Buffer = @splat(.{}),
    current: ?usize = null,
};

fn check(self: *forth.State, ior: Cell) RuntimeError!void {
    if (ior != 0) return self.throwCode(ior);
}

fn open(self: *forth.State) RuntimeError!Cell {
    if (self.block_storage.file) |file| return file;
    const files = try self.fileOps();
    var result = files.open(self.writer.context, default_file, .read_write, false);
    // Only a missing file authorizes CREATE; a permission error must not truncate it.
    var read_only = false;
    if (result.ior == map.errnoIor(2)) {
        result = files.open(self.writer.context, default_file, .read_write, true);
    } else if (result.ior == map.errnoIor(13) or result.ior == map.errnoIor(1) or result.ior == map.errnoIor(30)) {
        // Retry only permission/read-only failures, without hiding the original
        // failure if read-only access is also denied.
        const readonly = files.open(self.writer.context, default_file, .read_only, false);
        if (readonly.ior == 0) {
            result = readonly;
            read_only = true;
        }
    }
    try check(self, result.ior);
    const file: Cell = @bitCast(result.value);
    self.block_storage.file = file;
    self.block_storage.read_only = read_only;
    return file;
}

fn address(index: usize) Cell {
    return map.block_buffer_base + @as(Cell, @intCast(index * block_size));
}

fn bytes(self: *forth.State, index: usize) []u8 {
    const at: usize = @intCast(address(index));
    return self.memory[at..][0..block_size];
}

fn save(self: *forth.State, index: usize) RuntimeError!void {
    const buffer = &self.block_storage.buffers[index];
    if (!buffer.modified) return;
    const block = buffer.number orelse return;
    const file = try open(self);
    if (self.block_storage.read_only) return self.throwCode(map.errnoIor(13));
    const files = try self.fileOps();
    try check(self, files.reposition(self.writer.context, file, @as(u64, block) * block_size));
    try check(self, files.write(self.writer.context, file, bytes(self, index)));
    // Flush before clearing the flag: a failed write/flush must remain retryable.
    try check(self, files.flush(self.writer.context, file));
    buffer.modified = false;
}

pub fn get(self: *forth.State, value: Cell) RuntimeError!Cell {
    const block = try number(value, false);
    const index = slot(block);
    const buffer = &self.block_storage.buffers[index];
    if (buffer.number != block) {
        try save(self, index);
        const file = try open(self);
        const files = try self.fileOps();
        try check(self, files.reposition(self.writer.context, file, @as(u64, block) * block_size));
        // Stage the read so failures cannot corrupt the old buffer's identity/content.
        var incoming: [block_size]u8 = @splat(' ');
        var length: usize = 0;
        while (length < block_size) {
            const result = files.read(self.writer.context, file, incoming[length..]);
            try check(self, result.ior);
            if (result.value > block_size - length) return error.HostFailed;
            if (result.value == 0) break;
            length += @intCast(result.value);
        }
        @memcpy(bytes(self, index), &incoming);
        buffer.* = .{ .number = block };
    }
    self.block_storage.current = index;
    return address(index);
}

pub fn saveAll(self: *forth.State) RuntimeError!void {
    for (0..buffer_count) |index| try save(self, index);
}

pub fn empty(self: *forth.State) void {
    self.block_storage.buffers = @splat(.{});
    self.block_storage.current = null;
}

pub fn execute(self: *forth.State, comptime builtin: Builtin) RuntimeError!void {
    switch (builtin) {
        .blk => try self.push(map.blk_address),
        .scr => try self.push(map.scr_address),
        .load_block => try load(self, try self.pop()),
        .thru => {
            const last = try number(try self.pop(), true);
            const first = try number(try self.pop(), true);
            var block = first;
            while (block <= last and !self.halted) : (block += 1) try load(self, block);
        },
        .list_block => try list(self, try self.pop()),
        .block, .block_buffer => try self.push(try get(self, try self.pop())),
        .block_update => if (self.block_storage.current) |index| {
            self.block_storage.buffers[index].modified = true;
        },
        .save_buffers => try saveAll(self),
        .empty_buffers => empty(self),
        .flush_buffers => {
            try saveAll(self);
            empty(self);
        },
        else => unreachable,
    }
}

/// Each nested LOAD owns a logical source snapshot, so a colliding BLOCK or
/// nested LOAD cannot overwrite the caller's still-active input.
pub fn selectSource(self: *forth.State, value: Cell) RuntimeError![]const u8 {
    _ = try number(value, false);
    if (self.block_depth == 0) return error.InputUnavailable;
    const source = try get(self, value);
    const target: usize = @intCast(map.block_source_base + @as(Cell, @intCast((self.block_depth - 1) * block_size)));
    @memcpy(self.memory[target..][0..block_size], self.memory[@intCast(source)..][0..block_size]);
    try self.writeCell(map.blk_address, value);
    self.block_source_numbers[self.block_depth - 1] = value;
    return self.memory[target..][0..block_size];
}

pub fn currentSource(self: *forth.State) RuntimeError![]const u8 {
    if (self.block_depth == 0) return error.InputUnavailable;
    const current = self.readCellConst(map.blk_address);
    if (self.block_source_numbers[self.block_depth - 1] != current) return selectSource(self, current);
    const target: usize = @intCast(map.block_source_base + @as(Cell, @intCast((self.block_depth - 1) * block_size)));
    return self.memory[target..][0..block_size];
}

pub fn refill(self: *forth.State) RuntimeError![]const u8 {
    const current = self.readCellConst(map.blk_address);
    if (current < 0 or current >= block_limit - 1) return error.InvalidBlockNumber;
    return selectSource(self, current + 1);
}

pub fn load(self: *forth.State, value: Cell) RuntimeError!void {
    _ = try number(value, true);
    if (self.block_depth == map.max_include_depth) return error.IncludeNesting;
    const previous = self.readCellConst(map.blk_address);
    self.block_depth += 1;
    defer {
        self.block_depth -= 1;
        self.writeCell(map.blk_address, previous) catch unreachable;
    }
    const source = try selectSource(self, value);
    try self.interpretSource(source, .block);
}

fn list(self: *forth.State, value: Cell) RuntimeError!void {
    const source = try get(self, value);
    try self.writeCell(map.scr_address, value);
    self.write("Screen ");
    self.writeNumberDecimal(value);
    self.write(" ");
    self.write(if (self.block_storage.buffers[slot(@intCast(value))].modified) "modified     \n" else "not modified     \n");
    for (0..16) |line| {
        if (line < 10) self.write(" ");
        self.writeNumberDecimal(@intCast(line));
        self.write(" ");
        const at: usize = @intCast(source + @as(Cell, @intCast(line * line_size)));
        self.write(self.memory[at..][0..line_size]);
        self.write("\n");
    }
}
