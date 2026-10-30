//! SEE: showing definitions from their operations.

const std = @import("std");
const defs = @import("defs.zig");
const forth = @import("../forth.zig");
const memory_map = @import("memory_map.zig");
const Builtin = defs.Builtin;
const Cell = memory_map.Cell;
const Double = memory_map.Double;
const RuntimeError = defs.RuntimeError;
const State = forth.State;
const bitsFloat = defs.bitsFloat;
const cell_size = memory_map.cell_size;
const fs_precision = memory_map.fs_precision;
const max_code = memory_map.max_code;

pub const SeeRole = enum(u8) { plain, if_branch, else_branch, while_branch, repeat_branch, until_branch, again_branch };

/// Writes the space-separated tokens of SEE, wrapping long bodies.
pub const SeeOutput = struct {
    state: *State,
    column: usize = 0,

    fn token(self: *SeeOutput, width: usize) void {
        if (self.column != 0 and self.column + 1 + width > 72) {
            self.state.write("\n");
            self.column = 0;
        }
        if (self.column == 0) {
            self.state.write("  ");
            self.column = 2;
        } else {
            self.state.write(" ");
            self.column += 1;
        }
        self.column += width;
    }

    fn text(self: *SeeOutput, parts: []const []const u8) void {
        var width: usize = 0;
        for (parts) |part| width += part.len;
        self.token(width);
        for (parts) |part| self.state.write(part);
    }

    fn number(self: *SeeOutput, value: Double) void {
        self.token(self.state.numberWidth(value));
        self.state.writeNumber(value);
    }
};

/// SEE: shows how a word was defined. Colon definitions are decompiled from their
/// operations; branches that form IF ELSE THEN, BEGIN UNTIL/AGAIN, or BEGIN WHILE
/// REPEAT are shown as those words, and any other branch as BRANCH or ?BRANCH with
/// its target offset.
pub fn seeWord(self: *State, id: u16) RuntimeError!void {
    const word = self.words[id];
    const name = self.wordName(word);
    switch (word.kind) {
        .builtin => {
            self.write("BUILT-IN ");
            self.write(name);
        },
        .variable, .array => {
            self.write(if (word.kind == .array) "ARRAY " else "VARIABLE ");
            self.write(name);
            if (word.has_does) {
                self.write("\nDOES>");
                try self.seeBody(word.does_code_start, word.does_code_end);
            }
        },
        .constant, .value => {
            self.writeNumber(if (word.kind == .value) try self.readCell(word.value) else word.value);
            self.write(if (word.kind == .value) " VALUE " else " CONSTANT ");
            self.write(name);
        },
        .fconstant, .fvalue => {
            self.writeFloatExponent(if (word.kind == .fvalue) try self.readFloat(word.value) else bitsFloat(word.value), fs_precision);
            self.write(if (word.kind == .fvalue) " FVALUE " else " FCONSTANT ");
            self.write(name);
        },
        .two_constant => {
            self.writeNumber(try self.readDouble(word.value));
            self.write(". 2CONSTANT ");
            self.write(name);
        },
        .created => {
            self.write("CREATE ");
            self.write(name);
            if (word.has_does) {
                self.write("\nDOES>");
                try self.seeBody(word.does_code_start, word.does_code_end);
            }
        },
        .marker, .vocabulary => {
            self.write(if (word.kind == .marker) "MARKER " else "VOCABULARY ");
            self.write(name);
        },
        .colon => {
            if (name.len == 0) self.write(":NONAME") else {
                self.write(": ");
                self.write(name);
            }
            try self.seeBody(word.code_start, word.code_end);
        },
    }
    if (word.immediate) self.write(" IMMEDIATE");
    self.write("\n");
}

pub fn seeBody(self: *State, start: u16, end: u16) RuntimeError!void {
    var stop: usize = end;
    if (stop > start and self.code[stop - 1].kind == .exit) stop -= 1;
    var roles: [max_code]SeeRole = undefined;
    var thens: [max_code + 1]u16 = undefined;
    var begins: [max_code + 1]u16 = undefined;
    @memset(roles[start..stop], .plain);
    @memset(thens[start .. stop + 1], 0);
    @memset(begins[start .. stop + 1], 0);
    for (start..stop) |pc| {
        const op = self.code[pc];
        if (op.kind != .branch_zero) continue;
        const target: usize = @intCast(op.value);
        if (target < start or target > stop) continue;
        if (target <= pc) {
            roles[pc] = .until_branch;
            begins[target] += 1;
            continue;
        }
        const before = target - 1;
        if (before > pc and self.code[before].kind == .branch and roles[before] == .plain) {
            const other: usize = @intCast(self.code[before].value);
            if (other >= start and other <= pc) {
                roles[pc] = .while_branch;
                roles[before] = .repeat_branch;
                begins[other] += 1;
                continue;
            }
            if (other > before and other <= stop) {
                roles[pc] = .if_branch;
                roles[before] = .else_branch;
                thens[other] += 1;
                continue;
            }
        }
        roles[pc] = .if_branch;
        thens[target] += 1;
    }
    for (start..stop) |pc| {
        const op = self.code[pc];
        if (op.kind != .branch or roles[pc] != .plain) continue;
        const target: usize = @intCast(op.value);
        if (target >= start and target <= pc) {
            roles[pc] = .again_branch;
            begins[target] += 1;
        }
    }
    self.write("\n");
    var out = SeeOutput{ .state = self };
    var pc: usize = start;
    while (true) : (pc += 1) {
        for (0..thens[pc]) |_| out.text(&.{"THEN"});
        if (pc == stop) break;
        for (0..begins[pc]) |_| out.text(&.{"BEGIN"});
        try self.seeOperation(&out, pc, roles[pc], start);
    }
    if (out.column != 0) self.write("\n");
    self.write(";");
}

pub fn seeName(self: *State, id: Cell) []const u8 {
    if (id < 0 or id >= self.word_count) return "<INVALID>";
    const word = &self.words[@intCast(id)];
    return if (word.name_len == 0) "<NONAME>" else self.wordName(word.*);
}

pub fn seeOperation(self: *State, out: *SeeOutput, pc: usize, role: SeeRole, start: usize) RuntimeError!void {
    const op = self.code[pc];
    var offset_text: [24]u8 = undefined;
    switch (op.kind) {
        .call => out.text(&.{self.seeName(op.value)}),
        .compile_call => out.text(&.{ "POSTPONE ", self.seeName(op.value) }),
        .execution_token => out.text(&.{ "['] ", self.seeName(op.value) }),
        .store_value => out.text(&.{ "TO ", self.seeName(op.value) }),
        .builtin => {
            const builtin: Builtin = @enumFromInt(op.value);
            const name = for (self.words[0..self.builtin_count]) |*word| {
                if (word.builtin == builtin) break self.wordName(word.*);
            } else "<BUILT-IN>";
            out.text(&.{name});
        },
        .literal => out.number(op.value),
        .float_literal => {
            // The width of a float is not measured, so a wrapped line may run a little long.
            out.token(1);
            self.writeFloatExponent(bitsFloat(op.value), fs_precision);
        },
        .branch, .branch_zero => switch (role) {
            .if_branch => out.text(&.{"IF"}),
            .else_branch => out.text(&.{"ELSE"}),
            .while_branch => out.text(&.{"WHILE"}),
            .repeat_branch => out.text(&.{"REPEAT"}),
            .until_branch => out.text(&.{"UNTIL"}),
            .again_branch => out.text(&.{"AGAIN"}),
            .plain => {
                const relative: Cell = op.value - @as(Cell, @intCast(start));
                const label = std.fmt.bufPrint(&offset_text, "{d}", .{relative}) catch unreachable;
                out.text(&.{ if (op.kind == .branch) "BRANCH " else "?BRANCH ", label });
            },
        },
        .do_loop => out.text(&.{"DO"}),
        .q_do_loop => out.text(&.{"?DO"}),
        .loop => out.text(&.{"LOOP"}),
        .plus_loop => out.text(&.{"+LOOP"}),
        .leave => out.text(&.{"LEAVE"}),
        .print_string, .string_literal => {
            const at = try self.memoryAddress(op.value, 1);
            const length = self.memory[at];
            _ = try self.memoryAddress(op.value + 1, length);
            out.text(&.{ if (op.kind == .print_string) ".\" " else "S\" ", self.memory[at + 1 .. at + 1 + length], "\"" });
        },
        .does => out.text(&.{"DOES>"}),
        .exit => out.text(&.{"EXIT"}),
        .local_frame => {},
        .local_store, .local_fetch, .local_address, .local_execute => {
            const slot = std.fmt.bufPrint(&offset_text, "L#{d}", .{@divTrunc(op.value & 0xffff_ffff, cell_size)}) catch unreachable;
            const prefix: []const u8 = switch (op.kind) {
                .local_store => "TO ",
                .local_address => "ADDR ",
                .local_execute => "EXECUTE ",
                else => "",
            };
            out.text(&.{ prefix, slot });
        },
    }
}
