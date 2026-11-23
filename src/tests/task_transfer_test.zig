const std = @import("std");
const forth = @import("../forth.zig");
const map = @import("../core/memory_map.zig");
const transfer = @import("../core/task_transfer.zig");
const testing = std.testing;
const limits: transfer.Limits = .{ .input = 4, .result = 4 };

fn discard(_: ?*anyopaque, _: []const u8) void {}

fn fresh() !*forth.State {
    const vm = try testing.allocator.create(forth.State);
    errdefer testing.allocator.destroy(vm);
    vm.init(.{ .context = null, .write_fn = discard }, try forth.Storage.allocate(testing.allocator, false, .small));
    return vm;
}

fn destroy(vm: *forth.State) void {
    vm.storage().free(testing.allocator);
    testing.allocator.destroy(vm);
}

fn result(vm: *forth.State, address: forth.Cell, length: forth.Cell) void {
    vm.data_depth = 2;
    vm.data_stack[0] = address;
    vm.data_stack[1] = length;
}

test "task transfer executes byte ABI and owns input and result independently" {
    const vm = try fresh();
    var alive = true;
    defer if (alive) destroy(vm);
    try vm.interpretLine(": ENTRY OVER 90 SWAP C! ;");
    var input = [_]u8{ 'a', 'b', 'c', 'd' };
    const here = vm.data_here;
    try transfer.prepareInput(vm, &input, limits);
    try testing.expectEqual(std.mem.alignForward(forth.Cell, here, 8) + 8, vm.data_here);
    input[1] = 'x';
    try vm.executeWord(vm.lookup("ENTRY").?);
    const owned = try transfer.copyResult(vm, testing.allocator, limits);
    defer testing.allocator.free(owned);
    try testing.expectEqualStrings("Zbcd", owned);
    try testing.expectEqualStrings("axcd", &input);
    destroy(vm);
    alive = false;
    try testing.expectEqualStrings("Zbcd", owned);
}

test "task transfer zero length including exact data limit" {
    const vm = try fresh();
    defer destroy(vm);
    vm.data_here = vm.sizes.dataLimit();
    try transfer.prepareInput(vm, "", .{ .input = 0, .result = 0 });
    try testing.expectEqual(vm.sizes.dataLimit(), vm.data_stack[0]);
    const owned = try transfer.copyResult(vm, testing.allocator, .{ .input = 0, .result = 0 });
    defer testing.allocator.free(owned);
    try testing.expectEqual(@as(usize, 0), owned.len);
}

test "task transfer input failures do not mutate caller bytes HERE stacks or destination" {
    const vm = try fresh();
    defer destroy(vm);
    const here = vm.data_here;
    const start: usize = @intCast(here);
    vm.memory[start] = 77;
    vm.data_stack[0] = 123;
    var input = [_]u8{ 1, 2, 3, 4, 5 };
    try testing.expectError(error.InputTooLarge, transfer.prepareInput(vm, &input, limits));
    try testing.expectEqualSlices(u8, &.{ 1, 2, 3, 4, 5 }, &input);
    try testing.expectEqual(here, vm.data_here);
    try testing.expectEqual(@as(usize, 0), vm.data_depth);
    try testing.expectEqual(@as(forth.Cell, 123), vm.data_stack[0]);
    try testing.expectEqual(@as(u8, 77), vm.memory[start]);
    vm.data_here = vm.sizes.dataLimit() - 1;
    try testing.expectError(error.InputSpaceExhausted, transfer.prepareInput(vm, "ab", limits));
    try testing.expectEqual(vm.sizes.dataLimit() - 1, vm.data_here);
    const stack = vm.data_stack;
    vm.data_stack = stack[0..1];
    defer vm.data_stack = stack;
    try testing.expectError(error.InputStackTooSmall, transfer.prepareInput(vm, "", limits));
    vm.data_stack = stack;
    vm.data_here = vm.sizes.dataLimit() - 8;
    try transfer.prepareInput(vm, "a", limits);
    try testing.expectEqual(vm.sizes.dataLimit(), vm.data_here);
}

test "task transfer distinguishes result ABI diagnostics without consuming stacks" {
    const vm = try fresh();
    defer destroy(vm);
    for ([_]usize{ 0, 1, 3 }) |depth| {
        vm.data_depth = depth;
        try testing.expectError(error.ResultStackDepth, transfer.resultBytes(vm, limits));
        try testing.expectEqual(depth, vm.data_depth);
    }
    result(vm, forth.data_start, 0);
    vm.float_depth = 1;
    try testing.expectError(error.ResultFloatStackNotEmpty, transfer.resultBytes(vm, limits));
    vm.float_depth = 0;
    result(vm, forth.data_start, -1);
    try testing.expectError(error.NegativeResultLength, transfer.resultBytes(vm, limits));
    result(vm, std.math.maxInt(forth.Cell), 1);
    try testing.expectError(error.ResultAddressOverflow, transfer.resultBytes(vm, limits));
    result(vm, forth.data_start, 5);
    try testing.expectError(error.ResultTooLarge, transfer.resultBytes(vm, limits));
    try testing.expectEqual(@as(usize, 2), vm.data_depth);
    try testing.expectEqual(@as(forth.Cell, 5), vm.data_stack[1]);
}

test "task transfer rejects forbidden regions even for empty ranges and crossing data end" {
    const vm = try fresh();
    defer destroy(vm);
    for ([_]forth.Cell{ -1, 0, map.pad_address, map.input_area_base, map.block_buffer_base, map.block_source_base, forth.data_start - 1, vm.sizes.heapBase() + 1, vm.sizes.localsBase() }) |address| {
        for ([_]forth.Cell{ 0, 1 }) |length| {
            result(vm, address, length);
            try testing.expectError(error.ResultOutsideDataSpace, transfer.resultBytes(vm, limits));
        }
    }
    result(vm, vm.sizes.dataLimit(), 1);
    try testing.expectError(error.ResultOutsideDataSpace, transfer.resultBytes(vm, limits));
    result(vm, vm.sizes.dataLimit() - 1, 2);
    try testing.expectError(error.ResultOutsideDataSpace, transfer.resultBytes(vm, limits));
    result(vm, vm.sizes.dataLimit() - 4, 4);
    try testing.expectEqual(@as(usize, 4), (try transfer.resultBytes(vm, limits)).len);
}

test "task transfer checks every active preflight category before installing input" {
    const vm = try fresh();
    defer destroy(vm);
    try transfer.checkFresh(vm);
    inline for (.{ "loop_depth", "catch_depth", "frame_depth", "call_depth", "control_depth", "quote_depth", "interpret_loop_depth", "include_depth", "block_depth", "hold_depth", "local_count", "locals_frame_size", "assert_depth", "backtrace_suppression" }) |field| {
        @field(vm, field) = 1;
        try testing.expectError(error.ActiveVm, transfer.prepareInput(vm, "", limits));
        @field(vm, field) = 0;
    }
    inline for (.{ "defining", "postponing", "quote_closing", "noname_next" }) |field| {
        @field(vm, field) = true;
        try testing.expectError(error.ActiveVm, transfer.checkFresh(vm));
        @field(vm, field) = false;
    }
    vm.locals_top -= 1;
    try testing.expectError(error.ActiveVm, transfer.checkFresh(vm));
    vm.locals_top = vm.sizes.localsBase();
    vm.source_line = "borrowed";
    try testing.expectError(error.ActiveVm, transfer.checkFresh(vm));
    vm.source_line = "";
    vm.block_storage.buffers[0].modified = true;
    try testing.expectError(error.ActiveVm, transfer.checkFresh(vm));
    vm.block_storage = .{};
    vm.compiling = true;
    try testing.expectError(error.ActiveVm, transfer.checkFresh(vm));
    vm.compiling = false;
    vm.halted = true;
    try testing.expectError(error.HaltedVm, transfer.prepareInput(vm, "", limits));
    vm.halted = false;
    inline for (.{ "data_depth", "return_depth", "float_depth" }) |field| {
        @field(vm, field) = 1;
        try testing.expectError(error.NonEmptyStacks, transfer.checkFresh(vm));
        @field(vm, field) = 0;
    }
    inline for (.{ "capture_target", "output_file", "input_file", "output_error" }) |field| {
        @field(vm, field) = 0;
        try testing.expectError(error.CapturingVm, transfer.checkFresh(vm));
        @field(vm, field) = null;
    }
    var sink: @import("../core/macro_substitute.zig").Captured = .{};
    vm.capture_sink = &sink;
    try testing.expectError(error.CapturingVm, transfer.checkFresh(vm));
    vm.capture_sink = null;
    vm.report_capturing = true;
    try testing.expectError(error.CapturingVm, transfer.checkFresh(vm));
    vm.report_capturing = false;
    inline for (.{ "in_counted", "keep_counting", "tracing", "line_trace" }) |field| {
        @field(vm, field) = true;
        try testing.expectError(error.CountedVm, transfer.checkFresh(vm));
        @field(vm, field) = false;
    }
    vm.step_limit = 1;
    try testing.expectError(error.CountedVm, transfer.checkFresh(vm));
    vm.step_limit = 0;
    vm.stepper = .armed;
    try testing.expectError(error.CountedVm, transfer.checkFresh(vm));
    vm.stepper = .off;
    var profile: forth.Profile = undefined;
    vm.profile = &profile;
    try testing.expectError(error.CountedVm, transfer.checkFresh(vm));
    vm.profile = null;
    if (comptime @import("../core/defs.zig").debug_enabled) {
        vm.execution.depth = 1;
        try testing.expectError(error.CountedVm, transfer.checkFresh(vm));
        vm.execution.depth = 0;
    }
    vm.data_here = forth.data_start - 1;
    try testing.expectError(error.InvalidDataSpace, transfer.checkFresh(vm));
    vm.data_here = vm.sizes.dataLimit() + 1;
    try testing.expectError(error.InvalidDataSpace, transfer.checkFresh(vm));
    vm.data_here = forth.data_start;
    const memory = vm.memory;
    vm.memory = memory[0 .. vm.sizes.m - 1];
    defer vm.memory = memory;
    try testing.expectError(error.InvalidDataSpace, transfer.checkFresh(vm));
    result(vm, forth.data_start, 0);
    try testing.expectError(error.ResultOutsideDataSpace, transfer.resultBytes(vm, limits));
    vm.data_depth = 0;
    vm.memory = memory;
    try transfer.checkFresh(vm);
}

test "task transfer input and result limits are independent and static data is copied" {
    const vm = try fresh();
    defer destroy(vm);
    const separate: transfer.Limits = .{ .input = 0, .result = 4 };
    try transfer.prepareInput(vm, "", separate);
    const start: usize = @intCast(forth.data_start);
    @memcpy(vm.memory[start..][0..4], "data");
    result(vm, forth.data_start, 4);
    const owned = try transfer.copyResult(vm, testing.allocator, separate);
    defer testing.allocator.free(owned);
    vm.memory[start] = 'X';
    try testing.expectEqualStrings("data", owned);
    try testing.expectError(error.ResultTooLarge, transfer.resultBytes(vm, .{ .input = 4, .result = 0 }));
}

test "task transfer result allocation failure preserves VM for retry" {
    const vm = try fresh();
    defer destroy(vm);
    try transfer.prepareInput(vm, "abcd", limits);
    var failing = std.testing.FailingAllocator.init(testing.allocator, .{ .fail_index = 0 });
    try testing.expectError(error.OutOfMemory, transfer.copyResult(vm, failing.allocator(), limits));
    try testing.expectEqual(@as(usize, 2), vm.data_depth);
    const owned = try transfer.copyResult(vm, testing.allocator, limits);
    defer testing.allocator.free(owned);
    try testing.expectEqualStrings("abcd", owned);
}

test "task transfer enforces product ceilings and stopped result state" {
    const vm = try fresh();
    defer destroy(vm);
    try (transfer.Limits{}).validate();
    try testing.expectError(error.InvalidLimits, transfer.prepareInput(vm, "", .{ .input = transfer.default_input_limit + 1 }));
    result(vm, forth.data_start, 0);
    try testing.expectError(error.InvalidLimits, transfer.resultBytes(vm, .{ .result = transfer.default_result_limit + 1 }));
    inline for (.{ "return_depth", "loop_depth", "local_count" }) |field| {
        @field(vm, field) = 1;
        try testing.expectError(error.ResultVmNotStopped, transfer.resultBytes(vm, limits));
        @field(vm, field) = 0;
    }
    inline for (.{ "compiling", "halted" }) |field| {
        @field(vm, field) = true;
        try testing.expectError(error.ResultVmNotStopped, transfer.resultBytes(vm, limits));
        @field(vm, field) = false;
    }
}

test "task transfer aligns odd HERE and input and invalidates overwritten address records" {
    const vm = try fresh();
    defer destroy(vm);
    const base = vm.data_here;
    vm.data_here += 1;
    vm.addresses.records[0] = .{ .kind = .memory, .slot = base + 8, .value = base, .target = .data };
    vm.addresses.count = 1;
    try transfer.prepareInput(vm, "abc", limits);
    try testing.expectEqual(base + 8, vm.data_stack[0]);
    try testing.expectEqual(base + 16, vm.data_here);
    try testing.expectEqualStrings("abc", try transfer.resultBytes(vm, limits));
    try testing.expectEqual(@as(usize, 0), vm.addresses.count);
}

test "task transfer checks borrowed and diagnostic preflight fields" {
    const vm = try fresh();
    defer destroy(vm);
    inline for (.{ "wrap_guard", "abort_message", "sh_get_result" }) |field| {
        const T = @TypeOf(@field(vm, field).?);
        var value: T = undefined;
        if (comptime @typeInfo(T) == .pointer) {
            value = @ptrFromInt(@alignOf(@typeInfo(T).pointer.child));
        } else {
            value = std.mem.zeroes(T);
        }
        @field(vm, field) = value;
        try testing.expectError(error.ActiveVm, transfer.checkFresh(vm));
        @field(vm, field) = null;
    }
    vm.lint = @ptrFromInt(@alignOf(forth.Lint));
    try testing.expectError(error.CountedVm, transfer.checkFresh(vm));
    vm.lint = null;
    inline for (.{ "cell_watch_count", "watched_count" }) |field| {
        @field(vm, field) = 1;
        try testing.expectError(error.CountedVm, transfer.checkFresh(vm));
        @field(vm, field) = 0;
    }
    vm.pending = .colon_name;
    try testing.expectError(error.ActiveVm, transfer.checkFresh(vm));
    vm.pending = .none;
    inline for (.{ .evaluate, .file, .block }) |kind| {
        vm.source_kind = kind;
        try testing.expectError(error.ActiveVm, transfer.checkFresh(vm));
    }
    vm.source_kind = .terminal;
    try transfer.checkFresh(vm);
}
