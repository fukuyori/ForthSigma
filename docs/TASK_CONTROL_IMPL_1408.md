# tque 1408: TASK-SUBMIT latency measurement

[日本語](TASK_CONTROL_IMPL_1408.ja.md)

Acceptance-only probes split the synchronous submit path into snapshot lookup, admission, static entry inspection, Task allocation, name copy, and input copy. They use the monotonic acceptance clock and buffered `ACCEPTANCE` events; ordinary builds compile the probes away.

## Entry inspection assumptions and cache

After creation, a `Snapshot` does not mutate `bytes`. `inspectEntry` reads search order, case flags, dictionary and code from that saved image, resolves the entry name, and runs `inspectImage`. The submit caller supplies the same `admissionGate` every time; it never reads its context and always returns `false`. `inspectImage` reads no mutable machine state, clock, file, or runtime permission. Therefore this submit path's inspection result depends on the Snapshot and entry name.

Successful results are cached by name on each Snapshot, up to eight names. Names are copied with the Snapshot allocator and freed with the image when the last reference is released. Failed inspections and names beyond the limit are not cached. Repeated inspection of the same name on the same Snapshot skips parsing and static inspection. A lock inside the Snapshot serializes concurrent calls as well.

## Reproduction

```sh
export PATH=/opt/homebrew/bin:$PATH ZIG_GLOBAL_CACHE_DIR=$PWD/.work/codex-cache/global ZIG_LOCAL_CACHE_DIR=$PWD/.work/codex-cache/local
zig build -Dtask-acceptance=true --prefix .work/1399-submit/acceptance2
python3 tests/scripts/measure-task-submit.py .work/1399-submit/acceptance2/bin/sigma
```

The runner repeats the public T1 submit with the same `TS-SEARCH` entry and 1,048,593-byte argument as `examples/task-native-search.fs`, without opening a window. For every stage it prints the first call separately from later calls, with sample count, median and maximum in nanoseconds.

## Findings

On macOS arm64 Apple M5, 50 iterations before the change produced these medians/maxima (ns): snapshot lookup 1,000/3,000; admission 1,000/4,000; entry inspection 17,162,500/19,737,000; Task allocation 3,000/4,000; name copy 2,000/3,000; input copy 173,500/221,000.

After the change, first/later medians (ns) were: snapshot lookup 0/0; admission 1,000/0; entry inspection 9,832,000/1,000; Task allocation 2,000/3,000; name copy 2,000/2,000; input copy 108,000/95,000. The first entry inspection took 9,832,000 ns; the remaining 49 had a 1,000 ns median and maximum. These are separate runs, so differences in the other stages are not attributed to the cache. No native window was opened.

## Verification

Snapshot tests verify that a second inspection of the same name does not increment the inspection counter, a different name and a different Snapshot do, and a rejected name returns `EntryNotFound` on every attempt. They use `std.testing.allocator` to detect cache-name leaks on Snapshot release. Admission, limits, error ordering, ownership/freeing, and the meaning of `storage_zeroed` are unchanged. Failed results are not cached, so rejected entries are rechecked and return the same error.

Commands run: `zig build test`, `zig build runtime-test`, the acceptance build above, `python3 scripts/check-docs.py`, and `git diff --check`. The word-reference source fingerprint changed because implementation files changed; after confirming that Japanese explanations were unchanged, the reviewed fingerprints were recorded again.

## Claude's review and checks on three OSes (2026-11-26, tque 1408)

The cache key now also holds the options that can change an inspection result (`test_host_probes`, the `memory_gate` check function, `max_native_bytes`). The only caller today is `Service.submit` with the same options every time, but a call with other options must not reuse a result. A test checks that a different policy inspects again.

Stage times (entry inspection, median):

| OS | First | Later | Input copy (later) |
|---|---:|---:|---:|
| Windows | 4.6 ms | 0.002 ms | 0.21 ms |
| Linux | 5.7 ms | 0.004 ms | 0.73 ms |
| macOS | 12.5 ms | 0.001 ms | 0.10 ms |

Native window (macOS, plan macOS v6, `.work/1408/native-load1` to `3` and `native-baseline1`): the input-to-screen maximum went from 41.3 ms for T1 before the change (2 of 3 runs over the 33.34 ms guideline) to 16.7 ms or less for both T1 and G1 in all three runs. In the pair with the baseline, 1,200 frames and 6 inputs matched, per-frame deadline misses were 0 in the load run, and additional misses from tasks were 0.

Tests: `zig build test` and `zig build runtime-test` pass on Windows, Linux and macOS.