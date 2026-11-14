const std = @import("std");
const forth = @import("../forth.zig");
const support = @import("support.zig");
const map = @import("../core/memory_map.zig");
const registry = @import("../core/address_registry.zig");

test "P08b AVALUE explicitly tracks full-cell updates and rejects damaged address storage" {
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try m.interpretLine("CREATE BUFFER 16 ALLOT BUFFER AVALUE P 8 +TO P P BUFFER 8 + = 0 TO P P BUFFER ADDR P ! P BUFFER =");
    try support.expectStack(m, &.{ -1, 0, -1 });
    const slot = m.words[m.lookup("P").?].value;
    const r = registry.index(m, .memory, slot).?;
    try std.testing.expectEqual(registry.Status.valid, m.addresses.records[r].status);
    try m.interpretLine("1 ADDR P C!");
    try std.testing.expectEqual(registry.Status.damaged, m.addresses.records[r].status);
    try std.testing.expectError(error.InvalidAddress, m.encodedSize());
    try m.interpretLine("BUFFER TO P");
    try registry.validate(m);
}

test "P08b ADDR has distinct interpretation and compilation actions and stable local addresses" {
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try m.interpretLine("12 VALUE V ' ADDR CONSTANT AXT : M AXT EXECUTE ; IMMEDIATE : T M V LITERAL ; T @ : A POSTPONE ADDR ; IMMEDIATE : B A V ; B ADDR V = : L { x -- } ADDR x DUP @ SWAP 1 SWAP +! x ; 7 L");
    try support.expectStack(m, &.{ 12, -1, 7, 8 });
    try std.testing.expectError(error.InvalidDefinition, m.interpretLine(": BAD { W^ x -- } ADDR x ;"));
    m.report(error.InvalidDefinition);
    try m.interpretLine("9 ADDRESSABLE: VALUE W W");
    try std.testing.expectEqual(@as(map.Cell, 9), try m.pop());
}

test "P08b ADDR uses float double and XT local storage without outer-local capture" {
    try support.skipWithoutFloat();
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try m.interpretLine(": A 9 ; : D { D: x -- } ADDR x 2@ ; 1 2 D : F { F: x -- } ADDR x F@ ; 1.5e F : X { XT: x -- } ADDR x @ EXECUTE ; ' A X");
    try support.expectStack(m, &.{ 1, 2, 9 });
    try std.testing.expectEqual(@as(map.Float, 1.5), try m.fpop());
}

test "P08b colon IS commits only at semicolon and retains the previous action for DEFERS" {
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try m.interpretLine(": A 1 ; DEFER D ' A IS D :IS D [ D ] LITERAL DEFERS D + [: 7 ;] EXECUTE + ; D LATEST");
    try support.expectStack(m, &.{ 9, 0 });
    const action = try m.readCell(m.words[m.lookup("D").?].value);
    try std.testing.expectError(error.ControlMismatch, m.interpretLine(":IS D IF ;"));
    m.report(error.ControlMismatch);
    try std.testing.expect(m.colon_is_word == null);
    try std.testing.expectEqual(action, try m.readCell(m.words[m.lookup("D").?].value));
    m.data_depth = 0;
    try m.interpretLine(": START :IS ; START D 10 ; D");
    try support.expectStack(m, &.{10});
}

test "P08b active colon IS cannot be saved and malformed definitions cannot set its target" {
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try m.interpretLine("DEFER D :IS D");
    try std.testing.expectError(error.InvalidDefinition, m.encodedSize());
    m.report(error.InvalidDefinition);
    try std.testing.expect(m.colon_is_word == null);
    try std.testing.expectEqual(@as(map.Cell, -1), try m.readCell(m.words[m.lookup("D").?].value));
    try m.interpretLine(": A 1 ; ' A IS D : BAD S\" :IS D IF ;\" EVALUATE ; ' BAD CATCH D");
    try support.expectStack(m, &.{ -22, 1 });
}

test "P08b PRESERVE captures a compile-time action including the uninitialized sentinel" {
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try m.interpretLine(": A 1 ; : B 2 ; DEFER D ' A IS D : RESET PRESERVE D ; ' B IS D RESET D DEFER E : RESET-E PRESERVE E ; ' A IS E RESET-E ACTION-OF E");
    try support.expectStack(m, &.{ 1, -1 });
    try std.testing.expectError(error.CompileOnly, m.interpretLine("PRESERVE D"));
}

test "P08b WRAP XT restores dynamic actions after nested scopes rebinding and THROW" {
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try m.interpretLine(": A 1 ; : B 2 ; : C 3 ; DEFER D ' A IS D : INNER ['] C ['] D ['] D WRAP-XT D ; ' B ' D ' INNER WRAP-XT D : BAD D -123 THROW ; : R ['] B ['] D ['] BAD WRAP-XT ; ' R CATCH D");
    try support.expectStack(m, &.{ 3, 2, 1, -123, 1 });
    try std.testing.expect(m.wrap_guard == null);
    m.data_depth = 0;
    try m.interpretLine(": REBIND ['] C IS D ; ' B ' D ' REBIND WRAP-XT D");
    try support.expectStack(m, &.{1});
    m.data_depth = 0;
    try m.push(m.lookup("B").?);
    try m.push(m.lookup("A").?);
    try m.push(m.lookup("C").?);
    try std.testing.expectError(error.InvalidExecutionToken, m.executeBuiltin(.wrap_xt));
    try std.testing.expectEqual(@as(usize, 3), m.data_depth);
}

test "P08b WRAP XT invalidation cannot restore into a reused deferred word id" {
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try m.interpretLine(": A 1 ; : B 2 ; : REPLACE S\" FORGET D DEFER D ' B IS D\" EVALUATE ; : REPLACE-THROW REPLACE -123 THROW ; DEFER D ' A IS D");
    const old_id = m.lookup("D").?;
    try m.push(m.lookup("B").?);
    try m.push(old_id);
    try m.push(m.lookup("REPLACE").?);
    try std.testing.expectError(error.InvalidExecutionToken, m.executeBuiltin(.wrap_xt));
    try std.testing.expectEqual(old_id, m.lookup("D").?);
    try m.interpretLine("D");
    try support.expectStack(m, &.{2});
    try std.testing.expect(m.wrap_guard == null);
    m.data_depth = 0;
    try m.push(m.lookup("B").?);
    try m.push(m.lookup("D").?);
    try m.push(m.lookup("REPLACE-THROW").?);
    try std.testing.expectError(error.Thrown, m.executeBuiltin(.wrap_xt));
    try std.testing.expectEqual(@as(map.Cell, -123), m.throw_code);
    try m.interpretLine("D");
    try support.expectStack(m, &.{2});
    try std.testing.expect(m.wrap_guard == null);
}

test "P08b unrelated tail FORGET leaves the wrapped target valid" {
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try m.interpretLine(": A 1 ; : B 2 ; : DROP-TAIL S\" FORGET TAIL\" EVALUATE ; DEFER D ' A IS D : TAIL 9 ; ' B ' D ' DROP-TAIL WRAP-XT D");
    try support.expectStack(m, &.{1});
    try std.testing.expect(m.lookup("TAIL") == null);
}

const RestoreHost = struct {
    machine: *forth.State,
    image: []const u8,
    fn write(_: ?*anyopaque, _: []const u8) void {}
    fn run(context: ?*anyopaque, _: []const u8) forth.RuntimeError!map.Cell {
        const self: *@This() = @ptrCast(@alignCast(context.?));
        try self.machine.restoreImage(self.image);
        return 0;
    }
};

test "P08b successful restore invalidates wrappers while failed preflight preserves them" {
    var out = support.Output{};
    const source = try support.createMachine(&out);
    defer support.destroyMachine(source);
    try source.interpretLine(": A 1 ; : B 2 ; : C 3 ; DEFER D ' C IS D");
    const image = try std.testing.allocator.alloc(u8, try source.encodedSize());
    defer std.testing.allocator.free(image);
    _ = try source.encodeImage(image);
    for (0..2) |mode| {
        const m = try support.createMachine(&out);
        defer support.destroyMachine(m);
        try m.interpretLine(": A 1 ; : B 2 ; : C 3 ; DEFER D ' A IS D S\" restore\"");
        var host = RestoreHost{ .machine = m, .image = image };
        m.writer = .{ .context = &host, .write_fn = RestoreHost.write, .system_fn = RestoreHost.run };
        try m.push(m.lookup("B").?);
        try m.push(m.lookup("D").?);
        try m.push(m.builtinWord(.system));
        if (mode == 0) {
            try std.testing.expectError(error.InvalidExecutionToken, m.executeBuiltin(.wrap_xt));
        } else {
            image[0] = 'X';
            defer image[0] = 'S';
            try std.testing.expectError(error.InvalidImage, m.executeBuiltin(.wrap_xt));
            m.data_depth = 0;
        }
        try m.executeWord(m.lookup("D").?);
        try support.expectStack(m, &.{if (mode == 0) 3 else 1});
        try std.testing.expect(m.wrap_guard == null);
    }
}

test "P08b wrapper nesting is bounded and all deferred actions unwind on failure" {
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try m.interpretLine(": A 1 ; : B 2 ; DEFER D ' A IS D : R ['] B ['] D ['] R WRAP-XT ;");
    try std.testing.expectError(error.ReturnStackOverflow, m.executeWord(m.lookup("R").?));
    try std.testing.expect(m.wrap_guard == null);
    m.data_depth = 0;
    try m.interpretLine("D");
    try support.expectStack(m, &.{1});
}

test "P08b address values compiled ADDR and captured deferred actions survive all image routes" {
    var out = support.Output{};
    const source = try support.createMachine(&out);
    defer support.destroyMachine(source);
    try source.interpretLine("CREATE BUFFER 32 ALLOT BUFFER AVALUE P 8 +TO P 7 VALUE V : GET ADDR V ; : A 1 ; DEFER D ' A IS D : RESET PRESERVE D ; :IS D 2 ; :IS D [: 3 ;] EXECUTE ; : U RESET D ; DEFER E : RESET-E PRESERVE E ;");
    const image = try std.testing.allocator.alloc(u8, try source.encodedSize());
    defer std.testing.allocator.free(image);
    _ = try source.encodeImage(image);
    for (0..3) |mode| {
        const m = try support.createMachine(&out);
        defer support.destroyMachine(m);
        try m.interpretLine("CREATE BEFORE 24 ALLOT");
        switch (mode) {
            0 => try m.restoreImage(image),
            1 => try m.appendImage(source),
            else => {
                const append = @import("../core/image_append.zig");
                var work: append.Workspace = undefined;
                try append.append(m, image, &work);
            },
        }
        try m.interpretLine("P BUFFER 8 + = GET @ D U RESET-E ACTION-OF E");
        try support.expectStack(m, &.{ -1, 7, 3, 1, -1 });
        try registry.validate(m);
    }
}
