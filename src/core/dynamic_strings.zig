//! Dynamic strings ($! and its relatives) and string arrays.

const defs = @import("defs.zig");
const forth = @import("../forth.zig");
const memory_map = @import("memory_map.zig");
const Cell = memory_map.Cell;
const RuntimeError = defs.RuntimeError;
const State = forth.State;
const UCell = memory_map.UCell;
const cell_size = memory_map.cell_size;
const errno_invalid = memory_map.errno_invalid;
const errno_no_memory = memory_map.errno_no_memory;

const registry = @import("address_registry.zig");

pub const StringRef = struct { address: Cell, length: usize };

/// Only persistent logical slots participate in images. Input/local slots remain
/// usable at runtime, but cannot become image roots merely by holding a string.
pub fn preparePointer(self: *State, slot: Cell) RuntimeError!void {
    _ = try self.memoryAddress(slot, cell_size);
    if (registry.classify(self, slot) == .data and !registry.storageValid(self, slot)) return error.InvalidAddress;
    if (registry.storageValid(self, slot)) try registry.ensureRoom(self, .memory, slot);
}
pub fn registerPointer(self: *State, slot: Cell) RuntimeError!void {
    if (registry.storageValid(self, slot)) try registry.registerMemory(self, slot);
}

/// Reserve a previously untyped owner before operations that can create other
/// registrations. On failure, remove only this newly reserved metadata entry.
pub fn reservePointer(self: *State, slot: Cell) RuntimeError!bool {
    try preparePointer(self, slot);
    if (!registry.storageValid(self, slot) or registry.index(self, .memory, slot) != null) return false;
    try registry.registerMemory(self, slot);
    return true;
}
pub fn cancelPointer(self: *State, slot: Cell, reserved: bool) void {
    if (!reserved) return;
    const at = registry.index(self, .memory, slot) orelse return;
    var i = at;
    while (i + 1 < self.addresses.count) : (i += 1) self.addresses.records[i] = self.addresses.records[i + 1];
    self.addresses.count -= 1;
    self.addresses.index_dirty = true;
    self.addresses.stable_writes = 0;
}

pub fn fetchString(self: *State, string_var: Cell) RuntimeError!StringRef {
    const buffer = try self.readCell(string_var);
    if (buffer == 0) return .{ .address = 0, .length = 0 };
    const length = try self.readCell(buffer);
    if (length < 0) return error.InvalidAddress;
    _ = try self.memoryAddress(buffer + cell_size, @intCast(length));
    return .{ .address = buffer + cell_size, .length = @intCast(length) };
}

/// Resizes the string buffer; new bytes are zero. Returns the (possibly moved) buffer.
pub fn setStringLength(self: *State, string_var: Cell, length: usize) RuntimeError!Cell {
    const reserved = try reservePointer(self, string_var);
    errdefer cancelPointer(self, string_var, reserved);
    const old_length = (try self.fetchString(string_var)).length;
    const buffer = switch (try self.heapResize(try self.readCell(string_var), cell_size + length)) {
        .address => |moved| moved,
        .no_memory => return self.throwIor(errno_no_memory),
        .bad_pointer => return self.throwIor(errno_invalid),
    };
    try self.writeCell(string_var, buffer);
    try registerPointer(self, string_var);
    try self.writeCell(buffer, @intCast(length));
    if (length > old_length) {
        const start: usize = @intCast(buffer + cell_size);
        @memset(self.memory[start + old_length .. start + length], 0);
        @import("address_registry.zig").written(self, @intCast(start + old_length), length - old_length, false);
    }
    return buffer;
}

pub fn freeString(self: *State, string_var: Cell) RuntimeError!void {
    if (!try self.heapFree(try self.readCell(string_var))) return self.throwIor(errno_invalid);
    try self.writeCell(string_var, 0);
}

/// Inserts (or, for $OVER, overwrites) `length` bytes from `source` at `offset`.
/// A source inside the same string is copied out first, since resizing may move it.
pub fn insertString(self: *State, string_var: Cell, offset: usize, source: Cell, length: usize, overwrite: bool) RuntimeError!void {
    _ = try self.memoryAddress(source, length);
    const old = try self.fetchString(string_var);
    const inside = old.address != 0 and source + @as(Cell, @intCast(length)) > old.address - cell_size and source < old.address + @as(Cell, @intCast(old.length));
    var from = source;
    var detached: ?Cell = null;
    defer if (detached) |copy| {
        _ = self.heapFree(copy) catch {};
    };
    if (inside and length != 0) {
        const copy = try self.heapAllocate(length) orelse return self.throwIor(errno_no_memory);
        detached = copy;
        try self.copyMemory(copy, source, length);
        from = copy;
    }
    const at = if (overwrite) offset else @min(offset, old.length);
    const new_length = if (overwrite) @max(old.length, at + length) else old.length + length;
    const buffer = try self.setStringLength(string_var, new_length);
    const text = buffer + cell_size;
    if (overwrite) {
        // $OVER past the end pads the gap with blanks, as gforth does.
        if (at > old.length) {
            @memset(self.memory[@intCast(text + @as(Cell, @intCast(old.length)))..@intCast(text + @as(Cell, @intCast(at)))], ' ');
            @import("address_registry.zig").written(self, text + @as(Cell, @intCast(old.length)), at - old.length, false);
        }
    } else {
        try self.copyMemory(text + @as(Cell, @intCast(at + length)), text + @as(Cell, @intCast(at)), old.length - at);
    }
    try self.copyMemory(text + @as(Cell, @intCast(at)), from, length);
}

/// Appends output bytes to a string (used while $TMP captures output).
pub fn appendString(self: *State, string_var: Cell, bytes: []const u8) RuntimeError!void {
    const memory_start = @intFromPtr(self.memory.ptr);
    const address = @intFromPtr(bytes.ptr);
    if (address >= memory_start and address < memory_start + self.memory.len) {
        const end = (try self.fetchString(string_var)).length;
        return self.insertString(string_var, end, @intCast(address - memory_start), bytes.len, false);
    }
    const end = (try self.fetchString(string_var)).length;
    const buffer = try self.setStringLength(string_var, end + bytes.len);
    const start: usize = @intCast(buffer + cell_size);
    @memcpy(self.memory[start + end .. start + end + bytes.len], bytes);
    @import("address_registry.zig").written(self, @intCast(start + end), bytes.len, false);
}

pub fn stringArrayCount(self: *State, array_var: Cell) RuntimeError!usize {
    return (try self.fetchString(array_var)).length / cell_size;
}

/// Check ownership metadata before growing an array for a string-producing word.
pub fn prepareArrayElement(self: *State, array_var: Cell, index: usize) RuntimeError!void {
    try preparePointer(self, array_var);
    const array = try fetchString(self, array_var);
    const owner_needed: usize = if (registry.storageValid(self, array_var) and registry.index(self, .memory, array_var) == null) 1 else 0;
    const existing = index < array.length / cell_size and registry.index(self, .memory, array.address + @as(Cell, @intCast(index * cell_size))) != null;
    const needed = owner_needed + @as(usize, if (existing) 0 else 1);
    if (needed > registry.capacity - self.addresses.count) return error.MemoryExhausted;
}

/// Address of element `index`, growing the array with empty strings as needed.
pub fn stringArrayElement(self: *State, array_var: Cell, index: usize) RuntimeError!Cell {
    if (index >= @divTrunc(self.sizes.heapEnd() - self.sizes.heapBase(), cell_size)) return self.throwIor(errno_no_memory);
    const needed = (index + 1) * cell_size;
    if ((try self.fetchString(array_var)).length < needed) _ = try self.setStringLength(array_var, needed);
    return (try self.fetchString(array_var)).address + @as(Cell, @intCast(index * cell_size));
}

/// Reads the file line by line into the string array, replacing its contents.
pub fn slurpLines(self: *State, fileid: Cell, array_var: Cell) RuntimeError!void {
    var count: usize = 0;
    while (true) {
        try prepareArrayElement(self, array_var, count);
        if (!try slurpLine(self, fileid, try self.stringArrayElement(array_var, count))) break;
        count += 1;
    }
    const total = try self.stringArrayCount(array_var);
    for (count..total) |index| try self.freeString(try self.stringArrayElement(array_var, index));
    _ = try self.setStringLength(array_var, count * cell_size);
}

/// Reads the next line of the file into the string variable, replacing its text, for
/// $SLURP-LINE and $[]SLURP. At the end of the file it gives false and, as in gforth,
/// leaves an empty string.
pub fn slurpLine(self: *State, fileid: Cell, string_var: Cell) RuntimeError!bool {
    const reserved = try reservePointer(self, string_var);
    errdefer cancelPointer(self, string_var, reserved);
    const files = try self.fileOps();
    var chunk: [256]u8 = undefined;
    var temporary: Cell = 0;
    var length: usize = 0;
    errdefer _ = self.heapFree(temporary) catch false;
    var found = false;
    while (true) {
        const result = files.read_line(self.writer.context, fileid, &chunk);
        if (result.ior != 0) return self.throwCode(result.ior);
        if (!result.found) break;
        found = true;
        length += result.length;
        temporary = switch (try self.heapResize(temporary, cell_size + length)) {
            .address => |moved| moved,
            .no_memory => return self.throwIor(errno_no_memory),
            .bad_pointer => return self.throwIor(errno_invalid),
        };
        const at: usize = @intCast(temporary + cell_size + @as(Cell, @intCast(length - result.length)));
        @memcpy(self.memory[at..][0..result.length], chunk[0..result.length]);
        registry.written(self, @intCast(at), result.length, false);
        if (result.length < chunk.len) break;
    }
    if (temporary == 0) temporary = try self.heapAllocate(cell_size) orelse return self.throwIor(errno_no_memory);
    try self.writeCell(temporary, @intCast(length));
    const previous = try self.readCell(string_var);
    if (!try self.heapFree(previous)) return self.throwIor(errno_invalid);
    try self.writeCell(string_var, temporary);
    try registerPointer(self, string_var);
    return found;
}

/// Appends the rest of the file, from its position to the end, to the string variable.
pub fn slurpRest(self: *State, fileid: Cell, string_var: Cell) RuntimeError!void {
    const files = try self.fileOps();
    var chunk: [4096]u8 = undefined;
    while (true) {
        const result = files.read(self.writer.context, fileid, &chunk);
        if (result.ior != 0) return self.throwCode(result.ior);
        if (result.value == 0) break;
        try self.appendString(string_var, chunk[0..@intCast(result.value)]);
    }
    if ((try self.fetchString(string_var)).address == 0) try self.executeStringInit(string_var);
}

/// Reads the whole named file for SLURP-FILE and $SLURP-FILE: into the string variable
/// when one is given, replacing its text, or else into a new ALLOCATE block.
pub fn slurpFile(self: *State, name: []const u8, string_var: ?Cell) RuntimeError!StringRef {
    const files = try self.fileOps();
    const opened = files.open(self.writer.context, name, .read_only, false);
    if (opened.ior != 0) return self.throwCode(opened.ior);
    const fileid: Cell = @bitCast(opened.value);
    const text = readWholeFile(self, fileid, string_var) catch |err| {
        _ = files.close(self.writer.context, fileid);
        return err;
    };
    const closed = files.close(self.writer.context, fileid);
    if (closed != 0) {
        if (string_var == null) _ = try self.heapFree(text.address);
        return self.throwCode(closed);
    }
    return text;
}

fn readWholeFile(self: *State, fileid: Cell, string_var: ?Cell) RuntimeError!StringRef {
    const files = try self.fileOps();
    const sized = files.size(self.writer.context, fileid);
    if (sized.ior != 0) return self.throwCode(sized.ior);
    if (sized.value > @as(UCell, @intCast(self.sizes.heapEnd() - self.sizes.heapBase()))) return self.throwIor(errno_no_memory);
    const size: usize = @intCast(sized.value);
    const address = if (string_var) |string|
        (try self.setStringLength(string, size)) + cell_size
    else
        try self.heapAllocate(size) orelse return self.throwIor(errno_no_memory);
    errdefer if (string_var == null) {
        _ = self.heapFree(address) catch {};
    };
    const start: usize = @intCast(address);
    var length: usize = 0;
    while (length < size) {
        const result = files.read(self.writer.context, fileid, self.memory[start + length .. start + size]);
        if (result.ior != 0) return self.throwCode(result.ior);
        if (result.value == 0) break;
        length += @intCast(result.value);
    }
    // A file that shrank since its size was taken gives fewer bytes.
    if (length < size) {
        if (string_var) |string| return .{ .address = (try self.setStringLength(string, length)) + cell_size, .length = length };
    }
    return .{ .address = address, .length = length };
}

pub fn executeStringInit(self: *State, string_var: Cell) RuntimeError!void {
    try self.push(string_var);
    try self.executeBuiltin(.string_init);
}
