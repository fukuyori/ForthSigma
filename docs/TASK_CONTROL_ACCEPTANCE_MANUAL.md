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
as unverified, never passed. Do not transfer Windows evidence to Linux.
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

## AC-05

Run: `zig-out/bin/sigma tests/scripts/check-task-console.fs` (sigma.exe on Windows).

- **Preparation:** create `.work` and start the integration fixture.

- **Operation:** at `active` press `r`; at `replaced` press `c`; at `bye-active` press `b`.

- **Expected result:** frame=r/c/b, cancelled and released, file I/O progress while computation runs, then exit.

- **Record:** output, scratch file cleanup, process/thread ownership. Multiple simultaneous tasks, audio and native display ownership still require a combined fixture; mark these unverified.

## AC-18

Run: `zig-out/bin/sigma examples/task-path.fs` (sigma.exe on Windows).

- **Preparation:** note input mode and available native display backend.

- **Operation:** press `n`, then `q`; repeat with search and checksum.

- **Expected result:** input, task terminal state, file data and output progress independently.

- **Record:** whether Enter is required and which resources were real. Existing examples do not connect all sources to one composite wait. Real I/O availability, native paint/close and simultaneous-source acceptance require a dedicated fixture; do not infer a pass from this example or synthetic tests.

For supplementary real-window evidence, run the opt-in test on an available backend. Check that `public paint real native window wait (opt in)` is OK rather than skipped. Observe the 128 by 128 test window opening and closing. This alone does not accept all composite sources together.

Windows PowerShell:

```powershell
$previousAcceptancePaint = $env:FORTHZ_PAINT_SMOKE
$env:FORTHZ_PAINT_SMOKE = '1'
try { zig build runtime-test --summary all } finally { $env:FORTHZ_PAINT_SMOKE = $previousAcceptancePaint }
```

Linux:

```sh
FORTHZ_PAINT_SMOKE=1 zig build runtime-test --summary all
```

## AC-20

Run: `zig-out/bin/sigma examples/task-search.fs` (sigma.exe on Windows).

- **Preparation:** start T1 and a separate checksum session.

- **Operation:** alternate `a`/`b` repeatedly, then `q`, while checking checksum output.

- **Expected result:** input, search counts, display and file results all progress; no backward generation.

- **Record:** every stream progress and any stuck output. Separate sessions do not prove fairness in one host; the mixed-source host fixture is pending.

## AC-24

Run: `zig-out/bin/sigma examples/task-path.fs` (sigma.exe on Windows).

- **Preparation:** note PID/threads/children using Get-Process on Windows or ps on Linux.

- **Operation:** quit with `q` during work; repeat in a new process with Ctrl+C; repeat search and checksum.

- **Expected result:** owned task resources end and terminal recovers; distinguish task completion from output drain and process exit.

- **Record:** before/after ownership and terminal behavior. Child process/audio/display and isolated unstoppable-host combined fixtures are pending. Never kill a worker thread to report successful reclamation.

## AC-25

Run: `zig-out/bin/sigma examples/task-path.fs` (sigma.exe on Windows).

- **Preparation:** start G1, then repeat with T1.

- **Operation:** send `nnn` for G1, `ba` for T1, then `q`.

- **Expected result:** latest generations only; G1 generation 4 has 95 vertices; T1 `a` has 1048576 matches and 1000 stored offsets, `b` has zero.

- **Record:** retained display on failures, generations and cleanup. G2 map generation and maximum-load/mixed-I/O fixtures are pending; mark those subcases unverified.

## Completion record

Record passed, failed or unverified per subcase, with evidence and missing fixtures. Timing and capacity decisions follow the separate frozen plan.

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
native graphics or audio acceptance evidence.

Before Claude's measurements, compare the actual plan SHA-256 (PowerShell Get-FileHash,
Linux sha256sum) with the literal frozen in the implementation report and stop on a
mismatch. Pass that frozen literal through --plan-sha256; never derive the expected
value from the current file immediately before the run. Also verify the plan's -text attribute. The runner saves the exact plan
copy, fixture hashes, raw logs and JSON. Use the commands in the implementation
report; --mode smoke never evaluates latency. Phase misses and OS sampling gaps
must remain unverified rather than being replaced with inferred successful data.

## macOS execution (1383)

Use [the separate macOS plan](TASK_CONTROL_ACCEPTANCE_PLAN_MACOS.md) and
[the commands in the 1383 report](TASK_CONTROL_IMPL_1383.md). Claude runs native
arm64 in ~/source/zig/ForthSigma using zsh -lc, Python from /opt/homebrew/bin and
bin/sigma. Verify the installed SDK ABI before memory smoke. Run pipe smoke
without a TTY, then perform the foreground terminal checks above separately.
Record each applicable subcase under AC-27 with macOS evidence; absent native
paint/audio/combined fixtures remain unverified. Use ps for owned process/thread
inspection and check terminal recovery after q and Ctrl+C. The reduced counts
above require the user's separate confirmation for 1383 before measurement.

## Cancellation phase rendezvous (decision B, 2026-11-25)

Use the Windows/Linux plan v4 or macOS plan v2. Repeat only cancellation phases in a new run: 25 generation stages, five native operations with three phases, and queued cancellation, 100 attempts each per OS. Keep previous runs and counts separate.

Only task-acceptance=true builds hold the worker at the selected stage. The host observes hold_stage and invokes the public TASK-CANCEL handler; requested is its entry. Time spent waiting before requested is outside request-to-stop/reclaim. A five-second clock guard releases an unrequested hold; BYE shutdown cancellation also releases it. Timeout, clock failure, mismatched target/request/hold stage and missing task rows are missing samples with reasons. The old 250ms window and first-three-misses cutoff are removed; do not replenish successful samples.

Native before/after use the exact boundary. native_running uses a conservative guarded entry after preflight: request cancellation, then execute the complete bounded native call before the next checkpoint. Record method=guarded-native-entry-full-call; this is not an observed request inside native execution. It covers the full remaining native work for D07's 10ms request-to-stop check. FILL writes 64KiB, MOVE and COMPARE cover two 32KiB regions, SEARCH scans 65,535 a bytes for a one-byte b, and ROLL moves 8,192 cells (64KiB). Only native-roll uses --data-stack-size 16384. These replace the smaller/early-match old inputs without changing counts.

phase_ok requires target, hold_stage and request_stage to match with hold_timeout=false. Queued cancellation requires queued=true and an unstarted worker. Smoke records all phase checks with zero timing endpoints and no speed statistics. Run python tests/scripts/test-acceptance-hold.py against the acceptance binary for the unrequested timeout and BYE guards. Normal builds compile the hold away; compare normal .text before and after. A Windows smoke or cross-build does not establish Linux/macOS runtime acceptance.
