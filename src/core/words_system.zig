//! Images, exceptions, and host services such as time and the shell.

const defs = @import("defs.zig");
const forth = @import("../forth.zig");
const memory_map = @import("memory_map.zig");
const Builtin = defs.Builtin;
const CatchFrame = defs.CatchFrame;
const RuntimeError = defs.RuntimeError;
const State = forth.State;
const environment_buffer_base = memory_map.environment_buffer_base;
const environment_buffer_size = memory_map.environment_buffer_size;
const error_codes = defs.error_codes;
const max_host_name = memory_map.max_host_name;

/// The built-in words this file executes; executeBuiltin dispatches by this list.
pub const words = [_]Builtin{
    .bye, .load, .save, .savesys, .abort, .ms, .utime, .getenv, .system, .throw, .catch_word,
};

pub fn execute(self: *State, comptime builtin: Builtin) RuntimeError!void {
    switch (builtin) {
        .bye => self.halted = true,
        .load => {
            const path = (try self.nextSourceToken()) orelse return error.InputUnavailable;
            const load_fn = self.writer.load_fn orelse return error.FileUnavailable;
            try load_fn(self.writer.context, path, self);
        },
        .save => {
            const path = (try self.nextSourceToken()) orelse return error.InputUnavailable;
            const save_fn = self.writer.save_fn orelse return error.FileUnavailable;
            try save_fn(self.writer.context, path, self);
        },
        .savesys => {
            const path = (try self.nextSourceToken()) orelse return error.InputUnavailable;
            const savesys_fn = self.writer.savesys_fn orelse return error.FileUnavailable;
            try savesys_fn(self.writer.context, path, self);
        },
        .abort => return error.Aborted,
        .ms => {
            const milliseconds = try self.pop();
            const sleep_fn = self.writer.sleep_fn orelse return error.HostUnavailable;
            try sleep_fn(self.writer.context, @max(milliseconds, 0));
        },
        .utime => {
            const utime_fn = self.writer.utime_fn orelse return error.HostUnavailable;
            try self.pushDouble(try utime_fn(self.writer.context));
        },
        .getenv => {
            const name = try self.memoryRange();
            const getenv_fn = self.writer.getenv_fn orelse return error.HostUnavailable;
            // The name may lie inside the result buffer, so copy it out first.
            if (name.len > max_host_name) return error.StringTooLong;
            var name_copy: [max_host_name]u8 = undefined;
            @memcpy(name_copy[0..name.len], name);
            const start: usize = @intCast(environment_buffer_base);
            const found = try getenv_fn(self.writer.context, name_copy[0..name.len], self.memory[start .. start + environment_buffer_size]);
            if (found) |length| {
                try self.push(environment_buffer_base);
                try self.push(@intCast(length));
            } else {
                try self.push(0);
                try self.push(0);
            }
        },
        .system => {
            const command = try self.memoryRange();
            const system_fn = self.writer.system_fn orelse return error.HostUnavailable;
            try system_fn(self.writer.context, command);
        },
        .throw => {
            const code = try self.pop();
            if (code == 0) return;
            if (code == -1) return error.Aborted;
            // Codes of interpreter errors raise that error again, with its own message.
            for (error_codes) |entry| {
                if (entry[1] == code) return entry[0];
            }
            self.throw_code = code;
            return error.Thrown;
        },
        .catch_word => {
            const xt = try self.wordId(try self.pop());
            const frame = CatchFrame{
                .data_depth = self.data_depth,
                .float_depth = self.float_depth,
                .return_depth = self.return_depth,
                .loop_depth = self.loop_depth,
                .control_depth = self.control_depth,
                .pending = self.pending,
                .compiling = self.compiling,
                .defining = self.defining,
                .local_count = self.local_count,
            };
            if (self.executeWord(xt)) |_| {
                try self.push(0);
            } else |err| {
                const code = self.throwCodeOf(err);
                self.abort_message = null;
                self.restoreCatchFrame(frame);
                try self.push(code);
            }
        },
        else => @compileError(@tagName(builtin) ++ " is not in the words of this file"),
    }
}
