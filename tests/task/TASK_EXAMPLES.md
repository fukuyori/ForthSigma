# Computation task examples

Japanese: [TASK_EXAMPLES.ja.md](TASK_EXAMPLES.ja.md). English is primary.
These original examples use the repository's [MIT license](../../LICENSE).
Run commands from the repository root, with Zig 0.17.1 and EXTENSION and files
enabled. Graphics and audio are not required. Terminal output is the display.

## Run

```powershell
$env:ZIG_GLOBAL_CACHE_DIR = Join-Path $PWD '.zig-global-cache'
zig build -j2
zig-out/bin/sigma.exe tests/task/task-path.fs
zig-out/bin/sigma.exe tests/task/task-search.fs
zig-out/bin/sigma.exe tests/task/task-checksum.fs
```

G1: `n` changes the destination on an open 64 by 64 byte board; `q` quits.
The result contains a shortest four-neighbour path. T1: type a byte to change
the search pattern in a 1 MiB text of `a`; `q` quits. The G1 board uses `*` for
the path, `S` for the start and `G` for the goal. T1 overlapping matches are
counted; only the first 1,000 offsets are returned. The sample searches one byte,
while the worker accepts patterns of 1 to 256 bytes. I1: reads `LICENSE` in chunks
of at most 64 KiB and prints the chunk number and byte sum modulo 2^32 in order;
`q` quits. Change its path string for a larger file. Main owns all file I/O.

Every display loop checks input and polls the task with timeout zero. Frame and
generation output occurs only when the requested/applied generation or stop state
changes. Non-character events are ignored. The 10 MS pause limits polling; it
is not a frame deadline guarantee. G1/T1 reuse one snapshot and stream 7. A
successful new submission replaces the old request; its old public ID is then
released. Failure leaves the old handle available and prints the ior. Changing
the requested generation prevents that old result from being applied. Both
the captured request generation and the returned generation must match before
updating the display. Failed/cancelled work retains the previous display.
Main-side CATCH handlers release the task, snapshot and (for I1) open file before
rethrowing the original error. Cleanup attempts all releases even if one fails.
BYE also performs owner cleanup.

I1 keeps at most one outstanding chunk, so it preserves order without filling
the queue. Submission failure, failed work and cancelled work raise a Forth error instead of silently
skipping a chunk. This deliberately conservative example does not demonstrate
four queued chunks, asynchronous file reads, or a sustained input rate.

## Worker byte formats

Workers are separate loadable definition files; they do not start the UI.
Load them before taking a snapshot, then call TASK-SUBMIT with the worker name.
All metadata cells are forthz 64-bit cells for the current process, not a portable
file format. Offsets refer to bytes, never main-VM addresses. Callers must supply
complete headers, the declared payload, and the profile's size limits.

| Worker | Input | Result |
|---|---|---|
| `TP-SEARCH` | generation, width 64..256, start, goal; width squared terrain bytes (zero walkable) | generation, vertex count; 32-bit little-endian vertex IDs, goal first, start last; count zero for unreachable/invalid board |
| `TS-SEARCH` | generation, pattern length 1..256; pattern bytes then text bytes (up to 1 MiB) | generation, total matches, stored matches, truncated flag; up to 1,000 zero-based text byte offsets |
| `TI-CHECKSUM` | generation, chunk number; up to 64 KiB bytes | generation, chunk number, sum modulo 2^32 |

G1 uses breadth-first search with a FIFO and one visit per vertex. The maximum
path fits in 262,160 result bytes. A start equal to the goal returns one vertex;
blocked endpoints and disconnected boards return zero. Worker storage is private
to the restored VM. Worker loops use BEGIN, not DO. There is no dynamic execution,
CATCH, PAD, host output or file access in the workers. Native memory operations
in the worker process at most 64 KiB per call. Snapshot capture is a loading step.

## Automated checks

```powershell
python tests/scripts/verify-task-examples.py --sigma zig-out/bin/sigma.exe
zig build runtime-test -j2
```

The Python runner checks public Forth results, drives all three examples, then
exchanges keys with a process running an unending computation while it reads,
writes and deletes a scratch file and emits terminal frames. It exercises
replacement, cancellation, release and BYE with live work. Scratch files and
logs stay under `.work/`. Timeouts only detect hangs; no timing data is recorded.
Zig runtime tests additionally inspect host ownership after BYE: no ledger entries,
task/snapshot slots, transfer reservations or task allocator bytes remain.
This does not measure OS handles, committed memory or physical display response.

## Manual terminal check

In a foreground terminal run G1 and alternate `n` with other keys while results
arrive, then quit during calculation. Check that input and state-change output continue
and result generations never go backwards. Run T1, alternate `a`/`b`, and quit
during a search. Check the counts (1,048,576 for `a`, zero for `b`), truncation and
continued input/display. A terminal with line input may require Enter; record
that separately. Run I1 with a multi-chunk file and compare each printed sum
with an independent byte sum; press `q` during processing. Repeat normal exit
and Ctrl+C, then inspect process/resource ownership with the platform tools.
These manual checks have not been performed for 1380.

Deadline, input-to-screen latency and resource budget acceptance remain untested.
Obtain separate authorization before timing; fix the fixtures and conditions
from [usage conditions](../../docs/TASK_CONTROL_USAGE_CONDITIONS.md) first. The
[1380 report](../../docs/TASK_CONTROL_IMPL_1380.md) separates automated evidence,
manual procedures, Linux handoff and remaining acceptance work.

## Reclamation on each main-loop turn

Reclamation advances only inside task-word calls; MS, EKEY? and drawing do not advance it. After releasing results with TASK-RELEASE, keep calling a task word such as TASK-WAIT-MANY with a zero deadline on every application main-loop turn, including turns with no active task ID. A clock target (kind=4, id=0, arg0=0, arg1=0) and ms=0 can service reclamation without reusing a released ID. This advances collection after worker handback; it does not prove immediate termination.

```forth
CREATE REAP-TARGET 4 , 0 , 0 , 0 , 0 ,
CREATE REAP-EVENT 4 CELLS ALLOT
: REAP-TICK REAP-TARGET 1 REAP-EVENT 1 0 TASK-WAIT-MANY THROW 2DROP ;
```
