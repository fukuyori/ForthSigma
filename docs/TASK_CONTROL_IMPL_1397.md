# tque 1397: Windows real-machine check of the added fixtures

2026-11-26, Windows 11 Pro 26300, AMD Ryzen 7 7700, power plan Balanced, Zig 0.17.1, main `333f8af` (the work tree holds the uncommitted 1402 and 1403 changes; product src/ and build.zig are unchanged). Timing was run on レモン's instruction (2026-11-26, "time measurement may start any time"). Other applications were not stopped. See also the [Japanese version](TASK_CONTROL_IMPL_1397.ja.md).

## 1. Queue residence and Snapshot (1396)

`run-acceptance.py --mode measure --only workloads snapshot`, plan v7 (SHA-256 `9d1546a7…b467b`), two independent runs. Evidence: `.work/acceptance/20261125T222653Z-9e889cf3` (run1) and `20261125T232847Z-738a482e` (run2).

| Metric | run1 max | run2 max | Guideline |
|---|---:|---:|---:|
| G1 enqueued→acquired (3 scenes) | 0.121 ms | 0.033 ms | 50 ms |
| G2 enqueued→acquired | 0.018 ms | 0.076 ms | 100 ms |
| T1 enqueued→acquired | 0.060 ms | 0.029 ms | 100 ms |
| I1 enqueued→acquired | 25.7 ms | 23.2 ms | 200 ms |
| Snapshot capture (snapshot_main_ns, 300 times) | 13.29 ms | 13.15 ms | 50 ms (D07: 100 ms) |

Residence and Snapshot are within the guidelines in both runs. In addition, I1 publish→reclaim exceeded 100 ms (run1: 5 of 48,046, max 115.9 ms; run2: 1 of 48,021, max 102.1 ms). I1 `queue_waiting` reached 4 (limit 4) and the Snapshot size was 3,620,330 bytes (over 80% of 4 MiB); both call for extra trials under the 80% rule.

## 2. Composite wait and fairness (1395, AC-18, 19, 20)

`manual-acceptance-tty.py --cases mixed` (acceptance build `.work/1397/acceptance`). AC-18 (composite wait on real sources) and AC-19/20 (T1, I1, file reads and terminal I/O progress in every interval of one process) all passed. Evidence: `.work/1397/mixed/results.json`. There is no speed guideline.

## 3. Native window and audio (1394, AC-02, 05, 25, D07)

With timing recorded (`SIGMA_ACCEPTANCE_SMOKE=0`), a load run (`.work/1397/native-load`) and a baseline run (`--native-baseline`, `.work/1397/native-baseline`) were taken and imported under plan v7 (path `.work/acceptance/20261126T011354Z-a741d948`, search `20261126T011355Z-69290fc2`).

| Metric | Path (G1) | Search (T1) | Guideline |
|---|---:|---:|---:|
| Input→screen (backend drawing completion) max | 13.15 ms (6) | 15.32 ms (6) | 33.34 ms |
| Input→terminal (writer completion) max | 14.18 ms | 15.87 ms | 50 ms |
| 60 Hz frame deadline misses (load) | 7 of 120 | 1 of 20 | compare with baseline |
| Same (baseline) | 0 of 31 | 0 of 5 | — |

Input→screen and input→terminal are within the guidelines. The frame-deadline misses cannot be compared under the plan's rule because the baseline and load runs have different frame counts, so they stay **unverified**. Method: add a runner procedure that takes the baseline with the same frame count and input sequence (tque 1405). The endpoints are backend drawing completion and writer completion; OS, compositor and panel emission are not included.

Visual and audible check (レモン, 2026-11-26): the automated run was too fast to read, so each fixture was started in its own console and レモン pressed the keys.

- G1 (`task-native-path.fs`): n raises Requested and Generation catches up. Generation never decreases under rapid requests. After f, Generation and the picture stay as before. No problem.
- T1 (`task-native-search.fs`): the same with a and b. No problem.
- BYE (`task-native-bye.fs`): レモン answered "OK". Claude recorded this as: the tone sounded, stopped on q, and the window closed. Claude confirmed from the process list that Sigma (PID 37544) and conhost (PID 31448) exited.

The acceptance build prints an `ACCEPTANCE` line on every management turn, so when started by hand the BYE prompt line scrolled out of view. tque 1404 defines the executable and procedure for hand checks.

## 4. Verdict

- Residence, Snapshot, input→screen and input→terminal: within the guidelines on Windows.
- AC-18, 19, 20: passed. AC-25 (G1/T1 window) and AC-05 (BYE holding audio and window): confirmed by sight and hearing.
- Unverified: additional frame-deadline misses (1405). The I1 publish→reclaim excess over 100 ms is recorded in the acceptance summary together with its existing handling.
