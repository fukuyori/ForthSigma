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

Building with `zig build -Dfloat=false` gives a smaller version without floating-point numbers (see the chapter [Floating-point numbers](#floating-point-numbers)). In the same way, `-Dfiles=false` leaves out the words that open, read, write, or include files (such as `INCLUDE`, `REQUIRE`, `OPEN-FILE`, `STDIN`, `SLURP-FILE`, and the `$...SLURP` words), `-Dhelp=false` leaves out `HELP` and `LICENSE`, `-Dtools=false` leaves out `SEE`, `LOCATE`, and `WHERE`, and `-Dimage=false` leaves out `SAVE`, `LOAD`, and `SAVESYS`. The words left out are not in the dictionary (their names give the error `name ?`). The groups are independent: without the file words, `SAVE`, `LOAD`, and `SAVESYS` still write and read image files, and `LOCATE` still reads the source file. Every build gives each built-in word the same execution token, so an image saved by one build loads into a build with other groups; running a word that build left out gives the error `INVALID EXECUTION TOKEN`, and `SEE` shows it by its name. An image saved by an earlier build that left a group out (such as `-Dfloat=false`) gives `INVALID IMAGE`, since its built-in words had other execution tokens.

Started without arguments, it prints the following two lines (only the first in a build with `-Dhelp=false`) and shows the interactive prompt. The version number is the value of the `VERSION` file at the root. When it is started with arguments (it runs the argument string once and exits), these lines are not printed.

```text
FORTH/Sigma 0.3.0  MIT License
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
| `S" ..."` | ( -- addr u ) | Push the address and length of the string. A string used interactively is placed in a temporary buffer, and up to 4 stay valid at once. Inside a definition, it is stored in the data area. At most 255 characters. |
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
| `FLUSH-FILE` | ( fileid -- ior ) | Write what is buffered to the file. |
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

## Saving the dictionary and stand-alone executables

`SAVE` and `LOAD` of this port handle a dictionary image of the user-defined words. They differ from the edit-buffer operations of the book.

```forth
SAVE words.sigma
LOAD words.sigma
```

`LOAD` adds the saved user-defined words to the end of the current dictionary. For words with the same name, the newly loaded definitions take precedence. Dictionary images saved by earlier versions (`SIGIMG01` to `SIGIMG31`) and damaged dictionary images cannot be loaded (`INVALID IMAGE !`). A dictionary image has a checksum, so accidental damage is found before loading. Load only files made by `SAVE` or `SAVESYS` of Sigma. Execution tokens stored in constants or variables (such as the result of `:NONAME`), and execution tokens or addresses compiled into a definition with `LITERAL` (such as `[ ' X ] LITERAL`), may point to another word or place after `LOAD` into a dictionary that already has user-defined words. Execution tokens compiled with `['] X` are relocated correctly. This problem does not occur in an executable made with `SAVESYS`.

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

## Features not implemented

`EDIT`, `LIST`, the edit-buffer versions of `LOAD`/`SAVE`, CP/M file operations, the monitor functions of the PC-8001, and `MCODE` or running Z80 machine code are not supported at present. Sigma is not a Z80 emulator.

Of the gforth words, string substitution such as `SUBSTITUTE` and `$SUBSTITUTE`, UTF-8 character words such as `XC@+`, and `TRY` … `ENDTRY` and the like are not implemented. Words related to the start-up of gforth, such as `CODE` and `SAVESYSTEM`, are out of scope. For details, see the [compatibility list](COMPATIBILITY.md).
