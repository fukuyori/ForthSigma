const std = @import("std");
const forth = @import("forth.zig");

const Output = struct {
    bytes: [4096]u8 = undefined,
    len: usize = 0,

    fn write(context: ?*anyopaque, bytes: []const u8) void {
        const output: *Output = @ptrCast(@alignCast(context.?));
        const count = @min(bytes.len, output.bytes.len - output.len);
        @memcpy(output.bytes[output.len .. output.len + count], bytes[0..count]);
        output.len += count;
    }

    fn writer(self: *Output) forth.Writer {
        return .{ .context = @ptrCast(self), .write_fn = write };
    }

    fn written(self: *const Output) []const u8 {
        return self.bytes[0..self.len];
    }
};

fn expectStack(machine: *const forth.State, expected: []const forth.Cell) !void {
    try std.testing.expectEqual(expected.len, machine.data_depth);
    try std.testing.expectEqualSlices(forth.Cell, expected, machine.data_stack[0..machine.data_depth]);
}

test "16-bit arithmetic wraps and signed division truncates toward zero" {
    var output = Output{};
    var machine = forth.State.init(output.writer());

    try machine.interpretLine("32767 1 + -7 3 /MOD");

    const expected = [_]forth.Cell{ 32768, 0xffff, 0xfffe };
    try expectStack(&machine, &expected);
}

test "true flags use one and zero remains false" {
    var output = Output{};
    var machine = forth.State.init(output.writer());

    try machine.interpretLine("1 1 = 0 0= AND 0 1 = OR");

    const expected = [_]forth.Cell{1};
    try expectStack(&machine, &expected);
}

test "dictionary uses case-insensitive names and first-five-character identity" {
    var output = Output{};
    var machine = forth.State.init(output.writer());

    try machine.interpretLine(": ABCDE1 1 ; : ABCDE2 2 ; abcde2");

    const expected = [_]forth.Cell{2};
    try expectStack(&machine, &expected);
}

test "compiled nested loops and outer indices produce expected result" {
    var output = Output{};
    var machine = forth.State.init(output.writer());

    try machine.interpretLine(": TOTAL 0 3 0 DO 2 0 DO I J + + LOOP LOOP ; TOTAL");

    const expected = [_]forth.Cell{9};
    try expectStack(&machine, &expected);
}

test "q-do skips an empty range and do enters an equal range once" {
    var output = Output{};
    var machine = forth.State.init(output.writer());

    try machine.interpretLine(": SKIP 0 5 5 ?DO 1 + LOOP ; : ONCE 0 5 5 DO 1 + LOOP ; SKIP ONCE");

    const expected = [_]forth.Cell{ 0, 1 };
    try expectStack(&machine, &expected);
}

test "variable array and string operations use the portable data area" {
    var output = Output{};
    var machine = forth.State.init(output.writer());

    try machine.interpretLine("VARIABLE V 123 V ! V @ 2 ARRAY A 42 1 A A! 1 A A@ : MESSAGE \" OK\" TYPE ; MESSAGE");

    const expected = [_]forth.Cell{ 123, 42 };
    try expectStack(&machine, &expected);
    try std.testing.expectEqualStrings("OK", output.written());
}

test "decimal output has no trailing space and CR emits a newline" {
    var output = Output{};
    var machine = forth.State.init(output.writer());

    try machine.interpretLine("3 . CR");

    try std.testing.expectEqualStrings("3\n", output.written());
}

test "error reporting resets the stack and reports the unknown token" {
    var output = Output{};
    var machine = forth.State.init(output.writer());

    machine.interpretLine("1 MISSING") catch |err| machine.report(err);

    try expectStack(&machine, &.{});
    try std.testing.expectEqualStrings("MISSING ?\n", output.written());
}

test "forget removes later words and reclaims their data allocation" {
    var output = Output{};
    var machine = forth.State.init(output.writer());

    try machine.interpretLine(": KEEP 11 ; 2 ARRAY RECLAIM FORGET RECLAIM HERE KEEP");

    const expected = [_]forth.Cell{ 0x4000, 11 };
    try expectStack(&machine, &expected);
    try std.testing.expectEqual(@as(forth.Cell, 0x4000), machine.data_here);

    const missing = machine.interpretLine("RECLAIM");
    try std.testing.expectError(error.UnknownWord, missing);
    machine.report(error.UnknownWord);
    try std.testing.expectEqualStrings("RECLAIM ?\n", output.written());
}

test "forget reclaims compiled code for later definitions" {
    var output = Output{};
    var machine = forth.State.init(output.writer());

    try machine.interpretLine(": KEEP 11 ; : REMOVE 22 ; FORGET REMOVE KEEP");
    const before_redefinition = [_]forth.Cell{11};
    try expectStack(&machine, &before_redefinition);

    try machine.interpretLine(": REMOVE 33 ; REMOVE");
    const expected = [_]forth.Cell{ 11, 33 };
    try expectStack(&machine, &expected);
}

test "failed definition is rolled back and the interpreter recovers" {
    var output = Output{};
    var machine = forth.State.init(output.writer());
    const initial_words = machine.word_count;
    const initial_code = machine.code_count;

    const invalid = machine.interpretLine(": BROKEN 1 MISSING");
    try std.testing.expectError(error.UnknownWord, invalid);
    machine.report(error.UnknownWord);
    try std.testing.expectEqual(initial_words, machine.word_count);
    try std.testing.expectEqual(initial_code, machine.code_count);

    try machine.interpretLine(": GOOD 9 ; GOOD");
    const expected = [_]forth.Cell{9};
    try expectStack(&machine, &expected);
}

test "data allocation rejects 16-bit wrap without moving the allocation pointer" {
    var output = Output{};
    var machine = forth.State.init(output.writer());

    try machine.interpretLine("49151 ALLOT HERE");
    const expected = [_]forth.Cell{0xffff};
    try expectStack(&machine, &expected);
    try std.testing.expectEqual(@as(forth.Cell, 0xffff), machine.data_here);

    const overflow = machine.interpretLine("1 ALLOT");
    try std.testing.expectError(error.MemoryExhausted, overflow);
    machine.report(error.MemoryExhausted);
    try std.testing.expectEqual(@as(forth.Cell, 0xffff), machine.data_here);
}

test "16-bit cell access wraps across the logical memory boundary" {
    var output = Output{};
    var machine = forth.State.init(output.writer());

    try machine.interpretLine("4660 65535 ! 65535 @");

    const expected = [_]forth.Cell{0x1234};
    try expectStack(&machine, &expected);
}

test "division by zero returns the documented portable values" {
    var output = Output{};
    var machine = forth.State.init(output.writer());

    try machine.interpretLine("7 0 / 7 0 MOD 7 0 /MOD");

    const expected = [_]forth.Cell{ 0x7fff, 0, 0, 0x7fff };
    try expectStack(&machine, &expected);
    try std.testing.expectEqualStrings("DIVISION BY ZERO\nDIVISION BY ZERO\nDIVISION BY ZERO\n", output.written());
}

test "stack overflow is reported and subsequent input can run" {
    var output = Output{};
    var machine = forth.State.init(output.writer());
    var input: [2050]u8 = undefined;
    for (0..1024) |index| {
        input[index * 2] = '0';
        input[index * 2 + 1] = ' ';
    }
    input[2048] = '0';
    input[2049] = ' ';

    const overflow = machine.interpretLine(&input);
    try std.testing.expectError(error.StackOverflow, overflow);
    machine.report(error.StackOverflow);
    try expectStack(&machine, &.{});

    try machine.interpretLine("2 3 +");
    const expected = [_]forth.Cell{5};
    try expectStack(&machine, &expected);
}

test "return stack overflow and underflow reset cleanly" {
    var output = Output{};
    var machine = forth.State.init(output.writer());

    for (0..1024) |_| try machine.interpretLine("0 >R");
    try std.testing.expectEqual(@as(usize, 1024), machine.return_depth);
    const overflow = machine.interpretLine("0 >R");
    try std.testing.expectError(error.ReturnStackOverflow, overflow);
    machine.report(error.ReturnStackOverflow);
    try std.testing.expectEqual(@as(usize, 0), machine.return_depth);
    try expectStack(&machine, &.{});

    const underflow = machine.interpretLine("R>");
    try std.testing.expectError(error.ReturnStackUnderflow, underflow);
    machine.report(error.ReturnStackUnderflow);
    try std.testing.expectEqual(@as(usize, 0), machine.return_depth);
}

test "dictionary capacity failure preserves existing words" {
    var output = Output{};
    var machine = forth.State.init(output.writer());
    var definition: [32]u8 = undefined;

    while (machine.word_count < 1024) {
        const text = try std.fmt.bufPrint(&definition, ": W{d} 1 ;", .{machine.word_count});
        try machine.interpretLine(text);
    }
    try std.testing.expectEqual(@as(u16, 1024), machine.word_count);

    const overflow = machine.interpretLine(": EXTRA 2 ;");
    try std.testing.expectError(error.DictionaryFull, overflow);
    machine.report(error.DictionaryFull);
    try std.testing.expectEqual(@as(u16, 1024), machine.word_count);
    try machine.interpretLine("W1023");
    const expected = [_]forth.Cell{1};
    try expectStack(&machine, &expected);
}

test "control nesting overflow rolls back the incomplete definition" {
    var output = Output{};
    var machine = forth.State.init(output.writer());
    const initial_words = machine.word_count;
    const initial_code = machine.code_count;
    var input: [400]u8 = undefined;
    var used: usize = 0;
    const prefix = ": TOO-DEEP ";
    @memcpy(input[used .. used + prefix.len], prefix);
    used += prefix.len;
    for (0..129) |_| {
        @memcpy(input[used .. used + 3], "IF ");
        used += 3;
    }

    const overflow = machine.interpretLine(input[0..used]);
    try std.testing.expectError(error.ControlStackOverflow, overflow);
    machine.report(error.ControlStackOverflow);
    try std.testing.expectEqualStrings("NESTING ERROR !\n", output.written());
    try std.testing.expectEqual(initial_words, machine.word_count);
    try std.testing.expectEqual(initial_code, machine.code_count);
}

test "compiled code capacity failure rolls back the incomplete definition" {
    var output = Output{};
    var machine = forth.State.init(output.writer());
    const initial_words = machine.word_count;
    const initial_code = machine.code_count;
    var input: [16396]u8 = undefined;
    var used: usize = 0;
    const prefix = ": TOO-LONG ";
    @memcpy(input[used .. used + prefix.len], prefix);
    used += prefix.len;
    for (0..8192) |_| {
        @memcpy(input[used .. used + 2], "1 ");
        used += 2;
    }
    input[used] = ';';
    used += 1;

    const overflow = machine.interpretLine(input[0..used]);
    try std.testing.expectError(error.CodeFull, overflow);
    machine.report(error.CodeFull);
    try std.testing.expectEqual(initial_words, machine.word_count);
    try std.testing.expectEqual(initial_code, machine.code_count);
}
