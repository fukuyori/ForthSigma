//! Extension registration, rollback, lifetime, and image integration contracts.
const std = @import("std");
const support = @import("support.zig");
const defs = @import("../core/defs.zig");
const map = @import("../core/memory_map.zig");
const extension = @import("../core/words_extension.zig");
const loading = @import("../core/library_loading.zig");
const format = @import("../core/image_format.zig");

test "extension exclusion leaves no vocabulary, parser override, or HELP entries" {
    if (defs.extension_enabled) return error.SkipZigTest;
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try std.testing.expectError(error.UnknownWord, machine.interpretLine("REQUIRE-EXTENSION"));
    try std.testing.expectEqualStrings("REQUIRE-EXTENSION", machine.last_unknown_word.?);
    try std.testing.expect(machine.lookup("EXTENSION") == null);
    try std.testing.expect(@import("../core/words_help.zig").entry("HOST-OS") == null);
    try std.testing.expect(@import("../core/words_help.zig").entry("REQUIRE-EXTENSION") == null);
    try machine.interpretLine(": REQUIRE-EXTENSION 42 ; REQUIRE-EXTENSION");
    try support.expectStack(machine, &.{42});
    try std.testing.expectError(error.InvalidExecutionToken, machine.executeBuiltin(.host_os));
}

test "extension loads independently once and keeps order current base and pending name" {
    try support.skipWithout(&.{.extension});
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try machine.interpretLine("HEX VOCABULARY OWN-W ALSO OWN-W DEFINITIONS");
    const current = machine.currentWordlist();
    var order_buf: [map.max_search_order]map.Cell = undefined;
    const order = machine.searchOrder(&order_buf);
    var saved_order: [map.max_search_order]map.Cell = undefined;
    @memcpy(saved_order[0..order.len], order);
    machine.noname_next = true;
    try machine.interpretLine("REQUIRE-EXTENSION");
    try std.testing.expect(machine.noname_next);
    machine.noname_next = false;
    try std.testing.expectEqual(current, machine.currentWordlist());
    try std.testing.expectEqual(@as(map.Cell, 16), machine.readCellConst(map.base_address));
    try std.testing.expectEqualSlices(map.Cell, saved_order[0..order.len], machine.searchOrder(&order_buf));
    try std.testing.expect(extension.extensionLoaded(machine));
    try std.testing.expect(machine.lookup("HOST-OS") == null);
    try std.testing.expect(machine.lookup("AUDIO") == null);
    try std.testing.expect(machine.lookup("GRAPHICS") == null);
    const count = machine.word_count;
    try machine.interpretLine("require-extension REQUIRE-EXTENSION");
    try std.testing.expectEqual(count, machine.word_count);
    try machine.interpretLine(": BAD-W");
    try std.testing.expectError(error.InvalidDefinition, machine.interpretLine("REQUIRE-EXTENSION"));
}

test "extension failure rolls back vocabulary and definitions then permits retry" {
    try support.skipWithout(&.{.extension});
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    const count = machine.word_count;
    const here = machine.data_here;
    const current = machine.currentWordlist();
    machine.extension_library = ": PART-W 1 ; NO-SUCH-EXTENSION-WORD";
    try std.testing.expectError(error.UnknownWord, machine.interpretLine("REQUIRE-EXTENSION"));
    try std.testing.expectEqual(count, machine.word_count);
    try std.testing.expectEqual(here, machine.data_here);
    try std.testing.expectEqual(current, machine.currentWordlist());
    try std.testing.expect(!extension.extensionLoaded(machine));
    try std.testing.expect(machine.lookup("EXTENSION") == null);
    machine.extension_library = extension.library;
    try machine.interpretLine("REQUIRE-EXTENSION ALSO EXTENSION");
    try std.testing.expect(machine.lookup("PART-W") == null);
    try std.testing.expect(machine.lookup("HOST-OS") != null);
}

test "extension FORGET and MARKER allow clean reload" {
    try support.skipWithout(&.{.extension});
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try machine.interpretLine("MARKER BACK-W REQUIRE-EXTENSION BACK-W");
    try std.testing.expect(!extension.extensionLoaded(machine));
    try machine.interpretLine("REQUIRE-EXTENSION FORGET EXTENSION");
    try std.testing.expect(!extension.extensionLoaded(machine));
    try machine.interpretLine("REQUIRE-EXTENSION ALSO EXTENSION HOST-OS TYPE PREVIOUS");
    try std.testing.expectEqualStrings(extension.osName(@import("builtin").os.tag), output.written());
}

test "HOST-OS maps known and unknown targets and refreshes borrowed logical text" {
    try std.testing.expectEqualStrings("windows", extension.osName(.windows));
    try std.testing.expectEqualStrings("linux", extension.osName(.linux));
    try std.testing.expectEqualStrings("macos", extension.osName(.macos));
    try std.testing.expectEqualStrings("unknown", extension.osName(.freestanding));
    try std.testing.expectEqualStrings("unknown", extension.osName(.freebsd));
    try support.skipWithout(&.{.extension});
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try machine.interpretLine("REQUIRE-EXTENSION ALSO EXTENSION HOST-OS");
    const name = extension.osName(@import("builtin").os.tag);
    try support.expectStack(machine, &.{ map.host_os_buffer_address, @intCast(name.len) });
    const at: usize = @intCast(map.host_os_buffer_address);
    @memset(machine.memory[at..][0..8], 'x');
    try machine.interpretLine("2DROP HOST-OS TYPE PREVIOUS");
    try std.testing.expectEqualStrings(name, output.written());
    // A failed two-cell result does not leave a half result or rewrite the buffer.
    machine.data_depth = machine.data_stack.len - 1;
    machine.memory[at] = 'x';
    try std.testing.expectError(error.StackOverflow, machine.executeBuiltin(.host_os));
    try std.testing.expectEqual(machine.data_stack.len - 1, machine.data_depth);
    try std.testing.expectEqual(@as(u8, 'x'), machine.memory[at]);
}

test "extension restore and both append paths retain loaded identity and refresh OS text" {
    try support.skipWithout(&.{ .extension, .image });
    var output = support.Output{};
    const source = try support.createMachine(&output);
    defer support.destroyMachine(source);
    try source.interpretLine("REQUIRE-EXTENSION ALSO EXTENSION HOST-OS 2DROP PREVIOUS");
    // Model a result saved by another OS: HOST-OS must not return persisted bytes.
    @memset(source.memory[@intCast(map.host_os_buffer_address)..][0..8], 'x');
    const image = try std.testing.allocator.alloc(u8, try source.encodedSize());
    defer std.testing.allocator.free(image);
    _ = try source.encodeImage(image);
    try std.testing.expectEqualStrings(map.image_magic, image[0..8]);
    const target = try support.createMachine(&output);
    defer support.destroyMachine(target);
    try target.restoreImage(image);
    try std.testing.expect(extension.extensionLoaded(target));
    const count = target.word_count;
    try target.interpretLine("REQUIRE-EXTENSION ALSO EXTENSION HOST-OS TYPE PREVIOUS");
    try std.testing.expectEqual(count, target.word_count);
    try std.testing.expectEqualStrings(extension.osName(@import("builtin").os.tag), output.written());
    const appended = try support.createMachine(&output);
    defer support.destroyMachine(appended);
    try appended.interpretLine(": PREFIX-W 42 ;");
    try appended.appendImage(source);
    try std.testing.expect(extension.extensionLoaded(appended));
    const append_count = appended.word_count;
    try appended.interpretLine("REQUIRE-EXTENSION");
    try std.testing.expectEqual(append_count, appended.word_count);
    const typed = try support.createMachine(&output);
    defer support.destroyMachine(typed);
    try typed.interpretLine(": PREFIX-W 42 ;");
    var workspace: @import("../core/image_append.zig").Workspace = undefined;
    try @import("../core/image_append.zig").append(typed, image, &workspace);
    try std.testing.expect(extension.extensionLoaded(typed));
    const typed_count = typed.word_count;
    try typed.interpretLine("REQUIRE-EXTENSION");
    try std.testing.expectEqual(typed_count, typed.word_count);
    // Appending a second copy keeps the original selected group identity.
    const recorded = typed.readCellConst(map.extension_vocabulary_address);
    try @import("../core/image_append.zig").append(typed, image, &workspace);
    try std.testing.expectEqual(recorded, typed.readCellConst(map.extension_vocabulary_address));
}

test "extension HELP is available before loading but does not load the vocabulary" {
    try support.skipWithout(&.{ .extension, .help });
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try machine.interpretLine("HELP REQUIRE-EXTENSION HELP HOST-OS");
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "windows") != null);
    try std.testing.expect(!extension.extensionLoaded(machine));
}

test "excluded optional builtins and inline operations reject all image paths atomically" {
    try support.skipWithout(&.{.image});
    // This contract is exercised by excluded configurations in the matrix.
    if (defs.extension_enabled and defs.audio_enabled and defs.files_enabled and defs.debug_enabled) return error.SkipZigTest;
    inline for (.{ .{ defs.extension_enabled, defs.Builtin.host_os }, .{ defs.audio_enabled, defs.Builtin.snd_beep }, .{ defs.files_enabled, defs.Builtin.open_file }, .{ defs.debug_enabled, defs.Builtin.dbg } }) |feature| {
        if (!feature[0]) {
            inline for (.{ false, true }) |inline_only| {
                var output = support.Output{};
                const source = try support.createMachine(&output);
                defer support.destroyMachine(source);
                if (inline_only) {
                    try source.interpretLine(": INLINE-W 42 ;");
                    const id = source.lookup("INLINE-W").?;
                    source.code[source.words[id].code_start] = .{ .kind = .builtin, .value = @intCast(@backingInt(feature[1])) };
                } else {
                    _ = try source.appendWord("OPTIONAL-W", .builtin, feature[1], 0);
                }
                // The wire codec remains independent of this build's feature policy.
                const bytes = try std.testing.allocator.alloc(u8, try source.encodedSize());
                defer std.testing.allocator.free(bytes);
                _ = try source.encodeImage(bytes);
                var validation: format.Workspace = undefined;
                _ = try format.parse(bytes, &validation);
                const target = try support.createMachine(&output);
                defer support.destroyMachine(target);
                try target.interpretLine(": KEPT-W 42 ;");
                const count = target.word_count;
                const here = target.data_here;
                const names = target.names_used;
                const code = target.code_count;
                const heap = target.heapTop();
                const lists = target.wordlistCount();
                try std.testing.expectError(error.InvalidImage, target.restoreImage(bytes));
                try std.testing.expectError(error.InvalidImage, target.appendImage(source));
                var work: @import("../core/image_append.zig").Workspace = undefined;
                try std.testing.expectError(error.InvalidImage, @import("../core/image_append.zig").append(target, bytes, &work));
                try std.testing.expectEqual(count, target.word_count);
                try std.testing.expectEqual(here, target.data_here);
                try std.testing.expectEqual(names, target.names_used);
                try std.testing.expectEqual(code, target.code_count);
                try std.testing.expectEqual(heap, target.heapTop());
                try std.testing.expectEqual(lists, target.wordlistCount());
                try target.interpretLine("KEPT-W");
                try support.expectStack(target, &.{42});
            }
        }
    }
}

test "base excluded word calls keep legacy image behavior and fail only when executed" {
    if (defs.files_enabled or !defs.image_enabled) return error.SkipZigTest;
    var output = support.Output{};
    const source = try support.createMachine(&output);
    defer support.destroyMachine(source);
    try source.interpretLine(": BASE-CALL-W 42 ;");
    const id = source.lookup("BASE-CALL-W").?;
    const file_id = for (source.words[0..source.builtin_count], 0..) |word, i| {
        if (word.builtin == .open_file) break i;
    } else unreachable;
    source.code[source.words[id].code_start] = .{ .kind = .call_builtin, .value = @intCast(file_id) };
    const bytes = try std.testing.allocator.alloc(u8, try source.encodedSize());
    defer std.testing.allocator.free(bytes);
    _ = try source.encodeImage(bytes);
    const target = try support.createMachine(&output);
    defer support.destroyMachine(target);
    try target.restoreImage(bytes);
    try std.testing.expectError(error.InvalidExecutionToken, target.interpretLine("BASE-CALL-W"));
}

test "State append rejects inconsistent source ranges without touching target" {
    try support.skipWithout(&.{.image});
    var output = support.Output{};
    const source = try support.createMachine(&output);
    defer support.destroyMachine(source);
    const target = try support.createMachine(&output);
    defer support.destroyMachine(target);
    const count = target.word_count;
    source.word_count = source.builtin_count - 1;
    try std.testing.expectError(error.InvalidImage, target.appendImage(source));
    try std.testing.expectEqual(count, target.word_count);
}
