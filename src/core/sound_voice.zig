//! The standard sound's voices (tque 1189): one oscillator, envelope, pitch changes,
//! filter, and pan for each of 16 voices, with no chip's limits. A chip's character is
//! added by the effect libraries in include/ (tque 1190), not here.
//!
//! Units follow docs/SOUND_CORE_DESIGN_STUDY.md 3.3.1: ratios 0 to 65535, frequencies
//! in Hz, times in milliseconds, pitch differences in cents, pan -65535 to 65535 (a
//! negative side is inverted). Everything runs on the audio thread at the output's
//! sample rate, allocates nothing, and calls no Forth.

const std = @import("std");
const pcm = @import("sound_pcm.zig");

/// The voices the standard sound has (PLAY, SFX, and MOD share them, 3.6 of the study).
pub const voice_count = 16;

/// The segments one ENVELOPE can have.
pub const max_segments = 16;

/// The frequency a sample plays at its own rate: O4's C.
pub const sample_base_hz: f32 = 261.6256;

/// The noise's LFSR shifts this many times for each cycle of the voice's pitch, so that
/// the noise follows the note (low notes rumble, high notes hiss).
pub const noise_shifts_per_cycle: f32 = 16;

/// `external` is not chosen by a word: the engine gives the value of each sample (the
/// channels of a MOD, whose own player steps through their samples).
pub const Wave = enum(u8) { square, pulse, triangle, saw, noise, wavetable, sample, external };

/// 0: tone or noise alone; 1: the two added; 2: gated, high only when both are high
/// (as a PSG's channel mixes them).
pub const NoiseMix = enum(u8) { none, add, gate };

pub const FilterMode = enum(u8) { none, low_pass, band_pass, high_pass, notch };

/// One segment of an ENVELOPE: the level it goes to (0 to 65535), in `ms`
/// milliseconds, straight (`curve` 0) or exponential in decibels (1).
pub const Segment = struct {
    level: u16 = 0,
    ms: u32 = 0,
    curve: u8 = 0,
};

/// ENVELOPE: with no segments the note is at full level while it sounds. `loop` is the
/// segment the envelope goes back to after the last while the note sounds, `release`
/// the segment it stays at the end of until the note stops (-1 for none of either).
pub const Envelope = struct {
    count: u8 = 0,
    loop: i8 = -1,
    release: i8 = -1,
    segments: [max_segments]Segment = @splat(.{}),
};

/// An instrument of the standard sound (INSTRUMENT and the words after it).
pub const Tone = struct {
    wave: Wave = .square,
    /// The pulse's high part, 0 to 65535 of a cycle.
    duty: u16 = 32768,
    /// NOISE-LFSR: the register's length (1 to 32 bits) and the bit fed back with bit 0.
    noise_bits: u8 = 15,
    noise_tap: u8 = 1,
    noise_mix: NoiseMix = .none,
    /// WAVETABLE: one cycle in the pool (`start` and `length`; the rate is not used).
    table: pcm.Sample = .{},
    /// SAMPLE-INSTRUMENT: the sample number (0 to 63), or null.
    sample: ?u8 = null,
    envelope: Envelope = .{},
    /// PITCH-SWEEP: `sweep_cents` every `sweep_ms`; PITCH-SWEEP-LIMIT: silent outside
    /// `sweep_low_hz` to `sweep_high_hz` (0 0 for no limit).
    sweep_cents: i32 = 0,
    sweep_ms: u32 = 0,
    sweep_low_hz: u32 = 0,
    sweep_high_hz: u32 = 0,
    portamento_ms: u32 = 0,
    vibrato_cents: u32 = 0,
    vibrato_hz: u32 = 0,
    vibrato_delay_ms: u32 = 0,
    /// The source voices (1 to 16, 0 for none) of RING, SYNC, PITCH-MOD, and VOLUME-MOD.
    ring: u8 = 0,
    sync: u8 = 0,
    pitch_mod: u8 = 0,
    pitch_mod_cents: i32 = 0,
    volume_mod: u8 = 0,
    volume_mod_depth: u16 = 0,
    mod_only: bool = false,
    phase_reset: bool = false,
    note_limit_ms: u32 = 0,
    filter: FilterMode = .none,
    filter_hz: u32 = 1000,
    resonance: u16 = 0,
    pan_left: i32 = 65535,
    pan_right: i32 = 65535,
    reverb_send: u16 = 0,
    /// PITCH-PERIOD and PITCH-STEP (3.5 of the study): the clock in 1/1000 Hz, 0 for none.
    pitch_mode: PitchMode = .none,
    pitch_clock: u64 = 0,
    pitch_divider: u32 = 1,
    pitch_offset: u32 = 0,
    pitch_min: u32 = 0,
    pitch_max: u32 = 0,
    pitch_bits: u8 = 0,
    /// VOLUME-STEPS: an ascending table of levels (0 to 65535); none when the count is 0.
    volume_step_count: u8 = 0,
    volume_steps: [max_volume_steps]u16 = @splat(0),
    /// DUTY-STEPS: the pulse's duty in `duty_steps` steps, 0 for none.
    duty_steps: u16 = 0,
    /// INTERPOLATION: how a wavetable and a sample are read between their values.
    interpolation: Interpolation = .none,
    /// NOISE-RATE: the noise's shifts a second in 1/1000 Hz; 0 for 16 a cycle of the note.
    noise_rate: u64 = 0,
    /// V-STEPS: MML's V0 to V15 as these levels (0 to 65535); without them (count 0), 3 dB
    /// a step (mmlVolume).
    v_step_count: u8 = 0,
    v_steps: [16]u16 = @splat(0),
};

/// MML's V (0 to 15) on this tone: its V-STEPS, or 3 dB a step.
pub fn toneVolume(tone: *const Tone, v: u8) f32 {
    if (tone.v_step_count == 16) return @as(f32, @floatFromInt(tone.v_steps[@min(v, 15)])) / 65535.0;
    return mmlVolume(v);
}

pub const PitchMode = enum(u8) { none, period, step };
pub const Interpolation = enum(u8) { none, linear };

/// MIXER: how voices 1 to 4 are mixed (all the others are added).
pub const Mixer = enum(u8) { linear, nes };

/// The most levels of VOLUME-STEPS (Paula's 65 fit).
pub const max_volume_steps = 128;

/// The highest note a noise follows (16 shifts a cycle): the words' highest frequency.
const max_noise_hz: f64 = 1_000_000;

/// The frequency `hz` as the tone's pitch steps make it (PITCH-PERIOD, PITCH-STEP).
pub fn quantizePitch(tone: *const Tone, hz: f32) f32 {
    if (tone.pitch_mode == .none or tone.pitch_clock == 0 or !(hz > 0)) return hz;
    const clock = @as(f64, @floatFromInt(tone.pitch_clock)) / 1000.0;
    const f: f64 = hz;
    switch (tone.pitch_mode) {
        .none => return hz,
        .period => {
            const divider: f64 = @floatFromInt(@max(tone.pitch_divider, 1));
            const offset: f64 = @floatFromInt(tone.pitch_offset);
            const exact = clock / (divider * f) - offset;
            const low: f64 = @floatFromInt(tone.pitch_min);
            const high: f64 = @floatFromInt(tone.pitch_max);
            const period = std.math.clamp(@round(exact), low, high);
            if (period + offset <= 0) return 0;
            return @floatCast(clock / (divider * (period + offset)));
        },
        .step => {
            const scale = std.math.pow(f64, 2, @floatFromInt(tone.pitch_bits));
            const n = std.math.clamp(@round(f * scale / clock), 0, scale - 1);
            return @floatCast(n * clock / scale);
        },
    }
}

/// The amplitude `a` at the nearest of the tone's volume steps in decibels (VOLUME-STEPS):
/// between two levels the boundary is their geometric mean, and between 0 and the
/// lowest level half of it.
pub fn quantizeVolume(tone: *const Tone, a: f32) f32 {
    const count = tone.volume_step_count;
    if (count == 0) return a;
    const steps = tone.volume_steps[0..count];
    // The first level above a.
    var low: usize = 0;
    var high: usize = count;
    while (low < high) {
        const middle = (low + high) / 2;
        if (level(steps[middle]) <= a) low = middle + 1 else high = middle;
    }
    if (low == 0) return level(steps[0]);
    if (low == count) return level(steps[count - 1]);
    const below = level(steps[low - 1]);
    const above = level(steps[low]);
    const boundary = if (below == 0) above * 0.5 else @sqrt(below * above);
    return if (a < boundary) below else above;
}

/// The duty (0 to 1) at the tone's duty steps (DUTY-STEPS), never 0 or 1.
pub fn quantizeDuty(tone: *const Tone, duty: f32) f32 {
    if (tone.duty_steps < 2) return duty;
    const n: f32 = @floatFromInt(tone.duty_steps);
    return std.math.clamp(@round(duty * n), 1, n - 1) / n;
}

/// The quietest level the exponential curve passes through on its way to or from 0
/// (-60 dB); it reaches 0 itself at the end of the segment.
const exponential_floor: f32 = 0.001;

const Stage = enum(u8) { idle, running, holding, done };

pub const Voice = struct {
    tone: Tone = .{},
    /// The sample of a `.sample` tone, as the note started.
    sample: pcm.Sample = .{},
    active: bool = false,
    gate: bool = false,
    /// The instrument of VOICE-HOLD while it holds this voice; any other note clears it.
    held_instrument: ?u8 = null,
    /// The note's volume, 0 to 1.
    volume: f32 = 1,
    /// The pitch now (sweeps change it) and, while a portamento runs, where it goes.
    hz: f32 = 0,
    /// The pitch of the last sample, with vibrato and PITCH-MOD (a sample plays at it).
    sounding_hz: f32 = 0,
    glide_from: f32 = 0,
    glide_to: f32 = 0,
    glide_left: u32 = 0,
    glide_total: u32 = 0,
    sweep_left: u32 = 0,
    muted: bool = false,
    phase: f32 = 0,
    /// Whether the phase wrapped at the last sample (for the voices it syncs).
    wrapped: bool = false,
    lfsr: u32 = 1,
    /// In double precision, so that the slowest NOISE-RATE still moves it.
    noise_phase: f64 = 0,
    noise_high: bool = true,
    position: f64 = 0,
    stage: Stage = .idle,
    segment: u8 = 0,
    from_level: f32 = 0,
    elapsed: u32 = 0,
    length: u32 = 0,
    level: f32 = 0,
    vibrato_phase: f32 = 0,
    vibrato_wait: u32 = 0,
    played: u32 = 0,
    limit: u32 = 0,
    filter_a1: f32 = 0,
    filter_a2: f32 = 0,
    filter_a3: f32 = 0,
    filter_k: f32 = 2,
    ic1: f32 = 0,
    ic2: f32 = 0,
    /// What the voice gave at the last sample: the oscillator (-1 to 1, before the
    /// envelope), and the output (after the envelope, volume, and filter).
    osc: f32 = 0,
    out: f32 = 0,
    /// How many times the sample has reached its end or looped (VOICE-ENDS).
    ends: u32 = 0,
    /// The value of an `external` voice for the next sample.
    external: f32 = 0,

    /// Starts a note at `hz` with `volume` (0 to 1). `sample` is the tone's sample when
    /// it plays one.
    pub fn noteOn(self: *Voice, tone: Tone, hz: f32, volume: f32, sample: pcm.Sample, rate: f32) void {
        const previous = self.hz;
        const was_sounding = self.active;
        const had_note = self.active and previous > 0;
        self.held_instrument = null;
        self.tone = tone;
        self.sample = sample;
        self.active = true;
        self.gate = true;
        self.volume = volume;
        self.muted = false;
        self.hz = hz;
        self.glide_left = 0;
        if (tone.portamento_ms > 0 and had_note and previous != hz) {
            self.glide_from = previous;
            self.glide_to = hz;
            self.glide_total = msSamples(tone.portamento_ms, rate);
            self.glide_left = self.glide_total;
            self.hz = previous;
        }
        self.sweep_left = msSamples(tone.sweep_ms, rate);
        if (tone.phase_reset or !had_note) {
            self.phase = 0;
            self.vibrato_phase = 0;
        }
        self.position = 0;
        self.lfsr = 1;
        self.vibrato_wait = msSamples(tone.vibrato_delay_ms, rate);
        self.played = 0;
        self.limit = msSamples(tone.note_limit_ms, rate);
        self.setFilter(rate);
        self.startEnvelope(rate, was_sounding);
    }

    /// MML's `&`: the note goes on at another pitch and volume, without starting anew.
    pub fn retune(self: *Voice, hz: f32, volume: f32) void {
        self.glide_left = 0;
        self.hz = hz;
        self.volume = volume;
    }

    /// MML's `_`: as `retune`, sliding to the pitch in the tone's PORTAMENTO time, or in
    /// `samples` when it has none.
    pub fn glideTo(self: *Voice, hz: f32, volume: f32, samples: u32, rate: f32) void {
        const total = if (self.tone.portamento_ms > 0) msSamples(self.tone.portamento_ms, rate) else samples;
        const from = self.hz;
        self.retune(hz, volume);
        if (total == 0 or !(from > 0) or !(hz > 0) or from == hz) return;
        self.glide_from = from;
        self.glide_to = hz;
        self.glide_total = total;
        self.glide_left = total;
        self.hz = from;
    }

    /// Stops the note: the envelope goes on from its release segment, or the voice is
    /// silent at once when it has none.
    pub fn noteOff(self: *Voice, rate: f32) void {
        self.held_instrument = null;
        if (!self.active) return;
        self.gate = false;
        const envelope = self.tone.envelope;
        if (envelope.count == 0 or envelope.release < 0) return self.silence();
        const next: u8 = @intCast(envelope.release + 1);
        if (self.segment > envelope.release and self.stage == .running) return;
        if (next >= envelope.count) return self.silence();
        self.beginSegment(next, rate);
    }

    /// Silent at once, as a rest is.
    pub fn silence(self: *Voice) void {
        self.active = false;
        self.gate = false;
        self.level = 0;
        self.stage = .idle;
        self.out = 0;
        self.osc = 0;
    }

    /// The envelope from its first segment. On a voice that was sounding it goes on from
    /// the level the note before left (as the SID's attack does): going back to 0 at
    /// once would be heard as a click at the start of each note.
    fn startEnvelope(self: *Voice, rate: f32, was_sounding: bool) void {
        if (self.tone.envelope.count == 0) {
            self.stage = .done;
            self.level = 1;
            return;
        }
        if (!was_sounding) self.level = 0;
        self.beginSegment(0, rate);
    }

    fn beginSegment(self: *Voice, index: u8, rate: f32) void {
        const segment = self.tone.envelope.segments[index];
        self.segment = index;
        self.from_level = self.level;
        self.elapsed = 0;
        self.length = msSamples(segment.ms, rate);
        self.stage = .running;
        if (self.length == 0) self.endSegment(rate);
    }

    /// The segment has reached its level: hold there, go on, loop, or end.
    fn endSegment(self: *Voice, rate: f32) void {
        const envelope = self.tone.envelope;
        self.level = level(envelope.segments[self.segment].level);
        if (self.gate and envelope.release == self.segment) {
            self.stage = .holding;
            return;
        }
        var next = self.segment + 1;
        if (next >= envelope.count) {
            if (self.gate and envelope.loop >= 0 and envelope.loop < envelope.count) {
                next = @intCast(envelope.loop);
                // A loop of segments that all take no time would never end.
                if (self.loopTakesNoTime(rate)) {
                    self.stage = .done;
                    if (self.level == 0 and self.held_instrument == null) self.silence();
                    return;
                }
            } else {
                self.stage = .done;
                // Ended at 0: silent, as a rest is (and no more a source of RING). A voice
                // that VOICE-HOLD holds stays, at 0, so that only R13 (a new note) starts
                // its envelope again.
                if (self.level == 0 and self.held_instrument == null) self.silence();
                return;
            }
        }
        self.beginSegment(next, rate);
    }

    fn loopTakesNoTime(self: *const Voice, rate: f32) bool {
        const envelope = self.tone.envelope;
        var i: usize = @intCast(envelope.loop);
        while (i < envelope.count) : (i += 1) {
            if (msSamples(envelope.segments[i].ms, rate) != 0) return false;
        }
        return true;
    }

    fn stepEnvelope(self: *Voice, rate: f32) void {
        if (self.stage != .running) return;
        self.elapsed += 1;
        if (self.elapsed >= self.length) return self.endSegment(rate);
        const segment = self.tone.envelope.segments[self.segment];
        const target = level(segment.level);
        const t = @as(f32, @floatFromInt(self.elapsed)) / @as(f32, @floatFromInt(self.length));
        self.level = if (segment.curve == 0)
            self.from_level + (target - self.from_level) * t
        else if (self.from_level < exponential_floor and target < exponential_floor)
            self.from_level + (target - self.from_level) * t
        else exponential: {
            const a = @max(self.from_level, exponential_floor);
            const b = @max(target, exponential_floor);
            break :exponential a * std.math.pow(f32, b / a, t);
        };
    }

    /// VOICE-HOLD with the instrument the voice already holds: the note goes on with the
    /// instrument's settings as they are now (the wave, the duty, the filter, and the
    /// others), so that they can change while it sounds. The envelope goes on as the
    /// note started it, and the filter keeps what it has heard.
    pub fn retone(self: *Voice, tone: Tone, sample: pcm.Sample, rate: f32) void {
        const envelope = self.tone.envelope;
        const had_filter = self.tone.filter != .none;
        self.tone = tone;
        self.tone.envelope = envelope;
        if (tone.wave == .sample and !std.meta.eql(self.sample, sample)) {
            self.sample = sample;
            self.position = 0;
        }
        if (!had_filter) {
            self.ic1 = 0;
            self.ic2 = 0;
        }
        self.tuneFilter(rate);
    }

    pub fn setFilter(self: *Voice, rate: f32) void {
        self.ic1 = 0;
        self.ic2 = 0;
        self.tuneFilter(rate);
    }

    fn tuneFilter(self: *Voice, rate: f32) void {
        if (self.tone.filter == .none) return;
        const cutoff = std.math.clamp(@as(f32, @floatFromInt(self.tone.filter_hz)), @min(10, rate * 0.45), rate * 0.45);
        const g = std.math.tan(std.math.pi * cutoff / rate);
        // Resonance 0 is a Q of 0.5; the full value comes close to self-oscillation.
        const k = 2.0 - 1.98 * @as(f32, @floatFromInt(self.tone.resonance)) / 65535.0;
        self.filter_k = k;
        self.filter_a1 = 1.0 / (1.0 + g * (g + k));
        self.filter_a2 = g * self.filter_a1;
        self.filter_a3 = g * self.filter_a2;
    }

    fn filtered(self: *Voice, x: f32) f32 {
        if (self.tone.filter == .none) return x;
        // A state-variable filter in the topology-preserving form (stable at any cutoff).
        const v3 = x - self.ic2;
        const v1 = self.filter_a1 * self.ic1 + self.filter_a2 * v3;
        const v2 = self.ic2 + self.filter_a2 * self.ic1 + self.filter_a3 * v3;
        self.ic1 = 2 * v1 - self.ic1;
        self.ic2 = 2 * v2 - self.ic2;
        const low = v2;
        const high = x - self.filter_k * v1 - v2;
        return switch (self.tone.filter) {
            .none => x,
            .low_pass => low,
            .band_pass => v1,
            .high_pass => high,
            .notch => low + high,
        };
    }

    pub fn shiftNoise(self: *Voice) void {
        const bits: u5 = @intCast(std.math.clamp(self.tone.noise_bits, 1, 32) - 1);
        const tap: u5 = @intCast(@min(self.tone.noise_tap, bits));
        const feedback = (self.lfsr ^ (self.lfsr >> tap)) & 1;
        self.lfsr = (self.lfsr >> 1) | (feedback << bits);
        if (self.lfsr == 0) self.lfsr = 1;
        self.noise_high = self.lfsr & 1 != 0;
    }

    /// The oscillator's next value for `increment` of a cycle a sample.
    /// `noise_increment` is the note's cycle a sample without the limit of half the rate,
    /// so that a fast noise (the NES's shortest period) keeps its rate.
    fn oscillate(self: *Voice, increment: f32, noise_increment: f64, pool: []const i16, rate: f32) f32 {
        const phase = self.phase;
        var value: f32 = switch (self.tone.wave) {
            .square => pulse(phase, increment, 0.5),
            .pulse => pulse(phase, increment, quantizeDuty(&self.tone, @as(f32, @floatFromInt(self.tone.duty)) / 65536.0)),
            .triangle => 1.0 - 4.0 * @abs(phase - 0.5),
            .saw => 2.0 * phase - 1.0 - polyBlep(phase, increment),
            .noise => 0,
            .wavetable => table: {
                const table = self.tone.table;
                if (table.length == 0) break :table 0;
                const place = phase * @as(f32, @floatFromInt(table.length));
                const index: u64 = @min(@as(u64, @intFromFloat(place)), table.length - 1);
                const at = @as(u64, table.start) + index;
                if (at >= pool.len) break :table 0;
                const value = @as(f32, @floatFromInt(pool[@intCast(at)])) / 32768.0;
                if (self.tone.interpolation == .none) break :table value;
                // Linear: toward the next value, the first after the last.
                const next_at = @as(u64, table.start) + (index + 1) % table.length;
                if (next_at >= pool.len) break :table value;
                const next = @as(f32, @floatFromInt(pool[@intCast(next_at)])) / 32768.0;
                const t = std.math.clamp(place - @as(f32, @floatFromInt(index)), 0, 1);
                break :table value + (next - value) * t;
            },
            .sample => self.samplePlay(pool, rate),
            .external => self.external,
        };
        if (self.tone.wave == .noise or self.tone.noise_mix != .none) {
            self.noise_phase += if (self.tone.noise_rate > 0)
                @as(f64, @floatFromInt(self.tone.noise_rate)) / 1000.0 / @as(f64, rate)
            else
                noise_increment * noise_shifts_per_cycle;
            while (self.noise_phase >= 1) {
                self.noise_phase -= 1;
                self.shiftNoise();
            }
            const noise: f32 = if (self.noise_high) 1 else -1;
            if (self.tone.wave == .noise) {
                value = noise;
            } else switch (self.tone.noise_mix) {
                .none => {},
                .add => value = (value + noise) * 0.5,
                .gate => value = if (value > 0 and self.noise_high) 1 else -1,
            }
        }
        return value;
    }

    fn samplePlay(self: *Voice, pool: []const i16, rate: f32) f32 {
        const s = self.sample;
        if (s.length == 0 or s.rate == 0) return 0;
        const index: u64 = @intFromFloat(self.position);
        const at = @as(u64, s.start) + index;
        if (index >= s.length or at >= pool.len) {
            self.ends +%= 1;
            self.silence();
            return 0;
        }
        var value = @as(f32, @floatFromInt(pool[@intCast(at)])) / 32768.0;
        if (self.tone.interpolation == .linear) {
            // Toward the next value: the loop's start after its end, none after the last.
            var next_index = index + 1;
            if (s.loops() and next_index >= s.loop_end) next_index = s.loop_start;
            const next_at = @as(u64, s.start) + next_index;
            if (next_index < s.length and next_at < pool.len) {
                const next = @as(f32, @floatFromInt(pool[@intCast(next_at)])) / 32768.0;
                const t: f32 = @floatCast(self.position - @floor(self.position));
                value += (next - value) * t;
            }
        }
        const step = @as(f64, @floatFromInt(s.rate)) / @as(f64, rate) * @as(f64, self.currentHz()) / sample_base_hz;
        self.position += step;
        if (s.loops() and self.position >= @as(f64, @floatFromInt(s.loop_end))) {
            // However many times this step passed the loop.
            const span: f64 = @floatFromInt(s.loop_end - s.loop_start);
            const passes = @floor((self.position - @as(f64, @floatFromInt(s.loop_end))) / span) + 1;
            self.position -= passes * span;
            self.ends +%= @intFromFloat(@min(passes, 4294967295.0));
        }
        return value;
    }

    fn currentHz(self: *const Voice) f32 {
        return self.sounding_hz;
    }

    /// The sample's position (VOICE-POS), or -1 when the voice plays no sample.
    pub fn samplePosition(self: *const Voice) i64 {
        if (!self.active or self.tone.wave != .sample) return -1;
        return @intFromFloat(self.position);
    }
};

/// The 16 voices together: one sample of each, with their modulation of each other.
pub const Bank = struct {
    voices: [voice_count]Voice = @splat(.{}),
    rate: f32,
    mixer: Mixer = .linear,

    pub const Frame = struct { left: f32 = 0, right: f32 = 0, reverb_left: f32 = 0, reverb_right: f32 = 0 };

    pub fn init(sample_rate: u32) Bank {
        return .{ .rate = @floatFromInt(@max(sample_rate, 1)) };
    }

    /// The source voice `n` (1 to 16), as it was after its last sample: this sample's for
    /// the voices before the one asking, the sample before for the others.
    fn source(self: *const Bank, n: u8) ?*const Voice {
        if (n == 0 or n > voice_count) return null;
        return &self.voices[n - 1];
    }

    pub fn next(self: *Bank, pool: []const i16) Frame {
        var frame: Frame = .{};
        var nes: [4]f32 = @splat(0);
        for (&self.voices, 0..) |*voice, index| {
            if (!voice.active) {
                voice.wrapped = false;
                continue;
            }
            const tone = voice.tone;
            voice.played +%= 1;
            if (voice.limit > 0 and voice.gate and voice.played >= voice.limit) voice.noteOff(self.rate);
            if (!voice.active) continue;
            self.advancePitch(voice);
            var hz = voice.hz;
            if (tone.vibrato_cents > 0 and tone.vibrato_hz > 0) {
                if (voice.vibrato_wait > 0) {
                    voice.vibrato_wait -= 1;
                } else {
                    voice.vibrato_phase += @as(f32, @floatFromInt(tone.vibrato_hz)) / self.rate;
                    if (voice.vibrato_phase >= 1) voice.vibrato_phase -= 1;
                    hz *= cents(@as(f32, @floatFromInt(tone.vibrato_cents)) * @sin(2 * std.math.pi * voice.vibrato_phase));
                }
            }
            if (self.source(tone.pitch_mod)) |src| hz *= cents(@as(f32, @floatFromInt(tone.pitch_mod_cents)) * src.out);
            if (self.source(tone.sync)) |src| {
                if (src.wrapped) voice.phase = 0;
            }
            if (tone.pitch_mode != .none) {
                // A sample's steps are those of its rate (as Paula's period sets it).
                if (tone.wave == .sample and voice.sample.rate > 0) {
                    const scale = @as(f32, @floatFromInt(voice.sample.rate)) / sample_base_hz;
                    hz = quantizePitch(&tone, hz * scale) / scale;
                } else {
                    hz = quantizePitch(&tone, hz);
                }
            }
            voice.sounding_hz = if (std.math.isFinite(hz)) std.math.clamp(hz, 0, self.rate * 0.5) else 0;
            const increment = @min(voice.sounding_hz / self.rate, 0.5);
            const noise_increment: f64 = if (std.math.isFinite(hz)) std.math.clamp(@as(f64, hz), 0, max_noise_hz) / @as(f64, self.rate) else 0;
            var value = voice.oscillate(increment, noise_increment, pool, self.rate);
            if (!voice.active) continue;
            voice.phase += increment;
            voice.wrapped = voice.phase >= 1;
            if (voice.wrapped) voice.phase -= @floor(voice.phase);
            if (self.source(tone.ring)) |src| value *= src.osc;
            voice.osc = value;
            voice.stepEnvelope(self.rate);
            var amplitude = voice.level * voice.volume;
            if (self.source(tone.volume_mod)) |src| {
                const depth = @as(f32, @floatFromInt(tone.volume_mod_depth)) / 65535.0;
                amplitude *= (1 - depth) + depth * (src.out + 1) * 0.5;
            }
            amplitude = quantizeVolume(&tone, amplitude);
            if (voice.muted) amplitude = 0;
            const out = voice.filtered(value * amplitude);
            voice.out = out;
            if (voice.stage == .done and voice.level == 0 and !voice.gate) voice.active = false;
            if (tone.mod_only) continue;
            if (self.mixer == .nes and index < 4) {
                // The APU's inputs are levels 0 to 15: the wave from 0 up to the volume.
                const input = 15 * amplitude * (std.math.clamp(value, -1, 1) + 1) * 0.5;
                nes[index] += input;
                continue;
            }
            const left = out * @as(f32, @floatFromInt(tone.pan_left)) / 65535.0;
            const right = out * @as(f32, @floatFromInt(tone.pan_right)) / 65535.0;
            frame.left += left;
            frame.right += right;
            if (tone.reverb_send > 0) {
                const send = @as(f32, @floatFromInt(tone.reverb_send)) / 65535.0;
                frame.reverb_left += left * send;
                frame.reverb_right += right * send;
            }
        }
        if (self.mixer == .nes) {
            // The APU's mixer (NESdev Wiki): voices 1 and 2 the pulses, 3 the triangle,
            // 4 the noise; at most about 0.49, so twice that, on both sides.
            const pulses = nes[0] + nes[1];
            const pulse_out: f32 = if (pulses <= 0) 0 else 95.88 / (8128.0 / pulses + 100.0);
            const tnd_in = nes[2] / 8227.0 + nes[3] / 12241.0;
            const tnd_out: f32 = if (tnd_in <= 0) 0 else 159.79 / (1.0 / tnd_in + 100.0);
            const mixed = (pulse_out + tnd_out) * 2;
            frame.left += mixed;
            frame.right += mixed;
        }
        return frame;
    }

    /// The portamento and the sweep, a sample at a time.
    fn advancePitch(self: *Bank, voice: *Voice) void {
        const tone = voice.tone;
        if (voice.glide_left > 0) {
            voice.glide_left -= 1;
            const t = 1.0 - @as(f32, @floatFromInt(voice.glide_left)) / @as(f32, @floatFromInt(voice.glide_total));
            voice.hz = voice.glide_from * std.math.pow(f32, voice.glide_to / voice.glide_from, t);
        }
        if (tone.sweep_ms > 0 and tone.sweep_cents != 0) {
            if (voice.sweep_left > 0) voice.sweep_left -= 1;
            if (voice.sweep_left == 0) {
                voice.hz *= cents(@floatFromInt(tone.sweep_cents));
                voice.sweep_left = msSamples(tone.sweep_ms, self.rate);
                if (voice.glide_left > 0) {
                    voice.glide_from *= cents(@floatFromInt(tone.sweep_cents));
                    voice.glide_to *= cents(@floatFromInt(tone.sweep_cents));
                }
            }
        }
        if (tone.sweep_low_hz != 0 or tone.sweep_high_hz != 0) {
            const low: f32 = @floatFromInt(tone.sweep_low_hz);
            const high: f32 = if (tone.sweep_high_hz == 0) std.math.floatMax(f32) else @floatFromInt(tone.sweep_high_hz);
            voice.muted = voice.hz < low or voice.hz > high;
        }
    }
};

/// The 12 semitones from A up, as ratios of frequency.
const semitone_ratios = [12]f64{ 1.0, 1.0594630943592953, 1.122462048309373, 1.189207115002721, 1.2599210498948732, 1.3348398541700344, 1.4142135623730951, 1.4983070768766815, 1.5874010519681994, 1.681792830507429, 1.7817974362806785, 1.8877486253633868 };

/// The frequency of a note (octave × 12 + semitone, as sound_mml's Event.note) in equal
/// temperament with O4's A at 440 Hz.
pub fn noteFrequency(note: u8) f64 {
    const distance = @as(i32, note) - 57;
    var frequency = 440.0 * semitone_ratios[@intCast(@mod(distance, 12))];
    var octaves = @divFloor(distance, 12);
    while (octaves > 0) : (octaves -= 1) frequency *= 2;
    while (octaves < 0) : (octaves += 1) frequency /= 2;
    return frequency;
}

fn level(value: u16) f32 {
    return @as(f32, @floatFromInt(value)) / 65535.0;
}

fn msSamples(ms: u32, rate: f32) u32 {
    const samples = @round(@as(f64, @floatFromInt(ms)) * @as(f64, rate) / 1000.0);
    return @intFromFloat(@min(samples, 4294967295.0));
}

/// The ratio of frequency `c` cents up.
pub fn cents(c: f32) f32 {
    return std.math.exp2(c / 1200.0);
}

/// A pulse from -1 to 1, high for `duty` of each cycle, with both steps band-limited.
fn pulse(phase: f32, increment: f32, duty: f32) f32 {
    var value: f32 = if (phase < duty) 1 else -1;
    value += polyBlep(phase, increment);
    var fall = phase - duty;
    if (fall < 0) fall += 1;
    value -= polyBlep(fall, increment);
    return value;
}

/// The correction to a step of height 2 at phase 0 for an oscillator moving `increment`
/// of its cycle a sample (PolyBLEP): it spreads the step over two samples.
fn polyBlep(phase: f32, increment: f32) f32 {
    if (increment <= 0) return 0;
    if (phase < increment) {
        const x = phase / increment;
        return x + x - x * x - 1;
    }
    if (phase > 1 - increment) {
        const x = (phase - 1) / increment;
        return x * x + x + x + 1;
    }
    return 0;
}

/// MML's `V0` to `V15`: 3 dB a step down from `V15`, and `V0` silent (1189 decision).
pub fn mmlVolume(v: u8) f32 {
    if (v == 0) return 0;
    return std.math.pow(f32, 10.0, -3.0 * @as(f32, @floatFromInt(15 - @min(v, 15))) / 20.0);
}

/// MML's `S` shape (0 to 15) with the period `M` as an ENVELOPE, in the PSG's time on the
/// MSX: one ramp up or down (the PSG's 16 steps) takes 256 × M / 1789773 seconds (1189
/// and 1190 decisions). The steps go evenly in decibels (the exponential curve).
pub fn mmlEnvelope(shape: u8, period: u16) Envelope {
    const ramp_ms: u32 = @intFromFloat(@round(256.0 * @as(f64, @floatFromInt(@max(period, 1))) * 1000.0 / 1789773.0));
    const ms = @max(ramp_ms, 1);
    const full: u16 = 65535;
    var e: Envelope = .{};
    const S = Segment;
    switch (shape & 15) {
        // \___ : down once and stay at 0.
        0...3, 9 => {
            e.segments[0] = S{ .level = full, .ms = 0 };
            e.segments[1] = S{ .level = 0, .ms = ms, .curve = 1 };
            e.count = 2;
        },
        // /___ : up once, then 0.
        4...7, 15 => {
            e.segments[0] = S{ .level = full, .ms = ms, .curve = 1 };
            e.segments[1] = S{ .level = 0, .ms = 0 };
            e.count = 2;
        },
        // \\\\ : down again and again.
        8 => {
            e.segments[0] = S{ .level = full, .ms = 0 };
            e.segments[1] = S{ .level = 0, .ms = ms, .curve = 1 };
            e.count = 2;
            e.loop = 0;
        },
        // \/\/ : down and up.
        10 => {
            e.segments[0] = S{ .level = full, .ms = 0 };
            e.segments[1] = S{ .level = 0, .ms = ms, .curve = 1 };
            e.segments[2] = S{ .level = full, .ms = ms, .curve = 1 };
            e.count = 3;
            e.loop = 1;
        },
        // \¯¯¯ : down once, then full.
        11 => {
            e.segments[0] = S{ .level = full, .ms = 0 };
            e.segments[1] = S{ .level = 0, .ms = ms, .curve = 1 };
            e.segments[2] = S{ .level = full, .ms = 0 };
            e.count = 3;
        },
        // //// : up again and again.
        12 => {
            e.segments[0] = S{ .level = full, .ms = ms, .curve = 1 };
            e.segments[1] = S{ .level = 0, .ms = 0 };
            e.count = 2;
            e.loop = 0;
        },
        // /¯¯¯ : up once and stay.
        13 => {
            e.segments[0] = S{ .level = full, .ms = ms, .curve = 1 };
            e.count = 1;
        },
        // /\/\ : up and down.
        14 => {
            e.segments[0] = S{ .level = full, .ms = ms, .curve = 1 };
            e.segments[1] = S{ .level = 0, .ms = ms, .curve = 1 };
            e.count = 2;
            e.loop = 0;
        },
        else => unreachable,
    }
    return e;
}
