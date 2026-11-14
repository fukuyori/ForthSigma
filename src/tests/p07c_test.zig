const std = @import("std");
const support = @import("support.zig");
const map = @import("../core/memory_map.zig");
const loops = @import("../core/words_loops.zig");
const registry = @import("../core/address_registry.zig");

test "P07c signed unsigned and inclusive loop starts distinguish empty ranges" {
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try m.interpretLine(": A 3 0 +DO I LOOP ; : B 0 3 +DO 99 LOOP ; : C 0 0 -[DO I -1 +LOOP ; : D 0 3 -DO I 1 -LOOP ; A B C D");
    try support.expectStack(m, &.{ 0, 1, 2, 0, 3, 2, 1 });
    m.data_depth = 0;
    try m.interpretLine(": U 1 -1 U+DO 99 LOOP ; : V -1 1 U-DO 99 -1 +LOOP ; : W 1 -1 +DO I LOOP ; U V W");
    try support.expectStack(m, &.{ -1, 0 });
}

test "P07c negative loop uses unsigned decrement including zero and huge magnitudes" {
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try m.interpretLine(": A 0 5 DO I 2 -LOOP ; : B 0 5 DO I -1 -LOOP ; A B");
    try support.expectStack(m, &.{ 5, 3, 1, 5 });
    m.data_depth = 0;
    try m.interpretLine(": Z 0 5 DO I LEAVE 0 -LOOP ; Z");
    try support.expectStack(m, &.{5});
    try std.testing.expectEqual(@as(usize, 0), m.loop_depth);
    m.data_depth = 0;
    try m.interpretLine("VARIABLE TIMES : EQ 0 TIMES ! 0 0 -[DO I 1 TIMES +! TIMES @ 3 = IF LEAVE THEN 0 +LOOP ; EQ");
    try support.expectStack(m, &.{ 0, 0, 0 });
}

test "P07c FOR visits zero and preserves initialized body locals" {
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try m.interpretLine(": T 3 FOR I NEXT ; : Z 0 FOR I NEXT ; : L 1 FOR { x -- } NEXT x ; T Z 7 8 L");
    try support.expectStack(m, &.{ 3, 2, 1, 0, 0, 7 });
    m.data_depth = 0;
    try m.interpretLine(": N 1 FOR 1 FOR J I NEXT NEXT ; N");
    try support.expectStack(m, &.{ 1, 1, 1, 0, 0, 1, 0, 0 });
}

test "P07c loop limit and delta access work through helpers and reject absent frames" {
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try m.interpretLine(": H I I' DELTA-I ; : T 2 0 +DO H LOOP ; T : F 1 FOR I' DELTA-I NEXT ; F");
    try support.expectStack(m, &.{ 0, 2, 2, 1, 2, 1, 0, -1, 0, 0 });
    m.data_depth = 0;
    try std.testing.expectError(error.LoopMismatch, m.executeBuiltin(.index_limit));
    try std.testing.expectError(error.LoopMismatch, m.executeBuiltin(.delta_index));
}

test "P07c memory loops visit forward partial elements and reverse full elements" {
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try m.interpretLine(": A 100 5 2 MEM+DO I 100 - LOOP ; : B 100 5 2 MEM-DO I 100 - LOOP ; : C 100 1 3 MEM-DO 99 LOOP ; A B C");
    try support.expectStack(m, &.{ 0, 2, 4, 3, 1 });
    m.data_depth = 0;
    try m.interpretLine("CREATE DATA 1 , 3 , 7 , : R DATA 3 CELL ARRAY>MEM MEM+DO I @ LOOP DATA 3 CELL ARRAY>MEM MEM-DO I @ LOOP ; R");
    try support.expectStack(m, &.{ 1, 3, 7, 7, 3, 1 });
}

test "P07c invalid memory strides and overflowing ranges fail before consuming arguments" {
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    for ([_][3]map.Cell{ .{ 100, 4, 0 }, .{ 100, 4, -1 }, .{ -2, 4, 1 }, .{ 100, -1, 1 } }) |args| {
        for (args) |x| try m.push(x);
        try std.testing.expectError(error.InvalidNumber, loops.enter(m, .memory_up_do, 0));
        try support.expectStack(m, &args);
        m.data_depth = 0;
        try std.testing.expectEqual(@as(usize, 0), m.loop_depth);
    }
    try m.interpretLine(": T 100 4 9223372036854775807 MEM-DO 99 LOOP ; T");
    try support.expectStack(m, &.{});
}

test "P07c ARRAY MEM wraps cell multiplication and combined IF keeps the original value" {
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try m.interpretLine("-1 2 ARRAY>MEM : T ?DUP-IF 11 ELSE 22 THEN ; : U ?DUP-0=-IF 33 ELSE 44 THEN ; 0 T -1 T 0 U 3 U");
    try support.expectStack(m, &.{ -2, 2, 22, -1, 11, 33, 3, 44 });
}

test "P07c DONE resolves LEAVE for explicit UNLOOP and keeps surrounding loops intact" {
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try m.interpretLine(": A 3 0 DO I LEAVE DONE UNLOOP 9 ; A");
    try m.interpretLine(": C 2 0 DO 3 0 DO I LEAVE DONE UNLOOP I LOOP ; C : Q 0 0 ?DO 99 LEAVE DONE UNLOOP 7 ; Q");
    try support.expectStack(m, &.{ 0, 9, 0, 0, 0, 1, 7 });
    try std.testing.expectEqual(@as(usize, 0), m.loop_depth);
}

test "P07c CS operations work in temporary interpretation and reject incompatible loop controls" {
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try m.interpretLine(": T IF [ 0 CS-PICK CS-DROP ] 7 THEN ; -1 T 0 T : U BEGIN [ 0 CS-PICK CS-DROP ] 1 UNTIL 8 ; U");
    try support.expectStack(m, &.{ 7, 8 });
    try std.testing.expectError(error.CompileOnly, m.executeBuiltin(.cs_drop));
    try m.interpretLine(": OPEN 100 4 1 MEM+DO");
    try m.push(0);
    try std.testing.expectError(error.ControlMismatch, m.executeBuiltin(.cs_pick));
    try std.testing.expectEqual(@as(usize, 1), m.control_depth);
    m.report(error.Aborted);
    try std.testing.expect(m.lookup("OPEN") == null);
}

test "P07c loop cancellation exceptions and EXIT clean up VM loop frames" {
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try m.interpretLine(": A 3 FOR I UNLOOP EXIT NEXT ; A : B 100 6 2 MEM+DO -123 THROW LOOP ; ' B CATCH");
    try support.expectStack(m, &.{ 3, -123 });
    try std.testing.expectEqual(@as(usize, 0), m.loop_depth);
    try std.testing.expectEqual(@as(usize, 0), m.frame_depth);
}

test "P07c extended and DONE branch targets relocate through all image paths" {
    var out = support.Output{};
    const source = try support.createMachine(&out);
    defer support.destroyMachine(source);
    try source.interpretLine("CREATE DATA 1 , 3 , 7 , : R DATA 3 CELL ARRAY>MEM MEM-DO I @ LOOP ; : D 3 0 DO I LEAVE DONE UNLOOP ; : Q [: 2 FOR I NEXT ;] ; : RUN R D Q EXECUTE ;");
    const image = try std.testing.allocator.alloc(u8, try source.encodedSize());
    defer std.testing.allocator.free(image);
    _ = try source.encodeImage(image);
    for (0..3) |mode| {
        const m = try support.createMachine(&out);
        defer support.destroyMachine(m);
        try m.interpretLine(": BEFORE 9 ;");
        switch (mode) {
            0 => try m.restoreImage(image),
            1 => try m.appendImage(source),
            else => {
                const append = @import("../core/image_append.zig");
                var work: append.Workspace = undefined;
                try append.append(m, image, &work);
            },
        }
        try m.interpretLine("RUN");
        try support.expectStack(m, &.{ 7, 3, 1, 0, 2, 1, 0 });
        try registry.validate(m);
        try std.testing.expectEqual(@as(usize, 0), m.loop_depth);
    }
}

test "P07c malformed control syntax cannot close the wrong loop kind" {
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    for ([_][]const u8{ ": BAD NEXT ;", ": BAD -LOOP ;", ": BAD DONE ;", ": BAD 3 FOR LOOP ;", ": BAD 3 0 DO NEXT ;", ": BAD 100 4 1 MEM+DO 2 +LOOP ;" }) |input| {
        try std.testing.expectError(error.ControlMismatch, m.interpretLine(input));
        m.report(error.Aborted);
        try std.testing.expect(m.lookup("BAD") == null);
    }
}

test "P07c SEE reconstructs DONE and zero-step loops retain work-limit interruption" {
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try m.interpretLine(": EARLY 3 0 DO I LEAVE DONE UNLOOP ; : Z 0 5 DO 0 -LOOP ;");
    if (@import("build_options").tools) {
        try m.interpretLine("SEE EARLY");
        try std.testing.expect(std.mem.indexOf(u8, out.written(), "DONE UNLOOP") != null);
    }
    if (@import("build_options").debug) {
        m.step_limit = 50;
        m.steps_left = 50;
        try std.testing.expectError(error.StepLimit, m.interpretLine("' Z CATCH"));
        m.report(error.StepLimit);
        try support.expectStack(m, &.{});
        try std.testing.expectEqual(@as(usize, 0), m.loop_depth);
        m.step_limit = 0;
    }
}
