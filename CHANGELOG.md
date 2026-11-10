# Changelog

## [Unreleased]

### Added

- `STYLE ( chip -- )` makes an instrument sound like a chip (`MSX`, `ST`, `NES`, `C64`, `SCC`, `AMIGA`, or 0 for the voice's chip) on whichever voice plays it, so that one `PLAY` can use every chip with no chip chosen; `examples/music.fs` shows it.
- Added `examples/shmup-c64.fs` and `examples/shmup-amiga.fs`, Sigma Storm in the style of the Commodore 64 (320 by 200, its 16 colors, pictures drawn dot by dot, raster bars, music on the SID) and of the Amiga (640 by 512, colors of 4 bits a channel, pictures drawn with shaded polygons, a copper gradient, copper bars and a scroller, sampled music on Paula). The rules are those of `examples/shmup.fs`.
- Added `examples/klondike.fs`, the Klondike patience game played with the mouse: dragging cards and runs, draw 1 or 3, undo, hints, moving cards to the foundations automatically, and cards painted by the program itself.
- Added `examples/waterworks.fs`, a game of laying pipe ahead of the water on a blueprint: 8 stages with rocks, tanks, pumps, tunnels, and drains, played with the mouse or the keys.
- Added `examples/sweeper.fs` (Sonar Sweep), a game of finding mines on the sea bed from numbers: three sea areas, a safe first square, buoys, opening around a number, and best times, played with the mouse or the keys.
- Added `examples/pinball.fs` (Wyrm's Delve), a pinball table of a dungeon: monsters as bumpers with hit points and rolled damage, a d20 shrine, a RUNE bank and a chest, a spinner, an orbit with a one-way gate, a ramp, a kickback, a dragon that wakes when the monsters are slain, levels and floors, and a character sheet beside the table.

- The startup options of gforth choose the sizes of the memory and the stacks: `-m` (`--dictionary-size`), `-d` (`--data-stack-size`), `-r` (`--return-stack-size`), `-f` (`--fp-stack-size`), and `-l` (`--locals-stack-size`), with gforth's units (`e`, `b`, `k`, `M`, `G`, `T`). They come before the other arguments, and `--` ends them. The build options `-Dmemory-mib`, `-Dlocals-kib`, and `-Dstack-cells` change the defaults, and `-Dwords` and `-Dnames-kib` the size of the dictionary.

- Images besides the screen, as the pages of the MSX2 and the blitter of the Amiga: `NEW-IMAGE`, `FREE-IMAGE`, `IMAGE-SIZE`, `SCREEN`, `DRAW-TO` and `DRAWING` (the drawing words, `GFX-WIDTH`, `GFX-HEIGHT`, and the `SAVE-` words use the image drawn on; `SHOW` shows the screen), `COPY-RECT` and `PUT-IMAGE` with `TRANSPARENT` and `IMAGE-FLIP`. At most 256 images and 1 GiB in all; a handle that names no image gives the new error `INVALID IMAGE HANDLE` (-278).
- `LOAD-IMAGE ( c-addr u -- img )` reads a PNG (every color type and bit depth, also interlaced), BMP (1 to 32 bits, not RLE), or PPM/PGM (binary and plain) file into a new image; pixels more than half transparent get the `TRANSPARENT` color. A file it cannot read gives the new error `IMAGE FORMAT ERROR` (-279). PNG data is inflated with the decompressor of Zig's standard library; no C library was added.
- `REQUIRE-GAME` loads small Forth words for games into the `GAME` vocabulary: sprites (`SPRITE:`, `INIT-SPRITE`, `PUT-SPRITE`, `SPRITE-ANIM`, `ANIMATE`, `DRAW-SPRITE`) with their tests of overlap (`HIT?`, `PIXEL-HIT?`), and tile maps of bytes (`TILEMAP:`, `TILE@`, `TILE!`, `>TILE`, `DRAW-TILEMAP`), which draw only the part a view shows and can be drawn over one another. Sprites and maps are structures in the dictionary that the program makes; its own loop moves, draws, and tests them. Two GFX- words come under them: `GFX-PIXEL` and `GFX-TILEMAP`.
- What the GUI keeps from frame to frame is in variables the program may read and set: `GUI-FOCUSED`, `GUI-ACTIVE`, `GUI-MENU-OPEN`, and `GUI-MENU-ITEM`. `GUI-LIST-XT` and `GUI-CHOOSE-XT` take their items from a word ( i -- c-addr u ), so the items can be in any data of the program and may hold `|`.
- `examples/pinball.fs`, `examples/sweeper.fs`, and `examples/waterworks.fs` keep each sprite in an image (`NEW-IMAGE`) and draw it with `GFX-COPY`, instead of as lists of horizontal lines; every sprite draws the same pixels as before, faster. `README` and the user manual name the GUI and game words and the image files.
- `examples/shmup.fs`, `examples/shmup-c64.fs`, and `examples/shmup-amiga.fs` are drawn with the game words: their pictures are sprites on a sheet, drawn as before pixel for pixel; a shot hits an enemy where their pixels meet (`PIXEL-HIT?`); the backgrounds are pictures of color numbers (the Amiga's copper as a palette for each band of lines), whose water colors turn on the ocean; clouds are half seen, explosions, lasers, and shots glow, and a bomb or a boss blowing up ripples the rows. Drawing takes less time. The bosses are weaker: about a quarter less hit points (750, 950, and 1100), and they, their cannons, and their orbiters fire about half as often, with about half the shots in each fan and burst.
- The game words also have palettes of 256 colors (`PALETTE:`, `PALETTE!`, `PALETTE@`, `ROTATE-PALETTE`) for pictures of color numbers (`INDEXED:`, `INDEX@`, `INDEX!`, `DRAW-INDEXED`), effects on each row of a rectangle after it is drawn (`RASTER-SCROLL`, `RASTER-COLOR`), and `DRAW-SPRITES`, which shows only as many sprites on a row as the program says. Under them are `GFX-INDEXED`, `GFX-ROW-SHIFT`, and `GFX-ROW-COLOR`.
- `REQUIRE-GUI` loads a GUI written in Forth into the `GUI` vocabulary: buttons, check boxes, one-line text fields, lists, a menu bar with pull-down menus, a function key bar, panels (also from 9 tiles of an image), and dialogs, drawn each frame between `GUI-BEGIN` and `GUI-END`, and `GUI-ASK`, `GUI-MESSAGE`, and `GUI-CHOOSE`, which wait for the answer. The mouse, the keys (Tab moves the focus), and the first gamepad work them. The look is flat; every color is a role `GUI-COLOR!` sets, and the line widths are `GUI-BORDER-WIDTH` and `GUI-FOCUS-WIDTH`.
- `MOUSE-EVENT ( -- x y button kind true | false )` gives each press, release, and notch of the wheel in order, from the terminal, the window, and the Tk window, so that a click between two reads is not lost as it is with `MOUSE`. The oldest of 64 are dropped when more come. The window and the Windows console now report the wheel.
- `IMAGE-MODE` puts the pixels of `COPY-RECT` and `PUT-IMAGE` over, XORed, added, or mixed by `IMAGE-ALPHA` with those there, and `IMAGE-SCALE` draws them 1 to 16 times as large.

### Fixed

- The games in `examples` (`shmup.fs`, `hopper.fs`, `runner.fs`, and `paddle.fs`) left their window open when they ended; they now end Sigma, which closes it. Run from the interactive prompt with `INCLUDE`, they end Sigma too.

### Changed

- `PLAY` now always has 8 voices: `PLAYS` takes 1 to 8 and `PLAY?` takes 0 to 8 on any chip, and the voices after a chip's own sound like the last chip chosen. `CHIPS` takes any chips, also both `MSX` and `ST` and chips with more than 8 voices (the ones past the 8th are not played). A program that does not use these sounds the same as before, sample for sample.
- Larger limits: by default the dictionary has 32 MiB (before, 1 MiB) and the `ALLOCATE` heap 32 MiB (before, 896 KiB), each stack holds 4096 entries (before, 1024), and the dictionary holds 65535 words (before, 8192) with 1 MiB for their names (before, 256 KiB). An image may be 16384 pixels a side and 1 GiB (before, 8192 and 64 MiB), a font 64 MiB (before, 16 MiB), and the pool of samples is 64 MiB (before, 16 MiB). Physical memory is used only as a program fills the memory.
- Words are found through a hash table of their names: defining 60,000 words takes about 0.06 seconds instead of about 8 seconds. Which word a name finds is unchanged.
- Dictionary images are now `SIGIMG42` (`SIGIMG43` with the graphics words, `SIGIMG44` with the audio words) and record the `-m` and `-l` sizes they were saved with, since the input area moved in front of the dictionary. Images saved by 0.8.0 and earlier can no longer be loaded. `LOAD` reads an image saved with other sizes. An executable made by `SAVESYS` starts with the sizes it was saved with; `-m` and `-l` give it an error.

## [0.8.0] - 2026-11-09

### Added

- Sound on macOS: the audio words now play through an AudioQueue of AudioToolbox on the default output device (48 kHz 16-bit stereo, about 80 ms ahead), the framework loaded when the program runs, so that the macOS builds made on Linux need no SDK. Before, the music went on without sound there.
- The xchar words of gforth for UTF-8: `XC-SIZE`, `X-SIZE`, `XC@+`, `XC@`, `XC!+`, `XC!+?`, `XC,`, `XCHAR+`, `XCHAR-`, `XEMIT`, `XKEY`, `XKEY?`, `X-WIDTH`, `XC-WIDTH`, `+X/STRING`, `X\STRING-`, `-TRAILING-GARBAGE`, `XHOLD`, `EKEY>XCHAR`, and `X@+/STRING`. The widths of `XC-WIDTH` come from the Unicode Character Database 15.1.0 (`scripts/make-width-table.py`).
- Numbers in the forms gforth reads: `0x` for hexadecimal (`0xFF`, `-0x10`, `0x-5`), and the character literals `'a` (without the closing quote), `-'a`, and `''`.
- `ARGC`, `ARGV`, `ARG`, `SHIFT-ARGS`, and `NEXT-ARG`, as in gforth: a program sees the command-line arguments that have not been processed yet, and the ones it takes with `NEXT-ARG` are not processed as files (`sigma greet.fs world`).
- `scripts/sign-and-notarize-macos.sh` builds a universal (arm64 and x86_64) macOS installer package that puts `sigma` in `/usr/local/bin`, signs it with Developer ID certificates, has Apple notarize it, and staples the ticket.
- Added `examples/shmup.fs` (Sigma Storm), a vertical scrolling shooter: three stages with their waves, a carrier half way, and bosses in parts; a weapon of five levels, bombs, grazing, and a chain that multiplies the score; tunes and sound effects of its own. It takes the keys and a mapped gamepad, keeps its speed on a slow display by advancing in fixed steps, and plays silently in a build without the audio words.

### Changed

- Updated the product version and startup examples to 0.8.0.
- The command line now follows gforth, also in an executable made by `SAVESYS`: each argument names a file to include, in order (`sigma examples/hopper.fs`), and `-e text` (or `--evaluate text`) interprets `text`. After the last argument the banner and the interactive prompt follow, unless `BYE` ended the program; an error in an argument ends it with exit status 1. Before, the arguments were joined into one line of Forth input, run once, and the program exited, so `sigma "12 DUP * ."` is now written `sigma -e "12 DUP * . BYE"`.
- Dictionary images are now `SIGIMG36` (`SIGIMG37` with the graphics words, `SIGIMG38` with the audio words), since the argument words and the xchar words moved the numbers of the user's words. Images saved by 0.7.0 and earlier can no longer be loaded with `LOAD`, and 0.7.0 and earlier cannot load the new ones. An executable made by `SAVESYS` of 0.7.0 still runs, since it carries its own 0.7.0 runtime (with the old command line).
- `CHAR`, `[CHAR]`, and character literals give the code point of a UTF-8 character, as in gforth: `CHAR 日` is 26085 (before, 230, its first byte), and `'日'` is a character literal.
- On Windows, a console shows and reads UTF-8 while Sigma runs (the code page is put back at the end, also after Ctrl+C or Ctrl+Break, and for the programs `SYSTEM` starts). Before, UTF-8 text came out garbled in a Japanese console (code page 932), and the keys typed came as Shift_JIS.
- On Linux and macOS, `SHOW` with no display chosen now uses the Tk window when Sigma runs on a desktop (`DISPLAY`, `WAYLAND_DISPLAY`, or macOS's `__CFBundleIdentifier` is set) and `wish` starts; otherwise it uses the terminal as before. The games in `examples` now open a window there without `DISPLAY-TK`.

### Fixed

- In the MOD player, a row with a sample number and no note now takes the new sample's loop when the sound comes to its end or goes round its loop, at once if the sound has already ended, and silence if the new sample has no loop, as ProTracker's replayer does (checked against the source of pt2-clone). Before, the sound went on with the old sample, or stayed silent after it ended. A module tagged `FLT4` (Startrekker) keeps the old behavior.
- `FALSE PLAY-MOD` played a song that jumps back with `Bxx` for ever, so `MOD?` never became false; the song now ends where it would go round again. A pattern loop (`E6x`) still plays its rows again, and `TRUE PLAY-MOD` goes on as before.
- In the MOD player: a note delayed by `EDx` now sounds at its own period on the tick it starts (it kept the old period, or no sound, for that tick); `9xx` past the end of a sample with a loop plays the loop instead of nothing; `E9x` on a row without a note retriggers on the row's first tick too; `300` no longer slides back to a note the tone portamento already reached, after another note; `Bxx` goes to row 0 also after a `Dxx` on an earlier channel of the row; and a tempo set by `Fxx` counts from the next tick. These were found by comparing the player with libopenmpt, tick by tick.
- `examples/hopper.fs` ran at about half speed on macOS, since showing its window at four times the image's size through Tk took about 37 ms a frame and the game advances once a frame. Its window is now three times the image's size on every system.
- On a terminal on Linux and macOS, a key held down and released went on counting as held by `KEY-HELD?` for 0.6 s; once the key is repeating it now counts as held for 0.12 s after its last repeat. A key pressed once still counts for 0.6 s.
- On a terminal on Linux and macOS, `KEY-HELD?` went on counting a cursor key as held for 0.6 s after another cursor key was pressed, so a game could keep going the old way; a new cursor key now ends the one before it.
- In `examples/runner.fs`, holding P down no longer turns the pause on and off again and again.
- On a terminal on Linux and macOS, Backspace over a full-width character (Japanese, for example) moved the cursor back one column only, leaving half of the character on the screen, since the terminal's line input knows nothing of widths. Sigma now edits the lines of the interactive prompt and of `ACCEPT` itself: Backspace takes back as many columns as the character is wide, and Ctrl+U, Ctrl+W, Ctrl+D, Ctrl+C, Ctrl+\, and Ctrl+Z work as in the terminal. Cursor keys are now dropped instead of being put in the line as escape sequences.
- On Windows, file names and `SYSTEM` commands other than ASCII failed (`ERROR #-554 !`, `HOST FUNCTION ERROR !`), since the C library took them in the ANSI code page; they are now UTF-8, passed on as UTF-16. This also lets SAVESYS and an executable it made work from a folder with such a name.
- On Linux and macOS, an executable made by `SAVESYS` had no permission to run (`-rw-r--r--`); it now gets every permission the umask lets through (usually `-rwxr-xr-x`).
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

[0.8.0]: https://github.com/fukuyori/ForthSigma/releases/tag/v0.8.0
[0.7.0]: https://github.com/fukuyori/ForthSigma/releases/tag/v0.7.0
[0.6.1]: https://github.com/fukuyori/ForthSigma/releases/tag/v0.6.1
