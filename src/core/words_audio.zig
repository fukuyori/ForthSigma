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
const voice = sound_engine.voice;
const pcm = sound_engine.pcm;
const Tone = voice.Tone;
const Builtin = defs.Builtin;
const Engine = sound_engine.Engine;
const RuntimeError = defs.RuntimeError;
const Cell = memory_map.Cell;
const State = forth.State;

/// The built-in words this file executes; executeBuiltin dispatches by this list.
pub const words = [_]Builtin{ .snd_play, .snd_sound, .snd_beep, .snd_playing, .snd_device, .snd_plays, .snd_chip, .snd_instrument, .snd_wave, .snd_duty, .snd_adsr, .snd_ring, .snd_sync, .snd_filter, .snd_wavetable, .snd_load_sample, .snd_sample, .snd_loop_sample, .snd_sample_instrument, .snd_sfx, .snd_amiga_filter, .snd_free_samples, .snd_chips, .snd_load_mod, .snd_play_mod, .snd_stop_mod, .snd_mod_playing, .snd_style, .snd_pcm_open, .snd_pcm_write, .snd_pcm_queued, .snd_pcm_wait, .snd_pcm_stop, .snd_pcm_close, .snd_pcm_underruns, .snd_snes_frames, .snd_tone, .snd_play_tone, .snd_mod_filter, .snd_global, .snd_voice, .snd_hold };

/// The SND- words in the order REQUIRE-AUDIO appends them, right after the AUDIO
/// vocabulary. The order is part of the dictionary that images keep: add new words at
/// the end.
pub const definitions = [_]struct { []const u8, Builtin }{
    .{ "SND-PLAY", .snd_play },                           .{ "SND-SOUND", .snd_sound },                 .{ "SND-BEEP", .snd_beep },
    .{ "SND-PLAYING", .snd_playing },                     .{ "SND-DEVICE", .snd_device },               .{ "SND-PLAYS", .snd_plays },
    .{ "SND-CHIP", .snd_chip },                           .{ "SND-INSTRUMENT", .snd_instrument },       .{ "SND-WAVE", .snd_wave },
    .{ "SND-DUTY", .snd_duty },                           .{ "SND-ADSR", .snd_adsr },                   .{ "SND-RING", .snd_ring },
    .{ "SND-SYNC", .snd_sync },                           .{ "SND-FILTER", .snd_filter },               .{ "SND-WAVETABLE", .snd_wavetable },
    .{ "SND-LOAD-SAMPLE", .snd_load_sample },             .{ "SND-SAMPLE", .snd_sample },               .{ "SND-LOOP-SAMPLE", .snd_loop_sample },
    .{ "SND-SAMPLE-INSTRUMENT", .snd_sample_instrument }, .{ "SND-SFX", .snd_sfx },                     .{ "SND-AMIGA-FILTER", .snd_amiga_filter },
    .{ "SND-FREE-SAMPLES", .snd_free_samples },           .{ "SND-CHIPS", .snd_chips },                 .{ "SND-LOAD-MOD", .snd_load_mod },
    .{ "SND-PLAY-MOD", .snd_play_mod },                   .{ "SND-STOP-MOD", .snd_stop_mod },           .{ "SND-MOD-PLAYING", .snd_mod_playing },
    .{ "SND-STYLE", .snd_style },                         .{ "SND-PCM-OPEN", .snd_pcm_open },           .{ "SND-PCM-WRITE", .snd_pcm_write },
    .{ "SND-PCM-QUEUED", .snd_pcm_queued },               .{ "SND-PCM-WAIT", .snd_pcm_wait },           .{ "SND-PCM-STOP", .snd_pcm_stop },
    .{ "SND-PCM-CLOSE", .snd_pcm_close },                 .{ "SND-PCM-UNDERRUNS", .snd_pcm_underruns }, .{ "SND-SNES-FRAMES", .snd_snes_frames },
    .{ "SND-TONE", .snd_tone },                           .{ "SND-PLAY-TONE", .snd_play_tone },         .{ "SND-MOD-FILTER", .snd_mod_filter },
    .{ "SND-GLOBAL", .snd_global },                       .{ "SND-VOICE", .snd_voice },                 .{ "SND-HOLD", .snd_hold },
};

/// The words of the audio library that HELP describes; the help test checks that the
/// library defines each of them.
pub const library_words = [_][]const u8{ "PLAY", "PLAY2", "PLAY3", "PLAY?", "BEEP", "AUDIO?", "PLAYS", "PLAY-RESET", "INSTRUMENT", "SQUARE", "PULSE", "TRIANGLE", "SAW", "NOISE", "DUTY", "ADSR", "RING", "SYNC", "FILTER", "WAVETABLE", "LOAD-SAMPLE", "SAMPLE", "LOOP-SAMPLE", "SAMPLE-INSTRUMENT", "SFX", "FREE-SAMPLES", "LOAD-MOD", "PLAY-MOD", "STOP-MOD", "MOD?", "PCM-OPEN", "PCM-WRITE", "PCM-QUEUED", "PCM-WAIT", "PCM-STOP", "PCM-CLOSE", "PCM-UNDERRUNS", "SNES-FRAMES", "PLAY-TONE", "NOISE-LFSR", "NOISE-MIX", "ENVELOPE", "PITCH-SWEEP", "PITCH-SWEEP-LIMIT", "PORTAMENTO", "VIBRATO", "PITCH-MOD", "VOLUME-MOD", "MOD-ONLY", "PHASE-RESET", "NOTE-LIMIT", "VOICE-PAN", "INSTRUMENT-PAN", "REVERB-SEND", "MOD-FILTER", "REVERB", "REVERB-FIR", "MASTER-FILTER", "TONE-CONTROL", "MASTER-VOLUME", "VOICE-OSC", "VOICE-ENV", "VOICE-POS", "VOICE-ENDS", "VOICE-ON?", "PITCH-PERIOD", "PITCH-STEP", "VOLUME-STEPS", "DUTY-STEPS", "INTERPOLATION", "VOICE-LIMIT", "MIXER", "OUTPUT-BITS", "NOISE-RATE", "VOICE-HOLD", "V-STEPS" };

/// The audio library, which REQUIRE-AUDIO interprets after appending the SND- words.
pub const library = @import("embedded_text.zig").withoutCarriageReturns(@embedFile("../audio/audio.fs"));

/// The name the library has in the source file table, for LOCATE and error messages.
pub const library_name = "*audio library*";

pub const group: library_loading.Group(@TypeOf(definitions[0])) = .{
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
    return library_loading.isLoaded(self, group);
}

/// Whether a word is one REQUIRE-AUDIO added (HELP describes these).
pub fn isAudioWord(self: *const State, word: defs.Word) bool {
    return library_loading.isGroupWord(self, word, library_name);
}

pub fn execute(self: *State, builtin: Builtin) RuntimeError!void {
    switch (builtin) {
        .snd_snes_frames => return @import("words_snes_dsp.zig").execute(self),
        .snd_pcm_open, .snd_pcm_write, .snd_pcm_queued, .snd_pcm_wait, .snd_pcm_stop, .snd_pcm_close, .snd_pcm_underruns => return @import("words_pcm.zig").execute(self, builtin),
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
            if (count < 0 or count > sound_engine.max_voices) return error.InvalidNumber;
            if (count == 0) {
                const engine = try getEngine(self);
                try putCommand(self, engine, engine.stopPlayCommand());
                try waitTaken(self, engine);
                return;
            }
            var texts: [sound_engine.max_voices][]const u8 = undefined;
            var v: usize = @intCast(count);
            while (v > 0) {
                v -= 1;
                texts[v] = try self.memoryRange();
            }
            try play(self, texts[0..@intCast(count)]);
        },
        // The chips' words left the core (tque 1189): their libraries in include/ give
        // them again (tque 1190). The SND- words stay, so that images keep their words.
        .snd_chip, .snd_chips, .snd_style, .snd_amiga_filter, .snd_sound => return error.HostUnavailable,
        .snd_instrument => {
            const n = try self.pop();
            if (n < 0 or n >= mml.instrument_count) return error.InvalidNumber;
            self.audio_instrument = @intCast(n);
        },
        .snd_wave => {
            const n = try self.pop();
            // SQUARE, PULSE, TRIANGLE, SAW, and NOISE (0 to 4).
            if (n < 0 or n > 4) return error.InvalidNumber;
            var tone = currentTone(self);
            tone.wave = @fromBackingInt(@intCast(n));
            try setTone(self, tone);
        },
        .snd_duty => {
            const n = try self.pop();
            if (n < 0 or n > 65535) return error.InvalidNumber;
            var tone = currentTone(self);
            tone.duty = @intCast(n);
            try setTone(self, tone);
        },
        .snd_adsr => {
            const release = try self.pop();
            const sustain = try self.pop();
            const decay = try self.pop();
            const attack = try self.pop();
            if (!milliseconds(attack) or !milliseconds(decay) or !milliseconds(release) or sustain < 0 or sustain > 65535) return error.InvalidNumber;
            var tone = currentTone(self);
            tone.envelope = adsrEnvelope(@intCast(attack), @intCast(decay), @intCast(sustain), @intCast(release));
            try setTone(self, tone);
        },
        .snd_ring, .snd_sync => {
            const n = try self.pop();
            if (n < 0 or n > voice.voice_count) return error.InvalidNumber;
            var tone = currentTone(self);
            if (builtin == .snd_ring) tone.ring = @intCast(n) else tone.sync = @intCast(n);
            try setTone(self, tone);
        },
        .snd_filter => {
            const resonance = try self.pop();
            const hz = try self.pop();
            const mode = try self.pop();
            if (mode < 0 or mode > 7 or !frequency(hz) or resonance < 0 or resonance > 65535) return error.InvalidNumber;
            var tone = currentTone(self);
            tone.filter = @fromBackingInt(@intCast(mode));
            tone.filter_hz = @intCast(hz);
            tone.resonance = @intCast(resonance);
            try setTone(self, tone);
        },
        .snd_wavetable => {
            const n = try self.pop();
            const address = try self.pop();
            if (n < 1 or n > max_wavetable) return error.InvalidNumber;
            const count: usize = @intCast(n);
            const start = try self.memoryAddress(address, count * memory_map.cell_size);
            for (0..count) |i| {
                const value = std.mem.readInt(i64, self.memory[start + i * memory_map.cell_size ..][0..8], .little);
                if (value < -32768 or value > 32767) return error.InvalidNumber;
            }
            const engine = try getEngine(self);
            const out = try poolSpace(self, engine, count);
            for (out, 0..) |*s, i| s.* = @intCast(std.mem.readInt(i64, self.memory[start + i * memory_map.cell_size ..][0..8], .little));
            var tone = currentTone(self);
            tone.wave = .wavetable;
            tone.table = .{ .start = self.audio_pool_used, .length = @intCast(count) };
            try setTone(self, tone);
            self.audio_pool_used += @intCast(count);
        },
        .snd_tone => try toneWord(self),
        .snd_global => try globalWord(self),
        .snd_hold => {
            const n = try self.pop();
            const volume = try self.pop();
            const hz = try self.pop();
            const instrument = try self.pop();
            if (n < 1 or n > voice.voice_count or volume < 0 or volume > 65535 or hz < 0 or hz > max_frequency * 1000) return error.InvalidNumber;
            if (instrument < 0 or instrument >= mml.instrument_count) return error.InvalidNumber;
            const engine = try getEngine(self);
            try putCommand(self, engine, .{ .hold = .{
                .voice = @intCast(n - 1),
                .instrument = @intCast(instrument),
                .hz = @floatCast(@as(f64, @floatFromInt(hz)) / 1000.0),
                .volume = @intCast(volume),
            } });
        },
        .snd_voice => {
            const key = try self.pop();
            const n = try self.pop();
            if (n < 1 or n > voice.voice_count or key < 0 or key > 4) return error.InvalidNumber;
            const engine = try getEngine(self);
            const s = &engine.voice_states[@intCast(n - 1)];
            try self.push(switch (key) {
                0 => s.osc.load(.acquire),
                1 => s.env.load(.acquire),
                2 => s.position.load(.acquire),
                3 => s.ends.load(.acquire),
                else => if (s.on.load(.acquire)) -1 else 0,
            });
        },
        .snd_play_tone => {
            const ms = try self.pop();
            const hz = try self.pop();
            if (!frequency(hz) or !milliseconds(ms)) return error.InvalidNumber;
            const engine = try getEngine(self);
            try putCommand(self, engine, .{ .tone = .{ .hz = @intCast(hz), .ms = @intCast(ms) } });
        },
        .snd_mod_filter => {
            const hz = try self.pop();
            const mode = try self.pop();
            if (mode < 0 or mode > 7 or !frequency(hz)) return error.InvalidNumber;
            const engine = try getEngine(self);
            try putCommand(self, engine, .{ .mod_filter = .{ .mode = @fromBackingInt(@intCast(mode)), .hz = @intCast(hz) } });
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
            var tone = currentTone(self);
            if (n < 0) {
                tone.sample = null;
                if (tone.wave == .sample) tone.wave = .square;
            } else {
                tone.sample = @intCast(n);
                tone.wave = .sample;
            }
            try setTone(self, tone);
        },
        .snd_sfx => {
            const n = try sampleNumber(self);
            const engine = try getEngine(self);
            try putCommand(self, engine, .{ .sfx = n });
        },
        .snd_load_mod => {
            const name = try self.memoryRange();
            try self.push(try loadMod(self, name));
        },
        .snd_play_mod => {
            const repeat = try self.pop() != 0;
            const engine = try getEngine(self);
            try putCommand(self, engine, .{ .mod_play = repeat });
            // MOD? is true at once.
            try waitTaken(self, engine);
        },
        .snd_stop_mod => {
            const engine = try getEngine(self);
            try putCommand(self, engine, .mod_stop);
        },
        .snd_mod_playing => {
            const engine = try getEngine(self);
            try self.push(if (engine.mod_playing.load(.acquire)) -1 else 0);
        },
        .snd_free_samples => {
            const engine = try getEngine(self);
            // The music and the SFX stop first, so that nothing reads the pool any more.
            try reset(self, engine, false);
            try putCommand(self, engine, .free_samples);
            self.audio_samples = @splat(.{});
            self.audio_pool_used = 0;
            // The wavetables were in the pool too (the engine forgets them alike).
            sound_engine.forgetTables(&self.audio_instruments);
        },
        .snd_beep => {
            const engine = try getEngine(self);
            try reset(self, engine, true);
        },
        .snd_playing => {
            const n = try self.pop();
            if (n < 0 or n > sound_engine.max_voices) return error.InvalidNumber;
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

const mod_error_code: Cell = -277;

/// LOAD-MOD: reads a ProTracker module (4 channels, 31 samples) into the pool: its
/// patterns, its samples (8-bit, as 16-bit), and its song. The ior: 0, the file's,
/// MOD ERROR (-277) for a file that is not such a module or ends in its patterns, or
/// OUT OF MEMORY (-257). A module whose samples end early keeps what is there. The
/// module that played stops; nothing else changes on an error.
fn loadMod(self: *State, name: []const u8) RuntimeError!Cell {
    const mod = sound_engine.mod_module;
    const engine = try getEngine(self);
    const files = try self.fileOps();
    const context = self.writer.context;
    const opened = files.open(context, name, .read_only, false);
    if (opened.ior != 0) return opened.ior;
    const fileid: Cell = @bitCast(opened.value);
    defer _ = files.close(context, fileid);

    var header: [mod.header_size]u8 = undefined;
    switch (readAll(files, context, fileid, &header)) {
        .bytes => |count| if (count < header.len) return mod_error_code,
        .ior => |ior| return ior,
    }
    var song = mod.parseHeader(&header) catch return mod_error_code;
    // The patterns' bytes, the samples, and the song, one after the other.
    const pattern_slots = @as(usize, song.pattern_count) * mod.pattern_size / 2;
    var frames: usize = 0;
    for (song.samples) |info| frames += info.length;
    const song_slots = (@sizeOf(mod.Song) + 1) / 2;
    const out = poolSpace(self, engine, pattern_slots + frames + song_slots) catch return memory_error_code;
    const base = self.audio_pool_used;

    switch (readAll(files, context, fileid, std.mem.sliceAsBytes(out[0..pattern_slots]))) {
        .bytes => |count| if (count < pattern_slots * 2) return mod_error_code,
        .ior => |ior| return ior,
    }
    song.patterns_at = base * 2;
    var at: usize = pattern_slots;
    var buffer: [4096]u8 = undefined;
    var ended = false;
    for (&song.samples) |*info| {
        info.start = @intCast(base + at);
        var left: usize = info.length;
        var done: usize = 0;
        while (left > 0 and !ended) {
            const part = @min(left, buffer.len);
            const count = switch (readAll(files, context, fileid, buffer[0..part])) {
                .bytes => |c| c,
                .ior => |ior| return ior,
            };
            for (out[at + done ..][0..count], buffer[0..count]) |*s, byte| s.* = @as(i16, @as(i8, @bitCast(byte))) * 256;
            done += count;
            left -= count;
            if (count < part) ended = true;
        }
        // A sample cut short by the file's end is as long as what was read.
        info.length = @intCast(done);
        if (info.loop_start + info.loop_length > info.length) {
            info.loop_start = 0;
            info.loop_length = 0;
        }
        at += done;
    }
    @memcpy(std.mem.sliceAsBytes(out[at..][0..song_slots])[0..@sizeOf(mod.Song)], std.mem.asBytes(&song));
    const song_at: u32 = @intCast(base + at);
    self.audio_pool_used = @intCast(base + at + song_slots);
    try putCommand(self, engine, .{ .mod_load = song_at });
    return 0;
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

/// The instrument INSTRUMENT chose, as this side has it.
fn currentTone(self: *const State) Tone {
    return self.audio_instruments[self.audio_instrument];
}

/// Gives the instrument INSTRUMENT chose its new settings, for the audio thread and then
/// here (so that an error changes neither).
fn setTone(self: *State, tone: Tone) RuntimeError!void {
    const engine = try getEngine(self);
    try putCommand(self, engine, .{ .instrument = .{ .index = self.audio_instrument, .value = tone } });
    self.audio_instruments[self.audio_instrument] = tone;
}

/// The longest WAVETABLE, in samples.
const max_wavetable = 65536;

/// The largest time, frequency, and pitch difference the words take. An hour of
/// milliseconds fits the voices' counts of samples at any rate up to 192 kHz.
const max_milliseconds = 3_600_000;
const max_frequency = 1_000_000;
const max_cents = 1_200_000;

fn milliseconds(n: Cell) bool {
    return n >= 0 and n <= max_milliseconds;
}

fn frequency(n: Cell) bool {
    return n >= 0 and n <= max_frequency;
}

fn centsValue(n: Cell) bool {
    return n >= -max_cents and n <= max_cents;
}

/// ADSR as ENVELOPE's segments (3.3 of the study): a straight attack to the full level,
/// a decay to the sustain level (exponential), held until the note stops, and an
/// exponential release to 0.
pub fn adsrEnvelope(attack: u32, decay: u32, sustain: u16, release: u32) voice.Envelope {
    var e: voice.Envelope = .{ .count = 3, .release = 1 };
    e.segments[0] = .{ .level = 65535, .ms = attack };
    e.segments[1] = .{ .level = sustain, .ms = decay, .curve = 1 };
    e.segments[2] = .{ .level = 0, .ms = release, .curve = 1 };
    return e;
}

/// SND-GLOBAL ( ... key -- ): REVERB (0), REVERB-FIR (1), MASTER-FILTER (2),
/// TONE-CONTROL (3), and MASTER-VOLUME (4), 3.7 of the study, and VOICE-LIMIT (5),
/// MIXER (6), and OUTPUT-BITS (7), 3.5; MASTER-FILTER with its stage (8), VOICE-PAN (9), and PLAY-RESET (10). They take effect at once.
fn globalWord(self: *State) RuntimeError!void {
    const key = try self.pop();
    // PLAY-RESET: as a stop of the music (0 PLAYS), and the voices' MML settings go back
    // to what they are at start. SFX and MOD go on, and nothing sounds.
    if (key == 10) {
        const engine = try getEngine(self);
        return stop(self, engine, engine.stopPlayCommand());
    }
    const command: sound_engine.Command = switch (key) {
        0 => command: {
            const volume = try self.pop();
            const feedback = try self.pop();
            const ms = try self.pop();
            // The longest delay at 48 kHz (sound_master.max_delay_frames).
            if (ms < 0 or ms > max_reverb_ms or feedback < -65535 or feedback > 65535 or volume < 0 or volume > 65535) return error.InvalidNumber;
            break :command .{ .reverb = .{ .ms = @intCast(ms), .feedback = @intCast(feedback), .volume = @intCast(volume) } };
        },
        1 => command: {
            const n = try self.pop();
            const address = try self.pop();
            if (n < 0 or n > sound_engine.master.max_fir) return error.InvalidNumber;
            var coefficients: [sound_engine.master.max_fir]i32 = @splat(0);
            if (n > 0) {
                const count: usize = @intCast(n);
                const start = try self.memoryAddress(address, count * memory_map.cell_size);
                for (0..count) |i| {
                    const c = std.mem.readInt(i64, self.memory[start + i * memory_map.cell_size ..][0..8], .little);
                    if (c < -32768 or c > 32767) return error.InvalidNumber;
                    coefficients[i] = @intCast(c);
                }
            }
            break :command .{ .reverb_fir = .{ .count = @intCast(n), .coefficients = coefficients } };
        },
        2 => command: {
            const hz = try self.pop();
            const mode = try self.pop();
            if ((mode != 0 and mode != 1 and mode != 3) or !frequency(hz)) return error.InvalidNumber;
            break :command .{ .master_filter = .{ .mode = @enumFromInt(@as(u8, @intCast(mode))), .hz = @intCast(hz) } };
        },
        3 => command: {
            const treble = try self.pop();
            const bass = try self.pop();
            if (bass < -12 or bass > 12 or treble < -12 or treble > 12) return error.InvalidNumber;
            break :command .{ .tone_control = .{ .bass = @intCast(bass), .treble = @intCast(treble) } };
        },
        4 => command: {
            const ratio = try self.pop();
            if (ratio < 0 or ratio > 65535) return error.InvalidNumber;
            break :command .{ .master_volume = @intCast(ratio) };
        },
        5 => command: {
            const n = try self.pop();
            if (n < 1 or n > sound_engine.max_voices) return error.InvalidNumber;
            break :command .{ .voice_limit = @intCast(n) };
        },
        6 => command: {
            const mode = try self.pop();
            if (mode < 0 or mode > 1) return error.InvalidNumber;
            break :command .{ .mixer = @fromBackingInt(@intCast(mode)) };
        },
        7 => command: {
            const output_rate = try self.pop();
            const bits = try self.pop();
            if (bits < 0 or bits > 16 or !frequency(output_rate)) return error.InvalidNumber;
            break :command .{ .output_bits = .{ .bits = @intCast(bits), .rate = @intCast(output_rate) } };
        },
        // MASTER-FILTER with its stage (1 or 2); key 2 is stage 1 of the images that
        // have the word without one.
        8 => command: {
            const stage = try self.pop();
            const hz = try self.pop();
            const mode = try self.pop();
            if (stage < 1 or stage > sound_engine.master.filter_stages or !frequency(hz)) return error.InvalidNumber;
            if (mode != 0 and mode != 1 and mode != 3 and mode != 11 and mode != 13) return error.InvalidNumber;
            break :command .{ .master_filter = .{ .stage = @intCast(stage - 1), .mode = @enumFromInt(@as(u8, @intCast(mode))), .hz = @intCast(hz) } };
        },
        // VOICE-PAN: a voice's left and right levels.
        9 => command: {
            const n = try self.pop();
            const right = try self.pop();
            const left = try self.pop();
            if (n < 1 or n > voice.voice_count or left < -65535 or left > 65535 or right < -65535 or right > 65535) return error.InvalidNumber;
            break :command .{ .voice_pan = .{ .voice = @intCast(n - 1), .left = @intCast(left), .right = @intCast(right) } };
        },
        else => return error.InvalidNumber,
    };
    const engine = try getEngine(self);
    try putCommand(self, engine, command);
}

/// REVERB's longest delay: sound_master's 16384 frames at 48 kHz, in whole ms.
const max_reverb_ms = 341;

/// What SND-TONE's key (on top of the stack) chooses: the words of 3.3.1 of the study
/// that the audio library defines on it.
const ToneKey = enum(u8) { noise_lfsr, noise_mix, envelope, pitch_sweep, pitch_sweep_limit, portamento, vibrato, pitch_mod, volume_mod, mod_only, phase_reset, note_limit, instrument_pan, reverb_send, pitch_period, pitch_step, volume_steps, duty_steps, interpolation, noise_rate, v_steps };

/// The highest clock of PITCH-PERIOD and PITCH-STEP: 1 GHz, in 1/1000 Hz.
const max_pitch_clock: Cell = 1_000_000_000_000;

/// SND-TONE ( ... key -- ): one of the instrument's settings of 3.3.1. Every argument is
/// checked before anything changes.
fn toneWord(self: *State) RuntimeError!void {
    const key = try self.pop();
    if (key < 0 or key >= @typeInfo(ToneKey).@"enum".field_names.len) return error.InvalidNumber;
    var tone = currentTone(self);
    switch (@as(ToneKey, @fromBackingInt(@intCast(key)))) {
        .noise_lfsr => {
            const tap = try self.pop();
            const bits = try self.pop();
            if (bits < 2 or bits > 32 or tap < 1 or tap >= bits) return error.InvalidNumber;
            tone.noise_bits = @intCast(bits);
            tone.noise_tap = @intCast(tap);
        },
        .noise_mix => {
            const mode = try self.pop();
            if (mode < 0 or mode > 2) return error.InvalidNumber;
            tone.noise_mix = @fromBackingInt(@intCast(mode));
        },
        .envelope => {
            const release = try self.pop();
            const loop = try self.pop();
            const n = try self.pop();
            const address = try self.pop();
            if (n < 0 or n > voice.max_segments or loop < -1 or loop >= @max(n, 1) or release < -1 or release >= @max(n, 1)) return error.InvalidNumber;
            if (n == 0 and (loop != -1 or release != -1)) return error.InvalidNumber;
            var e: voice.Envelope = .{ .count = @intCast(n), .loop = @intCast(loop), .release = @intCast(release) };
            if (n > 0) {
                const count: usize = @intCast(n);
                const start = try self.memoryAddress(address, count * 3 * memory_map.cell_size);
                for (0..count) |i| {
                    const at = start + i * 3 * memory_map.cell_size;
                    const level = std.mem.readInt(i64, self.memory[at..][0..8], .little);
                    const ms = std.mem.readInt(i64, self.memory[at + 8 ..][0..8], .little);
                    const curve = std.mem.readInt(i64, self.memory[at + 16 ..][0..8], .little);
                    if (level < 0 or level > 65535 or !milliseconds(ms) or curve < 0 or curve > 1) return error.InvalidNumber;
                    e.segments[i] = .{ .level = @intCast(level), .ms = @intCast(ms), .curve = @intCast(curve) };
                }
            }
            tone.envelope = e;
        },
        .pitch_sweep => {
            const ms = try self.pop();
            const c = try self.pop();
            if (!centsValue(c) or !milliseconds(ms)) return error.InvalidNumber;
            tone.sweep_cents = @intCast(c);
            tone.sweep_ms = @intCast(ms);
        },
        .pitch_sweep_limit => {
            const high = try self.pop();
            const low = try self.pop();
            if (!frequency(low) or !frequency(high) or (high != 0 and low > high)) return error.InvalidNumber;
            tone.sweep_low_hz = @intCast(low);
            tone.sweep_high_hz = @intCast(high);
        },
        .portamento => {
            const ms = try self.pop();
            if (!milliseconds(ms)) return error.InvalidNumber;
            tone.portamento_ms = @intCast(ms);
        },
        .vibrato => {
            const delay = try self.pop();
            const hz = try self.pop();
            const c = try self.pop();
            if (c < 0 or c > max_cents or !frequency(hz) or !milliseconds(delay)) return error.InvalidNumber;
            tone.vibrato_cents = @intCast(c);
            tone.vibrato_hz = @intCast(hz);
            tone.vibrato_delay_ms = @intCast(delay);
        },
        .pitch_mod => {
            const c = try self.pop();
            const v = try self.pop();
            if (v < 0 or v > voice.voice_count or !centsValue(c)) return error.InvalidNumber;
            tone.pitch_mod = @intCast(v);
            tone.pitch_mod_cents = @intCast(c);
        },
        .volume_mod => {
            const ratio = try self.pop();
            const v = try self.pop();
            if (v < 0 or v > voice.voice_count or ratio < 0 or ratio > 65535) return error.InvalidNumber;
            tone.volume_mod = @intCast(v);
            tone.volume_mod_depth = @intCast(ratio);
        },
        .mod_only => tone.mod_only = try self.pop() != 0,
        .phase_reset => tone.phase_reset = try self.pop() != 0,
        .note_limit => {
            const ms = try self.pop();
            if (!milliseconds(ms)) return error.InvalidNumber;
            tone.note_limit_ms = @intCast(ms);
        },
        .instrument_pan => {
            const right = try self.pop();
            const left = try self.pop();
            if (left < -65535 or left > 65535 or right < -65535 or right > 65535) return error.InvalidNumber;
            tone.pan_left = @intCast(left);
            tone.pan_right = @intCast(right);
        },
        .reverb_send => {
            const ratio = try self.pop();
            if (ratio < 0 or ratio > 65535) return error.InvalidNumber;
            tone.reverb_send = @intCast(ratio);
        },
        .pitch_period => {
            const high = try self.pop();
            const low = try self.pop();
            const offset = try self.pop();
            const divider = try self.pop();
            const clock = try self.pop();
            // Clock 0: no steps, whatever the rest.
            if (clock == 0) {
                tone.pitch_mode = .none;
                tone.pitch_clock = 0;
                return setTone(self, tone);
            }
            if (clock < 0 or clock > max_pitch_clock or divider < 1 or divider > 65536 or offset < 0 or offset > 65536) return error.InvalidNumber;
            // The divisor is never 0: the shortest period plus the offset is at least 1.
            if (low < 0 or high < low or high > std.math.maxInt(u32) or low + offset < 1) return error.InvalidNumber;
            tone.pitch_mode = .period;
            tone.pitch_clock = @intCast(clock);
            tone.pitch_divider = @intCast(divider);
            tone.pitch_offset = @intCast(offset);
            tone.pitch_min = @intCast(low);
            tone.pitch_max = @intCast(high);
        },
        .pitch_step => {
            const bits = try self.pop();
            const clock = try self.pop();
            if (clock == 0) {
                tone.pitch_mode = .none;
                tone.pitch_clock = 0;
                return setTone(self, tone);
            }
            if (clock < 0 or clock > max_pitch_clock or bits < 1 or bits > 32) return error.InvalidNumber;
            tone.pitch_mode = .step;
            tone.pitch_clock = @intCast(clock);
            tone.pitch_bits = @intCast(bits);
        },
        .volume_steps => {
            const n = try self.pop();
            const address = try self.pop();
            if (n < 0 or n > voice.max_volume_steps) return error.InvalidNumber;
            var steps: [voice.max_volume_steps]u16 = @splat(0);
            if (n > 0) {
                const count: usize = @intCast(n);
                const start = try self.memoryAddress(address, count * memory_map.cell_size);
                for (0..count) |i| {
                    const v = std.mem.readInt(i64, self.memory[start + i * memory_map.cell_size ..][0..8], .little);
                    // Ascending, so that the nearest can be found by halves.
                    if (v < 0 or v > 65535 or (i > 0 and v < steps[i - 1])) return error.InvalidNumber;
                    steps[i] = @intCast(v);
                }
            }
            tone.volume_step_count = @intCast(n);
            tone.volume_steps = steps;
        },
        .duty_steps => {
            const n = try self.pop();
            if (n < 0 or n > 65535) return error.InvalidNumber;
            tone.duty_steps = @intCast(n);
        },
        .interpolation => {
            const mode = try self.pop();
            if (mode < 0 or mode > 1) return error.InvalidNumber;
            tone.interpolation = @fromBackingInt(@intCast(mode));
        },
        .noise_rate => {
            const hz = try self.pop();
            if (hz < 0 or hz > max_frequency * 1000) return error.InvalidNumber;
            tone.noise_rate = @intCast(hz);
        },
        .v_steps => {
            const n = try self.pop();
            const address = try self.pop();
            if (n != 0 and n != 16) return error.InvalidNumber;
            var steps: [16]u16 = @splat(0);
            if (n == 16) {
                const start = try self.memoryAddress(address, 16 * memory_map.cell_size);
                for (&steps, 0..) |*s, i| {
                    const v = std.mem.readInt(i64, self.memory[start + i * memory_map.cell_size ..][0..8], .little);
                    if (v < 0 or v > 65535) return error.InvalidNumber;
                    s.* = @intCast(v);
                }
            }
            tone.v_step_count = @intCast(n);
            tone.v_steps = steps;
        },
    }
    try setTone(self, tone);
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
            reset(self, engine, false) catch |reset_error| {
                if (reset_error != error.UserInterrupt) return reset_error;
            };
            return waiter.failure orelse error.UserInterrupt;
        },
    };
}

/// Drops the notes put so far, sounding BEEP's tone when `beep`; the voices' octave, length, tempo, and volume go back to MSX
/// BASIC's defaults. It returns when the audio thread has taken the command, so that
/// PLAY? is false at once.
fn reset(self: *State, engine: *Engine, beep: bool) RuntimeError!void {
    try stop(self, engine, engine.resetCommand(beep));
}

/// Puts a reset command (BEEP's or a stop's) and waits
/// until the audio thread has taken it.
fn stop(self: *State, engine: *Engine, command: sound_engine.Command) RuntimeError!void {
    self.audio_voices = @splat(.{});
    try putCommand(self, engine, command);
    try waitTaken(self, engine);
}

/// Waits until the audio thread has taken the commands put so far. It takes them every
/// few milliseconds; Ctrl+C is not taken here (the waits are short). The bound only
/// guards against a host whose thread has stopped.
fn waitTaken(self: *State, engine: *Engine) RuntimeError!void {
    var waiter: Waiter = .{ .state = self };
    var waits: usize = 0;
    while (!engine.commands.isEmpty() and waits < max_reset_waits) : (waits += 1) {
        if (!waiter.wait()) {
            if (waiter.failure) |failure| if (failure != error.UserInterrupt) return failure;
        }
    }
    if (!engine.commands.isEmpty()) return error.HostFailed;
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
            .host_failed => {
                self.failure = error.HostFailed;
                return false;
            },
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
