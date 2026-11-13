const std = @import("std");
const support = @import("support.zig");
const encoder = @import("../core/image_encoder.zig");
const restore = @import("../core/image_restore_plan.zig");
const registry = @import("../core/address_registry.zig");
const format = @import("../core/image_format.zig");

test "restore plan compacts heap and relocates source cells and interior cyclic targets" {
    var output = support.Output{};
    const source = try support.createMachine(&output);
    defer support.destroyMachine(source);
    _ = (try source.heapAllocate(128)).?; // Unrooted prefix must disappear.
    const a = (try source.heapAllocate(16)).?;
    const b = (try source.heapAllocate(16)).?;
    try source.writeCell(a, b + 3);
    try registry.registerMemory(source, a);
    try source.writeCell(b, a);
    try registry.registerMemory(source, b);
    try source.interpretLine("AVARIABLE ROOT");
    const root = source.words[source.lookup("ROOT").?].value;
    try source.writeCell(root, a);
    var workspace: encoder.Workspace = undefined;
    const bytes = try std.testing.allocator.alloc(u8, try encoder.measure(source, &workspace));
    defer std.testing.allocator.free(bytes);
    _ = try encoder.encode(source, bytes, &workspace);
    const target = try support.createMachine(&output);
    defer support.destroyMachine(target);
    try target.interpretLine("123 CONSTANT KEEP 77");
    const count = target.word_count;
    const here = target.data_here;
    var plan: restore.Plan = undefined;
    try restore.prepare(target, bytes, &plan);
    const base = target.sizes.heapBase();
    try std.testing.expectEqual(base + 16, plan.object_addresses[0]);
    try std.testing.expectEqual(base + 48, plan.object_addresses[1]);
    try std.testing.expectEqual(base + 64, plan.heap_top);
    try std.testing.expectEqual(base + 16, plan.records[0].value);
    try std.testing.expectEqual(base + 16, plan.records[1].slot);
    try std.testing.expectEqual(base + 51, plan.records[1].value);
    try std.testing.expectEqual(base + 48, plan.records[2].slot);
    try std.testing.expectEqual(base + 16, plan.records[2].value);
    try std.testing.expectEqual(count, target.word_count);
    try std.testing.expectEqual(here, target.data_here);
    try support.expectStack(target, &.{77});
}

test "restore preflight rejects builtin mismatch CRC and capacity without touching target" {
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try machine.interpretLine("123 CONSTANT KEEP 77");
    var workspace: encoder.Workspace = undefined;
    const bytes = try std.testing.allocator.alloc(u8, try encoder.measure(machine, &workspace));
    defer std.testing.allocator.free(bytes);
    _ = try encoder.encode(machine, bytes, &workspace);
    const count = machine.word_count;
    var plan: restore.Plan = undefined;
    bytes[96] ^= 1;
    try format.finish(bytes);
    try std.testing.expectError(error.InvalidImage, restore.prepare(machine, bytes, &plan));
    bytes[96] ^= 1;
    try format.finish(bytes);
    bytes[bytes.len - 1] ^= 1;
    try std.testing.expectError(error.InvalidImage, restore.prepare(machine, bytes, &plan));
    bytes[bytes.len - 1] ^= 1;
    const last = machine.builtin_count - 1;
    const original = machine.words[last].name_start;
    machine.words[last].name_start = @intCast(machine.names.len);
    defer machine.words[last].name_start = original;
    try std.testing.expectError(error.DictionaryFull, restore.prepare(machine, bytes, &plan));
    try std.testing.expectEqual(count, machine.word_count);
    try support.expectStack(machine, &.{77});
}
