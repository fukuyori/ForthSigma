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
const pcm = sound_engine.pcm;
const Builtin = defs.Builtin;
const Engine = sound_engine.Engine;
const RuntimeError = defs.RuntimeError;
const Cell = memory_map.Cell;
const State = forth.State;

/// The built-in words this file executes; executeBuiltin dispatches by this list.
pub const words = [_]Builtin{ .snd_play, .snd_sound, .snd_beep, .snd_playing, .snd_device, .snd_plays, .snd_chip, .snd_instrument, .snd_wave, .snd_duty, .snd_adsr, .snd_ring, .snd_sync, .snd_filter, .snd_wavetable, .snd_load_sample, .snd_sample, .snd_loop_sample, .snd_sample_instrument, .snd_sfx, .snd_amiga_filter, .snd_free_samples };

/// The SND- words in the order REQUIRE-AUDIO appends them, right after the AUDIO
/// vocabulary. The order is part of the dictionary that images keep: add new words at
/// the end.
pub const definitions = [_]struct { []const u8, Builtin }{
    .{ "SND-PLAY", .snd_play },                           .{ "SND-SOUND", .snd_sound },           .{ "SND-BEEP", .snd_beep },
    .{ "SND-PLAYING", .snd_playing },                     .{ "SND-DEVICE", .snd_device },         .{ "SND-PLAYS", .snd_plays },
    .{ "SND-CHIP", .snd_chip },                           .{ "SND-INSTRUMENT", .snd_instrument }, .{ "SND-WAVE", .snd_wave },
    .{ "SND-DUTY", .snd_duty },                           .{ "SND-ADSR", .snd_adsr },             .{ "SND-RING", .snd_ring },
    .{ "SND-SYNC", .snd_sync },                           .{ "SND-FILTER", .snd_filter },         .{ "SND-WAVETABLE", .snd_wavetable },
    .{ "SND-LOAD-SAMPLE", .snd_load_sample },             .{ "SND-SAMPLE", .snd_sample },         .{ "SND-LOOP-SAMPLE", .snd_loop_sample },
    .{ "SND-SAMPLE-INSTRUMENT", .snd_sample_instrument }, .{ "SND-SFX", .snd_sfx },               .{ "SND-AMIGA-FILTER", .snd_amiga_filter },
    .{ "SND-FREE-SAMPLES", .snd_free_samples },
};

/// The words of the audio library that HELP describes; the help test checks that the
/// library defines each of them.
pub const library_words = [_][]const u8{ "PLAY", "PLAY2", "PLAY3", "PLAY?", "SOUND", "BEEP", "AUDIO?", "PLAYS", "MSX-SOUND", "ST-SOUND", "NES-SOUND", "INSTRUMENT", "SQUARE", "PULSE", "TRIANGLE", "SAW", "NOISE", "DUTY", "ADSR", "C64-SOUND", "RING", "SYNC", "FILTER", "SCC-SOUND", "SCC-WAVE", "LOAD-SAMPLE", "SAMPLE", "LOOP-SAMPLE", "SAMPLE-INSTRUMENT", "SFX", "FREE-SAMPLES", "AMIGA-SOUND", "AMIGA-FILTER" };

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
        .snd_wavetable => {
            const n = try self.pop();
            const address = try self.pop();
            if (n < 0 or n >= mml.instrument_count) return error.InvalidNumber;
            const start = try self.memoryAddress(address, 32);
            var samples: [32]i8 = undefined;
            for (&samples, self.memory[start..][0..32]) |*s, byte| s.* = @bitCast(byte);
            try changeInstrumentAt(self, @intCast(n), .{ .wavetable = samples });
        },
        .snd_load_sample => {
            const n = try sampleNumber(self);
            const name = try self.memoryRange();
            try self.push(try loadSample(self, name, n));
        },
        .snd_sample => {
            const n = try sampleNumber(self);
            const rate = try self.pop();
            const bytes = try self.memoryRange();
            if (rate < 1000 or rate > 192_000) return error.InvalidNumber;
            const engine = try getEngine(self);
            const out = try poolSpace(self, engine, bytes.len);
            for (out, bytes) |*s, byte| s.* = @as(i16, @as(i8, @bitCast(byte))) * 256;
            try addSample(self, engine, n, @intCast(bytes.len), @intCast(rate));
        },
        .snd_loop_sample => {
            const n = try sampleNumber(self);
            const end = try self.pop();
            const start = try self.pop();
            const sample = &self.audio_samples[n];
            // 0 0 turns the loop off.
            if (start < 0 or end < start or end > sample.length) return error.InvalidNumber;
            sample.loop_start = @intCast(start);
            sample.loop_end = @intCast(end);
            const engine = try getEngine(self);
            try putCommand(self, engine, .{ .sample = .{ .index = n, .value = sample.* } });
        },
        .snd_sample_instrument => {
            const n = try self.pop();
            if (n < -1 or n >= pcm.sample_count) return error.InvalidNumber;
            try changeInstrument(self, .{ .sample = if (n < 0) .none else .{ .number = @intCast(n) } });
        },
        .snd_sfx => {
            const n = try sampleNumber(self);
            const engine = try getEngine(self);
            try putCommand(self, engine, .{ .sfx = n });
        },
        .snd_amiga_filter => {
            const on = try self.pop() != 0;
            const engine = try getEngine(self);
            try putCommand(self, engine, .{ .amiga_filter = on });
        },
        .snd_free_samples => {
            const engine = try getEngine(self);
            // The music and the SFX stop first, so that nothing reads the pool any more.
            try reset(self, engine, false);
            try putCommand(self, engine, .free_samples);
            self.audio_samples = @splat(.{});
            self.audio_pool_used = 0;
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

/// Pops a sample's number, 0 to 63.
fn sampleNumber(self: *State) RuntimeError!u8 {
    const n = try self.pop();
    if (n < 0 or n >= pcm.sample_count) return error.InvalidNumber;
    return @intCast(n);
}

/// The next `count` places of the pool, or OUT OF MEMORY when it has not that many.
fn poolSpace(self: *State, engine: *Engine, count: usize) RuntimeError![]i16 {
    const used: usize = self.audio_pool_used;
    if (used > engine.pool.len or count > engine.pool.len - used) return error.MemoryExhausted;
    return engine.pool[used .. used + count];
}

/// Makes the `count` samples just written at the pool's end sample n.
fn addSample(self: *State, engine: *Engine, n: u8, count: u32, rate: u32) RuntimeError!void {
    self.audio_samples[n] = .{ .start = self.audio_pool_used, .length = count, .rate = rate };
    self.audio_pool_used += count;
    try putCommand(self, engine, .{ .sample = .{ .index = n, .value = self.audio_samples[n] } });
}

/// The THROW code of a file LOAD-SAMPLE cannot read, and of a full pool.
const sample_error_code: Cell = -276;
const memory_error_code: Cell = -257;

/// LOAD-SAMPLE: reads a WAV file's PCM into the pool as sample n. The ior: 0, the
/// file's, SAMPLE ERROR (-276) for a file that is not a WAV of 8- or 16-bit PCM, or
/// OUT OF MEMORY (-257) when the pool has no room. Nothing changes on an error.
fn loadSample(self: *State, name: []const u8, n: u8) RuntimeError!Cell {
    const engine = try getEngine(self);
    const files = try self.fileOps();
    const context = self.writer.context;
    const opened = files.open(context, name, .read_only, false);
    if (opened.ior != 0) return opened.ior;
    const fileid: Cell = @bitCast(opened.value);
    defer _ = files.close(context, fileid);
    var buffer: [4096]u8 = undefined;

    var header: [12]u8 = undefined;
    switch (readAll(files, context, fileid, &header)) {
        .bytes => |count| if (count < 12 or !std.mem.eql(u8, header[0..4], "RIFF") or !std.mem.eql(u8, header[8..12], "WAVE")) return sample_error_code,
        .ior => |ior| return ior,
    }
    var format: ?pcm.Format = null;
    while (true) {
        var chunk: [8]u8 = undefined;
        const got = switch (readAll(files, context, fileid, &chunk)) {
            .bytes => |count| count,
            .ior => |ior| return ior,
        };
        if (got < 8) return sample_error_code;
        const size: u64 = std.mem.readInt(u32, chunk[4..8], .little);
        if (std.mem.eql(u8, chunk[0..4], "data")) {
            const found = format orelse return sample_error_code;
            const frame = found.frameBytes();
            const frames: usize = @intCast(size / frame);
            const out = poolSpace(self, engine, frames) catch return memory_error_code;
            // Whole frames at a time: 4096 bytes hold a whole number of any frame size.
            var done: usize = 0;
            while (done < frames) {
                const want = @min(frames - done, buffer.len / frame) * frame;
                const count = switch (readAll(files, context, fileid, buffer[0..want])) {
                    .bytes => |c| c,
                    .ior => |ior| return ior,
                };
                done += pcm.convertFrames(found, buffer[0..count], out[done..]);
                if (count < want) break;
            }
            try addSample(self, engine, n, @intCast(done), found.rate);
            return 0;
        }
        // Other chunks are skipped; their size is padded to an even number of bytes.
        var left = size + (size & 1);
        if (std.mem.eql(u8, chunk[0..4], "fmt ")) {
            const body_size: usize = @intCast(@min(size, buffer.len));
            switch (readAll(files, context, fileid, buffer[0..body_size])) {
                .bytes => |count| if (count < body_size) return sample_error_code,
                .ior => |ior| return ior,
            }
            format = pcm.parseFormat(buffer[0..body_size]) catch return sample_error_code;
            left -= body_size;
        }
        while (left > 0) {
            const part: usize = @intCast(@min(left, buffer.len));
            switch (readAll(files, context, fileid, buffer[0..part])) {
                .bytes => |count| if (count < part) return sample_error_code,
                .ior => |ior| return ior,
            }
            left -= part;
        }
    }
}

/// Reads until `buffer` is full or the file ends: the bytes read, or the file's ior.
fn readAll(files: *const forth.FileOps, context: ?*anyopaque, fileid: Cell, buffer: []u8) union(enum) { bytes: usize, ior: Cell } {
    var used: usize = 0;
    while (used < buffer.len) {
        const result = files.read(context, fileid, buffer[used..]);
        if (result.ior != 0) return .{ .ior = result.ior };
        if (result.value == 0) break;
        used += @intCast(result.value);
    }
    return .{ .bytes = used };
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
    wavetable: ?[32]i8 = null,
    sample: ?union(enum) { none, number: u8 } = null,
};

/// Changes the instrument INSTRUMENT chose, here and for the audio thread.
fn changeInstrument(self: *State, change: Change) RuntimeError!void {
    return changeInstrumentAt(self, self.audio_instrument, change);
}

/// Changes instrument `index`, here and for the audio thread.
fn changeInstrumentAt(self: *State, index: u8, change: Change) RuntimeError!void {
    const instrument = &self.audio_instruments[index];
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
    if (change.wavetable) |value| instrument.wavetable = value;
    if (change.sample) |value| instrument.sample = switch (value) {
        .none => null,
        .number => |n| n,
    };
    const engine = try getEngine(self);
    try putCommand(self, engine, .{ .instrument = .{ .index = index, .value = instrument.* } });
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
