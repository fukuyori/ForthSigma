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

// ---- S3a: the common parts, the NES, and the Atari ST ----

const parts = @import("../core/sound_parts.zig");
const nes_module = @import("../core/sound_nes.zig");

/// Rises across the middle of the lowest and highest sample, in `samples`.
fn risesOf(samples: []const f32) usize {
    var low = samples[0];
    var high = samples[0];
    for (samples) |s| {
        low = @min(low, s);
        high = @max(high, s);
    }
    const middle = (low + high) / 2;
    var rises: usize = 0;
    var above = samples[0] > middle;
    for (samples[1..]) |s| {
        const now = s > middle;
        if (now and !above) rises += 1;
        above = now;
    }
    return rises;
}

/// The fraction of `samples` above the middle of the lowest and highest.
fn highFraction(samples: []const f32) f32 {
    var low = samples[0];
    var high = samples[0];
    for (samples) |s| {
        low = @min(low, s);
        high = @max(high, s);
    }
    var count: usize = 0;
    for (samples) |s| {
        if (s > (low + high) / 2) count += 1;
    }
    return @as(f32, @floatFromInt(count)) / @as(f32, @floatFromInt(samples.len));
}

/// One second of the NES's output.
fn nesSecond(nes: *nes_module.Nes) ![]f32 {
    const samples = try std.testing.allocator.alloc(f32, rate);
    for (samples) |*s| s.* = nes.sample();
    return samples;
}

test "MML's @ chooses an instrument, and each note has its number for the other chips" {
    var voice: mml.Voice = .{};
    var parser = mml.Parser.init(&voice, "@5 C O3 A @ N57 R");
    const c = (try parser.next()).?;
    try std.testing.expectEqual(@as(u8, 5), c.instrument);
    try std.testing.expectEqual(@as(u8, 48), c.note);
    const a = (try parser.next()).?;
    try std.testing.expectEqual(@as(u8, 45), a.note);
    // @ without a number is @0; N57 is O5's A (octave 57 / 12 + 1).
    const n = (try parser.next()).?;
    try std.testing.expectEqual(@as(u8, 0), n.instrument);
    try std.testing.expectEqual(@as(u8, 69), n.note);
    try std.testing.expectEqual(@as(u16, 0), (try parser.next()).?.period);
    try std.testing.expectError(error.InvalidMml, mml.check(.{}, "@64C"));
}

test "a note's pitch in equal temperament, and on the chips' period registers" {
    try std.testing.expectApproxEqAbs(@as(f64, 440), parts.noteFrequency(57), 1e-9);
    try std.testing.expectApproxEqAbs(@as(f64, 220), parts.noteFrequency(45), 1e-9);
    try std.testing.expectApproxEqAbs(@as(f64, 261.6256), parts.noteFrequency(48), 1e-3);
    // The Atari ST: 2 MHz / (16 × 284) = 440.1 Hz.
    try std.testing.expectEqual(@as(u32, 284), parts.chipPeriod(57, psg_module.atari_st_clock, 16, 0, 4095));
    // The NES's pulse: 1789773 / (16 × (253 + 1)) = 440.4 Hz; and the limits.
    try std.testing.expectEqual(@as(u32, 253), parts.chipPeriod(57, nes_module.cpu_clock, 16, 1, 2047));
    try std.testing.expectEqual(@as(u32, 2047), parts.chipPeriod(12, nes_module.cpu_clock, 16, 1, 2047));
}

test "the ADSR envelope: its attack, its sustain level, and its release" {
    var adsr: parts.Adsr = .{};
    adsr.start(.{ .attack = 0, .decay = 0, .sustain = 6, .release = 0 }, rate);
    // Attack 0 is 2 ms (96 samples) to the top.
    var top: f32 = 0;
    for (0..100) |_| top = @max(top, adsr.next());
    try std.testing.expectEqual(@as(f32, 1), top);
    // Decay 0 is 6 ms to the sustain level, 6 / 15.
    for (0..rate / 10) |_| _ = adsr.next();
    try std.testing.expectApproxEqAbs(@as(f32, 0.4), adsr.next(), 1e-3);
    adsr.stop();
    for (0..rate / 10) |_| _ = adsr.next();
    try std.testing.expectEqual(@as(f32, 0), adsr.next());

    // A longer attack (8: 100 ms) is half way after 50 ms.
    var slow: parts.Adsr = .{};
    slow.start(.{ .attack = 8 }, rate);
    var level: f32 = 0;
    for (0..rate / 20) |_| level = slow.next();
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), level, 0.01);
}

test "the NES pulse sounds on its timer with the duty rounded to the four of the chip" {
    var nes = nes_module.Nes.init(rate);
    nes.triangle_level = 0;
    nes.noteOn(0, 57, 15, .{});
    const square = try nesSecond(&nes);
    defer std.testing.allocator.free(square);
    const rises = risesOf(square);
    try std.testing.expect(rises >= 439 and rises <= 441);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), highFraction(square), 0.01);

    nes.noteOn(1, 57, 15, .{ .wave = .pulse, .duty = 30 });
    nes.noteOff(0);
    for (0..rate / 10) |_| _ = nes.sample();
    const narrow = try nesSecond(&nes);
    defer std.testing.allocator.free(narrow);
    try std.testing.expectApproxEqAbs(@as(f32, 0.25), highFraction(narrow), 0.01);
}

test "the NES triangle sounds an octave lower than a pulse on the same timer, and keeps its step when it stops" {
    var nes = nes_module.Nes.init(rate);
    nes.noteOn(2, 45, 15, .{});
    const wave = try nesSecond(&nes);
    defer std.testing.allocator.free(wave);
    const rises = risesOf(wave);
    try std.testing.expect(rises >= 219 and rises <= 221);
    nes.noteOff(2);
    const held = nes.sample();
    for (0..1000) |_| try std.testing.expectEqual(held, nes.sample());
}

test "the NES noise is shorter for higher notes and goes silent with its envelope" {
    var nes = nes_module.Nes.init(rate);
    nes.triangle_level = 0;
    // O3's C is the longest period, O4's D# the shortest; the notes beyond take the ends.
    try std.testing.expectEqual(@as(usize, 15), nes_module.noiseIndex(36));
    try std.testing.expectEqual(@as(usize, 15), nes_module.noiseIndex(12));
    try std.testing.expectEqual(@as(usize, 14), nes_module.noiseIndex(37));
    try std.testing.expectEqual(@as(usize, 0), nes_module.noiseIndex(51));
    try std.testing.expectEqual(@as(usize, 0), nes_module.noiseIndex(84));
    var previous: usize = 16;
    for (36..52) |note| {
        try std.testing.expect(nes_module.noiseIndex(@intCast(note)) < previous);
        previous = nes_module.noiseIndex(@intCast(note));
    }
    nes.noteOn(3, 51, 15, .{});
    const high_period = nes.noise_period;
    nes.noteOn(3, 40, 15, .{});
    try std.testing.expect(nes.noise_period > high_period);
    var low: f32 = 1;
    var high: f32 = 0;
    for (0..rate / 10) |_| {
        const s = nes.sample();
        low = @min(low, s);
        high = @max(high, s);
    }
    try std.testing.expect(high - low > 0.1);
    nes.noteOff(3);
    for (0..rate / 10) |_| _ = nes.sample();
    try std.testing.expectEqual(@as(f32, 0), nes.sample());
}

test "the engine plays four NES voices together, with their instruments" {
    var engine = Engine.init(.ay8910, psg_module.msx_clock, rate);
    var voices: [engine_module.max_voices]mml.Voice = @splat(.{});
    var player: Player = .{ .engine = &engine };
    try std.testing.expect(engine.putCommand(engine.chipCommand(.nes)));
    try std.testing.expect(engine.putCommand(.{ .instrument = .{ .index = 3, .value = .{ .wave = .pulse, .duty = 12 } } }));
    player.play(10);
    try std.testing.expectEqual(engine_module.Chip.nes, engine.chips.only().?);
    try std.testing.expectEqual(@as(u8, 12), engine.instruments[3].duty);
    try engine_module.putPlay(&engine, &voices, &.{ "@3 C", "E", "G", "C" }, &player, Player.wait);
    player.play(30);
    for (1..5) |n| try std.testing.expect(engine.isPlaying(n));
    try std.testing.expect(!engine.isPlaying(5));
    try std.testing.expectEqual(@as(f32, 0.125), engine.nes.voices[0].duty);
    try std.testing.expectEqual(@as(f32, 0.5), engine.nes.voices[1].duty);
    player.play(1000);
    try std.testing.expect(!engine.isPlaying(0));
}

test "ST-SOUND plays the same notes on a YM2149 at 2 MHz" {
    var engine = Engine.init(.ay8910, psg_module.msx_clock, rate);
    var voices: [engine_module.max_voices]mml.Voice = @splat(.{});
    var player: Player = .{ .engine = &engine };
    try std.testing.expect(engine.putCommand(engine.chipCommand(.atari_st)));
    player.play(10);
    try std.testing.expectEqual(psg_module.Model.ym2149, engine.psg.model);
    try std.testing.expectEqual(psg_module.atari_st_clock, engine.psg.clock);
    try engine_module.putPlay(&engine, &voices, &.{"A"}, &player, Player.wait);
    player.play(30);
    try std.testing.expectEqual(@as(u8, 284 & 0xff), engine.psg.read(0));
    try std.testing.expectEqual(@as(u8, 284 >> 8), engine.psg.read(1));
    try std.testing.expectEqual(@as(u8, 8), engine.psg.read(8));
    // Back to the MSX: an AY at its clock, with the period of the ROM.
    try std.testing.expect(engine.putCommand(engine.chipCommand(.msx)));
    player.play(10);
    try engine_module.putPlay(&engine, &voices, &.{"A"}, &player, Player.wait);
    player.play(30);
    try std.testing.expectEqual(psg_module.Model.ay8910, engine.psg.model);
    try std.testing.expectEqual(@as(u8, 254), engine.psg.read(0));
}

// ---- S3b: the C64 ----

const c64_module = @import("../core/sound_c64.zig");

/// One second of the C64's output.
fn c64Second(c64: *c64_module.C64) ![]f32 {
    const samples = try std.testing.allocator.alloc(f32, rate);
    for (samples) |*s| s.* = c64.sample();
    return samples;
}

/// The mean square of the samples.
fn power(samples: []const f32) f32 {
    var sum: f32 = 0;
    for (samples) |s| sum += s * s;
    return sum / @as(f32, @floatFromInt(samples.len));
}

test "the SID's registers for a note and a pulse width, and the filter's cutoff" {
    // 440 × 2^24 / 985248 = 7492.5, rounded to 7493 (440.03 Hz).
    try std.testing.expectEqual(@as(u16, 7493), c64_module.frequencyRegister(57));
    try std.testing.expectEqual(@as(u16, 65535), c64_module.frequencyRegister(107));
    try std.testing.expectEqual(@as(u16, 1024), c64_module.pulseWidthRegister(25));
    try std.testing.expectEqual(@as(u16, 4095), c64_module.pulseWidthRegister(100));
    try std.testing.expectEqual(@as(f32, 30), c64_module.cutoffFrequency(0));
    try std.testing.expectApproxEqAbs(@as(f32, 11902.6), c64_module.cutoffFrequency(2047), 0.1);
}

test "the C64's waves sound at the note's pitch, the pulse with its width" {
    for ([_]parts.Wave{ .triangle, .saw, .square }) |wave| {
        var c64 = c64_module.C64.init(rate);
        c64.noteOn(0, 57, 15, .{ .wave = wave });
        const samples = try c64Second(&c64);
        defer std.testing.allocator.free(samples);
        const rises = risesOf(samples);
        try std.testing.expect(rises >= 439 and rises <= 441);
    }
    var c64 = c64_module.C64.init(rate);
    c64.noteOn(0, 57, 15, .{ .wave = .pulse, .duty = 25 });
    const pulse = try c64Second(&c64);
    defer std.testing.allocator.free(pulse);
    try std.testing.expectApproxEqAbs(@as(f32, 0.25), highFraction(pulse), 0.01);

    // The noise moves, and stops with the note's release.
    var noisy = c64_module.C64.init(rate);
    noisy.noteOn(1, 57, 15, .{ .wave = .noise });
    var low: f32 = 1;
    var high: f32 = -1;
    for (0..rate / 10) |_| {
        const s = noisy.sample();
        low = @min(low, s);
        high = @max(high, s);
    }
    try std.testing.expect(high - low > 0.3);
    noisy.noteOff(1);
    for (0..rate / 10) |_| _ = noisy.sample();
    try std.testing.expectEqual(@as(f32, 0), noisy.sample());
}

test "the C64's sync restarts a voice with the voice before, and ring modulation changes its triangle" {
    // Voice 2 (a sawtooth at O5's D, 587 Hz) synced to voice 1 (O3's A, 220 Hz): in each
    // of voice 1's cycles it falls twice by itself and once more at the sync, so 3 × 220
    // times a second instead of 587.
    for ([_]bool{ false, true }) |sync| {
        var c64 = c64_module.C64.init(rate);
        c64.noteOn(0, 45, 0, .{});
        c64.noteOn(1, 62, 15, .{ .wave = .saw, .sync = sync });
        const samples = try c64Second(&c64);
        defer std.testing.allocator.free(samples);
        var falls: usize = 0;
        var falling = false;
        for (samples[1..], 1..) |s, i| {
            // The voices are mixed as a third each: a fall of the sawtooth is 2/3.
            const now = s - samples[i - 1] < -0.15;
            if (now and !falling) falls += 1;
            falling = now;
        }
        const modulator = @as(f32, @floatFromInt(c64_module.frequencyRegister(45))) * c64_module.clock / 16_777_216.0;
        const own = @as(f32, @floatFromInt(c64_module.frequencyRegister(62))) * c64_module.clock / 16_777_216.0;
        const expected = if (sync) 3 * modulator else own;
        try std.testing.expectApproxEqAbs(expected, @as(f32, @floatFromInt(falls)), 3);
    }

    // Ring modulation: the same triangle, other samples.
    var plain = c64_module.C64.init(rate);
    var ringed = c64_module.C64.init(rate);
    for ([_]*c64_module.C64{ &plain, &ringed }, [_]bool{ false, true }) |c64, ring| {
        c64.noteOn(2, 40, 0, .{});
        c64.noteOn(0, 57, 15, .{ .wave = .triangle, .ring = ring });
    }
    var differ = false;
    for (0..rate / 10) |_| {
        if (@abs(plain.sample() - ringed.sample()) > 0.1) differ = true;
    }
    try std.testing.expect(differ);
}

test "the C64's filter: a low-pass takes the high notes away, a high-pass the low ones" {
    var open = c64_module.C64.init(rate);
    open.noteOn(0, 81, 15, .{ .wave = .saw });
    const bright = try c64Second(&open);
    defer std.testing.allocator.free(bright);
    var closed = c64_module.C64.init(rate);
    closed.noteOn(0, 81, 15, .{ .wave = .saw, .filter = 1, .cutoff = 0 });
    const dark = try c64Second(&closed);
    defer std.testing.allocator.free(dark);
    try std.testing.expect(power(dark) < power(bright) / 100);

    var high_pass = c64_module.C64.init(rate);
    high_pass.noteOn(0, 24, 15, .{ .wave = .triangle, .filter = 3, .cutoff = 2047 });
    const thin = try c64Second(&high_pass);
    defer std.testing.allocator.free(thin);
    var full = c64_module.C64.init(rate);
    full.noteOn(0, 24, 15, .{ .wave = .triangle });
    const whole = try c64Second(&full);
    defer std.testing.allocator.free(whole);
    try std.testing.expect(power(thin) < power(whole) / 100);
}

test "C64-SOUND plays three voices on the SID through the engine" {
    var engine = Engine.init(.ay8910, psg_module.msx_clock, rate);
    var voices: [engine_module.max_voices]mml.Voice = @splat(.{});
    var player: Player = .{ .engine = &engine };
    try std.testing.expect(engine.putCommand(engine.chipCommand(.c64)));
    try std.testing.expect(engine.putCommand(.{ .instrument = .{ .index = 1, .value = .{ .wave = .saw, .filter = 1, .cutoff = 300 } } }));
    player.play(10);
    try std.testing.expectEqual(engine_module.Chip.c64, engine.chips.only().?);
    try engine_module.putPlay(&engine, &voices, &.{ "@1 C", "E", "G" }, &player, Player.wait);
    player.play(30);
    for (1..4) |n| try std.testing.expect(engine.isPlaying(n));
    try std.testing.expectEqual(parts.Wave.saw, engine.c64.voices[0].instrument.wave);
    try std.testing.expectEqual(@as(u8, 1), engine.c64.filter.mode);
    player.play(1000);
    try std.testing.expect(!engine.isPlaying(0));
}

// ---- S3c: the SCC ----

const scc_module = @import("../core/sound_scc.zig");

test "the SCC's period for a note, and the waves the instruments make without SCC-WAVE" {
    // 3579545 / (32 × (253 + 1)) = 440.4 Hz.
    try std.testing.expectEqual(@as(u32, 253), scc_module.periodRegister(57));
    try std.testing.expectEqual(@as(u32, 4095), scc_module.periodRegister(0));
    const square = (parts.Instrument{}).table();
    try std.testing.expectEqual(@as(i8, 127), square[15]);
    try std.testing.expectEqual(@as(i8, -128), square[16]);
    const pulse = (parts.Instrument{ .wave = .pulse, .duty = 25 }).table();
    try std.testing.expectEqual(@as(i8, 127), pulse[7]);
    try std.testing.expectEqual(@as(i8, -128), pulse[8]);
    const triangle = (parts.Instrument{ .wave = .triangle }).table();
    try std.testing.expectEqual(@as(i8, -128), triangle[0]);
    try std.testing.expectEqual(@as(i8, 127), triangle[15]);
    try std.testing.expectEqual(@as(i8, -128), triangle[31]);
    const saw = (parts.Instrument{ .wave = .saw }).table();
    try std.testing.expectEqual(@as(i8, -128), saw[0]);
    try std.testing.expectEqual(@as(i8, 127), saw[31]);
    for (saw[1..], 1..) |s, i| try std.testing.expect(s > saw[i - 1]);
    const own: [32]i8 = @splat(5);
    try std.testing.expectEqual(own, (parts.Instrument{ .wave = .saw, .wavetable = own }).table());
}

test "the SCC plays its instrument's 32 samples as steps at the note's pitch" {
    var scc = scc_module.Scc.init(rate);
    scc.noteOn(0, 57, 15, .{});
    const samples = try std.testing.allocator.alloc(f32, rate);
    defer std.testing.allocator.free(samples);
    for (samples) |*s| s.* = scc.sample();
    const rises = risesOf(samples);
    try std.testing.expect(rises >= 439 and rises <= 441);

    // A wave of its own: half at 64, half at -64 and so on, as the steps say.
    var wave: [32]i8 = undefined;
    for (&wave, 0..) |*s, i| s.* = if (i < 16) 64 else -64;
    var own = scc_module.Scc.init(rate);
    own.noteOn(4, 57, 15, .{ .wave = .saw, .wavetable = wave });
    var top: f32 = 0;
    for (0..rate / 10) |_| top = @max(top, own.sample());
    try std.testing.expectApproxEqAbs(@as(f32, 0.5 / 5.0), top, 1e-6);
    own.noteOff(4);
    for (0..rate / 10) |_| _ = own.sample();
    try std.testing.expectEqual(@as(f32, 0), own.sample());
}

test "SCC-SOUND plays five voices through the engine" {
    var engine = Engine.init(.ay8910, psg_module.msx_clock, rate);
    var voices: [engine_module.max_voices]mml.Voice = @splat(.{});
    var player: Player = .{ .engine = &engine };
    try std.testing.expect(engine.putCommand(engine.chipCommand(.scc)));
    player.play(10);
    try engine_module.putPlay(&engine, &voices, &.{ "C", "E", "G", ">C", "<<C" }, &player, Player.wait);
    player.play(30);
    for (1..6) |n| try std.testing.expect(engine.isPlaying(n));
    player.play(1000);
    try std.testing.expect(!engine.isPlaying(0));
}

// ---- S4a: samples and the Amiga ----

const pcm = @import("../core/sound_pcm.zig");
const amiga_module = @import("../core/sound_amiga.zig");

test "a WAV file's format, and its frames as mono 16-bit samples" {
    // PCM, 2 channels, 22050 Hz, 8 bits.
    const stereo8 = [_]u8{ 1, 0, 2, 0, 0x22, 0x56, 0, 0, 0x44, 0xac, 0, 0, 2, 0, 8, 0 };
    const format = try pcm.parseFormat(&stereo8);
    try std.testing.expectEqual(pcm.Format{ .channels = 2, .rate = 22050, .bits = 8 }, format);
    var out: [3]i16 = undefined;
    // 128 is 0; the two channels' mean; a half frame at the end is left.
    try std.testing.expectEqual(@as(usize, 2), pcm.convertFrames(format, &.{ 128, 128, 255, 1, 0 }, &out));
    try std.testing.expectEqual(@as(i16, 0), out[0]);
    try std.testing.expectEqual(@as(i16, 0), out[1]);
    const mono16: pcm.Format = .{ .channels = 1, .rate = 44100, .bits = 16 };
    try std.testing.expectEqual(@as(usize, 2), pcm.convertFrames(mono16, &.{ 0x00, 0x80, 0xff, 0x7f }, &out));
    try std.testing.expectEqual(@as(i16, -32768), out[0]);
    try std.testing.expectEqual(@as(i16, 32767), out[1]);

    // Not PCM, 3 channels, 24 bits, too short.
    var bad = stereo8;
    bad[0] = 3;
    try std.testing.expectError(error.InvalidWav, pcm.parseFormat(&bad));
    bad = stereo8;
    bad[2] = 3;
    try std.testing.expectError(error.InvalidWav, pcm.parseFormat(&bad));
    bad = stereo8;
    bad[14] = 24;
    try std.testing.expectError(error.InvalidWav, pcm.parseFormat(&bad));
    try std.testing.expectError(error.InvalidWav, pcm.parseFormat(stereo8[0..10]));
}

test "the sample player holds each value, stops at the end, and loops where it is told" {
    const data = [_]i16{ 0, 16384, -16384, 8192 };
    var player: pcm.Player = .{};
    player.start(.{ .start = 0, .length = 4, .rate = 8000 }, 0.5);
    const expected = [_]f32{ 0, 0, 0.5, 0.5, -0.5, -0.5, 0.25, 0.25, 0, 0 };
    for (expected) |value| try std.testing.expectEqual(value, player.next(&data));
    try std.testing.expect(!player.active);

    player.start(.{ .start = 1, .length = 3, .rate = 8000, .loop_start = 1, .loop_end = 3 }, 1);
    const looped = [_]f32{ 0.5, -0.5, 0.25, -0.5, 0.25, -0.5 };
    for (looped) |value| try std.testing.expectEqual(value, player.next(&data));
}

test "the Amiga plays a sample on Paula's period, voices 1 and 4 left and 2 and 3 right" {
    // A sample at 8287 Hz plays O4's C on period 428, as the trackers' C-2.
    try std.testing.expectEqual(@as(u32, 428), amiga_module.period(8287));
    try std.testing.expectEqual(@as(u32, amiga_module.min_period), amiga_module.period(100_000));

    var pool: [64]i16 = undefined;
    for (&pool, 0..) |*s, i| s.* = if (i % 2 == 0) 16384 else -16384;
    var samples: [pcm.sample_count]pcm.Sample = @splat(.{});
    samples[3] = .{ .start = 0, .length = 64, .rate = 8287, .loop_start = 0, .loop_end = 64 };
    var amiga = amiga_module.Amiga.init(rate);
    amiga.noteOn(0, 48, 15, .{ .sample = 3 }, &samples);
    var left: f32 = 0;
    var right: f32 = 0;
    for (0..rate / 10) |_| {
        const sides = amiga.sample(&pool, false);
        left = @max(left, @abs(sides[0]));
        right = @max(right, @abs(sides[1]));
    }
    try std.testing.expect(left > 0.05);
    try std.testing.expectEqual(@as(f32, 0), right);

    // Without a sample, the instrument's wave at the note's pitch, on the right.
    var wave = amiga_module.Amiga.init(rate);
    wave.noteOn(1, 57, 15, .{}, &samples);
    const out = try std.testing.allocator.alloc(f32, rate);
    defer std.testing.allocator.free(out);
    for (out) |*s| s.* = wave.sample(&pool, false)[1];
    const rises = risesOf(out);
    try std.testing.expect(rises >= 439 and rises <= 441);
}

test "the Amiga's LED filter takes the high notes away" {
    var samples: [pcm.sample_count]pcm.Sample = @splat(.{});
    var powers: [2]f32 = undefined;
    for ([_]bool{ false, true }, 0..) |led, i| {
        var amiga = amiga_module.Amiga.init(rate);
        amiga.noteOn(0, 93, 15, .{}, &samples); // about 3.5 kHz
        var sum: f32 = 0;
        for (0..rate / 2) |_| {
            const s = amiga.sample(&.{}, led)[0];
            sum += s * s;
        }
        powers[i] = sum;
    }
    // O7's A (3520 Hz) is above the filter's 3.3 kHz: its fundamental keeps under half
    // its power.
    try std.testing.expect(powers[1] < powers[0] * 0.6);
}

test "the Amiga plays a high note of a wave with fewer samples, at its pitch" {
    var samples: [pcm.sample_count]pcm.Sample = @splat(.{});
    var amiga = amiga_module.Amiga.init(rate);
    amiga.noteOn(0, 93, 15, .{}, &samples);
    try std.testing.expectEqual(@as(u32, 8), amiga.voices[0].player.sample.length);
    const out = try std.testing.allocator.alloc(f32, rate);
    defer std.testing.allocator.free(out);
    for (out) |*s| s.* = amiga.sample(&.{}, false)[0];
    const rises = risesOf(out);
    // Period 126 for 8 samples: 3546895 / (126 × 8) = 3518.7 Hz.
    try std.testing.expect(rises >= 3516 and rises <= 3521);
}

test "SFX plays a sample once beside the music, on any chip, and a stop ends it" {
    var engine = Engine.init(.ay8910, psg_module.msx_clock, rate);
    var pool: [4800]i16 = undefined;
    for (&pool, 0..) |*s, i| s.* = if (i % 20 < 10) 20000 else -20000;
    engine.pool = &pool;
    var player: Player = .{ .engine = &engine };
    try std.testing.expect(engine.putCommand(.{ .sample = .{ .index = 2, .value = .{ .start = 0, .length = 4800, .rate = 48000 } } }));
    try std.testing.expect(engine.putCommand(.{ .sfx = 2 }));
    var buffer: [960]i16 = undefined;
    engine.render(&buffer);
    var loud = false;
    for (buffer) |s| {
        if (@abs(s) > 3000) loud = true;
    }
    try std.testing.expect(loud);
    // 4800 frames are 100 ms: then nothing plays.
    player.play(200);
    try std.testing.expect(!engine.sfx_players[0].active);

    try std.testing.expect(engine.putCommand(.{ .sfx = 2 }));
    player.play(10);
    try std.testing.expect(engine.sfx_players[1].active);
    try std.testing.expect(engine.putCommand(engine.resetCommand(false)));
    player.play(10);
    try std.testing.expect(!engine.sfx_players[1].active);
}

// ---- S4b: several chips together ----

test "the chips CHIPS takes, and the voices numbered across them" {
    const Chips = engine_module.Chips;
    const msx_scc = Chips.fromMask(1 | 16).?;
    try std.testing.expectEqual(@as(usize, 8), msx_scc.voiceCount());
    try std.testing.expectEqual(@as(?engine_module.Chip, null), msx_scc.only());
    try std.testing.expectEqual(engine_module.Chip.msx, msx_scc.place(2).?.chip);
    try std.testing.expectEqual(engine_module.Chip.scc, msx_scc.place(3).?.chip);
    try std.testing.expectEqual(@as(usize, 0), msx_scc.place(3).?.voice);
    try std.testing.expectEqual(@as(usize, 4), msx_scc.place(7).?.voice);
    try std.testing.expect(msx_scc.place(8) == null);
    const nes_amiga = Chips.fromMask(4 | 32).?;
    try std.testing.expectEqual(engine_module.Chip.amiga, nes_amiga.place(4).?.chip);
    try std.testing.expectEqual(engine_module.Chip.nes, Chips.fromMask(4).?.only().?);
    // None, unknown bits, both PSGs, more than 8 voices.
    for ([_]i64{ 0, -1, 64, 1 | 2, 16 | 32, 4 | 8 | 16 }) |mask| try std.testing.expect(Chips.fromMask(mask) == null);
}

test "the MSX's PSG and the SCC play one PLAY of 8 voices together" {
    var engine = Engine.init(.ay8910, psg_module.msx_clock, rate);
    var voices: [engine_module.max_voices]mml.Voice = @splat(.{});
    var player: Player = .{ .engine = &engine };
    try std.testing.expect(engine.putCommand(engine.chipsCommand(engine_module.Chips.fromMask(1 | 16).?)));
    player.play(10);
    try engine_module.putPlay(&engine, &voices, &.{ "A", "", "", "", "", "", "", "C" }, &player, Player.wait);
    player.play(30);
    // Voice 1 on the PSG with the ROM's period, voice 8 on the SCC's fifth voice.
    try std.testing.expectEqual(@as(u8, 254), engine.psg.read(0));
    try std.testing.expectEqual(@as(u8, 8), engine.psg.read(8));
    try std.testing.expect(engine.scc.voices[4].increment > 0);
    try std.testing.expectEqual(@as(f32, 0), engine.scc.voices[0].increment);
    for ([_]usize{ 1, 8 }) |n| try std.testing.expect(engine.isPlaying(n));
    try std.testing.expect(!engine.isPlaying(2));
    player.play(1000);
    try std.testing.expect(!engine.isPlaying(0));
}
