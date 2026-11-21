//! Tests of the standard sound's voices (src/core/sound_voice.zig, tque 1189-1).

const std = @import("std");
const voice_module = @import("../core/sound_voice.zig");
const pcm = @import("../core/sound_pcm.zig");
const Bank = voice_module.Bank;
const Tone = voice_module.Tone;

const rate: u32 = 48000;
const frate: f32 = 48000;

fn start(bank: *Bank, v: usize, tone: Tone, hz: f32) void {
    bank.voices[v].noteOn(tone, hz, 1, .{}, frate);
}

/// The times the left output goes from below 0 to 0 or above, over `samples`.
fn risingCrossings(bank: *Bank, samples: usize) usize {
    var count: usize = 0;
    var last: f32 = 0;
    for (0..samples) |_| {
        const frame = bank.next(&.{});
        if (last < 0 and frame.left >= 0) count += 1;
        last = frame.left;
    }
    return count;
}

test "square, saw and triangle at 1000 Hz cross zero 1000 times a second" {
    for ([_]voice_module.Wave{ .square, .saw, .triangle, .pulse }) |wave| {
        var bank = Bank.init(rate);
        start(&bank, 0, .{ .wave = wave, .duty = 16384 }, 1000);
        const n = risingCrossings(&bank, rate);
        try std.testing.expect(n >= 999 and n <= 1001);
    }
}

test "pan sends each side its own level, a negative one inverted" {
    var bank = Bank.init(rate);
    start(&bank, 0, .{ .wave = .square, .pan_left = 65535, .pan_right = -32768 }, 440);
    for (0..100) |_| {
        const frame = bank.next(&.{});
        try std.testing.expectApproxEqAbs(-frame.left * 32768.0 / 65535.0, frame.right, 1e-5);
    }
}

test "a linear envelope reaches half its level half way and holds at its release segment" {
    var tone: Tone = .{};
    tone.envelope.segments[0] = .{ .level = 65535, .ms = 100 };
    tone.envelope.segments[1] = .{ .level = 0, .ms = 100 };
    tone.envelope.count = 2;
    tone.envelope.release = 0;
    var bank = Bank.init(rate);
    start(&bank, 0, tone, 440);
    for (0..2400) |_| _ = bank.next(&.{});
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), bank.voices[0].level, 0.01);
    for (0..48000) |_| _ = bank.next(&.{});
    try std.testing.expectEqual(@as(f32, 1), bank.voices[0].level);
    bank.voices[0].noteOff(frate);
    for (0..2400) |_| _ = bank.next(&.{});
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), bank.voices[0].level, 0.01);
    for (0..2500) |_| _ = bank.next(&.{});
    try std.testing.expect(!bank.voices[0].active);
}

test "a note off without a release segment is silent at once" {
    var bank = Bank.init(rate);
    start(&bank, 0, .{}, 440);
    _ = bank.next(&.{});
    bank.voices[0].noteOff(frate);
    try std.testing.expect(!bank.voices[0].active);
    try std.testing.expectEqual(@as(f32, 0), bank.next(&.{}).left);
}

test "a looping envelope repeats while the note sounds" {
    const envelope = voice_module.mmlEnvelope(8, 160);
    var tone: Tone = .{ .envelope = envelope };
    tone.wave = .square;
    var bank = Bank.init(rate);
    start(&bank, 0, tone, 440);
    // 256 × 160 / 1789773 s ≈ 23 ms a ramp; after five ramps the voice still sounds.
    var highest_late: f32 = 0;
    for (0..rate / 4) |i| {
        _ = bank.next(&.{});
        if (i > rate / 8) highest_late = @max(highest_late, bank.voices[0].level);
    }
    try std.testing.expect(bank.voices[0].active);
    try std.testing.expect(highest_late > 0.9);
}

test "MML S0 decays once and stays silent; S13 rises and stays" {
    var bank = Bank.init(rate);
    start(&bank, 0, .{ .envelope = voice_module.mmlEnvelope(0, 10) }, 440);
    start(&bank, 1, .{ .envelope = voice_module.mmlEnvelope(13, 10) }, 440);
    for (0..rate / 10) |_| _ = bank.next(&.{});
    try std.testing.expect(!bank.voices[0].active);
    try std.testing.expectEqual(@as(f32, 1), bank.voices[1].level);
}

test "MML volume is 3 dB a step and V0 is silent" {
    try std.testing.expectEqual(@as(f32, 1), voice_module.mmlVolume(15));
    try std.testing.expectEqual(@as(f32, 0), voice_module.mmlVolume(0));
    try std.testing.expectApproxEqAbs(@as(f32, -42), 20 * std.math.log10(voice_module.mmlVolume(1)), 0.01);
}

test "the LFSR of 4 bits with tap 1 repeats after 15 shifts" {
    var voice: voice_module.Voice = .{ .tone = .{ .wave = .noise, .noise_bits = 4, .noise_tap = 1 } };
    var period: usize = 0;
    var state: u32 = 1;
    for (1..100) |i| {
        const feedback = (state ^ (state >> 1)) & 1;
        state = (state >> 1) | (feedback << 3);
        if (state == 1) {
            period = i;
            break;
        }
    }
    try std.testing.expectEqual(@as(usize, 15), period);
    // The voice's own shift gives the same sequence.
    var mine: u32 = 1;
    voice.lfsr = 1;
    for (0..15) |_| {
        voice.shiftNoise();
        const feedback = (mine ^ (mine >> 1)) & 1;
        mine = (mine >> 1) | (feedback << 3);
        try std.testing.expectEqual(mine, voice.lfsr);
    }
}

test "a sweep out of its limit silences the voice" {
    var bank = Bank.init(rate);
    start(&bank, 0, .{ .sweep_cents = 1200, .sweep_ms = 10, .sweep_low_hz = 100, .sweep_high_hz = 1000 }, 440);
    var loud: f32 = 0;
    for (0..rate / 100 - 1) |_| loud = @max(loud, @abs(bank.next(&.{}).left));
    try std.testing.expect(loud > 0.5);
    for (0..rate / 100 + 1) |_| _ = bank.next(&.{});
    // 440 Hz became 880 Hz then 1760 Hz, outside the limit.
    for (0..rate / 100) |_| try std.testing.expectEqual(@as(f32, 0), bank.next(&.{}).left);
}

test "a portamento goes from the last note to the next in its time" {
    var bank = Bank.init(rate);
    const tone: Tone = .{ .portamento_ms = 100 };
    start(&bank, 0, tone, 440);
    _ = bank.next(&.{});
    start(&bank, 0, tone, 880);
    for (0..rate / 20) |_| _ = bank.next(&.{});
    try std.testing.expectApproxEqRel(@as(f32, 440 * std.math.sqrt2), bank.voices[0].hz, 0.01);
    for (0..rate / 20) |_| _ = bank.next(&.{});
    try std.testing.expectApproxEqRel(@as(f32, 880), bank.voices[0].hz, 0.001);
}

test "a voice only for modulation is not heard, and ring multiplies by its source" {
    var bank = Bank.init(rate);
    // Voice 3 is voice 2 without RING, as a reference of the carrier.
    start(&bank, 0, .{ .wave = .square, .mod_only = true }, 100);
    start(&bank, 1, .{ .wave = .square, .ring = 1 }, 1000);
    start(&bank, 2, .{ .wave = .square, .mod_only = true }, 1000);
    var inverted: usize = 0;
    for (0..rate / 10) |_| {
        const frame = bank.next(&.{});
        const carrier = bank.voices[2].osc;
        try std.testing.expectApproxEqAbs(carrier * bank.voices[0].osc, frame.left, 1e-5);
        if (bank.voices[0].osc < -0.99 and carrier > 0.99) {
            try std.testing.expect(frame.left < -0.98);
            inverted += 1;
        }
    }
    try std.testing.expect(inverted > 100);
}

test "a voice that ended no more modulates by its last value" {
    var bank = Bank.init(rate);
    var short: Tone = .{ .wave = .square, .mod_only = true };
    short.envelope.segments[0] = .{ .level = 0, .ms = 5 };
    short.envelope.count = 1;
    start(&bank, 0, short, 100);
    start(&bank, 1, .{ .wave = .square, .ring = 1 }, 1000);
    for (0..rate / 100) |_| _ = bank.next(&.{});
    try std.testing.expect(!bank.voices[0].active);
    for (0..100) |_| try std.testing.expectEqual(@as(f32, 0), bank.next(&.{}).left);
}

test "an exponential segment from 0 to 0 stays silent" {
    var bank = Bank.init(rate);
    var tone: Tone = .{};
    tone.envelope.segments[0] = .{ .level = 0, .ms = 100, .curve = 1 };
    tone.envelope.segments[1] = .{ .level = 65535, .ms = 0 };
    tone.envelope.count = 2;
    tone.envelope.release = 1;
    start(&bank, 0, tone, 440);
    for (0..rate / 20) |_| try std.testing.expectEqual(@as(f32, 0), bank.next(&.{}).left);
}

test "a loop rounded to no samples ends, and long times saturate" {
    var slow = Bank.init(100);
    var tone: Tone = .{};
    tone.envelope.segments[0] = .{ .level = 65535, .ms = 1 };
    tone.envelope.count = 1;
    tone.envelope.loop = 0;
    slow.voices[0].noteOn(tone, 10, 1, .{}, slow.rate);
    _ = slow.next(&.{});
    var bank = Bank.init(rate);
    start(&bank, 0, .{ .portamento_ms = 4_000_000_000, .note_limit_ms = 4_000_000_000 }, 440);
    start(&bank, 0, .{ .portamento_ms = 4_000_000_000, .note_limit_ms = 4_000_000_000 }, 880);
    _ = bank.next(&.{});
    try std.testing.expect(bank.voices[0].active);
}

test "a sample that passes its loop more than once in a step stays in its loop" {
    var bank = Bank.init(rate);
    var data: [2]i16 = .{ 1000, 2000 };
    const sample: pcm.Sample = .{ .start = 0, .length = 2, .rate = 48000, .loop_start = 0, .loop_end = 2 };
    bank.voices[0].noteOn(.{ .wave = .sample, .sample = 0 }, voice_module.sample_base_hz * 5, 1, sample, frate);
    for (0..10) |_| {
        _ = bank.next(&data);
        const position = bank.voices[0].samplePosition();
        try std.testing.expect(position >= 0 and position < 2);
    }
    try std.testing.expect(bank.voices[0].active);
    try std.testing.expect(bank.voices[0].ends >= 20);
}

test "vibrato changes the speed of a sample" {
    var plain = Bank.init(rate);
    var wobbly = Bank.init(rate);
    var data: [48000]i16 = @splat(0);
    const sample: pcm.Sample = .{ .start = 0, .length = 48000, .rate = 48000 };
    plain.voices[0].noteOn(.{ .wave = .sample, .sample = 0 }, voice_module.sample_base_hz, 1, sample, frate);
    wobbly.voices[0].noteOn(.{ .wave = .sample, .sample = 0, .vibrato_cents = 1200, .vibrato_hz = 5 }, voice_module.sample_base_hz, 1, sample, frate);
    for (0..2400) |_| {
        _ = plain.next(&data);
        _ = wobbly.next(&data);
    }
    try std.testing.expect(wobbly.voices[0].samplePosition() > plain.voices[0].samplePosition() + 100);
}

test "sync restarts the voice's cycle when its source's cycle wraps" {
    var bank = Bank.init(rate);
    start(&bank, 0, .{ .mod_only = true }, 100);
    start(&bank, 1, .{ .wave = .saw, .sync = 1 }, 330);
    for (0..rate) |_| {
        _ = bank.next(&.{});
        if (bank.voices[0].wrapped) try std.testing.expect(bank.voices[1].phase < 330.0 / frate + 1e-6);
    }
}

test "a low-pass filter takes most of a tone far above its cutoff" {
    var plain = Bank.init(rate);
    var low = Bank.init(rate);
    start(&plain, 0, .{ .wave = .saw }, 8000);
    start(&low, 0, .{ .wave = .saw, .filter = .low_pass, .filter_hz = 500 }, 8000);
    var plain_sum: f32 = 0;
    var low_sum: f32 = 0;
    for (0..rate / 10) |_| {
        plain_sum += @abs(plain.next(&.{}).left);
        low_sum += @abs(low.next(&.{}).left);
    }
    try std.testing.expect(low_sum < plain_sum * 0.1);
}

test "a note limit stops the note, and a sample counts its end" {
    var bank = Bank.init(rate);
    start(&bank, 0, .{ .note_limit_ms = 10 }, 440);
    for (0..rate / 100 + 1) |_| _ = bank.next(&.{});
    try std.testing.expect(!bank.voices[0].active);

    var data: [100]i16 = @splat(16384);
    const sample: pcm.Sample = .{ .start = 0, .length = 100, .rate = 48000 };
    bank.voices[1].noteOn(.{ .wave = .sample, .sample = 0 }, voice_module.sample_base_hz, 1, sample, frate);
    try std.testing.expectEqual(@as(i64, 0), bank.voices[1].samplePosition());
    for (0..50) |_| _ = bank.next(&data);
    try std.testing.expectEqual(@as(i64, 50), bank.voices[1].samplePosition());
    for (0..51) |_| _ = bank.next(&data);
    try std.testing.expectEqual(@as(u32, 1), bank.voices[1].ends);
    try std.testing.expectEqual(@as(i64, -1), bank.voices[1].samplePosition());
}

test "volume modulation follows its source's output" {
    var bank = Bank.init(rate);
    start(&bank, 0, .{ .wave = .square, .mod_only = true }, 50);
    start(&bank, 1, .{ .wave = .square, .volume_mod = 1, .volume_mod_depth = 65535 }, 2000);
    for (0..rate / 10) |_| {
        const frame = bank.next(&.{});
        // When the source is at -1, the voice is silent.
        if (bank.voices[0].out < -0.99) try std.testing.expect(@abs(frame.left) < 0.02);
    }
}

test "a huge pitch modulation and a slow rate with a filter stay finite" {
    var bank = Bank.init(rate);
    var data: [64]i16 = @splat(100);
    const sample: pcm.Sample = .{ .start = 0, .length = 64, .rate = 48000, .loop_start = 0, .loop_end = 64 };
    start(&bank, 0, .{ .wave = .square, .mod_only = true }, 100);
    bank.voices[1].noteOn(.{ .wave = .sample, .sample = 0, .pitch_mod = 1, .pitch_mod_cents = 153600 }, voice_module.sample_base_hz, 1, sample, frate);
    for (0..1000) |_| {
        const frame = bank.next(&data);
        try std.testing.expect(std.math.isFinite(frame.left));
    }
    var slow = Bank.init(0);
    slow.voices[0].noteOn(.{ .filter = .low_pass, .filter_hz = 1000 }, 0.1, 1, .{}, slow.rate);
    for (0..10) |_| try std.testing.expect(std.math.isFinite(slow.next(&.{}).left));
}

// ---- 1198: the effects on all the voices together ----

const master_module = @import("../core/sound_master.zig");

test "the reverb repeats what is sent to it after its delay, smaller by its feedback" {
    const m = try std.testing.allocator.create(master_module.Master);
    defer std.testing.allocator.destroy(m);
    m.* = master_module.Master.init(rate);
    m.setReverb(10, 32768, 65535);
    // One impulse sent to the reverb: it comes back 480 frames later, then again.
    var heard: [3]f32 = .{ 0, 0, 0 };
    for (0..1500) |i| {
        const send: f32 = if (i == 0) 1 else 0;
        const out = m.process(0, 0, send, send);
        if (i == 480) heard[0] = out[0];
        if (i == 960) heard[1] = out[0];
        if (i == 1440) heard[2] = out[0];
    }
    try std.testing.expectApproxEqAbs(@as(f32, 1), heard[0], 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 32768.0 / 65535.0), heard[1], 1e-4);
    try std.testing.expect(heard[2] > 0.2 and heard[2] < 0.3);
    // Volume 0 turns it off and empties it: on again, nothing sent before comes back.
    _ = m.process(0, 0, 1, 1);
    m.setReverb(10, 32768, 0);
    for (0..1000) |_| try std.testing.expectEqual(@as(f32, 0), m.process(0, 0, 1, 1)[0]);
    m.setReverb(10, 32768, 65535);
    for (0..2000) |_| try std.testing.expectEqual(@as(f32, 0), m.process(0, 0, 0, 0)[0]);
}

test "the reverb's FIR filters the echo, and the master volume and filter apply to all" {
    const m = try std.testing.allocator.create(master_module.Master);
    defer std.testing.allocator.destroy(m);
    m.* = master_module.Master.init(rate);
    // The first echo is the delay itself; the FIR (0.75, 0.25) shapes what goes back.
    m.setReverb(1, 65535, 65535);
    m.setFir(&.{ 96, 32 });
    var heard: [200]f32 = undefined;
    for (&heard, 0..) |*h, i| h.* = m.process(0, 0, if (i == 0) 1 else 0, 0)[0];
    try std.testing.expectApproxEqAbs(@as(f32, 1), heard[48], 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 0), heard[49], 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 0.75), heard[96], 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, 0.25), heard[97], 1e-4);

    const v = try std.testing.allocator.create(master_module.Master);
    defer std.testing.allocator.destroy(v);
    v.* = master_module.Master.init(rate);
    v.setVolume(32768);
    try std.testing.expectApproxEqAbs(@as(f32, 0.25), v.process(0.5, 0.5, 0, 0)[0], 1e-4);
    v.setVolume(65535);
    v.setFilter(.low_pass, 200);
    var sum: f32 = 0;
    for (0..rate / 10) |i| sum += @abs(v.process(if (i % 4 < 2) 1 else -1, 0, 0, 0)[0]);
    try std.testing.expect(sum < @as(f32, rate / 10) * 0.05);
}

fn tonePeak(m: *master_module.Master, hz: f32) f32 {
    var peak: f32 = 0;
    for (0..rate) |i| {
        const x = @sin(2 * std.math.pi * hz * @as(f32, @floatFromInt(i)) / frate);
        const out = m.process(x, x, 0, 0)[0];
        if (i > rate / 2) peak = @max(peak, @abs(out));
    }
    return peak;
}

test "TONE-CONTROL raises the bass and leaves the middle, and the treble reaches its dB" {
    const m = try std.testing.allocator.create(master_module.Master);
    defer std.testing.allocator.destroy(m);
    m.* = master_module.Master.init(rate);
    m.setTone(12, 0);
    // +12 dB is about 4 times; below the shelf's corner it comes close.
    try std.testing.expect(tonePeak(m, 20) > 3.5);
    const middle = tonePeak(m, 1000);
    try std.testing.expect(middle > 0.95 and middle < 1.3);
    // -12 dB at half the rate: the alternating +1 -1 comes out at 10^(-12/20).
    m.* = master_module.Master.init(rate);
    m.setTone(0, -12);
    var last: f32 = 0;
    for (0..rate / 10) |i| last = m.process(if (i % 2 == 0) 1 else -1, 0, 0, 0)[0];
    try std.testing.expectApproxEqAbs(std.math.pow(f32, 10, -12.0 / 20.0), @abs(last), 0.01);
}

test "turning TONE-CONTROL on again does not bring back sound from before" {
    const m = try std.testing.allocator.create(master_module.Master);
    defer std.testing.allocator.destroy(m);
    m.* = master_module.Master.init(rate);
    m.setTone(12, 0);
    for (0..rate) |_| _ = m.process(1, 1, 0, 0);
    m.setTone(0, 0);
    for (0..rate) |_| _ = m.process(0, 0, 0, 0);
    m.setTone(12, 0);
    try std.testing.expect(@abs(m.process(0, 0, 0, 0)[0]) < 1e-3);
}

// ---- The steps of a chip (tque 1190, 3.5 of the study) ----

test "PITCH-PERIOD rounds to a whole period and keeps it within its range" {
    // The MSX's PSG: 1789773 Hz / (16 x period), periods 1 to 4095.
    const psg: Tone = .{ .pitch_mode = .period, .pitch_clock = 1_789_773_000, .pitch_divider = 16, .pitch_min = 1, .pitch_max = 4095 };
    try std.testing.expectApproxEqRel(@as(f32, 1789773.0 / (16.0 * 254.0)), voice_module.quantizePitch(&psg, 440), 1e-6);
    // Below the lowest: the longest period.
    try std.testing.expectApproxEqRel(@as(f32, 1789773.0 / (16.0 * 4095.0)), voice_module.quantizePitch(&psg, 5), 1e-6);
    // The offset: the SCC's 3579545 / (32 x (period + 1)).
    const scc: Tone = .{ .pitch_mode = .period, .pitch_clock = 3_579_545_000, .pitch_divider = 32, .pitch_offset = 1, .pitch_min = 0, .pitch_max = 4095 };
    try std.testing.expectApproxEqRel(@as(f32, 3579545.0 / (32.0 * 254.0)), voice_module.quantizePitch(&scc, 440), 1e-6);
    // No steps: as it is.
    try std.testing.expectEqual(@as(f32, 440), voice_module.quantizePitch(&.{}, 440));
}

test "PITCH-STEP rounds to clock x n / 2^bits" {
    // The SID on a PAL C64: 985248 Hz x n / 2^24.
    const sid: Tone = .{ .pitch_mode = .step, .pitch_clock = 985_248_000, .pitch_bits = 24 };
    try std.testing.expectApproxEqRel(@as(f32, 7493.0 * 985248.0 / 16777216.0), voice_module.quantizePitch(&sid, 440), 1e-6);
}

test "a sample's PITCH-PERIOD steps are those of its rate" {
    var bank = Bank.init(rate);
    // Paula: 3546895 / period samples a second. A sample of 8287 Hz at O4's C plays at
    // its own rate, which is period 428 exactly; a little higher rounds back to it.
    const tone: Tone = .{ .wave = .sample, .pitch_mode = .period, .pitch_clock = 3_546_895_000, .pitch_divider = 1, .pitch_min = 124, .pitch_max = 65535 };
    var pool: [64]i16 = @splat(1000);
    const sample: pcm.Sample = .{ .start = 0, .length = 64, .rate = 8287, .loop_start = 0, .loop_end = 64 };
    bank.voices[0].noteOn(tone, voice_module.sample_base_hz * 1.0005, 1, sample, frate);
    _ = bank.next(&pool);
    const expected = 3546895.0 / 428.0 / 8287.0 * voice_module.sample_base_hz;
    try std.testing.expectApproxEqRel(@as(f32, expected), bank.voices[0].sounding_hz, 1e-5);
}

test "VOLUME-STEPS rounds to the nearest level in decibels" {
    var tone: Tone = .{ .volume_step_count = 5 };
    tone.volume_steps[0..5].* = .{ 0, 1000, 4000, 16000, 65535 };
    const q = struct {
        fn at(t: *const Tone, n: f32) f32 {
            return voice_module.quantizeVolume(t, n / 65535.0) * 65535.0;
        }
    };
    try std.testing.expectApproxEqAbs(@as(f32, 0), q.at(&tone, 400), 1e-2);
    try std.testing.expectApproxEqAbs(@as(f32, 1000), q.at(&tone, 600), 1e-2);
    // Between 1000 and 4000 the boundary is 2000, not 2500.
    try std.testing.expectApproxEqAbs(@as(f32, 1000), q.at(&tone, 1900), 1e-2);
    try std.testing.expectApproxEqAbs(@as(f32, 4000), q.at(&tone, 2100), 1e-2);
    try std.testing.expectApproxEqAbs(@as(f32, 65535), q.at(&tone, 70000), 1e-2);
    try std.testing.expectApproxEqAbs(@as(f32, 300), q.at(&.{}, 300), 1e-2);
}

test "DUTY-STEPS rounds the duty and keeps it inside the cycle" {
    const tone: Tone = .{ .duty_steps = 4 };
    try std.testing.expectEqual(@as(f32, 0.25), voice_module.quantizeDuty(&tone, 0.3));
    try std.testing.expectEqual(@as(f32, 0.25), voice_module.quantizeDuty(&tone, 0.01));
    try std.testing.expectEqual(@as(f32, 0.75), voice_module.quantizeDuty(&tone, 0.99));
    try std.testing.expectEqual(@as(f32, 0.3), voice_module.quantizeDuty(&.{}, 0.3));
}

test "INTERPOLATION 1 reads a wavetable linearly, 0 in steps" {
    var pool: [2]i16 = .{ 0, 16384 };
    var heard: [2][8]f32 = undefined;
    for ([_]voice_module.Interpolation{ .none, .linear }, 0..) |mode, m| {
        var bank = Bank.init(rate);
        // An eighth of a cycle a sample.
        const tone: Tone = .{ .wave = .wavetable, .table = .{ .start = 0, .length = 2 }, .interpolation = mode };
        start(&bank, 0, tone, frate / 8);
        for (&heard[m]) |*h| h.* = bank.next(&pool).left;
    }
    try std.testing.expectEqualSlices(f32, &.{ 0, 0, 0, 0, 0.5, 0.5, 0.5, 0.5 }, &heard[0]);
    for ([_]f32{ 0, 0.125, 0.25, 0.375, 0.5, 0.375, 0.25, 0.125 }, heard[1]) |e, h| try std.testing.expectApproxEqAbs(e, h, 1e-6);
}

test "MIXER 1 mixes voices 1 to 4 with the NES's formulas, without their pan" {
    var bank = Bank.init(rate);
    bank.mixer = .nes;
    start(&bank, 0, .{ .pan_left = 0, .pan_right = 0 }, 1000);
    var high: f32 = 0;
    var low: f32 = 1;
    for (0..480) |_| {
        const frame = bank.next(&.{});
        try std.testing.expectEqual(frame.left, frame.right);
        high = @max(high, frame.left);
        low = @min(low, frame.left);
    }
    // One pulse at full volume: 15, then 0.
    try std.testing.expectApproxEqRel(@as(f32, 2 * 95.88 / (8128.0 / 15.0 + 100.0)), high, 1e-3);
    try std.testing.expectApproxEqAbs(@as(f32, 0), low, 1e-3);
    // Two pulses do not make twice one.
    start(&bank, 1, .{}, 1000);
    bank.voices[0].phase = 0;
    bank.voices[1].phase = 0;
    var both: f32 = 0;
    for (0..480) |_| both = @max(both, bank.next(&.{}).left);
    try std.testing.expectApproxEqRel(@as(f32, 2 * 95.88 / (8128.0 / 30.0 + 100.0)), both, 1e-3);
    try std.testing.expect(both < 2 * high);
}

test "OUTPUT-BITS rounds the output and holds it at its rate" {
    const m = try std.testing.allocator.create(master_module.Master);
    defer std.testing.allocator.destroy(m);
    m.* = master_module.Master.init(rate);
    // 2 bits: the four steps -1, -0.5, 0, and 0.5.
    m.setOutput(2, 0);
    try std.testing.expectEqual(@as(f32, 0.5), m.finish(.{ 0.3, -0.3 })[0]);
    try std.testing.expectEqual(@as(f32, -0.5), m.finish(.{ 0.3, -0.3 })[1]);
    try std.testing.expectEqual(@as(f32, 0.5), m.finish(.{ 1, -1 })[0]);
    try std.testing.expectEqual(@as(f32, -1), m.finish(.{ 1, -1 })[1]);
    var steps = std.AutoHashMap(i32, void).init(std.testing.allocator);
    defer steps.deinit();
    for (0..201) |i| {
        const x = @as(f32, @floatFromInt(i)) / 100 - 1;
        try steps.put(@intFromFloat(m.finish(.{ x, x })[0] * 2), {});
    }
    try std.testing.expectEqual(@as(u32, 4), steps.count());
    m.setOutput(0, 12000);
    var out: [8]f32 = undefined;
    for (&out, 0..) |*o, i| o.* = m.finish(.{ @as(f32, @floatFromInt(i)) * 0.1, 0 })[0];
    for ([_]f32{ 0, 0, 0, 0, 0.4, 0.4, 0.4, 0.4 }, out) |e, o| try std.testing.expectApproxEqAbs(e, o, 1e-6);
    m.setOutput(0, 0);
    try std.testing.expectApproxEqAbs(@as(f32, 0.7), m.finish(.{ 0.7, 0 })[0], 1e-6);
    // process no longer changes the mix.
    m.setOutput(2, 0);
    try std.testing.expectApproxEqAbs(@as(f32, 0.3), m.process(0.3, 0, 0, 0)[0], 1e-6);
}

test "NOISE-RATE shifts the noise at its own rate, apart from the note" {
    var bank = Bank.init(rate);
    // 4800 shifts a second at any note: 480 in a tenth of a second.
    start(&bank, 0, .{ .wave = .noise, .noise_rate = 4_800_000 }, 100);
    var shifts: usize = 0;
    var last = bank.voices[0].lfsr;
    for (0..rate / 10) |_| {
        _ = bank.next(&.{});
        if (bank.voices[0].lfsr != last) shifts += 1;
        last = bank.voices[0].lfsr;
    }
    try std.testing.expect(shifts >= 470 and shifts <= 481);
    // Without it, 16 a cycle of the note: 160 in a tenth of a second at 100 Hz.
    start(&bank, 1, .{ .wave = .noise }, 100);
    shifts = 0;
    last = bank.voices[1].lfsr;
    for (0..rate / 10) |_| {
        _ = bank.next(&.{});
        if (bank.voices[1].lfsr != last) shifts += 1;
        last = bank.voices[1].lfsr;
    }
    try std.testing.expect(shifts >= 155 and shifts <= 161);
    // A noise above half the rate keeps its own: the NES's period 4 (a note of
    // 1789773 / 64 Hz) moves 16 x 27965.2 / 48000 = 9.32 shifts a sample, not 8.
    var fast = Bank.init(rate);
    start(&fast, 0, .{ .wave = .noise }, 1789773.0 / 64.0);
    fast.voices[0].noise_phase = 0;
    _ = fast.next(&.{});
    try std.testing.expectApproxEqAbs(@as(f64, 1789773.0 / 4.0 / 48000.0 - 9.0), fast.voices[0].noise_phase, 1e-4);
    // The slowest, 1/1000 Hz, still moves the phase on after half a shift.
    var slow = Bank.init(rate);
    start(&slow, 0, .{ .wave = .noise, .noise_rate = 1 }, 100);
    slow.voices[0].noise_phase = 0.5;
    _ = slow.next(&.{});
    try std.testing.expect(slow.voices[0].noise_phase > 0.5);
}

test "a note on a sounding voice starts its envelope from the level the note before left" {
    // An attack of 100 ms to a sustain of half, as ADSR makes it.
    var tone: Tone = .{};
    tone.envelope.segments[0] = .{ .level = 65535, .ms = 100 };
    tone.envelope.segments[1] = .{ .level = 32768, .ms = 100 };
    tone.envelope.count = 2;
    tone.envelope.release = 1;
    var bank = Bank.init(rate);
    start(&bank, 0, tone, 440);
    for (0..48000) |_| _ = bank.next(&.{});
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), bank.voices[0].level, 0.001);
    // The next note: no step down to 0, and half way up to full after half the attack.
    start(&bank, 0, tone, 660);
    _ = bank.next(&.{});
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), bank.voices[0].level, 0.001);
    for (0..2400) |_| _ = bank.next(&.{});
    try std.testing.expectApproxEqAbs(@as(f32, 0.75), bank.voices[0].level, 0.01);
    // A voice that was silent starts from 0.
    bank.voices[0].silence();
    start(&bank, 0, tone, 440);
    _ = bank.next(&.{});
    try std.testing.expect(bank.voices[0].level < 0.01);
}
