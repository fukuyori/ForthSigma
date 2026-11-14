const std = @import("std");
const support = @import("support.zig");

test "P06b SH consumes line remainder prints newline and stores SYSTEM status" {
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try m.interpretLine("17 SH exit 3");
    try std.testing.expectEqualStrings("exit 3", out.command[0..out.command_len]);
    try std.testing.expectEqualStrings("\n", out.written());
    try m.interpretLine("$?");
    try support.expectStack(m, &.{ 17, 768 });
    try m.interpretLine(": SHELL-LINE SH ; SHELL-LINE echo 日本語  123");
    try std.testing.expectEqualStrings("echo 日本語  123", out.command[0..out.command_len]);
    try support.expectStack(m, &.{ 17, 768 });
}

test "P06b SH parses empty and NUL-delimited remainder like zero PARSE" {
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try m.interpretLine("SH");
    try std.testing.expectEqual(@as(usize, 0), out.command_len);
    try m.interpretLine("SH true\x00 42");
    try std.testing.expectEqualStrings("true", out.command[0..out.command_len]);
    try support.expectStack(m, &.{42});
}

test "P06b SH errors preserve prior status and output errors prevent shell execution" {
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    m.system_status = 99;
    try std.testing.expectError(error.HostFailed, m.interpretLine("SH fail"));
    try std.testing.expectEqual(@as(@import("../forth.zig").Cell, 99), m.system_status);
    m.writer.system_fn = null;
    const before = out.len;
    try std.testing.expectError(error.HostUnavailable, m.interpretLine("SH true"));
    try std.testing.expectEqual(before, out.len);
    m.writer.system_fn = support.Output.system;
    if (@import("build_options").files) {
        try m.interpretLine("S\" a.txt\" W/O CREATE-FILE THROW CONSTANT A : RUN-SH SH ; : RUN ['] RUN-SH A OUTFILE-EXECUTE ;");
        out.write_fails_at = out.file_writes + 1;
        out.command_len = 0;
        try std.testing.expectError(error.Thrown, m.interpretLine("RUN exit 3"));
        try std.testing.expectEqual(@as(usize, 0), out.command_len);
        try std.testing.expect(m.output_file == null);
    }
}

test "P06b SH snapshots EVALUATE text aliased to a growing capture owner and works without stack headroom" {
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try m.interpretLine("VARIABLE V S\" SH exit 3       \" V $! : RUN-SH V $@ EVALUATE ; ' RUN-SH V $EXEC");
    try std.testing.expectEqualStrings("exit 3       ", out.command[0..out.command_len]);
    try m.interpretLine("V $.");
    try std.testing.expectEqualStrings("SH exit 3       \n", out.written());
    try std.testing.expect(m.capture_target == null);
    m.data_depth = m.data_stack.len;
    try m.interpretLine("SH true");
    try std.testing.expectEqualStrings("true", out.command[0..out.command_len]);
}
