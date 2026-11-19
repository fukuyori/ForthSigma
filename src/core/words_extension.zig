//! Independently selected extension words; no graphics/audio public prerequisites.
const std = @import("std");
const defs = @import("defs.zig");
const forth = @import("../forth.zig");
const map = @import("memory_map.zig");
const loading = @import("library_loading.zig");
const Builtin = defs.Builtin;
const RuntimeError = defs.RuntimeError;
const State = forth.State;

pub const words = [_]Builtin{ .host_os, .term_mode_set, .term_mode_get, .terminal_cols, .terminal_rows, .ekey_wait, .ekey_mouse, .wait_files, .read_available, .write_available, .wait_writable, .proc_new, .proc_arg, .proc_cwd, .proc_env, .proc_io, .proc_start, .proc_stdin, .proc_stdout, .proc_stderr, .proc_status, .proc_wait, .proc_term, .proc_kill, .proc_free };
pub const definitions = [_]struct { []const u8, Builtin }{
    .{ "HOST-OS", .host_os },
    .{ "TERM-MODE!", .term_mode_set },
    .{ "TERM-MODE@", .term_mode_get },
    .{ "COLS", .terminal_cols },
    .{ "ROWS", .terminal_rows },
    .{ "EKEY-WAIT", .ekey_wait },
    .{ "EKEY-MOUSE", .ekey_mouse },
    .{ "WAIT-FILES", .wait_files },
    .{ "READ-AVAILABLE", .read_available },
    .{ "WRITE-AVAILABLE", .write_available },
    .{ "WAIT-WRITABLE", .wait_writable },
    .{ "PROC-NEW", .proc_new },
    .{ "PROC-ARG", .proc_arg },
    .{ "PROC-CWD", .proc_cwd },
    .{ "PROC-ENV", .proc_env },
    .{ "PROC-IO", .proc_io },
    .{ "PROC-START", .proc_start },
    .{ "PROC-STDIN", .proc_stdin },
    .{ "PROC-STDOUT", .proc_stdout },
    .{ "PROC-STDERR", .proc_stderr },
    .{ "PROC-STATUS", .proc_status },
    .{ "PROC-WAIT", .proc_wait },
    .{ "PROC-TERM", .proc_term },
    .{ "PROC-KILL", .proc_kill },
    .{ "PROC-FREE", .proc_free },
};
pub const library_words = [_][]const u8{ "TERM-ALT-SCREEN", "TERM-PASTE", "TERM-HIDE-CURSOR", "TERM-MOUSE", "K-MOUSE", "K-PASTE-BEGIN", "K-PASTE-END" };
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
        .proc_new, .proc_arg, .proc_cwd, .proc_env, .proc_io, .proc_start, .proc_stdin, .proc_stdout, .proc_stderr, .proc_status, .proc_wait, .proc_term, .proc_kill, .proc_free => try @import("words_process.zig").execute(self, builtin),
        .wait_files, .read_available, .write_available, .wait_writable => try @import("words_async_io.zig").execute(self, builtin),
        .host_os => {
            const name = osName(@import("builtin").os.tag);
            if (self.data_depth + 2 > self.data_stack.len) return error.StackOverflow;
            const at: usize = @intCast(map.host_os_buffer_address);
            @import("address_registry.zig").written(self, map.host_os_buffer_address, name.len, false);
            @memcpy(self.memory[at..][0..name.len], name);
            try self.push(map.host_os_buffer_address);
            try self.push(@intCast(name.len));
        },
        .term_mode_set => {
            const mask = try self.peek(0);
            const ior: map.Cell = if (mask < 0 or mask > 15) -24 else if (self.writer.terminal_mode_set_fn) |callback| callback(self.writer.context, @intCast(mask)) else -21;
            if (ior == 0) {
                const accepted = if (self.writer.terminal_mode_get_fn) |get| get(self.writer.context) else @as(u8, @intCast(mask));
                self.gfx_input.mouse_on = accepted & 8 != 0;
                if (accepted & 8 == 0) self.standard_input.buttons = 0;
                if (accepted & 2 == 0) self.standard_input.paste = false;
            }
            self.data_stack[self.data_depth - 1] = ior;
        },
        .term_mode_get => {
            if (self.data_depth == self.data_stack.len) return error.StackOverflow;
            const callback = self.writer.terminal_mode_get_fn orelse return error.HostUnavailable;
            try self.push(callback(self.writer.context));
        },
        .ekey_wait => {
            const timeout = try self.peek(0);
            if (self.data_depth + 2 > self.data_stack.len) return error.StackOverflow;
            const result = try @import("event_input.zig").modern(self, timeout, false);
            self.data_depth -= 1;
            switch (result) {
                .event => |packet| {
                    try self.push(packet.value);
                    try self.push(-1);
                    try self.push(0);
                },
                .eof => {
                    try self.push(@import("standard_keys.zig").eof);
                    try self.push(-1);
                    try self.push(0);
                },
                .timeout, .restart => {
                    try self.push(0);
                    try self.push(0);
                    try self.push(0);
                },
                .failure => |ior| {
                    try self.push(0);
                    try self.push(0);
                    try self.push(ior);
                },
            }
        },
        .ekey_mouse => {
            if (self.data_depth + 4 > self.data_stack.len) return error.StackOverflow;
            const mouse = self.standard_input.last_mouse;
            try self.push(mouse.column);
            try self.push(mouse.row);
            try self.push(mouse.buttons);
            try self.push(mouse.wheel);
        },
        .terminal_cols, .terminal_rows => {
            if (self.data_depth == self.data_stack.len) return error.StackOverflow;
            const size = @import("words_terminal.zig").dimensions(self);
            try self.push(if (builtin == .terminal_cols) size.columns else size.rows);
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
