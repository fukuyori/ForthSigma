const std = @import("std");
const Builtin = @import("../core/defs.zig").Builtin;
const support = @import("support.zig");
const map = @import("../core/memory_map.zig");
const tokens = @import("../core/words_compilation_tokens.zig");
const registry = @import("../core/address_registry.zig");

test "P07a compilation token parsing selects ordinary immediate and combined semantics" {
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try m.interpretLine("COMP' DUP");
    try support.expectStack(m, &.{ m.builtinWord(.dup), m.builtinWord(.compile_comma) });
    m.data_depth = 0;
    try m.interpretLine("COMP' IF");
    try support.expectStack(m, &.{ m.builtinWord(.compile_if), m.builtinWord(.execute) });
    m.data_depth = 0;
    try m.interpretLine("COMP' TO");
    try support.expectStack(m, &.{ m.builtinWord(.compile_assign_to), m.builtinWord(.execute) });
    m.data_depth = 0;
    try m.interpretLine(": P COMP' ; P DUP : Q [COMP'] TO ; Q");
    try support.expectStack(m, &.{ m.builtinWord(.dup), m.builtinWord(.compile_comma), m.builtinWord(.compile_assign_to), m.builtinWord(.execute) });
}

test "P07a POSTPONE comma composes ordinary immediate and assignment tokens" {
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try m.interpretLine(": DUP-M [ COMP' DUP POSTPONE, ] ; IMMEDIATE : I-M [ COMP' IF POSTPONE, ] ; IMMEDIATE : T 7 DUP-M I-M 11 ELSE 22 THEN ; T");
    try support.expectStack(m, &.{ 7, 11 });
    m.data_depth = 0;
    try m.interpretLine("1 VALUE V : SET-M [ COMP' TO POSTPONE, ] ; IMMEDIATE : U 9 SET-M V ; V U V");
    try support.expectStack(m, &.{ 1, 9 });
    m.data_depth = 0;
    try m.interpretLine(": M [COMP'] TO EXECUTE ; : Y 8 [ M V ] ; Y V");
    try support.expectStack(m, &.{8});
    // A noncanonical, but callable, second token is emitted as a generic pair.
    try m.interpretLine(": RUN-CT EXECUTE ; : BUILDER [ ' DUP ' RUN-CT POSTPONE, ] ; 4 BUILDER");
    try support.expectStack(m, &.{ 8, 4, 4 });
}

test "P07a restrictions affect ordinary interpretation and preserve explicit execution" {
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try m.interpretLine(": X 77 ; COMPILE-ONLY SYNONYM Y X : T X Y ; T ' X EXECUTE S\" X\" FIND-NAME NAME>INTERPRET EXECUTE");
    try support.expectStack(m, &.{ 77, 77, 77, 77 });
    m.data_depth = 0;
    try m.interpretLine(": BAD S\" X\" EVALUATE ; : ALIAS-BAD S\" Y\" EVALUATE ; ' BAD CATCH ' ALIAS-BAD CATCH");
    try support.expectStack(m, &.{ -14, -14 });
    m.data_depth = 0;
    try m.interpretLine(": I 12 ; IMMEDIATE RESTRICT : U I LITERAL ; U");
    try support.expectStack(m, &.{12});
    try std.testing.expectError(error.CompileOnly, m.interpretLine("I"));
    try std.testing.expect(m.words[m.lookup("Y").?].compile_only);
}

test "P07a unnamed or absent latest word cannot be restricted" {
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try std.testing.expectError(error.InvalidDefinition, m.executeBuiltin(.compile_only));
    try m.interpretLine(":NONAME 7 ;");
    const count = m.word_count;
    try std.testing.expectError(error.InvalidDefinition, m.executeBuiltin(.restrict_word));
    try std.testing.expectEqual(count, m.word_count);
    try std.testing.expect(!m.words[count - 1].compile_only);
}

test "P07a EXECUTE EXIT leaves its caller and restores local and loop resources" {
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    const locals = m.locals_top;
    try m.interpretLine(": A 7 ; : T { x -- } x ['] A EXECUTE-EXIT 99 ; : U 3 T 8 ; U : L 3 0 DO I 1 = IF UNLOOP ['] A EXECUTE-EXIT THEN LOOP 99 ; L");
    try support.expectStack(m, &.{ 3, 7, 8, 7 });
    try std.testing.expectEqual(locals, m.locals_top);
    try std.testing.expectEqual(@as(usize, 0), m.loop_depth);
    try std.testing.expectEqual(@as(usize, 0), m.frame_depth);
    m.data_depth = 0;
    try m.interpretLine(": THROWER -123 THROW ; : BAD { x -- } ['] THROWER EXECUTE-EXIT 99 ; : RUN 1 BAD ; ' RUN CATCH");
    try support.expectStack(m, &.{-123});
    try std.testing.expectEqual(locals, m.locals_top);
    try std.testing.expectEqual(@as(usize, 0), m.frame_depth);
}

test "P07a SELECT handles noncanonical flags and bracket NOOP has default compilation semantics" {
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try m.interpretLine("11 22 0 SELECT 11 22 1 SELECT 11 22 -2 SELECT : N [NOOP] ; [NOOP] N ' [NOOP] EXECUTE");
    try support.expectStack(m, &.{ 22, 11, 11 });
    m.data_depth = 0;
    try m.interpretLine("COMP' [NOOP]");
    try support.expectStack(m, &.{ m.builtinWord(.bracket_noop), m.builtinWord(.compile_comma) });
}

test "P07a compile state and token preflight reject invalid operations without partial emission" {
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    for ([_]Builtin{ .bracket_comp_tick, .execute_exit, .postpone_comma }) |word| {
        try std.testing.expectError(error.CompileOnly, m.executeBuiltin(word));
    }
    try m.interpretLine(": OPEN");
    const before = m.code_count;
    try m.push(-1);
    try m.push(m.builtinWord(.execute));
    try std.testing.expectError(error.InvalidExecutionToken, m.executeBuiltin(.postpone_comma));
    try support.expectStack(m, &.{ -1, m.builtinWord(.execute) });
    try std.testing.expectEqual(before, m.code_count);
    m.data_depth = 0;
    const saved = m.code_count;
    m.code_count = map.max_code - 1;
    defer m.code_count = saved;
    try std.testing.expectError(error.CodeFull, tokens.execute(m, .execute_exit));
    try std.testing.expectEqual(map.max_code - 1, m.code_count);
}

test "P07a compile-only metadata and token macros survive restore and both append paths" {
    var out = support.Output{};
    const source = try support.createMachine(&out);
    defer support.destroyMachine(source);
    try source.interpretLine(": X 77 ; COMPILE-ONLY SYNONYM Y X : M [ COMP' DUP POSTPONE, ] ; IMMEDIATE : T 4 M ; : A 8 ; : EXIT-M ['] A EXECUTE-EXIT 99 ;");
    const image = try std.testing.allocator.alloc(u8, try source.encodedSize());
    defer std.testing.allocator.free(image);
    _ = try source.encodeImage(image);
    for (0..3) |mode| {
        const target = try support.createMachine(&out);
        defer support.destroyMachine(target);
        try target.interpretLine(": BEFORE 9 ;");
        switch (mode) {
            0 => try target.restoreImage(image),
            1 => try target.appendImage(source),
            else => {
                const append = @import("../core/image_append.zig");
                var work: append.Workspace = undefined;
                try append.append(target, image, &work);
            },
        }
        try std.testing.expect(target.words[target.lookup("X").?].compile_only);
        try std.testing.expect(target.words[target.lookup("Y").?].compile_only);
        try std.testing.expectError(error.CompileOnly, target.interpretLine("Y"));
        try target.interpretLine(": U Y ; U T EXIT-M : C [COMP'] TO ; C");
        try support.expectStack(target, &.{ 77, 4, 4, 8, target.builtinWord(.compile_assign_to), target.builtinWord(.execute) });
        try registry.validate(target);
    }
}

test "P07a malformed compile-only image flag is rejected before dictionary mutation" {
    const format = @import("../core/image_format.zig");
    const defs = @import("../core/defs.zig");
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try m.interpretLine(": X 7 ; COMPILE-ONLY");
    const id = m.lookup("X").?;
    const image = try std.testing.allocator.alloc(u8, try m.encodedSize());
    defer std.testing.allocator.free(image);
    _ = try m.encodeImage(image);
    image[format.header_size + @as(usize, id) * @sizeOf(defs.Word) + @offsetOf(defs.Word, "compile_only")] = 2;
    try format.finish(image);
    const count = m.word_count;
    try std.testing.expectError(error.InvalidImage, m.restoreImage(image));
    try std.testing.expectEqual(count, m.word_count);
    try std.testing.expect(m.words[id].compile_only);
    try m.interpretLine("' X EXECUTE");
    try support.expectStack(m, &.{7});
}
