//! The checks of --lint. Forth source cannot be read without running it (immediate
//! words and words that read the input decide what the text means), so the files are
//! loaded as usual and the definitions they made are checked afterwards:
//!
//!     REDEFINED     a name that an earlier word already has
//!     UNREACHABLE   code of a definition that no path reaches
//!     STACK DEPTH   paths of a definition that meet with different stack depths
//!     RETURN STACK  a definition that ends with more or fewer cells on the return stack
//!     STACK EFFECT  a stack comment ( a b -- c ) that the code does not keep to
//!     UNUSED        a word that the files never use
//!
//! The stack effect of a definition is worked out from the effects of its operations:
//! those of the built-in words come from the stack comments of their HELP texts, those
//! of the words it calls from their own code. A definition with an operation whose
//! effect is not fixed (EXECUTE, ?DUP, PICK, a DEFER, code after DOES>, ...) is not
//! checked for the three stack findings; the report counts these. For the definitions
//! that call it, such a definition is taken at its stack comment, when it has one. A build with
//! -Ddebug=false has none of this.

const std = @import("std");
const defs = @import("defs.zig");
const forth = @import("../forth.zig");
const memory_map = @import("memory_map.zig");
const words_help = @import("words_help.zig");
const inline_calls = @import("inline_calls.zig");
const debug_log = @import("debug_log.zig");
const Builtin = defs.Builtin;
const State = forth.State;
const max_code = memory_map.max_code;
const max_name = memory_map.max_name;
const max_words = memory_map.max_words;

const builtin_count = @typeInfo(Builtin).@"enum".field_names.len;

/// What an operation or a word does to the stacks: the cells it needs to be there
/// (`takes`) and the change of the depth (`net`), for the data stack, the floating-point
/// stack, and the return stack. `known` is false when it is not fixed.
pub const Effect = struct {
    known: bool = false,
    takes: i16 = 0,
    net: i16 = 0,
    float_takes: i16 = 0,
    float_net: i16 = 0,
    return_net: i16 = 0,
};

/// The stack comment of a definition: `( in -- out )`, and `( F: in -- out )` when it
/// has one. `known` is false for a comment that gives no fixed numbers.
pub const Declared = struct {
    present: bool = false,
    known: bool = false,
    in: i16 = 0,
    out: i16 = 0,
    has_float: bool = false,
    float_in: i16 = 0,
    float_out: i16 = 0,
    /// `in` and `out` with d, ud, and xd counted as one cell: in a comment of the
    /// user's, d may be a name like any other (a distance), not a double.
    single_in: i16 = 0,
    single_out: i16 = 0,
};

/// The depths of the three stacks at a place in a definition, from its start. They are
/// wide enough for any code: at most 65535 operations, each of an effect of 16 bits.
const Depths = struct { data: i64 = 0, float: i64 = 0, returns: i64 = 0 };

/// What the checks keep; the host gives the memory (about 1.5 MiB) with --lint.
pub const Lint = struct {
    declared: [max_words]Declared,
    effects: [max_words]Effect,
    builtin_effects: [builtin_count]Effect,
    used: [max_words]bool,
    /// The depths at each operation of the definition being checked, where a path
    /// came by.
    seen: [max_code]bool,
    depths: [max_code]Depths,
    work: [work_size]u16,
    /// The definition being checked: the ones before it have their effects.
    checking: u16,
    findings: usize,
    unchecked: usize,

    const work_size = 2048;

    pub fn reset(self: *Lint) void {
        @memset(&self.declared, .{});
        self.checking = 0;
        self.findings = 0;
        self.unchecked = 0;
    }

    /// Drops the stack comments of the words `from` to `end`, which FORGET, a MARKER,
    /// or an error removes: the words that take their numbers have their own.
    pub fn forgetWords(self: *Lint, from: usize, end: usize) void {
        if (from < end) @memset(self.declared[from..end], .{});
    }

    /// The stack comment that follows the name of the definition `id`; `body` is the
    /// text between the parentheses. A second comment adds the floating-point stack.
    pub fn declare(self: *Lint, id: u16, body: []const u8) void {
        const entry = &self.declared[id];
        var counts = Counts{};
        const parsed = parseGroup(body, &counts, 2);
        var single = Counts{};
        _ = parseGroup(body, &single, 1);
        if (entry.present) {
            // Only ( F: ... ) may follow the first comment.
            if (!parsed or !counts.float_named or counts.in != 0 or counts.out != 0) return;
            entry.has_float = true;
            entry.float_in = counts.float_in;
            entry.float_out = counts.float_out;
            return;
        }
        entry.* = .{ .present = true, .known = parsed and counts.return_in == 0 and counts.return_out == 0, .in = counts.in, .out = counts.out, .has_float = counts.float_named, .float_in = counts.float_in, .float_out = counts.float_out, .single_in = single.in, .single_out = single.out };
    }

    /// Checks the definitions and writes the findings, one on a line, as
    /// `file:line: CHECK: text`, and then the number of them.
    pub fn report(self: *Lint, machine: *State) void {
        self.builtinEffects();
        @memset(&self.used, false);
        for (machine.uses[0..machine.use_count]) |use| self.used[use.word] = true;
        const uses_complete = machine.use_count < machine.uses.len;
        for (machine.builtin_count..machine.word_count) |index| {
            const id: u16 = @intCast(index);
            const word = machine.words[id];
            self.checking = id;
            const result = if (word.kind == .colon) self.analyze(machine, id) else Analysis{};
            self.effects[id] = result.effect;
            if (!isChecked(machine, word)) continue;
            self.redefined(machine, id);
            if (word.kind == .colon) {
                if (result.unreached) |pc| self.finding(machine, "UNREACHABLE", id, lineOf(machine, pc), "code in {s} that is never reached", .{name(machine, id)});
                if (result.uneven) |pc| self.finding(machine, "STACK DEPTH", id, lineOf(machine, pc), "paths in {s} meet with different stack depths", .{name(machine, id)});
                if (result.return_short) {
                    self.finding(machine, "RETURN STACK", id, 0, "{s} takes a cell from the return stack that it did not put there", .{name(machine, id)});
                } else if (!result.effect.known) {
                    if (result.uneven == null) self.unchecked += 1;
                } else {
                    const returns = result.effect.return_net;
                    if (returns != 0) self.finding(machine, "RETURN STACK", id, 0, "{s} ends with {d} {s} on the return stack", .{ name(machine, id), @abs(returns), if (returns > 0) "more" else "fewer" });
                    self.compare(machine, id, result.effect);
                }
            }
            if (uses_complete and !self.used[id]) self.finding(machine, "UNUSED", id, 0, "{s} is not used in the files", .{name(machine, id)});
        }
        var text: [96]u8 = undefined;
        if (self.unchecked != 0) machine.write(std.fmt.bufPrint(&text, "LINT: {d} DEFINITIONS WITHOUT A FIXED STACK EFFECT WERE NOT CHECKED FOR IT\n", .{self.unchecked}) catch unreachable);
        if (self.findings == 0) machine.write("LINT: NO FINDINGS\n") else machine.write(std.fmt.bufPrint(&text, "LINT: {d} FINDINGS\n", .{self.findings}) catch unreachable);
        if (debug_log.enabled(machine)) debug_log.logLintEnd(machine, self.findings, self.unchecked);
    }

    /// The stack comment against the code: the changes of the depths must be the same,
    /// and the code must not need more cells than the comment names.
    fn compare(self: *Lint, machine: *State, id: u16, effect: Effect) void {
        const declared = self.declared[id];
        if (!declared.present or !declared.known) return;
        const as_doubles = effect.net == declared.out - declared.in and effect.takes <= declared.in;
        const as_singles = effect.net == declared.single_out - declared.single_in and effect.takes <= declared.single_in;
        if (!as_doubles and !as_singles) {
            const in: i32 = @max(effect.takes, declared.in);
            self.finding(machine, "STACK EFFECT", id, 0, "{s} is declared ( {d} -- {d} ) but its code is ( {d} -- {d} )", .{ name(machine, id), declared.in, declared.out, in, in + effect.net });
        }
        // A comment without ( F: ... ) says nothing of the floating-point stack.
        if (!declared.has_float) return;
        if (effect.float_net != declared.float_out - declared.float_in or effect.float_takes > declared.float_in) {
            const in: i32 = @max(effect.float_takes, declared.float_in);
            self.finding(machine, "STACK EFFECT", id, 0, "{s} is declared ( F: {d} -- {d} ) but its code is ( F: {d} -- {d} )", .{ name(machine, id), declared.float_in, declared.float_out, in, in + effect.float_net });
        }
    }

    /// An earlier word of the same word list with the same name.
    fn redefined(self: *Lint, machine: *State, id: u16) void {
        const word = machine.words[id];
        const text = machine.wordName(word);
        if (text.len == 0) return;
        var index: usize = id;
        while (index > 0) {
            index -= 1;
            const earlier = machine.words[index];
            if (earlier.wordlist != word.wordlist or !std.ascii.eqlIgnoreCase(machine.wordName(earlier), text)) continue;
            if (index < machine.builtin_count) {
                self.finding(machine, "REDEFINED", id, 0, "{s} is a built-in word", .{text});
            } else if (earlier.source_file != 0) {
                self.finding(machine, "REDEFINED", id, 0, "{s} was defined at {s}:{d}", .{ text, machine.sourceFileName(earlier.source_file - 1), earlier.source_line });
            } else self.finding(machine, "REDEFINED", id, 0, "{s} was defined before", .{text});
            return;
        }
    }

    fn finding(self: *Lint, machine: *State, comptime check: []const u8, id: u16, line: u32, comptime format: []const u8, args: anytype) void {
        self.findings += 1;
        const word = machine.words[id];
        const file = machine.sourceFileName(word.source_file - 1);
        const at = if (line != 0) line else word.source_line;
        var message: [max_name * 2 + 160]u8 = undefined;
        const text = std.fmt.bufPrint(&message, format, args) catch message[0..0];
        var place: [24]u8 = undefined;
        machine.write(file);
        machine.write(std.fmt.bufPrint(&place, ":{d}: ", .{at}) catch unreachable);
        machine.write(check ++ ": ");
        machine.write(text);
        machine.write("\n");
        if (debug_log.enabled(machine)) debug_log.logLint(machine, check, name(machine, id), file, at, text);
    }

    const Analysis = struct {
        effect: Effect = .{},
        /// An operation that no path reaches.
        unreached: ?u16 = null,
        /// An operation where paths meet with different depths.
        uneven: ?u16 = null,
        /// The return stack was below its depth at the start.
        return_short: bool = false,
    };

    /// Follows every path of the code of the definition `id`.
    fn analyze(self: *Lint, machine: *State, id: u16) Analysis {
        const word = machine.words[id];
        var result = Analysis{};
        if (word.code_end <= word.code_start or word.code_end > machine.code_count) return result;
        const start = word.code_start;
        const end = word.code_end;
        @memset(self.seen[start..end], false);
        var known = true;
        var least = Depths{};
        var exit: ?Depths = null;
        var does_at: ?u16 = null;
        var work_count: usize = 1;
        self.work[0] = start;
        self.depths[start] = .{};
        self.seen[start] = true;
        paths: while (work_count > 0) {
            work_count -= 1;
            var pc = self.work[work_count];
            var now = self.depths[pc];
            // The end of the copied code of a short definition that the path is in.
            var copied_end: u16 = 0;
            // One path, until it ends or meets one that came by.
            while (true) {
                const op = machine.code[pc];
                var effect = self.operationEffect(machine, op);
                if (!effect.known) known = false;
                // What a called definition leaves on the return stack is its own
                // finding, also when its code was copied here.
                if (inline_calls.isInline(op)) copied_end = @max(copied_end, pc + inline_calls.span(op.value));
                if (pc < copied_end) effect.return_net = 0;
                least.data = @min(least.data, now.data - effect.takes);
                least.float = @min(least.float, now.float - effect.float_takes);
                now.data += effect.net;
                now.float += effect.float_net;
                now.returns += effect.return_net;
                least.returns = @min(least.returns, now.returns);
                var next: ?u16 = pc + 1;
                var other: ?u16 = null;
                switch (op.kind) {
                    .exit => next = null,
                    .does => {
                        next = null;
                        if (does_at == null or pc < does_at.?) does_at = pc;
                    },
                    .branch => next = target(op, start, end),
                    .branch_zero, .q_do_loop, .loop, .plus_loop => other = target(op, start, end),
                    .leave => next = leaveTarget(machine, pc, start, end),
                    else => {},
                }
                // ABORT, QUIT, and BYE do not come back: the path ends, and it is not
                // an end of the definition.
                if (neverReturns(machine, pc, start)) continue :paths;
                if (next == null) {
                    if (exit) |first| {
                        if (!std.meta.eql(first, now) and result.uneven == null) result.uneven = pc;
                    } else exit = now;
                }
                if (other) |branch| {
                    if (self.arrive(branch, end, now, &exit, &result)) {
                        if (work_count < work_size) {
                            self.work[work_count] = branch;
                            work_count += 1;
                        } else known = false;
                    }
                }
                const following = next orelse break;
                if (!self.arrive(following, end, now, &exit, &result)) break;
                pc = following;
            }
        }
        // Code that no path reached, but for the end that `;` compiles after a loop
        // without an end, and the code after DOES>, which the words it makes run.
        const checked_end = if (does_at) |pc| pc else end;
        for (start..checked_end) |index| {
            if (self.seen[index]) continue;
            if (index + 1 == end and machine.code[index].kind == .exit) continue;
            result.unreached = @intCast(index);
            break;
        }
        // With an operation whose effect is not known, the depths are not the real ones.
        if (!known) result.uneven = null;
        const last = exit orelse return result;
        if (!known or result.uneven != null) return result;
        // A definition that takes from the return stack what it did not put there.
        if (least.returns < 0) {
            result.return_short = true;
            return result;
        }
        // An effect too large to count (definitions that call definitions that push)
        // is not known. Each number is checked before the effect is given: a result that
        // is left when one does not fit must not say that it is known.
        const takes = std.math.cast(i16, -least.data) orelse return result;
        const net = std.math.cast(i16, last.data) orelse return result;
        const float_takes = std.math.cast(i16, -least.float) orelse return result;
        const float_net = std.math.cast(i16, last.float) orelse return result;
        const return_net = std.math.cast(i16, last.returns) orelse return result;
        result.effect = .{ .known = true, .takes = takes, .net = net, .float_takes = float_takes, .float_net = float_net, .return_net = return_net };
        return result;
    }

    /// A path comes to `pc` with the depths `now`: true when it goes on from there.
    fn arrive(self: *Lint, pc: u16, end: u16, now: Depths, exit: *?Depths, result: *Analysis) bool {
        // The end of the code is the end of the definition.
        if (pc >= end) {
            if (exit.*) |first| {
                if (!std.meta.eql(first, now) and result.uneven == null) result.uneven = end - 1;
            } else exit.* = now;
            return false;
        }
        if (self.seen[pc]) {
            if (!std.meta.eql(self.depths[pc], now) and result.uneven == null) result.uneven = pc;
            return false;
        }
        self.seen[pc] = true;
        self.depths[pc] = now;
        return true;
    }

    /// What one operation does to the stacks.
    fn operationEffect(self: *Lint, machine: *State, op: defs.Op) Effect {
        const unknown = Effect{};
        return switch (op.kind) {
            .call, .call_colon => {
                // The copied code of a short definition follows its mark.
                if (inline_calls.isInline(op)) return fixed(0, 0);
                if (op.value < 0 or op.value >= machine.word_count) return unknown;
                return self.wordEffect(machine, machine.synonymTarget(@intCast(op.value)));
            },
            .builtin => if (op.value >= 0 and op.value < builtin_count) self.builtin_effects[@intCast(op.value)] else unknown,
            .literal, .execution_token, .counted_string, .local_address => fixed(0, 1),
            .string_literal => fixed(0, 2),
            .float_literal => .{ .known = true, .float_net = 1 },
            .branch, .leave, .loop, .print_string, .local_frame, .compile_call, .exit, .does => fixed(0, 0),
            .branch_zero, .plus_loop, .abort_string => fixed(1, 0),
            .do_loop, .q_do_loop => fixed(2, 0),
            .store_value, .add_value => {
                if (op.value < 0 or op.value >= machine.word_count) return unknown;
                return switch (machine.words[@intCast(op.value)].kind) {
                    .fvalue => .{ .known = true, .float_takes = 1, .float_net = -1 },
                    .two_value, .string_value => fixed(2, 0),
                    else => fixed(1, 0),
                };
            },
            .local_store, .local_fetch => {
                const kind: defs.LocalKind = @enumFromInt(op.value >> 32);
                const store = op.kind == .local_store;
                return switch (kind) {
                    .float => if (store) Effect{ .known = true, .float_takes = 1, .float_net = -1 } else Effect{ .known = true, .float_net = 1 },
                    .double => if (store) fixed(2, 0) else fixed(0, 2),
                    else => if (store) fixed(1, 0) else fixed(0, 1),
                };
            },
            .local_execute => unknown,
            // call_builtin and the operations of the frequent built-in words keep the
            // word's id.
            else => {
                if (op.value < 0 or op.value >= machine.builtin_count) return unknown;
                return self.builtin_effects[@intFromEnum(machine.words[@intCast(op.value)].builtin)];
            },
        };
    }

    /// What calling the word `id` does to the stacks.
    fn wordEffect(self: *Lint, machine: *State, id: u16) Effect {
        const word = machine.words[id];
        return switch (word.kind) {
            .builtin => self.builtin_effects[@intFromEnum(word.builtin)],
            // The words are checked in the order they were defined; one that is not
            // before the one in work (a recursion) has no effect yet. A definition
            // whose own effect is not fixed is taken at its stack comment.
            // What a definition leaves on the return stack is its own finding, not one
            // of the definitions that call it.
            .colon => if (id < self.checking and self.effects[id].known) blk: {
                var effect = self.effects[id];
                effect.return_net = 0;
                break :blk effect;
            } else self.declaredEffect(id),
            .constant, .array, .value => fixed(0, 1),
            .variable, .created => if (word.has_does) Effect{} else fixed(0, 1),
            .two_constant, .two_value, .string_value => fixed(0, 2),
            .fconstant, .fvalue => .{ .known = true, .float_net = 1 },
            .field => fixed(1, 1),
            else => .{},
        };
    }

    /// The effect that the stack comment of the definition `id` gives; not known
    /// without one. A comment without ( F: ... ) is taken to leave the floating-point
    /// stack as it is.
    fn declaredEffect(self: *const Lint, id: u16) Effect {
        const declared = self.declared[id];
        if (!declared.present or !declared.known) return .{};
        // A comment with a d in it may mean a double or not.
        if (declared.in != declared.single_in or declared.out != declared.single_out) return .{};
        return .{ .known = true, .takes = declared.in, .net = declared.out - declared.in, .float_takes = declared.float_in, .float_net = declared.float_out - declared.float_in };
    }

    /// The effects of the built-in words, from the stack comments of their HELP texts.
    fn builtinEffects(self: *Lint) void {
        @memset(&self.builtin_effects, .{});
        if (!defs.help_enabled) return;
        for (State.builtin_definitions) |definition| {
            const index = @intFromEnum(definition[1]);
            if (self.builtin_effects[index].known or !fixedEffect(definition[1])) continue;
            // The table HELP uses, without the words the build leaves out: the
            // executable then holds one table, not that one and the whole one.
            for (words_help.help_entries) |entry| {
                if (!std.mem.eql(u8, entry.name, definition[0])) continue;
                self.builtin_effects[index] = parseComments(entry.stack);
                break;
            }
        }
    }
};

/// A built-in word whose stack comment is fixed but which runs other code, so that what
/// it does to the stacks is not.
fn fixedEffect(builtin: Builtin) bool {
    return switch (builtin) {
        .execute, .catch_word, .evaluate, .include, .included, .require, .required, .perform => false,
        else => true,
    };
}

/// The line the operation at `pc` was compiled from, 0 when it is not known.
fn lineOf(machine: *const State, pc: u16) u32 {
    return if (defs.debug_enabled) machine.code_lines[pc] else 0;
}

fn fixed(takes: i16, leaves: i16) Effect {
    return .{ .known = true, .takes = takes, .net = leaves - takes };
}

fn name(machine: *const State, id: u16) []const u8 {
    const text = machine.wordName(machine.words[id]);
    return if (text.len == 0) ":NONAME" else text;
}

/// A word the findings are about: one defined in a file of the user's (the libraries
/// that come with FORTH/Sigma have names in asterisks).
fn isChecked(machine: *State, word: defs.Word) bool {
    // The built-in words that REQUIRE-GRAPHICS and the like add are not the user's.
    if (word.source_file == 0 or word.kind == .builtin) return false;
    const file = machine.sourceFileName(word.source_file - 1);
    return file.len != 0 and file[0] != '*';
}

/// An operation that does not come back: ABORT, QUIT, BYE, and THROW after a number
/// that is not 0 (`1 THROW`). A THROW that comes back took a 0, as its comment says.
fn neverReturns(machine: *const State, pc: u16, start: u16) bool {
    const op = machine.code[pc];
    const builtin: Builtin = switch (op.kind) {
        .builtin => if (op.value >= 0 and op.value < builtin_count) @enumFromInt(op.value) else return false,
        .call, .call_builtin => blk: {
            if (op.value < 0 or op.value >= machine.builtin_count) return false;
            const word = machine.words[@intCast(op.value)];
            if (word.kind != .builtin) return false;
            break :blk word.builtin;
        },
        else => return false,
    };
    if (builtin == .throw) {
        if (pc == start) return false;
        const before = machine.code[pc - 1];
        return before.kind == .literal and before.value != 0;
    }
    return builtin == .abort or builtin == .quit or builtin == .bye;
}

/// Where a branch goes, when that is inside the definition.
fn target(op: defs.Op, start: u16, end: u16) ?u16 {
    if (op.value < start or op.value > end) return null;
    return @intCast(op.value);
}

/// Where LEAVE at `pc` goes: after the innermost DO loop around it.
fn leaveTarget(machine: *const State, pc: u16, start: u16, end: u16) ?u16 {
    var found: ?u16 = null;
    for (machine.code[start..pc]) |op| {
        if (op.kind != .do_loop and op.kind != .q_do_loop) continue;
        if (op.value <= pc or op.value > end) continue;
        found = @intCast(op.value);
    }
    return found;
}

const Counts = struct {
    in: i16 = 0,
    out: i16 = 0,
    float_in: i16 = 0,
    float_out: i16 = 0,
    float_named: bool = false,
    return_in: i16 = 0,
    return_out: i16 = 0,
};

/// The effect that the stack comments of a HELP text give: `( a b -- c )`, with
/// `( F: ... )` and `( R: ... )` for the other stacks. Not known when one of them has
/// alternatives (`|`) or a number of items that is not fixed (`...`).
fn parseComments(text: []const u8) Effect {
    var counts = Counts{};
    var rest = text;
    var any = false;
    while (std.mem.indexOfScalar(u8, rest, '(')) |open| {
        const close = std.mem.indexOfScalarPos(u8, rest, open, ')') orelse return .{};
        if (!parseGroup(rest[open + 1 .. close], &counts, 2)) return .{};
        any = true;
        rest = rest[close + 1 ..];
    }
    if (!any) return .{};
    return .{ .known = true, .takes = counts.in, .net = counts.out - counts.in, .float_takes = counts.float_in, .float_net = counts.float_out - counts.float_in, .return_net = counts.return_out - counts.return_in };
}

/// Counts the items of one comment (the text between the parentheses) into `counts`;
/// false when the comment gives no fixed numbers. A double-cell item counts as
/// `double_cells` cells.
fn parseGroup(body: []const u8, counts: *Counts, double_cells: i16) bool {
    const Stack = enum { data, float, returns, other };
    var stack: Stack = .data;
    var after = false;
    var separated = false;
    var tokens = std.mem.tokenizeAny(u8, body, " \t");
    var first = true;
    while (tokens.next()) |token| {
        if (first) {
            first = false;
            if (std.mem.eql(u8, token, "F:")) {
                stack = .float;
                counts.float_named = true;
                continue;
            } else if (std.mem.eql(u8, token, "R:")) {
                stack = .returns;
                continue;
            } else if (token.len == 2 and token[1] == ':') {
                stack = .other;
                continue;
            }
        }
        if (std.mem.eql(u8, token, "--")) {
            if (separated) return false;
            separated = true;
            after = true;
            continue;
        }
        // Alternatives, and a number of items that is not fixed (`...`, and `..` as in
        // the HELP texts of N>R and NR>).
        if (std.mem.indexOfScalar(u8, token, '|') != null or std.mem.indexOf(u8, token, "..") != null or std.mem.indexOf(u8, token, "*x") != null) return false;
        // What is read from the input is not on a stack.
        if (std.mem.indexOfScalar(u8, token, '"') != null or token[0] == '<') continue;
        const cells: i16 = if (stack == .data and isDouble(token)) double_cells else 1;
        switch (stack) {
            .data => if (after) {
                counts.out += cells;
            } else {
                counts.in += cells;
            },
            .float => if (after) {
                counts.float_out += cells;
            } else {
                counts.float_in += cells;
            },
            .returns => if (after) {
                counts.return_out += cells;
            } else {
                counts.return_in += cells;
            },
            .other => {},
        }
    }
    return separated;
}

/// A double-cell item of a stack comment: d, ud, or xd, and a number after it or none;
/// a sign before it and a prime after it are part of the name (-d, d', ud').
fn isDouble(item: []const u8) bool {
    const token = std.mem.trim(u8, item, "-+'");
    if (token.len == 0) return false;
    const letters: usize = if (std.mem.startsWith(u8, token, "ud") or std.mem.startsWith(u8, token, "xd")) 2 else if (token[0] == 'd') 1 else return false;
    for (token[letters..]) |byte| {
        if (!std.ascii.isDigit(byte)) return false;
    }
    return true;
}

test "stack comments are counted" {
    const plain = parseComments("( x1 x2 -- x2 x1 )");
    try std.testing.expect(plain.known and plain.takes == 2 and plain.net == 0);
    const double = parseComments("( d1 d2 -- d3 )");
    try std.testing.expect(double.takes == 4 and double.net == -2);
    const returns = parseComments("( x -- ) ( R: -- x )");
    try std.testing.expect(returns.takes == 1 and returns.net == -1 and returns.return_net == 1);
    const float = parseComments("( F: r1 r2 -- r3 )");
    try std.testing.expect(float.float_takes == 2 and float.float_net == -1 and float.net == 0);
    const reads = parseComments("( x \"name\" -- )");
    try std.testing.expect(reads.takes == 1 and reads.net == -1);
    try std.testing.expect(!parseComments("( x -- 0 | x x )").known);
    try std.testing.expect(!parseComments("( xu ... x0 u -- xu ... x0 xu )").known);
    try std.testing.expect(!parseComments("( x1 .. xn n -- ) ( R: -- x1 .. xn n )").known);
    try std.testing.expect(!parseComments("no comment").known);
    try std.testing.expect(!isDouble("dx") and isDouble("ud2") and isDouble("d"));
    try std.testing.expect(isDouble("-d") and isDouble("ud'") and !isDouble("-") and !isDouble("dest"));
    try std.testing.expect(parseComments("( d -- -d )").net == 0);
}
