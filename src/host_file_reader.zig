//! Windows pipe input has one reader after migration. Queues outlive waits;
//! join the producer before closing its borrowed stream or reusing the slot.
const std = @import("std");
const builtin = @import("builtin");
const base = @import("core/runtime_base.zig");
const Wake = @import("host_wake.zig").Wake;
pub const Reader = if (builtin.os.tag == .windows) Worker(false) else struct {};
pub const Writer = if (builtin.os.tag == .windows) Worker(true) else struct {};
const Handle = *anyopaque;
const win = struct {
    extern "kernel32" fn CreateThread(?*anyopaque, usize, *const fn (?*anyopaque) callconv(.winapi) u32, ?*anyopaque, u32, ?*u32) callconv(.winapi) ?Handle;
    extern "kernel32" fn WriteFile(Handle, [*]const u8, u32, *u32, ?*anyopaque) callconv(.winapi) i32;
    extern "kernel32" fn ReadFile(Handle, [*]u8, u32, *u32, ?*anyopaque) callconv(.winapi) i32;
    extern "kernel32" fn PeekNamedPipe(Handle, ?*anyopaque, u32, ?*u32, ?*u32, ?*u32) callconv(.winapi) i32;
    extern "kernel32" fn CreateEventW(?*anyopaque, i32, i32, ?[*:0]const u16) callconv(.winapi) ?Handle;
    extern "kernel32" fn SetEvent(Handle) callconv(.winapi) i32;
    extern "kernel32" fn ResetEvent(Handle) callconv(.winapi) i32;
    extern "kernel32" fn WaitForSingleObject(Handle, u32) callconv(.winapi) u32;
    extern "kernel32" fn CloseHandle(Handle) callconv(.winapi) i32;
    extern "kernel32" fn GetLastError() callconv(.winapi) u32;
    extern "kernel32" fn CancelSynchronousIo(Handle) callconv(.winapi) i32;
    extern "kernel32" fn AcquireSRWLockExclusive(*usize) callconv(.winapi) void;
    extern "kernel32" fn ReleaseSRWLockExclusive(*usize) callconv(.winapi) void;
    extern "kernel32" fn GetProcessHeap() callconv(.winapi) Handle;
    extern "kernel32" fn HeapAlloc(Handle, u32, usize) callconv(.winapi) ?*anyopaque;
    extern "kernel32" fn HeapFree(Handle, u32, *anyopaque) callconv(.winapi) i32;
};
pub const Result = struct { count: usize = 0, eof: bool = false, code: u32 = 0 };
fn Worker(comptime writing: bool) type {
    return struct {
        const Self = @This();
        pub const capacity = 65536;
        stream: ?Handle = null,
        thread: ?Handle = null,
        space: ?Handle = null,
        wake: ?*Wake = null,
        buffer: ?[*]u8 = null,
        lock: usize = 0,
        stopping: std.atomic.Value(bool) = .init(false),
        in_io: bool = false,
        head: usize = 0,
        length: usize = 0,
        ended: bool = false,
        failure: u32 = 0,
        write_callback: ?*const fn ([]const u8) Result = null,

        pub fn active(self: *const Self) bool {
            return self.buffer != null;
        }
        pub fn start(self: *Self, stream: Handle, wake: *Wake) base.Error!void {
            if (!self.active()) {
                self.space = win.CreateEventW(null, 1, 1, null) orelse return error.HostFailed;
                self.buffer = @ptrCast(win.HeapAlloc(win.GetProcessHeap(), 0, capacity) orelse {
                    _ = win.CloseHandle(self.space.?);
                    self.space = null;
                    return error.HostFailed;
                });
                self.stream = stream;
                self.wake = wake;
            }
            if (self.stream != stream or self.wake != wake) return error.HostFailed;
            if (self.stopping.load(.acquire)) try self.pause();
            if (self.thread != null or self.ended or self.failure != 0) return;
            self.stopping.store(false, .release);
            self.thread = win.CreateThread(null, 0, run, self, 0, null) orelse return error.HostFailed;
        }
        fn notify(self: *Self) bool {
            self.wake.?.notify() catch {
                win.AcquireSRWLockExclusive(&self.lock);
                self.failure = 5;
                win.ReleaseSRWLockExclusive(&self.lock);
                return false;
            };
            return true;
        }
        fn run(parameter: ?*anyopaque) callconv(.winapi) u32 {
            const self: *Self = @ptrCast(@alignCast(parameter.?));
            if (writing) return self.runWriter();
            while (!self.stopping.load(.acquire)) {
                win.AcquireSRWLockExclusive(&self.lock);
                if (self.stopping.load(.acquire)) {
                    win.ReleaseSRWLockExclusive(&self.lock);
                    break;
                }
                const full = self.length == capacity;
                const free = capacity - self.length;
                if (full) _ = win.ResetEvent(self.space.?);
                if (!full) self.in_io = true;
                win.ReleaseSRWLockExclusive(&self.lock);
                if (full) {
                    if (win.WaitForSingleObject(self.space.?, 0xffffffff) != 0) break;
                    continue;
                }
                var bytes: [4096]u8 = undefined;
                var count: u32 = 0;
                const ok = win.ReadFile(self.stream.?, &bytes, 1, &count, null);
                const code = if (ok == 0) win.GetLastError() else 0;
                // Block for the first byte, then drain a bounded available burst.
                // Peek is not used as a periodic readiness loop.
                if (count == 1 and free > 1) {
                    var available: u32 = 0;
                    if (win.PeekNamedPipe(self.stream.?, null, 0, null, &available, null) != 0 and available != 0) {
                        var extra: u32 = 0;
                        const wanted: u32 = @intCast(@min(available, @min(free - 1, bytes.len - 1)));
                        _ = win.ReadFile(self.stream.?, bytes[1..].ptr, wanted, &extra, null);
                        count += extra;
                    }
                }
                win.AcquireSRWLockExclusive(&self.lock);
                self.in_io = false;
                if (count != 0) {
                    for (bytes[0..count]) |byte| {
                        self.buffer.?[(self.head + self.length) % capacity] = byte;
                        self.length += 1;
                    }
                } else if (code != 995) {
                    // A successful zero-byte pipe read is a zero-length write, not EOF.
                    if (code == 109 or code == 38) self.ended = true else if (ok == 0) self.failure = code;
                }
                const done = self.ended or self.failure != 0;
                win.ReleaseSRWLockExclusive(&self.lock);
                const notified = self.notify();
                if (done or !notified) break;
            }
            return 0;
        }
        fn runWriter(self: *Self) u32 {
            while (!self.stopping.load(.acquire)) {
                win.AcquireSRWLockExclusive(&self.lock);
                if (self.stopping.load(.acquire)) {
                    win.ReleaseSRWLockExclusive(&self.lock);
                    break;
                }
                const amount: u32 = @intCast(@min(self.length, @min(capacity - self.head, 4096)));
                if (amount == 0) _ = win.ResetEvent(self.space.?);
                const source = self.buffer.? + self.head;
                if (amount != 0) self.in_io = true;
                win.ReleaseSRWLockExclusive(&self.lock);
                if (amount == 0) {
                    if (win.WaitForSingleObject(self.space.?, 0xffffffff) != 0) break;
                    continue;
                }
                var count: u32 = 0;
                const code: u32 = if (self.write_callback) |callback| result: {
                    const sent = callback(source[0..amount]);
                    count = @intCast(sent.count);
                    break :result sent.code;
                } else result: {
                    const success = win.WriteFile(self.stream.?, source, amount, &count, null);
                    break :result if (success == 0) win.GetLastError() else 0;
                };
                win.AcquireSRWLockExclusive(&self.lock);
                self.in_io = false;
                self.head = (self.head + count) % capacity;
                self.length -= count;
                if ((code != 0 or count == 0) and !(code == 995 and self.stopping.load(.acquire))) {
                    self.failure = if (code == 0) 5 else code;
                    self.length = 0;
                }
                const done = self.failure != 0;
                win.ReleaseSRWLockExclusive(&self.lock);
                const notified = self.notify();
                if (done or !notified) break;
            }
            return 0;
        }
        /// Accepted data is copied while holding the queue lock; caller memory is
        /// never accessed by the background writer after this method returns.
        pub fn write(self: *Self, source: []const u8) Result {
            win.AcquireSRWLockExclusive(&self.lock);
            defer win.ReleaseSRWLockExclusive(&self.lock);
            if (self.failure != 0) return .{ .code = self.failure };
            if (self.stopping.load(.acquire)) return .{ .code = 995 };
            const count = @min(source.len, capacity - self.length);
            for (source[0..count]) |byte| {
                self.buffer.?[(self.head + self.length) % capacity] = byte;
                self.length += 1;
            }
            if (count != 0 and win.SetEvent(self.space.?) == 0) self.failure = 5;
            return .{ .count = count, .code = self.failure };
        }
        pub fn peek(self: *Self) Result {
            win.AcquireSRWLockExclusive(&self.lock);
            defer win.ReleaseSRWLockExclusive(&self.lock);
            return .{ .count = self.length, .eof = self.length == 0 and self.ended, .code = if (writing and self.stopping.load(.acquire) and self.failure == 0) 995 else if (writing or self.length == 0) self.failure else 0 };
        }
        pub fn read(self: *Self, destination: []u8) Result {
            win.AcquireSRWLockExclusive(&self.lock);
            defer win.ReleaseSRWLockExclusive(&self.lock);
            const count = @min(destination.len, self.length);
            for (destination[0..count]) |*byte| {
                byte.* = self.buffer.?[self.head];
                self.head = (self.head + 1) % capacity;
            }
            self.length -= count;
            if (count != 0 and win.SetEvent(self.space.?) == 0) self.failure = 5;
            return .{ .count = count, .eof = self.length == 0 and self.ended, .code = if (self.length == 0 and count == 0) self.failure else 0 };
        }
        /// Cancel repeatedly: the worker may enter ReadFile just after the first cancel.
        /// The queue remains valid on failure and is retained when pausing stdin.
        pub fn pause(self: *Self) base.Error!void {
            const thread = self.thread orelse return;
            win.AcquireSRWLockExclusive(&self.lock);
            self.stopping.store(true, .release);
            const signaled = win.SetEvent(self.space.?);
            win.ReleaseSRWLockExclusive(&self.lock);
            if (signaled == 0) return error.HostFailed;
            while (true) {
                const status = win.WaitForSingleObject(thread, 0);
                if (status == 0) break;
                if (status == 0xffffffff) return error.HostFailed;
                win.AcquireSRWLockExclusive(&self.lock);
                const cancel = self.in_io;
                const ok = if (cancel) win.CancelSynchronousIo(thread) else 1;
                const code = if (ok == 0) win.GetLastError() else 0;
                win.ReleaseSRWLockExclusive(&self.lock);
                if (ok == 0 and code != 1168) return error.HostFailed;
                _ = win.WaitForSingleObject(thread, 10);
            }
            if (win.CloseHandle(thread) == 0) return error.HostFailed;
            self.thread = null;
        }
        pub fn deinit(self: *Self) base.Error!void {
            try self.pause();
            if (self.space) |handle| {
                if (win.CloseHandle(handle) == 0) return error.HostFailed;
                self.space = null;
            }
            if (self.buffer) |buffer| {
                if (win.HeapFree(win.GetProcessHeap(), 0, buffer) == 0) return error.HostFailed;
                self.buffer = null;
            }
            self.* = .{};
        }
    };
}

test "Windows pipe reader cancels silent input and preserves queued bytes across pause" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    const native = struct {
        extern "kernel32" fn CreatePipe(*?Handle, *?Handle, ?*anyopaque, u32) callconv(.winapi) i32;
        extern "kernel32" fn WriteFile(Handle, [*]const u8, u32, *u32, ?*anyopaque) callconv(.winapi) i32;
    };
    var input: ?Handle = null;
    var output: ?Handle = null;
    try std.testing.expect(native.CreatePipe(&input, &output, null, 4096) != 0);
    defer _ = win.CloseHandle(input.?);
    defer if (output) |handle| {
        _ = win.CloseHandle(handle);
    };
    var wake = try Wake.init();
    defer wake.deinit() catch {};
    var reader: Reader = .{};
    defer reader.deinit() catch {};
    // Includes the publication-to-ReadFile cancellation race and slot reuse.
    for (0..20) |_| {
        try reader.start(input.?, &wake);
        try reader.pause();
    }
    try reader.start(input.?, &wake);
    var written: u32 = 0;
    try std.testing.expect(native.WriteFile(output.?, "", 0, &written, null) != 0);
    try std.testing.expect(native.WriteFile(output.?, "ABC", 3, &written, null) != 0);
    const deadline = try base.Deadline.afterMilliseconds(try @import("host_clock.zig").now(), 2000);
    while (reader.peek().count < 3) {
        const observed = wake.observe();
        if (reader.peek().count >= 3) break;
        try std.testing.expect(try wake.waitWithClock(observed, deadline, null, @import("host_clock.zig").clock) != .timeout);
    }
    try reader.pause();
    var result: [3]u8 = undefined;
    try std.testing.expectEqual(@as(usize, 3), reader.read(&result).count);
    try std.testing.expectEqualStrings("ABC", &result);
    try reader.start(input.?, &wake);
    _ = win.CloseHandle(output.?);
    output = null;
    while (!reader.peek().eof) {
        const observed = wake.observe();
        if (reader.peek().eof) break;
        try std.testing.expect(try wake.waitWithClock(observed, deadline, null, @import("host_clock.zig").clock) != .timeout);
    }
}

test "Windows queued writer owns caller bytes and reports later broken pipe errors" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    const native = struct {
        extern "kernel32" fn CreatePipe(*?Handle, *?Handle, ?*anyopaque, u32) callconv(.winapi) i32;
    };
    var input: ?Handle = null;
    var output: ?Handle = null;
    try std.testing.expect(native.CreatePipe(&input, &output, null, 4096) != 0);
    defer _ = win.CloseHandle(output.?);
    defer if (input) |handle| {
        _ = win.CloseHandle(handle);
    };
    var wake = try Wake.init();
    defer wake.deinit() catch {};
    var writer: Writer = .{};
    defer writer.deinit() catch {};
    try writer.start(output.?, &wake);
    var bytes = [_]u8{ 'A', 'B', 'C' };
    try std.testing.expectEqual(@as(usize, 3), writer.write(&bytes).count);
    @memset(&bytes, 'X');
    var received: [3]u8 = undefined;
    var count: u32 = 0;
    try std.testing.expect(win.ReadFile(input.?, &received, 3, &count, null) != 0);
    try std.testing.expectEqualStrings("ABC", &received);
    _ = win.CloseHandle(input.?);
    input = null;
    _ = writer.write("D");
    const deadline = try base.Deadline.afterMilliseconds(try @import("host_clock.zig").now(), 2000);
    while (writer.peek().code == 0) {
        const observed = wake.observe();
        if (writer.peek().code != 0) break;
        try std.testing.expect(try wake.wait(observed, deadline, null) != .timeout);
    }
    try std.testing.expectEqual(@as(usize, 0), writer.write("E").count);
    try std.testing.expect(writer.write("F").code != 0);
}

test "Windows full reader and blocked writer stop before borrowed handles close" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    const native = struct {
        extern "kernel32" fn CreatePipe(*?Handle, *?Handle, ?*anyopaque, u32) callconv(.winapi) i32;
    };
    var input: ?Handle = null;
    var output: ?Handle = null;
    try std.testing.expect(native.CreatePipe(&input, &output, null, 4096) != 0);
    defer _ = win.CloseHandle(input.?);
    defer _ = win.CloseHandle(output.?);
    var wake = try Wake.init();
    defer wake.deinit() catch {};
    var reader: Reader = .{};
    defer reader.deinit() catch {};
    try reader.start(input.?, &wake);
    const bytes: [Reader.capacity]u8 = @splat('Q');
    var count: u32 = 0;
    try std.testing.expect(win.WriteFile(output.?, &bytes, bytes.len, &count, null) != 0);
    const deadline = try base.Deadline.afterMilliseconds(try @import("host_clock.zig").now(), 2000);
    while (reader.peek().count != Reader.capacity) {
        const observed = wake.observe();
        if (reader.peek().count == Reader.capacity) break;
        try std.testing.expect(try wake.wait(observed, deadline, null) != .timeout);
    }
    for (0..100) |_| {
        try reader.pause();
        try reader.start(input.?, &wake);
    }
    try reader.deinit();
    var writer: Writer = .{};
    defer writer.deinit() catch {};
    try writer.start(output.?, &wake);
    try std.testing.expectEqual(@as(usize, Writer.capacity), writer.write(&bytes).count);
    // No peer reads: native writes must be cancelled during deinit.
    try writer.deinit();
}
