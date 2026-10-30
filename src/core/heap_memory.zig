//! The ALLOCATE heap: blocks with a size cell and a used cell.

const defs = @import("defs.zig");
const forth = @import("../forth.zig");
const memory_map = @import("memory_map.zig");
const Cell = memory_map.Cell;
const HeapResult = defs.HeapResult;
const RuntimeError = defs.RuntimeError;
const State = forth.State;
const UCell = memory_map.UCell;
const cell_size = memory_map.cell_size;
const heap_base = memory_map.heap_base;
const heap_end = memory_map.heap_end;
const heap_header = memory_map.heap_header;
const heap_top_address = memory_map.heap_top_address;

pub fn heapTop(self: *State) Cell {
    return self.readCell(heap_top_address) catch unreachable;
}

/// Reads a block size, rejecting headers that would leave the used heap.
pub fn blockSize(self: *State, block: Cell) RuntimeError!Cell {
    const size = try self.readCell(block);
    if (size < 0 or @rem(size, cell_size) != 0 or size > self.heapTop() - block - heap_header) return error.InvalidAddress;
    return size;
}

pub fn blockUsed(self: *State, block: Cell) RuntimeError!bool {
    return try self.readCell(block + cell_size) != 0;
}

pub fn setBlock(self: *State, block: Cell, size: Cell, used: bool) void {
    self.writeCell(block, size) catch unreachable;
    self.writeCell(block + cell_size, @intFromBool(used)) catch unreachable;
}

/// Gives `block` exactly `need` bytes when the rest is large enough to form a free block.
pub fn splitBlock(self: *State, block: Cell, size: Cell, need: Cell, used: bool) void {
    if (size - need < heap_header + cell_size) {
        self.setBlock(block, size, used);
        return;
    }
    self.setBlock(block, need, used);
    self.setBlock(block + heap_header + need, size - need - heap_header, false);
}

pub fn heapNeed(size: UCell) ?Cell {
    if (size > heap_end - heap_base - heap_header) return null;
    return @intCast((size + cell_size - 1) & ~@as(UCell, cell_size - 1));
}

pub fn heapAllocate(self: *State, size: UCell) RuntimeError!?Cell {
    const need = heapNeed(size) orelse return null;
    const top = self.heapTop();
    var block = heap_base;
    while (block < top) {
        const size_here = try self.blockSize(block);
        if (!try self.blockUsed(block) and size_here >= need) {
            self.splitBlock(block, size_here, need, true);
            return block + heap_header;
        }
        block += heap_header + size_here;
    }
    if (heap_end - top < heap_header + need) return null;
    self.setBlock(top, need, true);
    self.writeCell(heap_top_address, top + heap_header + need) catch unreachable;
    return top + heap_header;
}

/// Finds the used block whose payload starts at `address`.
pub fn findBlock(self: *State, address: Cell) RuntimeError!?Cell {
    const top = self.heapTop();
    var block = heap_base;
    while (block < top and block + heap_header <= address) {
        const size = try self.blockSize(block);
        if (block + heap_header == address) return if (try self.blockUsed(block)) block else null;
        block += heap_header + size;
    }
    return null;
}

/// Merges neighbouring free blocks and gives a free last block back to the heap top.
pub fn coalesceHeap(self: *State) RuntimeError!void {
    const top = self.heapTop();
    var block = heap_base;
    var last: ?Cell = null;
    while (block < top) {
        var size = try self.blockSize(block);
        if (!try self.blockUsed(block)) {
            var next = block + heap_header + size;
            while (next < top and !try self.blockUsed(next)) {
                size += heap_header + try self.blockSize(next);
                next = block + heap_header + size;
            }
            self.setBlock(block, size, false);
        }
        last = block;
        block += heap_header + size;
    }
    if (last) |block_at_end| {
        if (!try self.blockUsed(block_at_end)) self.writeCell(heap_top_address, block_at_end) catch unreachable;
    }
}

/// Frees an ALLOCATE address; 0 is accepted. Returns false for an unknown address.
pub fn heapFree(self: *State, address: Cell) RuntimeError!bool {
    if (address == 0) return true;
    const block = try self.findBlock(address) orelse return false;
    self.setBlock(block, try self.blockSize(block), false);
    try self.coalesceHeap();
    return true;
}

pub fn heapResize(self: *State, address: Cell, size: UCell) RuntimeError!HeapResult {
    if (address == 0) return if (try self.heapAllocate(size)) |fresh| .{ .address = fresh } else .no_memory;
    const block = try self.findBlock(address) orelse return .bad_pointer;
    const need = heapNeed(size) orelse return .no_memory;
    const old_size = try self.blockSize(block);
    // Grow in place by absorbing following free blocks, or past the heap top.
    const top = self.heapTop();
    var available = old_size;
    var next = block + heap_header + available;
    while (available < need and next < top and !try self.blockUsed(next)) {
        available += heap_header + try self.blockSize(next);
        next = block + heap_header + available;
    }
    if (available >= need) {
        self.splitBlock(block, available, need, true);
        try self.coalesceHeap();
        return .{ .address = address };
    }
    if (next == top and heap_end - block - heap_header >= need) {
        self.setBlock(block, need, true);
        self.writeCell(heap_top_address, block + heap_header + need) catch unreachable;
        return .{ .address = address };
    }
    const moved = try self.heapAllocate(size) orelse return .no_memory;
    self.copyMemory(moved, address, @intCast(old_size));
    _ = try self.heapFree(address);
    return .{ .address = moved };
}
