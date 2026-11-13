const std = @import("std");
const support = @import("support.zig");
const encoder = @import("../core/image_encoder.zig");
const append = @import("../core/image_append_plan.zig");
const registry = @import("../core/address_registry.zig");
const map = @import("../core/memory_map.zig");

test "append plan relocates data constant and heap owners without changing target" {
    var output = support.Output{};
    const source = try support.createMachine(&output);
    defer support.destroyMachine(source);
    try source.interpretLine("CREATE TARGET 8 ALLOT TARGET ACONSTANT PTR VARIABLE TEXT S\" kept\" TEXT $!");
    var workspace: encoder.Workspace = undefined;
    const bytes = try std.testing.allocator.alloc(u8, try encoder.measure(source, &workspace));
    defer std.testing.allocator.free(bytes);
    _ = try encoder.encode(source, bytes, &workspace);
    const target = try support.createMachine(&output);
    defer support.destroyMachine(target);
    try target.interpretLine("CREATE FILLER 32 ALLOT AVARIABLE OWN 77");
    _ = (try target.heapAllocate(64)).?;
    const top = target.heapTop();
    const here = target.data_here;
    const count = target.word_count;
    var plan: append.Plan = undefined;
    try append.prepare(target, bytes, &plan);
    try std.testing.expectEqual(here, plan.image.records[0].value);
    try std.testing.expectEqual(@as(map.Cell, @intCast(count + 1)), plan.image.records[0].slot);
    try std.testing.expectEqual(top + map.heap_header, plan.image.records[1].value);
    try std.testing.expectEqual(here + 8, plan.image.records[1].slot);
    try std.testing.expectEqual(top, target.heapTop());
    try std.testing.expectEqual(here, target.data_here);
    try std.testing.expectEqual(count, target.word_count);
    try support.expectStack(target, &.{77});
}

test "append rejects conflicting system registrations and exhausted heap before mutation" {
    var output = support.Output{};
    const source = try support.createMachine(&output);
    defer support.destroyMachine(source);
    try source.interpretLine("S\" Sunday\" $UNESCAPE 2DROP");
    var workspace: encoder.Workspace = undefined;
    const bytes = try std.testing.allocator.alloc(u8, try encoder.measure(source, &workspace));
    defer std.testing.allocator.free(bytes);
    _ = try encoder.encode(source, bytes, &workspace);
    const target = try support.createMachine(&output);
    defer support.destroyMachine(target);
    try target.interpretLine("S\" Monday\" $UNESCAPE 2DROP 77");
    const top = target.heapTop();
    const root = try target.readCell(map.tmp_string_base);
    const count = target.addresses.count;
    var plan: append.Plan = undefined;
    try std.testing.expectError(error.InvalidImage, append.prepare(target, bytes, &plan));
    try std.testing.expectEqual(root, try target.readCell(map.tmp_string_base));
    try std.testing.expectEqual(top, target.heapTop());
    try std.testing.expectEqual(count, target.addresses.count);
    try registry.validate(target);
    try support.expectStack(target, &.{77});
    // An independent target has no fixed-slot conflict, but has no tail capacity.
    const full = try support.createMachine(&output);
    defer support.destroyMachine(full);
    try full.writeCell(map.heap_top_address, full.sizes.heapEnd());
    try std.testing.expectError(error.MemoryExhausted, append.prepare(full, bytes, &plan));
    try std.testing.expectEqual(full.sizes.heapEnd(), full.heapTop());
}

test "append transforms validated words and operations while preserving raw literals" {
    const defs = @import("../core/defs.zig");
    var output = support.Output{};
    const source = try support.createMachine(&output);
    defer support.destroyMachine(source);
    try source.interpretLine("CREATE TARGET 8 ALLOT TARGET ACONSTANT PTR TARGET CONSTANT RAW : CALC 5 DUP * ; : RUN CALC IF S\" ok\" TYPE THEN ;");
    var workspace: encoder.Workspace = undefined;
    const bytes = try std.testing.allocator.alloc(u8, try encoder.measure(source, &workspace));
    defer std.testing.allocator.free(bytes);
    _ = try encoder.encode(source, bytes, &workspace);
    const target = try support.createMachine(&output);
    defer support.destroyMachine(target);
    try target.interpretLine("CREATE FILLER 32 ALLOT : BEFORE 99 ;");
    var plan: append.Plan = undefined;
    try append.prepare(target, bytes, &plan);
    const ptr = try append.relocatedWord(&plan, source.lookup("PTR").?);
    const raw = try append.relocatedWord(&plan, source.lookup("RAW").?);
    try std.testing.expectEqual(target.data_here, ptr.value);
    try std.testing.expectEqual(map.data_start, raw.value);
    const run_id = source.lookup("RUN").?;
    const run = try append.relocatedWord(&plan, run_id);
    try std.testing.expectEqual(source.words[run_id].code_start + plan.code_base, run.code_start);
    for (0..plan.image.view.header.code_count) |i| {
        const original = std.mem.bytesToValue(defs.Op, plan.image.view.code[i * @sizeOf(defs.Op) ..][0..@sizeOf(defs.Op)]);
        const relocated = try append.relocatedOperation(&plan, i);
        switch (original.kind) {
            .branch, .branch_zero => try std.testing.expectEqual(original.value + @as(map.Cell, @intCast(plan.code_base)), relocated.value),
            .print_string, .string_literal => try std.testing.expectEqual(original.value + plan.data_delta, relocated.value),
            .call => try std.testing.expectEqual(if (original.value < source.builtin_count) original.value else original.value + @as(map.Cell, @intCast(plan.word_base)) - source.builtin_count, relocated.value),
            .literal => try std.testing.expectEqual(original.value, relocated.value),
            else => {},
        }
    }
    try std.testing.expectError(error.InvalidImage, append.relocatedWord(&plan, 0));
    try std.testing.expectError(error.InvalidImage, append.relocatedOperation(&plan, plan.image.view.header.code_count));
}
