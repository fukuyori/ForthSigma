//! TCL, TCL-EVAL, TCL-EVENT, and DISPLAY-TK: a Tcl/Tk interpreter (wish) that the host
//! runs as a program of its own, started the first time it is needed, which Sigma talks
//! to through the program's standard input and output (the protocol is described in
//! src/graphics/sigma_tk.tcl). No Tcl library is linked into Sigma.
//!
//! The strings Forth gets (a result, an error message, an event) are kept in the heap
//! of logical memory, each until the next of its kind comes.

const std = @import("std");
const defs = @import("defs.zig");
const forth = @import("../forth.zig");
const graphics_input = @import("graphics_input.zig");
const words_graphics = @import("words_graphics.zig");
const graphics_images = @import("graphics_images.zig");
const Cell = forth.Cell;
const RuntimeError = defs.RuntimeError;
const State = forth.State;

/// The script the host gives the program.
pub const script = @embedFile("../graphics/sigma_tk.tcl");

/// The longest message Sigma takes from the program, and sends to it: the largest image
/// in base64, as GFX-SHOW-TK sends it, with room for its command.
const max_message = (words_graphics.pngLength(words_graphics.max_side, words_graphics.max_side) + 2) / 3 * 4 + 64;
/// The events kept until TCL-EVENT takes them; later ones are dropped when it is full.
const max_events = 64;

const Text = struct { address: Cell = 0, length: usize = 0 };

pub const TclState = struct {
    running: bool = false,
    /// TCL-PROGRAM's program; empty for the host's choice.
    program: [256]u8 = undefined,
    program_length: usize = 0,
    /// Bytes read from the program and not yet taken.
    input: [4096]u8 = undefined,
    input_start: usize = 0,
    input_end: usize = 0,
    result: Text = .{},
    error_text: Text = .{},
    event: Text = .{},
    events: [max_events]Text = undefined,
    event_head: usize = 0,
    event_count: usize = 0,
    /// The message being read, which may come in pieces: the header so far, or the
    /// header read and the bytes of the text so far.
    header: [64]u8 = undefined,
    header_length: usize = 0,
    partial: ?Message = null,
    received: usize = 0,
    /// The bytes left of a message whose text was given up before it came whole (its
    /// strings freed before SAVE, or the heap replaced): they are read and dropped, so
    /// that the next message starts where it should.
    skip: usize = 0,
};

/// One message from the program: its kind (R, E, K, or M) and code, and its text in
/// the heap.
const Message = struct { kind: u8, code: i64, text: Text };

fn freeText(self: *State, text: *Text) void {
    if (text.address != 0) _ = self.heapFree(text.address) catch {};
    text.* = .{};
}

/// Forgets the strings in the heap without freeing them, when the heap is replaced (an
/// image is restored).
pub fn forgetHeap(self: *State) void {
    const tcl = &self.tcl;
    tcl.result = .{};
    tcl.error_text = .{};
    tcl.event = .{};
    tcl.event_count = 0;
    dropPartial(self, false);
}

/// Gives up the text of the message being read, freeing it if `free`, and keeps how
/// much of it is still to come.
fn dropPartial(self: *State, free: bool) void {
    const tcl = &self.tcl;
    if (tcl.partial) |*message| {
        // A release given up would leave its key held.
        if (message.kind == 'U') graphics_input.forgetTkKeys(self);
        tcl.skip += message.text.length - tcl.received;
        if (free) freeText(self, &message.text);
    }
    tcl.partial = null;
    tcl.received = 0;
}

/// Forgets all that was being read, when the program stops or starts.
fn resetReading(self: *State) void {
    const tcl = &self.tcl;
    dropPartial(self, true);
    tcl.skip = 0;
    tcl.header_length = 0;
    tcl.input_start = 0;
    tcl.input_end = 0;
}

/// Frees the strings in the heap before the dictionary is saved, so that the image does
/// not keep blocks nobody owns: a result, an error message, or an event read before
/// SAVE is not valid after it.
pub fn releaseHeap(self: *State) void {
    const tcl = &self.tcl;
    freeText(self, &tcl.result);
    freeText(self, &tcl.error_text);
    freeText(self, &tcl.event);
    while (tcl.event_count != 0) {
        freeText(self, &tcl.events[tcl.event_head]);
        tcl.event_head = (tcl.event_head + 1) % max_events;
        tcl.event_count -= 1;
    }
    // The program goes on: the rest of a message being read is dropped when it comes,
    // and a header read in part (not in the heap) is kept.
    dropPartial(self, true);
}

fn ensureRunning(self: *State) RuntimeError!void {
    const tcl = &self.tcl;
    if (tcl.running) return;
    const start = self.writer.process_start_fn orelse return error.HostUnavailable;
    try start(self.writer.context, tcl.program[0..tcl.program_length], script);
    tcl.running = true;
    resetReading(self);
}

/// Stops the program and drops what was being read from it. Returns whether the host
/// saw the program end.
fn halt(self: *State) bool {
    self.tcl.running = false;
    resetReading(self);
    graphics_input.forgetTkKeys(self);
    if (self.writer.process_stop_fn) |stop_fn| return stop_fn(self.writer.context);
    return true;
}

/// The program has ended, cannot be reached, or sent what the protocol does not allow:
/// HOST FUNCTION ERROR, and the next use starts it again.
fn lost(self: *State) RuntimeError {
    _ = halt(self);
    return error.HostFailed;
}

fn write(self: *State, bytes: []const u8) RuntimeError!void {
    const write_fn = self.writer.process_write_fn orelse return error.HostUnavailable;
    write_fn(self.writer.context, bytes) catch return lost(self);
}

/// The next byte the program wrote; null, when not waiting, if none has come.
fn readByte(self: *State, wait: bool) RuntimeError!?u8 {
    const tcl = &self.tcl;
    if (tcl.input_start == tcl.input_end) {
        const read_fn = self.writer.process_read_fn orelse return error.HostUnavailable;
        const count = read_fn(self.writer.context, &tcl.input, wait) catch return lost(self);
        if (count == 0) {
            if (wait) return lost(self);
            return null;
        }
        tcl.input_start = 0;
        tcl.input_end = count;
    }
    const byte = tcl.input[tcl.input_start];
    tcl.input_start += 1;
    return byte;
}

/// The kind, code, and text length of a header "<kind> <code> <length>": R with any
/// code (1 is an error), E, K, U, and M with 0. Anything else breaks the protocol.
fn parseHeader(header: []const u8) ?struct { kind: u8, code: i64, size: usize } {
    var fields = std.mem.splitScalar(u8, header, ' ');
    const kind = fields.next() orelse return null;
    const code = std.fmt.parseInt(i64, fields.next() orelse return null, 10) catch return null;
    const size = std.fmt.parseInt(usize, fields.next() orelse return null, 10) catch return null;
    if (fields.next() != null or kind.len != 1 or size > max_message) return null;
    switch (kind[0]) {
        'R' => {},
        'E', 'K', 'U', 'M' => if (code != 0) return null,
        else => return null,
    }
    return .{ .kind = kind[0], .code = code, .size = size };
}

/// Reads the next message. When not waiting, it takes what has come and gives null if
/// the message is not whole yet; the rest is read by a later call.
fn readMessage(self: *State, wait: bool) RuntimeError!?Message {
    const tcl = &self.tcl;
    while (tcl.skip != 0) {
        if (tcl.input_start == tcl.input_end) {
            _ = try readByte(self, wait) orelse return null;
            tcl.skip -= 1;
            continue;
        }
        const take = @min(tcl.skip, tcl.input_end - tcl.input_start);
        tcl.input_start += take;
        tcl.skip -= take;
    }
    while (tcl.partial == null) {
        const byte = try readByte(self, wait) orelse return null;
        if (byte != '\n') {
            if (tcl.header_length == tcl.header.len) return lost(self);
            tcl.header[tcl.header_length] = byte;
            tcl.header_length += 1;
            continue;
        }
        const header = parseHeader(tcl.header[0..tcl.header_length]) orelse return lost(self);
        tcl.header_length = 0;
        const address = try self.heapAllocate(@max(header.size, 1)) orelse {
            // No room for the text: the program is stopped, as its message cannot be
            // taken.
            _ = halt(self);
            return error.MemoryExhausted;
        };
        tcl.partial = .{ .kind = header.kind, .code = header.code, .text = .{ .address = address, .length = header.size } };
        tcl.received = 0;
    }
    const message = tcl.partial.?;
    const start: usize = @intCast(message.text.address);
    while (tcl.received < message.text.length) {
        const byte = try readByte(self, wait) orelse return null;
        self.memory[start + tcl.received] = byte;
        @import("address_registry.zig").written(self, @intCast(start + tcl.received), 1, false);
        tcl.received += 1;
    }
    tcl.partial = null;
    tcl.received = 0;
    return message;
}

/// Acts on a message that is not a result: keeps an event for TCL-EVENT, and gives keys
/// and the mouse of the Tk window to INKEY and MOUSE, and the keys released to KEY-HELD?.
fn dispatch(self: *State, message: Message) RuntimeError!void {
    var text = message.text;
    switch (message.kind) {
        'E' => {
            const tcl = &self.tcl;
            if (tcl.event_count == max_events) {
                freeText(self, &text);
                return;
            }
            tcl.events[(tcl.event_head + tcl.event_count) % max_events] = text;
            tcl.event_count += 1;
            return;
        },
        'K', 'U', 'M' => {
            defer freeText(self, &text);
            const start: usize = @intCast(text.address);
            var numbers = std.mem.tokenizeScalar(u8, self.memory[start..][0..text.length], ' ');
            if (message.kind == 'K' or message.kind == 'U') {
                while (numbers.next()) |field| {
                    const key = std.fmt.parseInt(u32, field, 10) catch continue;
                    if (message.kind == 'K') try graphics_input.windowKey(self, key, .tk) else graphics_input.windowKeyRelease(self, key, .tk);
                }
            } else {
                // x y buttons, and the wheel (1 up, -1 down) when it turned.
                var values: [4]i32 = .{ -1, -1, 0, 0 };
                for (&values) |*value| value.* = std.fmt.parseInt(i32, numbers.next() orelse "", 10) catch value.*;
                const wheel: i8 = if (values[3] > 0) 1 else if (values[3] < 0) -1 else 0;
                graphics_input.windowMouse(self, values[0], values[1], @intCast(values[2] & 7), wheel);
            }
        },
        else => freeText(self, &text),
    }
}

/// Reads the messages the program has sent, without waiting (INKEY, MOUSE, TCL-EVENT).
pub fn poll(self: *State) RuntimeError!void {
    if (!self.tcl.running) return;
    while (try readMessage(self, false)) |message| try dispatch(self, message);
}

/// Sends a script whose text `parts` gives (written in turn) and waits for its result.
/// Returns whether the script failed (Tcl's code 1); the result or the message is kept.
fn run(self: *State, parts: []const []const u8, length: usize, body: ?*const fn (*State) RuntimeError!void) RuntimeError!bool {
    try ensureRunning(self);
    // A script whose result cannot be taken (Ctrl+C from the Tk window, no memory for an
    // event) leaves its result to come: the program is stopped, so that the next
    // script does not take it for its own.
    errdefer if (self.tcl.running) {
        _ = halt(self);
    };
    var header: [24]u8 = undefined;
    try write(self, std.fmt.bufPrint(&header, "{d}\n", .{length}) catch unreachable);
    for (parts) |part| try write(self, part);
    if (body) |more| try more(self);
    while (true) {
        const message = try readMessage(self, true) orelse unreachable;
        if (message.kind != 'R') {
            try dispatch(self, message);
            continue;
        }
        const failed = message.code == 1;
        const slot = if (failed) &self.tcl.error_text else &self.tcl.result;
        freeText(self, slot);
        slot.* = message.text;
        return failed;
    }
}

/// GFX-TCL: runs a script; the result's text and whether it failed.
pub fn eval(self: *State, source: []const u8) RuntimeError![3]Cell {
    if (source.len > max_message) return error.StringTooLong;
    // The script is copied out of logical memory before the result may land there.
    const failed = try run(self, &.{source}, source.len, null);
    const text = if (failed) self.tcl.error_text else self.tcl.result;
    return .{ text.address, @intCast(text.length), if (failed) -1 else 0 };
}

/// GFX-TCL-ERROR: the message of the last script that failed.
pub fn errorText(self: *State) [2]Cell {
    return .{ self.tcl.error_text.address, @intCast(self.tcl.error_text.length) };
}

/// GFX-TCL-EVENT: the next event, as text, and true; or false.
pub fn nextEvent(self: *State) RuntimeError!?[2]Cell {
    try poll(self);
    const tcl = &self.tcl;
    freeText(self, &tcl.event);
    if (tcl.event_count == 0) return null;
    tcl.event = tcl.events[tcl.event_head];
    tcl.event_head = (tcl.event_head + 1) % max_events;
    tcl.event_count -= 1;
    return .{ tcl.event.address, @intCast(tcl.event.length) };
}

/// GFX-TCL-PROGRAM: the program the next start runs.
pub fn setProgram(self: *State, name: []const u8) RuntimeError!void {
    if (name.len > self.tcl.program.len) return error.StringTooLong;
    @memcpy(self.tcl.program[0..name.len], name);
    self.tcl.program_length = name.len;
}

/// GFX-TCL-STOP. HOST FUNCTION ERROR if the host could not see the program end; the
/// next use starts a new one all the same.
pub fn stop(self: *State) RuntimeError!void {
    if (!self.tcl.running) return;
    if (!halt(self)) return error.HostFailed;
}

/// Base64 of the PNG, written to the program in pieces.
const Base64Writer = struct {
    self: *State,
    pending: [3]u8 = undefined,
    pending_length: usize = 0,
    out: [4096]u8 = undefined,
    used: usize = 0,
    failure: ?RuntimeError = null,

    const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

    fn group(writer: *Base64Writer, data: []const u8) void {
        var value: u32 = 0;
        for (0..3) |index| value = value << 8 | (if (index < data.len) data[index] else 0);
        const chars = [4]u8{
            alphabet[value >> 18 & 63],
            alphabet[value >> 12 & 63],
            if (data.len > 1) alphabet[value >> 6 & 63] else '=',
            if (data.len > 2) alphabet[value & 63] else '=',
        };
        if (writer.used + 4 > writer.out.len) writer.flush();
        @memcpy(writer.out[writer.used..][0..4], &chars);
        writer.used += 4;
    }

    fn bytes(writer: *Base64Writer, data: []const u8) void {
        for (data) |byte| {
            writer.pending[writer.pending_length] = byte;
            writer.pending_length += 1;
            if (writer.pending_length == 3) {
                writer.group(&writer.pending);
                writer.pending_length = 0;
            }
        }
    }

    fn finish(writer: *Base64Writer) void {
        if (writer.pending_length != 0) writer.group(writer.pending[0..writer.pending_length]);
        writer.pending_length = 0;
        writer.flush();
    }

    fn flush(writer: *Base64Writer) void {
        if (writer.used == 0 or writer.failure != null) {
            writer.used = 0;
            return;
        }
        write(writer.self, writer.out[0..writer.used]) catch |err| {
            writer.failure = err;
        };
        writer.used = 0;
    }

    fn sink(writer: *Base64Writer) words_graphics.ByteSink {
        return .{ .context = writer, .write = struct {
            fn put(context: *anyopaque, data: []const u8) void {
                const base64: *Base64Writer = @ptrCast(@alignCast(context));
                base64.bytes(data);
            }
        }.put };
    }
};

fn writeImage(self: *State) RuntimeError!void {
    var writer = Base64Writer{ .self = self };
    // Tk shows the screen, whatever image the drawing words draw on.
    words_graphics.writePng(try graphics_images.screenCanvas(self), writer.sink(), self.gfx_color_mode);
    writer.finish();
    if (writer.failure) |failure| return failure;
}

/// GFX-SHOW-TK: shows the image in the Tk window, as a PNG in base64.
pub fn showImage(self: *State) RuntimeError!void {
    const png = words_graphics.pngLength(@intCast(self.gfx_width), @intCast(self.gfx_height));
    const base64 = (png + 2) / 3 * 4;
    // The size of the window's image (WINDOW-SIZE), 0 0 for the image's own.
    var buffer: [48]u8 = undefined;
    const command = std.fmt.bufPrint(&buffer, "sigma_show {d} {d} ", .{ self.gfx_window_size[0], self.gfx_window_size[1] }) catch unreachable;
    if (command.len + base64 > max_message) return error.InvalidNumber;
    if (try run(self, &.{command}, @intCast(command.len + base64), writeImage)) return error.TclFailed;
}
