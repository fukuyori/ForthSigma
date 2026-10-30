//! Defining, compiling, and control-structure words.

const std = @import("std");
const defs = @import("defs.zig");
const forth = @import("../forth.zig");
const integer_math = @import("integer_math.zig");
const memory_map = @import("memory_map.zig");
const Builtin = defs.Builtin;
const Cell = memory_map.Cell;
const Control = defs.Control;
const RuntimeError = defs.RuntimeError;
const State = forth.State;
const doubleCells = defs.doubleCells;
const floatBits = defs.floatBits;
const max_controls = memory_map.max_controls;
const max_gforth_string = memory_map.max_gforth_string;
const state_address = memory_map.state_address;
const truth = integer_math.truth;

/// The built-in words this file executes; executeBuiltin dispatches by this list.
pub const words = [_]Builtin{
    .builds, .immediate, .execute, .index, .index_2, .index_3, .leave, .unloop, .compile_if,
    .compile_else, .compile_ahead, .compile_then, .compile_begin, .compile_end, .compile_again, .compile_while,
    .compile_repeat, .compile_do, .compile_q_do, .compile_loop, .compile_plus_loop, .compile_does,
    .compile_case, .compile_of, .compile_endof, .compile_endcase, .compile_exit, .compile_recurse,
    .question_exit, .question_leave, .compile_question_of, .compile_contof, .compile_next_case,
    .define_colon, .define_variable, .define_fvariable, .define_constant, .define_value,
    .define_two_variable, .define_two_constant, .define_fconstant, .define_fvalue, .define_two_value, .define_buffer, .define_array, .end_definition,
    .tick, .to_body, .literal, .fliteral, .sliteral, .two_literal, .state, .bracket_if, .bracket_else, .bracket_then,
    .bracket_defined, .bracket_undefined, .cs_pick, .cs_roll, .bracket_ifdef, .bracket_ifundef,
    .bracket_do, .bracket_q_do, .bracket_loop, .bracket_plus_loop, .bracket_i, .bracket_begin,
    .bracket_until, .bracket_again, .bracket_while, .bracket_repeat, .bracket_for, .bracket_next,
};

pub fn execute(self: *State, comptime builtin: Builtin) RuntimeError!void {
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
        .compile_ahead => try self.compileAhead(),
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
        // ?EXIT ( flag -- ) and ?LEAVE ( flag -- ) exit or leave when flag is true.
        .question_exit, .question_leave => {
            try self.requireCompiling();
            const at = try self.emit(.{ .kind = .branch_zero });
            if (builtin == .question_exit) {
                _ = try self.emit(.{ .kind = .exit });
            } else try self.compileLeave();
            self.patch(at, self.code_count);
        },
        .compile_question_of => try self.compileQuestionOf(),
        .compile_contof => try self.compileContof(),
        .compile_next_case => try self.compileNextCase(),
        .compile_recurse => {
            if (!self.compiling or !self.defining) return error.CompileOnly;
            _ = try self.emit(.{ .kind = .call, .value = self.current_word });
        },
        .define_colon, .define_variable, .define_fvariable, .define_constant, .define_value, .define_two_variable, .define_two_constant, .define_fconstant, .define_fvalue, .define_two_value, .define_buffer, .define_array => try self.runDefiningWord(builtin),
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
        // [IFDEF] name and [IFUNDEF] name: [DEFINED] name [IF] and [UNDEFINED] name [IF].
        .bracket_ifdef, .bracket_ifundef => {
            const name = (try self.nextSourceToken()) orelse return error.InputUnavailable;
            const found = (self.compiling and self.findLocal(name) != null) or self.lookupRecorded(name);
            if (found != (builtin == .bracket_ifdef)) try self.skipConditional(true);
        },
        // The interpreted loops repeat by going back in the input to where they started,
        // also across the lines of a file, as gforth's do.
        .bracket_do, .bracket_q_do => {
            const start = try self.pop();
            const limit = try self.pop();
            if (builtin == .bracket_q_do and start == limit) {
                return self.skipInterpretLoop(&.{ "[DO]", "[?DO]" }, &.{ "[LOOP]", "[+LOOP]" }, &.{ "[LOOP]", "[+LOOP]" });
            }
            try self.pushInterpretLoop(.{ .kind = .counted, .index = start, .limit = limit, .place = self.saveInputPlace() });
        },
        .bracket_loop, .bracket_plus_loop => {
            const step: Cell = if (builtin == .bracket_plus_loop) try self.pop() else 1;
            const loop = try self.topInterpretLoop(.counted);
            const crossed = integer_math.loopCrossed(loop.index, loop.limit, step);
            loop.index +%= step;
            const again = if (builtin == .bracket_loop) loop.index != loop.limit else !crossed;
            try self.repeatInterpretLoop(again);
        },
        .bracket_i => {
            var index = self.interpret_loop_depth;
            while (index > 0) {
                index -= 1;
                const loop = self.interpret_loops[index];
                if (loop.kind != .begin) return self.push(loop.index);
            }
            return error.ControlMismatch;
        },
        .bracket_for => try self.pushInterpretLoop(.{ .kind = .countdown, .index = try self.pop(), .place = self.saveInputPlace() }),
        .bracket_next => {
            const loop = try self.topInterpretLoop(.countdown);
            const again = loop.index > 0;
            loop.index -%= 1;
            try self.repeatInterpretLoop(again);
        },
        .bracket_begin => try self.pushInterpretLoop(.{ .kind = .begin, .place = self.saveInputPlace() }),
        .bracket_until => {
            const flag = try self.pop();
            _ = try self.topInterpretLoop(.begin);
            try self.repeatInterpretLoop(flag == 0);
        },
        .bracket_again, .bracket_repeat => {
            _ = try self.topInterpretLoop(.begin);
            try self.repeatInterpretLoop(true);
        },
        .bracket_while => {
            const flag = try self.pop();
            _ = try self.topInterpretLoop(.begin);
            if (flag == 0) {
                self.interpret_loop_depth -= 1;
                try self.skipInterpretLoop(&.{"[BEGIN]"}, &.{ "[UNTIL]", "[AGAIN]", "[REPEAT]" }, &.{"[REPEAT]"});
            }
        },
        // CS-PICK and CS-ROLL ( u -- ) copy or move the u-th control-flow entry to the top.
        .cs_pick, .cs_roll => {
            const position = try self.pop();
            if (position < 0 or position >= self.control_depth) return error.ControlMismatch;
            const at = self.control_depth - 1 - @as(usize, @intCast(position));
            const item = self.control_stack[at];
            if (builtin == .cs_pick) {
                if (self.control_depth == max_controls) return error.ControlStackOverflow;
                self.control_stack[self.control_depth] = item;
                self.control_depth += 1;
            } else {
                std.mem.copyForwards(Control, self.control_stack[at .. self.control_depth - 1], self.control_stack[at + 1 .. self.control_depth]);
                self.control_stack[self.control_depth - 1] = item;
            }
        },
        .two_literal => {
            try self.requireCompiling();
            const cells = doubleCells(try self.popDouble());
            _ = try self.emit(.{ .kind = .literal, .value = cells.low });
            _ = try self.emit(.{ .kind = .literal, .value = cells.high });
        },
        // Compile a copy of the string, as S" does; it may lie in a buffer that changes.
        .sliteral => {
            try self.requireCompiling();
            const length = try self.popLength();
            const address = try self.pop();
            if (length > max_gforth_string) return error.StringTooLong;
            const start = try self.memoryAddress(address, length);
            var copy: [max_gforth_string]u8 = undefined;
            @memcpy(copy[0..length], self.memory[start .. start + length]);
            try self.compileCountedString(copy[0..length], .string_literal);
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
            const found = (self.compiling and self.findLocal(name) != null) or self.lookupRecorded(name);
            try self.push(truth(if (builtin == .bracket_defined) found else !found));
        },
        else => @compileError(@tagName(builtin) ++ " is not in the words of this file"),
    }
}
