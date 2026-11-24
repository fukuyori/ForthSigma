const std = @import("std");
const r = @import("../core/task_results.zig");
const t = std.testing;

test "task results boundaries, retry and non consuming reads" {
    var budgets: r.Budgets = .{};
    for ([_]usize{ 0, r.result_limit }) |size| {
        const source = try t.allocator.alloc(u8, size);
        defer t.allocator.free(source);
        @memset(source, 42);
        var buffer = try r.Buffer.copy(t.allocator, &budgets.transfer, source, r.result_limit);
        defer buffer.deinit();
        if (size != 0) {
            var short = [_]u8{99};
            const insufficient = buffer.query(&short);
            try t.expectEqual(size, insufficient.required);
            try t.expect(!insufficient.copied);
            try t.expectEqual(@as(u8, 99), short[0]);
        }
        const destination = try t.allocator.alloc(u8, size);
        defer t.allocator.free(destination);
        for (0..2) |_| {
            try t.expect(buffer.query(destination).copied);
            try t.expectEqualSlices(u8, source, destination);
        }
    }
    try t.expectEqual(@as(usize, 0), budgets.transfer.used);
    const large = try t.allocator.alloc(u8, r.result_limit + 1);
    defer t.allocator.free(large);
    try t.expectError(error.ItemLimitExceeded, r.Buffer.copy(t.allocator, &budgets.transfer, large, r.result_limit));
}

test "task results aggregate reservation and release" {
    var budgets: r.Budgets = .{};
    try budgets.transfer.reserve(budgets.transfer.limit);
    try t.expectError(error.TotalLimitExceeded, budgets.transfer.reserve(1));
    try t.expectError(error.TotalLimitExceeded, budgets.transfer.reserve(std.math.maxInt(usize)));
    budgets.transfer.release(budgets.transfer.limit);
    try budgets.transfer.reserve(1);
    budgets.transfer.release(1);
    try budgets.diagnostic.reserve(budgets.diagnostic.limit);
    try t.expectError(error.TotalLimitExceeded, r.Buffer.copy(t.allocator, &budgets.diagnostic, "x", r.diagnostic_limit));
    budgets.diagnostic.release(budgets.diagnostic.limit);
}

test "task results failure and cancellation discard partial result and retain diagnostics" {
    var budgets: r.Budgets = .{};
    for ([_]r.Terminal{ .failed, .cancelled }) |terminal| {
        var completion = r.Completion.init(terminal, try r.Buffer.copy(t.allocator, &budgets.transfer, "partial", r.result_limit), .{ .code = .execution, .text = try r.Buffer.copy(t.allocator, &budgets.diagnostic, "cause", r.diagnostic_limit) }, .{ .code = .cleanup });
        try t.expect(completion.queryResult(&.{}) == null);
        try t.expectEqual(@as(usize, 0), budgets.transfer.used);
        var text: [5]u8 = undefined;
        try t.expect(completion.primary.?.text.?.query(&text).copied);
        try t.expectEqualStrings("cause", &text);
        try t.expectEqual(terminal, completion.terminal);
        completion.deinit();
    }
    try t.expectEqual(@as(usize, 0), budgets.diagnostic.used);
}

test "task Writer exact limit, sticky overflow and cancellation precedence" {
    var budgets: r.Budgets = .{};
    const bytes = try t.allocator.alloc(u8, r.diagnostic_limit);
    defer t.allocator.free(bytes);
    @memset(bytes, 65);
    for ([_]r.Terminal{ .succeeded, .failed, .cancelled }) |terminal| {
        var output = try r.WorkerOutput.init(t.allocator, &budgets.diagnostic);
        defer output.deinit();
        const writer = output.writer();
        writer.write_fn(writer.context, &.{});
        writer.write_fn(writer.context, bytes);
        try t.expect(output.failure == null);
        writer.write_fn(writer.context, "x");
        writer.write_fn(writer.context, "ignored");
        var completion = output.finish(terminal, null, if (terminal == .succeeded) null else .{ .code = .execution }, .{ .code = .cleanup });
        defer completion.deinit();
        try t.expectEqual(if (terminal == .succeeded) r.Terminal.failed else terminal, completion.terminal);
        const diagnostic = if (terminal == .succeeded) completion.primary.? else completion.writer_failure.?;
        try t.expectEqual(r.DiagnosticCode.writer_overflow, diagnostic.code);
        try t.expectEqual(r.diagnostic_limit, completion.output.?.bytes.len);
        try t.expectEqual(r.DiagnosticCode.cleanup, completion.secondary.?.code);
    }
    try t.expectEqual(@as(usize, 0), budgets.diagnostic.used);
}

test "task results VM copy integration and allocation rollback" {
    const forth = @import("../forth.zig");
    var budgets: r.Budgets = .{};
    const vm = try t.allocator.create(forth.State);
    defer t.allocator.destroy(vm);
    const storage = try forth.Storage.allocate(t.allocator, false, .small);
    defer storage.free(t.allocator);
    var output = try r.WorkerOutput.init(t.allocator, &budgets.diagnostic);
    defer output.deinit();
    vm.init(output.writer(), storage);
    vm.data_depth = 2;
    vm.data_stack[0] = forth.data_start;
    vm.data_stack[1] = 1;
    vm.memory[@intCast(forth.data_start)] = 77;
    var copied = try r.Buffer.copyResult(vm, t.allocator, &budgets.transfer, .{});
    try t.expectEqualStrings("M", copied.bytes);
    copied.deinit();
    var failing = t.FailingAllocator.init(t.allocator, .{ .fail_index = 0 });
    try t.expectError(error.OutOfMemory, r.Buffer.copyResult(vm, failing.allocator(), &budgets.transfer, .{}));
    try t.expectEqual(@as(usize, 0), budgets.transfer.used);
    const reserved = budgets.diagnostic.used;
    try t.expectError(error.OutOfMemory, r.WorkerOutput.init(failing.allocator(), &budgets.diagnostic));
    try t.expectEqual(reserved, budgets.diagnostic.used);
}

test "task diagnostic boundaries and Writer shared budget failure" {
    var budgets: r.Budgets = .{};
    const bytes = try t.allocator.alloc(u8, r.diagnostic_limit + 1);
    defer t.allocator.free(bytes);
    @memset(bytes, 0);
    var diagnostic = try r.Diagnostic.copy(t.allocator, &budgets.diagnostic, .execution, bytes[0..r.diagnostic_limit]);
    diagnostic.text.?.deinit();
    try t.expectError(error.ItemLimitExceeded, r.Diagnostic.copy(t.allocator, &budgets.diagnostic, .execution, bytes));
    try budgets.diagnostic.reserve(budgets.diagnostic.limit);
    try t.expectError(error.TotalLimitExceeded, r.WorkerOutput.init(t.allocator, &budgets.diagnostic));
    budgets.diagnostic.release(budgets.diagnostic.limit);
}

test "task Writer preallocation, byte writes and successful output ownership" {
    var budget: r.Budget = .{ .limit = r.diagnostic_limit };
    var failing = t.FailingAllocator.init(t.allocator, .{ .fail_index = 1 });
    var output = try r.WorkerOutput.init(failing.allocator(), &budget);
    defer output.deinit();
    const writer = output.writer();
    for (0..r.diagnostic_limit) |_| writer.write_fn(writer.context, "a");
    try t.expect(output.failure == null);
    try t.expectEqual(r.diagnostic_limit, budget.used);
    var completion = output.finish(.succeeded, null, null, .{ .code = .cleanup });
    try t.expectEqual(r.Terminal.succeeded, completion.terminal);
    try t.expect(completion.primary == null);
    try t.expect(completion.writer_failure == null);
    try t.expectEqual(r.DiagnosticCode.cleanup, completion.secondary.?.code);
    try t.expectEqual(r.diagnostic_limit, completion.output.?.bytes.len);
    for (completion.output.?.bytes) |byte| try t.expectEqual(@as(u8, 'a'), byte);
    completion.deinit();
    try t.expectEqual(@as(usize, 0), budget.used);
}

test "task Writer worker handback and partial reservation lifetime" {
    var budget: r.Budget = .{ .limit = r.diagnostic_limit * 2 };
    var output = try r.WorkerOutput.init(t.allocator, &budget);
    defer output.deinit();
    const Worker = struct {
        fn run(target: *r.WorkerOutput) void {
            const writer = target.writer();
            writer.write_fn(writer.context, "abc");
        }
    };
    const thread = try std.Thread.spawn(.{}, Worker.run, .{&output});
    // Host operations may overlap worker writes: the worker never touches budget.
    try budget.reserve(r.diagnostic_limit);
    budget.release(r.diagnostic_limit);
    thread.join();
    var completion = output.finish(.succeeded, null, null, null);
    try t.expect(output.buffer == null);
    try t.expectEqualStrings("abc", completion.output.?.bytes);
    try t.expect(completion.secondary == null);
    try t.expectEqual(r.diagnostic_limit, budget.used);
    completion.deinit();
    try t.expectEqual(@as(usize, 0), budget.used);
}

test "task Writer empty output owns full reservation until completion destruction" {
    var budget: r.Budget = .{ .limit = r.diagnostic_limit };
    var output = try r.WorkerOutput.init(t.allocator, &budget);
    defer output.deinit();
    var completion = output.finish(.succeeded, null, null, null);
    try t.expectEqual(@as(usize, 0), completion.output.?.bytes.len);
    try t.expectEqual(r.diagnostic_limit, budget.used);
    completion.deinit();
    try t.expectEqual(@as(usize, 0), budget.used);
}
