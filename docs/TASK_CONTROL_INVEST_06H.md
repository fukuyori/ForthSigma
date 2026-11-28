# 06-H タスク取消し・停止観測の調査

## 対象と作業範囲

対象は `33f37f7075c5d9272f8eb0b1baa67610e198718d` の専用worktreeである。
Zig 0.17.1のソースを追い、既定で無効の診断を追加した。Linuxでの実行・測定は行っていない。
Windowsでは診断の動作と指定の試験を確認する。時刻値の評価はしない。
コミット・ブランチ・タグ・push・tqueの変更は行わない。

`TASK_CONTROL_IMPL_1380.md` のLinux追記は停止未確認の履歴と待ち期限切れを示すが、遅れた段階の実測は含まない。
`TASK_CONTROL_USAGE_CONDITIONS.md` 5節および10節のD07は要求→停止10 ms以内という採用条件であり、OSを含む時間保証ではない。
以下ではソースから分かる事実と、Linuxで確認すべき仮説を分ける。

## 取消しから停止までの経路

1. `src/core/task_schedule_host.zig` の `Host.submit` は入口でqueueの時計を読み、同一streamの世代差替えで旧entryへ `requestCancel` を呼ぶ。投入の許可判定・台帳登録・queue投入が先行するため、この入口時刻から実際の取消しまでにも処理がある。`requestCancel` は最初の要求時刻から10 ms/100 msの期限を保持し、`ledger.latchCancellation`、`queue.cancel` の順に呼ぶ。繰り返し要求で期限を延長しない。`latchCancellation` はホストの台帳フラグであり、ワーカーを停止させるトークンではない。
2. `src/core/task_queue.zig` の `cancel` はgateを取得し、`Job.cancellation.request()` のrelease storeでトークンを設定する。待ち中ならqueueから除去し、cleanupとsealをホストで行う。実行中ならgateを解放してprivate Wakeをkickする。gateはspin lockであり、取得時間の上限は設定されていない。
3. ワーカーは物理取得後、期限とトークンを確認する。`task_job_queue.Execution.run` → `task_job.runWithOptions` へ進む。ここで最初の確認、`FreshVm.create`、復元後の確認、fresh検査・名前解決・メモリgrant構築・許可語検査・入力コピー、`runAsWorkerWithMemory` の順になる。生成・復元の内部や、復元後の確認から実行入口までの各処理には、このトークンの確認はない。
4. `src/forth.zig` の `runAsWorkerWithMemory` はthread-local Contextにトークンを設置し、入口で確認する。worker専用の `runOperationsLoop` は最初と1024 Opごとにacquire loadする。1024は時間ではなく命令数である。`task_memory.before/after` はメモリ系builtinおよびROLL/PICK/N>R/NR>で前後を確認し、literalにも確認がある。primitiveの直接dispatchにもbefore/afterがある。全てのbuiltinの前後で無条件に確認する実装ではない。
5. 許可されたbuiltinのZig実装は同期実行であり、メモリ操作は既定64 KiBの仕事量制限を受ける。SEARCHは入力量だけでなく積による仕事量も検査する。64 KiBは時間の上限ではない。任意の外部nativeコールバックを無条件に許可しているわけではなく、`task_permissions` と `task_policy` が実行語・Opを制限する。
6. 検出すると `TaskCancelled` で戻る。`runOperations` のエラー処理はこれを通常のForth CATCHで握りつぶさず返す。Context解除、grant解放、VM解放、Snapshot実行参照の解放等のdeferが走る。`Execution.run` はこれをcancelled結果へ変換する。成功帰還後の遅い取消しで成功を取り消す検査は行わない（D04）。結果コピーや解放はForthの確認間隔とは別の区間である。
7. queueの `work` はrunnerから戻った後、`Job.seal` でcleanupを行い結果を格納する。gateを取り直してsealed化し、readyをrelease storeし、activeをnullへ戻す。これがcleanupを含む物理的な返却である。その後common Wakeへnotifyする。待ち中取消しでは次のhost pollがready公開と通知を担う。
8. `Host.poll` はqueueのreadyをacquire loadして終端を取り込み、既存のexecution_refを先に解消し、未観測の取得済み完了も処理する。`finishAcquired` は `ledger.finish` と `executionStopped` を呼ぶ。最後にもう一度clockを読み `checkStopDeadlines` を呼ぶ。`terminal && !execution_ref` を停止済みとし、未停止かつ `now > deadline` ならstop_exceededを保持する。execution_refがあり、`markUnresponsiveFor` が同じactive jobを確認した場合だけ停止未確認を台帳へ記録する。期限が過ぎたことを停止完了とは扱わない。

`release` は外部IDを無効にしてqueue.cancelを呼ぶが、単独では `requestCancel` のStopDiagnosticを作らない。差替えではそれに先立って旧entryのrequestCancelが呼ばれる。queue内部の差替え取消しが先に起きた場合、token設定がrequestCancelより早いこともある。

## 候補と根拠

| 候補 | ソース上の根拠と限界 | 切り分け |
|---|---|---|
| 初期化・復元・実行前検査 | `task_job.runWithOptions`、`FreshVm.create`、`task_permissions.inspect`、`Grants.init`には確認間隔の保証がない。VMの割当・初期化・復元は64 KiB native制限の対象ではない | ※推測です：要求時にこの区間へ入っていた場合に検出が遅れる。vm_start/restored/preparedとdetectedを比較し、Linuxのスタックも取得する |
| Forth探索の大きいループ | `tests/task/task-path-worker.fs` の親配列初期化、BFS、経路構築はBEGIN/WHILE/REPEATによるForth処理である。例は64×64、親配列等の確保容量は65536要素である。ループ中の@/!/C@/C!等にも確認があり、ループ全体が確認点なしではない | ※推測です：1024 Opの途中の失速や単一builtinで遅れる可能性はあるが、確認点のないBFS全体を原因とする根拠はない |
| 64 KiBまでのnative処理 | `task_memory` は仕事量を制限し前後で確認するが、処理途中のOS割込みやページフォルトまで時間制限しない。この経路探索は主にセル・バイト単位のアクセスであり、大きなFILL/MOVEをworkerの探索ループ内で呼んではいない | ※推測です：一般の許可nativeでは候補である。今回の主因かは未確定であり、Linuxで停止区間のスタックを確認する |
| ワーカースレッドの実行待ち | queueは通常の `std.Thread.spawn` で起動し、CPU割当や優先度・実行までの上限を指定しない。トークン設定やWakeは実行権の即時取得を保証しない | ※推測です：Linuxの競合負荷、プリエンプト、ページフォルト等が検出または解放を遅らせる。時刻ログだけではCPU上の処理時間と実行待ちを区別できない |
| 帰還後の解放・cleanup | `TaskCancelled` 検出後も `task_job` のdeferとqueue sealのcleanupが残る。queue返却はそれらの後である | ※推測です：VMの解放・allocator処理やSnapshot参照の最終解放が遅れる。detected→forth_return→runner_return→sealedで区分する |
| gate競合 | cancel、物理取得、公開、poll、view等が同じspin gateを使う | ※推測です：gate所有スレッドが停止・実行待ちになると他方も進めない。request→token_before、sealed→publishedが候補だが、これだけではgate待ちとOS実行待ちを断定できない |
| ホストの観測 | `task-path.fs` は各巡回でTC-POLL後に描画・TC-DRAW・10 MSを実行する。`Host.poll` の期限判定は停止時刻を保存して比較せず、そのpoll末尾の現在時刻と台帳を使う | ※推測です：公開をpollが取り逃した直後の競合やホスト巡回遅れで、観測と物理返却に差が出る。ただし既に終端を取り込んだpollでは、時刻が遅いだけでstop_exceededにはならない |
| Wake通知・観測 | 実行中の取消しkickはワーカーの計算を割り込ませない。ready公開後のcommon通知と、ワーカー用private通知は別である。`host_wake` は世代とevent/pipeを併用し、通知の合流を許す。workerのidle待機とqueueの再確認期限は10 msである | ※推測です：未取得ジョブの起床、host waitからの帰還には遅れがあり得る。ただし実行中のチェックはWakeを待たない。published→observedだけからWakeを原因と断定できない |
| 差替え入口からトークン設定まで | 期限起点はHost.submit入口のclockであり、requestCancel入口やtoken storeの時刻ではない | ※推測です：差替え準備やgate待ちが10 ms予算を消費する。api_entry→request→token_before/afterで確認する |

pollは各jobの終端取得を先に行うため、「10 MSのsleepがあるので必ず誤判定する」という結論にはならない。
一方、ready取得後の時刻と実停止時刻の比較ではないので、過去の10 ms達成を証明する機構でもない。
stop_exceededと台帳のstop_unconfirmedは同一ではない。走査中にactiveがnullになれば前者だけ残る場合がある。
公開診断の-314も履歴であり、ログ取得時にまだ走っているという意味ではない。

## 診断の実装

`zig build -Dtask-trace=true` でのみ有効になる。既定はfalseであり、無効時のStorageとtoken側の診断フィールドは空で、時計取得・診断用atomic・出力はコンパイル時に除去される。freestandingでも無効である。
queueが所有する固定長Storageをtokenに関連づけ、最初の各段階だけをatomicで保存する。tokenをconst参照するworkerは、別の可変Storageを更新する。ホストによるisRequestedは検出時刻として記録しない。診断のために確認点を追加してはいない。
ワーカーではI/Oも追加割当も行わない。公開後はworkerがJob/tokenを再参照しない。ホストがreadyを観測した際、取得済み結果を台帳へ反映した際、初回期限超過の際にstderrへ出力する。

形式は1行の `TASKTRACE token=<16進ポインタ> event=<observed|reconciled|deadline> <段階>=<整数ns> ...` である。
同じtokenの複数行は同じタスクの段階を補足する。アドレスは回収後に再利用され得るので別run間でIDとして使用しない。
LinuxはCLOCK_MONOTONIC、WindowsはQueryPerformanceCounterを既存 `host_clock` でnsへ換算する。api_entryだけは既存queue時計の保存値であり、実ホストの同一時計を前提とする。偽時計を使う試験の時刻差は解釈しない。
0は未通過・未記録・時計失敗またはi64範囲外を表す。待ち中取消しではdetectedやrunner_return等が0でも正常である。成功も出力するため、取消し要求のない行ではapi_entryが0になる。

| 段階 | 記録場所 |
|---|---|
| api_entry | requestCancelへ渡された最初の要求起点。差替えではHost.submit入口 |
| request | requestCancelでentryを取得した直後 |
| token_before / token_after | release storeの直前 / 直後。検出がtoken_afterより早くても競合として正常 |
| acquired | queueの物理取得、acquired storeの直前 |
| vm_start / restored / prepared | task_job開始 / FreshVm.create成功後 / runAsWorkerWithMemory呼出し直前 |
| detected | 既存のworker確認点で初めてtrueを読んだ直後 |
| forth_return | runAsWorkerWithMemory成功またはエラーの帰還後、task_jobのdefer前。実行前取消しでは0 |
| runner_return | queueへ同期runnerが帰還した直後。実行前にqueueが取り消した場合も結果選択後を記録 |
| sealed | Job.seal内のcleanupとresult格納が済んだ直後。phase更新より前 |
| published | ready release storeの直前。store後の厳密な時刻ではない |
| observed | hostが初めてready=trueを確認した直後 |
| host_stopped | 取得済みjobのexecutionStoppedが済んだ直後 |
| deadline_check | 初回期限超過の判定で比較に使ったpoll末尾のnow。診断出力前の値である |
| deadline | checkStopDeadlinesが初めて未停止かつ期限超過と判定した位置 |

各項目は単一atomicであり、行全体は原子的スナップショットではない。とくにdeadline行の後にもworkerが進み得る。
診断の時計取得、atomic、gate内の追加処理、ホスト出力は順序と実行時間に影響する。診断ビルドを性能保証の判定に使わない。
通知そのものの前後は記録しない。公開後にworkerがtokenへ触るとhost回収との競合を作るためである。Wakeの通知遅延とホストの巡回・実行待ちを分離するには、次項のOS側情報が必要である。

## Linuxでの採取手順（未実行）

利用者の確認後、ClaudeがLinux x86_64・Zig 0.17.1で実施する手順である。
リポジトリのルートをcwdとする。まず既存の再現と同じビルド設定を用い、task-traceのみ追加する。下記は既定debug設定である。

```sh
export ZIG_GLOBAL_CACHE_DIR="$PWD/.work/zig-global-cache"
zig build -Dtask-trace=true
python3 tests/scripts/trace-task-path.py --sigma zig-out/bin/sigma --log .work/06h/linux-trace.log
python3 tests/scripts/trace-task-path.py --analyze .work/06h/linux-trace.log
```

ドライバーは既存の診断Forthを起動し、G1バナー後にnnnを送り、generation=4の結果を待ってdqで終了する。固定の速度閾値で成功・失敗を決めず、既存Sessionのtimeoutはハング検知だけに用いる。既定では生ログの保存と形式確認だけを行い、時刻の差分を表示しない。`--analyze` は既存ログを読むだけで実行体を起動しない。
最新結果に到達できなければtimeoutとなり、それまでの出力を同じlogへ保存する。稀な再現を1回の成功で解消と判定しない。

手動の再現、旧ID保持、要求の間隔を変える場合は次を使う。

```sh
zig-out/bin/sigma tests/scripts/diagnose-task-path.fs 2>.work/06h/manual-trace.log
python3 tests/scripts/diagnose-task-path.py --sigma zig-out/bin/sigma --keep-old
# 既存ドライバーの生ログは .work/1380/diagnose-task-path-retained.log
```

手動ではnで差替え、dで公開診断、qで終了する。`.work/06h` は先に作る。
原例の描画による差も確認する場合は `tests/task/task-path.fs` を同じ診断ビルドで起動する。
ビルド種別、OS/kernel、CPU、負荷、要求の送り方、公開診断と生ログを一緒に残す。最適化設定を変えるときは別のログ名にする。

解釈は次の順に行う。

- api_entry→request→token_before/afterに大きな区間があれば、要求準備またはトークン設定側を調べる。
- token設定とvm_start/restored/preparedの位置関係から、要求時に生成・復元・許可検査・Forth実行のどこにいたかを絞る。detectedまでの遅れだけではnative処理とOSの実行待ちは分離できない。
- detected→forth_returnはForth側の巻き戻し、forth_return→runner_returnは結果コピー（成功の場合）やVM解放を含む。runner_return→sealedはqueue cleanup、sealed→publishedは公開前のgate取得等を含む。
- published→observedは公開後からhost初回取得までの区間であり、Wake、hostのsleep・描画・OS実行待ちを含み得る。observed→host_stoppedには台帳照合と診断出力の負荷も含まれる。
- deadline行と後続行を照合し、物理返却前の超過と、走査・観測の競合を区別する。token storeとready storeは前後の時計取得そのものではないため、境界付近の値を厳密な合否判定に使わない。
- ※推測です：CPUの実行待ちが疑われる場合は、同じ再現でLinuxのscheduler trace（sched_switch/sched_wakeup）と両スレッドのスタックを採取すると区別できる。実際にCPUで実行していた区間、off-CPU区間、ページフォルト、pipe待機、gate待ちを照合する。段階ログだけで原因を確定しない。

これは診断の準備であり、確認点の頻度・native上限・D07の値を変更する修正ではない。原因確定とLinuxでの10 ms条件の評価は残作業である。

## Windowsでの検証

PowerShell、Zig 0.17.1、作業ツリー内のZIG_GLOBAL_CACHE_DIRで最終ソースを検証した。
時刻の大小・差分・Linuxとの比較は評価していない。

| 検査 | 結果 |
|---|---|
| `zig build test` | 成功 |
| `zig build test -Ddebug=false` | 成功 |
| `zig build runtime-test` | 成功 |
| `zig build -Dtask-trace=true` | 成功 |
| `python tests/scripts/trace-task-path.py` | 正常終了、8件のレコード形式を確認。generation=4の結果到達を確認 |
| `zig build runtime-test -Dtask-trace=true` | 成功。偽時計による期限超過を含む診断経路も動作確認 |
| 変更した全8件のZigファイルの `zig fmt --check` | 成功 |
| `python -m py_compile tests/scripts/trace-task-path.py` | 成功 |
| `git diff --check` | 成功 |

fmtの対象は `build.zig`、`src/forth.zig`、`src/core/runtime_base.zig`、`task_trace.zig`、`task_schedule_host.zig`、`task_queue.zig`、`task_job.zig`、`task_memory.zig` である（後半6件はsrc/core配下）。
通常の診断ドライバーでは要求・検出・帰還・封印・公開・観測の各項目が記録されたことだけを確認した。
期限超過の出力経路は追加のruntime-testで確認した。これらは停止速度や値の妥当性の検証ではない。
生ログは `.work/06h/task-path-trace.log` と `.work/06h/runtime-trace.log` に保存した。
Linux実行、OSスケジューラ情報の採取、原因の確定、D07の時間条件の評価は未実施である。

## 06-H 続報：Linuxログの解釈と生成・回収の分離（2026-11-24）

この節は初回診断の続報である。根拠は提供された `docs/06h-linux-trace.log` と現行ソースであり、今回は速度・時間の測定やLinux実行を行っていない。時間値は提供ログに対するClaudeの集計値である。改良後のLinux採取・評価はClaudeが行う。

### 提供された結果の解釈

12コア、負荷ほぼ0のLinuxで、取消し3件のvm_start→restoredは39.3 / 38.7 / 38.6 ms。要求はこの区間に入り、restoredの0.3〜0.4 µs後にdetectedが記録されている。旧コードは生成前と生成・復元完了後にしか確認しないため、要求から検出まで23〜32 msが残った。これらの取消し行ではprepared・forth_returnが0で、Forth実行前の帰還である。Forth計算ループ自体はすぐ取消しに応じているという利用者・Claudeの観測と整合し、この3件の遅れをForthループ全体の確認不足とは説明できない。

detected→runner_returnは6.4〜6.5 ms。確認点からのエラー帰還と、旧task_jobのdeferによるVM・Storage・Snapshot参照解放等を含む。個別のfreeごとの時間は記録されていないので、全量を特定のOS呼出し一つに帰属させない。

既存ログのvm_start→restoredに途中の記録はなく、**39 msの各処理への時間配分は未確定**である。1356のWindows値（already_zero=trueのallocate＋init中央値94 µs、false約8.1 ms、restoreFresh約0.32 ms）は別環境・別構成の観測なので、Linux値から差し引かない。負荷が小さいことだけでも、ページフォルト・OS実行待ち・実際のメモリ書込みの内訳は区別できない。

### コードによる内訳と追加した記録

通常VMの `Storage.allocate`、`State.init`、`restore`、`restoreFresh` の処理は変更していない。ワーカー専用の `task_storage.allocate` と `restoreFreshWorker` に確認と記録を置いた。時刻記録は `-Dtask-trace=true` のときだけ有効で、falseでは時計取得・診断用atomic・出力は除去される。取消し確認は診断設定にかかわらず有効である。

| 終了段階（直前の段階との差） | 実際の処理と費用 |
|---|---|
| state_allocated（vm_startから） | limits.validate、事前確認、Snapshot retain、Stateのallocator.create。OS確保と安全検査時のundefined書込みも含む |
| memory_allocated | 論理メモリ全体（data＋heap＋locals）のallocator.alloc |
| data_allocated / return_allocated / float_allocated | 各スタックのallocator.alloc |
| loops_allocated / frames_allocated / catches_allocated | ループ・呼出し・CATCH配列のallocator.alloc |
| storage_zeroed（catches_allocatedから） | 必要な場合のmemory・data/return/floatスタックの明示0埋め。64 KiBごとに取消し確認 |
| storage_allocated | Storage所有権の確立と取消し確認 |
| initialized | State.init。Stateの既定値、制御セル・キー名等の書込み、installBuiltins。writer.utime_fnはnullでホスト時計コールバックは呼ばない |
| plan_allocated | 復元Planのallocator.create。安全検査時のundefined書込みも含む |
| restore_validated | image_restore_plan.prepare。画像parse、機能・語・Op・境界・オブジェクト・再配置等の検査、復元計画作成 |
| restore_applied | apply(memory_is_fresh=true)。語・コード・名前・保存メモリ範囲・heapオブジェクト・再配置の反映、索引再構築、debug配列初期化、call特殊化等 |
| restored | 復元完了の境界。旧記録と異なりPlan解放は次の区間へ分けた |
| plan_released | 成功時のPlan解放。途中失敗ではPlanもVMの後片付けに渡す |
| fresh_checked / resolved | task_transfer.checkFresh / 入口名lookup |
| grants_ready | Grants.init。私有heap走査と許可領域表の割当て |
| permissions_checked | permissions.inspect。到達する語・Opの許可検査と一時割当て |
| input_ready / prepared | 入力コピー・ABI準備 / 再配置追跡を外してForth実行を始める直前 |

ページの予約と最初の接触は別である。Linuxの匿名マッピング確保だけでは全ページに物理メモリを書き込まない。allocatorの安全検査用undefined書込み、明示0埋め、State.init、復元コピー等で最初に触れた区間にページフォルト費用が入る。上の段階ログはOS確保・ページフォルト・CPU実行待ちを個別計測しない。さらに分ける必要があればClaude側でOS情報を採取する。

診断のworker側は固定領域への時刻記録のみで、ログ整形・stderr出力・診断用の追加割当ては行わない。出力はhost側のobserved/reconciled/deadlineで行う。同時にhostが出力していた場合のスケジュールへの影響は、ログだけでは除外できない。

`trace-task-path.py --analyze <既存ログ>` も新段階に対応させた。旧ログにない項目は0とし、旧形式も読める。今回はドライバーの実行・時間差測定は行っていない。

### (a) 生成途中の取消しと部分所有権

State確保後、Storageの7配列それぞれの確保後、ゼロ化後、State.init後、Plan確保後、復元事前検査後、復元反映後、Plan解放後、fresh検査後、入口解決後、grant構築後、許可検査後、入力コピー後に確認する。要求済みならTaskCancelledを返し、後続段階へ進まない。明示0埋めの途中も64 KiBごとに確認する。

State未初期化、Storage部分確保、Plan保持をFreshVmで所有する。未初期化StateにはreleaseImagesを呼ばず、確保済みのStorageだけを解放する。同期runでは帰還までに解放し、実キューのworkerでは独立した回収所有者へ移す。Snapshot参照もその所有者が保持する。

単一のallocator呼出し、State.init、復元の事前検査・反映、grant構築、許可検査、入力コピーの内部すべてを割込み可能にしたわけではない。段階での即時帰還は試験できるが、任意環境の要求→停止10 msを保証しない。新ログで長い単独区間が見つかれば、追加分割の対象になる。

### (b) OSゼロ保証と1361の転送契約

Zig 0.17.1同梱の `std/heap/PageAllocator.zig`（map/alloc/free/unmap）と `std/mem/Allocator.zig`（allocBytesWithAlignment）をAppData内のインストール先で確認した。

- Linuxはmmap(PRIVATE | ANONYMOUS、fd=-1)で新規の匿名マッピングを取得し、freeはmunmapする。OSのゼロ初期化を使い、自前の使用済みバッファをプールして返さない。
- Windowsは新規領域のNtAllocateVirtualMemory(COMMIT | RESERVE)、整列の追加経路でも新規reserve→commitを使い、freeはRELEASEする。新規ページはOSがゼロ初期化する。
- PageAllocatorのresize/remapによる使い回しは、Storageの新規allocには使わない。
- 公開APIのAllocationsは既定backingがpage_allocator。使用量のatomic予約後、そのままbacking.rawAllocへ委譲し、freeもrawFreeへ委譲する。suballocation・独自プールはなく、resize/remapは無効なので、この性質を維持する。

Linux/Windowsの直接page_allocatorはvtable一致で識別する。公開APIのwrapperはbackingのvtableを確認して保証をExecutionに明示的に渡す。別backing（試験の失敗注入allocator等）ではfalseにする。未知のwrapper・汎用allocatorから保証を推測しない。

ただしAllocator.allocはundefinedを設定するため、runtime safety有効時には新規ページを汚す。従来Storageと同じ `!already_zero or std.debug.runtime_safety` の条件で0埋めを維持する。**-Ddebug=falseはForthのdebug機能を外す設定であり、Zigのruntime safetyを外す設定ではない**。既定の `zig build -Dtask-trace=true` で明示0埋めが省けるとは報告しない。

1361の「結果はHEREより先も含むdataLimitまでのデータ領域から返り得る」「未ゼロ化の使い回しバッファは禁止」という契約を維持する。画像で上書きする部分だけのゼロ化にはしていない。省略はOSゼロ保証がある新規ページ、かつruntime safety無効の場合に限定する。汎用allocatorと安全検査有効時は、対象範囲を従来同様にすべて0にする。通常VMの割当ては変更していない。

### (c) 終端公開後のworkerによる解放

STATE_MACHINEの終端と回収の分離（3節、5.1〜5.3節）に照らし、Forth実行・入力処理・結果コピー・診断確定が戻り、その後Job・入力・トークン・結果バッファへworkerが触れなければ、私有VMの解放は回収段階へ回せると判断した。

実キューではExecution.runが独立所有のRetiredへVM（途中生成も含む）を移す。queueはrunner帰還後、RetiredをJobから取り外し、sealを済ませ、readyをrelease公開して通知する。その後workerがRetiredを破棄する。解放にはRetired、VM、Snapshot参照、allocatorだけを使い、公開済みJob/token/入力/結果には触れない。成功結果はVMから独立したコピーを公開前に確保済みである。成功後の遅い取消しで成功を変えないD04も維持する。

queueのgateでcleaningを公開前に設定し、解放完了後に解除して再通知する。Host.collect、RELEASE後の自動回収、Reaper、restoreのidle判定はこの印を確認する。終端を観測しても、解放中のJob/Execution/allocator所有者は破棄できない。同じworkerが解放完了まで次のVMを生成しないため、VMが重複しない。解放中の割当ても公開APIのusedへ計上されたままである。

既存の要求→回収100 msの枠内で後片付けも待つ。期限後もcleaningが残ればReaperは回収未完了として扱い、全体shutdownStatusもresources_activeにする。時間内完了を保証したわけではない。終端を変えず資源を保持し、強制終了・detach・見切り解放は加えない。

runnerの直接同期呼出しではworker_retirementを有効にせず、その呼出し内で解放する。公開できない回収所有者を残さないためである。

公開後のworkerはtokenへ触れないので、VM解放完了時刻をtokenへ追加記録していない。今後のrunner_return/sealed/publishedはVM解放前を表す。回収完了はcleaning解除と回収処理で判定する。旧runner_returnと同じ意味の時刻として比較しない。

### 試験と最終検証

- setup.Stage全段階の試験専用hookで取消しを要求する。後続hookに進まないこと、TaskCancelled、Snapshot参照数の復元を確認する。経過時間で判定しない。
- std.testing.allocatorとcheckAllAllocationFailuresで、同期解放と回収所有者への移譲を両方検査する。Storage部分確保、未初期化State、Planも対象とする。
- Executionの回収所有者自体の確保失敗、成功・Forth失敗・入口不在、後続の各割当て失敗でも資源が漏れないことを検査する。
- 同期フラグで後片付けを保留し、終端とexecution_ref消滅は観測できるが、collect・restoreは拒否され、次のジョブは未取得であることを確認する。解除後に後続実行・回収を確認する。
- 公開APIのゼロ保証判定、未使用データ領域・スタックのゼロ、解放後使用量0、別backingで保証が無効になることを検査する。
- 既存試験の「終端観測＝資源解放完了」という仮定を、明示的な回収完了条件を待つ形に更新した。

| 検査 | 今回の結果 |
|---|---|
| `zig build test` | 成功 |
| `zig build test -Ddebug=false` | 成功 |
| `zig build runtime-test` | 成功 |
| `zig build -Dtask-trace=true` | 成功 |
| 変更したZigファイルの `zig fmt --check` | 成功 |

Linuxの改良後の内訳、10 ms/100 ms条件の評価はClaudeの採取待ちである。今回git commit・branch作成/切替・tag・push・tque変更、測定ドライバー・ベンチマーク実行は行っていない。

今回の検証ログは `.work/06h/test-current.log`、`test-nodebug-current.log`、`runtime-current.log`、`build-trace-current.log`（後半3件も同じディレクトリ）に保存した。Pythonは構文と既存ログ・合成した新形式の読取りだけを確認し、測定対象のアプリは起動していない。回収期限は偽時計を100 ms超過まで進め、終端を保持したまま回収未完了とする試験でも確認した。


## Linux 2回目のログと今回の追加改良（2026-11-24）

対象は `06h-linux-trace-Debug.log` と `06h-linux-trace-ReleaseFast.log`。12コア、負荷ほぼ0という実行条件は利用者の申告による。今回は既存ログを `--analyze` で読み取り、測定ドライバー・ベンチマークは実行していない。

Debugではstate_allocated→memory_allocatedが約24 ms、vm_start→state_allocatedが約2.6 ms、storage_allocated→initializedが約1.8 ms。取消し要求token_after→detectedは約10.5 / 2.6 / 13.4 msで、10 ms以内を満たさない例が残る。約24 msの区間は明示0埋めに到達する前の `Allocator.alloc` である。コード上はruntime safetyによるundefined書込みが配列全体に走る。ページフォルト・OS確保・スケジューリングの個別寄与はこのログだけでは確定しない。

ReleaseFastでは生成から復元まで約4 ms、plan_allocated→restore_validatedが約3.2 ms、storage_allocated→initializedが約0.29 ms。次の置換えまでに各要求の計算が完了しており、今回のログから取消し応答時間は評価できない。forth_return→runner_returnは約7〜11 µs。これは前回導入した公開後回収の境界であり、VM解放完了時間ではない。

### 取消し可能な初期化と所有権

ワーカー専用allocateArrayは、サイズの積のオーバーフローを検査し、型のalignmentでrawAllocする。標準Allocator.alloc内部の一括undefined書込みを通さず、runtime safety有効時には1 MiBごとに同じundefined初期化と取消し確認を行う。通常VMのStorage.allocateは変更しない。memory、各スタック、Stateが対象である。必要な明示0埋めは従来の64 KiB確認を維持し、試験hookにも公開した。OSゼロ保証がないallocatorに対するゼロ初期化の契約は維持する。

部分初期化中の配列はallocateArrayが所有し、失敗時はその場で解放する。Storageに渡った配列は従来の部分所有権で解放・回収する。State確保中の失敗ではSnapshot参照も返す。State.init完了前の取消しではreleaseImagesを呼ばない。

vm_start→state_allocatedを、snapshot_retained（limits検査・retainまで）、state_reserved（rawAllocまで）、state_chunk（最初の1 MiB書込み）、state_allocated（全書込み完了）に分けた。既存コードではStateのallocator.createにも一括undefined書込みがある。State.initの構造体一括代入も、ワーカーでは既定値をフィールドごと・最大1 MiBずつ反映する経路に分けた。制御セル・キー名・組込み語の設定は通常initと共通化する。runtime safety無効時は元のState.initを使い、分割のためだけの全フィールドコピーを増やさない。残るrawAlloc自体、組込み語の設定、復元prepare/apply内部は取消し可能な細分化の対象外であり、任意環境で10 ms以内を保証する変更ではない。

### ReleaseFast向けの追加採取

Claude側でtraceビルドに対し、次を実行する（今回は未実行）。

```text
python tests/scripts/trace-task-path.py --cancel-stages --log .work/06h/long-cancel.log
python tests/scripts/trace-task-path.py --analyze .work/06h/long-cancel.log
```

`trace-task-cancel.fs` のTRACE-LONGは `BEGIN AGAIN` で計算を継続する。各場面を別プロセスで実行し、SIGMA_TASK_TRACE_CANCEL_ATに指定した段階の記録をホストのTASK-STATEポーリングが観測したら、通常のhost.requestCancelを呼ぶ。vm_start、State確保、Storage各配列、初期化、Plan確保、復元事前検査・反映、入口準備、Forthループ途中（executing）の場面を用意した。各場面で取消し終端とtoken_after/detectedが記録されたことを検査する。設定の読取りと自動要求はtask-traceビルドに限定する。通常ビルドでは有効にならない。ホストポーリングはこの診断固有の負荷になる。

これは指定段階を通過した後の要求であり、その段階の内部に要求が必ず入るとは保証しない。短い区間はホストの観測までに通過し得る。生成・復元の各区間を狙うには直前の段階を指定する。ログのcancel-after-stageと解析のlast-stage-before-tokenを照合し、実際に要求された位置で分類する。executingはループの取消し確認位置で最初に記録し、preparedだけでは計算途中とは判定しない。workerに待機や人工的な遅延は挿入しない。旧ログにない追加段階は省略して前後の既存段階を解析する。

### 今回の試験

setup.Stage全境界での既存試験に加え、2個目のallocation_chunk、state_chunk、zero_chunk、state_initialized_chunkで取消しを要求する。同期解放と回収所有者への移譲の両方をstd.testing.allocatorおよびcheckAllAllocationFailuresで検査し、TaskCancelled、確認回数2、Snapshot参照数の復元を検証する。時間を合否基準にしない。

検証結果は後記する。新しいLinux実測と10 ms条件の再評価はClaude側の採取後に行う。

Pythonは構文検査、提供されたDebug 10レコード・ReleaseFast 8レコードの読取り、追加ラベルの互換性を確認した。25場面のドライバー制御はsubprocessを模擬して検査した。Forth測定ハーネスの実機実行と取消し遅延の実測は未実施である。

検証用のグローバルZigキャッシュは、この環境のアクセス制限に合わせ `ZIG_GLOBAL_CACHE_DIR=<worktree>/.zig-global-cache` を指定した。最初の試行では既定キャッシュのAccessDenied、および編集中ファイルの再読込みとフィールド列挙APIのコンパイルエラーがあり、修正後に再実行した。下記の最終ログを検証結果とする。

| 最終検証 | 結果 | ログ（.work/06h/） |
|---|---|---|
| `zig build test` | 成功 | test-round3.log |
| `zig build test -Ddebug=false` | 成功 | test-nodebug-round3.log |
| `zig build runtime-test` | 成功 | runtime-round3.log |
| `zig build -Dtask-trace=true` | 成功 | build-trace-round3.log |
| 変更したZigファイルの `zig fmt --check` | 成功 | 標準出力なし、終了コード0 |
| `zig build -Dtask-trace=true -Doptimize=ReleaseFast` | 成功 | build-trace-fast-round3.log |

指定の5コマンドと整形検査はすべて成功した。git commit・branch作成/切替・tag・push、tque変更、速度・時間を採取するシナリオの実行は行っていない。新しい取消し応答時間は未測定であり、今回のコード・試験の結果だけで10 ms以内に改善したとは断定しない。

## 取消し段階ハーネスの読込み修正とWindows実行確認（2026-11-24）

### 原因と対応

Linuxで報告された `tests/task/task-console.fs:12: TASK-SNAPSHOT ?` は、WindowsのDebugでも修正前の `--cancel-stages` を実行して再現した（終了コード1）。記録は `.work/06h/cancel-before-fix.log` と `cancel-before-fix-output.log` に保存した。

`task-console.fs` はEXTENSIONが検索順にあることを前提とする。通常の `task-path.fs` と診断用 `diagnose-task-path.fs` は、先に読む `task-path-worker.fs` の `REQUIRE-EXTENSION ALSO EXTENSION` により、この条件を満たす。一方、`trace-task-cancel.fs` はworkerを読み込まず、同じ設定も行っていなかった。これがTASK-SNAPSHOTの名前解決に失敗する原因である。

既存のworker例および `check-task-console.fs` に合わせ、`trace-task-cancel.fs` の冒頭、TRACE-LONGの定義と `task-console.fs` の読込みより前に `REQUIRE-EXTENSION ALSO EXTENSION` を追加した。同じコマンドは修正後に成功した。

前回はビルド、Pythonの構文・ログ読取り、subprocessを模擬した制御の確認までで報告しており、実際のsigmaによる `--cancel-stages` の場面は実行していなかった。そのため、Forth読込み時の検索順の不足を確認できていなかった。今回、以下の実行で実機動作を確認した。

### 今回のWindows検証結果

PowerShellから実行し、Zigのグローバルキャッシュは引き続きworktree内を指定した。Debugをビルドして直ちにドライバーを実行し、次にReleaseFastをビルドして同じドライバーを実行した。両方とも `--analyze` は使わず、動作の合否だけを確認した。

| コマンド | 結果 | ログ（.work/06h/） |
|---|---|---|
| `zig build -Dtask-trace=true` | 終了コード0 | build-trace-followup.log |
| `python tests/scripts/trace-task-path.py --cancel-stages --log .work/06h/cancel-Debug-followup.log` | 25段階すべて完了、終了コード0 | cancel-Debug-followup.log、cancel-Debug-followup-output.log |
| `zig build -Dtask-trace=true -Doptimize=ReleaseFast` | 終了コード0 | build-trace-fast-followup.log |
| `python tests/scripts/trace-task-path.py --cancel-stages --log .work/06h/cancel-ReleaseFast-followup.log` | 25段階すべて完了、終了コード0 | cancel-ReleaseFast-followup.log、cancel-ReleaseFast-followup-output.log |
| `zig build test` | 終了コード0 | test-followup.log |
| `zig build test -Ddebug=false` | 終了コード0 | test-nodebug-followup.log |
| `zig build runtime-test` | 終了コード0 | runtime-followup.log |
| 変更中のZigファイル20件の `zig fmt --check` | 終了コード0 | fmt-followup.log |

各段階でsigmaの終了コード0、対象段階の到達記録、token_afterが対象段階以降であること、detectedの記録、取消し終端 `trace-terminal=5` をドライバーが検査した。Windowsのトレースに含まれる速度・時間の値は評価していない。今回の修正対象はForthハーネスとこの報告書であり、整形検査はworktreeで変更中のZigファイル全件を対象とした。

### 提供されたLinux Debugログの記録

`docs/06h-linux-trace-Debug-3.log` は、0埋めを分けた後の通常の場面（`--cancel-stages` なし）のLinux Debugログである。利用者から提示された取消し検出区間 `token_after→detected` の値は、順に **0.19 ms、0.38 ms、0.14 ms**。参考値として記録し、速度・時間の評価や採用条件への適否判定は行わない。今回Linuxで新たな実行はしていない。

git commit・branch作成/切替・tag・push、tque変更は行っていない。

## レビュー指摘への対応（2026-11-24）

各指摘を現在の所有権・分岐条件と照合した。速度・時間の値の評価、測定シナリオの実行は行っていない。

1. **Snapshot参照の解放順序の退行を確認し修正した。** `Execution.run` が退役VMを受け取った後、成功・失敗・取消しのいずれでも、runnerから戻る前に `FreshVm.releaseExecutionResources` を呼ぶ。この処理はVM固有の画像、残存Plan、Snapshot参照を解放する。`deinit` からも呼べるよう二重解放を防ぎ、公開後のRetiredにはState・Storageの解放と退役所有者自身の破棄だけを残す。これによりqueueのseal・ready公開より前にSnapshot参照が返る。Admissionの解放は従来どおり `runWithOptions` のdeferで行う。
   - 退役破棄を実行しない状態で、3世代保持→Aから実行→runner終了・cleanup→Aの所有参照解放→再captureが成功する決定的な試験を追加した。sleepや回収完了待ちを挟まない。
   - 公開APIにも3個のTASK-SNAPSHOT→AからTASK-SUBMIT→TASK-WAITで終端→AのTASK-SNAPSHOT-RELEASE→新しいTASK-SNAPSHOTの試験を追加した。
   - 既存の成功・失敗・OOM網羅試験では、退役破棄より前のSnapshot参照数も検査する。
2. **0埋め省略経路の未検証を確認した。** 既存のaccounting allocator試験を強化し、runtime safety有効時にはzero_chunk到達、無効時にはzero_chunk未到達を明示的に検査する。OSの新規ページをbackingとするStorageのmemory・data_stack・return_stack・float_stack全要素がゼロであること、解放後の使用量0、backing変更でゼロ保証が無効になることを確認する。ReleaseFastで同じ試験を実行する。
3. **runtime safetyに依存する試験段階を確認し修正した。** safety無効時はallocation_chunk・state_chunk・state_initialized_chunkを、全境界試験と2回目のchunk取消し試験から除く。ただし、この試験のallocatorはstd.testing.allocatorであり、ゼロ保証を渡していないので、ReleaseFastでもzero_chunkを通る。したがって、この試験ではzero_chunkを除外しない。page_allocator等のゼロ保証を使うReleaseFast経路でzero_chunkを通らないことは上記2で検査する。指摘の誤りとして退けた項目はない。
4. **復元失敗時の画像解放経路の違いを確認した。** State.init完了後の復元失敗でもFreshVmの終了処理がreleaseImagesを呼ぶ。対象はそのVM自身のgfx_imagesであり、main VMやSnapshotの画像を解放する処理ではない。State.init未完了なら呼ばない。今回の退役経路ではこの処理も公開前に行い、その後のdeinitでは繰り返さない。これは以前のエラー経路との違いとして記録する。

### 今回の検証

PowerShellから実行し、`ZIG_GLOBAL_CACHE_DIR` はworktree内の `.zig-global-cache` を指定した。以下の全コマンドが終了コード0で成功した。ログは `.work/06h/` に保存した。

| 検証 | 結果 | ログ（.work/06h/） |
|---|---|---|
| `zig build test` | 成功 | test-review.log |
| `zig build test -Ddebug=false` | 成功 | test-nodebug-review.log |
| `zig build runtime-test` | 成功 | runtime-review.log |
| `zig build test -Doptimize=ReleaseFast` | 成功 | test-fast-review.log |
| `zig build -Dtask-trace=true` | 成功 | build-trace-review.log |
| 変更中のZigファイル全件の `zig fmt --check` | 成功 | fmt-review.log |

ReleaseFastも通常と同じtestステップ（core・host・runtime）全体を実行した。build.zigの各テストmoduleは指定されたoptimizeを使用するため、OSゼロページ試験もruntime safety無効の分岐で実行される。今回の変更はtask_job_queue.zig、task_snapshot.zig、task_job_test.zig、task_public_api_test.zig、host_task_api.zig、および本報告書。git commit・branch作成/切替・tag・push、tque変更は行っていない。
