# FORTH/Σ Zig Port User Manual

Japanese version: [USER_MANUAL.ja.md](USER_MANUAL.ja.md). This English version is the primary one.

This document explains how to use the current Zig port. Features that appear in the book but are not in the current implementation are not included. For the organized FORTH/Σ specification, see the [specification](SPEC.md); for whether each word appears in the book, see the [compatibility list](COMPATIBILITY.md).

This version keeps the FORTH/Σ words but follows gforth for numbers and the basic words. A cell is 64 bits, the true value is -1, and floating-point numbers use their own stack. The differences from the 16-bit specification of the book are collected in [decisions and open items](DECISIONS.md).

## Starting and input

Build and start it from the root of the repository as follows.

```powershell
zig build
.\zig-out\bin\sigma.exe
```

Building with `zig build -Dfloat=false` gives a smaller version without floating-point numbers (see the chapter [Floating-point numbers](#floating-point-numbers)). In the same way, `-Dfiles=false` leaves out the words that open, read, write, or include files (such as `INCLUDE`, `REQUIRE`, `OPEN-FILE`, `STDIN`, `SLURP-FILE`, and the `$...SLURP` words), `-Dhelp=false` leaves out `HELP` and `LICENSE`, `-Dtools=false` leaves out `SEE`, `LOCATE`, and `WHERE`, `-Dimage=false` leaves out `SAVE`, `LOAD`, and `SAVESYS`, and `-Dgraphics=false` leaves out `REQUIRE-GRAPHICS` and the graphics words (see [Graphics](#graphics)). The words left out are not in the dictionary (their names give the error `name ?`). The groups are independent: without the file words, `SAVE`, `LOAD`, and `SAVESYS` still write and read image files, and `LOCATE` still reads the source file. Every build gives each built-in word the same execution token, so an image saved by one build loads into a build with other groups; running a word that build left out gives the error `INVALID EXECUTION TOKEN`, and `SEE` shows it by its name. An image saved by an earlier build that left a group out (such as `-Dfloat=false`) gives `INVALID IMAGE`, since its built-in words had other execution tokens.

Started without arguments, it prints the following two lines (only the first in a build with `-Dhelp=false`) and shows the interactive prompt. The version number is the value of the `VERSION` file at the root. When it is started with arguments (it runs the argument string once and exits), these lines are not printed.

```text
FORTH/Sigma 0.6.1  MIT License
Type `help' for basic help
```

`HELP` shows the basic usage, and `HELP name` shows the stack effect of a word and a one-line description in English (example: `HELP DUP`). The name is read from the same line (also in an `EVALUATE` string, it does not read past a line end). `HELP` written in a definition reads the name when that definition runs. For a word defined by the user, it suggests viewing its contents with `SEE`. An unknown name gives the error `name ?`. `LICENSE` shows the full text of the license and the copyright notice of the included CORE-MATH.

When an input line has been processed successfully, `OK` is printed. For example, the following input prints the square of 12.

```forth
: SQUARE DUP * ;
12 SQUARE . CR
```

The result is `144 `. `.` appends one space after the number but no line break. When a line break is needed, follow it with `CR`. Forth source of several lines can be passed through standard input.

```powershell
Get-Content .\examples\demo.fs | .\zig-out\bin\sigma.exe
```

`BYE` ends the program. When an error such as an undefined word occurs, Sigma prints a diagnostic, empties all stacks, and goes on to the next input line.

`( ... )` skips text up to `)` on the same line as a comment, and `\` skips to the end of the line.

## Numbers

Integers are 64-bit signed values. Addition, subtraction, and multiplication that go out of range wrap around. `/`, `MOD`, and `/MOD` use floored division (rounding toward negative infinity): `-7 2 /` is `-4`, and `-7 2 MOD` is `1`. Dividing by 0 gives the error `DIVISION BY ZERO !`. Dividing the minimum value (-9223372036854775808) by -1 gives `RESULT OUT OF RANGE !` (exception code -11), also for `MOD`, because the quotient does not fit in one cell (the same as gforth).

`*/` (( n1 n2 n3 -- n4 )) and `*/MOD` (( n1 n2 n3 -- rem quot )) compute n1×n2 as a double cell and then divide by n3, so they give the correct quotient even when the product does not fit in one cell (floored division). `U<` and `U>` compare unsigned. `?DUP` copies the top cell unless it is zero.

A comparison gives `-1` (all bits set) for true and `0` for false. Conditions such as `IF` treat 0 as false and any other value as true.

A prefix before a number selects its base, whatever the current base is.

| Notation | Meaning |
| --- | --- |
| `$FF` | Hexadecimal |
| `#10`, `&10` | Decimal |
| `%101` | Binary |
| `'a'` | Character code |

### Double-cell integers

A number with a `.` among its digits is a double-cell integer (128 bits). It is pushed as two cells, the low cell first and then the high cell. `123.` is 123, and `12345.123` is 12345123 (the position of the dot is not recorded).

```forth
1234567890000000000. 9876543210000000000. D+ D.   \ 11111111100000000000
-7 S>D DABS D.                                    \ 7
CREATE BIGNUM 2 CELLS ALLOT
12345678901234567890 1 BIGNUM 2!
BIGNUM 2@ D.                                      \ 30792422974944119506
```

| Use | Words |
| --- | --- |
| Conversion | `S>D`, `D>S`, `D>F`, `F>D` |
| Arithmetic | `D+`, `D-`, `DNEGATE`, `DABS` |
| Comparison | `D0=`, `D0<`, `D=`, `D<` |
| Output | `D.` |
| Mixed single and double multiplication and division | `M*` (( n1 n2 -- d )), `UM*` (( u1 u2 -- ud )), `UM/MOD` (( ud u -- rem quot ), unsigned), `FM/MOD` (( d n -- rem quot ), floored division), `SM/REM` (( d n -- rem quot ), rounding toward 0) |

`*/`, `*/MOD`, `UM/MOD`, `FM/MOD`, and `SM/REM` give `DIVISION BY ZERO !` when dividing by 0, and `RESULT OUT OF RANGE !` (exception code -11) when the quotient does not fit in one cell. This is the same as gforth.

| Use | Words | Description |
| --- | --- | --- |
| Memory and definitions | `2@`, `2!`, `2VARIABLE name`, `value 2CONSTANT name`, `value 2VALUE name`, `2LITERAL` | The name of a `2VALUE` pushes its value, and `value TO name` changes it. `2LITERAL` compiles a double-cell integer into a definition. |
| Others | `D2*`, `D2/`, `DMAX`, `DMIN`, `M+`, `M*/`, `DU<`, `2ROT`, `D.R` | `M*/` (( d1 n1 +n2 -- d2 )) computes d1×n1 in three cells and then divides by n2 (floored division; as in gforth, n2 is treated as unsigned, and the quotient wraps when it does not fit in two cells). `D2/` rounds toward negative infinity (arithmetic shift). `M+` adds a single-cell integer to a double-cell integer. `DU<` compares unsigned. `2ROT` moves the third pair of cells to the top. `D.R` (( d width -- )) prints right-aligned in width characters, without a space after it. |

## Defining words and the dictionary

A user-defined word is made with `: name ... ;`. Word names are matched by the whole name, without distinguishing upper and lower case of ASCII letters. Redefining an existing name prints a warning, but the new definition takes precedence. A definition with the same name as a built-in word also takes precedence over the built-in word.

```forth
: DOUBLE 2 * ;
21 DOUBLE . CR
```

`WORDS` lists the words registered in the current dictionary. `FORGET name` removes the named word and the user-defined words registered after it. So, if you add a definition with the same name later and then `FORGET` the newer one, the older definition is used again. Note that other words defined after the removed word are removed with it.

`IMMEDIATE` makes the word defined last an immediate word. `POSTPONE name` adds "compile name" to the word being defined. `RECURSE` calls the word being defined.

### Deferred words and compiling words

| Word | Stack | Description |
|---|---|---|
| `DEFER name` | ( -- ) | Make a word whose action is set later. |
| `xt IS name` | ( xt -- ) | Set the word that the DEFER word runs. Like `TO`, it can be used inside a definition and also works on a VALUE (the same as gforth). |
| `ACTION-OF name` | ( -- xt ) | Return the word that the DEFER word runs. |
| `DEFER!`, `DEFER@` | ( xt2 xt1 -- ), ( xt1 -- xt2 ) | Set, or fetch, the action of the DEFER word given by an execution token. |
| `DEFERS name` | ( -- ) | Inside a definition, compile the word that the DEFER word runs at that time. It is an error for a DEFER whose action has not been set (gforth compiles a word that prints a warning). |
| `COMPILE,` | ( xt -- ) | Append the execution of xt to the definition being compiled. |
| `[COMPILE] name` | ( -- ) | Append the execution of name to the definition being compiled (also for an immediate word). It cannot be used for local variables or for parsing words that are not in a word list, such as `S"` and `TO`. |
| `NAME>COMPILE` | ( nt -- xt1 xt2 ) | Running xt2 on xt1 compiles the name (xt2 is `COMPILE,`, or `EXECUTE` for an immediate word). |
| `value +TO name` | ( n -- ) | Add a value to a VALUE or a local variable (a floating-point number for an FVALUE or a floating-point local variable, a double-cell integer for a 2VALUE or a double-cell local variable). |
| `PERFORM`, `NOOP` | ( addr -- ), ( -- ) | `PERFORM` runs the execution token stored at addr (`@ EXECUTE`). `NOOP` does nothing. |

When the action of a DEFER word has not been set yet, it prints a warning (`WARNING: DEFERRED WORD name IS UNINITIALIZED`) and does nothing, as in gforth. `DEFER@` then gives -1 (gforth gives the execution token of a word that prints the warning). gforth compiles `COMPILE,` used outside a definition with a warning, but in Sigma it is an error (`COMPILE MODE ERROR !`). When a DEFER runs itself (also through other words), it gives `RETURN STACK OVER FLOW !` (gforth keeps running without stopping). A DEFER that runs a word removed by `FORGET` or `MARKER` returns to the state where its action is not set.

### Structures

```forth
BEGIN-STRUCTURE POINT
  FIELD: P.X
  FIELD: P.Y
END-STRUCTURE
CREATE ORIGIN POINT ALLOT
10 ORIGIN P.Y !   ORIGIN P.Y @ .
```

| Word | Stack | Description |
|---|---|---|
| `BEGIN-STRUCTURE name`, `END-STRUCTURE` | ( -- addr 0 ), ( addr n -- ) | Define a structure. The name becomes a VALUE that returns the size of the structure (the same as gforth). |
| `+FIELD name` | ( n1 n2 -- n3 ) | Make a field at offset n1 of n2 bytes. The name adds n1 to an address. |
| `FIELD:`, `CFIELD:`, `FFIELD:`, `SFFIELD:`, `DFFIELD:` | ( n1 -- n2 ) | Make a field for a cell, a character, a floating-point number, or a 32-bit or 64-bit floating-point number, aligned as needed. |
| `STRUCT`, `FIELD name`, `END-STRUCT name` | ( -- align size ), ( align1 offset1 align size -- align2 offset2 ), ( align size -- ) | The older structure notation of gforth. The name made by `END-STRUCT` returns two values, the alignment and the size. |
| `CELL%`, `CHAR%`, `FLOAT%`, `DOUBLE%`, `SFLOAT%`, `DFLOAT%` | ( -- align size ) | The alignment and size of a type. |
| `%SIZE`, `%ALIGNMENT` | ( align size -- size ), ( align size -- align ) | Extract the size, or the alignment. |
| `%ALIGN`, `%ALLOT` | ( align size -- ), ( align size -- addr ) | Align `HERE`. `%ALLOT` also allots the size and returns the address. |
| `%ALLOC`, `%ALLOCATE` | ( align size -- addr ), ( align size -- addr ior ) | Allocate on the heap. `%ALLOC` does `THROW` when it fails. |

`SEE` shows a field as `offset +FIELD name` (this differs from the output of gforth).

## Variables, constants, and arrays

```forth
VARIABLE COUNT
10 COUNT !
COUNT @ . CR
42 CONSTANT ANSWER
ANSWER . CR
5 VALUE LIMIT
8 TO LIMIT
4 ARRAY TABLE
CREATE BUF 16 ALLOT
```

`VARIABLE` (alias `VAR`) makes a variable, and `CONSTANT` (alias `CONST`) registers the top value of the stack as a constant. `VALUE` makes a word that returns a value, and `TO name` changes the value. `ARRAY` takes the number of elements and makes an array of 8 bytes per element. Array indexes start at 0; read and write with `index array A@` and `value index array A!`. `CREATE name` makes a word that returns the current position of the data area.

One cell is 8 bytes. `CELLS` converts a number of elements to a number of bytes. In memory operations, the user must manage addresses and ranges. Reading or writing outside the logical memory gives `INVALID MEMORY ADDRESS !`.

## Control structures

Control structures are used inside definitions.

```forth
: ABS-VALUE DUP 0 < IF NEGATE THEN ;
: COUNT-UP 5 0 DO I . LOOP ;
: GRADE CASE 1 OF ." ONE" ENDOF 2 OF ." TWO" ENDOF ." OTHER" ENDCASE ;
```

The available structures are as follows.

- `IF ... ELSE ... THEN`
- `BEGIN ... END` (`UNTIL` is an alias of `END`), `BEGIN ... AGAIN`, `BEGIN ... WHILE ... REPEAT`
- `CASE ... OF ... ENDOF ... ENDCASE` (gforth's `?OF`, `CONTOF`, and `NEXT-CASE` can also be used)
- `DO ... LOOP`, `DO ... +LOOP`, `?DO`

`IF ... ENDIF` can also be used (`ENDIF` is an alias of `THEN`). `DO` runs the body once even when the start value equals the limit (the FORTH/Σ specification). `?DO` does not run the body when they are equal. `LEAVE` leaves the loop immediately. To `EXIT` in the middle of a loop, first clean up the loop with `UNLOOP`. `?EXIT` (( flag -- )) does `EXIT` when the flag is true, and `?LEAVE` (( flag -- )) does `LEAVE` when the flag is true. `?OF` (( flag -- )) is an `OF` that selects by a flag instead of comparing with a value, `CONTOF` is an `ENDOF` that goes back to the start of the `CASE`, and `NEXT-CASE` is an `ENDCASE` that goes back to the start without dropping the selector (the same as gforth). `I`, `J`, and `K` return the index of the first, second, and third loop, counted from the innermost.

## Floating-point numbers

A version built with `zig build -Dfloat=false` has none of the words of this chapter (the words in the floating-point rows of the word list, `FVARIABLE`, `FCONSTANT`, `FVALUE`, `FLITERAL`, `>FLOAT`, `FFIELD:`, `SFFIELD:`, `DFFIELD:`, `FLOAT%`, `SFLOAT%`, `DFLOAT%`), no floating-point literals, and no `F:` or `F^` local variables. A number such as `1e` is treated as an undefined word, and `ENVIRONMENT?` returns false for `FLOATING-STACK` and `MAX-FLOAT`. When an image saved by a version with floating-point numbers is loaded, running a floating-point word gives the error `INVALID EXECUTION TOKEN`.

Floating-point numbers are 64-bit (double precision) and are pushed on a floating-point stack separate from the integers. In source, a number containing `e` or `E` is a floating-point number when the base is 10.

```forth
1E 2E F+ F.          \ 3.
1.5e0 F.             \ 1.5
3.1415926535E FCONSTANT PI
: AREA ( f: r -- f: area ) FDUP F* PI F* ;
5E AREA F.           \ 78.5398163375
10 S>F 4E F/ F>S .   \ 2
```

A number without `E`, such as `1.5`, is not treated as a floating-point number.

| Use | Words | Description |
| --- | --- | --- |
| Output | `F.`, `FE.`, `FS.`, `F.S`, `F?` | `F.` prints `PRECISION` digits (initially 15) without an exponent and appends a space (`3.`, `0.5`). `FS.` prints one leading digit, the point, and an exponent (`1.23456780000000E4`), and `FE.` makes the exponent a multiple of 3 (`12.3456780000000E3`); both print `PRECISION` digits, trailing zeros included. Infinity and NaN print only their names (`infinity`, `NaN`), without a space (the same as gforth). `F.S` prints the count and then the top 9 items, each in the same form as `14 0 17 F.RDP` (`3.0000000000E0`). |
| Stack | `FDROP`, `FDUP`, `FSWAP`, `FOVER`, `FROT`, `F-ROT`, `FNIP`, `FTUCK`, `FPICK`, `FDEPTH` | The position for `FPICK` and the result of `FDEPTH` use the integer stack. |
| Arithmetic | `F+`, `F-`, `F*`, `F/`, `FNEGATE`/`FMINUS`, `FABS`, `FMAX`, `FMIN` | Dividing by 0 gives infinity or NaN. |
| Functions | `FSQRT`, `FEXP`, `FLN`, `FSIN`, `FCOS`, `FTAN`, `FSINCOS`, `FASIN`, `FACOS`, `FATAN`, `FATAN2`, `FSINH`, `FCOSH`, `FTANH`, `FASINH`, `FACOSH`, `FATANH`, `FEXPM1`, `FLNP1`, `FLOG`, `FALOG`, `F**` | Trigonometric functions use radians. `FSINCOS` is ( f: r -- sine cosine ), `FATAN2` is ( f: y x -- angle ), `F**` is ( f: x y -- x to the power y ), `FLOG` is the common logarithm, `FALOG` is 10 to the power r, `FEXPM1` is e^r - 1, and `FLNP1` is ln(1 + r). All except `FSQRT` give correctly rounded values, with the same results on every OS. |
| Rounding | `FLOOR`, `FTRUNC`, `FROUND` | Round to an integer. `FLOOR` rounds toward negative infinity, `FTRUNC` toward 0, and `FROUND` to the nearest integer (to even when exactly halfway). |
| Comparison | `F=`, `F<>`, `F<`, `F>`, `F<=`, `F>=`, `F0=`, `F0<>`, `F0<`, `F0>`, `F0<=`, `F0>=`, `F~` | The result (-1 or 0) is pushed on the integer stack. `F~` (( f: r1 r2 r3 -- ) ( -- flag )) checks, when r3 is positive, whether the absolute difference is less than r3; when r3 is 0, whether the values are the same down to the bits (`0e` and `-0e` differ, and the same NaN is equal); and when r3 is negative, whether the difference is less than \|r3\|×(\|r1\|+\|r2\|). |
| Memory | `F@`, `F!`, `F,`, `F+!`, `FLOATS`, `FLOAT+`, `DF@`, `DF!`, `DFLOATS`, `DFLOAT+`, `SF@`, `SF!`, `SFLOATS`, `SFLOAT+`, `FALIGN`, `FALIGNED`, `DFALIGN`, `DFALIGNED`, `SFALIGN`, `SFALIGNED` | One number is 8 bytes. The words with `DF` handle the same 8-byte values, and the words with `SF` handle 4-byte (single-precision) values (`SF!` rounds to single precision and gives infinity when the value is out of range). `FALIGN` and `DFALIGN` round HERE up to a multiple of 8, and `SFALIGN` to a multiple of 4. |
| Definitions | `FVARIABLE name`, `value FCONSTANT name`, `value FVALUE name`, `count FARRAY name`, `FA@`, `FA!` | The name of an `FVALUE` pushes its value on the floating-point stack, and `value TO name` changes it. `FARRAY` elements are read and written with `index array FA@` and `index array FA!`. |
| Conversion and input | `S>F`, `F>S`, `FINPUT` | `F>S` truncates toward 0. `FINPUT` reads one number from the terminal (the `E` may be omitted). |
| Extracting digits | `REPRESENT` | In the form ( addr u -- n flag1 flag2 ) ( f: r -- ), it writes u significant digits of r at addr (rounded exactly from the binary value) and returns the exponent n (r = 0.digits × 10 to the power n), whether r is negative, and whether r is finite. Infinity and NaN are written as their names cut to u characters (the same as gforth). |
| Output digits | `PRECISION`, `SET-PRECISION` | Return, or set, the number of digits of `F.`, `FE.`, and `FS.`. Output uses 1 to 1000 digits (gforth prints up to 1000 digits and ends abnormally for 0 or less, or for 4000). `PRECISION` returns the value that was set, unchanged. |
| Formatted output | `F.RDP`, `F>STR-RDP`, `F>BUF-RDP` | In the form ( r width places min-digits -- ), they print right-aligned in width characters (`F.RDP`), return a string (`F>STR-RDP` is ( -- addr u ); the string is overwritten by the next number formatting), or write into a given buffer (`F>BUF-RDP` is ( r addr width places min-digits -- )). Example: `12345.6789E 10 2 7 F.RDP` gives `  12345.68`, and with a minimum of 8 significant digits it gives `1.234568E4`. When fixed-point notation would show too few significant digits, or the integer part does not fit in the width, exponential notation is used; when that does not fit either, the field is filled with `*`. The results are the same as gforth. |

## Input, output, and number base

| Use | Words | Description |
| --- | --- | --- |
| Number output | `.`, `U.`, `C.`, `?`, `.S`, `.R`, `U.R` | All except `.R` and `U.R` append a space after the number. `.R` (( n width -- )) and `U.R` (( u width -- )) print right-aligned in width characters, without a space. A number longer than the width is printed as it is. `U.` prints unsigned, `C.` the low 8 bits, `?` the contents of an address, and `.S` the count and the top 9 items (`<depth> value ...`). No zero padding is done. |
| Character output | `ECHO`/`EMIT` | Output the low 8 bits of the top of the stack as a character. |
| String output | `TYPE`, `."..."` | `TYPE` takes an address and a character count and outputs the string. `."..."` is an extension of the port. |
| Line breaks and spaces | `CR`, `SPACE`, `SPCES`/`SPACES`, `BL` | Output a line break, one space, or the given number of spaces. `BL` pushes the character code of a space. |
| Character codes | `CHAR char`, `[CHAR] char` | Push the character code of the first character of the next word. Inside a definition, it is compiled as a literal. |
| Number input | `INPUT` | Read one integer from the terminal and push it on the stack. |
| Changing the base | `HEX`, `DEC`/`DECIMAL`, `OCT` | Switch the base of number input and output to hexadecimal, decimal, or octal. The initial base is decimal. |
| Referring to the base | `BASE` | Push the address in logical memory that holds the base (2 to 36). |

`"..."`, which comes from the book, is a string word that is compiled and used inside a definition. When it runs, it pushes the address and then the character count, so the result can be passed to `TYPE` directly.

## Strings

```forth
S" Hello, Forth!" TYPE CR
S\" Hello\tWorld!" TYPE CR
.\" Welcome,\nthe entire land" CR
.( printed at once, even inside a definition )
CREATE BUF 20 ALLOT
S" Forth" TUCK BUF SWAP MOVE BUF SWAP TYPE
```

| Word | Stack | Description |
| --- | --- | --- |
| `S" ..."` | ( -- addr u ) | Push the address and length of the string. A string used interactively gets its own place in the heap, as in gforth, which stays valid (it is not freed, so making strings this way again and again uses up the heap). Inside a definition, it is stored in the data area. At most 255 characters. |
| `S\" ..."` | ( -- addr u ) | Interpret escapes such as `\n` (line feed), `\t` (tab), `\"`, `\\`, and `\xHH`. |
| `.\" ..."` | ( -- ) | Print the string, interpreting escapes. |
| `.( ... )` | ( -- ) | Print the text up to `)` at once. |
| `COUNT` | ( c-addr -- addr u ) | Convert a string whose first byte is its length into an address and a length. |
| `PAD` | ( -- addr ) | The address of a 4096-byte scratch area. |
| `ACCEPT` | ( addr u -- u2 ) | Read a line from the terminal, store at most u characters at addr, and return the number of characters. |
| `EVALUATE` | ( addr u -- ) | Interpret a string as Forth input. |
| `KEY` | ( -- c ) | Read one character. |
| `KEY?` | ( -- flag ) | Return whether a character can be read. On an interactive terminal it waits for input. |
| `EKEY`, `EKEY?`, `EKEY>CHAR` | ( -- u ), ( -- flag ), ( u -- u false \| c true ) | `EKEY` and `EKEY?` are the same as `KEY` and `KEY?` (function keys and the like are not interpreted). `EKEY>CHAR` returns true with the character for 0 to 255. |
| `>NUMBER` | ( ud addr u -- ud2 addr2 u2 ) | Convert digits, returning the part that could not be converted. |
| `S>NUMBER?` | ( addr u -- d flag ) | Convert a string to an integer (double cell) and return whether it succeeded. |
| `>FLOAT` | ( addr u -- flag ) ( f: -- r ) | Convert a string to a floating-point number. The `E` may be omitted. The number is pushed on the floating-point stack only on success. |

## Number formatting (pictured numeric output)

Between `<<#` and `#>>`, a number is turned into a string one digit at a time from the right end.

```forth
: dollars-and-cents ( u -- )
  0 <<# # # [CHAR] . HOLD #S [CHAR] $ HOLD #> TYPE SPACE #>> ;
1234 dollars-and-cents   \ $12.34
: my-. ( n -- ) S>D SWAP OVER DABS <<# #S ROT SIGN #> TYPE SPACE #>> ;
-123 my-.                \ -123
```

| Word | Stack | Description |
| --- | --- | --- |
| `<#` | ( -- ) | Start a conversion, emptying every hold area, nested ones included. |
| `<<#` | ( -- ) | Start a conversion that can be nested (up to 16 levels). Pair it with `#>>`. |
| `#` | ( ud -- ud2 ) | Convert the lowest digit. |
| `#S` | ( ud -- 0 0 ) | Convert all remaining digits. |
| `HOLD`, `HOLDS` | ( c -- ), ( addr u -- ) | Add a character or a string to the front. |
| `SIGN` | ( n -- ) | Add `-` if n is negative. |
| `#>` | ( ud -- addr u ) | End the conversion and return the string. |
| `#>>` | ( -- ) | Release the hold area started by `<<#`. |

## Other words

```forth
5 0 10 WITHIN .                    \ -1
S" hello" PAD PLACE PAD COUNT TYPE  \ hello
S" abc" S" abd" COMPARE .          \ -1
S" hello world" S" wor" SEARCH . TYPE  \ -1 world
S" hello" 2 /STRING TYPE           \ llo
S" hi   " -TRAILING TYPE           \ hi
S" a,b,c" CHAR , SCAN TYPE         \ ,b,c
S" hello" S" he" STRING-PREFIX? .  \ -1
: GREETING [ S" hi there" ] SLITERAL ;
:NONAME DUP * ; CONSTANT SQUARE
7 SQUARE EXECUTE .                  \ 49
S" HOME" GETENV TYPE
S" dir" SYSTEM
```

| Word | Stack | Description |
| --- | --- | --- |
| `WITHIN` | ( n lo hi -- flag ) | True if lo ≦ n < hi. The range is checked with unsigned differences, so when the upper and lower limits are reversed, the range is treated as one that wraps around. |
| `2>R`, `2R>` | ( x1 x2 -- ), ( -- x1 x2 ) | Move two cells to or from the return stack, keeping their order. |
| `2R@` | ( -- x1 x2 ) | Copy the two cells moved by `2>R`, leaving them on the return stack. |
| `N>R`, `NR>` | ( x1 … xn n -- ), ( -- x1 … xn n ) | Move n cells and their count n to or from the return stack, keeping their order. |
| `ALIGN`, `UNUSED` | ( -- ), ( -- u ) | `ALIGN` rounds HERE up to a multiple of the cell size. `UNUSED` is the number of bytes left in the data area. |
| `PLACE` | ( addr u c-addr -- ) | Store a string at c-addr with its length in the first byte. At most 255 characters. |
| `C" ..."` | ( -- c-addr ) | Used inside a definition; push the address of a string with its length in the first byte (outside a definition, `COMPILE MODE ERROR !`). |
| `BUFFER: name` | ( u -- ) | Allot u bytes of data area; the name pushes its address. The contents are not initialized. |
| `DUMP` | ( addr u -- ) | Show u bytes from addr, 16 bytes to a line, in hexadecimal and as characters (characters other than 32 to 126 show as `.`). Addresses are logical memory addresses. |
| `COMPARE` | ( addr1 u1 addr2 u2 -- n ) | Compare two strings byte by byte from the start, unsigned; return -1 if the first sorts before, 0 if equal, and 1 if after. If one is the start of the other, the shorter one sorts before. |
| `SEARCH` | ( addr1 u1 addr2 u2 -- addr3 u3 flag ) | Find the second string in the first. If found, return the rest of the string from the match and true; if not, the first string and false. An empty second string is found at the start. |
| `/STRING` | ( addr u n -- addr+n u-n ) | Drop the first n characters of a string. It does not check whether n exceeds u (the same as gforth). |
| `-TRAILING` | ( addr u -- addr u' ) | Remove the spaces at the end of a string. Tabs are not removed. |
| `CHAR+`, `CHARS` | ( addr -- addr+1 ), ( n -- n ) | Add one character (1 byte). `CHARS` returns the number of bytes of n characters (n itself). |
| `BOUNDS` | ( addr u -- addr+u addr ) | Turn a string into the end and start of a `DO ... LOOP` (`BOUNDS ?DO I C@ ... LOOP`). |
| `BLANK` | ( addr u -- ) | Set u bytes to spaces. |
| `CMOVE>` | ( from to u -- ) | Copy u bytes one at a time, from the highest address down to the lowest. |
| `SCAN` | ( addr u c -- addr' u' ) | Find the character c and return the rest of the string from there. If it is not found, the length is 0. A space does not match a tab. |
| `SKIP` | ( addr u c -- addr' u' ) | Pass the c's at the start of a string and return the rest. |
| `STR=` | ( addr1 u1 addr2 u2 -- flag ) | True if the two strings are the same. |
| `STRING-PREFIX?` | ( addr1 u1 addr2 u2 -- flag ) | True if the first string starts with the second string. |
| `+PLACE` | ( addr u c-addr -- ) | Append a string to a counted string. It stops at 255 bytes in all. |
| `SLITERAL` | compile time ( addr u -- ), run time ( -- addr u ) | Used inside a definition; compile a string (up to 255 bytes) into the definition. |
| `STATE` | ( -- addr ) | The address of a cell that holds -1 while compiling and 0 while interpreting. Writing to it does not change the state. |
| `:NONAME ... ;` | ( -- xt ) | Make a definition without a name and push its execution token. |
| `ABORT` | ( -- ) | Empty the stacks and go back to waiting for input. No message is printed. |
| `QUIT` | ( -- ) | Stop what is running and the file being loaded, and go back to waiting for input. The data stack and the floating-point stack are kept. `CATCH` does not catch it (the same as gforth). |
| `ENVIRONMENT?` | ( addr u -- false \| value true ) | Return the value of this system for queries such as `MAX-N`, `MAX-D`, `/HOLD`, `/PAD`, `STACK-CELLS`, `RETURN-STACK-CELLS`, `FLOATING-STACK`, `#LOCALS`, `WORDLISTS`, `MAX-FLOAT`, `ADDRESS-UNIT-BITS`, `FLOORED`, `MAX-CHAR`, and `/COUNTED-STRING`. Any other name (including names of word sets) gives false. |
| `ABORT" ..."` | ( flag -- ) | Used inside a definition; if flag is not 0, print the string and abort (`THROW` of -2). When caught by `CATCH`, it returns -2 and prints nothing. |
| `MS` | ( n -- ) | Wait n milliseconds. |
| `UTIME` | ( -- ud ) | Return the time since January 1, 1970, in microseconds, as a double-cell integer. |
| `TIME&DATE` | ( -- second minute hour day month year ) | Return the local date and time. The month is 1 to 12, and the year is the year of the Common Era. |
| `PAGE` | ( -- ) | Clear the screen and move the cursor to the top left. |
| `AT-XY` | ( x y -- ) | Move the cursor to column x and row y (both from 0). It outputs the same escape sequence as gforth. |
| `GETENV` | ( addr u -- addr2 u2 ) | Return the value of an environment variable. When it is not set, `0 0`. The result is valid until the next `GETENV`, and a value longer than 3072 bytes gives `STRING TOO LONG !`. |
| `SYSTEM` | ( addr u -- ) | Run the string as a shell command (`cmd.exe` on Windows). The exit code of the command is not returned (it can be fetched with `$?`). |
| `$?` | ( -- n ) | The status of the last `SYSTEM`. On Linux and macOS it is the value returned by `system` (256 times the exit code), as in gforth; on Windows it is the exit code. |
## Local variables

```forth
: SUM3 { a b c -- sum } a b + c + ;
1 2 3 SUM3 .                          \ 6
: COUNTDOWN { n -- } BEGIN n . n 1- TO n n 0= UNTIL ;
5 COUNTDOWN                           \ 5 4 3 2 1
: AREA { F: w F: h -- F: a } w h F* ;
2E 3E AREA F.                         \ 6.
: SWAP2 { W^ a W^ b } b @ a @ ;       \ W^ pushes an address
```

Names written between `{` and `}` let you use the values on the stack by those names. The last name receives the value on the top of the stack.

| Notation | Meaning |
| --- | --- |
| `{ a b -- c }` | Take a and b from the stack. The part from `--` to `}` is a comment. |
| `{ a \| b c }` | b and c after `\|` start at 0 and are not taken from the stack. |
| `W:` (may be omitted), `D:`, `F:`, `C:` | Writing the name pushes a cell, a double-cell integer, a floating-point number, or a character value, respectively. `TO name` changes the value. |
| `XT:` | Writing the name runs the execution token it received. |
| `W^`, `D^`, `F^`, `C^`, `XT^` | Writing the name pushes the address of the place that holds the value. Read and write it with `@`, `!`, `F@`, and so on. |
| `{: a b :}` | The standard Forth notation. The same as `{ }`. |
| `LOCALS\| a b \|` | The older standard Forth notation. The first name (a) receives the top of the stack. |

Local variables can also be declared in the middle of a definition or inside a control structure. A name can be used only where every path reaches it through its declaration (the same as gforth). For example, a name declared inside `IF` cannot be used in the `ELSE` part or after `THEN`. A name declared in the body of `BEGIN ... UNTIL` or `DO ... LOOP` can be used after the loop too (a name declared after `?DO` or `WHILE` cannot). In recursive calls, each call has its own values. An address obtained from an address type becomes invalid when the definition is left. Local variables cannot be used outside a definition.

## Files and exceptions

```forth
: MAKE-FILE
  S" data.txt" W/O CREATE-FILE THROW >R
  S" line 1" R@ WRITE-LINE THROW
  S" line 2" R@ WRITE-LINE THROW
  R> CLOSE-FILE THROW ;
: SHOW-FILE ( addr u -- )
  R/O OPEN-FILE THROW
  BEGIN PAD 80 2 PICK READ-LINE THROW
  WHILE CR PAD SWAP TYPE
  REPEAT DROP CLOSE-FILE THROW ;
MAKE-FILE S" data.txt" SHOW-FILE
```

File words push an **ior** (0 for success, an error number otherwise) in addition to their results. Passing it to `THROW` interrupts the processing and prints a message only when there is an error (example: `NO SUCH FILE OR DIRECTORY !`).

| Word | Stack | Description |
| --- | --- | --- |
| `R/O`, `W/O`, `R/W` | ( -- fam ) | The access methods read-only, write-only, and read-write. |
| `OPEN-FILE` | ( addr u fam -- fileid ior ) | Open an existing file. Opening it with `W/O` does not erase its contents. |
| `CREATE-FILE` | ( addr u fam -- fileid ior ) | Create a new file. If it already exists, its contents are emptied. |
| `CLOSE-FILE` | ( fileid -- ior ) | Close a file. |
| `READ-LINE` | ( addr u fileid -- u2 flag ior ) | Read a line of at most u characters and return the number of characters. The line break at the end is not included. At the end of the file, flag is false. |
| `READ-FILE` | ( addr u fileid -- u2 ior ) | Read up to u bytes as they are, line breaks included. At the end of the file, u2 is 0. It can also read from `STDIN` (also on Windows, a pipe or redirection is read as it is; from the console, Enter gives a single line-feed character). |
| `WRITE-LINE` | ( addr u fileid -- ior ) | Write a string and a line break (CR LF on Windows, LF elsewhere). |
| `WRITE-FILE` | ( addr u fileid -- ior ) | Write a string without a line break. |
| `FILE-SIZE` | ( fileid -- ud ior ) | Return the size of the file (in bytes, as a double-cell integer). |
| `REPOSITION-FILE` | ( ud fileid -- ior ) | Move the read and write position. Passing the result of `FILE-SIZE` moves to the end, so you can append. |
| `FILE-POSITION` | ( fileid -- ud ior ) | Return the read and write position. |
| `RESIZE-FILE` | ( ud fileid -- ior ) | Cut the file to ud bytes, or extend it with zero bytes. The read and write position does not change. |
| `FLUSH-FILE` | ( fileid -- ior ) | Write what is buffered to the file. Output to `STDOUT` is kept and written when input is read, before `MS`, `SYSTEM`, and output to `STDERR`, at the end of each line on a terminal, when the buffer fills, and at normal exit. For progress text without a newline (including updates using `13 EMIT`), use `STDOUT FLUSH-FILE THROW` to display it immediately. Forced termination or a crash can lose buffered output. To make an open file's contents available to a command run by `SYSTEM`, explicitly flush that file first. |
| `DELETE-FILE` | ( addr u -- ior ) | Delete the named file. |
| `RENAME-FILE` | ( addr1 u1 addr2 u2 -- ior ) | Rename the file of the first name to the second name. If a file of the second name exists, it is replaced (also on Windows). |
| `FILE-STATUS` | ( addr u -- x ior ) | If the named file exists, ior is 0 and x is the way it can be opened (`R/O`, `W/O`, `R/W`). If not, ior is -514. |
| `BIN` | ( fam -- fam' ) | Ask for a binary file. Files are always read and written as bytes, so the behavior does not change. |
| `INCLUDE-FILE` | ( fileid -- ) | Interpret the open file, then close it. In error messages, the file name is shown as `*file*`. |
| `SLURP-FILE` | ( addr u -- addr' u' ) | Read all of the named file as it is, line breaks included, into an area allocated with `ALLOCATE`. Free it with `FREE` when you are done. If the file cannot be opened, it does `THROW`. |
| `STDIN`, `STDOUT`, `STDERR` | ( -- fileid ) | The file numbers of standard input, standard output, and standard error. |
| `THROW` | ( n -- ) | If n is 0, do nothing. If -1, the same as `ABORT`. Otherwise, unless `CATCH` catches it, it is reported as an error and Sigma goes back to waiting for input. |
| `CATCH` | ( xt -- 0 \| n ) | Run xt; push 0 if it ends normally, or the number of a `THROW` or an error that occurred. On an exception, the stack depth is restored to that at the time of CATCH. Stack underflow is -4, division by zero is -10, and an undefined word is -13. |

Up to 64 files can be open at once. Files still open at exit are closed. `CATCH` can catch `THROW` (see the table above).

## Dynamic memory and dynamic strings

```forth
VARIABLE MYSTRING
S" Hello, World!" MYSTRING $!
7 MYSTRING $!LEN  S" land" MYSTRING $+!  '!' MYSTRING C$+!
MYSTRING $.                     \ Hello, land!
VARIABLE NAMES
S" Alice" 0 NAMES $[]!  S" Bob" 1 NAMES $[]!
NAMES $[].                      \ prints Alice and Bob, one per line
100 CELLS ALLOCATE THROW  FREE THROW
```

A string variable is made with `VARIABLE`. Its contents are placed on the heap and are allocated and freed automatically to fit the length.

| Word | Stack | Description |
| --- | --- | --- |
| `ALLOCATE` | ( u -- addr ior ) | Allocate an area of u bytes. If there is not enough memory, ior is -524. |
| `FREE` | ( addr -- ior ) | Free an area allocated with `ALLOCATE`. |
| `RESIZE` | ( addr u -- addr2 ior ) | Change the size of an area. The contents are kept, and the address may change. |
| `$!` | ( addr u $var -- ) | Store a string in a string variable. |
| `$@`, `$@LEN` | ( $var -- addr u ), ( $var -- u ) | Return the string, or its length. For an empty variable, `0 0` and `0`. |
| `$!LEN` | ( u $var -- ) | Change the length. The added part is 0. |
| `$+!`, `C$+!` | ( addr u $var -- ), ( c $var -- ) | Append a string, or one character, to the end. |
| `$.` | ( $var -- ) | Print the string. |
| `$INS`, `$OVER` | ( addr u $var off -- ) | Insert at, or overwrite from, character position off. |
| `$DEL` | ( $var off u -- ) | Delete u characters from character position off. |
| `$FREE`, `$INIT` | ( $var -- ) | Free the string and set the variable to 0, or make it an empty string. |
| `$SPLIT` | ( addr u c -- addr u1 addr2 u2 ) | Split a string before and after the first character c. |
| `$ITER` | ( $var c xt -- ) | Run xt on each part ( addr u ) separated by the character c. |
| `$TMP` | ( xt -- addr u ) | Run xt and return what it printed as a string. |
| `$EXEC` | ( xt $var -- ) | Run xt and append what it prints to the end of the dynamic string. The output goes back to where it was even if xt does `THROW`. |
| `$+!LEN` | ( u $var -- addr ) | Lengthen the string by u bytes and return the address of the added part. |
| `$OFF` | ( $var -- ) | The same as `$FREE` (the old name in gforth). |
| `$VARIABLE name`, `$[]VARIABLE name` | ( -- ) | Make a variable for a dynamic string or a string array. The same as `VARIABLE`. |
| `$[]!`, `$[]@` | ( addr u n $[]var -- ), ( n $[]var -- addr u ) | Store into, or fetch, element n of a string array. |
| `$[]#`, `$[].` | ( $[]var -- n ), ( $[]var -- ) | Return the number of elements, or print every element, one per line. |
| `$[]MAP` | ( $[]var xt -- ) | Run xt on each element ( addr u ). |
| `$[]FREE` | ( $[]var -- ) | Free every element and the array. |
| `$[]SLURP`, `$[]SLURP-FILE` | ( fileid $[]var -- ), ( addr u $[]var -- ) | Read a file into an array, one line per element. |
| `$[]+!`, `$+[]!` | ( addr u n $[]var -- ), ( addr u $[]var -- ) | Append to the end of string n of an array. `$+[]!` places the string as a new last element. |
| `$SLURP-FILE` | ( addr u $var -- ) | Read all of the named file into a dynamic string, replacing its previous contents. |
| `$+SLURP-FILE` | ( addr u $var -- ) | Append all of the named file to the end of a dynamic string. |
| `$SLURP`, `$+SLURP` | ( fileid $var -- ) | Read an open file from the current position to the end, replacing the dynamic string (`$+SLURP` appends to it). The file is not closed. |
| `$SLURP-LINE` | ( fileid $var -- flag ) | Read the next line (without its line break) into a dynamic string. At the end of the file, flag is 0 and the string is empty. |

The heap is 896 KiB. An executable made with `SAVESYS` also keeps the contents of the heap, but `LOAD` does not carry them over.

## Dictionary search and input parsing

```forth
: SQUARE ( n -- n^2 ) DUP * ;
SEE SQUARE                         \ shows : SQUARE / DUP * / ;
S" DUP" FIND-NAME NAME>STRING TYPE \ DUP
: SHOW BL WORD FIND IF EXECUTE . ELSE COUNT TYPE ." ?" THEN ;
42 CONSTANT ANSWER
SHOW ANSWER                        \ 42
```

When exchanging saved images with versions from before short-call inlining, `SEE` can display the same executable definition differently. An older version reading a newer image may show extra `BRANCH` operations or an empty `ELSE`. The current version reading an older image may omit an empty `ELSE` or a forward branch to the next operation. These display differences do not by themselves indicate changed execution; `SEE` is not a source backup.

| Word | Stack | Description |
| --- | --- | --- |
| `SEE name` | ( -- ) | Show the contents of a definition. A colon definition is rebuilt from its operation stream, so it does not match the source exactly. |
| `FIND-NAME` | ( addr u -- nt \| 0 ) | Find a name in the dictionary and return its name token. If it is not found, 0. |
| `NAME>INT` | ( nt -- xt ) | Get the execution token from a name token. |
| `NAME>STRING` | ( nt -- addr u ) | Return the name as a string. The result stays valid for up to 8 calls. |
| `WORD` | ( c -- c-addr ) | Read the next word delimited by the character c from the input, and return it as a counted string. |
| `SYNONYM new old` | ( -- ) | Make another name for the old word. If the old word is immediate, the new name is immediate too, and `TO` and `>BODY` also act on the old word. |
| `TRAVERSE-WORDLIST` | ( xt wid -- ) | Run xt ( nt -- flag ) for each word of the word list, newest first, passing its name token. It stops when false is returned. |
| `NAME>INTERPRET` | ( nt -- xt ) | The same as `NAME>INT`. |
| `FIND` | ( c-addr -- c-addr 0 \| xt 1 \| xt -1 ) | Find the name given as a counted string. 1 for an immediate word, -1 for others. Parsing words such as `:` and `TO` are not found. |
| `PARSE` | ( c -- addr u ) | Return the rest of the input up to the character c. |
| `SOURCE` | ( -- addr u ) | The address and length of the current input line (the string, for `EVALUATE`). |
| `>IN` | ( -- addr ) | The address of the cell that holds the position to read next in the input line (bytes from the start). Changing it moves the reading position (a value at or beyond the length of the line skips the rest of the line, and a negative value gives `STRING TOO LONG !`). |
| `SOURCE-ID` | ( -- n ) | 0 for the terminal, -1 for `EVALUATE`, and the number of the file while a file is being loaded. |
| `REFILL` | ( -- flag ) | Read the next line from the terminal or from the file being loaded, make it the input, and return true. False at the end of the input and inside `EVALUATE`. |
| `SAVE-INPUT`, `RESTORE-INPUT` | ( -- x1 x2 x3 x4 4 ), ( x1 x2 x3 x4 4 -- flag ) | Save the place in the input (the source, `>IN`, and the line), and go back to it. flag is false when it could go back. For a file, the saved line is read again; for the terminal and `EVALUATE`, it can go back only within the same line. |
| `PARSE-NAME` | ( "name" -- addr u ) | Pass spaces and tabs, and return the next name in the input. At the end of the line, the length is 0. |

`WORD`, `PARSE`, and `PARSE-NAME` read the rest of the line on which the word is written. They do not read across lines.

## Word lists and conditional compilation

```forth
VOCABULARY MY-WORDS
ONLY FORTH ALSO MY-WORDS DEFINITIONS
: HELLO ." Hello, My Words!" ;
ORDER                \ MY-WORDS Forth Root     MY-WORDS
ONLY FORTH DEFINITIONS
HELLO                \ HELLO ? (no longer visible)
WORDLIST CONSTANT UTIL
UTIL SET-CURRENT : TWICE 2 * ; FORTH DEFINITIONS
UTIL >ORDER 5 TWICE .   \ 10
1 [IF] ." yes" [ELSE] ." no" [THEN]
```

Words belong to word lists, and they are looked up in the word lists arranged in the search order. New words go into the current word list (the word list for definitions). At start-up, the search order is `Forth Forth Root`, and the current word list is `Forth`.

| Word | Stack | Description |
| --- | --- | --- |
| `VOCABULARY name` | ( -- ) | Make a word list. Running the name replaces the first entry of the search order with that word list. |
| `WORDLIST` | ( -- wid ) | Make an unnamed word list and return its number. |
| `FORTH`, `FORTH-WORDLIST` | ( -- ), ( -- wid ) | Make Forth the first entry of the search order, or return the number of Forth. |
| `ONLY` | ( -- ) | Reduce the search order to the minimum (`Root Root`). It is usually followed by `FORTH`. |
| `ALSO`, `PREVIOUS` | ( -- ) | Duplicate the first entry of the search order, or remove the first entry. |
| `>ORDER` | ( wid -- ) | Put a word list first in the search order. |
| `DEFINITIONS` | ( -- ) | Make the first word list of the search order the current word list. |
| `GET-CURRENT`, `SET-CURRENT` | ( -- wid ), ( wid -- ) | Get, or change, the current word list. |
| `GET-ORDER`, `SET-ORDER` | ( -- wid... n ), ( wid... n -- ) | Get, or set, the search order. `-1 SET-ORDER` is the same as `ONLY`. |
| `ORDER` | ( -- ) | Show the search order and, after some spaces, the current word list. |
| `SEARCH-WORDLIST` | ( addr u wid -- 0 \| xt 1 \| xt -1 ) | Find a name in one word list only. |
| `[IF]`, `[ELSE]`, `[THEN]` | ( flag -- ), ( -- ), ( -- ) | If flag is 0, skip the input up to `[ELSE]` or `[THEN]`. They also work across lines. |
| `[DEFINED] name`, `[UNDEFINED] name` | ( -- flag ) | Return whether the name is found in the search order. |
| `[IFDEF] name`, `[IFUNDEF] name`, `[ENDIF]` | ( -- ) | The same as `[DEFINED] name [IF]` and `[UNDEFINED] name [IF]`. `[ENDIF]` is the same as `[THEN]`. |
| `[DO]` … `[LOOP]`, `[?DO]`, `[+LOOP]`, `[I]` | ( limit start -- ), ( n -- ), ( -- n ) | Repeat a range of the input while interpreting (the same as gforth). `[?DO]` does not run at all when limit and start are equal. `[I]` is the index of the innermost `[DO]` or `[FOR]`. In a file they also work across lines. |
| `[BEGIN]` … `[UNTIL]`, `[AGAIN]`, `[WHILE]` … `[REPEAT]` | ( flag -- ) and so on | Indefinite loops while interpreting. |
| `[FOR]` … `[NEXT]` | ( n -- ) | Repeat n+1 times, with the index going down from n to 0. |

The search order has up to 16 entries. `WORDS` shows only the words of the first word list in the search order. Even after `ONLY`, `FORTH`, `ONLY`, `ALSO`, `ORDER`, and the like can be used. Parsing words such as `:` and `TO` can always be used, whatever the search order.

## Loading source files

```forth
INCLUDE mylib.fs          \ loads and runs the file
REQUIRE mylib.fs          \ loads the file if it has not been loaded yet
S" mylib.fs" INCLUDED? .  \ -1 (already loaded)
LOCATE SQUARE             \ shows mylib.fs:2 and the lines of the definition
MARKER SAFE  : TEMP ." Hello" ;  SAFE   \ TEMP is removed
```

| Word | Stack | Description |
| --- | --- | --- |
| `INCLUDE filename` | ( -- ) | Load the file line by line and run it. |
| `INCLUDED` | ( addr u -- ) | Load the file named by the string. |
| `REQUIRE filename`, `NEEDS filename` | ( -- ) | Load the file only if it has not been loaded yet. |
| `REQUIRED` | ( addr u -- ) | The string version of `REQUIRE`. |
| `INCLUDED?` | ( addr u -- flag ) | True if the file has been loaded. |
| `SOURCEFILENAME` | ( -- addr u ) | The name of the file being loaded. At the terminal, `*the terminal*`. |
| `SOURCELINE#` | ( -- u ) | The number of the line being loaded. At the terminal, 0. |
| `LOCATE name` | ( -- ) | Show the file and line where the word was defined, and the contents of the definition. |
| `WHERE name` | ( -- ) | List the places in the loaded files where the word was used, in the form `file:line:column: text of the line` (as in gforth, each line is 80 columns wide, with a serial number at the right end). This includes places where the name was looked up by `'` or `[DEFINED]`. Uses at the terminal or in an `EVALUATE` string are not recorded. |
| `MARKER name` | ( -- ) | Running the name removes that word and the definitions after it, and marks the files loaded after it as not loaded. |

File names are relative paths from the current directory. `REQUIRE` compares names as they are written, so `./a.fs` and `a.fs` are treated as different files. When an error occurs while loading, it is shown with the file name and line number, as in `mylib.fs:3: ...`. A definition started in a file must be finished in the same file. Nesting goes up to 8 levels, and up to 64 files can be recorded.

## Graphics

Sigma draws on one image in memory and saves it as a PPM, BMP, or PNG file. The graphics words are not in the dictionary at start-up: `REQUIRE-GRAPHICS` adds the `GRAPHICS` vocabulary, with the `GFX-` words and the graphics library written in Forth (`src/graphics/graphics.fs` and, with the floating-point words, `src/graphics/graphics_float.fs`, built into the program), the first time it runs; later it does nothing. It does not change the search order, so make the words visible with `ALSO GRAPHICS` (or `GRAPHICS`). Where `SHOW` shows the image and with how many colors are summed up in the [graphics modes manual](GRAPHICS_MODES.md).

```forth
REQUIRE-GRAPHICS
ALSO GRAPHICS
320 200 GFX-INIT                  \ a black image of 320 by 200 pixels
255 0 0 COLOR                     \ the current color: red
10 10 300 190 LINE
0 255 0 COLOR
160 100 50 CIRCLE
0 0 255 COLOR
20 120 80 50 FILL-RECT            \ 80 by 50 pixels from 20 120
S" picture.bmp" SAVE-BMP
PREVIOUS
```

Coordinates start at 0 0 in the top left corner, and everything drawn outside the image is cut off; drawing far outside costs no more than drawing inside. The drawing words use the current color, which `COLOR` sets and which starts white. A color as one cell is `$RRGGBB` (the bits above the low 24 are ignored), and every pixel is opaque.

| Word | Stack | Description |
| --- | --- | --- |
| `REQUIRE-GRAPHICS` | ( -- ) | Load the graphics words, the first time only. It is a parsing word (like `TO`) and cannot be used inside a definition. The library is read in decimal whatever `BASE` is, and `BASE` stays as it was. |
| `RGB` | ( r g b -- rgb ) | The color `$RRGGBB` of red, green, and blue, each 0 to 255 (only the low 8 bits are used). |
| `COLOR` | ( r g b -- ) | Set the current color. |
| `COLOR!`, `COLOR@` | ( rgb -- ), ( -- rgb ) | Set and get the current color as `$RRGGBB`. |
| `PSET` | ( x y -- ) | Set one pixel. |
| `CLS` | ( -- ) | Make the whole image black. |
| `LINE` | ( x1 y1 x2 y2 -- ) | A line between two points, both included (Bresenham's algorithm). |
| `RECT` | ( x y w h -- ) | The outline of a w by h rectangle whose top left corner is x y. Nothing when w or h is 0 or less. |
| `FILL-RECT` | ( x y w h -- ) | A filled w by h rectangle. |
| `CIRCLE` | ( x y r -- ) | A circle of radius r around x y, with the pixels of the midpoint circle algorithm. Nothing when r is less than 0; one pixel when r is 0. |
| `FILL-CIRCLE` | ( x y r -- ) | A filled circle; it covers every pixel of `CIRCLE` with the same arguments. |
| `PAINT` | ( x y -- ) | Fill the area around x y that has the color of x y (pixels joined left, right, up, or down) with the current color. Nothing outside the image or when the area has the current color already. |
| `SAVE-PPM`, `SAVE-BMP`, `SAVE-PNG` | ( c-addr u -- ) | Write the image to a new file as a binary PPM (P6), a 24-bit BMP, or a PNG, and `THROW` the error of the file operation if there is one. The PNG has 8-bit red, green, and blue and is not compressed, so it is about as large as the BMP; any program that reads PNG files reads it. |
| `SHOW` | ( -- ) | Show the image: in a window when the host has one (Windows), on the terminal otherwise, or where `DISPLAY-TERMINAL` or `DISPLAY-WINDOW` said. |
| `DISPLAY-TERMINAL`, `DISPLAY-WINDOW` | ( -- ) | Make `SHOW` use the terminal, or the window. `DISPLAY-WINDOW` gives `HOST FUNCTION UNAVAILABLE !` when the host has no window. |
| `WINDOW-SIZE` | ( w h -- ) | From the next `SHOW`, show the image in the window (and in the Tk window of `DISPLAY-TK`) in an area w by h pixels large, each side 1 to 8192; 0 0 (the default) for the image's own size. The image keeps its proportions, as large as fits, in the middle with black around it; for example `160 120 GFX-INIT 640 480 WINDOW-SIZE` shows each pixel as 4 by 4. It does not change the image, nor the terminal. |
| `TERMINAL-BLOCKS`, `TERMINAL-SIXEL` | ( -- ) | Show the image on the terminal with half block characters (the default), or as Sixel graphics. |
| `DISPLAY-COLORS` | ( n -- ) | Make `SHOW` use full color (0, the default), or 2, 16, or 256 colors, for terminals that show fewer colors or for the look of older computers. 2 is black and white by brightness, 16 the ANSI colors (escapes 30 to 37 and 90 to 97; the nearest is chosen as xterm shows them by default, and other terminals may show them differently), 256 xterm's 6 × 6 × 6 cube and 24 grays (`ESC [ 38 ; 5 ; n m`). Sixel and the window use the same colors. The image keeps its colors, so files are saved in full color. Other values give `NUMBER ERROR !`. |
| `DITHER` | ( flag -- ) | With fewer colors, mix them in a 4 × 4 Bayer pattern (true) instead of taking the nearest (false, the default). The pattern stays in place, so animation does not flicker. |
| `GFX-INIT` | ( w h -- ) | Make a new black image. Each side is 1 to 8192 pixels and the image at most 64 MiB (4 bytes a pixel, so 4096 by 4096 at most for a square). The previous image stays when the new one cannot be made. |
| `GFX-WIDTH`, `GFX-HEIGHT` | ( -- n ) | The size of the image, 0 before `GFX-INIT`. |
| `GFX-PSET` | ( x y rgb -- ) | Set one pixel to the color rgb. |
| `GFX-PGET` | ( x y -- rgb ) | The color of one pixel, -1 outside the image. |
| `GFX-HLINE` | ( x1 x2 y rgb -- ) | A horizontal line from x1 to x2, both included. |
| `GFX-CLS` | ( rgb -- ) | Fill the whole image with the color rgb. |
| `GFX-SAVE-PPM`, `GFX-SAVE-BMP`, `GFX-SAVE-PNG` | ( c-addr u -- ior ) | As `SAVE-PPM`, `SAVE-BMP`, and `SAVE-PNG`, but return ior (0 or the error) instead. They also work in a build with `-Dfiles=false`. |
| `GFX-SHOW-BLOCKS`, `GFX-SHOW-SIXEL`, `GFX-SHOW-WINDOW` | ( -- ) | Show the image on the terminal with half blocks, as Sixel, or in the window. |
| `GFX-WINDOW?` | ( -- flag ) | True when the host can show the image in a window. |
| `GFX-COLOR-MODE` | ( n flag -- ) | The colors of the `GFX-SHOW-` words, as `DISPLAY-COLORS` and `DITHER` (which `SHOW` passes each time). |

The `GFX-` words are the base the library is written with; the other words are Forth definitions, so `SEE`, `LOCATE`, and `WHERE` show them. So that the arithmetic cannot overflow, coordinates and sizes are first limited to -2^61 .. 2^61 for `LINE`, `RECT`, and `FILL-RECT`, and to -2^30 .. 2^30 for the circles (a circle with a value beyond that is drawn with the value moved to the limit). `PAINT` keeps the rows still to fill in the heap; a very complicated area can need more than the heap has and then gives `CANNOT ALLOCATE MEMORY !` (THROW -524, the area is then partly filled).

Errors: a size outside the limits gives `NUMBER ERROR !`; an image the host cannot allocate gives `OUT OF MEMORY !`; using the image before `GFX-INIT` gives `NO GRAPHICS IMAGE !` (THROW -271); and `REQUIRE-GRAPHICS` in a build with `-Dgraphics=false` gives `GRAPHICS UNAVAILABLE !` (THROW -270). If the library fails to load, everything `REQUIRE-GRAPHICS` added is removed again. `REQUIRE-GRAPHICS` loads the words again after `FORGET` or a `MARKER` has removed the `GRAPHICS` vocabulary or `GFX-INIT`; when only later words were forgotten (such as `FORGET GFX-WIDTH`), it does nothing and they stay removed.

To try a changed copy of the library without rebuilding Sigma, load the built-in one and then include the copy into `GRAPHICS`; its words replace the built-in ones: `REQUIRE-GRAPHICS ALSO GRAPHICS DEFINITIONS DECIMAL INCLUDE src/graphics/graphics.fs`.

On the terminal, each character shows two pixels, one above the other, with 24-bit color escapes, which most terminals understand (Windows Terminal and the Windows console, xterm, GNOME Terminal, and so on). An image larger than the terminal is made smaller to fit, keeping its proportions, and each new pixel has the average color of the pixels it stands for; one line is left for the prompt. When the output is not a terminal (a pipe or a file), 80 columns and 24 rows are assumed. Sixel graphics (`TERMINAL-SIXEL`) show real pixels on terminals that support it, with 216 colors; a terminal without Sixel may show stray characters or nothing. On Windows, the console shows the half blocks with the UTF-8 code page, which Sigma sets while it writes them and then sets back.

On Windows, the window has a thread of its own: while Forth waits for input it can be moved, resized (the image is stretched to fit), and closed, and the keyboard stays with the console. Each `SHOW` draws the current image in it again and fits the window to a new image size, or to the size `WINDOW-SIZE` gave (without it, an image larger than 1600 by 1200 pixels is shown smaller). When the window is resized, the image keeps its proportions in it, with black around it, and `MOUSE` gives the pixel of the image under the mouse. A window that was closed is opened again by the next `SHOW` (an image shown at the very moment the window is being closed may not appear until then). Linux and macOS have no window yet; `SHOW` uses the terminal there.

The image is not part of the dictionary: `SAVE` and `SAVESYS` keep the graphics words and the words that use them, but not the pixels, so a program makes its image with `GFX-INIT` after it starts. A dictionary keeps the graphics library it loaded: `REQUIRE-GRAPHICS` does not add the words of a newer library to it, so build such a dictionary again from its source to use them.

### Text

`TEXT` draws a string with the current font. At first that is the built-in font: the ASCII characters of Misaki Gothic (美咲ゴシック by Num Kadoma, free to use; see [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md)), 4 pixels wide and 8 high. `LOAD-FONT` reads a BDF font file instead, on every system, and `SYSTEM-FONT` uses a font installed in the system by its name, on Windows. The string is read as UTF-8; a character the font does not have is drawn as one `?` (or not at all when the font has no `?` either), and so is each byte that is not UTF-8. Control characters are not drawn.

```forth
REQUIRE-GRAPHICS  ALSO GRAPHICS
160 40 GFX-INIT
255 255 0 COLOR  S" Hello, Sigma!" 4 4 TEXT
2 TEXT-SCALE  0 255 255 COLOR
S" FORTH/Sigma" 2DUP TEXT-WIDTH  160 SWAP - 2/  20 TEXT     \ centered
SHOW
```

| Word | Stack | Description |
| --- | --- | --- |
| `TEXT` | ( c-addr u x y -- ) | Draw the string with the top left of its line at x y, with the current color. The pixels between the strokes are left as they are; where a system font is smoothed, the edges mix the color with the image. |
| `TEXT-SCALE` | ( n -- ) | Draw each pixel of the font as n by n pixels, 1 to 256 (`NUMBER ERROR !` otherwise); 1 at first. |
| `TEXT-WIDTH` | ( c-addr u -- w ) | How many pixels wide `TEXT` draws the string, at the current scale. It needs no image. |
| `TEXT-HEIGHT` | ( -- h ) | The height of a line of the current font, at the current scale. |
| `LOAD-FONT` | ( c-addr u -- ) | Read the named BDF font file and use it. A file that cannot be opened throws its error, and one that is not a BDF font it can read `FONT ERROR !` (THROW -272); the font stays as it was then. A line is at most 256 pixels high and a glyph 512 pixels wide. The font in use is kept until the new one has been read whole. |
| `SYSTEM-FONT` | ( c-addr u height -- ) | Use the system's font of that name (such as `Consolas`, `MS Gothic`, or `メイリオ`), height pixels a line (1 to 256), smoothed in shades of gray. Characters from U+10000 up are drawn as `?`. `FONT ERROR !` when the system has no font of the name; `HOST FUNCTION UNAVAILABLE !` on Linux and macOS. |
| `BUILTIN-FONT` | ( -- ) | Use the built-in font again. |
| `GFX-GLYPH-LOAD` | ( code -- advance \| -1 ) | Load the glyph of a code point in the current font and give how far it moves the pen; -1 when the font has none. |
| `GFX-GLYPH-BOX` | ( -- left width height ) | The box of the loaded glyph: from `left` pixels right of the pen (negative: to the left) and from the top of the line. |
| `GFX-GLYPH-ALPHA` | ( x y -- a ) | The coverage of the loaded glyph at x y of its box, 0 (none) to 255 (full); 0 outside the box. |
| `GFX-FONT-HEIGHT` | ( -- h ) | The height of a line of the current font. |
| `GFX-FONT-LOAD`, `GFX-FONT-SYSTEM`, `GFX-FONT-BUILTIN` | ( c-addr u -- ior ), ( c-addr u height -- ior ), ( -- ) | As `LOAD-FONT`, `SYSTEM-FONT`, and `BUILTIN-FONT`, but returning ior (0, the file's error, or -272). |

The font is not part of the dictionary: `SAVE` and `SAVESYS` do not keep it, and a program starts with the built-in font, as it starts without an image. A BDF font is kept outside logical memory. With `LOAD-FONT`, any BDF font can be used, for example the whole of Misaki Gothic with its kanji (`misaki_gothic.bdf` from <https://littlelimit.net/misaki.htm>); the same program then draws the same pixels on every system. A system font draws differently on different systems, and the names of the fonts differ too.

### Tcl/Tk

The TCL words run Tcl scripts in a Tcl/Tk interpreter (`wish`) that Sigma starts as a program of its own, the first time it is needed, and talks to through pipes; no Tcl library is linked into Sigma. With it, a program can use Tk's widgets, and `DISPLAY-TK` shows the image in a Tk window, also on Linux and macOS, which have no window of Sigma's own. Tcl/Tk must be installed: Sigma uses the program named by `TCL-PROGRAM`, else by the environment variable `SIGMA_WISH`, else `wish` on the `PATH`, and on Windows, else the one Git for Windows comes with (`Git\mingw64\bin\wish.exe` under `%ProgramW6432%`, `%ProgramFiles%`, or `%LOCALAPPDATA%\Programs`; usually `C:\Program Files\Git\mingw64\bin\wish.exe`). On Linux it is in the `tk` package.

```forth
REQUIRE-GRAPHICS  ALSO GRAPHICS
S" expr {6 * 7}" TCL-EVAL TYPE                  \ 42
S" button .b -text Press -command {sigma_event pressed}; pack .b; wm deiconify ." TCL
: WAIT-PRESS   BEGIN TCL-EVENT 0= WHILE 10 MS REPEAT TYPE ;
WAIT-PRESS                                       \ pressed, after the button is pressed
```

`examples/calculator.fs` is a whole program: a calculator whose buttons and keys are Tk's and whose arithmetic is Forth's (`sigma.exe < examples/calculator.fs`).

| Word | Stack | Description |
| --- | --- | --- |
| `TCL` | ( c-addr u -- ) | Run a Tcl script (UTF-8) at the global level. `TCL ERROR !` (THROW -273) when it fails. |
| `TCL-EVAL` | ( c-addr u -- c-addr2 u2 ) | Run a Tcl script and give its result, which stays until the next script. |
| `TCL-ERROR$` | ( -- c-addr u ) | The message of the last script that failed. |
| `TCL-EVENT` | ( -- c-addr u true \| false ) | The next text the Tcl side sent with `sigma_event` (for example from a button's `-command`), without waiting; the text stays until the next `TCL-EVENT`. |
| `TCL-PROGRAM` | ( c-addr u -- ) | The program to start next time (a name on the `PATH` or a path); empty for `SIGMA_WISH`, `wish`, or Git for Windows's. |
| `TCL-STOP` | ( -- ) | End the program; the next `TCL` starts it again. It also ends with Sigma. What the program has written and Sigma has not read is dropped. `HOST FUNCTION ERROR !` when the host could not see the program end. |
| `DISPLAY-TK` | ( -- ) | Make `SHOW` show the image in the Tk window `.` (sent as a PNG, in the colors of `DISPLAY-COLORS`). Keys pressed and the mouse in it come to `INKEY` and `MOUSE`. Closing the window hides it until the next `SHOW`. With `WINDOW-SIZE`, the image is shown as large as fits by a whole factor (Tk zooms only so), or smaller by a whole factor when it does not fit, also when the window is resized. |
| `GFX-TCL`, `GFX-TCL-ERROR`, `GFX-TCL-EVENT`, `GFX-TCL-PROGRAM`, `GFX-TCL-STOP`, `GFX-SHOW-TK` | | The words underneath; `GFX-TCL` ( c-addr u -- c-addr2 u2 flag ) gives the result, or the message with a true flag, instead of throwing. |

When the program cannot be started or ends, the word gives `HOST FUNCTION ERROR !` (THROW -265), and the next one starts it again. A script runs until it returns, so a script that waits (such as `vwait`) holds Sigma too; Ctrl+C pressed in the Tk window meanwhile throws `USER INTERRUPT !` and ends the program, which the next script starts again. A script ending with `return`, `break`, or `continue` gives its result as any other; only an error is `TCL ERROR !`. The results and events are kept in the heap, and `SAVE` and `SAVESYS` free them first, so a string a TCL word gave before is not valid after them; a message still coming at that moment is dropped, and the program goes on. While more than 4 MiB that Sigma has not read wait in the program (Sigma reads only in the TCL words, `INKEY`, `KEY-HELD?`, and `MOUSE`), the program drops new events, keys pressed, and mouse reports; results and the releases of keys are always sent. Each `SHOW` sends the whole image, so large images update slowly. The Tcl side's protocol is in `src/graphics/sigma_tk.tcl`.

### Keys, the mouse, and animation

`INKEY` reads a key without waiting, from the terminal and from the window, and `MOUSE` gives the pixel of the image under the mouse. `KEY`, `KEY?`, and `ACCEPT` are not changed: they still read the terminal's line input.

```forth
REQUIRE-GRAPHICS  ALSO GRAPHICS
80 40 GFX-INIT  DISPLAY-TERMINAL  MOUSE-ON
VARIABLE X  40 X !
: STEP ( -- flag )   \ false when q is pressed
   INKEY  DUP K-LEFT = IF -1 X +! THEN  DUP K-RIGHT = IF 1 X +! THEN
   [CHAR] q <>
   MOUSE 1 AND IF PSET ELSE 2DROP THEN ;
: RUN   BEGIN  0 0 255 COLOR  X @ 20 3 FILL-CIRCLE  255 255 255 COLOR  33 FRAME  STEP 0= UNTIL  MOUSE-OFF ;
RUN
```

`examples/paddle.fs` is a whole game with these words: a ball that bounces off three walls and a paddle moved with the Up and Down keys (`sigma.exe "include examples/paddle.fs"`). `examples/runner.fs` (Classic Runner) is a larger one: a tile game where the runner climbs ladders, hangs on ropes, digs holes, and collects gold while guards chase it; the line at the bottom shows how long the game's work takes each frame and the frames shown each second.

| Word | Stack | Description |
| --- | --- | --- |
| `INKEY` | ( -- key \| -1 ) | The next key pressed, without waiting; -1 when there is none. A character gives its byte (each byte of a UTF-8 character in turn), Enter 13, Backspace 8, Tab 9, Esc 27. Ctrl+C throws `USER INTERRUPT !` (-28). |
| `K-UP`, `K-DOWN`, `K-LEFT`, `K-RIGHT`, `K-HOME`, `K-END`, `K-PRIOR`, `K-NEXT`, `K-INSERT`, `K-DELETE`, `K-F1` .. `K-F12` | ( -- key ) | The codes `INKEY` gives for the keys that are not characters: 256 to 277. |
| `MOUSE` | ( -- x y buttons ) | The pixel of the image under the mouse when it last moved, and the buttons held: 1 left, 2 right, 4 middle. -1 -1 while the position is not known. Keys pressed meanwhile wait for `INKEY`. |
| `MOUSE-ON`, `MOUSE-OFF` | ( -- ) | Have the terminal report the mouse, or stop. The window always reports it. |
| `FRAME` | ( ms -- ) | Wait until ms milliseconds have passed since the last `FRAME`, then `SHOW`. A loop that draws and calls `FRAME` runs at a steady pace; when the drawing took longer, it does not wait. |
| `KEY-HELD?` | ( key -- flag ) | Whether the key (a character of one byte, or `K-UP` and the other codes) is held down now. A game moves while a key is held, without waiting for the keyboard to repeat it (it waits about 0.5 s first). The Windows console, the window, and the Tk window tell when a key is released, and when they lose the focus; a terminal on Linux and macOS does not, so its keys count as held for 0.6 s after they were last pressed (a key held down is repeated, which holds it on). Keys read meanwhile wait for `INKEY`. |
| `GFX-INKEY`, `GFX-MOUSE`, `GFX-KEY-HELD` | as `INKEY`, `MOUSE`, `KEY-HELD?` | The words underneath. |
| `GFX-MOUSE-MODE` | ( flag -- ) | As `MOUSE-ON` (true) and `MOUSE-OFF` (false). |

The first `INKEY` or `MOUSE` sets the terminal to give each key at once, without echo; Sigma sets it back to its line input, dropping what was typed for the program, when it next reads a line or a `KEY`, runs `SYSTEM`, or ends. While the terminal gives single keys, Ctrl+C does not end Sigma: it reaches `INKEY`, which throws, so a loop that reads keys can be stopped with it (a loop that no longer calls `INKEY` or `MOUSE` then cannot). When standard input is not a terminal, `INKEY` gets only the window's keys.

On Linux and macOS, the keys that are not characters come from the terminal as escape sequences, which `INKEY` decodes; a sequence whose bytes come apart (over a slow connection) waits up to 50 ms for the rest, and an Esc that nothing follows within that time is the Esc key. The mouse comes as the reports of xterm in the SGR form, which most terminals send (xterm, GNOME Terminal, iTerm2, Windows Terminal, and others); `MOUSE-ON` asks for them and `MOUSE-OFF`, the return to line input, and the end stop them. On Windows, the console gives the keys and the mouse itself; the console's selection with the mouse is off while the terminal gives single keys. Keys pressed in the window come to `INKEY` as well, and the mouse in the window gives the pixel of the stretched image under it.

To find the pixel under the mouse on the terminal, Sigma asks the terminal where the cursor is after `SHOW` draws the image (only after `MOUSE-ON`), so the position is known from the first `SHOW` after `MOUSE-ON`. With half blocks, each character is two pixels; with Sixel the cell size comes from the terminal, or 10 by 20 pixels is assumed.

A `SHOW` on the terminal draws over the image it drew last when nothing was written in between, so an animation stays in place instead of scrolling; anything written in between (such as the prompt) starts a new picture below. With Sixel, the rows the picture takes are counted from the cell height, which may not match every terminal.

### Mathematical coordinates and graphs

In a build with the floating-point words, the library also draws in mathematical coordinates (`src/graphics/graphics_float.fs`; a build with `-Dfloat=false` leaves these words out). `X-RANGE` and `Y-RANGE` say which part of the plane the image shows: x grows to the right, from the left edge to the right one, and y grows upward, from the bottom edge to the top one. Both start as -1 to 1. A point is drawn at the pixel nearest to it.

```forth
REQUIRE-GRAPHICS  ALSO GRAPHICS
320 200 GFX-INIT
-3.2e0 3.2e0 X-RANGE  -1.5e0 1.5e0 Y-RANGE
128 128 128 COLOR  AXES
255 255 0 COLOR  ' FSIN PLOT
: PARABOLA ( F: x -- y )  FDUP F* 1e0 F- ;
0 255 255 COLOR  ' PARABOLA PLOT
SHOW
```

`examples/trig.fs` draws sin x, cos x, and tan x with a grid, labels, and a legend; it gives `PLOT` NaN where tan x is far beyond the image, so that the graph has gaps at the asymptotes (`sigma.exe "include examples/trig.fs"`).

| Word | Stack | Description |
| --- | --- | --- |
| `X-RANGE` | ( F: lo hi -- ) | Show x from lo at the left edge to hi at the right one. |
| `Y-RANGE` | ( F: lo hi -- ) | Show y from lo at the bottom edge to hi at the top one. |
| `MPSET` | ( F: x y -- ) | Set the pixel of the point x y. |
| `MLINE` | ( F: x1 y1 x2 y2 -- ) | A line between two points. |
| `AXES` | ( -- ) | The axes x = 0 and y = 0 across the image; an axis outside the range is not drawn. |
| `PLOT` | ( xt -- ) | The graph of the function xt ( F: x -- y ): its y at the x of every column of the image, with a line between neighboring columns. |

The range needs lo less than hi, both finite; otherwise `X-RANGE` and `Y-RANGE` give `NUMBER ERROR !` and the range stays as it was. A coordinate that is not a number (NaN) draws nothing, and `PLOT` leaves a gap where y is NaN (for example where the function is not defined). Pixel positions beyond -2^61 .. 2^61, among them infinities, are moved to that limit as with `LINE`, so a line with such an end may go in a different direction.

## Saving the dictionary and stand-alone executables

`SAVE` and `LOAD` of this port handle a dictionary image of the user-defined words. They differ from the edit-buffer operations of the book.

```forth
SAVE words.sigma
LOAD words.sigma
```

`LOAD` adds the saved user-defined words to the end of the current dictionary. For words with the same name, the newly loaded definitions take precedence. Dictionary images saved by earlier versions (`SIGIMG01` to `SIGIMG31`) and damaged dictionary images cannot be loaded (`INVALID IMAGE !`). Images of `SIGIMG32` (0.4.0) are loaded, but 0.4.0 cannot load the images (`SIGIMG33`) this version saves. A dictionary that has loaded the graphics words with `REQUIRE-GRAPHICS` is saved as `SIGIMG34`, which versions up to 0.5.2 cannot load; this stays so even after the graphics words are removed with `FORGET` or a `MARKER`. A dictionary that never loaded them is saved as `SIGIMG33`, as before. A dictionary image has a checksum, so accidental damage is found before loading. Load only files made by `SAVE` or `SAVESYS` of Sigma. Execution tokens stored in constants or variables (such as the result of `:NONAME`), and execution tokens or addresses compiled into a definition with `LITERAL` (such as `[ ' X ] LITERAL`), may point to another word or place after `LOAD` into a dictionary that already has user-defined words. Execution tokens compiled with `['] X` are relocated correctly. This problem does not occur in an executable made with `SAVESYS`.

`SAVESYS` makes a stand-alone executable for the running environment that contains the current dictionary, the compiled definitions, and the data.

```forth
SAVESYS demo.exe
```

Started without arguments, the generated file opens an interactive prompt with that dictionary. With arguments, it runs the string of the joined arguments once as Forth input and exits. The generated file is for the same runtime environment as the one that made it.

## Registered words

The following table lists the built-in words that are registered in the dictionary at start-up and listed by `WORDS`. Parsing words such as `TO`, `S"`, and `{` are listed separately in "Syntax and defining forms" below. Words defined by the user are not included in this table.

| Category | Registered words |
| --- | --- |
| Stack operations | `DROP`, `DUP`, `SWAP`, `OVER`, `ROT`, `-ROT`, `NIP`, `TUCK`, `PICK`, `ROLL`, `2DUP`, `2DROP`, `2SWAP`, `2OVER`, `DEPTH`, `>R`, `R>`, `R@`, `2>R`, `2R>`, `2R@`, `?DUP`, `2ROT`, `N>R`, `NR>` |
| Arithmetic | `+`, `-`, `*`, `/`, `MOD`, `/MOD`, `*/`, `*/MOD`, `MINUS`, `NEGATE`, `ABS`, `1+`, `1-`, `2*`, `2/`, `MAX`, `MIN`, `UNDER+` |
| Comparison, logic, and bits | `=`, `<>`, `<`, `>`, `<=`, `>=`, `NOT`, `0=`, `0<`, `0>`, `0>=`, `0<>`, `AND`, `OR`, `XOR`, `COM`, `INVERT`, `NAND`, `NOR`, `SWAB`, `LSHIFT`, `RSHIFT`, `TRUE`, `FALSE` |
| Constants and address arithmetic | `BL`, `CELL`, `CELLS`, `CELL+`, `ALIGNED`, `ALIGN`, `UNUSED`, `WITHIN`, `BUFFER:`, `DUMP` |
| Memory and arrays | `@`, `!`, `,`, `C,`, `C@`, `C!`, `+!`, `1+!`, `1-!`, `OSET`, `ON`, `OFF`, `?`, `A@`, `A!`, `ERASE`, `FILL`, `MOVE`, `CMOVE`, `HERE`, `ALLOT`, `CELL-` |
| Loops | `I`, `J`, `K`, `LEAVE`, `UNLOOP` |
| Input and output | `.`, `U.`, `.R`, `U.R`, `C.`, `.S`, `ECHO`, `EMIT`, `CR`, `SPACE`, `SPCES`, `SPACES`, `TYPE`, `INPUT` |
| Number base | `HEX`, `DEC`, `DECIMAL`, `OCT`, `BASE` |
| Definition helpers, dictionary, and execution | `<BUILDS`, `CREATE`, `IMMEDIATE`, `WORDS`, `BYE`, `LOAD`, `SAVE`, `SAVESYS`, `EXECUTE`, `SEE`, `FIND`, `FIND-NAME`, `NAME>INT`, `NAME>STRING`, `MARKER`, `LOCATE`, `WHERE`, `PERFORM`, `NOOP`, `DEFER`, `IS`, `ACTION-OF`, `DEFER!`, `DEFER@`, `DEFERS`, `COMPILE,`, `[COMPILE]`, `NAME>COMPILE`, `BEGIN-STRUCTURE`, `END-STRUCTURE`, `+FIELD`, `FIELD:`, `CFIELD:`, `FFIELD:`, `SFFIELD:`, `DFFIELD:`, `STRUCT`, `FIELD`, `END-STRUCT`, `CELL%`, `CHAR%`, `FLOAT%`, `DOUBLE%`, `SFLOAT%`, `DFLOAT%`, `%SIZE`, `%ALIGNMENT`, `%ALIGN`, `%ALLOT`, `%ALLOC`, `%ALLOCATE` |
| Control structures (immediate words) | `IF`, `ELSE`, `AHEAD`, `THEN`, `CS-PICK`, `CS-ROLL`, `ENDIF`, `BEGIN`, `END`, `UNTIL`, `AGAIN`, `WHILE`, `REPEAT`, `DO`, `?DO`, `LOOP`, `+LOOP`, `DOES>`, `CASE`, `OF`, `?OF`, `ENDOF`, `CONTOF`, `ENDCASE`, `NEXT-CASE`, `EXIT`, `?EXIT`, `?LEAVE`, `RECURSE` |
| Floating-point stack | `FDROP`, `FDUP`, `FSWAP`, `FOVER`, `FROT`, `F-ROT`, `FNIP`, `FTUCK`, `FPICK`, `FDEPTH`, `F.S` |
| Floating-point arithmetic and functions | `F+`, `F-`, `F*`, `F/`, `FNEGATE`, `FMINUS`, `FABS`, `FMAX`, `FMIN`, `FSQRT`, `FEXP`, `FLN`, `FSIN`, `FCOS`, `FTAN`, `FSINCOS`, `FASIN`, `FACOS`, `FATAN`, `FATAN2`, `FSINH`, `FCOSH`, `FTANH`, `FASINH`, `FACOSH`, `FATANH`, `FEXPM1`, `FLNP1`, `FLOG`, `FALOG`, `F**`, `FLOOR`, `FTRUNC`, `FROUND` |
| Floating-point comparison | `F=`, `F<>`, `F<`, `F>`, `F<=`, `F>=`, `F0=`, `F0<>`, `F0<`, `F0>`, `F0<=`, `F0>=`, `F~` |
| Floating-point memory, conversion, and input/output | `F@`, `F!`, `F,`, `FA@`, `FA!`, `F+!`, `F?`, `FLOATS`, `FLOAT+`, `DF@`, `DF!`, `DFLOATS`, `DFLOAT+`, `SF@`, `SF!`, `SFLOATS`, `SFLOAT+`, `FALIGN`, `FALIGNED`, `DFALIGN`, `DFALIGNED`, `SFALIGN`, `SFALIGNED`, `S>F`, `F>S`, `F.`, `FE.`, `FS.`, `REPRESENT`, `PRECISION`, `SET-PRECISION`, `FINPUT`, `F.RDP`, `F>STR-RDP`, `F>BUF-RDP` |
| Double-cell integers | `S>D`, `D>S`, `D+`, `D-`, `DNEGATE`, `DABS`, `D0=`, `D0<`, `D=`, `D<`, `DU<`, `DMAX`, `DMIN`, `D2*`, `D2/`, `M+`, `M*/`, `D.`, `D.R`, `M*`, `UM*`, `UM/MOD`, `FM/MOD`, `SM/REM`, `2@`, `2!`, `2VALUE`, `2LITERAL`, `D>F`, `F>D` |
| Strings and input | `COUNT`, `PAD`, `ACCEPT`, `EVALUATE`, `KEY`, `KEY?`, `>NUMBER`, `S>NUMBER?`, `>FLOAT`, `WORD`, `PARSE`, `PARSE-NAME`, `SOURCE`, `>IN`, `SOURCE-ID`, `REFILL`, `SAVE-INPUT`, `RESTORE-INPUT`, `EKEY`, `EKEY?`, `EKEY>CHAR` |
| Number formatting | `<#`, `<<#`, `#`, `#S`, `#>`, `#>>`, `HOLD`, `HOLDS`, `SIGN` |
| String storage, comparison, state, and abort | `PLACE`, `+PLACE`, `COMPARE`, `SEARCH`, `/STRING`, `-TRAILING`, `CHAR+`, `CHARS`, `BOUNDS`, `BLANK`, `CMOVE>`, `SCAN`, `SKIP`, `STR=`, `STRING-PREFIX?`, `SLITERAL`, `STATE`, `ABORT` |
| Time, screen, and OS | `MS`, `UTIME`, `TIME&DATE`, `PAGE`, `AT-XY`, `GETENV`, `SYSTEM`, `ENVIRONMENT?`, `QUIT` |
| Word lists and conditional compilation | `ONLY`, `ALSO`, `PREVIOUS`, `FORTH`, `DEFINITIONS`, `SYNONYM`, `TRAVERSE-WORDLIST`, `NAME>INTERPRET`, `ORDER`, `GET-ORDER`, `SET-ORDER`, `>ORDER`, `GET-CURRENT`, `SET-CURRENT`, `VOCABULARY`, `WORDLIST`, `FORTH-WORDLIST`, `SEARCH-WORDLIST`, `[IF]`, `[ELSE]`, `[THEN]`, `[DEFINED]`, `[UNDEFINED]`, `[IFDEF]`, `[IFUNDEF]`, `[ENDIF]`, `[DO]`, `[?DO]`, `[LOOP]`, `[+LOOP]`, `[I]`, `[BEGIN]`, `[UNTIL]`, `[AGAIN]`, `[WHILE]`, `[REPEAT]`, `[FOR]`, `[NEXT]` |
| Loading source | `INCLUDE`, `INCLUDED`, `REQUIRE`, `REQUIRED`, `NEEDS`, `INCLUDED?`, `SOURCEFILENAME`, `SOURCELINE#` |
| Files and exceptions | `THROW`, `CATCH`, `R/O`, `W/O`, `R/W`, `STDIN`, `STDOUT`, `STDERR`, `OPEN-FILE`, `CREATE-FILE`, `CLOSE-FILE`, `READ-LINE`, `READ-FILE`, `FILE-POSITION`, `RESIZE-FILE`, `FLUSH-FILE`, `DELETE-FILE`, `RENAME-FILE`, `FILE-STATUS`, `BIN`, `INCLUDE-FILE`, `WRITE-LINE`, `WRITE-FILE`, `FILE-SIZE`, `SLURP-FILE`, `REPOSITION-FILE` |
| Defining words and compilation | `:`, `;`, `VARIABLE`, `VAR`, `FVARIABLE`, `2VARIABLE`, `CONSTANT`, `CONST`, `FCONSTANT`, `2CONSTANT`, `VALUE`, `FVALUE`, `ARRAY`, `FARRAY`, `'`, `>BODY`, `LITERAL`, `FLITERAL` |
| Constants and help | `PI`, `HELP`, `LICENSE` |
| Dynamic memory and dynamic strings | `ALLOCATE`, `FREE`, `RESIZE`, `$!`, `$@`, `$@LEN`, `$!LEN`, `$+!`, `C$+!`, `$.`, `$DEL`, `$INS`, `$OVER`, `$FREE`, `$INIT`, `$SPLIT`, `$ITER`, `$TMP`, `$SLURP-FILE`, `$[]`, `$[]!`, `$[]@`, `$[]#`, `$[].`, `$[]MAP`, `$[]FREE`, `$[]SLURP`, `$[]SLURP-FILE`, `$SLURP`, `$+SLURP`, `$+SLURP-FILE`, `$SLURP-LINE`, `$+!LEN`, `$[]+!`, `$+[]!`, `$EXEC`, `$OFF`, `$VARIABLE`, `$[]VARIABLE`, `$?` |

At start-up, the Forth word list has **516** built-in words (aliases such as `MINUS`/`NEGATE` are each counted as one word). In addition, 10 words such as `FORTH` and `ONLY` are also registered in the Root word list.

### Syntax and defining forms

The following are syntax forms that can be used in Forth input, but they are not built-in dictionary words listed by `WORDS`.

| Kind | Words and forms | Description |
| --- | --- | --- |
| Definitions | `: name ... ;`, `:NONAME ... ;` | Make a compiled user-defined word. `:NONAME` makes a definition without a name and pushes its execution token. |
| Definition and removal | `VARIABLE name`, `VAR name`, `CONSTANT name`, `CONST name`, `value VALUE name`, `FORGET name` | Register a variable, a constant, or a value, or remove words up to the end of the dictionary. |
| Changing a value | `TO name` | Change the value of a word made by `VALUE`. It can also be used inside a definition. |
| Floating-point definitions | `FVARIABLE name`, `FCONSTANT name` | Register a floating-point variable or constant. |
| Double-cell definitions | `2VARIABLE name`, `2CONSTANT name`, `2VALUE name` | Register a double-cell variable, constant, or value. |
| Arrays | `count ARRAY name`, `count FARRAY name` | Take the number of elements from the stack and register an array. |
| Local variables | `{ ... }`, `{: ... :}`, `LOCALS\| ... \|` | See the section "Local variables". |
| Compilation control | `[`, `]`, `' name`, `['] name`, `POSTPONE name`, `LITERAL`, `FLITERAL` | Used to stop and resume compilation, get an execution token, add compile behavior, and compile values into a definition. `'` reads the next name when it runs; written inside a definition, it reads the name when that definition runs. `[']` reads the name when the definition is compiled and compiles its execution token. `LITERAL` and `FLITERAL` compile a value from the stack into the definition during compilation. |
| Data area | `xt >BODY` | Push the address of the data area of a word made by VARIABLE, VALUE, CREATE, and so on. For CONSTANT, FCONSTANT, colon definitions, and built-in words, it gives `INVALID EXECUTION TOKEN !`. `'` returns the number of the word, so the value of `' name` cannot be used as an address as in gforth. Word numbers overlap the low addresses (where the system variables such as `BASE` are), so writing to the place given by `' name +` may destroy system variables (`BASE ERROR !` and so on). For the data area, use `' name >BODY` (example: `10 0 CELLS ' DATA >BODY + !`). This is also the correct way in standard Forth. |
| Characters | `CHAR char`, `[CHAR] char` | Push a character code. |
| Comments | `( ... )`, `\` | A comment within a line, and a comment to the end of the line. |
| Strings | `"..."`, `."..."` | A compile-time string, and the string output extension of the port. |
| gforth strings | `S" ..."`, `S\" ..."`, `.\" ..."`, `.( ... )` | See the section "Strings". |
| Graphics | `REQUIRE-GRAPHICS` | Load the graphics words into the `GRAPHICS` vocabulary. See the section "Graphics". |

## Features not implemented

`EDIT`, `LIST`, the edit-buffer versions of `LOAD`/`SAVE`, CP/M file operations, the monitor functions of the PC-8001, and `MCODE` or running Z80 machine code are not supported at present. Sigma is not a Z80 emulator.

Of the gforth words, string substitution such as `SUBSTITUTE` and `$SUBSTITUTE`, UTF-8 character words such as `XC@+`, and `TRY` … `ENDTRY` and the like are not implemented. Words related to the start-up of gforth, such as `CODE` and `SAVESYSTEM`, are out of scope. For details, see the [compatibility list](COMPATIBILITY.md).
