//! Sigma standard keyboard events. Values are recorded in the P00 comparison data.
const Cell = @import("memory_map.zig").Cell;
pub const special: Cell = 0x80000000;
pub const shift: Cell = 0x10000000;
pub const alt: Cell = 0x20000000;
pub const ctrl: Cell = 0x40000000;
pub const constants = [_]struct { []const u8, Cell }{
    .{ "K-ALT-MASK", 536870912 },
    .{ "K-CTRL-MASK", 1073741824 },
    .{ "K-DELETE", 2147483657 },
    .{ "K-DOWN", 2147483651 },
    .{ "K-END", 2147483653 },
    .{ "K-F1", 2147483659 },
    .{ "K-F10", 2147483668 },
    .{ "K-F11", 2147483669 },
    .{ "K-F12", 2147483670 },
    .{ "K-F2", 2147483660 },
    .{ "K-F3", 2147483661 },
    .{ "K-F4", 2147483662 },
    .{ "K-F5", 2147483663 },
    .{ "K-F6", 2147483664 },
    .{ "K-F7", 2147483665 },
    .{ "K-F8", 2147483666 },
    .{ "K-F9", 2147483667 },
    .{ "K-HOME", 2147483652 },
    .{ "K-INSERT", 2147483656 },
    .{ "K-LEFT", 2147483648 },
    .{ "K-NEXT", 2147483655 },
    .{ "K-PRIOR", 2147483654 },
    .{ "K-RIGHT", 2147483649 },
    .{ "K-SHIFT-MASK", 268435456 },
    .{ "K-UP", 2147483650 },
    .{ "K-BACKSPACE", 2147483676 },
    .{ "K-ENTER", 2147483658 },
    .{ "K-EOF", 2147483681 },
    .{ "K-MUTE", 2147483673 },
    .{ "K-PAUSE", 2147483672 },
    .{ "K-SEL", 2147483678 },
    .{ "K-TAB", 2147483677 },
    .{ "K-VOLDOWN", 2147483675 },
    .{ "K-VOLUP", 2147483674 },
    .{ "K-WINCH", 2147483671 },
};

pub fn isFunction(event: Cell) bool {
    const base = event & ~(shift | alt | ctrl);
    return base >= special and base <= special + 33;
}

pub fn isCharacter(event: Cell) bool {
    return event >= 0 and event <= 0x10ffff and !(event >= 0xd800 and event <= 0xdfff);
}

pub const names = [_][]const u8{
    "k-left", "k-right", "k-up",    "k-down", "k-home",  "k-end",     "k-prior",     "k-next", "k-insert", "k-delete",  "k-enter",
    "k-f1",   "k-f2",    "k-f3",    "k-f4",   "k-f5",    "k-f6",      "k-f7",        "k-f8",   "k-f9",     "k-f10",     "k-f11",
    "k-f12",  "k-winch", "k-pause", "k-mute", "k-volup", "k-voldown", "k-backspace", "k-tab",  "k-sel",    "k-fgcolor", "k-bgcolor",
    "k-eof",
};
pub const eof = special + 33;
pub const winch = special + 23;
pub const tab = special + 29;
pub const name_bytes = bytes: {
    var count: usize = 0;
    for (names) |name| {
        count += name.len;
    }
    break :bytes count;
};
pub fn nameOffset(index: usize) usize {
    var offset: usize = 0;
    for (names[0..index]) |name| offset += name.len;
    return offset;
}
