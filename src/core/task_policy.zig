//! Worker-only boundary guards, not a complete safety or admission validator.
const defs = @import("defs.zig");
const Builtin = defs.Builtin;
const Op = defs.Op;
const RuntimeError = defs.RuntimeError;
const inline_calls = @import("inline_calls.zig");

// Build the numeric THROW table at comptime. Internal cancellation is not a
// numeric exception; ordinary THROW needs no per-entry cancellation branch.
pub const numeric_throw_codes = blk: {
    var count: usize = 0;
    for (defs.error_codes) |entry| {
        if (entry[0] != error.TaskCancelled) count += 1;
    }
    var entries: [count]@TypeOf(defs.error_codes[0]) = undefined;
    var index: usize = 0;
    for (defs.error_codes) |entry| {
        if (entry[0] == error.TaskCancelled) continue;
        entries[index] = entry;
        index += 1;
    }
    break :blk entries;
};

// Runtime boundary exclusions only; the full admission allowlist belongs to 1360.
pub fn checkBuiltin(self: anytype, builtin: Builtin) RuntimeError!void {
    const probes = @import("builtin").is_test and @import("task_context.zig").options(self).test_host_probes;
    if (@import("task_permissions.zig").policy(builtin) == .deny and
        !(probes and (builtin == .dot or builtin == .key_ior))) return error.InvalidExecutionToken;
    switch (builtin) {
        .index, .index_2, .index_3, .leave, .unloop, .question_leave, .compile_do, .compile_q_do, .compile_loop, .compile_plus_loop, .positive_do, .unsigned_positive_do, .negative_do, .unsigned_negative_do, .inclusive_negative_do, .unsigned_inclusive_negative_do, .negative_loop, .for_word, .next_word, .memory_up_do, .memory_down_do, .done => return error.InvalidExecutionToken,
        // Source interpreters and assertion bodies can reenter arbitrary words.
        .evaluate, .include, .included, .require, .required, .include_file, .load_block, .thru, .assert_paren, .assert_zero, .assert_one, .assert_two, .assert_three, .fast_throw => return error.InvalidExecutionToken,
        .execute, .execute_exit, .catch_word, .catch_nobt, .throw, .compile_does, .pad, .perform, .exec_limited, .dbg, .read_csv, .infile_execute, .outfile_execute, .to_string_execute, .base_execute, .execute_parsing, .execute_parsing_file, .traverse_wordlist, .in_vocabulary, .in_wordlist, .map_vocs, .string_iter, .string_array_map, .string_tmp, .string_exec, .wrap_xt, .substitute, .string_substitute, .dot_substitute => return error.InvalidExecutionToken,
        else => {},
    }
}

pub fn checkWord(self: anytype, id: u16) RuntimeError!void {
    const word = self.words[self.synonymTarget(id)];
    switch (word.kind) {
        .builtin, .colon, .synonym, .constant, .array, .variable, .created, .field, .fconstant => {},
        else => return error.InvalidExecutionToken,
    }
    if (word.has_does) return error.InvalidExecutionToken;
    if (word.kind == .builtin) try checkBuiltin(self, word.builtin);
}

pub fn checkOp(self: anytype, op: Op) RuntimeError!void {
    switch (op.kind) {
        .do_loop, .q_do_loop, .loop, .plus_loop, .leave, .positive_do, .unsigned_positive_do, .negative_do, .unsigned_negative_do, .inclusive_negative_do, .unsigned_inclusive_negative_do, .for_loop, .memory_up_do, .memory_down_do, .negative_loop, .next_loop, .execute, .local_execute, .does => return error.InvalidExecutionToken,
        .call, .call_colon => {
            const id = if (inline_calls.isInline(op)) inline_calls.wordId(op.value) else try self.wordId(op.value);
            try checkWord(self, id);
        },
        .call_builtin => try checkBuiltin(self, self.words[try self.wordId(op.value)].builtin),
        .builtin => try checkBuiltin(self, @fromBackingInt(@intCast(op.value))),
        .literal, .execution_token, .float_literal, .branch, .branch_zero, .exit, .counted_string, .string_literal => {},
        inline else => |kind| {
            if (comptime defs.isPrimitiveOp(kind)) {
                try checkBuiltin(self, comptime defs.primitiveBuiltin(kind));
            } else return error.InvalidExecutionToken;
        },
    }
}
