//! Tests of the xchar words, CHAR, and character literals with UTF-8. The values for
//! well-formed UTF-8 were checked against gforth 0.7.9_20260410 under WSL.

const std = @import("std");
const forth = @import("../forth.zig");
const support = @import("support.zig");
const char_width = @import("../core/char_width.zig");
const words_xchar = @import("../core/words_xchar.zig");
const Output = support.Output;
const createMachine = support.createMachine;
const destroyMachine = support.destroyMachine;
const expectStack = support.expectStack;
const expectOutput = support.expectOutput;

test "CHAR, [CHAR], and 'c' give the code point of a UTF-8 character" {
    try expectOutput("CHAR A . CHAR 日 . CHAR 😀 . CHAR é . 'あ' . '😀' . 'x' . : CC [CHAR] 日 ; CC .", "65 26085 128512 233 12354 128512 120 26085 ");
    // A literal of two characters is not a character literal.
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    try std.testing.expectError(error.UnknownWord, machine.interpretLine("'ab'"));
}

test "XC-SIZE, X-SIZE, XC@+, XC!+, XC!+?, XC,, and XEMIT as in gforth" {
    try expectOutput("0 XC-SIZE . 127 XC-SIZE . 128 XC-SIZE . 2047 XC-SIZE . 2048 XC-SIZE . 65535 XC-SIZE . 65536 XC-SIZE . 1114111 XC-SIZE .", "1 1 2 2 3 3 4 4 ");
    try expectOutput("S\" a日😀\" X-SIZE . S\" 日本\" X-SIZE . S\" 😀x\" X-SIZE . S\" \" X-SIZE .", "1 3 4 1 ");
    try expectOutput("CREATE TEST-BUF 8 ALLOT 26085 TEST-BUF XC!+ TEST-BUF - . TEST-BUF 3 TYPE 26085 TEST-BUF 2 XC!+? . . TEST-BUF - . 128512 TEST-BUF 4 XC!+? . . TEST-BUF - . TEST-BUF 4 TYPE", "3 日0 2 0 -1 0 4 😀");
    try expectOutput("HERE 26085 XC, HERE SWAP - . HERE 65 XC, HERE SWAP - . HERE 128512 XC, HERE SWAP - .", "3 1 4 ");
    try expectOutput("26085 XEMIT 128512 XEMIT 65 XEMIT 233 XEMIT $7FF XEMIT", "日😀Aé\u{7FF}");
    try expectOutput("S\" 日本\" DROP XC@ . S\" 😀\" DROP DUP XC@+ . SWAP - . S\" 日本語\" DROP 3 + XC@ .", "26085 128512 4 26412 ");
    // Surrogates and overlong forms decode as in gforth.
    try expectOutput("S\\\" \\xED\\xA0\\x80\" DROP XC@ . 55296 XC-SIZE . S\\\" \\xC0\\x80\" DROP XC@+ . DROP", "55296 3 0 ");
}

test "XCHAR+, XCHAR-, +X/STRING, X\\STRING-, -TRAILING-GARBAGE, and X@+/STRING" {
    try expectOutput("S\" a日😀\" DROP DUP XCHAR+ XCHAR+ SWAP - . S\" a日😀\" DROP DUP 8 + XCHAR- SWAP - . S\" a日😀\" DROP DUP 4 + XCHAR- SWAP - .", "4 4 1 ");
    try expectOutput("S\" 日本語\" +X/STRING TYPE SPACE S\" 日本語\" X\\STRING- TYPE SPACE S\" \" +X/STRING NIP . S\" \" X\\STRING- NIP . S\" 😀a\" X\\STRING- TYPE", "本語 日本 -1 0 😀");
    try expectOutput("S\\\" ab\\xE6\\x97\" -TRAILING-GARBAGE NIP . S\" ab日\" -TRAILING-GARBAGE NIP . S\\\" ab\\xFF\" -TRAILING-GARBAGE NIP . S\" \" -TRAILING-GARBAGE NIP .", "2 5 2 0 ");
    try expectOutput("S\" 日本\" X@+/STRING . TYPE S\" a😀\" X@+/STRING . TYPE", "26085 本97 😀");
}

test "XHOLD, EKEY>XCHAR, X-WIDTH, and XC-WIDTH" {
    try expectOutput("<# 26085 XHOLD 65 HOLD 128512 XHOLD 0 0 #> TYPE", "😀A日");
    try expectOutput("26085 EKEY>XCHAR . . 65 EKEY>XCHAR . . 230 EKEY>XCHAR . .", "-1 26085 -1 65 -1 230 ");
    try expectOutput("S\" a日😀é\" X-WIDTH . S\" ｱｲｳ\" X-WIDTH . S\\\" a\\x07b\" X-WIDTH .", "6 3 2 ");
    try expectOutput("65 XC-WIDTH . 26085 XC-WIDTH . 128512 XC-WIDTH . 769 XC-WIDTH . 0 XC-WIDTH . 7 XC-WIDTH . 127 XC-WIDTH . 888 XC-WIDTH . 12288 XC-WIDTH . $110000 XC-WIDTH . -1 XC-WIDTH .", "1 2 2 0 0 -1 -1 -1 2 -1 -1 ");
}

test "the width table matches the runs gforth gave at their edges" {
    // A few edges of the runs, from gforth's xc-width under WSL (glibc 2.39).
    const cases = [_]struct { u64, i8 }{
        .{ 0x1F, -1 },  .{ 0x20, 1 },    .{ 0xA0, 1 },     .{ 0xAD, 1 },      .{ 0x300, 0 },  .{ 0x600, 1 },   .{ 0x1160, 0 },
        .{ 0x1100, 2 }, .{ 0x200B, 0 },  .{ 0x2028, -1 },  .{ 0x3248, 2 },    .{ 0x4DC0, 2 }, .{ 0xD800, -1 }, .{ 0xE000, 1 },
        .{ 0xFF61, 1 }, .{ 0x1F600, 2 }, .{ 0x10FFFD, 1 }, .{ 0x10FFFE, -1 },
    };
    for (cases) |case| try std.testing.expectEqual(case[1], char_width.width(case[0]));
}

test "malformed UTF-8 follows one rule: U+FFFD, taking the start byte and the bytes that continue it" {
    const cases = [_]struct { []const u8, u21, usize }{
        .{ "\xE6\x97A", 0xFFFD, 2 },        .{ "\xFFA", 0xFFFD, 1 },                .{ "\x80A", 0xFFFD, 1 },
        .{ "\xF4\x90\x80\x80", 0xFFFD, 4 }, .{ "\xF8\x88\x80\x80\x80", 0xFFFD, 1 }, .{ "\xFE", 0xFFFD, 1 },
        .{ "\xE6", 0xFFFD, 1 },             .{ "\xF0\x9F\x98", 0xFFFD, 3 },         .{ "\xE0\x80\x80", 0, 3 },
        .{ "\xC1\xBF", 0x7F, 2 },
    };
    for (cases) |case| {
        const found = words_xchar.decode(case[0]);
        try std.testing.expectEqual(case[1], found.code);
        try std.testing.expectEqual(case[2], found.length);
    }
    // The same rule in X-SIZE, X@+/STRING, and X-WIDTH, within the string's length.
    try expectOutput("S\\\" \\xF0\\x9F\\x98\\x80\" DROP 2 X-SIZE . S\\\" \\xE6\\x97A\" X@+/STRING . . DROP S\\\" \\xFF\\xE6\\x97\" X-WIDTH .", "2 65533 1 2 ");
    // A value above U+10FFFF is written as U+FFFD.
    try expectOutput("$110000 XC-SIZE . -1 XC-SIZE . $110000 XEMIT", "3 3 \u{FFFD}");
}

test "XKEY reads the bytes of a character and leaves a byte that does not continue it for KEY" {
    var output = Output{ .keys = "あ😀a\xE6\x97A\xE6" };
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    try machine.interpretLine("XKEY XKEY XKEY XKEY XKEY? KEY XKEY? XKEY");
    try expectStack(machine, &.{ 12354, 128512, 97, 0xFFFD, -1, 'A', -1, 0xFFFD });
    try std.testing.expectError(error.InputUnavailable, machine.interpretLine("XKEY"));
}

test "without the host's unread_fn, the byte XKEY leaves still comes first to KEY and XKEY" {
    var output = Output{ .keys = "\xE6AB" };
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    machine.writer.unread_fn = null;
    try machine.interpretLine("XKEY XKEY? KEY KEY");
    try expectStack(machine, &.{ 0xFFFD, -1, 'A', 'B' });
}

test "EKEY decodes UTF-8 and modified function keys without changing KEY bytes" {
    var output = Output{ .keys = "é日😀\x1b[A\x1b[1;6D\x1b[24~x" };
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    try machine.interpretLine("EKEY EKEY EKEY EKEY K-UP = EKEY K-LEFT K-SHIFT-MASK OR K-CTRL-MASK OR = EKEY K-F12 = KEY");
    try expectStack(machine, &.{ 233, 26085, 128512, -1, -1, -1, 'x' });
}

test "unknown and incomplete EKEY sequences preserve input for KEY" {
    const cases = [_][]const u8{ "\x1b[", "\x1b[99~", "\x1bx" };
    for (cases) |bytes| {
        var output = Output{ .keys = bytes };
        const machine = try createMachine(&output);
        defer destroyMachine(machine);
        try machine.interpretLine("EKEY");
        try expectStack(machine, &.{27});
        for (bytes[1..]) |byte| {
            try machine.interpretLine("KEY");
            try std.testing.expectEqual(@as(forth.Cell, byte), try machine.pop());
        }
    }
}

test "standard key vocabulary can be restored after ONLY and GRAPHICS wins when selected" {
    try expectOutput("K-UP . K-ALT-MASK . ONLY FORTH ALSO EKEYS K-UP .", "2147483650 536870912 2147483650 ");
    try support.skipWithout(&.{.graphics});
    try expectOutput("REQUIRE-GRAPHICS K-UP . ALSO GRAPHICS K-UP . PREVIOUS K-UP .", "2147483650 256 2147483650 ");
}

test "EKEY? does not consume bytes needed by KEY" {
    var output = Output{ .keys = "AB" };
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    try machine.interpretLine("EKEY? EKEY? KEY EKEY EKEY?");
    try expectStack(machine, &.{ -1, -1, 'A', 'B', 0 });
}

test "EKEY escape continuation timeout is a total monotonic budget" {
    const Timed = struct {
        elapsed: i64 = 0,
        index: usize = 0,
        fn clock(context: ?*anyopaque) i64 {
            const self: *@This() = @ptrCast(@alignCast(context.?));
            return self.elapsed;
        }
        fn event(context: ?*anyopaque, timeout: i32) forth.RuntimeError!?forth.Cell {
            const self: *@This() = @ptrCast(@alignCast(context.?));
            if (timeout >= 0 and timeout < 20) {
                self.elapsed += timeout;
                return null;
            }
            const input = "\x1b[1;6A";
            if (self.index == input.len) return null;
            self.elapsed += 20;
            defer self.index += 1;
            return input[self.index];
        }
    };
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    var timed = Timed{};
    machine.writer.context = &timed;
    machine.writer.event_key_fn = Timed.event;
    machine.writer.monotonic_ms_fn = Timed.clock;
    machine.writer.unread_fn = null;
    const event = try @import("../core/event_input.zig").read(machine);
    try std.testing.expectEqual(@as(forth.Cell, 27), event);
    try std.testing.expectEqual(@as(i64, 70), timed.elapsed);
    try std.testing.expectEqual(@as(u8, '['), try words_xchar.key(machine));
    try std.testing.expectEqual(@as(u8, '1'), try words_xchar.key(machine));
}

test "ONLY ALSO EKEYS selects standard constants from Root" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    try machine.interpretLine("ONLY ALSO EKEYS K-UP");
    try expectStack(machine, &.{2147483650});
}

test "a deferred special key follows all pushed-back prefix bytes" {
    const Input = struct {
        index: usize = 0,
        pushed: [4]u8 = undefined,
        count: usize = 0,
        fn buffered(context: ?*anyopaque) ?u8 {
            const self: *@This() = @ptrCast(@alignCast(context.?));
            if (self.count == 0) return null;
            self.count -= 1;
            return self.pushed[self.count];
        }
        fn probe(context: ?*anyopaque) forth.RuntimeError!?u8 {
            return buffered(context);
        }
        fn unread(context: ?*anyopaque, byte: u8) void {
            const self: *@This() = @ptrCast(@alignCast(context.?));
            self.pushed[self.count] = byte;
            self.count += 1;
        }
        fn event(context: ?*anyopaque, _: i32) forth.RuntimeError!?forth.Cell {
            if (buffered(context)) |byte| return byte;
            const self: *@This() = @ptrCast(@alignCast(context.?));
            const events = [_]forth.Cell{ 27, '[', '1', 2147483650, 'x' };
            if (self.index == events.len) return null;
            defer self.index += 1;
            return events[self.index];
        }
    };
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    var input = Input{};
    machine.writer.context = &input;
    machine.writer.event_key_fn = Input.event;
    machine.writer.buffered_key_fn = Input.probe;
    machine.writer.unread_fn = Input.unread;
    machine.writer.key_fn = Input.buffered;
    const events = @import("../core/event_input.zig");
    try std.testing.expectEqual(@as(forth.Cell, 27), try events.read(machine));
    try std.testing.expectEqual(@as(u8, '['), try words_xchar.key(machine));
    try std.testing.expectEqual(@as(forth.Cell, '1'), try events.read(machine));
    try std.testing.expectEqual(@as(forth.Cell, 2147483650), try events.read(machine));
    try std.testing.expectEqual(@as(forth.Cell, 'x'), try events.read(machine));
}

test "interruption during an EKEY sequence preserves already read bytes" {
    const Input = struct {
        index: usize = 0,
        fn event(context: ?*anyopaque, _: i32) forth.RuntimeError!?forth.Cell {
            const self: *@This() = @ptrCast(@alignCast(context.?));
            defer self.index += 1;
            return switch (self.index) {
                0 => 27,
                1 => '[',
                else => error.UserInterrupt,
            };
        }
    };
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    var input = Input{};
    machine.writer.context = &input;
    machine.writer.event_key_fn = Input.event;
    machine.writer.unread_fn = null;
    try std.testing.expectError(error.UserInterrupt, @import("../core/event_input.zig").read(machine));
    try std.testing.expectEqual(@as(u8, 27), try words_xchar.key(machine));
    try std.testing.expectEqual(@as(u8, '['), try words_xchar.key(machine));
}
