//! Defining, compiling, and control-structure words.

const defs = @import("defs.zig");
const forth = @import("../forth.zig");
const integer_math = @import("integer_math.zig");
const memory_map = @import("memory_map.zig");
const Builtin = defs.Builtin;
const RuntimeError = defs.RuntimeError;
const State = forth.State;
const floatBits = defs.floatBits;
const state_address = memory_map.state_address;
const truth = integer_math.truth;

pub fn execute(self: *State, builtin: Builtin) RuntimeError!void {
    switch (builtin) {
        .builds => {
            const name = (try self.nextSourceToken()) orelse return error.InvalidDefinition;
            const address = self.data_here;
            const id = try self.appendWord(name, .created, .drop, address);
            self.words[id].data_here_before = address;
            self.last_created_word = id;
        },
        .immediate => {
            if (self.word_count == self.builtin_count) return error.InvalidDefinition;
            self.words[self.word_count - 1].immediate = true;
        },
        .execute => try self.executeWord(try self.wordId(try self.pop())),
        .index => try self.push((try self.loopFrame(1)).index),
        .index_2 => try self.push((try self.loopFrame(2)).index),
        .index_3 => try self.push((try self.loopFrame(3)).index),
        .leave => try self.compileLeave(),
        .unloop => {
            if (self.loop_depth == 0) return error.LoopMismatch;
            self.loop_depth -= 1;
        },
        .compile_if => try self.compileIf(),
        .compile_else => try self.compileElse(),
        .compile_then => try self.compileThen(),
        .compile_begin => try self.compileBegin(),
        .compile_end => try self.compileEnd(false),
        .compile_again => try self.compileEnd(true),
        .compile_while => try self.compileWhile(),
        .compile_repeat => try self.compileRepeat(),
        .compile_do => try self.compileDo(false),
        .compile_q_do => try self.compileDo(true),
        .compile_loop => try self.compileLoop(false),
        .compile_plus_loop => try self.compileLoop(true),
        .compile_does => try self.compileDoes(),
        .compile_case => try self.compileCase(),
        .compile_of => try self.compileOf(),
        .compile_endof => try self.compileEndof(),
        .compile_endcase => try self.compileEndcase(),
        .compile_exit => {
            try self.requireCompiling();
            _ = try self.emit(.{ .kind = .exit });
        },
        .compile_recurse => {
            if (!self.compiling or !self.defining) return error.CompileOnly;
            _ = try self.emit(.{ .kind = .call, .value = self.current_word });
        },
        .define_colon, .define_variable, .define_fvariable, .define_constant, .define_value, .define_two_variable, .define_two_constant, .define_fconstant, .define_array => try self.runDefiningWord(builtin),
        .end_definition => try self.endDefinition(),
        .tick => {
            const name = (try self.nextSourceToken()) orelse return error.InvalidDefinition;
            try self.push(try self.lookupOrFail(name));
        },
        .to_body => try self.push(try self.bodyAddress(try self.wordId(try self.pop()))),
        // Compile the value on the stack into the definition (`[ 2 3 * ] LITERAL`).
        .literal => {
            try self.requireCompiling();
            _ = try self.emit(.{ .kind = .literal, .value = try self.pop() });
        },
        .fliteral => {
            try self.requireCompiling();
            _ = try self.emit(.{ .kind = .float_literal, .value = floatBits(try self.fpop()) });
        },
        .state => try self.push(state_address),
        .bracket_if => {
            if (try self.pop() == 0) try self.skipConditional(true);
        },
        .bracket_else => try self.skipConditional(false),
        .bracket_then => {},
        .bracket_defined, .bracket_undefined => {
            const name = (try self.nextSourceToken()) orelse return error.InputUnavailable;
            // While compiling, a local variable in scope counts as defined, as in gforth.
            const found = (self.compiling and self.findLocal(name) != null) or self.lookup(name) != null;
            try self.push(truth(if (builtin == .bracket_defined) found else !found));
        },
        else => unreachable,
    }
}
