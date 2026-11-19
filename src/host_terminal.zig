//! Terminal presentation ownership, independent of raw keyboard mode and Forth State.
const std = @import("std");
pub const alternate: u8 = 1;
pub const paste: u8 = 2;
pub const hidden_cursor: u8 = 4;
pub const mouse: u8 = 8;
pub const all: u8 = 15;
pub const Error = error{ HostFailed, HostUnavailable, InvalidMode };
pub const Backend = struct {
    context: ?*anyopaque = null,
    apply: *const fn (?*anyopaque, u8, bool) error{HostFailed}!void,
};

/// Host-thread only. get() reports accepted requests, excluding uncertain bits.
/// Raw input ownership stays with host_input; presentation mouse reports require raw.
pub const Manager = struct {
    backend: Backend,
    available: bool = false,
    supported: u8 = all,
    wanted: u8 = 0,
    applied: u8 = 0,
    dirty: u8 = 0,
    raw: bool = false,
    pauses: u32 = 0,

    pub fn get(self: *const Manager) u8 {
        return self.wanted & ~self.dirty;
    }

    fn target(self: *const Manager) u8 {
        if (self.pauses != 0) return 0;
        return self.wanted & self.supported & (if (self.raw) all else all & ~(mouse | paste));
    }

    fn one(self: *Manager, bit: u8, on: bool) Error!void {
        if (self.dirty & bit == 0 and (self.applied & bit != 0) == on) return;
        // Even a failing write can have changed the terminal. Retain uncertainty
        // until an explicit compensating request succeeds.
        self.dirty |= bit;
        try self.backend.apply(self.backend.context, bit, on);
        self.applied = if (on) self.applied | bit else self.applied & ~bit;
        self.dirty &= ~bit;
    }

    fn transition(self: *Manager, target_mask: u8) Error!void {
        var failed = false;
        for ([_]u8{ mouse, paste, hidden_cursor, alternate }) |bit| {
            if (target_mask & bit == 0) self.one(bit, false) catch {
                failed = true;
            };
        }
        if (failed) return error.HostFailed;
        for ([_]u8{ alternate, hidden_cursor, paste, mouse }) |bit| {
            if (target_mask & bit != 0) self.one(bit, true) catch {
                failed = true;
            };
        }
        if (failed) return error.HostFailed;
    }

    pub fn set(self: *Manager, mask: u8) Error!void {
        if (mask & ~all != 0) return error.InvalidMode;
        if (mask != 0 and !self.available) return error.HostUnavailable;
        try self.update(mask);
    }

    pub fn setLegacyMouse(self: *Manager, on: bool) Error!void {
        try self.update(if (on) self.wanted | mouse else self.wanted & ~mouse);
    }

    fn update(self: *Manager, mask: u8) Error!void {
        const old = self.wanted;
        self.wanted = mask & self.supported;
        self.transition(self.target()) catch |err| {
            self.wanted = old;
            self.transition(self.target()) catch {};
            return err;
        };
    }

    /// The raw value describes the actual keyboard mode, even if reconciliation fails.
    pub fn setRaw(self: *Manager, raw: bool) Error!void {
        self.raw = raw;
        try self.transition(self.target());
    }

    pub fn suspendModes(self: *Manager) Error!void {
        if (self.pauses == std.math.maxInt(u32)) return error.HostFailed;
        if (self.pauses == 0) {
            self.transition(0) catch |err| {
                self.transition(self.target()) catch {};
                return err;
            };
        }
        self.pauses += 1;
    }

    pub fn resumeModes(self: *Manager) Error!void {
        if (self.pauses == 0) return error.HostFailed;
        self.pauses -= 1;
        try self.transition(self.target());
    }

    pub fn finish(self: *Manager) Error!void {
        self.wanted = 0;
        self.pauses = 0;
        self.raw = false;
        try self.transition(0);
    }
};

const Fake = struct {
    hardware: u8 = 0,
    calls: usize = 0,
    fail_at: usize = 0,
    fail_after: usize = 0,
    fn apply(context: ?*anyopaque, bit: u8, on: bool) error{HostFailed}!void {
        const self: *Fake = @ptrCast(@alignCast(context.?));
        self.calls += 1;
        // Model an OS write which changed the terminal before reporting failure.
        self.hardware = if (on) self.hardware | bit else self.hardware & ~bit;
        if (self.calls == self.fail_at or (self.fail_after != 0 and self.calls >= self.fail_after)) return error.HostFailed;
    }
    fn manager(self: *Fake) Manager {
        return .{ .available = true, .backend = .{ .context = self, .apply = apply } };
    }
};

test "presentation works before raw, mouse waits for raw, finish always restores" {
    var fake: Fake = .{};
    var manager = fake.manager();
    try manager.set(alternate | hidden_cursor | mouse);
    try std.testing.expectEqual(alternate | hidden_cursor | mouse, manager.get());
    try std.testing.expectEqual(alternate | hidden_cursor, fake.hardware);
    try manager.setRaw(true);
    try std.testing.expectEqual(alternate | hidden_cursor | mouse, fake.hardware);
    try manager.setRaw(false);
    try std.testing.expectEqual(alternate | hidden_cursor, fake.hardware);
    try manager.finish();
    try std.testing.expectEqual(@as(u8, 0), fake.hardware);
    const calls = fake.calls;
    try manager.finish();
    try std.testing.expectEqual(calls, fake.calls);
}

test "suspension nests and restores the latest request only at the outer boundary" {
    var fake: Fake = .{};
    var manager = fake.manager();
    try manager.set(alternate);
    try manager.suspendModes();
    try manager.suspendModes();
    try manager.set(hidden_cursor);
    try manager.resumeModes();
    try std.testing.expectEqual(hidden_cursor, manager.get());
    try std.testing.expectEqual(@as(u8, 0), fake.hardware);
    try manager.resumeModes();
    try std.testing.expectEqual(hidden_cursor, fake.hardware);
    try std.testing.expectError(error.HostFailed, manager.resumeModes());
}

test "partial setting failure rolls back and persistent restoration stays dirty" {
    var fake: Fake = .{ .fail_at = 2 };
    var manager = fake.manager();
    try std.testing.expectError(error.HostFailed, manager.set(alternate | hidden_cursor));
    try std.testing.expectEqual(@as(u8, 0), fake.hardware);
    try std.testing.expectEqual(@as(u8, 0), manager.wanted);
    fake.fail_after = fake.calls + 1;
    try std.testing.expectError(error.HostFailed, manager.set(alternate));
    try std.testing.expect(manager.dirty != 0);
    try std.testing.expectEqual(@as(u8, 0), manager.get());
    fake.fail_after = 0;
    try manager.finish();
    try std.testing.expectEqual(@as(u8, 0), manager.dirty);
    try std.testing.expectEqual(@as(u8, 0), fake.hardware);
}

test "unsupported paste is filtered and non-terminals reject nonzero requests" {
    var fake: Fake = .{};
    var manager = fake.manager();
    manager.supported = all & ~paste;
    try manager.set(paste | alternate);
    try std.testing.expectEqual(alternate, manager.get());
    try manager.finish();
    manager.available = false;
    try std.testing.expectError(error.HostUnavailable, manager.set(alternate));
    try manager.set(0);
    try std.testing.expectError(error.InvalidMode, manager.set(128));
}

test "failed suspend restores request and does not create an unmatched pause" {
    var fake: Fake = .{};
    var manager = fake.manager();
    try manager.set(alternate);
    fake.fail_at = fake.calls + 1;
    try std.testing.expectError(error.HostFailed, manager.suspendModes());
    try std.testing.expectEqual(@as(u32, 0), manager.pauses);
    try std.testing.expectEqual(alternate, fake.hardware);
}

test "an explicit reset can recover dirty ON state without retrying ON first" {
    var fake: Fake = .{};
    var manager = fake.manager();
    try manager.set(alternate);
    manager.applied = 0;
    manager.dirty = alternate;
    // A reset needs one OFF write. Retrying the old ON first would fail here.
    fake.fail_at = fake.calls + 2;
    try manager.set(0);
    try std.testing.expectEqual(@as(u8, 0), manager.get());
    try std.testing.expectEqual(@as(u8, 0), manager.dirty);
    try std.testing.expectEqual(@as(u8, 0), fake.hardware);
}
