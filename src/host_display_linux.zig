//! The displays for DISPLAYS on Linux (tque 1258): asked of the X server by the RandR
//! extension, over a connection of its own that is closed again, so that DISPLAYS works
//! with and without Sigma's window. display_randr.zig reads the replies.
//!
//! RandR 1.5 gives the monitors (RRGetMonitors), with their places, sizes, and which is
//! primary. The refresh rate of a monitor is that of the mode its first output shows.
//! The work area is the window manager's _NET_WORKAREA of the current desktop, inside
//! each monitor. The X server does not know a display's scale, so it is not told. An X
//! server without RandR 1.5, or one that has not told its monitors in two seconds,
//! gives no displays; when the rest (the refresh rates, the work area) does not come
//! in that time, the monitors are given without it. DISPLAYS waits that long at most.

const std = @import("std");
const display_info = @import("core/display_info.zig");
const randr = @import("display_randr.zig");
const x = @import("host_x11.zig");

pub fn snapshot(out: *display_info.Snapshot) void {
    fill(out) catch {};
}

/// The monitor most of a window is on (x y w h of its drawable part in pixels of the X
/// screen), by the name DISPLAYS gives it; null when the server does not tell, or the
/// window is on none. It asks the server over a connection of its own.
pub fn monitorOf(rect: [4]i64) ?u64 {
    var conn = x.Connection.openUntil(x.now() + 2000) catch return null;
    defer conn.close();
    var list: [display_info.max_displays]randr.Monitor = undefined;
    const found = (monitorList(&conn, &list) catch return null) orelse return null;
    return randr.monitorOf(list[0..found.count], rect);
}

/// What a connection that stays open (the window's own) knows of RandR: the opcode of
/// the extension (null when the server has none) and whether its version is 1.5 or
/// later, each asked once; a step that failed is asked again the next time.
pub const Randr = struct {
    extension_asked: bool = false,
    extension: ?u8 = null,
    version_asked: bool = false,
    version_ok: bool = false,
};

/// As monitorOf, asked over a connection that is open; RandR is looked for the first
/// time only. Null when the window is on no monitor or the server has no RandR 1.5;
/// an error when the server could not be asked.
pub fn monitorOn(conn: *x.Connection, known: *Randr, rect: [4]i64) x.Error!?u64 {
    if (!known.extension_asked) {
        known.extension = try randrExtension(conn);
        known.extension_asked = true;
    }
    const opcode = known.extension orelse return null;
    if (!known.version_asked) {
        known.version_ok = try randrVersion(conn, opcode);
        known.version_asked = true;
    }
    if (!known.version_ok) return null;
    var list: [display_info.max_displays]randr.Monitor = undefined;
    const count = try monitorsWith(conn, opcode, &list);
    return randr.monitorOf(list[0..count], rect);
}

const Found = struct { opcode: u8, count: usize };

/// The monitors in use, by RandR 1.5, and the extension's opcode; null without it.
fn monitorList(conn: *x.Connection, list: []randr.Monitor) x.Error!?Found {
    const opcode = try randrOpcode(conn) orelse return null;
    const count = try monitorsWith(conn, opcode, list);
    if (count == 0) return null;
    return .{ .opcode = opcode, .count = count };
}

/// The opcode of RandR, when the server has version 1.5 or later; null otherwise.
fn randrOpcode(conn: *x.Connection) x.Error!?u8 {
    const opcode = try randrExtension(conn) orelse return null;
    return if (try randrVersion(conn, opcode)) opcode else null;
}

/// The opcode of the RandR extension; null when the server has none.
fn randrExtension(conn: *x.Connection) x.Error!?u8 {
    var query: [12]u8 = @splat(0);
    x.put16(&query, 0, 5);
    @memcpy(query[4..9], "RANDR");
    const extension = try conn.reply(try conn.request(98, 0, &query));
    if (extension.len < 32 or extension[8] == 0) return null;
    return extension[9];
}

/// Whether the server's RandR is version 1.5 or later.
fn randrVersion(conn: *x.Connection, opcode: u8) x.Error!bool {

    var wanted: [8]u8 = undefined;
    x.put32(&wanted, 0, 1);
    x.put32(&wanted, 4, 5);
    const version = try conn.reply(try conn.request(opcode, 0, &wanted));
    if (version.len < 32) return false;
    const major = x.get32(version, 8);
    const minor = x.get32(version, 12);
    return major > 1 or (major == 1 and minor >= 5);
}

/// The monitors in use (RRGetMonitors, get_active), with the opcode of RandR.
fn monitorsWith(conn: *x.Connection, opcode: u8, list: []randr.Monitor) x.Error!usize {

    // The monitors that are in use (get_active).
    var ask: [8]u8 = @splat(0);
    x.put32(&ask, 0, conn.root);
    ask[4] = 1;
    return randr.monitors(try conn.reply(try conn.request(opcode, 42, &ask)), list);
}

fn fill(out: *display_info.Snapshot) x.Error!void {
    var conn = try x.Connection.openUntil(x.now() + 2000);
    defer conn.close();
    var list: [display_info.max_displays]randr.Monitor = undefined;
    const found = try monitorList(&conn, &list) orelse return;
    const opcode = found.opcode;
    const count = found.count;

    var rates: [display_info.max_displays][2]u32 = @splat(.{ 0, 0 });
    refreshRates(&conn, opcode, list[0..count], rates[0..count]) catch {};
    randr.place(out, list[0..count], rates[0..count], workArea(&conn) catch null);
}

/// The refresh rate of each monitor: its first output's CRTC's mode, among the modes of
/// the screen. A monitor whose rate cannot be found keeps 0 0.
fn refreshRates(conn: *x.Connection, opcode: u8, list: []const randr.Monitor, rates: [][2]u32) x.Error!void {
    var root: [4]u8 = undefined;
    x.put32(&root, 0, conn.root);
    // The reply is kept: the connection's buffer is used again by the next request.
    const resources = std.heap.c_allocator.dupe(u8, try conn.reply(try conn.request(opcode, 25, &root))) catch return error.OutOfMemory;
    defer std.heap.c_allocator.free(resources);
    var body: [8]u8 = undefined;
    x.put32(&body, 4, randr.configTime(resources));
    for (list, rates) |monitor, *hz| {
        const output = monitor.output orelse continue;
        x.put32(&body, 0, output);
        const crtc = randr.outputCrtc(conn.reply(try conn.request(opcode, 9, &body)) catch continue) orelse continue;
        x.put32(&body, 0, crtc);
        const mode = randr.crtcMode(conn.reply(try conn.request(opcode, 20, &body)) catch continue) orelse continue;
        hz.* = randr.modeRate(resources, mode);
    }
}

/// Up to `out.len` CARDINAL values of a property of the root window, from `first` on.
fn cardinals(conn: *x.Connection, name: []const u8, first: u32, out: []u32) x.Error!usize {
    const atom = try conn.atom(name);
    var body: [20]u8 = @splat(0);
    x.put32(&body, 0, conn.root);
    x.put32(&body, 4, atom);
    x.put32(&body, 8, 6); // CARDINAL
    x.put32(&body, 12, first);
    x.put32(&body, 16, @intCast(out.len));
    const reply = try conn.reply(try conn.request(20, 0, &body));
    if (reply.len < 32 or reply[1] != 32) return 0;
    const count = @min(x.get32(reply, 16), out.len, (reply.len - 32) / 4);
    for (out[0..count], 0..) |*value, i| value.* = x.get32(reply, 32 + i * 4);
    return count;
}

/// The work area of the current desktop, x y w h in pixels of the X screen; null when
/// the window manager tells none.
fn workArea(conn: *x.Connection) x.Error!?[4]i32 {
    var desktop: [1]u32 = .{0};
    _ = try cardinals(conn, "_NET_CURRENT_DESKTOP", 0, &desktop);
    var work: [4]u32 = undefined;
    if (try cardinals(conn, "_NET_WORKAREA", @min(desktop[0], 1 << 20) * 4, &work) != 4) return null;
    if (work[2] == 0 or work[3] == 0 or work[2] > 1 << 20 or work[3] > 1 << 20) return null;
    return .{ @bitCast(work[0]), @bitCast(work[1]), @intCast(work[2]), @intCast(work[3]) };
}
