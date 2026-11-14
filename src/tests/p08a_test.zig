const std = @import("std");
const support = @import("support.zig");
const map = @import("../core/memory_map.zig");
const lists = @import("../core/wordlists.zig");

test "P08a name tokens cover anonymous words links aliases restrictions and forgetting" {
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try m.interpretLine("WORDLIST CONSTANT W W SET-CURRENT : A 1 ; : TEST-BUF 2 ; FORTH-WORDLIST SET-CURRENT S\" TEST-BUF\" W FIND-NAME-IN NAME>LINK NAME>STRING TYPE : F 7 ; COMPILE-ONLY S\" F\" FIND-NAME COMPILE-ONLY? :NONAME 8 ; DUP XT>NAME NAME>INTERPRET = LATESTNT NAME>STRING NIP");
    try support.expectStack(m, &.{ -1, -1, 0 });
    try std.testing.expectEqualStrings("A", out.written());
    try m.interpretLine(": G 9 ;");
    const nt: map.Cell = @as(map.Cell, m.lookup("G").?) + 1;
    try m.interpretLine("FORGET G");
    try m.push(nt);
    try std.testing.expectError(error.InvalidExecutionToken, m.executeBuiltin(.name_to_link));
}

test "P08a case-sensitive wordlists and silent tables preserve spelling and warning policy" {
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try m.interpretLine("CS-VOCABULARY V ALSO V DEFINITIONS : Foo 7 ; : foo 8 ; Foo foo FORTH DEFINITIONS PREVIOUS TABLE CONSTANT W W SET-CURRENT : Z 1 ; : Z 2 ; FORTH-WORDLIST SET-CURRENT S\" Z\" W FIND-NAME-IN NAME>INTERPRET EXECUTE S\" z\" W FIND-NAME-IN");
    try support.expectStack(m, &.{ 7, 8, 2, 0 });
    try std.testing.expectEqualStrings("", out.written());
    try m.interpretLine("ALSO V DEFINITIONS : Foo 9 ; FORTH DEFINITIONS PREVIOUS");
    try std.testing.expectEqualStrings("WARNING: SAME NAME WORD EXISTS\n", out.written());
}

test "P08a nextname copies storage replaces noname and restores the one-shot on THROW" {
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try m.interpretLine("S\" Copied\" 2DUP NEXTNAME 0 FILL : 7 ; Copied NONAME S\" Named\" NEXTNAME 8 CONSTANT Named S\" Ignored\" NEXTNAME NONAME : 9 ; LATEST LATESTXT EXECUTE");
    try support.expectStack(m, &.{ 7, 8, 0, 9 });
    m.data_depth = 0;
    try m.interpretLine(": BAD S\" Temporary\" NEXTNAME -123 THROW ; S\" Kept\" NEXTNAME ' BAD CATCH DROP : 10 ; Kept S\" Temporary\" FIND-NAME");
    try support.expectStack(m, &.{ 10, 0 });
    try m.interpretLine("S\" Pending\" NEXTNAME :NONAME 11 ; DROP : 12 ; Pending");
    try support.expectStack(m, &.{ 10, 0, 12 });
}

test "P08a one-shot definition wordlist restores immediately and after callback errors" {
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try m.interpretLine("WORDLIST CONSTANT W W IN-WORDLIST : F [ GET-CURRENT FORTH-WORDLIST = ] LITERAL ; S\" F\" W FIND-NAME-IN NAME>INTERPRET EXECUTE : BAD -123 THROW ; : CALL-IN W IN-WORDLIST ; : R S\" BAD\" ['] CALL-IN EXECUTE-PARSING ; ' R CATCH GET-CURRENT FORTH-WORDLIST =");
    try support.expectStack(m, &.{ -1, -123, -1 });
    try m.interpretLine("VOCABULARY V 77 IN V CONSTANT Z ALSO V Z PREVIOUS");
    try support.expectStack(m, &.{ -1, -123, -1, 77 });
    try std.testing.expectError(error.InvalidDefinition, m.interpretLine("IN W : BAD-NAME 1 ;"));
    try std.testing.expect(m.lookup("BAD-NAME") == null);
}

test "P08a current context root and seal use VM cells and reject invalid current ids" {
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try m.interpretLine("WORDLIST CONSTANT W W CURRENT ! GET-CURRENT W = FORTH-WORDLIST CURRENT ! W >ORDER FORTH-WORDLIST CONTEXT ! CONTEXT @ FORTH-WORDLIST = : CHECK ROOT SEAL GET-ORDER ; CHECK");
    try support.expectStack(m, &.{ -1, -1, map.root_wordlist, 1 });
    m.setSearchOrder(&.{map.forth_wordlist});
    try m.writeCell(map.current_wordlist_address, -1);
    try std.testing.expectError(error.InvalidWordlist, m.interpretLine(": BAD 1 ;"));
    try m.writeCell(map.current_wordlist_address, map.forth_wordlist);
    m.setSearchOrder(&.{});
    try std.testing.expectError(error.SearchOrderUnderflow, m.executeBuiltin(.seal));
}

test "P08a map-vocs uses a finite snapshot and propagates callback errors" {
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try m.interpretLine("VARIABLE TIMES : VISIT DROP 1 TIMES +! WORDLIST DROP ; ' VISIT MAP-VOCS TIMES @");
    try support.expectStack(m, &.{4});
    try std.testing.expectEqual(@as(map.Cell, 7), m.wordlistCount());
    try m.interpretLine(": BAD-VISIT DROP -123 THROW ; : RUN-VISITS ['] BAD-VISIT MAP-VOCS ; ' RUN-VISITS CATCH");
    try support.expectStack(m, &.{ 4, -123 });
}

test "P08a displays list names and filters mwords without changing Sigma WORDS order" {
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try m.interpretLine("WORDLIST CONSTANT W W SET-CURRENT : Alpha 1 ; : Beta 2 ; : AlphaBeta 3 ; FORTH-WORDLIST SET-CURRENT W >ORDER MWORDS Alpha");
    try std.testing.expectEqualStrings("Alpha AlphaBeta \n", out.written());
    out.len = 0;
    try m.interpretLine("VLIST PREVIOUS W .VOC S\" W\" FIND-NAME .ID");
    try std.testing.expectEqualStrings("Alpha Beta AlphaBeta \nW W ", out.written());
}

test "P08a case policy and vocabulary targets survive all image routes with list rebasing" {
    var out = support.Output{};
    const source = try support.createMachine(&out);
    defer support.destroyMachine(source);
    try source.interpretLine("CS-VOCABULARY V ALSO V DEFINITIONS : Foo 7 ; : foo 8 ; FORTH DEFINITIONS PREVIOUS TABLE DROP");
    const image = try std.testing.allocator.alloc(u8, try source.encodedSize());
    defer std.testing.allocator.free(image);
    _ = try source.encodeImage(image);
    for (0..3) |mode| {
        const m = try support.createMachine(&out);
        defer support.destroyMachine(m);
        try m.interpretLine("CS-WORDLIST DROP");
        switch (mode) {
            0 => try m.restoreImage(image),
            1 => try m.appendImage(source),
            else => {
                const append = @import("../core/image_append.zig");
                var work: append.Workspace = undefined;
                try append.append(m, image, &work);
            },
        }
        try m.interpretLine("ALSO V Foo foo FORTH PREVIOUS");
        try support.expectStack(m, &.{ 7, 8 });
        const wid = m.words[m.lookup("V").?].value;
        try std.testing.expectEqual(@as(map.Cell, if (mode == 0) 4 else 5), wid);
        try std.testing.expect(lists.caseSensitive(m, wid));
        try std.testing.expect(lists.silent(m, wid + 1));
        try std.testing.expect(lists.caseSensitive(m, wid + 1));
    }
}

test "P08a invalid persisted wordlist policies fail before dictionary mutation" {
    const format = @import("../core/image_format.zig");
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try m.interpretLine(": KEEP 42 ;");
    const image = try std.testing.allocator.alloc(u8, try m.encodedSize());
    defer std.testing.allocator.free(image);
    _ = try m.encodeImage(image);
    std.mem.writeInt(u64, image[format.header_size + @as(usize, m.word_count) * @sizeOf(@import("../core/defs.zig").Word) + @as(usize, m.code_count) * @sizeOf(@import("../core/defs.zig").Op) + m.names_used + @as(usize, @intCast(map.case_wordlists_address)) ..][0..8], 1 << 63, .little);
    try format.finish(image);
    try std.testing.expectError(error.InvalidImage, m.restoreImage(image));
    try m.interpretLine("KEEP");
    try support.expectStack(m, &.{42});
}

test "P08a optional MWORDS pattern never consumes the next included line" {
    try support.skipWithout(&.{.files});
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try m.interpretLine("WORDLIST CONSTANT W W SET-CURRENT : Alpha 1 ; FORTH-WORDLIST SET-CURRENT W >ORDER");
    support.setFakeFile(&out, 0, "MWORDS\nPREVIOUS\n42\n");
    try m.interpretLine("INCLUDE a.txt");
    try std.testing.expectEqualStrings("Alpha \n", out.written());
    try support.expectStack(m, &.{42});
    try std.testing.expectEqual(map.forth_wordlist, m.searchOrderEntry(0));
}

test "P08a compile-only metadata covers controls and aliases without restricting postponed brackets" {
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try m.interpretLine("S\" IF\" FIND-NAME COMPILE-ONLY? SYNONYM COND IF S\" COND\" FIND-NAME COMPILE-ONLY? S\" TO\" FIND-NAME COMPILE-ONLY? S\" ]]\" FIND-NAME COMPILE-ONLY? : M [ ]] DUP [[ ; IMMEDIATE : T 7 M ; T");
    try support.expectStack(m, &.{ -1, -1, 0, 0, 7, 7 });
}

test "P08a last wordlist flag bit persists and capacity failure leaves allocation unchanged" {
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    while (m.wordlistCount() < map.max_wordlists) {
        try m.executeBuiltin(.table_wordlist);
        _ = try m.pop();
    }
    try std.testing.expect(lists.caseSensitive(m, 64));
    try std.testing.expect(lists.silent(m, 64));
    try std.testing.expectError(error.DictionaryFull, m.executeBuiltin(.cs_wordlist));
    try std.testing.expectEqual(@as(map.Cell, 64), m.wordlistCount());
    try support.expectStack(m, &.{});
    const image = try std.testing.allocator.alloc(u8, try m.encodedSize());
    defer std.testing.allocator.free(image);
    _ = try m.encodeImage(image);
    try m.restoreImage(image);
    try std.testing.expect(lists.caseSensitive(m, 64));
    try std.testing.expect(lists.silent(m, 64));
}
