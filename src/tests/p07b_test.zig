const std = @import("std");
const Float = @import("../core/memory_map.zig").Float;
const support = @import("support.zig");
const registry = @import("../core/address_registry.zig");

test "P07b interpreted nested and compiled quotations produce stable tokens" {
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try m.interpretLine("[: 7 ;] EXECUTE : T [: [: 8 ;] ;] ; T EXECUTE EXECUTE T T = LATESTXT ' T =");
    try support.expectStack(m, &.{ 7, 8, -1, -1 });
    try registry.validate(m);
}

test "P07b quotations isolate locals controls recursion and restore the outer definition" {
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try m.interpretLine(": T { x -- } x IF [: { n -- } n 0> IF n 1- RECURSE ELSE 7 THEN ;] ELSE [: DROP 8 ;] THEN 3 SWAP EXECUTE x ; 1 T 0 T");
    // n is reintroduced on every recursive entry; no outer-local capture.
    try support.expectStack(m, &.{ 7, 1, 8, 0 });
    try std.testing.expectEqual(@as(usize, 0), m.quote_depth);
    try std.testing.expectEqual(@as(usize, 0), m.local_count);
    try std.testing.expectEqual(@as(usize, 0), m.control_depth);
}

test "P07b quote callbacks preserve CATCH and IN COLON DEF semantics" {
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try m.interpretLine("IN-COLON-DEF? : T [ IN-COLON-DEF? ] LITERAL [: IN-COLON-DEF? ;] EXECUTE ; T 4 [: -123 THROW ;] CATCH");
    try support.expectStack(m, &.{ 0, -1, 0, 4, -123 });
}

test "P07b NONAME applies to colon data and deferred defining words without a name token" {
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try m.interpretLine("NONAME : 7 ; LATEST LATESTXT EXECUTE NONAME VARIABLE LATESTXT EXECUTE 8 OVER ! @ 9 NONAME VALUE LATESTXT EXECUTE NONAME CREATE 10 , LATESTXT EXECUTE @ NONAME DEFER LATESTXT DUP ' DUP SWAP DEFER! 11 SWAP EXECUTE");
    try support.expectStack(m, &.{ 0, 7, 8, 9, 10, 11, 11 });
    m.data_depth = 0;
    try m.interpretLine("NONAME NONAME 3 4 + CONSTANT LATESTXT EXECUTE : MAKE NONAME : ; MAKE 12 ; LATESTXT EXECUTE");
    try support.expectStack(m, &.{ 7, 12 });
}

test "P07b postponing supports word semantics numeric and parsing literals" {
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try m.interpretLine(": ADD ]] DUP + [[ ; IMMEDIATE : NUM ]] 7 [[ ; IMMEDIATE : T 3 ADD NUM ; T : STR ]] S\" [[ ; IMMEDIATE : U STR text\" ; U TYPE : PRINT ]] .\" [[ ; IMMEDIATE : P PRINT message\" ; P");
    try support.expectStack(m, &.{ 6, 7 });
    try std.testing.expectEqualStrings("textmessage", out.written());
    m.data_depth = 0;
    try m.interpretLine(": D ]] 7. [[ ; IMMEDIATE : DD D ; DD : L { x -- } ]] x + [[ ; IMMEDIATE : LL 3 [ 4 ] L ; LL");
    try support.expectStack(m, &.{ 7, 0, 7 });
    if (@import("build_options").float) {
        try m.interpretLine(": F ]] 2.5e [[ ; IMMEDIATE : FF F ; FF");
        try std.testing.expectEqual(@as(Float, 2.5), try m.fpop());
    }
}

test "P07b postponing quotes and assignments and temporary interpretation are composable" {
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try m.interpretLine("1 VALUE V : SET ]] TO [[ ; IMMEDIATE : T 7 SET V ; V T V : Q ]] [: 8 ;] [[ ; IMMEDIATE : U Q ; U EXECUTE : DUP-M [ ]] DUP [[ ; IMMEDIATE : D 3 DUP-M ; D");
    try support.expectStack(m, &.{ 1, 7, 8, 3, 3 });
    m.data_depth = 0;
    try m.interpretLine(": XT-M { XT: f -- } ]] f [[ ; IMMEDIATE : XT-T [ ' DUP ] XT-M ; 4 XT-T");
    try support.expectStack(m, &.{ 4, 4 });
    try std.testing.expect(!m.postponing);
    try std.testing.expect(m.lookup("[[") == null);
}

test "P07b malformed quote removes the whole unfinished outer definition" {
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try m.interpretLine(": KEEP 42 ;");
    const count = m.word_count;
    const code = m.code_count;
    const names = m.names_used;
    try std.testing.expectError(error.UnknownWord, m.interpretLine(": BAD { x -- } [: x ;] ;"));
    try std.testing.expectEqual(count, m.word_count);
    try std.testing.expectEqual(code, m.code_count);
    try std.testing.expectEqual(names, m.names_used);
    try std.testing.expect(!m.defining and !m.compiling and m.quote_depth == 0);
    try std.testing.expect(m.lookup("BAD") == null);
    try m.interpretLine("KEEP");
    try support.expectStack(m, &.{42});
    try std.testing.expectError(error.ControlMismatch, m.interpretLine(": BAD [: IF 7 ;] ;"));
    try std.testing.expectEqual(count, m.word_count);
    try std.testing.expectError(error.ControlMismatch, m.interpretLine(";]"));
    try std.testing.expectError(error.CompileOnly, m.interpretLine("]]"));
}

test "P07b unterminated EVALUATE and caught quote errors cannot resurrect a discarded compiler" {
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try m.interpretLine(": BAD S\" : LOST [: 7\" EVALUATE ; ' BAD CATCH");
    try support.expectStack(m, &.{-259});
    try std.testing.expect(m.lookup("LOST") == null);
    try std.testing.expect(!m.defining and !m.compiling and m.quote_depth == 0);
    m.data_depth = 0;
    try m.interpretLine(": QERR S\" [: UNKNOWN\" EVALUATE ; : OUTER [ ' QERR CATCH");
    try support.expectStack(m, &.{-13});
    try std.testing.expect(m.lookup("OUTER") == null);
    try std.testing.expect(!m.defining and !m.compiling and m.control_depth == 0);
}

test "P07b quote depth bound rolls back and independent later definitions still work" {
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    const count = m.word_count;
    var input: [128]u8 = undefined;
    var n: usize = 0;
    for (0..17) |_| {
        @memcpy(input[n..][0..3], "[: ");
        n += 3;
    }
    try std.testing.expectError(error.ControlStackOverflow, m.interpretLine(input[0..n]));
    try std.testing.expectEqual(count, m.word_count);
    try m.interpretLine(": GOOD [: 9 ;] ; GOOD EXECUTE");
    try support.expectStack(m, &.{9});
}

test "P07b quotations and macro compiler actions survive restore and both append paths" {
    var out = support.Output{};
    const source = try support.createMachine(&out);
    defer support.destroyMachine(source);
    try source.interpretLine(": Q [: [: 7 ;] ;] ; : MAC ]] 8 + [[ ; IMMEDIATE : T 3 MAC ; : MAKE-Q ]] [: 9 ;] [[ ; IMMEDIATE : U MAKE-Q ;");
    const image = try std.testing.allocator.alloc(u8, try source.encodedSize());
    defer std.testing.allocator.free(image);
    _ = try source.encodeImage(image);
    for (0..3) |mode| {
        const m = try support.createMachine(&out);
        defer support.destroyMachine(m);
        try m.interpretLine(": BEFORE 1 ;");
        switch (mode) {
            0 => try m.restoreImage(image),
            1 => try m.appendImage(source),
            else => {
                const append = @import("../core/image_append.zig");
                var work: append.Workspace = undefined;
                try append.append(m, image, &work);
            },
        }
        try m.interpretLine("Q EXECUTE EXECUTE T U EXECUTE : V 4 MAC ; V LATESTXT ' V =");
        try support.expectStack(m, &.{ 7, 11, 9, 12, -1 });
        try registry.validate(m);
    }
}

test "P07b unfinished quotation cannot be saved and failed close rolls back data and names" {
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try m.interpretLine(": KEEP 42 ;");
    const count = m.word_count;
    const here = m.data_here;
    try std.testing.expectError(error.UnknownWord, m.interpretLine(": BAD [: [ CREATE TEMP 16 ALLOT ] MISSING ;] ;"));
    try std.testing.expectEqual(count, m.word_count);
    try std.testing.expectEqual(here, m.data_here);
    try std.testing.expect(m.lookup("TEMP") == null);
    try m.interpretLine("[: 7");
    try std.testing.expectError(error.InvalidDefinition, m.encodedSize());
    m.data_depth = m.data_stack.len;
    try std.testing.expectError(error.StackOverflow, m.interpretLine(";]"));
    try std.testing.expectEqual(count, m.word_count);
    try std.testing.expect(!m.defining and m.quote_depth == 0);
    m.data_depth = 0;
    try m.interpretLine("KEEP");
    try support.expectStack(m, &.{42});
}

test "P07b multiline quotations and quoted outer locals restore before subsequent source lines" {
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try m.interpretLine(": T { x -- } [: 7");
    try m.interpretLine(";] EXECUTE x ; 3 T");
    try support.expectStack(m, &.{ 7, 3 });
    if (@import("build_options").files) {
        support.setFakeFile(&out, 0, ": Q [: 8\n;] ;\nQ EXECUTE\n");
        try m.interpretLine("S\" a.txt\" INCLUDED");
        try support.expectStack(m, &.{ 7, 3, 8 });
        support.setFakeFile(&out, 0, ": BAD [: 9\n");
        try std.testing.expectError(error.InvalidDefinition, m.interpretLine("S\" a.txt\" INCLUDED"));
        try std.testing.expect(m.lookup("BAD") == null);
    }
}

test "P07b malformed quotation metadata is rejected before replacing a dictionary" {
    const format = @import("../core/image_format.zig");
    const Word = @import("../core/defs.zig").Word;
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try m.interpretLine(": Q [: 7 ;] ;");
    const q = m.lookup("Q").?;
    const image = try std.testing.allocator.alloc(u8, try m.encodedSize());
    defer std.testing.allocator.free(image);
    _ = try m.encodeImage(image);
    const at = format.header_size + @as(usize, q + 1) * @sizeOf(Word) + @offsetOf(Word, "quotation");
    image[at] = 2;
    try format.finish(image);
    try std.testing.expectError(error.InvalidImage, m.restoreImage(image));
    image[at] = 1;
    image[format.header_size + @as(usize, q) * @sizeOf(Word) + @offsetOf(Word, "quotation")] = 1;
    try format.finish(image);
    try std.testing.expectError(error.InvalidImage, m.restoreImage(image));
    try m.interpretLine("Q EXECUTE LATESTXT ' Q =");
    try support.expectStack(m, &.{ 7, -1 });
}

test "P07 review CATCH discards runtime-opened quotations before later definitions" {
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try m.interpretLine(": OPEN POSTPONE [: -123 THROW ; : RUN ['] OPEN CATCH ; RUN");
    try support.expectStack(m, &.{-123});
    try std.testing.expectEqual(@as(usize, 0), m.quote_depth);
    try std.testing.expect(!m.defining and !m.compiling);
    try m.interpretLine(": KEEP 42 ;");
    const count = m.word_count;
    try std.testing.expectError(error.UnknownWord, m.interpretLine("UNKNOWN"));
    try std.testing.expectEqual(count, m.word_count);
    try m.interpretLine("KEEP");
    try support.expectStack(m, &.{ -123, 42 });
}

test "P07 review caught nested quote opening abandons its unfinished outer compiler" {
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try m.interpretLine(": OPEN POSTPONE [: POSTPONE [: -123 THROW ; : OUTER [ ' OPEN CATCH");
    try support.expectStack(m, &.{-123});
    try std.testing.expectEqual(@as(usize, 0), m.quote_depth);
    try std.testing.expect(!m.defining and !m.compiling and m.control_depth == 0);
    try std.testing.expect(m.lookup("OUTER") == null);
    m.data_depth = 0;
    try m.interpretLine(": BAD -77 THROW ; [: [ ' BAD CATCH DROP ] 7 ;] EXECUTE");
    try support.expectStack(m, &.{7});
}

test "P07 review CATCH does not restore closed quote controls into its outer definition" {
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try m.interpretLine(": CLOSE POSTPONE ;] -123 THROW ; : TRY ['] CLOSE CATCH ; IMMEDIATE : OUTER { x -- } x IF [: { y -- } TRY");
    try support.expectStack(m, &.{-123});
    try std.testing.expect(!m.defining and !m.compiling);
    try std.testing.expectEqual(@as(usize, 0), m.quote_depth);
    try std.testing.expectEqual(@as(usize, 0), m.control_depth);
    try std.testing.expectEqual(@as(usize, 0), m.local_count);
    try std.testing.expect(m.lookup("OUTER") == null);
    m.data_depth = 0;
    try m.interpretLine("[: TRY : KEEP 42 ; KEEP");
    try support.expectStack(m, &.{ -123, 42 });
    try std.testing.expect(!m.defining and !m.compiling and m.quote_depth == 0);
}

test "P07 review SEE and stepping name postponed compiler helpers" {
    try support.skipWithout(&.{ .tools, .debug });
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try m.interpretLine("1 VALUE V : M POSTPONE TO ; : S ]] S\" [[ ; SEE M SEE S");
    try std.testing.expect(std.mem.indexOf(u8, out.written(), "POSTPONE TO") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.written(), "POSTPONE S\"") != null);
    out.len = 0;
    out.keys = "\n\n\n\n";
    try m.interpretLine(": T [ DBG M V ] ;");
    try std.testing.expect(std.mem.indexOf(u8, out.written(), "POSTPONE TO") != null);
}

test "P07 review postponing rejects parser-only tokens without leaving a compiler" {
    const cases = [_][]const u8{ ": BAD ]] ['] DUP [[ ;", ": BAD ]] [CHAR] x [[ ;", ": BAD ]] POSTPONE DUP [[ ;" };
    for (cases) |source| {
        var out = support.Output{};
        const m = try support.createMachine(&out);
        defer support.destroyMachine(m);
        // Parser-only syntax is not a dictionary compilation token in Sigma.
        try std.testing.expectError(error.UnknownWord, m.interpretLine(source));
        m.report(error.UnknownWord);
        try std.testing.expect(!m.defining and !m.compiling and !m.postponing);
        try std.testing.expect(m.lookup("BAD") == null);
    }
}
