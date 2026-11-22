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

fn fill(out: *display_info.Snapshot) x.Error!void {
    var conn = try x.Connection.openUntil(x.now() + 2000);
    defer conn.close();

    var query: [12]u8 = @splat(0);
    x.put16(&query, 0, 5);
    @memcpy(query[4..9], "RANDR");
    const extension = try conn.reply(try conn.request(98, 0, &query));
    if (extension.len < 32 or extension[8] == 0) return;
    const opcode = extension[9];

    var wanted: [8]u8 = undefined;
    x.put32(&wanted, 0, 1);
    x.put32(&wanted, 4, 5);
    const version = try conn.reply(try conn.request(opcode, 0, &wanted));
    if (version.len < 32) return;
    const major = x.get32(version, 8);
    const minor = x.get32(version, 12);
    if (major < 1 or (major == 1 and minor < 5)) return;

    // The monitors that are in use (get_active).
    var ask: [8]u8 = @splat(0);
    x.put32(&ask, 0, conn.root);
    ask[4] = 1;
    var list: [display_info.max_displays]randr.Monitor = undefined;
    const count = randr.monitors(try conn.reply(try conn.request(opcode, 42, &ask)), &list);
    if (count == 0) return;

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
