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
const Builtin = defs.Builtin;
const Engine = sound_engine.Engine;
const RuntimeError = defs.RuntimeError;
const State = forth.State;

/// The built-in words this file executes; executeBuiltin dispatches by this list.
pub const words = [_]Builtin{ .snd_play, .snd_sound, .snd_beep, .snd_playing, .snd_device };

/// The SND- words in the order REQUIRE-AUDIO appends them, right after the AUDIO
/// vocabulary. The order is part of the dictionary that images keep: add new words at
/// the end.
pub const definitions = [_]struct { []const u8, Builtin }{
    .{ "SND-PLAY", .snd_play },       .{ "SND-SOUND", .snd_sound },   .{ "SND-BEEP", .snd_beep },
    .{ "SND-PLAYING", .snd_playing }, .{ "SND-DEVICE", .snd_device },
};

/// The words of the audio library that HELP describes; the help test checks that the
/// library defines each of them.
pub const library_words = [_][]const u8{ "PLAY", "PLAY2", "PLAY3", "PLAY?", "SOUND", "BEEP", "AUDIO?" };

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
            if (n < 0 or n > 3) return error.InvalidNumber;
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

/// PLAY: checks the three voices' MML (an error puts nothing), then puts their notes,
/// waiting while the queues are full. Ctrl+C while it waits drops every note put so far,
/// as BEEP does without its sound, and throws USER INTERRUPT.
fn play(self: *State, texts: *const [3][]const u8) RuntimeError!void {
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
    self.audio_voices = @splat(.{});
    try putCommand(self, engine, engine.resetCommand(beep));
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
