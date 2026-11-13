const std = @import("std");
const support = @import("support.zig");
const encoder = @import("../core/image_encoder.zig");
const restore = @import("../core/image_restore.zig");
const preflight = @import("../core/image_restore_plan.zig");
const registry = @import("../core/address_registry.zig");

test "typed restore runs strings arrays constants and code then resaves and restores again" {
    var output = support.Output{};
    const source = try support.createMachine(&output);
    defer support.destroyMachine(source);
    try source.interpretLine("VARIABLE TEXT S\" kept\" TEXT $! VARIABLE ARRAY S\" one\" 0 ARRAY $[]! CREATE DATA 8 ALLOT DATA ACONSTANT PTR : RUN 5 DUP * ;");
    var workspace: encoder.Workspace = undefined;
    const bytes = try std.testing.allocator.alloc(u8, try encoder.measure(source, &workspace));
    defer std.testing.allocator.free(bytes);
    _ = try encoder.encode(source, bytes, &workspace);
    const target = try support.createMachine(&output);
    defer support.destroyMachine(target);
    try target.interpretLine("VARIABLE OLD S\" discarded\" OLD $!");
    var plan: preflight.Plan = undefined;
    try restore.restore(target, bytes, &plan);
    try registry.validate(target);
    try std.testing.expect(target.lookup("OLD") == null);
    output.len = 0;
    try target.interpretLine("TEXT $. 0 ARRAY $[]@ TYPE PTR DATA = RUN");
    try std.testing.expectEqualStrings("keptone", output.written());
    try support.expectStack(target, &.{ -1, 25 });
    try target.interpretLine("S\" !\" TEXT $+!");
    const second = try std.testing.allocator.alloc(u8, try encoder.measure(target, &workspace));
    defer std.testing.allocator.free(second);
    _ = try encoder.encode(target, second, &workspace);
    try restore.restore(target, second, &plan);
    try registry.validate(target);
    output.len = 0;
    try target.interpretLine("TEXT $.");
    try std.testing.expectEqualStrings("kept!", output.written());
}

test "typed restore keeps cyclic interior pointers and failed restore keeps target" {
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try machine.interpretLine("AVARIABLE ROOT 77");
    _ = (try machine.heapAllocate(128)).?;
    const a = (try machine.heapAllocate(16)).?;
    const b = (try machine.heapAllocate(16)).?;
    try machine.writeCell(a, b + 3);
    try registry.registerMemory(machine, a);
    try machine.writeCell(b, a);
    try registry.registerMemory(machine, b);
    const root = machine.words[machine.lookup("ROOT").?].value;
    try machine.writeCell(root, a);
    var workspace: encoder.Workspace = undefined;
    const bytes = try std.testing.allocator.alloc(u8, try encoder.measure(machine, &workspace));
    defer std.testing.allocator.free(bytes);
    _ = try encoder.encode(machine, bytes, &workspace);
    var plan: preflight.Plan = undefined;
    bytes[bytes.len - 1] ^= 1;
    try std.testing.expectError(error.InvalidImage, restore.restore(machine, bytes, &plan));
    try support.expectStack(machine, &.{77});
    try std.testing.expectEqual(a, try machine.readCell(root));
    try registry.validate(machine);
    bytes[bytes.len - 1] ^= 1;
    try restore.restore(machine, bytes, &plan);
    try registry.validate(machine);
    const moved = try machine.readCell(root);
    try std.testing.expect(moved != a);
    const interior = try machine.readCell(moved);
    try std.testing.expectEqual(moved, try machine.readCell(interior - 3));
    try std.testing.expectEqual(@as(usize, 0), machine.data_depth);
}

test "typed restore retains system-rooted replacement lists and runtime block buffers" {
    const map = @import("../core/memory_map.zig");
    var output = support.Output{};
    const source = try support.createMachine(&output);
    defer support.destroyMachine(source);
    try source.interpretLine("S\" Sunday\" S\" day\" REPLACES S\" a%b\" $UNESCAPE 2DROP");
    var workspace: encoder.Workspace = undefined;
    const bytes = try std.testing.allocator.alloc(u8, try encoder.measure(source, &workspace));
    defer std.testing.allocator.free(bytes);
    _ = try encoder.encode(source, bytes, &workspace);
    const target = try support.createMachine(&output);
    defer support.destroyMachine(target);
    target.memory[@intCast(map.block_buffer_base)] = 0x71;
    target.memory[@intCast(map.block_buffer_end - 1)] = 0x72;
    var plan: preflight.Plan = undefined;
    try restore.restore(target, bytes, &plan);
    try registry.validate(target);
    try std.testing.expectEqual(@as(u8, 0x71), target.memory[@intCast(map.block_buffer_base)]);
    try std.testing.expectEqual(@as(u8, 0x72), target.memory[@intCast(map.block_buffer_end - 1)]);
    output.len = 0;
    try target.interpretLine("S\" %day%\" PAD 80 SUBSTITUTE DROP TYPE");
    try std.testing.expectEqualStrings("Sunday", output.written());
    try registry.validate(target);
}
