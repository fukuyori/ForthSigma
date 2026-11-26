const std = @import("std");
const support = @import("support.zig");
const snapshot = @import("../core/task_snapshot.zig");
const restore = @import("../core/image_restore.zig");
const Plan = @import("../core/image_restore_plan.zig").Plan;
const append = @import("../core/image_append.zig");
const a = std.testing.allocator;
const keys = @import("../core/physical_keys.zig");

const HostProbe = struct {
    resets: usize = 0,
    frees: usize = 0,
    fn get(context: ?*anyopaque) *HostProbe {
        return @ptrCast(@alignCast(context.?));
    }
    fn reset(context: ?*anyopaque) void {
        get(context).resets += 1;
    }
    fn free(context: ?*anyopaque, _: []u32) void {
        get(context).frees += 1;
    }
    fn available(_: ?*anyopaque) bool {
        return true;
    }
    fn flag(_: ?*anyopaque, _: u8) bool {
        return true;
    }
    fn next(_: ?*anyopaque) ?keys.Event {
        return null;
    }
    fn resync(_: ?*anyopaque, bitmap: *keys.Bitmap) void {
        bitmap.* = @splat(0);
    }
    const ops: keys.Ops = .{ .available = available, .supported = flag, .held = flag, .next = next, .resync = resync, .reset = reset };
};

test "snapshot immutable versions resolve local entry after main changes" {
    var manager = snapshot.Manager{};
    var output = support.Output{};
    const main = try support.createMachine(&output);
    defer support.destroyMachine(main);
    try main.interpretLine("VARIABLE V 7 V ! : ENTRY V @ ;");
    const old = try manager.capture(a, main);
    defer old.release();
    const bytes = try a.dupe(u8, old.image());
    defer a.free(bytes);
    try main.interpretLine("9 V ! : ENTRY 999 ;");
    const latest = try manager.capture(a, main);
    defer latest.release();
    try std.testing.expect(old.id != latest.id and old.version < latest.version);
    var admitted = try old.admit(main);
    defer admitted.deinit();
    var vm = try snapshot.FreshVm.create(a, &admitted);
    defer vm.deinit();
    const entry = try vm.resolve("ENTRY");
    try std.testing.expect(entry != main.lookup("ENTRY").?);
    try vm.state.executeWord(entry);
    try support.expectStack(vm.state, &.{7});
    try std.testing.expectError(error.EntryNotFound, vm.resolve("MISSING"));
    try std.testing.expectEqualSlices(u8, bytes, old.image());
    try main.executeWord(main.lookup("ENTRY").?);
    try support.expectStack(main, &.{999});
    var latest_admission = try latest.admit(main);
    defer latest_admission.deinit();
    var new_vm = try snapshot.FreshVm.create(a, &latest_admission);
    defer new_vm.deinit();
    try new_vm.state.executeWord(try new_vm.resolve("ENTRY"));
    try support.expectStack(new_vm.state, &.{999});
}

test "snapshot caches successful entry inspections by name and releases cache names" {
    var manager = snapshot.Manager{};
    var output = support.Output{};
    const main = try support.createMachine(&output);
    defer support.destroyMachine(main);
    try main.interpretLine(": ENTRY 42 ; : OTHER 7 ;");
    const old = try manager.capture(a, main);
    const gate = @import("../core/task_permissions.zig").MemoryGate{
        .context = undefined,
        .check = struct {
            fn deny(_: *const anyopaque, _: []const @import("../core/task_permissions.zig").Access, _: usize) bool {
                return false;
            }
        }.deny,
    };
    const options: @import("../core/task_permissions.zig").Options = .{ .memory_gate = &gate };
    var inspected: usize = 0;
    try old.inspectEntryCounted(a, "ENTRY", options, &inspected);
    try old.inspectEntryCounted(a, "ENTRY", options, &inspected);
    try std.testing.expectEqual(@as(usize, 1), inspected);
    try old.inspectEntryCounted(a, "OTHER", options, &inspected);
    try std.testing.expectEqual(@as(usize, 2), inspected);
    try std.testing.expectError(error.EntryNotFound, old.inspectEntryCounted(a, "MISSING", options, &inspected));
    try std.testing.expectError(error.EntryNotFound, old.inspectEntryCounted(a, "MISSING", options, &inspected));
    try std.testing.expectEqual(@as(usize, 4), inspected);
    // A different policy never reuses a result cached under another one.
    var stricter = options;
    stricter.max_native_bytes = 1024;
    try old.inspectEntryCounted(a, "ENTRY", stricter, &inspected);
    try std.testing.expectEqual(@as(usize, 5), inspected);
    try old.inspectEntryCounted(a, "ENTRY", options, &inspected);
    try std.testing.expectEqual(@as(usize, 5), inspected);

    const newer = try manager.capture(a, main);
    try newer.inspectEntryCounted(a, "ENTRY", options, &inspected);
    try std.testing.expectEqual(@as(usize, 6), inspected);
    newer.release();
    old.release(); // std.testing.allocator detects any cache-name leak here.
}

test "snapshot FORGET and MARKER reject admission but keep running version alive" {
    var manager = snapshot.Manager{};
    inline for (.{ "FORGET ENTRY", "BACK" }) |edit| {
        var output = support.Output{};
        const main = try support.createMachine(&output);
        defer support.destroyMachine(main);
        try main.interpretLine("MARKER BACK : ENTRY 42 ;");
        const old = try manager.capture(a, main);
        var running = try old.admit(main);
        old.release(); // external handle disappears before the running owner
        defer running.deinit();
        try main.interpretLine(edit);
        try main.interpretLine(": ENTRY 99 ;"); // reuse IDs, never resurrect epoch
        try std.testing.expectError(error.StaleSnapshot, running.snapshot.admit(main));
        var vm = try snapshot.FreshVm.create(a, &running);
        defer vm.deinit();
        try vm.state.executeWord(try vm.resolve("ENTRY"));
        try support.expectStack(vm.state, &.{42});
        const fresh = try manager.capture(a, main);
        defer fresh.release();
        try std.testing.expect(fresh.canSubmit(main));
    }
}

test "snapshot complete restore invalidates only after successful preflight" {
    var manager = snapshot.Manager{};
    var output = support.Output{};
    const main = try support.createMachine(&output);
    defer support.destroyMachine(main);
    try main.interpretLine(": ENTRY 42 ;");
    const old = try manager.capture(a, main);
    defer old.release();
    const plan = try a.create(Plan);
    defer a.destroy(plan);
    try std.testing.expectError(error.InvalidImage, restore.restore(main, "bad", plan));
    try std.testing.expect(old.canSubmit(main));
    try restore.restore(main, old.image(), plan);
    try std.testing.expectError(error.StaleSnapshot, old.admit(main));
}

test "snapshot error abort and quotation abort do not change structural epoch" {
    var manager = snapshot.Manager{};
    var output = support.Output{};
    const main = try support.createMachine(&output);
    defer support.destroyMachine(main);
    try main.interpretLine(": ENTRY 42 ;");
    const old = try manager.capture(a, main);
    defer old.release();
    try std.testing.expectError(error.UnknownWord, main.interpretLine(": BAD MISSING ;"));
    try std.testing.expect(old.canSubmit(main));
    try std.testing.expectError(error.UnknownWord, main.interpretLine("[: MISSING ;]"));
    try std.testing.expect(old.canSubmit(main));
    try main.interpretLine("[: 1 ;] DROP");
    try std.testing.expect(old.canSubmit(main));
}

test "snapshot typed and State append invalidate old versions" {
    var manager = snapshot.Manager{};
    inline for (.{ false, true }) |typed| {
        var output = support.Output{};
        const main = try support.createMachine(&output);
        defer support.destroyMachine(main);
        const source = try support.createMachine(&output);
        defer support.destroyMachine(source);
        try source.interpretLine(": ADDED 3 ;");
        const old = try manager.capture(a, main);
        defer old.release();
        const incoming = try manager.capture(a, source);
        defer incoming.release();
        if (typed) {
            const work = try a.create(append.Workspace);
            defer a.destroy(work);
            try std.testing.expectError(error.InvalidImage, append.append(main, "bad", work));
            try std.testing.expect(old.canSubmit(main));
            try append.append(main, incoming.image(), work);
        } else {
            try std.testing.expectError(error.InvalidImage, main.appendImage(main));
            try std.testing.expect(old.canSubmit(main));
            try main.appendImage(source);
        }
        try std.testing.expectError(error.StaleSnapshot, old.admit(main));
    }
}

test "snapshot library rollback invalidates previously captured epoch" {
    var manager = snapshot.Manager{};
    const loading = @import("../core/library_loading.zig");
    const group: loading.Group(struct { []const u8, @import("../core/defs.zig").Builtin }) = .{
        .vocabulary = "PROBE",
        .definitions = &.{},
        .library_name = "snapshot-probe.fs",
        .vocabulary_address = @import("../core/memory_map.zig").extension_vocabulary_address,
    };
    var output = support.Output{};
    const main = try support.createMachine(&output);
    defer support.destroyMachine(main);
    const old = try manager.capture(a, main);
    defer old.release();
    try std.testing.expectError(error.UnknownWord, loading.require(main, group, ": GOOD 1 ; MISSING"));
    try std.testing.expectError(error.StaleSnapshot, old.admit(main));
    try std.testing.expect(main.lookup("GOOD") == null);
}

test "snapshot VM reference outlives external and admission owners" {
    var manager = snapshot.Manager{};
    var output = support.Output{};
    const main = try support.createMachine(&output);
    defer support.destroyMachine(main);
    try main.interpretLine(": ENTRY 42 ;");
    const old = try manager.capture(a, main);
    var admission = try old.admit(main);
    var vm = try snapshot.FreshVm.create(a, &admission);
    defer vm.deinit();
    old.release();
    admission.deinit();
    try main.interpretLine("FORGET ENTRY");
    try std.testing.expectEqual(@as(usize, 1), vm.snapshot.references.load(.acquire));
    try vm.state.executeWord(try vm.resolve("ENTRY"));
    try support.expectStack(vm.state, &.{42});
}

test "snapshot fresh restore cannot inherit main host callbacks or runtime resources" {
    var manager = snapshot.Manager{};
    var output = support.Output{};
    const main = try support.createMachine(&output);
    defer support.destroyMachine(main);
    try main.interpretLine(": ENTRY 42 ;");
    var host = HostProbe{};
    var pixels = [_]u32{0x123456};
    const writer = main.writer;
    defer main.writer = writer;
    main.writer.context = &host;
    main.writer.physical_key_ops = &HostProbe.ops;
    main.writer.image_free_fn = HostProbe.free;
    main.gfx_images[0] = .{ .pixels = &pixels, .width = 1, .height = 1 };
    main.gfx_images_bytes = 4;
    defer {
        main.gfx_images[0] = .{};
        main.gfx_images_bytes = 0;
    }
    main.pending_key = 65;
    main.random_state = 123;
    const old = try manager.capture(a, main);
    defer old.release();
    var admitted = try old.admit(main);
    defer admitted.deinit();
    var vm = try snapshot.FreshVm.create(a, &admitted);
    defer vm.deinit();
    try std.testing.expect(vm.state.writer.context == null);
    try std.testing.expect(vm.state.writer.physical_key_ops == null);
    inline for (@typeInfo(@TypeOf(vm.state.writer)).@"struct".field_names) |name| {
        if (@typeInfo(@FieldType(@TypeOf(vm.state.writer), name)) == .optional) try std.testing.expect(@field(vm.state.writer, name) == null);
    }
    try std.testing.expectEqual(@as(usize, 0), host.resets);
    try std.testing.expectEqual(@as(usize, 0), host.frees);
    try std.testing.expectEqual(@as(usize, 1), main.gfx_images[0].pixels.len);
    try std.testing.expectEqual(@as(usize, 0), vm.state.gfx_images_bytes);
    try std.testing.expect(vm.state.pending_key == null);
    try std.testing.expect(vm.state.sh_get_result == null);
    try std.testing.expectEqual(@as(@TypeOf(main.pending_key), 65), main.pending_key);
    try std.testing.expectEqual(@as(@TypeOf(main.random_state), 123), main.random_state);
    try std.testing.expectEqual(@as(usize, 0), output.len);
}

fn allocationLifecycle(allocator: std.mem.Allocator, main: *@import("../forth.zig").State) !void {
    var manager = snapshot.Manager{};
    defer std.debug.assert(manager.live_versions.load(.acquire) == 0);
    const version = try manager.capture(allocator, main);
    defer version.release();
    var admitted = try version.admit(main);
    defer admitted.deinit();
    var vm = try snapshot.FreshVm.create(allocator, &admitted);
    defer vm.deinit();
    _ = try vm.resolve("ENTRY");
}

test "snapshot allocation failures release capture workspace plan storage and references" {
    var output = support.Output{};
    const main = try support.createMachine(&output);
    defer support.destroyMachine(main);
    try main.interpretLine(": ENTRY 42 ;");
    try std.testing.checkAllAllocationFailures(a, allocationLifecycle, .{main});
}

test "snapshot rejects unrelated owners and fails closed on epoch exhaustion" {
    var manager = snapshot.Manager{};
    var output = support.Output{};
    const main = try support.createMachine(&output);
    defer support.destroyMachine(main);
    const other = try support.createMachine(&output);
    defer support.destroyMachine(other);
    const old = try manager.capture(a, main);
    defer old.release();
    try std.testing.expectError(error.StaleSnapshot, old.admit(other));
    main.task_structure_epoch = std.math.maxInt(u64) - 1;
    const last = try manager.capture(a, main);
    defer last.release();
    try main.interpretLine(": LAST 1 ; FORGET LAST");
    try std.testing.expectError(error.StaleSnapshot, last.admit(main));
    try std.testing.expectError(error.EpochExhausted, manager.capture(a, main));
    try main.interpretLine(": LAST 1 ; FORGET LAST");
    try std.testing.expectEqual(std.math.maxInt(u64), main.task_structure_epoch);
}

test "snapshot capture rejects each incomplete transaction state" {
    var manager = snapshot.Manager{};
    var output = support.Output{};
    const main = try support.createMachine(&output);
    defer support.destroyMachine(main);
    inline for (.{ "defining", "compiling", "postponing", "quote_closing", "noname_next" }) |field| {
        @field(main, field) = true;
        try std.testing.expectError(error.NotQuiescent, manager.capture(a, main));
        @field(main, field) = false;
    }
    inline for (.{ "quote_depth", "control_depth", "next_name_len", "interpret_loop_depth" }) |field| {
        @field(main, field) = 1;
        try std.testing.expectError(error.NotQuiescent, manager.capture(a, main));
        @field(main, field) = 0;
    }
    main.pending = .tick_name;
    try std.testing.expectError(error.NotQuiescent, manager.capture(a, main));
    main.pending = .none;
    main.colon_is_word = 0;
    try std.testing.expectError(error.NotQuiescent, manager.capture(a, main));
    main.colon_is_word = null;
    try std.testing.expectEqual(@as(u64, 0), main.task_snapshot_origin);
    try std.testing.expectEqual(@as(usize, 0), manager.live_versions.load(.acquire));
    try main.interpretLine(": INCOMPLETE 1 [");
    try std.testing.expectError(error.NotQuiescent, manager.capture(a, main));
}

test "snapshot image byte limit accepts equality and returns reservation on failure" {
    var manager = snapshot.Manager{};
    var output = support.Output{};
    const main = try support.createMachine(&output);
    defer support.destroyMachine(main);
    const first = try manager.capture(a, main);
    const length = first.image().len;
    first.release();
    manager.max_image_bytes = length - 1;
    try std.testing.expectError(error.ImageTooLarge, manager.capture(a, main));
    try std.testing.expectEqual(@as(usize, 0), manager.live_versions.load(.acquire));
    manager.max_image_bytes = length;
    const exact = try manager.capture(a, main);
    exact.release();
}

test "snapshot manager counts versions through final admitted reference" {
    var manager = snapshot.Manager{};
    var output = support.Output{};
    const main = try support.createMachine(&output);
    defer support.destroyMachine(main);
    const first = try manager.capture(a, main);
    var admitted = try first.admit(main);
    first.release();
    const second = try manager.capture(a, main);
    defer second.release();
    const third = try manager.capture(a, main);
    defer third.release();
    try std.testing.expectEqual(@as(usize, 3), manager.live_versions.load(.acquire));
    try std.testing.expectError(error.VersionLimit, manager.capture(a, main));
    admitted.deinit();
    const replacement = try manager.capture(a, main);
    replacement.release();
}

test "snapshot capture rejects open quotation and compile-only state at input boundaries" {
    inline for (.{ ": OPEN 1", "[: 1", ": OPEN [ ]", "'" }) |source| {
        var manager = snapshot.Manager{};
        var output = support.Output{};
        const main = try support.createMachine(&output);
        defer support.destroyMachine(main);
        try main.interpretLine(source);
        try std.testing.expectError(error.NotQuiescent, manager.capture(a, main));
        try std.testing.expectEqual(@as(usize, 0), manager.live_versions.load(.acquire));
    }
}
