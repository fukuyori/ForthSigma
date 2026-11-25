# Task control manual acceptance (1382)

Japanese: [TASK_CONTROL_ACCEPTANCE_MANUAL.ja.md](TASK_CONTROL_ACCEPTANCE_MANUAL.ja.md).

## Preparation and record

Run one item at a time from the repository root, in a foreground terminal.
Windows uses PowerShell and `zig-out/bin/sigma.exe`; Linux uses
`zig-out/bin/sigma` on Claude's separate machine. Build with Zig 0.17.1:
`zig build -Doptimize=ReleaseFast -Ddebug=false -Dtask-trace=false`.
Do not run timed acceptance until the operator confirms the frozen plan.
These checks observe progress, not latency. Do not time them.
Record AC ID, OS/kernel, terminal, backend/capabilities, command, keys, expected
and observed result, exit status, screenshots/logs, source/binary SHA-256 and
missing resources in `.work/acceptance/manual-<OS>/`. Mark missing capability
as unverified, never passed, and propose how to verify it. Do not transfer Windows evidence to Linux.
Keep another terminal available to inspect the owned process, threads and children.
Only inspect/stop the test's own processes. After Ctrl+C check shell echo,
cursor, key entry and a fresh sigma invocation.

Start search with `zig-out/bin/sigma examples/task-search.fs` and I/O with `zig-out/bin/sigma examples/task-checksum.fs` (sigma.exe on Windows). After the automated examples group, `.work/1380/checksum-chunks.fs` is also available: the three expected checksums are 8355840, 8355840 and 21. If the run finishes before a mid-work quit can be observed, record that operation as unverified.

## AC-02

Run: `zig-out/bin/sigma examples/task-path.fs` (sigma.exe on Windows).

- **Preparation:** start G1 in the foreground.

- **Operation:** alternate `n` and unrelated keys, then `q` during calculation.

- **Expected result:** input and frame/generation output progress; old generations never replace the latest display; clean exit.

- **Record:** keys, displayed generations, cancellation diagnostics and exit state. This terminal example does not validate native graphics.

Native graphics/cursor: implement fixture 1394; Claude records each native OS run (1397–1399), with user observation.

## AC-05

Run: `zig-out/bin/sigma tests/scripts/check-task-console.fs` (sigma.exe on Windows).

- **Preparation:** create `.work` and start the integration fixture.

- **Input mode:** terminal `KEY` uses line input and requires Enter (USER_MANUAL.md, KEY). This fixture uses `EKEY EKEY>CHAR`, so send each letter without Enter; a newline would become the next input. The pipe integration test exercises the same fixture.

- **Operation:** at `active` press `r`; at `replaced` press `c`; at `bye-active` press `b`.

- **Expected result:** frame=r/c/b, cancelled and released, file I/O progress while computation runs, then exit.

- **Record:** output, scratch file cleanup, process/thread ownership. Multiple simultaneous tasks, audio and native display ownership still require a combined fixture; mark these unverified. Implement the combined task/audio/window fixture in 1394; Claude runs it on each OS (1397–1399) with the user observing sound and the native screen.

Terminal KEY requires Enter because it uses line input (USER_MANUAL.md, KEY). This fixture now uses EKEY EKEY>CHAR: send letters without Enter, since a newline would become the next input. verify-task-examples.py also checks the pipe path. For simultaneous tasks/audio/window ownership, implement 1394; Claude runs it per OS (1397–1399), with user observation of screen/audio.

## AC-18

Run from the repository root after `zig build` (use `sigma.exe` on Windows):

```sh
export ZIG_GLOBAL_CACHE_DIR=$PWD/.work/codex-cache/global ZIG_LOCAL_CACHE_DIR=$PWD/.work/codex-cache/local
python3 tests/scripts/manual-acceptance-tty.py --cases mixed --sigma zig-out/bin/sigma
```

Windows PowerShell:

```powershell
$env:ZIG_GLOBAL_CACHE_DIR = "$PWD/.work/codex-cache/global"
$env:ZIG_LOCAL_CACHE_DIR = "$PWD/.work/codex-cache/local"
zig build
python tests/scripts/manual-acceptance-tty.py --cases mixed --sigma zig-out/bin/sigma.exe
```

- **Preparation:** Python 3.9+, extension/files enabled, writable `.work/`; run only one AC-18 fixture at a time because its scratch name is fixed. The runner uses POSIX pty on Linux/macOS and ConPTY in a contained Job on Windows. Input is sent by the runner, without Enter.
- **Operation:** `check-task-wait-real.fs` loads `task-wait-real-common.fs`. It writes/opens `.work/ac18-real.tmp` and submits a real I1 task. The same aligned target array registers terminal input (kind=1), that file's readable data (kind=2), task success (kind=3), and a clock (kind=4). A separate positive 30 ms clock wait checks timer delivery; the mixed set uses a zero clock deadline so disk readiness cannot repeatedly restart a positive relative deadline. The runner sends `x` after INPUT-READY, then Ctrl+C after INTERRUPT-READY.
- **Expected result:** SOURCES=15, SIMULTANEOUS=4; every event's index, tag and reason checked, input and file bytes still consumable afterward. Eighty calls reuse the same buffers; Ctrl+C is caught as THROW -28, and registration succeeds again. Closing the file gives HANDLE; reopening/rebinding succeeds. PASS, scratch deletion, normal exit, restored terminal and a fresh search process are checked.
- **Record:** `ac18-real-composite/output.bin`, `output.txt`, `events.jsonl`, `processes.json` and `results.json`. These are public observations of detachment; they do not expose internal reference counts. Zig wait/host/public API tests additionally cover failure/rollback/detach paths. A regular disk file is a real provider, but does not demonstrate a blocked pipe becoming ready.

Native paint and window close are opt-in. In a display-enabled session, Claude runs the same command with `--native-paint --timeout 120` (1397–1399). `check-task-wait-paint-real.fs` adds kind=5 to the **same** target array: native host window id=0, `GFX-WINDOW-FRAMES` shown as arg0, arg1=0. Expect SOURCES=31 and SIMULTANEOUS=5. Observe the red 128×128 image; at CLOSE-WINDOW-NOW, close it using the native window control. The fixture waits for the native open flag to clear, then checks NO-CAPABILITY for a new paint registration without a window. Record visual observation separately. This checks painted completion and subsequent user close; closing during an outstanding, not-yet-painted registration is still a separate race test (1394). The supplemental `public paint real native window wait (opt in)` must report explicit OK; its macOS skip is unverified, not a failure of the five-source fixture.

Without `--native-paint`, paint/close is recorded as **unverified**. Set `--display-reason` to the actual reason; for this Linux sandbox: sockets are restricted and X11 cannot be reached. Do not substitute a timer for paint or infer a display pass. Claude must rerun with an available native display in 1397–1399. The runner preserves DISPLAY rather than forcing `:0`.

Platform evidence: `src/main.zig` uses `ioWaitProbe`/`filePollByte` to retain probed bytes, and semantic EOF; POSIX descriptor waits use poll. Windows regular disk files use stdio, whereas native pipes use bounded Reader/Writer workers and common Wake notifications (`host_file_reader.zig`). The fixture deliberately uses a portable regular file, with actual READ-FILE and byte verification, instead of POSIX-only FIFO setup. Existing main-host tests cover file-wait interruption and fetched-byte restoration; public API tests cover I/O reason conversion. Claude must verify readiness, EOF/reposition, Ctrl+C, terminal recovery and process cleanup natively on Windows/macOS; Linux results do not accept those platforms.

## AC-19

Use the `--cases mixed` command above. `check-task-fair-real.fs` runs T1 search and I1 checksum repeatedly in **one sigma process**, alongside terminal input and actual LICENSE file reads. Input, file, both task completions and a zero clock are registered together. A bounded main-loop turn polls completions, consumes at most one terminal event, releases/replenishes completed jobs, then yields. Successful search results and checksum values are checked. Work continues until `q`.

The runner sends `a/b/a/b` across four observation windows (`--fair-window`, default 2 seconds), then `q`. `progress.json` records cumulative successful search/checksum counts, input count, file bytes, received output bytes, timestamps and the sigma PID. Every interval between recorded samples must show progress for all five counters. A stopped fixture, failed result, stalled counter or failed cleanup fails the subcase. There is no minimum throughput or response-time threshold; the window selects a finite observation period, and `--timeout` only guards hangs. A slower native run can use a longer window while preserving the evidence and reason.

This is evidence of progress in the observed run, not a proof for every schedule. Queue-full retry, queue dwell and Snapshot availability remain separate coverage (1396); worker-to-worker waits remain prohibited by the public API. Inspect the per-case status even when the overall AC remains unverified for broader coverage or missing native collectors.

## AC-20

The same-process fixture is run again as `ac20-same-process`, with independent logs and counters. Check that T1, I1, terminal input, file data and output continue together until quit, with no counter stuck across the recorded intervals. Record `results.json`, both `progress.json` files, binary/source hashes and the OS. Run `--self-test` to verify the existing containment checks: cleanup must never signal outside the runner's anchored session/process group (Windows uses its non-breakaway Job). The new scenarios reuse that cleanup unchanged.

`--cases all` (default) also retains the previous two-session search/checksum overlap check; that check alone does not establish fairness within one host. The mixed fixtures do not replace single-VM time checks (1390–1393) or screen/audio ownership checks (1394). Windows ConPTY and macOS pty execution, native process collectors and optional real display observation are for Claude in 1397–1399.

Linux evidence (2026-11-25, main `6856d99` with working-tree changes): the three new headless subcases passed. AC-18 returned all four sources and passed 80 reuses, interrupt/re-registration, file reopen and terminal recovery. AC-19 search/checksum counts increased 23/22 → 90/90, and AC-20 increased 23/22 → 90/89; both input counts increased 1 → 4 and output bytes 60 → 240, with file bytes advancing at every sample. These are observed counts, not performance targets. Native paint/close remains unverified because sandbox sockets prevent X11 access. Windows/macOS remain unverified until Claude runs them. The machine-readable [Linux evidence summary](measurements/2026-11-25-task-1395-linux.json) preserves the scope and counts; complete logs remain in `.work/acceptance/1395-linux/`. The examples verifier passed 17 groups and the terminal self-test passed. `zig build test` had only the two known X11 send=-1 failures (1662 passed, 48 skipped); `zig build test -Dx11=false` passed. Documentation validation passed with zero findings.

## AC-24

Run: `zig-out/bin/sigma examples/task-path.fs` (sigma.exe on Windows).

- **Preparation:** note PID/threads/children using Get-Process on Windows or ps on Linux.

- **Operation:** quit with `q` during work; repeat in a new process with Ctrl+C; repeat search and checksum.

- **Expected result:** owned task resources end and terminal recovers; distinguish task completion from output drain and process exit.

- **Record:** before/after ownership and terminal behavior. For child/audio/window ownership at exit, implement 1394 and have Claude run it with user observation per OS (1397–1399). Unstoppable-host exit recovery was already verified by the reap reproduction tests in commit abadd1b (`src/tests/task_reap_reproduction_host_test.zig`); that evidence is separate from this terminal run. Never kill a worker thread to report successful reclamation.

Child/audio/window ownership at exit needs fixture 1394; Claude and the user verify it per OS (1397–1399). Unstoppable-host exit recovery was already verified by the reap reproduction tests at abadd1b (src/tests/task_reap_reproduction_host_test.zig); that is separate evidence, not rerun here. A dedicated unending worker prints WORKER-RUNNING after TASK-STATE reports TASK-RUNNING; only then does the runner send q or Ctrl+C. This proves the phase for that fixture, not each finite algorithm. Checksum uses the generated 64 MiB file for mid-file quit.

## AC-25

Run: `zig-out/bin/sigma examples/task-path.fs` (sigma.exe on Windows).

- **Preparation:** start G1, then repeat with T1.

- **Operation:** send `nnn` for G1, `ba` for T1, then `q`.

- **Expected result:** latest generations only; G1 generation 4 has 95 vertices; T1 `a` has 1048576 matches and 1000 stored offsets, `b` has zero.

- **Record:** retained display on failures, generations and cleanup. The runner now exercises maximum G1-open/wall/snake, G2, T1 and I1 terminal fixtures. Retained native display on injected failures needs 1394, and mixed real sources use the AC-18/19/20 fixtures above; Claude and the user verify those per OS in 1397–1399.

The runner now drives maximum-load G1-open/wall/snake, G2, T1 and I1 through the terminal and checks results and q recovery. response.fs checks INPUT-APPLIED for b and q. Retained native display under injected failures needs 1394; real mixed sources need 1395. Claude and the user verify those per OS (1397–1399). These untimed scenarios do not replace the separately authorized ten-minute protocol.

## Completion record

Record passed, failed or unverified per subcase, with evidence. Mark an item unverified and propose how to verify it: give the reason, the tool or fixture needed, the machine, and who runs it (Claude automatically, or the user in person). Register the proposal as a tque task so the item is not left unverified. Timing and capacity decisions follow the separate frozen plan.

## Maximum-load fixtures and the reduced protocol

The 2026-11-24 decision fixes cancellation at 100 attempts per phase, the five
representative memory operations at 100 attempts per phase, and each interaction
case at ten minutes once. This is a reduced protocol, not the prescribed starting
counts in Usage Conditions section 8. Retain this distinction in every result.
The frozen plan specifies when to add trials for an item exceeding 80% of its
limit; do not change the trial count after seeing results without recording the
extension and original run.

Generate the interactive fixtures from the repository root:

```text
python -c "import runpy; from pathlib import Path; runpy.run_path('tests/scripts/acceptance-fixtures.py')['generate'](Path('.'), Path('.work/manual-1382'), 1000000000)"
zig-out/bin/sigma .work/manual-1382/G1-open.fs
zig-out/bin/sigma .work/manual-1382/G1-wall.fs
zig-out/bin/sigma .work/manual-1382/G1-snake.fs
zig-out/bin/sigma .work/manual-1382/G2.fs
zig-out/bin/sigma .work/manual-1382/T1.fs
zig-out/bin/sigma .work/manual-1382/I1.fs
```

Use sigma.exe in PowerShell, and python3 on Linux. The normal manual binary has
both task-trace and task-acceptance disabled. These fixtures print result sizes
and counts while main-side polling and supply continue. Press q to finish; the
request is read between jobs (I1: between refill turns). Check that the shell
returns and owned resources disappear. Do not infer a 60Hz input guarantee from
this loop. G1 open/wall/snake vertex counts are 511, 0, and 32896; the snake goal
is vertex 65280. G2 returns a 256-square mine map with adjacent counts. T1 matches
1048576 bytes, storing at most 1000 entries. I1 uses 64KiB patterned chunks,
expected checksum 8355840, and attempts to keep one execution plus four waiting
jobs supplied. Queue depth is recorded by the automated probe; completion output
alone does not prove that four requests were continuously waiting.

For injected input, run `.work/manual-1382/response.fs`. After INPUT-READY, type
b and q. Confirm INPUT-APPLIED and the visible terminal change. Automatic
write-to-marker time includes transport and is an upper bound on state update;
physical key-to-screen and actual presentation require manual observation.
Keep the existing real-window/paint checks and record absent graphics/audio or
combined resource ownership as unverified. These terminal fixtures do not supply
native graphics or audio acceptance evidence. Implement 1394, then Claude and the user observe native output per OS in 1397–1399.

Before Claude's measurements, compare the actual plan SHA-256 (PowerShell Get-FileHash,
Linux sha256sum) with the literal frozen in the implementation report and stop on a
mismatch. Pass that frozen literal through --plan-sha256; never derive the expected
value from the current file immediately before the run. Also verify the plan's -text attribute. The runner saves the exact plan
copy, fixture hashes, raw logs and JSON. Use the commands in the implementation
report; --mode smoke never evaluates latency. Phase misses and OS sampling gaps
must remain unverified rather than being replaced with inferred successful data. Claude repeats the missing OS collector/phase on the corresponding native machine in 1397–1399, preserving the missing record; 1396 supplies queue/Snapshot observations and 1390–1393 cover single-VM execution.

## macOS execution (1383)

Use [the separate macOS plan](TASK_CONTROL_ACCEPTANCE_PLAN_MACOS.md) and
[the commands in the 1383 report](TASK_CONTROL_IMPL_1383.md). Claude runs native
arm64 in ~/source/zig/ForthSigma using zsh -lc, Python from /opt/homebrew/bin and
bin/sigma. Verify the installed SDK ABI before memory smoke. Run pipe smoke
without a TTY, then perform the foreground terminal checks above separately.
Record each applicable subcase under AC-27 with macOS evidence; absent native
paint/audio/combined fixtures remain unverified. Implement 1394–1396 and have Claude run the macOS subcases in 1399, with the user observing native screen/audio. Use ps for owned process/thread
inspection and check terminal recovery after q and Ctrl+C. The reduced counts
above require the user's separate confirmation for 1383 before measurement.

## Cancellation phase rendezvous (decision B, 2026-11-25)

Use the Windows/Linux plan v4 or macOS plan v2. Repeat only cancellation phases in a new run: 25 generation stages, five native operations with three phases, and queued cancellation, 100 attempts each per OS. Keep previous runs and counts separate.

Only task-acceptance=true builds hold the worker at the selected stage. The host observes hold_stage and invokes the public TASK-CANCEL handler; requested is its entry. Time spent waiting before requested is outside request-to-stop/reclaim. A five-second clock guard releases an unrequested hold; BYE shutdown cancellation also releases it. Timeout, clock failure, mismatched target/request/hold stage and missing task rows are missing samples with reasons. The old 250ms window and first-three-misses cutoff are removed; do not replenish successful samples.

Native before/after use the exact boundary. native_running uses a conservative guarded entry after preflight: request cancellation, then execute the complete bounded native call before the next checkpoint. Record method=guarded-native-entry-full-call; this is not an observed request inside native execution. It covers the full remaining native work for D07's 10ms request-to-stop check. FILL writes 64KiB, MOVE and COMPARE cover two 32KiB regions, SEARCH scans 65,535 a bytes for a one-byte b, and ROLL moves 8,192 cells (64KiB). Only native-roll uses --data-stack-size 16384. These replace the smaller/early-match old inputs without changing counts.

phase_ok requires target, hold_stage and request_stage to match with hold_timeout=false. Queued cancellation requires queued=true and an unstarted worker. Smoke records all phase checks with zero timing endpoints and no speed statistics. Run python tests/scripts/test-acceptance-hold.py against the acceptance binary for the unrequested timeout and BYE guards. Normal builds compile the hold away; compare normal .text before and after. A Windows smoke or cross-build does not establish Linux/macOS runtime acceptance.

## Pseudo-terminal automation (decision B, 2026-11-25)

`tests/scripts/manual-acceptance-tty.py` drives AC-02/05/18/19/20/24/25 through
a shell in ConPTY (Windows) or direct sigma under a POSIX pty supervisor (Linux/macOS), without external
Python packages. It requires Python 3.9 or later, including macOS
`/usr/bin/python3` 3.9.6. Run from the repository root after the normal build above.
No SSH TTY allocation is needed: the tool creates its own pty on the remote host.
Claude runs the Linux and macOS commands on their respective machines over SSH;
Windows results must not be substituted for those runs.

Windows PowerShell:

```powershell
python tests/scripts/manual-acceptance-tty.py --self-test
python tests/scripts/manual-acceptance-tty.py --sigma zig-out/bin/sigma.exe
```

Linux (run after connecting with `ssh HOST`, without `ssh -t`):

```sh
python3 tests/scripts/manual-acceptance-tty.py --sigma zig-out/bin/sigma
```

macOS (Homebrew Python through the login shell; adjust the checkout path):

```sh
zsh -lc 'cd ~/source/zig/ForthSigma && /opt/homebrew/bin/python3 tests/scripts/manual-acceptance-tty.py --sigma bin/sigma'
# The system Python is also supported:
/usr/bin/python3 tests/scripts/manual-acceptance-tty.py --sigma bin/sigma
```

The default evidence directory is
`.work/acceptance/manual-<os>/<UTC timestamp>/`. Each session keeps original
output bytes, readable output, timestamped sent keys and received bytes, process
snapshots, exit codes and terminal recovery records. POSIX also compares the
retained slave's `tcgetattr` values and `stty -a` before/after sigma. Windows
runs a Python helper inside ConPTY to call GetConsoleMode on its own console input/output handles before and after sigma; modes must match. A fresh sigma in the same terminal checks input after exit. The
runner saves binary SHA-256, source commit and working-tree status in
`results.json`. `--output` selects a new directory; existing runs are never
overwritten. `--timeout` and `--paint-timeout` are hang guards only.

With `--native-paint`, the tool also runs `FORTHZ_PAINT_SMOKE=1 zig build runtime-test --summary all`, preserving DISPLAY and the complete log. Without that option, paint/close remains unverified with the recorded reason. Only an explicit OK
for `public paint real native window wait (opt in)` accepts that supplementary
subcase; skip or absent named evidence remains unverified. This log does not
establish physical observation of the window.

Read the per-subcase results as well as the AC-level status. Every result
identifies pseudo-terminal evidence. Missing native/composite/audio/mixed-host
fixtures remain unverified, so successful terminal subcases do not imply a full
AC pass. A dedicated unending worker prints WORKER-RUNNING only after TASK-STATE reports TASK-RUNNING. The tool waits for that marker before q or Ctrl+C; this establishes the running phase for the dedicated fixture, not each finite algorithm. A 64 MiB patterned file in the evidence directory keeps checksum active for concurrent input and quit checks. Maximum-load fixtures and response.fs are also driven through the terminal. Exit status 0 from the tool means no failed
subcase, and can include unverified results; status 1 means a failed subcase.
`--self-test` checks Python 3.9 grammar, portable expectations, contained child/grandchild cleanup and survival of an outside dummy process. Windows also injects job-assignment failure and checks that the shell is never resumed. It runs real processes on the current OS, without
claiming that the POSIX implementation was executed on Windows. No latency or
capacity acceptance is performed.

With `--native-paint`, for explicit per-test paint evidence, the runner additionally stages the same
artifact with `zig build runtime-check --summary all` and runs
`zig-out/runtime-tests/<arch>-<os>/test` (`test.exe` on Windows) without the build
protocol. Both commands and their output are kept in `native-paint.log`, because
the normal build protocol may report only aggregate passed/skipped counts.

## POSIX startup, terminal restoration and missing observations

The POSIX runner no longer uses an interactive shell. A dedicated supervisor calls `setsid`, acquires the pty controlling terminal, and starts sigma directly in its own process group. The supervisor remains alive and unreaped until cleanup. Short helpers run echo and `stty -a` on the same pty after sigma exits; a fresh sigma verifies subsequent input. `stty` must exit successfully and produce a speed report; raw output is retained. Only the known `sh: child setpgid ... Operation not permitted` diagnostic is removed, at any position; apart from PENDIN as explained below, all other report lines and separate `tcgetattr` values remain part of restoration checks.

Linux sets `prctl(PR_SET_CHILD_SUBREAPER, 1)` (36) in the supervisor before starting helpers or sigma, and verifies the supervisor's reply at startup. After sigma exits, adopted exited children are reaped; the descendant tree must contain only the supervisor. Surviving descendants fail natural recovery, including those outside the original session/group. Cleanup repeatedly enumerates direct children inside the supervisor, validates each with `waitid(P_PID, ..., WEXITED | WNOHANG | WNOWAIT)`, sends SIGKILL, then reaps and repeats for newly adopted descendants. The same thread validates, signals and reaps, without releasing the validated direct child's identity before signalling. Grandchild snapshots never authorize signals. The final tree must contain only the supervisor; forced cleanup is not natural reclamation. Direct children are also read from the supervisor's `/proc/self/task/<pid>/children`, which must be empty; system-wide ppid sampling during reparenting alone cannot establish this endpoint. Finally, even on query failure, the parent kills the anchored group before reaping its leader. Linux retains a pidfd when available. This assumes descendants do not deliberately evade supervision using privileges or another subreaper; it is not hostile-process containment.

macOS has no subreaper. A dedicated collector recursively samples `proc_listchildpids` from `/usr/lib/libproc.dylib`, with a requested 20 ms interval. `child-polling.json` retains actual start/end timestamps and PID sets; collection and scheduling add to the interval. The API returns a PID count, not bytes; full buffers are retried at larger capacity. Errors make the case unverified. Sampled PIDs never authorize signals; cleanup targets only the anchored group. Fork/exit/reparenting between samples, escaped descendants and PID reuse prevent proof of lifetime ownership/reclamation, which remains unverified. Claude should collect native fork/exit events on the Mac (1399), tracing from before sigma starts through exit with an authorized Instruments/System Trace or DTrace setup, preserving attachment errors and dropped-event reports. Request user assistance if privileges are needed; unavailable or incomplete tracing remains unverified. Escaped survivors require operator investigation, not guessed-PID cleanup.

The separate `reproduce-tty-shell-ready.py` remains an interactive-shell diagnostic for the older startup problem. It is not the runner's startup mechanism.

Windows runs a Python helper inside ConPTY and calls GetConsoleMode on the helper's own console input/output handles. Successful before/after values must match; the parent's pipe handles are not used. Physical cursor/screen restoration requires fixture 1394, recorded by Claude with user observation per native OS (1397–1399).

For missing native screen/audio/composite fixtures throughout this document, implement 1394–1396, then Claude runs them per native OS (1397–1399), with the user observing screen/audio; macOS gaps are covered by 1399. For an OS sampling gap or failed process/thread collector, Claude reruns the collector on that native OS (1397–1399), preserving the command, error and available native process tools. Missing rows cannot prove cleanup. Single-VM execution is covered by 1390–1393. Existing task numbers are references only; this continuation does not modify tque.


## Process ownership and collection failures

Windows creates a private Job Object with `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE`, without breakaway flags. `PROC_THREAD_ATTRIBUTE_JOB_LIST` assigns the shell atomically during `CreateProcessW(CREATE_SUSPENDED)`; explicit `AssignProcessToJobObject` must also succeed before `ResumeThread`. Unsupported job-list attributes or assignment failure abort startup. Cleanup only terminates/closes this job, never opens a PID for termination. JobObjectBasicProcessIdList supplies current membership, including children created after launch; any workload left at natural exit fails the case. Forced workload cleanup cannot count as successful reclamation. The old image-name allowlist was removed because job membership, rather than names or parent-PID snapshots, defines ownership.

`src/host_process_native.c` starts children suspended with a nested job and `CREATE_NEW_PROCESS_GROUP`; it does not request `CREATE_BREAKAWAY_FROM_JOB`. Its inner job permits breakaway, but the runner's outer job does not. Children remain constrained by the outer job. Process/thread snapshots are observational metadata only, never termination authority.

Collector errors and missing rows are recorded in `processes.json`/`results.json` and make the affected subcase unverified. Linux `/proc` ENOENT is ignored only when a separate existence probe confirms ESRCH; if disappearance cannot be confirmed, retain missing evidence. Repeat failed collectors on the native OS, preserving errors and exit status (1397–1399). If AC-20 checksum exits before q or continuous overlap, prepare a workload that runs until quit on each OS, observe progress in both ptys, and send q while it is still running (1395, 1397–1399). This check is separate from same-process fairness.

## PENDIN and residual input (2026-11-25)

Restoration ignores only the platform's `termios.PENDIN` bit in lflag; raw states remain recorded and other fields still matter. `stty -a` replaces only the whole `pendin`/`-pendin` token. Apple's [tty source](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/kern/tty.c) maintains PENDIN during canonical transitions/input reprocessing. Linux [termios documentation](https://github.com/mkerrisk/man-pages/blob/master/man3/termios.3) marks PENDIN unsupported; use Linux's own constant rather than the macOS bit. Exclusion does not establish input consumption.

Immediately after the supervisor observes exit (20 ms polling, subject to scheduling), before the exit marker and helpers, it saves termios and slave FIONREAD. It temporarily clears ICANON/ECHO without flushing, measures FIONREAD again, reads residual bytes nonblocking, and restores attrs. This exposes incomplete canonical input where possible. Observation consumes bytes and temporarily changes modes; subsequent input checks therefore follow a diagnostic intervention. Restoration uses the attrs saved before intervention. Collection failure is unverified.

Each recovery and case's `residual_input_observations` records source, sent keys, canonical/noncanonical counts, residual hex/text and time; events also retain it. Leftovers are printed with the scenario name, informational rather than a failure. Compare q/b/n/Ctrl+C and other sends with those bytes. An empty queue does not prove sigma read them: the terminal may process signals or discard input. Claude should correlate EKEY/input markers and native read traces on Linux/Mac (1397/1399) to identify the reader or queued key. Do not infer the cause from PENDIN alone.

Supporting source inspection: task-path/search/checksum and their workers, task-map-worker, task-console, check-task-console and generated running/acceptance fixtures use workers, terminal/file operations and contain no SYSTEM or OPEN-PIPE calls. The examples include the named worker/common files. This supports intended child-free workloads, without proving the absence of child creation in runtime/native implementations or replacing macOS lifetime tracing. Recheck actual sources per run; `source-evidence.json` retains SHA-256 hashes of workloads and related sources.

Claude reruns self-tests and all scenarios on Linux and Mac, retaining an outside process started before the test and checking the same PID survives. Linux self-tests add setsid/setpgid descendants and require only the supervisor after cleanup. Portable Windows tests also cover PENDIN-only differences, other flags, tree traversal and rejection of non-child signalling; they do not execute POSIX APIs. Preserve old runs and use new output paths. Missing evidence retains its verification method above. Existing task references do not authorize tque changes in this continuation.


## 1394 native paint and BYE with live audio/window/tasks

Use a local display session (PowerShell on Windows; X11-enabled build on Linux). A window briefly receives focus. For untimed checks, retain SIGMA_ACCEPTANCE_SMOKE=1 (default).

```text
zig build -Dtask-acceptance=true --prefix .work/1394/acceptance
python tests/scripts/manual-acceptance-tty.py --native-paint --cases native --sigma .work/1394/acceptance/bin/sigma.exe
```

Omit .exe on macOS/Linux. To operate directly, run examples/task-native-path.fs, task-native-search.fs, and task-native-bye.fs. G1 uses n; T1 uses a/b; f injects worker division-by-zero failure; q exits. Compare Generation (accepted result) and Requested in the window against NATIVE-DRAW lines. Rapid replacements must never draw an older generation; failure must retain the preceding result.

The BYE fixture holds a 440Hz tone, window, Snapshot, and RUNNING worker until q invokes BYE. Record audible tone/start/stop and window closure as human observations. Verify exit code, terminal restoration, and owned process/thread reclamation from evidence. Missing visual, audible, or macOS lifetime observations remain unverified; Claude verifies on each native OS.

Only Claude performs timing after the user's explicit time-measurement confirmation. Preserve plan v7 / macOS v5 counts. Import PAINTTRACE through the runner's paint group. D07 here ends at backend drawing completion; physical panel emission is excluded. Terminal writer completion is distinct from emulator rendering. See the plan's 1394 section for endpoints, fixed 60Hz deadlines, baseline comparison, missing data, and import commands. Smoke imports compute no elapsed statistics.
