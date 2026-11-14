//! Standard terminal/key words, independent of GRAPHICS key encodings.
const std = @import("std");
const forth = @import("../forth.zig");
const defs = @import("defs.zig");
const map = @import("memory_map.zig");
const keys = @import("standard_keys.zig");
pub const words = [_]defs.Builtin{ .key_ior, .form, .at_deltaxy, .fkey_dot, .simple_fkey_string };

fn nameIndex(self: *forth.State, event: map.Cell) forth.RuntimeError!usize {
    if (event < keys.special or event >= keys.special + keys.names.len) return self.throwCode(-24);
    return @intCast(event - keys.special);
}
fn nameBytes(self: *forth.State, index: usize) []const u8 {
    const at: usize = @intCast(map.key_name_base + @as(map.Cell, @intCast(keys.nameOffset(index))));
    return self.memory[at..][0..keys.names[index].len];
}
fn keyIor(self: *forth.State) forth.RuntimeError!map.Cell {
    if (self.pending_key != null or self.pending_event_count != 0) return try @import("words_xchar.zig").key(self);
    const result = if (@import("input_redirect.zig").selected(self)) |id| selected: {
        const callback = (try self.fileOps()).key orelse return error.FileUnavailable;
        break :selected try callback(self.writer.context, id);
    } else if (self.writer.key_ior_fn) |callback| try callback(self.writer.context) else {
        const callback = self.writer.key_fn orelse return error.InputUnavailable;
        return if (callback(self.writer.context)) |byte| byte else map.ior_errno_base;
    };
    if (result.ior != 0) return result.ior;
    return if (result.byte) |byte| byte else map.ior_errno_base;
}
pub fn execute(self: *forth.State, comptime word: defs.Builtin) forth.RuntimeError!void {
    switch (word) {
        .key_ior => {
            if (self.data_depth == self.data_stack.len) return error.StackOverflow;
            try self.push(try keyIor(self));
        },
        .simple_fkey_string => {
            const index = try nameIndex(self, try self.peek(0));
            if (self.data_depth == self.data_stack.len) return error.StackOverflow;
            self.data_stack[self.data_depth - 1] = map.key_name_base + @as(map.Cell, @intCast(keys.nameOffset(index)));
            try self.push(@intCast(keys.names[index].len));
        },
        .fkey_dot => {
            const event = try self.peek(0);
            const index = try nameIndex(self, event & ~(keys.shift | keys.alt | keys.ctrl));
            self.data_depth -= 1;
            self.write(nameBytes(self, index));
            if (event & keys.shift != 0) self.write(" k-shift-mask or");
            if (event & keys.ctrl != 0) self.write(" k-ctrl-mask or");
            if (event & keys.alt != 0) self.write(" k-alt-mask or");
        },
        .form => {
            if (self.data_stack.len - self.data_depth < 2) return error.StackOverflow;
            var rows: map.Cell = 24;
            var columns: map.Cell = 80;
            if (self.capture_target != null or self.capture_sink != null) {
                rows = 1;
                columns = std.math.maxInt(map.Cell);
            } else if ((self.output_file orelse map.stdout_fileid) == map.stdout_fileid) {
                if (self.writer.terminal_size_fn) |callback| if (callback(self.writer.context)) |size| {
                    if (size.rows != 0 and size.columns != 0) {
                        rows = size.rows;
                        columns = size.columns;
                    }
                };
            }
            try self.push(rows);
            try self.push(columns);
        },
        .at_deltaxy => {
            try self.requireDepth(2);
            if (self.capture_target != null or self.capture_sink != null) return self.throwCode(-21);
            const y = try self.pop();
            const x = try self.pop();
            var buffer: [32]u8 = undefined;
            for ([_]map.Cell{ x, y }, 0..) |value, axis| {
                if (value == 0) continue;
                const magnitude: u64 = @intCast(if (value < 0) -@as(i128, value) else value);
                const direction: u8 = if (axis == 0) (if (value > 0) 'C' else 'D') else (if (value > 0) 'B' else 'A');
                self.write(std.fmt.bufPrint(&buffer, "\x1b[{d}{c}", .{ magnitude, direction }) catch unreachable);
                try self.checkOutputError();
            }
        },
        else => unreachable,
    }
}
