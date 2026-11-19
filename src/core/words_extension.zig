//! Independently selected extension words; no graphics/audio public prerequisites.
const std = @import("std");
const defs = @import("defs.zig");
const forth = @import("../forth.zig");
const map = @import("memory_map.zig");
const loading = @import("library_loading.zig");
const Builtin = defs.Builtin;
const RuntimeError = defs.RuntimeError;
const State = forth.State;

pub const words = [_]Builtin{.host_os};
pub const definitions = [_]struct { []const u8, Builtin }{
    .{ "HOST-OS", .host_os },
};
pub const library_words = [_][]const u8{};
pub const library_name = "*extension library*";
pub const library = @embedFile("../extension/extension.fs");
pub const group: loading.Group(@TypeOf(definitions[0])) = .{
    .vocabulary = "EXTENSION",
    .definitions = &definitions,
    .library_name = library_name,
    .vocabulary_address = map.extension_vocabulary_address,
};

pub fn requireExtension(self: *State) RuntimeError!void {
    if (!defs.extension_enabled) return error.UnknownWord;
    return loading.require(self, group, self.extension_library);
}

pub fn extensionLoaded(self: *const State) bool {
    return loading.isLoaded(self, group);
}

pub fn execute(self: *State, comptime builtin: Builtin) RuntimeError!void {
    switch (builtin) {
        .host_os => {
            const name = osName(@import("builtin").os.tag);
            if (self.data_depth + 2 > self.data_stack.len) return error.StackOverflow;
            const at: usize = @intCast(map.host_os_buffer_address);
            @import("address_registry.zig").written(self, map.host_os_buffer_address, name.len, false);
            @memcpy(self.memory[at..][0..name.len], name);
            try self.push(map.host_os_buffer_address);
            try self.push(@intCast(name.len));
        },
        else => @compileError(@tagName(builtin) ++ " is not an extension word"),
    }
}

/// Target OS family; pure mapping, with no OS services or native pointers.
pub fn osName(tag: std.Target.Os.Tag) []const u8 {
    return switch (tag) {
        .windows => "windows",
        .linux => "linux",
        .macos => "macos",
        else => "unknown",
    };
}
