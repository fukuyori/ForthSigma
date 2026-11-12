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
};

pub fn isFunction(event: Cell) bool {
    const base = event & ~(shift | alt | ctrl);
    return base >= special and base <= special + 22 and base != special + 10;
}

pub fn isCharacter(event: Cell) bool {
    return event >= 0 and event <= 0x10ffff and !(event >= 0xd800 and event <= 0xdfff);
}
