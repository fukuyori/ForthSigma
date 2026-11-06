//! The graphics window of the Windows host, for SHOW. The window has a thread of its
//! own that runs its messages, so it can be moved, resized, and closed while Forth
//! waits for input. SHOW copies the image under a lock and asks the window to draw it
//! again; a window the user closed is opened again by the next SHOW. Other hosts have
//! no window (`available` is false).

const std = @import("std");
const builtin = @import("builtin");
const forth = @import("forth.zig");

pub const available = builtin.os.tag == .windows;

/// The host's window_fn: shows the pixels, opening the window when it is not open.
pub const show = if (available) win32.show else unsupported;

/// The next key or mouse change in the window, for INKEY and MOUSE; null when none.
pub fn poll() ?forth.InputEvent {
    return if (available) win32.poll() else null;
}

/// Closes the window and waits for its thread, before the program ends.
pub fn close() void {
    if (available) win32.close();
}

fn unsupported(_: ?*anyopaque, _: []const u32, _: u32, _: u32, _: forth.ColorMode) forth.RuntimeError!void {
    return error.HostUnavailable;
}

const win32 = struct {
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

    const overlapped_window: u32 = 0x00CF0000;
    const use_default: i32 = @bitCast(@as(u32, 0x80000000));
    const wm_destroy = 0x0002;
    const wm_close = 0x0010;
    const wm_paint = 0x000F;
    const wm_erase_background = 0x0014;
    const wm_kill_focus = 0x0008;
    const wm_key_down = 0x0100;
    const wm_key_up = 0x0101;
    const wm_char = 0x0102;
    const wm_mouse_move = 0x0200;
    const wm_left_down = 0x0201;
    const wm_middle_up = 0x0208;
    const button_left: usize = 0x0001;
    const button_right: usize = 0x0002;
    const button_middle: usize = 0x0010;
    /// Sent by SHOW: draw the new image; wparam is 1 when its size changed.
    const wm_new_image = 0x8000;
    const show_no_activate = 4;
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
    /// The largest client area a new window gets; a larger image is drawn smaller.
    const max_client_width = 1600;
    const max_client_height = 1200;

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
    /// full), and the mouse: the pixel of the image under it and its buttons.
    var keys: [64]KeyEvent = undefined;
    var key_head: usize = 0;
    var key_count: usize = 0;
    var high_surrogate: u16 = 0;
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

    // Used only by the thread that runs Forth.
    var thread: ?Handle = null;
    var class_registered = false;
    var ready: ?Handle = null;
    var opened = false;

    fn show(_: ?*anyopaque, image: []const u32, image_width: u32, image_height: u32, mode: forth.ColorMode, size: [2]u32) forth.RuntimeError!void {
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
                if (holdable(key.code)) told[virtual_key] = key.code + 1;
            }
            key_head = (key_head + 1) % keys.len;
            key_count -= 1;
            return .{ .window_key = key.code };
        }
        // The keys told down that the window no longer has down.
        for (&told, down) |*code, now| {
            if (code.* == 0 or code.* == now) continue;
            const old = code.* - 1;
            code.* = 0;
            return .{ .window_key_release = old };
        }
        if (!mouse_changed) return null;
        mouse_changed = false;
        return .{ .window_mouse = .{ .x = mouse_x, .y = mouse_y, .buttons = mouse_buttons } };
    }

    /// A key pressed, and its virtual key (`no_key` for the bytes of a character after
    /// the first).
    const KeyEvent = struct { code: u32, virtual_key: usize };
    const no_key = std.math.maxInt(usize);

    /// The codes KEY-HELD? tells: one byte (ASCII), and the keys from 256 up.
    fn holdable(code: u32) bool {
        return code < 0x80 or code >= 256;
    }

    /// Called with the lock held.
    fn pushKey(key: u32, virtual_key: usize) void {
        if (key_count == keys.len) return;
        keys[(key_head + key_count) % keys.len] = .{ .code = key, .virtual_key = virtual_key };
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
        var bytes: [4]u8 = undefined;
        const length = std.unicode.utf8Encode(code_point, &bytes) catch return;
        for (bytes[0..length], 0..) |byte, index| pushKey(byte, if (index == 0) virtual_key else no_key);
        // A character of one byte is held until its key goes up.
        if (code_point < 0x80 and virtual_key < down.len) down[virtual_key] = code_point + 1;
    }

    /// Where the image is drawn in a client area: as large as fits with its proportions,
    /// in the middle; the rest is black. Called with the lock held.
    fn fitted(client_width: i32, client_height: i32) Rect {
        const cw: i64 = @max(client_width, 1);
        const ch: i64 = @max(client_height, 1);
        const iw: i64 = @max(width, 1);
        const ih: i64 = @max(height, 1);
        // The wider of the two fills its width; the other its height.
        var w: i64 = cw;
        var h: i64 = @max(1, @divFloor(ih * cw, iw));
        if (h > ch) {
            h = ch;
            w = @max(1, @divFloor(iw * ch, ih));
        }
        const left: i32 = @intCast(@divFloor(cw - w, 2));
        const top: i32 = @intCast(@divFloor(ch - h, 2));
        return .{ .left = left, .top = top, .right = left + @as(i32, @intCast(w)), .bottom = top + @as(i32, @intCast(h)) };
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
        const shown_width: i64 = @max(place.right - place.left, 1);
        const shown_height: i64 = @max(place.bottom - place.top, 1);
        mouse_x = @intCast(std.math.clamp(@divFloor((x - place.left) * width, shown_width), -1 << 20, 1 << 20));
        mouse_y = @intCast(std.math.clamp(@divFloor((y - place.top) * height, shown_height), -1 << 20, 1 << 20));
        var buttons: u8 = 0;
        if (wparam & button_left != 0) buttons |= 1;
        if (wparam & button_right != 0) buttons |= 2;
        if (wparam & button_middle != 0) buttons |= 4;
        mouse_buttons = buttons;
        mouse_changed = true;
    }

    /// Only called when there is no window: the old thread, if any, is ending (after
    /// WM_DESTROY, or after a window it could not create), so waiting for it ends.
    fn open() forth.RuntimeError!void {
        if (thread) |old| {
            _ = WaitForSingleObject(old, infinite);
            _ = CloseHandle(old);
            thread = null;
        }
        const event = CreateEventW(null, 1, 0, null) orelse return error.HostFailed;
        defer _ = CloseHandle(event);
        ready = event;
        opened = false;
        thread = CreateThread(null, 0, run, null, 0, null) orelse return error.HostFailed;
        _ = WaitForSingleObject(event, infinite);
        if (!opened) return error.HostFailed;
    }

    /// The size of a client area for the image, at most the largest a new window gets,
    /// keeping the image's proportions.
    fn clientSize(image_width: u32, image_height: u32) [2]i32 {
        if (requested[0] != 0) return .{ @intCast(requested[0]), @intCast(requested[1]) };
        var w: u64 = @max(image_width, 1);
        var h: u64 = @max(image_height, 1);
        if (w > max_client_width) {
            h = @max(1, h * max_client_width / w);
            w = max_client_width;
        }
        if (h > max_client_height) {
            w = @max(1, w * max_client_height / h);
            h = max_client_height;
        }
        return .{ @intCast(w), @intCast(h) };
    }

    fn windowSize(image_width: u32, image_height: u32) [2]i32 {
        const client = clientSize(image_width, image_height);
        var rect = Rect{ .right = client[0], .bottom = client[1] };
        _ = AdjustWindowRect(&rect, overlapped_window, 0);
        return .{ rect.right - rect.left, rect.bottom - rect.top };
    }

    fn run(_: ?*anyopaque) callconv(.winapi) u32 {
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
        AcquireSRWLockExclusive(&lock);
        const size = windowSize(width, height);
        ReleaseSRWLockExclusive(&lock);
        const handle = CreateWindowExW(0, class_name, title, overlapped_window, use_default, use_default, size[0], size[1], null, null, instance, null);
        if (handle == null) {
            _ = SetEvent(ready.?);
            return 1;
        }
        AcquireSRWLockExclusive(&lock);
        window = handle;
        update_pending = false;
        resize_pending = false;
        ReleaseSRWLockExclusive(&lock);
        // The console keeps the keyboard, so typing goes on there.
        _ = ShowWindow(handle, show_no_activate);
        opened = true;
        _ = SetEvent(ready.?);
        var message: Message = undefined;
        while (GetMessageW(&message, null, 0, 0) > 0) {
            _ = TranslateMessage(&message);
            _ = DispatchMessageW(&message);
        }
        return 0;
    }

    fn windowProc(handle: ?Handle, message: u32, wparam: usize, lparam: isize) callconv(.winapi) isize {
        switch (message) {
            wm_paint => {
                var paint: PaintStruct = undefined;
                const dc = BeginPaint(handle, &paint);
                var client = Rect{};
                _ = GetClientRect(handle, &client);
                _ = SetStretchBltMode(dc, color_on_color);
                AcquireSRWLockExclusive(&lock);
                // Rows from the top: a negative height.
                const info = BitmapInfo{ .header = .{ .width = @intCast(width), .height = -@as(i32, @intCast(height)) } };
                const place = fitted(client.right, client.bottom);
                if (pixels.len != 0) _ = StretchDIBits(dc, place.left, place.top, place.right - place.left, place.bottom - place.top, 0, 0, @intCast(width), @intCast(height), pixels.ptr, &info, 0, source_copy);
                ReleaseSRWLockExclusive(&lock);
                // Black around the image: above and below it, then left and right of it.
                _ = PatBlt(dc, 0, 0, client.right, place.top, blackness);
                _ = PatBlt(dc, 0, place.bottom, client.right, client.bottom - place.bottom, blackness);
                _ = PatBlt(dc, 0, place.top, place.left, place.bottom - place.top, blackness);
                _ = PatBlt(dc, place.right, place.top, client.right - place.right, place.bottom - place.top, blackness);
                _ = EndPaint(handle, &paint);
                return 0;
            },
            wm_erase_background => return 1,
            wm_key_down => {
                if (virtualKey(wparam)) |key| {
                    AcquireSRWLockExclusive(&lock);
                    pushKey(key, wparam);
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
                ReleaseSRWLockExclusive(&lock);
                return DefWindowProcW(handle, message, wparam, lparam);
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
            wm_new_image => {
                AcquireSRWLockExclusive(&lock);
                update_pending = false;
                const resize = resize_pending;
                resize_pending = false;
                const size = windowSize(width, height);
                ReleaseSRWLockExclusive(&lock);
                if (resize) _ = SetWindowPos(handle, null, 0, 0, size[0], size[1], no_move | no_z_order | no_activate);
                _ = InvalidateRect(handle, null, 0);
                return 0;
            },
            wm_destroy => {
                AcquireSRWLockExclusive(&lock);
                window = null;
                update_pending = false;
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
        if (thread) |running| {
            // A thread that has not ended in 5 seconds is left to the end of the process,
            // with its handle and the image it draws.
            if (WaitForSingleObject(running, 5000) != wait_object_0) return;
            _ = CloseHandle(running);
            thread = null;
        }
    }
};
