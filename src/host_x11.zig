//! Bounded X11 core-protocol transport. No libX11/libxcb dependency.
//! Only local Unix DISPLAY names are accepted; TCP/SSH forwarding is not implicit.
const std = @import("std");
pub const c = @import("c_x11");
const allocator = std.heap.c_allocator;
pub const Error = error{ Unavailable, Failed, OutOfMemory };
pub fn now() i64 {
    var ts: std.c.timespec = undefined;
    _ = std.c.clock_gettime(.MONOTONIC, &ts);
    return @as(i64, @intCast(ts.sec)) * 1000 + @divTrunc(ts.nsec, 1_000_000);
}
pub fn get16(bytes: []const u8, offset: usize) u16 {
    return std.mem.readInt(u16, bytes[offset..][0..2], .little);
}
pub fn get32(bytes: []const u8, offset: usize) u32 {
    return std.mem.readInt(u32, bytes[offset..][0..4], .little);
}
pub fn put16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .little);
}
pub fn put32(bytes: []u8, offset: usize, value: u32) void {
    std.mem.writeInt(u32, bytes[offset..][0..4], value, .little);
}
const Display = struct { number: u16, screen: u16 };
pub fn parseDisplay(value: []const u8) Error!Display {
    const s = if (std.mem.startsWith(u8, value, "unix:")) value[4..] else value;
    if (s.len < 2 or s[0] != ':') return error.Unavailable;
    var it = std.mem.splitScalar(u8, s[1..], '.');
    const n = std.fmt.parseInt(u16, it.next().?, 10) catch return error.Unavailable;
    const screen = if (it.next()) |v| std.fmt.parseInt(u16, v, 10) catch return error.Unavailable else 0;
    if (it.next() != null) return error.Unavailable;
    return .{ .number = n, .screen = screen };
}
fn getAuth(number: u16, output: *[256]u8) Error!usize {
    var path_buffer: [4096]u8 = undefined;
    const configured = c.getenv("XAUTHORITY");
    const path = if (configured != null and configured[0] != 0) std.mem.span(configured) else blk: {
        const home = c.getenv("HOME") orelse return 0;
        const value = std.fmt.bufPrint(path_buffer[0 .. path_buffer.len - 1], "{s}/.Xauthority", .{std.mem.span(home)}) catch return error.Unavailable;
        path_buffer[value.len] = 0;
        break :blk value;
    };
    // Do not block on a FIFO or inherit the authentication fd across SYSTEM/Tk.
    const fd = c.open(@ptrCast(path.ptr), c.O_RDONLY | c.O_CLOEXEC | c.O_NONBLOCK, @as(c_uint, 0));
    if (fd < 0) return 0;
    if (c.sigma_x11_authority_file(fd) == 0) {
        _ = c.close(fd);
        return error.Unavailable;
    }
    const file = c.fdopen(fd, "rb") orelse {
        _ = c.close(fd);
        return error.Unavailable;
    };
    defer _ = c.fclose(file);
    var hostname: [256]u8 = @splat(0);
    if (c.gethostname(&hostname, hostname.len - 1) != 0) return error.Unavailable;
    var number_buffer: [8]u8 = undefined;
    const digits = std.fmt.bufPrint(&number_buffer, "{d}", .{number}) catch unreachable;
    var best: usize = 0;
    var local_found = false;
    while (true) {
        var len: [2]u8 = undefined;
        const count = c.fread(&len, 1, 2, file);
        if (count == 0) {
            if (c.ferror(file) != 0) return error.Unavailable;
            break;
        }
        if (count != 2) return error.Unavailable;
        const family = std.mem.readInt(u16, &len, .big);
        var values: [4][1024]u8 = undefined;
        var lengths: [4]usize = undefined;
        for (&values, &lengths) |*value, *length| {
            if (c.fread(&len, 1, 2, file) != 2) return error.Unavailable;
            length.* = std.mem.readInt(u16, &len, .big);
            if (length.* > value.len or c.fread(value, 1, length.*, file) != length.*) return error.Unavailable;
        }
        const local = family == 256 and std.mem.eql(u8, values[0][0..lengths[0]], std.mem.sliceTo(&hostname, 0));
        if (!local and family != 65535) continue;
        if (lengths[1] != 0 and !std.mem.eql(u8, values[1][0..lengths[1]], digits)) continue;
        if (!std.mem.eql(u8, values[2][0..lengths[2]], "MIT-MAGIC-COOKIE-1") or lengths[3] > output.len) continue;
        if (best == 0 or (local and !local_found)) {
            best = lengths[3];
            @memcpy(output[0..best], values[3][0..best]);
            local_found = local;
        }
    }
    return best;
}
pub const Connection = struct {
    fd: c_int = -1,
    deadline: i64 = 0,
    sequence: u16 = 0,
    base: u32 = 0,
    mask: u32 = 0,
    next_id: u32 = 1,
    root: u32 = 0,
    /// The screen's size in pixels, from the connection setup.
    screen_width: u16 = 0,
    screen_height: u16 = 0,
    visual: u32 = 0,
    depth: u8 = 0,
    bits: u8 = 0,
    alignment: u8 = 0,
    byte_order: u8 = 0,
    red: u32 = 0,
    green: u32 = 0,
    blue: u32 = 0,
    max_request: usize = 0,
    min_key: u8 = 0,
    max_key: u8 = 0,
    rx: []u8,
    rx_used: usize = 0,
    packet: []u8,
    events: [512][32]u8 = undefined,
    event_count: usize = 0,
    xkb_event: u8 = 0,

    pub fn open() Error!Connection {
        return openUntil(now() + 5000);
    }
    pub fn openUntil(deadline: i64) Error!Connection {
        const display = c.getenv("DISPLAY") orelse return error.Unavailable;
        const d = try parseDisplay(std.mem.span(display));
        const rx = allocator.alloc(u8, 1024 * 1024) catch return error.OutOfMemory;
        errdefer allocator.free(rx);
        const packet = allocator.alloc(u8, 1024 * 1024) catch return error.OutOfMemory;
        errdefer allocator.free(packet);
        var self: Connection = .{ .rx = rx, .packet = packet, .deadline = deadline };
        self.fd = c.socket(c.AF_UNIX, c.SOCK_STREAM | c.SOCK_CLOEXEC | c.SOCK_NONBLOCK, 0);
        if (self.fd < 0) return error.Unavailable;
        errdefer _ = c.close(self.fd);
        var address: c.struct_sockaddr_un = std.mem.zeroes(c.struct_sockaddr_un);
        address.sun_family = c.AF_UNIX;
        const path = std.fmt.bufPrint(@as([*]u8, @ptrCast(&address.sun_path))[0 .. address.sun_path.len - 1], "/tmp/.X11-unix/X{d}", .{d.number}) catch return error.Unavailable;
        if (c.connect(self.fd, @ptrCast(&address), @intCast(@offsetOf(c.struct_sockaddr_un, "sun_path") + path.len + 1)) != 0) {
            if (c.__errno_location().* != c.EINPROGRESS) return error.Unavailable;
            try self.wait(c.POLLOUT);
            var value: c_int = 0;
            var size: c.socklen_t = @sizeOf(c_int);
            if (c.getsockopt(self.fd, c.SOL_SOCKET, c.SO_ERROR, &value, &size) != 0 or value != 0) return error.Unavailable;
        }
        var cookie: [256]u8 = undefined;
        const cookie_len = try getAuth(d.number, &cookie);
        var hello: [320]u8 = @splat(0);
        hello[0] = 'l';
        put16(&hello, 2, 11);
        const name = if (cookie_len != 0) "MIT-MAGIC-COOKIE-1" else "";
        put16(&hello, 6, @intCast(name.len));
        put16(&hello, 8, @intCast(cookie_len));
        @memcpy(hello[12..][0..name.len], name);
        const cookie_start = 12 + std.mem.alignForward(usize, name.len, 4);
        @memcpy(hello[cookie_start..][0..cookie_len], cookie[0..cookie_len]);
        try self.send(hello[0 .. cookie_start + std.mem.alignForward(usize, cookie_len, 4)]);
        var prefix: [8]u8 = undefined;
        try self.read(&prefix);
        const length: usize = @as(usize, get16(&prefix, 6)) * 4;
        if (prefix[0] != 1 or length < 32 or length > self.packet.len) return error.Unavailable;
        const body = self.packet[0..length];
        try self.read(body);
        self.base = get32(body, 4);
        self.mask = get32(body, 8);
        self.max_request = @as(usize, get16(body, 18)) * 4;
        self.byte_order = body[22];
        self.min_key = body[26];
        self.max_key = body[27];
        if (d.screen >= body[20] or self.max_request < 16384 or self.byte_order > 1 or self.mask == 0 or self.min_key < 8 or self.max_key < self.min_key) return error.Unavailable;
        const formats: usize = body[21];
        const format_start = 32 + std.mem.alignForward(usize, get16(body, 16), 4);
        var offset = format_start + formats * 8;
        if (offset > body.len) return error.Unavailable;
        for (0..body[20]) |screen| {
            if (offset + 40 > body.len) return error.Unavailable;
            if (screen == d.screen) {
                self.root = get32(body, offset);
                self.screen_width = get16(body, offset + 20);
                self.screen_height = get16(body, offset + 22);
                self.visual = get32(body, offset + 32);
                self.depth = body[offset + 38];
            }
            const depths = body[offset + 39];
            offset += 40;
            for (0..depths) |_| {
                if (offset + 8 > body.len) return error.Unavailable;
                const visuals = get16(body, offset + 2);
                offset += 8;
                for (0..visuals) |_| {
                    if (offset + 24 > body.len) return error.Unavailable;
                    if (screen == d.screen and get32(body, offset) == self.visual) {
                        if (body[offset + 4] != 4) return error.Unavailable; // TrueColor
                        self.red = get32(body, offset + 8);
                        self.green = get32(body, offset + 12);
                        self.blue = get32(body, offset + 16);
                    }
                    offset += 24;
                }
            }
        }
        for (0..formats) |index| {
            const f = body[format_start + index * 8 ..];
            if (f[0] == self.depth) {
                self.bits = f[1];
                self.alignment = f[2];
            }
        }
        if ((self.bits != 16 and self.bits != 24 and self.bits != 32) or
            (self.alignment != 8 and self.alignment != 16 and self.alignment != 32) or
            self.red == 0 or self.green == 0 or self.blue == 0) return error.Unavailable;
        return self;
    }
    pub fn close(self: *Connection) void {
        _ = c.close(self.fd);
        allocator.free(self.rx);
        allocator.free(self.packet);
    }
    fn wait(self: *Connection, events: c_short) Error!void {
        while (true) {
            const remaining = self.deadline - now();
            if (remaining <= 0) return error.Failed;
            var fd: c.struct_pollfd = .{ .fd = self.fd, .events = events, .revents = 0 };
            const result = c.poll(&fd, 1, @intCast(remaining));
            if (result < 0 and c.__errno_location().* == c.EINTR) continue;
            if (result <= 0 or fd.revents & (c.POLLERR | c.POLLHUP | c.POLLNVAL) != 0) return error.Failed;
            return;
        }
    }
    pub fn send(self: *Connection, bytes: []const u8) Error!void {
        var offset: usize = 0;
        while (offset < bytes.len) {
            if (now() >= self.deadline) return error.Failed;
            const count = c.send(self.fd, bytes[offset..].ptr, bytes.len - offset, c.MSG_NOSIGNAL);
            if (count > 0) {
                offset += @intCast(count);
                continue;
            }
            if (count == 0) return error.Failed;
            const err = c.__errno_location().*;
            if (err == c.EINTR) continue;
            if (err != c.EAGAIN) return error.Failed;
            // Drain readable data while waiting for writable space. The server must
            // never wait for us to read while we wait for its receive buffer.
            var fd: c.struct_pollfd = .{ .fd = self.fd, .events = c.POLLOUT | c.POLLIN, .revents = 0 };
            const remaining = self.deadline - now();
            if (remaining <= 0) return error.Failed;
            const polled = c.poll(&fd, 1, @intCast(remaining));
            if (polled < 0 and c.__errno_location().* == c.EINTR) continue;
            if (polled <= 0 or fd.revents & (c.POLLERR | c.POLLHUP | c.POLLNVAL) != 0) return error.Failed;
            if (fd.revents & c.POLLIN != 0) {
                if (self.rx_used == self.rx.len) return error.Failed;
                const n = c.recv(self.fd, self.rx[self.rx_used..].ptr, self.rx.len - self.rx_used, 0);
                if (n > 0) self.rx_used += @intCast(n) else if (n == 0 or (c.__errno_location().* != c.EAGAIN and c.__errno_location().* != c.EINTR)) return error.Failed;
            }
        }
    }
    fn read(self: *Connection, bytes: []u8) Error!void {
        const cached = @min(bytes.len, self.rx_used);
        @memcpy(bytes[0..cached], self.rx[0..cached]);
        std.mem.copyForwards(u8, self.rx[0 .. self.rx_used - cached], self.rx[cached..self.rx_used]);
        self.rx_used -= cached;
        var offset = cached;
        while (offset < bytes.len) {
            if (now() >= self.deadline) return error.Failed;
            const count = c.recv(self.fd, bytes[offset..].ptr, bytes.len - offset, 0);
            if (count > 0) {
                offset += @intCast(count);
                continue;
            }
            if (count == 0) return error.Failed;
            const err = c.__errno_location().*;
            if (err == c.EINTR) continue;
            if (err != c.EAGAIN) return error.Failed;
            try self.wait(c.POLLIN);
        }
    }
    pub fn request(self: *Connection, opcode: u8, detail: u8, body: []const u8) Error!u16 {
        const length = 4 + std.mem.alignForward(usize, body.len, 4);
        if (length > self.max_request or length / 4 > 65535) return error.Failed;
        var header: [4]u8 = .{ opcode, detail, 0, 0 };
        put16(&header, 2, @intCast(length / 4));
        try self.send(&header);
        try self.send(body);
        const padding = [_]u8{ 0, 0, 0 };
        try self.send(padding[0 .. length - 4 - body.len]);
        self.sequence +%= 1;
        return self.sequence;
    }
    pub fn ready(self: *Connection) Error!bool {
        if (self.rx_used != 0) return true;
        var fd: c.struct_pollfd = .{ .fd = self.fd, .events = c.POLLIN, .revents = 0 };
        const result = c.poll(&fd, 1, 0);
        if (result < 0 and c.__errno_location().* != c.EINTR) return error.Failed;
        if (fd.revents & (c.POLLERR | c.POLLHUP | c.POLLNVAL) != 0) return error.Failed;
        return result > 0;
    }
    pub fn next(self: *Connection) Error![]const u8 {
        try self.read(self.packet[0..32]);
        const kind = self.packet[0] & 127;
        if (kind == 0) return error.Failed;
        const units = if (kind == 1 or kind == 35) get32(self.packet, 4) else 0;
        if (units > (self.packet.len - 32) / 4) return error.Failed;
        const extra = @as(usize, units) * 4;
        try self.read(self.packet[32..][0..extra]);
        return self.packet[0 .. 32 + extra];
    }
    pub fn reply(self: *Connection, sequence: u16) Error![]const u8 {
        while (true) {
            const bytes = try self.next();
            if (bytes[0] == 1) {
                if (get16(bytes, 2) != sequence) return error.Failed;
                return bytes;
            }
            if (self.event_count == self.events.len) return error.Failed;
            self.events[self.event_count] = bytes[0..32].*;
            self.event_count += 1;
        }
    }
    pub fn sync(self: *Connection) Error!void {
        _ = try self.reply(try self.request(43, 0, &.{}));
    }
    pub fn enableDetectableRepeat(self: *Connection) Error!bool {
        var query: [13]u8 = @splat(0);
        put16(&query, 0, 9);
        @memcpy(query[4..], "XKEYBOARD");
        const extension = try self.reply(try self.request(98, 0, &query));
        if (extension[8] == 0) return false;
        const opcode = extension[9];
        self.xkb_event = extension[10];
        const version = try self.reply(try self.request(opcode, 0, &.{ 1, 0, 0, 0 }));
        if (version[1] == 0) return false;
        var selection: [12]u8 = @splat(0);
        put16(&selection, 0, 0x100);
        put16(&selection, 2, 3); // NewKeyboardNotify + MapNotify
        put16(&selection, 6, 3);
        put16(&selection, 8, 0xff); // all map components
        put16(&selection, 10, 0xff);
        _ = try self.request(opcode, 1, &selection);
        var flags: [24]u8 = @splat(0);
        put16(&flags, 0, 0x100); // UseCoreKbd
        put32(&flags, 4, 1); // change DetectableAutorepeat for this connection only
        put32(&flags, 8, 1);
        const reply_ = try self.reply(try self.request(opcode, 21, &flags));
        return get32(reply_, 8) & get32(reply_, 12) & 1 != 0;
    }
    pub fn resource(self: *Connection) Error!u32 {
        const shifted = @as(u64, self.next_id) << @intCast(@ctz(self.mask));
        if (shifted > std.math.maxInt(u32) or shifted & ~@as(u64, self.mask) != 0) return error.Failed;
        defer self.next_id += 1;
        return self.base | @as(u32, @intCast(shifted));
    }
    pub fn atom(self: *Connection, name: []const u8) Error!u32 {
        var body: [260]u8 = @splat(0);
        if (name.len > body.len - 4) return error.Failed;
        put16(&body, 0, @intCast(name.len));
        @memcpy(body[4..][0..name.len], name);
        return get32(try self.reply(try self.request(16, 0, body[0 .. 4 + name.len])), 8);
    }
};

test "local DISPLAY parser rejects forwarded and malformed names" {
    const d = try parseDisplay("unix:12.3");
    try std.testing.expectEqual(@as(u16, 12), d.number);
    try std.testing.expectEqual(@as(u16, 3), d.screen);
    for ([_][]const u8{ "", "localhost:10.0", "host:0", ":1.2.3", ":", ":1." }) |value|
        try std.testing.expectError(error.Unavailable, parseDisplay(value));
}

test "X11 oversized reply and GenericEvent lengths fail before multiplication" {
    var pair: [2]c_int = undefined;
    try std.testing.expectEqual(@as(c_int, 0), c.socketpair(c.AF_UNIX, c.SOCK_STREAM | c.SOCK_CLOEXEC, 0, &pair));
    defer _ = c.close(pair[1]);
    const rx = allocator.alloc(u8, 64) catch |err| {
        _ = c.close(pair[0]);
        return err;
    };
    const packet = allocator.alloc(u8, 64) catch |err| {
        allocator.free(rx);
        _ = c.close(pair[0]);
        return err;
    };
    var connection: Connection = .{ .fd = pair[0], .deadline = now() + 1000, .rx = rx, .packet = packet };
    defer connection.close();
    for ([_]u8{ 1, 35 }) |kind| {
        var header: [32]u8 = @splat(0);
        header[0] = kind;
        put32(&header, 4, std.math.maxInt(u32));
        try std.testing.expectEqual(@as(isize, header.len), c.send(pair[1], &header, header.len, c.MSG_NOSIGNAL));
        try std.testing.expectError(error.Failed, connection.next());
    }
}

test "X11 transport setup and round trip on an explicitly enabled desktop" {
    if (c.getenv("SIGMA_TEST_X11") == null) return error.SkipZigTest;
    var connection = try Connection.open();
    defer connection.close();
    try connection.sync();
    _ = try connection.enableDetectableRepeat();
    try std.testing.expect(try connection.atom("WM_PROTOCOLS") != 0);
}
