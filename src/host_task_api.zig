//! Main-thread public task owner. Pin Service until finish succeeds.
const std = @import("std");
const forth = @import("forth.zig");
const defs = @import("core/defs.zig");
const base = @import("core/runtime_base.zig");
const snap = @import("core/task_snapshot.zig");
const queue = @import("core/task_queue.zig");
const execution = @import("core/task_job_queue.zig");
const Host = @import("core/task_schedule_host.zig").Host;
const reap = @import("core/task_reap.zig");
const Wake = @import("host_wake.zig").Wake;
const Cell = forth.Cell;
const acceptance = @import("core/task_acceptance.zig");
pub const Identities = struct {
    serial: std.atomic.Value(u64) = .init(0),
    pub fn take(self: *Identities) !u64 {
        var old = self.serial.load(.monotonic);
        while (true) {
            if (old == std.math.maxInt(i64)) return error.IdentityExhausted;
            old = self.serial.cmpxchgWeak(old, old + 1, .monotonic, .monotonic) orelse return old + 1;
        }
    }
};
var identities: Identities = .{};
threadlocal var allocation_limited = false;
fn allocationCode() Cell {
    const limited = allocation_limited;
    allocation_limited = false;
    return if (limited) -305 else -257;
}
fn apiIor(err: anyerror) Cell {
    return if (err == error.OutOfMemory) allocationCode() else ior(err);
}

pub fn identity() !u64 {
    return identities.take();
}

/// Includes concurrent VM allocations, copies and temporary inspection storage.
const Allocations = struct {
    backing: std.mem.Allocator = std.heap.page_allocator,
    used: std.atomic.Value(usize) = .init(0),
    // Reserve the worker stack and pinned service outside allocator callbacks.
    limit: usize = 114 * 1024 * 1024 - @sizeOf(Service) - 128 * 1024,
    // Capability is checked on the backing vtable, never inferred from this
    // accounting wrapper's interface. No reuse, suballocation or remapping here.
    fn freshZeroPages(self: *const Allocations) bool {
        const os = @import("builtin").os.tag;
        return (os == .linux or os == .windows) and self.backing.vtable == std.heap.page_allocator.vtable;
    }
    fn allocator(self: *Allocations) std.mem.Allocator {
        return .{ .ptr = self, .vtable = &.{ .alloc = alloc, .free = free, .resize = std.mem.Allocator.noResize, .remap = std.mem.Allocator.noRemap } };
    }
    fn alloc(raw: *anyopaque, len: usize, alignment: std.mem.Alignment, ret: usize) ?[*]u8 {
        const self: *Allocations = @ptrCast(@alignCast(raw));
        var old = self.used.load(.monotonic);
        while (true) {
            if (len > self.limit - old) {
                allocation_limited = true;
                return null;
            }
            old = self.used.cmpxchgWeak(old, old + len, .acq_rel, .monotonic) orelse break;
        }
        return self.backing.rawAlloc(len, alignment, ret) orelse {
            _ = self.used.fetchSub(len, .acq_rel);
            return null;
        };
    }
    fn free(raw: *anyopaque, allocation: []u8, alignment: std.mem.Alignment, ret: usize) void {
        const self: *Allocations = @ptrCast(@alignCast(raw));
        self.backing.rawFree(allocation, alignment, ret);
        _ = self.used.fetchSub(allocation.len, .acq_rel);
    }
};

/// Storage.allocate's exact payload allocations plus its separately owned State.
/// Arithmetic uses u128 before comparing the 76 MiB worker-VM partition.
pub fn vmBytes(sizes: forth.Sizes) u128 {
    var total: u128 = @sizeOf(forth.State);
    total += sizes.memorySize();
    total += @as(u128, sizes.data_stack) * @sizeOf(forth.Cell);
    total += @as(u128, sizes.float_stack) * @sizeOf(forth.Float);
    inline for (.{ "return_stack", "loop_stack", "frames", "catches" }) |field| {
        const Element = @typeInfo(@TypeOf(@field(@as(forth.Storage, undefined), field))).pointer.child;
        total += @as(u128, sizes.return_stack) * @sizeOf(Element);
    }
    return total;
}

const Snapshot = struct { id: Cell, value: *snap.Snapshot };
const Task = struct {
    id: Cell,
    handle: base.Handle,
    job: queue.Job,
    run: execution.Execution,
    name: []u8,
    input: []u8,
    reservation: usize,
    valid: bool = true,
};

pub const Service = struct {
    allocations: Allocations = .{},
    manager: snap.Manager = .{},
    owner: u64 = 0,
    machine: ?*forth.State = null,
    wake: Wake = undefined,
    common_wake: ?*Wake = null,
    io: ?*const IoOps = null,
    waiting: bool = false,
    jobs: queue.DefaultQueue = undefined,
    host: Host = undefined,
    reaper: reap.Reaper = undefined,
    snapshots: [3]?Snapshot = @splat(null),
    tasks: [16]?*Task = @splat(null),
    transfer_used: usize = 0,
    initialized: bool = false,
    closed: bool = false,
    bind_host: bool = false,

    fn wakePtr(self: *Service) *Wake {
        return self.common_wake orelse &self.wake;
    }

    pub fn ensure(self: *Service, machine: *forth.State) !void {
        try @import("core/task_permissions.zig").requireHostSubmission();
        if (self.closed) return error.InvalidHandle;
        if (self.initialized) {
            if (self.machine != machine) return error.InvalidHandle;
            return;
        }
        const owner = try identity();
        if (self.common_wake == null) self.wake = try Wake.init();
        errdefer if (self.common_wake == null) {
            self.wake.deinit() catch {};
        };
        self.jobs = try queue.DefaultQueue.init(@import("host_clock.zig").clock, self.wakePtr().operations(), execution.Execution.runner());
        errdefer self.jobs.deinit() catch {};
        self.host = try Host.init(&self.jobs, owner);
        self.reaper = .{ .host = &self.host, .disposal = .{ .context = self, .destroy = destroy } };
        try self.jobs.start();
        self.owner = owner;
        self.machine = machine;
        self.initialized = true;
        if (self.bind_host) @import("host_task_reap.zig").bind(&self.reaper);
    }

    fn destroy(raw: ?*anyopaque, _: base.Handle, job: *queue.Job, _: queue.Result, _: ?Host.Publication) void {
        const self: *Service = @ptrCast(@alignCast(raw.?));
        for (&self.tasks) |*slot| if (slot.*) |payload| {
            if (&payload.job != job) continue;
            const a = self.allocations.allocator();
            const started = if (comptime acceptance.diagnostics) acceptance.now() else 0;
            payload.run.deinit();
            a.free(payload.input);
            a.free(payload.name);
            self.transfer_used -= payload.reservation;
            const probe = payload.job.acceptance;
            const task_id = payload.id;
            a.destroy(payload);
            slot.* = null;
            if (comptime acceptance.diagnostics) acceptance.interval("host_destroy_ns", started);
            if (comptime acceptance.enabled) probe.dump(task_id);
            return;
        };
        unreachable;
    }

    pub fn finish(self: *Service, cause: reap.Cause) !void {
        defer acceptance.flush();
        if (!self.initialized or self.closed) return;
        if (try self.reaper.finish(cause) != .collected) return error.WorkerUnresponsive;
        for (&self.snapshots) |*slot| if (slot.*) |version| {
            version.value.release();
            slot.* = null;
        };
        try self.jobs.deinit();
        if (self.common_wake == null) try self.wake.deinit();
        self.closed = true;
    }

    fn snapshot(self: *Service, id: Cell) !*snap.Snapshot {
        for (self.snapshots) |slot| if (slot) |version| {
            if (id > 0 and version.id == id) return version.value;
        };
        return error.InvalidHandle;
    }
    fn task(self: *Service, id: Cell) !*Task {
        for (self.tasks) |slot| if (slot) |value| {
            if (id > 0 and value.id == id and value.valid) {
                _ = try self.host.ledger.lookup(value.handle, self.owner);
                return value;
            }
        };
        return error.InvalidHandle;
    }
    pub fn poll(self: *Service) !void {
        const started = acceptance.now();
        defer acceptance.interval("management_turn_ns", started);
        try self.host.poll();
        // RELEASE never joins; collect only after physical worker handback.
        for (self.tasks) |slot| if (slot) |value| {
            if (value.valid) continue;
            const record = try self.host.ledger.inspect(value.handle, self.owner);
            if (record.state.terminal() and !record.execution_ref and record.internal_refs == 0 and !self.jobs.isCleaning(&value.job)) {
                try self.host.collect(value.handle, self.owner);
                destroy(self, value.handle, &value.job, value.job.terminal.?, null);
            }
        };
    }
    fn capture(self: *Service, machine: *forth.State) !Cell {
        for (&self.snapshots) |*slot| if (slot.* == null) {
            const id: Cell = @intCast(try identity());
            const version = try self.manager.capture(self.allocations.allocator(), machine);
            if (comptime acceptance.enabled) acceptance.value("snapshot_image_bytes", version.image().len);
            slot.* = .{ .id = id, .value = version };
            return id;
        };
        return error.ResourceFull;
    }
    fn admissionGate(_: *const anyopaque, _: []const @import("core/task_permissions.zig").Access, _: usize) bool {
        // Static analysis only checks presence; this is never an execution grant.
        return false;
    }
    fn submit(self: *Service, machine: *forth.State, args: []const Cell, name: []const u8, input: []const u8) !Cell {
        const started = acceptance.now();
        const version = try self.snapshot(args[0]);
        var admission = try version.admit(machine);
        errdefer admission.deinit();
        if (vmBytes(version.sizes) > 76 * 1024 * 1024) return error.ItemLimitExceeded;
        const profile: usize = @intCast(args[5]);
        if (profile != 3 and self.host.generation == std.math.maxInt(u64)) return error.IdentityExhausted;
        const input_limits = [_]usize{ 128 * 1024, 128 * 1024, 2 * 1024 * 1024, 128 * 1024 };
        const result_limits = [_]usize{ 512 * 1024, 128 * 1024, 64 * 1024, 4 * 1024 };
        if (input.len > input_limits[profile]) return error.ItemLimitExceeded;
        const reserve = input.len + result_limits[profile];
        if (reserve > 16 * 1024 * 1024 - self.transfer_used) return error.TotalLimitExceeded;
        const a = self.allocations.allocator();
        // Saved-code preflight does not allocate a second VM beside the worker.
        const gate = @import("core/task_permissions.zig").MemoryGate{ .context = self, .check = admissionGate };
        try version.inspectEntry(a, name, .{ .memory_gate = &gate });
        var available: ?*?*Task = null;
        for (&self.tasks) |*slot| if (slot.* == null) {
            available = slot;
            break;
        };
        const slot = available orelse return error.ResourceFull;
        const id: Cell = @intCast(try identity());
        const value = try a.create(Task);
        errdefer a.destroy(value);
        const name_copy = try a.dupe(u8, name);
        errdefer a.free(name_copy);
        const input_copy = try a.dupe(u8, input);
        errdefer a.free(input_copy);
        value.* = .{ .id = id, .handle = undefined, .job = undefined, .run = .{ .allocator = a, .oom_code_fn = allocationCode, .storage_zeroed = self.allocations.freshZeroPages(), .admission = admission, .entry = name_copy, .input = input_copy, .limits = .{ .input = input_limits[profile], .result = result_limits[profile] } }, .name = name_copy, .input = input_copy, .reservation = reserve };
        value.job = value.run.queued();
        if (comptime acceptance.enabled) {
            value.job.acceptance.submitted = started;
            value.job.acceptance.input_bytes = input.len;
        }
        value.handle = try self.host.submit(.{ .owner = self.owner, .kind = switch (profile) {
            0, 1 => .game,
            2 => .tui,
            else => .io,
        }, .stream = @intCast(args[6]), .input = .{ .bytes = input_copy }, .job = &value.job, .milliseconds = if (comptime acceptance.enabled) (if (acceptance.memory_hold) @as(i64, 120_000) else ([_]i64{ 50, 100, 100, 200 })[profile]) else ([_]i64{ 50, 100, 100, 200 })[profile] });
        if (comptime acceptance.enabled) acceptance.value("queue_waiting", self.jobs.view().count);
        self.transfer_used += reserve;
        slot.* = value;
        return id;
    }
};

pub fn ior(err: anyerror) Cell {
    return switch (err) {
        error.InvalidHandle, error.WrongOwner, error.WrongKind => -300,
        error.ResourceFull, error.QueueFull, error.VersionLimit, error.Closed => -301,
        error.StaleSnapshot => -302,
        error.EntryNotFound => -303,
        error.Denied, error.MemoryChecksRequired, error.CountedMode => -304,
        error.ImageTooLarge, error.ItemLimitExceeded, error.TotalLimitExceeded, error.InputTooLarge, error.ResultTooLarge => -305,
        error.NotReady => -306,
        error.NotQuiescent => -309,
        error.IdentityExhausted, error.EpochExhausted, error.ReferenceExhausted, error.ReferenceOverflow, error.SerialExhausted => -310,
        error.UnsupportedBackend, error.NoWindow, error.InvalidTarget => -311,
        error.OutOfMemory => -257,
        else => -312,
    };
}

fn state(service: *Service, value: *Task) !Cell {
    const record = try service.host.ledger.lookup(value.handle, service.owner);
    return switch (record.state) {
        .queued => 1,
        .running => 2,
        .succeeded => 3,
        .failed => 4,
        .cancelled => 5,
        .created => unreachable,
    };
}
fn diagnostic(value: *Task) Cell {
    if (value.job.terminal) |terminal| {
        if (terminal.reason == .queue_expired) return -313;
        if (terminal.reason == .clock_failed or terminal.reason == .worker_failed) return -312;
        if (value.run.failure_code != 0) return value.run.failure_code;
        if (value.run.failure) |err| {
            return switch (err) {
                error.TaskCancelled => 0,
                error.ResultTooLarge, error.InputTooLarge => -305,
                error.ResultStackDepth, error.ResultFloatStackNotEmpty, error.NegativeResultLength, error.ResultAddressOverflow, error.ResultOutsideDataSpace, error.ResultVmNotStopped => -308,
                else => apiIor(err),
            };
        }
    }
    return 0;
}

fn diagnosticText(value: *Task) []const u8 {
    if (diagnostic(value) == 0) return "";
    if (value.job.terminal) |terminal| {
        if (terminal.reason == .queue_expired) return "queue residence deadline exceeded";
        if (terminal.reason == .clock_failed or terminal.reason == .worker_failed) return "host failure";
    }
    return if (value.run.failure) |err| @errorName(err) else "";
}

fn bytes(machine: *forth.State, addr: Cell, len: Cell) forth.RuntimeError![]u8 {
    if (len < 0) return error.ResultOutOfRange;
    const start = try machine.memoryAddress(addr, @intCast(len));
    return machine.memory[start..][0..@intCast(len)];
}
fn result(machine: *forth.State, inputs: usize, values: []const Cell) forth.RuntimeError!void {
    machine.data_depth -= inputs;
    for (values) |v| try machine.push(v);
}

/// Validate all arguments before initialization, stack consumption or host effects.
pub fn execute(raw: ?*anyopaque, machine: *forth.State, word: defs.Builtin) forth.RuntimeError!void {
    const api_enter = acceptance.now();
    defer acceptance.flush();
    defer if (word == .task_snapshot) {
        acceptance.interval("snapshot_main_ns", api_enter);
    };
    const self: *Service = @ptrCast(@alignCast(raw.?));
    const shape = @import("core/words_task.zig").signature(word);
    const inputs = shape.inputs;
    const outputs = shape.outputs;
    try machine.requireDepth(inputs);
    if (machine.data_depth - inputs + outputs > machine.data_stack.len) return error.StackOverflow;
    const args = machine.data_stack[machine.data_depth - inputs .. machine.data_depth];
    var name: []const u8 = &.{};
    var input: []const u8 = &.{};
    var destination: []u8 = &.{};
    var deadline: base.Deadline = .{ .at = null };
    if (word == .task_wait) {
        const now = deadlineClock(self).now() catch return result(machine, inputs, &.{ 0, 8, -312 });
        deadline = base.Deadline.afterMilliseconds(now, args[1]) catch return machine.throwCode(-24);
    }
    switch (word) {
        .task_submit => {
            if (args[2] <= 0 or args[4] < 0 or args[5] < 0 or args[5] > 3 or args[6] < 0) return machine.throwCode(-24);
            name = try bytes(machine, args[1], args[2]);
            input = try bytes(machine, args[3], args[4]);
        },
        .task_result, .task_diagnostic => {
            if (args[inputs - 1] < 0) return machine.throwCode(-24);
            if (word == .task_diagnostic and (args[1] < 0 or args[1] > 3)) return machine.throwCode(-24);
            destination = try bytes(machine, args[inputs - 2], args[inputs - 1]);
        },
        .task_wait_many => return waitMany(self, machine, args),
        else => {},
    }
    self.ensure(machine) catch |err| {
        var failed: [5]Cell = @splat(0);
        failed[outputs - 1] = apiIor(err);
        if (word == .task_wait and failed[outputs - 1] == -312) failed[1] = 8;
        return result(machine, inputs, failed[0..outputs]);
    };
    self.poll() catch {
        var failed: [5]Cell = @splat(0);
        failed[outputs - 1] = -312;
        if (word == .task_wait) failed[1] = 8;
        return result(machine, inputs, failed[0..outputs]);
    };
    switch (word) {
        .task_snapshot => {
            const id = self.capture(machine) catch |err| return result(machine, 0, &.{ 0, apiIor(err) });
            try result(machine, 0, &.{ id, 0 });
        },
        .task_snapshot_release => {
            _ = self.snapshot(args[0]) catch |err| return result(machine, 1, &.{apiIor(err)});
            for (&self.snapshots) |*slot| if (slot.*) |version| {
                if (version.id == args[0]) {
                    version.value.release();
                    slot.* = null;
                    break;
                }
            };
            try result(machine, 1, &.{0});
        },
        .task_submit => {
            const id = self.submit(machine, args, name, input) catch |err| return result(machine, 7, &.{ 0, apiIor(err) });
            try result(machine, 7, &.{ id, 0 });
        },
        else => {
            const value = self.task(args[0]) catch |err| {
                var failed: [5]Cell = @splat(0);
                failed[outputs - 1] = apiIor(err);
                return result(machine, inputs, failed[0..outputs]);
            };
            const current = state(self, value) catch {
                var failed: [5]Cell = @splat(0);
                if (word == .task_wait) failed[1] = 8;
                failed[outputs - 1] = -312;
                return result(machine, inputs, failed[0..outputs]);
            };
            switch (word) {
                .task_state => {
                    if (comptime acceptance.enabled) {
                        if (acceptance.cancel_at) |stage| {
                            if (current < 3 and !value.job.cancellation.isRequested() and
                                value.job.acceptance.hold_stage.load(.acquire) == @backingInt(stage) and
                                !value.job.acceptance.hold_timeout.load(.acquire))
                            {
                                // Invoke the public TASK-CANCEL handler with the existing
                                // task id on the Forth stack; preserve its ordinary path.
                                try execute(raw, machine, .task_cancel);
                            }
                        }
                    }
                    // Trace-only host polling uses the ordinary cancellation path.
                    if (comptime @import("core/task_trace.zig").enabled) {
                        if (@import("core/task_trace.zig").cancel_at) |stage| {
                            if (current < 3 and !value.job.cancellation.isRequested()) {
                                if (value.job.cancellation.trace) |trace| {
                                    if (trace.times[@backingInt(stage)].load(.acquire) != 0) {
                                        const now = self.jobs.clock.now() catch return result(machine, 1, &.{ 0, 0, 0, 0, -312 });
                                        self.host.requestCancel(value.handle, self.owner, now) catch return result(machine, 1, &.{ 0, 0, 0, 0, -312 });
                                    }
                                }
                            }
                        }
                    }
                    const record = self.host.ledger.lookup(value.handle, self.owner) catch unreachable;
                    const text = if (current >= 3) diagnosticText(value) else "";
                    try result(machine, 1, &.{ current, if (record.cancel_requested) -1 else 0, if (current == 3) @intCast((if (value.run.result) |data| data.len else 0)) else 0, @intCast(text.len), 0 });
                },
                .task_cancel, .task_release => {
                    if (comptime acceptance.enabled) {
                        if (current < 3 and !value.job.acceptance.request_recorded) {
                            value.job.acceptance.requested = api_enter;
                            value.job.acceptance.request_recorded = true;
                            acceptance.cancellationRequested();
                            value.job.acceptance.native_request.store(api_enter, .release);
                            value.job.acceptance.request_stage = value.job.acceptance.latest.load(.acquire);
                        }
                    }
                    _ = self.jobs.notification_failed.swap(false, .acq_rel);
                    if (word == .task_release) {
                        value.valid = false;
                        self.host.release(value.handle, self.owner) catch return result(machine, 1, &.{-312});
                        if (current < 3) {
                            const now = self.jobs.clock.now() catch return result(machine, 1, &.{-312});
                            self.host.requestCancel(value.handle, self.owner, now) catch return result(machine, 1, &.{-312});
                        }
                    } else if (current < 3) {
                        const now = self.jobs.clock.now() catch return result(machine, 1, &.{-312});
                        self.host.requestCancel(value.handle, self.owner, now) catch return result(machine, 1, &.{-312});
                    }
                    try result(machine, 1, &.{if (self.jobs.notification_failed.swap(false, .acq_rel) and current < 3) @as(Cell, -312) else 0});
                },
                .task_result => {
                    if (current < 3) return result(machine, 3, &.{ 0, 0, -306 });
                    const data: []const u8 = if (current == 3) value.run.result orelse &.{} else &.{};
                    if (destination.len < data.len) return result(machine, 3, &.{ @intCast(data.len), current, -307 });
                    @import("core/address_registry.zig").written(machine, args[1], data.len, false);
                    @memcpy(destination[0..data.len], data);
                    try result(machine, 3, &.{ @intCast(data.len), current, 0 });
                },
                .task_diagnostic => {
                    if (current < 3 and args[1] != 3) return result(machine, 4, &.{ 0, 0, -306 });
                    const stop = self.host.stopDiagnostic(value.handle, self.owner) catch null;
                    if (current < 3 and (stop == null or !stop.?.stop_exceeded)) return result(machine, 4, &.{ 0, 0, -306 });
                    const code = if (args[1] == 0) diagnostic(value) else if (args[1] == 3 and stop != null and stop.?.stop_exceeded) @as(Cell, -314) else 0;
                    const text: []const u8 = if (args[1] == 0) diagnosticText(value) else if (args[1] == 3 and code != 0) "stop unconfirmed" else "";
                    if (destination.len < text.len) return result(machine, 4, &.{ @intCast(text.len), code, -307 });
                    @import("core/address_registry.zig").written(machine, args[2], text.len, false);
                    @memcpy(destination[0..text.len], text);
                    try result(machine, 4, &.{ @intCast(text.len), code, 0 });
                },
                .task_wait => try waitOne(self, machine, value, deadline),
                else => unreachable,
            }
        },
    }
}

const TaskWait = struct {
    service: *Service,
    value: *Task,
    backend: native.Task(queue.DefaultQueue),
    fn source(self: *TaskWait) wait.Source {
        return .{ .context = self, .validate = validate, .attach = attach, .prepare = prepare, .probe = probe, .detach = detach };
    }
    fn cast(raw: ?*anyopaque) *TaskWait {
        return @ptrCast(@alignCast(raw.?));
    }
    fn validate(raw: ?*anyopaque) base.Error!void {
        const self = cast(raw);
        const source_ = self.backend.source();
        try source_.validate(source_.context);
    }
    fn attach(raw: ?*anyopaque) base.Error!void {
        const self = cast(raw);
        self.service.host.ledger.retain(self.value.handle, self.service.owner) catch return error.HostFailed;
    }
    fn prepare(raw: ?*anyopaque) base.Error!void {
        const self = cast(raw);
        const source_ = self.backend.source();
        try source_.prepare.?(source_.context);
    }
    fn probe(raw: ?*anyopaque) base.Error!wait.State {
        const self = cast(raw);
        const source_ = self.backend.source();
        return source_.probe(source_.context);
    }
    fn detach(raw: ?*anyopaque) void {
        const self = cast(raw);
        self.service.host.ledger.drop(self.value.handle, self.service.owner) catch unreachable;
    }
};

fn deadlineClock(self: *Service) base.Clock {
    return if (self.initialized) self.jobs.clock else @import("host_clock.zig").clock;
}

fn waitOne(self: *Service, machine: *forth.State, value: *Task, deadline: base.Deadline) forth.RuntimeError!void {
    var source = TaskWait{ .service = self, .value = value, .backend = .{ .queue = &self.jobs, .job = &value.job } };
    var registration = wait.Registration{ .clock = self.jobs.clock, .wake = self.wakePtr().operations(), .deadline = deadline };
    registration.open(&.{.{ .kind = .task, .identity = value.handle, .source = source.source() }}) catch return result(machine, 2, &.{ 0, 8, -312 });
    defer registration.close();
    @import("host_wait.zig").beginInput() catch return result(machine, 2, &.{ 0, 8, -312 });
    var scoped = true;
    defer if (scoped) {
        @import("host_wait.zig").endInput() catch {};
    };
    while (true) {
        const found = native.poll(&registration, @import("host_wait.zig").takeInterrupt());
        if (found.interrupted) return error.UserInterrupt;
        if (found.finished()) {
            self.host.poll() catch return result(machine, 2, &.{ 0, 8, -312 });
            const current = state(self, value) catch return result(machine, 2, &.{ 0, 8, -312 });
            scoped = false;
            var host_failed = found.failed;
            @import("host_wait.zig").endInput() catch |err| {
                if (err == error.UserInterrupt) return err;
                host_failed = true;
            };
            const flags: Cell = (if (found.expired) @as(Cell, 1) else 0) | (if (found.cancelled) @as(Cell, 2) else 0) | (if (host_failed) @as(Cell, 8) else 0);
            return result(machine, 2, &.{ current, flags, if (host_failed) @as(Cell, -312) else 0 });
        }
        native.sleep(&registration, found, self.wakePtr(), &.{}) catch return result(machine, 2, &.{ 0, 8, -312 });
    }
}

const wait = @import("core/task_wait.zig");
const native = @import("host_task_wait.zig");
pub const IoOps = struct {
    check: *const fn (Cell, bool) Cell,
    attach: *const fn (Cell, bool) forth.RuntimeError!void,
    probe: *const fn (Cell, bool) forth.RuntimeError!wait.State,
    interest: *const fn (Cell, bool) ?Wake.Interest,
};
const IoSource = struct {
    ops: *const IoOps,
    id: Cell,
    mask: Cell,
    input: bool = false,
    fn source(self: *IoSource) wait.Source {
        return .{ .context = self, .validate = validate, .attach = attach, .probe = probe, .detach = native.noop.detach };
    }
    fn validate(raw: ?*anyopaque) base.Error!void {
        const self: *IoSource = @ptrCast(@alignCast(raw.?));
        if (self.mask & 1 != 0 and self.ops.check(self.id, false) != 0) return error.HostFailed;
        if (self.mask & 2 != 0 and self.ops.check(self.id, true) != 0) return error.HostFailed;
    }
    fn attach(raw: ?*anyopaque) base.Error!void {
        const self: *IoSource = @ptrCast(@alignCast(raw.?));
        if (self.mask & 1 != 0) self.ops.attach(self.id, false) catch return error.HostFailed;
        if (self.mask & 2 != 0) self.ops.attach(self.id, true) catch return error.HostFailed;
    }
    fn probe(raw: ?*anyopaque) base.Error!wait.State {
        const self: *IoSource = @ptrCast(@alignCast(raw.?));
        var found: wait.State = .{};
        inline for (0..2) |direction| {
            if (self.mask & (@as(Cell, 1) << direction) != 0) {
                const value = self.ops.probe(self.id, direction == 1) catch |err| {
                    if (err == error.UserInterrupt) return .{ .interrupted = true };
                    return error.HostFailed;
                };
                found.again = found.again or value.again;
                found.interrupted = found.interrupted or value.interrupted;
                found.next = wait.earlier(found.next, value.next);
                if (value.reason) |reason| {
                    found.reason = reason;
                    found.mask |= @intCast(reasonMask(reason));
                    if (value.detail != 0) found.detail = value.detail;
                }
            }
        }
        if (self.input and found.mask & 2 != 0) {
            found.mask = (found.mask & ~@as(u16, 2)) | 1;
            found.reason = .input;
        }
        return found;
    }
};
fn reasonMask(reason: wait.Reason) Cell {
    return switch (reason) {
        .input => 1,
        .readable => 2,
        .writable => 4,
        .eof => 8,
        .failure => 16,
        .closed => 32,
        .succeeded => 64,
        .failed => 128,
        .cancelled => 256,
        .released => 512,
        .deadline => 1024,
        .painted => 2048,
        .capability_lost => 4096,
    };
}
fn waitMany(self: *Service, machine: *forth.State, args: []const Cell) forth.RuntimeError!void {
    if (args[1] < 1 or args[1] > 64 or args[3] < 0 or @mod(args[0], 8) != 0 or @mod(args[2], 8) != 0) return machine.throwCode(-24);
    const count: usize = @intCast(args[1]);
    if (args[3] > std.math.maxInt(Cell) / 32) return machine.throwCode(-24);
    const targets_bytes = try bytes(machine, args[0], args[1] * 40);
    const events_bytes = try bytes(machine, args[2], args[3] * 32);
    if (targets_bytes.len != 0 and events_bytes.len != 0 and args[0] < args[2] + @as(Cell, @intCast(events_bytes.len)) and args[2] < args[0] + @as(Cell, @intCast(targets_bytes.len))) return machine.throwCode(-24);
    var records: [64][5]Cell = undefined;
    for (records[0..count], 0..) |*record, i| {
        for (record, 0..) |*cell, j| cell.* = machine.readCell(args[0] + @as(Cell, @intCast((i * 5 + j) * 8))) catch return error.InvalidAddress;
        const kind = record[0];
        if (kind < 1 or kind > 5) return machine.throwCode(-24);
        if ((kind == 1 and (record[1] != 0 or record[2] != 0 or record[3] != 0)) or
            (kind == 2 and (record[2] < 1 or record[2] > 3 or record[3] != 0)) or
            (kind == 3 and (record[2] != 0 or record[3] != 0)) or
            (kind == 4 and (record[1] != 0 or record[2] < 0 or record[3] != 0)) or
            (kind == 5 and record[3] != 0)) return machine.throwCode(-24);
    }
    if (args[3] < args[1]) return result(machine, 5, &.{ args[1], 0, -307 });
    if (self.waiting) return result(machine, 5, &.{ 0, 0, -309 });
    for (records[0..count]) |record| {
        if (record[0] == 2 and (!defs.files_enabled or self.io == null)) return result(machine, 5, &.{ 0, 0, -311 });
        if (record[0] == 5) {
            if (record[1] != 0) return result(machine, 5, &.{ 0, 0, -300 });
            if (!@import("host_window.zig").paintCapable(machine)) return result(machine, 5, &.{ 0, 0, -311 });
        }
    }
    const started = deadlineClock(self).now() catch return result(machine, 5, &.{ 0, 8, -312 });
    const deadline = base.Deadline.afterMilliseconds(started, args[4]) catch return machine.throwCode(-24);
    var clock_targets: [64]?base.Instant = @splat(null);
    for (records[0..count], 0..) |record, i| {
        if (record[0] == 4) clock_targets[i] = (base.Deadline.afterMilliseconds(started, record[2]) catch return machine.throwCode(-24)).at;
    }
    self.ensure(machine) catch |err| {
        const code = apiIor(err);
        return result(machine, 5, &.{ 0, if (code == -312) @as(Cell, 8) else 0, code });
    };
    self.poll() catch return result(machine, 5, &.{ 0, 8, -312 });
    var targets: [64]wait.Target = undefined;
    var tasks: [64]TaskWait = undefined;
    var ios: [64]IoSource = undefined;
    var inputs: [64]native.Input = undefined;
    var paints: [64]native.Paint = undefined;
    var paint_count: usize = 0;
    defer for (paints[0..paint_count]) |*paint| paint.close();
    var interests: [128]Wake.Interest = undefined;
    var interest_count: usize = 0;
    for (records[0..count], 0..) |record, i| {
        const kind = record[0];
        targets[i] = .{ .kind = switch (kind) {
            1 => .input,
            2 => .io,
            3 => .task,
            5 => .paint,
            else => .clock,
        }, .identity = .{ .epoch = self.owner, .serial = @intCast(i + 1) } };
        switch (kind) {
            1 => {
                inputs[i] = .{ .machine = machine };
                const redirected = @import("core/input_redirect.zig").selected(machine);
                if (redirected != null or !@import("host_input.zig").input_is_terminal) {
                    const ops = self.io orelse return result(machine, 5, &.{ 0, 0, -311 });
                    ios[i] = .{ .ops = ops, .id = redirected orelse forth.stdin_fileid, .mask = 1, .input = true };
                    ios[i].source().validate(&ios[i]) catch return result(machine, 5, &.{ 0, 0, -300 });
                    inputs[i].redirected = ios[i].source();
                    if (ops.interest(ios[i].id, false)) |interest| {
                        interests[interest_count] = interest;
                        interest_count += 1;
                    }
                    // Native Input only consults redirected for explicit WITH-INPUT.
                    targets[i].source = ios[i].source();
                } else {
                    targets[i].source = inputs[i].source();
                    if (inputs[i].interest()) |interest| {
                        interests[interest_count] = interest;
                        interest_count += 1;
                    }
                }
            },
            2 => {
                ios[i] = .{ .ops = self.io.?, .id = record[1], .mask = record[2] };
                ios[i].source().validate(&ios[i]) catch return result(machine, 5, &.{ 0, 0, -300 });
                targets[i].source = ios[i].source();
                inline for (0..2) |direction| {
                    if (record[2] & (@as(Cell, 1) << direction) != 0) if (self.io.?.interest(record[1], direction == 1)) |interest| {
                        if (interest_count == interests.len) return result(machine, 5, &.{ 0, 0, -301 });
                        interests[interest_count] = interest;
                        interest_count += 1;
                    };
                }
            },
            3 => {
                const value = self.task(record[1]) catch return result(machine, 5, &.{ 0, 0, -300 });
                tasks[i] = .{ .service = self, .value = value, .backend = .{ .queue = &self.jobs, .job = &value.job } };
                targets[i].identity = value.handle;
                targets[i].source = tasks[i].source();
            },
            4 => targets[i].at = clock_targets[i],
            5 => {
                if (record[1] != 0) return result(machine, 5, &.{ 0, 0, -300 });
                const paint = &paints[paint_count];
                paint.* = native.Paint.init(machine, i, @bitCast(record[2])) catch |err| return result(machine, 5, &.{ 0, 0, switch (err) {
                    error.UnsupportedBackend, error.NoWindow => @as(Cell, -311),
                    error.InvalidTarget => @as(Cell, -300),
                    else => @as(Cell, -312),
                } });
                paint_count += 1;
                targets[i].source = paint.source();
            },
            else => unreachable,
        }
    }
    if (paint_count != 0) if (@import("host_window.zig").paintInterest()) |interest| {
        interests[interest_count] = interest;
        interest_count += 1;
    };
    var registration = wait.Registration{ .wake = self.wakePtr().operations(), .clock = self.jobs.clock, .deadline = deadline };
    registration.open(targets[0..count]) catch return result(machine, 5, &.{ 0, 8, -312 });
    defer registration.close();
    self.waiting = true;
    defer self.waiting = false;
    const guard = @import("host_wait.zig");
    guard.beginInput() catch return result(machine, 5, &.{ 0, 8, -312 });
    var scoped = true;
    defer if (scoped) {
        guard.endInput() catch {};
    };
    while (true) {
        const found = native.poll(&registration, guard.takeInterrupt());
        if (found.interrupted) return error.UserInterrupt;
        if (found.finished()) {
            var host_failed = found.failed;
            scoped = false;
            guard.endInput() catch |err| {
                if (err == error.UserInterrupt) return err;
                host_failed = true;
            };
            // Commit only after interrupt restoration; a THROW never partially writes.
            // task_wait collects sources before clocks. Serialize in public index order.
            var ordered: [64]?wait.Item = @splat(null);
            for (found.items[0..found.count]) |item| ordered[item.index] = item;
            var n: usize = 0;
            for (ordered[0..count]) |slot| if (slot) |item| {
                const at = args[2] + @as(Cell, @intCast(n * 32));
                const mask: Cell = if (item.mask != 0) item.mask else reasonMask(item.reason);
                const detail: Cell = if (mask & 16 != 0) std.math.cast(Cell, item.detail) orelse -312 else 0;
                const values = [_]Cell{ @intCast(item.index), records[item.index][4], mask, detail };
                for (values, 0..) |v, j| try machine.writeCell(at + @as(Cell, @intCast(j * 8)), v);
                n += 1;
            };
            const flags: Cell = (if (found.expired) @as(Cell, 1) else 0) | (if (found.cancelled) @as(Cell, 2) else 0) | (if (host_failed) @as(Cell, 8) else 0);
            return result(machine, 5, &.{ @intCast(n), flags, if (host_failed) @as(Cell, -312) else 0 });
        }
        native.sleep(&registration, found, self.wakePtr(), interests[0..interest_count]) catch return result(machine, 5, &.{ 0, 8, -312 });
    }
}

test "allocation limit survives intervening successful allocation until reported" {
    var allocations: Allocations = .{ .limit = 8 };
    const a = allocations.allocator();
    try std.testing.expectError(error.OutOfMemory, a.alloc(u8, 9));
    const data = try a.alloc(u8, 1);
    defer a.free(data);
    try std.testing.expectEqual(@as(Cell, -305), allocationCode());
    try std.testing.expectEqual(@as(Cell, -257), allocationCode());
}

test "accounting allocator zero-page capability and worker Storage zero contract" {
    var allocations: Allocations = .{};
    if (!allocations.freshZeroPages()) return error.SkipZigTest;
    const allocator = allocations.allocator();
    const Probe = struct {
        zero_chunks: usize = 0,
        fn visit(raw: ?*anyopaque, stage: @import("core/task_setup.zig").Stage) void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            if (stage == .zero_chunk) self.zero_chunks += 1;
        }
    };
    var probe: Probe = .{};
    var cancellation: @import("core/runtime_base.zig").Cancellation = .{};
    {
        const storage = try @import("core/task_storage.zig").allocate(allocator, allocations.freshZeroPages(), .small, .{ .cancellation = &cancellation, .hook = .{ .context = &probe, .visit = Probe.visit } }, null);
        defer storage.free(allocator);
        if (std.debug.runtime_safety) {
            try std.testing.expect(probe.zero_chunks > 0);
        } else {
            try std.testing.expectEqual(@as(usize, 0), probe.zero_chunks);
        }
        // Includes un-restored data space: task_transfer may return any valid bytes
        // there, so zeroed fresh storage is a confidentiality requirement.
        for (storage.memory) |value| try std.testing.expectEqual(@as(u8, 0), value);
        for (storage.data_stack) |value| try std.testing.expectEqual(@as(Cell, 0), value);
        for (storage.return_stack) |value| try std.testing.expectEqual(@as(Cell, 0), value);
        for (storage.float_stack) |value| try std.testing.expectEqual(@as(forth.Float, 0), value);
    }
    try std.testing.expectEqual(@as(usize, 0), allocations.used.load(.acquire));
    allocations.backing = std.testing.allocator;
    try std.testing.expect(!allocations.freshZeroPages());
}
