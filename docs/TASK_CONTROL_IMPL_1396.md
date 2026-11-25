# tque 1396: queue residence endpoints

2026-11-25. Base: main c4931ac. Author: Roku. Formal measurement: not performed.

Implemented submitted (Service.submit entry), input_copied (owned input copy completed), enqueued (successful queue insertion, before unlocking the gate), and acquired (physical worker acquisition, under the gate before deadline/cancellation checks). They share the task ID in the existing reclaimed task row. Acquisition uses a worker-written atomic read by the host. Enqueue is published under the queue gate. These fields and clock reads are excluded from normal builds through comptime task_acceptance guards/empty Storage/constant now(). No per-instruction polling was added.

Runner aggregates acquired - enqueued, separately from submit - publish: G1 50 ms, G2/T1 100 ms, I1 200 ms (USAGE_CONDITIONS section 3). I1 excludes the fixture's blocker, matching the existing submit/publish filter. Queue-removed tasks have no acquisition interval; absent/invalid endpoints on other tasks are missing evidence. Existing per-case/metric 80% rules apply. Smoke checks field types and names without calculating timing statistics. Task rows allow submit preparation and owned input-copy completion to be examined separately; submitted is the existing service submit boundary, not the entire public-word argument-validation boundary.

Snapshot independent readiness is NOT implemented. USAGE_CONDITIONS section 6 sets capture start to submission readiness at 100 ms, but does not define readiness. STATE_MACHINE section 3 defines accepted queue registration, while PUBLIC_API_PROPOSAL sections 3-4 separate Snapshot acquisition from entry inspection and input-copy admission. None defines the requested independent Snapshot readiness condition. Returning a snapshot ID, successful admission, or worker restoration must not be selected by inference. snapshot_main_ns remains API duration only. A user decision on readiness is required before adding that metric or claiming D07 coverage.

Plans revised to Windows/Linux v6 and macOS v4 for tque 1396; trial/extension counts and workload pacing are unchanged. The unresolved Snapshot interval is explicitly retained as a gap. Fixed SHA-256:

- Windows/Linux: c45a98503ee4939ddd2518377ee721e70656b38af5ebc4a9d3af61de083e4dcb
- macOS: 515804545d987b0c80326b48314340d212e531a528e6b30d2963ece5c6141c27

Validation: zig build test; zig build test -Ddebug=false; zig build runtime-test; zig build -Dtask-acceptance=true; verify-task-examples.py (17 groups); test-acceptance-hold.py; test-acceptance-output.py --sigma zig-out/bin/sigma.exe; check-docs.py; zig fmt --check on all three changed Zig files: passed. Reviewed Japanese TASK-SUBMIT/SNAPSHOT descriptions remain correct; refreshed translation source fingerprints without changing public word documentation.

Windows smoke: .work/acceptance/20261125T115104Z-0cf0769c/results.json. Ten endpoint format records cover all four new metric names; all valid, no timing statistics. Initial direct-binary smoke rejected task-native-probe=true; the successful runner-managed build used the required workload configuration. Initial hold test used the pre-existing normal binary and failed; the acceptance-build rerun passed. Initial cache access failed; setting both ZIG_GLOBAL_CACHE_DIR and ZIG_LOCAL_CACHE_DIR under .work resolved it.

Normal-build .text comparison is recorded separately below. tque show 1396 failed with StorageFailure opening the external storage lock (AccessDenied); no task mutation was attempted. No commit, branch, tag or push was performed. Protected manual acceptance files were not edited.

Claude must obtain Lemon's timing confirmation before running these commands, replace CONFIRMATION_REFERENCE with that actual approval reference, and record the environment required by the plans. Execute workloads in two independent runs as already prescribed; do not merge old and new samples. These commands cannot evaluate the unresolved Snapshot readiness interval. Counts remain runner/plan defaults.

Windows (PowerShell, repository root):
```powershell
python tests/scripts/run-acceptance.py --mode measure --only workloads snapshot --plan docs/TASK_CONTROL_ACCEPTANCE_PLAN.md --plan-sha256 c45a98503ee4939ddd2518377ee721e70656b38af5ebc4a9d3af61de083e4dcb --confirmed CONFIRMATION_REFERENCE
```
Linux (repository root):
```sh
python3 tests/scripts/run-acceptance.py --mode measure --only workloads snapshot --plan docs/TASK_CONTROL_ACCEPTANCE_PLAN.md --plan-sha256 c45a98503ee4939ddd2518377ee721e70656b38af5ebc4a9d3af61de083e4dcb --confirmed CONFIRMATION_REFERENCE
```
macOS (native arm64, ~/source/zig/ForthSigma):
```sh
python3 tests/scripts/run-acceptance.py --mode measure --only workloads snapshot --plan docs/TASK_CONTROL_ACCEPTANCE_PLAN_MACOS.md --plan-sha256 515804545d987b0c80326b48314340d212e531a528e6b30d2963ece5c6141c27 --confirmed CONFIRMATION_REFERENCE
```

Final Git inspection also shows changes to protected manual files and new 1395/wait fixtures during the session. This work did not edit or revert them. They remain outside the 1396 implementation.

Normal .text: same build directory, identical ReleaseFast/debug=false/strip=true/task-acceptance=false arguments, HEAD archive before/after the three Zig changes. Raw PE .text sizes [1532928, 1532928], SHA-256 ['955e53b3e44a95130d83f768441e815a60dad1bf064967988316c536794c5016', '955e53b3e44a95130d83f768441e815a60dad1bf064967988316c536794c5016'], equal=True. Evidence: .work/1396-release-text.json. Default Debug and different-directory comparisons also differed. No timing measurement was used.


## Snapshot readiness definition (user decision 2026-11-25, A)

By Lemon's decision, a Snapshot is ready for submission when `TASK-SNAPSHOT` returns its ID. The current implementation completes the capture on the main thread before returning the ID (`src/host_task_api.zig:214`), and that ID can be passed to `TASK-SUBMIT` at once. "Capture start to ready" is therefore the same interval as the existing `snapshot_main_ns`, and no new endpoint is added. The D07 100 ms target is checked with `snapshot_main_ns` (50 ms target). Maxima so far: Windows 13.2 ms, Linux 16.5 ms, Mac 32.2 ms (the 80% rule section of [the 1382 report](TASK_CONTROL_IMPL_1382.md)). If part of the capture is ever moved after the ID is returned, add an independent endpoint then.
