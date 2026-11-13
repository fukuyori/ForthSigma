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

fn expectInlineToken(machine: *forth.State, caller: u16, guards: []const u16, token: u16) !void {
    const word = machine.words[caller];
    try std.testing.expect(inline_calls.isInline(machine.code[word.code_start]));
    var guard_count: usize = 0;
    var token_count: usize = 0;
    for (machine.code[word.code_start..word.code_end]) |op| {
        if (inline_calls.isInline(op)) {
            try std.testing.expect(guard_count < guards.len);
            try std.testing.expectEqual(guards[guard_count], inline_calls.wordId(op.value));
            guard_count += 1;
        } else if (op.kind == .execution_token) {
            token_count += 1;
            try std.testing.expectEqual(@as(forth.Cell, token), op.value);
        }
    }
    try std.testing.expectEqual(guards.len, guard_count);
    try std.testing.expectEqual(@as(usize, 1), token_count);
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
                    @memset(machine.data_stack, std.math.maxInt(forth.Cell));
                }
                const actual = optimized.executeWord(optimized.lookup(name).?);
                const expected = control.executeWord(control.lookup(name).?);
                try std.testing.expectEqual(expected, actual);
                try std.testing.expectEqual(control.data_depth, optimized.data_depth);
                try std.testing.expectEqualSlices(forth.Cell, control.data_stack, optimized.data_stack);
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

test "inline capacity fallback reserves one slot but not the rest of a definition" {
    for ([_]usize{ 7, 6, 5, 3, 2 }) |remaining| {
        for ([_]bool{ false, true }) |ordinary| {
            var output = support.Output{};
            const machine = try support.createMachine(&output);
            defer support.destroyMachine(machine);
            try machine.interpretLine(": A 1+ 1+ 1+ 1+ ;");
            const start: u16 = @intCast(machine.code.len - remaining);
            @memset(machine.code[machine.code_count..start], .{ .kind = .exit });
            machine.code_count = start;
            const word_count = machine.word_count;
            const names_used = machine.names_used;
            try machine.interpretLine(": T");
            if (ordinary) {
                _ = try machine.emit(.{ .kind = .call_colon, .value = machine.lookup("A").? });
            } else {
                try machine.interpretLine("A");
            }
            try std.testing.expectEqual(!ordinary and remaining >= 6, inline_calls.isInline(machine.code[start]));
            try machine.interpretLine("1");
            if (remaining == 2 or (!ordinary and remaining == 6)) {
                try std.testing.expectError(error.CodeFull, machine.interpretLine(";"));
                machine.report(error.CodeFull);
                try std.testing.expectEqual(start, machine.code_count);
                try std.testing.expectEqual(word_count, machine.word_count);
                try std.testing.expectEqual(names_used, machine.names_used);
                try std.testing.expect(machine.lookup("T") == null);
                try std.testing.expectEqualStrings("OUT OF CODE SPACE !\n", output.written());
                // A smaller definition still compiles and executes after recovery.
                try machine.interpretLine(": OK 9 ; OK");
                try support.expectStack(machine, &.{9});
            } else {
                try machine.interpretLine("; 10 T");
                try support.expectStack(machine, &.{ 14, 1 });
                const used: u16 = if (!ordinary and remaining >= 6) 7 else 3;
                try std.testing.expectEqual(start + used, machine.code_count);
            }
        }
    }
}

test "saved inline padding consumes LOAD capacity and rejection leaves the target unchanged" {
    for ([_]bool{ false, true }) |ordinary| {
        var output = support.Output{};
        const source = try support.createMachine(&output);
        defer support.destroyMachine(source);
        try source.interpretLine(": A 1+ 1+ 1+ 1+ ; : B");
        if (ordinary) {
            _ = try source.emit(.{ .kind = .call_colon, .value = source.lookup("A").? });
        } else {
            try source.interpretLine("A");
        }
        try source.interpretLine(";");
        const buffer = try std.testing.allocator.alloc(u8, forth.State.imageCapacity(.small));
        defer std.testing.allocator.free(buffer);
        const length = try source.encodeImage(buffer);
        const restored = try support.createMachine(&output);
        defer support.destroyMachine(restored);
        try restored.restoreImage(buffer[0..length]);
        try std.testing.expectEqual(@as(u16, if (ordinary) 7 else 11), restored.code_count);
        try std.testing.expectEqual(!ordinary, inline_calls.isInline(first(restored, "B")));
        const target = try support.createMachine(&output);
        defer support.destroyMachine(target);
        try target.interpretLine(": PREFIX 99 ;");
        @memset(target.code[target.code_count .. target.code.len - 7], .{ .kind = .exit });
        target.code_count = @intCast(target.code.len - 7);
        const word_count = target.word_count;
        const names_used = target.names_used;
        const data_here = target.data_here;
        if (ordinary) {
            try target.appendImage(restored);
            try std.testing.expectEqual(target.code.len, target.code_count);
            try target.interpretLine("10 B PREFIX");
            try support.expectStack(target, &.{ 14, 99 });
        } else {
            try std.testing.expectError(error.CodeFull, target.appendImage(restored));
            try std.testing.expectEqual(target.code.len - 7, target.code_count);
            try std.testing.expectEqual(word_count, target.word_count);
            try std.testing.expectEqual(names_used, target.names_used);
            try std.testing.expectEqual(data_here, target.data_here);
            try std.testing.expect(target.lookup("A") == null);
            try std.testing.expect(target.lookup("B") == null);
            try target.interpretLine("PREFIX");
            try support.expectStack(target, &.{99});
        }
    }
}

test "copied execution tokens relocate through repeated LOAD and another image round trip" {
    var output = support.Output{};
    const source = try support.createMachine(&output);
    defer support.destroyMachine(source);
    try source.interpretLine(": T 5 ; : A ['] T ; : U A ; : C U EXECUTE ; : D ['] DUP ; : E D EXECUTE ;");
    const buffer = try std.testing.allocator.alloc(u8, forth.State.imageCapacity(.small));
    defer std.testing.allocator.free(buffer);
    const length = try source.encodeImage(buffer);
    const restored = try support.createMachine(&output);
    defer support.destroyMachine(restored);
    try restored.restoreImage(buffer[0..length]);
    try restored.interpretLine("C 7 E");
    try support.expectStack(restored, &.{ 5, 7, 7 });
    const target = try support.createMachine(&output);
    defer support.destroyMachine(target);
    // Wrongly unrelocated user tokens would resolve to these different words.
    try target.interpretLine(": P1 99 ; : P2 88 ;");
    const LoadedCopy = struct {
        c: u16,
        e: u16,
        t: u16,
        u: u16,
        a: u16,
        d: u16,

        fn check(copy: @This(), machine: *forth.State, dup: u16) !void {
            try expectInlineToken(machine, copy.c, &.{ copy.u, copy.a }, copy.t);
            try expectInlineToken(machine, copy.e, &.{copy.d}, dup);
        }
    };
    const dup = target.lookup("DUP").?;
    var copies: [2]LoadedCopy = undefined;
    for (&copies, 0..) |*copy, index| {
        try target.appendImage(restored);
        copy.* = .{
            .c = target.lookup("C").?,
            .e = target.lookup("E").?,
            .t = target.lookup("T").?,
            .u = target.lookup("U").?,
            .a = target.lookup("A").?,
            .d = target.lookup("D").?,
        };
        // Check earlier copies too: a later LOAD must not retarget their guards or tokens.
        for (copies[0 .. index + 1]) |loaded| try loaded.check(target, dup);
        try target.interpretLine("C 7 E P1 P2");
        try support.expectStack(target, &.{ 5, 7, 7, 99, 88 });
        target.data_depth = 0;
    }
    try std.testing.expect(copies[0].t != copies[1].t);
    // Both the older and newer loaded definitions must retain their own tokens.
    const combined_length = try target.encodeImage(buffer);
    try source.restoreImage(buffer[0..combined_length]);
    for (copies) |copy| {
        try copy.check(source, dup);
        try source.executeWord(copy.c);
    }
    try source.interpretLine("7 E P1 P2");
    try support.expectStack(source, &.{ 5, 5, 7, 7, 99, 88 });
}

test "inlining survives image normalization restoration and repeated relocation" {
    var output = support.Output{};
    const source = try support.createMachine(&output);
    defer support.destroyMachine(source);
    try source.interpretLine(": A 1+ ; : B A A ; : C B B ;");
    const buffer = try std.testing.allocator.alloc(u8, forth.State.imageCapacity(.small));
    defer std.testing.allocator.free(buffer);
    const length = try source.encodeImage(buffer);
    try std.testing.expectEqualStrings("SIGIMG45", buffer[0..8]);
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

test "SEE may omit empty old-image branches reconstructed as inline padding" {
    try support.skipWithout(&.{ .tools, .image });
    var output = support.Output{};
    const original = try support.createMachine(&output);
    defer support.destroyMachine(original);
    // Emit compact ordinary calls as the pre-inlining compiler did, without padding.
    try original.interpretLine(": X 1+ ; : Y IF");
    const x = original.lookup("X").?;
    _ = try original.emit(.{ .kind = .call_colon, .value = x });
    try original.interpretLine("THEN ; : Z IF");
    _ = try original.emit(.{ .kind = .call_colon, .value = x });
    try original.interpretLine("ELSE THEN ; : W");
    _ = try original.emit(.{ .kind = .call_colon, .value = x });
    try original.interpretLine("AHEAD THEN ; SEE Y SEE Z SEE W");
    try std.testing.expectEqualStrings(": Y\n  IF X THEN\n;\n: Z\n  IF X ELSE THEN\n;\n: W\n  X BRANCH 2\n;\n", output.written());
    const execute = "10 0 Y 10 -1 Y 10 0 Z 10 -1 Z 10 W";
    try original.interpretLine(execute);
    try support.expectStack(original, &.{ 10, 11, 10, 11, 11 });
    const buffer = try std.testing.allocator.alloc(u8, forth.State.imageCapacity(.small));
    defer std.testing.allocator.free(buffer);
    var length = try original.encodeImage(buffer);
    const loaded = try support.createMachine(&output);
    defer support.destroyMachine(loaded);
    for (0..2) |_| {
        try loaded.restoreImage(buffer[0..length]);
        output.len = 0;
        try loaded.interpretLine("SEE Y SEE Z SEE W");
        try std.testing.expectEqualStrings(": Y\n  IF X THEN\n;\n: Z\n  IF X THEN\n;\n: W\n  X\n;\n", output.written());
        const y = loaded.words[loaded.lookup("Y").?];
        const z = loaded.words[loaded.lookup("Z").?];
        try std.testing.expect(!inline_calls.isInline(loaded.code[y.code_start + 1]));
        try std.testing.expect(inline_calls.isInline(loaded.code[z.code_start + 1]));
        try std.testing.expect(inline_calls.isInline(first(loaded, "W")));
        try loaded.interpretLine(execute);
        try support.expectStack(loaded, &.{ 10, 11, 10, 11, 11 });
        length = try loaded.encodeImage(buffer);
    }
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
