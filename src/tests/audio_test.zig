//! Tests of REQUIRE-AUDIO and the audio words, with the fake host's sound engine: the
//! host's waits play what the audio thread would play meanwhile.

const std = @import("std");
const forth = @import("../forth.zig");
const defs = @import("../core/defs.zig");
const memory_map = @import("../core/memory_map.zig");
const mml = @import("../core/sound_mml.zig");
const psg_module = @import("../core/sound_psg.zig");
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
    return Engine.init(.ay8910, psg_module.msx_clock, rate);
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
    const image = try std.testing.allocator.alloc(u8, forth.State.imageCapacity());
    errdefer std.testing.allocator.free(image);
    const length = try machine.encodeImage(image);
    return image[0..length];
}

fn freeImage(image: []u8) void {
    std.testing.allocator.free(image.ptr[0..forth.State.imageCapacity()]);
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

test "a dictionary that has had the audio words is saved as SIGIMG35, which LOAD reads" {
    try skipWithout(&.{ .audio, .image });
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    const plain = try saveImage(machine);
    defer freeImage(plain);
    try std.testing.expectEqualStrings("SIGIMG33", plain[0..8]);

    try machine.interpretLine("REQUIRE-AUDIO ALSO AUDIO DEFINITIONS : TUNE S\" CDE\" PLAY ; FORTH DEFINITIONS PREVIOUS");
    const image = try saveImage(machine);
    defer freeImage(image);
    try std.testing.expectEqualStrings("SIGIMG35", image[0..8]);

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
    try std.testing.expectEqualStrings("SIGIMG35", appended[0..8]);
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

    try std.testing.expectError(error.InvalidNumber, machine.interpretLine("4 PLAY?"));
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

test "SOUND writes a PSG register at the audio thread's next turn, within MSX BASIC's ranges" {
    try skipWithout(&.{.audio});
    var engine = newEngine();
    var output = Output{ .audio = &engine };
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    try machine.interpretLine("REQUIRE-AUDIO ALSO AUDIO");
    try machine.interpretLine("0 100 SOUND 8 15 SOUND");
    try std.testing.expectEqual(@as(u8, 0x55), engine.psg.read(0));
    render(&engine, 1);
    try std.testing.expectEqual(@as(u8, 100), engine.psg.read(0));
    try std.testing.expectEqual(@as(u8, 15), engine.psg.read(8));
    try std.testing.expectError(error.InvalidNumber, machine.interpretLine("14 0 SOUND"));
    machine.data_depth = 0;
    try std.testing.expectError(error.InvalidNumber, machine.interpretLine("0 256 SOUND"));
    machine.data_depth = 0;
    try std.testing.expectError(error.InvalidNumber, machine.interpretLine("-1 0 SOUND"));
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
    try std.testing.expectEqual(@as(u8, sound_engine.beep_period), engine.psg.read(0));
    try std.testing.expectEqual(sound_engine.beep_volume, engine.psg.read(8));
    render(&engine, rate / 10);
    try std.testing.expectEqual(@as(u8, 0), engine.psg.read(8));
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

test "NES-SOUND, ST-SOUND, and MSX-SOUND choose the chip, which sets how many voices PLAYS and PLAY? take" {
    try skipWithout(&.{.audio});
    var engine = newEngine();
    var output = Output{ .audio = &engine };
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    try machine.interpretLine("REQUIRE-AUDIO ALSO AUDIO");
    try std.testing.expectError(error.InvalidNumber, machine.interpretLine("S\" C\" S\" D\" S\" E\" S\" F\" 4 PLAYS"));
    machine.data_depth = 0;
    try std.testing.expectError(error.InvalidNumber, machine.interpretLine("4 PLAY?"));
    machine.data_depth = 0;

    // The chip changes at once: the audio thread has taken the command when it returns.
    try machine.interpretLine("S\" O2 CDEFG\" PLAY NES-SOUND");
    try std.testing.expectEqual(sound_engine.Chip.nes, engine.chip);
    try machine.interpretLine("0 PLAY?");
    try expectStack(machine, &.{0});
    machine.data_depth = 0;
    try machine.interpretLine("S\" C\" S\" E\" S\" G\" S\" C\" 4 PLAYS 4 PLAY?");
    try expectStack(machine, &.{-1});
    machine.data_depth = 0;
    try std.testing.expectEqual(@as(u32, 2), queued(&engine, 3));
    try std.testing.expectEqual(@as(u32, 1), queued(&engine, 4));
    try std.testing.expectError(error.InvalidNumber, machine.interpretLine("S\" C\" S\" C\" S\" C\" S\" C\" S\" C\" 5 PLAYS"));
    machine.data_depth = 0;
    try std.testing.expectError(error.InvalidNumber, machine.interpretLine("0 PLAYS"));
    machine.data_depth = 0;

    try machine.interpretLine("ST-SOUND");
    try std.testing.expectEqual(sound_engine.Chip.atari_st, engine.chip);
    try machine.interpretLine("MSX-SOUND");
    try std.testing.expectEqual(sound_engine.Chip.msx, engine.chip);
    try std.testing.expectError(error.InvalidNumber, machine.interpretLine("9 SND-CHIP"));
}

test "INSTRUMENT and the words after it change an instrument here and for the audio thread" {
    try skipWithout(&.{.audio});
    var engine = newEngine();
    var output = Output{ .audio = &engine };
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    try machine.interpretLine("REQUIRE-AUDIO ALSO AUDIO");
    try machine.interpretLine("7 INSTRUMENT PULSE 25 DUTY 1 2 10 3 ADSR");
    const expected: sound_engine.Instrument = .{ .wave = .pulse, .duty = 25, .attack = 1, .decay = 2, .sustain = 10, .release = 3 };
    try std.testing.expectEqual(expected, machine.audio_instruments[7]);
    render(&engine, 1);
    try std.testing.expectEqual(expected, engine.instruments[7]);
    try std.testing.expectEqual(sound_engine.Instrument{}, engine.instruments[0]);
    try machine.interpretLine("SQUARE TRIANGLE SAW NOISE");
    try std.testing.expectEqual(@import("../core/sound_parts.zig").Wave.noise, machine.audio_instruments[7].wave);

    // The ranges.
    for ([_][]const u8{ "64 INSTRUMENT", "-1 INSTRUMENT", "101 DUTY", "16 0 0 0 ADSR", "0 0 0 -1 ADSR", "5 SND-WAVE" }) |line| {
        try std.testing.expectError(error.InvalidNumber, machine.interpretLine(line));
        machine.data_depth = 0;
    }
    // BEEP keeps the instruments and the chip.
    try machine.interpretLine("NES-SOUND BEEP");
    try std.testing.expectEqual(sound_engine.Chip.nes, engine.chip);
    try std.testing.expectEqual(expected.duty, machine.audio_instruments[7].duty);
}

test "C64-SOUND, RING, SYNC, and FILTER" {
    try skipWithout(&.{.audio});
    var engine = newEngine();
    var output = Output{ .audio = &engine };
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    try machine.interpretLine("REQUIRE-AUDIO ALSO AUDIO C64-SOUND");
    try std.testing.expectEqual(sound_engine.Chip.c64, engine.chip);
    try std.testing.expectError(error.InvalidNumber, machine.interpretLine("S\" C\" S\" C\" S\" C\" S\" C\" 4 PLAYS"));
    machine.data_depth = 0;
    try machine.interpretLine("4 INSTRUMENT TRIANGLE TRUE RING TRUE SYNC 2 1500 12 FILTER");
    const instrument = machine.audio_instruments[4];
    try std.testing.expect(instrument.ring and instrument.sync);
    try std.testing.expectEqual(@as(u8, 2), instrument.filter);
    try std.testing.expectEqual(@as(u16, 1500), instrument.cutoff);
    try std.testing.expectEqual(@as(u8, 12), instrument.resonance);
    render(&engine, 1);
    try std.testing.expectEqual(instrument, engine.instruments[4]);
    try machine.interpretLine("FALSE RING 0 0 0 FILTER");
    try std.testing.expect(!machine.audio_instruments[4].ring);
    try std.testing.expectEqual(@as(u8, 0), machine.audio_instruments[4].filter);
    for ([_][]const u8{ "4 0 0 FILTER", "1 2048 0 FILTER", "1 0 16 FILTER", "-1 0 0 FILTER" }) |line| {
        try std.testing.expectError(error.InvalidNumber, machine.interpretLine(line));
        machine.data_depth = 0;
    }
}
