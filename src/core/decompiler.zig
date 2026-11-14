//! SEE: showing definitions from their operations.

const std = @import("std");
const inline_calls = @import("inline_calls.zig");
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
        .forward => {
            self.write("FORWARD ");
            self.write(name);
        },
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
            self.write(if (word.kind == .value) (if (@import("address_registry.zig").index(self, .memory, word.value) != null) " AVALUE " else " VALUE ") else " CONSTANT ");
            self.write(name);
        },
        .fconstant, .fvalue => {
            if (defs.float_enabled) self.writeFloatExponent(if (word.kind == .fvalue) try self.readFloat(word.value) else bitsFloat(word.value), fs_precision) else self.write("?");
            self.write(if (word.kind == .fvalue) " FVALUE " else " FCONSTANT ");
            self.write(name);
        },
        .string_value => {
            const text = try self.fetchString(word.value);
            self.write("S\" ");
            self.writeMemory(text.address, text.length);
            self.write("\" $VALUE ");
            self.write(name);
        },
        .two_constant, .two_value => {
            self.writeNumber(try self.readDouble(word.value));
            self.write(if (word.kind == .two_value) ". 2VALUE " else ". 2CONSTANT ");
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
        .synonym => {
            self.write("SYNONYM ");
            self.write(name);
            self.write(" ");
            self.write(seeName(self, word.value));
        },
        // A DEFER shows its action the way it would be set.
        .deferred => {
            self.write("DEFER ");
            self.write(name);
            const action = try self.readCell(word.value);
            if (action >= 0 and action < self.word_count) {
                self.write("\n' ");
                self.write(self.seeName(action));
                self.write(" IS ");
                self.write(name);
            }
        },
        .field => {
            self.writeNumber(word.value);
            self.write(" +FIELD ");
            self.write(name);
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
    var dones: [max_code + 1]u16 = undefined;
    @memset(roles[start..stop], .plain);
    @memset(thens[start .. stop + 1], 0);
    @memset(begins[start .. stop + 1], 0);
    @memset(dones[start .. stop + 1], 0);
    for (self.code[start..stop]) |op| {
        const loops = @import("words_loops.zig");
        if (loops.isEntry(op.kind) and op.value & loops.done_flag != 0) {
            const at = loops.target(op.value);
            if (at >= start and at <= stop) dones[@intCast(at)] += 1;
        }
    }
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
        for (0..dones[pc]) |_| out.text(&.{"DONE"});
        if (pc == stop) break;
        for (0..begins[pc]) |_| out.text(&.{"BEGIN"});
        try self.seeOperation(&out, pc, roles[pc], start);
        if (inline_calls.isInline(self.code[pc])) pc += inline_calls.span(self.code[pc].value) - 1;
    }
    if (out.column != 0) self.write("\n");
    self.write(";");
}

pub fn seeName(self: *State, id: Cell) []const u8 {
    if (id < 0 or id >= self.word_count) return "<INVALID>";
    const word = &self.words[@intCast(id)];
    if (word.name_len != 0) return self.wordName(word.*);
    // A built-in word the build leaves out has no name in the dictionary; a definition
    // loaded from a build that has it shows it by its own name.
    return if (word.kind == .builtin) builtinName(word.builtin) else "<NONAME>";
}

/// The name a built-in word is defined with, whether or not the build has it.
pub fn builtinName(builtin: Builtin) []const u8 {
    // These entries intentionally have no searchable name. Display their action
    // rather than losing the operation in SEE and single-step output.
    switch (builtin) {
        .compile_addr => return "POSTPONE ADDR",
        .compile_assign_to => return "POSTPONE TO",
        .compile_assign_is => return "POSTPONE IS",
        .compile_assign_plus_to => return "POSTPONE +TO",
        .compile_assignment_action_of => return "POSTPONE ACTION-OF",
        .postpone_s_quote => return "POSTPONE S\"",
        .postpone_print_quote => return "POSTPONE .\"",
        .postpone_left_bracket => return "POSTPONE [",
        .postpone_right_bracket => return "POSTPONE ]",
        .postpone_parsed_string => return "POSTPONE (PARSED-STRING)",
        else => {},
    }
    for (State.builtin_definitions) |definition| {
        if (definition[1] == builtin and definition[0].len != 0) return definition[0];
    }
    return "<BUILT-IN>";
}

pub fn seeOperation(self: *State, out: *SeeOutput, pc: usize, role: SeeRole, start: usize) RuntimeError!void {
    const op = self.code[pc];
    var offset_text: [24]u8 = undefined;
    switch (op.kind) {
        .call, .call_builtin, .call_colon => out.text(&.{self.seeName(if (inline_calls.isInline(op)) inline_calls.wordId(op.value) else op.value)}),
        inline else => |kind| {
            _ = comptime defs.primitiveBuiltin(kind);
            out.text(&.{self.seeName(op.value)});
        },
        .compile_call => out.text(&.{ "POSTPONE ", self.seeName(op.value) }),
        .execution_token => out.text(&.{ "['] ", self.seeName(op.value) }),
        .store_value => out.text(&.{ "TO ", self.seeName(op.value) }),
        .add_value => out.text(&.{ "+TO ", self.seeName(op.value) }),
        .builtin => {
            const builtin: Builtin = @fromBackingInt(@intCast(op.value));
            const name = for (self.words[0..self.builtin_count]) |*word| {
                if (word.builtin == builtin and word.name_len != 0) break self.wordName(word.*);
            } else builtinName(builtin);
            out.text(&.{name});
        },
        .literal => out.number(op.value),
        .float_literal => {
            // The width of a float is not measured, so a wrapped line may run a little long.
            out.token(1);
            if (defs.float_enabled) self.writeFloatExponent(bitsFloat(op.value), fs_precision) else self.write("?");
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
        .positive_do => out.text(&.{"+DO"}),
        .unsigned_positive_do => out.text(&.{"U+DO"}),
        .negative_do => out.text(&.{"-DO"}),
        .unsigned_negative_do => out.text(&.{"U-DO"}),
        .inclusive_negative_do => out.text(&.{"-[DO"}),
        .unsigned_inclusive_negative_do => out.text(&.{"U-[DO"}),
        .for_loop => out.text(&.{"FOR"}),
        .memory_up_do => out.text(&.{"MEM+DO"}),
        .memory_down_do => out.text(&.{"MEM-DO"}),
        .negative_loop => out.text(&.{"-LOOP"}),
        .next_loop => out.text(&.{"NEXT"}),
        .do_loop => out.text(&.{"DO"}),
        .q_do_loop => out.text(&.{"?DO"}),
        .loop => out.text(&.{"LOOP"}),
        .plus_loop => out.text(&.{"+LOOP"}),
        .leave => out.text(&.{"LEAVE"}),
        .print_string, .string_literal, .counted_string, .abort_string => {
            const at = try self.memoryAddress(op.value, 1);
            const length = self.memory[at];
            _ = try self.memoryAddress(op.value + 1, length);
            const opening = switch (op.kind) {
                .print_string => ".\" ",
                .counted_string => "C\" ",
                .abort_string => "ABORT\" ",
                else => "S\" ",
            };
            out.text(&.{ opening, self.memory[at + 1 .. at + 1 + length], "\"" });
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
