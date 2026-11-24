//! Host/runtime coverage, including task integration with fresh Forth VMs.
test {
    _ = @import("tests/task_reap_test.zig");
    _ = @import("tests/task_reap_reproduction_host_test.zig");
    _ = @import("tests/task_cancel_queue_test.zig");
    _ = @import("tests/task_state_machine_test.zig");
    _ = @import("tests/task_wait_host_test.zig");
    _ = @import("tests/task_wait_reproduction_host_test.zig");
    // Queue workers and their watchdogs use host Wake; POSIX tests need c_file.
    _ = @import("tests/task_queue_test.zig");
    _ = @import("tests/task_schedule_host_test.zig");
    _ = @import("tests/task_ledger_test.zig");
    _ = @import("tests/task_paint_test.zig");
    _ = @import("tests/runtime_base_test.zig");
    _ = @import("host_wake.zig");
    _ = @import("host_signal_broker.zig");
    _ = @import("host_runtime.zig");
}
