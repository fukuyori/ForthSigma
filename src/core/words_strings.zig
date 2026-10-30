//! Dynamic string words ($! and its relatives).

const std = @import("std");
const defs = @import("defs.zig");
const forth = @import("../forth.zig");
const memory_map = @import("memory_map.zig");
const Builtin = defs.Builtin;
const Cell = memory_map.Cell;
const RuntimeError = defs.RuntimeError;
const State = forth.State;
const UCell = memory_map.UCell;
const cell_size = memory_map.cell_size;
const errno_invalid = memory_map.errno_invalid;
const errno_no_memory = memory_map.errno_no_memory;
const tmp_string_base = memory_map.tmp_string_base;
const tmp_string_count = memory_map.tmp_string_count;

/// The built-in words this file executes; executeBuiltin dispatches by this list.
pub const words = [_]Builtin{
    .string_store, .string_fetch, .string_fetch_len, .string_store_len, .string_append,
    .char_append, .string_dot, .string_delete, .string_insert, .string_over, .string_free,
    .string_init, .string_split, .string_iter, .string_tmp, .string_array, .string_array_store,
    .string_array_fetch, .string_array_count, .string_array_dot, .string_array_map,
    .string_array_free, .string_array_slurp, .string_array_slurp_file, .string_slurp_file,
};

pub fn execute(self: *State, comptime builtin: Builtin) RuntimeError!void {
    switch (builtin) {
        .string_store => {
            const string_var = try self.pop();
            const length = try self.popLength();
            const source = try self.pop();
            _ = try self.memoryAddress(source, length);
            // A fresh buffer keeps the source intact even when it lies in the old string.
            const buffer = try self.heapAllocate(cell_size + length) orelse return self.throwIor(errno_no_memory);
            self.copyMemory(buffer + cell_size, source, length);
            try self.writeCell(buffer, @intCast(length));
            const old = try self.readCell(string_var);
            if (!try self.heapFree(old)) {
                _ = try self.heapFree(buffer);
                return self.throwIor(errno_invalid);
            }
            try self.writeCell(string_var, buffer);
        },
        .string_fetch => {
            const string = try self.fetchString(try self.pop());
            try self.push(string.address);
            try self.push(@intCast(string.length));
        },
        .string_fetch_len => try self.push(@intCast((try self.fetchString(try self.pop())).length)),
        .string_store_len => {
            const string_var = try self.pop();
            _ = try self.setStringLength(string_var, try self.popLength());
        },
        .string_append => {
            const string_var = try self.pop();
            const length = try self.popLength();
            const source = try self.pop();
            const end = (try self.fetchString(string_var)).length;
            try self.insertString(string_var, end, source, length, false);
        },
        .char_append => {
            const string_var = try self.pop();
            const char: u8 = @truncate(@as(UCell, @bitCast(try self.pop())));
            const length = (try self.fetchString(string_var)).length;
            const buffer = try self.setStringLength(string_var, length + 1);
            self.memory[@intCast(buffer + cell_size + @as(Cell, @intCast(length)))] = char;
        },
        .string_dot => {
            const string = try self.fetchString(try self.pop());
            self.writeMemory(string.address, string.length);
        },
        .string_delete => {
            const count = try self.popLength();
            const offset = try self.popLength();
            const string_var = try self.pop();
            const string = try self.fetchString(string_var);
            const start = @min(offset, string.length);
            const removed = @min(count, string.length - start);
            const base: usize = @intCast(string.address);
            std.mem.copyForwards(u8, self.memory[base + start .. base + string.length - removed], self.memory[base + start + removed .. base + string.length]);
            _ = try self.setStringLength(string_var, string.length - removed);
        },
        .string_insert, .string_over => {
            const offset = try self.popLength();
            const string_var = try self.pop();
            const length = try self.popLength();
            const source = try self.pop();
            try self.insertString(string_var, offset, source, length, builtin == .string_over);
        },
        .string_free => {
            const string_var = try self.pop();
            try self.freeString(string_var);
        },
        .string_init => {
            const string_var = try self.pop();
            const buffer = try self.heapAllocate(cell_size) orelse return self.throwIor(errno_no_memory);
            try self.writeCell(buffer, 0);
            try self.writeCell(string_var, buffer);
        },
        .string_split => {
            const separator: u8 = @truncate(@as(UCell, @bitCast(try self.pop())));
            const length = try self.popLength();
            const address = try self.pop();
            const start = try self.memoryAddress(address, length);
            const found = std.mem.indexOfScalar(u8, self.memory[start .. start + length], separator);
            const first = found orelse length;
            const rest = if (found != null) first + 1 else length;
            try self.push(address);
            try self.push(@intCast(first));
            try self.push(address + @as(Cell, @intCast(rest)));
            try self.push(@intCast(length - rest));
        },
        .string_iter => {
            const xt = try self.wordId(try self.pop());
            const separator: u8 = @truncate(@as(UCell, @bitCast(try self.pop())));
            const string = try self.fetchString(try self.pop());
            var address = string.address;
            var remaining = string.length;
            while (remaining != 0) {
                const start: usize = @intCast(address);
                const part = std.mem.indexOfScalar(u8, self.memory[start .. start + remaining], separator) orelse remaining;
                const consumed = if (part < remaining) part + 1 else part;
                try self.push(address);
                try self.push(@intCast(part));
                try self.executeWord(xt);
                address += @intCast(consumed);
                remaining -= consumed;
            }
        },
        .string_tmp => {
            const xt = try self.wordId(try self.pop());
            const slot = tmp_string_base + @as(Cell, @intCast(self.tmp_string_index % tmp_string_count)) * cell_size;
            self.tmp_string_index += 1;
            try self.freeString(slot);
            const previous_target = self.capture_target;
            const previous_failed = self.capture_failed;
            self.capture_target = slot;
            self.capture_failed = false;
            const result = self.executeWord(xt);
            const failed = self.capture_failed;
            self.capture_target = previous_target;
            self.capture_failed = previous_failed;
            try result;
            if (failed) return self.throwIor(errno_no_memory);
            const string = try self.fetchString(slot);
            try self.push(string.address);
            try self.push(@intCast(string.length));
        },
        .string_array => {
            const array_var = try self.pop();
            try self.push(try self.stringArrayElement(array_var, try self.popLength()));
        },
        .string_array_store => {
            const array_var = try self.pop();
            const index = try self.popLength();
            const element = try self.stringArrayElement(array_var, index);
            try self.push(element);
            try self.executeBuiltin(.string_store);
        },
        .string_array_fetch => {
            const array_var = try self.pop();
            const index: UCell = @bitCast(try self.pop());
            if (index < try self.stringArrayCount(array_var)) {
                const string = try self.fetchString(try self.stringArrayElement(array_var, @intCast(index)));
                try self.push(string.address);
                try self.push(@intCast(string.length));
            } else {
                try self.push(0);
                try self.push(0);
            }
        },
        .string_array_count => try self.push(@intCast(try self.stringArrayCount(try self.pop()))),
        .string_array_dot, .string_array_map => {
            const xt: ?u16 = if (builtin == .string_array_map) try self.wordId(try self.pop()) else null;
            const array_var = try self.pop();
            const count = try self.stringArrayCount(array_var);
            for (0..count) |index| {
                if (index >= try self.stringArrayCount(array_var)) break;
                const string = try self.fetchString(try self.stringArrayElement(array_var, index));
                if (xt) |id| {
                    try self.push(string.address);
                    try self.push(@intCast(string.length));
                    try self.executeWord(id);
                } else {
                    self.writeMemory(string.address, string.length);
                    self.write("\n");
                }
            }
        },
        .string_array_free => {
            const array_var = try self.pop();
            const count = try self.stringArrayCount(array_var);
            for (0..count) |index| try self.freeString(try self.stringArrayElement(array_var, index));
            try self.freeString(array_var);
        },
        .string_array_slurp => {
            const array_var = try self.pop();
            const fileid = try self.pop();
            try self.slurpLines(fileid, array_var);
        },
        .string_array_slurp_file => {
            const array_var = try self.pop();
            const name = try self.memoryRange();
            const files = try self.fileOps();
            const opened = files.open(self.writer.context, name, .read_only, false);
            if (opened.ior != 0) return self.throwCode(opened.ior);
            const fileid: Cell = @bitCast(opened.value);
            self.slurpLines(fileid, array_var) catch |err| {
                _ = files.close(self.writer.context, fileid);
                return err;
            };
            const closed = files.close(self.writer.context, fileid);
            if (closed != 0) return self.throwCode(closed);
        },
        .string_slurp_file => {
            const string_var = try self.pop();
            _ = try self.slurpFile(try self.memoryRange(), string_var);
        },
        else => @compileError(@tagName(builtin) ++ " is not in the words of this file"),
    }
}
