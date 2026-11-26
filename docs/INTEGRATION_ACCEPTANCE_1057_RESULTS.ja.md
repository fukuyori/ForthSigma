# 1057：統合受け入れ結果台帳（1415、追記用）

[English](INTEGRATION_ACCEPTANCE_1057_RESULTS.md)

## 1. 記録の範囲と判定

2026-11-26、ロク。記録基点 `99afe6d`。1057全体は未確認で、IA-18は集約の準備段階。今回は既存ログの読取りと静的照合だけで、ビルド・実機実行・時間測定を行っていない。[計画](INTEGRATION_ACCEPTANCE_PLAN_1057.ja.md)§2/4/7/8/11と末尾の決定、[道具](INTEGRATION_ACCEPTANCE_1057_TOOLS.ja.md)、[文書・採否照合](INTEGRATION_ACCEPTANCE_1057_REVIEW.ja.md)を参照。

P=自動機能判定の合格、F=不合格、U=未確認、N=適用外、D=未実施（分類は未確認）。P/Uは自動合格だが手作業等を含むIA全体は未確認。Pは実提示・聴取・時間・完全復元競合の合格を意味しない。Nは語群除外や計画対象外であり、機器不足には使わない。静的なIA-14〜18は全OS・全構成に共通で§4を参照する。

## 2. 出典・実行版・原記録

| 出典 / Source | run ID | 実行時HEAD / Tested HEAD | 方法 / Method | ledger SHA-256 |
|---|---|---|---|---|
| W | 20261126-193555-1be64edd | 92617e7c6b8ca97079f074adce11d0710c37594c | tests/scripts/integration-acceptance.py --functional --configs M0 M1 M2 M3 M4 M5 M6 M7 M8 M9 M10 | 49c8cecbaf81f057fc1df57f1aef4ffdde2e4ad820c937ef0b450ce9482af5c8 |
| W1 | 20261126-201122-54d17ba8 | 92617e7c6b8ca97079f074adce11d0710c37594c | tests/scripts/integration-acceptance.py --functional --configs M1 | 33fd1c0bb941fd67757fbe747d262b98c7d669a09ad835db1dd6517ec46d7215 |
| WT | 20261126-192325-012b4581 | 92617e7c6b8ca97079f074adce11d0710c37594c | tests/scripts/integration-acceptance.py --functional --configs M0 --backend tk --frames 240 | ada16933277ed86814d64f6b2695fb97f74ad411070aa0d19fba4e00663de626 |
| WC | 20261126-192425-c5f0d86e | 92617e7c6b8ca97079f074adce11d0710c37594c | tests/scripts/integration-acceptance.py --functional --configs M0 --backend terminal --frames 240 | 35bf40136528507ab09b09d02a5630e869b80a95e623574ba930720df4d49c4b |
| L | 20261126-193548-e41e290a | 未確認 / unknown | Claude確認済み要約 / supplied Claude-checked summary | 未取得 / unavailable |
| A | 20261126-193548-73ed9e3e | 未確認 / unknown | macOS: descendant lifetime tracking absent | 未取得 / unavailable |

WのM1をW1で置き換える。旧WのM1 IA-03未確認を消さず、最新W1の合格を採用する。WT/WCは[1412報告](../.work/integration-acceptance/1412-diagnosis/REPORT.ja.md)にあるTk/terminalの240枠runで、1,200枠のWと同じ実行としない。Windowsの元記録版はmanifest/ledgerの92617e7、今回の集約版は99afe6d基点の作業ツリー。元のdirty差分・plan/fixture/binary hashを各runのmanifest.json、working-tree.stdout、M*/binary.jsonで追える。実行時HEADが同じでもバイナリ同一とは断定しない。

Windowsのrunはリポジトリ内`.work/integration-acceptance/<run ID>/`に実在し、ledgerのevidence先も確認した。機器・音経路はledgerのsystem default (unverified)のままで、人の回答は未取得。Linux/macOSのファイルにはアクセスせず、今回提示された要約を転記した。Lの「全構成合格」は適用可能な自動機能枝に限り、M10の保存起動やM0以外のIA-05へ拡張しない。L/Aの実行版・機器・backend・ハッシュ・原ログはClaudeが追記する。

## 3. IA×OS×構成・backend

計画§2より広い構成でadapterが実行した合格は補足証拠として残す。各セルの原判定・理由・場面別証拠は、出典runのledger.jsonの同一ia/configuration/backend行を参照する。手作業を要するIAは下記の総合判定を優先する。M11はLinux専用でWindows/macOSでは全IA-01〜13がN。

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

IA-11のP/Uは保存起動・appendの自動成功まで。計画末尾Bが要求する活動中の完全復元は道具§4のZig試験で別記し、窓差替えの試験を実paint競合の証拠にはしない。LのIA-13 M10は要約に結果がなく未確認。Aは短命・逸脱した子孫の寿命証拠がなく、適用可能な全場面を未確認とし、exit 0や他OSの合格で埋めない。

## 4. 全OS・全構成に共通の静的判定

| IA | 判定 / Verdict | 根拠・残件 / Evidence and remaining work |
|---|---|---|
| IA-14 | P | Review §1–2; F1–F4 corrected; N1–N3 recorded |
| IA-15 | P | Review §3 and validation §6; original plan/decisions unchanged |
| IA-16 | P | Review §4; 1140 §1–3 and plan §6 agree; no remeasurement |
| IA-17 | P | Review §5; six stored medians agree; no native additions |
| IA-18 | U | This ledger prepared; native/manual/timing and L/A provenance remain open |

## 5. 未実施・未確認と追記手順

| 対象 / Item | 状態 / State | 次の確認方法 / Next procedure |
|---|---|---|
| IA-04 / MNL-05 | 未実施 | OSごとに保存アプリの窓を手で閉じ、同じプロセスの待機解除・端末回復を観察。連番/処理/保留/破棄とpipe/taskの自動照合を分けて記録。 |
| IA-06 / MNL-02 | 未実施 | 実施前にレモンの明示確認を得て計画§8のhashを固定。M0のpath/search各1,200枠・独立2組load→baseline、80%時の追加2組、PCMと描画の同等性・個々の完了端点を照合。聴取は別の回答。 |
| IA-07のnative能力 / 非EXTENSION描画 | 未実施 | OS/backendごとに能力表示と非対応待機拒否、期限/入力/取消しによる終了を同一runで照合。WT/WCのPをnativeへ流用しない。 |
| MNL-01a / 01b / 01b-f | 未実施 | M0のpathでn、searchでa/b、別起動でfを個別依頼。世代と画像保持を目視しIA-05へ結び付ける。 |
| MNL-03a / 03b | 未実施 | 待機中の物理Ctrl+Cと、task取消し後の再投入を別依頼。入力/カーソル・音/窓の継続と回復を観察しIA-08へ結び付ける。 |
| MNL-04 | 未実施 | 保存bye題材でq、窓消滅と音停止を観察。IA-09のプロセス回収自動ログと分離する。 |
| IA-11 / real paint | 未確認 | 計画末尾Bの同時PCM/task/window Zig試験とD2子/pipe試験の実行記録をOS別に関連付ける。実paintとの競合の観察・試験は差替えと分離する。 |
| macOS 全場面 | 未確認 | 起動前からesloggerのfork/exec/exitを採取し全所有子孫の寿命と端末・場面結果を関連付ける。欠測・権限失敗も保存し、間欠pollのみで回収合格としない。 |
| Linux M11 / IA-13; M10 | 未確認 | Linux原ledger/manifestを取り込み、M11のX11除外能力、M10 image境界の証拠と理由を追記。 |
| L/A の出所 | 未確認 | Claudeが原ledger/manifest、実行版/dirty diff、記録版、OS/機器/backend/音経路、SHA-256、原ログを添付。 |

各手作業は計画§7どおり一度に1件。依頼時に実行体の絶対パス、OS/backend/音経路、対象窓、コマンド、操作・期待結果・止め方を示す。DwmFlush非対応実環境はR6決定の除外を維持し、再要求しない。

### Claudeの追記欄

| 日付 / Date | IA / OS / Config / backend | run / tested / recorded | 自動 / 総合判定 Auto / Overall | 原ログ・SHA-256 / Raw logs | 機器・音経路 / Devices | 人の回答 / Human reply | 制約・次の方法 / Limits, next method |
|---|---|---|---|---|---|---|---|
| — | — | — | — | — | — | — | — |

新しいrunを別行で追加し、旧失敗・未確認と置換理由を残す。raw hashとhuman-reply.jsonを結び付け、要約の出典と直接ログを区別する。英日同じキーの行を同時に更新し、自動判定だけでMNLや測定を合格へ変更しない。

## 6. 今回の文書検証

2026-11-26：`python scripts/check-docs.py`は指摘0、`git diff --check`は成功。新規4文書のローカルリンク106件と引用した節の実在、Windows ledgerのevidence先、1001の保存7値の中央値6件、英日構成とLFを確認した。計画の英日ファイルはHEADと同一で、決定表も変更していない。
