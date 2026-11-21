//! The chip comparison's old side (tque 1206): the chips' settings as they were at
//! e90b6f6, before tque 1199 removed them. Built in that commit's src/core by
//! tests/scripts/compare-chip-libraries.py; prints one JSON object.
const std = @import("std");
const engine_module = @import("sound_engine.zig");
const mml = @import("sound_mml.zig");
const psg = @import("sound_psg.zig");
const parts = @import("sound_parts.zig");
const m = @import("measure.zig");
const cases = @import("cases.zig");

const Engine = engine_module.Engine;

const Player = struct {
    engine: *Engine,
    buffer: [960]i16 = undefined,
    fn wait(self: *Player) bool {
        self.engine.render(&self.buffer);
        return true;
    }
};

fn chipOf(c: cases.Chip) parts.Chip {
    return switch (c) {
        .msx => .msx,
        .st => .atari_st,
        .nes => .nes,
        .c64 => .c64,
        .scc => .scc,
        .amiga => .amiga,
    };
}

fn instrumentOf(case: cases.Case) parts.Instrument {
    var i: parts.Instrument = .{};
    i.wave = switch (case.wave) {
        .square => .square,
        .pulse => .pulse,
        .triangle => .triangle,
        .saw => .saw,
        .noise => .noise,
        .wavetable, .sample => .square,
    };
    i.duty = case.duty_percent;
    if (case.wave == .wavetable) i.wavetable = cases.scc_wave;
    if (case.wave == .sample) i.sample = 0;
    return i;
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
        engine.* = Engine.init(.ay8910, psg.msx_clock, m.rate);
        engine.pool = &pool;
        cases.fillSample(&pool);
        if (!engine.putCommand(engine.chipsCommand(engine_module.Chips.one(chipOf(case.chip))))) return 3;
        if (!engine.putCommand(.{ .instrument = .{ .index = 1, .value = instrumentOf(case) } })) return 3;
        if (!engine.putCommand(.{ .sample = .{ .index = 0, .value = .{ .start = 0, .length = 64, .rate = cases.sample_rate, .loop_start = 0, .loop_end = 64 } } })) return 3;
        var player: Player = .{ .engine = engine };
        var voices: [8]mml.Voice = @splat(.{});
        engine_module.putPlay(engine, &voices, case.texts(), &player, Player.wait) catch return 4;
        // Two seconds; the first half second is left out.
        var done: usize = 0;
        while (done < m.rate * 2) : (done += 480) engine.render(out[done * 2 ..][0 .. 480 * 2]);
        m.print(case.name, m.measure(out, m.rate / 2), n + 1 == cases.all.len);
    }
    _ = m.puts("}");
    return 0;
}
