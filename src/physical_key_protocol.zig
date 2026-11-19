//! Bounded AppKit physical-input line decoding. No native dependencies.
const std = @import("std");
const keys = @import("core/physical_keys.zig");
pub const Receiver = struct {
    sequence: u64 = 0,
    sync_pending: bool = false,
    pub fn accept(self: *Receiver, host: *keys.Host, line: []const u8) bool {
        if (!std.mem.startsWith(u8, line, "INPUT SCAN")) return false;
        if (!host.available) return true;
        self.decode(host, line) catch {
            host.tracker.transportLost();
            self.sync_pending = true;
        };
        return true;
    }
    fn decode(self: *Receiver, host: *keys.Host, line: []const u8) !void {
        var fields = std.mem.tokenizeScalar(u8, line, ' ');
        _ = fields.next();
        const kind = fields.next() orelse return error.Bad;
        const seq = try std.fmt.parseInt(u64, fields.next() orelse return error.Bad, 10);
        if (std.mem.eql(u8, kind, "SCAN")) {
            const scan = try std.fmt.parseInt(u8, fields.next() orelse return error.Bad, 10);
            const down = fields.next() orelse return error.Bad;
            if (fields.next() != null or !host.has(scan) or (!std.mem.eql(u8, down, "0") and !std.mem.eql(u8, down, "1"))) return error.Bad;
            if (seq != self.sequence +% 1) {
                host.tracker.transportLost();
                self.sync_pending = true;
            }
            self.sequence = seq;
            if (!host.tracker.stale) host.update(scan, down[0] == '1');
        } else if (std.mem.eql(u8, kind, "SCANSNAP")) {
            const hex = fields.next() orelse return error.Bad;
            if (fields.next() != null or hex.len != 64 or seq -% self.sequence > std.math.maxInt(u64) / 2) return error.Bad;
            var bitmap: keys.Bitmap = undefined;
            for (&bitmap, 0..) |*byte, i| byte.* = (try std.fmt.parseInt(u8, hex[i * 2 ..][0..2], 16)) & host.supported[i];
            self.sequence = seq;
            self.sync_pending = false;
            host.tracker.replaceSnapshot(bitmap);
        } else return error.Bad;
    }
};
test "physical IPC gap stays stale until authoritative snapshot" {
    var host: keys.Host = .{ .available = true };
    host.support(4);
    var receiver: Receiver = .{};
    try std.testing.expect(receiver.accept(&host, "INPUT SCAN 1 4 1"));
    try std.testing.expect(host.tracker.held(4));
    _ = receiver.accept(&host, "INPUT SCAN 3 4 0");
    try std.testing.expect(receiver.sync_pending and host.tracker.stale);
    _ = host.tracker.resync();
    try std.testing.expect(host.tracker.resync_required);
    _ = receiver.accept(&host, "INPUT SCANSNAP 3 0000000000000000000000000000000000000000000000000000000000000000");
    try std.testing.expect(!receiver.sync_pending and !host.tracker.stale and !host.tracker.held(4));
    _ = host.tracker.resync();
    try std.testing.expectEqual(@as(?keys.Event, null), host.tracker.next());
}
test "physical IPC rejects malformed payloads and supports sequence wrap" {
    var host: keys.Host = .{ .available = true };
    host.support(4);
    var receiver: Receiver = .{ .sequence = std.math.maxInt(u64) };
    _ = receiver.accept(&host, "INPUT SCAN 0 4 1");
    try std.testing.expect(!host.tracker.stale and host.tracker.held(4));
    _ = receiver.accept(&host, "INPUT SCAN 1 4 2");
    try std.testing.expect(host.tracker.stale and receiver.sync_pending);
    try std.testing.expect(!receiver.accept(&host, "INPUT TEXT 65"));
    _ = receiver.accept(&host, "INPUT SCANSNAP 0 XX");
    try std.testing.expect(host.tracker.stale);
}

test "physical lines after closure cannot leave the next window stale" {
    var host: keys.Host = .{};
    var receiver: Receiver = .{};
    _ = receiver.accept(&host, "INPUT SCAN 1 4 1");
    _ = receiver.accept(&host, "INPUT SCANSNAP corrupt");
    try std.testing.expect(!host.tracker.stale and !receiver.sync_pending);
}

pub const Writer = struct {
    context: ?*anyopaque,
    write: *const fn (?*anyopaque, []const u8) bool,
};
/// Child-side latest-state recovery. Caller owns synchronization and supplies a
/// nonblocking, all-or-nothing writer (each line is below PIPE_BUF).
pub const Sender = struct {
    bitmap: keys.Bitmap = @splat(0),
    sequence: u64 = 0,
    dirty: bool = false,
    pub fn edge(self: *Sender, scan: u8, down: bool, writer: Writer) void {
        if (scan < 4) return;
        const mask = @as(u8, 1) << @as(u3, @truncate(scan));
        if ((self.bitmap[scan / 8] & mask != 0) == down) return;
        if (down) self.bitmap[scan / 8] |= mask else self.bitmap[scan / 8] &= ~mask;
        self.sequence +%= 1;
        if (self.dirty) {
            self.flush(writer);
            return;
        }
        var buffer: [80]u8 = undefined;
        const line = std.fmt.bufPrint(&buffer, "INPUT SCAN {d} {d} {d}\n", .{ self.sequence, scan, @intFromBool(down) }) catch unreachable;
        if (!writer.write(writer.context, line)) self.dirty = true;
    }
    pub fn flush(self: *Sender, writer: Writer) void {
        if (!self.dirty) return;
        var buffer: [128]u8 = undefined;
        const prefix = std.fmt.bufPrint(&buffer, "INPUT SCANSNAP {d} ", .{self.sequence}) catch unreachable;
        const hex = "0123456789abcdef";
        for (self.bitmap, 0..) |byte, i| {
            buffer[prefix.len + i * 2] = hex[byte >> 4];
            buffer[prefix.len + i * 2 + 1] = hex[byte & 15];
        }
        buffer[prefix.len + 64] = '\n';
        if (writer.write(writer.context, buffer[0 .. prefix.len + 65])) self.dirty = false;
    }
    pub fn releaseAll(self: *Sender, writer: Writer) void {
        for (4..256) |scan| self.edge(@intCast(scan), false, writer);
    }
};
test "sender repairs final lost release on periodic flush without further edges" {
    const Sink = struct {
        blocked: bool = false,
        line: [128]u8 = undefined,
        length: usize = 0,
        fn write(ctx: ?*anyopaque, line: []const u8) bool {
            const self: *@This() = @ptrCast(@alignCast(ctx.?));
            if (self.blocked) return false;
            @memcpy(self.line[0..line.len], line);
            self.length = line.len;
            return true;
        }
    };
    var sink: Sink = .{};
    const writer: Writer = .{ .context = &sink, .write = Sink.write };
    var sender: Sender = .{};
    sender.edge(4, true, writer);
    var host: keys.Host = .{ .available = true };
    host.support(4);
    var receiver: Receiver = .{};
    _ = receiver.accept(&host, std.mem.trimEnd(u8, sink.line[0..sink.length], "\n"));
    try std.testing.expect(host.tracker.held(4));
    sink.blocked = true;
    sender.edge(4, false, writer);
    sender.flush(writer);
    try std.testing.expect(sender.dirty);
    sink.blocked = false;
    sender.flush(writer);
    try std.testing.expect(!sender.dirty);
    _ = receiver.accept(&host, std.mem.trimEnd(u8, sink.line[0..sink.length], "\n"));
    try std.testing.expect(!host.tracker.held(4) and host.tracker.resync_required);
    try std.testing.expectEqual(@as(u64, 2), receiver.sequence);
}
