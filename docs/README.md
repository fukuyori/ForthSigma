# FORTH/Σ for Zig

Japanese version: [README.ja.md](README.ja.md). This English version is the primary one.

For the project overview, how to build, the current features, the differences from standard Forth, and the sources and the license, see the [README of the repository](../README.md).

- [FORTH/Σ specification](SPEC.md): the specification compiled from the magazine sources, and where it comes from
- [User manual](USER_MANUAL.md): how to start, basic operation, the list of the words registered now
- [Debugging guide](DEBUGGING.md): how to find what is wrong with a program, from the command line and for agents (backtrace, trace, single steps, watching memory, profile, coverage, lint, formatter, the log as JSON Lines)
- [Graphics and sound manual](GRAPHICS_AND_SOUND.md): the graphics words (drawing, text, Tcl/Tk, keys, the mouse, animation) and the sound words (MSX BASIC's PLAY, sound chips, recorded sound, modules)
- [Graphics modes](GRAPHICS_MODES.md): where `SHOW` shows the image (terminal, Sixel, window, Tk window), the number of colors, and the size it is shown at
- [Sound research](SOUND_RESEARCH.md): the sound chips of the MSX, the Atari ST, the C64, the NES, and the Amiga, MSX BASIC's sound, and the audio output of each system, with the sources (in Japanese)
- [Implementation notes](IMPLEMENTATION.md): the structure of the Zig port, implementation decisions, features not implemented
- [Word compatibility list](COMPATIBILITY.md): the words published in the book and their current implementation status
- [Gforth word implementation phases](GFORTH_WORD_PHASES.md): implementation order, acceptance criteria, and tque tasks for 380 priority A–C words and dictionary registration of four existing syntax words, prioritizing Forth 2012 words (in Japanese)
- [P00 specification and reference cases](GFORTH_P00_SPEC.md): compatibility decisions, address relocation design, and reproducible Gforth comparisons (in Japanese)
- [Decisions and open issues](DECISIONS.md): the division between the specification of the original sources and the porting decisions (in Japanese)
- [Memory and graphics plan](MEMORY_AND_GRAPHICS_PLAN.md): the plan for setting the memory limits at start-up and at build time, and for the GUI, sprite, and image words modeled on the MSX, the NES, and the Amiga (in Japanese)
- [Development schedule](DEVELOPMENT_SCHEDULE.md): the record of the work (in Japanese)
- [Version update checklist](version-update-checklist.md): what to update when the version changes, and the release steps (in Japanese)

- [S01 review and validation](S01_REVIEW.md): Claude Code findings, fixes, and measured comparisons (Japanese).

- [P01 review and validation](P01_REVIEW.md): Claude Code findings, documentation fixes, and measured return-stack differences (Japanese).

- [Async tasks and event queue overview](ASYNC_OVERVIEW.md): proposal, three issues to resolve before implementation, and open design questions; details undecided (in Japanese).

- [P02 numeric extensions](P02_IMPLEMENTATION.md): integer, floating-point, conversion/output and random semantics, reference differences, and validation (Japanese).

- [P02 review and validation](P02_REVIEW.md): Claude Code findings, fixes, and targeted comparisons (Japanese).

- [P03 memory implementation](P03_IMPLEMENTATION.md): P03a widths, alignment, endian conversion, and validation; relocation and heap stages remain pending (Japanese).
