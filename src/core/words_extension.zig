//! Independently selected extension words; no graphics/audio public prerequisites.
const std = @import("std");
const defs = @import("defs.zig");
const forth = @import("../forth.zig");
const map = @import("memory_map.zig");
const loading = @import("library_loading.zig");
const Builtin = defs.Builtin;
const RuntimeError = defs.RuntimeError;
const State = forth.State;

pub const words = [_]Builtin{ .host_os, .term_mode_set, .term_mode_get, .terminal_cols, .terminal_rows, .ekey_wait, .ekey_mouse, .wait_files, .read_available, .write_available, .wait_writable, .proc_new, .proc_arg, .proc_cwd, .proc_env, .proc_io, .proc_start, .proc_stdin, .proc_stdout, .proc_stderr, .proc_status, .proc_wait, .proc_term, .proc_kill, .proc_free, .x_grapheme, .x_grapheme_last, .compact_filename, .file_realpath, .file_metadata, .sync_file, .task_snapshot, .task_snapshot_release, .task_submit, .task_state, .task_cancel, .task_wait, .task_result, .task_diagnostic, .task_release, .task_wait_many, .task_queued, .task_running, .task_succeeded, .task_failed, .task_cancelled, .task_g1, .task_g2, .task_t1, .task_i1, .task_wait_target_cells, .task_wait_event_cells, .task_e_handle, .task_e_full, .task_e_stale, .task_e_entry, .task_e_denied, .task_e_limit, .task_e_not_ready, .task_e_short, .task_e_abi, .task_e_busy, .task_e_exhausted, .task_e_no_capability, .task_e_host, .task_e_queue_expired, .task_e_stop_unconfirmed, .task_wait_input, .task_wait_io, .task_wait_task, .task_wait_clock, .task_wait_paint, .task_event_input, .task_event_readable, .task_event_writable, .task_event_eof, .task_event_failure, .task_event_closed, .task_event_succeeded, .task_event_failed, .task_event_cancelled, .task_event_released, .task_event_deadline, .task_event_painted, .task_event_capability_lost, .task_wait_expired, .task_wait_cancelled, .task_wait_interrupted, .task_wait_host_failed, .exec_limited };
const Definition = struct { []const u8, Builtin };
pub const definitions = [_]Definition{
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
    .{ "X-GRAPHEME", .x_grapheme },
    .{ "X-GRAPHEME-LAST", .x_grapheme_last },
    .{ "COMPACT-FILENAME", .compact_filename },
    .{ "FILE>REALPATH", .file_realpath },
    .{ "FILE-METADATA", .file_metadata },
    .{ "SYNC-FILE", .sync_file },
    .{ "TASK-SNAPSHOT", .task_snapshot },
    .{ "TASK-SNAPSHOT-RELEASE", .task_snapshot_release },
    .{ "TASK-SUBMIT", .task_submit },
    .{ "TASK-STATE", .task_state },
    .{ "TASK-CANCEL", .task_cancel },
    .{ "TASK-WAIT", .task_wait },
    .{ "TASK-RESULT", .task_result },
    .{ "TASK-DIAGNOSTIC", .task_diagnostic },
    .{ "TASK-RELEASE", .task_release },
    .{ "TASK-WAIT-MANY", .task_wait_many },
    .{ "TASK-QUEUED", .task_queued },
    .{ "TASK-RUNNING", .task_running },
    .{ "TASK-SUCCEEDED", .task_succeeded },
    .{ "TASK-FAILED", .task_failed },
    .{ "TASK-CANCELLED", .task_cancelled },
    .{ "TASK-G1", .task_g1 },
    .{ "TASK-G2", .task_g2 },
    .{ "TASK-T1", .task_t1 },
    .{ "TASK-I1", .task_i1 },
    .{ "TASK-WAIT-TARGET-CELLS", .task_wait_target_cells },
    .{ "TASK-WAIT-EVENT-CELLS", .task_wait_event_cells },
    .{ "TASK-E-HANDLE", .task_e_handle },
    .{ "TASK-E-FULL", .task_e_full },
    .{ "TASK-E-STALE", .task_e_stale },
    .{ "TASK-E-ENTRY", .task_e_entry },
    .{ "TASK-E-DENIED", .task_e_denied },
    .{ "TASK-E-LIMIT", .task_e_limit },
    .{ "TASK-E-NOT-READY", .task_e_not_ready },
    .{ "TASK-E-SHORT", .task_e_short },
    .{ "TASK-E-ABI", .task_e_abi },
    .{ "TASK-E-BUSY", .task_e_busy },
    .{ "TASK-E-EXHAUSTED", .task_e_exhausted },
    .{ "TASK-E-NO-CAPABILITY", .task_e_no_capability },
    .{ "TASK-E-HOST", .task_e_host },
    .{ "TASK-E-QUEUE-EXPIRED", .task_e_queue_expired },
    .{ "TASK-E-STOP-UNCONFIRMED", .task_e_stop_unconfirmed },
    .{ "TASK-WAIT-INPUT", .task_wait_input },
    .{ "TASK-WAIT-IO", .task_wait_io },
    .{ "TASK-WAIT-TASK", .task_wait_task },
    .{ "TASK-WAIT-CLOCK", .task_wait_clock },
    .{ "TASK-WAIT-PAINT", .task_wait_paint },
    .{ "TASK-EVENT-INPUT", .task_event_input },
    .{ "TASK-EVENT-READABLE", .task_event_readable },
    .{ "TASK-EVENT-WRITABLE", .task_event_writable },
    .{ "TASK-EVENT-EOF", .task_event_eof },
    .{ "TASK-EVENT-FAILURE", .task_event_failure },
    .{ "TASK-EVENT-CLOSED", .task_event_closed },
    .{ "TASK-EVENT-SUCCEEDED", .task_event_succeeded },
    .{ "TASK-EVENT-FAILED", .task_event_failed },
    .{ "TASK-EVENT-CANCELLED", .task_event_cancelled },
    .{ "TASK-EVENT-RELEASED", .task_event_released },
    .{ "TASK-EVENT-DEADLINE", .task_event_deadline },
    .{ "TASK-EVENT-PAINTED", .task_event_painted },
    .{ "TASK-EVENT-CAPABILITY-LOST", .task_event_capability_lost },
    .{ "TASK-WAIT-EXPIRED", .task_wait_expired },
    .{ "TASK-WAIT-CANCELLED", .task_wait_cancelled },
    .{ "TASK-WAIT-INTERRUPTED", .task_wait_interrupted },
    .{ "TASK-WAIT-HOST-FAILED", .task_wait_host_failed },
    .{ "EXEC-LIMITED", .exec_limited },
};
comptime {
    if (definitions[definitions.len - 1][1] != .exec_limited) @compileError("EXEC-LIMITED must remain the final extension definition for debug exclusion");
}
pub const enabled_definitions = if (defs.debug_enabled) definitions else definitions[0 .. definitions.len - 1].*;
pub const library_words = [_][]const u8{ "TERM-ALT-SCREEN", "TERM-PASTE", "TERM-HIDE-CURSOR", "TERM-MOUSE", "K-MOUSE", "K-PASTE-BEGIN", "K-PASTE-END" };
pub const library_name = "*extension library*";
pub const library = @embedFile("../extension/extension.fs");
pub const group: loading.Group(@TypeOf(definitions[0])) = .{
    .vocabulary = "EXTENSION",
    .definitions = &enabled_definitions,
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
        .task_snapshot, .task_snapshot_release, .task_submit, .task_state, .task_cancel, .task_wait, .task_result, .task_diagnostic, .task_release, .task_wait_many, .task_queued, .task_running, .task_succeeded, .task_failed, .task_cancelled, .task_g1, .task_g2, .task_t1, .task_i1, .task_wait_target_cells, .task_wait_event_cells, .task_e_handle, .task_e_full, .task_e_stale, .task_e_entry, .task_e_denied, .task_e_limit, .task_e_not_ready, .task_e_short, .task_e_abi, .task_e_busy, .task_e_exhausted, .task_e_no_capability, .task_e_host, .task_e_queue_expired, .task_e_stop_unconfirmed, .task_wait_input, .task_wait_io, .task_wait_task, .task_wait_clock, .task_wait_paint, .task_event_input, .task_event_readable, .task_event_writable, .task_event_eof, .task_event_failure, .task_event_closed, .task_event_succeeded, .task_event_failed, .task_event_cancelled, .task_event_released, .task_event_deadline, .task_event_painted, .task_event_capability_lost, .task_wait_expired, .task_wait_cancelled, .task_wait_interrupted, .task_wait_host_failed => try @import("words_task.zig").execute(self, builtin),
        .exec_limited => try @import("execution_control.zig").run(self),
        .compact_filename, .file_realpath, .file_metadata, .sync_file => try @import("words_filesystem.zig").execute(self, builtin),
        .x_grapheme, .x_grapheme_last => {
            try self.requireDepth(2);
            const length = std.math.cast(usize, try self.peek(0)) orelse return error.InvalidAddress;
            const start = try self.memoryAddress(try self.peek(1), length);
            const result = try @import("grapheme.zig").size(self.memory[start..][0..length], builtin == .x_grapheme_last);
            self.data_depth -= 1;
            self.data_stack[self.data_depth - 1] = @intCast(result);
        },
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
