const std = @import("std");
const support = @import("support.zig");
const forth = @import("../forth.zig");
const map = @import("../core/memory_map.zig");
const registry = @import("../core/address_registry.zig");
const name = "Test/日本";
fn converted(context: ?*anyopaque, seconds: forth.Double, buffer: []u8) forth.RuntimeError!forth.ZonedTime {
    const o: *support.Output = @ptrCast(@alignCast(context.?));
    o.time = seconds;
    o.file_writes += 1;
    @memcpy(buffer[0..name.len], name);
    if (o.host_fails) {
        @memset(buffer, 'X');
        return error.HostFailed;
    }
    if (o.close_fails) return error.ResultOutOfRange;
    return .{ .local = .{ .second = 56, .minute = 34, .hour = 12, .day = 15, .month = 6, .year = 2024 }, .dst = true, .offset = 20700, .zone_length = name.len };
}
fn setup(o: *support.Output) !*forth.State {
    const m = try support.createMachine(o);
    m.writer.zoned_time_fn = converted;
    return m;
}

test "P05b datetime timezone has exact ten-cell order and dedicated borrowed UTF8 bytes" {
    var o = support.Output{};
    const m = try setup(&o);
    defer support.destroyMachine(m);
    const seconds = (@as(forth.Double, 1) << 80) + 123;
    try m.pushDouble(seconds);
    try m.executeBuiltin(.to_time_date_tz);
    try support.expectStack(m, &.{ 56, 34, 12, 15, 6, 2024, -1, 20700, map.timezone_buffer_address, name.len });
    try std.testing.expectEqual(seconds, o.time);
    try std.testing.expectEqualStrings(name, m.memory[@intCast(map.timezone_buffer_address)..][0..name.len]);
    m.data_depth = 0;
    try m.interpretLine("S\" HOME\" GETENV 2DROP");
    if (@import("build_options").files) {
        o.files[0].exists = true;
        try m.interpretLine("VARIABLE P P PATH= ~+ S\" a.txt\" P FILE>PATH 2DROP");
    }
    try std.testing.expectEqualStrings(name, m.memory[@intCast(map.timezone_buffer_address)..][0..name.len]);
}

test "P05b timezone failures retain input cells and previous name even after host writes" {
    var o = support.Output{};
    const m = try setup(&o);
    defer support.destroyMachine(m);
    try m.pushDouble(0);
    try m.executeBuiltin(.to_time_date_tz);
    m.data_depth = 0;
    var before: [map.timezone_buffer_size]u8 = undefined;
    @memcpy(&before, m.memory[@intCast(map.timezone_buffer_address)..][0..before.len]);
    try m.pushDouble(-1);
    o.host_fails = true;
    try std.testing.expectError(error.HostFailed, m.executeBuiltin(.to_time_date_tz));
    try support.expectStack(m, &.{ -1, -1 });
    try std.testing.expectEqualSlices(u8, &before, m.memory[@intCast(map.timezone_buffer_address)..][0..before.len]);
    o.host_fails = false;
    o.close_fails = true;
    try std.testing.expectError(error.ResultOutOfRange, m.executeBuiltin(.to_time_date_tz));
    try support.expectStack(m, &.{ -1, -1 });
    m.writer.zoned_time_fn = null;
    try std.testing.expectError(error.HostUnavailable, m.executeBuiltin(.to_time_date_tz));
    try support.expectStack(m, &.{ -1, -1 });
    try std.testing.expectEqualSlices(u8, &before, m.memory[@intCast(map.timezone_buffer_address)..][0..before.len]);
}

fn invalidDate(context: ?*anyopaque, seconds: forth.Double, buffer: []u8) forth.RuntimeError!forth.ZonedTime {
    var result = try converted(context, seconds, buffer);
    result.local.month = 13;
    return result;
}
fn invalidLength(context: ?*anyopaque, seconds: forth.Double, buffer: []u8) forth.RuntimeError!forth.ZonedTime {
    var result = try converted(context, seconds, buffer);
    result.zone_length = buffer.len + 1;
    return result;
}
test "P05b timezone preflights all output slots and rejects malformed callbacks atomically" {
    var o = support.Output{};
    const m = try setup(&o);
    defer support.destroyMachine(m);
    try m.push(7);
    try std.testing.expectError(error.StackUnderflow, m.executeBuiltin(.to_time_date_tz));
    try support.expectStack(m, &.{7});
    m.data_depth = m.data_stack.len - 7;
    m.data_stack[m.data_depth - 2] = 1;
    m.data_stack[m.data_depth - 1] = 0;
    try std.testing.expectError(error.StackOverflow, m.executeBuiltin(.to_time_date_tz));
    try std.testing.expectEqual(@as(usize, 0), o.file_writes);
    m.data_depth -= 1;
    m.data_stack[m.data_depth - 2] = 1;
    m.data_stack[m.data_depth - 1] = 0;
    try m.executeBuiltin(.to_time_date_tz);
    try std.testing.expectEqual(m.data_stack.len, m.data_depth);
    var before: [map.timezone_buffer_size]u8 = undefined;
    @memcpy(&before, m.memory[@intCast(map.timezone_buffer_address)..][0..before.len]);
    const Hook = *const fn (?*anyopaque, forth.Double, []u8) forth.RuntimeError!forth.ZonedTime;
    for ([_]Hook{ invalidDate, invalidLength }) |hook| {
        m.writer.zoned_time_fn = hook;
        m.data_depth = 0;
        try m.pushDouble(123);
        try std.testing.expectError(error.InvalidAddress, m.executeBuiltin(.to_time_date_tz));
        try support.expectStack(m, &.{ 123, 0 });
        try std.testing.expectEqualSlices(u8, &before, m.memory[@intCast(map.timezone_buffer_address)..][0..before.len]);
    }
}

fn empty(context: ?*anyopaque, seconds: forth.Double, buffer: []u8) forth.RuntimeError!forth.ZonedTime {
    var result = try converted(context, seconds, buffer);
    result.zone_length = 0;
    result.dst = false;
    result.offset = -18000;
    return result;
}
test "P05b timezone supports an empty name and notifies typed scratch writes" {
    var o = support.Output{};
    const m = try setup(&o);
    defer support.destroyMachine(m);
    try m.writeCell(map.timezone_buffer_address, 0);
    try registry.registerMemory(m, map.timezone_buffer_address);
    try m.pushDouble(0);
    try m.executeBuiltin(.to_time_date_tz);
    try std.testing.expectError(error.InvalidAddress, registry.validate(m));
    try m.writeCell(map.timezone_buffer_address, 0);
    try registry.validate(m);
    m.data_depth = 0;
    m.writer.zoned_time_fn = empty;
    try m.pushDouble(0);
    try m.executeBuiltin(.to_time_date_tz);
    try support.expectStack(m, &.{ 56, 34, 12, 15, 6, 2024, 0, -18000, map.timezone_buffer_address, 0 });
}

test "P05b timezone compiled calls and image restore need no file feature or heap" {
    var o = support.Output{};
    const m = try setup(&o);
    defer support.destroyMachine(m);
    m.writer.file_ops = null;
    try m.interpretLine(": ZONE >TIME&DATE&TZ ;");
    const image = try std.testing.allocator.alloc(u8, try m.encodedSize());
    defer std.testing.allocator.free(image);
    _ = try m.encodeImage(image);
    try m.restoreImage(image);
    _ = (try m.heapAllocate(@intCast(m.sizes.heapEnd() - m.heapTop() - 16))).?;
    const top = m.heapTop();
    try m.pushDouble(-1);
    try m.executeWord(m.lookup("ZONE").?);
    try support.expectStack(m, &.{ 56, 34, 12, 15, 6, 2024, -1, 20700, map.timezone_buffer_address, name.len });
    try std.testing.expectEqual(top, m.heapTop());
}
