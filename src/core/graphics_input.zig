//! Keys and the mouse for the graphics words (INKEY, MOUSE). The host gives what the
//! user did without waiting: bytes from a terminal, which this file decodes (keys sent
//! as escape sequences and the terminal's mouse reports in the SGR form), or keys and
//! mouse positions that a Windows console or a window gave already decoded. The mouse
//! on the terminal is turned into a pixel of the image from where SHOW put the image.

const std = @import("std");
const defs = @import("defs.zig");
const forth = @import("../forth.zig");
const host_interface = @import("host_interface.zig");
const Cell = forth.Cell;
const RuntimeError = defs.RuntimeError;
const State = forth.State;
const InputEvent = host_interface.InputEvent;

/// The codes INKEY gives for keys that are not characters; a character key gives its
/// byte (each byte of a UTF-8 character in turn), Enter 13, Backspace 8, Esc 27.
pub const key_up = 256;
pub const key_down = 257;
pub const key_left = 258;
pub const key_right = 259;
pub const key_home = 260;
pub const key_end = 261;
pub const key_prior = 262;
pub const key_next = 263;
pub const key_insert = 264;
pub const key_delete = 265;
/// F1 to F12 are key_f1 to key_f1 + 11.
pub const key_f1 = 266;

/// The byte of Ctrl+C, which INKEY and MOUSE throw as USER INTERRUPT.
const interrupt_byte = 3;

/// Where the terminal shows the image that SHOW wrote there last.
pub const Shown = struct {
    /// State.output_count right after the image: a SHOW with nothing written since
    /// draws over it.
    output_mark: u64,
    /// The character rows the image takes.
    rows: u32,
    /// The screen row of the image's first row, when the host could tell.
    top: ?i32,
    /// The size of the image, and of the picture of it on the terminal, in pixels.
    width: u32,
    height: u32,
    out_width: u32,
    out_height: u32,
    /// The pixels of the picture in one character cell: 1 × 2 for half blocks.
    cell_width: u32,
    cell_height: u32,
};

pub const InputState = struct {
    /// The bytes of an escape sequence that has not come whole yet, and when its first
    /// byte came (UTIME's microseconds).
    pending: [32]u8 = undefined,
    pending_len: usize = 0,
    pending_since: forth.Double = 0,
    /// Keys read but not yet taken by INKEY: MOUSE reads past them.
    keys: [64]Key = undefined,
    key_head: usize = 0,
    key_count: usize = 0,
    /// The pixel of the image under the mouse when it last moved, -1 -1 before that or
    /// when the image's place on the terminal is not known, and the buttons held.
    mouse_x: Cell = -1,
    mouse_y: Cell = -1,
    mouse_buttons: Cell = 0,
    /// The buttons that the terminal's reports said were pressed and not yet released,
    /// and whether the terminal (not a window) moved the mouse last.
    terminal_buttons: u8 = 0,
    mouse_from_terminal: bool = false,
    /// Whether MOUSE-ON asked the terminal for mouse reports.
    mouse_on: bool = false,
    shown: ?Shown = null,
    /// The keys KEY-HELD? holds, the most recently pressed last.
    held: [16]Held = undefined,
    held_count: usize = 0,
    /// Presses, releases, and turns of the wheel not yet read by MOUSE-EVENT, the oldest
    /// at `mouse_head`; when it is full, the oldest is dropped. `event_buttons` are the
    /// buttons the events of the terminal (0) and of a window (1) have told so far.
    mouse_events: [mouse_event_capacity]MouseEvent = undefined,
    mouse_head: usize = 0,
    mouse_count: usize = 0,
    event_buttons: [2]u8 = .{ 0, 0 },
};

pub const mouse_event_capacity = 64;

/// What MOUSE-EVENT gives: the pixel of the image under the mouse, the button (1 left, 2
/// right, 4 middle; for the wheel 1 up, -1 down), and the kind.
pub const MouseEvent = struct { x: Cell, y: Cell, button: Cell, kind: MouseEventKind };

pub const MouseEventKind = enum(u8) { press = 1, release = 2, wheel = 3 };

fn pushMouseEvent(input: *InputState, event: MouseEvent) void {
    if (input.mouse_count == input.mouse_events.len) {
        input.mouse_head = (input.mouse_head + 1) % input.mouse_events.len;
        input.mouse_count -= 1;
    }
    input.mouse_events[(input.mouse_head + input.mouse_count) % input.mouse_events.len] = event;
    input.mouse_count += 1;
}

/// The events of a report of the mouse from the terminal (source 0) or a window (1):
/// a press or a release for each button that changed since its last report, then the
/// wheel.
fn mouseEvents(input: *InputState, source: usize, x: Cell, y: Cell, buttons: u8, wheel: i8) void {
    const before = input.event_buttons[source];
    inline for (.{ 1, 2, 4 }) |bit| {
        if ((buttons ^ before) & bit != 0) {
            pushMouseEvent(input, .{ .x = x, .y = y, .button = bit, .kind = if (buttons & bit != 0) .press else .release });
        }
    }
    input.event_buttons[source] = buttons;
    if (wheel != 0) pushMouseEvent(input, .{ .x = x, .y = y, .button = wheel, .kind = .wheel });
}

/// MOUSE-EVENT: reads what the host has (keys wait for INKEY) and gives the oldest event
/// of the mouse not yet read, or null.
pub fn nextMouseEvent(self: *State) RuntimeError!?MouseEvent {
    try readInput(self, false);
    const input = &self.gfx_input;
    if (input.mouse_count == 0) return null;
    const event = input.mouse_events[input.mouse_head];
    input.mouse_head = (input.mouse_head + 1) % input.mouse_events.len;
    input.mouse_count -= 1;
    return event;
}

/// A key that is held: until its host tells it was released (`until` null: a Windows
/// console, a window, the Tk window), or, as a terminal does not tell, until a while
/// after it was last pressed (the terminal repeats a key held down). Its source is
/// forgotten whole when it can no longer tell: the terminal restarting, the Tcl program
/// stopping.
const Held = struct { code: u32, source: KeySource, until: ?forth.Double, pressed: forth.Double };

pub const KeySource = enum { terminal, window, tk };

/// How long a key from a terminal counts as held after it was pressed: longer than
/// most terminals wait before they repeat a key (about 0.5 s).
pub const terminal_hold_us = 600_000;

/// A key from a terminal that comes again this soon is being repeated, and counts as held
/// only this long: repeats come much faster than this, and the key stops soon after it is
/// released.
pub const terminal_repeat_us = 120_000;

/// What a complete sequence of bytes from the terminal stands for.
const Decoded = union(enum) {
    key: u32,
    mouse: struct { column: i32, row: i32, buttons: u8, wheel: i8 = 0 },
    /// A sequence that stands for nothing INKEY gives (it is dropped).
    nothing,
};

const Parse = union(enum) {
    /// More bytes are needed.
    incomplete,
    done: struct { length: usize, decoded: Decoded },
};

/// The byte a key gives, as the other systems give it: Enter gives 13 also where the
/// terminal sends LF, and Backspace 8 also where it sends DEL.
fn keyByte(byte: u8) u32 {
    return switch (byte) {
        '\n' => 13,
        127 => 8,
        else => byte,
    };
}

fn letterKey(letter: u8) ?u32 {
    return switch (letter) {
        'A' => key_up,
        'B' => key_down,
        'C' => key_right,
        'D' => key_left,
        'H' => key_home,
        'F' => key_end,
        'P', 'Q', 'R', 'S' => key_f1 + @as(u32, letter - 'P'),
        else => null,
    };
}

/// The key of `ESC [ n ~`.
fn tildeKey(number: u32) ?u32 {
    return switch (number) {
        1, 7 => key_home,
        2 => key_insert,
        3 => key_delete,
        4, 8 => key_end,
        5 => key_prior,
        6 => key_next,
        11...15 => key_f1 + (number - 11),
        17...21 => key_f1 + 5 + (number - 17),
        23, 24 => key_f1 + 10 + (number - 23),
        else => null,
    };
}

/// The numbers separated by ';' in the parameters of a control sequence (at most
/// three are kept); a missing number is 0.
fn parameters(bytes: []const u8) [3]u32 {
    var numbers: [3]u32 = @splat(0);
    var index: usize = 0;
    for (bytes) |byte| {
        if (byte == ';') {
            index += 1;
            if (index == numbers.len) break;
        } else if (byte >= '0' and byte <= '9') {
            numbers[index] = numbers[index] *| 10 +| (byte - '0');
        }
    }
    return numbers;
}

/// Decodes the bytes at the start of `bytes`: a key, an escape sequence, or a mouse
/// report. `buttons` are those held before an SGR mouse report, which it changes.
fn parse(bytes: []const u8, buttons: *u8) Parse {
    if (bytes[0] != 0x1b) return .{ .done = .{ .length = 1, .decoded = .{ .key = keyByte(bytes[0]) } } };
    if (bytes.len < 2) return .incomplete;
    switch (bytes[1]) {
        'O' => {
            if (bytes.len < 3) return .incomplete;
            const decoded: Decoded = if (letterKey(bytes[2])) |key| .{ .key = key } else .nothing;
            return .{ .done = .{ .length = 3, .decoded = decoded } };
        },
        '[' => {
            var index: usize = 2;
            while (index < bytes.len) : (index += 1) {
                const byte = bytes[index];
                if (byte >= 0x40 and byte <= 0x7e) break;
                // Not a byte of a control sequence: what came so far is dropped.
                if (byte < 0x20 or byte > 0x3f) return .{ .done = .{ .length = index, .decoded = .nothing } };
            } else return .incomplete;
            const final = bytes[index];
            const parameter_bytes = bytes[2..index];
            return .{ .done = .{ .length = index + 1, .decoded = controlSequence(parameter_bytes, final, buttons) } };
        },
        // Esc alone, followed by another key.
        else => return .{ .done = .{ .length = 1, .decoded = .{ .key = 27 } } },
    }
}

fn controlSequence(parameter_bytes: []const u8, final: u8, buttons: *u8) Decoded {
    if (parameter_bytes.len != 0 and parameter_bytes[0] == '<') {
        // ESC [ < b ; column ; row M (pressed or moved) or m (released).
        if (final != 'M' and final != 'm') return .nothing;
        const numbers = parameters(parameter_bytes[1..]);
        const code = numbers[0];
        // 0 left, 1 middle, 2 right; 64 and up are the wheel, which changes no button.
        const bit: u8 = switch (code & 3) {
            0 => 1,
            1 => 4,
            2 => 2,
            else => 0,
        };
        if (code & 64 == 0 and code & 32 == 0) {
            if (final == 'M') buttons.* |= bit else buttons.* &= ~bit;
        } else if (code & 64 == 0 and code & 3 == 3) {
            // Moved with no button held.
            buttons.* = 0;
        }
        const column: i32 = @intCast(@min(numbers[1], 1 << 20));
        const row: i32 = @intCast(@min(numbers[2], 1 << 20));
        // The wheel: 64 up, 65 down (66 and 67, sideways, are not told), when pressed.
        const wheel: i8 = if (code & 64 == 0 or final != 'M') 0 else switch (code & 3) {
            0 => 1,
            1 => -1,
            else => 0,
        };
        return .{ .mouse = .{ .column = column - 1, .row = row - 1, .buttons = buttons.*, .wheel = wheel } };
    }
    if (final == '~') return if (tildeKey(parameters(parameter_bytes)[0])) |key| .{ .key = key } else .nothing;
    return if (letterKey(final)) |key| .{ .key = key } else .nothing;
}

/// A key waiting for INKEY, and whether it came from the terminal (whose keys are
/// dropped when it gives single keys again) or from a window.
const Key = struct { code: u32, from_terminal: bool };

fn pushKey(input: *InputState, key: Key) void {
    if (input.key_count == input.keys.len) return;
    input.keys[(input.key_head + input.key_count) % input.keys.len] = key;
    input.key_count += 1;
}

fn popKey(input: *InputState) ?u32 {
    if (input.key_count == 0) return null;
    const key = input.keys[input.key_head];
    input.key_head = (input.key_head + 1) % input.keys.len;
    input.key_count -= 1;
    return key.code;
}

/// The terminal gives single keys again after its line input: what was kept of its
/// input is dropped; the keys and the mouse of a window stay.
fn restart(input: *InputState) void {
    var kept: usize = 0;
    for (0..input.key_count) |index| {
        const key = input.keys[(input.key_head + index) % input.keys.len];
        if (key.from_terminal) continue;
        input.keys[(input.key_head + kept) % input.keys.len] = key;
        kept += 1;
    }
    input.key_count = kept;
    input.pending_len = 0;
    input.terminal_buttons = 0;
    if (input.mouse_from_terminal) input.mouse_buttons = 0;
    // Its next report starts again from no button; the events read so far stay.
    input.event_buttons[0] = 0;
    // Keys released while the terminal had its line input were not seen.
    forgetSource(input, .terminal);
}

/// Forgets the keys held from a source that will not tell their release.
fn forgetSource(input: *InputState, source: KeySource) void {
    var kept: usize = 0;
    for (input.held[0..input.held_count]) |held| {
        if (held.source == source) continue;
        input.held[kept] = held;
        kept += 1;
    }
    input.held_count = kept;
}

/// The Tcl program stopped, or a message of it was dropped: the Tk window's keys.
pub fn forgetTkKeys(self: *State) void {
    forgetSource(&self.gfx_input, .tk);
}

/// The keys KEY-HELD? can tell: those of one byte (ASCII) and the keys from 256 up.
fn holdable(code: u32) bool {
    return code < 0x80 or (code >= key_up and code <= key_f1 + 11);
}

fn isDirection(code: u32) bool {
    return code >= key_up and code <= key_right;
}

fn forgetOtherDirections(input: *InputState, source: KeySource, code: u32) void {
    var index = input.held_count;
    while (index != 0) {
        index -= 1;
        const held = input.held[index];
        if (held.source == source and isDirection(held.code) and held.code != code) forget(input, index);
    }
}

fn forget(input: *InputState, index: usize) void {
    std.mem.copyForwards(Held, input.held[index .. input.held_count - 1], input.held[index + 1 .. input.held_count]);
    input.held_count -= 1;
}

/// A key was pressed: `released` when its host tells when it is released.
fn press(self: *State, code: u32, source: KeySource, released: bool) void {
    if (!holdable(code)) return;
    const input = &self.gfx_input;
    const time = now(self) orelse 0;
    // A terminal repeats only the key pressed last: a new direction takes over from the
    // one before it, which would otherwise count as held for a while and could win.
    if (!released and isDirection(code)) forgetOtherDirections(input, source, code);
    var repeating = false;
    for (input.held[0..input.held_count], 0..) |held, index| {
        if (held.code == code and held.source == source) {
            repeating = time >= held.pressed and time - held.pressed <= terminal_repeat_us;
            forget(input, index);
            break;
        }
    }
    const until: ?forth.Double = if (released) null else time + @as(forth.Double, if (repeating) terminal_repeat_us else terminal_hold_us);
    // With all taken, the key pressed longest ago gives way.
    if (input.held_count == input.held.len) forget(input, 0);
    input.held[input.held_count] = .{ .code = code, .source = source, .until = until, .pressed = time };
    input.held_count += 1;
}

fn release(input: *InputState, code: u32, source: KeySource) void {
    for (input.held[0..input.held_count], 0..) |held, index| {
        if (held.code == code and held.source == source) return forget(input, index);
    }
}

/// The pixel of the image under a character cell of the terminal, from where SHOW put
/// the image: the middle of the cell.
fn terminalPixel(shown: Shown, column: i32, row: i32) ?[2]Cell {
    const top = shown.top orelse return null;
    const twice_x = (2 * @as(i64, column) + 1) * shown.cell_width;
    const twice_y = (2 * (@as(i64, row) - top) + 1) * shown.cell_height;
    return .{
        @divFloor(twice_x * shown.width, 2 * @as(i64, shown.out_width)),
        @divFloor(twice_y * shown.height, 2 * @as(i64, shown.out_height)),
    };
}

fn apply(self: *State, decoded: Decoded) RuntimeError!void {
    const input = &self.gfx_input;
    switch (decoded) {
        .key => |key| {
            try addKey(self, key, true);
            press(self, key, .terminal, false);
        },
        .mouse => |mouse| {
            input.mouse_buttons = mouse.buttons;
            input.mouse_from_terminal = true;
            const shown = input.shown orelse {
                input.mouse_x = -1;
                input.mouse_y = -1;
                mouseEvents(input, 0, -1, -1, mouse.buttons, mouse.wheel);
                return;
            };
            const position = terminalPixel(shown, mouse.column, mouse.row) orelse [2]Cell{ -1, -1 };
            input.mouse_x = position[0];
            input.mouse_y = position[1];
            mouseEvents(input, 0, position[0], position[1], mouse.buttons, mouse.wheel);
        },
        .nothing => {},
    }
}

fn addKey(self: *State, key: u32, from_terminal: bool) RuntimeError!void {
    if (key == interrupt_byte) return error.UserInterrupt;
    pushKey(&self.gfx_input, .{ .code = key, .from_terminal = from_terminal });
}

/// Whether a sequence not ended has waited its time for the rest of its bytes.
fn pendingExpired(self: *State) bool {
    const input = &self.gfx_input;
    const time = now(self) orelse return true;
    return time - input.pending_since >= sequence_wait_us or time < input.pending_since;
}

/// Decodes the pending bytes; with `flush`, a sequence that has not come whole is taken
/// as the keys of its bytes, as when Esc was pressed alone.
fn decodePending(self: *State, flush: bool) RuntimeError!void {
    const input = &self.gfx_input;
    while (input.pending_len != 0) {
        const bytes = input.pending[0..input.pending_len];
        var length: usize = 1;
        var decoded: Decoded = .{ .key = keyByte(bytes[0]) };
        switch (parse(bytes, &input.terminal_buttons)) {
            .incomplete => if (!flush and input.pending_len < input.pending.len) return,
            .done => |done| {
                length = done.length;
                decoded = done.decoded;
            },
        }
        std.mem.copyForwards(u8, input.pending[0 .. input.pending_len - length], input.pending[length..input.pending_len]);
        input.pending_len -= length;
        try apply(self, decoded);
    }
}

/// How long a sequence that has not ended waits for the rest of its bytes, which may
/// come apart (over a slow connection); then its bytes are keys, as Esc pressed alone.
const sequence_wait_us = 50_000;

fn now(self: *State) ?forth.Double {
    const utime_fn = self.writer.utime_fn orelse return null;
    return utime_fn(self.writer.context) catch null;
}

/// Reads what the host has without waiting, until a key is waiting for INKEY (when
/// `until_key`) or the host has nothing more. Keys beyond the queue's room are dropped,
/// but the mouse and Ctrl+C are still read.
fn readInput(self: *State, until_key: bool) RuntimeError!void {
    const input = &self.gfx_input;
    // The Tk window's keys and mouse come with the Tcl program's messages.
    if (defs.graphics_enabled) try @import("tcl.zig").poll(self);
    const input_fn = self.writer.input_fn orelse return;
    // At least one event is read, so that a restart of the terminal's single keys is
    // seen before INKEY gives a key it kept from before.
    var first = true;
    while (first or !(until_key and input.key_count != 0)) {
        first = false;
        const event = input_fn(self.writer.context) orelse break;
        switch (event) {
            .byte => |byte| {
                // A sequence that waited too long ends before the new byte.
                if (input.pending_len != 0 and pendingExpired(self)) try decodePending(self, true);
                if (input.pending_len == 0) input.pending_since = now(self) orelse 0;
                input.pending[input.pending_len] = byte;
                input.pending_len += 1;
                try decodePending(self, false);
            },
            .restarted => restart(input),
            .key => |key| {
                try addKey(self, key, true);
                press(self, key, .terminal, true);
            },
            .window_key => |key| try windowKey(self, key, .window),
            .key_release => |key| release(input, key, .terminal),
            .window_key_release => |key| release(input, key, .window),
            .terminal_mouse => |mouse| try apply(self, .{ .mouse = .{ .column = mouse.column, .row = mouse.row, .buttons = mouse.buttons, .wheel = mouse.wheel } }),
            .window_mouse => |mouse| windowMouse(self, mouse.x, mouse.y, mouse.buttons, mouse.wheel),
        }
    }
    // A sequence not ended yet waits for its other bytes, for a while.
    if (input.pending_len != 0) try decodePending(self, pendingExpired(self));
}

/// Reads what the host has without waiting, keeping the keys for INKEY: Ctrl+C throws
/// USER INTERRUPT (PLAY waiting for its queues).
pub fn readPending(self: *State) RuntimeError!void {
    try readInput(self, false);
}

/// A key pressed in a window: the host's, or one whose program sends it (the Tk window
/// of DISPLAY-TK). The window tells when it is released.
pub fn windowKey(self: *State, key: u32, source: KeySource) RuntimeError!void {
    try addKey(self, key, false);
    press(self, key, source, true);
}

/// A key released in such a window.
pub fn windowKeyRelease(self: *State, key: u32, source: KeySource) void {
    release(&self.gfx_input, key, source);
}

/// KEY-HELD?: whether the key (as INKEY gives it) is held down now. It reads what the
/// host has first; keys read meanwhile wait for INKEY.
pub fn keyHeld(self: *State, code: Cell) RuntimeError!bool {
    try readInput(self, false);
    const input = &self.gfx_input;
    for (input.held[0..input.held_count], 0..) |held, index| {
        if (code < 0 or held.code != code) continue;
        const until = held.until orelse return true;
        const time = now(self) orelse 0;
        // Past its time, or the clock went back.
        if (time < until and time + terminal_hold_us >= until) return true;
        forget(input, index);
        return false;
    }
    return false;
}

/// The mouse over such a window: the pixel of the image under it, the buttons, and the
/// wheel (1 a notch up, -1 down, 0 none).
pub fn windowMouse(self: *State, x: i32, y: i32, buttons: u8, wheel: i8) void {
    const input = &self.gfx_input;
    input.mouse_x = x;
    input.mouse_y = y;
    input.mouse_buttons = buttons;
    input.mouse_from_terminal = false;
    mouseEvents(input, 1, x, y, buttons, wheel);
}

/// INKEY: the next key without waiting, or -1 when none has been pressed.
pub fn inkey(self: *State) RuntimeError!Cell {
    try readInput(self, true);
    return if (popKey(&self.gfx_input)) |key| key else -1;
}

/// MOUSE: reads what the host has (keys wait for INKEY) and gives the mouse's pixel
/// and buttons.
pub fn mouseState(self: *State) RuntimeError![3]Cell {
    try readInput(self, false);
    const input = &self.gfx_input;
    return .{ input.mouse_x, input.mouse_y, input.mouse_buttons };
}

/// MOUSE-ON and MOUSE-OFF.
pub fn setMouse(self: *State, on: bool) void {
    self.gfx_input.mouse_on = on;
    if (self.writer.mouse_fn) |mouse_fn| mouse_fn(self.writer.context, on);
}
