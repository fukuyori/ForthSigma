# タスク1371：タスク制御03-D スケジューリング

## 今回の修正範囲とレビュー確認

2026-11-24の再レビュー指摘をソースで確認し、全5点を反映した。誤りと判断して退けた指摘はない。今回編集したファイルは次の3件である。

| ファイル | 要点 |
|---|---|
| `src/core/task_schedule.zig` | FIFO位置を引き継ぐ置換提案、実行中要求の取消し提案、ストリーム世代、区別付き待機結果、入力上限定数を追加した |
| `src/tests/task_schedule_test.zig` | 既存7試験をAPIに追従させ、継続I/O中の置換・実行中取消しと世代・3種の待機結果の3試験を追加した（計10試験） |
| `docs/TASK_CONTROL_IMPL_1371.md` | 修正後の契約、検証結果、03-Fへの引継ぎを記録した |

既存の通常実行経路、State配置、`src/forth.zig`、workerの命令実行経路は今回変更していない。通常経路の変更箇所はない。命令ごとの定期取消し確認、公開Forth語・スタック効果・公開エラー番号を追加していない。初回実装で追加済みの `src/forth_test.zig` の試験importはそのままであり、今回の修正では編集していない。開始時点で他タスクの差分と未追跡ファイルが多数存在したため、今回の成果を上記3件に限定する。

## 設計上の選択と理由

詳細計画10節、方式判断8節、判断記録の「利用者の決定（2026-11-24）」、状態機械1363、待機登録1368の9節・W16、利用条件G1/T1を確認した。スケジューラは引き続き割当なしの純粋な判定APIである。キュー・台帳・VM・OS待機・スレッドの実体は持たない。`turn` は注入されたClockを1回読み、時計エラーを返す。実際の処理と同期はホスト側で行う。

### 1. 置換位置と公平性

旧実装は待ちの同系列IDだけを返し、末尾へ追加する契約であった。I/O追加とゲーム置換の継続で末尾へ押し戻される指摘は妥当である。

`Admission.placement.replace` は旧IDと列内indexを返し、その位置で新規項目へ置換する契約とした。同じkindとstreamだけを対象とする。FIFO位置は引き継ぐが、入力・ID・期限は新規要求のものである。ホストは資源予約後、列の整合した観測と排他的取得に基づいて確定する。失敗時は旧項目を維持する。

試験では `[io1, io2, io3, g]` から各I/O発送後にI/Oを追加し、さらにゲームを3回ずつ置換する。ゲームが元の位置から先頭へ進み、3件のI/O発送後に最新ゲームIDが発送候補になることを確認する。これは順序の決定的試験であり、50 msの実時間達成の証明ではない。

### 2. 実行中取消しと結果の鮮度

`Submission.running` に実行中1件のID・kind・streamを渡す。同じkindとstreamのゲーム/TUI要求を受理すると、`Admission.cancel_running` に実行中の旧IDを返す。待ち置換の旧IDは `placement.replace.id` から取得する。取消しは要求の提案であり、状態機械の終端確定や即時停止を意味しない。

ホストは系列ごとの現在世代を `Submission.current_generation` に渡す。受理するゲーム/TUI要求には、その値を1増やした `Admission.generation` を返す。ホストは新要求とその結果にこの世代を保存し、同系列の現在世代と `resultIsCurrent` で照合してから公開する。待ちも実行中もなく、古い完了結果だけが残る場合にも世代は進む。別kind・別streamの実行中要求は取り消さない。I/Oは置換・世代更新・同系列取消しの対象としない。

逆圧・禁止による拒否は世代と取消しを返さない。世代のu64上限では `ResultOutOfRange` を返し、周回させない。これは既存の内部エラー集合であり、公開数値を定めるものではない。ホストは系列の世代を古い結果が届き得る間に初期化・再利用してはならない。初回の現在世代は0である。

配置確定・現在世代更新・取消し要求をホストの同期境界で一体として扱い、失敗時はすべてを維持する。結果公開も投入受理と同じ同期境界で再照合する必要がある。このモジュールは状態を所有しないため、実取消しトークン操作や結果公開への接続は統合側の責任である。

### 3. 待機結果の区別

曖昧な `sleep_until: ?Instant` を廃し、`Decision.next` を次の区別付き結果とした。

| 結果 | 条件と意味 |
|---|---|
| `run_again` | 残作業、取り出し・発送提案、到来済み期限がある。OS待機せず再巡回する |
| `sleep_until(Instant)` | 残作業がなく、キュー・ホスト内部期限の最小値まで待機できる |
| `wait_for_wake` | 残作業も期限もない。新規作業や容量変化等の起床通知を待つ |

どちらの待機も、終端更新後の全条件probeと起床世代の再確認を前提とする。通知障害回復・取消し・回収・decoder・描画等の内部期限が必要ならホストが絶対期限を渡す。起床のたびに期限を作り直さない。満杯で抑制された読取りだけを残作業として空回りしない。

### 4. 有限上限

完了記述数の16を `Limits.completion_records`、期限記述数の16を `Limits.deadlines` とした。完了通知取込みの `Limits.notifications` とは独立した量である。

| 1巡の有限上限 | 値 |
|---|---:|
| 待ち項目の全走査 | 4件 |
| 完了記述入力 | 16件 |
| 完了コピー対象 | 4件 |
| 結果・診断コピー総量 | 合算16 KiB |
| 完了通知取込み | 16件 |
| その他の各供給元 | 各8事象 |
| 計算用読取り・別出力排出 | 各16 KiB |
| 絶対期限入力 | 16件 |
| workerへの引渡し提案 | 1件 |

入力・I/O読取り・出力排出・完了・描画・取消し・回収の走査開始位置を巡回し、全供給元へ独立の有限枠を与える既存方針は維持した。コピーは部分位置をホストに保持させ、最終片のコピーと検査後だけ公開する。上限値から応答時間や処理時間の達成を主張しない。

## 試験と実行結果

PowerShell、Zig 0.17.1で実行した。キャッシュ先はプロセス環境変数 `ZIG_GLOBAL_CACHE_DIR` と `ZIG_LOCAL_CACHE_DIR` でworktree内の `.zig-global-cache` と `.zig-cache` に設定した。速度・時間測定は実施していない。build標準集計の所要時間も性能評価に使用していない。

| コマンド | 結果 |
|---|---|
| `zig build test --summary all -j2` | 終了0、23/23 steps成功。core 1258成功・10スキップである |
| `zig build test -Ddebug=false --summary all -j2` | 終了0、23/23 steps成功。core 1185成功・83スキップである |
| `zig fmt --check src/core/task_schedule.zig src/tests/task_schedule_test.zig` | 終了0、診断なしである |
| `git diff --check` | 終了0である。開始時から差分がある `src/forth_test.zig` のLF→CRLF警告のみである |

両構成でcore試験を実行し、追加した3試験を含む全10件のスケジューラ試験が成功した。その他のrunはcachedであり、今回実行した件数には加算していない。語群除外構成は今回実行していない。参照先はruntime_baseのClock・Instantのみであり、語群やStateへの依存は追加していない。`git diff --check` は未追跡ファイルを検査しないため、今回の3ファイルについて末尾空白も別途確認した。

## 未確認事項と引継ぎ

指摘4のとおり、`worker` と `result_dependencies` は現在、呼出し側が設定する宣言である。試験で確認できるのは宣言に対する拒否だけであり、呼出し元の真正性や依存辺作成の阻止まで強制しているわけではない。

次を、利用者指定の新しいタスク「タスク制御03-F」（親1051）へ引き継ぐ。tqueの参照・変更・登録は本作業では行っていない。

- workerからの投入とタスク間結果依存を実際の入口で阻止すること。
- 台帳満杯時の逆圧を、資源予約・投入確定・解放と結合すること。完了入力上限16件は台帳容量検査の実装ではない。
- 1巡のコピー合算16 KiBとG1の投入→公開100 msを両立できるか確認すること。入力コピー・結果検査・反映も含めて評価すること。

実際の列置換、取消しトークン、世代保持と結果公開、取得競合、VM新規生成、Snapshot失効、共通Wake・OS待機・全条件probe、実I/O・描画・回収との統合は未確認である。worker1枠の維持、入力整合性（ID重複や同系列複数待ちがないこと）、世代の同期もホスト側の契約である。実時間の期限達成・60 Hz・管理1 ms/巡・取消し10 ms・回収100 msは未検証である。

方式確定・公開、公開Forth語・公開エラー値、VM再利用は保留のままである。今回の修正に追加の利用者判断を必要とする事項はない。コミット・ブランチ・タグ・push・tque変更・パッケージ作成・作業ツリー外への変更は行っていない。

## 最終Git状態

HEADは35523f6のdetached状態である。以下は開始時から存在する差分を含む `git status --short` の全出力である。今回の3ファイルも元から未追跡のため、表示上の追加・削除はない。

```text
 M docs/CORE_EXTENSION_DESIGN_DECISIONS.md
 M docs/CORE_EXTENSION_DETAILED_DESIGN.md
 M docs/CORE_EXTENSION_PLAN.md
 M docs/CORE_EXTENSION_WORKER_STATE_AUDIT.md
 M docs/README.ja.md
 M docs/README.md
 M docs/TASK_CONTROL_PLAN.md
 M docs/WINDOWS_NATIVE_DISPLAY_VALIDATION.md
 M src/core/defs.zig
 M src/core/dictionary_image.zig
 M src/core/error_reporting.zig
 M src/core/exception_registry.zig
 M src/core/image_append.zig
 M src/core/image_restore.zig
 M src/core/words_system.zig
 M src/forth.zig
 M src/forth_test.zig
?? docs/TASK_CONTROL_ACCEPTANCE.md
?? docs/TASK_CONTROL_AUDIT_ALLOWED_SET.md
?? docs/TASK_CONTROL_AUDIT_REENTRY.md
?? docs/TASK_CONTROL_AUDIT_SHARED_STATE.md
?? docs/TASK_CONTROL_CONFIG_MATRIX.md
?? docs/TASK_CONTROL_DETAILED_PLAN.md
?? docs/TASK_CONTROL_IMPL_1359.md
?? docs/TASK_CONTROL_IMPL_1360.md
?? docs/TASK_CONTROL_IMPL_1361.md
?? docs/TASK_CONTROL_IMPL_1371.md
?? docs/TASK_CONTROL_IMPL_1384.md
?? docs/TASK_CONTROL_METHOD_COMPARISON.md
?? docs/TASK_CONTROL_METHOD_DECISION.md
?? docs/TASK_CONTROL_PROTO_1352.md
?? docs/TASK_CONTROL_PROTO_1353.md
?? docs/TASK_CONTROL_PROTO_1354.md
?? docs/TASK_CONTROL_PROTO_1355.md
?? docs/TASK_CONTROL_PROTO_1356.md
?? docs/TASK_CONTROL_STATE_MACHINE.md
?? docs/TASK_CONTROL_USAGE_CONDITIONS.md
?? docs/TASK_CONTROL_WAIT_REGISTRATION.md
?? src/core/task_context.zig
?? src/core/task_permissions.zig
?? src/core/task_policy.zig
?? src/core/task_schedule.zig
?? src/core/task_snapshot.zig
?? src/core/task_transfer.zig
?? src/tests/task_control_1384_test.zig
?? src/tests/task_control_w1_test.zig
?? src/tests/task_permissions_test.zig
?? src/tests/task_schedule_test.zig
?? src/tests/task_snapshot_test.zig
?? src/tests/task_transfer_test.zig
```
