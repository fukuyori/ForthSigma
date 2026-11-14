const std = @import("std");
const support = @import("support.zig");
const map = @import("../core/memory_map.zig");
const registry = @import("../core/address_registry.zig");

test "P07d scoped parsing restores input after success nested calls and THROW" {
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try m.interpretLine(": P PARSE-NAME TYPE ; : Q S\" inner\" ['] P EXECUTE-PARSING PARSE-NAME TYPE ; S\" outer\" ' Q EXECUTE-PARSING : BAD PARSE-NAME 2DROP -123 THROW ; : R S\" abc\" ['] BAD EXECUTE-PARSING ; : T ['] R CATCH PARSE-NAME TYPE ; T tail");
    try std.testing.expectEqualStrings("inneroutertail", out.written());
    try support.expectStack(m, &.{-123});
    try std.testing.expectEqual(@as(usize, 0), m.include_depth);
}

test "P07d execute parsing does not interpret the string and supports defining callbacks" {
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try m.interpretLine(": P 9 ; S\" UNKNOWN\" ' P EXECUTE-PARSING 5 S\" FOO\" ' CONSTANT EXECUTE-PARSING FOO : A NAME TYPE ; : B PARSE-WORD TYPE ; A abc B xyz");
    try support.expectStack(m, &.{ 9, 5 });
    try std.testing.expectEqualStrings("abcxyz", out.written());
}

test "P07d string parse handles empty missing overlapping and binary delimiters" {
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try m.interpretLine(": P S\" ::\" STRING-PARSE TYPE >IN @ ; S\" abc::rest\" ' P EXECUTE-PARSING : E S\" \" STRING-PARSE NIP >IN @ ; S\" abc\" ' E EXECUTE-PARSING");
    try support.expectStack(m, &.{ 5, 0, 0 });
    try std.testing.expectEqualStrings("abc", out.written());
    m.data_depth = 0;
    try m.interpretLine(": N S\" xxx\" STRING-PARSE NIP >IN @ ; S\" ab\" ' N EXECUTE-PARSING");
    try support.expectStack(m, &.{ 2, 2 });
}

test "P07d scope preserves raw cursor source identity line serial and block state" {
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try m.interpretLine(": P SOURCE-ID REFILL ; S\" inner\"");
    const addr = try m.peek(1);
    const len = try m.peek(0);
    m.data_depth = 0;
    const old = m.source_line;
    const kind = m.source_kind;
    const serial = m.input_line_serial;
    try m.writeCell(map.in_address, 7777);
    try m.writeCell(map.blk_address, 42);
    try m.push(addr);
    try m.push(len);
    try m.push(m.lookup("P").?);
    try m.executeBuiltin(.execute_parsing);
    try support.expectStack(m, &.{ -1, 0 });
    try std.testing.expectEqual(@as(map.Cell, 7777), try m.readCell(map.in_address));
    try std.testing.expectEqual(@as(map.Cell, 42), try m.readCell(map.blk_address));
    try std.testing.expectEqual(serial, m.input_line_serial);
    try std.testing.expectEqual(kind, m.source_kind);
    try std.testing.expectEqual(old.ptr, m.source_line.ptr);
}

test "P07d file parsing starts empty refills privately and closes its owned file" {
    try support.skipWithout(&.{.files});
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    support.setFakeFile(&out, 0, "abc def\nsecond line\n");
    try m.interpretLine("S\" a.txt\" R/O OPEN-FILE THROW CONSTANT F : P SOURCE NIP >IN @ SOURCE-ID F = REFILL PARSE-NAME TYPE REFILL PARSE-NAME TYPE REFILL ; F ' P EXECUTE-PARSING-FILE");
    try support.expectStack(m, &.{ 0, 0, -1, -1, -1, 0 });
    try std.testing.expectEqualStrings("abcsecond", out.written());
    try std.testing.expect(!out.files[0].open);
    try std.testing.expectEqual(@as(usize, 0), m.include_depth);
}

test "P07d file failure cleanup prioritizes callback errors and preflight retains ownership" {
    try support.skipWithout(&.{.files});
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    support.setFakeFile(&out, 0, "abc\n");
    try m.interpretLine("S\" a.txt\" R/O OPEN-FILE THROW CONSTANT F : BAD REFILL DROP -123 THROW ; : R F ['] BAD EXECUTE-PARSING-FILE ;");
    out.close_fails = true;
    try m.interpretLine("' R CATCH");
    try support.expectStack(m, &.{-123});
    try std.testing.expect(!out.files[0].open);
    try std.testing.expectEqual(@as(usize, 0), m.include_depth);
    out.close_fails = false;
    m.data_depth = 0;
    try m.interpretLine("S\" a.txt\" R/O OPEN-FILE THROW");
    const id = try m.peek(0);
    try m.push(-1);
    try std.testing.expectError(error.InvalidExecutionToken, m.executeBuiltin(.execute_parsing_file));
    try std.testing.expect(out.files[0].open);
    m.data_depth = 0;
    try m.push(id);
    try m.push(m.builtinWord(.noop));
    out.close_fails = true;
    try std.testing.expectError(error.Thrown, m.executeBuiltin(.execute_parsing_file));
    try std.testing.expectEqual(map.errnoIor(5), m.throw_code);
    try std.testing.expect(!out.files[0].open);
}

test "P07d forward resolution patches calls while preserving old execution token identity" {
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try m.interpretLine("FORWARD F : T F ; : TOKEN ['] F ; : RUN T ; ' RUN CATCH : F 7 ; T TOKEN ' F = TOKEN EXECUTE .UNRESOLVED");
    try support.expectStack(m, &.{ -259, 7, 0, 7 });
    try std.testing.expectEqualStrings("", out.stderr_bytes[0..out.stderr_len]);
}

test "P07d forwards are colon-only same-wordlist and report unresolved declarations" {
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try m.interpretLine("FORWARD F : BAD S\" 7 CONSTANT F\" EVALUATE ; ' BAD CATCH .UNRESOLVED WORDLIST CONSTANT W W SET-CURRENT : F 7 ; FORTH-WORDLIST SET-CURRENT");
    try support.expectStack(m, &.{-259});
    try std.testing.expect(std.mem.indexOf(u8, out.stderr_bytes[0..out.stderr_len], "F is unresolved") != null);
    try m.interpretLine(": F 8 ; F");
    try support.expectStack(m, &.{ -259, 8 });
}

test "P07d FORGET unbinds a removed forward target and later colon resolution repairs calls" {
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try m.interpretLine("FORWARD F : T F ; : F 7 ; T FORGET F ' T CATCH : F 8 ; T");
    try support.expectStack(m, &.{ 7, -259, 8 });
    try registry.validate(m);
}

test "P07d recursive maintains Sigma self-visibility and enforces compile state" {
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try m.interpretLine(": FACT RECURSIVE DUP IF DUP 1- FACT * ELSE DROP 1 THEN ; 5 FACT : IMPLICIT DUP IF 1- IMPLICIT ELSE DROP 9 THEN ; 2 IMPLICIT");
    try support.expectStack(m, &.{ 120, 9 });
    try std.testing.expectError(error.CompileOnly, m.executeBuiltin(.recursive_word));
}

test "P07d forward bindings and old typed xts persist through restore and both append routes" {
    var out = support.Output{};
    const source = try support.createMachine(&out);
    defer support.destroyMachine(source);
    try source.interpretLine("FORWARD F : T F ; : TOKEN ['] F ; : F 7 ; FORWARD LATER : U LATER ;");
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
                const app = @import("../core/image_append.zig");
                var w: app.Workspace = undefined;
                try app.append(m, image, &w);
            },
        }
        try m.interpretLine("T TOKEN EXECUTE : LATER 8 ; U");
        try support.expectStack(m, &.{ 7, 7, 8 });
        try registry.validate(m);
    }
}

test "P07d parsing accepts a binary delimiter without decoding bytes" {
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    const base: usize = @intCast(map.string_buffer_base);
    @memcpy(m.memory[base..][0..7], "ab\x00tail");
    m.memory[base + 32] = 0;
    m.source_line = m.memory[base..][0..7];
    m.source_kind = .evaluate;
    m.setSourceCursor(0);
    try m.push(@intCast(base + 32));
    try m.push(1);
    try m.executeBuiltin(.string_parse);
    try support.expectStack(m, &.{ @intCast(base), 2 });
    try std.testing.expectEqual(@as(usize, 3), m.sourceCursor());
}

test "P07d malformed forward destination is rejected before dictionary replacement" {
    const format = @import("../core/image_format.zig");
    const Word = @import("../core/defs.zig").Word;
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try m.interpretLine("FORWARD F : F 7 ;");
    const id = m.lookup("F").?;
    const image = try std.testing.allocator.alloc(u8, try m.encodedSize());
    defer std.testing.allocator.free(image);
    _ = try m.encodeImage(image);
    image[format.header_size + @as(usize, id) * @sizeOf(Word) + @offsetOf(Word, "kind")] = 255;
    try format.finish(image);
    try std.testing.expectError(error.InvalidImage, m.restoreImage(image));
    try m.interpretLine("F");
    try support.expectStack(m, &.{7});
}
