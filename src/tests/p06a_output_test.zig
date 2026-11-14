const std = @import("std");
const support = @import("support.zig");
const map = @import("../core/memory_map.zig");

fn setup(m: *@import("../forth.zig").State) !void {
    try m.interpretLine("S\" a.txt\" W/O CREATE-FILE THROW CONSTANT A S\" b.txt\" W/O CREATE-FILE THROW CONSTANT B");
}

test "P06a output IDs nested destinations and borrowed handles" {
    try support.skipWithout(&.{.files});
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try setup(m);
    try m.interpretLine(": INNER OUTFILE-ID B = 66 EMIT ; : OUTER OUTFILE-ID A = 65 EMIT ['] INNER B OUTFILE-EXECUTE OUTFILE-ID A = 67 EMIT ; OUTFILE-ID STDOUT = ' OUTER A OUTFILE-EXECUTE OUTFILE-ID STDOUT =");
    try support.expectStack(m, &.{ -1, -1, -1, -1, -1 });
    try std.testing.expectEqualStrings("AC", out.files[0].data[0..out.files[0].len]);
    try std.testing.expectEqualStrings("B", out.files[1].data[0..out.files[1].len]);
    try std.testing.expect(out.files[0].open and out.files[1].open);
    try std.testing.expect(m.output_file == null and m.output_error == null);
}

test "P06a output exceptions restore destination and retain already written bytes" {
    try support.skipWithout(&.{.files});
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try setup(m);
    try m.interpretLine(": BAD 65 EMIT -123 THROW ; : RUN ['] BAD A OUTFILE-EXECUTE ; ' RUN CATCH OUTFILE-ID STDOUT = 90 EMIT");
    try support.expectStack(m, &.{ -123, -1 });
    try std.testing.expectEqualStrings("A", out.files[0].data[0..out.files[0].len]);
    try std.testing.expectEqualStrings("Z", out.written());
    try std.testing.expect(out.files[0].open);
}

test "P06a output nesting composes with caller-owned capture in both directions" {
    try support.skipWithout(&.{.files});
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try setup(m);
    try m.interpretLine(": TXT 88 EMIT ; : FILE-OUT ['] TXT A OUTFILE-EXECUTE 89 EMIT ; ' FILE-OUT >STRING-EXECUTE OVER >R TYPE R> FREE THROW");
    try std.testing.expectEqualStrings("X", out.files[0].data[0..out.files[0].len]);
    try std.testing.expectEqualStrings("Y", out.written());
    out.len = 0;
    try m.interpretLine(": CAPTURE ['] TXT >STRING-EXECUTE OVER >R TYPE R> FREE THROW ; ' CAPTURE B OUTFILE-EXECUTE");
    try std.testing.expectEqualStrings("X", out.files[1].data[0..out.files[1].len]);
    try std.testing.expectEqualStrings("", out.written());
}

test "P06a output errors are caught inside callback for EMIT and compiled print strings" {
    try support.skipWithout(&.{.files});
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try setup(m);
    try m.interpretLine(": EM 65 EMIT ; : TXT .\" text\" ; : HANDLE ['] EM CATCH ;");
    out.write_fails_at = out.file_writes + 1;
    try m.interpretLine("' HANDLE A OUTFILE-EXECUTE");
    try support.expectStack(m, &.{map.errnoIor(28)});
    m.data_depth = 0;
    out.write_fails_at = out.file_writes + 1;
    try m.interpretLine(": RUN ['] TXT A OUTFILE-EXECUTE ; ' RUN CATCH OUTFILE-ID STDOUT =");
    try support.expectStack(m, &.{ map.errnoIor(28), -1 });
    try std.testing.expect(m.output_error == null);
}

test "P06a output invalid tokens and closed files restore prior state without closing borrowed files" {
    try support.skipWithout(&.{.files});
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try setup(m);
    try m.push(-1);
    try m.push(12345);
    try std.testing.expectError(error.InvalidExecutionToken, m.executeBuiltin(.outfile_execute));
    try support.expectStack(m, &.{ -1, 12345 });
    try std.testing.expect(m.output_file == null);
    m.data_depth = 0;
    try m.interpretLine(": TXT 65 EMIT ; A CLOSE-FILE THROW : RUN ['] TXT A OUTFILE-EXECUTE ; ' RUN CATCH");
    try support.expectStack(m, &.{map.errnoIor(map.errno_bad_file)});
    try std.testing.expect(m.output_file == null and m.output_error == null);
    try std.testing.expect(out.files[1].open);
    m.data_depth = m.data_stack.len;
    try std.testing.expectError(error.StackOverflow, m.executeBuiltin(.outfile_id));
}

test "P06a explicit STDOUT output prevents SHOW from overwriting intervening text" {
    try support.skipWithout(&.{ .files, .graphics });
    var out = support.Output{ .terminal_columns = 80, .terminal_rows = 24 };
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try setup(m);
    try m.interpretLine("REQUIRE-GRAPHICS ALSO GRAPHICS 2 2 GFX-INIT : TXT 65 EMIT ; GFX-SHOW-BLOCKS");
    const mark = m.output_count;
    try m.interpretLine("' TXT A OUTFILE-EXECUTE");
    try std.testing.expectEqual(mark, m.output_count);
    try m.interpretLine("' TXT >STRING-EXECUTE DROP FREE THROW");
    try std.testing.expectEqual(mark, m.output_count);
    try m.interpretLine("' TXT STDOUT OUTFILE-EXECUTE");
    try std.testing.expectEqualStrings("A", out.stdout_bytes[0..out.stdout_len]);
    try std.testing.expectEqual(mark + 1, m.output_count);
    out.len = 0;
    try m.interpretLine("GFX-SHOW-BLOCKS");
    try std.testing.expect(std.mem.indexOf(u8, out.written(), "\x1b[1A") == null);
}
