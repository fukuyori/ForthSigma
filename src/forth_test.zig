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
    command: [64]u8 = undefined,
    command_len: usize = 0,
    files: [2]FakeFile = .{ .{}, .{} },
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
        output.slept = milliseconds;
    }

    fn utime(_: ?*anyopaque) forth.RuntimeError!forth.Double {
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
    const index: usize = if (std.mem.eql(u8, name, "a.txt")) 0 else if (std.mem.eql(u8, name, "b.txt")) 1 else return .{ .ior = forth.errnoIor(2) };
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
    return 0;
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

    try machine.interpretLine(": VALUE 1 ; : VALUE 2 ; VALUE");

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

test "F.S shows the float stack with exponent markers" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("1E 2E 0.5E 1E-7 -3.25E 1E30 F.S");

    try std.testing.expectEqualStrings("<6> 1e 2e .5e 1e-7 -3.25e 1e30 ", output.written());
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
    try machine.interpretLine("3.1415926535E FCONSTANT PI : AREA FDUP F* PI F* ; 5E AREA F.");
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
    try std.testing.expectEqualStrings("HOST FUNCTION UNAVAILABLE !\nHOST FUNCTION UNAVAILABLE !\n", output.written());
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
    for (codes) |line| {
        try std.testing.expectError(error.Thrown, machine.interpretLine(line));
        machine.report(error.Thrown);
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

    try machine.interpretLine("16 ALLOCATE THROW 32 ALLOCATE THROW 64 ALLOCATE THROW ROT DUP >R FREE THROW FREE THROW FREE THROW 980000 ALLOCATE THROW R> =");
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