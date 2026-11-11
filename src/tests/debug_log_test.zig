//! Tests of the log of --debug-log: the errors, the trace, and the profile as lines of
//! JSON.

const std = @import("std");
const forth = @import("../forth.zig");
const support = @import("support.zig");
const Output = support.Output;
const createMachine = support.createMachine;
const destroyMachine = support.destroyMachine;
const setFakeFile = support.setFakeFile;

var log_text: [8192]u8 = undefined;
var log_len: usize = 0;

fn logWrite(_: ?*anyopaque, bytes: []const u8) void {
    const count = @min(bytes.len, log_text.len - log_len);
    @memcpy(log_text[log_len..][0..count], bytes[0..count]);
    log_len += count;
}

/// What was written to the log since the last call.
fn logged() []const u8 {
    const text = log_text[0..log_len];
    log_len = 0;
    return text;
}

/// A machine that writes its log to `log_text`.
fn createLogged(output: *Output) !*forth.State {
    const machine = try createMachine(output);
    machine.writer.log_fn = logWrite;
    log_len = 0;
    return machine;
}

test "an error is logged with its message, code, backtrace, and stacks" {
    try support.skipWithout(&.{.debug});
    var output = Output{};
    const machine = try createLogged(&output);
    defer destroyMachine(machine);

    forth.logStart(machine, "1.2.3");
    try std.testing.expectEqualStrings("{\"event\":\"start\",\"version\":\"1.2.3\"}\n", logged());

    try machine.interpretLine(": AVG / ; : REP 10 20 2SWAP AVG ;");
    try std.testing.expectError(error.DivisionByZero, machine.interpretLine("7 30 0 REP"));
    machine.report(error.DivisionByZero);
    const float_part = if (@import("build_options").float) ",\"float_stack_depth\":0,\"float_stack\":[]" else "";
    try std.testing.expectEqualStrings("{\"event\":\"error\",\"message\":\"DIVISION BY ZERO !\",\"code\":-10," ++
        "\"backtrace\":[{\"word\":\"AVG\"},{\"word\":\"REP\"}],\"more\":0," ++
        "\"stack_depth\":3,\"stack\":[7,10,20]" ++ float_part ++ "}\n", logged());
    // The error is shown as without a log.
    try std.testing.expectEqualStrings("DIVISION BY ZERO !\nBACKTRACE:\n  AVG\n  REP\nSTACK: <3> 7 10 20 \n", output.written());

    // An error outside compiled code has an empty backtrace; ABORT is not logged.
    try std.testing.expectError(error.UnknownWord, machine.interpretLine("MISSING"));
    machine.report(error.UnknownWord);
    try std.testing.expectEqualStrings("{\"event\":\"error\",\"message\":\"MISSING ?\",\"code\":-13,\"backtrace\":[],\"more\":0," ++
        "\"stack_depth\":0,\"stack\":[]" ++ float_part ++ "}\n", logged());
    try std.testing.expectError(error.Aborted, machine.interpretLine("ABORT"));
    machine.report(error.Aborted);
    try std.testing.expectEqualStrings("", logged());
}

test "the log gives files, lines, copied words, recursions, and names as JSON strings" {
    try support.skipWithout(&.{ .debug, .files });
    var output = Output{};
    setFakeFile(&output, 0, ": SQUARE DUP * ;\n: TWICE\n  SQUARE SQUARE ;\n: A\"B\\ 1 0 / ;\n: DEEP DEEP ;\nTWICE\n");
    const machine = try createLogged(&output);
    defer destroyMachine(machine);

    try std.testing.expectError(error.StackUnderflow, machine.interpretLine("INCLUDE a.txt"));
    machine.report(error.StackUnderflow);
    const text = logged();
    try std.testing.expect(std.mem.startsWith(u8, text, "{\"event\":\"error\",\"message\":\"a.txt:6: STACK UNDER FLOW !\",\"code\":-4,\"file\":\"a.txt\",\"line\":6," ++
        "\"backtrace\":[{\"word\":\"SQUARE\",\"file\":\"a.txt\",\"line\":3,\"inline\":true},{\"word\":\"TWICE\",\"file\":\"a.txt\",\"line\":3}],\"more\":0,"));

    // A quote and a backslash in a name are escaped.
    try std.testing.expectError(error.DivisionByZero, machine.interpretLine("A\"B\\"));
    machine.report(error.DivisionByZero);
    try std.testing.expect(std.mem.indexOf(u8, logged(), "\"backtrace\":[{\"word\":\"A\\\"B\\\\\",\"file\":\"a.txt\",\"line\":4}]") != null);

    try std.testing.expectError(error.ReturnStackOverflow, machine.interpretLine("DEEP"));
    machine.report(error.ReturnStackOverflow);
    const deep = logged();
    try std.testing.expect(std.mem.indexOf(u8, deep, "\"backtrace\":[{\"word\":\"DEEP\",\"file\":\"a.txt\",\"line\":5,\"times\":32}],\"more\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, deep, "\"more\":0,") == null);
}

test "with a log, the trace and the profile go to it instead of standard error" {
    try support.skipWithout(&.{.debug});
    var output = Output{};
    const machine = try createLogged(&output);
    defer destroyMachine(machine);
    const profile = try std.testing.allocator.create(forth.Profile);
    defer std.testing.allocator.destroy(profile);
    profile.reset();
    machine.profile = profile;
    machine.plain_calls = true;
    machine.tracing = true;
    machine.trace_limit = 3;

    try machine.interpretLine(": SQUARE DUP * ; : SUMSQ SQUARE SWAP SQUARE + ; 3 4 SUMSQ DROP");
    try std.testing.expectEqualStrings(
        \\{"event":"enter","word":"SUMSQ","depth":0,"stack_depth":2,"stack":[3,4]}
        \\{"event":"enter","word":"SQUARE","depth":1,"stack_depth":2,"stack":[3,4]}
        \\{"event":"exit","word":"SQUARE","depth":1,"stack_depth":2,"stack":[3,16]}
        \\{"event":"trace_limit","lines":3}
        \\
    , logged());

    profile.show(machine);
    try std.testing.expectEqualStrings(
        \\{"event":"profile","operations":11}
        \\{"event":"profile_word","word":"SQUARE","calls":2,"self":6,"total":6}
        \\{"event":"profile_word","word":"SUMSQ","calls":1,"self":5,"total":11}
        \\
    , logged());
    try std.testing.expectEqual(@as(usize, 0), output.stderr_len);
    try std.testing.expectEqualStrings("", output.written());
}

test "the log is UTF-8 also when a message is cut or a name is not" {
    try support.skipWithout(&.{.debug});
    var output = Output{};
    const machine = try createLogged(&output);
    defer destroyMachine(machine);

    // 240 bytes of the message are kept: "a", 79 characters of 3 bytes, and 2 bytes of
    // the next, which are left out.
    const long = "a" ++ support.repeat("\xe6\x97\xa5", 81);
    try std.testing.expectError(error.UnknownWord, machine.interpretLine(long));
    machine.report(error.UnknownWord);
    const text = logged();
    try std.testing.expect(std.unicode.utf8ValidateSlice(text));
    try std.testing.expect(std.mem.startsWith(u8, text, "{\"event\":\"error\",\"message\":\"a" ++ support.repeat("\xe6\x97\xa5", 79) ++ "\",\"code\":-13,"));

    // A name with bytes that are not UTF-8.
    try std.testing.expectError(error.DivisionByZero, machine.interpretLine(": X\xff\xc3Y 1 0 / ; X\xff\xc3Y"));
    machine.report(error.DivisionByZero);
    const named = logged();
    try std.testing.expect(std.unicode.utf8ValidateSlice(named));
    try std.testing.expect(std.mem.indexOf(u8, named, "{\"word\":\"X\xef\xbf\xbd\xef\xbf\xbdY\"}") != null);
}

test "a change of a watched cell is logged" {
    try support.skipWithout(&.{.debug});
    var output = Output{};
    const machine = try createLogged(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("VARIABLE SCORE : BUMP 1 SCORE +! ; SCORE DUP WATCH");
    const score = try machine.pop();
    try machine.interpretLine("BUMP 4 SCORE !");
    var expected: [256]u8 = undefined;
    try std.testing.expectEqualStrings(try std.fmt.bufPrint(&expected, "{{\"event\":\"watch\",\"address\":{d},\"old\":0,\"new\":1,\"in\":\"BUMP\"}}\n" ++
        "{{\"event\":\"watch\",\"address\":{d},\"old\":1,\"new\":4}}\n", .{ score, score }), logged());
}
