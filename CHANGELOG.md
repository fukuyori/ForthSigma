# Changelog

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
- Added `examples/music.fs`, which plays a tune on each chip and a sound effect, and a Sound chapter to the user manual.

### Changed

- Updated the product version and startup examples to 0.7.0.
- A dictionary that has loaded the audio words is saved as `SIGIMG35`, which versions up to 0.6.1 cannot load.
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
