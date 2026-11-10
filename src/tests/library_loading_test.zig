//! Tests of word groups whose library is Forth only and which need other groups, as
//! REQUIRE-GUI and REQUIRE-GAME will be: a test group stands in for them.

const std = @import("std");
const forth = @import("../forth.zig");
const defs = @import("../core/defs.zig");
const library_loading = @import("../core/library_loading.zig");
const memory_map = @import("../core/memory_map.zig");
const words_graphics = @import("../core/words_graphics.zig");
const support = @import("support.zig");
const Output = support.Output;
const createMachine = support.createMachine;
const destroyMachine = support.destroyMachine;
const expectStack = support.expectStack;
const skipWithout = support.skipWithout;

const test_group: library_loading.Group(struct { []const u8, defs.Builtin }) = .{
    .vocabulary = "TESTLIB",
    .definitions = &.{},
    .library_name = "*test library*",
    .vocabulary_address = memory_map.gui_vocabulary_address,
    .prerequisites = &.{.{ .require = words_graphics.requireGraphics, .vocabulary_address = memory_map.graphics_vocabulary_address }},
};

/// A machine whose graphics library is one short word, so that the tests load quickly.
fn machineWithSmallGraphics(output: *Output) !*forth.State {
    const machine = try createMachine(output);
    machine.graphics_library = ": GLIB 42 ;\n";
    return machine;
}

test "a library of Forth only loads after the groups it needs and finds their words" {
    try skipWithout(&.{.graphics});
    var output = Output{};
    const machine = try machineWithSmallGraphics(&output);
    defer destroyMachine(machine);
    try library_loading.require(machine, test_group, ": TWICE-GLIB GLIB 2 * ;\n: WIDTH-OF GFX-WIDTH ;\n");
    try std.testing.expect(words_graphics.graphicsLoaded(machine));
    try std.testing.expect(library_loading.isLoaded(machine, test_group));
    // The search order is as it was: the words are in TESTLIB.
    try std.testing.expect(machine.lookup("TWICE-GLIB") == null);
    try std.testing.expect(machine.lookup("GLIB") == null);
    try machine.interpretLine("TESTLIB TWICE-GLIB FORTH");
    try expectStack(machine, &.{84});
    const word = machine.words[machine.lookupIn("TWICE-GLIB", machine.words[@intCast(machine.readCellConst(memory_map.gui_vocabulary_address))].value).?];
    try std.testing.expect(library_loading.isGroupWord(machine, word, test_group.library_name));

    // The second time nothing is added.
    const words = machine.word_count;
    try library_loading.require(machine, test_group, "NO-SUCH-WORD\n");
    try std.testing.expectEqual(words, machine.word_count);
}

test "a library of Forth only that fails is removed, and the groups it needs stay" {
    try skipWithout(&.{.graphics});
    var output = Output{};
    const machine = try machineWithSmallGraphics(&output);
    defer destroyMachine(machine);
    try std.testing.expectError(error.UnknownWord, library_loading.require(machine, test_group, ": GOOD 1 ;\nNO-SUCH-WORD\n"));
    try std.testing.expect(!library_loading.isLoaded(machine, test_group));
    try std.testing.expect(words_graphics.graphicsLoaded(machine));
    try std.testing.expect(machine.lookup("TESTLIB") == null);
    try library_loading.require(machine, test_group, ": GOOD 1 ;\n");
    try std.testing.expect(library_loading.isLoaded(machine, test_group));
}

test "FORGET removes a library of Forth only, and a vocabulary of the same name does not count" {
    try skipWithout(&.{.graphics});
    var output = Output{};
    const machine = try machineWithSmallGraphics(&output);
    defer destroyMachine(machine);
    try library_loading.require(machine, test_group, ": GOOD 1 ;\n");
    try machine.interpretLine("FORGET TESTLIB");
    try std.testing.expect(!library_loading.isLoaded(machine, test_group));
    // A vocabulary of the user at the same word number, followed by a word of the user.
    try machine.interpretLine("VOCABULARY TESTLIB : GOOD 2 ;");
    try std.testing.expect(!library_loading.isLoaded(machine, test_group));
    try library_loading.require(machine, test_group, ": GOOD 1 ;\n");
    try std.testing.expect(library_loading.isLoaded(machine, test_group));
}

test "an image keeps a library of Forth only loaded, also when appended" {
    try skipWithout(&.{ .graphics, .image });
    var output = Output{};
    const source = try machineWithSmallGraphics(&output);
    defer destroyMachine(source);
    try library_loading.require(source, test_group, ": GOOD 1 ;\n");
    const image = try std.testing.allocator.alloc(u8, source.encodedSize());
    defer std.testing.allocator.free(image);
    _ = try source.encodeImage(image);
    // Its format is that of the graphics words: the library has no built-in words.
    try std.testing.expectEqualStrings(memory_map.graphics_image_magic, image[0..8]);

    const restored = try createMachine(&output);
    defer destroyMachine(restored);
    try restored.restoreImage(image);
    try std.testing.expect(library_loading.isLoaded(restored, test_group));

    const target = try createMachine(&output);
    defer destroyMachine(target);
    try target.interpretLine(": FIRST 1 ; : SECOND 2 ;");
    const word_base = target.word_count;
    const was_loaded = library_loading.isLoaded(target, test_group);
    try target.appendImage(restored);
    try library_loading.appendLoaded(target, restored, test_group, was_loaded, word_base);
    try std.testing.expect(library_loading.isLoaded(target, test_group));
    try std.testing.expect(words_graphics.graphicsLoaded(target));
    try target.interpretLine("TESTLIB GOOD FORTH");
    try expectStack(target, &.{1});
}
