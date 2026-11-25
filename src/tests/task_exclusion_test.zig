//! AC-28: inspect tables and image payloads independently of search order.
const std = @import("std");
const forth = @import("../forth.zig");
const defs = @import("../core/defs.zig");
const format = @import("../core/image_format.zig");
const support = @import("support.zig");

fn isTask(b: defs.Builtin) bool {
    return std.mem.startsWith(u8, @tagName(b), "task_");
}

test "AC28 task builtin and HELP tables obey configuration without search order" {
    @setEvalBranchQuota(100_000);
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    if (defs.extension_enabled) try machine.interpretLine("REQUIRE-EXTENSION");
    var public_count: usize = 0;
    for (@import("../core/words_extension.zig").definitions) |definition| {
        if (!std.mem.startsWith(u8, definition[0], "TASK-")) continue;
        public_count += 1;
        try std.testing.expect(isTask(definition[1]));
    }
    try std.testing.expectEqual(@as(usize, 58), public_count);
    // Includes any future internal task_* builtin, even without a public name.
    inline for (@typeInfo(defs.Builtin).@"enum".field_names) |name| {
        if (comptime std.mem.startsWith(u8, name, "task_")) {
            try std.testing.expectEqual(!defs.extension_enabled, defs.isExcludedBuiltin(@field(defs.Builtin, name)));
            if (!defs.extension_enabled) try std.testing.expectError(error.InvalidExecutionToken, machine.executeBuiltin(@field(defs.Builtin, name)));
        }
    }
    var installed_count: usize = 0;
    for (machine.words[0..machine.word_count]) |word| {
        if (word.kind == .builtin and isTask(word.builtin)) installed_count += 1;
        if (!defs.extension_enabled) {
            try std.testing.expect(!std.mem.startsWith(u8, machine.wordName(word), "TASK-"));
            try std.testing.expect(word.kind != .builtin or !isTask(word.builtin));
        }
    }
    try std.testing.expectEqual(@as(usize, if (defs.extension_enabled) 58 else 0), installed_count);
    // No task-specific direct opcode currently exists. Fail if one is introduced.
    inline for (@typeInfo(defs.OpKind).@"enum".field_names) |name| {
        try std.testing.expect(!std.mem.startsWith(u8, name, "task_"));
    }
    var help_count: usize = 0;
    for (@import("../core/words_help.zig").help_entries) |entry| {
        if (std.mem.startsWith(u8, entry.name, "TASK-")) help_count += 1;
    }
    // The filtered metadata follows extension; help=false removes the entry point.
    try std.testing.expectEqual(@as(usize, if (defs.extension_enabled) 58 else 0), help_count);
    try std.testing.expectEqual(defs.help_enabled, machine.lookup("HELP") != null);
}

test "AC28 excluded task source preserves existing dictionary after error recovery" {
    if (defs.extension_enabled) return error.SkipZigTest;
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try machine.interpretLine(": KEPT 42 ;");
    const count = machine.word_count;
    const code = machine.code_count;
    const names = machine.names_used;
    const here = machine.data_here;
    for (@import("../core/words_extension.zig").definitions) |definition| {
        if (!isTask(definition[1])) continue;
        var buffer: [128]u8 = undefined;
        const line = try std.fmt.bufPrint(&buffer, ": BAD {s} ;", .{definition[0]});
        try std.testing.expectError(error.UnknownWord, machine.interpretLine(line));
        machine.report(error.UnknownWord);
        try std.testing.expectEqual(count, machine.word_count);
        try std.testing.expectEqual(code, machine.code_count);
        try std.testing.expectEqual(names, machine.names_used);
        try std.testing.expectEqual(here, machine.data_here);
        try std.testing.expect(machine.lookup("BAD") == null);
        try machine.interpretLine("KEPT");
        try support.expectStack(machine, &.{42});
        machine.data_depth = 0;
    }
    try machine.interpretLine(": AFTER 9 ; AFTER");
    try support.expectStack(machine, &.{9});
}

test "AC28 saved task exclusions and rejected builtin and direct Op preserve dictionary" {
    if (defs.extension_enabled) return error.SkipZigTest;
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try machine.interpretLine(": KEPT 42 ; : PROBE 1 ;");
    const storage = try std.testing.allocator.alloc(u8, forth.State.imageCapacity(.small));
    defer std.testing.allocator.free(storage);
    const workspace = try std.testing.allocator.create(format.Workspace);
    defer std.testing.allocator.destroy(workspace);
    const length = try machine.encodeImage(storage);
    const view = try format.parse(storage[0..length], workspace);
    for (0..view.header.word_count) |i| {
        const word = std.mem.bytesToValue(defs.Word, view.words[i * @sizeOf(defs.Word) ..][0..@sizeOf(defs.Word)]);
        try std.testing.expect(!std.mem.startsWith(u8, view.names[word.name_start..][0..word.name_len], "TASK-"));
        try std.testing.expect(word.kind != .builtin or !isTask(word.builtin));
    }
    for (0..view.header.code_count) |i| {
        const op = std.mem.bytesToValue(defs.Op, view.code[i * @sizeOf(defs.Op) ..][0..@sizeOf(defs.Op)]);
        try @import("../core/image_features.zig").validateOperation(op);
    }
    // Real encoder, valid checksums: isolate every task builtin from the other
    // extension words in a foreign image, as both an added word and a direct Op.
    const probe = machine.lookup("PROBE").?;
    const original_word = machine.words[probe];
    const original_op = machine.code[original_word.code_start];
    for (@import("../core/words_extension.zig").definitions) |definition| {
        if (!isTask(definition[1])) continue;
        for (0..2) |mode| {
            if (mode != 0) {
                machine.code[original_word.code_start] = .{ .kind = .builtin, .value = @backingInt(definition[1]) };
            } else {
                machine.words[probe].kind = .builtin;
                machine.words[probe].builtin = definition[1];
            }
            const size = try machine.encodeImage(storage);
            machine.words[probe] = original_word;
            machine.code[original_word.code_start] = original_op;
            const before_size = try machine.encodeImage(storage[size..]);
            try std.testing.expectError(error.InvalidImage, machine.restoreImage(storage[0..size]));
            const after = try std.testing.allocator.alloc(u8, before_size);
            defer std.testing.allocator.free(after);
            try std.testing.expectEqual(before_size, try machine.encodeImage(after));
            try std.testing.expectEqualSlices(u8, storage[size..][0..before_size], after);
        }
    }
    try machine.interpretLine("KEPT PROBE : AFTER 9 ; AFTER");
    try support.expectStack(machine, &.{ 42, 1, 9 });
}
