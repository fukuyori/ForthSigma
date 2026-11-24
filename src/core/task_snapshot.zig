//! Internal immutable dictionary versions. No execution permission is implied.
//! Capture/admission and structural edits are serialized by the main VM owner.
//! Each thread must own a reference; publishing that reference needs external
//! synchronization. The allocator must support allocation/free on its users' threads.
const std = @import("std");
const forth = @import("../forth.zig");
const encoder = @import("image_encoder.zig");
const restore = @import("image_restore.zig");
const Plan = @import("image_restore_plan.zig").Plan;

var next_id: std.atomic.Value(u64) = .init(0);

fn uniqueId() error{IdentityExhausted}!u64 {
    var previous = next_id.load(.monotonic);
    while (true) {
        if (previous == std.math.maxInt(u64)) return error.IdentityExhausted;
        previous = next_id.cmpxchgWeak(previous, previous + 1, .monotonic, .monotonic) orelse return previous + 1;
    }
}

/// One manager per task subsystem, shared by all source VMs and versions.
/// Keep its address and limits stable until every capture/reference is released.
/// Capture and structural edits still require main-owner serialization.
pub const Manager = struct {
    max_image_bytes: usize = 4 * 1024 * 1024,
    max_versions: usize = 3,
    live_versions: std.atomic.Value(usize) = .init(0),

    pub fn capture(self: *Manager, allocator: std.mem.Allocator, main: *forth.State) !*Snapshot {
        // Reject incomplete parser/compiler transactions before identity/allocation.
        if (main.defining or main.quote_depth != 0 or main.compiling or
            main.pending != .none or main.postponing or main.control_depth != 0 or
            main.quote_closing or main.noname_next or main.next_name_len != 0 or
            main.colon_is_word != null or main.interpret_loop_depth != 0)
            return error.NotQuiescent;
        var previous = self.live_versions.load(.monotonic);
        while (true) {
            if (previous >= self.max_versions) return error.VersionLimit;
            previous = self.live_versions.cmpxchgWeak(previous, previous + 1, .acq_rel, .monotonic) orelse break;
        }
        errdefer self.releaseVersion();
        return Snapshot.captureReserved(allocator, main, self);
    }

    fn releaseVersion(self: *Manager) void {
        const previous = self.live_versions.fetchSub(1, .acq_rel);
        std.debug.assert(previous != 0);
    }
};

pub const Snapshot = struct {
    allocator: std.mem.Allocator,
    manager: *Manager,
    // Treat fields as private: consumers borrow bytes through image().
    bytes: []const u8,
    id: u64,
    // Version is the globally monotonic successful-capture identity (gaps allowed).
    version: u64,
    origin: u64,
    epoch: u64,
    sizes: forth.Sizes,
    references: std.atomic.Value(usize) = .init(1),

    fn captureReserved(allocator: std.mem.Allocator, main: *forth.State, manager: *Manager) !*Snapshot {
        if (main.task_structure_epoch == std.math.maxInt(u64)) return error.EpochExhausted;
        if (main.task_snapshot_origin == 0) main.task_snapshot_origin = try uniqueId();
        const work = try allocator.create(encoder.Workspace);
        defer allocator.destroy(work);
        const measured = try encoder.measure(main, work);
        if (measured > manager.max_image_bytes) return error.ImageTooLarge;
        const bytes = try allocator.alloc(u8, measured);
        errdefer allocator.free(bytes);
        // Same encoder as encodeImage, with explicitly heap-owned workspace.
        const length = try encoder.encode(main, bytes, work);
        std.debug.assert(length == bytes.len);
        const self = try allocator.create(Snapshot);
        errdefer allocator.destroy(self);
        const id = try uniqueId();
        self.* = .{ .allocator = allocator, .manager = manager, .bytes = bytes, .id = id, .version = id, .origin = main.task_snapshot_origin, .epoch = main.task_structure_epoch, .sizes = main.sizes };
        @import("task_acceptance.zig").memoryCheckpoint();
        return self;
    }

    /// Resolve against the saved search order/case flags and inspect saved code
    /// without creating a second VM while the sole worker is running.
    pub fn inspectEntry(self: *const Snapshot, allocator: std.mem.Allocator, name: []const u8, options: @import("task_permissions.zig").Options) !void {
        const format = @import("image_format.zig");
        const map = @import("memory_map.zig");
        const work = try allocator.create(format.Workspace);
        defer allocator.destroy(work);
        const view = try format.parse(self.bytes, work);
        defer @import("task_acceptance.zig").memoryCheckpoint();
        const memory = view.memory;
        const depth = std.mem.readInt(forth.Cell, memory[@intCast(map.search_order_depth_address)..][0..8], .little);
        const flags: u64 = @bitCast(std.mem.readInt(forth.Cell, memory[@intCast(map.case_wordlists_address)..][0..8], .little));
        if (depth < 0 or depth > map.max_search_order) return error.InvalidImage;
        for (0..@intCast(depth)) |order| {
            const at: usize = @intCast(map.search_order_address + @as(forth.Cell, @intCast(order)) * 8);
            const wid = std.mem.readInt(forth.Cell, memory[at..][0..8], .little);
            const sensitive = wid == map.macros_wordlist or (wid >= 1 and wid <= map.max_wordlists and flags & (@as(u64, 1) << @intCast(wid - 1)) != 0);
            var index = view.header.word_count;
            while (index > 0) {
                index -= 1;
                const word = std.mem.bytesToValue(@import("defs.zig").Word, view.words[index * @sizeOf(@import("defs.zig").Word) ..][0..@sizeOf(@import("defs.zig").Word)]);
                if (word.wordlist != wid or word.name_len == 0) continue;
                const saved = view.names[word.name_start..][0..word.name_len];
                if (if (sensitive) std.mem.eql(u8, saved, name) else forth.State.asciiEqlIgnoreCase(saved, name)) {
                    _ = try @import("task_permissions.zig").inspectImage(allocator, view, @intCast(index), options);
                    return;
                }
            }
        }
        return error.EntryNotFound;
    }

    pub fn image(self: *const Snapshot) []const u8 {
        return self.bytes;
    }

    pub fn canSubmit(self: *const Snapshot, main: *const forth.State) bool {
        return main.task_structure_epoch != std.math.maxInt(u64) and self.origin == main.task_snapshot_origin and self.epoch == main.task_structure_epoch;
    }

    /// Acquire a running/queued reference before releasing the main-owner lock.
    /// Already admitted references remain valid after a structural edit.
    pub fn admit(self: *Snapshot, main: *const forth.State) !Admission {
        if (!self.canSubmit(main)) return error.StaleSnapshot;
        try self.retain();
        return .{ .snapshot = self };
    }

    /// A live owned reference is required. Never resurrect a released pointer.
    pub fn retain(self: *Snapshot) error{ReferenceExhausted}!void {
        var previous = self.references.load(.monotonic);
        while (true) {
            std.debug.assert(previous != 0);
            if (previous == std.math.maxInt(usize)) return error.ReferenceExhausted;
            previous = self.references.cmpxchgWeak(previous, previous + 1, .monotonic, .monotonic) orelse return;
        }
    }

    pub fn release(self: *Snapshot) void {
        const previous = self.references.fetchSub(1, .acq_rel);
        std.debug.assert(previous != 0);
        if (previous == 1) {
            const allocator = self.allocator;
            const manager = self.manager;
            allocator.free(self.bytes);
            allocator.destroy(self);
            manager.releaseVersion();
        }
    }
};

/// Owned submission reference; create it only through Snapshot.admit. Do not copy
/// ownership by value. Moving it to a queue/worker requires synchronized handoff.
pub const Admission = struct {
    snapshot: *Snapshot,

    pub fn deinit(self: *Admission) void {
        self.snapshot.release();
        self.* = undefined;
    }
};

pub const FreshVm = struct {
    allocator: std.mem.Allocator,
    state: *forth.State,
    snapshot: *Snapshot,
    owned_storage: ?forth.Storage = null,
    initialized: bool = true,
    pending_plan: ?*Plan = null,
    execution_resources_released: bool = false,

    /// Explicit capability: caller guarantees fresh OS-zeroed Storage allocations.
    /// Generic allocators (including reuse/pooling allocators) must leave this false.
    pub const CreateOptions = struct {
        storage_zeroed: bool = false,
        retired_vm: ?*?FreshVm = null,
        control: ?@import("task_setup.zig").Control = null,
    };

    /// Takes its own reference from an already admitted version. Does not execute
    /// code: the separate allowed-set validator must approve it before execution.
    /// No host Writer/context can enter restore's apply/cleanup path here.
    pub fn create(allocator: std.mem.Allocator, admission: *const Admission) !FreshVm {
        return createWithOptions(allocator, admission, .{});
    }

    pub fn createWithOptions(allocator: std.mem.Allocator, admission: *const Admission, options: CreateOptions) !FreshVm {
        const admitted = admission.snapshot;
        try admitted.retain();
        const state_slice = blk: {
            errdefer admitted.release();
            if (options.control) |control| try control.check(.snapshot_retained);
            break :blk @import("task_storage.zig").allocateArray(forth.State, allocator, 1, options.control, .state_chunk);
        } catch |err| {
            admitted.release();
            return err;
        };
        const state = &state_slice[0];
        var owned: FreshVm = .{ .allocator = allocator, .state = state, .snapshot = admitted, .initialized = false };
        errdefer {
            if (options.retired_vm) |retired| retired.* = owned else owned.deinit();
        }
        if (options.control) |control| try control.check(.state_allocated);
        const storage = try @import("task_storage.zig").allocate(allocator, options.storage_zeroed or zeroPageAllocator(allocator), admitted.sizes, options.control, if (options.retired_vm != null) &owned.owned_storage else null);
        owned.owned_storage = storage;
        if (options.control) |control| try control.check(.storage_allocated);
        if (options.control) |control| {
            try state.initWorker(.{ .context = null, .write_fn = discard }, storage, control);
        } else state.init(.{ .context = null, .write_fn = discard }, storage);
        owned.initialized = true;
        if (options.control) |control| try control.check(.initialized);
        const plan = try allocator.create(Plan);
        owned.pending_plan = plan;
        if (options.control) |control| try control.check(.plan_allocated);
        if (options.control) |control| {
            try restore.restoreFreshWorker(state, admitted.image(), plan, control);
        } else {
            try restore.restoreFresh(state, admitted.image(), plan);
        }
        if (options.control) |control| try control.check(.restored);
        allocator.destroy(plan);
        owned.pending_plan = null;
        if (options.control) |control| try control.check(.plan_released);
        return owned;
    }

    /// Name/search order belongs to the restored version. Returned IDs are local
    /// to this VM and must never be used against the main VM.
    pub fn resolve(self: *const FreshVm, name: []const u8) error{EntryNotFound}!u16 {
        return self.state.lookup(name) orelse error.EntryNotFound;
    }

    /// End execution ownership before terminal publication. Only State/Storage
    /// remain for the independent retirement owner; snapshot may now disappear.
    pub fn releaseExecutionResources(self: *FreshVm) void {
        if (self.execution_resources_released) return;
        if (self.initialized) forth.releaseImages(self.state);
        if (self.pending_plan) |plan| self.allocator.destroy(plan);
        self.pending_plan = null;
        self.snapshot.release();
        self.execution_resources_released = true;
    }

    pub fn deinit(self: *FreshVm) void {
        self.releaseExecutionResources();
        if (self.owned_storage) |storage| storage.free(self.allocator);
        self.allocator.destroy(self.state);
        self.* = undefined;
    }
};

fn discard(_: ?*anyopaque, _: []const u8) void {}

/// Only the audited Linux/Windows page allocator; wrappers must pass capability
/// explicitly after inspecting their own backing allocator (host_task_api).
fn zeroPageAllocator(allocator: std.mem.Allocator) bool {
    const os = @import("builtin").os.tag;
    return (os == .linux or os == .windows) and allocator.vtable == std.heap.page_allocator.vtable;
}
