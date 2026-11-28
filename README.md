# FORTH/Σ for Zig

Japanese version: [README.ja.md](https://github.com/fukuyori/ForthSigma/blob/main/README.ja.md). This English version is the primary one.

This project implements the language core of FORTH/Σ (FORTH/Sigma) as a native port that runs on Zig. It uses the description of FORTH/Σ and the Z80 source listing published in the monthly magazine ASCII in 1982 as material for studying the specification. It does not execute or emulate Z80 instructions or machine code.

## Current implementation

- It uses 64-bit cells and a logical memory of 64 MiB by default: 32 MiB for the dictionary (120 KiB of it reserved for the system, input, and block buffers, the rest for the data area), an `ALLOCATE` heap of the same size, and 64 KiB for local variables. Each stack holds 4096 entries. The sizes can be chosen when Sigma starts, with the options of gforth (`-m`, `-d`, `-r`, `-f`, `-l`). The true value is -1, and division is floored.
- Floating-point numbers (double precision) are handled on a separate stack. A number that contains `E`, such as `1E` or `1.5e0`, is a floating-point number, and the F words such as `F+`, `F.`, `FSQRT`, and `FCONSTANT` are available.
- It supports interactive input, dictionary search, number input, and word definition and compilation.
- Stack operations, arithmetic, comparison, and logical operations, memory operations, and variables, constants, values, and arrays are available.
- IF ... ELSE ... THEN, BEGIN ... END/UNTIL, BEGIN ... AGAIN, BEGIN ... WHILE ... REPEAT, CASE ... ENDCASE, DO ... LOOP, DO ... +LOOP, LEAVE, and EXIT are available.
- The compiler can be extended with IMMEDIATE, POSTPONE, RECURSE, and CREATE ... DOES>.
- It supports base changes with HEX, DEC, and OCT, and output of numbers, characters, and strings.
- Strings such as `S"`, double-cell integers (128-bit) in the `123.` form, number formatting with `<<# # #S #> #>>`, `ACCEPT`, `EVALUATE`, and `KEY` are available.
- WORDS, FORGET, and BYE are provided as interactive words.
- Graphics, an extension of this port (`REQUIRE-GRAPHICS`): an image in memory with lines, shapes, painting, graphs, and text (a built-in ASCII font, BDF fonts, and on Windows the system's fonts), shown on the terminal (half blocks or Sixel), in Sigma's own window (Windows, macOS, and Linux on X11 or XWayland), or in a Tk window; more images to draw on and copy between, read from PNG, BMP, and PPM files; keys and the mouse (`INKEY`, `MOUSE`, `MOUSE-EVENT`); a GUI drawn each frame (`REQUIRE-GUI`); sprites, tile maps, and palettes for games (`REQUIRE-GAME`); and Tcl/Tk scripts run in a `wish` that Sigma starts (`TCL`, `TCL-EVAL`, `TCL-EVENT`). Tcl/Tk is not linked into Sigma and must be installed to use the TCL words.
- Sound, an extension of this port (`REQUIRE-AUDIO`): MSX BASIC's `PLAY` and `BEEP` with its music macro language, played by an audio thread while the program goes on, with a standard sound of 16 voices and instruments (envelopes, filters, modulation, reverb); libraries in `include/` that give it the character of the sound chips of the MSX (with `SOUND`), the Atari ST, the NES, the C64, Konami's SCC, and the Amiga, alone or together; recorded sound from WAV files and sound effects; and ProTracker modules (MOD files). See [Sound](https://github.com/fukuyori/ForthSigma/blob/main/docs/GRAPHICS_AND_SOUND.md#sound) and `examples/music.fs`.
- The EXTENSION vocabulary, an extension of this port (`REQUIRE-EXTENSION`): the host OS, terminal modes and size, waiting for key, mouse, and paste events, computation tasks that run beside the program and can be cancelled, file and path utilities, grapheme clusters, and limited execution. See the [extension manual](https://github.com/fukuyori/ForthSigma/blob/main/docs/EXTENSION.md).
- The dictionary, compiled definitions, memory, and input and output are separated from the host environment, so the program is easy to port to other operating systems and CPUs.

For the supported words and the porting decisions, see the [implementation notes](https://github.com/fukuyori/ForthSigma/blob/main/docs/IMPLEMENTATION.md). For the language specification compiled from the sources, see the [FORTH/Σ specification](https://github.com/fukuyori/ForthSigma/blob/main/docs/SPEC.md). The implementation is under development and does not support every word in the book or machine-specific features.

For usage and the list of the built-in words registered now, see the [user manual](https://github.com/fukuyori/ForthSigma/blob/main/docs/USER_MANUAL.md); for the graphics and the sound, see the [graphics and sound manual](https://github.com/fukuyori/ForthSigma/blob/main/docs/GRAPHICS_AND_SOUND.md); for the EXTENSION vocabulary, see the [extension manual](https://github.com/fukuyori/ForthSigma/blob/main/docs/EXTENSION.md); for finding what is wrong with a program, see the [debugging guide](https://github.com/fukuyori/ForthSigma/blob/main/docs/DEBUGGING.md).

For individual descriptions of all current words and syntax, see the [complete word reference](docs/WORD_REFERENCE.md) and its [reading guide and examples](docs/WORD_REFERENCE_GUIDE.md).

The defining words (BUILDS/DOES) that let users make words that hold data are also supported.

`SAVE filename` and `LOAD-DICTIONARY filename` save user-defined words and load them additionally. A standalone executable is made with a separate extension word, `SAVESYS filename.exe`.
Standard `LOAD` executes numbered blocks in `blocks.fb`; `LOAD-DICTIONARY filename` loads a saved dictionary image.


For the support status of each word, see the [compatibility list](https://github.com/fukuyori/ForthSigma/blob/main/docs/COMPATIBILITY.md). For the distinction between the specification settled by the sources and the porting decisions, see [decisions and open issues](https://github.com/fukuyori/ForthSigma/blob/main/docs/DECISIONS.md).

At present, LIST, source file and editor operations, the CP/M file functions, the PC-8001 monitor functions, and words that use Z80 machine code are not supported.

### Graphics modes

There are no numbered screen modes, such as `SCREEN 1` of BASIC. A program makes one image of any size with `GFX-INIT` ( w h -- ), 1 to 16384 pixels a side, and chooses separately where `SHOW` shows it and with how many colors. The image itself always keeps full color, and files are saved in full color.

| Where `SHOW` shows the image | Words | Where it works |
| --- | --- | --- |
| Terminal, half blocks (two pixels a character) | `DISPLAY-TERMINAL TERMINAL-BLOCKS` | every system |
| Terminal, Sixel | `DISPLAY-TERMINAL TERMINAL-SIXEL` | terminals that support Sixel |
| Window of Sigma's own | `DISPLAY-WINDOW` | Windows, macOS, and Linux on X11 or XWayland |
| Tk window | `DISPLAY-TK` | where Tcl/Tk is installed |

Until one is chosen, `SHOW` uses Sigma's own window when the host has one; otherwise it uses the Tk window on a desktop when Tcl/Tk is installed, and the terminal with half blocks otherwise. `DISPLAY-AUTO` makes the next `SHOW` choose again in this order. On Linux, `-Dx11=false` builds without the X11 window. `n DISPLAY-COLORS` shows the image in full color (0, the default), black and white (2), the 16 ANSI colors (16), or xterm's 256 colors (256), and `TRUE DITHER` mixes the fewer colors in a Bayer pattern. `w h WINDOW-SIZE` shows the image larger in the window and the Tk window, for example `160 120 GFX-INIT 640 480 WINDOW-SIZE` shows each pixel as 4 by 4.

Tcl/Tk is not part of Sigma, so the Tk window needs it installed. On Debian and Ubuntu it is the `tk` package, on Fedora and RHEL `sudo dnf install tk`, and on Arch `sudo pacman -S tk`; each of them puts a `wish` on the `PATH`.

    sudo apt install tk

On macOS, install Tcl/Tk with `brew install tcl-tk`: the Tcl/Tk 8.5 that macOS comes with (`/usr/bin/wish`) no longer starts on recent macOS, which kills it as it starts, so Sigma passes over it and uses another `wish` on the `PATH`, else Homebrew's (`/opt/homebrew/bin/wish` or `/usr/local/bin/wish`) or MacPorts's (`/opt/local/bin/wish`). `SIGMA_WISH` (or `TCL-PROGRAM`) names another one. On Windows nothing has to be installed when Git for Windows is there, since Sigma falls back to its `wish`. With Tcl/Tk in place, a program that calls `SHOW` opens a window on a Linux or macOS desktop, for example `sigma examples/hopper.fs`.

```forth
REQUIRE-GRAPHICS  ALSO GRAPHICS
160 120 GFX-INIT  255 255 0 COLOR  80 60 40 CIRCLE
DISPLAY-TERMINAL  16 DISPLAY-COLORS  TRUE DITHER  SHOW
```

For the details, see the [graphics modes manual](https://github.com/fukuyori/ForthSigma/blob/main/docs/GRAPHICS_MODES.md).

## Building and running

In an environment with Zig 0.17.1 installed, run these commands from the root of the repository.

    zig build
    ./zig-out/bin/sigma.exe

On Linux and macOS, the same `zig build` builds the program, and the executable is `zig-out/bin/sigma`.

    zig build
    ./zig-out/bin/sigma

On Linux, when `zig build` fails on the C library's headers of the distribution (`'gnu/stubs-32.h' not found`), give the musl target, which uses the headers that come with Zig: `zig build -Dtarget=x86_64-linux-musl`.

The core regression tests run with zig build test.

To specify another Zig target, use zig build -Dtarget=<triple>.

The current product version is recorded in [`VERSION`](https://github.com/fukuyori/ForthSigma/blob/main/VERSION). The Windows release build and the Inno Setup installer are made with the following PowerShell scripts. The installers (`dist\installer\sigma-<version>-windows-x86_64-setup.exe` and `dist\installer\sigma-<version>-windows-x86_64-forth2012-setup.exe`) use the value in `VERSION`, as the executable does.

    .\scripts\build-release.ps1
    .\scripts\build-installer.ps1

`build-release.ps1` builds the full version (`dist\release`) and the Forth 2012 profile (`dist\release-forth2012`). The latter keeps standard word sets, including floating point and file access, and omits graphics, sound, and Sigma's extension vocabulary. `-Variant Full` or `-Variant Forth2012` builds only one of them; `-OutputDirectory` and `-Forth2012OutputDirectory` change the output directories. Even when `-Target` is not given, the CPU is baseline (`-Dcpu=baseline`). `build-installer.ps1` makes an installer for each profile, and `-Variant Full` or `-Variant Forth2012` makes only one. The Forth 2012 profile is installed as a program of its own (`FORTH Sigma 2012`, without the `include` libraries), so both can be installed side by side.

On Linux and macOS, the following script makes the full release build (`dist/release/bin/sigma`) and the Forth 2012 profile (`dist/release-forth2012/bin/sigma`). The profile keeps standard word sets, including floating point and file access, and omits graphics, sound, and Sigma's extension vocabulary. `--variant full` or `--variant forth2012` builds only one of them; `--output` and `--forth2012-output` change the output directories. When `--target` is not given, Linux builds the machine's musl target (`x86_64-linux-musl` or `aarch64-linux-musl`); macOS builds for the machine with the baseline CPU (`-Dcpu=baseline`). `--help` lists all options.

    ./scripts/build-release.sh

For another target, give `--target`. Zig builds for other operating systems and CPUs too, so any of them can be made on any operating system. The targets GitHub Actions uses are `x86_64-linux-musl` for Linux x86_64, `aarch64-linux-musl` for Linux arm64, and `aarch64-macos` for macOS arm64. A Linux executable uses no shared libraries, so it runs on any distribution.

    ./scripts/build-release.sh --target aarch64-linux-musl

Linux has no installer: copy the executable to a directory on the `PATH`. On macOS the executable can be copied the same way.

    sudo install -m 755 dist/release/bin/sigma /usr/local/bin/sigma

GitHub Actions (`.github/workflows/release.yml`) can be started by hand (Actions > Release > Run workflow), and also runs when a `vVERSION` tag is pushed (for example, `v0.13.0`). It tests both profiles and builds ZIPs for Windows x86_64, Linux x86_64 and arm64, and macOS arm64; each ZIP remains a run artifact. Every ZIP contains the executable, LICENSE, THIRD_PARTY_NOTICES.md, and README.md. The full ZIP also contains the Sigma-specific libraries in `include` and examples in `examples`; the Forth 2012 profile ZIP omits both. After all jobs succeed for a matching version tag, the workflow publishes the Linux x86_64 ZIPs (`sigma-<version>-linux-x86_64.zip` and `sigma-<version>-linux-x86_64-forth2012.zip`) and their SHA256 files as a GitHub Release. The other platform ZIPs remain run artifacts. Each target has the full version (`sigma-<version>-<target>.zip`) and the Forth 2012 profile (`sigma-<version>-<target>-forth2012.zip`). The tests run on Windows x86_64, Linux x86_64 and arm64, and macOS arm64. Windows ZIPs with the same names (`dist\zip\sigma-<version>-windows-x86_64.zip` and `dist\zip\sigma-<version>-windows-x86_64-forth2012.zip`) are made with the following script. `-Variant Full` or `-Variant Forth2012` selects one profile.

    .\scripts\build-zip.ps1

For Linux and macOS, the following script makes the same two ZIP profiles as GitHub Actions (`dist/zip/sigma-<version>-<target>.zip` and `dist/zip/sigma-<version>-<target>-forth2012.zip`). The full ZIP contains `include` and `examples`; the Forth 2012 profile ZIP contains neither. The target is the machine unless `--platform` names `linux-x86_64`, `linux-arm64`, `macos-arm64`, or all (`all`). `--variant full` or `--variant forth2012` makes one profile; `--output` changes the output directory. It needs the `zip` command.

    ./scripts/build-zip.sh
    ./scripts/build-zip.sh --platform all

Before the interactive prompt, the program shows two lines with the version and the license (`FORTH/Sigma 0.13.0  MIT License` and `` Type `help' for basic help ``). `HELP` shows basic usage, `HELP` followed by a word name, such as `HELP DUP`, shows the description of that word, and `LICENSE` shows the full text of the license.

Example:

    : SQUARE DUP * ;
    12 SQUARE .

As in gforth, each command-line argument names a Forth source file to include, in order, and `-e text` interprets `text`. After the last argument the interactive prompt follows, unless `BYE` ended the program; an error in an argument ends it with exit status 1. Examples, with the two lines above saved as `square.fs`:

    sigma.exe square.fs
    sigma.exe -e "12 DUP * . BYE"

Forth source files can also be read from standard input. Example:

    sigma.exe < square.fs

The Boing demos show a rotating, bouncing checkered ball: [the original](examples/boing.fs) renders 320×200, [HD](examples/boing-hd.fs) renders 960×600, and [HFR](examples/boing-hfr.fs) renders 1920×1200 with a 120 fps target. Graphics and floating-point support are required; audio is optional. Space pauses/resumes and Q or Esc quits. For HFR, use a fast build:

```sh
zig build -Doptimize=fast
zig-out/bin/sigma examples/boing-hfr.fs
```

HFR opens a 1280×800 window that can be resized. The target is not a guarantee of monitor FPS; see the [graphics and sound manual](docs/GRAPHICS_AND_SOUND.md) for the variants and performance limits.

`examples/calculator.fs` is a calculator whose window and buttons are Tk's and whose arithmetic is Forth's. It needs Tcl/Tk: Sigma uses `SIGMA_WISH`, else `wish` on the `PATH`; on Windows, else the `wish` of Git for Windows; and on macOS it passes over the system's `/usr/bin/wish` and, without another `wish` on the `PATH`, uses Homebrew's or MacPorts's.

    sigma.exe < examples/calculator.fs

In this port, `SAVE filename` and `LOAD-DICTIONARY filename` save user-defined words as a dictionary image and load them additionally. For words with the same name, the newer definition takes precedence; when `FORGET` removes the newer one, the older definition comes back. `LOAD` and `SAVE` in the book are edit-buffer operations, and that function is not implemented. A standalone executable that contains the registered words is made with `SAVESYS`.

    SAVE words.sigma
    SAVESYS demo.exe

The saved executable starts with the registered words and takes the same arguments as `sigma.exe`: with no arguments it opens the interactive prompt, and `demo.exe -e "12 SQUARE . BYE"` runs the expression and exits. The sample shows `144`, the square of `12`.

### Leaving out word groups

Build options leave out groups of words, for a smaller program or for a host that does not need them. Without them, every group is in.

| Option | Leaves out | Size | Smaller than (none) by |
|---|---|---|---|
| (none) | — | 2,465,792 bytes | — |
| `-Dfloat=false` | The floating-point words, floating-point literals (such as `1e`), the `F:` and `F^` local variables, `FLOATING-STACK` and `MAX-FLOAT` of `ENVIRONMENT?`, CORE-MATH, and the graphics words that draw graphs (`PLOT` and others) | 2,010,624 bytes | 455,168 bytes |
| `-Dfiles=false` | The words that open, read, write, or include files, such as `INCLUDE`, `REQUIRE`, `OPEN-FILE`, `STDIN`, `SLURP-FILE`, and the `$...SLURP` words | 2,381,824 bytes | 83,968 bytes |
| `-Dhelp=false` | `HELP`, `LICENSE`, and their texts (the banner no longer mentions `help`) | 2,174,464 bytes | 291,328 bytes |
| `-Dtools=false` | `SEE`, `LOCATE`, and `WHERE` | 2,416,640 bytes | 49,152 bytes |
| `-Dimage=false` | `SAVE`, `LOAD-DICTIONARY`, and `SAVESYS` | 2,461,696 bytes | 4,096 bytes |
| `-Dgraphics=false` | `REQUIRE-GRAPHICS`, the `GFX-` words, the graphics library, its fonts, and the Tcl/Tk words | 2,063,360 bytes | 402,432 bytes |
| `-Daudio=false` | `REQUIRE-AUDIO`, the `SND-` words, the audio library, and the audio thread | 2,323,968 bytes | 141,824 bytes |
| `-Dextension=false` | `REQUIRE-EXTENSION` and the EXTENSION vocabulary, including `HOST-OS` | 2,290,688 bytes | 175,104 bytes |
| `-Ddebug=false` | The debugging features: the backtrace after an error, `--max-steps`, `--trace`, `--profile`, `--debug-log`, `--lint`, `--format`, `--coverage`, and the words `WATCH`, `UNWATCH`, `.COVER-RAW`, `COV%`, `.COVERAGE`, `DBG`, `BREAK:`, `BREAK"`, `~~BT`, `~~1BT`, `ONCE`, `~~VALUE`, `~~VARIABLE`, `+LTRACE`, and `-LTRACE` | 2,345,984 bytes | 119,808 bytes |
| The seven from `-Dfloat=false` to `-Daudio=false` together | All of them | 1,184,256 bytes | 1,281,536 bytes |
| Those seven and `-Ddebug=false` | All of them and the debugging features | 1,098,240 bytes | 1,367,552 bytes |
| All nine options | Every group | 969,216 bytes | 1,496,576 bytes |
| FORTH 2012 profile: `-Dgraphics=false -Daudio=false -Dextension=false` | Graphics, sound, and EXTENSION (the second ZIP of a release) | 1,722,368 bytes | 743,424 bytes |

The sizes are those of version 0.13.0 (commit `f8fd8f0`) built with `-Doptimize=fast -Dcpu=baseline -Dstrip=true`, the same as the release, for Windows x86_64 (measured 2026-11-28). The full build of 0.12.0 was 1,837,568 bytes under the same conditions. On Linux (x86_64 musl) the full build is 2,701,928 bytes, and `-Dx11=false`, which leaves out the X11 window, makes it 2,486,984 bytes; its FORTH 2012 profile is 1,727,432 bytes. The options can be combined, for example `zig build -Doptimize=fast -Dfloat=false -Dhelp=false`. The sizes of other combinations and the speed of eight small kernels, compared with 0.12.0 and gforth, are in the [size and speed measurement](docs/SIZE_SPEED_MEASUREMENT.md).


The EXTENSION vocabulary is in by default. `REQUIRE-EXTENSION ALSO EXTENSION HOST-OS TYPE PREVIOUS` shows the OS family Sigma runs on (`windows`, `linux` including WSL and Android, `macos`, or `unknown`). The vocabulary also has terminal modes and size (`TERM-MODE!`, `TERM-MODE@`, `COLS`, `ROWS`), waiting for key, mouse, and paste events (`EKEY-WAIT`, `EKEY-MOUSE`), computation tasks, and file and path utilities. The [extension manual](docs/EXTENSION.md) describes every word, and the [task API guide](docs/README.md#computation-tasks) has examples of tasks. With `-Dextension=false`, `REQUIRE-EXTENSION` is an unknown word (-13); the clocks and waits that audio and graphics use inside stay in.

The words of a group left out are not in the dictionary, and `HELP` has no entries for them. The groups are independent: without the file words, `SAVE`, `LOAD-DICTIONARY`, and `SAVESYS` still write and read image files, and `LOCATE` still reads the source file, unless their own groups are left out too. Builtin execution tokens stay stable across feature configurations, but images containing appended builtins or direct builtin operations excluded by the receiving build are rejected with `INVALID IMAGE` before installation. The runtime `INVALID EXECUTION TOKEN` defense remains for raw execution-token values kept as data. Images from older builtin tables are also rejected by the ABI check.

Image feature checks cover appended builtin words and direct builtin operations. Ordinary calls to reserved base dictionary slots retain the earlier behavior: loading succeeds and executing an excluded base word raises INVALID EXECUTION TOKEN. This is separate from data holding a raw xt value.

The tests run with the same options, for example `zig build test -Dfloat=false`; the tests that use a group left out are skipped.

`zig build freestanding` compiles the core (`src/forth.zig` and `src/core/`) for a Cortex-M0+ with no operating system, from what a host calls: start-up, interpreting a line, and the image functions. It fails when that code reaches a service of the operating system through Zig's standard library, so that the core stays usable with a host of its own, such as a microcontroller. The result is not linked, so a function the core declared `extern` itself would not be found. `zig build test` includes it.

## Relation to gforth and standard Forth

Since 2026-10-28, the numeric behavior and the basic words follow the behavior of [gforth](https://github.com/forthy42/gforth), with the goal of running the samples of the ForthBasicMaster course material. The work was divided into 6 stages. Stage 1 (64-bit cells, true = -1, floored division, name matching on all characters, `TYPE ( addr u )`, basic standard words), stage 2 (floating point), stage 3 (strings such as `S"`, double-cell integers, number formatting with `<# #>`), the small words used in the course material (`WITHIN`, `:NONAME`, `STATE`, `MS`, `GETENV`, `SYSTEM`, and others), `THROW` and `CATCH` and the main file operations (`OPEN-FILE`, `READ-LINE`, `WRITE-LINE`, and others), `ALLOCATE` and dynamic strings (`$!`, `$[]!`, and others), local variables (`{ a b -- c }`, type prefixes such as `F:`, `LOCALS|`), loading source files (`INCLUDE`, `REQUIRE`, and others), `SEE`, `LOCATE`, and `MARKER`, and word lists (`VOCABULARY`, `ONLY`, `ALSO`, and others) and `[IF]` are implemented, and all 6 stages are done ([decisions and open issues](https://github.com/fukuyori/ForthSigma/blob/main/docs/DECISIONS.md)).

This implementation is **not a system that guarantees conformance to ANS Forth or Forth 2012**; what was checked is in [Forth 2012 conformance status](#forth-2012-conformance-status) below. Words specific to FORTH/Σ whose meaning does not conflict with gforth are retained.

| Item | FORTH/Σ sources | Current port |
| --- | --- | --- |
| Cell width | 16 bits | 64 bits (the same as gforth on 64-bit systems) |
| Truth values | 0 is false, 1 is true | 0 is false, -1 is true |
| Name identity | Length and first 5 characters | The whole name (case-insensitive) |
| TYPE | ( u addr -- ) | ( addr u -- ) |
| Strings | "..." pushes the address after the length | "..." pushes the length after the address. ." is also provided as an extension. S", S\", and .\" are also available |
| Number output | . prints no space; 4 hexadecimal digits, 6 octal digits | . prints a trailing space, no zero padding, signed in every base |
| Division | Not settled by the sources | Floored division. Division by zero is an error |
| LEAVE | Ends at the next LOOP | Leaves the loop at once |
| DO | Runs once even when the start and limit are equal | As in Forth 2012 and gforth: the index wraps through every cell value. Use `?DO` to skip an empty range |
| Floating point | None | Separate stack, double precision, literals containing `E` |

For the definitions on the standard side, see the [Forth 2012 Standard](https://forth-standard.org/standard/index). Individual behavior and porting decisions are recorded in the specification, the implementation notes, and the decisions.

### Forth 2012 conformance status

Checked on 2026-11-17 against the glossary of the Forth 2012 standard document (450 entries in 25 word sets, 435 different names). The full build provides 446 of the 450 entries.

| Word set | Available / entries | Not available |
| --- | ---: | --- |
| CORE | 133 / 133 |  |
| CORE EXT | 49 / 49 |  |
| BLOCK | 8 / 8 |  |
| BLOCK EXT | 6 / 6 |  |
| DOUBLE | 20 / 20 |  |
| DOUBLE EXT | 3 / 3 |  |
| EXCEPTION | 2 / 2 |  |
| EXCEPTION EXT | 2 / 2 |  |
| FACILITY | 3 / 3 |  |
| FACILITY EXT | 37 / 37 |  |
| FILE | 21 / 21 |  |
| FILE EXT | 8 / 8 |  |
| FLOATING | 31 / 31 |  |
| FLOATING EXT | 48 / 48 |  |
| LOCAL | 1 / 1 |  |
| LOCAL EXT | 2 / 2 |  |
| MEMORY | 3 / 3 |  |
| TOOLS | 5 / 5 |  |
| TOOLS EXT | 18 / 22 | `;CODE`, `ASSEMBLER`, `CODE`, `EDITOR` |
| SEARCH | 9 / 9 |  |
| SEARCH EXT | 5 / 5 |  |
| STRING | 8 / 8 |  |
| STRING EXT | 3 / 3 |  |
| XCHAR | 10 / 10 |  |
| XCHAR EXT | 11 / 11 |  |

The four missing words belong to the Programming-Tools extension and need an assembler or an editor. The status of each word is in [the word list](docs/forth2012-word-status.tsv).

What this count means and does not mean:

- It counts names. Most entries were found with `[DEFINED]`. The words that the text interpreter handles as syntax (`\`, `."`, `S"`, `S\"`, `C"`, `.(`, `ABORT"`, `[CHAR]`, `[']`, `[`, `]`, `POSTPONE`, `:NONAME`, `{:`, `LOCALS|`, `FORGET`) were checked by running them.
- It is not a conformance test. The behavior of every word has not been compared with the standard text. Sigma does not claim to be a Standard System.
- A build that leaves out word groups (`-Dfloat=false` and the others) provides fewer words.

Results of the standard test suite ([Forth-Standard/forth-standard-test-suite](https://github.com/Forth-Standard/forth-standard-test-suite), version 0.13.4), run on 2026-11-17 with the full Windows build: `runtests.fth` (about 1,920 tests) runs to its end and reports 2 failures, both in the String word set.

| Part | Result |
| --- | --- |
| Core, Core extension, Block, Double number, Exception, Facility, File-access, Locals, Memory-allocation, Programming-tools, Search-order | No failure |
| String | 2 failures: the tests create the substitution `MAC3` and use it as `%mac3%`. Sigma matches substitution names with case, as gforth 1.0.2 does, and gforth reports the same two failures. The standard does not say how the case of these names is treated |
| Floating point (`fp/runfptests.fth`) | No failure: `fatan2-test`, `ieee-arith-test`, `ieee-fprox-test`, `fpzero-test`, `to-float-test` report 0 errors, `fpio-test` and `ak-fp-test` complete, and `paranoia` finds no failure, defect, or flaw |

The floating-point part needed one change to the test harness: `HAS-FLOATING` in `ttester.fs` was set by hand, because Sigma answers the `FLOATING` environment query, which Forth 2012 marks as obsolescent, as unknown. Tests whose output must be read by eye (displayed characters, number formats) were not judged. The suite itself says that its tests are not comprehensive, so passing it does not make Sigma a Standard System. The first run on the same day found ten differences, which were then removed; [both runs, with the logs](docs/measurements/2026-11-17-forth2012-test-suite.json).

Behavior that was compared with the standard text:

| Item | Standard | Sigma |
| --- | --- | --- |
| `DO` with an equal start and limit | No special case; `LOOP` ends only when the index equals the limit after adding one (6.1.1240, 6.1.1800) | The same since 2026-11-17. Earlier versions ran the body once |
| `?DO` with an equal start and limit | The body is skipped (6.2.0620) | The same |
| `+LOOP` | Ends when the index crosses the boundary between the limit minus one and the limit (6.1.0140) | The same, also for a negative step |
| `LEAVE`, `UNLOOP` | Leave at once; `UNLOOP` before `EXIT` (6.1.1760, 6.1.2380) | The same |
| Loop control parameters | A system may keep them on the return stack (3.2.3.3) | Kept on a separate loop stack. Standard programs see no difference |
| Structures | `BEGIN-STRUCTURE`, `+FIELD`, `FIELD:`, `CFIELD:`, `FFIELD:`, `SFFIELD:`, `DFFIELD:`, `END-STRUCTURE` | Available; the sizes and offsets of a test structure are the same as gforth |

### Differences from gforth

Sigma follows gforth where the two can agree, and the words are compared with gforth run under WSL. The known differences are these; the per-word records are in [the compatibility notes](docs/COMPATIBILITY.md).

| Item | gforth | Sigma |
| --- | --- | --- |
| Loop control parameters | On the return stack: inside a loop `R@` gives the loop index, and `I` after `>R` gives the value pushed | On a separate loop stack: `R@` gives the value the program pushed, and `I` stays the index. Both uses are outside the standard |
| Leaving a loop with `2RDROP EXIT` | Works | Throws -6 when the program has no cells of its own on the return stack. Use `UNLOOP EXIT`, which works in both |
| `CODE`, `END-CODE`, `;CODE`, `ASSEMBLER` | Available | Not available (no assembler) |
| `SAVESYSTEM`, `'COLD`, `BOOTMESSAGE`, `SCRIPT?` | Available | Not available. `SAVESYS` saves an image |
| Memory | Host addresses | One logical memory (64 MiB by default) with its own addresses; `-m`, `-d`, `-r`, `-f`, `-l` set the sizes |
| `FPATH` when empty or unset | An empty search path | Files are looked up from the current directory as before |
| `IS` | Deferred words | Also accepted on `FVALUE`, `2VALUE`, and `$VALUE`; unsupported targets throw -259 |
| Pipes | `BROKEN-PIPE-ERROR` is -2049 | One-way only (`R/O` or `W/O`); `BROKEN-PIPE-ERROR` is -544 |
| Floating-point functions | Its own results | CORE-MATH, correctly rounded; some results differ from gforth by 1 ulp |
| `SEE` | gforth's decompiler output | Its own format, for example `offset +FIELD name` for a field |
| Words of FORTH/Σ | None | Kept where they do not conflict, for example `"..."` strings and `BEGIN ... END` |

The loop rows were run on gforth 1.0.2 on 2026-11-17. The other rows come from the comparisons recorded in the compatibility notes, most of them made with gforth 0.7.9_20260410.

## Sources and references

### Primary sources of FORTH/Σ

This project refers to "FORTH/Σ" by 一ノ瀬敏彰 and 山口晶嗣 in the series of articles in *Encyclopedia ASCII* Vol. 11 (ASCII, April 1982) to Vol. 13 (September of the same year). The table below gives the volume, issue, and pages of each installment.

| Source | Pages | Main parts referred to |
| --- | --- | --- |
| 一ノ瀬敏彰 and 山口晶嗣, "FORTH/Σ", *Encyclopedia ASCII* Vol. 11, ASCII, April 1982 | pp. 108–117 | Overview, dictionary, interpreter, control structures, user's manual, word table. |
| Same authors, "FORTH/Σ", *Encyclopedia ASCII* Vol. 12, ASCII, May 1982 | pp. 166–173 | Description of the PC-8001 version, memory layout, editor, machine-specific words. |
| Same authors, "FORTH/Σ", *Encyclopedia ASCII* Vol. 12, ASCII, June 1982 | pp. 92–99 | Z80 source for dictionary search, number conversion, creating definitions, compilation, and control structures. |
| Same authors, "FORTH/Σ", *Encyclopedia ASCII* Vol. 12, ASCII, July 1982 | pp. 178–185 | Definitions, control structures, memory, stack, word list. |
| Same authors, "FORTH/Σ", *Encyclopedia ASCII* Vol. 12, ASCII, August 1982 | pp. 144–151 | Source listings for number output, arithmetic, and others. |
| Same authors, "FORTH/Σ", *Encyclopedia ASCII* Vol. 13, ASCII, September 1982 | pp. 172–179 | Editing and file processing in the CP/M version. |

The page information above is recorded in the [FORTH/Σ specification](https://github.com/fukuyori/ForthSigma/blob/main/docs/SPEC.md). The Z80 source in the book was referred to in order to study what it does; the port does not contain or execute Z80 machine code or the source code from the book.

### Sources used for comparison and checking

- The source code and the [manual](https://gforth.org/manual/) of [gforth](https://github.com/forthy42/gforth) are referred to as comparison material when considering implementation behavior that the sources do not settle, such as name matching. They are not a basis for the FORTH/Σ specification.
- The ForthBasicMaster course material is referred to as reference material for checking Forth terms and usage examples. It is not a basis for the FORTH/Σ specification.
- Differences from Forth 2012 are compared with the corresponding definitions in the [Forth 2012 Standard](https://forth-standard.org/standard/index).

### Scope of the sources and the license

The MIT License covers the program code and documentation made in this project. Magazine articles and other third-party material are not covered by the MIT License. Third-party material is not included in the repository. Citing a source does not mean permission to copy or redistribute third-party material.

## License

The code and documentation made in the project are provided under the [MIT License](https://github.com/fukuyori/ForthSigma/blob/main/LICENSE). The floating-point math functions (`FSIN` `FEXP` `FASIN` `F**` and others) use the code of CORE-MATH (MIT License, `src/core-math/`) and, on CPUs without an FMA instruction, musl's `fma` (MIT License, `src/fma/`). On Linux, `SYSTEM-FONT` reads font files with stb_truetype (MIT License, `src/stb/`). The copyright notices are in [THIRD_PARTY_NOTICES.md](https://github.com/fukuyori/ForthSigma/blob/main/THIRD_PARTY_NOTICES.md). For the handling of third-party material, see "Scope of the sources and the license" above.
