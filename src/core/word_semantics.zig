//! Select interpretation and compilation actions without consulting STATE at execution.
const forth = @import("../forth.zig");
const defs = @import("defs.zig");

pub fn pending(self: *const forth.State, id: u16) ?defs.Pending {
    const word = self.words[self.synonymTarget(id)];
    if (word.kind != .builtin) return null;
    return switch (word.builtin) {
        .assign_to, .assign_is => .to_name,
        .assign_plus_to => .plus_to_name,
        .assignment_action_of => .action_of_name,
        else => null,
    };
}

pub fn interpretation(self: *const forth.State, id: u16) u16 {
    return self.synonymTarget(id);
}

pub const Compilation = struct { target: u16, execute: bool };
pub fn compilation(self: *const forth.State, id: u16) Compilation {
    const target = interpretation(self, id);
    const word = self.words[target];
    const compiler: ?defs.Builtin = if (word.kind == .builtin) switch (word.builtin) {
        .assign_to => .compile_assign_to,
        .assign_is => .compile_assign_is,
        .assign_plus_to => .compile_assign_plus_to,
        .assignment_action_of => .compile_assignment_action_of,
        else => null,
    } else null;
    if (compiler) |builtin| return .{ .target = @intCast(self.builtinWord(builtin)), .execute = true };
    return .{ .target = id, .execute = self.words[id].immediate };
}
