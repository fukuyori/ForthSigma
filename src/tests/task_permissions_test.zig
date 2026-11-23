const std = @import("std");
const forth = @import("../forth.zig");
const permissions = @import("../core/task_permissions.zig");
const inlining = @import("../core/inline_calls.zig");
const support = @import("support.zig");
fn inspect(vm: *forth.State, name: []const u8) !void {
    _ = try permissions.inspect(std.testing.allocator, vm, vm.lookup(name).?, .{});
}
test "worker admission accepts optimized arithmetic BEGIN and recursive static calls" {
    var output = support.Output{};
    const vm = try support.createMachine(&output);
    defer support.destroyMachine(vm);
    try vm.interpretLine(": INC 1+ ; : CALC 0 BEGIN DUP 4 < WHILE INC REPEAT ; : REC DUP IF 1- RECURSE THEN ;");
    try inspect(vm, "CALC");
    try inspect(vm, "REC");
    try vm.interpretLine("CALC 3 REC");
    try support.expectStack(vm, &.{ 4, 0 });
}
test "worker admission rejects direct and indirect forbidden definitions" {
    var output = support.Output{};
    const vm = try support.createMachine(&output);
    defer support.destroyMachine(vm);
    for ([_][]const u8{ "EXECUTE", "CATCH", "THROW", "PAD", "EVALUATE", "SYSTEM", "!", "I", "J", "UNLOOP", "LEAVE", ".", "CREATE" }) |name| {
        try std.testing.expectError(if (std.mem.eql(u8, name, "!")) error.MemoryChecksRequired else error.Denied, inspect(vm, name));
    }
    try vm.interpretLine(": BAD EXECUTE ; : INDIRECT BAD ; : LOOPY 2 0 DO LOOP ;");
    try std.testing.expectError(error.Denied, inspect(vm, "INDIRECT"));
    try std.testing.expectError(error.Denied, inspect(vm, "LOOPY"));
}
test "worker admission decodes actual Op dispatch and inline bodies" {
    var output = support.Output{};
    const vm = try support.createMachine(&output);
    defer support.destroyMachine(vm);
    try vm.interpretLine(": ENTRY 1 ; : OTHER 2 ;");
    const id = vm.lookup("ENTRY").?;
    const pc = vm.words[id].code_start;
    const plus = vm.lookup("+").?;
    const execute = vm.lookup("EXECUTE").?;
    vm.code[pc] = .{ .kind = .call_builtin, .value = execute };
    try std.testing.expectError(error.Denied, inspect(vm, "ENTRY"));
    const original_plus = vm.words[plus];
    defer vm.words[plus] = original_plus;
    vm.words[plus].kind = .constant;
    vm.code[pc] = .{ .kind = .call_builtin, .value = plus };
    try inspect(vm, "ENTRY"); // VM uses builtin even if kind is not builtin.
    try vm.push(20);
    try vm.push(22);
    try vm.executeWord(id);
    try support.expectStack(vm, &.{42});
    vm.words[plus].builtin = .execute;
    try std.testing.expectError(error.Denied, inspect(vm, "ENTRY"));
    vm.code[pc] = .{ .kind = .call_colon, .value = plus };
    try std.testing.expectError(error.InvalidCode, inspect(vm, "ENTRY"));
    vm.code[pc] = .{ .kind = .call_builtin, .value = id };
    try std.testing.expectError(error.InvalidCode, inspect(vm, "ENTRY"));
    vm.code[pc] = .{ .kind = .call_colon, .value = inlining.operand(id, 2, 1) };
    vm.code[pc + 1] = .{ .kind = .execute };
    try std.testing.expectError(error.Denied, inspect(vm, "ENTRY"));
    vm.code[pc + 1] = .{ .kind = .add };
    try inspect(vm, "ENTRY");
    const other = vm.lookup("OTHER").?;
    vm.words[id].kind = .synonym;
    vm.words[id].value = other;
    vm.words[other].kind = .synonym;
    vm.words[other].value = id;
    try std.testing.expectError(error.SynonymCycle, inspect(vm, "ENTRY"));
    vm.words[id].has_does = true;
    try std.testing.expectError(error.Denied, inspect(vm, "ENTRY"));
}
test "worker memory contract requires grants bounds write permission and native budget" {
    const grants = [_]permissions.Region{.{ .start = 100, .length = 10, .writable = false, .kind = .input }};
    try std.testing.expect(permissions.checkAccess(&grants, 100, 10, false, 10));
    try std.testing.expect(!permissions.checkAccess(&grants, 100, 10, true, 10));
    try std.testing.expect(!permissions.checkAccess(&grants, 99, 1, false, 10));
    try std.testing.expect(!permissions.checkAccess(&grants, 109, 2, false, 10));
    try std.testing.expect(!permissions.checkAccess(&grants, 100, -1, false, 10));
    try std.testing.expect(!permissions.checkAccess(&grants, 100, 10, false, 9));
    var output = support.Output{};
    const vm = try support.createMachine(&output);
    defer support.destroyMachine(vm);
    const gate = permissions.MemoryGate{ .context = &grants, .check = denyMemory };
    const result = try permissions.inspect(std.testing.allocator, vm, vm.lookup("@").?, .{ .memory_gate = &gate, .max_native_bytes = 123 });
    try std.testing.expectEqual(&gate, result.memory_gate.?);
    try std.testing.expect(!gate.permits(&.{}, 0, 123));
    try std.testing.expectEqual(@as(usize, 123), result.max_native_bytes);
}

test "protected worker regions cannot be granted even for reading" {
    for ([_]permissions.RegionKind{ .system, .block_buffer, .heap_header, .local_frame }) |kind| {
        const grants = [_]permissions.Region{.{ .start = 100, .length = 10, .writable = true, .kind = kind }};
        try std.testing.expect(!permissions.checkAccess(&grants, 100, 1, false, 10));
        try std.testing.expect(!permissions.checkAccess(&grants, 100, 1, true, 10));
    }
}

test "worker denies every non-admitted control operation in copied code" {
    const defs = @import("../core/defs.zig");
    var output = support.Output{};
    const vm = try support.createMachine(&output);
    defer support.destroyMachine(vm);
    try vm.interpretLine(": ENTRY 1 ;");
    const id = vm.lookup("ENTRY").?;
    const pc = vm.words[id].code_start;
    for ([_]defs.OpKind{
        .execute,                        .local_execute, .does,                 .abort_string,   .print_string,         .compile_call,
        .do_loop,                        .q_do_loop,     .loop,                 .plus_loop,      .leave,                .index,
        .index_2,                        .positive_do,   .unsigned_positive_do, .negative_do,    .unsigned_negative_do, .inclusive_negative_do,
        .unsigned_inclusive_negative_do, .for_loop,      .memory_up_do,         .memory_down_do, .negative_loop,        .next_loop,
        .local_frame,                    .local_store,   .local_fetch,          .local_address,  .store_value,          .add_value,
    }) |kind| {
        vm.code[pc] = .{ .kind = kind };
        try std.testing.expectError(error.Denied, inspect(vm, "ENTRY"));
    }
    for ([_]defs.WordKind{ .forward, .deferred, .marker, .vocabulary, .exception_entry }) |kind| {
        vm.words[id].kind = kind;
        try std.testing.expectError(error.Denied, inspect(vm, "ENTRY"));
    }
}

test "worker builtin forms cannot hide forbidden implementations" {
    const defs = @import("../core/defs.zig");
    var output = support.Output{};
    const vm = try support.createMachine(&output);
    defer support.destroyMachine(vm);
    try vm.interpretLine(": ENTRY 1 ; : SAFE 2 ;");
    const entry = vm.lookup("ENTRY").?;
    const pc = vm.words[entry].code_start;
    vm.code[pc] = .{ .kind = .builtin, .value = @backingInt(defs.Builtin.execute) };
    try std.testing.expectError(error.Denied, inspect(vm, "ENTRY"));
    vm.code[pc] = .{ .kind = .call, .value = vm.lookup("EXECUTE").? };
    try std.testing.expectError(error.Denied, inspect(vm, "ENTRY"));
    vm.code[pc] = .{ .kind = .branch, .value = @as(forth.Cell, pc) - 1 };
    try std.testing.expectError(error.InvalidCode, inspect(vm, "ENTRY"));
    const safe = vm.lookup("SAFE").?;
    vm.words[entry].kind = .synonym;
    vm.words[entry].value = safe;
    try inspect(vm, "ENTRY");
}

fn denyMemory(_: *const anyopaque, _: []const permissions.Access, _: usize) bool {
    return false;
}

test "worker rejects protected overlaps before accepting payload grants" {
    for ([_]permissions.RegionKind{ .system, .block_buffer, .heap_header, .local_frame }) |kind| {
        for ([_]bool{ false, true }) |reverse| {
            var grants = [_]permissions.Region{
                .{ .start = 90, .length = 40, .writable = true, .kind = .heap_payload },
                .{ .start = 100, .length = 10, .writable = true, .kind = kind },
            };
            if (reverse) std.mem.swap(permissions.Region, &grants[0], &grants[1]);
            for ([_]bool{ false, true }) |write| {
                for ([_][2]forth.Cell{ .{ 99, 2 }, .{ 100, 1 }, .{ 109, 2 }, .{ 90, 30 } }) |range| {
                    try std.testing.expect(!permissions.checkAccess(&grants, range[0], range[1], write, 40));
                }
                try std.testing.expect(permissions.checkAccess(&grants, 90, 10, write, 40));
                try std.testing.expect(permissions.checkAccess(&grants, 110, 10, write, 40));
            }
        }
    }
}

test "worker admission rejects dirty state and counted settings individually" {
    var output = support.Output{};
    const vm = try support.createMachine(&output);
    defer support.destroyMachine(vm);
    inline for (.{ "halted", "compiling", "defining" }) |field| {
        @field(vm, field) = true;
        try std.testing.expectError(error.DirtyVm, inspect(vm, "+"));
        @field(vm, field) = false;
    }
    inline for (.{ "return_depth", "loop_depth", "catch_depth", "frame_depth", "call_depth", "control_depth", "interpret_loop_depth", "quote_depth" }) |field| {
        @field(vm, field) = 1;
        try std.testing.expectError(error.DirtyVm, inspect(vm, "+"));
        @field(vm, field) = 0;
    }
    vm.output_error = -1;
    try std.testing.expectError(error.DirtyVm, inspect(vm, "+"));
    vm.output_error = null;
    inline for (.{ "tracing", "keep_counting", "in_counted" }) |field| {
        @field(vm, field) = true;
        try std.testing.expectError(error.CountedMode, inspect(vm, "+"));
        @field(vm, field) = false;
    }
    inline for (.{ "step_limit", "cell_watch_count" }) |field| {
        @field(vm, field) = 1;
        try std.testing.expectError(error.CountedMode, inspect(vm, "+"));
        @field(vm, field) = 0;
    }
    inline for (.{ .armed, .on }) |mode| {
        vm.stepper = mode;
        try std.testing.expectError(error.CountedMode, inspect(vm, "+"));
    }
    vm.stepper = .off;
    var profile: forth.Profile = undefined;
    vm.profile = &profile;
    try std.testing.expectError(error.CountedMode, inspect(vm, "+"));
    vm.profile = null;
    if (comptime @import("../core/defs.zig").debug_enabled) {
        vm.execution.depth = 1;
        try std.testing.expectError(error.CountedMode, inspect(vm, "+"));
        vm.execution.depth = 0;
    }
    try inspect(vm, "+");
}

test "worker admission covers word kinds strings malformed guards and builtin escapes" {
    const defs = @import("../core/defs.zig");
    var output = support.Output{};
    const vm = try support.createMachine(&output);
    defer support.destroyMachine(vm);
    try vm.interpretLine(": ENTRY 1 ; : TARGET 2 ; : MAKER CREATE DOES> 1 ; MAKER CHILD");
    const entry = vm.lookup("ENTRY").?;
    const target = vm.lookup("TARGET").?;
    const child = vm.lookup("CHILD").?;
    const pc = vm.words[entry].code_start;
    const end = vm.words[entry].code_end;
    const saved = vm.words[target];
    for ([_]defs.WordKind{ .value, .fvalue, .two_constant, .field, .constant, .variable }) |kind| {
        vm.words[target].kind = kind;
        vm.code[pc] = .{ .kind = .call, .value = target };
        switch (kind) {
            .field, .constant, .variable => try inspect(vm, "ENTRY"),
            else => try std.testing.expectError(error.Denied, inspect(vm, "ENTRY")),
        }
    }
    vm.words[target] = saved;
    try std.testing.expect(vm.words[child].has_does);
    vm.code[pc] = .{ .kind = .call, .value = child };
    try std.testing.expectError(error.Denied, inspect(vm, "ENTRY"));
    for ([_]defs.OpKind{ .string_literal, .counted_string }) |kind| {
        vm.code[pc] = .{ .kind = kind, .value = 0 };
        vm.memory[0] = 0;
        try std.testing.expectError(error.MemoryChecksRequired, inspect(vm, "ENTRY"));
    }
    for ([_]defs.OpKind{ .branch, .branch_zero }) |kind| {
        vm.code[pc] = .{ .kind = kind, .value = @as(forth.Cell, end) + 1 };
        try std.testing.expectError(error.InvalidCode, inspect(vm, "ENTRY"));
    }
    vm.code[pc] = .{ .kind = .execution_token, .value = vm.word_count };
    try std.testing.expectError(error.InvalidCode, inspect(vm, "ENTRY"));
    for ([_]struct { id: u16, span: u16, depth: u16, does: bool, expected: permissions.Error }{
        .{ .id = vm.lookup("+").?, .span = 1, .depth = 1, .does = false, .expected = error.InvalidCode },
        .{ .id = target, .span = 1, .depth = 1, .does = true, .expected = error.Denied },
        .{ .id = target, .span = end - pc + 1, .depth = 1, .does = false, .expected = error.InvalidCode },
        .{ .id = target, .span = 1, .depth = 0, .does = false, .expected = error.InvalidCode },
    }) |case| {
        vm.words[target].has_does = case.does;
        vm.code[pc] = .{ .kind = .call_colon, .value = inlining.operand(case.id, case.span, case.depth) };
        try std.testing.expectError(case.expected, inspect(vm, "ENTRY"));
    }
    vm.words[target] = saved;
    for ([_]defs.Builtin{ .fast_throw, .assert_paren, .assert_run, .assert_close, .assert_level, .assert_zero, .assert_one, .assert_two, .assert_three, .abort }) |builtin| {
        vm.words[target].kind = .builtin;
        vm.words[target].builtin = builtin;
        vm.code[pc] = .{ .kind = .call, .value = target };
        try std.testing.expectError(error.Denied, inspect(vm, "ENTRY"));
        vm.code[pc] = .{ .kind = .builtin, .value = @backingInt(builtin) };
        try std.testing.expectError(error.Denied, inspect(vm, "ENTRY"));
    }
    vm.code[pc] = .{ .kind = .abort_string, .value = 0 };
    try std.testing.expectError(error.Denied, inspect(vm, "ENTRY"));
}

test "worker admission checks compiled string and abort quote bodies" {
    var output = support.Output{};
    const vm = try support.createMachine(&output);
    defer support.destroyMachine(vm);
    for ([_]struct { source: []const u8, expected: permissions.Error }{
        .{ .source = ": CASE S\" text\" ;", .expected = error.MemoryChecksRequired },
        .{ .source = ": CASE C\" text\" ;", .expected = error.MemoryChecksRequired },
        .{ .source = ": CASE ABORT\" text\" ;", .expected = error.Denied },
    }) |case| {
        try vm.interpretLine(case.source);
        try std.testing.expectError(case.expected, inspect(vm, "CASE"));
    }
}

fn allowMemory(context: *const anyopaque, accesses: []const permissions.Access, native_bytes: usize) bool {
    const expected: *const usize = @ptrCast(@alignCast(context));
    return accesses.len == 2 and accesses[0].address == 100 and
        accesses[1].write and native_bytes == expected.*;
}

test "worker gate invokes supplied checker and enforces total native budget" {
    const work: usize = 20;
    const gate = permissions.MemoryGate{ .context = &work, .check = allowMemory };
    const accesses = [_]permissions.Access{
        .{ .address = 100, .length = 10, .write = false },
        .{ .address = 200, .length = 10, .write = true },
    };
    try std.testing.expect(gate.permits(&accesses, 20, 20));
    try std.testing.expect(!gate.permits(&accesses, 20, 19));
    try std.testing.expect(!gate.permits(accesses[0..1], 20, 20));
}
