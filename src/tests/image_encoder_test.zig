const std = @import("std");
const support = @import("support.zig");
const encoder = @import("../core/image_encoder.zig");
const format = @import("../core/image_format.zig");

test "State encoder produces structurally valid typed graphs and deterministic bytes" {
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try machine.interpretLine("VARIABLE TEXT S\" kept\" TEXT $! CREATE TARGET 8 ALLOT TARGET ACONSTANT PTR CREATE REF TARGET A, : SQUARE DUP * ; : RUN 5 SQUARE ; RUN DROP");
    var workspace: encoder.Workspace = undefined;
    const length = try encoder.measure(machine, &workspace);
    const bytes = try std.testing.allocator.alloc(u8, length * 2);
    defer std.testing.allocator.free(bytes);
    const before_code = try std.testing.allocator.dupe(u8, std.mem.sliceAsBytes(machine.code[0..machine.code_count]));
    defer std.testing.allocator.free(before_code);
    const here = machine.data_here;
    try std.testing.expectEqual(length, try encoder.encode(machine, bytes[0..length], &workspace));
    try std.testing.expectEqual(length, try encoder.encode(machine, bytes[length..], &workspace));
    try std.testing.expectEqualSlices(u8, bytes[0..length], bytes[length..]);
    var validation: format.Workspace = undefined;
    const view = try format.parse(bytes[0..length], &validation);
    try std.testing.expectEqual(machine.builtin_count, view.header.builtin_count);
    try std.testing.expectEqual(@as(u32, 1), view.header.object_count);
    try std.testing.expectEqual(@as(u32, 3), view.header.relocation_count);
    try std.testing.expectEqualSlices(u8, before_code, std.mem.sliceAsBytes(machine.code[0..machine.code_count]));
    try std.testing.expectEqual(here, machine.data_here);
}

test "State encoder leaves short output untouched and rejects damaged references" {
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try machine.interpretLine("CREATE TARGET 8 ALLOT CREATE REF TARGET A,");
    var workspace: encoder.Workspace = undefined;
    var bytes: [16]u8 = @splat(0xa5);
    const expected: [16]u8 = @splat(0xa5);
    try std.testing.expectError(error.InvalidImage, encoder.encode(machine, &bytes, &workspace));
    try std.testing.expectEqualSlices(u8, &expected, &bytes);
    try machine.interpretLine("0 REF C!");
    try std.testing.expectError(error.InvalidAddress, encoder.encode(machine, &bytes, &workspace));
    try std.testing.expectEqualSlices(u8, &expected, &bytes);
}

test "State encoder preserves shared cyclic heap records and excludes raw orphan blocks" {
    const registry = @import("../core/address_registry.zig");
    const map = @import("../core/memory_map.zig");
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try machine.interpretLine("AVARIABLE ROOT");
    const a = (try machine.heapAllocate(16)).?;
    const b = (try machine.heapAllocate(16)).?;
    _ = (try machine.heapAllocate(256)).?;
    try machine.writeCell(a, b + 1);
    try registry.registerMemory(machine, a);
    try machine.writeCell(b, a);
    try registry.registerMemory(machine, b);
    try machine.writeCell(machine.words[machine.lookup("ROOT").?].value, a);
    var workspace: encoder.Workspace = undefined;
    const length = try encoder.measure(machine, &workspace);
    const bytes = try std.testing.allocator.alloc(u8, length);
    defer std.testing.allocator.free(bytes);
    for ([_]format.FileKind{ .normal, .graphics, .audio }) |kind| {
        try machine.writeCell(map.graphics_image_address, if (kind == .graphics) 1 else 0);
        try machine.writeCell(map.audio_image_address, if (kind == .audio) 1 else 0);
        _ = try encoder.encode(machine, bytes, &workspace);
        var validation: format.Workspace = undefined;
        const view = try format.parse(bytes, &validation);
        try std.testing.expectEqual(kind, view.header.kind);
        try std.testing.expectEqual(@as(u32, 2), view.header.object_count);
        try std.testing.expectEqual(@as(u32, 3), view.header.relocation_count);
        try std.testing.expectEqual(@as(u64, 80), view.header.heap_bytes);
    }
}
