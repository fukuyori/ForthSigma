//! Original port of the declared Forth S-DSP sample-boundary model (not SPC700).
//! Buffers and their lifetime belong to the caller. No device or allocation.
const gauss = @import("snes_gauss.zig").values;
pub const rates = [_]i64{ 0, 2048, 1536, 1280, 1024, 768, 640, 512, 384, 320, 256, 192, 160, 128, 96, 80, 64, 48, 40, 32, 24, 20, 16, 12, 10, 8, 6, 5, 4, 3, 2, 1 };
pub const cycle = 0;
pub const divider = 1;
pub const frame = 2;
pub const pending = 3;
pub const noise = 4;
pub const eoff = 5;
pub const elen = 6;
pub const ehi = 7;
pub const left = 8;
pub const right = 9;
fn sat(n: i64) i64 {
    return @min(32767, @max(-32768, n));
}
fn signed(n: i64, comptime bits: u6) i64 {
    const mask: i64 = (@as(i64, 1) << bits) - 1;
    const value = n & mask;
    return if (value & (@as(i64, 1) << (bits - 1)) != 0) value - (@as(i64, 1) << bits) else value;
}
fn byte(n: i64) u8 {
    return @truncate(@as(u64, @bitCast(n)));
}
fn idx(n: i64) usize {
    return @intCast(n);
}
pub fn brr(nibble: i64, header: i64, old: i64, older: i64) i64 {
    const n = signed(nibble, 4);
    const shift: u6 = @intCast(header >> 4);
    var value = if (shift <= 12) (n * (@as(i64, 1) << shift)) >> 1 else if (n < 0) @as(i64, -2048) else 0;
    value += switch ((header >> 2) & 3) {
        0 => 0,
        1 => old + ((-old) >> 4),
        2 => old * 2 + ((-old * 3) >> 5) - older + (older >> 4),
        3 => old * 2 + ((-old * 13) >> 6) - older + ((older * 3) >> 4),
        else => unreachable,
    };
    return signed(sat(value), 15);
}
pub fn gaussian(phase: i64, history: []const i64) i64 {
    const f = idx((phase >> 4) & 255);
    const first = (history[0] * gauss[255 - f] >> 10) + (history[1] * gauss[511 - f] >> 10) + (history[2] * gauss[256 + f] >> 10);
    return sat(signed(first, 16) + (history[3] * gauss[f] >> 10)) >> 1;
}
pub const Model = struct {
    regs: []u8,
    ram: []u8,
    voices: [112]i64,
    globals: [10]i64,
    history: [16]i64,
    reg_writes: [128]bool = @splat(false),
    ram_writes: [4]u16 = undefined,
    ram_write_count: usize = 0,
    fn word(self: *const Model, address: i64) i64 {
        return @as(i64, self.ram[idx(address & 65535)]) | (@as(i64, self.ram[idx((address + 1) & 65535)]) << 8);
    }
    fn putWord(self: *Model, address: i64, n: i64) void {
        self.ram_writes[self.ram_write_count] = @intCast(address & 65535);
        self.ram_writes[self.ram_write_count + 1] = @intCast((address + 1) & 65535);
        self.ram_write_count += 2;
        self.ram[idx(address & 65535)] = byte(n);
        self.ram[idx((address + 1) & 65535)] = byte(n >> 8);
    }
    fn directory(self: *const Model, i: usize) i64 {
        return (@as(i64, self.regs[93]) * 256 + @as(i64, self.regs[i * 16 + 4]) * 4) & 65535;
    }
    fn start(self: *Model, i: usize) void {
        const v = self.voices[i * 14 ..][0..14];
        @memset(v, 0);
        v[0] = -1;
        v[1] = self.word(self.directory(i));
        v[9] = 5;
        self.reg_writes[124] = true;
        self.regs[124] &= ~(@as(u8, 1) << @as(u3, @intCast(i)));
    }
    fn consume(self: *Model, i: usize) void {
        const v = self.voices[i * 14 ..][0..14];
        if (v[2] == 0) v[3] = self.ram[idx(v[1])];
        const data: i64 = self.ram[idx((v[1] + 1 + @divTrunc(v[2], 2)) & 65535)];
        const n = if (v[2] & 1 != 0) data & 15 else data >> 4;
        const value = brr(n, v[3], v[4], v[5]);
        v[5] = v[4];
        v[4] = value;
        v[10] = v[11];
        v[11] = v[12];
        v[12] = v[13];
        v[13] = value;
        v[2] += 1;
        if (v[2] == 16) {
            v[2] = 0;
            if (v[3] & 1 != 0) {
                self.reg_writes[124] = true;
                self.regs[124] |= @as(u8, 1) << @as(u3, @intCast(i));
                v[1] = self.word(self.directory(i) + 2);
                if (v[3] & 2 == 0) {
                    v[7] = 0;
                    v[8] = 3;
                }
            } else v[1] = (v[1] + 9) & 65535;
        }
    }
    fn due(self: *const Model, rate: usize) bool {
        return rate != 0 and @mod(self.globals[frame], rates[rate]) == 0;
    }
    pub fn envelope(self: *Model, i: usize) void {
        const v = self.voices[i * 14 ..][0..14];
        var env = v[7];
        const mode = v[8];
        if (mode == 3) {
            v[7] = @max(0, env - 8);
            return;
        }
        const a: i64 = self.regs[i * 16 + 5];
        const b: i64 = self.regs[i * 16 + 6];
        const gain: i64 = self.regs[i * 16 + 7];
        if (a & 128 != 0) {
            const rate = switch (mode) {
                0 => (a & 15) * 2 + 1,
                1 => ((a >> 4) & 7) * 2 + 16,
                2 => b & 31,
                else => unreachable,
            };
            const delta = if (mode == 0) (if (a & 15 == 15) @as(i64, 1024) else 32) else -@divTrunc(env + 255, 256);
            if (self.due(idx(rate))) env += delta;
        } else if (gain & 128 == 0) {
            env = (gain & 127) * 16;
        } else if (self.due(idx(gain & 31))) {
            env += switch ((gain >> 5) & 3) {
                0 => -32,
                1 => -@divTrunc(env + 255, 256),
                2 => 32,
                3 => if (env < 1536) @as(i64, 32) else 8,
                else => unreachable,
            };
        }
        v[7] = @min(2047, @max(0, env));
        if (v[8] == 0 and v[7] >= 2016) v[8] = 1;
        if (v[8] == 1 and v[7] <= ((b >> 5) + 1) * 256) v[8] = 2;
    }
    fn publish(self: *Model, i: usize, value: i64) void {
        self.reg_writes[i * 16 + 8] = true;
        self.reg_writes[i * 16 + 9] = true;
        self.regs[i * 16 + 8] = byte(self.voices[i * 14 + 7] >> 4);
        self.regs[i * 16 + 9] = byte(value >> 7);
    }
    fn voice(self: *Model, i: usize, previous: i64) i64 {
        const v = self.voices[i * 14 ..][0..14];
        if (v[0] == 0) {
            self.publish(i, 0);
            return 0;
        }
        if (v[9] > 0) {
            v[9] -= 1;
            if (v[9] == 0) self.consume(i);
            self.publish(i, 0);
            return 0;
        }
        const mask = @as(u8, 1) << @as(u3, @intCast(i));
        const sample = if (self.regs[61] & mask != 0) signed(self.globals[noise], 15) else gaussian(v[6], v[10..14]);
        const value = (sample * v[7]) >> 11;
        self.publish(i, value);
        self.envelope(i);
        var pitch: i64 = @as(i64, self.regs[i * 16 + 2]) | (@as(i64, self.regs[i * 16 + 3] & 63) << 8);
        if (i > 0 and self.regs[45] & mask != 0) pitch = @min(16383, @max(0, (pitch * (1024 + (previous >> 4))) >> 10));
        v[6] += pitch;
        while (v[6] >= 4096) {
            self.consume(i);
            v[6] -= 4096;
        }
        return value;
    }
    fn fir(self: *const Model, ch: usize) i64 {
        var sum: i64 = 0;
        for (0..8) |k| {
            if (k == 7) sum = signed(sum, 16);
            const h = self.history[((idx(self.globals[ehi]) + k + 1) & 7) * 2 + ch];
            sum += (h * signed(self.regs[k * 16 + 15], 8)) >> 6;
        }
        return sat(sum);
    }
    fn echo(self: *Model, mix: [2]i64, emix: [2]i64) void {
        if (self.globals[eoff] == 0) self.globals[elen] = @max(4, @as(i64, self.regs[125] & 15) * 2048);
        const address = (@as(i64, self.regs[109]) * 256 + self.globals[eoff]) & 65535;
        for (0..2) |ch| self.history[idx(self.globals[ehi]) * 2 + ch] = signed(self.word(address + @as(i64, @intCast(ch)) * 2), 16) >> 1;
        for (0..2) |ch| {
            const value = self.fir(ch);
            const output = sat(signed((mix[ch] * signed(self.regs[ch * 16 + 12], 8)) >> 7, 16) + signed((value * signed(self.regs[ch * 16 + 44], 8)) >> 7, 16));
            self.globals[left + ch] = if (self.regs[108] & 64 != 0) 0 else output;
            if (self.regs[108] & 32 == 0) self.putWord(address + @as(i64, @intCast(ch)) * 2, sat(emix[ch] + signed((value * signed(self.regs[13], 8)) >> 7, 16)) & ~@as(i64, 1));
        }
        self.globals[eoff] += 4;
        if (self.globals[eoff] >= self.globals[elen]) self.globals[eoff] = 0;
        self.globals[ehi] = (self.globals[ehi] + 1) & 7;
    }
    pub fn step(self: *Model) void {
        self.reg_writes = @splat(false);
        self.ram_write_count = 0;
        self.globals[frame] += 1;
        if (self.due(self.regs[108] & 31)) {
            const n = self.globals[noise];
            self.globals[noise] = (n >> 1) | (((n ^ (n >> 1)) & 1) << 14);
        }
        const poll = self.globals[frame] & 1 != 0;
        for (0..8) |i| {
            const v = self.voices[i * 14 ..][0..14];
            const mask = @as(i64, 1) << @as(u6, @intCast(i));
            if (self.regs[108] & 128 != 0) {
                v[7] = 0;
                v[8] = 3;
            }
            if (poll) {
                if (self.regs[92] & mask != 0) v[8] = 3;
                if (self.globals[pending] & mask != 0) self.start(i);
            }
        }
        if (poll) self.globals[pending] = 0;
        var mix: [2]i64 = .{ 0, 0 };
        var emix = mix;
        var previous: i64 = 0;
        for (0..8) |i| {
            const value = self.voice(i, previous);
            previous = value;
            for (0..2) |ch| {
                const term = (value * signed(self.regs[i * 16 + ch], 8)) >> 6;
                mix[ch] = sat(mix[ch] + term);
                if (self.regs[77] & (@as(u8, 1) << @as(u3, @intCast(i))) != 0) emix[ch] = sat(emix[ch] + term);
            }
        }
        self.echo(mix, emix);
        self.globals[cycle] += 32 - self.globals[divider];
        self.globals[divider] = 0;
    }
};
