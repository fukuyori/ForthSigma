//! Optional pinned host binding. No worker is created by binding this hook.
const reap = @import("core/task_reap.zig");
const forth = @import("forth.zig");
var current: ?*reap.Reaper = null;
var end_failed = false;
pub fn endFailed() bool {
    return end_failed;
}
pub fn bind(reaper: ?*reap.Reaper) void {
    current = reaper;
    end_failed = false;
}
pub fn end(cause: reap.Cause) !void {
    if (current) |reaper| {
        const progress = reaper.finish(cause) catch |err| {
            end_failed = true;
            return err;
        };
        if (progress != .collected) {
            end_failed = true;
            return error.WorkerUnresponsive;
        }
    }
}
pub fn interpret(machine: *forth.State, source: []const u8) forth.RuntimeError!void {
    try machine.interpretLine(source);
    if (machine.halted) end(.bye) catch return error.HostFailed;
}
pub fn include(machine: *forth.State, path: []const u8) forth.RuntimeError!void {
    try machine.includeFile(path);
    if (machine.halted) end(.bye) catch return error.HostFailed;
}
pub fn runEntry(machine: *forth.State, id: u16) forth.RuntimeError!void {
    try machine.runEntry(id);
    if (machine.halted) end(.bye) catch return error.HostFailed;
}
/// Complete restoration only. LOAD-DICTIONARY appends through a temporary VM
/// and must not enter this path. Busy leaves the original machine untouched.
pub fn restore(machine: *forth.State, image: []const u8) !void {
    if (current) |reaper| try reaper.requireRestoreIdle();
    try machine.restoreFreshImage(image);
}
