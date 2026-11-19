//! VM-thread process owner; FileSlot adopts public pipes after native startup.
const std = @import("std");
const builtin = @import("builtin");
const forth = @import("forth.zig");
const io = @import("core/host_interface.zig");
const model = @import("host_process_table.zig");
const Native = @import("host_process_native.zig").Native;
const clock = @import("host_clock.zig");
const base = @import("core/runtime_base.zig");
const Cell = forth.Cell;
pub const Bridge = struct {
    context: ?*anyopaque = null,
    room: *const fn (?*anyopaque, usize) bool,
    publish: *const fn (?*anyopaque, Cell, u2, *anyopaque) forth.FileResult,
    belongs: *const fn (?*anyopaque, Cell, Cell) bool,
    discard: *const fn (?*anyopaque, Cell, Cell) Cell,
    /// Stop private adapter I/O before the native object closes its C streams.
    stop_internal: ?*const fn (?*anyopaque, Cell) Cell = null,
    released_internal: ?*const fn (?*anyopaque, Cell) void = null,
};
fn ior(err: c_int) Cell {
    return if (err == 0) 0 else forth.errnoIor(err);
}
fn modelIor(err: anyerror, capacity_error: c_int) Cell {
    return ior(switch (err) {
        error.InvalidId => 9,
        error.InvalidState => 16,
        error.OutOfMemory => 12,
        error.Capacity => capacity_error,
        error.TooLarge => 7,
        else => 22,
    });
}
pub const Registry = struct {
    table: model.Table,
    inherited: *const std.process.Environ.Map,
    bridge: Bridge,
    native: [model.capacity + 1]Native = @splat(.{}),
    streams: [model.capacity + 1][3]Cell = @splat(@splat(0)),
    pub fn init(allocator: std.mem.Allocator, inherited: *const std.process.Environ.Map, bridge: Bridge) Registry {
        return .{ .table = model.Table.init(allocator), .inherited = inherited, .bridge = bridge };
    }
    fn index(self: *Registry, id: Cell, internal: bool) ?usize {
        for (&self.table.slots, 0..) |*slot, which| if (slot.*) |entry| {
            if (entry.id == id and (internal or !entry.internal)) return which;
        };
        return null;
    }
    pub fn create(self: *Registry, internal: bool) forth.FileResult {
        const id = (if (internal) self.table.createInternal() else self.table.create()) catch |err| return .{ .ior = modelIor(err, 24) };
        return .{ .value = @bitCast(id) };
    }
    pub fn text(self: *Registry, id: Cell, internal: bool, kind: io.ProcessText, bytes: []const u8) Cell {
        const slot = self.index(id, internal) orelse return ior(9);
        const config = self.table.slots[slot].?.editable() catch |err| return modelIor(err, 7);
        (switch (kind) {
            .argument => config.addArgument(self.table.allocator, bytes),
            .cwd => config.setCwd(self.table.allocator, bytes),
            .environment => config.addEnvironment(self.table.allocator, bytes),
        }) catch |err| return modelIor(err, 7);
        return 0;
    }
    pub fn setIo(self: *Registry, id: Cell, internal: bool, which: Cell, mode: Cell) Cell {
        const slot = self.index(id, internal) orelse return ior(9);
        if (which < 0 or which > 2 or mode < 0 or mode > 3) return ior(22);
        const config = self.table.slots[slot].?.editable() catch |err| return modelIor(err, 7);
        config.setMode(@intCast(which), @fromBackingInt(@intCast(mode))) catch |err| return modelIor(err, 7);
        return 0;
    }
    fn closeStreams(self: *Registry, slot: usize) Cell {
        const entry = &self.table.slots[slot].?;
        if (entry.internal) {
            if (self.bridge.stop_internal) |stop| return stop(self.bridge.context, entry.id);
            return 0;
        }
        var first: Cell = 0;
        for (&self.streams[slot]) |*id| {
            if (id.* == 0) continue;
            if (!self.bridge.belongs(self.bridge.context, entry.id, id.*)) {
                id.* = 0;
                continue;
            }
            const result = self.bridge.discard(self.bridge.context, entry.id, id.*);
            if (result != 0 and first == 0) first = result;
            if (!self.bridge.belongs(self.bridge.context, entry.id, id.*)) id.* = 0;
        }
        return first;
    }
    fn streamsPending(self: *Registry, slot: usize) bool {
        for (self.streams[slot]) |id| if (id != 0 and self.bridge.belongs(self.bridge.context, self.table.slots[slot].?.id, id)) return true;
        return false;
    }
    fn abortStart(self: *Registry, slot: usize, timeout_ms: u32) Cell {
        const entry = &self.table.slots[slot].?;
        if (self.native[slot].pointer != null) _ = self.native[slot].signal(true);
        const streams_error = self.closeStreams(slot);
        if (streams_error != 0 and (entry.internal or self.streamsPending(slot))) return streams_error;
        var err = self.native[slot].abort(timeout_ms);
        for (0..2) |_| {
            if (err != 10) break;
            entry.ownershipLost();
            err = self.native[slot].abort(0);
        }
        if (err != 0) return ior(err);
        entry.nativeReleased() catch return ior(5);
        return streams_error;
    }
    pub fn start(self: *Registry, id: Cell, internal: bool) Cell {
        return self.startWithin(id, internal, 3000);
    }
    pub fn startWithin(self: *Registry, id: Cell, internal: bool, timeout_ms: u32) Cell {
        const slot = self.index(id, internal) orelse return ior(9);
        const entry = &self.table.slots[slot].?;
        const config = entry.editable() catch |err| return modelIor(err, 7);
        if (config.arguments.items.len == 0) return ior(22);
        var pipes: usize = 0;
        for (config.modes) |mode| if (mode == .pipe) {
            pipes += 1;
        };
        if (!entry.internal and !self.bridge.room(self.bridge.context, pipes)) return ior(24);
        entry.nativeAcquired() catch return ior(16);
        const err = self.native[slot].start(self.table.allocator, config, self.inherited);
        if (err != 0) {
            _ = self.abortStart(slot, timeout_ms);
            return ior(err);
        }
        if (!entry.internal) for (0..3) |which| {
            const pipe_file = self.native[slot].stream(@intCast(which)) orelse continue;
            const result = self.bridge.publish(self.bridge.context, id, @intCast(which), pipe_file);
            if (result.ior != 0) {
                _ = self.abortStart(slot, timeout_ms);
                return result.ior;
            }
            // Bridge owns the FILE only after successful publication.
            self.streams[slot][which] = @bitCast(result.value);
            _ = self.native[slot].take(@intCast(which));
        };
        entry.started() catch {
            _ = self.abortStart(slot, timeout_ms);
            return ior(5);
        };
        return 0;
    }
    pub fn stream(self: *Registry, id: Cell, internal: bool, which: u2) forth.FileResult {
        const slot = self.index(id, internal) orelse return .{ .ior = ior(9) };
        if (which > 2) return .{ .ior = ior(22) };
        if (self.table.slots[slot].?.phase == .configuring) return .{ .ior = ior(22) };
        const fileid = self.streams[slot][which];
        if (fileid == 0) return .{};
        if (!self.bridge.belongs(self.bridge.context, id, fileid)) return .{ .ior = ior(9) };
        return .{ .value = @bitCast(fileid) };
    }
    /// Private Tcl protocol never publishes its IDs or streams to PROC callbacks.
    pub fn internalStream(self: *Registry, id: Cell, which: u2, take: bool) ?*anyopaque {
        const slot = self.index(id, true) orelse return null;
        if (!self.table.slots[slot].?.internal) return null;
        return if (take) self.native[slot].take(which) else self.native[slot].stream(which);
    }
    pub fn status(self: *Registry, id: Cell, internal: bool) io.ProcessStatus {
        const slot = self.index(id, internal) orelse return .{ .ior = ior(9) };
        const entry = &self.table.slots[slot].?;
        if (entry.native_lost) return .{ .state = @backingInt(entry.phase), .code = entry.code, .ior = ior(10) };
        if (entry.phase == .configuring) return .{ .ior = if (entry.native_owned) ior(16) else 0 };
        if (self.native[slot].pointer != null) {
            const result = self.native[slot].status();
            if (result.err != 0) {
                if (result.err == 10) entry.ownershipLost();
                return .{ .state = @backingInt(entry.phase), .code = entry.code, .ior = ior(result.err) };
            }
            if (entry.phase == .running and (result.state == 2 or result.state == 3)) entry.finished(if (result.state == 2) .exited else .signaled, result.code) catch return .{ .ior = ior(5) };
        }
        return .{ .state = @backingInt(entry.phase), .code = entry.code };
    }
    pub fn signal(self: *Registry, id: Cell, internal: bool, force: bool) Cell {
        const slot = self.index(id, internal) orelse return ior(9);
        if (self.table.slots[slot].?.native_lost) return ior(10);
        const result = self.native[slot].signal(force);
        if (result == 10) self.table.slots[slot].?.ownershipLost();
        return ior(result);
    }
    pub fn waitSlice(self: *Registry, id: Cell, internal: bool, milliseconds: u32) Cell {
        const slot = self.index(id, internal) orelse return ior(9);
        return ior(self.native[slot].waitSlice(milliseconds));
    }
    pub fn free(self: *Registry, id: Cell, internal: bool) Cell {
        return self.freeWithin(id, internal, 3000);
    }
    pub fn freeWithin(self: *Registry, id: Cell, internal: bool, timeout_ms: u32) Cell {
        const slot = self.index(id, internal) orelse return ior(9);
        const entry = &self.table.slots[slot].?;
        var close_error: Cell = 0;
        if (entry.phase == .configuring and entry.native_owned) {
            const error_ior = self.abortStart(slot, timeout_ms);
            if (error_ior != 0 and entry.native_owned) return error_ior;
            close_error = error_ior;
        } else if (entry.phase != .configuring) {
            const observed = self.status(id, internal);
            if (!entry.native_lost and observed.ior != 0) return observed.ior;
            if (!entry.native_lost and entry.phase == .running) return ior(16);
            const streams_error = self.closeStreams(slot);
            if (streams_error != 0 and (entry.internal or self.streamsPending(slot))) return streams_error;
            close_error = streams_error;
            var err = if (entry.native_lost) self.native[slot].abort(0) else self.native[slot].destroy();
            // ECHILD cleanup reports the loss once while retaining its retry token.
            for (0..2) |_| {
                if (err != 10) break;
                entry.ownershipLost();
                err = self.native[slot].abort(0);
            }
            if (err != 0) return ior(err);
            entry.nativeReleased() catch return ior(5);
        }
        const lost = entry.native_lost;
        const was_internal = entry.internal;
        self.table.remove(id) catch |err| return modelIor(err, 24);
        if (was_internal) if (self.bridge.released_internal) |released| released(self.bridge.context, id);
        return if (lost) ior(10) else close_error;
    }
    pub fn hasResources(self: *Registry) bool {
        for (self.table.slots) |slot| if (slot != null) return true;
        return false;
    }
    pub fn shutdown(self: *Registry) Cell {
        var first: Cell = 0;
        for (&self.table.slots, 0..) |*slot, index_| if (slot.*) |*entry| {
            if (self.native[index_].pointer != null) {
                const native_status = self.native[index_].status();
                if (native_status.err == 0 and native_status.state == 0) continue;
                const result = self.signal(entry.id, true, true);
                if (result != 0 and first == 0) first = result;
            }
        };
        const deadline = base.Deadline.afterMilliseconds(cleanupNow(&first), 3000) catch base.Deadline{ .at = 0 };
        for (&self.table.slots, 0..) |*slot, index_| if (slot.*) |*entry| {
            const stream_error = self.closeStreams(index_);
            if (stream_error != 0) {
                if (first == 0) first = stream_error;
                if (entry.internal or self.streamsPending(index_)) continue;
            }
            while (true) {
                const observed = self.status(entry.id, true);
                if (observed.ior != 0 or observed.state != 1) break;
                if (deadline.expired(cleanupNow(&first))) {
                    if (first == 0) first = ior(16);
                    break;
                }
                pause();
            }
            const result = self.freeWithin(entry.id, true, deadline.remainingMilliseconds(cleanupNow(&first), 3000));
            if (result != 0 and first == 0) first = result;
        };
        return first;
    }
};
fn pause() void {
    if (builtin.os.tag == .windows) {
        const win = struct {
            extern "kernel32" fn Sleep(u32) callconv(.winapi) void;
        };
        win.Sleep(5);
    } else {
        const time: std.c.timespec = .{ .sec = 0, .nsec = 5000000 };
        _ = std.c.nanosleep(&time, null);
    }
}

fn cleanupNow(first: *Cell) base.Instant {
    return clock.now() catch {
        if (first.* == 0) first.* = ior(5);
        return std.math.maxInt(base.Instant);
    };
}
