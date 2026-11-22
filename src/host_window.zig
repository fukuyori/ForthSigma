//! The host's native graphics window. Windows runs it on a dedicated thread; macOS uses
//! the AppKit child process in host_window_macos.zig. Other hosts have no native window.

const std = @import("std");
const builtin = @import("builtin");
const forth = @import("forth.zig");
const window_layout = @import("window_layout.zig");
const linux_enabled = builtin.os.tag == .linux and @import("build_options").graphics and @import("build_options").x11;
const linux_window = if (linux_enabled) @import("host_window_linux.zig") else struct {};

const macos_window = if (builtin.os.tag == .macos) @import("host_window_macos.zig") else struct {
    fn imePreedit(_: ?*anyopaque, _: []u8) forth.RuntimeError!usize {
        return 0;
    }
    fn imeCaret(_: ?*anyopaque, _: bool, _: i64, _: i64, _: i64) forth.RuntimeError!void {}
};

pub const available = builtin.os.tag == .windows or builtin.os.tag == .macos or linux_enabled;
pub const internal_child_argument = if (builtin.os.tag == .macos) macos_window.child_argument else "";

/// The host's window_fn: shows the pixels, opening the window when it is not open.
pub const show = if (builtin.os.tag == .windows) win32.show else if (builtin.os.tag == .macos) macos_window.show else if (linux_enabled) linux_window.show else unsupported;

/// Copies the latest native-window IME preedit, when that backend supports it.
pub fn imePreedit(context: ?*anyopaque, destination: []u8) forth.RuntimeError!usize {
    if (builtin.os.tag == .windows) return win32.imePreedit(context, destination);
    if (linux_enabled) return linux_window.imePreedit(context, destination);
    return macos_window.imePreedit(context, destination);
}

/// Updates the native-window input-method caret, when that backend supports it.
pub fn imeCaret(context: ?*anyopaque, active: bool, x: i64, y: i64, height: i64) forth.RuntimeError!void {
    if (builtin.os.tag == .windows) return win32.imeCaret(context, active, x, y, height);
    if (linux_enabled) return linux_window.imeCaret(context, active, x, y, height);
    return macos_window.imeCaret(context, active, x, y, height);
}

/// The next key or mouse change in the window, for INKEY and MOUSE; null when none.
pub fn poll() ?forth.InputEvent {
    return if (builtin.os.tag == .windows) win32.poll() else if (builtin.os.tag == .macos) macos_window.poll() else if (linux_enabled) linux_window.poll() else null;
}

/// The host's window_fullscreen_fn.
pub fn fullscreen(context: ?*anyopaque, request: i8) forth.RuntimeError!bool {
    if (builtin.os.tag == .windows) return win32.fullscreen(context, request);
    if (builtin.os.tag == .macos) return macos_window.fullscreen(context, request);
    if (linux_enabled) return linux_window.fullscreen(context, request);
    return error.HostUnavailable;
}

/// The host's window_display_fn: the display the window is on, as host_display names
/// it, or null without a window. Only Windows tells yet.
pub fn windowDisplay(_: ?*anyopaque) ?u64 {
    if (builtin.os.tag == .windows) return win32.windowDisplay();
    return null;
}

/// The host's window_cursor_fn.
pub fn mouseCursor(context: ?*anyopaque, visible: bool) forth.RuntimeError!void {
    if (builtin.os.tag == .windows) return win32.mouseCursor(context, visible);
    if (builtin.os.tag == .macos) return macos_window.mouseCursor(context, visible);
    if (linux_enabled) return linux_window.mouseCursor(context, visible);
    return error.HostUnavailable;
}

/// Closes the window and waits for its thread, before the program ends.
pub fn close() void {
    if (builtin.os.tag == .windows) win32.close() else if (builtin.os.tag == .macos) macos_window.close() else if (linux_enabled) linux_window.close();
}

/// Internal AppKit child entry point, dispatched before Sigma initializes its Forth VM.
pub fn runChild() !u8 {
    if (builtin.os.tag == .macos) return macos_window.runChild();
    return error.HostUnavailable;
}

/// Configures the executable and inherited environment used by the AppKit child.
pub fn initMac(executable_path: [:0]const u8, environment: [:null]const ?[*:0]const u8) void {
    if (builtin.os.tag == .macos) macos_window.init(executable_path, environment);
}

fn unsupported(_: ?*anyopaque, _: []const u32, _: u32, _: u32, _: forth.ColorMode, _: [2]u32) forth.RuntimeError!void {
    return error.HostUnavailable;
}

const physical_keys = @import("core/physical_keys.zig");
const physical_map = @import("physical_key_map.zig");
fn physicalRequest(req: physical_keys.Request) physical_keys.Response {
    if (builtin.os.tag == .windows) return win32.physical(req);
    if (builtin.os.tag == .macos) return macos_window.physical(req);
    if (linux_enabled) return linux_window.physicalQuery(req);
    return switch (req) {
        .available, .supported, .held => .{ .flag = false },
        .next => .{ .event = null },
        .resync => .{ .bitmap = @splat(0) },
        .reset => .none,
    };
}
fn physicalAvailable(_: ?*anyopaque) bool {
    return physicalRequest(.available).flag;
}
fn physicalSupported(_: ?*anyopaque, scan: u8) bool {
    return physicalRequest(.{ .supported = scan }).flag;
}
fn physicalHeld(_: ?*anyopaque, scan: u8) bool {
    return physicalRequest(.{ .held = scan }).flag;
}
fn physicalNext(_: ?*anyopaque) ?physical_keys.Event {
    return physicalRequest(.next).event;
}
fn physicalResync(_: ?*anyopaque, out: *physical_keys.Bitmap) void {
    out.* = physicalRequest(.resync).bitmap;
}
fn physicalReset(_: ?*anyopaque) void {
    _ = physicalRequest(.reset);
}
pub const physical_ops: physical_keys.Ops = .{ .available = physicalAvailable, .supported = physicalSupported, .held = physicalHeld, .next = physicalNext, .resync = physicalResync, .reset = physicalReset };

const win32 = struct {
    var physical_state: physical_keys.Host = .{};
    fn physical(req: physical_keys.Request) physical_keys.Response {
        AcquireSRWLockExclusive(&lock);
        defer ReleaseSRWLockExclusive(&lock);
        return physical_state.request(req);
    }

    const Handle = *anyopaque;
    const WindowProc = *const fn (?Handle, u32, usize, isize) callconv(.winapi) isize;
    const WindowClass = extern struct {
        size: u32,
        style: u32,
        window_proc: WindowProc,
        class_extra: i32 = 0,
        window_extra: i32 = 0,
        instance: ?Handle,
        icon: ?Handle = null,
        cursor: ?Handle,
        background: ?Handle = null,
        menu_name: ?[*:0]const u16 = null,
        class_name: [*:0]const u16,
        small_icon: ?Handle = null,
    };
    const Point = extern struct { x: i32, y: i32 };
    const Message = extern struct { window: ?Handle, message: u32, wparam: usize, lparam: isize, time: u32, point: Point, private: u32 };
    const Rect = extern struct { left: i32 = 0, top: i32 = 0, right: i32 = 0, bottom: i32 = 0 };
    const PaintStruct = extern struct { dc: ?Handle, erase: i32, paint: Rect, restore: i32, inc_update: i32, reserved: [32]u8 };
    const BitmapInfoHeader = extern struct {
        size: u32 = @sizeOf(BitmapInfoHeader),
        width: i32,
        height: i32,
        planes: u16 = 1,
        bit_count: u16 = 32,
        compression: u32 = 0,
        size_image: u32 = 0,
        x_pels_per_meter: i32 = 0,
        y_pels_per_meter: i32 = 0,
        colors_used: u32 = 0,
        colors_important: u32 = 0,
    };
    const BitmapInfo = extern struct { header: BitmapInfoHeader, colors: [1]u32 = .{0} };
    const SrwLock = extern struct { pointer: ?*anyopaque = null };

    extern "user32" fn GetKeyState(i32) callconv(.winapi) i16;
    extern "user32" fn SetTimer(?Handle, usize, u32, ?*anyopaque) callconv(.winapi) usize;
    extern "user32" fn RegisterClassExW(*const WindowClass) callconv(.winapi) u16;
    extern "user32" fn CreateWindowExW(u32, [*:0]const u16, [*:0]const u16, u32, i32, i32, i32, i32, ?Handle, ?Handle, ?Handle, ?*anyopaque) callconv(.winapi) ?Handle;
    extern "user32" fn DefWindowProcW(?Handle, u32, usize, isize) callconv(.winapi) isize;
    extern "user32" fn GetMessageW(*Message, ?Handle, u32, u32) callconv(.winapi) i32;
    extern "user32" fn TranslateMessage(*const Message) callconv(.winapi) i32;
    extern "user32" fn DispatchMessageW(*const Message) callconv(.winapi) isize;
    extern "user32" fn PostQuitMessage(i32) callconv(.winapi) void;
    extern "user32" fn PostMessageW(?Handle, u32, usize, isize) callconv(.winapi) i32;
    extern "user32" fn ShowWindow(?Handle, i32) callconv(.winapi) i32;
    extern "user32" fn InvalidateRect(?Handle, ?*const Rect, i32) callconv(.winapi) i32;
    extern "user32" fn BeginPaint(?Handle, *PaintStruct) callconv(.winapi) ?Handle;
    extern "user32" fn EndPaint(?Handle, *const PaintStruct) callconv(.winapi) i32;
    extern "user32" fn GetClientRect(?Handle, *Rect) callconv(.winapi) i32;
    extern "user32" fn AdjustWindowRect(*Rect, u32, i32) callconv(.winapi) i32;
    extern "user32" fn SetWindowPos(?Handle, ?Handle, i32, i32, i32, i32, u32) callconv(.winapi) i32;
    extern "user32" fn LoadCursorW(?Handle, usize) callconv(.winapi) ?Handle;
    extern "gdi32" fn StretchDIBits(?Handle, i32, i32, i32, i32, i32, i32, i32, i32, ?*const anyopaque, *const BitmapInfo, u32, u32) callconv(.winapi) i32;
    extern "gdi32" fn SetStretchBltMode(?Handle, i32) callconv(.winapi) i32;
    extern "user32" fn MapVirtualKeyW(u32, u32) callconv(.winapi) u32;
    extern "gdi32" fn PatBlt(?Handle, i32, i32, i32, i32, u32) callconv(.winapi) i32;
    extern "kernel32" fn GetModuleHandleW(?[*:0]const u16) callconv(.winapi) ?Handle;
    extern "kernel32" fn CreateThread(?*anyopaque, usize, *const fn (?*anyopaque) callconv(.winapi) u32, ?*anyopaque, u32, ?*u32) callconv(.winapi) ?Handle;
    extern "kernel32" fn CreateEventW(?*anyopaque, i32, i32, ?[*:0]const u16) callconv(.winapi) ?Handle;
    extern "kernel32" fn SetEvent(Handle) callconv(.winapi) i32;
    extern "kernel32" fn WaitForSingleObject(Handle, u32) callconv(.winapi) u32;
    extern "kernel32" fn CloseHandle(Handle) callconv(.winapi) i32;
    extern "kernel32" fn AcquireSRWLockExclusive(*SrwLock) callconv(.winapi) void;
    extern "kernel32" fn ReleaseSRWLockExclusive(*SrwLock) callconv(.winapi) void;
    extern "user32" fn SetCapture(?Handle) callconv(.winapi) ?Handle;
    extern "user32" fn ReleaseCapture() callconv(.winapi) i32;
    extern "user32" fn GetWindowRect(?Handle, *Rect) callconv(.winapi) i32;
    extern "user32" fn MonitorFromWindow(?Handle, u32) callconv(.winapi) ?Handle;
    extern "user32" fn GetMonitorInfoW(?Handle, *MonitorInfo) callconv(.winapi) i32;
    extern "kernel32" fn GetProcAddress(Handle, [*:0]const u8) callconv(.winapi) ?*const anyopaque;
    extern "kernel32" fn GetTickCount64() callconv(.winapi) u64;
    extern "kernel32" fn ResetEvent(Handle) callconv(.winapi) i32;
    extern "user32" fn DestroyWindow(?Handle) callconv(.winapi) i32;
    extern "user32" fn SetWindowLongPtrW(?Handle, i32, isize) callconv(.winapi) isize;
    extern "user32" fn SetForegroundWindow(?Handle) callconv(.winapi) i32;
    extern "user32" fn BringWindowToTop(?Handle) callconv(.winapi) i32;
    extern "user32" fn SetCursor(?Handle) callconv(.winapi) ?Handle;
    extern "user32" fn GetCursorPos(*Point) callconv(.winapi) i32;
    extern "user32" fn WindowFromPoint(Point) callconv(.winapi) ?Handle;
    extern "imm32" fn ImmGetContext(?Handle) callconv(.winapi) ?Handle;
    extern "imm32" fn ImmReleaseContext(?Handle, ?Handle) callconv(.winapi) i32;
    extern "imm32" fn ImmGetCompositionStringW(?Handle, u32, ?*anyopaque, u32) callconv(.winapi) i32;
    extern "imm32" fn ImmSetCompositionWindow(?Handle, *const CompositionForm) callconv(.winapi) i32;
    extern "imm32" fn ImmSetCandidateWindow(?Handle, *const CandidateForm) callconv(.winapi) i32;

    const CompositionForm = extern struct { style: u32, point: Point, area: Rect = .{} };
    const CandidateForm = extern struct { index: u32 = 0, style: u32, point: Point, area: Rect = .{} };
    const cfs_point: u32 = 0x0002;
    const cfs_exclude: u32 = 0x0080;
    const gcs_composition: u32 = 0x0008;
    const gcs_result: u32 = 0x0800;

    const MonitorInfo = extern struct { size: u32 = @sizeOf(MonitorInfo), monitor: Rect = .{}, work: Rect = .{}, flags: u32 = 0 };

    /// The DPI functions of Windows 10 1607 and later, looked up when the window thread
    /// starts so that Sigma still runs (unaware of DPI, as before) on older Windows. The
    /// window is aware of DPI from Windows 10 1703 (Per Monitor v2).
    const Dpi = struct {
        set_thread_context: ?*const fn (?*anyopaque) callconv(.winapi) ?*anyopaque = null,
        for_window: ?*const fn (?Handle) callconv(.winapi) u32 = null,
        adjust_rect: ?*const fn (*Rect, u32, i32, u32, u32) callconv(.winapi) i32 = null,
    };
    var dpi: Dpi = .{};
    var dpi_loaded = false;
    /// DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2 (Windows 10 1703).
    const per_monitor_aware_v2: isize = -4;
    const monitor_default_to_nearest: u32 = 2;

    const overlapped_window: u32 = 0x00CF0000;
    const use_default: i32 = @bitCast(@as(u32, 0x80000000));
    const wm_destroy = 0x0002;
    const wm_close = 0x0010;
    const wm_paint = 0x000F;
    const wm_erase_background = 0x0014;
    const wm_kill_focus = 0x0008;
    const wm_capture_changed = 0x0215;
    const wm_ime_start_composition = 0x010D;
    const wm_ime_end_composition = 0x010E;
    const wm_ime_composition = 0x010F;
    const wm_ime_set_context = 0x0281;
    const isc_show_composition_window: usize = 0x8000_0000;
    const wm_size = 0x0005;
    /// Sent by imeCaret: the focused GUI-FIELD's caret moved, or the field was left.
    const wm_ime_caret = 0x8001;
    const wm_key_down = 0x0100;
    const wm_key_up = 0x0101;
    const wm_char = 0x0102;
    const wm_mouse_move = 0x0200;
    const wm_left_down = 0x0201;
    const wm_middle_up = 0x0208;
    const wm_mouse_wheel = 0x020A;
    const wm_dpi_changed = 0x02E0;
    const wm_get_dpi_scaled_size = 0x02E4;
    const wm_system_key_down = 0x0104;
    const wm_system_char = 0x0106;
    const wm_set_cursor = 0x0020;
    /// Sent by fullscreen and mouseCursor: the window takes what was asked.
    const wm_fullscreen = 0x8002;
    const wm_cursor = 0x8003;
    const ws_popup: u32 = 0x8000_0000;
    const ws_visible: u32 = 0x1000_0000;
    const gwl_style: i32 = -16;
    const frame_changed: u32 = 0x0020;
    const show_window: u32 = 0x0040;
    const hit_client: usize = 1;
    const vk_return: usize = 0x0D;
    const button_left: usize = 0x0001;
    const button_right: usize = 0x0002;
    const button_middle: usize = 0x0010;
    /// Sent by SHOW: draw the new image; wparam is 1 when its size changed.
    const wm_new_image = 0x8000;
    const show_no_activate = 4;
    const no_size: u32 = 0x0001;
    const no_move: u32 = 0x0002;
    const no_z_order: u32 = 0x0004;
    const no_activate: u32 = 0x0010;
    const arrow_cursor: usize = 32512;
    const color_on_color = 3;
    const source_copy: u32 = 0x00CC0020;
    const blackness: u32 = 0x00000042;
    const map_scan_to_virtual: u32 = 1;
    const redraw_vertical: u32 = 0x0001;
    const redraw_horizontal: u32 = 0x0002;
    const infinite: u32 = 0xFFFF_FFFF;
    const wait_object_0: u32 = 0;

    const class_name = std.unicode.utf8ToUtf16LeStringLiteral("SigmaGraphicsWindow");
    const title = std.unicode.utf8ToUtf16LeStringLiteral("FORTH/Sigma graphics");

    // What the window shows, kept under `lock`, which both threads take.
    var lock = SrwLock{};
    var pixels: []u32 = &.{};
    var width: u32 = 0;
    var height: u32 = 0;
    /// WINDOW-SIZE: the client area the window gets, 0 0 for the image's size.
    var requested: [2]u32 = .{ 0, 0 };
    var window: ?Handle = null;
    /// A wm_new_image message is waiting in the window's queue: SHOW sends no other, so
    /// the queue cannot fill, and that message draws the latest image.
    var update_pending = false;
    /// The image's size changed since the window last fitted it.
    var resize_pending = false;
    /// Keys pressed in the window and not yet read (later ones are dropped when it is
    /// full), and the mouse: the pixel of the image under it and its buttons. A text the
    /// IME commits comes all at once; INKEY takes it from here a key at a time, so the
    /// queue holds that much.
    var keys: [1024]KeyEvent = undefined;
    var key_head: usize = 0;
    var key_count: usize = 0;
    var high_surrogate: u16 = 0;
    /// Ctrl+C was pressed and is not yet told.
    var interrupt_pending = false;
    /// FULLSCREEN: wanted (under `lock`; Alt+Enter clears it), and whether the window
    /// covers its screen now with the place it had before (window thread only).
    var fullscreen_wanted = false;
    var fullscreen_on = false;
    var windowed_place = Rect{};
    /// MOUSE-CURSOR, under `lock`.
    var cursor_visible = true;
    /// The focused GUI-FIELD's caret, in image pixels (imeCaret), and the text the IME
    /// is converting there, as UTF-8 (imePreedit). Without a focused field the IME
    /// shows its own composition window, as before.
    var ime_caret: struct { active: bool = false, x: i64 = 0, y: i64 = 0, height: i64 = 0 } = .{};
    /// Counts the changes of ime_caret.active, so that a composition read for one
    /// field is not stored after that field was left.
    var ime_generation: u32 = 0;
    var preedit: [512]u8 = undefined;
    var preedit_len: usize = 0;
    /// For KEY-HELD?, by virtual key, the code plus 1 (0: none): `down`, the key the
    /// window has down now; `told`, the key poll told the core was pressed and not yet
    /// that it was released. Releases are not queued: poll tells them from the two, so
    /// none is lost when the queue is full, the window loses the focus, or a held key
    /// gives another character.
    var down: [256]u32 = @splat(0);
    var told: [256]u32 = @splat(0);
    var mouse_x: i32 = -1;
    var mouse_y: i32 = -1;
    var mouse_buttons: u8 = 0;
    var mouse_changed = false;
    /// The changes of the buttons and the notches of the wheel, in order, so that a click
    /// between two reads is not lost (MOUSE-EVENT); the oldest is dropped when it is full.
    /// Moves are only the last place above. `queued_buttons` are the buttons of the last
    /// change queued, and `wheel_rest` the part of a notch the wheel has turned.
    var mouse_queue: [64]MouseItem = undefined;
    var mouse_head: usize = 0;
    var mouse_count: usize = 0;
    var queued_buttons: u8 = 0;
    var wheel_rest: i32 = 0;

    const MouseItem = struct { x: i32, y: i32, buttons: u8, wheel: i8 };

    fn queueMouse(item: MouseItem) void {
        if (mouse_count == mouse_queue.len) {
            mouse_head = (mouse_head + 1) % mouse_queue.len;
            mouse_count -= 1;
        }
        mouse_queue[(mouse_head + mouse_count) % mouse_queue.len] = item;
        mouse_count += 1;
    }

    // Used only by the thread that runs Forth.
    var thread: ?Handle = null;
    var class_registered = false;
    /// A window could not be made within the time: SHOW fails from then on.
    var broken = false;
    /// The longest open waits, in milliseconds; tests make it shorter.
    var start_timeout_ms: u32 = 5000;
    /// The event the window thread sets when it has told how making the window went.
    var started: ?Handle = null;
    /// Tests hold the window thread here before it makes the window.
    var test_gate: ?Handle = null;
    /// How making the window went, under `lock`: the window thread sets opened or
    /// failed, and open sets cancelled when it stops waiting first.
    var start: enum { waiting, opened, failed, cancelled } = .waiting;

    fn show(_: ?*anyopaque, image: []const u32, image_width: u32, image_height: u32, mode: forth.ColorMode, size: [2]u32) forth.RuntimeError!void {
        if (broken) return error.HostFailed;
        AcquireSRWLockExclusive(&lock);
        // The window fits itself again when the image or WINDOW-SIZE changed.
        const resized = image_width != width or image_height != height or size[0] != requested[0] or size[1] != requested[1];
        requested = size;
        if (pixels.len != image.len) {
            const buffer = std.heap.c_allocator.alloc(u32, image.len) catch {
                ReleaseSRWLockExclusive(&lock);
                return error.MemoryExhausted;
            };
            if (pixels.len != 0) std.heap.c_allocator.free(pixels);
            pixels = buffer;
        }
        if (mode.colors == 0) {
            @memcpy(pixels, image);
        } else {
            // DISPLAY-COLORS: each pixel as the palette shows it.
            for (pixels, image, 0..) |*target, pixel, index| {
                target.* = 0xff00_0000 | forth.graphicsColor(mode, index % image_width, index / image_width, pixel);
            }
        }
        width = image_width;
        height = image_height;
        if (resized) resize_pending = true;
        const current = window;
        const post = current != null and !update_pending;
        if (post) update_pending = true;
        ReleaseSRWLockExclusive(&lock);
        // No window: it was closed (its thread ends after WM_DESTROY), or never opened.
        const handle = current orelse return open();
        if (!post or PostMessageW(handle, wm_new_image, 0, 0) != 0) return;
        AcquireSRWLockExclusive(&lock);
        update_pending = false;
        const still_open = window != null;
        ReleaseSRWLockExclusive(&lock);
        // The window closed meanwhile: open a new one. Otherwise the image is copied and
        // the window shows it when it next draws, but the request did not reach it.
        if (!still_open) return open();
        return error.HostFailed;
    }

    fn poll() ?forth.InputEvent {
        AcquireSRWLockExclusive(&lock);
        defer ReleaseSRWLockExclusive(&lock);
        // Ctrl+C before the keys queued, and also when their queue was full.
        if (interrupt_pending) {
            interrupt_pending = false;
            return .{ .window_text = interrupt_character };
        }
        if (key_count != 0) {
            const key = keys[key_head];
            if (key.virtual_key < told.len) {
                const virtual_key = key.virtual_key;
                // Another code of a key told down: that one was released first.
                if (told[virtual_key] != 0 and told[virtual_key] != key.code + 1) {
                    const old = told[virtual_key] - 1;
                    told[virtual_key] = 0;
                    return .{ .window_key_release = old };
                }
                if (holdable(key)) told[virtual_key] = key.code + 1;
            }
            key_head = (key_head + 1) % keys.len;
            key_count -= 1;
            // A character goes whole, so that the core takes all its UTF-8 bytes or none.
            return if (key.text) .{ .window_text = @intCast(key.code) } else .{ .window_key = key.code };
        }
        // The keys told down that the window no longer has down.
        for (&told, down) |*code, now| {
            if (code.* == 0 or code.* == now) continue;
            const old = code.* - 1;
            code.* = 0;
            return .{ .window_key_release = old };
        }
        // The queued changes first; the last place comes after them, so the core ends
        // with the mouse as it is now.
        if (mouse_count != 0) {
            const item = mouse_queue[mouse_head];
            mouse_head = (mouse_head + 1) % mouse_queue.len;
            mouse_count -= 1;
            return .{ .window_mouse = .{ .x = item.x, .y = item.y, .buttons = item.buttons, .wheel = item.wheel } };
        }
        if (!mouse_changed) return null;
        mouse_changed = false;
        return .{ .window_mouse = .{ .x = mouse_x, .y = mouse_y, .buttons = mouse_buttons } };
    }

    /// A key pressed: a key that gives no character (`text` false, graphics_input's
    /// code), or a character (`text`, its Unicode scalar), and its virtual key (`no_key`
    /// when none).
    const KeyEvent = struct { code: u32, virtual_key: usize, text: bool = false };
    const no_key = std.math.maxInt(usize);
    /// Ctrl+C, which WM_CHAR gives as 3.
    const interrupt_character = 3;

    /// What KEY-HELD? tells: a character of one byte (ASCII), and the keys from 256 up.
    fn holdable(key: KeyEvent) bool {
        return if (key.text) key.code < 0x80 else key.code >= 256;
    }

    /// Called with the lock held. A key or character that does not fit is dropped whole.
    fn pushKey(key: KeyEvent) void {
        if (key_count == keys.len) return;
        keys[(key_head + key_count) % keys.len] = key;
        key_count += 1;
    }

    /// The key code of a key that gives no character (graphics_input's codes).
    fn virtualKey(code: usize) ?u32 {
        return switch (code) {
            0x26 => 256, // up
            0x28 => 257, // down
            0x25 => 258, // left
            0x27 => 259, // right
            0x24 => 260, // home
            0x23 => 261, // end
            0x21 => 262, // page up
            0x22 => 263, // page down
            0x2D => 264, // insert
            0x2E => 265, // delete
            0x70...0x7B => @intCast(266 + (code - 0x70)), // F1 to F12
            else => null,
        };
    }

    /// A UTF-16 unit of WM_CHAR, as the bytes of its UTF-8 character, from the key of
    /// that virtual key.
    fn pushCharacter(unit: u16, virtual_key: usize) void {
        var code_point: u21 = unit;
        if (unit >= 0xD800 and unit < 0xDC00) {
            high_surrogate = unit;
            return;
        }
        if (unit >= 0xDC00 and unit < 0xE000) {
            if (high_surrogate == 0) return;
            code_point = 0x10000 + ((@as(u21, high_surrogate) - 0xD800) << 10) + (unit - 0xDC00);
        }
        high_surrogate = 0;
        // Ctrl+C is not queued: it is told first, even when the queue is full.
        if (code_point == interrupt_character) {
            interrupt_pending = true;
            return;
        }
        if (!std.unicode.utf8ValidCodepoint(code_point)) return;
        if (key_count == keys.len) return;
        pushKey(.{ .code = code_point, .virtual_key = virtual_key, .text = true });
        // A character of one byte is held until its key goes up.
        if (code_point < 0x80 and virtual_key < down.len) down[virtual_key] = code_point + 1;
    }

    /// Where the image is drawn in a client area, by window_layout's rule. Called with
    /// the lock held.
    fn fitted(client_width: i32, client_height: i32) window_layout.Place {
        return window_layout.place(width, height, @intCast(@max(client_width, 1)), @intCast(@max(client_height, 1)));
    }

    /// The image drawn at the size it is shown, a band of rows at a time, by the
    /// nearest-neighbour rule, so that GDI copies it pixel for pixel. The band holds at
    /// most band_pixels pixels (4 MB) however large the window is; used only by the
    /// window thread, with the lock held.
    const band_pixels = 1 << 20;
    var band: []u32 = &.{};
    var band_columns: []u32 = &.{};

    /// Draws the image at `fit` by bands; false when there is no memory for them (GDI
    /// then stretches the image itself).
    fn drawScaled(dc: ?Handle, fit: window_layout.Place) bool {
        if (band.len == 0) band = std.heap.c_allocator.alloc(u32, band_pixels) catch return false;
        if (band_columns.len < fit.w) {
            const columns = std.heap.c_allocator.alloc(u32, fit.w) catch return false;
            if (band_columns.len != 0) std.heap.c_allocator.free(band_columns);
            band_columns = columns;
        }
        window_layout.sourceColumns(band_columns, width, fit.w);
        // At least one row, however wide: a row of 16384 pixels fits the band.
        const rows_per_band: u32 = @intCast(@max(1, band_pixels / fit.w));
        var first: u32 = 0;
        while (first < fit.h) : (first += rows_per_band) {
            const rows = @min(rows_per_band, fit.h - first);
            window_layout.scaleRows(pixels, width, height, band, fit.w, fit.h, band_columns, first, rows);
            const info = BitmapInfo{ .header = .{ .width = @intCast(fit.w), .height = -@as(i32, @intCast(rows)) } };
            _ = StretchDIBits(dc, @intCast(fit.x), @intCast(fit.y + first), @intCast(fit.w), @intCast(rows), 0, 0, @intCast(fit.w), @intCast(rows), band.ptr, &info, 0, source_copy);
        }
        return true;
    }

    /// The pixel of the image under a point of the client area, from where the image is
    /// drawn in it (outside the image: beyond its edges).
    fn mouseMoved(handle: ?Handle, wparam: usize, lparam: isize) void {
        var client = Rect{};
        _ = GetClientRect(handle, &client);
        const bits: usize = @bitCast(lparam);
        const x: i64 = @as(i16, @bitCast(@as(u16, @truncate(bits))));
        const y: i64 = @as(i16, @bitCast(@as(u16, @truncate(bits >> 16))));
        AcquireSRWLockExclusive(&lock);
        defer ReleaseSRWLockExclusive(&lock);
        const place = fitted(client.right, client.bottom);
        mouse_x = @intCast(std.math.clamp(window_layout.imagePixel(x, place.x, width, place.w), -1 << 20, 1 << 20));
        mouse_y = @intCast(std.math.clamp(window_layout.imagePixel(y, place.y, height, place.h), -1 << 20, 1 << 20));
        var buttons: u8 = 0;
        if (wparam & button_left != 0) buttons |= 1;
        if (wparam & button_right != 0) buttons |= 2;
        if (wparam & button_middle != 0) buttons |= 4;
        mouse_buttons = buttons;
        mouse_changed = true;
        if (buttons != queued_buttons) {
            queueMouse(.{ .x = mouse_x, .y = mouse_y, .buttons = buttons, .wheel = 0 });
            queued_buttons = buttons;
        }
    }

    /// The window lost the focus or the mouse: the buttons held are released, with a
    /// release for MOUSE-EVENT, at the last place. Called with the lock held.
    fn releaseButtons() void {
        if (mouse_buttons == 0 and queued_buttons == 0) return;
        mouse_buttons = 0;
        mouse_changed = true;
        if (queued_buttons != 0) {
            queueMouse(.{ .x = mouse_x, .y = mouse_y, .buttons = 0, .wheel = 0 });
            queued_buttons = 0;
        }
    }

    /// The window is closed: keys and buttons are released, and the mouse is nowhere
    /// (-1 -1) until a window shows it again. Called with the lock held.
    fn windowGone() void {
        physical_state.close();
        down = @splat(0);
        releaseButtons();
        mouse_x = -1;
        mouse_y = -1;
        mouse_changed = true;
        wheel_rest = 0;
        preedit_len = 0;
    }

    /// WM_MOUSEWHEEL: the high word of wparam is the distance, 120 a notch, above 0 up. A
    /// notch is told at the last place of the mouse in the window.
    fn wheelTurned(wparam: usize) void {
        const distance: i16 = @bitCast(@as(u16, @truncate(wparam >> 16)));
        AcquireSRWLockExclusive(&lock);
        defer ReleaseSRWLockExclusive(&lock);
        wheel_rest += distance;
        while (wheel_rest >= 120 or wheel_rest <= -120) {
            const notch: i8 = if (wheel_rest > 0) 1 else -1;
            wheel_rest -= @as(i32, notch) * 120;
            queueMouse(.{ .x = mouse_x, .y = mouse_y, .buttons = mouse_buttons, .wheel = notch });
        }
    }

    /// Only called when there is no window: the old thread, if any, is ending (after
    /// WM_DESTROY, or after a window it could not create), so waiting for it ends.
    /// Waits at most start_timeout_ms in all (the contract's 5 seconds) for the old
    /// thread to end and the new window to be made. When the time runs out, the window
    /// thread is told to destroy the window it may still make, and the window is not
    /// tried again in this process (a thread stuck in CreateWindowExW cannot be ended).
    fn open() forth.RuntimeError!void {
        if (broken) return error.HostFailed;
        // While automatic display looks for a display, the window has at most 2 of its
        // 5 seconds, so that Tk can still be tried (as on Linux).
        const display_budget = @import("host_display_budget.zig");
        var deadline = GetTickCount64() + start_timeout_ms;
        if (display_budget.active()) {
            if (display_budget.expired()) return error.HostFailed;
            deadline = @min(deadline, GetTickCount64() + 2000, @as(u64, @intCast(@max(0, display_budget.deadline()))));
        }
        if (thread) |old| {
            if (WaitForSingleObject(old, remainingMs(deadline)) != wait_object_0) {
                broken = true;
                return error.HostFailed;
            }
            _ = CloseHandle(old);
            thread = null;
        }
        // One event for the whole process, never closed: a thread may set it after open
        // stopped waiting. The thread before has ended, so it no longer sets it.
        if (started == null) started = CreateEventW(null, 1, 0, null);
        const event = started orelse return error.HostFailed;
        _ = ResetEvent(event);
        AcquireSRWLockExclusive(&lock);
        start = .waiting;
        ReleaseSRWLockExclusive(&lock);
        thread = CreateThread(null, 0, run, null, 0, null) orelse return error.HostFailed;
        _ = WaitForSingleObject(event, remainingMs(deadline));
        // The state decides, not the wait: the thread may have told its result just as
        // the time ran out.
        AcquireSRWLockExclusive(&lock);
        const result = start;
        if (result == .waiting) start = .cancelled;
        ReleaseSRWLockExclusive(&lock);
        switch (result) {
            .opened => {},
            // The thread ends by itself; the next open waits for it.
            .failed => return error.HostFailed,
            .waiting, .cancelled => {
                broken = true;
                return error.HostFailed;
            },
        }
    }

    /// GFX-IME-PREEDIT: the text being converted in the focused GUI-FIELD, cut at a
    /// character's start to fit.
    fn imePreedit(_: ?*anyopaque, destination: []u8) forth.RuntimeError!usize {
        AcquireSRWLockExclusive(&lock);
        defer ReleaseSRWLockExclusive(&lock);
        var n = @min(preedit_len, destination.len);
        while (n > 0 and n < preedit_len and preedit[n] & 0xc0 == 0x80) n -= 1;
        @memcpy(destination[0..n], preedit[0..n]);
        return n;
    }

    /// GFX-IME-CARET, which GUI-FIELD calls each frame: the window moves the IME's
    /// windows only when the caret changed.
    fn imeCaret(_: ?*anyopaque, active: bool, x: i64, y: i64, caret_height: i64) forth.RuntimeError!void {
        AcquireSRWLockExclusive(&lock);
        const changed = ime_caret.active != active or ime_caret.x != x or ime_caret.y != y or ime_caret.height != caret_height;
        if (changed) {
            if (ime_caret.active != active) ime_generation +%= 1;
            ime_caret = .{ .active = active, .x = x, .y = y, .height = caret_height };
            if (!active) preedit_len = 0;
        }
        const current = window;
        ReleaseSRWLockExclusive(&lock);
        if (changed) if (current) |handle| {
            _ = PostMessageW(handle, wm_ime_caret, 0, 0);
        };
    }

    /// UTF-16 as UTF-8 into `destination`, as much as fits by whole characters. An
    /// unpaired surrogate is left out.
    fn utf16ToUtf8(destination: []u8, units: []const u16) usize {
        var length: usize = 0;
        var index: usize = 0;
        while (index < units.len) : (index += 1) {
            var code_point: u21 = units[index];
            if (code_point >= 0xD800 and code_point < 0xDC00) {
                if (index + 1 >= units.len or units[index + 1] < 0xDC00 or units[index + 1] >= 0xE000) continue;
                index += 1;
                code_point = 0x10000 + ((code_point - 0xD800) << 10) + (units[index] - 0xDC00);
            } else if (code_point >= 0xDC00 and code_point < 0xE000) continue;
            var bytes: [4]u8 = undefined;
            const n = std.unicode.utf8Encode(code_point, &bytes) catch continue;
            if (length + n > destination.len) break;
            @memcpy(destination[length..][0..n], bytes[0..n]);
            length += n;
        }
        return length;
    }

    /// One of the IME's strings (gcs_composition or gcs_result) as UTF-16, at most
    /// `units`; its length.
    fn imeString(context: ?Handle, which: u32, units: []u16) usize {
        const bytes = ImmGetCompositionStringW(context, which, units.ptr, @intCast(units.len * 2));
        return if (bytes <= 0) 0 else @min(@as(usize, @intCast(bytes)) / 2, units.len);
    }

    /// Puts the IME's composition and candidate windows at the focused field's caret,
    /// from image pixels to the client area by window_layout's rule.
    fn placeIme(handle: Handle) void {
        var client = Rect{};
        _ = GetClientRect(handle, &client);
        AcquireSRWLockExclusive(&lock);
        const caret = ime_caret;
        const fit = fitted(client.right, client.bottom);
        const iw: i64 = @max(width, 1);
        const ih: i64 = @max(height, 1);
        ReleaseSRWLockExclusive(&lock);
        if (!caret.active) return;
        const limit: i64 = 1 << 24;
        const x: i32 = @intCast(std.math.clamp(fit.x + @divFloor(std.math.clamp(caret.x, -limit, limit) * fit.w, iw), -limit, limit));
        const y: i32 = @intCast(std.math.clamp(fit.y + @divFloor(std.math.clamp(caret.y, -limit, limit) * fit.h, ih), -limit, limit));
        const h: i32 = @intCast(std.math.clamp(@divFloor(std.math.clamp(caret.height, 1, limit) * fit.h, ih), 1, limit));
        const context = ImmGetContext(handle) orelse return;
        defer _ = ImmReleaseContext(handle, context);
        _ = ImmSetCompositionWindow(context, &.{ .style = cfs_point, .point = .{ .x = x, .y = y } });
        // The candidates go below the caret, not over it.
        _ = ImmSetCandidateWindow(context, &.{ .style = cfs_exclude, .point = .{ .x = x, .y = y + h }, .area = .{ .left = x, .top = y, .right = x + 1, .bottom = y + h } });
    }

    /// WM_IME_COMPOSITION in a focused GUI-FIELD: the text being converted goes to
    /// imePreedit, and the text committed to INKEY as characters typed.
    /// `generation` is ime_generation when the window saw the field focused: a text
    /// being converted read after the field was left is not stored. Without either
    /// flag, the composition was cancelled.
    fn composition(handle: Handle, flags: isize, generation: u32) void {
        if (flags & (gcs_result | gcs_composition) == 0) {
            AcquireSRWLockExclusive(&lock);
            preedit_len = 0;
            ReleaseSRWLockExclusive(&lock);
            return;
        }
        const context = ImmGetContext(handle) orelse return;
        defer _ = ImmReleaseContext(handle, context);
        if (flags & gcs_result != 0) committed(context);
        if (flags & gcs_composition != 0) {
            // More than the field can show is not needed.
            var units: [512]u16 = undefined;
            const count = imeString(context, gcs_composition, &units);
            AcquireSRWLockExclusive(&lock);
            if (ime_caret.active and ime_generation == generation) preedit_len = utf16ToUtf8(&preedit, units[0..count]);
            ReleaseSRWLockExclusive(&lock);
        }
    }

    /// The text committed, whole, however long, as characters typed for INKEY.
    fn committed(context: Handle) void {
        const bytes = ImmGetCompositionStringW(context, gcs_result, null, 0);
        var small: [256]u16 = undefined;
        var units: []u16 = &small;
        var allocated: ?[]u16 = null;
        if (bytes > 0 and @as(usize, @intCast(bytes)) / 2 > small.len) {
            // Without memory for it, the start of the text is taken.
            allocated = std.heap.c_allocator.alloc(u16, @as(usize, @intCast(bytes)) / 2) catch null;
            if (allocated) |buffer| units = buffer;
        }
        defer if (allocated) |buffer| std.heap.c_allocator.free(buffer);
        const count = imeString(context, gcs_result, units);
        AcquireSRWLockExclusive(&lock);
        defer ReleaseSRWLockExclusive(&lock);
        for (units[0..count]) |unit| pushCharacter(unit, no_key);
        preedit_len = 0;
    }

    /// Whether a GUI-FIELD is focused, and ime_generation then.
    fn imeState() struct { active: bool, generation: u32 } {
        AcquireSRWLockExclusive(&lock);
        defer ReleaseSRWLockExclusive(&lock);
        return .{ .active = ime_caret.active, .generation = ime_generation };
    }

    fn imeActive() bool {
        return imeState().active;
    }

    /// FULLSCREEN and FULLSCREEN?: request 1 or 0 asks, -1 only tells what is wanted.
    /// Without a window, the next one opens so.
    fn fullscreen(_: ?*anyopaque, request: i8) forth.RuntimeError!bool {
        AcquireSRWLockExclusive(&lock);
        var changed = false;
        if (request >= 0) {
            changed = fullscreen_wanted != (request == 1);
            fullscreen_wanted = request == 1;
        }
        const wanted = fullscreen_wanted;
        const current = window;
        ReleaseSRWLockExclusive(&lock);
        if (changed) if (current) |handle| {
            _ = PostMessageW(handle, wm_fullscreen, 0, 0);
        };
        return wanted;
    }

    /// MOUSE-CURSOR.
    fn mouseCursor(_: ?*anyopaque, visible: bool) forth.RuntimeError!void {
        AcquireSRWLockExclusive(&lock);
        const changed = cursor_visible != visible;
        cursor_visible = visible;
        const current = window;
        ReleaseSRWLockExclusive(&lock);
        if (changed) if (current) |handle| {
            _ = PostMessageW(handle, wm_cursor, 0, 0);
        };
    }

    /// Makes the window cover its screen, or a window again at the place it had, as
    /// fullscreen_wanted says. Window thread only.
    fn applyFullscreen(handle: Handle) void {
        AcquireSRWLockExclusive(&lock);
        const wanted = fullscreen_wanted;
        ReleaseSRWLockExclusive(&lock);
        if (wanted == fullscreen_on) return;
        if (wanted) {
            var monitor_info = MonitorInfo{};
            const monitor = MonitorFromWindow(handle, monitor_default_to_nearest) orelse return;
            if (GetMonitorInfoW(monitor, &monitor_info) == 0) return;
            if (GetWindowRect(handle, &windowed_place) == 0) return;
            const screen = monitor_info.monitor;
            _ = SetWindowLongPtrW(handle, gwl_style, @intCast(ws_popup | ws_visible));
            fullscreen_on = true;
            // On top of the others and with the keys, over the whole screen.
            _ = SetWindowPos(handle, null, screen.left, screen.top, screen.right - screen.left, screen.bottom - screen.top, frame_changed | show_window);
            takeKeys(handle);
        } else {
            _ = SetWindowLongPtrW(handle, gwl_style, @intCast(overlapped_window | ws_visible));
            fullscreen_on = false;
            const place = windowed_place;
            _ = SetWindowPos(handle, null, place.left, place.top, place.right - place.left, place.bottom - place.top, frame_changed | show_window | no_z_order | no_activate);
        }
        if (imeActive()) placeIme(handle);
        _ = InvalidateRect(handle, null, 0);
    }

    /// Brings the window to the front with the keys, as far as Windows lets it: it
    /// refuses a process that is not in front (another program the user works in keeps
    /// the keys; then a click gives them to the window). Joining another thread's input
    /// (AttachThreadInput) is not used, since SetForegroundWindow can then hang.
    fn takeKeys(handle: Handle) void {
        _ = BringWindowToTop(handle);
        _ = SetForegroundWindow(handle);
    }

    /// Shows or hides the cursor at once when the mouse is over the window.
    fn applyCursor(handle: Handle) void {
        var point: Point = undefined;
        if (GetCursorPos(&point) == 0 or WindowFromPoint(point) != handle) return;
        AcquireSRWLockExclusive(&lock);
        const visible = cursor_visible;
        ReleaseSRWLockExclusive(&lock);
        _ = SetCursor(if (visible) LoadCursorW(null, arrow_cursor) else null);
    }

    fn remainingMs(deadline: u64) u32 {
        const now = GetTickCount64();
        return if (now >= deadline) 0 else @intCast(@min(deadline - now, infinite - 1));
    }

    /// Looks up the DPI functions once, and makes the window thread aware of each
    /// monitor's DPI, so that the window's sizes are its raster pixels and Windows does
    /// not stretch its bitmap. Only the window thread is changed: the console is not.
    fn useDpi() void {
        if (!dpi_loaded) {
            dpi_loaded = true;
            if (GetModuleHandleW(std.unicode.utf8ToUtf16LeStringLiteral("user32.dll"))) |user32| {
                dpi.set_thread_context = @ptrCast(GetProcAddress(user32, "SetThreadDpiAwarenessContext"));
                dpi.for_window = @ptrCast(GetProcAddress(user32, "GetDpiForWindow"));
                dpi.adjust_rect = @ptrCast(GetProcAddress(user32, "AdjustWindowRectExForDpi"));
            }
        }
        const set = dpi.set_thread_context orelse return;
        // Per Monitor v2 is Windows 10 1703's. Without it the window stays unaware of DPI
        // (Per Monitor v1 would need EnableNonClientDpiScaling for its frame to match
        // frameSize); GetDpiForWindow then gives 96, as the frame is.
        _ = set(@ptrFromInt(@as(usize, @bitCast(per_monitor_aware_v2))));
    }

    /// The size the frame and title bar add to a client area, at the window's DPI.
    fn frameSize(handle: Handle) [2]i32 {
        var rect = Rect{};
        if (dpi.adjust_rect != null and dpi.for_window != null) {
            _ = dpi.adjust_rect.?(&rect, overlapped_window, 0, 0, dpi.for_window.?(handle));
        } else _ = AdjustWindowRect(&rect, overlapped_window, 0);
        return .{ rect.right - rect.left, rect.bottom - rect.top };
    }

    /// The window's size at `new_dpi` for `size`, the window size it is about to have
    /// at the present DPI (it may differ from the present one while it is resized): its
    /// client area scaled by new_dpi / the present DPI, with the frame at new_dpi. Null
    /// without the DPI functions.
    fn dpiScaledSize(handle: Handle, size: [2]i32, new_dpi: u32) ?[2]i32 {
        const for_window = dpi.for_window orelse return null;
        const adjust = dpi.adjust_rect orelse return null;
        const old_dpi = for_window(handle);
        if (old_dpi == 0 or new_dpi == 0) return null;
        var old_frame = Rect{};
        if (adjust(&old_frame, overlapped_window, 0, 0, old_dpi) == 0) return null;
        const client = [2]i32{ size[0] - (old_frame.right - old_frame.left), size[1] - (old_frame.bottom - old_frame.top) };
        const scaled = window_layout.dpiScaled(.{ @intCast(@max(client[0], 0)), @intCast(@max(client[1], 0)) }, old_dpi, new_dpi);
        var rect = Rect{ .right = @intCast(scaled[0]), .bottom = @intCast(scaled[1]) };
        if (adjust(&rect, overlapped_window, 0, 0, new_dpi) == 0) return null;
        return .{ rect.right - rect.left, rect.bottom - rect.top };
    }

    /// The monitor the window is on (its HMONITOR), or null without a window.
    fn windowDisplay() ?u64 {
        AcquireSRWLockExclusive(&lock);
        const handle = window;
        ReleaseSRWLockExclusive(&lock);
        const monitor = MonitorFromWindow(handle orelse return null, monitor_default_to_nearest) orelse return null;
        return @intFromPtr(monitor);
    }

    /// The work area (the screen without the taskbar) of the monitor the window is on.
    fn workArea(handle: Handle) ?Rect {
        var info = MonitorInfo{};
        const monitor = MonitorFromWindow(handle, monitor_default_to_nearest) orelse return null;
        if (GetMonitorInfoW(monitor, &info) == 0) return null;
        return info.work;
    }

    /// The window's size for the image: the client area WINDOW-SIZE gave, or for 0 0
    /// the image's size as window_layout gives it, which also fits the work area. Called
    /// with the lock held, on the window thread.
    fn windowSize(handle: Handle, image_width: u32, image_height: u32) [2]i32 {
        const frame = frameSize(handle);
        var client: [2]u32 = requested;
        if (requested[0] == 0) {
            var room = [2]u32{ 0, 0 };
            if (workArea(handle)) |work| {
                room = .{ @intCast(@max(1, work.right - work.left - frame[0])), @intCast(@max(1, work.bottom - work.top - frame[1])) };
            }
            client = window_layout.autoClientSize(image_width, image_height, room);
        }
        return .{ @as(i32, @intCast(client[0])) + frame[0], @as(i32, @intCast(client[1])) + frame[1] };
    }

    /// Moves a window just sized for its image into its monitor's work area, as far as
    /// it fits (a larger one keeps its top left corner in the work area).
    fn keepInWorkArea(handle: Handle) void {
        const work = workArea(handle) orelse return;
        var place = Rect{};
        if (GetWindowRect(handle, &place) == 0) return;
        var x = place.left;
        var y = place.top;
        if (place.right > work.right) x -= place.right - work.right;
        if (place.bottom > work.bottom) y -= place.bottom - work.bottom;
        x = @max(x, work.left);
        y = @max(y, work.top);
        if (x != place.left or y != place.top) _ = SetWindowPos(handle, null, x, y, 0, 0, no_size | no_z_order | no_activate);
    }

    /// The window thread: makes the window, tells open through `start` and the event it
    /// was given, and runs the window's messages. A window made after open stopped
    /// waiting is destroyed at once.
    fn run(_: ?*anyopaque) callconv(.winapi) u32 {
        const event = started.?;
        if (builtin.is_test) if (test_gate) |gate| {
            _ = WaitForSingleObject(gate, infinite);
        };
        useDpi();
        const instance = GetModuleHandleW(null);
        if (!class_registered) {
            const class = WindowClass{
                .size = @sizeOf(WindowClass),
                // Drawn again whole when resized, so the image fits the new size.
                .style = redraw_horizontal | redraw_vertical,
                .window_proc = windowProc,
                .instance = instance,
                .cursor = LoadCursorW(null, arrow_cursor),
                .class_name = class_name,
            };
            class_registered = RegisterClassExW(&class) != 0;
        }
        // Made hidden at the default place, then sized at the DPI of the monitor it is on.
        const handle = CreateWindowExW(0, class_name, title, overlapped_window, use_default, use_default, use_default, use_default, null, null, instance, null) orelse {
            AcquireSRWLockExclusive(&lock);
            if (start == .waiting) start = .failed;
            ReleaseSRWLockExclusive(&lock);
            _ = SetEvent(event);
            return 1;
        };
        AcquireSRWLockExclusive(&lock);
        const size = windowSize(handle, width, height);
        ReleaseSRWLockExclusive(&lock);
        _ = SetWindowPos(handle, null, 0, 0, size[0], size[1], no_move | no_z_order | no_activate);
        keepInWorkArea(handle);
        AcquireSRWLockExclusive(&lock);
        const cancelled = start == .cancelled;
        if (!cancelled) {
            start = .opened;
            window = handle;
            physical_state.available = true;
            physical_state.supported = @splat(0);
            // IME-processed legacy messages do not preserve physical edges for
            // the grave/zenkaku position (53) and Kana (136). Exclude both.
            for (physical_map.windows) |scan| if (scan != 53 and scan != 136 and scan != 70 and scan != 72 and scan != 102 and (scan < 127 or scan > 129)) {
                physical_state.support(scan);
            };
            if (SetTimer(handle, 0x5343, 16, null) == 0) physical_state.supported[28] &= ~@as(u8, 0x22);
            update_pending = false;
            resize_pending = false;
        }
        ReleaseSRWLockExclusive(&lock);
        _ = SetEvent(event);
        if (cancelled) {
            _ = DestroyWindow(handle);
            return 1;
        }
        // The console keeps the keyboard, so typing goes on there. A window opened
        // while fullscreen is wanted covers its screen at once, and takes the keys.
        _ = ShowWindow(handle, show_no_activate);
        fullscreen_on = false;
        applyFullscreen(handle);
        var message: Message = undefined;
        while (GetMessageW(&message, null, 0, 0) > 0) {
            _ = TranslateMessage(&message);
            _ = DispatchMessageW(&message);
        }
        return 0;
    }

    fn windowProc(handle: ?Handle, message: u32, wparam: usize, lparam: isize) callconv(.winapi) isize {
        if (message == 0x100 or message == 0x101 or message == 0x104 or message == 0x105) {
            const bits: usize = @bitCast(lparam);
            const scan = physical_map.windowsScan(@truncate(bits >> 16), bits & (1 << 24) != 0);
            AcquireSRWLockExclusive(&lock);
            physical_state.update(scan, message == 0x100 or message == 0x104);
            ReleaseSRWLockExclusive(&lock);
        }
        if (message == 0x113 and wparam == 0x5343) {
            // SDL documents Windows losing one Shift key-up when both were held.
            // Only reconcile releases; never infer a new press from polling.
            const left = GetKeyState(0xa0) < 0;
            const right = GetKeyState(0xa1) < 0;
            AcquireSRWLockExclusive(&lock);
            if (!left) physical_state.update(225, false);
            if (!right) physical_state.update(229, false);
            ReleaseSRWLockExclusive(&lock);
            return 0;
        }
        switch (message) {
            wm_paint => {
                var paint: PaintStruct = undefined;
                const dc = BeginPaint(handle, &paint);
                var client = Rect{};
                _ = GetClientRect(handle, &client);
                _ = SetStretchBltMode(dc, color_on_color);
                AcquireSRWLockExclusive(&lock);
                const fit = fitted(client.right, client.bottom);
                const left: i32 = @intCast(fit.x);
                const top: i32 = @intCast(fit.y);
                const right: i32 = @intCast(fit.x + fit.w);
                const bottom: i32 = @intCast(fit.y + fit.h);
                // Rows from the top: a negative height. The image is drawn at its shown
                // size and copied as it is; without memory for that, GDI stretches it.
                if (pixels.len != 0 and !drawScaled(dc, fit)) {
                    const info = BitmapInfo{ .header = .{ .width = @intCast(width), .height = -@as(i32, @intCast(height)) } };
                    _ = StretchDIBits(dc, left, top, @intCast(fit.w), @intCast(fit.h), 0, 0, @intCast(width), @intCast(height), pixels.ptr, &info, 0, source_copy);
                }
                ReleaseSRWLockExclusive(&lock);
                // Black around the image: above and below it, then left and right of it.
                _ = PatBlt(dc, 0, 0, client.right, top, blackness);
                _ = PatBlt(dc, 0, bottom, client.right, client.bottom - bottom, blackness);
                _ = PatBlt(dc, 0, top, left, bottom - top, blackness);
                _ = PatBlt(dc, right, top, client.right - right, bottom - top, blackness);
                _ = EndPaint(handle, &paint);
                return 0;
            },
            wm_erase_background => return 1,
            wm_key_down => {
                if (virtualKey(wparam)) |key| {
                    AcquireSRWLockExclusive(&lock);
                    pushKey(.{ .code = key, .virtual_key = wparam });
                    if (wparam < down.len) down[wparam] = key + 1;
                    ReleaseSRWLockExclusive(&lock);
                }
                return DefWindowProcW(handle, message, wparam, lparam);
            },
            wm_key_up => {
                AcquireSRWLockExclusive(&lock);
                if (wparam < down.len) down[wparam] = 0;
                ReleaseSRWLockExclusive(&lock);
                return DefWindowProcW(handle, message, wparam, lparam);
            },
            // Keys that go up while the window has not the focus do not tell it.
            wm_kill_focus => {
                AcquireSRWLockExclusive(&lock);
                down = @splat(0);
                physical_state.tracker.releaseAll();
                releaseButtons();
                preedit_len = 0;
                ReleaseSRWLockExclusive(&lock);
                return DefWindowProcW(handle, message, wparam, lparam);
            },
            // Another window took the mouse while a button was held: its release does
            // not come here. lparam is the window that takes it: this window itself when
            // a second button calls SetCapture again, which releases nothing. (Our
            // ReleaseCapture after the last button also sends this, with the buttons
            // already up.)
            wm_capture_changed => {
                if (lparam != @as(isize, @bitCast(@intFromPtr(handle)))) {
                    AcquireSRWLockExclusive(&lock);
                    releaseButtons();
                    ReleaseSRWLockExclusive(&lock);
                }
                return 0;
            },
            // In a focused GUI-FIELD the field shows the text being converted itself:
            // the IME's own composition window is not opened (DefWindowProcW is not
            // called). Elsewhere the IME works as before.
            wm_ime_start_composition => {
                if (!imeActive()) return DefWindowProcW(handle, message, wparam, lparam);
                placeIme(handle.?);
                return 0;
            },
            wm_ime_composition => {
                const state = imeState();
                if (!state.active) return DefWindowProcW(handle, message, wparam, lparam);
                composition(handle.?, lparam, state.generation);
                return 0;
            },
            // The IME's own composition window is not wanted in a focused field.
            wm_ime_set_context => {
                const bits: usize = @bitCast(lparam);
                const shown = if (wparam != 0 and imeActive()) bits & ~isc_show_composition_window else bits;
                return DefWindowProcW(handle, message, wparam, @bitCast(shown));
            },
            // The caret's place on the screen moves with the window's size.
            wm_size => {
                if (imeActive()) placeIme(handle.?);
                return DefWindowProcW(handle, message, wparam, lparam);
            },
            wm_ime_end_composition => {
                AcquireSRWLockExclusive(&lock);
                preedit_len = 0;
                ReleaseSRWLockExclusive(&lock);
                if (!imeActive()) return DefWindowProcW(handle, message, wparam, lparam);
                return 0;
            },
            wm_ime_caret => {
                placeIme(handle.?);
                return 0;
            },
            wm_char => {
                // The key of the character, from the scan code WM_CHAR carries (keys
                // pressed in between do not change it).
                const bits: usize = @bitCast(lparam);
                const virtual_key: usize = MapVirtualKeyW(@intCast((bits >> 16) & 0xFF), map_scan_to_virtual);
                AcquireSRWLockExclusive(&lock);
                pushCharacter(@truncate(wparam), if (virtual_key == 0) no_key else virtual_key);
                ReleaseSRWLockExclusive(&lock);
                return 0;
            },
            wm_mouse_move...wm_middle_up => {
                mouseMoved(handle, wparam, lparam);
                // While a button is held, the mouse is followed also outside the window.
                if (wparam & (button_left | button_right | button_middle) != 0) {
                    if (message != wm_mouse_move) _ = SetCapture(handle);
                } else _ = ReleaseCapture();
                return 0;
            },
            wm_mouse_wheel => {
                wheelTurned(wparam);
                return 0;
            },
            wm_new_image => {
                AcquireSRWLockExclusive(&lock);
                update_pending = false;
                const resize = resize_pending;
                resize_pending = false;
                const size = windowSize(handle.?, width, height);
                ReleaseSRWLockExclusive(&lock);
                // A fullscreen window keeps covering its screen.
                if (resize and !fullscreen_on) {
                    _ = SetWindowPos(handle, null, 0, 0, size[0], size[1], no_move | no_z_order | no_activate);
                    keepInWorkArea(handle.?);
                    // The image's size changed: the caret's place on the screen too.
                    if (imeActive()) placeIme(handle.?);
                }
                _ = InvalidateRect(handle, null, 0);
                return 0;
            },
            // About to move to a monitor of another DPI: the size Windows then suggests
            // keeps the client area's proportions exactly (by default it scales the
            // whole window, frame included).
            wm_get_dpi_scaled_size => {
                if (fullscreen_on) return 0;
                const size: *[2]i32 = @ptrFromInt(@as(usize, @bitCast(lparam)));
                const scaled = dpiScaledSize(handle.?, size.*, @truncate(wparam)) orelse return 0;
                size.* = scaled;
                return 1;
            },
            // Moved to a monitor of another DPI: take the size Windows suggests. The image
            // is laid out again in the client area it gets; WINDOW-SIZE is not restored.
            wm_dpi_changed => {
                const suggested: *const Rect = @ptrFromInt(@as(usize, @bitCast(lparam)));
                if (!fullscreen_on) _ = SetWindowPos(handle, null, suggested.left, suggested.top, suggested.right - suggested.left, suggested.bottom - suggested.top, no_z_order | no_activate);
                _ = InvalidateRect(handle, null, 0);
                return 0;
            },
            wm_fullscreen => {
                applyFullscreen(handle.?);
                return 0;
            },
            wm_cursor => {
                applyCursor(handle.?);
                return 0;
            },
            // Alt+Enter leaves fullscreen; it is not a key for INKEY. Bit 29 of lparam is
            // set when Alt is down (Enter alone also comes here when no window has the
            // focus); bit 30 when the key was down already (a repeat, left alone).
            wm_system_key_down => {
                const bits: usize = @bitCast(lparam);
                const alt = bits & (1 << 29) != 0;
                const repeat = bits & (1 << 30) != 0;
                if (wparam == vk_return and alt and !repeat and fullscreen_on) {
                    AcquireSRWLockExclusive(&lock);
                    fullscreen_wanted = false;
                    ReleaseSRWLockExclusive(&lock);
                    applyFullscreen(handle.?);
                    return 0;
                }
                return DefWindowProcW(handle, message, wparam, lparam);
            },
            // The character of Alt+Enter would only beep.
            wm_system_char => {
                if (wparam == 13) return 0;
                return DefWindowProcW(handle, message, wparam, lparam);
            },
            wm_set_cursor => {
                AcquireSRWLockExclusive(&lock);
                const visible = cursor_visible;
                ReleaseSRWLockExclusive(&lock);
                if (!visible and (@as(usize, @bitCast(lparam)) & 0xFFFF) == hit_client) {
                    _ = SetCursor(null);
                    return 1;
                }
                return DefWindowProcW(handle, message, wparam, lparam);
            },
            wm_destroy => {
                AcquireSRWLockExclusive(&lock);
                window = null;
                update_pending = false;
                windowGone();
                ReleaseSRWLockExclusive(&lock);
                PostQuitMessage(0);
                return 0;
            },
            else => return DefWindowProcW(handle, message, wparam, lparam),
        }
    }

    fn close() void {
        AcquireSRWLockExclusive(&lock);
        const current = window;
        ReleaseSRWLockExclusive(&lock);
        if (current) |handle| _ = PostMessageW(handle, wm_close, 0, 0);
        // After a window that took too long, the thread may still be in CreateWindowExW:
        // it is left to the end of the process without waiting.
        if (broken) return;
        if (thread) |running| {
            // A thread that has not ended in 5 seconds is left to the end of the process,
            // with its handle and the image it draws.
            if (WaitForSingleObject(running, 5000) != wait_object_0) return;
            _ = CloseHandle(running);
            thread = null;
        }
    }

    /// A window thread slower than the time open waits: SHOW fails at once, and the
    /// window made late is destroyed, so its thread ends.
    fn testLateWindow() !void {
        // The gate holds the window thread until the test lets it go, so open's time
        // surely runs out first.
        const gate = CreateEventW(null, 1, 0, null) orelse return error.SkipZigTest;
        defer _ = CloseHandle(gate);
        test_gate = gate;
        start_timeout_ms = 200;
        defer {
            broken = false;
            start_timeout_ms = 5000;
            test_gate = null;
        }
        var image: [4]u32 = @splat(0);
        var before = GetTickCount64();
        try std.testing.expectError(error.HostFailed, @This().show(null, &image, 2, 2, .{}, .{ 0, 0 }));
        // GetTickCount64 counts in steps of 10 to 16 ms; the bound above is loose.
        const waited = GetTickCount64() - before;
        try std.testing.expect(waited >= 150 and waited < 3000);
        try std.testing.expect(broken);
        // Broken: SHOW fails without starting another wait.
        before = GetTickCount64();
        try std.testing.expectError(error.HostFailed, @This().show(null, &image, 2, 2, .{}, .{ 0, 0 }));
        try std.testing.expect(GetTickCount64() - before < 150);
        _ = SetEvent(gate);
        const late = thread.?;
        try std.testing.expectEqual(wait_object_0, WaitForSingleObject(late, 5000));
        _ = CloseHandle(late);
        thread = null;
        AcquireSRWLockExclusive(&lock);
        defer ReleaseSRWLockExclusive(&lock);
        try std.testing.expect(window == null);
        try std.testing.expectEqual(.cancelled, start);
    }

    /// Losing the focus releases the buttons held, and closing puts the mouse nowhere.
    fn testMouseRelease() !void {
        AcquireSRWLockExclusive(&lock);
        defer ReleaseSRWLockExclusive(&lock);
        defer {
            mouse_x = -1;
            mouse_y = -1;
            mouse_buttons = 0;
            queued_buttons = 0;
            mouse_changed = false;
            mouse_count = 0;
        }
        mouse_x = 5;
        mouse_y = 6;
        mouse_buttons = 1;
        queued_buttons = 1;
        mouse_changed = false;
        mouse_count = 0;
        releaseButtons();
        try std.testing.expectEqual(@as(usize, 1), mouse_count);
        try std.testing.expectEqual(MouseItem{ .x = 5, .y = 6, .buttons = 0, .wheel = 0 }, mouse_queue[mouse_head]);
        try std.testing.expect(mouse_changed);
        try std.testing.expectEqual(@as(u8, 0), mouse_buttons);
        // Nothing more to release.
        releaseButtons();
        try std.testing.expectEqual(@as(usize, 1), mouse_count);
        mouse_count = 0;
        mouse_buttons = 2;
        queued_buttons = 2;
        down[65] = 'A' + 1;
        windowGone();
        try std.testing.expectEqual(@as(usize, 1), mouse_count);
        try std.testing.expectEqual(MouseItem{ .x = 5, .y = 6, .buttons = 0, .wheel = 0 }, mouse_queue[mouse_head]);
        try std.testing.expectEqual(@as(i32, -1), mouse_x);
        try std.testing.expectEqual(@as(i32, -1), mouse_y);
        try std.testing.expectEqual(@as(u8, 0), mouse_buttons);
        try std.testing.expectEqual(@as(u32, 0), down[65]);
    }

    /// Characters are queued whole, as Unicode scalars, and Ctrl+C comes first even when
    /// the queue is full.
    fn testCharacters() !void {
        const reset = struct {
            fn all() void {
                key_head = 0;
                key_count = 0;
                high_surrogate = 0;
                interrupt_pending = false;
                down = @splat(0);
                told = @splat(0);
            }
        };
        reset.all();
        defer reset.all();
        pushCharacter('A', 0x41);
        pushCharacter(0x3042, 0x41);
        pushCharacter(0xD83D, 0x41);
        pushCharacter(0xDE00, 0x41);
        // A low surrogate alone is no character.
        pushCharacter(0xDE00, 0x41);
        pushCharacter(interrupt_character, 0x43);
        try std.testing.expectEqual(@as(usize, 3), key_count);
        try std.testing.expectEqual(forth.InputEvent{ .window_text = 3 }, @This().poll().?);
        try std.testing.expectEqual(forth.InputEvent{ .window_text = 'A' }, @This().poll().?);
        // Another code of the same key: the A is released first.
        try std.testing.expectEqual(forth.InputEvent{ .window_key_release = 'A' }, @This().poll().?);
        try std.testing.expectEqual(forth.InputEvent{ .window_text = 0x3042 }, @This().poll().?);
        try std.testing.expectEqual(forth.InputEvent{ .window_text = 0x1F600 }, @This().poll().?);
        reset.all();
        for (0..keys.len) |_| pushCharacter('x', no_key);
        pushCharacter(0x3042, no_key);
        try std.testing.expectEqual(keys.len, key_count);
        pushCharacter(interrupt_character, no_key);
        try std.testing.expectEqual(forth.InputEvent{ .window_text = 3 }, @This().poll().?);
        try std.testing.expectEqual(forth.InputEvent{ .window_text = 'x' }, @This().poll().?);
        try std.testing.expectEqual(keys.len - 1, key_count);
        try std.testing.expectEqual(@as(u32, 'x'), keys[(key_head + key_count - 1) % keys.len].code);
    }

    /// The IME's text as UTF-8, cut by whole characters, and the caret that clears it.
    fn testIme() !void {
        var out: [8]u8 = undefined;
        // あ, 😀 (a surrogate pair), and a lone low surrogate left out.
        const units = [_]u16{ 0x3042, 0xD83D, 0xDE00, 0xDC00, 'a' };
        try std.testing.expectEqualStrings("\u{3042}\u{1F600}a", out[0..utf16ToUtf8(&out, &units)]);
        // Only whole characters fit: あ (3 bytes) and not the 4 of 😀 in 6.
        try std.testing.expectEqualStrings("\u{3042}", out[0..utf16ToUtf8(out[0..6], &units)]);
        // A high surrogate at the end is left out.
        try std.testing.expectEqual(@as(usize, 0), utf16ToUtf8(&out, &.{0xD83D}));
        defer {
            ime_caret = .{};
            preedit_len = 0;
        }
        preedit_len = utf16ToUtf8(&preedit, &units);
        var two: [4]u8 = undefined;
        // A copy cut inside 😀 keeps あ only.
        try std.testing.expectEqual(@as(usize, 3), try @This().imePreedit(null, &two));
        const generation = ime_generation;
        try @This().imeCaret(null, true, 1, 2, 8);
        try std.testing.expect(ime_caret.active);
        try std.testing.expect(preedit_len != 0);
        try std.testing.expectEqual(generation +% 1, ime_generation);
        // A caret that moves in the same field is not another field.
        try @This().imeCaret(null, true, 5, 2, 8);
        try std.testing.expectEqual(generation +% 1, ime_generation);
        try @This().imeCaret(null, false, 1, 2, 8);
        try std.testing.expectEqual(@as(usize, 0), preedit_len);
        try std.testing.expectEqual(generation +% 2, ime_generation);
    }
};

test "the Windows window gives the IME's text as UTF-8 for GUI-FIELD" {
    if (comptime builtin.os.tag == .windows) try win32.testIme() else return error.SkipZigTest;
}

test "the Windows window queues characters whole and tells Ctrl+C first" {
    if (comptime builtin.os.tag == .windows) try win32.testCharacters() else return error.SkipZigTest;
}

test "the Windows window releases the mouse buttons when it loses the focus or closes" {
    if (comptime builtin.os.tag == .windows) try win32.testMouseRelease() else return error.SkipZigTest;
}

test "the Windows window stops waiting after its time and destroys the late window" {
    if (comptime builtin.os.tag == .windows) try win32.testLateWindow() else return error.SkipZigTest;
}
