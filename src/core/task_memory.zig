//! Worker-only logical memory preflight. Never called by the plain VM.
const std = @import("std");
const forth = @import("../forth.zig");
const defs = @import("defs.zig");
const permissions = @import("task_permissions.zig");
const scopes = @import("task_context.zig");
const Cell = forth.Cell;
const Error = forth.RuntimeError;

fn checkpoint(vm: *forth.State) Error!void {
    if (vm.workerCancellation().?.isRequested()) return error.TaskCancelled;
}
fn validate(vm: *forth.State, accesses: []const permissions.Access, bytes: usize) Error!void {
    const options = scopes.options(vm);
    const gate = options.memory_gate orelse return error.InvalidAddress;
    if (!gate.permits(accesses, bytes, options.max_native_bytes)) return error.InvalidAddress;
}
fn access(address: Cell, length: Cell, write: bool) permissions.Access {
    return .{ .address = address, .length = length, .write = write };
}
fn positive(n: Cell) Cell {
    return @max(0, n);
}
fn add(a: Cell, b: Cell) Error!Cell {
    const sum = @addWithOverflow(a, b);
    if (sum[1] != 0) return error.InvalidAddress;
    return sum[0];
}
fn multiply(a: Cell, b: Cell) Error!Cell {
    const product = @mulWithOverflow(a, b);
    if (product[1] != 0) return error.InvalidAddress;
    return product[0];
}
fn check(vm: *forth.State, accesses: []const permissions.Access) Error!void {
    var total: usize = 0;
    for (accesses) |item| {
        const size = std.math.cast(usize, item.length) orelse return error.InvalidAddress;
        const sum = @addWithOverflow(total, size);
        if (sum[1] != 0) return error.InvalidAddress;
        total = sum[0];
    }
    try validate(vm, accesses, total);
}
fn top(vm: *forth.State, n: usize) Error!Cell {
    try vm.requireDepth(n + 1);
    return vm.data_stack[vm.data_depth - n - 1];
}
fn isMemory(b: defs.Builtin) bool {
    return switch (b) {
        .fetch, .store, .cfetch, .cstore, .add_store, .inc_store, .dec_store, .zero_store, .off, .on, .array_fetch, .array_store, .erase, .fill, .move, .cmove, .two_fetch, .two_store, .count, .place, .compare, .search, .minus_trailing, .blank_fill, .cmove_up, .scan, .skip, .str_equal, .string_prefix_query, .plus_place => true,
        else => false,
    };
}
pub fn before(vm: *forth.State, b: defs.Builtin) Error!void {
    switch (b) {
        .roll, .pick, .n_to_r, .n_r_from => {
            try checkpoint(vm);
            const n = if (b == .n_r_from) blk: {
                if (vm.return_depth == 0) return error.ReturnStackUnderflow;
                break :blk vm.return_stack[vm.return_depth - 1];
            } else try top(vm, 0);
            if (n >= 0) {
                const cells = try add(n, 1);
                const bytes = try multiply(cells, @sizeOf(Cell));
                if (bytes > scopes.options(vm).max_native_bytes) return error.InvalidAddress;
            }
            return;
        },
        else => {},
    }
    if (!isMemory(b)) return;
    try checkpoint(vm);
    // Image relocation tracking is not part of the task byte-result ABI. Its
    // metadata walks can exceed the native work bound. task_job discards this
    // private registry before entry; raw worker callers must do likewise.
    if (vm.addresses.count != 0) return error.InvalidExecutionToken;
    switch (b) {
        .fetch, .store, .add_store, .inc_store, .dec_store, .zero_store, .off, .on, .cfetch, .cstore, .two_fetch, .two_store, .count => {
            const write = switch (b) {
                .fetch, .cfetch, .two_fetch, .count => false,
                else => true,
            };
            const size: Cell = switch (b) {
                .cfetch, .cstore, .count => 1,
                .two_fetch, .two_store => 16,
                else => 8,
            };
            const address = try top(vm, 0);
            switch (b) {
                .add_store, .inc_store, .dec_store => try check(vm, &.{ access(address, size, false), access(address, size, true) }),
                else => try check(vm, &.{access(address, size, write)}),
            }
        },
        .array_fetch, .array_store => {
            const address = try add(try top(vm, 0), try multiply(try top(vm, 1), 8));
            try check(vm, &.{access(address, 8, b == .array_store)});
        },
        .erase, .blank_fill, .minus_trailing => try check(vm, &.{access(try top(vm, 1), positive(try top(vm, 0)), b != .minus_trailing)}),
        .fill, .scan, .skip => try check(vm, &.{access(try top(vm, 2), positive(try top(vm, 1)), b == .fill)}),
        .move, .cmove, .cmove_up => {
            const count = positive(try top(vm, 0));
            try check(vm, &.{ access(try top(vm, 2), count, false), access(try top(vm, 1), count, true) });
        },
        .compare, .search, .str_equal, .string_prefix_query => {
            const first = positive(try top(vm, 2));
            const second = positive(try top(vm, 0));
            const ranges = [_]permissions.Access{ access(try top(vm, 3), first, false), access(try top(vm, 1), second, false) };
            try check(vm, &ranges);
            // SEARCH may compare the pattern at every text position. Bound work,
            // not only the input footprint, without performing the search first.
            if (b == .search) {
                const work = try multiply(first, @max(1, second));
                try validate(vm, &ranges, std.math.cast(usize, work) orelse return error.InvalidAddress);
            }
        },
        .place, .plus_place => {
            const destination = try top(vm, 0);
            const length = std.math.clamp(try top(vm, 1), 0, 255);
            if (b == .plus_place) {
                // Do not read the counted header before validating ALL ranges.
                // Conservatively require its complete 256-byte capacity and the
                // largest possible source span, even if the string is nearly full.
                try check(vm, &.{ access(destination, 1, false), access(try top(vm, 2), length, false), access(destination, 256, true) });
            } else try check(vm, &.{ access(try top(vm, 2), length, false), access(destination, 1 + length, true) });
        },
        else => unreachable,
    }
}
pub fn after(vm: *forth.State, b: defs.Builtin) Error!void {
    if (isMemory(b) or b == .roll or b == .pick or b == .n_to_r or b == .n_r_from) try checkpoint(vm);
}
pub fn literal(vm: *forth.State, address: Cell) Error!void {
    try checkpoint(vm);
    try check(vm, &.{access(address, 1, false)});
}

/// Grants are built once from the restored, private VM. Worker code cannot
/// allocate/free heap blocks or modify headers; no shared permission registry.
pub const Grants = struct {
    regions: std.ArrayList(permissions.Region) = .empty,
    pub fn init(allocator: std.mem.Allocator, vm: *forth.State) !Grants {
        var self: Grants = .{};
        errdefer self.deinit(allocator);
        try self.regions.append(allocator, .{ .start = @intCast(forth.data_start), .length = vm.sizes.m - @as(usize, @intCast(forth.data_start)), .writable = true, .kind = .dictionary_payload });
        const heap = @import("heap_memory.zig");
        const map = @import("memory_map.zig");
        const end = vm.heapTop();
        if (end < vm.sizes.heapBase() or end > vm.sizes.heapEnd()) return error.InvalidAddress;
        var block = vm.sizes.heapBase();
        while (block < end) {
            if (end - block < map.heap_header) return error.InvalidAddress;
            const size = try heap.blockSize(vm, block);
            if (try heap.blockUsed(vm, block)) try self.regions.append(allocator, .{ .start = @intCast(block + map.heap_header), .length = @intCast(size), .writable = true, .kind = .heap_payload });
            block += map.heap_header + size;
        }
        return self;
    }
    pub fn deinit(self: *Grants, allocator: std.mem.Allocator) void {
        self.regions.deinit(allocator);
    }
    pub fn gate(self: *const Grants) permissions.MemoryGate {
        return .{ .context = self, .check = permits };
    }
    fn permits(raw: *const anyopaque, accesses: []const permissions.Access, _: usize) bool {
        const self: *const Grants = @ptrCast(@alignCast(raw));
        for (accesses) |item| {
            if (item.address < 0) return false;
            const address = std.math.cast(usize, item.address) orelse return false;
            // Grants are disjoint and sorted: dictionary first, then heap
            // payloads in block order. Never scan the whole heap per VM access.
            var low: usize = 0;
            var high = self.regions.items.len;
            while (low < high) {
                const mid = low + (high - low) / 2;
                if (self.regions.items[mid].start <= address) low = mid + 1 else high = mid;
            }
            if (low == 0 or !permissions.checkAccess(self.regions.items[low - 1 .. low], item.address, item.length, item.write, std.math.maxInt(usize))) return false;
        }
        return true;
    }
};
