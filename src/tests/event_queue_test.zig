const std = @import("std");
const support = @import("support.zig");
const forth = @import("../forth.zig");
const ev = @import("../core/standard_event.zig");
const keys = @import("../core/standard_keys.zig");
const base = @import("../core/runtime_base.zig");
const Item = struct { at: i128 = 0, result: ev.Result };
const Fake = struct {
    items: []const Item = &.{},
    index: usize = 0,
    now: i128 = 0,
    eof: bool = false,
    failed_clock: bool = false,
    fn clock(context: ?*anyopaque) base.Error!i128 {
        const self: *Fake = @ptrCast(@alignCast(context.?));
        if (self.failed_clock) return error.HostFailed;
        return self.now;
    }
    fn read(context: ?*anyopaque, timeout: i32) forth.RuntimeError!ev.Result {
        const self: *Fake = @ptrCast(@alignCast(context.?));
        const limit = if (timeout < 0) std.math.maxInt(i128) else self.now + @as(i128, timeout) * 1_000_000;
        if (self.index < self.items.len and self.items[self.index].at <= limit) {
            const item = self.items[self.index];
            self.index += 1;
            self.now = @max(self.now, item.at);
            return item.result;
        }
        if (self.eof) return .eof;
        if (timeout > 0) self.now = limit;
        return .timeout;
    }
    fn source(self: *Fake) ev.Source {
        return .{ .context = self, .read_fn = read, .clock = .{ .context = self, .now_fn = clock } };
    }
};
fn value(result: ev.Result) !forth.Cell {
    return switch (result) {
        .event => |packet| packet.value,
        else => error.TestUnexpectedResult,
    };
}
fn bytes(comptime text: []const u8) [text.len]Item {
    var result: [text.len]Item = undefined;
    for (text, 0..) |byte, i| result[i] = .{ .result = .{ .event = .{ .value = byte } } };
    return result;
}

test "event deadline holds split UTF8 and ESC across calls without extending escape age" {
    var fake = Fake{ .items = &.{ .{ .result = .{ .event = .{ .value = 0xe6 } } }, .{ .at = 3_000_000, .result = .{ .event = .{ .value = 0x97 } } }, .{ .at = 20_000_000, .result = .{ .event = .{ .value = 0xa5 } } } } };
    var decoder = ev.Decoder{};
    try std.testing.expect((try ev.read(&decoder, fake.source(), 5, false)) == .timeout);
    try std.testing.expectEqual(@as(usize, 2), decoder.length);
    try std.testing.expectEqual(@as(forth.Cell, 26085), try value(try ev.read(&decoder, fake.source(), 30, false)));
    var escape = Fake{ .items = &bytes("\x1b") };
    decoder = .{};
    try std.testing.expect((try ev.read(&decoder, escape.source(), 10, false)) == .timeout);
    try std.testing.expectEqual(@as(forth.Cell, 27), try value(try ev.read(&decoder, escape.source(), 100, false)));
    try std.testing.expectEqual(@as(i128, 50_000_000), escape.now);
}

test "peeking native mouse preserves last consumed metadata and event ordering" {
    var fake = Fake{ .items = &.{ .{ .result = .{ .event = .{ .value = keys.mouse, .mouse = .{ .column = 7, .buttons = 1 } } } }, .{ .result = .{ .event = .{ .value = keys.mouse, .mouse = .{ .column = 9, .buttons = 0 } } } } } };
    var decoder = ev.Decoder{};
    _ = try ev.read(&decoder, fake.source(), 0, true);
    _ = try ev.read(&decoder, fake.source(), 0, true);
    try std.testing.expectEqual(@as(usize, 1), fake.index);
    try std.testing.expectEqual(@as(forth.Cell, 0), decoder.last_mouse.column);
    _ = try ev.read(&decoder, fake.source(), 0, false);
    _ = try ev.read(&decoder, fake.source(), 0, true);
    try std.testing.expectEqual(@as(forth.Cell, 7), decoder.last_mouse.column);
    _ = try ev.read(&decoder, fake.source(), 0, false);
    try std.testing.expectEqual(@as(forth.Cell, 9), decoder.last_mouse.column);
}

test "paste treats ESC and CtrlC as text, preserves newline, and ends without swallowing next input" {
    var fake = Fake{ .items = &bytes("\x1b[200~\x03\x1b[A\r\n\t\x1b[201~Z"), .eof = true };
    var decoder = ev.Decoder{};
    try std.testing.expectEqual(keys.paste_begin, try value(try ev.read(&decoder, fake.source(), 0, false)));
    for ([_]forth.Cell{ 3, 27, '[', 'A', 13, 10, 9, keys.paste_end, 'Z' }) |expected| try std.testing.expectEqual(expected, try value(try ev.read(&decoder, fake.source(), 0, false)));
    try std.testing.expect((try ev.read(&decoder, fake.source(), 0, false)) == .eof);
    var interrupt = Fake{ .items = &bytes("\x03") };
    try std.testing.expectError(error.UserInterrupt, ev.read(&decoder, interrupt.source(), 0, false));
}

test "SGR mouse tracks held buttons, modifiers, wheel and ignores horizontal wheel" {
    var fake = Fake{ .items = &bytes("\x1b[<4;3;4M\x1b[<2;3;4M\x1b[<0;3;4m\x1b[<64;3;4M\x1b[<66;3;4MX"), .eof = true };
    var decoder = ev.Decoder{};
    try std.testing.expectEqual(keys.mouse | keys.shift, try value(try ev.read(&decoder, fake.source(), 0, true)));
    try std.testing.expectEqual(@as(forth.Cell, 0), decoder.last_mouse.buttons);
    _ = try ev.read(&decoder, fake.source(), 0, false);
    try std.testing.expectEqual(@as(forth.Cell, 1), decoder.last_mouse.buttons);
    _ = try ev.read(&decoder, fake.source(), 0, false);
    try std.testing.expectEqual(@as(forth.Cell, 3), decoder.last_mouse.buttons);
    _ = try ev.read(&decoder, fake.source(), 0, false);
    try std.testing.expectEqual(@as(forth.Cell, 2), decoder.last_mouse.buttons);
    _ = try ev.read(&decoder, fake.source(), 0, false);
    try std.testing.expectEqual(@as(forth.Cell, 1), decoder.last_mouse.wheel);
    try std.testing.expectEqual(@as(forth.Cell, 'X'), try value(try ev.read(&decoder, fake.source(), 0, false)));
}

test "ior and clock failure preserve partial bytes; native events do not split partial text" {
    var fake = Fake{ .items = &.{ .{ .result = .{ .event = .{ .value = 0xe6 } } }, .{ .result = .{ .failure = -999 } }, .{ .result = .{ .event = .{ .value = keys.winch } } } }, .eof = true };
    var decoder = ev.Decoder{};
    const failed = try ev.read(&decoder, fake.source(), 0, false);
    try std.testing.expectEqual(@as(forth.Cell, -999), failed.failure);
    try std.testing.expectEqual(@as(usize, 1), decoder.length);
    fake.failed_clock = true;
    try std.testing.expectError(error.HostFailed, ev.read(&decoder, fake.source(), 0, false));
    fake.failed_clock = false;
    try std.testing.expectEqual(keys.winch, try value(try ev.read(&decoder, fake.source(), 0, false)));
    try std.testing.expectEqual(@as(forth.Cell, 0xfffd), try value(try ev.read(&decoder, fake.source(), 0, false)));
}

test "EKEY-WAIT fixed results, EOF and overflow are checked before input consumption" {
    try support.skipWithout(&.{.extension});
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    var fake = Fake{};
    machine.writer.context = &fake;
    machine.writer.standard_event_fn = Fake.read;
    machine.writer.standard_clock = fake.source().clock;
    machine.writer.buffered_key_fn = null;
    machine.writer.unread_fn = null;
    machine.writer.input_error_fn = null;
    try machine.interpretLine("REQUIRE-EXTENSION ALSO EXTENSION 0 EKEY-WAIT");
    try support.expectStack(machine, &.{ 0, 0, 0 });
    fake.eof = true;
    try machine.interpretLine("0 EKEY-WAIT");
    try support.expectStack(machine, &.{ 0, 0, 0, keys.eof, -1, 0 });
    fake.items = &bytes("X");
    fake.index = 0;
    machine.data_depth = machine.data_stack.len;
    try std.testing.expectError(error.StackOverflow, machine.executeBuiltin(.ekey));
    try std.testing.expectError(error.StackOverflow, machine.executeBuiltin(.ekey_question));
    machine.data_depth = machine.data_stack.len - 1;
    machine.data_stack[machine.data_depth - 1] = 0;
    try std.testing.expectError(error.StackOverflow, machine.executeBuiltin(.ekey_wait));
    try std.testing.expectEqual(@as(usize, 0), fake.index);
}

test "overlong escapes are lossless and file controls stay literal" {
    const text = "\x1b[1234567890123456789012345678901234567890";
    var fake = Fake{ .items = &bytes(text), .eof = true };
    var decoder = ev.Decoder{};
    try std.testing.expectEqual(@as(forth.Cell, 27), try value(try ev.read(&decoder, fake.source(), 0, false)));
    for (text[1..]) |byte| try std.testing.expectEqual(@as(forth.Cell, byte), try value(try ev.read(&decoder, fake.source(), 0, false)));
    fake = .{ .items = &bytes("\x1b[200~"), .eof = true };
    decoder = .{};
    var source = fake.source();
    source.controls = false;
    for ("\x1b[200~") |byte| try std.testing.expectEqual(@as(forth.Cell, byte), try value(try ev.read(&decoder, source, 0, false)));
}

test "escape deadline overflow returns a range error and retains input" {
    var fake = Fake{ .items = &bytes("\x1b"), .now = std.math.maxInt(i128) - 10 };
    var decoder = ev.Decoder{};
    try std.testing.expectError(error.ResultOutOfRange, ev.read(&decoder, fake.source(), 0, false));
    try std.testing.expectEqual(@as(usize, 1), decoder.length);
}

test "image restoration clears standard decoder state without serializing native events" {
    try support.skipWithout(&.{.image});
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    machine.standard_input = .{ .paste = true, .deferred = .{ .value = keys.mouse, .mouse = .{ .buttons = 1 } }, .last_mouse = .{ .column = 8 }, .length = 1 };
    machine.standard_input.bytes[0] = 27;
    const image = try std.testing.allocator.alloc(u8, try machine.encodedSize());
    defer std.testing.allocator.free(image);
    _ = try machine.encodeImage(image);
    try machine.restoreImage(image);
    try std.testing.expect(!machine.standard_input.paste);
    try std.testing.expect(machine.standard_input.deferred == null);
    try std.testing.expectEqual(@as(usize, 0), machine.standard_input.length);
    try std.testing.expectEqual(@as(forth.Cell, 0), machine.standard_input.last_mouse.column);
}

test "peek retains one-shot EOF and restart preserves escape age while resetting buttons" {
    var fake = Fake{ .items = &.{.{ .result = .eof }} };
    var decoder = ev.Decoder{};
    try std.testing.expect((try ev.read(&decoder, fake.source(), 0, true)) == .eof);
    try std.testing.expect((try ev.read(&decoder, fake.source(), 0, false)) == .eof);
    try std.testing.expectEqual(@as(usize, 1), fake.index);
    fake = .{ .items = &.{ .{ .result = .{ .event = .{ .value = 27 } } }, .{ .at = 20_000_000, .result = .restart } } };
    decoder = .{ .buttons = 1 };
    try std.testing.expectEqual(@as(forth.Cell, 27), try value(try ev.read(&decoder, fake.source(), 100, false)));
    try std.testing.expectEqual(@as(i128, 50_000_000), fake.now);
    try std.testing.expectEqual(@as(u8, 0), decoder.buttons);
}

test "unsupported extended mouse buttons do not alter primary buttons" {
    var fake = Fake{ .items = &bytes("\x1b[<128;3;4M\x1b[<32;3;4M"), .eof = true };
    var decoder = ev.Decoder{};
    try std.testing.expectEqual(keys.mouse, try value(try ev.read(&decoder, fake.source(), 0, false)));
    try std.testing.expectEqual(@as(forth.Cell, 1), decoder.last_mouse.buttons);
}

test "byte-only embedded line fallback drains EKEY prefix and keeps CRLF behavior" {
    var output = support.Output{ .keys = "bc\r\nZ" };
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    machine.writer.unread_fn = null;
    machine.standard_input.bytes[0] = 'a';
    machine.standard_input.length = 1;
    try machine.interpretLine("PAD 20 ACCEPT PAD SWAP TYPE KEY");
    try std.testing.expectEqualStrings("abc", output.written());
    try support.expectStack(machine, &.{'Z'});
}

test "selected file timed wait rejects before reading and keeps outer decoder across THROW" {
    try support.skipWithout(&.{ .files, .extension });
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    support.setFakeFile(&output, 0, "ABC");
    machine.standard_input.bytes[0] = 0xe6;
    machine.standard_input.length = 1;
    machine.standard_input.paste = true;
    try machine.interpretLine("REQUIRE-EXTENSION ALSO EXTENSION S\" a.txt\" R/O OPEN-FILE THROW CONSTANT A : WAIT-W 0 EKEY-WAIT ; : INNER-W ['] WAIT-W CATCH ; ' INNER-W A INFILE-EXECUTE A KEY-FILE");
    try support.expectStack(machine, &.{ -21, 'A' });
    try std.testing.expectEqual(@as(usize, 1), machine.standard_input.length);
    try std.testing.expect(machine.standard_input.paste);
    try machine.interpretLine(": OLD-W EKEY ; ' OLD-W A INFILE-EXECUTE");
    try std.testing.expectEqual(@as(forth.Cell, 'B'), try machine.pop());
}

test "stdin decoder is shared through stdin file stdin nesting" {
    try support.skipWithout(&.{.files});
    const Bridge = struct {
        var input: *Fake = undefined;
        fn read(_: ?*anyopaque, timeout: i32) forth.RuntimeError!ev.Result {
            return Fake.read(input, timeout);
        }
    };
    var fake = Fake{ .items = &bytes("AB"), .eof = true };
    Bridge.input = &fake;
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    support.setFakeFile(&output, 0, "file");
    machine.writer.standard_event_fn = Bridge.read;
    machine.writer.standard_clock = fake.source().clock;
    try machine.interpretLine("S\" a.txt\" R/O OPEN-FILE THROW CONSTANT A EKEY? DROP : STD-W EKEY ; : FILE-W ['] STD-W STDIN INFILE-EXECUTE ; ' FILE-W A INFILE-EXECUTE EKEY");
    try support.expectStack(machine, &.{ 'A', 'B' });
}

test "completed native resize does not split an unfinished escape sequence" {
    var fake = Fake{ .items = &.{ .{ .result = .{ .event = .{ .value = 27 } } }, .{ .result = .{ .event = .{ .value = '[' } } }, .{ .result = .{ .event = .{ .value = keys.winch } } }, .{ .result = .{ .event = .{ .value = 'A' } } } } };
    var decoder = ev.Decoder{};
    try std.testing.expectEqual(keys.winch, try value(try ev.read(&decoder, fake.source(), 0, false)));
    try std.testing.expectEqual(@as(usize, 2), decoder.length);
    try std.testing.expectEqual(keys.special + 2, try value(try ev.read(&decoder, fake.source(), 0, false)));
}

test "nested stdin scopes preserve legacy pending key bytes and special event" {
    try support.skipWithout(&.{.files});
    const Bridge = struct {
        var input: *Fake = undefined;
        fn read(_: ?*anyopaque, timeout: i32) forth.RuntimeError!ev.Result {
            return Fake.read(input, timeout);
        }
    };
    var fake = Fake{ .items = &bytes("A"), .eof = true };
    Bridge.input = &fake;
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    support.setFakeFile(&output, 0, "file");
    machine.writer.standard_event_fn = Bridge.read;
    machine.writer.standard_clock = fake.source().clock;
    machine.writer.unread_fn = null;
    machine.pending_key = 'X';
    machine.pending_event_bytes[0] = 'Z';
    machine.pending_event_bytes[1] = 'Y';
    machine.pending_event_count = 2;
    machine.pending_standard_event = keys.winch;
    try machine.interpretLine("S\" a.txt\" R/O OPEN-FILE THROW CONSTANT A : STD-W KEY EKEY EKEY EKEY ; : FILE-W ['] STD-W STDIN INFILE-EXECUTE ; ' FILE-W A INFILE-EXECUTE EKEY");
    try support.expectStack(machine, &.{ 'X', 'Y', 'Z', keys.winch, 'A' });
}

test "line fallback retains nonLF after CR for the next ACCEPT" {
    var output = support.Output{ .keys = "bc\rde\n" };
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    machine.writer.unread_fn = null;
    machine.standard_input.bytes[0] = 'a';
    machine.standard_input.length = 1;
    try machine.interpretLine("PAD 20 ACCEPT PAD SWAP TYPE SPACE PAD 20 ACCEPT PAD SWAP TYPE");
    try std.testing.expectEqualStrings("abc de", output.written());
}

test "checked pushback rejection retains a byte and legacy acceptance never duplicates on later error" {
    const Context = struct {
        accepted: usize = 0,
        report: bool = false,
        reject: bool = false,
        fn check(context: ?*anyopaque) forth.RuntimeError!void {
            const self: *@This() = @ptrCast(@alignCast(context.?));
            if (self.report) {
                self.report = false;
                return error.HostFailed;
            }
        }
        fn legacy(context: ?*anyopaque, _: u8) void {
            const self: *@This() = @ptrCast(@alignCast(context.?));
            self.accepted += 1;
            self.report = true;
        }
        fn checked(context: ?*anyopaque, _: u8) forth.RuntimeError!void {
            const self: *@This() = @ptrCast(@alignCast(context.?));
            if (self.reject) return error.HostFailed;
            self.accepted += 1;
        }
    };
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    var context = Context{};
    machine.writer.context = &context;
    machine.writer.input_error_fn = Context.check;
    machine.writer.unread_fn = Context.legacy;
    machine.standard_input.bytes[0] = 'A';
    machine.standard_input.length = 1;
    try std.testing.expectError(error.HostFailed, @import("../core/event_input.zig").beforeBytes(machine));
    try std.testing.expectEqual(@as(usize, 0), machine.standard_input.length);
    try std.testing.expectEqual(@as(usize, 1), context.accepted);
    context = .{ .reject = true };
    machine.standard_input.length = 1;
    machine.writer.unread_byte_fn = Context.checked;
    try std.testing.expectError(error.HostFailed, @import("../core/event_input.zig").beforeBytes(machine));
    try std.testing.expectEqual(@as(usize, 1), machine.standard_input.length);
    context.reject = false;
    try @import("../core/event_input.zig").beforeBytes(machine);
    try std.testing.expectEqual(@as(usize, 0), machine.standard_input.length);
    try std.testing.expectEqual(@as(usize, 1), context.accepted);
}

test "peek to KEY keeps decoder prefix ahead of legacy bytes with and without checked pushback" {
    const Context = struct {
        held: [65]u8 = undefined,
        count: usize = 0,
        fn push(context: ?*anyopaque, byte: u8) forth.RuntimeError!void {
            const self: *@This() = @ptrCast(@alignCast(context.?));
            if (self.count == self.held.len) return error.HostFailed;
            self.held[self.count] = byte;
            self.count += 1;
        }
        fn take(context: ?*anyopaque) ?u8 {
            const self: *@This() = @ptrCast(@alignCast(context.?));
            if (self.count == 0) return null;
            self.count -= 1;
            return self.held[self.count];
        }
        fn event(context: ?*anyopaque, _: i32) forth.RuntimeError!ev.Result {
            return if (take(context)) |byte| .{ .event = .{ .value = byte } } else .timeout;
        }
        fn clock(_: ?*anyopaque) base.Error!i128 {
            return 0;
        }
    };
    for ([_]bool{ false, true }) |checked| {
        var output = support.Output{};
        const machine = try support.createMachine(&output);
        defer support.destroyMachine(machine);
        var context = Context{};
        machine.writer.context = &context;
        machine.writer.standard_event_fn = Context.event;
        machine.writer.standard_clock = .{ .context = null, .now_fn = Context.clock };
        machine.writer.unread_fn = null;
        machine.writer.unread_byte_fn = if (checked) Context.push else null;
        machine.writer.key_fn = Context.take;
        machine.pending_key = 'X';
        machine.pending_event_bytes[0] = 'Z';
        machine.pending_event_bytes[1] = 'Y';
        machine.pending_event_count = 2;
        if (@import("build_options").files) {
            try machine.interpretLine("STDIN KEY?-FILE");
            try std.testing.expectEqual(@as(forth.Cell, -1), try machine.pop());
        }
        try machine.interpretLine("EKEY? DROP KEY KEY KEY");
        try support.expectStack(machine, &.{ 'X', 'Y', 'Z' });
        if (!checked) {
            machine.data_depth = 0;
            machine.standard_input.bytes[0] = 0xe6;
            machine.standard_input.bytes[1] = 0xff;
            machine.standard_input.bytes[2] = 'Q';
            machine.standard_input.length = 3;
            try machine.interpretLine("XKEY KEY KEY");
            try support.expectStack(machine, &.{ 0xfffd, 0xff, 'Q' });
        }
    }
}

test "selected file EKEY-WAIT dispatches fixed results without consuming on stack overflow" {
    try support.skipWithout(&.{ .files, .extension });
    const Bridge = struct {
        var calls: usize = 0;
        var outcome: ev.Result = .timeout;
        fn wait(_: ?*anyopaque, id: forth.Cell, ms: i64) forth.RuntimeError!ev.Result {
            if (id != forth.first_file_id or ms != 7) return error.HostFailed;
            calls += 1;
            return outcome;
        }
    };
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    var ops = support.fake_file_ops;
    ops.event_wait = Bridge.wait;
    machine.writer.file_ops = &ops;
    machine.input_file = forth.first_file_id;
    Bridge.calls = 0;
    Bridge.outcome = .{ .event = .{ .value = 0x3042 } };
    try machine.push(7);
    try machine.executeBuiltin(.ekey_wait);
    try support.expectStack(machine, &.{ 0x3042, -1, 0 });
    machine.data_depth = 0;
    Bridge.outcome = .{ .failure = -37 };
    try machine.push(7);
    try machine.executeBuiltin(.ekey_wait);
    try support.expectStack(machine, &.{ 0, 0, -37 });
    machine.data_depth = 0;
    Bridge.outcome = .eof;
    try machine.push(7);
    try machine.executeBuiltin(.ekey_wait);
    try support.expectStack(machine, &.{ keys.eof, -1, 0 });
    machine.data_depth = machine.data_stack.len - 1;
    machine.data_stack[machine.data_depth - 1] = 7;
    try std.testing.expectError(error.StackOverflow, machine.executeBuiltin(.ekey_wait));
    try std.testing.expectEqual(@as(usize, 3), Bridge.calls);
}
