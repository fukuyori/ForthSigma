# Test and verification scripts

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
