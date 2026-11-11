const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    // Release builds for distribution leave out debug information unless -Dstrip=false.
    const strip = b.option(bool, "strip", "Omit debug information (default: on for fast and small)") orelse
        (optimize == .fast or optimize == .small);
    // -Dfloat=false leaves out the floating-point words and CORE-MATH, for a smaller program.
    const float = b.option(bool, "float", "Include the floating-point words (default: on)") orelse true;
    // The other word groups can be left out the same way, for a smaller program.
    const files = b.option(bool, "files", "Include the words that open, read, write, and include files (default: on)") orelse true;
    const help = b.option(bool, "help", "Include HELP, LICENSE, and their texts (default: on)") orelse true;
    const tools = b.option(bool, "tools", "Include SEE, LOCATE, and WHERE (default: on)") orelse true;
    const image = b.option(bool, "image", "Include SAVE, LOAD, and SAVESYS (default: on)") orelse true;
    const graphics = b.option(bool, "graphics", "Include REQUIRE-GRAPHICS and the GFX- words (default: on)") orelse true;
    const audio = b.option(bool, "audio", "Include REQUIRE-AUDIO and the SND- words (default: on)") orelse true;
    const debug = b.option(bool, "debug", "Include the debugging features: the backtrace after an error, --max-steps, --trace, --profile, --debug-log, and the debugging words (DBG, BREAK:, ~~BT and others) (default: on)") orelse true;
    const options = b.addOptions();
    options.addOption(bool, "float", float);
    options.addOption(bool, "files", files);
    options.addOption(bool, "help", help);
    options.addOption(bool, "tools", tools);
    options.addOption(bool, "image", image);
    options.addOption(bool, "graphics", graphics);
    options.addOption(bool, "audio", audio);
    options.addOption(bool, "debug", debug);
    options.addOption(usize, "memory_mib", b.option(usize, "memory-mib", "The default size of the data area, and of the heap, in MiB (default: 32)") orelse 32);
    options.addOption(usize, "locals_kib", b.option(usize, "locals-kib", "The default size of the area for local variables, in KiB (default: 64)") orelse 64);
    options.addOption(usize, "stack_cells", b.option(usize, "stack-cells", "The default size of each stack, in elements (default: 4096)") orelse 4096);
    options.addOption(usize, "max_words", b.option(usize, "words", "The number of dictionary entries, at most 65535 (default: 65535)") orelse 65535);
    options.addOption(usize, "names_kib", b.option(usize, "names-kib", "The size of the area for the names of the dictionary entries, in KiB (default: 1024)") orelse 1024);

    const exe = b.addExecutable(.{
        .name = "sigma",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .strip = strip,
        }),
    });
    exe.root_module.addOptions("build_options", options);
    if (float) addCoreMath(b, exe.root_module);
    addEmbeddedTexts(b, exe.root_module);
    addCTime(b, exe.root_module, target, optimize);
    // Each function and constant in its own section, so that the linker drops the ones
    // nothing calls, also from the C files.
    exe.link_function_sections = true;
    exe.link_data_sections = true;
    exe.link_gc_sections = true;
    b.installArtifact(exe);
    // The program's license and the third-party notices go with every build output.
    b.installFile("LICENSE", "LICENSE");
    b.installFile("THIRD_PARTY_NOTICES.md", "THIRD_PARTY_NOTICES.md");

    const test_module = b.createModule(.{
        .root_source_file = b.path("src/forth_test.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    test_module.addOptions("build_options", options);
    addEmbeddedTexts(b, test_module);
    if (float) {
        addCoreMath(b, test_module);
        test_module.addCSourceFile(.{
            .file = b.path("src/fma/fma_for_tests.c"),
            .flags = &.{ "-std=gnu11", "-include", fmaHeader(b) },
        });
    }
    const unit_tests = b.addTest(.{ .root_module = test_module });
    const run_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run FORTH/Σ core and host tests");
    test_step.dependOn(&run_tests.step);

    const host_tests = b.addTest(.{ .root_module = exe.root_module });
    test_step.dependOn(&b.addRunArtifact(host_tests).step);

    // The core compiled for a Cortex-M0+ with no operating system: it fails to build
    // when forth.zig or src/core starts to use an OS service. The test step includes it.
    const freestanding_module = b.createModule(.{
        .root_source_file = b.path("src/freestanding_check.zig"),
        .target = b.resolveTargetQuery(.{
            .cpu_arch = .thumb,
            .os_tag = .freestanding,
            .abi = .eabi,
            .cpu_model = .{ .explicit = &std.Target.arm.cpu.cortex_m0plus },
        }),
        .optimize = .ReleaseSmall,
    });
    freestanding_module.addOptions("build_options", options);
    addEmbeddedTexts(b, freestanding_module);
    const freestanding = b.addObject(.{ .name = "sigma-freestanding", .root_module = freestanding_module });
    const freestanding_step = b.step("freestanding", "Compile the core for a Cortex-M0+ with no OS");
    freestanding_step.dependOn(&freestanding.step);
    test_step.dependOn(&freestanding.step);

    // The executable itself reading a real pipe: READ-FILE gets the bytes unchanged (on
    // Windows the C library would turn CR LF into LF and stop at Ctrl+Z), and READ-LINE
    // still ends lines at CR LF.
    if (!files) return;
    const pipe_bytes = b.addRunArtifact(exe);
    pipe_bytes.addArgs(&.{ "-e", ": T PAD 9 STDIN READ-FILE . DUP . 0 DO PAD I + C@ . LOOP ; T BYE" });
    pipe_bytes.setStdIn(.{ .bytes = "A\r\nB\x1aC\x00\xff" });
    pipe_bytes.expectStdOutEqual("0 8 65 13 10 66 26 67 0 255 ");
    test_step.dependOn(&pipe_bytes.step);
    const pipe_lines = b.addRunArtifact(exe);
    pipe_lines.addArgs(&.{ "-e", "PAD 20 STDIN READ-LINE . . PAD SWAP TYPE PAD 20 STDIN READ-LINE . . PAD SWAP TYPE BYE" });
    pipe_lines.setStdIn(.{ .bytes = "ab\r\ncd\n" });
    pipe_lines.expectStdOutEqual("0 -1 ab0 -1 cd");
    test_step.dependOn(&pipe_lines.step);

    // The command line as in gforth: a file to include, then `-e`, with the stack kept
    // between arguments; a missing `-e` argument or file ends the program with status 1.
    const argument_file = b.addRunArtifact(exe);
    argument_file.addFileArg(b.path("src/tests/argument_file.fs"));
    argument_file.addArgs(&.{ "-e", ". BYE" });
    argument_file.expectStdOutEqual("ARG-FILE5 ");
    test_step.dependOn(&argument_file.step);
    const argument_stack = b.addRunArtifact(exe);
    argument_stack.addArgs(&.{ "-e", "7", "--evaluate", ". BYE" });
    argument_stack.expectStdOutEqual("7 ");
    test_step.dependOn(&argument_stack.step);
    const argument_missing = b.addRunArtifact(exe);
    argument_missing.addArg("-e");
    // The terminal output ends lines with CR LF on Windows.
    const missing_message = "-e: OPTION REQUIRES AN ARGUMENT !";
    argument_missing.expectStdOutEqual(if (target.result.os.tag == .windows) missing_message ++ "\r\n" else missing_message ++ "\n");
    argument_missing.expectExitCode(1);
    test_step.dependOn(&argument_missing.step);
    // A byte XKEY reads that does not continue the character comes first to the next
    // read of the input, by ACCEPT, READ-LINE, or INKEY as by KEY.
    const xkey_accept = b.addRunArtifact(exe);
    xkey_accept.addArgs(&.{ "-e", "XKEY . PAD 10 ACCEPT PAD SWAP TYPE SPACE KEY . BYE" });
    xkey_accept.setStdIn(.{ .bytes = "\xE6A\nrest\n" });
    xkey_accept.expectStdOutEqual("65533 A 114 ");
    test_step.dependOn(&xkey_accept.step);
    const xkey_read_line = b.addRunArtifact(exe);
    xkey_read_line.addArgs(&.{ "-e", "XKEY . PAD 10 STDIN READ-LINE . . PAD SWAP TYPE BYE" });
    xkey_read_line.setStdIn(.{ .bytes = "\xE6Ab\ncd\n" });
    xkey_read_line.expectStdOutEqual("65533 0 -1 Ab");
    test_step.dependOn(&xkey_read_line.step);
    if (graphics) {
        const xkey_inkey = b.addRunArtifact(exe);
        xkey_inkey.addArgs(&.{ "-e", "REQUIRE-GRAPHICS ALSO GRAPHICS XKEY . INKEY . INKEY . BYE" });
        xkey_inkey.setStdIn(.{ .bytes = "\xE6AB" });
        // INKEY reads a pipe only for the byte read ahead, so B is not a key to it.
        xkey_inkey.expectStdOutEqual("65533 65 -1 ");
        test_step.dependOn(&xkey_inkey.step);
    }
    const argument_no_file = b.addRunArtifact(exe);
    argument_no_file.addArgs(&.{ "sigma-no-such-file.fs", "-e", "BYE" });
    argument_no_file.expectExitCode(1);
    test_step.dependOn(&argument_no_file.step);
}

/// The correctly rounded math functions the core calls for FSIN, FEXP, FASIN, F**, and
/// the other floating-point functions. Each newer function keeps CORE-MATH's folder, since
/// their helper headers share names but differ.
fn addCoreMath(b: *std.Build, module: *std.Build.Module) void {
    module.addCSourceFiles(.{
        .root = b.path("src/core-math"),
        .files = &.{
            "sin.c",         "cos.c",         "tan.c",         "exp.c",         "log.c",
            "asin/asin.c",   "acos/acos.c",   "atan/atan.c",   "atan2/atan2.c", "sinh/sinh.c",
            "cosh/cosh.c",   "tanh/tanh.c",   "asinh/asinh.c", "acosh/acosh.c", "atanh/atanh.c",
            "expm1/expm1.c", "log1p/log1p.c", "log10/log10.c", "exp10/exp10.c", "pow/pow.c",
        },
        // On a baseline CPU __builtin_roundeven becomes a call that musl and macOS lack;
        // rint gives the same result in the round-to-nearest mode Forth always runs in.
        // sigma_fma.h sends __builtin_fma to musl's fma when the CPU has no FMA
        // instruction, since the C library's fma on Windows is wrong for tiny products.
        .flags = &.{ "-std=gnu11", "-D__builtin_roundeven=__builtin_rint", "-include", fmaHeader(b) },
    });
    module.addCSourceFiles(.{
        .root = b.path("src/fma"),
        .files = &.{"fma.c"},
        .flags = &.{ "-std=gnu11", "-Dfma=sigma_fma_software", "-Wno-shift-op-parentheses" },
    });
}

/// The version and the license texts that the banner, HELP, and LICENSE show.
fn addEmbeddedTexts(b: *std.Build, module: *std.Build.Module) void {
    module.addAnonymousImport("version", .{ .root_source_file = b.path("VERSION") });
    module.addAnonymousImport("license", .{ .root_source_file = b.path("LICENSE") });
    module.addAnonymousImport("third_party_notices", .{ .root_source_file = b.path("THIRD_PARTY_NOTICES.md") });
}

/// The full path of the header that `-include` puts before each math source file.
fn fmaHeader(b: *std.Build) []const u8 {
    return b.root.joinString(b.allocator, "src/fma/sigma_fma.h") catch @panic("OOM");
}

/// The C library's time.h as the module `c_time`, so that time_t and the names of time
/// and localtime are the ones each target uses (32-bit musl and Windows rename them).
fn addCTime(b: *std.Build, module: *std.Build.Module, target: std.Build.ResolvedTarget, optimize: std.builtin.Optimize) void {
    const c_time = b.addTranslateC(.{
        .root_source_file = b.addWriteFiles().add("c_time.h", "#include <time.h>\n"),
        .target = target,
        .optimize = optimize,
    });
    module.addImport("c_time", c_time.createModule());
}
