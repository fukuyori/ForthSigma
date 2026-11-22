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
//! The thread is started by the first audio word and joined during shutdown. It
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

const Engine = sound_engine.Engine;
const fixture_enabled = builtin.is_test or (@hasDecl(@import("root"), "audio_lifecycle_fixture") and @import("root").audio_lifecycle_fixture);
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
var next_pcm_id: i64 = 1;
var state: enum { idle, running, failed } = .idle;
var device_open = std.atomic.Value(bool).init(false);
var stop_requested = std.atomic.Value(bool).init(false);
var thread_exited = std.atomic.Value(bool).init(false);
var cleanup_ok = std.atomic.Value(bool).init(true);
var terminal_cleanup_failure = false;
var windows_thread: ?std.Thread = null;
var posix_handle: ?usize = null;

const PosixThread = struct {
    extern "c" fn pthread_create(*usize, ?*const anyopaque, *const fn (?*anyopaque) callconv(.c) ?*anyopaque, ?*anyopaque) c_int;
    extern "c" fn pthread_join(usize, ?*?*anyopaque) c_int;
    fn entry(_: ?*anyopaque) callconv(.c) ?*anyopaque {
        var mask: std.c.sigset_t = undefined;
        var previous: std.c.sigset_t = undefined;
        if (std.c.sigfillset(&mask) != 0) {
            cleanup_ok.store(false, .release);
            _ = closeBackend();
            thread_exited.store(true, .release);
            return null;
        }
        for ([_]std.c.SIG{ .ILL, .TRAP, .ABRT, .BUS, .FPE, .SEGV, .SYS }) |signal| {
            if (std.c.sigdelset(&mask, signal) != 0) {
                cleanup_ok.store(false, .release);
                _ = closeBackend();
                thread_exited.store(true, .release);
                return null;
            }
        }
        if (std.c.pthread_sigmask(std.c.SIG.BLOCK, &mask, &previous) != 0) {
            cleanup_ok.store(false, .release);
            _ = closeBackend();
            thread_exited.store(true, .release);
            return null;
        }
        run();
        return null;
    }
};
const TestMode = enum { normal, silent, blocked, fail_thread, pipe_fixture, alsa_fixture, rollback_recovered };
var test_mode: TestMode = .normal;
var test_release = std.atomic.Value(bool).init(false);
var test_windows_fail: enum { none, event, header } = .none;
var test_header_index: usize = 0;
var test_windows_opened = false;
var test_pipe_eagain = std.atomic.Value(u32).init(0);
var test_clock_failed = false;
var test_cleanup_failed = false;
var test_cleanup_fail_once = false;
var test_player_kind: enum { eof, term, kill } = .kill;
var test_player_stage: u8 = 0;
var test_alsa_calls = std.atomic.Value(u32).init(0);
var test_alsa_closed = false;

/// All shared storage is host-owned and remains alive until shutdown succeeds.
pub fn start(_: ?*anyopaque) ?*Engine {
    switch (state) {
        .running => {
            if (thread_exited.load(.acquire)) {
                state = .failed;
                return null;
            }
            return &engine;
        },
        .failed => return null,
        .idle => {},
    }
    stop_requested.store(false, .release);
    thread_exited.store(false, .release);
    cleanup_ok.store(true, .release);
    terminal_cleanup_failure = false;
    engine = Engine.init(sample_rate);
    engine.pcm_session.next_id = next_pcm_id;
    engine.pcm_session.storage = std.heap.page_allocator.alloc(sound_engine.stream.Frame, 65536) catch &.{};
    engine.pool = std.heap.page_allocator.alloc(i16, sound_engine.pcm.pool_samples) catch &.{};
    if (!fixture_enabled or test_mode == .normal) {
        if (is_windows and windows.open()) device_open.store(true, .release);
        if (is_linux and linux.open()) device_open.store(true, .release);
        if (is_macos and macos.open()) device_open.store(true, .release);
    }
    if (fixture_enabled and is_linux and test_mode == .pipe_fixture) {
        const script: [*:0]const u8 = switch (test_player_kind) {
            .eof => "exec cat >/dev/null",
            .term => "exec sleep 60",
            .kill => "trap '' TERM; exec sleep 60",
        };
        const command = [_:null]?[*:0]const u8{ "/bin/sh", "-c", script };
        if (linux.spawn(&command)) {
            linux.backend = .pipe;
            device_open.store(true, .release);
        }
    }
    if (fixture_enabled and is_linux and test_mode == .alsa_fixture) {
        linux.backend = .alsa;
        linux.pcm = @ptrFromInt(16);
        linux.alsa_write = linux.testWrite;
        linux.alsa_wait = linux.testWait;
        linux.alsa_recover = linux.testRecover;
        linux.alsa_drop = linux.testEnd;
        linux.alsa_close = linux.testClose;
        device_open.store(true, .release);
    }
    if (fixture_enabled and test_mode == .rollback_recovered) cleanup_ok.store(false, .release);
    if (!cleanup_ok.load(.acquire) or !startThread()) {
        const closed = closeBackend();
        state = .failed;
        // A failed rollback retains every potentially referenced allocation.
        if (closed) {
            if (!terminal_cleanup_failure) cleanup_ok.store(true, .release);
            unloadLibraries();
            freeStorage();
        }
        return null;
    }
    state = .running;
    return &engine;
}

pub fn hasDevice(_: ?*anyopaque) bool {
    return device_open.load(.acquire);
}

/// False means shutdown is incomplete: do not restart or free shared memory.
/// Safe to retry after a late consumer exit. Does not touch VM/runtime storage.
pub fn shutdown(milliseconds: u32) bool {
    if (state == .idle) return true;
    stop_requested.store(true, .release);
    state = .failed;
    // Workers have finite waits (100 ms at most). No cross-thread device call:
    // even SetEvent would race the worker closing/reusing the native handle.
    if (windows_thread != null or posix_handle != null) {
        const deadline = @import("core/runtime_base.zig").Deadline.afterMilliseconds(shutdownNow() catch return false, milliseconds) catch return false;
        while (!thread_exited.load(.acquire)) {
            if (deadline.expired(shutdownNow() catch return false)) {
                state = .failed;
                return false;
            }
            sleepMilliseconds(1);
        }
        if (is_windows) {
            windows_thread.?.join();
            windows_thread = null;
        } else {
            if (PosixThread.pthread_join(posix_handle.?, null) != 0) {
                state = .failed;
                return false;
            }
            posix_handle = null;
        }
    }
    if (!cleanup_ok.load(.acquire)) {
        state = .failed;
        return false;
    }
    unloadLibraries();
    freeStorage();
    state = .idle;
    return true;
}

fn freeStorage() void {
    next_pcm_id = engine.pcm_session.next_id;
    std.heap.page_allocator.free(engine.pcm_session.storage);
    engine.pcm_session.storage = &.{};
    std.heap.page_allocator.free(engine.pool);
    engine.pool = &.{};
}

fn shutdownNow() @import("core/runtime_base.zig").Error!@import("core/runtime_base.zig").Instant {
    if (fixture_enabled and test_clock_failed) return error.HostFailed;
    return @import("host_clock.zig").now();
}

/// Called only after all ordinary application defers have run and output flushed.
/// A surviving library worker must not race libc/DLL finalizers during exit.
pub fn abortIncomplete() noreturn {
    if (is_windows) {
        const native = struct {
            extern "kernel32" fn GetCurrentProcess() callconv(.winapi) *anyopaque;
            extern "kernel32" fn TerminateProcess(*anyopaque, u32) callconv(.winapi) c_int;
        };
        _ = native.TerminateProcess(native.GetCurrentProcess(), 1);
        unreachable;
    } else {
        const native = struct {
            extern "c" fn _exit(c_int) noreturn;
        };
        native._exit(1);
    }
}

fn unloadLibraries() void {
    if (is_linux) linux.unload();
    if (is_macos) macos.unload();
}

fn startThread() bool {
    if (fixture_enabled and test_mode == .fail_thread) return false;
    if (is_windows) {
        windows_thread = std.Thread.spawn(.{ .stack_size = 256 * 1024 }, run, .{}) catch return false;
    } else {
        var handle: usize = 0;
        if (PosixThread.pthread_create(&handle, null, PosixThread.entry, null) != 0) return false;
        posix_handle = handle;
    }
    return true;
}

fn closeBackend() bool {
    if (fixture_enabled and test_cleanup_fail_once) {
        test_cleanup_fail_once = false;
        cleanup_ok.store(false, .release);
        return false;
    }
    if (fixture_enabled and test_cleanup_failed) {
        cleanup_ok.store(false, .release);
        return false;
    }
    const success = if (is_windows) windows.release() else if (is_linux) linux.release() else if (is_macos) macos.release() else true;
    device_open.store(false, .release);
    if (!success) cleanup_ok.store(false, .release);
    return success;
}

fn run() void {
    defer thread_exited.store(true, .release);
    defer {
        if (closeBackend() and !terminal_cleanup_failure) cleanup_ok.store(true, .release);
    }
    if (fixture_enabled and test_mode == .blocked) {
        while (!test_release.load(.acquire)) sleepMilliseconds(1);
        return;
    }
    if (device_open.load(.acquire)) {
        if (is_windows) windows.play();
        if (is_linux) linux.play();
        if (is_macos) macos.play();
        // Stop callbacks and release the failed device BEFORE silent rendering.
        if (!closeBackend()) return;
    }
    if (!stop_requested.load(.acquire)) playSilently();
}

fn playSilently() void {
    var buffer: [buffer_frames * 2]i16 = undefined;
    const begin = monotonicNanoseconds();
    var frames: u64 = 0;
    while (!stop_requested.load(.acquire)) {
        sleepMilliseconds(5);
        const elapsed = monotonicNanoseconds() -% begin;
        const due = elapsed / std.time.ns_per_s * sample_rate + elapsed % std.time.ns_per_s * sample_rate / std.time.ns_per_s;
        while (frames < due and !stop_requested.load(.acquire)) {
            const count: usize = @intCast(@min(due - frames, buffer_frames));
            engine.render(buffer[0 .. count * 2]);
            frames += count;
        }
    }
}

// ---- PLAY's wait ----

/// Waits a few milliseconds with Ctrl+C caught.
pub fn wait() forth.AudioWait {
    if (thread_exited.load(.acquire)) return .host_failed;
    return @import("host_wait.zig").audioWait(null);
}
pub fn waitWithRuntime(runtime: *@import("host_runtime.zig").Runtime) forth.AudioWait {
    if (thread_exited.load(.acquire)) return .host_failed;
    return @import("host_wait.zig").audioWait(runtime);
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
    extern "kernel32" fn CloseHandle(HANDLE) callconv(.winapi) c_int;
    extern "winmm" fn waveOutReset(HANDLE) callconv(.winapi) u32;
    extern "winmm" fn waveOutUnprepareHeader(HANDLE, *WaveHeader, u32) callconv(.winapi) u32;
    extern "winmm" fn waveOutClose(HANDLE) callconv(.winapi) u32;
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
    var prepared: usize = 0;

    /// Opens the default device; false when there is none.
    fn open() bool {
        var success = false;
        defer if (!success) {
            if (!release()) cleanup_ok.store(false, .release);
        };
        event = CreateEventW(null, 0, 0, null) orelse return false;
        if (fixture_enabled and test_windows_fail == .event) return false;
        const format: WaveFormat = .{
            .format_tag = 1, // PCM
            .channels = 2,
            .samples_per_second = sample_rate,
            .bytes_per_second = sample_rate * 4,
            .block_align = 4,
            .bits_per_sample = 16,
            .extra_size = 0,
        };
        var made: ?HANDLE = null;
        if (waveOutOpen(&made, wave_mapper, &format, @intFromPtr(event.?), 0, callback_event) != 0) return false;
        device = made;
        if (fixture_enabled) test_windows_opened = true;
        for (&headers, &samples) |*header, *buffer| {
            if (fixture_enabled and test_windows_fail == .header and prepared == test_header_index) return false;
            header.* = .{ .data = @ptrCast(buffer), .buffer_length = @sizeOf(@TypeOf(buffer.*)) };
            if (waveOutPrepareHeader(device.?, header, @sizeOf(WaveHeader)) != 0) return false;
            prepared += 1;
        }
        success = true;
        return true;
    }

    fn release() bool {
        if (device) |handle| {
            if (waveOutReset(handle) != 0) return false;
            while (prepared > 0) {
                if (waveOutUnprepareHeader(handle, &headers[prepared - 1], @sizeOf(WaveHeader)) != 0) return false;
                prepared -= 1;
            }
            if (waveOutClose(handle) != 0) return false;
            device = null;
        }
        if (event) |handle| {
            if (CloseHandle(handle) == 0) return false;
            event = null;
        }
        return true;
    }

    /// Fills each buffer the device has finished with, in turn, until a write fails.
    fn play() void {
        _ = SetThreadPriority(GetCurrentThread(), thread_priority_time_critical);
        for (&headers, &samples) |*header, *buffer| {
            if (stop_requested.load(.acquire)) return;
            engine.render(buffer);
            if (waveOutWrite(device.?, header, @sizeOf(WaveHeader)) != 0) return;
        }
        var next: usize = 0;
        while (!stop_requested.load(.acquire)) {
            _ = WaitForSingleObject(event.?, 100);
            // The device sets the flag from its own thread.
            while (!stop_requested.load(.acquire) and @atomicLoad(u32, &headers[next].flags, .acquire) & header_done != 0) {
                engine.render(&samples[next]);
                if (waveOutWrite(device.?, &headers[next], @sizeOf(WaveHeader)) != 0) return;
                next = (next + 1) % buffer_count;
            }
        }
    }
};

// ---- Linux: PulseAudio, ALSA, or a command through a pipe ----

const linux = struct {
    extern "c" fn pipe2(*[2]c_int, c_int) c_int;
    extern "c" fn close(c_int) c_int;
    extern "c" fn write(c_int, [*]const u8, usize) isize;
    extern "c" fn fcntl(c_int, c_int, ...) c_int;
    extern "c" fn kill(c_int, c_int) c_int;
    extern "c" fn poll([*]PollFd, usize, c_int) c_int;
    const PollFd = extern struct { fd: c_int, events: c_short, revents: c_short = 0 };
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
    extern "c" var environ: [*:null]const ?[*:0]const u8;

    const f_getfl = 3;
    const f_setfl = 4;
    const o_nonblock = 2048;
    const eagain = 11;
    const f_setfd = 2;
    const fd_cloexec = 1;
    const f_setpipe_sz = 1031;
    const o_wronly = 1;
    const posix_spawn_setpgroup = 2;
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
    const PulseFree = *const fn (*anyopaque) callconv(.c) void;
    var pulse_free: PulseFree = undefined;
    var pulse_lib: ?std.DynLib = null;

    // ALSA.
    const AlsaOpen = *const fn (*?*anyopaque, [*:0]const u8, c_int, c_int) callconv(.c) c_int;
    const AlsaSetParams = *const fn (*anyopaque, c_int, c_int, c_uint, c_uint, c_int, c_uint) callconv(.c) c_int;
    const AlsaWrite = *const fn (*anyopaque, [*]const u8, c_ulong) callconv(.c) c_long;
    const AlsaRecover = *const fn (*anyopaque, c_int, c_int) callconv(.c) c_int;
    var pcm: ?*anyopaque = null;
    var alsa_write: AlsaWrite = undefined;
    var alsa_recover: AlsaRecover = undefined;
    const AlsaMode = *const fn (*anyopaque, c_int) callconv(.c) c_int;
    const AlsaEnd = *const fn (*anyopaque) callconv(.c) c_int;
    const AlsaWait = *const fn (*anyopaque, c_int) callconv(.c) c_int;
    var alsa_drop: AlsaEnd = undefined;
    var alsa_close: AlsaEnd = undefined;
    var alsa_wait: AlsaWait = undefined;
    var alsa_lib: ?std.DynLib = null;

    // The command's pipe.
    var pipe_fd: c_int = -1;
    var pipe_pid: c_int = 0;

    fn open() bool {
        if (can_load) {
            if (openPulse()) {
                backend = .pulse;
                return true;
            }
            if (!cleanup_ok.load(.acquire)) return false;
            if (openAlsa()) {
                backend = .alsa;
                return true;
            }
        }
        if (!cleanup_ok.load(.acquire)) return false;
        if (openPipe()) {
            backend = .pipe;
            return true;
        }
        return false;
    }

    /// PulseAudio (and PipeWire's PulseAudio server), about 40 ms ahead.
    fn openPulse() bool {
        var lib = std.DynLib.open("libpulse-simple.so.0") catch return false;
        var success = false;
        defer if (!success) lib.close();
        const new = lib.lookup(PulseNew, "pa_simple_new") orelse return false;
        pulse_write = lib.lookup(PulseWrite, "pa_simple_write") orelse return false;
        pulse_free = lib.lookup(PulseFree, "pa_simple_free") orelse return false;
        const spec: SampleSpec = .{ .format = 3, .rate = sample_rate, .channels = 2 };
        const none = std.math.maxInt(u32);
        const attr: BufferAttr = .{ .maxlength = none, .tlength = sample_rate * 4 * 40 / 1000, .prebuf = none, .minreq = none, .fragsize = none };
        pulse = new(null, "FORTH/Sigma", 1, null, "sound", &spec, null, &attr, null) orelse return false;
        pulse_lib = lib;
        success = true;
        return true;
    }

    fn openAlsa() bool {
        var lib = std.DynLib.open("libasound.so.2") catch return false;
        var owned = false;
        defer if (!owned) lib.close();
        const pcm_open = lib.lookup(AlsaOpen, "snd_pcm_open") orelse return false;
        const set_params = lib.lookup(AlsaSetParams, "snd_pcm_set_params") orelse return false;
        const nonblock = lib.lookup(AlsaMode, "snd_pcm_nonblock") orelse return false;
        alsa_write = lib.lookup(AlsaWrite, "snd_pcm_writei") orelse return false;
        alsa_recover = lib.lookup(AlsaRecover, "snd_pcm_recover") orelse return false;
        alsa_drop = lib.lookup(AlsaEnd, "snd_pcm_drop") orelse return false;
        alsa_close = lib.lookup(AlsaEnd, "snd_pcm_close") orelse return false;
        alsa_wait = lib.lookup(AlsaWait, "snd_pcm_wait") orelse return false;
        var made: ?*anyopaque = null;
        if (pcm_open(&made, "default", 0, 1) < 0) return false;
        pcm = made;
        alsa_lib = lib;
        owned = true;
        if (set_params(pcm.?, 2, 3, 2, sample_rate, 1, 50_000) < 0 or nonblock(pcm.?, 1) < 0) {
            if (!release()) cleanup_ok.store(false, .release);
            return false;
        }
        return true;
    }

    // Called only by the backend owner, or before a worker has been started.
    fn release() bool {
        if (pulse) |handle| {
            pulse_free(handle);
            pulse = null;
        }
        if (pcm) |handle| {
            _ = alsa_drop(handle);
            // snd_pcm_close consumes the handle even when it reports an error.
            const result = alsa_close(handle);
            pcm = null;
            if (result < 0) {
                terminal_cleanup_failure = true;
                return false;
            }
        }
        if (pipe_fd >= 0) {
            _ = close(pipe_fd);
            pipe_fd = -1;
        }
        if (pipe_pid > 0) {
            // First allow EOF to stop the owned player. Signals target its group.
            if (!reapFor(100)) {
                if (fixture_enabled) test_player_stage = 1;
                _ = kill(-pipe_pid, 15);
                if (!reapFor(100)) {
                    if (fixture_enabled) test_player_stage = 2;
                    _ = kill(-pipe_pid, 9);
                    if (!reapFor(100)) return false;
                }
            }
        }
        backend = .none;
        return true;
    }
    fn testWrite(_: *anyopaque, _: [*]const u8, frames: c_ulong) callconv(.c) c_long {
        const call = test_alsa_calls.raw;
        test_alsa_calls.store(call + 1, .release);
        return switch (call % 4) {
            0 => -eagain,
            1 => 0,
            2 => @intCast(@min(frames, 17)),
            else => -32,
        };
    }
    fn testWait(_: *anyopaque, _: c_int) callconv(.c) c_int {
        sleepMilliseconds(1);
        return 0;
    }
    fn testRecover(_: *anyopaque, _: c_int, _: c_int) callconv(.c) c_int {
        return 0;
    }
    fn testEnd(_: *anyopaque) callconv(.c) c_int {
        return 0;
    }
    fn testClose(_: *anyopaque) callconv(.c) c_int {
        test_alsa_closed = true;
        return 0;
    }
    fn unload() void {
        if (pulse_lib) |*lib| {
            lib.close();
            pulse_lib = null;
        }
        if (alsa_lib) |*lib| {
            lib.close();
            alsa_lib = null;
        }
    }
    fn reapFor(milliseconds: u32) bool {
        var elapsed: u32 = 0;
        while (true) {
            const result = waitpid(pipe_pid, null, wnohang);
            if (result == pipe_pid or (result < 0 and std.c._errno().* == 10)) {
                pipe_pid = 0;
                return true;
            }
            if (result < 0 and std.c._errno().* != eintr) return false;
            if (elapsed >= milliseconds) return false;
            sleepMilliseconds(1);
            elapsed += 1;
        }
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
        if (pipe2(&fds, 0x80000) != 0) return false; // O_CLOEXEC at creation
        for (&fds) |*fd| {
            if (fd.* <= 2) {
                const moved = fcntl(fd.*, @as(c_int, 1030), @as(c_int, 3)); // F_DUPFD_CLOEXEC
                _ = close(fd.*);
                fd.* = moved;
                if (moved < 0) {
                    for (fds) |item| {
                        if (item >= 0) _ = close(item);
                    }
                    return false;
                }
            }
        }
        defer _ = close(fds[0]);
        var keep_writer = false;
        defer if (!keep_writer) {
            _ = close(fds[1]);
        };
        // Both ends become CLOEXEC before spawning; dup2 creates the child's stdin.
        if (fcntl(fds[0], f_setfd, @as(c_int, fd_cloexec)) < 0 or fcntl(fds[1], f_setfd, @as(c_int, fd_cloexec)) < 0) return false;
        const flags = fcntl(fds[1], f_getfl);
        if (flags < 0 or fcntl(fds[1], f_setfl, flags | @as(c_int, o_nonblock)) < 0) return false;
        var actions: [256]u8 align(16) = undefined;
        var attr: [512]u8 align(16) = undefined;
        if (posix_spawn_file_actions_init(&actions) != 0) return false;
        defer _ = posix_spawn_file_actions_destroy(&actions);
        if (posix_spawn_file_actions_adddup2(&actions, fds[0], 0) != 0 or
            posix_spawn_file_actions_addclose(&actions, fds[0]) != 0 or
            posix_spawn_file_actions_addclose(&actions, fds[1]) != 0 or
            posix_spawn_file_actions_addopen(&actions, 1, "/dev/null", o_wronly, 0) != 0 or
            posix_spawn_file_actions_addopen(&actions, 2, "/dev/null", o_wronly, 0) != 0) return false;
        if (posix_spawnattr_init(&attr) != 0) return false;
        defer _ = posix_spawnattr_destroy(&attr);
        if (posix_spawnattr_setflags(&attr, posix_spawn_setpgroup) != 0 or posix_spawnattr_setpgroup(&attr, 0) != 0) return false;
        var pid: c_int = 0;
        if (posix_spawnp(&pid, argv[0].?, &actions, &attr, argv, environ) != 0) return false;
        pipe_pid = pid;
        pipe_fd = fds[1];
        keep_writer = true;
        _ = fcntl(pipe_fd, f_setpipe_sz, @as(c_int, 8192));
        sleepMilliseconds(100);
        const result = waitpid(pid, null, wnohang);
        if (result == pid) {
            pipe_pid = 0;
            _ = close(pipe_fd);
            pipe_fd = -1;
            return false;
        }
        if (result < 0) {
            if (!release()) cleanup_ok.store(false, .release);
            return false;
        }
        return true;
    }

    /// Sends the samples until the device fails.
    fn play() void {
        // PosixThread.entry already blocks SIGPIPE and other async signals.
        var buffer: [buffer_frames * 2]i16 = undefined;
        while (!stop_requested.load(.acquire)) {
            engine.render(&buffer);
            const bytes = std.mem.sliceAsBytes(&buffer);
            switch (backend) {
                .pulse => if (pulse_write(pulse.?, bytes.ptr, bytes.len, null) < 0) return,
                .alsa => {
                    var done: usize = 0;
                    while (done < buffer_frames and !stop_requested.load(.acquire)) {
                        const written = alsa_write(pcm.?, bytes[done * 4 ..].ptr, buffer_frames - done);
                        if (written == 0 or written == -eagain or written == -eintr) {
                            _ = alsa_wait(pcm.?, 20);
                            continue;
                        }
                        if (written < 0) {
                            if (alsa_recover(pcm.?, @intCast(written), 1) < 0) return;
                            continue;
                        }
                        done += @intCast(written);
                    }
                },
                .pipe => {
                    var done: usize = 0;
                    while (done < bytes.len and !stop_requested.load(.acquire)) {
                        const written = write(pipe_fd, bytes[done..].ptr, bytes.len - done);
                        if (written < 0) {
                            if (std.c._errno().* == eintr) continue;
                            if (std.c._errno().* == eagain) {
                                if (fixture_enabled) test_pipe_eagain.store(test_pipe_eagain.raw + 1, .release);
                                var ready: [1]PollFd = .{.{ .fd = pipe_fd, .events = 4 }};
                                _ = poll(&ready, 1, 20);
                                continue;
                            }
                            return;
                        }
                        if (written == 0) return;
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
    const Dispose = *const fn (AudioQueue, u8) callconv(.c) i32;

    const framework = "/System/Library/Frameworks/AudioToolbox.framework/AudioToolbox";
    const core_audio_framework = "/System/Library/Frameworks/CoreAudio.framework/CoreAudio";
    const linear_pcm: u32 = 0x6c70_636d; // 'lpcm'
    const signed_integer: u32 = 1 << 2;
    const packed_samples: u32 = 1 << 3;
    const buffer_bytes = buffer_frames * 4;

    var queue: ?AudioQueue = null;
    var buffers: [buffer_count]*Buffer = undefined;
    var enqueue: EnqueueBuffer = undefined;
    var start_queue: Start = undefined;
    var stop_queue: Stop = undefined;
    var dispose_queue: Dispose = undefined;
    var framework_lib: ?std.DynLib = null;
    /// Set by the queue's thread when a buffer could not be queued again.
    var failed = std.atomic.Value(bool).init(false);

    const PropertyAddress = extern struct {
        selector: u32,
        scope: u32,
        element: u32,
    };
    const GetPropertyData = *const fn (u32, *const PropertyAddress, u32, ?*const anyopaque, *u32, *anyopaque) callconv(.c) i32;

    /// AudioQueueNewOutput can succeed with the default-device sentinel even when
    /// CoreAudio has no output device. Check the hardware route before claiming audio
    /// reaches a device.
    fn hasDefaultOutputDevice() bool {
        var lib = std.DynLib.open(core_audio_framework) catch return false;
        defer lib.close();
        const get_property = lib.lookup(GetPropertyData, "AudioObjectGetPropertyData") orelse return false;
        const address = PropertyAddress{
            .selector = (@as(u32, 'd') << 24) | (@as(u32, 'O') << 16) | (@as(u32, 'u') << 8) | 't', // kAudioHardwarePropertyDefaultOutputDevice
            .scope = (@as(u32, 'g') << 24) | (@as(u32, 'l') << 16) | (@as(u32, 'o') << 8) | 'b', // kAudioObjectPropertyScopeGlobal
            .element = 0, // kAudioObjectPropertyElementMain
        };
        var device: u32 = 0;
        var size: u32 = @sizeOf(u32);
        if (get_property(1, &address, 0, null, &size, &device) != 0) return false; // system object
        return size == @sizeOf(u32) and device != 0;
    }

    /// Makes the queue on the default output device and its buffers; false when the
    /// framework or the device is not there. The queue calls `refill` from a thread of
    /// its own (no run loop is given).
    fn open() bool {
        if (!hasDefaultOutputDevice()) return false;
        var lib = std.DynLib.open(framework) catch return false;
        var owned = false;
        defer if (!owned) lib.close();
        const new_output = lib.lookup(NewOutput, "AudioQueueNewOutput") orelse return false;
        const allocate = lib.lookup(AllocateBuffer, "AudioQueueAllocateBuffer") orelse return false;
        enqueue = lib.lookup(EnqueueBuffer, "AudioQueueEnqueueBuffer") orelse return false;
        start_queue = lib.lookup(Start, "AudioQueueStart") orelse return false;
        stop_queue = lib.lookup(Stop, "AudioQueueStop") orelse return false;
        dispose_queue = lib.lookup(Dispose, "AudioQueueDispose") orelse return false;
        failed.store(false, .release);
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
        var made_queue: ?AudioQueue = null;
        if (new_output(&format, refill, null, null, null, 0, &made_queue) != 0) return false;
        queue = made_queue;
        framework_lib = lib;
        owned = true;
        var success = false;
        defer if (!success) {
            if (!release()) cleanup_ok.store(false, .release);
        };
        for (&buffers) |*buffer| {
            var made: ?*Buffer = null;
            if (allocate(queue.?, buffer_bytes, &made) != 0) return false;
            buffer.* = made.?;
        }
        success = true;
        return true;
    }

    /// The queue is done with a buffer: it is filled with the next samples and queued
    /// again. The engine has one consumer at a time: the queue calls this from one
    /// thread, and the audio thread renders nothing while the queue plays.
    fn refill(_: ?*anyopaque, audio_queue: AudioQueue, buffer: *Buffer) callconv(.c) void {
        if (stop_requested.load(.acquire) or failed.load(.acquire)) return;
        fill(buffer);
        if (stop_requested.load(.acquire)) return;
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
            if (stop_requested.load(.acquire)) return;
            fill(buffer);
            if (enqueue(queue.?, buffer, 0, null) != 0) return;
        }
        if (start_queue(queue.?, null) != 0) return;
        while (!stop_requested.load(.acquire) and !failed.load(.acquire)) sleepMilliseconds(10);
    }
    fn release() bool {
        if (queue) |handle| {
            // Dispose synchronously is the lifetime barrier, even if Stop fails.
            _ = stop_queue(handle, 1);
            if (dispose_queue(handle, 1) != 0) return false;
            queue = null;
        }
        return true;
    }
    fn unload() void {
        if (framework_lib) |*lib| {
            lib.close();
            framework_lib = null;
        }
    }
};

test "audio lifecycle stops and joins silent consumers repeatedly" {
    if (!is_windows and !is_linux and !is_macos) return error.SkipZigTest;
    test_mode = .silent;
    defer test_mode = .normal;
    for (0..20) |_| {
        try std.testing.expect(start(null) != null);
        try std.testing.expect(shutdown(1000));
        try std.testing.expectEqual(@as(usize, 0), engine.pool.len);
        try std.testing.expect(windows_thread == null and posix_handle == null);
    }
}

test "audio lifecycle timeout retains blocked consumer storage and allows late join" {
    if (!is_windows and !is_linux and !is_macos) return error.SkipZigTest;
    test_mode = .blocked;
    test_release.store(false, .release);
    defer {
        test_release.store(true, .release);
        _ = shutdown(1000);
        test_mode = .normal;
    }
    const running = start(null) orelse return error.TestUnexpectedResult;
    const pointer = running.pool.ptr;
    try std.testing.expect(!shutdown(5));
    try std.testing.expect(start(null) == null);
    try std.testing.expect(running.pool.ptr == pointer and running.pool.len != 0);
    test_release.store(true, .release);
    try std.testing.expect(shutdown(1000));
}

test "audio lifecycle failed thread creation rolls back host storage" {
    test_mode = .fail_thread;
    defer test_mode = .normal;
    try std.testing.expect(start(null) == null);
    try std.testing.expectEqual(@as(usize, 0), engine.pool.len);
    try std.testing.expect(shutdown(1000));
}

fn testResourceCount() !usize {
    if (is_windows) {
        const native = struct {
            extern "kernel32" fn GetCurrentProcess() callconv(.winapi) windows.HANDLE;
            extern "kernel32" fn GetProcessHandleCount(windows.HANDLE, *u32) callconv(.winapi) c_int;
        };
        var count: u32 = 0;
        if (native.GetProcessHandleCount(native.GetCurrentProcess(), &count) == 0) return error.TestUnexpectedResult;
        return count;
    }
    const native = struct {
        extern "c" fn opendir([*:0]const u8) ?*anyopaque;
        extern "c" fn readdir(*anyopaque) ?*anyopaque;
        extern "c" fn closedir(*anyopaque) c_int;
    };
    const dir = native.opendir(if (is_linux) "/proc/self/fd" else "/dev/fd") orelse return error.SkipZigTest;
    defer _ = native.closedir(dir);
    var count: usize = 0;
    while (native.readdir(dir) != null) count += 1;
    return count;
}

test "audio repeated silent join leaves native handles or fds unchanged" {
    test_mode = .silent;
    defer test_mode = .normal;
    _ = start(null) orelse return error.TestUnexpectedResult;
    try std.testing.expect(shutdown(1000));
    const before = try testResourceCount();
    for (0..20) |_| {
        _ = start(null) orelse return error.TestUnexpectedResult;
        try std.testing.expect(shutdown(1000));
    }
    try std.testing.expectEqual(before, try testResourceCount());
}

test "Windows audio partial open rolls back event and prepared headers" {
    if (!is_windows) return error.SkipZigTest;
    test_mode = .normal;
    defer {
        test_windows_fail = .none;
        test_mode = .normal;
    }
    // First device open loads Windows' shared driver infrastructure. Compare
    // repeated owned-resource lifetimes only after that one-time setup.
    _ = start(null) orelse return error.TestUnexpectedResult;
    try std.testing.expect(shutdown(1000));
    const before = try testResourceCount();
    test_windows_fail = .event;
    for (0..20) |_| {
        _ = start(null) orelse return error.TestUnexpectedResult;
        try std.testing.expect(!hasDevice(null));
        try std.testing.expect(shutdown(1000));
    }
    try std.testing.expectEqual(before, try testResourceCount());
    test_windows_fail = .header;
    test_windows_opened = false;
    for (0..buffer_count) |index| {
        test_header_index = index;
        _ = start(null) orelse return error.TestUnexpectedResult;
        try std.testing.expect(!hasDevice(null));
        try std.testing.expect(shutdown(1000));
    }
    try std.testing.expectEqual(before, try testResourceCount());
    if (!test_windows_opened) return error.SkipZigTest;
}

test "Windows real audio device repeated shutdown releases buffers and handles" {
    if (!is_windows) return error.SkipZigTest;
    test_mode = .normal;
    defer test_mode = .normal;
    _ = start(null) orelse return error.TestUnexpectedResult;
    const available = hasDevice(null);
    try std.testing.expect(shutdown(1000));
    if (!available) return error.SkipZigTest;
    const before = try testResourceCount();
    for (0..20) |_| {
        _ = start(null) orelse return error.TestUnexpectedResult;
        try std.testing.expect(shutdown(1000));
    }
    try std.testing.expectEqual(before, try testResourceCount());
}

test "Linux stalled private audio player pipe stops and reaps its process group" {
    if (!is_linux) return error.SkipZigTest;
    test_mode = .pipe_fixture;
    defer test_mode = .normal;
    const before = try testResourceCount();
    test_pipe_eagain.store(0, .release);
    for ([_]@TypeOf(test_player_kind){ .eof, .term, .kill }) |kind| {
        test_player_kind = kind;
        test_player_stage = 0;
        _ = start(null) orelse return error.TestUnexpectedResult;
        try std.testing.expect(hasDevice(null));
        const child = linux.pipe_pid;
        sleepMilliseconds(60);
        try std.testing.expect(shutdown(1000));
        try std.testing.expect(linux.pipe_fd == -1 and linux.pipe_pid == 0);
        try std.testing.expectEqual(@as(c_int, -1), linux.waitpid(child, null, linux.wnohang));
        try std.testing.expectEqual(@as(c_int, 10), std.c._errno().*);
        try std.testing.expectEqual(@as(u8, switch (kind) {
            .eof => 0,
            .term => 1,
            .kill => 2,
        }), test_player_stage);
    }
    try std.testing.expect(test_pipe_eagain.load(.acquire) > 0);
    try std.testing.expectEqual(before, try testResourceCount());
}

test "audio clock failure prevents restart and retains storage until retry" {
    test_mode = .silent;
    defer {
        test_clock_failed = false;
        _ = shutdown(1000);
        test_mode = .normal;
    }
    _ = start(null) orelse return error.TestUnexpectedResult;
    test_clock_failed = true;
    try std.testing.expect(!shutdown(1000));
    try std.testing.expect(start(null) == null);
    try std.testing.expect(engine.pool.len != 0);
    test_clock_failed = false;
    try std.testing.expect(shutdown(1000));
}

test "audio failed backend cleanup retains storage after joining" {
    test_mode = .silent;
    defer {
        test_cleanup_failed = false;
        cleanup_ok.store(true, .release);
        _ = shutdown(1000);
        test_mode = .normal;
    }
    _ = start(null) orelse return error.TestUnexpectedResult;
    test_cleanup_failed = true;
    try std.testing.expect(!shutdown(1000));
    try std.testing.expect(windows_thread == null and posix_handle == null);
    try std.testing.expect(engine.pool.len != 0);
    try std.testing.expect(start(null) == null);
}

/// Only the separately built lifecycle fixture exposes its blocked-consumer hook.
pub const testing = if (fixture_enabled) struct {
    pub fn holdConsumer() void {
        test_mode = .blocked;
        test_release.store(false, .release);
    }
    pub fn retained() bool {
        return engine.pool.len != 0 and engine.pcm_session.storage.len != 0;
    }
} else struct {};

test "Linux ALSA partial and unready retries stop and close on the owner" {
    if (!is_linux) return error.SkipZigTest;
    test_mode = .alsa_fixture;
    defer test_mode = .normal;
    test_alsa_calls.store(0, .release);
    test_alsa_closed = false;
    _ = start(null) orelse return error.TestUnexpectedResult;
    sleepMilliseconds(30);
    try std.testing.expect(shutdown(1000));
    try std.testing.expect(test_alsa_closed);
    try std.testing.expect(test_alsa_calls.load(.acquire) >= 4);
    try std.testing.expect(linux.pcm == null);
}

test "audio recovered pre-thread rollback completes shutdown without retaining storage" {
    test_mode = .rollback_recovered;
    defer test_mode = .normal;
    try std.testing.expect(start(null) == null);
    try std.testing.expect(start(null) == null);
    try std.testing.expectEqual(@as(usize, 0), engine.pool.len);
    try std.testing.expect(shutdown(1000));
}

test "Linux transient worker cleanup failure recovers before join" {
    if (!is_linux) return error.SkipZigTest;
    test_mode = .alsa_fixture;
    defer {
        test_cleanup_fail_once = false;
        _ = shutdown(1000);
        test_mode = .normal;
    }
    test_alsa_closed = false;
    test_cleanup_fail_once = true;
    _ = start(null) orelse return error.TestUnexpectedResult;
    try std.testing.expect(shutdown(1000));
    try std.testing.expect(test_alsa_closed);
    try std.testing.expectEqual(@as(usize, 0), engine.pool.len);
}

test "PCM identity survives host restart and frame storage follows successful join" {
    test_mode = .silent;
    defer {
        _ = shutdown(1000);
        test_mode = .normal;
    }
    const first = start(null) orelse return error.TestUnexpectedResult;
    const first_id = (try first.pcm_session.open(&first.pcm_control, 42, 48000, 2, 4096, sample_rate)).id;
    try std.testing.expect(first_id > 0 and first.pcm_session.storage.len == 65536);
    try std.testing.expect(shutdown(1000));
    try std.testing.expectEqual(@as(usize, 0), engine.pcm_session.storage.len);
    const second = start(null) orelse return error.TestUnexpectedResult;
    const second_id = (try second.pcm_session.open(&second.pcm_control, 42, 48000, 2, 4096, sample_rate)).id;
    try std.testing.expect(second_id > first_id);
    try std.testing.expect(shutdown(1000));
}
