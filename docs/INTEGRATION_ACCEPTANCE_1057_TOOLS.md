# 1057 integrated acceptance fixtures and tools (1411)

[日本語](INTEGRATION_ACCEPTANCE_1057_TOOLS.ja.md)

2026-11-26, Roku. Target: ForthSigma / Zig 0.17.1. The contract is the [plan](INTEGRATION_ACCEPTANCE_PLAN_1057.md), sections 2–4, 7, 8, 10, 11 and its final user decisions. This describes tools, not completion of three-OS acceptance. Preserve B for configurations/measurement/restoration and A for D1–D5.

## 1. Windows invocation

Use PowerShell at the repository root.

```powershell
$env:ZIG_GLOBAL_CACHE_DIR="$PWD/.work/codex-cache/global"
$env:ZIG_LOCAL_CACHE_DIR="$PWD/.work/codex-cache/local"
$env:SIGMA_ACCEPTANCE_SMOKE='1'
python tests/scripts/integration-acceptance.py --smoke --configs M0 M1 M2 M4 M7 M9
```

Each configuration uses `zig build -Doptimize=ReleaseFast -Dtask-acceptance=true --prefix <run>/<configuration>/build` and its exclusion flags. To accept a build, use, for example, `--configs M0 --binary zig-out/bin/sigma.exe`. The operator must establish its configuration and acceptance flags: the adapter records SHA-256 and declared configuration, without inferring build options from the binary.

Every invocation creates `.work/integration-acceptance/<date>-<random>/`, preserving previous evidence. `--output` selects the parent. Windows may open. Ordinary smoke is silent. `--frames` defaults to 240 for smoke and 1,200 for functional runs. Native graphics uses a frame-count termination budget; Tk, terminal and GRAPHICS-excluded configurations use budget ×16,667 µs as an exit deadline (`IA-BUDGET deadline reached`), independent of terminal image-output speed. This is not a response threshold. Use `--functional --frames 240` for a shorter functional run. `--functional` runs functional checks without timing verdicts. Claude performs full runs of all configurations.

## 2. Saving and startup

`examples/integration/` contains definitions and persistent-data initialization only. `core.fs` defines the entry, staged acquisition and cleanup; `extension.fs` tasks/input; `requests.fs` the reused path/search request and rendering definitions; `audio.fs` PCM; `graphics.fs` rendering; `pipe.fs` child/pipes; `loop.fs` composite waiting, resource comparison and runtime reset before resaving. `measurement.fs` prepares render replay for measurement modes.

The adapter concatenates configuration-appropriate definitions into `definitions.fs`. It reuses workers from `task-path-worker.fs` / `task-search-worker.fs`, management from `task-console.fs` and the rendering header from `task-native-common.fs`. It does not load the execution tails of `task-native-path/search/bye.fs`. No INCLUDED is introduced in FILES-excluded fixtures. Host command-line source loading is independent of FILES vocabulary availability.

The saving process loads `definitions.fs`, then executes a separate `-e` argument: `' IA-ENTRY APP-ENTRY! SAVESYS <app> BYE`. Saving acquires no input/window/PCM/Snapshot/task/child resources. A new process starts the saved executable, runs the entry once, reads current arguments and acquires resources in order. `IA-FRESH` checks ownership variables and native-window absence before acquisition. It does not assert that old integer IDs must always be invalid in another process.

| Mode / keys | Behavior |
|---|---|
| `normal` / `path`, n, f | Replace path requests, fail a worker, retain the last valid result |
| `search`, a/b, f | Replace search requests, retain the last valid result after failure, recover |
| `fault-input/window/pcm/task/pipe` | Throw -4100 immediately after the selected acquisition; release acquired resources, retaining the original failure |
| `cancel`, c, n | Cancel dedicated running and waiting tasks; separately record request, terminal state and RELEASE, then resubmit |
| `normal`, q / end of budget | Explicit cleanup and normal entry return, status 0 |
| `bye` / `quit` / `throw` | Prepare a running task immediately before exit; leave PCM/window/Snapshot/child/pipes live for BYE / QUIT / -4123 THROW; expect status 0 / 1 / 1 |
| `append` | LOAD-DICTIONARY with active resources; compare APP registration, ownership IDs, terminal request and shown-frame count; do not dispatch the source entry |
| `resave` | Release legally, reset runtime variables, resave; adapter starts it in a new process |
| `measure-path/search` | Fixed frame budget, PAINTTRACE, PCM interval endpoints and supply records; use the dedicated invocations below |
| `audible` | Play the known PS-DEMO-SETUP synthesis for approximately 0.25 seconds each second; q stops |

q requests normal termination. The loop catches Ctrl+C's -28, records it and continues retaining resources. f uses division by zero, consistent with the existing worker inspection rules; it does not insert a denied worker THROW to bypass entry validation.

## 3. Configurations and waits

| Configuration | Resources actually used |
|---|---|
| M0 | Input/terminal, window, PCM, Snapshot/tasks, child and stdout/stderr pipes |
| M1 | Input/terminal, PCM, Snapshot/tasks, child/pipes; no window |
| M2 | Input/terminal, window, Snapshot/tasks, child/pipes; no PCM |
| M3 | Window and PCM; no public EXTENSION/task/terminal/pipe words |
| M4 | Input/terminal, Snapshot/tasks, child/pipes |
| M5 | Window; no public tasks |
| M6 | PCM; no public tasks |
| M7 | Saved entry, arguments and persistent data; no later resources |
| M8 / M9 | Input/terminal, window, PCM, Snapshot/tasks; no FILES/pipes; M9 also excludes DEBUG |
| M10 | No saved app; check absence of SAVESYS / APP-ENTRY! at the image boundary |
| M11 | Linux only, M2-like with DEBUG/X11 excluded; default terminal, optionally `--backend tk` |

`--backend native/tk/terminal` selects the actual rendering words. Never reuse native frame numbers for Tk. Tk/terminal verify rejection of unsupported native frame waits and progress through deadlines/input. Missing hardware is not a vocabulary exclusion.

Explicit Tk cleanup uses `2 GFX-TK-WINDOW-CLOSE DROP`, supplying the action and consuming the returned close count. For Tk/terminal with EXTENSION, IA-07 automatically joins the capability-rejection record to normal deadline expiry, empty-argument q termination, path/search result updates followed by normal exit, and ownership recovery. Native and graphics configurations without EXTENSION retain an unverified capability observation.

With EXTENSION, one loop registers input, tasks, clock and, where available, stdout/stderr and native paint in TASK-WAIT-MANY. Rebuild the target list each turn and do not reuse released/terminal IDs. Events carry sequence, tag and reason. Pipes are drained asynchronously. Normal cleanup sends stdin EOF to the controlled child, lets it wait for its grandchild, and then FREEs it. Fault/exit reclamation also exercises host ownership.

PCM is 48,000 Hz mono s16LE, capacity 4,096, in 512-frame/1,024-byte blocks. Supply until capacity is exhausted; retain unsent data after partial/zero writes and advance only by accepted frames. PCM-WAIT uses need=1 / timeout=1,000 ms. No fixed supply sleep. Supply is interleaved with input/I/O/render/task turns. Read the starting underrun count after initial filling and observed consumption; read the ending count immediately after the loop, before STOP/close or child cleanup. Record supply timestamps, accepted counts and cumulative counts.

## 4. Verdicts and evidence

`manifest.json` records HEAD, invocation, OS/Python, both plan SHA-256 values and fixture/tool fingerprints. `working-tree.stdout` retains the dirty diff. Each configuration's `binary.json` records base/saved executable SHA-256, settings and definition hash. Build/save argv, status, stdout and stderr are recorded separately.

Saved applications launch through the existing `manual-acceptance-tty.py` Terminal.launch_argv. Windows uses ConPTY and a non-breakaway Job; POSIX uses pty and the existing supervisor. Reuse process/thread snapshots at launch/active/exit, owned child/grandchild tracking, terminal before/after comparison and shell recovery. Do not implement a second Job/supervisor. ConPTY/pty merges stdout/stderr: retain original bytes in output.bin and events.jsonl rather than claiming separation. output.txt, result.json and processes.json correspond to these records. Forced workload cleanup cannot pass. Missing collection is unverified. macOS polling alone cannot prove lifetimes of short-lived/escaping descendants.

ledger.json contains IA × OS × configuration × backend rows with pass/fail/unverified/N/A, run ID, tested/recording revisions, evidence, reason, devices/routes, human reply and next procedure. Exit status alone cannot pass a condition. IA-01/02/03/05/08/09/10/11/12/13 join required endpoints to terminal/ownership checks. IA-04 reconciles readiness-notification sequences and processed/pending/discarded counts, and separately reconciles pipe bytes/task results. Discards identify entry exit as their reason. automated_result records the automatic verdict; the overall condition stays unverified pending human close observation. IA-06 never passes from smoke. IA-07 separates progress without a window from backend capability observations. IA-14–18 require semantic translation review, 999/1001 decision reconciliation, and three-OS/manual aggregation; successful automatic startup cannot pass them.

Full restoration for IA-11 uses Zig tests, not a new product word. `1057 bound restore ...` in src/tests/task_reap_test.zig holds PCM/tasks/window simultaneously and checks **task Busy before PCM -528**, unchanged dictionary/APP/resources on rejection, success after PCM-CLOSE/task quiescence, and window retention/image release. Its window host is substituted; this is not physical paint/restore concurrency evidence. `1057 D2 ...` in src/main.zig restores a target with a real OS child (Windows sort, POSIX cat) and live pipes; checks child survival, identical pipe IDs, transfers before/after restore, normal exit and reclamation. Core direct calls are outside the task Busy guarantee; do not full-restore inside an active EXEC entry.

## 5. IA-06 format checks and later measurements

```powershell
# Smoke load followed by baseline, for each fixture. Substitute the emitted run path.
python tests/scripts/integration-acceptance.py --smoke --measure path
python tests/scripts/integration-acceptance.py --smoke --measure path --baseline --load-schedule <load-run>/M0/results.json
# Repeat these two commands for search.
```

Reuse 1405's Runner.native: load inputs follow result progress, baseline inputs replay matching frame numbers. Baseline uses the **identical saved executable** from the load run; only arguments suppress additional task submissions. Both sides prepare identical deterministic worker results before acquiring resources. Load results are byte-compared with that preparation; baseline replays the load's per-frame result and requested generations for rendering. Baseline's logical task generation stays at 1; only rendering replays. Compare render_schedule exactly. The 8,192-byte/result bound applies to this fixed fixture, not arbitrary path/search inputs.

paint.log extracts PAINTTRACE JSON from terminal records. ConPTY cursor movement may place records on the same line; extract JSON delimiters while retaining raw bytes. Logs can be imported by run-acceptance.py paint (`--mode smoke --only paint --paint-log ... --paint-baseline-log ...`). PCM counters/accepted frames are in results.json; all supply observations are in terminal logs. Smoke calculates no timing differences, thresholds or distributions.

Claude performs formal measurement only after Lemon explicitly confirms. Unset SIGMA_ACCEPTANCE_SMOKE and replace --smoke with `--confirmed <confirmation reference> --plan-sha256 <exact Japanese plan SHA-256>`. Formal --measure path/search fixes 1,200 frames. Wrong plans/hashes are rejected. For each fixture, run two independent new load→baseline pairs; the fixed section-8 80% rule adds two more when triggered, retaining all four pairs. Each adapter invocation is one run; the operator manages pair counts/extensions under the plan.

Formal review reconciles each run's underrun delta, accepted frames/supply, identical executable/configuration/backend, rendering replay, individual request→complete and input→paint/writer endpoints. Missing data or unequal supply/rendering remains unverified, never replaced with favorable samples. Apply section 8's 33.34 ms paint, 50 ms writer, 16,666,667 ns individual-frame threshold, zero additional misses, zero underrun delta per run, and the 80% extension. Exclude only the first frame from deadline statistics, retaining it raw. Physical display/key/audio observations remain separate.

## 6. Manual units and remaining verification

For one unit, use, for example, `python tests/scripts/integration-acceptance.py --manual MNL-01a --configs M0`. MNL-01b's a/b and f use separate MNL-01b / MNL-01b-f invocations. MNL-03a/03b are also separate. Guidance identifies absolute executable, OS/backend/audio route, target window, action, expectations and q to stop. Relay terminal keys one line at a time in the adapter console; entering the literal Ctrl+C sends the control character. Use the target window directly for its keys/close. After done, record the observation in human-reply.json with its run-linked evidence path and raw hash. Do not fabricate numerical or human observations.

Windows smoke, Zig tests and document checks validate implementation. Linux/macOS execution, full runs of all configurations, MNL-01a–05, actual paint/restore concurrency, physical presentation, listening, formal timing and pair-count/supply equivalence review remain separate. Preserve R6's exclusion of real DwmFlush-unavailable environments. Do not mutate Git/tque.

On POSIX the adapter supplies `TERM=xterm-256color` for its owned ANSI-decoded PTY when the inherited TERM is missing, empty or `dumb`; manifest.json records inherited/effective values. Inheriting `dumb` makes `TERM-MODE!` return -21 even for a saved application. Provider pipe totals count LF on POSIX (6 bytes per stream) and CRLF on Windows (7), before PTY translation. This does not establish physical terminal presentation.
