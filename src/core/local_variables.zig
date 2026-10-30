//! Local variables: declarations, frames, and access.

const std = @import("std");
const defs = @import("defs.zig");
const forth = @import("../forth.zig");
const memory_map = @import("memory_map.zig");
const text_input = @import("text_input.zig");
const Cell = memory_map.Cell;
const Local = defs.Local;
const LocalKind = defs.LocalKind;
const OpKind = defs.OpKind;
const RuntimeError = defs.RuntimeError;
const State = forth.State;
const UCell = memory_map.UCell;
const asciiEqlIgnoreCase = text_input.asciiEqlIgnoreCase;
const cell_size = memory_map.cell_size;
const max_locals = memory_map.max_locals;
const max_name = memory_map.max_name;

pub fn findLocal(self: *State, name: []const u8) ?Local {
    var index = self.local_count;
    while (index > 0) {
        index -= 1;
        const local = self.locals[index];
        if (asciiEqlIgnoreCase(local.name[0..local.name_len], name)) return local;
    }
    return null;
}

pub fn localOperand(local: Local) Cell {
    return @as(Cell, local.offset) | (@as(Cell, @intFromEnum(local.kind)) << 32);
}

pub fn compileLocalReference(self: *State, local: Local) RuntimeError!void {
    const kind: OpKind = if (local.variable) .local_address else if (local.kind == .xt) .local_execute else .local_fetch;
    _ = try self.emit(.{ .kind = kind, .value = localOperand(local) });
}

pub fn addLocal(self: *State, name: []const u8, kind: LocalKind, variable: bool) RuntimeError!Local {
    if (self.local_count == max_locals) return error.InvalidDefinition;
    if (name.len == 0 or name.len > max_name) return error.NameTooLong;
    const size: u16 = if (kind == .double) 2 * cell_size else cell_size;
    var local = Local{ .name_len = @intCast(name.len), .kind = kind, .variable = variable, .offset = self.locals_frame_size };
    @memcpy(local.name[0..name.len], name);
    self.locals[self.local_count] = local;
    self.local_count += 1;
    self.locals_frame_size += size;
    return local;
}

/// Emits the frame setup and the stores that take initial values off the stacks.
/// `locals` is in the order the values are popped (top of stack first).
pub fn compileLocalInitialization(self: *State, locals: []const Local) RuntimeError!void {
    _ = try self.emit(.{ .kind = .local_frame, .value = self.current_word });
    for (locals) |local| _ = try self.emit(.{ .kind = .local_store, .value = localOperand(local) });
}

/// gforth's `{ ... }` and the standard `{: ... :}`: typed names take their values from
/// the stacks (the last name from the top), names after `|` start at zero, and
/// everything after `--` is a comment.
pub fn compileLocals(self: *State, closing: []const u8) RuntimeError!void {
    if (!self.compiling or !self.defining) return error.CompileOnly;
    var initialized: [max_locals]Local = undefined;
    var initialized_count: usize = 0;
    var uninitialized = false;
    var comment = false;
    const Flavor = struct { kind: LocalKind, variable: bool };
    var pending: ?Flavor = null;
    while (true) {
        const token = (try self.nextSourceToken()) orelse return error.InvalidDefinition;
        if (std.mem.eql(u8, token, closing)) break;
        if (comment) continue;
        if (std.mem.eql(u8, token, "--")) {
            comment = true;
            continue;
        }
        if (std.mem.eql(u8, token, "|")) {
            if (pending != null) return error.InvalidDefinition;
            uninitialized = true;
            continue;
        }
        const types = [_]struct { []const u8, LocalKind, bool }{
            .{ "W:", .cell, false }, .{ "W^", .cell, true },  .{ "D:", .double, false }, .{ "D^", .double, true },
            .{ "F:", .float, false }, .{ "F^", .float, true }, .{ "C:", .char, false },   .{ "C^", .char, true },
            .{ "XT:", .xt, false },  .{ "XT^", .xt, true },
        };
        const prefix = for (types) |entry| {
            if (asciiEqlIgnoreCase(token, entry[0])) break entry;
        } else null;
        if (prefix) |entry| {
            if (pending != null) return error.InvalidDefinition;
            pending = .{ .kind = entry[1], .variable = entry[2] };
            continue;
        }
        const flavor = pending orelse Flavor{ .kind = .cell, .variable = false };
        pending = null;
        const local = try self.addLocal(token, flavor.kind, flavor.variable);
        if (!uninitialized) {
            initialized[initialized_count] = local;
            initialized_count += 1;
        }
    }
    if (pending != null) return error.InvalidDefinition;
    std.mem.reverse(Local, initialized[0..initialized_count]);
    try self.compileLocalInitialization(initialized[0..initialized_count]);
}

/// The standard `LOCALS| a b |`: the first name takes the top of the stack.
pub fn compileAnsLocals(self: *State) RuntimeError!void {
    if (!self.compiling or !self.defining) return error.CompileOnly;
    var names: [max_locals]Local = undefined;
    var count: usize = 0;
    while (true) {
        const token = (try self.nextSourceToken()) orelse return error.InvalidDefinition;
        if (std.mem.eql(u8, token, "|")) break;
        names[count] = try self.addLocal(token, .cell, false);
        count += 1;
    }
    try self.compileLocalInitialization(names[0..count]);
}

pub fn storeLocal(self: *State, address: Cell, kind: LocalKind) RuntimeError!void {
    switch (kind) {
        .cell, .xt => try self.writeCell(address, try self.pop()),
        .double => try self.writeDouble(address, try self.popDouble()),
        .float => try self.writeFloat(address, try self.fpop()),
        .char => self.memory[try self.memoryAddress(address, 1)] = @truncate(@as(UCell, @bitCast(try self.pop()))),
    }
}

pub fn fetchLocal(self: *State, address: Cell, kind: LocalKind) RuntimeError!void {
    switch (kind) {
        .cell, .xt => try self.push(try self.readCell(address)),
        .double => try self.pushDouble(try self.readDouble(address)),
        .float => try self.fpush(try self.readFloat(address)),
        .char => try self.push(self.memory[try self.memoryAddress(address, 1)]),
    }
}
