//! Floating extensions: IEEE values, fused rounding and byte-strided vectors.
const std = @import("std");
const support = @import("support.zig");
const enabled = @import("build_options").float;

test "P02b IEEE constants reciprocal sign copying and stack access" {
    if (!enabled) return error.SkipZigTest;
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try machine.interpretLine("INF INFINITY -INF -INFINITY NAN");
    try std.testing.expect(std.math.isNan(try machine.fpop()));
    try std.testing.expectEqual(-std.math.inf(f64), try machine.fpop());
    try std.testing.expectEqual(-std.math.inf(f64), try machine.fpop());
    try std.testing.expectEqual(std.math.inf(f64), try machine.fpop());
    try std.testing.expectEqual(std.math.inf(f64), try machine.fpop());
    try machine.interpretLine("-0e 1/F 0e -0e FCOPYSIGN");
    try std.testing.expectEqual(@as(u64, 1) << 63, @as(u64, @bitCast(try machine.fpop())));
    try std.testing.expectEqual(-std.math.inf(f64), try machine.fpop());
    try machine.interpretLine(": P02B FTHIRD FFOURTH ; 1e 2e 3e P02B");
    try std.testing.expectEqual(@as(f64, 1), try machine.fpop());
    try std.testing.expectEqual(@as(f64, 1), try machine.fpop());
    try std.testing.expectEqual(@as(f64, 3), try machine.fpop());
    machine.float_depth = 0;
    try machine.interpretLine("-0e F2* F2/");
    try std.testing.expectEqual(@as(u64, 1) << 63, @as(u64, @bitCast(try machine.fpop())));
}

test "P02b F star plus is fused and approximate comparison is strict" {
    if (!enabled) return error.SkipZigTest;
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    // (1+2^-27)*(1-2^-27)-1: a separate multiply rounds away the residual.
    try machine.fpush(-1);
    try machine.fpush(1.0 + 0x1p-27);
    try machine.fpush(1.0 - 0x1p-27);
    try machine.interpretLine("F*+");
    try std.testing.expectEqual(@as(f64, -0x1p-54), try machine.fpop());
    try machine.interpretLine("1e -1e 2e F~REL 1e 2e 1e F~ABS 0e -0e 0e F~ABS NAN NAN 1e F~ABS");
    try support.expectStack(machine, &.{ -1, 0, 0, 0 });
}

test "P02b vectors support byte strides negative strides aliasing and empty counts" {
    if (!enabled) return error.SkipZigTest;
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try machine.interpretLine("CREATE X 1e F, 2e F, 3e F, CREATE Y 4e F, 5e F, 6e F,");
    try machine.interpretLine("X 8 Y 8 3 V*");
    try std.testing.expectEqual(@as(f64, 32), try machine.fpop());
    try machine.interpretLine("X 16 + -8 Y 8 3 V*");
    try std.testing.expectEqual(@as(f64, 28), try machine.fpop());
    try machine.interpretLine("2e X 8 Y 8 3 FAXPY Y F@ Y 8 + F@ Y 16 + F@");
    try std.testing.expectEqual(@as(f64, 12), try machine.fpop());
    try std.testing.expectEqual(@as(f64, 9), try machine.fpop());
    try std.testing.expectEqual(@as(f64, 6), try machine.fpop());
    try machine.interpretLine("2e X 0 X 0 2 FAXPY X F@");
    try std.testing.expectEqual(@as(f64, 9), try machine.fpop());
    try machine.interpretLine("-1 -1 -1 -1 0 V* 1e -1 -1 -1 -1 0 FAXPY");
    try std.testing.expectEqual(@as(f64, 0), try machine.fpop());
}

test "P02b vector range failure precedes writes and handles stride arithmetic overflow" {
    if (!enabled) return error.SkipZigTest;
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try machine.interpretLine("CREATE X 1e F, 2e F, CREATE Y 9e F, 9e F,");
    try std.testing.expectError(error.InvalidAddress, machine.interpretLine("2e X 8 Y -10000000 2 FAXPY"));
    machine.data_depth = 0;
    machine.float_depth = 0;
    try machine.interpretLine("Y F@");
    try std.testing.expectEqual(@as(f64, 9), try machine.fpop());
    try std.testing.expectError(error.InvalidAddress, machine.interpretLine("X $7FFFFFFFFFFFFFFF Y 8 -1 V*"));
    machine.data_depth = 0;
    for ([_][]const u8{ "FTHIRD", "FFOURTH", "F*+", "F~REL" }) |word| {
        machine.float_depth = 0;
        try std.testing.expectError(error.FloatStackUnderflow, machine.interpretLine(word));
    }
}
