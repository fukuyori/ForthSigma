# タスク制御03-E（1372）：待機の再現試験

作成日：2026-11-24。基点は detached HEAD の `ab21c51` である。

## 1. 変更ファイルと要点

| ファイル | 内容 |
|---|---|
| `src/tests/task_wait_reproduction_test.zig` | 偽時計・偽起床による4試験である。本番Registration、task_paint.Source、task_scheduleを呼び、公開位置、保持状態、返却集合、参照数、世代、循環順序を検査する |
| `src/tests/task_wait_reproduction_host_test.zig` | 実Wakeを使う4試験である。本番の入力adapter、Task adapter、キュー、スケジューラHost、台帳、描画状態を使う |
| `src/forth_test.zig` | ホスト資源を使わない試験を1行で登録した |
| `src/runtime_test.zig` | 実Wake・キュー等を使う試験を1行で登録した |
| `src/host_task_wait.zig` | 解放済みJobへの新規登録を事前検査で拒否する最小修正である |
| 本書 | 実装・試験・残る確認範囲の記録である |

公開Forth語・公開エラー値・VM実行部は追加・変更していない。通常実行経路の変更はない。コミット、ブランチ作成、プッシュ、tque変更、パッケージ作成、速度・時間の測定は行っていない。

## 2. 設計上の選択と理由

試験用に待機アルゴリズムを再実装せず、本番の `Registration.open/poll/close` を使った。偽装するのは時計、起床操作、供給元の公開タイミングである。供給元のattach/probe/detach、observeに同期した公開を挿入するため、任意のsleepやスレッドの偶然の順序には依存しない。

描画は本番の `task_paint.Source.publish/register/probe/unregister` を使う。現行 `task_wait.Kind` は input/io/task/clock であり描画を含まない。そのため描画を独自kindへ拡張せず、同じ公開・巡回に対して独立した描画登録を照会する。共通返却配列に描画が入ることを検証したものではない。

本番キューを起動前の状態で用いることで、ホストによる待ち項目の取消し・期限処理を決定的に再現した。runnerは呼ばれた場合に失敗する。実workerのスケジューリングや実VMの停止をこの試験の成立条件にしていない。

コア試験は有限回の巡回と、予期しないsleepを即時エラーにする偽起床を用いる。ホスト試験には独立スレッド・実単調時計・専用Wakeによる20秒の監視期限を設けた。監視は待機・ロック・後片付けの停止を検出してプロセスを失敗させるものであり、応答時間の測定ではない。

## 3. 再現した順序と判定

以下のW番号は `TASK_CONTROL_WAIT_REGISTRATION.md` 10節との対応である。複数内容を持つW項目について、その全実機条件の完了を意味しない。

| 対応 | 今回の判定 |
|---|---|
| W01〜W03 | 初回observe前、observe後attach前、attach内、再observe後probe前、probeの状態採取後、native待機入口直前の6位置で公開する。前4位置はsleepなし、後2位置は保存世代との差による再取得で成立する。各公開境界の直前にpending、公開後にpaintedであることを検査する。描画固定目標2を後続SHOWの3へ動かさない |
| W04・W06 | 入力、成功終端、対象時計、WAIT期限、待機取消し、割込みを同じ巡回に入れる。返却3件と独立した3印を保持し、入力バイトと結果値42を後から取得できる。描画はpendingで登録し、公開直前もpending、公開後にpaintedであることを別登録から確認する。I/Oはコア側の保持供給元で重複対象の各番号を確認する |
| W05・W14 | コアでは8巡の返却件数と絶対期限100の不変を確認する。偽通知32回ずつはカウンターを増やすだけでRegistration.pollは読まないため、通知併合の根拠にはしない。ホストでは実Wake通知64回後のsleepと再pollが無関係通知で終了しないことを確認する。対象時計40の先行成立でWAIT期限到来を偽造しない |
| W06・T09 | 本番Task adapterを通してWAIT期限のみ、割込みのみ、待機取消し＋割込み＋期限を採取する。期限返却後にcloseし、次の期限を設定して新規openする。割込みはpollへ渡すboolであり、実信号、bindInterruptWake、信号パイプを通る割込みの検証ではない。本番Hostの台帳がqueuedのままで、実行参照、対象の取消し印、キュー待ち件数、未終端状態が変わらないことを確認する。その後の対象自身の取消しでは同じ巡回にcancelledが返る |
| W07 | キュー期限を偽時計で到来させ、共通notifyを無効化した状態でもprepare/probeから失敗終端とqueue_expired理由を得る。無期限WAIT自身のexpiredはfalseである |
| W08・T10 | 既存登録で終端を返した後、RELEASEを行うとreleasedを繰返し返す。元の失敗終端は不変であり、close後の登録件数は0となる。同じ解放済みJobへの新規openは拒否し、active、count、registration.generation、registration.observed、wake.observe()が変わらない。別試験で待ち中の仕事をopen → queue.release → pollの順に進め、既存WAITがcancelledではなくreleasedを返し、host.poll後の台帳がcancelledとなることを確認する |
| W09 | detach中に保持I/O状態と描画完了を公開する。封印済みの結果は0件のままで、登録参照数は0へ戻り、次の登録世代と描画probeで成立を得る |
| W16 | 全7供給元へ合成eventsを与える7巡で、本番schedulerの全供給元quotaと循環開始位置を確認する。先頭を全供給元が1回ずつ担当し、残作業中はrun_againとなり、WAIT期限も到来する。入力登録は接続しておらず、run_againはhost_wait.sleepのagain防護にも結び付けていない。1387のHost.decideでも実キュー情報と合成eventsに対する全供給元quotaを確認する |

同時成立のホスト試験では、成功Jobを構造体リテラルでsealedに設定してreadyを公開する。キュー投入・worker帰還による公開経路は通していない。

状態機械文書のT09はWAIT期限・中断・通知、T10はWAITとRELEASEの前後関係を含むため、後者も別途検査した。登録参照数の増減はコア試験の供給元で記録する。Task adapter自体はJobを借用するAPIであり、この試験はJobの物理回収や台帳登録参照の自動接続を追加していない。

## 4. 発見した不具合と担当外ファイルの変更理由

`host_task_wait.Task.source()` はvalidateに無条件成功のnoopを設定していた。このため `job.external_valid == false` でも新規 `Registration.open` が成功する構造であった。これは待機登録設計8節の「RELEASE後の新規WAITを無副作用で拒否する」に反する。

validateだけを専用関数に替え、解放済みなら既存内部エラー `HostFailed` を返すようにした。既存登録のprobeは引き続きreleasedを返し、内部完了の取得を継続する。公開エラー値は作らない。担当外の本番ファイル変更はこの1箇所だけである。修正前の挙動はソース確認に基づくものであり、修正前バイナリでの失敗実行は行っていない。修正後の拒否は回帰試験で確認した。

job.external_validと台帳（task_ledger.zig）のexternal_validは別々の印であり、まだ結び付いていない。Task adapterには本番の呼出し元がないため、公開層で古いIDを検査して拒否する処理は後のフロントエンドの担当である。今回の拒否試験はJobの外部有効性に対する内部アダプターの検査である。

試験ルート2ファイルの変更は指定の登録先へ各1行を追加するためである。台帳・キュー・描画・スケジューラの本体は変更していない。

## 5. 試験と実行結果

PowerShell、Zig 0.17.1で実行した。既定の外部キャッシュはAccessDeniedとなったため、以後 `ZIG_GLOBAL_CACHE_DIR` を作業ツリー内の `.zig-global-cache` に指定した。同ディレクトリは既存.gitignoreの対象であり、設定ファイルの変更は不要であった。最終確認では並列度の制限に `-j2` を使用した。今回の再検証ではPowerShellのプロファイルを無効にし、作業ツリー内のキャッシュを指定した。追加検査の初回コンパイルでは名前衝突、初回実行では再公開にもpendingを求める検査の誤りを検出して修正した。修正中のクロス試験コンパイルはファイル更新検出で失敗したため、ソース確定後に再実行した。下表は修正後の最終結果である。

| コマンド | 結果 |
|---|---|
| `zig build test -j2` | 成功（終了コード0） |
| `zig build test -Ddebug=false -j2` | 成功（終了コード0） |
| `zig build runtime-test -j2` | 成功（終了コード0） |
| `zig build -Dtarget=x86_64-linux -j2` | 成功（終了コード0） |
| `zig build -Dtarget=aarch64-macos -j2` | 成功（終了コード0） |
| `zig build core-check runtime-check -Dtarget=x86_64-linux -j2` | 成功（終了コード0）、試験のコンパイルのみ |
| `zig build core-check runtime-check -Dtarget=aarch64-macos -j2` | 成功（終了コード0）、試験のコンパイルのみ |
| `zig fmt --check src/host_task_wait.zig src/forth_test.zig src/runtime_test.zig src/tests/task_wait_reproduction_test.zig src/tests/task_wait_reproduction_host_test.zig` | 成功（終了コード0） |
| `git diff --check` | 成功（終了コード0） |

## 6. 未確認事項と利用者の判断

Linux・macOSでの実行は行っていない。Linux実行は別機械の担当へ渡す。Windows実コンソールへのフォーカス・キー解放投入、実reader/writer、POSIX fdの通知消費各境界、実ウィンドウのclose・最小化・再表示、macOS子のPAINTED処理は今回新しく検証していない。

W07の実worker帰還との競合全種、W08の封印直前RELEASE、W09の実callback終了同期、W10〜W13・W15・W17・W18の全条件網羅も今回の追加試験の範囲外である。既存試験の成功をこれらすべての再現成功として扱わない。飢餓に関する検査は合成eventsに対する本番スケジューラの有限quota・巡回順序・run_again判断についてであり、実OS供給元の処理費用の保証ではない。

要求→停止10ms、回収100ms、60Hz・管理1ms/巡、追加メモリ128MiB等の実測・最終受入れは未確認である。今回は新たな利用者判断を必要とする仕様変更はない。方式採用、公開API、性能受入れの保留を維持する。

## 7. レビュー反映

指摘1〜7を仕様とソースで照合し、すべて反映した。誤りと判断した指摘はない。今回の追加修正は試験2ファイルと本書だけであり、本番モジュールの追加変更はない。
