const std = @import("std");
const forth = @import("forth.zig");

extern "c" fn getchar() c_int;
extern "c" fn putchar(c_int) c_int;
extern "c" fn fflush(?*anyopaque) c_int;

fn terminalWrite(_: ?*anyopaque, bytes: []const u8) void {
    for (bytes) |byte| _ = putchar(byte);
    _ = fflush(null);
}

fn terminalRead(_: ?*anyopaque, buffer: []u8) ?[]const u8 {
    var used: usize = 0;
    while (true) {
        const ch = getchar();
        if (ch < 0) return if (used == 0) null else buffer[0..used];
        const byte: u8 = @intCast(ch);
        if (byte == '\r' or byte == '\n') {
            if (used == 0) continue;
            return buffer[0..used];
        }
        if (used < buffer.len) {
            buffer[used] = byte;
            used += 1;
        }
    }
}

fn interpretAndPrompt(machine: *forth.State, line: []const u8) void {
    machine.interpretLine(line) catch |err| {
        machine.report(err);
        return;
    };
    machine.write(" OK\n");
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const machine = try allocator.create(forth.State);
    defer allocator.destroy(machine);

    machine.* = forth.State.init(.{ .context = null, .write_fn = terminalWrite, .read_fn = terminalRead });
    machine.write("FORTH/Sigma Zig portable core\n");

    var line: [4096]u8 = undefined;
    var used: usize = 0;
    var discarding_line = false;
    while (!machine.halted) {
        const ch = getchar();
        if (ch < 0) {
            if (!discarding_line and used != 0) interpretAndPrompt(machine, line[0..used]);
            break;
        }
        const byte: u8 = @intCast(ch);
        if (byte == '\r' or byte == '\n') {
            if (!discarding_line and used != 0) interpretAndPrompt(machine, line[0..used]);
            used = 0;
            discarding_line = false;
            continue;
        }
        if (discarding_line) continue;
        if (used == line.len) {
            machine.write("LINE TOO LONG\n");
            used = 0;
            discarding_line = true;
            continue;
        }
        line[used] = byte;
        used += 1;
    }
}
