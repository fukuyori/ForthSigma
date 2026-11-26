# tque 1398: Linux real-machine check of the added fixtures

2026-11-26, Linux machine (Ubuntu, Linux 7.0.0-44-generic, Intel Core i7-8700K, GNOME/Mutter with XWayland, DISPLAY=:0), Zig 0.17.1. Timing was run on レモン's instruction (2026-11-26, "time measurement may start any time"). See also the [Japanese version](TASK_CONTROL_IMPL_1398.ja.md).

## 1. Queue residence and Snapshot (1396)

`run-acceptance.py --mode measure --only workloads snapshot`, plan v7, two independent runs. Evidence on the Linux machine: `.work/acceptance/20261126T012404Z-6c8f32dc` and `20261126T022630Z-2bb6d391`.

| Metric | run1 max | run2 max | Guideline |
|---|---:|---:|---:|
| G1 enqueued→acquired (3 scenes) | 0.095 ms | 0.094 ms | 50 ms |
| G2 enqueued→acquired | 0.089 ms | 0.092 ms | 100 ms |
| T1 enqueued→acquired | 0.075 ms | 0.086 ms | 100 ms |
| I1 enqueued→acquired | 36.2 ms | 36.1 ms | 200 ms |
| Snapshot capture (300 times) | 15.5 ms | 15.5 ms | 50 ms |

All within the guidelines. I1 publish→reclaim reached 88.0 ms in run2: not over 100 ms but over 80%. I1 `queue_waiting` reached 4 (limit 4) and the Snapshot size was 3,620,338 bytes. All three call for extra trials under the 80% rule.

## 2. Composite wait, fairness and cleanup

`manual-acceptance-tty.py --cases mixed`: AC-18, 19 and 20 passed (`.work/1398/mixed`). `--self-test`: reclaiming owned children and grandchildren, survival of the outside dummy, and startup-failure protection passed; a `sleep` started outside the test was still alive afterwards (`.work/1398/self-test`).

## 3. Native window (1394, AC-02, 05, 25, D07)

The first measurement (`.work/1398/native-load` and `native-baseline`) showed a median request→complete of about 14 ms, and T1 input→screen over 33.34 ms (about 36 ms). By レモン's decision (option 2) the cause was investigated and fixed first ([1406](TASK_CONTROL_IMPL_1406.md): row-by-row PutImage batched up to 8 rows, direct 32bpp stores, poll-based frame wakeup). Request→complete became about 4.8 ms.

After the fix, a pair was taken with the 1405 tool (load run first, its send frames replayed in the baseline, 1,200 frames each) and imported under plan v8 (per-frame request→complete within 1/60 s, レモン's decision, option 1). Evidence: `.work/1398/native-load4` and `native-baseline4`; imports `.work/acceptance/20261126T060746Z-8d23057f` (path) and `20261126T060747Z-eedf2469` (search).

| Metric | G1 | T1 | Guideline / verdict |
|---|---:|---:|---|
| Frames and inputs | 1,200 and 6 (match baseline) | 1,200 and 6 (match baseline) | comparison condition met |
| Per-frame deadline misses (load / baseline) | 0 / 0 | 0 / 0 | pass |
| Additional misses from tasks | 0 | 0 | pass |
| Input→screen max | 23.1 ms | 23.7 ms | 33.34 ms, pass |
| Input→terminal max | 23.3 ms | 23.8 ms | 50 ms, pass |
| Cumulative cadence misses (reference, load / baseline) | 1,048 / 1,106 | 208 / 1,184 | property of the fixture loop period (mean 16.7-17.6 ms); not used for the verdict |

Visual and audible check (レモン, 2026-11-26): the normal-build fixtures (G1, T1, BYE) were run by hand in a terminal on the Linux desktop, and レモン answered "確認OK". Claude recorded this as: Generation did not decrease and the previous result stayed after f on G1 and T1; on BYE the tone sounded, stopped on q, and the window closed.

## 4. Verdict

- Residence, Snapshot, input→screen, input→terminal and per-frame deadlines: within the guidelines on Linux, with no additional misses from tasks.
- AC-18, 19, 20 and the cleanup self-test: passed. AC-25 and AC-05: confirmed by sight and hearing.
- Pixel readback after a window resize: passed on a private Xvfb (tque 1409; see the 1406 record).
