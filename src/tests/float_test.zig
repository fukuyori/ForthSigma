//! Tests of the floating-point words, their output, and the math functions.

const std = @import("std");
const forth = @import("../forth.zig");
const support = @import("support.zig");
const Output = support.Output;
const createMachine = support.createMachine;
const destroyMachine = support.destroyMachine;
const expectStack = support.expectStack;
const expectFloatStack = support.expectFloatStack;
const expectOutput = support.expectOutput;

test "float literals require an exponent and use a separate stack" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("1 1E 1.5e0 .5E -2.25E+1 0.e 3");

    const expected = [_]forth.Cell{ 1, 3 };
    try expectStack(machine, &expected);
    const floats = [_]forth.Float{ 1.0, 1.5, 0.5, -22.5, 0.0 };
    try expectFloatStack(machine, &floats);

    try machine.interpretLine("2DROP 1.5 HEX 1E DECIMAL");
    const not_floats = [_]forth.Cell{ 15, 0, 0x1e };
    try expectStack(machine, &not_floats);
    try expectFloatStack(machine, &floats);
}

test "F. prints fixed notation with 15 significant digits and a trailing space" {
    try expectOutput("1E 2E F+ F. 1.5E F. 0.5E F. 1E-5 F. 1E20 F. -2.5E F. 0E F. 123E F. 2E FSQRT F.", "3. 1.5 0.5 0.00001 100000000000000000000. -2.5 0. 123. 1.4142135623731 ");
}

test "F. prints non-finite values by name" {
    try expectOutput("1E 0E F/ F. -1E 0E F/ F. 0E 0E F/ F.", "infinity -infinity NaN ");
}

test "F.S shows each float as 14 0 17 F.RDP does" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("1E 2E 0.5E 1E-7 -3.25E 1E30 F.S");

    try std.testing.expectEqualStrings("<6> 1.0000000000E0 2.0000000000E0 5.000000000E-1 1.000000000E-7 -3.250000000E0 1.000000000E30 ", output.written());
    try std.testing.expectEqual(@as(usize, 6), machine.float_depth);
}

test "float arithmetic comparison and conversion" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("1E 2E F< 2E 1E F< 1E 1E F= 0E F0= -1E F0< 10 S>F 4E F/ F>S 2.9E F>S -2.9E F>S FDEPTH");
    const expected = [_]forth.Cell{ -1, 0, -1, -1, -1, 2, 2, -2, 0 };
    try expectStack(machine, &expected);

    try machine.interpretLine("3E 4E FMAX -5E FABS FMIN 2E FNEGATE 1E FOVER FSWAP FDROP FNIP 7E 8E FTUCK F-ROT FROT 1 FPICK");
    const floats = [_]forth.Float{ 4.0, -2.0, 8.0, 7.0, 8.0, 7.0 };
    try expectFloatStack(machine, &floats);
}

test "float math functions follow the host libm" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("9E FSQRT 0E FEXP 1E FLN 0E FSIN 0E FCOS 0E FTAN");

    const floats = [_]forth.Float{ 3.0, 1.0, 0.0, 0.0, 1.0, 0.0 };
    try expectFloatStack(machine, &floats);
}

test "float memory, variables, constants, and arrays" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("CREATE TEMP 1 FLOATS ALLOT 37.5E TEMP F! TEMP F@ F.");
    try machine.interpretLine("FVARIABLE ACC 1.5E ACC F! 2E ACC F+! ACC F?");
    try machine.interpretLine("3.1415926535E FCONSTANT MYPI : AREA FDUP F* MYPI F* ; 5E AREA F.");
    try machine.interpretLine("3 FARRAY POINTS 1.25E 2 POINTS FA! 2 POINTS FA@ F. HERE 0 FLOAT+ 2 FLOATS");
    try machine.interpretLine(": HALF 0.5E F* ; 3E HALF F. HERE 6.5E F, F@ F.");

    try std.testing.expectEqualStrings("37.5 3.5 78.5398163375 1.25 1.5 6.5 ", output.written());
    try std.testing.expectEqual(@as(usize, 3), machine.data_depth);
    try std.testing.expectEqual(@as(forth.Cell, 8), machine.data_stack[1]);
    try std.testing.expectEqual(@as(forth.Cell, 16), machine.data_stack[2]);
}

test "float stack underflow is reported and both stacks are reset" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try std.testing.expectError(error.FloatStackUnderflow, machine.interpretLine("1 1E F+"));
    machine.report(error.FloatStackUnderflow);
    try expectStack(machine, &.{});
    try expectFloatStack(machine, &.{});
    try std.testing.expectEqualStrings("FLOATING-POINT STACK UNDER FLOW !\n", output.written());
}

test "FINPUT reads a float and INPUT reads a 64-bit integer" {
    var output = Output{};
    output.input_lines[0] = "abc";
    output.input_lines[1] = "2.5";
    output.input_lines[2] = "-9000000000";
    output.input_count = 3;
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("FINPUT INPUT");

    const expected = [_]forth.Cell{-9000000000};
    try expectStack(machine, &expected);
    const floats = [_]forth.Float{2.5};
    try expectFloatStack(machine, &floats);
    try std.testing.expectEqualStrings(" ?\n", output.written());
}

test "dictionary image round trip relocates words, floats, values, and strings" {
    var output = Output{};
    const source = try createMachine(&output);
    defer destroyMachine(source);
    try source.interpretLine("2.5E FCONSTANT RATE 4 VALUE COUNTER VARIABLE V 11 V ! 70000000000000000000. 2CONSTANT HUGE");
    try source.interpretLine(": SCALE RATE F* ; : BUMP COUNTER 1+ TO COUNTER ; : SAY \" HI\" TYPE ;");
    const image = try std.testing.allocator.alloc(u8, forth.State.imageCapacity());
    defer std.testing.allocator.free(image);
    const length = try source.encodeImage(image);

    const loaded = try createMachine(&output);
    defer destroyMachine(loaded);
    try loaded.restoreImage(image[0..length]);

    const target = try createMachine(&output);
    defer destroyMachine(target);
    try target.interpretLine("VARIABLE FIRST 1 FIRST ! : EARLIER 1 ;");
    try target.appendImage(loaded);
    try target.interpretLine("2E SCALE F. BUMP COUNTER V @ FIRST @ SAY HUGE D.");

    const expected = [_]forth.Cell{ 5, 11, 1 };
    try expectStack(target, &expected);
    try std.testing.expectEqualStrings("5. HI70000000000000000000 ", output.written());
}

test "F>STR-RDP matches gforth's output for fixed, exponential, and overflowing fields" {
    const cases = [_]struct { []const u8, []const u8 }{
        .{ "12.3456789E 7 3 1", " 12.346" },       .{ "12.3456789E 7 4 1", "12.3457" },  .{ "-12.3456789E 7 4 1", "-1.23E1" },
        .{ "0.0996E 7 3 1", "  0.100" },           .{ "0.0996E 7 3 3", "9.96E-2" },      .{ "999.9994E 7 3 1", "999.999" },
        .{ "999.9996E 7 3 1", "1.000E3" },         .{ "-1E-20 5 2 1", "*****" },         .{ "12345.6789E 10 2 7", "  12345.68" },
        .{ "12345.6789E 10 2 8", "1.234568E4" },   .{ "0E 7 3 1", "  0.000" },           .{ "-0E 7 3 1", " -0.000" },
        .{ "1E 0E F/ 7 3 1", "infinit" },          .{ "-1E 0E F/ 7 3 1", "-infini" },    .{ "0E 0E F/ 7 3 1", "NaN    " },
        .{ "1E-20 5 2 1", "1E-20" },               .{ "1E-5 7 3 1", "1.00E-5" },         .{ "1E-5 7 3 0", "  0.000" },
        .{ "1.5E300 7 2 1", "1.5E300" },           .{ "123456E 6 0 0", "1.23E5" },       .{ "2.5E 5 0 1", "   2." },
        .{ "3.5E 5 0 1", "   4." },                .{ "3.14159E 4 3 1", "3.E0" },        .{ "0.5E 4 3 1", ".500" },
        .{ "-0.5E 5 3 1", "-.500" },               .{ "3.14159E 10 2 11", "3.141590E0" }, .{ "2.675E 6 2 1", "  2.67" },
        .{ "0.95E 5 1 0", "  0.9" },               .{ "1E 1 0 0", "*" },                 .{ "9.99E 3 1 1", "1E1" },
        .{ "1E-100 7 0 1", "1.E-100" },            .{ "0.0005E 7 3 0", "  0.000" },      .{ "0.0006E 7 3 0", "  0.001" },
        .{ "0.05E 5 1 0", "  0.0" },               .{ "0.000123E 10 6 2", "  0.000123" }, .{ "-100E 3 0 1", "***" },
        // Rounding that shortens the exponent, adds a digit, or makes np reachable.
        .{ "9.999E-10 4 2 1", "1E-9" },            .{ "-0.9999E 4 2 1", "-1E0" },     .{ "0.09999E 4 2 2", "0.10" },
        .{ "9.999E-100 5 2 1", "1E-99" },          .{ "9.999E-100 6 2 1", "1.E-99" }, .{ "99.996E 5 2 1", "1.0E2" },
        .{ "99.996E 6 2 1", "100.00" },            .{ "-99.996E 6 2 1", "-1.0E2" },   .{ "0.96E 2 1 0", "**" },
        // Zero has one integer digit; a tiny value rounded up loses a unit that does not fit.
        .{ "0E 4 3 1", "0.E0" },                   .{ "-0E 5 3 1", "-0.E0" },         .{ "0E 3 3 1", "0E0" },
        .{ "-0E 6 3 1", "-0.000" },                .{ "0.7E 1 0 0", "." },            .{ "-0.7E 2 0 0", "-." },
        .{ "0.7E 2 0 0", "1." },                   .{ "0.0007E 4 3 0", ".001" },
        // log10 overestimates the exponent of these; rounding there would lose a digit.
        .{ "9.999999999999998E34 20 0 0", "9.999999999999998E34" }, .{ "9.999999999999998E-10 21 0 1", "9.999999999999999E-10" },
    };
    for (cases) |case| {
        var output = Output{};
        const machine = try createMachine(&output);
        defer destroyMachine(machine);
        var line: [80]u8 = undefined;
        try machine.interpretLine(try std.fmt.bufPrint(&line, "{s} F>STR-RDP TYPE", .{case[0]}));
        std.testing.expectEqualStrings(case[1], output.written()) catch |err| {
            std.debug.print("case: {s}\n", .{case[0]});
            return err;
        };
    }
}

test "F.RDP prints, F>BUF-RDP fills a buffer, and the book's Level 20 examples hold" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("12345.6789E 10 2 7 F.RDP 12345.6789E 10 2 8 F.RDP PI 10 2 0 F.RDP");
    try machine.interpretLine("CREATE BUF 50 ALLOT BUF 50 ERASE PI BUF 10 4 0 F>BUF-RDP BUF 10 TYPE PI 0 2 0 F>STR-RDP NIP PI 0 0 0 F.RDP");
    try std.testing.expectEqualStrings("  12345.681.234568E4      3.14    3.1416", output.written());
    try expectStack(machine, &.{0});
    try std.testing.expectError(error.StringTooLong, machine.interpretLine("1E 5000 2 0 F.RDP"));
    machine.report(error.StringTooLong);
    try std.testing.expectError(error.PicturedNumericOverflow, machine.interpretLine("123. <# #S 1E 4096 2 0 F>STR-RDP"));
}

test "F.RDP and F>BUF-RDP show a value whose exponent shortens when rounded" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("CREATE BUF 8 ALLOT BUF 8 88 FILL 9.999E-10 BUF 1+ 4 2 1 F>BUF-RDP BUF 8 TYPE 9.999E-10 4 2 1 F.RDP");
    try std.testing.expectEqualStrings("X1E-9XXX1E-9", output.written());
    try expectStack(machine, &.{});
}

test "[ while interpreting, PI, and F. rounded from the exact binary value" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("[ 1 . : X [ 2 . ] 3 ; X .");
    try machine.interpretLine("PI F. PI 10 4 0 F.RDP");
    // The shortest forms end in 5 (1.414213562373095, 0.5463024898437905); the exact values round down.
    try machine.interpretLine("1.4142135623730949E F. 0.5E FTAN F. 1E 3E F/ F.S");
    try std.testing.expectEqualStrings("1 2 3 3.14159265358979     3.14161.41421356237309 0.54630248984379 <1> 3.333333333E-1 ", output.written());
}

test ".S and F.S show the top nine items, and F.S shows zero, infinity, and NaN as gforth does" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("1E 2E 0E -0E 1E 0E F/ 0E 0E F/ 5E-324 -1.7976931348623157E308 1E-300 2E F.S");
    try machine.interpretLine("1 2 3 4 5 6 7 8 9 10 11 12 .S");
    try std.testing.expectEqualStrings("<10> 2.0000000000E0 0.0000000000E0 -0.000000000E0 infinity       NaN            4.9406565E-324 -1.7976931E308 1.0000000E-300 2.0000000000E0 <12> 4 5 6 7 8 9 10 11 12 ", output.written());
}

test "FSIN FCOS FTAN FEXP FLN are correctly rounded, as the original gforth in Linux gets them from glibc" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    // Values where the Windows gforth (UCRT) and Zig's builtins are one bit off.
    try machine.interpretLine("8.455291201133988E FSIN 4.097339611316615E FCOS -3.790540510731324E FTAN 7.5804220383449845E 10E F/ FEXP");
    try machine.interpretLine("0.7853981634E FSIN 2E FLN 1E 0E F/ FSIN");
    const expected = [_]forth.Float{ 0x1.a63160a19e355p-1, -0x1.276c6481934a7p-1, -0x1.846014ab289adp-1, 0x1.1129fe0eea6f9p+1, 0x1.6a09e667f7b49p-1, 0x1.62e42fefa39efp-1 };
    try std.testing.expectEqual(@as(usize, expected.len + 1), machine.float_depth);
    for (expected, machine.float_stack[0..expected.len]) |want, got| {
        try std.testing.expectEqual(@as(u64, @bitCast(want)), @as(u64, @bitCast(got)));
    }
    try std.testing.expect(std.math.isNan(machine.float_stack[expected.len]));
}

test "math functions match the original gforth at large arguments, range limits, subnormals, and non-finite values" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    // Expected bits are the original gforth's (glibc) and CORE-MATH's, which agree here.
    try machine.interpretLine("1E300 FSIN 1E300 FCOS 1E300 FTAN -1E300 FSIN 1E22 FSIN 1E22 FCOS");
    try machine.interpretLine("709.782712893384E FEXP 709.7827128933841E FEXP -745E FEXP -746E FEXP -708.4E FEXP");
    try machine.interpretLine("5E-324 FLN 5E-324 FSIN 5E-324 FTAN 1.0000000000000002E FLN 0.9999999999999999E FLN");
    try machine.interpretLine("2.2250738585072014E-308 FLN 1.7976931348623157E308 FLN");
    const expected = [_]u64{
        0xBFEA2C16B010E385, 0xBFE2699022ADC4C1, 0x3FF6BE411F37AC77, 0x3FEA2C16B010E385, 0xBFEB453AB76BF397, 0x3FE0BE2CEF01C8F4,
        0x7FEFFFFFFFFFFF2A, 0x7FF0000000000000, 0x0000000000000001, 0x0000000000000000, 0x000FF15B469EDF89,
        0xC0874385446D71C3, 0x0000000000000001, 0x0000000000000001, 0x3CAFFFFFFFFFFFFF, 0xBCA0000000000000,
        0xC086232BDD7ABCD2, 0x40862E42FEFA39EF,
    };
    try std.testing.expectEqual(expected.len, machine.float_depth);
    for (expected, machine.float_stack[0..expected.len]) |want, got| try std.testing.expectEqual(want, @as(u64, @bitCast(got)));

    // A NaN argument comes back unchanged (quiet); infinity gives the CPU's default NaN,
    // not CORE-MATH's all-ones NaN.
    try machine.interpretLine(": FCLEAR FDEPTH 0 ?DO FDROP LOOP ; FCLEAR CREATE BB 8 ALLOT");
    try machine.interpretLine("HEX 7FF8000000001234 BB ! BB F@ FSIN FFF8000000005678 BB ! BB F@ FTAN DECIMAL");
    // The default NaN comes from the CPU at run time, as the interpreter computes it.
    try machine.interpretLine("1E 0E F/ FSIN 1E 0E F/ FCOS -1E 0E F/ FTAN 1E 0E F/ FDUP F-");
    const default_nan: u64 = @bitCast(machine.float_stack[5]);
    machine.float_depth -= 1;
    const nans = [_]u64{ 0x7FF8000000001234, 0xFFF8000000005678, default_nan, default_nan, default_nan };
    try std.testing.expectEqual(nans.len, machine.float_depth);
    for (nans, machine.float_stack[0..nans.len]) |want, got| try std.testing.expectEqual(want, @as(u64, @bitCast(got)));
    try std.testing.expect(default_nan != 0xFFFFFFFFFFFFFFFF);
}

test ".S and F.S at depth zero, at exactly nine items, and in hexadecimal" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine(".S F.S 1 2 3 4 5 6 7 8 9 .S 10 HEX .S DECIMAL");
    try machine.interpretLine("1E 2E 3E 4E 5E 6E 7E 8E 9E F.S 10E HEX F.S DECIMAL");
    try std.testing.expectEqualStrings("<0> <0> <9> 1 2 3 4 5 6 7 8 9 <A> 2 3 4 5 6 7 8 9 A " ++
        "<9> 1.0000000000E0 2.0000000000E0 3.0000000000E0 4.0000000000E0 5.0000000000E0 6.0000000000E0 7.0000000000E0 8.0000000000E0 9.0000000000E0 " ++
        "<A> 2.0000000000E0 3.0000000000E0 4.0000000000E0 5.0000000000E0 6.0000000000E0 7.0000000000E0 8.0000000000E0 9.0000000000E0 1.0000000000E1 ", output.written());
}
