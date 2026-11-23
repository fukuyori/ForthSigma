//! The displays on macOS (tque 1259), read in the Forth process. CoreGraphics supplies
//! global desktop bounds and the active mode refresh rate; NSScreen supplies visible
//! frames and backing scale. Physical-pixel rectangles are placed outward from the
//! primary display, snapping adjacent edges and scaling offsets in the parent display.

const std = @import("std");
const display_info = @import("core/display_info.zig");
const host_display = @import("host_display.zig");

const Id = ?*anyopaque;
const Sel = ?*anyopaque;
const Point = extern struct { x: f64, y: f64 };
const Size = extern struct { width: f64, height: f64 };
const Rect = extern struct { origin: Point, size: Size };

const ObjcGetClass = *const fn ([*:0]const u8) callconv(.c) Id;
const SelRegisterName = *const fn ([*:0]const u8) callconv(.c) Sel;
const SendId0 = *const fn (Id, Sel) callconv(.c) Id;
const SendId1 = *const fn (Id, Sel, Id) callconv(.c) Id;
const SendIdUsize = *const fn (Id, Sel, usize) callconv(.c) Id;
const SendUsize0 = *const fn (Id, Sel) callconv(.c) usize;
const SendU32_0 = *const fn (Id, Sel) callconv(.c) u32;
const SendDouble0 = *const fn (Id, Sel) callconv(.c) f64;
const SendRect0 = *const fn (Id, Sel) callconv(.c) Rect;
const SendRectStret = *const fn (*Rect, Id, Sel) callconv(.c) void;
const DisplayMode = *const fn (u32) callconv(.c) Id;
const GetActiveDisplayList = *const fn (u32, ?[*]u32, *u32) callconv(.c) i32;
const DisplayBounds = *const fn (u32) callconv(.c) Rect;
const MainDisplayId = *const fn () callconv(.c) u32;
const ModeRefresh = *const fn (Id) callconv(.c) f64;
const Release = *const fn (Id) callconv(.c) void;
const SendVoid0 = *const fn (Id, Sel) callconv(.c) void;

const RawDisplay = struct {
    id: u32,
    bounds: Rect,
    frame: Rect,
    visible: Rect,
    scale: f64,
    hz: [2]u32,
    primary: bool,
    rect: [4]i32 = .{ 0, 0, 0, 0 },
    placed: bool = false,
};

const max_screens = display_info.max_displays;
const framework = "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics";
const objc_runtime = "/usr/lib/libobjc.A.dylib";
const appkit = "/System/Library/Frameworks/AppKit.framework/AppKit";
extern "c" fn pthread_main_np() c_int;

/// Fills the snapshot with the current NSScreen values. If AppKit is unavailable (for
/// example in a headless launch), leaves it empty so DISPLAYS reports 0.
pub fn snapshot(out: *display_info.Snapshot) void {
    var objc = std.DynLib.open(objc_runtime) catch return;
    defer objc.close();
    var cocoa = std.DynLib.open(appkit) catch return;
    defer cocoa.close();
    var graphics = std.DynLib.open(framework) catch return;
    defer graphics.close();
    const active_displays = graphics.lookup(GetActiveDisplayList, "CGGetActiveDisplayList") orelse return;
    var active_count: u32 = 0;
    if (active_displays(0, null, &active_count) != 0 or active_count == 0) return;
    var active_ids: [max_screens]u32 = undefined;
    const active_capacity: u32 = @intCast(@min(active_count, active_ids.len));
    if (active_displays(active_capacity, &active_ids, &active_count) != 0) return;
    const visible_count: usize = @min(active_count, active_capacity);

    // NSScreen is AppKit state. The current Forth VM calls host words on the main
    // thread; if that changes, display queries must be routed to the AppKit child.
    if (pthread_main_np() == 0) return;

    const get_class = objc.lookup(ObjcGetClass, "objc_getClass") orelse return;
    const register = objc.lookup(SelRegisterName, "sel_registerName") orelse return;
    const send_id = objc.lookup(SendId0, "objc_msgSend") orelse return;
    const send_id1 = objc.lookup(SendId1, "objc_msgSend") orelse return;
    const send_void = objc.lookup(SendVoid0, "objc_msgSend") orelse return;
    const send_count = objc.lookup(SendUsize0, "objc_msgSend") orelse return;
    const send_at = objc.lookup(SendIdUsize, "objc_msgSend") orelse return;
    const send_number = objc.lookup(SendU32_0, "objc_msgSend") orelse return;
    const send_scale = objc.lookup(SendDouble0, "objc_msgSend") orelse return;
    const send_rect: SendRect0 = objc.lookup(SendRect0, "objc_msgSend") orelse return;
    const send_rect_stret: ?SendRectStret = if (@import("builtin").cpu.arch == .x86_64)
        objc.lookup(SendRectStret, "objc_msgSend_stret")
    else
        null;

    const pool_class = get_class("NSAutoreleasePool") orelse return;
    const pool = send_id(pool_class, register("alloc")) orelse return;
    const pool_init = send_id(pool, register("init")) orelse return;
    defer send_void(pool_init, register("drain"));

    const screen_class = get_class("NSScreen") orelse return;
    const screens = send_id(screen_class, register("screens")) orelse return;
    const screen_count = send_count(screens, register("count"));
    const count = @min(screen_count, max_screens);
    if (count == 0) return;

    const string_class = get_class("NSString") orelse return;
    const MakeString = *const fn (Id, Sel, [*:0]const u8) callconv(.c) Id;
    const make_string = objc.lookup(MakeString, "objc_msgSend") orelse return;
    const key = make_string(string_class, register("stringWithUTF8String:"), "NSScreenNumber") orelse return;
    const main_id = (graphics.lookup(MainDisplayId, "CGMainDisplayID") orelse return)();
    if (main_id == 0) return;
    const display_bounds = graphics.lookup(DisplayBounds, "CGDisplayBounds") orelse return;
    const display_mode = graphics.lookup(DisplayMode, "CGDisplayCopyDisplayMode") orelse return;
    const mode_refresh = graphics.lookup(ModeRefresh, "CGDisplayModeGetRefreshRate") orelse return;
    const mode_release = graphics.lookup(Release, "CGDisplayModeRelease") orelse return;

    var found: [max_screens]RawDisplay = undefined;
    var found_count: usize = 0;
    for (0..count) |i| {
        const screen = send_at(screens, register("objectAtIndex:"), i) orelse continue;
        const id = screenId(send_id, send_id1, send_number, register, screen, key);
        const scale = send_scale(screen, register("backingScaleFactor"));
        if (id == 0 or !hasId(active_ids[0..visible_count], id) or !(scale > 0) or !std.math.isFinite(scale)) continue;
        const frame = rect(send_rect, send_rect_stret, register, screen, "frame") orelse continue;
        const visible = rect(send_rect, send_rect_stret, register, screen, "visibleFrame") orelse continue;

        const mode = display_mode(id) orelse continue;
        defer mode_release(mode);
        const refresh_hz = mode_refresh(mode);
        const hz = refreshFraction(refresh_hz);

        const bounds = display_bounds(id);
        if (physicalSize(bounds, scale) == null) continue;
        found[found_count] = .{
            .id = id,
            .bounds = bounds,
            .frame = frame,
            .visible = visible,
            .scale = scale,
            .hz = hz,
            .primary = id == main_id,
        };
        found_count += 1;
    }

    if (!placeDisplayRects(found[0..found_count])) return;
    for (found[0..found_count]) |screen| {
        const rect_x = screen.rect[0];
        const rect_y = screen.rect[1];
        const rect_w = screen.rect[2];
        const rect_h = screen.rect[3];
        const work_x = toI32(@as(f64, @floatFromInt(rect_x)) + (screen.visible.origin.x - screen.frame.origin.x) * screen.scale) orelse continue;
        const work_y = toI32(@as(f64, @floatFromInt(rect_y)) + (screen.frame.origin.y + screen.frame.size.height - screen.visible.origin.y - screen.visible.size.height) * screen.scale) orelse continue;
        const work_w = toI32(screen.visible.size.width * screen.scale) orelse continue;
        const work_h = toI32(screen.visible.size.height * screen.scale) orelse continue;
        out.add(.{
            .id = screen.id,
            .rect = .{ rect_x, rect_y, rect_w, rect_h },
            .work = .{ work_x, work_y, work_w, work_h },
            .scale = fraction(screen.scale),
            .hz = screen.hz,
            .primary = screen.primary,
        });
    }
}

fn physicalSize(bounds: Rect, scale: f64) ?[2]i32 {
    if (!(scale > 0) or !std.math.isFinite(scale)) return null;
    const width = toI32(bounds.size.width * scale) orelse return null;
    const height = toI32(bounds.size.height * scale) orelse return null;
    if (width <= 0 or height <= 0) return null;
    return .{ width, height };
}

/// Maps the macOS point-space layout into the shared physical-pixel space. Starting at
/// the primary, each next display is attached to its closest placed neighbour. Shared
/// edges snap exactly; gaps and offsets along the neighbour use the chosen scale policy.
fn placeDisplayRects(displays: []RawDisplay) bool {
    if (displays.len == 0) return true;
    var primary_index: ?usize = null;
    for (displays, 0..) |screen, i| {
        if (screen.primary) {
            primary_index = i;
            break;
        }
    }
    const root_index = primary_index orelse return false;
    const root = &displays[root_index];
    const root_size = physicalSize(root.bounds, root.scale) orelse return false;
    root.rect = .{ 0, 0, root_size[0], root_size[1] };
    root.placed = true;

    var placed_count: usize = 1;
    while (placed_count < displays.len) : (placed_count += 1) {
        var best_distance = std.math.inf(f64);
        var best_edge: f64 = -1;
        var best_scale: f64 = -1;
        var best_id: u32 = std.math.maxInt(u32);
        var best_source: ?usize = null;
        var best_target: ?usize = null;
        for (displays, 0..) |target, target_index| {
            if (target.placed) continue;
            for (displays, 0..) |source, source_index| {
                if (!source.placed) continue;
                const distance = separation(source.bounds, target.bounds);
                const edge = sharedEdge(source.bounds, target.bounds);
                if (distance < best_distance or
                    (distance == best_distance and edge > best_edge) or
                    (distance == best_distance and edge == best_edge and target.scale > best_scale) or
                    (distance == best_distance and edge == best_edge and target.scale == best_scale and target.id < best_id))
                {
                    best_distance = distance;
                    best_edge = edge;
                    best_scale = target.scale;
                    best_id = target.id;
                    best_source = source_index;
                    best_target = target_index;
                }
            }
        }
        const source_index = best_source orelse return false;
        const target_index = best_target orelse return false;
        const source = displays[source_index];
        const target = &displays[target_index];
        const size = physicalSize(target.bounds, target.scale) orelse return false;
        const source_right = source.bounds.origin.x + source.bounds.size.width;
        const target_right = target.bounds.origin.x + target.bounds.size.width;
        const source_bottom = source.bounds.origin.y + source.bounds.size.height;
        const target_bottom = target.bounds.origin.y + target.bounds.size.height;
        const gap_x = @max(@as(f64, 0), @max(target.bounds.origin.x - source_right, source.bounds.origin.x - target_right));
        const gap_y = @max(@as(f64, 0), @max(target.bounds.origin.y - source_bottom, source.bounds.origin.y - target_bottom));
        const overlap_x = overlapLength(source.bounds.origin.x, source_right, target.bounds.origin.x, target_right);
        const overlap_y = overlapLength(source.bounds.origin.y, source_bottom, target.bounds.origin.y, target_bottom);
        const horizontal = if (overlap_y > 0) true else if (overlap_x > 0) false else if (gap_x != gap_y)
            gap_x > gap_y
        else
            @abs(target.bounds.origin.x - source.bounds.origin.x) >= @abs(target.bounds.origin.y - source.bounds.origin.y);

        var x: f64 = @floatFromInt(source.rect[0]);
        var y: f64 = @floatFromInt(source.rect[1]);
        if (horizontal) {
            if (target.bounds.origin.x >= source_right) {
                x += @as(f64, @floatFromInt(source.rect[2])) + gap_x * source.scale;
            } else if (target_right <= source.bounds.origin.x) {
                x -= @as(f64, @floatFromInt(size[0])) + gap_x * target.scale;
            } else {
                x += (target.bounds.origin.x - source.bounds.origin.x) * source.scale;
            }
            y += (target.bounds.origin.y - source.bounds.origin.y) * source.scale;
        } else {
            x += (target.bounds.origin.x - source.bounds.origin.x) * source.scale;
            if (target.bounds.origin.y >= source_bottom) {
                y += @as(f64, @floatFromInt(source.rect[3])) + gap_y * source.scale;
            } else if (target_bottom <= source.bounds.origin.y) {
                y -= @as(f64, @floatFromInt(size[1])) + gap_y * target.scale;
            } else {
                y += (target.bounds.origin.y - source.bounds.origin.y) * source.scale;
            }
        }
        target.rect = .{
            toI32(x) orelse return false,
            toI32(y) orelse return false,
            size[0],
            size[1],
        };
        if (!avoidOverlaps(displays, target_index)) return false;
        target.placed = true;
    }
    return true;
}

fn overlapLength(a0: f64, a1: f64, b0: f64, b1: f64) f64 {
    return @max(@as(f64, 0), @min(a1, b1) - @max(a0, b0));
}

fn sharedEdge(a: Rect, b: Rect) f64 {
    const a_right = a.origin.x + a.size.width;
    const b_right = b.origin.x + b.size.width;
    const a_bottom = a.origin.y + a.size.height;
    const b_bottom = b.origin.y + b.size.height;
    const tolerance = 0.01;
    if (@abs(a_right - b.origin.x) <= tolerance or @abs(b_right - a.origin.x) <= tolerance) {
        return overlapLength(a.origin.y, a_bottom, b.origin.y, b_bottom);
    }
    if (@abs(a_bottom - b.origin.y) <= tolerance or @abs(b_bottom - a.origin.y) <= tolerance) {
        return overlapLength(a.origin.x, a_right, b.origin.x, b_right);
    }
    return 0;
}

fn avoidOverlaps(displays: []RawDisplay, target_index: usize) bool {
    const target = &displays[target_index];
    const target_right = @as(i64, target.rect[0]) + target.rect[2];
    const target_bottom = @as(i64, target.rect[1]) + target.rect[3];
    var push_right: i64 = 0;
    var push_left: i64 = 0;
    var push_down: i64 = 0;
    var push_up: i64 = 0;
    var has_overlap = false;
    for (displays, 0..) |other, other_index| {
        if (other_index == target_index or !other.placed) continue;
        const other_right = @as(i64, other.rect[0]) + other.rect[2];
        const other_bottom = @as(i64, other.rect[1]) + other.rect[3];
        const y_overlaps = target.rect[1] < other_bottom and other.rect[1] < target_bottom;
        const x_overlaps = target.rect[0] < other_right and other.rect[0] < target_right;
        if (x_overlaps and y_overlaps) has_overlap = true;
        if (y_overlaps) {
            push_right = @max(push_right, other_right - target.rect[0]);
            push_left = @min(push_left, @as(i64, other.rect[0]) - target_right);
        }
        if (x_overlaps) {
            push_down = @max(push_down, other_bottom - target.rect[1]);
            push_up = @min(push_up, @as(i64, other.rect[1]) - target_bottom);
        }
    }
    if (!has_overlap) return true;
    const shifts = [_]i64{ push_right, push_left, push_down, push_up };
    var selected: usize = 0;
    for (shifts[1..], 1..) |shift, index| if (@abs(shift) < @abs(shifts[selected])) {
        selected = index;
    };
    if (shifts[selected] == 0) return true;
    const coordinate = switch (selected) {
        0, 1 => @as(i64, target.rect[0]) + shifts[selected],
        2, 3 => @as(i64, target.rect[1]) + shifts[selected],
        else => unreachable,
    };
    const converted = toI32(@floatFromInt(coordinate)) orelse return false;
    target.rect[if (selected < 2) 0 else 1] = converted;
    return true;
}

fn separation(a: Rect, b: Rect) f64 {
    const a_right = a.origin.x + a.size.width;
    const b_right = b.origin.x + b.size.width;
    const a_bottom = a.origin.y + a.size.height;
    const b_bottom = b.origin.y + b.size.height;
    const dx = @max(@as(f64, 0), @max(b.origin.x - a_right, a.origin.x - b_right));
    const dy = @max(@as(f64, 0), @max(b.origin.y - a_bottom, a.origin.y - b_bottom));
    return dx + dy;
}

fn hasId(ids: []const u32, id: u32) bool {
    for (ids) |candidate| if (candidate == id) return true;
    return false;
}

fn screenId(
    send_id: SendId0,
    send_id1: SendId1,
    send_number: SendU32_0,
    register: SelRegisterName,
    screen: Id,
    key: Id,
) u32 {
    const description = send_id(screen, register("deviceDescription")) orelse return 0;
    const number = send_id1(description, register("objectForKey:"), key) orelse return 0;
    return send_number(number, register("unsignedIntValue"));
}

fn rect(
    send_rect: SendRect0,
    send_stret: ?SendRectStret,
    register: SelRegisterName,
    object: Id,
    selector_name: [*:0]const u8,
) ?Rect {
    const selector = register(selector_name);
    if (@import("builtin").cpu.arch == .x86_64) {
        var result: Rect = undefined;
        (send_stret orelse return null)(&result, object, selector);
        return result;
    }
    return send_rect(object, selector);
}

fn toI32(value: f64) ?i32 {
    if (!std.math.isFinite(value) or value < std.math.minInt(i32) or value > std.math.maxInt(i32)) return null;
    return @intFromFloat(@round(value));
}

fn fraction(value: f64) [2]u32 {
    if (!std.math.isFinite(value) or value <= 0 or value > 1000) return .{ 0, 0 };
    return host_display.reduced(@intFromFloat(@round(value * 1000)), 1000);
}

fn refreshFraction(value: f64) [2]u32 {
    if (!std.math.isFinite(value) or value <= 0 or value > 1_000_000) return .{ 0, 0 };
    // Common NTSC-derived rates are exact fractions (60000/1001), while the CoreGraphics
    // API reports them as doubles. Preserve those instead of rounding them to 59.94.
    const ntsc = value * 1001;
    const nearest_ntsc = @round(ntsc);
    if (@abs(ntsc - nearest_ntsc) < 0.0001 and nearest_ntsc <= std.math.maxInt(u32)) {
        return host_display.reduced(@intFromFloat(nearest_ntsc), 1001);
    }
    return host_display.reduced(@intFromFloat(@round(value * 1000)), 1000);
}

test "macOS refresh rates keep NTSC fractions and unknown modes" {
    try std.testing.expectEqual([2]u32{ 60, 1 }, refreshFraction(60));
    try std.testing.expectEqual([2]u32{ 60_000, 1001 }, refreshFraction(59.94005994));
    try std.testing.expectEqual([2]u32{ 0, 0 }, refreshFraction(0));
}

test "macOS display layout snaps adjacent mixed-scale bounds from primary" {
    const retina = Rect{ .origin = .{ .x = 0, .y = 0 }, .size = .{ .width = 1470, .height = 956 } };
    const regular_right = Rect{ .origin = .{ .x = 1470, .y = 0 }, .size = .{ .width = 1920, .height = 1080 } };
    var right = [_]RawDisplay{
        .{ .id = 1, .bounds = retina, .frame = retina, .visible = retina, .scale = 2, .hz = .{ 60, 1 }, .primary = true },
        .{ .id = 2, .bounds = regular_right, .frame = regular_right, .visible = regular_right, .scale = 1, .hz = .{ 60, 1 }, .primary = false },
    };
    try std.testing.expect(placeDisplayRects(&right));
    try std.testing.expectEqual([4]i32{ 0, 0, 2940, 1912 }, right[0].rect);
    try std.testing.expectEqual([4]i32{ 2940, 0, 1920, 1080 }, right[1].rect);

    const regular_primary = Rect{ .origin = .{ .x = 0, .y = 0 }, .size = .{ .width = 1920, .height = 1080 } };
    const retina_right = Rect{ .origin = .{ .x = 1920, .y = 0 }, .size = .{ .width = 1470, .height = 956 } };
    var mixed_right = [_]RawDisplay{
        .{ .id = 1, .bounds = regular_primary, .frame = regular_primary, .visible = regular_primary, .scale = 1, .hz = .{ 60, 1 }, .primary = true },
        .{ .id = 2, .bounds = retina_right, .frame = retina_right, .visible = retina_right, .scale = 2, .hz = .{ 60, 1 }, .primary = false },
    };
    try std.testing.expect(placeDisplayRects(&mixed_right));
    try std.testing.expectEqual([4]i32{ 1920, 0, 2940, 1912 }, mixed_right[1].rect);

    const regular_below = Rect{ .origin = .{ .x = 0, .y = 956 }, .size = .{ .width = 1470, .height = 1080 } };
    var below = [_]RawDisplay{
        .{ .id = 1, .bounds = retina, .frame = retina, .visible = retina, .scale = 2, .hz = .{ 60, 1 }, .primary = true },
        .{ .id = 2, .bounds = regular_below, .frame = regular_below, .visible = regular_below, .scale = 1, .hz = .{ 60, 1 }, .primary = false },
    };
    try std.testing.expect(placeDisplayRects(&below));
    try std.testing.expectEqual([4]i32{ 0, 0, 2940, 1912 }, below[0].rect);
    try std.testing.expectEqual([4]i32{ 0, 1912, 1470, 1080 }, below[1].rect);

    const regular_left = Rect{ .origin = .{ .x = -1920, .y = 0 }, .size = .{ .width = 1920, .height = 1280 } };
    var left = [_]RawDisplay{
        .{ .id = 1, .bounds = retina, .frame = retina, .visible = retina, .scale = 2, .hz = .{ 60, 1 }, .primary = true },
        .{ .id = 2, .bounds = regular_left, .frame = regular_left, .visible = regular_left, .scale = 1, .hz = .{ 60, 1 }, .primary = false },
    };
    try std.testing.expect(placeDisplayRects(&left));
    try std.testing.expectEqual([4]i32{ -1920, 0, 1920, 1280 }, left[1].rect);

    const offset_left = Rect{ .origin = .{ .x = -1920, .y = 300 }, .size = .{ .width = 1920, .height = 1280 } };
    var shifted = [_]RawDisplay{
        .{ .id = 1, .bounds = retina, .frame = retina, .visible = retina, .scale = 2, .hz = .{ 60, 1 }, .primary = true },
        .{ .id = 2, .bounds = offset_left, .frame = offset_left, .visible = offset_left, .scale = 1, .hz = .{ 60, 1 }, .primary = false },
    };
    try std.testing.expect(placeDisplayRects(&shifted));
    try std.testing.expectEqual([4]i32{ -1920, 600, 1920, 1280 }, shifted[1].rect);

    const regular_above = Rect{ .origin = .{ .x = 0, .y = -1080 }, .size = .{ .width = 1470, .height = 1080 } };
    var above = [_]RawDisplay{
        .{ .id = 1, .bounds = retina, .frame = retina, .visible = retina, .scale = 2, .hz = .{ 60, 1 }, .primary = true },
        .{ .id = 2, .bounds = regular_above, .frame = regular_above, .visible = regular_above, .scale = 1, .hz = .{ 60, 1 }, .primary = false },
    };
    try std.testing.expect(placeDisplayRects(&above));
    try std.testing.expectEqual([4]i32{ 0, -1080, 1470, 1080 }, above[1].rect);

    const regular_left_gap = Rect{ .origin = .{ .x = -2020, .y = 0 }, .size = .{ .width = 1920, .height = 1280 } };
    var gap = [_]RawDisplay{
        .{ .id = 1, .bounds = retina, .frame = retina, .visible = retina, .scale = 2, .hz = .{ 60, 1 }, .primary = true },
        .{ .id = 2, .bounds = regular_left_gap, .frame = regular_left_gap, .visible = regular_left_gap, .scale = 1, .hz = .{ 60, 1 }, .primary = false },
    };
    try std.testing.expect(placeDisplayRects(&gap));
    try std.testing.expectEqual([4]i32{ -2020, 0, 1920, 1280 }, gap[1].rect);

    const square_primary = Rect{ .origin = .{ .x = 0, .y = 0 }, .size = .{ .width = 1000, .height = 1000 } };
    const square_right = Rect{ .origin = .{ .x = 1000, .y = 0 }, .size = .{ .width = 1000, .height = 1000 } };
    const square_below_right = Rect{ .origin = .{ .x = 1000, .y = 1000 }, .size = .{ .width = 1000, .height = 500 } };
    var corner = [_]RawDisplay{
        .{ .id = 1, .bounds = square_primary, .frame = square_primary, .visible = square_primary, .scale = 2, .hz = .{ 60, 1 }, .primary = true },
        .{ .id = 2, .bounds = square_right, .frame = square_right, .visible = square_right, .scale = 1, .hz = .{ 60, 1 }, .primary = false },
        .{ .id = 3, .bounds = square_below_right, .frame = square_below_right, .visible = square_below_right, .scale = 1, .hz = .{ 60, 1 }, .primary = false },
    };
    try std.testing.expect(placeDisplayRects(&corner));
    try std.testing.expectEqual(@as(i32, 1000), corner[2].rect[1]);
    try std.testing.expect(!rectsOverlap(corner[0].rect, corner[1].rect));
    try std.testing.expect(!rectsOverlap(corner[0].rect, corner[2].rect));
    try std.testing.expect(!rectsOverlap(corner[1].rect, corner[2].rect));

    const upper = Rect{ .origin = .{ .x = 0, .y = 0 }, .size = .{ .width = 2000, .height = 1000 } };
    const lower_left_retina = Rect{ .origin = .{ .x = 0, .y = 1000 }, .size = .{ .width = 1000, .height = 1000 } };
    const lower_right = Rect{ .origin = .{ .x = 1000, .y = 1000 }, .size = .{ .width = 1000, .height = 1000 } };
    var junction = [_]RawDisplay{
        .{ .id = 1, .bounds = upper, .frame = upper, .visible = upper, .scale = 1, .hz = .{ 60, 1 }, .primary = true },
        .{ .id = 2, .bounds = lower_left_retina, .frame = lower_left_retina, .visible = lower_left_retina, .scale = 2, .hz = .{ 60, 1 }, .primary = false },
        .{ .id = 3, .bounds = lower_right, .frame = lower_right, .visible = lower_right, .scale = 1, .hz = .{ 60, 1 }, .primary = false },
    };
    try std.testing.expect(placeDisplayRects(&junction));
    try std.testing.expectEqual([4]i32{ 2000, 1000, 1000, 1000 }, junction[2].rect);
    try std.testing.expect(!rectsOverlap(junction[0].rect, junction[1].rect));
    try std.testing.expect(!rectsOverlap(junction[0].rect, junction[2].rect));
    try std.testing.expect(!rectsOverlap(junction[1].rect, junction[2].rect));

    var junction_reordered = [_]RawDisplay{
        .{ .id = 1, .bounds = upper, .frame = upper, .visible = upper, .scale = 1, .hz = .{ 60, 1 }, .primary = true },
        .{ .id = 3, .bounds = lower_right, .frame = lower_right, .visible = lower_right, .scale = 1, .hz = .{ 60, 1 }, .primary = false },
        .{ .id = 2, .bounds = lower_left_retina, .frame = lower_left_retina, .visible = lower_left_retina, .scale = 2, .hz = .{ 60, 1 }, .primary = false },
    };
    try std.testing.expect(placeDisplayRects(&junction_reordered));
    try std.testing.expectEqual([4]i32{ 2000, 1000, 1000, 1000 }, junction_reordered[1].rect);
    try std.testing.expect(!rectsOverlap(junction_reordered[0].rect, junction_reordered[1].rect));
    try std.testing.expect(!rectsOverlap(junction_reordered[0].rect, junction_reordered[2].rect));
    try std.testing.expect(!rectsOverlap(junction_reordered[1].rect, junction_reordered[2].rect));

    const wide_below = Rect{ .origin = .{ .x = 0, .y = 1080 }, .size = .{ .width = 2920, .height = 500 } };
    const retina_right_of_primary = Rect{ .origin = .{ .x = 1920, .y = 0 }, .size = .{ .width = 1000, .height = 1000 } };
    var three = [_]RawDisplay{
        .{ .id = 1, .bounds = regular_primary, .frame = regular_primary, .visible = regular_primary, .scale = 1, .hz = .{ 60, 1 }, .primary = true },
        .{ .id = 2, .bounds = retina_right_of_primary, .frame = retina_right_of_primary, .visible = retina_right_of_primary, .scale = 2, .hz = .{ 60, 1 }, .primary = false },
        .{ .id = 3, .bounds = wide_below, .frame = wide_below, .visible = wide_below, .scale = 1, .hz = .{ 60, 1 }, .primary = false },
    };
    try std.testing.expect(placeDisplayRects(&three));
    for (three, 0..) |a, i| for (three[i + 1 ..]) |b| {
        try std.testing.expect(!rectsOverlap(a.rect, b.rect));
    };

    const upper_row = Rect{ .origin = .{ .x = 0, .y = -1000 }, .size = .{ .width = 3000, .height = 1000 } };
    const lower_left = Rect{ .origin = .{ .x = 0, .y = 0 }, .size = .{ .width = 1000, .height = 1000 } };
    const lower_mid = Rect{ .origin = .{ .x = 1000, .y = 0 }, .size = .{ .width = 1000, .height = 1000 } };
    const lower_right_row = Rect{ .origin = .{ .x = 2000, .y = 0 }, .size = .{ .width = 1000, .height = 1000 } };
    var squeezed = [_]RawDisplay{
        .{ .id = 1, .bounds = upper_row, .frame = upper_row, .visible = upper_row, .scale = 1, .hz = .{ 60, 1 }, .primary = true },
        .{ .id = 2, .bounds = lower_left, .frame = lower_left, .visible = lower_left, .scale = 2, .hz = .{ 60, 1 }, .primary = false },
        .{ .id = 3, .bounds = lower_right_row, .frame = lower_right_row, .visible = lower_right_row, .scale = 1, .hz = .{ 60, 1 }, .primary = false },
        .{ .id = 4, .bounds = lower_mid, .frame = lower_mid, .visible = lower_mid, .scale = 1, .hz = .{ 60, 1 }, .primary = false },
    };
    try std.testing.expect(placeDisplayRects(&squeezed));
    for (squeezed, 0..) |a, i| for (squeezed[i + 1 ..]) |b| {
        try std.testing.expect(!rectsOverlap(a.rect, b.rect));
    };

    const ring_top = Rect{ .origin = .{ .x = -1000, .y = -1000 }, .size = .{ .width = 3000, .height = 1000 } };
    const ring_left = Rect{ .origin = .{ .x = -1000, .y = 0 }, .size = .{ .width = 1000, .height = 1000 } };
    const ring_right = Rect{ .origin = .{ .x = 1000, .y = 0 }, .size = .{ .width = 1000, .height = 1000 } };
    const ring_bottom = Rect{ .origin = .{ .x = -1000, .y = 1000 }, .size = .{ .width = 3000, .height = 1000 } };
    const ring_center = Rect{ .origin = .{ .x = 0, .y = 0 }, .size = .{ .width = 1000, .height = 1000 } };
    var ring = [_]RawDisplay{
        .{ .id = 1, .bounds = ring_top, .frame = ring_top, .visible = ring_top, .scale = 1, .hz = .{ 60, 1 }, .primary = true },
        .{ .id = 2, .bounds = ring_left, .frame = ring_left, .visible = ring_left, .scale = 1, .hz = .{ 60, 1 }, .primary = false },
        .{ .id = 3, .bounds = ring_right, .frame = ring_right, .visible = ring_right, .scale = 1, .hz = .{ 60, 1 }, .primary = false },
        .{ .id = 4, .bounds = ring_bottom, .frame = ring_bottom, .visible = ring_bottom, .scale = 1, .hz = .{ 60, 1 }, .primary = false },
        .{ .id = 99, .bounds = ring_center, .frame = ring_center, .visible = ring_center, .scale = 1, .hz = .{ 60, 1 }, .primary = false },
    };
    try std.testing.expect(placeDisplayRects(&ring));
    try std.testing.expectEqual([4]i32{ 1000, 1000, 1000, 1000 }, ring[4].rect);
    for (ring, 0..) |a, i| for (ring[i + 1 ..]) |b| {
        try std.testing.expect(!rectsOverlap(a.rect, b.rect));
    };
}

fn rectsOverlap(a: [4]i32, b: [4]i32) bool {
    return a[0] < b[0] + b[2] and b[0] < a[0] + a[2] and a[1] < b[1] + b[3] and b[1] < a[1] + a[3];
}
