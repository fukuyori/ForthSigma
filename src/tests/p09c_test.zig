const std = @import("std");
const support = @import("support.zig");
const defs = @import("../core/defs.zig");
const map = @import("../core/memory_map.zig");

test "P09c RPICK and second fetch use only user cells and keep them in place" {
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try m.interpretLine(": T 11 >R 22 >R 33 >R 0 RPICK 1 RPICK 2 RPICK R'@ R> R> R> ; T");
    try support.expectStack(m, &.{ 33, 22, 11, 22, 33, 22, 11 });
    try std.testing.expectEqual(@as(usize, 0), m.return_depth);
    m.data_depth = 0;
    try m.interpretLine("99 >R");
    try std.testing.expectError(error.ReturnStackUnderflow, m.interpretLine("1 RPICK"));
    try support.expectStack(m, &.{1});
    try std.testing.expectEqual(@as(usize, 1), m.return_depth);
    m.data_depth = 0;
    try std.testing.expectError(error.ReturnStackUnderflow, m.interpretLine("-1 RPICK"));
    try support.expectStack(m, &.{-1});
    try std.testing.expectError(error.ReturnStackUnderflow, m.executeBuiltin(.r_second_fetch));
}

test "P09c float return moves preserve zero infinity NaN and every payload bit" {
    try support.skipWithoutFloat();
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    for ([_]u64{ 0, 0x8000000000000000, 0x7ff0000000000000, 0xfff0000000000000, 0x7ff8000012345678, 1, 0x3ff4000000000000 }) |bits| {
        try m.fpush(@bitCast(bits));
        try m.executeBuiltin(.f_to_r);
        try std.testing.expectEqual(bits, @as(u64, @bitCast(m.return_stack[0])));
        try m.executeBuiltin(.f_r_fetch);
        try std.testing.expectEqual(bits, @as(u64, @bitCast(try m.fpop())));
        try m.executeBuiltin(.f_r_from);
        try std.testing.expectEqual(bits, @as(u64, @bitCast(try m.fpop())));
        try std.testing.expectEqual(@as(usize, 0), m.return_depth);
    }
}

test "P09c float transfer failures leave both stacks intact" {
    try support.skipWithoutFloat();
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try std.testing.expectError(error.FloatStackUnderflow, m.executeBuiltin(.f_to_r));
    try std.testing.expectError(error.ReturnStackUnderflow, m.executeBuiltin(.f_r_from));
    try m.fpush(1.25);
    m.return_depth = m.return_stack.len;
    try std.testing.expectError(error.ReturnStackOverflow, m.executeBuiltin(.f_to_r));
    try std.testing.expectEqual(@as(usize, 1), m.float_depth);
    m.return_depth = 1;
    m.return_stack[0] = defs.floatBits(2.5);
    m.float_depth = m.float_stack.len;
    try std.testing.expectError(error.FloatStackOverflow, m.executeBuiltin(.f_r_from));
    try std.testing.expectError(error.FloatStackOverflow, m.executeBuiltin(.f_r_fetch));
    try std.testing.expectEqual(@as(usize, 1), m.return_depth);
    try std.testing.expectEqual(defs.floatBits(2.5), m.return_stack[0]);
}

test "P09c return extensions compose with loops CATCH recursion and locals" {
    try support.skipWithoutFloat();
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try m.interpretLine(": LOOPED 77 >R 3 0 DO I S>F F>R FR@ F>S FR> F>S + 0 RPICK DROP LOOP R> ; LOOPED");
    try support.expectStack(m, &.{ 0, 2, 4, 77 });
    m.data_depth = 0;
    try m.interpretLine(": BAD 1.25E F>R 77 >R -123 THROW ; : CAUGHT 42 >R ['] BAD CATCH R> ; CAUGHT");
    try support.expectStack(m, &.{ -123, 42 });
    m.data_depth = 0;
    try m.interpretLine(": LOCAL { n -- r } n S>F F>R FR@ F>S FR> FDROP ; 7 LOCAL : REC DUP 0= IF DROP EXIT THEN DUP S>F F>R 1- RECURSE FR> F>S ; 4 REC");
    try support.expectStack(m, &.{ 7, 1, 2, 3, 4 });
    try std.testing.expectEqual(@as(usize, 0), m.return_depth);
    try std.testing.expectEqual(@as(usize, 0), m.float_depth);
    try std.testing.expectEqual(@as(usize, 0), m.loop_depth);
}

test "P09c return words retain identity across all image routes" {
    try support.skipWithout(&.{.image});
    try support.skipWithoutFloat();
    var out = support.Output{};
    const source = try support.createMachine(&out);
    defer support.destroyMachine(source);
    try source.interpretLine(": RETURNS 11 >R 22 >R R'@ 0 RPICK R> DROP R> DROP 1.25E F>R FR@ F>S FR> F>S ;");
    const image = try std.testing.allocator.alloc(u8, try source.encodedSize());
    defer std.testing.allocator.free(image);
    _ = try source.encodeImage(image);
    for (0..3) |mode| {
        const m = try support.createMachine(&out);
        defer support.destroyMachine(m);
        try m.interpretLine(": PREFIX 99 ;");
        switch (mode) {
            0 => try m.restoreImage(image),
            1 => try m.appendImage(source),
            else => {
                var work: @import("../core/image_append.zig").Workspace = undefined;
                try @import("../core/image_append.zig").append(m, image, &work);
            },
        }
        try m.interpretLine("RETURNS");
        try support.expectStack(m, &.{ 11, 22, 1, 1 });
        try std.testing.expectEqual(@as(usize, 0), m.return_depth);
    }
}
