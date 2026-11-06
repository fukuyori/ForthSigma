# FORTH/Σ for Zig

Japanese version: [README.ja.md](README.ja.md). This English version is the primary one.

This project implements the language core of FORTH/Σ (FORTH/Sigma) as a native port that runs on Zig. It uses the description of FORTH/Σ and the Z80 source listing published in the monthly magazine ASCII in 1982 as material for studying the specification. It does not execute or emulate Z80 instructions or machine code.

## Current implementation

- It uses 64-bit cells and 2 MiB of logical memory (the upper half holds the `ALLOCATE` heap and the local-variable area). The true value is -1, and division is floored.
- Floating-point numbers (double precision) are handled on a separate stack. A number that contains `E`, such as `1E` or `1.5e0`, is a floating-point number, and the F words such as `F+`, `F.`, `FSQRT`, and `FCONSTANT` are available.
- It supports interactive input, dictionary search, number input, and word definition and compilation.
- Stack operations, arithmetic, comparison, and logical operations, memory operations, and variables, constants, values, and arrays are available.
- IF ... ELSE ... THEN, BEGIN ... END/UNTIL, BEGIN ... AGAIN, BEGIN ... WHILE ... REPEAT, CASE ... ENDCASE, DO ... LOOP, DO ... +LOOP, LEAVE, and EXIT are available.
- The compiler can be extended with IMMEDIATE, POSTPONE, RECURSE, and CREATE ... DOES>.
- It supports base changes with HEX, DEC, and OCT, and output of numbers, characters, and strings.
- Strings such as `S"`, double-cell integers (128-bit) in the `123.` form, number formatting with `<<# # #S #> #>>`, `ACCEPT`, `EVALUATE`, and `KEY` are available.
- WORDS, FORGET, and BYE are provided as interactive words.
- Graphics, an extension of this port (`REQUIRE-GRAPHICS`): an image in memory with lines, shapes, painting, graphs, and text (a built-in ASCII font, BDF fonts, and on Windows the system's fonts), shown on the terminal (half blocks or Sixel), in a window on Windows, or in a Tk window; keys and the mouse (`INKEY`, `MOUSE`); and Tcl/Tk scripts run in a `wish` that Sigma starts (`TCL`, `TCL-EVAL`, `TCL-EVENT`). Tcl/Tk is not linked into Sigma and must be installed to use the TCL words.
- The dictionary, compiled definitions, memory, and input and output are separated from the host environment, so the program is easy to port to other operating systems and CPUs.

For the supported words and the porting decisions, see the [implementation notes](docs/IMPLEMENTATION.md). For the language specification compiled from the sources, see the [FORTH/Σ specification](docs/SPEC.md). The implementation is under development and does not support every word in the book or machine-specific features.

For usage and the list of the built-in words registered now, see the [user manual](docs/USER_MANUAL.md).

The defining words (BUILDS/DOES) that let users make words that hold data are also supported.

`SAVE filename` and `LOAD filename` save user-defined words and load them additionally. A standalone executable is made with a separate extension word, `SAVESYS filename.exe`.

For the support status of each word, see the [compatibility list](docs/COMPATIBILITY.md). For the distinction between the specification settled by the sources and the porting decisions, see [decisions and open issues](docs/DECISIONS.md).

At present, LIST, source file and editor operations, the CP/M file functions, the PC-8001 monitor functions, and words that use Z80 machine code are not supported.

## Building and running

In an environment with Zig 0.17.0 installed, run these commands from the root of the repository.

    zig build
    ./zig-out/bin/sigma.exe

The core regression tests run with zig build test.

On Linux and macOS, run the generated zig-out/bin/sigma. To specify another Zig target, use zig build -Dtarget=<triple>.

The current product version is recorded in [`VERSION`](VERSION). The Windows release build and the Inno Setup installer are made with the following PowerShell scripts. The installer (`dist\installer\sigma-<version>-windows-x86_64-setup.exe`) uses the value in `VERSION`; if needed, `-Version MAJOR.MINOR.PATCH` overrides it.

    .\scripts\build-release.ps1
    .\scripts\build-installer.ps1

`build-release.ps1` builds both the version with the floating-point words (`dist\release`) and the version without them (`dist\release-nofloat`). `-Variant Float` or `-Variant NoFloat` builds only one of them, and `-OutputDirectory` and `-NoFloatOutputDirectory` change the output directories. Even when `-Target` is not given, the CPU is baseline (`-Dcpu=baseline`). The installer contains only the version with the floating-point words.

To sign, set `CODESIGN_CERT` to the subject of the certificate in the certificate store, and give `-Sign`. When signing, the scripts sign the executable, the installer, and the uninstaller, and verify the signatures of the executable and the installer. The signatures get an RFC 3161 timestamp, so they stay valid after the certificate expires. The timestamp server is `http://timestamp.digicert.com` by default (the server of DigiCert, the root of the certificate); the environment variable `CODESIGN_TIMESTAMP_URL` changes it. If no timestamp is added, the scripts stop with an error.

    .\scripts\build-release.ps1 -Sign
    .\scripts\build-installer.ps1 -Sign

When a tag with the same version as `VERSION`, such as `v0.6.0`, is pushed, GitHub Actions (`.github/workflows/release.yml`) tests and builds on Windows x86_64, Linux x86_64, arm32, and arm64, and macOS arm64, and adds each ZIP (the executable, LICENSE, THIRD_PARTY_NOTICES.md, README.md, and USER_MANUAL.md) to a draft release. Each target has two ZIPs: the version with the floating-point words (`sigma-<version>-<target>.zip`) and the version without them (`sigma-<version>-<target>-nofloat.zip`). The tests run on real machines for Windows x86_64, Linux x86_64 and arm64, and macOS arm64. The Windows build from CI is not signed, so before publishing, its ZIPs are replaced with signed ZIPs that have the same names and the same contents (`dist\zip\sigma-<version>-windows-x86_64.zip` and `dist\zip\sigma-<version>-windows-x86_64-nofloat.zip`), made with the following script. `-Variant Float` or `-Variant NoFloat` makes only one of them.

    .\scripts\build-zip.ps1 -Sign

When started with no arguments, the program shows two lines with the version and the license (`FORTH/Sigma 0.6.0  MIT License` and `` Type `help' for basic help ``) and then the interactive prompt. `HELP` shows basic usage, `HELP` followed by a word name, such as `HELP DUP`, shows the description of that word, and `LICENSE` shows the full text of the license.

Example:

    : SQUARE DUP * ;
    12 SQUARE .

Forth source files can be read from standard input. Example:

    sigma.exe < examples/demo.fs

`examples/calculator.fs` is a calculator whose window and buttons are Tk's and whose arithmetic is Forth's. It needs Tcl/Tk: Sigma uses `SIGMA_WISH`, else `wish` on the `PATH`, and on Windows, else the `wish` of Git for Windows.

    sigma.exe < examples/calculator.fs

In this port, `SAVE filename` and `LOAD filename` save user-defined words as a dictionary image and load them additionally. For words with the same name, the newer definition takes precedence; when `FORGET` removes the newer one, the older definition comes back. `LOAD` and `SAVE` in the book are edit-buffer operations, and that function is not implemented. A standalone executable that contains the registered words is made with `SAVESYS`.

    SAVE words.sigma
    SAVESYS demo.exe

With no arguments, the saved executable opens an interactive prompt that has the registered words. With arguments, it executes the arguments once as Forth input and exits. The sample shows `144`, the square of `12`.

### Leaving out word groups

Build options leave out groups of words, for a smaller program or for a host that does not need them. Without them, every group is in.

| Option | Leaves out | Size |
|---|---|---|
| (none) | — | 913,920 bytes |
| `-Dfloat=false` | The floating-point words, floating-point literals (such as `1e`), the `F:` and `F^` local variables, `FLOATING-STACK` and `MAX-FLOAT` of `ENVIRONMENT?`, CORE-MATH, and the graphics words that draw graphs (`PLOT` and others) | 524,288 bytes |
| `-Dfiles=false` | The words that open, read, write, or include files, such as `INCLUDE`, `REQUIRE`, `OPEN-FILE`, `STDIN`, `SLURP-FILE`, and the `$...SLURP` words | 877,568 bytes |
| `-Dhelp=false` | `HELP`, `LICENSE`, and their texts (the banner no longer mentions `help`) | 832,000 bytes |
| `-Dtools=false` | `SEE`, `LOCATE`, and `WHERE` | 856,064 bytes |
| `-Dimage=false` | `SAVE`, `LOAD`, and `SAVESYS` | 913,920 bytes |
| `-Dgraphics=false` | `REQUIRE-GRAPHICS`, the `GFX-` words, the graphics library, its fonts, and the Tcl/Tk words | 798,208 bytes |
| All six | All of the above | 289,792 bytes |

The sizes are those of 0.6.0 built with `-Doptimize=fast`, the same as the release, on Windows x86_64 (measured 2026-11-06). The options can be combined, for example `zig build -Doptimize=fast -Dfloat=false -Dhelp=false`.

The words of a group left out are not in the dictionary, and `HELP` has no entries for them. The groups are independent: without the file words, `SAVE`, `LOAD`, and `SAVESYS` still write and read image files, and `LOCATE` still reads the source file, unless their own groups are left out too. Every build gives each built-in word the same execution token, so an image saved by one build loads into a build with other groups; running a word that build left out gives the error `INVALID EXECUTION TOKEN`, and `SEE` shows it by its name. An image saved by an earlier build that left a group out (such as `-Dfloat=false`) gives `INVALID IMAGE`, since its built-in words had other execution tokens.

The tests run with the same options, for example `zig build test -Dfloat=false`; the tests that use a group left out are skipped.

`zig build freestanding` compiles the core (`src/forth.zig` and `src/core/`) for a Cortex-M0+ with no operating system, from what a host calls: start-up, interpreting a line, and the image functions. It fails when that code reaches a service of the operating system through Zig's standard library, so that the core stays usable with a host of its own, such as a microcontroller. The result is not linked, so a function the core declared `extern` itself would not be found. `zig build test` includes it.

## Relation to gforth and standard Forth

Since 2026-10-28, the numeric behavior and the basic words follow the behavior of [gforth](https://github.com/forthy42/gforth), with the goal of running the samples of the ForthBasicMaster course material. The work was divided into 6 stages. Stage 1 (64-bit cells, true = -1, floored division, name matching on all characters, `TYPE ( addr u )`, basic standard words), stage 2 (floating point), stage 3 (strings such as `S"`, double-cell integers, number formatting with `<# #>`), the small words used in the course material (`WITHIN`, `:NONAME`, `STATE`, `MS`, `GETENV`, `SYSTEM`, and others), `THROW` and `CATCH` and the main file operations (`OPEN-FILE`, `READ-LINE`, `WRITE-LINE`, and others), `ALLOCATE` and dynamic strings (`$!`, `$[]!`, and others), local variables (`{ a b -- c }`, type prefixes such as `F:`, `LOCALS|`), loading source files (`INCLUDE`, `REQUIRE`, and others), `SEE`, `LOCATE`, and `MARKER`, and word lists (`VOCABULARY`, `ONLY`, `ALSO`, and others) and `[IF]` are implemented, and all 6 stages are done ([decisions and open issues](docs/DECISIONS.md)).

This implementation is **not a system that guarantees conformance to ANS Forth or Forth 2012**. Words specific to FORTH/Σ whose meaning does not conflict with gforth are retained.

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
| DO | Runs once even when the start and limit are equal | As in the sources (differs from gforth) |
| Floating point | None | Separate stack, double precision, literals containing `E` |

For the definitions on the standard side, see the [Forth 2012 Standard](https://forth-standard.org/standard/index). Individual behavior and porting decisions are recorded in the specification, the implementation notes, and the decisions.

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

The page information above is recorded in the [FORTH/Σ specification](docs/SPEC.md). The Z80 source in the book was referred to in order to study what it does; the port does not contain or execute Z80 machine code or the source code from the book.

### Sources used for comparison and checking

- The source code and the [manual](https://gforth.org/manual/) of [gforth](https://github.com/forthy42/gforth) are referred to as comparison material when considering implementation behavior that the sources do not settle, such as name matching. They are not a basis for the FORTH/Σ specification.
- The ForthBasicMaster course material is referred to as reference material for checking Forth terms and usage examples. It is not a basis for the FORTH/Σ specification.
- Differences from Forth 2012 are compared with the corresponding definitions in the [Forth 2012 Standard](https://forth-standard.org/standard/index).

### Scope of the sources and the license

The MIT License covers the program code and documentation made in this project. Magazine articles and other third-party material are not covered by the MIT License. Third-party material is not included in the repository. Citing a source does not mean permission to copy or redistribute third-party material.

## License

The code and documentation made in the project are provided under the [MIT License](LICENSE). The floating-point math functions (`FSIN` `FEXP` `FASIN` `F**` and others) use the code of CORE-MATH (MIT License, `src/core-math/`) and, on CPUs without an FMA instruction, musl's `fma` (MIT License, `src/fma/`). The copyright notices are in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). For the handling of third-party material, see "Scope of the sources and the license" above.
