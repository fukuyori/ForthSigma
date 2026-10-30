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

/// __builtin_fma as the CORE-MATH files get it (src/fma/fma_for_tests.c).
extern fn sigma_fma_for_tests(x: f64, y: f64, z: f64) f64;

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

test "tiny arguments give the same results without an FMA instruction" {
    // Without an FMA instruction CORE-MATH used the C library's fma, and on Windows FCOS
    // gave NaN and FSIN and FTAN lost the last bit for these arguments. The expected bits
    // are the original gforth's. Run the tests with -Dcpu=baseline to check that build.
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("CREATE BB 8 ALLOT HEX 0104FBDED5CFE46A BB ! BB F@ FCOS 80416FC797E7F607 BB ! BB F@ FCOS");
    try machine.interpretLine("000A45AD6D0175E3 BB ! BB F@ FSIN 800D3630CCBAC9A1 BB ! BB F@ FSIN 000916FA26F94A47 BB ! BB F@ FTAN DECIMAL 1E-300 FCOS");
    const expected = [_]u64{ 0x3FF0000000000000, 0x3FF0000000000000, 0x000A45AD6D0175E3, 0x800D3630CCBAC9A1, 0x000916FA26F94A47, 0x3FF0000000000000 };
    try std.testing.expectEqual(expected.len, machine.float_depth);
    for (expected, machine.float_stack[0..expected.len]) |want, got| try std.testing.expectEqual(want, @as(u64, @bitCast(got)));
}

fn expectFloatBits(machine: *forth.State, expected: []const u64) !void {
    try std.testing.expectEqual(expected.len, machine.float_depth);
    for (expected, machine.float_stack[0..expected.len]) |want, got| try std.testing.expectEqual(want, @as(u64, @bitCast(got)));
    machine.float_depth = 0;
}

test "the CORE-MATH functions of FASIN to F** are correctly rounded and give gforth's NaNs" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    // These agree with the original gforth bit for bit.
    try machine.interpretLine("0.5E FASIN 0.5E FACOS 1E FATAN 1E 2E FATAN2 -1E -0E FATAN2 0E -0E FATAN2 1E FSINH 1E FCOSH 1E FTANH");
    try expectFloatBits(machine, &.{ 0x3FE0C152382D7366, 0x3FF0C152382D7366, 0x3FE921FB54442D18, 0x3FDDAC670561BB4F, 0xBFF921FB54442D18, 0x400921FB54442D18, 0x3FF2CD9FC44EB982, 0x3FF8B07551D9F550, 0x3FE85EFAB514F394 });
    try machine.interpretLine("1E FASINH 1E-10 FEXPM1 1E-10 FLNP1 100E FLOG 2E FALOG 2E 0.5E F** -8E 3E F** 0E 0E F**");
    try expectFloatBits(machine, &.{ 0x3FEC34366179D427, 0x3DDB7CDFD9DDA4E3, 0x3DDB7CDFD9D1D693, 0x4000000000000000, 0x4059000000000000, 0x3FF6A09E667F3BCD, 0xC080000000000000, 0x3FF0000000000000 });
    // Where glibc is not correctly rounded, the results differ from gforth's by one
    // unit in the last place: atanh(0.5) = ln(3)/2 = 0.54930614433405484570...,
    // log1p(2) = ln 3, e - 1, and acosh(2) = ln(2 + sqrt 3) round to these.
    try machine.interpretLine("0.5E FATANH 2E FLNP1 1E FEXPM1 2E FACOSH");
    try expectFloatBits(machine, &.{ 0x3FE193EA7AAD030B, 0x3FF193EA7AAD030B, 0x3FFB7E151628AED3, 0x3FF5124271980435 });
    // Outside the domain: a positive NaN for FASIN, FACOS, and FLOG, the CPU's default NaN
    // for the others, as gforth (glibc on x86-64) gives them.
    try machine.interpretLine("2E FASIN 2E FACOS -1E FLOG");
    try expectFloatBits(machine, &.{ 0x7FF8000000000000, 0x7FF8000000000000, 0x7FF8000000000000 });
    try machine.interpretLine("1E 0E F/ FDUP F- -1E FSQRT 0.5E FACOSH -2E FATANH -2E FLNP1 -2E 0.5E F** 1E 0E F/ FSINCOS");
    const default_nan: u64 = @bitCast(machine.float_stack[0]);
    try expectFloatBits(machine, &.{ default_nan, default_nan, default_nan, default_nan, default_nan, default_nan, default_nan, default_nan });
}

test "FLOOR FTRUNC FROUND F~ FSINCOS and the SF@ DF@ and alignment words work as in gforth" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("2.5E FROUND -2.5E FROUND -0.4E FROUND 0.5E FROUND -0.5E FROUND 4503599627370497E FROUND 3.5E FROUND -1.5E FLOOR -0E FLOOR 0.5E FLOOR -1.5E FTRUNC -0.5E FTRUNC 1E 0E F/ FROUND");
    try expectFloatBits(machine, &.{ 0x4000000000000000, 0xC000000000000000, 0x8000000000000000, 0, 0x8000000000000000, 0x4330000000000001, 0x4010000000000000, 0xC000000000000000, 0x8000000000000000, 0, 0xBFF0000000000000, 0x8000000000000000, 0x7FF0000000000000 });
    try expectOutput(
        "1E 1.0000001E 1E-6 F~ . 1E 1.1E 1E-6 F~ . 1E 1E 0E F~ . 0E -0E 0E F~ . 1E 1.0000001E -1E-6 F~ . 1E 1.1E -0.01E F~ . 0E 0E F/ FDUP 0E F~ . 0E 0E F/ FDUP 1E F~ .",
        "-1 0 -1 0 -1 0 -1 0 ",
    );
    try expectOutput("1E FSINCOS F. F. 0E FSINCOS F. F.", "0.54030230586814 0.841470984807897 1. 0. ");
    try expectOutput(
        "HERE 3 ALLOT FALIGN HERE SWAP - . HERE 1 ALLOT SFALIGN HERE SWAP - . HERE 1 ALLOT DFALIGN HERE SWAP - . 5 FALIGNED . 5 SFALIGNED . 5 DFALIGNED . 3 SFLOATS . 3 DFLOATS . 10 SFLOAT+ . 10 DFLOAT+ .",
        "8 4 4 8 8 8 12 24 14 18 ",
    );
    try expectOutput(
        "CREATE SB 16 ALLOT 1.1E SB SF! SB SF@ F. SB @ 4294967295 AND HEX U. DECIMAL 1E300 SB SF! SB SF@ F. 2.5E SB DF! SB DF@ F. 1E-50 SB SF! SB SF@ F.",
        "1.10000002384186 3F8CCCCD infinity 2.5 0. ",
    );
}

test "REPRESENT gives the digits, exponent, and sign as gforth does" {
    const line = "CREATE BUF 40 ALLOT : R. ( u -- ) BUF OVER BLANK BUF SWAP 2DUP 2>R REPRESENT . . . 2R> TYPE .\" |\" ; ";
    try expectOutput(line ++ "3.14159E 5 R. -0.000123456E 4 R. 0E 5 R. -0E 3 R. 9.99999E 3 R. 1E300 6 R.", "-1 0 1 31416|-1 -1 -3 1235|-1 0 1 00000|-1 -1 1 000|-1 0 2 100|-1 0 301 100000|");
    try expectOutput(line ++ "5E-324 4 R. 2.5E 1 R. 123.456E 20 R.", "-1 0 -323 4941|-1 0 1 2|-1 0 3 12345600000000000307|");
    try expectOutput(line ++ "1E 0E F/ 5 R. -1E 0E F/ 5 R. 0E 0E F/ 5 R.", "0 0 0 infin|0 -1 0 -infi|0 0 0 NaN  |");
}

test "FE. FS. and F. follow PRECISION as in gforth" {
    try expectOutput(
        "12345.678E FE. 12345.678E FS. -0.000123E FE. -0.000123E FS. 0E FE. 0E FS. 999.9999999999999E FE. -0E FS.",
        "12.3456780000000E3 1.23456780000000E4 -123.000000000000E-6 -1.23000000000000E-4 0.00000000000000E0 0.00000000000000E0 1.00000000000000E3 -0.00000000000000E0 ",
    );
    // A non-finite value is printed by name, without a space after it, as gforth does.
    try expectOutput("1E 0E F/ FE. -1E 0E F/ FS. 0E 0E F/ FE. 5E-324 FS. 1.7976931348623157E308 FE.", "infinity-infinityNaN4.94065645841247E-324 179.769313486232E306 ");
    try expectOutput(
        "3 SET-PRECISION 12345.678E FE. 12345.678E FS. 1E 3E F/ F. 9.9999E FS. 99999E FE. PRECISION . 2.675E F.",
        "12.3E3 1.23E4 0.333 1.00E1 100.E3 3 2.67 ",
    );
    try expectOutput("1 SET-PRECISION 1E 3E F/ F. 2.5E FS. 3.5E FS. 0.95E FS. 99E FS.", "0.3 2.E0 4.E0 9.E-1 1.E2 ");
    // gforth fails for these two; padding with zeros keeps the value right.
    try expectOutput("1 SET-PRECISION 0.95E FE. 12E FE.", "900.E-3 10.E0 ");
    try expectOutput("20 SET-PRECISION 1E 3E F/ F. 1E 3E F/ FE. 0.1E F.", "0.33333333333333331483 333.33333333333331483E-3 0.10000000000000000555 ");
    // PRECISION gives back what was set; output keeps to 1 to 1000 digits.
    try expectOutput("-1 SET-PRECISION PRECISION . 1E 3E F/ F. 15 SET-PRECISION PRECISION .", "-1 0.3 15 ");
}

test "the fma that CORE-MATH uses gives the FMA instruction's results" {
    // x, y, z, and the result of the FMA instruction (computed with -mfma). Without an FMA
    // instruction, as with -Dcpu=baseline, this is musl's fma through sigma_fma.h; the
    // fma linked on Windows returned NaN for the first products that underflow. A NaN
    // result is compared as NaN only, since the CPU's default NaN differs between x86 and ARM.
    const cases = [_][4]u64{
        .{ 0x032598bc8a19195c, 0xb7ec2bb5797f5e16, 0x0000000000000000, 0x8000000000000000 },
        .{ 0x032598bc8a19195c, 0x37ec2bb5797f5e16, 0x8000000000000000, 0x0000000000000000 },
        .{ 0x9a70000000000000, 0x1a70000000000000, 0x8000000000000000, 0x8000000000000000 },
        .{ 0x0000000000000000, 0x4014000000000000, 0x8000000000000000, 0x0000000000000000 },
        .{ 0x8000000000000000, 0x4014000000000000, 0x8000000000000000, 0x8000000000000000 },
        .{ 0x8000000000000000, 0x4014000000000000, 0x0000000000000000, 0x0000000000000000 },
        .{ 0x01a56e1fc2f8f359, 0x3c80000000000000, 0x3ff0000000000000, 0x3ff0000000000000 },
        .{ 0x0000000000000001, 0x3c80000000000000, 0x3ff0000000000000, 0x3ff0000000000000 },
        .{ 0x01a56e1fc2f8f359, 0x01a56e1fc2f8f359, 0xbff0000000000000, 0xbff0000000000000 },
        .{ 0x0010000000000000, 0x3cb0000000000000, 0x0000000000000000, 0x0000000000000001 },
        .{ 0x0010000000000000, 0x3cb8000000000000, 0x0000000000000001, 0x0000000000000002 },
        .{ 0x3ff0000000000001, 0x3fefffffffffffff, 0xbff0000000000000, 0x3c9ffffffffffffe },
        .{ 0x3ff0000000000001, 0x3ff0000000000001, 0xbff0000000000002, 0x3970000000000000 },
        .{ 0x7fefffffffffffff, 0x4000000000000000, 0xffefffffffffffff, 0x7fefffffffffffff },
        .{ 0x4008000000000000, 0x4014000000000000, 0x401c000000000000, 0x4036000000000000 },
        .{ 0x7ff0000000000000, 0x4000000000000000, 0x3ff0000000000000, 0x7ff0000000000000 },
        .{ 0x7ff0000000000000, 0x4000000000000000, 0xfff0000000000000, 0xfff8000000000000 },
        .{ 0x0000000000000000, 0x7ff0000000000000, 0x3ff0000000000000, 0xfff8000000000000 },
        .{ 0x3ff0000000000000, 0x4000000000000000, 0x7ff0000000000000, 0x7ff0000000000000 },
        .{ 0x7ff8000000000000, 0x3ff0000000000000, 0x3ff0000000000000, 0x7ff8000000000000 },
    };
    for (cases) |case| {
        const got = sigma_fma_for_tests(@bitCast(case[0]), @bitCast(case[1]), @bitCast(case[2]));
        const want: f64 = @bitCast(case[3]);
        if (std.math.isNan(want)) {
            try std.testing.expect(std.math.isNan(got));
        } else try std.testing.expectEqual(case[3], @as(u64, @bitCast(got)));
    }
}

test "SF! FROUND and many-digit output at their limits, as in gforth" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    // SF! rounds to a 32-bit float: overflow to infinity, the smallest subnormal, a value
    // below half of it, a negative underflow to -0, and NaN (only checked to be a NaN: the
    // CPU's default NaN, from 0E 0E F/, is negative on x86 and positive on ARM).
    try machine.interpretLine("CREATE B 8 ALLOT : SBITS B SF! B @ 4294967295 AND ; 1E300 SBITS -1E300 SBITS -0E SBITS 1.401298464324817E-45 SBITS -1E-50 SBITS 0E 0E F/ SBITS 2147483647 AND 2139095040 > 7.006492321624085E-46 SBITS 1.1754942E-38 SBITS");
    try expectStack(machine, &.{ 0x7F800000, 0xFF800000, 0x80000000, 1, 0x80000000, -1, 0, 0x7FFFFF });
    machine.data_depth = 0;
    try machine.interpretLine("0.49999999999999994E FROUND 0.5000000000000001E FROUND 4503599627370495.5E FROUND -4503599627370495.5E FROUND -0.5000000000000001E FROUND");
    try expectFloatBits(machine, &.{ 0, 0x3FF0000000000000, 0x4330000000000000, 0xC330000000000000, 0xBFF0000000000000 });
    try machine.interpretLine("100 SET-PRECISION 0.1E FS. 101 SET-PRECISION 1E FS. 1000 SET-PRECISION 5E-324 FE.");
    const exact_tenth = "1.000000000000000055511151231257827021181583404541015625" ++ "0" ** 45 ++ "E-1 ";
    const one = "1." ++ "0" ** 100 ++ "E0 ";
    // 5e-324 is 2^-1074, whose exact decimal form has 751 significant digits.
    const smallest = "4.940656458412465441765687928682213723650598026143247644255856825006755072702087518652998363616359923797965646";
    const written = output.written();
    try std.testing.expect(std.mem.startsWith(u8, written, exact_tenth ++ one ++ smallest));
    try std.testing.expect(std.mem.endsWith(u8, written, "0" ** 249 ++ "E-324 "));
    try std.testing.expectEqual(exact_tenth.len + one.len + "4.".len + 999 + "E-324 ".len, written.len);
}

test "FVALUE pushes its float, TO stores one, and SEE shows it" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("1.5E FVALUE FV FV F. 2.5E TO FV FV F. : T 3.5E TO FV FV F. ; T ' FV >BODY F@ F. SEE FV");
    try std.testing.expectEqualStrings("1.5 2.5 3.5 3.5 3.5e FVALUE FV\n", output.written());
    try std.testing.expectError(error.FloatStackUnderflow, machine.interpretLine("TO FV"));
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
