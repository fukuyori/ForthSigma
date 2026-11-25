//! macOS AppKit child-process prototype. It imports no Apple SDK headers: AppKit,
//! Objective-C, and libdispatch are loaded at runtime. Parent protocol: READY 1,
//! FRAME <sequence> / FRAME-ACCEPTED <sequence>, then QUIT / CLOSED.

const paint_source = &@import("host_paint.zig").source;
const std = @import("std");
const window_layout = @import("window_layout.zig");
const host_display_macos = @import("host_display_macos.zig");
const forth = @import("forth.zig");

const physical_keys = @import("core/physical_keys.zig");
const physical_map = @import("physical_key_map.zig");
const physical_protocol = @import("physical_key_protocol.zig");
var physical_state: physical_keys.Host = .{};
var physical_receiver: physical_protocol.Receiver = .{};
pub fn physical(req: physical_keys.Request) physical_keys.Response {
    // Reset is a non-I/O boundary used during image commit.
    if (req != .reset) {
        readChildInput();
        if (physical_receiver.sync_pending) if (child_process) |child| {
            // This pipe is nonblocking. Never interleave control with FRAME pixels.
            if (std.c.write(child.to_child, "SCANSYNC\n", 9) == 9) physical_receiver.sync_pending = false;
        };
    }
    return physical_state.request(req);
}

const Id = ?*anyopaque;
const Sel = ?*anyopaque;
const Imp = *const anyopaque;
const ObjcGetClass = *const fn ([*:0]const u8) callconv(.c) Id;
const SelRegisterName = *const fn ([*:0]const u8) callconv(.c) Sel;
const AllocateClassPair = *const fn (Id, [*:0]const u8, usize) callconv(.c) Id;
const ClassAddMethod = *const fn (Id, Sel, Imp, [*:0]const u8) callconv(.c) i8;
const RegisterClassPair = *const fn (Id) callconv(.c) void;
const ObjcGetProtocol = *const fn ([*:0]const u8) callconv(.c) Id;
const ClassAddProtocol = *const fn (Id, Id) callconv(.c) i8;
const ClassConformsToProtocol = *const fn (Id, Id) callconv(.c) i8;
const SendId0 = *const fn (Id, Sel) callconv(.c) Id;
const SendRange0 = *const fn (Id, Sel) callconv(.c) Range;
const SendUsize0 = *const fn (Id, Sel) callconv(.c) usize;
const SendBool1 = *const fn (Id, Sel, i8) callconv(.c) i8;
const SendBool0 = *const fn (Id, Sel) callconv(.c) i8;
const SendIdIndex = *const fn (Id, Sel, usize) callconv(.c) Id;
const SendU16 = *const fn (Id, Sel) callconv(.c) u16;
const SendIdClass = *const fn (Id, Sel, Id) callconv(.c) i8;
const SendCString0 = *const fn (Id, Sel) callconv(.c) ?[*:0]const u8;
const SendDouble0 = *const fn (Id, Sel) callconv(.c) f64;
const SendPoint0 = *const fn (Id, Sel) callconv(.c) Point;
const SendPoint0Stret = *const fn (*Point, Id, Sel) callconv(.c) void;
const SendPointFromView = *const fn (Id, Sel, Point, Id) callconv(.c) Point;
const SendPointTransform = *const fn (Id, Sel, Point) callconv(.c) Point;
const SendPointTransformStret = *const fn (*Point, Id, Sel, Point) callconv(.c) void;
const SendPointFromViewStret = *const fn (*Point, Id, Sel, Point, Id) callconv(.c) void;
const SendInitWindow = *const fn (Id, Sel, Rect, usize, usize, i8) callconv(.c) Id;
const SendInitView = *const fn (Id, Sel, Rect) callconv(.c) Id;
const SendSize1 = *const fn (Id, Sel, Size) callconv(.c) void;
const SendSetFrame = *const fn (Id, Sel, Rect, i8, i8) callconv(.c) void;
const SendSizeReturn = *const fn (Id, Sel, Size) callconv(.c) Size;
const SendSizeStret = *const fn (*Size, Id, Sel, Size) callconv(.c) void;
const SendRect0 = *const fn (Id, Sel) callconv(.c) Rect;
const SendRectStret = *const fn (*Rect, Id, Sel) callconv(.c) void;
const SendRect1 = *const fn (Id, Sel, Rect) callconv(.c) Rect;
const SendRect1Stret = *const fn (*Rect, Id, Sel, Rect) callconv(.c) void;
const SendRectToView = *const fn (Id, Sel, Rect, Id) callconv(.c) Rect;
const SendRectToViewStret = *const fn (*Rect, Id, Sel, Rect, Id) callconv(.c) void;
const SendId1 = *const fn (Id, Sel, Id) callconv(.c) Id;
const SendString = *const fn (Id, Sel, [*:0]const u8) callconv(.c) Id;
const SendColor = *const fn (Id, Sel, f64, f64, f64, f64) callconv(.c) Id;
const SendOtherEvent = *const fn (Id, Sel, usize, Point, usize, f64, isize, Id, i16, isize, isize) callconv(.c) Id;
const SendVoid0 = *const fn (Id, Sel) callconv(.c) void;
const SendVoid1 = *const fn (Id, Sel, Id) callconv(.c) void;
const SendSetMarkedText = *const fn (Id, Sel, Id, Range, Range) callconv(.c) void;
const SendFirstRect = *const fn (Id, Sel, Range, ?*Range) callconv(.c) Rect;
const SendAttributedSubstring = *const fn (Id, Sel, Range, ?*Range) callconv(.c) Id;
const SendPointIndex = *const fn (Id, Sel, Point) callconv(.c) usize;
const SendDoCommand = *const fn (Id, Sel, Sel) callconv(.c) void;
const SendSizeToId = *const fn (Id, Sel, Size) callconv(.c) Id;
const SendImageHotSpot = *const fn (Id, Sel, Id, Point) callconv(.c) Id;
const SendRectCursor = *const fn (Id, Sel, Rect, Id) callconv(.c) void;
var send_size_to_id: ?SendSizeToId = null;
var send_image_hot_spot: ?SendImageHotSpot = null;
var send_rect_cursor: ?SendRectCursor = null;
const PostEvent = *const fn (Id, Sel, Id, i8) callconv(.c) void;
const RectFill = *const fn (Rect) callconv(.c) void;
const DispatchQueue = ?*anyopaque;
const DispatchWork = *const fn (?*anyopaque) callconv(.c) void;
const DispatchAsyncF = *const fn (DispatchQueue, ?*anyopaque, DispatchWork) callconv(.c) void;

const Point = extern struct { x: f64, y: f64 };
const Size = extern struct { width: f64, height: f64 };
const Rect = extern struct { origin: Point, size: Size };
const Range = extern struct { location: usize, length: usize };

const objc_path = "/usr/lib/libobjc.A.dylib";
const appkit_path = "/System/Library/Frameworks/AppKit.framework/AppKit";
const dispatch_path = "/usr/lib/system/libdispatch.dylib";
pub const child_argument = "--sigma-internal-window-child-v1";

const Command = union(enum) { frame: Frame, caret: ImeCaret, fullscreen: bool, cursor: bool, fit: window_layout.Fit, smooth: bool, place: u64, display_query: u64, quit };
const Frame = struct { sequence: u64, width: u32, height: u32, requested: [2]u32, pixels: []u32 };
const ImeCaret = struct { active: bool = false, x: i32 = 0, y: i32 = 0, height: u32 = 0 };

var did_draw = false;
var did_close = false;
var active_app: Id = null;
var stdout_lock = std.atomic.Value(u8).init(0);
var active_view: Id = null;
var active_window: Id = null;
var selector_register: SelRegisterName = undefined;
var send_void1: SendVoid1 = undefined;
var send_id1: SendId1 = undefined;
var send_bool1: SendBool1 = undefined;
var send_bool0: SendBool0 = undefined;
var send_id_index: ?SendIdIndex = null;
var send_range0: SendRange0 = undefined;
var send_usize0: SendUsize0 = undefined;
var send_keycode: SendU16 = undefined;
var send_utf8: SendCString0 = undefined;
var send_is_kind: SendIdClass = undefined;
var current_hardware_key: usize = std.math.maxInt(usize);
var send_double0: SendDouble0 = undefined;
var send_point0: ?SendPoint0 = null;
var send_point0_stret: ?SendPoint0Stret = null;
var send_point_from_view: ?SendPointFromView = null;
var send_point_transform: ?SendPointTransform = null;
var send_point_from_view_stret: ?SendPointFromViewStret = null;
var send_point_transform_stret: ?SendPointTransformStret = null;
var send_other_event: SendOtherEvent = undefined;
var post_event: PostEvent = undefined;
var dispatch_async: DispatchAsyncF = undefined;
const DispatchAfterF = *const fn (u64, DispatchQueue, ?*anyopaque, *const fn (?*anyopaque) callconv(.c) void) callconv(.c) void;
const DispatchTime = *const fn (u64, i64) callconv(.c) u64;
var dispatch_after: ?DispatchAfterF = null;
var dispatch_time: ?DispatchTime = null;
var main_queue: DispatchQueue = null;
var rect_fill: RectFill = undefined;
var executable_path: [:0]const u8 = undefined;
var environment: [:null]const ?[*:0]const u8 = &.{null};
var parent_ready = false;
var child_process: ?ChildProcess = null;
var display_request_sequence: u64 = 0;
var display_response_sequence: u64 = 0;
var display_response_id: u64 = 0;
var window_was_ready = false;
var frame_sequence: u64 = 0;
/// The child said CLOSED or EXIT 0 where the answer to a frame was expected.
var child_said_closed = false;
/// The keys the window holds, as the child told, for their release when it ends.
var held_keys: [16]u32 = @splat(0);
/// The mouse buttons of the last mouse event put in the queue.
var queued_buttons: u8 = 0;
var input_queue: [128]forth.InputEvent = undefined;
var input_head: usize = 0;
var input_count: usize = 0;
var input_line: [640]u8 = undefined;
/// WINDOW-PIXELS and WINDOW-CHANGES of the AppKit window (tque 1266), as the child last
/// told them in its INPUT WINDOW lines; read and changed only by the parent's thread.
var window_size: WindowSize = .{};
/// WINDOW-FIT as last asked (tque 1286), sent to each child that starts, and the size of
/// the image the last SHOW gave, so that WINDOW-IMAGE-RECT is reckoned from them and the
/// window's size as they are when asked, as on Linux. Parent's thread only.
var parent_fit: window_layout.Fit = .aspect;
var parent_smooth = false;
/// WINDOW-ON as last asked (tque 1039): the display's displayKey, 0 for none; sent to
/// each child that starts, before fullscreen, so that a fullscreen window covers it.
var parent_place: u64 = 0;
/// WINDOW-KEEP-OPEN as last asked (tque 1328), sent to each child that starts, and whether
/// the child kept the window open at a request the program has not read since.
var parent_keep_open = false;
var close_pending = false;
/// WINDOW-FRAMES (tque 1302): the images children accepted in this run, the FRAME
/// sequence of the last of them, and how many of them had been given when the window
/// last drew. One child's accepted sequences follow each other (a send that fails ends
/// the child), so a PAINTED sequence s is image shown - (last - s). Parent's thread only.
var frames_shown: u64 = 0;
var frames_painted: u64 = 0;
var last_accepted_sequence: u64 = 0;
var shown_image: [2]u32 = .{ 0, 0 };
var input_line_used: usize = 0;
var preedit_buffer: [256]u8 = undefined;
var preedit_length: usize = 0;
var ime_caret = ImeCaret{};
/// Parent: FULLSCREEN as wanted (the child tells when the window entered or left it)
/// and MOUSE-CURSOR. Child: whether NSCursor hide is in effect.
var fullscreen_wanted = false;
var cursor_visible = true;
/// Child: the fullscreen state the parent asked for last (or the user chose), whether
/// a transition of the window is under way, and MOUSE-CURSOR with the blank cursor
/// the view's cursor rectangle gives while the cursor is hidden.
var fullscreen_desired = false;
var fullscreen_transitioning = false;
/// Child: the transition under way was started by Sigma (toggleFullScreen:), not by
/// the user (the green button, the system's shortcut).
var transition_by_sigma = false;
/// Child: Sigma asked for fullscreen or not while the user's transition was under
/// way; that request, not the user's, is what is wanted when it ends.
var asked_during_transition = false;
/// Child: WINDOW-ON (tque 1039): the display, by host_display_macos.displayKey, the window
/// is to move to; 0 when no move is waiting. reconcileFullscreen carries it out: a
/// fullscreen window leaves fullscreen first, then moves, then covers the new display.
var pending_place: u64 = 0;
/// Child: the window left fullscreen for a WINDOW-ON move, which waits a moment.
var place_after_exit = false;

/// The moment after leaving fullscreen for a WINDOW-ON move has passed: move, then go on
/// toward what is wanted (fullscreen again, on the new display).
fn placeLater(_: ?*anyopaque) callconv(.c) void {
    fullscreen_transitioning = false;
    reconcileFullscreen();
}
var child_cursor_visible = true;
var blank_cursor: Id = null;
var pressed_keys: [256]u32 = @splat(0);
var mouse_buttons: u8 = 0;
/// The mouse buttons of the last mouse line the child sent or kept.
var sent_buttons: u8 = 0;
var wheel_remainder: f64 = 0;
var last_mouse_x: i32 = -1;
var last_mouse_y: i32 = -1;
var last_mouse_event_ns: u64 = 0;
var frame_pixels: []u32 = &.{};
var frame_width: u32 = 0;
var frame_height: u32 = 0;
var last_frame_size: [2]u32 = .{ 0, 0 };
var last_requested_size: [2]u32 = .{ 0, 0 };
/// WINDOW-FIT in the child (tque 1286): how the image is laid out in the content view,
/// by window_layout.placeFit as on Windows and Linux. Read and set on the AppKit thread.
var child_fit: window_layout.Fit = .aspect;
/// WINDOW-SMOOTH in the child (tque 1320): each shown pixel is the average of the part
/// of the image it covers (window_layout.smoothRows, as on Windows and Linux), unless
/// the factors are whole numbers or there is no memory for it. AppKit thread only.
var child_smooth = false;
/// The FRAME sequence of the image the child holds, and the last one it told the parent
/// it had drawn (tque 1302): INPUT PAINTED goes once for each image. AppKit thread only.
var child_frame_sequence: u64 = 0;
var child_painted_sequence: u64 = 0;
/// WINDOW-KEEP-OPEN in the child (tque 1328), and whether the user asked to close while it
/// was true and the program has not read WINDOW-CLOSES since: then asking again closes.
/// The parent's reader thread sets them; windowShouldClose reads them on the AppKit thread.
var child_keep_open = std.atomic.Value(bool).init(false);
var child_close_unseen = std.atomic.Value(bool).init(false);
var smoother: window_layout.Smooth = .{};
var send_size1: SendSize1 = undefined;
var send_size_return: ?SendSizeReturn = null;
var send_size_stret: ?SendSizeStret = null;
var send_rect0: ?SendRect0 = null;
var send_rect_stret: ?SendRectStret = null;
var send_rect1: ?SendRect1 = null;
var send_rect1_stret: ?SendRect1Stret = null;
var send_rect_to_view: ?SendRectToView = null;
var send_rect_to_view_stret: ?SendRectToViewStret = null;
var send_set_frame: ?SendSetFrame = null;
var marked_text: Id = null;
var marked_selection = Range{ .location = 0, .length = 0 };

pub fn imePreedit(_: ?*anyopaque, destination: []u8) forth.RuntimeError!usize {
    const length = @min(preedit_length, destination.len);
    @memcpy(destination[0..length], preedit_buffer[0..length]);
    return length;
}

/// The host's window_fullscreen_fn: request 1 or 0 asks, -1 only tells. The child
/// says (INPUT FULLSCREEN) only when the wish changed without Sigma asking: the user's
/// Control+Command+F or the green button, or a transition that failed. The window
/// carrying out what Sigma asked is not told, so later requests are not undone.
pub fn fullscreen(_: ?*anyopaque, request: i8) forth.RuntimeError!bool {
    // What the child said meanwhile (the user may have left fullscreen) comes first.
    readChildInput();
    if (request >= 0 and fullscreen_wanted != (request == 1)) {
        fullscreen_wanted = request == 1;
        if (child_process) |child| {
            try writeAllUntil(child.to_child, if (fullscreen_wanted) "FULLSCREEN 1\n" else "FULLSCREEN 0\n", monotonicNs() + std.time.ns_per_s);
        }
    }
    return fullscreen_wanted;
}

/// The host's window_cursor_fn.
pub fn mouseCursor(_: ?*anyopaque, visible: bool) forth.RuntimeError!void {
    if (cursor_visible == visible) return;
    cursor_visible = visible;
    if (child_process) |child| {
        try writeAllUntil(child.to_child, if (visible) "CURSOR 1\n" else "CURSOR 0\n", monotonicNs() + std.time.ns_per_s);
    }
}

pub fn imeCaret(_: ?*anyopaque, active: bool, x: i64, y: i64, height: i64) forth.RuntimeError!void {
    const next = ImeCaret{
        .active = active,
        .x = @intCast(std.math.clamp(x, -1048576, 1048576)),
        .y = @intCast(std.math.clamp(y, -1048576, 1048576)),
        .height = @intCast(std.math.clamp(height, 0, 1048576)),
    };
    if (std.meta.eql(ime_caret, next)) return;
    ime_caret = next;
    const child = child_process orelse return;
    var buffer: [96]u8 = undefined;
    const line = std.fmt.bufPrint(&buffer, "CARET {d} {d} {d} {d}\n", .{ @intFromBool(ime_caret.active), ime_caret.x, ime_caret.y, ime_caret.height }) catch return error.HostFailed;
    try writeAllUntil(child.to_child, line, monotonicNs() + std.time.ns_per_s);
}

/// The AppKit window's display, by the CGDirectDisplayID in NSScreen.deviceDescription.
/// A request/reply goes to the child so AppKit is only touched on its own thread.
pub fn windowDisplay(_: ?*anyopaque, id: u64) ?u64 {
    if (id != 0) return null; // Tk's Aqua window id is not a CGWindowID.
    readChildInput();
    const child = child_process orelse return null;
    display_request_sequence +%= 1;
    if (display_request_sequence == 0) display_request_sequence = 1;
    const sequence = display_request_sequence;
    display_response_sequence = 0;
    var buffer: [64]u8 = undefined;
    const line = std.fmt.bufPrint(&buffer, "DISPLAY? {d}\n", .{sequence}) catch return null;
    writeAllUntil(child.to_child, line, monotonicNs() + std.time.ns_per_s) catch return null;
    const deadline = monotonicNs() + std.time.ns_per_s;
    while (display_response_sequence != sequence and monotonicNs() < deadline) {
        readChildInput();
        if (display_response_sequence == sequence) break;
        var delay: std.c.timespec = .{ .sec = 0, .nsec = 1_000_000 };
        _ = std.c.nanosleep(&delay, null);
    }
    if (display_response_sequence != sequence or display_response_id == 0) return null;
    return display_response_id;
}

/// The host's window_state_fn on macOS: the size of the window's content area in backing
/// pixels (0 0 without the window) and the count of its changes (tque 1266), the
/// rectangle of the image (1286), whether it is open, has the keyboard, is minimized,
/// and how many times the user closed it (1297), and the images shown and drawn (1302).
pub fn windowState() @import("core/display_info.zig").WindowState {
    readChildInput();
    var state: @import("core/display_info.zig").WindowState = .{
        .width = window_size.size[0],
        .height = window_size.size[1],
        .changes = window_size.changes,
        .open = window_size.open,
        .focused = window_size.open and window_size.focused,
        .minimized = window_size.open and window_size.minimized,
        .closes = window_size.closes,
        .frames_shown = frames_shown,
        .frames_painted = frames_painted,
    };
    if (window_size.open and shown_image[0] != 0 and state.width != 0 and state.height != 0) {
        const p = window_layout.placeFit(parent_fit, shown_image[0], shown_image[1], state.width, state.height);
        state.view = .{ p.x, p.y, p.w, p.h };
    }
    return state;
}

/// The host's window_close_fn on macOS (tque 1328): 0 and 1 WINDOW-KEEP-OPEN false and
/// true, 2 WINDOW-CLOSE (the program closes the window, not counted; the next SHOW opens
/// it again), 3 WINDOW-CLOSES: the count, a request kept open being taken as read.
pub fn windowClose(what: u8) u64 {
    readChildInput();
    switch (what) {
        0, 1 => {
            parent_keep_open = what == 1;
            if (!parent_keep_open) close_pending = false;
            if (child_process) |child| writeAllUntil(child.to_child, if (parent_keep_open) "KEEP-OPEN 1\n" else "KEEP-OPEN 0\n", monotonicNs() + std.time.ns_per_s) catch failChild();
        },
        2 => {
            close_pending = false;
            close();
        },
        3 => if (close_pending) {
            close_pending = false;
            if (child_process) |child| writeAllUntil(child.to_child, "CLOSES-SEEN\n", monotonicNs() + std.time.ns_per_s) catch failChild();
        },
        else => {},
    }
    return window_size.closes;
}

/// The host's window_place_fn on macOS (tque 1039): kept, and sent to the child when
/// there is one, which moves the window there; a child that starts later is told at its
/// start. 0 (no display) moves nothing.
pub fn windowPlace(id: u64) void {
    parent_place = id;
    readChildInput();
    if (id == 0) return;
    const child = child_process orelse return;
    var buffer: [40]u8 = undefined;
    const line = std.fmt.bufPrint(&buffer, "PLACE {d}\n", .{id}) catch return;
    writeAllUntil(child.to_child, line, monotonicNs() + std.time.ns_per_s) catch failChild();
}

/// The host's window_smooth_fn on macOS (tque 1320): kept, and sent to the child when
/// there is one; a child that starts later is told at its start.
pub fn windowSmooth(on: bool) void {
    parent_smooth = on;
    readChildInput();
    const child = child_process orelse return;
    writeAllUntil(child.to_child, if (on) "SMOOTH 1\n" else "SMOOTH 0\n", monotonicNs() + std.time.ns_per_s) catch failChild();
}

/// The host's window_fit_fn on macOS (tque 1286): kept, and sent to the child when there
/// is one; a child that starts later is told at its start.
pub fn windowFit(fit: u8) void {
    parent_fit = @fromBackingInt(@intCast(fit));
    readChildInput();
    const child = child_process orelse return;
    var buffer: [8]u8 = undefined;
    const line = std.fmt.bufPrint(&buffer, "FIT {d}\n", .{fit}) catch return;
    writeAllUntil(child.to_child, line, monotonicNs() + std.time.ns_per_s) catch failChild();
}

/// What the parent knows of the window's size. The count goes up when the window comes
/// (its first report), when it goes, when its size changes, and when the child says that
/// its scale, its screen, or the displays changed (also with the same size).
const WindowSize = struct {
    size: [2]u32 = .{ 0, 0 },
    changes: u64 = 0,
    open: bool = false,
    /// From INPUT STATE lines (tque 1297); false while the window is not open.
    focused: bool = false,
    minimized: bool = false,
    /// The times the user closed the window (INPUT CLOSE-ASKED), in this run; kept when
    /// the window goes, as on Windows and Linux.
    closes: u64 = 0,

    /// The rest of an INPUT STATE line: 1 or 0 for the keyboard, 1 or 0 for minimized.
    fn acceptState(self: *WindowSize, fields: anytype) void {
        const focused = fields.next() orelse return;
        const minimized = fields.next() orelse return;
        if (fields.next() != null) return;
        if (!(std.mem.eql(u8, focused, "0") or std.mem.eql(u8, focused, "1"))) return;
        if (!(std.mem.eql(u8, minimized, "0") or std.mem.eql(u8, minimized, "1"))) return;
        self.focused = focused[0] == '1';
        self.minimized = minimized[0] == '1';
    }

    /// The rest of an INPUT WINDOW line: width, height, and 1 when the change is to be
    /// counted whatever the size. A line that is not so is left out.
    fn accept(self: *WindowSize, fields: anytype) void {
        const width = std.fmt.parseInt(u32, fields.next() orelse return, 10) catch return;
        const height = std.fmt.parseInt(u32, fields.next() orelse return, 10) catch return;
        const changed = fields.next() orelse return;
        if (fields.next() != null or width > 1 << 20 or height > 1 << 20) return;
        if (!std.mem.eql(u8, changed, "0") and !std.mem.eql(u8, changed, "1")) return;
        self.report(width, height, changed[0] == '1');
    }

    fn report(self: *WindowSize, width: u32, height: u32, changed: bool) void {
        if (!self.open or changed or self.size[0] != width or self.size[1] != height) self.changes +%= 1;
        self.size = .{ width, height };
        self.open = true;
    }

    fn gone(self: *WindowSize) void {
        shown_image = .{ 0, 0 };
        if (self.open) self.changes +%= 1;
        self.size = .{ 0, 0 };
        self.open = false;
        self.focused = false;
        self.minimized = false;
    }
};

const ChildProcess = struct {
    pid: std.c.pid_t,
    to_child: std.c.fd_t,
    from_child: std.c.fd_t,
};

extern "c" fn waitpid(std.c.pid_t, ?*c_int, c_int) std.c.pid_t;
extern "c" fn kill(std.c.pid_t, c_int) c_int;

/// Called once by Sigma before it enters the Forth interpreter.
pub fn init(path: [:0]const u8, envp: [:null]const ?[*:0]const u8) void {
    executable_path = path;
    environment = envp;
    parent_ready = true;
}

/// Send a snapshot; the child owns a retained copy before acknowledging the frame.
/// When the user closed the window while the frame was on its way (the child says
/// CLOSED, or has ended with status zero), that is not a failure: the window is made
/// again and the frame sent once more, as for a window closed before SHOW.
pub fn show(_: ?*anyopaque, pixels: []const u32, width: u32, height: u32, mode: forth.ColorMode, size: [2]u32) forth.RuntimeError!void {
    if (width == 0 or height == 0 or width > 16384 or height > 16384 or @as(u64, width) * height != pixels.len) return error.HostFailed;
    var retried = false;
    while (true) {
        if (child_process) |child| {
            var status: c_int = 0;
            const result = waitpid(child.pid, &status, 1); // WNOHANG
            if (result == child.pid) {
                forgetChild(child);
                // AppKit exits with status zero when the user closes the window.
                if (status != 0) return error.HostFailed;
            } else if (result < 0 and std.c._errno().* == @backingInt(std.c.E.CHILD)) {
                forgetChild(child);
                return error.HostFailed;
            }
        }
        if (child_process == null) startChild() catch |err| {
            return if (window_was_ready) error.HostFailed else err;
        };
        child_said_closed = false;
        shown_image = .{ width, height };
        sendFrame(pixels, width, height, mode, size) catch |err| {
            if (err == error.HostFailed and !retried and childClosedNormally()) {
                retried = true;
                continue;
            }
            failChild();
            return err;
        };
        return;
    }
}

/// True when the child has ended with status zero, as it does when the user closes the
/// window; the child is then forgotten. A child that said CLOSED is given half a second
/// to end, any other a moment.
fn childClosedNormally() bool {
    const child = child_process orelse return false;
    const duration: u64 = if (child_said_closed) 500 * std.time.ns_per_ms else 50 * std.time.ns_per_ms;
    const deadline = monotonicNs() + duration;
    while (true) {
        var status: c_int = 0;
        const result = waitpid(child.pid, &status, 1); // WNOHANG
        if (result == child.pid) {
            if (status != 0) {
                // Ended, but not by a close: failChild must not signal a pid that is gone.
                forgetChild(child);
                return false;
            }
            forgetChild(child);
            return true;
        }
        if (result < 0 or monotonicNs() >= deadline) return false;
        var delay: std.c.timespec = .{ .sec = 0, .nsec = 1_000_000 };
        _ = std.c.nanosleep(&delay, null);
    }
}

/// Closes the pipes of a child that has ended and been reaped, and gives the program
/// what the child may not have been able to send: the keys and buttons released, the
/// mouse nowhere.
fn forgetChild(child: ChildProcess) void {
    _ = std.c.close(child.to_child);
    _ = std.c.close(child.from_child);
    child_process = null;
    publishPaint();
    physical_state.close();
    window_size.gone();
    input_line_used = 0;
    preedit_length = 0;
    for (held_keys) |code| {
        if (code != 0) queueInput(.{ .window_key_release = code });
    }
    queueInput(.{ .window_mouse = .{ .x = -1, .y = -1, .buttons = 0, .wheel = 0 } });
}

fn sendFrame(pixels: []const u32, width: u32, height: u32, mode: forth.ColorMode, size: [2]u32) forth.RuntimeError!void {
    frame_sequence +%= 1;
    var line_buffer: [128]u8 = undefined;
    const line = std.fmt.bufPrint(&line_buffer, "FRAME {d} {d} {d} {d} {d}\n", .{ frame_sequence, width, height, size[0], size[1] }) catch return error.HostFailed;
    const child = child_process orelse return error.HostFailed;
    const deadline = monotonicNs() + 5 * std.time.ns_per_s;
    try writeAllUntil(child.to_child, line, deadline);
    var ready_buffer: [64]u8 = undefined;
    const ready_line = std.fmt.bufPrint(&ready_buffer, "FRAME-READY {d}", .{frame_sequence}) catch return error.HostFailed;
    try readFrameStatus(child.from_child, ready_line, deadline);
    var bytes: [4096]u8 = undefined;
    var offset: usize = 0;
    while (offset < pixels.len) {
        const count = @min(pixels.len - offset, bytes.len / 4);
        for (pixels[offset..][0..count], 0..) |pixel, i| {
            const rgb = if (mode.colors == 0) pixel else forth.graphicsColor(mode, (offset + i) % width, (offset + i) / width, pixel);
            const argb = 0xff00_0000 | (rgb & 0x00ff_ffff); // Display is opaque; ignore source alpha.
            std.mem.writeInt(u32, bytes[i * 4 ..][0..4], argb, .little);
        }
        const byte_count = count * @as(usize, 4);
        try writeAllUntil(child.to_child, bytes[0..byte_count], deadline);
        offset += count;
    }
    var expected_buffer: [64]u8 = undefined;
    const expected = std.fmt.bufPrint(&expected_buffer, "FRAME-ACCEPTED {d}", .{frame_sequence}) catch return error.HostFailed;
    try readFrameStatus(child.from_child, expected, deadline);
    frames_shown +%= 1;
    @import("host_paint_trace.zig").record("request", frames_shown, 0);
    last_accepted_sequence = frame_sequence;
    publishPaint();
}

/// An INPUT PAINTED sequence: the window drew the image of that FRAME.
fn painted(sequence: u64) void {
    if (sequence == 0 or sequence > last_accepted_sequence) return;
    const behind = last_accepted_sequence - sequence;
    if (behind >= frames_shown) return;
    if (frames_shown - behind > frames_painted) @import("host_paint_trace.zig").record("complete", frames_shown - behind, 0);
    frames_painted = @max(frames_painted, frames_shown - behind);
    publishPaint();
}

/// WINDOW-PAINT-WAIT: waits until the window has drawn the image the last SHOW gave it,
/// `ms` milliseconds at most; false at once without the window, when it goes meanwhile,
/// and when the time runs out (a minimized window does not draw).
pub fn frameWait(ms: u32) bool {
    const deadline = monotonicNs() + @as(u64, ms) * std.time.ns_per_ms;
    while (true) {
        readChildInput();
        if (child_process == null or !window_size.open) return false;
        if (frames_painted >= frames_shown) return true;
        if (monotonicNs() >= deadline) return false;
        var delay: std.c.timespec = .{ .sec = 0, .nsec = 1_000_000 };
        _ = std.c.nanosleep(&delay, null);
    }
}

/// Progresses a bounded batch of child responses for the common wait bridge.
pub fn progressPaint() void {
    readChildInput();
}
var paint_input_ended = false;
pub fn paintInputFd() c_int {
    if (paint_input_ended) return -1;
    return if (child_process) |child| child.from_child else -1;
}
fn publishPaint() void {
    paint_source.publish(true, child_process != null and window_size.open, frames_shown, frames_painted);
}
/// Reads at most 4096 available bytes without waiting. Input events stay queued
/// for poll; INPUT FULLSCREEN updates fullscreen_wanted.
fn readChildInput() void {
    if (paint_input_ended) return;
    const child = child_process orelse return;
    for (0..4096) |_| {
        var descriptor = [_]std.c.pollfd{.{ .fd = child.from_child, .events = std.c.POLL.IN, .revents = 0 }};
        if (std.c.poll(&descriptor, descriptor.len, 0) <= 0) return;
        var byte: u8 = undefined;
        const count = std.c.read(child.from_child, @ptrCast(&byte), 1);
        if (count < 0) {
            const err = std.c._errno().*;
            if (err == @backingInt(std.c.E.INTR)) continue;
            if (err == @backingInt(std.c.E.AGAIN)) return;
        }
        if (count <= 0) {
            paint_input_ended = true;
            physical_state.close();
            window_size.gone();
            publishPaint();
            return;
        }
        if (byte == '\n') {
            enqueueInputLine(input_line[0..input_line_used]);
            input_line_used = 0;
        } else if (input_line_used < input_line.len) {
            input_line[input_line_used] = byte;
            input_line_used += 1;
        } else return;
    }
}

pub fn poll() ?forth.InputEvent {
    if (input_count != 0) {
        const event = input_queue[input_head];
        input_head = (input_head + 1) % input_queue.len;
        input_count -= 1;
        return event;
    }
    const child = child_process orelse return null;
    while (true) {
        var descriptor = [_]std.c.pollfd{.{ .fd = child.from_child, .events = std.c.POLL.IN, .revents = 0 }};
        const ready = std.c.poll(&descriptor, descriptor.len, 0);
        if (ready <= 0) return null;
        var byte: u8 = undefined;
        const count = std.c.read(child.from_child, @ptrCast(&byte), 1);
        if (count < 0) {
            const err = std.c._errno().*;
            if (err == @backingInt(std.c.E.INTR)) continue;
            if (err == @backingInt(std.c.E.AGAIN)) return null;
        }
        if (count <= 0) {
            paint_input_ended = true;
            physical_state.close();
            window_size.gone();
            publishPaint();
            return null;
        }
        if (byte == '\n') {
            enqueueInputLine(input_line[0..input_line_used]);
            input_line_used = 0;
            if (input_count != 0) {
                const event = input_queue[input_head];
                input_head = (input_head + 1) % input_queue.len;
                input_count -= 1;
                return event;
            }
        } else if (input_line_used < input_line.len) {
            input_line[input_line_used] = byte;
            input_line_used += 1;
        } else return null;
    }
}

fn enqueueInputLine(line: []const u8) void {
    defer {
        publishPaint();
        paint_source.input();
    }
    if (std.mem.eql(u8, line, "CLOSED") or std.mem.eql(u8, line, "EXIT 0")) {
        physical_state.close();
        window_size.gone();
    }
    if (std.mem.startsWith(u8, line, "DISPLAY ")) {
        var fields = std.mem.tokenizeScalar(u8, line[8..], ' ');
        const sequence = std.fmt.parseInt(u64, fields.next() orelse return, 10) catch return;
        const id = std.fmt.parseInt(u64, fields.next() orelse return, 10) catch return;
        if (fields.next() != null or sequence == 0) return;
        display_response_id = id;
        display_response_sequence = sequence;
        return;
    }
    if (physical_receiver.accept(&physical_state, line)) return;
    if (!std.mem.startsWith(u8, line, "INPUT ")) return;
    var fields = std.mem.tokenizeScalar(u8, line[6..], ' ');
    const kind = fields.next() orelse return;
    if (std.mem.eql(u8, kind, "PREEDIT")) {
        updatePreeditHex(fields.next() orelse return);
        return;
    }
    if (std.mem.eql(u8, kind, "FULLSCREEN")) {
        fullscreen_wanted = std.mem.eql(u8, fields.next() orelse return, "1");
        return;
    }
    if (std.mem.eql(u8, kind, "WINDOW")) {
        window_size.accept(&fields);
        return;
    }
    if (std.mem.eql(u8, kind, "PAINTED")) {
        const sequence = std.fmt.parseInt(u64, fields.next() orelse return, 10) catch return;
        if (fields.next() == null) painted(sequence);
        return;
    }
    if (std.mem.eql(u8, kind, "STATE")) {
        window_size.acceptState(&fields);
        return;
    }
    if (std.mem.eql(u8, kind, "CLOSE-ASKED")) {
        const kept = fields.next() orelse return;
        if (fields.next() != null or !(std.mem.eql(u8, kept, "0") or std.mem.eql(u8, kept, "1"))) return;
        window_size.closes +%= 1;
        close_pending = kept[0] == '1';
        return;
    }
    const event: forth.InputEvent = if (std.mem.eql(u8, kind, "KEY")) blk: {
        const code = std.fmt.parseInt(u32, fields.next() orelse return, 10) catch return;
        break :blk .{ .window_key = code };
    } else if (std.mem.eql(u8, kind, "TEXT")) blk: {
        const code_point = std.fmt.parseInt(u21, fields.next() orelse return, 10) catch return;
        break :blk .{ .window_text = code_point };
    } else if (std.mem.eql(u8, kind, "KEYUP")) blk: {
        const code = std.fmt.parseInt(u32, fields.next() orelse return, 10) catch return;
        break :blk .{ .window_key_release = code };
    } else if (std.mem.eql(u8, kind, "MOUSE")) blk: {
        const x = std.fmt.parseInt(i32, fields.next() orelse return, 10) catch return;
        const y = std.fmt.parseInt(i32, fields.next() orelse return, 10) catch return;
        const buttons = std.fmt.parseInt(u8, fields.next() orelse return, 10) catch return;
        const wheel = std.fmt.parseInt(i8, fields.next() orelse return, 10) catch return;
        break :blk .{ .window_mouse = .{ .x = x, .y = y, .buttons = buttons, .wheel = wheel } };
    } else return;
    queueInput(event);
}

/// Adds an event of the child to the queue. A move of the mouse takes the place of the
/// move before it, so that moves do not fill the queue while the program does not read.
/// In a full queue a new key or character is dropped, but a release of a key and a
/// change of the mouse buttons are not: the oldest event that is not a release goes.
fn queueInput(event: forth.InputEvent) void {
    switch (event) {
        .window_mouse => |mouse| {
            if (mouse.wheel == 0 and input_count != 0) {
                const last = &input_queue[(input_head + input_count - 1) % input_queue.len];
                if (last.* == .window_mouse and last.window_mouse.wheel == 0 and last.window_mouse.buttons == mouse.buttons and mouse.buttons == queued_buttons) {
                    last.* = event;
                    return;
                }
            }
            const changed = mouse.buttons != queued_buttons or (mouse.x == -1 and mouse.y == -1);
            if (input_count == input_queue.len and !(changed and dropOldestInput())) return;
            queued_buttons = mouse.buttons;
        },
        .window_key_release => |code| {
            if (input_count == input_queue.len and !dropOldestInput()) return;
            for (&held_keys) |*held| {
                if (held.* == code) held.* = 0;
            }
        },
        .window_key => |code| {
            if (input_count == input_queue.len) return;
            for (&held_keys) |*held| {
                if (held.* == code) break;
            } else for (&held_keys) |*held| {
                if (held.* == 0) {
                    held.* = code;
                    break;
                }
            }
        },
        else => if (input_count == input_queue.len) return,
    }
    input_queue[(input_head + input_count) % input_queue.len] = event;
    input_count += 1;
}

/// Takes the oldest event that is not a release of a key out of a full queue; false
/// when there is none.
fn dropOldestInput() bool {
    var index: usize = 0;
    while (index < input_count) : (index += 1) {
        if (input_queue[(input_head + index) % input_queue.len] != .window_key_release) break;
    } else return false;
    while (index + 1 < input_count) : (index += 1) {
        input_queue[(input_head + index) % input_queue.len] = input_queue[(input_head + index + 1) % input_queue.len];
    }
    input_count -= 1;
    return true;
}

fn updatePreeditHex(encoded: []const u8) void {
    preedit_length = 0;
    if (std.mem.eql(u8, encoded, "-")) return;
    if (encoded.len % 2 != 0) return;
    const byte_count = @min(encoded.len / 2, preedit_buffer.len);
    for (0..byte_count) |index| {
        const byte = std.fmt.parseInt(u8, encoded[index * 2 ..][0..2], 16) catch {
            preedit_length = 0;
            return;
        };
        preedit_buffer[index] = byte;
    }
    // A capacity boundary may cut a multibyte character. Keep only complete scalars.
    var valid_length: usize = 0;
    while (valid_length < byte_count) {
        const sequence = std.unicode.utf8ByteSequenceLength(preedit_buffer[valid_length]) catch break;
        if (valid_length + sequence > byte_count) break;
        _ = std.unicode.utf8Decode(preedit_buffer[valid_length .. valid_length + sequence]) catch break;
        valid_length += sequence;
    }
    preedit_length = valid_length;
}

fn readUntil(fd: std.c.fd_t, expected: []const u8, deadline: u64) bool {
    while (true) {
        var buffer: [640]u8 = undefined;
        const line = readLine(fd, &buffer, deadline) catch return false;
        if (std.mem.eql(u8, line, expected)) return true;
        enqueueInputLine(line);
    }
}

fn readFrameStatus(fd: std.c.fd_t, expected: []const u8, deadline: u64) forth.RuntimeError!void {
    while (true) {
        var buffer: [640]u8 = undefined;
        const line = readLine(fd, &buffer, deadline) catch return error.HostFailed;
        if (std.mem.eql(u8, line, expected)) return;
        if (std.mem.eql(u8, line, "ERROR MEMORY")) return error.MemoryExhausted;
        if (std.mem.startsWith(u8, line, "INPUT ")) {
            enqueueInputLine(line);
            continue;
        }
        if (std.mem.startsWith(u8, line, "DISPLAY ")) {
            enqueueInputLine(line);
            continue;
        }
        if (std.mem.eql(u8, line, "CLOSED") or std.mem.eql(u8, line, "EXIT 0")) child_said_closed = true;
        return error.HostFailed;
    }
}

/// Gracefully asks the child to quit, then uses bounded termination and detached reap.
pub fn close() void {
    const child = child_process orelse return;
    var saw_exit = false;
    const deadline = monotonicNs() + std.time.ns_per_s;
    _ = writeAllUntil(child.to_child, "QUIT\n", deadline) catch {};
    var responses: u16 = 0;
    while (monotonicNs() < deadline and responses < 512 and !saw_exit) {
        var buffer: [640]u8 = undefined;
        const line = readLine(child.from_child, &buffer, deadline) catch break;
        if (std.mem.eql(u8, line, "EXIT 0")) saw_exit = true;
        enqueueInputLine(line);
        responses += 1;
    }
    _ = std.c.close(child.to_child);
    _ = std.c.close(child.from_child);
    if (!saw_exit) terminateAndReap(child.pid) else reapBounded(child.pid);
    child_process = null;
    publishPaint();
    window_size.gone();
}

fn startChild() forth.RuntimeError!void {
    if (!parent_ready) return error.HostUnavailable;
    var to_child: [2]std.c.fd_t = undefined;
    var from_child: [2]std.c.fd_t = undefined;
    if (std.c.pipe(&to_child) != 0) return error.HostUnavailable;
    if (std.c.pipe(&from_child) != 0) {
        _ = std.c.close(to_child[0]);
        _ = std.c.close(to_child[1]);
        return error.HostUnavailable;
    }
    if (!moveAboveStdio(&to_child) or !moveAboveStdio(&from_child)) {
        closePipe(to_child);
        closePipe(from_child);
        return error.HostUnavailable;
    }

    var actions: std.c.posix_spawn_file_actions_t = undefined;
    if (std.c.posix_spawn_file_actions_init(&actions) != 0) {
        closePipe(to_child);
        closePipe(from_child);
        return error.HostUnavailable;
    }
    defer _ = std.c.posix_spawn_file_actions_destroy(&actions);
    if (std.c.posix_spawn_file_actions_adddup2(&actions, to_child[0], 0) != 0 or
        std.c.posix_spawn_file_actions_adddup2(&actions, from_child[1], 1) != 0)
    {
        closePipe(to_child);
        closePipe(from_child);
        return error.HostUnavailable;
    }
    for ([_]std.c.fd_t{ to_child[0], to_child[1], from_child[0], from_child[1] }) |fd| {
        if (std.c.posix_spawn_file_actions_addclose(&actions, fd) != 0) {
            closePipe(to_child);
            closePipe(from_child);
            return error.HostUnavailable;
        }
    }

    var attributes: std.c.posix_spawnattr_t = undefined;
    if (std.c.posix_spawnattr_init(&attributes) != 0) {
        closePipe(to_child);
        closePipe(from_child);
        return error.HostUnavailable;
    }
    defer _ = std.c.posix_spawnattr_destroy(&attributes);
    if (std.c.posix_spawnattr_setflags(&attributes, .{ .CLOEXEC_DEFAULT = true }) != 0) {
        closePipe(to_child);
        closePipe(from_child);
        return error.HostUnavailable;
    }
    const arguments = [_:null]?[*:0]const u8{ executable_path.ptr, child_argument.ptr };
    var pid: std.c.pid_t = 0;
    const spawned = std.c.posix_spawn(&pid, executable_path.ptr, &actions, &attributes, &arguments, environment.ptr);
    _ = std.c.close(to_child[0]);
    _ = std.c.close(from_child[1]);
    if (spawned != 0) {
        _ = std.c.close(to_child[1]);
        _ = std.c.close(from_child[0]);
        return error.HostUnavailable;
    }
    const child = ChildProcess{ .pid = pid, .to_child = to_child[1], .from_child = from_child[0] };
    errdefer {
        _ = std.c.close(child.to_child);
        _ = std.c.close(child.from_child);
        terminateAndReap(pid);
    }
    // No program started later (wish, SYSTEM, a pipe) inherits these ends: with the
    // write end open elsewhere, the child would not see the end of its input when
    // Sigma has gone.
    if (std.c.fcntl(child.to_child, 2, @as(c_int, 1)) == -1 or std.c.fcntl(child.from_child, 2, @as(c_int, 1)) == -1) return error.HostUnavailable; // F_SETFD, FD_CLOEXEC
    // Prevent a dead child from delivering SIGPIPE and a stalled child from blocking
    // the Forth thread while it is receiving a large frame.
    if (std.c.fcntl(child.to_child, 73, @as(c_int, 1)) == -1) return error.HostUnavailable; // F_SETNOSIGPIPE
    const flags = std.c.fcntl(child.to_child, 3, @as(c_int, 0)); // F_GETFL
    if (flags < 0 or std.c.fcntl(child.to_child, 4, flags | 4) == -1) return error.HostUnavailable; // F_SETFL, O_NONBLOCK
    const startup_deadline = monotonicNs() + 5 * std.time.ns_per_s;
    writeAllUntil(child.to_child, "HELLO 1\n", startup_deadline) catch return error.HostUnavailable;
    if (!readUntil(child.from_child, "READY 1", startup_deadline)) return error.HostUnavailable;
    var caret_buffer: [96]u8 = undefined;
    const caret_line = std.fmt.bufPrint(&caret_buffer, "CARET {d} {d} {d} {d}\n", .{ @intFromBool(ime_caret.active), ime_caret.x, ime_caret.y, ime_caret.height }) catch return error.HostFailed;
    try writeAllUntil(child.to_child, caret_line, startup_deadline);
    // WINDOW-ON first, so that a window opened while fullscreen is wanted covers that display.
    if (parent_place != 0) {
        var place_buffer: [40]u8 = undefined;
        try writeAllUntil(child.to_child, std.fmt.bufPrint(&place_buffer, "PLACE {d}\n", .{parent_place}) catch return error.HostFailed, startup_deadline);
    }
    // A window opened while fullscreen is wanted covers its screen at once.
    try writeAllUntil(child.to_child, if (fullscreen_wanted) "FULLSCREEN 1\n" else "FULLSCREEN 0\n", startup_deadline);
    try writeAllUntil(child.to_child, if (cursor_visible) "CURSOR 1\n" else "CURSOR 0\n", startup_deadline);
    var fit_buffer: [8]u8 = undefined;
    try writeAllUntil(child.to_child, std.fmt.bufPrint(&fit_buffer, "FIT {d}\n", .{@backingInt(parent_fit)}) catch return error.HostFailed, startup_deadline);
    try writeAllUntil(child.to_child, if (parent_smooth) "SMOOTH 1\n" else "SMOOTH 0\n", startup_deadline);
    try writeAllUntil(child.to_child, if (parent_keep_open) "KEEP-OPEN 1\n" else "KEEP-OPEN 0\n", startup_deadline);
    close_pending = false;
    child_process = child;
    paint_input_ended = false;
    physical_receiver = .{ .sync_pending = physical_state.tracker.stale };
    physical_state.available = true;
    physical_state.supported = @splat(0);
    for (physical_map.darwin) |scan| if (scan != 102 and (scan < 127 or scan > 129)) {
        physical_state.support(scan);
    };
    window_was_ready = true;
}

fn moveAboveStdio(pipe_fds: *[2]std.c.fd_t) bool {
    for (pipe_fds) |*fd| {
        if (fd.* > 2) continue;
        const duplicate = std.c.fcntl(fd.*, std.c.F.DUPFD, @as(c_int, 3));
        if (duplicate < 0) return false;
        _ = std.c.close(fd.*);
        fd.* = duplicate;
    }
    return true;
}

fn closePipe(fds: [2]std.c.fd_t) void {
    _ = std.c.close(fds[0]);
    _ = std.c.close(fds[1]);
}

fn writeAllUntil(fd: std.c.fd_t, bytes: []const u8, deadline: u64) forth.RuntimeError!void {
    var remaining = bytes;
    while (remaining.len != 0) {
        const now = monotonicNs();
        if (now >= deadline) return error.HostFailed;
        const count = std.c.write(fd, remaining.ptr, remaining.len);
        if (count < 0 and std.c._errno().* == @backingInt(std.c.E.INTR)) continue;
        if (count < 0 and std.c._errno().* == @backingInt(std.c.E.AGAIN)) {
            const wait_ms: c_int = @intCast(@min((deadline - now + std.time.ns_per_ms - 1) / std.time.ns_per_ms, std.math.maxInt(c_int)));
            var descriptors = [_]std.c.pollfd{.{ .fd = fd, .events = std.c.POLL.OUT, .revents = 0 }};
            const ready = std.c.poll(&descriptors, descriptors.len, wait_ms);
            if (ready < 0 and std.c._errno().* == @backingInt(std.c.E.INTR)) continue;
            if (ready <= 0) return error.HostFailed;
            continue;
        }
        if (count <= 0) return error.HostFailed;
        remaining = remaining[@intCast(count)..];
    }
}

fn readLine(fd: std.c.fd_t, buffer: []u8, deadline: u64) forth.RuntimeError![]const u8 {
    var used: usize = 0;
    while (used < buffer.len) {
        const now = monotonicNs();
        if (now >= deadline) return error.HostFailed;
        const remaining_ms: c_int = @intCast(@min((deadline - now + std.time.ns_per_ms - 1) / std.time.ns_per_ms, std.math.maxInt(c_int)));
        var descriptors = [_]std.c.pollfd{.{ .fd = fd, .events = std.c.POLL.IN, .revents = 0 }};
        const ready = std.c.poll(&descriptors, descriptors.len, remaining_ms);
        if (ready < 0 and std.c._errno().* == @backingInt(std.c.E.INTR)) continue;
        if (ready <= 0) return error.HostFailed;
        var byte: u8 = undefined;
        const count = std.c.read(fd, @ptrCast(&byte), 1);
        if (count < 0 and std.c._errno().* == @backingInt(std.c.E.INTR)) continue;
        if (count <= 0) return error.HostFailed;
        if (byte == '\n') return buffer[0..used];
        buffer[used] = byte;
        used += 1;
    }
    return error.HostFailed;
}

fn monotonicNs() u64 {
    var now: std.c.timespec = undefined;
    if (std.c.clock_gettime(std.c.CLOCK.MONOTONIC, &now) != 0) return 0;
    return @as(u64, @intCast(now.sec)) * std.time.ns_per_s + @as(u64, @intCast(now.nsec));
}

fn failChild() void {
    const child = child_process orelse return;
    terminateAndReap(child.pid);
    forgetChild(child);
}

fn terminateAndReap(pid: std.c.pid_t) void {
    _ = kill(pid, 15);
    if (waitBounded(pid, 100 * std.time.ns_per_ms)) return;
    _ = kill(pid, 9);
    if (!waitBounded(pid, 100 * std.time.ns_per_ms)) {
        const thread = std.Thread.spawn(.{}, reap, .{pid}) catch return;
        thread.detach();
    }
}

fn reapBounded(pid: std.c.pid_t) void {
    if (!waitBounded(pid, 500 * std.time.ns_per_ms)) terminateAndReap(pid);
}

fn waitBounded(pid: std.c.pid_t, duration: u64) bool {
    const deadline = monotonicNs() + duration;
    while (monotonicNs() < deadline) {
        var status: c_int = 0;
        const result = waitpid(pid, &status, 1); // WNOHANG
        if (result == pid or (result < 0 and std.c._errno().* == @backingInt(std.c.E.CHILD))) return true;
        var delay: std.c.timespec = .{ .sec = 0, .nsec = 1_000_000 };
        _ = std.c.nanosleep(&delay, null);
    }
    return false;
}

fn reap(pid: std.c.pid_t) void {
    var status: c_int = 0;
    while (waitpid(pid, &status, 0) < 0 and std.c._errno().* == @backingInt(std.c.E.INTR)) {}
}

fn checkParentGreeting() !void {
    const expected = "HELLO 1\n";
    var received: [expected.len]u8 = undefined;
    var used: usize = 0;
    while (used < received.len) {
        const count = std.c.read(0, received[used..].ptr, received.len - used);
        if (count <= 0) return error.InvalidParentGreeting;
        used += @intCast(count);
    }
    if (!std.mem.eql(u8, &received, expected)) return error.InvalidParentGreeting;
}

fn drawCalibration(_: Id, _: Sel, _: Rect) callconv(.c) void {
    did_draw = true;
    const view = active_view orelse return;
    const bounds = getRect(view, selector_register("bounds"));
    const backing_bounds = convertRect(view, "convertRectToBacking:", bounds);
    const color_class = objc_get_class.?("NSColor") orelse return;
    const black = send_color.?(color_class, selector_register("colorWithCalibratedRed:green:blue:alpha:"), 0, 0, 0, 1) orelse return;
    send_void0.?(black, selector_register("set"));
    rect_fill(bounds);
    if (frame_pixels.len != 0) {
        const target_backing = fittedRect(backing_bounds, frame_width, frame_height, child_fit);
        drawQuartzImage(frame_pixels, frame_width, frame_height, target_backing, convertRect(view, "convertRectFromBacking:", target_backing));
        // WINDOW-FRAMES and WINDOW-PAINT-WAIT (tque 1302): the image is drawn in the
        // window's backing store; the window server shows it at its next composition.
        if (child_frame_sequence != child_painted_sequence) {
            child_painted_sequence = child_frame_sequence;
            var buffer: [48]u8 = undefined;
            const line = std.fmt.bufPrint(&buffer, "INPUT PAINTED {d}\n", .{child_frame_sequence}) catch return;
            outputInput(line, true);
        }
    }
}

/// Where the image goes in the drawing area (in backing pixels, AppKit's y growing
/// upward), by WINDOW-FIT as window_layout.placeFit lays it out on Windows and Linux:
/// with `aspect`, the width limits it when cw × ih <= ch × iw, else the height, with
/// floor division; an odd spare pixel goes right or below.
fn fittedRect(bounds: Rect, image_width: u32, image_height: u32, fit: window_layout.Fit) Rect {
    const cw = backingSide(bounds.size.width);
    const ch = backingSide(bounds.size.height);
    const p = window_layout.placeFit(fit, image_width, image_height, cw, ch);
    return .{
        .origin = .{ .x = bounds.origin.x + @as(f64, @floatFromInt(p.x)), .y = bounds.origin.y + @as(f64, @floatFromInt(ch - p.y - p.h)) },
        .size = .{ .width = @floatFromInt(p.w), .height = @floatFromInt(p.h) },
    };
}

fn backingSide(value: f64) u32 {
    if (!std.math.isFinite(value) or value < 1) return 1;
    return @intFromFloat(@min(@round(value), 1 << 20));
}

test "fittedRect follows the contract's rule, the odd pixel right and below" {
    const r = fittedRect(.{ .origin = .{ .x = 0, .y = 0 }, .size = .{ .width = 100, .height = 100 } }, 100, 101, .aspect);
    try std.testing.expectEqual(@as(f64, 99), r.size.width);
    try std.testing.expectEqual(@as(f64, 100), r.size.height);
    // 1 by 1 in 4 by 3: 3 by 3, the spare column on the right.
    const s = fittedRect(.{ .origin = .{ .x = 0, .y = 0 }, .size = .{ .width = 4, .height = 3 } }, 1, 1, .aspect);
    try std.testing.expectEqual(@as(f64, 0), s.origin.x);
    // 1 by 1 in 3 by 4: the spare row below, at y 0 to 1 (y grows upward).
    const t = fittedRect(.{ .origin = .{ .x = 0, .y = 0 }, .size = .{ .width = 3, .height = 4 } }, 1, 1, .aspect);
    try std.testing.expectEqual(@as(f64, 1), t.origin.y);
}

test "fittedRect lays out by WINDOW-FIT as window_layout.placeFit, y upward" {
    const bounds: Rect = .{ .origin = .{ .x = 0, .y = 0 }, .size = .{ .width = 1000, .height = 700 } };
    // 320 by 200, three times (960 by 600) at 20 50 from the top left: 50 from the bottom too.
    const whole = fittedRect(bounds, 320, 200, .whole);
    try std.testing.expectEqual(Rect{ .origin = .{ .x = 20, .y = 50 }, .size = .{ .width = 960, .height = 600 } }, whole);
    try std.testing.expectEqual(Rect{ .origin = .{ .x = 0, .y = 0 }, .size = .{ .width = 1000, .height = 700 } }, fittedRect(bounds, 320, 200, .stretch));
    // 200 by 120 in 700 by 500: aspect 0 40 700 420 from the top, so 40 from the bottom.
    const aspect = fittedRect(.{ .origin = .{ .x = 0, .y = 0 }, .size = .{ .width = 700, .height = 500 } }, 200, 120, .aspect);
    try std.testing.expectEqual(Rect{ .origin = .{ .x = 0, .y = 40 }, .size = .{ .width = 700, .height = 420 } }, aspect);
    // 200 by 120 in 700 by 501 by whole factors: 600 by 360 at 50 70 from the top, 71 from the bottom.
    const odd = fittedRect(.{ .origin = .{ .x = 0, .y = 0 }, .size = .{ .width = 700, .height = 501 } }, 200, 120, .whole);
    try std.testing.expectEqual(Rect{ .origin = .{ .x = 50, .y = 71 }, .size = .{ .width = 600, .height = 360 } }, odd);
}

fn getRect(object: Id, selector: Sel) Rect {
    if (@import("builtin").cpu.arch == .x86_64) {
        var result: Rect = undefined;
        send_rect_stret.?(&result, object, selector);
        return result;
    }
    return send_rect0.?(object, selector);
}

fn convertRect(object: Id, selector_name: [*:0]const u8, rect: Rect) Rect {
    const selector = selector_register(selector_name);
    if (@import("builtin").cpu.arch == .x86_64) {
        var result: Rect = undefined;
        send_rect1_stret.?(&result, object, selector, rect);
        return result;
    }
    return send_rect1.?(object, selector, rect);
}

fn convertRectToWindow(view: Id, rect: Rect) Rect {
    const selector = selector_register("convertRect:toView:");
    if (@import("builtin").cpu.arch == .x86_64) {
        var result: Rect = undefined;
        send_rect_to_view_stret.?(&result, view, selector, rect, null);
        return result;
    }
    return send_rect_to_view.?(view, selector, rect, null);
}

fn convertRectToScreen(window: Id, rect: Rect) Rect {
    const selector = selector_register("convertRectToScreen:");
    if (@import("builtin").cpu.arch == .x86_64) {
        var result: Rect = undefined;
        send_rect1_stret.?(&result, window, selector, rect);
        return result;
    }
    return send_rect1.?(window, selector, rect);
}

fn convertSizeFromBacking(window: Id, size: Size) Size {
    const selector = selector_register("convertSizeFromBacking:");
    if (@import("builtin").cpu.arch == .x86_64) {
        var result: Size = undefined;
        send_size_stret.?(&result, window, selector, size);
        return result;
    }
    return send_size_return.?(window, selector, size);
}

const ProviderCreate = *const fn (?*anyopaque, ?*const anyopaque, usize, ?*const anyopaque) callconv(.c) Id;
const ColorSpaceCreate = *const fn () callconv(.c) Id;
const ImageCreate = *const fn (usize, usize, usize, usize, usize, Id, u32, Id, ?*const anyopaque, bool, u32) callconv(.c) Id;
const ContextDrawImage = *const fn (Id, Rect, Id) callconv(.c) void;
const ContextInterpolation = *const fn (Id, u32) callconv(.c) void;
const ReleaseQuartz = *const fn (Id) callconv(.c) void;
var cg_provider: ProviderCreate = undefined;
var cg_color_space: ColorSpaceCreate = undefined;
var cg_image: ImageCreate = undefined;
var cg_draw: ContextDrawImage = undefined;
var cg_interpolation: ContextInterpolation = undefined;
var cg_release: ReleaseQuartz = undefined;
var cg_provider_release: ReleaseQuartz = undefined;
var cg_color_release: ReleaseQuartz = undefined;
var send_id0_global: SendId0 = undefined;
var send_string_from_utf8: SendString = undefined;

/// Brings the image to output_width × output_height pixels for drawing: each output
/// pixel is the image's pixel it falls in (window_layout's nearest rule), or, with
/// `smooth` (WINDOW-SMOOTH), the average of the part of the image it covers where a
/// factor is not a whole number (smoothRows, as on Windows and Linux). Without memory
/// for the averages it draws the nearest pixels. The output is opaque.
fn scaleImage(out: []u32, output_width: usize, output_height: usize, pixels: []const u32, width: u32, height: u32, smooth: ?*window_layout.Smooth) void {
    if (smooth) |work| if (output_width <= 1 << 20 and output_height <= 1 << 20) {
        const drawn_width: u32 = @intCast(output_width);
        const drawn_height: u32 = @intCast(output_height);
        if ((drawn_width % width != 0 or drawn_height % height != 0) and work.fit(std.heap.page_allocator, drawn_width)) {
            work.begin(width, drawn_width);
            window_layout.smoothRows(work, pixels, width, height, out, drawn_width, drawn_height, 0, drawn_height);
            // smoothRows gives colors only; the window's pixels are opaque.
            for (out[0 .. output_width * output_height]) |*pixel| pixel.* |= 0xff00_0000;
            return;
        }
    };
    for (0..output_height) |y| {
        const source_y = @min(@as(usize, height - 1), y * @as(usize, height) / output_height);
        for (0..output_width) |x| {
            const source_x = @min(@as(usize, width - 1), x * @as(usize, width) / output_width);
            out[y * output_width + x] = pixels[source_y * width + source_x];
        }
    }
}

test "scaleImage averages by area with WINDOW-SMOOTH, and takes the nearest pixel without" {
    var work: window_layout.Smooth = .{};
    defer work.free(std.heap.page_allocator);
    const image = [_]u32{ 0xff00_0000, 0xffff_ffff }; // black, white
    var out: [3]u32 = undefined;
    scaleImage(&out, 3, 1, &image, 2, 1, null);
    try std.testing.expectEqualSlices(u32, &.{ 0xff00_0000, 0xff00_0000, 0xffff_ffff }, &out);
    scaleImage(&out, 3, 1, &image, 2, 1, &work);
    // The middle output pixel covers half of each: gray, between 0x7f and 0x80.
    try std.testing.expectEqual(@as(u32, 0xff00_0000), out[0]);
    try std.testing.expectEqual(@as(u32, 0xffff_ffff), out[2]);
    try std.testing.expect(out[1] == 0xff80_8080 or out[1] == 0xff7f_7f7f);
    // Whole factors give the nearest pixels also when smooth.
    var twice: [4]u32 = undefined;
    scaleImage(&twice, 4, 1, &image, 2, 1, &work);
    try std.testing.expectEqualSlices(u32, &.{ 0xff00_0000, 0xff00_0000, 0xffff_ffff, 0xffff_ffff }, &twice);
    // Another image of the same width is not mixed with the rows of the first.
    const red = [_]u32{ 0xffff_0000, 0xffff_0000 };
    scaleImage(&out, 3, 1, &red, 2, 1, &work);
    try std.testing.expectEqualSlices(u32, &.{ 0xffff_0000, 0xffff_0000, 0xffff_0000 }, &out);
}

fn drawQuartzImage(pixels: []const u32, width: u32, height: u32, target_backing: Rect, target_points: Rect) void {
    const output_width: usize = @intFromFloat(@max(1, target_backing.size.width));
    const output_height: usize = @intFromFloat(@max(1, target_backing.size.height));
    const scaled = std.heap.page_allocator.alloc(u32, std.math.mul(usize, output_width, output_height) catch return) catch return;
    defer std.heap.page_allocator.free(scaled);
    scaleImage(scaled, output_width, output_height, pixels, width, height, if (child_smooth) &smoother else null);
    const context_class = objc_get_class.?("NSGraphicsContext") orelse return;
    const context_obj = send_id0_global(context_class, selector_register("currentContext")) orelse return;
    const context = send_id0_global(context_obj, selector_register("CGContext")) orelse return;
    const provider = cg_provider(null, @ptrCast(scaled.ptr), scaled.len * 4, null) orelse return;
    defer cg_provider_release(provider);
    const color_space = cg_color_space() orelse return;
    defer cg_color_release(color_space);
    // Little-endian BGRA memory represents the host's 0xAARRGGBB word.
    const image = cg_image(output_width, output_height, 8, 32, output_width * 4, color_space, 0x2002, provider, null, false, 0) orelse return;
    defer cg_release(image);
    cg_interpolation(context, 1); // kCGInterpolationNone
    cg_draw(context, target_points, image);
}

var objc_get_class: ?ObjcGetClass = null;
var send_color: ?SendColor = null;
var send_void0: ?SendVoid0 = null;

/// The window entered or left fullscreen, also by the user: the parent's FULLSCREEN?
/// follows it.
/// A transition begins, Sigma's or the user's: frames do not resize the window and no
/// other toggle starts until it ends.
fn windowWillEnterFullScreen(_: Id, _: Sel, _: Id) callconv(.c) void {
    if (!transition_by_sigma) asked_during_transition = false;
    fullscreen_transitioning = true;
}

fn windowWillExitFullScreen(_: Id, _: Sel, _: Id) callconv(.c) void {
    if (!transition_by_sigma) asked_during_transition = false;
    fullscreen_transitioning = true;
}

/// A transition ended. One the user made is now wanted, and the parent is told (its
/// FULLSCREEN? follows); one Sigma asked for needs no word. Then the window goes on
/// toward what is wanted now.
fn endTransition(now_fullscreen: bool) void {
    // The user's transition decides, unless Sigma asked something meanwhile.
    const by_user = !transition_by_sigma and !asked_during_transition;
    fullscreen_transitioning = false;
    transition_by_sigma = false;
    asked_during_transition = false;
    if (by_user and fullscreen_desired != now_fullscreen) {
        fullscreen_desired = now_fullscreen;
        outputInput(if (now_fullscreen) "INPUT FULLSCREEN 1\n" else "INPUT FULLSCREEN 0\n", true);
    }
    // AppKit restores the window's pre-fullscreen frame. Keep that size and position;
    // resizing here would discard a user's manual resize and move.
    reconcileFullscreen();
}

fn windowDidEnterFullScreen(_: Id, _: Sel, _: Id) callconv(.c) void {
    endTransition(true);
}

fn windowDidExitFullScreen(_: Id, _: Sel, _: Id) callconv(.c) void {
    endTransition(false);
}

/// A transition that did not happen (another one, or the system refused): the window
/// stays as it is, and so does the wish, which the parent is told of.
fn windowDidFailToEnterFullScreen(_: Id, _: Sel, _: Id) callconv(.c) void {
    fullscreen_transitioning = false;
    transition_by_sigma = false;
    fullscreen_desired = false;
    outputInput("INPUT FULLSCREEN 0\n", true);
}

fn windowDidFailToExitFullScreen(_: Id, _: Sel, _: Id) callconv(.c) void {
    fullscreen_transitioning = false;
    transition_by_sigma = false;
    fullscreen_desired = true;
    outputInput("INPUT FULLSCREEN 1\n", true);
}

fn windowIsFullscreen(window: Id) bool {
    return send_usize0(window, selector_register("styleMask")) & (1 << 14) != 0; // NSWindowStyleMaskFullScreen
}

/// One transition at a time, toward fullscreen_desired as it is when the last ends. A
/// WINDOW-ON move waiting goes first: out of fullscreen (Sigma's transition, so the wish
/// stays), then the move, then back into fullscreen on the new display.
fn reconcileFullscreen() void {
    if (fullscreen_transitioning) return;
    const window = active_window orelse return;
    if (pending_place != 0) {
        if (windowIsFullscreen(window)) {
            fullscreen_transitioning = true;
            transition_by_sigma = true;
            place_after_exit = true;
            send_void1(window, selector_register("toggleFullScreen:"), null);
            return;
        }
        // AppKit puts the window back to its frame from before fullscreen just after
        // it has left fullscreen, which would undo the move: wait a moment first.
        if (place_after_exit) {
            place_after_exit = false;
            if (dispatch_after) |after| if (dispatch_time) |time| {
                fullscreen_transitioning = true;
                after(time(0, 400 * std.time.ns_per_ms), main_queue, null, placeLater);
                return;
            };
        }
        const id = pending_place;
        pending_place = 0;
        moveToScreen(window, id);
    }
    if (fullscreen_desired == windowIsFullscreen(window)) return;
    if (fullscreen_desired) {
        if (active_app) |app| _ = send_bool1(app, selector_register("activateIgnoringOtherApps:"), 1);
        _ = send_id1(window, selector_register("makeKeyAndOrderFront:"), null);
    }
    fullscreen_transitioning = true;
    transition_by_sigma = true;
    send_void1(window, selector_register("toggleFullScreen:"), null);
}

/// WINDOW-ON: puts the window in the middle of the visible frame of the screen whose
/// displayKey is `id`, as large as it is where that fits, else as large as the visible
/// frame. Nothing when no such screen is there: the window stays where it is.
fn moveToScreen(window: Id, id: u64) void {
    const screen_class = objc_get_class.?("NSScreen") orelse return;
    const screens = send_id0_global(screen_class, selector_register("screens")) orelse return;
    const count = send_usize0(screens, selector_register("count"));
    for (0..count) |index| {
        const screen = (send_id_index orelse return)(screens, selector_register("objectAtIndex:"), index) orelse continue;
        if (screenKey(screen) != id) continue;
        const visible = getRect(screen, selector_register("visibleFrame"));
        var frame = getRect(window, selector_register("frame"));
        frame.size.width = @min(frame.size.width, visible.size.width);
        frame.size.height = @min(frame.size.height, visible.size.height);
        frame.origin.x = visible.origin.x + @floor((visible.size.width - frame.size.width) / 2);
        frame.origin.y = visible.origin.y + @floor((visible.size.height - frame.size.height) / 2);
        (send_set_frame orelse return)(window, selector_register("setFrame:display:animate:"), frame, 1, 0);
        return;
    }
}

/// host_display_macos.displayKey of a screen: its CGDirectDisplayID with the digest of
/// its monitor, as DISPLAYS names displays; 0 when the screen has no number.
fn screenKey(screen: Id) u64 {
    const description = send_id0_global(screen, selector_register("deviceDescription")) orelse return 0;
    const string_class = objc_get_class.?("NSString") orelse return 0;
    const key = send_string_from_utf8(string_class, selector_register("stringWithUTF8String:"), "NSScreenNumber\x00") orelse return 0;
    const number = send_id1(description, selector_register("objectForKey:"), key) orelse return 0;
    const string = send_id0_global(number, selector_register("stringValue")) orelse return 0;
    const utf8 = send_utf8(string, selector_register("UTF8String")) orelse return 0;
    const cg = std.fmt.parseInt(u32, std.mem.span(utf8), 10) catch return 0;
    return host_display_macos.displayKey(cg);
}

/// The window's size for the image shown (WINDOW-SIZE, or 0 0 by the work area).
fn fitWindowToFrame() void {
    const window = active_window orelse return;
    const view = active_view orelse return;
    if (frame_width == 0 or frame_height == 0) return;
    const desired = requestedClientSize(frame_width, frame_height, last_requested_size, roomFor(window, view));
    const points = convertSizeFromBacking(view, .{ .width = @floatFromInt(desired[0]), .height = @floatFromInt(desired[1]) });
    send_size1(window, selector_register("setContentSize:"), points);
    if (last_requested_size[0] == 0 and last_requested_size[1] == 0) keepAutoSizedWindowVisible(window);
}

/// `setContentSize:` changes the window's frame but does not guarantee that the
/// resulting frame stays inside NSScreen.visibleFrame. Clamp its origin after sizing.
fn keepAutoSizedWindowVisible(window: Id) void {
    const screen = send_id0_global(window, selector_register("screen")) orelse blk: {
        const screen_class = objc_get_class.?("NSScreen") orelse return;
        break :blk send_id0_global(screen_class, selector_register("mainScreen")) orelse return;
    };
    const visible = getRect(screen, selector_register("visibleFrame"));
    var frame = getRect(window, selector_register("frame"));
    const max_x = visible.origin.x + @max(0, visible.size.width - frame.size.width);
    const max_y = visible.origin.y + @max(0, visible.size.height - frame.size.height);
    frame.origin.x = std.math.clamp(frame.origin.x, visible.origin.x, max_x);
    frame.origin.y = std.math.clamp(frame.origin.y, visible.origin.y, max_y);
    (send_set_frame orelse return)(window, selector_register("setFrame:display:animate:"), frame, 1, 0);
}

/// Child: makes the window cover its screen (a fullscreen Space) or a window again,
/// and takes the keys for fullscreen.
fn applyFullscreen(on: bool) void {
    if (fullscreen_transitioning) asked_during_transition = true;
    fullscreen_desired = on;
    reconcileFullscreen();
}

/// Child: MOUSE-CURSOR, by the view's cursor rectangle (resetCursorRects), so that
/// the cursor is hidden only over the image's view, not over the title bar or other
/// programs.
fn applyCursor(visible: bool) void {
    child_cursor_visible = visible;
    const window = active_window orelse return;
    const view = active_view orelse return;
    send_void1(window, selector_register("invalidateCursorRectsForView:"), view);
}

/// A cursor of an empty 1 by 1 image: nothing shows.
fn blankCursor() Id {
    if (blank_cursor != null) return blank_cursor;
    const size_to_id = send_size_to_id orelse return null;
    const image_hot_spot = send_image_hot_spot orelse return null;
    const image_class = objc_get_class.?("NSImage") orelse return null;
    const cursor_class = objc_get_class.?("NSCursor") orelse return null;
    const image_alloc = send_id0_global(image_class, selector_register("alloc")) orelse return null;
    const image = size_to_id(image_alloc, selector_register("initWithSize:"), .{ .width = 1, .height = 1 }) orelse return null;
    // Drawing nothing gives the image a representation of transparent pixels.
    send_void0.?(image, selector_register("lockFocus"));
    send_void0.?(image, selector_register("unlockFocus"));
    const cursor_alloc = send_id0_global(cursor_class, selector_register("alloc")) orelse return null;
    blank_cursor = image_hot_spot(cursor_alloc, selector_register("initWithImage:hotSpot:"), image, .{ .x = 0, .y = 0 });
    return blank_cursor;
}

fn resetCursorRects(self: Id, _: Sel) callconv(.c) void {
    if (child_cursor_visible) return;
    const add = send_rect_cursor orelse return;
    const cursor = blankCursor() orelse return;
    add(self, selector_register("addCursorRect:cursor:"), getRect(self, selector_register("bounds")), cursor);
}

fn windowWillClose(_: Id, _: Sel, _: Id) callconv(.c) void {
    did_close = true;
    releaseAllInput(true);
    output("CLOSED\n");
    if (active_app) |app| send_void1(app, selector_register("stop:"), null);
}

fn applicationDidFinishLaunching(_: Id, _: Sel, _: Id) callconv(.c) void {
    output("READY 1\n");
    reportWindow(true);
    reportState();
}

/// Tells the parent the size of the content area in backing pixels (tque 1266). `changed`:
/// the scale, the screen, or the displays changed, so the parent counts a change also
/// when the size is the same. Called on the AppKit thread; the line is kept when the
/// pipe is full, so that the parent's count does not miss it.
fn reportWindow(changed: bool) void {
    if (did_close) return;
    const view = active_view orelse return;
    const backing = convertRect(view, "convertRectToBacking:", getRect(view, selector_register("bounds")));
    const width = backingLength(backing.size.width);
    const height = backingLength(backing.size.height);
    var buffer: [64]u8 = undefined;
    const line = std.fmt.bufPrint(&buffer, "INPUT WINDOW {d} {d} {d}\n", .{ width, height, @intFromBool(changed) }) catch return;
    outputInput(line, true);
}

fn backingLength(value: f64) u32 {
    if (!std.math.isFinite(value) or value <= 0) return 0;
    return @intFromFloat(@min(@round(value), 1 << 20));
}

fn windowDidResize(_: Id, _: Sel, _: Id) callconv(.c) void {
    reportWindow(false);
}

fn windowDidChangeBackingProperties(_: Id, _: Sel, _: Id) callconv(.c) void {
    reportWindow(true);
}

fn windowDidChangeScreen(_: Id, _: Sel, _: Id) callconv(.c) void {
    reportWindow(true);
}

fn applicationDidChangeScreenParameters(_: Id, _: Sel, _: Id) callconv(.c) void {
    reportWindow(true);
}

fn acceptsFirstResponder(_: Id, _: Sel) callconv(.c) i8 {
    return 1;
}

fn clearMarkedText() void {
    const was_marked = marked_text != null;
    if (marked_text) |text| send_void0.?(text, selector_register("release"));
    marked_text = null;
    marked_selection = .{ .location = 0, .length = 0 };
    if (was_marked) sendInputPreedit(&.{});
}

fn hasMarkedText(_: Id, _: Sel) callconv(.c) i8 {
    return @intFromBool(marked_text != null);
}

fn markedRange(_: Id, _: Sel) callconv(.c) Range {
    const text = marked_text orelse return .{ .location = std.math.maxInt(usize), .length = 0 };
    return .{ .location = 0, .length = send_usize0(text, selector_register("length")) };
}

fn selectedRange(_: Id, _: Sel) callconv(.c) Range {
    return marked_selection;
}

fn setMarkedText(_: Id, _: Sel, text: Id, selection: Range, replacement: Range) callconv(.c) void {
    const attributed = objc_get_class.?("NSAttributedString") orelse return;
    const plain = if (send_is_kind(text, selector_register("isKindOfClass:"), attributed) != 0)
        send_id0_global(text, selector_register("string")) orelse return
    else
        text;
    const copy = send_id0_global(plain, selector_register("copy")) orelse return;
    clearMarkedText();
    const length = send_usize0(copy, selector_register("length"));
    if (length == 0) {
        send_void0.?(copy, selector_register("release"));
        sendInputPreedit(&.{});
        return;
    }
    marked_text = copy;
    const start = if (replacement.location == std.math.maxInt(usize)) 0 else replacement.location;
    marked_selection = .{
        .location = start + @min(selection.location, length),
        .length = @min(selection.length, length - @min(selection.location, length)),
    };
    const utf8 = send_utf8(copy, selector_register("UTF8String")) orelse return;
    sendInputPreedit(std.mem.span(utf8));
}

fn unmarkText(_: Id, _: Sel) callconv(.c) void {
    clearMarkedText();
}

fn validAttributesForMarkedText(_: Id, _: Sel) callconv(.c) Id {
    const array_class = objc_get_class.?("NSArray") orelse return null;
    return send_id0_global(array_class, selector_register("array"));
}

fn attributedSubstringForProposedRange(_: Id, _: Sel, _: Range, actual: ?*Range) callconv(.c) Id {
    if (actual) |range| range.* = .{ .location = std.math.maxInt(usize), .length = 0 };
    return null;
}

fn firstRectForCharacterRange(_: Id, _: Sel, range: Range, actual: ?*Range) callconv(.c) Rect {
    if (actual) |value| value.* = range;
    const view = active_view orelse return emptyCandidateRect();
    const window = active_window orelse return emptyCandidateRect();
    if (frame_width == 0 or frame_height == 0) return emptyCandidateRect();
    const bounds = convertRect(view, "convertRectToBacking:", getRect(view, selector_register("bounds")));
    const place = fittedRect(bounds, frame_width, frame_height, child_fit);
    const image_width = @max(frame_width, 1);
    const image_height = @max(frame_height, 1);
    const caret: ImeCaret = if (ime_caret.active) ime_caret else .{ .active = true, .x = 0, .y = 0, .height = 18 };
    const scale_x = place.size.width / @as(f64, @floatFromInt(image_width));
    const scale_y = place.size.height / @as(f64, @floatFromInt(image_height));
    const height = @max(1, @as(f64, @floatFromInt(caret.height)) * scale_y);
    const backing_rect = Rect{
        .origin = .{
            .x = place.origin.x + @as(f64, @floatFromInt(caret.x)) * scale_x,
            .y = place.origin.y + place.size.height - @as(f64, @floatFromInt(caret.y)) * scale_y - height,
        },
        .size = .{ .width = 1, .height = height },
    };
    const view_rect = convertRect(view, "convertRectFromBacking:", backing_rect);
    const window_rect = convertRectToWindow(view, view_rect);
    return convertRectToScreen(window, window_rect);
}

fn emptyCandidateRect() Rect {
    return .{ .origin = .{ .x = 0, .y = 0 }, .size = .{ .width = 1, .height = 18 } };
}

fn characterIndexForPoint(_: Id, _: Sel, _: Point) callconv(.c) usize {
    return std.math.maxInt(usize);
}

fn doCommandBySelector(_: Id, _: Sel, _: Sel) callconv(.c) void {}

fn keyDown(self: Id, _: Sel, event: Id) callconv(.c) void {
    const hardware = send_keycode(event, selector_register("keyCode"));
    if (hardware >= pressed_keys.len) return;
    // Control+Command+F (the F key, 3) leaves fullscreen; it is no key for INKEY.
    const flags = send_usize0(event, selector_register("modifierFlags"));
    const control_command = (1 << 18) | (1 << 20);
    if (hardware == 3 and flags & control_command == control_command) {
        if (active_window) |window| if (windowIsFullscreen(window)) {
            fullscreen_desired = false;
            outputInput("INPUT FULLSCREEN 0\n", true);
            reconcileFullscreen();
            return;
        };
    }
    if (specialKey(hardware)) |special| if (marked_text == null) {
        const previous = pressed_keys[hardware];
        if (previous != 0 and previous != special) sendInput("KEYUP", previous);
        pressed_keys[hardware] = special;
        sendInput("KEY", special);
        return;
    };
    const array_class = objc_get_class.?("NSArray") orelse return;
    const events = send_id1(array_class, selector_register("arrayWithObject:"), event) orelse return;
    current_hardware_key = hardware;
    send_void1(self, selector_register("interpretKeyEvents:"), events);
    current_hardware_key = std.math.maxInt(usize);
}

fn insertText(_: Id, _: Sel, text: Id) callconv(.c) void {
    const attributed = objc_get_class.?("NSAttributedString") orelse return;
    const string = if (send_is_kind(text, selector_register("isKindOfClass:"), attributed) != 0)
        send_id0_global(text, selector_register("string")) orelse return
    else
        text;
    const utf8 = send_utf8(string, selector_register("UTF8String")) orelse return;
    const bytes = std.mem.span(utf8);
    var offset: usize = 0;
    var first = true;
    while (offset < bytes.len) {
        const length = std.unicode.utf8ByteSequenceLength(bytes[offset]) catch {
            offset += 1;
            continue;
        };
        if (offset + length > bytes.len) break;
        const code_point = std.unicode.utf8Decode(bytes[offset .. offset + length]) catch {
            offset += length;
            continue;
        };
        sendInputText(code_point);
        if (first and current_hardware_key < pressed_keys.len) {
            const previous = pressed_keys[current_hardware_key];
            if (previous != 0 and (code_point >= 0x80 or previous != code_point)) sendInput("KEYUP", previous);
            pressed_keys[current_hardware_key] = if (code_point < 0x80) code_point else 0;
        }
        first = false;
        offset += length;
    }
    clearMarkedText();
}

fn insertTextWithRange(_: Id, _: Sel, text: Id, _: Range) callconv(.c) void {
    insertText(null, null, text);
}

fn keyUp(_: Id, _: Sel, event: Id) callconv(.c) void {
    const hardware = send_keycode(event, selector_register("keyCode"));
    if (hardware >= pressed_keys.len) return;
    const code = pressed_keys[hardware];
    if (code != 0) sendInput("KEYUP", code);
    pressed_keys[hardware] = 0;
}

fn mouseMoved(_: Id, _: Sel, event: Id) callconv(.c) void {
    reportMouse(event, 0, false, 0);
}
fn leftMouseDown(_: Id, _: Sel, event: Id) callconv(.c) void {
    reportMouse(event, 1, true, 0);
}
fn leftMouseUp(_: Id, _: Sel, event: Id) callconv(.c) void {
    reportMouse(event, 1, false, 0);
}
fn leftMouseDragged(_: Id, _: Sel, event: Id) callconv(.c) void {
    reportMouse(event, 0, false, 0);
}
fn rightMouseDown(_: Id, _: Sel, event: Id) callconv(.c) void {
    reportMouse(event, 2, true, 0);
}
fn rightMouseUp(_: Id, _: Sel, event: Id) callconv(.c) void {
    reportMouse(event, 2, false, 0);
}
fn rightMouseDragged(_: Id, _: Sel, event: Id) callconv(.c) void {
    reportMouse(event, 0, false, 0);
}
fn otherMouseDown(_: Id, _: Sel, event: Id) callconv(.c) void {
    reportMouse(event, 4, true, 0);
}
fn otherMouseUp(_: Id, _: Sel, event: Id) callconv(.c) void {
    reportMouse(event, 4, false, 0);
}
fn otherMouseDragged(_: Id, _: Sel, event: Id) callconv(.c) void {
    reportMouse(event, 0, false, 0);
}

fn scrollWheel(_: Id, _: Sel, event: Id) callconv(.c) void {
    wheel_remainder += send_double0(event, selector_register("scrollingDeltaY"));
    var notch: i8 = 0;
    if (wheel_remainder >= 1) {
        notch = 1;
        wheel_remainder -= 1;
    }
    if (wheel_remainder <= -1) {
        notch = -1;
        wheel_remainder += 1;
    }
    reportMouse(event, 0, false, notch);
}

fn reportMouse(event: Id, button: u8, down: bool, wheel: i8) void {
    if (frame_width == 0 or frame_height == 0) return;
    const view = active_view orelse return;
    const window_point = eventLocation(event);
    const local = convertPointFromWindow(view, window_point);
    const point = convertPointToBacking(view, local);
    const bounds = convertRect(view, "convertRectToBacking:", getRect(view, selector_register("bounds")));
    const place = fittedRect(bounds, frame_width, frame_height, child_fit);
    const shown_w = @max(place.size.width, 1);
    const shown_h = @max(place.size.height, 1);
    const x: i32 = @intFromFloat(std.math.clamp(@floor((point.x - place.origin.x) * @as(f64, @floatFromInt(frame_width)) / shown_w), -1048576, 1048576));
    const y: i32 = @intFromFloat(std.math.clamp(@floor((place.origin.y + shown_h - point.y) * @as(f64, @floatFromInt(frame_height)) / shown_h), -1048576, 1048576));
    const moved = x != last_mouse_x or y != last_mouse_y;
    last_mouse_x = x;
    last_mouse_y = y;
    if (button != 0) {
        if (down) mouse_buttons |= button else mouse_buttons &= ~button;
    }
    const now = monotonicNs();
    if (button == 0 and wheel == 0 and mouse_buttons == 0 and (!moved or now -| last_mouse_event_ns < 16 * std.time.ns_per_ms)) return;
    last_mouse_event_ns = now;
    sendMouseInput(x, y, mouse_buttons, wheel);
}

fn sendMouseInput(x: i32, y: i32, buttons: u8, wheel: i8) void {
    var buffer: [96]u8 = undefined;
    const line = std.fmt.bufPrint(&buffer, "INPUT MOUSE {d} {d} {d} {d}\n", .{ x, y, buttons, wheel }) catch return;
    const keep = buttons != sent_buttons or (x == -1 and y == -1);
    sent_buttons = buttons;
    outputInput(line, keep);
}

/// The Forth thread may wait on terminal input without draining this pipe.
/// Never block the AppKit event loop for an input notification.
/// Lines of the child that must reach the parent (a key released, the mouse buttons
/// changed, the window closed) and could not be written while the pipe was full. They
/// go out before anything else, in their order.
var kept_input: [2048]u8 = undefined;
var kept_input_length: usize = 0;

/// Writes kept_input, as far as the pipe takes it. The caller holds stdout_lock.
fn writeKeptInput() void {
    while (kept_input_length != 0) {
        // A line is at most PIPE_BUF (512) bytes, so a write that does not wait takes a
        // whole line or nothing.
        const end = if (std.mem.indexOfScalar(u8, kept_input[0..kept_input_length], '\n')) |newline| newline + 1 else kept_input_length;
        const written = std.c.write(1, &kept_input, end);
        if (written <= 0) return;
        const count: usize = @intCast(written);
        std.mem.copyForwards(u8, kept_input[0 .. kept_input_length - count], kept_input[count..kept_input_length]);
        kept_input_length -= count;
    }
}

/// Tells the parent of input without waiting for it to read: the window answers the
/// user also while the program computes. A line that the full pipe does not take is
/// dropped, or kept for later when `keep` says that it must not be lost.
fn outputInput(bytes: []const u8, keep: bool) void {
    while (stdout_lock.swap(1, .acquire) != 0) std.atomic.spinLoopHint();
    defer stdout_lock.store(0, .release);
    const flags = std.c.fcntl(1, 3, @as(c_int, 0)); // F_GETFL
    if (flags < 0 or std.c.fcntl(1, 4, flags | 4) == -1) return; // F_SETFL, O_NONBLOCK
    defer _ = std.c.fcntl(1, 4, flags);
    writeKeptInput();
    if (kept_input_length == 0 and std.c.write(1, bytes.ptr, bytes.len) == @as(isize, @intCast(bytes.len))) return;
    if (keep and bytes.len <= kept_input.len - kept_input_length) {
        @memcpy(kept_input[kept_input_length..][0..bytes.len], bytes);
        kept_input_length += bytes.len;
    }
}

var physical_sender: physical_protocol.Sender = .{};
var physical_guard = std.atomic.Value(u8).init(0);
var physical_sync_requested = std.atomic.Value(bool).init(false);
const ObjcSuper = extern struct { receiver: Id, superclass: Id };
const SendSuperEvent = *const fn (*ObjcSuper, Sel, Id) callconv(.c) void;
var send_super_event: SendSuperEvent = undefined;
var application_superclass: Id = null;

/// Caller holds physical_guard and stdout_lock. Every physical line fits PIPE_BUF.
fn physicalWrite(line: []const u8) bool {
    const flags = std.c.fcntl(1, 3, @as(c_int, 0));
    if (flags < 0 or std.c.fcntl(1, 4, flags | 4) == -1) return false;
    defer _ = std.c.fcntl(1, 4, flags);
    return std.c.write(1, line.ptr, line.len) == @as(isize, @intCast(line.len));
}
fn physicalTryWrite(_: ?*anyopaque, line: []const u8) bool {
    if (stdout_lock.cmpxchgStrong(0, 1, .acquire, .monotonic) != null) return false;
    defer stdout_lock.store(0, .release);
    return physicalWrite(line);
}
const physical_writer: physical_protocol.Writer = .{ .context = null, .write = physicalTryWrite };
fn physicalFlush() void {
    if (physical_guard.cmpxchgStrong(0, 1, .acquire, .monotonic) != null) return;
    defer physical_guard.store(0, .release);
    if (physical_sync_requested.swap(false, .acq_rel)) physical_sender.dirty = true;
    physical_sender.flush(physical_writer);
}
fn physicalChildEdge(scan: u8, down_: bool) void {
    if (scan == 102 or (scan >= 127 and scan <= 129)) return;
    while (physical_guard.swap(1, .acquire) != 0) std.atomic.spinLoopHint();
    defer physical_guard.store(0, .release);
    physical_sender.edge(scan, down_, physical_writer);
}
fn physicalChildRelease() void {
    while (physical_guard.swap(1, .acquire) != 0) std.atomic.spinLoopHint();
    defer physical_guard.store(0, .release);
    physical_sender.releaseAll(physical_writer);
}
fn applicationSendEvent(app: Id, selector: Sel, event: Id) callconv(.c) void {
    const kind = send_usize0(event, selector_register("type"));
    if (active_window != null and send_id0_global(event, selector_register("window")) == active_window and (kind == 10 or kind == 11 or kind == 12)) {
        const scan = physical_map.darwinScan(send_keycode(event, selector_register("keyCode")));
        if (kind == 12 and scan >= 224 and scan <= 231) {
            // Device-specific bits from Apple IOHIDFamily/IOLLEvent.h.
            const masks = [_]usize{ 1, 2, 32, 8, 8192, 4, 64, 16 };
            const groups = [_]usize{ 0x40000, 0x20000, 0x80000, 0x100000 };
            const flags = send_usize0(event, selector_register("modifierFlags"));
            const index = scan - 224;
            const target = flags & masks[index] != 0;
            const other = flags & masks[index ^ 4] != 0;
            const either = flags & groups[index % 4] != 0;
            physicalChildEdge(scan, if (either != (target or other)) either else target);
        } else if (kind != 12) physicalChildEdge(scan, kind == 10);
    }
    var super = ObjcSuper{ .receiver = app, .superclass = application_superclass };
    send_super_event(&super, selector, event);
}

fn releaseAllInput(closed: bool) void {
    physicalChildRelease();
    for (&pressed_keys) |*code| {
        if (code.* != 0) sendInput("KEYUP", code.*);
        code.* = 0;
    }
    mouse_buttons = 0;
    if (closed) {
        last_mouse_x = -1;
        last_mouse_y = -1;
    }
    sendMouseInput(last_mouse_x, last_mouse_y, 0, 0);
}

fn windowDidResignKey(_: Id, _: Sel, _: Id) callconv(.c) void {
    releaseAllInput(false);
    clearMarkedText();
    reportState();
}

/// Tells the parent whether the window has the keyboard and whether it is minimized
/// (tque 1297), as an INPUT STATE line that is kept when the pipe is full. AppKit thread.
fn reportState() void {
    if (did_close) return;
    const window = active_window orelse return;
    const focused = send_bool0(window, selector_register("isKeyWindow")) != 0;
    const minimized = send_bool0(window, selector_register("isMiniaturized")) != 0;
    outputInput(if (minimized) (if (focused) "INPUT STATE 1 1\n" else "INPUT STATE 0 1\n") else if (focused) "INPUT STATE 1 0\n" else "INPUT STATE 0 0\n", true);
}

fn windowDidBecomeKey(_: Id, _: Sel, _: Id) callconv(.c) void {
    reportState();
}

fn windowDidMiniaturize(_: Id, _: Sel, _: Id) callconv(.c) void {
    reportState();
}

fn windowDidDeminiaturize(_: Id, _: Sel, _: Id) callconv(.c) void {
    reportState();
}

/// AppKit asks this only when the user closes the window (its button, or the system's
/// key), not when the program does: so it counts WINDOW-CLOSES (tque 1297). The line
/// says 1 when the window stays (WINDOW-KEEP-OPEN), 0 when it closes.
fn windowShouldClose(_: Id, _: Sel, _: Id) callconv(.c) i8 {
    // With WINDOW-KEEP-OPEN the window stays, unless the program has not read the
    // request before (tque 1328): a program that does not look cannot hold it open.
    if (child_keep_open.load(.acquire) and !child_close_unseen.load(.acquire)) {
        child_close_unseen.store(true, .release);
        outputInput("INPUT CLOSE-ASKED 1\n", true);
        return 0;
    }
    child_close_unseen.store(false, .release);
    outputInput("INPUT CLOSE-ASKED 0\n", true);
    return 1;
}

fn eventLocation(event: Id) Point {
    const selector = selector_register("locationInWindow");
    if (@import("builtin").cpu.arch == .x86_64) {
        var result: Point = undefined;
        send_point0_stret.?(&result, event, selector);
        return result;
    }
    return send_point0.?(event, selector);
}

fn convertPointFromWindow(view: Id, point: Point) Point {
    if (@import("builtin").cpu.arch == .x86_64) {
        var result: Point = undefined;
        send_point_from_view_stret.?(&result, view, selector_register("convertPoint:fromView:"), point, null);
        return result;
    }
    return send_point_from_view.?(view, selector_register("convertPoint:fromView:"), point, null);
}

fn convertPointToBacking(view: Id, point: Point) Point {
    if (@import("builtin").cpu.arch == .x86_64) {
        var result: Point = undefined;
        send_point_transform_stret.?(&result, view, selector_register("convertPointToBacking:"), point);
        return result;
    }
    return send_point_transform.?(view, selector_register("convertPointToBacking:"), point);
}

fn specialKey(hardware: u16) ?u32 {
    return switch (hardware) {
        126 => 256,
        125 => 257,
        123 => 258,
        124 => 259,
        115 => 260,
        119 => 261,
        116 => 262,
        121 => 263,
        117 => 265,
        122 => 266,
        120 => 267,
        99 => 268,
        118 => 269,
        96 => 270,
        97 => 271,
        98 => 272,
        100 => 273,
        101 => 274,
        109 => 275,
        103 => 276,
        111 => 277,
        36, 76 => 13,
        51 => 8,
        48 => 9,
        53 => 27,
        else => null,
    };
}

fn sendInput(kind: []const u8, code: u32) void {
    var buffer: [64]u8 = undefined;
    const line = std.fmt.bufPrint(&buffer, "INPUT {s} {d}\n", .{ kind, code }) catch return;
    outputInput(line, std.mem.eql(u8, kind, "KEYUP"));
}

fn sendInputText(code_point: u21) void {
    var buffer: [64]u8 = undefined;
    const line = std.fmt.bufPrint(&buffer, "INPUT TEXT {d}\n", .{code_point}) catch return;
    outputInput(line, false);
}

fn sendInputPreedit(bytes: []const u8) void {
    const bounded = bytes[0..@min(bytes.len, 240)];
    if (bounded.len == 0) {
        outputInput("INPUT PREEDIT -\n", false);
        return;
    }
    const hex = "0123456789ABCDEF";
    var buffer: [544]u8 = undefined;
    const prefix = "INPUT PREEDIT ";
    @memcpy(buffer[0..prefix.len], prefix);
    for (bounded, 0..) |byte, index| {
        buffer[prefix.len + index * 2] = hex[byte >> 4];
        buffer[prefix.len + index * 2 + 1] = hex[byte & 0xf];
    }
    const length = prefix.len + bounded.len * 2;
    buffer[length] = '\n';
    outputInput(buffer[0 .. length + 1], false);
}

fn sendCurrentPreedit() void {
    const text = marked_text orelse {
        sendInputPreedit(&.{});
        return;
    };
    const utf8 = send_utf8(text, selector_register("UTF8String")) orelse {
        sendInputPreedit(&.{});
        return;
    };
    sendInputPreedit(std.mem.span(utf8));
}

fn postWakeEvent(app: Id) void {
    const event_class = objc_get_class.?("NSEvent") orelse return;
    const event = send_other_event(event_class, selector_register("otherEventWithType:location:modifierFlags:timestamp:windowNumber:context:subtype:data1:data2:"), 15, .{ .x = 0, .y = 0 }, 0, 0, 0, null, 0, 0, 0) orelse return;
    post_event(app, selector_register("postEvent:atStart:"), event, 1);
}

fn runCommand(context: ?*anyopaque) callconv(.c) void {
    const command: *Command = @ptrCast(@alignCast(context orelse return));
    defer std.heap.page_allocator.destroy(command);
    switch (command.*) {
        .frame => |frame| {
            if (frame_pixels.len != 0) std.heap.page_allocator.free(frame_pixels);
            frame_pixels = frame.pixels;
            frame_width = frame.width;
            frame_height = frame.height;
            child_frame_sequence = frame.sequence;
            if (!std.mem.eql(u32, &last_frame_size, &.{ frame.width, frame.height }) or !std.mem.eql(u32, &last_requested_size, &frame.requested)) {
                last_frame_size = .{ frame.width, frame.height };
                last_requested_size = frame.requested;
                // A fullscreen window keeps covering its screen. AppKit restores the
                // saved window frame when fullscreen ends; later frames use this size.
                if (active_window) |window| if (!fullscreen_transitioning and !windowIsFullscreen(window)) fitWindowToFrame();
            }
            if (active_view) |view| _ = send_bool1(view, selector_register("setNeedsDisplay:"), 1);
            var buffer: [64]u8 = undefined;
            const line = std.fmt.bufPrint(&buffer, "FRAME-ACCEPTED {d}\n", .{frame.sequence}) catch return;
            output(line);
            sendCurrentPreedit();
        },
        .fullscreen => |on| applyFullscreen(on),
        .place => |id| {
            pending_place = id;
            reconcileFullscreen();
        },
        .fit => |fit| {
            child_fit = fit;
            if (active_view) |view| _ = send_bool1(view, selector_register("setNeedsDisplay:"), 1);
        },
        .smooth => |on| {
            child_smooth = on;
            if (active_view) |view| _ = send_bool1(view, selector_register("setNeedsDisplay:"), 1);
        },
        .cursor => |visible| applyCursor(visible),
        .caret => |caret| {
            ime_caret = caret;
            if (active_view) |view| {
                if (send_id0_global(view, selector_register("inputContext"))) |input_context| {
                    send_void0.?(input_context, selector_register("invalidateCharacterCoordinates"));
                }
            }
        },
        .display_query => |sequence| {
            var buffer: [64]u8 = undefined;
            const line = std.fmt.bufPrint(&buffer, "DISPLAY {d} {d}\n", .{ sequence, windowDisplayId() }) catch return;
            output(line);
        },
        .quit => {
            output("QUIT-ACCEPTED\n");
            if (active_app) |app| {
                send_void1(app, selector_register("stop:"), null);
                postWakeEvent(app);
            }
        },
    }
}

/// Called on the AppKit thread. A missing or not-yet-attached screen has id 0.
fn windowDisplayId() u64 {
    if (did_close) return 0;
    const window = active_window orelse return 0;
    const screen = send_id0_global(window, selector_register("screen")) orelse return 0;
    return screenKey(screen);
}

fn queueCommand(command: Command) bool {
    const owned = std.heap.page_allocator.create(Command) catch return false;
    owned.* = command;
    dispatch_async(main_queue, owned, runCommand);
    return true;
}

/// The reader thread of the child. When it ends without a QUIT of the parent (the
/// parent has gone and its pipe gives end of file, or what it sent cannot be read),
/// the child ends as for a QUIT, so that no window stays without its parent.
fn readParentCommands() void {
    if (!readParentLoop()) _ = queueCommand(.quit);
}

/// True when the parent sent QUIT and it was queued.
fn readParentLoop() bool {
    var line: [128]u8 = undefined;
    var used: usize = 0;
    while (true) {
        physicalFlush();
        var descriptor = [_]std.c.pollfd{.{ .fd = 0, .events = std.c.POLL.IN, .revents = 0 }};
        const ready = std.c.poll(&descriptor, 1, 16);
        if (ready < 0) {
            if (std.c._errno().* == @backingInt(std.c.E.INTR)) continue;
            return false;
        }
        if (ready == 0) continue;
        var byte: u8 = undefined;
        const count = std.c.read(0, @ptrCast(&byte), 1);
        if (count <= 0) return false;
        if (byte != '\n') {
            if (used == line.len) return false;
            line[used] = byte;
            used += 1;
            continue;
        }
        const message = line[0..used];
        used = 0;
        if (std.mem.eql(u8, message, "SCANSYNC")) {
            physical_sync_requested.store(true, .release);
            continue;
        }
        if (std.mem.eql(u8, message, "QUIT")) {
            return queueCommand(.quit);
        }
        if (std.mem.startsWith(u8, message, "DISPLAY? ")) {
            const sequence = std.fmt.parseInt(u64, message[9..], 10) catch continue;
            if (sequence == 0 or !queueCommand(.{ .display_query = sequence })) return false;
            continue;
        }
        if (std.mem.startsWith(u8, message, "FRAME ")) {
            receiveFrame(message[6..]) catch |err| {
                if (err == error.OutOfMemory) output("ERROR MEMORY\n") else output("ERROR PROTOCOL\n");
                return false;
            };
            continue;
        }
        if (std.mem.eql(u8, message, "FULLSCREEN 1") or std.mem.eql(u8, message, "FULLSCREEN 0")) {
            if (!queueCommand(.{ .fullscreen = message[11] == '1' })) return false;
            continue;
        }
        if (std.mem.eql(u8, message, "KEEP-OPEN 1") or std.mem.eql(u8, message, "KEEP-OPEN 0")) {
            const on = message[10] == '1';
            child_keep_open.store(on, .release);
            if (!on) child_close_unseen.store(false, .release);
            continue;
        }
        if (std.mem.eql(u8, message, "CLOSES-SEEN")) {
            child_close_unseen.store(false, .release);
            continue;
        }
        if (std.mem.startsWith(u8, message, "PLACE ")) {
            const id = std.fmt.parseInt(u64, message[6..], 10) catch continue;
            if (!queueCommand(.{ .place = id })) return false;
            continue;
        }
        if (std.mem.eql(u8, message, "SMOOTH 1") or std.mem.eql(u8, message, "SMOOTH 0")) {
            if (!queueCommand(.{ .smooth = message[7] == '1' })) return false;
            continue;
        }
        if (message.len == 5 and std.mem.startsWith(u8, message, "FIT ") and message[4] >= '0' and message[4] <= '2') {
            if (!queueCommand(.{ .fit = @fromBackingInt(@intCast(message[4] - '0')) })) return false;
            continue;
        }
        if (std.mem.eql(u8, message, "CURSOR 1") or std.mem.eql(u8, message, "CURSOR 0")) {
            if (!queueCommand(.{ .cursor = message[7] == '1' })) return false;
            continue;
        }
        if (std.mem.startsWith(u8, message, "CARET ")) {
            var fields = std.mem.tokenizeScalar(u8, message[6..], ' ');
            const active = (std.fmt.parseInt(u8, fields.next() orelse continue, 10) catch continue) != 0;
            const x = std.fmt.parseInt(i32, fields.next() orelse continue, 10) catch continue;
            const y = std.fmt.parseInt(i32, fields.next() orelse continue, 10) catch continue;
            const height = std.fmt.parseInt(u32, fields.next() orelse continue, 10) catch continue;
            if (fields.next() != null) continue;
            if (!queueCommand(.{ .caret = .{ .active = active, .x = x, .y = y, .height = height } })) return false;
        }
    }
}

fn receiveFrame(header: []const u8) !void {
    var fields = std.mem.tokenizeScalar(u8, header, ' ');
    const sequence = try std.fmt.parseInt(u64, fields.next() orelse return error.BadFrame, 10);
    const width = try std.fmt.parseInt(u32, fields.next() orelse return error.BadFrame, 10);
    const height = try std.fmt.parseInt(u32, fields.next() orelse return error.BadFrame, 10);
    const requested_width = try std.fmt.parseInt(u32, fields.next() orelse return error.BadFrame, 10);
    const requested_height = try std.fmt.parseInt(u32, fields.next() orelse return error.BadFrame, 10);
    if (fields.next() != null or width == 0 or height == 0 or width > 16384 or height > 16384) return error.BadFrame;
    if ((requested_width == 0) != (requested_height == 0) or requested_width > 16384 or requested_height > 16384) return error.BadFrame;
    const pixels = try std.heap.page_allocator.alloc(u32, @as(usize, width) * height);
    errdefer std.heap.page_allocator.free(pixels);
    var ready_buffer: [64]u8 = undefined;
    const ready_line = try std.fmt.bufPrint(&ready_buffer, "FRAME-READY {d}\n", .{sequence});
    output(ready_line);
    const raw = std.mem.sliceAsBytes(pixels);
    var received: usize = 0;
    while (received < raw.len) {
        const count = std.c.read(0, raw[received..].ptr, raw.len - received);
        if (count < 0 and std.c._errno().* == @backingInt(std.c.E.INTR)) continue;
        if (count <= 0) return error.BadFrame;
        received += @intCast(count);
    }
    if (@import("builtin").cpu.arch.endian() == .big) {
        for (pixels) |*pixel| pixel.* = @byteSwap(pixel.*);
    }
    if (!queueCommand(.{ .frame = .{ .sequence = sequence, .width = width, .height = height, .requested = .{ requested_width, requested_height }, .pixels = pixels } })) return error.OutOfMemory;
}

/// The client size in backing pixels: what WINDOW-SIZE gave, or for 0 0 the image's
/// size by window_layout, which also fits `room`.
fn requestedClientSize(image_width: u32, image_height: u32, requested: [2]u32, room: [2]u32) [2]u32 {
    if (requested[0] != 0) return requested;
    return window_layout.autoClientSize(image_width, image_height, room);
}

/// The room WINDOW-SIZE 0 0 may use, in backing pixels: the visible frame of the
/// window's screen (without the menu bar and the Dock), less the window's title bar
/// and frame. A side of 0 is not known.
fn roomFor(window: Id, view: Id) [2]u32 {
    const screen = send_id0_global(window, selector_register("screen")) orelse blk: {
        const screen_class = objc_get_class.?("NSScreen") orelse return .{ 0, 0 };
        break :blk send_id0_global(screen_class, selector_register("mainScreen")) orelse return .{ 0, 0 };
    };
    const visible = getRect(screen, selector_register("visibleFrame"));
    const outer = getRect(window, selector_register("frame"));
    const content = getRect(view, selector_register("bounds"));
    const width = visible.size.width - @max(0, outer.size.width - content.size.width);
    const height = visible.size.height - @max(0, outer.size.height - content.size.height);
    if (!(width >= 1 and height >= 1)) return .{ 0, 0 };
    const backing = convertRect(view, "convertRectToBacking:", .{ .origin = .{ .x = 0, .y = 0 }, .size = .{ .width = width, .height = height } });
    return .{ sideOf(backing.size.width), sideOf(backing.size.height) };
}

fn sideOf(value: f64) u32 {
    if (!(value >= 1)) return 1;
    return @intFromFloat(@min(@floor(value), 1 << 30));
}

fn output(bytes: []const u8) void {
    while (stdout_lock.swap(1, .acquire) != 0) std.atomic.spinLoopHint();
    defer stdout_lock.store(0, .release);
    // This write waits for the parent, so what was kept goes out first.
    writeKeptInput();
    var rest = bytes;
    while (rest.len != 0) {
        const written = std.c.write(1, rest.ptr, rest.len);
        if (written <= 0) return;
        rest = rest[@intCast(written)..];
    }
}

fn addMethod(allocate_class: AllocateClassPair, class_add_method: ClassAddMethod, register_class: RegisterClassPair, superclass: Id, name: [*:0]const u8, selector: Sel, implementation: Imp, encoding: [*:0]const u8) !Id {
    const cls = allocate_class(superclass, name, 0) orelse return error.ObjcClassAllocationFailed;
    if (class_add_method(cls, selector, implementation, encoding) == 0) return error.ObjcMethodRegistrationFailed;
    register_class(cls);
    return cls;
}

pub fn runChild() !u8 {
    try checkParentGreeting();
    var objc = try std.DynLib.open(objc_path);
    defer objc.close();
    var appkit = try std.DynLib.open(appkit_path);
    defer appkit.close();

    const get_class = objc.lookup(ObjcGetClass, "objc_getClass") orelse return error.ObjcRuntimeUnavailable;
    objc_get_class = get_class;
    selector_register = objc.lookup(SelRegisterName, "sel_registerName") orelse return error.ObjcRuntimeUnavailable;
    const allocate_class = objc.lookup(AllocateClassPair, "objc_allocateClassPair") orelse return error.ObjcRuntimeUnavailable;
    const class_add_method = objc.lookup(ClassAddMethod, "class_addMethod") orelse return error.ObjcRuntimeUnavailable;
    const register_class = objc.lookup(RegisterClassPair, "objc_registerClassPair") orelse return error.ObjcRuntimeUnavailable;
    const get_protocol = objc.lookup(ObjcGetProtocol, "objc_getProtocol") orelse return error.ObjcRuntimeUnavailable;
    const class_add_protocol = objc.lookup(ClassAddProtocol, "class_addProtocol") orelse return error.ObjcRuntimeUnavailable;
    const class_conforms_to_protocol = objc.lookup(ClassConformsToProtocol, "class_conformsToProtocol") orelse return error.ObjcRuntimeUnavailable;
    const send_id0 = objc.lookup(SendId0, "objc_msgSend") orelse return error.ObjcRuntimeUnavailable;
    send_id0_global = send_id0;
    send_range0 = objc.lookup(SendRange0, "objc_msgSend") orelse return error.ObjcRuntimeUnavailable;
    send_usize0 = objc.lookup(SendUsize0, "objc_msgSend") orelse return error.ObjcRuntimeUnavailable;
    send_size1 = objc.lookup(SendSize1, "objc_msgSend") orelse return error.ObjcRuntimeUnavailable;
    if (@import("builtin").cpu.arch == .x86_64) {
        send_rect_stret = objc.lookup(SendRectStret, "objc_msgSend_stret") orelse return error.ObjcRuntimeUnavailable;
        send_rect1_stret = objc.lookup(SendRect1Stret, "objc_msgSend_stret") orelse return error.ObjcRuntimeUnavailable;
        send_rect_to_view_stret = objc.lookup(SendRectToViewStret, "objc_msgSend_stret") orelse return error.ObjcRuntimeUnavailable;
        send_size_stret = objc.lookup(SendSizeStret, "objc_msgSend_stret") orelse return error.ObjcRuntimeUnavailable;
    } else {
        send_rect0 = objc.lookup(SendRect0, "objc_msgSend") orelse return error.ObjcRuntimeUnavailable;
        send_rect1 = objc.lookup(SendRect1, "objc_msgSend") orelse return error.ObjcRuntimeUnavailable;
        send_rect_to_view = objc.lookup(SendRectToView, "objc_msgSend") orelse return error.ObjcRuntimeUnavailable;
        send_size_return = objc.lookup(SendSizeReturn, "objc_msgSend") orelse return error.ObjcRuntimeUnavailable;
    }
    send_bool1 = objc.lookup(SendBool1, "objc_msgSend") orelse return error.ObjcRuntimeUnavailable;
    send_bool0 = objc.lookup(SendBool0, "objc_msgSend") orelse return error.ObjcRuntimeUnavailable;
    send_id_index = objc.lookup(SendIdIndex, "objc_msgSend");
    send_keycode = objc.lookup(SendU16, "objc_msgSend") orelse return error.ObjcRuntimeUnavailable;
    send_double0 = objc.lookup(SendDouble0, "objc_msgSend") orelse return error.ObjcRuntimeUnavailable;
    if (@import("builtin").cpu.arch == .x86_64) {
        send_point0_stret = objc.lookup(SendPoint0Stret, "objc_msgSend_stret") orelse return error.ObjcRuntimeUnavailable;
        send_point_from_view_stret = objc.lookup(SendPointFromViewStret, "objc_msgSend_stret") orelse return error.ObjcRuntimeUnavailable;
        send_point_transform_stret = objc.lookup(SendPointTransformStret, "objc_msgSend_stret") orelse return error.ObjcRuntimeUnavailable;
    } else {
        send_point0 = objc.lookup(SendPoint0, "objc_msgSend") orelse return error.ObjcRuntimeUnavailable;
        send_point_from_view = objc.lookup(SendPointFromView, "objc_msgSend") orelse return error.ObjcRuntimeUnavailable;
        send_point_transform = objc.lookup(SendPointTransform, "objc_msgSend") orelse return error.ObjcRuntimeUnavailable;
    }
    send_utf8 = objc.lookup(SendCString0, "objc_msgSend") orelse return error.ObjcRuntimeUnavailable;
    send_string_from_utf8 = objc.lookup(SendString, "objc_msgSend") orelse return error.ObjcRuntimeUnavailable;
    send_is_kind = objc.lookup(SendIdClass, "objc_msgSend") orelse return error.ObjcRuntimeUnavailable;
    const send_window = objc.lookup(SendInitWindow, "objc_msgSend") orelse return error.ObjcRuntimeUnavailable;
    const send_view = objc.lookup(SendInitView, "objc_msgSend") orelse return error.ObjcRuntimeUnavailable;
    send_id1 = objc.lookup(SendId1, "objc_msgSend") orelse return error.ObjcRuntimeUnavailable;
    send_color = objc.lookup(SendColor, "objc_msgSend") orelse return error.ObjcRuntimeUnavailable;
    send_other_event = objc.lookup(SendOtherEvent, "objc_msgSend") orelse return error.ObjcRuntimeUnavailable;
    send_void0 = objc.lookup(SendVoid0, "objc_msgSend") orelse return error.ObjcRuntimeUnavailable;
    send_void1 = objc.lookup(SendVoid1, "objc_msgSend") orelse return error.ObjcRuntimeUnavailable;
    send_size_to_id = objc.lookup(SendSizeToId, "objc_msgSend");
    send_image_hot_spot = objc.lookup(SendImageHotSpot, "objc_msgSend");
    send_rect_cursor = objc.lookup(SendRectCursor, "objc_msgSend");
    send_set_frame = objc.lookup(SendSetFrame, "objc_msgSend") orelse return error.ObjcRuntimeUnavailable;
    post_event = objc.lookup(PostEvent, "objc_msgSend") orelse return error.ObjcRuntimeUnavailable;
    rect_fill = appkit.lookup(RectFill, "NSRectFill") orelse return error.AppKitSymbolUnavailable;
    var graphics = try std.DynLib.open("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics");
    defer graphics.close();
    cg_provider = graphics.lookup(ProviderCreate, "CGDataProviderCreateWithData") orelse return error.AppKitSymbolUnavailable;
    cg_color_space = graphics.lookup(ColorSpaceCreate, "CGColorSpaceCreateDeviceRGB") orelse return error.AppKitSymbolUnavailable;
    cg_image = graphics.lookup(ImageCreate, "CGImageCreate") orelse return error.AppKitSymbolUnavailable;
    cg_draw = graphics.lookup(ContextDrawImage, "CGContextDrawImage") orelse return error.AppKitSymbolUnavailable;
    cg_interpolation = graphics.lookup(ContextInterpolation, "CGContextSetInterpolationQuality") orelse return error.AppKitSymbolUnavailable;
    cg_release = graphics.lookup(ReleaseQuartz, "CGImageRelease") orelse return error.AppKitSymbolUnavailable;
    // CGColorSpaceRelease and CGDataProviderRelease have the same ABI as CGImageRelease.
    cg_color_release = graphics.lookup(ReleaseQuartz, "CGColorSpaceRelease") orelse return error.AppKitSymbolUnavailable;
    cg_provider_release = graphics.lookup(ReleaseQuartz, "CGDataProviderRelease") orelse return error.AppKitSymbolUnavailable;
    var dispatch_lib = try std.DynLib.open(dispatch_path);
    defer dispatch_lib.close();
    dispatch_async = dispatch_lib.lookup(DispatchAsyncF, "dispatch_async_f") orelse return error.DispatchUnavailable;
    dispatch_after = dispatch_lib.lookup(DispatchAfterF, "dispatch_after_f");
    dispatch_time = dispatch_lib.lookup(DispatchTime, "dispatch_time");
    main_queue = dispatch_lib.lookup(*anyopaque, "_dispatch_main_q") orelse return error.DispatchUnavailable;
    if (main_queue == null) return error.DispatchUnavailable;

    const pool_class = get_class("NSAutoreleasePool") orelse return error.AppKitClassUnavailable;
    const pool = send_id0(pool_class, selector_register("alloc")) orelse return error.AppKitInitializationFailed;
    const pool_init = send_id0(pool, selector_register("init")) orelse return error.AppKitInitializationFailed;
    defer send_void0.?(pool_init, selector_register("drain"));

    application_superclass = get_class("NSApplication") orelse return error.AppKitClassUnavailable;
    send_super_event = objc.lookup(SendSuperEvent, "objc_msgSendSuper") orelse return error.ObjcRuntimeUnavailable;
    const app_class = try addMethod(allocate_class, class_add_method, register_class, application_superclass, "SigmaPhysicalApplication\x00", selector_register("sendEvent:"), @ptrCast(&applicationSendEvent), "v@:@\x00");
    const app = send_id0(app_class, selector_register("sharedApplication")) orelse return error.AppKitInitializationFailed;
    active_app = app;
    if (send_bool1(app, selector_register("setActivationPolicy:"), 0) == 0) return error.AppKitInitializationFailed;

    const object_class = get_class("NSObject") orelse return error.AppKitClassUnavailable;
    const delegate_class = try addMethod(allocate_class, class_add_method, register_class, object_class, "SigmaProbeDelegate\x00", selector_register("windowWillClose:"), @ptrCast(&windowWillClose), "v@:@\x00");
    if (class_add_method(delegate_class, selector_register("applicationDidFinishLaunching:"), @ptrCast(&applicationDidFinishLaunching), "v@:@\x00") == 0) return error.ObjcMethodRegistrationFailed;
    if (class_add_method(delegate_class, selector_register("windowDidResignKey:"), @ptrCast(&windowDidResignKey), "v@:@\x00") == 0) return error.ObjcMethodRegistrationFailed;
    if (class_add_method(delegate_class, selector_register("windowDidResize:"), @ptrCast(&windowDidResize), "v@:@\x00") == 0) return error.ObjcMethodRegistrationFailed;
    if (class_add_method(delegate_class, selector_register("windowDidBecomeKey:"), @ptrCast(&windowDidBecomeKey), "v@:@\x00") == 0) return error.ObjcMethodRegistrationFailed;
    if (class_add_method(delegate_class, selector_register("windowDidMiniaturize:"), @ptrCast(&windowDidMiniaturize), "v@:@\x00") == 0) return error.ObjcMethodRegistrationFailed;
    if (class_add_method(delegate_class, selector_register("windowDidDeminiaturize:"), @ptrCast(&windowDidDeminiaturize), "v@:@\x00") == 0) return error.ObjcMethodRegistrationFailed;
    if (class_add_method(delegate_class, selector_register("windowShouldClose:"), @ptrCast(&windowShouldClose), "c@:@\x00") == 0) return error.ObjcMethodRegistrationFailed;
    if (class_add_method(delegate_class, selector_register("windowDidChangeBackingProperties:"), @ptrCast(&windowDidChangeBackingProperties), "v@:@\x00") == 0) return error.ObjcMethodRegistrationFailed;
    if (class_add_method(delegate_class, selector_register("windowDidChangeScreen:"), @ptrCast(&windowDidChangeScreen), "v@:@\x00") == 0) return error.ObjcMethodRegistrationFailed;
    if (class_add_method(delegate_class, selector_register("applicationDidChangeScreenParameters:"), @ptrCast(&applicationDidChangeScreenParameters), "v@:@\x00") == 0) return error.ObjcMethodRegistrationFailed;
    if (class_add_method(delegate_class, selector_register("windowDidEnterFullScreen:"), @ptrCast(&windowDidEnterFullScreen), "v@:@\x00") == 0) return error.ObjcMethodRegistrationFailed;
    if (class_add_method(delegate_class, selector_register("windowDidExitFullScreen:"), @ptrCast(&windowDidExitFullScreen), "v@:@\x00") == 0) return error.ObjcMethodRegistrationFailed;
    if (class_add_method(delegate_class, selector_register("windowDidFailToEnterFullScreen:"), @ptrCast(&windowDidFailToEnterFullScreen), "v@:@\x00") == 0) return error.ObjcMethodRegistrationFailed;
    if (class_add_method(delegate_class, selector_register("windowWillEnterFullScreen:"), @ptrCast(&windowWillEnterFullScreen), "v@:@\x00") == 0) return error.ObjcMethodRegistrationFailed;
    if (class_add_method(delegate_class, selector_register("windowWillExitFullScreen:"), @ptrCast(&windowWillExitFullScreen), "v@:@\x00") == 0) return error.ObjcMethodRegistrationFailed;
    if (class_add_method(delegate_class, selector_register("windowDidFailToExitFullScreen:"), @ptrCast(&windowDidFailToExitFullScreen), "v@:@\x00") == 0) return error.ObjcMethodRegistrationFailed;
    const delegate_alloc = send_id0(delegate_class, selector_register("alloc")) orelse return error.AppKitInitializationFailed;
    const delegate = send_id0(delegate_alloc, selector_register("init")) orelse return error.AppKitInitializationFailed;

    const view_class = get_class("NSView") orelse return error.AppKitClassUnavailable;
    const probe_view_class = allocate_class(view_class, "SigmaProbeView\x00", 0) orelse return error.ObjcClassAllocationFailed;
    if (class_add_method(probe_view_class, selector_register("drawRect:"), @ptrCast(&drawCalibration), "v@:{CGRect={CGPoint=dd}{CGSize=dd}}\x00") == 0 or
        class_add_method(probe_view_class, selector_register("acceptsFirstResponder"), @ptrCast(&acceptsFirstResponder), "c@:\x00") == 0 or
        class_add_method(probe_view_class, selector_register("resetCursorRects"), @ptrCast(&resetCursorRects), "v@:\x00") == 0 or
        class_add_method(probe_view_class, selector_register("keyDown:"), @ptrCast(&keyDown), "v@:@\x00") == 0 or
        class_add_method(probe_view_class, selector_register("keyUp:"), @ptrCast(&keyUp), "v@:@\x00") == 0 or
        class_add_method(probe_view_class, selector_register("hasMarkedText"), @ptrCast(&hasMarkedText), "c@:\x00") == 0 or
        class_add_method(probe_view_class, selector_register("markedRange"), @ptrCast(&markedRange), "{_NSRange=QQ}@:\x00") == 0 or
        class_add_method(probe_view_class, selector_register("selectedRange"), @ptrCast(&selectedRange), "{_NSRange=QQ}@:\x00") == 0 or
        class_add_method(probe_view_class, selector_register("setMarkedText:selectedRange:replacementRange:"), @ptrCast(&setMarkedText), "v@:@{_NSRange=QQ}{_NSRange=QQ}\x00") == 0 or
        class_add_method(probe_view_class, selector_register("unmarkText"), @ptrCast(&unmarkText), "v@:\x00") == 0 or
        class_add_method(probe_view_class, selector_register("validAttributesForMarkedText"), @ptrCast(&validAttributesForMarkedText), "@@:\x00") == 0 or
        class_add_method(probe_view_class, selector_register("attributedSubstringForProposedRange:actualRange:"), @ptrCast(&attributedSubstringForProposedRange), "@@:{_NSRange=QQ}^{_NSRange=QQ}\x00") == 0 or
        class_add_method(probe_view_class, selector_register("firstRectForCharacterRange:actualRange:"), @ptrCast(&firstRectForCharacterRange), "{CGRect={CGPoint=dd}{CGSize=dd}}@:{_NSRange=QQ}^{_NSRange=QQ}\x00") == 0 or
        class_add_method(probe_view_class, selector_register("characterIndexForPoint:"), @ptrCast(&characterIndexForPoint), "Q@:{CGPoint=dd}\x00") == 0 or
        class_add_method(probe_view_class, selector_register("doCommandBySelector:"), @ptrCast(&doCommandBySelector), "v@::\x00") == 0 or
        class_add_method(probe_view_class, selector_register("insertText:"), @ptrCast(&insertText), "v@:@\x00") == 0 or
        class_add_method(probe_view_class, selector_register("insertText:replacementRange:"), @ptrCast(&insertTextWithRange), "v@:@{_NSRange=QQ}\x00") == 0 or
        class_add_method(probe_view_class, selector_register("mouseMoved:"), @ptrCast(&mouseMoved), "v@:@\x00") == 0 or
        class_add_method(probe_view_class, selector_register("mouseDown:"), @ptrCast(&leftMouseDown), "v@:@\x00") == 0 or
        class_add_method(probe_view_class, selector_register("mouseUp:"), @ptrCast(&leftMouseUp), "v@:@\x00") == 0 or
        class_add_method(probe_view_class, selector_register("mouseDragged:"), @ptrCast(&leftMouseDragged), "v@:@\x00") == 0 or
        class_add_method(probe_view_class, selector_register("rightMouseDown:"), @ptrCast(&rightMouseDown), "v@:@\x00") == 0 or
        class_add_method(probe_view_class, selector_register("rightMouseUp:"), @ptrCast(&rightMouseUp), "v@:@\x00") == 0 or
        class_add_method(probe_view_class, selector_register("rightMouseDragged:"), @ptrCast(&rightMouseDragged), "v@:@\x00") == 0 or
        class_add_method(probe_view_class, selector_register("otherMouseDown:"), @ptrCast(&otherMouseDown), "v@:@\x00") == 0 or
        class_add_method(probe_view_class, selector_register("otherMouseUp:"), @ptrCast(&otherMouseUp), "v@:@\x00") == 0 or
        class_add_method(probe_view_class, selector_register("otherMouseDragged:"), @ptrCast(&otherMouseDragged), "v@:@\x00") == 0 or
        class_add_method(probe_view_class, selector_register("scrollWheel:"), @ptrCast(&scrollWheel), "v@:@\x00") == 0) return error.ObjcMethodRegistrationFailed;
    const text_input_protocol = get_protocol("NSTextInputClient\x00") orelse return error.ObjcProtocolUnavailable;
    if (class_conforms_to_protocol(probe_view_class, text_input_protocol) == 0 and class_add_protocol(probe_view_class, text_input_protocol) == 0) return error.ObjcProtocolRegistrationFailed;
    register_class(probe_view_class);
    const view_alloc = send_id0(probe_view_class, selector_register("alloc")) orelse return error.AppKitInitializationFailed;
    const view = send_view(view_alloc, selector_register("initWithFrame:"), .{ .origin = .{ .x = 0, .y = 0 }, .size = .{ .width = 640, .height = 480 } }) orelse return error.AppKitInitializationFailed;
    active_view = view;

    const window_class = get_class("NSWindow") orelse return error.AppKitClassUnavailable;
    const allocated_window = send_id0(window_class, selector_register("alloc")) orelse return error.AppKitInitializationFailed;
    const window = send_window(allocated_window, selector_register("initWithContentRect:styleMask:backing:defer:"), .{ .origin = .{ .x = 120, .y = 120 }, .size = .{ .width = 640, .height = 480 } }, 15, 2, 0) orelse return error.AppKitInitializationFailed;
    active_window = window;
    const string_class = get_class("NSString") orelse return error.AppKitClassUnavailable;
    const title = (objc.lookup(SendString, "objc_msgSend") orelse return error.ObjcRuntimeUnavailable)(string_class, selector_register("stringWithUTF8String:"), "FORTH/Sigma graphics\x00") orelse return error.AppKitInitializationFailed;
    _ = send_id1(window, selector_register("setTitle:"), title);
    _ = send_id1(window, selector_register("setDelegate:"), delegate);
    // The window may become a fullscreen Space (NSWindowCollectionBehaviorFullScreenPrimary).
    send_void1(window, selector_register("setCollectionBehavior:"), @ptrFromInt(1 << 7));
    _ = send_id1(window, selector_register("setContentView:"), view);
    _ = send_id1(app, selector_register("setDelegate:"), delegate);
    _ = send_bool1(view, selector_register("setNeedsDisplay:"), 1);
    _ = send_id1(window, selector_register("makeKeyAndOrderFront:"), null);
    _ = send_id1(window, selector_register("makeFirstResponder:"), view);
    _ = send_bool1(window, selector_register("setAcceptsMouseMovedEvents:"), 1);

    var reader = try std.Thread.spawn(.{}, readParentCommands, .{});
    reader.detach();
    send_void0.?(app, selector_register("run"));
    if (!did_draw) return error.AppKitDrawNotCalled;
    if (!did_close) _ = send_id1(window, selector_register("close"), null);
    if (!did_close) return error.AppKitCloseDelegateNotCalled;

    output("EXIT 0\n");
    return 0;
}

/// Standalone entry point for the prototype driver; Sigma calls runChild only for its
/// private child mode.
pub fn main() !void {
    _ = try runChild();
}

test "macOS window size reports count opening, size, scale, and closing" {
    var state: WindowSize = .{};
    var fields = std.mem.tokenizeScalar(u8, "640 480 1", ' ');
    state.accept(&fields);
    try std.testing.expectEqual([2]u32{ 640, 480 }, state.size);
    try std.testing.expectEqual(@as(u64, 1), state.changes); // the window came
    fields = std.mem.tokenizeScalar(u8, "640 480 0", ' ');
    state.accept(&fields);
    try std.testing.expectEqual(@as(u64, 1), state.changes); // same size, not counted
    fields = std.mem.tokenizeScalar(u8, "800 600 0", ' ');
    state.accept(&fields);
    try std.testing.expectEqual(@as(u64, 2), state.changes);
    fields = std.mem.tokenizeScalar(u8, "800 600 1", ' ');
    state.accept(&fields);
    try std.testing.expectEqual(@as(u64, 3), state.changes); // scale, screen, or displays
    for ([_][]const u8{ "800", "800 600", "800 600 2", "800 600 0 9", "-1 600 0", "1048577 600 0", "x 600 0" }) |bad| {
        fields = std.mem.tokenizeScalar(u8, bad, ' ');
        state.accept(&fields);
    }
    try std.testing.expectEqual([2]u32{ 800, 600 }, state.size);
    try std.testing.expectEqual(@as(u64, 3), state.changes);
    state.gone();
    try std.testing.expectEqual([2]u32{ 0, 0 }, state.size);
    try std.testing.expectEqual(@as(u64, 4), state.changes);
    state.gone(); // CLOSED and the reaping both say so: counted once
    try std.testing.expectEqual(@as(u64, 4), state.changes);
    state.report(800, 600, false);
    try std.testing.expectEqual(@as(u64, 5), state.changes); // opened again
}

test "macOS window state lines tell focus and minimizing, and the window going clears them" {
    var state: WindowSize = .{};
    var fields = std.mem.tokenizeScalar(u8, "1 0", ' ');
    state.acceptState(&fields);
    try std.testing.expect(state.focused and !state.minimized);
    fields = std.mem.tokenizeScalar(u8, "0 1", ' ');
    state.acceptState(&fields);
    try std.testing.expect(!state.focused and state.minimized);
    for ([_][]const u8{ "1", "1 0 0", "2 0", "1 x", "" }) |bad| {
        fields = std.mem.tokenizeScalar(u8, bad, ' ');
        state.acceptState(&fields);
    }
    try std.testing.expect(!state.focused and state.minimized);
    state.report(640, 480, true);
    state.closes = 2;
    state.gone();
    try std.testing.expect(!state.focused and !state.minimized and !state.open);
    try std.testing.expectEqual(@as(u64, 2), state.closes); // the count stays
}

test "macOS PAINTED sequences give the place in the count of images shown" {
    const saved = .{ frames_shown, frames_painted, last_accepted_sequence };
    defer {
        frames_shown = saved[0];
        frames_painted = saved[1];
        last_accepted_sequence = saved[2];
    }
    // Five images accepted, FRAME sequences 11 to 15 (sequences 1 to 10 went to a child
    // that failed).
    frames_shown = 5;
    frames_painted = 0;
    last_accepted_sequence = 15;
    enqueueInputLine("INPUT PAINTED 13");
    try std.testing.expectEqual(@as(u64, 3), frames_painted);
    enqueueInputLine("INPUT PAINTED 12"); // older: the place does not go back
    try std.testing.expectEqual(@as(u64, 3), frames_painted);
    for ([_][]const u8{ "INPUT PAINTED 16", "INPUT PAINTED 0", "INPUT PAINTED 10", "INPUT PAINTED x", "INPUT PAINTED 15 1" }) |bad| enqueueInputLine(bad);
    try std.testing.expectEqual(@as(u64, 3), frames_painted);
    enqueueInputLine("INPUT PAINTED 15");
    try std.testing.expectEqual(@as(u64, 5), frames_painted);
}

test "macOS close requests count, and reading WINDOW-CLOSES takes one kept open as read" {
    const saved_size = window_size;
    const saved_pending = close_pending;
    defer {
        window_size = saved_size;
        close_pending = saved_pending;
    }
    window_size = .{};
    close_pending = false;
    enqueueInputLine("INPUT CLOSE-ASKED 1"); // kept open
    try std.testing.expectEqual(@as(u64, 1), window_size.closes);
    try std.testing.expect(close_pending);
    try std.testing.expectEqual(@as(u64, 1), windowClose(3)); // read: no longer pending
    try std.testing.expect(!close_pending);
    enqueueInputLine("INPUT CLOSE-ASKED 0"); // closed
    try std.testing.expectEqual(@as(u64, 2), window_size.closes);
    try std.testing.expect(!close_pending);
    for ([_][]const u8{ "INPUT CLOSE-ASKED", "INPUT CLOSE-ASKED 2", "INPUT CLOSE-ASKED 1 1" }) |bad| enqueueInputLine(bad);
    try std.testing.expectEqual(@as(u64, 2), window_size.closes);
}
