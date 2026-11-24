const std = @import("std");
const support = @import("support.zig");
const forth = @import("../forth.zig");
const memory = @import("../core/task_memory.zig");
const permissions = @import("../core/task_permissions.zig");
const base = @import("../core/runtime_base.zig");
const scopes = @import("../core/task_context.zig");
const snapshot = @import("../core/task_snapshot.zig");
const job = @import("../core/task_job.zig");
const a = std.testing.allocator;

test "1373 job reads input writes result and isolates dictionary writes between jobs" {
    var output = support.Output{};
    const vm = try support.createMachine(&output);
    defer support.destroyMachine(vm);
    try vm.interpretLine("VARIABLE V : JOB V @ IF 0 0 / THEN 1 V ! 2DUP 65 FILL ;");
    try @import("../core/address_registry.zig").registerMemory(vm, vm.words[vm.lookup("V").?].value);
    var manager = snapshot.Manager{};
    const version = try manager.capture(a, vm);
    defer version.release();
    var token: base.Cancellation = .{};
    for (0..3) |_| {
        var admission = try version.admit(vm);
        const bytes = try job.run(a, &admission, "JOB", "abc", &token, .{});
        defer a.free(bytes);
        try std.testing.expectEqualStrings("AAA", bytes);
    }
    try std.testing.expectEqual(@as(forth.Cell, 0), try vm.readCell(vm.words[vm.lookup("V").?].value));
    // Read the input and return a subrange, rather than merely returning its ABI.
    try vm.interpretLine(": READ DUP IF OVER C@ 97 <> IF 0 0 / THEN THEN 1 /STRING ;");
    const next = try manager.capture(a, vm);
    defer next.release();
    var admission = try next.admit(vm);
    const bytes = try job.run(a, &admission, "READ", "abc", &token, .{});
    defer a.free(bytes);
    try std.testing.expectEqualStrings("bc", bytes);
}

test "1373 every admitted memory builtin preflights before operand mutation" {
    var output = support.Output{};
    const vm = try support.createMachine(&output);
    defer support.destroyMachine(vm);
    var grants = try memory.Grants.init(a, vm);
    defer grants.deinit(a);
    const gate = grants.gate();
    var token: base.Cancellation = .{};
    const defs = @import("../core/defs.zig");
    @setEvalBranchQuota(20000);
    inline for (@typeInfo(defs.Builtin).@"enum".field_names) |name| {
        const builtin = @field(defs.Builtin, name);
        if (comptime permissions.policy(builtin) == .memory) {
            vm.data_depth = 0;
            // Every operand is an address or length of 1, which touches system
            // storage for each memory operation, including array and string paths.
            for (0..4) |_| try vm.push(1);
            try std.testing.expectError(error.InvalidAddress, vm.runAsWorkerWithMemory(@intCast(vm.builtinWord(builtin)), &token, .{ .memory_gate = &gate }));
            try support.expectStack(vm, &.{ 1, 1, 1, 1 });
        }
    }
}

test "1373 worker memory rejects protected regions overflow and native budget before effects" {
    var output = support.Output{};
    const vm = try support.createMachine(&output);
    defer support.destroyMachine(vm);
    try vm.interpretLine(": JOB ! ; : COPY MOVE ; : INDEX A@ ; : TEXT S\" abc\" ;");
    var grants = try memory.Grants.init(a, vm);
    defer grants.deinit(a);
    const gate = grants.gate();
    var token: base.Cancellation = .{};
    const map = @import("../core/memory_map.zig");
    const addresses = [_]forth.Cell{ 0, map.input_area_end, vm.sizes.heapBase(), vm.sizes.localsBase(), std.math.maxInt(forth.Cell), -1, vm.sizes.dataLimit() - 4 };
    for (addresses) |address| {
        vm.data_depth = 0;
        try vm.push(99);
        try vm.push(address);
        try std.testing.expectError(error.InvalidAddress, vm.runAsWorkerWithMemory(vm.lookup("JOB").?, &token, .{ .memory_gate = &gate }));
        try support.expectStack(vm, &.{ 99, address });
    }
    vm.data_depth = 0;
    try vm.push(std.math.maxInt(forth.Cell));
    try vm.push(forth.data_start);
    try std.testing.expectError(error.InvalidAddress, vm.runAsWorkerWithMemory(vm.lookup("INDEX").?, &token, .{ .memory_gate = &gate }));
    // Destination is valid, source is protected: destination must stay untouched.
    vm.data_depth = 0;
    const dest = forth.data_start;
    vm.memory[@intCast(dest)] = 77;
    try vm.push(0);
    try vm.push(dest);
    try vm.push(1);
    try std.testing.expectError(error.InvalidAddress, vm.runAsWorkerWithMemory(vm.lookup("COPY").?, &token, .{ .memory_gate = &gate }));
    try std.testing.expectEqual(@as(u8, 77), vm.memory[@intCast(dest)]);
    vm.data_depth = 0;
    try vm.push(dest);
    try vm.push(dest + 16);
    try vm.push(4);
    try std.testing.expectError(error.InvalidAddress, vm.runAsWorkerWithMemory(vm.lookup("COPY").?, &token, .{ .memory_gate = &gate, .max_native_bytes = 7 }));
    try vm.runAsWorkerWithMemory(vm.lookup("COPY").?, &token, .{ .memory_gate = &gate, .max_native_bytes = 8 });
    try support.expectStack(vm, &.{});
    // Compiled S" reads its length byte through the gate; absent gate denies it.
    try std.testing.expectError(error.InvalidAddress, vm.runAsWorker(vm.lookup("TEXT").?, &token));
}

test "1373 actual heap payload grant excludes its header free blocks and locals" {
    var output = support.Output{};
    const vm = try support.createMachine(&output);
    defer support.destroyMachine(vm);
    const payload = (try vm.heapAllocate(32)).?;
    var grants = try memory.Grants.init(a, vm);
    defer grants.deinit(a);
    const gate = grants.gate();
    try std.testing.expect(gate.permits(&.{.{ .address = payload, .length = 32, .write = true }}, 32, 64));
    for ([_]forth.Cell{ payload - 1, payload + 32, vm.sizes.localsBase() }) |address| {
        try std.testing.expect(!gate.permits(&.{.{ .address = address, .length = 1, .write = false }}, 1, 64));
    }
}

test "1373 native cancellation checks immediately before and after bounded memory work" {
    var output = support.Output{};
    const vm = try support.createMachine(&output);
    defer support.destroyMachine(vm);
    const Probe = struct {
        token: base.Cancellation = .{},
        calls: usize = 0,
        fn check(raw: *const anyopaque, _: []const permissions.Access, _: usize) bool {
            const self: *@This() = @ptrCast(@alignCast(@constCast(raw)));
            self.calls += 1;
            self.token.request(); // deterministic request between precheck and native work
            return true;
        }
    };
    var probe: Probe = .{};
    const gate: permissions.MemoryGate = .{ .context = &probe, .check = Probe.check };
    const address = forth.data_start;
    // Direct scope avoids the entry check, exercising the native pre-boundary.
    var context: scopes.Context = undefined;
    context.enter(vm, &probe.token);
    defer context.leave();
    context.memory = .{ .memory_gate = &gate };
    try vm.push(address);
    try vm.push(1);
    try vm.push(65);
    probe.token.request();
    try std.testing.expectError(error.TaskCancelled, memory.before(vm, .fill));
    try std.testing.expectEqual(@as(usize, 0), probe.calls);
    // A different fresh token represents the next independent execution.
    var fresh: Probe = .{};
    const after_gate: permissions.MemoryGate = .{ .context = &fresh, .check = Probe.check };
    context.token = &fresh.token;
    context.memory.memory_gate = &after_gate;
    try std.testing.expectError(error.TaskCancelled, vm.runAsWorkerWithMemory(@intCast(vm.builtinWord(.fill)), &fresh.token, .{ .memory_gate = &after_gate }));
    try std.testing.expectEqual(@as(u8, 65), vm.memory[@intCast(address)]);
}

test "1373 memory gate covers primitive builtin call_builtin and word fallback encodings" {
    var output = support.Output{};
    const vm = try support.createMachine(&output);
    defer support.destroyMachine(vm);
    try vm.interpretLine(": JOB 1 ;");
    const id = vm.lookup("JOB").?;
    const at = vm.words[id].code_start;
    const defs = @import("../core/defs.zig");
    var grants = try memory.Grants.init(a, vm);
    defer grants.deinit(a);
    const gate = grants.gate();
    var token: base.Cancellation = .{};
    for ([_]defs.OpKind{ .store, .builtin, .call_builtin, .call }) |kind| {
        vm.code[at] = .{ .kind = kind, .value = if (kind == .builtin) @backingInt(defs.Builtin.store) else vm.builtinWord(.store) };
        vm.data_depth = 0;
        try vm.push(99);
        try vm.push(0);
        try std.testing.expectError(error.InvalidAddress, vm.runAsWorkerWithMemory(id, &token, .{ .memory_gate = &gate }));
        try support.expectStack(vm, &.{ 99, 0 });
        vm.data_depth = 0;
        try vm.push(99);
        try vm.push(forth.data_start);
        try vm.runAsWorkerWithMemory(id, &token, .{ .memory_gate = &gate });
        try std.testing.expectEqual(@as(forth.Cell, 99), try vm.readCell(forth.data_start));
    }
}

test "1373 default native limit accepts 64 KiB and rejects the next byte without writing" {
    var output = support.Output{};
    const vm = try support.createMachine(&output);
    defer support.destroyMachine(vm);
    var grants = try memory.Grants.init(a, vm);
    defer grants.deinit(a);
    const gate = grants.gate();
    var token: base.Cancellation = .{};
    const address = forth.data_start;
    const entry: u16 = @intCast(vm.builtinWord(.fill));
    try vm.push(address);
    try vm.push(65536);
    try vm.push(65);
    try vm.runAsWorkerWithMemory(entry, &token, .{ .memory_gate = &gate });
    try std.testing.expectEqual(@as(u8, 65), vm.memory[@intCast(address + 65535)]);
    try vm.push(address);
    try vm.push(65537);
    try vm.push(66);
    try std.testing.expectError(error.InvalidAddress, vm.runAsWorkerWithMemory(entry, &token, .{ .memory_gate = &gate }));
    try std.testing.expectEqual(@as(u8, 65), vm.memory[@intCast(address)]);
    try support.expectStack(vm, &.{ address, 65537, 66 });
}

test "1373 admitted memory builtins preserve ordinary results on granted data" {
    var left_output = support.Output{};
    var right_output = support.Output{};
    const plain = try support.createMachine(&left_output);
    defer support.destroyMachine(plain);
    const worker = try support.createMachine(&right_output);
    defer support.destroyMachine(worker);
    var grants = try memory.Grants.init(a, worker);
    defer grants.deinit(a);
    const gate = grants.gate();
    var token: base.Cancellation = .{};
    const defs = @import("../core/defs.zig");
    const address = forth.data_start;
    @setEvalBranchQuota(20000);
    inline for (@typeInfo(defs.Builtin).@"enum".field_names) |name| {
        const b = @field(defs.Builtin, name);
        if (comptime permissions.policy(b) == .memory) {
            const args: []const forth.Cell = switch (b) {
                .fetch, .cfetch, .inc_store, .dec_store, .zero_store, .off, .on, .two_fetch, .count => &.{address},
                .store, .cstore, .add_store => &.{ 65, address },
                .array_fetch => &.{ 1, address },
                .array_store => &.{ 65, 1, address },
                .erase, .blank_fill, .minus_trailing => &.{ address, 8 },
                .fill, .scan, .skip => &.{ address, 8, 65 },
                .move, .cmove, .cmove_up => &.{ address, address + 32, 8 },
                .two_store => &.{ 1, 2, address },
                .place, .plus_place => &.{ address, 8, address + 32 },
                .compare, .search, .str_equal, .string_prefix_query => &.{ address, 8, address + 32, 8 },
                else => unreachable,
            };
            for ([_]*forth.State{ plain, worker }) |vm| {
                vm.data_depth = 0;
                const start: usize = @intCast(address);
                @memset(vm.memory[start .. start + 512], 65);
                vm.memory[start] = 3;
                vm.memory[start + 32] = 3;
                for (args) |value| try vm.push(value);
            }
            try plain.executeWord(@intCast(plain.builtinWord(b)));
            try worker.runAsWorkerWithMemory(@intCast(worker.builtinWord(b)), &token, .{ .memory_gate = &gate });
            try std.testing.expectEqualSlices(forth.Cell, plain.data_stack[0..plain.data_depth], worker.data_stack[0..worker.data_depth]);
            const start: usize = @intCast(address);
            try std.testing.expectEqualSlices(u8, plain.memory[start .. start + 512], worker.memory[start .. start + 512]);
        }
    }
}

test "1373 all memory primitive Ops reject protected operands unchanged" {
    var output = support.Output{};
    const vm = try support.createMachine(&output);
    defer support.destroyMachine(vm);
    try vm.interpretLine(": JOB 1 ;");
    const id = vm.lookup("JOB").?;
    const at = vm.words[id].code_start;
    const defs = @import("../core/defs.zig");
    var grants = try memory.Grants.init(a, vm);
    defer grants.deinit(a);
    const gate = grants.gate();
    var token: base.Cancellation = .{};
    @setEvalBranchQuota(30000);
    inline for (@typeInfo(defs.OpKind).@"enum".field_names) |name| {
        const kind = @field(defs.OpKind, name);
        if (comptime defs.isPrimitiveOp(kind)) {
            if (comptime permissions.policy(defs.primitiveBuiltin(kind)) == .memory) {
                vm.code[at] = .{ .kind = kind, .value = 0 };
                vm.data_depth = 0;
                for (0..4) |_| try vm.push(1);
                try std.testing.expectError(error.InvalidAddress, vm.runAsWorkerWithMemory(id, &token, .{ .memory_gate = &gate }));
                try support.expectStack(vm, &.{ 1, 1, 1, 1 });
            }
        }
    }
}

test "1373 copied inline body colon call and string literal cannot bypass gate" {
    var output = support.Output{};
    const vm = try support.createMachine(&output);
    defer support.destroyMachine(vm);
    try vm.interpretLine(": WRITE ! ; : JOB WRITE ; : TEXT S\" abc\" ;");
    const id = vm.lookup("JOB").?;
    const at = vm.words[id].code_start;
    const inlining = @import("../core/inline_calls.zig");
    // Explicit encoding makes the regression independent of debug inlining options.
    vm.code[at] = .{ .kind = .call_colon, .value = inlining.operand(vm.lookup("WRITE").?, 2, 1) };
    vm.code[at + 1] = vm.code[vm.words[vm.lookup("WRITE").?].code_start];
    vm.code[at + 2] = .{ .kind = .exit, .value = 0 };
    vm.words[id].code_end = at + 3;
    var grants = try memory.Grants.init(a, vm);
    defer grants.deinit(a);
    const gate = grants.gate();
    var token: base.Cancellation = .{};
    for (0..2) |mode| {
        if (mode == 1) vm.code[at] = .{ .kind = .call, .value = vm.lookup("WRITE").? };
        vm.data_depth = 0;
        try vm.push(99);
        try vm.push(0);
        try std.testing.expectError(error.InvalidAddress, vm.runAsWorkerWithMemory(id, &token, .{ .memory_gate = &gate }));
        try support.expectStack(vm, &.{ 99, 0 });
    }
    const text = vm.lookup("TEXT").?;
    vm.code[vm.words[text].code_start] = .{ .kind = .string_literal, .value = 0 };
    vm.data_depth = 0;
    try std.testing.expectError(error.InvalidAddress, vm.runAsWorkerWithMemory(text, &token, .{ .memory_gate = &gate }));
    try support.expectStack(vm, &.{});
}

test "1373 direct worker denies host probes and bounds variable stack work" {
    var output = support.Output{};
    const vm = try support.createMachine(&output);
    defer support.destroyMachine(vm);
    var token: base.Cancellation = .{};
    for ([_]@import("../core/defs.zig").Builtin{ .dot, .key_ior }) |b| {
        try std.testing.expectError(error.InvalidExecutionToken, vm.runAsWorker(@intCast(vm.builtinWord(b)), &token));
    }
    for ([_]@import("../core/defs.zig").Builtin{ .roll, .pick, .n_to_r, .n_r_from }) |b| {
        vm.data_depth = 0;
        vm.return_depth = 0;
        try vm.push(2);
        vm.return_stack[0] = 2;
        vm.return_depth = 1;
        try std.testing.expectError(error.InvalidAddress, vm.runAsWorkerWithMemory(@intCast(vm.builtinWord(b)), &token, .{ .max_native_bytes = 16 }));
        try support.expectStack(vm, &.{2});
        try std.testing.expectEqual(@as(usize, 1), vm.return_depth);
    }
}

test "1373 variable stack preflight accepts exactly 64 KiB and rejects next cell" {
    var output = support.Output{};
    const vm = try support.createMachine(&output);
    defer support.destroyMachine(vm);
    var token: base.Cancellation = .{};
    var context: scopes.Context = undefined;
    context.enter(vm, &token);
    defer context.leave();
    for ([_]@import("../core/defs.zig").Builtin{ .roll, .pick, .n_to_r, .n_r_from }) |b| {
        vm.data_depth = 0;
        try vm.push(8191);
        vm.return_depth = 1;
        vm.return_stack[0] = 8191;
        // Test the budget preflight alone; no oversized VM allocation is needed.
        try memory.before(vm, b);
        vm.data_stack[0] = 8192;
        vm.return_stack[0] = 8192;
        try std.testing.expectError(error.InvalidAddress, memory.before(vm, b));
        try support.expectStack(vm, &.{8192});
        try std.testing.expectEqual(@as(forth.Cell, 8192), vm.return_stack[0]);
    }
}
