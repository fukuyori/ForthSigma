//! The displays of the machine, as DISPLAYS took them last (tque 1038): the host fills a
//! Snapshot, the core keeps the last one, and the DISPLAY- words read it. The state is
//! of this run only: it is not part of a dictionary image.
//!
//! All places and sizes are in physical pixels of the desktop, whose origin is the top
//! left corner of the primary display; a display to the left of it or above it has
//! negative coordinates. A value the host cannot tell is a fraction with denominator 0;
//! a host that cannot tell the displays at all gives none (DISPLAYS is 0).

const memory_map = @import("memory_map.zig");
const Cell = memory_map.Cell;

/// At most this many displays are kept; a host with more gives the first ones.
pub const max_displays = 16;

pub const Display = struct {
    /// The host's own name for the display, to find the one a window is on; it is not
    /// given to the program, and it may name another display after the displays change.
    id: u64 = 0,
    /// x y w h of the whole display.
    rect: [4]i32 = @splat(0),
    /// x y w h of the part an ordinary window may cover (without a task bar or a menu bar).
    work: [4]i32 = @splat(0),
    /// The scale of the display as a fraction (3/2 for 150%); denominator 0 when unknown.
    scale: [2]u32 = .{ 0, 0 },
    /// The refresh rate in Hz as a fraction (60000/1001 for 59.94); denominator 0 when unknown.
    hz: [2]u32 = .{ 0, 0 },
    primary: bool = false,
};

pub const Snapshot = struct {
    count: usize = 0,
    items: [max_displays]Display = @splat(.{}),

    /// Adds a display, unless the snapshot is full.
    pub fn add(snapshot: *Snapshot, display: Display) void {
        if (snapshot.count == max_displays) return;
        snapshot.items[snapshot.count] = display;
        snapshot.count += 1;
    }

    /// The number of the primary display, or -1 when there is none.
    pub fn primary(snapshot: *const Snapshot) Cell {
        for (snapshot.items[0..snapshot.count], 0..) |display, index| {
            if (display.primary) return @intCast(index);
        }
        return -1;
    }

    /// The number of the display with the host's name `id`, or -1.
    pub fn find(snapshot: *const Snapshot, id: u64) Cell {
        for (snapshot.items[0..snapshot.count], 0..) |display, index| {
            if (display.id == id) return @intCast(index);
        }
        return -1;
    }
};

/// The host's own window as it is now, for WINDOW-PIXELS and WINDOW-CHANGES (tque 1041):
/// the size of the part it can draw in, in physical pixels (0 0 without a window), and a
/// count that goes up each time that size, the window's scale, the display it is on, or
/// the displays themselves change. The count never goes down in a run.
///
/// For WINDOW-OPEN?, WINDOW-FOCUSED?, WINDOW-MINIMIZED?, and WINDOW-CLOSES (tque 1042):
/// whether there is such a window, whether it has the keyboard, whether it is minimized,
/// and how many times the user closed it (not the program) in this run.
pub const WindowState = struct {
    width: u32 = 0,
    height: u32 = 0,
    changes: u64 = 0,
    /// WINDOW-IMAGE-RECT (tque 1040): x y w h of the rectangle of the drawable part in which
    /// the image is shown now, as WINDOW-FIT lays it out; all 0 without a window or
    /// before an image is shown.
    view: [4]u32 = .{ 0, 0, 0, 0 },
    /// WINDOW-FRAMES (tque 1043): the images SHOW gave the window in this run, and the
    /// number of them the window had been given when it last drew. Images given faster
    /// than the window draws are not drawn one by one: only the latest is.
    frames_shown: u64 = 0,
    frames_painted: u64 = 0,
    open: bool = false,
    focused: bool = false,
    minimized: bool = false,
    closes: u64 = 0,
};

/// The fields GFX-DISPLAY-INFO gives, by number: 0 to 3 the display's x y w h, 4 to 7 the
/// work area's, 8 and 9 the scale's numerator and denominator, 10 and 11 the refresh
/// rate's, 12 whether it is the primary display (-1 or 0).
pub const field_count = 13;

pub fn field(display: Display, number: usize) Cell {
    return switch (number) {
        0...3 => display.rect[number],
        4...7 => display.work[number - 4],
        8, 9 => display.scale[number - 8],
        10, 11 => display.hz[number - 10],
        else => if (display.primary) -1 else 0,
    };
}
