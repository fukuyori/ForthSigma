//! Compilation-token words and explicit interpretation restrictions.
const forth = @import("../forth.zig");
const defs = @import("defs.zig");
const semantics = @import("word_semantics.zig");
const map = @import("memory_map.zig");
pub const words = [_]defs.Builtin{ .comp_tick, .bracket_comp_tick, .compile_only, .restrict_word, .execute_exit, .postpone_comma, .select_word, .bracket_noop };

pub fn execute(self: *forth.State, comptime word: defs.Builtin) forth.RuntimeError!void {
    switch (word) {
        .comp_tick, .bracket_comp_tick => {
            if (word == .bracket_comp_tick) {
                try self.requireCompiling();
                if (map.max_code - self.code_count < 2) return error.CodeFull;
            } else if (self.data_stack.len - self.data_depth < 2) return error.StackOverflow;
            const name = (try self.nextSourceToken()) orelse return error.InvalidDefinition;
            const action = semantics.compilation(self, try self.lookupOrFail(name));
            const first = semantics.interpretation(self, action.target);
            const second = self.builtinWord(if (action.execute) .execute else .compile_comma);
            if (word == .bracket_comp_tick) {
                _ = try self.emit(.{ .kind = .execution_token, .value = first });
                _ = try self.emit(.{ .kind = .execution_token, .value = second });
            } else {
                try self.push(first);
                try self.push(second);
            }
        },
        .compile_only, .restrict_word => {
            if (self.word_count == self.builtin_count or self.words[self.latestWord()].name_len == 0) return error.InvalidDefinition;
            self.words[self.latestWord()].compile_only = true;
        },
        .execute_exit => {
            try self.requireCompiling();
            if (map.max_code - self.code_count < 2) return error.CodeFull;
            _ = try self.emit(.{ .kind = .execute, .value = self.builtinWord(.execute) });
            _ = try self.emit(.{ .kind = .exit });
        },
        .postpone_comma => {
            if (!self.defining) return error.CompileOnly;
            try self.requireDepth(2);
            const second = try self.wordId(try self.peek(0));
            const first = try self.wordId(try self.peek(1));
            // Keep both tokens intact until validation has succeeded.
            if (second == self.builtinWord(.execute)) {
                try self.compileCall(first);
            } else if (second == self.builtinWord(.compile_comma)) {
                _ = try self.emit(.{ .kind = .compile_call, .value = first });
            } else {
                if (map.max_code - self.code_count < 2) return error.CodeFull;
                _ = try self.emit(.{ .kind = .execution_token, .value = first });
                try self.compileCall(second);
            }
            self.data_depth -= 2;
        },
        .select_word => {
            try self.requireDepth(3);
            const flag = self.data_stack[self.data_depth - 1];
            const selected = self.data_stack[self.data_depth - (if (flag != 0) @as(usize, 3) else 2)];
            self.data_depth -= 2;
            self.data_stack[self.data_depth - 1] = selected;
        },
        .bracket_noop => {},
        else => unreachable,
    }
}
