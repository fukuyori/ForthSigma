//! Runtime-owned process configuration and result table. No OS resources or VM
//! addresses are stored here. The native backend must release its resources
//! before removing an entry; a running entry cannot be removed accidentally.
const std = @import("std");
const Allocator = std.mem.Allocator;
const windows = @import("builtin").os.tag == .windows;
pub const Id = i64;
pub const capacity = 64;
pub const max_arguments = 128;
pub const max_environment_edits = 128;
pub const max_text_bytes = 65536;
pub const first_id: Id = 0x2000000000000000;
pub const Error = error{ InvalidId, InvalidState, InvalidText, Capacity, TooLarge, OutOfMemory };
pub const Mode = enum(u8) { pipe, inherit, ignore, merge_stdout };
pub const Phase = enum(u8) { configuring, running, exited, signaled };

pub const Config = struct {
    arguments: std.ArrayList([:0]u8) = .empty,
    /// Ordered edits: NAME=VALUE sets (including empty VALUE), NAME removes.
    /// Native environment construction applies platform-specific name matching.
    environment: std.ArrayList([:0]u8) = .empty,
    cwd: ?[:0]u8 = null,
    modes: [3]Mode = @splat(.pipe),
    text_bytes: usize = 0,

    pub fn deinit(self: *Config, allocator: Allocator) void {
        for (self.arguments.items) |value| allocator.free(value);
        for (self.environment.items) |value| allocator.free(value);
        self.arguments.deinit(allocator);
        self.environment.deinit(allocator);
        if (self.cwd) |value| allocator.free(value);
        self.* = .{};
    }
    fn validate(text: []const u8) Error!void {
        if (std.mem.indexOfScalar(u8, text, 0) != null or !std.unicode.utf8ValidateSlice(text)) return error.InvalidText;
    }
    fn room(self: *const Config, length: usize, removed: usize) Error!void {
        if (length >= max_text_bytes or length + 1 > max_text_bytes - (self.text_bytes - removed)) return error.TooLarge;
    }
    pub fn addArgument(self: *Config, allocator: Allocator, text: []const u8) Error!void {
        try validate(text);
        if (self.arguments.items.len == 0 and (text.len == 0 or (windows and std.mem.indexOfScalar(u8, text, '"') != null))) return error.InvalidText;
        if (self.arguments.items.len == max_arguments) return error.Capacity;
        try self.room(text.len, 0);
        const owned = try allocator.dupeSentinel(u8, text, 0);
        errdefer allocator.free(owned);
        try self.arguments.append(allocator, owned);
        self.text_bytes += text.len + 1;
    }
    pub fn setCwd(self: *Config, allocator: Allocator, text: []const u8) Error!void {
        try validate(text);
        const old_size = if (self.cwd) |old| old.len + 1 else 0;
        if (text.len == 0) {
            if (self.cwd) |old| allocator.free(old);
            self.cwd = null;
            self.text_bytes -= old_size;
            return;
        }
        try self.room(text.len, old_size);
        const owned = try allocator.dupeSentinel(u8, text, 0);
        if (self.cwd) |old| allocator.free(old);
        self.cwd = owned;
        self.text_bytes = self.text_bytes - old_size + text.len + 1;
    }
    pub fn addEnvironment(self: *Config, allocator: Allocator, text: []const u8) Error!void {
        try validate(text);
        const name = text[0 .. std.mem.indexOfScalar(u8, text, '=') orelse text.len];
        if (name.len == 0) return error.InvalidText;
        if (self.environment.items.len == max_environment_edits) return error.Capacity;
        try self.room(text.len, 0);
        const owned = try allocator.dupeSentinel(u8, text, 0);
        errdefer allocator.free(owned);
        try self.environment.append(allocator, owned);
        self.text_bytes += text.len + 1;
    }
    pub fn setMode(self: *Config, which: usize, mode: Mode) Error!void {
        if (which >= 3 or (mode == .merge_stdout and which != 2)) return error.InvalidText;
        self.modes[which] = mode;
    }
};

pub const Entry = struct {
    id: Id,
    internal: bool = false,
    native_owned: bool = false,
    native_lost: bool = false,
    config: Config = .{},
    phase: Phase = .configuring,
    /// Windows exit codes retain all 32 bits; POSIX signal numbers stay separate.
    code: i64 = 0,
    pub fn editable(self: *Entry) Error!*Config {
        if (self.phase != .configuring or self.native_owned or self.native_lost) return error.InvalidState;
        return &self.config;
    }
    /// Reserve native ownership before creating any OS resource. Keep this guard
    /// set if rollback fails; backend payload stays associated with this entry.
    pub fn nativeAcquired(self: *Entry) Error!void {
        if (self.phase != .configuring or self.native_owned or self.native_lost or self.config.arguments.items.len == 0) return error.InvalidState;
        self.native_owned = true;
    }
    /// Called only after native startup and FileSlot publication succeed.
    pub fn started(self: *Entry) Error!void {
        if (self.phase != .configuring or !self.native_owned or self.native_lost) return error.InvalidState;
        self.phase = .running;
    }
    /// Native backend calls this only after streams, process/PID and Job/group
    /// ownership have actually been released. Terminal status alone is not enough.
    pub fn nativeReleased(self: *Entry) Error!void {
        if (self.phase == .running and !self.native_lost) return error.InvalidState;
        self.native_owned = false;
    }
    /// Backend proved ECHILD/ownership loss. This is not an invented exit code;
    /// public STATUS continues reporting the native error until FREE.
    pub fn ownershipLost(self: *Entry) void {
        self.native_lost = true;
    }
    /// Status is sticky. Native PID/Job ownership remains until FREE; terminal
    /// state does not imply that the backend has reaped/released the process.
    pub fn finished(self: *Entry, phase: Phase, code: i64) Error!void {
        if (self.native_lost or self.phase != .running or (phase != .exited and phase != .signaled)) return error.InvalidState;
        if (phase == .signaled) {
            if (windows) return error.InvalidState;
            if (code < 1 or code > 127) return error.InvalidText;
        } else if (code < 0 or code > (if (windows) @as(i64, std.math.maxInt(u32)) else 255)) return error.InvalidText;
        self.phase = phase;
        self.code = code;
    }
};

// Access is serialized on the VM thread, including every native spawn adapter.
pub const Table = struct {
    allocator: Allocator,
    slots: [capacity + 1]?Entry = @splat(null),
    next_id: Id = first_id,
    pub fn init(allocator: Allocator) Table {
        return .{ .allocator = allocator };
    }
    /// Native ownership is external: do not call until native shutdown succeeds.
    pub fn deinit(self: *Table) void {
        for (&self.slots) |*slot| if (slot.*) |*entry| {
            std.debug.assert((entry.phase != .running or entry.native_lost) and !entry.native_owned);
            entry.config.deinit(self.allocator);
            slot.* = null;
        };
        // Preserve next_id: old IDs stay invalid if this table is reused.
    }
    pub fn create(self: *Table) Error!Id {
        const slot = for (self.slots[0..capacity]) |*candidate| {
            if (candidate.* == null) break candidate;
        } else return error.Capacity;
        if (self.next_id == std.math.maxInt(Id)) return error.Capacity;
        const id = self.next_id;
        self.next_id += 1;
        slot.* = .{ .id = id };
        return id;
    }
    /// One private Tcl entry shares the backend but not the public capacity.
    pub fn createInternal(self: *Table) Error!Id {
        const slot = &self.slots[capacity];
        if (slot.* != null or self.next_id == std.math.maxInt(Id)) return error.Capacity;
        const id = self.next_id;
        self.next_id += 1;
        slot.* = .{ .id = id, .internal = true };
        return id;
    }
    /// Public PROC callbacks must use this lookup; the Tcl adapter uses get().
    pub fn getPublic(self: *Table, id: Id) Error!*Entry {
        const entry = try self.get(id);
        if (entry.internal) return error.InvalidId;
        return entry;
    }
    pub fn get(self: *Table, id: Id) Error!*Entry {
        if (id < first_id) return error.InvalidId;
        for (&self.slots) |*slot| if (slot.*) |*entry| {
            if (entry.id == id) return entry;
        };
        return error.InvalidId;
    }
    pub fn removePublic(self: *Table, id: Id) Error!void {
        _ = try self.getPublic(id);
        return self.remove(id);
    }
    pub fn remove(self: *Table, id: Id) Error!void {
        for (&self.slots) |*slot| if (slot.*) |*entry| {
            if (entry.id != id) continue;
            if ((entry.phase == .running and !entry.native_lost) or entry.native_owned) return error.InvalidState;
            entry.config.deinit(self.allocator);
            slot.* = null;
            return;
        };
        return error.InvalidId;
    }
};

test "process configurations own strings, preserve empty argv and ordered environment edits" {
    var table = Table.init(std.testing.allocator);
    defer table.deinit();
    const id = try table.create();
    const entry = try table.get(id);
    var source = [_]u8{ 'a', 'b', 'c' };
    const config = try entry.editable();
    try config.addArgument(table.allocator, &source);
    @memset(&source, 'X');
    try config.addArgument(table.allocator, "");
    try config.addArgument(table.allocator, "日 本\\\"");
    try config.setCwd(table.allocator, "directory with spaces");
    try config.addEnvironment(table.allocator, "NAME=value");
    try config.addEnvironment(table.allocator, "NAME=");
    try config.addEnvironment(table.allocator, "NAME");
    try std.testing.expectEqualStrings("abc", config.arguments.items[0]);
    try std.testing.expectEqualStrings("", config.arguments.items[1]);
    try std.testing.expectEqualStrings("NAME=", config.environment.items[1]);
    try std.testing.expectEqualStrings("NAME", config.environment.items[2]);
    const old_bytes = config.text_bytes;
    try std.testing.expectError(error.InvalidText, config.addArgument(table.allocator, "a\x00b"));
    try std.testing.expectError(error.InvalidText, config.addEnvironment(table.allocator, "=bad"));
    try std.testing.expectError(error.InvalidText, config.addArgument(table.allocator, "\xff"));
    try std.testing.expectError(error.InvalidText, config.setMode(0, .merge_stdout));
    try std.testing.expectEqual(old_bytes, config.text_bytes);
    try config.setCwd(table.allocator, "");
    try std.testing.expect(config.cwd == null);
}

test "process IDs do not revive after free, slot reuse, or table cleanup" {
    var table = Table.init(std.testing.allocator);
    defer table.deinit();
    var ids: [capacity]Id = undefined;
    for (&ids) |*id| id.* = try table.create();
    try std.testing.expectError(error.Capacity, table.create());
    try table.remove(ids[0]);
    const replacement = try table.create();
    try std.testing.expect(replacement != ids[0]);
    try std.testing.expectError(error.InvalidId, table.get(ids[0]));
    table.deinit();
    const after_cleanup = try table.create();
    try std.testing.expect(after_cleanup > replacement);
    try std.testing.expectError(error.InvalidId, table.get(replacement));
    table.next_id = std.math.maxInt(Id);
    try std.testing.expectError(error.Capacity, table.create());
}

test "running process cannot be reconfigured or freed and terminal results remain readable" {
    var table = Table.init(std.testing.allocator);
    defer table.deinit();
    const id = try table.create();
    const entry = try table.get(id);
    try std.testing.expectError(error.InvalidState, entry.started());
    try entry.config.addArgument(table.allocator, "program");
    try entry.nativeAcquired();
    try entry.started();
    try std.testing.expectError(error.InvalidState, entry.editable());
    try std.testing.expectError(error.InvalidState, table.remove(id));
    try std.testing.expectError(error.InvalidText, entry.finished(.exited, -1));
    const exit_code: i64 = if (windows) 0xffffffff else 255;
    try entry.finished(.exited, exit_code);
    try std.testing.expectEqual(exit_code, (try table.get(id)).code);
    try std.testing.expectError(error.InvalidState, entry.finished(.exited, 0));
    try std.testing.expectEqual(exit_code, (try table.get(id)).code);
    try std.testing.expectError(error.InvalidState, table.removePublic(id));
    try entry.nativeReleased();
    try table.removePublic(id);
}

test "configuration allocation failures keep earlier arguments cwd and environment intact" {
    const Scenario = struct {
        fn run(allocator: Allocator) !void {
            var config: Config = .{};
            defer config.deinit(allocator);
            try config.addArgument(allocator, "program");
            try config.addEnvironment(allocator, "NAME=value");
            try config.setCwd(allocator, "old-directory");
            const before = config.text_bytes;
            config.setCwd(allocator, "replacement") catch |err| {
                try std.testing.expectEqualStrings("old-directory", config.cwd.?);
                try std.testing.expectEqual(before, config.text_bytes);
                return err;
            };
            try config.addArgument(allocator, "second");
            try config.addEnvironment(allocator, "NAME");
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Scenario.run, .{});
}

test "configuration text and argument limits fail without consuming capacity" {
    var config: Config = .{};
    defer config.deinit(std.testing.allocator);
    try std.testing.expectError(error.InvalidText, config.addArgument(std.testing.allocator, ""));
    try config.addArgument(std.testing.allocator, "program");
    const large: [max_text_bytes]u8 = @splat('a');
    const before = config.text_bytes;
    try std.testing.expectError(error.TooLarge, config.addArgument(std.testing.allocator, &large));
    try std.testing.expectEqual(before, config.text_bytes);
    while (config.arguments.items.len < max_arguments) try config.addArgument(std.testing.allocator, "");
    try std.testing.expectError(error.Capacity, config.addArgument(std.testing.allocator, ""));
}

test "Tcl reserved entry shares ownership without using or exposing public process slots" {
    var table = Table.init(std.testing.allocator);
    defer table.deinit();
    for (0..capacity) |_| _ = try table.create();
    try std.testing.expectError(error.Capacity, table.create());
    const tcl_id = try table.createInternal();
    try std.testing.expect((try table.get(tcl_id)).internal);
    try std.testing.expectError(error.InvalidId, table.getPublic(tcl_id));
    try std.testing.expectError(error.InvalidId, table.removePublic(tcl_id));
    try std.testing.expectError(error.Capacity, table.createInternal());
    try table.remove(tcl_id);
    const replacement = try table.createInternal();
    try std.testing.expect(replacement != tcl_id);
    try std.testing.expectError(error.InvalidId, table.get(tcl_id));
}

test "process terminal status validates OS exit codes and does not invent Windows signals" {
    var table = Table.init(std.testing.allocator);
    defer table.deinit();
    const entry = try table.get(try table.create());
    try (try entry.editable()).addArgument(table.allocator, "program");
    try entry.nativeAcquired();
    try entry.started();
    if (windows) {
        try std.testing.expectError(error.InvalidState, entry.finished(.signaled, 15));
        try entry.finished(.exited, 143);
    } else {
        try std.testing.expectError(error.InvalidText, entry.finished(.exited, 256));
        try std.testing.expectError(error.InvalidText, entry.finished(.signaled, 0));
        try std.testing.expectError(error.InvalidText, entry.finished(.signaled, 128));
        try entry.finished(.signaled, 15);
    }
    try entry.nativeReleased();
}

test "partially created native resources block reconfiguration until rollback completes" {
    var table = Table.init(std.testing.allocator);
    defer table.deinit();
    const id = try table.create();
    const entry = try table.getPublic(id);
    try (try entry.editable()).addArgument(table.allocator, "program");
    try entry.nativeAcquired();
    try std.testing.expectError(error.InvalidState, entry.editable());
    try std.testing.expectError(error.InvalidState, table.removePublic(id));
    try std.testing.expectError(error.InvalidState, entry.nativeAcquired());
    try entry.nativeReleased();
    try std.testing.expectEqualStrings("program", (try entry.editable()).arguments.items[0]);
    try table.removePublic(id);
}

test "verified native ownership loss permits cleanup without fabricating an exit result" {
    var table = Table.init(std.testing.allocator);
    defer table.deinit();
    const id = try table.create();
    const entry = try table.getPublic(id);
    try (try entry.editable()).addArgument(table.allocator, "program");
    try entry.nativeAcquired();
    try entry.started();
    entry.ownershipLost();
    try std.testing.expectEqual(Phase.running, entry.phase);
    try std.testing.expectError(error.InvalidState, table.removePublic(id));
    try entry.nativeReleased();
    try table.removePublic(id);
}
