//! Tests of word lists, the search order, and conditional compilation.

const std = @import("std");
const forth = @import("../forth.zig");
const support = @import("support.zig");
const Output = support.Output;
const setFakeFile = support.setFakeFile;
const createMachine = support.createMachine;
const destroyMachine = support.destroyMachine;
const expectStack = support.expectStack;

test "VOCABULARY ONLY ALSO DEFINITIONS and ORDER follow the book's Level 16 example" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("ORDER CR VOCABULARY MY-WORDS ONLY FORTH ALSO MY-WORDS DEFINITIONS : HELLO .\" Hello\" ; ORDER CR");
    try std.testing.expectError(error.UnknownWord, machine.interpretLine("ONLY FORTH HELLO"));
    machine.report(error.UnknownWord);
    try machine.interpretLine("ORDER CR DEFINITIONS ORDER CR ONLY FORTH ALSO MY-WORDS HELLO CR ONLY ORDER FORTH CR SEE MY-WORDS");
    try std.testing.expectEqualStrings(
        "Forth Forth Root     Forth \nMY-WORDS Forth Root     MY-WORDS \nHELLO ?\n" ++
            "Forth Root     MY-WORDS \nForth Root     Forth \nHello\nRoot Root     Forth \nVOCABULARY MY-WORDS\n",
        output.written(),
    );
}

test "WORDLIST SET-CURRENT and >ORDER build modules and shadow words by order" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("WORDLIST CONSTANT MATH MATH SET-CURRENT : ADD2 2 + ; : SQUARE DUP * ; DEFINITIONS");
    try machine.interpretLine("WORDLIST CONSTANT IO IO SET-CURRENT : SHOW .\" Result: \" . ; DEFINITIONS MATH >ORDER IO >ORDER");
    try machine.interpretLine(": MAIN { x -- } x ADD2 SQUARE SHOW ; 3 MAIN ORDER ONLY FORTH");
    try machine.interpretLine("WORDLIST CONSTANT W1 WORDLIST CONSTANT W2 W1 SET-CURRENT : PRINT .\" W1\" ; W2 SET-CURRENT : PRINT .\" W2\" ;");
    try machine.interpretLine("W1 >ORDER W2 >ORDER PRINT ONLY FORTH W2 >ORDER W1 >ORDER PRINT ONLY FORTH DEFINITIONS");
    try std.testing.expectEqualStrings("Result: 25 IO MATH Forth Forth Root     Forth W2W1", output.written());
    try std.testing.expectError(error.UnknownWord, machine.interpretLine("3 ADD2"));
}

test "GET-ORDER SET-ORDER PREVIOUS and the search order limits" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("GET-ORDER WORDLIST SWAP 1+ SET-ORDER GET-ORDER NIP NIP NIP NIP PREVIOUS GET-ORDER");
    try expectStack(machine, &.{ 4, 2, 1, 1, 3 });
    machine.data_depth = 0;
    try machine.interpretLine("GET-CURRENT -1 SET-ORDER GET-ORDER FORTH-WORDLIST");
    try expectStack(machine, &.{ 1, 2, 2, 2, 1 });
    machine.data_depth = 0;
    try std.testing.expectError(error.SearchOrderOverflow, machine.interpretLine("ONLY FORTH : FILL-ORDER 15 0 DO FORTH-WORDLIST >ORDER LOOP ; FILL-ORDER"));
    machine.report(error.SearchOrderOverflow);
    try machine.interpretLine(": EP 0 SET-ORDER ['] PREVIOUS CATCH -1 SET-ORDER FORTH ; EP");
    try expectStack(machine, &.{-50});
    machine.data_depth = 0;
    try std.testing.expectError(error.InvalidWordlist, machine.interpretLine("99 SET-CURRENT"));
    machine.report(error.InvalidWordlist);
    try std.testing.expectError(error.InvalidWordlist, machine.interpretLine("0 >ORDER"));
}

test "WORDS lists the first word list and SEARCH-WORDLIST searches one list" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("VOCABULARY V V DEFINITIONS : ONE 1 ; : TWO 2 ; IMMEDIATE WORDS");
    try std.testing.expectEqualStrings("ONE TWO \n", output.written());
    try machine.interpretLine("S\" TWO\" GET-CURRENT SEARCH-WORDLIST NIP S\" TWO\" FORTH-WORDLIST SEARCH-WORDLIST S\" DUP\" FORTH-WORDLIST SEARCH-WORDLIST NIP");
    try expectStack(machine, &.{ 1, 0, -1 });
}

test "[IF] [ELSE] [THEN] select input, nest, span lines, and work while compiling" {
    var output = Output{};
    output.input_lines[0] = "  skipped words";
    output.input_lines[1] = "[ELSE] 7 [THEN] 8";
    output.input_count = 2;
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("1 [IF] 1 [ELSE] 2 [THEN] 0 [IF] 3 [IF] 4 [THEN] [ELSE] 5 [THEN] : T [ 0 ] [IF] 10 [ELSE] 20 [THEN] ; T");
    try machine.interpretLine("[DEFINED] DUP [UNDEFINED] DUP [DEFINED] NOSUCH 0 [IF]");
    try expectStack(machine, &.{ 1, 5, 20, -1, 0, 0, 7, 8 });
    try std.testing.expectError(error.ControlMismatch, machine.interpretLine("S\" 0 [IF] 1\" EVALUATE"));
}

test "MARKER restores the search order and the current word list" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("MARKER M VOCABULARY V ALSO V DEFINITIONS : X ; M ORDER");
    try std.testing.expectEqualStrings("Forth Forth Root     Forth ", output.written());
    try machine.interpretLine("S\" X\" FIND-NAME S\" V\" FIND-NAME");
    try expectStack(machine, &.{ 0, 0 });
}

test "word lists and the search order survive image restore and LOAD renumbers them" {
    var output = Output{};
    const source = try createMachine(&output);
    defer destroyMachine(source);
    try source.interpretLine("VOCABULARY TOOLS ALSO TOOLS DEFINITIONS : TOOL 7 ; MARKER M ONLY FORTH DEFINITIONS");
    const image = try std.testing.allocator.alloc(u8, forth.State.imageCapacity());
    defer std.testing.allocator.free(image);
    const length = try source.encodeImage(image);

    const loaded = try createMachine(&output);
    defer destroyMachine(loaded);
    try loaded.restoreImage(image[0..length]);
    try loaded.interpretLine("ALSO TOOLS TOOL ORDER");

    const target = try createMachine(&output);
    defer destroyMachine(target);
    try target.interpretLine("VOCABULARY MINE ALSO MINE DEFINITIONS : OWN 1 ; ONLY FORTH DEFINITIONS");
    const restored = try createMachine(&output);
    defer destroyMachine(restored);
    try restored.restoreImage(image[0..length]);
    try target.appendImage(restored);
    try target.interpretLine("ALSO TOOLS TOOL ALSO MINE OWN M ORDER");
    try expectStack(loaded, &.{7});
    try expectStack(target, &.{ 7, 1 });
    try std.testing.expectEqualStrings("TOOLS Forth Root     Forth TOOLS Forth Forth Root     TOOLS ", output.written());
}

test "a MARKER made in reclaimed data space survives LOAD with old values in its unused slots" {
    var output = Output{};
    const source = try createMachine(&output);
    defer destroyMachine(source);
    try source.interpretLine("VOCABULARY TOOLS HERE CONSTANT A CREATE OLD 152 ALLOT 9223372036854775807 A 144 + ! FORGET OLD MARKER M A 144 + @");
    try expectStack(source, &.{0});
    source.data_depth = 0;
    const image = try std.testing.allocator.alloc(u8, forth.State.imageCapacity());
    defer std.testing.allocator.free(image);
    const length = try source.encodeImage(image);
    const loaded = try createMachine(&output);
    defer destroyMachine(loaded);
    try loaded.restoreImage(image[0..length]);

    const target = try createMachine(&output);
    defer destroyMachine(target);
    try target.interpretLine("VOCABULARY MINE");
    try target.appendImage(loaded);
    try target.interpretLine("ALSO TOOLS M ORDER");
    try std.testing.expectEqualStrings("Forth Forth Root     Forth ", output.written());
}

test "[DEFINED] and [UNDEFINED] see local variables while compiling" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine(": T { x -- } [DEFINED] x [IF] x [ELSE] 99 [THEN] ; 7 T");
    try machine.interpretLine(": U { x -- } [UNDEFINED] x [IF] 99 [ELSE] x 1+ [THEN] ; 7 U");
    try machine.interpretLine(": DUP2 { DUP } [DEFINED] DUP [IF] DUP [THEN] ; 5 DUP2");
    try machine.interpretLine(": MK CREATE { y } DOES> DROP [DEFINED] y [IF] 1 [ELSE] 2 [THEN] ; 3 MK THING THING");
    try expectStack(machine, &.{ 7, 8, 5, 2 });
}

test "[IF] skipping inside an included file reads further lines and fails at its end" {
    var output = Output{};
    setFakeFile(&output, 0, "0 [IF]\n  skipped\n  lines\n[ELSE] 1\n[THEN] 2\n");
    setFakeFile(&output, 1, "0 [IF]\nnever closed\n");
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("INCLUDE a.txt");
    try expectStack(machine, &.{ 1, 2 });
    try std.testing.expectError(error.ControlMismatch, machine.interpretLine("INCLUDE b.txt"));
    machine.report(error.ControlMismatch);
    try std.testing.expectEqualStrings("b.txt:2: CONTROL STRUCTURE ERROR !\n", output.written());
    try machine.interpretLine("S\" b.txt\" ' INCLUDED CATCH NIP NIP 3");
    try expectStack(machine, &.{ -22, 3 });
    for (output.files) |file| try std.testing.expect(!file.open);
}

test "[IFDEF] [IFUNDEF] [ENDIF] and the interpreted loops work as in gforth" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("[IFDEF] DUP 1 [ELSE] 2 [THEN] [IFDEF] NOSUCH 3 [ELSE] 4 [ENDIF] [IFUNDEF] NOSUCH 5 [THEN] [IFUNDEF] DUP 6 [THEN]");
    try expectStack(machine, &.{ 1, 4, 5 });
    machine.data_depth = 0;
    try machine.interpretLine("3 0 [DO] [I] [LOOP] 0 0 [?DO] 99 [LOOP] 10 0 [DO] [I] 3 [+LOOP] 0 3 [DO] [I] -1 [+LOOP]");
    try expectStack(machine, &.{ 0, 1, 2, 0, 3, 6, 9, 3, 2, 1, 0 });
    machine.data_depth = 0;
    try machine.interpretLine("2 0 [DO] 2 0 [DO] [I] [LOOP] [LOOP] 2 [FOR] [I] [NEXT] 0 [FOR] [I] [NEXT]");
    try expectStack(machine, &.{ 0, 1, 0, 1, 2, 1, 0, 0 });
    machine.data_depth = 0;
    try machine.interpretLine("VARIABLE N 0 N ! [BEGIN] N @ 1 N +! N @ 3 = [UNTIL] 0 N ! [BEGIN] N @ 2 < [WHILE] N @ 10 + 1 N +! [REPEAT] N @");
    try expectStack(machine, &.{ 0, 1, 2, 10, 11, 2 });
    machine.data_depth = 0;
    try machine.interpretLine(": T [ 2 0 [DO] [I] ] LITERAL [ [LOOP] ] ; T S\" 2 0 [DO] [I] [LOOP]\" EVALUATE");
    try expectStack(machine, &.{ 0, 1, 0, 1 });
    try std.testing.expectError(error.ControlMismatch, machine.interpretLine("[LOOP]"));
    try std.testing.expectError(error.ControlMismatch, machine.interpretLine("[I]"));
}

test "CATCH ends the interpreted loops started in the caught word" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine(": BAD S\" 3 0 [DO] -99 THROW [LOOP]\" EVALUATE ; ' BAD CATCH");
    try expectStack(machine, &.{-99});
    try std.testing.expectError(error.ControlMismatch, machine.interpretLine("[I]"));
    // An outer loop goes on with its own index.
    machine.data_depth = 0;
    try machine.interpretLine("2 0 [DO] [I] ' BAD CATCH DROP [LOOP]");
    try expectStack(machine, &.{ 0, 1 });
}

test "an interpreted loop does not go back into a later terminal line of the same length" {
    var output = Output{};
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    // The two lines have the same length and lie in the same buffer.
    try machine.interpretLine("2 0 [DO] [I] .                          ");
    try std.testing.expectError(error.ControlMismatch, machine.interpretLine("[LOOP]   99 .                           "));
    try std.testing.expectEqualStrings("0 ", output.written());
    // SAVE-INPUT on one line cannot go back from the next line either.
    machine.data_depth = 0;
    try machine.interpretLine("SAVE-INPUT                    ");
    try machine.interpretLine("RESTORE-INPUT                 ");
    try expectStack(machine, &.{-1});
}

test "an interpreted loop in an included file repeats its lines" {
    var output = Output{};
    setFakeFile(&output, 0, "3 0 [DO] [I]\n  100 +\n[LOOP] 7\n");
    setFakeFile(&output, 1, "0 0 [?DO]\n  never\n[LOOP] 8\n");
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("INCLUDE a.txt INCLUDE b.txt");
    try expectStack(machine, &.{ 100, 101, 102, 7, 8 });
}

test "WHERE lists the uses of a word in included files as gforth does" {
    var output = Output{};
    setFakeFile(&output, 0, ": SQ DUP * ;\n\t: T2\tSQ ;\n   7 SQ DROP\n: T3 SQ SQ ; \\ \u{3042}\u{3044}\u{3046}\n: LONG " ++ "SQ " ** 30 ++ ";\n");
    setFakeFile(&output, 1, "' SQ DROP CHAR SQ DROP .( SQ) \\ SQ\n[DEFINED] SQ DROP S\" SQ\" FIND-NAME DROP 0 [IF] SQ [THEN]\n");
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    // A use typed at the terminal is not recorded.
    try machine.interpretLine("INCLUDE a.txt 3 SQ DROP WHERE SQ");
    const long_line = ": LONG " ++ "SQ " ** 20 ++ "S";
    // A tab takes the columns up to the next multiple of 8 and a wide character two.
    const first_lines = "\na.txt:2:7: : T2\tSQ ;" ++ " " ** 56 ++ "0" ++
        "\na.txt:3:6: 7 SQ DROP" ++ " " ** 59 ++ "1" ++
        "\na.txt:4:6: : T3 SQ SQ ; \\ \u{3042}\u{3044}\u{3046}" ++ " " ** 47 ++ "2" ++
        "\na.txt:4:9: : T3 SQ SQ ; \\ \u{3042}\u{3044}\u{3046}" ++ " " ** 47 ++ "3" ++
        "\na.txt:5:8: " ++ long_line ++ "4" ++
        "\na.txt:5:11: " ++ long_line[0 .. long_line.len - 1] ++ "5";
    try std.testing.expectEqualStrings(first_lines, output.written()[0..first_lines.len]);
    try std.testing.expectEqual(@as(usize, 34), std.mem.count(u8, output.written(), "\n"));

    // ' [DEFINED] and FIND-NAME record a use at the last word read; CHAR, comments,
    // and skipped input do not. As in gforth, the uses in forgotten definitions stay.
    output.len = 0;
    try machine.interpretLine("INCLUDE b.txt FORGET T2 WHERE SQ");
    const written = output.written();
    try std.testing.expectEqual(@as(usize, 37), std.mem.count(u8, written, "\n"));
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, written, "\nb.txt:1:"));
    try std.testing.expect(std.mem.indexOf(u8, written, "\nb.txt:1:3: ' SQ DROP CHAR SQ DROP .( SQ) \\ SQ ") != null);
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, written, "\nb.txt:2:"));
    try std.testing.expect(std.mem.indexOf(u8, written, "\nb.txt:2:11: [DEFINED] SQ") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "\nb.txt:2:26: [DEFINED] SQ") != null);

    // A new definition of the name has uses of its own; a forgotten word has none.
    output.len = 0;
    try machine.interpretLine(": SQ 1 ; WHERE SQ");
    try std.testing.expectEqualStrings("WARNING: SAME NAME WORD EXISTS\n", output.written());
    try std.testing.expectError(error.UnknownWord, machine.interpretLine("WHERE NOSUCH"));

    // When the place alone is wider than the line, all of the text follows, as in gforth.
    const long_name = support.fake_file_names[4];
    const long_text = ": T SQ2 " ++ "SQ2 " ** 20 ++ ";";
    setFakeFile(&output, 4, ": SQ2 DUP * ;\n" ++ long_text ++ "\n");
    output.len = 0;
    try machine.interpretLine("INCLUDE " ++ long_name ++ " WHERE SQ2");
    try std.testing.expectEqualStrings("\n" ++ long_name ++ ":2:5: " ++ long_text ++ "0", output.written()[0 .. long_name.len + long_text.len + 8]);
}

test "FIND and LOCATE pick the word from the first list in the search order" {
    var output = Output{};
    setFakeFile(&output, 0, "VOCABULARY V1 VOCABULARY V2\nALSO V1 DEFINITIONS : SAME 1 ;\nV2 DEFINITIONS : SAME 2 ;\n");
    const machine = try createMachine(&output);
    defer destroyMachine(machine);

    try machine.interpretLine("INCLUDE a.txt FORTH DEFINITIONS ALSO V1 SAME : W BL WORD FIND DROP EXECUTE ; W SAME LOCATE SAME");
    try machine.interpretLine("PREVIOUS ALSO V2 SAME W SAME LOCATE SAME");
    try expectStack(machine, &.{ 1, 1, 2, 2 });
    try std.testing.expectEqualStrings("a.txt:2\nALSO V1 DEFINITIONS : SAME 1 ;\na.txt:3\nV2 DEFINITIONS : SAME 2 ;\n", output.written());
}

test "image restore keeps words of a vocabulary made with :NONAME and DOES>" {
    var output = Output{};
    const source = try createMachine(&output);
    defer destroyMachine(source);
    try source.interpretLine("VOCABULARY TOOLS ALSO TOOLS DEFINITIONS :NONAME 40 + ; CONSTANT ADDER : HOLDER CREATE , DOES> @ ; 2 HOLDER TWO");
    try source.interpretLine("FORTH DEFINITIONS PREVIOUS");
    const image = try std.testing.allocator.alloc(u8, forth.State.imageCapacity());
    defer std.testing.allocator.free(image);
    const length = try source.encodeImage(image);
    const loaded = try createMachine(&output);
    defer destroyMachine(loaded);
    try loaded.restoreImage(image[0..length]);

    try std.testing.expectError(error.UnknownWord, loaded.interpretLine("TWO"));
    loaded.report(error.UnknownWord);
    try loaded.interpretLine("ALSO TOOLS TWO ADDER EXECUTE S\" TWO\" FIND-NAME 0<> ORDER");
    try expectStack(loaded, &.{ 42, -1 });
    try std.testing.expectEqualStrings("TWO ?\nTOOLS Forth Forth Root     Forth ", output.written());
}
