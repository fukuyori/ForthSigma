//! Tests of REQUIRE-AUDIO and the audio words, with the fake host's sound engine: the
//! host's waits play what the audio thread would play meanwhile.

const std = @import("std");
const forth = @import("../forth.zig");
const defs = @import("../core/defs.zig");
const memory_map = @import("../core/memory_map.zig");
const mml = @import("../core/sound_mml.zig");
const sound_engine = @import("../core/sound_engine.zig");
const words_audio = @import("../core/words_audio.zig");
const support = @import("support.zig");
const Output = support.Output;
const createMachine = support.createMachine;
const destroyMachine = support.destroyMachine;
const expectStack = support.expectStack;
const skipWithout = support.skipWithout;

const Engine = sound_engine.Engine;
const rate = 48_000;

fn newEngine() Engine {
    return Engine.init(rate);
}

/// Plays `frames` frames, as the audio thread would.
fn render(engine: *Engine, frames: usize) void {
    var samples: [960 * 2]i16 = undefined;
    var left = frames;
    while (left > 0) {
        const count: usize = @min(left, 960);
        engine.render(samples[0 .. count * 2]);
        left -= count;
    }
}

/// The items waiting in a voice's queue.
fn queued(engine: *const Engine, voice: usize) u32 {
    return sound_engine.voice_queue_size - engine.voiceFree(voice);
}

fn saveImage(machine: *forth.State) ![]u8 {
    const image = try std.testing.allocator.alloc(u8, forth.State.imageCapacity(.small));
    errdefer std.testing.allocator.free(image);
    const length = try machine.encodeImage(image);
    return image[0..length];
}

fn freeImage(image: []u8) void {
    std.testing.allocator.free(image.ptr[0..forth.State.imageCapacity(.small)]);
}

test "REQUIRE-AUDIO is refused in a build without audio" {
    if (@import("build_options").audio) return error.SkipZigTest;
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    try std.testing.expectError(error.AudioUnavailable, machine.interpretLine("REQUIRE-AUDIO"));
    try std.testing.expect(machine.lookup("AUDIO") == null);
}

test "REQUIRE-AUDIO appends AUDIO, the SND- words, and the library once, keeping the search order" {
    try skipWithout(&.{.audio});
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    const builtins = machine.builtin_count;
    const words_before = machine.word_count;
    try machine.interpretLine("ORDER");
    const order_before = try std.testing.allocator.dupe(u8, output.written());
    defer std.testing.allocator.free(order_before);
    output.len = 0;

    try machine.interpretLine("REQUIRE-AUDIO");
    try std.testing.expectEqual(builtins, machine.builtin_count);
    try std.testing.expectEqual(defs.WordKind.vocabulary, machine.words[words_before].kind);
    for (words_audio.definitions, 1..) |definition, offset| {
        try std.testing.expectEqual(definition[1], machine.words[words_before + offset].builtin);
    }
    try std.testing.expect(words_audio.audioLoaded(machine));
    try machine.interpretLine("ORDER");
    try std.testing.expectEqualStrings(order_before, output.written());
    try std.testing.expect(machine.lookup("PLAY") == null);

    const words_after = machine.word_count;
    try machine.interpretLine("REQUIRE-AUDIO require-audio");
    try std.testing.expectEqual(words_after, machine.word_count);
    for (words_audio.library_words) |name| {
        try machine.interpretLine("ALSO AUDIO");
        try std.testing.expect(machine.lookup(name) != null);
        try machine.interpretLine("PREVIOUS");
    }

    // Not inside a definition, as REQUIRE-GRAPHICS.
    var other_output = Output{};
    const other = try createMachine(&other_output);
    defer destroyMachine(other);
    try other.interpretLine(": X");
    try std.testing.expectError(error.InvalidDefinition, other.interpretLine("REQUIRE-AUDIO"));
}

test "a dictionary that has had the audio words is saved as SIGIMG47, which LOAD reads" {
    try skipWithout(&.{ .audio, .image });
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    const plain = try saveImage(machine);
    defer freeImage(plain);
    try std.testing.expectEqualStrings("SIGIMG45", plain[0..8]);

    try machine.interpretLine("REQUIRE-AUDIO ALSO AUDIO DEFINITIONS : TUNE S\" CDE\" PLAY ; FORTH DEFINITIONS PREVIOUS");
    const image = try saveImage(machine);
    defer freeImage(image);
    try std.testing.expectEqualStrings("SIGIMG47", image[0..8]);

    const loaded = try createMachine(&output);
    defer destroyMachine(loaded);
    try loaded.restoreImage(image);
    try std.testing.expect(words_audio.audioLoaded(loaded));
    try std.testing.expectEqual(@as(forth.Cell, 1), loaded.readCellConst(memory_map.audio_image_address));

    // Appended to another dictionary, the words count as loaded there too.
    const target = try createMachine(&output);
    defer destroyMachine(target);
    try target.interpretLine(": EXISTING 99 ;");
    try target.appendImage(loaded);
    try std.testing.expect(words_audio.audioLoaded(target));
    const words_after = target.word_count;
    try target.interpretLine("REQUIRE-AUDIO");
    try std.testing.expectEqual(words_after, target.word_count);
    const appended = try saveImage(target);
    defer freeImage(appended);
    try std.testing.expectEqualStrings("SIGIMG47", appended[0..8]);
}

test "PLAY puts the notes of voice A and an end mark in every voice, and PLAY? sees them" {
    try skipWithout(&.{.audio});
    var engine = newEngine();
    var output = Output{ .audio = &engine };
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    try machine.interpretLine("REQUIRE-AUDIO ALSO AUDIO");

    try machine.interpretLine("0 PLAY? 1 PLAY?");
    try expectStack(machine, &.{ 0, 0 });
    machine.data_depth = 0;
    try machine.interpretLine("S\" CDE\" PLAY");
    try std.testing.expectEqual(@as(u32, 4), queued(&engine, 0));
    try std.testing.expectEqual(@as(u32, 1), queued(&engine, 1));
    try std.testing.expectEqual(@as(u32, 1), queued(&engine, 2));
    try std.testing.expectEqual(@as(usize, 0), output.audio_waits);
    // Voice B's end mark counts until the audio thread takes it, at the next tick (as
    // on the MSX, whose ROM also ends every voice of a PLAY with a mark).
    try machine.interpretLine("0 PLAY? 1 PLAY? 2 PLAY?");
    try expectStack(machine, &.{ -1, -1, -1 });
    machine.data_depth = 0;
    render(&engine, rate / 50);
    try machine.interpretLine("0 PLAY? 1 PLAY? 2 PLAY?");
    try expectStack(machine, &.{ -1, -1, 0 });
    machine.data_depth = 0;

    // Three quarter notes at T120 are 1.5 s; then nothing plays.
    render(&engine, rate * 2);
    try machine.interpretLine("0 PLAY?");
    try expectStack(machine, &.{0});
    machine.data_depth = 0;

    // PLAY2 and PLAY3 fill voices B and C; the voices keep their settings.
    try machine.interpretLine("S\" O5 L8 C\" S\" D\" PLAY2  S\" E\" S\" F\" S\" G\" PLAY3");
    try std.testing.expectEqual(@as(u8, 5), machine.audio_voices[0].octave);
    try std.testing.expectEqual(@as(u8, 8), machine.audio_voices[0].length);
    try std.testing.expectEqual(@as(u32, 4), queued(&engine, 1));
    try std.testing.expectEqual(@as(u32, 3), queued(&engine, 2));

    try std.testing.expectError(error.InvalidNumber, machine.interpretLine("9 PLAY?"));
    machine.data_depth = 0;
    try std.testing.expectError(error.InvalidNumber, machine.interpretLine("-1 PLAY?"));
}

test "PLAY with invalid MML throws INVALID MML (-274) and puts nothing" {
    try skipWithout(&.{.audio});
    var engine = newEngine();
    var output = Output{ .audio = &engine };
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    try machine.interpretLine("REQUIRE-AUDIO ALSO AUDIO");
    // Voice C's string is wrong: voices A and B put nothing either.
    try std.testing.expectError(error.InvalidMml, machine.interpretLine("S\" CDE\" S\" EFG\" S\" O9C\" PLAY3"));
    for (0..3) |v| try std.testing.expectEqual(@as(u32, 0), queued(&engine, v));
    try std.testing.expectEqual(mml.Voice{}, machine.audio_voices[0]);
    machine.data_depth = 0;
    try machine.interpretLine(": TRY S\" C65\" ['] PLAY CATCH ; TRY");
    try std.testing.expectEqual(@as(usize, 3), machine.data_depth);
    try std.testing.expectEqual(@as(forth.Cell, -274), machine.data_stack[2]);
    machine.data_depth = 0;
    try std.testing.expectError(error.InvalidMml, machine.interpretLine("S\" X\" PLAY"));
    output.len = 0;
    machine.report(error.InvalidMml);
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "INVALID MML !") != null);
}

test "a long PLAY waits for room while the audio thread plays, and starts before it is all put" {
    try skipWithout(&.{.audio});
    var engine = newEngine();
    var output = Output{ .audio = &engine };
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    try machine.interpretLine("REQUIRE-AUDIO ALSO AUDIO");
    // 100 notes of L64 at T255 (5 ticks each) do not fit in 32 places.
    try machine.interpretLine("S\" T255 L64\" PLAY S\" " ++ support.repeat("C", 100) ++ "\" PLAY");
    try std.testing.expect(output.audio_waits > 0);
    try std.testing.expect(queued(&engine, 0) <= sound_engine.voice_queue_size);
    render(&engine, rate * 20);
    try machine.interpretLine("0 PLAY?");
    try expectStack(machine, &.{0});
}

test "Ctrl+C while PLAY waits throws USER INTERRUPT and drops the notes put so far" {
    try skipWithout(&.{.audio});
    var engine = newEngine();
    var output = Output{ .audio = &engine, .audio_interrupt_at = 2 };
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    try machine.interpretLine("REQUIRE-AUDIO ALSO AUDIO");
    try std.testing.expectError(error.UserInterrupt, machine.interpretLine("S\" O2 " ++ support.repeat("C", 100) ++ "\" PLAY"));
    try std.testing.expectEqual(mml.Voice{}, machine.audio_voices[0]);
    // The stop has reached the audio thread before PLAY threw.
    for (0..3) |v| try std.testing.expectEqual(@as(u32, 0), queued(&engine, v));
    try machine.interpretLine("0 PLAY?");
    try expectStack(machine, &.{0});
}

test "PLAY reports an interrupt scope failure as HOST FUNCTION ERROR" {
    try skipWithout(&.{.audio});
    var engine = newEngine();
    var output = Output{ .audio = &engine };
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    const Fake = struct {
        fn wait(context: ?*anyopaque) forth.AudioWait {
            const output_value: *Output = @ptrCast(@alignCast(context.?));
            const outcome = Output.audioWait(context);
            return if (output_value.audio_waits == 1) .host_failed else outcome;
        }
    };
    machine.writer.audio_wait_fn = Fake.wait;
    try machine.interpretLine("REQUIRE-AUDIO ALSO AUDIO");
    try std.testing.expectError(error.HostFailed, machine.interpretLine("S\" " ++ support.repeat("C", 100) ++ "\" PLAY"));
    try std.testing.expectEqual(mml.Voice{}, machine.audio_voices[0]);
    for (0..3) |v| try std.testing.expectEqual(@as(u32, 0), queued(&engine, v));
}

test "persistent audio host failure reports an error without claiming reset was consumed" {
    try skipWithout(&.{.audio});
    var engine = newEngine();
    var output = Output{ .audio = &engine };
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    const Fake = struct {
        fn wait(context: ?*anyopaque) forth.AudioWait {
            const value: *Output = @ptrCast(@alignCast(context.?));
            value.audio_waits += 1;
            return .host_failed;
        }
    };
    machine.writer.audio_wait_fn = Fake.wait;
    try machine.interpretLine("REQUIRE-AUDIO ALSO AUDIO");
    try std.testing.expectError(error.HostFailed, machine.interpretLine("S\" " ++ support.repeat("C", 100) ++ "\" PLAY"));
    try std.testing.expect(output.audio_waits < 4);
    try std.testing.expect(!engine.commands.isEmpty());
    render(&engine, 1);
    for (0..3) |v| try std.testing.expectEqual(@as(u32, 0), queued(&engine, v));
}

test "Ctrl+C as a key, when the terminal gives single keys, also stops PLAY's wait" {
    try skipWithout(&.{.audio});
    var engine = newEngine();
    const events = [_]forth.InputEvent{.{ .key = 3 }};
    var output = Output{ .audio = &engine, .audio_read_input_at = 1, .events = &events };
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    try machine.interpretLine("REQUIRE-AUDIO ALSO AUDIO");
    try std.testing.expectError(error.UserInterrupt, machine.interpretLine("S\" " ++ support.repeat("C", 100) ++ "\" PLAY"));
    for (0..3) |v| try std.testing.expectEqual(@as(u32, 0), queued(&engine, v));
}

test "the chips' words left the core: their SND- words throw -21 and the library has none of them" {
    try skipWithout(&.{.audio});
    var engine = newEngine();
    var output = Output{ .audio = &engine };
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    try machine.interpretLine("REQUIRE-AUDIO ALSO AUDIO");
    for ([_][]const u8{ "0 100 SND-SOUND", "0 SND-CHIP", "1 SND-CHIPS", "4 SND-STYLE", "TRUE SND-AMIGA-FILTER" }) |line| {
        try std.testing.expectError(error.HostUnavailable, machine.interpretLine(line));
        machine.data_depth = 0;
    }
    inline for (.{ "SOUND", "MSX-SOUND", "NES-SOUND", "CHIPS", "STYLE", "SCC-WAVE", "AMIGA-FILTER" }) |name| {
        try machine.interpretLine("S\" " ++ name ++ "\" FIND-NAME 0=");
        try expectStack(machine, &.{-1});
        machine.data_depth = 0;
    }
}

test "BEEP drops the music and the voices' settings, and beeps" {
    try skipWithout(&.{.audio});
    var engine = newEngine();
    var output = Output{ .audio = &engine };
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    try machine.interpretLine("REQUIRE-AUDIO ALSO AUDIO");
    try machine.interpretLine("S\" O2 L8 T200 V12 CDEFGAB\" PLAY BEEP");
    try std.testing.expectEqual(mml.Voice{}, machine.audio_voices[0]);
    try machine.interpretLine("0 PLAY?");
    try expectStack(machine, &.{0});
    render(&engine, 1);
    for (0..3) |v| try std.testing.expectEqual(@as(u32, 0), queued(&engine, v));
    try std.testing.expectApproxEqRel(sound_engine.beep_hz, engine.bank.voices[0].hz, 1e-6);
    try std.testing.expect(engine.bank.voices[0].active);
    render(&engine, rate / 10);
    try std.testing.expect(!engine.bank.voices[0].active);
}

test "AUDIO? tells whether the sound reaches a device; without the host's engine the words fail" {
    try skipWithout(&.{.audio});
    var engine = newEngine();
    var output = Output{ .audio = &engine };
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    try machine.interpretLine("REQUIRE-AUDIO ALSO AUDIO AUDIO?");
    output.audio_device = true;
    try machine.interpretLine("AUDIO?");
    try expectStack(machine, &.{ 0, -1 });

    var failing_output = Output{};
    const failing = try createMachine(&failing_output);
    defer destroyMachine(failing);
    try failing.interpretLine("REQUIRE-AUDIO ALSO AUDIO");
    try std.testing.expectError(error.HostFailed, failing.interpretLine("BEEP"));
}

test "PLAYS and PLAY? take the 8 voices of PLAY" {
    try skipWithout(&.{.audio});
    var engine = newEngine();
    var output = Output{ .audio = &engine };
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    try machine.interpretLine("REQUIRE-AUDIO ALSO AUDIO");
    for ([_][]const u8{ "9 PLAYS", "9 PLAY?", "-1 PLAYS" }) |line| {
        try std.testing.expectError(error.InvalidNumber, machine.interpretLine(line));
        machine.data_depth = 0;
    }
    try machine.interpretLine("S\" C\" S\" E\" S\" G\" S\" C\" S\" E\" S\" G\" S\" >C\" S\" <C\" 8 PLAYS 8 PLAY?");
    try expectStack(machine, &.{-1});
    machine.data_depth = 0;
    try std.testing.expectEqual(@as(u32, 2), queued(&engine, 7));
}

test "INSTRUMENT and the words after it change an instrument here and for the audio thread" {
    try skipWithout(&.{.audio});
    var engine = newEngine();
    var output = Output{ .audio = &engine };
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    try machine.interpretLine("REQUIRE-AUDIO ALSO AUDIO");
    try machine.interpretLine("7 INSTRUMENT PULSE 16384 DUTY 10 200 40000 300 ADSR");
    var expected: sound_engine.Tone = .{ .wave = .pulse, .duty = 16384 };
    expected.envelope = words_audio.adsrEnvelope(10, 200, 40000, 300);
    try std.testing.expectEqualDeep(expected, machine.audio_instruments[7]);
    render(&engine, 1);
    try std.testing.expectEqualDeep(expected, engine.instruments[7]);
    try std.testing.expectEqualDeep(sound_engine.Tone{}, engine.instruments[0]);
    try machine.interpretLine("SQUARE TRIANGLE SAW NOISE");
    try std.testing.expectEqual(sound_engine.voice.Wave.noise, machine.audio_instruments[7].wave);

    // The ranges; an error changes nothing.
    for ([_][]const u8{ "64 INSTRUMENT", "-1 INSTRUMENT", "65536 DUTY", "-1 DUTY", "0 0 65536 0 ADSR", "0 0 0 -1 ADSR", "5 SND-WAVE" }) |line| {
        try std.testing.expectError(error.InvalidNumber, machine.interpretLine(line));
        machine.data_depth = 0;
    }
    try std.testing.expectEqual(@as(u16, 16384), machine.audio_instruments[7].duty);
    // BEEP keeps the instruments.
    try machine.interpretLine("BEEP");
    try std.testing.expectEqual(expected.duty, machine.audio_instruments[7].duty);
}

test "RING, SYNC, and FILTER take source voices and Hz" {
    try skipWithout(&.{.audio});
    var engine = newEngine();
    var output = Output{ .audio = &engine };
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    try machine.interpretLine("REQUIRE-AUDIO ALSO AUDIO 4 INSTRUMENT TRIANGLE 3 RING 16 SYNC 2 1500 30000 FILTER");
    const tone = machine.audio_instruments[4];
    try std.testing.expectEqual(@as(u8, 3), tone.ring);
    try std.testing.expectEqual(@as(u8, 16), tone.sync);
    try std.testing.expectEqual(sound_engine.voice.FilterMode.band_pass, tone.filter);
    try std.testing.expectEqual(@as(u32, 1500), tone.filter_hz);
    try std.testing.expectEqual(@as(u16, 30000), tone.resonance);
    render(&engine, 1);
    try std.testing.expectEqualDeep(tone, engine.instruments[4]);
    try machine.interpretLine("0 RING 4 100 0 FILTER");
    try std.testing.expectEqual(@as(u8, 0), machine.audio_instruments[4].ring);
    try std.testing.expectEqual(sound_engine.voice.FilterMode.notch, machine.audio_instruments[4].filter);
    for ([_][]const u8{ "17 RING", "-1 SYNC", "5 0 0 FILTER", "1 1000001 0 FILTER", "1 0 65536 FILTER", "-1 0 0 FILTER" }) |line| {
        try std.testing.expectError(error.InvalidNumber, machine.interpretLine(line));
        machine.data_depth = 0;
    }
}

test "WAVETABLE puts a cycle of cells in the pool for the instrument INSTRUMENT chose" {
    try skipWithout(&.{.audio});
    var engine = newEngine();
    var pool: [64]i16 = undefined;
    engine.pool = &pool;
    var output = Output{ .audio = &engine };
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    try machine.interpretLine("REQUIRE-AUDIO ALSO AUDIO CREATE W 32767 , -32768 , 0 , 100 ,");
    try machine.interpretLine("3 INSTRUMENT W 4 WAVETABLE");
    const tone = machine.audio_instruments[3];
    try std.testing.expectEqual(sound_engine.voice.Wave.wavetable, tone.wave);
    try std.testing.expectEqual(@as(u32, 4), tone.table.length);
    try std.testing.expectEqualSlices(i16, &.{ 32767, -32768, 0, 100 }, pool[tone.table.start..][0..4]);
    try std.testing.expectEqual(@as(u32, 4), machine.audio_pool_used);
    try machine.interpretLine("CREATE BAD 32768 ,");
    for ([_][]const u8{ "BAD 1 WAVETABLE", "W 0 WAVETABLE", "W 65537 WAVETABLE" }) |line| {
        try std.testing.expectError(error.InvalidNumber, machine.interpretLine(line));
        machine.data_depth = 0;
    }
    try std.testing.expectEqual(@as(u32, 4), machine.audio_pool_used);
    try std.testing.expectError(error.InvalidAddress, machine.interpretLine("-5 1 WAVETABLE"));
}

test "the instrument words of the standard sound check their ranges before changing anything" {
    try skipWithout(&.{.audio});
    var engine = newEngine();
    var output = Output{ .audio = &engine };
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    try machine.interpretLine("REQUIRE-AUDIO ALSO AUDIO 5 INSTRUMENT");
    try machine.interpretLine("17 3 NOISE-LFSR 2 NOISE-MIX -100 20 PITCH-SWEEP 50 2000 PITCH-SWEEP-LIMIT 30 PORTAMENTO 20 6 100 VIBRATO");
    try machine.interpretLine("1 -1200 PITCH-MOD 2 30000 VOLUME-MOD TRUE MOD-ONLY TRUE PHASE-RESET 250 NOTE-LIMIT -65535 32768 VOICE-PAN 1000 REVERB-SEND");
    try machine.interpretLine("CREATE SEGS 65535 , 10 , 0 ,  20000 , 100 , 1 ,  0 , 50 , 1 ,  SEGS 3 -1 1 ENVELOPE");
    const t = machine.audio_instruments[5];
    try std.testing.expectEqual(@as(u8, 17), t.noise_bits);
    try std.testing.expectEqual(@as(u8, 3), t.noise_tap);
    try std.testing.expectEqual(sound_engine.voice.NoiseMix.gate, t.noise_mix);
    try std.testing.expectEqual(@as(i32, -100), t.sweep_cents);
    try std.testing.expectEqual(@as(u32, 20), t.sweep_ms);
    try std.testing.expectEqual(@as(u32, 2000), t.sweep_high_hz);
    try std.testing.expectEqual(@as(u32, 30), t.portamento_ms);
    try std.testing.expectEqual(@as(u32, 100), t.vibrato_delay_ms);
    try std.testing.expectEqual(@as(i32, -1200), t.pitch_mod_cents);
    try std.testing.expectEqual(@as(u16, 30000), t.volume_mod_depth);
    try std.testing.expect(t.mod_only and t.phase_reset);
    try std.testing.expectEqual(@as(u32, 250), t.note_limit_ms);
    try std.testing.expectEqual(@as(i32, -65535), t.pan_left);
    try std.testing.expectEqual(@as(u16, 1000), t.reverb_send);
    try std.testing.expectEqual(@as(u8, 3), t.envelope.count);
    try std.testing.expectEqual(@as(i8, 1), t.envelope.release);
    try std.testing.expectEqual(@as(u16, 20000), t.envelope.segments[1].level);
    try std.testing.expectEqual(@as(u8, 1), t.envelope.segments[2].curve);
    render(&engine, 1);
    try std.testing.expectEqualDeep(t, engine.instruments[5]);
    for ([_][]const u8{ "1 1 NOISE-LFSR", "33 1 NOISE-LFSR", "8 8 NOISE-LFSR", "3 NOISE-MIX", "SEGS 17 -1 -1 ENVELOPE", "SEGS 3 3 -1 ENVELOPE", "SEGS 0 0 -1 ENVELOPE", "2000 50 PITCH-SWEEP-LIMIT", "-1 PORTAMENTO", "-1 6 0 VIBRATO", "17 0 PITCH-MOD", "1 65536 VOLUME-MOD", "-65536 0 VOICE-PAN", "65536 REVERB-SEND", "21 SND-TONE" }) |line| {
        try std.testing.expectError(error.InvalidNumber, machine.interpretLine(line));
        machine.data_depth = 0;
    }
    try machine.interpretLine("CREATE BADSEG 65536 , 10 , 0 ,");
    try std.testing.expectError(error.InvalidNumber, machine.interpretLine("BADSEG 1 -1 -1 ENVELOPE"));
    machine.data_depth = 0;
    try std.testing.expectEqualDeep(t, machine.audio_instruments[5]);
    // 0 segments: no envelope.
    try machine.interpretLine("0 0 -1 -1 ENVELOPE");
    try std.testing.expectEqual(@as(u8, 0), machine.audio_instruments[5].envelope.count);
}

test "E00 turns MOD-FILTER's filter on for MOD's voices only, and E01 off" {
    try skipWithout(&.{ .audio, .files });
    var engine = newEngine();
    var pool: [8192]i16 = undefined;
    engine.pool = &pool;
    var output = Output{ .audio = &engine };
    support.setFakeFile(&output, 0, &modFile(1, &.{ .{ 0, modCell(1, 428, 0xe, 0x00) }, .{ 2, modCell(0, 0, 0xe, 0x01) } }));
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    try machine.interpretLine("REQUIRE-AUDIO ALSO AUDIO 1 3300 MOD-FILTER S\" a.txt\" LOAD-MOD FALSE PLAY-MOD S\" C1\" PLAY");
    _ = playUntil(&engine, .row, 1);
    render(&engine, 10);
    for (0..4) |c| {
        const v = engine.bank.voices[sound_engine.mod_first + c];
        try std.testing.expectEqual(sound_engine.voice.FilterMode.low_pass, v.tone.filter);
        try std.testing.expectEqual(@as(u32, 3300), v.tone.filter_hz);
    }
    try std.testing.expectEqual(sound_engine.voice.FilterMode.none, engine.bank.voices[0].tone.filter);
    _ = playUntil(&engine, .row, 3);
    render(&engine, 10);
    for (0..4) |c| try std.testing.expectEqual(sound_engine.voice.FilterMode.none, engine.bank.voices[sound_engine.mod_first + c].tone.filter);
}

test "the effects on all the voices and the voices' state through the words" {
    try skipWithout(&.{.audio});
    const engine = try std.testing.allocator.create(Engine);
    defer std.testing.allocator.destroy(engine);
    engine.* = newEngine();
    var output = Output{ .audio = engine };
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    try machine.interpretLine("REQUIRE-AUDIO ALSO AUDIO 100 -30000 20000 REVERB CREATE C 64 , 64 , C 2 REVERB-FIR 3 5000 MASTER-FILTER 6 -3 TONE-CONTROL 40000 MASTER-VOLUME");
    render(engine, 1);
    try std.testing.expectEqual(@as(u32, 4800), engine.master.delay_frames);
    try std.testing.expectEqual(@as(u8, 2), engine.master.fir_count);
    try std.testing.expectEqual(@import("../core/sound_master.zig").FilterMode.high_pass, engine.master.filter);
    try std.testing.expectApproxEqRel(@as(f32, 40000.0 / 65535.0), engine.master.volume, 1e-6);
    for ([_][]const u8{ "342 0 1 REVERB", "0 65536 1 REVERB", "C 9 REVERB-FIR", "2 1000 MASTER-FILTER", "13 0 TONE-CONTROL", "65536 MASTER-VOLUME", "8 SND-GLOBAL", "0 VOICE-ON?", "17 VOICE-ON?", "1 5 SND-VOICE" }) |line| {
        try std.testing.expectError(error.InvalidNumber, machine.interpretLine(line));
        machine.data_depth = 0;
    }
    try machine.interpretLine("S\" C1\" PLAY");
    render(engine, 960);
    try machine.interpretLine("1 VOICE-ON? 2 VOICE-ON? 1 VOICE-ENV 1 VOICE-POS 1 VOICE-ENDS");
    try expectStack(machine, &.{ -1, 0, 65535, -1, 0 });
    machine.data_depth = 0;
    try machine.interpretLine("1 VOICE-OSC ABS 32767 <=");
    try expectStack(machine, &.{-1});
}

test "FREE-SAMPLES forgets the wavetables on both sides" {
    try skipWithout(&.{.audio});
    var engine = newEngine();
    var pool: [64]i16 = undefined;
    engine.pool = &pool;
    var output = Output{ .audio = &engine };
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    try machine.interpretLine("REQUIRE-AUDIO ALSO AUDIO CREATE W 1 , 2 , 2 INSTRUMENT W 2 WAVETABLE FREE-SAMPLES");
    render(&engine, 1);
    try std.testing.expectEqual(@as(u32, 0), machine.audio_instruments[2].table.length);
    try std.testing.expectEqual(sound_engine.voice.Wave.square, machine.audio_instruments[2].wave);
    try std.testing.expectEqualDeep(machine.audio_instruments[2], engine.instruments[2]);
}

test "PLAY-TONE sounds on an SFX voice and MOD-FILTER sets the filter of E0x" {
    try skipWithout(&.{.audio});
    var engine = newEngine();
    var output = Output{ .audio = &engine };
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    try machine.interpretLine("REQUIRE-AUDIO ALSO AUDIO 880 100 PLAY-TONE 1 3300 MOD-FILTER");
    render(&engine, 1);
    try std.testing.expect(engine.bank.voices[sound_engine.sfx_first].active);
    try std.testing.expectApproxEqRel(@as(f32, 880), engine.bank.voices[sound_engine.sfx_first].hz, 1e-6);
    try std.testing.expectEqual(sound_engine.voice.FilterMode.low_pass, engine.mod_filter);
    try std.testing.expectEqual(@as(u32, 3300), engine.mod_filter_hz);
    for ([_][]const u8{ "-1 100 PLAY-TONE", "440 -1 PLAY-TONE", "440 3600001 PLAY-TONE", "0 0 0 3600001 ADSR", "5 100 MOD-FILTER", "1 -1 MOD-FILTER" }) |line| {
        try std.testing.expectError(error.InvalidNumber, machine.interpretLine(line));
        machine.data_depth = 0;
    }
}

/// A WAV file of 16-bit mono PCM at 11025 Hz with `frames` samples 0, 500, 1000, ...,
/// and a LIST chunk before the data (which LOAD-SAMPLE skips).
fn wavFile(comptime frames: usize) [12 + 24 + 12 + 8 + frames * 2]u8 {
    var bytes: [12 + 24 + 12 + 8 + frames * 2]u8 = undefined;
    @memcpy(bytes[0..4], "RIFF");
    std.mem.writeInt(u32, bytes[4..8], bytes.len - 8, .little);
    @memcpy(bytes[8..16], "WAVEfmt ");
    std.mem.writeInt(u32, bytes[16..20], 16, .little);
    std.mem.writeInt(u16, bytes[20..22], 1, .little);
    std.mem.writeInt(u16, bytes[22..24], 1, .little);
    std.mem.writeInt(u32, bytes[24..28], 11025, .little);
    std.mem.writeInt(u32, bytes[28..32], 22050, .little);
    std.mem.writeInt(u16, bytes[32..34], 2, .little);
    std.mem.writeInt(u16, bytes[34..36], 16, .little);
    @memcpy(bytes[36..40], "LIST");
    std.mem.writeInt(u32, bytes[40..44], 4, .little);
    @memcpy(bytes[44..48], "INFO");
    @memcpy(bytes[48..52], "data");
    std.mem.writeInt(u32, bytes[52..56], frames * 2, .little);
    for (0..frames) |i| std.mem.writeInt(i16, bytes[56 + i * 2 ..][0..2], @intCast(i * 500), .little);
    return bytes;
}

test "LOAD-SAMPLE reads a WAV file into the pool; other files throw SAMPLE ERROR (-276)" {
    try skipWithout(&.{ .audio, .files });
    var engine = newEngine();
    var pool: [64]i16 = undefined;
    engine.pool = &pool;
    var output = Output{ .audio = &engine };
    support.setFakeFile(&output, 0, &wavFile(20));
    support.setFakeFile(&output, 1, "RIFF....AVI LIST");
    support.setFakeFile(&output, 2, &wavFile(50));
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    try machine.interpretLine("REQUIRE-AUDIO ALSO AUDIO");
    try machine.interpretLine("S\" a.txt\" 5 LOAD-SAMPLE");
    try std.testing.expectEqual(sound_engine.pcm.Sample{ .start = 0, .length = 20, .rate = 11025 }, machine.audio_samples[5]);
    try std.testing.expectEqual(@as(i16, 9500), pool[19]);
    try std.testing.expectEqual(@as(u32, 20), machine.audio_pool_used);
    render(&engine, 1);
    try std.testing.expectEqual(machine.audio_samples[5], engine.samples[5]);

    // A file whose data ends before the size its "data" chunk says: the sample is
    // what there is (as a module's samples), here 10 frames of the 30 it says.
    var short = wavFile(10);
    std.mem.writeInt(u32, short[52..56], 30 * 2, .little);
    support.setFakeFile(&output, 3, &short);
    try machine.interpretLine("S\" d.txt\" 7 LOAD-SAMPLE");
    try std.testing.expectEqual(@as(u32, 10), machine.audio_samples[7].length);
    try std.testing.expectEqual(@as(u32, 30), machine.audio_pool_used);
    // (put back as it was before, for the checks below)
    machine.audio_samples[7] = .{};
    machine.audio_pool_used = 20;

    try machine.interpretLine("S\" b.txt\" 6 SND-LOAD-SAMPLE S\" missing.txt\" 6 SND-LOAD-SAMPLE 0<>");
    try std.testing.expectEqual(@as(forth.Cell, -276), machine.data_stack[0]);
    try std.testing.expectEqual(@as(forth.Cell, -1), machine.data_stack[1]);
    machine.data_depth = 0;
    try std.testing.expectError(error.SampleInvalid, machine.interpretLine("S\" b.txt\" 6 LOAD-SAMPLE"));
    machine.data_depth = 0;
    // 50 more samples do not fit in the 64 of this pool: nothing changes.
    try machine.interpretLine("S\" c.txt\" 6 SND-LOAD-SAMPLE");
    try expectStack(machine, &.{-257});
    machine.data_depth = 0;
    try std.testing.expectEqual(@as(u32, 20), machine.audio_pool_used);
    try std.testing.expectEqual(@as(u32, 0), machine.audio_samples[6].length);
    try std.testing.expectError(error.InvalidNumber, machine.interpretLine("S\" a.txt\" 64 LOAD-SAMPLE"));
}

test "SAMPLE, LOOP-SAMPLE, SAMPLE-INSTRUMENT, SFX, and FREE-SAMPLES" {
    try skipWithout(&.{.audio});
    var engine = newEngine();
    var pool: [64]i16 = undefined;
    engine.pool = &pool;
    var output = Output{ .audio = &engine };
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    try machine.interpretLine("REQUIRE-AUDIO ALSO AUDIO");
    try machine.interpretLine("CREATE S 10 ALLOT S 10 0 FILL 127 S C! 128 S 1 + C!  S 10 8000 1 SAMPLE");
    try std.testing.expectEqual(@as(i16, 127 * 256), pool[0]);
    try std.testing.expectEqual(@as(i16, -128 * 256), pool[1]);
    try std.testing.expectEqual(@as(u32, 10), machine.audio_samples[1].length);
    try machine.interpretLine("2 8 1 LOOP-SAMPLE");
    try std.testing.expect(machine.audio_samples[1].loops());
    for ([_][]const u8{ "5 4 1 LOOP-SAMPLE", "0 11 1 LOOP-SAMPLE", "S 10 999 1 SAMPLE", "S 10 8000 64 SAMPLE", "64 SAMPLE-INSTRUMENT", "-2 SAMPLE-INSTRUMENT", "64 SFX" }) |line| {
        try std.testing.expectError(error.InvalidNumber, machine.interpretLine(line));
        machine.data_depth = 0;
    }
    try std.testing.expectError(error.MemoryExhausted, machine.interpretLine("S 60 8000 2 SAMPLE"));
    machine.data_depth = 0;

    try machine.interpretLine("3 INSTRUMENT 1 SAMPLE-INSTRUMENT");
    try std.testing.expectEqual(@as(?u8, 1), machine.audio_instruments[3].sample);
    try std.testing.expectEqual(sound_engine.voice.Wave.sample, machine.audio_instruments[3].wave);
    try machine.interpretLine("-1 SAMPLE-INSTRUMENT");
    try std.testing.expectEqual(@as(?u8, null), machine.audio_instruments[3].sample);
    try std.testing.expectEqual(sound_engine.voice.Wave.square, machine.audio_instruments[3].wave);

    try machine.interpretLine("1 SFX");
    render(&engine, 1);
    try std.testing.expect(engine.bank.voices[sound_engine.sfx_first].active);

    try machine.interpretLine("FREE-SAMPLES");
    try std.testing.expectEqual(@as(u32, 0), machine.audio_pool_used);
    try std.testing.expectEqual(@as(u32, 0), machine.audio_samples[1].length);
    try std.testing.expect(!engine.bank.voices[sound_engine.sfx_first].active);
    render(&engine, 1);
    try std.testing.expectEqual(@as(u32, 0), engine.samples[1].length);
}

test "0 PLAYS stops queued and sounding MML while SFX and MOD continue" {
    try skipWithout(&.{ .audio, .files });
    var engine = newEngine();
    var pool: [8192]i16 = undefined;
    engine.pool = &pool;
    var output = Output{ .audio = &engine };
    support.setFakeFile(&output, 0, &modFile(1, &.{.{ 0, modCell(1, 428, 0, 0) }}));
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    try machine.interpretLine("REQUIRE-AUDIO ALSO AUDIO S\" a.txt\" LOAD-MOD TRUE PLAY-MOD");
    try machine.interpretLine("CREATE STOP-SAMPLE 2048 ALLOT STOP-SAMPLE 2048 64 FILL STOP-SAMPLE 2048 8000 1 SAMPLE");
    try machine.interpretLine("2 INSTRUMENT PULSE 25 DUTY S\" @2 T42 O3 V12 L8 C1 D1\" PLAY 1 SFX");
    render(&engine, 16);
    const sfx = &engine.bank.voices[sound_engine.sfx_first];
    try std.testing.expect(engine.isPlaying(0));
    try std.testing.expect(sfx.active);
    const position = sfx.position;
    const mod_tick = @as(u16, engine.mod.row) * 6 + engine.mod.tick;
    const voice = machine.audio_voices[0];
    const instrument = machine.audio_instruments[2];
    try machine.interpretLine("0 PLAYS 0 PLAY? MOD?");
    try expectStack(machine, &.{ 0, -1 });
    machine.data_depth = 0;
    try std.testing.expectEqualDeep(voice, machine.audio_voices[0]);
    try std.testing.expectEqualDeep(instrument, machine.audio_instruments[2]);
    try std.testing.expectEqual(@as(u8, 2), machine.audio_instrument);
    for (0..sound_engine.max_voices) |v| try std.testing.expectEqual(@as(u32, 0), queued(&engine, v));
    render(&engine, 2400);
    try std.testing.expect(!engine.isPlaying(0));
    try std.testing.expect(sfx.active);
    try std.testing.expect(sfx.position > position);
    try std.testing.expect(engine.mod.playing);
    try std.testing.expect(@as(u16, engine.mod.row) * 6 + engine.mod.tick > mod_tick);
    try std.testing.expectEqual(@as(u32, 2048), engine.samples[1].length);
    try machine.interpretLine("S\" @2 O5 C64\" PLAY");
    render(&engine, 1);
    try std.testing.expect(engine.isPlaying(0));
    try std.testing.expect(sfx.active);
    try machine.interpretLine("BEEP");
    try std.testing.expect(!sfx.active);
    try std.testing.expect(!engine.mod.playing);
}

// ---- S6: modules ----

const mod_module = @import("../core/sound_mod.zig");

/// Plays a frame at a time until the module is at row `row`, or has stopped; the frames.
fn playUntil(engine: *Engine, until: enum { row, stopped }, row: u8) usize {
    var frames: usize = 0;
    while (frames < rate * 10) : (frames += 1) {
        switch (until) {
            .row => if (engine.mod.row == row) return frames,
            .stopped => if (!engine.mod.playing) return frames,
        }
        render(engine, 1);
    }
    return frames;
}

/// One row's cell: sample, period, effect, and parameter.
fn modCell(sample: u8, period: u16, effect: u4, param: u8) [4]u8 {
    return .{ (sample & 0xf0) | @as(u8, @intCast(period >> 8)), @truncate(period), (sample << 4) | effect, param };
}

/// A module of one pattern played `positions` times, with one sample of 64 frames
/// (square, volume 48, finetune -1) and the rows given for channel 1.
fn modFile(comptime positions: u8, rows: []const struct { u8, [4]u8 }) [mod_module.header_size + mod_module.pattern_size + 64]u8 {
    var bytes: [mod_module.header_size + mod_module.pattern_size + 64]u8 = @splat(0);
    @memcpy(bytes[0..4], "test");
    const h = bytes[20..50];
    h[22] = 0;
    h[23] = 32; // 32 words
    h[24] = 0x0f; // finetune -1
    h[25] = 48;
    h[29] = 1; // no loop
    bytes[950] = positions;
    @memcpy(bytes[1080..1084], "M.K.");
    for (rows) |row| @memcpy(bytes[mod_module.header_size + @as(usize, row[0]) * 16 ..][0..4], &row[1]);
    for (0..64) |i| bytes[mod_module.header_size + mod_module.pattern_size + i] = if (i % 8 < 4) 100 else 156;
    return bytes;
}

test "a MOD header: the tags of four channels, the samples, and the song" {
    var file = modFile(3, &.{});
    const song = try mod_module.parseHeader(file[0..mod_module.header_size]);
    try std.testing.expectEqual(@as(u8, 3), song.length);
    try std.testing.expectEqual(@as(u8, 1), song.pattern_count);
    try std.testing.expectEqual(@as(u32, 64), song.samples[0].length);
    try std.testing.expectEqual(@as(i8, -1), song.samples[0].finetune);
    try std.testing.expectEqual(@as(u8, 48), song.samples[0].volume);
    try std.testing.expectEqual(@as(u32, 0), song.samples[0].loop_length);
    // A loop of 8 words from word 4; the order's highest pattern sets the count.
    file[20 + 27] = 4;
    file[20 + 29] = 8;
    file[952 + 1] = 2;
    const looped = try mod_module.parseHeader(file[0..mod_module.header_size]);
    try std.testing.expectEqual(@as(u32, 8), looped.samples[0].loop_start);
    try std.testing.expectEqual(@as(u32, 16), looped.samples[0].loop_length);
    try std.testing.expectEqual(@as(u8, 3), looped.pattern_count);
    // The entries past the song's length count too: the file keeps the patterns up to
    // the highest number in all 128 (Codex's review R02, not taken, 2026-11-07).
    var unused = modFile(1, &.{});
    unused[952 + 100] = 4;
    try std.testing.expectEqual(@as(u8, 5), (try mod_module.parseHeader(unused[0..mod_module.header_size])).pattern_count);
    for ([_]*const [4]u8{ "M!K!", "FLT4", "4CHN" }) |tag| {
        @memcpy(file[1080..1084], tag);
        _ = try mod_module.parseHeader(file[0..mod_module.header_size]);
    }
    @memcpy(file[1080..1084], "8CHN");
    try std.testing.expectError(error.InvalidMod, mod_module.parseHeader(file[0..mod_module.header_size]));
    @memcpy(file[1080..1084], "M.K.");
    file[950] = 0;
    try std.testing.expectError(error.InvalidMod, mod_module.parseHeader(file[0..mod_module.header_size]));
}

test "LOAD-MOD and PLAY-MOD: a row lasts its speed's ticks, a pattern break ends the song" {
    try skipWithout(&.{ .audio, .files });
    var engine = newEngine();
    var pool: [4096]i16 = undefined;
    engine.pool = &pool;
    var output = Output{ .audio = &engine };
    // Row 0: C-2 (period 428) with sample 1; row 1: a pattern break to the next
    // position, which is past the song's end.
    support.setFakeFile(&output, 0, &modFile(1, &.{ .{ 0, modCell(1, 428, 0, 0) }, .{ 1, modCell(0, 0, 0xd, 0) } }));
    support.setFakeFile(&output, 1, "not a module");
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    try machine.interpretLine("REQUIRE-AUDIO ALSO AUDIO S\" a.txt\" LOAD-MOD MOD?");
    try expectStack(machine, &.{0});
    machine.data_depth = 0;
    render(&engine, 1);
    try std.testing.expectEqual(@as(u8, 1), engine.mod.song.length);
    const waits = output.audio_waits;
    try machine.interpretLine("FALSE PLAY-MOD MOD?");
    try expectStack(machine, &.{-1});
    machine.data_depth = 0;
    render(&engine, 1);
    const channel = engine.mod.channels[0];
    // Finetune -1 makes the period a little longer than 428.
    try std.testing.expectEqual(@as(u16, 431), channel.period);
    try std.testing.expectEqual(@as(i32, 48), channel.volume);
    try std.testing.expectApproxEqAbs(@as(f64, 3546895.0 / 431.0 / 48000.0), channel.player.step, 1e-9);
    // Two rows of 6 ticks at 50 a second: 240 ms (the fake host's waits in PLAY-MOD
    // played some of them already); then it has stopped.
    const played = (output.audio_waits - waits) * output.audio_wait_samples + 1 + playUntil(&engine, .stopped, 0);
    try std.testing.expectApproxEqAbs(@as(f64, rate * 240 / 1000), @as(f64, @floatFromInt(played)), 2);
    try machine.interpretLine("MOD?");
    try expectStack(machine, &.{0});
    machine.data_depth = 0;

    // Played again and again, it does not stop; STOP-MOD stops it.
    try machine.interpretLine("TRUE PLAY-MOD");
    render(&engine, rate);
    try std.testing.expect(engine.mod.playing);
    try machine.interpretLine("STOP-MOD");
    render(&engine, 1);
    try std.testing.expect(!engine.mod.playing);

    try std.testing.expectError(error.ModInvalid, machine.interpretLine("S\" b.txt\" LOAD-MOD"));
    machine.data_depth = 0;
    try machine.interpretLine("S\" missing.txt\" SND-LOAD-MOD 0<>");
    try expectStack(machine, &.{-1});
}

test "the module's effects: set volume, volume slide, speed, and portamento" {
    try skipWithout(&.{ .audio, .files });
    var engine = newEngine();
    var pool: [4096]i16 = undefined;
    engine.pool = &pool;
    var output = Output{ .audio = &engine };
    support.setFakeFile(&output, 0, &modFile(1, &.{
        .{ 0, modCell(1, 428, 0xf, 3) }, // speed 3: a row is 60 ms
        .{ 1, modCell(0, 0, 0xc, 20) }, // volume 20
        .{ 2, modCell(0, 0, 0xa, 0x20) }, // up 2 a tick after the first: 24
        .{ 3, modCell(0, 0, 0x2, 4) }, // the period down by 4 a tick after the first
        .{ 4, modCell(0, 0, 0xd, 0) },
    }));
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    try machine.interpretLine("REQUIRE-AUDIO ALSO AUDIO S\" a.txt\" LOAD-MOD");
    const waits = output.audio_waits;
    try machine.interpretLine("FALSE PLAY-MOD");
    var played = (output.audio_waits - waits) * output.audio_wait_samples;
    // When each row has started, the one before has had all its ticks.
    played += playUntil(&engine, .row, 2);
    try std.testing.expectEqual(@as(i32, 20), engine.mod.channels[0].volume);
    played += playUntil(&engine, .row, 3);
    try std.testing.expectEqual(@as(i32, 24), engine.mod.channels[0].volume);
    played += playUntil(&engine, .row, 4);
    try std.testing.expectEqual(@as(u16, 431 + 8), engine.mod.channels[0].period);
    // Five rows of 3 ticks: 300 ms.
    played += playUntil(&engine, .stopped, 0);
    try std.testing.expectApproxEqAbs(@as(f64, rate * 300 / 1000), @as(f64, @floatFromInt(played)), 2);

    // FREE-SAMPLES forgets the module.
    try machine.interpretLine("FREE-SAMPLES TRUE PLAY-MOD MOD?");
    try expectStack(machine, &.{0});
}

test "the module's pattern loop plays its rows again, and a note delay starts the note late" {
    try skipWithout(&.{ .audio, .files });
    var engine = newEngine();
    var pool: [4096]i16 = undefined;
    engine.pool = &pool;
    var output = Output{ .audio = &engine };
    // Rows 0 and 1 three times (E60, then E62), then row 2 ends the song: 7 rows of
    // 6 ticks, 840 ms. Row 2 also starts its note on its third tick (ED2).
    support.setFakeFile(&output, 0, &modFile(1, &.{
        .{ 0, modCell(1, 428, 0xe, 0x60) },
        .{ 1, modCell(0, 0, 0xe, 0x62) },
        .{ 2, modCell(1, 214, 0xe, 0xd2) },
        .{ 3, modCell(0, 0, 0xd, 0) },
    }));
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    try machine.interpretLine("REQUIRE-AUDIO ALSO AUDIO S\" a.txt\" LOAD-MOD");
    const waits = output.audio_waits;
    try machine.interpretLine("FALSE PLAY-MOD");
    var played = (output.audio_waits - waits) * output.audio_wait_samples;
    played += playUntil(&engine, .row, 2);
    // Six rows have played: three times rows 0 and 1.
    try std.testing.expectApproxEqAbs(@as(f64, rate * 720 / 1000), @as(f64, @floatFromInt(played)), 2);
    // The delayed note has not started on the row's first tick.
    render(&engine, rate / 50);
    try std.testing.expectEqual(@as(u16, 431), engine.mod.channels[0].period);
    // 214 with finetune -1: 215.55, rounded.
    render(&engine, rate / 50 * 2);
    try std.testing.expectEqual(@as(u16, 216), engine.mod.channels[0].period);
    played += rate / 50 * 3 + playUntil(&engine, .stopped, 0);
    try std.testing.expectApproxEqAbs(@as(f64, rate * 960 / 1000), @as(f64, @floatFromInt(played)), 2);
}

/// A module played directly, a tick (20 ms at the first tempo) at a time. The effects
/// below were also compared with libopenmpt, tick by tick (2026-11-08).
const ModRun = struct {
    player: mod_module.Mod,
    pool: [4096]i16,
    led: bool,

    fn start(self: *ModRun, file: []const u8) !void {
        var song = try mod_module.parseHeader(file[0..mod_module.header_size]);
        self.pool = @splat(0);
        self.led = false;
        const pattern_slots = mod_module.pattern_size / 2;
        @memcpy(std.mem.sliceAsBytes(self.pool[0..pattern_slots]), file[mod_module.header_size..][0..mod_module.pattern_size]);
        song.patterns_at = 0;
        song.samples[0].start = pattern_slots;
        for (file[mod_module.header_size + mod_module.pattern_size ..], 0..) |byte, i| {
            self.pool[pattern_slots + i] = @as(i16, @as(i8, @bitCast(byte))) * 256;
        }
        self.player = mod_module.Mod.init(rate);
        self.player.song = song;
        self.player.start(false);
    }

    fn frames(self: *ModRun, count: usize) void {
        for (0..count) |_| _ = self.player.sample(&self.pool, &self.led);
    }

    fn ticks(self: *ModRun, count: usize) void {
        self.frames(count * rate / 50);
    }

    fn channel(self: *ModRun) *@TypeOf(self.player.channels[0]) {
        return &self.player.channels[0];
    }

    /// What 1 tick moves the sample by, at a period.
    fn tickSteps(period: f64) f64 {
        return 3546895.0 / period / rate * (rate / 50);
    }
};

fn expectOut(run: *ModRun, period: u16, volume: i32) !void {
    try std.testing.expectEqual(period, run.channel().out_period);
    try std.testing.expectEqual(volume, run.channel().out_volume);
}

/// Sample 2 of a test module: the first sample's frames, with a loop over the last 32.
fn addLoopedSample(run: *ModRun) void {
    const first = run.player.song.samples[0];
    run.player.song.samples[1] = .{ .start = first.start, .length = 64, .loop_start = 32, .loop_length = 32, .volume = 32 };
}

test "a sample number without a note starts the loop of a sample once the sound has ended" {
    var run: ModRun = undefined;
    try run.start(&modFile(1, &.{
        .{ 0, modCell(1, 428, 0, 0) },
        .{ 1, modCell(2, 0, 0, 0) },
    }));
    addLoopedSample(&run);
    run.ticks(6);
    try std.testing.expect(!run.channel().player.active); // sample 1 has ended
    run.ticks(1);
    try std.testing.expect(run.channel().player.active);
    try std.testing.expectEqual(@as(u32, 32), run.channel().player.sample.loop_start);
    try std.testing.expect(run.channel().player.position >= 32 and run.channel().player.position < 64);
    try expectOut(&run, 431, 32); // the old note's period, the new sample's volume
}

test "a sample number without a note starts nothing without a loop, before a note, or during a sound" {
    var run: ModRun = undefined;
    // The new sample has no loop: silence goes on.
    try run.start(&modFile(1, &.{
        .{ 0, modCell(1, 428, 0, 0) },
        .{ 1, modCell(1, 0, 0, 0) },
    }));
    run.ticks(7);
    try std.testing.expect(!run.channel().player.active);
    // No note has been played on the channel.
    try run.start(&modFile(1, &.{.{ 0, modCell(2, 0, 0, 0) }}));
    addLoopedSample(&run);
    run.ticks(2);
    try std.testing.expect(!run.channel().player.active);
}

test "a sample number without a note changes nothing of the sound in a module of Startrekker" {
    var run: ModRun = undefined;
    var file = modFile(1, &.{
        .{ 0, modCell(1, 428, 0, 0) },
        .{ 1, modCell(2, 0, 0, 0) },
        .{ 8, modCell(2, 428, 0, 0) },
        .{ 9, modCell(1, 0, 0, 0) },
    });
    @memcpy(file[1080..1084], "FLT4");
    try run.start(&file);
    addLoopedSample(&run);
    try std.testing.expect(run.player.song.startrekker);
    run.ticks(7);
    try std.testing.expect(!run.channel().player.active); // the ended sound stays silent
    run.ticks(6 * 7 + 6);
    try std.testing.expectEqual(@as(u32, 64), run.channel().player.sample.loop_end);
    try std.testing.expect(run.channel().player.active); // the loop goes on past the number
    try std.testing.expectEqual(@as(u8, 0), run.channel().swap);
}

test "a sample number without a note takes over when the sound goes round its loop or ends" {
    var run: ModRun = undefined;
    // A loop goes round: the new sample's loop follows, and not before that.
    try run.start(&modFile(1, &.{
        .{ 0, modCell(2, 428, 0, 0) },
        .{ 1, modCell(3, 0, 0, 0) },
    }));
    addLoopedSample(&run);
    run.player.song.samples[2] = .{ .start = run.player.song.samples[0].start, .length = 16, .loop_start = 8, .loop_length = 8, .volume = 20 };
    run.ticks(6);
    run.frames(1);
    try std.testing.expectEqual(@as(u32, 64), run.channel().player.sample.loop_end);
    try std.testing.expectEqual(@as(i32, 20), run.channel().out_volume); // the volume at once
    run.ticks(1);
    try std.testing.expect(run.channel().player.active);
    try std.testing.expectEqual(@as(u32, 16), run.channel().player.sample.loop_end);
    try std.testing.expect(run.channel().player.position >= 8 and run.channel().player.position < 16);
    try std.testing.expectEqual(@as(u8, 0), run.channel().swap);

    // A new sample without a loop: silence after the loop goes round.
    try run.start(&modFile(1, &.{
        .{ 0, modCell(2, 428, 0, 0) },
        .{ 1, modCell(1, 0, 0, 0) },
    }));
    addLoopedSample(&run);
    run.ticks(7);
    try std.testing.expect(!run.channel().player.active);

    // A sample without a loop plays to its end before the new loop.
    try run.start(&modFile(1, &.{
        .{ 0, modCell(3, 856, 0, 0) },
        .{ 1, modCell(2, 0, 0, 0) },
    }));
    addLoopedSample(&run);
    run.player.song.samples[2] = .{ .start = run.player.song.samples[0].start, .length = 600, .volume = 64 };
    run.ticks(7);
    try std.testing.expectEqual(@as(u32, 600), run.channel().player.sample.length);
    run.ticks(2);
    try std.testing.expect(run.channel().player.active);
    try std.testing.expectEqual(@as(u32, 32), run.channel().player.sample.loop_start);

    // A note before the end takes the place of what was waiting.
    try run.start(&modFile(1, &.{
        .{ 0, modCell(2, 428, 0, 0) },
        .{ 1, modCell(1, 0, 0, 0) },
        .{ 1, modCell(1, 428, 0, 0) },
    }));
    addLoopedSample(&run);
    run.ticks(7);
    try std.testing.expectEqual(@as(u8, 0), run.channel().swap);
}

test "the module's arpeggio changes the note on each tick, and comes back" {
    var run: ModRun = undefined;
    try run.start(&modFile(1, &.{.{ 0, modCell(1, 428, 0, 0x47) }}));
    run.ticks(1);
    try expectOut(&run, 431, 48);
    run.ticks(1);
    try expectOut(&run, 342, 48); // 4 semitones up
    try std.testing.expectApproxEqAbs(@as(f64, 3546895.0 / 342.0 / 48000.0), run.channel().player.step, 1e-9);
    run.ticks(1);
    try expectOut(&run, 288, 48); // 7 semitones up
    run.ticks(1);
    try expectOut(&run, 431, 48);
    // The note itself did not move.
    try std.testing.expectEqual(@as(u16, 431), run.channel().period);
}

test "the module's portamento stops at ProTracker's limits" {
    var run: ModRun = undefined;
    try run.start(&modFile(1, &.{.{ 0, modCell(1, 428, 1, 4) }}));
    run.ticks(6);
    try std.testing.expectEqual(@as(u16, 431 - 20), run.channel().period);

    try run.start(&modFile(1, &.{.{ 0, modCell(1, 135, 1, 0x10) }}));
    run.ticks(2);
    try std.testing.expectEqual(@as(u16, 120), run.channel().period);
    run.ticks(1);
    try std.testing.expectEqual(@as(u16, 113), run.channel().period);

    try run.start(&modFile(1, &.{.{ 0, modCell(1, 808, 2, 0x10) }}));
    run.ticks(3);
    try std.testing.expectEqual(@as(u16, 846), run.channel().period);
    run.ticks(1);
    try std.testing.expectEqual(@as(u16, 856), run.channel().period);
}

test "the module's tone portamento slides to the note, remembers its speed, and stops there" {
    var run: ModRun = undefined;
    try run.start(&modFile(1, &.{
        .{ 0, modCell(1, 428, 0, 0) },
        .{ 1, modCell(0, 339, 3, 8) },
        .{ 2, modCell(0, 0, 3, 0) },
        .{ 3, modCell(0, 0, 3, 0) },
    }));
    run.ticks(12);
    try std.testing.expectEqual(@as(u16, 431 - 40), run.channel().period);
    run.ticks(6);
    try std.testing.expectEqual(@as(u16, 431 - 80), run.channel().period);
    run.ticks(2);
    try std.testing.expectEqual(@as(u16, 343), run.channel().period);
    run.ticks(1);
    try std.testing.expectEqual(@as(u16, 341), run.channel().period);
    run.ticks(3);
    try std.testing.expectEqual(@as(u16, 341), run.channel().period);
}

test "the module's vibrato bends the note around it and keeps its place between rows" {
    var run: ModRun = undefined;
    try run.start(&modFile(1, &.{
        .{ 0, modCell(1, 428, 4, 0x48) },
        .{ 1, modCell(0, 0, 4, 0) },
        .{ 2, modCell(0, 0, 4, 0x83) },
    }));
    run.ticks(2);
    try expectOut(&run, 431, 48);
    run.ticks(1);
    try expectOut(&run, 437, 48);
    run.ticks(1);
    try expectOut(&run, 442, 48);
    run.ticks(2);
    try expectOut(&run, 446, 48);
    // The first tick of a row has no vibrato; the rest go on from where it was.
    run.ticks(1);
    try expectOut(&run, 431, 48);
    run.ticks(1);
    try expectOut(&run, 445, 48);
    // The second half of the wave, with the new speed and depth.
    run.ticks(6);
    try expectOut(&run, 427, 48);
    try std.testing.expectEqual(@as(u16, 431), run.channel().period);
}

test "the module's slides of the volume go on with portamento and vibrato" {
    var run: ModRun = undefined;
    try run.start(&modFile(1, &.{
        .{ 0, modCell(1, 428, 0, 0) },
        .{ 1, modCell(0, 339, 3, 4) },
        .{ 2, modCell(0, 0, 5, 0x04) },
        .{ 3, modCell(0, 0, 5, 0x20) },
    }));
    run.ticks(18);
    try std.testing.expectEqual(@as(u16, 431 - 40), run.channel().period);
    try std.testing.expectEqual(@as(i32, 48 - 20), run.channel().volume);
    run.ticks(6);
    try std.testing.expectEqual(@as(u16, 431 - 60), run.channel().period);
    try std.testing.expectEqual(@as(i32, 28 + 10), run.channel().volume);

    try run.start(&modFile(1, &.{
        .{ 0, modCell(1, 428, 4, 0x48) },
        .{ 1, modCell(0, 0, 6, 0x04) },
    }));
    run.ticks(8);
    try expectOut(&run, 445, 44);
}

test "the module's tremolo moves the volume it plays with, not the channel's" {
    var run: ModRun = undefined;
    try run.start(&modFile(1, &.{
        .{ 0, modCell(1, 428, 0xc, 32) },
        .{ 1, modCell(0, 0, 7, 0x48) },
    }));
    run.ticks(7);
    try expectOut(&run, 431, 32);
    run.ticks(1);
    try expectOut(&run, 431, 32);
    run.ticks(1);
    try expectOut(&run, 431, 32 + 12);
    run.ticks(1);
    try expectOut(&run, 431, 32 + 22);
    try std.testing.expectEqual(@as(i32, 32), run.channel().volume);
}

test "the module's sample offset starts later in the sample and remembers its place" {
    var run: ModRun = undefined;
    try run.start(&modFile(1, &.{
        .{ 0, modCell(1, 428, 9, 2) },
        .{ 1, modCell(0, 0, 0, 0) },
        .{ 2, modCell(1, 428, 9, 0) },
        .{ 3, modCell(1, 428, 0, 0) },
    }));
    run.player.song.samples[0].length = 1024;
    const tick = ModRun.tickSteps(431);
    run.ticks(1);
    try std.testing.expectApproxEqAbs(512 + tick, run.channel().player.position, 1);
    run.ticks(12);
    try std.testing.expectApproxEqAbs(512 + tick, run.channel().player.position, 1);
    run.ticks(6);
    try std.testing.expectApproxEqAbs(tick, run.channel().player.position, 1);

    // Past the end of a sample without a loop: no sound.
    try run.start(&modFile(1, &.{.{ 0, modCell(1, 428, 9, 1) }}));
    run.ticks(1);
    try std.testing.expect(!run.channel().player.active);
}

test "the module's fine slides work once, on the row's first tick" {
    var run: ModRun = undefined;
    try run.start(&modFile(1, &.{
        .{ 0, modCell(1, 428, 0xe, 0x14) },
        .{ 1, modCell(0, 0, 0xe, 0x24) },
        .{ 2, modCell(0, 0, 0xe, 0xa4) },
        .{ 3, modCell(0, 0, 0xe, 0xb8) },
    }));
    run.ticks(1);
    try std.testing.expectEqual(@as(u16, 427), run.channel().period);
    run.ticks(5);
    try std.testing.expectEqual(@as(u16, 427), run.channel().period);
    run.ticks(6);
    try std.testing.expectEqual(@as(u16, 431), run.channel().period);
    run.ticks(1);
    try std.testing.expectEqual(@as(i32, 52), run.channel().volume);
    run.ticks(5);
    try std.testing.expectEqual(@as(i32, 52), run.channel().volume);
    run.ticks(6);
    try std.testing.expectEqual(@as(i32, 44), run.channel().volume);
}

test "the module's note cut silences the note on its tick, and retrigger starts it again" {
    var run: ModRun = undefined;
    try run.start(&modFile(1, &.{.{ 0, modCell(1, 428, 0xe, 0xc2) }}));
    run.ticks(2);
    try std.testing.expectEqual(@as(i32, 48), run.channel().volume);
    run.ticks(1);
    try std.testing.expectEqual(@as(i32, 0), run.channel().volume);

    try run.start(&modFile(1, &.{.{ 0, modCell(1, 428, 0xe, 0x92) }}));
    run.player.song.samples[0].length = 1024;
    const tick = ModRun.tickSteps(431);
    run.ticks(2);
    try std.testing.expectApproxEqAbs(2 * tick, run.channel().player.position, 1);
    run.ticks(1);
    try std.testing.expectApproxEqAbs(tick, run.channel().player.position, 1);
}

test "the module's position jump, pattern break in decimal digits, delay, and tempo" {
    var run: ModRun = undefined;
    try run.start(&modFile(2, &.{.{ 0, modCell(1, 428, 0xb, 1) }}));
    run.ticks(6);
    try std.testing.expectEqual(@as(u8, 0), run.player.position);
    run.ticks(1);
    try std.testing.expectEqual(@as(u8, 1), run.player.position);
    try std.testing.expectEqual(@as(u8, 0), run.player.row);

    // A jump past the song's end ends it.
    try run.start(&modFile(1, &.{.{ 0, modCell(1, 428, 0xb, 5) }}));
    run.ticks(7);
    try std.testing.expect(!run.player.playing);

    // D12 is row 12, not 18.
    try run.start(&modFile(2, &.{.{ 0, modCell(1, 428, 0xd, 0x12) }}));
    run.ticks(7);
    try std.testing.expectEqual(@as(u8, 1), run.player.position);
    try std.testing.expectEqual(@as(u8, 12), run.player.row);

    // EE2: the row lasts three times as long.
    try run.start(&modFile(1, &.{.{ 0, modCell(1, 428, 0xe, 0xe2) }}));
    run.ticks(18);
    try std.testing.expectEqual(@as(u8, 0), run.player.row);
    run.ticks(1);
    try std.testing.expectEqual(@as(u8, 1), run.player.row);

    // Tempo 80 counts from the next tick: this one is still 960 frames, the next 1500.
    try run.start(&modFile(1, &.{.{ 0, modCell(1, 428, 0xf, 80) }}));
    run.frames(960);
    try std.testing.expectEqual(@as(u8, 1), run.player.tick);
    run.frames(1);
    try std.testing.expectEqual(@as(u8, 2), run.player.tick);
    run.frames(1499);
    try std.testing.expectEqual(@as(u8, 2), run.player.tick);
    run.frames(1);
    try std.testing.expectEqual(@as(u8, 3), run.player.tick);
}

test "the module played once ends where it would go round again, and goes on when repeating" {
    var run: ModRun = undefined;
    // Row 1 jumps back to the song's start.
    try run.start(&modFile(1, &.{
        .{ 0, modCell(1, 428, 0, 0) },
        .{ 1, modCell(0, 0, 0xb, 0) },
    }));
    run.ticks(12);
    try std.testing.expect(run.player.playing);
    run.ticks(1);
    try std.testing.expect(!run.player.playing);

    // Played again and again, it goes round.
    run.player.start(true);
    run.ticks(120);
    try std.testing.expect(run.player.playing);

    // A jump forward to a position not played goes on, and ends when it comes again.
    try run.start(&modFile(2, &.{.{ 0, modCell(1, 428, 0xb, 1) }}));
    run.ticks(12);
    try std.testing.expect(run.player.playing);
    try std.testing.expectEqual(@as(u8, 1), run.player.position);
    run.ticks(1);
    try std.testing.expect(!run.player.playing);

    // A break at the song's end to rows not played yet plays them, and the song ends
    // when it comes to a row it has played.
    try run.start(&modFile(1, &.{
        .{ 0, modCell(1, 428, 0, 0) },
        .{ 1, modCell(0, 0, 0xd, 0x02) },
        .{ 3, modCell(0, 0, 0xd, 0) },
    }));
    run.ticks(13);
    try std.testing.expect(run.player.playing);
    try std.testing.expectEqual(@as(u8, 0), run.player.position);
    try std.testing.expectEqual(@as(u8, 2), run.player.row);
    run.ticks(11);
    try std.testing.expect(run.player.playing);
    try std.testing.expectEqual(@as(u8, 3), run.player.row);
    run.ticks(1);
    try std.testing.expect(!run.player.playing);

    // A pattern loop plays its rows again without ending the song.
    try run.start(&modFile(1, &.{
        .{ 0, modCell(1, 428, 0xe, 0x60) },
        .{ 1, modCell(0, 0, 0xe, 0x61) },
        .{ 2, modCell(0, 0, 0xd, 0) },
    }));
    run.ticks(24);
    try std.testing.expect(run.player.playing);
    try std.testing.expectEqual(@as(u8, 1), run.player.row);
    run.ticks(1);
    try std.testing.expect(run.player.playing);
    try std.testing.expectEqual(@as(u8, 2), run.player.row);
}

test "the module's delayed note sounds at its own period on the tick it starts" {
    var run: ModRun = undefined;
    try run.start(&modFile(1, &.{
        .{ 0, modCell(1, 428, 0xe, 0xd2) },
        .{ 1, modCell(1, 339, 0xe, 0xd3) },
    }));
    run.ticks(2);
    try expectOut(&run, 0, 48);
    run.ticks(1);
    try expectOut(&run, 431, 48);
    try std.testing.expectApproxEqAbs(@as(f64, 3546895.0 / 431.0 / 48000.0), run.channel().player.step, 1e-9);
    // The next row's note keeps the old period until its tick 3.
    run.ticks(6);
    try expectOut(&run, 431, 48);
    run.ticks(1);
    try expectOut(&run, 341, 48);
    try std.testing.expectApproxEqAbs(@as(f64, 3546895.0 / 341.0 / 48000.0), run.channel().player.step, 1e-9);
}

test "the module's sample offset past the end of a sample with a loop plays the loop" {
    var run: ModRun = undefined;
    try run.start(&modFile(1, &.{.{ 0, modCell(1, 428, 9, 1) }}));
    run.player.song.samples[0].loop_start = 8;
    run.player.song.samples[0].loop_length = 16;
    run.ticks(1);
    try std.testing.expect(run.channel().player.active);
    try std.testing.expect(run.channel().player.position >= 8 and run.channel().player.position < 24);
}

test "the module's retrigger on a row without a note starts on the first tick too" {
    var run: ModRun = undefined;
    try run.start(&modFile(1, &.{
        .{ 0, modCell(1, 428, 0, 0) },
        .{ 1, modCell(0, 0, 0xe, 0x93) },
    }));
    run.player.song.samples[0].length = 1024;
    const tick = ModRun.tickSteps(431);
    run.ticks(6);
    try std.testing.expectApproxEqAbs(6 * tick, run.channel().player.position, 1);
    run.ticks(1);
    try std.testing.expectApproxEqAbs(tick, run.channel().player.position, 1);
    run.ticks(2);
    try std.testing.expectApproxEqAbs(3 * tick, run.channel().player.position, 1);
    run.ticks(1);
    try std.testing.expectApproxEqAbs(tick, run.channel().player.position, 1);
}

test "the module's tone portamento forgets a note it reached, but not one it did not" {
    var run: ModRun = undefined;
    try run.start(&modFile(1, &.{
        .{ 0, modCell(1, 428, 0, 0) },
        .{ 1, modCell(0, 339, 3, 0x40) },
        .{ 2, modCell(1, 428, 0, 0) },
        .{ 3, modCell(0, 0, 3, 8) },
    }));
    run.ticks(12);
    try std.testing.expectEqual(@as(u16, 341), run.channel().period);
    run.ticks(12);
    try std.testing.expectEqual(@as(u16, 431), run.channel().period);

    try run.start(&modFile(1, &.{
        .{ 0, modCell(1, 428, 0, 0) },
        .{ 1, modCell(0, 214, 3, 1) },
        .{ 2, modCell(1, 428, 0, 0) },
        .{ 3, modCell(0, 0, 3, 4) },
    }));
    run.ticks(24);
    try std.testing.expectEqual(@as(u16, 431 - 20), run.channel().period);
}

test "the module's position jump goes to row 0 after a pattern break on an earlier channel" {
    var run: ModRun = undefined;
    // Channel 1 breaks to row 3 and channel 2 jumps: row 0.
    var file = modFile(2, &.{.{ 0, modCell(1, 428, 0xd, 3) }});
    @memcpy(file[mod_module.header_size + 4 ..][0..4], &modCell(0, 0, 0xb, 1));
    try run.start(&file);
    run.ticks(7);
    try std.testing.expectEqual(@as(u8, 1), run.player.position);
    try std.testing.expectEqual(@as(u8, 0), run.player.row);

    // Channel 1 jumps and channel 2 breaks to row 3: row 3.
    file = modFile(2, &.{.{ 0, modCell(1, 428, 0xb, 1) }});
    @memcpy(file[mod_module.header_size + 4 ..][0..4], &modCell(0, 0, 0xd, 3));
    try run.start(&file);
    run.ticks(7);
    try std.testing.expectEqual(@as(u8, 1), run.player.position);
    try std.testing.expectEqual(@as(u8, 3), run.player.row);
}

test "the module's sample with a loop goes on, one without ends, and E0 sets the LED filter" {
    var run: ModRun = undefined;
    try run.start(&modFile(1, &.{.{ 0, modCell(1, 428, 0xe, 0x00) }}));
    run.ticks(30);
    try std.testing.expect(!run.channel().player.active);
    try std.testing.expect(run.led);

    try run.start(&modFile(1, &.{.{ 0, modCell(1, 428, 0xe, 0x01) }}));
    run.led = true;
    run.player.song.samples[0].loop_start = 8;
    run.player.song.samples[0].loop_length = 16;
    run.ticks(30);
    try std.testing.expect(run.channel().player.active);
    try std.testing.expect(run.channel().player.position >= 8 and run.channel().player.position < 24);
    try std.testing.expect(!run.led);
}

test "the steps of a chip and the global hooks through the words (tque 1190)" {
    try skipWithout(&.{.audio});
    const engine = try std.testing.allocator.create(Engine);
    defer std.testing.allocator.destroy(engine);
    engine.* = newEngine();
    var output = Output{ .audio = engine };
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    try machine.interpretLine("REQUIRE-AUDIO ALSO AUDIO 7 INSTRUMENT 1789773000 16 0 1 4095 PITCH-PERIOD");
    try machine.interpretLine("CREATE LV 0 , 1000 , 65535 ,  LV 3 VOLUME-STEPS 8 DUTY-STEPS 1 INTERPOLATION");
    var t = machine.audio_instruments[7];
    try std.testing.expectEqual(sound_engine.voice.PitchMode.period, t.pitch_mode);
    try std.testing.expectEqual(@as(u64, 1_789_773_000), t.pitch_clock);
    try std.testing.expectEqual(@as(u32, 16), t.pitch_divider);
    try std.testing.expectEqual(@as(u32, 4095), t.pitch_max);
    try std.testing.expectEqual(@as(u8, 3), t.volume_step_count);
    try std.testing.expectEqual(@as(u16, 1000), t.volume_steps[1]);
    try std.testing.expectEqual(@as(u16, 8), t.duty_steps);
    try std.testing.expectEqual(sound_engine.voice.Interpolation.linear, t.interpolation);
    // PITCH-STEP takes the place of PITCH-PERIOD; clock 0 turns the steps off.
    try machine.interpretLine("985248000 24 PITCH-STEP");
    t = machine.audio_instruments[7];
    try std.testing.expectEqual(sound_engine.voice.PitchMode.step, t.pitch_mode);
    try std.testing.expectEqual(@as(u8, 24), t.pitch_bits);
    render(engine, 1);
    try std.testing.expectEqualDeep(t, engine.instruments[7]);
    try machine.interpretLine("CREATE DOWN 1000 , 10 , ");
    for ([_][]const u8{ "-1 16 0 1 4095 PITCH-PERIOD", "1000 0 0 1 4095 PITCH-PERIOD", "1000 16 65537 1 4095 PITCH-PERIOD", "1000 16 0 10 9 PITCH-PERIOD", "1000000 1 0 0 4095 PITCH-PERIOD", "1000000000001 16 0 1 2 PITCH-PERIOD", "1000 0 PITCH-STEP", "1000 33 PITCH-STEP", "DOWN 2 VOLUME-STEPS", "LV 129 VOLUME-STEPS", "65536 DUTY-STEPS", "2 INTERPOLATION", "0 VOICE-LIMIT", "9 VOICE-LIMIT", "2 MIXER", "17 0 OUTPUT-BITS", "8 -1 OUTPUT-BITS" }) |line| {
        try std.testing.expectError(error.InvalidNumber, machine.interpretLine(line));
        machine.data_depth = 0;
    }
    try std.testing.expectEqualDeep(t, machine.audio_instruments[7]);
    try machine.interpretLine("0 0 0 0 0 PITCH-PERIOD");
    try std.testing.expectEqual(sound_engine.voice.PitchMode.none, machine.audio_instruments[7].pitch_mode);
    // The global hooks.
    try machine.interpretLine("1 MIXER 8 22050 OUTPUT-BITS 1 VOICE-LIMIT");
    render(engine, 1);
    try std.testing.expectEqual(sound_engine.voice.Mixer.nes, engine.bank.mixer);
    try std.testing.expectEqual(@as(u8, 8), engine.master.output_bits);
    try std.testing.expectEqual(@as(u32, 22050), engine.master.output_rate);
    // VOICE-LIMIT 1: PLAY's second voice stays silent.
    try machine.interpretLine("0 MIXER S\" C1\" S\" E1\" PLAY2");
    render(engine, 960);
    try machine.interpretLine("1 VOICE-ON? 2 VOICE-ON?");
    try expectStack(machine, &.{ -1, 0 });
    machine.data_depth = 0;
    try machine.interpretLine("8 VOICE-LIMIT 0 0 OUTPUT-BITS");
}

test "VOICE-HOLD with the same instrument takes its settings as they are now, and the envelope goes on" {
    try skipWithout(&.{.audio});
    const engine = try std.testing.allocator.create(Engine);
    defer std.testing.allocator.destroy(engine);
    engine.* = newEngine();
    var output = Output{ .audio = engine };
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    try machine.interpretLine("REQUIRE-AUDIO ALSO AUDIO 3 INSTRUMENT PULSE 32768 DUTY CREATE E 65535 , 0 , 0 , 0 , 1000 , 0 , E 2 -1 -1 ENVELOPE");
    try machine.interpretLine("3 440000 65535 2 VOICE-HOLD");
    render(engine, 4800);
    const v = &engine.bank.voices[1];
    const level = v.level;
    try std.testing.expect(level < 0.95 and level > 0.85);
    // The instrument changes while the note sounds: nothing of it reaches the voice
    // until VOICE-HOLD names it again.
    try machine.interpretLine("3 INSTRUMENT 8192 DUTY 1 2000 0 FILTER 0 0 -1 -1 ENVELOPE");
    render(engine, 1);
    try std.testing.expectEqual(@as(u16, 32768), v.tone.duty);
    try machine.interpretLine("3 440000 65535 2 VOICE-HOLD");
    render(engine, 1);
    try std.testing.expectEqual(@as(u16, 8192), v.tone.duty);
    try std.testing.expect(v.tone.filter == .low_pass);
    try std.testing.expectEqual(@as(u32, 2000), v.tone.filter_hz);
    // The envelope is the one the note started with, and it was not started again.
    try std.testing.expectEqual(@as(u8, 2), v.tone.envelope.count);
    try std.testing.expect(v.level < level and v.level > level - 0.01);
    // A filter that is already on keeps what it has heard when its cutoff changes.
    render(engine, 480);
    // (Emptied, it would be under 0.1 after one sample.)
    try std.testing.expect(@abs(v.ic1) + @abs(v.ic2) > 0.2);
    try machine.interpretLine("3 INSTRUMENT 1 3000 0 FILTER 3 440000 65535 2 VOICE-HOLD");
    render(engine, 1);
    try std.testing.expectEqual(@as(u32, 3000), v.tone.filter_hz);
    try std.testing.expect(@abs(v.ic1) + @abs(v.ic2) > 0.2);
    try machine.interpretLine("0 0 0 2 VOICE-HOLD");
}

test "VOICE-HOLD keeps a voice sounding, goes on at a new pitch and volume, and stops at 0" {
    try skipWithout(&.{.audio});
    const engine = try std.testing.allocator.create(Engine);
    defer std.testing.allocator.destroy(engine);
    engine.* = newEngine();
    var output = Output{ .audio = engine };
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    try machine.interpretLine("REQUIRE-AUDIO ALSO AUDIO 3 INSTRUMENT SAW CREATE E 65535 , 0 , 0 , 0 , 1000 , 0 , E 2 -1 -1 ENVELOPE");
    try machine.interpretLine("3 440000 65535 2 VOICE-HOLD");
    render(engine, 4800);
    const v = &engine.bank.voices[1];
    try std.testing.expect(v.active);
    try std.testing.expectApproxEqRel(@as(f32, 440), v.hz, 1e-6);
    // A tenth into the falling envelope; the same instrument does not start it again.
    const level = v.level;
    try std.testing.expect(level < 0.95 and level > 0.85);
    try machine.interpretLine("3 880000 32768 2 VOICE-HOLD");
    render(engine, 1);
    try std.testing.expectApproxEqRel(@as(f32, 880), v.hz, 1e-6);
    try std.testing.expectApproxEqRel(@as(f32, 32768.0 / 65535.0), v.volume, 1e-6);
    try std.testing.expect(v.level < level);
    // Another instrument starts anew: instrument 0 has no envelope, full level.
    try machine.interpretLine("0 880000 65535 2 VOICE-HOLD");
    render(engine, 1);
    try std.testing.expectEqual(@as(f32, 1), v.level);
    // A slide on the way gives way to the new pitch.
    try machine.interpretLine("4 INSTRUMENT 500 PORTAMENTO 4 440000 65535 2 VOICE-HOLD");
    render(engine, 480);
    try std.testing.expect(v.glide_left > 0);
    try machine.interpretLine("4 220000 65535 2 VOICE-HOLD");
    render(engine, 480);
    try std.testing.expectApproxEqRel(@as(f32, 220), v.hz, 1e-6);
    // A rest of PLAY on the voice ends the hold: the release goes on, and the same
    // instrument again starts a new note.
    try machine.interpretLine("5 INSTRUMENT 0 0 65535 1000 ADSR 5 440000 65535 1 VOICE-HOLD");
    render(engine, 480);
    try machine.interpretLine("S\" R\" PLAY");
    // The rest (half a second) ends; the release (a second) goes on.
    render(engine, 26000);
    try std.testing.expect(engine.bank.voices[0].active and !engine.bank.voices[0].gate);
    try std.testing.expectEqual(@as(?u8, null), engine.bank.voices[0].held_instrument);
    try machine.interpretLine("5 440000 65535 1 VOICE-HOLD");
    render(engine, 1);
    try std.testing.expect(engine.bank.voices[0].gate);
    try std.testing.expectEqual(@as(?u8, 5), engine.bank.voices[0].held_instrument);
    try machine.interpretLine("0 0 0 1 VOICE-HOLD");
    // Volume 0 silences it.
    try machine.interpretLine("0 0 0 2 VOICE-HOLD");
    render(engine, 1);
    try std.testing.expect(!v.active);
    // A note of PLAY takes the voice back from it.
    try machine.interpretLine("0 440000 65535 1 VOICE-HOLD");
    render(engine, 1);
    try std.testing.expectEqual(@as(?u8, 0), engine.bank.voices[0].held_instrument);
    try machine.interpretLine("S\" C\" PLAY");
    render(engine, 960);
    try std.testing.expectEqual(@as(?u8, null), engine.bank.voices[0].held_instrument);
    try machine.interpretLine("3 INSTRUMENT NOISE 111861000 NOISE-RATE");
    // V-STEPS: 16 levels or none.
    try machine.interpretLine("CREATE VS 0 , 100 , 200 , 300 , 400 , 500 , 600 , 700 , 800 , 900 , 1000 , 1100 , 1200 , 1300 , 1400 , 65535 , VS 16 V-STEPS");
    try std.testing.expectEqual(@as(u8, 16), machine.audio_instruments[3].v_step_count);
    try std.testing.expectEqual(@as(u16, 900), machine.audio_instruments[3].v_steps[9]);
    for ([_][]const u8{ "VS 15 V-STEPS", "VS 17 V-STEPS" }) |line| {
        try std.testing.expectError(error.InvalidNumber, machine.interpretLine(line));
        machine.data_depth = 0;
    }
    try machine.interpretLine("-1 VS 4 CELLS + ! ");
    try std.testing.expectError(error.InvalidNumber, machine.interpretLine("VS 16 V-STEPS"));
    machine.data_depth = 0;
    try machine.interpretLine("0 0 V-STEPS");
    try std.testing.expectEqual(@as(u8, 0), machine.audio_instruments[3].v_step_count);
    try std.testing.expectEqual(@as(u64, 111_861_000), machine.audio_instruments[3].noise_rate);
    for ([_][]const u8{ "0 440000 65535 0 VOICE-HOLD", "0 440000 65535 17 VOICE-HOLD", "64 440000 65535 1 VOICE-HOLD", "0 -1 65535 1 VOICE-HOLD", "0 1000000001 65535 1 VOICE-HOLD", "0 440000 65536 1 VOICE-HOLD", "-1 NOISE-RATE", "1000000001 NOISE-RATE" }) |line| {
        try std.testing.expectError(error.InvalidNumber, machine.interpretLine(line));
        machine.data_depth = 0;
    }
}

/// Loads the chip libraries of include/ (tque 1190) line by line, without their
/// REQUIRED lines (the files are loaded here in order instead).
fn loadChipLibraries(machine: *forth.State) !void {
    const files = [_][]const u8{ @embedFile("include/chip-sound.fs"), @embedFile("include/msx-sound.fs"), @embedFile("include/st-sound.fs"), @embedFile("include/nes-sound.fs"), @embedFile("include/c64-sound.fs"), @embedFile("include/scc-sound.fs"), @embedFile("include/amiga-sound.fs"), @embedFile("include/chips.fs") };
    for (files) |text| {
        var lines = std.mem.splitScalar(u8, text, '\n');
        while (lines.next()) |line| {
            if (std.mem.indexOf(u8, line, "REQUIRED") != null) continue;
            try machine.interpretLine(line);
        }
    }
}

/// V-STEPS of V / steps (V0 silent, V15 full) on the tone, all 16.
fn expectLinearV(tone: sound_engine.voice.Tone, steps: f64) !void {
    try std.testing.expectEqual(@as(u8, 16), tone.v_step_count);
    for (tone.v_steps, 0..) |level, n| try std.testing.expectEqual(@as(u16, @intFromFloat(@round(@as(f64, @floatFromInt(n)) * 65535.0 / steps))), level);
}

test "the chip libraries set the steps and the global hooks (tque 1190)" {
    try skipWithout(&.{.audio});
    const engine = try std.testing.allocator.create(Engine);
    defer std.testing.allocator.destroy(engine);
    engine.* = newEngine();
    var output = Output{ .audio = engine };
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    var pool: [256]i16 = undefined;
    engine.pool = &pool;
    try loadChipLibraries(machine);
    try machine.interpretLine("ALSO AUDIO MSX-SOUND");
    render(engine, 1);
    try std.testing.expectEqual(@as(u8, 3), engine.voice_limit);
    for ([_]usize{ 0, 63 }) |i| {
        const t = engine.instruments[i];
        try std.testing.expectEqual(sound_engine.voice.PitchMode.period, t.pitch_mode);
        try std.testing.expectEqual(@as(u64, 1_789_773_000), t.pitch_clock);
        try std.testing.expectEqual(@as(u8, 16), t.volume_step_count);
        try std.testing.expectEqual(@as(u16, 65535), t.volume_steps[15]);
        try std.testing.expectEqual(@as(u8, 17), t.noise_bits);
        // MML's V is the AY's level.
        try std.testing.expectEqual(@as(u8, 16), t.v_step_count);
        try std.testing.expectEqual(t.volume_steps[12], t.v_steps[12]);
    }
    // V12 on MSX-SOUND sounds at the AY's level 12, not 9 dB down.
    try machine.interpretLine("S\" V12 O4 A\" PLAY");
    render(engine, 960);
    try std.testing.expectApproxEqRel(@as(f32, (1.882 - 1.147) / (2.58 - 1.147)), engine.bank.voices[0].volume, 1e-4);
    try machine.interpretLine("ST-SOUND");
    render(engine, 1);
    try std.testing.expectEqual(@as(u8, 32), engine.instruments[9].volume_step_count);
    // V n is the YM's step 2n + 1, V0 silent.
    try std.testing.expectEqual(@as(u16, 0), engine.instruments[9].v_steps[0]);
    for (1..16) |n| try std.testing.expectEqual(engine.instruments[9].volume_steps[2 * n + 1], engine.instruments[9].v_steps[n]);
    try std.testing.expectEqual(@as(u64, 2_000_000_000), engine.instruments[9].pitch_clock);
    try machine.interpretLine("NES-SOUND 1 INSTRUMENT NES-TRIANGLE 2 INSTRUMENT NES-NOISE");
    render(engine, 1);
    try std.testing.expectEqual(sound_engine.voice.Mixer.nes, engine.bank.mixer);
    try std.testing.expectEqual(@as(u8, 4), engine.voice_limit);
    try std.testing.expectEqual(@as(u16, 8), engine.instruments[0].duty_steps);
    try expectLinearV(engine.instruments[0], 15);
    try std.testing.expectEqual(sound_engine.voice.Wave.wavetable, engine.instruments[1].wave);
    try std.testing.expectEqual(@as(u32, 32), engine.instruments[1].pitch_divider);
    try std.testing.expectEqual(@as(u8, 1), engine.instruments[1].volume_step_count);
    try std.testing.expectEqual(sound_engine.voice.Wave.noise, engine.instruments[2].wave);
    try std.testing.expectEqual(@as(u32, 4068), engine.instruments[2].pitch_max);
    try machine.interpretLine("C64-SOUND");
    render(engine, 1);
    try std.testing.expectEqual(sound_engine.voice.PitchMode.step, engine.instruments[0].pitch_mode);
    try std.testing.expectEqual(sound_engine.voice.Mixer.linear, engine.bank.mixer);
    try std.testing.expectEqual(@as(u16, 4096), engine.instruments[0].duty_steps);
    try expectLinearV(engine.instruments[0], 15);
    try machine.interpretLine("SCC-SOUND CREATE W 32 ALLOT W 32 0 FILL 127 W C! 128 W 1+ C! W 4 SCC-WAVE");
    render(engine, 1);
    try std.testing.expectEqual(@as(u8, 5), engine.voice_limit);
    const wave = engine.instruments[4].table;
    try std.testing.expectEqual(@as(u32, 32), wave.length);
    try std.testing.expectEqual(@as(i16, 127 * 256), engine.pool[wave.start]);
    try std.testing.expectEqual(@as(i16, -128 * 256), engine.pool[wave.start + 1]);
    try std.testing.expectEqual(@as(u32, 1), engine.instruments[4].pitch_offset);
    try expectLinearV(engine.instruments[4], 15);
    try machine.interpretLine("AMIGA-SOUND");
    render(engine, 1);
    try std.testing.expectEqual(@import("../core/sound_master.zig").FilterMode.low_pass, engine.master.filter);
    try std.testing.expectEqual(@as(u8, 65), engine.instruments[0].volume_step_count);
    try std.testing.expectEqual(@as(u32, 3275), engine.mod_filter_hz);
    // Paula's V x 64 / 15, rounded, out of 64.
    for (engine.instruments[0].v_steps, 0..) |level, n| {
        const paula = @round(@as(f64, @floatFromInt(n)) * 64.0 / 15.0);
        try std.testing.expectEqual(@as(u16, @intFromFloat(@round(paula * 65535.0 / 64.0))), level);
    }
    try machine.interpretLine("5 INSTRUMENT NES STYLE 6 INSTRUMENT C64 STYLE");
    render(engine, 1);
    try std.testing.expectEqual(@as(u32, 16), engine.instruments[5].pitch_divider);
    try std.testing.expectEqual(sound_engine.voice.PitchMode.step, engine.instruments[6].pitch_mode);
    try std.testing.expectError(error.InvalidNumber, machine.interpretLine("3 STYLE"));
    machine.data_depth = 0;
    try machine.interpretLine("STANDARD-SOUND");
    render(engine, 1);
    try std.testing.expectEqual(@as(u8, 8), engine.voice_limit);
    try std.testing.expectEqual(@import("../core/sound_master.zig").FilterMode.none, engine.master.filter);
    for (engine.instruments) |t| {
        try std.testing.expectEqual(sound_engine.voice.PitchMode.none, t.pitch_mode);
        try std.testing.expectEqual(@as(u8, 0), t.volume_step_count);
        try std.testing.expectEqual(@as(u8, 0), t.v_step_count);
    }
}

test "SOUND writes the PSG's registers onto voices 1 to 3 (tque 1190)" {
    try skipWithout(&.{.audio});
    const engine = try std.testing.allocator.create(Engine);
    defer std.testing.allocator.destroy(engine);
    engine.* = newEngine();
    var output = Output{ .audio = engine };
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    try loadChipLibraries(machine);
    // Voice 1's tone at period 254, full volume.
    try machine.interpretLine("ALSO AUDIO 7 62 SOUND 0 254 SOUND 1 0 SOUND 8 15 SOUND");
    render(engine, 1);
    const v = &engine.bank.voices[0];
    try std.testing.expect(v.active and !engine.bank.voices[1].active);
    try std.testing.expectApproxEqRel(@as(f32, 1789773.0 / (16.0 * 254.0)), v.hz, 1e-5);
    try std.testing.expectEqual(@as(f32, 1), v.volume);
    try std.testing.expectEqual(sound_engine.voice.Wave.square, v.tone.wave);
    // A softer level: the AY's level 10, and the note goes on (no new start).
    v.phase = 0.25;
    try machine.interpretLine("8 10 SOUND");
    render(engine, 1);
    try std.testing.expectApproxEqRel(@as(f32, (1.573 - 1.147) / (2.58 - 1.147)), v.volume, 1e-4);
    try std.testing.expect(v.phase > 0.25);
    // The noise alone on voice 1, at clock / (16 x 10) shifts a second.
    try machine.interpretLine("6 10 SOUND 7 55 SOUND");
    render(engine, 1);
    try std.testing.expectEqual(sound_engine.voice.Wave.noise, v.tone.wave);
    try std.testing.expectEqual(@as(u64, 1_789_773_000 / 160), v.tone.noise_rate);
    try std.testing.expectEqual(@as(u8, 17), v.tone.noise_bits);
    // Tone and noise: gated.
    try machine.interpretLine("7 54 SOUND");
    render(engine, 1);
    try std.testing.expectEqual(sound_engine.voice.NoiseMix.gate, v.tone.noise_mix);
    // The envelope: shape 0 with period 2560, one fall of 256 x 2560 / 1789773 s.
    try machine.interpretLine("7 62 SOUND 11 0 SOUND 12 10 SOUND 13 0 SOUND 8 16 SOUND");
    render(engine, 1);
    try std.testing.expectEqual(@as(u8, 2), v.tone.envelope.count);
    try std.testing.expectEqual(@as(u32, 366), v.tone.envelope.segments[1].ms);
    try std.testing.expectEqual(@as(f32, 1), v.volume);
    // Writing R13 again starts the envelope anew.
    render(engine, 4800);
    const fallen = v.level;
    try machine.interpretLine("13 0 SOUND");
    render(engine, 1);
    try std.testing.expect(v.level > fallen);
    // A fall that has ended stays ended when another register is written.
    render(engine, 48000);
    try std.testing.expectEqual(@as(f32, 0), v.level);
    try machine.interpretLine("0 200 SOUND");
    render(engine, 1);
    try std.testing.expectEqual(@as(f32, 0), v.level);
    // The tone and the noise both off: the envelope alone, on a square at 0 Hz.
    try machine.interpretLine("7 63 SOUND 13 14 SOUND");
    render(engine, 1);
    try std.testing.expect(v.active);
    try std.testing.expectEqual(@as(f32, 0), v.hz);
    try std.testing.expectEqual(@as(u8, 2), v.tone.envelope.count);
    // Volume 0 silences the voice; the registers are checked.
    try machine.interpretLine("8 0 SOUND");
    render(engine, 1);
    try std.testing.expect(!v.active);
    // Instrument 61 changed while the voice was silent is set again.
    try machine.interpretLine("61 INSTRUMENT SAW 7 62 SOUND 8 15 SOUND");
    render(engine, 1);
    try std.testing.expectEqual(sound_engine.voice.Wave.square, v.tone.wave);
    try std.testing.expectEqual(@as(u8, 0), v.tone.envelope.count);
    try machine.interpretLine("8 0 SOUND");
    for ([_][]const u8{ "14 0 SOUND", "-1 0 SOUND", "0 256 SOUND", "0 -1 SOUND" }) |line| {
        try std.testing.expectError(error.InvalidNumber, machine.interpretLine(line));
        machine.data_depth = 0;
    }
}
