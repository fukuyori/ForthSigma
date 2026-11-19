//! Parent-side preparation. All allocations and path resolution happen before
//! native creation; POSIX child branches must not call these routines.
const std = @import("std");
const builtin = @import("builtin");
const table = @import("host_process_table.zig");
const Allocator = std.mem.Allocator;
const Environment = std.process.Environ.Map;
pub const quoteWindows = @import("host_process_quote.zig").encode;
pub const Error = error{ InvalidText, NotFound, AccessDenied, BadExecutable, Io, OutOfMemory };
pub const ProbeResult = enum { missing, denied, executable, invalid_format };
pub const Probe = struct {
    context: ?*anyopaque,
    check: *const fn (?*anyopaque, []const u8) Error!ProbeResult,
};
pub fn environment(allocator: Allocator, inherited: *const Environment, config: *const table.Config) Allocator.Error!Environment {
    var result = try inherited.clone(allocator);
    errdefer result.deinit();
    for (config.environment.items) |edit| {
        if (std.mem.indexOfScalar(u8, edit, '=')) |separator| {
            try result.put(edit[0..separator], edit[separator + 1 ..]);
        } else _ = result.orderedRemove(edit);
    }
    return result;
}

fn isScript(program: []const u8) bool {
    if (builtin.os.tag != .windows) return false;
    const extension = std.fs.path.extension(program);
    return std.ascii.eqlIgnoreCase(extension, ".bat") or std.ascii.eqlIgnoreCase(extension, ".cmd");
}
fn hasSeparator(program: []const u8) bool {
    return std.mem.indexOfScalar(u8, program, '/') != null or
        (builtin.os.tag == .windows and std.mem.findAny(u8, program, "\\:") != null);
}
fn validateWindowsPath(path: []const u8) Error!void {
    if (builtin.os.tag != .windows) return;
    var prefix: [4]u8 = @splat(0);
    for (path[0..@min(path.len, prefix.len)], 0..) |byte, index| prefix[index] = if (byte == '/') '\\' else byte;
    if (std.mem.eql(u8, &prefix, "\\\\?\\") or std.mem.eql(u8, &prefix, "\\\\.\\") or std.mem.eql(u8, &prefix, "\\??\\")) return error.InvalidText;
    if (prefix[0] == '\\' and prefix[1] == '\\' and prefix[2] == '\\') return error.InvalidText;
    for (path, 0..) |byte, index| {
        if (byte != ':') continue;
        if (index != 1 or !std.ascii.isAlphabetic(path[0]) or path.len < 3 or (path[2] != '\\' and path[2] != '/')) return error.InvalidText;
    }
    var parts = std.mem.tokenizeAny(u8, path, "\\/");
    while (parts.next()) |part| {
        if (std.mem.eql(u8, part, ".") or std.mem.eql(u8, part, "..")) continue;
        if (part[part.len - 1] == '.' or part[part.len - 1] == ' ') return error.InvalidText;
    }
}
fn candidate(allocator: Allocator, base: []const u8, directory: []const u8, program: []const u8) Error![:0]u8 {
    if (builtin.os.tag != .windows) {
        if (std.fs.path.isAbsolute(program)) return allocator.dupeSentinel(u8, program, 0);
        // Keep .. for the kernel to resolve after symbolic links.
        if (std.fs.path.isAbsolute(directory)) return std.fs.path.joinZ(allocator, &.{ directory, program });
        return std.fs.path.joinZ(allocator, &.{ base, directory, program });
    }
    try validateWindowsPath(directory);
    const path = try std.fs.path.resolve(allocator, &.{ base, directory, program });
    defer allocator.free(path);
    try validateWindowsPath(path);
    if (isScript(path)) return error.InvalidText;
    return allocator.dupeSentinel(u8, path, 0);
}
/// Windows tries .exe first for bare extensionless names, then the exact name.
/// The native Windows probe must classify a supported executable, not just any
/// existing file. No batch/script fallback is allowed.
fn tryCandidate(allocator: Allocator, probe: Probe, path: [:0]u8, denied: *bool) Error!?[:0]u8 {
    errdefer allocator.free(path);
    if (builtin.os.tag == .windows and std.fs.path.extension(path).len == 0) {
        const with_extension = try std.mem.concatWithSentinel(allocator, u8, &.{ path, ".exe" }, 0);
        errdefer allocator.free(with_extension);
        switch (try probe.check(probe.context, with_extension)) {
            .executable => {
                allocator.free(path);
                return with_extension;
            },
            .invalid_format => return error.BadExecutable,
            .denied => denied.* = true,
            .missing => {},
        }
        allocator.free(with_extension);
    }
    switch (try probe.check(probe.context, path)) {
        .executable => return path,
        .invalid_format => return error.BadExecutable,
        .denied => denied.* = true,
        .missing => {},
    }
    allocator.free(path);
    return null;
}
/// The caller supplies an absolute effective child cwd and merged environment.
/// Relative PATH components are resolved against that child cwd; empty components
/// are skipped. Probe performs OS-specific existence/access checks in the parent.
pub fn resolveProgram(allocator: Allocator, program: []const u8, cwd: []const u8, env: *const Environment, probe: Probe) Error![:0]u8 {
    if (program.len == 0 or !std.fs.path.isAbsolute(cwd) or std.mem.indexOfScalar(u8, program, 0) != null or std.mem.indexOfScalar(u8, cwd, 0) != null) return error.InvalidText;
    if (builtin.os.tag == .windows and std.fs.path.diskDesignatorWindows(cwd).len == 0) return error.InvalidText;
    try validateWindowsPath(program);
    try validateWindowsPath(cwd);
    if (isScript(program)) return error.InvalidText;
    // C:relative depends on per-drive working directories and is not portable.
    if (builtin.os.tag == .windows and std.mem.indexOfScalar(u8, program, ':') != null and !std.fs.path.isAbsolute(program)) return error.InvalidText;
    var denied = false;
    if (hasSeparator(program)) {
        const path = try candidate(allocator, cwd, "", program);
        return (try tryCandidate(allocator, probe, path, &denied)) orelse if (denied) error.AccessDenied else error.NotFound;
    }
    const path = env.get("PATH") orelse return error.NotFound;
    if (std.mem.indexOfScalar(u8, path, 0) != null) return error.InvalidText;
    var components = std.mem.splitScalar(u8, path, if (builtin.os.tag == .windows) ';' else ':');
    while (components.next()) |component| {
        if (component.len == 0) continue;
        // Windows PATH convention permits individually quoted directory entries.
        const directory = if (builtin.os.tag == .windows and component.len >= 2 and component[0] == '"' and component[component.len - 1] == '"') component[1 .. component.len - 1] else component;
        if (directory.len == 0) continue;
        const full = try candidate(allocator, cwd, directory, program);
        if (try tryCandidate(allocator, probe, full, &denied)) |found| return found;
    }
    return if (denied) error.AccessDenied else error.NotFound;
}

const TestProbe = struct {
    expected: []const u8,
    result: ProbeResult = .executable,
    calls: usize = 0,
    fn check(context: ?*anyopaque, path: []const u8) Error!ProbeResult {
        const self: *@This() = @ptrCast(@alignCast(context.?));
        self.calls += 1;
        return if (std.mem.eql(u8, self.expected, path)) self.result else .missing;
    }
    fn probe(self: *@This()) Probe {
        return .{ .context = self, .check = check };
    }
};

test "process environment edits use a private copy and retain ordering and platform name rules" {
    var inherited = Environment.init(std.testing.allocator);
    defer inherited.deinit();
    try inherited.put("KEEP", "original");
    try inherited.put("REMOVE", "old");
    try inherited.put("ÅNAME", "before");
    var config: table.Config = .{};
    defer config.deinit(std.testing.allocator);
    try config.addEnvironment(std.testing.allocator, "KEEP=first");
    try config.addEnvironment(std.testing.allocator, "KEEP=");
    try config.addEnvironment(std.testing.allocator, "REMOVE");
    try config.addEnvironment(std.testing.allocator, "åname=after");
    var result = try environment(std.testing.allocator, &inherited, &config);
    defer result.deinit();
    try std.testing.expectEqualStrings("original", inherited.get("KEEP").?);
    try std.testing.expectEqualStrings("", result.get("KEEP").?);
    try std.testing.expect(result.get("REMOVE") == null);
    try std.testing.expectEqualStrings(if (builtin.os.tag == .windows) "after" else "before", result.get("ÅNAME").?);
}

test "process resolution uses effective child cwd and merged PATH without probing empty components" {
    const cwd = if (builtin.os.tag == .windows) "C:\\work\\child" else "/work/child";
    const expected = if (builtin.os.tag == .windows) "C:\\work\\child\\tools\\tool.exe" else "/work/child/tools/tool";
    var env = Environment.init(std.testing.allocator);
    defer env.deinit();
    try env.put("PATH", if (builtin.os.tag == .windows) ";tools;C:\\bin;" else ":tools:/bin:");
    var probe: TestProbe = .{ .expected = expected };
    const resolved = try resolveProgram(std.testing.allocator, "tool", cwd, &env, probe.probe());
    defer std.testing.allocator.free(resolved);
    try std.testing.expectEqualStrings(expected, resolved);
    probe.result = .denied;
    try std.testing.expectError(error.AccessDenied, resolveProgram(std.testing.allocator, "tool", cwd, &env, probe.probe()));
    _ = env.orderedRemove("PATH");
    probe.calls = 0;
    try std.testing.expectError(error.NotFound, resolveProgram(std.testing.allocator, "tool", cwd, &env, probe.probe()));
    try std.testing.expectEqual(@as(usize, 0), probe.calls);
    try std.testing.expectError(error.InvalidText, resolveProgram(std.testing.allocator, "tool", "relative", &env, probe.probe()));
}

test "process resolution passes explicit paths without PATH lookup and never invokes a shell" {
    const cwd = if (builtin.os.tag == .windows) "C:\\work" else "/work";
    const expected = if (builtin.os.tag == .windows) "C:\\work\\dir\\tool.exe" else "/work/dir/tool";
    const program = if (builtin.os.tag == .windows) "dir\\tool.exe" else "dir/tool";
    var env = Environment.init(std.testing.allocator);
    defer env.deinit();
    var probe: TestProbe = .{ .expected = expected };
    const resolved = try resolveProgram(std.testing.allocator, program, cwd, &env, probe.probe());
    defer std.testing.allocator.free(resolved);
    try std.testing.expectEqualStrings(expected, resolved);
    if (builtin.os.tag == .windows) {
        try std.testing.expectError(error.InvalidText, resolveProgram(std.testing.allocator, "file.CMD", cwd, &env, probe.probe()));
        try std.testing.expectError(error.InvalidText, resolveProgram(std.testing.allocator, "C:tool.exe", cwd, &env, probe.probe()));
    }
}

test "environment and executable preparation roll back every failed allocation" {
    const Scenario = struct {
        fn run(allocator: Allocator) !void {
            var base = Environment.init(allocator);
            defer base.deinit();
            try base.put("PATH", "tools");
            try base.put("UNCHANGED", "kept");
            var config: table.Config = .{};
            defer config.deinit(allocator);
            try config.addEnvironment(allocator, "NEW=value");
            var merged = try environment(allocator, &base, &config);
            defer merged.deinit();
            const cwd = if (builtin.os.tag == .windows) "C:\\work" else "/work";
            const expected = if (builtin.os.tag == .windows) "C:\\work\\tools\\tool.exe" else "/work/tools/tool";
            var probe: TestProbe = .{ .expected = expected };
            const found = try resolveProgram(allocator, "tool", cwd, &merged, probe.probe());
            defer allocator.free(found);
            try std.testing.expectEqualStrings("kept", base.get("UNCHANGED").?);
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Scenario.run, .{});
}

test {
    _ = @import("host_process_quote.zig");
}

test "Windows resolution rejects normalized batch aliases ADS and ambiguous namespaces before probing" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    var env = Environment.init(std.testing.allocator);
    defer env.deinit();
    var probe: TestProbe = .{ .expected = "" };
    for ([_][]const u8{ "x.bat.", "x.bat ", "dir/x.cmd.", "x.exe:stream", "C:\\tool.exe::$DATA", "\\\\?\\C:\\tool.exe", "//./pipe/x", "/\\.\\x", "\\??\\UNC\\server\\share\\x.exe" }) |program| {
        try std.testing.expectError(error.InvalidText, resolveProgram(std.testing.allocator, program, "C:\\work", &env, probe.probe()));
    }
    try std.testing.expectEqual(@as(usize, 0), probe.calls);
}

test "POSIX resolution preserves symbolic link parent components for the kernel" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;
    var env = Environment.init(std.testing.allocator);
    defer env.deinit();
    try env.put("PATH", "links/..");
    var probe: TestProbe = .{ .expected = "/work/links/../tool" };
    const path = try resolveProgram(std.testing.allocator, "tool", "/work", &env, probe.probe());
    defer std.testing.allocator.free(path);
    try std.testing.expectEqualStrings(probe.expected, path);
}

test "Windows PATH rejects drive relative entries and prefers exe without probing empty quoted entries" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    const Both = struct {
        calls: usize = 0,
        fn check(context: ?*anyopaque, path: []const u8) Error!ProbeResult {
            const self: *@This() = @ptrCast(@alignCast(context.?));
            self.calls += 1;
            if (std.mem.eql(u8, path, "C:\\work\\tools\\tool.exe") or std.mem.eql(u8, path, "C:\\work\\tools\\tool")) return .executable;
            return .missing;
        }
    };
    var env = Environment.init(std.testing.allocator);
    defer env.deinit();
    var both: Both = .{};
    const probe: Probe = .{ .context = &both, .check = Both.check };
    try env.put("PATH", "\"\";tools");
    const found = try resolveProgram(std.testing.allocator, "tool", "C:\\work", &env, probe);
    defer std.testing.allocator.free(found);
    try std.testing.expectEqualStrings("C:\\work\\tools\\tool.exe", found);
    try std.testing.expectEqual(@as(usize, 1), both.calls);
    try std.testing.expectError(error.InvalidText, resolveProgram(std.testing.allocator, "tool", "\\work", &env, probe));
    for ([_][]const u8{ "C:bin", "tools.", "tools ", "//./pipe", "\\??\\UNC\\server\\share" }) |path| {
        try env.put("PATH", path);
        try std.testing.expectError(error.InvalidText, resolveProgram(std.testing.allocator, "tool", "C:\\work", &env, probe));
    }
    try std.testing.expectEqual(@as(usize, 1), both.calls);
}

test "Windows drive-rooted and UNC child cwd resolution retains the selected root" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    const Case = struct { cwd: []const u8, program: []const u8, expected: []const u8 };
    const cases = [_]Case{
        .{ .cwd = "D:\\child", .program = "\\bin\\tool.exe", .expected = "D:\\bin\\tool.exe" },
        .{ .cwd = "\\\\server\\share\\child", .program = "dir\\tool.exe", .expected = "\\\\server\\share\\child\\dir\\tool.exe" },
        .{ .cwd = "\\\\server\\share\\child", .program = "\\bin\\tool.exe", .expected = "\\\\server\\share\\bin\\tool.exe" },
    };
    var env = Environment.init(std.testing.allocator);
    defer env.deinit();
    for (cases) |case| {
        var probe: TestProbe = .{ .expected = case.expected };
        const found = try resolveProgram(std.testing.allocator, case.program, case.cwd, &env, probe.probe());
        defer std.testing.allocator.free(found);
        try std.testing.expectEqualStrings(case.expected, found);
    }
}

test "executable probing distinguishes invalid format and I/O failure from missing paths" {
    const Failure = struct {
        fn format(_: ?*anyopaque, _: []const u8) Error!ProbeResult {
            return .invalid_format;
        }
        fn io(_: ?*anyopaque, _: []const u8) Error!ProbeResult {
            return error.Io;
        }
    };
    var env = Environment.init(std.testing.allocator);
    defer env.deinit();
    const cwd = if (builtin.os.tag == .windows) "C:\\work" else "/work";
    try std.testing.expectError(error.BadExecutable, resolveProgram(std.testing.allocator, "dir/tool", cwd, &env, .{ .context = null, .check = Failure.format }));
    try std.testing.expectError(error.Io, resolveProgram(std.testing.allocator, "dir/tool", cwd, &env, .{ .context = null, .check = Failure.io }));
}
