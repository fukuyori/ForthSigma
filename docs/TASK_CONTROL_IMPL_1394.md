# 1394: native task drawing and resource shutdown

[日本語](TASK_CONTROL_IMPL_1394.ja.md)

2026-11-25, Roku. Source checkout began at main `8ad71bb`. Implementation and Windows functional checks completed; acceptance timing, human visual/audible checks, macOS and Linux execution remain unverified. No commit, branch, tag, push, tque mutation, or formal timing run was performed.

Final repository HEAD was `47c169b` (1390), after `83832ff`; this session performed no Git mutations. Build logs and each native run retain their own source/executable evidence. Do not treat the initial HEAD as the final repository HEAD.

## 1. Scope and ownership

U1 / AC-02/05/25 now have native G1 (256×256 open board), T1 (1MiB search), and live audio/window/worker BYE fixtures. The prohibited files build.zig, src/forth.zig, src/core/runtime_base.zig and tests/scripts/single-vm-ab.py were not edited (git diff confirmed). Existing/concurrent audio and graphics/audio documentation changes are retained. The tque show 1394 query failed with StorageFailure opening the datastore lock (Access denied); current title/parent/status were not verified. Retry the read-only query in an environment with datastore access.

## 2. Fixtures and observations

`examples/task-native-common.fs` shares presentation and kind=5 waits. `task-native-path.fs` and `task-native-search.fs` reuse the existing workers and generation freshness predicate. The window displays accepted Generation and current Requested separately. Path vertices / search count and stored-offset count are rendered. n or a/b replaces work; f submits a permitted divide-by-zero worker; q exits. The failed generation never replaces the previous pixels. Every acknowledged frame produces `NATIVE-DRAW generation=… frame=… requested=…` on the terminal. Rapid replacement is checked through generation 7 without assuming every intermediate task succeeds.

`task-native-bye.fs` maintains a 440Hz held voice and window. A busy worker is renewed when its bounded deadline expires; q starts a fresh RUNNING worker and immediately calls BYE while audio, window, task and Snapshot remain owned. Shutdown is intentionally delegated to the application, with no fixture-side resource release. The fixture's RUNNING assertion, exit 0, terminal restoration and empty owned-process remainder were observed. Audible start/stop and actual window disappearance need a human observation; they are not inferred from process exit.

The manual driver adds `--native-paint --cases native`, and `--native-baseline` for the same rendering loop with no further submissions after warmup. Existing Job/session containment and recovery logic are unchanged. Its safety self-test passed (contained child/grandchild cleanup, unrelated dummy survival, failed startup). POSIX safety execution must be repeated by Claude on macOS/Linux. General AC statuses deliberately remain unverified.

## 3. Timing endpoints and aggregation

`src/host_paint_trace.zig` is enabled only by task-acceptance. A bounded, locked ring accepts backend-thread records; the owner copies it under the lock and serializes outside it. Overflow is explicit missing evidence. Normal builds have neither clock calls nor retained trace storage. The three backends record native frame request/complete IDs. `host_task_wait.zig` records kind=5 registration / PAINTED. macOS completion is parent observation of the child's PAINTED, not a synchronized child clock.

Native input acquisition (first host observation, including peek) is associated with the following request generation. Terminal endpoint means a NATIVE-DRAW line has drained from the writer; buffered/error cases omit the endpoint. It does not measure terminal-emulator pixel updates. The screen endpoint is the matched native frame's backend drawing completion. Physical key press, OS input queue residence, compositor presentation, and panel emission are outside these endpoints. D07 here ends at drawing completion; no physical-panel claim is made.

The runner's `paint` group imports an existing single-process PAINTTRACE log and never launches a timing workload. Smoke retains zero clocks and computes no differences/statistics. Confirmed measure imports require the existing confirmation and frozen-plan hash. It joins request/completion and wait endpoints, reports input-screen 33.34ms and input-terminal 50ms statistics/exceedances, and preserves all per-frame 60Hz deadlines. Frame 1 opens the window and is excluded only from steady cadence; frame 2 anchors rational 1/60-second deadlines. A later painted-through frame never fabricates completion of a skipped frame. Missing/duplicate/reversed endpoints and overflow are detected.

A taskless baseline must have matching source/build/backend/refresh/input/rendering workload and frame count, and meet its own deadlines before additional misses can be judged. The runner reports descriptive count differences and endpoint-count compatibility, but leaves comparison eligibility false pending Claude's environment/workload review. Different result shapes also require review. Synthetic parser checks cover joins, smoke exclusion, missing/overflow and invalid endpoints; these use invented timestamps and are not real timing measurements.

## 4. Frozen plans

Existing counts, independent runs, supply intervals and extension rules are unchanged. These are fixed file hashes, not hashes to recompute as expected values immediately before measurement:

| Plan | SHA-256 |
|---|---|
| Windows/Linux v7 | `9d1546a7899f16f9630c982192c1151b2c7c0dcff66a99d3171f58fd7b1b467b` |
| macOS v5 | `8e65bf5ede134c3ca2c396618fe76b03efe6538e62e13cd0715c7c02e30c85b2` |

Use the platform's fixed hash with --plan-sha256. Smoke imports need no timing confirmation. Native timing requires the user's prior time-measurement confirmation and is performed by Claude.

## 5. Normal-build .text

Compared ReleaseFast / debug=false / strip=true / acceptance=false artifacts in this same checkout, with the six changed tracked Zig files temporarily replaced by HEAD bytes normalized to LF, then restored byte-for-byte. Other checkout files, including audio changes, stayed common to both sides. The final modified files also used LF. No branch or worktree was created. The initial pre-edit build and intermediate mismatches are retained, not reused as the final comparison.

The complete file-backed PE .text bytes, including padding, match. Both logical sizes are 1,532,806 B; both file-backed sizes are 1,532,928 B; SHA-256 is `40a55252d6cc9f369ee041f7969f63188d96d73615854960f2f85f3aab61330e`. Evidence: `.work/1394/text-comparison.json`, `normal-same-checkout-before/`, `normal-final3/`, `build-normalized-baseline.py`. This is a code-byte comparison, not AC-29 performance acceptance or tque 1390 work.

## 6. Windows validation

All seven requested checks passed: test and debug=false test each 25/25 build steps; runtime-test 8/8; acceptance build exit 0; task examples 17 groups; docs findings 0; changed Zig files formatted. Safety and synthetic parser checks also passed.

Final checks and evidence are stored under `.work/1394/`: `accepted-test.log` (zig build test), `accepted-plain.log` (test -Ddebug=false), `accepted-runtime.log` (runtime-test), `accepted-build.log` (-Dtask-acceptance=true, separate prefix because existing sigma.exe was locked), `accepted-examples.log` (verify-task-examples.py), `accepted-docs.log` (check-docs.py), `accepted-fmt.log` (seven changed Zig files). The documentation source fingerprint record was refreshed after reviewing Japanese source explanations. No public words or version changed.

Native ConPTY checks: `native-final/results.json`, per-case raw output/events/process snapshots, plus `native-baseline-smoke/`. Path/search reach generations 1, 2, retained 2 after failed 3, 4, then 7; all processes exit naturally with code 0 and no forced workload cleanup. The initial `native-tty-smoke/` timed out because ConPTY omitted a trailing blank that an assertion required. The pattern was corrected to a word boundary; the failed attempt remains separate from successful runs. A later header cleanup temporarily omitted the worker include; native-final-ui records that failed attempt. The include was restored and native-final is the successful final-source rerun. Pipe smoke is supplementary, not terminal acceptance. Parser smoke import is recorded in the runner's own .work/acceptance output directory.

## 7. Remaining native acceptance

Claude repeats the documented build, native cases, baseline, driver safety self-test and specified suites on macOS and Linux/X11. In each local display session, visually match window Generation/Requested to NATIVE-DRAW, ensure f retains the preceding result, observe BYE closing the window, and have a human record tone start/stop. Capture process/thread/audio/window lifetime evidence; macOS needs fork/exit lifetime tracing rather than polling alone. For terminal pixel update timing, add an observed terminal-render endpoint; writer completion alone cannot establish it. After user confirmation, collect equal-condition baseline/load logs with SIGMA_ACCEPTANCE_SMOKE=0 and import them using the fixed plan hash; retain missing observations and avoid declaring full AC acceptance from exit 0 or statistics alone. No timing thresholds were evaluated in this implementation session.
