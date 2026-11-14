const std = @import("std");
const support = @import("support.zig");

test "P06a owned capture is independent FREE-able output including empty output" {
    var output = support.Output{};
    const m = try support.createMachine(&output);
    defer support.destroyMachine(m);
    try m.interpretLine(": OUT S\" ABC\" TYPE ; ' OUT >STRING-EXECUTE OVER >R S\" ABC\" COMPARE R> FREE");
    try support.expectStack(m, &.{ 0, 0 });
    m.data_depth = 0;
    try m.interpretLine(": EMPTY ; ' EMPTY >STRING-EXECUTE SWAP FREE");
    try support.expectStack(m, &.{ 0, 0 });
    try std.testing.expectEqualStrings("", output.written());
}

test "P06a nested capture and TMP restore their enclosing output destinations" {
    var output = support.Output{};
    const m = try support.createMachine(&output);
    defer support.destroyMachine(m);
    try m.interpretLine(": INNER S\" inner\" TYPE ; : OUT S\" a\" TYPE ['] INNER >STRING-EXECUTE OVER >R TYPE R> FREE THROW S\" b\" TYPE ; ' OUT >STRING-EXECUTE OVER >R TYPE R> FREE THROW");
    try std.testing.expectEqualStrings("ainnerb", output.written());
    output.len = 0;
    try m.interpretLine("' OUT $TMP TYPE ' INNER >STRING-EXECUTE OVER >R TYPE R> FREE THROW");
    try std.testing.expectEqualStrings("ainnerbinner", output.written());
}

test "P06a callback THROW restores capture and releases private allocations" {
    var output = support.Output{};
    const m = try support.createMachine(&output);
    defer support.destroyMachine(m);
    try m.interpretLine(": BAD S\" hidden\" TYPE -123 THROW ; : RUN ['] BAD >STRING-EXECUTE ;");
    const top = m.heapTop();
    try m.interpretLine("' RUN CATCH");
    try support.expectStack(m, &.{-123});
    try std.testing.expectEqual(top, m.heapTop());
    try std.testing.expect(m.capture_sink == null and m.capture_target == null);
    try m.interpretLine("S\" visible\" TYPE");
    try std.testing.expectEqualStrings("visible", output.written());
}

test "P06a capture rejects invalid tokens and full stack before callback" {
    var output = support.Output{};
    const m = try support.createMachine(&output);
    defer support.destroyMachine(m);
    try m.push(-1);
    try std.testing.expectError(error.InvalidExecutionToken, m.executeBuiltin(.to_string_execute));
    m.data_depth = 0;
    try m.interpretLine(": OUT 65 EMIT ;");
    m.data_depth = m.data_stack.len;
    m.data_stack[m.data_depth - 1] = m.lookup("OUT").?;
    try std.testing.expectError(error.StackOverflow, m.executeBuiltin(.to_string_execute));
    try std.testing.expectEqualStrings("", output.written());
}

test "P06a failed allocation and callback result overflow release capture and restore output" {
    var output = support.Output{};
    const m = try support.createMachine(&output);
    defer support.destroyMachine(m);
    try m.interpretLine(": OUT S\" data\" TYPE ; : CAPTURE-FILL 1 2 ;");
    m.data_depth = m.data_stack.len - 1;
    m.data_stack[m.data_depth - 1] = m.lookup("CAPTURE-FILL").?;
    try std.testing.expectError(error.StackOverflow, m.executeBuiltin(.to_string_execute));
    try std.testing.expect(m.capture_sink == null);
    m.data_depth = 0;
    _ = (try m.heapAllocate(@intCast(m.sizes.heapEnd() - m.heapTop() - 16))).?;
    const top = m.heapTop();
    try m.push(m.lookup("OUT").?);
    try std.testing.expectError(error.Thrown, m.executeBuiltin(.to_string_execute));
    try std.testing.expectEqual(top, m.heapTop());
    try std.testing.expect(m.capture_sink == null and m.capture_target == null);
    try std.testing.expectEqualStrings("", output.written());
}
