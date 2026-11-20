//! Separate owned-process fixture. Never installed with Sigma's normal build.
pub const audio_lifecycle_fixture = true;
const audio = @import("host_audio.zig");
extern "c" fn puts([*:0]const u8) c_int;
extern "c" fn fflush(?*anyopaque) c_int;
pub fn main() u8 {
    audio.testing.holdConsumer();
    _ = audio.start(null) orelse return 2;
    if (audio.shutdown(5) or !audio.testing.retained()) return 3;
    _ = puts("blocked consumer retained; hard exit 1");
    _ = fflush(null);
    audio.abortIncomplete();
}
