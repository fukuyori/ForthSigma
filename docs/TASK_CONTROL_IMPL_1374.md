# タスク1374：終了時の回収（1375統合後）

更新日：2026-11-24。担当：ロク。詳細な統合記録と検証は [1375の報告書](TASK_CONTROL_IMPL_1375.md) にまとめた。本書は統合後の1374の契約を記録する。

## 変更ファイルと要点

- src/core/task_reap.zig：所有者別・全体のbegin/poll/finish、busy検査、Disposal.retire/destroyを提供する。期限と診断はHostへ委譲する。
- src/host_task_reap.zig：任意のReaper結合、BYE・明示的所有者終了、完全復元の接続点である。
- src/core/task_schedule_host.zig：受付停止、終了所有者の記録、RELEASE、内部検索による取消しと回収を提供する。
- src/main.zig：実行単位ごとのフック、埋込みイメージ復元前検査、VM/Runtime破棄前の最終回収を接続する。失敗時は独立した後始末を行って1375のabortへ進む。
- src/tests/task_reap_test.zig：所有者分離、回収順序、内部参照、遅延帰還、復元、Snapshot、フック、実Wakeのfinishを検証する。
- src/runtime_test.zig：host専用試験をruntimeルートへ登録する。本統合では整形も行った。

## 設計上の選択と理由

2026-11-24の利用者判断に従い、REPLのエラー・ABORT・QUITではタスクを終了しない。BYEと明示的所有者終了だけで回収する。Causeはowner_exit・bye・restoreであり、restoreは終了ではなく静止検査である。

Reaper.beginはHost.beginShutdownまたはendOwnerに委譲する。Reaper.pollはHost.poll、shutdownStatus、collectを使い、独自の100ms期限・markUnresponsive・ledger.collectを持たない。不応答の台帳印はHost.checkStopDeadlinesだけで付ける。所有者別終了でも最初のrequested_atと10ms停止診断を保持する。ホスト全体の終了期限は最初のbeginShutdownから100msであり、古い取消し期限と分ける。

WAIT・コピー利用者はretireで退役させる。物理帰還・終端・内部参照消尽を確認してからHost.collectし、封印結果とPublicationをdestroyへ渡す。JobやHost等は回収まで固定位置に保持する。遅延帰還は実際の結果で終端化し、成功を取消しへ書き換えない。所有者別回収では共有workerを終了しない。全体終了ではworkerの退出確認後だけjoinする。

完全復元のbusy検査はbegunの早期returnより前に行う。活動中・実行参照・内部参照があればBusyで拒否する。静止した完了記録は保持できる。完全復元は受付やworkerを閉じず、復元後も投入できる。LOAD-DICTIONARYは辞書追加であり、この完全復元フックの対象ではない。

## 担当外変更と通常経路への影響

Hostの変更は1374の無効化と1375の診断を同じ回収経路へ結び付けるためである。Queueの変更は待機中の解除不能な不応答印を除くためである。両者の詳細は1375の報告書に記録した。

通常経路の変化はmainの実行単位フック、復元前フック、終了時deferだけである。forth.zig、通常VMの命令実行ループ、State配置、worker許可集合、命令ごとの取消し確認は変更していない。公開Forth語・公開エラー値は追加していない。

製品の起動時にはReaperをbindしない。結合処理は公開語を作る1379の担当である。未結合時の終了フックは何もしない。最終回収失敗はflushOutput、utf8_console.finish、resize_scope.endを行い、1375のhost_task_stop.abortの共通診断と終了コード1を使う。C exitに伴うatexit・stdio flushの制約は1375の報告書に記した。

## 試験と実行結果

PowerShell、Zig 0.17.1、作業ツリー内キャッシュで検証した。

| コマンド | 最終結果 |
|---|---|
| zig build test | 成功 |
| zig build test -Ddebug=false | 成功 |
| zig build runtime-test | 成功 |
| zig build -Dtarget=x86_64-linux | 成功、クロスビルドのみ |
| zig build -Dtarget=aarch64-macos | 成功、クロスビルドのみ |
| zig fmt --check（差分のZig 9ファイル） | 成功 |
| git diff --check | 成功 |

いずれも終了コード0である。未結合フック、REPLの打ち間違い、ABORT/QUITでの継続、BYEでの回収、別理由のbegin後の復元Busy、実イメージ復元後の受付継続、実Wakeを使うfinishを検査した。回帰時の無限待機を避けるためホスト側試験ループへ反復上限を設けた。

## 未確認事項と利用者判断

Linux/macOS実機実行、実際の停止不能VMとexitの実行、時間性能は未確認である。Linux実行は別機械のClaudeが担当する。速度・時間の測定は行っていない。タスク機能の製品結合と実際のWAIT/コピー利用者の退役は1379以降に残る。

今回の追加判断事項はない。commit・branch・tag・push・tque変更は行っていない。衝突マーカーは解消したがgit addは行わず、indexの解消登録はClaude側に残す。
