const std = @import("std");
const stream = @import("../core/sound_stream.zig");
const Stream = stream.Stream;
const Frame = stream.Frame;
const mix = stream.mix;

test "PCM bounded copy validates complete input, full ring and wrap" {
    var memory: [4]Frame = undefined;
    var s = try Stream.init(&memory, 48000, 48000, 1);
    const bytes = [_]u8{ 1, 0, 2, 0, 3, 0, 4, 0, 5, 0 };
    try std.testing.expectError(error.InvalidBuffer, s.write(&bytes, 6));
    try std.testing.expectEqual(@as(u32, 0), s.queued());
    try std.testing.expectEqual(@as(usize, 4), try s.write(&bytes, 5));
    try std.testing.expectEqual(@as(usize, 0), try s.write(&bytes, 1));
    try std.testing.expectEqual(@as(i16, 1), s.sample().left);
    try std.testing.expectEqual(@as(usize, 1), try s.write(bytes[8..], 1));
    for ([_]i16{ 2, 3, 4, 5 }) |value| try std.testing.expectEqual(value, s.sample().right);
    s.head.raw = std.math.maxInt(u32) - 1;
    s.tail.raw = s.head.raw;
    try std.testing.expectEqual(@as(usize, 4), try s.write(&bytes, 4));
    for ([_]i16{ 1, 2, 3, 4 }) |value| try std.testing.expectEqual(value, s.sample().left);
    try std.testing.expectEqual(@as(u32, 0), s.queued());
}

test "PCM hold, held frame accounting, silence episodes and restart" {
    var memory: [4]Frame = undefined;
    var s = try Stream.init(&memory, 8000, 48000, 1);
    try std.testing.expectEqual(@as(usize, 2), try s.write(&.{ 100, 0, 200, 0 }, 2));
    for (0..5) |_| try std.testing.expectEqual(@as(i16, 100), s.sample().left);
    try std.testing.expectEqual(@as(u32, 2), s.queued());
    try std.testing.expectEqual(@as(i16, 100), s.sample().left);
    try std.testing.expectEqual(@as(u32, 1), s.queued());
    for (0..6) |_| try std.testing.expectEqual(@as(i16, 200), s.sample().left);
    for (0..9) |_| try std.testing.expectEqual(@as(i16, 0), s.sample().left);
    try std.testing.expectEqual(@as(u64, 1), s.underruns.load(.acquire));
    _ = try s.write(&.{ 100, 0 }, 1);
    for (0..6) |_| try std.testing.expectEqual(@as(i16, 100), s.sample().left);
    _ = s.sample();
    try std.testing.expectEqual(@as(u64, 2), s.underruns.load(.acquire));
}

test "PCM rational rate exact frame boundary and stereo signed decoding" {
    var memory: [512]Frame = undefined;
    var s = try Stream.init(&memory, 44100, 48000, 2);
    var bytes: [441 * 4]u8 = undefined;
    for (0..441) |i| {
        std.mem.writeInt(i16, bytes[i * 4 ..][0..2], @intCast(i + 1), .little);
        std.mem.writeInt(i16, bytes[i * 4 + 2 ..][0..2], -@as(i16, @intCast(i + 1)), .little);
    }
    _ = try s.write(&bytes, 441);
    for (0..480) |i| {
        const f = s.sample();
        const expected: i16 = @intCast(i * 44100 / 48000 + 1);
        try std.testing.expectEqual(expected, f.left);
        try std.testing.expectEqual(-expected, f.right);
    }
    try std.testing.expectEqual(@as(u32, 0), s.queued());
    try std.testing.expectEqual(@as(u64, 0), s.phase);
    try std.testing.expectEqual(@as(i16, 32767), mix(30000, 10000));
    try std.testing.expectEqual(@as(i16, -32768), mix(-30000, -10000));
}

test "PCM downsampling and unaligned little endian input" {
    var memory: [8]Frame = undefined;
    var s = try Stream.init(&memory, 192000, 48000, 2);
    const data = [_]u8{ 99, 0, 128, 255, 127, 1, 0, 2, 0, 3, 0, 4, 0, 5, 0, 6, 0, 7, 0, 8, 0 };
    _ = try s.write(data[1..], 5);
    const first = s.sample();
    try std.testing.expectEqual(@as(i16, -32768), first.left);
    try std.testing.expectEqual(@as(i16, 32767), first.right);
    try std.testing.expectEqual(@as(u32, 1), s.queued());
    try std.testing.expectEqual(@as(i16, 7), s.sample().left);
    try std.testing.expectEqual(@as(u32, 0), s.queued());
    try std.testing.expectEqual(@as(i16, 0), s.sample().left);
}

test "PCM true producer consumer publication stress" {
    const Worker = struct {
        fn produce(s: *Stream, abort: *std.atomic.Value(bool)) void {
            var bytes: [2]u8 = undefined;
            for (0..100000) |i| {
                std.mem.writeInt(i16, &bytes, @intCast(i % 30000 + 1), .little);
                while ((s.write(&bytes, 1) catch unreachable) == 0) {
                    if (abort.load(.acquire)) return;
                    std.atomic.spinLoopHint();
                }
            }
        }
    };
    var memory: [256]Frame = undefined;
    var s = try Stream.init(&memory, 48000, 48000, 1);
    var abort = std.atomic.Value(bool).init(false);
    const worker = try std.Thread.spawn(.{}, Worker.produce, .{ &s, &abort });
    defer {
        abort.store(true, .release);
        worker.join();
    }
    var count: usize = 0;
    while (count < 100000) {
        const f = s.sample();
        if (f.left == 0) {
            std.atomic.spinLoopHint();
            continue;
        }
        try std.testing.expectEqual(@as(i16, @intCast(count % 30000 + 1)), f.left);
        try std.testing.expectEqual(f.left, f.right);
        count += 1;
    }
}

test "PCM detach acknowledges previous reads before storage can be released" {
    var memory: [4]Frame = undefined;
    var s = try Stream.init(&memory, 48000, 48000, 1);
    var control = stream.Control{};
    const opening = try control.publish(&s);
    try std.testing.expect(!control.completed(opening));
    try std.testing.expectError(error.Busy, control.publish(null));
    control.apply();
    try std.testing.expect(control.completed(opening));
    try std.testing.expect(control.active == &s);
    _ = try s.write(&.{ 42, 0 }, 1);
    const borrowed = control.active.?;
    const closing = try control.publish(null);
    // A paused consumer still owns the previous stream. Neither timeout nor
    // another OPEN can turn a queued detach into permission to free storage.
    try std.testing.expect(!control.completed(closing));
    try std.testing.expectError(error.Busy, control.publish(&s));
    try std.testing.expectEqual(@as(i16, 42), borrowed.sample().left);
    control.apply();
    try std.testing.expect(control.completed(closing));
    try std.testing.expect(control.active == null);
    control.next = std.math.maxInt(u32);
    try std.testing.expectError(error.IdentityExhausted, control.publish(&s));
    _ = try control.publish(null);
    control.apply();
    try std.testing.expectError(error.IdentityExhausted, control.publish(null));
}

test "PCM rate matrix matches absolute rational positions without block drift" {
    var memory: [8192]Frame = undefined;
    var bytes: [8192 * 2]u8 = undefined;
    for (0..8192) |i| std.mem.writeInt(i16, bytes[i * 2 ..][0..2], @intCast(i + 1), .little);
    for ([_]u32{ 8000, 11025, 22050, 44100, 48000, 96000, 192000 }) |rate| {
        var s = try Stream.init(&memory, rate, 48000, 1);
        // Several source writes and output blocks must follow one rational clock.
        _ = try s.write(bytes[0 .. 2000 * 2], 2000);
        _ = try s.write(bytes[2000 * 2 ..], 6192);
        for (0..2000) |i| {
            const expected: i16 = @intCast(i * rate / 48000 + 1);
            try std.testing.expectEqual(expected, s.sample().left);
        }
        try std.testing.expectEqual(@as(u32, @intCast(8192 - 2000 * rate / 48000)), s.queued());
        try std.testing.expectEqual(@as(u64, 2000 * rate % 48000), s.phase);
    }
}

test "PCM rejects invalid storage configuration and byte count overflow" {
    var memory: [4]Frame = undefined;
    try std.testing.expectError(error.InvalidConfig, Stream.init(memory[0..3], 48000, 48000, 1));
    try std.testing.expectError(error.InvalidConfig, Stream.init(&memory, 0, 48000, 1));
    try std.testing.expectError(error.InvalidConfig, Stream.init(&memory, 48000, 0, 1));
    try std.testing.expectError(error.InvalidConfig, Stream.init(&memory, 48000, 48000, 3));
    var s = try Stream.init(&memory, 48000, 48000, 2);
    try std.testing.expectError(error.InvalidBuffer, s.write(&.{}, std.math.maxInt(usize)));
    try std.testing.expectEqual(@as(usize, 0), try s.write(&.{}, 0));
    try std.testing.expectEqual(@as(u32, 0), s.queued());
}

test "PCM downsampling preserves skipped positions across source writes" {
    var memory: [16]Frame = undefined;
    var s = try Stream.init(&memory, 192000, 48000, 1);
    _ = try s.write(&.{ 1, 0, 2, 0, 3, 0, 4, 0, 5, 0 }, 5);
    try std.testing.expectEqual(@as(i16, 1), s.sample().left);
    try std.testing.expectEqual(@as(i16, 5), s.sample().left);
    _ = try s.write(&.{ 6, 0, 7, 0, 8, 0, 9, 0 }, 4);
    try std.testing.expectEqual(@as(i16, 9), s.sample().left);
    try std.testing.expectEqual(@as(u64, 0), s.underruns.load(.acquire));
}

test "PCM previous control completion stays true after later acknowledgements" {
    var memory: [4]Frame = undefined;
    var s = try Stream.init(&memory, 48000, 48000, 1);
    var c = stream.Control{};
    _ = try c.publish(&s);
    c.apply();
    const closing = try c.publish(null);
    c.apply();
    _ = try c.publish(&s);
    c.apply();
    try std.testing.expect(c.completed(closing));
    try std.testing.expect(!c.completed(0));
}

test "PCM initial silence is not an underrun episode" {
    var memory: [4]Frame = undefined;
    var s = try Stream.init(&memory, 48000, 48000, 1);
    for (0..16) |_| _ = s.sample();
    try std.testing.expectEqual(@as(u64, 0), s.underruns.load(.acquire));
    _ = try s.write(&.{ 1, 0 }, 1);
    _ = s.sample();
    _ = s.sample();
    try std.testing.expectEqual(@as(u64, 1), s.underruns.load(.acquire));
}

test "PCM engine mixes after legacy filter and detaches at block boundary" {
    const engine = @import("../core/sound_engine.zig");
    var sound = engine.Engine.init(48000);
    var memory: [4]Frame = undefined;
    var s = try Stream.init(&memory, 48000, 48000, 2);
    _ = try s.write(&.{ 0xff, 0x7f, 0, 0x80, 0x34, 0x12, 0xcc, 0xed }, 2);
    const opening = try sound.pcm_control.publish(&s);
    var output: [4]i16 = undefined;
    sound.render(&output);
    try std.testing.expect(sound.pcm_control.completed(opening));
    try std.testing.expectEqualSlices(i16, &.{ 32767, -32768, 4660, -4660 }, &output);
    const closing = try sound.pcm_control.publish(null);
    sound.render(&output);
    try std.testing.expect(sound.pcm_control.completed(closing));
    try std.testing.expectEqualSlices(i16, &.{ 0, 0, 0, 0 }, &output);
}

test "PCM capacity stays within latency and memory budgets at every supported rate" {
    for ([_]u32{ 8000, 11025, 22050, 44100, 48000, 96000, 192000 }) |rate| {
        var found = false;
        var capacity: u32 = 256;
        while (capacity <= 65536) : (capacity *= 2) {
            if (stream.validCapacity(rate, capacity)) {
                try std.testing.expect(capacity <= rate);
                try std.testing.expect(@as(u64, capacity) * 25 >= rate);
                found = true;
            }
        }
        try std.testing.expect(found);
    }
    try std.testing.expect(!stream.validCapacity(8000, 8192));
    try std.testing.expect(!stream.validCapacity(192000, 4096));
    try std.testing.expect(stream.validCapacity(192000, 8192));
    try std.testing.expect(!stream.validCapacity(48000, 1000));
}

test "PCM detach discards queued frames before reusing the backing buffer" {
    var memory: [4]Frame = undefined;
    var s = try Stream.init(&memory, 8000, 48000, 1);
    var c = stream.Control{};
    _ = try c.publish(&s);
    c.apply();
    _ = try s.write(&.{ 1, 0, 2, 0 }, 2);
    _ = s.sample();
    _ = try c.publish(null);
    c.apply();
    try std.testing.expectEqual(@as(u32, 0), s.queued());
    _ = try s.write(&.{ 3, 0 }, 1);
    _ = try c.publish(&s);
    c.apply();
    for (0..6) |_| try std.testing.expectEqual(@as(i16, 3), s.sample().left);
    try std.testing.expectEqual(@as(u32, 0), s.queued());
}

test "PCM nonunity concurrent publication follows the continuous rational clock" {
    const Worker = struct {
        fn produce(s: *Stream, abort: *std.atomic.Value(bool)) void {
            var bytes: [2]u8 = undefined;
            for (0..44100) |i| {
                std.mem.writeInt(i16, &bytes, @intCast(i % 30000 + 1), .little);
                while ((s.write(&bytes, 1) catch unreachable) == 0) {
                    if (abort.load(.acquire)) return;
                    std.atomic.spinLoopHint();
                }
            }
        }
    };
    var memory: [256]Frame = undefined;
    var s = try Stream.init(&memory, 44100, 48000, 1);
    var abort = std.atomic.Value(bool).init(false);
    const worker = try std.Thread.spawn(.{}, Worker.produce, .{ &s, &abort });
    defer {
        abort.store(true, .release);
        worker.join();
    }
    for (0..48000) |i| {
        // Consumer-only indices: wait for publication rather than inserting an
        // actual timed underrun into this continuity test.
        while (s.tail.load(.acquire) == s.head.raw) std.atomic.spinLoopHint();
        const expected: i16 = @intCast((i * 44100 / 48000) % 30000 + 1);
        try std.testing.expectEqual(expected, s.sample().left);
    }
    try std.testing.expectEqual(@as(u64, 0), s.phase);
    try std.testing.expectEqual(@as(u32, 0), s.tail.load(.acquire) -% s.head.raw);
}

test "PCM intentional drain suppresses only its empty tail" {
    var memory: [4]Frame = undefined;
    var s = try Stream.init(&memory, 48000, 48000, 1);
    _ = try s.write(&.{ 1, 0 }, 1);
    s.draining.store(true, .release);
    _ = s.sample();
    for (0..8) |_| _ = s.sample();
    try std.testing.expectEqual(@as(u32, 0), s.underruns.load(.acquire));
    // A timed out/cancelled drain returns to running; a subsequent actual empty
    // output is once again an underrun, rather than permanently suppressed.
    s.draining.store(false, .release);
    _ = s.sample();
    try std.testing.expectEqual(@as(u32, 1), s.underruns.load(.acquire));
}
