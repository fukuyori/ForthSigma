//! Root of the core test suite: each file under tests/ holds the tests of one subject.

comptime {
    _ = @import("tests/image_format_test.zig");
    _ = @import("tests/p01c_test.zig");
    _ = @import("tests/p02a_test.zig");
    _ = @import("tests/p02b_test.zig");
    _ = @import("tests/p02c_test.zig");
    _ = @import("tests/p03a_test.zig");
    _ = @import("tests/p03b_data_test.zig");
    _ = @import("tests/p03b_address_test.zig");
    _ = @import("tests/p03c_test.zig");
    _ = @import("tests/p03_review_test.zig");
    _ = @import("tests/p04a_basic_test.zig");
    _ = @import("tests/p04a_edit_test.zig");
    _ = @import("tests/p04a_xc_test.zig");
    _ = @import("tests/p04b_values_test.zig");
    _ = @import("tests/p04b_macros_test.zig");
    _ = @import("tests/p04_review_test.zig");
    _ = @import("tests/p05a_stream_test.zig");
    _ = @import("tests/p05a_input_test.zig");
    _ = @import("tests/p05a_misc_test.zig");
    _ = @import("tests/p05a_path_test.zig");
    _ = @import("tests/p05a_search_test.zig");
    _ = @import("tests/p05b_path_parts_test.zig");
    _ = @import("tests/p05b_filename_match_test.zig");
    _ = @import("tests/p05b_cwd_test.zig");
    _ = @import("tests/p05b_mkdir_test.zig");
    _ = @import("tests/p01b_test.zig");
    _ = @import("tests/p01a_test.zig");
    _ = @import("core/blocks.zig");
    _ = @import("tests/blocks_test.zig");
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
    _ = @import("tests/debug_words_test.zig");
    _ = @import("tests/debug_step_test.zig");
    _ = @import("tests/debug_log_test.zig");
    _ = @import("core/lint.zig");
    _ = @import("tests/lint_test.zig");
}

comptime {
    _ = @import("tests/image_graph_test.zig");
    _ = @import("tests/image_encoder_test.zig");
    _ = @import("tests/image_restore_plan_test.zig");
    _ = @import("tests/image_restore_typed_test.zig");
    _ = @import("tests/image_append_plan_test.zig");
    _ = @import("tests/image_append_typed_test.zig");
    _ = @import("tests/internal_pointer_test.zig");
}
