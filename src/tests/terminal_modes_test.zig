const std = @import("std");
const support = @import("support.zig");
const forth = @import("../forth.zig");
const map = @import("../core/memory_map.zig");
fn set(context: ?*anyopaque, mask: u8) forth.Cell {
    const output: *support.Output = @ptrCast(@alignCast(context.?));
    output.terminal_set_calls += 1;
    if (output.terminal_ior == 0) output.terminal_mask = mask;
    return output.terminal_ior;
}
fn get(context: ?*anyopaque) u8 {
    const output: *support.Output = @ptrCast(@alignCast(context.?));
    return output.terminal_mask;
}
fn inputError(context: ?*anyopaque) forth.RuntimeError!void {
    const output: *support.Output = @ptrCast(@alignCast(context.?));
    if (output.input_failure) |err| {
        output.input_failure = null;
        return err;
    }
}

test "terminal masks validate before host effects, share mouse intent and return ior" {
    try support.skipWithout(&.{.extension});
    var output: support.Output = .{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    machine.writer.terminal_mode_set_fn = set;
    machine.writer.terminal_mode_get_fn = get;
    try machine.interpretLine("REQUIRE-EXTENSION ALSO EXTENSION 9 TERM-MODE! TERM-MODE@");
    try support.expectStack(machine, &.{ 0, 9 });
    try std.testing.expect(machine.gfx_input.mouse_on);
    try machine.interpretLine("-1 TERM-MODE! 16 TERM-MODE!");
    try std.testing.expectEqual(@as(usize, 1), output.terminal_set_calls);
    try support.expectStack(machine, &.{ 0, 9, -24, -24 });
    output.terminal_ior = -265;
    try machine.interpretLine("0 TERM-MODE!");
    try std.testing.expect(machine.gfx_input.mouse_on);
    output.terminal_ior = 0;
    try machine.interpretLine("0 TERM-MODE!");
    try std.testing.expect(!machine.gfx_input.mouse_on);
    try std.testing.expectEqual(@as(u8, 0), output.terminal_mask);
}

test "terminal mode host absence and stack overflow have no side effects" {
    try support.skipWithout(&.{.extension});
    var output: support.Output = .{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try machine.interpretLine("REQUIRE-EXTENSION ALSO EXTENSION 1 TERM-MODE!");
    try support.expectStack(machine, &.{-21});
    try std.testing.expectError(error.HostUnavailable, machine.interpretLine("TERM-MODE@"));
    machine.writer.terminal_mode_get_fn = get;
    machine.data_depth = machine.data_stack.len;
    try std.testing.expectError(error.StackOverflow, machine.interpretLine("TERM-MODE@"));
    try std.testing.expectEqual(@as(usize, 0), output.terminal_set_calls);
}

test "COLS and ROWS share FORM values including capture and zero-size fallback" {
    try support.skipWithout(&.{.extension});
    var output: support.Output = .{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try machine.interpretLine("REQUIRE-EXTENSION ALSO EXTENSION ROWS COLS FORM");
    try support.expectStack(machine, &.{ 24, 80, 24, 80 });
    output.terminal_columns = 101;
    output.terminal_rows = 37;
    machine.data_depth = 0;
    try machine.interpretLine("ROWS COLS FORM");
    try support.expectStack(machine, &.{ 37, 101, 37, 101 });
    machine.data_depth = 0;
    var capture: @import("../core/macro_substitute.zig").Captured = .{};
    machine.capture_sink = &capture;
    defer machine.capture_sink = null;
    try machine.interpretLine("ROWS COLS FORM");
    try support.expectStack(machine, &.{ 1, std.math.maxInt(map.Cell), 1, std.math.maxInt(map.Cell) });
}

test "nullable input callbacks propagate a latched host failure or interrupt" {
    var output: support.Output = .{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    machine.writer.input_error_fn = inputError;
    output.input_failure = error.UserInterrupt;
    try std.testing.expectError(error.UserInterrupt, machine.interpretLine("KEY"));
    output.input_failure = error.HostFailed;
    try std.testing.expectError(error.HostFailed, machine.interpretLine("KEY?"));
    output.input_failure = error.HostFailed;
    try std.testing.expectError(error.HostFailed, machine.interpretLine("PAD 4 ACCEPT"));
}
