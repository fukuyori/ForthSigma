//! HELP and LICENSE.

const std = @import("std");
const defs = @import("defs.zig");
const forth = @import("../forth.zig");
const help_text = @import("help_text.zig");
const text_input = @import("text_input.zig");
const words_graphics = @import("words_graphics.zig");
const words_audio = @import("words_audio.zig");
const Builtin = defs.Builtin;
const RuntimeError = defs.RuntimeError;
const State = forth.State;

/// The built-in words this file executes; executeBuiltin dispatches by this list.
pub const words = [_]Builtin{ .help, .license };

pub fn execute(self: *State, comptime builtin: Builtin) RuntimeError!void {
    switch (builtin) {
        .help => {
            const name = nameOnSameLine(self) orelse return self.write(basic);
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
    var cursor = self.sourceCursor();
    if (cursor > 0 and cursor <= line.len and isLineEnd(line[cursor - 1])) return null;
    while (cursor < line.len and !isLineEnd(line[cursor]) and text_input.isSeparator(line[cursor])) cursor += 1;
    if (cursor == line.len or isLineEnd(line[cursor])) return null;
    const token = text_input.nextToken(line, &cursor);
    self.setSourceCursor(cursor);
    return token;
}

fn isLineEnd(byte: u8) bool {
    return byte == '\n' or byte == '\r';
}

/// Prints the description of a built-in or parser word, or says where to look for a
/// word the user defined. An unknown name is an error, as everywhere else.
fn describe(self: *State, name: []const u8) RuntimeError!void {
    if (self.lookup(name)) |id| {
        const group_word = words_graphics.isGraphicsWord(self, self.words[id]) or words_audio.isAudioWord(self, self.words[id]) or @import("words_gui.zig").isGuiWord(self, self.words[id]) or @import("words_game.zig").isGameWord(self, self.words[id]);
        if (id >= self.builtin_count and !(group_word and entry(name) != null)) {
            const word = self.words[id];
            const word_name = self.wordName(word);
            self.write(word_name);
            // Without SEE (-Dtools=false) the message does not point to it.
            if (!defs.tools_enabled) return self.write(" is a word defined after start-up.\n");
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
    for (&help_entries) |*candidate| {
        if (State.asciiEqlIgnoreCase(candidate.name, name)) return candidate;
    }
    return null;
}

/// The basic help, without what mentions the word groups the build leaves out: float
/// numbers without floating-point words, and SEE and LOCATE without the tools.
pub const basic = blk: {
    @setEvalBranchQuota(100_000);
    var text: []const u8 = help_text.basic;
    if (!defs.float_enabled) text = replaced(text, "123 is a cell, 123. a double cell, 1e or 1.5E3 a float (the E is needed);", "123 is a cell and 123. a double cell;");
    if (!defs.tools_enabled) {
        text = replaced(text, "  SEE name      show how a word is defined\n", "");
        text = replaced(text, "  LOCATE name   show the file and lines where a word was defined\n", "");
    }
    break :blk text;
};

fn replaced(comptime text: []const u8, comptime old: []const u8, comptime new: []const u8) []const u8 {
    const at = std.mem.indexOf(u8, text, old).?;
    return text[0..at] ++ new ++ text[at + old.len ..];
}

/// The help entries, without those of the words a build leaves out (-Dfloat=false and
/// the like).
pub const help_entries = blk: {
    @setEvalBranchQuota(10_000_000);
    var kept: [help_text.entries.len]help_text.Entry = undefined;
    var count: usize = 0;
    for (help_text.entries) |candidate| {
        if (isExcludedName(candidate.name)) continue;
        kept[count] = candidate;
        count += 1;
    }
    const result = kept[0..count].*;
    break :blk result;
};

/// A name of a built-in word the build leaves out, or of an F: or F^ local without
/// floating-point words.
fn isExcludedName(comptime name: []const u8) bool {
    for (@import("standard_keys.zig").constants) |constant| {
        if (std.mem.eql(u8, name, constant[0])) return false;
    }
    if (!defs.float_enabled and (std.mem.eql(u8, name, "F:") or std.mem.eql(u8, name, "F^"))) return true;
    if (std.mem.eql(u8, name, "REQUIRE-GRAPHICS")) return !defs.graphics_enabled;
    for (words_graphics.library_words) |library_word| {
        if (std.mem.eql(u8, library_word, name)) return !defs.graphics_enabled;
    }
    for (words_graphics.float_library_words) |library_word| {
        if (std.mem.eql(u8, library_word, name)) return !defs.graphics_enabled or !defs.float_enabled;
    }
    for (words_graphics.definitions) |definition| {
        if (std.mem.eql(u8, definition[0], name)) return defs.isExcludedBuiltin(definition[1]);
    }
    if (std.mem.eql(u8, name, "REQUIRE-GUI")) return !defs.graphics_enabled;
    for (@import("words_gui.zig").library_words) |library_word| {
        if (std.mem.eql(u8, library_word, name)) return !defs.graphics_enabled;
    }
    if (std.mem.eql(u8, name, "REQUIRE-GAME")) return !defs.graphics_enabled;
    for (@import("words_game.zig").library_words) |library_word| {
        if (std.mem.eql(u8, library_word, name)) return !defs.graphics_enabled;
    }
    if (std.mem.eql(u8, name, "REQUIRE-AUDIO")) return !defs.audio_enabled;
    for (words_audio.library_words) |library_word| {
        if (std.mem.eql(u8, library_word, name)) return !defs.audio_enabled;
    }
    for (words_audio.definitions) |definition| {
        if (std.mem.eql(u8, definition[0], name)) return defs.isExcludedBuiltin(definition[1]);
    }
    for (State.builtin_definitions) |definition| {
        if (std.mem.eql(u8, definition[0], name)) return defs.isExcludedBuiltin(definition[1]);
    }
    return false;
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
