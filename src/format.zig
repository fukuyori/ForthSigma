//! The formatter of --format: it sets the indentation of the lines of a Forth source
//! file by the control structures they are in, and removes the blanks at the ends of
//! lines. It reads the text only, without running it.
//!
//! What it changes is the blanks before the first and after the last character of a
//! line that is not a blank; everything between them stays byte for byte, so the words
//! of the program, its strings, and its comments are the ones it had. In FORTH/Sigma a
//! string or a `( comment )` ends on its line, so no line is the inside of one.
//!
//! Each structure remembers where the line that opened it stands, and the lines are set
//! from there:
//!
//! - A line inside a colon definition or a control structure stands one step (`width`
//!   blanks) further in than the line that opened the innermost one. `IF`, `BEGIN`,
//!   `DO`, `?DO`, `CASE`, and `OF` open a structure, and `THEN`, `UNTIL`, `AGAIN`,
//!   `REPEAT`, `LOOP`, `+LOOP`, `ENDOF`, and `ENDCASE` close one. What one line opens
//!   is one step together (`h 0 DO  w 0 DO`, closed by `LOOP LOOP`); what the line of
//!   a definition's name opens is a step of its own (`: T ( -- )   10 0 DO`, closed
//!   by `   LOOP ;`).
//! - A line that starts with a word that closes stands under the line that opened what
//!   it closes; one that starts with `ELSE`, `WHILE`, or `DOES>` under the line that
//!   opened what it is a part of; `;` under the name. So does a line that gives the
//!   condition or the step of a loop before the word that takes it (`DONE @ UNTIL`,
//!   `2 +LOOP`, `DUP WHILE`).
//! - After a line that ends in `x IF y ELSE`, the lines stand under it, not a step
//!   in: the chains of conditions stay at one depth.
//! - A line that starts with none of these words and stands further in than the line
//!   before it is the rest of a long line: it keeps its distance from that line (in
//!   the same structure any distance, after a line that opened or closed one a
//!   distance of three steps or more), and what it opens is set from where it stands.
//! - A line outside every structure keeps its indentation: the lines of a table after
//!   `CREATE` stay as they are. `[IF]`, `[ELSE]`, `[THEN]` and the other words in
//!   brackets do not indent: what they choose between is often a large part of a file.
//! - A tab in the indentation becomes blanks: one step inside a structure, and to the
//!   next multiple of eight outside.
//! - The ends of the lines (LF or CR LF) stay as they are.
//!
//! The words are known by their names, whatever the program made of them: a program
//! that defines its own `IF` is indented as if it were the usual one. Formatting a text
//! that is formatted changes nothing.

const std = @import("std");

pub const default_width = 3;

/// What became of a text.
pub const Result = struct {
    /// The formatted text, at the start of `buffer`, which is what to free.
    text: []u8,
    buffer: []u8,
    /// The lines that are not as they were.
    changed: usize,
};

/// A structure that is open.
const Entry = struct {
    /// The indentation of the line that opened it; the lines in it stand a step
    /// further in, or under that line when `step` is false.
    base: usize = 0,
    step: bool = true,
    /// A number of its own, to tell whether two lines are in the same structure.
    id: usize = 0,
    /// Without a step: where the first line in it stands, which the writer may have
    /// set further in than the line that opened it; the lines after it stand there too.
    body: ?usize = null,
};

/// The structures that are open, innermost last.
const Open = struct {
    entries: [256]Entry = undefined,
    count: usize = 0,
    /// The ones that did not fit; they are closed first.
    beyond: usize = 0,
    /// The number of them when the colon definition being read started.
    definition_base: ?usize = null,
    next_id: usize = 1,

    fn push(self: *Open) void {
        if (self.count == self.entries.len) {
            self.beyond += 1;
            return;
        }
        self.entries[self.count] = .{ .id = self.next_id };
        self.next_id += 1;
        self.count += 1;
    }

    /// Closes the innermost one; gives it, when there was one that is kept.
    fn pop(self: *Open) ?Entry {
        if (self.beyond != 0) {
            self.beyond -= 1;
            return null;
        }
        if (self.count == 0) return null;
        self.count -= 1;
        return self.entries[self.count];
    }

    fn top(self: *const Open) ?Entry {
        return if (self.count == 0) null else self.entries[self.count - 1];
    }
};

/// The formatted `source`, in memory of `allocator`.
pub fn format(allocator: std.mem.Allocator, source: []const u8, width: usize) !Result {
    // The text is formatted twice: first only to learn how long it gets (a line may get
    // any indentation that a line before it had), then into memory of that length.
    var measure = Sink{ .buffer = null };
    const changed = formatInto(&measure, source, width);
    const out = try allocator.alloc(u8, measure.length);
    var sink = Sink{ .buffer = out };
    _ = formatInto(&sink, source, width);
    return .{ .text = out[0..sink.length], .buffer = out, .changed = changed };
}

/// Where the formatted text goes: into `buffer`, or nowhere, when only its length is
/// wanted.
const Sink = struct {
    buffer: ?[]u8,
    length: usize = 0,

    fn blanks(self: *Sink, count: usize) void {
        if (self.buffer) |buffer| @memset(buffer[self.length..][0..count], ' ');
        self.length += count;
    }

    fn bytes(self: *Sink, text: []const u8) void {
        if (self.buffer) |buffer| @memcpy(buffer[self.length..][0..text.len], text);
        self.length += text.len;
    }
};

/// Writes the formatted `source` to `sink`; gives the number of lines that change.
fn formatInto(sink: *Sink, source: []const u8, width: usize) usize {
    var changed: usize = 0;
    var open = Open{};
    // Of the line before: the innermost structure it was in (0: none), the indentation
    // it had, and the one it got.
    var last_in: usize = 0;
    var last_has: usize = 0;
    var last_blanks: usize = 0;
    // Whether it stood where its structure puts the lines in it.
    var last_inside = true;
    // The number of the first structure that it could open.
    var last_opened_from: usize = 1;
    var rest = source;
    while (rest.len > 0) {
        const newline = std.mem.indexOfScalar(u8, rest, '\n');
        const whole = if (newline) |at| rest[0 .. at + 1] else rest;
        rest = rest[whole.len..];
        // The end of the line stays as it is.
        const ending: []const u8 = if (std.mem.endsWith(u8, whole, "\r\n")) "\r\n" else if (std.mem.endsWith(u8, whole, "\n")) "\n" else "";
        const line = whole[0 .. whole.len - ending.len];
        const text = std.mem.trim(u8, line, " \t");
        if (text.len == 0) {
            if (line.len != 0) changed += 1;
            sink.bytes(ending);
            continue;
        }
        const indentation = line[0 .. @intFromPtr(text.ptr) - @intFromPtr(line.ptr)];
        const outside = open.count == 0;
        // Inside a structure a tab of the indentation is one step, as its writer meant
        // it; outside, where the indentation is kept, it goes to the next multiple of
        // eight, as it is shown.
        const has = measured(indentation, if (outside) 8 else @max(width, 1));
        const in: usize = if (open.top()) |entry| entry.id else 0;
        // Where the innermost structure puts a line.
        const inside: usize = if (open.top()) |entry| (if (entry.step) entry.base + width else entry.body orelse entry.base) else has;
        // After `x IF y ELSE` at the end of the line before, the lines stand under
        // that line, and one that the writer set further in keeps its distance.
        const chained = if (open.top()) |entry| !entry.step and entry.id >= last_opened_from else false;
        const opened_from = open.next_id;
        const place = scan(text, &open, inside);
        // The rest of a long line stands further in than the line before it: in the
        // same structure by any distance, and after a line that opened or closed one,
        // or that stood under the line of its structure, by three steps or more (less
        // is the indentation of a text written with other steps).
        const continues = if ((in == last_in and last_inside) or chained) has >= last_has else width != 0 and has >= last_has + 3 * width;
        const blanks = if (outside)
            has
        else if (place.exact or !continues)
            place.blanks
        else
            // As much further in as the writer set it (or under the line before it,
            // when it stood there).
            last_blanks + (has - last_has);
        // The first line after `x IF y ELSE` says where the lines after it stand.
        if (!place.exact) {
            for (open.entries[0..open.count]) |*entry| {
                if (entry.id == in and !entry.step and entry.body == null) entry.body = blanks;
            }
        }
        // What this line opened is set from where the line stands. What the line of a
        // definition's name opened, besides the definition, is a step of its own.
        var after_colon = false;
        for (open.entries[0..open.count]) |*entry| {
            if (entry.id < opened_from) continue;
            entry.base = if (after_colon) blanks + width else blanks;
            if (place.colon_id == entry.id) after_colon = true;
        }
        last_in = in;
        last_opened_from = opened_from;
        last_has = has;
        last_blanks = blanks;
        // A line that stands under the line of its structure (`ELSE`, `WHILE`, the
        // condition of a loop) is no line to stand further in than.
        last_inside = outside or !place.exact or blanks == inside;
        // The line is as it was when its indentation is these blanks and nothing
        // follows its last character.
        if (indentation.len != blanks or std.mem.indexOfScalar(u8, indentation, '\t') != null or indentation.len + text.len != line.len) changed += 1;
        sink.blanks(blanks);
        sink.bytes(text);
        sink.bytes(ending);
    }
    return changed;
}

/// The width of an indentation, a tab going to the next multiple of `tab`.
fn measured(indentation: []const u8, tab: usize) usize {
    var blanks: usize = 0;
    for (indentation) |byte| blanks += if (byte == '\t') tab - blanks % tab else 1;
    return blanks;
}

const Kind = enum { open, close, middle, colon, semicolon, name_follows, none };

/// Where a line stands: its indentation, and whether that is the place a structure
/// gives it (it starts with a word of one, or gives the condition of a loop) or the
/// place of a line like any other, which may be the rest of a long line instead.
/// `colon_id` is the definition that the line started, if it started one.
const Place = struct { blanks: usize, exact: bool, colon_id: usize = 0 };

/// Reads the words of a line (without the blanks around it): opens and closes the
/// structures in `open`, and gives where the line stands; `inside` is where the
/// innermost structure puts a line.
fn scan(text: []const u8, open: *Open, inside: usize) Place {
    var place = Place{ .blanks = inside, .exact = false };
    // Where the line that opened the innermost structure stands.
    const under: usize = if (open.top()) |entry| entry.base else inside;
    var first = true;
    var words: usize = 0;
    // Only words that close have come so far on this line.
    var leading_closes = true;
    // No word of a structure has come so far.
    var plain = true;
    const opened_from = open.next_id;
    // The last word so far is an ELSE after a structure that this line opened.
    var ended_with_else = false;
    var index: usize = 0;
    while (nextWord(text, &index, &first)) |word| {
        const kind = kindOf(word);
        const structural = kind == .open or kind == .close or kind == .middle or kind == .colon or kind == .semicolon;
        ended_with_else = false;
        // A word after a comment or a string does not start the line.
        if (words == 0 and !first) leading_closes = false;
        words += 1;
        if (first and structural) place.exact = true;
        if (!first and plain and endsLoopAfterCondition(word)) {
            // `DONE @ UNTIL`, `2 +LOOP`, `DUP WHILE`: the condition or the step of a
            // loop stands with the word that takes it.
            place.blanks = under;
            place.exact = true;
        }
        switch (kind) {
            .open => open.push(),
            .close => {
                const closed = open.pop();
                // A line that starts with words that close stands under the line that
                // opened what they close.
                if (leading_closes) {
                    if (closed) |entry| place.blanks = entry.base;
                }
            },
            .middle => {
                if (first) place.blanks = under;
                // `x IF y ELSE` at the end of a line: what follows stands under the
                // line, as the next condition of a chain does.
                if (std.ascii.eqlIgnoreCase(word, "ELSE")) {
                    if (open.top()) |entry| ended_with_else = entry.id >= opened_from;
                }
            },
            .colon => {
                open.definition_base = open.count;
                open.push();
                if (open.top()) |entry| place.colon_id = entry.id;
                // The name of the definition is not a word of it.
                if (!std.ascii.eqlIgnoreCase(word, ":NONAME")) _ = nextName(text, &index);
            },
            // The end of the definition closes what was left open in it.
            .semicolon => if (open.definition_base) |base| {
                if (first and base < open.count) place.blanks = open.entries[base].base;
                open.count = @min(open.count, base);
                open.beyond = 0;
                open.definition_base = null;
            },
            .name_follows => _ = nextName(text, &index),
            .none => {},
        }
        if (kind != .close) leading_closes = false;
        if (structural) plain = false;
        first = false;
    }
    if (ended_with_else and open.count > 0) open.entries[open.count - 1].step = false;
    return place;
}

/// The next word of the line, after what the words before it read from the line
/// themselves: a comment, a string, or a name. A word after a comment or a string is not
/// the `first` of its line.
fn nextWord(text: []const u8, index: *usize, first: *bool) ?[]const u8 {
    while (true) {
        const word = nextName(text, index) orelse return null;
        // A comment to the end of the line.
        if (std.mem.eql(u8, word, "\\")) {
            index.* = text.len;
            return null;
        }
        // ( comment ) and .( text ).
        if (std.mem.eql(u8, word, "(") or std.mem.eql(u8, word, ".(")) {
            skipPast(text, index, ')', false);
            first.* = false;
            continue;
        }
        // The strings, as the interpreter reads them. `" text"`: a quote by itself
        // starts one.
        if (std.mem.eql(u8, word, "\"")) {
            skipPast(text, index, '"', false);
            first.* = false;
            continue;
        }
        // `." text"`, and the text joined to the word: `."text"` ends in the word
        // itself, `."te xt"` at the next quote.
        if (std.mem.startsWith(u8, word, ".\"")) {
            if (word.len == 2 or word[word.len - 1] != '"') skipPast(text, index, '"', false);
            first.* = false;
            continue;
        }
        // S" text", C" text", ABORT" text", and the words of a program that end in a
        // quote as they do; S\" and .\" take \" as a part of the text.
        if (word.len > 1 and word[word.len - 1] == '"') {
            skipPast(text, index, '"', word.len > 2 and word[word.len - 2] == '\\');
            first.* = false;
            continue;
        }
        return word;
    }
}

/// The next run of characters that are not blanks.
fn nextName(text: []const u8, index: *usize) ?[]const u8 {
    while (index.* < text.len and (text[index.*] == ' ' or text[index.*] == '\t')) index.* += 1;
    if (index.* == text.len) return null;
    const start = index.*;
    while (index.* < text.len and text[index.*] != ' ' and text[index.*] != '\t') index.* += 1;
    return text[start..index.*];
}

/// Moves past the next `end` (after the one blank that follows the word), or to the end
/// of the line when there is none.
fn skipPast(text: []const u8, index: *usize, end: u8, escapes: bool) void {
    if (index.* < text.len) index.* += 1;
    while (index.* < text.len) : (index.* += 1) {
        const byte = text[index.*];
        if (escapes and byte == '\\' and index.* + 1 < text.len) {
            index.* += 1;
        } else if (byte == end) {
            index.* += 1;
            return;
        }
    }
}

/// A word that ends a loop, or its first part, and takes what the words before it on
/// the line worked out.
fn endsLoopAfterCondition(word: []const u8) bool {
    return std.ascii.eqlIgnoreCase(word, "UNTIL") or std.ascii.eqlIgnoreCase(word, "+LOOP") or std.ascii.eqlIgnoreCase(word, "WHILE");
}

fn kindOf(word: []const u8) Kind {
    const Name = struct { []const u8, Kind };
    const table = [_]Name{
        .{ ":", .colon },                  .{ ":NONAME", .colon },          .{ ";", .semicolon },
        .{ "IF", .open },                  .{ "BEGIN", .open },             .{ "DO", .open },
        .{ "?DO", .open },                 .{ "CASE", .open },              .{ "OF", .open },
        .{ "?OF", .open },                 .{ "THEN", .close },             .{ "ENDIF", .close },
        .{ "UNTIL", .close },              .{ "AGAIN", .close },            .{ "REPEAT", .close },
        .{ "LOOP", .close },               .{ "+LOOP", .close },            .{ "ENDCASE", .close },
        .{ "ENDOF", .close },              .{ "CONTOF", .close },           .{ "NEXT-CASE", .close },
        .{ "ELSE", .middle },              .{ "WHILE", .middle },           .{ "DOES>", .middle },
        // The words that read a name, which may be that of a word above.
        .{ "CHAR", .name_follows },        .{ "[CHAR]", .name_follows },    .{ "'", .name_follows },
        .{ "[']", .name_follows },         .{ "POSTPONE", .name_follows },  .{ "[COMPILE]", .name_follows },
        .{ "TO", .name_follows },          .{ "+TO", .name_follows },       .{ "IS", .name_follows },
        .{ "ACTION-OF", .name_follows },   .{ "DEFER", .name_follows },     .{ "CREATE", .name_follows },
        .{ "VARIABLE", .name_follows },    .{ "CONSTANT", .name_follows },  .{ "VALUE", .name_follows },
        .{ "2VARIABLE", .name_follows },   .{ "2CONSTANT", .name_follows }, .{ "2VALUE", .name_follows },
        .{ "FVARIABLE", .name_follows },   .{ "FCONSTANT", .name_follows }, .{ "FVALUE", .name_follows },
        .{ "BUFFER:", .name_follows },     .{ "MARKER", .name_follows },    .{ "FORGET", .name_follows },
        .{ "SYNONYM", .name_follows },     .{ "ALIAS", .name_follows },     .{ "[DEFINED]", .name_follows },
        .{ "[UNDEFINED]", .name_follows }, .{ "SEE", .name_follows },       .{ "LOCATE", .name_follows },
        .{ "WHERE", .name_follows },       .{ "HELP", .name_follows },      .{ "DBG", .name_follows },
        .{ "INCLUDE", .name_follows },     .{ "REQUIRE", .name_follows },   .{ "~~VALUE", .name_follows },
        .{ "BEGIN-STRUCTURE", .name_follows },
    };
    for (table) |entry| {
        if (std.ascii.eqlIgnoreCase(word, entry[0])) return entry[1];
    }
    return .none;
}

fn expectFormat(expected: []const u8, source: []const u8) !void {
    const result = try format(std.testing.allocator, source, default_width);
    defer std.testing.allocator.free(result.buffer);
    try std.testing.expectEqualStrings(expected, result.text);
    // The words of each line are the ones it had.
    var was = std.mem.splitScalar(u8, source, '\n');
    var is = std.mem.splitScalar(u8, result.text, '\n');
    while (was.next()) |line| try std.testing.expectEqualStrings(std.mem.trim(u8, line, " \t\r"), std.mem.trim(u8, is.next().?, " \t\r"));
    try std.testing.expect(is.next() == null);
    // What is formatted stays as it is.
    const again = try format(std.testing.allocator, result.text, default_width);
    defer std.testing.allocator.free(again.buffer);
    try std.testing.expectEqualStrings(result.text, again.text);
    try std.testing.expectEqual(@as(usize, 0), again.changed);
}

test "lines are indented by the structures they are in" {
    try expectFormat(
        \\: SIGN ( n -- )
        \\   DUP 0< IF
        \\      DROP ." minus"
        \\   ELSE
        \\      0= IF ." zero" ELSE ." plus" THEN
        \\   THEN ;
        \\: COUNT-UP ( n -- )
        \\   0 ?DO
        \\      I .
        \\   LOOP ;
        \\: PICKS ( c -- n )
        \\   CASE
        \\      [CHAR] A OF 1 ENDOF
        \\      [CHAR] B OF
        \\         2
        \\      ENDOF
        \\      0 SWAP
        \\   ENDCASE ;
        \\: WAITS BEGIN KEY? 0= WHILE 1 MS REPEAT ;
        \\
    ,
        \\: SIGN ( n -- )
        \\DUP 0< IF
        \\DROP ." minus"
        \\ELSE
        \\  0= IF ." zero" ELSE ." plus" THEN
        \\        THEN ;
        \\: COUNT-UP ( n -- )
        \\0 ?DO
        \\I .
        \\LOOP ;
        \\: PICKS ( c -- n )
        \\CASE
        \\[CHAR] A OF 1 ENDOF
        \\[CHAR] B OF
        \\2
        \\ENDOF
        \\0 SWAP
        \\ENDCASE ;
        \\: WAITS BEGIN KEY? 0= WHILE 1 MS REPEAT ;
        \\
    );
}

test "the condition of a loop stands with the word that takes it" {
    try expectFormat(
        \\: POLL ( -- )
        \\   BEGIN
        \\      STEP
        \\   DONE @ UNTIL
        \\   10 0 DO
        \\      I .
        \\   2 +LOOP
        \\   BEGIN
        \\      MORE?
        \\   WHILE
        \\      ONE
        \\   REPEAT
        \\   BEGIN
        \\   DUP 0> WHILE
        \\      1-
        \\   REPEAT DROP ;
        \\
    ,
        \\: POLL ( -- )
        \\BEGIN
        \\STEP
        \\DONE @ UNTIL
        \\10 0 DO
        \\I .
        \\2 +LOOP
        \\BEGIN
        \\MORE?
        \\WHILE
        \\ONE
        \\REPEAT
        \\BEGIN
        \\DUP 0> WHILE
        \\1-
        \\REPEAT DROP ;
        \\
    );
}

test "what one line opens is one step, and chains of conditions stay at one depth" {
    try expectFormat(
        \\: FILL-ALL ( -- )
        \\   h 0 DO  w 0 DO
        \\      I J DOT
        \\   LOOP LOOP ;
        \\: CLASS ( n -- )
        \\   DUP 1 = IF
        \\      ONE
        \\   ELSE DUP 2 = IF
        \\      TWO
        \\   ELSE
        \\      MANY
        \\   THEN THEN DROP ;
        \\: BYTES ( b -- n )
        \\   DUP $80 < IF  1  ELSE
        \\   DUP $E0 < IF  2  ELSE
        \\      3
        \\   THEN THEN NIP ;
        \\
    ,
        \\: FILL-ALL ( -- )
        \\h 0 DO  w 0 DO
        \\I J DOT
        \\LOOP LOOP ;
        \\: CLASS ( n -- )
        \\DUP 1 = IF
        \\ONE
        \\ELSE DUP 2 = IF
        \\TWO
        \\ELSE
        \\MANY
        \\THEN THEN DROP ;
        \\: BYTES ( b -- n )
        \\DUP $80 < IF  1  ELSE
        \\DUP $E0 < IF  2  ELSE
        \\   3
        \\THEN THEN NIP ;
        \\
    );
}

test "what a word reads from the line is not a word: comments, strings, and names" {
    try expectFormat(
        \\: T ( IF this were read, the rest would move )
        \\   ." IF " S" THEN" 2DROP \ IF BEGIN DO
        \\   [CHAR] : EMIT  POSTPONE IF  ['] ; DROP
        \\   S\" a \" IF" 2DROP .( DO )
        \\   1 ;
        \\: IF-NOT 0= ;
        \\1 .
        \\
    ,
        \\: T ( IF this were read, the rest would move )
        \\." IF " S" THEN" 2DROP \ IF BEGIN DO
        \\[CHAR] : EMIT  POSTPONE IF  ['] ; DROP
        \\S\" a \" IF" 2DROP .( DO )
        \\1 ;
        \\: IF-NOT 0= ;
        \\1 .
        \\
    );
}

test "a line may stand further in than its structure puts it, but not further out" {
    try expectFormat(
        \\: DRAW ( -- )
        \\   10 20 MOVE-TO  30 40 LINE-TO
        \\                  50 60 LINE-TO
        \\   FLAG IF
        \\      ONE
        \\      TWO THEN ;
        \\
    ,
        \\: DRAW ( -- )
        \\   10 20 MOVE-TO  30 40 LINE-TO
        \\                  50 60 LINE-TO
        \\ FLAG IF
        \\  ONE
        \\TWO THEN ;
        \\
    );
}

test "the lines outside every structure keep their indentation, and blanks at the ends go" {
    try expectFormat("CREATE TABLE\n      1 , 2 ,\n      3 , 4 ,\n\n0 [IF]\n: A ;\n[ELSE]\n   : B\n      1 ;\n[THEN]\n\\ end", "CREATE TABLE  \n      1 , 2 ,\t\n      3 , 4 ,\n   \n0 [IF]\n: A ;\n[ELSE]\n   : B\n1 ;\n[THEN]\n\\ end");
    // A tab in the indentation becomes blanks, and CR LF stays.
    try expectFormat("        1 ,\r\n: T\r\n   2 ;\r\n", "\t1 ,\r\n: T\r\n\t2 ;  \r\n");
}

test "a definition that leaves a structure open does not move what follows it" {
    try expectFormat(
        \\: OPEN
        \\   IF
        \\      1 ;
        \\: NEXT-ONE
        \\   2 ;
        \\THEN THEN
        \\3
        \\
    ,
        \\: OPEN
        \\IF
        \\1 ;
        \\: NEXT-ONE
        \\2 ;
        \\THEN THEN
        \\3
        \\
    );
}

test "the name's line may open a structure, and a word after a string does not start its line" {
    try expectFormat(
        \\: SCAN ( -- )   10 0 DO
        \\      I .
        \\   LOOP ;
        \\: TEXT ( -- c-addr u )
        \\   S" hello" ;
        \\: NOTE ( -- )
        \\   ( the end ) ;
        \\
    ,
        \\: SCAN ( -- )   10 0 DO
        \\I .
        \\LOOP ;
        \\: TEXT ( -- c-addr u )
        \\S" hello" ;
        \\: NOTE ( -- )
        \\( the end ) ;
        \\
    );
}

test "a file indented by tabs or by four blanks comes to the same steps" {
    try expectFormat(": T\n   X IF\n      Y\n   THEN\n   Z ;\n", ": T\n\tX IF\n\t\tY\n\tTHEN\n\tZ ;\n");
    // MORE, the rest of the line of Y, keeps its distance of four blanks from it.
    try expectFormat(": T\n   X IF\n      Y\n          MORE\n   THEN\n   Z ;\n", ": T\n    X IF\n        Y\n            MORE\n    THEN\n    Z ;\n");
}

test "the changed lines are counted" {
    const result = try format(std.testing.allocator, ": T\n1 ;\n: U\n   2 ;\n", default_width);
    defer std.testing.allocator.free(result.buffer);
    try std.testing.expectEqual(@as(usize, 1), result.changed);
}

test "an indentation carried to the lines of a definition fits in the memory for it" {
    // A thousand blanks before the name are the margin of each line of the definition.
    var source: [2048]u8 = undefined;
    @memset(source[0..1000], ' ');
    var length: usize = 1000;
    for (0..102) |line| {
        const part: []const u8 = if (line == 0) ": T\n" else if (line == 101) ";\n" else "1\n";
        @memcpy(source[length..][0..part.len], part);
        length += part.len;
    }
    const result = try format(std.testing.allocator, source[0..length], default_width);
    defer std.testing.allocator.free(result.buffer);
    try std.testing.expectEqual(result.buffer.len, result.text.len);
    try std.testing.expectEqual(@as(usize, 1004 + 100 * 1005 + 1002), result.text.len);
    try std.testing.expectEqual(@as(usize, 101), result.changed);
}

test "strings are read as the interpreter reads them" {
    // A quote by itself starts a string, and a string joined to ." ends in its word.
    try expectFormat(
        \\: T
        \\   " IF " TYPE
        \\   1 .
        \\   FLAG IF
        \\      ."yes" THEN
        \\   ."a b" THEN" CR
        \\   2 . ;
        \\
    ,
        \\: T
        \\" IF " TYPE
        \\1 .
        \\FLAG IF
        \\."yes" THEN
        \\."a b" THEN" CR
        \\2 . ;
        \\
    );
}

test "with steps of no blanks, the indentation of the structures goes" {
    const result = try format(std.testing.allocator, ": T\n   1\n   X IF\n      2\n   THEN\n;\n  3\n", 0);
    defer std.testing.allocator.free(result.buffer);
    try std.testing.expectEqualStrings(": T\n1\nX IF\n2\nTHEN\n;\n  3\n", result.text);
    try std.testing.expectEqual(@as(usize, 4), result.changed);
}

test "what is formatted stays as it is when it is formatted again" {
    // The text of the review: a margin, steps of four and three, and lines set further
    // in.
    try expectStable(" : T\n     X IF\n        Y\n          Z\n THEN\n     Q\n      ;\n", default_width);

    // And texts made of the words of structures and others, in any order, with any
    // indentation: whatever they mean, formatting them twice gives what once gives.
    const words = [_][]const u8{
        ":", "T",   ";",    "IF",   "ELSE",  "THEN",   "BEGIN", "WHILE", "REPEAT", "UNTIL", "AGAIN", "DO",    "?DO", "LOOP", "+LOOP",
        "CASE", "OF", "ENDOF", "ENDCASE", "DOES>", "X",     "1",     "DUP",    "[IF]",  "[THEN]", "\\ c", "( c )", ".\" s\"", "S\" IF\"", "CREATE",
    };
    var random = std.Random.DefaultPrng.init(20261111);
    var source: [4096]u8 = undefined;
    for (0..400) |_| {
        var length: usize = 0;
        const lines = random.random().uintLessThan(usize, 24) + 1;
        for (0..lines) |_| {
            // Blank lines, tabs, and blanks at the end too.
            const indentation = random.random().uintLessThan(usize, 14);
            for (0..indentation) |_| {
                source[length] = if (random.random().uintLessThan(u8, 12) == 0) '\t' else ' ';
                length += 1;
            }
            for (0..random.random().uintLessThan(usize, 5)) |_| {
                const word = words[random.random().uintLessThan(usize, words.len)];
                @memcpy(source[length..][0..word.len], word);
                length += word.len;
                source[length] = ' ';
                length += 1;
            }
            source[length] = '\n';
            length += 1;
        }
        for ([_]usize{ 0, 2, default_width, 4 }) |width| try expectStable(source[0..length], width);
    }
}

/// Formats `source`, and what that gives again: the second time nothing changes. The
/// words of each line stay the ones it had.
fn expectStable(source: []const u8, width: usize) !void {
    const once = try format(std.testing.allocator, source, width);
    defer std.testing.allocator.free(once.buffer);
    var was = std.mem.splitScalar(u8, source, '\n');
    var is = std.mem.splitScalar(u8, once.text, '\n');
    while (was.next()) |line| try std.testing.expectEqualStrings(std.mem.trim(u8, line, " \t\r"), std.mem.trim(u8, is.next().?, " \t\r"));
    const twice = try format(std.testing.allocator, once.text, width);
    defer std.testing.allocator.free(twice.buffer);
    std.testing.expectEqualStrings(once.text, twice.text) catch |err| {
        std.debug.print("the source ({d} blanks a step):\n{s}\n", .{ width, source });
        return err;
    };
    try std.testing.expectEqual(@as(usize, 0), twice.changed);
}
