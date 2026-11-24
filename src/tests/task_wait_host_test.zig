const std = @import("std");
const base = @import("../core/runtime_base.zig");
const wait = @import("../core/task_wait.zig");
const host = @import("../host_task_wait.zig");
const Wake = @import("../host_wake.zig").Wake;
const Fake = struct {
    now: base.Instant = 10,
    ready: bool = false,
    attached: usize = 0,
    detached: usize = 0,
    wake: *Wake,
    fn clock(context: ?*anyopaque) base.Error!base.Instant {
        const self: *@This() = @ptrCast(@alignCast(context.?));
        return self.now;
    }
    fn attach(context: ?*anyopaque) base.Error!void {
        const self: *@This() = @ptrCast(@alignCast(context.?));
        self.attached += 1;
        self.ready = true;
        try self.wake.notify();
    }
    fn probe(context: ?*anyopaque) base.Error!wait.State {
        const self: *@This() = @ptrCast(@alignCast(context.?));
        return .{ .reason = if (self.ready) .readable else null };
    }
    fn detach(context: ?*anyopaque) void {
        const self: *@This() = @ptrCast(@alignCast(context.?));
        self.detached += 1;
        self.ready = true;
        self.wake.notify() catch unreachable;
    }
    fn source(self: *@This()) wait.Source {
        return .{ .context = self, .validate = host.noop.check, .attach = attach, .probe = probe, .detach = detach };
    }
};
test "registration preserves simultaneous source deadline and cancellation, detach retains state" {
    var wake = try Wake.init();
    defer wake.deinit() catch unreachable;
    var fake = Fake{ .wake = &wake };
    var token = base.Cancellation{};
    var registration = wait.Registration{ .wake = wake.operations(), .clock = .{ .context = &fake, .now_fn = Fake.clock }, .deadline = .{ .at = 10 }, .cancellation = &token };
    const targets = [_]wait.Target{
        .{ .kind = .io, .identity = .{ .epoch = 1, .serial = 1 }, .source = fake.source() },
        .{ .kind = .clock, .identity = .{ .epoch = 1, .serial = 2 }, .at = 10 },
    };
    try registration.open(&targets);
    try registration.requestCancellation();
    const result = registration.poll();
    try std.testing.expectEqual(@as(usize, 2), result.count);
    try std.testing.expect(result.expired and result.cancelled and !result.interrupted);
    try std.testing.expectEqual(wait.Reason.readable, result.items[0].reason);
    try std.testing.expectEqual(wait.Reason.deadline, result.items[1].reason);
    registration.close();
    try std.testing.expectEqual(@as(usize, 1), fake.detached);
    try std.testing.expect(fake.ready);
    // The next registration sees the persistent state from detachment.
    try registration.open(targets[0..1]);
    defer registration.close();
    try std.testing.expectEqual(@as(usize, 1), registration.poll().count);
}
test "native wait adapter instantiates and false clock deadline does not sleep" {
    var wake = try Wake.init();
    defer wake.deinit() catch unreachable;
    var fake = Fake{ .wake = &wake };
    var registration = wait.Registration{ .wake = wake.operations(), .clock = .{ .context = &fake, .now_fn = Fake.clock }, .deadline = .{ .at = null } };
    try registration.open(&.{.{ .kind = .clock, .identity = .{ .epoch = 1, .serial = 1 }, .at = 11 }});
    defer registration.close();
    var result = registration.poll();
    try std.testing.expectEqual(@as(?base.Instant, 11), result.next.at);
    try std.testing.expect(!result.finished());
    try wake.notify();
    try host.sleep(&registration, result, &wake, &.{});
    fake.now = 11;
    result = registration.poll();
    try std.testing.expectEqual(@as(usize, 1), result.count);
    try host.sleep(&registration, result, &wake, &.{});
    std.testing.refAllDecls(host.Input);
    std.testing.refAllDecls(host.Task(@import("../core/task_queue.zig").DefaultQueue));
}
test "task wait sleep uses absolute clock and task publication is acquired without consuming" {
    const queue_module = @import("../core/task_queue.zig");
    var wake = try Wake.init();
    defer wake.deinit() catch unreachable;
    var fake = Fake{ .wake = &wake };
    var registration = wait.Registration{ .wake = wake.operations(), .clock = .{ .context = &fake, .now_fn = Fake.clock }, .deadline = .{ .at = 10 } };
    try host.sleep(&registration, .{ .next = .{ .at = 10 } }, &wake, &.{});
    const Runner = struct {
        fn run(_: ?*anyopaque, _: *queue_module.Job) queue_module.Result {
            return .{ .kind = .succeeded };
        }
    };
    var queue = try queue_module.DefaultQueue.init(registration.clock, wake.operations(), .{ .run_fn = Runner.run });
    defer queue.deinit() catch unreachable;
    var job = queue_module.Job{ .phase = .sealed, .result = .{ .kind = .failed } };
    job.ready.store(true, .release);
    var task = host.Task(queue_module.DefaultQueue){ .queue = &queue, .job = &job };
    const source = task.source();
    try std.testing.expectEqual(wait.Reason.failed, (try source.probe(source.context)).reason.?);
    try std.testing.expect(job.terminal != null);
    try std.testing.expectEqual(wait.Reason.failed, (try source.probe(source.context)).reason.?);
    job.external_valid = false;
    try std.testing.expectEqual(wait.Reason.released, (try source.probe(source.context)).reason.?);
}
test "POSIX signal self pipe joins common native wait without handler calling Wake" {
    if (@import("builtin").os.tag == .windows) return error.SkipZigTest;
    const pipe = @import("../host_signal_pipe.zig");
    try pipe.open();
    defer pipe.close() catch unreachable;
    var wake = try Wake.init();
    defer wake.deinit() catch unreachable;
    pipe.signal();
    const clock = @import("../host_clock.zig").clock;
    const deadline = try base.Deadline.afterMilliseconds(try clock.now(), 1000);
    try std.testing.expectEqual(base.WakeOutcome.notified, try wake.waitMany(wake.observe(), deadline, null, clock, &.{.{ .fd = pipe.descriptor() }}));
    try std.testing.expect(try pipe.pump());
    try std.testing.expect(!try pipe.pump());
}

test "input wait peek retains events and decoder deadline" {
    const input_module = @import("../host_input.zig");
    const standard = @import("../core/standard_event.zig");
    const support = @import("support.zig");
    var output = support.Output{};
    const machine = try support.createMachine(&output);
    defer support.destroyMachine(machine);
    const saved = input_module.input_is_terminal;
    input_module.input_is_terminal = false;
    defer input_module.input_is_terminal = saved;
    const FakeClock = struct {
        fn now(_: ?*anyopaque) @import("../core/runtime_base.zig").Error!@import("../core/runtime_base.zig").Instant {
            return 10;
        }
    };
    const Read = struct {
        fn read(_: ?*anyopaque, _: i32) @import("../forth.zig").RuntimeError!standard.Result {
            return .timeout;
        }
    };
    machine.writer.standard_event_fn = Read.read;
    machine.writer.standard_clock = .{ .context = null, .now_fn = FakeClock.now };
    try machine.standard_input.putByte('A');
    var adapter = @import("../host_task_wait.zig").Input{ .machine = machine };
    const source = adapter.source();
    const event_input = @import("../core/event_input.zig");
    event_input.modern_depth += 1;
    const reentered = source.probe(source.context);
    event_input.modern_depth -= 1;
    try std.testing.expectError(error.HostFailed, reentered);
    try source.validate(source.context);
    try source.attach(source.context);
    defer source.detach(source.context);
    try std.testing.expectEqual(wait.Reason.input, (try source.probe(source.context)).reason.?);
    try std.testing.expectEqual(@as(u8, 'A'), machine.standard_input.takeByte().?);
    try machine.standard_input.putByte(27);
    const state = try source.probe(source.context);
    try std.testing.expectEqual(@as(?wait.Reason, null), state.reason);
    try std.testing.expectEqual(@as(?@import("../core/runtime_base.zig").Instant, 10 + 50_000_000), state.next.at);
}
test "borrowed common Wake survives failed native producer cleanup" {
    var runtime = try @import("../host_runtime.zig").Runtime.init();
    defer {
        runtime.native_users = 0;
        runtime.deinit() catch unreachable;
    }
    runtime.native_users = 1;
    try std.testing.expectError(error.ResourceBusy, runtime.deinit());
    const before = try runtime.observe();
    try runtime.notify();
    try std.testing.expect((try runtime.observe()) != before);
}

test "sleep rejects a foreign Wake and observes publication without recovery clock" {
    var wake = try Wake.init();
    defer wake.deinit() catch unreachable;
    var foreign = try Wake.init();
    defer foreign.deinit() catch unreachable;
    const Clock = struct {
        fn fail(_: ?*anyopaque) base.Error!base.Instant {
            return error.HostFailed;
        }
    };
    var registration = wait.Registration{ .wake = wake.operations(), .clock = .{ .context = null, .now_fn = Clock.fail }, .deadline = .{ .at = null } };
    try std.testing.expectError(error.HostFailed, host.sleep(&registration, .{}, &foreign, &.{}));
    registration.observed = wake.observe();
    try wake.notify();
    // No clock access or periodic recovery can hide a mismatched generation.
    try host.sleep(&registration, .{}, &wake, &.{});
}
test "cancellation and user interruption remain independent" {
    var wake = try Wake.init();
    defer wake.deinit() catch unreachable;
    var fake = Fake{ .wake = &wake };
    var token = base.Cancellation{};
    var registration = wait.Registration{ .wake = wake.operations(), .clock = .{ .context = &fake, .now_fn = Fake.clock }, .deadline = .{ .at = 10 }, .cancellation = &token };
    try registration.open(&.{.{ .kind = .clock, .identity = .{ .epoch = 1, .serial = 1 }, .at = 10 }});
    defer registration.close();
    token.request();
    const result = host.poll(&registration, true);
    try std.testing.expect(result.cancelled and result.interrupted and result.expired and result.count == 1);
}
