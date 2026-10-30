//! Compiling control structures, and skipping input for [IF].

const defs = @import("defs.zig");
const forth = @import("../forth.zig");
const memory_map = @import("memory_map.zig");
const text_input = @import("text_input.zig");
const Builtin = defs.Builtin;
const Control = defs.Control;
const ControlKind = defs.ControlKind;
const RuntimeError = defs.RuntimeError;
const State = forth.State;
const asciiEqlIgnoreCase = text_input.asciiEqlIgnoreCase;
const max_controls = memory_map.max_controls;

pub fn requireCompiling(self: *State) RuntimeError!void {
    if (!self.compiling) return error.CompileOnly;
}

pub fn pushControl(self: *State, kind: ControlKind, address: u16) RuntimeError!void {
    try self.requireCompiling();
    if (self.control_depth == max_controls) return error.ControlStackOverflow;
    self.control_stack[self.control_depth] = .{ .kind = kind, .address = address, .locals = @intCast(self.local_count) };
    self.control_depth += 1;
}

pub fn popControl(self: *State, expected: ControlKind) RuntimeError!Control {
    try self.requireCompiling();
    if (self.control_depth == 0) return error.ControlMismatch;
    self.control_depth -= 1;
    const item = self.control_stack[self.control_depth];
    if (item.kind != expected) {
        self.control_depth += 1;
        return error.ControlMismatch;
    }
    return item;
}

pub fn topControl(self: *State) ?ControlKind {
    if (self.control_depth == 0) return null;
    return self.control_stack[self.control_depth - 1].kind;
}

pub fn compileIf(self: *State) RuntimeError!void {
    try self.requireCompiling();
    const at = try self.emit(.{ .kind = .branch_zero });
    try self.pushControl(.if_branch, at);
}

pub fn compileElse(self: *State) RuntimeError!void {
    const old = try self.popControl(.if_branch);
    const at = try self.emit(.{ .kind = .branch });
    self.patch(old.address, self.code_count);
    // The ELSE part is reached without the locals declared in the IF part.
    self.local_count = old.locals;
    try self.pushControl(.else_branch, at);
}

/// AHEAD: a forward branch taken always, resolved by THEN as ELSE's is.
pub fn compileAhead(self: *State) RuntimeError!void {
    try self.requireCompiling();
    const at = try self.emit(.{ .kind = .branch });
    try self.pushControl(.else_branch, at);
}

pub fn compileThen(self: *State) RuntimeError!void {
    try self.requireCompiling();
    const kind = self.topControl() orelse return error.ControlMismatch;
    if (kind != .if_branch and kind != .else_branch and kind != .while_branch) return error.ControlMismatch;
    self.control_depth -= 1;
    self.patch(self.control_stack[self.control_depth].address, self.code_count);
    // After THEN only the locals visible at the IF remain: the code can be reached
    // along a path that skipped the branch (gforth's rule).
    self.local_count = self.control_stack[self.control_depth].locals;
}

pub fn compileBegin(self: *State) RuntimeError!void {
    try self.pushControl(.begin_loop, self.code_count);
}

pub fn compileEnd(self: *State, unconditional: bool) RuntimeError!void {
    const begin = try self.popControl(.begin_loop);
    _ = try self.emit(.{ .kind = if (unconditional) .branch else .branch_zero, .value = begin.address });
}

/// WHILE ( C: dest -- orig dest ), as the standard has it: the forward branch goes under
/// the BEGIN, so that REPEAT, AGAIN, or UNTIL closes the loop and THEN resolves each
/// further WHILE (BEGIN ... WHILE ... WHILE ... REPEAT THEN), and CS-ROLL idioms work.
pub fn compileWhile(self: *State) RuntimeError!void {
    try self.requireCompiling();
    if (self.topControl() != .begin_loop) return error.ControlMismatch;
    const begin = self.control_stack[self.control_depth - 1];
    self.control_depth -= 1;
    const at = try self.emit(.{ .kind = .branch_zero });
    try self.pushControl(.while_branch, at);
    if (self.control_depth == max_controls) return error.ControlStackOverflow;
    self.control_stack[self.control_depth] = begin;
    self.control_depth += 1;
}

/// REPEAT ( C: orig dest -- ): AGAIN, then THEN for the branch under the BEGIN.
pub fn compileRepeat(self: *State) RuntimeError!void {
    const begin = try self.popControl(.begin_loop);
    const kind = self.topControl() orelse return error.ControlMismatch;
    if (kind != .while_branch and kind != .if_branch and kind != .else_branch) return error.ControlMismatch;
    self.control_depth -= 1;
    const orig = self.control_stack[self.control_depth];
    _ = try self.emit(.{ .kind = .branch, .value = begin.address });
    self.patch(orig.address, self.code_count);
    // The loop is left at WHILE, so the locals declared after it are not visible.
    self.local_count = orig.locals;
}

pub fn compileDo(self: *State, conditional: bool) RuntimeError!void {
    try self.requireCompiling();
    const at = try self.emit(.{ .kind = if (conditional) .q_do_loop else .do_loop });
    try self.pushControl(.do_loop, at);
}

pub fn compileLoop(self: *State, plus: bool) RuntimeError!void {
    const loop = try self.popControl(.do_loop);
    const body: u16 = loop.address + 1;
    _ = try self.emit(.{ .kind = if (plus) .plus_loop else .loop, .value = body });
    self.patch(loop.address, self.code_count);
    // DO always runs the body, so its locals stay visible, except those a LEAVE can
    // skip; ?DO may skip the whole body.
    if (self.code[loop.address].kind == .q_do_loop) {
        self.local_count = loop.locals;
    } else self.local_count = @min(self.local_count, loop.leave_locals);
}

pub fn compileLeave(self: *State) RuntimeError!void {
    try self.requireCompiling();
    var index = self.control_depth;
    while (index > 0) {
        index -= 1;
        const control = &self.control_stack[index];
        if (control.kind == .do_loop) {
            _ = try self.emit(.{ .kind = .leave });
            control.leave_locals = @min(control.leave_locals, @as(u16, @intCast(self.local_count)));
            return;
        }
    }
    return error.ControlMismatch;
}

pub fn compileDoes(self: *State) RuntimeError!void {
    if (!self.compiling or !self.defining) return error.CompileOnly;
    _ = try self.emit(.{ .kind = .does });
    // The DOES> part runs in its own invocation, so earlier locals are out of scope.
    self.local_count = 0;
}

pub fn compileCase(self: *State) RuntimeError!void {
    try self.pushControl(.case_start, 0);
}

pub fn compileOf(self: *State) RuntimeError!void {
    try self.requireCompiling();
    const kind = self.topControl() orelse return error.ControlMismatch;
    if (kind != .case_start and kind != .endof_branch) return error.ControlMismatch;
    _ = try self.emit(.{ .kind = .builtin, .value = @intFromEnum(Builtin.over) });
    _ = try self.emit(.{ .kind = .builtin, .value = @intFromEnum(Builtin.equal) });
    const at = try self.emit(.{ .kind = .branch_zero });
    _ = try self.emit(.{ .kind = .builtin, .value = @intFromEnum(Builtin.drop) });
    try self.pushControl(.of_branch, at);
}

pub fn compileEndof(self: *State) RuntimeError!void {
    const of = try self.popControl(.of_branch);
    const at = try self.emit(.{ .kind = .branch });
    self.patch(of.address, self.code_count);
    // The next OF test is reached without the locals declared in this OF branch.
    self.local_count = of.locals;
    try self.pushControl(.endof_branch, at);
}

pub fn compileEndcase(self: *State) RuntimeError!void {
    try self.requireCompiling();
    _ = try self.emit(.{ .kind = .builtin, .value = @intFromEnum(Builtin.drop) });
    while (true) {
        const kind = self.topControl() orelse return error.ControlMismatch;
        self.control_depth -= 1;
        switch (kind) {
            .case_start => {
                self.local_count = self.control_stack[self.control_depth].locals;
                return;
            },
            .endof_branch => self.patch(self.control_stack[self.control_depth].address, self.code_count),
            else => {
                self.control_depth += 1;
                return error.ControlMismatch;
            },
        }
    }
}

/// [IF] and [ELSE]: skips input words up to the matching [THEN], or to the matching
/// [ELSE] when `to_else` is set, counting nested [IF]s. Skipping may read further lines.
pub fn skipConditional(self: *State, to_else: bool) RuntimeError!void {
    var depth: usize = 0;
    while (true) {
        const token = (try self.nextSourceToken()) orelse return error.ControlMismatch;
        if (asciiEqlIgnoreCase(token, "[IF]")) {
            depth += 1;
        } else if (asciiEqlIgnoreCase(token, "[ELSE]")) {
            if (depth == 0 and to_else) return;
        } else if (asciiEqlIgnoreCase(token, "[THEN]")) {
            if (depth == 0) return;
            depth -= 1;
        }
    }
}
