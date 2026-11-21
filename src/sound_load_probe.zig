//! The load of the standard sound's 16 voices (tque 1201). A separate program, never
//! installed with Sigma's normal build: `zig build sound-load-check`.
//!
//! It renders three loads on the engine as the audio thread does, 48 kHz stereo. With
//! nothing on its standard input it only checks them (no timing); with `m` it also times
//! each (tests/scripts/measure-standard-sound-load.py, which needs the user's approval
//! first). It prints one JSON object.
const std = @import("std");
const engine_module = @import("core/sound_engine.zig");
const voice = engine_module.voice;
const pcm = engine_module.pcm;
const clock = @import("host_clock.zig");

extern "c" fn getchar() c_int;
extern "c" fn fflush(?*anyopaque) c_int;
extern "c" fn puts([*:0]const u8) c_int;

const rate = 48000;
/// Ten seconds of sound for each load.
const frames = rate * 10;
const block = 480;
const rounds = 7;
const table_length = 256;

const Load = enum { square16, full16, table16 };

fn envelope() voice.Envelope {
    var e: voice.Envelope = .{ .count = 3, .loop = 1, .release = -1 };
    e.segments[0] = .{ .level = 65535, .ms = 5, .curve = 0 };
    e.segments[1] = .{ .level = 20000, .ms = 120, .curve = 1 };
    e.segments[2] = .{ .level = 65535, .ms = 80, .curve = 0 };
    return e;
}

/// Sets up `load` on a fresh engine: all 16 voices sound from the start.
fn setUp(engine: *engine_module.Engine, load: Load, pool: []i16) void {
    engine.* = engine_module.Engine.init(rate);
    for (pool[0..table_length], 0..) |*x, i| {
        const t = @as(f32, @floatFromInt(i)) / table_length;
        x.* = @intFromFloat(@sin(2 * std.math.pi * t) * 20000 + @sin(6 * std.math.pi * t) * 8000);
    }
    engine.pool = pool;
    const table: pcm.Sample = .{ .start = 0, .length = table_length };
    const sample: pcm.Sample = .{ .start = 0, .length = table_length, .rate = 16000, .loop_start = 0, .loop_end = table_length };
    for (&engine.bank.voices, 0..) |*v, i| {
        const n: u8 = @intCast(i);
        var tone: voice.Tone = .{};
        var hz: f32 = 110 * std.math.pow(f32, 2, @as(f32, @floatFromInt(i)) / 7);
        var source: pcm.Sample = .{};
        switch (load) {
            .square16 => {},
            .full16 => {
                tone.wave = switch (i % 5) {
                    0 => .square,
                    1 => .pulse,
                    2 => .triangle,
                    3 => .saw,
                    else => .noise,
                };
                tone.duty = 16384;
                tone.noise_mix = if (i % 5 == 4) .none else .add;
                tone.envelope = envelope();
                tone.vibrato_cents = 30;
                tone.vibrato_hz = 6;
                tone.pitch_mod = if (i == 0) 16 else n;
                tone.pitch_mod_cents = 50;
                tone.volume_mod = if (i == 15) 1 else n + 2;
                tone.volume_mod_depth = 16384;
                tone.ring = if (i % 2 == 1) n else 0;
                tone.filter = .low_pass;
                tone.filter_hz = 1500 + 200 * @as(u32, n);
                tone.resonance = 40000;
                tone.pan_left = if (i % 2 == 0) 65535 else 30000;
                tone.pan_right = if (i % 2 == 0) 30000 else 65535;
                tone.reverb_send = 20000;
                tone.sweep_cents = 1;
                tone.sweep_ms = 50;
                tone.sweep_low_hz = 20;
                tone.sweep_high_hz = 20000;
            },
            .table16 => {
                if (i % 2 == 0) {
                    tone.wave = .wavetable;
                    tone.table = table;
                } else {
                    tone.wave = .sample;
                    source = sample;
                    hz = 261.6 * std.math.pow(f32, 2, @as(f32, @floatFromInt(i)) / 12);
                }
                tone.filter = .band_pass;
                tone.filter_hz = 2000;
                tone.resonance = 20000;
                tone.reverb_send = 10000;
            },
        }
        // V8: 16 squares at V12 clip the output (16 x 0.35 x the mix gain is over 1).
        v.noteOn(tone, hz, voice.mmlVolume(8), source, engine.bank.rate);
    }
    if (load != .square16) {
        engine.master.setReverb(300, 32768, 30000);
        engine.master.setFir(&.{ 96, 16, 8, 4, 2, 1, 1, 0 });
        engine.master.setFilter(.low_pass, 8000);
        engine.master.setTone(6, -6);
    }
}

const Result = struct { sum: i64 = 0, nonzero: u32 = 0, peak: u16 = 0, sounding: u8 = 0, heard: u8 = 0, sides_differ: u32 = 0 };

/// Renders `count` frames of the load into `out` as the audio thread does, in blocks
/// of 10 ms.
fn render(engine: *engine_module.Engine, out: []i16, count: usize) void {
    var done: usize = 0;
    while (done < count) : (done += block) engine.render(out[done * 2 ..][0 .. block * 2]);
}

/// What the output and the voices show, after the rendering.
fn examine(engine: *const engine_module.Engine, out: []const i16) Result {
    var result: Result = .{};
    for (out) |x| {
        result.sum +%= x;
        if (x != 0) result.nonzero += 1;
        result.peak = @max(result.peak, @abs(x));
    }
    var i: usize = 0;
    while (i < out.len) : (i += 2) {
        if (out[i] != out[i + 1]) result.sides_differ += 1;
    }
    for (engine.bank.voices) |v| {
        if (v.active) result.sounding += 1;
    }
    return result;
}

/// The voices that reach the output: with the voice made unheard (as MOD-ONLY makes it,
/// still a source of modulation), the first second of the output must change.
fn countHeard(engine: *engine_module.Engine, load: Load, pool: []i16, first_out: []const i16, out: []i16) u8 {
    var heard: u8 = 0;
    for (0..voice.voice_count) |k| {
        setUp(engine, load, pool);
        engine.bank.voices[k].tone.mod_only = true;
        render(engine, out, rate);
        if (!std.mem.eql(i16, out[0 .. rate * 2], first_out[0 .. rate * 2])) heard += 1;
    }
    return heard;
}

pub fn main() u8 {
    const measure = getchar() == 'm';
    const allocator = std.heap.c_allocator;
    const engine = allocator.create(engine_module.Engine) catch return 2;
    defer allocator.destroy(engine);
    const pool = allocator.alloc(i16, table_length) catch return 2;
    defer allocator.free(pool);
    const first_out = allocator.alloc(i16, frames * 2) catch return 2;
    defer allocator.free(first_out);
    const out = allocator.alloc(i16, frames * 2) catch return 2;
    defer allocator.free(out);
    var line: [1024]u8 = undefined;
    _ = puts(if (measure) "{\"timing_enabled\": true, \"rate\": 48000, \"frames\": 480000, \"loads\": {" else "{\"timing_enabled\": false, \"rate\": 48000, \"frames\": 480000, \"loads\": {");
    for (std.enums.values(Load), 0..) |load, index| {
        // The untimed round, with the checks.
        setUp(engine, load, pool);
        render(engine, first_out, frames);
        var first = examine(engine, first_out);
        first.heard = countHeard(engine, load, pool, first_out, out);
        // All 16 voices sound to the end, the output is not silent or clipped, and the
        // panned load is not the same on both sides.
        const sides_ok = load != .full16 or first.sides_differ * 2 > frames;
        if (first.sounding != 16 or first.heard != 16 or first.nonzero < frames or first.peak == 0 or first.peak >= 32767 or !sides_ok) {
            var why: [160]u8 = undefined;
            _ = puts(@ptrCast(std.fmt.bufPrint(&why, "\"{s}\": sounding {d}, heard {d}, nonzero {d}, peak {d}, sides differ {d}\x00", .{ @tagName(load), first.sounding, first.heard, first.nonzero, first.peak, first.sides_differ }) catch return 6));
            return 5;
        }
        // The timed rounds: only the rendering is timed, and each must make the same
        // output, sample for sample.
        var times: [rounds]i64 = @splat(0);
        if (measure) {
            for (&times) |*t| {
                setUp(engine, load, pool);
                const start = clock.now() catch return 3;
                render(engine, out, frames);
                const stop = clock.now() catch return 3;
                if (!std.mem.eql(i16, out, first_out)) return 4;
                t.* = @intCast(stop - start);
            }
        }
        var at: usize = 0;
        at += (std.fmt.bufPrint(line[at..], "  \"{s}\": {{\"sounding\": {d}, \"heard\": {d}, \"nonzero_samples\": {d}, \"sides_differ\": {d}, \"peak\": {d}, \"sum\": {d}, \"wall_ns\": [", .{
            @tagName(load), first.sounding, first.heard, first.nonzero, first.sides_differ, first.peak, first.sum,
        }) catch return 6).len;
        if (measure) {
            for (times, 0..) |t, i| at += (std.fmt.bufPrint(line[at..], "{s}{d}", .{ if (i == 0) "" else ", ", t }) catch return 6).len;
            var sorted = times;
            std.mem.sort(i64, &sorted, {}, std.sort.asc(i64));
            const median: f64 = @floatFromInt(sorted[rounds / 2]);
            at += (std.fmt.bufPrint(line[at..], "], \"median_ns_per_frame\": {d:.1}, \"median_realtime_ratio\": {d:.1}}}", .{
                median / frames, @as(f64, frames) / rate * 1e9 / @max(median, 1),
            }) catch return 6).len;
        } else {
            at += (std.fmt.bufPrint(line[at..], "], \"median_ns_per_frame\": null, \"median_realtime_ratio\": null}}", .{}) catch return 6).len;
        }
        at += (std.fmt.bufPrint(line[at..], "{s}\x00", .{if (index + 1 < std.enums.values(Load).len) "," else ""}) catch return 6).len;
        _ = puts(@ptrCast(&line));
    }
    _ = puts("}}");
    _ = fflush(null);
    return 0;
}
