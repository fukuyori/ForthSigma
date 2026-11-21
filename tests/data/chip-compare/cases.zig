//! The cases of the chip comparison (tque 1206), the same for the old and the new side:
//! one instrument (1) on one voice, two seconds of one note.
const std = @import("std");

pub const Chip = enum { msx, st, nes, c64, scc, amiga };
pub const Wave = enum { square, pulse, triangle, saw, noise, wavetable, sample };

pub const Case = struct {
    name: []const u8,
    chip: Chip,
    wave: Wave = .square,
    /// The old PULSE's percent (the new duty is the same part of 65536).
    duty_percent: u8 = 50,
    /// PLAY's voice, 1 to 4 (the voices before it rest).
    voice: u8 = 1,
    mml: []const u8,

    var buffer: [4][]const u8 = undefined;

    pub fn texts(self: Case) []const []const u8 {
        for (0..self.voice - 1) |v| buffer[v] = "T120 L1 R";
        buffer[self.voice - 1] = self.mml;
        return buffer[0..self.voice];
    }
};

pub const all = [_]Case{
    .{ .name = "msx_square_v15", .chip = .msx, .mml = "T120 V15 O4 L1 A" },
    .{ .name = "msx_square_v12", .chip = .msx, .mml = "T120 V12 O4 L1 A" },
    .{ .name = "msx_square_v9", .chip = .msx, .mml = "T120 V9 O4 L1 A" },
    .{ .name = "msx_square_v6", .chip = .msx, .mml = "T120 V6 O4 L1 A" },
    .{ .name = "msx_square_v3", .chip = .msx, .mml = "T120 V3 O4 L1 A" },
    .{ .name = "msx_square_o7", .chip = .msx, .mml = "T120 V15 O7 L1 A" },
    .{ .name = "msx_noise", .chip = .msx, .wave = .noise, .mml = "T120 @1 V15 O4 L1 A" },
    .{ .name = "st_square_v15", .chip = .st, .mml = "T120 V15 O4 L1 A" },
    .{ .name = "st_square_v9", .chip = .st, .mml = "T120 V9 O4 L1 A" },
    .{ .name = "st_square_v3", .chip = .st, .mml = "T120 V3 O4 L1 A" },
    .{ .name = "nes_pulse12", .chip = .nes, .wave = .pulse, .duty_percent = 12, .mml = "T120 @1 V15 O4 L1 A" },
    .{ .name = "nes_square_v9", .chip = .nes, .mml = "T120 V9 O4 L1 A" },
    .{ .name = "nes_triangle", .chip = .nes, .wave = .triangle, .voice = 3, .mml = "T120 @1 V15 O3 L1 A" },
    .{ .name = "nes_noise", .chip = .nes, .wave = .noise, .voice = 4, .mml = "T120 @1 V15 O4 L1 A" },
    .{ .name = "c64_saw", .chip = .c64, .wave = .saw, .mml = "T120 @1 V15 O4 L1 A" },
    .{ .name = "c64_pulse25", .chip = .c64, .wave = .pulse, .duty_percent = 25, .mml = "T120 @1 V15 O4 L1 A" },
    .{ .name = "c64_triangle", .chip = .c64, .wave = .triangle, .mml = "T120 @1 V15 O4 L1 A" },
    .{ .name = "scc_wave", .chip = .scc, .wave = .wavetable, .mml = "T120 @1 V15 O4 L1 A" },
    .{ .name = "scc_square_v9", .chip = .scc, .mml = "T120 V9 O4 L1 A" },
    .{ .name = "amiga_sample", .chip = .amiga, .wave = .sample, .mml = "T120 @1 V15 O4 L1 C" },
    .{ .name = "amiga_square", .chip = .amiga, .mml = "T120 V15 O4 L1 A" },
};

/// SCC-WAVE's 32 signed bytes: a sine and its second harmonic.
pub const scc_wave: [32]i8 = blk: {
    var w: [32]i8 = undefined;
    for (&w, 0..) |*x, i| {
        const t = @as(f64, @floatFromInt(i)) / 32.0;
        x.* = @intFromFloat(@round(90 * @sin(2 * std.math.pi * t) + 35 * @sin(4 * std.math.pi * t)));
    }
    break :blk w;
};

/// One cycle of a sine in 64 values, looped, at 16574 Hz: at O4's C (the sample's own
/// rate) a note of 16574 / 64 = 259 Hz.
pub const sample_rate = 16574;

pub fn fillSample(pool: *[64]i16) void {
    for (pool, 0..) |*x, i| {
        const t = @as(f64, @floatFromInt(i)) / 64.0;
        x.* = @intFromFloat(@round(@sin(2 * std.math.pi * t) * 100) * 256);
    }
}
