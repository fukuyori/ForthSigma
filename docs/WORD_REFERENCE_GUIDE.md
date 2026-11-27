# Reading the word reference and running the examples

## Scope and navigation

See the [extension manual](EXTENSION.md) for terminals, asynchronous I/O, child processes and tasks, and the [graphics and sound manual](GRAPHICS_AND_SOUND.md) for drawing, GUI, games and audio. [Registered words](USER_MANUAL.md#registered-words) summarizes loading and entry counts by group.

The [complete word reference](WORD_REFERENCE.md) inventories current registration sources, including both old and newly added words. Entries are grouped under FORTH, Root, EKEYS, EXTENSION, GRAPHICS, GUI, GAME and AUDIO. Parser forms and local declarations appear under Syntax. Public words precede private helpers within each vocabulary. Private helpers are not a stable API. Arbitrary user-defined names and unimplemented words are outside this inventory.

Every entry includes its stack effect, behavior description, worker policy, usage example, caution, kind and sources. The Japanese companion provides Japanese explanations and retains the English explanations in collapsible sections. Follow the related manuals and library definitions as well. Source excerpts require the setup, input and expectations at their linked locations; they are distinct from standalone runnable examples. Internal operations may use an indirect example of the public syntax that compiles them.

The reviewed translation sources are fingerprinted in `docs/word-reference/translation-sources.json`. Changed descriptions, stack effects, attributes or definitions fail validation. Review/update the Japanese explanations before recording new fingerprints with `python scripts/word-reference.py --record-reviewed-sources`. This option does not automatically translate anything.

Test excerpts include successful cases and deliberately invalid inputs used to check error conditions. Consult the linked test for expected exceptions and its stack, file and host setup. BYE exits the process. Examples reading STDIN consume input until EOF.

## Stack notation

`( before -- after )` lists stack items from bottom to top, left to right. `( x1 x2 -- x2 x1 )` exchanges the top item x2 with x1 below it. Lower items omitted from the notation remain unchanged. `"name"` and `"text"` indicate input parsed from the source stream, rather than items passed on the data stack.

`n` is a signed 64-bit integer, `u` an unsigned 64-bit integer, `x` one cell, `flag` normally 0 (false) or -1 (true), and `addr`/`c-addr` an address in logical memory. A cell is eight bytes. Double-cell integers place the low cell below the high cell. `addr u` is an address and a byte length, not necessarily a UTF-8 character count.

`F:` denotes the floating-point stack and `R:` the user return stack. Floating-point literals require E, as in `1e` or `1.5E3`. Do not confuse the data and floating-point stacks. `compilation:` and `runtime:` distinguish compile-time and execution effects. A helper's `{ ... | ... -- ... }` is its implementation's local declaration; temporary locals after `|` are not caller-supplied arguments.

## Definitions, syntax and search order

`immediate` marks a built-in executed during compilation; `compile-only` marks a built-in restricted to definition compilation. Syntax without such a flag may still require compilation: follow its description. Looking up `HELP IF` is different from executing IF at the prompt.

Load an optional library with `REQUIRE-GRAPHICS`, for example, and add it to the search order with `ALSO GRAPHICS`. REQUIRE alone preserves the caller's search order. GUI and GAME require GRAPHICS, but programs using both sets of names should select both, for example `ALSO GRAPHICS ALSO GUI`. PREVIOUS removes the first search-order entry. DEFINITIONS changes the destination of new definitions; it is unnecessary for merely looking up names.

The standard `EKEYS K-LEFT` and `GRAPHICS K-LEFT` have different values. Use standard values with EKEY/EKEY>FKEY and graphics values with INKEY. Search order determines which same-named word is found. Do not treat the two encodings as interchangeable.

## Ownership, errors and optional features

Check a returned `ior` or pass it to THROW; zero means success. CATCH also returns zero for normal completion. File/pipe EOF and the K-EOF event returned by terminal EKEY are different interfaces. Terminal Ctrl+C interrupts; byte 3 from a file or pipe is a character.

Release owned regions returned by ALLOCATE, SAVE-MEM or S+ through the corresponding mechanism. Borrowed strings are not owned allocations and may become invalid after subsequent operations. Persist addresses in dictionary images using explicit typed references such as ACONSTANT, AVARIABLE or A,. Relocation never guesses addresses from ordinary numeric cells.

The inventory assumes the full build. Feature-disabled builds such as `-Dfloat=false` omit their corresponding words. Listing GUI or audio words does not imply identical display or sound device support on all OSes. See [graphics and sound](GRAPHICS_AND_SOUND.md) for prerequisites and limits.

Implementation-source fingerprints also detect Zig-body changes. This is a change-detection review gate, not proof of translation or semantic correctness. Private storage roles are maintained in private-storage.json. KEY-IOR returns a byte OR a negative I/O result in one cell: do not pass an ordinary byte to THROW. RECURSE and local declarations require definition compilation.


The worker field follows task_permissions builtin policy and registration kinds. Allowed does not guarantee that an entire entry is admissible. Conditional entries require reachability and optimized-operation validation, plus logical ranges, write permission and total native work <=64 KiB per call when accessing memory. Feature exclusions still apply; unregistered and future words default to forbidden.

## Examples

### Stack operations

SWAP exchanges cells; DUP copies the top cell. Dot consumes the printed cell.

```forth
10 20 SWAP . . CR
3 DUP * . CR
```

Output:

```text
10 20
9
```

### Floored and truncated division

The quotient is on top of the remainder, so dot prints the quotient first. /MOD floors, /MODS truncates.

```forth
-7 3 /MOD . . CR
-7 3 /MODS . . CR
```

Output:

```text
-3 2
-2 -1
```

### Comparisons and flags

True is -1 and false is 0. OR operates on all bits of a cell.

```forth
2 3 < . 3 2 < . TRUE FALSE OR . CR
```

Output:

```text
-1 0 -1
```

### Variables and dictionary storage

A variable or CREATE word returns its data address. CELL+ advances by one eight-byte cell.

```forth
VARIABLE TOTAL
10 TOTAL ! 5 TOTAL +! TOTAL @ . CR
CREATE DATA 123 , 456 ,
DATA @ . DATA CELL+ @ . CR
```

Output:

```text
15
123 456
```

### Definitions and branches

IF and THEN compile a branch inside a colon definition.

```forth
: MAGNITUDE DUP 0< IF NEGATE THEN ;
-12 MAGNITUDE . 8 MAGNITUDE . CR
```

Output:

```text
12 8
```

### Counted loops

DO/LOOP excludes the limit. FOR/NEXT includes zero and executes u+1 bodies.

```forth
: INDICES 4 0 DO I . LOOP ;
INDICES CR
: DOWN 3 FOR I . NEXT ;
DOWN CR
```

Output:

```text
0 1 2 3
3 2 1 0
```

### Return stack

Balance user return-stack pushes and pops within the definition.

```forth
: SUM-SAVED 5 >R 7 R@ + R> DROP ;
SUM-SAVED . CR
```

Output:

```text
12
```

### Strings and byte lengths

S-quote returns address/length. TYPE consumes both; equal byte strings compare as zero.

```forth
S" hello" TYPE CR
S" abc" NIP . CR
S" abc" S" abc" COMPARE . CR
```

Output:

```text
hello
3
0
```

### UTF-8 characters

CHAR parses the next word. String lengths count UTF-8 bytes.

```forth
CHAR A . CR
S" 日本" NIP . CR
```

Output:

```text
65
6
```

### Number bases

HEX changes BASE. Explicit prefixes choose a base for an individual literal.

```forth
HEX FF DECIMAL . CR
$FF . %101 . #10 . CR
```

Output:

```text
255
255 5 10
```

### Double-cell integers

A trailing dot makes a double-cell integer, rather than a float.

```forth
123. 456. D+ D. CR
```

Output:

```text
579
```

### Floating-point conversion

Floating-point operands use a separate stack. F>S returns a cell on the data stack.

```forth
1e 2e F+ F>S . CR
9 S>F FSQRT F>S . CR
```

Output:

```text
3
3
```

### Execution tokens and quotations

Tick and a quotation produce execution tokens for EXECUTE.

```forth
: INC 1+ ;
5 ' INC EXECUTE . CR
[: 2 * ;] 7 SWAP EXECUTE . CR
```

Output:

```text
6
14
```

### Values and deferred words

TO replaces a value, +TO adds to it, and IS installs the action of a deferred word.

```forth
10 VALUE LIMIT
20 TO LIMIT 3 +TO LIMIT LIMIT . CR
DEFER ACTION
' DUP IS ACTION
6 ACTION + . CR
```

Output:

```text
23
12
```

### Local variables

The last initialized local takes the top stack item. Locals last only for the call.

```forth
: DIFFERENCE { a b -- n } a b - ;
10 3 DIFFERENCE . CR
: LOCAL-SQUARE {: n :} n n * ;
5 LOCAL-SQUARE . CR
```

Output:

```text
7
25
```

### Exceptions

CATCH returns an exception code, or zero above the action's results on success.

```forth
: FAIL -24 THROW ;
' FAIL CATCH . CR
: PASS 42 ;
' PASS CATCH . . CR
```

Output:

```text
-24
0 42
```

### Evaluating source strings

EVALUATE interprets the address/length pair as Forth source.

```forth
S" 6 7 *" EVALUATE . CR
```

Output:

```text
42
```

### Owned memory

Check allocation/release IORs with THROW and free the owned region after use.

```forth
16 ALLOCATE THROW CONSTANT MEM
123 MEM ! MEM @ . CR
MEM FREE THROW
```

Output:

```text
123
```

### Owned concatenation

S+ allocates a new owned string. Preserve its address for FREE after printing.

```forth
S" ab" S" cd" S+ 2DUP TYPE CR DROP FREE THROW
```

Output:

```text
abcd
```

### Owned string values

A string value owns its storage and lends address/length when executed.

```forth
S" ab" $VALUE LABEL
S" cd" +TO LABEL
LABEL TYPE CR
```

Output:

```text
abcd
```

### Fixed-width memory

W! and W@ store and fetch an unsigned 16-bit quantity.

```forth
CREATE SHORT-DATA 4 ALLOT
$1234 SHORT-DATA W!
SHORT-DATA W@ . CR
```

Output:

```text
4660
```

### Growing buffers

BUFFER% supplies alignment/size. Initialize the descriptor before growing and release its owned region.

```forth
CREATE BUF BUFFER% NIP ALLOT
BUF INIT-BUFFER
12 BUF ADJUST-BUFFER
BUF @ . CR
BUF FREE-MEM-VAR
```

Output:

```text
12
```

### Private wordlists

DEFINITIONS changes where a new word is registered; ALSO adds a vocabulary for lookup.

```forth
VOCABULARY EXTRA
ALSO EXTRA DEFINITIONS
: ANSWER 42 ;
FORTH DEFINITIONS
ALSO EXTRA ANSWER . CR
PREVIOUS
```

Output:

```text
42
```

### Standard and graphics key encodings

These are distinct vocabularies and encodings even though the name is identical.

```forth
ALSO EKEYS K-LEFT . PREVIOUS
REQUIRE-GRAPHICS ALSO GRAPHICS K-LEFT . PREVIOUS CR
```

Output:

```text
2147483648 258
```

### Drawing in memory

Create an image, select red and set a pixel. This does not display a window or terminal image.

```forth
REQUIRE-GRAPHICS ALSO GRAPHICS
16 16 GFX-INIT
255 0 0 COLOR
3 4 PSET
3 4 GFX-PGET . CR
```

Output:

```text
16711680
```

### GUI color roles

Set and read the face color role without running an interactive GUI frame.

```forth
REQUIRE-GUI ALSO GUI
$123456 GUI-FACE GUI-COLOR!
GUI-FACE GUI-COLOR@ . CR
```

Output:

```text
1193046
```

### Sprite data

SPRITE: owns dictionary data for the sprite. Field words return addresses to fetch with @.

```forth
REQUIRE-GAME ALSO GRAPHICS ALSO GAME
16 16 GFX-INIT
SCREEN 0 0 8 8 SPRITE: HERO
3 4 HERO PUT-SPRITE
HERO SPRITE-X @ . HERO SPRITE-Y @ . CR
```

Output:

```text
3 4
```

### An instrument of the standard sound

Instrument 1 gets a quarter pulse, an envelope in milliseconds, and an inverted left side. Setting an instrument needs the host's audio engine but plays no sound.

```forth
REQUIRE-AUDIO ALSO AUDIO
1 INSTRUMENT PULSE 16384 DUTY 10 200 40000 300 ADSR
-65535 65535 INSTRUMENT-PAN ." set" CR
```

Output:

```text
set
```

## Regeneration and checks

Entries are generated from implementation registration tables, HELP and embedded Forth libraries, without filtering by age or task number. --check detects missing descriptions and stale generated files without writing them. --sigma compares every name with the actual dictionaries of the supplied executable and checks example outputs. Build the full configuration first; a feature-disabled binary will not match.

```powershell
zig build
python scripts/word-reference.py
python scripts/word-reference.py --check --sigma zig-out/bin/sigma.exe
python scripts/check-docs.py
```

Each example runs in a fresh process. Examples do not save files, launch a shell, request input, display a window or play sound. Consult each entry's related manuals for words requiring those operations. This check does not mean that every word's behavior has been tested on a physical device.

[Back to the complete reference](WORD_REFERENCE.md)
