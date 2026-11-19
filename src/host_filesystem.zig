//! Per-call owned OS results. No filesystem resources enter the VM State.
const io = @import("core/host_interface.zig");
const map = @import("core/memory_map.zig");
const std = @import("std");
pub const supported = switch (@import("builtin").os.tag) {
    .windows, .linux, .macos => true,
    else => false,
};
extern "c" fn sigma_fs_realpath([*:0]const u8, *?[*]u8, *usize) c_int;
extern "c" fn sigma_fs_info([*:0]const u8, *u64, *i64, *u32) c_int;
extern "c" fn sigma_fs_free([*]const u8) void;
extern "c" fn sigma_fs_name_too_long() c_int;
pub extern "c" fn sigma_fs_regular(c_int) c_int;
pub extern "c" fn sigma_fs_sync(c_int) c_int;

fn nameBytes(name: []const u8, buffer: *[4096:0]u8) ?[*:0]const u8 {
    if (name.len == 0 or name.len >= buffer.len or std.mem.indexOfScalar(u8, name, 0) != null) return null;
    @memcpy(buffer[0..name.len], name);
    buffer[name.len] = 0;
    return @ptrCast(buffer);
}
pub fn realpath(_: ?*anyopaque, name: []const u8) io.OwnedPath {
    var buffer: [4096:0]u8 = undefined;
    if (name.len >= buffer.len) return .{ .ior = map.errnoIor(sigma_fs_name_too_long()) };
    const path = nameBytes(name, &buffer) orelse return .{ .ior = map.errnoIor(22) };
    var bytes: ?[*]u8 = null;
    var length: usize = 0;
    const error_code = sigma_fs_realpath(path, &bytes, &length);
    if (error_code != 0) return .{ .ior = map.errnoIor(error_code) };
    if (bytes == null or length == 0) {
        if (bytes) |allocated| sigma_fs_free(allocated);
        return .{ .ior = map.errnoIor(5) };
    }
    return .{ .bytes = bytes.?[0..length] };
}
pub fn release(_: ?*anyopaque, bytes: []const u8) void {
    if (bytes.len != 0) sigma_fs_free(bytes.ptr);
}
pub fn metadata(_: ?*anyopaque, name: []const u8) io.FileMetadata {
    var buffer: [4096:0]u8 = undefined;
    if (name.len >= buffer.len) return .{ .ior = map.errnoIor(sigma_fs_name_too_long()) };
    const path = nameBytes(name, &buffer) orelse return .{ .ior = map.errnoIor(22) };
    var result = io.FileMetadata{};
    const code = sigma_fs_info(path, &result.size, &result.seconds, &result.nanoseconds);
    if (code != 0) return .{ .ior = map.errnoIor(code) };
    return result;
}
