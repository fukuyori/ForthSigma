//! A root for compiling the core with no operating system (`zig build freestanding`).
//! Nothing runs it: building it checks that what a host calls (start-up, a line, and the
//! image functions) reaches no OS service through Zig's standard library, so that the
//! core stays usable on a microcontroller with a host of its own. The object is not
//! linked, so a function the core declares `extern` itself is not checked.

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

export fn sigma_image_capacity() usize {
    return forth.State.imageCapacity();
}

/// The image's length, or 0 when it does not fit.
export fn sigma_encode_image(state: *forth.State, output: [*]u8, capacity: usize) usize {
    return state.encodeImage(output[0..capacity]) catch 0;
}

export fn sigma_restore_image(state: *forth.State, image: [*]const u8, length: usize) bool {
    state.restoreImage(image[0..length]) catch return false;
    return true;
}

export fn sigma_append_image(state: *forth.State, source: *const forth.State) bool {
    state.appendImage(source) catch return false;
    return true;
}

const sound = @import("core/sound_engine.zig");

/// The sound engine as an audio thread would run it: it, too, must reach no OS service.
export fn sigma_sound_render(engine: *sound.Engine, output: [*]i16, length: usize) void {
    engine.render(output[0..length]);
}
