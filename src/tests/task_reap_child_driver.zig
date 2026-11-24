const std = @import("std");

/// Host-only driver: the tested runtime artifact is supplied by the build graph.
pub fn main(init: std.process.Init) !void {
    const allocator = std.heap.page_allocator;
    var args = try std.process.Args.Iterator.initAllocator(init.minimal.args, allocator);
    defer args.deinit();
    _ = args.next();
    const path = args.next() orelse return error.ExpectedRuntimeTestPath;
    if (args.next() != null) return error.ExpectedRuntimeTestPath;
    var env = try std.process.Environ.createMap(init.minimal.environ, allocator);
    defer env.deinit();
    try env.put("FORTHZ_1376_FATAL_CHILD", "1");
    // Zig 0.17.1 process.run spawns a process.Child, drains both pipes and waits.
    const child = try std.process.run(allocator, init.io, .{
        .argv = &.{path},
        .environ_map = &env,
        .stdout_limit = .limited(4 * 1024 * 1024),
        .stderr_limit = .limited(4 * 1024 * 1024),
    });
    defer allocator.free(child.stdout);
    defer allocator.free(child.stderr);
    switch (child.term) {
        .exited => |code| if (code != 1) return error.UnexpectedFatalExitCode,
        else => return error.UnexpectedFatalTermination,
    }
    const marker = "1376: retained runner; independent cleanup; fatal diagnostic; exit 1";
    if (std.mem.indexOf(u8, child.stdout, marker) == null) return error.MissingFatalMarker;
}
