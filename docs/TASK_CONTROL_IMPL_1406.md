# tque 1406: Linux X11 paint batching

2026-11-26. See the [Japanese report](TASK_CONTROL_IMPL_1406.ja.md). Stage 1 tracing remains in place; stage 2 changes the Linux draw transport and mailbox wait. No plan, tque or Git state was modified by commands.

## Stage 1 evidence and cause

Claude measured outside the sandbox on XWayland: G1, 226 frames, 480×360 window. Evidence supplied for this task is under `.work/1406/native-before`.

| Interval | Median (ms) | p95 (ms) |
|---|---:|---:|
| request → take | 1.0 | 2.0 |
| take → draw-begin | 0.02 | 0.03 |
| draw-begin → draw-end | 13.4 | 14.0 |
| draw-end → roundtrip | 0.06 | 0.06 |
| roundtrip → complete | 0.0005 | 0.0006 |

T1 had the same pattern (draw about 13.5 ms). Window.draw dominated: one PutImage per row, separate header/body writes, ready() per row, and channel() per component per pixel. The next contributor was run()'s 2 ms sleep before taking a new frame. Completion after the server roundtrip was negligible.

Stage 1 added take, draw-begin, draw-end and roundtrip endpoints. `tests/scripts/paint-breakdown.py` joins the final draw attempt to its completion, reports missing endpoints and excludes smoke records. `run-acceptance.py` ignores unknown event types before applying its existing endpoint validation.

## Implementation

`src/host_window_linux.zig` packs the PutImage header and multiple scanlines into one contiguous send, retaining Connection.send's partial-write/backpressure handling and incrementing the protocol sequence once per request. Each request is limited to the setup maximum-request-length × 4, the 64 KiB local buffer and eight rows. BIG-REQUESTS is not enabled. Four-byte request padding remains distinct from each scanline's format padding. Windows wider than 2048 pixels keep horizontal tiles and one scaling pass per row.

After each generated row, the monotonic millisecond clock is checked. A changed clock tick ends the batch early; eight rows is the other cap. Events are drained in order between requests, and stop/redraw/window destruction abort drawing as before. Thus conversion between checks is approximately one millisecond plus at most one existing row's work; scheduling and socket backpressure are not hard real-time bounded. Actual input/Expose/close latency still needs native verification.

For the supported TrueColor visual, 32bpp with masks 0xff0000/0xff00/0xff and matching server/native byte order uses a direct native u32 store. The high byte is cleared exactly as in the generic path. Other formats retain channel() and byte-order conversion. A unit test compares both byte streams for all 256 values of each component and grayscale with nonzero alpha, and checks fast-path exclusion for opposite byte order and 16bpp.

A nonblocking, close-on-exec pipe wakes poll when a frame is published or stop is requested. The X fd is polled alongside it. Pipe registration, notification and closure share the mailbox lock to prevent writes to a reused fd; a full pipe already represents a pending wake. Frames published before registration are taken before the first wait. `src/host_x11.h` declares Linux pipe2 for libc translation without _GNU_SOURCE. The 2 ms poll timeout preserves the cadence of mode/IME housekeeping; frame arrival and X input no longer wait for that timeout.

The existing window_layout row generation, fit/smooth behavior, minimized/deferred completion, server roundtrip and WINDOW-FRAMES/WINDOW-PAINT-WAIT publication remain in use.

## Validation and native follow-up

With the requested cache directories, `zig build test` reported 371 passed, 36 skipped and two failures (the same host_x11 oversized-reply/GenericEvent socket test in two test binaries, expected send=32, actual -1). `zig build runtime-test` reported 184 passed, 17 skipped and the same one failure. The added TrueColor equivalence test passed. The acceptance build and `python3 tests/scripts/test-acceptance-paint.py` passed. `python3 scripts/check-docs.py` and `git diff --check` passed. Japanese word-reference descriptions were reviewed: batching/wakeup changes do not change word semantics; translation-source fingerprints were refreshed with `python3 scripts/word-reference.py --record-reviewed-sources`.

The sandbox cannot validate a displayed window. Existing host X11 socket send=-1 failures are an environment limitation, not a passing result.

Use the same fixtures, input cadence, display, scale and window size as stage 1. Build and capture new evidence in a fresh directory:

```sh
export ZIG_GLOBAL_CACHE_DIR=$PWD/.work/codex-cache/global
export ZIG_LOCAL_CACHE_DIR=$PWD/.work/codex-cache/local
zig build -Dtask-acceptance=true --prefix .work/1406/acceptance-after
python3 tests/scripts/manual-acceptance-tty.py --sigma .work/1406/acceptance-after/bin/sigma --cases native --native-paint --output .work/1406/native-after
python3 tests/scripts/paint-breakdown.py .work/1406/native-after/native-path/output.txt .work/1406/native-after/native-search/output.txt
```

For deterministic pixel readback on a private Xvfb, also run `SIGMA_TEST_BINARY=$PWD/.work/1406/acceptance-after/bin/sigma python3 tests/scripts/test-linux-native-window.py`; repeat with `SIGMA_TEST_RESIZE=1`. Inspect Expose, close, input, minimize/restore and stop under load. The manual runner is a functional/evidence driver; for timing use the stage 1 equal-length 226-frame procedure rather than treating its variable-length output as an equivalent sample.

## Stage 2 measurements

Claude measured outside the sandbox on XWayland (DISPLAY=:0, desktop logged in). Evidence on the Linux machine: `.work/1406/native-after` (G1 339 frames, T1 29 frames) and the 1398 pair `.work/1398/native-load4` and `native-baseline4` (1,200 frames each).

| Interval | Before median (ms) | After median (ms) | After p95 (ms) |
|---|---:|---:|---:|
| request → take | 1.00 | 0.04 | 0.04 |
| take → draw-begin | 0.02 | 0.02 | 0.03 |
| draw-begin → draw-end | 13.42 | 4.75 | 5.80 |
| draw-end → roundtrip | 0.06 | 0.06 | 0.08 |
| roundtrip → complete | 0.0005 | 0.0005 | 0.0007 |

Request to complete went from about 14.5 ms to about 4.8 ms. In the 1398 pair (plan v8), per-frame 1/60 s deadline misses were 0 in both the load and baseline runs, and the input-to-screen maximum was 23.1 ms for G1 and 23.7 ms for T1 (guideline 33.34 ms).

Native checks: with the normal build, `test-linux-native-window.py` (pixel readback, letterbox, key press and release, WM_DELETE and reopen, exit) and `verify-linux-window-restore.py` (drawing deferred while minimized and restored, close while waiting) passed. The `SIGMA_TEST_RESIZE=1` resize readback fails on the real display with the same X11 error (BadMatch on GetImage) for the build before this change as well, so it is not caused by 1406. That test assumes a private Xvfb, which the Linux machine does not have, so pixel readback after a resize is unverified. Method: install Xvfb (package `xvfb`) on the Linux machine and run the same test on `Xvfb :99`.
## Plan revision and freeze (2026-11-26, the user's decision, option 1)

The 60 Hz frame deadline is now judged per frame: request to complete within 1/60 s (the plans' closing section on the 60 Hz deadline revision). The cumulative cadence misses stay in the results as a property of the fixture's loop period and are not used for the verdict. A baseline with zero misses is no longer a condition for the comparison. Later imports pass these frozen values to `--plan-sha256`.

| Plan | SHA-256 |
|---|---|
| Windows/Linux v8 | `377be53a251b59dd58bd4df16763691998f28f69001d6b17864ea529e125194c` |
| macOS v6 | `ae2fabd1f1f6a687d3e1ef87e5a6571942f7a0bae0b9cbf79f69a8e095b97889` |