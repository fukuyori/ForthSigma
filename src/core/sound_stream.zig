const std = @import("std");

/// Bounded PCM transport and sample/hold conversion. Public words and host
/// lifetime integration are separate; this module owns no OS resource.
/// One producer calls write/queued; one consumer calls sample. Storage and this
/// object must stay at stable addresses until the consumer has acknowledged close.
pub const Frame = struct { left: i16, right: i16 };

/// Public configuration bounds: 40 ms..1 second of input, at most 256 KiB.
/// Internal tests may use smaller rings with Stream.init.
pub fn validCapacity(hz: u32, capacity: u32) bool {
    return hz >= 8000 and hz <= 192000 and capacity >= 256 and capacity <= 65536 and
        std.math.isPowerOfTwo(capacity) and capacity <= hz and @as(u64, capacity) * 25 >= hz;
}
pub const Stream = struct {
    frames: []Frame,
    input_rate: u32,
    output_rate: u32,
    channels: u32,
    head: std.atomic.Value(u32) = .init(0),
    tail: std.atomic.Value(u32) = .init(0),
    // Consumer-only phase and episode state. An underrun restarts phase at zero.
    phase: u64 = 0,
    skip: u64 = 0,
    started: bool = false,
    starving: bool = false,
    underruns: std.atomic.Value(u32) = .init(0),
    /// Producer-owned suppression for intentional drain. Set before waiting.
    draining: std.atomic.Value(bool) = .init(false),

    pub fn init(frames: []Frame, rate: u32, output: u32, channels: u32) error{InvalidConfig}!Stream {
        if (frames.len == 0 or frames.len > 65536 or !std.math.isPowerOfTwo(frames.len) or
            rate < 8000 or rate > 192000 or output < 8000 or output > 192000 or (channels != 1 and channels != 2)) return error.InvalidConfig;
        return .{ .frames = frames, .input_rate = rate, .output_rate = output, .channels = channels };
    }

    /// Producer: held resampler frames remain queued until their final use.
    pub fn queued(self: *const Stream) u32 {
        return self.tail.raw -% self.head.load(.acquire);
    }
    pub fn free(self: *const Stream) u32 {
        return @as(u32, @intCast(self.frames.len)) - self.queued();
    }
    /// Nonblocking copy of complete input frames. Validate all requested bytes,
    /// even when only a prefix currently fits. No borrowed input survives return.
    pub fn write(self: *Stream, bytes: []const u8, requested: usize) error{InvalidBuffer}!usize {
        const count = @mulWithOverflow(requested, @as(usize, self.channels) * 2);
        if (count[1] != 0 or bytes.len < count[0]) return error.InvalidBuffer;
        const fit = @min(requested, self.free());
        const tail = self.tail.raw;
        for (0..fit) |i| {
            const at = i * self.channels * 2;
            const left = std.mem.readInt(i16, bytes[at..][0..2], .little);
            const right = if (self.channels == 1) left else std.mem.readInt(i16, bytes[at + 2 ..][0..2], .little);
            self.frames[(tail +% @as(u32, @intCast(i))) % self.frames.len] = .{ .left = left, .right = right };
        }
        self.tail.store(tail +% @as(u32, @intCast(fit)), .release);
        return fit;
    }
    /// Consumer, at a quiescent render boundary. Never called by the producer.
    fn begin(self: *Stream) void {
        self.phase = 0;
        self.skip = 0;
        self.started = false;
        self.starving = false;
        self.underruns.store(0, .release);
    }
    fn discard(self: *Stream) void {
        self.head.store(self.tail.load(.acquire), .release);
        self.phase = 0;
        self.skip = 0;
    }
    /// Consumer: rational sample/hold, no anti-aliasing. Empty input is silence.
    pub fn sample(self: *Stream) Frame {
        var head = self.head.raw;
        var available = self.tail.load(.acquire) -% head;
        if (self.skip != 0) {
            const dropped: u32 = @intCast(@min(self.skip, available));
            head +%= dropped;
            available -= dropped;
            self.skip -= dropped;
            self.head.store(head, .release);
        }
        if (available == 0) {
            if (!self.draining.load(.acquire)) {
                if (self.started and !self.starving) {
                    const value = self.underruns.raw;
                    self.underruns.store(value +| 1, .release);
                }
                self.starving = true;
            }
            self.phase = 0;
            self.skip = 0;
            return .{ .left = 0, .right = 0 };
        }
        self.starving = false;
        self.started = true;
        const result = self.frames[head % self.frames.len];
        self.phase += self.input_rate;
        const advance = self.phase / self.output_rate;
        self.phase %= self.output_rate;
        const consumed: u32 = @intCast(@min(advance, available));
        self.head.store(head +% consumed, .release);
        self.skip = advance - consumed;
        return result;
    }
};

/// Mix after the legacy engine filter so PCM is not DC-filtered or scaled by it.
pub fn mix(legacy: i16, input: i16) i16 {
    return @intCast(std.math.clamp(@as(i32, legacy) + input, std.math.minInt(i16), std.math.maxInt(i16)));
}

/// One producer publishes immutable control data; the consumer acknowledges only
/// at a render boundary, after all reads through the previous pointer have ended.
/// A timeout does not cancel a published request or release either object.
pub const Control = struct {
    request: std.atomic.Value(u32) = .init(0),
    acknowledged: std.atomic.Value(u32) = .init(0),
    pending: ?*Stream = null,
    // Consumer only. The producer must use completed() rather than reading this.
    active: ?*Stream = null,
    next: u32 = 1,

    pub fn publish(self: *Control, target: ?*Stream) error{ Busy, IdentityExhausted }!u32 {
        if (self.request.raw != self.acknowledged.load(.acquire)) return error.Busy;
        const serial = self.next;
        // Reserve the final serial for detaching a currently active stream.
        if (serial == 0 or (serial == std.math.maxInt(u32) and target != null)) return error.IdentityExhausted;
        self.next = if (serial == std.math.maxInt(u32)) 0 else serial + 1;
        self.pending = target;
        self.request.store(serial, .release);
        return serial;
    }
    /// Producer: may release the OLD stream only after a detach/replace ack.
    pub fn completed(self: *const Control, serial: u32) bool {
        return serial != 0 and self.acknowledged.load(.acquire) >= serial;
    }
    /// Consumer: invoke once at the start of a render block. Never concurrently
    /// with a prior render using active. No allocation, host callback or wait.
    pub fn apply(self: *Control) void {
        const serial = self.request.load(.acquire);
        if (serial == self.acknowledged.raw) return;
        if (self.active) |previous| previous.discard();
        self.active = self.pending;
        if (self.active) |current| current.begin();
        self.acknowledged.store(serial, .release);
    }
};
