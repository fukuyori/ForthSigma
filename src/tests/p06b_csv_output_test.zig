const std = @import("std");
const support = @import("support.zig");
const map = @import("../core/memory_map.zig");

fn quote(m: *@import("../forth.zig").State, bytes: []const u8) !void {
    @memcpy(m.memory[@intCast(map.string_buffer_base)..][0..bytes.len], bytes);
    try m.push(map.string_buffer_base);
    try m.push(@intCast(bytes.len));
    try m.executeBuiltin(.dot_quoted_csv);
}

test "P06b CSV values support interpreted compiled TO and PLUS TO with quoted binary output" {
    try support.skipWithout(&.{.files});
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try m.interpretLine("CSV-QUOTE CSV-SEPARATOR : CONFIG 39 TO CSV-QUOTE 59 TO CSV-SEPARATOR ; CONFIG CSV-QUOTE CSV-SEPARATOR 1 +TO CSV-SEPARATOR");
    try support.expectStack(m, &.{ 34, 44, 39, 59 });
    try quote(m, "a'b\x00\n");
    try std.testing.expectEqualStrings("'a''b\x00\n'", out.written());
    try std.testing.expectEqual(@as(map.Cell, 60), try m.readCell(map.csv_separator_address));
}

test "P06b CSV output always encloses fields doubles quotes and adds no separator or newline" {
    try support.skipWithout(&.{.files});
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try quote(m, "");
    try quote(m, "a\"b,\r\n日本語");
    try std.testing.expectEqualStrings("\"\"\"a\"\"b,\r\n日本語\"", out.written());
    out.len = 0;
    try m.interpretLine("256 TO CSV-QUOTE");
    try quote(m, "\x00");
    try std.testing.expectEqualStrings("\x00\x00\x00", out.written());
}

test "P06b CSV capture snapshots input that aliases the growing output owner" {
    try support.skipWithout(&.{.files});
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try m.interpretLine("VARIABLE V S\" ab\" V $! : CSV-APPEND V $@ .QUOTED-CSV ; ' CSV-APPEND V $EXEC V $.");
    try std.testing.expectEqualStrings("ab\"ab\"", out.written());
    try std.testing.expect(m.capture_target == null and m.capture_sink == null);
}

test "P06b CSV settings persist in full images and remain destination settings through both append routes" {
    try support.skipWithout(&.{.files});
    const append = @import("../core/image_append.zig");
    var out = support.Output{};
    const source = try support.createMachine(&out);
    defer support.destroyMachine(source);
    const target = try support.createMachine(&out);
    defer support.destroyMachine(target);
    try source.interpretLine("39 TO CSV-QUOTE 59 TO CSV-SEPARATOR : READ-SETTINGS CSV-QUOTE CSV-SEPARATOR ; : SET-QUOTE 42 TO CSV-QUOTE ;");
    const image = try std.testing.allocator.alloc(u8, try source.encodedSize());
    defer std.testing.allocator.free(image);
    _ = try source.encodeImage(image);
    try target.restoreImage(image);
    try target.interpretLine("READ-SETTINGS");
    try support.expectStack(target, &.{ 39, 59 });
    target.data_depth = 0;
    try target.interpretLine("35 TO CSV-QUOTE 58 TO CSV-SEPARATOR");
    try target.appendImage(source);
    var work: append.Workspace = undefined;
    try append.append(target, image, &work);
    try target.interpretLine("READ-SETTINGS SET-QUOTE CSV-QUOTE");
    try support.expectStack(target, &.{ 35, 58, 42 });
}

test "P06b CSV image validation rejects a changed builtin VALUE address before restore mutation" {
    try support.skipWithout(&.{.files});
    var out = support.Output{};
    const source = try support.createMachine(&out);
    defer support.destroyMachine(source);
    const target = try support.createMachine(&out);
    defer support.destroyMachine(target);
    const image = try std.testing.allocator.alloc(u8, try source.encodedSize());
    defer std.testing.allocator.free(image);
    _ = try source.encodeImage(image);
    const format = @import("../core/image_format.zig");
    const defs = @import("../core/defs.zig");
    const at = format.header_size + @as(usize, source.lookup("CSV-QUOTE").?) * @sizeOf(defs.Word) + @offsetOf(defs.Word, "value");
    std.mem.writeInt(map.Cell, image[at..][0..8], map.data_start, @import("builtin").cpu.arch.endian());
    try format.finish(image);
    const words = target.word_count;
    try std.testing.expectError(error.InvalidImage, target.restoreImage(image));
    try std.testing.expectEqual(words, target.word_count);
    try std.testing.expectEqual(@as(map.Cell, 34), try target.readCell(map.csv_quote_address));
}

test "P06b omitted CSV VALUE slots keep image shape but cannot execute" {
    if (@import("build_options").files) return error.SkipZigTest;
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    const id: u16 = for (m.words[0..m.builtin_count], 0..) |word, index| {
        if (word.builtin == .csv_quote) break @intCast(index);
    } else unreachable;
    try std.testing.expect(m.lookup("CSV-QUOTE") == null);
    try std.testing.expectEqual(@import("../core/defs.zig").WordKind.value, m.words[id].kind);
    try std.testing.expectError(error.InvalidExecutionToken, m.executeWord(id));
    const image = try std.testing.allocator.alloc(u8, try m.encodedSize());
    defer std.testing.allocator.free(image);
    _ = try m.encodeImage(image);
    try m.restoreImage(image);
}
