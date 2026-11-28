# 1057: Integrated acceptance results ledger (1415, open for updates)

[日本語](INTEGRATION_ACCEPTANCE_1057_RESULTS.ja.md)

## 1. Scope and verdicts

2026-11-26, Roku. Recording base `99afe6d`. Overall 1057 remains unverified; IA-18 aggregation is prepared, not completed. This update reads existing records and performs static review only, with no build, native execution or timing. See [plan](INTEGRATION_ACCEPTANCE_PLAN_1057.md) sections 2/4/7/8/11 and final decisions, [tools](INTEGRATION_ACCEPTANCE_1057_TOOLS.md) and [document/decision review](INTEGRATION_ACCEPTANCE_1057_REVIEW.md).

2026-11-28 update: IA-18 aggregation completed; the current proposal is to accept 1057 as passed (see the final aggregation at the end; the earlier proposal to keep it unverified was superseded the same day). The same day Lemon accepted 1057 as passed (see "User's final decision" at the end). The preceding 2026-11-26 statement is the initial record.

Initial snapshot legend (current P/F/U/N codes are defined in Final aggregation): P=automated functional pass, F=fail, U=unverified, N=N/A, D=not performed (classified unverified). P/U means automatic pass with the complete IA still unverified pending manual or other evidence. P does not establish physical presentation, listening, timing or native restore/paint concurrency. N is a vocabulary/plan exclusion, never missing hardware. Shared static IA-14–18 apply to every OS/configuration; see section 4.

> 1445/1447 note: dated entries below are historical snapshots. Current verdicts are in §3 and the final aggregation. A7 supersedes A6; 1443 supersedes the Mac manual cleanup gap. Missing provenance in §2 remains missing.

2026-11-28 update after Claude’s 07:4x checks: current verdicts are in §3 and Re-aggregation (1451) below. The 07:02 final aggregation and missing-provenance statements are retained as history and superseded where specified below.

2026-11-28 final update (1447): §3 and “Final consolidation after Lemon’s decision (1447)” at the end are current. Earlier verdicts, counts and the 07:52 list of 22 required gaps are retained as superseded history.

2026-11-28 supplemental update (1461, 1462, 1466): §3 and the final “Consolidation after supplemental checks” are current. Earlier statements and counts are retained as superseded history.

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

## 3. IA × OS × configuration × backend (current / 現行、1461・1462・1466)

See Consolidation after supplemental checks and Change to not required for current evidence codes and counts; earlier rules and tables remain as history.

| OS | Config | backend | IA-01 | IA-02 | IA-03 | IA-04 | IA-05 | IA-06 | IA-07 | IA-08 | IA-09 | IA-10 | IA-11 | IA-12 | IA-13 | IA-14 | IA-15 | IA-16 | IA-17 | IA-18 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Windows | M0 | native | P:W | P:W | P:W | P:W+H | P:W+H | P:T+H | P:K07 | P:W+H | P:W+H | P:W | P:R11 | P:W | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Windows | M0 | Tk | P:WT | P:WT | P:WT | P:C29 | N:XHD | N:XTD | P:WT | P:D29 | P:D29 | P:WT | P:R11 | P:WT | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Windows | M0 | terminal | P:WC | P:WC | P:WC | P:C29 | N:XHD | N:XTD | P:WC | P:D29 | P:D29 | P:WC | P:R11 | P:WC | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Windows | M1 | native | P:W1 | P:W1 | P:W1 | P:C28 | N:XHD | N:X6 | P:W1 | P:D28 | P:W1 | P:W1 | P:R11 | P:W1 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Windows | M1 | Tk | P:B29 | P:B29 | P:B29 | P:B29 | N:XHD | N:X6 | P:B29 | P:B29 | P:B29 | P:B29 | P:R11 | P:B29 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Windows | M1 | terminal | P:B29 | P:B29 | P:B29 | P:B29 | N:XHD | N:X6 | P:B29 | P:B29 | P:B29 | P:B29 | P:R11 | P:B29 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Windows | M2 | native | P:W | P:W | P:W | P:C28 | N:XHD | N:X6 | P:K29 | P:D28 | P:W | P:W | P:R11 | P:W | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Windows | M2 | Tk | P:B29 | P:B29 | P:B29 | P:B29 | N:XHD | N:X6 | P:B29 | P:B29 | P:B29 | P:B29 | P:R11 | P:B29 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Windows | M2 | terminal | P:B29 | P:B29 | P:B29 | P:B29 | N:XHD | N:X6 | P:B29 | P:B29 | P:B29 | P:B29 | P:R11 | P:B29 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Windows | M3 | native | P:W | P:W | P:W | N:XE | N:XE | N:X6 | P:K29 | N:XE | P:W | P:W | P:R11 | P:W | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Windows | M3 | Tk | P:B29 | P:B29 | P:B29 | N:XE | N:XE | N:X6 | P:B29 | N:XE | P:B29 | P:B29 | P:R11 | P:B29 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Windows | M3 | terminal | P:B29 | P:B29 | P:B29 | N:XE | N:XE | N:X6 | P:B29 | N:XE | P:B29 | P:B29 | P:R11 | P:B29 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Windows | M4 | native | P:W | P:W | P:W | P:C29 | N:XHD | N:X6 | P:W | P:W | P:W | P:W | P:R11 | P:W | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Windows | M4 | Tk | P:B29 | P:B29 | P:B29 | P:B29 | N:XHD | N:X6 | P:B29 | P:B29 | P:B29 | P:B29 | P:R11 | P:B29 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Windows | M4 | terminal | P:B29 | P:B29 | P:B29 | P:B29 | N:XHD | N:X6 | P:B29 | P:B29 | P:B29 | P:B29 | P:R11 | P:B29 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Windows | M5 | native | P:W | P:W | P:W | N:XE | N:XE | N:X6 | P:K29 | N:XE | P:W | P:W | P:R11 | P:W | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Windows | M5 | Tk | P:B29 | P:B29 | P:B29 | N:XE | N:XE | N:X6 | P:B29 | N:XE | P:B29 | P:B29 | P:R11 | P:B29 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Windows | M5 | terminal | P:B29 | P:B29 | P:B29 | N:XE | N:XE | N:X6 | P:B29 | N:XE | P:B29 | P:B29 | P:R11 | P:B29 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Windows | M6 | native | P:W | P:W | P:W | N:XE | N:XE | N:X6 | P:W | N:XE | P:W | P:W | P:R11 | P:W | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Windows | M6 | Tk | P:B29 | P:B29 | P:B29 | N:XE | N:XE | N:X6 | P:B29 | N:XE | P:B29 | P:B29 | P:R11 | P:B29 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Windows | M6 | terminal | P:B29 | P:B29 | P:B29 | N:XE | N:XE | N:X6 | P:B29 | N:XE | P:B29 | P:B29 | P:R11 | P:B29 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Windows | M7 | native | P:W | P:W | N:X3 | N:XE | N:XE | N:X6 | P:W | N:XE | P:W | P:W | P:R11 | P:W | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Windows | M7 | Tk | P:B29 | P:B29 | N:X3 | N:XE | N:XE | N:X6 | P:B29 | N:XE | P:B29 | P:B29 | P:R11 | P:B29 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Windows | M7 | terminal | P:B29 | P:B29 | N:X3 | N:XE | N:XE | N:X6 | P:B29 | N:XE | P:B29 | P:B29 | P:R11 | P:B29 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Windows | M8 | native | P:W | P:W | P:W | P:C29 | N:XHD | N:X6P | P:K29 | P:W | P:W | P:W | P:R11 | P:W | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Windows | M8 | Tk | P:B29 | P:B29 | P:B29 | P:B29 | N:XHD | N:X6P | P:B29 | P:B29 | P:B29 | P:B29 | P:R11 | P:B29 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Windows | M8 | terminal | P:B29 | P:B29 | P:B29 | P:B29 | N:XHD | N:X6P | P:B29 | P:B29 | P:B29 | P:B29 | P:R11 | P:B29 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Windows | M9 | native | P:W | P:W | P:W | P:C28 | N:XHD | N:X6P | P:K29 | P:D28 | P:D28 | P:W | P:R11 | P:W | P:W | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Windows | M9 | Tk | P:B29 | P:B29 | P:B29 | P:B29 | N:XHD | N:X6P | P:B29 | P:B29 | P:B29 | P:B29 | P:R11 | P:B29 | P:B29 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Windows | M9 | terminal | P:B29 | P:B29 | P:B29 | P:B29 | N:XHD | N:X6P | P:B29 | P:B29 | P:B29 | P:B29 | P:R11 | P:B29 | P:B29 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Windows | M10 | native | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | P:W | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Windows | M10 | Tk | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | P:B29 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Windows | M10 | terminal | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | P:B29 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Windows | M11 | native | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Windows | M11 | Tk | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Windows | M11 | terminal | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Linux | M0 | native | P:L | P:L | P:L | P:L+H | P:L+H | P:T+H | P:K07 | P:L+H | P:L+H | P:L | P:R11 | P:L | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Linux | M0 | Tk | P:L19 | P:L19 | P:L19 | P:C29 | N:XHD | N:XTD | P:L19 | P:D29 | P:D29 | P:L19 | P:R11 | P:L19 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Linux | M0 | terminal | P:L19 | P:L19 | P:L19 | P:C29 | N:XHD | N:XTD | P:L19 | P:D29 | P:D29 | P:L19 | P:R11 | P:L19 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Linux | M1 | native | P:L | P:L | P:L | P:C28 | N:XHD | N:X6 | P:K28 | P:D28 | P:L | P:L | P:R11 | P:L | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Linux | M1 | Tk | P:B29 | P:B29 | P:B29 | P:B29 | N:XHD | N:X6 | P:B29 | P:B29 | P:B29 | P:B29 | P:R11 | P:B29 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Linux | M1 | terminal | P:B29 | P:B29 | P:B29 | P:B29 | N:XHD | N:X6 | P:B29 | P:B29 | P:B29 | P:B29 | P:R11 | P:B29 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Linux | M2 | native | P:L | P:L | P:L | P:C28 | N:XHD | N:X6 | P:K29 | P:D28 | P:L | P:L | P:R11 | P:L | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Linux | M2 | Tk | P:B29 | P:B29 | P:B29 | P:B29 | N:XHD | N:X6 | P:B29 | P:B29 | P:B29 | P:B29 | P:R11 | P:B29 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Linux | M2 | terminal | P:B29 | P:B29 | P:B29 | P:B29 | N:XHD | N:X6 | P:B29 | P:B29 | P:B29 | P:B29 | P:R11 | P:B29 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Linux | M3 | native | P:L | P:L | P:L | N:XE | N:XE | N:X6 | P:K29 | N:XE | P:L | P:L | P:R11 | P:L | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Linux | M3 | Tk | P:B29 | P:B29 | P:B29 | N:XE | N:XE | N:X6 | P:B29 | N:XE | P:B29 | P:B29 | P:R11 | P:B29 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Linux | M3 | terminal | P:B29 | P:B29 | P:B29 | N:XE | N:XE | N:X6 | P:B29 | N:XE | P:B29 | P:B29 | P:R11 | P:B29 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Linux | M4 | native | P:L | P:L | P:L | P:C29 | N:XHD | N:X6 | P:K29 | P:L | P:L | P:L | P:R11 | P:L | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Linux | M4 | Tk | P:B29 | P:B29 | P:B29 | P:B29 | N:XHD | N:X6 | P:B29 | P:B29 | P:B29 | P:B29 | P:R11 | P:B29 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Linux | M4 | terminal | P:B29 | P:B29 | P:B29 | P:B29 | N:XHD | N:X6 | P:B29 | P:B29 | P:B29 | P:B29 | P:R11 | P:B29 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Linux | M5 | native | P:L | P:L | P:L | N:XE | N:XE | N:X6 | P:K29 | N:XE | P:L | P:L | P:R11 | P:L | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Linux | M5 | Tk | P:B29 | P:B29 | P:B29 | N:XE | N:XE | N:X6 | P:B29 | N:XE | P:B29 | P:B29 | P:R11 | P:B29 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Linux | M5 | terminal | P:B29 | P:B29 | P:B29 | N:XE | N:XE | N:X6 | P:B29 | N:XE | P:B29 | P:B29 | P:R11 | P:B29 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Linux | M6 | native | P:L | P:L | P:L | N:XE | N:XE | N:X6 | P:K29 | N:XE | P:L | P:L | P:R11 | P:L | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Linux | M6 | Tk | P:B29 | P:B29 | P:B29 | N:XE | N:XE | N:X6 | P:B29 | N:XE | P:B29 | P:B29 | P:R11 | P:B29 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Linux | M6 | terminal | P:B29 | P:B29 | P:B29 | N:XE | N:XE | N:X6 | P:B29 | N:XE | P:B29 | P:B29 | P:R11 | P:B29 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Linux | M7 | native | P:L | P:L | N:X3 | N:XE | N:XE | N:X6 | P:K29 | N:XE | P:L | P:L | P:R11 | P:L | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Linux | M7 | Tk | P:B29 | P:B29 | N:X3 | N:XE | N:XE | N:X6 | P:B29 | N:XE | P:B29 | P:B29 | P:R11 | P:B29 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Linux | M7 | terminal | P:B29 | P:B29 | N:X3 | N:XE | N:XE | N:X6 | P:B29 | N:XE | P:B29 | P:B29 | P:R11 | P:B29 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Linux | M8 | native | P:L | P:L | P:L | P:C29 | N:XHD | N:X6P | P:K29 | P:L | P:L | P:L | P:R11 | P:L | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Linux | M8 | Tk | P:B29 | P:B29 | P:B29 | P:B29 | N:XHD | N:X6P | P:B29 | P:B29 | P:B29 | P:B29 | P:R11 | P:B29 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Linux | M8 | terminal | P:B29 | P:B29 | P:B29 | P:B29 | N:XHD | N:X6P | P:B29 | P:B29 | P:B29 | P:B29 | P:R11 | P:B29 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Linux | M9 | native | P:L | P:L | P:L | P:C28 | N:XHD | N:X6P | P:K29 | P:D28 | P:D28 | P:L | P:R11 | P:L | P:L | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Linux | M9 | Tk | P:B29 | P:B29 | P:B29 | P:B29 | N:XHD | N:X6P | P:B29 | P:B29 | P:B29 | P:B29 | P:R11 | P:B29 | P:B29 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Linux | M9 | terminal | P:B29 | P:B29 | P:B29 | P:B29 | N:XHD | N:X6P | P:B29 | P:B29 | P:B29 | P:B29 | P:R11 | P:B29 | P:B29 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Linux | M10 | native | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | P:I13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Linux | M10 | Tk | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | P:B29 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Linux | M10 | terminal | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | P:B29 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Linux | M11 | native | N:X11N | N:X11N | N:X11N | N:X11N | N:X11N | N:X6 | N:X11N | N:X11N | N:X11N | N:X11N | N:X11N | N:X11N | N:X11N | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Linux | M11 | Tk | P:L20 | P:L20 | P:L20 | P:C29 | N:XHD | N:X6 | P:L20 | P:L20 | P:L20 | P:L20 | P:R11 | P:L20 | P:L20 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Linux | M11 | terminal | P:L20 | P:L20 | P:L20 | P:C29 | N:XHD | N:X6 | P:L20 | P:L20 | P:L20 | P:L20 | P:R11 | P:L20 | P:L20 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| macOS | M0 | native | P:A43 | P:A43 | P:A43 | P:A43+H | P:A43+H | P:T+H | P:K07 | P:A43+H | P:A43+H | P:A43 | P:R11 | P:A43 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| macOS | M0 | Tk | P:A24 | P:A24 | P:A24 | P:C29 | N:XHD | N:XTD | P:A24 | P:D29 | P:D29 | P:A24 | P:R11 | P:A24 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| macOS | M0 | terminal | P:A24 | P:A24 | P:A24 | P:C29 | N:XHD | N:XTD | P:A24 | P:D29 | P:D29 | P:A24 | P:R11 | P:A24 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| macOS | M1 | native | P:A43 | P:A43 | P:A43 | P:C28 | N:XHD | N:X6 | P:A43 | P:D28 | P:A43 | P:A43 | P:R11 | P:A43 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| macOS | M1 | Tk | P:B29 | P:B29 | P:B29 | P:B29 | N:XHD | N:X6 | P:B29 | P:B29 | P:B29 | P:B29 | P:R11 | P:B29 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| macOS | M1 | terminal | P:B29 | P:B29 | P:B29 | P:B29 | N:XHD | N:X6 | P:B29 | P:B29 | P:B29 | P:B29 | P:R11 | P:B29 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| macOS | M2 | native | P:A43 | P:A43 | P:A43 | P:C28 | N:XHD | N:X6 | P:K29 | P:D28 | P:A43 | P:A43 | P:R11 | P:A43 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| macOS | M2 | Tk | P:B29 | P:B29 | P:B29 | P:B29 | N:XHD | N:X6 | P:B29 | P:B29 | P:B29 | P:B29 | P:R11 | P:B29 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| macOS | M2 | terminal | P:B29 | P:B29 | P:B29 | P:B29 | N:XHD | N:X6 | P:B29 | P:B29 | P:B29 | P:B29 | P:R11 | P:B29 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| macOS | M3 | native | P:A43 | P:A43 | P:A43 | N:XE | N:XE | N:X6 | P:K29 | N:XE | P:A43 | P:A43 | P:R11 | P:A43 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| macOS | M3 | Tk | P:B29 | P:B29 | P:B29 | N:XE | N:XE | N:X6 | P:B29 | N:XE | P:B29 | P:B29 | P:R11 | P:B29 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| macOS | M3 | terminal | P:B29 | P:B29 | P:B29 | N:XE | N:XE | N:X6 | P:B29 | N:XE | P:B29 | P:B29 | P:R11 | P:B29 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| macOS | M4 | native | P:A43 | P:A43 | P:A43 | P:C29 | N:XHD | N:X6 | P:A43 | P:A43 | P:A43 | P:A43 | P:R11 | P:A43 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| macOS | M4 | Tk | P:B29 | P:B29 | P:B29 | P:B29 | N:XHD | N:X6 | P:B29 | P:B29 | P:B29 | P:B29 | P:R11 | P:B29 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| macOS | M4 | terminal | P:B29 | P:B29 | P:B29 | P:B29 | N:XHD | N:X6 | P:B29 | P:B29 | P:B29 | P:B29 | P:R11 | P:B29 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| macOS | M5 | native | P:A43 | P:A43 | P:A43 | N:XE | N:XE | N:X6 | P:K29 | N:XE | P:A43 | P:A43 | P:R11 | P:A43 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| macOS | M5 | Tk | P:B29 | P:B29 | P:B29 | N:XE | N:XE | N:X6 | P:B29 | N:XE | P:B29 | P:B29 | P:R11 | P:B29 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| macOS | M5 | terminal | P:B29 | P:B29 | P:B29 | N:XE | N:XE | N:X6 | P:B29 | N:XE | P:B29 | P:B29 | P:R11 | P:B29 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| macOS | M6 | native | P:A43 | P:A43 | P:A43 | N:XE | N:XE | N:X6 | P:A43 | N:XE | P:A43 | P:A43 | P:R11 | P:A43 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| macOS | M6 | Tk | P:B29 | P:B29 | P:B29 | N:XE | N:XE | N:X6 | P:B29 | N:XE | P:B29 | P:B29 | P:R11 | P:B29 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| macOS | M6 | terminal | P:B29 | P:B29 | P:B29 | N:XE | N:XE | N:X6 | P:B29 | N:XE | P:B29 | P:B29 | P:R11 | P:B29 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| macOS | M7 | native | P:A43 | P:A43 | N:X3 | N:XE | N:XE | N:X6 | P:A43 | N:XE | P:A43 | P:A43 | P:R11 | P:A43 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| macOS | M7 | Tk | P:B29 | P:B29 | N:X3 | N:XE | N:XE | N:X6 | P:B29 | N:XE | P:B29 | P:B29 | P:R11 | P:B29 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| macOS | M7 | terminal | P:B29 | P:B29 | N:X3 | N:XE | N:XE | N:X6 | P:B29 | N:XE | P:B29 | P:B29 | P:R11 | P:B29 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| macOS | M8 | native | P:A43 | P:A43 | P:A43 | P:C29 | N:XHD | N:X6P | P:K29 | P:A43 | P:A43 | P:A43 | P:R11 | P:A43 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| macOS | M8 | Tk | P:B29 | P:B29 | P:B29 | P:B29 | N:XHD | N:X6P | P:B29 | P:B29 | P:B29 | P:B29 | P:R11 | P:B29 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| macOS | M8 | terminal | P:B29 | P:B29 | P:B29 | P:B29 | N:XHD | N:X6P | P:B29 | P:B29 | P:B29 | P:B29 | P:R11 | P:B29 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| macOS | M9 | native | P:A43 | P:A43 | P:A43 | P:C28 | N:XHD | N:X6P | P:K29 | P:D28 | P:D28 | P:A43 | P:R11 | P:A43 | P:A43 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| macOS | M9 | Tk | P:B29 | P:B29 | P:B29 | P:B29 | N:XHD | N:X6P | P:B29 | P:B29 | P:B29 | P:B29 | P:R11 | P:B29 | P:B29 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| macOS | M9 | terminal | P:B29 | P:B29 | P:B29 | P:B29 | N:XHD | N:X6P | P:B29 | P:B29 | P:B29 | P:B29 | P:R11 | P:B29 | P:B29 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| macOS | M10 | native | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | P:I13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| macOS | M10 | Tk | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | P:B29 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| macOS | M10 | terminal | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | P:B29 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| macOS | M11 | native | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| macOS | M11 | Tk | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| macOS | M11 | terminal | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |


## 4. Shared static verdicts / 共通静的判定（1447）

Supplemental update (1461, 1462, 1466): the 1447 statements in this section are retained as superseded history. Current IA-14–18 are all P (IA-15 P:S15). See the final section for the remaining 59 unverified cells.

IA-14 P:S14; IA-15 U:V; IA-16 P:S16; IA-17 P:S17; IA-18 P:S18.

## 5. Remaining unverified / 現在の未確認（1447）

Supplemental update (1461, 1462, 1466): the 1447 statements in this section are retained as superseded history. Current IA-14–18 are all P (IA-15 P:S15). See the final section for the remaining 59 unverified cells.

All remaining gaps are U:B/C/H/T/K/Q/R/I/V in §3; apply the final code table reason/next method to each cell. Later sections resolve three-OS M0 manual/timing, macOS descendant cleanup and Linux M11 Tk/terminal IA-13. Missing provenance/backend/configuration evidence remains unverified.

## 6. Document validation for this update

2026-11-26: `python scripts/check-docs.py` reports zero findings; `git diff --check` passes. Checked 106 local links in the four new documents, named source sections, Windows ledger evidence paths, all six medians from the stored seven-value 1001 samples, bilingual structure and LF. Both plan files match HEAD; their decision tables are unchanged.

2026-11-28 (1445/1447): check-docs.py reports findings 0. All Markdown local-link target files exist: 39 per results ledger and 122 per audit, 322 total. Backticked remote .work locations are not local-link validation targets. Bilingual current 108×18 cells and counts match exactly. Both frozen plan SHA-256 values match. git diff --check also checked after removing trailing blank lines. This update is static reconciliation only.

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

## Historical snapshot / 初期表の履歴（2026-11-26、99afe6d）

The following preserves old values only; it is not the current verdict.

### Historical / 旧 3. IA by OS, configuration and backend

Adapter checks outside plan section 2’s narrower configuration scope are retained as supplemental evidence. Each cell’s original verdict, reason and scenario evidence are in the matching ia/configuration/backend row of its source ledger.json. The aggregate manual qualifications below take precedence. M11 is Linux-only: all IA-01–13 are N on Windows/macOS.

#### Windows

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

#### Linux

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

#### macOS

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

### Historical / 旧 4. Shared static verdicts for all OSes/configurations

| IA | 判定 / Verdict | 根拠・残件 / Evidence and remaining work |
|---|---|---|
| IA-14 | P | 1444 audit complete; D1–D4 resolved; proposed pass within audited scope / 1444照合完了、D1〜D4解消済み、照合範囲で合格案。末尾のIA-14節を参照 |
| IA-15 | P | Review §3 and validation §6; original plan/decisions unchanged |
| IA-16 | P | Review §4; 1140 §1–3 and plan §6 agree; no remeasurement |
| IA-17 | P | Review §5; six stored medians agree; no native additions |
| IA-18 | U | This ledger prepared; native/manual/timing and L/A provenance remain open |

### Historical / 旧 5. Unperformed/unverified work and update procedure

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

#### Append-only records for Claude

| 日付 / Date | IA / OS / Config / backend | run / tested / recorded | 自動 / 総合判定 Auto / Overall | 原ログ・SHA-256 / Raw logs | 機器・音経路 / Devices | 人の回答 / Human reply | 制約・次の方法 / Limits, next method |
|---|---|---|---|---|---|---|---|
| — | — | — | — | — | — | — | — |

Append each new run separately, retaining earlier failures/gaps and the reason for supersession. Link human-reply.json to raw hashes; distinguish supplied summaries from direct logs. Update matching bilingual keys together; automatic results alone never pass MNL or timing.


## IA-15: plan, results and history reconciliation (1445)

The bilingual plans agree on §2 IA-01–18, §4 M0–M11, §7 MNL steps, §8 33.34/50 ms, 16,666,667 ns, 1,200/1,199 frames, two pairs extended to four at 80%, PCM 48,000 Hz/512/4,096 and underrun 0, and final B/B/B, D1–D5 A, IA-11 B decisions. Frozen hashes match the recorded values; plans remain unchanged.

Discrepancies: initial §3/5 did not reflect later completions, and initial IA-15 P/IA-18 prepared wording could appear current. Replaced current tables and preserved original tables as history. Explicit precedence: A7 over macOS A6; 1443 over the 1426 cleanup gap; the post-1442 MNL-03a repeat over the first failure. IA-14 remains limited to the audited scope.

**Proposed verdict: IA-15 unverified**. IA IDs/configurations/limits/procedures and current classifications/gap reasons agree bilingually, but missing L19 run IDs and original L/A manifests, tested revisions/dirty diffs, recording revisions and raw hashes cannot be supplied by editing prose. A43 tested 73b782c, A7 tested 6b6a7ac plus the 1440 working tree, and human runs tested 58fa00a plus 1442 are distinct binaries. Recording base: `22cfba22e7cebb82d0a8fc9e9da964fc9f7ec9fc` plus this working-tree update (2026-11-28). Remote .work paths are transcribed locations, not claims of local existence.

## Final aggregation (1447)

2026-11-28, Roku. These are proposed verdicts; Lemon decides overall acceptance. Section 3 now contains the complete current cell table defined here.

3 OSes × 12 configurations × 3 backends × 18 IAs = **1,944 cells**. P=pass, F=fail, U=unverified, N=N/A. Each status:evidence-code cell expands through the code table together with its OS/config/backend to evidence, reason and next method. Unperformed tests are never N/A. Cells beyond plan §2 configuration scope are supplemental; their U status does not create new mandatory 1057 work. Shared static checks repeat across 108 rows, so counts are not independent test counts.

| OS | P | F | U | N |
|---|---:|---:|---:|---:|
| Windows | 226 | 0 | 260 | 162 |
| Linux | 175 | 0 | 347 | 126 |
| macOS | 225 | 0 | 261 | 162 |
| Total / 合計 | 626 | 0 | 868 | 450 |

| Unverified code / 未確認コード | Cells / セル数 |
|---|---:|
| U:B | 552 |
| U:C | 23 |
| U:H | 47 |
| U:I | 2 |
| U:K | 18 |
| U:Q | 68 |
| U:R | 38 |
| U:T | 12 |
| U:V | 108 |

| Code | Evidence / 根拠、理由と次の確認方法 |
|---|---|
| W / W1 / WT / WC | §2 Windows run IDs and hashes; W1 replaces W/M1 / §2の実行版・原ログ。 |
| L | §2 L (`20261126-193548-e41e290a`), supplied Linux 1413 functional summary / Linux機の要約、原manifestは未取得。 |
| L19 | Linux M0 Tk/terminal 1419: supplied completion in the 1445/1447 request, corroborated by the 1424 comparison; run IDs/hashes not recorded here / 今回の依頼の確定情報、1424の比較記述。run ID等の不足はV。 |
| L20 | “Linux M11 … (1420)” / 「LinuxのM11…（1420）」: Tk `20261126-212518-c4bf82b5`, terminal `20261126-193339-3d89dcf4`. |
| A43 | “macOS rerun under eslogger … (1443)” / 「macOSのeslogger…（1443）」: `20261127-210221-a3d08a10`, tested `73b782c`, 164 cases, `.work/1443-eslogger.jsonl`, `.work/1443-process-tree.txt`; supersedes A/1423 for fixed M0–M9. |
| A24 | macOS M0 Tk/terminal (1424): `20261126-212155-d3dee35b` / `20261126-212545-283a799a`; eslogger in that section / 同節の寿命追跡。 |
| H | OS-specific MNL section 1418 / 1422 / 1426+1442+1443; each unit's run ID remains in its table. Applies only to M0/native / 人の観察はM0/nativeのみ。Mac回収はレモンの決定Aによる対応付け。 |
| T | Windows 1417 `.work/1417-runs4.txt`, `1417-runs4-extra.txt`; Linux 1421 `.work/1421-runs.txt`; macOS A7/1425+1440 `.work/1425b-runs.txt`. Remote indexes are recorded locations, not locally validated files / 遠隔機の索引は本作業で取得していない。 |
| S14 / S16 / S17 / S18 | Last IA-14 audit section / IA-16–17 (1446) / final aggregation (1447), respectively; shared static evidence, not runtime runs / 静的照合を全セルへ展開。 |
| U:B | Backend/configuration has no recorded run; run applicable functional scenarios on that OS/config/backend and retain manifest/ledger/raw hashes. No hardware exclusion / 未実行backend・構成。同条件の自動実行と原記録を取得。 |
| U:C | Automatic reconciliation exists but complete IA-04 close/termination evidence is not recorded for this cell; inspect its sequence/provider ledger and perform the applicable close/input/deadline observation / 自動照合と手作業を同セルで結ぶ。窓なしでは入力・期限による終了を確認。 |
| U:H | Required human observation absent for this configuration/backend, or scenario outside the tested M0-only IA-05 scope; perform relevant MNL-01/03/04/05 and retain reply/raw hash / M0の観察を流用しない。 |
| U:T | No formal IA-06 baseline/load pairs and listening for this cell; use frozen §8 and MNL-02 if extending scope. Non-M0 is supplemental, not a new plan requirement / 非M0・非nativeへの追加確認は計画拡張時のみ。 |
| U:K | Native capability/unsupported-wait or non-EXTENSION graphics observation missing; collect capabilities, rejection where unsupported, and deadline/input/cancellation termination on this backend / IA-07能力観察を同じ実行で記録。 |
| U:Q | Linux L has OS-level functional passes, but §2 and the historical table leave the backend unknown. Do not allocate these passes to native; import the original manifest/backend and assign the existing evidence, or rerun on the specified backend / Linux自動合格は維持するがbackend未取得のためnativeセルを未確認とする。 |
| U:R | Append/startup passes do not prove full restore. Per OS, link bound PCM/task/window and D2 real child/pipe Zig test outputs; additionally test actual pending native paint/restore for graphics. Substituted window tests remain substituted / IA-11完全復元の実行記録と実paint競合が不足。 |
| U:I | Linux/macOS M10 static image-boundary verdict absent; inspect existing C11 image/58-word records and link exact evidence for no SAVESYS/APP words; no saved app / M10は新たな保存起動を要求しない。 |
| U:V | Later run provenance incomplete: import remote manifest, tested HEAD+dirty diff, recording revision, binary/tool hashes, OS/backend/audio route and raw-log hashes; link human replies. Keep unknown fields unknown / 実行版・記録版・生ログの不足を埋めるまでIA-15全体は未確認。 |
| N:X11 | M11 is Linux-only by design / M11は設計上Linux専用。 |
| N:X10 | image=false: saved-app conditions IA-01–12 excluded / 保存題材が設計上存在しない。 |
| N:X3 | M7 has no staged runtime resource acquisitions / 故障注入対象資源なし。 |
| N:XE | EXTENSION/public tasks or composite wait excluded / 公開task・複合待機を除外。 |
| N:X6 | Integrated task+PCM+graphics response cannot exist with a required group excluded / 必須のaudio・graphics・extensionのいずれかを除外。 |
| N:X13 | This configuration has none of the M9/M10/M11 debug/image/X11 exclusion boundaries / IA-13で指定する除外境界を持たない。 |

### Proposed overall verdict

Pass within the cited scope: three-OS functional summaries, M0 human observations and IA-06 numerical measurements. Linux L functional passes are not assigned to a backend until its manifest is imported. Tk/terminal retain only their separately recorded automated checks and IA-07; native timing/observations are not transferred. Proposed passes: IA-14 within its audit scope, IA-16/17 as decision reconciliation, and IA-18 as complete classification/aggregation including gaps. No current cell fails; this does not erase historical failures.

**Propose keeping overall 1057 unverified**. Required gaps that propose blocking completion: IA-07 M0/native on three OSes, IA-11 M0/M9 full restore/actual paint concurrency, Linux/macOS M10 IA-13, and IA-15 provenance including the Linux L backend assignment. For IA-04/08/09 gaps such as M1/M2/M9, supplement evidence only for branches applicable under plan §2. M0 manual passes cannot fill other configurations. Supplemental untested backend/configuration cells beyond the plan do not alone block completion. Lemon decides final scope and acceptance.

Cross-builds do not establish native execution. IA-16 WSL/pacat/RDPSink and native Apple II/PipeWire are distinct historical routes, not substitutes for the current Linux desktop acceptance. The 1422 Xvfb/scripted runs are not human acceptance. IA-11 substituted windows do not establish actual paint concurrency. Physical presentation is outside measurement endpoints. R6 real DwmFlush-unavailable environments remain unperformed and excluded from completion by Lemon; do not request them again or transfer that exclusion to other cells.


## 07:02 status table (superseded history)

| OS | Config | backend | IA-01 | IA-02 | IA-03 | IA-04 | IA-05 | IA-06 | IA-07 | IA-08 | IA-09 | IA-10 | IA-11 | IA-12 | IA-13 | IA-14 | IA-15 | IA-16 | IA-17 | IA-18 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Windows | M0 | native | P:W | P:W | P:W | P:W+H | P:W+H | P:T+H | U:K | P:W+H | P:W+H | P:W | U:R | P:W | N:X13 | P:S14 | U:V | P:S16 | P:S17 | P:S18 |
| Windows | M0 | Tk | P:WT | P:WT | P:WT | U:C | U:H | U:T | P:WT | U:H | U:H | P:WT | U:R | P:WT | N:X13 | P:S14 | U:V | P:S16 | P:S17 | P:S18 |
| Windows | M0 | terminal | P:WC | P:WC | P:WC | U:C | U:H | U:T | P:WC | U:H | U:H | P:WC | U:R | P:WC | N:X13 | P:S14 | U:V | P:S16 | P:S17 | P:S18 |
| Windows | M1 | native | P:W1 | P:W1 | P:W1 | U:C | U:H | N:X6 | P:W1 | U:H | P:W1 | P:W1 | U:R | P:W1 | N:X13 | P:S14 | U:V | P:S16 | P:S17 | P:S18 |
| Windows | M1 | Tk | U:B | U:B | U:B | U:B | U:B | N:X6 | U:B | U:B | U:B | U:B | U:B | U:B | N:X13 | P:S14 | U:V | P:S16 | P:S17 | P:S18 |
| Windows | M1 | terminal | U:B | U:B | U:B | U:B | U:B | N:X6 | U:B | U:B | U:B | U:B | U:B | U:B | N:X13 | P:S14 | U:V | P:S16 | P:S17 | P:S18 |
| Windows | M2 | native | P:W | P:W | P:W | U:C | U:H | N:X6 | U:K | U:H | P:W | P:W | U:R | P:W | N:X13 | P:S14 | U:V | P:S16 | P:S17 | P:S18 |
| Windows | M2 | Tk | U:B | U:B | U:B | U:B | U:B | N:X6 | U:B | U:B | U:B | U:B | U:B | U:B | N:X13 | P:S14 | U:V | P:S16 | P:S17 | P:S18 |
| Windows | M2 | terminal | U:B | U:B | U:B | U:B | U:B | N:X6 | U:B | U:B | U:B | U:B | U:B | U:B | N:X13 | P:S14 | U:V | P:S16 | P:S17 | P:S18 |
| Windows | M3 | native | P:W | P:W | P:W | N:XE | N:XE | N:X6 | U:K | N:XE | P:W | P:W | U:R | P:W | N:X13 | P:S14 | U:V | P:S16 | P:S17 | P:S18 |
| Windows | M3 | Tk | U:B | U:B | U:B | N:XE | N:XE | N:X6 | U:B | N:XE | U:B | U:B | U:B | U:B | N:X13 | P:S14 | U:V | P:S16 | P:S17 | P:S18 |
| Windows | M3 | terminal | U:B | U:B | U:B | N:XE | N:XE | N:X6 | U:B | N:XE | U:B | U:B | U:B | U:B | N:X13 | P:S14 | U:V | P:S16 | P:S17 | P:S18 |
| Windows | M4 | native | P:W | P:W | P:W | U:C | U:H | N:X6 | P:W | P:W | P:W | P:W | U:R | P:W | N:X13 | P:S14 | U:V | P:S16 | P:S17 | P:S18 |
| Windows | M4 | Tk | U:B | U:B | U:B | U:B | U:B | N:X6 | U:B | U:B | U:B | U:B | U:B | U:B | N:X13 | P:S14 | U:V | P:S16 | P:S17 | P:S18 |
| Windows | M4 | terminal | U:B | U:B | U:B | U:B | U:B | N:X6 | U:B | U:B | U:B | U:B | U:B | U:B | N:X13 | P:S14 | U:V | P:S16 | P:S17 | P:S18 |
| Windows | M5 | native | P:W | P:W | P:W | N:XE | N:XE | N:X6 | U:K | N:XE | P:W | P:W | U:R | P:W | N:X13 | P:S14 | U:V | P:S16 | P:S17 | P:S18 |
| Windows | M5 | Tk | U:B | U:B | U:B | N:XE | N:XE | N:X6 | U:B | N:XE | U:B | U:B | U:B | U:B | N:X13 | P:S14 | U:V | P:S16 | P:S17 | P:S18 |
| Windows | M5 | terminal | U:B | U:B | U:B | N:XE | N:XE | N:X6 | U:B | N:XE | U:B | U:B | U:B | U:B | N:X13 | P:S14 | U:V | P:S16 | P:S17 | P:S18 |
| Windows | M6 | native | P:W | P:W | P:W | N:XE | N:XE | N:X6 | P:W | N:XE | P:W | P:W | U:R | P:W | N:X13 | P:S14 | U:V | P:S16 | P:S17 | P:S18 |
| Windows | M6 | Tk | U:B | U:B | U:B | N:XE | N:XE | N:X6 | U:B | N:XE | U:B | U:B | U:B | U:B | N:X13 | P:S14 | U:V | P:S16 | P:S17 | P:S18 |
| Windows | M6 | terminal | U:B | U:B | U:B | N:XE | N:XE | N:X6 | U:B | N:XE | U:B | U:B | U:B | U:B | N:X13 | P:S14 | U:V | P:S16 | P:S17 | P:S18 |
| Windows | M7 | native | P:W | P:W | N:X3 | N:XE | N:XE | N:X6 | P:W | N:XE | P:W | P:W | U:R | P:W | N:X13 | P:S14 | U:V | P:S16 | P:S17 | P:S18 |
| Windows | M7 | Tk | U:B | U:B | N:X3 | N:XE | N:XE | N:X6 | U:B | N:XE | U:B | U:B | U:B | U:B | N:X13 | P:S14 | U:V | P:S16 | P:S17 | P:S18 |
| Windows | M7 | terminal | U:B | U:B | N:X3 | N:XE | N:XE | N:X6 | U:B | N:XE | U:B | U:B | U:B | U:B | N:X13 | P:S14 | U:V | P:S16 | P:S17 | P:S18 |
| Windows | M8 | native | P:W | P:W | P:W | U:C | U:H | U:T | U:K | P:W | P:W | P:W | U:R | P:W | N:X13 | P:S14 | U:V | P:S16 | P:S17 | P:S18 |
| Windows | M8 | Tk | U:B | U:B | U:B | U:B | U:B | U:B | U:B | U:B | U:B | U:B | U:B | U:B | N:X13 | P:S14 | U:V | P:S16 | P:S17 | P:S18 |
| Windows | M8 | terminal | U:B | U:B | U:B | U:B | U:B | U:B | U:B | U:B | U:B | U:B | U:B | U:B | N:X13 | P:S14 | U:V | P:S16 | P:S17 | P:S18 |
| Windows | M9 | native | P:W | P:W | P:W | U:C | U:H | U:T | U:K | U:H | U:H | P:W | U:R | P:W | P:W | P:S14 | U:V | P:S16 | P:S17 | P:S18 |
| Windows | M9 | Tk | U:B | U:B | U:B | U:B | U:B | U:B | U:B | U:B | U:B | U:B | U:B | U:B | U:B | P:S14 | U:V | P:S16 | P:S17 | P:S18 |
| Windows | M9 | terminal | U:B | U:B | U:B | U:B | U:B | U:B | U:B | U:B | U:B | U:B | U:B | U:B | U:B | P:S14 | U:V | P:S16 | P:S17 | P:S18 |
| Windows | M10 | native | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | P:W | P:S14 | U:V | P:S16 | P:S17 | P:S18 |
| Windows | M10 | Tk | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | U:B | P:S14 | U:V | P:S16 | P:S17 | P:S18 |
| Windows | M10 | terminal | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | U:B | P:S14 | U:V | P:S16 | P:S17 | P:S18 |
| Windows | M11 | native | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | P:S14 | U:V | P:S16 | P:S17 | P:S18 |
| Windows | M11 | Tk | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | P:S14 | U:V | P:S16 | P:S17 | P:S18 |
| Windows | M11 | terminal | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | P:S14 | U:V | P:S16 | P:S17 | P:S18 |
| Linux | M0 | native | U:Q | U:Q | U:Q | U:Q | U:Q | P:T+H | U:K | U:Q | U:Q | U:Q | U:R | U:Q | N:X13 | P:S14 | U:V | P:S16 | P:S17 | P:S18 |
| Linux | M0 | Tk | P:L19 | P:L19 | P:L19 | U:C | U:H | U:T | P:L19 | U:H | U:H | P:L19 | U:R | P:L19 | N:X13 | P:S14 | U:V | P:S16 | P:S17 | P:S18 |
| Linux | M0 | terminal | P:L19 | P:L19 | P:L19 | U:C | U:H | U:T | P:L19 | U:H | U:H | P:L19 | U:R | P:L19 | N:X13 | P:S14 | U:V | P:S16 | P:S17 | P:S18 |
| Linux | M1 | native | U:Q | U:Q | U:Q | U:C | U:H | N:X6 | U:Q | U:H | U:Q | U:Q | U:R | U:Q | N:X13 | P:S14 | U:V | P:S16 | P:S17 | P:S18 |
| Linux | M1 | Tk | U:B | U:B | U:B | U:B | U:B | N:X6 | U:B | U:B | U:B | U:B | U:B | U:B | N:X13 | P:S14 | U:V | P:S16 | P:S17 | P:S18 |
| Linux | M1 | terminal | U:B | U:B | U:B | U:B | U:B | N:X6 | U:B | U:B | U:B | U:B | U:B | U:B | N:X13 | P:S14 | U:V | P:S16 | P:S17 | P:S18 |
| Linux | M2 | native | U:Q | U:Q | U:Q | U:C | U:H | N:X6 | U:K | U:H | U:Q | U:Q | U:R | U:Q | N:X13 | P:S14 | U:V | P:S16 | P:S17 | P:S18 |
| Linux | M2 | Tk | U:B | U:B | U:B | U:B | U:B | N:X6 | U:B | U:B | U:B | U:B | U:B | U:B | N:X13 | P:S14 | U:V | P:S16 | P:S17 | P:S18 |
| Linux | M2 | terminal | U:B | U:B | U:B | U:B | U:B | N:X6 | U:B | U:B | U:B | U:B | U:B | U:B | N:X13 | P:S14 | U:V | P:S16 | P:S17 | P:S18 |
| Linux | M3 | native | U:Q | U:Q | U:Q | N:XE | N:XE | N:X6 | U:K | N:XE | U:Q | U:Q | U:R | U:Q | N:X13 | P:S14 | U:V | P:S16 | P:S17 | P:S18 |
| Linux | M3 | Tk | U:B | U:B | U:B | N:XE | N:XE | N:X6 | U:B | N:XE | U:B | U:B | U:B | U:B | N:X13 | P:S14 | U:V | P:S16 | P:S17 | P:S18 |
| Linux | M3 | terminal | U:B | U:B | U:B | N:XE | N:XE | N:X6 | U:B | N:XE | U:B | U:B | U:B | U:B | N:X13 | P:S14 | U:V | P:S16 | P:S17 | P:S18 |
| Linux | M4 | native | U:Q | U:Q | U:Q | U:C | U:H | N:X6 | U:Q | U:Q | U:Q | U:Q | U:R | U:Q | N:X13 | P:S14 | U:V | P:S16 | P:S17 | P:S18 |
| Linux | M4 | Tk | U:B | U:B | U:B | U:B | U:B | N:X6 | U:B | U:B | U:B | U:B | U:B | U:B | N:X13 | P:S14 | U:V | P:S16 | P:S17 | P:S18 |
| Linux | M4 | terminal | U:B | U:B | U:B | U:B | U:B | N:X6 | U:B | U:B | U:B | U:B | U:B | U:B | N:X13 | P:S14 | U:V | P:S16 | P:S17 | P:S18 |
| Linux | M5 | native | U:Q | U:Q | U:Q | N:XE | N:XE | N:X6 | U:K | N:XE | U:Q | U:Q | U:R | U:Q | N:X13 | P:S14 | U:V | P:S16 | P:S17 | P:S18 |
| Linux | M5 | Tk | U:B | U:B | U:B | N:XE | N:XE | N:X6 | U:B | N:XE | U:B | U:B | U:B | U:B | N:X13 | P:S14 | U:V | P:S16 | P:S17 | P:S18 |
| Linux | M5 | terminal | U:B | U:B | U:B | N:XE | N:XE | N:X6 | U:B | N:XE | U:B | U:B | U:B | U:B | N:X13 | P:S14 | U:V | P:S16 | P:S17 | P:S18 |
| Linux | M6 | native | U:Q | U:Q | U:Q | N:XE | N:XE | N:X6 | U:Q | N:XE | U:Q | U:Q | U:R | U:Q | N:X13 | P:S14 | U:V | P:S16 | P:S17 | P:S18 |
| Linux | M6 | Tk | U:B | U:B | U:B | N:XE | N:XE | N:X6 | U:B | N:XE | U:B | U:B | U:B | U:B | N:X13 | P:S14 | U:V | P:S16 | P:S17 | P:S18 |
| Linux | M6 | terminal | U:B | U:B | U:B | N:XE | N:XE | N:X6 | U:B | N:XE | U:B | U:B | U:B | U:B | N:X13 | P:S14 | U:V | P:S16 | P:S17 | P:S18 |
| Linux | M7 | native | U:Q | U:Q | N:X3 | N:XE | N:XE | N:X6 | U:Q | N:XE | U:Q | U:Q | U:R | U:Q | N:X13 | P:S14 | U:V | P:S16 | P:S17 | P:S18 |
| Linux | M7 | Tk | U:B | U:B | N:X3 | N:XE | N:XE | N:X6 | U:B | N:XE | U:B | U:B | U:B | U:B | N:X13 | P:S14 | U:V | P:S16 | P:S17 | P:S18 |
| Linux | M7 | terminal | U:B | U:B | N:X3 | N:XE | N:XE | N:X6 | U:B | N:XE | U:B | U:B | U:B | U:B | N:X13 | P:S14 | U:V | P:S16 | P:S17 | P:S18 |
| Linux | M8 | native | U:Q | U:Q | U:Q | U:C | U:H | U:T | U:K | U:Q | U:Q | U:Q | U:R | U:Q | N:X13 | P:S14 | U:V | P:S16 | P:S17 | P:S18 |
| Linux | M8 | Tk | U:B | U:B | U:B | U:B | U:B | U:B | U:B | U:B | U:B | U:B | U:B | U:B | N:X13 | P:S14 | U:V | P:S16 | P:S17 | P:S18 |
| Linux | M8 | terminal | U:B | U:B | U:B | U:B | U:B | U:B | U:B | U:B | U:B | U:B | U:B | U:B | N:X13 | P:S14 | U:V | P:S16 | P:S17 | P:S18 |
| Linux | M9 | native | U:Q | U:Q | U:Q | U:C | U:H | U:T | U:K | U:H | U:H | U:Q | U:R | U:Q | U:Q | P:S14 | U:V | P:S16 | P:S17 | P:S18 |
| Linux | M9 | Tk | U:B | U:B | U:B | U:B | U:B | U:B | U:B | U:B | U:B | U:B | U:B | U:B | U:B | P:S14 | U:V | P:S16 | P:S17 | P:S18 |
| Linux | M9 | terminal | U:B | U:B | U:B | U:B | U:B | U:B | U:B | U:B | U:B | U:B | U:B | U:B | U:B | P:S14 | U:V | P:S16 | P:S17 | P:S18 |
| Linux | M10 | native | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | U:I | P:S14 | U:V | P:S16 | P:S17 | P:S18 |
| Linux | M10 | Tk | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | U:B | P:S14 | U:V | P:S16 | P:S17 | P:S18 |
| Linux | M10 | terminal | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | U:B | P:S14 | U:V | P:S16 | P:S17 | P:S18 |
| Linux | M11 | native | U:B | U:B | U:B | U:B | U:B | N:X6 | U:B | U:B | U:B | U:B | U:B | U:B | U:B | P:S14 | U:V | P:S16 | P:S17 | P:S18 |
| Linux | M11 | Tk | P:L20 | P:L20 | P:L20 | U:C | U:H | N:X6 | P:L20 | P:L20 | P:L20 | P:L20 | U:R | P:L20 | P:L20 | P:S14 | U:V | P:S16 | P:S17 | P:S18 |
| Linux | M11 | terminal | P:L20 | P:L20 | P:L20 | U:C | U:H | N:X6 | P:L20 | P:L20 | P:L20 | P:L20 | U:R | P:L20 | P:L20 | P:S14 | U:V | P:S16 | P:S17 | P:S18 |
| macOS | M0 | native | P:A43 | P:A43 | P:A43 | P:A43+H | P:A43+H | P:T+H | U:K | P:A43+H | P:A43+H | P:A43 | U:R | P:A43 | N:X13 | P:S14 | U:V | P:S16 | P:S17 | P:S18 |
| macOS | M0 | Tk | P:A24 | P:A24 | P:A24 | U:C | U:H | U:T | P:A24 | U:H | U:H | P:A24 | U:R | P:A24 | N:X13 | P:S14 | U:V | P:S16 | P:S17 | P:S18 |
| macOS | M0 | terminal | P:A24 | P:A24 | P:A24 | U:C | U:H | U:T | P:A24 | U:H | U:H | P:A24 | U:R | P:A24 | N:X13 | P:S14 | U:V | P:S16 | P:S17 | P:S18 |
| macOS | M1 | native | P:A43 | P:A43 | P:A43 | U:C | U:H | N:X6 | P:A43 | U:H | P:A43 | P:A43 | U:R | P:A43 | N:X13 | P:S14 | U:V | P:S16 | P:S17 | P:S18 |
| macOS | M1 | Tk | U:B | U:B | U:B | U:B | U:B | N:X6 | U:B | U:B | U:B | U:B | U:B | U:B | N:X13 | P:S14 | U:V | P:S16 | P:S17 | P:S18 |
| macOS | M1 | terminal | U:B | U:B | U:B | U:B | U:B | N:X6 | U:B | U:B | U:B | U:B | U:B | U:B | N:X13 | P:S14 | U:V | P:S16 | P:S17 | P:S18 |
| macOS | M2 | native | P:A43 | P:A43 | P:A43 | U:C | U:H | N:X6 | U:K | U:H | P:A43 | P:A43 | U:R | P:A43 | N:X13 | P:S14 | U:V | P:S16 | P:S17 | P:S18 |
| macOS | M2 | Tk | U:B | U:B | U:B | U:B | U:B | N:X6 | U:B | U:B | U:B | U:B | U:B | U:B | N:X13 | P:S14 | U:V | P:S16 | P:S17 | P:S18 |
| macOS | M2 | terminal | U:B | U:B | U:B | U:B | U:B | N:X6 | U:B | U:B | U:B | U:B | U:B | U:B | N:X13 | P:S14 | U:V | P:S16 | P:S17 | P:S18 |
| macOS | M3 | native | P:A43 | P:A43 | P:A43 | N:XE | N:XE | N:X6 | U:K | N:XE | P:A43 | P:A43 | U:R | P:A43 | N:X13 | P:S14 | U:V | P:S16 | P:S17 | P:S18 |
| macOS | M3 | Tk | U:B | U:B | U:B | N:XE | N:XE | N:X6 | U:B | N:XE | U:B | U:B | U:B | U:B | N:X13 | P:S14 | U:V | P:S16 | P:S17 | P:S18 |
| macOS | M3 | terminal | U:B | U:B | U:B | N:XE | N:XE | N:X6 | U:B | N:XE | U:B | U:B | U:B | U:B | N:X13 | P:S14 | U:V | P:S16 | P:S17 | P:S18 |
| macOS | M4 | native | P:A43 | P:A43 | P:A43 | U:C | U:H | N:X6 | P:A43 | P:A43 | P:A43 | P:A43 | U:R | P:A43 | N:X13 | P:S14 | U:V | P:S16 | P:S17 | P:S18 |
| macOS | M4 | Tk | U:B | U:B | U:B | U:B | U:B | N:X6 | U:B | U:B | U:B | U:B | U:B | U:B | N:X13 | P:S14 | U:V | P:S16 | P:S17 | P:S18 |
| macOS | M4 | terminal | U:B | U:B | U:B | U:B | U:B | N:X6 | U:B | U:B | U:B | U:B | U:B | U:B | N:X13 | P:S14 | U:V | P:S16 | P:S17 | P:S18 |
| macOS | M5 | native | P:A43 | P:A43 | P:A43 | N:XE | N:XE | N:X6 | U:K | N:XE | P:A43 | P:A43 | U:R | P:A43 | N:X13 | P:S14 | U:V | P:S16 | P:S17 | P:S18 |
| macOS | M5 | Tk | U:B | U:B | U:B | N:XE | N:XE | N:X6 | U:B | N:XE | U:B | U:B | U:B | U:B | N:X13 | P:S14 | U:V | P:S16 | P:S17 | P:S18 |
| macOS | M5 | terminal | U:B | U:B | U:B | N:XE | N:XE | N:X6 | U:B | N:XE | U:B | U:B | U:B | U:B | N:X13 | P:S14 | U:V | P:S16 | P:S17 | P:S18 |
| macOS | M6 | native | P:A43 | P:A43 | P:A43 | N:XE | N:XE | N:X6 | P:A43 | N:XE | P:A43 | P:A43 | U:R | P:A43 | N:X13 | P:S14 | U:V | P:S16 | P:S17 | P:S18 |
| macOS | M6 | Tk | U:B | U:B | U:B | N:XE | N:XE | N:X6 | U:B | N:XE | U:B | U:B | U:B | U:B | N:X13 | P:S14 | U:V | P:S16 | P:S17 | P:S18 |
| macOS | M6 | terminal | U:B | U:B | U:B | N:XE | N:XE | N:X6 | U:B | N:XE | U:B | U:B | U:B | U:B | N:X13 | P:S14 | U:V | P:S16 | P:S17 | P:S18 |
| macOS | M7 | native | P:A43 | P:A43 | N:X3 | N:XE | N:XE | N:X6 | P:A43 | N:XE | P:A43 | P:A43 | U:R | P:A43 | N:X13 | P:S14 | U:V | P:S16 | P:S17 | P:S18 |
| macOS | M7 | Tk | U:B | U:B | N:X3 | N:XE | N:XE | N:X6 | U:B | N:XE | U:B | U:B | U:B | U:B | N:X13 | P:S14 | U:V | P:S16 | P:S17 | P:S18 |
| macOS | M7 | terminal | U:B | U:B | N:X3 | N:XE | N:XE | N:X6 | U:B | N:XE | U:B | U:B | U:B | U:B | N:X13 | P:S14 | U:V | P:S16 | P:S17 | P:S18 |
| macOS | M8 | native | P:A43 | P:A43 | P:A43 | U:C | U:H | U:T | U:K | P:A43 | P:A43 | P:A43 | U:R | P:A43 | N:X13 | P:S14 | U:V | P:S16 | P:S17 | P:S18 |
| macOS | M8 | Tk | U:B | U:B | U:B | U:B | U:B | U:B | U:B | U:B | U:B | U:B | U:B | U:B | N:X13 | P:S14 | U:V | P:S16 | P:S17 | P:S18 |
| macOS | M8 | terminal | U:B | U:B | U:B | U:B | U:B | U:B | U:B | U:B | U:B | U:B | U:B | U:B | N:X13 | P:S14 | U:V | P:S16 | P:S17 | P:S18 |
| macOS | M9 | native | P:A43 | P:A43 | P:A43 | U:C | U:H | U:T | U:K | U:H | U:H | P:A43 | U:R | P:A43 | P:A43 | P:S14 | U:V | P:S16 | P:S17 | P:S18 |
| macOS | M9 | Tk | U:B | U:B | U:B | U:B | U:B | U:B | U:B | U:B | U:B | U:B | U:B | U:B | U:B | P:S14 | U:V | P:S16 | P:S17 | P:S18 |
| macOS | M9 | terminal | U:B | U:B | U:B | U:B | U:B | U:B | U:B | U:B | U:B | U:B | U:B | U:B | U:B | P:S14 | U:V | P:S16 | P:S17 | P:S18 |
| macOS | M10 | native | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | U:I | P:S14 | U:V | P:S16 | P:S17 | P:S18 |
| macOS | M10 | Tk | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | U:B | P:S14 | U:V | P:S16 | P:S17 | P:S18 |
| macOS | M10 | terminal | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | U:B | P:S14 | U:V | P:S16 | P:S17 | P:S18 |
| macOS | M11 | native | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | P:S14 | U:V | P:S16 | P:S17 | P:S18 |
| macOS | M11 | Tk | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | P:S14 | U:V | P:S16 | P:S17 | P:S18 |
| macOS | M11 | terminal | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | P:S14 | U:V | P:S16 | P:S17 | P:S18 |



## Re-aggregation (1451)

2026-11-28, Roku. Claude’s 07:4x checks are accepted as confirmed evidence supplied by Lemon; runtime tests were not rerun here. Local provenance JSON, Windows original records and test feature gates were inspected. These updated verdicts are proposals; Lemon decides overall acceptance.

| OS | P | F | U | N |
|---|---:|---:|---:|---:|
| Windows | 275 | 0 | 211 | 162 |
| Linux | 291 | 0 | 231 | 126 |
| macOS | 275 | 0 | 211 | 162 |
| Total / 合計 | 841 | 0 | 653 | 450 |

| Unverified code / 未確認コード | Cells / セル数 |
|---|---:|
| U:B | 552 |
| U:C | 23 |
| U:H | 47 |
| U:K | 19 |
| U:T | 12 |

All 1,944 cells were recounted. U:I/U:Q/U:R/U:V now have zero cells. Linux’s originally unverified IA-07 for M1/M4/M6/M7 becomes U:K; identifying the backend alone does not pass those checks.

| Code | Updated evidence and verdict scope |
|---|---|
| K07 | IA-07 M0/native passes on three OSes. tag=105 reason=2048: Windows 17/23 scenarios, 13,245 events; Linux 17 scenarios, 13,263; macOS 17 scenarios, 13,217. Normal draws/waits: 1199/1222, 1199/1871, 1199/1849 respectively; all IA-CLEAN error=0. Native completion waits occurred and composite waits terminated by deadline/input. Unsupported rejection passes separately in WT/WC, L19 and A24. |
| R11 | IA-11 passes within decision B: automated saved startup and resource-owning LOAD-DICTIONARY plus “1057 bound restore …” in src/tests/task_reap_test.zig and “1057 D2 …” in src/main.zig. Default builds execute them; only feature availability gates skipping. zig build test: Windows succeeds (same content as 22cfba2); Linux 1672/1724 passed, 52 skipped; macOS 1659/1714 passed, 55 skipped (both HEAD 22cfba2). Window host is substituted. Actual paint concurrency was not tested and is outside decision B. |
| I13 | M10/image-boundary: Linux `20261128-074434-f362c963`, macOS `20261128-074557-31b09102`, HEAD `22cfba2`; `[DEFINED] SAVESYS . [DEFINED] APP-ENTRY! . BYE` → `0 0`, status 0; no saved fixture; passes the same boundary as Windows W. |
| S15 | Provenance/history reconciliation is updated below; propose IA-15 pass. Unavailable device details remain unavailable. Supersedes the former blanket U:V verdict. |

### Provenance supplement (IA-15)

Indexes are stored in each machine’s `.work/1451-provenance-{windows,linux,macos}.json` (139/32/41 runs). Local JSON copies were inspected; this does not assert local availability of remote raw run trees. Indexes retain argv and manual units. Each run’s `working-tree.stdout` retains its diff; executable/saved-executable SHA-256 locations are `M*/binary.json`, fields `binary_sha256` / `app_sha256`. Index `binaries` values are null, so the indexes themselves do not supply hash values. Both fields were verified in Windows W/M0’s original record. Remote locations/results rely on supplied evidence.

| OS | run ID | Purpose / argv or manual unit | backend | HEAD | dirty lines | SHA-256 location |
|---|---|---|---|---|---:|---|
| windows | 20261126-192325-012b4581 | `--functional --configs M0 --backend tk --frames 240` | tk | `92617e7` | 107 | `M*/binary.json` |
| windows | 20261126-192425-c5f0d86e | `--functional --configs M0 --backend terminal --frames 240` | terminal | `92617e7` | 107 | `M*/binary.json` |
| windows | 20261126-193555-1be64edd | `--functional --configs M0 M1 M2 M3 M4 M5 M6 M7 M8 M9 M10` | native | `92617e7` | 148 | `M*/binary.json` |
| windows | 20261126-201122-54d17ba8 | `--functional --configs M1` | native | `92617e7` | 148 | `M*/binary.json` |
| windows | 20261126-214314-22fdffeb | `--manual MNL-01a --configs M0` | native | `765b6cc` | 0 | `M*/binary.json` |
| windows | 20261126-214846-207f770a | `--manual MNL-01b --configs M0` | native | `765b6cc` | 26 | `M*/binary.json` |
| windows | 20261126-214957-ffbb5770 | `--manual MNL-01b-f --configs M0` | native | `765b6cc` | 26 | `M*/binary.json` |
| windows | 20261126-215101-ce76c751 | `--manual MNL-02 --configs M0` | native | `765b6cc` | 26 | `M*/binary.json` |
| windows | 20261127-175012-bce2d422 | `--manual MNL-03a --configs M0` | native | `765b6cc` | 307 | `M*/binary.json` |
| windows | 20261127-175137-3a541c85 | `--manual MNL-03b --configs M0` | native | `765b6cc` | 307 | `M*/binary.json` |
| windows | 20261127-175338-a70ec686 | `--manual MNL-04 --configs M0` | native | `765b6cc` | 307 | `M*/binary.json` |
| windows | 20261127-175430-85f15024 | `--manual MNL-05 --configs M0` | native | `765b6cc` | 307 | `M*/binary.json` |
| linux | 20261126-193339-3d89dcf4 | `--configs M11 --functional --frames 240` | native | `92617e7` | 148 | `M*/binary.json` |
| linux | 20261126-193548-e41e290a | `--functional --configs M0 M1 M2 M3 M4 M5 M6 M7 M8 M9 M11` | native | `92617e7` | 148 | `M*/binary.json` |
| linux | 20261126-204141-6cc18c01 | `--functional --configs M0 --backend tk` | tk | `99afe6d` | 0 | `M*/binary.json` |
| linux | 20261126-204538-356dcc99 | `--functional --configs M0 --backend terminal` | terminal | `99afe6d` | 0 | `M*/binary.json` |
| linux | 20261126-212518-c4bf82b5 | `--functional --configs M11 --backend tk` | tk | `99afe6d` | 0 | `M*/binary.json` |
| linux | 20261127-180115-cf93845f | `--manual MNL-03a --configs M0` | native | `765b6cc` | 307 | `M*/binary.json` |
| linux | 20261127-180218-f7df2c56 | `--manual MNL-03a --configs M0` | native | `765b6cc` | 307 | `M*/binary.json` |
| linux | 20261127-180335-e2f5d3ff | `--measure path --confirmed user 2026-11-27: linuxを進めて (1421 probe) --plan-sha256 bab8017fa35c6448d4d0cdbe8ebf2b2040d907fff420489a873cf95d9a8f08d2` | native | `765b6cc` | 307 | `M*/binary.json` |
| linux | 20261127-185201-963d2260 | `--manual MNL-01a --configs M0` | native | `765b6cc` | 466 | `M*/binary.json` |
| linux | 20261127-185310-fa4b1253 | `--manual MNL-01b --configs M0` | native | `765b6cc` | 466 | `M*/binary.json` |
| linux | 20261127-185337-88b5e1b8 | `--manual MNL-01b-f --configs M0` | native | `765b6cc` | 466 | `M*/binary.json` |
| linux | 20261127-185404-9764766d | `--manual MNL-02 --configs M0` | native | `765b6cc` | 466 | `M*/binary.json` |
| linux | 20261127-185435-4d79b310 | `--manual MNL-03a --configs M0` | native | `765b6cc` | 466 | `M*/binary.json` |
| linux | 20261127-185510-ca063f21 | `--manual MNL-03b --configs M0` | native | `765b6cc` | 466 | `M*/binary.json` |
| linux | 20261127-185645-1f34064b | `--manual MNL-04 --configs M0` | native | `765b6cc` | 466 | `M*/binary.json` |
| linux | 20261127-185701-8febe452 | `--manual MNL-05 --configs M0` | native | `765b6cc` | 466 | `M*/binary.json` |
| linux | 20261128-074434-f362c963 | `--functional --configs M10` | native | `22cfba2` | 0 | `M*/binary.json` |
| macos | 20261126-193548-73ed9e3e | `--functional --configs M0 M1 M2 M3 M4 M5 M6 M7 M8 M9` | native | `92617e7` | 148 | `M*/binary.json` |
| macos | 20261126-204614-acd76ed6 | `--functional --configs M0 M1 M2 M3 M4 M5 M6 M7 M8 M9` | native | `99afe6d` | 0 | `M*/binary.json` |
| macos | 20261126-212155-d3dee35b | `--functional --configs M0 --backend tk` | tk | `99afe6d` | 0 | `M*/binary.json` |
| macos | 20261126-212545-283a799a | `--functional --configs M0 --backend terminal` | terminal | `99afe6d` | 0 | `M*/binary.json` |
| macos | 20261127-201016-b147caed | `--manual MNL-01a --configs M0` | native | `58fa00a` | 0 | `M*/binary.json` |
| macos | 20261127-201058-f7055782 | `--manual MNL-01b --configs M0` | native | `58fa00a` | 0 | `M*/binary.json` |
| macos | 20261127-201124-7f6a1b70 | `--manual MNL-01b-f --configs M0` | native | `58fa00a` | 0 | `M*/binary.json` |
| macos | 20261127-201146-6bbc52bc | `--manual MNL-02 --configs M0` | native | `58fa00a` | 0 | `M*/binary.json` |
| macos | 20261127-201210-0d1b9296 | `--manual MNL-03a --configs M0` | native | `58fa00a` | 0 | `M*/binary.json` |
| macos | 20261127-201333-dd3efd39 | `--manual MNL-03b --configs M0` | native | `58fa00a` | 0 | `M*/binary.json` |
| macos | 20261127-201426-1ab471ed | `--manual MNL-04 --configs M0` | native | `58fa00a` | 0 | `M*/binary.json` |
| macos | 20261127-201441-43f14454 | `--manual MNL-05 --configs M0` | native | `58fa00a` | 0 | `M*/binary.json` |
| macos | 20261127-201804-29170cda | `--manual MNL-03a --configs M0` | native | `58fa00a` | 0 | `M*/binary.json` |
| macos | 20261127-201924-f3eb73f7 | `--manual MNL-03a --configs M0` | native | `58fa00a` | 17 | `M*/binary.json` |
| macos | 20261127-202404-f2115c56 | `--manual MNL-03a --configs M0` | native | `58fa00a` | 17 | `M*/binary.json` |
| macos | 20261127-210221-a3d08a10 | `--functional --configs M0 M1 M2 M3 M4 M5 M6 M7 M8 M9` | native | `73b782c` | 0 | `M*/binary.json` |
| macos | 20261128-074557-31b09102 | `--functional --configs M10` | native | `22cfba2` | 0 | `M*/binary.json` |

L19: Tk `20261126-204141-6cc18c01`, terminal `20261126-204538-356dcc99`. Linux L is native, 92617e7 plus a 148-line diff; former U:Q cells are assigned their existing automatic evidence. Windows `20261126-181938-verification-7ab559a1` has no manifest: it contains bilingual REPORT files and a smoke-verification summary.json, referencing separate smoke runs rather than an independent execution. It is not used for current acceptance passes; no missing manifest is fabricated. Recording revision is 22cfba2 plus this ledger update, distinct from tested revisions above.

### Required gaps and proposed overall verdict

**Propose IA-15 pass; propose keeping overall 1057 unverified.** The former four blockers (IA-07 M0/native, IA-11 decision B, M10 IA-13 and IA-15) are resolved as above, but plan §2 still requires the gaps below.

| IA | OS / configuration / backend | Reason and next check |
|---|---|---|
| IA-04 | Windows/Linux/macOS; M1/M2/M9 native | U:C: reconcile sequence/pipe/completion/termination in each configuration; M1 input/deadline without a window, M2/M9 including window wait release. |
| IA-08 | Windows/Linux/macOS; M1/M2/M9 native | U:H: link configuration-specific cancellation, recovery and resubmission observations to MNL-03; do not transfer M0 observations. |
| IA-09 | Windows/Linux/macOS; M9 native | U:H: link M9 automatic live-resource exit reconciliation with MNL-04/05 observations. |
| IA-07 | Linux; M1 native | U:K: L originally left this unverified; inspect capability, unsupported rejection and deadline/input/cancellation termination for graphics exclusion; rerun that configuration if evidence is absent. |

Required unverified cells total 22 (IA-04: 9; IA-08: 9; IA-09: 3; IA-07: 1). Other U cells exceed plan §2 configuration/backend scope and do not independently block completion, including non-M0 response/listening, additional IA-07 configurations other than M1, and unexecuted additional backends. Actual paint concurrency for IA-11 remains untested supplemental scope, not a completion condition. Shared static results repeated across 108 rows are not independent executions. Earlier tables/verdicts remain above as history; this section and updated §3 take precedence.

## Final consolidation after Lemon’s decision (1447)

2026-11-28, Roku. This update supersedes the earlier overall proposals, aggregation tables and 07:52 required-gap list without removing them. §3 is the current status matrix. Evidence below is the Claude raw-log confirmation supplied by Lemon in this request; no runtime tests or remote log inspection were repeated here.

### User decision — 2026-11-28

Lemon decided: “omit human observation.” Under plan §7, human observations MNL-03/04/05 are required only for M0. Judge IA-08 and IA-09 for M1/M2/M9 using the automated cancellation, recovery and exit results of the same configuration. This decision does not establish human observation for those configurations and does not transfer M0 observations. Overall acceptance remains Lemon’s decision.

| Code / updated cells | Evidence and verdict basis |
|---|---|
| C28 / IA-04, M1/M2/M9 native, all three OSes (9) | Claude checked original automated logs: Windows W `20261126-193555-1be64edd`, Linux L `20261126-193548-e41e290a` (native), macOS A43 `20261127-210221-a3d08a10`. Each OS/configuration has 16 IA-RECONCILE records satisfying produced = processed + discarded and pending=0, zero mismatches, and 13 IA-CLEAN records with error=0. Completion waits tag=105 reason=2048: Windows M2/M9 13,259/13,215; Linux 11,307/13,248; macOS 13,215/13,212. M1 has no window and zero such waits. Pass, omitting absent providers as plan §2 requires. W is used specifically for this M1 reconciliation confirmation; the W1 startup correction remains in force for its other cells. |
| K28 / IA-07, Linux M1 native (1) | L’s graphics-excluded M1 progresses through waits and reconciliation and ends with IA-CLEAN error=0, the same evidence pattern used to pass Windows/macOS M1. Pass without claiming a paint wait in a windowless configuration. |
| D28 / IA-08, M1/M2/M9 native (9); IA-09, M9 native (3) | Pass using each configuration’s automated cancellation/recovery/exit verdicts in W, L and A43 (macOS rerun under eslogger tracing), together with Lemon’s 2026-11-28 decision above. These are automated passes under the agreed observation scope; MNL-03/04/05 were not performed for these configurations. |

### Recount of the current matrix

All 108 rows × 18 conditions = 1,944 cells were recounted. Exactly 22 cells changed from U to P (IA-04: 9; IA-07: 1; IA-08: 9; IA-09: 3). U:I/U:Q/U:R/U:V remain zero. Repeated shared static cells do not represent independent executions.

| OS | P | F | U | N |
|---|---:|---:|---:|---:|
| Windows | 282 | 0 | 204 | 162 |
| Linux | 299 | 0 | 223 | 126 |
| macOS | 282 | 0 | 204 | 162 |
| Total / 合計 | 863 | 0 | 631 | 450 |

| Unverified code / 未確認コード | Cells / セル数 |
|---|---:|
| U:B | 552 |
| U:C | 14 |
| U:H | 35 |
| U:K | 18 |
| U:T | 12 |

### Required scope and proposed overall verdict

**Propose accepting 1057 as passed.** No unverified cells remain within the configuration/backend scope required by plan §2, applying the dated user decision above. The 22 required gaps in the 07:52 proposal are resolved; the remaining 631 U cells are supplemental and do not prevent completion. This is a proposal, not Lemon’s final acceptance.

Supplemental unverified scope retained explicitly:

- Untested configurations/backends beyond plan §2’s specified combinations (U:B, 552 cells).
- Additional mixed-provider reconciliation outside the required configurations (U:C, 14 cells).
- Non-M0 response/observation checks and additional backend observations beyond the required scope (U:H, 35 cells). Non-M0 listening and numerical response checks remain unverified (U:T, 12 cells).
- Additional IA-07 configurations beyond M0 per backend and M1 (U:K, 18 cells).
- Actual paint concurrency in IA-11 remains untested and outside decision B; substituted-window evidence is retained as such. Physical presentation is outside the measured endpoint. Missing device/audio-route details remain unavailable; no new evidence is inferred.

The earlier R6 exclusion for a real DwmFlush-unavailable environment remains unchanged. Required M0 human acceptance and existing static decisions retain their recorded evidence and limitations.

## Consolidation after supplemental checks (1461, 1462, 1466)

2026-11-28, Roku. This section supersedes the 863 P / 0 F / 631 U / 450 N consolidation and its remaining-gap list; those historical records are retained. §3 is updated. These are supplemental checks beyond the plan’s required combinations, authorized by Lemon’s “proceed with 1 and 2” on 2026-11-28. Evidence is the Claude raw-log counts and execution results supplied by Lemon, not a new execution or independent remote-log verification in this ledger update. Untested device/audio-route details and hashes are not fabricated.

### User decisions — 2026-11-28

Lemon’s “omit human observation” keeps observation at M0 only. Automated cancellation/recovery/exit checks decide non-M0 IA-08/09; they do not establish human observations or the visual-generation/last-valid-image checks in IA-05. IA-05 outside the observed M0/native combination remains unverified. For IA-06 M8/M9 Lemon selected “A: record as outside the plan (N) and do not measure.” This exclusion applies to all M8/M9 backend cells; the attempted native measurements were rejected on all three OSes by `tests/scripts/integration-acceptance.py:606` (`IA-06 requires M0`). The plan specifies three OSes / M0 (lines 36, 134, 138). M8/M9 requests and search automated scenarios already pass; that is not a response measurement. Overall acceptance remains Lemon’s decision.

### Evidence and updated cell rules

| Code | Evidence and scope |
|---|---|
| C29 | IA-04: Claude counted native M4 (15 records per OS) and M8 (16 per OS) in W `20261126-193555-1be64edd`, L `20261126-193548-e41e290a`, A43 `20261127-210221-a3d08a10`. All IA-RECONCILE records satisfy produced = processed + discarded, pending=0, zero mismatches. M0 Tk/terminal each has 17 matching records in WT/WC, Linux `20261126-204141-6cc18c01` / `20261126-204538-356dcc99`, macOS `20261126-212155-d3dee35b` / `20261126-212545-283a799a`. Linux M11 Tk `20261126-212518-c4bf82b5` / terminal `20261126-193339-3d89dcf4` each has 16 matching records. Pass. |
| K29 | IA-07 M2–M9 native: M2/M8/M9 each have over 10,000 rendering-completion waits (tag=105 reason=2048); windowless M3–M7 exit normally without rendering, IA-CLEAN error=0. Resolve the 18 U:K cells; existing P cells retain their original evidence. |
| D29 | IA-08/09 M0 Tk/terminal: all automated scenarios pass in the M0 runs listed under C29. macOS’s only lifetime-tracing gap was resolved by 1424 eslogger evidence. This records the supplied automated verdicts, not new human observation. |
| B29 | M1–M10 Tk/terminal runs below: all M1–M9 applicable automated scenarios pass. Windows/Linux have zero non-pass rows, 142–143 rows per run. IA-RECONCILE has zero mismatches (M1/M2/M8/M9: 16 each; M4: 15), IA-CLEAN error=0. M10 image-boundary prints `0 0`, status 0. IA-FRAME-WAIT rejection on non-native M2/M8/M9 is the expected unsupported-backend path, not native paint completion. Use the same automatic boundaries as M0 Tk/terminal: IA-01/02/03/04/07/08/09/10/12 and applicable IA-13 pass; IA-11 uses the existing R11 decision-B tests plus these startup/restore results. Retain vocabulary exclusions and IA-05/06 limitations. |
| N:X11N | Linux M11 native has no native window in the no-X11 build: IA-01–13 are N/A (the existing IA-06 N:X6 is retained). Tk/terminal results are separate. |
| N:X6P | IA-06 M8/M9 is outside the plan by Lemon’s dated decision above. No measurement pass is claimed. |

| OS | Tk run | terminal run | Tested HEAD |
|---|---|---|---|
| Windows | `20261128-082054-79804a11` | `20261128-085831-e04c06b1` | `342c288` |
| Linux | `20261128-082946-39097f0a` | `20261128-090844-ba212d3b` | `342c288` |
| macOS | `20261128-084449-82e1c68d` | `20261128-091839-a7711485` | `342c288` |

For macOS B29, the adapter marked all 142 scenarios per run unverified solely as `native lifetime tracing required`, as in 1443. Runs were covered by `.work/1465-eslogger.jsonl` (14,265 events). Matching with `tests/scripts/eslogger-process-tree.py` found 179 sigma starts / 343 descendants for Tk and 179 starts / 100 descendants for terminal; zero processes remained. Combining these exit records with the automated scenario results establishes passes on the same basis as 1443. The adapter’s original unverified verdicts are retained here explicitly.

### Changed cells and recount

All OS references below mean Windows, Linux and macOS. Only previously unverified cells are changed; existing passes and exclusions remain. This is the complete grouped change list.

| Scope | IA and change | Cells |
|---|---|---:|
| All OSes, M4/M8 native; M0 Tk/terminal; Linux M11 Tk/terminal | IA-04 U:C → P:C29 | 14 |
| All OSes, M0 Tk/terminal | IA-08/09 U:H → P:D29 | 12 |
| All OSes, M2/M3/M5/M8/M9 native; Linux M4/M6/M7 native | IA-07 U:K → P:K29 | 18 |
| All OSes, M1–M9 Tk/terminal | IA-01/02/07/09/10/12 U:B → P:B29 (54 each); IA-11 U:B → P:R11 (54) | 378 |
| All OSes, M1–M6/M8/M9 Tk/terminal | IA-03 U:B → P:B29 | 48 |
| All OSes, M1/M2/M4/M8/M9 Tk/terminal | IA-04/08 U:B → P:B29 (30 each) | 60 |
| All OSes, M9/M10 Tk/terminal | IA-13 U:B → P:B29 | 12 |
| All OSes, M1/M2/M4/M8/M9 Tk/terminal | IA-05 U:B → U:H (execution now recorded; visual check still unverified) | 30 |
| All OSes, M8/M9 native and Tk/terminal | IA-06 U:T (6) / U:B (12) → N:X6P | 18 |
| Linux, M11 native | IA-01–05/07–13 U:B → N:X11N | 12 |

108 × 18 = 1,944 cells recounted: 542 U→P, 30 U→N, 30 U→U reason changes (602 edited cells). Compared with the preceding consolidation: P +542, F unchanged, U −572, N +30. U:H rises from 35 to 53 because 30 previously unexecuted IA-05 cells are now classified by their remaining observation gap, while 12 M0 IA-08/09 gaps pass. U:T falls from 12 to 6; U:B/C/K become zero. Shared static cells are not independent executions.

| OS | P | F | U | N |
|---|---:|---:|---:|---:|
| Windows | 461 | 0 | 19 | 168 |
| Linux | 483 | 0 | 21 | 144 |
| macOS | 461 | 0 | 19 | 168 |
| Total / 合計 | 1405 | 0 | 59 | 480 |

| Unverified code / 未確認コード | Cells / セル数 |
|---|---:|
| U:H | 53 |
| U:T | 6 |
| U:B / U:C / U:K / U:I / U:Q / U:R / U:V | 0 |

### Remaining supplemental gaps and proposed overall verdict

**Propose accepting 1057 as passed.** The required-plan result is unchanged. Supplemental checks reduce unverified cells from 631 to 59; this remains a proposal for Lemon’s final decision.

| Remaining code | Complete cell scope | Cells |
|---|---|---:|
| U:H | IA-05, all OSes: M0 Tk/terminal; M1/M2/M4/M8/M9 native/Tk/terminal. Also Linux M11 Tk/terminal. Visual generation/last-valid-image checks are unverified; automated cancellation/exit does not establish them. | 53 |
| U:T | IA-06, all OSes: M0 Tk/terminal. Formal baseline/load response measurement and listening are unverified. | 6 |

IA-11 actual paint concurrency remains untested outside decision B. Physical presentation remains outside the measured endpoint; unavailable device/audio-route details remain unavailable. Prior R6 exclusions and required M0/native human acceptance retain their recorded boundaries.

### User's final decision (2026-11-28)

Lemon's decision "A": **1057 is accepted as passed.** Basis: no unverified or failed cells remain within the scope required by plan §2. The 59 supplemental unverified cells above (U:H 53, U:T 6) are outside the plan; they remain recorded as unverified and are not used as evidence for the pass.

## Change to not required (2026-11-28, user decision)

By Lemon's decision ("change item 1 from unverified to not required"), the 59 supplemental unverified cells are reclassified as not required (N). In the current §3 table, the 53 U:H cells become N:XHD and the 6 U:T cells become N:XTD. They are not counted as passes.

| Code | Reason |
|---|---|
| N:XHD | IA-05 visual checks outside M0 native are not required by the user's decision. Human observation applies to M0 native only (consistent with "human observation omitted"). No visual pass is claimed. |
| N:XTD | IA-06 response measurement and listening on M0 Tk/terminal are not required by the user's decision. The formal IA-06 measurement passed on M0 native on all three OSes (the adapter's PAINTTRACE is native-only). No measurement pass is claimed. |

| OS | P | F | U | N |
|---|---:|---:|---:|---:|
| Windows | 461 | 0 | 0 | 187 |
| Linux | 483 | 0 | 0 | 165 |
| macOS | 461 | 0 | 0 | 187 |
| Total | 1405 | 0 | 0 | 539 |

The following items are not table cells and are also not required by the user's decision (2026-11-28, "change item 2 to not required as well"): IA-11 actual paint concurrency (outside decision B), physical presentation (outside the measured endpoint), unavailable device/audio-route details, and the tested HEAD of the §2 L and A rows together with the remote raw run sets. None of them is claimed as checked; statements in earlier sections of this ledger calling them unverified, untested or unavailable are superseded by this decision. No unverified item remains for 1057.
