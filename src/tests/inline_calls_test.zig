const std = @import("std");
const forth = @import("../forth.zig");
const inline_calls = @import("../core/inline_calls.zig");
const support = @import("support.zig");

fn first(machine: *forth.State, name: []const u8) @import("../core/defs.zig").Op {
    return machine.code[machine.words[machine.lookup(name).?].code_start];
}

// Independent control execution uses ordinary calls and jumps over the expansion.
fn ordinaryCalls(machine: *forth.State) void {
    var pc: usize = 0;
    while (pc < machine.code_count) : (pc += 1) {
        const op = machine.code[pc];
        if (!inline_calls.isInline(op)) continue;
        const end = pc + inline_calls.span(op.value);
        machine.code[pc] = .{ .kind = .call_colon, .value = inline_calls.wordId(op.value) };
        for (pc + 1..end) |at| machine.code[at] = .{ .kind = .branch, .value = @intCast(end) };
        pc = end - 1;
    }
}

test "short calls inline with nested depth guards and retain original word identity" {
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try machine.interpretLine(": A 1+ ; : B A A ; : C B B ;");
    try std.testing.expect(inline_calls.isInline(first(machine, "B")));
    try std.testing.expect(inline_calls.isInline(first(machine, "C")));
    const c = machine.words[machine.lookup("C").?];
    try std.testing.expectEqual(@as(u16, 2), inline_calls.depth(machine.code[c.code_start + 1].value));
    try machine.interpretLine("0 C : A 100 + ; 0 C 0 A");
    try support.expectStack(machine, &.{ 4, 4, 100 });
    try std.testing.expectEqualStrings("WARNING: SAME NAME WORD EXISTS\n", output.written());
    output.len = 0;
    try machine.interpretLine(support.see("SEE B SEE C"));
    try std.testing.expectEqualStrings(support.see(": B\n  A A\n;\n: C\n  B B\n;\n"), output.written());
}

test "inlined calls reject words removed during execution by FORGET or MARKER" {
    for ([_][]const u8{
        ": A 1+ ; : P S\" FORGET A\" EVALUATE 10 A . ;",
        "MARKER M : A 1+ ; : P M 10 A . ;",
        ": A 1+ ; : B A A ; : P S\" FORGET A\" EVALUATE 10 B . ;",
        "MARKER M : A 1+ ; : B A A ; : P M 10 B . ;",
    }) |source| {
        for ([_]bool{ false, true }) |ordinary| {
            var output = support.Output{};
            const machine = try support.createMachine(&output);
            defer support.destroyMachine(machine);
            try machine.interpretLine(source);
            const caller = machine.lookup("P").?;
            const word = machine.words[caller];
            const has_inline = for (machine.code[word.code_start..word.code_end]) |op| {
                if (inline_calls.isInline(op)) break true;
            } else false;
            try std.testing.expect(has_inline);
            if (ordinary) ordinaryCalls(machine);
            try std.testing.expectError(error.InvalidExecutionToken, machine.executeWord(caller));
            try support.expectStack(machine, &.{10});
            try std.testing.expectEqualStrings("", output.written());
            try std.testing.expect(machine.lookup("A") == null);
            try std.testing.expect(machine.lookup("P") == null);
            try std.testing.expectEqual(@as(usize, 0), machine.call_depth);
            try std.testing.expectEqual(@as(usize, 0), machine.frame_depth);
        }
    }
}

test "inlined calls preserve call-limit and stack-error ordering" {
    var output = support.Output{};
    const optimized = try support.createMachine(&output);
    defer support.destroyMachine(optimized);
    const control = try support.createMachine(&output);
    defer support.destroyMachine(control);
    const source = ": A 1+ ; : B A A ; : C B B ; : Q DROP A ; : R Q ;";
    try optimized.interpretLine(source);
    try control.interpretLine(source);
    ordinaryCalls(control);
    for ([_][]const u8{ "C", "R" }) |name| {
        for ([_]usize{ 0, 1021, 1022, 1023, 1024 }) |call_depth| {
            for ([_]usize{ 0, 1, 2, 1024 }) |data_depth| {
                for ([_]*forth.State{ optimized, control }) |machine| {
                    machine.call_depth = call_depth;
                    machine.data_depth = data_depth;
                    @memset(&machine.data_stack, std.math.maxInt(forth.Cell));
                }
                const actual = optimized.executeWord(optimized.lookup(name).?);
                const expected = control.executeWord(control.lookup(name).?);
                try std.testing.expectEqual(expected, actual);
                try std.testing.expectEqual(control.data_depth, optimized.data_depth);
                try std.testing.expectEqualSlices(forth.Cell, &control.data_stack, &optimized.data_stack);
                try std.testing.expectEqual(control.call_depth, optimized.call_depth);
                try std.testing.expectEqual(control.frame_depth, optimized.frame_depth);
                try std.testing.expectEqual(control.locals_top, optimized.locals_top);
            }
        }
    }
}

test "recursive branching local dynamic and large definitions stay as calls" {
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try machine.interpretLine(": REC RECURSE ; : BR IF 1 THEN ; : LOCAL { x } x ; : DYN EXECUTE ; : LONG 1+ 1+ 1+ 1+ 1+ ; : EARLY EXIT ;");
    try machine.interpretLine(": R REC ; : B BR ; : L LOCAL ; : D DYN ; : G LONG ; : E EARLY ;");
    for ([_][]const u8{ "REC", "R", "B", "L", "D", "G", "E" }) |name| {
        try std.testing.expect(!inline_calls.isInline(first(machine, name)));
    }
    try machine.interpretLine(": A 1+ ;");
    const saved_count = machine.code_count;
    machine.code_count = @intCast(machine.code.len - 1);
    try machine.compileCall(machine.lookup("A").?);
    try std.testing.expectEqual(machine.code.len, machine.code_count);
    try std.testing.expect(!inline_calls.isInline(machine.code[machine.code_count - 1]));
    machine.code_count = saved_count;
}

test "inlining survives image normalization restoration and repeated relocation" {
    var output = support.Output{};
    const source = try support.createMachine(&output);
    defer support.destroyMachine(source);
    try source.interpretLine(": A 1+ ; : B A A ; : C B B ;");
    const buffer = try std.testing.allocator.alloc(u8, forth.State.imageCapacity());
    defer std.testing.allocator.free(buffer);
    const length = try source.encodeImage(buffer);
    try std.testing.expectEqualStrings("SIGIMG33", buffer[0..8]);
    try std.testing.expect(inline_calls.isInline(first(source, "B")));
    const restored = try support.createMachine(&output);
    defer support.destroyMachine(restored);
    try restored.restoreImage(buffer[0..length]);
    try std.testing.expect(inline_calls.isInline(first(restored, "B")));
    try std.testing.expect(inline_calls.isInline(first(restored, "C")));
    try restored.interpretLine("0 C");
    try support.expectStack(restored, &.{4});
    const target = try support.createMachine(&output);
    defer support.destroyMachine(target);
    try target.interpretLine(": PREFIX 99 ;");
    for (0..2) |_| {
        try target.appendImage(restored);
        try std.testing.expect(inline_calls.isInline(first(target, "C")));
        try target.interpretLine("0 C PREFIX");
    }
    try support.expectStack(target, &.{ 4, 99, 4, 99 });
    try target.interpretLine(support.see("SEE C"));
    try std.testing.expectEqualStrings(support.see(": C\n  B B\n;\n"), output.written());
}

test "image inlining does not hide a branch into reserved padding" {
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try machine.interpretLine(": A 1+ ; : B A A ; : C B B ;");
    ordinaryCalls(machine);
    const b = machine.words[machine.lookup("B").?];
    _ = try machine.emit(.{ .kind = .branch, .value = b.code_start + 1 });
    inline_calls.restore(machine);
    try std.testing.expect(!inline_calls.isInline(first(machine, "B")));
    try std.testing.expect(!inline_calls.isInline(first(machine, "C")));
    try machine.interpretLine("0 C");
    try support.expectStack(machine, &.{4});
}
