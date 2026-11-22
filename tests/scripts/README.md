# Test and verification scripts

`zig build audio-lifecycle-check --prefix .work/1127/windows` builds an isolated
blocked-consumer fixture (outside the normal install/release). Run
`python tests/scripts/verify-audio-shutdown.py .work/1127/windows/audio-check/x86_64-windows/probe.exe`
to verify three owned child processes exit with status 1 while retaining storage.
Use a Linux target and run the generated probe under Linux for the POSIX check.
See [lifecycle results](../../docs/PCM_HOST_LIFETIME_IMPLEMENTATION.md).

`python tests/scripts/verify-saved-application.py PATH` creates owned SAVESYS
executables and checks entry dispatch, raw arguments, host bypass, corrupt images,
atomic resave/self-alias rejection and process exit. On POSIX it also uses an owned
PTY for interruption and terminal restoration. `--no-debug` and `--no-files` select
feature-disabled expectations. On Windows, `verify-saved-application-windows.py
PATH` checks Ctrl+C in a hidden private console. Both scripts clean up their own
files under `.work/1069`; neither sends input to the user console. See
[results and Mac procedure](../../docs/SAVED_APPLICATION_STARTUP_IMPLEMENTATION.md).

`verify-filesystem.py --sigma PATH --output PATH` checks 1,010 observed Gforth
COMPACT cases, long byte paths, realpath capacity/alias/links, regular-file metadata
and SYNC direction/pending-input/EOF and rejection cases on owned temporary files.
`zig cc -shared -DSIGMA_FS_TESTING src/host_filesystem_native.c -o .work/646/filesystem-native.dll`
builds the Windows native fixture for `verify-filesystem-native.py --library PATH`.
On Linux use a GNU shared object (`-shared -fPIC -target x86_64-linux-gnu`).
The native test checks 1,000 iterations for handle/fd cleanup and, on Windows,
uses a test-only counter to verify device rejection before open. It does not
open serial devices. All owned test files stay under `.work/646`.

`verify-graphemes.py --sigma PATH` compares EXTENSION's X-GRAPHEME and
X-GRAPHEME-LAST against all 853 pinned Unicode 18.0.0 GraphemeBreakTest cases,
including every cluster from both ends (3,096 public-word checks).
`python scripts/make-grapheme-table.py --check` verifies offline regeneration
and the SHA256 hashes of the official inputs. Neither command accesses the network.

Run these scripts from the repository root. `test-*` contains regression tests,
`verify-*` contains integration and comparison checks, and `probe-*` collects
reference results. `gforth-p00/` contains the P00 Gforth reference suite; see its
README for the required reference build. Platform and reference-runtime
requirements still apply to individual scripts.

Examples:

```sh
python3 tests/scripts/test-word-reference.py --sigma zig-out/bin/sigma
python3 tests/scripts/test-line-editor.py --sigma zig-out/bin/sigma
python3 tests/scripts/verify-p10.py --sigma zig-out/bin/sigma --output .work/p10/report.json
python3 tests/scripts/verify-feature-matrix.py --platform macos
python3 tests/scripts/verify-debug-outputs.py --sigma zig-out/bin/sigma --out tests/scripts/debug-outputs/windows.json
python3 tests/scripts/verify-debug-outputs.py --compare tests/scripts/debug-outputs/macos.json tests/scripts/debug-outputs/windows.json
```

Build, distribution, data-generation, documentation-generation and benchmark
commands remain in `scripts/`, including `check-docs.py`, `word-reference.py`,
its `word_reference_examples.py` helper, and `benchmark-runtime.py`.
`test-benchmark-runtime.py` requires Linux's process CPU clock API.

`debug-outputs/` keeps what `verify-debug-outputs.py` recorded on each system, to be
compared with `--compare`.

`check-ime.fs` is a check by hand, not a script that judges: it shows a `GUI-FIELD` to
type Japanese into with the input method, and prints what was entered (its header
tells how to run it).

`check-window.fs` is a check by hand too, of Sigma's own window: it prints the presses,
releases, and wheel notches of the mouse, and lets the window be moved, resized, and
closed while the program waits for input and while it computes (its header tells how to
run it).

`check-fullscreen.fs` is a check by hand of `FULLSCREEN` and `MOUSE-CURSOR`: the window
opens fullscreen, and keys leave it, enter it again and hide the cursor (its header
tells the keys and what to look for).

`check-auto-size.fs` is a check by hand of `WINDOW-SIZE 0 0`: it shows three images in
turn, and the window should fit the work area of its screen (its header tells what to
look for).

Recorded measurement JSON and original external review transcripts preserve
paths as they were when recorded. Current commands use `tests/scripts/`.

For the experimental Linux X11 backend, build with `zig build -Dx11=true`.
`test-linux-native-window.py` checks pixels, letterboxing, keys and close/reopen;
`SIGMA_TEST_RESIZE=1` also checks resize redraw. On a private Xvfb only,
`SIGMA_TEST_REMAP=1` checks keyboard-map refresh, and `test-linux-xim-fixture.py`
checks preedit changes, Unicode commits and IM liveness. Both intrusive cases
require `SIGMA_TEST_PRIVATE_XSERVER=1`; never point them at the user desktop.
`SIGMA_TEST_CLOSE_AFTER=6` covers reopening after the initial startup deadline.
`test-linux-x11-failures.py` owns a temporary local socket and checks rejected,
disconnected and stalled setup. `SIGMA_TEST_BINARY` selects the built executable.

`test-linux-display-budget.py` requires the experimental Linux build and checks the
shared five-second native/Tk search budget, blocked PNG writes, unresponsive or
stopped children, trickling output, cleanup, retries and explicit Tcl after failure.
It uses temporary fake wish programs and a private local socket; no desktop is used.
The acceptance tolerance is 5.25 seconds including process startup and scheduling.

`check-window-keys.fs` logs native-window key codes and A-held changes for manual
special-key, repeat and focus-loss checks. Run with stdin from `/dev/null` to exclude
terminal input. Escape exits; Ctrl+C in the window is caught in key and held-state reads. Repeated
codes and VM processing timestamps need correlation with the operator’s report.
See its header for the procedure.

`test-linux-window-colors.py` compares native and Tk raster readback for all eight
full/2/16/256-color and dither settings, before and after integer-zoom resize.
`test-linux-auto-display.py` checks automatic selection, selected-backend loss,
explicit failure and `DISPLAY-AUTO` recovery. Both own authenticated depth24 Xvfb
servers and never use the user's DISPLAY. Set `SIGMA_TEST_XVFB` if Xvfb is not on
PATH and `SIGMA_TEST_BINARY` for the experimental Linux executable. Missing
Xvfb/wish is reported as a skip with exit code 77, rather than a passing result.
`test-linux-x11-support.py` checks the shared helper's partial-line timeout,
stderr draining, process-group cleanup, X11 authentication and skip status.

`check-window-display.fs` is a manual color/resize/monitor-movement check. It shows
color bars, a gray ramp and four click targets; 0/2/6/5 select color count and D
changes dithering. It changes no desktop display settings. See its header.


### 子プロセス管理（643）

`verify-process-words.py --sigma PATH` は公開PROC語とFILE/AVAILABLEの大量3streamを、`verify-process-interrupt.py --sigma PATH` は無期限WAITの中断と子の生存を調べる。Windowsの中断試験は専用の非表示consoleを作り、その中だけにCtrl+Cを送る。

`zig cc tests/process_wish_fixture.c -o .work/643/wish-fixture.exe` で制御されたfixtureを作り、`verify-process-capacity.py --sigma PATH --fixture PATH` で64実プロセスと超過/再利用、`verify-process-tcl.py --sigma PATH --fixture PATH` でTcl内部予約枠・再起動・script削除・終了時の子孫回収を確認する。Linux用fixtureは `zig cc -target x86_64-linux-musl` で作り、WSL内でLinux版Sigmaと実行する。fixtureは実Tcl/TkやGUI表示の代用とはしない。

native C単体は `zig cc -shared -DSIGMA_PROC_TESTING src/host_process_native.c -o .work/643/process-native.dll` と `verify-process-native.py --library PATH`。LinuxのPython ctypesにはGNU共有libraryを使う。Linuxの子孫試験は専用helperのsubreaper設定を一時変更し、自分で作った子孫を回収して元の設定へ戻す。製品Sigmaにsubreaperを設定しない。

各scriptの`--output PATH`でJSON証拠を残せる。OS単体・公開語・Tcl protocol・実GUIを区別し、Macのクロスコンパイルは実機確認へ代えない。

### EXEC-LIMITED (652)

Run `python tests/scripts/verify-execution-control.py PATH_TO_SIGMA` for public budget/THROW/NS cases. On Unix it also owns PTYs for raw character/paste/ESC retention, SIGINT, NS and cooked KEY interruption, and terminal-mode restoration. Run `python tests/scripts/verify-execution-control-windows.py PATH_TO_SIGMA_EXE` for a hidden private console with injected F1/Japanese/paste/partial ESC input, cooked Ctrl+C, NS/KEY and queue-full retention. It never sends input or signals to the user console. Redirect stdout to JSON evidence. These fixtures do not prove physical keyboard or Mac acceptance.

## Public PCM validation

`python tests/scripts/verify-pcm-stream.py PATH_TO_SIGMA` runs owned processes with silent PCM: write/full wait/drain/close, memory error recovery, busy open, saved applications and dictionary append. Use `--no-image` for image-excluded builds.

`python tests/scripts/verify-pcm-terminal.py PATH_TO_SIGMA` uses a dedicated hidden Windows console or a Linux PTY. It injects characters, Japanese, incomplete ESC and Ctrl+C, verifies WAIT/STOP -28 and CLOSE -516/retry, retained input and restored terminal settings. It never injects into the user's console. All frames are zero; this does not verify audible sound or physical keys. Results: [PCM validation](../../docs/PCM_PUBLIC_IMPLEMENTATION.md).

## Forth synthesis prototype

`python tests/scripts/verify-pcm-synth.py PATH_TO_SIGMA [--benchmark]` checks hand-calculated samples, independent Python s16LE vectors, split/render/register continuity, invalid arguments, forced partial/full/timeout/close failures and silent real PCM integration. Benchmark mode records seven warmed synthesis-only NTIME/CPUTIME intervals with a final-buffer checksum; the separate paced run uses an external monotonic clock and records write/wait/underrun counts and AUDIO?. It does not validate a chip emulator or audible output. Run from the repository root. [Scope and results](../../docs/PCM_SYNTH_PROTOTYPE.md).

## NES APU Forth subset

`python tests/scripts/verify-nes-apu.py PATH_TO_SIGMA [--benchmark]` compares Forth per-cycle/batched state and PCM against an independent Python per-cycle model. It checks frame/reset/IRQ boundaries, envelope/length/sweep/linear behavior, timestamped writes, queue ordering/capacity, invalid input and silent real PCM integration. Benchmark mode times nominal/reference and fastest-noise APU workloads in seven warmed processes with 128 timed writes. This regression workload leaves DMC playback disabled and excludes emulated CPU/PPU, bus arbitration and device playback; the five-voice workload is in verify-nes-dmc.py. Long schedules use owned temporary Forth files, avoiding CLI -e length limits. [Specification, source audit and results](../../docs/NES_APU_FORTH.md).

## NES DMC model

`python tests/scripts/verify-nes-dmc.py PATH_TO_SIGMA [--benchmark]` checks all rates, copied buffers, loop/stop/restart, IRQ/status, address wrap, direct DAC parity limits, all32799 LUT entries and mapped-memory validation. Streaming8kHz DAC exceeds1024 queued writes and compares full output with Python. Benchmark mode records seven processes per nominal/reference/maximum-noise-DMC/direct-DAC workload. The companion verify-nes-apu.py retains the fixed1134 output SHA. Own sample patterns only; no ROM, hardware DMA or audible generated output. [Contract and measurements](../../docs/NES_DMC_FORTH.md).

## SID register model and filter proxy

`python tests/scripts/verify-sid.py PATH_TO_SIGMA [--benchmark]` checks per-clock Python against both Forth paths, scheduled three-voice PCM, ADSR/sync/noise boundaries, atomic rejection, pulse/ring/routing hand values, all2048 coefficients,64 filter impulse cases and8kHz queue compaction with full PCM comparison. Benchmark mode uses seven warmed fresh processes for nominal/reference/maximum mixed-filter-sync/three-noise/8kHz write workloads. `python scripts/sid-filter-coeffs.py --check` reproduces the Decimal table. Audio checks submit silence. No real6581/8580 or ROM oracle is claimed. [Contract and limits](../../docs/SID_FORTH.md).

## Paula stereo register model

`python tests/scripts/verify-paula.py PATH_TO_SIGMA [--benchmark]` compares independent per-clock Python with both Forth paths and split stereo PCM. It checks DMA/reload/IRQ, manual-data latches, volume and attachment masks, memory wrap/preservation, atomic errors and queue compaction. Benchmarks record seven processes for nominal/reference/minimum-period/attachment/8kHz volume/manual workloads, each preceded by full PCM verification outside timing. Audio tests submit silence; Mac and generated-sound audition remain separate. [Contract and limitations](../../docs/PAULA_FORTH.md).

Supplemental `python tests/scripts/verify-paula-stream.py PATH_TO_SIGMA` runs ten isolated stereo callback/hand-attachment checks without opening native PCM. It forces partial/full retries and checks nonzero bytes,4-byte offsets,cleanup errors and attach alternation.

## YM2149/ST register and virtual-port model

`python tests/scripts/verify-ym2149.py PATH_TO_SIGMA [--benchmark]` checks independent master-clock Python against both Forth paths: all16 envelope shapes,64 mixer truth tables,32 coefficients,3072 I/O cases,ST select/data,atomic errors,queue compaction and full PCM. Benchmark mode verifies all32768frames and37 semantic state fields for six workloads, then times seven fresh processes; every timed final state is also checked after warmup/reset. `python tests/scripts/verify-ym2149-stream.py PATH_TO_SIGMA` adds isolated mono callback/cleanup and relative-time/query/bus/reset-state hand checks. `python scripts/ym2149-levels.py --check` reproduces the ideal DAC table. Native zero-volume regression runs with `zig build test`. No real peripheral or physical-chip oracle. [Contract and measurements](../../docs/YM2149_FORTH.md).

## PCM audio exclusion and listening acceptance

For CHIP-8 audio, run `python tests/scripts/verify-chip8-audio.py PATH_TO_SIGMA` for independent math/fullPCM/state checks and `python tests/scripts/verify-chip8-audio-stream.py PATH_TO_SIGMA` for nonzero RAM-only mono/cleanup fixtures. `python scripts/chip8-pitches.py --check` reproduces all256 integer steps. Run from the repository root; these commands do not submit generated sound to a device. [Contract](../../docs/CHIP8_AUDIO_FORTH.md).

`python tests/scripts/verify-pcm-exclusion.py PATH_TO_SIGMA --audio enabled` (or `disabled`) executes REQUIRE-AUDIO through EVALUATE/CATCH and checks actual name lookup/stack depth. It opens no audio. `python tests/scripts/pcm-listen.py PATH_TO_SIGMA --case 1` runs a silent acceptance case. Add `--audible` explicitly for generated sound; cases1..8 cover mono/stereo, MML/SFX mix, discard/reopen, drain, SAVESYS and foreground Ctrl+C/ACCEPT. Execution JSON never claims a human listening result. [Procedure and remaining acceptance](../../docs/PCM_LISTENING_ACCEPTANCE.md).

## ZX Spectrum audio (1169)

`python tests/scripts/verify-zx-spectrum-audio.py PATH_TO_SIGMA` checks all 65536 OUT/IN ports, AY masks/envelopes, independent CPU-tick PCM/state, same-tick ordering and error boundaries. It opens no audio device.

`python tests/scripts/verify-zx-spectrum-audio-stream.py PATH_TO_SIGMA` checks partial writes, copied bytes, timeout/cleanup and stream preflight with RAM callbacks. Generated audio remains in memory. See [scope and results](../../docs/ZX_SPECTRUM_AUDIO_FORTH.md). Speed measurements require a separate start confirmation.

`python tests/scripts/measure-zx-spectrum-audio.py PATH_TO_SIGMA` verifies six full32768frame workloads without timing by default. Use `--measure` only after user timing-start approval; it performs seven fresh-process rounds. See [preparation review](../../docs/reviews/1170-1171-review-response.md).

## Apple II audio (1179)

`python tests/scripts/verify-apple2-audio.py PATH_TO_SIGMA` checks the speaker and Mockingboard model against an independent per-cycle oracle: every address written and read, the 6522 ports and AY bus functions, AY masks/envelopes, the speaker mean, whole stereo PCM and state on the batched and per-cycle paths, same-cycle ordering and error boundaries. It opens no audio device. A Debug build takes a few minutes.

`python tests/scripts/verify-apple2-audio-stream.py PATH_TO_SIGMA` checks partial writes, copied bytes, the initial eight blocks, timeout/cleanup and stream preflight with RAM callbacks. Generated audio remains in memory. See [the specification and results](../../docs/APPLE2_AUDIO_FORTH.md).

`python tests/scripts/measure-apple2-audio.py PATH_TO_SIGMA` verifies six workloads of 32768 frames against the oracle without timing by default. Use `--measure` only after the user has approved the start of timing; it then runs each workload in seven fresh processes.

`python tests/scripts/accept-apple2-audio.py PATH_TO_SIGMA [--play | --interrupt] [--record FILE]` is the acceptance on a machine's audio device (1180 to 1182): silent by default, `--play` plays three pieces a person listens to, `--interrupt` is the Ctrl+C step and needs a foreground terminal. Use a ReleaseFast build.

`python tests/scripts/profile-snes-dsp-audio.py PATH_TO_SIGMA` runs probes for the parts of a frame of the Forth S-DSP model (1188). `--measure` times them, only after the user has approved the start of timing.

## SNES S-DSP audio (1174)

`python scripts/snes-tables.py --check` reproduces the512 hardware constants.

`python tests/scripts/verify-snes-dsp-audio.py PATH_TO_SIGMA --reference-doc CACHED_FULLSNES_HTML` checks exhaustiveBRR/Gauss/rates/registers/ARAM, independentPCM/state/fullARAM and queue/error boundaries. A cached [fullsnes](https://problemkaputt.de/fullsnes.htm) HTML is checked against its pinned hash. Without the option, the numeric hash still checks the table but independent document extraction is omitted. No audio device opens.

`python tests/scripts/verify-snes-dsp-audio-stream.py PATH_TO_SIGMA` checks19 owned stereo RAM callback fixtures:4byte offsets, prime/continuation, partial writes, timeout and cleanup. See [scope/results](../../docs/SNES_DSP_AUDIO_FORTH.md).

`python tests/scripts/measure-snes-dsp-audio.py PATH_TO_SIGMA` validates six16384frame workloads without timing by default. Use `--measure` only after user timing-start approval.

### S-DSP native frame kernel

`verify-snes-dsp-audio.py SIGMA --native` adds native-frame BRR256x16x3,317 envelope cases,Gaussian256x4 and FIR8 impulses against independent Python. `verify-snes-dsp-native.py SIGMA` checks batches, divider, backend switches, reset, EXEC-LIMITED interruption/resume and SAVESYS state/ARAM. Pass `--no-debug` when debug is excluded.

`verify-snes-dsp-audio-stream.py SIGMA --native` uses RAM callbacks only. `measure-snes-dsp-audio.py SIGMA --native` defaults to untimed six-load validation; add `--measure` only after fresh user start approval. Audio-excluded builds use the reference Forth checks without --native. Temporary helpers belong under `.work`.

### Standard sound

`python tests/scripts/listen-standard-sound.py PATH_TO_SIGMA` plays 32 listening cases of the standard sound (PLAY, MML V/S/M, BEEP, PLAY-TONE, the instrument words, SAMPLE and SFX, MOD, the global effects, and all 16 voices at once) and of the chip libraries of `include/` (cases 22 to 32: each chip, SOUND, and STYLE), printing what should be heard before each and waiting for Enter. `--list` prints the cases, `--case N` picks some, and `--silent` runs them all at `0 MASTER-VOLUME` to check that they run. The JSON records only what ran; a human reports what was heard. Generated programs and the MOD file go under `.work/1201`.

`python tests/scripts/measure-standard-sound-load.py zig-out/audio-check/<arch>-<os>/sound-load(.exe)` checks three 16-voice loads on the engine alone (built by `zig build sound-load-check -Doptimize=ReleaseFast`) without timing by default. Use `--measure` only after user timing-start approval; it renders each load once untimed and seven times timed, ten seconds of 48 kHz stereo each.

`python tests/scripts/compare-chip-libraries.py` compares the chip libraries of `include/` with the chips' settings removed in tque 1199: it builds `tests/data/chip-compare/old_probe.zig` at e90b6f6 and `new_probe.zig` at HEAD (or `--new COMMIT`, or `--new WORKTREE` for the files as they are now) in git worktrees of a new folder under `.work/1206`, plays the same 21 one-note cases, and prints the fundamental, RMS, zero crossings, and harmonics of both as JSON. It removes only the worktrees it made. The new side does not read `include/`: `new_probe.zig` writes the libraries' settings out again (`src/tests/audio_test.zig` checks the libraries give them), so a change to a library needs the same change there. No timing; nothing is heard. See [the results](../../docs/measurements/2026-11-21-chip-libraries-compare.json).
