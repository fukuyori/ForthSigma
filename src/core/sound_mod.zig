//! Playing ProTracker modules (MOD files) for LOAD-MOD and PLAY-MOD: four channels of
//! 8-bit samples, the patterns of 64 rows, and the effects most modules use, on Paula's
//! periods and through the Amiga's filters.
//!
//! The format and the effects follow ProTracker's published description (see
//! docs/DECISIONS.md, "S6"); no player's code is used. The module's patterns, samples,
//! and song are in the pool of samples (sound_pcm.zig), which the audio thread reads.

const std = @import("std");
const pcm = @import("sound_pcm.zig");
const amiga = @import("sound_amiga.zig");

pub const channel_count = 4;
pub const sample_count = 31;
/// The header: the title, 31 samples' descriptions, the song, and the format's tag.
pub const header_size = 1084;
/// A pattern: 64 rows of 4 channels of 4 bytes.
pub const pattern_size = 64 * channel_count * 4;
/// ProTracker's highest and lowest periods (B-3 and C-1).
pub const min_period = 113;
pub const max_period = 856;

pub const Error = error{InvalidMod};

/// One sample: `length` frames from `start` in the pool, its loop (none when
/// `loop_length` is 0), its finetune (-8 to 7, eighths of a semitone), and its volume.
pub const SampleInfo = extern struct {
    start: u32 = 0,
    length: u32 = 0,
    loop_start: u32 = 0,
    loop_length: u32 = 0,
    finetune: i8 = 0,
    volume: u8 = 0,
    pad: [2]u8 = .{ 0, 0 },
};

/// What the audio thread needs of a module; kept in the pool as bytes, and copied out.
pub const Song = extern struct {
    samples: [sample_count]SampleInfo = @splat(.{}),
    order: [128]u8 = @splat(0),
    /// The positions the song plays, 1 to 128 (0: no module).
    length: u8 = 0,
    pattern_count: u8 = 0,
    pad: [2]u8 = .{ 0, 0 },
    /// Where the patterns start in the pool, in bytes.
    patterns_at: u32 = 0,
};

fn bigEndian16(bytes: []const u8) u32 {
    return @as(u32, bytes[0]) << 8 | bytes[1];
}

/// The song in a header, without the places in the pool: the format's tag must be one
/// of ProTracker's for four channels.
pub fn parseHeader(header: *const [header_size]u8) Error!Song {
    const tag = header[1080..1084];
    const tags = [_]*const [4]u8{ "M.K.", "M!K!", "FLT4", "4CHN" };
    for (tags) |known| {
        if (std.mem.eql(u8, tag, known)) break;
    } else return error.InvalidMod;
    var song: Song = .{};
    for (&song.samples, 0..) |*info, i| {
        const h = header[20 + i * 30 ..][0..30];
        info.length = bigEndian16(h[22..24]) * 2;
        const nibble: i8 = @intCast(h[24] & 0x0f);
        info.finetune = if (nibble > 7) nibble - 16 else nibble;
        info.volume = @min(h[25], 64);
        info.loop_start = bigEndian16(h[26..28]) * 2;
        info.loop_length = bigEndian16(h[28..30]) * 2;
        // A loop of one word means none; a loop past the end is cut to it.
        if (info.loop_length <= 2 or info.loop_start >= info.length) {
            info.loop_start = 0;
            info.loop_length = 0;
        } else {
            info.loop_length = @min(info.loop_length, info.length - info.loop_start);
        }
    }
    song.length = header[950];
    if (song.length == 0 or song.length > 128) return error.InvalidMod;
    @memcpy(&song.order, header[952..1080]);
    var highest: u8 = 0;
    for (song.order) |pattern| highest = @max(highest, pattern);
    if (highest >= 128) return error.InvalidMod;
    song.pattern_count = highest + 1;
    return song;
}

/// ProTracker's vibrato and tremolo: half a sine in 32 steps.
const sine = [32]u8{ 0, 24, 49, 74, 97, 120, 141, 161, 180, 197, 212, 224, 235, 244, 250, 253, 255, 253, 250, 244, 235, 224, 212, 197, 180, 161, 141, 120, 97, 74, 49, 24 };

fn waveValue(position: u8, depth: u8) i32 {
    const value = @as(i32, sine[position & 31]) * depth;
    return if (position & 32 != 0) -value else value;
}

/// A period moved by a finetune of `finetune` eighths of a semitone.
fn finetuned(period: u32, finetune: i8) u16 {
    if (finetune == 0) return @intCast(period);
    const factor = std.math.pow(f32, 2.0, -@as(f32, @floatFromInt(finetune)) / 96.0);
    return @intFromFloat(@round(@as(f32, @floatFromInt(period)) * factor));
}

const Channel = struct {
    player: pcm.Player = .{},
    /// The sample (1 to 31), 0 before one.
    sample: u8 = 0,
    /// The note's period and the period now (portamento moves it); 0 before a note.
    note_period: u16 = 0,
    period: u16 = 0,
    target: u16 = 0,
    porta_speed: u8 = 0,
    volume: i32 = 0,
    vibrato_position: u8 = 0,
    vibrato_speed: u8 = 0,
    vibrato_depth: u8 = 0,
    tremolo_position: u8 = 0,
    tremolo_speed: u8 = 0,
    tremolo_depth: u8 = 0,
    offset: u8 = 0,
    loop_row: u8 = 0,
    loop_count: u8 = 0,
    /// This row's effect and its parameter.
    effect: u8 = 0,
    param: u8 = 0,
    /// A note EDx starts later in the row.
    delayed: u16 = 0,
    /// The period and the volume the channel sounds with this tick.
    out_period: u16 = 0,
    out_volume: i32 = 0,
};

pub const Mod = struct {
    sample_rate: u32,
    song: Song = .{},
    playing: bool = false,
    repeat: bool = false,
    position: u8 = 0,
    row: u8 = 0,
    tick: u8 = 0,
    speed: u8 = 6,
    tempo: u8 = 125,
    /// Samples until the next tick.
    tick_left: f64 = 0,
    /// The times the row is played again (EEx), and whether it is being played again.
    pattern_delay: u8 = 0,
    repeating: bool = false,
    jump: ?u8 = null,
    break_row: ?u8 = null,
    /// Whether the jump is a pattern loop's (E6x), which plays rows again on purpose.
    pattern_loop: bool = false,
    /// The rows played, by position: a song played once ends when it jumps to one.
    visited: [128]u64 = @splat(0),
    channels: [channel_count]Channel = @splat(.{}),
    filters: amiga.Filters,

    pub fn init(sample_rate: u32) Mod {
        return .{ .sample_rate = sample_rate, .filters = amiga.Filters.init(sample_rate) };
    }

    /// Plays the song from its start, again from the start after its end when `repeat`.
    pub fn start(self: *Mod, repeat: bool) void {
        const song = self.song;
        self.* = Mod.init(self.sample_rate);
        self.song = song;
        self.repeat = repeat;
        self.playing = song.length > 0;
    }

    pub fn stop(self: *Mod) void {
        self.playing = false;
        for (&self.channels) |*channel| channel.player.active = false;
    }

    /// The next left and right samples, about -1 to 1. `led` is the LED filter, which
    /// the effect E0x turns on and off.
    pub fn sample(self: *Mod, pool: []const i16, led: *bool) [2]f32 {
        if (!self.playing) return .{ 0, 0 };
        if (self.tick_left <= 0) {
            // A tempo set on this tick (Fxx) counts from the next one.
            const tempo = self.tempo;
            self.doTick(pool, led);
            self.tick_left += @as(f64, @floatFromInt(self.sample_rate)) * 2.5 / @as(f64, @floatFromInt(tempo));
        }
        self.tick_left -= 1;
        var sides: [2]f32 = .{ 0, 0 };
        for (&self.channels, 0..) |*channel, c| {
            const value = channel.player.next(pool) * @as(f32, @floatFromInt(channel.out_volume)) / 64.0;
            // Channels 1 and 4 on the left, 2 and 3 on the right, as Paula's.
            sides[if (c == 0 or c == 3) 0 else 1] += value / 2;
        }
        return self.filters.process(sides, led.*);
    }

    /// One tick: the next row starts when the last tick of a row has had its time.
    fn doTick(self: *Mod, pool: []const i16, led: *bool) void {
        if (self.tick >= self.speed) {
            self.tick = 0;
            if (self.pattern_delay > 0) {
                // EEx: the row again, without its notes; its slides go on.
                self.pattern_delay -= 1;
                self.repeating = true;
            } else {
                self.repeating = false;
                self.nextRow();
                if (!self.playing) return;
            }
        }
        if (self.tick == 0 and !self.repeating) {
            self.readRow(pool, led);
        } else {
            for (&self.channels) |*channel| self.tickEffect(channel);
        }
        for (&self.channels) |*channel| self.sound(channel);
        self.tick += 1;
    }

    fn nextRow(self: *Mod) void {
        const jumped = self.jump != null or self.break_row != null;
        const pattern_loop = self.pattern_loop;
        self.pattern_loop = false;
        if (jumped) {
            self.position = self.jump orelse self.position +% 1;
            self.row = self.break_row orelse 0;
            self.jump = null;
            self.break_row = null;
        } else {
            self.row += 1;
            if (self.row >= 64) {
                self.row = 0;
                self.position +%= 1;
            }
        }
        if (self.position >= self.song.length) {
            if (!self.repeat) return self.stop();
            self.position = 0;
        }
        // A song played once ends where it would go round again (Bxx or Dxx back).
        if (jumped and !pattern_loop and !self.repeat and self.visited[self.position] >> @intCast(self.row) & 1 != 0) self.stop();
    }

    fn readRow(self: *Mod, pool: []const i16, led: *bool) void {
        self.visited[self.position] |= @as(u64, 1) << @intCast(self.row);
        const bytes = std.mem.sliceAsBytes(pool);
        const pattern = self.song.order[self.position];
        const at = @as(usize, self.song.patterns_at) + @as(usize, pattern) * pattern_size + @as(usize, self.row) * channel_count * 4;
        for (&self.channels, 0..) |*channel, c| {
            const cell = if (at + c * 4 + 4 <= bytes.len) bytes[at + c * 4 ..][0..4].* else [4]u8{ 0, 0, 0, 0 };
            const number = (cell[0] & 0xf0) | (cell[2] >> 4);
            const period = @as(u32, cell[0] & 0x0f) << 8 | cell[1];
            channel.effect = cell[2] & 0x0f;
            channel.param = cell[3];
            const x = channel.param >> 4;
            const y = channel.param & 0x0f;
            if (number != 0 and number <= sample_count) {
                channel.sample = number;
                channel.volume = self.song.samples[number - 1].volume;
            }
            if (channel.effect == 0x9 and channel.param != 0) channel.offset = channel.param;
            if (period != 0) {
                const finetune = if (channel.sample != 0) self.song.samples[channel.sample - 1].finetune else 0;
                const tuned = finetuned(period, finetune);
                if (channel.effect == 0x3 or channel.effect == 0x5) {
                    channel.target = tuned;
                } else if (channel.effect == 0xe and x == 0xd and y > 0) {
                    channel.delayed = tuned;
                } else {
                    self.trigger(channel, tuned);
                }
            }
            switch (channel.effect) {
                0x3 => if (channel.param != 0) {
                    channel.porta_speed = channel.param;
                },
                0x4 => {
                    if (x != 0) channel.vibrato_speed = x;
                    if (y != 0) channel.vibrato_depth = y;
                },
                0x7 => {
                    if (x != 0) channel.tremolo_speed = x;
                    if (y != 0) channel.tremolo_depth = y;
                },
                0xb => {
                    // Row 0, also after a pattern break on a channel before this one.
                    self.jump = channel.param;
                    self.break_row = 0;
                    self.pattern_loop = false;
                },
                0xc => channel.volume = @min(channel.param, 64),
                0xd => {
                    self.break_row = @min(x * 10 + y, 63);
                    if (self.jump == null) self.jump = self.position +% 1;
                    self.pattern_loop = false;
                },
                0xe => switch (x) {
                    0x0 => led.* = y == 0,
                    0x1 => channel.period = @max(channel.period -| y, min_period),
                    0x2 => channel.period = @min(channel.period + y, max_period),
                    0x6 => if (y == 0) {
                        channel.loop_row = self.row;
                    } else {
                        if (channel.loop_count == 0) channel.loop_count = y else channel.loop_count -= 1;
                        if (channel.loop_count > 0) {
                            self.break_row = channel.loop_row;
                            self.jump = self.position;
                            self.pattern_loop = true;
                        }
                    },
                    // A row without a note starts the sound again on its first tick too.
                    0x9 => if (y != 0 and period == 0 and channel.note_period != 0) self.trigger(channel, channel.note_period),
                    0xa => channel.volume = @min(channel.volume + y, 64),
                    0xb => channel.volume = @max(channel.volume - y, 0),
                    0xc => if (y == 0) {
                        channel.volume = 0;
                    },
                    0xe => if (self.pattern_delay == 0 and !self.repeating) {
                        self.pattern_delay = y;
                    },
                    else => {},
                },
                0xf => if (channel.param != 0) {
                    if (channel.param < 32) self.speed = channel.param else self.tempo = channel.param;
                },
                else => {},
            }
            channel.out_period = channel.period;
            channel.out_volume = channel.volume;
        }
    }

    /// Starts the channel's sample at `period`, from EFFECT 9's offset when the row has it.
    fn trigger(self: *Mod, channel: *Channel, period: u16) void {
        channel.note_period = period;
        channel.period = period;
        // A note started on a later tick (EDx, E9x) sounds at its period on that tick.
        channel.out_period = period;
        channel.vibrato_position = 0;
        channel.tremolo_position = 0;
        if (channel.sample == 0) return;
        const info = self.song.samples[channel.sample - 1];
        const loops = info.loop_length > 0;
        const length = if (loops) info.loop_start + info.loop_length else info.length;
        channel.player.start(.{
            .start = info.start,
            .length = length,
            .rate = 0,
            .loop_start = if (loops) info.loop_start else 0,
            .loop_end = if (loops) length else 0,
        }, 0);
        if (channel.effect == 0x9) {
            const offset = @as(u32, channel.offset) * 256;
            // Past the end, a sample with a loop goes on with its loop.
            if (offset < length) {
                channel.player.position = @floatFromInt(offset);
            } else if (loops) {
                channel.player.position = @floatFromInt(info.loop_start);
            } else {
                channel.player.active = false;
            }
        }
    }

    fn volumeSlide(channel: *Channel) void {
        const x = channel.param >> 4;
        const y = channel.param & 0x0f;
        channel.volume = if (x != 0) @min(channel.volume + x, 64) else @max(channel.volume - y, 0);
    }

    fn tonePortamento(channel: *Channel) void {
        if (channel.target == 0 or channel.period == 0) return;
        if (channel.period < channel.target) {
            channel.period = @min(channel.period + channel.porta_speed, channel.target);
        } else {
            channel.period = @max(channel.period -| channel.porta_speed, channel.target);
        }
        // Reached: a later 300 does not slide back to it after another note.
        if (channel.period == channel.target) channel.target = 0;
    }

    fn vibrato(channel: *Channel) void {
        const delta = @divTrunc(waveValue(channel.vibrato_position, channel.vibrato_depth), 128);
        channel.out_period = @intCast(std.math.clamp(@as(i32, channel.period) + delta, min_period, 2 * max_period));
        channel.vibrato_position = (channel.vibrato_position + channel.vibrato_speed) & 63;
    }

    /// The effects that work on the ticks after the first of a row.
    fn tickEffect(self: *Mod, channel: *Channel) void {
        const x = channel.param >> 4;
        const y = channel.param & 0x0f;
        channel.out_period = channel.period;
        channel.out_volume = channel.volume;
        switch (channel.effect) {
            0x0 => if (channel.param != 0) {
                const semitones: u8 = switch (self.tick % 3) {
                    0 => 0,
                    1 => x,
                    else => y,
                };
                const factor = std.math.pow(f32, 2.0, -@as(f32, @floatFromInt(semitones)) / 12.0);
                channel.out_period = @intFromFloat(@max(@round(@as(f32, @floatFromInt(channel.period)) * factor), 1));
            },
            0x1 => {
                channel.period = @max(channel.period -| channel.param, min_period);
                channel.out_period = channel.period;
            },
            0x2 => {
                channel.period = @min(channel.period + channel.param, max_period);
                channel.out_period = channel.period;
            },
            0x3 => {
                tonePortamento(channel);
                channel.out_period = channel.period;
            },
            0x4 => vibrato(channel),
            0x5 => {
                tonePortamento(channel);
                volumeSlide(channel);
                channel.out_period = channel.period;
            },
            0x6 => {
                vibrato(channel);
                volumeSlide(channel);
            },
            0x7 => {
                channel.out_volume = std.math.clamp(channel.volume + @divTrunc(waveValue(channel.tremolo_position, channel.tremolo_depth), 64), 0, 64);
                channel.tremolo_position = (channel.tremolo_position + channel.tremolo_speed) & 63;
            },
            0xa => volumeSlide(channel),
            0xe => switch (x) {
                0x9 => if (y != 0 and self.tick % y == 0) self.trigger(channel, channel.note_period),
                0xc => if (self.tick == y) {
                    channel.volume = 0;
                },
                0xd => if (self.tick == y and channel.delayed != 0) {
                    self.trigger(channel, channel.delayed);
                    channel.delayed = 0;
                },
                else => {},
            },
            else => {},
        }
        if (channel.effect != 0x7) channel.out_volume = channel.volume;
    }

    /// Sets the channel's rate from its period this tick: Paula plays clock / period
    /// samples a second.
    fn sound(self: *Mod, channel: *Channel) void {
        if (channel.out_period == 0) return;
        const frequency = @as(f64, @floatFromInt(amiga.clock)) / @as(f64, @floatFromInt(channel.out_period));
        channel.player.step = frequency / @as(f64, @floatFromInt(self.sample_rate));
    }
};
