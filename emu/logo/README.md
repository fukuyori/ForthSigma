# LOGO and turtle graphics

A LOGO subset translated to Forth and executed by ForthSigma. Run commands from
the repository root, using the existing full Sigma executable. The language and
pixel rules are in [SPECIFICATION.md](docs/SPECIFICATION.md).

## Running

```powershell
zig-out/bin/sigma.exe emu/logo/logo.fs emu/logo/examples/square.lg
zig-out/bin/sigma.exe emu/logo/logo.fs --emit-forth .work/square.fs emu/logo/examples/square.lg
```

The normal runner displays the drawing and waits for **Esc** or **window close**.
Both actions exit successfully. Other errors exit with status 1 and include the
input filename, line, category, and error number. LOGO-MAIN prints the diagnostic
once, then uses QUIT to exit without Sigma's standard error display or backtrace.
LOGO-HEADLESS still rethrows the original error to its Forth caller after cleanup;
cancellation (-4205) remains silent and successful. Output directories must exist.
`--emit-forth` occurs once before the input filename; it writes UTF-8 Forth with
LF endings **and then executes it**. It is not a translation-only option. An
input/output path that resolves to the same file is rejected before writing.
Distinct hard-link paths are outside the check by specification (section 2),
because Sigma has no public word that compares file IDs. Do not use such an
alias as the output destination.

Loading `logo.fs` without a program argument, or followed by Sigma's `-e`, only
loads the library. For a run without a window:

```powershell
zig-out/bin/sigma.exe emu/logo/logo.fs -e 'ALSO LOGO S" emu/logo/examples/square.lg" LOGO-HEADLESS PREVIOUS ALSO TURTLE TURTLE-DISPOSE BYE'
```

In PowerShell, put the **whole `-e` argument in single quotes**, leaving the
Forth double quotes as shown. `LOGO-HEADLESS ( addr u -- )` starts with the
default 640×480 canvas, translates and executes the named file, and never calls
`SHOW` or `FRAME`. On success only the canvas remains, for pixel inspection or
saving; the caller must call `TURTLE-DISPOSE`. Failure releases the canvas and
rethrows the original exception. Definitions and translation buffers are
reclaimed on either path. Do not keep canvas handles after disposal, and dispose
a live canvas before another run.

## Accepted LOGO

Names are ASCII, case insensitive, starting with a letter or `_`, followed by
letters, digits, `_`, or `?`. Variables use `:name`; `"name` is a quoted word
without a closing quote. `;` starts a comment. UTF-8 is accepted, with one
optional leading BOM; line endings may be LF or CRLF. Only `LABEL` accepts
arbitrary UTF-8 quoted words. A newline ends a statement's inputs unless enclosed
in `[]` or `()`; several commands can share a line.

| Commands / operations | Inputs and result |
| --- | --- |
| `FD FORWARD BK BACK` | One distance; move forward/backward |
| `RT RIGHT LT LEFT` | One angle in degrees |
| `PU PENUP PD PENDOWN` | No inputs; pen state |
| `HOME CS CLEARSCREEN CLEAN` | No inputs; home or clear |
| `SETXY` | Two coordinates |
| `SETH SETHEADING` | One heading; 0 is up, clockwise positive |
| `SETPC SETPENCOLOR SETBG SETBACKGROUND` | Integer palette index 0–15 or literal `[r g b]`, percentages 0–100 |
| `SETPENSIZE SETSPEED` | Integer width 1–64; speed 0–1000 ms (default 10 ms) |
| `SETSCREENSIZE` | Two integer dimensions, each 2–4096; resets all state |
| `ST SHOWTURTLE HT HIDETURTLE` | No inputs; turtle visibility |
| `WRAP WINDOW FENCE` | No inputs; wrap, clip, or reject out-of-bounds movement |
| `ARC` | Angle and nonnegative radius; position/heading unchanged |
| `LABEL` | One quoted UTF-8 word; horizontal text |
| `TO name :arg ...` / `END` | Fixed-input procedure header and terminator, each on its own line |
| `REPEAT count [commands]` | Truncated, nonnegative repeat count, at most 2147483647 |
| `REPCOUNT` | One-based lexical repeat index; otherwise −1 |
| `IF condition [commands]` | Command only |
| `IFELSE condition [a] [b]` | Commands, or one value expression in each branch |
| `STOP` / `OUTPUT value` | Exit the current procedure; `OUTPUT` returns one value |
| `MAKE "name value` / `LOCAL "name` | Assign a variable / declare a procedure local |
| `THING "name` / `:name` | Read one numeric value |
| `TRUE FALSE` | Numeric −1 and 0 |
| `RANDOM bound` | Integer from 0 to floor(bound)−1; truncated bound 1–2147483647 |
| Unary `+ -`, binary `* / + -` | Floating-point arithmetic; multiplication/division bind more tightly |
| `= <> < > <= >=` | Numeric comparisons, lower precedence; no chaining |
| `(expression)` | Grouping; does not change fixed input counts |

Prefix operations take complete expressions for their fixed inputs. Thus
`FD (RANDOM 10) + 1` and `FD RANDOM 10 + 1` have different random bounds.
`FD :A - 10` subtracts; `FD :A -10` leaves an unused value and fails. `FD - 10`
accepts a unary minus. Conditions must be exactly 0 or −1. Arithmetic must stay
finite, and division by zero fails.

Locals are lexical, not dynamically inherited from a caller. Every `LOCAL` is
collected before translating its entire procedure, including declarations in
unexecuted branches. Locals and globals are unreadable until assigned; globals
do not survive a program run. Procedures containing any `OUTPUT` are value
procedures; executing `STOP` or reaching `END` in one raises an error. Unused
values and command procedures used as values are translation errors. Forward
references, mutual recursion, nested loop exits, and simultaneous argument
updates in self-tail calls are supported. General recursion has no depth
guarantee; one definition may use at most 64 argument/local/flag/temporary slots.

The six original examples cover repetition (`square`), finite self-tail calls
(`spiral`), recursion (`branches`), colours/width (`colours`), edge modes (`edges`),
and values/variables (`values`).

## Saving LOGO.EXE

Load only the library, register the completed entry word, then use `SAVESYS`.
For example, with an existing writable `C:/Temp` directory:

```powershell
zig-out/bin/sigma.exe emu/logo/logo.fs -e 'ALSO LOGO '' LOGO-MAIN APP-ENTRY! PREVIOUS SAVESYS C:/Temp/LOGO.EXE BYE'
C:/Temp/LOGO.EXE emu/logo/examples/spiral.lg
C:/Temp/LOGO.EXE --emit-forth C:/Temp/spiral.fs emu/logo/examples/spiral.lg
```

The doubled apostrophe in the PowerShell string passes Forth's `'` to Sigma.
The equivalent Forth input is:

```forth
INCLUDE emu/logo/logo.fs
ALSO LOGO
' LOGO-MAIN APP-ENTRY!
PREVIOUS
SAVESYS C:/Temp/LOGO.EXE
BYE
```

Do not run a LOGO program before saving, and do not leave a program marker in
the image. The saved application recreates runtime resources. Its ordinary
arguments belong to LOGO; no arguments is a usage error. A normal return from
`LOGO-MAIN` exits the application. Saved memory/local-stack capacities are kept;
testing used Sigma's defaults (32 MiB and 64 KiB).

## Forth turtle API

`ALSO TURTLE` selects the standalone API in `turtle.fs`. `F:` below denotes the
separate floating-point stack. Full semantics are in specification chapter 4.

| Words (aliases have identical effects) | Stack |
| --- | --- |
| `FD FORWARD BK BACK RT RIGHT LT LEFT SETH SETHEADING` | `( F: n -- )` |
| `SETXY ARC` | `( F: a b -- )` |
| `PU PENUP PD PENDOWN HOME CS CLEARSCREEN CLEAN` | `( -- )` |
| `ST SHOWTURTLE HT HIDETURTLE WRAP WINDOW FENCE` | `( -- )` |
| `SETPC SETPENCOLOR SETBG SETBACKGROUND SETPENSIZE SETSPEED` | `( n -- )` |
| `SETPENCOLOR-RGB SETBACKGROUND-RGB` | `( F: r g b -- )` |
| `SETSCREENSIZE TURTLE-INIT` | `( w h -- )` |
| `LABEL TURTLE-SAVE-PNG` | `( addr u -- )` |
| `TURTLE-PAINT TURTLE-DISPOSE` | `( -- )` |
| `TURTLE-IMAGE` | `( -- image )`; borrowed handle, never free directly |
| `TURTLE-RUN` | `( xt -- )`; display and wait after execution |

This example initializes, draws, saves, and disposes without opening a window:

```powershell
zig-out/bin/sigma.exe emu/logo/turtle.fs -e 'ALSO TURTLE 101 101 TURTLE-INIT 20e FD 90e RT 20e FD S" .work/turtle.png" TURTLE-SAVE-PNG TURTLE-DISPOSE BYE'
```

Dispose before calling `TURTLE-INIT` again in the same process. `TURTLE-PAINT`
composes the screen image without opening a window. Display is requested by
`TURTLE-RUN`, which lets Sigma's `SHOW` select its display backend.

## Differences from UCBLogo

This is a deliberately limited numeric language. There are no list values,
list operations, `RUN`, runtime code generation, dynamic scope, interactive
prompt, variable/optional/rest inputs, variable-arity parenthesized calls,
builtin redefinitions, `FILL`, `FOREVER`, `SUM`, multiple turtles, erase/reverse
pens, or LOGO image file commands. Brackets are only command blocks and RGB
literals. Quoted words are restricted to `MAKE`, `THING`, `LOCAL`, and `LABEL`.
Only self-tail calls are optimized; mutual tail calls remain ordinary calls.

`REPCOUNT` is lexical and does not inherit a caller's repeat index. Booleans are
numbers −1/0, with strict conditions. Local declarations cover the whole
procedure. Palette RGB values, arc start direction/chord approximation,
square-brush thickness, half-pixel rounding, edge splitting/atomic FENCE
failure, horizontal labels, canvas reset rules, limits, and speed-in-ms are this
implementation's specified choices, not verified UCBLogo compatibility. The
canvas stays fixed when a display window is resized; turtle overlays are not
part of the saved image. Speed 0 skips intermediate display, not input checks.

## Tests and observed validation

```powershell
zig-out/bin/sigma.exe emu/logo/test-turtle.fs
zig-out/bin/sigma.exe emu/logo/test-logo.fs
```

The tests use `.work/1477/` for disposable files. They never display or play
sound, compare complete small canvases with explicit expected pixels, and fail
with status 1 if any assertion fails. The LOGO tests also check emitted-text
replay, diagnostics, repeated cleanup, file/image capacity, and all six examples.
The frozen 7.4 translation and its differences from the illustrative text are
documented in [the implementation report](docs/IMPLEMENTATION-1477.md).
Window interaction, fonts other than the initial ASCII font, and rendered
Japanese glyphs have not been visually verified.
