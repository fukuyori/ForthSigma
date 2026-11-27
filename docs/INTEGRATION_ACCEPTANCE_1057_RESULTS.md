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
| IA-14 | P | 1444 audit complete; D1–D4 resolved; proposed pass within audited scope / 1444照合完了、D1〜D4解消済み、照合範囲で合格案。末尾のIA-14節を参照 |
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

## macOS hand checks MNL-01a to 05 (1426 and 1442, 2026-11-27)

Run by the user in Terminal on the Mac, following the procedure in the note of tque 1426. Every observation answer was OK or ok (`M0/human-reply.json` of each run on the Mac). No unit needed forced cleanup; each ended with IA-CLEAN error=0 (MNL-04 with IA-EXIT live BYE).

| Unit | Lines confirmed | Run | Binary |
|---|---|---|---|
| MNL-01a | IA-CLEAN error=0 | `20261127-201016-b147caed` | 58fa00a |
| MNL-01b | IA-CLEAN error=0 | `20261127-201058-f7055782` | 58fa00a |
| MNL-01b-f | IA-CLEAN error=0 | `20261127-201124-7f6a1b70` | 58fa00a |
| MNL-02 | IA-CLEAN error=0 | `20261127-201146-6bbc52bc` | 58fa00a |
| MNL-03a | IA-CAUGHT, IA-CLEAN error=0 | `20261127-202404-f2115c56` | 58fa00a plus 1442 |
| MNL-03b | IA-CANCEL resubmitted, IA-CLEAN error=0 | `20261127-201333-dd3efd39` | 58fa00a |
| MNL-04 | IA-EXIT live BYE | `20261127-201426-1ab471ed` | 58fa00a |
| MNL-05 | IA-WINDOW-CLOSED, IA-CLEAN error=0 | `20261127-201441-43f14454` | 58fa00a |

The first MNL-03a (`20261127-201210-0d1b9296`) failed: right after IA-CAUGHT the saved application ended with HOST FUNCTION ERROR and the sound stopped. The SIGINT of a physical Ctrl+C reaches the whole foreground process group, and the AppKit window child ended too. Claude reproduced it with scripted input (`20261127-201804-29170cda`), and 1442 made the window child ignore SIGINT. The scripted check after the fix (`20261127-201924-f3eb73f7`) and the user's repeat (`20261127-202404-f2115c56`) pass. The 1442 fix only changes how the window child treats SIGINT and does not affect the other seven observations.

The automated checks of all eight units are unverified with "native lifetime tracing required beyond macOS child polling", because they ran without eslogger; there is no other unverified reason and no failure.

Verdict: the human observations of macOS MNL-01a to 05 all pass. The descendant-process cleanup check is unverified.

## macOS rerun under eslogger tracing (1443, 2026-11-27)

With the binary after the 1440 and 1442 fixes (HEAD `73b782c`), the M0 to M9 automated checks ran with the same arguments as 1423 (`.work/integration-acceptance/20261127-210221-a3d08a10`, 21:02:21 to 21:40:41 JST). All 164 cases were unverified only because "native lifetime tracing required beyond macOS child polling"; no case was unverified for another reason or failed (the same shape as the 1423 run).

The user recorded with `sudo eslogger fork exec exit` (`.work/1443-eslogger.jsonl`, 9,439 events, 12:02:10 to 12:57:05 UTC), which covers the run. `tests/scripts/eslogger-process-tree.py` shows that the run's 204 processes, such as the saved applications, and their 238 descendants all exited; none was left without an exit (`.work/1443-process-tree.txt`).

Verdict: the macOS M0 to M9 automated checks pass with the fixed binary too. By the user's decision A (2026-11-27), this record also confirms the descendant cleanup of the hand checks MNL-01a to 05, whose endings (q, BYE, closing the window, Ctrl+C) take the same paths as the automated exit-quit, exit-bye, fault-window and interrupt cases. macOS MNL-01a to 05 therefore pass.

## IA-16 and IA-17: decisions for 999 and 1001 (1446)

Static transcription by Roku, 2026-11-28. Final authorities: [audio audit](AUDIO_TARGET_AUDIT.md), “最終採否（1140、2026-11-22、利用者の決定）” sections 1–3, and [emulator plan](EMULATOR_CORE_PLAN.md), “背景1画面の試作と測定（1001、2026-11-22）”. This checks existing records; no timing, listening or decision was repeated.

### IA-16: eight targets and measurement scope

The adopted versions batch advances as declared in each document (SNES uses SNES-FRAMES). Ratios are audio duration / wall time at the heaviest audio-only load, excluding the emulated CPU, display and devices. Windows: Windows 11 / Ryzen 7 7700. Linux: normally WSL / the same CPU; Apple II alone uses native Ubuntu 26.04.1 / Core i7-8700K. Mac: macOS 27.2.1 / Apple M5.

| Target | Model and adopted version | Heaviest load | Windows / Linux / Mac | Decision | Individual document and records |
|---|---|---|---|---|---|
| CHIP-8 | Original/SUPER-CHIP buzzer; XO-CHIP pattern/pitch, batched | xo_8khz_pattern_pitch | 33.78× / 38.23× / 50.59× | Keep Forth | [CHIP8_AUDIO_FORTH.md](CHIP8_AUDIO_FORTH.md); [JSON 1](measurements/2026-11-20-chip8-os-acceptance.json) |
| ZX Spectrum | 48K beeper; 128K beeper + AY, batched | 128k_period_zero | 3.59× / 4.14× / 5.34× | Keep Forth | [ZX_SPECTRUM_AUDIO_FORTH.md](ZX_SPECTRUM_AUDIO_FORTH.md); [JSON 1](measurements/2026-11-20-zx-spectrum-os-acceptance.json) |
| NES | NTSC five voices including DMC, batched | fast_max_noise_dmc | 6.17× / 6.88× / 9.17× | Keep Forth | [NES_DMC_FORTH.md](NES_DMC_FORTH.md); [JSON 1](measurements/2026-11-20-nes-dmc.json), [JSON 2](measurements/2026-11-20-nes-sid-windows-listening.json), [JSON 3](measurements/2026-11-20-linux-audio-listening.json) |
| Commodore 64 | PAL three-register-voice model, custom filter approximation, batched | maximum filter, sync and mixed modes | 1.03× / 1.17× / 1.43× | Keep Forth | [SID_FORTH.md](SID_FORTH.md); [JSON 1](measurements/2026-11-20-sid.json), [JSON 2](measurements/2026-11-20-nes-sid-windows-listening.json), [JSON 3](measurements/2026-11-20-linux-audio-listening.json) |
| SNES | S-DSP eight voices, BRR, envelope, noise, pitch modulation, echo/FIR, batched | dense_8khz_reg_ram (with `SNES-FRAMES`) | 28.69× / 30.34× / 28.04× | Keep SNES-FRAMES in core (1188) | [SNES_DSP_AUDIO_FORTH.md](SNES_DSP_AUDIO_FORTH.md); [JSON 1](measurements/2026-11-20-snes-dsp-os-acceptance.json), [JSON 2](measurements/2026-11-22-snes-dsp-macos-acceptance.json), [JSON 3](measurements/2026-11-22-snes-dsp-macos-timing.json), [JSON 4](measurements/2026-11-22-snes-dsp-macos-final-play.json) |
| Apple II | II/II+ NTSC speaker and Mockingboard, batched | card_8khz_bus | 5.82× / 2.74× / 7.49× | Keep Forth | [APPLE2_AUDIO_FORTH.md](APPLE2_AUDIO_FORTH.md); [JSON 1](measurements/2026-11-22-apple2-audio-windows-acceptance.json), [JSON 2](measurements/2026-11-22-apple2-audio-linux-acceptance.json), [JSON 3](measurements/2026-11-22-apple2-audio-macos-acceptance.json) |
| Amiga | PAL Paula four-channel stereo, DMA, manual DAT, IRQ, attach, batched | volume/period modulation | 5.52× / 6.44× / 7.95× | Keep Forth | [PAULA_FORTH.md](PAULA_FORTH.md); [JSON 1](measurements/2026-11-20-paula.json), [JSON 2](measurements/2026-11-20-paula-ym-windows-listening.json), [JSON 3](measurements/2026-11-20-linux-audio-listening.json) |
| Atari ST | YM2149 three voices, noise, envelope, I/O, ST byte bus, batched | fast_period1 | 3.21× / 3.83× / 4.87× | Keep Forth | [YM2149_FORTH.md](YM2149_FORTH.md); [JSON 1](measurements/2026-11-20-ym2149.json), [JSON 2](measurements/2026-11-20-paula-ym-windows-listening.json), [JSON 3](measurements/2026-11-20-linux-audio-listening.json) |

The final decision records listening, stopping after physical Ctrl+C and replay on all three OSes for all eight targets. Distinguish Windows waveOut, WSL pacat → WSLg PulseAudio RDPSink, native Apple II Linux pw-play → PipeWire, and Mac listening. WSL does not establish physical Linux/ALSA acceptance; direct ALSA is also unverified for Apple II. Mac acceptance sections are in the individual documents; some raw logs exist only in .work on that machine. These linked records were transcribed without fetching remote raw logs. Catching interruption is limited to existing waits/checkpoints; Ctrl+C in synthesis without checkpoints does not guarantee cleanup.

CHIP-8, ZX, SNES and Apple II were timed after user authorization. NES, SID, Paula and ST retain measurements taken without stopping other applications; the user decided against repeating them. SID at 1.03× on Windows is not headroom for the whole C64. Its internal bottleneck has not been measured; profile the breakdown when integrating the whole machine.

[1188 evidence and decision](SOUND_CORE_DESIGN_STUDY.md#124-決定利用者2026-11-22), sections 12.1–12.4: even rewritten pure Forth reaches only 0.74× for brr_filter3_pitchmax on native Linux. Fine generic helpers leave preparation/state management; their estimated 0.9–1.0× at maximum pitch is an estimate, not an implemented measurement. Retain SNES-FRAMES as the core policy exception and the optimized reference Forth for audio-excluded builds. Add no generic core component. Do not combine the table’s SNES 28.69/30.34/28.04× with the different-CPU 1188 breakdown samples.

| Target | Deferred variants |
|---|---|
| CHIP-8 | original speaker electrical characteristics |
| ZX Spectrum | +2/+3, clones, ULA contention, AY port B |
| NES | PAL/Dendy, cartridge expansion audio, CPU DMA stalls and bus contention |
| Commodore 64 | 6581/8580 analog behavior, D418 digi, combined waveforms, NTSC |
| SNES | SPC700 and fine DSP slot timing |
| Apple II | IIe/IIc/IIgs including DOC, PAL, cassette output, SC-01/SSI263, other cards, 6522 timers/interrupts |
| Amiga | NTSC, ECS, analog/LED filters, Agnus slots |
| Atari ST | STE DMA, Falcon, analog mixing |

Other model exclusions in each document are also deferred because the required CPU-side emulator does not yet exist, not because investigation established they are unnecessary. Add target-specific work when needed. Proposed verdict: IA-16 passes; no transcription conflict with final sections 1–3 was found. The SNES document’s old future-tense plan to replace components after 1188 is superseded history, as established by its opening update and the final 1188 decision.

### IA-17: Windows background prototype

Input: 256×240, 32×30 tiles, two bit planes and attribute-byte palette selection; no scrolling or sprites. Windows 11 Pro 10.0.26300 / Ryzen 7 7700 / Zig 0.17.1, -Doptimize=fast -Dcpu=baseline. After the user confirmed other applications were stopped, each workload ran in seven fresh processes in rotated order; medians cover only the word’s UTIME interval. Buffers/pixels were checked against independent Python calculations each round. SHOW, window presentation, startup and checks are excluded.

| Workload | Seven-run median µs/frame | Share at 60 Hz |
|---|---:|---:|
| naive8 | 4276.55 | 25.66% |
| fast8 | 691.38 | 4.15% |
| to32 | 1969.00 | 11.81% |
| put_indexed | 24.59 | 0.15% |
| put_rgb | 24.63 | 0.15% |
| put_rows | 43.24 | 0.26% |

Source: [Windows JSON](measurements/2026-11-22-background-prototype-windows.json), environment, method, result.workloads and sources. For all six workloads, medians recomputed from the seven stored values match the plan document. fast8 packs eight pixels into a cell and GFX-INDEXED delegates palette conversion to the core. The user decided on 2026-11-22 to keep Forth and add no core operation in this scope. Sprites, priority composition and four or more bit planes remain unmeasured. If Forth rendering proves insufficient, define generic inputs and add separate work. Later Mac measurements are not inputs/samples for this Windows decision. Excluding audio does not alter this drawing decision; excluding graphics does not require drawing words. Proposed verdict: IA-17 passes; no conflict in the checked conditions, values or decision.

## IA-14 English/Japanese documentation audit (1444)

Proposed verdict: **audit complete, D1–D4 resolved (proposed pass within this audited scope)**. See the [correspondence, inventory, original quotations and resolutions](INTEGRATION_ACCEPTANCE_1057_DOCS_AUDIT.md). All 15 former section 3 rows now match; 0 undecidable. Coverage remains 178 spellings/179 entries plus 43 supplemental PCM-STOP/TASK entries. D1 records native Mac async-I/O acceptance; D2 corrects LOOP/+LOOP HELP, Japanese translations and regenerated references; D3 records Tcl-driven Linux Tk close validation; D4 aligns current backend capabilities. Corrected rows were compared again. Runtime processing and contracts are unchanged; native acceptance was not rerun. Mechanical checks do not substitute for semantic comparison.
