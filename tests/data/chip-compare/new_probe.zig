//! The chip comparison's new side (tque 1206): the standard sound with the settings the
//! chip libraries of include/ give (src/tests/audio_test.zig checks that the libraries
//! give these). Built in src/core by tests/scripts/compare-chip-libraries.py; prints one
//! JSON object.
const std = @import("std");
const engine_module = @import("sound_engine.zig");
const mml = @import("sound_mml.zig");
const voice = @import("sound_voice.zig");
const m = @import("measure.zig");
const cases = @import("cases.zig");

const Engine = engine_module.Engine;
const Tone = voice.Tone;

const Player = struct {
    engine: *Engine,
    buffer: [960]i16 = undefined,
    fn wait(self: *Player) bool {
        self.engine.render(&self.buffer);
        return true;
    }
};

fn table(comptime n: usize, values: [n]u16) [voice.max_volume_steps]u16 {
    var out: [voice.max_volume_steps]u16 = @splat(0);
    @memcpy(out[0..n], &values);
    return out;
}

// The levels of the libraries (include/msx-sound.fs and the others).
const ay = blk: {
    const volts = [16]f64{ 1.147, 1.162, 1.169, 1.178, 1.192, 1.213, 1.238, 1.299, 1.336, 1.457, 1.573, 1.707, 1.882, 2.06, 2.32, 2.58 };
    var v: [16]u16 = undefined;
    for (&v, volts) |*x, volt| x.* = @intFromFloat(@round((volt - volts[0]) / (volts[15] - volts[0]) * 65535));
    break :blk v;
};
fn ymLevels() [32]u16 {
    var v: [32]u16 = undefined;
    v[0] = 0;
    for (1..32) |i| v[i] = @intFromFloat(@round(std.math.pow(f64, 10, -1.5 * @as(f64, @floatFromInt(31 - i)) / 20) * 65535));
    return v;
}
fn linear(comptime n: usize) [n]u16 {
    var v: [n]u16 = undefined;
    for (&v, 0..) |*x, i| x.* = @intFromFloat(@round(@as(f64, @floatFromInt(i)) * 65535 / @as(f64, @floatFromInt(n - 1))));
    return v;
}

/// The instrument and what the library sets on all the voices.
fn setUp(engine: *Engine, case: cases.Case, pool: []i16) Tone {
    var t: Tone = .{};
    t.wave = switch (case.wave) {
        .square => .square,
        .pulse => .pulse,
        .triangle => .triangle,
        .saw => .saw,
        .noise => .noise,
        .wavetable => .wavetable,
        .sample => .sample,
    };
    t.duty = @intCast(@as(u32, case.duty_percent) * 65536 / 100);
    var limit: u8 = 8;
    // V-STEPS: MML's V as the chip's volume (V0 to V15), as each library sets it.
    var v: [16]u16 = undefined;
    switch (case.chip) {
        .msx, .st => {
            t.pitch_mode = .period;
            t.pitch_clock = if (case.chip == .msx) 1_789_773_000 else 2_000_000_000;
            t.pitch_divider = 16;
            t.pitch_min = 1;
            t.pitch_max = 4095;
            if (case.chip == .msx) {
                t.volume_step_count = 16;
                t.volume_steps = table(16, ay);
            } else {
                t.volume_step_count = 32;
                t.volume_steps = table(32, ymLevels());
            }
            t.noise_bits = 17;
            t.noise_tap = 3;
            if (case.chip == .msx) {
                v = ay;
            } else {
                const ym = ymLevels();
                v[0] = 0;
                for (1..16) |i| v[i] = ym[2 * i + 1];
            }
            limit = 3;
        },
        .nes => {
            t.pitch_mode = .period;
            t.pitch_clock = 1_789_773_000;
            t.pitch_divider = 16;
            t.pitch_offset = 1;
            t.pitch_min = 8;
            t.pitch_max = 2047;
            t.volume_step_count = 16;
            t.volume_steps = table(16, linear(16));
            t.duty_steps = 8;
            v = linear(16);
            if (case.wave == .triangle) {
                // NES-TRIANGLE: the 32 steps, clock / 32, full volume.
                t.wave = .wavetable;
                for (0..32) |i| {
                    const level: f64 = @floatFromInt(if (i < 16) 15 - i else i - 16);
                    pool[i] = @intFromFloat(@round((level - 7.5) / 7.5 * 32767));
                }
                t.table = .{ .start = 0, .length = 32 };
                t.pitch_divider = 32;
                t.pitch_min = 2;
                t.volume_step_count = 1;
                t.volume_steps = table(1, .{65535});
                t.duty_steps = 0;
            }
            if (case.wave == .noise) {
                t.pitch_offset = 0;
                t.pitch_min = 4;
                t.pitch_max = 4068;
                t.duty_steps = 0;
            }
            limit = 4;
            engine.bank.mixer = .nes;
        },
        .c64 => {
            t.pitch_mode = .step;
            t.pitch_clock = 985_248_000;
            t.pitch_bits = 24;
            t.duty_steps = 4096;
            t.noise_bits = 23;
            t.noise_tap = 5;
            v = linear(16);
            limit = 3;
        },
        .scc => {
            t.pitch_mode = .period;
            t.pitch_clock = 3_579_545_000;
            t.pitch_divider = 32;
            t.pitch_offset = 1;
            t.pitch_min = 0;
            t.pitch_max = 4095;
            t.volume_step_count = 16;
            t.volume_steps = table(16, linear(16));
            v = linear(16);
            if (case.wave == .wavetable) {
                for (cases.scc_wave, 0..) |b, i| pool[i] = @as(i16, b) * 256;
                t.table = .{ .start = 0, .length = 32 };
            }
            limit = 5;
        },
        .amiga => {
            t.pitch_mode = .period;
            t.pitch_clock = 3_546_895_000;
            t.pitch_divider = 1;
            t.pitch_min = 124;
            t.pitch_max = 65535;
            t.volume_step_count = 65;
            t.volume_steps = table(65, linear(65));
            if (case.wave == .sample) t.sample = 0;
            for (&v, 0..) |*x, i| x.* = @intFromFloat(@round(@round(@as(f64, @floatFromInt(i)) * 64.0 / 15.0) * 65535.0 / 64.0));
            limit = 4;
            engine.master.setFilter(.low_pass, 4900);
        },
    }
    engine.voice_limit = limit;
    // V-STEPS came with tque 1206; a commit before it has no such fields.
    if (@hasField(Tone, "v_step_count")) {
        t.v_step_count = 16;
        t.v_steps = v;
    }
    return t;
}

pub fn main() u8 {
    const allocator = std.heap.c_allocator;
    const engine = allocator.create(Engine) catch return 2;
    defer allocator.destroy(engine);
    const out = allocator.alloc(i16, m.rate * 2 * 2) catch return 2;
    defer allocator.free(out);
    var pool: [64]i16 = undefined;
    _ = m.puts("{");
    for (cases.all, 0..) |case, n| {
        engine.* = Engine.init(m.rate);
        // The sample first; NES-TRIANGLE and SCC-WAVE then put their waves at the start.
        cases.fillSample(&pool);
        engine.pool = &pool;
        const tone = setUp(engine, case, &pool);
        if (!engine.putCommand(.{ .instrument = .{ .index = 0, .value = blk: {
            // Instrument 0 (the voices that rest) with the same steps.
            var rest = tone;
            rest.wave = .square;
            break :blk rest;
        } } })) return 3;
        if (!engine.putCommand(.{ .instrument = .{ .index = 1, .value = tone } })) return 3;
        if (!engine.putCommand(.{ .sample = .{ .index = 0, .value = .{ .start = 0, .length = 64, .rate = cases.sample_rate, .loop_start = 0, .loop_end = 64 } } })) return 3;
        var player: Player = .{ .engine = engine };
        var voices: [8]mml.Voice = @splat(.{});
        engine_module.putPlay(engine, &voices, case.texts(), &player, Player.wait) catch return 4;
        var done: usize = 0;
        while (done < m.rate * 2) : (done += 480) engine.render(out[done * 2 ..][0 .. 480 * 2]);
        m.print(case.name, m.measure(out, m.rate / 2), n + 1 == cases.all.len);
    }
    _ = m.puts("}");
    return 0;
}
