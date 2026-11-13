//! Base restoration, unsigned double output, parser state, and reproducible randoms.
const std = @import("std");
const support = @import("support.zig");
const map = @import("../core/memory_map.zig");
const enabled = @import("build_options").float;

test "P02c BASE EXECUTE restores base on return and exception and preserves results" {
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try machine.interpretLine(": READBASE BASE @ ; ' READBASE 16 BASE-EXECUTE BASE @");
    try support.expectStack(machine, &.{ 16, 10 });
    machine.data_depth = 0;
    try machine.interpretLine(": FAILBASE -99 THROW ;");
    try std.testing.expectError(error.Thrown, machine.interpretLine("' FAILBASE 16 BASE-EXECUTE"));
    try std.testing.expectEqual(@as(map.Cell, 10), machine.currentBase());
}

test "P02c DPL and CONVERT report decimal and input consumption positions" {
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try machine.interpretLine("S\" 1.25\" S>NUMBER? DROP 2DROP DPL @");
    try support.expectStack(machine, &.{2});
    machine.data_depth = 0;
    try machine.interpretLine("S\" 1.2.3\" S>NUMBER? DROP 2DROP DPL @");
    try support.expectStack(machine, &.{1});
    machine.data_depth = 0;
    try machine.interpretLine("0. S\" x123?\" DROP CONVERT DUP C@ SWAP DROP");
    try support.expectStack(machine, &.{ 123, 0, '?' });
    machine.data_depth = 0;
    try machine.interpretLine("0. S\" xZ\" DROP CONVERT C@");
    try support.expectStack(machine, &.{ 0, 0, 'Z' });
}

test "P02c explicit bases preserve BASE and print full unsigned doubles" {
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try machine.interpretLine("HEX -12 DEC. 12 5 DEC.R SPACE 12 H. 12 HEX. DECIMAL -1 -1 UD. -1 -1 2 UD.R");
    try std.testing.expectEqualStrings("-18    18 $12 $12 340282366920938463463374607431768211455 340282366920938463463374607431768211455", output.written());
    try std.testing.expectEqual(@as(map.Cell, 10), machine.currentBase());
}

test "P02c randoms accept all seeds reproduce streams and respect unsigned bounds" {
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    for ([_]map.Cell{ 0, 1, -1, std.math.minInt(map.Cell) }) |seed| {
        try machine.push(seed);
        try machine.interpretLine("SEED!");
        var values: [8]map.Cell = undefined;
        for (&values) |*value| {
            try machine.interpretLine("RND");
            value.* = try machine.pop();
        }
        try machine.push(seed);
        try machine.interpretLine("SEED!");
        for (values) |value| {
            try machine.interpretLine("RND");
            try std.testing.expectEqual(value, try machine.pop());
        }
        for ([_]u64{ 0, 1, 2, 100, @as(u64, 1) << 63, std.math.maxInt(u64) }) |bound| {
            for (0..32) |_| {
                try machine.push(@bitCast(bound));
                try machine.interpretLine("RANDOM");
                const value: u64 = @bitCast(try machine.pop());
                if (bound == 0) try std.testing.expectEqual(@as(u64, 0), value) else try std.testing.expect(value < bound);
            }
        }
    }
}

test "P02c decimal separators and compact outputs round trip exact binary64 values" {
    if (!enabled) return error.SkipZigTest;
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try machine.interpretLine("S\" 1,5\" 44 >FLOAT1 S\" 1.5\" 44 >FLOAT1 S\"    \" 44 >FLOAT1");
    try support.expectStack(machine, &.{ -1, 0, -1 });
    try std.testing.expectEqual(@as(f64, 0), try machine.fpop());
    try std.testing.expectEqual(@as(f64, 1.5), try machine.fpop());
    const values = [_]f64{ 0, -0.0, 0.1, 1, -123.25, 0x1p-1074, std.math.floatMax(f64), 0x1.0000000000001p0 };
    for (values) |value| {
        for ([_][]const u8{ "E.", "E.EXACT" }) |word| {
            output = .{};
            try machine.fpush(value);
            try machine.interpretLine(word);
            const parsed = @import("../core/number_io.zig").parseFloat(output.written(), false) orelse return error.TestExpectedEqual;
            try std.testing.expectEqual(@as(u64, @bitCast(value)), @as(u64, @bitCast(parsed)));
        }
    }
}

test "P02 definitions keep their builtin calls across dictionary restore and append" {
    try support.skipWithout(&.{.image});
    var output = support.Output{};
    const source = try support.createMachine(&output);
    defer support.destroyMachine(source);
    try source.interpretLine(": P02-DIV -7 3 /MODS ; : P02-SHIFT 1. 64 DLSHIFT ; : P02-RANDOM 123 SEED! 1 RANDOM ;");
    if (enabled) try source.interpretLine(": P02-FLOAT -1e 1.000000007450580596923828125e 0.999999992549419403076171875e F*+ ;");
    const image = try std.testing.allocator.alloc(u8, source.encodedSize());
    defer std.testing.allocator.free(image);
    _ = try source.encodeImage(image);
    const restored = try support.createMachine(&output);
    defer support.destroyMachine(restored);
    try restored.restoreImage(image);
    const target = try support.createMachine(&output);
    defer support.destroyMachine(target);
    try target.interpretLine("CREATE BEFORE 64 ALLOT");
    try target.appendImage(restored);
    for ([_]*@import("../forth.zig").State{ restored, target }) |machine| {
        try machine.interpretLine("P02-DIV P02-SHIFT P02-RANDOM");
        try support.expectStack(machine, &.{ -1, -2, 0, 1, 0 });
        if (enabled) {
            try machine.interpretLine("P02-FLOAT");
            try std.testing.expectEqual(@as(f64, -0x1p-54), try machine.fpop());
        }
    }
}

test "P02c precision output rounds before choosing compact layout" {
    if (!enabled) return error.SkipZigTest;
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try machine.interpretLine("999.9e 3 E.P SPACE 1234e 3 E.P SPACE 0.00001e 3 E.P");
    try std.testing.expectEqualStrings("1e3 1234e .00001e", output.written());
    try std.testing.expectError(error.ResultOutOfRange, machine.interpretLine("1e 0 E.P"));
}

test "P02 seed initialization uses the host clock with a zero fallback" {
    var output = support.Output{ .time = 123456789 };
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try std.testing.expectEqual(@as(u64, 123456789), machine.random_state);
    const storage = machine.storage();
    var writer = output.writer();
    writer.utime_fn = null;
    machine.init(writer, storage);
    try std.testing.expectEqual(@as(u64, 0), machine.random_state);
    output.host_fails = true;
    machine.init(output.writer(), storage);
    try std.testing.expectEqual(@as(u64, 0), machine.random_state);
}

test "P02 nested BASE EXECUTE restores each base through CATCH" {
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try machine.interpretLine(": INNER BASE @ -99 THROW ; : OUTER ['] INNER 2 BASE-EXECUTE ; : RUN ['] OUTER 16 BASE-EXECUTE ; ' RUN CATCH BASE @");
    try support.expectStack(machine, &.{ -99, 10 });
    machine.data_depth = 0;
    try machine.interpretLine(": CAUGHT ['] INNER CATCH BASE @ ; ' CAUGHT 16 BASE-EXECUTE BASE @");
    try support.expectStack(machine, &.{ -99, 16, 10 });
}

test "P02 large padded fields obey the step limit" {
    try support.skipWithout(&.{.debug});
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    machine.step_limit = 1;
    for ([_][]const u8{ "1 $4000000000000000 DEC.R", "1. $4000000000000000 UD.R" }) |source| {
        machine.data_depth = 0;
        machine.resetSteps();
        try std.testing.expectError(error.StepLimit, machine.interpretLine(source));
    }
}
