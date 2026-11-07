const std = @import("std");
const psg_module = @import("../core/sound_psg.zig");
const mml = @import("../core/sound_mml.zig");
const engine_module = @import("../core/sound_engine.zig");
const wav = @import("../core/sound_wav.zig");

const Psg = psg_module.Psg;
const Engine = engine_module.Engine;

const rate = 48_000;

fn msxPsg() Psg {
    return Psg.init(.ay8910, psg_module.msx_clock, rate);
}

/// Counts the rises of one channel's square wave (at most 1/3 of the PSG's output) over
/// `samples` samples.
fn countRises(psg: *Psg, samples: usize) usize {
    var rises: usize = 0;
    var high = false;
    for (0..samples) |_| {
        const now = psg.sample() > 1.0 / 6.0;
        if (now and !high) rises += 1;
        high = now;
    }
    return rises;
}

test "a PSG tone sounds at clock / (16 × period): O4's A on the MSX is 440 Hz" {
    var psg = msxPsg();
    psg.write(0, 254);
    psg.write(1, 0);
    psg.write(7, 0b1111_1110); // tone A only
    psg.write(8, 15);
    const rises = countRises(&psg, rate); // 1 second
    // 1789773 / (16 × 254) = 440.4 Hz
    try std.testing.expect(rises >= 439 and rises <= 441);

    // The 12-bit period uses R1's low 4 bits; 0 is taken as 1.
    psg.write(0, 0);
    psg.write(1, 0xf1);
    try std.testing.expectEqual(@as(u8, 1), psg.read(1));
    const low = countRises(&psg, rate);
    // 1789773 / (16 × 256) = 437 Hz
    try std.testing.expect(low >= 436 and low <= 438);
}

test "the PSG's noise is a 17-bit LFSR that repeats after 131071 shifts" {
    var psg = msxPsg();
    psg.write(6, 1); // the noise shifts every second step
    var shifts: u32 = 0;
    const start = psg.lfsr;
    while (true) {
        psg.step();
        psg.step();
        shifts += 1;
        if (psg.lfsr == start) break;
        try std.testing.expect(shifts <= 131071);
    }
    try std.testing.expectEqual(@as(u32, 131071), shifts);
}

/// The envelope's levels, one per envelope step (period 1), for `count` steps.
fn envelopeLevels(model: psg_module.Model, shape: u8, count: usize, out: []u8) void {
    var psg = Psg.init(model, psg_module.msx_clock, rate);
    psg.write(11, 1);
    psg.write(12, 0);
    psg.write(13, shape);
    for (0..count) |i| {
        out[i] = psg.envelopeLevel();
        psg.step();
    }
}

test "the 16 envelope shapes of R13" {
    var levels: [96]u8 = undefined;
    const down = [_]u8{ 31, 30, 29, 28, 27, 26, 25, 24, 23, 22, 21, 20, 19, 18, 17, 16, 15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0 };
    var up: [32]u8 = undefined;
    for (&up, 0..) |*l, i| l.* = @intCast(i);
    const Expect = struct { shapes: []const u8, parts: [3][]const u8 };
    const zero: [32]u8 = @splat(0);
    const top: [32]u8 = @splat(31);
    const cases = [_]Expect{
        .{ .shapes = &.{ 0, 1, 2, 3, 9 }, .parts = .{ &down, &zero, &zero } },
        .{ .shapes = &.{ 4, 5, 6, 7, 15 }, .parts = .{ &up, &zero, &zero } },
        .{ .shapes = &.{8}, .parts = .{ &down, &down, &down } },
        .{ .shapes = &.{10}, .parts = .{ &down, &up, &down } },
        .{ .shapes = &.{11}, .parts = .{ &down, &top, &top } },
        .{ .shapes = &.{12}, .parts = .{ &up, &up, &up } },
        .{ .shapes = &.{13}, .parts = .{ &up, &top, &top } },
        .{ .shapes = &.{14}, .parts = .{ &up, &down, &up } },
    };
    for (cases) |case| for (case.shapes) |shape| {
        envelopeLevels(.ym2149, shape, 96, &levels);
        for (case.parts, 0..) |part, p| try std.testing.expectEqualSlices(u8, part, levels[p * 32 ..][0..32]);
    };
}

test "a whole envelope lasts 256 × period clocks on the AY and the YM" {
    var psg = Psg.init(.ay8910, psg_module.msx_clock, rate);
    psg.write(11, 10);
    psg.write(13, 0); // one fall
    var steps: u32 = 0;
    while (!psg.env_holding) : (steps += 1) psg.step();
    // 32 envelope steps of 10 PSG steps, each 8 clocks.
    try std.testing.expectEqual(@as(u32, 32 * 10), steps);
}

test "the PSG's mixer and volumes" {
    var psg = msxPsg();
    // Tone and noise off: the channel's level is its volume, constantly.
    psg.write(7, 0xff);
    psg.write(8, 15);
    try std.testing.expectEqual(@as(f32, 1.0 / 3.0), psg.level());
    psg.write(8, 0);
    try std.testing.expectEqual(@as(f32, 0), psg.level());
    // The AY's levels rise from 0 to 1.
    var previous: f32 = -1;
    for (0..16) |v| {
        psg.write(8, @intCast(v));
        const now = psg.channelLevel(0);
        try std.testing.expect(now > previous);
        previous = now;
    }
    try std.testing.expectEqual(@as(f32, 1), previous);
    // The YM's fixed volumes are 3 dB apart.
    var ym = Psg.init(.ym2149, psg_module.atari_st_clock, rate);
    ym.write(7, 0xff);
    ym.write(8, 15);
    const full = ym.channelLevel(0);
    ym.write(8, 14);
    try std.testing.expectApproxEqAbs(@as(f32, 0.7079), ym.channelLevel(0) / full, 0.001);
    // The envelope bit uses the envelope's level instead.
    ym.write(8, 16);
    ym.write(13, 13);
    try std.testing.expectEqual(@as(f32, 0), ym.channelLevel(0));
}

/// All events of one voice's MML.
fn parseAll(voice: *mml.Voice, text: []const u8, out: []mml.Event) !usize {
    var parser = mml.Parser.init(voice, text);
    var count: usize = 0;
    while (try parser.next()) |event| : (count += 1) out[count] = event;
    return count;
}

test "MML notes: pitches, lengths, dots, and the defaults" {
    var events: [16]mml.Event = undefined;
    var voice: mml.Voice = .{};
    try std.testing.expectEqual(@as(usize, 4), try parseAll(&voice, "cde A", &events));
    // O4: octave 1's dividers halved three times; L4 at T120 is 25 ticks (0.5 s).
    try std.testing.expectEqual(@as(u16, 3421 >> 3), events[0].period);
    try std.testing.expectEqual(@as(u16, 3047 >> 3), events[1].period);
    try std.testing.expectEqual(@as(u16, 2715 >> 3), events[2].period);
    try std.testing.expectEqual(@as(u16, 254), events[3].period);
    for (events[0..4]) |e| {
        try std.testing.expectEqual(@as(u16, 25), e.ticks);
        try std.testing.expectEqual(@as(u8, 8), e.amplitude);
    }
    // Sharps, flats, and the ROM's B+ (C) and C- (B) of the same octave.
    voice = .{};
    _ = try parseAll(&voice, "C+D#E-B+C-", &events);
    try std.testing.expectEqual(@as(u16, 3228 >> 3), events[0].period);
    try std.testing.expectEqual(@as(u16, 2876 >> 3), events[1].period);
    try std.testing.expectEqual(@as(u16, 2876 >> 3), events[2].period);
    try std.testing.expectEqual(@as(u16, 3421 >> 3), events[3].period);
    try std.testing.expectEqual(@as(u16, 1812 >> 3), events[4].period);
    // Lengths: 12000 / (L × T) ticks, cut to whole ticks, at least 5; dots add half.
    voice = .{};
    _ = try parseAll(&voice, "L8C C2 C4. C.. T255L64C", &events);
    try std.testing.expectEqual(@as(u16, 12), events[0].ticks);
    try std.testing.expectEqual(@as(u16, 50), events[1].ticks);
    try std.testing.expectEqual(@as(u16, 37), events[2].ticks);
    try std.testing.expectEqual(@as(u16, 28), events[3].ticks); // 12.5 × 2.25
    try std.testing.expectEqual(@as(u16, 5), events[4].ticks);
    // A command without its number takes the default: L is 4 again, R is R4.
    voice = .{};
    _ = try parseAll(&voice, "L16 L C R O2 O C", &events);
    try std.testing.expectEqual(@as(u16, 25), events[0].ticks);
    try std.testing.expectEqual(@as(u16, 0), events[1].period);
    try std.testing.expectEqual(@as(u8, 0), events[1].amplitude);
    try std.testing.expectEqual(@as(u16, 25), events[1].ticks);
    try std.testing.expectEqual(@as(u16, 3421 >> 3), events[2].period);
    // N: the octave is n / 12 + 1 (N36 is O4's C), N0 a rest.
    voice = .{};
    _ = try parseAll(&voice, "N36N0N1N96", &events);
    try std.testing.expectEqual(@as(u16, 3421 >> 3), events[0].period);
    try std.testing.expectEqual(@as(u16, 0), events[1].period);
    try std.testing.expectEqual(@as(u16, 3228), events[2].period);
    try std.testing.expectEqual(@as(u16, 3421 >> 8), events[3].period);
    // < and >, V, S, M.
    voice = .{};
    _ = try parseAll(&voice, "O4>C<<C V15C S8M1000C V3C", &events);
    try std.testing.expectEqual(@as(u16, 3421 >> 4), events[0].period);
    try std.testing.expectEqual(@as(u16, 3421 >> 2), events[1].period);
    try std.testing.expectEqual(@as(u8, 15), events[2].amplitude);
    try std.testing.expectEqual(@as(u8, 16), events[3].amplitude);
    try std.testing.expectEqual(@as(u8, 8), events[3].shape);
    try std.testing.expectEqual(@as(u16, 1000), events[3].envelope_period);
    try std.testing.expectEqual(@as(u8, 3), events[4].amplitude);
    // The voice keeps what the commands set.
    try std.testing.expectEqual(@as(u8, 3), voice.volume);
    try std.testing.expectEqual(@as(u8, 3), voice.octave);
}

test "MML errors" {
    const bad = [_][]const u8{ "O9", "O0", "L65", "C65", "T31", "T256", "V16", "N97", "N", "S16", "M0", "M65536", "Z", "C=X;", "O1<", "O8>", "X$;" };
    for (bad) |text| try std.testing.expectError(error.InvalidMml, mml.check(.{}, text));
    // Lower-case letters and spaces are taken.
    try mml.check(.{}, "o7 > c d+ l8 e");
}

/// The wait of putPlay in the tests: the audio thread plays a little.
const Player = struct {
    engine: *Engine,
    waits: usize = 0,
    limit: usize = 1_000_000,
    buffer: [960]i16 = undefined,

    fn wait(self: *Player) bool {
        self.waits += 1;
        if (self.waits > self.limit) return false;
        self.engine.render(&self.buffer);
        return true;
    }

    /// Plays `ms` milliseconds.
    fn play(self: *Player, ms: usize) void {
        for (0..ms / 10) |_| self.engine.render(&self.buffer);
    }
};

test "PLAY's voices start together, and PLAY(n) tells which still play" {
    var engine = Engine.init(.ay8910, psg_module.msx_clock, rate);
    var voices = [_]mml.Voice{ .{}, .{}, .{} };
    var player: Player = .{ .engine = &engine };
    try engine_module.putPlay(&engine, &voices, &.{ "C", "C2" }, &player, Player.wait);
    try engine_module.putPlay(&engine, &voices, &.{"D"}, &player, Player.wait);
    try std.testing.expect(engine.isPlaying(0) and engine.isPlaying(1) and engine.isPlaying(2) and engine.isPlaying(3));
    try std.testing.expectEqual(@as(usize, 0), player.waits);

    // A's C (0.5 s) ends; B's C2 (1 s) goes on; the next PLAY waits for it.
    player.play(800);
    try std.testing.expectEqual(@as(u8, 3421 >> 3 & 0xff), engine.psg.read(0));
    try std.testing.expectEqual(@as(u8, 0), engine.psg.read(8));
    try std.testing.expectEqual(@as(u8, 8), engine.psg.read(9));
    // At 1 s the second PLAY starts A's D.
    player.play(300);
    try std.testing.expectEqual(@as(u8, 3047 >> 3 & 0xff), engine.psg.read(0));
    try std.testing.expectEqual(@as(u8, 8), engine.psg.read(8));
    try std.testing.expectEqual(@as(u8, 0), engine.psg.read(9));
    try std.testing.expect(engine.isPlaying(1) and !engine.isPlaying(2));
    player.play(600);
    try std.testing.expect(!engine.isPlaying(0));
    try std.testing.expectEqual(@as(u8, 0), engine.psg.read(8));
}

test "a PLAY longer than the queue plays while it is put" {
    var engine = Engine.init(.ay8910, psg_module.msx_clock, rate);
    var voices = [_]mml.Voice{ .{}, .{}, .{} };
    var player: Player = .{ .engine = &engine };
    const text = comptime blk: {
        var t: []const u8 = "T255L64";
        for (0..20) |_| t = t ++ "CDEFGAB";
        break :blk t;
    };
    try engine_module.putPlay(&engine, &voices, &.{ text, "", text }, &player, Player.wait);
    try std.testing.expect(player.waits > 0);
    try std.testing.expect(engine.isPlaying(1));
    // 140 notes of 5 ticks: 14 s, part of it played while putting.
    player.play(15_000);
    try std.testing.expect(!engine.isPlaying(0));

    // A stop while waiting leaves notes; a reset drops them.
    player = .{ .engine = &engine, .limit = 3 };
    try std.testing.expectError(error.Interrupted, engine_module.putPlay(&engine, &voices, &.{text}, &player, Player.wait));
    try std.testing.expect(engine.isPlaying(1));
    try std.testing.expect(engine.putCommand(engine.resetCommand(false)));
    player.play(20);
    try std.testing.expect(!engine.isPlaying(0));
    try std.testing.expectEqual(@as(u8, 0xb8), engine.psg.read(7));
}

test "an invalid PLAY puts nothing" {
    var engine = Engine.init(.ay8910, psg_module.msx_clock, rate);
    var voices = [_]mml.Voice{ .{}, .{}, .{} };
    var player: Player = .{ .engine = &engine };
    try std.testing.expectError(error.InvalidMml, engine_module.putPlay(&engine, &voices, &.{ "CDE", "O9C" }, &player, Player.wait));
    try std.testing.expect(!engine.isPlaying(0));
    try std.testing.expectEqual(@as(u32, 0), engine.plays_put.raw);
    try std.testing.expectEqual(@as(u8, 4), voices[0].octave);
}

test "BEEP drops the notes, sounds 1316 Hz for 40 ms, and sets the PSG as at the start" {
    var engine = Engine.init(.ay8910, psg_module.msx_clock, rate);
    var voices = [_]mml.Voice{ .{}, .{}, .{} };
    var player: Player = .{ .engine = &engine };
    try engine_module.putPlay(&engine, &voices, &.{"CDEFG"}, &player, Player.wait);
    player.play(100);
    try std.testing.expect(engine.putCommand(engine.resetCommand(true)));
    var buffer: [2 * 480]i16 = undefined; // 10 ms
    engine.render(&buffer);
    try std.testing.expect(!engine.isPlaying(0));
    try std.testing.expectEqual(@as(u8, 85), engine.psg.read(0));
    try std.testing.expectEqual(@as(u8, 7), engine.psg.read(8));
    player.play(40);
    try std.testing.expectEqualSlices(u8, &engine_module.msxInitialRegisters(), &engine.psg.regs);
}

test "SOUND writes a register; the output is 16-bit stereo without the constant level" {
    var engine = Engine.init(.ay8910, psg_module.msx_clock, rate);
    try std.testing.expect(engine.putCommand(.{ .write = .{ .reg = 8, .value = 15 } }));
    var buffer: [2 * 4800]i16 = undefined;
    engine.render(&buffer);
    try std.testing.expectEqual(@as(u8, 15), engine.psg.read(8));
    // Left and right are the same; the tone swings around 0.
    var low: i16 = 0;
    var high: i16 = 0;
    var i: usize = 0;
    while (i < buffer.len) : (i += 2) {
        try std.testing.expectEqual(buffer[i], buffer[i + 1]);
        low = @min(low, buffer[i]);
        high = @max(high, buffer[i]);
    }
    // One channel at full volume swings 1/3 of the level, ± about 3300.
    try std.testing.expect(low < -2500 and high > 2500);
    // Silence settles at 0.
    try std.testing.expect(engine.putCommand(.{ .write = .{ .reg = 8, .value = 0 } }));
    for (0..20) |_| engine.render(&buffer);
    try std.testing.expect(@abs(buffer[buffer.len - 2]) < 2);
}

test "the same notes always make the same samples" {
    var a = Engine.init(.ay8910, psg_module.msx_clock, rate);
    var b = Engine.init(.ay8910, psg_module.msx_clock, rate);
    var voices_a = [_]mml.Voice{ .{}, .{}, .{} };
    var voices_b = [_]mml.Voice{ .{}, .{}, .{} };
    var player_a: Player = .{ .engine = &a };
    var player_b: Player = .{ .engine = &b };
    try engine_module.putPlay(&a, &voices_a, &.{ "S8M300CDE", "O2G" }, &player_a, Player.wait);
    try engine_module.putPlay(&b, &voices_b, &.{ "S8M300CDE", "O2G" }, &player_b, Player.wait);
    var out_a: [2000]i16 = undefined;
    var out_b: [2000]i16 = undefined;
    for (0..50) |_| {
        a.render(&out_a);
        b.render(&out_b);
        try std.testing.expectEqualSlices(i16, &out_a, &out_b);
    }
}

test "the WAV header of 16-bit PCM" {
    const h = wav.header(48_000, 2, 1000);
    try std.testing.expectEqualSlices(u8, "RIFF", h[0..4]);
    try std.testing.expectEqual(@as(u32, 36 + 4000), std.mem.readInt(u32, h[4..8], .little));
    try std.testing.expectEqualSlices(u8, "WAVEfmt ", h[8..16]);
    try std.testing.expectEqual(@as(u16, 1), std.mem.readInt(u16, h[20..22], .little));
    try std.testing.expectEqual(@as(u16, 2), std.mem.readInt(u16, h[22..24], .little));
    try std.testing.expectEqual(@as(u32, 48_000), std.mem.readInt(u32, h[24..28], .little));
    try std.testing.expectEqual(@as(u32, 192_000), std.mem.readInt(u32, h[28..32], .little));
    try std.testing.expectEqual(@as(u16, 4), std.mem.readInt(u16, h[32..34], .little));
    try std.testing.expectEqual(@as(u16, 16), std.mem.readInt(u16, h[34..36], .little));
    try std.testing.expectEqual(@as(u32, 4000), std.mem.readInt(u32, h[40..44], .little));
    var bytes: [4]u8 = undefined;
    wav.putSamples(&bytes, &.{ -2, 0x1234 });
    try std.testing.expectEqualSlices(u8, &.{ 0xfe, 0xff, 0x34, 0x12 }, &bytes);
}
