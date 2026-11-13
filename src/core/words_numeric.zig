//! Numeric conversion extensions, explicit bases, and VM-local reproducible random state.
const std = @import("std");
const defs = @import("defs.zig");
const forth = @import("../forth.zig");
const map = @import("memory_map.zig");
const io = @import("number_io.zig");
const State = forth.State;
const Builtin = defs.Builtin;
const RuntimeError = defs.RuntimeError;

pub const words = [_]Builtin{ .random, .rnd, .seed_store, .base_execute, .convert, .decimal_dot, .decimal_dot_r, .dpl, .hex_dot, .h_dot, .ud_dot, .ud_dot_r };

pub fn execute(self: *State, comptime builtin: Builtin) RuntimeError!void {
    switch (builtin) {
        .seed_store => self.random_state = @bitCast(try self.pop()),
        .rnd, .random => {
            const bound: u64 = if (builtin == .random) @bitCast(try self.pop()) else 0;
            // Full-period 64-bit LCG; the sequence is a Sigma convention, not Gforth's.
            self.random_state = self.random_state *% 6364136223846793005 +% 1442695040888963407;
            const value: u64 = if (builtin == .rnd) self.random_state else @intCast((@as(u128, self.random_state) * bound) >> 64);
            try self.push(@bitCast(value));
        },
        .dpl => try self.push(map.dpl_address),
        .base_execute => {
            const base = try self.pop();
            const xt = try self.wordId(try self.pop());
            if (base < 2 or base > 36) return error.InvalidBase;
            const old = self.currentBase();
            defer self.writeCell(map.base_address, old) catch unreachable;
            try self.writeCell(map.base_address, base);
            try self.executeWord(xt);
        },
        .convert => {
            var address = try self.pop();
            var value: u128 = @bitCast(try self.popDouble());
            const base: u128 = @intCast(try self.validBase());
            while (true) {
                address = std.math.add(i64, address, 1) catch return error.InvalidAddress;
                const at = try self.memoryAddress(address, 1);
                const digit = io.digitValue(self.memory[at]) orelse break;
                if (digit >= base) break;
                value = value *% base +% @as(u128, @intCast(digit));
            }
            try self.pushDouble(@bitCast(value));
            try self.push(address);
        },
        .decimal_dot, .decimal_dot_r, .hex_dot, .h_dot, .ud_dot, .ud_dot_r => {
            const width = if (builtin == .decimal_dot_r or builtin == .ud_dot_r) try self.pop() else 0;
            const value: u128 = if (builtin == .ud_dot or builtin == .ud_dot_r) @bitCast(try self.popDouble()) else @as(u64, @bitCast(try self.pop()));
            const decimal = builtin == .decimal_dot or builtin == .decimal_dot_r;
            const hex = builtin == .hex_dot or builtin == .h_dot;
            const base: u128 = if (decimal) 10 else if (hex) 16 else @intCast(try self.validBase());
            const signed = builtin == .decimal_dot;
            const negative = signed and @as(i64, @bitCast(@as(u64, @truncate(value)))) < 0;
            var magnitude = if (negative) @as(u128, 0 -% @as(u64, @truncate(value))) else value;
            var buffer: [130]u8 = undefined;
            var start = buffer.len;
            while (true) {
                const d: u8 = @intCast(magnitude % base);
                start -= 1;
                buffer[start] = if (d < 10) '0' + d else 'A' + d - 10;
                magnitude /= base;
                if (magnitude == 0) break;
            }
            if (negative or hex) {
                start -= 1;
                buffer[start] = if (negative) '-' else '$';
            }
            var padding = width -| @as(i64, @intCast(buffer.len - start));
            var written: u64 = 0;
            while (padding > 0) : (padding -= 1) {
                if (written & 255 == 0) try checkWorkBlock(self);
                self.write(" ");
                written += 1;
            }
            self.write(buffer[start..]);
            if (builtin != .decimal_dot_r and builtin != .ud_dot_r) self.write(" ");
        },
        else => @compileError(@tagName(builtin) ++ " is not in the words of this file"),
    }
}

/// One budget unit per at most 256 native-loop iterations. The VM's compiled hot
/// loop is unchanged; direct numeric calls also respect an enabled --max-steps.
pub fn checkWorkBlock(self: *State) RuntimeError!void {
    if (comptime defs.debug_enabled) {
        if (self.step_limit != 0) {
            if (self.steps_left == 0) return error.StepLimit;
            self.steps_left -= 1;
        }
    }
}
