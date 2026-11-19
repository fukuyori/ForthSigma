//! Verify Windows pipe access before giving a synchronous handle to a worker.
//! Optional system APIs are resolved dynamically; unknown is never assumed safe.
const std = @import("std");
const builtin = @import("builtin");
const Error = @import("core/runtime_base.zig").Error;
const Handle = *anyopaque;
extern "kernel32" fn GetModuleHandleW(?[*:0]const u16) callconv(.winapi) ?Handle;
extern "kernel32" fn GetProcAddress(Handle, [*:0]const u8) callconv(.winapi) ?*const anyopaque;
const Basic = extern struct {
    attributes: u32 = 0,
    granted_access: u32 = 0,
    handle_count: u32 = 0,
    pointer_count: u32 = 0,
    reserved: [10]u32 = @splat(0),
};
pub const Access = struct { read: bool, write: bool };

pub fn query(handle: Handle) Error!Access {
    const module = GetModuleHandleW(std.unicode.utf8ToUtf16LeStringLiteral("ntdll.dll")) orelse return error.HostFailed;
    const callback: *const fn (Handle, u32, *Basic, u32, ?*u32) callconv(.winapi) i32 = @ptrCast(GetProcAddress(module, "NtQueryObject") orelse return error.HostFailed);
    var information = Basic{};
    if (callback(handle, 0, &information, @sizeOf(Basic), null) < 0) return error.HostFailed;
    return .{ .read = information.granted_access & 1 != 0, .write = information.granted_access & 2 != 0 };
}

pub fn same(first: Handle, second: Handle) Error!bool {
    const module = GetModuleHandleW(std.unicode.utf8ToUtf16LeStringLiteral("kernelbase.dll")) orelse return error.HostFailed;
    const callback: *const fn (Handle, Handle) callconv(.winapi) i32 = @ptrCast(GetProcAddress(module, "CompareObjectHandles") orelse return error.HostFailed);
    return callback(first, second) != 0;
}

test "Windows pipe directions and duplicated kernel objects are distinguished" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    const win = struct {
        extern "kernel32" fn CreatePipe(*?Handle, *?Handle, ?*anyopaque, u32) callconv(.winapi) i32;
        extern "kernel32" fn CloseHandle(Handle) callconv(.winapi) i32;
        extern "kernel32" fn GetCurrentProcess() callconv(.winapi) Handle;
        extern "kernel32" fn DuplicateHandle(Handle, Handle, Handle, *?Handle, u32, i32, u32) callconv(.winapi) i32;
    };
    var input: ?Handle = null;
    var output: ?Handle = null;
    try std.testing.expect(win.CreatePipe(&input, &output, null, 4096) != 0);
    defer _ = win.CloseHandle(input.?);
    defer _ = win.CloseHandle(output.?);
    try std.testing.expectEqual(Access{ .read = true, .write = false }, try query(input.?));
    try std.testing.expectEqual(Access{ .read = false, .write = true }, try query(output.?));
    var duplicate: ?Handle = null;
    try std.testing.expect(win.DuplicateHandle(win.GetCurrentProcess(), input.?, win.GetCurrentProcess(), &duplicate, 0, 0, 2) != 0);
    defer _ = win.CloseHandle(duplicate.?);
    try std.testing.expect(try same(input.?, duplicate.?));
    try std.testing.expect(!try same(input.?, output.?));
}
