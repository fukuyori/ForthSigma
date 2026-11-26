# タスク制御の受入れ総括（1382・1383）

[English](TASK_CONTROL_ACCEPTANCE_SUMMARY.md)

2026-11-25現在（2026-11-26に3a節とAC表を更新、main `9e5e5c3`、Claude）。作成時の照合のmainは `6856d99`、作成者：ロク。全体判定は **合格（2026-11-26、利用者の決定 案1）**（全ACの判定は合格。3a節）。下表は指定報告書とgit logの記録からの判定であり、今回の再実行結果ではない。コミットは実行時の版と結果記録の版を区別する。

合格はそのACの指定条件を満たす再現試験の記録があること、失敗は最新の有効な確認で条件を満たさないこと、未確認は証拠不足または残る実機条件、対象外はそのOSが担当外であることを示す。skip・終了コード0・クロスビルドだけでは合格にしない。実機結合を含むACは一部成功でも未確認とする。

## 1. 根拠の索引

| ID | 報告書・節と範囲 | 実行版・記録コミット | runまたはログ |
|---|---|---|---|
| R-W | [TASK_CONTROL_IMPL_1382.md](TASK_CONTROL_IMPL_1382.md) — 1382 9節と「最終検証（Windows）」、1400「Validation」の最新test・plain・runtime成功。1382 1・5節にAC別対象試験。 | `latest tested d3d0d66; record 6856d99` | .work/ac28-*.log (1400); .work/main-gap/checks-final/ (1382) |
| R-L | [TASK_CONTROL_IMPL_1381.md](TASK_CONTROL_IMPL_1381.md) — 1381 6.1節：Linux実機のtest・plain・runtime、例、C00〜C16。端末・画面の合格ではない。 | `33f37f7` | No run ID recorded / run ID記載なし; .work/task-public-matrix/ |
| R-M | [TASK_CONTROL_IMPL_1383.md](TASK_CONTROL_IMPL_1383.md) — 1383「Mac 実機での事前確認」「Mac実機での構成C00〜C16」：実機test・plain・runtimeと後続の全構成試験。 | `preflight record 0019f97; matrix tested adcc38b / record f33eb57` | No run ID recorded / run ID記載なし; .work/task-public-matrix/ |
| C | [TASK_CONTROL_IMPL_1382.md](TASK_CONTROL_IMPL_1382.md) — 1382「出力保留の修正後の取消し位相の本測定」、1383「取消し位相の本測定の結果」：各OS 4,100/4,100、欠測・超過0。 | `ff7363b (record d6fa707)` | W 20261124T222722Z-ce3f2f55; L 20261124T222719Z-24000d52; M 20261124T222720Z-457847ee |
| W | [TASK_CONTROL_IMPL_1382.md](TASK_CONTROL_IMPL_1382.md) — 1382「出力の保留の後の Windows の対話の場面の本測定」：6題材、独立10分×2回、超過0。 | `eb45fed (record 3a80b26)` | 20261125T064638Z-e22f81c2; 20261125T074647Z-593d4db2 |
| LM | [TASK_CONTROL_IMPL_1382.md](TASK_CONTROL_IMPL_1382.md) — 1382「G1 ワーカーの高速化の後の対話の場面の本測定」：Linux・Mac全指標で超過0、待ち4件は追加対象。 | `0bb8a41 (record 04eddb5)` | L 20261125T032136Z-45c9954c / 20261125T042205Z-e63d6606; M 20261125T032140Z-29144992 / 20261125T042150Z-34c7c910 |
| F | [TASK_CONTROL_IMPL_1382.md](TASK_CONTROL_IMPL_1382.md) — 1382「最新のソースでの残りの項目の本測定」：Snapshot・メモリ・pipe反映・起動・サイズ。 | `3a80b26; A=35523f6 (record 579201a)` | W 20261125T084814Z-8d7094e2; L 20261125T084806Z-4269e6d6; M 20261125T084809Z-72cea647 |
| E | [TASK_CONTROL_IMPL_1382.md](TASK_CONTROL_IMPL_1382.md) — 1382「80%規則による追加の測定」：Snapshot 1,000プロセス×3世代、メモリ7題材×10、超過0。 | `f5dcd15 (record adcc38b)` | Snapshot W 20261125T092612Z-992f9968 / L 20261125T092605Z-7b4c10ee / M 20261125T092608Z-3fa3a22b; memory W 20261125T092700Z-552b637a / L 20261125T092712Z-c36d1684 / M 20261125T092650Z-40ebbe5b |
| X | [TASK_CONTROL_IMPL_1400.md](TASK_CONTROL_IMPL_1400.md) — 1400「Validation」：Windows C00〜C17（18構成・155コマンド）合格。追加検査のLinux・Mac実行は未実施。 | `tested d3d0d66; recorded 6856d99` | .work/ac28-matrix-final.log; .work/task-public-matrix/ |
| T | [TASK_CONTROL_ACCEPTANCE_MANUAL.md](TASK_CONTROL_ACCEPTANCE_MANUAL.md) — 手順書「Pseudo-terminal automation」「Process ownership and collection failures」「PENDIN and residual input」：道具と制約。3 OS受入れrunの実施記録ではない。 | `d3d0d66` | No acceptance run ID in the cited reports / 指定報告書に受入れrun IDなし |

<a id="ac-verdicts"></a>

## 2. AC別・OS別の判定

Rは各OSのR-W/R-L/R-Mを指す。未確認欄の記号は3節の確認方法・担当タスクへ対応する。AC-07/09/13/21等の機能条件と、別途残るD07計時・容量条件は区別する。

| AC | 対象 | Windows | Linux | Mac | 根拠・未確認の確認先 |
|---|---|---|---|---|---|
| AC-01 | 取消し | 合格 | 合格 | 合格 | R, C  1382 §1/§5: `src/tests/task_control_w1_test.zig` |
| AC-02 | メイン応答 | 合格 | 合格 | 合格 | R, C, W, LM, F, T; U1; 2026-11-26: 1397, 1398, 1399, 1407, 1408 |
| AC-03 | 実行文脈 | 合格 | 合格 | 合格 | R, C  1382 §1/§5: `src/tests/task_control_1384_test.zig`, `task_control_w1_test.zig`, `task_permissions_test.zig` |
| AC-04 | 隔離 | 合格 | 合格 | 合格 | R  1382 §1/§5: `src/tests/task_cancel_memory_test.zig`, `task_job_test.zig` |
| AC-05 | 実資源の所有 | 合格 | 合格 | 合格 | R, C, W, LM, F, T; U1; 2026-11-26: 1397, 1398, 1399, 1407, 1408 |
| AC-06 | 禁止語 | 合格 | 合格 | 合格 | R  1382 §1/§5: `src/tests/task_permissions_test.zig` |
| AC-07 | Snapshotデータ | 合格 | 合格 | 合格 | R, E  1382 §1/§5: `src/tests/task_snapshot_test.zig` |
| AC-08 | Snapshot寿命 | 合格 | 合格 | 合格 | R, E  1382 §1/§5: `src/tests/task_snapshot_test.zig` |
| AC-09 | 転送・結果 | 合格 | 合格 | 合格 | R  1382 §1/§5: `src/tests/task_transfer_test.zig` |
| AC-10 | 結果API | 合格 | 合格 | 合格 | R  1382 §1/§5: `src/tests/task_results_test.zig`, `task_public_api_test.zig` |
| AC-11 | 状態競合 | 合格 | 合格 | 合格 | R, C  1382 §1/§5: `src/tests/task_state_machine_test.zig` |
| AC-12 | 台帳ID | 合格 | 合格 | 合格 | R  1382 §1/§5: `src/tests/task_ledger_test.zig` |
| AC-13 | 逆圧 | 合格 | 合格 | 合格 | R  1382 §1/§5: `src/tests/task_queue_test.zig` |
| AC-14 | 通知回復 | 合格 | 合格 | 合格 | R  1382 §1/§5: `src/tests/task_wait_reproduction_test.zig` |
| AC-15 | 待機登録 | 合格 | 合格 | 合格 | R  1382 §1/§5: `src/tests/task_wait_reproduction_host_test.zig` |
| AC-16 | 待機優先・期限 | 合格 | 合格 | 合格 | R, C  1382 §1/§5: `src/tests/task_wait_host_test.zig` |
| AC-17 | 描画契約 | 合格 | 合格 | 合格 | R  1382 §1/§5: `src/tests/task_paint_test.zig` |
| AC-18 | 実際の複合待機 | 合格 | 合格 | 合格 | R, C, W, LM, F, T; U1, U2; 2026-11-26: 1397, 1398, 1399, 1407, 1408 |
| AC-19 | 再現試験の公平性 | 合格 | 合格 | 合格 | R  1382 §1/§5: `src/tests/task_schedule_host_test.zig` |
| AC-20 | 実際の公平性 | 合格 | 合格 | 合格 | R, C, W, LM, F, T; U2, U3; 2026-11-26: 1397, 1398, 1399, 1407, 1408 |
| AC-21 | VM連続実行・回収 | 合格 | 合格 | 合格 | R, E  1382 §1/§5: `src/tests/task_reap_reproduction_host_test.zig` |
| AC-22 | 終了・復元 | 合格 | 合格 | 合格 | R  1382 §1/§5: `src/tests/task_reap_test.zig` |
| AC-23 | 停止不能ホスト | 合格 | 合格 | 合格 | R  1382 §1/§5: `src/tests/task_reap_reproduction_host_test.zig` |
| AC-24 | 実資源の終了 | 合格 | 合格 | 合格 | R, C, W, LM, F, T; U1, U4; 2026-11-26: 1397, 1398, 1399, 1407, 1408 |
| AC-25 | 利用例の結合 | 合格 | 合格 | 合格 | R, C, W, LM, F, T; U1, U2; 2026-11-26: 1397, 1398, 1399, 1407, 1408 |
| AC-26 | Windows・Linux構成 | 合格 | 合格 | 対象外 | R, X, T; U1, U2; 2026-11-26: 1397, 1398, 1399, 1407, 1408 |
| AC-27 | Mac構成 | 対象外 | 対象外 | 合格 | R, X, T; U1, U2; 2026-11-26: 1397, 1398, 1399, 1407, 1408 |
| AC-28 | 公開語・文書 | 合格 | 合格 | 合格 | R, X, T; N1 |
| AC-29 | 通常経路の生成コード | 合格 | 合格 | 合格 | F; size approval f5dcd15; U5; 2026-11-26: 1391–1393 (B/A′ normal-loop machine code identical; time not judgeable) |

AC-21の合格は同一Queue/workerで新規VMを連続実行する現契約の確認であり、温めたVMプール内部の再利用を実証した意味ではない。AC-26/27のC00〜C16の構成実行自体は3 OSとも合格。行全体では残る実機結合を未確認とし、1400のC17等を過去の17構成へ遡及適用しない。

## 3. 未確認事項の確認方法と担当

| ID | 確認方法・範囲 | tque担当 |
|---|---|---|
| U1 | 手順書AC-02/05/18/24/25と構成別実機条件を、task・音・窓の結合題材で確認する。実キー・カーソル・画面復旧、失敗時の表示保持、60Hz提示、画面33.34ms・端末50ms、追加フレーム期限超過を実時刻と目視・聴取で記録する。 | 1394 → Windows 1397 / Linux 1398 / Mac 1399 — 2026-11-26 済み（3a節） |
| U2 | 実入力・I/O可用・完了・paint/close・期限を同じ待機へ接続し、同一プロセスで連続供給する。進行・優先・入力欠落・I/O排出を記録する。別セッションの並行実行だけで公平性を合格にしない。 | 1395 → Windows 1397 / Linux 1398 / Mac 1399 — 2026-11-26 済み（3a節） |
| U3 | acquiredと投入可能の端点を独立に保存し、最大滞留50/100/100/200ms、Snapshot取得開始→投入可能100msと照合する。Snapshot API所要時間だけで代用しない。 | 1396 → Windows 1397 / Linux 1398 / Mac 1399 — 2026-11-26 済み（3a節） |
| U4 | OSごとに疑似端末手順を実行し、process/thread/child・端末を記録、失敗した採取を再実行する。Macは起動前から終了までSystem Trace/DTrace等のfork/exit生存期間イベントを採り、接続失敗・欠落も保存する。POSIX残留キーはnative readと照合する。Macの子孫回収は間欠採取だけで断定しない。 | Windows 1397 / Linux 1398 / Mac 1399; POSIX residual input: Linux 1398 / Mac 1399 — 2026-11-26 済み（3a節） |
| U5 | 同構成A/A′/Bの単一VM負荷と通常ループ逆アセンブル比較を用意し、中央値+1%・p95+2%、配置の不確かさ、D01方針を照合する。サイズ承認だけで生成コード・性能を完了にしない。 | 1390 → OS measurements 1391–1393 (OS assignment not live-verified / OS割当は今回照会不能) — 2026-11-26 済み（3a節） |
| N1 | 実施済み：1400を実機のLinux・Macで実行（Claude、2026-11-25）：test・plain・runtime-test・文書の検査と、C00〜C17の全構成が合格。記録はコミット6856d99。 | 6856d99 |
| N2 | 不要と判断（Claude、2026-11-25）：Snapshotの取得（`src/host_task_api.zig:214`）とジョブのVM（同255行）を含むタスクの確保は、すべて上限を数える割当ての仕組みを通り、その上限（同44行）がワーカーのスタックとサービスの分を含めて128MiB以内に保つ。上限の振る舞いは試験済み（`src/host_task_api.zig:794`、`src/tests/task_public_api_test.zig` の割当て失敗の試験）、Snapshotの4MiBの上限も試験済み（`src/tests/task_snapshot_test.zig:302`）。境界はOSの採取からの推定ではなく、作りで守られている。 | 登録しない |

N2はAC-07/21等に関連するD07容量の残件であり、機能再現試験の合格を取り消すものではない。1396の滞留・投入可能時刻には全メモリ境界検査が明記されていないため別案とした。N1/N2を既存番号へ割り当てたとは扱わない。

tque show 1382・1383・1390〜1399を試みたが、保存先lockへのAccess deniedで全て失敗した。番号・内容は今回の利用者指定と手順書による。現行の題名・親・完了状態は確認できていない。tque変更・登録は行っていない。

## 3a. 2026-11-26 の後続の結果

U1〜U5の確認は2026-11-26に完了した。各OSの記録は [1397](TASK_CONTROL_IMPL_1397.ja.md)（Windows）、[1407](TASK_CONTROL_IMPL_1407.ja.md)（Windowsの組の測り直し）、[1398](TASK_CONTROL_IMPL_1398.ja.md)（Linux）、[1399](TASK_CONTROL_IMPL_1399.ja.md)（macOS）、[1391](TASK_CONTROL_IMPL_1391.ja.md)（単一VM、3 OS）。途中で見つけて直したものは [1401](TASK_CONTROL_IMPL_1401.ja.md)（埋め込むテキストの改行）、[1406](TASK_CONTROL_IMPL_1406.ja.md)（Linuxの描画の高速化）、[1408](TASK_CONTROL_IMPL_1408.ja.md)（投入時の入口の検査の重複）、1404・1405（手順と基準の組）。

| 項目 | Windows | Linux | macOS |
|---|---|---|---|
| 滞留（enqueued→acquired）・Snapshot取得 | 目安内 | 目安内 | 目安内 |
| AC-18・19・20（実供給元・同一プロセス） | 成功 | 成功 | 成功（eslogger で全子孫の終了を確認） |
| 入力→画面の最大（目安33.34 ms） | 13.5 ms | 23.7 ms | 16.7 ms |
| 各フレームの期限（計画v8／macOS v6）とタスクによる追加の超過 | 0・0 | 0・0 | 0・0 |
| 目視・聴取（G1・T1・BYE） | 確認 | 確認 | 確認 |
| 単一VM（AC-29、レモンの決定 案1） | 通常ループの機械語がB・A′で同一 | 同一（命令数も確認） | 同一 |

WindowsのI1の公開→回収は、他の処理と並行した2026-11-26昼の2 runで100 msを6件超えた（最大115.9 ms）。レモンの決定（案1）で、他のアプリを止めてI1だけを独立に2回測り直し、最大72.0 ms・超過0だった（`.work/acceptance/20261126T071523Z-e2ea10b0`・`20261126T072609Z-ba34be09`、計画v8）。

残る未確認：Linuxで窓の大きさを変えた後の画素の読み戻し（`test-linux-native-window.py` の `SIGMA_TEST_RESIZE=1`。専用のXvfbが前提で、Linux機にXvfbがない。変更前のビルドでも同じエラーで、1406によるものではない）。ACの判定には含めない。

## 4. 最新結果と過去runの扱い

Cは旧位相欠測とWindows run `20261124T220657Z-67318d59` の回収超過8件を置き換える。native_runningはnative入口をholdして要求後に最大量全体を実行する保守的確認であり、処理中要求の直接観測ではない。

LMは `d6fa707` 時点のG1超過と `b7073ab` のLinux G1-open中央値116msを置き換える。WindowsのLM時点の回収超過（最大176.5ms）はWで置き換える。同期ログ出力の改善後、全題材の超過0、管理1巡最大0.517ms、公開→回収最大60.6msとなった。

Fを基礎とし、Snapshot・メモリ・待ち4件の追加規則はEで完了。Snapshot最大取得はWindows/Linux/Macで13.2/16.5/32.2ms、大きさ3,620,330/3,620,338/3,620,338 B。追加メモリ観測最大は77.1/77.0/68.9MB。pipe入力→状態はFの0.617/1.349/0.565msであり、物理画面反映ではない。Windows待ち取消し追加1,000回 `20261125T090001Z-7edefb21` は回収最大17.2ms、超過0で、旧54msの事象は再現しなかった。

Mac起動は100回の3 run `20261125T085914Z-93419dc0`・`20261125T090056Z-b099dab4`・`20261125T090057Z-24bac77a` を、決定Bによる1,000回run `20261125T090233Z-49332dc5`（`3a80b26`、記録 `e47725b`）で置き換えて判定。中央値+0.012ms、p95+0.006msで合格。Windows/Linux起動もFで目安内。サイズは3 OSとも目安内、内訳確認後 `f5dcd15` で承認済み。AC-29全体はU5が残る。

過去run・超過・欠測・旧手順は履歴として保持する。置換は同じ対象の最新判定に限り、別OS・未観測項目への転用や標本の混合をしない。UTCのrun IDが11月24日でも、上記取消しrunはJSTの11月25日の実施である。Tは自動化の追加記録であり、3 OSの実行済み結果と解釈しない。

## 5. 利用者の決定（2026-11-24〜25）

| 日付・選択 | 決定・適用範囲 | 根拠 |
|---|---|---|
| 11-24 A | 縮小回数：生成25×100、native 5種×3位相×100、待ち100、対話10分×1。正式な1,000回・3 runの出発条件と区別。 | 1382 §2; bce27b9; current user instruction / 今回の指定 |
| 11-25 B | 取消し位相をholdで確実に狙い、41ケースを再測定。旧欠測を保持。 | 1382 / 1383 “2026-11-25 決定B”; 0019f97 |
| 11-25 A | Linux G1を壁付き作業盤面のworkerで高速化し、3 OSを再測定。目安は維持。 | 1382 “G1 ワーカーの高速化の後…”; 0bb8a41 / 04eddb5; choice label from current user instruction / 選択記号は今回の指定 |
| 11-25 B | Mac起動は1,000回を1回測り直して判定、先の100回×3も保持。 | 1382 “最新のソース…”; e47725b |
| 11-25 B → A | サイズ増加を先に内訳調査（B）、その後3 OSの増加を承認（A）。未測定の単一VM時間は承認に含めない。 | 1382 “コードの大きさ…”; 03a2c40 / f5dcd15 |
| 11-25 B | 一定値のSnapshot容量・待ち4件にも固定済み80%規則を適用し追加測定。 | 1382 “80%規則…”; adcc38b |
| 11-25 B | 手動端末手順をConPTY/POSIX ptyで自動化。native目視・聴取や能力不足の未確認は保持。 | Manual “Pseudo-terminal automation (decision B, 2026-11-25)”; d3d0d66 |

2026-11-25の時点で全体は未確認で、既存番号に明示的に当てはまらない残件はN1・N2だった。2026-11-26の時点で全ACの判定は合格（3a節）で、全体の判定は合格（利用者の決定 案1）。
