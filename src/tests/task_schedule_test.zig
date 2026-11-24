const std = @import("std");
const s = @import("../core/task_schedule.zig");
const base = @import("../core/runtime_base.zig");
const t = std.testing;
fn clockNow(context: ?*anyopaque) base.Error!base.Instant {
    return @as(*base.Instant, @ptrCast(@alignCast(context.?))).*;
}
fn item(id: u64, kind: s.Kind, stream: u64) s.Waiting {
    return .{ .id = id, .kind = kind, .stream = stream, .deadline = 100 };
}
fn failedClock(_: ?*anyopaque) base.Error!base.Instant {
    return error.HostFailed;
}
test "schedule rejects oversized inputs and propagates clock failure" {
    const waiting: [5]s.Waiting = @splat(item(1, .io, 0));
    const records: [17]s.Completion = @splat(.{ .id = 1, .remaining = 0 });
    const deadlines: [17]base.Instant = @splat(10);
    try t.expectError(error.InvalidInput, s.admit(&waiting, .{ .kind = .io, .stream = 0 }));
    try t.expectError(error.InvalidInput, s.decide(.{ .waiting = &waiting }, 0, 0));
    try t.expectError(error.InvalidInput, s.decide(.{ .completions = &records }, 0, 0));
    try t.expectError(error.InvalidInput, s.decide(.{ .deadlines = &deadlines }, 0, 0));
    try t.expectError(error.HostFailed, s.turn(.{}, .{ .context = null, .now_fn = failedClock }, 0));
}
test "schedule aggregate copy bound exact boundary and blocked-only reads do not spin" {
    const records = [_]s.Completion{
        .{ .id = 1, .remaining = s.Limits.copy_bytes - 1 },
        .{ .id = 2, .remaining = 1 },
        .{ .id = 3, .remaining = 1 },
    };
    var d = try s.decide(.{ .completions = &records }, 0, 0);
    try t.expectEqual(@as(usize, 2), d.copy_count);
    var total: usize = 0;
    for (d.copies[0..d.copy_count]) |copy| total += copy.bytes;
    try t.expectEqual(@as(usize, s.Limits.copy_bytes), total);
    try t.expect(d.next == .run_again);
    const waiting: [4]s.Waiting = @splat(item(1, .io, 0));
    var events: [s.source_count]usize = @splat(0);
    events[@backingInt(s.Source.io_read)] = 100;
    d = try s.decide(.{ .waiting = &waiting, .events = events }, 0, 0);
    try t.expectEqual(@as(base.Instant, 100), d.next.sleep_until);
}
test "schedule continuous sources progress with rotating start and bounded work" {
    var now: base.Instant = 0;
    const clock: base.Clock = .{ .context = &now, .now_fn = clockNow };
    var start: usize = 0;
    var remaining: usize = s.Limits.copy_bytes * 3 + 1;
    var first: [s.source_count]usize = @splat(0);
    for (0..70) |_| {
        const records = [_]s.Completion{.{ .id = 7, .remaining = remaining }};
        const d = try s.turn(.{ .events = @splat(100), .completions = &records, .deadlines = &.{50} }, clock, start);
        first[@backingInt(d.order[0])] += 1;
        for (d.take, 0..) |take, index| {
            try t.expect(take > 0);
            try t.expect(take <= if (index == @backingInt(s.Source.completion)) s.Limits.notifications else s.Limits.events);
        }
        try t.expect(d.copy_count <= s.Limits.completions);
        try t.expect(d.copies[0].bytes <= s.Limits.copy_bytes);
        remaining -= d.copies[0].bytes;
        if (remaining == 0) remaining = s.Limits.copy_bytes * 3 + 1;
        try t.expect(d.next == .run_again);
        start = d.next_start;
        now += 1;
    }
    for (first) |count| try t.expectEqual(@as(usize, 10), count);
}
test "schedule FIFO copy count and partial head with notification-only input" {
    var records: [6]s.Completion = undefined;
    for (&records, 0..) |*record, i| record.* = .{ .id = i, .remaining = 0 };
    var d = try s.decide(.{ .completions = &records }, 0, 0);
    try t.expectEqual(@as(usize, 4), d.copy_count);
    for (d.copies, 0..) |copy, i| try t.expectEqual(i, copy.id);
    records[0].remaining = s.Limits.copy_bytes + 1;
    d = try s.decide(.{ .completions = &records }, 0, 0);
    try t.expectEqual(@as(usize, 1), d.copy_count);
    try t.expect(!d.copies[0].finish);
    records[0].remaining -= d.copies[0].bytes;
    d = try s.decide(.{ .completions = &records }, 1, d.next_start);
    try t.expect(d.copies[0].finish);
    try t.expectEqual(@as(usize, 1), d.copies[0].bytes);
    var events: [s.source_count]usize = @splat(0);
    events[@backingInt(s.Source.completion)] = 500;
    d = try s.decide(.{ .events = events }, 0, 0);
    try t.expectEqual(@as(usize, 0), d.copy_count);
}
test "schedule latest replacement domain FIFO and backpressure" {
    const waiting = [_]s.Waiting{ item(1, .game, 1), item(2, .io, 0), item(3, .tui, 9), item(4, .io, 0) };
    try t.expectEqual(@as(u64, 1), (try s.admit(&waiting, .{ .kind = .game, .stream = 1 })).placement.replace.id);
    try t.expectEqual(@as(u64, 3), (try s.admit(&waiting, .{ .kind = .tui, .stream = 9 })).placement.replace.id);
    try t.expect((try s.admit(&waiting, .{ .kind = .tui, .stream = 10 })).placement == .backpressure);
    const replaced = [_]s.Waiting{ item(5, .game, 1), waiting[1], waiting[2], waiting[3] };
    const d = try s.decide(.{ .waiting = &replaced, .worker_available = true }, 0, 0);
    try t.expectEqual(@as(?u64, 5), d.dispatch);
    try t.expect((try s.admit(waiting[0..3], .{ .kind = .io, .stream = 0 })).placement == .append);
    const full = try s.decide(.{ .waiting = &waiting, .events = @splat(100) }, 0, 0);
    try t.expect(full.pause_compute_reads);
    try t.expectEqual(@as(usize, 0), full.take[@backingInt(s.Source.io_read)]);
    try t.expectEqual(@as(usize, 0), full.io_read_bytes);
    try t.expect(full.io_drain_bytes > 0 and full.io_drain_bytes <= s.Limits.io_bytes);
    const resumed = try s.decide(.{ .waiting = waiting[0..3], .events = @splat(1) }, 0, 1);
    try t.expect(!resumed.pause_compute_reads and resumed.io_read_bytes > 0);
}
test "schedule prohibits worker submissions and all dependency edges including cycles" {
    for ([_]usize{ 0, 1, 2 }) |dependencies| {
        try t.expect((try s.admit(&.{}, .{ .worker = true, .kind = .io, .stream = 0, .result_dependencies = dependencies })).placement == .forbidden);
    }
    try t.expect((try s.admit(&.{}, .{ .kind = .io, .stream = 0, .result_dependencies = 1 })).placement == .forbidden);
}
test "schedule fake clock absolute deadlines cancellations and FIFO dispatch" {
    var now: base.Instant = 99;
    const clock: base.Clock = .{ .context = &now, .now_fn = clockNow };
    var waiting = [_]s.Waiting{ item(1, .game, 0), item(2, .io, 0), item(3, .io, 0) };
    waiting[0].cancel_requested = true;
    waiting[2].deadline = 200;
    var d = try s.turn(.{ .waiting = &waiting }, clock, 0);
    try t.expectEqual(@as(usize, 1), d.removal_count);
    try t.expect(d.removals[0].reason == .cancel);
    now = 100;
    d = try s.turn(.{ .waiting = &waiting, .worker_available = true }, clock, d.next_start);
    try t.expectEqual(@as(usize, 2), d.removal_count);
    try t.expect(d.removals[1].reason == .expired);
    try t.expectEqual(@as(?u64, 3), d.dispatch);
    d = try s.turn(.{ .deadlines = &.{ 150, 105, 110 } }, clock, 0);
    try t.expectEqual(@as(base.Instant, 105), d.next.sleep_until);
    now = 105;
    d = try s.turn(.{ .deadlines = &.{ 150, 105, 110 }, .events = @splat(100) }, clock, 1);
    try t.expect(d.next == .run_again);
    try t.expectError(error.InvalidInput, s.decide(.{}, 0, s.source_count));
}

test "schedule replacement retains FIFO progress under continuous IO and faster game replacement" {
    var queue = [_]s.Waiting{ item(1, .io, 0), item(2, .io, 0), item(3, .io, 0), item(4, .game, 1) };
    var generation: u64 = 0;
    var game_id: u64 = 4;
    // Each IO dispatch is followed by new IO and multiple game replacements.
    for (0..4) |round| {
        const d = try s.decide(.{ .waiting = &queue, .worker_available = true }, 0, round);
        if (round == 3) {
            try t.expectEqual(@as(?u64, game_id), d.dispatch);
            return;
        }
        try t.expectEqual(@as(?u64, round + 1), d.dispatch);
        for (0..3) |i| queue[i] = queue[i + 1];
        queue[3] = item(10 + round, .io, 0);
        for (0..3) |_| {
            const a = try s.admit(&queue, .{ .kind = .game, .stream = 1, .current_generation = generation });
            const slot = a.placement.replace;
            try t.expectEqual(game_id, slot.id);
            try t.expectEqual(@as(usize, 2 - round), slot.index);
            game_id += 100;
            queue[slot.index] = item(game_id, .game, 1);
            generation = a.generation.?;
        }
    }
    return error.TestUnexpectedResult;
}

test "schedule latest running cancellation and stale publication for game and TUI" {
    for ([_]s.Kind{ .game, .tui }) |kind| {
        const running: s.Running = .{ .id = 10, .kind = kind, .stream = 3 };
        var a = try s.admit(&.{}, .{ .kind = kind, .stream = 3, .running = running, .current_generation = 7 });
        try t.expect(a.placement == .append);
        try t.expectEqual(@as(?u64, 10), a.cancel_running);
        try t.expectEqual(@as(?u64, 8), a.generation);
        const waiting = [_]s.Waiting{item(11, kind, 3)};
        a = try s.admit(&waiting, .{ .kind = kind, .stream = 3, .running = running, .current_generation = 8 });
        try t.expectEqual(@as(u64, 11), a.placement.replace.id);
        try t.expectEqual(@as(usize, 0), a.placement.replace.index);
        try t.expectEqual(@as(?u64, 10), a.cancel_running);
        try t.expect(!s.resultIsCurrent(7, a.generation.?));
        try t.expect(!s.resultIsCurrent(8, a.generation.?));
        try t.expect(s.resultIsCurrent(9, a.generation.?));
        // A completed request still becomes stale even without running work.
        a = try s.admit(&.{}, .{ .kind = kind, .stream = 3, .current_generation = 9 });
        try t.expect(!s.resultIsCurrent(9, a.generation.?));
        try t.expect(a.cancel_running == null);
        a = try s.admit(&.{}, .{ .kind = kind, .stream = 4, .running = running });
        try t.expect(a.cancel_running == null);
        a = try s.admit(&.{}, .{ .kind = if (kind == .game) .tui else .game, .stream = 3, .running = running });
        try t.expect(a.cancel_running == null);
    }
    const full: [s.capacity]s.Waiting = @splat(item(1, .io, 0));
    const rejected = try s.admit(&full, .{ .kind = .game, .stream = 1, .running = .{ .id = 9, .kind = .game, .stream = 1 } });
    try t.expect(rejected.placement == .backpressure);
    try t.expect(rejected.generation == null and rejected.cancel_running == null);
    const forbidden = try s.admit(&.{}, .{ .worker = true, .kind = .game, .stream = 1, .running = .{ .id = 9, .kind = .game, .stream = 1 } });
    try t.expect(forbidden.generation == null and forbidden.cancel_running == null);
    const io = try s.admit(&.{}, .{ .kind = .io, .stream = 1, .running = .{ .id = 9, .kind = .io, .stream = 1 } });
    try t.expect(io.generation == null and io.cancel_running == null);
    try t.expectError(error.ResultOutOfRange, s.admit(&.{}, .{ .kind = .game, .stream = 1, .current_generation = std.math.maxInt(u64) }));
}

test "schedule distinguishes idle wake wait timed wait and immediate work" {
    var d = try s.decide(.{}, 0, 0);
    try t.expect(d.next == .wait_for_wake);
    d = try s.decide(.{ .deadlines = &.{10} }, 0, 0);
    try t.expectEqual(@as(base.Instant, 10), d.next.sleep_until);
    d = try s.decide(.{ .deadlines = &.{10} }, 10, 0);
    try t.expect(d.next == .run_again);
    var events: [s.source_count]usize = @splat(0);
    events[@backingInt(s.Source.input)] = s.Limits.events + 1;
    d = try s.decide(.{ .events = events }, 0, 0);
    try t.expect(d.next == .run_again);
    const records = [_]s.Completion{.{ .id = 1, .remaining = s.Limits.copy_bytes + 1 }};
    d = try s.decide(.{ .completions = &records }, 0, 0);
    try t.expect(d.next == .run_again);
}
