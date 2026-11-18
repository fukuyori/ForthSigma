//! Static Linux musl gamepad snapshots through evdev ioctls. No event stream,
//! device grab, SDL dependency, force feedback, or custom mappings.
const std = @import("std");
const gp = @import("core/gamepad.zig");
const c = @import("c_evdev");
const Slot = struct {
    fd: c_int = -1,
    node: u16 = 0,
    pad: gp.Pad = .{},
    axes: [16]u8 = @splat(0),
    buttons: [32]u16 = @splat(0),
    hats: [4]bool = @splat(false),
    hat_axes: [8]bool = @splat(false),
};
var slots: [gp.max_pads]Slot = @splat(.{});
var next_id: u32 = 1;
var next_scan: i64 = 0;
var denied = false;
var denied_once: [256]bool = @splat(false);
var directory_present = false;
fn ioctl(fd: c_int, request: u32, argument: anytype) c_int {
    const Request = @typeInfo(@TypeOf(c.ioctl)).@"fn".param_types[1].?;
    const value: Request = if (@sizeOf(Request) == 4) @bitCast(request) else request;
    var attempts: usize = 0;
    while (true) {
        const result = c.ioctl(fd, value, argument);
        if (result >= 0 or c.__errno_location().* != c.EINTR or attempts == 8) return result;
        attempts += 1;
    }
}
fn milliseconds() i64 {
    var ts: std.c.timespec = undefined;
    _ = std.c.clock_gettime(.MONOTONIC, &ts);
    return @as(i64, @intCast(ts.sec)) * 1000 + @divTrunc(ts.nsec, 1_000_000);
}
fn bit(bytes: []const u8, n: usize) bool {
    const word_bits = @bitSizeOf(c_ulong);
    const offset = (n / word_bits) * @sizeOf(c_ulong);
    if (offset + @sizeOf(c_ulong) > bytes.len) return false;
    const word = std.mem.readInt(c_ulong, bytes[offset..][0..@sizeOf(c_ulong)], @import("builtin").cpu.arch.endian());
    return word & (@as(c_ulong, 1) << @intCast(n % word_bits)) != 0;
}
fn readText(path: [*:0]const u8, buffer: []u8) ?[]const u8 {
    const fd = c.open(path, c.O_RDONLY | c.O_CLOEXEC | c.O_NONBLOCK, @as(c_uint, 0));
    if (fd < 0) return null;
    defer _ = c.close(fd);
    const count = c.read(fd, buffer.ptr, buffer.len);
    if (count < 0 or count == buffer.len) return null;
    return buffer[0..@intCast(count)];
}
// The kernel's modalias lists individual hexadecimal event codes, avoiding
// sysfs bitmap word-size assumptions when a 32-bit program runs on a 64-bit kernel.
fn isGamepad(alias: []const u8) bool {
    const start = std.mem.indexOfScalar(u8, alias, 'k') orelse return false;
    const end = std.mem.indexOfScalarPos(u8, alias, start, 'r') orelse return false;
    var codes = std.mem.splitScalar(u8, alias[start + 1 .. end], ',');
    while (codes.next()) |code| {
        if (code.len == 0) continue;
        const value = std.fmt.parseInt(u16, code, 16) catch continue;
        if (value == c.BTN_GAMEPAD or value == c.BTN_JOYSTICK) return true;
    }
    return false;
}
fn drop(slot: *Slot) void {
    if (slot.fd >= 0) _ = c.close(slot.fd);
    slot.* = .{};
}
pub fn close() void {
    for (&slots) |*slot| drop(slot);
    next_scan = 0;
}
fn scan() void {
    denied = false;
    directory_present = c.access("/sys/class/input", c.F_OK) == 0 and c.access("/dev/input", c.F_OK) == 0;
    var buffer: [8192]u8 = undefined;
    for (0..256) |node| {
        var occupied = false;
        for (&slots) |slot| if (slot.fd >= 0 and slot.node == node) {
            occupied = true;
            break;
        };
        if (occupied) continue;
        var path: [256]u8 = @splat(0);
        _ = std.fmt.bufPrint(path[0 .. path.len - 1], "/sys/class/input/event{d}/device/modalias", .{node}) catch continue;
        const alias = readText(@ptrCast(&path), &buffer) orelse {
            denied_once[node] = false;
            continue;
        };
        if (!isGamepad(alias)) {
            denied_once[node] = false;
            continue;
        }
        const slot = for (&slots) |*candidate| {
            if (candidate.fd < 0) break candidate;
        } else break;
        @memset(&path, 0);
        _ = std.fmt.bufPrint(path[0 .. path.len - 1], "/dev/input/event{d}", .{node}) catch continue;
        const fd = c.open(@ptrCast(&path), c.O_RDONLY | c.O_NONBLOCK | c.O_CLOEXEC, @as(c_uint, 0));
        if (fd < 0) {
            if (c.__errno_location().* == c.EACCES or c.__errno_location().* == c.EPERM) {
                if (denied_once[node]) denied = true;
                denied_once[node] = true;
            }
            continue;
        }
        denied_once[node] = false;
        var keycaps: [96]u8 = @splat(0);
        var abscaps: [8]u8 = @splat(0);
        if (ioctl(fd, c.SIGMA_EVDEV_KEYS, &keycaps) < 0 or ioctl(fd, c.SIGMA_EVDEV_ABS, &abscaps) < 0 or (!bit(&keycaps, c.BTN_GAMEPAD) and !bit(&keycaps, c.BTN_JOYSTICK))) {
            _ = c.close(fd);
            continue;
        }
        slot.* = .{ .fd = fd, .node = @intCast(node), .pad = .{ .id = next_id } };
        next_id +%= 1;
        if (next_id == 0) next_id = 1;
        _ = ioctl(fd, c.SIGMA_EVDEV_NAME, &slot.pad.name);
        slot.pad.name_len = @intCast(std.mem.sliceTo(&slot.pad.name, 0).len);
        var id: c.struct_input_id = std.mem.zeroes(c.struct_input_id);
        _ = ioctl(fd, c.SIGMA_EVDEV_ID, &id);
        // Backend-specific identifier, not an SDL mapping GUID. The GUID remains
        // 32 hexadecimal characters; GAMEPAD-MAP deliberately returns false.
        const fields = [_]u16{ id.bustype, id.vendor, id.product, id.version };
        const hex = "0123456789abcdef";
        @memset(&slot.pad.guid, '0');
        for (fields, 0..) |value, i| for (0..4) |j| {
            slot.pad.guid[i * 4 + j] = hex[(value >> @as(u4, @intCast(12 - 4 * j))) & 15];
        };
        for (0..64) |code| {
            if (!bit(&abscaps, code)) continue;
            const info = if (code >= c.ABS_HAT0X and code <= c.ABS_HAT3Y) abs(fd, @intCast(code)) else null;
            if (info != null and info.?.minimum == -1 and info.?.maximum == 1) {
                const hat = (code - c.ABS_HAT0X) / 2;
                slot.hats[hat] = true;
                slot.hat_axes[code - c.ABS_HAT0X] = true;
                slot.pad.hat_count = @max(slot.pad.hat_count, @as(u8, @intCast(hat + 1)));
                continue;
            }
            if (slot.pad.axis_count == slot.axes.len) continue;
            slot.axes[slot.pad.axis_count] = @intCast(code);
            slot.pad.axis_count += 1;
        }
        for (256..768) |code| if (bit(&keycaps, code)) {
            if (slot.pad.button_count == slot.buttons.len) break;
            slot.buttons[slot.pad.button_count] = @intCast(code);
            slot.pad.button_count += 1;
        };
    }
}
fn normalise(value: i32, minimum: i32, maximum: i32) i16 {
    if (maximum <= minimum) return 0;
    const clipped = @min(maximum, @max(minimum, value));
    return @intCast(@divTrunc((@as(i64, clipped) - minimum) * 65535, @as(i64, maximum) - minimum) - 32768);
}
fn abs(fd: c_int, code: u8) ?c.struct_input_absinfo {
    var info: c.struct_input_absinfo = undefined;
    const request = @as(u32, c.SIGMA_EVDEV_ABS0) + code;
    if (ioctl(fd, request, &info) < 0) return null;
    return info;
}
fn snapshot(slot: *Slot) bool {
    var updated = slot.pad;
    var state: [96]u8 = @splat(0);
    if (ioctl(slot.fd, c.SIGMA_EVDEV_STATE, &state) < 0) return false;
    updated.buttons = 0;
    for (slot.buttons[0..updated.button_count], 0..) |code, index| if (bit(&state, code)) {
        updated.buttons |= @as(u32, 1) << @intCast(index);
    };
    for (slot.axes[0..updated.axis_count], 0..) |code, index| {
        const info = abs(slot.fd, code) orelse return false;
        updated.axes[index] = normalise(info.value, info.minimum, info.maximum);
    }
    for (slot.hats, 0..) |present, index| if (present) {
        const horizontal: i32 = if (slot.hat_axes[index * 2]) (abs(slot.fd, @intCast(@as(usize, c.ABS_HAT0X) + index * 2)) orelse return false).value else 0;
        const vertical: i32 = if (slot.hat_axes[index * 2 + 1]) (abs(slot.fd, @intCast(@as(usize, c.ABS_HAT0Y) + index * 2)) orelse return false).value else 0;
        updated.hats[index] = 0;
        if (horizontal < 0) updated.hats[index] |= 8 else if (horizontal > 0) updated.hats[index] |= 2;
        if (vertical < 0) updated.hats[index] |= 1 else if (vertical > 0) updated.hats[index] |= 4;
    };
    slot.pad = updated;
    return true;
}
pub fn poll(_: ?*anyopaque, output: *gp.Snapshot) bool {
    output.* = .{};
    const now = milliseconds();
    if (now >= next_scan) {
        scan();
        next_scan = now + 1000;
    }
    for (&slots) |*slot| if (slot.fd >= 0) {
        if (!snapshot(slot)) {
            const err = c.__errno_location().*;
            if (err == c.ENODEV or err == c.ENXIO or err == c.EBADF) {
                drop(slot);
                next_scan = 0;
                continue;
            }
            // EINTR and transient failures retain the previous whole snapshot.
        }
        output.pads[output.count] = slot.pad;
        output.count += 1;
    };
    return output.count != 0 or (directory_present and !denied);
}

test "evdev raw axis ranges saturate without integer overflow" {
    try std.testing.expectEqual(@as(i16, -32768), normalise(-100, 0, 255));
    try std.testing.expectEqual(@as(i16, 32767), normalise(300, 0, 255));
    try std.testing.expectEqual(@as(i16, 0), normalise(0, -32768, 32767));
    try std.testing.expectEqual(@as(i16, 0), normalise(0, 10, 10));
    try std.testing.expectEqual(@as(i16, 32767), normalise(std.math.maxInt(i32), std.math.minInt(i32), std.math.maxInt(i32)));
}
test "evdev modalias classification does not admit keyboards or motion sensors" {
    try std.testing.expect(isGamepad("input:b0003v1234p5678e0001-e0,1,3,k130,131,133,134,ramlsfw"));
    try std.testing.expect(isGamepad("input:b0003v1234p5678e0001-e0,1,3,k120,121,ramlsfw"));
    try std.testing.expect(!isGamepad("input:b0019v0000p0003e0000-e0,1,k8E,ramlsfw"));
    try std.testing.expect(!isGamepad("input:b0003-e0,3,kra0,1,2,mlsfw"));
}

test "evdev capability bits follow native unsigned-long layout" {
    var data: [16]u8 = @splat(0);
    std.mem.writeInt(c_ulong, data[0..@sizeOf(c_ulong)], 129, @import("builtin").cpu.arch.endian());
    try std.testing.expect(bit(&data, 0) and bit(&data, 7));
    try std.testing.expect(!bit(&data, 8) and !bit(&data, 128));
}
