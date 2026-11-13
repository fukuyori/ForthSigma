const std = @import("std");
const support = @import("support.zig");
const values = @import("../core/string_values.zig");
const registry = @import("../core/address_registry.zig");

test "P04b string values replace append and self-reference in interpreted and compiled code" {
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try machine.interpretLine("S\" ab\" $VALUE TEXT TEXT TYPE S\" cd\" TO TEXT S\" e\" +TO TEXT TEXT TYPE : SET-TEXT S\" ij\" TO TEXT ; : ADD-TEXT S\" k\" +TO TEXT ; SET-TEXT ADD-TEXT TEXT TYPE TEXT TO TEXT TEXT +TO TEXT TEXT TYPE");
    try std.testing.expectEqualStrings("abcdeijkijkijk", output.written());
    try registry.validate(machine);
}

test "P04b MACRO is a value alias and supports multiline compiled defining words" {
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try machine.interpretLine(": MAKE $VALUE ; S\" one\" MAKE FIRST S\" two\" MACRO:");
    try machine.interpretLine("SECOND FIRST TYPE SECOND TYPE ' SECOND >BODY @ 0<>");
    try std.testing.expectEqualStrings("onetwo", output.written());
    try support.expectStack(machine, &.{-1});
    try registry.validate(machine);
}

test "P04b failed replacement and append preserve string owner and input" {
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try machine.interpretLine("S\" kept\" $VALUE TEXT CREATE SRC 128 ALLOT");
    const id = machine.lookup("TEXT").?;
    const owner = machine.words[id].value;
    const pointer = try machine.readCell(owner);
    const remainder: u64 = @intCast(machine.sizes.heapEnd() - machine.heapTop() - 16);
    _ = (try machine.heapAllocate(remainder)).?;
    const top = machine.heapTop();
    const source = machine.words[machine.lookup("SRC").?].value;
    try machine.push(source);
    try machine.push(128);
    try std.testing.expectError(error.Thrown, values.store(machine, id, false));
    try support.expectStack(machine, &.{ source, 128 });
    try std.testing.expectError(error.Thrown, values.store(machine, id, true));
    try support.expectStack(machine, &.{ source, 128 });
    try std.testing.expectEqual(pointer, try machine.readCell(owner));
    try std.testing.expectEqual(top, machine.heapTop());
    const text = try machine.fetchString(owner);
    try std.testing.expectEqualStrings("kept", machine.memory[@intCast(text.address)..][0..text.length]);
    try registry.validate(machine);
}

test "P04b failed creation restores dictionary HERE names and lookup index" {
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try machine.interpretLine(": KEEP 77 ;");
    _ = (try machine.heapAllocate(@intCast(machine.sizes.heapEnd() - machine.heapTop() - 16))).?;
    const words = machine.word_count;
    const names = machine.names_used;
    const here = machine.data_here;
    try std.testing.expectError(error.Thrown, values.define(machine, "FAILED", 0, 0));
    try std.testing.expectEqual(words, machine.word_count);
    try std.testing.expectEqual(names, machine.names_used);
    try std.testing.expectEqual(here, machine.data_here);
    try std.testing.expect(machine.lookup("FAILED") == null);
    try machine.interpretLine("KEEP");
    try support.expectStack(machine, &.{77});
    try registry.validate(machine);
}

test "P04b value execution checks output room and setters check input ranges" {
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try machine.interpretLine("S\" kept\" $VALUE TEXT");
    const id = machine.lookup("TEXT").?;
    try machine.push(-1);
    try machine.push(1);
    try std.testing.expectError(error.InvalidAddress, values.store(machine, id, false));
    try support.expectStack(machine, &.{ -1, 1 });
    machine.data_depth = machine.data_stack.len - 1;
    try std.testing.expectError(error.StackOverflow, machine.executeWord(id));
    try std.testing.expectEqual(machine.data_stack.len - 1, machine.data_depth);
}

test "P04b string values and compiled TO plus TO survive repeated append and restore" {
    var output = support.Output{};
    const source = try support.createMachine(&output);
    defer support.destroyMachine(source);
    try source.interpretLine("S\" copy\" $VALUE TEXT : SET-TEXT S\" new\" TO TEXT ; : ADD-TEXT S\" !\" +TO TEXT ;");
    const target = try support.createMachine(&output);
    defer support.destroyMachine(target);
    try target.interpretLine("CREATE FILLER 31 ALLOT : BEFORE 9 ;");
    try target.appendImage(source);
    const first_owner = target.words[target.lookup("TEXT").?].value;
    try target.appendImage(source);
    const second_owner = target.words[target.lookup("TEXT").?].value;
    try std.testing.expect(first_owner != second_owner);
    try target.interpretLine("SET-TEXT ADD-TEXT");
    const first = try target.fetchString(first_owner);
    try std.testing.expectEqualStrings("copy", target.memory[@intCast(first.address)..][0..first.length]);
    const second = try target.fetchString(second_owner);
    try std.testing.expectEqualStrings("new!", target.memory[@intCast(second.address)..][0..second.length]);
    const bytes = try std.testing.allocator.alloc(u8, try target.encodedSize());
    defer std.testing.allocator.free(bytes);
    const length = try target.encodeImage(bytes);
    try target.restoreImage(bytes[0..length]);
    try registry.validate(target);
    output.len = 0;
    try target.interpretLine("TEXT TYPE SET-TEXT ADD-TEXT TEXT TYPE");
    try std.testing.expectEqualStrings("new!new!", output.written());
}

test "P04b explicit aliases to a replaced borrowed string become invalid" {
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try machine.interpretLine("S\" old\" $VALUE TEXT TEXT DROP ACONSTANT OLD-TEXT S\" new\" TO TEXT");
    try std.testing.expectError(error.InvalidAddress, registry.validate(machine));
}

test "P04b MARKER removes string value dictionary storage and its persistence root" {
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try machine.interpretLine("MARKER BACK S\" transient\" $VALUE TEXT");
    const owner = machine.words[machine.lookup("TEXT").?].value;
    try std.testing.expect(registry.index(machine, .memory, owner) != null);
    try machine.interpretLine("BACK");
    try std.testing.expect(machine.lookup("TEXT") == null);
    try std.testing.expect(registry.index(machine, .memory, owner) == null);
    try registry.validate(machine);
    var graph: @import("../core/image_graph.zig").Graph = undefined;
    try @import("../core/image_graph.zig").collect(machine, &graph);
    try std.testing.expectEqual(@as(usize, 0), graph.object_count);
}

test "P04b images reject missing owner types and invalid string headers before restore" {
    const format = @import("../core/image_format.zig");
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    try machine.interpretLine("S\" kept\" $VALUE TEXT");
    const bytes = try std.testing.allocator.alloc(u8, try machine.encodedSize());
    defer std.testing.allocator.free(bytes);
    _ = try machine.encodeImage(bytes);
    var validation: format.Workspace = undefined;
    const view = try format.parse(bytes, &validation);
    const reloc_at: usize = @intCast(format.header_size + view.header.word_bytes + view.header.code_bytes + view.header.name_bytes + view.header.memory_bytes);
    const shortened = try std.testing.allocator.alloc(u8, reloc_at + 4);
    defer std.testing.allocator.free(shortened);
    @memcpy(shortened[0..reloc_at], bytes[0..reloc_at]);
    std.mem.writeInt(u32, shortened[40..44], 0, .little);
    std.mem.writeInt(u32, shortened[44..48], 0, .little);
    std.mem.writeInt(u64, shortened[80..88], 0, .little);
    std.mem.writeInt(u64, shortened[88..96], 0, .little);
    try format.finish(shortened);
    const count = machine.word_count;
    try std.testing.expectError(error.InvalidImage, machine.restoreImage(shortened));
    try std.testing.expectEqual(count, machine.word_count);
    const heap_at = reloc_at + format.record_size;
    std.mem.writeInt(u64, bytes[heap_at + format.object_header_size ..][0..8], std.math.maxInt(u64), .little);
    try format.finish(bytes);
    try std.testing.expectError(error.InvalidImage, machine.restoreImage(bytes));
    try std.testing.expectEqual(count, machine.word_count);
    try machine.interpretLine("' TEXT >BODY $FREE TEXT OR");
    try support.expectStack(machine, &.{0});
    const empty = try std.testing.allocator.alloc(u8, try machine.encodedSize());
    defer std.testing.allocator.free(empty);
    _ = try machine.encodeImage(empty);
    try machine.restoreImage(empty);
    try registry.validate(machine);
}
