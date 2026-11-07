# FORTH/Σ specification

Japanese version: [SPEC.ja.md](SPEC.ja.md). This English version is the primary one.

## 1. Purpose of this document

This document organizes the specification that can be confirmed from the explanation, the user's manual, the word list, and the source listing of "FORTH/Σ" by 一ノ瀬敏彰 and 山口晶嗣. The series appeared in 『エンサイクロペディア・アスキー』 (Encyclopedia ASCII), Vol. 11 (ASCII, April 1982) through Vol. 13 (ASCII, September 1982). It does not fill in gaps with later Forth standards or with the specifications of common Forth systems.

The original material covers several machines and versions. A description that names no particular machine or version is treated as the "common specification". Features and capacities specific to one version are treated as information about that version. A passage that cannot be read, or a behavior that the material does not describe, is marked "undetermined".

This document is a record of the specification in the original material. The current Zig implementation changes cell width, truth values, name identity, `TYPE`, numeric output, and other points to match Gforth, so parts of it differ from this document. For the differences, see [Decisions and open items](DECISIONS.md). The material has no graphics words, so the graphics words, the keys and the mouse (`INKEY`, `MOUSE`), and the Tcl/Tk words of the port are extensions outside this document; they are specified in the [graphics and sound manual](GRAPHICS_AND_SOUND.md), and their implementation is described in the [implementation notes](IMPLEMENTATION.md).

## 2. Product overview

FORTH/Σ is a stack-based programming language system for Z80-family CPUs. It is described as a self-extending language: a program is built by defining words and extending the dictionary. Besides interactive execution, it can compile defined words and register them in the dictionary. It puts weight on execution speed, and the core of the system is written in assembly language.

### 2.1 Machines and versions confirmed in the material

| Machine or version | What the material shows |
| --- | --- |
| SORD M200 | Introduced as the first implementation of FORTH/Σ (VER.1). |
| CP/M version | The source listing is published, together with routines that use CP/M file input/output and DMA. |
| PC-8001 version | The May 1982 issue publishes the memory layout, the editor, and the machine-specific words of the PC-8001 version. |
| Version in the April issue | The user's manual and the word table. The magazine does not limit this version to the PC-8001. |

The material does not confirm that these versions share the same memory layout, word set, and input/output features. When implementing, fix the target machine and version separately.

## 3. Language model

### 3.1 Stacks and values

- Most operations use postfix notation: they take values from the parameter stack, process them, and put the results back on the stack.
- The material gives the data width as 16 bits. Numbers, addresses, and logical values are not distinguished; they are all handled as the same 16-bit values.
- The top value of the stack is called the first element. The number of stack items each word consumes and produces is listed in the tables of the user's manual.
- The return stack is used for loop information and similar data. The material distinguishes the parameter stack, the return stack, and the CPU registers.
- In an example memory diagram, the 16-bit value `0821` is stored as the low byte `21` followed by the high byte `08`.

Values are handled as 16-bit two's complement. Comparison, `MAX`, and `MIN` are signed. Division truncates toward zero, and the remainder has the same sign as the dividend. Number conversion does not check for overflow beyond 16 bits. The parameter stack grows toward lower addresses, and the return stack grows toward higher addresses.

### 3.2 Tokens and execution

The input text is separated by spaces (20H) and carriage returns (0DH). Tabs are not treated as separators. The interpreter searches the dictionary for each token and executes the word if it is found. If the token is not a word but can be recognized as a number, it is converted to a number in the current base and pushed on the stack. For input that is neither, the system prints the token followed by ` ?`.

In the examples in the material, spaces separate words, and there is no operator precedence between words. Expressions are written in postfix notation. The material does not settle how upper and lower case are matched.

### 3.3 Definitions and compilation

- A new word is defined in the form `: name ... ;`.
- There is a normal execution mode and a compile mode. During compilation, the words in the definition are registered in the dictionary, and `;` ends the definition.
- A new word is made by combining existing words, so recursive definitions are also possible.
- `FORGET` removes the given word and all words registered after it from the dictionary, and frees the memory they used. Words defined later are also lost, so care is needed not to remove basic words.
- A word with the same name can be redefined. After the redefinition, the new definition is used.
- A word name is identified by its length and its first 5 characters. The header contains the length, a 5-character name field, a link, and a status. A warning is printed on redefinition. The warning text differs between the published versions.
- Arrays, variables, and constants must be defined before they are used.

The material does not settle the character encoding of names or whether upper and lower case are distinguished.

### 3.4 Control structures

The control structures in the material are as follows.

- Conditional branch: `IF ... THEN`, `IF ... ELSE ... THEN`
- Conditional loop: `BEGIN ... WHILE ... REPEAT`
- Loop with the test at the end: `BEGIN ... END`
- Counted loop: `DO ... LOOP`, `DO ... +LOOP`
- Reference to the index inside a loop: `I`
- Leaving a loop: `LEAVE`

A condition test examines the top value of the stack and treats 0 as false and any other value as true. The true value is 1. Besides `IF` and `WHILE`, the material shows the comparison words and `NOT`. `BEGIN ... END` is a loop with the test at the end: the condition is tested at `END`, so the words in between run at least once. The body of `DO ... LOOP`/`+LOOP` also runs at least once. `LEAVE` sets the counter to the limit value and continues to `LOOP`, where the loop exits.

### 3.5 Number base

The initial base is decimal. `HEX`, `DEC`, and `OCT` switch to hexadecimal, decimal, and octal. Numbers cannot be handled in any other base. `BASE` is listed as a word that pushes the address of the base indicator on the stack.

## 4. Dictionary and memory

The dictionary consists of word headers and execution routines or data areas. The header elements shown in the figures are the length, the name, the link, the status, and the execution routine or data area. A word is searched for by following the dictionary links.

The machine introduction in the material describes the system core as about 1 KB, the dictionary as about 5 KB, and the work areas such as the stacks as about 1.5 KB. These are the values stated for the published version, not values guaranteed for every version. Separately, the source listing of the CP/M version shows input/output buffers and an edit buffer.

The material has dictionary and memory words such as `HERE`, `ALLOT`, `ARRAY`, `<BUILDS`, `DOES>`, and `MCODE`. An array is defined by pushing the number of elements on the stack and then giving `ARRAY` followed by the name. Indexes start at 0. `A@` reads an element from an index and the start address of the array. `A!` writes an element with the value, the index, and the start address of the array on the stack. `OSET` sets the 16-bit value at the given address to 0, and `?` prints the value at the given address. Array bounds are not checked, and an access out of range corrupts memory.

## 5. Word groups

The following is a classification of the words published in the material. The spelling follows the magazine. Words with the same name may still be implemented differently in the versions for different machines.

| Group | Examples in the material | Summary |
| --- | --- | --- |
| Stack operations | `DROP`, `DUP`, `SWAP`, `OVER`, `ROT`, `>R`, `R>` | Discard, duplicate, exchange, copy from below, rotate, and move to and from the return stack. |
| Arithmetic | `+`, `-`, `*`, `/`, `MOD`, `1-`, `ABS`, `MINUS`, `MAX`, `MIN` | Integer arithmetic, remainder, decrement, absolute value, sign inversion, and selection of the larger or smaller value. `1-` appears in a sample, but its treatment in the word lists is not consistent. |
| Logic and comparison | `AND`, `OR`, `XOR`, `COM`, `NAND`, `NOR`, `=`, `<`, `>`, `<=`, `>=`, `<>`, `NOT`, `0=` | Bit operations, comparison, and inversion and testing of truth values. |
| Memory | `@`, `!`, `C@`, `C!`, `+!`, `1+!`, `1-!`, `OSET`, `?`, `A@`, `A!` | 16-bit and 8-bit reads and writes, update by addition, memory clearing and display, array access, and so on. The set differs between the published versions. |
| Definitions and dictionary | `:`, `;`, `FORGET`, `HERE`, `ALLOT`, `ARRAY`, `CONST`, `VAR`, `MCODE`, `<BUILDS`, `DOES>` | Definition and management of words, constants, variables, arrays, and machine-code areas. |
| Input/output | `.`, `C.`, `CR`, `SPACE`, `SPCES`, `ECHO`, `TYPE`, `INPUT`, `?`, `"` | Output of numbers, characters, strings, spaces, and new lines; number input; and display of memory contents. `C.` prints the low 8 bits as a number, and `ECHO` prints a character. `TYPE` takes the length and the address on the stack, with the address on top. |
| Files and editing | `EDIT`, `EXEC`, `CLB`, `LOAD`, `SAVE`, `LIST`, `INPUT`, `BYE` | Edit buffer operations, file load and save, listing, input, and exit from the system. Availability depends on the version. |
| Number base | `HEX`, `DEC`, `OCT`, `BASE` | Selection and reference of the base for number input and output. |
| Loops | `DO`, `LOOP`, `+LOOP`, `LEAVE`, `I`, `BEGIN`, `END`, `WHILE`, `REPEAT` | Conditional loops and counted loops. `J` and `K` are described as examples that the user can define. |
| Others | `/MOD`, `SWAB`, `LEAVE`, `[`, `]`, `'`, `,`, `C,`, `NAND`, `NOR`, `J`, `K`, `USR`, `PUHL`, `POHL`, `NEXT` | Availability differs between the published versions. `J` and `K` are described as examples of user definitions. |

### 5.1 Notes on input/output and number conversion

The user's manual covers number output, ASCII character output, string output, new lines, and space output. `.` does not add a trailing space. A hexadecimal number is printed with 4 digits and an octal number with 6 digits; a decimal number is printed signed, with leading zeros suppressed. `"` is a word that, during compilation, pushes the address and the length of a string; a string is at most 127 characters. The address comes on top of the stack, so `TYPE` is used with the length and then the address pushed. `."` is not in the FORTH/Σ magazine articles; it is an extension of the port. The CP/M version's source listing contains routines for file open, close, sequential read and write, file creation, and setting the DMA address.

In the description of the CP/M version, the disk transfer buffer is 128 bytes. This value concerns the source of the CP/M version; it does not define the file format or buffer length of the versions for other machines.

## 6. Errors and warnings

The diagnostic messages confirmed in the material include "the token followed by ` ?`" for an undefined word, `STACK UNDER FLOW !`, `COMPILE MODE ERROR !!`, `OUT OF MEMORY !`, `NESTING ERROR`, `END OF COMMENT MUST BE ")" !`, `DIVISION BY ZERO`, the warning on redefining an existing name, and `DISK FULL !` during file operations. The text of the redefinition warning differs between the published versions.

On an error, FLER resets the stack pointer and other state, abandons an incomplete compilation, and returns to the interpreter. The individual error messages in the material differ between the published versions.

### 6.1 Inconsistencies and hard-to-read passages in the material

- For `NOR`, the explanatory text says `OR NOT`, while the Z80 listing and the manual say `OR COM`; the descriptions do not agree.
- `1-` appears in a sample in the magazine, but its treatment in the word lists is not consistent.
- How `+LOOP` compares a negative increment with the limit value, and whether `NTEST` accepts lowercase hexadecimal digits, cannot be read from the Z80 listing with confidence.

These are not stated as part of the common specification. When a port chooses a behavior for them, the choice is recorded as an implementation decision.

## 7. Scope of conformance based on the material

When you use this specification as implementation requirements, first state the target version. The following items in particular must be separated by version.

1. Startup environment and memory layout (SORD M200, CP/M, PC-8001)
2. The available file and editing words
3. The capacity of the dictionary, the stacks, and the work areas
4. Machine-specific words, and how to port words that handle Z80 machine code directly
5. Input line length, character encoding, and handling of upper and lower case
6. The number of stack items consumed and produced, and the side effects, of every word

Where the material does not describe the behaviors above, this document does not fill them in with new specifications.

## 8. Sources

The following are the magazine pages of each installment of the series.

- Magazine pages 108–109, 一ノ瀬敏彰 and 山口晶嗣, "FORTH/Σ", 『エンサイクロペディア・アスキー 第11巻 ASCII 1982年4月号』 (Encyclopedia ASCII, Vol. 11, ASCII, April 1982): overview, design policy, explanation of the stacks, and the memory size of the system for the Z80.
- Magazine pages 110–117, same issue: dictionary, interpreter, compile and execution modes, control structures, user's manual, and word table.
- Magazine pages 166–173, same authors, "FORTH/Σ", 『エンサイクロペディア・アスキー 第12巻 ASCII 1982年5月号』 (Encyclopedia ASCII, Vol. 12, ASCII, May 1982): the PC-8001 version, machine-specific words, memory layout, and editor.
- Magazine pages 92–99, same authors, "FORTH/Σ", 『エンサイクロペディア・アスキー 第12巻 ASCII 1982年6月号』 (Encyclopedia ASCII, Vol. 12, ASCII, June 1982): Z80 source listing and explanation of the dictionary search, number conversion, definition creation, the compiler, and the control structures.
- Magazine pages 178–185, same authors, "FORTH/Σ", 『エンサイクロペディア・アスキー 第12巻 ASCII 1982年7月号』 (Encyclopedia ASCII, Vol. 12, ASCII, July 1982): defining words, control structures, memory, stacks, and word list.
- Magazine pages 144–151, same authors, "FORTH/Σ", 『エンサイクロペディア・アスキー 第12巻 ASCII 1982年8月号』 (Encyclopedia ASCII, Vol. 12, ASCII, August 1982): source listing and explanation of number output, arithmetic, and other processing.
- Magazine pages 172–179, same authors, "FORTH/Σ", 『エンサイクロペディア・アスキー 第13巻 ASCII 1982年9月号』 (Encyclopedia ASCII, Vol. 13, ASCII, September 1982): editing and file processing of the CP/M version, and explanation of the transfer buffer.
