const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "sigma",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    addCoreMath(b, exe.root_module);
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
    addCoreMath(b, test_module);
    const unit_tests = b.addTest(.{ .root_module = test_module });
    const run_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run FORTH/Σ core and host tests");
    test_step.dependOn(&run_tests.step);

    const host_tests = b.addTest(.{ .root_module = exe.root_module });
    test_step.dependOn(&b.addRunArtifact(host_tests).step);
}

/// The correctly rounded math functions the core calls for FSIN, FCOS, FTAN, FEXP, and FLN.
fn addCoreMath(b: *std.Build, module: *std.Build.Module) void {
    module.addCSourceFiles(.{
        .root = b.path("src/core-math"),
        .files = &.{ "sin.c", "cos.c", "tan.c", "exp.c", "log.c" },
        // On a baseline CPU __builtin_roundeven becomes a call that musl and macOS lack;
        // rint gives the same result in the round-to-nearest mode Forth always runs in.
        .flags = &.{ "-std=gnu11", "-D__builtin_roundeven=__builtin_rint" },
    });
}
