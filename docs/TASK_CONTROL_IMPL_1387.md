# タスク1387：タスク制御03-F スケジュールの結合

更新日：2026-11-24。担当：ロク。専用worktreeは D:/tmp/forthz-1387、HEADは83987a2（detached）である。本修正開始時には前回実装の未コミット差分が存在した。

## 変更ファイルと要点

| ファイル | 要点 |
|---|---|
| src/core/task_schedule_host.zig（新規） | 実キューと台帳の結合、FIFO置換、取消し、世代、結果コピー・適用・回収である。未知のJobをInvalidJobで拒否し、stageも旧世代を拒否する |
| src/core/task_schedule.zig | 許可検査付きadmitと純粋提案propose、所有者による系列分離、台帳満杯の逆圧である。コピー枠の既定を96KiBとし、Input.copy_bytesで設定可能にした |
| src/core/task_context.zig | worker全生存期間のWorkerScopeとVMによらない文脈照会である |
| src/core/task_permissions.zig | 実際のworker文脈から投入を拒否するrequireHostSubmissionである |
| src/core/task_ledger.zig | QueueFailureにworker_failedを追加した。registerの変更は取り消し、1364の契約を復元した |
| src/core/task_queue.zig | 原子的FIFO置換、キュー観測、取得証跡、worker文脈を追加した。停止未確認中も投入を受け付け、実行取得だけを止める |
| src/runtime_test.zig | ホスト専用の結合試験を登録した |
| src/tests/task_schedule_host_test.zig（新規） | 実Wake・実workerを使う結合試験11件である |
| src/tests/task_schedule_test.zig | 純粋提案と検査付き入口への追従である |
| src/tests/task_queue_test.zig | 停止未確認中の投入受理に既存試験を追従させた |
| 本書 | 設計、レビュー修正、検証、残作業を記録する |

src/tests/task_ledger_test.zigはHEADの内容へ戻した。通常のVM命令実行経路への変更はない。forth.zig、通常命令ループ、State配置は変更していない。命令ごとの定期取消し確認は追加していない。公開Forth語・公開エラー番号・動的実行・例外・counted・PAD・DO系の許可も追加していない。第三者コード・ライブラリの追加はない。

## 設計上の選択と理由

Hostは単一の直列ホストスレッド専用であり、専用Queue・固定16件の台帳を所有する結合である。Job、Host、Queue、runner文脈は固定アドレスで保持する。workerへ台帳を渡さない。WorkerScopeで初期化・runner・cleanup・終了通知まで覆い、申告フラグによる投入許可を廃した。入力のtask_resultは実台帳の識別子・所有者を検査してから拒否する。独立したbytesの由来を追跡するものではない。

投入前に呼出し側がJob・入力・Snapshot等を予約する。台帳のcreatedを予約し、キュー成立後にpublishする。失敗時は非公開予約を回収し、世代と旧要求を維持する。台帳16件が埋まれば置換でも逆圧とする。旧IDも回収まで一件を占めるためである。

ゲーム/TUIの同じ所有者・kind・streamだけを待ちFIFOの同位置で置換する。取得競合後は末尾へ追加し、満杯なら変更せず失敗する。I/OはFIFOを維持する。受理した同系列の旧要求へ台帳とキューの両方で取消しを要求する。物理的な取得・帰還を観測して台帳の実行参照を更新し、期限経過を停止完了と読み替えない。

世代はホスト全体の単調増加スタンプである。各記録が同系列の現在世代を保持し、最新記録の回収後も旧世代を復活させない。stage、コピー対象選択、takeResultで鮮度を検査する。takeResultは最終コピー後に一度だけ返す。

結果と独立した診断4バッファは連結せず、共通のコピー枠で段階コピーする。Host.copy_bytesは既定96KiBであり、copyTurnとdecideの両方へ反映する。純粋schedule.decideの設定はInput.copy_bytesである。コピー対象は古いID順、最大4完了である。呼出し側が封印元とコピー先の予算予約・非重複・寿命を保証し、collectまで保持する。

## レビュー指摘への対応

1. 指摘を採用した。USAGE_CONDITIONSの停止不能時の拒否対象は新規実行であり、1364の「停止未確認中でも投入を受け付け、実行開始だけ拒否」という決定を維持する。registerの追加検査と台帳試験変更を取り消し、admitの同検査も除去した。submitReplacingは停止不能中も待ちへ受理する。キューのunresponsiveラッチにより取得を止め、ホストpollのexpireで待ち期限切れとする。停止未確認中の受理・未取得・期限切れと台帳failedを試験した。
2. 指摘を採用した。16KiBは利用者決定ではなく、初期実装の値であった。既定96KiBの設定可能な枠へ変更し、最大G1結果＋診断の6巡コピーを試験した。計算は次節のとおり訂正する。
3. 指摘を採用した。Host.queueはinit後固定であり、待ち項目を新キューへ移すホストAPIは現在存在しない。前報告の「新しいキューで再開」は実装済み回復経路として扱えない。待ち項目と台帳ID・世代・期限を維持した安全なキュー交換は後続作業である。旧workerの帰還・join確認前に代替VMを生成してはならない。
4. 指摘を採用した。byJobをエラー返却へ変更し、submit・poll・decideで伝播する。未知のJobが待つ場合のsubmitとdecideのInvalidJobを試験した。releaseでもunreachableを実行しない。
5. 指摘を採用した。stageはfind直後に世代を検査し、旧世代ならInvalidTransitionを返す。バッファの検証・保持より前に拒否する。Host自体はバッファを確保しないため、呼出し側の事前予約そのものを省くAPIではない。旧世代のstage拒否を試験した。

誤りと判断して退けた指摘はない。

## 96KiB/巡と投入→公開100msの計算

以下は算術と設計配分であり、速度・時間の実測ではない。1KiBは1,024 bytesである。60Hzの100msは約6フレームであり、管理予算は1フレーム1ms、合計約6msである。run_againで巡回数を増やしても、この予算が増えるわけではない。

| 先行完了がない場合の対象 | 既定96KiBでの必要巡回数 |
|---|---:|
| 結果512KiB | ceil(512/96) = 6巡 |
| G1結果512KiB＋診断16KiB | ceil(528/96) = 6巡 |
| 結果512KiB＋診断4本各16KiB | ceil(576/96) = 6巡 |

G1の528KiBを6巡でコピーするには少なくとも88KiB/巡が必要である。今回の96KiBでは5巡各96KiBと最終48KiB、合計6巡でコピーが完了し公開可能となる。33巡という前報告の計算は旧16KiB枠のものであり、訂正する。

6巡という値はコピーの必要巡回数であり、投入から公開までの100ms達成を証明しない。待ち・入力コピー・復元・許可検査・計算・worker結果確保・起床・描画・先行完了等の費用も考慮する必要がある。96KiBのコピーを含む管理処理が各フレームの1msに収まるかは未測定であり、後続の受け入れ測定で確認する。今回の依頼では速度・時間の測定を行わない。

## 担当外のファイルを変更した箇所と理由

task_contextとtask_permissionsは、実worker文脈を申告なしで照会するための追加である。既存の取消し取得や許可語一覧は変更していない。task_ledgerは実キューのworker_failedを別理由として受領するための列挙追加だけを残した。registerと対応単体試験は1364へ戻した。

task_queueは原子的置換・観測・取得証跡と停止未確認中の投入受理のために変更した。対応する既存キュー試験の拒否期待も受理へ変更した。host専用試験はruntime_testにのみ登録し、core試験ルートへhostモジュールを持ち込んでいない。

## 試験と実行結果

検証結果は下表に記録する。実行はPowerShellから行い、キャッシュは作業ツリー内を使用する。初回runtime-testは既定グローバルキャッシュへのmanifest_create AccessDeniedで開始できなかったため、ZIG_GLOBAL_CACHE_DIRを作業ツリー内の.zig-cache/global-reviewへ設定して再実行した。

| コマンド | 結果 |
|---|---|
| zig build test --summary all | 終了0、23/23 steps成功。今回実行分1317成功・13 skip（core 1268成功・10 skip、runtime 49成功・3 skip）、hostはcachedである |
| zig build test -Ddebug=false --summary all -j2 | 終了0、23/23 steps成功。今回実行分1195成功・83 skip、host/runtimeはcachedである |
| zig build runtime-test --summary all -j2 | 終了0、5/5 steps成功。最終呼出しはcachedである。同じ最終ソースのruntimeは上記testで49成功・3 skipである |
| zig build -Dtarget=x86_64-linux --summary all | 終了0、13/13 steps成功。本体のクロスビルドであり実行していない |
| zig build -Dtarget=aarch64-macos --summary all -j2 | 終了0、11/11 steps成功。本体のクロスビルドであり実行していない |
| zig build runtime-check -Dtarget=x86_64-linux --summary all -j2 | 終了0、5/5 steps成功。最終結合試験のクロスコンパイルであり実行していない |
| zig build runtime-check -Dtarget=aarch64-macos --summary all -j2 | 終了0、5/5 steps成功。最終結合試験のクロスコンパイルであり実行していない |
| zig fmt --check（変更したZig全10ファイル） | 終了0、診断なしである |
| git diff --check | 終了0、空白エラーなしである。LF→CRLFの予告のみである |

Zigは0.17.1である。ログは.zig-cache/review-*.logに保持する。cachedの結果を新規実行件数へ加算していない。debug=falseは本プロジェクトの-Ddebugスイッチであり、Build Summaryの最適化表記はdebugである。独立したRelease最適化試験を行ったとは扱わない。

修正途中のruntime-testで、試験変数名の一括置換が別試験へ及んだことによる未宣言識別子のコンパイルエラーを検出した。該当する別試験の変数名を戻した後、上記の全体試験・runtime-test・クロスコンパイルが成功した。速度・時間の測定は行っていない。

## 未確認事項と利用者の判断が必要な事項

- LinuxとmacOSはクロスコンパイルまでであり、実行は未確認である。Linux実行は別機械のClaudeが担当する。
- 実ホストの全供給元・probe・共通Wake・OS待機・描画を結合した運転、公開Forth入口、task_jobの新規VM・Snapshot・転送・許可検査を組み合わせた全体受け入れは未実施である。
- 停止不能後のHost水準の回復は後続作業である。現在は旧キューに待ちを受け付け、期限切れへ進める。待ちを新キューへ移す機能は提供していない。
- 60Hz、管理1ms/フレーム、投入→公開100ms、要求→停止10ms、回収100ms、追加128MiBの実測達成は未確認である。
- 今回は既存決定へ戻す修正であり、追加の仕様判断を求める事項はない。回復経路の後続実装と、受け入れ測定で予算を満たさなかった場合の扱いは未完である。利用条件自体の変更が必要になればレモンの判断を要する。

コミット・ブランチ作成・タグ・push・tque変更・作業ツリー外への変更・速度や時間の測定は行っていない。

## 最終Git状態

HEADは83987a2（detached）のままである。8件の変更と3件の新規ファイルである。

```text
 M src/core/task_context.zig
 M src/core/task_ledger.zig
 M src/core/task_permissions.zig
 M src/core/task_queue.zig
 M src/core/task_schedule.zig
 M src/runtime_test.zig
 M src/tests/task_queue_test.zig
 M src/tests/task_schedule_test.zig
?? docs/TASK_CONTROL_IMPL_1387.md
?? src/core/task_schedule_host.zig
?? src/tests/task_schedule_host_test.zig
```

