//! Number and text output words, and the number base.

const defs = @import("defs.zig");
const forth = @import("../forth.zig");
const memory_map = @import("memory_map.zig");
const Builtin = defs.Builtin;
const Cell = memory_map.Cell;
const Double = memory_map.Double;
const RuntimeError = defs.RuntimeError;
const State = forth.State;
const UCell = memory_map.UCell;
const base_address = memory_map.base_address;
const max_dot_s_items = memory_map.max_dot_s_items;

/// The built-in words this file executes; executeBuiltin dispatches by this list.
pub const words = [_]Builtin{
    .dot, .u_dot, .dot_r, .u_dot_r, .c_dot, .dot_s, .echo, .cr, .space, .spaces, .type, .hex, .dec, .oct, .base,
    .d_dot, .page,
};

pub fn execute(self: *State, comptime builtin: Builtin) RuntimeError!void {
    switch (builtin) {
        .dot, .u_dot => {
            const value = try self.pop();
            self.writeNumber(if (builtin == .u_dot) @as(UCell, @bitCast(value)) else value);
            self.write(" ");
        },
        // The number right-aligned in a field of width characters, without a space after it;
        // a longer number is printed whole.
        .dot_r, .u_dot_r => {
            const width = try self.pop();
            const value = try self.pop();
            const number: Double = if (builtin == .u_dot_r) @as(UCell, @bitCast(value)) else value;
            var pad = width -| @as(Cell, @intCast(self.numberWidth(number)));
            while (pad > 0) : (pad -= 1) self.write(" ");
            self.writeNumber(number);
        },
        .c_dot => {
            self.writeNumber((try self.pop()) & 0xff);
            self.write(" ");
        },
        .dot_s => {
            self.writeDepth(self.data_depth);
            // Like gforth, only the top items are shown below the depth.
            for (self.data_stack[self.data_depth -| max_dot_s_items .. self.data_depth]) |value| {
                self.writeNumber(value);
                self.write(" ");
            }
        },
        .echo => {
            const byte: [1]u8 = .{@truncate(@as(UCell, @bitCast(try self.pop())))};
            self.write(&byte);
        },
        .cr => self.write("\n"),
        .space => self.write(" "),
        .spaces => {
            var count = try self.pop();
            while (count > 0) : (count -= 1) self.write(" ");
        },
        .type => {
            const bytes = try self.memoryRange();
            self.write(bytes);
        },
        .hex => try self.writeCell(base_address, 16),
        .dec => try self.writeCell(base_address, 10),
        .oct => try self.writeCell(base_address, 8),
        .base => try self.push(base_address),
        .d_dot => {
            self.writeNumber(try self.popDouble());
            self.write(" ");
        },
        .page => self.write("\x1b[2J\x1b[1;1H"),
        else => @compileError(@tagName(builtin) ++ " is not in the words of this file"),
    }
}
