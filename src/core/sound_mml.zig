//! The music macro language of MSX BASIC's PLAY, turned into the notes of one voice.
//!
//! The commands, their ranges, the defaults of an omitted number, the pitches, and the
//! lengths follow the MSX Red Book's description of the MSX1 ROM (see docs/DECISIONS.md,
//! "MSX の MML"). BASIC's variables (X and =name;) are not taken: a Forth program joins
//! the strings itself.

/// What a voice plays: a note or a rest for `ticks` of 1/50 second, or the end of one
/// PLAY (the voices start the next PLAY together).
pub const Event = struct {
    kind: Kind = .note,
    ticks: u16 = 0,
    /// The PSG's tone period on the MSX; 0 for a rest.
    period: u16 = 0,
    /// The same pitch for the other chips: octave × 12 + semitone (O4's A is 57, 440 Hz).
    note: u8 = 0,
    /// The instrument that `@` chose (0 to 63), for the chips that have instruments.
    instrument: u8 = 0,
    /// The PSG's amplitude register: a volume 0 to 15, or 16 to use the envelope.
    amplitude: u8 = 0,
    /// The envelope's shape (R13) and period (R11 and R12), when `amplitude` is 16.
    shape: u8 = 0,
    envelope_period: u16 = 0,

    pub const Kind = enum(u8) { note, end };
};

/// What each voice keeps from one PLAY to the next.
pub const Voice = struct {
    octave: u8 = 4,
    length: u8 = 4,
    tempo: u8 = 120,
    volume: u8 = 8,
    envelope: bool = false,
    shape: u8 = 0,
    envelope_period: u16 = 255,
    instrument: u8 = 0,
};

/// The instruments `@` can choose.
pub const instrument_count = 64;

pub const Error = error{InvalidMml};

/// The PSG's periods of octave 1 (C to B) on the MSX's clock; each octave halves them.
pub const octave1_periods = [12]u16{ 3421, 3228, 3047, 2876, 2715, 2562, 2419, 2283, 2155, 2034, 1920, 1812 };

/// The semitone of each letter A to G within its octave.
const letter_semitones = [7]u8{ 9, 11, 0, 2, 4, 5, 7 };

/// Reads one voice's MML a note at a time; the voice's octave, length, and the others
/// change as the commands come.
pub const Parser = struct {
    voice: *Voice,
    text: []const u8,
    position: usize = 0,

    pub fn init(voice: *Voice, text: []const u8) Parser {
        return .{ .voice = voice, .text = text };
    }

    /// The next note or rest, or null at the end of the text.
    pub fn next(self: *Parser) Error!?Event {
        while (true) {
            self.skipSpaces();
            if (self.position >= self.text.len) return null;
            const command = upper(self.text[self.position]);
            self.position += 1;
            switch (command) {
                'A'...'G' => return try self.note(command),
                'N' => {
                    const n = (try self.number()) orelse return error.InvalidMml;
                    if (n > 96) return error.InvalidMml;
                    if (n == 0) return try self.rest(self.voice.length);
                    return try self.tone(@intCast(n / 12 + 1), @intCast(n % 12), self.voice.length);
                },
                'R' => return try self.rest(try self.argument(1, 64, 4)),
                'O' => self.voice.octave = try self.argument(1, 8, 4),
                'L' => self.voice.length = try self.argument(1, 64, 4),
                'T' => self.voice.tempo = try self.argument(32, 255, 120),
                'V' => {
                    self.voice.volume = try self.argument(0, 15, 8);
                    self.voice.envelope = false;
                },
                'S' => {
                    self.voice.shape = try self.argument(0, 15, 0);
                    self.voice.envelope = true;
                },
                'M' => {
                    const period = (try self.number()) orelse 255;
                    if (period < 1 or period > 65535) return error.InvalidMml;
                    self.voice.envelope_period = @intCast(period);
                },
                '@' => self.voice.instrument = try self.argument(0, instrument_count - 1, 0),
                '<' => {
                    if (self.voice.octave <= 1) return error.InvalidMml;
                    self.voice.octave -= 1;
                },
                '>' => {
                    if (self.voice.octave >= 8) return error.InvalidMml;
                    self.voice.octave += 1;
                },
                else => return error.InvalidMml,
            }
        }
    }

    fn note(self: *Parser, letter: u8) Error!Event {
        var semitone: i8 = @intCast(letter_semitones[letter - 'A']);
        if (self.position < self.text.len) {
            switch (self.text[self.position]) {
                '+', '#' => {
                    semitone += 1;
                    self.position += 1;
                },
                '-' => {
                    semitone -= 1;
                    self.position += 1;
                },
                else => {},
            }
        }
        // As the ROM's table: B+ is C and C- is B of the same octave.
        const in_octave: u8 = @intCast(@mod(semitone, 12));
        const length = (try self.number()) orelse self.voice.length;
        if (length < 1 or length > 64) return error.InvalidMml;
        return self.tone(self.voice.octave, in_octave, @intCast(length));
    }

    fn tone(self: *Parser, octave: u8, semitone: u8, length: u8) Error!Event {
        var event: Event = .{
            .ticks = self.duration(length),
            .period = octave1_periods[semitone] >> @intCast(octave - 1),
            .note = octave * 12 + semitone,
            .instrument = self.voice.instrument,
        };
        if (self.voice.envelope) {
            event.amplitude = 16;
            event.shape = self.voice.shape;
            event.envelope_period = self.voice.envelope_period;
        } else {
            event.amplitude = self.voice.volume;
        }
        return event;
    }

    fn rest(self: *Parser, length: u8) Error!Event {
        return .{ .ticks = self.duration(length) };
    }

    /// 12000 / (length × tempo) ticks of 1/50 second, half again for each dot, and at
    /// least 5.
    fn duration(self: *Parser, length: u8) u16 {
        var ticks: f64 = 12000.0 / (@as(f64, @floatFromInt(length)) * @as(f64, @floatFromInt(self.voice.tempo)));
        while (self.position < self.text.len and self.text[self.position] == '.') : (self.position += 1) {
            ticks *= 1.5;
        }
        if (ticks >= 65535) return 65535;
        return @max(@as(u16, @intFromFloat(ticks)), 5);
    }

    /// A number in a range, or `default` when it is left out.
    fn argument(self: *Parser, low: u32, high: u32, default: u8) Error!u8 {
        const value = (try self.number()) orelse return default;
        if (value < low or value > high) return error.InvalidMml;
        return @intCast(value);
    }

    /// The decimal digits after a command, or null when there are none.
    fn number(self: *Parser) Error!?u32 {
        self.skipSpaces();
        var value: u32 = 0;
        var digits: usize = 0;
        while (self.position < self.text.len) : (self.position += 1) {
            const c = self.text[self.position];
            if (c < '0' or c > '9') break;
            value = value * 10 + (c - '0');
            if (value > 65535) return error.InvalidMml;
            digits += 1;
        }
        return if (digits == 0) null else value;
    }

    fn skipSpaces(self: *Parser) void {
        while (self.position < self.text.len and self.text[self.position] == ' ') self.position += 1;
    }
};

fn upper(c: u8) u8 {
    return if (c >= 'a' and c <= 'z') c - 32 else c;
}

/// Whether the whole text is valid MML for this voice, without changing the voice.
pub fn check(voice: Voice, text: []const u8) Error!void {
    var copy = voice;
    var parser = Parser.init(&copy, text);
    while (try parser.next()) |_| {}
}
