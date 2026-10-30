//! HELP and LICENSE.

const defs = @import("defs.zig");
const forth = @import("../forth.zig");
const help_text = @import("help_text.zig");
const text_input = @import("text_input.zig");
const Builtin = defs.Builtin;
const RuntimeError = defs.RuntimeError;
const State = forth.State;

/// The built-in words this file executes; executeBuiltin dispatches by this list.
pub const words = [_]Builtin{ .help, .license };

pub fn execute(self: *State, comptime builtin: Builtin) RuntimeError!void {
    switch (builtin) {
        .help => {
            const name = nameOnSameLine(self) orelse return self.write(help_text.basic);
            try describe(self, name);
        },
        .license => {
            self.write(license_text);
            self.write("\n");
            self.write(notices_text);
        },
        else => @compileError(@tagName(builtin) ++ " is not in the words of this file"),
    }
}

/// The next name if it is on the same line. HELP alone does not wait for input, and in
/// an EVALUATE string, whose lines are one input, it does not take a name from the next
/// line; the separator after HELP may already be that line end.
fn nameOnSameLine(self: *State) ?[]const u8 {
    const line = self.source_line;
    var cursor = self.source_cursor;
    if (cursor > 0 and cursor <= line.len and isLineEnd(line[cursor - 1])) return null;
    while (cursor < line.len and !isLineEnd(line[cursor]) and text_input.isSeparator(line[cursor])) cursor += 1;
    if (cursor == line.len or isLineEnd(line[cursor])) return null;
    self.source_cursor = cursor;
    return text_input.nextToken(line, &self.source_cursor);
}

fn isLineEnd(byte: u8) bool {
    return byte == '\n' or byte == '\r';
}

/// Prints the description of a built-in or parser word, or says where to look for a
/// word the user defined. An unknown name is an error, as everywhere else.
fn describe(self: *State, name: []const u8) RuntimeError!void {
    if (self.lookup(name)) |id| {
        if (id >= self.builtin_count) {
            const word = self.words[id];
            const word_name = self.wordName(word);
            self.write(word_name);
            self.write(" is a word defined after start-up; SEE ");
            self.write(word_name);
            self.write(" shows its definition.\n");
            return;
        }
    }
    const found = entry(name) orelse {
        self.last_unknown_word = name;
        return error.UnknownWord;
    };
    self.write(found.name);
    self.write(" ");
    self.write(found.stack);
    self.write("\n  ");
    self.write(found.text);
    self.write("\n");
}

pub fn entry(name: []const u8) ?*const help_text.Entry {
    for (&help_text.entries) |*candidate| {
        if (State.asciiEqlIgnoreCase(candidate.name, name)) return candidate;
    }
    return null;
}

const license_text = withoutCarriageReturns(@embedFile("license"));
const notices_text = withoutCarriageReturns(@embedFile("third_party_notices"));

/// The embedded files keep the line ends of the checkout; output uses LF throughout.
fn withoutCarriageReturns(comptime text: []const u8) []const u8 {
    comptime {
        @setEvalBranchQuota(100_000);
        var result: []const u8 = "";
        for (text) |byte| {
            if (byte != '\r') result = result ++ [_]u8{byte};
        }
        return result;
    }
}
