//! File access and source file words.

const std = @import("std");
const defs = @import("defs.zig");
const forth = @import("../forth.zig");
const host_interface = @import("host_interface.zig");
const integer_math = @import("integer_math.zig");
const memory_map = @import("memory_map.zig");
const source_input = @import("source_input.zig");
const Builtin = defs.Builtin;
const Cell = memory_map.Cell;
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
const sourceFileEntry = source_input.sourceFileEntry;
const stderr_fileid = memory_map.stderr_fileid;
const stdin_fileid = memory_map.stdin_fileid;
const stdout_fileid = memory_map.stdout_fileid;
const terminal_source_name = memory_map.terminal_source_name;
const terminal_source_name_address = memory_map.terminal_source_name_address;
const truth = integer_math.truth;

/// The built-in words this file executes; executeBuiltin dispatches by this list.
pub const words = [_]Builtin{
    .include,            .require,     .included,        .required,    .included_query, .source_file_name,
    .source_line_number, .read_only,   .write_only,      .read_write,  .stdin,          .stdout,
    .stderr,             .open_file,   .create_file,     .close_file,  .read_line,      .write_line,
    .write_file,         .file_size,   .reposition_file, .slurp_file,  .read_file,      .bin,
    .file_position,      .resize_file, .flush_file,      .delete_file, .rename_file,    .file_status,
    .include_file, .emit_file, .slurp_fid, .key_file, .key_query_file, .file_eof_query, .plus_fmode, .dot_included, .triple_backslash,
    .absolute_file_query, .clear_path, .also_path, .dot_path, .path_plus, .path_equals, .open_path_file, .file_to_path, .basename, .dirname, .filename_match, .get_dir, .set_dir, .equals_mkdir, .mkdir_parents,
};

pub fn execute(self: *State, comptime builtin: Builtin) RuntimeError!void {
    switch (builtin) {
        .get_dir, .set_dir, .equals_mkdir, .mkdir_parents => try @import("directories.zig").execute(self, builtin),
        .filename_match => try @import("filename_match.zig").execute(self),
        .absolute_file_query, .clear_path, .also_path, .dot_path, .path_plus, .path_equals, .open_path_file, .file_to_path, .basename, .dirname => try @import("paths.zig").execute(self, builtin),
        .plus_fmode => {
            try self.requireDepth(2);
            const fam: memory_map.UCell = @bitCast(try self.peek(1));
            const mode: memory_map.UCell = @bitCast(try self.peek(0));
            self.data_stack[self.data_depth - 2] = @bitCast(fam | ((mode ^ 0o666) << 4));
            self.data_depth -= 1;
        },
        .dot_included => {
            for (0..self.sourceFileCount()) |index| {
                if (!self.sourceFileLoaded(index)) continue;
                self.write("\n");
                self.write(self.sourceFileName(index));
            }
        },
        .triple_backslash => try source_input.endSourceFile(self),
        .key_file, .key_query_file, .file_eof_query => {
            const fileid = try self.peek(0);
            const files = try self.fileOps();
            const value: Cell = if (builtin == .key_file) result: {
                const key = files.key orelse return error.FileUnavailable;
                const result = try key(self.writer.context, fileid);
                if (result.ior != 0) return self.throwCode(result.ior);
                break :result if (result.byte) |byte| byte else -1;
            } else result: {
                const result = if (builtin == .key_query_file)
                    try (files.ready orelse return error.FileUnavailable)(self.writer.context, fileid)
                else
                    (files.eof orelse return error.FileUnavailable)(self.writer.context, fileid);
                if (result.ior != 0) return self.throwCode(result.ior);
                break :result truth(result.value != 0);
            };
            self.data_stack[self.data_depth - 1] = value;
        },
        .emit_file => {
            try self.requireDepth(2);
            const fileid = try self.peek(0);
            const byte: u8 = @truncate(@as(memory_map.UCell, @bitCast(try self.peek(1))));
            const ior = (try self.fileOps()).write(self.writer.context, fileid, &.{byte});
            self.data_depth -= 2;
            try self.push(ior);
        },
        .slurp_fid => {
            const fileid = try self.peek(0);
            if (self.data_depth == self.data_stack.len) return error.StackOverflow;
            const text = try @import("file_streams.zig").slurp(self, fileid);
            self.data_depth -= 1;
            try self.push(text.address);
            try self.push(@intCast(text.length));
        },
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
            // BIN changes nothing: files are always read and written as bytes.
            const access: ?FileAccess = switch (fam & ~@as(Cell, (0o777 << 4) | 1)) {
                fam_read_only => .read_only,
                fam_write_only => .write_only,
                fam_read_write => .read_write,
                else => null,
            };
            const result = if (access) |mode| result: {
                const encoded = @as(memory_map.UCell, @bitCast(fam)) >> 4;
                if (builtin == .create_file and encoded != 0) {
                    const create_mode = files.create_mode orelse break :result FileResult{ .ior = errnoIor(errno_invalid) };
                    break :result create_mode(self.writer.context, name, mode, @intCast(encoded ^ 0o666));
                }
                break :result files.open(self.writer.context, name, mode, builtin == .create_file);
            } else FileResult{ .ior = errnoIor(errno_invalid) };
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
            if (self.data_stack.len - self.data_depth < 3) return error.StackOverflow;
            const result = files.read_line(self.writer.context, fileid, buffer);
            @import("address_registry.zig").written(self, @intCast(@intFromPtr(buffer.ptr) - @intFromPtr(self.memory.ptr)), if (result.ior != 0) buffer.len else @min(result.length, buffer.len), false);
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
        .bin => try self.push((try self.pop()) | 1),
        .file_position => {
            const result = (try self.fileOps()).position(self.writer.context, try self.pop());
            try self.pushDouble(if (result.ior == 0) result.value else -1);
            try self.push(result.ior);
        },
        .resize_file => {
            const fileid = try self.pop();
            const size: UDouble = @bitCast(try self.popDouble());
            const files = try self.fileOps();
            try self.push(if (size > std.math.maxInt(i64)) errnoIor(errno_invalid) else files.resize(self.writer.context, fileid, @intCast(size)));
        },
        .flush_file => try self.push((try self.fileOps()).flush(self.writer.context, try self.pop())),
        .delete_file => {
            const name = try self.memoryRange();
            try self.push((try self.fileOps()).delete(self.writer.context, name));
        },
        .rename_file => {
            const new = try self.memoryRange();
            const old = try self.memoryRange();
            try self.push((try self.fileOps()).rename(self.writer.context, old, new));
        },
        .file_status => {
            const name = try self.memoryRange();
            const result = (try self.fileOps()).status(self.writer.context, name);
            try self.push(if (result.ior == 0) @bitCast(result.value) else 0);
            try self.push(result.ior);
        },
        .include_file => try self.includeOpenFile(try self.pop(), "*file*"),
        .read_file => {
            const fileid = try self.pop();
            const buffer = try self.memoryRange();
            const files = try self.fileOps();
            if (self.data_stack.len - self.data_depth < 2) return error.StackOverflow;
            const result = files.read(self.writer.context, fileid, buffer);
            @import("address_registry.zig").written(self, @intCast(@intFromPtr(buffer.ptr) - @intFromPtr(self.memory.ptr)), if (result.ior != 0) buffer.len else @intCast(@min(result.value, buffer.len)), false);
            try self.push(if (result.ior == 0) @intCast(result.value) else 0);
            try self.push(result.ior);
        },
        .slurp_file => {
            const text = try self.slurpFile(try self.memoryRange(), null);
            try self.push(text.address);
            try self.push(@intCast(text.length));
        },
        else => @compileError(@tagName(builtin) ++ " is not in the words of this file"),
    }
}
