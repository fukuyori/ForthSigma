//! Local X11/XWayland window, enabled by default; -Dx11=false omits it.
//! Physical keys use XKB position names independently of text/IME input.
const std = @import("std");
const physical_keys = @import("core/physical_keys.zig");
var physical_state: physical_keys.Host = .{};
pub fn physicalQuery(req: physical_keys.Request) physical_keys.Response {
    lock();
    defer unlock();
    return physical_state.request(req);
}

const forth = @import("forth.zig");
const x = @import("host_x11.zig");
const xim = @import("host_xim.zig");
const window_layout = @import("window_layout.zig");
const display_info = @import("core/display_info.zig");
const c = x.c;
const allocator = std.heap.c_allocator;
const Status = enum { idle, starting, ready, closed, unavailable, failed, oom };
/// An image SHOW gave; `serial` is its place in the count of images given (WINDOW-FRAMES).
const Frame = struct { pixels: []u32, width: u32, height: u32, requested: [2]u32, deadline: i64 = 0, serial: u64 = 0 };
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
    physical_state.tracker.releaseAll();
    mouse_latest.window_mouse.buttons = 0;
    mouse_dirty = true;
    preedit_len = 0;
}

/// The window as it is now, for WINDOW-PIXELS, WINDOW-CHANGES, WINDOW-OPEN?,
/// WINDOW-FOCUSED?, WINDOW-MINIMIZED?, WINDOW-CLOSES, and WINDOW-IMAGE-RECT (tque 1265,
/// 1296), and the place of its drawable part in the X screen, for WINDOW-DISPLAY. The
/// window thread puts them here, under the lock; the counts stay when the window goes.
var shared: display_info.WindowState = .{};
var shared_origin: [2]i32 = .{ 0, 0 };
/// The size of the image the last SHOW gave, so that WINDOW-IMAGE-RECT is reckoned from
/// WINDOW-FIT and that image as they are when asked, as on Windows. Only show() sets
/// it (forget() clears it): the window thread may still draw an older image.
var shared_image: [2]u32 = .{ 0, 0 };

/// WINDOW-FIT and WINDOW-SMOOTH as last asked (tque 1285, 1319), under the lock; kept
/// when the window goes. `layout_dirty`: the window thread takes them and draws again.
var fit_mode: window_layout.Fit = .aspect;
var smooth_on = false;
var layout_dirty = false;

/// WINDOW-KEEP-OPEN (tque 1327), under the lock: the user's closing is counted and the
/// window stays. `close_unseen`: the user asked so and the program has not read
/// WINDOW-CLOSES since; asking again then closes the window, as on Windows.
var keep_open = false;
var close_unseen = false;

/// The user asked to close the window (WM_DELETE_WINDOW); whether it closes. Counted.
fn closeAsked() bool {
    lock();
    defer unlock();
    shared.closes += 1;
    if (keep_open and !close_unseen) {
        close_unseen = true;
        return false;
    }
    close_unseen = false;
    return true;
}

/// The host's window_close_fn: 0 and 1 WINDOW-KEEP-OPEN false and true, 2 WINDOW-CLOSE
/// (the program closes the window, not counted; the next SHOW opens it again), 3
/// WINDOW-CLOSES: the count, taken as read in the same step.
pub fn windowClose(what: u8) u64 {
    if (what == 2) {
        close();
        lock();
        close_unseen = false;
        unlock();
    }
    lock();
    defer unlock();
    switch (what) {
        0, 1 => {
            keep_open = what == 1;
            if (!keep_open) close_unseen = false;
        },
        3 => close_unseen = false,
        else => {},
    }
    return shared.closes;
}

/// WINDOW-PAINT-WAIT: waits until the window has drawn the whole of the image the last
/// SHOW gave, `ms` milliseconds at most; false at once without the window, when it goes
/// meanwhile, and when the time runs out (a minimized window does not count as drawn).
pub fn frameWait(ms: u32) bool {
    const deadline = x.now() + ms;
    while (true) {
        lock();
        const open = shared.open;
        const done = shared.frames_painted >= shared.frames_shown;
        unlock();
        if (!open) return false;
        if (done) return true;
        if (x.now() >= deadline) return false;
        _ = c.usleep(1000);
    }
}

/// The host's window_fit_fn.
pub fn windowFit(fit: u8) void {
    lock();
    defer unlock();
    fit_mode = @enumFromInt(fit);
    layout_dirty = true;
}

/// The host's window_smooth_fn.
pub fn windowSmooth(on: bool) void {
    lock();
    defer unlock();
    smooth_on = on;
    layout_dirty = true;
}

/// The host's window_state_fn.
pub fn windowState() display_info.WindowState {
    lock();
    defer unlock();
    var state = shared;
    if (state.open and shared_image[0] != 0) state.view = layout(fit_mode, shared_image[0], shared_image[1], state.width, state.height);
    return state;
}

/// The host's window_display_fn: the monitor most of the window is on, as
/// host_display_linux.zig names it; null without the window, or when the X server does
/// not tell. `id` 0 is this window; no other window is known yet.
pub fn windowDisplay(id: u64) ?u64 {
    if (id != 0) return null;
    lock();
    const state = shared;
    const origin = shared_origin;
    unlock();
    if (!state.open) return null;
    return @import("host_display_linux.zig").monitorOf(.{ origin[0], origin[1], state.width, state.height });
}

/// The window is gone: no size, no focus, not minimized, and that is a change.
fn forget() void {
    lock();
    defer unlock();
    if (shared.open) shared.changes += 1;
    shared = .{ .changes = shared.changes, .closes = shared.closes, .frames_shown = shared.frames_shown, .frames_painted = shared.frames_painted };
    shared_image = .{ 0, 0 };
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
    // The window is closing (WINDOW-CLOSE, or close() whose wait ran out): its thread
    // is waited for, so that this SHOW opens the window again.
    while (running and stop.load(.acquire)) {
        unlock();
        if (x.now() >= deadline) {
            allocator.free(pixels);
            return error.HostUnavailable;
        }
        _ = c.usleep(1000);
        lock();
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
    shared.frames_shown += 1;
    mailbox = .{ .pixels = pixels, .width = width, .height = height, .requested = requested, .deadline = if (status == .starting) start_deadline else x.now() + 5000, .serial = shared.frames_shown };
    // WINDOW-IMAGE-RECT is reckoned from this image from now on, as on Windows.
    shared_image = .{ width, height };
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
    forget();
    if (take()) |frame| free(frame);
    lock();
    if (abandoned) {
        status = .idle;
    } else if (result) |value| status = value;
    running = false;
    physical_state.close();
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
    normal_rect: ?window_layout.ScreenRect = null,
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
    /// Minimized: the window manager's WM_STATE says iconic (read again after the
    /// window was unmapped or the property changed: an unmapping alone may be the
    /// window manager taking the window into its frame, or the window going), or
    /// _NET_WM_STATE_HIDDEN is in its state.
    iconic: bool = false,
    iconic_dirty: bool = false,
    wm_state_atom: u32 = 0,
    hidden: bool = false,
    hidden_atom: u32 = 0,
    /// The window was moved or resized: where it is, and on which monitor, is asked
    /// again. `origin` is the drawable part's corner in the X screen; `on_monitor` the
    /// monitor most of it is on, by the name WINDOW-DISPLAY gives.
    geometry_dirty: bool = true,
    origin: [2]i32 = .{ 0, 0 },
    on_monitor: ?u64 = null,
    randr: @import("host_display_linux.zig").Randr = .{},
    /// The pointer's last place in the window, so that MOUSE tells the image's pixel
    /// under it again when WINDOW-FIT changes; null before it was in the window.
    pointer: ?[2]i32 = null,
    /// WINDOW-FIT and WINDOW-SMOOTH as the window draws now, and the memory to make
    /// the rows of the image at the size it is shown: the image's column for each
    /// column shown, one row, and what the smooth drawing needs.
    fit: window_layout.Fit = .aspect,
    smooth: bool = false,
    scale_columns: []u32 = &.{},
    scale_row: []u32 = &.{},
    smoother: window_layout.Smooth = .{},
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
    physical_dirty: bool = false,
    scan_map: [256]u8 = @splat(0),
    scan_valid: bool = false,
    pending_release: ?[32]u8 = null,
    last_key: ?[32]u8 = null,
    physical_down: [256]bool = @splat(false),
    has_focus: bool = false,
    pending_text: [4096]u21 = undefined,
    text_count: usize = 0,
    text_offset: usize = 0,
    fn physicalNames(self: *Window) x.Error!void {
        const next = self.conn.physicalNames() catch |err| {
            if (err != error.Unavailable and err != error.XError) return err;
            self.scan_map = @splat(0);
            self.scan_valid = false;
            lock();
            defer unlock();
            physical_state.tracker.boundary();
            physical_state.available = false;
            physical_state.supported = @splat(0);
            return;
        };
        lock();
        defer unlock();
        if (self.scan_valid and !std.mem.eql(u8, &self.scan_map, &next)) physical_state.tracker.boundary();
        self.scan_map = next;
        self.scan_valid = false;
        for (next) |scan| if (scan >= 4) {
            self.scan_valid = true;
            break;
        };
        physical_state.supported = @splat(0);
        for (next) |scan| physical_state.support(scan);
        physical_state.available = self.id != 0 and self.scan_valid;
    }

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
                    const rect = layout(self.fit, frame.width, frame.height, self.width, self.height);
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
        var owner_pid: [4]u8 = undefined;
        x.put32(&owner_pid, 0, @intCast(c.getpid()));
        try self.property(try self.conn.atom("_NET_WM_PID"), 6, 32, &owner_pid);
        // Fullscreen asked before the window is made: it is mapped so (EWMH).
        self.fullscreen_on = false;
        self.normal_rect = null;
        self.state_dirty = false;
        self.state_asked = null;
        self.state_atom = try self.conn.atom("_NET_WM_STATE");
        self.fullscreen_atom = try self.conn.atom("_NET_WM_STATE_FULLSCREEN");
        self.hidden_atom = try self.conn.atom("_NET_WM_STATE_HIDDEN");
        self.wm_state_atom = try self.conn.atom("WM_STATE");
        self.iconic = false;
        self.iconic_dirty = false;
        self.hidden = false;
        self.geometry_dirty = true;
        self.on_monitor = null;
        self.pointer = null;
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

    /// Xinerama is also exposed by RandR/XWayland servers. Query it directly,
    /// without a library dependency. Re-query so display layout changes are seen.
    fn monitor(self: *Window) x.Error!?window_layout.ScreenRect {
        var query: [12]u8 = @splat(0);
        x.put16(&query, 0, 8);
        @memcpy(query[4..], "XINERAMA");
        const extension = try self.conn.reply(try self.conn.request(98, 0, &query));
        if (extension[8] == 0) return null;
        const opcode = extension[9];
        const screens = try self.conn.reply(try self.conn.request(opcode, 5, &.{}));
        const count = x.get32(screens, 8);
        if (count == 0 or count > 256 or screens.len < 32 + @as(usize, count) * 8) return null;
        var monitors: [256]window_layout.ScreenRect = undefined;
        for (monitors[0..count], 0..) |*rect, i| {
            const offset = 32 + i * 8;
            rect.* = .{ .x = @as(i16, @bitCast(x.get16(screens, offset))), .y = @as(i16, @bitCast(x.get16(screens, offset + 2))), .w = x.get16(screens, offset + 4), .h = x.get16(screens, offset + 6) };
        }
        // Before mapping, choose the pointer's monitor. Afterwards use the window's
        // largest overlap, translating through any WM reparenting to root coordinates.
        var target: window_layout.ScreenRect = undefined;
        if (self.mapped) {
            var body: [12]u8 = @splat(0);
            x.put32(&body, 0, self.id);
            x.put32(&body, 4, self.conn.root);
            const position = try self.conn.reply(try self.conn.request(40, 0, &body));
            if (position[1] == 0) return null;
            target = .{ .x = @as(i16, @bitCast(x.get16(position, 12))), .y = @as(i16, @bitCast(x.get16(position, 14))), .w = self.width, .h = self.height };
        } else {
            var body: [4]u8 = undefined;
            x.put32(&body, 0, self.conn.root);
            const pointer = try self.conn.reply(try self.conn.request(38, 0, &body));
            if (pointer[1] == 0) return null;
            target = .{ .x = @as(i16, @bitCast(x.get16(pointer, 16))), .y = @as(i16, @bitCast(x.get16(pointer, 18))), .w = 1, .h = 1 };
        }
        return window_layout.selectMonitor(monitors[0..count], target);
    }

    /// Intersect the desktop work area with this window's monitor before removing
    /// decorations. Without monitor information retain the core-screen fallback.
    fn room(self: *Window) [2]u32 {
        const bounds = self.monitor() catch null;
        var desktop: [1]u32 = .{0};
        _ = self.cardinals(self.conn.root, "_NET_CURRENT_DESKTOP", 0, &desktop) catch 0;
        var work: [4]u32 = undefined;
        const got = self.cardinals(self.conn.root, "_NET_WORKAREA", @min(desktop[0], 1 << 20) * 4, &work) catch 0;
        var area = [2]u32{ self.conn.screen_width, self.conn.screen_height };
        if (bounds) |monitor_rect| area = .{ monitor_rect.w, monitor_rect.h };
        if (got == 4 and work[2] != 0 and work[3] != 0) {
            const work_rect: window_layout.ScreenRect = .{ .x = @as(i32, @bitCast(work[0])), .y = @as(i32, @bitCast(work[1])), .w = work[2], .h = work[3] };
            if (bounds) |monitor_rect| {
                area = window_layout.workRoom(monitor_rect, work_rect);
            } else area = .{ work[2], work[3] };
        }
        if (self.id != 0 and self.mapped) {
            var extents: [4]u32 = undefined;
            if ((self.cardinals(self.id, "_NET_FRAME_EXTENTS", 0, &extents) catch 0) == 4) {
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
            if (bytes[1] == 0 or bytes[1] == 6) self.physical_dirty = true;
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
                lock();
                physical_state.update(self.scan_map[bytes[1]], true);
                unlock();
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
            28 => if (x.get32(bytes, 4) == self.id and self.id != 0) {
                if (x.get32(bytes, 8) == self.state_atom) self.state_dirty = true;
                if (x.get32(bytes, 8) == self.wm_state_atom) self.iconic_dirty = true;
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
                physical_state.close();
                status = .closed;
                unlock();
            },
            // Unmapped or mapped: whether the window manager minimized it is read from
            // its WM_STATE.
            18 => if (x.get32(bytes, 8) == self.id and self.id != 0) {
                self.iconic_dirty = true;
            },
            19 => if (x.get32(bytes, 8) == self.id) {
                self.mapped = true;
                self.iconic_dirty = true;
                self.geometry_dirty = true;
            },
            22 => if (x.get32(bytes, 8) == self.id) {
                self.width = @min(16384, @max(1, x.get16(bytes, 20)));
                self.height = @min(16384, @max(1, x.get16(bytes, 22)));
                self.redraw = true;
                self.geometry_dirty = true;
                lock();
                caret_dirty = true;
                unlock();
            },
            33 => if (bytes[1] == 32 and x.get32(bytes, 4) == self.id and x.get32(bytes, 8) == self.protocols and x.get32(bytes, 12) == self.delete) {
                // The user's closing (the window manager's close button or key): counted,
                // and with WINDOW-KEEP-OPEN the window stays.
                if (!closeAsked()) return;
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
                physical_state.close();
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
            self.hidden = std.mem.indexOfScalar(u32, atoms[0..count], self.hidden_atom) != null;
            if (self.state_asked) |asked| {
                // What was asked has come; a state on the way to it is not the window
                // manager's own.
                if (asked == on) self.state_asked = null;
            } else if (self.fullscreen_on and !on and !modes_dirty) {
                lock();
                if (!fullscreen_dirty) fullscreen_wanted = false;
                unlock();
            }
            if (self.fullscreen_on and !on) {
                if (self.normal_rect) |rect| {
                    // Restore the frame origin with NorthWestGravity after the WM's
                    // fullscreen restore. The WM retains the previous client size.
                    try self.rootMessage(try self.conn.atom("_NET_MOVERESIZE_WINDOW"), .{
                        1 | (3 << 8) | (1 << 12),
                        @bitCast(@as(i32, @intCast(rect.x))),
                        @bitCast(@as(i32, @intCast(rect.y))),
                        0,
                        0,
                    });
                    self.normal_rect = null;
                }
            }
            self.fullscreen_on = on;
        }
        // Compared with what was asked last when that has not come yet, so that asking
        // the other way meanwhile is sent too.
        if (modes_dirty and wanted != (self.state_asked orelse self.fullscreen_on)) {
            if (wanted and !self.fullscreen_on and self.normal_rect == null) {
                var translate: [12]u8 = @splat(0);
                x.put32(&translate, 0, self.id);
                x.put32(&translate, 4, self.conn.root);
                const position = try self.conn.reply(try self.conn.request(40, 0, &translate));
                if (position[1] != 0) {
                    const px: i64 = @as(i16, @bitCast(x.get16(position, 12)));
                    const py: i64 = @as(i16, @bitCast(x.get16(position, 14)));
                    var extents: [4]u32 = @splat(0);
                    _ = self.cardinals(self.id, "_NET_FRAME_EXTENTS", 0, &extents) catch 0;
                    self.normal_rect = .{ .x = px - extents[0], .y = py - extents[2], .w = self.width, .h = self.height };
                }
            }
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
    /// Puts the window as it is now where the Forth side reads it. Where the window is
    /// in the X screen, and the monitor most of it is on (as WINDOW-DISPLAY finds it),
    /// are asked again only after it was moved or resized. The count of changes goes
    /// up when the window comes or goes, when its size changes, and when it is on
    /// another monitor. What the server does not tell stays as it was: asking does not
    /// end the window.
    fn publish(self: *Window) void {
        var next: display_info.WindowState = .{};
        var moved = false;
        if (self.id != 0) {
            if (self.iconic_dirty) self.readIconic();
            if (self.geometry_dirty and self.mapped) {
                self.geometry_dirty = false;
                self.locate() catch {};
                // X places are 16 bits: a window is not beyond 32767.
                // Not asked (an X error, no answer in time): as it was, and no change.
                const now = @import("host_display_linux.zig").monitorOn(self.conn, &self.randr, .{ self.origin[0], self.origin[1], self.width, self.height }) catch self.on_monitor;
                if (now != self.on_monitor) moved = true;
                self.on_monitor = now;
            }
            next.open = true;
            next.width = self.width;
            next.height = self.height;
            next.focused = self.has_focus;
            next.minimized = self.iconic or self.hidden;
            if (self.frame) |frame| next.view = layout(self.fit, frame.width, frame.height, self.width, self.height);
        }
        lock();
        defer unlock();
        const changed = moved or next.open != shared.open or next.width != shared.width or next.height != shared.height;
        next.changes = shared.changes + @intFromBool(changed);
        next.closes = shared.closes;
        next.frames_shown = shared.frames_shown;
        next.frames_painted = shared.frames_painted;
        shared = next;
        if (next.open) shared_origin = self.origin;
    }
    /// Whether the window manager has the window iconic: WM_STATE's first value is 3
    /// (ICCCM). Not told: not iconic.
    fn readIconic(self: *Window) void {
        self.iconic_dirty = false;
        var state: [1]u32 = .{0};
        const got = self.values(self.id, "WM_STATE", 0, 0, &state) catch 0;
        self.iconic = got == 1 and state[0] == 3;
    }
    /// Whether _NET_WM_STATE_HIDDEN is in the window's state. state_dirty is left for
    /// applyModes, which reads the fullscreen state from the same property.
    fn readHidden(self: *Window) void {
        var atoms: [16]u32 = undefined;
        const count = self.values(self.id, "_NET_WM_STATE", 4, 0, &atoms) catch return;
        self.hidden = std.mem.indexOfScalar(u32, atoms[0..count], self.hidden_atom) != null;
    }
    /// The corner of the drawable part in the X screen, through the window manager's
    /// frame.
    fn locate(self: *Window) x.Error!void {
        var body: [12]u8 = @splat(0);
        x.put32(&body, 0, self.id);
        x.put32(&body, 4, self.conn.root);
        const position = try self.conn.reply(try self.conn.request(40, 0, &body));
        if (position[1] != 0) self.origin = .{ @as(i16, @bitCast(x.get16(position, 12))), @as(i16, @bitCast(x.get16(position, 14))) };
    }
    /// Memory for a row of `width` pixels shown; false without it.
    fn scaleMemory(self: *Window, width: u32) bool {
        if (self.scale_row.len >= width) return true;
        const columns = allocator.alloc(u32, width) catch return false;
        const row = allocator.alloc(u32, width) catch {
            allocator.free(columns);
            return false;
        };
        self.freeScale();
        self.scale_columns = columns;
        self.scale_row = row;
        return true;
    }
    fn freeScale(self: *Window) void {
        if (self.scale_row.len != 0) {
            allocator.free(self.scale_columns);
            allocator.free(self.scale_row);
        }
        self.scale_columns = &.{};
        self.scale_row = &.{};
    }
    /// WINDOW-FIT and WINDOW-SMOOTH as last asked: taken, and the image drawn again
    /// (the input method's caret goes where the image's place is now).
    fn takeLayout(self: *Window) void {
        lock();
        const dirty = layout_dirty;
        layout_dirty = false;
        const fit = fit_mode;
        const smooth = smooth_on;
        if (dirty) caret_dirty = true;
        unlock();
        if (fit != self.fit or smooth != self.smooth) self.redraw = true;
        const relaid = fit != self.fit;
        self.fit = fit;
        self.smooth = smooth;
        // The image is elsewhere now: MOUSE tells the pixel under the pointer again,
        // without the pointer moving (as Windows does).
        if (relaid) if (self.pointer) |place| if (self.frame) |frame| {
            const position = imagePosition(self.fit, frame, self.width, self.height, place[0], place[1]);
            lock();
            defer unlock();
            mouse_latest = .{ .window_mouse = .{ .x = position[0], .y = position[1], .buttons = self.buttons } };
            mouse_dirty = true;
        };
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
            physical_state.update(self.scan_map[hardware], false);
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
        self.pointer = .{ px, py };
        const position = if (self.frame) |frame| imagePosition(self.fit, frame, self.width, self.height, px, py) else [2]i32{ -1, -1 };
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
    /// Draws the image; true when the whole of it was drawn (not cut short by a new
    /// size, by stopping, or by the window going).
    fn draw(self: *Window) x.Error!bool {
        const frame = self.frame orelse return false;
        if (self.id == 0) return false;
        const rect = layout(self.fit, frame.width, frame.height, self.width, self.height);
        self.redraw = false;
        // The rows of the image at the size shown are made as Windows makes them
        // (window_layout): by the pixel each place falls in, or with WINDOW-SMOOTH by
        // the mean of what it covers (the same by whole factors). Without memory for
        // them each pixel is taken by itself, as before.
        const scaled = self.scaleMemory(rect[2]);
        if (scaled) window_layout.sourceColumns(self.scale_columns, frame.width, rect[2]);
        const by_area = scaled and self.smooth and (rect[2] % frame.width != 0 or rect[3] % frame.height != 0) and self.smoother.fit(allocator, rect[2]);
        if (by_area) self.smoother.begin(frame.width, rect[2]);
        var body: [16380]u8 = undefined;
        const bytes_per_pixel: usize = self.conn.bits / 8;
        var y: u32 = 0;
        while (y < self.height) : (y += 1) {
            if (stop.load(.acquire) or self.redraw) return false;
            self.conn.deadline = x.now() + 5000;
            const inside = y >= rect[1] and y < rect[1] + rect[3];
            if (scaled and inside) {
                if (by_area) {
                    window_layout.smoothRows(&self.smoother, frame.pixels, frame.width, frame.height, self.scale_row, rect[2], rect[3], y - rect[1], 1);
                } else {
                    window_layout.scaleRows(frame.pixels, frame.width, frame.height, self.scale_row, rect[2], rect[3], self.scale_columns, y - rect[1], 1);
                }
            }
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
                    if (px >= rect[0] and px < rect[0] + rect[2] and inside) {
                        if (scaled) {
                            rgb = self.scale_row[px - rect[0]];
                        } else {
                            const sx = @as(u64, px - rect[0]) * frame.width / rect[2];
                            const sy = @as(u64, y - rect[1]) * frame.height / rect[3];
                            rgb = frame.pixels[@intCast(sy * frame.width + sx)];
                        }
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
                if (self.id == 0) return false;
            }
        }
        // A new size or another reason to draw again, met on the last row: not drawn whole.
        return !self.redraw;
    }
    /// After the whole image was drawn: once the server has done what it was sent, the
    /// image counts as drawn for WINDOW-FRAMES and WINDOW-PAINT-WAIT, unless the window
    /// is minimized (nothing shows then, as on Windows).
    fn painted(self: *Window) x.Error!void {
        const frame = self.frame orelse return;
        // The server's answer to a request sent after the drawing tells that it has done
        // the drawing. The events that come before the answer are handled as they come,
        // in order, not kept (there is room for only so many).
        try self.drainSaved();
        const sequence = try self.conn.request(43, 0, &.{}); // GetInputFocus
        while (true) {
            const bytes = try self.conn.next();
            if (bytes[0] == 1) {
                if (x.get16(bytes, 2) != sequence) return error.Failed;
                break;
            }
            try self.event(bytes);
        }
        try self.drainSaved();
        // Changed meanwhile (a new size, an exposure, the window gone): drawn again first.
        if (self.id == 0 or self.redraw) return;
        // Minimized meanwhile: read now, not at the next turn of the loop.
        if (self.iconic_dirty) self.readIconic();
        if (self.state_dirty) self.readHidden();
        if (self.iconic or self.hidden) return;
        lock();
        defer unlock();
        if (frame.serial > shared.frames_painted) shared.frames_painted = frame.serial;
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
/// x y w h of the rectangle the image is drawn in, as WINDOW-FIT lays it out
/// (window_layout.placeFit, as on Windows).
fn layout(fit: window_layout.Fit, iw: u32, ih: u32, w: u32, h: u32) [4]u32 {
    const rect = window_layout.placeFit(fit, iw, ih, w, h);
    return .{ rect.x, rect.y, rect.w, rect.h };
}
fn imagePosition(fit: window_layout.Fit, frame: Frame, w: u32, h: u32, px: i32, py: i32) [2]i32 {
    const rect = layout(fit, frame.width, frame.height, w, h);
    return .{ @intCast(@divFloor((@as(i64, px) - rect[0]) * frame.width, rect[2])), @intCast(@divFloor((@as(i64, py) - rect[1]) * frame.height, rect[3])) };
}
fn run() x.Error!void {
    var conn = try x.Connection.openUntil(start_deadline);
    defer conn.close();
    var window: Window = .{ .conn = &conn };
    defer if (window.frame) |frame| free(frame);
    defer if (window.input_method) |*method| method.close();
    defer window.freeScale();
    defer window.smoother.free(allocator);
    window.protocols = try conn.atom("WM_PROTOCOLS");
    window.delete = try conn.atom("WM_DELETE_WINDOW");
    try window.keymap();
    _ = try conn.enableDetectableRepeat();
    try window.physicalNames();
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
            physical_state.available = window.scan_valid;
            unlock();
            // The state is there before SHOW returns: WINDOW-PIXELS just after SHOW
            // tells of this window, with WINDOW-FIT as asked before it.
            window.takeLayout();
            window.publish();
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
        if (window.physical_dirty) {
            window.physical_dirty = false;
            try window.physicalNames();
        }
        try window.drainSaved();
        while (try conn.ready()) try window.event(try conn.next());
        window.pumpIme() catch window.dropIme();
        try window.applyModes();
        window.takeLayout();
        window.publish();
        // Events that came while the server was asked are handled before newer ones.
        try window.drainSaved();
        if (window.pending_release) |release| {
            window.pending_release = null;
            window.key(&release);
        }
        if (window.redraw) {
            if (try window.draw()) try window.painted();
        }
        _ = c.usleep(2000);
    }
}

test "X11 letterbox coordinates preserve outside and nearest sampling" {
    const frame: Frame = .{ .pixels = &.{}, .width = 3, .height = 2, .requested = .{ 0, 0 } };
    try std.testing.expectEqual([4]u32{ 0, 2, 10, 6 }, layout(.aspect, 3, 2, 10, 10));
    try std.testing.expectEqual([2]i32{ 1, -1 }, imagePosition(.aspect, frame, 10, 10, 5, 1));
    try std.testing.expectEqual([2]i32{ 2, 1 }, imagePosition(.aspect, frame, 10, 10, 9, 7));
    // WINDOW-FIT: by whole factors (3 times, 9 by 6 in the middle), and over the whole.
    try std.testing.expectEqual([4]u32{ 0, 2, 9, 6 }, layout(.whole, 3, 2, 10, 10));
    try std.testing.expectEqual([2]i32{ 1, 0 }, imagePosition(.whole, frame, 10, 10, 5, 2));
    try std.testing.expectEqual([2]i32{ 3, 1 }, imagePosition(.whole, frame, 10, 10, 9, 7));
    try std.testing.expectEqual([4]u32{ 0, 0, 10, 10 }, layout(.stretch, 3, 2, 10, 10));
    try std.testing.expectEqual([2]i32{ 1, 0 }, imagePosition(.stretch, frame, 10, 10, 5, 1));
    try std.testing.expectEqual([2]i32{ 2, 1 }, imagePosition(.stretch, frame, 10, 10, 9, 7));
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
