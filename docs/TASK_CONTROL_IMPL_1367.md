# タスク制御02-E：状態の再現試験（1367）

作成日：2026-11-24。作成者：ロク。基点：83987a2（専用detached worktree）。

## 変更ファイルと要点

- `src/tests/task_state_machine_test.zig`：台帳・キュー・結果・同期ジョブを接続する試験専用のHostと7個の再現試験を追加した。公開APIではない。
- `src/runtime_test.zig`：上記を登録した。実worker・ホストWake・監視スレッドを使うため、コア試験ルートには登録しない。
- `build.zig`：runtime試験にbuild_options、埋込み文書、float有効時の既存Core-Math設定を渡した。task_jobから実際のForth VMを使うために必要である。アプリ・通常コア試験の設定は変更していない。
- 本書：対応範囲、選択、検証結果と限界を記録した。

既存の`src/core/task_*.zig`、`forth.zig`を変更していない。通常実行経路の変更は0件であり、命令ごとの取消し確認を追加していない。公開Forth語・公開エラー値を導入していない。

## 設計上の選択と理由

本番のTaskManagerを先取りせず、試験専用Hostが既存モジュール間の所有権引渡しを接続する。台帳の更新と結果Budget操作はホストだけが行い、workerはtask_jobを呼び、独立した返却バイト列をキューのrelease/acquire公開で引き渡す。タスクごとにtask_jobが新規VMを作成する。

workerの取得直後（キュー用時計の読取り）、runner入口、試験専用VMのEMIT内、task_job帰還後かつ封印前、キュー封印公開後、ホスト終端受理後を同期境界とした。原子的なフラグをrelease/acquireで操作し、偶然のスケジューリングやsleepで順序を決めない。ホスト取り出し勝ちはworker開始前、または実行中の別タスクを入口で保留して作る。ワーカー勝ちは取得またはrunner入口の到達を確認して作る。

待ち期限は偽時計で直前と一致時刻を与える。独立した実Wakeの監視スレッドは30秒の絶対期限で試験プロセスをpanicさせる。監視はアサーション失敗時のworker解除・join・資源解放中も有効である。実時計はハング防止だけに使い、速度・停止時間・回収時間・性能の測定は行っていない。

通知は世代を常に0とする併合と、notifyがHostFailedを返す欠落を注入する。ホストは通知件数を終端の証拠にせずpollで回復する。実Wakeでの有限待ちからの回復は、既存`task_queue_test.zig`の試験も合わせて実行する。

## 状態機械仕様との対応

| 項目 | 今回の再現と証拠の範囲 |
|---|---|
| T01 | キュー4件満杯時の台帳予約・Snapshot参照ロールバック、旧版admit失敗、入力所有不変、createdの非公開、台帳16件満杯を確認する。全割当失敗位置の注入は既存task_job_testのcheckAllAllocationFailuresが補完する |
| T02 | queued、running、成功・失敗・取消し、終端照会の非消費を確認する |
| T03 | 取消し反復、ホスト取り出し、worker取得後かつ入口前の取消しを確認する。未接続のruntime_tokenによる独立性の確認は削除した |
| T04–T06 | T04・T06は2入口×5境界×CANCEL／RELEASEの20順序である。追加4順序は新規VMのrunAsWorkerで入口確認後のEMITを試験専用Writerで止め、要求印trueを確認してから解除する。成功／DivisionByZeroとcancel_requested=trueの併存を確認する。EMITはtask_jobの許可集合外のため、この4順序だけ試験専用runVmを使う。T05の後片付け失敗の発生・検出は未対応である。診断の直接注入を削除し、secondary=nullを確認する |
| T07–T08 | CANCEL→RELEASE、RELEASE→CANCEL、再RELEASE、ホスト取り出し勝ち、worker受取り勝ち、受取り後の入口前確認を再現する。Snapshot参照の減少とcleanup1回、後続runner未到達を確認する |
| T09–T10 | 台帳の参照の契約だけ。WAITは対象外（1369・1372で扱う）。Waiterのbool引数は模型であり、時計・Wakeに基づく期限・中断の試験ではない。期限の算術だけの確認は削除した |
| T11 | 容量不足の必要量5と宛先不変、反復取得、失敗・取消しの結果なし、コピー開始参照→RELEASE→新規query拒否→既存コピー完了→参照解放を確認する |
| T12 | queued／running／終端／RELEASE済み内部記録を含む所有者終了と完了受理、回収を確認する。所有者終了後の新規受理停止は呼出し側の責任であり、この試験Hostは本番受付管理を実装しない |
| T13–T14 | 実行参照・コピー参照を個別に残してcollect拒否を確認する。復帰可能なrunner保留で停止未確認診断、実行枠保持、未終端保持、join未成立、deinit拒否を確認し、保留解除後にjoin・回収する。VM内部資源を直接観測する試験ではない |
| T15–T16 | epoch違い、serial=0、ロールバック済み、削除済み、RELEASE済み、別種、別所有者の拒否と対象不変、同スロット再利用、最大serial発行後の枯渇を確認する。検査優先順の詳細は既存task_ledger_testも補完する |
| T17 | 同一Snapshotの複数参照、一方の解放で版を失わないこと、FORGET後の新規admit拒否と投入済み旧版の正常実行を確認する |
| T18 | 通知失敗後のpoll回復、同一終端の重複受理false、矛盾終端ConflictingTerminal、結果不変と回収を確認する |
| T19 | 実行結果上限0でResultTooLarge→failed、RESULT宛先不足で終端を変えないことを区別する |
| T20 | 20順序で成功・失敗・取消しを作成・回収する。各回で新規VM、workerのjoin、台帳0件、Snapshot参照1を確認する。Completion破棄後のtransfer.used=0も確認する。std.testing.allocatorでリークも検出する |

## 担当外の変更

`build.zig`のruntime_module設定4行と`src/runtime_test.zig`の登録・説明のみである。実Forth VMと実ホストWakeを同じ試験に組み込むための変更であり、Linuxのコア試験へホスト専用依存を混入させないためである。本番モジュールの不具合修正は0件である。

## 試験と実行結果

Zig 0.17.1、Windows PowerShellを使用した。Zigの既定キャッシュ作成がAccessDeniedとなったため、ZIG_GLOBAL_CACHE_DIRとZIG_LOCAL_CACHE_DIRをworktree内に指定して実行した。検証後のキャッシュは無視対象の`.work/`配下へ移動した。既存ホスト試験が固定で使用する`.zig-cache`ディレクトリも作成した。

初回実行では、追加試験のenum型指定と、WAIT参照を残したまま参照数0の記録と比較した試験側の誤りを修正した。固定パスの`.zig-cache`が未作成の実行では既存ファイル試験15件が失敗し、作成後の再実行で通過した。

追加試験7件を含む最終ソースで、次の結果を得た。

| コマンド | 結果 |
|---|---|
| `zig build test -j2` | 成功 |
| `zig build test -Ddebug=false -j2` | 成功 |
| `zig build runtime-test -j2` | 成功 |
| `zig build -Dtarget=x86_64-linux -j2` | 成功 |
| `zig build -Dtarget=aarch64-macos -j2` | 成功 |
| `zig build runtime-check -Dtarget=x86_64-linux -j2` | 成功 |
| `zig build runtime-check -Dtarget=aarch64-macos -j2` | 成功 |
| `zig fmt --check build.zig src/runtime_test.zig src/tests/task_state_machine_test.zig` | 成功 |

## 未確認事項と利用者判断

Linux・macOSでの実行は未確認である。クロスビルド成功は実行成功を意味しない。Linux実行は別機械で行う引継ぎである。

本番WAIT登録、公開API、TaskManagerの受付停止、実際のUI・入力・I/Oとの複合待機、本番取消し・終了回収との接続は後続範囲である。Waiterは台帳参照の試験用モデルである。Host.acceptも試験専用の完了受入れ処理であり、本番の受入れ処理を実装した際にはその処理に対する別の試験が必要である。T05の後片付け失敗は未対応である。128MiB全体予算、64KiB/native、10ms停止・100ms回収、60Hz・管理1ms/巡の達成は測定していない。

今回の差分に新たな仕様判断を要する事項はない。方式の確定・公開・性能受入れは既存決定どおり別判断である。コミット・ブランチ・タグ・push・tque変更を行っていない。



## レビュー指摘への対応（2026-11-24）

6点ともソースで確認し、妥当と判断した。上記に加え、ホストで全仕事を除去してからworkerを開始する試験では、stop・join後にも全仕事のentered=falseを確認した。本修正で変更したのは試験ファイルと本書だけである。本番モジュールの不具合は確認されていない。通常経路の変更は0件である。

以下は今回の再検証結果である。前節の結果は修正前の記録である。

| コマンド | 今回の再検証結果 |
|---|---|
| `zig build test -j2` | 成功（23/23 steps） |
| `zig build test -Ddebug=false -j2` | 成功（23/23 steps） |
| `zig build runtime-test -j2` | 成功 |
| `zig build -Dtarget=x86_64-linux -j2` | 成功 |
| `zig build -Dtarget=aarch64-macos -j2` | 成功 |
| `zig build runtime-check -Dtarget=x86_64-linux -j2` | 成功 |
| `zig build runtime-check -Dtarget=aarch64-macos -j2` | 成功 |
| `zig fmt --check build.zig src/runtime_test.zig src/tests/task_state_machine_test.zig` | 成功 |

今回もキャッシュはworktree内の`.work/`配下に置いた。速度・時間の測定は行っていない。

## 4タスク取り込み後のハング修正（2026-11-24）

対象はメイン作業ツリーへの1367・1369・1373・1387取り込み後である。上記の専用作業ツリーでの結果とは区別する。

### 原因と確認方法

1367の試験専用VMは`runAsWorker`から`HELD-ECHO`／`HELD-FAIL`の`EMIT`へ到達する前提だった。1373は`task_policy.checkBuiltin`を`task_permissions.policy`の許可リストへ接続し、`EMIT`を`InvalidExecutionToken`で拒否する。試験専用例外は`builtin.is_test`かつ`test_host_probes=true`の場合の`.`／`KEY-IOR`だけである。従来の試験はその例外を使っていなかった。

一時ログを追加した実行で、`ECHO point=4 release=false`の`HELD-ECHO`が`failure=error.InvalidExecutionToken vm_entered=false`で帰還し、その後watchdogが発火することを確認した。point=0～3は進行していた。ログ追加コードは除去済みである。

1367の試験ファイルが元の専用作業ツリーと同一であること、1373のキュー・1387のcontext／台帳との差分も確認した。sealed後の取消し要求、phaseOf、observeStart、Binding.pollは、VMの出力callbackへ到達する前の拒否を発生させる経路ではない。1387のsubmitReplacingはこの試験ではold=nullであり、停止不能中の受付・task_schedule_hostも当該境界では使っていない。WorkerScopeはホスト投入判定用で、上記callbackの許可を与えない。Job.acquiredのatomic統合と1369のWake接続は維持した。

### 修正

本番コードは変更していない。`src/tests/task_state_machine_test.zig`だけで同期用の`65 EMIT`を`65 .`へ替え、その試験専用VMに既存の`test_host_probes=true`を明示した。成功／DivisionByZero、CANCEL／RELEASE、VM入口確認後の保留という20順序の検査内容は保つ。task_job本番入口の許可集合は広げていない。

さらに`awaitVm`でcallback到達前のrunner帰還を検出し、公開済みの実際のエラーを返すようにした。到達不能な同期点を待ち続けず、既存のdeferによるゲート解除・join・資源解放へ進む。偽時計と取得直後のゲートは変更していない。1364の投入受付方針、1373の取消し規則、利用者の設計判断も変更していない。

### 検証

PowerShell、Zig 0.17.1で実行した。全コマンドに`-j2 --summary all`を指定した。グローバルキャッシュはメイン作業ツリー内の`.work/zig-global-cache`を使った。成功済みのrunステップがcachedとなった回は反復回数に数えず、必要な回は`--cache-dir .work/hang-…`で個別のローカルキャッシュを指定し、実際の実行件数を確認した。

| コマンド | 取り込み後の最終結果 |
|---|---|
| `zig build test` | 全試験を実行した3回とも終了コード0、23/23 steps、1575成功・31 skip（1606件） |
| `zig build test -Ddebug=false` | 3回とも終了コード0、23/23 steps、1500成功・106 skip（1606件） |
| `zig build runtime-test` | 実行省略のない3回とも終了コード0、6/6 steps、104成功・5 skip（109件） |
| `zig build -Dtarget=x86_64-linux` | 終了コード0、13/13 steps |
| `zig build -Dtarget=aarch64-macos` | 終了コード0、11/11 steps |
| `zig build runtime-check -Dtarget=x86_64-linux` | 変更した試験を含めクロスコンパイル成功、6/6 steps |
| `zig build runtime-check -Dtarget=aarch64-macos` | 変更した試験を含めクロスコンパイル成功、6/6 steps |
| `zig fmt --check src/tests/task_state_machine_test.zig` | 終了コード0 |
| `git diff --check` | 終了コード0 |

実行ログは`.work/runtime-hang-test-fresh-1.log`、`runtime-hang-test-{2,3}.log`、`runtime-hang-test-nodebug-{1,2,3}.log`、`runtime-hang-runtime-1.log`、`runtime-hang-runtime-actual-{2,3}.log`に保存した（いずれも`.work/`配下）。再現時のログは`.work/runtime-hang-diagnostic.log`、クロスビルドのログも同じディレクトリの`runtime-hang-*.log`である。

Linux・macOSでの実行は行っていない。性能・停止時間・回収時間の測定、tqueの変更・測定、Gitのadd・commit・stash・reset・checkout・tag・pushは行っていない。各専用作業ツリーは読取りだけである。今回の追記と試験修正は未ステージのまま残した。
