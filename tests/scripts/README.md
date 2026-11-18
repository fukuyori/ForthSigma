# Test and verification scripts

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
