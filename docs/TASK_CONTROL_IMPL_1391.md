# tque 1391, 1392, 1393: single-VM run-time measurement and verdict

2026-11-26, main `333f8af` to `4c666ee` (the runner includes the 1402 and 1403 changes; product src/ and build.zig are unchanged since `333f8af`). Timing was run on レモン's instruction (2026-11-26, "time measurement may start any time"); other applications were not stopped. See also the [Japanese version](TASK_CONTROL_IMPL_1391.ja.md).

## 1. How the verdict is made (レモン's decision, 2026-11-26, option 1)

The time comparison varies by ±2-10% with layout and run, more than the guideline (median +1%, p95 +2%), so under the rule of the [1390 procedure](TASK_CONTROL_IMPL_1390.md) it **cannot be judged**. The verdict compares the machine code of the normal loop between B (current source) and A' (B with only the worker entry check removed). On Linux, after レモン set `kernel.perf_event_paranoid` to 2, instruction counts (`perf stat -e instructions:u`) were taken as supporting data.

## 2. Time measurement (cannot be judged)

Five workloads (CALC, XT, DEFERRED, INTERPRET, byte-scan); per control 5 warm-up and 100 samples, 10,000,000 iterations, two independent runs. The interval runs from the parent's release to receipt of the DONE line. Median B/A change:

| OS and layout | CALC | XT | DEFERRED | INTERPRET | byte-scan |
|---|---:|---:|---:|---:|---:|
| Windows base run1/run2 | +0.10 / −0.56 | −3.4 / −3.6 | −2.2 / −2.3 | −2.0 / −1.7 | −4.3 / −4.2 |
| Linux base | +5.6 | −13.7 | −6.6 | −1.1 | +0.3 |
| Linux hot16 | −5.2 | −13.2 | +7.3 | +4.0 | −10.6 |
| Linux hot32 | +2.5 | −12.4 | −4.7 | +1.4 | −5.3 |
| Mac base run1/run2 | +2.1 / −2.3 | −2.5 / −1.7 | −4.6 / −3.9 | −1.2 / −1.6 | −5.4 / −4.3 |
| Mac tail64 run1/run2 | −1.1 / −2.1 | −1.6 / −1.4 | −4.3 / −5.2 | −0.6 / −1.0 | −5.2 / −6.0 |

(Percent. Linux shows run1; run2 gave nearly the same values. tail64 on Linux is omitted because it matched base.)

- Linux: changing the layout flips the sign, and run1 and run2 reproduce the same values. The variation is set by the layout.
- Mac: CALC flips sign between runs of the same layout. Only two layouts could be made (runOperations at offsets 20 and 28 from a 64-byte boundary).
- Windows: all workloads were within the guideline, but the layout variants did not move the code ([1403](TASK_CONTROL_IMPL_1403.md)). A' holds the same normal loop as B, 160 bytes away, and was 50% slower on CALC. The layout effect is far larger than the guideline.

Evidence: Windows `.work/1391-prepared`, `.work/1391-run{1,2}`; Linux `.work/1391-prepared-linux`, `.work/1392-run{1,2}`, `.work/1392-layout-*-run{1,2}`; Mac `.work/1393-prepared`, `.work/1393-run{1,2}`, `.work/1393-layout-*-run{1,2}`.

## 3. Machine code of the normal loop

[single-vm-compare-function.py](../tests/scripts/single-vm-compare-function.py) disassembles each function range, replaces addresses, symbol names and immediate numbers, and compares the instruction sequences. On a pair that must differ (Linux A vs B runOperations) it reported 2,531 differing lines, which shows the tool does not miss differences.

| OS | executeWordMode (normal) | runOperations (normal) | executeBuiltin |
|---|---|---|---|
| Windows | 497 instructions, 0 differ | 1,905 instructions, 0 differ | 4,777 instructions, 0 differ |
| Linux | 454 instructions, 0 differ | 2,200 instructions, 0 differ | 4,787 instructions, 0 differ |
| Mac | 353 and 438 instructions, 0 differ | 1,813 and 105 instructions, 0 differ | 6,098 instructions, 0 differ |

Comparing the sizes of all 1,717 functions on Linux, B differs from A' only in `executeWord`, which became a separate function (81 bytes on Windows, 97 bytes on Linux), in the interpreter functions that call it (`handleWord`, `wordInLoop`, the `execute` of several word groups), and in the worker loop, which a single VM does not run.

## 4. Instruction counts (Linux, supporting)

[single-vm-count-instructions.py](../tests/scripts/single-vm-count-instructions.py) counts N=1,000 and N=10,000,000 three times each and derives instructions per iteration from the difference, so startup and definitions cancel. The three counts differ by a few instructions at most. Evidence: `.work/1392-perf/instructions-tool.json` on the Linux machine.

| Workload | A | A' | B | B/A | B/A' |
|---|---:|---:|---:|---:|---:|
| CALC | 223 | 214 | 214 | −4.0% | 0 |
| XT | 220 | 204 | 204 | −7.3% | 0 |
| DEFERRED | 214 | 197 | 197 | −7.9% | 0 |
| INTERPRET | 1,624 | 1,618 | 1,630 | +0.37% | +0.74% (+12 instructions) |
| byte-scan | 293 | 276 | 276 | −5.8% | 0 |

The entry check runs only in INTERPRET, which goes through the interpreter: 12 instructions per iteration (`S" 1+" EVALUATE`). CALC, where B was 5.6% slower than A in time, has 4.0% fewer instructions in B. This supports that the time differences come from layout.

## 5. Verdict

- On all three OSes the worker entry check adds nothing to the machine code of the normal loop. Under option 1 the single-VM normal path **passes**.
- The time comparison **cannot be judged** (layout and run variation exceeds the guideline).
- Scope: the normal loops of A and B differ widely in machine code (this includes other changes since W1). Option 1 compares B with A', so that difference is outside the verdict. In the Linux instruction counts, B/A is at most +0.37% for every workload.
- Instruction counts were not taken on Windows or Mac. Because the machine code is identical, the normal loop runs the same number of instructions in A' and B.
