const std = @import("std");
const support = @import("support.zig");
const forth = @import("../forth.zig");
const registry = @import("../core/address_registry.zig");

test "P07 assignment names have interpretation tokens and immediate compilation semantics" {
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    for ([_][]const u8{ "TO", "IS", "+TO", "ACTION-OF" }) |name| {
        const id = m.lookup(name).?;
        try std.testing.expect(m.words[id].immediate);
        try std.testing.expectEqual(id, @import("../core/word_semantics.zig").interpretation(m, id));
        const compile = @import("../core/word_semantics.zig").compilation(m, id);
        try std.testing.expect(compile.execute and compile.target != id);
        try std.testing.expectEqual(@as(u8, 0), m.words[compile.target].name_len);
    }
    try m.interpretLine("1 VALUE V DEFER D : A 7 ; ' TO CONSTANT SET ' +TO CONSTANT ADD ' IS CONSTANT BIND ' ACTION-OF CONSTANT ACTION 2 SET EXECUTE V 3 ADD EXECUTE V ' A BIND EXECUTE D ACTION EXECUTE D EXECUTE");
    try support.expectStack(m, &.{7});
    try m.interpretLine("V");
    try support.expectStack(m, &.{ 7, 5 });
}

test "P07 interpretation actions execute immediately during compilation without changing STATE" {
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try m.interpretLine("1 VALUE V ' TO CONSTANT SET ' +TO CONSTANT ADD : M 2 SET EXECUTE ; IMMEDIATE : T M V V ; V T ' TO ' SET DROP DROP");
    try support.expectStack(m, &.{ 2, 2 });
    m.data_depth = 0;
    try m.interpretLine(": N 3 ADD EXECUTE ; IMMEDIATE : U N V V ; V U");
    try support.expectStack(m, &.{ 5, 5 });
    m.data_depth = 0;
    try m.interpretLine("DEFER D : A 8 ; ' IS CONSTANT BIND : B ['] A BIND EXECUTE ; IMMEDIATE : C B D D ; C ' ACTION-OF CONSTANT ACTION : GET ACTION EXECUTE POSTPONE LITERAL ; IMMEDIATE : Q GET D ; Q EXECUTE STATE @");
    try support.expectStack(m, &.{ 8, 8, 0 });
}

test "P07 POSTPONE and NAME COMPILE choose compilation actions including aliases" {
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try m.interpretLine("1 VALUE V SYNONYM SET TO SYNONYM ADD +TO : M POSTPONE SET ; IMMEDIATE : N POSTPONE ADD ; IMMEDIATE : T 3 M V 4 N V ; V T V");
    try support.expectStack(m, &.{ 1, 7 });
    m.data_depth = 0;
    try m.interpretLine("DEFER D : A 9 ; SYNONYM BIND IS SYNONYM ACTION ACTION-OF : B POSTPONE BIND ; IMMEDIATE : G POSTPONE ACTION ; IMMEDIATE : R ['] A B D G D ; R EXECUTE");
    try support.expectStack(m, &.{9});
    m.data_depth = 0;
    try m.interpretLine(": CT [ S\" TO\" FIND-NAME NAME>COMPILE SWAP ] LITERAL LITERAL EXECUTE ; IMMEDIATE : X 42 CT V ; X V");
    try support.expectStack(m, &.{42});
    m.data_depth = 0;
    try m.interpretLine(": Y 17 [ CT V ] ; Y V");
    try support.expectStack(m, &.{17});
    m.data_depth = 0;
    try m.interpretLine(": BRC [COMPILE] TO ; IMMEDIATE : BRT 29 BRC V ; V BRT V : INTERP [ ' TO COMPILE, ] ; 31 INTERP V V");
    try support.expectStack(m, &.{ 17, 29, 31 });
}

test "P07 dictionary search and redefinition shadow assignment names" {
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try m.interpretLine("1 VALUE V SYNONYM SET TO WORDLIST CONSTANT W W SET-CURRENT : TO 55 ; FORTH-WORDLIST SET-CURRENT W >ORDER TO PREVIOUS 2 TO V V 3 SET V V : TO 77 ; TO");
    try support.expectStack(m, &.{ 55, 2, 3, 77 });
}

test "P07 assignments retain scalar double string float and local behavior" {
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try m.interpretLine("1. 2VALUE D S\" a\" $VALUE S 3. IS D S\" b\" IS S : T 4. TO D S\" c\" +TO S ; T D S TYPE : L { x -- } 2 TO x 3 +TO x x ; 1 L");
    try support.expectStack(m, &.{ 4, 0, 5 });
    try std.testing.expectEqualStrings("bc", out.written());
    if (@import("build_options").float) {
        try m.interpretLine("1e FVALUE F 2e IS F : FF 3e +TO F ; FF F F.");
        try std.testing.expectEqualStrings("bc5. ", out.written());
    }
    try registry.validate(m);
}

test "P07 parsing names across lines and failures preserve Sigma error policy" {
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try m.interpretLine("1 VALUE V 2 TO");
    try m.interpretLine("V : T 3 +TO");
    try m.interpretLine("V ; T V");
    try support.expectStack(m, &.{5});
    m.data_depth = 0;
    try m.interpretLine(": BAD S\" 2 TO DUP\" EVALUATE ; : MISSING S\" TO\" EVALUATE ; ' BAD CATCH ' MISSING CATCH");
    try support.expectStack(m, &.{ -259, -259 });
    try std.testing.expect(m.pending == .none);
}

fn imageOf(m: *forth.State) ![]u8 {
    const image = try std.testing.allocator.alloc(u8, try m.encodedSize());
    errdefer std.testing.allocator.free(image);
    _ = try m.encodeImage(image);
    return image;
}

test "P07 assignment tokens and postponed actions survive full restore and both append paths" {
    var out = support.Output{};
    const source = try support.createMachine(&out);
    defer support.destroyMachine(source);
    try source.interpretLine("1 VALUE V ' TO CONSTANT SET : M POSTPONE TO ; IMMEDIATE : T 8 M V ; : RUN S\" 3 SET EXECUTE V\" EVALUATE T V ;");
    const image = try imageOf(source);
    defer std.testing.allocator.free(image);
    for (0..3) |mode| {
        const target = try support.createMachine(&out);
        defer support.destroyMachine(target);
        try target.interpretLine(": BEFORE 99 ;");
        switch (mode) {
            0 => try target.restoreImage(image),
            1 => try target.appendImage(source),
            else => {
                const append = @import("../core/image_append.zig");
                var work: append.Workspace = undefined;
                try append.append(target, image, &work);
            },
        }
        try target.interpretLine("RUN");
        try support.expectStack(target, &.{8});
        try registry.validate(target);
    }
}

test "P07 watched assignment uses token semantics rather than STATE" {
    try support.skipWithout(&.{.debug});
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try m.interpretLine("7 ~~VALUE V ' TO CONSTANT SET : M 9 SET EXECUTE ; IMMEDIATE : T M V ;");
    const t = m.words[m.lookup("T").?];
    try std.testing.expectEqual(@as(u16, 1), t.code_end - t.code_start);
    try std.testing.expect(std.mem.indexOf(u8, out.stderr_bytes[0..out.stderr_len], "V") != null);
    try m.interpretLine("T V");
    try support.expectStack(m, &.{9});
}

test "P07 assignment dictionary names and targets retain source use records" {
    try support.skipWithout(&.{ .files, .tools });
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    support.setFakeFile(&out, 0, "1 VALUE V\n2 TO V\n: M POSTPONE TO ; IMMEDIATE\n: T 3 M V ;\n");
    try m.interpretLine("S\" a.txt\" INCLUDED");
    const to = m.lookup("TO").?;
    const value = m.lookup("V").?;
    var to_uses: usize = 0;
    var value_uses: usize = 0;
    for (m.uses[0..m.use_count]) |use| {
        if (use.word == to) to_uses += 1;
        if (use.word == value) value_uses += 1;
    }
    try std.testing.expect(to_uses >= 2 and value_uses >= 2);
    try m.interpretLine("T V");
    try support.expectStack(m, &.{3});
}
