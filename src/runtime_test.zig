//! Standalone coverage for the shared runtime, without a Forth dictionary or UI.
test {
    _ = @import("tests/runtime_base_test.zig");
    _ = @import("host_wake.zig");
    _ = @import("host_signal_broker.zig");
    _ = @import("host_runtime.zig");
}
