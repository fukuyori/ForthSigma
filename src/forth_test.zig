//! Root of the core test suite: each file under tests/ holds the tests of one subject.

comptime {
    _ = @import("tests/core_words_test.zig");
    // The floating-point tests need the floating-point words (not in -Dfloat=false).
    if (@import("build_options").float) _ = @import("tests/float_test.zig");
    _ = @import("tests/text_and_numbers_test.zig");
    _ = @import("tests/host_words_test.zig");
    _ = @import("tests/xchar_test.zig");
    _ = @import("tests/files_and_heap_test.zig");
    _ = @import("tests/locals_test.zig");
    _ = @import("tests/catch_test.zig");
    _ = @import("tests/source_and_see_test.zig");
    _ = @import("tests/wordlists_test.zig");
    _ = @import("tests/definitions_test.zig");
    _ = @import("tests/help_test.zig");
    _ = @import("tests/dictionary_test.zig");
    _ = @import("tests/inline_calls_test.zig");
    _ = @import("tests/graphics_test.zig");
    _ = @import("tests/library_loading_test.zig");
    _ = @import("tests/graphics_images_test.zig");
    _ = @import("tests/load_image_test.zig");
    _ = @import("tests/gui_test.zig");
    _ = @import("tests/game_test.zig");
    _ = @import("tests/gamepad_test.zig");
    _ = @import("tests/sound_test.zig");
    _ = @import("tests/audio_test.zig");
    _ = @import("tests/gforth_rest_test.zig");
    _ = @import("tests/debug_test.zig");
}
