//! The host's audio thread for REQUIRE-AUDIO's words: it runs the core's sound engine
//! (src/core/sound_engine.zig) and sends its samples, 48 kHz 16-bit stereo, to the audio
//! device. On Windows the device is waveOut's; elsewhere, and when no device opens,
//! the thread makes the samples in time without sending them, so that PLAY, PLAY? and
//! the program behave the same without sound.
//!
//! The thread is started by the first audio word and runs until the program ends. It
//! takes the engine's queues without locks, as the engine expects of its consumer.
//!
//! While PLAY waits for room in the queues (`wait`), Ctrl+C is caught instead of ending
//! the program, and PLAY throws USER INTERRUPT; outside those waits it ends the program
//! as before.

const std = @import("std");
const builtin = @import("builtin");
const forth = @import("forth.zig");
const host_input = @import("host_input.zig");
const sound_engine = @import("core/sound_engine.zig");
const sound_psg = @import("core/sound_psg.zig");

const Engine = sound_engine.Engine;
const is_windows = builtin.os.tag == .windows;

pub const sample_rate: u32 = 48_000;
/// Each of the device's buffers holds 10 ms; eight of them are queued, so a note starts
/// about 80 ms after the audio thread takes it. With five, waveOut ran out of samples on
/// Windows 11 (it took 80 buffers a second instead of 100), and six had no margin.
const buffer_frames = sample_rate / 100;
const buffer_count = 8;

var engine: Engine = undefined;
var state: enum { idle, running, failed } = .idle;
var device_open = std.atomic.Value(bool).init(false);

/// The engine, starting the audio thread the first time; null when it cannot start.
pub fn start(_: ?*anyopaque) ?*Engine {
    switch (state) {
        .running => return &engine,
        .failed => return null,
        .idle => {},
    }
    engine = Engine.init(.ay8910, sound_psg.msx_clock, sample_rate);
    // The pool of samples, kept until the program ends; without it, samples do not fit
    // (OUT OF MEMORY) and the rest works.
    engine.pool = std.heap.page_allocator.alloc(i16, sound_engine.pcm.pool_samples) catch &.{};
    // The device is opened here, so that AUDIO? knows at once whether there is one.
    if (is_windows and windows.open()) device_open.store(true, .release);
    const thread = std.Thread.spawn(.{ .stack_size = 256 * 1024 }, run, .{}) catch {
        state = .failed;
        return null;
    };
    thread.detach();
    state = .running;
    return &engine;
}

/// Whether the samples reach a device: false when none opened, or after it failed.
pub fn hasDevice(_: ?*anyopaque) bool {
    return device_open.load(.acquire);
}

fn run() void {
    if (is_windows and device_open.load(.acquire)) {
        windows.play();
        // The device failed: the music goes on without it.
        device_open.store(false, .release);
    }
    playSilently();
}

/// Makes the samples as fast as a device would take them, and drops them.
fn playSilently() void {
    var buffer: [buffer_frames * 2]i16 = undefined;
    const begin = monotonicNanoseconds();
    var frames: u64 = 0;
    while (true) {
        sleepMilliseconds(5);
        const elapsed = monotonicNanoseconds() -% begin;
        const due = elapsed * sample_rate / std.time.ns_per_s;
        while (frames < due) {
            const count: usize = @intCast(@min(due - frames, buffer_frames));
            engine.render(buffer[0 .. count * 2]);
            frames += count;
        }
    }
}

// ---- PLAY's wait ----

var interrupted = std.atomic.Value(bool).init(false);

/// Waits a few milliseconds with Ctrl+C caught.
pub fn wait() forth.AudioWait {
    if (is_windows) {
        _ = windows.SetConsoleCtrlHandler(windows.ctrlHandler, 1);
        sleepMilliseconds(3);
        _ = windows.SetConsoleCtrlHandler(windows.ctrlHandler, 0);
    } else {
        const previous = posix.signal(posix.sigint, @intFromPtr(&posix.handler));
        sleepMilliseconds(3);
        _ = posix.signal(posix.sigint, previous);
    }
    if (interrupted.swap(false, .acq_rel)) return .interrupted;
    // In single-key mode Ctrl+C is a key, which the core reads.
    return if (host_input.isRaw()) .read_input else .waited;
}

// ---- Time ----

fn sleepMilliseconds(milliseconds: u32) void {
    if (is_windows) {
        windows.Sleep(milliseconds);
    } else {
        var request: std.c.timespec = .{ .sec = 0, .nsec = @intCast(@as(u64, milliseconds) * std.time.ns_per_ms) };
        var remaining: std.c.timespec = undefined;
        _ = std.c.nanosleep(&request, &remaining);
    }
}

fn monotonicNanoseconds() u64 {
    if (is_windows) {
        var count: i64 = 0;
        var frequency: i64 = 1;
        _ = windows.QueryPerformanceCounter(&count);
        _ = windows.QueryPerformanceFrequency(&frequency);
        const c: u64 = @intCast(count);
        const f: u64 = @intCast(frequency);
        return c / f * std.time.ns_per_s + c % f * std.time.ns_per_s / f;
    }
    var time: std.c.timespec = undefined;
    if (std.c.clock_gettime(std.c.CLOCK.MONOTONIC, &time) != 0) return 0;
    return @as(u64, @intCast(time.sec)) * std.time.ns_per_s + @as(u64, @intCast(time.nsec));
}

const posix = struct {
    extern "c" fn signal(c_int, usize) usize;
    const sigint = 2;

    fn handler(_: c_int) callconv(.c) void {
        interrupted.store(true, .release);
    }
};

// ---- Windows: waveOut ----

const windows = struct {
    const HANDLE = *anyopaque;
    extern "kernel32" fn Sleep(u32) callconv(.winapi) void;
    extern "kernel32" fn QueryPerformanceCounter(*i64) callconv(.winapi) c_int;
    extern "kernel32" fn QueryPerformanceFrequency(*i64) callconv(.winapi) c_int;
    extern "kernel32" fn CreateEventW(?*anyopaque, c_int, c_int, ?[*:0]const u16) callconv(.winapi) ?HANDLE;
    extern "kernel32" fn WaitForSingleObject(HANDLE, u32) callconv(.winapi) u32;
    extern "kernel32" fn GetCurrentThread() callconv(.winapi) HANDLE;
    extern "kernel32" fn SetThreadPriority(HANDLE, c_int) callconv(.winapi) c_int;
    extern "kernel32" fn SetConsoleCtrlHandler(?*const fn (u32) callconv(.winapi) c_int, c_int) callconv(.winapi) c_int;

    const WaveFormat = extern struct {
        format_tag: u16,
        channels: u16,
        samples_per_second: u32,
        bytes_per_second: u32,
        block_align: u16,
        bits_per_sample: u16,
        extra_size: u16,
    };
    const WaveHeader = extern struct {
        data: [*]u8,
        buffer_length: u32,
        bytes_recorded: u32 = 0,
        user: usize = 0,
        flags: u32 = 0,
        loops: u32 = 0,
        next: ?*WaveHeader = null,
        reserved: usize = 0,
    };
    extern "winmm" fn waveOutOpen(*?HANDLE, u32, *const WaveFormat, usize, usize, u32) callconv(.winapi) u32;
    extern "winmm" fn waveOutPrepareHeader(HANDLE, *WaveHeader, u32) callconv(.winapi) u32;
    extern "winmm" fn waveOutWrite(HANDLE, *WaveHeader, u32) callconv(.winapi) u32;

    const wave_mapper: u32 = 0xffff_ffff;
    const callback_event: u32 = 0x0005_0000;
    const header_done: u32 = 1;
    const ctrl_c_event: u32 = 0;
    const thread_priority_time_critical: c_int = 15;

    var device: ?HANDLE = null;
    var event: ?HANDLE = null;
    var samples: [buffer_count][buffer_frames * 2]i16 = undefined;
    var headers: [buffer_count]WaveHeader = undefined;

    fn ctrlHandler(kind: u32) callconv(.winapi) c_int {
        if (kind != ctrl_c_event) return 0;
        interrupted.store(true, .release);
        return 1;
    }

    /// Opens the default device; false when there is none.
    fn open() bool {
        event = CreateEventW(null, 0, 0, null) orelse return false;
        const format: WaveFormat = .{
            .format_tag = 1, // PCM
            .channels = 2,
            .samples_per_second = sample_rate,
            .bytes_per_second = sample_rate * 4,
            .block_align = 4,
            .bits_per_sample = 16,
            .extra_size = 0,
        };
        if (waveOutOpen(&device, wave_mapper, &format, @intFromPtr(event.?), 0, callback_event) != 0) return false;
        for (&headers, &samples) |*header, *buffer| {
            header.* = .{ .data = @ptrCast(buffer), .buffer_length = @sizeOf(@TypeOf(buffer.*)) };
            if (waveOutPrepareHeader(device.?, header, @sizeOf(WaveHeader)) != 0) return false;
        }
        return true;
    }

    /// Fills each buffer the device has finished with, in turn, until a write fails.
    fn play() void {
        _ = SetThreadPriority(GetCurrentThread(), thread_priority_time_critical);
        for (&headers, &samples) |*header, *buffer| {
            engine.render(buffer);
            if (waveOutWrite(device.?, header, @sizeOf(WaveHeader)) != 0) return;
        }
        var next: usize = 0;
        while (true) {
            _ = WaitForSingleObject(event.?, 100);
            // The device sets the flag from its own thread.
            while (@atomicLoad(u32, &headers[next].flags, .acquire) & header_done != 0) {
                engine.render(&samples[next]);
                if (waveOutWrite(device.?, &headers[next], @sizeOf(WaveHeader)) != 0) return;
                next = (next + 1) % buffer_count;
            }
        }
    }
};
