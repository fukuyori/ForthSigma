//! Experimental local X11 window. Enable with -Dx11=true while broader
//! acceptance is unfinished; the default Linux display remains Tk/terminal.
const std = @import("std");
const forth = @import("forth.zig");
const x = @import("host_x11.zig");
const xim = @import("host_xim.zig");
const window_layout = @import("window_layout.zig");
const c = x.c;
const allocator = std.heap.c_allocator;
const Status = enum { idle, starting, ready, closed, unavailable, failed, oom };
const Frame = struct { pixels: []u32, width: u32, height: u32, requested: [2]u32, deadline: i64 = 0 };
var guard = std.atomic.Value(u8).init(0);
var stop = std.atomic.Value(bool).init(false);
var running = false;
// Protected by guard; failures of an abandoned startup have no remaining waiter.
var abandoned = false;
var thread: ?c.pthread_t = null;
var status: Status = .idle;
var start_deadline: i64 = 0;
var mailbox: ?Frame = null;
var keys: [64]struct { hardware: u8, code: u32 } = undefined;
var key_head: usize = 0;
var key_count: usize = 0;
var down: [256]u32 = @splat(0);
var told: [256]u32 = @splat(0);
var mouse_queue: [64]forth.InputEvent = undefined;
var mouse_head: usize = 0;
var mouse_count: usize = 0;
var mouse_latest: forth.InputEvent = .{ .window_mouse = .{ .x = -1, .y = -1, .buttons = 0 } };
var mouse_dirty = false;
var preedit: [1024]u8 = undefined;
var preedit_len: usize = 0;
const Caret = struct { active: bool = false, px: i64 = 0, py: i64 = 0, height: i64 = 0 };
var caret: Caret = .{};
var caret_dirty = false;
/// FULLSCREEN and MOUSE-CURSOR as asked (Alt+Enter clears fullscreen_wanted), and
/// whether the window has yet to take them.
var fullscreen_wanted = false;
var fullscreen_dirty = false;
var cursor_visible = true;
var cursor_dirty = false;
/// The host's window_fullscreen_fn: request 1 or 0 asks, -1 only tells.
pub fn fullscreen(_: ?*anyopaque, request: i8) forth.RuntimeError!bool {
    lock();
    defer unlock();
    if (request >= 0 and fullscreen_wanted != (request == 1)) {
        fullscreen_wanted = request == 1;
        fullscreen_dirty = true;
    }
    return fullscreen_wanted;
}
/// The host's window_cursor_fn.
pub fn mouseCursor(_: ?*anyopaque, visible: bool) forth.RuntimeError!void {
    lock();
    defer unlock();
    if (cursor_visible != visible) {
        cursor_visible = visible;
        cursor_dirty = true;
    }
}
pub fn imePreedit(_: ?*anyopaque, destination: []u8) forth.RuntimeError!usize {
    lock();
    defer unlock();
    var n = @min(preedit_len, destination.len);
    while (n > 0 and n < preedit_len and preedit[n] & 0xc0 == 0x80) n -= 1;
    @memcpy(destination[0..n], preedit[0..n]);
    return n;
}
pub fn imeCaret(_: ?*anyopaque, active: bool, px: i64, py: i64, height: i64) forth.RuntimeError!void {
    lock();
    defer unlock();
    if (caret.active != active or caret.px != px or caret.py != py or caret.height != height) {
        caret = .{ .active = active, .px = px, .py = py, .height = height };
        caret_dirty = true;
        if (!active) preedit_len = 0;
    }
}
fn setPreedit(bytes: []const u8) void {
    lock();
    defer unlock();
    preedit_len = @min(bytes.len, preedit.len);
    @memcpy(preedit[0..preedit_len], bytes[0..preedit_len]);
}
fn releaseFocus() void {
    lock();
    defer unlock();
    down = @splat(0);
    mouse_latest.window_mouse.buttons = 0;
    mouse_dirty = true;
    preedit_len = 0;
}

fn lock() void {
    while (guard.cmpxchgWeak(0, 1, .acquire, .monotonic) != null) std.atomic.spinLoopHint();
}
fn unlock() void {
    guard.store(0, .release);
}
fn free(frame: Frame) void {
    allocator.free(frame.pixels);
}
fn take() ?Frame {
    lock();
    defer unlock();
    const result = mailbox;
    mailbox = null;
    return result;
}
fn resetInput() void {
    lock();
    defer unlock();
    down = @splat(0);
    mouse_latest = .{ .window_mouse = .{ .x = -1, .y = -1, .buttons = 0 } };
    mouse_dirty = true;
}
pub fn show(_: ?*anyopaque, image: []const u32, width: u32, height: u32, mode: forth.ColorMode, requested: [2]u32) forth.RuntimeError!void {
    if (width == 0 or height == 0 or image.len != @as(usize, width) * height) return error.InvalidNumber;
    const budget = @import("host_display_budget.zig");
    const deadline = @min(x.now() + @as(i64, if (budget.active()) 2000 else 5000), budget.deadline());
    if (x.now() >= deadline) return error.HostUnavailable;
    const pixels = allocator.alloc(u32, image.len) catch return error.MemoryExhausted;
    for (pixels, image, 0..) |*out, value, index| {
        if (index % 4096 == 0 and budget.active() and x.now() >= deadline) {
            allocator.free(pixels);
            return error.HostUnavailable;
        }
        out.* = if (mode.colors == 0) value else forth.graphicsColor(mode, index % width, index / width, value);
    }
    lock();
    while (running and abandoned) {
        unlock();
        if (x.now() >= deadline) {
            allocator.free(pixels);
            return error.HostUnavailable;
        }
        _ = c.usleep(1000);
        lock();
    }
    if (running and stop.load(.acquire)) {
        unlock();
        allocator.free(pixels);
        return error.HostUnavailable;
    }
    if (!running) {
        const old_thread = thread;
        const old_status = status;
        thread = null;
        status = .idle;
        unlock();
        if (old_thread) |t| _ = c.pthread_join(t, null);
        if (old_status == .failed or old_status == .oom) {
            allocator.free(pixels);
            return if (old_status == .oom) error.MemoryExhausted else error.HostFailed;
        }
        lock();
        stop.store(false, .release);
        abandoned = false;
        running = true;
        status = .starting;
        start_deadline = deadline;
        var handle: c.pthread_t = undefined;
        var blocked: c.sigset_t = undefined;
        var previous_mask: c.sigset_t = undefined;
        _ = c.sigfillset(&blocked);
        if (c.pthread_sigmask(c.SIG_BLOCK, &blocked, &previous_mask) != 0) {
            running = false;
            unlock();
            allocator.free(pixels);
            return error.HostUnavailable;
        }
        var attributes: c.pthread_attr_t = undefined;
        const attr_ok = c.pthread_attr_init(&attributes) == 0;
        const sized = attr_ok and c.pthread_attr_setstacksize(&attributes, 4 * 1024 * 1024) == 0;
        const spawned = if (sized) c.pthread_create(&handle, &attributes, entry, null) else -1;
        if (attr_ok) _ = c.pthread_attr_destroy(&attributes);
        _ = c.pthread_sigmask(c.SIG_SETMASK, &previous_mask, null);
        if (spawned != 0) {
            running = false;
            status = .unavailable;
            unlock();
            allocator.free(pixels);
            return error.HostUnavailable;
        }
        thread = handle;
    }
    const old = mailbox;
    if (status == .closed) {
        status = .starting;
        start_deadline = deadline;
    }
    mailbox = .{ .pixels = pixels, .width = width, .height = height, .requested = requested, .deadline = if (status == .starting) start_deadline else x.now() + 5000 };
    const wait_for_ready = status != .ready;
    unlock();
    if (old) |frame| free(frame);
    if (!wait_for_ready) return;
    while (x.now() < deadline) {
        lock();
        const current = status;
        if (current == .failed or current == .oom or current == .unavailable) status = .idle;
        unlock();
        switch (current) {
            .ready => return,
            .unavailable => return error.HostUnavailable,
            .failed => return error.HostFailed,
            .oom => return error.MemoryExhausted,
            else => {},
        }
        _ = c.usleep(1000);
    }
    lock();
    abandoned = true;
    stop.store(true, .release);
    if (!running) status = .idle;
    unlock();
    return error.HostUnavailable;
}
pub fn poll() ?forth.InputEvent {
    lock();
    defer unlock();
    if (key_count != 0) {
        const item = keys[key_head];
        if (told[item.hardware] != 0 and told[item.hardware] != item.code + 1) {
            const old = told[item.hardware] - 1;
            told[item.hardware] = 0;
            return .{ .window_key_release = old };
        }
        key_head = (key_head + 1) % keys.len;
        key_count -= 1;
        if (item.code < 512) told[item.hardware] = item.code + 1;
        return if (item.code < 512) .{ .window_key = item.code } else .{ .window_text = @intCast(item.code & 0x1fffff) };
    }
    for (&told, down) |*old, current| {
        if (old.* != 0 and old.* != current) {
            const code = old.* - 1;
            old.* = 0;
            return .{ .window_key_release = code };
        }
    }
    if (mouse_count != 0) {
        const result = mouse_queue[mouse_head];
        mouse_head = (mouse_head + 1) % mouse_queue.len;
        mouse_count -= 1;
        return result;
    }
    if (mouse_dirty) {
        mouse_dirty = false;
        return mouse_latest;
    }
    return null;
}
pub fn close() void {
    stop.store(true, .release);
    const deadline = x.now() + 5200;
    while (true) {
        lock();
        const alive = running;
        unlock();
        if (!alive or x.now() >= deadline) break;
        _ = c.usleep(1000);
    }
    lock();
    const handle = if (!running) thread else null;
    if (!running) {
        thread = null;
        status = .idle;
    }
    unlock();
    if (handle) |t| _ = c.pthread_join(t, null);
    if (take()) |frame| free(frame);
}
fn entry(_: ?*anyopaque) callconv(.c) ?*anyopaque {
    var result: ?Status = null;
    run() catch |err| {
        result = switch (err) {
            error.OutOfMemory => .oom,
            error.Unavailable => .unavailable,
            else => .failed,
        };
    };
    resetInput();
    if (take()) |frame| free(frame);
    lock();
    if (abandoned) {
        status = .idle;
    } else if (result) |value| status = value;
    running = false;
    unlock();
    return null;
}
const Window = struct {
    conn: *x.Connection,
    id: u32 = 0,
    gc: u32 = 0,
    protocols: u32 = 0,
    delete: u32 = 0,
    mapped: bool = false,
    /// The window covers its screen (EWMH fullscreen asked), and the blank cursor of
    /// MOUSE-CURSOR, once made.
    fullscreen_on: bool = false,
    blank_cursor: u32 = 0,
    /// A window opened fullscreen asks for the keys once mapped.
    activate_pending: bool = false,
    /// _NET_WM_STATE and _NET_WM_STATE_FULLSCREEN, and whether the window manager
    /// changed the window's state since applyModes last read it.
    state_atom: u32 = 0,
    fullscreen_atom: u32 = 0,
    state_dirty: bool = false,
    /// The fullscreen state last asked of the window manager and not yet seen in its
    /// _NET_WM_STATE; null when none is on the way.
    state_asked: ?bool = null,
    frame: ?Frame = null,
    width: u32 = 1,
    height: u32 = 1,
    buttons: u8 = 0,
    redraw: bool = false,
    input_method: ?xim.Client = null,
    keysyms: [256][8]u32 = @splat(@splat(0)),
    columns: usize = 0,
    num_lock_mask: u16 = 0,
    /// The modifier bit Alt_L or Alt_R is on (Mod1 when the map has none).
    alt_mask: u16 = 8,
    map_dirty: bool = false,
    pending_release: ?[32]u8 = null,
    last_key: ?[32]u8 = null,
    physical_down: [256]bool = @splat(false),
    has_focus: bool = false,
    pending_text: [4096]u21 = undefined,
    text_count: usize = 0,
    text_offset: usize = 0,
    fn wantsIme(self: *Window) bool {
        lock();
        defer unlock();
        return self.has_focus and caret.active;
    }
    fn dropIme(self: *Window) void {
        if (self.input_method) |*method| method.close();
        self.input_method = null;
        setPreedit("");
        releaseFocus();
    }
    fn enqueue(self: *Window, hardware: u8, code: u32) void {
        _ = self;
        lock();
        defer unlock();
        if (key_count == keys.len) return;
        keys[(key_head + key_count) % keys.len] = .{ .hardware = hardware, .code = code };
        key_count += 1;
    }

    fn flushText(self: *Window) void {
        lock();
        defer unlock();
        while (self.text_offset < self.text_count and key_count < keys.len) {
            const point = self.pending_text[self.text_offset];
            self.text_offset += 1;
            const physical = self.last_key;
            const hardware: u8 = if (physical) |physical_key| physical_key[1] else 0;
            const ascii = point < 128;
            const associated = ascii and physical != null and self.keyCode(&physical.?) == point;
            const source: u8 = if (associated) hardware else 0;
            if (ascii) down[source] = if (associated and self.physical_down[source]) @as(u32, point) + 1 else 0;
            keys[(key_head + key_count) % keys.len] = .{ .hardware = source, .code = if (ascii) point else @as(u32, point) | 0x1000000 };
            key_count += 1;
        }
        if (self.text_offset == self.text_count) {
            self.text_count = 0;
            self.text_offset = 0;
        }
    }
    fn pumpIme(self: *Window) x.Error!void {
        self.flushText();
        if (self.text_count != 0) return;
        if (self.input_method) |*method| {
            method.conn.deadline = x.now() + 750;
            try method.focus(self.wantsIme());
            while (try method.ready()) {
                switch (try method.next()) {
                    .none => {},
                    .symbol => |symbol| {
                        if (keysym(symbol)) |code| {
                            lock();
                            down[0] = 0;
                            unlock();
                            self.enqueue(0, code);
                        }
                    },
                    .key => |returned_key| if (returned_key[0] & 127 == 2) {
                        if (self.keyCode(&returned_key)) |code| self.enqueue(returned_key[1], code);
                    },
                    .preedit => |bytes| setPreedit(bytes),
                    .text => |bytes| {
                        var iterator = (std.unicode.Utf8View.init(bytes) catch return error.Failed).iterator();
                        self.text_count = 0;
                        self.text_offset = 0;
                        while (iterator.nextCodepoint()) |point| {
                            if (self.text_count == self.pending_text.len) return error.Failed;
                            self.pending_text[self.text_count] = point;
                            self.text_count += 1;
                        }
                        self.flushText();
                        if (self.text_count != 0) return;
                    },
                }
            }
            lock();
            const current_caret = caret;
            const dirty = caret_dirty;
            caret_dirty = false;
            unlock();
            if (dirty and method.awaiting) {
                lock();
                caret_dirty = true;
                unlock();
            }
            if (dirty and !method.awaiting and !current_caret.active) {
                try method.reset();
                setPreedit("");
            }
            if (dirty and !method.awaiting and current_caret.active) {
                if (self.frame) |frame| {
                    const rect = layout(frame.width, frame.height, self.width, self.height);
                    const px = @as(i128, rect[0]) + @divTrunc(@as(i128, current_caret.px) * rect[2], frame.width);
                    const py = @as(i128, rect[1]) + @divTrunc((@as(i128, current_caret.py) + current_caret.height) * rect[3], frame.height);
                    try method.spot(@intCast(@min(32767, @max(-32768, px))), @intCast(@min(32767, @max(-32768, py))));
                }
            }
        }
    }
    fn keymap(self: *Window) x.Error!void {
        self.keysyms = @splat(@splat(0));
        const count: usize = @as(usize, self.conn.max_key) - self.conn.min_key + 1;
        if (count > 255) return error.Unavailable;
        const reply = try self.conn.reply(try self.conn.request(101, 0, &.{ self.conn.min_key, @intCast(count), 0, 0 }));
        self.columns = reply[1];
        if (self.columns == 0 or reply.len != 32 + count * self.columns * 4) return error.Unavailable;
        for (0..count) |index| for (0..@min(self.columns, 8)) |column| {
            self.keysyms[index + self.conn.min_key][column] = x.get32(reply, 32 + (index * self.columns + column) * 4);
        };
        const modifiers = try self.conn.reply(try self.conn.request(119, 0, &.{}));
        const per_mod: usize = modifiers[1];
        if (modifiers.len < 32 + per_mod * 8) return error.Failed;
        self.num_lock_mask = 0;
        var alt: u16 = 0;
        for (0..8) |index| for (0..per_mod) |i| {
            const hardware = modifiers[32 + index * per_mod + i];
            for (self.keysyms[hardware]) |symbol| {
                if (symbol == 0xff7f) self.num_lock_mask |= @as(u16, 1) << @intCast(index);
                if (index >= 3 and (symbol == 0xffe9 or symbol == 0xffea)) alt |= @as(u16, 1) << @intCast(index);
            }
        };
        self.alt_mask = if (alt != 0) alt else 8;
    }
    fn create(self: *Window, frame: Frame) x.Error!void {
        self.has_focus = false;
        self.buttons = 0;
        self.physical_down = @splat(false);
        self.last_key = null;
        self.pending_release = null;
        // Not mapped yet: room() must not ask for the frame of a window not made.
        self.mapped = false;
        self.id = try self.conn.resource();
        self.gc = try self.conn.resource();
        const size = desired(frame, self.room());
        self.width = size[0];
        self.height = size[1];
        var body: [40]u8 = @splat(0);
        x.put32(&body, 0, self.id);
        x.put32(&body, 4, self.conn.root);
        x.put16(&body, 12, @intCast(self.width));
        x.put16(&body, 14, @intCast(self.height));
        x.put16(&body, 18, 1);
        x.put32(&body, 20, self.conn.visual);
        x.put32(&body, 24, (1 << 1) | (1 << 11));
        x.put32(&body, 32, 1 | 2 | 4 | 8 | 16 | 32 | 64 | (1 << 15) | (1 << 17) | (1 << 21) | (1 << 22)); // ... PropertyChange
        _ = try self.conn.request(1, self.conn.depth, body[0..36]);
        var protocol: [4]u8 = undefined;
        x.put32(&protocol, 0, self.delete);
        try self.property(self.protocols, 4, 32, &protocol);
        try self.property(39, 31, 8, "FORTH/Sigma graphics");
        try self.property(67, 31, 8, "sigma\x00Sigma\x00"); // WM_CLASS
        // Fullscreen asked before the window is made: it is mapped so (EWMH).
        self.fullscreen_on = false;
        self.state_dirty = false;
        self.state_asked = null;
        self.state_atom = try self.conn.atom("_NET_WM_STATE");
        self.fullscreen_atom = try self.conn.atom("_NET_WM_STATE_FULLSCREEN");
        lock();
        const open_fullscreen = fullscreen_wanted;
        fullscreen_dirty = false;
        cursor_dirty = true;
        unlock();
        self.activate_pending = open_fullscreen;
        if (open_fullscreen) {
            var state: [4]u8 = undefined;
            x.put32(&state, 0, try self.conn.atom("_NET_WM_STATE_FULLSCREEN"));
            try self.property(try self.conn.atom("_NET_WM_STATE"), 4, 32, &state);
            self.fullscreen_on = true;
        } else {
            // Do not request focus on map; a fullscreen window asks for it (G10).
            const user_time = try self.conn.atom("_NET_WM_USER_TIME");
            const zero = [_]u8{ 0, 0, 0, 0 };
            try self.property(user_time, 6, 32, &zero);
        }
        var hints: [36]u8 = @splat(0);
        x.put32(&hints, 0, 1);
        x.put32(&hints, 4, 1); // InputHint, accepts input.
        try self.property(35, 35, 32, &hints);
        var gc: [16]u8 = @splat(0);
        x.put32(&gc, 0, self.gc);
        x.put32(&gc, 4, self.id);
        x.put32(&gc, 8, 1 << 16);
        _ = try self.conn.request(55, 0, &gc); // graphics-exposures=False
        var id: [4]u8 = undefined;
        x.put32(&id, 0, self.id);
        _ = try self.conn.request(8, 0, &id);
        try self.conn.sync();
        try self.drainSaved();
        while (!self.mapped and self.id != 0) try self.event(try self.conn.next());
        if (self.id == 0) return error.Failed;
        self.input_method = xim.Client.open(self.id, @min(self.conn.deadline, x.now() + 750)) catch |err| blk: {
            if (err == error.OutOfMemory) return err;
            break :blk null;
        };
        if (self.input_method) |*method| method.focus(self.wantsIme()) catch self.dropIme();
        lock();
        caret_dirty = true;
        unlock();
    }
    /// Up to `values.len` 32-bit values of a property of `window` (CARDINAL); how many
    /// came. Nothing when the property is not there or not 32-bit.
    fn cardinals(self: *Window, window: u32, name: []const u8, first: u32, values_: []u32) x.Error!usize {
        return self.values(window, name, 6, first, values_); // CARDINAL
    }
    /// Up to `out.len` 32-bit values of a property of type `kind` (4 ATOM, 6 CARDINAL).
    fn values(self: *Window, window: u32, name: []const u8, kind: u32, first: u32, out: []u32) x.Error!usize {
        const atom = try self.conn.atom(name);
        var body: [20]u8 = @splat(0);
        x.put32(&body, 0, window);
        x.put32(&body, 4, atom);
        x.put32(&body, 8, kind);
        x.put32(&body, 12, first);
        x.put32(&body, 16, @intCast(out.len));
        const reply = try self.conn.reply(try self.conn.request(20, 0, &body));
        if (reply.len < 32 or reply[1] != 32) return 0;
        const count = @min(x.get32(reply, 16), out.len, (reply.len - 32) / 4);
        for (out[0..count], 0..) |*value, i| value.* = x.get32(reply, 32 + i * 4);
        return count;
    }

    /// The room for the client area that WINDOW-SIZE 0 0 may use: the current
    /// desktop's work area (_NET_WORKAREA), else the screen, less the frame the window
    /// manager gives this window (_NET_FRAME_EXTENTS, known once the window is
    /// mapped). A side of 0 is not known.
    fn room(self: *Window) [2]u32 {
        var area = [2]u32{ self.conn.screen_width, self.conn.screen_height };
        var desktop: [1]u32 = .{0};
        _ = self.cardinals(self.conn.root, "_NET_CURRENT_DESKTOP", 0, &desktop) catch 0;
        var work: [4]u32 = undefined;
        const got = self.cardinals(self.conn.root, "_NET_WORKAREA", @min(desktop[0], 1 << 20) * 4, &work) catch 0;
        if (got == 4 and work[2] != 0 and work[3] != 0) area = .{ work[2], work[3] };
        if (self.id != 0 and self.mapped) {
            var extents: [4]u32 = undefined; // left, right, top, bottom
            if ((self.cardinals(self.id, "_NET_FRAME_EXTENTS", 0, &extents) catch 0) == 4) {
                // A known side stays known: at least 1 pixel, never 0 (unknown).
                if (area[0] != 0) area[0] = @max(1, area[0] -| (extents[0] +| extents[1]));
                if (area[1] != 0) area[1] = @max(1, area[1] -| (extents[2] +| extents[3]));
            }
        }
        return area;
    }

    fn property(self: *Window, atom: u32, kind: u32, bits: u8, value: []const u8) x.Error!void {
        var body: [256]u8 = @splat(0);
        if (value.len > body.len - 20) return error.Failed;
        x.put32(&body, 0, self.id);
        x.put32(&body, 4, atom);
        x.put32(&body, 8, kind);
        body[12] = bits;
        x.put32(&body, 16, @intCast(value.len / (bits / 8)));
        @memcpy(body[20..][0..value.len], value);
        _ = try self.conn.request(18, 0, body[0 .. 20 + value.len]);
    }
    fn drainSaved(self: *Window) x.Error!void {
        while (self.conn.event_count != 0) {
            const saved = self.conn.events[0];
            self.conn.event_count -= 1;
            std.mem.copyForwards([32]u8, self.conn.events[0..self.conn.event_count], self.conn.events[1 .. self.conn.event_count + 1]);
            try self.event(&saved);
        }
    }
    fn event(self: *Window, bytes: []const u8) x.Error!void {
        const kind = bytes[0] & 127;
        if (self.conn.xkb_event != 0 and kind == self.conn.xkb_event) {
            if (bytes[1] == 0 or bytes[1] == 1) self.map_dirty = true;
            return;
        }
        if (((kind >= 2 and kind <= 8) and x.get32(bytes, 12) != self.id) or ((kind == 9 or kind == 10) and x.get32(bytes, 4) != self.id) or (kind == 12 and x.get32(bytes, 4) != self.id)) return;
        if (kind == 1) return error.Failed;
        // Servers without detectable autorepeat emit release/press pairs with the
        // same keycode and timestamp. Delay release until the next packet/tick.
        var paired = false;
        if (self.pending_release) |release| {
            self.pending_release = null;
            paired = kind == 2 and release[1] == bytes[1] and x.get32(&release, 4) == x.get32(bytes, 4);
            if (!paired) self.key(&release);
        }
        switch (kind) {
            2 => {
                // A press paired with the release before it is the key repeating.
                const repeat = self.physical_down[bytes[1]] or paired;
                self.physical_down[bytes[1]] = true;
                if (self.leavesFullscreen(bytes, repeat)) return;
                if (self.input_method) |*method| {
                    method.conn.deadline = self.conn.deadline;
                    self.last_key = bytes[0..32].*;
                    if (self.wantsIme()) {
                        const code = self.keyCode(bytes);
                        if (code != null and code.? < 512) {
                            lock();
                            down[bytes[1]] = code.? + 1;
                            unlock();
                        }
                        method.forward(bytes) catch {
                            self.dropIme();
                            self.key(bytes);
                        };
                    } else self.key(bytes);
                } else self.key(bytes);
            },
            3 => {
                self.physical_down[bytes[1]] = false;
                self.pending_release = bytes[0..32].*;
                if (self.input_method) |*method| {
                    method.conn.deadline = self.conn.deadline;
                    if (self.wantsIme()) method.forward(bytes) catch self.dropIme();
                }
            },
            4, 5, 6, 7, 8 => self.mouse(bytes),
            9 => {
                if (bytes[8] != 0 and bytes[8] != 3 or bytes[1] >= 5) return;
                self.has_focus = true;
                if (self.input_method) |*method| {
                    method.conn.deadline = self.conn.deadline;
                    method.focus(self.wantsIme()) catch self.dropIme();
                }
            },
            10 => {
                if (bytes[8] != 0 and bytes[8] != 3 or bytes[1] >= 5) return;
                self.has_focus = false;
                self.physical_down = @splat(false);
                self.buttons = 0;
                releaseFocus();
                if (self.input_method) |*method| {
                    method.conn.deadline = self.conn.deadline;
                    method.focus(false) catch self.dropIme();
                }
            }, // FocusOut
            12 => self.redraw = true,
            // The window manager's state of the window: fullscreen as it really is. Left
            // by the window manager itself, it is no longer wanted either.
            // No request here: applyModes reads the property after the events.
            28 => if (x.get32(bytes, 4) == self.id and self.id != 0 and x.get32(bytes, 8) == self.state_atom) {
                self.state_dirty = true;
            },
            17 => if (x.get32(bytes, 8) == self.id) {
                if (self.gc != 0) {
                    var id: [4]u8 = undefined;
                    x.put32(&id, 0, self.gc);
                    _ = try self.conn.request(60, 0, &id);
                    self.gc = 0;
                }
                self.id = 0;
                if (self.input_method) |*method| method.close();
                self.input_method = null;
                setPreedit("");
                resetInput();
                lock();
                status = .closed;
                unlock();
            },
            19 => if (x.get32(bytes, 8) == self.id) {
                self.mapped = true;
            },
            22 => if (x.get32(bytes, 8) == self.id) {
                self.width = @min(16384, @max(1, x.get16(bytes, 20)));
                self.height = @min(16384, @max(1, x.get16(bytes, 22)));
                self.redraw = true;
                lock();
                caret_dirty = true;
                unlock();
            },
            33 => if (bytes[1] == 32 and x.get32(bytes, 4) == self.id and x.get32(bytes, 8) == self.protocols and x.get32(bytes, 12) == self.delete) {
                var id: [4]u8 = undefined;
                x.put32(&id, 0, self.id);
                _ = try self.conn.request(4, 0, &id);
                if (self.gc != 0) {
                    x.put32(&id, 0, self.gc);
                    _ = try self.conn.request(60, 0, &id);
                    self.gc = 0;
                }
                self.id = 0;
                if (self.input_method) |*method| method.close();
                self.input_method = null;
                setPreedit("");
                self.mapped = false;
                self.buttons = 0;
                resetInput();
                lock();
                status = .closed;
                unlock();
            },
            34 => self.map_dirty = true,
            else => {},
        }
    }
    /// Alt+Enter (Return or the keypad's Enter with Mod1) pressed, not a repeat, while
    /// fullscreen: it leaves fullscreen and is no key for INKEY.
    fn leavesFullscreen(self: *Window, bytes: []const u8, repeat: bool) bool {
        if (!self.fullscreen_on or repeat) return false;
        const symbol = self.keysyms[bytes[1]][0];
        if ((symbol != 0xff0d and symbol != 0xff8d) or x.get16(bytes, 28) & self.alt_mask == 0) return false;
        lock();
        fullscreen_wanted = false;
        fullscreen_dirty = true;
        unlock();
        return true;
    }
    /// Takes FULLSCREEN and MOUSE-CURSOR as asked, once the window is mapped: EWMH's
    /// _NET_WM_STATE to the root (the window manager covers the screen and puts the
    /// window back), _NET_ACTIVE_WINDOW for the keys, and a blank cursor or none.
    fn applyModes(self: *Window) x.Error!void {
        if (self.id == 0 or !self.mapped) return;
        lock();
        const wanted = fullscreen_wanted;
        const modes_dirty = fullscreen_dirty;
        const visible = cursor_visible;
        const cursor_changed = cursor_dirty;
        fullscreen_dirty = false;
        cursor_dirty = false;
        unlock();
        // fullscreen_on follows the window manager (PropertyNotify of _NET_WM_STATE).
        // Left by the window manager itself, fullscreen is no longer wanted either.
        if (self.state_dirty) {
            self.state_dirty = false;
            var atoms: [16]u32 = undefined;
            const count = try self.values(self.id, "_NET_WM_STATE", 4, 0, &atoms);
            const on = std.mem.indexOfScalar(u32, atoms[0..count], self.fullscreen_atom) != null;
            if (self.state_asked) |asked| {
                // What was asked has come; a state on the way to it is not the window
                // manager's own.
                if (asked == on) self.state_asked = null;
            } else if (self.fullscreen_on and !on and !modes_dirty) {
                lock();
                if (!fullscreen_dirty) fullscreen_wanted = false;
                unlock();
            }
            self.fullscreen_on = on;
        }
        // Compared with what was asked last when that has not come yet, so that asking
        // the other way meanwhile is sent too.
        if (modes_dirty and wanted != (self.state_asked orelse self.fullscreen_on)) {
            try self.rootMessage(self.state_atom, .{ @intFromBool(wanted), self.fullscreen_atom, 0, 1, 0 });
            self.state_asked = wanted;
            if (wanted) self.activate_pending = true;
        }
        if (self.activate_pending) {
            self.activate_pending = false;
            try self.rootMessage(try self.conn.atom("_NET_ACTIVE_WINDOW"), .{ 1, 0, 0, 0, 0 });
        }
        if (cursor_changed) {
            if (!visible and self.blank_cursor == 0) {
                // A 1 by 1 cursor whose mask shows nothing.
                const pixmap = try self.conn.resource();
                var make_pixmap: [12]u8 = @splat(0);
                x.put32(&make_pixmap, 0, pixmap);
                x.put32(&make_pixmap, 4, self.id);
                x.put16(&make_pixmap, 8, 1);
                x.put16(&make_pixmap, 10, 1);
                _ = try self.conn.request(53, 1, &make_pixmap);
                // A new pixmap's bits are undefined: clear them, so the mask shows nothing.
                const clear_gc = try self.conn.resource();
                var make_gc: [16]u8 = @splat(0);
                x.put32(&make_gc, 0, clear_gc);
                x.put32(&make_gc, 4, pixmap);
                x.put32(&make_gc, 8, 1 << 2); // GCForeground
                x.put32(&make_gc, 12, 0);
                _ = try self.conn.request(55, 0, &make_gc);
                var fill: [16]u8 = @splat(0);
                x.put32(&fill, 0, pixmap);
                x.put32(&fill, 4, clear_gc);
                x.put16(&fill, 12, 1);
                x.put16(&fill, 14, 1);
                _ = try self.conn.request(70, 0, &fill);
                var free_gc: [4]u8 = undefined;
                x.put32(&free_gc, 0, clear_gc);
                _ = try self.conn.request(60, 0, &free_gc);
                self.blank_cursor = try self.conn.resource();
                var cursor: [28]u8 = @splat(0);
                x.put32(&cursor, 0, self.blank_cursor);
                x.put32(&cursor, 4, pixmap);
                x.put32(&cursor, 8, pixmap);
                _ = try self.conn.request(93, 0, &cursor);
                var free_pixmap: [4]u8 = undefined;
                x.put32(&free_pixmap, 0, pixmap);
                _ = try self.conn.request(54, 0, &free_pixmap);
            }
            var attributes: [12]u8 = @splat(0);
            x.put32(&attributes, 0, self.id);
            x.put32(&attributes, 4, 1 << 14); // CWCursor
            x.put32(&attributes, 8, if (visible) 0 else self.blank_cursor);
            _ = try self.conn.request(2, 0, &attributes);
        }
    }
    /// An EWMH client message about this window to the root window.
    fn rootMessage(self: *Window, kind: u32, data: [5]u32) x.Error!void {
        var body: [40]u8 = @splat(0);
        x.put32(&body, 0, self.conn.root);
        x.put32(&body, 4, (1 << 19) | (1 << 20)); // SubstructureNotify, SubstructureRedirect
        body[8] = 33;
        body[9] = 32;
        x.put32(&body, 12, self.id);
        x.put32(&body, 16, kind);
        for (data, 0..) |value, i| x.put32(&body, 20 + i * 4, value);
        _ = try self.conn.request(25, 0, &body);
    }
    fn key(self: *Window, bytes: []const u8) void {
        const hardware = bytes[1];
        lock();
        defer unlock();
        if (bytes[0] & 127 == 3) {
            down[hardware] = 0;
            return;
        }
        const code = self.keyCode(bytes) orelse return;
        if (code < 512) down[hardware] = code + 1;
        if (key_count == keys.len) return;
        keys[(key_head + key_count) % keys.len] = .{ .hardware = hardware, .code = code };
        key_count += 1;
    }
    fn keyCode(self: *Window, bytes: []const u8) ?u32 {
        const hardware = bytes[1];
        const modifiers = x.get16(bytes, 28);
        const symbols = self.keysyms[hardware];
        var column: usize = @as(usize, (modifiers >> 13) & 1) * 2 + (if (modifiers & 1 != 0) @as(usize, 1) else 0);
        if (modifiers & 128 != 0 and self.columns > column + 4) column += 4;
        if (symbols[column] == 0 and symbols[column & ~@as(usize, 1)] == 0) column &= 1;
        const second = symbols[(column & ~@as(usize, 1)) + 1];
        if (modifiers & self.num_lock_mask != 0 and second >= 0xffaa and second <= 0xffb9) column = (column & ~@as(usize, 1)) + (if (modifiers & 1 != 0) @as(usize, 0) else 1);
        var symbol = symbols[column];
        if (symbol == 0) symbol = symbols[column & ~@as(usize, 1)];
        if (modifiers & 2 != 0 and ((symbol >= 'a' and symbol <= 'z') or (symbol >= 'A' and symbol <= 'Z'))) symbol ^= 32;
        if (modifiers & 4 != 0) {
            if (symbol == ' ' or symbol == '2') return 0;
            if (symbol >= '3' and symbol <= '7') return symbol - '3' + 27;
            if (symbol == '8') return 127;
            if (symbol >= 0x40 and symbol <= 0x7f) return symbol & 31;
        }
        return keysym(symbol);
    }
    fn mouse(self: *Window, bytes: []const u8) void {
        const kind = bytes[0] & 127;
        const button = bytes[1];
        const old = self.buttons;
        const mask: u8 = switch (button) {
            1 => 1,
            2 => 4,
            3 => 2,
            else => 0,
        };
        if (kind == 4) self.buttons |= mask else if (kind == 5) self.buttons &= ~mask;
        const wheel: i8 = if (kind == 4 and button == 4) 1 else if (kind == 4 and button == 5) -1 else 0;
        const px: i32 = @as(i16, @bitCast(x.get16(bytes, 24)));
        const py: i32 = @as(i16, @bitCast(x.get16(bytes, 26)));
        const position = if (self.frame) |frame| imagePosition(frame, self.width, self.height, px, py) else [2]i32{ -1, -1 };
        const event_: forth.InputEvent = .{ .window_mouse = .{ .x = position[0], .y = position[1], .buttons = self.buttons, .wheel = wheel } };
        lock();
        defer unlock();
        mouse_latest = .{ .window_mouse = .{ .x = position[0], .y = position[1], .buttons = self.buttons } };
        mouse_dirty = true;
        if (old != self.buttons or wheel != 0) {
            if (mouse_count == mouse_queue.len) {
                mouse_head = (mouse_head + 1) % mouse_queue.len;
                mouse_count -= 1;
            }
            mouse_queue[(mouse_head + mouse_count) % mouse_queue.len] = event_;
            mouse_count += 1;
        }
    }
    fn draw(self: *Window) x.Error!void {
        const frame = self.frame orelse return;
        if (self.id == 0) return;
        const rect = layout(frame.width, frame.height, self.width, self.height);
        self.redraw = false;
        var body: [16380]u8 = undefined;
        const bytes_per_pixel: usize = self.conn.bits / 8;
        var y: u32 = 0;
        while (y < self.height) : (y += 1) {
            if (stop.load(.acquire) or self.redraw) return;
            self.conn.deadline = x.now() + 5000;
            var left: u32 = 0;
            while (left < self.width) {
                const width: u32 = @min(self.width - left, 2048);
                const stride = std.mem.alignForward(usize, @as(usize, width) * bytes_per_pixel, self.conn.alignment / 8);
                @memset(body[0 .. 20 + stride], 0);
                x.put32(&body, 0, self.id);
                x.put32(&body, 4, self.gc);
                x.put16(&body, 8, @intCast(width));
                x.put16(&body, 10, 1);
                x.put16(&body, 12, @intCast(left));
                x.put16(&body, 14, @intCast(y));
                body[17] = self.conn.depth;
                for (0..width) |i| {
                    const px = left + @as(u32, @intCast(i));
                    var rgb: u32 = 0;
                    if (px >= rect[0] and px < rect[0] + rect[2] and y >= rect[1] and y < rect[1] + rect[3]) {
                        const sx = @as(u64, px - rect[0]) * frame.width / rect[2];
                        const sy = @as(u64, y - rect[1]) * frame.height / rect[3];
                        rgb = frame.pixels[@intCast(sy * frame.width + sx)];
                    }
                    const value = channel(rgb >> 16, self.conn.red) | channel(rgb >> 8, self.conn.green) | channel(rgb, self.conn.blue);
                    for (0..bytes_per_pixel) |b| body[20 + i * bytes_per_pixel + b] = @truncate(value >> @as(u5, @intCast(8 * (if (self.conn.byte_order == 0) b else bytes_per_pixel - 1 - b))));
                }
                _ = try self.conn.request(72, 2, body[0 .. 20 + stride]);
                left += width;
            }
            // Bound buffered events while also keeping Expose/close/input responsive.
            while (try self.conn.ready()) {
                try self.event(try self.conn.next());
                if (self.id == 0) return;
            }
        }
    }
};
fn channel(value: u32, mask: u32) u32 {
    const shift: u5 = @intCast(@ctz(mask));
    const maximum = mask >> shift;
    return @as(u32, @intCast((@as(u64, value & 255) * maximum + 127) / 255)) << shift;
}
fn keysym(symbol: u32) ?u32 {
    return switch (symbol) {
        1...0x1f => symbol,
        0xfe20 => 9,
        0xff8d => 13,
        0xff95 => 260,
        0xff96 => 258,
        0xff97 => 256,
        0xff98 => 259,
        0xff99 => 257,
        0xff9a => 262,
        0xff9b => 263,
        0xff9c => 261,
        0xff9e => 264,
        0xff9f => 265,
        0xffbd => 61,
        0xffaa...0xffaf => symbol - 0xff80,
        0xffb0...0xffb9 => symbol - 0xff80,
        0xff08 => 8,
        0xff09 => 9,
        0xff0d => 13,
        0xff1b => 27,
        0xff52 => 256,
        0xff54 => 257,
        0xff51 => 258,
        0xff53 => 259,
        0xff50 => 260,
        0xff57 => 261,
        0xff55 => 262,
        0xff56 => 263,
        0xff63 => 264,
        0xffff => 265,
        0xffbe...0xffc9 => 266 + symbol - 0xffbe,
        0x20...0x7f => symbol,
        0x80...0xff => symbol | 0x1000000,
        0x01000100...0x0110ffff => if (symbol & 0xffffff >= 0xd800 and symbol & 0xffffff <= 0xdfff) null else (symbol & 0xffffff) | 0x1000000,
        else => null,
    };
}
/// The window's size: what WINDOW-SIZE gave, or for 0 0 the image's size by
/// window_layout, which also fits `room` (the work area less the frame).
fn desired(frame: Frame, room: [2]u32) [2]u32 {
    if (frame.requested[0] != 0 and frame.requested[1] != 0) return frame.requested;
    return window_layout.autoClientSize(frame.width, frame.height, room);
}
fn layout(iw: u32, ih: u32, w: u32, h: u32) [4]u32 {
    var rw = w;
    var rh = h;
    if (@as(u64, w) * ih <= @as(u64, h) * iw) rh = @intCast(@max(1, @as(u64, w) * ih / iw)) else rw = @intCast(@max(1, @as(u64, h) * iw / ih));
    return .{ (w - rw) / 2, (h - rh) / 2, rw, rh };
}
fn imagePosition(frame: Frame, w: u32, h: u32, px: i32, py: i32) [2]i32 {
    const rect = layout(frame.width, frame.height, w, h);
    return .{ @intCast(@divFloor((@as(i64, px) - rect[0]) * frame.width, rect[2])), @intCast(@divFloor((@as(i64, py) - rect[1]) * frame.height, rect[3])) };
}
fn run() x.Error!void {
    var conn = try x.Connection.openUntil(start_deadline);
    defer conn.close();
    var window: Window = .{ .conn = &conn };
    defer if (window.frame) |frame| free(frame);
    defer if (window.input_method) |*method| method.close();
    window.protocols = try conn.atom("WM_PROTOCOLS");
    window.delete = try conn.atom("WM_DELETE_WINDOW");
    try window.keymap();
    _ = try conn.enableDetectableRepeat();
    while (!stop.load(.acquire)) {
        conn.deadline = x.now() + 5000;
        if (take()) |frame| {
            const previous = window.frame;
            const resize = if (previous) |old| old.width != frame.width or old.height != frame.height or !std.mem.eql(u32, &old.requested, &frame.requested) else true;
            window.frame = frame;
            if (previous) |old| free(old);
            if (window.id == 0) {
                conn.deadline = frame.deadline;
                try window.create(frame);
            } else if (resize and !window.fullscreen_on) {
                // A fullscreen window keeps covering its screen.
                const size = desired(frame, window.room());
                var body: [16]u8 = @splat(0);
                x.put32(&body, 0, window.id);
                x.put16(&body, 4, 12);
                x.put32(&body, 8, size[0]);
                x.put32(&body, 12, size[1]);
                _ = try conn.request(12, 0, &body);
            }
            if (stop.load(.acquire)) break;
            window.redraw = true;
            lock();
            if (abandoned or stop.load(.acquire)) {
                unlock();
                break;
            }
            status = .ready;
            unlock();
        }
        if (window.map_dirty) {
            window.map_dirty = false;
            try window.keymap();
            _ = try conn.enableDetectableRepeat();
        }
        try window.drainSaved();
        while (try conn.ready()) try window.event(try conn.next());
        window.pumpIme() catch window.dropIme();
        try window.applyModes();
        if (window.pending_release) |release| {
            window.pending_release = null;
            window.key(&release);
        }
        if (window.redraw) try window.draw();
        _ = c.usleep(2000);
    }
}

test "X11 letterbox coordinates preserve outside and nearest sampling" {
    const frame: Frame = .{ .pixels = &.{}, .width = 3, .height = 2, .requested = .{ 0, 0 } };
    try std.testing.expectEqual([4]u32{ 0, 2, 10, 6 }, layout(3, 2, 10, 10));
    try std.testing.expectEqual([2]i32{ 1, -1 }, imagePosition(frame, 10, 10, 5, 1));
    try std.testing.expectEqual([2]i32{ 2, 1 }, imagePosition(frame, 10, 10, 9, 7));
}

test "X11 group fallback, NumLock and Control keep their key meanings" {
    var window: Window = .{ .conn = undefined, .columns = 4, .num_lock_mask = 16 };
    var event_: [32]u8 = @splat(0);
    event_[1] = 36;
    window.keysyms[36][0] = 0xff0d;
    x.put16(&event_, 28, 1 << 13);
    try std.testing.expectEqual(@as(?u32, 13), window.keyCode(&event_));
    event_[1] = 90;
    window.keysyms[90][0] = 0xff9e;
    window.keysyms[90][1] = 0xffb0;
    x.put16(&event_, 28, 16);
    try std.testing.expectEqual(@as(?u32, '0'), window.keyCode(&event_));
    x.put16(&event_, 28, 17);
    try std.testing.expectEqual(@as(?u32, 264), window.keyCode(&event_));
    event_[1] = 38;
    window.keysyms[38][0] = 'c';
    x.put16(&event_, 28, 4);
    try std.testing.expectEqual(@as(?u32, 3), window.keyCode(&event_));
}
