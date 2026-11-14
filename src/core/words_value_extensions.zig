//! Address-valued storage and scoped deferred actions; no native pointers in images.
const forth = @import("../forth.zig");
const defs = @import("defs.zig");
const map = @import("memory_map.zig");
const registry = @import("address_registry.zig");
pub const words = [_]defs.Builtin{ .avalue, .addressable, .addr, .compile_addr, .colon_is, .preserve, .wrap_xt };

/// Linked only while a host scope is on the stack. Dictionary invalidation must
/// not let cleanup store an old action into a removed/reused deferred cell.
pub const Guard = struct {
    previous: ?*Guard,
    target: u16,
    valid: bool = true,
    saved_action: map.Cell = -1,
    saved_valid: bool = true,
    depth: u8,
};
pub fn pushGuard(self: *forth.State, guard: *Guard, target: u16) forth.RuntimeError!void {
    const depth = if (self.wrap_guard) |previous| previous.depth else 0;
    if (depth == 64) return error.ReturnStackOverflow;
    guard.* = .{ .previous = self.wrap_guard, .target = target, .depth = depth + 1 };
    self.wrap_guard = guard;
}
pub fn popGuard(self: *forth.State, guard: *const Guard) void {
    self.wrap_guard = guard.previous;
}
pub fn invalidate(self: *forth.State, first: u16) void {
    var guard = self.wrap_guard;
    while (guard) |g| : (guard = g.previous) {
        if (g.target >= first) g.valid = false;
        if (g.saved_action >= first) {
            g.saved_action = -1;
            g.saved_valid = false;
        }
    }
    if (self.colon_is_word) |id| {
        if (id >= first or self.colon_is_target >= first) self.colon_is_word = null;
    }
}
fn deferred(self: *forth.State, id: u16) forth.RuntimeError!u16 {
    const target = self.synonymTarget(id);
    if (self.words[target].kind != .deferred) return error.InvalidExecutionToken;
    return target;
}
pub fn finishColon(self: *forth.State, id: u16) forth.RuntimeError!void {
    if (self.colon_is_word != id) return;
    const target = try deferred(self, try self.wordId(self.colon_is_target));
    try self.writeCell(self.words[target].value, id);
    self.colon_is_word = null;
}
pub fn execute(self: *forth.State, comptime word: defs.Builtin) forth.RuntimeError!void {
    switch (word) {
        // Every Sigma value already has stable backing storage. The annotation
        // needs no one-shot host state and does not affect later definitions.
        .addressable => {},
        .avalue => {
            try self.requireDepth(1);
            const value = try self.peek(0);
            const name = (try @import("quotations.zig").definitionName(self)) orelse return error.InvalidDefinition;
            try registry.ensureRoom(self, .memory, self.data_here);
            const id = try self.appendDataWord(name, .value, map.cell_size);
            try self.writeCell(self.words[id].value, value);
            try registry.registerMemory(self, self.words[id].value);
            self.data_depth -= 1;
        },
        .addr, .compile_addr => {
            const compile = word == .compile_addr;
            if (compile and !self.defining) return error.CompileOnly;
            const name = (try self.nextSourceToken()) orelse return error.InvalidDefinition;
            if (compile) if (self.findLocal(name)) |local| {
                if (local.variable) return error.InvalidDefinition;
                _ = try self.emit(.{ .kind = .local_address, .value = forth.State.localOperand(local) });
                return;
            };
            const id = self.synonymTarget(try self.lookupOrFail(name));
            switch (self.words[id].kind) {
                .value, .fvalue, .two_value, .string_value, .deferred => {},
                else => return error.InvalidDefinition,
            }
            if (compile) {
                if (map.max_code - self.code_count < 2) return error.CodeFull;
                _ = try self.emit(.{ .kind = .execution_token, .value = id });
                _ = try self.emit(.{ .kind = .builtin, .value = @backingInt(defs.Builtin.to_body) });
            } else try self.push(self.words[id].value);
        },
        .colon_is => {
            if (self.defining) return error.InvalidDefinition;
            const name = (try self.nextSourceToken()) orelse return error.InvalidDefinition;
            const target = self.synonymTarget(try self.lookupOrFail(name));
            if (self.words[target].kind != .deferred) return error.InvalidDefinition;
            const id = try self.appendAnonymousColon();
            self.beginDefinition(id);
            self.colon_is_word = id;
            self.colon_is_target = target;
        },
        .preserve => {
            try self.requireCompiling();
            const name = (try self.nextSourceToken()) orelse return error.InvalidDefinition;
            const id = self.synonymTarget(try self.lookupOrFail(name));
            if (self.words[id].kind != .deferred) return error.InvalidDefinition;
            const action = try self.readCell(self.words[id].value);
            if (action != -1) _ = try self.wordId(action);
            if (map.max_code - self.code_count < 2) return error.CodeFull;
            _ = try self.emit(.{ .kind = if (action == -1) .literal else .execution_token, .value = action });
            _ = try self.emit(.{ .kind = .store_value, .value = id });
        },
        .wrap_xt => {
            try self.requireDepth(3);
            const action = try self.wordId(try self.peek(2));
            const target = try deferred(self, try self.wordId(try self.peek(1)));
            const callback = try self.wordId(try self.peek(0));
            const slot = self.words[target].value;
            const old = try self.readCell(slot);
            if (old != -1) _ = try self.wordId(old);
            var guard: Guard = undefined;
            try pushGuard(self, &guard, target);
            guard.saved_action = old;
            defer {
                if (guard.valid) self.writeCell(slot, guard.saved_action) catch unreachable;
                popGuard(self, &guard);
            }
            try self.writeCell(slot, action);
            self.data_depth -= 3;
            try self.executeWord(callback);
            if (!guard.valid or !guard.saved_valid) return error.InvalidExecutionToken;
        },
        else => unreachable,
    }
}
