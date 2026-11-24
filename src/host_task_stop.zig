//! Fatal host exit contract shared with the 1369 retained-runtime path.
//! Cleanup must touch only independent resources, never the retained task graph.
//! Never unwind VM/Storage/queue defers while a worker can still reference them.
pub const exit_code: u8 = 1;
pub const message = "error: runtime resources remain active: task worker stop unconfirmed or collection limit exceeded\n";
extern "c" fn exit(c_int) noreturn;
pub fn abort(context: ?*anyopaque, cleanup: *const fn (?*anyopaque) void, write: *const fn (?*anyopaque, []const u8) void) noreturn {
    cleanup(context);
    write(context, message);
    exit(exit_code);
}
