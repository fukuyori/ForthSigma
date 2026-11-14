const std = @import("std");
const support = @import("support.zig");
const forth = @import("../forth.zig");
const map = @import("../core/memory_map.zig");
const keys = @import("../core/standard_keys.zig");

test "P06c all standard names and new EKEYS constants classify without heap allocation" {
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    const top = m.heapTop();
    for (keys.names, 0..) |name, i| {
        const code: map.Cell = keys.special + @as(map.Cell, @intCast(i));
        try std.testing.expect(keys.isFunction(code | keys.shift | keys.ctrl | keys.alt));
        try m.push(code);
        try m.executeBuiltin(.simple_fkey_string);
        const len: usize = @intCast(try m.pop());
        const at: usize = @intCast(try m.pop());
        try std.testing.expectEqualStrings(name, m.memory[at..][0..len]);
    }
    try m.interpretLine("K-ENTER K-EOF K-WINCH K-PAUSE K-MUTE K-VOLUP K-VOLDOWN K-BACKSPACE K-TAB K-SEL");
    try support.expectStack(m, &.{ keys.special + 10, keys.eof, keys.winch, keys.special + 24, keys.special + 25, keys.special + 26, keys.special + 27, keys.special + 28, keys.tab, keys.special + 30 });
    try std.testing.expectEqual(top, m.heapTop());
}

test "P06c names remain stable and FKEY prints modifiers in shift ctrl alt order" {
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try m.interpretLine("K-UP SIMPLE-FKEY-STRING K-DOWN SIMPLE-FKEY-STRING 2DROP TYPE K-TAB K-SHIFT-MASK OR K-CTRL-MASK OR K-ALT-MASK OR FKEY.");
    try std.testing.expectEqualStrings("k-upk-tab k-shift-mask or k-ctrl-mask or k-alt-mask or", out.written());
    for ([_]map.Cell{ -1, 65, keys.special + 34, keys.special | keys.shift }) |invalid| {
        try m.push(invalid);
        try std.testing.expectError(error.Thrown, m.executeBuiltin(.simple_fkey_string));
        try std.testing.expectEqual(@as(map.Cell, -24), m.throw_code);
        try std.testing.expectEqual(invalid, try m.pop());
    }
}

test "P06c FORM uses physical fallback redirected and virtual capture dimensions" {
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    out.terminal_columns = 113;
    out.terminal_rows = 41;
    try m.executeBuiltin(.form);
    try support.expectStack(m, &.{ 41, 113 });
    m.data_depth = 0;
    m.output_file = forth.first_file_id;
    try m.executeBuiltin(.form);
    try support.expectStack(m, &.{ 24, 80 });
    m.data_depth = 0;
    m.output_file = null;
    out.terminal_columns = 0;
    try m.executeBuiltin(.form);
    try support.expectStack(m, &.{ 24, 80 });
    m.data_depth = 0;
    m.capture_target = map.tmp_string_base;
    try m.executeBuiltin(.form);
    try support.expectStack(m, &.{ 1, std.math.maxInt(map.Cell) });
    m.capture_target = null;
}

test "P06c relative movement handles signs zero minimum cell and rejects capture before output" {
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try m.interpretLine("1 2 AT-DELTAXY -3 -4 AT-DELTAXY 0 0 AT-DELTAXY -9223372036854775808 0 AT-DELTAXY");
    try std.testing.expectEqualStrings("\x1b[1C\x1b[2B\x1b[3D\x1b[4A\x1b[9223372036854775808D", out.written());
    out.len = 0;
    try m.push(1);
    try m.push(2);
    m.capture_target = map.tmp_string_base;
    try std.testing.expectError(error.Thrown, m.executeBuiltin(.at_deltaxy));
    try std.testing.expectEqual(@as(map.Cell, -21), m.throw_code);
    try support.expectStack(m, &.{ 1, 2 });
    try std.testing.expectEqualStrings("", out.written());
    m.capture_target = null;
}

fn failedKey(_: ?*anyopaque) forth.RuntimeError!forth.FileKeyResult {
    return .{ .ior = -999 };
}
fn interruptKey(_: ?*anyopaque) forth.RuntimeError!forth.FileKeyResult {
    return error.UserInterrupt;
}

test "P06c KEY-IOR shares pending bytes returns EOF and errors and preserves interrupts" {
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    out.keys = "A\x00";
    m.pending_key = 'Z';
    m.pending_standard_event = keys.winch;
    try m.interpretLine("KEY-IOR KEY-IOR KEY-IOR KEY-IOR EKEY EKEY EKEY?");
    try support.expectStack(m, &.{ 90, 65, 0, -512, keys.winch, keys.eof, 0 });
    m.data_depth = 0;
    m.writer.key_ior_fn = failedKey;
    try m.executeBuiltin(.key_ior);
    try support.expectStack(m, &.{-999});
    m.data_depth = 0;
    m.writer.key_ior_fn = interruptKey;
    try std.testing.expectError(error.UserInterrupt, m.executeBuiltin(.key_ior));
    m.data_depth = m.data_stack.len;
    out.key_index = 0;
    try std.testing.expectError(error.StackOverflow, m.executeBuiltin(.key_ior));
    try std.testing.expectEqual(@as(usize, 0), out.key_index);
}

test "P06c selected file KEY-IOR and EKEY EOF differ from legacy KEY and Shift Tab decodes" {
    try support.skipWithout(&.{.files});
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    support.setFakeFile(&out, 0, "");
    try m.interpretLine("S\" a.txt\" R/O OPEN-FILE THROW CONSTANT A : READ-END KEY-IOR EKEY? EKEY ; ' READ-END A INFILE-EXECUTE");
    try support.expectStack(m, &.{ -512, 0, keys.eof });
    m.data_depth = 0;
    out.keys = "\x1b[Z\r\t\x7f";
    try m.interpretLine("EKEY EKEY EKEY EKEY");
    try support.expectStack(m, &.{ keys.tab | keys.shift, 13, 9, 127 });
}

test "P06c key names persist through images and GRAPHICS keeps independent arrow values" {
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    const image = try std.testing.allocator.alloc(u8, try m.encodedSize());
    defer std.testing.allocator.free(image);
    _ = try m.encodeImage(image);
    try m.restoreImage(image);
    try m.interpretLine("K-ENTER SIMPLE-FKEY-STRING TYPE");
    try std.testing.expectEqualStrings("k-enter", out.written());
    if (@import("build_options").graphics) {
        try m.interpretLine("REQUIRE-GRAPHICS ALSO GRAPHICS K-UP PREVIOUS K-UP");
        try support.expectStack(m, &.{ 256, keys.special + 2 });
    }
}

test "P06c typed key-name references retain fixed addresses through dictionary append" {
    var out = support.Output{};
    const source = try support.createMachine(&out);
    defer support.destroyMachine(source);
    const target = try support.createMachine(&out);
    defer support.destroyMachine(target);
    try source.interpretLine("K-UP SIMPLE-FKEY-STRING DROP ACONSTANT KEY-NAME-PTR : SHOW-KEY-NAME KEY-NAME-PTR 4 TYPE ;");
    try target.interpretLine(": BEFORE 42 ;");
    try target.appendImage(source);
    try target.interpretLine("SHOW-KEY-NAME");
    try std.testing.expectEqualStrings("k-up", out.written());
    const image = try std.testing.allocator.alloc(u8, try target.encodedSize());
    defer std.testing.allocator.free(image);
    _ = try target.encodeImage(image);
    try target.restoreImage(image);
    out.len = 0;
    try target.interpretLine("SHOW-KEY-NAME");
    try std.testing.expectEqualStrings("k-up", out.written());
}
