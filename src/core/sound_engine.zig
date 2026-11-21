//! Plays MSX BASIC's PLAY, SFX, and MOD on the standard sound's 16 voices, for a host's
//! audio thread (tque 1189).
//!
//! Two threads share an Engine: the Forth program (the producer) puts notes and commands
//! into one-way queues, and the audio thread (the consumer) takes them in `render`, which
//! makes the samples. Each queue has one writer of each index, so neither side locks or
//! waits. As on the MSX, a PLAY's voices start together: each PLAY ends every voice's
//! notes with an end mark, and the next PLAY starts only when all voices reached theirs
//! (and the producer has put all of the next one in).
//!
//! The voices are shared out once (a user decision, docs/SOUND_CORE_DESIGN_STUDY.md
//! 3.6): PLAY has voices 1 to 8, SFX 9 to 12, and MOD 13 to 16, so none takes another's.
//! The engine has no chip: a chip's character comes from the effect libraries in
//! include/ (tque 1190).

const std = @import("std");
const mml = @import("sound_mml.zig");
pub const voice = @import("sound_voice.zig");
pub const pcm = @import("sound_pcm.zig");
pub const stream = @import("sound_stream.zig");
pub const mod_module = @import("sound_mod.zig");
pub const master = @import("sound_master.zig");

pub const Event = mml.Event;
pub const Tone = voice.Tone;

/// The voices PLAY has (1 to 8); each has its queue.
pub const max_voices = 8;

/// The SFX that can sound at once (voices 9 to 12); a new one takes the place of the
/// oldest.
pub const sfx_voices = 4;
pub const sfx_first = max_voices;

/// The voices of MOD's four channels (13 to 16).
pub const mod_first = sfx_first + sfx_voices;

comptime {
    std.debug.assert(mod_first + mod_module.channel_count == voice.voice_count);
}

/// The level of the voices together before the output's constant level is taken away:
/// one voice at full volume is half the output's range there.
const mix_gain: f32 = 0.5;

/// A queue with one producer and one consumer. `capacity` must be a power of two.
pub fn Ring(comptime T: type, comptime capacity: u32) type {
    return struct {
        const Self = @This();
        items: [capacity]T = undefined,
        /// The next item to take; only the consumer writes it.
        head: std.atomic.Value(u32) = .init(0),
        /// The next free place; only the producer writes it.
        tail: std.atomic.Value(u32) = .init(0),

        pub const size = capacity;

        /// Producer: how many items fit now.
        pub fn free(self: *const Self) u32 {
            return capacity - (self.tail.raw -% self.head.load(.acquire));
        }

        /// Producer.
        pub fn push(self: *Self, item: T) bool {
            const tail = self.tail.raw;
            if (tail -% self.head.load(.acquire) >= capacity) return false;
            self.items[tail % capacity] = item;
            self.tail.store(tail +% 1, .release);
            return true;
        }

        /// Producer: whether the consumer has taken everything.
        pub fn isEmpty(self: *const Self) bool {
            return self.head.load(.acquire) == self.tail.raw;
        }

        /// Consumer: the next item, still in the queue.
        pub fn peek(self: *const Self) ?T {
            const head = self.head.raw;
            if (head == self.tail.load(.acquire)) return null;
            return self.items[head % capacity];
        }

        /// Consumer: takes the item `peek` gave.
        pub fn drop(self: *Self) void {
            self.head.store(self.head.raw +% 1, .release);
        }

        /// Consumer: takes everything before `position`, a tail the producer had.
        pub fn dropUntil(self: *Self, position: u32) void {
            self.head.store(position, .release);
        }
    };
}

/// Notes and end marks each voice can wait with.
pub const voice_queue_size = 32;

pub const Command = union(enum) {
    /// BEEP (with `beep`) or a stop: drops the notes put before it (up to these tails
    /// and this PLAY count), and sounds BEEP's note when `beep`. With
    /// `preserve_effects`, SFX and MOD go on.
    reset: struct { tails: [max_voices]u32, plays: u32, beep: bool, preserve_effects: bool = false },
    /// INSTRUMENT and the words after it: the instrument's settings, which the notes
    /// that start from now on use.
    instrument: struct { index: u8, value: Tone },
    /// LOAD-SAMPLE, SAMPLE, and LOOP-SAMPLE: where sample `index` is in the pool.
    sample: struct { index: u8, value: pcm.Sample },
    /// FREE-SAMPLES, after a stop: every sample is gone.
    free_samples,
    /// SFX: plays a sample once at its rate, at once and beside the music.
    sfx: u8,
    /// PLAY-TONE: a square of `hz` for `ms`, on an SFX voice.
    tone: struct { hz: u32, ms: u32 },
    /// LOAD-MOD: the module whose song (sound_mod.Song) is in the pool from this place
    /// (in 16-bit units). A module that plays stops.
    mod_load: u32,
    /// PLAY-MOD: plays the module from its start, again after its end when true.
    mod_play: bool,
    /// STOP-MOD.
    mod_stop,
    /// MOD-FILTER: the filter the effect E0x turns on for MOD's voices.
    mod_filter: struct { mode: voice.FilterMode, hz: u32 },
    /// The effects on all the voices together (sound_master.zig).
    reverb: struct { ms: u32, feedback: i32, volume: u16 },
    reverb_fir: struct { count: u8, coefficients: [master.max_fir]i32 },
    master_filter: struct { mode: master.FilterMode, hz: u32 },
    tone_control: struct { bass: i32, treble: i32 },
    master_volume: u16,
    /// VOICE-LIMIT, MIXER, and OUTPUT-BITS (3.5 of the study).
    voice_limit: u8,
    mixer: voice.Mixer,
    output_bits: struct { bits: u8, rate: u32 },
    /// VOICE-HOLD: voice `voice` (0 to 15) sounds the instrument until told otherwise.
    hold: struct { voice: u8, instrument: u8, hz: f32, volume: u16 },
};

/// What the audio thread last saw of each voice, for VOICE-OSC and the others; it
/// writes them at the end of each render, and the program reads them.
pub const VoiceState = struct {
    osc: std.atomic.Value(i32) = .init(0),
    env: std.atomic.Value(u32) = .init(0),
    position: std.atomic.Value(i32) = .init(-1),
    ends: std.atomic.Value(u32) = .init(0),
    on: std.atomic.Value(bool) = .init(false),
};

/// BEEP: about 1316 Hz (O6's E on the MSX's PSG, 1789773 / (16 × 85)) at MML's V7 for
/// 40 ms, on the standard square (3.2 of the study).
pub const beep_hz: f32 = 1789773.0 / (16.0 * 85.0);
pub const beep_volume: u8 = 7;
pub const beep_milliseconds: u32 = 40;

pub const Engine = struct {
    bank: voice.Bank,
    master: master.Master,
    voice_states: [voice.voice_count]VoiceState = @splat(.{}),
    sample_rate: u32,
    /// The host's pool of samples; the producer adds to its end (sound_pcm.zig).
    pool: []i16 = &.{},
    samples: [pcm.sample_count]pcm.Sample = @splat(.{}),
    sfx_next: usize = 0,
    mod: mod_module.Mod,
    /// Whether the module plays; only the consumer writes it (MOD?).
    mod_playing: std.atomic.Value(bool) = .init(false),
    /// The filter of E0x (MOD-FILTER), and whether E0x has turned it on.
    mod_led: bool = false,
    mod_filter: voice.FilterMode = .none,
    mod_filter_hz: u32 = 1000,
    /// The filter the MOD's voices have now.
    mod_filter_applied: bool = false,
    instruments: [mml.instrument_count]Tone = @splat(.{}),
    /// VOICE-LIMIT: PLAY's voices from this one on stay silent.
    voice_limit: u8 = max_voices,
    voices: [max_voices]Ring(Event, voice_queue_size) = @splat(.{}),
    commands: Ring(Command, 64) = .{},
    /// The PLAYs put in; only the producer writes it.
    plays_put: std.atomic.Value(u32) = .init(0),
    /// The PLAYs started; only the consumer writes it.
    plays_started: std.atomic.Value(u32) = .init(0),
    /// Bit n: voice n plays a note of the current PLAY; only the consumer writes it.
    sounding: std.atomic.Value(u8) = .init(0),

    /// Producer publishes PCM attachment; consumer applies at a render boundary.
    pcm_control: stream.Control = .{},
    pcm_session: @import("sound_stream_session.zig").Session = .{},

    // The consumer's own state.
    remaining: [max_voices]u16 = @splat(0),
    /// MML's Q: the ticks until the note stops before its length is over; 0 for none.
    gate_left: [max_voices]u16 = @splat(0),
    at_end: [max_voices]bool = @splat(true),
    tick_fraction: u32 = 0,
    beep_samples: u32 = 0,
    dc_input: [2]f32 = .{ 0, 0 },
    dc_output: [2]f32 = .{ 0, 0 },

    pub fn init(sample_rate: u32) Engine {
        return .{ .bank = voice.Bank.init(sample_rate), .master = master.Master.init(sample_rate), .mod = mod_module.Mod.init(sample_rate), .sample_rate = sample_rate };
    }

    fn rate(self: *const Engine) f32 {
        return self.bank.rate;
    }

    // ---- The producer's side (the Forth program) ----

    /// How many more items voice `v` can take now.
    pub fn voiceFree(self: *const Engine, v: usize) u32 {
        return self.voices[v].free();
    }

    pub fn putEvent(self: *Engine, v: usize, event: Event) bool {
        return self.voices[v].push(event);
    }

    /// Lets the audio thread start the PLAY being put.
    pub fn countPlay(self: *Engine) void {
        self.plays_put.store(self.plays_put.raw +% 1, .release);
    }

    /// Ends one PLAY with an end mark in each voice (the caller has checked they fit).
    pub fn endPlay(self: *Engine) void {
        for (&self.voices) |*queue| std.debug.assert(queue.push(.{ .kind = .end }));
    }

    pub fn putCommand(self: *Engine, command: Command) bool {
        return self.commands.push(command);
    }

    /// The command for BEEP (`beep`) or a stop, which drops every note put so far.
    pub fn resetCommand(self: *const Engine, beep: bool) Command {
        var tails: [max_voices]u32 = undefined;
        for (&tails, &self.voices) |*tail, *queue| tail.* = queue.tail.raw;
        return .{ .reset = .{ .tails = tails, .plays = self.plays_put.raw, .beep = beep } };
    }

    /// Stop MML and its voices, preserving independent SFX and MOD playback.
    pub fn stopPlayCommand(self: *const Engine) Command {
        var command = self.resetCommand(false);
        command.reset.preserve_effects = true;
        return command;
    }

    /// PLAY(n): whether voice n - 1 (or any voice, for n = 0) still has notes to play.
    pub fn isPlaying(self: *const Engine, n: usize) bool {
        if (n == 0) {
            for (1..max_voices + 1) |v| {
                if (self.isPlaying(v)) return true;
            }
            return false;
        }
        const v = n - 1;
        // The consumer sets `sounding` before it takes the note, so the voice never
        // looks idle between the two.
        if (self.sounding.load(.acquire) & (@as(u8, 1) << @intCast(v)) != 0) return true;
        return !self.voices[v].isEmpty();
    }

    // ---- The consumer's side (the audio thread) ----

    /// Fills `out` with stereo frames (left, right) of 16-bit samples.
    pub fn render(self: *Engine, out: []i16) void {
        self.pcm_control.apply();
        self.runCommands();
        var i: usize = 0;
        while (i + 1 < out.len) : (i += 2) {
            if (self.beep_samples > 0) {
                self.beep_samples -= 1;
            } else {
                self.tick_fraction += 50;
                if (self.tick_fraction >= self.sample_rate) {
                    self.tick_fraction -= self.sample_rate;
                    self.tick();
                }
            }
            if (self.mod.playing) {
                const values = self.mod.sample(self.pool, &self.mod_led);
                for (values, 0..) |value, c| self.bank.voices[mod_first + c].external = value;
                if (self.mod_led != self.mod_filter_applied) self.applyModFilter();
                if (!self.mod.playing) self.silenceMod();
            }
            const frame = self.bank.next(self.pool);
            const mixed = self.master.process(frame.left, frame.right, frame.reverb_left, frame.reverb_right);
            const input = if (self.pcm_control.active) |active| active.sample() else stream.Frame{ .left = 0, .right = 0 };
            const final = self.master.finish(.{ self.filtered(0, mixed[0] * mix_gain), self.filtered(1, mixed[1] * mix_gain) });
            out[i] = stream.mix(@intFromFloat(final[0] * 32767.0), input.left);
            out[i + 1] = stream.mix(@intFromFloat(final[1] * 32767.0), input.right);
        }
        self.mod_playing.store(self.mod.playing, .release);
        self.publishStates();
    }

    /// The voices' state for VOICE-OSC and the others, as this render left them.
    fn publishStates(self: *Engine) void {
        for (&self.bank.voices, &self.voice_states) |*v, *s| {
            s.osc.store(@intFromFloat(std.math.clamp(v.osc, -1, 1) * 32767), .release);
            s.env.store(@intFromFloat(std.math.clamp(v.level, 0, 1) * 65535), .release);
            s.position.store(@intCast(std.math.clamp(v.samplePosition(), -1, std.math.maxInt(i32))), .release);
            s.ends.store(v.ends, .release);
            s.on.store(v.active, .release);
        }
    }

    /// The level without its constant part (as the coupling capacitor of a computer's
    /// audio output removes it), as a 16-bit sample.
    fn filtered(self: *Engine, side: usize, x: f32) f32 {
        const y = x - self.dc_input[side] + 0.9985 * self.dc_output[side];
        self.dc_input[side] = x;
        self.dc_output[side] = y;
        return std.math.clamp(y * 0.6, -1.0, 1.0);
    }

    fn runCommands(self: *Engine) void {
        while (self.commands.peek()) |command| {
            self.commands.drop();
            switch (command) {
                .instrument => |i| self.instruments[i.index] = i.value,
                .sample => |s| self.samples[s.index] = s.value,
                .free_samples => {
                    self.samples = @splat(.{});
                    forgetTables(&self.instruments);
                    self.mod = mod_module.Mod.init(self.sample_rate);
                    self.silenceMod();
                    self.mod_playing.store(false, .release);
                },
                .mod_load => |at| {
                    self.mod.stop();
                    self.silenceMod();
                    const bytes = std.mem.sliceAsBytes(self.pool);
                    const start = @as(usize, at) * 2;
                    @memcpy(std.mem.asBytes(&self.mod.song), bytes[start..][0..@sizeOf(mod_module.Song)]);
                    self.mod_playing.store(false, .release);
                },
                .mod_play => |repeat| {
                    self.mod.start(repeat);
                    self.mod_led = false;
                    self.startMod();
                    self.mod_playing.store(self.mod.playing, .release);
                },
                .mod_stop => {
                    self.mod.stop();
                    self.silenceMod();
                    self.mod_playing.store(false, .release);
                },
                .mod_filter => |f| {
                    self.mod_filter = f.mode;
                    self.mod_filter_hz = f.hz;
                    self.applyModFilter();
                },
                .reverb => |r| self.master.setReverb(r.ms, r.feedback, r.volume),
                .reverb_fir => |f| self.master.setFir(f.coefficients[0..f.count]),
                .master_filter => |f| self.master.setFilter(f.mode, f.hz),
                .tone_control => |t| self.master.setTone(t.bass, t.treble),
                .master_volume => |ratio| self.master.setVolume(ratio),
                .voice_limit => |n| {
                    self.voice_limit = n;
                    for (self.bank.voices[n..max_voices]) |*v| v.silence();
                },
                .mixer => |m| self.bank.mixer = m,
                .output_bits => |o| self.master.setOutput(o.bits, o.rate),
                .hold => |h| self.hold(h.voice, h.instrument, h.hz, h.volume),
                .sfx => |n| {
                    const tone: Tone = .{ .wave = .sample, .sample = n };
                    self.nextSfx().noteOn(tone, voice.sample_base_hz, 1, self.samples[n], self.rate());
                },
                .tone => |t| {
                    const tone: Tone = .{ .wave = .square, .note_limit_ms = @max(t.ms, 1) };
                    self.nextSfx().noteOn(tone, @floatFromInt(t.hz), 1, .{}, self.rate());
                },
                .reset => |b| {
                    for (&self.voices, b.tails) |*queue, tail| queue.dropUntil(tail);
                    self.plays_started.store(b.plays, .release);
                    self.remaining = @splat(0);
                    self.gate_left = @splat(0);
                    self.at_end = @splat(true);
                    self.sounding.store(0, .release);
                    for (self.bank.voices[0..max_voices]) |*v| v.* = .{};
                    if (!b.preserve_effects) {
                        for (self.bank.voices[sfx_first..mod_first]) |*v| v.* = .{};
                        self.mod.stop();
                        self.silenceMod();
                        self.mod_playing.store(false, .release);
                    }
                    self.beep_samples = 0;
                    if (b.beep) {
                        const tone: Tone = .{ .wave = .square, .note_limit_ms = beep_milliseconds };
                        self.bank.voices[0].noteOn(tone, beep_hz, voice.mmlVolume(beep_volume), .{}, self.rate());
                        self.beep_samples = @max(self.sample_rate * beep_milliseconds / 1000, 1);
                    }
                },
            }
        }
    }

    /// VOICE-HOLD: a held voice with the same instrument goes on (its phase and its
    /// envelope) at the new pitch and volume, with the instrument's settings as they
    /// are now; otherwise the note starts anew. Volume 0 silences the voice at once.
    fn hold(self: *Engine, v: u8, instrument: u8, hz: f32, volume_ratio: u16) void {
        const target = &self.bank.voices[v];
        if (volume_ratio == 0) return target.silence();
        const volume = @as(f32, @floatFromInt(volume_ratio)) / 65535.0;
        const tone = self.instruments[instrument];
        const sample: pcm.Sample = if (tone.wave == .sample) if (tone.sample) |n| self.samples[n] else .{} else .{};
        if (target.active and target.gate and target.held_instrument == instrument) {
            // A slide on the way stops: the new pitch is the pitch.
            target.glide_left = 0;
            target.hz = hz;
            target.volume = volume;
            target.retone(tone, sample, self.rate());
            return;
        }
        target.noteOn(tone, hz, volume, sample, self.rate());
        target.held_instrument = instrument;
    }

    fn nextSfx(self: *Engine) *voice.Voice {
        const v = &self.bank.voices[sfx_first + self.sfx_next];
        self.sfx_next = (self.sfx_next + 1) % sfx_voices;
        return v;
    }

    /// MOD's voices sound what the module's channels give, on the format's sides.
    fn startMod(self: *Engine) void {
        for (0..mod_module.channel_count) |c| {
            const left: i32 = if (mod_module.Mod.side(c) == 0) 65535 else 0;
            const tone: Tone = .{ .wave = .external, .pan_left = left, .pan_right = 65535 - left };
            self.bank.voices[mod_first + c].noteOn(tone, 0, 1, .{}, self.rate());
        }
        self.mod_filter_applied = !self.mod_led;
        self.applyModFilter();
    }

    fn silenceMod(self: *Engine) void {
        for (self.bank.voices[mod_first..]) |*v| v.* = .{};
    }

    fn applyModFilter(self: *Engine) void {
        self.mod_filter_applied = self.mod_led;
        for (self.bank.voices[mod_first..]) |*v| {
            if (!v.active) continue;
            v.tone.filter = if (self.mod_led) self.mod_filter else .none;
            v.tone.filter_hz = self.mod_filter_hz;
            v.setFilter(self.rate());
        }
    }

    /// One tick of 1/50 second: each voice counts down its note and takes the next.
    fn tick(self: *Engine) void {
        for (0..max_voices) |v| {
            if (self.gate_left[v] > 0) {
                self.gate_left[v] -= 1;
                if (self.gate_left[v] == 0) self.bank.voices[v].noteOff(self.rate());
            }
            if (self.remaining[v] > 0) self.remaining[v] -= 1;
            if (self.remaining[v] == 0 and !self.at_end[v]) self.nextEvent(v);
        }
        for (self.at_end) |at_end| {
            if (!at_end) return;
        }
        self.startPlay();
    }

    fn startPlay(self: *Engine) void {
        const started = self.plays_started.raw;
        if (self.plays_put.load(.acquire) == started) return;
        self.plays_started.store(started +% 1, .release);
        self.at_end = @splat(false);
        for (0..max_voices) |v| self.nextEvent(v);
    }

    fn nextEvent(self: *Engine, v: usize) void {
        // The producer puts a whole PLAY before it counts it, so the voice has an item.
        const event = self.voices[v].peek() orelse return;
        const bit = @as(u8, 1) << @intCast(v);
        switch (event.kind) {
            .end => {
                self.at_end[v] = true;
                self.bank.voices[v].noteOff(self.rate());
                self.sounding.store(self.sounding.raw & ~bit, .release);
                self.voices[v].drop();
            },
            .note => {
                self.sounding.store(self.sounding.raw | bit, .release);
                self.voices[v].drop();
                self.play(v, event);
            },
        }
    }

    fn play(self: *Engine, v: usize, event: Event) void {
        self.remaining[v] = event.ticks;
        self.gate_left[v] = 0;
        const target = &self.bank.voices[v];
        if (event.period == 0) return target.noteOff(self.rate());
        if (v >= self.voice_limit) return;
        // Q: the note stops before its length is over.
        if (event.gate_ticks > 0 and event.gate_ticks < event.ticks) self.gate_left[v] = event.gate_ticks;
        var tone = self.instruments[event.instrument];
        var volume = voice.toneVolume(&tone, event.amplitude);
        // S and M: the envelope in MSX MML's time, at full volume (1189 decision).
        if (event.amplitude == 16) {
            tone.envelope = voice.mmlEnvelope(event.shape, event.envelope_period);
            volume = 1;
        }
        // K: cents added to the pitch.
        const hz: f32 = @as(f32, @floatCast(voice.noteFrequency(event.note))) * voice.cents(@floatFromInt(event.detune));
        // & and _: the note before goes on at this pitch (a note that has ended stays
        // silent); its instrument's settings, P, and Y stay as it started.
        if (event.join != .none) {
            if (!target.active or !target.gate) return;
            switch (event.join) {
                .none => unreachable,
                .slur => target.retune(hz, volume),
                .glide => target.glideTo(hz, volume, @intCast(@as(u64, event.ticks) * self.sample_rate / 50), self.rate()),
            }
            return;
        }
        // P: the left and right levels, times the instrument's VOICE-PAN.
        tone.pan_left = @divTrunc(tone.pan_left * @as(i32, event.pan_left), 100);
        tone.pan_right = @divTrunc(tone.pan_right * @as(i32, event.pan_right), 100);
        // Y: the vibrato's depth and speed in place of the instrument's (its delay stays).
        if (event.vibrato == .set) {
            tone.vibrato_cents = event.vibrato_cents;
            tone.vibrato_hz = event.vibrato_hz;
        }
        const sample: pcm.Sample = if (tone.wave == .sample) if (tone.sample) |n| self.samples[n] else .{} else .{};
        target.noteOn(tone, hz, volume, sample, self.rate());
    }
};

/// After FREE-SAMPLES: the instruments' wavetables were in the pool, so they are gone,
/// and those instruments play the square again. Both sides do the same.
pub fn forgetTables(instruments: []Tone) void {
    for (instruments) |*tone| {
        if (tone.table.length == 0) continue;
        tone.table = .{};
        if (tone.wave == .wavetable) tone.wave = .square;
    }
}

/// Puts one PLAY's voices (up to 8 texts) for `engine`, a note at a time, after checking
/// all of them, so that an error puts nothing. When the voices that still have notes are
/// all full, the PLAY is let start (as the MSX does, so that a long PLAY plays while it
/// is being put) and `waitFn(context)` is called until there is room; it returns false
/// to stop, and putPlay then returns error.Interrupted: the notes put so far stay, and
/// the caller drops them with a reset command.
pub fn putPlay(engine: *Engine, voices: []mml.Voice, texts: []const []const u8, context: anytype, comptime waitFn: fn (@TypeOf(context)) bool) (mml.Error || error{Interrupted})!void {
    std.debug.assert(texts.len <= max_voices and voices.len >= texts.len);
    for (texts, 0..) |text, v| try mml.check(voices[v], text);
    var parsers: [max_voices]?mml.Parser = @splat(null);
    for (texts, 0..) |text, v| parsers[v] = mml.Parser.init(&voices[v], text);
    var pending: [max_voices]?Event = @splat(null);
    var counted = false;
    while (true) {
        var left = false;
        var progressed = false;
        for (0..max_voices) |v| {
            if (parsers[v] == null) continue;
            while (true) {
                if (pending[v] == null) pending[v] = parsers[v].?.next() catch unreachable;
                const event = pending[v] orelse {
                    parsers[v] = null;
                    break;
                };
                // Keep one place for the end mark.
                if (engine.voiceFree(v) <= 1) break;
                std.debug.assert(engine.putEvent(v, event));
                pending[v] = null;
                progressed = true;
            }
            if (parsers[v] != null) left = true;
        }
        if (!left) break;
        if (!progressed) {
            if (!counted) {
                engine.countPlay();
                counted = true;
            }
            if (!waitFn(context)) return error.Interrupted;
        }
    }
    while (!allHaveRoom(engine)) {
        if (!counted) {
            engine.countPlay();
            counted = true;
        }
        if (!waitFn(context)) return error.Interrupted;
    }
    engine.endPlay();
    if (!counted) engine.countPlay();
}

fn allHaveRoom(engine: *const Engine) bool {
    for (0..max_voices) |v| {
        if (engine.voiceFree(v) < 1) return false;
    }
    return true;
}
