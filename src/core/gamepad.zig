//! A per-interpreter input snapshot. No OS handles or device data enter SAVE images.
const forth = @import("../forth.zig");
const defs = @import("defs.zig");

pub const max_pads = 8;
pub const Pad = struct {
    id: u32 = 0,
    mapped: bool = false,
    buttons: u32 = 0,
    axes: [16]i16 = @splat(0),
    hats: [4]u8 = @splat(0),
    axis_count: u8 = 0,
    button_count: u8 = 0,
    hat_count: u8 = 0,
    name: [128]u8 = @splat(0),
    name_len: u8 = 0,
    guid: [32]u8 = @splat(0),
};
pub const Snapshot = struct { pads: [max_pads]Pad = @splat(.{}), count: usize = 0 };
pub const Ops = struct {
    /// False means that the backend is unavailable, not that no pads are connected.
    poll: *const fn (?*anyopaque, *Snapshot) bool,
    mapping: *const fn (?*anyopaque, []const u8) bool,
};

pub fn execute(self: *forth.State, word: defs.Builtin) defs.RuntimeError!void {
    switch (word) {
        .gfx_gamepad_poll => {
            self.gamepads = .{};
            const ops = self.writer.gamepad_ops orelse {
                try self.push(-1);
                return;
            };
            if (!ops.poll(self.writer.context, &self.gamepads)) {
                self.gamepads = .{};
                try self.push(-1);
            } else {
                self.gamepads.count = @min(self.gamepads.count, max_pads);
                try self.push(@intCast(self.gamepads.count));
            }
        },
        .gfx_gamepad_query => {
            const index = try self.pop();
            const field = try self.pop();
            if (index < 0 or index >= max_pads or !(field >= 0 and field <= 6 or field >= 16 and field < 36)) return error.InvalidNumber;
            if (index >= self.gamepads.count) {
                try self.push(0);
                return;
            }
            const pad = &self.gamepads.pads[@intCast(index)];
            const value: forth.Cell = switch (field) {
                0 => -1,
                1 => pad.id,
                2 => pad.buttons,
                3 => if (pad.mapped) -1 else 0,
                4 => pad.axis_count,
                5 => pad.button_count,
                6 => pad.hat_count,
                16...31 => pad.axes[@intCast(field - 16)],
                32...35 => pad.hats[@intCast(field - 32)],
                else => unreachable,
            };
            try self.push(value);
        },
        .gfx_gamepad_name, .gfx_gamepad_guid => {
            const index = try self.pop();
            const dest = try self.memoryRange();
            if (index < 0 or index >= max_pads) return error.InvalidNumber;
            if (index >= self.gamepads.count) {
                try self.push(0);
                return;
            }
            const pad = &self.gamepads.pads[@intCast(index)];
            const source: []const u8 = if (word == .gfx_gamepad_guid) &pad.guid else pad.name[0..@min(pad.name_len, pad.name.len)];
            const n = @min(dest.len, source.len);
            @memcpy(dest[0..n], source[0..n]);
            @import("address_registry.zig").written(self, @intCast(@intFromPtr(dest.ptr) - @intFromPtr(self.memory.ptr)), n, false);
            try self.push(@intCast(n));
        },
        .gfx_gamepad_map => {
            const mapping = try self.memoryRange();
            const ops = self.writer.gamepad_ops orelse {
                try self.push(0);
                return;
            };
            try self.push(if (ops.mapping(self.writer.context, mapping)) -1 else 0);
        },
        else => unreachable,
    }
}
