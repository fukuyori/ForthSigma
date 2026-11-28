# 1057：統合受け入れ結果台帳（1415、追記用）

[English](INTEGRATION_ACCEPTANCE_1057_RESULTS.md)

## 1. 記録の範囲と判定

2026-11-26、ロク。記録基点 `99afe6d`。1057全体は未確認で、IA-18は集約の準備段階。今回は既存ログの読取りと静的照合だけで、ビルド・実機実行・時間測定を行っていない。[計画](INTEGRATION_ACCEPTANCE_PLAN_1057.ja.md)§2/4/7/8/11と末尾の決定、[道具](INTEGRATION_ACCEPTANCE_1057_TOOLS.ja.md)、[文書・採否照合](INTEGRATION_ACCEPTANCE_1057_REVIEW.ja.md)を参照。

2026-11-28更新：IA-18の集約を完了。現行の判定案は「1057は合格の案」（末尾の最終集約を参照。同日の先の「未確認の判定案」は置き換えた）。以下の2026-11-26の説明は初期記録。

初期記録の凡例（現行P/F/U/Nは最終集約で定義）：P=自動機能判定の合格、F=不合格、U=未確認、N=適用外、D=未実施（分類は未確認）。P/Uは自動合格だが手作業等を含むIA全体は未確認。Pは実提示・聴取・時間・完全復元競合の合格を意味しない。Nは語群除外や計画対象外であり、機器不足には使わない。静的なIA-14〜18は全OS・全構成に共通で§4を参照する。

> 1445/1447注記：以下の記録は各日付時点の履歴。現行判定は§3と末尾の最終集約を優先する。A6の未確認はA7、Mac手作業の回収未確認は1443で更新。§2の未取得・未確認は出所情報の不足として現在も残る。

2026-11-28 07:4x確認反映：現行判定は末尾の「再集約（1451）」と§3。07:02の最終集約・出所不足の記述は履歴として保持し、後続の更新を優先する。

2026-11-28 最終更新（1447）：現行の判定は§3と末尾「利用者の決定後の最終集約（1447）」を参照。旧判定・旧集計・07:52の必須未確認22セルの一覧は、更新前の履歴として残す。

2026-11-28 補足更新（1461・1462・1466）：現行は§3と末尾「補足確認後の最終集約」。旧い記述と集計は更新前の履歴として保持する。

## 2. 出典・実行版・原記録

| 出典 / Source | run ID | 実行時HEAD / Tested HEAD | 方法 / Method | ledger SHA-256 |
|---|---|---|---|---|
| W | 20261126-193555-1be64edd | 92617e7c6b8ca97079f074adce11d0710c37594c | tests/scripts/integration-acceptance.py --functional --configs M0 M1 M2 M3 M4 M5 M6 M7 M8 M9 M10 | 49c8cecbaf81f057fc1df57f1aef4ffdde2e4ad820c937ef0b450ce9482af5c8 |
| W1 | 20261126-201122-54d17ba8 | 92617e7c6b8ca97079f074adce11d0710c37594c | tests/scripts/integration-acceptance.py --functional --configs M1 | 33fd1c0bb941fd67757fbe747d262b98c7d669a09ad835db1dd6517ec46d7215 |
| WT | 20261126-192325-012b4581 | 92617e7c6b8ca97079f074adce11d0710c37594c | tests/scripts/integration-acceptance.py --functional --configs M0 --backend tk --frames 240 | ada16933277ed86814d64f6b2695fb97f74ad411070aa0d19fba4e00663de626 |
| WC | 20261126-192425-c5f0d86e | 92617e7c6b8ca97079f074adce11d0710c37594c | tests/scripts/integration-acceptance.py --functional --configs M0 --backend terminal --frames 240 | 35bf40136528507ab09b09d02a5630e869b80a95e623574ba930720df4d49c4b |
| L | 20261126-193548-e41e290a | 未確認 / unknown | Claude確認済み要約 / supplied Claude-checked summary | 未取得 / unavailable |
| A | 20261126-193548-73ed9e3e | 未確認 / unknown | macOS: descendant lifetime tracking absent | 未取得 / unavailable |
| A6 | 1425、path/search各4組 | 765b6cca36e05edb0c3a60d65fe8571901ecae5f | M0 native、1,200フレームの正式測定 | `.work/1425-summary.json`（各output.binのSHA-256を収録） |
| A7 | 1425の測り直し、path/search各2組 | 6b6a7ac＋1440の作業ツリー | M0 native、1,200フレームの正式測定 | Mac機の `.work/1425b-runs.txt` |

WのM1をW1で置き換える。旧WのM1 IA-03未確認を消さず、最新W1の合格を採用する。WT/WCは[1412報告](../.work/integration-acceptance/1412-diagnosis/REPORT.ja.md)にあるTk/terminalの240枠runで、1,200枠のWと同じ実行としない。Windowsの元記録版はmanifest/ledgerの92617e7、今回の集約版は99afe6d基点の作業ツリー。元のdirty差分・plan/fixture/binary hashを各runのmanifest.json、working-tree.stdout、M*/binary.jsonで追える。実行時HEADが同じでもバイナリ同一とは断定しない。

Windowsのrunはリポジトリ内`.work/integration-acceptance/<run ID>/`に実在し、ledgerのevidence先も確認した。機器・音経路はledgerのsystem default (unverified)のままで、人の回答は未取得。Linux/macOSのファイルにはアクセスせず、今回提示された要約を転記した。Lの「全構成合格」は適用可能な自動機能枝に限り、M10の保存起動やM0以外のIA-05へ拡張しない。L/Aの実行版・機器・backend・ハッシュ・原ログはClaudeが追記する。

## 3. IA × OS × configuration × backend (current / 現行、1461・1462・1466)

現行の根拠コード・集計は末尾「補足確認後の最終集約」を参照。従来の分類規則・旧表は履歴として保持。

| OS | Config | backend | IA-01 | IA-02 | IA-03 | IA-04 | IA-05 | IA-06 | IA-07 | IA-08 | IA-09 | IA-10 | IA-11 | IA-12 | IA-13 | IA-14 | IA-15 | IA-16 | IA-17 | IA-18 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Windows | M0 | native | P:W | P:W | P:W | P:W+H | P:W+H | P:T+H | P:K07 | P:W+H | P:W+H | P:W | P:R11 | P:W | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Windows | M0 | Tk | P:WT | P:WT | P:WT | P:C29 | U:H | U:T | P:WT | P:D29 | P:D29 | P:WT | P:R11 | P:WT | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Windows | M0 | terminal | P:WC | P:WC | P:WC | P:C29 | U:H | U:T | P:WC | P:D29 | P:D29 | P:WC | P:R11 | P:WC | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Windows | M1 | native | P:W1 | P:W1 | P:W1 | P:C28 | U:H | N:X6 | P:W1 | P:D28 | P:W1 | P:W1 | P:R11 | P:W1 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Windows | M1 | Tk | P:B29 | P:B29 | P:B29 | P:B29 | U:H | N:X6 | P:B29 | P:B29 | P:B29 | P:B29 | P:R11 | P:B29 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Windows | M1 | terminal | P:B29 | P:B29 | P:B29 | P:B29 | U:H | N:X6 | P:B29 | P:B29 | P:B29 | P:B29 | P:R11 | P:B29 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Windows | M2 | native | P:W | P:W | P:W | P:C28 | U:H | N:X6 | P:K29 | P:D28 | P:W | P:W | P:R11 | P:W | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Windows | M2 | Tk | P:B29 | P:B29 | P:B29 | P:B29 | U:H | N:X6 | P:B29 | P:B29 | P:B29 | P:B29 | P:R11 | P:B29 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Windows | M2 | terminal | P:B29 | P:B29 | P:B29 | P:B29 | U:H | N:X6 | P:B29 | P:B29 | P:B29 | P:B29 | P:R11 | P:B29 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Windows | M3 | native | P:W | P:W | P:W | N:XE | N:XE | N:X6 | P:K29 | N:XE | P:W | P:W | P:R11 | P:W | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Windows | M3 | Tk | P:B29 | P:B29 | P:B29 | N:XE | N:XE | N:X6 | P:B29 | N:XE | P:B29 | P:B29 | P:R11 | P:B29 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Windows | M3 | terminal | P:B29 | P:B29 | P:B29 | N:XE | N:XE | N:X6 | P:B29 | N:XE | P:B29 | P:B29 | P:R11 | P:B29 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Windows | M4 | native | P:W | P:W | P:W | P:C29 | U:H | N:X6 | P:W | P:W | P:W | P:W | P:R11 | P:W | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Windows | M4 | Tk | P:B29 | P:B29 | P:B29 | P:B29 | U:H | N:X6 | P:B29 | P:B29 | P:B29 | P:B29 | P:R11 | P:B29 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Windows | M4 | terminal | P:B29 | P:B29 | P:B29 | P:B29 | U:H | N:X6 | P:B29 | P:B29 | P:B29 | P:B29 | P:R11 | P:B29 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Windows | M5 | native | P:W | P:W | P:W | N:XE | N:XE | N:X6 | P:K29 | N:XE | P:W | P:W | P:R11 | P:W | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Windows | M5 | Tk | P:B29 | P:B29 | P:B29 | N:XE | N:XE | N:X6 | P:B29 | N:XE | P:B29 | P:B29 | P:R11 | P:B29 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Windows | M5 | terminal | P:B29 | P:B29 | P:B29 | N:XE | N:XE | N:X6 | P:B29 | N:XE | P:B29 | P:B29 | P:R11 | P:B29 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Windows | M6 | native | P:W | P:W | P:W | N:XE | N:XE | N:X6 | P:W | N:XE | P:W | P:W | P:R11 | P:W | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Windows | M6 | Tk | P:B29 | P:B29 | P:B29 | N:XE | N:XE | N:X6 | P:B29 | N:XE | P:B29 | P:B29 | P:R11 | P:B29 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Windows | M6 | terminal | P:B29 | P:B29 | P:B29 | N:XE | N:XE | N:X6 | P:B29 | N:XE | P:B29 | P:B29 | P:R11 | P:B29 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Windows | M7 | native | P:W | P:W | N:X3 | N:XE | N:XE | N:X6 | P:W | N:XE | P:W | P:W | P:R11 | P:W | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Windows | M7 | Tk | P:B29 | P:B29 | N:X3 | N:XE | N:XE | N:X6 | P:B29 | N:XE | P:B29 | P:B29 | P:R11 | P:B29 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Windows | M7 | terminal | P:B29 | P:B29 | N:X3 | N:XE | N:XE | N:X6 | P:B29 | N:XE | P:B29 | P:B29 | P:R11 | P:B29 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Windows | M8 | native | P:W | P:W | P:W | P:C29 | U:H | N:X6P | P:K29 | P:W | P:W | P:W | P:R11 | P:W | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Windows | M8 | Tk | P:B29 | P:B29 | P:B29 | P:B29 | U:H | N:X6P | P:B29 | P:B29 | P:B29 | P:B29 | P:R11 | P:B29 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Windows | M8 | terminal | P:B29 | P:B29 | P:B29 | P:B29 | U:H | N:X6P | P:B29 | P:B29 | P:B29 | P:B29 | P:R11 | P:B29 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Windows | M9 | native | P:W | P:W | P:W | P:C28 | U:H | N:X6P | P:K29 | P:D28 | P:D28 | P:W | P:R11 | P:W | P:W | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Windows | M9 | Tk | P:B29 | P:B29 | P:B29 | P:B29 | U:H | N:X6P | P:B29 | P:B29 | P:B29 | P:B29 | P:R11 | P:B29 | P:B29 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Windows | M9 | terminal | P:B29 | P:B29 | P:B29 | P:B29 | U:H | N:X6P | P:B29 | P:B29 | P:B29 | P:B29 | P:R11 | P:B29 | P:B29 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Windows | M10 | native | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | P:W | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Windows | M10 | Tk | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | P:B29 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Windows | M10 | terminal | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | P:B29 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Windows | M11 | native | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Windows | M11 | Tk | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Windows | M11 | terminal | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Linux | M0 | native | P:L | P:L | P:L | P:L+H | P:L+H | P:T+H | P:K07 | P:L+H | P:L+H | P:L | P:R11 | P:L | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Linux | M0 | Tk | P:L19 | P:L19 | P:L19 | P:C29 | U:H | U:T | P:L19 | P:D29 | P:D29 | P:L19 | P:R11 | P:L19 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Linux | M0 | terminal | P:L19 | P:L19 | P:L19 | P:C29 | U:H | U:T | P:L19 | P:D29 | P:D29 | P:L19 | P:R11 | P:L19 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Linux | M1 | native | P:L | P:L | P:L | P:C28 | U:H | N:X6 | P:K28 | P:D28 | P:L | P:L | P:R11 | P:L | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Linux | M1 | Tk | P:B29 | P:B29 | P:B29 | P:B29 | U:H | N:X6 | P:B29 | P:B29 | P:B29 | P:B29 | P:R11 | P:B29 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Linux | M1 | terminal | P:B29 | P:B29 | P:B29 | P:B29 | U:H | N:X6 | P:B29 | P:B29 | P:B29 | P:B29 | P:R11 | P:B29 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Linux | M2 | native | P:L | P:L | P:L | P:C28 | U:H | N:X6 | P:K29 | P:D28 | P:L | P:L | P:R11 | P:L | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Linux | M2 | Tk | P:B29 | P:B29 | P:B29 | P:B29 | U:H | N:X6 | P:B29 | P:B29 | P:B29 | P:B29 | P:R11 | P:B29 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Linux | M2 | terminal | P:B29 | P:B29 | P:B29 | P:B29 | U:H | N:X6 | P:B29 | P:B29 | P:B29 | P:B29 | P:R11 | P:B29 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Linux | M3 | native | P:L | P:L | P:L | N:XE | N:XE | N:X6 | P:K29 | N:XE | P:L | P:L | P:R11 | P:L | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Linux | M3 | Tk | P:B29 | P:B29 | P:B29 | N:XE | N:XE | N:X6 | P:B29 | N:XE | P:B29 | P:B29 | P:R11 | P:B29 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Linux | M3 | terminal | P:B29 | P:B29 | P:B29 | N:XE | N:XE | N:X6 | P:B29 | N:XE | P:B29 | P:B29 | P:R11 | P:B29 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Linux | M4 | native | P:L | P:L | P:L | P:C29 | U:H | N:X6 | P:K29 | P:L | P:L | P:L | P:R11 | P:L | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Linux | M4 | Tk | P:B29 | P:B29 | P:B29 | P:B29 | U:H | N:X6 | P:B29 | P:B29 | P:B29 | P:B29 | P:R11 | P:B29 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Linux | M4 | terminal | P:B29 | P:B29 | P:B29 | P:B29 | U:H | N:X6 | P:B29 | P:B29 | P:B29 | P:B29 | P:R11 | P:B29 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Linux | M5 | native | P:L | P:L | P:L | N:XE | N:XE | N:X6 | P:K29 | N:XE | P:L | P:L | P:R11 | P:L | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Linux | M5 | Tk | P:B29 | P:B29 | P:B29 | N:XE | N:XE | N:X6 | P:B29 | N:XE | P:B29 | P:B29 | P:R11 | P:B29 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Linux | M5 | terminal | P:B29 | P:B29 | P:B29 | N:XE | N:XE | N:X6 | P:B29 | N:XE | P:B29 | P:B29 | P:R11 | P:B29 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Linux | M6 | native | P:L | P:L | P:L | N:XE | N:XE | N:X6 | P:K29 | N:XE | P:L | P:L | P:R11 | P:L | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Linux | M6 | Tk | P:B29 | P:B29 | P:B29 | N:XE | N:XE | N:X6 | P:B29 | N:XE | P:B29 | P:B29 | P:R11 | P:B29 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Linux | M6 | terminal | P:B29 | P:B29 | P:B29 | N:XE | N:XE | N:X6 | P:B29 | N:XE | P:B29 | P:B29 | P:R11 | P:B29 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Linux | M7 | native | P:L | P:L | N:X3 | N:XE | N:XE | N:X6 | P:K29 | N:XE | P:L | P:L | P:R11 | P:L | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Linux | M7 | Tk | P:B29 | P:B29 | N:X3 | N:XE | N:XE | N:X6 | P:B29 | N:XE | P:B29 | P:B29 | P:R11 | P:B29 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Linux | M7 | terminal | P:B29 | P:B29 | N:X3 | N:XE | N:XE | N:X6 | P:B29 | N:XE | P:B29 | P:B29 | P:R11 | P:B29 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Linux | M8 | native | P:L | P:L | P:L | P:C29 | U:H | N:X6P | P:K29 | P:L | P:L | P:L | P:R11 | P:L | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Linux | M8 | Tk | P:B29 | P:B29 | P:B29 | P:B29 | U:H | N:X6P | P:B29 | P:B29 | P:B29 | P:B29 | P:R11 | P:B29 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Linux | M8 | terminal | P:B29 | P:B29 | P:B29 | P:B29 | U:H | N:X6P | P:B29 | P:B29 | P:B29 | P:B29 | P:R11 | P:B29 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Linux | M9 | native | P:L | P:L | P:L | P:C28 | U:H | N:X6P | P:K29 | P:D28 | P:D28 | P:L | P:R11 | P:L | P:L | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Linux | M9 | Tk | P:B29 | P:B29 | P:B29 | P:B29 | U:H | N:X6P | P:B29 | P:B29 | P:B29 | P:B29 | P:R11 | P:B29 | P:B29 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Linux | M9 | terminal | P:B29 | P:B29 | P:B29 | P:B29 | U:H | N:X6P | P:B29 | P:B29 | P:B29 | P:B29 | P:R11 | P:B29 | P:B29 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Linux | M10 | native | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | P:I13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Linux | M10 | Tk | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | P:B29 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Linux | M10 | terminal | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | P:B29 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Linux | M11 | native | N:X11N | N:X11N | N:X11N | N:X11N | N:X11N | N:X6 | N:X11N | N:X11N | N:X11N | N:X11N | N:X11N | N:X11N | N:X11N | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Linux | M11 | Tk | P:L20 | P:L20 | P:L20 | P:C29 | U:H | N:X6 | P:L20 | P:L20 | P:L20 | P:L20 | P:R11 | P:L20 | P:L20 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| Linux | M11 | terminal | P:L20 | P:L20 | P:L20 | P:C29 | U:H | N:X6 | P:L20 | P:L20 | P:L20 | P:L20 | P:R11 | P:L20 | P:L20 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| macOS | M0 | native | P:A43 | P:A43 | P:A43 | P:A43+H | P:A43+H | P:T+H | P:K07 | P:A43+H | P:A43+H | P:A43 | P:R11 | P:A43 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| macOS | M0 | Tk | P:A24 | P:A24 | P:A24 | P:C29 | U:H | U:T | P:A24 | P:D29 | P:D29 | P:A24 | P:R11 | P:A24 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| macOS | M0 | terminal | P:A24 | P:A24 | P:A24 | P:C29 | U:H | U:T | P:A24 | P:D29 | P:D29 | P:A24 | P:R11 | P:A24 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| macOS | M1 | native | P:A43 | P:A43 | P:A43 | P:C28 | U:H | N:X6 | P:A43 | P:D28 | P:A43 | P:A43 | P:R11 | P:A43 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| macOS | M1 | Tk | P:B29 | P:B29 | P:B29 | P:B29 | U:H | N:X6 | P:B29 | P:B29 | P:B29 | P:B29 | P:R11 | P:B29 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| macOS | M1 | terminal | P:B29 | P:B29 | P:B29 | P:B29 | U:H | N:X6 | P:B29 | P:B29 | P:B29 | P:B29 | P:R11 | P:B29 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| macOS | M2 | native | P:A43 | P:A43 | P:A43 | P:C28 | U:H | N:X6 | P:K29 | P:D28 | P:A43 | P:A43 | P:R11 | P:A43 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| macOS | M2 | Tk | P:B29 | P:B29 | P:B29 | P:B29 | U:H | N:X6 | P:B29 | P:B29 | P:B29 | P:B29 | P:R11 | P:B29 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| macOS | M2 | terminal | P:B29 | P:B29 | P:B29 | P:B29 | U:H | N:X6 | P:B29 | P:B29 | P:B29 | P:B29 | P:R11 | P:B29 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| macOS | M3 | native | P:A43 | P:A43 | P:A43 | N:XE | N:XE | N:X6 | P:K29 | N:XE | P:A43 | P:A43 | P:R11 | P:A43 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| macOS | M3 | Tk | P:B29 | P:B29 | P:B29 | N:XE | N:XE | N:X6 | P:B29 | N:XE | P:B29 | P:B29 | P:R11 | P:B29 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| macOS | M3 | terminal | P:B29 | P:B29 | P:B29 | N:XE | N:XE | N:X6 | P:B29 | N:XE | P:B29 | P:B29 | P:R11 | P:B29 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| macOS | M4 | native | P:A43 | P:A43 | P:A43 | P:C29 | U:H | N:X6 | P:A43 | P:A43 | P:A43 | P:A43 | P:R11 | P:A43 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| macOS | M4 | Tk | P:B29 | P:B29 | P:B29 | P:B29 | U:H | N:X6 | P:B29 | P:B29 | P:B29 | P:B29 | P:R11 | P:B29 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| macOS | M4 | terminal | P:B29 | P:B29 | P:B29 | P:B29 | U:H | N:X6 | P:B29 | P:B29 | P:B29 | P:B29 | P:R11 | P:B29 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| macOS | M5 | native | P:A43 | P:A43 | P:A43 | N:XE | N:XE | N:X6 | P:K29 | N:XE | P:A43 | P:A43 | P:R11 | P:A43 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| macOS | M5 | Tk | P:B29 | P:B29 | P:B29 | N:XE | N:XE | N:X6 | P:B29 | N:XE | P:B29 | P:B29 | P:R11 | P:B29 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| macOS | M5 | terminal | P:B29 | P:B29 | P:B29 | N:XE | N:XE | N:X6 | P:B29 | N:XE | P:B29 | P:B29 | P:R11 | P:B29 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| macOS | M6 | native | P:A43 | P:A43 | P:A43 | N:XE | N:XE | N:X6 | P:A43 | N:XE | P:A43 | P:A43 | P:R11 | P:A43 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| macOS | M6 | Tk | P:B29 | P:B29 | P:B29 | N:XE | N:XE | N:X6 | P:B29 | N:XE | P:B29 | P:B29 | P:R11 | P:B29 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| macOS | M6 | terminal | P:B29 | P:B29 | P:B29 | N:XE | N:XE | N:X6 | P:B29 | N:XE | P:B29 | P:B29 | P:R11 | P:B29 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| macOS | M7 | native | P:A43 | P:A43 | N:X3 | N:XE | N:XE | N:X6 | P:A43 | N:XE | P:A43 | P:A43 | P:R11 | P:A43 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| macOS | M7 | Tk | P:B29 | P:B29 | N:X3 | N:XE | N:XE | N:X6 | P:B29 | N:XE | P:B29 | P:B29 | P:R11 | P:B29 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| macOS | M7 | terminal | P:B29 | P:B29 | N:X3 | N:XE | N:XE | N:X6 | P:B29 | N:XE | P:B29 | P:B29 | P:R11 | P:B29 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| macOS | M8 | native | P:A43 | P:A43 | P:A43 | P:C29 | U:H | N:X6P | P:K29 | P:A43 | P:A43 | P:A43 | P:R11 | P:A43 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| macOS | M8 | Tk | P:B29 | P:B29 | P:B29 | P:B29 | U:H | N:X6P | P:B29 | P:B29 | P:B29 | P:B29 | P:R11 | P:B29 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| macOS | M8 | terminal | P:B29 | P:B29 | P:B29 | P:B29 | U:H | N:X6P | P:B29 | P:B29 | P:B29 | P:B29 | P:R11 | P:B29 | N:X13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| macOS | M9 | native | P:A43 | P:A43 | P:A43 | P:C28 | U:H | N:X6P | P:K29 | P:D28 | P:D28 | P:A43 | P:R11 | P:A43 | P:A43 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| macOS | M9 | Tk | P:B29 | P:B29 | P:B29 | P:B29 | U:H | N:X6P | P:B29 | P:B29 | P:B29 | P:B29 | P:R11 | P:B29 | P:B29 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| macOS | M9 | terminal | P:B29 | P:B29 | P:B29 | P:B29 | U:H | N:X6P | P:B29 | P:B29 | P:B29 | P:B29 | P:R11 | P:B29 | P:B29 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| macOS | M10 | native | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | P:I13 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| macOS | M10 | Tk | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | P:B29 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| macOS | M10 | terminal | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | N:X10 | P:B29 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| macOS | M11 | native | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| macOS | M11 | Tk | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |
| macOS | M11 | terminal | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | N:X11 | P:S14 | P:S15 | P:S16 | P:S17 | P:S18 |


## 4. Shared static verdicts / 共通静的判定（1447）

補足更新（1461・1462・1466）：本節の1447時点の記述は更新前の履歴。現行IA-14〜18はすべてP（IA-15はP:S15）。残る未確認59セルの内訳は末尾を参照。

IA-14 P:S14; IA-15 U:V; IA-16 P:S16; IA-17 P:S17; IA-18 P:S18.

## 5. Remaining unverified / 現在の未確認（1447）

補足更新（1461・1462・1466）：本節の1447時点の記述は更新前の履歴。現行IA-14〜18はすべてP（IA-15はP:S15）。残る未確認59セルの内訳は末尾を参照。

§3のU:B/C/H/T/K/Q/R/I/Vが未確認の全分類。末尾コード表の理由・次の方法を各セルへ適用する。3 OSのM0手作業・数値測定、macOS子孫回収、Linux M11のTk/terminal IA-13は後続節で解消済み。出所・backend・構成が不足する部分は未確認を保持。

## 6. 今回の文書検証

2026-11-26：`python scripts/check-docs.py`は指摘0、`git diff --check`は成功。新規4文書のローカルリンク106件と引用した節の実在、Windows ledgerのevidence先、1001の保存7値の中央値6件、英日構成とLFを確認した。計画の英日ファイルはHEADと同一で、決定表も変更していない。

2026-11-28（1445/1447）：check-docs.pyはfindings 0。台帳英日各39件、監査表英日各122件、計322件のMarkdownローカルリンクの対象ファイルが実在。遠隔機のバッククォート内.workパスは対象外。英日の現行108行×18セルと集計は完全一致。計画2本のSHA-256は固定値と一致。git diff --checkも確認（末尾余白修正後）。本作業は静的照合のみ。

## 計画の固定（IA-06の測定の前、2026-11-26）

日本語版の計画を正本とし、そのSHA-256を `--plan-sha256` に渡す。計画の英日は `.gitattributes` で `-text` にし、3 OSの取り出しで同じバイト列になるようにした。

| 文書 | SHA-256 |
|---|---|
| INTEGRATION_ACCEPTANCE_PLAN_1057.ja.md（正本） | `bab8017fa35c6448d4d0cdbe8ebf2b2040d907fff420489a873cf95d9a8f08d2` |
| INTEGRATION_ACCEPTANCE_PLAN_1057.md | `da20c53d90710e430b77534a5ce299194e499da7adb99b712c63e3633c41020e` |
## macOSの子孫の寿命の追跡（1423、2026-11-26）

macOSの自動の実行（`.work/integration-acceptance/20261126-204614-acd76ed6`、M0〜M9、HEAD `99afe6d`）は、174場面すべてが「macOSの子プロセスの間欠的な調査を超える寿命の追跡が必要」という理由だけで未確認だった（それ以外の理由で合格しなかった場面は0件）。レモンが `sudo eslogger fork exec exit` で記録し（`.work/1414-eslogger.jsonl`、28,711件、11:45:13〜12:21:44 UTC）、実行の期間（11:46:14〜12:20:51 UTC）を含むことを確かめた。`tests/scripts/eslogger-process-tree.py` で集計すると、run の保存アプリなど204個とその子孫238個がすべて終了し、終了していないものは0個だった。これにより、macOSのIA-01〜03・05・08〜12・13（M9）は、Windows・Linuxと同じく自動の判定で合格とする。IA-04・06・07の一部・手作業は、他のOSと同じく別のタスクで確かめる。
## LinuxのM11（X11なし）のIA-07・IA-13（1420、2026-11-26）

adapterはM11のIA-13を自動では判定せず、常に未確認とする（`tests/scripts/integration-acceptance.py:347`）。Linux機で、M11をTk（`.work/integration-acceptance/20261126-212518-c4bf82b5`）と端末（`20261126-193339-3d89dcf4`）のbackendで実行し、どちらもIA-01〜03・07〜12が合格し、`normal` の場面で `IA-FRAME-WAIT rejected no-capability; deadline/input fallback` と `IA-BUDGET deadline reached` が出た。X11なしの構成で、ネイティブのフレーム完了の待ちを能力がないとして拒否し、期限と入力で進んで終わることを示す。Claudeはこれを根拠に、IA-13（M11）を合格と判断した。
## macOSのM0のTk・terminal backend（1424、2026-11-26）

Tk（`.work/integration-acceptance/20261126-212155-d3dee35b`）とterminal（`20261126-212545-283a799a`）で、各23場面とも未確認の理由は「子孫の寿命の追跡が必要」だけだった。同じeslogger記録（`.work/1414-eslogger.jsonl`、12:30:08 UTCまで）で集計し、Tkはrunのプロセス26個と子孫99個、terminalは26個と子孫36個がすべて終了した。IA-07を含め、Windows・Linuxと同じく合格とする。
## WindowsのIA-06（1417、2026-11-26）

計画（日本語版 SHA-256 `bab8017f…`）で固定した条件で、M0の保存アプリの入口からPCMを再生しながら測った。利用者の指示（「いつでも進めて」）で開始し、他のアプリの停止は求めていない。最初の3回は道具の不具合で判定に至らず（ConPTYが記録の途中に制御列を入れた、同じく端末の行が分かれた、複合待機の入力の時刻を記録していなかった）、adapterと計測用ビルドの記録を直して4回目で判定した。失敗したrunも `.work/1417-runs*.txt` に残す。

| 組 | 入力→画面の最大 | 入力→端末の最大 | 各フレームの期限超過（負荷／基準） | 追加の超過 | PCM underrunの増分 |
|---|---:|---:|---:|---:|---:|
| path 1 | 26.77 ms | 28.12 ms | 0／0 | 0 | 0 |
| path 2 | 10.97 ms | 12.14 ms | 0／0 | 0 | 0 |
| path 3（80%規則の追加） | 10.54 ms | 11.90 ms | 0／0 | 0 | 0 |
| path 4（80%規則の追加） | 11.74 ms | 13.01 ms | 0／0 | 0 | 0 |
| search 1 | 13.15 ms | 14.65 ms | 0／0 | 0 | 0 |
| search 2 | 26.30 ms | 27.50 ms | 0／0 | 0 | 0 |

全組で、基準とフレーム数1,200・入力数6が一致した。path 1の26.77 msが目安33.34 msの80%（26.67 ms）を超えたため、計画どおり独立2組を追加し、元の組を含めて残した。判定：WindowsのIA-06は合格。run IDは `.work/1417-runs4.txt` と `.work/1417-runs4-extra.txt`。
## Windowsの手作業 MNL-01a〜05（1418、2026-11-26〜27）

M0のnative。利用者が自分のPowerShellで `--manual <単位>` を実行し、`キー>` に端末キーを打ち、`観察結果>` に答えた。道具の不具合（qの後に入力を待つ、Ctrl+Cが中断として届かない、音を鳴らさない、保存アプリの表示が利用者に見えない）を直して進めた。答えの欄が空や `done` だった単位は、チャットでの利用者の回答をClaudeが書き写し、その旨を `human-reply.json` に記録した。

| 単位 | 観察 | run |
|---|---|---|
| MNL-01a | 問題なし（nでRequestedが増えGenerationが追いつき、古い値に戻らない） | `20261126-214314-22fdffeb` |
| MNL-01b | 問題なし（a・bで同様） | `20261126-214846-207f770a` |
| MNL-01b-f | 問題なし（fの後もGenerationと表示が残る） | `20261126-214957-ffbb5770` |
| MNL-02 | 問題なし（合成音に乱れなし、キーに画面が反応） | `20261126-215101-ce76c751` |
| MNL-03a | ok（Ctrl+CでIA-CAUGHT、窓と音が続く） | `20261127-175012-bce2d422` |
| MNL-03b | OK（cで取消しと投げ直し、nで新しい結果） | `20261127-175137-3a541c85` |
| MNL-04 | ok（qでIA-EXIT live BYE、窓が消え音が止まる） | `20261127-175338-a70ec686` |
| MNL-05 | ok（閉じるボタンでIA-WINDOW-CLOSED、IA-CLEAN error=0） | `20261127-175430-85f15024` |

判定：WindowsのMNL-01a〜05はすべて合格。IA-04（closeの待ち解除）・IA-05・IA-08・IA-09の人の観察の部分を満たす。
## LinuxのIA-06（1421、2026-11-27）

最初の試しのrunで、POSIXの端末入力の経路でinputの時刻が0になった（`.work/integration-acceptance/20261127-180335-e2f5d3ff`）。Windowsと同じく、計測用ビルドだけで、POSIXの1バイトの読み取り（`src/host_input.zig` の `posix.readByte`）で最初の取得時刻を記録するように直し、試験を加えた（通常ビルドの動作は同じ）。そのうえで、Linux機の実際の画面（GNOME/Mutter＋XWayland）で測った。run IDはLinux機の `.work/1421-runs.txt`。

| 組 | 入力→画面の最大 | 入力→端末の最大 | 各フレームの期限超過（負荷／基準） | 追加の超過 | PCM underrunの増分 |
|---|---:|---:|---:|---:|---:|
| path 1 | 12.95 ms | 12.06 ms | 0／0 | 0 | 0 |
| path 2 | 16.27 ms | 15.50 ms | 0／0 | 0 | 0 |
| search 1 | 21.51 ms | 20.95 ms | 0／0 | 0 | 0 |
| search 2 | 19.85 ms | 18.83 ms | 0／0 | 0 | 0 |

全組で基準とフレーム数1,200・入力数6が一致した。最大21.51 msは目安33.34 msの80%未満で、追加の組は不要。判定：LinuxのIA-06は合格。

## macOS IA-06（1425、2026-11-27）

計画SHA-256 `bab8017fa35c6448d4d0cdbe8ebf2b2040d907fff420489a873cf95d9a8f08d2`、HEAD `765b6cca36e05edb0c3a60d65fe8571901ecae5f`、M0/nativeでpath/search各1,200フレームを独立2組測定した。入力→画面の最大が各題材で33.34 msの80%以上となったため、計画§8どおり追加2組ずつ実施した。

| 題材・組 | 入力→画面 最大 | 入力→端末 最大 | 要求→完了 超過数（負荷／基準） | 追加超過 | PCM underrun増分（負荷／基準） | accepted frames（負荷／基準） | 欠測端点数（負荷／基準） |
|---|---:|---:|---:|---:|---:|---:|---:|
| path 1 | 41.221 ms | 23.864 ms | 398／9 | 389 | 0／0 | 958,336／958,336 | 506／41 |
| path 2 | 33.925 ms | 20.020 ms | 123／664 | 0 | 0／0 | 958,816／958,816 | 139／763 |
| path 3（追加） | 32.076 ms | 23.352 ms | 166／154 | 12 | 0／0 | 958,816／958,816 | 182／166 |
| path 4（追加） | 32.467 ms | 23.368 ms | 663／194 | 469 | 0／0 | 958,336／958,816 | 754／207 |
| search 1 | 30.132 ms | 22.312 ms | 177／172 | 5 | 0／0 | 958,336／958,816 | 262／185 |
| search 2 | 31.966 ms | 21.478 ms | 111／534 | 0 | 0／0 | 958,336／958,816 | 125／650 |
| search 3（追加） | 32.069 ms | 20.938 ms | 160／364 | 0 | 0／0 | 958,336／958,816 | 174／483 |
| search 4（追加） | 29.286 ms | 19.906 ms | 162／91 | 71 | 0／0 | 958,816／958,336 | 176／108 |

8組すべてで負荷・基準の描画列は一致し、各runのPCM underrun増分は0だった。一方、全組で個別paint/wait端点が欠け、path 4とsearch全組でaccepted framesが負荷・基準間で480異なる。観測できた追加超過もpath 1/3/4とsearch 1/4に残る。よってmacOS IA-06は未確認とし、成功とは判定しない。音声経路はsystem default（未確認）。MNL-02の人による聴取は別途未実施。run ID、実行体・raw outputのSHA-256は `.work/1425-summary.json` にある。先行の不正な計測試行も各 `.work/1425-*/` 下に保持した。

## Linuxの手作業 MNL-01a〜05（1422、2026-11-27）

Linux機のデスクトップ（GNOME/Mutter＋XWayland）の端末で、利用者がtque 1422の備考の手順に従って実行した。8単位とも自動の判定は合格、強制的な後始末なし、観察の答えはOKまたはok（Linux機の各runの `M0/human-reply.json`）。

| 単位 | 確かめた表示 | run |
|---|---|---|
| MNL-01a | IA-CLEAN error=0 | `20261127-185201-963d2260` |
| MNL-01b | IA-CLEAN error=0 | `20261127-185310-fa4b1253` |
| MNL-01b-f | IA-CLEAN error=0 | `20261127-185337-88b5e1b8` |
| MNL-02 | IA-CLEAN error=0 | `20261127-185404-9764766d` |
| MNL-03a | IA-CAUGHT、IA-CLEAN error=0 | `20261127-185435-4d79b310` |
| MNL-03b | IA-CANCEL resubmitted、IA-CLEAN error=0 | `20261127-185510-ca063f21` |
| MNL-04 | IA-EXIT live BYE | `20261127-185645-1f34064b` |
| MNL-05 | IA-WINDOW-CLOSED、IA-CLEAN error=0 | `20261127-185701-8febe452` |

判定：LinuxのMNL-01a〜05はすべて合格。Claudeが道具の確認のために動かしたMNL-03a（`20261127-180115-cf93845f`（Xvfb）、`20261127-180218-f7df2c56`（入力を流し込んだもの））は、受入れの証拠に使わない。

## macOS IA-06の測り直し（1425・1440、2026-11-27）

A6の未確認の原因を1440で調べた。親から子への画像の送信は最大約1 ms、子の描画は最大12.3 msで、遅れは子の「描いた」の通知を親が読むまでの区間（最大34.8 ms）にあった。親は決まった処理の途中でしかpipeを読まず、子は画面の更新ごとにまとめて描くので間のフレームが描かれないことがあった。1440で、親に子のpipeの読取りスレッドを設けて到着時刻で端点を記録し、子は各FRAMEを受け取った直後に描くようにした。

| 題材・組 | 入力→画面 最大 | 入力→端末 最大 | 期限超過（負荷／基準） | 追加超過 | 欠測端点 | PCM underrun増分（負荷／基準） | accepted frames（負荷／基準） |
|---|---:|---:|---:|---:|---:|---:|---:|
| path 1 | 14.83 ms | 14.66 ms | 0／0 | 0 | 0 | 0／0 | 958,816／959,776 |
| path 2 | 19.87 ms | 19.71 ms | 0／0 | 0 | 0 | 0／0 | 958,816／959,776 |
| search 1 | 14.84 ms | 14.66 ms | 0／0 | 0 | 0 | 0／0 | 958,816／959,776 |
| search 2 | 19.46 ms | 19.32 ms | 0／0 | 0 | 0 | 0／0 | 958,816／960,256 |

全組で、基準とフレーム数1,200・入力数6・描画列が一致した。最大が33.34 msの80%（26.67 ms）未満なので追加組はない。

accepted framesの扱い（2026-11-27、レモンの決定A）：accepted framesは測定区間の長さで変わる量で、負荷側と基準側の差を不合格の理由にしない。計画§8の「欠落」は記録の欠落、「供給方式の差」は供給の仕方の違いと読み、音の欠けはunderrun増分（全run 0）で判定する。Windows（1417、差は約1万〜5万frames）とLinux（1421、差0）の合格もこの扱いと一致する。

判定：macOSのIA-06は合格。run IDはMac機の `.work/1425b-runs.txt`。

## macOSの手作業 MNL-01a〜05（1426・1442、2026-11-27）

Macのターミナルで、利用者がtque 1426の備考の手順に従って実行した。観察の答えはすべてOKまたはok（Mac機の各runの `M0/human-reply.json`）。8単位とも強制的な後始末はなく、IA-CLEAN error=0（MNL-04はIA-EXIT live BYE）。

| 単位 | 確かめた表示 | run | 実行体 |
|---|---|---|---|
| MNL-01a | IA-CLEAN error=0 | `20261127-201016-b147caed` | 58fa00a |
| MNL-01b | IA-CLEAN error=0 | `20261127-201058-f7055782` | 58fa00a |
| MNL-01b-f | IA-CLEAN error=0 | `20261127-201124-7f6a1b70` | 58fa00a |
| MNL-02 | IA-CLEAN error=0 | `20261127-201146-6bbc52bc` | 58fa00a |
| MNL-03a | IA-CAUGHT、IA-CLEAN error=0 | `20261127-202404-f2115c56` | 58fa00a＋1442 |
| MNL-03b | IA-CANCEL resubmitted、IA-CLEAN error=0 | `20261127-201333-dd3efd39` | 58fa00a |
| MNL-04 | IA-EXIT live BYE | `20261127-201426-1ab471ed` | 58fa00a |
| MNL-05 | IA-WINDOW-CLOSED、IA-CLEAN error=0 | `20261127-201441-43f14454` | 58fa00a |

最初のMNL-03a（`20261127-201210-0d1b9296`）は不合格だった。IA-CAUGHTの直後に保存アプリがHOST FUNCTION ERRORで終わり、音が止まった。物理Ctrl+CのSIGINTは前面のプロセスグループ全体に届き、AppKitの窓の子プロセスも終わっていた。Claudeが入力を流し込んだrunで再現し（`20261127-201804-29170cda`）、1442で窓の子プロセスがSIGINTを無視するよう直した。修正後の流し込みの確認（`20261127-201924-f3eb73f7`）と、利用者のやり直し（`20261127-202404-f2115c56`）で合格。1442の修正は窓の子プロセスのSIGINTの扱いだけで、ほかの7単位の観察には関わらない。

自動の判定は、8単位とも「native lifetime tracing required beyond macOS child polling」で未確認。esloggerなしで実行したためで、ほかの理由の未確認・不合格はない。

判定：macOSのMNL-01a〜05の人の観察はすべて合格。子孫プロセスの後始末の判定は未確認。

## macOSのeslogger記録下の再実行（1443、2026-11-27）

1440・1442の修正後の実行体（HEAD `73b782c`）で、M0〜M9の自動の判定を1423と同じ引数で実行した（`.work/integration-acceptance/20261127-210221-a3d08a10`、21:02:21〜21:40:41 JST）。164場面すべてが「macOSの子プロセスの間欠的な調査を超える寿命の追跡が必要」という理由だけで未確認で、ほかの理由の未確認・不合格は0（1423の実行と同じ形）。

レモンが `sudo eslogger fork exec exit` で記録し（`.work/1443-eslogger.jsonl`、9,439件、12:02:10〜12:57:05 UTC）、runの期間を含むことを確かめた。`tests/scripts/eslogger-process-tree.py` で集計すると、runの保存アプリなど204個とその子孫238個がすべて終了し、終了していないものは0だった（`.work/1443-process-tree.txt`）。

判定：修正後の実行体でも、macOSのM0〜M9の自動の判定は合格。レモンの決定A（2026-11-27）により、手作業MNL-01a〜05の子孫プロセスの後始末も、この記録で確かめたとみなす。手作業の終わり方（q、BYE、窓を閉じる、Ctrl+C）は、自動の判定のexit-quit・exit-bye・fault-window・中断の場面と同じ経路である。よってmacOSのMNL-01a〜05は合格。

## IA-16・IA-17（999・1001の採否、1446）

2026-11-28、ロクによる静的転記。最終根拠は[音源監査](AUDIO_TARGET_AUDIT.md)「最終採否（1140、2026-11-22、利用者の決定）」§1〜3と[エミュレータ計画](EMULATOR_CORE_PLAN.md)「背景1画面の試作と測定（1001、2026-11-22）」。既存記録の照合であり、再測定・実聴・採否のやり直しはしていない。

### IA-16：8対象と測定範囲

採用版は、各文書のまとめて進める版（SNESはSNES-FRAMES併用）。倍率は音源単体の最重負荷の音声時間÷wall時間であり、CPU・画面・装置を含む機種全体ではない。WindowsはWindows 11／Ryzen 7 7700、Linuxは原則WSL／同CPU、Apple IIだけUbuntu 26.04.1実機／Core i7-8700K。MacはmacOS 27.2.1／Apple M5。

| 対象 | モデル・採用版 | 最重負荷 | Windows / Linux / Mac | 採否 | 個別文書・測定記録 |
|---|---|---|---|---|---|
| CHIP-8 | 原型とSUPER-CHIPのブザー、XO-CHIPのpatternとpitch、まとめ処理版 | xo_8khz_pattern_pitch | 33.78× / 38.23× / 50.59× | Forthで維持 | [CHIP8_AUDIO_FORTH.md](CHIP8_AUDIO_FORTH.md); [JSON 1](measurements/2026-11-20-chip8-os-acceptance.json) |
| ZX Spectrum | 48Kのbeeper、128Kのbeeper＋AY、まとめ処理版 | 128k_period_zero | 3.59× / 4.14× / 5.34× | Forthで維持 | [ZX_SPECTRUM_AUDIO_FORTH.md](ZX_SPECTRUM_AUDIO_FORTH.md); [JSON 1](measurements/2026-11-20-zx-spectrum-os-acceptance.json) |
| NES | NTSCの5声（DMCを含む）、まとめ処理版 | fast_max_noise_dmc | 6.17× / 6.88× / 9.17× | Forthで維持 | [NES_DMC_FORTH.md](NES_DMC_FORTH.md); [JSON 1](measurements/2026-11-20-nes-dmc.json), [JSON 2](measurements/2026-11-20-nes-sid-windows-listening.json), [JSON 3](measurements/2026-11-20-linux-audio-listening.json) |
| Commodore 64 | 3声のレジスタモデルと独自のフィルター近似（PAL）、まとめ処理版 | 最大フィルター・同期・混在 | 1.03× / 1.17× / 1.43× | Forthで維持 | [SID_FORTH.md](SID_FORTH.md); [JSON 1](measurements/2026-11-20-sid.json), [JSON 2](measurements/2026-11-20-nes-sid-windows-listening.json), [JSON 3](measurements/2026-11-20-linux-audio-listening.json) |
| SNES | S-DSPの8声、BRR、envelope、noise、pitch modulation、echoとFIR、まとめ処理版 | dense_8khz_reg_ram（`SNES-FRAMES`を使う場合） | 28.69× / 30.34× / 28.04× | `SNES-FRAMES`を本体に残す（1188） | [SNES_DSP_AUDIO_FORTH.md](SNES_DSP_AUDIO_FORTH.md); [JSON 1](measurements/2026-11-20-snes-dsp-os-acceptance.json), [JSON 2](measurements/2026-11-22-snes-dsp-macos-acceptance.json), [JSON 3](measurements/2026-11-22-snes-dsp-macos-timing.json), [JSON 4](measurements/2026-11-22-snes-dsp-macos-final-play.json) |
| Apple II | II／II+（NTSC）の内蔵スピーカー、Mockingboard、まとめ処理版 | card_8khz_bus | 5.82× / 2.74× / 7.49× | Forthで維持 | [APPLE2_AUDIO_FORTH.md](APPLE2_AUDIO_FORTH.md); [JSON 1](measurements/2026-11-22-apple2-audio-windows-acceptance.json), [JSON 2](measurements/2026-11-22-apple2-audio-linux-acceptance.json), [JSON 3](measurements/2026-11-22-apple2-audio-macos-acceptance.json) |
| Amiga | Paulaの4声ステレオ、DMA、手動DAT、IRQ、attach（PAL）、まとめ処理版 | volume/period変調 | 5.52× / 6.44× / 7.95× | Forthで維持 | [PAULA_FORTH.md](PAULA_FORTH.md); [JSON 1](measurements/2026-11-20-paula.json), [JSON 2](measurements/2026-11-20-paula-ym-windows-listening.json), [JSON 3](measurements/2026-11-20-linux-audio-listening.json) |
| Atari ST | YM2149の3声、noise、envelope、I/O、STのbyte bus、まとめ処理版 | fast_period1 | 3.21× / 3.83× / 4.87× | Forthで維持 | [YM2149_FORTH.md](YM2149_FORTH.md); [JSON 1](measurements/2026-11-20-ym2149.json), [JSON 2](measurements/2026-11-20-paula-ym-windows-listening.json), [JSON 3](measurements/2026-11-20-linux-audio-listening.json) |

8対象とも、上記最終採否は3 OSでの実聴・物理Ctrl+C後の停止・再再生を完了と記録する。WindowsのwaveOut、WSLのpacat→WSLg PulseAudio RDPSink、Apple II実機Linuxのpw-play→PipeWire、Macの実機聴取を区別する。WSLは物理Linux/ALSAの証拠ではなく、Apple IIの実機もALSA直結は未確認。Macの各受け入れ節は個別文書にあり、一部の生ログはその機械の.workのみ。ここではリンク先記録を転記し、別機械の生ログの再取得はしていない。捕捉できるのは既存の待機・確認点の範囲で、確認点のない合成中のCtrl+Cまで後始末を保証しない。

CHIP-8・ZX・SNES・Apple IIは利用者了承後の測定。NES・SID・Paula・STは他アプリを止めていない既存測定で、利用者決定どおり再測定しない。SIDのWindows 1.03倍はC64全体の余裕ではない。SID内部の遅い計算は未測定で、全体結合時に内訳を測って判断する。

[1188の測定と決定](SOUND_CORE_DESIGN_STUDY.md#124-決定利用者2026-11-22)（§12.1〜12.4）：書き直したForthのみでもLinux実機のbrr_filter3_pitchmaxは0.74倍。細かい共通部品への分割では準備と状態管理が残り、最大音程の約0.9〜1.0倍という値は実装測定ではなく見積もり。SNES-FRAMESを本体に残す方針例外を維持し、速くした参照Forthもaudioなし構成用に残す。機種共通の本体部品は追加しない。上表のSNES 28.69/30.34/28.04倍と、別CPUの1188の内訳測定を同一標本にしない。

| 対象 | 保留変種 |
|---|---|
| CHIP-8 | 原機のスピーカーの電気特性 |
| ZX Spectrum | +2、+3、クローン、ULAのバス競合、AYのポートB |
| NES | PALとDendy、カートリッジの拡張音源、DMAによるCPUの停止とバス競合 |
| Commodore 64 | 6581と8580のアナログ特性、D418のデジ再生、合成波形、NTSC |
| SNES | SPC700、DSPの細かいスロットの時刻 |
| Apple II | IIe、IIc、IIgs（DOCを含む）、PAL、カセット出力、SC-01とSSI263、Mockingboard以外のカード、6522のタイマーと割込み |
| Amiga | NTSC、ECS、アナログとLEDのフィルター、Agnusのスロット |
| Atari ST | STEのDMA、Falcon、アナログの混合 |

各文書のほかのモデル外項目も保留。理由は必要なCPU側エミュレータがまだないことであり、調べて「不要」と判断したのではない。必要時に機種別タスクを追加する。判定案：IA-16は合格。最終採否§1〜3との転記の食い違いは見つからなかった。SNES個別文書に残る「1188のあとは…置き換えた部品」という旧予定は、同文書冒頭と1188最終決定より古い履歴として扱う。

### IA-17：Windowsの背景試作

入力は256×240、32×30タイル、2ビットプレーン、属性バイトによるパレット選択。スクロールとスプライトなし。Windows 11 Pro 10.0.26300／Ryzen 7 7700／Zig 0.17.1、-Doptimize=fast -Dcpu=baseline。他アプリ停止の利用者回答後、負荷ごとに新規プロセス7回、順序を回し、語だけのUTIME区間の中央値。Pythonの独立計算とバッファ・画素を毎回照合。SHOW・窓提示・起動・検査の時間は含まない。

| 負荷 | 7回中央値 µs/画面 | 60Hz比率 |
|---|---:|---:|
| naive8 | 4276.55 | 25.66% |
| fast8 | 691.38 | 4.15% |
| to32 | 1969.00 | 11.81% |
| put_indexed | 24.59 | 0.15% |
| put_rgb | 24.63 | 0.15% |
| put_rows | 43.24 | 0.26% |

出典：[Windows測定JSON](measurements/2026-11-22-background-prototype-windows.json)のenvironment・method・result.workloads・sources。6負荷すべて、7値からの中央値と計画文書の値が一致。fast8は8画素を1セルへまとめ、GFX-INDEXEDで色変換を本体に任せるため、測定範囲ではForth維持・本体追加なし（利用者、2026-11-22）。スプライト・優先順位合成・4枚以上のビットプレーンは未測定。Forthで描画を書いて不足が出たとき、機種共通入力を決めて別タスクを追加する。Macの後続測定をこのWindows決定の入力や標本に混ぜない。audioなしでもこの描画判断は変わらず、graphicsなしでは描画語の提供を要求しない。判定案：IA-17は合格。照合した条件・値・決定の食い違いなし。

## IA-14 英日の文書照合（1444）

判定案：**照合完了・D1〜D4解消済み（今回の照合範囲で合格案）**。[対応表・語の全件表・旧引用と解消内容](INTEGRATION_ACCEPTANCE_1057_DOCS_AUDIT.ja.md)を参照。旧§3の15行は修正後すべて一致、未判定0。178綴り・179項目とPCM-STOP/TASKの補足43項目を照合。D1はMacの非ブロッキングI/O実機合格、D2はLOOP/+LOOPのHELP・日本語訳と再生成、D3はLinux TkのTclによるclose検証、D4は現行backend対応へ修正し再照合した。処理・契約は変更していない。実機受け入れは再実施しておらず、機械的検査だけを意味の照合の代わりにはしていない。

## Historical snapshot / 初期表の履歴（2026-11-26、99afe6d）

以下は旧値を残すための引用であり、現行判定には使わない。

### Historical / 旧 3. IA×OS×構成・backend

計画§2より広い構成でadapterが実行した合格は補足証拠として残す。各セルの原判定・理由・場面別証拠は、出典runのledger.jsonの同一ia/configuration/backend行を参照する。手作業を要するIAは下記の総合判定を優先する。M11はLinux専用でWindows/macOSでは全IA-01〜13がN。

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

IA-11のP/Uは保存起動・appendの自動成功まで。計画末尾Bが要求する活動中の完全復元は道具§4のZig試験で別記し、窓差替えの試験を実paint競合の証拠にはしない。LのIA-13 M10は要約に結果がなく未確認。Aは短命・逸脱した子孫の寿命証拠がなく、適用可能な全場面を未確認とし、exit 0や他OSの合格で埋めない。

### Historical / 旧 4. 全OS・全構成に共通の静的判定

| IA | 判定 / Verdict | 根拠・残件 / Evidence and remaining work |
|---|---|---|
| IA-14 | P | 1444 audit complete; D1–D4 resolved; proposed pass within audited scope / 1444照合完了、D1〜D4解消済み、照合範囲で合格案。末尾のIA-14節を参照 |
| IA-15 | P | Review §3 and validation §6; original plan/decisions unchanged |
| IA-16 | P | Review §4; 1140 §1–3 and plan §6 agree; no remeasurement |
| IA-17 | P | Review §5; six stored medians agree; no native additions |
| IA-18 | U | This ledger prepared; native/manual/timing and L/A provenance remain open |

### Historical / 旧 5. 未実施・未確認と追記手順

| 対象 / Item | 状態 / State | 次の確認方法 / Next procedure |
|---|---|---|
| IA-04 / MNL-05 | 未実施 | OSごとに保存アプリの窓を手で閉じ、同じプロセスの待機解除・端末回復を観察。連番/処理/保留/破棄とpipe/taskの自動照合を分けて記録。 |
| IA-06 / MNL-02 | macOS数値測定は合格（A7）、MNL-02は未実施 | 1425の初回（A6、未確認）は保持。1440の修正後の測り直し（A7）で合格。MNL-02の聴取は1426で別に依頼。 |
| IA-07のnative能力 / 非EXTENSION描画 | 未実施 | OS/backendごとに能力表示と非対応待機拒否、期限/入力/取消しによる終了を同一runで照合。WT/WCのPをnativeへ流用しない。 |
| MNL-01a / 01b / 01b-f | 未実施 | M0のpathでn、searchでa/b、別起動でfを個別依頼。世代と画像保持を目視しIA-05へ結び付ける。 |
| MNL-03a / 03b | 未実施 | 待機中の物理Ctrl+Cと、task取消し後の再投入を別依頼。入力/カーソル・音/窓の継続と回復を観察しIA-08へ結び付ける。 |
| MNL-04 | 未実施 | 保存bye題材でq、窓消滅と音停止を観察。IA-09のプロセス回収自動ログと分離する。 |
| IA-11 / real paint | 未確認 | 計画末尾Bの同時PCM/task/window Zig試験とD2子/pipe試験の実行記録をOS別に関連付ける。実paintとの競合の観察・試験は差替えと分離する。 |
| macOS 全場面 | 未確認 | 起動前からesloggerのfork/exec/exitを採取し全所有子孫の寿命と端末・場面結果を関連付ける。欠測・権限失敗も保存し、間欠pollのみで回収合格としない。 |
| Linux M11 / IA-13; M10 | 未確認 | Linux原ledger/manifestを取り込み、M11のX11除外能力、M10 image境界の証拠と理由を追記。 |
| L/A の出所 | 未確認 | Claudeが原ledger/manifest、実行版/dirty diff、記録版、OS/機器/backend/音経路、SHA-256、原ログを添付。 |

各手作業は計画§7どおり一度に1件。依頼時に実行体の絶対パス、OS/backend/音経路、対象窓、コマンド、操作・期待結果・止め方を示す。DwmFlush非対応実環境はR6決定の除外を維持し、再要求しない。

#### Claudeの追記欄

| 日付 / Date | IA / OS / Config / backend | run / tested / recorded | 自動 / 総合判定 Auto / Overall | 原ログ・SHA-256 / Raw logs | 機器・音経路 / Devices | 人の回答 / Human reply | 制約・次の方法 / Limits, next method |
|---|---|---|---|---|---|---|---|
| — | — | — | — | — | — | — | — |

新しいrunを別行で追加し、旧失敗・未確認と置換理由を残す。raw hashとhuman-reply.jsonを結び付け、要約の出典と直接ログを区別する。英日同じキーの行を同時に更新し、自動判定だけでMNLや測定を合格へ変更しない。


## IA-15：計画・結果・履歴の照合（1445）

計画英日§2のIA-01〜18、§4のM0〜M11、§7のMNL手順、§8の33.34/50 ms・16,666,667 ns・1,200/1,199フレーム・2組と80%時4組・PCM 48,000 Hz/512/4,096・underrun 0、末尾B/B/B・D1〜D5 A・IA-11 Bは一致。凍結ハッシュも記録値と一致し、計画は変更しない。

食い違い：初期§3/5が後続の完了を反映せず、IA-15の初期PとIA-18準備中が現在に見える状態だった。現行表へ更新し旧表は履歴として保持。macOS A6はA7、1426の回収未確認は1443、初回MNL-03a失敗は1442後の再実行で更新されたことを明示した。IA-14は監査表の照合範囲に限定。

**判定案：IA-15は未確認**。英日でIA・構成・閾値・手順・今回の分類と未確認理由は一致するが、L19のrun ID、L/Aの元manifest・実行版/dirty diff・記録版・原ログhash等の不足を文書だけでは補えない。A43の実行版73b782c、A7の6b6a7ac＋1440作業ツリー、手作業58fa00a＋1442を同じバイナリと扱わない。今回の記録基点は `22cfba22e7cebb82d0a8fc9e9da964fc9f7ec9fc`＋本作業ツリー更新（2026-11-28）とし、実行版と区別する。遠隔.workの記述は所在の転記であり、本機の実在確認を主張しない。

## 最終集約（1447）

2026-11-28、ロク。下記は判定案。全体の採否はレモンが決める。§3は本節の全セルを示す現行表に更新した。

3 OS × 12構成 × 3 backend × 18 IA = **1,944セル**。P=合格、F=不合格、U=未確認、N=適用外。各セルは「判定:根拠コード」で、コード表とOS・構成・backendを合わせて根拠・理由・次の方法を一意に指定する。未実行はNにしない。計画§2の構成限定を超えるセルは補足範囲で、Uでも自動的に1057の必須作業にはしない。静的IAは同じ照合を108行へ展開した重複を含むため、集計は独立試験数ではない。

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

### 全体の判定案

3 OSの自動機能の要約、M0の人の観察、IA-06数値測定は上記の根拠範囲で合格。Linux Lの自動合格はbackend未取得のためnativeセルへ割り当てず未確認を保持する。Tk/terminalは別runの自動機能・IA-07だけを採用し、nativeの数値や観察を流用しない。IA-14は監査範囲、IA-16・17は既存決定の照合、IA-18は欠測も含む分類・集約の完成として合格案。現行セルに不合格はないが、旧失敗を消した意味ではない。

**1057全体は未確認のままとする案**。必須範囲に残るIA-07 M0/native（3 OS）、IA-11 M0/M9の完全復元・実paint競合、Linux/macOS M10のIA-13、IA-15の出所不足（Linux Lのbackend割当てを含む）は完了を妨げる案。IA-04・08・09のM1/M2/M9などの未確認は、計画§2で適用される枝だけ同一構成の証拠を補う。MNLのM0合格で他構成を埋めない。計画外のbackend/構成の補足Uは、それだけでは完了を妨げない。最終の範囲判断と採否はレモンに委ねる。

crossビルドは実機実行と数えない。IA-16のWSL/pacat/RDPSinkとnative Apple II/PipeWireは既存決定の別経路であり、今回のLinux画面受け入れの代用ではない。1422のXvfb/台本入力は人の観察に算入しない。IA-11の差替え窓は実paintの証拠ではない。実提示は計測端点外。R6のDwmFlush非対応実環境はレモンの決定で完了要件から除外され、未実施のまま保持し、再確認を求めない。この除外を別のセルのNには流用しない。


## 07:02の状態表（更新前の履歴）

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



## 再集約（1451）

2026-11-28、ロク。Claudeの07:4x確認結果はレモン提供の確定情報として採用。原試験は再実行していない。ローカルの出所JSON・Windows原記録と試験の機能条件を確認した。以下は更新した判定案で、全体の採否はレモンが決める。

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

全1,944セルを再集計。旧U:I・U:Q・U:R・U:Vは0。Linuxの元のIA-07未確認（M1/M4/M6/M7）はbackendの判明だけでは合格にせずU:Kへ分類した。

| Code | 更新した根拠・判定範囲 |
|---|---|
| K07 | IA-07 M0/nativeは3 OS合格。tag=105 reason=2048：Windows 17/23場面・13,245件、Linux 17場面・13,263件、macOS 17場面・13,217件。normal draws/waitsは順に1199/1222、1199/1871、1199/1849、全てIA-CLEAN error=0。nativeの完了待機成立と期限・入力終了を確認。非対応拒否はWT/WC・L19・A24で別途合格。 |
| R11 | 決定Bの範囲でIA-11合格。保存起動・資源を持ったLOAD-DICTIONARYの自動合格と、src/tests/task_reap_test.zigの「1057 bound restore …」・src/main.zigの「1057 D2 …」を組み合わせる。既定ビルドで実行され、機能除外時のみskip。zig build test：Windows成功（22cfba2同内容）、Linux 1672/1724 passed・52 skipped、macOS 1659/1714 passed・55 skipped（両者HEAD 22cfba2）。窓は差替えhost。実paint競合は未試験であり、決定Bの要求には含まれない。 |
| I13 | M10/image-boundary: Linux `20261128-074434-f362c963`, macOS `20261128-074557-31b09102`, HEAD `22cfba2`; `[DEFINED] SAVESYS . [DEFINED] APP-ENTRY! . BYE` → `0 0`, status 0; 保存題材なし。Windows Wと同じ境界で合格。 |
| S15 | 出所・履歴の区別は下表で更新し、IA-15は合格案。機器等の未取得情報は未取得として保持。旧U:Vによる全体未確認を置き換える。 |

### 出所の追補（IA-15）

索引は各機の `.work/1451-provenance-{windows,linux,macos}.json` に保存（139/32/41 run）。本機には確認用JSONがあるが、遠隔機の原run一式があることは主張しない。各行のargv・手作業単位は索引に保存。差分は各runの `working-tree.stdout`、実行体・保存実行体のSHA-256は `M*/binary.json` の `binary_sha256` / `app_sha256` に保存される。索引の `binaries` 値はnullなので、索引自体にハッシュ値が収録済みとは扱わない。Windows W/M0原記録では両フィールドの値を確認。遠隔の所在・結果は提供情報に基づく。

| OS | run ID | 用途 / argv・手作業単位 | backend | HEAD | dirty lines | SHA-256 location |
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

L19はTk `20261126-204141-6cc18c01`、terminal `20261126-204538-356dcc99`。Linux Lはnative、92617e7＋148行の差分であり、現行U:Qを既存の自動合格へ割り当て直した。manifestなしのWindows `20261126-181938-verification-7ab559a1` はREPORT英日とsummary.jsonのsmoke検証集約で、独立実行ではない。summaryは別のsmoke runを参照し、現行の受入れ合格の根拠には使っていない。欠落manifestを合格根拠として補完しない。記録版は22cfba2＋本台帳更新で、各行の実行版とは区別する。

### 必須範囲の残件と全体の判定案

**IA-15は合格案、1057全体は未確認を維持する案。** 旧4項目のうちIA-07 M0/native・IA-11決定B・M10 IA-13・IA-15は上記で解消。ただし計画§2の指定範囲には下表の未確認が残る。

| IA | OS / configuration / backend | 理由と次の確認方法 |
|---|---|---|
| IA-04 | Windows/Linux/macOS; M1/M2/M9 native | U:C：同一構成の連番・pipe・完了・終了の照合を確認。M1は窓なしで入力・期限の終了、M2/M9は窓を含む待機解除を記録。 |
| IA-08 | Windows/Linux/macOS; M1/M2/M9 native | U:H：該当構成の取消し・回復・再投入の観察をMNL-03に関連付ける。M0の観察を流用しない。 |
| IA-09 | Windows/Linux/macOS; M9 native | U:H：同一M9の生存資源を持った終了の自動照合とMNL-04/05の観察を関連付ける。 |
| IA-07 | Linux; M1 native | U:K：Lの元の判定は未確認。graphics除外時の能力・非対応拒否と期限/入力/取消しによる終了を原ログで確認し、不足時は同構成で実行。 |

必須未確認は計22セル（IA-04 9、IA-08 9、IA-09 3、IA-07 1）。その他のUは計画§2の対象構成・backendを超える補足であり、単独では完了を妨げない。特に非M0の応答・聴取、M1以外の追加IA-07、未実行の追加backendは補足。IA-11の実paint競合は未試験の補足であり、完了条件に加えない。静的IAの108行への重複展開は独立した実行数ではない。旧表・旧判定は上に保持し、本節と§3の更新を優先する。

## 利用者の決定後の最終集約（1447）

2026-11-28、ロク。旧い全体判定案・集計表・07:52の必須残件一覧を削除せず、本更新で置き換える。現行の状態表は§3。以下の根拠は、今回レモンから提示されたClaudeによる原ログの確認結果であり、ここで実行試験や遠隔ログの確認をやり直したものではない。

### 利用者の決定 — 2026-11-28

レモンの決定：「人の観察は省略」。計画§7のとおり、人の観察MNL-03/04/05を求めるのはM0だけとする。M1/M2/M9のIA-08・IA-09は、同一構成の取消し・回復・終了の自動判定で判定する。この決定は非M0の人の観察を実施済みにするものではなく、M0の観察も流用しない。全体の採否はレモンが決める。

| コード / 更新セル | 根拠と判定範囲 |
|---|---|
| C28 / IA-04、3 OSのM1/M2/M9 native（9） | Claudeが自動判定の原ログを確認。Windows W `20261126-193555-1be64edd`、Linux L `20261126-193548-e41e290a`（native）、macOS A43 `20261127-210221-a3d08a10`。各OS・構成でIA-RECONCILEは16件すべてproduced = processed + discarded、pending=0を満たし、不一致0。IA-CLEAN error=0は各13件。完了待ちtag=105 reason=2048はWindows M2/M9が13,259/13,215件、Linuxが11,307/13,248件、macOSが13,215/13,212件。M1は窓なしで0件。計画§2に従い、存在しないproviderを除いて合格。M1の照合には今回確認されたWを使い、その他のセルに対するW1の起動修正は維持する。 |
| K28 / IA-07、Linux M1 native（1） | LのM1は描画を持たない構成で待ちと照合が進み、IA-CLEAN error=0で終了する。Windows・macOSのM1を合格にした根拠と同じ形であり、合格。窓なしの構成でpaint待ちが成立したとはしない。 |
| D28 / IA-08、M1/M2/M9 native（9）；IA-09、M9 native（3） | W・L・A43（macOSはeslogger記録下の再実行）の同一構成の取消し・回復・終了の自動判定結果と、上記2026-11-28のレモンの決定に基づき合格。合意した観察範囲での自動判定による合格であり、非M0のMNL-03/04/05は未実施。 |

### 現行状態表の再集計

108行×18項目＝1,944セルを数え直した。UからPへの更新は22セル（IA-04：9、IA-07：1、IA-08：9、IA-09：3）。U:I/U:Q/U:R/U:Vは引き続き0。共有の静的判定を各行へ展開したセル数は、独立した実行数ではない。

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

### 必須範囲と全体の判定案

**1057は合格の案。** 上記の日付つき利用者決定を適用すると、計画§2が求める構成・backendの範囲に未確認は残らない。07:52の案に記録した必須未確認22セルは解消した。残るU 631セルは補足であり、完了を妨げない。これは案であり、レモンによる全体の採否決定ではない。

補足として残る未確認を以下に示す。

- 計画§2の指定の組合せを超える未実行の構成・backend（U:B、552セル）。
- 必須構成以外の追加の混在provider照合（U:C、14セル）。
- 非M0の応答・観察と、必須範囲外の追加backendの観察（U:H、35セル）。非M0の聴取・数値による応答判定も未確認（U:T、12セル）。
- M0のbackend別確認とM1以外の追加IA-07（U:K、18セル）。
- IA-11の実paint競合は未試験で決定Bの範囲外。窓を代替した根拠は、その制約を保持する。物理提示は測定終点の範囲外。機器・音声経路の不足情報は引き続き未取得であり、新たな根拠を補完しない。

実DwmFlush非対応環境に関する従来のR6除外は維持する。必須M0の人の受入れと既存の静的決定は、記録済みの根拠と制約を保持する。

## 補足確認後の最終集約（1461・1462・1466）

2026-11-28、ロク。本節で旧集計863合格・0不合格・631未確認・450適用外とその残件一覧を更新する。旧記録は履歴として残し、§3を更新した。これはレモンの「1と2を進めて」（2026-11-28）に基づく、計画が求める組合せを超えた補足確認。根拠はレモンが提示したClaudeによる原ログの集計と実行結果であり、今回の台帳更新で実行試験や遠隔ログの独立した検証を行ったものではない。機器・音声経路やハッシュの不足情報は補完しない。

### 利用者の決定 — 2026-11-28

レモンの「人の観察は省略」に従い、観察はM0のみ。非M0のIA-08/09は取消し・回復・終了の自動判定で決める。この決定で人の観察やIA-05の世代・最後の有効画像の目視確認を実施済みとはしない。観察済みのM0/native以外のIA-05は未確認を保持する。IA-06 M8/M9はレモンの決定「A：計画の範囲外（N）として記録し、測定しない」に従う。M8/M9の全backendセルに適用する。nativeの測定は3 OSともアダプタ `tests/scripts/integration-acceptance.py:606`（`IA-06 requires M0`）が拒否した。計画の対象は3 OS / M0（36・134・138行）。M8/M9のrequests・searchの自動判定は合格済みだが、応答の測定とは区別する。全体の採否はレモンが決める。

### 根拠と更新セルの規則

| コード | 根拠と範囲 |
|---|---|
| C29 | IA-04：ClaudeがnativeのM4各15件・M8各16件をW `20261126-193555-1be64edd`、L `20261126-193548-e41e290a`、A43 `20261127-210221-a3d08a10`で集計。IA-RECONCILEはすべてproduced = processed + discarded、pending=0、不一致0。M0 Tk/端末はWT/WC、Linux `20261126-204141-6cc18c01` / `20261126-204538-356dcc99`、macOS `20261126-212155-d3dee35b` / `20261126-212545-283a799a`で各17件一致。Linux M11 Tk `20261126-212518-c4bf82b5` / 端末 `20261126-193339-3d89dcf4`は各16件一致。合格。 |
| K29 | IA-07 M2〜M9 native：窓のあるM2/M8/M9は描画の完了待ちtag=105 reason=2048が各1万件以上。窓のないM3〜M7は描画を使わず正常終了、IA-CLEAN error=0。U:Kの18セルを解消し、既存Pの根拠は保持する。 |
| D29 | IA-08/09 M0 Tk/端末：C29記載のM0 runで全場面の自動判定が合格。macOSの寿命追跡だけの不足は1424のeslogger記録で解消済み。提示された自動判定を記録するもので、新たな人の観察ではない。 |
| B29 | 下表のM1〜M10 Tk/端末：M1〜M9の該当する全場面の自動判定が合格。Windows/Linuxは各run 142〜143行、非pass行0。IA-RECONCILE不一致0（M1/M2/M8/M9各16件、M4 15件）、IA-CLEAN error=0。M10 image-boundaryは `0 0`、status 0。非nativeのM2/M8/M9のIA-FRAME-WAIT rejectedは想定どおりの非対応拒否であり、native描画完了ではない。M0 Tk/端末と同じ自動判定の境界でIA-01/02/03/04/07/08/09/10/12と該当IA-13を合格とする。IA-11は既存R11の決定Bの試験と今回の起動・復元結果を組み合わせる。語彙の除外とIA-05/06の制約は保持する。 |
| N:X11N | Linux M11 nativeはX11なしのビルドでnative窓がないためIA-01〜13は適用外（既存IA-06のN:X6は保持）。Tk/端末の結果とは別。 |
| N:X6P | IA-06 M8/M9は上記の日付つき利用者決定により計画外。測定の合格とはしない。 |

| OS | Tk run | terminal run | Tested HEAD |
|---|---|---|---|
| Windows | `20261128-082054-79804a11` | `20261128-085831-e04c06b1` | `342c288` |
| Linux | `20261128-082946-39097f0a` | `20261128-090844-ba212d3b` | `342c288` |
| macOS | `20261128-084449-82e1c68d` | `20261128-091839-a7711485` | `342c288` |

macOS B29は1443と同じく、アダプタ上は各run全142場面が `native lifetime tracing required` のみでunverified。`.work/1465-eslogger.jsonl`（14,265件）の記録下で実行した。`tests/scripts/eslogger-process-tree.py` の照合でTkはsigma起動179・子孫343、端末は起動179・子孫100、終了しないプロセス0。自動判定の結果とこの終了記録を組み合わせ、1443と同じ根拠で合格とする。アダプタの元の未確認判定もここに明記して保持する。

### 変更セルと再集計

下表の全OSはWindows・Linux・macOS。未確認だったセルだけを更新し、既存の合格・除外は保持する。変更セルの一覧を組合せごとにすべて示す。

| 範囲 | IAと変更 | セル数 |
|---|---|---:|
| 全OSのM4/M8 native・M0 Tk/端末、Linux M11 Tk/端末 | IA-04 U:C → P:C29 | 14 |
| 全OSのM0 Tk/端末 | IA-08/09 U:H → P:D29 | 12 |
| 全OSのM2/M3/M5/M8/M9 native、Linux M4/M6/M7 native | IA-07 U:K → P:K29 | 18 |
| 全OSのM1〜M9 Tk/端末 | IA-01/02/07/09/10/12 U:B → P:B29（各54）；IA-11 U:B → P:R11（54） | 378 |
| 全OSのM1〜M6/M8/M9 Tk/端末 | IA-03 U:B → P:B29 | 48 |
| 全OSのM1/M2/M4/M8/M9 Tk/端末 | IA-04/08 U:B → P:B29（各30） | 60 |
| 全OSのM9/M10 Tk/端末 | IA-13 U:B → P:B29 | 12 |
| 全OSのM1/M2/M4/M8/M9 Tk/端末 | IA-05 U:B → U:H（実行済み、目視確認は未確認） | 30 |
| 全OSのM8/M9 native・Tk/端末 | IA-06 U:T（6）/ U:B（12）→ N:X6P | 18 |
| Linux M11 native | IA-01〜05/07〜13 U:B → N:X11N | 12 |

108×18＝1,944セルを再集計。U→P 542、U→N 30、U→Uの理由変更30（変更602セル）。前回比はP +542、F変化なし、U −572、N +30。U:Hは未実行だったIA-05の30セルを観察不足に分類し、M0 IA-08/09の12セルを合格にしたため35から53へ増加。U:Tは12から6へ減少、U:B/C/Kは0。共有の静的判定のセル数は独立した実行数ではない。

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

### 残る補足の未確認と全体の判定案

**1057は合格の案。** 計画の必須範囲の結果は変わらない。補足確認で未確認は631から59セルへ減少した。全体の採否はレモンが決めるため、引き続き案とする。

| 残るコード | 該当セルの全範囲 | セル数 |
|---|---|---:|
| U:H | IA-05：全OSのM0 Tk/端末、M1/M2/M4/M8/M9 native・Tk・端末。加えてLinux M11 Tk/端末。世代・最後の有効画像の目視確認は未確認で、取消し・終了の自動判定で代替しない。 | 53 |
| U:T | IA-06：全OSのM0 Tk/端末。負荷・基準の正式な応答測定と聴取は未確認。 | 6 |

IA-11の実paint競合は決定Bの範囲外で未試験。物理提示は測定終点の範囲外。機器・音声経路の未取得情報は保持する。従来のR6除外と必須M0/nativeの人の受入れは、記録済みの境界を保持する。
