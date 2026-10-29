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
    b.installArtifact(exe);

    const test_module = b.createModule(.{
        .root_source_file = b.path("src/forth_test.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    const unit_tests = b.addTest(.{ .root_module = test_module });
    const run_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run FORTH/Σ core and host tests");
    test_step.dependOn(&run_tests.step);

    const host_tests = b.addTest(.{ .root_module = exe.root_module });
    test_step.dependOn(&b.addRunArtifact(host_tests).step);
}
