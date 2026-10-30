//! What the host provides to the core: output, input, files, and other services.

const defs = @import("defs.zig");
const forth = @import("../forth.zig");
const memory_map = @import("memory_map.zig");
const Cell = memory_map.Cell;
const Double = memory_map.Double;
const RuntimeError = defs.RuntimeError;
const State = forth.State;
const UCell = memory_map.UCell;

pub const FileAccess = enum { read_only, write_only, read_write };

pub const FileResult = struct { value: UCell = 0, ior: Cell = 0 };

/// `found` is false only at the end of the file with nothing read.
pub const LineResult = struct { length: usize = 0, found: bool = false, ior: Cell = 0 };

/// Host file operations. Ids are opaque cells; the standard streams use the fixed ids above.
pub const FileOps = struct {
    /// Opens an existing file, or creates and truncates one when `create` is set.
    open: *const fn (?*anyopaque, []const u8, FileAccess, bool) FileResult,
    close: *const fn (?*anyopaque, Cell) Cell,
    /// Reads up to `buffer.len` bytes of one line, without the LF, CR or CRLF terminator.
    read_line: *const fn (?*anyopaque, Cell, []u8) LineResult,
    /// Reads up to `buffer.len` bytes as they are; the value is the count, 0 at the end.
    read: *const fn (?*anyopaque, Cell, []u8) FileResult,
    write: *const fn (?*anyopaque, Cell, []const u8) Cell,
    size: *const fn (?*anyopaque, Cell) FileResult,
    reposition: *const fn (?*anyopaque, Cell, UCell) Cell,
    /// The read and write position.
    position: *const fn (?*anyopaque, Cell) FileResult,
    /// Cuts the file to the size or extends it with zero bytes; the position stays.
    resize: *const fn (?*anyopaque, Cell, UCell) Cell,
    flush: *const fn (?*anyopaque, Cell) Cell,
    delete: *const fn (?*anyopaque, []const u8) Cell,
    rename: *const fn (?*anyopaque, []const u8, []const u8) Cell,
    /// Whether the named file exists; the value is R/O, W/O, or R/W, as it can be opened.
    status: *const fn (?*anyopaque, []const u8) FileResult,
};

/// The local date and time, for TIME&DATE: month 1 to 12, the full year.
pub const LocalTime = struct { second: Cell, minute: Cell, hour: Cell, day: Cell, month: Cell, year: Cell };

pub const Writer = struct {
    context: ?*anyopaque,
    write_fn: *const fn (?*anyopaque, []const u8) void,
    read_fn: ?*const fn (?*anyopaque, []u8) ?[]const u8 = null,
    load_fn: ?*const fn (?*anyopaque, []const u8, *State) RuntimeError!void = null,
    save_fn: ?*const fn (?*anyopaque, []const u8, *State) RuntimeError!void = null,
    savesys_fn: ?*const fn (?*anyopaque, []const u8, *State) RuntimeError!void = null,
    key_fn: ?*const fn (?*anyopaque) ?u8 = null,
    key_ready_fn: ?*const fn (?*anyopaque) bool = null,
    sleep_fn: ?*const fn (?*anyopaque, Cell) RuntimeError!void = null,
    /// Microseconds since the Unix epoch.
    utime_fn: ?*const fn (?*anyopaque) RuntimeError!Double = null,
    local_time_fn: ?*const fn (?*anyopaque) RuntimeError!LocalTime = null,
    /// Copies the variable's value into the buffer and returns its length, or null when unset.
    getenv_fn: ?*const fn (?*anyopaque, []const u8, []u8) RuntimeError!?usize = null,
    /// Runs a shell command and returns the status `system` gave; a non-zero status is not an error.
    system_fn: ?*const fn (?*anyopaque, []const u8) RuntimeError!Cell = null,
    file_ops: ?*const FileOps = null,

    pub fn write(self: Writer, bytes: []const u8) void {
        self.write_fn(self.context, bytes);
    }
};
