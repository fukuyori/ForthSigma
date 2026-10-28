# Zig implementation notes

## Architecture

The runtime uses 16-bit cells and a 64 KiB logical byte memory. Cell reads and writes use the little-endian layout shown in the FORTH/Σ manual. The dictionary is a bounded host-side table; colon definitions compile into a small host-independent operation stream. The operation stream represents calls, literals, branches, loops, and string output. No Z80 opcodes or machine addresses are executed.

`State` owns the interpreter and receives output through a callback. The command-line adapter uses C standard input and output so the language core does not depend on a particular terminal API. File storage, cassette commands, the PC-8001 line editor, and CP/M monitor calls are outside this initial scope.

## Z80 listing correspondence

The June 1982 source article describes the main path used for the port:

- `START` establishes the parameter stack and system pointers.
- `READ` obtains a token, `DSRCH` searches the linked dictionary, and the numeric-check/conversion routines (`NTEST`, `CNVRT`) recognize numbers using `BASE`.
- `MAKE` adds a dictionary header for a new definition. `CCOLON` and the control-word handlers compile calls, literals, and patched branch destinations.
- `FLER` handles parse/compile errors and abandons an incomplete definition.
- The compiler emits Z80 subroutine calls and machine-code branches. This implementation preserves the language-level call and branch behavior in a host-independent operation stream instead.

These routine names and relationships come from the source-list explanation in the June–July 1982 source articles, magazine pages 92–99 and 178–185 (*Encyclopedia ASCII*, Vol. 6, No. 6–7, June–July 1982). The byte-for-byte Z80 layout is intentionally not reproduced.

## Current language support

- Stack words: `DROP`, `DUP`, `SWAP`, `OVER`, `ROT`, `>R`, `R>`.
- Arithmetic and comparison: `+`, `-`, `*`, `/`, `MOD`, `/MOD`, `1-`, `MINUS`, `ABS`, `MAX`, `MIN`, `=`, `<>`, `<`, `>`, `<=`, `>=`, `NOT`, `0=`, `AND`, `OR`, `XOR`, `COM`, `NAND`, `NOR`, `SWAB`.
- Memory: `@`, `!`, `C@`, `C!`, `,`, `C,`, `+!`, `1+!`, `1-!`, `OSET`, `?`, `A@`, `A!`, `HERE`, `ALLOT`, `VARIABLE`/`VAR`, `CONSTANT`/`CONST`, and `ARRAY`.
- Output, terminal input, and base selection: `.`, `C.`, `ECHO`, `CR`, `SPACE`, `SPCES`, `TYPE`, `INPUT`, `HEX`, `DEC`, `OCT`, `BASE`, the original compile-time `"..."` string word, and the extension `."..."`.
- Compilation: `: ... ;`, `[` and `]`, `'`, `EXECUTE`, `IF ... ELSE ... THEN`, `BEGIN ... END`, `BEGIN ... WHILE ... REPEAT`, `DO ... LOOP`, `DO ... +LOOP`, `?DO`, `LEAVE`, `I`, `J`, and `K`.
- Defining words: <BUILDS creates a named data word from the remaining input; DOES> attaches the compiled behavior after it to that word.
- `WORDS`, `FORGET`, and `BYE` are provided for interactive use.

## Deliberate implementation choices

The source articles determine the FORTH/Σ compatibility behavior below. The portable implementation choices and deviations are listed separately.

- Names are matched without ASCII case distinction, following gforth's `capscomp` in `kernel/prim.fs` and the `Level 3.md` explanation. Lookup also follows FORTH/Σ's documented identity rule: same length and same first five bytes.
- Decimal is the source-defined initial base. The core accepts bases 2 through 16 as a portability extension; the original documents bases 8, 10, and 16.
- Lowercase `a`–`f` are accepted for number input as a convenience extension. The source listing's treatment of lowercase hexadecimal digits is not clear.
- Cells wrap at 16 bits. Comparisons, `MIN`, `MAX`, `/`, and `MOD` use signed two's-complement values. A true flag is `1`; false is `0`.
- `.` and `?` do not append spaces. Hexadecimal output is four digits, octal output is six digits, and decimal output is signed without leading zeroes. `C.` formats the low byte numerically (two hexadecimal or three octal digits); `ECHO` emits it as a character.
- The original `"` word is compile-only, stores strings up to 127 bytes, and pushes the string length followed by its address so the address is on top for `TYPE`. `."` is retained as a convenience extension.
- `DO` always enters the body once, including when start equals limit. For regular `LOOP`, the portable implementation stops on index equality. For `+LOOP`, it stops when the signed index crosses the limit in the step direction. The source article's Z80 loop comparison is difficult to read, so this directional crossing rule is the portable design choice, not a confirmed historical detail.
- `LEAVE` marks the active loop to exit when it reaches `LOOP`/`+LOOP`, matching the source description. Loop frames remain in a separate runtime stack instead of sharing the user-visible return stack.
- Stack capacities and immediate underflow checks favor a bounded portable runtime. Errors clear the data, return, and loop stacks and abandon an incomplete definition.
- Multi-line colon definitions remain enabled for source input. The keyboard interpreter's one-line behavior and the editor `EXEC` path in the original material differ; this implementation does not reproduce the machine-specific editor.
- The `,` and `C,` words share the logical data area with variables, arrays, and strings. `FORGET` restores the data pointer to the removed word's allocation mark.
- `'` produces an opaque dictionary token for this portable runtime; `EXECUTE` consumes it. This replaces machine addresses and is an implementation extension.
- `1-` is included as a portable arithmetic word; the source examples use it, but its word tables do not consistently list it.
- `?DO` skips an equal start and limit as an optional portable extension. FORTH/Σ `DO` itself still executes its body at least once. `J` and `K` expose the second and third nested loop indices as convenience words; the source describes them as straightforward user definitions rather than required built-ins.
- The logical memory is 64 KiB; the variable/allocation area begins at `0x4000`. This is a portable runtime layout, not the PC-8001 or CP/M memory map.
- Stack capacity is 1024 cells; the dictionary holds 1024 words; compiled code holds 8192 operations; names are limited to 255 bytes; an input line is limited to 4096 bytes.

These choices are implementation behavior, not claims about every historical FORTH/Σ version. They can be revised as more of the printed manual or a particular machine version is decoded.

## Reference use

The gforth source and ForthBasicMaster book are comparison material, not FORTH/Σ specification sources. When the source articles do not settle a portable behavior, this implementation uses gforth-style case-insensitive name matching (`gforth/kernel/prim.fs`, `capscomp`; `ForthBasicMaster/jp/chapters/Level 3.md`), `?DO` for zero-iteration loops, and `J`/`K` for outer loop indices. Where the source articles specify behavior, such as the one-or-more-iteration `DO` and `LEAVE`, the FORTH/Σ rule takes precedence.

## Not implemented yet

The runtime does not implement LIST, source-file/editor words (EDIT, LOAD, SAVE, EXEC, CLB, CLOAD, CSAVE), CP/M file calls, PC-8001 monitor/graphics/printing words, MCODE, USR, PUHL/POHL/NEXT, or every word in the magazine's dictionary tables. These facilities either depend on the original dictionary/compiler layout, an editor or filesystem, or Z80/monitor machine code. The core does not execute Z80 instructions and does not claim byte-level machine compatibility.

## Verification record

zig build passes for the native Windows target. zig build test passes 29 regression tests with Zig 0.16.0, covering arithmetic, flags, dictionary lookup and capacity, FORGET, nested and conditional control flow, positive and negative loop steps, LEAVE, variables/arrays/strings, <BUILDS/DOES>, redefinition, output, allocation and cell-address boundaries, stack limits, code/control limits, division by zero, and error recovery. The suite does not cover every word or every invalid input. No cross-OS execution checks have been run.
