const std = @import("std");
const support = @import("support.zig");
const forth = @import("../forth.zig");
const map = @import("../core/memory_map.zig");

fn make(context: ?*anyopaque, name: []const u8, mode: forth.Cell) forth.Cell {
    const output: *support.Output = @ptrCast(@alignCast(context.?));
    output.slept = mode;
    output.file_writes += 1;
    if (name.len > output.command.len) return forth.errnoIor(36);
    @memcpy(output.command[0..name.len], name);
    output.command_len = name.len;
    support.Output.write(context, name);
    support.Output.write(context, "|");
    if (output.host_fails and output.file_writes == 2) return forth.errnoIor(13);
    if (std.mem.eql(u8, name, "existing") or std.mem.eql(u8, name, "existing/sub")) return forth.errnoIor(17);
    return 0;
}
const ops = blk: {
    var value = support.fake_file_ops;
    value.mkdir = make;
    break :blk value;
};
fn setup(output: *support.Output) !*forth.State {
    try support.skipWithout(&.{.files});
    const m = try support.createMachine(output);
    m.writer.file_ops = &ops;
    return m;
}

test "P05b mkdir parents attempts raw prefixes in order with the same native mode" {
    var output = support.Output{};
    const m = try setup(&output);
    defer support.destroyMachine(m);
    try m.interpretLine("S\" existing/sub/日本語\" 493 MKDIR-PARENTS");
    try support.expectStack(m, &.{0});
    try std.testing.expectEqualStrings("existing|existing/sub|existing/sub/日本語|", output.written());
    try std.testing.expectEqual(@as(forth.Cell, 493), output.slept);
    m.data_depth = 0;
    output.len = 0;
    output.file_writes = 0;
    try m.interpretLine("S\" /a//b/\" 511 MKDIR-PARENTS");
    try std.testing.expectEqualStrings("/a|/a/|/a//b|/a//b/|", output.written());
    try support.expectStack(m, &.{0});
    m.data_depth = 0;
    output.len = 0;
    try m.interpretLine("S\" a\\b\" 511 MKDIR-PARENTS");
    try std.testing.expectEqualStrings("a\\b|", output.written());
}

test "P05b mkdir reports final EEXIST and stops after a failed parent" {
    var output = support.Output{};
    const m = try setup(&output);
    defer support.destroyMachine(m);
    try m.interpretLine("S\" existing/sub\" 511 MKDIR-PARENTS");
    try support.expectStack(m, &.{forth.errnoIor(17)});
    try std.testing.expectEqualStrings("existing|existing/sub|", output.written());
    output.len = 0;
    output.file_writes = 0;
    output.host_fails = true;
    m.data_depth = 0;
    try m.interpretLine("S\" a/b/c/d\" 448 MKDIR-PARENTS");
    try support.expectStack(m, &.{forth.errnoIor(13)});
    try std.testing.expectEqualStrings("a|a/b|", output.written());
    try std.testing.expectEqual(@as(usize, 2), output.file_writes);
}

test "P05b mkdir expands homes per attempt and preserves source and OS dot semantics" {
    var output = support.Output{};
    const m = try setup(&output);
    defer support.destroyMachine(m);
    const program = "S\" ~/a/../b\" -1 MKDIR-PARENTS";
    try m.interpretLine(program);
    try support.expectStack(m, &.{0});
    try std.testing.expectEqualStrings("/home/lemon|/home/lemon/a|/home/lemon/a/..|/home/lemon/a/../b|", output.written());
    try std.testing.expectEqualStrings(program, m.memory[@intCast(map.tib_address)..][0..program.len]);
    try std.testing.expectEqual(@as(forth.Cell, -1), output.slept);
    m.data_depth = 0;
    output.len = 0;
    try m.interpretLine("S\" ~+/leaf\" 511 =MKDIR");
    try support.expectStack(m, &.{0});
    try std.testing.expectEqualStrings("leaf|", output.written());
}

test "P05b mkdir preflights hooks ranges NUL and total length before creation" {
    var output = support.Output{};
    const m = try setup(&output);
    defer support.destroyMachine(m);
    inline for (.{ .equals_mkdir, .mkdir_parents }) |word| {
        m.data_depth = 0;
        try m.push(0);
        try m.push(0);
        try std.testing.expectError(error.StackUnderflow, m.executeBuiltin(word));
        try support.expectStack(m, &.{ 0, 0 });
        m.data_depth = 0;
        try m.push(@intCast(m.memory.len));
        try m.push(1);
        try m.push(511);
        try std.testing.expectError(error.InvalidAddress, m.executeBuiltin(word));
        try support.expectStack(m, &.{ @intCast(m.memory.len), 1, 511 });
        m.data_depth = 0;
        try m.push(0);
        try m.push(0);
        try m.push(511);
        m.writer.file_ops = &support.fake_file_ops;
        try std.testing.expectError(error.FileUnavailable, m.executeBuiltin(word));
        try support.expectStack(m, &.{ 0, 0, 511 });
        m.writer.file_ops = &ops;
    }
    m.data_depth = 0;
    try m.interpretLine("S\" a/X/b\" 2DUP DROP 2 + 0 SWAP C! 511 MKDIR-PARENTS");
    try support.expectStack(m, &.{forth.errnoIor(map.errno_invalid)});
    m.data_depth = 0;
    const long = (try m.heapAllocate(1025)).?;
    @memset(m.memory[@intCast(long)..][0..1025], 'x');
    m.memory[@intCast(long + 1)] = '/';
    try m.push(long);
    try m.push(1025);
    try m.push(511);
    try std.testing.expectError(error.StringTooLong, m.executeBuiltin(.mkdir_parents));
    try support.expectStack(m, &.{ long, 1025, 511 });
    try std.testing.expectEqual(@as(usize, 0), output.file_writes);
}

test "P05b mkdir needs no spare stack or heap and checks budget between attempts" {
    var output = support.Output{};
    const m = try setup(&output);
    defer support.destroyMachine(m);
    try m.interpretLine(": MAKE MKDIR-PARENTS ; S\" a/b\" 493");
    _ = (try m.heapAllocate(@intCast(m.sizes.heapEnd() - m.heapTop() - 16))).?;
    const top = m.heapTop();
    try m.executeWord(m.lookup("MAKE").?);
    try support.expectStack(m, &.{0});
    try std.testing.expectEqual(top, m.heapTop());
    m.data_depth = m.data_stack.len;
    m.data_stack[m.data_depth - 3] = @intCast(m.memory.len);
    m.data_stack[m.data_depth - 2] = 0;
    m.data_stack[m.data_depth - 1] = 511;
    try m.executeBuiltin(.equals_mkdir);
    try std.testing.expectEqual(m.data_stack.len - 2, m.data_depth);
    if (@import("build_options").debug) {
        @memcpy(m.memory[@intCast(map.pad_address)..][0..5], "a/b/c");
        m.data_depth = 0;
        try m.push(map.pad_address);
        try m.push(5);
        try m.push(493);
        output.len = 0;
        output.file_writes = 0;
        m.step_limit = 1;
        m.steps_left = 1;
        try std.testing.expectError(error.StepLimit, m.executeBuiltin(.mkdir_parents));
        try support.expectStack(m, &.{ map.pad_address, 5, 493 });
        try std.testing.expectEqualStrings("a|", output.written());
    }
}
