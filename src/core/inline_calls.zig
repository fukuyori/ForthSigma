//! Bounded inlining of straight-line colon definitions. Guards preserve call limits.
const defs = @import("defs.zig");
const forth = @import("../forth.zig");
const limits = @import("memory_map.zig");
pub const max_body = 4;

pub fn isInline(op: defs.Op) bool {
    return op.kind == .call_colon and op.value >= (@as(forth.Cell, 1) << 32);
}

// Low 16 bits: original word id; next 16: span including this guard; next 16:
// required call-depth headroom relative to the non-inlined caller.
pub fn wordId(value: forth.Cell) u16 {
    return @truncate(@as(u64, @bitCast(value)));
}
pub fn span(value: forth.Cell) u16 {
    return @truncate(@as(u64, @bitCast(value)) >> 16);
}
pub fn depth(value: forth.Cell) u16 {
    return @truncate(@as(u64, @bitCast(value)) >> 32);
}
pub fn operand(id: u16, length: u16, nesting: u16) forth.Cell {
    return @as(forth.Cell, id) | (@as(forth.Cell, length) << 16) | (@as(forth.Cell, nesting) << 32);
}

fn body(self: *const forth.State, id: u16) ?[]const defs.Op {
    const word = self.words[id];
    if (word.kind != .colon or word.immediate or word.locals_size != 0) return null;
    if (word.code_end <= word.code_start or word.code_end > self.code_count) return null;
    if (word.code_end - word.code_start <= 1) return null;
    if (self.code[word.code_end - 1].kind != .exit) return null;
    const ops = self.code[word.code_start .. word.code_end - 1];
    if (ops.len > max_body) return null;
    for (ops) |op| {
        if (defs.isPrimitiveOp(op.kind)) continue;
        switch (op.kind) {
            .literal, .float_literal, .execution_token => {},
            .call_colon => if (!isInline(op) or depth(op.value) >= @min(self.frames.len, 65535)) return null,
            else => return null,
        }
    }
    return ops;
}

pub fn compile(self: *forth.State, id: u16) forth.RuntimeError!bool {
    // The trace shows a word when it is called and when it returns.
    if (defs.debug_enabled and self.tracing) return false;
    if (self.defining and id == self.current_word) return false;
    const ops = body(self, id) orelse return false;
    // Fall back to an ordinary call if expansion would exhaust the code area.
    if (@as(usize, self.code_count) + ops.len + 1 >= limits.max_code) return false;
    _ = try self.emit(.{ .kind = .call_colon, .value = operand(id, @intCast(ops.len + 1), 1) });
    for (ops) |original| {
        var op = original;
        if (isInline(op)) op.value = operand(wordId(op.value), span(op.value), depth(op.value) + 1);
        _ = try self.emit(op);
    }
    return true;
}

fn mark(targets: []u8, target: usize) void {
    targets[target / 8] |= @as(u8, 1) << @as(u3, @intCast(target % 8));
}
fn marked(targets: []const u8, target: usize) bool {
    return targets[target / 8] & (@as(u8, 1) << @as(u3, @intCast(target % 8))) != 0;
}

/// Saved expansions are an ordinary call followed by branches over the reserved
/// slots. Rebuild only exact padding spans with no other entry point inside them.
pub fn restore(self: *forth.State) void {
    if (defs.debug_enabled and self.tracing) return;
    var targets: [(limits.max_code + 7) / 8]u8 = @splat(0);
    for (self.words[0..self.word_count]) |word| {
        if (word.kind == .colon) {
            if (word.code_start <= self.code_count) mark(&targets, word.code_start);
            if (word.code_end <= self.code_count) mark(&targets, word.code_end);
        }
        if (word.has_does) {
            if (word.does_code_start <= self.code_count) mark(&targets, word.does_code_start);
            if (word.does_code_end <= self.code_count) mark(&targets, word.does_code_end);
        }
    }
    for (self.code[0..self.code_count]) |op| switch (op.kind) {
        .branch, .branch_zero, .do_loop, .q_do_loop, .loop, .plus_loop => {
            if (op.value >= 0 and op.value <= self.code_count) mark(&targets, @intCast(op.value));
        },
        else => {},
    };
    var pc: usize = 0;
    while (pc + 1 < self.code_count) : (pc += 1) {
        const call = self.code[pc];
        if (call.kind != .call_colon or isInline(call) or call.value < 0 or call.value >= self.word_count) continue;
        const id: u16 = @intCast(call.value);
        if (self.words[id].code_end > pc) continue;
        const ops = body(self, id) orelse continue;
        const end = pc + ops.len + 1;
        if (end > self.code_count) continue;
        const valid = for (pc + 1..end) |index| {
            const padding = self.code[index];
            if (marked(&targets, index) or padding.kind != .branch or padding.value != end) break false;
        } else true;
        if (!valid) continue;
        self.code[pc] = .{ .kind = .call_colon, .value = operand(id, @intCast(ops.len + 1), 1) };
        for (ops, pc + 1..) |original, index| {
            var op = original;
            if (isInline(op)) op.value = operand(wordId(op.value), span(op.value), depth(op.value) + 1);
            self.code[index] = op;
        }
        pc = end - 1;
    }
}
