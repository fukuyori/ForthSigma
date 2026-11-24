const std = @import("std");
const t = std.testing;
const ledger = @import("../core/task_ledger.zig");
const base = @import("../core/runtime_base.zig");

fn running(l: anytype, owner: u64) !base.Handle {
    const id = try l.register(owner);
    try l.publish(id, owner);
    try l.start(id, owner);
    return id;
}

test "ledger capacity includes released running and unreclaimed terminal records" {
    var l = try ledger.LedgerWithConcurrency(2, 2).init(1);
    const a = try running(&l, 1);
    try l.release(a, 1);
    const b = try running(&l, 1);
    _ = try l.finish(b, 1, .failed);
    try t.expectError(error.ResourceFull, l.register(1));
    try t.expectEqual(@as(usize, 2), l.count());
    try t.expectError(error.ReferencesRemain, l.collect(a, 1));
    try t.expectError(error.ReferencesRemain, l.collect(b, 1));
    try l.release(b, 1);
    try l.executionStopped(b, 1);
    _ = try l.collect(b, 1);
    _ = try l.register(1);
}

test "ledger identity validation follows ResourceTable order and never wraps" {
    var l = try ledger.Ledger(2).init(7);
    l.table_for_testing.next_serial = std.math.maxInt(u64);
    const a = try l.register(1);
    try t.expectError(error.InvalidHandle, l.lookup(a, 1)); // created is private
    try l.publish(a, 1);
    try t.expectError(error.WrongOwner, l.lookup(a, 2));
    try t.expectError(error.InvalidHandle, l.lookup(.{ .epoch = 6, .serial = a.serial }, 2));
    try t.expectError(error.InvalidHandle, l.lookup(.{ .epoch = 7, .serial = 0 }, 1));
    try t.expectError(error.IdentityExhausted, l.register(1));
    try l.release(a, 1);
    _ = try l.finish(a, 1, .cancelled);
    _ = try l.collect(a, 1);
    try t.expectError(error.InvalidHandle, l.lookup(a, 1));
    try t.expectError(error.IdentityExhausted, l.register(1));
    var mixed = try ledger.Ledger(2).init(8);
    const other = try mixed.table_for_testing.insert(1, .process, .{});
    try t.expectError(error.WrongKind, mixed.lookup(other, 2));
}

test "ledger terminal is immutable and cancellation is independent of outcome" {
    var l = try ledger.DefaultLedger.init(1);
    const a = try running(&l, 1);
    try l.cancel(a, 1);
    try l.cancel(a, 1);
    try t.expect(try l.finish(a, 1, .succeeded));
    try t.expect(!try l.finish(a, 1, .succeeded));
    try t.expectError(error.ConflictingTerminal, l.finish(a, 1, .cancelled));
    try t.expectError(error.InvalidTransition, l.finish(a, 1, .running));
    try t.expect((try l.lookup(a, 1)).cancel_requested);
    try l.executionStopped(a, 1);
    const b = try running(&l, 1);
    _ = try l.finish(b, 1, .failed);
    try l.cancel(b, 1);
    try t.expect(!(try l.lookup(b, 1)).cancel_requested);
}

test "ledger RELEASE rejects external operations but preserves internal completion and refs" {
    var l = try ledger.DefaultLedger.init(1);
    const a = try running(&l, 1);
    try l.retain(a, 1);
    try l.release(a, 1);
    try t.expectError(error.InvalidHandle, l.lookup(a, 1));
    try t.expectError(error.InvalidHandle, l.cancel(a, 1));
    try t.expectError(error.InvalidHandle, l.release(a, 1));
    try t.expect((try l.inspect(a, 1)).execution_ref);
    try t.expectError(error.InvalidTransition, l.executionStopped(a, 1));
    _ = try l.finish(a, 1, .cancelled);
    try t.expectError(error.ReferencesRemain, l.collect(a, 1));
    try l.executionStopped(a, 1);
    try t.expectError(error.ReferencesRemain, l.collect(a, 1));
    try l.drop(a, 1);
    try t.expectError(error.InvalidTransition, l.drop(a, 1));
    _ = try l.collect(a, 1);
    const b = try l.register(1);
    try t.expect(a.serial != b.serial);
    try t.expectError(error.InvalidHandle, l.inspect(a, 1));
    _ = try l.collect(b, 1); // created rollback
}

test "ledger owner ending retains released and stopped-unconfirmed work" {
    var l = try ledger.DefaultLedger.init(1);
    const a = try running(&l, 1);
    try l.release(a, 1);
    const b = try l.register(1);
    try l.publish(b, 1);
    const c = try l.register(2);
    try l.publish(c, 2);
    try t.expectEqual(@as(usize, 2), try l.endOwner(1));
    try t.expectError(error.InvalidHandle, l.lookup(b, 1));
    _ = try l.lookup(c, 2);
    try l.markStopUnconfirmed(a, 1);
    const waiting = try l.register(2);
    _ = try l.collect(waiting, 2);
    try t.expectError(error.WorkerOccupied, l.start(c, 2));
    try t.expectEqual(ledger.State.running, (try l.inspect(a, 1)).state);
    _ = try l.finish(b, 1, .cancelled); // exclusive queue removal supplied by host
    _ = try l.collect(b, 1);
    _ = try l.finish(a, 1, .succeeded);
    try t.expectError(error.WorkerOccupied, l.checkWorkerAvailable());
    try l.executionStopped(a, 1);
    _ = try l.collect(a, 1);
    try l.checkWorkerAvailable();
    try t.expectEqual(@as(usize, 1), l.count());
}

test "default ledger has exactly sixteen slots including private reservations" {
    var l = try ledger.DefaultLedger.init(1);
    var ids: [16]base.Handle = undefined;
    for (&ids) |*id| id.* = try l.register(1);
    try t.expectError(error.ResourceFull, l.register(1));
    for (ids) |id| _ = try l.collect(id, 1);
    try t.expectEqual(@as(usize, 0), l.count());
    try t.expectError(error.InvalidHandle, ledger.DefaultLedger.init(0));
    try t.expectError(error.WrongOwner, l.register(0));
}

test "owner ending preserves terminal state and created rollback with outstanding refs" {
    var l = try ledger.DefaultLedger.init(1);
    const a = try running(&l, 1);
    _ = try l.finish(a, 1, .succeeded);
    try l.executionStopped(a, 1);
    const b = try l.register(1);
    try l.retain(b, 1);
    try t.expectEqual(@as(usize, 2), try l.endOwner(1));
    const terminal = try l.inspect(a, 1);
    try t.expectEqual(ledger.State.succeeded, terminal.state);
    try t.expect(!terminal.cancel_requested);
    _ = try l.collect(a, 1);
    try t.expectError(error.ReferencesRemain, l.collect(b, 1));
    try l.drop(b, 1);
    _ = try l.collect(b, 1);
    try t.expectEqual(@as(usize, 0), try l.endOwner(1));
    try t.expectError(error.WrongOwner, l.endOwner(0));
}

test "ledger rejects invalid transitions without changing records" {
    var l = try ledger.DefaultLedger.init(1);
    const a = try l.register(1);
    for ([_]ledger.State{ .succeeded, .failed, .cancelled }) |outcome|
        try t.expectError(error.InvalidTransition, l.finish(a, 1, outcome));
    try t.expectError(error.InvalidTransition, l.start(a, 1));
    try t.expectError(error.InvalidTransition, l.markStopUnconfirmed(a, 1));
    try t.expectError(error.InvalidTransition, l.failQueued(a, 1, .queue_expired));
    try l.publish(a, 1);
    try t.expectError(error.InvalidTransition, l.publish(a, 1));
    for ([_]ledger.State{ .succeeded, .failed, .cancelled }) |outcome|
        try t.expectError(error.InvalidTransition, l.finish(a, 1, outcome));
    try t.expectEqual(ledger.State.queued, (try l.inspect(a, 1)).state);
    try t.expectError(error.InvalidTransition, l.markStopUnconfirmed(a, 1));
    try l.release(a, 1);
    try t.expectError(error.InvalidTransition, l.collect(a, 1));
    try l.start(a, 1);
    try t.expectError(error.InvalidTransition, l.start(a, 1));
    try t.expectError(error.InvalidTransition, l.publish(a, 1));
    // Fault injection: even a running record with no remaining references cannot collect.
    (try l.table_for_testing.get(a, 1, .task)).execution_ref = false;
    try t.expectError(error.InvalidTransition, l.collect(a, 1));
    try t.expectError(error.InvalidTransition, l.markStopUnconfirmed(a, 1));
    _ = try l.finish(a, 1, .cancelled);
    try t.expectError(error.InvalidTransition, l.start(a, 1));
    try t.expectError(error.InvalidTransition, l.markStopUnconfirmed(a, 1));
    _ = try l.collect(a, 1);
}

test "ledger queued failure is separate from cancellation and execution completion" {
    var l = try ledger.DefaultLedger.init(1);
    for ([_]ledger.DefaultLedger.QueueFailure{ .queue_expired, .clock_failed }) |reason| {
        const a = try l.register(1);
        try l.publish(a, 1);
        try t.expect(try l.failQueued(a, 1, reason));
        try t.expect(!try l.failQueued(a, 1, reason));
        try t.expect(!try l.finish(a, 1, .failed));
        try t.expectError(error.ConflictingTerminal, l.finish(a, 1, .cancelled));
        const r = try l.inspect(a, 1);
        try t.expectEqual(ledger.State.failed, r.state);
        try t.expect(!r.cancel_requested and !r.execution_ref);
    }
    const b = try running(&l, 1);
    try t.expectError(error.InvalidTransition, l.failQueued(b, 1, .queue_expired));
    _ = try l.finish(b, 1, .succeeded);
    try t.expectError(error.ConflictingTerminal, l.failQueued(b, 1, .queue_expired));
    try l.executionStopped(b, 1);
    const c = try l.register(1);
    try l.publish(c, 1);
    try l.cancel(c, 1);
    try t.expect(try l.finish(c, 1, .cancelled));
}

test "ledger execution slots remain occupied until physical stop and submissions stay open" {
    var l = try ledger.DefaultLedger.init(1);
    const a = try running(&l, 1);
    const b = try l.register(1);
    try l.publish(b, 1);
    try t.expectError(error.WorkerOccupied, l.start(b, 1));
    try t.expect(!(try l.inspect(b, 1)).execution_ref);
    _ = try l.finish(a, 1, .succeeded);
    try t.expectError(error.WorkerOccupied, l.start(b, 1));
    try l.markStopUnconfirmed(a, 1);
    const c = try l.register(1);
    try l.publish(c, 1);
    _ = try l.failQueued(c, 1, .queue_expired);
    try t.expectError(error.WorkerOccupied, l.start(b, 1));
    try l.executionStopped(a, 1);
    try l.start(b, 1);

    var two = try ledger.LedgerWithConcurrency(4, 2).init(2);
    const x = try running(&two, 1);
    _ = try running(&two, 1);
    const z = try two.register(1);
    try two.publish(z, 1);
    try t.expectError(error.WorkerOccupied, two.start(z, 1));
    _ = try two.finish(x, 1, .failed);
    try two.executionStopped(x, 1);
    try two.start(z, 1);
}

test "sixteen slots count mixed states and released running records" {
    var l = try ledger.LedgerWithConcurrency(16, 2).init(1);
    const terminal = try running(&l, 1);
    _ = try l.finish(terminal, 1, .succeeded);
    try l.executionStopped(terminal, 1);
    _ = try running(&l, 1);
    const released = try running(&l, 1);
    try l.release(released, 1);
    for (0..13) |i| {
        const id = try l.register(1);
        if (i % 2 == 0) try l.publish(id, 1);
    }
    try t.expectEqual(@as(usize, 16), l.count());
    try t.expectError(error.ResourceFull, l.register(1));
    try l.release(terminal, 1);
    _ = try l.collect(terminal, 1);
    try t.expectEqual(@as(usize, 15), l.count());
    _ = try l.register(1);
    try t.expectEqual(@as(usize, 16), l.count());
    try t.expectError(error.ResourceFull, l.register(1));
}
