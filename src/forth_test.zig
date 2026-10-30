const std = @import("std");
const forth = @import("forth.zig");

const Output = struct {
    bytes: [4096]u8 = undefined,
    len: usize = 0,
    input_lines: [4][]const u8 = undefined,
    input_count: usize = 0,
    input_index: usize = 0,
    keys: []const u8 = "",
    key_index: usize = 0,
    slept: forth.Cell = -1,
    host_fails: bool = false,
    close_fails: bool = false,
    command: [64]u8 = undefined,
    command_len: usize = 0,
    files: [4]FakeFile = .{ .{}, .{}, .{}, .{} },
    stdout_bytes: [64]u8 = undefined,
    stdout_len: usize = 0,

    fn write(context: ?*anyopaque, bytes: []const u8) void {
        const output: *Output = @ptrCast(@alignCast(context.?));
        const count = @min(bytes.len, output.bytes.len - output.len);
        @memcpy(output.bytes[output.len .. output.len + count], bytes[0..count]);
        output.len += count;
    }

    fn writer(self: *Output) forth.Writer {
        return .{ .context = @ptrCast(self), .write_fn = write, .read_fn = read, .key_fn = key, .key_ready_fn = keyReady, .sleep_fn = sleep, .utime_fn = utime, .getenv_fn = getenv, .system_fn = system, .file_ops = &fake_file_ops };
    }

    fn sleep(context: ?*anyopaque, milliseconds: forth.Cell) forth.RuntimeError!void {
        const output: *Output = @ptrCast(@alignCast(context.?));
        if (output.host_fails) return error.HostFailed;
        output.slept = milliseconds;
    }

    fn utime(context: ?*anyopaque) forth.RuntimeError!forth.Double {
        const output: *Output = @ptrCast(@alignCast(context.?));
        if (output.host_fails) return error.HostFailed;
        return 1_700_000_000_000_000;
    }

    fn getenv(_: ?*anyopaque, name: []const u8, buffer: []u8) forth.RuntimeError!?usize {
        const value: []const u8 = if (std.mem.eql(u8, name, "HOME")) "/home/lemon" else if (std.mem.eql(u8, name, "EMPTY")) "" else if (std.mem.eql(u8, name, "LONG")) &([_]u8{'x'} ** 4000) else return null;
        if (value.len > buffer.len) return error.StringTooLong;
        @memcpy(buffer[0..value.len], value);
        return value.len;
    }

    fn system(context: ?*anyopaque, command: []const u8) forth.RuntimeError!void {
        const output: *Output = @ptrCast(@alignCast(context.?));
        if (std.mem.eql(u8, command, "fail")) return error.HostFailed;
        @memcpy(output.command[0..command.len], command);
        output.command_len = command.len;
    }

    fn key(context: ?*anyopaque) ?u8 {
        const output: *Output = @ptrCast(@alignCast(context.?));
        if (output.key_index == output.keys.len) return null;
        output.key_index += 1;
        return output.keys[output.key_index - 1];
    }

    fn keyReady(context: ?*anyopaque) bool {
        const output: *Output = @ptrCast(@alignCast(context.?));
        return output.key_index < output.keys.len;
    }

    fn read(context: ?*anyopaque, buffer: []u8) ?[]const u8 {
        const output: *Output = @ptrCast(@alignCast(context.?));
        if (output.input_index == output.input_count) return null;
        const line = output.input_lines[output.input_index];
        output.input_index += 1;
        if (line.len > buffer.len) return null;
        @memcpy(buffer[0..line.len], line);
        return buffer[0..line.len];
    }

    fn written(self: *const Output) []const u8 {
        return self.bytes[0..self.len];
    }
};

/// An in-memory file for the fake host; "a.txt" and "b.txt" are the only names.
const FakeFile = struct {
    data: [512]u8 = undefined,
    len: usize = 0,
    position: usize = 0,
    open: bool = false,
    exists: bool = false,
};

const fake_file_names = [_][]const u8{ "a.txt", "b.txt", "c.txt", "d.txt" };

fn setFakeFile(output: *Output, index: usize, text: []const u8) void {
    @memcpy(output.files[index].data[0..text.len], text);
    output.files[index].len = text.len;
    output.files[index].exists = true;
}

const fake_file_ops = forth.FileOps{ .open = fakeOpen, .close = fakeClose, .read_line = fakeReadLine, .write = fakeWrite, .size = fakeSize, .reposition = fakeReposition };

fn fakeOutput(context: ?*anyopaque) *Output {
    return @ptrCast(@alignCast(context.?));
}

fn fakeFile(context: ?*anyopaque, fileid: forth.Cell) ?*FakeFile {
    const output = fakeOutput(context);
    if (fileid < forth.first_file_id or fileid - forth.first_file_id >= output.files.len) return null;
    const file = &output.files[@intCast(fileid - forth.first_file_id)];
    return if (file.open) file else null;
}

fn fakeOpen(context: ?*anyopaque, name: []const u8, _: forth.FileAccess, create: bool) forth.FileResult {
    const index: usize = for (fake_file_names, 0..) |known, position| {
        if (std.mem.eql(u8, name, known)) break position;
    } else return .{ .ior = forth.errnoIor(2) };
    const file = &fakeOutput(context).files[index];
    if (!create and !file.exists) return .{ .ior = forth.errnoIor(2) };
    if (create) file.len = 0;
    file.exists = true;
    file.open = true;
    file.position = 0;
    return .{ .value = @intCast(forth.first_file_id + @as(forth.Cell, @intCast(index))) };
}

fn fakeClose(context: ?*anyopaque, fileid: forth.Cell) forth.Cell {
    const file = fakeFile(context, fileid) orelse return forth.errnoIor(forth.errno_bad_file);
    file.open = false;
    return if (fakeOutput(context).close_fails) forth.errnoIor(5) else 0;
}

fn fakeReadLine(context: ?*anyopaque, fileid: forth.Cell, buffer: []u8) forth.LineResult {
    const file = fakeFile(context, fileid) orelse return .{ .ior = forth.errnoIor(forth.errno_bad_file) };
    if (file.position >= file.len) return .{};
    var length: usize = 0;
    while (length < buffer.len and file.position < file.len) {
        const byte = file.data[file.position];
        file.position += 1;
        if (byte == '\n') break;
        if (byte == '\r') continue;
        buffer[length] = byte;
        length += 1;
    }
    return .{ .length = length, .found = true };
}

fn fakeWrite(context: ?*anyopaque, fileid: forth.Cell, bytes: []const u8) forth.Cell {
    if (fileid == forth.stdout_fileid) {
        const output = fakeOutput(context);
        @memcpy(output.stdout_bytes[output.stdout_len .. output.stdout_len + bytes.len], bytes);
        output.stdout_len += bytes.len;
        return 0;
    }
    const file = fakeFile(context, fileid) orelse return forth.errnoIor(forth.errno_bad_file);
    @memcpy(file.data[file.position .. file.position + bytes.len], bytes);
    file.position += bytes.len;
    file.len = @max(file.len, file.position);
    return 0;
}

fn fakeSize(context: ?*anyopaque, fileid: forth.Cell) forth.FileResult {
    const file = fakeFile(context, fileid) orelse return .{ .ior = forth.errnoIor(forth.errno_bad_file) };
    return .{ .value = file.len };
}

fn fakeReposition(context: ?*anyopaque, fileid: forth.Cell, position: forth.UCell) forth.Cell {
    const file = fakeFile(context, fileid) orelse return forth.errnoIor(forth.errno_bad_file);
    file.position = @intCast(position);
    return 0;
}

fn createMachine(output: *Output) !*forth.State {
    const machine = try std.testing.allocator.create(forth.State);
    machine.* = forth.State.init(output.writer());
    return machine;
}

/// Feeds a definition of `count` literals over several lines, since one input line holds
/// at most `forth.tib_size` bytes.
fn interpretLiteralDefinition(machine: *forth.State, prefix: []const u8, count: usize) !void {
    try machine.interpretLine(prefix);
    var line: [2000]u8 = undefined;
    var remaining = count;
    while (remaining > 0) {
        const batch: usize = @min(remaining, line.len / 2);
        for (0..batch) |index| @memcpy(line[index * 2 ..][0..2], "1 ");
        try machine.interpretLine(line[0 .. batch * 2]);
        remaining -= batch;
    }
    try machine.interpretLine(";");
}

fn destroyMachine(machine: *forth.State) void {
    std.testing.allocator.destroy(machine);
}

fn expectStack(machine: *const forth.State, expected: []const forth.Cell) !void {
    try std.testing.expectEqual(expected.len, machine.data_depth);
    try std.testing.expectEqualSlices(forth.Cell, expected, machine.data_stack[0..machine.data_depth]);
}

fn expectFloatStack(machine: *const forth.State, expected: []const forth.Float) !void {
    try std.testing.expectEqual(expected.len, machine.float_depth);
    try std.testing.expectEqualSlices(forth.Float, expected, machine.float_stack[0..machine.float_depth]);
}

fn expectOutput(line: []const u8, expected: []const u8) !void {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    try machine.interpretLine(line);
    try std.testing.expectEqualStrings(expected, output.written());
}

test "64-bit arithmetic wraps and division floors toward negative infinity" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("9223372036854775807 1 + -7 3 /MOD -7 2 / -7 2 MOD 7 -2 MOD");

    const expected = [_]forth.Cell{ std.math.minInt(forth.Cell), 2, -3, -4, 1, -1 };
    try expectStack(machine, &expected);
}

test "true flags are all bits set and zero remains false" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("1 1 = 0 0= AND 0 1 = OR 1 2 < 2 1 < NOT TRUE FALSE");

    const expected = [_]forth.Cell{ -1, -1, -1, -1, 0 };
    try expectStack(machine, &expected);
}

test "dictionary uses case-insensitive full-name identity" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine(": ABCDE1 1 ; : ABCDE2 2 ; abcde1 abcde2");

    const expected = [_]forth.Cell{ 1, 2 };
    try expectStack(machine, &expected);
}

test "compiled nested loops and outer indices produce expected result" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine(": TOTAL 0 3 0 DO 2 0 DO I J + + LOOP LOOP ; TOTAL");

    const expected = [_]forth.Cell{9};
    try expectStack(machine, &expected);
}

test "q-do skips an empty range and do enters an equal range once" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine(": SKIP 0 5 5 ?DO 1 + LOOP ; : ONCE 0 5 5 DO 1 + LOOP ; SKIP ONCE");

    const expected = [_]forth.Cell{ 0, 1 };
    try expectStack(machine, &expected);
}

test "variable array and string operations use the portable data area" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("VARIABLE V 123 V ! V @ 2 ARRAY A 42 1 A A! 1 A A@ : MESSAGE \" OK\" TYPE ; MESSAGE");

    const expected = [_]forth.Cell{ 123, 42 };
    try expectStack(machine, &expected);
    try std.testing.expectEqualStrings("OK", output.written());
}

test "number output is followed by a space and CR emits a newline" {
    try expectOutput("3 . -3 . CR", "3 -3 \n");
}

test "number output uses signed digits without zero padding in every base" {
    try expectOutput("HEX FF . -1 . 10 U. DECIMAL -1 U. 8 OCT . DECIMAL 300 C.", "FF -1 10 18446744073709551615 10 44 ");
}

test "dot-s shows depth and items without consuming them" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("1 -2 3 .S");

    try std.testing.expectEqualStrings("<3> 1 -2 3 ", output.written());
    const expected = [_]forth.Cell{ 1, -2, 3 };
    try expectStack(machine, &expected);
}

test "error reporting resets the stack and reports the unknown token" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    machine.interpretLine("1 MISSING") catch |err| machine.report(err);

    try expectStack(machine, &.{});
    try std.testing.expectEqualStrings("MISSING ?\n", output.written());
}

test "forget removes later words and reclaims their data allocation" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine(": KEEP 11 ; 2 ARRAY RECLAIM FORGET RECLAIM HERE KEEP");

    const expected = [_]forth.Cell{ 0x4000, 11 };
    try expectStack(machine, &expected);
    try std.testing.expectEqual(@as(forth.Cell, 0x4000), machine.data_here);

    const missing = machine.interpretLine("RECLAIM");
    try std.testing.expectError(error.UnknownWord, missing);
    machine.report(error.UnknownWord);
    try std.testing.expectEqualStrings("RECLAIM ?\n", output.written());
}

test "forget reclaims compiled code for later definitions" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine(": KEEP 11 ; : REMOVE 22 ; FORGET REMOVE KEEP");
    const before_redefinition = [_]forth.Cell{11};
    try expectStack(machine, &before_redefinition);

    try machine.interpretLine(": REMOVE 33 ; REMOVE");
    const expected = [_]forth.Cell{ 11, 33 };
    try expectStack(machine, &expected);
}

test "failed definition is rolled back and the interpreter recovers" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    const initial_words = machine.word_count;
    const initial_code = machine.code_count;

    const invalid = machine.interpretLine(": BROKEN 1 MISSING");
    try std.testing.expectError(error.UnknownWord, invalid);
    machine.report(error.UnknownWord);
    try std.testing.expectEqual(initial_words, machine.word_count);
    try std.testing.expectEqual(initial_code, machine.code_count);

    try machine.interpretLine(": GOOD 9 ; GOOD");
    const expected = [_]forth.Cell{9};
    try expectStack(machine, &expected);
}

test "data allocation stops at the start of the heap without moving the allocation pointer" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("1032192 ALLOT HERE");
    const expected = [_]forth.Cell{forth.data_limit};
    try expectStack(machine, &expected);
    try std.testing.expectEqual(@as(forth.Cell, forth.data_limit), machine.data_here);

    const overflow = machine.interpretLine("1 ALLOT");
    try std.testing.expectError(error.MemoryExhausted, overflow);
    machine.report(error.MemoryExhausted);
    try std.testing.expectEqual(@as(forth.Cell, forth.data_limit), machine.data_here);
}

test "cell access is 64-bit little-endian and rejects addresses outside logical memory" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("-2 2097144 ! 2097144 @ 2097144 C@ 2097151 C@");
    const expected = [_]forth.Cell{ -2, 0xfe, 0xff };
    try expectStack(machine, &expected);

    try std.testing.expectError(error.InvalidAddress, machine.interpretLine("2097145 @"));
    machine.report(error.InvalidAddress);
    try std.testing.expectError(error.InvalidAddress, machine.interpretLine("-1 C@"));
    machine.report(error.InvalidAddress);
    try std.testing.expectEqualStrings("INVALID MEMORY ADDRESS !\nINVALID MEMORY ADDRESS !\n", output.written());
}

test "division by zero is reported as an error" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try std.testing.expectError(error.DivisionByZero, machine.interpretLine("7 0 /"));
    machine.report(error.DivisionByZero);
    try std.testing.expectError(error.DivisionByZero, machine.interpretLine("7 0 MOD"));
    machine.report(error.DivisionByZero);
    try std.testing.expectError(error.DivisionByZero, machine.interpretLine("7 0 /MOD"));
    machine.report(error.DivisionByZero);
    try expectStack(machine, &.{});
    try std.testing.expectEqualStrings("DIVISION BY ZERO !\nDIVISION BY ZERO !\nDIVISION BY ZERO !\n", output.written());
}

test "stack overflow is reported and subsequent input can run" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
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
    try expectStack(machine, &.{});

    try machine.interpretLine("2 3 +");
    const expected = [_]forth.Cell{5};
    try expectStack(machine, &expected);
}

test "return stack overflow and underflow reset cleanly" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    for (0..1024) |_| try machine.interpretLine("0 >R");
    try std.testing.expectEqual(@as(usize, 1024), machine.return_depth);
    const overflow = machine.interpretLine("0 >R");
    try std.testing.expectError(error.ReturnStackOverflow, overflow);
    machine.report(error.ReturnStackOverflow);
    try std.testing.expectEqual(@as(usize, 0), machine.return_depth);
    try expectStack(machine, &.{});

    const underflow = machine.interpretLine("R>");
    try std.testing.expectError(error.ReturnStackUnderflow, underflow);
    machine.report(error.ReturnStackUnderflow);
    try std.testing.expectEqual(@as(usize, 0), machine.return_depth);
}

test "dictionary capacity failure preserves existing words" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
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
    try expectStack(machine, &expected);
}

test "control nesting overflow rolls back the incomplete definition" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
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
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    const initial_words = machine.word_count;
    const initial_code = machine.code_count;
    const overflow = interpretLiteralDefinition(machine, ": TOO-LONG", 8192);
    try std.testing.expectError(error.CodeFull, overflow);
    machine.report(error.CodeFull);
    try std.testing.expectEqual(initial_words, machine.word_count);
    try std.testing.expectEqual(initial_code, machine.code_count);
}

test "nested IF ELSE THEN selects every branch" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine(": SELECT DUP 0= IF DROP 10 ELSE DUP 1 = IF DROP 20 ELSE DROP 30 THEN THEN ; 0 SELECT 1 SELECT 2 SELECT");

    const expected = [_]forth.Cell{ 10, 20, 30 };
    try expectStack(machine, &expected);
}

test "BEGIN WHILE REPEAT and BEGIN END compile and run" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine(": COUNT-UP 0 BEGIN DUP 3 < WHILE 1 + REPEAT ;");
    try machine.interpretLine(": COUNT-TO 0 BEGIN 1 + DUP 3 = END ;");
    try machine.interpretLine("COUNT-UP COUNT-TO");

    const expected = [_]forth.Cell{ 3, 3 };
    try expectStack(machine, &expected);
}

test "+LOOP handles positive and negative increments at the boundary" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine(": COUNT-UP 0 5 0 DO 1 + 2 +LOOP ; : COUNT-DOWN 0 0 3 DO 1 + -1 +LOOP ; COUNT-UP COUNT-DOWN");

    const expected = [_]forth.Cell{ 3, 4 };
    try expectStack(machine, &expected);
}

test "LEAVE exits the active loop without losing the outer result" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine(": SUM-UNTIL-FIVE 0 10 0 DO I 5 = IF LEAVE ELSE I + THEN LOOP ; SUM-UNTIL-FIVE");

    const expected = [_]forth.Cell{10};
    try expectStack(machine, &expected);
}

test "multiline definitions and immediate string output preserve compiler state" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine(": GREET");
    try machine.interpretLine("\" HELLO\" TYPE ;");
    try machine.interpretLine("GREET : SAY .\" SIGMA\" ; SAY");

    try std.testing.expectEqualStrings("HELLOSIGMA", output.written());
}

test "quoted string length is limited to 127 bytes" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    var input: [256]u8 = undefined;
    var used: usize = 0;
    const prefix = ": TEXT \" ";
    @memcpy(input[used .. used + prefix.len], prefix);
    used += prefix.len;
    @memset(input[used .. used + 127], 'X');
    used += 127;
    const suffix = "\" TYPE ; TEXT";
    @memcpy(input[used .. used + suffix.len], suffix);
    used += suffix.len;
    try machine.interpretLine(input[0..used]);
    try std.testing.expectEqual(@as(usize, 127), output.len);
    try std.testing.expect(std.mem.allEqual(u8, output.written(), 'X'));

    var oversized: [256]u8 = undefined;
    var oversized_len: usize = 0;
    const oversized_prefix = ": TOO-LONG \" ";
    @memcpy(oversized[oversized_len .. oversized_len + oversized_prefix.len], oversized_prefix);
    oversized_len += oversized_prefix.len;
    @memset(oversized[oversized_len .. oversized_len + 128], 'Y');
    oversized_len += 128;
    oversized[oversized_len] = '"';
    oversized_len += 1;

    const too_long = machine.interpretLine(oversized[0..oversized_len]);
    try std.testing.expectError(error.MemoryExhausted, too_long);
    machine.report(error.MemoryExhausted);
    try std.testing.expectEqual(@as(forth.Cell, 0x4000 + 128), machine.data_here);
}

test "redefinition warns and subsequent lookup uses the newest definition" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine(": TWICE 1 ; : TWICE 2 ; TWICE");

    const expected = [_]forth.Cell{2};
    try expectStack(machine, &expected);
    try std.testing.expectEqualStrings("WARNING: SAME NAME WORD EXISTS\n", output.written());
}

test "<BUILDS and DOES> attach a compiled behavior to created words" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine(": CELL <BUILDS , DOES> @ ; 42 CELL ANSWER 43 CELL OTHER ANSWER OTHER");

    const expected = [_]forth.Cell{ 42, 43 };
    try expectStack(machine, &expected);
    try std.testing.expectEqual(@as(forth.Cell, forth.data_start + 16), machine.data_here);
}

test "<BUILDS reads a created word name from the next input line" {
    var output = Output{};
    output.input_lines[0] = "ACROSS-LINE";
    output.input_count = 1;
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine(": CELL <BUILDS , DOES> @ ;");
    try machine.interpretLine("73 CELL");
    try machine.interpretLine("ACROSS-LINE");

    const expected = [_]forth.Cell{73};
    try expectStack(machine, &expected);
}

test "FORGET removes created words and their data can be reused" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine(": CELL <BUILDS , DOES> @ ; 42 CELL FIRST 43 CELL SECOND FORGET SECOND 44 CELL THIRD FIRST THIRD");

    const expected = [_]forth.Cell{ 42, 44 };
    try expectStack(machine, &expected);
    try std.testing.expectEqual(@as(forth.Cell, forth.data_start + 16), machine.data_here);
}

test "LEAVE exits immediately and UNLOOP allows EXIT from a loop" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine(": STOP-AT-3 0 10 0 DO I 3 = IF LEAVE THEN 1+ LOOP ;");
    try machine.interpretLine(": FIND-4 10 0 DO I 4 = IF I UNLOOP EXIT THEN LOOP -1 ;");
    try machine.interpretLine("STOP-AT-3 FIND-4");

    const expected = [_]forth.Cell{ 3, 4 };
    try expectStack(machine, &expected);
    try std.testing.expectEqual(@as(usize, 0), machine.loop_depth);
}

test "stack words follow the standard stack effects" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("1 2 3 -ROT NIP 4 TUCK 2DUP 2DROP DEPTH 9 8 7 2 PICK 3 ROLL 5 >R R@ R> 2SWAP 2OVER");

    const expected = [_]forth.Cell{ 3, 4, 2, 4, 4, 8, 7, 5, 5, 9, 9, 5, 5 };
    try expectStack(machine, &expected);
}

test "basic standard words cover bit shifts, cells, characters, and number prefixes" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("1 4 LSHIFT -1 60 RSHIFT 3 CELLS 0 CELL+ 9 ALIGNED BL CHAR A : Z [CHAR] Z ; Z $FF #10 %101 'a' -7 2/ 1 \\ 2 3");

    const expected = [_]forth.Cell{ 16, 15, 24, 8, 16, 32, 65, 90, 255, 10, 5, 97, -4, 1 };
    try expectStack(machine, &expected);
}

test "memory words fill, erase, move, and switch flags on and off" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("CREATE BUF 16 ALLOT BUF 4 65 FILL BUF BUF 1+ 3 MOVE BUF 3 + 1 ERASE BUF 4 TYPE VARIABLE F F ON F @ F OFF F @");

    const expected = [_]forth.Cell{ -1, 0 };
    try expectStack(machine, &expected);
    try std.testing.expectEqualStrings("AAA\x00", output.written());
}

test "UNTIL AGAIN EXIT and RECURSE compile structured definitions" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine(": U 0 BEGIN 1+ DUP 3 = UNTIL ; : A 0 BEGIN 1+ DUP 5 = IF EXIT THEN AGAIN ;");
    try machine.interpretLine(": FACT DUP 1 > IF DUP 1- RECURSE * THEN ; U A 20 FACT");

    const expected = [_]forth.Cell{ 3, 5, 2432902008176640000 };
    try expectStack(machine, &expected);
}

test "CASE OF ENDOF ENDCASE selects a branch and drops the selector" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine(": PICK-ONE CASE 1 OF 10 ENDOF 2 OF 20 ENDOF 99 SWAP ENDCASE ; 1 PICK-ONE 2 PICK-ONE 3 PICK-ONE");

    const expected = [_]forth.Cell{ 10, 20, 99 };
    try expectStack(machine, &expected);
}

test "VALUE and TO work interpreted and compiled" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("5 VALUE X X 7 TO X X : SETX TO X ; 9 SETX X");

    const expected = [_]forth.Cell{ 5, 7, 9 };
    try expectStack(machine, &expected);
}

test "IMMEDIATE and POSTPONE extend the compiler" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine(": MY-IF POSTPONE IF ; IMMEDIATE : SIGNED MY-IF 1 ELSE 2 THEN ; -1 SIGNED 0 SIGNED");
    try machine.interpretLine(": FIVE 5 ; : COMPILE-FIVE POSTPONE FIVE ; IMMEDIATE : USE-FIVE COMPILE-FIVE ; USE-FIVE");

    const expected = [_]forth.Cell{ 1, 2, 5 };
    try expectStack(machine, &expected);
}

test "compile-only words are rejected while interpreting" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try std.testing.expectError(error.CompileOnly, machine.interpretLine("1 IF"));
    machine.report(error.CompileOnly);
    try std.testing.expectError(error.CompileOnly, machine.interpretLine("EXIT"));
    machine.report(error.CompileOnly);
    try std.testing.expectError(error.CompileOnly, machine.interpretLine("LEAVE"));
    machine.report(error.CompileOnly);
}

test "float literals require an exponent and use a separate stack" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("1 1E 1.5e0 .5E -2.25E+1 0.e 3");

    const expected = [_]forth.Cell{ 1, 3 };
    try expectStack(machine, &expected);
    const floats = [_]forth.Float{ 1.0, 1.5, 0.5, -22.5, 0.0 };
    try expectFloatStack(machine, &floats);

    try machine.interpretLine("2DROP 1.5 HEX 1E DECIMAL");
    const not_floats = [_]forth.Cell{ 15, 0, 0x1e };
    try expectStack(machine, &not_floats);
    try expectFloatStack(machine, &floats);
}

test "F. prints fixed notation with 15 significant digits and a trailing space" {
    try expectOutput("1E 2E F+ F. 1.5E F. 0.5E F. 1E-5 F. 1E20 F. -2.5E F. 0E F. 123E F. 2E FSQRT F.", "3. 1.5 0.5 0.00001 100000000000000000000. -2.5 0. 123. 1.4142135623731 ");
}

test "F. prints non-finite values by name" {
    try expectOutput("1E 0E F/ F. -1E 0E F/ F. 0E 0E F/ F.", "infinity -infinity NaN ");
}

test "F.S shows each float as 14 0 17 F.RDP does" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("1E 2E 0.5E 1E-7 -3.25E 1E30 F.S");

    try std.testing.expectEqualStrings("<6> 1.0000000000E0 2.0000000000E0 5.000000000E-1 1.000000000E-7 -3.250000000E0 1.000000000E30 ", output.written());
    try std.testing.expectEqual(@as(usize, 6), machine.float_depth);
}

test "float arithmetic comparison and conversion" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("1E 2E F< 2E 1E F< 1E 1E F= 0E F0= -1E F0< 10 S>F 4E F/ F>S 2.9E F>S -2.9E F>S FDEPTH");
    const expected = [_]forth.Cell{ -1, 0, -1, -1, -1, 2, 2, -2, 0 };
    try expectStack(machine, &expected);

    try machine.interpretLine("3E 4E FMAX -5E FABS FMIN 2E FNEGATE 1E FOVER FSWAP FDROP FNIP 7E 8E FTUCK F-ROT FROT 1 FPICK");
    const floats = [_]forth.Float{ 4.0, -2.0, 8.0, 7.0, 8.0, 7.0 };
    try expectFloatStack(machine, &floats);
}

test "float math functions follow the host libm" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("9E FSQRT 0E FEXP 1E FLN 0E FSIN 0E FCOS 0E FTAN");

    const floats = [_]forth.Float{ 3.0, 1.0, 0.0, 0.0, 1.0, 0.0 };
    try expectFloatStack(machine, &floats);
}

test "float memory, variables, constants, and arrays" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("CREATE TEMP 1 FLOATS ALLOT 37.5E TEMP F! TEMP F@ F.");
    try machine.interpretLine("FVARIABLE ACC 1.5E ACC F! 2E ACC F+! ACC F?");
    try machine.interpretLine("3.1415926535E FCONSTANT MYPI : AREA FDUP F* MYPI F* ; 5E AREA F.");
    try machine.interpretLine("3 FARRAY POINTS 1.25E 2 POINTS FA! 2 POINTS FA@ F. HERE 0 FLOAT+ 2 FLOATS");
    try machine.interpretLine(": HALF 0.5E F* ; 3E HALF F. HERE 6.5E F, F@ F.");

    try std.testing.expectEqualStrings("37.5 3.5 78.5398163375 1.25 1.5 6.5 ", output.written());
    try std.testing.expectEqual(@as(usize, 3), machine.data_depth);
    try std.testing.expectEqual(@as(forth.Cell, 8), machine.data_stack[1]);
    try std.testing.expectEqual(@as(forth.Cell, 16), machine.data_stack[2]);
}

test "float stack underflow is reported and both stacks are reset" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try std.testing.expectError(error.FloatStackUnderflow, machine.interpretLine("1 1E F+"));
    machine.report(error.FloatStackUnderflow);
    try expectStack(machine, &.{});
    try expectFloatStack(machine, &.{});
    try std.testing.expectEqualStrings("FLOATING-POINT STACK UNDER FLOW !\n", output.written());
}

test "FINPUT reads a float and INPUT reads a 64-bit integer" {
    var output = Output{};
    output.input_lines[0] = "abc";
    output.input_lines[1] = "2.5";
    output.input_lines[2] = "-9000000000";
    output.input_count = 3;
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("FINPUT INPUT");

    const expected = [_]forth.Cell{-9000000000};
    try expectStack(machine, &expected);
    const floats = [_]forth.Float{2.5};
    try expectFloatStack(machine, &floats);
    try std.testing.expectEqualStrings(" ?\n", output.written());
}

test "dictionary image round trip relocates words, floats, values, and strings" {
    var output = Output{};
    const source = try createMachine(&output);
    defer destroyMachine(source);
    try source.interpretLine("2.5E FCONSTANT RATE 4 VALUE COUNTER VARIABLE V 11 V ! 70000000000000000000. 2CONSTANT HUGE");
    try source.interpretLine(": SCALE RATE F* ; : BUMP COUNTER 1+ TO COUNTER ; : SAY \" HI\" TYPE ;");
    const image = try std.testing.allocator.alloc(u8, forth.State.imageCapacity());
    defer std.testing.allocator.free(image);
    const length = try source.encodeImage(image);

    const loaded = try createMachine(&output);
    defer destroyMachine(loaded);
    try loaded.restoreImage(image[0..length]);

    const target = try createMachine(&output);
    defer destroyMachine(target);
    try target.interpretLine("VARIABLE FIRST 1 FIRST ! : EARLIER 1 ;");
    try target.appendImage(loaded);
    try target.interpretLine("2E SCALE F. BUMP COUNTER V @ FIRST @ SAY HUGE D.");

    const expected = [_]forth.Cell{ 5, 11, 1 };
    try expectStack(target, &expected);
    try std.testing.expectEqualStrings("5. HI70000000000000000000 ", output.written());
}

test "numbers containing a dot are double-cell integers" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("123. -5. 12345.123 #10. $FF.");

    const expected = [_]forth.Cell{ 123, 0, -5, -1, 12345123, 0, 10, 0, 255, 0 };
    try expectStack(machine, &expected);
}

test "double arithmetic, comparison, and output exceed a single cell" {
    try expectOutput("1234567890000000000. 9876543210000000000. D+ D. -1. D. 5 S>D D. -7 S>D DABS D. 3. DNEGATE D.", "11111111100000000000 -1 5 7 -3 ");
}

test "2! and 2@ store a double with the high cell first" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("CREATE BIGNUM 2 CELLS ALLOT 12345678901234567890 1 BIGNUM 2! BIGNUM 2@ D. BIGNUM @");
    try machine.interpretLine("2VARIABLE DV 7. DV 2! DV 2@ 42. 2CONSTANT ANSWER ANSWER D0= 0. D0= 1. 2. D< 3. 3. D= -1. D0< 9. D>S");

    try std.testing.expectEqualStrings("30792422974944119506 ", output.written());
    const expected = [_]forth.Cell{ 1, 7, 0, 0, -1, -1, -1, -1, 9 };
    try expectStack(machine, &expected);
}

test "pictured numeric output builds strings from the right" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine(": MY-U. 0 <<# #S #> TYPE SPACE #>> ;");
    try machine.interpretLine(": DOLLARS 0 <<# # # [CHAR] . HOLD #S [CHAR] $ HOLD #> TYPE SPACE #>> ;");
    try machine.interpretLine(": MY-. S>D SWAP OVER DABS <<# #S ROT SIGN #> TYPE SPACE #>> ;");
    try machine.interpretLine("123 MY-U. 1234 DOLLARS 5 DOLLARS -123 MY-. 456 MY-. 255 HEX MY-U. DECIMAL");
    try machine.interpretLine("<# 7 0 # # S\" ab\" HOLDS #> TYPE");

    try std.testing.expectEqualStrings("123 $12.34 $0.05 -123 456 FF ab07", output.written());
    try std.testing.expectEqual(@as(usize, 0), machine.data_depth);
}

test "nested hold areas keep the outer conversion" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("<<# 12 0 #S <<# 34 0 #S #> TYPE #>> #> TYPE #>>");

    try std.testing.expectEqualStrings("3412", output.written());
    try std.testing.expectError(error.PicturedNumericOverflow, machine.interpretLine("#>>"));
    machine.report(error.PicturedNumericOverflow);
}

test "S\" and S\\\" return strings while interpreting and compiling" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("S\" Hello, Forth!\" TYPE CR : GREET S\" compiled\" TYPE ; GREET CR");
    try machine.interpretLine("S\\\" a\\tb\\x41\\\"q\" TYPE .\\\" x\\ny\" : SAY .\\\" [\\q]\" ; SAY .( paren) CR");
    try machine.interpretLine("CREATE BUF 20 ALLOT S\" Forth\" TUCK BUF SWAP MOVE BUF SWAP TYPE");

    try std.testing.expectEqualStrings("Hello, Forth!\ncompiled\na\tbA\"qx\ny[\"]paren\nForth", output.written());
}

test "S\" keeps several interpreted strings alive" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("S\" one\" S\" two\" S\" three\" TYPE TYPE TYPE");

    try std.testing.expectEqualStrings("threetwoone", output.written());
}

test "COUNT and PAD give addressable buffers" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("3 PAD C! 65 PAD 1+ C! 66 PAD 2 + C! 67 PAD 3 + C! PAD COUNT TYPE PAD");

    try std.testing.expectEqualStrings("ABC", output.written());
    const expected = [_]forth.Cell{forth.pad_address};
    try expectStack(machine, &expected);
}

test ">NUMBER S>NUMBER? and >FLOAT convert strings" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("0. S\" 123x\" >NUMBER NIP S\" -42\" S>NUMBER? S\" 3.14\" S>NUMBER? S\" nope\" S>NUMBER?");
    const expected = [_]forth.Cell{ 123, 0, 1, -42, -1, -1, 314, 0, -1, 0, 0, 0 };
    try expectStack(machine, &expected);
}

test ">FLOAT accepts decimal text without an exponent" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("S\" 2.5\" >FLOAT S\" 1e3\" >FLOAT S\" x\" >FLOAT S\"  \" >FLOAT 7. D>F 2.9E F>D");

    const expected = [_]forth.Cell{ -1, -1, 0, -1, 2, 0 };
    try expectStack(machine, &expected);
    const floats = [_]forth.Float{ 2.5, 1000.0, 0.0, 7.0 };
    try expectFloatStack(machine, &floats);
}

test "ACCEPT and EVALUATE read and interpret a line" {
    var output = Output{};
    output.input_lines[0] = "2 3 + 4 *";
    output.input_count = 1;
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("PAD 80 ACCEPT PAD SWAP EVALUATE S\" : SQ DUP * ;\" EVALUATE 5 SQ");

    const expected = [_]forth.Cell{ 20, 25 };
    try expectStack(machine, &expected);
}

test "KEY and KEY? read single characters" {
    var output = Output{};
    output.keys = "hi";
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine(": ECHO-ALL BEGIN KEY? WHILE KEY EMIT REPEAT ; ECHO-ALL KEY?");

    try std.testing.expectEqualStrings("hi", output.written());
    const expected = [_]forth.Cell{0};
    try expectStack(machine, &expected);
}

test "WITHIN tests a half-open range with wrap-around like gforth" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("5 0 10 WITHIN 10 0 10 WITHIN -1 0 10 WITHIN 0 -5 -1 WITHIN 5 5 5 WITHIN 3 10 0 WITHIN 11 10 0 WITHIN");
    try machine.interpretLine("9223372036854775807 9223372036854775807 -9223372036854775808 WITHIN -9223372036854775808 9223372036854775807 -9223372036854775808 WITHIN");

    const expected = [_]forth.Cell{ -1, 0, 0, 0, 0, 0, -1, -1, 0 };
    try expectStack(machine, &expected);
}

test "2>R and 2R> move a cell pair and keep its order" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine(": T 1 2 2>R 3 2R> ; T");
    const expected = [_]forth.Cell{ 3, 1, 2 };
    try expectStack(machine, &expected);

    machine.data_depth = 0;
    try std.testing.expectError(error.StackUnderflow, machine.interpretLine("1 2>R"));
    machine.report(error.StackUnderflow);
    try std.testing.expectEqual(@as(usize, 0), machine.return_depth);
    try std.testing.expectError(error.ReturnStackUnderflow, machine.interpretLine("1 >R 2R>"));
    machine.report(error.ReturnStackUnderflow);
}

test "ENDIF is an alias of THEN" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine(": S 0< IF -1 ELSE 1 ENDIF ; -5 S 5 S");

    const expected = [_]forth.Cell{ -1, 1 };
    try expectStack(machine, &expected);
}

test "PLACE stores a counted string, handles overlap, and limits the length to 255" {
    try expectOutput("S\" hello\" PAD PLACE PAD COUNT TYPE", "hello");
    try expectOutput("S\" abcde\" PAD SWAP MOVE PAD 5 PAD PLACE PAD COUNT TYPE", "abcde");
    try expectOutput("S\" vwxyz\" PAD 10 + SWAP MOVE PAD 10 + 5 PAD 7 + PLACE PAD 7 + COUNT TYPE", "vwxyz");

    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    try machine.interpretLine("PAD 255 PAD 512 + PLACE PAD 512 + C@ PAD 256 PAD 1024 + PLACE PAD 1024 + C@ PAD 0 2097151 PLACE");
    const expected = [_]forth.Cell{ 255, 255 };
    try expectStack(machine, &expected);
    try std.testing.expectError(error.InvalidAddress, machine.interpretLine("PAD 1 2097151 PLACE"));
}

test "STATE reflects the compiler state through a saved address" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("STATE @ STATE CONSTANT ST : CHECK ST @ ; IMMEDIATE : SAMPLE CHECK [ ST @ ] ; ST @");
    const expected = [_]forth.Cell{ 0, -1, 0, 0 };
    try expectStack(machine, &expected);

    try std.testing.expectError(error.UnknownWord, machine.interpretLine(": BROKEN MISSING"));
    machine.report(error.UnknownWord);
    try machine.interpretLine("ST @");
    try expectStack(machine, &.{0});
}

test "ABORT clears the stacks silently, even from EVALUATE" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try std.testing.expectError(error.Aborted, machine.interpretLine("1 2 ABORT 3"));
    machine.report(error.Aborted);
    try expectStack(machine, &.{});

    try std.testing.expectError(error.Aborted, machine.interpretLine("1E : STOP 1 ABORT 2 ; S\" STOP\" EVALUATE"));
    machine.report(error.Aborted);
    try expectStack(machine, &.{});
    try expectFloatStack(machine, &.{});
    try std.testing.expectEqualStrings("", output.written());
}

test ":NONAME compiles an unnamed definition and leaves its execution token" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    const initial_words = machine.word_count;

    try machine.interpretLine(":NONAME 2 * ; 21 SWAP EXECUTE :NONAME 42 ; CONSTANT ACTION ACTION EXECUTE");
    const expected = [_]forth.Cell{ 42, 42 };
    try expectStack(machine, &expected);

    try machine.interpretLine("WORDS");
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "  ") == null);

    try std.testing.expectError(error.InvalidDefinition, machine.interpretLine(": OUTER :NONAME ;"));
    machine.report(error.InvalidDefinition);
    try std.testing.expectError(error.UnknownWord, machine.interpretLine(":NONAME 1 MISSING"));
    machine.report(error.UnknownWord);
    // The two unnamed definitions and ACTION remain; OUTER and the failed one are rolled back.
    try std.testing.expectEqual(initial_words + 3, machine.word_count);
}

test "an execution token stored in a constant survives a full image restore" {
    var output = Output{};
    const source = try createMachine(&output);
    defer destroyMachine(source);
    try source.interpretLine(":NONAME 42 ; CONSTANT ACTION");
    const image = try std.testing.allocator.alloc(u8, forth.State.imageCapacity());
    defer std.testing.allocator.free(image);
    const length = try source.encodeImage(image);

    const loaded = try createMachine(&output);
    defer destroyMachine(loaded);
    try loaded.restoreImage(image[0..length]);
    try loaded.interpretLine("ACTION EXECUTE");
    try expectStack(loaded, &.{42});

    @memcpy(image[0..8], "SIGIMG02");
    try std.testing.expectError(error.InvalidImage, loaded.restoreImage(image[0..length]));
}

test "MS UTIME GETENV and SYSTEM call the host" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("250 MS UTIME S\" HOME\" GETENV TYPE S\" MISSING\" GETENV S\" EMPTY\" GETENV NIP S\" dir /b\" SYSTEM");
    try std.testing.expectEqual(@as(forth.Cell, 250), output.slept);
    try std.testing.expectEqualStrings("/home/lemon", output.written());
    try std.testing.expectEqualStrings("dir /b", output.command[0..output.command_len]);
    const expected = [_]forth.Cell{ 1_700_000_000_000_000, 0, 0, 0, 0 };
    try expectStack(machine, &expected);

    try std.testing.expectError(error.StringTooLong, machine.interpretLine("S\" LONG\" GETENV"));
    machine.report(error.StringTooLong);
    try std.testing.expectError(error.HostFailed, machine.interpretLine("S\" fail\" SYSTEM"));
    machine.report(error.HostFailed);
}

test "host words report an error when the host does not provide them" {
    var output = Output{};
    const machine = try std.testing.allocator.create(forth.State);
    defer destroyMachine(machine);
    machine.* = forth.State.init(.{ .context = @ptrCast(&output), .write_fn = Output.write });

    try std.testing.expectError(error.HostUnavailable, machine.interpretLine("1 MS"));
    machine.report(error.HostUnavailable);
    try std.testing.expectError(error.HostUnavailable, machine.interpretLine("S\" X\" SYSTEM"));
    machine.report(error.HostUnavailable);
    try std.testing.expectError(error.HostUnavailable, machine.interpretLine("UTIME"));
    machine.report(error.HostUnavailable);
    try std.testing.expectError(error.HostUnavailable, machine.interpretLine("S\" X\" GETENV"));
    machine.report(error.HostUnavailable);
    try std.testing.expectEqualStrings("HOST FUNCTION UNAVAILABLE !\n" ** 4, output.written());
    try expectStack(machine, &.{});
}

test "host failures in MS and UTIME are reported and leave a clean stack" {
    var output = Output{};
    output.host_fails = true;
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try std.testing.expectError(error.HostFailed, machine.interpretLine("7 100 MS"));
    machine.report(error.HostFailed);
    try std.testing.expectError(error.HostFailed, machine.interpretLine(": T UTIME ; T"));
    machine.report(error.HostFailed);
    try std.testing.expectEqualStrings("HOST FUNCTION ERROR !\nHOST FUNCTION ERROR !\n", output.written());
    try std.testing.expectEqual(@as(forth.Cell, -1), output.slept);
    try expectStack(machine, &.{});
}

test "PAGE clears the screen with ANSI sequences" {
    try expectOutput("PAGE", "\x1b[2J\x1b[1;1H");
}
test "THROW ignores zero, aborts on -1, and reports other codes in decimal" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("1 2 0 THROW");
    try expectStack(machine, &.{ 1, 2 });
    try std.testing.expectError(error.Aborted, machine.interpretLine("-1 THROW"));
    machine.report(error.Aborted);
    try expectStack(machine, &.{});

    const codes = [_][]const u8{ "-4 THROW", "-514 THROW", ": T -37 THROW ; T", "HEX 5 THROW" };
    // -4 is the code of the interpreter's stack underflow, so THROW raises that error.
    const errors = [_]anyerror{ error.StackUnderflow, error.Thrown, error.Thrown, error.Thrown };
    for (codes, errors) |line, expected| {
        try std.testing.expectError(expected, machine.interpretLine(line));
        machine.report(expected);
    }
    try std.testing.expectEqualStrings("STACK UNDER FLOW !\nNO SUCH FILE OR DIRECTORY !\nFILE I/O EXCEPTION !\nERROR #5 !\n", output.written());
}

test "file access methods and standard stream ids follow gforth" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("R/O W/O R/W STDIN STDOUT STDERR");
    try expectStack(machine, &.{ 0, 4, 2, 1, 2, 3 });
}

test "files are created, written, sized, repositioned, read by line, and closed" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    const newline = if (@import("builtin").os.tag == .windows) "\r\n" else "\n";

    try machine.interpretLine("S\" a.txt\" W/O CREATE-FILE THROW VALUE F");
    try machine.interpretLine("S\" abc\" F WRITE-LINE S\" de\" F WRITE-FILE F FILE-SIZE F CLOSE-FILE");
    try expectStack(machine, &.{ 0, 0, @intCast(5 + newline.len), 0, 0, 0 });
    try std.testing.expectEqualStrings("abc" ++ newline ++ "de", output.files[0].data[0..output.files[0].len]);

    machine.data_depth = 0;
    try machine.interpretLine("S\" a.txt\" R/O OPEN-FILE THROW TO F PAD 2 F READ-LINE PAD 10 F READ-LINE PAD 10 F READ-LINE PAD 10 F READ-LINE");
    try expectStack(machine, &.{ 2, -1, 0, 1, -1, 0, 2, -1, 0, 0, 0, 0 });
    machine.data_depth = 0;
    try machine.interpretLine("0. F REPOSITION-FILE PAD 10 F READ-LINE DROP DROP PAD SWAP TYPE F CLOSE-FILE F CLOSE-FILE");
    try std.testing.expectEqualStrings("abc", output.written());
    try expectStack(machine, &.{ 0, 0, forth.errnoIor(forth.errno_bad_file) });
}

test "file errors are returned as iors without changing the stack shape" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    const bad = forth.errnoIor(forth.errno_bad_file);
    const invalid = forth.errnoIor(forth.errno_invalid);

    try machine.interpretLine("S\" b.txt\" R/O OPEN-FILE S\" a.txt\" 99 OPEN-FILE 99 FILE-SIZE PAD 4 99 READ-LINE");
    try expectStack(machine, &.{ 0, forth.errnoIor(2), 0, invalid, 0, 0, bad, 0, 0, bad });
    machine.data_depth = 0;
    try machine.interpretLine("S\" a.txt\" W/O CREATE-FILE DROP -1 0 2 PICK REPOSITION-FILE NIP");
    try expectStack(machine, &.{invalid});
}

test "WRITE-LINE to STDOUT reaches the host" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    const newline = if (@import("builtin").os.tag == .windows) "\r\n" else "\n";

    try machine.interpretLine("S\" hi\" STDOUT WRITE-LINE");
    try expectStack(machine, &.{0});
    try std.testing.expectEqualStrings("hi" ++ newline, output.stdout_bytes[0..output.stdout_len]);
}

test "file words report an error when the host has no file support" {
    var output = Output{};
    const machine = try std.testing.allocator.create(forth.State);
    defer destroyMachine(machine);
    machine.* = forth.State.init(.{ .context = @ptrCast(&output), .write_fn = Output.write });

    try std.testing.expectError(error.HostUnavailable, machine.interpretLine("S\" a.txt\" R/O OPEN-FILE"));
}
test "ALLOCATE FREE and RESIZE manage the heap and reuse freed blocks" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    const no_memory = forth.errnoIor(forth.errno_no_memory);
    const invalid = forth.errnoIor(forth.errno_invalid);

    try machine.interpretLine("100 ALLOCATE THROW VALUE A 77 A ! A 1000 RESIZE THROW TO A A @ A FREE 100 ALLOCATE THROW A =");
    try expectStack(machine, &.{ 77, 0, -1 });
    machine.data_depth = 0;
    try machine.interpretLine("-1 ALLOCATE 2000000 ALLOCATE 12345 FREE 0 FREE A 8 + FREE");
    try expectStack(machine, &.{ 0, no_memory, 0, no_memory, invalid, 0, invalid });
    machine.data_depth = 0;
    try machine.interpretLine("0 16 RESIZE NIP A 2000000 RESIZE SWAP A =");
    try expectStack(machine, &.{ 0, no_memory, -1 });
}

test "freeing every block returns the heap to its start" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("16 ALLOCATE THROW 32 ALLOCATE THROW 64 ALLOCATE THROW ROT DUP >R FREE THROW FREE THROW FREE THROW 900000 ALLOCATE THROW R> =");
    try expectStack(machine, &.{-1});
}

test "dynamic string words follow the book's Level 14 example" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("VARIABLE S S\" Hello, World!\" S $! S $@ TYPE SPACE S $. SPACE S $@LEN . 7 S $!LEN S $. CR");
    try machine.interpretLine("S\" land\" S $+! '!' S C$+! S $. CR S\" new \" S 7 $INS S $. CR S 7 4 $DEL S $. CR S\" world\" S 7 $OVER S $. CR");
    try std.testing.expectEqualStrings("Hello, World! Hello, World! 13 Hello, \nHello, land!\nHello, new land!\nHello, land!\nHello, world\n", output.written());
    try machine.interpretLine("VARIABLE E E $@ E $@LEN S $FREE S @");
    try expectStack(machine, &.{ 0, 0, 0, 0 });
}

test "dynamic strings handle sources inside themselves and out-of-range edits" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("VARIABLE S S\" abc\" S $! S $@ S $+! S $@ DROP 1+ 2 S 0 $INS S $. SPACE");
    try machine.interpretLine("S 2 100 $DEL S $. SPACE S 99 0 $DEL S\" xy\" S 99 $INS S $. SPACE S\" Z\" S 4 $OVER S $@ TYPE");
    try std.testing.expectEqualStrings("bcabcabc bc bcxy bcxyZ", output.written());
    output.len = 0;
    try machine.interpretLine("S\" ab\" S $! S\" Z\" S 4 $OVER S $@ TYPE");
    try std.testing.expectEqualStrings("ab  Z", output.written());
}

test "$SPLIT and $ITER divide strings at a separator" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("S\" name=value\" '=' $SPLIT TYPE SPACE TYPE SPACE S\" novalue\" '=' $SPLIT NIP . TYPE CR");
    try machine.interpretLine(": PART TYPE [CHAR] | EMIT ; VARIABLE S S\" 1234,567,,890\" S $! S ',' ' PART $ITER");
    try std.testing.expectEqualStrings("value name 0 novalue\n1234|567||890|", output.written());
}

test "$TMP captures output, nests, and restores output after an error" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine(": INNER .\" in\" 7 . ; : OUTER .\" <\" ['] INNER $TMP TYPE .\" >\" ; ' OUTER $TMP SPACE TYPE");
    try std.testing.expectEqualStrings(" <in7 >", output.written());
    try std.testing.expectError(error.UnknownWord, machine.interpretLine(": BAD .\" x\" MISSING ;"));
    machine.report(error.UnknownWord);
    try std.testing.expectError(error.StackUnderflow, machine.interpretLine(": FAIL .\" hidden\" DROP ; ' FAIL $TMP"));
    machine.report(error.StackUnderflow);
    try std.testing.expectEqualStrings(" <in7 >MISSING ?\nSTACK UNDER FLOW !\n", output.written());
}

test "string arrays store, fetch, count, map, print, and free elements" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("VARIABLE N S\" Alice\" 0 N $[]! S\" Bob\" 1 N $[]! S\" Charlie\" 3 N $[]! 1 N $[]@ TYPE SPACE N $[]# . 2 N $[]@ . DROP 9 N $[]@ . DROP N $[]# . CR");
    try machine.interpretLine(": SHOW TYPE [CHAR] ; EMIT ; N ' SHOW $[]MAP CR N $[]. N $[]FREE N @ .");
    try std.testing.expectEqualStrings("Bob 4 0 0 4 \nAlice;Bob;;Charlie;\nAlice\nBob\n\nCharlie\n0 ", output.written());
}

test "$[]SLURP and $[]SLURP-FILE read a file line by line" {
    var output = Output{};
    const long = "x" ** 300;
    const text = "one\n\n" ++ long ++ "\nlast";
    @memcpy(output.files[1].data[0..text.len], text);
    output.files[1].len = text.len;
    output.files[1].exists = true;
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("VARIABLE L S\" b.txt\" R/O OPEN-FILE THROW DUP L $[]SLURP CLOSE-FILE THROW L $[]# 0 L $[]@ TYPE 1 L $[]@ NIP 2 L $[]@ NIP 3 L $[]@ TYPE");
    try expectStack(machine, &.{ 4, 0, 300 });
    try std.testing.expectEqualStrings("onelast", output.written());
    machine.data_depth = 0;
    try machine.interpretLine("S\" b.txt\" L $[]SLURP-FILE L $[]#");
    try expectStack(machine, &.{4});
    try std.testing.expectError(error.Thrown, machine.interpretLine("S\" none.txt\" L $[]SLURP-FILE"));
    try std.testing.expectEqual(forth.errnoIor(2), machine.throw_code);
}

test "heap strings survive a full image restore" {
    var output = Output{};
    const source = try createMachine(&output);
    defer destroyMachine(source);
    try source.interpretLine("VARIABLE S S\" kept\" S $!");
    const image = try std.testing.allocator.alloc(u8, forth.State.imageCapacity());
    defer std.testing.allocator.free(image);
    const length = try source.encodeImage(image);

    const loaded = try createMachine(&output);
    defer destroyMachine(loaded);
    try loaded.restoreImage(image[0..length]);
    try loaded.interpretLine("S $. S\" !\" S $+! S $.");
    try std.testing.expectEqualStrings("keptkept!", output.written());
}
test "locals take values in stack order and can be redefined mid-definition" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine(": T { a b -- c } 10 { c } a b < IF a b + c * ELSE a b - c * THEN ; 1 2 T 2 1 T");
    try machine.interpretLine(": E { a b c } c b a ; 10 20 30 E : L 3 0 DO I { k } k k * LOOP ; L");
    try expectStack(machine, &.{ 30, 10, 30, 20, 10, 0, 1, 4 });
}

test "TO changes value-flavoured locals and | starts locals at zero" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine(": C { n -- } BEGIN n n 1- TO n n 0= UNTIL ; 3 C : U { a | b c -- } b c a TO b b 2 * TO c b c ; 21 U");
    try expectStack(machine, &.{ 3, 2, 1, 0, 0, 21, 42 });
}

test "typed locals hold cells, doubles, floats, characters, and execution tokens" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine(": AREA { F: r -- F: a } r r F* ; 3E AREA : ADD { D: n -- D: r } n 1000. D+ ; 5000. ADD");
    try machine.interpretLine(": UP { C: ch } ch 32 - ; 'a' 256 + UP : RUN { XT: x } x ; : PASS { W: xt } xt EXECUTE ; 1 2 ' + RUN 3 4 ' * PASS");
    try expectFloatStack(machine, &.{9});
    try expectStack(machine, &.{ 6000, 0, 'A', 3, 12 });
}

test "variable-flavoured locals push addresses into the locals frame" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine(": SW { W^ a W^ b } a @ 2 * b @ 2 * a ! b ! a @ b @ ; 3 7 SW : FS { F^ a F^ b } a F@ b F@ a F! b F! a F@ b F@ ; 1.5E 2.5E FS");
    try machine.interpretLine(": CH { C^ p } p 1 TYPE ; 72 CH 73 CH : G 0 { W^ s } S\" Hi\" s $! S\" !\" s $+! s $. ; G");
    try expectStack(machine, &.{ 14, 6 });
    try expectFloatStack(machine, &.{ 2.5, 1.5 });
    try std.testing.expectEqualStrings("HIHi!", output.written());
}

test "LOCALS| binds the first name to the top of the stack and {: :} is accepted" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine(": M LOCALS| n2 n1 | n1 n2 > IF n1 ELSE n2 THEN ; 3 9 M 9 3 M : S {: a b -- d :} a b - ; 10 3 S");
    try expectStack(machine, &.{ 9, 9, 7 });
}

test "each recursive call gets its own locals frame and frames are released" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    const top = machine.locals_top;

    try machine.interpretLine(": FIB { n -- r } n 2 < IF n ELSE n 1- RECURSE n 2 - RECURSE + THEN ; 20 FIB : R { a b } a >R b 2 * R> + ; 1 2 R");
    try expectStack(machine, &.{ 6765, 5 });
    try std.testing.expectEqual(top, machine.locals_top);
    machine.data_depth = 0;
    try std.testing.expectError(error.StackUnderflow, machine.interpretLine("FIB"));
    machine.report(error.StackUnderflow);
    try std.testing.expectEqual(top, machine.locals_top);
}

test "local names are scoped to their definition and rejected outside one" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine(": DUP2 { DUP } DUP DUP ; 4 DUP2 : AFTER 5 DUP ; AFTER");
    try expectStack(machine, &.{ 4, 4, 5, 5 });
    try std.testing.expectError(error.CompileOnly, machine.interpretLine("1 { X }"));
    machine.report(error.CompileOnly);
    try std.testing.expectError(error.InvalidDefinition, machine.interpretLine(": BAD { F: } ;"));
    machine.report(error.InvalidDefinition);
    try std.testing.expectError(error.InvalidDefinition, machine.interpretLine(": BAD2 { W^ v } 1 TO v ;"));
    machine.report(error.InvalidDefinition);
}

test "locals survive a full image restore" {
    var output = Output{};
    const source = try createMachine(&output);
    defer destroyMachine(source);
    try source.interpretLine(": SUB { a b } a b - ; :NONAME { F: x } x x F* ; CONSTANT SQ");
    const image = try std.testing.allocator.alloc(u8, forth.State.imageCapacity());
    defer std.testing.allocator.free(image);
    const length = try source.encodeImage(image);

    const target = try createMachine(&output);
    defer destroyMachine(target);
    try target.interpretLine(": EARLIER 1 ;");
    const loaded = try createMachine(&output);
    defer destroyMachine(loaded);
    try loaded.restoreImage(image[0..length]);
    try target.appendImage(loaded);
    try target.interpretLine("10 3 SUB");
    try expectStack(target, &.{7});
}
test "tabs separate tokens like spaces" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine(": T\t{ a b -- c }\n\t10 { c }\ta b + c * ;\t1\t2 T");
    try machine.interpretLine("S\"\tx\" TYPE\t.\"\ty\"\tCHAR\tz EMIT");
    try expectStack(machine, &.{30});
    try std.testing.expectEqualStrings("xyz", output.written());
}
test ":NONAME failures restore code, data, stack, and STATE" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    const words = machine.word_count;
    const code = machine.code_count;
    const data = machine.data_here;

    try std.testing.expectError(error.UnknownWord, machine.interpretLine(":NONAME [ 16 ALLOT ] 1 MISSING"));
    machine.report(error.UnknownWord);
    try std.testing.expectEqual(words, machine.word_count);
    try std.testing.expectEqual(code, machine.code_count);
    try std.testing.expectEqual(data, machine.data_here);
    try expectStack(machine, &.{});
    try machine.interpretLine("STATE @ :NONAME 5 ; EXECUTE");
    try expectStack(machine, &.{ 0, 5 });

    // A full data stack fails before the definition starts.
    machine.data_depth = machine.data_stack.len;
    const words_before_overflow = machine.word_count;
    try std.testing.expectError(error.StackOverflow, machine.interpretLine(":NONAME 1 ;"));
    try std.testing.expect(!machine.defining);
    try std.testing.expectEqual(words_before_overflow, machine.word_count);
    machine.report(error.StackOverflow);
}

test ":NONAME rolls back when the code area fills at ; and fails cleanly on a full dictionary" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    const words = machine.word_count;
    const code = machine.code_count;
    try std.testing.expectError(error.CodeFull, interpretLiteralDefinition(machine, ":NONAME", 8192 - @as(usize, code)));
    machine.report(error.CodeFull);
    try std.testing.expectEqual(words, machine.word_count);
    try std.testing.expectEqual(code, machine.code_count);
    try expectStack(machine, &.{});
    try machine.interpretLine("STATE @ :NONAME 5 ; EXECUTE");
    try expectStack(machine, &.{ 0, 5 });

    machine.data_depth = 0;
    var definition: [32]u8 = undefined;
    while (machine.word_count < 1024) {
        try machine.interpretLine(try std.fmt.bufPrint(&definition, ": W{d} 1 ;", .{machine.word_count}));
    }
    try std.testing.expectError(error.DictionaryFull, machine.interpretLine(":NONAME 1 ;"));
    try std.testing.expect(!machine.defining);
    machine.report(error.DictionaryFull);
    try expectStack(machine, &.{});
    try machine.interpretLine("W1023 STATE @");
    try expectStack(machine, &.{ 1, 0 });
}
test "CATCH returns 0 or the THROW code and restores the stack depths like gforth" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine(": T 1 2 3 5 THROW ; 9 ' T CATCH");
    try expectStack(machine, &.{ 9, 5 });
    machine.data_depth = 0;
    try machine.interpretLine(": U DROP DROP DROP DROP ; 1 2 ' U CATCH");
    try expectStack(machine, &.{ 1, 2, -4 });
    machine.data_depth = 0;
    try machine.interpretLine("1 2 ' + CATCH : V 1 0 / ; ' V CATCH ' ABORT CATCH S\" NOSUCHWORD\" ' EVALUATE CATCH NIP NIP");
    try expectStack(machine, &.{ 3, 0, -10, -1, -13 });
    machine.data_depth = 0;
    try machine.interpretLine("1E 2E : X FDROP FDROP 3 THROW ; ' X CATCH : W 1 >R 2 >R 7 THROW ; ' W CATCH : L 10 0 DO I 5 = IF 8 THROW THEN LOOP ; ' L CATCH");
    try expectStack(machine, &.{ 3, 7, 8 });
    try expectFloatStack(machine, &.{ 1, 2 });
    try std.testing.expectEqual(@as(usize, 0), machine.return_depth);
    try std.testing.expectEqual(@as(usize, 0), machine.loop_depth);
    try std.testing.expectEqualStrings("", output.written());
}

test "CATCH works with file iors, nested catches, locals, and $TMP" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    const locals_top = machine.locals_top;

    try machine.interpretLine(": OPEN S\" none.txt\" R/O OPEN-FILE THROW ; ' OPEN CATCH");
    try machine.interpretLine(": INNER 4 THROW ; : OUTER ['] INNER CATCH 10 + THROW ; ' OUTER CATCH");
    try machine.interpretLine(": LOC 5 { a } a 9 THROW ; ' LOC CATCH : NOISY .\" hidden\" 6 THROW ; : CAP ['] NOISY $TMP ; ' CAP CATCH");
    try expectStack(machine, &.{ forth.errnoIor(2), 14, 9, 6 });
    try std.testing.expectEqual(locals_top, machine.locals_top);
    try machine.interpretLine(".\" shown\"");
    try std.testing.expectEqualStrings("shown", output.written());
}

test "a THROWn interpreter code is reported like the original error" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    const lines = [_][]const u8{ ": V 1 0 / ; ' V CATCH THROW", "-1 ' THROW CATCH THROW", "-13 THROW", "S\" MISSING\" ' EVALUATE CATCH THROW" };
    const errors = [_]anyerror{ error.DivisionByZero, error.Aborted, error.Thrown, error.Thrown };
    for (lines, errors) |line, expected| {
        try std.testing.expectError(expected, machine.interpretLine(line));
        machine.report(expected);
    }
    try std.testing.expectEqualStrings("DIVISION BY ZERO !\nUNDEFINED WORD !\nUNDEFINED WORD !\n", output.written());
}

test "CATCH abandons a definition started by the caught word" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    const words = machine.word_count;
    const code = machine.code_count;

    try machine.interpretLine("S\" : HALF 1 MISSING\" ' EVALUATE CATCH NIP NIP STATE @");
    try expectStack(machine, &.{ -13, 0 });
    try std.testing.expectEqual(words, machine.word_count);
    try std.testing.expectEqual(code, machine.code_count);
    try std.testing.expect(!machine.defining);
    try machine.interpretLine(": AFTER 3 ; AFTER");
    try expectStack(machine, &.{ -13, 0, 3 });
}
test "a token consumes one following separator, so PARSE keeps further spaces" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine(": P [CHAR] | PARSE TYPE .\" |\" ; P  x y| : Q [CHAR] ) PARSE TYPE ; Q in parens) .\" after\"");
    try machine.interpretLine("S\"  two\" TYPE .\" |\" .\"glued text\" .\" |\" ");
    try std.testing.expectEqualStrings(" x y|in parensafter two|glued text|", output.written());
}

test "WORD returns a counted string and FIND reports immediacy" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine(": NEXT-NAME BL WORD COUNT ; NEXT-NAME    spaced NEXT-NAME");
    try std.testing.expectEqual(@as(usize, 4), machine.data_depth);
    try std.testing.expectEqual(@as(forth.Cell, 6), machine.data_stack[1]);
    try std.testing.expectEqual(@as(forth.Cell, 0), machine.data_stack[3]);
    machine.data_depth = 0;
    try machine.interpretLine(": LOOKUP BL WORD FIND NIP ; LOOKUP DUP LOOKUP IF LOOKUP NOSUCH : SHOW BL WORD FIND IF EXECUTE ELSE COUNT TYPE THEN ; 7 SHOW . SHOW MISSING");
    try expectStack(machine, &.{ -1, 1, 0 });
    try std.testing.expectEqualStrings("7 MISSING", output.written());
}

test "FIND-NAME NAME>INT and NAME>STRING follow the book's Level 10 example" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("S\" DUP\" FIND-NAME DUP 0<> SWAP NAME>INT ' DUP = S\" dup\" FIND-NAME NAME>STRING TYPE S\" NOSUCH\" FIND-NAME");
    try expectStack(machine, &.{ -1, -1, 0 });
    try std.testing.expectEqualStrings("DUP", output.written());
    try std.testing.expectError(error.InvalidExecutionToken, machine.interpretLine("0 NAME>INT"));
    machine.report(error.InvalidExecutionToken);
    try std.testing.expectError(error.InvalidExecutionToken, machine.interpretLine("100000 NAME>STRING"));
}

test "SEE shows definitions with their control structures" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine(": SQUARE ( n -- n^2 ) DUP * ; SEE SQUARE SEE IF 42 CONSTANT C SEE C");
    try machine.interpretLine(": T DUP 0< IF NEGATE ELSE 1+ THEN 3 0 DO I LOOP BEGIN DUP WHILE 1- REPEAT BEGIN 1+ DUP 5 > UNTIL BEGIN AGAIN ; SEE T");
    try machine.interpretLine(": M CREATE , DOES> @ ; 5 M FIVE SEE FIVE : S S\" hi\" TYPE .\" x\" ['] DUP DROP ; IMMEDIATE SEE S");
    try std.testing.expectEqualStrings(
        ": SQUARE\n  DUP *\n;\nBUILT-IN IF IMMEDIATE\n42 CONSTANT C\n" ++
            ": T\n  DUP 0< IF NEGATE ELSE 1+ THEN 3 0 DO I LOOP BEGIN DUP WHILE 1- REPEAT\n  BEGIN 1+ DUP 5 > UNTIL BEGIN AGAIN\n;\n" ++
            "CREATE FIVE\nDOES>\n  @\n;\n: S\n  S\" hi\" TYPE .\" x\" ['] DUP DROP\n; IMMEDIATE\n",
        output.written(),
    );
}

test "EVALUATE does not read further terminal lines and input lines are limited to the TIB" {
    var output = Output{};
    output.input_lines[0] = "NAME";
    output.input_count = 1;
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try std.testing.expectError(error.InvalidDefinition, machine.interpretLine("S\" CREATE\" EVALUATE"));
    machine.report(error.InvalidDefinition);
    try std.testing.expectEqual(@as(usize, 0), output.input_index);
    try machine.interpretLine("CREATE");
    try std.testing.expectEqual(@as(usize, 1), output.input_index);
    const long = [_]u8{' '} ** (forth.tib_size + 1);
    try std.testing.expectError(error.StringTooLong, machine.interpretLine(&long));
}
test "INCLUDE interprets a file across lines and reports its name and line" {
    var output = Output{};
    setFakeFile(&output, 0, ": SQUARE ( n -- n^2 )\n\tDUP * ;\nSOURCEFILENAME TYPE SPACE SOURCELINE# .\nCREATE\n  TABLE 7 ,\n");
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("INCLUDE a.txt 3 SQUARE TABLE @ S\" a.txt\" INCLUDED? S\" b.txt\" INCLUDED? SOURCELINE#");
    try expectStack(machine, &.{ 9, 7, -1, 0, 0 });
    try machine.interpretLine("SPACE SOURCEFILENAME TYPE SPACE S\" SOURCEFILENAME TYPE\" EVALUATE");
    try std.testing.expectEqualStrings("a.txt 3  *the terminal* *evaluated string*", output.written());
    try std.testing.expect(!output.files[0].open);
}

test "REQUIRE loads a file once, even when it requires itself" {
    var output = Output{};
    setFakeFile(&output, 0, "REQUIRE a.txt\n.\" once\"\n");
    setFakeFile(&output, 1, "DUP CONSTANT SIZE\n");
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("REQUIRE a.txt NEEDS a.txt S\" a.txt\" REQUIRED 1024 REQUIRE b.txt DROP 2048 REQUIRE b.txt DROP SIZE");
    try expectStack(machine, &.{1024});
    try std.testing.expectEqualStrings("once", output.written());
}

test "errors in included files name the innermost file and line and close every file" {
    var output = Output{};
    setFakeFile(&output, 0, "1\nINCLUDE b.txt\n2\n");
    setFakeFile(&output, 1, "3\n: BAD MISSING ;\n");
    setFakeFile(&output, 2, ": HALF 1\n");
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    const words = machine.word_count;

    try std.testing.expectError(error.UnknownWord, machine.interpretLine("INCLUDE a.txt"));
    machine.report(error.UnknownWord);
    try std.testing.expectError(error.InvalidDefinition, machine.interpretLine("INCLUDE c.txt"));
    machine.report(error.InvalidDefinition);
    try std.testing.expectError(error.Thrown, machine.interpretLine("INCLUDE none.txt"));
    machine.report(error.Thrown);
    try std.testing.expectEqualStrings("b.txt:2: MISSING ?\nc.txt:1: DEFINITION ERROR !\nNO SUCH FILE OR DIRECTORY !\n", output.written());
    try std.testing.expectEqual(words, machine.word_count);
    for (output.files) |file| try std.testing.expect(!file.open);
    try machine.interpretLine("STATE @");
    try expectStack(machine, &.{0});
}

test "CATCH around INCLUDED lets the rest of the line run" {
    var output = Output{};
    setFakeFile(&output, 0, "1 2\nMISSING\n");
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("S\" a.txt\" ' INCLUDED CATCH NIP NIP 42");
    try expectStack(machine, &.{ -13, 42 });
    machine.report(error.Aborted);
    try std.testing.expectEqualStrings("", output.written());
    try std.testing.expect(!output.files[0].open);
}

test "INCLUDE nesting is limited" {
    var output = Output{};
    setFakeFile(&output, 0, "INCLUDE a.txt\n");
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try std.testing.expectError(error.IncludeNesting, machine.interpretLine("INCLUDE a.txt"));
    machine.report(error.IncludeNesting);
    try std.testing.expectEqualStrings("a.txt:1: INCLUDE NESTING ERROR !\n", output.written());
}

test "MARKER forgets later words and the files required after it" {
    var output = Output{};
    setFakeFile(&output, 0, "DUP CONSTANT SIZE\n");
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    const words = machine.word_count;

    try machine.interpretLine("MARKER SAFE : TEMP 1 ; 5 REQUIRE a.txt DROP SIZE SAFE 7 REQUIRE a.txt DROP SIZE S\" TEMP\" FIND-NAME");
    try expectStack(machine, &.{ 5, 7, 0 });
    try std.testing.expectEqual(words + 1, machine.word_count);
    try machine.interpretLine("MARKER M SEE M");
    try std.testing.expectEqualStrings("MARKER M\n", output.written());
}

test "LOCATE prints the file, line, and the lines of the definition" {
    var output = Output{};
    setFakeFile(&output, 0, "\\ library\n: SUM\n  BEGIN DEPTH 1 > WHILE + REPEAT ;\n: OTHER ;\n");
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("INCLUDE a.txt : HERE-ONLY ; LOCATE SUM LOCATE HERE-ONLY");
    try std.testing.expectEqualStrings("a.txt:2\n: SUM\n  BEGIN DEPTH 1 > WHILE + REPEAT ;\nHERE-ONLY: NO FILE INFORMATION\n", output.written());
}

test "source locations and the REQUIRE history survive image restore and LOAD" {
    var output = Output{};
    setFakeFile(&output, 0, ": FROM-A 1 ;\n");
    setFakeFile(&output, 1, ": FROM-B\n  2 ;\n");
    const source = try createMachine(&output);
    defer destroyMachine(source);
    try source.interpretLine("INCLUDE b.txt");
    const image = try std.testing.allocator.alloc(u8, forth.State.imageCapacity());
    defer std.testing.allocator.free(image);
    const length = try source.encodeImage(image);

    const loaded = try createMachine(&output);
    defer destroyMachine(loaded);
    try loaded.restoreImage(image[0..length]);
    try loaded.interpretLine("S\" b.txt\" INCLUDED? LOCATE FROM-B");

    const target = try createMachine(&output);
    defer destroyMachine(target);
    try target.interpretLine("INCLUDE a.txt");
    try target.appendImage(loaded);
    try target.interpretLine("S\" b.txt\" INCLUDED? LOCATE FROM-B LOCATE FROM-A");
    try expectStack(loaded, &.{-1});
    try expectStack(target, &.{-1});
    try std.testing.expectEqualStrings("b.txt:1\n: FROM-B\n  2 ;\nb.txt:1\n: FROM-B\n  2 ;\na.txt:1\n: FROM-A 1 ;\n", output.written());
}
test "a parsing word left waiting at the end of an EVALUATE string is an error" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    const words = machine.word_count;

    try std.testing.expectError(error.InvalidDefinition, machine.interpretLine("S\" VARIABLE\" EVALUATE LEAK"));
    machine.report(error.InvalidDefinition);
    try std.testing.expectError(error.InvalidDefinition, machine.interpretLine("S\" :\" EVALUATE NAME"));
    machine.report(error.InvalidDefinition);
    try std.testing.expectEqual(words, machine.word_count);
    try machine.interpretLine("S\" 5 CONSTANT\" ' EVALUATE CATCH NIP NIP S\" LEAK\" FIND-NAME");
    try expectStack(machine, &.{ -259, 0 });
}

test "INCLUDE between CREATE and DOES> keeps the word being created" {
    var output = Output{};
    setFakeFile(&output, 0, "\\ only a comment\n");
    setFakeFile(&output, 1, "MISSING\n");
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine(": M1 CREATE , S\" a.txt\" INCLUDED DOES> @ ; 5 M1 FIVE FIVE");
    try machine.interpretLine(": M2 CREATE , S\" b.txt\" ['] INCLUDED CATCH NIP NIP DROP DOES> @ ; 6 M2 SIX SIX");
    try machine.interpretLine(": M3 CREATE , S\" 1 DROP\" EVALUATE DOES> @ ; 7 M3 SEVEN SEVEN");
    try expectStack(machine, &.{ 5, 6, 7 });
}

test "MARKER inside an included file keeps the names that frames and words refer to" {
    var output = Output{};
    setFakeFile(&output, 0, ": FROM-A ;\nM\nINCLUDE c.txt\nSOURCEFILENAME TYPE\n");
    setFakeFile(&output, 2, ": FROM-C ;\n");
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("MARKER M INCLUDE a.txt S\" a.txt\" INCLUDED? S\" c.txt\" INCLUDED? LOCATE FROM-C");
    try expectStack(machine, &.{ 0, -1 });
    try std.testing.expectEqualStrings("a.txtc.txt:1\n: FROM-C ;\n", output.written());
    machine.data_depth = 0;
    try machine.interpretLine("MARKER M2 REQUIRE c.txt M2 S\" c.txt\" INCLUDED?");
    try expectStack(machine, &.{-1});
}

test "a MARKER loaded with LOAD restores the history it was made with" {
    var output = Output{};
    setFakeFile(&output, 0, ": FROM-A 1 ;\n");
    setFakeFile(&output, 1, ": FROM-B 2 ;\n");
    setFakeFile(&output, 2, ": FROM-C 3 ;\n");
    const source = try createMachine(&output);
    defer destroyMachine(source);
    try source.interpretLine("INCLUDE a.txt MARKER M");
    const image = try std.testing.allocator.alloc(u8, forth.State.imageCapacity());
    defer std.testing.allocator.free(image);
    const length = try source.encodeImage(image);
    const loaded = try createMachine(&output);
    defer destroyMachine(loaded);
    try loaded.restoreImage(image[0..length]);

    const target = try createMachine(&output);
    defer destroyMachine(target);
    try target.interpretLine("INCLUDE b.txt");
    try target.appendImage(loaded);
    try target.interpretLine("REQUIRE c.txt M S\" a.txt\" INCLUDED? S\" b.txt\" INCLUDED? S\" c.txt\" INCLUDED? INCLUDE c.txt LOCATE FROM-A");
    try expectStack(target, &.{ -1, -1, 0 });
    try std.testing.expectEqualStrings("a.txt:1\n: FROM-A 1 ;\n", output.written());
}

test "a file that ends the caller's definition and starts another is an error" {
    var output = Output{};
    setFakeFile(&output, 3, "] ; : HALF 1\n");
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try std.testing.expectError(error.InvalidDefinition, machine.interpretLine(": OUTER 1 [ S\" d.txt\" INCLUDED"));
    machine.report(error.InvalidDefinition);
    try std.testing.expectEqualStrings("d.txt:1: DEFINITION ERROR !\n", output.written());
    try machine.interpretLine("S\" HALF\" FIND-NAME");
    try expectStack(machine, &.{0});
}

test "a failing close is reported at the file that failed" {
    var output = Output{};
    output.close_fails = true;
    setFakeFile(&output, 0, "1\n");
    setFakeFile(&output, 1, "INCLUDE a.txt\n2\n");
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try std.testing.expectError(error.Thrown, machine.interpretLine("INCLUDE a.txt"));
    machine.report(error.Thrown);
    try std.testing.expectError(error.Thrown, machine.interpretLine("INCLUDE b.txt"));
    machine.report(error.Thrown);
    try machine.interpretLine("S\" a.txt\" ' INCLUDED CATCH NIP NIP");
    try expectStack(machine, &.{forth.errnoIor(5)});
    try std.testing.expectEqualStrings("a.txt:1: INPUT/OUTPUT ERROR !\na.txt:1: INPUT/OUTPUT ERROR !\n", output.written());
    for (output.files) |file| try std.testing.expect(!file.open);
}

test "WORD and NAME>STRING buffers have the documented limits" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    var line: [300]u8 = undefined;
    @memcpy(line[0..16], ": W BL WORD ; W ");
    @memset(line[16 .. 16 + 255], 'x');

    try machine.interpretLine(line[0 .. 16 + 255]);
    try std.testing.expectEqual(@as(u8, 255), machine.memory[@intCast(machine.data_stack[0])]);
    line[16 + 255] = 'x';
    try std.testing.expectError(error.StringTooLong, machine.interpretLine(line[0 .. 16 + 256]));
    machine.report(error.StringTooLong);
    try machine.interpretLine(": NS 9 0 DO S\" DUP\" FIND-NAME NAME>STRING DROP LOOP ; NS");
    try std.testing.expectEqual(@as(usize, 9), machine.data_depth);
    try std.testing.expectEqual(machine.data_stack[0], machine.data_stack[8]);
    for (1..8) |index| try std.testing.expect(machine.data_stack[index] != machine.data_stack[0]);
}

test "SEE handles nested and empty branches and CASE" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine(": N IF IF 1 THEN ELSE THEN ; SEE N : E IF THEN BEGIN UNTIL ; SEE E : C CASE 1 OF 10 ENDOF 20 SWAP ENDCASE ; SEE C");
    try std.testing.expectEqualStrings(
        ": N\n  IF IF 1 THEN ELSE THEN\n;\n: E\n  IF THEN BEGIN UNTIL\n;\n: C\n  1 OVER = IF DROP 10 ELSE 20 SWAP DROP THEN\n;\n",
        output.written(),
    );
}
test "VOCABULARY ONLY ALSO DEFINITIONS and ORDER follow the book's Level 16 example" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("ORDER CR VOCABULARY MY-WORDS ONLY FORTH ALSO MY-WORDS DEFINITIONS : HELLO .\" Hello\" ; ORDER CR");
    try std.testing.expectError(error.UnknownWord, machine.interpretLine("ONLY FORTH HELLO"));
    machine.report(error.UnknownWord);
    try machine.interpretLine("ORDER CR DEFINITIONS ORDER CR ONLY FORTH ALSO MY-WORDS HELLO CR ONLY ORDER FORTH CR SEE MY-WORDS");
    try std.testing.expectEqualStrings(
        "Forth Forth Root     Forth \nMY-WORDS Forth Root     MY-WORDS \nHELLO ?\n" ++
            "Forth Root     MY-WORDS \nForth Root     Forth \nHello\nRoot Root     Forth \nVOCABULARY MY-WORDS\n",
        output.written(),
    );
}

test "WORDLIST SET-CURRENT and >ORDER build modules and shadow words by order" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("WORDLIST CONSTANT MATH MATH SET-CURRENT : ADD2 2 + ; : SQUARE DUP * ; DEFINITIONS");
    try machine.interpretLine("WORDLIST CONSTANT IO IO SET-CURRENT : SHOW .\" Result: \" . ; DEFINITIONS MATH >ORDER IO >ORDER");
    try machine.interpretLine(": MAIN { x -- } x ADD2 SQUARE SHOW ; 3 MAIN ORDER ONLY FORTH");
    try machine.interpretLine("WORDLIST CONSTANT W1 WORDLIST CONSTANT W2 W1 SET-CURRENT : PRINT .\" W1\" ; W2 SET-CURRENT : PRINT .\" W2\" ;");
    try machine.interpretLine("W1 >ORDER W2 >ORDER PRINT ONLY FORTH W2 >ORDER W1 >ORDER PRINT ONLY FORTH DEFINITIONS");
    try std.testing.expectEqualStrings("Result: 25 IO MATH Forth Forth Root     Forth W2W1", output.written());
    try std.testing.expectError(error.UnknownWord, machine.interpretLine("3 ADD2"));
}

test "GET-ORDER SET-ORDER PREVIOUS and the search order limits" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("GET-ORDER WORDLIST SWAP 1+ SET-ORDER GET-ORDER NIP NIP NIP NIP PREVIOUS GET-ORDER");
    try expectStack(machine, &.{ 4, 2, 1, 1, 3 });
    machine.data_depth = 0;
    try machine.interpretLine("GET-CURRENT -1 SET-ORDER GET-ORDER FORTH-WORDLIST");
    try expectStack(machine, &.{ 1, 2, 2, 2, 1 });
    machine.data_depth = 0;
    try std.testing.expectError(error.SearchOrderOverflow, machine.interpretLine("ONLY FORTH : FILL-ORDER 15 0 DO FORTH-WORDLIST >ORDER LOOP ; FILL-ORDER"));
    machine.report(error.SearchOrderOverflow);
    try machine.interpretLine(": EP 0 SET-ORDER ['] PREVIOUS CATCH -1 SET-ORDER FORTH ; EP");
    try expectStack(machine, &.{-50});
    machine.data_depth = 0;
    try std.testing.expectError(error.InvalidWordlist, machine.interpretLine("99 SET-CURRENT"));
    machine.report(error.InvalidWordlist);
    try std.testing.expectError(error.InvalidWordlist, machine.interpretLine("0 >ORDER"));
}

test "WORDS lists the first word list and SEARCH-WORDLIST searches one list" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("VOCABULARY V V DEFINITIONS : ONE 1 ; : TWO 2 ; IMMEDIATE WORDS");
    try std.testing.expectEqualStrings("ONE TWO \n", output.written());
    try machine.interpretLine("S\" TWO\" GET-CURRENT SEARCH-WORDLIST NIP S\" TWO\" FORTH-WORDLIST SEARCH-WORDLIST S\" DUP\" FORTH-WORDLIST SEARCH-WORDLIST NIP");
    try expectStack(machine, &.{ 1, 0, -1 });
}

test "[IF] [ELSE] [THEN] select input, nest, span lines, and work while compiling" {
    var output = Output{};
    output.input_lines[0] = "  skipped words";
    output.input_lines[1] = "[ELSE] 7 [THEN] 8";
    output.input_count = 2;
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("1 [IF] 1 [ELSE] 2 [THEN] 0 [IF] 3 [IF] 4 [THEN] [ELSE] 5 [THEN] : T [ 0 ] [IF] 10 [ELSE] 20 [THEN] ; T");
    try machine.interpretLine("[DEFINED] DUP [UNDEFINED] DUP [DEFINED] NOSUCH 0 [IF]");
    try expectStack(machine, &.{ 1, 5, 20, -1, 0, 0, 7, 8 });
    try std.testing.expectError(error.ControlMismatch, machine.interpretLine("S\" 0 [IF] 1\" EVALUATE"));
}

test "MARKER restores the search order and the current word list" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("MARKER M VOCABULARY V ALSO V DEFINITIONS : X ; M ORDER");
    try std.testing.expectEqualStrings("Forth Forth Root     Forth ", output.written());
    try machine.interpretLine("S\" X\" FIND-NAME S\" V\" FIND-NAME");
    try expectStack(machine, &.{ 0, 0 });
}

test "word lists and the search order survive image restore and LOAD renumbers them" {
    var output = Output{};
    const source = try createMachine(&output);
    defer destroyMachine(source);
    try source.interpretLine("VOCABULARY TOOLS ALSO TOOLS DEFINITIONS : TOOL 7 ; MARKER M ONLY FORTH DEFINITIONS");
    const image = try std.testing.allocator.alloc(u8, forth.State.imageCapacity());
    defer std.testing.allocator.free(image);
    const length = try source.encodeImage(image);

    const loaded = try createMachine(&output);
    defer destroyMachine(loaded);
    try loaded.restoreImage(image[0..length]);
    try loaded.interpretLine("ALSO TOOLS TOOL ORDER");

    const target = try createMachine(&output);
    defer destroyMachine(target);
    try target.interpretLine("VOCABULARY MINE ALSO MINE DEFINITIONS : OWN 1 ; ONLY FORTH DEFINITIONS");
    const restored = try createMachine(&output);
    defer destroyMachine(restored);
    try restored.restoreImage(image[0..length]);
    try target.appendImage(restored);
    try target.interpretLine("ALSO TOOLS TOOL ALSO MINE OWN M ORDER");
    try expectStack(loaded, &.{7});
    try expectStack(target, &.{ 7, 1 });
    try std.testing.expectEqualStrings("TOOLS Forth Root     Forth TOOLS Forth Forth Root     TOOLS ", output.written());
}
test "a MARKER made in reclaimed data space survives LOAD with old values in its unused slots" {
    var output = Output{};
    const source = try createMachine(&output);
    defer destroyMachine(source);
    try source.interpretLine("VOCABULARY TOOLS HERE CONSTANT A CREATE OLD 152 ALLOT 9223372036854775807 A 144 + ! FORGET OLD MARKER M A 144 + @");
    try expectStack(source, &.{0});
    source.data_depth = 0;
    const image = try std.testing.allocator.alloc(u8, forth.State.imageCapacity());
    defer std.testing.allocator.free(image);
    const length = try source.encodeImage(image);
    const loaded = try createMachine(&output);
    defer destroyMachine(loaded);
    try loaded.restoreImage(image[0..length]);

    const target = try createMachine(&output);
    defer destroyMachine(target);
    try target.interpretLine("VOCABULARY MINE");
    try target.appendImage(loaded);
    try target.interpretLine("ALSO TOOLS M ORDER");
    try std.testing.expectEqualStrings("Forth Forth Root     Forth ", output.written());
}

test "[DEFINED] and [UNDEFINED] see local variables while compiling" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine(": T { x -- } [DEFINED] x [IF] x [ELSE] 99 [THEN] ; 7 T");
    try machine.interpretLine(": U { x -- } [UNDEFINED] x [IF] 99 [ELSE] x 1+ [THEN] ; 7 U");
    try machine.interpretLine(": DUP2 { DUP } [DEFINED] DUP [IF] DUP [THEN] ; 5 DUP2");
    try machine.interpretLine(": MK CREATE { y } DOES> DROP [DEFINED] y [IF] 1 [ELSE] 2 [THEN] ; 3 MK THING THING");
    try expectStack(machine, &.{ 7, 8, 5, 2 });
}

test "[IF] skipping inside an included file reads further lines and fails at its end" {
    var output = Output{};
    setFakeFile(&output, 0, "0 [IF]\n  skipped\n  lines\n[ELSE] 1\n[THEN] 2\n");
    setFakeFile(&output, 1, "0 [IF]\nnever closed\n");
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("INCLUDE a.txt");
    try expectStack(machine, &.{ 1, 2 });
    try std.testing.expectError(error.ControlMismatch, machine.interpretLine("INCLUDE b.txt"));
    machine.report(error.ControlMismatch);
    try std.testing.expectEqualStrings("b.txt:2: CONTROL STRUCTURE ERROR !\n", output.written());
    try machine.interpretLine("S\" b.txt\" ' INCLUDED CATCH NIP NIP 3");
    try expectStack(machine, &.{ -22, 3 });
    for (output.files) |file| try std.testing.expect(!file.open);
}

test "FIND and LOCATE pick the word from the first list in the search order" {
    var output = Output{};
    setFakeFile(&output, 0, "VOCABULARY V1 VOCABULARY V2\nALSO V1 DEFINITIONS : SAME 1 ;\nV2 DEFINITIONS : SAME 2 ;\n");
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("INCLUDE a.txt FORTH DEFINITIONS ALSO V1 SAME : W BL WORD FIND DROP EXECUTE ; W SAME LOCATE SAME");
    try machine.interpretLine("PREVIOUS ALSO V2 SAME W SAME LOCATE SAME");
    try expectStack(machine, &.{ 1, 1, 2, 2 });
    try std.testing.expectEqualStrings("a.txt:2\nALSO V1 DEFINITIONS : SAME 1 ;\na.txt:3\nV2 DEFINITIONS : SAME 2 ;\n", output.written());
}

test "image restore keeps words of a vocabulary made with :NONAME and DOES>" {
    var output = Output{};
    const source = try createMachine(&output);
    defer destroyMachine(source);
    try source.interpretLine("VOCABULARY TOOLS ALSO TOOLS DEFINITIONS :NONAME 40 + ; CONSTANT ADDER : HOLDER CREATE , DOES> @ ; 2 HOLDER TWO");
    try source.interpretLine("FORTH DEFINITIONS PREVIOUS");
    const image = try std.testing.allocator.alloc(u8, forth.State.imageCapacity());
    defer std.testing.allocator.free(image);
    const length = try source.encodeImage(image);
    const loaded = try createMachine(&output);
    defer destroyMachine(loaded);
    try loaded.restoreImage(image[0..length]);

    try std.testing.expectError(error.UnknownWord, loaded.interpretLine("TWO"));
    loaded.report(error.UnknownWord);
    try loaded.interpretLine("ALSO TOOLS TWO ADDER EXECUTE S\" TWO\" FIND-NAME 0<> ORDER");
    try expectStack(loaded, &.{ 42, -1 });
    try std.testing.expectEqualStrings("TWO ?\nTOOLS Forth Forth Root     Forth ", output.written());
}
test "locals are visible only where every path passes their declaration, as in gforth" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    const visible = [_][]const u8{
        ": T1 1 IF 5 { x } x THEN ; T1",
        ": T4 BEGIN 5 { x } x 1 UNTIL ; T4",
        ": T5 BEGIN 5 { x } 1 UNTIL x ; T5",
        ": T7 3 0 DO I { x } LOOP x ; T7",
        ": T8 5 { x } 1 IF x THEN x ; T8",
        ": T11 1 IF 5 { dup } THEN 3 dup ; T11",
        ": T13 10 0 DO I { x } x 5 = IF LEAVE THEN LOOP x ; T13",
        ": T14 1 BEGIN 7 { y } DUP WHILE 1- REPEAT DROP y ; T14",
    };
    for (visible) |line| try machine.interpretLine(line);
    try expectStack(machine, &.{ 5, 5, 5, 2, 5, 5, 3, 3, 5, 7 });

    const hidden = [_][]const u8{
        ": T2 0 IF 5 { x } ELSE x THEN ;",
        ": T3 1 IF 5 { x } THEN x ;",
        ": T9 3 0 ?DO I { x } LOOP x ;",
        ": T10 1 BEGIN DUP WHILE 5 { x } 1- REPEAT DROP x ;",
        ": T12 10 0 DO I 5 = IF LEAVE THEN I { x } LOOP x ;",
        ": T15 2 CASE 1 OF 5 { z } ENDOF z ENDCASE ;",
    };
    for (hidden) |line| {
        try std.testing.expectError(error.UnknownWord, machine.interpretLine(line));
        machine.report(error.UnknownWord);
    }
    try std.testing.expectEqualStrings("x ?\nx ?\nx ?\nx ?\nx ?\nz ?\n", output.written());
}
test "F>STR-RDP matches gforth's output for fixed, exponential, and overflowing fields" {
    const cases = [_]struct { []const u8, []const u8 }{
        .{ "12.3456789E 7 3 1", " 12.346" },       .{ "12.3456789E 7 4 1", "12.3457" },  .{ "-12.3456789E 7 4 1", "-1.23E1" },
        .{ "0.0996E 7 3 1", "  0.100" },           .{ "0.0996E 7 3 3", "9.96E-2" },      .{ "999.9994E 7 3 1", "999.999" },
        .{ "999.9996E 7 3 1", "1.000E3" },         .{ "-1E-20 5 2 1", "*****" },         .{ "12345.6789E 10 2 7", "  12345.68" },
        .{ "12345.6789E 10 2 8", "1.234568E4" },   .{ "0E 7 3 1", "  0.000" },           .{ "-0E 7 3 1", " -0.000" },
        .{ "1E 0E F/ 7 3 1", "infinit" },          .{ "-1E 0E F/ 7 3 1", "-infini" },    .{ "0E 0E F/ 7 3 1", "NaN    " },
        .{ "1E-20 5 2 1", "1E-20" },               .{ "1E-5 7 3 1", "1.00E-5" },         .{ "1E-5 7 3 0", "  0.000" },
        .{ "1.5E300 7 2 1", "1.5E300" },           .{ "123456E 6 0 0", "1.23E5" },       .{ "2.5E 5 0 1", "   2." },
        .{ "3.5E 5 0 1", "   4." },                .{ "3.14159E 4 3 1", "3.E0" },        .{ "0.5E 4 3 1", ".500" },
        .{ "-0.5E 5 3 1", "-.500" },               .{ "3.14159E 10 2 11", "3.141590E0" }, .{ "2.675E 6 2 1", "  2.67" },
        .{ "0.95E 5 1 0", "  0.9" },               .{ "1E 1 0 0", "*" },                 .{ "9.99E 3 1 1", "1E1" },
        .{ "1E-100 7 0 1", "1.E-100" },            .{ "0.0005E 7 3 0", "  0.000" },      .{ "0.0006E 7 3 0", "  0.001" },
        .{ "0.05E 5 1 0", "  0.0" },               .{ "0.000123E 10 6 2", "  0.000123" }, .{ "-100E 3 0 1", "***" },
        // Rounding that shortens the exponent, adds a digit, or makes np reachable.
        .{ "9.999E-10 4 2 1", "1E-9" },            .{ "-0.9999E 4 2 1", "-1E0" },     .{ "0.09999E 4 2 2", "0.10" },
        .{ "9.999E-100 5 2 1", "1E-99" },          .{ "9.999E-100 6 2 1", "1.E-99" }, .{ "99.996E 5 2 1", "1.0E2" },
        .{ "99.996E 6 2 1", "100.00" },            .{ "-99.996E 6 2 1", "-1.0E2" },   .{ "0.96E 2 1 0", "**" },
        // Zero has one integer digit; a tiny value rounded up loses a unit that does not fit.
        .{ "0E 4 3 1", "0.E0" },                   .{ "-0E 5 3 1", "-0.E0" },         .{ "0E 3 3 1", "0E0" },
        .{ "-0E 6 3 1", "-0.000" },                .{ "0.7E 1 0 0", "." },            .{ "-0.7E 2 0 0", "-." },
        .{ "0.7E 2 0 0", "1." },                   .{ "0.0007E 4 3 0", ".001" },
        // log10 overestimates the exponent of these; rounding there would lose a digit.
        .{ "9.999999999999998E34 20 0 0", "9.999999999999998E34" }, .{ "9.999999999999998E-10 21 0 1", "9.999999999999999E-10" },
    };
    for (cases) |case| {
        var output = Output{};
        const machine = try createMachine(&output);
        defer destroyMachine(machine);
        var line: [80]u8 = undefined;
        try machine.interpretLine(try std.fmt.bufPrint(&line, "{s} F>STR-RDP TYPE", .{case[0]}));
        std.testing.expectEqualStrings(case[1], output.written()) catch |err| {
            std.debug.print("case: {s}\n", .{case[0]});
            return err;
        };
    }
}

test "F.RDP prints, F>BUF-RDP fills a buffer, and the book's Level 20 examples hold" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("12345.6789E 10 2 7 F.RDP 12345.6789E 10 2 8 F.RDP PI 10 2 0 F.RDP");
    try machine.interpretLine("CREATE BUF 50 ALLOT BUF 50 ERASE PI BUF 10 4 0 F>BUF-RDP BUF 10 TYPE PI 0 2 0 F>STR-RDP NIP PI 0 0 0 F.RDP");
    try std.testing.expectEqualStrings("  12345.681.234568E4      3.14    3.1416", output.written());
    try expectStack(machine, &.{0});
    try std.testing.expectError(error.StringTooLong, machine.interpretLine("1E 5000 2 0 F.RDP"));
    machine.report(error.StringTooLong);
    try std.testing.expectError(error.PicturedNumericOverflow, machine.interpretLine("123. <# #S 1E 4096 2 0 F>STR-RDP"));
}

test "F.RDP and F>BUF-RDP show a value whose exponent shortens when rounded" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("CREATE BUF 8 ALLOT BUF 8 88 FILL 9.999E-10 BUF 1+ 4 2 1 F>BUF-RDP BUF 8 TYPE 9.999E-10 4 2 1 F.RDP");
    try std.testing.expectEqualStrings("X1E-9XXX1E-9", output.written());
    try expectStack(machine, &.{});
}

test "defining words compiled into a definition read their name when it runs" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine(": V VARIABLE ; V AA 5 AA ! AA @ . : C CONSTANT ; 7 C BB BB . : FV FVARIABLE ; FV CC 2E CC F! CC F@ F.");
    try machine.interpretLine(": FC FCONSTANT ; 3E FC DD DD F. : VL VALUE ; 9 VL GG GG . 4 TO GG GG . : D2 2CONSTANT ; 1. D2 HH HH D.");
    try machine.interpretLine(": V2 2VARIABLE ; V2 II 3. II 2! II 2@ D. : AR ARRAY ; 3 AR JJ 8 1 JJ A! 1 JJ A@ .");
    // Level 31 of the book: a word that starts a definition and one that ends it.
    try machine.interpretLine(": DEFINE-FUNCTION : ; : END-FUNCTION POSTPONE ; ; IMMEDIATE");
    try machine.interpretLine("DEFINE-FUNCTION SQUARE FDUP F* END-FUNCTION 3E SQUARE F.");
    try std.testing.expectEqualStrings("5 7 2. 3. 9 4 1 3 8 9. ", output.written());
    try expectStack(machine, &.{});
    try std.testing.expectError(error.InvalidDefinition, machine.interpretLine("V"));
    try std.testing.expectError(error.InvalidDefinition, machine.interpretLine(": START : ; IMMEDIATE : OUTER START INNER ;"));
}

test "[ while interpreting, PI, and F. rounded from the exact binary value" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("[ 1 . : X [ 2 . ] 3 ; X .");
    try machine.interpretLine("PI F. PI 10 4 0 F.RDP");
    // The shortest forms end in 5 (1.414213562373095, 0.5463024898437905); the exact values round down.
    try machine.interpretLine("1.4142135623730949E F. 0.5E FTAN F. 1E 3E F/ F.S");
    try std.testing.expectEqualStrings("1 2 3 3.14159265358979     3.14161.41421356237309 0.54630248984379 <1> 3.333333333E-1 ", output.written());
}

test "defining words follow the search order, a variable takes DOES>, and F. keeps every digit" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine(": PROBE ONLY S\" VARIABLE AA\" EVALUATE ; ' PROBE CATCH FORTH . [DEFINED] AA .");
    try machine.interpretLine(": V VARIABLE DOES> @ ; V BB BB . : USEIT BB ; USEIT . : FV FVARIABLE DOES> F@ ; FV FF FF F.");
    try machine.interpretLine(": V2 2VARIABLE DOES> 2@ ; V2 DD DD D. 9.99999999999995E34 F.");
    try std.testing.expectEqualStrings("-13 0 0 0 0. 0 99999999999999500000000000000000000. ", output.written());
    try expectStack(machine, &.{});
}

test ".S and F.S show the top nine items, and F.S shows zero, infinity, and NaN as gforth does" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("1E 2E 0E -0E 1E 0E F/ 0E 0E F/ 5E-324 -1.7976931348623157E308 1E-300 2E F.S");
    try machine.interpretLine("1 2 3 4 5 6 7 8 9 10 11 12 .S");
    try std.testing.expectEqualStrings("<10> 2.0000000000E0 0.0000000000E0 -0.000000000E0 infinity       NaN            4.9406565E-324 -1.7976931E308 1.0000000E-300 2.0000000000E0 <12> 4 5 6 7 8 9 10 11 12 ", output.written());
}

test "FSIN FCOS FTAN FEXP FLN are correctly rounded, as the original gforth in Linux gets them from glibc" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    // Values where the Windows gforth (UCRT) and Zig's builtins are one bit off.
    try machine.interpretLine("8.455291201133988E FSIN 4.097339611316615E FCOS -3.790540510731324E FTAN 7.5804220383449845E 10E F/ FEXP");
    try machine.interpretLine("0.7853981634E FSIN 2E FLN 1E 0E F/ FSIN");
    const expected = [_]forth.Float{ 0x1.a63160a19e355p-1, -0x1.276c6481934a7p-1, -0x1.846014ab289adp-1, 0x1.1129fe0eea6f9p+1, 0x1.6a09e667f7b49p-1, 0x1.62e42fefa39efp-1 };
    try std.testing.expectEqual(@as(usize, expected.len + 1), machine.float_depth);
    for (expected, machine.float_stack[0..expected.len]) |want, got| {
        try std.testing.expectEqual(@as(u64, @bitCast(want)), @as(u64, @bitCast(got)));
    }
    try std.testing.expect(std.math.isNan(machine.float_stack[expected.len]));
}

test "math functions match the original gforth at large arguments, range limits, subnormals, and non-finite values" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    // Expected bits are the original gforth's (glibc) and CORE-MATH's, which agree here.
    try machine.interpretLine("1E300 FSIN 1E300 FCOS 1E300 FTAN -1E300 FSIN 1E22 FSIN 1E22 FCOS");
    try machine.interpretLine("709.782712893384E FEXP 709.7827128933841E FEXP -745E FEXP -746E FEXP -708.4E FEXP");
    try machine.interpretLine("5E-324 FLN 5E-324 FSIN 5E-324 FTAN 1.0000000000000002E FLN 0.9999999999999999E FLN");
    try machine.interpretLine("2.2250738585072014E-308 FLN 1.7976931348623157E308 FLN");
    const expected = [_]u64{
        0xBFEA2C16B010E385, 0xBFE2699022ADC4C1, 0x3FF6BE411F37AC77, 0x3FEA2C16B010E385, 0xBFEB453AB76BF397, 0x3FE0BE2CEF01C8F4,
        0x7FEFFFFFFFFFFF2A, 0x7FF0000000000000, 0x0000000000000001, 0x0000000000000000, 0x000FF15B469EDF89,
        0xC0874385446D71C3, 0x0000000000000001, 0x0000000000000001, 0x3CAFFFFFFFFFFFFF, 0xBCA0000000000000,
        0xC086232BDD7ABCD2, 0x40862E42FEFA39EF,
    };
    try std.testing.expectEqual(expected.len, machine.float_depth);
    for (expected, machine.float_stack[0..expected.len]) |want, got| try std.testing.expectEqual(want, @as(u64, @bitCast(got)));

    // A NaN argument comes back unchanged (quiet); infinity gives the CPU's default NaN,
    // not CORE-MATH's all-ones NaN.
    try machine.interpretLine(": FCLEAR FDEPTH 0 ?DO FDROP LOOP ; FCLEAR CREATE BB 8 ALLOT");
    try machine.interpretLine("HEX 7FF8000000001234 BB ! BB F@ FSIN FFF8000000005678 BB ! BB F@ FTAN DECIMAL");
    // The default NaN comes from the CPU at run time, as the interpreter computes it.
    try machine.interpretLine("1E 0E F/ FSIN 1E 0E F/ FCOS -1E 0E F/ FTAN 1E 0E F/ FDUP F-");
    const default_nan: u64 = @bitCast(machine.float_stack[5]);
    machine.float_depth -= 1;
    const nans = [_]u64{ 0x7FF8000000001234, 0xFFF8000000005678, default_nan, default_nan, default_nan };
    try std.testing.expectEqual(nans.len, machine.float_depth);
    for (nans, machine.float_stack[0..nans.len]) |want, got| try std.testing.expectEqual(want, @as(u64, @bitCast(got)));
    try std.testing.expect(default_nan != 0xFFFFFFFFFFFFFFFF);
}

test ".S and F.S at depth zero, at exactly nine items, and in hexadecimal" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine(".S F.S 1 2 3 4 5 6 7 8 9 .S 10 HEX .S DECIMAL");
    try machine.interpretLine("1E 2E 3E 4E 5E 6E 7E 8E 9E F.S 10E HEX F.S DECIMAL");
    try std.testing.expectEqualStrings("<0> <0> <9> 1 2 3 4 5 6 7 8 9 <A> 2 3 4 5 6 7 8 9 A " ++
        "<9> 1.0000000000E0 2.0000000000E0 3.0000000000E0 4.0000000000E0 5.0000000000E0 6.0000000000E0 7.0000000000E0 8.0000000000E0 9.0000000000E0 " ++
        "<A> 2.0000000000E0 3.0000000000E0 4.0000000000E0 5.0000000000E0 6.0000000000E0 7.0000000000E0 8.0000000000E0 9.0000000000E0 1.0000000000E1 ", output.written());
}

test ">BODY gives the data area, and ' in a definition reads its name when the definition runs" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("VARIABLE V 11 V ! ' V >BODY @ . 2VARIABLE D 1. D 2! ' D >BODY 2@ D. FVARIABLE F 2E F F! ' F >BODY F@ F.");
    try machine.interpretLine("7 VALUE W ' W >BODY @ . 3. 2CONSTANT DC ' DC >BODY 2@ D. : MK CREATE , DOES> @ ; 9 MK M ' M >BODY @ .");
    // Level 31 of the book: a word that reads a variable's name when it runs.
    try machine.interpretLine(": RT ' >BODY @ ; RT V . : READ-NEXT ' ; READ-NEXT DUP ' DUP = . : TK ['] DUP ; TK ' DUP = .");
    try machine.interpretLine("' V EXECUTE ' V >BODY = . '");
    try machine.interpretLine("V ' V = .");
    try std.testing.expectEqualStrings("11 1 2. 7 3 9 11 -1 -1 -1 -1 ", output.written());
    try expectStack(machine, &.{});
    try std.testing.expectError(error.InvalidExecutionToken, machine.interpretLine("5 CONSTANT K ' K >BODY"));
    try std.testing.expectError(error.InvalidExecutionToken, machine.interpretLine(": SQ DUP * ; ' SQ >BODY"));
    try std.testing.expectError(error.InvalidExecutionToken, machine.interpretLine("' DUP >BODY"));
    try std.testing.expectError(error.InvalidDefinition, machine.interpretLine("RT"));
}
