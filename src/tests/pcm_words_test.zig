const std = @import("std");
const forth = @import("../forth.zig");
const support = @import("support.zig");
const stream = @import("../core/sound_stream.zig");
const engine_module = @import("../core/sound_engine.zig");
const psg = @import("../core/sound_psg.zig");
const ops_type = @import("../core/host_interface.zig").ExecutionOps;
const Fake = struct {
    output: support.Output = .{},
    now_ns: i128 = 0,
    depth: usize = 0,
    begins: usize = 0,
    ends: usize = 0,
    end_interrupt: bool = false,
    end_failure: bool = false,
    fn of(context: ?*anyopaque) *Fake {
        const output: *support.Output = @ptrCast(@alignCast(context.?));
        return @fieldParentPtr("output", output);
    }
    fn now(context: ?*anyopaque) @import("../core/runtime_base.zig").Error!i128 {
        return of(context).now_ns;
    }
    fn begin(context: ?*anyopaque, _: *forth.State) forth.RuntimeError!void {
        const f = of(context);
        f.depth += 1;
        f.begins += 1;
    }
    fn end(context: ?*anyopaque, _: *forth.State) forth.RuntimeError!void {
        const f = of(context);
        f.depth -= 1;
        f.ends += 1;
        if (f.end_failure) return error.HostFailed;
        if (f.end_interrupt) {
            f.end_interrupt = false;
            return error.UserInterrupt;
        }
    }
    fn poll(_: ?*anyopaque, _: *forth.State) forth.RuntimeError!void {}
    fn wait(context: ?*anyopaque) forth.AudioWait {
        of(context).now_ns += 3_000_000;
        return support.Output.audioWait(context);
    }
    const ops = ops_type{ .begin = begin, .poll = poll, .end = end };
    fn bind(self: *Fake, machine: *forth.State, engine: *engine_module.Engine, storage: []stream.Frame) void {
        self.output.audio = engine;
        engine.pcm_session.storage = storage;
        machine.writer.audio_scope_ops = &ops;
        machine.writer.audio_wait_fn = wait;
        machine.writer.standard_clock = .{ .context = &self.output, .now_fn = now };
    }
};
fn newEngine() engine_module.Engine {
    return engine_module.Engine.init(.ay8910, psg.msx_clock, 48000);
}
fn setup(machine: *forth.State) !void {
    try machine.interpretLine("REQUIRE-AUDIO ALSO AUDIO");
}
fn open(machine: *forth.State) !forth.Cell {
    try machine.interpretLine("48000 2 4096 PCM-OPEN");
    try std.testing.expectEqual(@as(forth.Cell, 0), try machine.pop());
    return try machine.pop();
}
fn call(machine: *forth.State, word: []const u8, arguments: []const forth.Cell) !void {
    machine.data_depth = 0;
    for (arguments) |arg| try machine.push(arg);
    try machine.interpretLine(word);
}

test "PCM public open copied frames partial full queries stop and stale close" {
    try support.skipWithout(&.{.audio});
    var f = Fake{};
    var engine = newEngine();
    var frames: [4096]stream.Frame = undefined;
    const m = try support.createMachine(&f.output);
    defer support.destroyMachine(m);
    f.bind(m, &engine, &frames);
    try setup(m);
    const id = try open(m);
    try std.testing.expectEqual(id, m.audio_pcm_handle);
    const at = m.data_here;
    try m.reserveData(4096 * 4);
    @memset(m.memory[@intCast(at)..][0 .. 4096 * 4], 0x12);
    try call(m, "PCM-WRITE", &.{ at, 4096, id });
    try support.expectStack(m, &.{ 4096, 0 });
    try call(m, "PCM-WRITE", &.{ at, 1, id });
    try support.expectStack(m, &.{ 0, 0 });
    try call(m, "PCM-QUEUED", &.{id});
    try support.expectStack(m, &.{ 4096, 0 });
    try call(m, "PCM-WAIT", &.{ 1, 0, id });
    try support.expectStack(m, &.{ 0, 0 });
    try call(m, "PCM-WAIT", &.{ 1, 100, id });
    try support.expectStack(m, &.{ -1, 0 });
    try call(m, "PCM-STOP", &.{ 1, 100, id });
    try support.expectStack(m, &.{ -1, 0 });
    try call(m, "PCM-WRITE", &.{ at, 1, id });
    try support.expectStack(m, &.{ 0, -534 });
    try call(m, "PCM-CLOSE", &.{id});
    try support.expectStack(m, &.{0});
    try std.testing.expectEqual(@as(forth.Cell, 0), m.audio_pcm_handle);
    try call(m, "PCM-CLOSE", &.{id});
    try support.expectStack(m, &.{-521});
    const again = try open(m);
    try std.testing.expect(again > id);
    try call(m, "PCM-CLOSE", &.{again});
    try support.expectStack(m, &.{0});
    try std.testing.expect(f.depth == 0 and f.begins == f.ends);
}

test "PCM validates arguments and complete byte ranges without publishing partial frames" {
    try support.skipWithout(&.{.audio});
    var f = Fake{};
    var engine = newEngine();
    var frames: [4096]stream.Frame = undefined;
    const m = try support.createMachine(&f.output);
    defer support.destroyMachine(m);
    f.bind(m, &engine, &frames);
    try setup(m);
    try std.testing.expectError(error.InvalidNumber, call(m, "PCM-OPEN", &.{ 8000, 1, 8192 }));
    try support.expectStack(m, &.{ 8000, 1, 8192 });
    m.data_depth = 0;
    const id = try open(m);
    try std.testing.expectError(error.InvalidAddress, call(m, "PCM-WRITE", &.{ -1, 1, id }));
    try support.expectStack(m, &.{ -1, 1, id });
    try std.testing.expectError(error.InvalidAddress, call(m, "PCM-WRITE", &.{ 0, std.math.maxInt(i64), id }));
    try std.testing.expectEqual(@as(u32, 0), engine.pcm_session.transport.queued());
    try call(m, "PCM-WRITE", &.{ -1, 0, id });
    try support.expectStack(m, &.{ 0, 0 });
    try std.testing.expectError(error.InvalidNumber, call(m, "PCM-STOP", &.{ 2, 0, id }));
    try std.testing.expectError(error.InvalidNumber, call(m, "PCM-WAIT", &.{ 4097, 0, id }));
    try call(m, "PCM-CLOSE", &.{id});
}

test "PCM close interrupted while opening keeps closing ID and retries after acknowledgement" {
    try support.skipWithout(&.{.audio});
    var f = Fake{};
    var engine = newEngine();
    var frames: [4096]stream.Frame = undefined;
    const m = try support.createMachine(&f.output);
    defer support.destroyMachine(m);
    f.bind(m, &engine, &frames);
    try setup(m);
    const id = try open(m);
    f.output.audio_interrupt_at = 1;
    try call(m, "PCM-CLOSE", &.{id});
    try support.expectStack(m, &.{-516});
    try std.testing.expectEqual(id, m.audio_pcm_handle);
    try std.testing.expectEqual(.closing, engine.pcm_session.phase);
    try call(m, "PCM-WRITE", &.{ 0, 0, id });
    try support.expectStack(m, &.{ 0, -534 });
    f.output.audio_interrupt_at = 0;
    try call(m, "PCM-CLOSE", &.{id});
    try support.expectStack(m, &.{0});
    try std.testing.expectEqual(@as(usize, 0), f.depth);
}

test "PCM close timeout keeps storage and a late end interrupt cannot lose the handle" {
    try support.skipWithout(&.{.audio});
    var f = Fake{};
    var engine = newEngine();
    var frames: [4096]stream.Frame = undefined;
    const m = try support.createMachine(&f.output);
    defer support.destroyMachine(m);
    f.bind(m, &engine, &frames);
    try setup(m);
    const id = try open(m);
    f.output.audio_wait_samples = 0;
    try call(m, "PCM-CLOSE", &.{id});
    try support.expectStack(m, &.{-528});
    try std.testing.expectEqual(id, m.audio_pcm_handle);
    f.output.audio_wait_samples = 960;
    f.end_interrupt = true;
    try call(m, "PCM-CLOSE", &.{id});
    try support.expectStack(m, &.{-516});
    try std.testing.expectEqual(id, m.audio_pcm_handle);
    try call(m, "PCM-CLOSE", &.{id});
    try support.expectStack(m, &.{0});
}

test "PCM drain interruption preserves accepted data and failure restoration takes precedence" {
    try support.skipWithout(&.{.audio});
    var f = Fake{};
    var engine = newEngine();
    var frames: [4096]stream.Frame = undefined;
    const m = try support.createMachine(&f.output);
    defer support.destroyMachine(m);
    f.bind(m, &engine, &frames);
    try setup(m);
    const id = try open(m);
    const at = m.data_here;
    try m.reserveData(4096 * 4);
    try call(m, "PCM-WRITE", &.{ at, 4096, id });
    f.output.audio_interrupt_at = 1;
    try std.testing.expectError(error.UserInterrupt, call(m, "PCM-STOP", &.{ 1, 100, id }));
    try std.testing.expect(engine.pcm_session.transport.queued() > 0);
    try std.testing.expect(engine.pcm_session.writable());
    try std.testing.expect(!engine.pcm_session.transport.draining.load(.acquire));
    f.output.audio_interrupt_at = 0;
    f.end_failure = true;
    try std.testing.expectError(error.HostFailed, call(m, "PCM-WAIT", &.{ 1, 0, id }));
    f.end_failure = false;
    try call(m, "PCM-CLOSE", &.{id});
}

test "PCM rejects foreign ownership and exhausts IDs without reusing them" {
    try support.skipWithout(&.{.audio});
    var f = Fake{};
    var engine = newEngine();
    var frames: [4096]stream.Frame = undefined;
    const m = try support.createMachine(&f.output);
    defer support.destroyMachine(m);
    f.bind(m, &engine, &frames);
    try setup(m);
    engine.pcm_session.next_id = std.math.maxInt(i64);
    const id = try open(m);
    const other = try support.createMachine(&f.output);
    defer support.destroyMachine(other);
    f.bind(other, &engine, &frames);
    try setup(other);
    other.audio_pcm_handle = id;
    try call(other, "PCM-QUEUED", &.{id});
    try support.expectStack(other, &.{ 0, -521 });
    other.audio_pcm_handle = 0;
    try call(m, "PCM-CLOSE", &.{id});
    try call(m, "PCM-OPEN", &.{ 48000, 2, 4096 });
    try support.expectStack(m, &.{ 0, -587 });
}

test "PCM full restore is busy before mutation while save and typed append retain ownership" {
    try support.skipWithout(&.{ .audio, .image });
    var f = Fake{};
    var engine = newEngine();
    var frames: [4096]stream.Frame = undefined;
    const m = try support.createMachine(&f.output);
    defer support.destroyMachine(m);
    f.bind(m, &engine, &frames);
    try setup(m);
    const id = try open(m);
    const bytes = try std.testing.allocator.alloc(u8, forth.State.imageCapacity(.small));
    defer std.testing.allocator.free(bytes);
    const length = try m.encodeImage(bytes);
    const words = m.word_count;
    try std.testing.expectError(error.Thrown, m.restoreImage(bytes[0..length]));
    try std.testing.expectEqual(@as(i64, -528), m.throw_code);
    try std.testing.expectError(error.Thrown, m.restoreFreshImage(bytes[0..length]));
    try std.testing.expectEqual(words, m.word_count);
    const other = try support.createMachine(&f.output);
    defer support.destroyMachine(other);
    try other.restoreFreshImage(bytes[0..length]);
    try std.testing.expectEqual(@as(i64, 0), other.audio_pcm_handle);
    try m.appendImage(other);
    try std.testing.expectEqual(id, m.audio_pcm_handle);
    try call(m, "PCM-CLOSE", &.{id});
    try support.expectStack(m, &.{0});
}

test "PCM copied stereo input can be reused immediately and silent tails count once" {
    try support.skipWithout(&.{.audio});
    var f = Fake{};
    var engine = newEngine();
    var frames: [4096]stream.Frame = undefined;
    const m = try support.createMachine(&f.output);
    defer support.destroyMachine(m);
    f.bind(m, &engine, &frames);
    try setup(m);
    const id = try open(m);
    const at = m.data_here;
    try m.reserveData(4);
    @memcpy(m.memory[@intCast(at)..][0..4], &[_]u8{ 0x34, 0x12, 0xcc, 0xed });
    try call(m, "PCM-WRITE", &.{ at, 1, id });
    @memset(m.memory[@intCast(at)..][0..4], 0);
    var output: [2]i16 = undefined;
    engine.render(&output);
    try std.testing.expectEqualSlices(i16, &.{ 4660, -4660 }, &output);
    for (0..4) |_| engine.render(&output);
    try call(m, "PCM-UNDERRUNS", &.{id});
    try support.expectStack(m, &.{ 1, 0 });
    try call(m, "PCM-CLOSE", &.{id});
}

test "PCM open requires wait capabilities and reports allocation failure without ownership" {
    try support.skipWithout(&.{.audio});
    var f = Fake{};
    var engine = newEngine();
    const m = try support.createMachine(&f.output);
    defer support.destroyMachine(m);
    f.bind(m, &engine, &.{});
    try setup(m);
    m.writer.audio_scope_ops = null;
    try std.testing.expectError(error.HostUnavailable, call(m, "PCM-OPEN", &.{ 48000, 2, 4096 }));
    try support.expectStack(m, &.{ 48000, 2, 4096 });
    m.writer.audio_scope_ops = &Fake.ops;
    try call(m, "PCM-OPEN", &.{ 48000, 2, 4096 });
    try support.expectStack(m, &.{ 0, -524 });
    try std.testing.expectEqual(@as(i64, 0), m.audio_pcm_handle);
    try std.testing.expectEqual(.free, engine.pcm_session.phase);
}

test "PCM pending discard stop keeps the request on timeout and refuses writes until ack" {
    try support.skipWithout(&.{.audio});
    var f = Fake{};
    var engine = newEngine();
    var frames: [4096]stream.Frame = undefined;
    const m = try support.createMachine(&f.output);
    defer support.destroyMachine(m);
    f.bind(m, &engine, &frames);
    try setup(m);
    const id = try open(m);
    var output: [2]i16 = undefined;
    engine.render(&output); // acknowledge OPEN only
    f.output.audio_wait_samples = 0;
    try call(m, "PCM-STOP", &.{ 0, 0, id });
    try support.expectStack(m, &.{ 0, 0 });
    try std.testing.expectEqual(.stopping, engine.pcm_session.phase);
    try call(m, "PCM-WRITE", &.{ 0, 0, id });
    try support.expectStack(m, &.{ 0, -534 });
    f.output.audio_wait_samples = 960;
    try call(m, "PCM-STOP", &.{ 0, 100, id });
    try support.expectStack(m, &.{ -1, 0 });
    try call(m, "PCM-CLOSE", &.{id});
    try support.expectStack(m, &.{0});
}

test "PCM query before attach acknowledges no previous underrun count" {
    try support.skipWithout(&.{.audio});
    var f = Fake{};
    var engine = newEngine();
    var frames: [4096]stream.Frame = undefined;
    const m = try support.createMachine(&f.output);
    defer support.destroyMachine(m);
    f.bind(m, &engine, &frames);
    try setup(m);
    const id = try open(m);
    engine.pcm_session.transport.underruns.store(99, .release); // stale publication before consumer reset
    try call(m, "PCM-UNDERRUNS", &.{id});
    try support.expectStack(m, &.{ 0, 0 });
    try call(m, "PCM-CLOSE", &.{id});
}
