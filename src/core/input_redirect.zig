//! Scoped borrowed input selection; parser source identity is independent.
const forth = @import("../forth.zig");
const map = @import("memory_map.zig");

pub fn selected(self: *forth.State) ?forth.Cell {
    const id = self.input_file orelse return null;
    return if (id == map.stdin_fileid) null else id;
}

pub fn run(self: *forth.State) forth.RuntimeError!void {
    try self.requireDepth(2);
    const id = try self.peek(0);
    const xt = try self.wordId(try self.peek(1));
    _ = try self.fileOps();
    const previous = self.input_file;
    const changed = id != (previous orelse map.stdin_fileid);
    const pending = self.pending_key;
    const events = self.pending_event_bytes;
    const count = self.pending_event_count;
    const event = self.pending_standard_event;
    self.input_file = id;
    if (changed) {
        self.pending_key = null;
        self.pending_event_count = 0;
        self.pending_standard_event = null;
    }
    defer {
        self.input_file = previous;
        if (changed) {
            self.pending_key = pending;
            self.pending_event_bytes = events;
            self.pending_event_count = count;
            self.pending_standard_event = event;
        }
    }
    self.data_depth -= 2;
    try self.executeWord(xt);
}

pub fn byte(self: *forth.State) forth.RuntimeError!?u8 {
    const files = try self.fileOps();
    const callback = files.key orelse return error.FileUnavailable;
    const result = try callback(self.writer.context, selected(self).?);
    if (result.ior != 0) return self.throwCode(result.ior);
    return result.byte;
}

pub fn unread(self: *forth.State, value: u8) forth.RuntimeError!void {
    const files = try self.fileOps();
    const callback = files.unread orelse return error.FileUnavailable;
    try callback(self.writer.context, selected(self).?, value);
}

pub fn ready(self: *forth.State) forth.RuntimeError!bool {
    if (selected(self)) |id| {
        const callback = (try self.fileOps()).ready orelse return error.FileUnavailable;
        const result = try callback(self.writer.context, id);
        if (result.ior != 0) return self.throwCode(result.ior);
        return result.value != 0;
    }
    return self.pending_key != null or self.pending_event_count != 0 or if (self.writer.key_ready_fn) |callback| callback(self.writer.context) else false;
}

/// Preserve Sigma's line-read/clip behavior; drain the complete physical line.
pub fn line(self: *forth.State, buffer: []u8) forth.RuntimeError!?[]const u8 {
    if (selected(self) == null) {
        const callback = self.writer.read_fn orelse return null;
        return callback(self.writer.context, buffer);
    }
    var length: usize = 0;
    var found = false;
    var work: usize = 0;
    while (try byte(self)) |value| {
        found = true;
        if (value == '\n') break;
        if (value == '\r') {
            if (try byte(self)) |next| if (next != '\n') try unread(self, next);
            break;
        }
        if (length < buffer.len) {
            buffer[length] = value;
            length += 1;
        }
        work += 1;
        if (work % 1024 == 0) try @import("words_numeric.zig").checkWorkBlock(self);
    }
    return if (found) buffer[0..length] else null;
}
