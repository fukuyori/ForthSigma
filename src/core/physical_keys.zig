//! Physical keyboard state and bounded edge history, independent of text input.
//! The owner serializes access; this module never allocates or touches the OS.
const std = @import("std");

pub const capacity = 256;
pub const Bitmap = [32]u8;
pub const Kind = enum(u8) { press = 1, release = 2, resync = 3 };
pub const Event = struct { scan: u8, kind: Kind };

pub const Tracker = struct {
    bitmap: Bitmap = @splat(0),
    events: [capacity]Event = undefined,
    head: usize = 0,
    count: usize = 0,
    resync_required: bool = false,
    stale: bool = false,

    pub fn held(self: *const Tracker, scan: u8) bool {
        return self.bitmap[scan / 8] & (@as(u8, 1) << @as(u3, @truncate(scan))) != 0;
    }

    /// USB keyboard usages 0..3 are reserved/error reports, never edges.
    /// Repeats (and duplicate releases) do not alter history.
    pub fn update(self: *Tracker, scan: u8, down: bool) void {
        if (scan < 4 or self.held(scan) == down) return;
        const mask = @as(u8, 1) << @as(u3, @truncate(scan));
        if (down) self.bitmap[scan / 8] |= mask else self.bitmap[scan / 8] &= ~mask;
        if (self.resync_required) return;
        if (self.count == capacity) {
            self.resync_required = true;
            return;
        }
        self.events[(self.head + self.count) % capacity] = .{ .scan = scan, .kind = if (down) .press else .release };
        self.count += 1;
    }

    /// Keep reporting loss until the consumer explicitly adopts a snapshot.
    pub fn next(self: *Tracker) ?Event {
        if (self.count == 0) return if (self.resync_required) .{ .scan = 0, .kind = .resync } else null;
        const event = self.events[self.head];
        self.head = (self.head + 1) % capacity;
        self.count -= 1;
        return event;
    }

    /// The host holds its lock over the returned copy and acknowledgement.
    /// Callers validate the destination before entering this operation.
    pub fn resync(self: *Tracker) Bitmap {
        const copy = self.bitmap;
        self.head = 0;
        self.count = 0;
        self.resync_required = self.stale;
        return copy;
    }

    /// Focus loss preserves earlier short taps and appends synthetic releases.
    pub fn releaseAll(self: *Tracker) void {
        for (4..256) |scan| self.update(@intCast(scan), false);
    }

    /// Changed physical map / successful restore: no earlier history survives.
    pub fn boundary(self: *Tracker) void {
        self.bitmap = @splat(0);
        self.stale = false;
        self.loseHistory();
    }

    /// Transport loss may leave the bitmap usable, but invalidates its history.
    pub fn loseHistory(self: *Tracker) void {
        self.head = 0;
        self.count = 0;
        self.resync_required = true;
    }

    /// A sequence gap means even the held bitmap may be out of date.
    /// A consumer snapshot cannot acknowledge this until transport catches up.
    pub fn transportLost(self: *Tracker) void {
        self.stale = true;
        self.loseHistory();
    }

    /// Adopt an authoritative transport snapshot and require consumer resync.
    pub fn replaceSnapshot(self: *Tracker, bitmap: Bitmap) void {
        self.bitmap = bitmap;
        self.bitmap[0] &= 0xf0; // Never expose reserved/error usages as held.
        self.stale = false;
        self.loseHistory();
    }
};

test "short tap survives polling later and repeat adds no edge" {
    var tracker: Tracker = .{};
    tracker.update(4, true);
    tracker.update(4, true);
    tracker.update(4, false);
    tracker.update(4, false);
    try std.testing.expect(!tracker.held(4));
    try std.testing.expectEqual(Event{ .scan = 4, .kind = .press }, tracker.next().?);
    try std.testing.expectEqual(Event{ .scan = 4, .kind = .release }, tracker.next().?);
    try std.testing.expectEqual(@as(?Event, null), tracker.next());
}

test "all nonreserved usages coexist independently including both modifiers" {
    var tracker: Tracker = .{};
    for (0..256) |scan| tracker.update(@intCast(scan), true);
    for (0..256) |scan| try std.testing.expectEqual(scan >= 4, tracker.held(@intCast(scan)));
    try std.testing.expectEqual(@as(usize, 252), tracker.count);
    const bitmap = tracker.resync();
    try std.testing.expectEqual(@as(u8, 0xf0), bitmap[0]);
    for (bitmap[1..]) |byte| try std.testing.expectEqual(@as(u8, 255), byte);
    tracker.update(224, false);
    try std.testing.expect(!tracker.held(224));
    try std.testing.expect(tracker.held(228));
    try std.testing.expectEqual(Event{ .scan = 224, .kind = .release }, tracker.next().?);
}

test "exact capacity is lossless and overflow is sticky until snapshot" {
    var tracker: Tracker = .{};
    for (0..capacity) |index| tracker.update(4, index % 2 == 0);
    try std.testing.expect(!tracker.resync_required);
    try std.testing.expectEqual(@as(usize, capacity), tracker.count);
    tracker.update(5, true);
    tracker.update(4, true);
    for (0..capacity) |index| try std.testing.expectEqual(Event{ .scan = 4, .kind = if (index % 2 == 0) .press else .release }, tracker.next().?);
    for (0..3) |_| try std.testing.expectEqual(Event{ .scan = 0, .kind = .resync }, tracker.next().?);
    try std.testing.expect(tracker.held(4) and tracker.held(5));
    const bitmap = tracker.resync();
    try std.testing.expectEqual(@as(u8, 0x30), bitmap[0]);
    try std.testing.expectEqual(@as(?Event, null), tracker.next());
    tracker.update(5, false);
    try std.testing.expectEqual(Event{ .scan = 5, .kind = .release }, tracker.next().?);
}

test "transport gap cannot be acknowledged before an authoritative snapshot" {
    var tracker: Tracker = .{};
    tracker.update(4, true);
    tracker.transportLost();
    for (0..2) |_| {
        _ = tracker.resync();
        try std.testing.expectEqual(Event{ .scan = 0, .kind = .resync }, tracker.next().?);
    }
    tracker.update(5, true);
    var bitmap: Bitmap = @splat(0);
    bitmap[0] = 0x20;
    tracker.replaceSnapshot(bitmap);
    try std.testing.expect(!tracker.stale);
    try std.testing.expectEqual(Event{ .scan = 0, .kind = .resync }, tracker.next().?);
    try std.testing.expectEqual(bitmap, tracker.resync());
    try std.testing.expectEqual(@as(?Event, null), tracker.next());
    tracker.transportLost();
    tracker.boundary();
    try std.testing.expectEqual(@as(Bitmap, @splat(0)), tracker.resync());
    try std.testing.expectEqual(@as(?Event, null), tracker.next());
}

test "ring wrap keeps order across repeated draining" {
    var tracker: Tracker = .{};
    for (0..1000) |_| {
        tracker.update(255, true);
        tracker.update(255, false);
        try std.testing.expectEqual(Event{ .scan = 255, .kind = .press }, tracker.next().?);
        try std.testing.expectEqual(Event{ .scan = 255, .kind = .release }, tracker.next().?);
    }
    try std.testing.expect(!tracker.resync_required);
}

test "focus releases preserve taps and all current held bits" {
    var tracker: Tracker = .{};
    tracker.update(4, true);
    tracker.update(4, false);
    tracker.update(225, true);
    tracker.releaseAll();
    const expected = [_]Event{
        .{ .scan = 4, .kind = .press },   .{ .scan = 4, .kind = .release },
        .{ .scan = 225, .kind = .press }, .{ .scan = 225, .kind = .release },
    };
    for (expected) |event| try std.testing.expectEqual(event, tracker.next().?);
    try std.testing.expectEqual(@as(?Event, null), tracker.next());
    try std.testing.expectEqual(@as(Bitmap, @splat(0)), tracker.resync());
}

test "focus release overflow still clears every held bit" {
    var tracker: Tracker = .{};
    for (4..256) |scan| tracker.update(@intCast(scan), true);
    tracker.releaseAll();
    try std.testing.expect(tracker.resync_required);
    try std.testing.expectEqual(@as(Bitmap, @splat(0)), tracker.resync());
}

test "boundary discards stale input and marks even an empty state" {
    var tracker: Tracker = .{};
    tracker.update(4, true);
    tracker.boundary();
    try std.testing.expect(!tracker.held(4));
    try std.testing.expectEqual(Event{ .scan = 0, .kind = .resync }, tracker.next().?);
    _ = tracker.resync();
    tracker.update(5, true);
    try std.testing.expectEqual(Event{ .scan = 5, .kind = .press }, tracker.next().?);
}

test "transport snapshot preserves state but invalidates old history" {
    var tracker: Tracker = .{};
    tracker.update(4, true);
    var bitmap: Bitmap = @splat(0);
    bitmap[0] = 15;
    bitmap[28] = 0x11; // Left and right Ctrl.
    tracker.replaceSnapshot(bitmap);
    try std.testing.expect(!tracker.held(4));
    for (0..4) |scan| try std.testing.expect(!tracker.held(@intCast(scan)));
    try std.testing.expect(tracker.held(224) and tracker.held(228));
    try std.testing.expectEqual(Event{ .scan = 0, .kind = .resync }, tracker.next().?);
    _ = tracker.resync();
    tracker.update(224, false);
    try std.testing.expectEqual(Event{ .scan = 224, .kind = .release }, tracker.next().?);
}
pub const Ops = struct {
    available: *const fn (?*anyopaque) bool,
    supported: *const fn (?*anyopaque, u8) bool,
    held: *const fn (?*anyopaque, u8) bool,
    next: *const fn (?*anyopaque) ?Event,
    resync: *const fn (?*anyopaque, *Bitmap) void,
    reset: *const fn (?*anyopaque) void,
};
pub const Request = union(enum) { available, supported: u8, held: u8, next, resync, reset };
pub const Response = union(enum) { flag: bool, event: ?Event, bitmap: Bitmap, none };

/// Native host storage; the caller holds its existing host lock.
pub const Host = struct {
    tracker: Tracker = .{},
    available: bool = false,
    supported: Bitmap = @splat(0),
    pub fn support(self: *Host, scan: u8) void {
        if (scan >= 4) self.supported[scan / 8] |= @as(u8, 1) << @as(u3, @truncate(scan));
    }
    pub fn has(self: *const Host, scan: u8) bool {
        return self.available and self.supported[scan / 8] & (@as(u8, 1) << @as(u3, @truncate(scan))) != 0;
    }
    pub fn update(self: *Host, scan: u8, down: bool) void {
        if (self.has(scan)) self.tracker.update(scan, down);
    }
    pub fn close(self: *Host) void {
        self.tracker.releaseAll();
        self.tracker.stale = false;
        self.available = false;
    }
    pub fn request(self: *Host, req: Request) Response {
        return switch (req) {
            .available => .{ .flag = self.available },
            .supported => |scan| .{ .flag = self.has(scan) },
            .held => |scan| .{ .flag = self.has(scan) and self.tracker.held(scan) },
            .next => .{ .event = self.tracker.next() },
            .resync => .{ .bitmap = self.tracker.resync() },
            .reset => blk: {
                self.tracker.boundary();
                break :blk .none;
            },
        };
    }
};
