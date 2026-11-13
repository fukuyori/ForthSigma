//! Images, exceptions, and host services such as time and the shell.

const std = @import("std");
const defs = @import("defs.zig");
const forth = @import("../forth.zig");
const memory_map = @import("memory_map.zig");
const text_input = @import("text_input.zig");

fn prepareSave(self: *forth.State) RuntimeError!void {
    var graph: @import("image_graph.zig").Graph = undefined;
    try @import("image_graph.zig").collect(self, &graph);
    if (defs.graphics_enabled) @import("tcl.zig").releaseHeap(self);
}
const Builtin = defs.Builtin;
const CatchFrame = defs.CatchFrame;
const Cell = memory_map.Cell;
const Double = memory_map.Double;
const Float = memory_map.Float;
const RuntimeError = defs.RuntimeError;
const State = forth.State;
const asciiEqlIgnoreCase = text_input.asciiEqlIgnoreCase;
const environment_buffer_base = memory_map.environment_buffer_base;
const environment_buffer_size = memory_map.environment_buffer_size;
const error_codes = defs.error_codes;
const hold_bottom = memory_map.hold_bottom;
const hold_top = memory_map.hold_top;
const max_host_name = memory_map.max_host_name;
const max_locals = memory_map.max_locals;
const max_wordlists = memory_map.max_wordlists;
const pad_address = memory_map.pad_address;
const string_buffer_base = memory_map.string_buffer_base;
const true_flag = memory_map.true_flag;

/// The built-in words this file executes; executeBuiltin dispatches by this list.
pub const words = [_]Builtin{
    .bye,          .load,         .save,              .savesys, .abort, .ms,      .utime, .getenv, .system, .throw,      .catch_word,
    .ekey_to_char, .ekey_to_fkey, .environment_query, .quit,    .noop,  .perform, .argc,  .argv,   .arg,    .shift_args, .next_arg,
};

/// Writes the command-line arguments into the argument area (see `argc_address`), with
/// ARGV pointing at the vector. Fails when they do not fit; nothing is set then.
pub fn setArguments(self: *State, arguments: []const []const u8) RuntimeError!void {
    if (arguments.len > memory_map.max_arguments) return error.StringTooLong;
    var bytes: usize = 0;
    for (arguments) |text| bytes += text.len + 1;
    if (bytes > memory_map.argument_strings_end - memory_map.argument_strings) return error.StringTooLong;
    var at: Cell = memory_map.argument_strings;
    for (arguments, 0..) |text, index| {
        const start: usize = @intCast(at);
        @memcpy(self.memory[start .. start + text.len], text);
        self.memory[start + text.len] = 0;
        @import("address_registry.zig").written(self, @intCast(start), text.len + 1, false);
        try self.writeCell(memory_map.argument_vector + @as(Cell, @intCast(index)) * memory_map.cell_size, at);
        at += @intCast(text.len + 1);
    }
    try self.writeCell(memory_map.argv_address, memory_map.argument_vector);
    try self.writeCell(memory_map.argc_address, @intCast(arguments.len));
}

/// ARG: argument `index` as an address and a length, or 0 0 when ARGC has fewer.
pub fn argument(self: *State, index: Cell) RuntimeError!struct { Cell, usize } {
    const count = try self.readCell(memory_map.argc_address);
    if (@as(u64, @bitCast(index)) >= @as(u64, @bitCast(count))) return .{ 0, 0 };
    const vector = try self.readCell(memory_map.argv_address);
    const address = try self.readCell(vector +% index *% memory_map.cell_size);
    const start = try self.memoryAddress(address, 0);
    const length = std.mem.indexOfScalar(u8, self.memory[start..], 0) orelse return error.InvalidAddress;
    return .{ address, length };
}

/// SHIFT-ARGS: removes argument 1, keeping argument 0 first, as gforth does.
pub fn shiftArguments(self: *State) RuntimeError!void {
    const count = try self.readCell(memory_map.argc_address);
    if (count <= 1) return;
    const vector = try self.readCell(memory_map.argv_address);
    const first = try self.readCell(vector);
    try self.writeCell(memory_map.argc_address, count - 1);
    try self.writeCell(memory_map.argv_address, vector +% memory_map.cell_size);
    try self.writeCell(vector +% memory_map.cell_size, first);
}

fn pushArgument(self: *State, index: Cell) RuntimeError!void {
    const found = try argument(self, index);
    try self.push(found[0]);
    try self.push(@intCast(found[1]));
}

/// Shared by interpreted CATCH and catches kept by the compiled-code loop.
pub const CatchContext = struct {
    frame: CatchFrame,
    trace_depth: usize,
    profile_depth: usize,

    pub fn init(self: *const State) CatchContext {
        return .{
            .frame = .{
                .data_depth = self.data_depth,
                .float_depth = self.float_depth,
                .return_depth = self.return_depth,
                .loop_depth = self.loop_depth,
                .control_depth = self.control_depth,
                .interpret_loop_depth = self.interpret_loop_depth,
                .pending = self.pending,
                .compiling = self.compiling,
                .defining = self.defining,
                .local_count = self.local_count,
            },
            .trace_depth = self.trace_depth,
            .profile_depth = if (self.profile) |profile| profile.depth else 0,
        };
    }

    pub fn handleError(context: CatchContext, self: *State, err: RuntimeError) RuntimeError!void {
        if (err == error.Quit or err == error.StepLimit) return err;
        self.trace_depth = context.trace_depth;
        if (self.stepper == .on and self.step_depth > self.call_depth) self.stepper = .off;
        if (self.profile) |profile| profile.unwind(context.profile_depth);
        const code = self.throwCodeOf(err);
        self.abort_message = null;
        self.restoreCatchFrame(context.frame);
        try self.push(code);
    }
};

pub fn execute(self: *State, comptime builtin: Builtin) RuntimeError!void {
    switch (builtin) {
        .argc => try self.push(memory_map.argc_address),
        .argv => try self.push(memory_map.argv_address),
        .arg => try pushArgument(self, try self.pop()),
        .shift_args => try shiftArguments(self),
        // NEXT-ARG is 1 ARG SHIFT-ARGS.
        .next_arg => {
            try pushArgument(self, 1);
            try shiftArguments(self);
        },
        .bye => {
            try @import("blocks.zig").saveAll(self);
            self.halted = true;
        },
        .quit => return error.Quit,
        // Byte characters and extended characters share the standard event representation.
        .ekey_to_char => {
            const event = try self.pop();
            try self.push(event);
            try self.push(if (event >= 0 and event < 256) true_flag else 0);
        },
        .ekey_to_fkey => {
            const event = try self.pop();
            try self.push(event);
            try self.push(if (@import("standard_keys.zig").isFunction(event)) true_flag else 0);
        },
        // ENVIRONMENT? answers the queries about this system's sizes; others, and the
        // obsolescent word set names, give false.
        .environment_query => {
            const name = try self.memoryRange();
            const cells = [_]struct { []const u8, Cell }{
                .{ "/COUNTED-STRING", 255 },
                .{ "/HOLD", hold_top - hold_bottom },
                .{ "/PAD", string_buffer_base - pad_address },
                .{ "ADDRESS-UNIT-BITS", 8 },
                .{ "FLOORED", true_flag },
                .{ "MAX-CHAR", 255 },
                .{ "MAX-N", std.math.maxInt(Cell) },
                .{ "MAX-U", -1 },
                .{ "RETURN-STACK-CELLS", @intCast(self.return_stack.len) },
                .{ "STACK-CELLS", @intCast(self.data_stack.len) },
                .{ "FLOATING-STACK", @intCast(self.float_stack.len) },
                .{ "#LOCALS", max_locals },
                .{ "WORDLISTS", max_wordlists },
            };
            for (cells) |entry| {
                if (!defs.float_enabled and std.mem.eql(u8, entry[0], "FLOATING-STACK")) continue;
                if (asciiEqlIgnoreCase(name, entry[0])) {
                    try self.push(entry[1]);
                    return self.push(true_flag);
                }
            }
            if (asciiEqlIgnoreCase(name, "MAX-D") or asciiEqlIgnoreCase(name, "MAX-UD")) {
                try self.pushDouble(if (asciiEqlIgnoreCase(name, "MAX-D")) std.math.maxInt(Double) else -1);
                return self.push(true_flag);
            }
            if (defs.float_enabled and asciiEqlIgnoreCase(name, "MAX-FLOAT")) {
                try self.fpush(std.math.floatMax(Float));
                return self.push(true_flag);
            }
            try self.push(0);
        },
        .load => {
            const path = (try self.nextSourceToken()) orelse return error.InputUnavailable;
            const load_fn = self.writer.load_fn orelse return error.FileUnavailable;
            try @import("address_registry.zig").validate(self);
            try load_fn(self.writer.context, path, self);
        },
        .save => {
            const path = (try self.nextSourceToken()) orelse return error.InputUnavailable;
            const save_fn = self.writer.save_fn orelse return error.FileUnavailable;
            try prepareSave(self);
            try save_fn(self.writer.context, path, self);
        },
        .savesys => {
            const path = (try self.nextSourceToken()) orelse return error.InputUnavailable;
            const savesys_fn = self.writer.savesys_fn orelse return error.FileUnavailable;
            try prepareSave(self);
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
        .noop => {},
        // PERFORM ( addr -- ) is @ EXECUTE.
        .perform => try self.executeWord(try self.wordId(try self.readCell(try self.pop()))),
        .system => {
            const command = try self.memoryRange();
            const system_fn = self.writer.system_fn orelse return error.HostUnavailable;
            self.system_status = try system_fn(self.writer.context, command);
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
            const context = CatchContext.init(self);
            if (self.executeWord(xt)) |_| {
                try self.push(0);
            } else |err| {
                try context.handleError(self, err);
            }
        },
        else => @compileError(@tagName(builtin) ++ " is not in the words of this file"),
    }
}
