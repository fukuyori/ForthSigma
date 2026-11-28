# CHIP-8 for Sigma

An original interpreter for the 64x32 CHIP-8 instruction set with selectable
CHIP-48 and COSMAC VIP behaviour. SUPER-CHIP and XO-CHIP are not supported.

Run from the repository root using the existing executable:

```powershell
zig-out/bin/sigma.exe emu/chip8/chip8.fs emu/roms/c8games/PONG
zig-out/bin/sigma.exe emu/chip8/chip8.fs emu/roms/c8games/PONG vip
zig-out/bin/sigma.exe emu/chip8/test-chip8.fs
zig-out/bin/sigma.exe emu/chip8/chip8.fs -e 'S" emu/roms/c8games/MAZE" CH8-LOAD 300 CH8-TICKS CH8-DUMP BYE'
```

The optional argument after the ROM selects `vip` or `chip48`, case-insensitively.
Omitting it uses CHIP-48. An invalid profile or extra argument prints usage and
exits without opening a window. The ROM and profile are consumed with NEXT-ARG,
so Sigma does not treat the profile as another source file. When argument 1 is
absent or starts with `-` (such as `-e`), the script only defines words.
ROM opening/loading happens before the window loop. Paths, including INCLUDE
in the tests, resolve from the working directory. ROMs over 3584 bytes are rejected.

The 640x320 window displays a 64x32 image. Escape exits; F5 resets from the
kept ROM copy. Closing the window exits. Both letter cases work:

```text
CHIP-8       PC
1 2 3 C      1 2 3 4
4 5 6 D      Q W E R
7 8 9 E      A S D F
A 0 B F      Z X C V
```

## Profiles and options

The six switches are VARIABLEs; set them with `!`. FALSE is the initial value
of every switch. The profile names describe this emulator's option bundles.

| Behaviour | CHIP-48 profile (default) | VIP profile |
|---|---|---|
| Shift source (`CH8-SHIFT-VY`) | FALSE: shift Vx | TRUE: shift Vy into Vx |
| Fx55/Fx65 I update (`CH8-LOAD-INC`) | FALSE: preserve I | TRUE: advance I by x+1 |
| 8xy1/2/3 VF (`CH8-LOGIC-VF`) | FALSE: no separate VF write | TRUE: clear VF after writing Vx; zero wins for x=F |
| Draw pacing (`CH8-DISPLAY-WAIT`) | FALSE: full instruction burst | TRUE: Dxyn ends the current tick's burst |
| Digit shapes (`CH8-VIP-FONT`) | FALSE: common font | TRUE: VIP font |
| Sprite overflow (`CH8-WRAP`) | FALSE: clip | FALSE: clip |

`CH8-CHIP48 ( -- )` sets all six switches FALSE and runs once when the file
loads. `CH8-VIP ( -- )` sets the first five TRUE and CH8-WRAP FALSE. Neither
changes `CH8-SPEED` (default 10 instructions per 16667-microsecond tick).
A font option/profile change takes effect at the next CH8-RESET or CH8-LOAD.
Both fonts occupy $050, five bytes per digit. The VIP font reproduces the
shapes only: the original ROM patterns overlap at addresses 81xx.

Display wait is an approximation: the VIP waits for the display interrupt
before drawing; here Dxyn draws immediately and ends that tick's instruction
burst, limiting drawing to one sprite per tick. CH8-STEP on its own is unaffected.
CH8-TICK still decrements timers when a draw ends its burst.

Sprite start coordinates always wrap; overflow pixels clip unless CH8-WRAP
is TRUE. Drawing XORs pixels, reports erased pixels in VF, and preserves I.
Operands are captured before writes; arithmetic/shift flags and the optional
logic clear write VF last, even for x=F. With logic clear disabled, there is
no separate VF write (x=F still writes its logical result to VF).
7xkk and Fx1E have no separate flag write. I arithmetic is 16-bit; memory
accesses mask addresses to 12 bits. Bnnn uses V0.
Fx0A keeps PC on the instruction until a key is pressed and released; timers
continue. Simultaneous keys select the lowest key number.

CH8-RUN seeds randomness from UTIME when interactive execution starts.
CH8-RESET and CH8-TICK do not consult the host clock; the initial seed is 12345
and CH8-SEED can be set explicitly for reproducible headless runs.

`CH8-BLEND` (default 3) selects how many recent frames to OR for display.
Values are clamped to 1..4 when used; 1 disables blending. Each interactive
tick saves a snapshot, even without screen changes. The afterimage lasts up to
`CH8-BLEND - 1` ticks (about 33 ms by default). The CHIP-8 screen and collision
results are unchanged. `00E0` and `CH8-RESET` (including F5) clear history too.
Neither profile changes this variable. Edit its initial value or use `-e`;
there is no new command-line argument:

```powershell
zig-out/bin/sigma.exe emu/chip8/chip8.fs -e '1 CH8-BLEND ! S" emu/roms/c8games/PONG" CH8-PLAY BYE'
```

XOR erase and redraw can be more than one tick apart in PONG. The user's
600-tick measurement with stationary paddles found missing paddles in 265 of
599 displayed frames without blending, 68 with two frames, and 0 with three.
`CH8-BLEND-FRAME ( -- )` updates history and fills `CH8-SHOWN` without host
output; `CH8-PAINT` draws that buffer.

## Differences from the VIP

In addition to the selectable behaviours and display/font approximations above,
the following are deliberately not implemented:

- The tone while a key is held during Fx0A.
- The minimum tone value 02.
- The 12-level stack: this emulator uses 16 levels.
- Machine-language subroutines (0nnn): ignored except clear/return.
- The instruction timing of the 1802.

## Errors and execution

Unknown instructions and stack errors print diagnostics before throwing.
The emulator's named throw codes are:

| Code | Constant | Meaning |
|---|---|---|
| -4100 | CH8-ERR-ROM-SIZE | ROM exceeds 3584 bytes |
| -4101 | CH8-ERR-ROM-READ | Short ROM read |
| -4102 | CH8-ERR-OPCODE | Unknown/invalid opcode |
| -4103 | CH8-ERR-STACK-UNDERFLOW | Return with empty stack |
| -4104 | CH8-ERR-STACK-OVERFLOW | Call with full stack |

File operations also propagate Sigma's file I/O errors.

Interactive ticks execute instructions, decrement timers, then feed optional
48 kHz mono 440 Hz PCM. Audio unavailable/open failure means silence. Redraw
occurs only when the blended image differs from the last shown image, at most once per tick. Late ticks catch up; lateness
over five ticks resets the deadline. CH8-RUN catches errors, closes PCM, and rethrows.

Public words: CH8-LOAD / CH8-PLAY `( addr len -- )`, CH8-RESET, CH8-STEP,
CH8-TICK, CH8-TICKS `( n -- )`, CH8-DUMP, CH8-RUN, CH8-CHIP48 and CH8-VIP
(the others have effect `( -- )`). CH8-TICK has no host input, window output,
or sound. State uses the CH8- names in the script; CH8-KEYS contains sixteen
bytes (0/1), suitable for headless input.

## Making a stand-alone executable

`SAVESYS` writes the current dictionary into a stand-alone executable, and
`APP-ENTRY!` registers the word that executable calls once at start-up. Write a
file such as `make-chip8.fs`:

```forth
INCLUDE emu/chip8/chip8.fs
' CH8-START APP-ENTRY!
SAVESYS CHIP8.EXE
BYE
```

Run it from the repository root:

```powershell
.\zig-out\bin\sigma.exe make-chip8.fs
```

Start the executable with the path of a ROM, optionally followed by `vip` or
`chip48`:

```powershell
.\CHIP8.EXE emu\roms\c8games\PONG
.\CHIP8.EXE emu\roms\c8games\PONG vip
```

- `INCLUDE emu/chip8/chip8.fs` loads the emulator. `CH8-START` at the end of
  `chip8.fs` finds no argument here (Sigma removes the file names it processes
  from the arguments), so it does nothing.
- `' CH8-START APP-ENTRY!` registers the start-up word. It handles the
  arguments the same way as `sigma emu/chip8/chip8.fs ...`: a ROM path and an
  optional profile, or `padtest`.
- `SAVESYS CHIP8.EXE` writes the executable. Because an entry is registered, it
  starts in `CH8-START` and does not enter the Forth prompt.

Notes:

- Every argument of `CHIP8.EXE` goes to the emulator. To pass Sigma options,
  write `CHIP8.EXE --sigma <options> -- <arguments>`.
- `pads.txt` is still read as `emu/chip8/pads.txt` relative to the current
  directory. Started elsewhere, the executable silently uses the default pad
  assignment.
- The usage line still reads `Usage: sigma emu/chip8/chip8.fs ...`.
- Without arguments the executable exits without a message (status 0).
- Make the executable again after changing `chip8.fs` or rebuilding
  `sigma.exe`. An executable saved by another build stops with an error at
  start-up when the dictionary format differs.
- The executable is about 16 MB. Created at the repository root it shows up as
  untracked in `git status`; files under `.work/` are ignored.

## Verification

The suite prints a short label, expected value and actual value for each failed
check, followed by `passed N failed M`. Failures throw before BYE and give
process status 1. It runs MAZE and PONG headlessly for 300 ticks each and prints
MAZE once. The ROMs are not in the repository (`emu/roms/` is ignored by Git);
when `emu/roms/c8games/MAZE` or `PONG` is missing, that check is skipped with an
`INFO skipped, ROM not found:` line. This run passed 3257 checks, failed 0, exit status 0; the silent audio
stream open/close cycle and ST=0 checks run without submitting samples. The test source itself contains the configuration
fixture, so no temporary files are created.
It covers both settings of the new switches, x=F logic destinations, burst
termination, standalone steps, both fonts and all six profile settings.

With a nonexistent ROM, default, `ViP` and `ChIp48` each failed at OPEN-FILE
before the window loop (status 1); an invalid profile printed usage (status 0).
Interactive input/window, real-time pacing, audible PCM, UTIME seeding during
CH8-RUN, and Ctrl+C cleanup were not exercised. The audio-free build was not
available for testing; its branch uses conditional definitions.

## References

- Cowgod, *Chip-8 Technical Reference v1.0*.
- Matthew Mikolay, *Mastering CHIP-8*.
- Laurence Muller, *How to write an emulator (CHIP-8 interpreter)*.
- RCA, *COSMAC VIP CDP18S711 Instruction Manual* (1978), section III Table I
  and Appendix C interpreter listing.
- Erik Bryntse, *SUPER-CHIP v1.1 documentation* (CHIP-48 instruction table only).

No code was taken from these references. The VIP requirements and digit bytes
were supplied with task 1469; external sources were not fetched in this round.
Layout follows `examples/paddle.fs`.

## Gamepad

Both mapped and raw pad 0 work. `CH8-INPUT` polls once per pass; a negative
`GAMEPAD-POLL` disables polling until the next `CH8-RUN`. Keyboard and pad
keys are ORed, including the press/release wait of `Fx0A`.

The 36 inputs are `up down left right` (0..3), then `b0`..`b31` (4..35).
Directions combine hat 0 (up=1, right=2, down=4, left=8), axes 0/1 (X/Y)
with strict thresholds below -16384 or above 16384, and, on mapped pads,
d-pad buttons 11..14. Counts are checked before querying any input.
Each raw axis independently ignores -32768 until a different value has been
seen in this run; subsequent -32768 values work normally.

`bN` means Sigma button N, using mapped or raw numbering as appropriate.
Aliases `a b x y back start l r` mean `b0 b1 b2 b3 b4 b6 b9 b10`.
On raw pads these are just button numbers and may not match printed labels.
Targets are `-` (none), a hex digit `0`..`F`, `reset` (F5), or `quit` (Esc).
Actions fire only on each input's press edge. Defaults are
`up=2 down=8 left=4 right=6 b0=5`, all others unmapped. Mapped pads also get
`b6=reset b4=quit`; raw pads get these actions only through explicit settings.

Run from the repository root. Configuration is `emu/chip8/pads.txt`, with
lines `NAME input=target ...`. NAME is the ROM basename (either slash type);
`*` applies to every ROM. Names and targets are case-insensitive. Empty lines
and `#` comments are ignored, even without a space before `#`. Lines support
255 characters. Invalid tokens warn with filename, line number and token,
then parsing continues. A missing file is silent.

Order: built-in defaults, every `*` line in file order, then every matching
ROM line in file order. Lines accumulate; only named inputs change, and the
last valid assignment wins. Two file passes build a 36-cell overlay (`-2`
means not set). The first pad observation selects mapped/raw defaults and
applies that overlay. `CH8-PLAY` and command-line play load the configuration.
`CH8-LOAD` alone clears it and restores raw defaults pending pad detection.
`CH8-RESET` preserves map and input history. `CH8-RUN` resets detection and history.

Find a raw pad's button numbers with:

```powershell
sigma emu/chip8/chip8.fs padtest
# Or the existing repository executable:
zig-out/bin/sigma.exe emu/chip8/chip8.fs padtest
```

Argument 1 must equal `padtest`, case-insensitively. It prints mapped flag,
held directions and held button numbers about ten times per second, exiting
on a keyboard key (`INKEY`) or after 30 seconds. It opens no window and plays
no sound. Use the numbers in settings such as `* b9=reset b8=quit`.

| Word / storage | Meaning |
| --- | --- |
| `CH8-PAD-DEFAULT ( mapped -- )` | Set built-in defaults; does not apply the overlay |
| `CH8-PAD! ( target input# -- )` | Set target -1..17 for input 0..35; invalid arguments ignored |
| `CH8-PAD-LOAD ( rom-addr rom-u -- )` | Load the common and ROM overlay from pads.txt |
| `CH8-PAD-LOAD-FILE ( rom-addr rom-u file-addr file-u -- )` | Load from a specified file |
| `CH8-PAD-MAP` | 36 cells; -1=none, 0..15=key, 16=reset, 17=quit |
| `CH8-PAD-KEYS`, `CH8-PC-KEYS` | Separate 16-byte key arrays |
| `CH8-MERGE-KEYS ( -- )` | Merge into `CH8-KEYS` without host input |
| `CH8-PAD-STATE ( dirs buttons mapped -- )` | Apply direction bits 0..3 and a 32-bit button mask, including action edges; no host input |
| `CH8-PAD-DIRS ( hat x y buttons mapped -- dirs )` | Combine direction sources |
| `CH8-PAD-AXIS-VALUE ( value axis mapped -- value )` | Suppress raw startup values for axis 0 or 1 |
| `CH8-PAD-PRINT ( dirs buttons mapped -- )` | Print one diagnostic line |
| `CH8-PAD-TEST ( -- )` | Run the windowless diagnostic for up to 30 seconds |

Sources: `docs/WORD_REFERENCE.ja.md`, entries `GAMEPAD-HAT`, `GAMEPAD-HATS`,
`GAMEPAD-AXES`, `GAMEPAD-AXIS`, `GAMEPAD-BUTTON-COUNT`, `GAMEPAD-BUTTONS`;
`docs/GRAPHICS_AND_SOUND.ja.md` line 366 describes raw-axis startup values.
The six shipped ROM direction meanings require gameplay confirmation.
Tests cover host-free state conversion, parsing, accumulation/precedence,
aliases, edges, axis startup and fixed-value diagnostic formatting.
Physical pad operation and the diagnostic wait loop have not been exercised.

Diagnostic examples: `mapped=0 directions=- buttons=-` and
`mapped=0 directions=up,left buttons=0,9`. Empty fields use `-`; multiple inputs use commas.
