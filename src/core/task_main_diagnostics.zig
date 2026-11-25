//! Main-thread-only fixed storage; no output until process shutdown.
const std = @import("std");
pub const enabled = @import("build_options").task_main_diagnostics;
const Stamp = struct { at: i64 = 0, cpu: i64 = -1 };
const Event = struct { name: []const u8, start: i64, end: i64, cpu_ns: i64 };
const windows = struct {
    extern "kernel32" fn GetCurrentThread() callconv(.winapi) ?*anyopaque;
    extern "kernel32" fn GetThreadTimes(?*anyopaque, *u64, *u64, *u64, *u64) callconv(.winapi) i32;
};
fn cpu() i64 {
    if (comptime !enabled or @import("builtin").os.tag != .windows) return -1;
    var created: u64 = 0;
    var exited: u64 = 0;
    var kernel: u64 = 0;
    var user: u64 = 0;
    if (windows.GetThreadTimes(windows.GetCurrentThread(), &created, &exited, &kernel, &user) == 0) return -1;
    return @intCast((kernel + user) * 100);
}
var events: [if (enabled) 262144 else 0]Event = undefined;
var count: usize = 0;
var lost: usize = 0;
pub inline fn begin() Stamp {
    if (comptime !enabled) return .{};
    const at = std.math.cast(i64, @import("../host_clock.zig").now() catch return .{}) orelse return .{};
    return .{ .at = at, .cpu = cpu() };
}
pub inline fn end(name: []const u8, start: Stamp) void {
    if (comptime !enabled) return;
    const finish = begin();
    // Keep every host span; retain the most recent records on overflow.
    events[count % events.len] = .{ .name = name, .start = start.at, .end = finish.at, .cpu_ns = if (start.cpu >= 0 and finish.cpu >= 0) finish.cpu - start.cpu else -1 };
    count += 1;
    if (count > events.len) lost += 1;
}
pub fn dump() void {
    if (comptime !enabled) return;
    const first = count - @min(count, events.len);
    for (first..count) |i| {
        const e = events[i % events.len];
        std.debug.print("MAIN-SPAN {{\"name\":\"{s}\",\"start\":{d},\"end\":{d},\"cpu_ns\":{d}}}\n", .{ e.name, e.start, e.end, e.cpu_ns });
    }
    std.debug.print("MAIN-SPAN {{\"lost\":{d}}}\n", .{lost});
}
