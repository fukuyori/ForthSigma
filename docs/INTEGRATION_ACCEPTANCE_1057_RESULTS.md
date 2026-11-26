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
| M0 | 未取得 / unknown | A | U | U | U | D | U | D | U | U | U | U | U | U | N |
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
| IA-06 / MNL-02 | Not performed | Obtain Lemon’s explicit confirmation and freeze plan hashes first. M0 path/search: 1,200 frames, two independent load→baseline pairs, two extra pairs under the 80% rule. Reconcile PCM/render equivalence and individual endpoints; listening is separate. |
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