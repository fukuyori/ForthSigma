//! Scoped, borrowed output-file redirection.
const forth = @import("../forth.zig");

pub fn run(self: *forth.State) forth.RuntimeError!void {
    try self.requireDepth(2);
    const fileid = try self.peek(0);
    const xt = try self.wordId(try self.peek(1));
    _ = try self.fileOps();
    const previous_file = self.output_file;
    const previous_error = self.output_error;
    const previous_sink = self.capture_sink;
    const previous_target = self.capture_target;
    const previous_failed = self.capture_failed;
    self.output_file = fileid;
    self.output_error = null;
    self.capture_sink = null;
    self.capture_target = null;
    self.capture_failed = false;
    defer {
        self.output_file = previous_file;
        self.output_error = previous_error;
        self.capture_sink = previous_sink;
        self.capture_target = previous_target;
        self.capture_failed = previous_failed;
    }
    self.data_depth -= 2;
    try self.executeWord(xt);
    try self.checkOutputError();
}
