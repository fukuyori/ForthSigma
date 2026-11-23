# タスク1361：入力・結果の転送（レビュー修正）

## 変更ファイルと範囲

今回変更したのは `src/core/task_transfer.zig`、`src/tests/task_transfer_test.zig`、本報告書である。公開Forth語・公開スタック効果・公開エラー番号は追加していない。既存製品ソース、State配置、命令実行ループは変更していない。通常経路の変更箇所はなく、命令ごとの定期取消し確認も追加していない。

前回実装の `src/forth_test.zig` のimport追加は試験登録用であり、今回の追加変更はない。開始時からある他の文書差分は編集していない。コミット・ブランチ・タグ・push・tque変更・作業ツリー外の変更・パッケージ作成・速度や時間の測定は行っていない。

## 設計上の選択とレビュー対応

指摘7点をソースと `CORE_EXTENSION_WORKER_STATE_AUDIT.md` で確認し、すべて採用した。誤りと判断して退けた指摘はない。

1. `checkFresh` にdefining、pending、postponing、quote_closing、noname_next、local_count、locals_frame_size、locals_top、assert_depth、backtrace_suppression、source_kind/source_line、wrap_guard、abort_message、sh_get_result、block_storageをActiveVmとして追加した。input_file/output_errorはCapturingVm、lint/line_trace/cell_watch_count/watched_countはCountedVmに追加した。locals_topはlocalsBaseとの一致、ポインター類はnull、sourceはterminalかつ空を要求する。block_storageは全メタデータを初期値と比較する。無効な深さの先の未初期化配列は読まない。辞書構築後の非アクティブな履歴値までState.initとの完全一致を要求するものではない。
2. `default_input_limit` は2 MiB、`default_result_limit` は512 KiBであり、Limitsの既定値と最大値に使用する。両APIはLimits.validateで設定自体を検査し、超過をInvalidLimitsで拒否する。小さい設定と0は許す。転送総和16 MiBは `transfer_total_limit` として定義した。1364・1366の管理側がコピー・割当前に同時保持バイトを共有台帳へ予約し、投入失敗・取消し・回収・解放を含む全経路で解放する接点をAPIコメントに記した。同時に存在するコピーも別々に計上する。本モジュールは共有台帳を持たない。
3. 入力開始位置をHERE以上の8バイト境界、更新後HEREを入力終端以上の8バイト境界とする。空入力でも開始位置の整列余白を確保する。データ領域の残量と前後の余白を加算前に検査し、整列終端の範囲超過・オーバーフローを防ぐ。全検査は書込み前に終える。
4. @memmove後にコピー範囲[start, end)についてdiscardRange(start, end, .data, false)を呼ぶ。重なるメモリ登録を除去し、対象への参照を失効させる。
5. resultBytesは上限設定とreturn_depth、loop_depth、compiling、halted、local_countを検査し、停止状態違反を内部エラーResultVmNotStoppedとする。その後に既存のdata/float深さ、長さ、加算オーバーフロー、領域境界、結果上限を検査する。data_depthは結果の2セルを許す。
6. タスクVMはStorage.allocate(allocator, false, sizes)とState.initで生成する。already_zero=trueを使えるのはゼロ保証付きallocatorだけである。Snapshot復元もdataLimitまでの初期化を維持する必要がある。Stateに割当履歴がなく、checkFreshではこの契約を検査できない。全領域のゼロ検査はSnapshotの有効データも拒否するため加えていない。試験はfalseで確保する。
7. 試験の一時的なdata_stack/memory短縮にdeferでの復元を追加した。期待失敗時も元の割当を解放する。

入力は借用であり、失敗時も所有権を消費しない。投入失敗時は統合側がVMを破棄する。resultBytesは停止後の借用ビュー、copyResultは呼出し側所有の複製である。結果はデータ領域だけを許し、HEREより先でもdataLimitまでを許す。コピー完了までVMを排他保持し、結果は同じallocatorで解放する。worker論理メモリを結果allocatorのbacking storeとしてはならない。

## 試験と実行結果

WindowsのPowerShell、Zig 0.17.1、worktree内のグローバルキャッシュで実行した。追加試験を含め11試験であり、前提状態、上限設定、停止状態、奇数HEREと入力の整列、アドレス登録除去、領域境界、結果の所有、割当失敗を扱う。

初回実行では整列後HEREとdiscardRangeの登録除去に対する試験の期待値が誤っており失敗した。ソースの動作を確認して期待値を修正し、最終ソースで再実行した。最終結果は以下のとおりである。

| コマンド | 最終結果 |
|---|---|
| `zig build test --summary all` | 終了0、23/23 steps成功。今回実行core 1205 pass・10 skip、他runはcachedである。 |
| `zig build test -Ddebug=false --summary all` | 終了0、23/23 steps成功。今回実行core 1133 pass・82 skip、他runはcachedである。 |
| 下記の語群除外構成 | 終了0、13/13 steps成功。今回実行core 621 pass・568 skip、他runはcachedである。 |
| `zig fmt --check src/core/task_transfer.zig src/tests/task_transfer_test.zig src/forth_test.zig` | 終了0、診断なしである。 |
| `git diff --check` | 終了0。既存追跡ファイルの改行警告のみである。未追跡ファイルは対象外である。 |

語群除外構成は `zig build test -Ddebug=false -Dfloat=false -Dfiles=false -Dhelp=false -Dtools=false -Dimage=false -Dgraphics=false -Daudio=false -Dextension=false --summary all` である。cachedのrunを今回の新規実行件数へ加算していない。

## 未確認事項

総和16 MiBの共有台帳との結合、キュー投入失敗との結合、実スレッドの同期、取消し・停止競合、Snapshot失効、許可語検査、Writer隔離・回収は本タスクでは実証していない。新規VMの前提検査は割当履歴や任意Forthコードの安全境界を証明するものではない。VM再利用は許可しない。

## 利用者の判断が必要な事項

入力2 MiB・結果512 KiB・転送総和16 MiBは決定済みであり、保留ではない。方式の確定・公開、公開Forth語・公開エラー値は保留である。今回の修正で新たな判断を要する事項はない。

## 最終Git状態

HEADは35523f6のdetached状態である。以下は既存差分を含む `git status --short` の出力である。

```text
 M docs/CORE_EXTENSION_DESIGN_DECISIONS.md
 M docs/CORE_EXTENSION_DETAILED_DESIGN.md
 M docs/CORE_EXTENSION_PLAN.md
 M docs/README.ja.md
 M docs/README.md
 M docs/TASK_CONTROL_PLAN.md
 M docs/WINDOWS_NATIVE_DISPLAY_VALIDATION.md
 M src/forth_test.zig
?? docs/TASK_CONTROL_ACCEPTANCE.md
?? docs/TASK_CONTROL_AUDIT_ALLOWED_SET.md
?? docs/TASK_CONTROL_AUDIT_REENTRY.md
?? docs/TASK_CONTROL_AUDIT_SHARED_STATE.md
?? docs/TASK_CONTROL_CONFIG_MATRIX.md
?? docs/TASK_CONTROL_DETAILED_PLAN.md
?? docs/TASK_CONTROL_IMPL_1361.md
?? docs/TASK_CONTROL_METHOD_COMPARISON.md
?? docs/TASK_CONTROL_METHOD_DECISION.md
?? docs/TASK_CONTROL_PROTO_1352.md
?? docs/TASK_CONTROL_PROTO_1353.md
?? docs/TASK_CONTROL_PROTO_1354.md
?? docs/TASK_CONTROL_PROTO_1355.md
?? docs/TASK_CONTROL_PROTO_1356.md
?? docs/TASK_CONTROL_USAGE_CONDITIONS.md
?? src/core/task_transfer.zig
?? src/tests/task_transfer_test.zig
```

