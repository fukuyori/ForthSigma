//! Public PCM primitives. Validate before effects; all consumer storage is host-owned.
const std = @import("std");
const forth = @import("../forth.zig");
const defs = @import("defs.zig");
const base = @import("runtime_base.zig");
const Engine = @import("sound_engine.zig").Engine;
const Session = @import("sound_stream_session.zig").Session;
const State = forth.State;
const Cell = forth.Cell;
const Error = forth.RuntimeError;

fn engineOf(self: *State) Error!*Engine {
    const callback = self.writer.audio_fn orelse return error.HostUnavailable;
    return callback(self.writer.context) orelse error.HostFailed;
}
fn owned(self: *State, id: Cell) Error!?*Engine {
    if (self.writer.audio_fn == null) return error.HostUnavailable;
    if (id <= 0 or self.audio_pcm_handle != id) return null;
    const engine = try engineOf(self);
    if (!engine.pcm_session.matches(@intFromPtr(self), id)) {
        self.audio_pcm_handle = 0;
        return null;
    }
    engine.pcm_session.refresh(&engine.pcm_control);
    return engine;
}
fn result(self: *State, consumed: usize, value: Cell, ior: Cell) Error!void {
    self.data_depth -= consumed;
    try self.push(value);
    try self.push(ior);
}
fn single(self: *State, ior: Cell) Error!void {
    self.data_depth -= 1;
    try self.push(ior);
}

pub fn execute(self: *State, builtin: defs.Builtin) Error!void {
    switch (builtin) {
        .snd_pcm_open => {
            try self.requireDepth(3);
            const hz = try self.peek(2);
            const channels = try self.peek(1);
            const capacity = try self.peek(0);
            if (hz < 8000 or hz > 192000 or channels < 1 or channels > 2 or capacity < 256 or capacity > 65536 or
                !@import("sound_stream.zig").validCapacity(@intCast(hz), @intCast(capacity))) return error.InvalidNumber;
            if (self.writer.audio_scope_ops == null or self.writer.standard_clock == null or self.writer.audio_wait_fn == null) return error.HostUnavailable;
            const engine = try engineOf(self);
            if (self.audio_pcm_handle != 0 and !engine.pcm_session.matches(@intFromPtr(self), self.audio_pcm_handle)) self.audio_pcm_handle = 0;
            if (self.audio_pcm_handle != 0) return result(self, 3, 0, -528);
            const opened = try engine.pcm_session.open(&engine.pcm_control, @intFromPtr(self), @intCast(hz), @intCast(channels), @intCast(capacity), engine.sample_rate);
            if (opened.ior == 0) self.audio_pcm_handle = opened.id;
            try result(self, 3, opened.id, opened.ior);
        },
        .snd_pcm_write => {
            try self.requireDepth(3);
            const address = try self.peek(2);
            const frames = try self.peek(1);
            const id = try self.peek(0);
            if (frames < 0) return error.InvalidNumber;
            const engine = (try owned(self, id)) orelse return result(self, 3, 0, -521);
            const session = &engine.pcm_session;
            if (!session.writable()) return result(self, 3, 0, -534);
            var bytes: []const u8 = &.{};
            if (frames != 0) {
                const product = @mulWithOverflow(@as(u64, @intCast(frames)), @as(u64, session.transport.channels) * 2);
                if (product[1] != 0 or product[0] > std.math.maxInt(usize)) return error.InvalidAddress;
                const length: usize = @intCast(product[0]);
                const start = try self.memoryAddress(address, length);
                bytes = self.memory[start..][0..length];
            }
            const copied = session.transport.write(bytes, @intCast(frames)) catch return error.HostFailed;
            try result(self, 3, @intCast(copied), 0);
        },
        .snd_pcm_queued, .snd_pcm_underruns => {
            try self.requireDepth(1);
            if (self.data_depth >= self.data_stack.len) return error.StackOverflow;
            const engine = (try owned(self, try self.peek(0))) orelse return result(self, 1, 0, -521);
            const session = &engine.pcm_session;
            const value: Cell = if (builtin == .snd_pcm_queued) session.transport.queued() else if (!engine.pcm_control.completed(session.request) and !session.detached) 0 else session.transport.underruns.load(.acquire);
            try result(self, 1, value, 0);
        },
        .snd_pcm_wait, .snd_pcm_stop => {
            try self.requireDepth(3);
            const argument = try self.peek(2);
            const milliseconds = try self.peek(1);
            const id = try self.peek(0);
            if (argument < 0 or (builtin == .snd_pcm_stop and argument > 1)) return error.InvalidNumber;
            const engine = (try owned(self, id)) orelse return result(self, 3, 0, -521);
            const session = &engine.pcm_session;
            if (builtin == .snd_pcm_wait) {
                if (argument == 0 or argument > session.transport.frames.len) return error.InvalidNumber;
                if (!session.writable()) return result(self, 3, 0, -534);
            } else {
                if (session.phase == .closing) return result(self, 3, 0, -534);
                if (session.phase == .stopped) return result(self, 3, -1, 0);
            }
            const ready = try waitFor(self, engine, if (builtin == .snd_pcm_wait) .space else .stop, argument, milliseconds);
            try result(self, 3, if (ready) -1 else 0, 0);
        },
        .snd_pcm_close => {
            try self.requireDepth(1);
            const engine = (try owned(self, try self.peek(0))) orelse return single(self, -521);
            const session = &engine.pcm_session;
            if (session.phase != .stopped) {
                const completed = waitFor(self, engine, .close, 0, 1000) catch |err| {
                    if (err == error.UserInterrupt) return single(self, -516);
                    return err;
                };
                if (!completed) return single(self, -528);
            }
            // Commit only after the whole-operation interrupt scope restored.
            session.commitClose(&engine.pcm_control);
            self.audio_pcm_handle = 0;
            try single(self, 0);
        },
        else => unreachable,
    }
}
const Kind = enum { space, stop, close };
fn waitFor(self: *State, engine: *Engine, kind: Kind, argument: Cell, milliseconds: Cell) Error!bool {
    const ops = self.writer.audio_scope_ops orelse return error.HostUnavailable;
    const clock = self.writer.standard_clock orelse return error.HostUnavailable;
    const sleep = self.writer.audio_wait_fn orelse return error.HostUnavailable;
    try ops.begin(self.writer.context, self);
    const session = &engine.pcm_session;
    if (kind == .close) session.beginClose();
    if (kind == .stop and argument == 1 and session.writable()) session.transport.draining.store(true, .release);
    const outcome = loop(self, engine, ops, clock, sleep, kind, argument, milliseconds);
    // An uncommitted drain timeout/error returns to running. A published detach
    // keeps suppression until ack and the next OPEN's quiescent initialization.
    if (kind == .stop and !session.detached) session.transport.draining.store(false, .release);
    ops.end(self.writer.context, self) catch |end_error| {
        if (end_error != error.UserInterrupt) return end_error;
        if (outcome) |_| {} else |work_error| if (work_error != error.UserInterrupt) return work_error;
        return end_error;
    };
    return outcome;
}
fn loop(self: *State, engine: *Engine, ops: *const @import("host_interface.zig").ExecutionOps, clock: base.Clock, sleep: *const fn (?*anyopaque) forth.AudioWait, kind: Kind, argument: Cell, milliseconds: Cell) Error!bool {
    const deadline = try base.Deadline.afterMilliseconds(try clock.now(), milliseconds);
    const session = &engine.pcm_session;
    while (true) {
        try ops.poll(self.writer.context, self);
        session.refresh(&engine.pcm_control);
        const ready = switch (kind) {
            .space => session.transport.free() >= @as(u64, @intCast(argument)),
            .stop => if (argument == 1 and !session.detached and session.transport.queued() != 0) false else try session.tryDetach(&engine.pcm_control, false),
            .close => try session.tryDetach(&engine.pcm_control, true),
        };
        if (ready) return true;
        if (deadline.expired(try clock.now())) return false;
        switch (sleep(self.writer.context)) {
            .host_failed => return error.HostFailed,
            .interrupted => return error.UserInterrupt,
            .waited, .read_input => {}, // scope.poll preserves raw input itself.
        }
    }
}
