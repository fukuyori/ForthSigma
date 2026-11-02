//! A root for compiling the core with no operating system (`zig build freestanding`).
//! Nothing runs it: building it checks that forth.zig and src/core use no OS service, so
//! that the core stays usable on a microcontroller with a host of its own.

const forth = @import("forth.zig");

export fn sigma_init(state: *forth.State, writer: *const forth.Writer) void {
    state.init(writer.*);
}

export fn sigma_interpret_line(state: *forth.State, line: [*]const u8, length: usize) bool {
    state.interpretLine(line[0..length]) catch |err| {
        state.report(err);
        return false;
    };
    return true;
}
