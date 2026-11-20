//! Producer-owned PCM session metadata. Consumer sees only transport and Control.
const std = @import("std");
const stream = @import("sound_stream.zig");
pub const Session = struct {
    storage: []stream.Frame = &.{},
    transport: stream.Stream = undefined,
    phase: enum { free, opening, running, stopping, stopped, closing } = .free,
    id: i64 = 0,
    owner: usize = 0,
    next_id: i64 = 1,
    request: u32 = 0,
    detached: bool = false,

    pub fn open(self: *Session, control: *stream.Control, owner: usize, hz: u32, channels: u32, capacity: u32, output_rate: u32) error{HostFailed}!struct { id: i64 = 0, ior: i64 = 0 } {
        if (self.phase == .free) {
            std.debug.assert(control.request.raw == control.acknowledged.load(.acquire) and control.pending == null);
        }
        if (self.phase != .free) return .{ .ior = -528 };
        if (self.storage.len < capacity) return .{ .ior = -524 };
        if (self.next_id == 0) return .{ .ior = -587 };
        // No consumer can refer to transport while the session is free: close
        // commits only after detach acknowledgement. A new instance starts here.
        self.transport = stream.Stream.init(self.storage[0..capacity], hz, output_rate, channels) catch return error.HostFailed;
        const serial = control.publish(&self.transport) catch |err| return .{ .ior = if (err == error.Busy) -528 else -587 };
        self.id = self.next_id;
        self.next_id = if (self.next_id == std.math.maxInt(i64)) 0 else self.next_id + 1;
        self.owner = owner;
        self.phase = .opening;
        self.request = serial;
        self.detached = false;
        return .{ .id = self.id };
    }
    pub fn matches(self: *const Session, owner: usize, id: i64) bool {
        return id > 0 and self.phase != .free and self.id == id and self.owner == owner;
    }
    pub fn refresh(self: *Session, control: *const stream.Control) void {
        if (!control.completed(self.request)) return;
        if (self.phase == .opening) self.phase = .running;
        if (self.phase == .stopping and self.detached) self.phase = .stopped;
    }
    pub fn writable(self: *const Session) bool {
        return self.phase == .opening or self.phase == .running;
    }
    pub fn tryDetach(self: *Session, control: *stream.Control, closing: bool) error{HostFailed}!bool {
        self.refresh(control);
        if (self.detached) return control.completed(self.request);
        if (!control.completed(self.request)) return false;
        self.transport.draining.store(true, .release);
        const serial = control.publish(null) catch return error.HostFailed;
        self.request = serial;
        self.detached = true;
        self.phase = if (closing) .closing else .stopping;
        return false;
    }
    pub fn beginClose(self: *Session) void {
        self.phase = .closing;
        self.transport.draining.store(true, .release);
    }
    pub fn commitClose(self: *Session, control: *const stream.Control) void {
        std.debug.assert(self.detached and control.completed(self.request));
        self.phase = .free;
        self.id = 0;
        self.owner = 0;
        self.request = 0;
        self.detached = false;
    }
};
