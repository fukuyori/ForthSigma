const std = @import("std");
const forth = @import("../forth.zig");
const map = @import("../core/memory_map.zig");
const support = @import("support.zig");

const RestoreHost = struct {
    state: *forth.State,
    image: []const u8,
    fn write(_: ?*anyopaque, _: []const u8) void {}
    fn run(context: ?*anyopaque, _: []const u8) forth.RuntimeError!map.Cell {
        const self: *@This() = @ptrCast(@alignCast(context.?));
        try self.state.restoreImage(self.image);
        return 0;
    }
};

test "P08 review one-shot CURRENT cannot overwrite a restored dictionary context" {
    var out = support.Output{};
    const source = try support.createMachine(&out);
    defer support.destroyMachine(source);
    try source.interpretLine("CS-WORDLIST DROP : KEEP 42 ;");
    const image = try std.testing.allocator.alloc(u8, try source.encodedSize());
    defer std.testing.allocator.free(image);
    _ = try source.encodeImage(image);
    for (0..2) |mode| {
        const m = try support.createMachine(&out);
        defer support.destroyMachine(m);
        try m.interpretLine("WORDLIST CONSTANT OLD OLD CURRENT ! S\" restore\"");
        var host = RestoreHost{ .state = m, .image = image };
        m.writer = .{ .context = &host, .write_fn = RestoreHost.write, .system_fn = RestoreHost.run };
        m.source_line = "SYSTEM";
        m.source_kind = .evaluate;
        m.setSourceCursor(0);
        try m.push(map.forth_wordlist);
        if (mode == 0) {
            try m.executeBuiltin(.in_wordlist);
            try std.testing.expectEqual(map.forth_wordlist, m.currentWordlist());
            try m.interpretLine(": AFTER 9 ; AFTER");
            try support.expectStack(m, &.{9});
        } else {
            image[0] = 'X';
            defer image[0] = 'S';
            try std.testing.expectError(error.InvalidImage, m.executeBuiltin(.in_wordlist));
            try std.testing.expectEqual(@as(map.Cell, 4), m.currentWordlist());
        }
    }
}

test "P08 review MAP VOCS stops when a callback handle is forgotten and reused" {
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try m.interpretLine("VARIABLE TIMES : B DROP 99 TIMES +! ; : REPLACE S\" FORGET D DEFER D ' B IS D\" EVALUATE ; : A DROP REPLACE ; DEFER D ' A IS D");
    try m.push(m.lookup("D").?);
    try std.testing.expectError(error.InvalidExecutionToken, m.executeBuiltin(.map_vocs));
    try std.testing.expectEqual(@as(map.Cell, 0), try m.readCell(m.words[m.lookup("TIMES").?].value));
    try std.testing.expect(m.wrap_guard == null);
}

test "P08 review removed saved actions are not restored into surviving deferred words" {
    for (0..2) |mode| {
        var out = support.Output{};
        const m = try support.createMachine(&out);
        defer support.destroyMachine(m);
        try m.interpretLine(": CB S\" FORGET X\" EVALUATE ; : CB-THROW CB -123 THROW ; DEFER D : X 1 ; ' X IS D : A 2 ;");
        try m.push(m.lookup("A").?);
        try m.push(m.lookup("D").?);
        try m.push(m.lookup(if (mode == 0) "CB" else "CB-THROW").?);
        if (mode == 0) {
            try std.testing.expectError(error.InvalidExecutionToken, m.executeBuiltin(.wrap_xt));
        } else {
            try std.testing.expectError(error.Thrown, m.executeBuiltin(.wrap_xt));
            try std.testing.expectEqual(@as(map.Cell, -123), m.throw_code);
        }
        try std.testing.expectEqual(@as(map.Cell, -1), try m.readCell(m.words[m.lookup("D").?].value));
        try std.testing.expect(m.wrap_guard == null);
        try m.interpretLine(": REUSED 99 ;");
        try std.testing.expectEqual(@as(map.Cell, -1), try m.readCell(m.words[m.lookup("D").?].value));
    }
}

const loading = @import("../core/library_loading.zig");
const TestDefinition = struct { []const u8, @import("../core/defs.zig").Builtin };
const test_group = loading.Group(TestDefinition){
    .vocabulary = "REVIEW-LIB",
    .definitions = &.{},
    .library_name = "*p08-review*",
    .vocabulary_address = map.graphics_vocabulary_address,
};

test "P08 review lazy loading isolates pending NEXTNAME and NONAME choices" {
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try m.interpretLine("S\" User-Name\" NEXTNAME");
    try loading.require(m, test_group, ": LIB-WORD 1 ;");
    try std.testing.expect(m.lookup("REVIEW-LIB") != null);
    try m.interpretLine(": 7 ; User-Name");
    try support.expectStack(m, &.{7});
    const another = loading.Group(TestDefinition){ .vocabulary = "REVIEW-TWO", .definitions = &.{}, .library_name = "*p08-review-two*", .vocabulary_address = map.audio_vocabulary_address };
    try m.interpretLine("NONAME");
    try loading.require(m, another, ": LIB-TWO 2 ;");
    try std.testing.expect(m.lookup("REVIEW-TWO") != null);
    try m.interpretLine(": 8 ; LATEST LATESTXT EXECUTE");
    try support.expectStack(m, &.{ 7, 0, 8 });
}

test "P08 review failed lazy loading restores allocated wordlist policy masks" {
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try m.interpretLine("CS-WORDLIST DROP S\" User-Name\" NEXTNAME");
    const count = m.wordlistCount();
    const cases = m.readCellConst(map.case_wordlists_address);
    const silent = m.readCellConst(map.silent_wordlists_address);
    try std.testing.expectError(error.UnknownWord, loading.require(m, test_group, "TABLE DROP : OK 1 ; UNKNOWN"));
    try std.testing.expectEqual(count, m.wordlistCount());
    try std.testing.expectEqual(cases, m.readCellConst(map.case_wordlists_address));
    try std.testing.expectEqual(silent, m.readCellConst(map.silent_wordlists_address));
    _ = try m.encodedSize();
    try m.interpretLine(": 9 ; User-Name");
    try support.expectStack(m, &.{9});
}

test "P08 review nested scopes track removal of each independently saved action" {
    for (0..2) |mode| {
        var out = support.Output{};
        const m = try support.createMachine(&out);
        defer support.destroyMachine(m);
        try m.interpretLine(": BASE-ACTION 1 ; : DROP-OLD S\" FORGET OLD-ACTION\" EVALUATE ; : INNER S\" BASE-ACTION\" FIND-NAME NAME>INTERPRET S\" D\" FIND-NAME NAME>INTERPRET ['] DROP-OLD WRAP-XT ; DEFER D : OLD-ACTION 2 ;");
        const base = m.lookup("BASE-ACTION").?;
        const old = m.lookup("OLD-ACTION").?;
        const d = m.lookup("D").?;
        try m.writeCell(m.words[d].value, if (mode == 0) old else base);
        try m.push(if (mode == 0) base else old);
        try m.push(d);
        try m.push(m.lookup("INNER").?);
        try std.testing.expectError(error.InvalidExecutionToken, m.executeBuiltin(.wrap_xt));
        try std.testing.expectEqual(@as(map.Cell, if (mode == 0) -1 else base), try m.readCell(m.words[d].value));
        try std.testing.expect(m.wrap_guard == null);
    }
}

test "P08 review final Macros callback still checks lifetime before MAP VOCS returns" {
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try m.interpretLine("VARIABLE TIMES : B DROP 99 TIMES +! ; : REPLACE S\" FORGET D DEFER D ' B IS D\" EVALUATE ; : A 255 = IF REPLACE THEN ; DEFER D ' A IS D");
    try m.push(m.lookup("D").?);
    try std.testing.expectError(error.InvalidExecutionToken, m.executeBuiltin(.map_vocs));
    try std.testing.expectEqual(@as(map.Cell, 0), try m.readCell(m.words[m.lookup("TIMES").?].value));
    try std.testing.expect(m.wrap_guard == null);
}

const Prerequisites = struct {
    const first = loading.Group(TestDefinition){ .vocabulary = "REVIEW-FIRST", .definitions = &.{}, .library_name = "*p08-first*", .vocabulary_address = map.graphics_vocabulary_address };
    const second = loading.Group(TestDefinition){ .vocabulary = "REVIEW-SECOND", .definitions = &.{}, .library_name = "*p08-second*", .vocabulary_address = map.audio_vocabulary_address };
    fn firstRequire(m: *forth.State) forth.RuntimeError!void {
        try loading.require(m, first, "TABLE DROP : FIRST-WORD 1 ;");
    }
    fn secondRequire(m: *forth.State) forth.RuntimeError!void {
        try loading.require(m, second, ": SECOND-WORD 2 ; UNKNOWN");
    }
    const outer = loading.Group(TestDefinition){
        .vocabulary = "REVIEW-OUTER",
        .definitions = &.{},
        .library_name = "*p08-outer*",
        .vocabulary_address = map.gui_vocabulary_address,
        .prerequisites = &.{
            .{ .require = firstRequire, .vocabulary_address = map.graphics_vocabulary_address },
            .{ .require = secondRequire, .vocabulary_address = map.audio_vocabulary_address },
        },
    };
};

test "P08 review failed prerequisites retain successful prerequisites and their case policies" {
    var out = support.Output{};
    const m = try support.createMachine(&out);
    defer support.destroyMachine(m);
    try m.interpretLine("S\" User-Name\" NEXTNAME");
    try std.testing.expectError(error.UnknownWord, loading.require(m, Prerequisites.outer, ": OUTER-WORD 3 ;"));
    try std.testing.expect(m.lookup("REVIEW-FIRST") != null);
    try std.testing.expect(m.lookup("REVIEW-SECOND") == null);
    try std.testing.expect(m.lookup("REVIEW-OUTER") == null);
    try std.testing.expectEqual(@as(map.Cell, 5), m.wordlistCount());
    try std.testing.expectEqual(@as(map.Cell, 16), m.readCellConst(map.case_wordlists_address));
    try std.testing.expectEqual(@as(map.Cell, 16), m.readCellConst(map.silent_wordlists_address));
    try m.interpretLine(": 7 ; User-Name");
    try support.expectStack(m, &.{7});
    const image = try std.testing.allocator.alloc(u8, try m.encodedSize());
    defer std.testing.allocator.free(image);
    _ = try m.encodeImage(image);
    try m.restoreImage(image);
    try std.testing.expectEqual(@as(map.Cell, 16), m.readCellConst(map.silent_wordlists_address));
}
