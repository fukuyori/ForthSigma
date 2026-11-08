# Changelog

## [Unreleased]

### Added

- Sound on macOS: the audio words now play through an AudioQueue of AudioToolbox on the default output device (48 kHz 16-bit stereo, about 80 ms ahead), the framework loaded when the program runs, so that the macOS builds made on Linux need no SDK. Before, the music went on without sound there.
- `scripts/sign-and-notarize-macos.sh` builds a universal (arm64 and x86_64) macOS installer package that puts `sigma` in `/usr/local/bin`, signs it with Developer ID certificates, has Apple notarize it, and staples the ticket.

### Changed

- On Linux and macOS, `SHOW` with no display chosen now uses the Tk window when Sigma runs on a desktop (`DISPLAY`, `WAYLAND_DISPLAY`, or macOS's `__CFBundleIdentifier` is set) and `wish` starts; otherwise it uses the terminal as before. The games in `examples` now open a window there without `DISPLAY-TK`.

### Fixed

- On macOS, the TCL words, `DISPLAY-TK`, and `examples/calculator.fs` failed with `HOST FUNCTION ERROR`, because the system's `/usr/bin/wish` (Tcl/Tk 8.5) is killed as it starts on recent macOS. Sigma now passes over it and uses another `wish` on the `PATH`, else Homebrew's or MacPorts's; install Tcl/Tk with `brew install tcl-tk`.
- `examples/calculator.fs` showed nothing in its display in the dark mode of macOS: the display had a white background but the system's text color, which is white there. Its text is now black. On macOS its window could also open partly undrawn (black), since it was shown before its widgets were in place; it is now shown once they all are.
- An animation on the terminal could show half-drawn frames, which looked like noise (in Ghostty, for one): each picture of `SHOW` on a terminal is now sent as one frame of synchronized output (DEC mode 2026), which terminals that do not know it ignore.
- The Linux release builds were silent with PipeWire 1.x, whose `pw-play` reads its input as a sound file unless `--raw` is given; Sigma now passes `--raw`, and falls back to the old form for older PipeWire. `pw-play` also gets `--latency=40ms`, as `pacat` does, so that sounds no longer come about 0.2 s late, and `aplay` gets a 40 ms buffer (`-B 40000`) instead of about 0.5 s.

## [0.7.0] - 2026-11-07

### Added

- Added sound, an extension of this port: `REQUIRE-AUDIO` loads the `AUDIO` vocabulary, the `SND-` words, and an audio library written in Forth. The sound is made by an audio thread, so the program goes on while the music plays.
- Added MSX BASIC's `PLAY`, `PLAY2`, `PLAY3`, `PLAY?`, `SOUND`, and `BEEP` with its music macro language (the MSX1 ROM's, as the MSX Red Book describes it), on an AY-3-8910 by its registers. An invalid string throws the new error `INVALID MML` (-274).
- Added the sound chips of the Atari ST (YM2149), the NES, the C64 (SID, with ring modulation, sync, and its filter), Konami's SCC, and the Amiga (Paula), chosen with `MSX-SOUND`, `ST-SOUND`, `NES-SOUND`, `C64-SOUND`, `SCC-SOUND`, and `AMIGA-SOUND`, or several together with `CHIPS` (up to 8 voices); `PLAYS` plays up to 8 voices.
- Added instruments, which MML's `@n` chooses: `INSTRUMENT`, `SQUARE`, `PULSE`, `TRIANGLE`, `SAW`, `NOISE`, `DUTY`, `ADSR`, `RING`, `SYNC`, `FILTER`, and `SCC-WAVE`.
- Added recorded sound: `LOAD-SAMPLE` (WAV files of 8- or 16-bit PCM; the new error `SAMPLE ERROR`, -276), `SAMPLE`, `LOOP-SAMPLE`, `SAMPLE-INSTRUMENT`, `SFX` for sound effects beside the music, `FREE-SAMPLES`, and `AMIGA-FILTER`.
- Added ProTracker modules: `LOAD-MOD` (four channels; the new error `MOD ERROR`, -277), `PLAY-MOD`, `STOP-MOD`, and `MOD?`.
- Added the audio output: waveOut on Windows; on Linux, PulseAudio or ALSA in builds that can load libraries, and otherwise the commands `pacat`, `pw-play`, or `aplay` (the release builds). Without an audio device, and on macOS, the words work without sound; `AUDIO?` tells which.
- Added the build option `-Daudio=false`, which leaves the sound out; `REQUIRE-AUDIO` then throws the new error `AUDIO UNAVAILABLE` (-275).
- Added `examples/music.fs`, which plays a tune on each chip and a sound effect.
- Added the graphics and sound manual (`docs/GRAPHICS_AND_SOUND.md`, and `.ja.md` in Japanese): the Graphics chapter moved there from the user manual, and a new Sound chapter.
- Added `examples/hopper.fs` (Sky Hopper), a side-scrolling platform game with sound effects and a tune of its own for each course; `examples/paddle.fs` and `examples/runner.fs` got sound effects. The games play silently in a build without the audio words.

### Changed

- Updated the product version and startup examples to 0.7.0.
- A dictionary that has loaded the audio words is saved as `SIGIMG35`, which versions up to 0.6.1 cannot load.
- The release ZIPs hold the executable, LICENSE, THIRD_PARTY_NOTICES.md, and README.md; the README's links lead to the manuals and the other documents on GitHub.
- `S"` and `S\"` outside a definition keep each string in the heap, as gforth does, instead of four buffers used in turn: a fifth string no longer overwrites the first, and strings made interactively stay valid. The heap they take is not freed.

## [0.6.1] - 2026-11-06

### Added

- Added generic SDL3 gamepad input for graphics programs. The API reports connected devices, raw axes, buttons, hats, mapped controls, names, and GUIDs; SDL mapping strings can be applied at runtime.
- Added the `GAMEPAD-*` Forth words and `examples/gamepad.fs`, a device inspection example.
- Added `scripts/install-gamepad-runtime.ps1` to install the optional SDL3 runtime.

### Changed

- Updated the product version and startup examples to 0.6.1.
- Added an optional SDL3 host backend. Builds can still run when SDL3 is unavailable; gamepad polling then reports that the backend is unavailable.

[0.7.0]: https://github.com/fukuyori/ForthSigma/releases/tag/v0.7.0
[0.6.1]: https://github.com/fukuyori/ForthSigma/releases/tag/v0.6.1
