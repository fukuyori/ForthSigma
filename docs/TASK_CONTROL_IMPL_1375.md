# タスク1375：停止不能時の扱いと1374の統合

更新日：2026-11-24。担当：ロク。基点：ab21c51。1374の差分を適用済みの専用worktreeで統合した記録である。

## 変更ファイルと要点

| ファイル | 統合後の役割・修正 |
|---|---|
| src/core/task_schedule_host.zig | 2か所の衝突を解消した。1374の受付停止・所有者終了と1375の期限・診断を統合した。内部検索とlatchCancellationによる取消し、Host経由の回収に集約した。 |
| src/core/task_reap.zig | beginはHost.beginShutdown/endOwner、pollはHost.poll/shutdownStatus/collectを使う。不応答設定と台帳collectをHostへ集約した。追加修正では所有者終了用の100ms期限をReaperに持たせた。 |
| src/core/task_queue.zig | markUnresponsiveForを非optionalのJobポインタとした。既存markUnresponsiveは活動中のJobにだけ委譲し、待機中は印を付けない。 |
| src/host_task_reap.zig | REPLエラー・ABORT・QUITは呼出し元へ返す。BYEだけ終了フックを呼ぶ。完全復元はbusy検査後に復元し、受付停止を行わない。 |
| src/host_task_stop.zig | 1375の独立資源cleanup、診断出力、C exit(1)の共通経路を使用する。本統合でソース変更はない。 |
| src/main.zig | 最終回収失敗時にflushOutput、utf8_console.finish、resize_scope.endを実行してからhost_task_stop.abortへ進む。 |
| src/tests/task_schedule_host_test.zig | 古い取消し期限、RELEASE後の終了、手渡しと不応答指定の順序を試験した。ホスト側の待機ループと後始末に反復上限を設けた。 |
| src/tests/task_reap_test.zig | 所有者別・全体回収、復元、未結合フック、打ち間違い、ABORT/QUIT/BYE、実Wakeのfinishを試験した。ホスト側の待機ループと後始末に反復上限を設けた。 |
| src/runtime_test.zig | 1374の回収試験登録を維持し、zig fmtを適用した。host専用試験はruntimeルートに限定した。 |
| docs/TASK_CONTROL_IMPL_1374.md、本書 | 統合後の契約、検証、未確認事項に更新した。 |

## 設計上の選択と理由

### 取消し・期限・診断

requestCancelはfindInternalとledger.inspectで内部エントリーを取得し、ledger.latchCancellationとqueue.cancelへ進む。外部IDの有効性を要求しないため、RELEASE済み・所有者終了済み・世代差替えの内部記録でも同じ経路を使用できる。最初のStopDiagnosticとrequested_at、10ms停止期限、100ms回収診断は維持する。反復要求で診断を消さない。

Host.beginShutdownは受付を閉じ、待ち仕事を先に取り除き、保持中の全エントリーにrequestCancelとendOwnerを適用してキューを停止する。RELEASE済み・終了所有者の記録も診断対象である。endOwnerは外部IDを無効化し、待ち仕事の除去後に各エントリーへ取消しを要求する。終了所有者の再投入を拒否する1374の固定長記録は維持した。

終了専用のshutdown_deadlineをHostに1つ持つ。最初のbeginShutdownから100msであり、個別取消しのcollection_exceededとは独立している。shutdownStatusはjoin成功時に再度pollする。joinできず、終了専用期限を過ぎ、実行参照が残るか未終端である記録があるときだけresources_activeを返す。停止済み・未回収だけの記録は数えない。古い取消し期限の超過だけで終了直後に致命判定する問題を防ぐ。

不応答の台帳印を付ける場所はHost.checkStopDeadlinesだけである。Host.markUnresponsiveは除去した。活動中の記録を台帳へ反映できない場合もpollを早期returnせず、停止期限検査へ進む。

### 回収と復元

Reaperは所有者終了用の期限を持ち、不応答設定はHostに委ねる。Hostの診断・終了判定を参照し、物理帰還・終端・参照消尽を確認してHost.collectを呼び、コピーしたエントリー情報をDisposal.destroyへ渡す。VM・Job・結果・Snapshot等の参照グラフは回収まで保持する。Disposal.retireはWAIT/結果コピー利用者の退役の接続点であり、その利用停止前に参照を落としてはならない。

ホスト全体の停止済み記録に内部参照だけが残る場合、shutdownStatusはresources_activeにしない。Reaperは終了専用期限を過ぎても内部参照が残ればstop_unconfirmedを返す。これはワーカー停止未確認とは別の回収失敗であり、診断文は両方を含む。所有者別回収は共有workerを停止せず、Reaper.beginで所有者を終了するときから100msの期限に従う。古いcollection_exceededによる即時失敗は行わない。

終了理由はowner_exit・bye・restoreに整理した。restoreは終了ではなく静止検査である。活動中、実行参照または内部参照があればBusyで拒否し、取消し・ID無効化・受付停止を行わない。別理由でbegin済みでもbusy検査を省略しない。静止した完了記録は保持したまま完全復元を許可し、後の明示的終了で通常回収できる。復元後もHostの受付と共有workerは開いたままである。

REPLのinterpretLineエラー、ABORT、QUITではタスクを終了しない。include/runEntryも同じ契約である。BYEと明示的な所有者終了だけで終了処理へ進む。

### 不応答印と物理帰還

Queueのunresponsiveは毎回のrunner・cleanupの物理帰還時に解除される。単一workerでは活動中に新しい仕事を取得しないため、この印だけで追加の停止状態を作るものではない。台帳のexecution_refとstop_unconfirmed、およびJobの物理所有権を併せて扱う必要がある。

markUnresponsiveForはロック内で対象Jobとactiveを照合する。古いJobの帰還後に別Jobを取得していれば印も取消しも付けない。偽runnerのatomicゲートで、旧Jobの帰還前に指定する順序と、帰還して次Jobを取得した後に指定・回収する順序を固定し、両方を検査した。nullで待機中に誰も解除しない印を立てる形は除去した。

### 致命的終了

mainの最終回収deferは、runtime.beginShutdown、端末のrecover/finishPresentation/leave、音の停止、gamepadとwindowの終了のdeferより先に登録する。逆順実行により、これらの独立した後始末を済ませてから回収失敗を判定し、出力・UTF-8コンソール・resizeの後始末を経てhost_task_stop.abortへ進む。音の停止が失敗した場合はabortIncompleteも呼ぶ。診断は同モジュールの「error: runtime resources remain active: task worker stop unconfirmed or collection limit exceeded」、終了コードは1に統一した。既存のruntime資源残存の致命経路と同じ後始末・終了コードの方針である。

abortはCのexitを使い、ZigのVM・Storage・Queueのdeferを進めない。ただしPOSIXを含め、C exitはatexitハンドラーとstdioのflushを実行する。ワーカーが動作中の可能性があるため、それらが保持中のタスク資源へアクセスして安全であることは本実装では保証しない。今回の選択はこの制約の文書化であり、_exitへの切替えやプロセス終了の実行試験は行っていない。

## 担当外変更と通常経路への影響

task_schedule_hostは1387の結合、task_queueは1366の所有権管理であり、終了処理との整合に必要な変更である。task_reap・host_task_reap・mainは1374との統合対象であり、runtime_testと両試験ファイルはその検証・登録のためである。他のコアモジュールは変更していない。

通常経路の変化は、1374で追加されたmainの実行単位ごとのinterpret/include/runEntryフック、組込みイメージ復元前のフック、終了時deferである。本統合ではその終了条件と致命時処理を修正した。通常VMの命令実行、State配置、comptime workerの選択、取消し確認点、worker許可集合は変更していない。命令ごとの定期取消し確認は追加していない。

製品起動時にはReaperをbindしない。タスク未利用者向けには未結合フックのままである。公開語を実装する1379が、固定位置のHost/Queue/Reaper、DisposalとWAIT参照の退役、bind/unbindの寿命を結び付ける担当である。公開Forth語・公開エラー値は追加していない。

## 試験と実行結果

PowerShell、Zig 0.17.1を使用した。ZIG_GLOBAL_CACHE_DIRは既存.gitignore対象の作業ツリー内.zig-global-cacheとした。既定キャッシュの最初の試行はmanifest_create AccessDeniedで失敗した。途中のruntime試験では、回収参照保持の期限判定と、取消し診断用に時計を進めた試験の待ち期限基準の不一致を検出した。判定を終了専用期限へ統合し、待ち期限の試験を投入時刻からの相対値へ修正して再検証した。

| コマンド | 最終結果 |
|---|---|
| zig build test | 成功、終了コード0 |
| zig build test -Ddebug=false | 成功、終了コード0 |
| zig build runtime-test | 成功、終了コード0 |
| zig build -Dtarget=x86_64-linux | 成功、終了コード0（クロスビルド） |
| zig build -Dtarget=aarch64-macos | 成功、終了コード0（クロスビルド） |
| zig fmt --check（差分に含まれるZig 9ファイル） | 成功、終了コード0 |
| git diff --check | 成功、終了コード0 |

追加修正前のruntime試験は122件中117件成功・5件スキップであった。今回の追加修正後の結果は末尾に記す。

ホスト側の待機試験は10,000,000回の反復上限とerror.Timeoutを持つ。deferのworker回収は同じ上限で明示的にpanicする。偽runnerの停止ゲートはdeferで解放する。反復数は実時間の保証・測定ではない。

## 未確認事項

- Linux/macOSの実機実行は未実施である。Linux実行は別機械のClaudeが担当する。
- 停止10ms・回収100ms、60Hz・管理1ms/巡などの実時間達成は未確認である。速度・時間の測定は行っていない。
- 実際の停止不能VM、致命的exit(1)、atexitとワーカーの並行動作は実行試験していない。
- 製品での公開語・Reaper結合・実際のWAIT/コピー利用者との寿命統合は1379以降の範囲である。

## 利用者の判断が必要な事項

今回の修正について追加判断事項はない。REPLエラー・ABORT・QUITは継続、BYEと明示的所有者終了だけ回収、活動中の完全復元はBusyという決定を反映した。

Gitの書込み、commit・branch・tag・push・tque変更は行っていない。

## 統合後レビューの追加修正（2026-11-24）

指摘1〜4はいずれもソース上で確認でき、修正した。指摘5は既存契約として確認した。

- src/main.zig：終了deferの登録位置を変更した。ワーカーが参照し得るVM・Storage・イメージ・ファイル・runtime本体の解放より前に回収失敗で終了する。通常成功時の独立資源の後始末順は維持する。reportDiagnosticは終了フックが失敗したHostFailedの表示を抑え、最終終了診断へ集約する。
- src/host_task_reap.zig：終了失敗の内部ラッチと参照関数endFailedを追加した。bindで初期化する。公開Forth語・公開エラー値の追加はない。
- src/core/task_reap.zig：所有者終了用の100ms期限を初回beginに設定する。繰り返しbeginで延長しない。未終端・実行参照・内部参照のいずれかが残れば、この期限の後にstop_unconfirmedとする。全体終了では従来どおりHost.shutdown_deadlineを使用する。
- src/tests/task_schedule_host_test.zig：awaitResultの反復上限でerror.Timeoutを返す。
- src/tests/task_reap_test.zig：未結合interpret・restoreの実行と復元後の語の結果、所有者終了前の古い取消し期限と新期限の直前・一致時、内部参照保持、遅い参照解放後の回収、BYE失敗ラッチを検査する。時計は注入値を用い、時間測定は行わない。

STATE_MACHINEの5.1〜5.3は、結果コピー・待機等の内部参照消尽を回収条件とし、終端報告後の回収停止も別途診断する。したがって、終端・join済みでもDisposal.retireがnull、または参照を落とさずinternal_refsが残る場合は「資源が残っている」と数える。停止未確認そのものとは区別されるが、Progress.stop_unconfirmedは回収失敗も含む既存内部値として維持した。参照を強制的に落とさず、期限後も保持し、参照解放後には回収できる。

Host.collectは終端確認後、external_validならledger.releaseを行ってからledger.collectする。そのため内部参照が残ってReferencesRemainとなった場合でも、外部IDは無効になっている。未終端の場合はreleaseの前でReferencesRemainとなる。本修正ではこの既存契約を変更していない。

担当外変更はmainの終了順・診断とhost_task_reapの診断連携、および指定された試験のみであり、いずれも今回の指摘修正に必要である。通常経路の追加変更はエラー表示時のHostFailed比較と内部ラッチ参照のみである。通常VMの命令実行、comptime worker経路、取消し確認点、許可集合は変更していない。追加判断事項はない。実際の致命的終了と端末復元の実機試験、Linux/macOSでの実行、実時間条件の達成は未確認である。

### 追加修正後の検証結果

PowerShellで実行し、キャッシュは作業ツリー内.zig-global-cacheを使用した。以下はすべて終了コード0である。

| コマンド | 結果 |
|---|---|
| zig build test | 成功 |
| zig build test -Ddebug=false | 成功 |
| zig build runtime-test | 成功（最終main修正後にも再実行） |
| zig build -Dtarget=x86_64-linux | 成功、実行は未実施 |
| zig build -Dtarget=aarch64-macos | 成功、実行は未実施 |
| zig fmt --check src/main.zig src/host_task_reap.zig src/core/task_reap.zig src/tests/task_schedule_host_test.zig src/tests/task_reap_test.zig | 成功 |
| git diff --check | 成功（改行変換の警告あり） |

最終git status --shortは次のとおりである。Gitの登録状態は変更していない。今回編集したのは、本書と上記fmt対象の5ファイルだけである。

```text
AM docs/TASK_CONTROL_IMPL_1374.md
AM docs/TASK_CONTROL_IMPL_1375.md
MM src/core/task_queue.zig
AM src/core/task_reap.zig
UU src/core/task_schedule_host.zig
AM src/host_task_reap.zig
A  src/host_task_stop.zig
MM src/main.zig
MM src/runtime_test.zig
AM src/tests/task_reap_test.zig
MM src/tests/task_schedule_host_test.zig
```
