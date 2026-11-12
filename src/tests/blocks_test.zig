//! Standard block storage tests using the existing fake file host.
const std = @import("std");
const forth = @import("../forth.zig");
const support = @import("support.zig");
const blocks = @import("../core/blocks.zig");
fn open(context: ?*anyopaque, name: []const u8, access: forth.FileAccess, create: bool) forth.FileResult {
    return support.fakeOpen(context, if (std.mem.eql(u8, name, blocks.default_file)) "a.txt" else name, access, create);
}
fn read(context: ?*anyopaque, fileid: forth.Cell, buffer: []u8) forth.FileResult {
    const file = support.fakeFile(context, fileid) orelse return .{ .ior = forth.errnoIor(forth.errno_bad_file) };
    if (file.position >= file.len) return .{ .value = 0 };
    return support.fakeRead(context, fileid, buffer);
}
const ops = blk: {
    var value = support.fake_file_ops;
    value.open = open;
    value.read = read;
    break :blk value;
};

test "BLOCK and BUFFER read contents and pad short blocks with spaces" {
    try support.skipWithout(&.{.files});
    var output = support.Output{};
    support.setFakeFile(&output, 0, "ABC");
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    machine.writer.file_ops = &ops;
    try machine.interpretLine("0 BLOCK DUP C@ SWAP 3 + C@ 0 BUFFER 0 BLOCK =");
    try support.expectStack(machine, &.{ 'A', ' ', -1 });
    try std.testing.expectEqual(@as(usize, 3), output.files[0].len);
}

test "UPDATE saves only modified blocks and EMPTY-BUFFERS discards changes" {
    try support.skipWithout(&.{.files});
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    machine.writer.file_ops = &ops;
    try machine.interpretLine("1 BLOCK 65 SWAP C! UPDATE SAVE-BUFFERS EMPTY-BUFFERS 1 BLOCK C@ 1 BLOCK 66 SWAP C! EMPTY-BUFFERS 1 BLOCK C@ FLUSH 1 BLOCK C@");
    try support.expectStack(machine, &.{ 65, 65, 65 });
    try std.testing.expectEqual(@as(usize, 1), output.file_writes);
    try std.testing.expectEqual(@as(usize, 2048), output.files[0].len);
}

test "colliding buffer saves old contents and write failures remain retryable" {
    try support.skipWithout(&.{.files});
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    machine.writer.file_ops = &ops;
    try machine.interpretLine("1 BLOCK 81 SWAP C! UPDATE");
    output.write_fails_at = 1;
    try std.testing.expectError(error.Thrown, machine.interpretLine("33 BLOCK"));
    try std.testing.expect(machine.block_storage.buffers[1].modified);
    try std.testing.expectEqual(@as(?u32, 1), machine.block_storage.buffers[1].number);
    output.write_fails_at = 0;
    machine.data_depth = 0;
    try machine.interpretLine("33 BLOCK DROP 1 BLOCK C@");
    try support.expectStack(machine, &.{81});
}

test "invalid block numbers throw minus 35 without opening storage" {
    try support.skipWithout(&.{.files});
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    machine.writer.file_ops = &ops;
    try machine.interpretLine(": BAD -1 BLOCK ; ' BAD CATCH : LARGE $200000 BUFFER ; ' LARGE CATCH");
    try support.expectStack(machine, &.{ -35, -35 });
    try std.testing.expect(machine.block_storage.file == null);
}

test "failed open never creates over an existing file" {
    try support.skipWithout(&.{.files});
    const Denied = struct {
        fn openFile(context: ?*anyopaque, _: []const u8, _: forth.FileAccess, create: bool) forth.FileResult {
            const output = support.fakeOutput(context);
            if (create) output.file_writes += 1;
            return .{ .ior = forth.errnoIor(13) };
        }
    };
    var denied_ops = ops;
    denied_ops.open = Denied.openFile;
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    machine.writer.file_ops = &denied_ops;
    try std.testing.expectError(error.Thrown, machine.interpretLine("1 BLOCK"));
    try std.testing.expectEqual(@as(usize, 0), output.file_writes);
    try std.testing.expect(machine.block_storage.file == null);
}

test "failed read keeps the previous buffer contents and identity" {
    try support.skipWithout(&.{.files});
    const Failing = struct {
        fn readFile(_: ?*anyopaque, _: forth.Cell, _: []u8) forth.FileResult {
            return .{ .ior = forth.errnoIor(5) };
        }
    };
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    machine.writer.file_ops = &ops;
    const address = try blocks.get(machine, 1);
    machine.memory[@intCast(address)] = 82;
    var failing_ops = ops;
    failing_ops.read = Failing.readFile;
    machine.writer.file_ops = &failing_ops;
    try std.testing.expectError(error.Thrown, blocks.get(machine, 33));
    try std.testing.expectEqual(@as(?u32, 1), machine.block_storage.buffers[1].number);
    try std.testing.expectEqual(@as(u8, 82), machine.memory[@intCast(address)]);
}

test "failed flush retains dirty buffers and FLUSH does not empty them" {
    try support.skipWithout(&.{.files});
    const Failing = struct {
        fn flushFile(_: ?*anyopaque, _: forth.Cell) forth.Cell {
            return forth.errnoIor(5);
        }
    };
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    machine.writer.file_ops = &ops;
    try machine.interpretLine("1 BLOCK DROP UPDATE");
    var failing_ops = ops;
    failing_ops.flush = Failing.flushFile;
    machine.writer.file_ops = &failing_ops;
    try std.testing.expectError(error.Thrown, machine.interpretLine("FLUSH"));
    try std.testing.expect(machine.block_storage.buffers[1].modified);
    try std.testing.expectEqual(@as(?u32, 1), machine.block_storage.buffers[1].number);
    machine.writer.file_ops = &ops;
    try machine.interpretLine("FLUSH");
    try std.testing.expect(machine.block_storage.buffers[1].number == null);
}

test "dictionary restore preserves this process's unsaved runtime block buffer" {
    try support.skipWithout(&.{ .files, .image });
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    machine.writer.file_ops = &ops;
    try machine.interpretLine("1 BLOCK 83 SWAP C! UPDATE");
    const image = try std.testing.allocator.alloc(u8, machine.encodedSize());
    defer std.testing.allocator.free(image);
    _ = try machine.encodeImage(image);
    try machine.restoreImage(image);
    try machine.interpretLine("1 BLOCK C@");
    try support.expectStack(machine, &.{83});
    try std.testing.expect(machine.block_storage.buffers[1].modified);
    try std.testing.expectEqual(@as(usize, 0), output.file_writes);
}

fn setBlock(output: *support.Output, block: usize, source: []const u8) void {
    const start = block * blocks.block_size;
    const file = &output.files[0];
    @memset(file.data[file.len..@max(file.len, start + blocks.block_size)], ' ');
    @memcpy(file.data[start..][0..source.len], source);
    file.len = @max(file.len, start + blocks.block_size);
    file.exists = true;
}

test "LOAD exposes block input and restores the caller after success or THROW" {
    try support.skipWithout(&.{.files});
    var output = support.Output{};
    setBlock(&output, 1, "BLK @ SOURCE-ID SOURCE NIP");
    setBlock(&output, 2, "-99 THROW");
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    machine.writer.file_ops = &ops;
    try machine.interpretLine("1 LOAD BLK @ : BAD 2 LOAD ; ' BAD CATCH BLK @ 42");
    try support.expectStack(machine, &.{ 1, 2, 1024, 0, -99, 0, 42 });
    try std.testing.expectEqual(@as(usize, 0), machine.block_depth);
}

test "nested LOAD and colliding BLOCK cannot overwrite the active source" {
    try support.skipWithout(&.{.files});
    var output = support.Output{};
    setBlock(&output, 1, "33 BLOCK DROP 2 LOAD 11");
    setBlock(&output, 2, "22");
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    machine.writer.file_ops = &ops;
    try machine.interpretLine("1 LOAD 1 2 THRU");
    try support.expectStack(machine, &.{ 22, 11, 22, 11, 22 });
}

test "block comments stop at 64 characters and EVALUATE temporarily clears BLK" {
    try support.skipWithout(&.{.files});
    var output = support.Output{};
    var source: [128]u8 = @splat(' ');
    const comment = "7 \\ ignored 999";
    @memcpy(source[0..comment.len], comment);
    const code = "8 S\" BLK @ SOURCE-ID\" EVALUATE BLK @";
    @memcpy(source[64..][0..code.len], code);
    setBlock(&output, 1, &source);
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    machine.writer.file_ops = &ops;
    try machine.interpretLine("1 LOAD");
    try support.expectStack(machine, &.{ 7, 8, 0, -1, 1 });
}

test "block REFILL and SAVE-INPUT RESTORE-INPUT restore block and cursor" {
    try support.skipWithout(&.{.files});
    var output = support.Output{};
    setBlock(&output, 1, "R 11 BLK @");
    setBlock(&output, 2, "22");
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    machine.writer.file_ops = &ops;
    try machine.interpretLine(": R SAVE-INPUT REFILL DROP RESTORE-INPUT ; 1 LOAD");
    try support.expectStack(machine, &.{ 0, 11, 1 });
    machine.data_depth = 0;
    try machine.interpretLine(": R REFILL DROP ; 1 LOAD");
    try support.expectStack(machine, &.{22});
}

test "LIST displays sixteen lines and sets SCR; LOAD zero throws minus 35" {
    try support.skipWithout(&.{.files});
    var output = support.Output{};
    setBlock(&output, 1, "hello");
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    machine.writer.file_ops = &ops;
    try machine.interpretLine("1 LIST SCR @ BLK @ 0 ' LOAD CATCH");
    try support.expectStack(machine, &.{ 1, 0, 0, -35 });
    try std.testing.expect(std.mem.startsWith(u8, output.written(), "Screen 1 not modified     \n 0 hello"));
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "\n15 ") != null);
}

test "a BLK store changes SOURCE while keeping the current input cursor" {
    try support.skipWithout(&.{.files});
    var output = support.Output{};
    setBlock(&output, 1, "2 BLK ! 999");
    setBlock(&output, 2, "        22");
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    machine.writer.file_ops = &ops;
    try machine.interpretLine("1 LOAD");
    try support.expectStack(machine, &.{22});
}

test "recursive LOAD and failed REFILL restore all input frames" {
    try support.skipWithout(&.{.files});
    var output = support.Output{};
    setBlock(&output, 1, "1 LOAD");
    setBlock(&output, 2, "BAD-R");
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    machine.writer.file_ops = &ops;
    try machine.interpretLine(": BAD-R $1fffff BLK ! REFILL ; : RECURSE-BLOCK 1 LOAD ; ' RECURSE-BLOCK CATCH BLK @ : BAD-REFILL 2 LOAD ; ' BAD-REFILL CATCH BLK @");
    try std.testing.expectEqual(@as(usize, 0), machine.block_depth);
    try support.expectStack(machine, &.{ machine.throwCodeOf(error.IncludeNesting), 0, -35, 0 });
}

test "BYE saves dirty blocks and a failed write can be caught before halting" {
    try support.skipWithout(&.{.files});
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    machine.writer.file_ops = &ops;
    try machine.interpretLine("1 BLOCK 84 SWAP C! UPDATE");
    output.write_fails_at = 1;
    try machine.interpretLine("' BYE CATCH");
    try std.testing.expect(!machine.halted);
    try std.testing.expect(machine.block_storage.buffers[1].modified);
    try support.expectStack(machine, &.{forth.errnoIor(28)});
    output.write_fails_at = 0;
    try machine.interpretLine("BYE");
    try std.testing.expect(machine.halted);
    try std.testing.expectEqual(@as(u8, 84), output.files[0].data[1024]);
    try std.testing.expect(!machine.block_storage.buffers[1].modified);
}

test "a block ending while a defining word waits for a name cannot consume caller input" {
    try support.skipWithout(&.{.files});
    var output = support.Output{};
    setBlock(&output, 1, "VARIABLE");
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    machine.writer.file_ops = &ops;
    try machine.interpretLine(": BAD 1 LOAD ; ' BAD CATCH 77");
    try support.expectStack(machine, &.{ machine.throwCodeOf(error.InvalidDefinition), 77 });
    try std.testing.expectEqual(@as(forth.Cell, 0), machine.readCellConst(@import("../core/memory_map.zig").blk_address));
}

test "read-only block files can be loaded but dirty writeback fails without losing data" {
    try support.skipWithout(&.{.files});
    const ReadOnly = struct {
        fn openFile(context: ?*anyopaque, name: []const u8, access: forth.FileAccess, create: bool) forth.FileResult {
            if (access != .read_only or create) return .{ .ior = forth.errnoIor(13) };
            return open(context, name, access, false);
        }
    };
    var readonly_ops = ops;
    readonly_ops.open = ReadOnly.openFile;
    var output = support.Output{};
    setBlock(&output, 1, "42");
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    machine.writer.file_ops = &readonly_ops;
    try machine.interpretLine("1 LOAD 1 BLOCK 65 SWAP C! UPDATE ' SAVE-BUFFERS CATCH");
    try support.expectStack(machine, &.{ 42, forth.errnoIor(13) });
    try std.testing.expect(machine.block_storage.buffers[1].modified);
    try std.testing.expectEqual(@as(usize, 0), output.file_writes);
}

test "block parser clamps an out-of-range input cursor before WORD" {
    try support.skipWithout(&.{.files});
    var output = support.Output{};
    setBlock(&output, 1, "PROBE");
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    machine.writer.file_ops = &ops;
    try machine.interpretLine(": PROBE 2000 >IN ! BL WORD COUNT NIP ; 1 LOAD");
    try support.expectStack(machine, &.{0});
}

test "BLK may select block zero inside LOAD while LOAD zero remains invalid" {
    try support.skipWithout(&.{.files});
    var output = support.Output{};
    setBlock(&output, 0, "        55");
    setBlock(&output, 1, "0 BLK ! 99");
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    machine.writer.file_ops = &ops;
    try machine.interpretLine("1 LOAD BLK @ 0 ' LOAD CATCH");
    try support.expectStack(machine, &.{ 55, 0, 0, -35 });
}

test "unrelated block open failures do not attempt read-only fallback" {
    try support.skipWithout(&.{.files});
    const Failing = struct {
        fn openFile(context: ?*anyopaque, _: []const u8, access: forth.FileAccess, _: bool) forth.FileResult {
            if (access == .read_only) support.fakeOutput(context).file_writes += 1;
            return .{ .ior = forth.errnoIor(24) };
        }
    };
    var failing_ops = ops;
    failing_ops.open = Failing.openFile;
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    machine.writer.file_ops = &failing_ops;
    try machine.interpretLine(": BAD 1 BLOCK DROP ; ' BAD CATCH");
    try support.expectStack(machine, &.{forth.errnoIor(24)});
    try std.testing.expectEqual(@as(usize, 0), output.file_writes);
}
