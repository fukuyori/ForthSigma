//! Standalone coverage for the shared runtime, without a Forth dictionary or UI.
test {
    // Queue workers and their watchdogs use host Wake; POSIX tests need c_file.
    _ = @import("tests/task_queue_test.zig");
    _ = @import("tests/task_ledger_test.zig");
    _ = @import("tests/task_paint_test.zig");
    _ = @import("tests/runtime_base_test.zig");
    _ = @import("host_wake.zig");
    _ = @import("host_signal_broker.zig");
    _ = @import("host_runtime.zig");
}
