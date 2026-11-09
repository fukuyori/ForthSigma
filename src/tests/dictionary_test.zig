//! Tests of the dictionary's name area and of the size and contents of images.

const std = @import("std");
const forth = @import("../forth.zig");
const defs = @import("../core/defs.zig");
const inline_calls = @import("../core/inline_calls.zig");
const Builtin = defs.Builtin;
const support = @import("support.zig");
const Output = support.Output;
const repeat = support.repeat;
const createMachine = support.createMachine;
const destroyMachine = support.destroyMachine;
const expectStack = support.expectStack;
const see = support.see;

test "a word group the build leaves out has no words in the dictionary, and its code does not run" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    const options = @import("build_options");
    const groups = .{
        .{ options.files, [_][]const u8{ "INCLUDE", "REQUIRE", "OPEN-FILE", "READ-LINE", "STDIN", "SLURP-FILE", "$SLURP-FILE", "$[]SLURP" }, Builtin.include },
        .{ options.help, [_][]const u8{ "HELP", "LICENSE" }, Builtin.help },
        .{ options.tools, [_][]const u8{ "SEE", "LOCATE", "WHERE" }, Builtin.see },
        .{ options.image, [_][]const u8{ "SAVE", "LOAD", "SAVESYS" }, Builtin.save },
    };
    inline for (groups) |group| {
        for (group[1]) |name| try std.testing.expectEqual(group[0], machine.lookup(name) != null);
        // An excluded word can only come from an image of a build that has it: its
        // execution token, kept at the same place, does not run it.
        if (!group[0]) {
            try std.testing.expectError(error.InvalidExecutionToken, machine.executeBuiltin(group[2]));
            var line: [32]u8 = undefined;
            const text = try std.fmt.bufPrint(&line, "{d} EXECUTE", .{machine.builtinWord(group[2])});
            try std.testing.expectError(error.InvalidExecutionToken, machine.interpretLine(text));
        }
    }
}

test "every build gives each built-in word the same execution token, a word left out keeping its place without a name" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    // The Root list's copies follow the definitions.
    const definitions = forth.State.builtin_definitions;
    try std.testing.expect(machine.builtin_count > definitions.len);
    for (definitions, 0..) |definition, id| {
        const word = machine.words[id];
        try std.testing.expectEqual(definition[1], word.builtin);
        if (defs.isExcludedBuiltin(definition[1])) {
            try std.testing.expectEqual(@as(u8, 0), word.name_len);
        } else {
            try std.testing.expectEqualStrings(definition[0], machine.wordName(word));
        }
        // An immediate word stays immediate when the build leaves it out, so a name token
        // from an image of a build that has it compiles the same way.
        if (definition[1] == .fliteral or definition[1] == .compile_if) try std.testing.expect(word.immediate);
    }
}

test "a full restore keeps this build's built-in words when the image's built-in names differ" {
    var output = Output{};
    const source = try createMachine(&output);
    defer destroyMachine(source);
    try source.interpretLine(": MINE 7 ; : TWICE MINE DUP + ;");
    const saved = try saveImage(source);
    defer freeImage(saved);

    // The image as a build without DUP's name would save it: DUP keeps its place without
    // a name, and the names after it move down.
    const Word = @TypeOf(source.words[0]);
    const dup: usize = source.lookup("DUP").?;
    const removed: usize = source.words[dup].name_len;
    const removed_at: usize = source.words[dup].name_start;
    const header = 24;
    const words_end = header + @as(usize, source.word_count) * @sizeOf(Word);
    const names_at = words_end + @as(usize, source.code_count) * @sizeOf(@TypeOf(source.code[0]));
    const image = try std.testing.allocator.alloc(u8, saved.len - removed);
    defer std.testing.allocator.free(image);
    @memcpy(image[0 .. names_at + removed_at], saved[0 .. names_at + removed_at]);
    @memcpy(image[names_at + removed_at ..], saved[names_at + removed_at + removed ..]);
    std.mem.writeInt(u32, image[20..24], source.names_used - @as(u32, @intCast(removed)), .little);
    image[header + dup * @sizeOf(Word) + @offsetOf(Word, "name_len")] = 0;
    for (dup + 1..source.word_count) |id| {
        const at = header + id * @sizeOf(Word) + @offsetOf(Word, "name_start");
        const start = std.mem.readInt(u32, image[at..][0..4], .little);
        std.mem.writeInt(u32, image[at..][0..4], start - @as(u32, @intCast(removed)), .little);
    }
    resealImage(image);

    const restored = try createMachine(&output);
    defer destroyMachine(restored);
    const fresh_names = restored.names_used;
    try restored.restoreImage(image);
    // DUP keeps this build's name, and the image's words their own.
    try std.testing.expectEqualStrings("DUP", restored.wordName(restored.words[dup]));
    try std.testing.expectEqual(fresh_names + "MINE".len + "TWICE".len, restored.names_used);
    try restored.interpretLine("TWICE 3 DUP");
    try expectStack(restored, &.{ 14, 3, 3 });
    try restored.interpretLine("FORGET TWICE : AFTER 1 ; AFTER");
    try expectStack(restored, &.{ 14, 3, 3, 1 });
}

test "a built-in word compiles to a direct call, and an image with plain calls still runs" {
    var output = Output{};
    const source = try createMachine(&output);
    defer destroyMachine(source);
    try source.interpretLine(": SQ DUP * ; : FOUR SQ SQ ;");
    const sq = source.words[source.lookup("SQ").?];
    const four = source.words[source.lookup("FOUR").?];
    // Execution-only tags bypass both word-kind and primitive dispatch.
    try std.testing.expectEqual(defs.OpKind.dup, source.code[sq.code_start].kind);
    try std.testing.expectEqual(defs.OpKind.mul, source.code[sq.code_start + 1].kind);
    try std.testing.expectEqual(defs.OpKind.call_colon, source.code[four.code_start].kind);

    // The same words with the built-in words called with .call, as SIGIMG32 had them.
    const image = try saveImage(source);
    defer freeImage(image);
    const Word = @TypeOf(source.words[0]);
    const Op = @TypeOf(source.code[0]);
    const code_at = 24 + @as(usize, source.word_count) * @sizeOf(Word);
    var changed: usize = 0;
    for (0..source.code_count) |index| {
        const at = code_at + index * @sizeOf(Op) + @offsetOf(Op, "kind");
        if (image[at] != @intFromEnum(defs.OpKind.call_builtin)) continue;
        image[at] = @intFromEnum(defs.OpKind.call);
        changed += 1;
    }
    try std.testing.expect(changed >= 2);
    resealImage(image);
    const restored = try createMachine(&output);
    defer destroyMachine(restored);
    try restored.restoreImage(image);
    try restored.interpretLine("3 FOUR 5 SQ");
    try expectStack(restored, &.{ 81, 25 });
}

test "execution-only calls normalize on save and relocate on LOAD without changing SEE" {
    var output = Output{};
    const source = try createMachine(&output);
    defer destroyMachine(source);
    try source.interpretLine(": SQ DUP * ; : FOUR SQ SQ ; : DOWN DUP IF 1- RECURSE THEN ; : ALIASES MINUS INVERT ;");
    const image = try saveImage(source);
    defer freeImage(image);
    try std.testing.expectEqualStrings("SIGIMG39", image[0..8]);
    const Word = @TypeOf(source.words[0]);
    const Op = @TypeOf(source.code[0]);
    const code_at = 24 + @as(usize, source.word_count) * @sizeOf(Word);
    var inline_end: usize = 0;
    for (source.code[0..source.code_count], 0..) |op, index| {
        const at = code_at + index * @sizeOf(Op);
        const tag = image[at + @offsetOf(Op, "kind")];
        const expected = if (index < inline_end) defs.OpKind.branch else if (op.kind == .call_colon) defs.OpKind.call else if (defs.isPrimitiveOp(op.kind)) defs.OpKind.call_builtin else op.kind;
        try std.testing.expectEqual(@intFromEnum(expected), tag);
        if (index >= inline_end and inline_calls.isInline(op))
            inline_end = index + inline_calls.span(op.value);
    }
    // Saving must not replace the fast instructions in the running machine.
    const four = source.words[source.lookup("FOUR").?];
    try std.testing.expectEqual(defs.OpKind.call_colon, source.code[four.code_start].kind);
    const restored = try createMachine(&output);
    defer destroyMachine(restored);
    try restored.restoreImage(image);
    const restored_four = restored.words[restored.lookup("FOUR").?];
    try std.testing.expectEqual(defs.OpKind.call_colon, restored.code[restored_four.code_start].kind);
    const target = try createMachine(&output);
    defer destroyMachine(target);
    // Shift both dictionary ids and code addresses before appending.
    try target.interpretLine(": EXISTING 99 ; 11 CONSTANT OLD");
    try target.appendImage(restored);
    try target.interpretLine("3 FOUR 5 DOWN EXISTING");
    try expectStack(target, &.{ 81, 0, 99 });
    try target.interpretLine(see("SEE FOUR SEE ALIASES"));
    try std.testing.expectEqualStrings(see(": FOUR\n  SQ SQ\n;\n: ALIASES\n  MINUS INVERT\n;\n"), output.written());
}

test "primitive instructions match dictionary calls including errors and full stacks" {
    var direct_output = Output{};
    var generic_output = Output{};
    const direct = try createMachine(&direct_output);
    defer destroyMachine(direct);
    const generic = try createMachine(&generic_output);
    defer destroyMachine(generic);
    const Op = @TypeOf(direct.code[0]);
    try direct.interpretLine(": PROBE ;");
    const probe_id = direct.lookup("PROBE").?;
    const probe_start = direct.words[probe_id].code_start;
    // Compare all specialized primitives with their interpreted implementation,
    // including partial stack effects on underflow/overflow and memory errors.
    inline for (@typeInfo(defs.OpKind).@"enum".field_names) |name| {
        const kind = @field(defs.OpKind, name);
        if (comptime defs.isPrimitiveOp(kind)) {
            const builtin = comptime defs.primitiveBuiltin(kind);
            try std.testing.expectEqual(kind, defs.builtinOpKind(builtin));
            const id = direct.builtinWord(builtin);
            for ([_]usize{ 0, 1, 2, 3, direct.data_stack.len }) |depth| for ([_]bool{ false, true }) |populated| {
                direct.data_depth = depth;
                generic.data_depth = depth;
                @memset(direct.data_stack, 3);
                @memset(generic.data_stack, 3);
                const address = forth.data_start;
                if (populated and depth > 0) {
                    direct.data_stack[depth - 1] = address;
                    generic.data_stack[depth - 1] = address;
                }
                try direct.writeCell(address, 123);
                try generic.writeCell(address, 123);
                direct.float_depth = @min(depth, direct.float_stack.len);
                generic.float_depth = direct.float_depth;
                @memset(direct.float_stack, 2);
                @memset(generic.float_stack, 2);
                direct.return_depth = if (populated) direct.return_stack.len else 0;
                generic.return_depth = direct.return_depth;
                @memset(direct.return_stack, 7);
                @memset(generic.return_stack, 7);
                direct.loop_depth = if (populated) 2 else 0;
                generic.loop_depth = direct.loop_depth;
                direct.loop_stack[0] = .{ .index = 11, .limit = 20, .exit_pc = 0 };
                direct.loop_stack[1] = .{ .index = 13, .limit = 20, .exit_pc = 0 };
                generic.loop_stack[0] = direct.loop_stack[0];
                generic.loop_stack[1] = direct.loop_stack[1];
                direct.code[probe_start] = Op{ .kind = kind, .value = id };
                const direct_result = direct.executeWord(probe_id);
                const generic_result = generic.executeWord(try generic.wordId(id));
                if (generic_result) |_| {
                    try direct_result;
                } else |err| try std.testing.expectError(err, direct_result);
                try std.testing.expectEqual(generic.data_depth, direct.data_depth);
                try std.testing.expectEqualSlices(forth.Cell, generic.data_stack, direct.data_stack);
                try std.testing.expectEqual(generic.float_depth, direct.float_depth);
                try std.testing.expectEqualSlices(forth.Float, generic.float_stack, direct.float_stack);
                try std.testing.expectEqual(generic.return_depth, direct.return_depth);
                try std.testing.expectEqualSlices(forth.Cell, generic.return_stack, direct.return_stack);
                try std.testing.expectEqual(generic.loop_depth, direct.loop_depth);
                try std.testing.expectEqualSlices(u8, generic.memory[address..][0..8], direct.memory[address..][0..8]);
            };
        }
    }
}

test "SEE shows a built-in word the build leaves out by its own name" {
    try support.skipWithout(&.{.tools});
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    try machine.interpretLine(": CALL-DUP DUP ; : TICK-DUP ['] DUP ; SYNONYM MY-DUP DUP");
    // DUP as it is in a build that leaves it out: in its place, without a name.
    machine.words[machine.lookup("DUP").?].name_len = 0;
    try machine.interpretLine("SEE CALL-DUP SEE TICK-DUP SEE MY-DUP");
    try std.testing.expectEqualStrings(": CALL-DUP\n  DUP\n;\n: TICK-DUP\n  ['] DUP\n;\nSYNONYM MY-DUP DUP\n", output.written());
}

test "FORGET, MARKER, and a failed definition give back the space of their names" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    const start = machine.names_used;
    try machine.interpretLine(": A-LONG-NAME 1 ; VARIABLE ANOTHER-NAME");
    try std.testing.expectEqual(start + "A-LONG-NAME".len + "ANOTHER-NAME".len, machine.names_used);
    try machine.interpretLine("FORGET A-LONG-NAME");
    try std.testing.expectEqual(start, machine.names_used);
    try machine.interpretLine("MARKER GONE : FIRST-WORD 1 ; : SECOND-WORD 2 ; GONE");
    try std.testing.expectEqual(start, machine.names_used);
    try std.testing.expectError(error.UnknownWord, machine.interpretLine(": BROKEN-DEFINITION NO-SUCH-WORD ;"));
    machine.report(error.UnknownWord);
    try std.testing.expectEqual(start, machine.names_used);
    try machine.interpretLine(": SHORT 7 ; SHORT");
    try expectStack(machine, &.{7});
}

test "a full name area is a full dictionary, and the words before still work" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    // Names of 255 characters fill the name area long before the word limit.
    var line: [300]u8 = undefined;
    var count: usize = 0;
    while (true) : (count += 1) {
        const text = try std.fmt.bufPrint(&line, ": {s}{d:0>6} {d} ;", .{ repeat("N", 249), count, count });
        machine.interpretLine(text) catch |err| {
            try std.testing.expectEqual(error.DictionaryFull, err);
            machine.report(err);
            break;
        };
    }
    try std.testing.expect(count > 1000 and count < machine.words.len);
    try std.testing.expect(machine.names_used <= machine.names.len);
    try machine.interpretLine(try std.fmt.bufPrint(&line, "{s}{d:0>6}", .{ repeat("N", 249), count - 1 }));
    try expectStack(machine, &.{@as(forth.Cell, @intCast(count - 1))});
}

test "an image keeps HERE's data, the used heap, and the source table, and nothing else" {
    var output = Output{};
    const source = try createMachine(&output);
    defer destroyMachine(source);
    try source.interpretLine("VARIABLE S S\" kept on the heap\" S $! : SHOW S $@ TYPE ; CREATE BUF 4 ALLOT 1 BUF C!");
    // Bytes above HERE are not part of the image.
    try source.interpretLine("HERE 100 + 99 SWAP C!");
    const image = try std.testing.allocator.alloc(u8, forth.State.imageCapacity());
    defer std.testing.allocator.free(image);
    const length = try source.encodeImage(image);

    const source_table_bytes = 64 * 256 + 64;
    const expected = 24 + @as(usize, source.word_count) * @sizeOf(@TypeOf(source.words[0])) + @as(usize, source.code_count) * @sizeOf(@TypeOf(source.code[0])) +
        source.names_used + @as(usize, @intCast(source.data_here - 0x10000)) + @as(usize, @intCast(source.heapTop() - forth.data_limit)) + source_table_bytes + 4;
    try std.testing.expectEqual(expected, length);
    try std.testing.expect(length < 200_000);

    const loaded = try createMachine(&output);
    defer destroyMachine(loaded);
    try loaded.restoreImage(image[0..length]);
    try loaded.interpretLine("SHOW BUF C@ HERE 100 + C@");
    try std.testing.expectEqualStrings("kept on the heap", output.written());
    try expectStack(loaded, &.{ 1, 0 });
    try std.testing.expectError(error.InvalidImage, loaded.restoreImage(image[0 .. length - 1]));
}

test "an FVALUE and a TO of it keep working after LOAD, a second LOAD, and a full restore" {
    try support.skipWithoutFloat();
    var output = Output{};
    const source = try createMachine(&output);
    defer destroyMachine(source);
    try source.interpretLine("1.5E FVALUE FV : SETFV 2.5E TO FV ; : GETFV FV ;");
    const image = try saveImage(source);
    defer freeImage(image);

    // Appended twice after data of the dictionary's own, so the address of the value moves.
    const target = try createMachine(&output);
    defer destroyMachine(target);
    try target.interpretLine("CREATE FILLER 100 ALLOT 7E FVALUE OWN : EARLIER 1 ;");
    const loaded = try createMachine(&output);
    defer destroyMachine(loaded);
    try loaded.restoreImage(image);
    try target.appendImage(loaded);
    try target.interpretLine("FV F. SETFV FV F. GETFV F. 3.5E TO FV GETFV F.");
    try target.appendImage(loaded);
    try target.interpretLine("FV F. SETFV GETFV F. OWN F.");
    try std.testing.expectEqualStrings("1.5 2.5 2.5 3.5 1.5 2.5 7. ", output.written());

    // A full restore, as SAVESYS starts, keeps the value and the word that stores it.
    output.len = 0;
    const restored = try createMachine(&output);
    defer destroyMachine(restored);
    try source.interpretLine("4.5E TO FV");
    const image2 = try saveImage(source);
    defer freeImage(image2);
    try restored.restoreImage(image2);
    try restored.interpretLine("FV F. SETFV GETFV F." ++ see(" SEE FV"));
    try std.testing.expectEqualStrings("4.5 2.5 " ++ see("2.5e FVALUE FV\n"), output.written());
}

test "LOAD gives the added words their names after the dictionary's own" {
    var output = Output{};
    const source = try createMachine(&output);
    defer destroyMachine(source);
    try source.interpretLine(": FIRST-LOADED 10 ; : SECOND-LOADED FIRST-LOADED 1+ ;");
    const image = try std.testing.allocator.alloc(u8, forth.State.imageCapacity());
    defer std.testing.allocator.free(image);
    const length = try source.encodeImage(image);

    const target = try createMachine(&output);
    defer destroyMachine(target);
    try target.interpretLine(": ALREADY-HERE 5 ;");
    const loaded = try createMachine(&output);
    defer destroyMachine(loaded);
    try loaded.restoreImage(image[0..length]);
    try target.appendImage(loaded);
    try target.interpretLine("ALREADY-HERE SECOND-LOADED FIRST-LOADED" ++ see(" SEE SECOND-LOADED"));
    try expectStack(target, &.{ 5, 11, 10 });
    try std.testing.expectEqualStrings(see(": SECOND-LOADED\n  FIRST-LOADED 1+\n;\n"), output.written());
    try target.interpretLine("FORGET FIRST-LOADED : AFTER-FORGET 3 ; AFTER-FORGET");
    try expectStack(target, &.{ 5, 11, 10, 3 });
}

fn saveImage(machine: *forth.State) ![]u8 {
    const image = try std.testing.allocator.alloc(u8, forth.State.imageCapacity());
    errdefer std.testing.allocator.free(image);
    const length = try machine.encodeImage(image);
    return image[0..length];
}

fn freeImage(image: []u8) void {
    std.testing.allocator.free(image.ptr[0..forth.State.imageCapacity()]);
}

/// Writes the checksum again after a test has changed an image, so that the checks
/// behind it are reached.
fn resealImage(image: []u8) void {
    const body = image[0 .. image.len - 4];
    std.mem.writeInt(u32, image[body.len..][0..4], std.hash.Crc32.hash(body), .little);
}

test "a damaged image, or one whose names are out of order or out of range, is rejected before anything changes" {
    var output = Output{};
    const source = try createMachine(&output);
    defer destroyMachine(source);
    try source.interpretLine(": FIRST-WORD 1 ; :NONAME 2 ; DROP : SECOND-WORD 3 ;");
    const image = try saveImage(source);
    defer freeImage(image);
    const Word = @TypeOf(source.words[0]);
    const builtins: usize = source.builtin_count;

    const loaded = try createMachine(&output);
    defer destroyMachine(loaded);
    const before_words = loaded.word_count;
    const before_names = loaded.names_used;
    // Each byte is flipped with the mask, so the corruption changes it whatever it was
    // (a fixed value can equal the byte already there as the built-in names grow).
    const corruptions = [_]struct { usize, usize, u8 }{
        // A user word's name moved by one byte, into the built-in names or past them.
        .{ builtins, @offsetOf(Word, "name_start"), 0x01 },
        // The last built-in name given another length.
        .{ builtins - 1, @offsetOf(Word, "name_len"), 0xff },
        // The last word's name moved far past the end of the used names.
        .{ source.word_count - 1, @offsetOf(Word, "name_start") + 2, 0x04 },
        // A built-in word at another place, as in an image of a build that gave the
        // built-in words other execution tokens; their tokens would mean other words.
        .{ 0, @offsetOf(Word, "builtin"), 0x01 },
        .{ 1, @offsetOf(Word, "kind"), 0x01 },
    };
    for (corruptions) |corruption| {
        const at = 24 + corruption[0] * @sizeOf(Word) + corruption[1];
        const saved = image[at];
        image[at] = saved ^ corruption[2];
        resealImage(image);
        try std.testing.expectError(error.InvalidImage, loaded.restoreImage(image));
        image[at] = saved;
        resealImage(image);
        try std.testing.expectEqual(before_words, loaded.word_count);
        try std.testing.expectEqual(before_names, loaded.names_used);
    }
    // SIGIMG38 and earlier are not read: their user words have other numbers, or their addresses are of another layout.
    for ([_]*const [8]u8{ "SIGIMG31", "SIGIMG32", "SIGIMG33", "SIGIMG34", "SIGIMG35", "SIGIMG36", "SIGIMG37", "SIGIMG38" }) |old| {
        @memcpy(image[0..8], old);
        resealImage(image);
        try std.testing.expectError(error.InvalidImage, loaded.restoreImage(image));
    }
    @memcpy(image[0..8], "SIGIMG39");
    resealImage(image);
    // One damaged byte anywhere, here in the saved memory or in the checksum itself,
    // fails the checksum, and the dictionary, code, and memory stay as they were.
    const memory_before = try std.testing.allocator.dupe(u8, loaded.memory);
    defer std.testing.allocator.free(memory_before);
    const code_before = loaded.code_count;
    const here_before = loaded.data_here;
    for ([_]usize{ image.len - 100, image.len - 1 }) |at| {
        image[at] ^= 0x01;
        try std.testing.expectError(error.InvalidImage, loaded.restoreImage(image));
        image[at] ^= 0x01;
        try std.testing.expectEqual(before_words, loaded.word_count);
        try std.testing.expectEqual(before_names, loaded.names_used);
        try std.testing.expectEqual(code_before, loaded.code_count);
        try std.testing.expectEqual(here_before, loaded.data_here);
        try std.testing.expectEqualSlices(u8, memory_before, loaded.memory);
    }
    try loaded.restoreImage(image);
    try loaded.interpretLine("FIRST-WORD SECOND-WORD");
    try expectStack(loaded, &.{ 1, 3 });
}

test "a VARIABLE without room for its name and a definition CATCH abandons leave HERE and the names as they were" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    const names_before = machine.names_used;
    try machine.interpretLine(": START S\" : BROKEN NO-SUCH-WORD ;\" EVALUATE ; ' START CATCH .");
    try std.testing.expectEqualStrings("-13 ", output.written());
    try std.testing.expectEqual(names_before + "START".len, machine.names_used);

    var line: [300]u8 = undefined;
    var count: usize = 0;
    while (true) : (count += 1) {
        machine.interpretLine(try std.fmt.bufPrint(&line, ": {s}{d:0>6} ;", .{ repeat("N", 249), count })) catch |err| {
            machine.report(err);
            break;
        };
    }
    const here = machine.data_here;
    const names = machine.names_used;
    const words = machine.word_count;
    try std.testing.expectError(error.DictionaryFull, machine.interpretLine("VARIABLE " ++ repeat("V", 255)));
    machine.report(error.DictionaryFull);
    try std.testing.expectEqual(here, machine.data_here);
    try std.testing.expectEqual(names, machine.names_used);
    try std.testing.expectEqual(words, machine.word_count);
}

test "LOAD into a dictionary without room changes nothing, and unnamed words keep LOAD and FORGET in step" {
    var output = Output{};
    const source = try createMachine(&output);
    defer destroyMachine(source);
    try source.interpretLine(": AAA 1 ; :NONAME 2 ; DROP : BBB 3 ;");
    const image = try saveImage(source);
    defer freeImage(image);
    const loaded = try createMachine(&output);
    defer destroyMachine(loaded);
    try loaded.restoreImage(image);

    const target = try createMachine(&output);
    defer destroyMachine(target);
    try target.interpretLine(":NONAME 9 ; DROP : CCC 4 ;");
    const names_before = target.names_used;
    try target.appendImage(loaded);
    try target.interpretLine("AAA BBB CCC");
    try expectStack(target, &.{ 1, 3, 4 });
    try target.interpretLine("FORGET AAA : DDD 5 ; DDD CCC");
    try std.testing.expectEqual(names_before + "DDD".len, target.names_used);
    try expectStack(target, &.{ 1, 3, 4, 5, 4 });

    // A full name area: the appended image does not fit and nothing changes.
    const full = try createMachine(&output);
    defer destroyMachine(full);
    var line: [300]u8 = undefined;
    var count: usize = 0;
    while (true) : (count += 1) {
        full.interpretLine(try std.fmt.bufPrint(&line, ": {s}{d:0>6} ;", .{ repeat("N", 249), count })) catch |err| {
            full.report(err);
            break;
        };
    }
    const words = full.word_count;
    const names = full.names_used;
    const code = full.code_count;
    const here = full.data_here;
    // Names longer than the room left (less than one 255-byte name).
    const long_source = try createMachine(&output);
    defer destroyMachine(long_source);
    try long_source.interpretLine(": " ++ repeat("A", 200) ++ " 1 ; : " ++ repeat("B", 200) ++ " 2 ;");
    const long_image = try saveImage(long_source);
    defer freeImage(long_image);
    const long_loaded = try createMachine(&output);
    defer destroyMachine(long_loaded);
    try long_loaded.restoreImage(long_image);
    try std.testing.expectError(error.DictionaryFull, full.appendImage(long_loaded));
    try std.testing.expectEqual(words, full.word_count);
    try std.testing.expectEqual(names, full.names_used);
    try std.testing.expectEqual(code, full.code_count);
    try std.testing.expectEqual(here, full.data_here);
}

test "LOAD keeps a DEFER's action pointing to the loaded word" {
    var output = Output{};
    const source = try createMachine(&output);
    defer destroyMachine(source);
    try source.interpretLine(": TWICE 2 * ; DEFER ACT ' TWICE IS ACT DEFER BUILTIN-ACT ' DUP IS BUILTIN-ACT");
    const image = try std.testing.allocator.alloc(u8, forth.State.imageCapacity());
    defer std.testing.allocator.free(image);
    const length = try source.encodeImage(image);

    const target = try createMachine(&output);
    defer destroyMachine(target);
    try target.interpretLine(": ALREADY-HERE 5 ; : MORE 6 ;");
    const loaded = try createMachine(&output);
    defer destroyMachine(loaded);
    try loaded.restoreImage(image[0..length]);
    try target.appendImage(loaded);
    try target.interpretLine("4 ACT 3 BUILTIN-ACT ACTION-OF ACT ' TWICE =");
    try expectStack(target, &.{ 8, 3, 3, -1 });
}
