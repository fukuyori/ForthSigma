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
    keys: [64]u32 = undefined,
    key_head: usize = 0,
    key_count: usize = 0,
    /// The pixel of the image under the mouse when it last moved, -1 -1 before that or
    /// when the image's place on the terminal is not known, and the buttons held.
    mouse_x: Cell = -1,
    mouse_y: Cell = -1,
    mouse_buttons: Cell = 0,
    /// The buttons that the terminal's reports said were pressed and not yet released.
    terminal_buttons: u8 = 0,
    /// Whether MOUSE-ON asked the terminal for mouse reports.
    mouse_on: bool = false,
    shown: ?Shown = null,
};

/// What a complete sequence of bytes from the terminal stands for.
const Decoded = union(enum) {
    key: u32,
    mouse: struct { column: i32, row: i32, buttons: u8 },
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
        return .{ .mouse = .{ .column = column - 1, .row = row - 1, .buttons = buttons.* } };
    }
    if (final == '~') return if (tildeKey(parameters(parameter_bytes)[0])) |key| .{ .key = key } else .nothing;
    return if (letterKey(final)) |key| .{ .key = key } else .nothing;
}

fn pushKey(input: *InputState, key: u32) void {
    if (input.key_count == input.keys.len) return;
    input.keys[(input.key_head + input.key_count) % input.keys.len] = key;
    input.key_count += 1;
}

fn popKey(input: *InputState) ?u32 {
    if (input.key_count == 0) return null;
    const key = input.keys[input.key_head];
    input.key_head = (input.key_head + 1) % input.keys.len;
    input.key_count -= 1;
    return key;
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
            if (key == interrupt_byte) return error.UserInterrupt;
            pushKey(input, key);
        },
        .mouse => |mouse| {
            input.mouse_buttons = mouse.buttons;
            const shown = input.shown orelse {
                input.mouse_x = -1;
                input.mouse_y = -1;
                return;
            };
            const position = terminalPixel(shown, mouse.column, mouse.row) orelse [2]Cell{ -1, -1 };
            input.mouse_x = position[0];
            input.mouse_y = position[1];
        },
        .nothing => {},
    }
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
    const input_fn = self.writer.input_fn orelse return;
    while (!(until_key and input.key_count != 0)) {
        const event = input_fn(self.writer.context) orelse break;
        switch (event) {
            .byte => |byte| {
                if (input.pending_len == 0) input.pending_since = now(self) orelse 0;
                input.pending[input.pending_len] = byte;
                input.pending_len += 1;
                try decodePending(self, false);
            },
            .restarted => {
                input.key_count = 0;
                input.key_head = 0;
                input.pending_len = 0;
                input.terminal_buttons = 0;
                input.mouse_buttons = 0;
            },
            .key => |key| try apply(self, .{ .key = key }),
            .terminal_mouse => |mouse| try apply(self, .{ .mouse = .{ .column = mouse.column, .row = mouse.row, .buttons = mouse.buttons } }),
            .window_mouse => |mouse| {
                input.mouse_x = mouse.x;
                input.mouse_y = mouse.y;
                input.mouse_buttons = mouse.buttons;
            },
        }
    }
    // A sequence not ended yet waits for its other bytes, for a while.
    if (input.pending_len != 0) {
        const time = now(self);
        const expired = time == null or time.? - input.pending_since >= sequence_wait_us or time.? < input.pending_since;
        try decodePending(self, expired);
    }
}

/// INKEY: the next key without waiting, or -1 when none has been pressed.
pub fn inkey(self: *State) RuntimeError!Cell {
    if (popKey(&self.gfx_input)) |key| return key;
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
