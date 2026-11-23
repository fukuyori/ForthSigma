//! The host's displays for DISPLAYS (tque 1038). Windows uses the native monitor APIs,
//! Linux/X11 uses RandR 1.5 (host_display_linux.zig), and macOS uses NSScreen with the
//! active CoreGraphics mode (host_display_macos.zig). Other hosts leave the list empty.

const std = @import("std");
const builtin = @import("builtin");
const display_info = @import("core/display_info.zig");
const linux_enabled = builtin.os.tag == .linux and @import("build_options").graphics and @import("build_options").x11;
const macos_enabled = builtin.os.tag == .macos and @import("build_options").graphics;
const linux_display = if (linux_enabled) @import("host_display_linux.zig") else struct {};
const macos_display = if (macos_enabled) @import("host_display_macos.zig") else struct {};

pub const internal_child_argument = if (macos_enabled) macos_display.child_argument else "";

pub const available = builtin.os.tag == .windows or linux_enabled or macos_enabled;

/// The host's displays_fn: fills the empty snapshot.
pub fn snapshot(_: ?*anyopaque, out: *display_info.Snapshot) void {
    if (builtin.os.tag == .windows) win32.snapshot(out) else if (linux_enabled) linux_display.snapshot(out) else if (macos_enabled) macos_display.snapshot(out);
}

/// Configures the short-lived macOS display probe child.
pub fn initMac(executable_path: [:0]const u8, environment: [:null]const ?[*:0]const u8) void {
    if (macos_enabled) macos_display.init(executable_path, environment);
}

/// Runs the private macOS display probe child before the Forth VM starts.
pub fn runProbeChild() !u8 {
    if (macos_enabled) return macos_display.runChild();
    return error.HostUnavailable;
}

/// The host's window_size_fn: the size of the client area of the window with the window
/// system's identifier `id` (another program's window: the Tk window's), in physical
/// pixels on Windows, X server pixels on Linux (which a compositor may scale),
/// or null when there is no such window. Windows and Linux under X tell it.
pub fn windowSize(_: ?*anyopaque, id: u64) ?[2]u32 {
    if (builtin.os.tag == .windows) return win32.windowSize(id);
    if (linux_enabled) return linux_display.windowSize(id);
    return null;
}

/// Actual WM minimization for Tk under XWayland, which can retain its mapped
/// window and leave Tk's wm state cache at normal while WM_STATE says iconic.
pub fn windowMinimized(_: ?*anyopaque, id: u64) ?bool {
    if (linux_enabled) return linux_display.windowMinimized(id);
    return null;
}

/// The smallest terms of a fraction; 0 0 when the denominator is 0.
pub fn reduced(numerator: u32, denominator: u32) [2]u32 {
    if (denominator == 0) return .{ 0, 0 };
    const divisor = std.math.gcd(numerator, denominator);
    if (divisor == 0) return .{ 0, denominator };
    return .{ numerator / divisor, denominator / divisor };
}

const win32 = struct {
    const Rect = extern struct { left: i32 = 0, top: i32 = 0, right: i32 = 0, bottom: i32 = 0 };
    const MonitorInfoEx = extern struct {
        size: u32 = @sizeOf(MonitorInfoEx),
        monitor: Rect = .{},
        work: Rect = .{},
        flags: u32 = 0,
        device: [32]u16 = @splat(0),
    };
    const Luid = extern struct { low: u32, high: i32 };
    const Rational = extern struct { numerator: u32, denominator: u32 };
    const PathSource = extern struct { adapter: Luid, id: u32, mode_index: u32, status: u32 };
    const PathTarget = extern struct {
        adapter: Luid,
        id: u32,
        mode_index: u32,
        technology: u32,
        rotation: u32,
        scaling: u32,
        refresh: Rational,
        scan_line_ordering: u32,
        available: i32,
        status: u32,
    };
    const PathInfo = extern struct { source: PathSource, target: PathTarget, flags: u32 };
    const ModeInfo = extern struct { bytes: [64]u8 };
    const SourceName = extern struct {
        kind: u32 = 1, // DISPLAYCONFIG_DEVICE_INFO_GET_SOURCE_NAME
        size: u32 = @sizeOf(SourceName),
        adapter: Luid,
        id: u32,
        gdi_name: [32]u16 = @splat(0),
    };
    const EnumProc = *const fn (?*anyopaque, ?*anyopaque, *Rect, isize) callconv(.winapi) i32;
    const SetThreadContext = *const fn (isize) callconv(.winapi) isize;
    const GetDpiForMonitor = *const fn (?*anyopaque, i32, *u32, *u32) callconv(.winapi) i32;

    extern "user32" fn EnumDisplayMonitors(?*anyopaque, ?*const Rect, EnumProc, isize) callconv(.winapi) i32;
    extern "user32" fn GetMonitorInfoW(?*anyopaque, *MonitorInfoEx) callconv(.winapi) i32;
    extern "user32" fn EnumDisplaySettingsW([*:0]const u16, u32, [*]u8) callconv(.winapi) i32;
    extern "kernel32" fn LoadLibraryExA([*:0]const u8, ?*anyopaque, u32) callconv(.winapi) ?*anyopaque;
    /// LOAD_LIBRARY_SEARCH_SYSTEM32: the system's own DLL, not one of that name elsewhere.
    const search_system32: u32 = 0x0000_0800;
    extern "kernel32" fn GetProcAddress(?*anyopaque, [*:0]const u8) callconv(.winapi) ?*anyopaque;

    const GetBufferSizes = *const fn (u32, *u32, *u32) callconv(.winapi) i32;
    const QueryConfig = *const fn (u32, *u32, [*]PathInfo, *u32, [*]ModeInfo, ?*u32) callconv(.winapi) i32;
    const GetDeviceInfo = *const fn (*SourceName) callconv(.winapi) i32;

    /// The functions of Windows 7, 8.1 and 10 that older Windows lacks, looked up once.
    const Optional = struct {
        set_thread_context: ?SetThreadContext = null,
        dpi_for_monitor: ?GetDpiForMonitor = null,
        buffer_sizes: ?GetBufferSizes = null,
        query_config: ?QueryConfig = null,
        device_info: ?GetDeviceInfo = null,
    };
    var optional: Optional = .{};
    var optional_loaded = false;

    const query_only_active_paths: u32 = 2;
    const enum_current_settings: u32 = 0xFFFF_FFFF;
    /// DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2 (Windows 10 1703).
    const per_monitor_aware_v2: isize = -4;
    const max_paths = 64;

    const Refresh = struct { device: [32]u16, rate: Rational };
    const Pass = struct {
        out: *display_info.Snapshot,
        /// The thread is per-monitor aware while the monitors are enumerated: only then
        /// is the DPI Windows gives the display's own.
        aware: bool = false,
        refresh: [max_paths]Refresh = undefined,
        refresh_count: usize = 0,
    };

    fn load() void {
        if (optional_loaded) return;
        optional_loaded = true;
        if (LoadLibraryExA("user32.dll", null, search_system32)) |user32| {
            optional.set_thread_context = @ptrCast(GetProcAddress(user32, "SetThreadDpiAwarenessContext"));
            optional.buffer_sizes = @ptrCast(GetProcAddress(user32, "GetDisplayConfigBufferSizes"));
            optional.query_config = @ptrCast(GetProcAddress(user32, "QueryDisplayConfig"));
            optional.device_info = @ptrCast(GetProcAddress(user32, "DisplayConfigGetDeviceInfo"));
        }
        if (LoadLibraryExA("shcore.dll", null, search_system32)) |shcore| optional.dpi_for_monitor = @ptrCast(GetProcAddress(shcore, "GetDpiForMonitor"));
    }

    /// The refresh rates of the active paths as fractions, by the display's device name.
    fn readRefresh(pass: *Pass) void {
        const sizes = optional.buffer_sizes orelse return;
        const query = optional.query_config orelse return;
        const info = optional.device_info orelse return;
        var paths_n: u32 = 0;
        var modes_n: u32 = 0;
        if (sizes(query_only_active_paths, &paths_n, &modes_n) != 0) return;
        var paths: [max_paths]PathInfo = undefined;
        var modes: [2 * max_paths]ModeInfo = undefined;
        if (paths_n > paths.len or modes_n > modes.len) return;
        if (query(query_only_active_paths, &paths_n, &paths, &modes_n, &modes, null) != 0) return;
        for (paths[0..paths_n]) |path| {
            var source = SourceName{ .adapter = path.source.adapter, .id = path.source.id };
            if (info(&source) != 0) continue;
            pass.refresh[pass.refresh_count] = .{ .device = source.gdi_name, .rate = path.target.refresh };
            pass.refresh_count += 1;
        }
    }

    extern "user32" fn IsWindow(?*anyopaque) callconv(.winapi) i32;
    extern "user32" fn GetClientRect(?*anyopaque, *Rect) callconv(.winapi) i32;

    /// The client area of any program's window, asked in a per-monitor-aware thread
    /// context: Windows then gives its size in physical pixels also when the window's
    /// own program is not aware of the displays' scales and is shown stretched (as Tk
    /// 8.6 is). Where the context cannot be set, the size is as Windows gives it to a
    /// program that is not aware either.
    fn windowSize(id: u64) ?[2]u32 {
        if (id == 0) return null;
        const handle: *anyopaque = @ptrFromInt(std.math.cast(usize, id) orelse return null);
        if (IsWindow(handle) == 0) return null;
        load();
        const before: isize = if (optional.set_thread_context) |set| set(per_monitor_aware_v2) else 0;
        // The function is there and refused: the size would be in an unknown unit, so
        // none is told. Without the function (Windows before 10 1703) the thread is
        // not aware, and the size is as Windows gives it to such a program.
        if (optional.set_thread_context != null and before == 0) return null;
        defer if (before != 0) {
            _ = optional.set_thread_context.?(before);
        };
        var client = Rect{};
        if (GetClientRect(handle, &client) == 0) return null;
        return .{ @intCast(@max(client.right - client.left, 0)), @intCast(@max(client.bottom - client.top, 0)) };
    }

    fn sameName(a: *const [32]u16, b: *const [32]u16) bool {
        for (a, b) |x, y| {
            if (x != y) return false;
            if (x == 0) return true;
        }
        return true;
    }

    fn monitorProc(monitor: ?*anyopaque, _: ?*anyopaque, _: *Rect, data: isize) callconv(.winapi) i32 {
        const pass: *Pass = @ptrFromInt(@as(usize, @bitCast(data)));
        var info = MonitorInfoEx{};
        if (GetMonitorInfoW(monitor, &info) == 0) return 1;
        var display = display_info.Display{
            .id = @intFromPtr(monitor),
            .rect = .{ info.monitor.left, info.monitor.top, info.monitor.right - info.monitor.left, info.monitor.bottom - info.monitor.top },
            .work = .{ info.work.left, info.work.top, info.work.right - info.work.left, info.work.bottom - info.work.top },
            .primary = info.flags & 1 != 0,
        };
        if (pass.aware) {
            if (optional.dpi_for_monitor) |dpi_for_monitor| {
                var x: u32 = 0;
                var y: u32 = 0;
                // MDT_EFFECTIVE_DPI: 96 times the scale the user chose for the display.
                // A thread that is not per-monitor aware gets 96 for every display, so
                // the scale is left unknown there rather than told as 1.
                if (dpi_for_monitor(monitor, 0, &x, &y) == 0 and x != 0) display.scale = reduced(x, 96);
            }
        }
        for (pass.refresh[0..pass.refresh_count]) |entry| {
            if (!sameName(&entry.device, &info.device)) continue;
            if (entry.rate.numerator != 0 and entry.rate.denominator != 0) display.hz = reduced(entry.rate.numerator, entry.rate.denominator);
            break;
        }
        if (display.hz[1] == 0) {
            // The whole Hz of the display's mode (DEVMODEW as bytes: dmSize at 68,
            // dmDisplayFrequency at 184); 0 and 1 stand for the hardware's default.
            var mode: [220 + 64]u8 = @splat(0);
            std.mem.writeInt(u16, mode[68..70], 220, .little);
            if (EnumDisplaySettingsW(@ptrCast(&info.device), enum_current_settings, &mode) != 0) {
                const frequency = std.mem.readInt(u32, mode[184..188], .little);
                if (frequency > 1) display.hz = .{ frequency, 1 };
            }
        }
        pass.out.add(display);
        return 1;
    }

    /// Enumerates in a per-monitor-aware thread context, so that the places and sizes are
    /// physical pixels also where the displays have different scales, and puts the
    /// thread's context back: the console and the rest of the main thread stay as they were.
    /// Where the context cannot be set (Windows before 10 1703, or the call fails), the
    /// places and sizes are as Windows gives them to a program unaware of DPI, and the
    /// scales are not told.
    fn snapshot(out: *display_info.Snapshot) void {
        load();
        var pass = Pass{ .out = out };
        readRefresh(&pass);
        const before: isize = if (optional.set_thread_context) |set| set(per_monitor_aware_v2) else 0;
        pass.aware = before != 0;
        defer if (before != 0) {
            _ = optional.set_thread_context.?(before);
        };
        _ = EnumDisplayMonitors(null, null, monitorProc, @bitCast(@intFromPtr(&pass)));
    }
};

test "a fraction is given in its smallest terms" {
    try std.testing.expectEqual([2]u32{ 3, 2 }, reduced(144, 96));
    try std.testing.expectEqual([2]u32{ 1, 1 }, reduced(96, 96));
    try std.testing.expectEqual([2]u32{ 59951, 1000 }, reduced(59951, 1000));
    try std.testing.expectEqual([2]u32{ 0, 0 }, reduced(60, 0));
    try std.testing.expectEqual([2]u32{ 0, 1 }, reduced(0, 5));
}
