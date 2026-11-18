//! XIM X-transport client, currently limited to negotiated UTF8_STRING and
//! transport 0.x. No locale tables or libX11 are loaded by static musl builds.
const std = @import("std");
const x = @import("host_x11.zig");
const c = x.c;
const alloc = std.heap.c_allocator;
pub const Event = union(enum) { key: [32]u8, symbol: u32, text: []const u8, preedit: []const u8, none };
const Attr = struct { id: u16 = 0, found: bool = false };
pub const Client = struct {
    conn: x.Connection,
    window: u32 = 0,
    peer: u32 = 0,
    protocol: u32 = 0,
    more: u32 = 0,
    property: u32 = 0,
    properties: [16]u32 = @splat(0),
    property_index: usize = 0,
    minor: u32 = 0,
    boundary: u32 = 0,
    imid: u16 = 0,
    icid: u16 = 0,
    style: Attr = .{},
    client_window: Attr = .{},
    focus_window: Attr = .{},
    preedit_attr: Attr = .{},
    spot_attr: Attr = .{},
    buffer: []u8,
    used: usize = 0,
    text: [4096]u8 = undefined,
    preedit: [1024]u8 = undefined,
    preedit_len: usize = 0,
    focused: bool = false,
    awaiting: bool = false,
    awaiting_since: i64 = 0,
    last_received: i64 = 0,
    probe_sent: i64 = 0,
    forwarded_since_receive: bool = false,

    pub fn open(native_window: u32, deadline: i64) x.Error!Client {
        var self: Client = .{ .conn = try x.Connection.openUntil(deadline), .buffer = undefined };
        errdefer self.conn.close();
        self.buffer = alloc.alloc(u8, 65536) catch return error.OutOfMemory;
        errdefer alloc.free(self.buffer);
        self.conn.deadline = deadline;
        const servers = try self.conn.atom("XIM_SERVERS");
        var property: [20]u8 = @splat(0);
        x.put32(&property, 0, self.conn.root);
        x.put32(&property, 4, servers);
        x.put32(&property, 8, 4);
        x.put32(&property, 16, 1024);
        const server_reply = try self.conn.reply(try self.conn.request(20, 0, &property));
        if (server_reply[1] != 32 or server_reply.len > 32 + 4096) return error.Unavailable;
        var atoms: [1024]u32 = undefined;
        const count = x.get32(server_reply, 16);
        if (count > atoms.len or server_reply.len < 32 + @as(usize, count) * 4) return error.Unavailable;
        for (0..count) |i| atoms[i] = x.get32(server_reply, 32 + i * 4);
        var owner: u32 = 0;
        const modifiers = c.getenv("XMODIFIERS");
        const wanted = if (modifiers != null and std.mem.startsWith(u8, std.mem.span(modifiers), "@im=")) std.mem.span(modifiers)[4..] else "";
        if (std.mem.eql(u8, wanted, "none")) return error.Unavailable;
        for (atoms[0..count]) |atom| {
            var id: [4]u8 = undefined;
            x.put32(&id, 0, atom);
            const name_reply = try self.conn.reply(try self.conn.request(17, 0, &id));
            const n = x.get16(name_reply, 8);
            if (name_reply.len < 32 + @as(usize, n)) return error.Failed;
            const name = name_reply[32..][0..n];
            if (wanted.len != 0 and (!std.mem.startsWith(u8, name, "@server=") or !std.mem.eql(u8, name[8..], wanted))) continue;
            const reply = try self.conn.reply(try self.conn.request(23, 0, &id));
            owner = x.get32(reply, 8);
            if (owner != 0) break;
        }
        if (owner == 0) return error.Unavailable;
        self.window = try self.conn.resource();
        var create: [28]u8 = @splat(0);
        x.put32(&create, 0, self.window);
        x.put32(&create, 4, self.conn.root);
        x.put16(&create, 12, 1);
        x.put16(&create, 14, 1);
        x.put16(&create, 18, 1);
        x.put32(&create, 20, self.conn.visual);
        _ = try self.conn.request(1, self.conn.depth, &create);
        const connect = try self.conn.atom("_XIM_XCONNECT");
        self.protocol = try self.conn.atom("_XIM_PROTOCOL");
        self.more = try self.conn.atom("_XIM_MOREDATA");
        self.property = try self.conn.atom("_client_sigma_xim");
        for (&self.properties, 0..) |*atom, i| {
            var name: [64]u8 = undefined;
            const value = std.fmt.bufPrint(&name, "_client_sigma_xim_{d}", .{i}) catch unreachable;
            atom.* = try self.conn.atom(value);
        }
        var values: [20]u8 = @splat(0);
        x.put32(&values, 0, self.window);
        try self.cm(owner, connect, 32, &values);
        const hello = try self.message();
        if (hello[1] != 32 or x.get32(&hello, 8) != connect or x.get32(&hello, 16) != 0) return error.Unavailable;
        self.peer = x.get32(&hello, 12);
        self.minor = x.get32(&hello, 20);
        self.boundary = x.get32(&hello, 24);
        if (self.peer == 0 or self.minor > 2) return error.Unavailable;
        try self.send(1, &.{ 'l', 0, 1, 0, 0, 0, 0, 0 });
        _ = try self.expect(2);
        var locale: []const u8 = "en_US.UTF-8";
        for ([_][*:0]const u8{ "LC_ALL", "LC_CTYPE", "LANG" }) |name| {
            const value = c.getenv(name);
            if (value != null and value[0] != 0) {
                locale = std.mem.span(value);
                break;
            }
        }
        if (locale.len > 255) return error.Unavailable;
        var locale_packet: [256]u8 = undefined;
        locale_packet[0] = @intCast(locale.len);
        @memcpy(locale_packet[1..][0..locale.len], locale);
        try self.send(30, locale_packet[0 .. locale.len + 1]);
        const opened = try self.expect(31);
        if (opened.len < 8) return error.Failed;
        self.imid = x.get16(opened, 0);
        const im_len: usize = x.get16(opened, 2);
        if (im_len + 8 > opened.len) return error.Failed;
        const ic_len: usize = x.get16(opened, 4 + im_len);
        var offset = 8 + im_len;
        const end = offset + ic_len;
        if (end > opened.len) return error.Failed;
        while (offset < end) {
            if (end - offset < 6) return error.Failed;
            const id = x.get16(opened, offset);
            const length: usize = x.get16(opened, offset + 4);
            if (offset + 6 + length > end) return error.Failed;
            const name = opened[offset + 6 ..][0..length];
            inline for (.{ .{ "inputStyle", "style" }, .{ "clientWindow", "client_window" }, .{ "focusWindow", "focus_window" }, .{ "preeditAttributes", "preedit_attr" }, .{ "spotLocation", "spot_attr" } }) |item| {
                if (std.mem.eql(u8, name, item[0])) @field(self, item[1]) = .{ .id = id, .found = true };
            }
            offset += 4 + std.mem.alignForward(usize, 2 + length, 4);
        }
        // Only UTF-8 is offered: do not interpret COMPOUND_TEXT bytes as UTF-8.
        var enc: [20]u8 = @splat(0);
        x.put16(&enc, 0, self.imid);
        x.put16(&enc, 2, 12);
        enc[4] = 11;
        @memcpy(enc[5..16], "UTF8_STRING");
        try self.send(38, &enc);
        const encoding = try self.expect(39);
        if (encoding.len < 8 or x.get16(encoding, 2) != 0 or x.get16(encoding, 4) != 0) return error.Unavailable;
        if (!self.style.found or !self.client_window.found or !self.focus_window.found) return error.Unavailable;
        var attrs: [24]u8 = @splat(0);
        for ([_]u16{ self.style.id, self.client_window.id, self.focus_window.id }, 0..) |id, index| {
            x.put16(&attrs, index * 8, id);
            x.put16(&attrs, index * 8 + 2, 4);
            x.put32(&attrs, index * 8 + 4, if (index == 0) 0x402 else native_window);
        }
        var context: [28]u8 = @splat(0);
        x.put16(&context, 0, self.imid);
        x.put16(&context, 2, attrs.len);
        @memcpy(context[4..], &attrs);
        try self.send(50, &context);
        const created = try self.expect(51);
        if (created.len < 4 or x.get16(created, 0) != self.imid) return error.Failed;
        self.icid = x.get16(created, 2);
        if (self.icid == 0) return error.Failed;
        return self;
    }
    pub fn close(self: *Client) void {
        self.conn.deadline = x.now() + 100;
        if (self.icid != 0) {
            var ids: [4]u8 = undefined;
            x.put16(&ids, 0, self.imid);
            x.put16(&ids, 2, self.icid);
            self.send(52, &ids) catch {};
            _ = self.expect(53) catch &.{};
        }
        if (self.imid != 0) {
            var im: [4]u8 = @splat(0);
            x.put16(&im, 0, self.imid);
            self.send(32, &im) catch {};
            _ = self.expect(33) catch &.{};
        }
        if (self.peer != 0) {
            self.send(3, &.{}) catch {};
            _ = self.expect(4) catch &.{};
        }
        self.conn.close();
        alloc.free(self.buffer);
    }
    fn cm(self: *Client, target: u32, atom: u32, format: u8, bytes: []const u8) x.Error!void {
        if (bytes.len > 20) return error.Failed;
        var body: [40]u8 = @splat(0);
        x.put32(&body, 0, target);
        body[8] = 33;
        body[9] = format;
        x.put32(&body, 12, target);
        x.put32(&body, 16, atom);
        @memcpy(body[20..][0..bytes.len], bytes);
        _ = try self.conn.request(25, 0, &body);
    }
    fn send(self: *Client, opcode: u8, bytes: []const u8) x.Error!void {
        var outgoing: [4096]u8 = @splat(0);
        const length = std.mem.alignForward(usize, bytes.len, 4);
        if (length > outgoing.len - 4) return error.Failed;
        outgoing[0] = opcode;
        x.put16(&outgoing, 2, @intCast(length / 4));
        @memcpy(outgoing[4..][0..bytes.len], bytes);
        const value = outgoing[0 .. 4 + length];
        if (value.len <= 20) return self.cm(self.peer, self.protocol, 8, value);
        if (self.minor == 1 or (self.minor == 2 and value.len < self.boundary)) {
            var offset: usize = 0;
            while (offset < value.len) : (offset += 20) try self.cm(self.peer, if (offset + 20 < value.len) self.more else self.protocol, 8, value[offset..@min(offset + 20, value.len)]);
        } else {
            self.property = self.properties[self.property_index];
            self.property_index = (self.property_index + 1) % self.properties.len;
            var property: [4120]u8 = @splat(0);
            x.put32(&property, 0, self.peer);
            x.put32(&property, 4, self.property);
            x.put32(&property, 8, 31);
            property[12] = 8;
            x.put32(&property, 16, @intCast(value.len));
            @memcpy(property[20..][0..value.len], value);
            _ = try self.conn.request(18, 2, property[0 .. 20 + value.len]);
            var notify: [8]u8 = undefined;
            x.put32(&notify, 0, @intCast(value.len));
            x.put32(&notify, 4, self.property);
            try self.cm(self.peer, self.protocol, 32, &notify);
        }
    }
    fn message(self: *Client) x.Error![32]u8 {
        while (true) {
            const result = if (self.conn.event_count != 0) blk: {
                const item = self.conn.events[0];
                self.conn.event_count -= 1;
                std.mem.copyForwards([32]u8, self.conn.events[0..self.conn.event_count], self.conn.events[1 .. self.conn.event_count + 1]);
                break :blk item;
            } else (try self.conn.next())[0..32].*;
            if (result[0] & 127 == 33 and x.get32(&result, 4) == self.window) return result;
            // MappingNotify is broadcast to all X clients, including this one.
            if (result[0] & 127 == 17 and x.get32(&result, 8) == self.window) return error.Failed;
        }
    }
    fn packet(self: *Client) x.Error![]const u8 {
        self.used = 0;
        while (true) {
            const event = try self.message();
            const atom = x.get32(&event, 8);
            if (atom != self.protocol and atom != self.more) return error.Failed;
            if (event[1] == 8) {
                if (self.used + 20 > self.buffer.len) return error.Failed;
                @memcpy(self.buffer[self.used..][0..20], event[12..32]);
                self.used += 20;
                if (atom == self.more) continue;
            } else if (event[1] == 32) {
                const length: usize = x.get32(&event, 12);
                if (length > self.buffer.len - self.used) return error.Failed;
                var body: [20]u8 = @splat(0);
                x.put32(&body, 0, self.window);
                x.put32(&body, 4, x.get32(&event, 16));
                x.put32(&body, 8, 0);
                x.put32(&body, 16, @intCast(self.buffer.len / 4));
                const reply = try self.conn.reply(try self.conn.request(20, 1, &body));
                const actual: usize = x.get32(reply, 16);
                if (reply[1] != 8 or x.get32(reply, 12) != 0 or actual < length or reply.len < 32 + actual) return error.Failed;
                if (actual > length) {
                    var restore: [65556]u8 = @splat(0);
                    const rest = actual - length;
                    if (rest > restore.len - 20) return error.Failed;
                    x.put32(&restore, 0, self.window);
                    x.put32(&restore, 4, x.get32(&event, 16));
                    x.put32(&restore, 8, x.get32(reply, 8));
                    restore[12] = 8;
                    x.put32(&restore, 16, @intCast(rest));
                    @memcpy(restore[20..][0..rest], reply[32 + length ..][0..rest]);
                    _ = try self.conn.request(18, 1, restore[0 .. 20 + rest]); // prepend unread tail
                }
                @memcpy(self.buffer[self.used..][0..length], reply[32..][0..length]);
                self.used += length;
            } else return error.Failed;
            if (self.used < 4) return error.Failed;
            const length: usize = 4 + @as(usize, x.get16(self.buffer, 2)) * 4;
            if (length > self.used) return error.Failed;
            return self.buffer[0..length];
        }
    }
    fn expect(self: *Client, opcode: u8) x.Error![]const u8 {
        var notices: usize = 0;
        while (notices < 128) : (notices += 1) {
            const bytes = try self.packet();
            if (bytes[0] == opcode) return bytes[4..];
            if (bytes[0] != 37 and bytes[0] != 34) return error.Failed;
        }
        return error.Failed;
    }
    pub fn reset(self: *Client) x.Error!void {
        var ids: [4]u8 = undefined;
        x.put16(&ids, 0, self.imid);
        x.put16(&ids, 2, self.icid);
        try self.send(64, &ids);
    }
    pub fn focus(self: *Client, active: bool) x.Error!void {
        if (self.focused == active) return;
        var ids: [4]u8 = undefined;
        x.put16(&ids, 0, self.imid);
        x.put16(&ids, 2, self.icid);
        try self.send(if (active) 58 else 59, &ids);
        self.focused = active;
    }
    pub fn forward(self: *Client, event: []const u8) x.Error!void {
        if (!self.forwarded_since_receive) self.last_received = x.now();
        self.forwarded_since_receive = true;
        var body: [40]u8 = @splat(0);
        x.put16(&body, 0, self.imid);
        x.put16(&body, 2, self.icid);
        x.put16(&body, 4, 3);
        @memcpy(body[8..], event[0..32]);
        try self.send(60, &body);
    }
    pub fn spot(self: *Client, px: i16, py: i16) x.Error!void {
        if (!self.preedit_attr.found or !self.spot_attr.found or self.awaiting) return;
        var body: [20]u8 = @splat(0);
        x.put16(&body, 0, self.imid);
        x.put16(&body, 2, self.icid);
        x.put16(&body, 4, 12);
        x.put16(&body, 8, self.preedit_attr.id);
        x.put16(&body, 10, 8);
        x.put16(&body, 12, self.spot_attr.id);
        x.put16(&body, 14, 4);
        x.put16(&body, 16, @bitCast(px));
        x.put16(&body, 18, @bitCast(py));
        try self.send(54, &body);
        self.awaiting = true;
        self.awaiting_since = x.now();
    }
    fn sync(self: *Client) x.Error!void {
        var ids: [4]u8 = undefined;
        x.put16(&ids, 0, self.imid);
        x.put16(&ids, 2, self.icid);
        try self.send(62, &ids);
    }
    pub fn ready(self: *Client) x.Error!bool {
        while (self.conn.event_count != 0) {
            const event = self.conn.events[0];
            if (event[0] & 127 == 33 and x.get32(&event, 4) == self.window) return true;
            self.conn.event_count -= 1;
            std.mem.copyForwards([32]u8, self.conn.events[0..self.conn.event_count], self.conn.events[1 .. self.conn.event_count + 1]);
            if (event[0] & 127 == 17 and x.get32(&event, 8) == self.window) return error.Failed;
        }
        while (try self.conn.ready()) {
            const event = try self.conn.next();
            if (event[0] & 127 == 33 and x.get32(event, 4) == self.window) {
                self.conn.events[0] = event[0..32].*;
                self.conn.event_count = 1;
                return true;
            }
            if (event[0] & 127 == 17 and x.get32(event, 8) == self.window) return error.Failed;
        }
        if (self.awaiting and x.now() - self.awaiting_since > 1000) return error.Failed;
        if (self.forwarded_since_receive and x.now() - self.last_received > 1000) {
            if (self.probe_sent == 0) {
                var ids: [4]u8 = undefined;
                x.put16(&ids, 0, self.imid);
                x.put16(&ids, 2, self.icid);
                try self.send(61, &ids);
                self.probe_sent = x.now();
            } else if (x.now() - self.probe_sent > 1000) return error.Failed;
        }
        return false;
    }
    pub fn next(self: *Client) x.Error!Event {
        const bytes = try self.packet();
        self.last_received = x.now();
        self.probe_sent = 0;
        self.forwarded_since_receive = false;
        const body = bytes[4..];
        if (bytes[0] == 34) return .none;
        if (body.len < 4 or x.get16(body, 0) != self.imid) return error.Failed;
        switch (bytes[0]) {
            20 => return error.Failed,
            37, 34 => return .none,
            55 => {
                self.awaiting = false;
                return .none;
            },
            61 => {
                try self.sync();
                return .none;
            },
            62 => {
                return .none;
            },
            65 => {
                self.preedit_len = 0;
                return .{ .preedit = self.preedit[0..0] };
            },
            60 => {
                if (body.len < 40) return error.Failed;
                const event = body[8..40].*;
                if (x.get16(body, 4) & 1 != 0) try self.sync();
                return .{ .key = event };
            },
            63 => {
                if (body.len < 8) return error.Failed;
                const flags = x.get16(body, 4);
                const has_text = flags & 2 != 0;
                const both = flags & 6 == 6;
                const offset: usize = if (both) 12 else 6;
                if (!has_text) {
                    if (flags & 1 != 0) try self.sync();
                    if (flags & 4 != 0) {
                        if (body.len < 12) return error.Failed;
                        return .{ .symbol = x.get32(body, 8) };
                    }
                    return .none;
                }
                if (body.len < offset + 2) return error.Failed;
                const length: usize = x.get16(body, offset);
                if (length > self.text.len or body.len < offset + 2 + length) return error.Failed;
                @memcpy(self.text[0..length], body[offset + 2 ..][0..length]);
                if (!std.unicode.utf8ValidateSlice(self.text[0..length])) return error.Failed;
                if (flags & 1 != 0) try self.sync();
                return .{ .text = self.text[0..length] };
            },
            73 => {
                self.preedit_len = 0;
                var response: [8]u8 = @splat(0);
                x.put16(&response, 0, self.imid);
                x.put16(&response, 2, self.icid);
                x.put32(&response, 4, @intCast(self.preedit.len / 4));
                try self.send(74, &response);
                return .{ .preedit = self.preedit[0..0] };
            },
            75 => {
                if (body.len < 22) return error.Failed;
                const first = x.get32(body, 8);
                const deleted = x.get32(body, 12);
                const flags = x.get32(body, 16);
                const length: usize = x.get16(body, 20);
                if (body.len < 22 + length) return error.Failed;
                if (flags & 1 == 0 and length == 0) return .none; // feedback only
                const insert: []const u8 = if (flags & 1 != 0) "" else body[22..][0..length];
                if (!std.unicode.utf8ValidateSlice(insert)) return error.Failed;
                const count = std.unicode.utf8CountCodepoints(self.preedit[0..self.preedit_len]) catch return error.Failed;
                const signed_first: i32 = @bitCast(first);
                const signed_deleted: i32 = @bitCast(deleted);
                const start: u64 = @intCast(@min(count, @as(usize, @intCast(@max(0, signed_first)))));
                const removed: u64 = @intCast(@max(0, signed_deleted));
                const begin = byteOffset(self.preedit[0..self.preedit_len], start) orelse return error.Failed;
                const end = byteOffset(self.preedit[0..self.preedit_len], @min(count, start + removed)) orelse return error.Failed;
                const total = self.preedit_len - (end - begin) + insert.len;
                if (total > self.preedit.len) return error.Failed;
                if (begin + insert.len < end)
                    std.mem.copyForwards(u8, self.preedit[begin + insert.len .. total], self.preedit[end..self.preedit_len])
                else
                    std.mem.copyBackwards(u8, self.preedit[begin + insert.len .. total], self.preedit[end..self.preedit_len]);
                @memcpy(self.preedit[begin..][0..insert.len], insert);
                self.preedit_len = total;
                return .{ .preedit = self.preedit[0..total] };
            },
            76 => {
                if (body.len < 16) return error.Failed;
                var response: [8]u8 = undefined;
                @memcpy(response[0..4], body[0..4]);
                @memcpy(response[4..8], body[4..8]);
                try self.send(77, &response);
                return .none;
            },
            78 => {
                self.preedit_len = 0;
                return .{ .preedit = self.preedit[0..0] };
            },
            else => return .none,
        }
    }
};
fn byteOffset(bytes: []const u8, scalar: u64) ?usize {
    var offset: usize = 0;
    var count: u64 = 0;
    while (count < scalar and offset < bytes.len) : (count += 1) {
        const length = std.unicode.utf8ByteSequenceLength(bytes[offset]) catch return null;
        offset += length;
    }
    return if (count == scalar and offset <= bytes.len) offset else null;
}

test "XIM preedit positions count Unicode scalars rather than bytes" {
    try std.testing.expectEqual(@as(?usize, 3), byteOffset("日本語", 1));
    try std.testing.expectEqual(@as(?usize, 8), byteOffset("a😀日", 3));
    try std.testing.expectEqual(@as(?usize, null), byteOffset("日", 2));
}

test "XIM UTF-8 and preedit-capable context on an explicitly enabled desktop" {
    if (c.getenv("SIGMA_TEST_XIM") == null) return error.SkipZigTest;
    var connection = try x.Connection.open();
    defer connection.close();
    const window = try connection.resource();
    var body: [28]u8 = @splat(0);
    x.put32(&body, 0, window);
    x.put32(&body, 4, connection.root);
    x.put16(&body, 12, 1);
    x.put16(&body, 14, 1);
    x.put16(&body, 18, 1);
    x.put32(&body, 20, connection.visual);
    _ = try connection.request(1, connection.depth, &body);
    try connection.sync();
    var client = try Client.open(window, x.now() + 5000);
    defer client.close();
    try client.focus(true);
    try client.spot(10, 20);
    try client.focus(false);
}
