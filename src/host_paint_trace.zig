//! Acceptance-only, bounded cross-thread drawing log. No clock or storage in normal builds.
const std = @import("std");
const acceptance = @import("core/task_acceptance.zig");
pub const enabled = acceptance.enabled;
const Event = struct { kind: []const u8, frame: u64, detail: u64, at: i64 };
var guard: std.atomic.Value(u8) = .init(0);
var events: [4096]Event = undefined;
var count: usize = 0;
var lost: usize = 0;
fn lock() void {
    while (guard.cmpxchgWeak(0, 1, .acquire, .monotonic) != null) std.atomic.spinLoopHint();
}
pub inline fn record(comptime kind: []const u8, frame: u64, detail: u64) void {
    if (comptime !enabled) return;
    recordAt(kind, frame, detail, acceptance.now());
}
fn recordAt(comptime kind: []const u8, frame: u64, detail: u64, at: i64) void {
    if (comptime !enabled) return;
    lock();
    defer guard.store(0, .release);
    if (count == events.len) {
        lost += 1;
        return;
    }
    events[count] = .{ .kind = kind, .frame = frame, .detail = detail, .at = at };
    count += 1;
}
// Owner thread only; backend threads never serialize or write to the terminal.
pub fn flush() void {
    if (comptime !enabled) return;
    var copy: [4096]Event = undefined;
    lock();
    const n = count;
    const missing = lost;
    @memcpy(copy[0..n], events[0..n]);
    count = 0;
    lost = 0;
    guard.store(0, .release);
    for (copy[0..n]) |e| std.debug.print("PAINTTRACE {{\"event\":\"{s}\",\"frame\":{d},\"detail\":{d},\"at\":{d},\"smoke\":{}}}\n", .{ e.kind, e.frame, e.detail, e.at, acceptance.smoke });
    if (missing != 0) std.debug.print("PAINTTRACE {{\"lost_events\":{d}}}\n", .{missing});
}

var line: [256]u8 = undefined;
var used: usize = 0;
pub const Marker = struct { input: bool, generation: u64, frame: u64, requested: u64 = 0 };
pub fn feed(bytes: []const u8) ?Marker {
    if (comptime !enabled) return null;
    var result: ?Marker = null;
    for (bytes) |byte| {
        if (byte == '\n') {
            const text = line[0..used];
            const is_input = std.mem.startsWith(u8, text, "NATIVE-INPUT generation=");
            if (is_input or std.mem.startsWith(u8, text, "NATIVE-DRAW generation=")) {
                var fields = std.mem.tokenizeAny(u8, text, "= \r");
                _ = fields.next();
                _ = fields.next();
                result = .{ .input = is_input, .generation = std.fmt.parseInt(u64, fields.next() orelse "0", 10) catch 0, .frame = 0 };
                if (!is_input) {
                    _ = fields.next();
                    result.?.frame = std.fmt.parseInt(u64, fields.next() orelse "0", 10) catch 0;
                    _ = fields.next();
                    result.?.requested = std.fmt.parseInt(u64, fields.next() orelse "0", 10) catch 0;
                }
            }
            used = 0;
        } else if (used < line.len) {
            line[used] = byte;
            used += 1;
        }
    }
    return result;
}

var pending_input: ?i64 = null;
pub fn input(key: i64) void {
    if (comptime !enabled) return;
    if (key == 110 or key == 97 or key == 98 or key == 102) {
        if (pending_input == null) pending_input = acceptance.now();
    }
}
pub fn recordMarker(marker: Marker) void {
    if (marker.input) {
        recordAt("input", marker.generation, 0, pending_input orelse 0);
        pending_input = null;
    } else {
        record("draw-generation", marker.generation, marker.frame);
        record("terminal", marker.requested, marker.frame);
    }
}

// Inspection exists only in test binaries; no public runtime instrumentation API.
pub const Test = if (@import("builtin").is_test) struct {
    pub fn reset() void {
        pending_input = null;
        count = 0;
        lost = 0;
    }
    pub fn pending() ?i64 {
        return pending_input;
    }
    pub fn lastAt() i64 {
        return events[count - 1].at;
    }
} else struct {};
