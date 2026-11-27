# 1057: Integrated acceptance results ledger (1415, open for updates)

[日本語](INTEGRATION_ACCEPTANCE_1057_RESULTS.ja.md)

## 1. Scope and verdicts

2026-11-26, Roku. Recording base `99afe6d`. Overall 1057 remains unverified; IA-18 aggregation is prepared, not completed. This update reads existing records and performs static review only, with no build, native execution or timing. See [plan](INTEGRATION_ACCEPTANCE_PLAN_1057.md) sections 2/4/7/8/11 and final decisions, [tools](INTEGRATION_ACCEPTANCE_1057_TOOLS.md) and [document/decision review](INTEGRATION_ACCEPTANCE_1057_REVIEW.md).

P=automated functional pass, F=fail, U=unverified, N=N/A, D=not performed (classified unverified). P/U means automatic pass with the complete IA still unverified pending manual or other evidence. P does not establish physical presentation, listening, timing or native restore/paint concurrency. N is a vocabulary/plan exclusion, never missing hardware. Shared static IA-14–18 apply to every OS/configuration; see section 4.

## 2. Sources, tested revisions and raw records

| 出典 / Source | run ID | 実行時HEAD / Tested HEAD | 方法 / Method | ledger SHA-256 |
|---|---|---|---|---|
| W | 20261126-193555-1be64edd | 92617e7c6b8ca97079f074adce11d0710c37594c | tests/scripts/integration-acceptance.py --functional --configs M0 M1 M2 M3 M4 M5 M6 M7 M8 M9 M10 | 49c8cecbaf81f057fc1df57f1aef4ffdde2e4ad820c937ef0b450ce9482af5c8 |
| W1 | 20261126-201122-54d17ba8 | 92617e7c6b8ca97079f074adce11d0710c37594c | tests/scripts/integration-acceptance.py --functional --configs M1 | 33fd1c0bb941fd67757fbe747d262b98c7d669a09ad835db1dd6517ec46d7215 |
| WT | 20261126-192325-012b4581 | 92617e7c6b8ca97079f074adce11d0710c37594c | tests/scripts/integration-acceptance.py --functional --configs M0 --backend tk --frames 240 | ada16933277ed86814d64f6b2695fb97f74ad411070aa0d19fba4e00663de626 |
| WC | 20261126-192425-c5f0d86e | 92617e7c6b8ca97079f074adce11d0710c37594c | tests/scripts/integration-acceptance.py --functional --configs M0 --backend terminal --frames 240 | 35bf40136528507ab09b09d02a5630e869b80a95e623574ba930720df4d49c4b |
| L | 20261126-193548-e41e290a | 未確認 / unknown | Claude確認済み要約 / supplied Claude-checked summary | 未取得 / unavailable |
| A | 20261126-193548-73ed9e3e | 未確認 / unknown | macOS: descendant lifetime tracking absent | 未取得 / unavailable |
| A6 | 1425, four path/search pairs each | 765b6cca36e05edb0c3a60d65fe8571901ecae5f | M0 native, formal 1,200-frame measurement | `.work/1425-summary.json` (contains SHA-256 for each output.bin) |
| A7 | 1425 re-measurement, two path/search pairs each | 6b6a7ac plus the 1440 working tree | M0 native, formal 1,200-frame measurement | `.work/1425b-runs.txt` on the Mac |

W1 supersedes W for M1; retain W’s earlier IA-03 unverified record rather than erasing it. WT/WC are the 240-budget Tk/terminal runs in the [1412 report](../.work/integration-acceptance/1412-diagnosis/REPORT.ja.md), distinct from W’s 1,200-budget run. Original Windows recording revisions are 92617e7 in manifest/ledger; this aggregate is the working tree based on 99afe6d. Original dirty diff and plan/fixture/binary hashes remain in each run’s manifest.json, working-tree.stdout and M*/binary.json. Matching HEAD alone does not establish identical binaries.

Windows runs exist under `.work/integration-acceptance/<run ID>/`; referenced ledger evidence paths were checked. Devices/audio remain “system default (unverified)” and human replies are absent. Linux/macOS files were not accessed: entries use the supplied summaries. L’s “all configurations pass” applies to applicable automatic branches, not saved startup on M10 or IA-05 outside M0. Claude should append L/A revisions, devices, backends, hashes and raw logs.

## 3. IA by OS, configuration and backend

Adapter checks outside plan section 2’s narrower configuration scope are retained as supplemental evidence. Each cell’s original verdict, reason and scenario evidence are in the matching ia/configuration/backend row of its source ledger.json. The aggregate manual qualifications below take precedence. M11 is Linux-only: all IA-01–13 are N on Windows/macOS.

### Windows

| 構成 / Config | backend | 出典 / Source | IA-01 | IA-02 | IA-03 | IA-04 | IA-05 | IA-06 | IA-07 | IA-08 | IA-09 | IA-10 | IA-11 | IA-12 | IA-13 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| M0 | native | W | P | P | P | D | P/U | D | U | P/U | P/U | P | P/U | P | N |
| M1 | native | W1 | P | P | P | D | N | N | P | P/U | P | P | P | P | N |
| M2 | native | W | P | P | P | D | N | N | U | P/U | P | P | P | P | N |
| M3 | native | W | P | P | P | N | N | N | U | N | P | P | P | P | N |
| M4 | native | W | P | P | P | D | N | N | P | P | P | P | P | P | N |
| M5 | native | W | P | P | P | N | N | N | U | N | P | P | P | P | N |
| M6 | native | W | P | P | P | N | N | N | P | N | P | P | P | P | N |
| M7 | native | W | P | P | N | N | N | N | P | N | P | P | P | P | N |
| M8 | native | W | P | P | P | D | N | N | U | P | P | P | P | P | N |
| M9 | native | W | P | P | P | D | N | N | U | P/U | P/U | P | P/U | P | P |
| M10 | native | W | N | N | N | N | N | N | N | N | N | N | N | N | P |
| M0 | tk | WT | P | P | P | D | P/U | D | P | P/U | P/U | P | P/U | P | N |
| M0 | terminal | WC | P | P | P | D | P/U | D | P | P/U | P/U | P | P/U | P | N |

### Linux

| 構成 / Config | backend | 出典 / Source | IA-01 | IA-02 | IA-03 | IA-04 | IA-05 | IA-06 | IA-07 | IA-08 | IA-09 | IA-10 | IA-11 | IA-12 | IA-13 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| M0 | 未取得 / unknown | L | P | P | P | D | P/U | D | U | P/U | P/U | P | P/U | P | N |
| M1 | 未取得 / unknown | L | P | P | P | D | N | N | U | P/U | P | P | P | P | N |
| M2 | 未取得 / unknown | L | P | P | P | D | N | N | U | P/U | P | P | P | P | N |
| M3 | 未取得 / unknown | L | P | P | P | N | N | N | U | N | P | P | P | P | N |
| M4 | 未取得 / unknown | L | P | P | P | D | N | N | U | P | P | P | P | P | N |
| M5 | 未取得 / unknown | L | P | P | P | N | N | N | U | N | P | P | P | P | N |
| M6 | 未取得 / unknown | L | P | P | P | N | N | N | U | N | P | P | P | P | N |
| M7 | 未取得 / unknown | L | P | P | N | N | N | N | U | N | P | P | P | P | N |
| M8 | 未取得 / unknown | L | P | P | P | D | N | N | U | P | P | P | P | P | N |
| M9 | 未取得 / unknown | L | P | P | P | D | N | N | U | P/U | P/U | P | P/U | P | P |
| M10 | 未取得 / unknown | L | N | N | N | N | N | N | N | N | N | N | N | N | U |
| M11 | 未取得 / unknown | L | P | P | P | D | N | N | U | P | P | P | P | P | U |

### macOS

| 構成 / Config | backend | 出典 / Source | IA-01 | IA-02 | IA-03 | IA-04 | IA-05 | IA-06 | IA-07 | IA-08 | IA-09 | IA-10 | IA-11 | IA-12 | IA-13 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| M0 | native | A/A7 | U | U | U | D | U | P | U | U | U | U | U | U | N |
| M1 | 未取得 / unknown | A | U | U | U | D | N | N | U | U | U | U | U | U | N |
| M2 | 未取得 / unknown | A | U | U | U | D | N | N | U | U | U | U | U | U | N |
| M3 | 未取得 / unknown | A | U | U | U | N | N | N | U | N | U | U | U | U | N |
| M4 | 未取得 / unknown | A | U | U | U | D | N | N | U | U | U | U | U | U | N |
| M5 | 未取得 / unknown | A | U | U | U | N | N | N | U | N | U | U | U | U | N |
| M6 | 未取得 / unknown | A | U | U | U | N | N | N | U | N | U | U | U | U | N |
| M7 | 未取得 / unknown | A | U | U | N | N | N | N | U | N | U | U | U | U | N |
| M8 | 未取得 / unknown | A | U | U | U | D | N | N | U | U | U | U | U | U | N |
| M9 | 未取得 / unknown | A | U | U | U | D | N | N | U | U | U | U | U | U | U |
| M10 | 未取得 / unknown | A | N | N | N | N | N | N | N | N | N | N | N | N | U |

IA-11 P/U covers automatic saved startup/append only. Active full restore required by final decision B needs the separate Zig test described in tools section 4; a substituted window does not prove native paint concurrency. L has no supplied M10 IA-13 verdict, so it stays unverified. A lacks short-lived/escaping descendant lifetime evidence: every applicable scenario remains unverified despite exit 0 or passes on other OSes.

## 4. Shared static verdicts for all OSes/configurations

| IA | 判定 / Verdict | 根拠・残件 / Evidence and remaining work |
|---|---|---|
| IA-14 | P | Review §1–2; F1–F4 corrected; N1–N3 recorded |
| IA-15 | P | Review §3 and validation §6; original plan/decisions unchanged |
| IA-16 | P | Review §4; 1140 §1–3 and plan §6 agree; no remeasurement |
| IA-17 | P | Review §5; six stored medians agree; no native additions |
| IA-18 | U | This ledger prepared; native/manual/timing and L/A provenance remain open |

## 5. Unperformed/unverified work and update procedure

| 対象 / Item | 状態 / State | 次の確認方法 / Next procedure |
|---|---|---|
| IA-04 / MNL-05 | Not performed | Manually close the saved app window per OS, observing same-process wait release and terminal recovery. Keep sequence dispositions and pipe/task reconciliation separate. |
| IA-06 / MNL-02 | macOS numeric measurement passes (A7); MNL-02 not performed | The first 1425 run (A6, unverified) is kept. The re-measurement after the 1440 fix (A7) passes. MNL-02 listening is requested separately in 1426. |
| IA-07 native capability / non-EXTENSION graphics | Not performed | Per OS/backend, record capabilities, unsupported-wait rejection and deadline/input/cancellation termination in one run. Do not reuse WT/WC passes for native. |
| MNL-01a / 01b / 01b-f | Not performed | Request path n, search a/b and separate f runs individually; visually compare generations and retained images for IA-05. |
| MNL-03a / 03b | Not performed | Separately request physical Ctrl+C during a wait and resubmission after cancellation; observe terminal/cursor and audio/window recovery/continuation for IA-08. |
| MNL-04 | Not performed | q in saved bye fixture; observe window disappearance/audio stop separately from automatic IA-09 reclamation. |
| IA-11 / real paint | Unverified | Link per-OS execution evidence for final-B simultaneous PCM/task/window Zig test and D2 child/pipe test. Separate actual native paint concurrency from substitution. |
| macOS all scenarios | Unverified | Capture eslogger fork/exec/exit before launch through exit; link owned-descendant lifetimes to terminal/scenario records. Retain gaps/permission failures; polling alone cannot pass reclamation. |
| Linux M11 / IA-13; M10 | Unverified | Import original Linux ledger/manifest; attach X11-excluded M11 capability and M10 image-boundary evidence/reasons. |
| L/A provenance | Unverified | Claude appends original ledger/manifest, tested revision/dirty diff, recording revision, OS/devices/backend/audio route, SHA-256 and raw logs. |

Request manual units one at a time under plan section 7, giving absolute executable, OS/backend/audio route, target window, command, action, expected result and stop method. Preserve R6’s exclusion of real DwmFlush-unavailable environments; do not request them again.

### Append-only records for Claude

| 日付 / Date | IA / OS / Config / backend | run / tested / recorded | 自動 / 総合判定 Auto / Overall | 原ログ・SHA-256 / Raw logs | 機器・音経路 / Devices | 人の回答 / Human reply | 制約・次の方法 / Limits, next method |
|---|---|---|---|---|---|---|---|
| — | — | — | — | — | — | — | — |

Append each new run separately, retaining earlier failures/gaps and the reason for supersession. Link human-reply.json to raw hashes; distinguish supplied summaries from direct logs. Update matching bilingual keys together; automatic results alone never pass MNL or timing.

## 6. Document validation for this update

2026-11-26: `python scripts/check-docs.py` reports zero findings; `git diff --check` passes. Checked 106 local links in the four new documents, named source sections, Windows ledger evidence paths, all six medians from the stored seven-value 1001 samples, bilingual structure and LF. Both plan files match HEAD; their decision tables are unchanged.

## Plan freeze (before the IA-06 measurement, 2026-11-26)

The Japanese plan is authoritative; its SHA-256 is passed to `--plan-sha256`. Both plan files are `-text` in `.gitattributes`, so checkouts on all three OSes have the same bytes.

| Document | SHA-256 |
|---|---|
| INTEGRATION_ACCEPTANCE_PLAN_1057.ja.md (authoritative) | `bab8017fa35c6448d4d0cdbe8ebf2b2040d907fff420489a873cf95d9a8f08d2` |
| INTEGRATION_ACCEPTANCE_PLAN_1057.md | `da20c53d90710e430b77534a5ce299194e499da7adb99b712c63e3633c41020e` |
## macOS descendant lifetime tracing (1423, 2026-11-26)

The macOS automated run (`.work/integration-acceptance/20261126-204614-acd76ed6`, M0-M9, HEAD `99afe6d`) left all 174 cases unverified for one reason only: lifetime tracing beyond macOS child polling was required (0 cases failed to pass for any other reason). The user recorded with `sudo eslogger fork exec exit` (`.work/1414-eslogger.jsonl`, 28,711 events, 11:45:13 to 12:21:44 UTC), which covers the run (11:46:14 to 12:20:51 UTC). `tests/scripts/eslogger-process-tree.py` found 204 run processes (saved applications and others) and their 238 descendants, all exited; none remained. macOS IA-01 to 03, 05, 08 to 12 and 13 (M9) therefore pass by the automated checks, as on Windows and Linux. IA-04, 06, part of 07 and the hand checks are covered by separate tasks, as on the other OSes.
## Linux M11 (no X11) IA-07 and IA-13 (1420, 2026-11-26)

The adapter never judges IA-13 for M11 automatically; it always marks it unverified (`tests/scripts/integration-acceptance.py:347`). On the Linux machine, M11 ran with the Tk backend (`.work/integration-acceptance/20261126-212518-c4bf82b5`) and the terminal backend (`20261126-193339-3d89dcf4`). Both passed IA-01 to 03 and 07 to 12, and the `normal` case printed `IA-FRAME-WAIT rejected no-capability; deadline/input fallback` and `IA-BUDGET deadline reached`: without X11, the native frame-completion wait is rejected as unavailable, and the run proceeds and ends by deadline and input. On this evidence Claude judged IA-13 (M11) as passed.
## macOS M0 on the Tk and terminal backends (1424, 2026-11-26)

On Tk (`.work/integration-acceptance/20261126-212155-d3dee35b`) and terminal (`20261126-212545-283a799a`), each of the 23 cases was unverified only because lifetime tracing was required. With the same eslogger record (`.work/1414-eslogger.jsonl`, up to 12:30:08 UTC), all 26 run processes and 99 descendants (Tk) and all 26 and 36 (terminal) exited. Including IA-07, these pass as on Windows and Linux.
## Windows IA-06 (1417, 2026-11-26)

Measured from the M0 saved-application entry while playing PCM, under the conditions frozen by the plan (Japanese SHA-256 `bab8017f…`). Started on the user's instruction ("いつでも進めて"); other applications were not required to be stopped. The first three attempts did not reach a verdict because of tool problems (ConPTY inserted control sequences inside records; likewise split terminal lines; input times were not recorded on the composite-wait path). After fixing the adapter and the acceptance-build recording, the fourth attempt was judged. Failed runs are kept in `.work/1417-runs*.txt`.

| Pair | Input→screen max | Input→terminal max | Per-frame deadline misses (load / baseline) | Additional misses | PCM underrun increase |
|---|---:|---:|---:|---:|---:|
| path 1 | 26.77 ms | 28.12 ms | 0 / 0 | 0 | 0 |
| path 2 | 10.97 ms | 12.14 ms | 0 / 0 | 0 | 0 |
| path 3 (80% rule extra) | 10.54 ms | 11.90 ms | 0 / 0 | 0 | 0 |
| path 4 (80% rule extra) | 11.74 ms | 13.01 ms | 0 / 0 | 0 | 0 |
| search 1 | 13.15 ms | 14.65 ms | 0 / 0 | 0 | 0 |
| search 2 | 26.30 ms | 27.50 ms | 0 / 0 | 0 | 0 |

Every pair matched the baseline at 1,200 frames and 6 inputs. Path 1's 26.77 ms exceeded 80% of the 33.34 ms guideline (26.67 ms), so two independent extra pairs were added as planned, and the original pairs are kept. Verdict: Windows IA-06 passes. Run IDs are in `.work/1417-runs4.txt` and `.work/1417-runs4-extra.txt`.
## Windows hand checks MNL-01a to 05 (1418, 2026-11-26 to 27)

M0, native. The user ran `--manual <unit>` in their own PowerShell, typed terminal keys at `キー>`, and answered at `観察結果>`. Tool problems were fixed along the way (waiting for input after q, Ctrl+C not delivered as an interrupt, no audible tone, saved-application output not visible to the user). Where the answer field was empty or `done`, Claude copied the user's chat answer and noted that in `human-reply.json`.

| Unit | Observation | Run |
|---|---|---|
| MNL-01a | no problem (n raises Requested, Generation catches up, never goes back) | `20261126-214314-22fdffeb` |
| MNL-01b | no problem (same with a and b) | `20261126-214846-207f770a` |
| MNL-01b-f | no problem (Generation and display stay after f) | `20261126-214957-ffbb5770` |
| MNL-02 | no problem (synthetic tone clean, display reacts to keys) | `20261126-215101-ce76c751` |
| MNL-03a | ok (Ctrl+C gives IA-CAUGHT; window and sound continue) | `20261127-175012-bce2d422` |
| MNL-03b | OK (c cancels and resubmits; n gives a new result) | `20261127-175137-3a541c85` |
| MNL-04 | ok (q gives IA-EXIT live BYE; window closes, sound stops) | `20261127-175338-a70ec686` |
| MNL-05 | ok (close button gives IA-WINDOW-CLOSED, IA-CLEAN error=0) | `20261127-175430-85f15024` |

Verdict: Windows MNL-01a to 05 all pass, covering the human-observed parts of IA-04 (close releases the wait), IA-05, IA-08 and IA-09.
## Linux IA-06 (1421, 2026-11-27)

The first probe run recorded input times of 0 on the POSIX terminal-input path (`.work/integration-acceptance/20261127-180335-e2f5d3ff`). As on Windows, acceptance builds now stamp the first fetch in the POSIX single-byte read (`posix.readByte` in `src/host_input.zig`), with a test; normal builds behave the same. The measurement then ran on the Linux machine's real display (GNOME/Mutter with XWayland). Run IDs are in `.work/1421-runs.txt` on the Linux machine.

| Pair | Input→screen max | Input→terminal max | Per-frame deadline misses (load / baseline) | Additional misses | PCM underrun increase |
|---|---:|---:|---:|---:|---:|
| path 1 | 12.95 ms | 12.06 ms | 0 / 0 | 0 | 0 |
| path 2 | 16.27 ms | 15.50 ms | 0 / 0 | 0 | 0 |
| search 1 | 21.51 ms | 20.95 ms | 0 / 0 | 0 | 0 |
| search 2 | 19.85 ms | 18.83 ms | 0 / 0 | 0 | 0 |

Every pair matched the baseline at 1,200 frames and 6 inputs. The 21.51 ms maximum is below 80% of the 33.34 ms guideline, so no extra pairs were needed. Verdict: Linux IA-06 passes.

## macOS IA-06 (1425, 2026-11-27)

Measured M0/native path and search at 1,200 frames per run, with two independent pairs per topic. Plan SHA-256: `bab8017fa35c6448d4d0cdbe8ebf2b2040d907fff420489a873cf95d9a8f08d2`; HEAD: `765b6cca36e05edb0c3a60d65fe8571901ecae5f`. Each topic reached at least 80% of the 33.34 ms input-to-screen limit, so two extra pairs per topic were collected under plan section 8.

| Topic / pair | Input→screen max | Input→terminal max | Request→complete misses (load / baseline) | Additional misses | PCM underrun delta (load / baseline) | Accepted frames (load / baseline) | Missing endpoints (load / baseline) |
|---|---:|---:|---:|---:|---:|---:|---:|
| path 1 | 41.221 ms | 23.864 ms | 398 / 9 | 389 | 0 / 0 | 958,336 / 958,336 | 506 / 41 |
| path 2 | 33.925 ms | 20.020 ms | 123 / 664 | 0 | 0 / 0 | 958,816 / 958,816 | 139 / 763 |
| path 3 (extra) | 32.076 ms | 23.352 ms | 166 / 154 | 12 | 0 / 0 | 958,816 / 958,816 | 182 / 166 |
| path 4 (extra) | 32.467 ms | 23.368 ms | 663 / 194 | 469 | 0 / 0 | 958,336 / 958,816 | 754 / 207 |
| search 1 | 30.132 ms | 22.312 ms | 177 / 172 | 5 | 0 / 0 | 958,336 / 958,816 | 262 / 185 |
| search 2 | 31.966 ms | 21.478 ms | 111 / 534 | 0 | 0 / 0 | 958,336 / 958,816 | 125 / 650 |
| search 3 (extra) | 32.069 ms | 20.938 ms | 160 / 364 | 0 | 0 / 0 | 958,336 / 958,816 | 174 / 483 |
| search 4 (extra) | 29.286 ms | 19.906 ms | 162 / 91 | 71 | 0 / 0 | 958,816 / 958,336 | 176 / 108 |

All eight load/baseline pairs had matching render schedules, and every run had PCM underrun delta 0. However, each pair lacks individual paint/wait endpoints; accepted PCM frames also differ by 480 between load and baseline for path 4 and all search pairs. Observed additional deadline misses remain in path 1/3/4 and search 1/4. Therefore macOS IA-06 remains unverified, not a pass. The audio route was system default (unverified); MNL-02 listening remains separate and unperformed. Run IDs, executable hashes and raw output SHA-256 values are indexed in `.work/1425-summary.json`. Earlier invalid measurement attempts are retained under their `.work/1425-*/` directories.

## Linux hand checks MNL-01a to 05 (1422, 2026-11-27)

Run by the user in a terminal on the Linux machine's desktop (GNOME/Mutter with XWayland), following the procedure in the note of tque 1422. All eight units passed the automated checks, with no forced cleanup; the observation answers were OK or ok (`M0/human-reply.json` of each run on the Linux machine).

| Unit | Lines confirmed | Run |
|---|---|---|
| MNL-01a | IA-CLEAN error=0 | `20261127-185201-963d2260` |
| MNL-01b | IA-CLEAN error=0 | `20261127-185310-fa4b1253` |
| MNL-01b-f | IA-CLEAN error=0 | `20261127-185337-88b5e1b8` |
| MNL-02 | IA-CLEAN error=0 | `20261127-185404-9764766d` |
| MNL-03a | IA-CAUGHT, IA-CLEAN error=0 | `20261127-185435-4d79b310` |
| MNL-03b | IA-CANCEL resubmitted, IA-CLEAN error=0 | `20261127-185510-ca063f21` |
| MNL-04 | IA-EXIT live BYE | `20261127-185645-1f34064b` |
| MNL-05 | IA-WINDOW-CLOSED, IA-CLEAN error=0 | `20261127-185701-8febe452` |

Verdict: Linux MNL-01a to 05 all pass. The MNL-03a runs Claude made to check the tool (`20261127-180115-cf93845f` on Xvfb, `20261127-180218-f7df2c56` with scripted input) are not acceptance evidence.

## macOS IA-06 re-measurement (1425 and 1440, 2026-11-27)

Task 1440 investigated why A6 was unverified. Sending the image from the parent to the child took about 1 ms at most and the child's drawing 12.3 ms at most; the delay was in the parent reading the child's "painted" notice (up to 34.8 ms). The parent read the pipe only at certain points, and the child drew once per display update, so a frame in between could be replaced before it was drawn. In 1440 the parent gained a reader thread for the child's pipe that records endpoints at arrival time, and the child now draws each FRAME as soon as it accepts it.

| Topic, pair | Input to screen max | Input to terminal max | Deadline misses (load / baseline) | Additional misses | Missing endpoints | PCM underrun delta (load / baseline) | Accepted frames (load / baseline) |
|---|---:|---:|---:|---:|---:|---:|---:|
| path 1 | 14.83 ms | 14.66 ms | 0 / 0 | 0 | 0 | 0 / 0 | 958,816 / 959,776 |
| path 2 | 19.87 ms | 19.71 ms | 0 / 0 | 0 | 0 | 0 / 0 | 958,816 / 959,776 |
| search 1 | 14.84 ms | 14.66 ms | 0 / 0 | 0 | 0 | 0 / 0 | 958,816 / 959,776 |
| search 2 | 19.46 ms | 19.32 ms | 0 / 0 | 0 | 0 | 0 / 0 | 958,816 / 960,256 |

Every pair matched its baseline in frame count (1,200), input count (6) and rendering sequence. The maxima are below 80% of 33.34 ms (26.67 ms), so no extra pairs were needed.

Accepted frames (2026-11-27, the user's decision A): the accepted-frame count depends on the length of the measured interval, and a difference between load and baseline is not a reason to fail. In plan section 8, "missing" means a missing record and "a difference in supply method" means a different way of supplying; audio gaps are judged by the underrun delta (0 in every run). The Windows pass (1417, differences of about 10,000 to 50,000 frames) and the Linux pass (1421, difference 0) agree with this reading.

Verdict: macOS IA-06 passes. Run IDs are in `.work/1425b-runs.txt` on the Mac.
