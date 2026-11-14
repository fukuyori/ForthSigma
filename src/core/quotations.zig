//! Isolated quotation compiler frames; closures are deliberately unsupported.
const forth = @import("../forth.zig");
const defs = @import("defs.zig");
const map = @import("memory_map.zig");
pub const Frame = struct {
    defining: bool,
    compiling: bool,
    word: u16,
    data_start: map.Cell,
    branch: u16,
    locals: [map.max_locals]defs.Local,
    local_count: usize,
    locals_size: u16,
    controls: [map.max_controls]defs.Control,
    control_depth: usize,
    postponing: bool,
};
pub const words = [_]defs.Builtin{ .quote_open, .quote_close, .noname, .in_colon_def, .postpone_open, .postpone_s_quote, .postpone_print_quote, .postpone_left_bracket, .postpone_right_bracket, .postpone_parsed_string };

pub fn latest(self: *const forth.State) u16 {
    var id = self.word_count - 1;
    while (id != 0 and self.words[id].quotation) id -= 1;
    return id;
}
pub fn definitionName(self: *forth.State) forth.RuntimeError!?[]const u8 {
    return if (self.noname_next) "" else try self.nextSourceToken();
}
pub fn abort(self: *forth.State) void {
    if (self.quote_depth == 0) return;
    const frame = &self.quote_frames[0];
    const root = if (frame.defining) frame.word else self.quote_root;
    const start = self.words[root].data_here_before;
    self.code_count = self.words[root].code_start;
    self.names_used = self.words[root].name_start;
    self.dropWordsFrom(root);
    self.dropUsesFrom(root);
    @import("address_registry.zig").discardRange(self, start, self.data_here, .data, true);
    self.data_here = start;
    self.quote_depth = 0;
    self.postponing = false;
    self.noname_next = false;
    self.defining = false;
    self.setCompiling(false);
    self.control_depth = 0;
    self.local_count = 0;
    self.pending = .none;
}

pub fn execute(self: *forth.State, comptime word: defs.Builtin) forth.RuntimeError!void {
    switch (word) {
        .noname => self.noname_next = true,
        .in_colon_def => try self.push(if (self.defining) -1 else 0),
        .postpone_open => {
            if (!self.defining) return error.CompileOnly;
            self.postponing = true;
        },
        .quote_open => {
            if (self.quote_depth == self.quote_frames.len) return error.ControlStackOverflow;
            if (!self.defining and self.data_depth == self.data_stack.len) return error.StackOverflow;
            const branch = if (self.defining) try self.emit(.{ .kind = .branch }) else self.code_count;
            const frame = &self.quote_frames[self.quote_depth];
            frame.* = .{ .defining = self.defining, .compiling = self.compiling, .word = self.current_word, .data_start = self.current_data_start, .branch = branch, .locals = undefined, .local_count = self.local_count, .locals_size = self.locals_frame_size, .controls = undefined, .control_depth = self.control_depth, .postponing = self.postponing };
            @memcpy(frame.locals[0..self.local_count], self.locals[0..self.local_count]);
            @memcpy(frame.controls[0..self.control_depth], self.control_stack[0..self.control_depth]);
            const id = try self.appendAnonymousColon();
            self.words[id].quotation = frame.defining;
            if (self.quote_depth == 0) self.quote_root = id;
            self.quote_depth += 1;
            self.control_depth = 0;
            self.postponing = false;
            self.beginDefinition(id);
        },
        .quote_close => {
            if (self.quote_depth == 0) return error.ControlMismatch;
            if (!self.compiling or self.postponing) return error.CompileOnly;
            const destination = &self.quote_frames[self.quote_depth - 1];
            const needs_token = !destination.defining or !destination.compiling;
            if (needs_token and self.data_depth == self.data_stack.len) return error.StackOverflow;
            const need: usize = if (needs_token) 1 else 2;
            if (map.max_code - self.code_count < need) return error.CodeFull;
            const id = self.current_word;
            self.quote_closing = true;
            defer self.quote_closing = false;
            try self.endDefinition();
            self.quote_depth -= 1;
            const frame = &self.quote_frames[self.quote_depth];
            self.current_word = frame.word;
            self.current_data_start = frame.data_start;
            self.defining = frame.defining;
            self.setCompiling(frame.compiling);
            self.local_count = frame.local_count;
            self.locals_frame_size = frame.locals_size;
            @memcpy(self.locals[0..frame.local_count], frame.locals[0..frame.local_count]);
            self.control_depth = frame.control_depth;
            @memcpy(self.control_stack[0..frame.control_depth], frame.controls[0..frame.control_depth]);
            self.postponing = frame.postponing;
            if (frame.defining) {
                self.code[frame.branch].value = self.code_count;
                if (frame.compiling) _ = try self.emit(.{ .kind = .execution_token, .value = id }) else try self.push(id);
            } else try self.push(id);
        },
        .postpone_left_bracket => self.setCompiling(false),
        .postpone_right_bracket => {
            if (!self.defining or self.compiling) return error.CompileOnly;
            self.setCompiling(true);
        },
        .postpone_parsed_string => {
            const kind: defs.StringWord = switch (try self.pop()) {
                0 => .s_escape_quote,
                1 => .print_escape,
                2 => .c_quote,
                3 => .abort_quote,
                4 => .print_paren,
                else => return error.InvalidNumber,
            };
            var cursor = self.sourceCursor();
            try self.handleParsedString(kind, self.source_line, &cursor);
            self.setSourceCursor(cursor);
        },
        .postpone_s_quote, .postpone_print_quote => {
            var cursor = self.sourceCursor();
            if (word == .postpone_s_quote) try self.handleParsedString(.s_quote, self.source_line, &cursor) else try self.handleStringToken(".\"", self.source_line, &cursor, true);
            self.setSourceCursor(cursor);
        },
        else => unreachable,
    }
}

/// Postponing runs before ordinary parsing (string parsers are themselves postponed).
pub fn token(self: *forth.State, text: []const u8) forth.RuntimeError!void {
    if (std.ascii.eqlIgnoreCase(text, "[[")) {
        self.postponing = false;
        self.setCompiling(true);
        return;
    }
    if (std.mem.eql(u8, text, "[") or std.mem.eql(u8, text, "]")) {
        try self.compileCall(@intCast(self.builtinWord(if (text[0] == '[') .postpone_left_bracket else .postpone_right_bracket)));
        return;
    }
    if (std.ascii.eqlIgnoreCase(text, "S\"") or std.mem.eql(u8, text, ".\"")) {
        const builtin: defs.Builtin = if (text[0] == '.') .postpone_print_quote else .postpone_s_quote;
        try self.compileCall(@intCast(self.builtinWord(builtin)));
        return;
    }
    const parsed: ?map.Cell = if (std.ascii.eqlIgnoreCase(text, "S\\\"")) 0 else if (std.mem.eql(u8, text, ".\\\"")) 1 else if (std.ascii.eqlIgnoreCase(text, "C\"")) 2 else if (std.ascii.eqlIgnoreCase(text, "ABORT\"")) 3 else if (std.mem.eql(u8, text, ".(")) 4 else null;
    if (parsed) |kind| {
        if (map.max_code - self.code_count < 2) return error.CodeFull;
        _ = try self.emit(.{ .kind = .literal, .value = kind });
        _ = try self.emit(.{ .kind = .builtin, .value = @backingInt(defs.Builtin.postpone_parsed_string) });
        return;
    }
    if (self.findLocal(text)) |local| {
        if (local.kind == .xt and !local.variable) {
            _ = try self.emit(.{ .kind = .local_fetch, .value = forth.State.localOperand(local) });
            try self.compileCall(@intCast(self.builtinWord(.compile_comma)));
        } else {
            try self.compileLocalReference(local);
            _ = try self.emit(.{ .kind = .builtin, .value = @backingInt(if (local.kind == .float and !local.variable) defs.Builtin.fliteral else if (local.kind == .double and !local.variable) defs.Builtin.two_literal else defs.Builtin.literal) });
        }
        return;
    }
    if (self.lookup(text)) |id| {
        self.recordUse(id);
        const action = @import("word_semantics.zig").compilation(self, id);
        _ = try self.emit(.{ .kind = if (action.execute) .call else .compile_call, .value = action.target });
        return;
    }
    if (try self.parseNumber(text)) |n| {
        const cells = defs.doubleCells(n.value);
        _ = try self.emit(.{ .kind = .literal, .value = cells.low });
        if (n.double) _ = try self.emit(.{ .kind = .literal, .value = cells.high });
        _ = try self.emit(.{ .kind = .builtin, .value = @backingInt(if (n.double) defs.Builtin.two_literal else defs.Builtin.literal) });
        return;
    }
    if (defs.float_enabled and self.currentBase() == 10) if (forth.State.parseFloat(text, true)) |n| {
        _ = try self.emit(.{ .kind = .float_literal, .value = defs.floatBits(n) });
        _ = try self.emit(.{ .kind = .builtin, .value = @backingInt(defs.Builtin.fliteral) });
        return;
    };
    self.last_unknown_word = text;
    return error.UnknownWord;
}
const std = @import("std");
