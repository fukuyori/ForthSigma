# tque 1407: Windows native paint pair, measured again

2026-11-26, Windows 11 Pro 26300, AMD Ryzen 7 7700, Zig 0.17.1, main `0fc4888`. The 60 Hz frame-deadline comparison left unverified in [1397](TASK_CONTROL_IMPL_1397.md) was measured again with the [1405](TASK_CONTROL_ACCEPTANCE_MANUAL.md) tool (load run first, its send frames replayed in the baseline, 1,200 frames each) and plan v8 (per-frame request to complete within 1/60 s). See also the [Japanese version](TASK_CONTROL_IMPL_1407.ja.md).

## Tool fix

The first run (`.work/1407/load`) failed because the `NATIVE-DRAW` line of frame 37 (of 1,200 in G1) was not counted. ConPTY sent a space inside the line as a cursor-forward move (`ESC[1C`), and `clean()` in `manual-acceptance-tty.py` removed it instead of turning it back into a space. It now replaces `ESC[nC` with n spaces, and the self-test has examples.

## Results

Evidence: `.work/1407/load2` and `baseline2`; imports `.work/acceptance/20261126T061424Z-2d7f5b3a` (path) and `20261126T061425Z-c3f5a345` (search).

| Metric | G1 | T1 | Guideline / verdict |
|---|---:|---:|---|
| Frames and inputs | 1,200 and 6 (match baseline) | 1,200 and 6 (match baseline) | comparison condition met |
| Per-frame deadline misses (load / baseline) | 0 / 0 | 0 / 0 | pass |
| Additional misses from tasks | 0 | 0 | pass |
| Input→screen max | 13.5 ms | 13.0 ms | 33.34 ms, pass |
| Input→terminal max | 14.3 ms | 13.8 ms | 50 ms, pass |
| Request→complete max | 10.4 ms | 8.6 ms | — |
| Cumulative cadence misses (reference, load / baseline) | 93 / 71 | 3 / 0 | property of the fixture loop period; not used for the verdict |

Windows also has no per-frame deadline misses and no additional misses from tasks. This settles the unverified item of 1397.
