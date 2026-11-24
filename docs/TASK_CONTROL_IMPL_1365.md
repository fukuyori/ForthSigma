# タスク1365：結果と診断の所有バッファ

更新日：2026-11-24。作成者：ロク。

## 変更ファイルと要点

今回のレビュー修正は `src/core/task_results.zig`、`src/tests/task_results_test.zig`、本書の3ファイルだけである。開始時から存在した他タスクの変更と未追跡ファイルは保持した。初回1365で追加済みの `src/forth_test.zig` の試験importは今回変更していない。

## 指摘の確認と設計上の選択

5点とも修正前ソースで確認し、妥当と判断した。誤りとして退けた指摘はない。根拠は `TASK_CONTROL_STATE_MACHINE.md` の終端・RESULT・寿命契約と `TASK_CONTROL_USAGE_CONDITIONS.md` 4節の予算である。

1. Writerのwriteが共有Budgetのreserve/releaseとallocatorを呼んでいた。`WorkerOutput.init`を追加し、所有ホストが投入前に16 KiBを予約・確保する方式へ変更した。writeは専有バッファへのコピー、使用量更新、失敗印だけを扱う。Budgetはホスト専用であり、内部ロックを持たないことをソースにも明記した。
2. 各writeで全量を再確保・コピーしていた。固定バッファの未使用部分へ追記する方式へ変更し、既存内容のコピーをなくした。速度・時間の測定は行っていない。
3. `Budget.release`のassertを明示条件によるpanicへ変更した。ReleaseFastでも減算前に下回りを検出する。内部所有権契約違反の扱いであり、公開エラー値ではない。
4. `Buffer.copyResult`は`transfer.resultBytes`による検証を一度だけ実施し、得たスライスをallocator.dupeでコピーする。割当失敗では予約を戻す。コピー完了までVMとStorageの排他保持が必要である。
5. 成功出力の`.writer_output`診断を廃止し、`Completion.output`に分離した。`finish`に呼出し側のsecondary引数を追加した。実行主診断がある場合のWriter失敗は専用の`writer_failure`に置き、secondaryの後始末診断を上書きしない。

`Buffer`は所有領域と予約先を保持する。Writerでは初期化済みスライス`bytes`と全確保領域`allocation`を区別する。未使用部分を公開せず、実際に保持する16 KiBを予算に数えるためである。空出力でも予約を保持する。finishは縮小・再割当てせず、領域と予約をCompletionへ移譲する。解放はホストがCompletion.deinitで行う。finish前に中止した場合はホストがWorkerOutput.deinitで解放する。

全Budget操作、Bufferの生成・破棄、WorkerOutput.init/finish/deinitは所有ホストスレッドで行う。ホストはjoinまたは同等の同期による排他的な返却後にfinish/deinitを呼ぶ。WriterはStateへ渡している間、アドレスを固定する。本部品のためにallocatorのスレッド安全性を要求しない。ホスト専用契約は文書によるもので、型によるスレッド識別は実装していない。

出力上限を超えた書込みは全体を拒否し、その後も無視する。失敗前の出力はoutputに保持する。Writer失敗だけなら主診断へ置き、実行主診断があればwriter_failureへ置く。成功帰還でWriter失敗があればfailedとし、cancelledはcancelledを保つ。secondaryは常に保持する。失敗・取消しでは部分結果を破棄する。成功出力だけでは診断を生成しない。

initの予算不足・割当失敗は投入前のエラーとして返し、予約を復旧する。旧writer_budget/writer_allocationは不要となり削除した。結果上限512 KiB、診断・Writer上限16 KiB、共通診断予算1 MiBは維持した。非消費query、宛先不足時の宛先不変、結果なしと0バイト結果の区別も維持した。所有型は値コピーして二重解放してはならず、allocatorとBudgetは所有領域より長く生存させる。

## 既存ファイルと通常経路

今回、既存ファイルへの追加変更はない。変更したZigソースは初回1365で追加した2ファイルだけである。通常実行ループ、State配置、src/forth.zig、task_transfer.zigは変更していない。通常経路の変化はなく、命令ごとの定期取消し確認も追加していない。公開Forth語、スタック効果、公開エラー番号は追加していない。

## 試験と実行結果

PowerShell、Zig 0.17.1で実行した。ZIG_GLOBAL_CACHE_DIRはworktree内の`.zig-global-cache`とした。

試験は9件である。結果境界・非消費取得・総量・部分結果破棄・VM結果コピーに加え、初期確保失敗時の予約復旧、投入前の予算不足、16 KiBの1バイトずつの出力、空・短い出力の予約寿命、所有権移譲、成功出力と診断の分離、実行原因・Writer失敗・後始末診断の併存、取消し優先を検査する。実スレッドによるWriter書込みとホスト側の同一Budget操作を併行させ、join後に出力を確認する。FailingAllocatorは初回確保後の追加割当てを失敗させる設定であり、write/finishが追加割当てをしないことを検査する。std.testing.allocatorで解放漏れを検査する。

| コマンド | 結果 |
|---|---|
| `zig build test --summary all` | 終了コード0、23/23ステップ成功。再実行対象1257 passed、10 skipped（1267 total） |
| `zig build test -Ddebug=false --summary all` | 終了コード0、23/23ステップ成功。再実行対象1184 passed、83 skipped（1267 total） |
| `zig fmt --check src/core/task_results.zig src/tests/task_results_test.zig` | 終了コード0 |
| `git diff --check` | 終了コード0 |

両buildの他対象にはキャッシュ再利用がある。追加・更新した9試験はcore試験に含まれ、失敗・メモリリークの報告はなかった。通常構成は追加2試験の反映後に再実行した最終結果である。

## 未確認事項と利用者判断

実スケジューラ、台帳・通知・参照管理との結合、全経路でホスト専用契約が守られることは本タスク単独では未確認である。Budget下回りpanicの異常終了試験は追加しておらず、明示条件とpanicをソースで確認した。代表的な語群除外構成は今回は実行していない。速度・時間、OSメモリ量の測定は行っていない。

追加の利用者判断を要する事項はない。方式の確定・公開、VM再利用、公開診断形式・Forth語は引き続き保留である。コミット、ブランチ、タグ、push、tque変更、パッケージ作成、作業ツリー外への変更は行っていない。

## 最終Git状態

開始時からの差分を含む `git status --short` 全件は次のとおりである。今回の修正対象は冒頭の3ファイルである。

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
?? docs/TASK_CONTROL_IMPL_1365.md
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
?? src/core/task_results.zig
?? src/core/task_snapshot.zig
?? src/core/task_transfer.zig
?? src/tests/task_control_1384_test.zig
?? src/tests/task_control_w1_test.zig
?? src/tests/task_permissions_test.zig
?? src/tests/task_results_test.zig
?? src/tests/task_snapshot_test.zig
?? src/tests/task_transfer_test.zig
```

