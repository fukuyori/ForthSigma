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

/// Closes the window and waits for its thread, before the program ends.
pub fn close() void {
    if (available) win32.close();
}

fn unsupported(_: ?*anyopaque, _: []const u32, _: u32, _: u32) forth.RuntimeError!void {
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
    extern "kernel32" fn GetModuleHandleW(?[*:0]const u16) callconv(.winapi) ?Handle;
    extern "kernel32" fn CreateThread(?*anyopaque, usize, *const fn (?*anyopaque) callconv(.winapi) u32, ?*anyopaque, u32, ?*u32) callconv(.winapi) ?Handle;
    extern "kernel32" fn CreateEventW(?*anyopaque, i32, i32, ?[*:0]const u16) callconv(.winapi) ?Handle;
    extern "kernel32" fn SetEvent(Handle) callconv(.winapi) i32;
    extern "kernel32" fn WaitForSingleObject(Handle, u32) callconv(.winapi) u32;
    extern "kernel32" fn CloseHandle(Handle) callconv(.winapi) i32;
    extern "kernel32" fn AcquireSRWLockExclusive(*SrwLock) callconv(.winapi) void;
    extern "kernel32" fn ReleaseSRWLockExclusive(*SrwLock) callconv(.winapi) void;

    const overlapped_window: u32 = 0x00CF0000;
    const use_default: i32 = @bitCast(@as(u32, 0x80000000));
    const wm_destroy = 0x0002;
    const wm_close = 0x0010;
    const wm_paint = 0x000F;
    const wm_erase_background = 0x0014;
    /// Sent by SHOW: draw the new image; wparam is 1 when its size changed.
    const wm_new_image = 0x8000;
    const show_no_activate = 4;
    const no_move: u32 = 0x0002;
    const no_z_order: u32 = 0x0004;
    const no_activate: u32 = 0x0010;
    const arrow_cursor: usize = 32512;
    const color_on_color = 3;
    const source_copy: u32 = 0x00CC0020;
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
    var window: ?Handle = null;
    /// A wm_new_image message is waiting in the window's queue: SHOW sends no other, so
    /// the queue cannot fill, and that message draws the latest image.
    var update_pending = false;
    /// The image's size changed since the window last fitted it.
    var resize_pending = false;

    // Used only by the thread that runs Forth.
    var thread: ?Handle = null;
    var class_registered = false;
    var ready: ?Handle = null;
    var opened = false;

    fn show(_: ?*anyopaque, image: []const u32, image_width: u32, image_height: u32) forth.RuntimeError!void {
        AcquireSRWLockExclusive(&lock);
        const resized = image_width != width or image_height != height;
        if (pixels.len != image.len) {
            const buffer = std.heap.c_allocator.alloc(u32, image.len) catch {
                ReleaseSRWLockExclusive(&lock);
                return error.MemoryExhausted;
            };
            if (pixels.len != 0) std.heap.c_allocator.free(pixels);
            pixels = buffer;
        }
        @memcpy(pixels, image);
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
                .style = 0,
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
                if (pixels.len != 0) _ = StretchDIBits(dc, 0, 0, client.right, client.bottom, 0, 0, @intCast(width), @intCast(height), pixels.ptr, &info, 0, source_copy);
                ReleaseSRWLockExclusive(&lock);
                _ = EndPaint(handle, &paint);
                return 0;
            },
            wm_erase_background => return 1,
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
