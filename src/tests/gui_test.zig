//! Tests of REQUIRE-GUI and the GUI words, with the mouse, the keys, and a gamepad of the
//! fake host.

const std = @import("std");
const forth = @import("../forth.zig");
const gp = @import("../core/gamepad.zig");
const words_graphics = @import("../core/words_graphics.zig");
const words_gui = @import("../core/words_gui.zig");
const support = @import("support.zig");
const Output = support.Output;
const createMachine = support.createMachine;
const destroyMachine = support.destroyMachine;
const expectStack = support.expectStack;
const skipWithout = support.skipWithout;

/// A machine with the GUI words in the search order, drawing on an image of 160 by 120 (the
/// fake host's screen is small).
fn guiMachine(output: *Output) !*forth.State {
    const machine = try createMachine(output);
    errdefer destroyMachine(machine);
    try machine.interpretLine("REQUIRE-GUI ALSO GRAPHICS ALSO GUI 40 40 GFX-INIT 160 120 NEW-IMAGE DRAW-TO");
    return machine;
}

/// The events of the next frame.
fn events(output: *Output, list: []const forth.InputEvent) void {
    output.events = list;
    output.event_index = 0;
}

/// A click of the left button at x y, as the window gives it.
fn click(x: i32, y: i32) [2]forth.InputEvent {
    return .{ .{ .window_mouse = .{ .x = x, .y = y, .buttons = 1 } }, .{ .window_mouse = .{ .x = x, .y = y, .buttons = 0 } } };
}

fn key(code: u32) forth.InputEvent {
    return .{ .window_key = code };
}

test "REQUIRE-GUI loads the graphics words first, once, and keeps the search order" {
    try skipWithout(&.{.graphics});
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    try machine.interpretLine("REQUIRE-GUI");
    try std.testing.expect(words_graphics.graphicsLoaded(machine));
    try std.testing.expect(words_gui.guiLoaded(machine));
    try std.testing.expect(machine.lookup("GUI-BUTTON") == null);
    const words = machine.word_count;
    try machine.interpretLine("REQUIRE-GUI require-gui GUI GUI-FACE GUI-COLOR@ FORTH");
    try expectStack(machine, &.{0xE1E1E1});
    try std.testing.expectEqual(words, machine.word_count);
    try std.testing.expectError(error.InvalidDefinition, machine.interpretLine(": X REQUIRE-GUI ;"));
}

test "REQUIRE-GUI is refused in a build without graphics" {
    if (@import("build_options").graphics) return error.SkipZigTest;
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);
    try std.testing.expectError(error.GraphicsUnavailable, machine.interpretLine("REQUIRE-GUI"));
}

test "the colors and the line widths are settings, and GUI-DEFAULT puts them back" {
    try skipWithout(&.{.graphics});
    var output = Output{};
    const machine = try guiMachine(&output);
    defer destroyMachine(machine);
    try machine.interpretLine("$FF123456 GUI-TEXT GUI-COLOR! GUI-TEXT GUI-COLOR@ 3 GUI-BORDER-WIDTH");
    try expectStack(machine, &.{0x123456});
    machine.data_depth = 0;
    // A button 3 lines wide is drawn so: its corner pixel and the ones inside it.
    try machine.interpretLine("0 GFX-CLS GUI-BEGIN S\" OK\" 10 10 GUI-BUTTON DROP GUI-END 12 12 GFX-PGET 13 13 GFX-PGET");
    try expectStack(machine, &.{ 0x8A8A8A, 0xE1E1E1 });
    machine.data_depth = 0;
    for ([_][]const u8{ "0 11 GUI-COLOR!", "0 -1 GUI-COLOR@", "9 GUI-BORDER-WIDTH", "-1 GUI-FOCUS-WIDTH" }) |line| {
        try std.testing.expectError(error.InvalidNumber, machine.interpretLine(line));
        machine.data_depth = 0;
    }
    try machine.interpretLine("GUI-DEFAULT GUI-TEXT GUI-COLOR@");
    try expectStack(machine, &.{0});
}

test "a button is clicked by the mouse, or by Enter and Space with the focus" {
    try skipWithout(&.{.graphics});
    var output = Output{};
    const machine = try guiMachine(&output);
    defer destroyMachine(machine);
    // Two buttons: OK at 10 10, Cancel at 60 10.
    try machine.interpretLine(": FRAME-1 GUI-BEGIN S\" OK\" 10 10 GUI-BUTTON S\" Cancel\" 60 10 GUI-BUTTON GUI-END ;");
    const on_ok = click(12, 12);
    events(&output, &on_ok);
    try machine.interpretLine("FRAME-1");
    try expectStack(machine, &.{ -1, 0 });
    machine.data_depth = 0;
    // Pressed on OK and released elsewhere: no click.
    const away = [_]forth.InputEvent{ .{ .window_mouse = .{ .x = 12, .y = 12, .buttons = 1 } }, .{ .window_mouse = .{ .x = 150, .y = 100, .buttons = 0 } } };
    events(&output, &away);
    try machine.interpretLine("FRAME-1");
    try expectStack(machine, &.{ 0, 0 });
    machine.data_depth = 0;
    // The click gave OK the focus; Tab gives it to Cancel, Enter clicks it, Space too.
    const keys = [_]forth.InputEvent{ key(9), key(13) };
    events(&output, &keys);
    try machine.interpretLine("FRAME-1");
    try expectStack(machine, &.{ 0, -1 });
    machine.data_depth = 0;
    const space = [_]forth.InputEvent{key(' ')};
    events(&output, &space);
    try machine.interpretLine("FRAME-1");
    try expectStack(machine, &.{ 0, -1 });
    machine.data_depth = 0;
    // A disabled button takes no click and no focus; the key not taken waits for GUI-KEY.
    const disabled = [_]forth.InputEvent{ on_ok[0], on_ok[1], key('x') };
    events(&output, &disabled);
    try machine.interpretLine("GUI-BEGIN FALSE GUI-ENABLE S\" OK\" 10 10 GUI-BUTTON GUI-END GUI-KEY GUI-KEY");
    try expectStack(machine, &.{ 0, 'x', -1 });
}

test "a check box changes its flag when clicked or with Space" {
    try skipWithout(&.{.graphics});
    var output = Output{};
    const machine = try guiMachine(&output);
    defer destroyMachine(machine);
    try machine.interpretLine("VARIABLE GRID : FRAME-1 GUI-BEGIN GRID S\" Grid\" 10 10 GUI-CHECK GUI-END ;");
    // On the label, which belongs to the box.
    const on_label = click(30, 14);
    events(&output, &on_label);
    try machine.interpretLine("FRAME-1 GRID @");
    try expectStack(machine, &.{ -1, -1 });
    machine.data_depth = 0;
    const space = [_]forth.InputEvent{key(' ')};
    events(&output, &space);
    try machine.interpretLine("FRAME-1 GRID @");
    try expectStack(machine, &.{ -1, 0 });
}

test "a field takes text, UTF-8 too, edits it at the cursor, and tells Enter" {
    try skipWithout(&.{.graphics});
    var output = Output{};
    const machine = try guiMachine(&output);
    defer destroyMachine(machine);
    try machine.interpretLine("CREATE BUF 8 ALLOT VARIABLE LEN : FRAME-1 GUI-BEGIN BUF 8 LEN 10 10 100 GUI-FIELD GUI-END ; : TEXT$ BUF LEN @ ;");
    // The only part: it has the focus. "ab", then あ (3 bytes), then Backspace takes
    // all of it; Left, and X goes in before b.
    const typed = [_]forth.InputEvent{ key('a'), key('b'), key(0xE3), key(0x81), key(0x82), key(8), key(258), key('X') };
    events(&output, &typed);
    try machine.interpretLine("FRAME-1 TEXT$ S\" aXb\" COMPARE");
    try expectStack(machine, &.{ 0, 0 });
    machine.data_depth = 0;
    // Home, Delete, End, more than there is room for, and Enter.
    const more = [_]forth.InputEvent{ key(260), key(265), key(261), key('1'), key('2'), key('3'), key('4'), key('5'), key('6'), key('7'), key(13) };
    events(&output, &more);
    try machine.interpretLine("FRAME-1 TEXT$ S\" Xb123456\" COMPARE");
    try expectStack(machine, &.{ -1, 0 });
}

test "a list follows the arrows and the mouse, and tells the choice" {
    try skipWithout(&.{.graphics});
    var output = Output{};
    const machine = try guiMachine(&output);
    defer destroyMachine(machine);
    try machine.interpretLine("VARIABLE PICK : FRAME-1 GUI-BEGIN S\" One|Two|Three\" PICK 10 10 60 GUI-LIST GUI-END ;");
    // Up from the first goes round to the last; Down then Enter.
    const keys = [_]forth.InputEvent{ key(256), key(257), key(257), key(13) };
    events(&output, &keys);
    try machine.interpretLine("FRAME-1 PICK @");
    try expectStack(machine, &.{ -1, 1 });
    machine.data_depth = 0;
    // A click on the third row (each row is 16 pixels with the built-in font).
    const on_third = click(20, 10 + 2 * 16 + 4);
    events(&output, &on_third);
    try machine.interpretLine("FRAME-1 PICK @");
    try expectStack(machine, &.{ -1, 2 });
}

test "the menu bar opens a menu, and an item is chosen by a click or the keys" {
    try skipWithout(&.{.graphics});
    var output = Output{};
    const machine = try guiMachine(&output);
    defer destroyMachine(machine);
    try machine.interpretLine(
        \\: FRAME-1 GUI-BEGIN S" File|Edit" GUI-MENUBAR
        \\  DUP 0 = IF DROP S" New|-|~Export|Quit" GUI-MENU ELSE 1 = IF S" Copy" GUI-MENU ELSE -9 THEN THEN
        \\  S" OK" 10 100 GUI-BUTTON GUI-END ;
    );
    const on_file = click(4, 4);
    events(&output, &on_file);
    try machine.interpretLine("FRAME-1");
    // File is open; nothing chosen yet.
    try expectStack(machine, &.{ -1, 0 });
    machine.data_depth = 0;
    // The items are under the bar: New at 16, the line, ~Export, and Quit at 16+16+5+16.
    const on_quit = click(10, 16 + 16 + 5 + 16 + 4);
    events(&output, &on_quit);
    try machine.interpretLine("FRAME-1");
    try expectStack(machine, &.{ 3, 0 });
    machine.data_depth = 0;
    // Closed after the choice; the disabled item cannot be chosen.
    events(&output, &on_file);
    try machine.interpretLine("FRAME-1");
    machine.data_depth = 0;
    const on_export = click(10, 16 + 16 + 5 + 4);
    events(&output, &on_export);
    try machine.interpretLine("FRAME-1");
    try expectStack(machine, &.{ -1, 0 });
    machine.data_depth = 0;
    // With the menu open the keys go to it: Down skips the line and ~Export, Enter
    // chooses; the OK button under the menu takes neither the click nor the key.
    const keys = [_]forth.InputEvent{ key(257), key(13) };
    events(&output, &keys);
    try machine.interpretLine("FRAME-1");
    try expectStack(machine, &.{ 3, 0 });
    machine.data_depth = 0;
    // Right goes to the next menu; Esc closes it.
    events(&output, &on_file);
    try machine.interpretLine("FRAME-1");
    machine.data_depth = 0;
    const right = [_]forth.InputEvent{key(259)};
    events(&output, &right);
    try machine.interpretLine("FRAME-1");
    try expectStack(machine, &.{ -1, 0 });
    machine.data_depth = 0;
    const escape = [_]forth.InputEvent{key(27)};
    events(&output, &escape);
    try machine.interpretLine("FRAME-1");
    try expectStack(machine, &.{ -9, 0 });
}

test "the function key bar tells a key pressed or a label clicked" {
    try skipWithout(&.{.graphics});
    var output = Output{};
    const machine = try guiMachine(&output);
    defer destroyMachine(machine);
    try machine.interpretLine(": FRAME-1 GUI-BEGIN S\" Help|Load|Save|Run\" GUI-FKEYS GUI-END ;");
    const f3 = [_]forth.InputEvent{key(268)};
    events(&output, &f3);
    try machine.interpretLine("FRAME-1");
    try expectStack(machine, &.{2});
    machine.data_depth = 0;
    // The bar takes the last row of 16 pixels; the second of four labels is at 40 to 80.
    const on_load = click(50, 120 - 8);
    events(&output, &on_load);
    try machine.interpretLine("FRAME-1 FRAME-1");
    try expectStack(machine, &.{ 1, -1 });
}

test "a dialog answers by its buttons, Enter, and Esc" {
    try skipWithout(&.{.graphics});
    var output = Output{};
    const machine = try guiMachine(&output);
    defer destroyMachine(machine);
    try machine.interpretLine(": FRAME-1 GUI-BEGIN S\" Quit?\" GUI-YES-NO GUI-END ;");
    try machine.interpretLine("FRAME-1");
    try expectStack(machine, &.{-1});
    machine.data_depth = 0;
    const enter = [_]forth.InputEvent{key(13)};
    events(&output, &enter);
    try machine.interpretLine("FRAME-1");
    try expectStack(machine, &.{1});
    machine.data_depth = 0;
    const escape = [_]forth.InputEvent{key(27)};
    events(&output, &escape);
    try machine.interpretLine("FRAME-1");
    try expectStack(machine, &.{0});
}

test "GUI-ASK and GUI-CHOOSE wait for the answer and put the screen back" {
    try skipWithout(&.{.graphics});
    var output = Output{ .has_window = true };
    const machine = try guiMachine(&output);
    defer destroyMachine(machine);
    // These draw on the screen, 40 by 40 here.
    try machine.interpretLine("DRAWING FREE-IMAGE DISPLAY-WINDOW $123456 GFX-CLS");
    const enter = [_]forth.InputEvent{key(13)};
    events(&output, &enter);
    try machine.interpretLine("S\" Quit?\" GUI-ASK 20 20 GFX-PGET DRAWING");
    try expectStack(machine, &.{ -1, 0x123456, 0 });
    machine.data_depth = 0;
    try std.testing.expectEqual(@as(usize, 0), output.images_live);
    const down_enter = [_]forth.InputEvent{ key(257), key(257), key(13) };
    events(&output, &down_enter);
    try machine.interpretLine("S\" A|B|C\" GUI-CHOOSE");
    try expectStack(machine, &.{2});
    machine.data_depth = 0;
    const escape = [_]forth.InputEvent{key(27)};
    events(&output, &escape);
    try machine.interpretLine("S\" A|B|C\" GUI-CHOOSE");
    try expectStack(machine, &.{-1});
    machine.data_depth = 0;
    // GUI-MESSAGE closes with Esc too.
    events(&output, &escape);
    try machine.interpretLine("S\" Done\" GUI-MESSAGE 20 20 GFX-PGET");
    try expectStack(machine, &.{0x123456});
}

var pad: gp.Snapshot = .{};
fn padPoll(_: ?*anyopaque, out: *gp.Snapshot) bool {
    out.* = pad;
    return true;
}
fn padMapping(_: ?*anyopaque, _: []const u8) bool {
    return false;
}
const pad_ops: gp.Ops = .{ .poll = padPoll, .mapping = padMapping };

test "the first gamepad moves a list and chooses with A, each press once" {
    try skipWithout(&.{.graphics});
    var output = Output{};
    const machine = try guiMachine(&output);
    defer destroyMachine(machine);
    machine.writer.gamepad_ops = &pad_ops;
    try machine.interpretLine("VARIABLE PICK : FRAME-1 GUI-BEGIN S\" One|Two|Three\" PICK 10 10 60 GUI-LIST GUI-END ;");
    pad = .{};
    pad.count = 1;
    pad.pads[0] = .{ .id = 1, .mapped = true, .buttons = 1 << 12 };
    // Down held over two frames moves once.
    try machine.interpretLine("FRAME-1 FRAME-1 PICK @");
    try expectStack(machine, &.{ 0, 0, 1 });
    machine.data_depth = 0;
    pad.pads[0].buttons = 1;
    try machine.interpretLine("FRAME-1 PICK @");
    try expectStack(machine, &.{ -1, 1 });
    pad = .{};
}
