const std = @import("std");
const support = @import("support.zig");
const encoder = @import("../core/image_encoder.zig");
const append = @import("../core/image_append.zig");
const restore = @import("../core/image_restore.zig");
const preflight = @import("../core/image_restore_plan.zig");
const registry = @import("../core/address_registry.zig");

test "typed append twice retains independent strings and constants then resaves" {
    var output = support.Output{};
    const source = try support.createMachine(&output);
    defer support.destroyMachine(source);
    try source.interpretLine("VARIABLE TEXT S\" kept\" TEXT $! CREATE TARGET 8 ALLOT TARGET ACONSTANT PTR : CALC 5 DUP * ;");
    var encoding: encoder.Workspace = undefined;
    const bytes = try std.testing.allocator.alloc(u8, try encoder.measure(source, &encoding));
    defer std.testing.allocator.free(bytes);
    _ = try encoder.encode(source, bytes, &encoding);
    const target = try support.createMachine(&output);
    defer support.destroyMachine(target);
    try target.interpretLine("CREATE FILLER 32 ALLOT AVARIABLE OWN 77");
    var work: append.Workspace = undefined;
    try append.append(target, bytes, &work);
    const first = target.words[target.lookup("TEXT").?].value;
    const first_buffer = try target.readCell(first);
    try append.append(target, bytes, &work);
    const second = target.words[target.lookup("TEXT").?].value;
    try std.testing.expect(first != second);
    try std.testing.expect(first_buffer != try target.readCell(second));
    try registry.validate(target);
    output.len = 0;
    try target.interpretLine("TEXT $. PTR TARGET = CALC");
    try std.testing.expectEqualStrings("kept", output.written());
    try support.expectStack(target, &.{ 77, -1, 25 });
    const saved = try std.testing.allocator.alloc(u8, try encoder.measure(target, &encoding));
    defer std.testing.allocator.free(saved);
    _ = try encoder.encode(target, saved, &encoding);
    var plan: preflight.Plan = undefined;
    try restore.restore(target, saved, &plan);
    try registry.validate(target);
    output.len = 0;
    try target.interpretLine("TEXT $. PTR TARGET = CALC");
    try std.testing.expectEqualStrings("kept", output.written());
    try support.expectStack(target, &.{ -1, 25 });
}

test "typed append maps source locations and deferred actions and preserves failed target" {
    var output = support.Output{};
    const source = try support.createMachine(&output);
    defer support.destroyMachine(source);
    const file = try source.recordSourceFile("loaded.fs");
    try source.interpretLine(": ACTION 42 ; DEFER HOOK ' ACTION IS HOOK MARKER BACK");
    source.words[source.lookup("ACTION").?].source_file = file + 1;
    var encoding: encoder.Workspace = undefined;
    const bytes = try std.testing.allocator.alloc(u8, try encoder.measure(source, &encoding));
    defer std.testing.allocator.free(bytes);
    _ = try encoder.encode(source, bytes, &encoding);
    const target = try support.createMachine(&output);
    defer support.destroyMachine(target);
    _ = try target.recordSourceFile("own.fs");
    var work: append.Workspace = undefined;
    try append.append(target, bytes, &work);
    try std.testing.expectEqual(@as(u8, 2), target.words[target.lookup("ACTION").?].source_file);
    try target.interpretLine("HOOK BACK HOOK");
    try support.expectStack(target, &.{ 42, 42 });
    const count = target.word_count;
    bytes[bytes.len - 1] ^= 1;
    try std.testing.expectError(error.InvalidImage, append.append(target, bytes, &work));
    try std.testing.expectEqual(count, target.word_count);
    try support.expectStack(target, &.{ 42, 42 });
    try registry.validate(target);
}

test "typed append carries graphics library registration to its relocated vocabulary" {
    try support.skipWithout(&.{.graphics});
    const graphics = @import("../core/words_graphics.zig");
    var output = support.Output{};
    const source = try support.createMachine(&output);
    defer support.destroyMachine(source);
    try source.interpretLine("REQUIRE-GRAPHICS");
    var encoding: encoder.Workspace = undefined;
    const bytes = try std.testing.allocator.alloc(u8, try encoder.measure(source, &encoding));
    defer std.testing.allocator.free(bytes);
    _ = try encoder.encode(source, bytes, &encoding);
    const target = try support.createMachine(&output);
    defer support.destroyMachine(target);
    try target.interpretLine(": BEFORE 99 ;");
    var work: append.Workspace = undefined;
    try append.append(target, bytes, &work);
    try std.testing.expect(graphics.graphicsLoaded(target));
    const count = target.word_count;
    try target.interpretLine("REQUIRE-GRAPHICS");
    try std.testing.expectEqual(count, target.word_count);
    try registry.validate(target);
}
