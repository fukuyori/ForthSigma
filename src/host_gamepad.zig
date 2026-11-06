//! Optional SDL3 backend (SDL 3.2 ABI), loaded on first GAMEPAD-POLL.
//! SDL supplies XInput, HID/DirectInput and known-controller mappings. Unknown
//! joysticks remain available as raw axes/buttons/hats. All calls run on main.
const std = @import("std");
const builtin = @import("builtin");
const gp = @import("core/gamepad.zig");
const Handle = *anyopaque;
const Guid = extern struct { bytes: [16]u8 };
const windows = builtin.os.tag == .windows;
// Zig's static musl ELF loader cannot resolve SDL's dependent shared libraries.
// Such builds remain usable without gamepads and report an unavailable backend.
const can_load = !(builtin.os.tag == .linux and builtin.link_mode == .static and
    (builtin.abi == .musl or builtin.abi == .musleabi or builtin.abi == .musleabihf));
extern "c" fn getenv([*:0]const u8) ?[*:0]const u8;
const Lib = if (windows) struct {
    handle: Handle,
    extern "kernel32" fn LoadLibraryExW([*:0]const u16, ?Handle, u32) callconv(.winapi) ?Handle;
    extern "kernel32" fn GetProcAddress(Handle, [*:0]const u8) callconv(.winapi) ?*anyopaque;
    extern "kernel32" fn FreeLibrary(Handle) callconv(.winapi) i32;
    fn open() !@This() {
        if (getenv("SIGMA_SDL3")) |path| {
            const wide = try std.unicode.utf8ToUtf16LeAllocZ(std.heap.c_allocator, std.mem.span(path));
            defer std.heap.c_allocator.free(wide);
            return .{ .handle = LoadLibraryExW(wide, null, 0x1000) orelse return error.NotFound };
        }
        // Application directory and system/default DLL directories, not the CWD.
        return .{ .handle = LoadLibraryExW(std.unicode.utf8ToUtf16LeStringLiteral("SDL3.dll"), null, 0x1000) orelse return error.NotFound };
    }
    fn lookup(self: *@This(), comptime T: type, name: [:0]const u8) ?T {
        return @ptrCast(GetProcAddress(self.handle, name.ptr) orelse return null);
    }
    fn close(self: *@This()) void {
        _ = FreeLibrary(self.handle);
    }
} else struct {
    lib: std.DynLib,
    fn open() !@This() {
        const path = if (getenv("SIGMA_SDL3")) |p| std.mem.span(p) else if (builtin.os.tag == .macos) "libSDL3.dylib" else "libSDL3.so.0";
        return .{ .lib = try std.DynLib.open(path) };
    }
    fn lookup(self: *@This(), comptime T: type, name: [:0]const u8) ?T {
        return self.lib.lookup(T, name);
    }
    fn close(self: *@This()) void {
        self.lib.close();
    }
};
const Api = struct {
    SDL_SetMainReady: *const fn () callconv(.c) void,
    SDL_InitSubSystem: *const fn (u32) callconv(.c) bool,
    SDL_QuitSubSystem: *const fn (u32) callconv(.c) void,
    SDL_GetJoysticks: *const fn (*c_int) callconv(.c) ?[*]u32,
    SDL_free: *const fn (?*anyopaque) callconv(.c) void,
    SDL_IsGamepad: *const fn (u32) callconv(.c) bool,
    SDL_OpenGamepad: *const fn (u32) callconv(.c) ?Handle,
    SDL_CloseGamepad: *const fn (Handle) callconv(.c) void,
    SDL_GetGamepadAxis: *const fn (Handle, c_int) callconv(.c) i16,
    SDL_GetGamepadButton: *const fn (Handle, c_int) callconv(.c) bool,
    SDL_UpdateGamepads: *const fn () callconv(.c) void,
    SDL_SetGamepadEventsEnabled: *const fn (bool) callconv(.c) void,
    SDL_SetJoystickEventsEnabled: *const fn (bool) callconv(.c) void,
    SDL_OpenJoystick: *const fn (u32) callconv(.c) ?Handle,
    SDL_CloseJoystick: *const fn (Handle) callconv(.c) void,
    SDL_JoystickConnected: *const fn (Handle) callconv(.c) bool,
    SDL_GetJoystickName: *const fn (Handle) callconv(.c) ?[*:0]const u8,
    SDL_GetJoystickGUID: *const fn (Handle) callconv(.c) Guid,
    SDL_GetNumJoystickAxes: *const fn (Handle) callconv(.c) c_int,
    SDL_GetNumJoystickButtons: *const fn (Handle) callconv(.c) c_int,
    SDL_GetNumJoystickHats: *const fn (Handle) callconv(.c) c_int,
    SDL_GetJoystickAxis: *const fn (Handle, c_int) callconv(.c) i16,
    SDL_GetJoystickButton: *const fn (Handle, c_int) callconv(.c) bool,
    SDL_GetJoystickHat: *const fn (Handle, c_int) callconv(.c) u8,
    SDL_AddGamepadMapping: *const fn ([*:0]const u8) callconv(.c) c_int,
};
const Open = struct { id: u32 = 0, joystick: ?Handle = null, gamepad: ?Handle = null };
var library: ?Lib = null;
var api: Api = undefined;
var opened: [gp.max_pads]Open = @splat(.{});
const subsystem = 0x2000;
pub const ops: gp.Ops = .{ .poll = poll, .mapping = mapping };

fn initialize() bool {
    if (comptime !can_load) return false;
    if (library != null) return true;
    var lib = Lib.open() catch return false;
    inline for (@typeInfo(Api).@"struct".field_names) |name| {
        @field(api, name) = lib.lookup(@FieldType(Api, name), name) orelse {
            lib.close();
            return false;
        };
    }
    api.SDL_SetMainReady();
    if (!api.SDL_InitSubSystem(subsystem)) {
        lib.close();
        return false;
    }
    api.SDL_SetGamepadEventsEnabled(false);
    api.SDL_SetJoystickEventsEnabled(false);
    library = lib;
    return true;
}
fn closePad(pad: *Open) void {
    if (pad.gamepad) |p| api.SDL_CloseGamepad(p);
    if (pad.joystick) |p| api.SDL_CloseJoystick(p);
    pad.* = .{};
}
pub fn close() void {
    if (library) |*lib| {
        for (&opened) |*pad| closePad(pad);
        api.SDL_QuitSubSystem(subsystem);
        lib.close();
        library = null;
    }
}
fn bounded(n: c_int, max: u8) u8 {
    return @intCast(@min(@max(n, 0), max));
}
fn readPad(slot: *Open) gp.Pad {
    const joy = slot.joystick.?;
    var result: gp.Pad = .{ .id = slot.id, .mapped = slot.gamepad != null };
    const hex = "0123456789abcdef";
    for (api.SDL_GetJoystickGUID(joy).bytes, 0..) |byte, i| {
        result.guid[i * 2] = hex[byte >> 4];
        result.guid[i * 2 + 1] = hex[byte & 15];
    }
    if (api.SDL_GetJoystickName(joy)) |name| {
        const text = std.mem.span(name);
        const n = @min(text.len, result.name.len);
        @memcpy(result.name[0..n], text[0..n]);
        result.name_len = @intCast(n);
    }
    if (slot.gamepad) |pad| {
        result.axis_count = 6;
        result.button_count = 26;
        result.hat_count = 1;
        for (0..6) |i| result.axes[i] = api.SDL_GetGamepadAxis(pad, @intCast(i));
        for (0..26) |i| if (api.SDL_GetGamepadButton(pad, @intCast(i))) {
            result.buttons |= @as(u32, 1) << @intCast(i);
        };
        // SDL button indices: up 11, down 12, left 13, right 14.
        for ([_]u5{ 11, 14, 12, 13 }, 0..) |button, direction| {
            if (result.buttons & (@as(u32, 1) << button) != 0) result.hats[0] |= @as(u8, 1) << @intCast(direction);
        }
    } else {
        result.axis_count = bounded(api.SDL_GetNumJoystickAxes(joy), 16);
        result.button_count = bounded(api.SDL_GetNumJoystickButtons(joy), 32);
        result.hat_count = bounded(api.SDL_GetNumJoystickHats(joy), 4);
        for (0..result.axis_count) |i| result.axes[i] = api.SDL_GetJoystickAxis(joy, @intCast(i));
        for (0..result.button_count) |i| if (api.SDL_GetJoystickButton(joy, @intCast(i))) {
            result.buttons |= @as(u32, 1) << @intCast(i);
        };
        for (0..result.hat_count) |i| result.hats[i] = api.SDL_GetJoystickHat(joy, @intCast(i));
    }
    return result;
}
pub fn poll(_: ?*anyopaque, snapshot: *gp.Snapshot) bool {
    snapshot.* = .{};
    if (!initialize()) return false;
    api.SDL_UpdateGamepads();
    var count: c_int = 0;
    const ids = api.SDL_GetJoysticks(&count) orelse return true;
    defer api.SDL_free(@ptrCast(ids));
    // Release removed devices before admitting replacements. Enumeration indices
    // may change; the SDL instance ID lets a caller identify a replacement.
    for (&opened) |*slot| if (slot.joystick) |joy| {
        if (!api.SDL_JoystickConnected(joy)) closePad(slot);
    };
    for (ids[0..@intCast(@max(count, 0))]) |id| {
        var slot: ?*Open = null;
        for (&opened) |*entry| if (entry.id == id) {
            slot = entry;
            break;
        };
        if (slot == null) {
            for (&opened) |*entry| if (entry.id == 0) {
                slot = entry;
                break;
            };
            const entry = slot orelse break;
            const joy = api.SDL_OpenJoystick(id) orelse continue;
            entry.* = .{ .id = id, .joystick = joy };
        }
        const entry = slot.?;
        if (entry.gamepad == null and api.SDL_IsGamepad(id)) entry.gamepad = api.SDL_OpenGamepad(id);
        snapshot.pads[snapshot.count] = readPad(entry);
        snapshot.count += 1;
        if (snapshot.count == gp.max_pads) break;
    }
    return true;
}
fn mapping(_: ?*anyopaque, text: []const u8) bool {
    if (text.len == 0 or text.len >= 4096 or std.mem.indexOfScalar(u8, text, 0) != null or !initialize()) return false;
    var buffer: [4096]u8 = undefined;
    @memcpy(buffer[0..text.len], text);
    buffer[text.len] = 0;
    return api.SDL_AddGamepadMapping(buffer[0..text.len :0]) >= 0;
}

// SDL 3.2's versioned virtual-device descriptor. Callbacks are unused/null.
const Virtual = extern struct {
    version: u32 = @sizeOf(Virtual),
    kind: u16 = 0,
    padding: u16 = 0,
    vendor: u16 = 0,
    product: u16 = 0,
    axes: u16 = 0,
    buttons: u16 = 0,
    balls: u16 = 0,
    hats: u16 = 0,
    touchpads: u16 = 0,
    sensors: u16 = 0,
    padding2: [2]u16 = .{ 0, 0 },
    button_mask: u32 = 0,
    axis_mask: u32 = 0,
    name: ?[*:0]const u8 = null,
    touchpad_desc: ?*anyopaque = null,
    sensor_desc: ?*anyopaque = null,
    userdata: ?*anyopaque = null,
    callbacks: [8]?*anyopaque = @splat(null),
};
fn findPad(snapshot: *const gp.Snapshot, id: u32) ?gp.Pad {
    for (snapshot.pads[0..snapshot.count]) |pad| if (pad.id == id) return pad;
    return null;
}
test "SDL3 virtual raw/mapped devices, remapping and hot unplug" {
    // Optional integration test: set SIGMA_SDL3 to the runtime library. Core
    // snapshot tests always run, even on machines without SDL or physical pads.
    if (!can_load or getenv("SIGMA_SDL3") == null) return error.SkipZigTest;
    try std.testing.expect(initialize());
    defer close();
    try std.testing.expectEqual(if (@sizeOf(usize) == 8) @as(usize, 136) else 84, @sizeOf(Virtual));
    const attach = library.?.lookup(*const fn (*const Virtual) callconv(.c) u32, "SDL_AttachVirtualJoystick").?;
    const detach = library.?.lookup(*const fn (u32) callconv(.c) bool, "SDL_DetachVirtualJoystick").?;
    const axis = library.?.lookup(*const fn (Handle, c_int, i16) callconv(.c) bool, "SDL_SetJoystickVirtualAxis").?;
    const button = library.?.lookup(*const fn (Handle, c_int, bool) callconv(.c) bool, "SDL_SetJoystickVirtualButton").?;
    const hat = library.?.lookup(*const fn (Handle, c_int, u8) callconv(.c) bool, "SDL_SetJoystickVirtualHat").?;
    const raw_id = attach(&.{ .axes = 4, .buttons = 8, .hats = 1, .name = "Sigma raw test" });
    try std.testing.expect(raw_id != 0);
    defer _ = detach(raw_id);
    const mapped_id = attach(&.{ .kind = 1, .axes = 6, .buttons = 15, .button_mask = 0x7fff, .axis_mask = 0x3f, .name = "Sigma mapped test" });
    try std.testing.expect(mapped_id != 0);
    defer _ = detach(mapped_id);
    const raw = api.SDL_OpenJoystick(raw_id).?;
    defer api.SDL_CloseJoystick(raw);
    const mapped = api.SDL_OpenJoystick(mapped_id).?;
    defer api.SDL_CloseJoystick(mapped);
    var snapshot: gp.Snapshot = .{};
    try std.testing.expect(poll(null, &snapshot));
    try std.testing.expect(!findPad(&snapshot, raw_id).?.mapped);
    try std.testing.expect(findPad(&snapshot, mapped_id).?.mapped);
    try std.testing.expect(axis(raw, 0, -20000));
    try std.testing.expect(button(raw, 7, true));
    try std.testing.expect(hat(raw, 0, 3));
    try std.testing.expect(axis(mapped, 1, 22000));
    try std.testing.expect(axis(mapped, 4, -32768));
    try std.testing.expect(axis(mapped, 5, 32767));
    try std.testing.expect(button(mapped, 0, true));
    try std.testing.expect(button(mapped, 14, true));
    try std.testing.expect(poll(null, &snapshot));
    const r = findPad(&snapshot, raw_id).?;
    try std.testing.expectEqual(@as(i16, -20000), r.axes[0]);
    try std.testing.expectEqual(@as(u32, 128), r.buttons);
    try std.testing.expectEqual(@as(u8, 3), r.hats[0]);
    const m = findPad(&snapshot, mapped_id).?;
    try std.testing.expectEqual(@as(i16, 22000), m.axes[1]);
    try std.testing.expectEqual(@as(i16, 0), m.axes[4]);
    try std.testing.expectEqual(@as(i16, 32767), m.axes[5]);
    try std.testing.expectEqual(@as(u32, 1 | (1 << 14)), m.buttons);
    try std.testing.expectEqual(@as(u8, 2), m.hats[0]);
    var text: [512]u8 = undefined;
    const config = try std.fmt.bufPrint(&text, "{s},Sigma custom,a:b7,leftx:a0,dpup:h0.1,dpright:h0.2,", .{r.guid});
    try std.testing.expect(mapping(null, config));
    try std.testing.expect(poll(null, &snapshot));
    try std.testing.expect(findPad(&snapshot, raw_id).?.mapped);
    try std.testing.expect(findPad(&snapshot, raw_id).?.buttons & 1 != 0);
    try std.testing.expect(detach(raw_id));
    try std.testing.expect(detach(mapped_id));
    try std.testing.expect(poll(null, &snapshot));
    try std.testing.expect(findPad(&snapshot, raw_id) == null);
    try std.testing.expect(findPad(&snapshot, mapped_id) == null);
    for (snapshot.pads[snapshot.count..]) |pad| try std.testing.expectEqual(@as(u32, 0), pad.buttons);
    const replacement = attach(&.{ .axes = 4, .buttons = 8, .hats = 1, .name = "Sigma raw test" });
    try std.testing.expect(replacement != 0 and replacement != raw_id);
    defer _ = detach(replacement);
    try std.testing.expect(poll(null, &snapshot));
    try std.testing.expect(findPad(&snapshot, replacement) != null);
    try std.testing.expectEqual(@as(u32, 0), findPad(&snapshot, replacement).?.buttons);
}
