//! The host's audio thread for REQUIRE-AUDIO's words: it runs the core's sound engine
//! (src/core/sound_engine.zig) and sends its samples, 48 kHz 16-bit stereo, to the audio
//! device. On Windows the device is waveOut's. On Linux it is PulseAudio's or ALSA's,
//! their libraries loaded when the program runs (in a build that can load them), or else
//! the first of the commands pacat, pw-play, and aplay, which the samples go to through
//! a pipe (the static musl builds). On macOS it is an AudioQueue of AudioToolbox, the
//! framework loaded when the program runs (so that a build made on another system needs
//! no macOS SDK). When no device opens, the thread makes the samples in time without
//! sending them, so that PLAY, PLAY? and the program behave the same without sound.
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
const is_linux = builtin.os.tag == .linux;
const is_macos = builtin.os.tag == .macos;

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
    if (is_linux and linux.open()) device_open.store(true, .release);
    if (is_macos and macos.open()) device_open.store(true, .release);
    if (!startThread()) {
        state = .failed;
        return null;
    }
    state = .running;
    return &engine;
}

/// Whether the samples reach a device: false when none opened, or after it failed.
pub fn hasDevice(_: ?*anyopaque) bool {
    return device_open.load(.acquire);
}

/// Starts the audio thread, which runs until the program ends. Elsewhere than on Windows
/// it is pthread_create's with its default attributes: Zig 0.17's std.Thread.spawn sets
/// attributes that glibc 2.39 refuses (EINVAL) in an x86_64-linux-gnu build.
fn startThread() bool {
    if (is_windows) {
        const thread = std.Thread.spawn(.{ .stack_size = 256 * 1024 }, run, .{}) catch return false;
        thread.detach();
        return true;
    }
    const posix_thread = struct {
        extern "c" fn pthread_create(*usize, ?*const anyopaque, *const fn (?*anyopaque) callconv(.c) ?*anyopaque, ?*anyopaque) c_int;
        extern "c" fn pthread_detach(usize) c_int;
        fn entry(_: ?*anyopaque) callconv(.c) ?*anyopaque {
            run();
            return null;
        }
    };
    var handle: usize = 0;
    if (posix_thread.pthread_create(&handle, null, posix_thread.entry, null) != 0) return false;
    _ = posix_thread.pthread_detach(handle);
    return true;
}

fn run() void {
    if (is_windows and device_open.load(.acquire)) {
        windows.play();
        // The device failed: the music goes on without it.
        device_open.store(false, .release);
    }
    if (is_linux and device_open.load(.acquire)) {
        linux.play();
        device_open.store(false, .release);
    }
    if (is_macos and device_open.load(.acquire)) {
        macos.play();
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

// ---- Linux: PulseAudio, ALSA, or a command through a pipe ----

const linux = struct {
    extern "c" fn pipe(*[2]c_int) c_int;
    extern "c" fn close(c_int) c_int;
    extern "c" fn write(c_int, [*]const u8, usize) isize;
    extern "c" fn fcntl(c_int, c_int, ...) c_int;
    extern "c" fn waitpid(c_int, ?*c_int, c_int) c_int;
    extern "c" fn posix_spawnp(*c_int, [*:0]const u8, ?*const anyopaque, ?*const anyopaque, [*:null]const ?[*:0]const u8, [*:null]const ?[*:0]const u8) c_int;
    extern "c" fn posix_spawn_file_actions_init(*anyopaque) c_int;
    extern "c" fn posix_spawn_file_actions_destroy(*anyopaque) c_int;
    extern "c" fn posix_spawn_file_actions_adddup2(*anyopaque, c_int, c_int) c_int;
    extern "c" fn posix_spawn_file_actions_addclose(*anyopaque, c_int) c_int;
    extern "c" fn posix_spawn_file_actions_addopen(*anyopaque, c_int, [*:0]const u8, c_int, c_uint) c_int;
    extern "c" fn posix_spawnattr_init(*anyopaque) c_int;
    extern "c" fn posix_spawnattr_destroy(*anyopaque) c_int;
    extern "c" fn posix_spawnattr_setflags(*anyopaque, c_short) c_int;
    extern "c" fn posix_spawnattr_setpgroup(*anyopaque, c_int) c_int;
    extern "c" fn sigemptyset(*anyopaque) c_int;
    extern "c" fn sigaddset(*anyopaque, c_int) c_int;
    extern "c" fn pthread_sigmask(c_int, ?*const anyopaque, ?*anyopaque) c_int;
    extern "c" var environ: [*:null]const ?[*:0]const u8;

    const f_setfd = 2;
    const fd_cloexec = 1;
    const f_setpipe_sz = 1031;
    const o_wronly = 1;
    const posix_spawn_setpgroup = 2;
    const sig_block = 0;
    const sigpipe = 13;
    const wnohang = 1;
    const eintr = 4;

    /// A static musl build cannot load shared libraries (as host_gamepad.zig says).
    const can_load = !(builtin.link_mode == .static and
        (builtin.abi == .musl or builtin.abi == .musleabi or builtin.abi == .musleabihf));

    var backend: enum { none, pulse, alsa, pipe } = .none;

    // PulseAudio's simple API.
    const SampleSpec = extern struct { format: c_int, rate: u32, channels: u8 };
    const BufferAttr = extern struct { maxlength: u32, tlength: u32, prebuf: u32, minreq: u32, fragsize: u32 };
    const PulseNew = *const fn (?[*:0]const u8, [*:0]const u8, c_int, ?[*:0]const u8, [*:0]const u8, *const SampleSpec, ?*const anyopaque, ?*const BufferAttr, ?*c_int) callconv(.c) ?*anyopaque;
    const PulseWrite = *const fn (*anyopaque, [*]const u8, usize, ?*c_int) callconv(.c) c_int;
    var pulse: ?*anyopaque = null;
    var pulse_write: PulseWrite = undefined;

    // ALSA.
    const AlsaOpen = *const fn (*?*anyopaque, [*:0]const u8, c_int, c_int) callconv(.c) c_int;
    const AlsaSetParams = *const fn (*anyopaque, c_int, c_int, c_uint, c_uint, c_int, c_uint) callconv(.c) c_int;
    const AlsaWrite = *const fn (*anyopaque, [*]const u8, c_ulong) callconv(.c) c_long;
    const AlsaRecover = *const fn (*anyopaque, c_int, c_int) callconv(.c) c_int;
    var pcm: ?*anyopaque = null;
    var alsa_write: AlsaWrite = undefined;
    var alsa_recover: AlsaRecover = undefined;

    // The command's pipe.
    var pipe_fd: c_int = -1;

    fn open() bool {
        if (can_load) {
            if (openPulse()) {
                backend = .pulse;
                return true;
            }
            if (openAlsa()) {
                backend = .alsa;
                return true;
            }
        }
        if (openPipe()) {
            backend = .pipe;
            return true;
        }
        return false;
    }

    /// PulseAudio (and PipeWire's PulseAudio server), about 40 ms ahead.
    fn openPulse() bool {
        var lib = std.DynLib.open("libpulse-simple.so.0") catch return false;
        const new = lib.lookup(PulseNew, "pa_simple_new") orelse return false;
        pulse_write = lib.lookup(PulseWrite, "pa_simple_write") orelse return false;
        const spec: SampleSpec = .{ .format = 3, .rate = sample_rate, .channels = 2 }; // PA_SAMPLE_S16LE
        const none = std.math.maxInt(u32);
        const attr: BufferAttr = .{ .maxlength = none, .tlength = sample_rate * 4 * 40 / 1000, .prebuf = none, .minreq = none, .fragsize = none };
        pulse = new(null, "FORTH/Sigma", 1, null, "sound", &spec, null, &attr, null) orelse return false; // PA_STREAM_PLAYBACK
        return true;
    }

    /// ALSA's default device, about 50 ms ahead.
    fn openAlsa() bool {
        var lib = std.DynLib.open("libasound.so.2") catch return false;
        const pcm_open = lib.lookup(AlsaOpen, "snd_pcm_open") orelse return false;
        const set_params = lib.lookup(AlsaSetParams, "snd_pcm_set_params") orelse return false;
        alsa_write = lib.lookup(AlsaWrite, "snd_pcm_writei") orelse return false;
        alsa_recover = lib.lookup(AlsaRecover, "snd_pcm_recover") orelse return false;
        if (pcm_open(&pcm, "default", 0, 0) < 0) return false; // SND_PCM_STREAM_PLAYBACK
        // SND_PCM_FORMAT_S16_LE, SND_PCM_ACCESS_RW_INTERLEAVED, resampling allowed.
        return set_params(pcm.?, 2, 3, 2, sample_rate, 1, 50_000) >= 0;
    }

    /// The first of the commands that starts and is still running a moment later. It runs
    /// in its own process group, so that Ctrl+C at the terminal does not end it; it ends
    /// when the pipe closes with the program.
    fn openPipe() bool {
        const commands = [_][]const ?[*:0]const u8{
            &.{ "pacat", "--raw", "--format=s16le", "--rate=48000", "--channels=2", "--latency-msec=40", null },
            // Newer PipeWire reads stdin as a sound file unless --raw says otherwise;
            // older versions have no --raw and end at once, so the second form follows.
            &.{ "pw-play", "--raw", "--latency=40ms", "--format=s16", "--rate=48000", "--channels=2", "-", null },
            &.{ "pw-play", "--latency=40ms", "--format=s16", "--rate=48000", "--channels=2", "-", null },
            &.{ "aplay", "-q", "-B", "40000", "-t", "raw", "-f", "S16_LE", "-r", "48000", "-c", "2", null },
        };
        for (commands) |argv| {
            if (spawn(@ptrCast(argv.ptr))) return true;
        }
        return false;
    }

    fn spawn(argv: [*:null]const ?[*:0]const u8) bool {
        var fds: [2]c_int = undefined;
        if (pipe(&fds) != 0) return false;
        var actions: [256]u8 align(16) = undefined;
        var attr: [512]u8 align(16) = undefined;
        _ = posix_spawn_file_actions_init(&actions);
        defer _ = posix_spawn_file_actions_destroy(&actions);
        _ = posix_spawn_file_actions_adddup2(&actions, fds[0], 0);
        _ = posix_spawn_file_actions_addclose(&actions, fds[0]);
        _ = posix_spawn_file_actions_addclose(&actions, fds[1]);
        _ = posix_spawn_file_actions_addopen(&actions, 1, "/dev/null", o_wronly, 0);
        _ = posix_spawn_file_actions_addopen(&actions, 2, "/dev/null", o_wronly, 0);
        _ = posix_spawnattr_init(&attr);
        defer _ = posix_spawnattr_destroy(&attr);
        _ = posix_spawnattr_setflags(&attr, posix_spawn_setpgroup);
        _ = posix_spawnattr_setpgroup(&attr, 0);
        var pid: c_int = 0;
        const failed = posix_spawnp(&pid, argv[0].?, &actions, &attr, argv, environ) != 0;
        _ = close(fds[0]);
        if (failed) {
            _ = close(fds[1]);
            return false;
        }
        // Other children (SYSTEM, the Tcl program) must not keep the pipe open; a small
        // pipe keeps the delay short (8 KiB: about 40 ms).
        _ = fcntl(fds[1], f_setfd, @as(c_int, fd_cloexec));
        _ = fcntl(fds[1], f_setpipe_sz, @as(c_int, 8192));
        // A command that cannot play (no server) ends at once.
        sleepMilliseconds(100);
        var status: c_int = 0;
        if (waitpid(pid, &status, wnohang) == pid) {
            _ = close(fds[1]);
            return false;
        }
        pipe_fd = fds[1];
        return true;
    }

    /// Sends the samples until the device fails.
    fn play() void {
        // A write to a command that has ended fails here instead of ending the program.
        var set: [128]u8 align(8) = undefined;
        _ = sigemptyset(&set);
        _ = sigaddset(&set, sigpipe);
        _ = pthread_sigmask(sig_block, &set, null);
        var buffer: [buffer_frames * 2]i16 = undefined;
        while (true) {
            engine.render(&buffer);
            const bytes = std.mem.sliceAsBytes(&buffer);
            switch (backend) {
                .pulse => if (pulse_write(pulse.?, bytes.ptr, bytes.len, null) < 0) return,
                .alsa => {
                    var done: usize = 0;
                    while (done < buffer_frames) {
                        const written = alsa_write(pcm.?, bytes[done * 4 ..].ptr, buffer_frames - done);
                        if (written < 0) {
                            if (alsa_recover(pcm.?, @intCast(written), 1) < 0) return;
                            continue;
                        }
                        done += @intCast(written);
                    }
                },
                .pipe => {
                    var done: usize = 0;
                    while (done < bytes.len) {
                        const written = write(pipe_fd, bytes[done..].ptr, bytes.len - done);
                        if (written < 0) {
                            if (std.c._errno().* == eintr) continue;
                            return;
                        }
                        done += @intCast(written);
                    }
                },
                .none => return,
            }
        }
    }
};

// ---- macOS: AudioToolbox's AudioQueue ----

const macos = struct {
    const AudioQueue = *anyopaque;
    const StreamDescription = extern struct {
        sample_rate: f64,
        format_id: u32,
        format_flags: u32,
        bytes_per_packet: u32,
        frames_per_packet: u32,
        bytes_per_frame: u32,
        channels_per_frame: u32,
        bits_per_channel: u32,
        reserved: u32 = 0,
    };
    const Buffer = extern struct {
        capacity: u32,
        data: [*]u8,
        size: u32,
        user: ?*anyopaque,
        packet_description_capacity: u32,
        packet_descriptions: ?*anyopaque,
        packet_description_count: u32,
    };
    const Callback = *const fn (?*anyopaque, AudioQueue, *Buffer) callconv(.c) void;
    const NewOutput = *const fn (*const StreamDescription, Callback, ?*anyopaque, ?*anyopaque, ?*anyopaque, u32, *?AudioQueue) callconv(.c) i32;
    const AllocateBuffer = *const fn (AudioQueue, u32, *?*Buffer) callconv(.c) i32;
    const EnqueueBuffer = *const fn (AudioQueue, *Buffer, u32, ?*const anyopaque) callconv(.c) i32;
    const Start = *const fn (AudioQueue, ?*const anyopaque) callconv(.c) i32;
    const Stop = *const fn (AudioQueue, u8) callconv(.c) i32;

    const framework = "/System/Library/Frameworks/AudioToolbox.framework/AudioToolbox";
    const linear_pcm: u32 = 0x6c70_636d; // 'lpcm'
    const signed_integer: u32 = 1 << 2;
    const packed_samples: u32 = 1 << 3;
    const buffer_bytes = buffer_frames * 4;

    var queue: ?AudioQueue = null;
    var buffers: [buffer_count]*Buffer = undefined;
    var enqueue: EnqueueBuffer = undefined;
    var start_queue: Start = undefined;
    var stop_queue: Stop = undefined;
    /// Set by the queue's thread when a buffer could not be queued again.
    var failed = std.atomic.Value(bool).init(false);

    /// Makes the queue on the default output device and its buffers; false when the
    /// framework or the device is not there. The queue calls `refill` from a thread of
    /// its own (no run loop is given).
    fn open() bool {
        var lib = std.DynLib.open(framework) catch return false;
        const new_output = lib.lookup(NewOutput, "AudioQueueNewOutput") orelse return false;
        const allocate = lib.lookup(AllocateBuffer, "AudioQueueAllocateBuffer") orelse return false;
        enqueue = lib.lookup(EnqueueBuffer, "AudioQueueEnqueueBuffer") orelse return false;
        start_queue = lib.lookup(Start, "AudioQueueStart") orelse return false;
        stop_queue = lib.lookup(Stop, "AudioQueueStop") orelse return false;
        const format: StreamDescription = .{
            .sample_rate = sample_rate,
            .format_id = linear_pcm,
            .format_flags = signed_integer | packed_samples,
            .bytes_per_packet = 4,
            .frames_per_packet = 1,
            .bytes_per_frame = 4,
            .channels_per_frame = 2,
            .bits_per_channel = 16,
        };
        if (new_output(&format, refill, null, null, null, 0, &queue) != 0) return false;
        for (&buffers) |*buffer| {
            var made: ?*Buffer = null;
            if (allocate(queue.?, buffer_bytes, &made) != 0) return false;
            buffer.* = made.?;
        }
        return true;
    }

    /// The queue is done with a buffer: it is filled with the next samples and queued
    /// again. The engine has one consumer at a time: the queue calls this from one
    /// thread, and the audio thread renders nothing while the queue plays.
    fn refill(_: ?*anyopaque, audio_queue: AudioQueue, buffer: *Buffer) callconv(.c) void {
        if (failed.load(.acquire)) return;
        fill(buffer);
        if (enqueue(audio_queue, buffer, 0, null) != 0) failed.store(true, .release);
    }

    fn fill(buffer: *Buffer) void {
        const samples: [*]i16 = @ptrCast(@alignCast(buffer.data));
        engine.render(samples[0 .. buffer_frames * 2]);
        buffer.size = buffer_bytes;
    }

    /// Queues the buffers, starts the queue, and waits until it fails; then stops it, so
    /// that the queue no longer renders when the audio thread goes on without sound.
    fn play() void {
        for (buffers) |buffer| {
            fill(buffer);
            if (enqueue(queue.?, buffer, 0, null) != 0) return;
        }
        if (start_queue(queue.?, null) != 0) return;
        while (!failed.load(.acquire)) sleepMilliseconds(100);
        _ = stop_queue(queue.?, 1);
    }
};
