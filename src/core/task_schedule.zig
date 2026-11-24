//! Bounded host-turn decisions; no allocation, queue, ledger, VM or Forth ABI.
const base = @import("runtime_base.zig");
pub const capacity = 4;
pub const Source = enum { input, io_read, io_drain, completion, draw, cancel, reclaim };
pub const source_count = @typeInfo(Source).@"enum".field_names.len;
pub const Limits = struct {
    pub const events: usize = 8;
    pub const notifications: usize = 16;
    pub const completion_records: usize = 16;
    pub const deadlines: usize = 16;
    pub const completions: usize = 4;
    pub const copy_bytes: usize = 16 * 1024;
    pub const io_bytes: usize = 16 * 1024;
};
pub const Kind = enum { game, tui, io };
pub const Waiting = struct {
    id: u64,
    kind: Kind,
    stream: u64,
    deadline: base.Instant,
    cancel_requested: bool = false,
};
pub const Running = struct { id: u64, kind: Kind, stream: u64 };
pub const Submission = struct {
    /// Host-owned current generation for this (kind, stream), including completed work.
    current_generation: u64 = 0,
    running: ?Running = null,
    worker: bool = false,
    kind: Kind,
    stream: u64,
    result_dependencies: usize = 0,
};
pub const Placement = union(enum) {
    append,
    /// Replace in place: retain the old FIFO slot, not its deadline or payload.
    replace: struct { id: u64, index: usize },
    backpressure,
    forbidden,
};
pub const Admission = struct {
    placement: Placement,
    /// Accepted game/TUI request's generation; null for I/O or rejection.
    generation: ?u64 = null,
    cancel_running: ?u64 = null,
};
pub const Error = error{ InvalidInput, HostFailed, ResultOutOfRange };

/// Pure proposal over a coherent host observation. Reserve resources first,
/// then atomically commit placement, generation and cancellation together.
/// On failure preserve the queue, generation and running request unchanged.
/// Host stamps accepted work with generation and compares it to the current
/// generation for the SAME (kind, stream) immediately before publishing results.
/// Never reset/reuse a stream generation while old results can still arrive.
pub fn admit(waiting: []const Waiting, request: Submission) Error!Admission {
    if (waiting.len > capacity) return error.InvalidInput;
    if (request.worker or request.result_dependencies != 0) return .{ .placement = .forbidden };
    var placement: Placement = if (waiting.len == capacity) .backpressure else .append;
    if (request.kind != .io) {
        for (waiting, 0..) |entry, index| {
            if (entry.kind == request.kind and entry.stream == request.stream) {
                placement = .{ .replace = .{ .id = entry.id, .index = index } };
                break;
            }
        }
    }
    if (placement == .backpressure or request.kind == .io) return .{ .placement = placement };
    if (request.current_generation == @import("std").math.maxInt(u64)) return error.ResultOutOfRange;
    var out: Admission = .{ .placement = placement, .generation = request.current_generation + 1 };
    if (request.running) |running| {
        if (running.kind == request.kind and running.stream == request.stream)
            out.cancel_running = running.id;
    }
    return out;
}

/// Call under the host's publication/acceptance synchronization for this stream.
pub fn resultIsCurrent(result_generation: u64, current_generation: u64) bool {
    return result_generation == current_generation;
}

/// Acquired sealed records, oldest first; NOT notifications. remaining includes
/// diagnostics. Host retains partial-copy cursor, publishes only on final copy.
pub const Completion = struct { id: u64, remaining: usize };
pub const Input = struct {
    waiting: []const Waiting = &.{},
    completions: []const Completion = &.{},
    events: [source_count]usize = @splat(0),
    worker_available: bool = false,
    /// Absolute WAIT/decoder/frame/cancel/reclaim/wake-recovery deadlines.
    deadlines: []const base.Instant = &.{},
};
pub const Removal = struct { id: u64, reason: enum { cancel, expired } };
pub const Copy = struct { id: u64, bytes: usize, finish: bool };
pub const Decision = struct {
    order: [source_count]Source = undefined,
    next_start: usize,
    take: [source_count]usize = @splat(0),
    io_read_bytes: usize = 0,
    io_drain_bytes: usize = 0,
    copies: [Limits.completions]Copy = undefined,
    copy_count: usize = 0,
    removals: [capacity]Removal = undefined,
    removal_count: usize = 0,
    dispatch: ?u64 = null,
    pause_compute_reads: bool,
    /// Before either wait, probe ALL conditions after terminal updates and
    /// recheck wake generation. wait_for_wake has no timer, but must wake on
    /// capacity changes/new work; host supplies any required recovery deadline.
    next: union(enum) { run_again, sleep_until: base.Instant, wait_for_wake } = .run_again,
};

/// Pure decision. Carry next_start between turns. Host executes all source
/// quotas nonblockingly in order; an adapter event must itself have bounded cost.
pub fn decide(input: Input, now: base.Instant, start: usize) Error!Decision {
    if (input.waiting.len > capacity or input.completions.len > Limits.completion_records or
        input.deadlines.len > Limits.deadlines or start >= source_count) return error.InvalidInput;
    var out: Decision = .{
        .next_start = (start + 1) % source_count,
        .pause_compute_reads = input.waiting.len == capacity,
    };
    var pending = false;
    for (0..source_count) |offset| {
        const index = (start + offset) % source_count;
        out.order[offset] = @fromBackingInt(@intCast(index));
        const blocked = index == @backingInt(Source.io_read) and out.pause_compute_reads;
        const limit: usize = if (index == @backingInt(Source.completion)) Limits.notifications else Limits.events;
        out.take[index] = if (blocked) 0 else @min(input.events[index], limit);
        // Backpressured reads alone must not spin: capacity changes wake host.
        if (!blocked and input.events[index] > out.take[index]) pending = true;
    }
    out.io_read_bytes = if (out.take[@backingInt(Source.io_read)] != 0) Limits.io_bytes else 0;
    out.io_drain_bytes = if (out.take[@backingInt(Source.io_drain)] != 0) Limits.io_bytes else 0;
    var budget: usize = Limits.copy_bytes;
    for (input.completions) |item| {
        if (out.copy_count == Limits.completions) break;
        const bytes = @min(item.remaining, budget);
        if (item.remaining != 0 and bytes == 0) break;
        const finish = bytes == item.remaining;
        out.copies[out.copy_count] = .{ .id = item.id, .bytes = bytes, .finish = finish };
        out.copy_count += 1;
        budget -= bytes;
        if (!finish) break;
    }
    if (out.copy_count < input.completions.len or
        (out.copy_count != 0 and !out.copies[out.copy_count - 1].finish)) pending = true;
    var earliest: ?base.Instant = null;
    for (input.waiting) |item| {
        if (item.cancel_requested or now >= item.deadline) {
            out.removals[out.removal_count] = .{
                .id = item.id,
                .reason = if (item.cancel_requested) .cancel else .expired,
            };
            out.removal_count += 1;
        } else {
            minimum(&earliest, item.deadline);
            if (input.worker_available and out.dispatch == null) out.dispatch = item.id;
        }
    }
    for (input.deadlines) |deadline| minimum(&earliest, deadline);
    // Proposals only: host must atomically claim queue ownership before update.
    if (out.removal_count != 0 or out.dispatch != null) pending = true;
    if (earliest) |deadline| {
        if (deadline <= now) pending = true;
    }
    if (!pending) out.next = if (earliest) |deadline| .{ .sleep_until = deadline } else .wait_for_wake;
    return out;
}
fn minimum(value: *?base.Instant, candidate: base.Instant) void {
    value.* = if (value.*) |old| @min(old, candidate) else candidate;
}
pub fn turn(input: Input, clock: base.Clock, start: usize) Error!Decision {
    return decide(input, try clock.now(), start);
}
