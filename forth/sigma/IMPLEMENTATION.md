# Zig implementation notes

## Architecture

The runtime uses 64-bit cells, a separate 64-bit (IEEE binary64) floating-point stack, and a 1 MiB logical byte memory. Cell and float reads and writes use little-endian 8-byte layout. The dictionary is a bounded host-side table; colon definitions compile into a small host-independent operation stream. The operation stream represents calls, integer and float literals, branches, loops, and string output. No Z80 opcodes or machine addresses are executed.

`State` owns the interpreter and receives output through a callback. The command-line adapter uses C standard input and output so the language core does not depend on a particular terminal API. File storage, cassette commands, the PC-8001 line editor, and CP/M monitor calls are outside this scope.

The FORTH/Σ source articles define a 16-bit system. Since stage 1 of the gforth-alignment work (2026-10-28), cell width, truth values, division, output spacing, name identity, and `TYPE` follow gforth instead; see [DECISIONS.md](DECISIONS.md). FORTH/Σ-specific words that do not conflict with gforth are retained.

## Z80 listing correspondence

The June 1982 source article describes the main path used for the port:

- `START` establishes the parameter stack and system pointers.
- `READ` obtains a token, `DSRCH` searches the linked dictionary, and the numeric-check/conversion routines (`NTEST`, `CNVRT`) recognize numbers using `BASE`.
- `MAKE` adds a dictionary header for a new definition. `CCOLON` and the control-word handlers compile calls, literals, and patched branch destinations.
- `FLER` handles parse/compile errors and abandons an incomplete definition.
- The compiler emits Z80 subroutine calls and machine-code branches. This implementation preserves the language-level call and branch behavior in a host-independent operation stream instead.

These routine names and relationships come from the source-list explanation in the June–July 1982 source articles, magazine pages 92–99 and 178–185 (*Encyclopedia ASCII*, Vol. 6, No. 6–7, June–July 1982). The byte-for-byte Z80 layout is intentionally not reproduced.

## Current language support

- Stack words: `DROP`, `DUP`, `SWAP`, `OVER`, `ROT`, `-ROT`, `NIP`, `TUCK`, `PICK`, `ROLL`, `2DUP`, `2DROP`, `2SWAP`, `2OVER`, `DEPTH`, `>R`, `R>`, `R@`.
- Arithmetic and comparison: `+`, `-`, `*`, `/`, `MOD`, `/MOD`, `1+`, `1-`, `2*`, `2/`, `MINUS`/`NEGATE`, `ABS`, `MAX`, `MIN`, `=`, `<>`, `<`, `>`, `<=`, `>=`, `NOT`, `0=`, `0<`, `0>`, `0<>`, `TRUE`, `FALSE`.
- Bit operations: `AND`, `OR`, `XOR`, `COM`/`INVERT`, `NAND`, `NOR`, `SWAB`, `LSHIFT`, `RSHIFT`.
- Memory: `@`, `!`, `C@`, `C!`, `,`, `C,`, `+!`, `1+!`, `1-!`, `OSET`, `ON`, `OFF`, `?`, `A@`, `A!`, `ERASE`, `FILL`, `MOVE`, `CMOVE`, `CELL`, `CELLS`, `CELL+`, `ALIGNED`, `BL`, `HERE`, `ALLOT`, `VARIABLE`/`VAR`, `CONSTANT`/`CONST`, `VALUE`/`TO`, and `ARRAY`.
- Output, terminal input, and base selection: `.`, `U.`, `C.`, `.S`, `ECHO`/`EMIT`, `CR`, `SPACE`, `SPCES`/`SPACES`, `TYPE`, `INPUT`, `HEX`, `DEC`/`DECIMAL`, `OCT`, `BASE`, `CHAR`, `[CHAR]`, the original compile-time `"..."` string word, and the extension `."..."`.
- Compilation: `: ... ;`, `[` and `]`, `'`/`[']`, `EXECUTE`, `IMMEDIATE`, `POSTPONE`, `RECURSE`, `EXIT`, `IF ... ELSE ... THEN`, `BEGIN ... END`/`UNTIL`, `BEGIN ... AGAIN`, `BEGIN ... WHILE ... REPEAT`, `CASE ... OF ... ENDOF ... ENDCASE`, `DO ... LOOP`, `DO ... +LOOP`, `?DO`, `LEAVE`, `UNLOOP`, `I`, `J`, and `K`. Control words are immediate dictionary entries, so `POSTPONE IF` works.
- Comments: `( ... )` within one line and `\` to the end of the line.
- Defining words: `<BUILDS`/`CREATE` create a named data word from the remaining input; `DOES>` attaches the compiled behavior after it to that word.
- Strings and input: `S"`, `S\"`, `.\"`, `.( ... )`, `COUNT`, `PAD`, `ACCEPT`, `EVALUATE`, `KEY`, `KEY?`, `>NUMBER`, `S>NUMBER?`, and `>FLOAT`.
- Double-cell integers (128-bit, high cell on top): literals containing `.` (`123.`, `12.34`, `#10.`), `S>D`, `D>S`, `D+`, `D-`, `DNEGATE`, `DABS`, `D0=`, `D0<`, `D=`, `D<`, `D.`, `2@`, `2!`, `2VARIABLE`, `2CONSTANT`, `D>F`, and `F>D`.
- Pictured numeric output: `<#`, `<<#`, `#`, `#S`, `HOLD`, `HOLDS`, `SIGN`, `#>`, and `#>>`.
- Floating point: `FDROP`, `FDUP`, `FSWAP`, `FOVER`, `FROT`, `F-ROT`, `FNIP`, `FTUCK`, `FPICK`, `FDEPTH`, `F.S`, `F+`, `F-`, `F*`, `F/`, `FNEGATE`/`FMINUS`, `FABS`, `FMAX`, `FMIN`, `FSQRT`, `FEXP`, `FLN`, `FSIN`, `FCOS`, `FTAN`, `F=`, `F<>`, `F<`, `F>`, `F<=`, `F>=`, `F0=`, `F0<>`, `F0<`, `F0>`, `F0<=`, `F0>=`, `F@`, `F!`, `F,`, `FA@`, `FA!`, `F+!`, `F?`, `FLOATS`, `FLOAT+`, `S>F`, `F>S`, `F.`, `FINPUT`, `FVARIABLE`, `FCONSTANT`, and `FARRAY`.
- Source can be piped to standard input and is interpreted by the same core as interactive input.
- `SAVE filename` writes a versioned dictionary image (`SIGIMG02`). `LOAD filename` appends its user definitions to the current dictionary. Newer duplicate definitions take precedence; `FORGET` of the newer definition reveals the older one. These portable dictionary operations differ from the magazine editor-buffer commands with the same names. Images written by the 16-bit version (`SIGIMG01`) are rejected with `INVALID IMAGE !`.
- `SAVESYS image.exe` copies the running executable and appends a versioned snapshot of the dictionary, compiled operations, and memory. The generated executable restores that image at startup. With no arguments it opens the interactive prompt; command-line arguments are joined as Forth input, interpreted once, and then the process exits.
- `WORDS`, `FORGET`, and `BYE` are provided for interactive use.

## Deliberate implementation choices

### Behavior aligned with gforth

The gforth source tree (`D:\home\source\forth\gforth`, GPLv3) was read for behavior only; no gforth code is copied into this MIT-licensed project.

- Cells are 64-bit two's-complement and wrap on overflow. A true flag is `-1` (all bits set); false is `0`.
- `/`, `MOD`, and `/MOD` use floored division, matching gforth's default aliases (`kernel/main.fs`: `/f`, `modf`, `/modf`). Division by zero is an error (`DIVISION BY ZERO !`). The minimum integer divided by `-1` returns the minimum integer with remainder 0.
- Names are matched by their full length without ASCII case distinction. The FORTH/Σ five-character identity rule is no longer used.
- `.`, `U.`, `?`, and `C.` append one space. Numbers are signed in every base and are not zero-padded. `.S` prints `<depth> ` followed by each item.
- `TYPE` takes `( addr u )`. The original `"` word therefore now pushes the address followed by the length.
- `LEAVE` is compile-only and leaves the loop immediately. `UNLOOP` drops the innermost loop frame so that `EXIT` can be used inside a loop.
- Number input accepts the prefixes `$` (hex), `#` and `&` (decimal), `%` (binary), and `'c'` character literals. `BASE` may be 2 through 36.
- Floating-point literals follow gforth's `rec-float` (`float.fs`): `BASE` must be decimal and the token must contain `e` or `E` (`1E`, `1.5e0`, `.5E`, `-2.25E+1`, `0.e`).
- Integers containing a `.` anywhere among their digits are double-cell numbers, following gforth's `s>unumber?` (`kernel/int.fs`): `1.5` is the double 15 and `12345.123` is 12345123. The position of the dot is not recorded (`DPL` is not implemented). A `-` may precede or follow a base prefix (`-$10`, `$-10`).
- Single-cell literals that exceed 64 bits wrap; double-cell literals wrap at 128 bits.
- Pictured numeric output uses a hold area at `0x1000`–`0x1FFF` that grows downward, like gforth's `holdptr`/`holdend` (`kernel/nio.fs`). `<<#` and `#>>` nest up to 16 levels; `<#` resets all levels. Overflowing the area or an unmatched `#>>` raises `PICTURED NUMERIC OUTPUT ERROR !`.
- `PAD` is a fixed 4096-byte area at `0x2000`.
- `S"` and `S\"` used while interpreting store the text in one of four rotating 256-byte buffers at `0x3000`, so up to four interpreted strings stay valid at once. Inside a definition they compile the text into the data area. These strings, `.\"`, and `.(` may be up to 255 bytes; the FORTH/Σ `"` word and `."` keep the 127-byte limit.
- `S\"` and `.\"` accept the gforth escapes `\a \b \e \f \l \m \n \q \r \t \v \z \" \\` and `\xHH`; `\n` is a line feed. Other escaped characters stand for themselves.
- `2!` stores the high cell at the lower address, as in Forth 2012, so `CREATE X 2 CELLS ALLOT 12345678901234567890 1 X 2! X 2@ D.` prints `30792422974944119506`.
- `S>NUMBER?` returns a double and a flag for single and double syntax. `>FLOAT` accepts decimal text with or without an exponent and treats a string of blanks as zero.
- `ACCEPT` reads one line from the host input. `KEY` reads one byte; `KEY?` reports whether a byte is available. The command-line host implements `KEY?` by reading one byte ahead, so in an interactive terminal it waits for input instead of returning false immediately. With piped input it returns false at end of input.
- `F.` prints 15 significant digits without an exponent, removes trailing zeros, and appends a space (`3.`, `0.5`, `0.00001`, `100000000000000000000.`), following gforth's `f.` with the default precision 15. Infinity and NaN print `infinity`, `-infinity`, and `NaN`, following the portable `represent` in `engine/support.c`.
- `F.S` prints `<depth> ` and each item with up to 14 significant digits and an `e` marker (`1e`, `.5e`, `1e-7`, `-3.25e`, `1e30`), following gforth's `f.s` / `e.p` (`stuff.fs`, `edot.fs`). Older gforth releases and the ForthBasicMaster book show a different `F.S` format.
- Float comparisons push `-1`/`0` on the data stack. `F/` follows IEEE 754 (division by zero yields infinity or NaN; no error).
- `F>S` truncates toward zero; NaN converts to 0 and out-of-range values saturate to the minimum or maximum integer. This range handling is a portable choice; gforth leaves it to the C conversion.

### FORTH/Σ behavior retained

- Decimal is the source-defined initial base. `HEX`, `DEC`, and `OCT` remain; `DECIMAL` is an alias of `DEC`.
- The original `"` word is compile-only and stores strings up to 127 bytes. `."` is retained as a convenience extension.
- `DO` always enters the body once, including when start equals limit. For regular `LOOP`, the implementation stops on index equality. For `+LOOP`, it stops when the signed index crosses the limit in the step direction. The source article's Z80 loop comparison is difficult to read, so this directional crossing rule is the portable design choice, not a confirmed historical detail.
- `MINUS`, `COM`, `NAND`, `NOR`, `SWAB`, `END`, `VAR`, `CONST`, `ARRAY`, `A@`, `A!`, `OSET`, `1+!`, `1-!`, `C.`, `ECHO`, `SPCES`, `INPUT`, and `<BUILDS` remain available. `SWAB` now reverses all eight bytes of a cell; this widening is a portable choice. `C.` prints the low byte as an unsigned number followed by a space.
- `NOT` remains the FORTH/Σ logical not (same as `0=`) and now returns `-1` for true.
- `ARRAY` and `FARRAY` allocate eight bytes per element; `A@`/`A!` and `FA@`/`FA!` take `( index base )`.
- `F+!`, `F?`, `FA@`, `FA!`, `FARRAY`, `FINPUT`, and `FMINUS` are float counterparts of FORTH/Σ words added for this port; they are not gforth words.

### Other portable choices

- Loop frames remain in a separate runtime stack instead of sharing the user-visible return stack. `I` and `R@` therefore differ.
- `CHAR` and `[CHAR]` both read the next token; inside a definition either one compiles the character as a literal.
- Words defined by the user shadow built-in words and the parsing words (`VALUE`, `TO`, `VARIABLE`, …) of the same name.
- Stack capacities and immediate underflow checks favor a bounded portable runtime. Errors clear the data, return, float, and loop stacks and abandon an incomplete definition.
- Multi-line colon definitions remain enabled for source input. The keyboard interpreter's one-line behavior and the editor `EXEC` path in the original material differ; this implementation does not reproduce the machine-specific editor.
- The `,`, `C,`, and `F,` words share the logical data area with variables, arrays, and strings. `FORGET` restores the data pointer to the removed word's allocation mark.
- `'` produces an opaque dictionary token for this portable runtime; `EXECUTE` consumes it. This replaces machine addresses and is an implementation extension.
- `?DO` skips an equal start and limit. `J` and `K` expose the second and third nested loop indices.
- The logical memory is 1 MiB; the variable/allocation area begins at `0x4000` and may grow to the end of memory. Addresses outside `0`–`0xFFFFF` (or an access that would cross the end) raise `INVALID MEMORY ADDRESS !`.
- The data stack, return stack, and float stack hold 1024 entries each; the dictionary holds 1024 words; compiled code holds 8192 operations; names are limited to 255 bytes; an input line is limited to 4096 bytes.

These choices are implementation behavior, not claims about every historical FORTH/Σ version.

## Reference use

The gforth source and ForthBasicMaster book (`D:\home\Documents\BasicMaster\ForthBasicMaster`) are comparison material, not FORTH/Σ specification sources. Since the gforth-alignment work, they also define the target behavior for words that the book's sample programs use. Stage 1 (core), stage 2 (floating point, `Level 17.md`), and stage 3 (strings, double-cell integers, pictured numeric output) are implemented. Stages 4–6 (locals, exceptions and files, word lists and conditional compilation) are not implemented yet. The gforth dynamic-string words used in `Level 14.md` (`$!`, `$@`, `$+!`, …) depend on heap allocation and are deferred to stage 5. The `Level 20.md` comma-grouping example (`format-commas`) emits leading zeros in each group (`# # #` always produces three digits), so it cannot print the output shown in the book.

## Not implemented yet

The runtime does not implement the magazine's editor-buffer versions of LOAD/SAVE, LIST, EDIT, EXEC, CLB, CLOAD, CSAVE, CP/M file calls, PC-8001 monitor/graphics/printing words, MCODE, USR, PUHL/POHL/NEXT, or every word in the magazine's dictionary tables. From gforth, locals, `THROW`/`CATCH`, file words, `ALLOCATE` and dynamic strings, word lists, `[IF]`, `DPL`, `.R`/`U.R`/`D.R`, `UM*`/`UM/MOD`/`M*`, `C"`, `/STRING`, `COMPARE`, and floating-point words other than those listed above (for example `FE.`, `FS.`, `F**`, `FLOOR`, `FROUND`, `F.RDP`, `F>STR-RDP`) are not implemented yet.

## Verification record

On 2026-10-28, after stage 3, `zig build test` passed all 62 tests with Zig 0.16.0 on Windows. The Debug executable ran the book's `my-u.`, `dollars-and-cents`, double addition, `BIGNUM 2!`, `S"`/`S\"`/`.\"`, `ACCEPT`+`EVALUATE` from piped input, and a `KEY?`/`KEY` echo loop; the outputs matched the expected values (for the book examples, the values printed in the book).

After stages 1 and 2, `zig build test` passed all 50 tests with Zig 0.16.0 on Windows. A ReleaseFast build was checked manually: SAVE/LOAD and SAVESYS of a dictionary containing an `FCONSTANT` and a float-using colon definition printed `78.5398163375 144`, both after `LOAD` and from the generated executable with arguments, and a `SIGIMG01` image from the previous version was rejected with `INVALID IMAGE !`. Linux and macOS have not been re-verified after these changes.

Earlier record (16-bit version): Cross-builds for x86_64 Linux musl and x86_64 macOS passed with Zig 0.16.0. Windows and Ubuntu WSL manual acceptance confirmed source input by redirection, dictionary SAVE/LOAD, duplicate shadowing, FORGET restoring the older definition, SAVESYS restart, and argument-driven execution. The Windows release script produced a ReleaseFast executable (871,936 bytes), and Inno Setup 6.7.3 compiled an unsigned installer using version `0.0.0` for script validation (2,321,748 bytes). The signing attempt returned `0x800704C7`; signed executable/installer/uninstaller generation has not been verified. Installation and uninstallation have not been exercised.
