//! File access and source file words.

const std = @import("std");
const defs = @import("defs.zig");
const forth = @import("../forth.zig");
const host_interface = @import("host_interface.zig");
const integer_math = @import("integer_math.zig");
const memory_map = @import("memory_map.zig");
const source_input = @import("source_input.zig");
const Builtin = defs.Builtin;
const FileAccess = host_interface.FileAccess;
const FileResult = host_interface.FileResult;
const RuntimeError = defs.RuntimeError;
const State = forth.State;
const UDouble = memory_map.UDouble;
const errnoIor = memory_map.errnoIor;
const errno_invalid = memory_map.errno_invalid;
const evaluate_source_name = memory_map.evaluate_source_name;
const evaluate_source_name_address = memory_map.evaluate_source_name_address;
const fam_read_only = memory_map.fam_read_only;
const fam_read_write = memory_map.fam_read_write;
const fam_write_only = memory_map.fam_write_only;
const line_terminator = memory_map.line_terminator;
const max_stack = memory_map.max_stack;
const sourceFileEntry = source_input.sourceFileEntry;
const stderr_fileid = memory_map.stderr_fileid;
const stdin_fileid = memory_map.stdin_fileid;
const stdout_fileid = memory_map.stdout_fileid;
const terminal_source_name = memory_map.terminal_source_name;
const terminal_source_name_address = memory_map.terminal_source_name_address;
const truth = integer_math.truth;

/// The built-in words this file executes; executeBuiltin dispatches by this list.
pub const words = [_]Builtin{
    .include, .require, .included, .required, .included_query, .source_file_name,
    .source_line_number, .read_only, .write_only, .read_write, .stdin, .stdout, .stderr, .open_file,
    .create_file, .close_file, .read_line, .write_line, .write_file, .file_size, .reposition_file,
};

pub fn execute(self: *State, comptime builtin: Builtin) RuntimeError!void {
    switch (builtin) {
        .include, .require => {
            const name = (try self.nextSourceToken()) orelse return error.InputUnavailable;
            if (builtin == .include) try self.includeFile(name) else try self.requireFile(name);
        },
        .included, .required => {
            const name = try self.memoryRange();
            if (builtin == .included) try self.includeFile(name) else try self.requireFile(name);
        },
        .included_query => try self.push(truth(self.findSourceFile(try self.memoryRange()) != null)),
        .source_file_name => {
            if (self.currentFileFrame()) |frame| {
                try self.push(@intCast(sourceFileEntry(frame.file_index) + 1));
                try self.push(@intCast(self.sourceFileName(frame.file_index).len));
            } else {
                const evaluating = self.source_kind == .evaluate;
                try self.push(if (evaluating) evaluate_source_name_address else terminal_source_name_address);
                try self.push(@intCast(if (evaluating) evaluate_source_name.len else terminal_source_name.len));
            }
        },
        .source_line_number => try self.push(if (self.currentFileFrame()) |frame| frame.line else 0),
        .read_only => try self.push(fam_read_only),
        .write_only => try self.push(fam_write_only),
        .read_write => try self.push(fam_read_write),
        .stdin => try self.push(stdin_fileid),
        .stdout => try self.push(stdout_fileid),
        .stderr => try self.push(stderr_fileid),
        .open_file, .create_file => {
            const fam = try self.pop();
            const name = try self.memoryRange();
            const files = try self.fileOps();
            const access: ?FileAccess = switch (fam) {
                fam_read_only => .read_only,
                fam_write_only => .write_only,
                fam_read_write => .read_write,
                else => null,
            };
            const result = if (access) |mode| files.open(self.writer.context, name, mode, builtin == .create_file) else FileResult{ .ior = errnoIor(errno_invalid) };
            try self.push(if (result.ior == 0) @bitCast(result.value) else 0);
            try self.push(result.ior);
        },
        .close_file => {
            const fileid = try self.pop();
            try self.push((try self.fileOps()).close(self.writer.context, fileid));
        },
        .read_line => {
            const fileid = try self.pop();
            const buffer = try self.memoryRange();
            const files = try self.fileOps();
            if (max_stack - self.data_depth < 3) return error.StackOverflow;
            const result = files.read_line(self.writer.context, fileid, buffer);
            try self.push(if (result.ior == 0) @intCast(result.length) else 0);
            try self.push(if (result.ior == 0) truth(result.found) else 0);
            try self.push(result.ior);
        },
        .write_line, .write_file => {
            const fileid = try self.pop();
            const bytes = try self.memoryRange();
            const files = try self.fileOps();
            var ior = files.write(self.writer.context, fileid, bytes);
            if (ior == 0 and builtin == .write_line) ior = files.write(self.writer.context, fileid, line_terminator);
            try self.push(ior);
        },
        .file_size => {
            const fileid = try self.pop();
            const result = (try self.fileOps()).size(self.writer.context, fileid);
            try self.pushDouble(if (result.ior == 0) result.value else 0);
            try self.push(result.ior);
        },
        .reposition_file => {
            const fileid = try self.pop();
            const position: UDouble = @bitCast(try self.popDouble());
            const files = try self.fileOps();
            try self.push(if (position > std.math.maxInt(i64)) errnoIor(errno_invalid) else files.reposition(self.writer.context, fileid, @intCast(position)));
        },
        else => @compileError(@tagName(builtin) ++ " is not in the words of this file"),
    }
}
