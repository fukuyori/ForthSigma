//! The audio words: REQUIRE-AUDIO, which loads them, and the SND- words, which give MSX
//! BASIC's PLAY, SOUND, and BEEP to the AUDIO library (src/audio/audio.fs).
//!
//! As with the graphics words, a dictionary that never loads them keeps the numbers of
//! its words, and its images keep their format. The notes go to the sound engine of the
//! host's audio thread (sound_engine.zig) through one-way queues; this file is the
//! producer's side. What each voice keeps from one PLAY to the next (octave, length,
//! tempo, volume) is in State.audio_voices, on this side too.

const std = @import("std");
const defs = @import("defs.zig");
const forth = @import("../forth.zig");
const graphics_input = @import("graphics_input.zig");
const library_loading = @import("library_loading.zig");
const memory_map = @import("memory_map.zig");
const mml = @import("sound_mml.zig");
const sound_engine = @import("sound_engine.zig");
const parts = @import("sound_parts.zig");
const Builtin = defs.Builtin;
const Engine = sound_engine.Engine;
const RuntimeError = defs.RuntimeError;
const State = forth.State;

/// The built-in words this file executes; executeBuiltin dispatches by this list.
pub const words = [_]Builtin{ .snd_play, .snd_sound, .snd_beep, .snd_playing, .snd_device, .snd_plays, .snd_chip, .snd_instrument, .snd_wave, .snd_duty, .snd_adsr, .snd_ring, .snd_sync, .snd_filter };

/// The SND- words in the order REQUIRE-AUDIO appends them, right after the AUDIO
/// vocabulary. The order is part of the dictionary that images keep: add new words at
/// the end.
pub const definitions = [_]struct { []const u8, Builtin }{
    .{ "SND-PLAY", .snd_play },       .{ "SND-SOUND", .snd_sound },           .{ "SND-BEEP", .snd_beep },
    .{ "SND-PLAYING", .snd_playing }, .{ "SND-DEVICE", .snd_device },         .{ "SND-PLAYS", .snd_plays },
    .{ "SND-CHIP", .snd_chip },       .{ "SND-INSTRUMENT", .snd_instrument }, .{ "SND-WAVE", .snd_wave },
    .{ "SND-DUTY", .snd_duty },       .{ "SND-ADSR", .snd_adsr },             .{ "SND-RING", .snd_ring },
    .{ "SND-SYNC", .snd_sync },       .{ "SND-FILTER", .snd_filter },
};

/// The words of the audio library that HELP describes; the help test checks that the
/// library defines each of them.
pub const library_words = [_][]const u8{ "PLAY", "PLAY2", "PLAY3", "PLAY?", "SOUND", "BEEP", "AUDIO?", "PLAYS", "MSX-SOUND", "ST-SOUND", "NES-SOUND", "INSTRUMENT", "SQUARE", "PULSE", "TRIANGLE", "SAW", "NOISE", "DUTY", "ADSR", "C64-SOUND", "RING", "SYNC", "FILTER" };

/// The audio library, which REQUIRE-AUDIO interprets after appending the SND- words.
pub const library = @embedFile("../audio/audio.fs");

/// The name the library has in the source file table, for LOCATE and error messages.
pub const library_name = "*audio library*";

const group: library_loading.Group(@TypeOf(definitions[0])) = .{
    .vocabulary = "AUDIO",
    .definitions = &definitions,
    .library_name = library_name,
    .vocabulary_address = memory_map.audio_vocabulary_address,
    .image_address = memory_map.audio_image_address,
};

/// REQUIRE-AUDIO: as REQUIRE-GRAPHICS, for the AUDIO vocabulary, the SND- words, and the
/// audio library.
pub fn requireAudio(self: *State) RuntimeError!void {
    if (!defs.audio_enabled) return error.AudioUnavailable;
    return library_loading.require(self, group, self.audio_library);
}

/// Whether REQUIRE-AUDIO has loaded the audio words and they are still in the dictionary.
pub fn audioLoaded(self: *const State) bool {
    return library_loading.isLoaded(self, memory_map.audio_vocabulary_address, definitions[0][1]);
}

/// Whether a word is one REQUIRE-AUDIO added (HELP describes these).
pub fn isAudioWord(self: *const State, word: defs.Word) bool {
    return library_loading.isGroupWord(self, word, library_name);
}

pub fn execute(self: *State, builtin: Builtin) RuntimeError!void {
    switch (builtin) {
        .snd_play => {
            var texts: [3][]const u8 = undefined;
            var v: usize = 3;
            while (v > 0) {
                v -= 1;
                texts[v] = try self.memoryRange();
            }
            try play(self, &texts);
        },
        .snd_plays => {
            const count = try self.pop();
            if (count < 1 or count > self.audio_chip.voiceCount()) return error.InvalidNumber;
            var texts: [sound_engine.max_voices][]const u8 = undefined;
            var v: usize = @intCast(count);
            while (v > 0) {
                v -= 1;
                texts[v] = try self.memoryRange();
            }
            try play(self, texts[0..@intCast(count)]);
        },
        .snd_chip => {
            const n = try self.pop();
            const chips = @typeInfo(sound_engine.Chip).@"enum".field_names.len;
            if (n < 0 or n >= chips) return error.InvalidNumber;
            const engine = try getEngine(self);
            const chip: sound_engine.Chip = @fromBackingInt(@intCast(n));
            self.audio_chip = chip;
            try stop(self, engine, engine.chipCommand(chip));
        },
        .snd_instrument => {
            const n = try self.pop();
            if (n < 0 or n >= mml.instrument_count) return error.InvalidNumber;
            self.audio_instrument = @intCast(n);
        },
        .snd_wave => {
            const n = try self.pop();
            if (n < 0 or n >= @typeInfo(parts.Wave).@"enum".field_names.len) return error.InvalidNumber;
            try changeInstrument(self, .{ .wave = @fromBackingInt(@intCast(n)) });
        },
        .snd_duty => {
            const n = try self.pop();
            if (n < 0 or n > 100) return error.InvalidNumber;
            try changeInstrument(self, .{ .duty = @intCast(n) });
        },
        .snd_adsr => {
            var values: [4]u8 = undefined;
            var i: usize = 4;
            while (i > 0) {
                i -= 1;
                const n = try self.pop();
                if (n < 0 or n > 15) return error.InvalidNumber;
                values[i] = @intCast(n);
            }
            try changeInstrument(self, .{ .attack = values[0], .decay = values[1], .sustain = values[2], .release = values[3] });
        },
        .snd_ring => try changeInstrument(self, .{ .ring = try self.pop() != 0 }),
        .snd_sync => try changeInstrument(self, .{ .sync = try self.pop() != 0 }),
        .snd_filter => {
            const resonance = try self.pop();
            const cutoff = try self.pop();
            const mode = try self.pop();
            if (mode < 0 or mode > 3 or cutoff < 0 or cutoff > 2047 or resonance < 0 or resonance > 15) return error.InvalidNumber;
            try changeInstrument(self, .{ .filter = @intCast(mode), .cutoff = @intCast(cutoff), .resonance = @intCast(resonance) });
        },
        .snd_sound => {
            const value = try self.pop();
            const reg = try self.pop();
            // MSX BASIC's SOUND takes the registers 0 to 13 and values 0 to 255.
            if (reg < 0 or reg > 13 or value < 0 or value > 255) return error.InvalidNumber;
            const engine = try getEngine(self);
            try putCommand(self, engine, .{ .write = .{ .reg = @intCast(reg), .value = @intCast(value) } });
        },
        .snd_beep => {
            const engine = try getEngine(self);
            try reset(self, engine, true);
        },
        .snd_playing => {
            const n = try self.pop();
            if (n < 0 or n > self.audio_chip.voiceCount()) return error.InvalidNumber;
            const engine = try getEngine(self);
            try self.push(if (engine.isPlaying(@intCast(n))) -1 else 0);
        },
        .snd_device => {
            // Whether the sound is heard: the thread runs first, so that it has tried
            // the device.
            _ = try getEngine(self);
            const device_fn = self.writer.audio_device_fn orelse return self.push(0);
            try self.push(if (device_fn(self.writer.context)) -1 else 0);
        },
        else => unreachable,
    }
}

fn getEngine(self: *State) RuntimeError!*Engine {
    const audio_fn = self.writer.audio_fn orelse return error.HostUnavailable;
    return audio_fn(self.writer.context) orelse error.HostFailed;
}

/// Which settings of the instrument being edited change.
const Change = struct {
    wave: ?parts.Wave = null,
    duty: ?u8 = null,
    attack: ?u8 = null,
    decay: ?u8 = null,
    sustain: ?u8 = null,
    release: ?u8 = null,
    ring: ?bool = null,
    sync: ?bool = null,
    filter: ?u8 = null,
    cutoff: ?u16 = null,
    resonance: ?u8 = null,
};

/// Changes the instrument INSTRUMENT chose, here and for the audio thread.
fn changeInstrument(self: *State, change: Change) RuntimeError!void {
    const instrument = &self.audio_instruments[self.audio_instrument];
    if (change.wave) |value| instrument.wave = value;
    if (change.duty) |value| instrument.duty = value;
    if (change.attack) |value| instrument.attack = value;
    if (change.decay) |value| instrument.decay = value;
    if (change.sustain) |value| instrument.sustain = value;
    if (change.release) |value| instrument.release = value;
    if (change.ring) |value| instrument.ring = value;
    if (change.sync) |value| instrument.sync = value;
    if (change.filter) |value| instrument.filter = value;
    if (change.cutoff) |value| instrument.cutoff = value;
    if (change.resonance) |value| instrument.resonance = value;
    const engine = try getEngine(self);
    try putCommand(self, engine, .{ .instrument = .{ .index = self.audio_instrument, .value = instrument.* } });
}

/// PLAY: checks the voices' MML (an error puts nothing), then puts their notes,
/// waiting while the queues are full. Ctrl+C while it waits drops every note put so far,
/// as BEEP does without its sound, and throws USER INTERRUPT.
fn play(self: *State, texts: []const []const u8) RuntimeError!void {
    for (texts, 0..) |text, v| mml.check(self.audio_voices[v], text) catch return error.InvalidMml;
    const engine = try getEngine(self);
    var waiter: Waiter = .{ .state = self };
    sound_engine.putPlay(engine, &self.audio_voices, texts, &waiter, Waiter.wait) catch |err| switch (err) {
        error.InvalidMml => unreachable,
        error.Interrupted => {
            reset(self, engine, false) catch {};
            return waiter.failure orelse error.UserInterrupt;
        },
    };
}

/// Drops the notes put so far and sets the PSG as the MSX starts it, sounding BEEP's
/// tone when `beep`; the voices' octave, length, tempo, and volume go back to MSX
/// BASIC's defaults. It returns when the audio thread has taken the command, so that
/// PLAY? is false at once.
fn reset(self: *State, engine: *Engine, beep: bool) RuntimeError!void {
    try stop(self, engine, engine.resetCommand(beep));
}

/// Puts a reset command (BEEP's, a stop's, or MSX-SOUND's and the others') and waits
/// until the audio thread has taken it.
fn stop(self: *State, engine: *Engine, command: sound_engine.Command) RuntimeError!void {
    self.audio_voices = @splat(.{});
    try putCommand(self, engine, command);
    // The thread takes commands every few milliseconds; Ctrl+C is not taken here, as
    // the music is stopping anyway. The bound only guards against a host whose thread
    // has stopped.
    var waiter: Waiter = .{ .state = self };
    var waits: usize = 0;
    while (!engine.commands.isEmpty() and waits < max_reset_waits) : (waits += 1) {
        _ = waiter.wait();
    }
}

/// About a second of the host's waits.
const max_reset_waits = 300;

fn putCommand(self: *State, engine: *Engine, command: sound_engine.Command) RuntimeError!void {
    var waiter: Waiter = .{ .state = self };
    while (!engine.putCommand(command)) {
        if (!waiter.wait()) return waiter.failure orelse error.UserInterrupt;
    }
}

/// Waits for the audio thread through the host, and notices Ctrl+C.
const Waiter = struct {
    state: *State,
    failure: ?RuntimeError = null,

    fn wait(self: *Waiter) bool {
        const state = self.state;
        const wait_fn = state.writer.audio_wait_fn orelse {
            self.failure = error.HostUnavailable;
            return false;
        };
        switch (wait_fn(state.writer.context)) {
            .waited => return true,
            .interrupted => {
                self.failure = error.UserInterrupt;
                return false;
            },
            .read_input => {
                // Keys read here stay for INKEY; Ctrl+C throws.
                graphics_input.readPending(state) catch |err| {
                    self.failure = err;
                    return false;
                };
                return true;
            },
        }
    }
};
