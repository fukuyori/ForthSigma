# Task control configuration checks

Japanese version: [TASK_CONTROL_CONFIG_TESTING.ja.md](TASK_CONTROL_CONFIG_TESTING.ja.md).

This guide runs C00窶鼎16 from [the configuration plan](TASK_CONTROL_CONFIG_MATRIX.md) with Zig 0.17.1 and Python 3. Run commands from the repository root. This is functional verification, with no benchmark or elapsed-time report. Do not package or install the output system-wide.

## Windows (PowerShell)

```powershell
python tests/scripts/verify-task-public-matrix.py --fresh-cache
```

## Linux x86_64 (run on the Linux machine)

Use the same checkout including the changes for 1381. Keep the checkout on a writable filesystem. Install Zig 0.17.1 and Python 3 according to the project's build instructions before running the checks; this script does not download dependencies.

```sh
zig version  # must report 0.17.1
python3 --version
uname -sm   # Linux x86_64
mkdir -p .work
python3 tests/scripts/verify-task-public-matrix.py --fresh-cache > .work/task-public-linux.log 2>&1
printf '%s\n' "$?"  # Check the exit status immediately; zero is required.
cat .work/task-public-linux.log
cat .work/task-public-matrix/results.json
```

With `--fresh-cache`, each invocation uses new `.zig-global-cache` and `.zig-cache` directories under a unique `.work/fresh-*/` directory. All configurations in that invocation share these initially empty caches; dependency reuse within the run is allowed. Build logs include `--summary all`, distinguishing executed and cached steps. Without the option, the script uses the checkout caches. Native output and logs go to `.work/task-public-matrix/`. Use separate Windows and Linux checkouts or copy the results before rerunning: every invocation resets `results.json` to `[]`; after a `--configs` rerun it contains only the selected configurations that completed, not rows from earlier runs. Logs for selected configurations are overwritten; other log files can remain from older runs. The JSON records completed configurations; an interrupted or failed run is not a full pass. `commands.json` records commands and log paths. Preserve stderr and the process exit status as well.

To rerun selected configurations:

```sh
python3 tests/scripts/verify-task-public-matrix.py --configs C08 C11 C12 C16
```

Each native configuration runs `zig build test`, builds the executable, stages and directly runs the runtime tests, and checks all 58 TASK- words. EXTENSION builds also run Forth lifecycle/cancellation checks and capability rejection checks where files or graphics are disabled, plus paint rejection without a native window even when graphics is enabled. Existing controlled runtime tests must pass for enabled kind=2 and supported kind=5; these use injected I/O and synthetic paint publication, not real devices. Debug vocabulary checks distinguish DBG (`debug`) from EXEC-LIMITED (`debug` and `extension`). Enabled EXEC-LIMITED budgets are checked separately. Each JSON row records OS/platform, architecture, Zig/Python versions, DISPLAY/WAYLAND_DISPLAY/TERM, process TTY flags, cache paths, and runtime passed/skipped/failed counts. Runtime logs expose passed/skipped tests even when Zig's build execution cache would otherwise suppress output.

E=0 word checks use only `[DEFINED]` in the default search order. Hidden or unreachable builtins, TASK-specific HELP entries, and saved-image builtin/direct-Op exclusion are not verified by this matrix.

The matrix does not open real windows or sound devices as an acceptance test. On Linux, record desktop/TTY/backend availability separately. C16 disables X11; passing the matrix does not establish a working framebuffer or other display backend. Do not treat optional skipped tests as hardware passes. Real terminal input, audio, graphics and shutdown integration remain separate acceptance work. Deadline and latency targets are not measured by this script.

## Cross compilation only

From Windows PowerShell, compile all configurations for macOS without running target programs:

```powershell
python tests/scripts/verify-task-public-matrix.py --build-only --target aarch64-macos
```

This builds the executable, core/host/runtime test binaries and the existing freestanding boundary check. Output is under `.work/task-public-matrix/aarch64-macos/`. It does not establish macOS runtime behavior; that belongs to 1383. `--target` requires `--build-only`, preventing accidental execution through an emulator or another OS.

E=0 checks use only `[DEFINED]` in the default search order. Hidden/unreachable builtins, TASK-specific HELP entries, and saved-image builtin/direct-Op exclusion are unverified. Enabled kind=2 and supported kind=5 acceptance is checked through existing controlled runtime tests with injected I/O and synthetic paint publication. Paint without a native window must return NO-CAPABILITY, including Linux C16. Real device acceptance remains separate.

Each JSON row records platform/OS, arch, Zig/Python versions, DISPLAY/WAYLAND_DISPLAY/TERM, process TTY flags, cache paths, and runtime passed/skipped/failed counts.

See [the 1381 implementation report](TASK_CONTROL_IMPL_1381.md) for observed results and pending work.
