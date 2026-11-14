//! Explicit editor commands and one-shot/default selection destinations.
const std = @import("std");
const forth = @import("../forth.zig");
const defs = @import("defs.zig");
const map = @import("memory_map.zig");
const input = @import("source_input.zig");
const navigation = @import("source_navigation.zig");
pub const words = [_]defs.Builtin{ .edit_source, .source_g, .source_gg, .source_ll, .where_g };
pub const Destination = enum { display, editor };
pub const Mode = struct { base: Destination = .display, once: ?Destination = null, generation: u64 = 0 };
fn mode(self: *forth.State) *Mode {
    if (self.source_editor_mode.generation != self.image_generation) self.source_editor_mode = .{ .generation = self.image_generation };
    return &self.source_editor_mode;
}
pub fn takeDestination(self: *forth.State) Destination {
    const choice = mode(self);
    const result = choice.once orelse choice.base;
    choice.once = null;
    return result;
}
pub fn execute(self: *forth.State, comptime word: defs.Builtin) forth.RuntimeError!void {
    switch (word) {
        .edit_source => {
            const name = (try self.nextSourceToken()) orelse return error.InputUnavailable;
            const id = try self.lookupOrFail(name);
            const definition = self.words[id];
            self.source_navigation.length = 0;
            if (definition.source_file != 0) navigation.select(self, definition.source_file - 1, definition.source_line);
            try open(self);
        },
        .source_g => try open(self),
        .source_gg, .source_ll => {
            const choice = mode(self);
            const destination: Destination = if (word == .source_gg) .editor else .display;
            if (choice.once == destination) {
                choice.base = destination;
                choice.once = null;
            } else choice.once = destination;
        },
        .where_g => try where(self),
        else => unreachable,
    }
}
pub fn open(self: *forth.State) forth.RuntimeError!void {
    const selected = self.source_navigation;
    if (selected.length == 0 or selected.generation != self.image_generation) {
        self.source_navigation.length = 0;
        return navigation.noLocation(self);
    }
    const edit = self.writer.editor_fn orelse return error.HostUnavailable;
    const name = selected.path[0..selected.length];
    if (input.embeddedSource(self, name)) |text| {
        return edit(self.writer.context, .{ .text = .{ .bytes = text, .line = selected.edit_line } });
    }
    const absolute = try @import("source_listing.zig").expanded(self, name);
    return edit(self.writer.context, .{ .file = .{ .path = absolute.text(), .line = selected.edit_line } });
}
fn where(self: *forth.State) forth.RuntimeError!void {
    const name = (try self.nextSourceToken()) orelse return error.InputUnavailable;
    const id = try self.lookupOrFail(name);
    const edit = self.writer.editor_fn orelse return error.HostUnavailable;
    const generation = self.image_generation;
    var output = @import("macro_substitute.zig").Captured{};
    defer if (self.image_generation == generation) output.free(self);
    {
        const old_target = self.capture_target;
        const old_sink = self.capture_sink;
        const old_failed = self.capture_failed;
        const old_style = self.readCellConst(map.where_style_address);
        self.capture_target = null;
        self.capture_sink = &output;
        self.capture_failed = false;
        var style_changed = false;
        defer {
            self.capture_target = old_target;
            self.capture_sink = old_sink;
            self.capture_failed = old_failed;
            if (style_changed and self.image_generation == generation) self.writeCell(map.where_style_address, old_style) catch unreachable;
        }
        try self.writeCell(map.where_style_address, 1);
        style_changed = true;
        try input.listUses(self, id);
        if (self.image_generation != generation) return error.InvalidExecutionToken;
        if (self.capture_failed) return self.throwIor(map.errno_no_memory);
    }
    const text = std.mem.trimStart(u8, output.bytes(self), "\n");
    if (text.len == 0) return navigation.noLocation(self);
    // The callback must consume the borrowed text before it returns. A host that
    // restores a dictionary must copy it first; the generation guard avoids freeing
    // an allocation at the same address in the newly restored heap.
    try edit(self.writer.context, .{ .text = .{ .bytes = text, .line = 1 } });
}
