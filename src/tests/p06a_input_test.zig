const std = @import("std");
const support = @import("support.zig");
const map = @import("../core/memory_map.zig");

fn setup(m: *@import("../forth.zig").State, out: *support.Output, first: []const u8, second: []const u8) !void {
    support.setFakeFile(out, 0, first);
    support.setFakeFile(out, 1, second);
    try m.interpretLine("S\" a.txt\" R/O OPEN-FILE THROW CONSTANT A S\" b.txt\" R/O OPEN-FILE THROW CONSTANT B");
}

test "P06a borrowed input nests IDs and keeps terminal pending bytes isolated" {
    try support.skipWithout(&.{.files});
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try setup(m, &out, "AC", "B");
    m.pending_key = 'Z';
    m.pending_standard_event = 1234;
    try m.interpretLine(": INNER INFILE-ID B = KEY ; : OUTER INFILE-ID A = KEY ['] INNER B INFILE-EXECUTE KEY ; INFILE-ID STDIN = ' OUTER A INFILE-EXECUTE INFILE-ID STDIN = KEY");
    try support.expectStack(m, &.{ -1, -1, 65, -1, 66, 67, -1, 90 });
    try std.testing.expectEqual(@as(?@import("../forth.zig").Cell, 1234), m.pending_standard_event);
    try std.testing.expect(out.files[0].open and out.files[1].open);
}

test "P06a input THROW restores selection and leaves borrowed file progress intact" {
    try support.skipWithout(&.{.files});
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try setup(m, &out, "AB", "");
    try m.interpretLine(": BAD KEY DROP -123 THROW ; : RUN ['] BAD A INFILE-EXECUTE ; ' RUN CATCH INFILE-ID STDIN = A KEY-FILE");
    try support.expectStack(m, &.{ -123, -1, 66 });
    try std.testing.expect(m.input_file == null and out.files[0].open);
}

test "P06a file ACCEPT clips and drains lines without echo while numeric INPUT shares selection" {
    try support.skipWithout(&.{.files});
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try setup(m, &out, "AB\r\nCD\rE\n42\n", "");
    try m.interpretLine(": READ-LINES PAD 1 ACCEPT PAD SWAP TYPE KEY PAD 0 ACCEPT DROP KEY PAD 8 ACCEPT DROP INPUT ; ' READ-LINES A INFILE-EXECUTE");
    try support.expectStack(m, &.{ 67, 69, 42 });
    try std.testing.expectEqualStrings("A", out.written());
}

test "P06a Unicode and unread byte stay in borrowed file across selection scopes" {
    try support.skipWithout(&.{.files});
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try setup(m, &out, "日\xc3Z", "\x1b[A");
    try m.interpretLine(": U EKEY ; : X XKEY ; ' U A INFILE-EXECUTE ' X A INFILE-EXECUTE A KEY-FILE : ESC EKEY EKEY EKEY ; ' ESC B INFILE-EXECUTE");
    try support.expectStack(m, &.{ 26085, 0xfffd, 90, 27, 91, 65 });
    try std.testing.expectEqual(@as(usize, 0), out.key_index);
}

test "P06a input readiness EOF and invalid operands do not change ownership" {
    try support.skipWithout(&.{.files});
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try setup(m, &out, "A", "");
    try m.interpretLine(": R KEY? EKEY? KEY XKEY? ; ' R A INFILE-EXECUTE : K KEY ; : EOF-RUN ['] K B INFILE-EXECUTE ; ' EOF-RUN CATCH");
    try support.expectStack(m, &.{ -1, -1, 65, 0, -262 });
    m.data_depth = 0;
    try m.push(-1);
    try m.push(1234);
    try std.testing.expectError(error.InvalidExecutionToken, m.executeBuiltin(.infile_execute));
    try support.expectStack(m, &.{ -1, 1234 });
    try std.testing.expect(m.input_file == null and out.files[0].open and out.files[1].open);
}

test "P06a selected terminal REFILL and parser continuation read the borrowed stream" {
    try support.skipWithout(&.{.files});
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try setup(m, &out, "next line\n", "");
    try m.interpretLine(": REFILL-ONE REFILL ;");
    try m.push(m.lookup("REFILL-ONE").?);
    try m.push(@import("../forth.zig").first_file_id);
    try m.executeBuiltin(.infile_execute);
    try support.expectStack(m, &.{-1});
    try std.testing.expectEqualStrings("next line", m.source_line);
    try std.testing.expect(m.input_file == null);
    m.data_depth = 0;
    try m.interpretLine(": EV S\" REFILL\" EVALUATE ; ' EV B INFILE-EXECUTE");
    try support.expectStack(m, &.{0});
}

fn failedKey(_: ?*anyopaque, _: @import("../forth.zig").Cell) @import("../forth.zig").RuntimeError!@import("../forth.zig").FileKeyResult {
    return .{ .ior = map.errnoIor(5) };
}

test "P06a input errors missing hooks and same-stream nesting restore state" {
    try support.skipWithout(&.{.files});
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try setup(m, &out, "AB", "");
    try m.interpretLine(": K KEY ; : N KEY ['] K A INFILE-EXECUTE ; ' N A INFILE-EXECUTE");
    try support.expectStack(m, &.{ 65, 66 });
    m.data_depth = 0;
    var ops = support.fake_file_ops;
    ops.key = failedKey;
    m.writer.file_ops = &ops;
    try m.interpretLine(": RUN ['] K A INFILE-EXECUTE ; ' RUN CATCH");
    try support.expectStack(m, &.{map.errnoIor(5)});
    m.data_depth = 0;
    ops.ready = null;
    try m.interpretLine(": R KEY? ; : RUN-R ['] R A INFILE-EXECUTE ; ' RUN-R CATCH");
    try support.expectStack(m, &.{-263});
    try std.testing.expect(m.input_file == null and out.files[0].open);
}

test "P06a explicit STDIN shares caller pending state and long ACCEPT drains the line" {
    try support.skipWithout(&.{.files});
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try setup(m, &out, "", "");
    try m.interpretLine(": ONE KEY ;");
    m.pending_key = 'Z';
    try m.interpretLine("' ONE STDIN INFILE-EXECUTE");
    try support.expectStack(m, &.{90});
    try std.testing.expect(m.pending_key == null);
    m.data_depth = 0;
    @memset(out.files[0].data[0..5000], 'x');
    @memcpy(out.files[0].data[5000..5003], "\nY\n");
    out.files[0].len = 5003;
    try m.interpretLine(": LINE PAD 1 ACCEPT DROP KEY ; ' LINE A INFILE-EXECUTE");
    try support.expectStack(m, &.{89});
}
