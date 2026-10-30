//! Root of the core test suite: each file under tests/ holds the tests of one subject.

comptime {
    _ = @import("tests/core_words_test.zig");
    _ = @import("tests/float_test.zig");
    _ = @import("tests/text_and_numbers_test.zig");
    _ = @import("tests/host_words_test.zig");
    _ = @import("tests/files_and_heap_test.zig");
    _ = @import("tests/locals_test.zig");
    _ = @import("tests/catch_test.zig");
    _ = @import("tests/source_and_see_test.zig");
    _ = @import("tests/wordlists_test.zig");
    _ = @import("tests/definitions_test.zig");
    _ = @import("tests/help_test.zig");
}
