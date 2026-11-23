# FORTH/Σ for Zig

Japanese version: [README.ja.md](README.ja.md). This English version is the primary one.
- [638 イベントキューの詳細設計](EVENT_QUEUE_DESIGN.md): 期限付きEKEY、途中入力、マウス付随情報、貼付け、入力切替と復元。
- [637 端末制御の詳細設計](TERMINAL_CONTROL_DESIGN.md): 表示要求、入力境界、復元、Windows/Linux/Macの確認範囲。

For the project overview, how to build, the current features, the differences from standard Forth, and the sources and the license, see the [README of the repository](../README.md).

- [FORTH/Σ specification](SPEC.md): the specification compiled from the magazine sources, and where it comes from
- [User manual](USER_MANUAL.md): how to start, basic operation, the list of the words registered now
- [Complete word reference](WORD_REFERENCE.md): individual stack effects and descriptions for all current words, syntax, standard keys and library helpers; [reading guide and checked examples](WORD_REFERENCE_GUIDE.md)
- [Debugging guide](DEBUGGING.md): how to find what is wrong with a program, from the command line and for agents (backtrace, trace, single steps, watching memory, profile, coverage, lint, formatter, the log as JSON Lines)
- [Graphics and sound manual](GRAPHICS_AND_SOUND.md): the graphics words (drawing, text, Tcl/Tk, keys, the mouse, animation) and the sound words (MSX BASIC's PLAY, the standard sound and its instruments, the chip libraries, recorded sound, modules)
- [Graphics modes](GRAPHICS_MODES.md): where `SHOW` shows the image (terminal, Sixel, window, Tk window), the number of colors, and the size it is shown at
- [Sound research](SOUND_RESEARCH.md): the sound chips of the MSX, the Atari ST, the C64, the NES, and the Amiga, MSX BASIC's sound, and the audio output of each system, with the sources (in Japanese)
- [Native windows on Windows, macOS, and Linux: a study](NATIVE_WINDOW_STUDY.md): proposed shared criteria for `SHOW` and macOS/Linux backends, dependencies, and validation criteria (under consideration; in Japanese)
- [Linux physical hotplug recorder](LINUX_DISPLAY_HOTPLUG_VALIDATION.md): cable unplug/replug procedure, DRM/X11 evidence, recorder checks, and pending physical acceptance (tque 1336/1345; in Japanese).
- [LOGO turtle graphics: a study](LOGO_TURTLE_STUDY.md): interpreting LOGO programs and drawing turtle graphics in Forth on Sigma without changing Sigma itself; approach, items to decide, and problems (under consideration; in Japanese)
- [Implementation notes](IMPLEMENTATION.md): the structure of the Zig port, implementation decisions, features not implemented
- [Forth 2012 word status](forth2012-word-status.tsv): each glossary entry of the Forth 2012 standard and whether the full build provides it (checked 2026-11-17; summary in the top-level README)
- [Size and speed measurements](SIZE_SPEED_MEASUREMENT.md): 2026-11-20 Windows/Linux size configurations, before/after CPU timings and WSL comparisons with Gforth 1.0.2, including raw samples (in Japanese)
- [Extending the core: the whole plan](CORE_EXTENSION_PLAN.md): shared infrastructure and OS identification, TUI and async I/O, sound and drawing, game display, task control, dependencies, and stages 0–E (tque 613; common foundation and terminal controls accepted on Mac, event-queue Windows/Linux acceptance completed with native Mac acceptance pending). [Implementation and validation log](CORE_EXTENSION_IMPLEMENTATION.md) (in Japanese)
- [Unicode grapheme design](GRAPHEME_DESIGN.md) and [implementation evidence](GRAPHEME_IMPLEMENTATION.md): Unicode 18.0.0 boundaries, validation scope and complexity, tests and remaining Mac acceptance (in Japanese)
- [Filesystem design](FILESYSTEM_DESIGN.md) and [implementation evidence](FILESYSTEM_IMPLEMENTATION.md): path utilities, metadata, synchronization, review decisions and remaining Mac acceptance (in Japanese)
- [Core extension handoff (2026-11-19)](CORE_EXTENSION_HANDOFF_2026-11-19.md): current core extension state, Git/tque state and validation (in Japanese)
- [Word groups and OS identification](EXTENSION_GROUP_DESIGN.md): extension selection/loading, HOST-OS, excluded builds, and image contracts (1056/1036; in Japanese)
- [Saved application startup plan](SAVED_APPLICATION_STARTUP_PLAN.md): SAVESYS startup, application arguments, lifecycle, image integration and acceptance (1066 under 1003). LOGO remains an external Forth application (in Japanese)
- [Core extension detailed design](CORE_EXTENSION_DETAILED_DESIGN.md): allocation to the core and optional word groups, proposed APIs, internal structure, ownership, failure, cancellation, restore, and validation. [Design decisions](CORE_EXTENSION_DESIGN_DECISIONS.md), [State isolation audit](CORE_EXTENSION_WORKER_STATE_AUDIT.md) (in Japanese; proposals, not implemented)
- [Detailed design review response](CORE_EXTENSION_REVIEW_RESPONSE.md): responses to Claude Code's [initial review](CORE_EXTENSION_CLAUDE_REVIEW.md) and [follow-up](CORE_EXTENSION_CLAUDE_FOLLOWUP.md), with remaining adoption gates. [Review request](CORE_EXTENSION_REVIEW_REQUEST.md) (in Japanese)
- [Task control plan](TASK_CONTROL_PLAN.md): execution models, state and results, combined waits, cancellation, cleanup, VM isolation, and use without debug features (tque 1048; in Japanese; model undecided, not implemented)
- [1048 detailed task control plan](TASK_CONTROL_DETAILED_PLAN.md): current-source checks, model comparison and prototype gates, child-task deliverables, isolation, cancellation, combined waits, validation, measurements, and adoption decisions (proposal; in Japanese)
- [Extending the core: the common rules](ASYNC_COMMON_RULES.md): proposed stage 0 contracts and the scope of the minimal internal infrastructure: clocks, waits, deadlines and interrupts, queues, limited execution, resource ownership, dictionary images, and word groups; remaining details are to be checked during implementation (in Japanese; not implemented)
- [TUI and asynchronous execution: how to proceed](ASYNC_CORE_PLAN.md): the seven items of the extension module, what exists in Sigma and gforth, and the approach for each, with the decisions of 2026-11-17 (in Japanese; not implemented)
- [For emulators of old computers: how to proceed](EMULATOR_CORE_PLAN.md): the five items to add to the sound and graphics words, the approach for each, the review by Codex, and the decisions of 2026-11-18 (in Japanese; not implemented)
- [VM performance improvement plan](VM_PERFORMANCE_PLAN.md): proposed experiments to reduce interpreter overhead while preserving CATCH safety; not implemented (in Japanese)
- [VM performance design review](VM_PERFORMANCE_REVIEW.md): Claude Code and Antigravity reviews, corrections, decisions and bounded acceptance criteria (in Japanese)
- [Gforth VM implementation reference](GFORTH_VM_REFERENCE.md): fixed-version sources and applicable design principles; no engine or GPL code migration (in Japanese)
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

- [SIGIMG45/46/47 image format](IMAGE_FORMAT45.md)

- [Saved application startup: implementation, validation and Mac procedure (Japanese)](SAVED_APPLICATION_STARTUP_IMPLEMENTATION.md)

- [PCM stream design, source audit and internal component validation (Japanese)](PCM_STREAM_IMPLEMENTATION.md)

- [Audio host shutdown, rollback and lifecycle verification (Japanese)](PCM_HOST_LIFETIME_IMPLEMENTATION.md)

- [Public PCM implementation and validation](PCM_PUBLIC_IMPLEMENTATION.md): ownership, waits, image boundaries, Windows/Linux automation and pending Mac checks.

- [Forth synthesis prototype](PCM_SYNTH_PROTOTYPE.md): original four-voice workload, PCM streaming, Windows/Linux measurements and limits.

- [NES APU Forth prototype](NES_APU_FORTH.md): NTSC four-channel registers, scheduled writes, reference/batch equivalence and measured scope.

- [NES DMC Forth model](NES_DMC_FORTH.md): five-voice sample reader/DAC/IRQ behavior, own memory map and workload measurements.

- [C64 SID Forth model](SID_FORTH.md): declared three-voice digital model, integer filter proxy, independent verification and scope limits.

- [Paula Forth register model](PAULA_FORTH.md): declared stereo DMA/manual/IRQ/attachment model, independent validation and pending Mac acceptance.

- [YM2149/ST Forth model and audit](YM2149_FORTH.md): existing/native gaps, fixed-zero mute correction, timestamped registers/virtual ports/bus, independent PCM tests and measurements.

- [Eight-target audio coverage audit](AUDIO_TARGET_AUDIT.md): source-backed gaps, declared model boundaries and per-machine/OS follow-up tasks; final adoption remains separate.

- [SNES S-DSP audio model](SNES_DSP_AUDIO_FORTH.md): declared8voice/BRR/envelope/noise/PMON/echoFIR model, independent validation and limits (Japanese).
- [ZX Spectrum 48K/128K audio model](ZX_SPECTRUM_AUDIO_FORTH.md): Forth beeper/AY synthesis, independent port/PCM validation and declared limits.
- [Apple II/II+ speaker and Mockingboard audio model](APPLE2_AUDIO_FORTH.md): Forth speaker toggle and two AY-3-8910 through 6522 ports, independent bus/PCM validation and declared limits.
- [CHIP-8 and XO-CHIP Forth audio](CHIP8_AUDIO_FORTH.md): declared60Hz timer, portable buzzer, copied128-bit pattern and integer pitch/phase model; CPU and OS acceptance are separate.

- [S-DSP native frame kernel](SNES_DSP_NATIVE_DESIGN.md): Design and review decisions for synchronous borrowed buffers after measured Forth shortfall.
