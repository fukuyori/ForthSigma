# タスク制御02-D：投入キューと完了領域（1366）

作成日：2026-11-24。作成者：ロク。

## 変更ファイルと要点

- `src/core/task_queue.zig`：内部API、既定待ち4件・設定可能なFIFO、単一worker、JobRunner、項目ごとの完了領域、取消し・RELEASE・所有者終了、期限超過、停止不能保持、終了・joinを追加した。
- `src/tests/task_queue_test.zig`：偽runner・偽時計・通知失敗注入、取得競合、寿命と終了の試験を追加した。
- `src/forth_test.zig`：上記試験のimportを1行追加した。fmtによる改行の統一も行った。作業開始時点で存在した他タスクのimportは保持した。
- 本報告書を追加した。

開始時点には既存変更・未追跡ファイルが多数存在した。本作業はそれらを基礎とする。Git HEADとの差分全体を1366の変更と扱ってはならない。

## 設計上の選択と理由

### 所有と排他

`Queue(capacity)`はホスト1本とworker1本を前提とする。`DefaultQueue`の待ち容量は4件であり、実行中の1件は待ち容量に含めない。ホストの取り出しとworkerの受取りは同じatomic gateの排他区間で行い、キュー参照を一方だけへ移す。runnerとcleanupと共通通知callbackはgate外で呼ぶ。gate内にはキューの移動と短い状態操作を置き、VMの実行・転送を置かない。

ホストが取り出した取消しは、その呼出しで取消し内容を封印し、次のホスト巡回の`poll(job)`でrelease-storeによる公開と共通Wakeへの通知を行う。workerが先に受け取った場合は取消しトークンだけを立てる。workerは実行前にトークンを確認するが、runnerへ入った後の結果はrunnerの返却値を採用する。要求が立っていても成功・失敗を取消しへ変更しない。確定後の再照会・取消しは終端を変更しない。

`release`は外部有効性を失効させて取消し経路へ進む。`stop`は新規投入を閉じ、待ち項目と実行中項目の外部有効性を失効させ、実行中へ取消しを要求する。既に受け取った項目・結果領域は保持する。公開ハンドルの識別子・所有者検査、全件の台帳管理は後続結合側の責任であり、このキューに公開ハンドル表を重複実装していない。

### 結果と参照

`JobRunner`の返却値は成功・失敗・取消し、内部理由、内部値である。公開エラー番号ではない。結果本体・診断バッファを保持するcontextの所有は呼出し側に置き、本モジュールで追加コピーや確保を行わない。`cleanup_fn`は入力・Snapshotの実行側参照を一度だけ外すためのcallbackである。ホストの待ち取り出しまたはrunner帰還後に呼ぶ。Job自体・保存結果・通知先をこのcallbackで解放してはならない。

完了内容の書込みとcleanup後にready印をrelease-storeし、共通WakeOpsへnotifyする。ホストはacquire-load後に結果を読み、ホスト専用のterminalへ一度だけ受領する。workerはホストのResourceTableを変更しない。notify失敗は`notification_failed`にラッチし、通知の有無・回数とは独立した`poll`で回復する。共通Wakeの世代・OS登録は既存WakeOpsと後続1369の責任である。

Queueとrunner・通知contextはstartからjoin完了まで固定アドレスで保持する。受理済みJobは少なくとも`poll`による終端受領まで保持する。保存結果の利用者がいる間はその領域を保持する。一度使ったJobを初期化し直して再投入しない。再投入は新しいJobとする。外部失効したJobも内部台帳から失わずpollする必要がある。

### 期限

注入するClockと共通WakeOpsのcallbackはホスト・worker双方から呼べることを契約とする。期限は投入時に`Clock`と`Deadline.afterMilliseconds`で絶対期限へ変換する。用途別の既定値はG1=50、G2/T1=100、I1=200 msであり、submitの引数で項目別に設定できる。負の無期限指定は受理しない。0は直ちに期限到来となる。

ホストの`expire`はキュー全体を走査し、期限切れ項目を排他的に取り出す。先頭が未到来でも後続の到来を処理する。workerも受取り後・runner開始前に同じ時計で検査し、期限切れの仕事をrunnerへ渡さない。結果は`failed / queue_expired`とし、取消し・runner失敗・時計失敗と区別する。これは再投入可能な失敗の内部表現であり、公開状態や数値エラー値の決定ではない。時計失敗は`failed / clock_failed`として待ち続けない。

ホストは毎巡回で全内部Jobをpollし、`nextDeadline`を共通待機の最早期限へ組み込む。通知なしでも同巡回の照会で取消しと期限超過を得られる。10 ms以内のメイン巡回・公開の実時間保証は1371等の結合検証が必要である。

### 停止と通知先

workerのOSスタック要求は1 MiBに固定し、利用条件のOSスタック等4 MiB枠内に収める設定とした。実VMとの結合時の十分性・OSの実予約量は未確認である。workerの仕事待ちには専用Wakeを用い、ホストの共通Wakeを消費しない。専用Wakeのnotify失敗時にも停止要求を再確認できるよう、workerの休止待ちは実時計の10 msを上限とする。この待機期限は実行途中の取消し確認ではない。仕事の待ち期限判定には注入Clockを用い、試験では偽時計とする。

停止期限超過を診断するホストは`markUnresponsive`を呼ぶ。以後のsubmitは満杯・終了とは別の`WorkerUnresponsive`で拒否する。既存の待ち項目を次の実行へ渡さず、実行中の枠と関連参照を保持する。印を立てただけで成功・取消し・停止を生成しない。ホストはstopで待ち項目の取消しを進められる。

`joinIfStopped`は終了印を確認できなければfalseを返し、ブロックするjoinへ入らない。確認後に実際のjoinを行い、最後のnotifyも含むworkerの参照消滅を待つ。deinitは未joinや未処理キューを拒否し、切離し・強制終了は行わない。停止期限そのものの監視・診断はホストの責任である。

## 既存経路への影響

通常Forthの実行経路・runAsWorker・命令ディスパッチには変更を加えていない。命令ごとの定期取消し確認は追加していない。既存ファイルへの追加は試験ルートのimport 1行であり、本モジュールは実行アプリへまだ結合しない。公開Forth語・スタック効果・公開エラー番号を導入しない。

## 試験と実行結果

PowerShellから実行した。Zigは`0.17.1`である。キャッシュを作業ツリー内へ限定するため、実行時は以下の環境変数を設定した。

```powershell
$env:ZIG_LOCAL_CACHE_DIR = Join-Path $PWD '.task1366-cache'
$env:ZIG_GLOBAL_CACHE_DIR = Join-Path $PWD '.task1366-global-cache'
```

初回は既定キャッシュ作成で`AccessDenied`となった。環境変数指定後はコンパイルが進んだが、既存ホスト試験の固定パス`.zig-cache/...`の親ディレクトリが存在せずファイル作成が失敗した。作業ツリー内に`.zig-cache`を作成し、各構成を順に再実行した。ソースの試験内容を緩和する変更は行っていない。

初回実装時の差分について以下がすべて終了コード0で成功した。

| コマンド | 結果 |
|---|---|
| `zig build test -j2` | 成功 |
| `zig build test -Ddebug=false -j2` | 成功 |
| `zig build test -Ddebug=false -Dfloat=false -Dfiles=false -Dgraphics=false -Daudio=false -Dextension=false -j2` | 成功 |
| `zig fmt --check src/core/task_queue.zig src/tests/task_queue_test.zig src/forth_test.zig` | 成功 |
| `git diff --check` | 成功 |

初回実装の新規6試験は上記3構成で成功した。`-j2`はビルド並列度の指定であり、試験内容を変更しない。検証終了後、ローカルキャッシュを`.zig-cache/task1366-local`、グローバルキャッシュを`.zig-global-cache`へ移し、既存の無視対象内に整理した。Git設定やignore規則は変更していない。

新規試験は以下の6件である。

1. 待ち満杯、ホスト取消しの次巡回公開、RELEASE、G1期限境界、実行しないcleanup。
2. 偽runner内の同期点でworker受取りを固定し、後続項目のホスト取得と実行中取消しを256回反復する。notify全失敗・世代不変の併合状態でもpollで全結果を回収し、成功不変とcleanup 512件を検査する。
3. 初回は取消しとworker受取りを1024回反復した。レビュー修正で両結果を確実に起こす同期試験へ置換した（末尾参照）。
4. 停止不能診断後の専用拒否、停止前の未完了維持、実行中RELEASE相当の保持、待ち所有者終了、帰還後joinを検査する。
5. 項目別期限、後続0期限、最早期限、時計障害、用途別既定値を検査する。
6. ホストがexpireしないworker側期限検査、および取消し要求後のrunner失敗・取消し帰還と診断値の保持を検査する。

各試験に独立監視スレッドの20秒期限を設けた。gate・runner・joinのどこで停止しても監視期限でテストプロセスを失敗終了させる。これはハング防止であり、処理速度・応答時間の測定ではない。

## 未確認事項

1362の実行関数、Snapshot・VMの実参照、台帳1364、診断1365、共通待機1369、巡回1371とは未結合である。偽runnerのcleanup件数検査は実Snapshot解放・VM破棄の実証ではない。10 ms取消し公開、100 ms回収、用途別の投入から公開までの実時間達成、追加メモリ予算は未測定である。速度・時間測定を行っていない。nativeで戻らないrunnerを強制停止する機構は設けない。試験の停止不能は同期点で帰還を保留して再現し、検査後に明示的に解放する。

## 利用者判断が必要な事項

方式の最終採用・公開、公開語名・スタック効果・エラー番号は引き続き保留である。今回の内部API実装をそれらの確定と扱わない。既決定のworker 1、待ち4、旧Snapshot規則、タスクごとの新規VMを変更する判断は行っていない。本モジュールの範囲では新たな利用者判断を要する仕様変更はない。

## 最終Git状態

コミット・ブランチ作成・タグ・プッシュ・tque変更は行っていない。以下は開始時からの変更を含む全件の git status --short である。1366の対象は冒頭の4ファイルである。

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
?? docs/TASK_CONTROL_IMPL_1366.md
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
?? src/core/task_queue.zig
?? src/core/task_snapshot.zig
?? src/core/task_transfer.zig
?? src/tests/task_control_1384_test.zig
?? src/tests/task_control_w1_test.zig
?? src/tests/task_permissions_test.zig
?? src/tests/task_queue_test.zig
?? src/tests/task_snapshot_test.zig
?? src/tests/task_transfer_test.zig
```
## レビュー指摘への修正（2026-11-24）

指摘1・2・3・5・6を確認して修正した。指摘4は変更不要である。今回の変更は本報告書、src/core/task_queue.zig、src/tests/task_queue_test.zigの3件だけである。通常Forth経路と既存ファイルへの追加変更はない。

- 完了通知：実行中・通知中・notificationFailed()がtrueの場合、nextDeadline()へ10 ms後の再確認期限を含める。通知中の印はready公開から通知失敗記録までの隙間を覆う。時計・期限計算異常時は即時再確認とする。ホストはobserve、全内部Jobのpoll、nextDeadlineによる期限決定、共通Wake待機の順に処理する。通知失敗印はラッチされる。ホストはこの印を無視して無期限待機へ変更してはならない。実時間の10 ms保証ではない。
- 待機異常：worker_failedに元のbase.Errorを保存し、新規投入をWorkerFailedで拒否する。待ち項目はfailed / worker_failedとしてcleanup後に直ちに公開する。結果作成後にgate内でsealed・readyを公開し、未完成結果の受領を防ぐ。原因フィールドは終了確認後またはgate排他下で読む。所有者によるClosedと区別する。worker_clockとworker_wakeはstart前にのみ設定する内部注入点である。既定は実時計・専用Wakeである。
- 未開始のjoinIfStoppedはtrueを返す。試験補助のthread有無による待機回避は外した。二重deinit防止の判定は保持した。
- submitのkickをgate解放後へ移した。待つ側はobserve後にgate内で状態を確認するため、投入との競合で起床を失わない。
- 入口前の取消し確認はTASK_CONTROL_STATE_MACHINE.md 3節のqueuedからrunningへの遷移にある「既に要求済みなら入口の実行前に確認する」に従う。runner開始後の正常結果は取消しへ置換しない。
- markUnresponsive後もrunner帰還後は10 ms上限の休止待機を繰り返す。専用kick失敗時にもstopを再確認するため維持する。実行中の命令単位の確認ではない。所有者はstopとjoin確認を進める必要がある。

試験には実Wakeによるホストの通知なし期限待機、専用kick失敗からの回復、ワーカー待機・時計異常、待ち項目の失敗と原因保持、再投入拒否、未開始joinを追加した。実Wake待機の時計callbackからrunnerを解放し、通知されずtimeoutとなることを検査する。OS内部でワーカーが実行される瞬間までは固定しない。1024回の確率的取消し競合試験は、開始前のホスト取得とrunner入口同期後のワーカー取得を確実に起こす試験へ置換し、両結果・実行回数・cleanup回数を検査する。既存256回の両経路試験と20秒の独立監視期限も維持する。

実VM・ホスト台帳・1369の待機登録との結合と実機の停止上限は未確認である。方式採用、公開Forth語、公開エラー値、VM再利用は利用者の判断を待つ。今回、追加の公開仕様判断は行っていない。

### レビュー修正後の検証結果

PowerShell、Zig 0.17.1で次の全コマンドが終了コード0で成功した。試験は合計9件である（初回6件のうち1件を置換し、3件追加）。-j2はビルド並列度の指定である。

| コマンド | 結果 |
|---|---|
| zig build test -j2 | 成功 |
| zig build test -Ddebug=false -j2 | 成功 |
| zig build test -Ddebug=false -Dfloat=false -Dfiles=false -Dgraphics=false -Daudio=false -Dextension=false -j2 | 成功 |
| zig fmt --check src/core/task_queue.zig src/tests/task_queue_test.zig | 成功 |
| git diff --check | 成功 |

レビュー検証用キャッシュは検証終了後、作業ツリー内の既存無視対象である.zig-cache/task1366-review-localと.zig-cache/task1366-review-globalへ移した。Git設定は変更していない。実装・試験・本報告書以外のソースは変更していない。コミット、ブランチ、タグ、プッシュ、tque変更、速度・時間測定は行っていない。

レビュー修正後のgit status --shortは次のとおりである。開始時点の既存変更を含む。本件の3ファイルは初回実装から未追跡である。

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
?? docs/TASK_CONTROL_IMPL_1366.md
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
?? src/core/task_queue.zig
?? src/core/task_snapshot.zig
?? src/core/task_transfer.zig
?? src/tests/task_control_1384_test.zig
?? src/tests/task_control_w1_test.zig
?? src/tests/task_permissions_test.zig
?? src/tests/task_queue_test.zig
?? src/tests/task_snapshot_test.zig
?? src/tests/task_transfer_test.zig
```
