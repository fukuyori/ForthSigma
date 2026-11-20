//! Tests of the MML, the queues of PLAY, and the engine on the standard sound's voices
//! (tque 1189), the WAV header, and the sample player.

const std = @import("std");
const mml = @import("../core/sound_mml.zig");
const engine_module = @import("../core/sound_engine.zig");
const wav = @import("../core/sound_wav.zig");
const pcm = @import("../core/sound_pcm.zig");
const sv = engine_module.voice;

const Engine = engine_module.Engine;

const rate = 48_000;

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
    // A number of any length is an error past 65535, checked at each digit, so it never
    // overflows (Codex's review R01, 2026-11-07).
    const long = [_][]const u8{ "C4294967296", "T99999999999999999999", "M65536", "N123456789012345678901234567890" };
    for (long) |text| try std.testing.expectError(error.InvalidMml, mml.check(.{}, text));
    try mml.check(.{}, "M65535 C00000000004");
    // Lower-case letters and spaces are taken.
    try mml.check(.{}, "o7 > c d+ l8 e");
}


test "PLAY's queue at its edge: 31 notes and the end mark fit, one more waits" {
    var engine = Engine.init(rate);
    var voices: [engine_module.max_voices]mml.Voice = @splat(.{});
    var player: Player = .{ .engine = &engine };
    const notes31 = "L64 T255 CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC"; // 31 notes
    try engine_module.putPlay(&engine, &voices, &.{notes31}, &player, Player.wait);
    try std.testing.expectEqual(@as(usize, 0), player.waits);
    try std.testing.expectEqual(@as(u32, 0), engine.voiceFree(0));
    // The next PLAY waits until the audio thread has taken some.
    try engine_module.putPlay(&engine, &voices, &.{"C"}, &player, Player.wait);
    try std.testing.expect(player.waits > 0);
    // A stop while the queue is full drops everything.
    var stopped = Engine.init(rate);
    var stop_voices: [engine_module.max_voices]mml.Voice = @splat(.{});
    var stop_player: Player = .{ .engine = &stopped };
    try engine_module.putPlay(&stopped, &stop_voices, &.{notes31}, &stop_player, Player.wait);
    try std.testing.expect(stopped.putCommand(stopped.resetCommand(false)));
    stop_player.play(10);
    for (0..engine_module.max_voices) |v| try std.testing.expectEqual(@as(u32, engine_module.voice_queue_size), stopped.voiceFree(v));
    try std.testing.expect(!stopped.isPlaying(0));
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
    var engine = Engine.init(rate);
    var voices = [_]mml.Voice{ .{}, .{}, .{} };
    var player: Player = .{ .engine = &engine };
    try engine_module.putPlay(&engine, &voices, &.{ "C", "C2" }, &player, Player.wait);
    try engine_module.putPlay(&engine, &voices, &.{"D"}, &player, Player.wait);
    try std.testing.expect(engine.isPlaying(0) and engine.isPlaying(1) and engine.isPlaying(2) and engine.isPlaying(3));
    try std.testing.expectEqual(@as(usize, 0), player.waits);

    // A's C (0.5 s) ends; B's C2 (1 s) goes on; the next PLAY waits for it.
    player.play(800);
    try std.testing.expect(!engine.bank.voices[0].active);
    try std.testing.expect(engine.bank.voices[1].active);
    // At 1 s the second PLAY starts A's D.
    player.play(300);
    try std.testing.expectApproxEqRel(@as(f32, @floatCast(sv.noteFrequency(50))), engine.bank.voices[0].hz, 1e-6);
    try std.testing.expect(engine.bank.voices[0].active and !engine.bank.voices[1].active);
    try std.testing.expect(engine.isPlaying(1) and !engine.isPlaying(2));
    player.play(600);
    try std.testing.expect(!engine.isPlaying(0));
    try std.testing.expect(!engine.bank.voices[0].active);
}

test "a PLAY longer than the queue plays while it is put" {
    var engine = Engine.init(rate);
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
    try std.testing.expect(!engine.bank.voices[0].active);
}

test "an invalid PLAY puts nothing" {
    var engine = Engine.init(rate);
    var voices = [_]mml.Voice{ .{}, .{}, .{} };
    var player: Player = .{ .engine = &engine };
    try std.testing.expectError(error.InvalidMml, engine_module.putPlay(&engine, &voices, &.{ "CDE", "O9C" }, &player, Player.wait));
    try std.testing.expect(!engine.isPlaying(0));
    try std.testing.expectEqual(@as(u32, 0), engine.plays_put.raw);
    try std.testing.expectEqual(@as(u8, 4), voices[0].octave);
}

test "a note plays in equal temperament at MML's volume, and S plays the envelope" {
    var engine = Engine.init(rate);
    var voices = [_]mml.Voice{ .{}, .{}, .{} };
    var player: Player = .{ .engine = &engine };
    try engine_module.putPlay(&engine, &voices, &.{ "V12O4A", "S0M100C" }, &player, Player.wait);
    player.play(20);
    try std.testing.expectApproxEqRel(@as(f32, 440), engine.bank.voices[0].hz, 1e-6);
    try std.testing.expectEqual(sv.mmlVolume(12), engine.bank.voices[0].volume);
    try std.testing.expectEqual(@as(f32, 1), engine.bank.voices[1].volume);
    try std.testing.expectEqual(@as(u8, 2), engine.bank.voices[1].tone.envelope.count);
    // S0 M100: 16 × 256 × 100 / 1789773 s ≈ 229 ms down, then silent.
    player.play(300);
    try std.testing.expect(!engine.bank.voices[1].active);
    try std.testing.expect(engine.bank.voices[0].active);
}

test "an instrument's settings reach the notes that start after them" {
    var engine = Engine.init(rate);
    var voices = [_]mml.Voice{ .{}, .{}, .{} };
    var player: Player = .{ .engine = &engine };
    try std.testing.expect(engine.putCommand(.{ .instrument = .{ .index = 3, .value = .{ .wave = .saw, .pan_left = 0 } } }));
    try engine_module.putPlay(&engine, &voices, &.{"@3C"}, &player, Player.wait);
    player.play(20);
    try std.testing.expectEqual(sv.Wave.saw, engine.bank.voices[0].tone.wave);
    var buffer: [960]i16 = undefined;
    engine.render(&buffer);
    var i: usize = 0;
    var right_loud = false;
    while (i < buffer.len) : (i += 2) {
        try std.testing.expect(@abs(buffer[i]) < 3);
        if (@abs(buffer[i + 1]) > 300) right_loud = true;
    }
    try std.testing.expect(right_loud);
}

test "BEEP drops the notes and sounds 1316 Hz for 40 ms on the standard square" {
    var engine = Engine.init(rate);
    var voices = [_]mml.Voice{ .{}, .{}, .{} };
    var player: Player = .{ .engine = &engine };
    try engine_module.putPlay(&engine, &voices, &.{"CDEFG"}, &player, Player.wait);
    player.play(100);
    try std.testing.expect(engine.putCommand(engine.resetCommand(true)));
    var buffer: [2 * 480]i16 = undefined; // 10 ms
    engine.render(&buffer);
    try std.testing.expect(!engine.isPlaying(0));
    try std.testing.expectApproxEqRel(@as(f32, 1316.0), engine.bank.voices[0].hz, 1e-3);
    try std.testing.expectEqual(sv.mmlVolume(7), engine.bank.voices[0].volume);
    player.play(40);
    try std.testing.expect(!engine.bank.voices[0].active);
}

test "PLAY-TONE sounds beside the music, and the output is 16-bit stereo without the constant level" {
    var engine = Engine.init(rate);
    try std.testing.expect(engine.putCommand(.{ .tone = .{ .hz = 1000, .ms = 100 } }));
    var buffer: [2 * 2400]i16 = undefined;
    engine.render(&buffer);
    try std.testing.expect(engine.bank.voices[engine_module.sfx_first].active);
    var low: i16 = 0;
    var high: i16 = 0;
    var i: usize = 0;
    while (i < buffer.len) : (i += 2) {
        try std.testing.expectEqual(buffer[i], buffer[i + 1]);
        low = @min(low, buffer[i]);
        high = @max(high, buffer[i]);
    }
    try std.testing.expect(low < -5000 and high > 5000);
    // After its 100 ms, silence settles at 0.
    for (0..20) |_| engine.render(&buffer);
    try std.testing.expect(!engine.bank.voices[engine_module.sfx_first].active);
    try std.testing.expect(@abs(buffer[buffer.len - 2]) < 2);
}

test "the same notes always make the same samples" {
    var a = Engine.init(rate);
    var b = Engine.init(rate);
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

test "a note's pitch in equal temperament" {
    try std.testing.expectApproxEqAbs(@as(f64, 440), sv.noteFrequency(57), 1e-9);
    try std.testing.expectApproxEqAbs(@as(f64, 220), sv.noteFrequency(45), 1e-9);
    try std.testing.expectApproxEqAbs(@as(f64, 261.6256), sv.noteFrequency(48), 1e-3);
}

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

test "SFX plays a sample once beside the music on voices 9 to 12, and a stop ends it" {
    var engine = Engine.init(rate);
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
    try std.testing.expect(!engine.bank.voices[engine_module.sfx_first].active);

    try std.testing.expect(engine.putCommand(.{ .sfx = 2 }));
    player.play(10);
    try std.testing.expect(engine.bank.voices[engine_module.sfx_first + 1].active);
    // A stop of PLAY alone keeps it; a full stop ends it.
    try std.testing.expect(engine.putCommand(engine.stopPlayCommand()));
    player.play(10);
    try std.testing.expect(engine.bank.voices[engine_module.sfx_first + 1].active);
    try std.testing.expect(engine.putCommand(engine.resetCommand(false)));
    player.play(10);
    try std.testing.expect(!engine.bank.voices[engine_module.sfx_first + 1].active);
}
