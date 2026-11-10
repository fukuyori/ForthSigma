//! The profile of --profile: how often each colon definition was called and how many
//! operations of compiled code it ran, shown on standard error when the program ends.
//! The counts are of operations, not of time, so that two runs of the same program give
//! the same profile. A build with -Ddebug=false has none of this.

const std = @import("std");
const forth = @import("../forth.zig");
const memory_map = @import("memory_map.zig");
const words_debug = @import("words_debug.zig");
const words_tools = @import("words_tools.zig");
const State = forth.State;
const max_code = memory_map.max_code;
const max_name = memory_map.max_name;
const max_words = memory_map.max_words;

/// The counts of one run. The host gives the memory (about 2 MiB) when it wants a
/// profile; `reset` makes it ready.
pub const Profile = struct {
    /// How often each operation ran.
    op_counts: [max_code]u64,
    /// How often each word was called, and the operations run between its start and
    /// its end, those of the words it called included. A word that is running already
    /// (a recursion) does not count its inner runs again.
    calls: [max_words]u64,
    total: [max_words]u64,
    active: [max_words]u16,
    /// The words that are running, innermost last. `depth` goes on counting when they
    /// no longer fit, so that the ends still match the starts.
    stack: [stack_size]Entry,
    depth: usize,
    /// All the operations run so far.
    operations: u64,
    /// The words in the order of the report.
    order: [max_words]u16,

    const stack_size = 1024;
    const Entry = struct { word: u16, start: u64, counted: bool };

    pub fn reset(self: *Profile) void {
        @memset(&self.op_counts, 0);
        @memset(&self.calls, 0);
        @memset(&self.total, 0);
        @memset(&self.active, 0);
        self.depth = 0;
        self.operations = 0;
    }

    pub inline fn countOperation(self: *Profile, pc: u16) void {
        self.op_counts[pc] +%= 1;
        self.operations +%= 1;
    }

    pub fn enter(self: *Profile, word: u16) void {
        self.calls[word] +%= 1;
        if (self.depth < stack_size) {
            self.stack[self.depth] = .{ .word = word, .start = self.operations, .counted = self.active[word] == 0 };
            self.active[word] +|= 1;
        }
        self.depth += 1;
    }

    pub fn leave(self: *Profile) void {
        if (self.depth == 0) return;
        self.depth -= 1;
        if (self.depth >= stack_size) return;
        const entry = self.stack[self.depth];
        self.active[entry.word] -|= 1;
        if (entry.counted) self.total[entry.word] +%= self.operations - entry.start;
    }

    /// Ends the words above `depth`, which an error ended.
    pub fn unwind(self: *Profile, depth: usize) void {
        while (self.depth > depth) self.leave();
    }

    /// The report: a line of the whole, then a line for each definition that was called
    /// or ran operations, the one that ran the most operations of its own first.
    ///
    ///     PROFILE: 1234 OPERATIONS
    ///          CALLS        SELF       TOTAL  WORD
    ///             20          80          80  SQUARE prog.fs:2
    ///             10         120         200  SUMSQ prog.fs:3
    ///
    /// SELF is the operations of the definition's own code (those after DOES> count for
    /// the defining word), TOTAL those between its start and its end.
    pub fn show(self: *Profile, machine: *State) void {
        self.unwind(0);
        var line: [max_name + 160]u8 = undefined;
        {
            var writer = words_debug.LineWriter{ .buffer = &line };
            writer.add("PROFILE: ");
            writer.number(self.operations);
            writer.add(" OPERATIONS\n");
            words_tools.writeError(machine, writer.text());
        }
        var count: usize = 0;
        for (machine.words[machine.builtin_count..machine.word_count], machine.builtin_count..) |word, id| {
            if (word.kind != .colon) continue;
            if (self.calls[id] == 0 and selfOperations(self, machine, @intCast(id)) == 0) continue;
            self.order[count] = @intCast(id);
            count += 1;
        }
        if (count == 0) return;
        const Context = struct {
            profile: *Profile,
            machine: *State,
            fn before(context: @This(), a: u16, b: u16) bool {
                const self_a = selfOperations(context.profile, context.machine, a);
                const self_b = selfOperations(context.profile, context.machine, b);
                if (self_a != self_b) return self_a > self_b;
                return a < b;
            }
        };
        std.mem.sort(u16, self.order[0..count], Context{ .profile = self, .machine = machine }, Context.before);
        words_tools.writeError(machine, "     CALLS        SELF       TOTAL  WORD\n");
        for (self.order[0..count]) |id| {
            const word = machine.words[id];
            var writer = words_debug.LineWriter{ .buffer = &line };
            column(&writer, self.calls[id], 10);
            column(&writer, selfOperations(self, machine, id), 12);
            column(&writer, self.total[id], 12);
            writer.add("  ");
            const name = machine.wordName(word);
            writer.add(if (name.len == 0) ":NONAME" else name);
            if (word.source_file != 0 and word.source_line != 0) {
                writer.add(" ");
                writer.add(machine.sourceFileName(word.source_file - 1));
                writer.add(":");
                writer.number(word.source_line);
            }
            writer.add("\n");
            words_tools.writeError(machine, writer.text());
        }
    }
};

/// The operations that the code of the definition `id` ran.
fn selfOperations(profile: *const Profile, machine: *const State, id: u16) u64 {
    const word = machine.words[id];
    if (word.code_end < word.code_start or word.code_end > machine.code_count) return 0;
    var sum: u64 = 0;
    for (profile.op_counts[word.code_start..word.code_end]) |ran| sum +%= ran;
    return sum;
}

/// `value` at the right of a column `width` wide.
fn column(writer: *words_debug.LineWriter, value: u64, width: usize) void {
    var digits: [24]u8 = undefined;
    const text = std.fmt.bufPrint(&digits, "{d}", .{value}) catch unreachable;
    for (text.len..@max(width, text.len)) |_| writer.add(" ");
    writer.add(text);
}
