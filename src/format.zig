//! The formatter of --format: it sets the indentation of the lines of a Forth source
//! file by the control structures they are in, and removes the blanks at the ends of
//! lines. It reads the text only, without running it.
//!
//! What it changes is the blanks before the first and after the last character of a
//! line that is not a blank; everything between them stays byte for byte, so the words
//! of the program, its strings, and its comments are the ones it had. In FORTH/Sigma a
//! string or a `( comment )` ends on its line, so no line is the inside of one.
//!
//! The rules:
//!
//! - A line inside a colon definition or a control structure is indented by `width`
//!   blanks for each step it is in. `IF`, `BEGIN`, `DO`, `?DO`, `CASE`, and `OF` open a
//!   structure, and `THEN`, `UNTIL`, `AGAIN`, `REPEAT`, `LOOP`, `+LOOP`, `ENDOF`, and
//!   `ENDCASE` close one.
//! - The structures that one line opens are one step together (`h 0 DO  w 0 DO`, closed
//!   by `LOOP LOOP`), and a structure opened after `ELSE` on its line, or before one,
//!   is no step of its own (`ELSE x IF`, and `x IF y ELSE` at the end of a line): the
//!   chains of conditions stay at one depth.
//! - A line that starts with a word that closes, with `ELSE`, `WHILE`, `DOES>`, or
//!   with `;` stands one step out. So does a line that gives the condition or the step
//!   of a loop before the word that takes it (`DONE @ UNTIL`, `2 +LOOP`, `DUP WHILE`).
//! - A line that starts with none of these words, in the same structure as the line
//!   before it and set further in than that line, is the rest of a long line: it keeps
//!   its distance from the line before it. The lines after it that stood under it
//!   stay under it.
//! - A line outside every structure keeps its indentation: the lines of a table after
//!   `CREATE` stay as they are. `[IF]`, `[ELSE]`, `[THEN]` and the other words in
//!   brackets do not indent: what they choose between is often a large part of a file.
//! - A tab in the indentation becomes blanks, to the next multiple of eight.
//! - The ends of the lines (LF or CR LF) stay as they are.
//!
//! The words are known by their names, whatever the program made of them: a program
//! that defines its own `IF` is indented as if it were the usual one.

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

/// The indentation of a line is at most this many steps.
const max_steps = 32;

/// The structures that are open, each with whether it is a step of the indentation.
const Open = struct {
    steps: [256]bool = undefined,
    count: usize = 0,
    /// The number of them when the colon definition being read started.
    definition_base: ?usize = null,
    /// The structure that the last line opened and followed by an ELSE at its end;
    /// the next line says whether it is a step.
    else_ended: ?usize = null,

    fn push(self: *Open, step: bool) void {
        if (self.count == self.steps.len) return;
        self.steps[self.count] = step;
        self.count += 1;
    }

    fn pop(self: *Open) void {
        self.count -|= 1;
    }

    /// The steps of the indentation of what is open.
    fn indentation(self: *const Open) usize {
        var steps: usize = 0;
        for (self.steps[0..self.count]) |step| steps += @intFromBool(step);
        return steps;
    }
};

/// The formatted `source`, in memory of `allocator`.
pub fn format(allocator: std.mem.Allocator, source: []const u8, width: usize) !Result {
    // A line grows by its new indentation at most (a tab of the old one counts as
    // eight blanks).
    const lines = std.mem.count(u8, source, "\n") + 1;
    const out = try allocator.alloc(u8, source.len * 16 + lines * (max_steps * width + 1));
    var length: usize = 0;
    var changed: usize = 0;
    var open = Open{};
    // The indentation of the last line that stood outside every structure.
    var margin: usize = 0;
    // Of the line before: the indentation its structure gave it, the one it had, and
    // the one it got.
    var last_wanted: usize = 0;
    var last_has: usize = 0;
    var last_blanks: usize = 0;
    const unit = writersStep(source) orelse width;
    var rest = source;
    while (rest.len > 0) {
        const newline = std.mem.indexOfScalar(u8, rest, '\n');
        const whole = if (newline) |at| rest[0 .. at + 1] else rest;
        rest = rest[whole.len..];
        // The end of the line stays as it is.
        const ending: []const u8 = if (std.mem.endsWith(u8, whole, "\r\n")) "\r\n" else if (std.mem.endsWith(u8, whole, "\n")) "\n" else "";
        const line = whole[0 .. whole.len - ending.len];
        const text = std.mem.trim(u8, line, " \t");
        const start = length;
        if (text.len != 0) {
            const has = indentationOf(line);
            // `x IF y ELSE` ended the line before: the IF is a step when the writer set
            // this line further in (what follows the ELSE is a part of its own), and
            // none when it stands under that line (a chain of conditions).
            if (open.else_ended) |entry| {
                if (entry < open.count) open.steps[entry] = has > last_has;
                open.else_ended = null;
            }
            const before = open.indentation();
            const place = scan(text, &open);
            // Outside every structure the indentation is the writer's, and what such a
            // line opens is indented from there.
            const outside = before == 0 and place.level == 0;
            if (outside) margin = has;
            const wanted = margin + @min(place.level, max_steps) * width;
            // The rest of a long line stands further in than the line before it: in the
            // same structure by any distance, and after a line that opened one by more
            // than a step of the writer's own indentation.
            const continues = if (wanted == last_wanted) has >= last_has else has > last_has + unit;
            const blanks = if (outside)
                has
            else if (place.exact or !continues)
                wanted
            else
                // As much further in as the writer set it (or under the line before it,
                // when it stood there).
                last_blanks + (has - last_has);
            last_wanted = wanted;
            last_has = has;
            last_blanks = blanks;
            @memset(out[length..][0..blanks], ' ');
            length += blanks;
            @memcpy(out[length..][0..text.len], text);
            length += text.len;
        }
        if (!std.mem.eql(u8, out[start..length], line)) changed += 1;
        @memcpy(out[length..][0..ending.len], ending);
        length += ending.len;
    }
    return .{ .text = out[0..length], .buffer = out, .changed = changed };
}

/// The indentation a line has, a tab going to the next multiple of eight.
fn indentationOf(line: []const u8) usize {
    var blanks: usize = 0;
    for (line) |byte| switch (byte) {
        ' ' => blanks += 1,
        '\t' => blanks += 8 - blanks % 8,
        else => break,
    };
    return blanks;
}

/// The step of the indentation of a text as it is written: the distance by which a line
/// most often stands further in than the line before it. Null for a text without one.
fn writersStep(source: []const u8) ?usize {
    var counts: [17]usize = @splat(0);
    var last: usize = 0;
    var lines = std.mem.splitScalar(u8, source, '\n');
    while (lines.next()) |line| {
        if (std.mem.trim(u8, line, " \t\r").len == 0) continue;
        const has = indentationOf(line);
        if (has > last and has - last < counts.len) counts[has - last] += 1;
        last = has;
    }
    var best: ?usize = null;
    for (counts, 0..) |count, step| {
        if (count != 0 and (best == null or count > counts[best.?])) best = step;
    }
    return best;
}

const Kind = enum { open, close, middle, colon, semicolon, name_follows, none };

/// Where a line stands: the steps of its indentation, and whether that is the place a
/// structure gives it (it starts with a word of one, or gives the condition of a loop)
/// or the least it may have.
const Place = struct { level: usize, exact: bool };

/// Reads the words of a line (without the blanks around it): opens and closes the
/// structures in `open`, and gives where the line stands.
fn scan(text: []const u8, open: *Open) Place {
    const before = open.indentation();
    var place = Place{ .level = before, .exact = false };
    var first = true;
    // Only words that close have come so far on this line.
    var leading_closes = true;
    // No word of a structure has come so far.
    var plain = true;
    // A structure that this line opened is a step already, or the line has an ELSE.
    var stepped = false;
    var opened_here: usize = 0;
    // The last word so far is an ELSE after a structure that this line opened.
    var ended_with_else = false;
    var index: usize = 0;
    while (nextWord(text, &index, &first)) |word| {
        const kind = kindOf(word);
        const structural = kind == .open or kind == .close or kind == .middle or kind == .colon or kind == .semicolon;
        ended_with_else = false;
        if (first and structural) place.exact = true;
        if (!first and plain and endsLoopAfterCondition(word)) {
            // `DONE @ UNTIL`, `2 +LOOP`, `DUP WHILE`: the condition or the step of a
            // loop stands with the word that takes it.
            place = .{ .level = before -| 1, .exact = true };
        }
        switch (kind) {
            .open => {
                open.push(!stepped);
                stepped = true;
                opened_here += 1;
            },
            .close => {
                open.pop();
                opened_here -|= 1;
                // A line that starts with words that close stands where what they
                // close stood.
                if (leading_closes) place.level = open.indentation();
            },
            .middle => {
                if (first) place.level = before -| 1;
                // A structure that follows an ELSE on its line is no step of its own
                // (`ELSE x IF`). Whether one that an ELSE follows is (`x IF y ELSE`
                // at the end of a line), the next line says.
                if (std.ascii.eqlIgnoreCase(word, "ELSE")) {
                    ended_with_else = opened_here > 0 and open.count > 0;
                    stepped = true;
                }
            },
            .colon => {
                // A structure opened on the line of the name is a step besides that of
                // the definition: `: T ( -- )   10 0 DO`, closed by `   LOOP ;`.
                open.definition_base = open.count;
                open.push(true);
                // The name of the definition is not a word of it.
                if (!std.ascii.eqlIgnoreCase(word, ":NONAME")) _ = nextName(text, &index);
            },
            // The end of the definition closes what was left open in it.
            .semicolon => if (open.definition_base) |base| {
                open.count = base;
                open.definition_base = null;
                if (first) place.level = open.indentation();
            },
            .name_follows => _ = nextName(text, &index),
            .none => {},
        }
        if (kind != .close) leading_closes = false;
        if (structural) plain = false;
        first = false;
    }
    if (ended_with_else) open.else_ended = open.count - 1;
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
        // S" text", ." text", ABORT" text", and the words of a program that end in a
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
    const Entry = struct { []const u8, Kind };
    const table = [_]Entry{
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
        \\      3
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
