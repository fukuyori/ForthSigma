//! Fresh worker Storage only. Ordinary Storage.allocate is unchanged.
const std = @import("std");
const forth = @import("../forth.zig");
const setup = @import("task_setup.zig");
pub fn allocate(allocator: std.mem.Allocator, already_zero: bool, sizes: forth.Sizes, control: ?setup.Control, retired_storage: ?*?forth.Storage) !forth.Storage {
    var storage: forth.Storage = undefined;
    storage.sizes = sizes;
    const fields = .{ "memory", "data_stack", "return_stack", "float_stack", "loop_stack", "frames", "catches" };
    inline for (fields) |field| @field(storage, field) = &.{};
    errdefer {
        if (retired_storage) |retired| retired.* = storage else storage.free(allocator);
    }
    inline for (fields, 0..) |field, index| {
        const T = @typeInfo(@TypeOf(@field(storage, field))).pointer.child;
        const count = switch (index) {
            0 => sizes.memorySize(),
            1 => sizes.data_stack,
            3 => sizes.float_stack,
            else => sizes.return_stack,
        };
        @field(storage, field) = try allocateArray(T, allocator, count, control, .allocation_chunk);
        if (control) |c| try c.check(switch (index) {
            0 => .memory_allocated,
            1 => .data_allocated,
            2 => .return_allocated,
            3 => .float_allocated,
            4 => .loops_allocated,
            5 => .frames_allocated,
            6 => .catches_allocated,
            else => unreachable,
        });
    }
    // Allocator.alloc poisons undefined memory in safety builds. Retain the
    // explicit zeroing there even for an OS-zeroed backing allocator.
    if (!already_zero or std.debug.runtime_safety) {
        inline for (.{ "memory", "data_stack", "return_stack", "float_stack" }) |field| {
            const bytes = std.mem.sliceAsBytes(@field(storage, field));
            var offset: usize = 0;
            while (offset < bytes.len) {
                const end = @min(bytes.len, offset + 64 * 1024);
                @memset(bytes[offset..end], 0);
                offset = end;
                if (control) |c| try c.check(.zero_chunk);
            }
        }
    }
    if (control) |c| try c.check(.storage_zeroed);
    return storage;
}

// Bypass Allocator.alloc's single, uninterruptible safety poison. Preserve the
// same undefined representation, but check between bounded writes. Ownership is
// established here before the first checkpoint, including fault-injection paths.
pub const chunk_bytes = 1024 * 1024;
pub fn allocateArray(comptime T: type, allocator: std.mem.Allocator, count: usize, control: ?setup.Control, stage: setup.Stage) ![]T {
    const len = std.math.mul(usize, @sizeOf(T), count) catch return error.OutOfMemory;
    if (len == 0) return allocator.alloc(T, count);
    const raw = allocator.rawAlloc(len, .of(T), @returnAddress()) orelse return error.OutOfMemory;
    const values = @as([*]T, @ptrCast(@alignCast(raw)))[0..count];
    errdefer allocator.free(values);
    if (stage == .state_chunk) if (control) |c| try c.check(.state_reserved);
    if (std.debug.runtime_safety) {
        var offset: usize = 0;
        while (offset < len) {
            const end = @min(len, offset + chunk_bytes);
            @memset(raw[offset..end], undefined);
            offset = end;
            if (control) |c| try c.check(stage);
        }
    }
    return values;
}
