# tque 1390: single-VM A/A'/B comparison tooling

2026-11-25, Linux, starting main `8ad71bb`, Zig 0.17.1. No acceptance timing measurement or timing verdict was performed. Changes remain in the working tree. No tque changes, commits, branches or pushes.

## Controls and scope

This implements the missing single-VM comparison described in [usage conditions](TASK_CONTROL_USAGE_CONDITIONS.md), section 7 and line 122, using the reduced-plan approach in the [acceptance plan](TASK_CONTROL_ACCEPTANCE_PLAN.md). The code-size breakdown in [1382](TASK_CONTROL_IMPL_1382.md) motivated preserving the second worker loop. The existing frozen plan and runner are unchanged. This is not a complete AC-29 acceptance result.

A is `35523f676836134c4fbaed19e3d01d2a23ec2a92`, exported with `git archive` and built separately. B is the ordinary working-tree build. All use ReleaseFast, debug=false, native target, default word groups/capacities and strip=false, retaining symbols for disassembly. B/A' additionally explicitly disable task-trace and task-acceptance. Do not combine these observations with strip=true distribution-build measurements.

A' copies B's tracked and nonignored untracked files and changes exactly one source anchor in `src/forth.zig`:

```diff
-        if (self.workerCancellation() != null) return self.executeWordMode(true, id);
+        if (comptime false) return self.executeWordMode(true, id);
```

This removes the worker-context decision at `executeWord`, including native reentry through that entry. It preserves `runAsWorkerWithMemory` → `executeWordMode(true)`, the second worker `runOperations`/`runOperationsLoop` instantiation, task services, State layout and recovery machinery. A' is strictly a single-VM, worker-unused control; it must not be used as a functioning worker product. The actual patch is saved as `Aprime.patch`; a changed/nonunique anchor fails closed. No product build setting, build.zig or src modification is introduced.

A/B includes other changes since W1. A'/B may include compiler, inlining and layout effects: it is not exclusively entry cost. A/A' is not a pure noise control either. The runner also builds an unmodified B copy at a separate source location and requires exact `.text` (Mac `__text`) bytes/hash agreement with ordinary B. This checks reproducibility of the unchanged default configuration, not speed invariance.

## Method and evidence

[The runner](../tests/scripts/single-vm-ab.py) exercises five independent fixtures: CALC (the existing runtime benchmark's arithmetic kernel), XT/EXECUTE, DEFERRED/DEFER/IS calls, INTERPRET/EVALUATE, and a 4KiB byte-buffer sum. The last approximates a small streaming aggregation kernel, not a complete application. There is no worker, rendering or file I/O inside the timed workload. Each fixture has an independently calculated integer checksum.

Each sample starts a separate process, defines/initializes/compiles its fixture, then waits at READY. The parent measures `monotonic_ns` from releasing one input byte to receiving DONE. This excludes startup and compilation but includes pipes, scheduling and completion output; it is wall time, not pure VM CPU time. The protocol is identical on Linux, Windows and macOS. Whole-process wall time is recorded separately for cost estimates. Choose iterations long enough before evaluating a 1% difference.

All six permutations of A/A'/B rotate deterministically. Warmups are separate. Median averages the two middle samples for even counts; p95 uses nearest rank. Each workload reports B/A, B/A', A'/A increases against median 1% and p95 2%. B/A is the main comparison; others aid diagnosis. Workloads are never averaged together, and meeting the numerical guidelines does not grant automatic acceptance. Smoke runs one warmup plus two functional samples per engine/workload, with no timing statistics or verdict.

Proposed reduced-plan counts are five warmups plus 100 samples per workload/control, in two independent runs. With 100 samples, p95 is only the 95th observation. **The user must fix counts, iterations, number of runs and extension rules before measurement; these values are proposals, not an approved plan.** Measure requires explicit `--rounds`, `--confirmed` and `--environment`. Do not discard slow observations. Interrupted/failed runs are incomplete; preserve them and use a new directory for reruns. Do not automatically apply the existing maximum-based 80% extension rule to these relative statistics; decide extension rules separately beforehand.

Artifacts include source manifest, A archive/hash, A' patch, HEAD/status, Zig version/binary hash, build commands/logs, executable hashes, fixture files/hashes, raw JSONL including warmups, summaries, objdump section tables, complete disassembly and selected normal-function listings. `--builds` reuses binaries; preserve their original preparation directory as provenance. Binary hashes and text sections are recaptured on reuse. Missing summary after an interruption is not a passing run.

## Layout uncertainty and disassembly

An identical B copy checks reproducibility but does not settle layout sensitivity. Before acceptance, prepare several matched A/A'/B layout variants in separate source copies, retaining patches, commands and function addresses. A concrete additional experiment is to add a small retained C function through a copied build.zig, containing 0/64/256 bytes of NOPs, and reverse C-object addition order. Verify in disassembly that linker GC retained it and that relevant function addresses/layout actually changed. This extra experiment is proposed, not implemented or executed. Appending zeros to the file or repeating ASLR alone does not substitute for changing function layout.

Each variant can be supplied through `--builds` using the generated builds.json structure (A/Aprime/B/B-copy binary entries). B-copy must duplicate B with the same layout settings. Keep layouts and independent runs separate. If the sign or guideline classification changes across runs/layouts, or variation is large relative to 1%, report inconclusive and investigate. Confidence intervals are not computed automatically. Layout uncertainty remains until this experiment is done.

`*-normal-functions.txt` extracts all symbols matching runOperations/Loop, executeWord/Mode, executeBuiltin and executeCompiled. Identify ordinary worker=false and worker instantiations from source/call sites. Distinguish anonymous symbol numbering, addresses, relocation changes and actual instructions; a textual diff alone is insufficient. Inspect full disassembly for inlined entry code.

## Claude's measurement commands and estimated duration

Run from repository root using Python 3.12+, Zig 0.17.1, git and GNU objdump or a compatible llvm-objdump. On Mac, use `--objdump llvm-objdump` (or the installed Mach-O-capable tool) on every invocation. Windows/macOS execution has not been verified here. The proposed 100 samples, 10,000,000 iterations and two runs below require a user decision beforehand. Replace confirmation/environment placeholders with real records. Use new output directories every time.

Linux/macOS:

```sh
export ZIG_GLOBAL_CACHE_DIR=$PWD/.work/codex-cache/global ZIG_LOCAL_CACHE_DIR=$PWD/.work/codex-cache/local
python3 tests/scripts/single-vm-ab.py --mode prepare --out .work/1390-prepared
python3 tests/scripts/single-vm-ab.py --mode measure --builds .work/1390-prepared/builds.json --out .work/1390-run1 --rounds 100 --warmup 5 --iterations 10000000 --confirmed USER-DECISION-REF --environment 'CPU, power, background load, terminal: fill before run'
python3 tests/scripts/single-vm-ab.py --mode measure --builds .work/1390-prepared/builds.json --out .work/1390-run2 --rounds 100 --warmup 5 --iterations 10000000 --confirmed USER-DECISION-REF --environment 'CPU, power, background load, terminal: fill before run'
```

Windows PowerShell:

```powershell
$env:ZIG_GLOBAL_CACHE_DIR="$PWD/.work/codex-cache/global"
$env:ZIG_LOCAL_CACHE_DIR="$PWD/.work/codex-cache/local"
python tests/scripts/single-vm-ab.py --mode prepare --out .work/1390-prepared
if ($LASTEXITCODE) { throw 'prepare failed' }
foreach ($n in 1,2) {
  python tests/scripts/single-vm-ab.py --mode measure --builds .work/1390-prepared/builds.json --out ".work/1390-run$n" --rounds 100 --warmup 5 --iterations 10000000 --confirmed USER-DECISION-REF --environment 'CPU, power, background load, terminal: fill before run'
  if ($LASTEXITCODE) { throw "run $n failed" }
}
```

One run has 1,575 processes: `3 × (100+5) × sum(mean process duration for each of five workloads)`. ※推測です: assuming 0.1–2 seconds per process, allow about 3–53 minutes/run, or 6–106 minutes for two runs per OS. INTERPRET may be substantially longer; this range is not a guarantee. ※推測です: separately allow 2–15 minutes/OS for four builds and disassembly, plus the same preparation and two-run allowance for every layout variant. Windows, Linux and Mac use the same hypothetical range because their measurement performance was not measured. This is not a linear extrapolation of smoke into acceptance performance.

## Linux verification

Final results are appended below. Known sandbox X11 `send=-1` failures are not modified by this task. See also the [Japanese report](TASK_CONTROL_IMPL_1390.ja.md).

- `zig build test`: 1,662 passed, 48 skipped, two failures, both the same known X11 `send=-1` test in main/runtime. The result is retained in `.work/1390/test.log`.
- `zig build test -Ddebug=false`: 1,587 passed, 123 skipped, two failures from the same X11 test.
- `zig build runtime-test`: 182 passed, 17 skipped, one failure from the same X11 test. These three commands are not reported as completely passing.
- Smoke in `.work/1390/smoke-verified/`: five workloads × three controls × (one warmup + two checks) = 45 processes, all checksums correct, no timing verdict. The first `.work/1390/smoke/` stopped on fixture names colliding with existing words; names now use the `SVAB-` prefix. The failed attempt is retained.
- Python byte compilation and `git diff --check`: passed.
- `python3 scripts/check-docs.py`: findings: 0 after aligning English/Japanese code fences.

Some loop code is inlined into runOperations, so counting runOperationsLoop symbols alone does not identify worker-loop presence. A' retains the worker entry and both compile-time modes in source.

B was also rebuilt directly from the repository root before the final smoke. B and its unmodified copy have byte-identical .text: 1,387,299 bytes, SHA-256 `afd2fc65b2f1ab91f0797e2f4d49ac606e9270611a6b92e5bff6c64a293971e1`. A is 1,279,875 bytes; A' is 1,385,571 bytes. These are artifact checks, not timing verdicts. Repeating `zig build test` reused cached successful checks and reported 367 passed, 36 skipped, and the same two X11 failures; 1,662 passed above refers to the first complete run. Final logs remain under `.work/1390/`.
