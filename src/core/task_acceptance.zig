//! Opt-in acceptance endpoints. Timing runs use fixed worker atomics only.
//! Memory-only runs explicitly hold resources until the parent samples them.
const std = @import("std");
pub const enabled = @import("build_options").task_acceptance and @import("builtin").os.tag != .freestanding;
pub const diagnostics = enabled and @import("build_options").task_reclaim_diagnostics;
const Stage = @import("task_trace.zig").Stage;
pub var smoke = true;
pub var memory_hold = false;
extern "c" fn getchar() c_int;
pub fn memoryCheckpoint() void {
    if (comptime !enabled) return;
    if (!memory_hold) return;
    std.debug.print("ACCEPTANCE-MEMORY-HOLD\n", .{});
    _ = getchar();
}
pub var cancel_at: ?Stage = null;
pub var native_name: ?[]const u8 = null;
pub fn configure(short: ?[]const u8, cancel: ?[]const u8, native: ?[]const u8) !void {
    if (comptime enabled) {
        const host_clock = @import("../host_clock.zig");
        const clock_name = if (@import("builtin").os.tag == .windows) "QPC" else "CLOCK_MONOTONIC";
        std.debug.print("ACCEPTANCE {{\"clock\":\"{s}\",\"monotonic\":true,\"resolution_ns\":{d}}}\n", .{ clock_name, try host_clock.resolutionNs() });
    }
    if (comptime enabled and !@import("build_options").task_native_probe) {
        if (native != null) return error.NativeProbeDisabled;
        std.debug.print("ACCEPTANCE {{\"native_probe\":false}}\n", .{});
    }
    native_name = native;
    smoke = if (short) |s| std.mem.eql(u8, s, "1") else true;
    cancel_at = if (cancel) |s| std.meta.stringToEnum(Stage, s) orelse return error.InvalidAcceptanceStage else null;
}
pub inline fn now() i64 {
    if (comptime !enabled) return 0;
    if (smoke) return 0;
    return std.math.cast(i64, @import("../host_clock.zig").now() catch return 0) orelse 0;
}
// Host-only buffering keeps serialization and pipe writes outside measured sections.
const Event = union(enum) {
    value: struct { metric: []const u8, value: usize },
    interval: struct { metric: []const u8, start: i64, end: i64 },
    task: struct { storage: Storage, id: i64, reclaimed: i64 },
};
var events: [512]Event = undefined;
var count: usize = 0;
var lost: usize = 0;
// Host-only: output must not delay a requested task's next management turn.
var pending_cancellations: usize = 0;
pub inline fn cancellationRequested() void {
    if (comptime enabled) pending_cancellations += 1;
}
fn append(event: Event) void {
    if (count == events.len) {
        lost += 1;
        return;
    }
    events[count] = event;
    count += 1;
}
pub inline fn interval(comptime metric: []const u8, start: i64) void {
    if (comptime enabled) {
        if (memory_hold) return;
        append(.{ .interval = .{ .metric = metric, .start = start, .end = now() } });
    }
}
pub inline fn value(comptime metric: []const u8, amount: usize) void {
    if (comptime enabled) append(.{ .value = .{ .metric = metric, .value = amount } });
}
pub fn flush() void {
    if (comptime !enabled) return;
    const main_started = if (comptime @import("task_main_diagnostics.zig").enabled) @import("task_main_diagnostics.zig").begin() else {};
    defer if (comptime @import("task_main_diagnostics.zig").enabled) @import("task_main_diagnostics.zig").end("acceptance_flush", main_started);
    if (pending_cancellations != 0) return;
    @import("../host_paint_trace.zig").flush();
    const started = if (comptime diagnostics) now() else 0;
    for (events[0..count]) |event| switch (event) {
        .value => |v| std.debug.print("ACCEPTANCE {{\"metric\":\"{s}\",\"value\":{d}}}\n", .{ v.metric, v.value }),
        .interval => |v| std.debug.print("ACCEPTANCE {{\"metric\":\"{s}\",\"start\":{d},\"end\":{d},\"smoke\":{}}}\n", .{ v.metric, v.start, v.end, smoke }),
        .task => |v| v.storage.print(v.id, v.reclaimed),
    };
    if (lost != 0) std.debug.print("ACCEPTANCE {{\"lost_events\":{d}}}\n", .{lost});
    count = 0;
    lost = 0;
    // Record on the NEXT flush: never recursively measure our own output.
    if (comptime diagnostics) interval("acceptance_flush_ns", started);
}
pub const Storage = if (enabled) struct {
    retirement_start: i64 = 0, // worker writes; host reads only after !isCleaning
    retirement_end: i64 = 0,
    handback_end: i64 = 0,
    hold_stage: std.atomic.Value(u8) = .init(255),
    hold_claimed: std.atomic.Value(bool) = .init(false),
    hold_timeout: std.atomic.Value(bool) = .init(false),
    native_request: std.atomic.Value(i64) = .init(0),
    native_before: std.atomic.Value(i64) = .init(0),
    native_running: std.atomic.Value(i64) = .init(0),
    native_after: std.atomic.Value(i64) = .init(0),
    input_bytes: usize = 0,
    submitted: i64 = 0,
    input_copied: i64 = 0,
    enqueued: i64 = 0, // host writes under queue gate
    acquired: std.atomic.Value(i64) = .init(0),
    requested: i64 = 0, // main owner only
    request_recorded: bool = false, // also true in smoke, whose timestamps are zero
    request_stage: u8 = 0,
    queued: bool = false,
    stopped: std.atomic.Value(i64) = .init(0),
    published: std.atomic.Value(i64) = .init(0),
    stages: std.atomic.Value(u64) = .init(0),
    latest: std.atomic.Value(u8) = .init(0),
    pub fn hold(self: *@This(), point: Stage, token: *const std.atomic.Value(bool)) void {
        if (cancel_at != point or token.load(.acquire)) return;
        // One rendezvous per task. Native-running is the guarded entry, after
        // preflight: after release the entire bounded native call still runs.
        if (self.hold_claimed.swap(true, .acq_rel)) return;
        self.hold_stage.store(@intCast(@backingInt(point)), .release);
        const start = @import("../host_clock.zig").now() catch {
            self.hold_timeout.store(true, .release);
            return;
        };
        while (!token.load(.acquire)) {
            const at = @import("../host_clock.zig").now() catch break;
            if (at - start >= 5_000_000_000) break;
            std.atomic.spinLoopHint();
        }
        if (!token.load(.acquire)) self.hold_timeout.store(true, .release);
    }
    pub fn stage(self: *@This(), point: Stage) void {
        const mask = @as(u64, 1) << @intCast(@backingInt(point));
        const previous = self.stages.fetchOr(mask, .release);
        self.latest.store(@intCast(@backingInt(point)), .release);
        if (previous & mask == 0) memoryCheckpoint();
        switch (point) {
            .native_before => {
                if (self.native_request.load(.acquire) == 0) {
                    self.native_before.store(now(), .release);
                    self.native_running.store(0, .release);
                    self.native_after.store(0, .release);
                }
            },
            .native_running => self.native_running.store(now(), .release),
            .native_after => self.native_after.store(now(), .release),
            .runner_return => self.stopped.store(now(), .release),
            .published => self.published.store(now(), .release),
            else => {},
        }
    }
    pub fn seen(self: *const @This(), point: Stage) bool {
        return self.stages.load(.acquire) & (@as(u64, 1) << @intCast(@backingInt(point))) != 0;
    }
    // Called after physical handback, run.deinit, all task buffers and slot freed.
    // The separately owned public Snapshot is intentionally not a task reference.
    pub fn dump(self: *const @This(), id: i64) void {
        if (comptime diagnostics) {
            append(.{ .interval = .{ .metric = "worker_retirement_ns", .start = self.retirement_start, .end = self.retirement_end } });
            append(.{ .interval = .{ .metric = "worker_handback_ns", .start = self.retirement_end, .end = self.handback_end } });
        }
        append(.{ .task = .{ .storage = self.*, .id = id, .reclaimed = now() } });
        if (self.request_recorded) {
            std.debug.assert(pending_cancellations != 0);
            pending_cancellations -= 1;
        }
    }
    fn print(self: *const @This(), id: i64, reclaimed: i64) void {
        std.debug.print("ACCEPTANCE {{\"task\":{d},\"input_bytes\":{d},\"submitted\":{d},\"input_copied\":{d},\"enqueued\":{d},\"acquired\":{d},\"requested\":{d},\"stopped\":{d},\"published\":{d},\"reclaimed\":{d},\"request_stage\":{d},\"queued\":{},\"hold_stage\":{d},\"hold_timeout\":{},\"native_before\":{d},\"native_running\":{d},\"native_after\":{d},\"smoke\":{}}}\n", .{ id, self.input_bytes, self.submitted, self.input_copied, self.enqueued, self.acquired.load(.acquire), self.requested, self.stopped.load(.acquire), self.published.load(.acquire), reclaimed, self.request_stage, self.queued, self.hold_stage.load(.acquire), self.hold_timeout.load(.acquire), self.native_before.load(.acquire), self.native_running.load(.acquire), self.native_after.load(.acquire), smoke });
    }
} else struct {};
