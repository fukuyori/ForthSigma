const std = @import("std");
const support = @import("support.zig");
const forth = @import("../forth.zig");
fn output(context: ?*anyopaque) *support.Output {
    return @ptrCast(@alignCast(context.?));
}
fn nano(context: ?*anyopaque) forth.RuntimeError!forth.Double {
    const o = output(context);
    o.file_writes += 1;
    if (o.host_fails) return error.HostFailed;
    return (@as(forth.Double, 1) << 70) + 123456789;
}
fn cpu(context: ?*anyopaque) forth.RuntimeError!forth.CpuTimes {
    const o = output(context);
    o.file_writes += 1;
    if (o.host_fails) return error.HostFailed;
    return .{ .user = (@as(forth.Double, 1) << 80) + 99, .system = (@as(forth.Double, 1) << 96) + 7 };
}
fn negative(_: ?*anyopaque) forth.RuntimeError!forth.Double {
    return -1;
}
fn setup(o: *support.Output) !*forth.State {
    const m = try support.createMachine(o);
    m.writer.ntime_fn = nano;
    m.writer.cputime_fn = cpu;
    return m;
}

test "P05b clocks keep 128-bit low-high cells and process user-system order" {
    var o = support.Output{};
    const m = try setup(&o);
    defer support.destroyMachine(m);
    try m.interpretLine(": CLOCKS NTIME CPUTIME ; CLOCKS");
    try support.expectStack(m, &.{ 123456789, 64, 99, 65536, 7, 4294967296 });
    try std.testing.expectEqual(@as(usize, 2), o.file_writes);
    m.data_depth = 0;
    m.writer.ntime_fn = negative;
    try m.interpretLine("NTIME");
    try support.expectStack(m, &.{ -1, -1 });
}

test "P05b clocks preflight all stack room before querying the host" {
    var o = support.Output{};
    const m = try setup(&o);
    defer support.destroyMachine(m);
    inline for (.{ .ntime, .cputime }) |word| {
        const room: usize = if (word == .ntime) 2 else 4;
        m.data_depth = m.data_stack.len - room + 1;
        m.data_stack[m.data_depth - 1] = 123;
        try std.testing.expectError(error.StackOverflow, m.executeBuiltin(word));
        try std.testing.expectEqual(@as(usize, 0), o.file_writes);
        try std.testing.expectEqual(@as(forth.Cell, 123), try m.peek(0));
        try std.testing.expectEqual(m.data_stack.len - room + 1, m.data_depth);
        m.data_depth -= 1;
        try m.executeBuiltin(word);
        try std.testing.expectEqual(m.data_stack.len, m.data_depth);
        o.file_writes = 0;
    }
}

test "P05b clocks report missing and failed hosts without changing existing operands" {
    var o = support.Output{};
    const m = try setup(&o);
    defer support.destroyMachine(m);
    try m.push(42);
    m.writer.ntime_fn = null;
    m.writer.cputime_fn = null;
    try std.testing.expectError(error.HostUnavailable, m.executeBuiltin(.ntime));
    try std.testing.expectError(error.HostUnavailable, m.executeBuiltin(.cputime));
    try support.expectStack(m, &.{42});
    m.writer.ntime_fn = nano;
    m.writer.cputime_fn = cpu;
    o.host_fails = true;
    try std.testing.expectError(error.HostFailed, m.executeBuiltin(.ntime));
    try std.testing.expectError(error.HostFailed, m.executeBuiltin(.cputime));
    try support.expectStack(m, &.{42});
}

test "P05b clocks need neither file features nor free heap and retain hooks through image restore" {
    var o = support.Output{};
    const m = try setup(&o);
    defer support.destroyMachine(m);
    m.writer.file_ops = null;
    try m.interpretLine(": CPU CPUTIME ;");
    const image = try std.testing.allocator.alloc(u8, try m.encodedSize());
    defer std.testing.allocator.free(image);
    _ = try m.encodeImage(image);
    try m.restoreImage(image);
    _ = (try m.heapAllocate(@intCast(m.sizes.heapEnd() - m.heapTop() - 16))).?;
    const top = m.heapTop();
    try m.interpretLine("NTIME CPU");
    try support.expectStack(m, &.{ 123456789, 64, 99, 65536, 7, 4294967296 });
    try std.testing.expectEqual(top, m.heapTop());
}
