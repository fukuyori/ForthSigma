# tque 1399: macOS real-machine check of the added fixtures

2026-11-26, MacBook Air (Apple M5, macOS 27.2.1, arm64, AC power), Zig 0.17.1. Timing was run on レモン's instruction (2026-11-26, "time measurement may start any time"). See also the [Japanese version](TASK_CONTROL_IMPL_1399.ja.md).

## 1. Queue residence and Snapshot (1396)

`run-acceptance.py --mode measure --only workloads snapshot`, plan macOS v5, two independent runs. Evidence on the Mac: `.work/acceptance/20261125T224425Z-06333bfd` and `20261125T234525Z-bf6ec10a`.

| Metric | run1 max | run2 max | Guideline |
|---|---:|---:|---:|
| G1 enqueued→acquired (3 scenes) | 0.050 ms | 0.118 ms | 50 ms |
| G2 enqueued→acquired | 0.059 ms | 0.044 ms | 100 ms |
| T1 enqueued→acquired | 0.066 ms | 0.071 ms | 100 ms |
| I1 enqueued→acquired | 30.4 ms | 29.2 ms | 200 ms |
| Snapshot capture (300 times) | 33.4 ms | 31.7 ms | 50 ms |

All within the guidelines. I1 `queue_waiting` reached 4 (limit 4) and the Snapshot size was 3,620,338 bytes; both call for extra trials under the 80% rule.

## 2. Composite wait, fairness, cleanup and descendant tracing

`--cases mixed` (AC-18, 19, 20) ran successfully (`.work/1399/mixed` and `mixed2`). `--self-test` passed, and a `sleep` started outside the test was still alive afterwards (`.work/1399/self-test`).

Intermittent polling on macOS cannot prove descendant lifetimes. By レモン's decision (option A), レモン ran `sudo eslogger fork exec exit` in a Mac terminal while Claude ran AC-18, 19, 20 and the native fixtures (load and baseline). The log `.work/1399/eslogger.jsonl` (2,273 events, 06:23:46 to 06:26:35 UTC) covers the run (06:24:08 to 06:25:51 UTC). It was analysed with [eslogger-process-tree.py](../tests/scripts/eslogger-process-tree.py).

- All 16 acceptance-build Sigma processes exited.
- Sigma forked 5 children (one per native fixture: load G1, T1, BYE; baseline G1, T1); all exited, and none forked grandchildren.
- Processes without an exit: 0.

## 3. Native window (1394, AC-02, 05, 25, D07)

In the first pair (`.work/1399/native-load` and `native-baseline`, plan macOS v6), T1 input→screen reached 40.9 ms; in 2 of 3 runs the first input after start exceeded the 33.34 ms guideline. By レモン's decision (option 1) the cause was investigated first: TASK-SUBMIT repeated the static entry inspection on every submit. It was fixed in [1408](TASK_CONTROL_IMPL_1408.md).

After the fix (`.work/1408/native-load1` to `3` and `native-baseline1`; imports `.work/acceptance/20261126T070828Z-b42c39db` (path) and `20261126T070828Z-39b23625` (search)):

| Metric | G1 | T1 | Guideline / verdict |
|---|---:|---:|---|
| Frames and inputs | 1,200 and 6 (match baseline) | 1,200 and 6 (match baseline) | comparison condition met |
| Per-frame deadline misses (load / baseline) | 0 / 0 | 0 / 1 | pass |
| Additional misses from tasks | 0 | 0 | pass |
| Input→screen max (3 runs) | 16.7 ms | 16.7 ms | 33.34 ms, pass |
| Input→terminal max | 16.7 ms | 16.7 ms | 50 ms, pass |

Visual and audible check (レモン, 2026-11-26): the normal-build fixtures (G1, T1, BYE) were run by hand one at a time in a Mac terminal, and レモン answered "3つOK". Claude recorded this as: Generation did not decrease and the previous result stayed after f on G1 and T1; on BYE the tone sounded, stopped on q, and the window closed.

## 4. Verdict

- Residence, Snapshot, input→screen, input→terminal and per-frame deadlines: within the guidelines on macOS, with no additional misses from tasks.
- AC-18, 19, 20 and descendant reclamation for AC-05 and 25: every process exit confirmed with eslogger.
- AC-25 and AC-05 window and audio: confirmed by sight and hearing.
