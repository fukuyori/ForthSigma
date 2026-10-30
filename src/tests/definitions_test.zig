//! Tests of defining words in definitions, ', >BODY, and LITERAL.

const std = @import("std");
const forth = @import("../forth.zig");
const support = @import("support.zig");
const Output = support.Output;
const setFakeFile = support.setFakeFile;
const createMachine = support.createMachine;
const destroyMachine = support.destroyMachine;
const expectStack = support.expectStack;

test "defining words compiled into a definition read their name when it runs" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine(": V VARIABLE ; V AA 5 AA ! AA @ . : C CONSTANT ; 7 C BB BB . : FV FVARIABLE ; FV CC 2E CC F! CC F@ F.");
    try machine.interpretLine(": FC FCONSTANT ; 3E FC DD DD F. : VL VALUE ; 9 VL GG GG . 4 TO GG GG . : D2 2CONSTANT ; 1. D2 HH HH D.");
    try machine.interpretLine(": V2 2VARIABLE ; V2 II 3. II 2! II 2@ D. : AR ARRAY ; 3 AR JJ 8 1 JJ A! 1 JJ A@ .");
    // Level 31 of the book: a word that starts a definition and one that ends it.
    try machine.interpretLine(": DEFINE-FUNCTION : ; : END-FUNCTION POSTPONE ; ; IMMEDIATE");
    try machine.interpretLine("DEFINE-FUNCTION SQUARE FDUP F* END-FUNCTION 3E SQUARE F.");
    try std.testing.expectEqualStrings("5 7 2. 3. 9 4 1 3 8 9. ", output.written());
    try expectStack(machine, &.{});
    try std.testing.expectError(error.InvalidDefinition, machine.interpretLine("V"));
    try std.testing.expectError(error.InvalidDefinition, machine.interpretLine(": START : ; IMMEDIATE : OUTER START INNER ;"));
}

test "defining words follow the search order, a variable takes DOES>, and F. keeps every digit" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine(": PROBE ONLY S\" VARIABLE AA\" EVALUATE ; ' PROBE CATCH FORTH . [DEFINED] AA .");
    try machine.interpretLine(": V VARIABLE DOES> @ ; V BB BB . : USEIT BB ; USEIT . : FV FVARIABLE DOES> F@ ; FV FF FF F.");
    try machine.interpretLine(": V2 2VARIABLE DOES> 2@ ; V2 DD DD D. 9.99999999999995E34 F.");
    try std.testing.expectEqualStrings("-13 0 0 0 0. 0 99999999999999500000000000000000000. ", output.written());
    try expectStack(machine, &.{});
}

test ">BODY gives the data area, and ' in a definition reads its name when the definition runs" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("VARIABLE V 11 V ! ' V >BODY @ . 2VARIABLE D 1. D 2! ' D >BODY 2@ D. FVARIABLE F 2E F F! ' F >BODY F@ F.");
    try machine.interpretLine("7 VALUE W ' W >BODY @ . 3. 2CONSTANT DC ' DC >BODY 2@ D. : MK CREATE , DOES> @ ; 9 MK M ' M >BODY @ .");
    // Level 31 of the book: a word that reads a variable's name when it runs.
    try machine.interpretLine(": RT ' >BODY @ ; RT V . : READ-NEXT ' ; READ-NEXT DUP ' DUP = . : TK ['] DUP ; TK ' DUP = .");
    try machine.interpretLine("' V EXECUTE ' V >BODY = . '");
    try machine.interpretLine("V ' V = .");
    try std.testing.expectEqualStrings("11 1 2. 7 3 9 11 -1 -1 -1 -1 ", output.written());
    try expectStack(machine, &.{});
    try std.testing.expectError(error.InvalidExecutionToken, machine.interpretLine("5 CONSTANT K ' K >BODY"));
    try std.testing.expectError(error.InvalidExecutionToken, machine.interpretLine(": SQ DUP * ; ' SQ >BODY"));
    try std.testing.expectError(error.InvalidExecutionToken, machine.interpretLine("' DUP >BODY"));
    try std.testing.expectError(error.InvalidDefinition, machine.interpretLine("RT"));
}

test "LITERAL and FLITERAL compile a value, as the book's Level 31 DSL uses them" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine(": SIX [ 2 3 * ] LITERAL ; SIX . : AREA FDUP F* [ 3.14159265358979E 2.0E F* ] FLITERAL F* 2.0E F/ ; 2E AREA F.");
    try machine.interpretLine("TRUE CONSTANT DEBUG : PROCESS [ DEBUG ] LITERAL IF 1 . THEN 2 * ; 5 PROCESS . : T2 [ ' DUP ] LITERAL EXECUTE ; 7 T2 . .");
    // Words that compile a variable's address or a word's xt where they are used.
    try machine.interpretLine(": PUT ' >BODY STATE @ IF POSTPONE LITERAL POSTPONE F! ELSE F! THEN ; IMMEDIATE");
    try machine.interpretLine(": (AT) EXECUTE F. ; : AT ' STATE @ IF POSTPONE LITERAL POSTPONE (AT) ELSE (AT) THEN ; IMMEDIATE");
    try machine.interpretLine("FVARIABLE X 1.5E PUT X X F@ F. : SQ FDUP F* ; : RUN 3E PUT X X F@ AT SQ ; RUN 4E AT SQ");
    try std.testing.expectEqualStrings("6 12.5663706143592 1 10 7 7 1.5 9. 16. ", output.written());
    try expectStack(machine, &.{});
    try std.testing.expectError(error.CompileOnly, machine.interpretLine("5 LITERAL"));
    try std.testing.expectError(error.CompileOnly, machine.interpretLine("1E FLITERAL"));
}

test "' follows the search order and reads its name across input boundaries" {
    var output = Output{};
    setFakeFile(&output, 0, "'\nDUP ' DUP = .\n: Q ' ;\nQ\nSWAP ' SWAP = .\n");
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("VOCABULARY V ALSO V DEFINITIONS : ' 99 ; PREVIOUS DEFINITIONS ALSO V ' . PREVIOUS ' DUP ' DUP = .");
    try machine.interpretLine("S\" '\" FIND-NAME 0<> . : PT POSTPONE ' ; IMMEDIATE : RT PT ; RT DUP ' DUP = .");
    // Q reads the name after it when it runs, here inside CATCH.
    try machine.interpretLine(": Q ' ; ' Q CATCH DUP . ' DUP = .");
    try machine.interpretLine("INCLUDE a.txt");
    try std.testing.expectEqualStrings("WARNING: SAME NAME WORD EXISTS\n99 -1 -1 -1 0 -1 -1 WARNING: SAME NAME WORD EXISTS\n-1 ", output.written());
    try expectStack(machine, &.{});
    // An EVALUATE string ends the input: a ' at its end has no name to read.
    try std.testing.expectError(error.InvalidDefinition, machine.interpretLine("S\" '\" EVALUATE"));
    try std.testing.expectError(error.InvalidDefinition, machine.interpretLine("S\" Q\" EVALUATE"));
}

test ">BODY of ARRAY and plain CREATE words, and the words without a data area" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("3 ARRAY A ' A >BODY A = . CREATE C ' C >BODY C = . HERE ' C >BODY = .");
    try std.testing.expectEqualStrings("-1 -1 -1 ", output.written());
    try std.testing.expectError(error.InvalidExecutionToken, machine.interpretLine("MARKER MM ' MM >BODY"));
    try std.testing.expectError(error.InvalidExecutionToken, machine.interpretLine("VOCABULARY VV ' VV >BODY"));
    try std.testing.expectError(error.InvalidExecutionToken, machine.interpretLine(":NONAME 1 ; >BODY"));
    try std.testing.expectError(error.InvalidExecutionToken, machine.interpretLine("1E FCONSTANT FC ' FC >BODY"));
    try std.testing.expectError(error.InvalidExecutionToken, machine.interpretLine("12345 >BODY"));
}

test "LITERAL takes one cell at a time and fails without a value or outside a definition" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine(": DD [ 123. ] LITERAL LITERAL ; DD . .");
    try std.testing.expectEqualStrings("123 0 ", output.written());
    try std.testing.expectError(error.StackUnderflow, machine.interpretLine(": EMPTY LITERAL ;"));
    machine.report(error.StackUnderflow);
    try std.testing.expectError(error.FloatStackUnderflow, machine.interpretLine(": EMPTYF FLITERAL ;"));
    machine.report(error.FloatStackUnderflow);
    try std.testing.expectError(error.CompileOnly, machine.interpretLine(": BRACKET [ 5 LITERAL ] ;"));
}

test "an execution token compiled by ['] is relocated by LOAD, one compiled by LITERAL is not" {
    var output = Output{};
    const source = try createMachine(&output);
    defer destroyMachine(source);
    try source.interpretLine(": TARGET 123 ; : A ['] TARGET EXECUTE ; : B [ ' TARGET ] LITERAL EXECUTE ;");
    const image = try std.testing.allocator.alloc(u8, forth.State.imageCapacity());
    defer std.testing.allocator.free(image);
    const length = try source.encodeImage(image);

    const target = try createMachine(&output);
    defer destroyMachine(target);
    try target.interpretLine(": EARLIER 1 ;");
    const loaded = try createMachine(&output);
    defer destroyMachine(loaded);
    try loaded.restoreImage(image[0..length]);
    try target.appendImage(loaded);
    // LITERAL compiled the number TARGET had when it was saved, which is EARLIER here.
    try target.interpretLine("A B");
    try expectStack(target, &.{ 123, 1 });
}
