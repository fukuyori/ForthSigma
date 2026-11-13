const std = @import("std");
const support = @import("support.zig");
const map = @import("../core/memory_map.zig");
const registry = @import("../core/address_registry.zig");

test "P04b dictionary macros have case sensitive lookup and restore CURRENT" {
    var output = support.Output{};
    const m = try support.createMachine(&output);
    defer support.destroyMachine(m);
    try m.interpretLine("GET-CURRENT REPLACER: Foo S\" callback\" ; GET-CURRENT = S\" lower\" S\" foo\" REPLACES S\" %Foo%/%foo%/%FOO%/%%/%missing%/%\" .SUBSTITUTE");
    try support.expectStack(m, &.{ -1, 2 });
    try std.testing.expectEqualStrings("callback/lower/%FOO%/%/%missing%/%", output.written());
    try m.interpretLine("S\" value\" MACRO: Value");
    // CURRENT is still Forth, so Value does not become a macro implicitly.
    try std.testing.expect(m.lookupIn("Value", map.macros_wordlist) == null);
    try registry.validate(m);
}

test "P04b replacements and TO share the macro dictionary while hard coded macros stay" {
    var output = support.Output{};
    const m = try support.createMachine(&output);
    defer support.destroyMachine(m);
    try m.interpretLine("S\" one\" S\" X\" REPLACES S\" two\" S\" X\" REPLACES REPLACER: Y S\" kept\" ; S\" ignored\" S\" Y\" REPLACES MACROS-WORDLIST GET-CURRENT SWAP SET-CURRENT S\" val\" MACRO: Z SET-CURRENT MACROS-WORDLIST >ORDER S\" !\" +TO Z S\" changed\" TO X PREVIOUS S\" %X%/%Y%/%Z%\" .SUBSTITUTE");
    try support.expectStack(m, &.{3});
    try std.testing.expectEqualStrings("WARNING: Y is a hard-coded macro\nchanged/kept/val!", output.written());
    try registry.validate(m);
}

test "P04b each API executes callbacks once per occurrence including overflow" {
    var output = support.Output{};
    const m = try support.createMachine(&output);
    defer support.destroyMachine(m);
    try m.interpretLine("VARIABLE N REPLACER: X 1 N +! S\" abc\" ; CREATE BUF 2 ALLOT S\" %X%%X%\" $SUBSTITUTE . TYPE N @ . S\" %X%%X%\" BUF 2 SUBSTITUTE . TYPE N @ . S\" %X%\" .SUBSTITUTE . N @ .");
    try std.testing.expectEqualStrings("2 abcabc2 -78 ab4 abc1 5 ", output.written());
    try support.expectStack(m, &.{});
    try registry.validate(m);
}

test "P04b callback exceptions propagate and captured outputs do not commit" {
    var output = support.Output{};
    const m = try support.createMachine(&output);
    defer support.destroyMachine(m);
    try m.interpretLine("REPLACER: X -123 THROW ; CREATE BUF 16 ALLOT BUF 16 65 FILL : DOT S\" before%X%after\" .SUBSTITUTE ; : OWN S\" before%X%after\" $SUBSTITUTE ; : BOUND S\" before%X%after\" BUF 16 SUBSTITUTE ;");
    const top = m.heapTop();
    try m.interpretLine("' DOT CATCH . ' OWN CATCH . ' BOUND CATCH . BUF 16 TYPE");
    try std.testing.expectEqualStrings("before-123 -123 -123 AAAAAAAAAAAAAAAA", output.written());
    try std.testing.expectEqual(top, m.heapTop());
    try registry.validate(m);
}

test "P04b nested substitutions and input freed by a callback remain safe" {
    var output = support.Output{};
    const m = try support.createMachine(&output);
    defer support.destroyMachine(m);
    try m.interpretLine("S\" inner\" S\" I\" REPLACES REPLACER: N S\" <%I%>\" $SUBSTITUTE DROP ; VARIABLE INPUT-OWNER S\" %N%/%F%/tail\" INPUT-OWNER $! REPLACER: F INPUT-OWNER $FREE S\" freed\" ; INPUT-OWNER $@ $SUBSTITUTE . TYPE");
    try std.testing.expectEqualStrings("2 <inner>/freed/tail", output.written());
    try support.expectStack(m, &.{});
    try registry.validate(m);
}

test "P04b overlapping bounded substitution damages typed destinations" {
    var output = support.Output{};
    const m = try support.createMachine(&output);
    defer support.destroyMachine(m);
    try m.interpretLine("CREATE BUF 64 ALLOT S\" %X%tail\" BUF SWAP MOVE REPLACER: X S\" value\" ; BUF 7 BUF 64 SUBSTITUTE . TYPE");
    try std.testing.expectEqualStrings("1 valuetail", output.written());
    try m.interpretLine("AVARIABLE OWNER HERE OWNER ! S\" x\" OWNER 1 SUBSTITUTE 2DROP DROP");
    try std.testing.expectError(error.InvalidAddress, registry.validate(m));
}

test "P04b macro callback stack and address contracts reject malformed results" {
    var output = support.Output{};
    const m = try support.createMachine(&output);
    defer support.destroyMachine(m);
    try m.interpretLine("REPLACER: BAD 1 ; : RUN S\" %BAD%\" $SUBSTITUTE ;");
    const top = m.heapTop();
    try std.testing.expectError(error.InvalidDefinition, m.interpretLine("RUN"));
    try std.testing.expectEqual(top, m.heapTop());
    m.data_depth = 0;
    try m.interpretLine("REPLACER: BADADDR -1 2 ; : RUNADDR S\" %BADADDR%\" .SUBSTITUTE ;");
    try std.testing.expectError(error.InvalidAddress, m.interpretLine("RUNADDR"));
}

test "P04b macros survive public restore and repeated append with user wordlists" {
    var output = support.Output{};
    const source = try support.createMachine(&output);
    defer support.destroyMachine(source);
    try source.interpretLine("WORDLIST CONSTANT USERLIST S\" value\" S\" X\" REPLACES REPLACER: Y S\" callback\" ; : RUN S\" %X%/%Y%\" .SUBSTITUTE DROP ;");
    const target = try support.createMachine(&output);
    defer support.destroyMachine(target);
    try target.interpretLine("WORDLIST CONSTANT OTHER CREATE PADDED 29 ALLOT");
    try target.appendImage(source);
    try target.appendImage(source);
    const bytes = try std.testing.allocator.alloc(u8, try target.encodedSize());
    defer std.testing.allocator.free(bytes);
    _ = try target.encodeImage(bytes);
    try target.restoreImage(bytes);
    try registry.validate(target);
    try target.interpretLine("RUN S\" new\" S\" X\" REPLACES RUN");
    try std.testing.expectEqualStrings("value/callbacknew/callback", output.written());
    try support.expectStack(target, &.{});
}

test "P04b MARKER removes macro words and roots and REPLACER supports multiline names" {
    var output = support.Output{};
    const m = try support.createMachine(&output);
    defer support.destroyMachine(m);
    try m.interpretLine("MARKER BACK REPLACER:");
    try m.interpretLine("X S\" hello\" ; S\" %X%\" .SUBSTITUTE DROP BACK S\" %X%\" .SUBSTITUTE");
    try std.testing.expectEqualStrings("hello%X%", output.written());
    try support.expectStack(m, &.{0});
    try std.testing.expect(m.lookupIn("X", map.macros_wordlist) == null);
    try registry.validate(m);
}

test "P04b output allocation failure frees snapshots and partial captures" {
    var output = support.Output{};
    const m = try support.createMachine(&output);
    defer support.destroyMachine(m);
    try m.interpretLine("REPLACER: X S\" a long replacement that exceeds the small remaining heap\" ; CREATE INPUT-TEXT 3 ALLOT S\" %X%\" INPUT-TEXT SWAP MOVE");
    const address = m.words[m.lookup("INPUT-TEXT").?].value;
    _ = (try m.heapAllocate(@intCast(m.sizes.heapEnd() - m.heapTop() - 96))).?;
    const top = m.heapTop();
    const source = m.memory[@intCast(address)..][0..3];
    try std.testing.expectError(error.Thrown, @import("../core/macro_substitute.zig").capture(m, source));
    try std.testing.expectEqual(top, m.heapTop());
    try registry.validate(m);
}

test "P04b failed TMP promotion does not retain a dangling owner or captured block" {
    var output = support.Output{};
    const m = try support.createMachine(&output);
    defer support.destroyMachine(m);
    try m.interpretLine("CREATE TYPES : FILL-TYPES 2048 0 DO 0 A, LOOP ; FILL-TYPES : RUN-PLAIN S\" plain\" $SUBSTITUTE ;");
    const top = m.heapTop();
    try std.testing.expectError(error.MemoryExhausted, m.interpretLine("RUN-PLAIN"));
    try std.testing.expectEqual(top, m.heapTop());
    try std.testing.expectEqual(@as(map.Cell, 0), try m.readCell(map.tmp_string_base));
    try registry.validate(m);
}

test "P04b captures callback emissions and restores nested TMP output targets" {
    var output = support.Output{};
    const m = try support.createMachine(&output);
    defer support.destroyMachine(m);
    try m.interpretLine(": INNER .\" captured\" ; REPLACER: X .\" emitted\" ['] INNER $TMP S\" captured\" COMPARE 0= IF S\" returned\" ELSE S\" wrong\" THEN ; S\" a%X%b\" $SUBSTITUTE . TYPE : OUTER S\" <%X%>\" $SUBSTITUTE DROP TYPE ; ' OUTER $TMP TYPE");
    try std.testing.expectEqualStrings("1 aemittedreturnedb<emittedreturned>", output.written());
    try std.testing.expect(m.capture_sink == null);
    try std.testing.expect(m.capture_target == null);
    try registry.validate(m);
}
