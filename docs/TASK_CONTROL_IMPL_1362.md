# タスク1362：1件の仕事のVM寿命

作成日：2026-11-24。対象：1048配下の1362。内部APIと同期試験の実装報告である。

## 変更ファイルと要点

| ファイル | 内容 |
|---|---|
| `src/core/task_job.zig`（新規） | `run`で投入参照を引き取り、新規VMの復元、入口解決、許可検査、入力コピー、worker実行、結果検査・所有コピー、VM・投入参照の解放を行う |
| `src/tests/task_job_test.zig`（新規） | 終了経路ごとの割当失敗注入、参照数の復帰、連続実行の隔離、最後のSnapshot解放後の結果保持を検査する |
| `src/forth_test.zig` | 新規試験を登録する1行だけを追加した。既存の他タスクの登録行は保持した |
| `docs/TASK_CONTROL_IMPL_1362.md`（新規） | 本報告である |

開始時から多数の追跡済み差分と未追跡ファイルが存在した。本タスクの変更は上記に限定する。通常実行経路の変更はゼロであり、命令ごとの取消し確認、State配置、既存の実行器・通常入口・回復処理は変更していない。公開Forth語・スタック効果・公開エラー値を追加・確定していない。commit・branch・tag・push・tque変更、速度・時間測定、作業ツリー外の変更は行っていない。

## 設計上の選択と所有権

根拠は`CORE_EXTENSION_DESIGN_DECISIONS.md`の2026-11-24決定、`TASK_CONTROL_METHOD_DECISION.md`8節、詳細計画、監査文書、PROTO_1352〜1356、および既存1359〜1361・1384の内部APIである。終端の扱いは`TASK_CONTROL_STATE_MACHINE.md`に合わせ、実行後に取消し要求を再確認して成功を取消しに置き換える処理は追加していない。待機登録・利用条件の期限・完了公開を、この同期関数で実装済みとはしない。

`run`は`Snapshot.admit`で得た`Admission`の所有権を全終了経路で消費する。呼出し側は再使用・再解放してはならない。投入時のmain所有者による直列化と失効検査は1359に従い、投入済み旧版はその参照を使う。関数内で新規投入をやり直さない。`FreshVm.create`が別の参照を取り、`Storage.allocate(false)`と`State.init`を経て復元する。復元Planは同API内、inspectのmarks/pendingは1360内で確保・解放される。失敗時も既存APIのerrdeferと本関数のdeferを組み合わせて解放する。

入力は呼出し中だけ借用し、1361の`prepareInput`でVM所有のデータ領域へコピーする。独立した二重の入力バッファは作らない。入力コピーはStorageの解放で消え、呼出し側の入力は消費しない。入口名とCancellationも借用であり、VMへホストcallbackを設定しない。成功結果は`copyResult`で別の所有バッファとなり、VM・Snapshotを破棄した後に返る。呼出し側が同じallocatorで解放する。失敗・取消しは結果バッファを返さない。停止せず帰還しない処理について、タイムアウトでVMを強制解放する機構はない。

## メモリ操作の制限と1373への引継ぎ

現状の1362は、まだ実際に使える仕事の経路ではない。`task_permissions.zig`は、`@ ! C@ C! MOVE CMOVE FILL ERASE COUNT COMPARE SEARCH SCAN SKIP -TRAILING PLACE`などのメモリ操作と文字列リテラルにMemoryGateを要求し、`task_job.run`は検査器を必要とする入口をすべて拒否する。そのため、入力のバイトを読む入口、結果を書き込む入口、文字列リテラルを返す入口は1373が終わるまで1つも実行できない。現状で通るのは、`ECHO`や`/STRING`など、メモリアクセスを伴わず`(addr len)`をスタック上で扱う入口に限られる。

追加指示に従い、MemoryGateを必要とする入口は実行前に`MemoryChecksRequired`で拒否する。inspectには解析専用の常時拒否gateを渡し、返されたRequirementsの`memory_gate != null`を確認して拒否する。このgateはVMへ接続せず、実行許可として扱わない。直接のC@と、それを呼ぶ間接入口も拒否試験に含める。メモリ検査器が必要な経路を未検査で実行するfallbackはない。

1373では、実際のVM領域を示すMemoryGateをrunAsWorkerへ接続し、primitive・文字列等を含むすべての論理アクセスの検査とnative量上限を保証した後で、この制限の解除を扱う。本タスクの結果コピーは1361による停止後の範囲検査を使う。これはworker実行中のメモリ検査の代替ではない。

## 試験と実行結果

PowerShell、Zig 0.17.1で実行する。`ZIG_GLOBAL_CACHE_DIR`はworktree内の`.zig-global-cache`に指定する。ビルドツールの自動時間表示は測定資料に使わない。

試験ケースは通常成功・空結果・有限BEGIN系の成功、入力上限、結果上限、結果スタック違反、負の結果長、PAD拒否、直接／間接メモリ操作拒否、未定義入口、ゼロ除算、要求済みCancellationである。各ケースを`std.testing.allocator`で直接実行し、続いて`checkAllAllocationFailures`で仕事内のすべての割当位置へ失敗を注入する。エラーを期待するケースでもOutOfMemoryを握りつぶさず注入器へ返す。各帰還後にSnapshot参照が呼出し前と同じであることを検査する。最後のSnapshot参照を仕事へ渡した成功試験ではlive_versions=0を確認し、その後も結果を読めることを検査する。

連続試験は結果長を変える仕事、return/data stackを使って失敗する仕事、通常仕事の順に実行する。前の結果が保持され、次の結果が独立し、メインのスタックが空であることを確認する。毎回別Storage＋State.initであり、前のVMを再利用しない。

この試験だけでは、変数へ書き込んだ値を次の仕事へ引き継がないことを実行で確認できていない。現状の隔離は毎回新規Storage＋State.initを使う構造で保証している。変数への書込みを含む分離試験は、実行中のメモリ検査を接続する1373で加える。

## レビュー指摘への修正（2026-11-24）

4点ともソースで確認し、反映した。`run`は、上限検証 → 新規VM作成・復元 → checkFresh → 名前解決 → inspect → 入力コピー → worker実行 → 結果検査・コピーの順とした。上限はVMに依存しないため復元前に検証し、checkFreshはFreshVm.create直後のdefer登録に続けて実行する。prepareInput内の再検証は既存APIの契約として保持した。通常実行経路の変更はない。既定入力上限を1超えるInvalidLimitsのケースを追加し、既存の参照解放・割当失敗注入の枠内でも検査する。今回変更したファイルは`src/core/task_job.zig`、`src/tests/task_job_test.zig`、本報告書の3点である。指摘を誤りと判断した点はない。

修正後にPowerShellから再実行した結果、`zig build test --summary all`は終了0（23/23 steps、1250 pass・10 skip）、`zig build test -Ddebug=false --summary all`は終了0（23/23 steps、1177 pass・83 skip）であった。いずれもcore以外の試験はcachedの成功である。`zig fmt --check src/core/task_job.zig src/tests/task_job_test.zig`と`git diff --check`も終了0であった。後者には既存の`src/forth_test.zig`についてLFからCRLFへの変換警告が出た。語群除外の追加構成は今回も未実行である。修正後の`git status --short`を再確認し、末尾掲載の状態と一致した。

最終実行結果とGit状態を末尾に記録した。

## 未確認事項と利用者判断

実スレッド、キュー・台帳、共有転送量16 MiBの予約・解放、完了データの封印・release公開・acquire受領、待機通知、実行途中に別スレッドから要求する取消し、停止・回収期限、実機の隔離、性能条件は本タスクでは未確認である。1364・1366・1373以降の結合検証事項である。std.testing.allocatorでの成功は本番allocatorの並行契約の証明ではない。

VM再利用（全初期化による再利用を含む）は保留である。再開には利用者判断に加え、1354の残留表（非アクティブstack/frame/catch、random、source、block、Tcl、gfx等）と`CORE_EXTENSION_WORKER_STATE_AUDIT.md`のState・Writer・到達先の全項目を再確認し、所有資源の回収を初期化より先に行う契約、借用参照・callbackの遮断、全初期化、成功・失敗・取消し後の隔離と回収を検証する必要がある。restore／restoreFreshだけで全残留が消えるとは扱わない。

本タスクの範囲で新たに利用者判断を要する事項はない。方式の確定・公開、公開語・エラー値、VM再利用とメモリ許可拡張は保留事項のままである。

| コマンド | 結果 |
|---|---|
| `zig build test --summary all` | 最終版は終了0、23/23 steps、core 1250 pass/10 skip。他の試験はcachedの成功である |
| `zig build test -Ddebug=false --summary all`（最終版） | 終了0、23/23 steps、core 1177 pass/83 skip。他の試験はcachedの成功である |
| `zig fmt --check src/core/task_job.zig src/tests/task_job_test.zig src/forth_test.zig` | 終了0、診断なし |
| `git diff --check` | 終了0。未追跡ファイルは対象外であり、新規Zigは上記fmtで確認した |

新規2試験はdebugの条件によるskipを置いていない。語群除外の追加構成は未実行である。`forth_test.zig`はfmtによる改行正規化も行ったが、内容差分は試験登録1行だけである。


## 最終Git状態

HEADは35523f6、detached HEADである。開始時からの差分を含むgit status --shortの出力である。

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
?? docs/TASK_CONTROL_IMPL_1362.md
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
?? src/core/task_job.zig
?? src/core/task_permissions.zig
?? src/core/task_policy.zig
?? src/core/task_snapshot.zig
?? src/core/task_transfer.zig
?? src/tests/task_control_1384_test.zig
?? src/tests/task_control_w1_test.zig
?? src/tests/task_job_test.zig
?? src/tests/task_permissions_test.zig
?? src/tests/task_snapshot_test.zig
?? src/tests/task_transfer_test.zig
```
