const std = @import("std");
const support = @import("support.zig");
const forth = @import("../forth.zig");
const max_duration = @import("../core/nanosecond_wait.zig").max_duration;
fn sleep(context: ?*anyopaque, duration: forth.Double) forth.RuntimeError!void {
    const o: *support.Output = @ptrCast(@alignCast(context.?));
    o.file_writes += 1;
    o.time = duration;
    if (o.host_fails) return error.HostFailed;
}
fn interrupt(_: ?*anyopaque, _: forth.Double) forth.RuntimeError!void {
    return error.UserInterrupt;
}
fn setup(o: *support.Output) !*forth.State {
    const m = try support.createMachine(o);
    m.writer.sleep_ns_fn = sleep;
    o.time = 0;
    return m;
}

test "P05b NS consumes nonpositive double cells without querying a host" {
    var o = support.Output{};
    const m = try setup(&o);
    defer support.destroyMachine(m);
    m.writer.sleep_ns_fn = null;
    for ([_]forth.Double{ 0, -1, std.math.minInt(forth.Double) }) |duration| {
        try m.pushDouble(duration);
        try m.executeBuiltin(.ns);
        try support.expectStack(m, &.{});
    }
    try std.testing.expectEqual(@as(usize, 0), o.file_writes);
}

test "P05b NS transports full double values and validates the signed seconds bound" {
    var o = support.Output{};
    const m = try setup(&o);
    defer support.destroyMachine(m);
    for ([_]forth.Double{ 1, (@as(forth.Double, 1) << 64) + 123, max_duration }) |duration| {
        try m.pushDouble(duration);
        try m.executeBuiltin(.ns);
        try support.expectStack(m, &.{});
        try std.testing.expectEqual(duration, o.time);
    }
    try m.pushDouble(max_duration + 1);
    try std.testing.expectError(error.ResultOutOfRange, m.executeBuiltin(.ns));
    try std.testing.expectEqual(@as(usize, 3), o.file_writes);
    try std.testing.expectEqual(@as(usize, 2), m.data_depth);
}

test "P05b NS errors preserve operands and CATCH sees UserInterrupt" {
    var o = support.Output{};
    const m = try setup(&o);
    defer support.destroyMachine(m);
    try m.push(7);
    try std.testing.expectError(error.StackUnderflow, m.executeBuiltin(.ns));
    try support.expectStack(m, &.{7});
    m.data_depth = 0;
    try m.pushDouble(1);
    m.writer.sleep_ns_fn = null;
    try std.testing.expectError(error.HostUnavailable, m.executeBuiltin(.ns));
    try support.expectStack(m, &.{ 1, 0 });
    m.writer.sleep_ns_fn = sleep;
    o.host_fails = true;
    try std.testing.expectError(error.HostFailed, m.executeBuiltin(.ns));
    try support.expectStack(m, &.{ 1, 0 });
    m.writer.sleep_ns_fn = interrupt;
    try std.testing.expectError(error.UserInterrupt, m.executeBuiltin(.ns));
    try support.expectStack(m, &.{ 1, 0 });
    m.data_depth = 0;
    try m.interpretLine(": WAIT 1. NS ; ' WAIT CATCH");
    try support.expectStack(m, &.{-28});
}

test "P05b NS needs no spare stack file feature or VM heap and keeps destination hooks" {
    var o = support.Output{};
    const m = try setup(&o);
    defer support.destroyMachine(m);
    m.writer.file_ops = null;
    try m.interpretLine(": WAIT NS ;");
    const image = try std.testing.allocator.alloc(u8, try m.encodedSize());
    defer std.testing.allocator.free(image);
    _ = try m.encodeImage(image);
    try m.restoreImage(image);
    _ = (try m.heapAllocate(@intCast(m.sizes.heapEnd() - m.heapTop() - 16))).?;
    const top = m.heapTop();
    m.data_depth = m.data_stack.len;
    m.data_stack[m.data_depth - 2] = 1000;
    m.data_stack[m.data_depth - 1] = 0;
    try m.executeBuiltin(.ns);
    try std.testing.expectEqual(m.data_stack.len - 2, m.data_depth);
    m.data_depth = 0;
    try m.pushDouble(1001);
    try m.executeWord(m.lookup("WAIT").?);
    try support.expectStack(m, &.{});
    try std.testing.expectEqual(@as(forth.Double, 1001), o.time);
    try std.testing.expectEqual(top, m.heapTop());
}
