const std = @import("std");
const support = @import("support.zig");
const forth = @import("../forth.zig");
const map = @import("../core/memory_map.zig");
const registry = @import("../core/address_registry.zig");
fn output(context: ?*anyopaque) *support.Output {
    return @ptrCast(@alignCast(context.?));
}
fn get(context: ?*anyopaque, buffer: []u8) forth.FileResult {
    const o = output(context);
    if (o.host_fails) return .{ .ior = forth.errnoIor(5) };
    if (buffer.len <= o.command_len) return .{ .ior = forth.errnoIor(34) };
    @memcpy(buffer[0..o.command_len], o.command[0..o.command_len]);
    buffer[o.command_len] = 0;
    return .{ .value = @intCast(o.command_len) };
}
fn set(context: ?*anyopaque, name: []const u8) forth.Cell {
    const o = output(context);
    if (o.host_fails) return forth.errnoIor(13);
    if (name.len > o.command.len) return forth.errnoIor(36);
    @memcpy(o.command[0..name.len], name);
    o.command_len = name.len;
    return 0;
}
const ops = blk: {
    var value = support.fake_file_ops;
    value.get_dir = get;
    value.set_dir = set;
    break :blk value;
};
fn setup(o: *support.Output) !*forth.State {
    try support.skipWithout(&.{.files});
    const m = try support.createMachine(o);
    m.writer.file_ops = &ops;
    @memcpy(o.command[0..5], "/work");
    o.command_len = 5;
    return m;
}

test "P05b cwd requires terminator capacity and returns zero zero on failure" {
    var o = support.Output{};
    const m = try setup(&o);
    defer support.destroyMachine(m);
    for ([_]usize{ 0, 1, 5, 6, 32 }) |length| {
        m.data_depth = 0;
        @memset(m.memory[@intCast(map.pad_address)..][0..32], 'X');
        try m.push(map.pad_address);
        try m.push(@intCast(length));
        try m.executeBuiltin(.get_dir);
        if (length > 5) {
            try support.expectStack(m, &.{ map.pad_address, 5 });
            try std.testing.expectEqualStrings("/work\x00", m.memory[@intCast(map.pad_address)..][0..6]);
            try std.testing.expectEqual(@as(u8, 'X'), m.memory[@intCast(map.pad_address + 6)]);
        } else {
            try support.expectStack(m, &.{ 0, 0 });
            try std.testing.expectEqual(@as(u8, 'X'), m.memory[@intCast(map.pad_address)]);
        }
    }
    m.data_depth = 0;
    o.host_fails = true;
    try m.interpretLine("PAD 32 GET-DIR");
    try support.expectStack(m, &.{ 0, 0 });
}

test "P05b set directory expands homes without source-relative normalization" {
    var o = support.Output{};
    const m = try setup(&o);
    defer support.destroyMachine(m);
    for ([_]struct { source: []const u8, result: []const u8 }{
        .{ .source = "S\" 日本語 dir\" SET-DIR", .result = "日本語 dir" },
        .{ .source = "S\" ./relative\" SET-DIR", .result = "./relative" },
        .{ .source = "S\" ~/dir\" SET-DIR", .result = "/home/lemon/dir" },
        .{ .source = "S\" ~+/dir\" SET-DIR", .result = "dir" },
        .{ .source = "S\" ~unknown/dir\" SET-DIR", .result = "~unknown/dir" },
    }) |case| {
        m.data_depth = 0;
        try m.interpretLine(case.source);
        try support.expectStack(m, &.{0});
        try std.testing.expectEqualStrings(case.result, o.command[0..o.command_len]);
    }
    o.host_fails = true;
    m.data_depth = 0;
    try m.interpretLine("S\" missing\" SET-DIR");
    try support.expectStack(m, &.{forth.errnoIor(13)});
    try std.testing.expectEqualStrings("~unknown/dir", o.command[0..o.command_len]);
}

test "P05b cwd validates operands hooks and NUL without host side effects" {
    var o = support.Output{};
    const m = try setup(&o);
    defer support.destroyMachine(m);
    inline for (.{ .get_dir, .set_dir }) |word| {
        m.data_depth = 0;
        try m.push(0);
        try std.testing.expectError(error.StackUnderflow, m.executeBuiltin(word));
        try support.expectStack(m, &.{0});
        m.data_depth = 0;
        try m.push(@intCast(m.memory.len));
        try m.push(1);
        try std.testing.expectError(error.InvalidAddress, m.executeBuiltin(word));
        try support.expectStack(m, &.{ @intCast(m.memory.len), 1 });
        m.data_depth = 0;
        try m.push(0);
        try m.push(-1);
        try std.testing.expectError(error.InvalidAddress, m.executeBuiltin(word));
        m.writer.file_ops = &support.fake_file_ops;
        m.data_depth = 0;
        try m.push(0);
        try m.push(0);
        try std.testing.expectError(error.FileUnavailable, m.executeBuiltin(word));
        try support.expectStack(m, &.{ 0, 0 });
        m.writer.file_ops = &ops;
    }
    m.data_depth = 0;
    try m.interpretLine("S\" badXname\" 2DUP DROP 3 + 0 SWAP C! SET-DIR");
    try support.expectStack(m, &.{forth.errnoIor(map.errno_invalid)});
    try std.testing.expectEqualStrings("/work", o.command[0..o.command_len]);
    m.data_depth = 0;
    const long = (try m.heapAllocate(1025)).?;
    @memset(m.memory[@intCast(long)..][0..1025], 'x');
    try m.push(long);
    try m.push(1025);
    try std.testing.expectError(error.StringTooLong, m.executeBuiltin(.set_dir));
    try support.expectStack(m, &.{ long, 1025 });
    try std.testing.expectEqualStrings("/work", o.command[0..o.command_len]);
}

test "P05b cwd writes invalidate typed addresses and need no spare stack or heap" {
    var o = support.Output{};
    const m = try setup(&o);
    defer support.destroyMachine(m);
    try m.interpretLine("CREATE P 0 A, : CWD GET-DIR ;");
    const owner = m.words[m.lookup("P").?].value;
    try std.testing.expect(m.addresses.count > 0);
    m.data_depth = m.data_stack.len;
    m.data_stack[m.data_depth - 2] = owner;
    m.data_stack[m.data_depth - 1] = 8;
    try m.executeBuiltin(.get_dir);
    try std.testing.expectEqual(m.data_stack.len, m.data_depth);
    try std.testing.expectEqual(@as(map.Cell, 5), try m.peek(0));
    try std.testing.expectError(error.InvalidAddress, registry.validate(m));
    try m.writeCell(owner, 0);
    try registry.validate(m);
    m.data_depth = 0;
    try m.interpretLine("S\" ./new\"");
    _ = (try m.heapAllocate(@intCast(m.sizes.heapEnd() - m.heapTop() - 16))).?;
    const top = m.heapTop();
    try m.executeBuiltin(.set_dir);
    try support.expectStack(m, &.{0});
    m.data_depth = 0;
    try m.push(map.pad_address);
    try m.push(32);
    try m.executeWord(m.lookup("CWD").?);
    try support.expectStack(m, &.{ map.pad_address, 5 });
    try std.testing.expectEqual(top, m.heapTop());
    try std.testing.expectEqualStrings("./new\x00", m.memory[@intCast(map.pad_address)..][0..6]);
}

fn overreport(_: ?*anyopaque, _: []u8) forth.FileResult {
    return .{ .value = 100 };
}
fn unterminated(_: ?*anyopaque, buffer: []u8) forth.FileResult {
    @memset(buffer, 'X');
    return .{ .value = 1 };
}
test "P05b cwd rejects malformed host lengths and missing terminators" {
    var o = support.Output{};
    const m = try setup(&o);
    defer support.destroyMachine(m);
    var bad = ops;
    for ([_]*const fn (?*anyopaque, []u8) forth.FileResult{ overreport, unterminated }) |get_fn| {
        bad.get_dir = get_fn;
        m.writer.file_ops = &bad;
        m.data_depth = 0;
        try m.push(map.pad_address);
        try m.push(16);
        try std.testing.expectError(error.InvalidAddress, m.executeBuiltin(.get_dir));
        try support.expectStack(m, &.{ map.pad_address, 16 });
    }
}
