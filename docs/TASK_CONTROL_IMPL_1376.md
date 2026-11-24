# タスク制御04-D（1376）：回収の再現試験

更新日：2026-11-24。対象は1048配下の1376である。

## 変更ファイルと要点

- src/tests/task_reap_reproduction_host_test.zig：本番Execution、Queue、Host、Reaper、終了フックを使用するホスト結合試験である。レビューに従って同期、取消し結果、所有者終了後のworker保持の検査を修正した。
- src/tests/task_reap_child_driver.zig：runtime試験実行体を子プロセスで起動し、終了コード1と完全な診断マーカーを検査する親driverである。
- build.zig：親driverをtestとruntime-testに登録し、生成したruntime試験実行体のパスをaddArtifactArgで渡す。
- src/runtime_test.zig：ホスト結合試験の登録1行である。
- docs/TASK_CONTROL_IMPL_1376.md：本書である。

開始時の1372・1374・1375の差分は維持した。本番モジュールへの追加修正はない。通常経路の変更、公開Forth語、公開エラー値の追加もない。

## 設計上の選択とレビュー対応

### 1. 回収の6場面

成功、失敗、明示取消し、RELEASE、所有者終了、BYEの全場面でQueueを開始し、f.enteredによってworkerがrunnerへ進入したことを確認する。成功・失敗では同期点を開けて終端を待つ。明示取消し・RELEASEではそれぞれの要求後に同期点を開け、終了処理を始める前に終端を確認する。これによりRELEASEの効果を終了処理による取消しと区別する。

所有者終了はReaper.beginの後に同期点を開け、回収後もqueue.thread != nullであることを確認する。Hostの受付が残り、その所有者の再投入を拒否することも確認する。fixtureの後始末でworkerを停止・joinする。他の場面では回収後のthreadなしも確認する。

BYEでは本番フックが取消しを要求した後、同期用スレッドが同期点を開ける。先に同期点を開けて成功してしまう競合を避けるためである。場面2〜5は終端cancelledとExecution.failureのTaskCancelledを確認する。

全場面でdestroy 1回、入力Budget 0、台帳0件、待ち0件、activeなし、Executionの結果とadmissionなしを確認する。再pollでdestroyが増えないこと、Snapshot最終参照の解放後にManagerの版数が0になることも確認する。実メモリの漏れはtesting.allocatorでも検査する。

runner境界はVM生成前である。場面2〜5はworkerが取得した仕事を本番Executionへ渡して取り消す検査であり、VM生成済みとは主張しない。生成・復元済みVMの破棄は、次のRestoreGate試験で確認する。

### 新規VMの取消しと連続実行

同じSnapshotと、一度startして最後まで停止しないQueueで、取消し、成功、失敗、成功、成功の順に実行する。各Executionは新規VMを使う。成功語と失敗語は変数Vを変更し、次の仕事と元VMへ変更が残らないことを確認する。成功時は入力がAAAとなり、失敗時はDivisionByZeroとなる。

最初の取消しは、試験用AllocatorがFreshVm.createの復元Plan解放を捕捉するRestoreGateで停止する。VM確保・復元後のSnapshot参照数3と残存割当てを確認し、本番Binding.cancelとHost.requestCancelを重複して呼ぶ。同期点を開けた後はTaskCancelled、割当て数0、Snapshot参照数1を確認する。本番への試験用コールバック追加はない。

### 2. 別プロセスの終了検査

親driverは子だけにFORTHZ_1376_FATAL_CHILDを設定し、ビルドが生成したruntime試験実行体を起動する。終了コード1と「1376: retained runner; independent cleanup; fatal diagnostic; exit 1」の両方を検査する。異常終了、別の終了コード、マーカー欠落はビルド失敗である。OS別の固定パスや手動PowerShell検査は不要である。

Zig 0.17.1にはstd.process.Child.runが存在しない。インストール済み標準ライブラリを確認し、内部でChildをspawnしてstdout・stderrを回収しwaitするstd.process.runを使用した。初回のdriverコンパイルは旧APIのargsAllocで失敗し、現行のInit、Args.Iterator、Environへ修正した。

子は戻らないrunnerを保持した検査後にも同期点を開かず、本番host_task_stop.abortを呼ぶ。独立した後始末、診断callback、Cのexit(1)を通る。callbackは後始末の順序と本番診断文字列の一致を検査してからマーカーを出す。

.github/workflows/release.ymlのWindows、Ubuntu、Ubuntu ARM、macOSの各ジョブはzig build testを実行するため、子プロセス検査も同じ手順に含まれる。今回CI自体の実行結果は取得していない。

### 3. 停止未確認の保持と遅延復帰

workerがrunnerへ進入した直後に同期点で止める。完全復元のbusy拒否が取消しを起こさないことを確認し、RELEASE後にBYE回収を開始する。偽時計で回収期限を超過させ、複数回pollする。stop_unconfirmed、診断のID・所有者・要求時刻・期限超過・stoppedが偽であること、実行参照、台帳1件、Snapshot参照2、入力Budget 3バイト、thread保持、destroy 0回を確認する。

通常試験では同期点を開け、終端kindがcancelled、execution.failureがerror.TaskCancelledであることを追加確認する。回収後はdestroy 1回、Budget 0、台帳0件、Snapshot参照1、threadなし、activeなしとなる。

### 4. 同期の監視

runner、RestoreGate、進入待ち、終端待ち、回収待ち、join、BYE取消し待ちは実時計による20秒の期限で監視する。1億回の反復上限は廃止した。独立したWakeと監視スレッドによるGuardも維持する。時計はハング防止専用であり、性能や利用条件の時間測定ではない。停止・回収期限の分岐検査にはホストだけが読む偽時計を使う。

### 5. 同じworkerという表現

OSスレッドIDは比較していないため、試験名と説明を同じQueueでの連続実行へ弱めた。

### 6. 判断Aの確認範囲

明示bindしたhost_task_reap.interpretでQUIT、ABORT、未定義語エラーを発生させ、Reaper未開始、取消しなし、台帳・Snapshot・Budgetの保持を確認する。完全復元のbusy拒否ではepoch、HERE、JOB検索結果の保持を確認する。

main.zigはhost_task_reap.bindを呼ばないため、実際のアプリでは未bindの終了フックは何もしない。本試験は明示bindしたフック関数の試験であり、mainのREPLにあるreportDiagnostic、pauseForReplの経路は通らない。アプリのREPL動作を検証したものとは扱わない。

指摘を誤りとして退けた箇所はない。Childを使用する方法のみ、同版に実在するAPIへ合わせた。

## 担当外の変更と理由

src/runtime_test.zigの登録は、実ホストWakeを使う試験をコア試験ルートへ混入させないためである。build.zigの変更は別プロセス検査をtestとruntime-testへ組み込むためである。本番の不具合は検出せず、本番修正は行っていない。

## 試験と実行結果

PowerShellでworktree内のZIG_GLOBAL_CACHE_DIRを使用する。Zig 0.17.1、Windowsで以下を確認した。

| 検証 | 結果 |
|---|---|
| zig build test | 成功。runtime 125 passed、5 skipped、子プロセスdriver成功 |
| zig build test -Ddebug=false | 成功。runtime 124 passed、6 skipped、子プロセスdriver成功 |
| zig build runtime-test | 成功。通常試験はキャッシュ再利用、子プロセスdriverは実行成功 |
| zig build -Dtarget=x86_64-linux | 成功 |
| zig build -Dtarget=aarch64-macos | 成功 |
| zig build runtime-check -Dtarget=x86_64-linux | 成功 |
| zig build runtime-check -Dtarget=aarch64-macos | 成功 |
| 変更Zigファイルのzig fmt --check | 成功 |
| git diff --check | 成功 |

親driver単体もx86_64-linux、aarch64-linux、aarch64-macosでzig build-exe -fno-emit-binによるコンパイル確認に成功した。クロス先での実行はしていない。変更Zigファイルのfmt対象はbuild.zig、src/tests/task_reap_child_driver.zig、src/tests/task_reap_reproduction_host_test.zig、src/runtime_test.zigである。

## 未確認事項と利用者の判断

Linux・macOS実機の実行、CIの各OSでの実行は未確認である。クロスビルド成功を実機での停止・join成立とは扱わない。Linux実行は別機械で行う予定である。

10ms／100ms、60Hz、管理1ms／巡、128MiBの実測・受入れ判定は行っていない。Forthの任意の途中命令で取消す試験ではない。Budgetの検査はホスト所有の入力Bufferが対象であり、アプリ全体の転送予算への統合完了を主張しない。

終了する子プロセスの保持資源はOSへ委ねる。abort後のjoin数やAllocator漏れは調べられないため、通常の遅延復帰試験で回収・join・解放を検査する。

今回の修正で新たに利用者の判断が必要な事項はない。方式の最終採用と利用条件の受入れは別判断である。コミット、ブランチ作成、タグ、プッシュ、tque変更、作業ツリー外の変更は行っていない。
