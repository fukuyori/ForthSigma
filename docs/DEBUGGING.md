# Debugging FORTH/Σ programs

Japanese version: [DEBUGGING.ja.md](DEBUGGING.ja.md). This English version is the primary one.

This guide shows how to find what is wrong with a Forth program in FORTH/Σ: where an error came up, why a program does not end, which words ran and with what on the stack, what changes a cell, and which code is slow or never runs. Everything here works from the command line, in one start of `sigma` that ends by itself, so that a program — an agent, a script, a CI job — can use it as well as a person at the prompt.

The [user manual](USER_MANUAL.md) has the same features word by word; this guide is ordered by what you want to find out.

## What to use

| You want to know | Use | Where it writes |
|---|---|---|
| Where an error came up | Nothing: the backtrace follows the message | standard output |
| Why a program does not end | `--max-steps N` | standard output |
| Which words ran, in what order, with what stack | `--trace`, `--trace-limit N` | standard error |
| The stack at one place in a definition | `~~`, `~~BT`, `~~1BT`, `ONCE` | standard error |
| What a word does, one operation at a time | `DBG name`, `BREAK:`, `BREAK"` | standard output |
| When a value or a variable is used | `~~VALUE`, `~~VARIABLE` | standard error |
| What changes a cell of memory | `WATCH`, `UNWATCH` | standard error |
| Which words take the most work | `--profile` | standard error |
| Which parts of the code never ran | `--coverage`, `.COVER-RAW`, `COV%`, `.COVERAGE` | standard output |
| Mistakes that can be seen without a test | `--lint` | standard output |
| A layout that shows the structure | `--format`, `--format-check` | the files |
| All of the above, for a program to read | `--debug-log FILE` | a file of JSON Lines |

The options come before the files and the other arguments, as the size options do, and `--` ends them:

```text
sigma [options] [file ...] [-e "text"] ...
```

The examples below use this file, `prog.fs`:

```forth
: SQUARE ( n -- n ) DUP * ;
: SUMSQ ( a b -- n ) SQUARE SWAP SQUARE + ;
: AVERAGE ( sum n -- avg ) / ;
: REPORT ( a b n -- )
   >R SUMSQ R> AVERAGE . ;
VARIABLE SCORE
: BUMP ( -- ) 1 SCORE +! ;
: SPIN ( -- ) BEGIN BUMP AGAIN ;
: TELL ( n -- ) DUP 0< IF DROP ." minus" ELSE 0= IF ." zero" THEN THEN ;
```

## An error: the backtrace

When an error that no `CATCH` caught comes up in a colon definition, the message is followed by the definitions that were running and the stack. Nothing has to be turned on.

```text
> sigma prog.fs -e "3 4 0 REPORT"
DIVISION BY ZERO !
BACKTRACE:
  AVERAGE prog.fs:3
  REPORT prog.fs:5
STACK: <0>
```

Read it from the top: the error came up in `AVERAGE`, at line 3 of `prog.fs`; `AVERAGE` was called by `REPORT`, at line 5. `STACK:` is the data stack as the error left it (the word that failed has taken its arguments), in the form of `.S`; a `FLOAT STACK:` line follows when the floating-point stack holds something. When the input itself is a file, its `file:line:` stands before the message.

- A short definition whose code was copied into its caller is marked `(INLINE)`.
- A recursion is one line with the number of times (`DEEP prog.fs:4 *32`); `... 4064 MORE` counts the callers beyond the 32 that are kept.
- An error outside a definition, `ABORT`, `QUIT`, and an error that `CATCH` caught have no backtrace.
- The exit status is 1.

## A program that does not end: `--max-steps`

`--max-steps N` ends the run after `N` operations of compiled code, with the error `STEP LIMIT !` and its backtrace, which says where the program was. `CATCH` does not catch it.

```text
> sigma --max-steps 1000 prog.fs -e "SPIN"
STEP LIMIT !
BACKTRACE:
  BUMP prog.fs:7
  SPIN prog.fs:8
STACK: <0>
```

The count starts again for each file, each `-e`, and each line typed. An agent that runs a program it does not know should always give a limit: a program that waits for a key or loops for ever would otherwise never return.

## What ran: `--trace`

`--trace` shows each colon definition as it starts (`>`) and as it ends (`<`), with the depth of the data stack and its top nine items, indented by the nesting.

```text
> sigma --trace prog.fs -e "3 4 5 REPORT BYE"
> REPORT <3> 3 4 5
  > SUMSQ <2> 3 4
    > SQUARE <2> 3 4
    < SQUARE <2> 3 16
    > SQUARE <2> 16 3
    < SQUARE <2> 16 9
  < SUMSQ <1> 25
  > AVERAGE <2> 25 5
  < AVERAGE <1> 5
< REPORT <0>
```

The line of a word's end shows what it left, so a word that leaves the wrong thing is the one whose `<` line first looks wrong. `--trace-limit N` ends the trace after `N` lines with the line `TRACE LIMIT`, and the program goes on; give it whenever the program has a loop. A word that an error ended has no `<` line.

## The stack at one place: `~~` and `~~BT`

For one place in one definition, put `~~` there: it shows where it is (`file:line:column:`) and the whole data stack each time it runs. `~~BT` shows the callers too, and `~~1BT` does so the first time only. `ONCE ... THEN` runs what is between them once, which keeps a `~~` in a loop to one line.

```text
> sigma prog.fs -e ": T 5 ~~ SQUARE ~~BT DROP ; : CALLER T ; CALLER BYE"

*the terminal*:0:7:<1> #5

*the terminal*:0:17:<1> #25
BACKTRACE:
  CALLER
```

These are gforth's words, with gforth's form of the line.

## One operation at a time: `DBG` and `BREAK:`

`DBG name` runs a colon definition one operation at a time. Before each operation it shows the operation and `->` and waits for a key; then the operation runs, and what it writes and the stack follow on the same line.

```text
> printf '3 4 DBG SUMSQ\n\n\n\n\n\n. BYE\n' | sigma prog.fs
FORTH/Sigma 0.10.0  MIT License
Type `help' for basic help
: SUMSQ
[ 2 ] 3 4
SQUARE         -> [ 2 ] 3 16
SWAP           -> [ 2 ] 16 3
SQUARE         -> [ 2 ] 16 9
+              -> [ 1 ] 25
;              ->  OK
25  OK
```

| Key | Action |
|---|---|
| Enter | Runs the operation; a word it calls runs without stopping. |
| `n` | Goes into the definition the operation calls; at its `;` the steps go on in the caller. |
| `u` | Runs the rest of the definition without stopping. |
| `d` | Ends the steps and runs the rest. |
| `s` | Ends the run with the error `debugger aborted`. |

The keys are read as `KEY` reads them, so they can come from a pipe, as above: an agent sends the line that starts the steps and then one key for each step. At the end of the input the steps end as with `d`.

`BREAK:` in a definition starts the steps at that place, and `BREAK" text"` shows `BREAK AT: text` first. Use them when the place of interest is deep in a program and stepping from its start would take long.

## When a value changes: `~~VALUE` and `~~VARIABLE`

`x ~~VALUE name` defines a `VALUE` whose every `TO` is shown, and `~~VARIABLE name` a `VARIABLE` whose every use by name is shown: the place, the data stack, and the name. Change `VALUE` to `~~VALUE` in the source, run, and change it back.

## What changes a cell: `WATCH`

`a-addr WATCH` shows each change of the cell from then on, with the definition and the place of the word that made it. The change is found however it is made — through the name, through an address that was worked out, or by `MOVE` or `FILL` over the cell — so it finds the word that overwrites a cell it should not touch.

```text
> sigma prog.fs -e "SCORE WATCH BUMP 7 SCORE ! BYE"
WATCH: 81920 changed from 0 to 1
  in BUMP prog.fs:7
WATCH: 81920 changed from 1 to 7
```

The second change was made at the prompt, so it has no definition. `a-addr UNWATCH` ends it for that cell. Up to eight cells are watched. Run `WATCH` before the program is started, outside a definition: a definition that is already running is not looked at.

## What takes the most work: `--profile`

`--profile` shows, when the program ends, how often each colon definition was called and how many operations it ran.

```text
> sigma --profile prog.fs -e "3 4 5 REPORT BYE"
PROFILE: 19 OPERATIONS
     CALLS        SELF       TOTAL  WORD
         2           6           6  SQUARE prog.fs:1
         1           6          19  REPORT prog.fs:4
         1           5          11  SUMSQ prog.fs:2
         1           2           2  AVERAGE prog.fs:3
```

`SELF` is the operations of the definition's own code, `TOTAL` those between its start and its end with the words it called. The counts are of operations, not of time, so two runs give the same numbers and a change can be compared exactly. A built-in word is one operation whatever it does: time spent drawing or waiting is not in the profile.

## What never ran: `--coverage`

`--coverage` counts how often each block of the code runs — the code after the name of a definition and after `IF`, `ELSE`, `THEN`, `BEGIN`, `WHILE`, `REPEAT`, `UNTIL`, `AGAIN`, `DO`, `LOOP`, `CASE`, `OF`, `ENDOF`, `ENDCASE`, and from the start of each further line of a definition. gforth's words show the counts:

```text
> sigma --coverage prog.fs -e "3 4 5 REPORT -1 TELL CR COV% CR .COVERAGE BYE"
5 minus
53.3% coverage

: SQUARE ( 2)  ( n -- n ) DUP * ;
: SUMSQ ( 1)  ( a b -- n ) SQUARE SWAP SQUARE + ;
: AVERAGE ( 1)  ( sum n -- avg ) / ;
: REPORT ( 1)  ( a b n -- )
 ( 1)    >R SUMSQ R> AVERAGE . ;
VARIABLE SCORE
: BUMP ( 0)  ( -- ) 1 SCORE +! ;
: SPIN ( 0)  ( -- ) BEGIN ( 0)  BUMP AGAIN ( 0)  ;
: TELL ( 1)  ( n -- ) DUP 0< IF ( 1)  DROP ." minus" ELSE ( 0)  0= IF ( 0)  ." zero" THEN ( 0)  THEN ( 1)  ;
```

A `( 0)` is code that the run never reached: here `BUMP`, `SPIN`, and the `ELSE` part of `TELL`. `.COVER-RAW` gives the same counts one block on a line, as `file:line:column: count`, which is the form for a program to read. The places and counts are those gforth gives for the same text after `require coverage.fs`.

## Mistakes without a test: `--lint`

`--lint` loads the files as usual and then checks the definitions they made. Forth source cannot be read without running it, so the code outside definitions runs; give `--max-steps` for a program that does not end by itself.

```text
> sigma --lint prog.fs
prog.fs:4: UNUSED: REPORT is not used in the files
prog.fs:8: UNUSED: SPIN is not used in the files
prog.fs:9: UNUSED: TELL is not used in the files
LINT: 1 DEFINITIONS WITHOUT A FIXED STACK EFFECT WERE NOT CHECKED FOR IT
LINT: 3 FINDINGS
```

| Check | What it finds |
|---|---|
| `STACK EFFECT` | Code that does not keep to the stack comment `( a b -- c )` after the name |
| `STACK DEPTH` | Paths that meet with different stack depths (`IF 1 THEN`) |
| `RETURN STACK` | `>R` without `R>`, or `R>` without `>R` |
| `UNREACHABLE` | Code after `EXIT` or `AGAIN` |
| `REDEFINED` | A name that an earlier word already has |
| `UNUSED` | A word that no file uses |

The exit status is 0 without findings and 2 with them. A definition with a word whose effect is not fixed (`EXECUTE`, `?DUP`, a `DEFER`, a recursion, a loop without an end — `SPIN` above) is not checked for the three stack findings; the report counts these. The most useful habit is to write the stack comment after every name: the check then finds a `DROP` too few or a `SWAP` too many before the program is run.

## A layout that shows the structure: `--format`

`--format` sets the indentation of the files by their colon definitions and control structures and removes the blanks at the ends of lines. The files are read as text and not run, and only the blanks before the first and after the last character of a line change, so the program is the one it was. `--format-check` changes nothing and says how many lines would change, with exit status 2 when there are any.

```text
> sigma --format-check prog.fs
prog.fs: FORMATTED ALREADY
```

Format before reading a program whose indentation does not match its structure: an `IF` without its `THEN` then shows as lines that never come back out.

## For a program to read: `--debug-log`

`--debug-log FILE` writes the errors, the trace, the profile, the findings of `--lint`, and the changes of watched cells to `FILE`, one JSON object on each line. Each line is written when its event happens, so the log is whole also when the program ends badly.

```text
> sigma --debug-log run.jsonl --trace --profile prog.fs -e "3 4 0 REPORT"
```

```text
{"event":"start","version":"0.10.0"}
{"event":"enter","word":"REPORT","depth":0,"stack_depth":3,"stack":[3,4,0]}
{"event":"enter","word":"SUMSQ","depth":1,"stack_depth":2,"stack":[3,4]}
...
{"event":"enter","word":"AVERAGE","depth":1,"stack_depth":2,"stack":[25,0]}
{"event":"error","message":"DIVISION BY ZERO !","code":-10,"backtrace":[{"word":"AVERAGE","file":"prog.fs","line":3},{"word":"REPORT","file":"prog.fs","line":5}],"more":0,"stack_depth":0,"stack":[],"float_stack_depth":0,"float_stack":[]}
{"event":"profile","operations":16}
{"event":"profile_word","word":"SQUARE","file":"prog.fs","line":1,"calls":2,"self":6,"total":6}
```

With a log, the trace and the profile go to the log and not to standard error; an error is still shown as without one. The events are `start`, `error`, `enter`, `exit`, `trace_limit`, `watch`, `lint`, `lint_end`, `profile`, and `profile_word`; the [user manual](USER_MANUAL.md) lists the members of each. A reader should pass over members and events it does not know.

## Notes for agents

- **One start, one answer.** Give the program and what to run as arguments, end with `BYE`, and read the output: `sigma [options] prog.fs -e "MAIN BYE"`. Without `BYE` the interactive prompt follows; redirect the input from nothing (`< /dev/null`, `< NUL`) so that it ends.
- **Always limit the run** of a program you did not write or have just changed: `--max-steps 10000000`. Add `--trace-limit` to every `--trace`.
- **Read the exit status first**: 0 is a run without an error, 1 an error (the message and the backtrace are in the output), 2 findings of `--lint` or lines that `--format-check` would change.
- **Keep the streams apart.** The program's own output, the error with its backtrace, the steps of `DBG`, and the findings of `--lint` are on standard output; the trace, the profile, `~~`, and `WATCH` are on standard error. With `--debug-log` the trace and the profile are in the log only.
- **Prefer the log** when the output is to be worked on: each line of it is one JSON object.
- **A good order of work**: run with `--max-steps`; on an error read the backtrace; when the place is known but not the cause, `--trace --trace-limit 200`; when a value is wrong but not where it went wrong, `WATCH` its cell; when the logic of one word is in doubt, `DBG` it with the keys from a pipe. Before handing the program back, `--lint` and `--format-check`.

## What it costs

The usual loop that runs compiled code does none of this: without these options and words a program runs as fast as without the features. `--max-steps`, `--trace`, `--profile`, `--coverage`, a `DBG`, a compiled `BREAK:`, and a `WATCH` make the program run in a second loop that counts operations, which is slower; `--trace`, `--profile`, and `--coverage` also call short definitions instead of copying them into their callers.

`zig build -Ddebug=false` builds FORTH/Σ without any of these features: no backtrace, none of the options, none of the words. Use it for a program that is delivered, when the size of the executable matters.

## Reference

| Option | Value | Effect |
|---|---|---|
| `--max-steps` | `N` | Ends compiled code after `N` operations with `STEP LIMIT !` |
| `--trace` | — | Shows the colon definitions as they start and end |
| `--trace-limit` | `N` | Ends the trace after `N` lines |
| `--profile` | — | Shows the calls and the operations of each definition at the end |
| `--coverage` | — | Counts the blocks, for `.COVER-RAW`, `COV%`, and `.COVERAGE` |
| `--debug-log` | `FILE` | Writes the events to `FILE` as JSON Lines |
| `--lint` | — | Checks the definitions after the files are loaded; no prompt |
| `--format` | — | Sets the indentation of the files; they are not run |
| `--format-check` | — | Says how many lines `--format` would change |
| `--format-indent` | `N` | The blanks of one step of `--format` (3) |

A value follows its option (`--max-steps 1000`) or `=` (`--max-steps=1000`).

| Word | Stack | From |
|---|---|---|
| `~~`, `~~BT`, `~~1BT` | `( -- )` | gforth |
| `ONCE` | `( -- )` | gforth |
| `DBG` | `( "name" -- )` | gforth |
| `BREAK:`, `BREAK"` | `( -- )` | gforth |
| `~~VALUE` | `( x "name" -- )` | gforth |
| `~~VARIABLE` | `( "name" -- )` | gforth |
| `+LTRACE`, `-LTRACE` | `( -- )` | gforth |
| `.COVER-RAW`, `COV%`, `.COVERAGE` | `( -- )` | gforth |
| `WATCH`, `UNWATCH` | `( a-addr -- )` | FORTH/Σ |
| `ASSERT(` | `( "code)" -- )` | gforth |

Where a word of gforth differs from gforth's, the [word compatibility list](COMPATIBILITY.md) says how.
