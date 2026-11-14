//! CSV settings and quoted field output. Input parsing is added separately.
const forth = @import("../forth.zig");
const defs = @import("defs.zig");
const map = @import("memory_map.zig");

pub fn execute(self: *forth.State, comptime word: defs.Builtin) forth.RuntimeError!void {
    switch (word) {
        .csv_quote => try self.push(self.readCellConst(map.csv_quote_address)),
        .csv_separator => try self.push(self.readCellConst(map.csv_separator_address)),
        .dot_quoted_csv => {
            try self.requireDepth(2);
            const length: usize = @intCast(@max(try self.peek(0), 0));
            const at = try self.memoryAddress(try self.peek(1), length);
            var bytes: []const u8 = self.memory[at..][0..length];
            var snapshot: ?map.Cell = null;
            defer if (snapshot) |copy| {
                _ = self.heapFree(copy) catch {};
            };
            // Appending captured output may resize/free the input's owner.
            if (length != 0 and (self.capture_sink != null or self.capture_target != null)) {
                const copy = try self.heapAllocate(length) orelse return self.throwIor(map.errno_no_memory);
                snapshot = copy;
                @memcpy(self.memory[@intCast(copy)..][0..length], bytes);
                bytes = self.memory[@intCast(copy)..][0..length];
            }
            const quote = self.readCellConst(map.csv_quote_address);
            const delimiter: [1]u8 = .{@truncate(@as(map.UCell, @bitCast(quote)))};
            self.data_depth -= 2;
            self.write(&delimiter);
            try self.checkOutputError();
            for (bytes, 0..) |byte, index| {
                if (index % 256 == 0) try @import("words_numeric.zig").checkWorkBlock(self);
                if (@as(map.Cell, byte) == quote) self.write(&delimiter);
                self.write(&.{byte});
                try self.checkOutputError();
            }
            self.write(&delimiter);
        },
        else => unreachable,
    }
}
