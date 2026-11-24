//! Owned task completion bytes. Move-only by convention; externally serialized.
//! Seal before release/acquire publication; keep alive through all readers.
const std = @import("std");
const transfer = @import("task_transfer.zig");
const forth = @import("../forth.zig");
pub const result_limit = transfer.default_result_limit;
pub const diagnostic_limit = 16 * 1024;
pub const diagnostic_total_limit = 1024 * 1024;

/// Counts live payload allocations, including concurrently retained copies.
/// Host-thread-only: all reservation, allocation and destruction run on the owning host.
/// Workers must never call Budget or allocator operations. Never copy a live Budget.
pub const Budget = struct {
    used: usize = 0,
    limit: usize,
    pub fn reserve(self: *Budget, size: usize) error{TotalLimitExceeded}!void {
        if (size > self.limit - self.used) return error.TotalLimitExceeded;
        self.used += size;
    }
    pub fn release(self: *Budget, size: usize) void {
        if (size > self.used) @panic("task Budget release exceeds reservation");
        self.used -= size;
    }
};
pub const Budgets = struct {
    transfer: Budget = .{ .limit = transfer.transfer_total_limit },
    diagnostic: Budget = .{ .limit = diagnostic_total_limit },
};
pub const Read = struct { required: usize, copied: bool };
fn read(bytes: []const u8, destination: []u8) Read {
    if (destination.len < bytes.len) return .{ .required = bytes.len, .copied = false };
    @memcpy(destination[0..bytes.len], bytes);
    return .{ .required = bytes.len, .copied = true };
}

/// Owns both allocation and reservation. No borrowed VM pointers survive copying.
pub const Buffer = struct {
    allocator: std.mem.Allocator,
    budget: *Budget,
    bytes: []u8,
    /// Full allocation/reservation when bytes exposes only its initialized prefix.
    allocation: ?[]u8 = null,
    pub fn copy(allocator: std.mem.Allocator, budget: *Budget, bytes: []const u8, limit: usize) !Buffer {
        if (bytes.len > limit) return error.ItemLimitExceeded;
        try budget.reserve(bytes.len);
        errdefer budget.release(bytes.len);
        return .{ .allocator = allocator, .budget = budget, .bytes = try allocator.dupe(u8, bytes) };
    }
    /// Validate once, then reserve and copy; roll back on allocation failure.
    pub fn copyResult(vm: *const forth.State, allocator: std.mem.Allocator, budget: *Budget, limits: transfer.Limits) !Buffer {
        const bytes = try transfer.resultBytes(vm, limits);
        try budget.reserve(bytes.len);
        errdefer budget.release(bytes.len);
        return .{ .allocator = allocator, .budget = budget, .bytes = try allocator.dupe(u8, bytes) };
    }
    pub fn query(self: *const Buffer, destination: []u8) Read {
        return read(self.bytes, destination);
    }
    pub fn deinit(self: *Buffer) void {
        const allocation = self.allocation orelse self.bytes;
        self.budget.release(allocation.len);
        self.allocator.free(allocation);
        self.* = undefined;
    }
};
pub const Terminal = enum { succeeded, failed, cancelled };
pub const DiagnosticCode = enum { execution, cancelled, writer_overflow, cleanup };
/// Text is optional so even allocation/budget exhaustion retains a typed cause.
pub const Diagnostic = struct {
    code: DiagnosticCode,
    text: ?Buffer = null,
    pub fn copy(allocator: std.mem.Allocator, budget: *Budget, code: DiagnosticCode, bytes: []const u8) !Diagnostic {
        return .{ .code = code, .text = try Buffer.copy(allocator, budget, bytes, diagnostic_limit) };
    }
};

pub const Completion = struct {
    terminal: Terminal,
    result: ?Buffer,
    primary: ?Diagnostic,
    secondary: ?Diagnostic,
    output: ?Buffer = null,
    writer_failure: ?Diagnostic = null,
    /// Consumes supplied buffers. Failure/cancellation discard every partial result.
    /// Primary is the execution cause; secondary is output/cleanup failure.
    pub fn init(terminal: Terminal, result: ?Buffer, primary: ?Diagnostic, secondary: ?Diagnostic) Completion {
        var completion: Completion = .{ .terminal = terminal, .result = result, .primary = primary, .secondary = secondary };
        if (terminal != .succeeded) {
            if (completion.result) |*buffer| buffer.deinit();
            completion.result = null;
        }
        return completion;
    }
    pub fn queryResult(self: *const Completion, destination: []u8) ?Read {
        return if (self.result) |*buffer| buffer.query(destination) else null;
    }
    pub fn deinit(self: *Completion) void {
        if (self.result) |*buffer| buffer.deinit();
        if (self.output) |*buffer| buffer.deinit();
        if (self.writer_failure) |*diagnostic| if (diagnostic.text) |*buffer| buffer.deinit();
        if (self.primary) |*diagnostic| if (diagnostic.text) |*buffer| buffer.deinit();
        if (self.secondary) |*diagnostic| if (diagnostic.text) |*buffer| buffer.deinit();
        self.* = undefined;
    }
};

/// Host calls init before dispatch and finish/deinit only after exclusive handback
/// (join or equivalent synchronization). Stable address while installed in State.
/// Only write runs on the worker; it never allocates or touches the shared Budget.
pub const WorkerOutput = struct {
    buffer: ?Buffer,
    used: usize = 0,
    failure: ?DiagnosticCode = null,
    sealed: bool = false,

    pub fn init(allocator: std.mem.Allocator, budget: *Budget) !WorkerOutput {
        try budget.reserve(diagnostic_limit);
        errdefer budget.release(diagnostic_limit);
        return .{ .buffer = .{ .allocator = allocator, .budget = budget, .bytes = try allocator.alloc(u8, diagnostic_limit) } };
    }
    pub fn writer(self: *WorkerOutput) forth.Writer {
        return .{ .context = self, .write_fn = write };
    }
    fn write(context: ?*anyopaque, bytes: []const u8) void {
        const self: *WorkerOutput = @ptrCast(@alignCast(context.?));
        if (self.sealed) @panic("task Writer used after handback");
        if (self.failure != null) return;
        if (bytes.len > diagnostic_limit - self.used) {
            self.failure = .writer_overflow;
            return;
        }
        @memcpy(self.buffer.?.bytes[self.used..][0..bytes.len], bytes);
        self.used += bytes.len;
    }
    /// Host-only; consumes supplied buffers and transfers the reserved allocation.
    /// Primary execution cause, Writer failure and caller cleanup diagnostic coexist.
    pub fn finish(self: *WorkerOutput, terminal: Terminal, result: ?Buffer, primary: ?Diagnostic, secondary: ?Diagnostic) Completion {
        if (self.sealed) @panic("task Writer finished twice");
        self.sealed = true;
        var output = self.buffer.?;
        self.buffer = null;
        output.allocation = output.bytes;
        output.bytes = output.bytes[0..self.used];
        var completion = Completion.init(if (self.failure != null and terminal == .succeeded) .failed else terminal, result, primary, secondary);
        completion.output = output;
        if (self.failure) |code| {
            if (completion.primary == null) {
                completion.primary = .{ .code = code };
            } else {
                completion.writer_failure = .{ .code = code };
            }
        }
        return completion;
    }
    pub fn deinit(self: *WorkerOutput) void {
        if (self.buffer) |*buffer| buffer.deinit();
        self.* = undefined;
    }
};
