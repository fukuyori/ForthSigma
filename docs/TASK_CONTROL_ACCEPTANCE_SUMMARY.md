# Task control acceptance summary (1382 / 1383)

[日本語](TASK_CONTROL_ACCEPTANCE_SUMMARY.ja.md)

As of 2026-11-25 (section 3a and the AC table updated on 2026-11-26 at main `9e5e5c3` by Claude). Originally reviewed main `6856d99`; author: Roku. Overall verdict: **awaiting the user's confirmation** (every AC row passes; section 3a). This is an assessment of the cited reports and git log, not a new execution. Tested revisions and result-recording commits are distinguished.

Pass means recorded tests satisfy the specified AC contract; fail means the latest valid check violates it; unverified means missing evidence or remaining native subcases; N/A means outside that OS assignment. Skips, exit status zero and cross-builds alone do not establish acceptance. An AC with incomplete native integration remains unverified despite passing subcases.

## 1. Evidence index

| ID | Report / section and scope | Tested / recording commit | Run or log |
|---|---|---|---|
| R-W | [TASK_CONTROL_IMPL_1382.md](TASK_CONTROL_IMPL_1382.md) — 1382 §9 and “最終検証（Windows）”; 1400 “Validation”: latest test/plain/runtime passed. 1382 §1/§5 maps each AC to its tests. | `latest tested d3d0d66; record 6856d99` | .work/ac28-*.log (1400); .work/main-gap/checks-final/ (1382) |
| R-L | [TASK_CONTROL_IMPL_1381.md](TASK_CONTROL_IMPL_1381.md) — 1381 §6.1: native Linux full test/plain/runtime, examples and C00–C16; no terminal/graphics acceptance. | `33f37f7` | No run ID recorded / run ID記載なし; .work/task-public-matrix/ |
| R-M | [TASK_CONTROL_IMPL_1383.md](TASK_CONTROL_IMPL_1383.md) — 1383 “Mac 実機での事前確認” and “Mac実機での構成C00〜C16”: native test/plain/runtime and later full matrix. | `preflight record 0019f97; matrix tested adcc38b / record f33eb57` | No run ID recorded / run ID記載なし; .work/task-public-matrix/ |
| C | [TASK_CONTROL_IMPL_1382.md](TASK_CONTROL_IMPL_1382.md) — 1382 “出力保留の修正後の取消し位相の本測定”; 1383 “取消し位相の本測定の結果”: 4,100/4,100 per OS, no missing phases or threshold violations. | `ff7363b (record d6fa707)` | W 20261124T222722Z-ce3f2f55; L 20261124T222719Z-24000d52; M 20261124T222720Z-457847ee |
| W | [TASK_CONTROL_IMPL_1382.md](TASK_CONTROL_IMPL_1382.md) — 1382 “出力の保留の後の Windows の対話の場面の本測定”: six workloads, two independent ten-minute runs, no violations. | `eb45fed (record 3a80b26)` | 20261125T064638Z-e22f81c2; 20261125T074647Z-593d4db2 |
| LM | [TASK_CONTROL_IMPL_1382.md](TASK_CONTROL_IMPL_1382.md) — 1382 “G1 ワーカーの高速化の後の対話の場面の本測定”: Linux/Mac all metrics within targets; queue_waiting=4 triggers extension. | `0bb8a41 (record 04eddb5)` | L 20261125T032136Z-45c9954c / 20261125T042205Z-e63d6606; M 20261125T032140Z-29144992 / 20261125T042150Z-34c7c910 |
| F | [TASK_CONTROL_IMPL_1382.md](TASK_CONTROL_IMPL_1382.md) — 1382 “最新のソースでの残りの項目の本測定”: Snapshot, memory, pipe response, startup and size. | `3a80b26; A=35523f6 (record 579201a)` | W 20261125T084814Z-8d7094e2; L 20261125T084806Z-4269e6d6; M 20261125T084809Z-72cea647 |
| E | [TASK_CONTROL_IMPL_1382.md](TASK_CONTROL_IMPL_1382.md) — 1382 “80%規則による追加の測定”: Snapshot 1,000 processes × three generations, seven memory cases × ten; no violations. | `f5dcd15 (record adcc38b)` | Snapshot W 20261125T092612Z-992f9968 / L 20261125T092605Z-7b4c10ee / M 20261125T092608Z-3fa3a22b; memory W 20261125T092700Z-552b637a / L 20261125T092712Z-c36d1684 / M 20261125T092650Z-40ebbe5b |
| X | [TASK_CONTROL_IMPL_1400.md](TASK_CONTROL_IMPL_1400.md) — 1400 “Validation”: Windows C00–C17 (18 configurations, 155 commands) passed; new Linux/Mac checks unperformed. | `tested d3d0d66; recorded 6856d99` | .work/ac28-matrix-final.log; .work/task-public-matrix/ |
| T | [TASK_CONTROL_ACCEPTANCE_MANUAL.md](TASK_CONTROL_ACCEPTANCE_MANUAL.md) — Manual “Pseudo-terminal automation”, “Process ownership and collection failures”, “PENDIN and residual input”: tool and limitations, not a recorded three-OS acceptance run. | `d3d0d66` | No acceptance run ID in the cited reports / 指定報告書に受入れrun IDなし |

<a id="ac-verdicts"></a>

## 2. Verdict by AC and OS

R means R-W/R-L/R-M for the respective OS. Gap identifiers refer to methods and owners in section 3. Functional AC-07/09/13/21 contracts are distinct from the additional D07 timing/capacity gaps.

| AC | Scope | Windows | Linux | Mac | Evidence / gap owners |
|---|---|---|---|---|---|
| AC-01 | Cancellation | Pass | Pass | Pass | R, C  1382 §1/§5: `src/tests/task_control_w1_test.zig` |
| AC-02 | Main responsiveness | Pass | Pass | Pass | R, C, W, LM, F, T; U1; 2026-11-26: 1397, 1398, 1399, 1407, 1408 |
| AC-03 | Execution context | Pass | Pass | Pass | R, C  1382 §1/§5: `src/tests/task_control_1384_test.zig`, `task_control_w1_test.zig`, `task_permissions_test.zig` |
| AC-04 | Isolation | Pass | Pass | Pass | R  1382 §1/§5: `src/tests/task_cancel_memory_test.zig`, `task_job_test.zig` |
| AC-05 | Real resource ownership | Pass | Pass | Pass | R, C, W, LM, F, T; U1; 2026-11-26: 1397, 1398, 1399, 1407, 1408 |
| AC-06 | Forbidden words | Pass | Pass | Pass | R  1382 §1/§5: `src/tests/task_permissions_test.zig` |
| AC-07 | Snapshot data | Pass | Pass | Pass | R, E  1382 §1/§5: `src/tests/task_snapshot_test.zig` |
| AC-08 | Snapshot lifetime | Pass | Pass | Pass | R, E  1382 §1/§5: `src/tests/task_snapshot_test.zig` |
| AC-09 | Transfer/results | Pass | Pass | Pass | R  1382 §1/§5: `src/tests/task_transfer_test.zig` |
| AC-10 | Result API | Pass | Pass | Pass | R  1382 §1/§5: `src/tests/task_results_test.zig`, `task_public_api_test.zig` |
| AC-11 | State races | Pass | Pass | Pass | R, C  1382 §1/§5: `src/tests/task_state_machine_test.zig` |
| AC-12 | Ledger identities | Pass | Pass | Pass | R  1382 §1/§5: `src/tests/task_ledger_test.zig` |
| AC-13 | Backpressure | Pass | Pass | Pass | R  1382 §1/§5: `src/tests/task_queue_test.zig` |
| AC-14 | Notification recovery | Pass | Pass | Pass | R  1382 §1/§5: `src/tests/task_wait_reproduction_test.zig` |
| AC-15 | Wait registration | Pass | Pass | Pass | R  1382 §1/§5: `src/tests/task_wait_reproduction_host_test.zig` |
| AC-16 | Wait priority/deadline | Pass | Pass | Pass | R, C  1382 §1/§5: `src/tests/task_wait_host_test.zig` |
| AC-17 | Paint contract | Pass | Pass | Pass | R  1382 §1/§5: `src/tests/task_paint_test.zig` |
| AC-18 | Real composite wait | Pass | Pass | Pass | R, C, W, LM, F, T; U1, U2; 2026-11-26: 1397, 1398, 1399, 1407, 1408 |
| AC-19 | Controlled fairness | Pass | Pass | Pass | R  1382 §1/§5: `src/tests/task_schedule_host_test.zig` |
| AC-20 | Real fairness | Pass | Pass | Pass | R, C, W, LM, F, T; U2, U3; 2026-11-26: 1397, 1398, 1399, 1407, 1408 |
| AC-21 | Sequential VM reclamation | Pass | Pass | Pass | R, E  1382 §1/§5: `src/tests/task_reap_reproduction_host_test.zig` |
| AC-22 | Exit/restore | Pass | Pass | Pass | R  1382 §1/§5: `src/tests/task_reap_test.zig` |
| AC-23 | Unstoppable host | Pass | Pass | Pass | R  1382 §1/§5: `src/tests/task_reap_reproduction_host_test.zig` |
| AC-24 | Real exit/resources | Pass | Pass | Pass | R, C, W, LM, F, T; U1, U4; 2026-11-26: 1397, 1398, 1399, 1407, 1408 |
| AC-25 | Combined examples | Pass | Pass | Pass | R, C, W, LM, F, T; U1, U2; 2026-11-26: 1397, 1398, 1399, 1407, 1408 |
| AC-26 | Windows/Linux configurations | Pass | Pass | N/A | R, X, T; U1, U2; 2026-11-26: 1397, 1398, 1399, 1407, 1408 |
| AC-27 | Mac configurations | N/A | N/A | Pass | R, X, T; U1, U2; 2026-11-26: 1397, 1398, 1399, 1407, 1408 |
| AC-28 | Public words/docs | Pass | Pass | Pass | R, X, T; N1 |
| AC-29 | Ordinary generated code | Pass | Pass | Pass | F; size approval f5dcd15; U5; 2026-11-26: 1391–1393 (B/A′ normal-loop machine code identical; time not judgeable) |

AC-21 passes for the current contract: sequential new VMs on the same queue/worker, not reuse of warm VM internals. C00–C16 configuration execution itself passed on all three OSes. AC-26/27 remain unverified for native integration; the new 1400/C17 checks are not retroactively attributed to those 17-configuration runs.

## 3. Unverified items, methods and owners

| ID | Method / scope | tque owner |
|---|---|---|
| U1 | Run the manual AC-02/05/18/24/25 and configuration subcases with a combined task/audio/window fixture. Observe physical key/cursor/screen recovery, retained display on injected failure, 60 Hz presentation, 33.34 ms screen/50 ms terminal updates and extra missed frames; keep native timestamps and observations. | 1394 → Windows 1397 / Linux 1398 / Mac 1399 — done 2026-11-26 (section 3a) |
| U2 | Connect real input, I/O availability, completion, paint/close and deadlines to one wait; continuously feed them in one process and record progress, priority, input loss and I/O drainage. Separate sessions are supplementary only. | 1395 → Windows 1397 / Linux 1398 / Mac 1399 — done 2026-11-26 (section 3a) |
| U3 | Record acquired and submission-available endpoints independently; compare queue dwell 50/100/100/200 ms and Snapshot start-to-submission-available 100 ms. Snapshot API duration is insufficient. | 1396 → Windows 1397 / Linux 1398 / Mac 1399 — done 2026-11-26 (section 3a) |
| U4 | Run pseudo-terminal scenarios per OS, retain process/thread/child and terminal observations, rerun failed collectors. On Mac obtain fork/exit lifetime events from before startup through exit (System Trace/DTrace), including attachment/drop errors. Correlate residual keys with native reads on POSIX. Sampling alone cannot prove Mac descendant reclamation. | Windows 1397 / Linux 1398 / Mac 1399; POSIX residual input: Linux 1398 / Mac 1399 — done 2026-11-26 (section 3a) |
| U5 | Implement same-configuration A/A′/B single-VM workloads and ordinary-loop disassembly comparison; report median +1% / p95 +2%, layout uncertainty and D01 policy. Size approval does not close generated-code/performance acceptance. | 1390 → OS measurements 1391–1393 (OS assignment not live-verified / OS割当は今回照会不能) — done 2026-11-26 (section 3a) |
| N1 | Done: 1400 on native Linux and Mac (Claude, 2026-11-25): test, plain, runtime-test, docs and all C00–C17 configurations passed; recorded in commit 6856d99. | 6856d99 |
| N2 | Not needed (Claude, 2026-11-25): every task allocation, including Snapshot capture (`src/host_task_api.zig:214`) and job VMs (`:255`), goes through the accounting allocator whose limit (`:44`) keeps the total within the 128 MiB budget with the worker stack and service; the limit is tested (`src/host_task_api.zig:794`, the public allocation-failure test in `src/tests/task_public_api_test.zig`), and the 4 MiB Snapshot image limit is tested (`src/tests/task_snapshot_test.zig:302`). The boundary is enforced by construction, not inferred from OS sampling. | Not registered |

N2 is an additional D07 capacity gap related to AC-07/21, not a reversal of passing functional reproduction tests. Full memory-boundary verification is not stated in the queue-dwell/Snapshot-availability scope of 1396, so it is proposed separately. N1/N2 are not assigned existing numbers.

Attempts to run tque show for 1382, 1383 and 1390–1399 all failed with Access denied opening the storage lock. Numbers/scopes come from the current user instruction and manual. Current titles, parentage and completion flags could not be verified. No tque modification or registration was made.

## 3a. Follow-up results (2026-11-26)

U1-U5 were completed on 2026-11-26. Per-OS records: [1397](TASK_CONTROL_IMPL_1397.md) (Windows), [1407](TASK_CONTROL_IMPL_1407.md) (Windows pair, measured again), [1398](TASK_CONTROL_IMPL_1398.md) (Linux), [1399](TASK_CONTROL_IMPL_1399.md) (macOS), [1391](TASK_CONTROL_IMPL_1391.md) (single VM, three OSes). Problems found and fixed on the way: [1401](TASK_CONTROL_IMPL_1401.md) (line ends of embedded text), [1406](TASK_CONTROL_IMPL_1406.md) (faster Linux painting), [1408](TASK_CONTROL_IMPL_1408.md) (repeated entry inspection on submit), 1404 and 1405 (procedure and baseline pairing).

| Item | Windows | Linux | macOS |
|---|---|---|---|
| Residence (enqueued→acquired) and Snapshot capture | within guidelines | within guidelines | within guidelines |
| AC-18, 19, 20 (real sources, one process) | pass | pass | pass (every descendant exit confirmed with eslogger) |
| Input→screen max (guideline 33.34 ms) | 13.5 ms | 23.7 ms | 16.7 ms |
| Per-frame deadline (plan v8 / macOS v6) and additional misses from tasks | 0 and 0 | 0 and 0 | 0 and 0 |
| Visual and audible check (G1, T1, BYE) | confirmed | confirmed | confirmed |
| Single VM (AC-29, the user's decision, option 1) | normal-loop machine code identical in B and A′ | identical (instruction counts also checked) | identical |

On Windows, I1 publish→reclaim exceeded 100 ms six times (max 115.9 ms) in two runs on the afternoon of 2026-11-26 while other work was running. By the user's decision (option 1), I1 alone was measured again twice with other applications stopped: max 72.0 ms, no exceedances (`.work/acceptance/20261126T071523Z-e2ea10b0` and `20261126T072609Z-ba34be09`, plan v8).

Remaining unverified: pixel readback after a window resize on Linux (`SIGMA_TEST_RESIZE=1` in `test-linux-native-window.py`; it assumes a private Xvfb, which the Linux machine lacks; the build before 1406 fails the same way). It is not part of any AC verdict.

## 4. Latest results and superseded runs

C supersedes earlier phase misses and eight Windows reclamation violations in `20261124T220657Z-67318d59`. native_running holds at native entry and executes the full maximum operation after cancellation; it is a conservative bound, not direct observation of an in-flight request.

LM supersedes G1 violations at `d6fa707` and Linux G1-open median 116 ms at `b7073ab`. W supersedes the Windows reclamation violations still present at LM (maximum 176.5 ms). After buffering output: zero workload violations, management maximum 0.517 ms, publish-to-reclaim maximum 60.6 ms.

F is supplemented by E, completing the Snapshot/memory/queue-four extensions. Snapshot maximum duration W/L/M: 13.2/16.5/32.2 ms; bytes: 3,620,330/3,620,338/3,620,338. Observed added memory: 77.1/77.0/68.9 MB. F pipe-to-state maxima 0.617/1.349/0.565 ms are not physical screen latency. Windows queued-cancel extension `20261125T090001Z-7edefb21` ran 1,000 trials, reclamation maximum 17.2 ms, zero violations; the earlier 54 ms event did not recur.

Mac startup is judged by decision-B 1,000-trial run `20261125T090233Z-49332dc5` (`3a80b26`, record `e47725b`), superseding three 100-trial runs `20261125T085914Z-93419dc0`, `20261125T090056Z-b099dab4`, `20261125T090057Z-24bac77a`. Median +0.012 ms and p95 +0.006 ms pass. Windows/Linux startup also meets F targets. Size meets all three OS targets and was approved after breakdown in `f5dcd15`; U5 still prevents full AC-29 acceptance.

All old runs, violations, missing observations and old procedures remain historical records. Supersession applies only to the same measured scope; do not pool samples or transfer results to another OS or an unobserved condition. Cancellation run IDs dated November 24 UTC occurred on November 25 JST. T records added automation, not completed three-OS acceptance.

## 5. User decisions (2026-11-24–25)

| Date / choice | Decision / scope | Evidence |
|---|---|---|
| 11-24 A | Reduce counts: generation 25 × 100, native five × three × 100, queued 100, interaction ten minutes × one; preserve distinction from formal 1,000 / three-run starting protocol. | 1382 §2; bce27b9; current user instruction / 今回の指定 |
| 11-25 B | Hold the intended cancellation stage and rerun all 41 cases; retain old misses. | 1382 / 1383 “2026-11-25 決定B”; 0019f97 |
| 11-25 A | Speed up Linux G1 with the walled-grid worker, then remeasure all OSes; keep thresholds. | 1382 “G1 ワーカーの高速化の後…”; 0bb8a41 / 04eddb5; choice label from current user instruction / 選択記号は今回の指定 |
| 11-25 B | Judge Mac startup using one 1,000-trial rerun, retaining three earlier 100-trial runs. | 1382 “最新のソース…”; e47725b |
| 11-25 B → A | First obtain a size-growth breakdown, then approve growth on all three OSes; this does not approve unmeasured single-VM execution. | 1382 “コードの大きさ…”; 03a2c40 / f5dcd15 |
| 11-25 B | Apply the fixed 80% extension rule even to constant Snapshot size and queue_waiting=4. | 1382 “80%規則…”; adcc38b |
| 11-25 B | Automate manual terminal scenarios with ConPTY/POSIX pty; retain native observation and missing-capability gaps. | Manual “Pseudo-terminal automation (decision B, 2026-11-25)”; d3d0d66 |

On 2026-11-25 the overall acceptance was unverified, and N1 and N2 were gaps without an explicit existing task scope. As of 2026-11-26 every AC row passes (section 3a); the overall verdict awaits the user's confirmation.
