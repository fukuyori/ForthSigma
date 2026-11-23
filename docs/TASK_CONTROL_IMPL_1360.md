# タスク制御05-C 許可検査の実装（1360）

## 範囲と変更ファイル

対象は1048配下1360の内部許可検査と、そのレビュー修正である。公開Forth語・スタック効果・公開エラー番号を追加していない。通常経路の命令ごとの取消し確認、速度・時間の測定、git commit・branch・tag・push、tque変更は行っていない。

- src/core/task_permissions.zig：到達先走査・許可表、検査器の受渡し、実行前状態検査、保護範囲の優先拒否である。
- src/tests/task_permissions_test.zig：許可・拒否・偽装・循環・実行解釈・メモリ契約の計12試験である。
- src/forth_test.zig：前回実装の新規試験importが1行ある。今回の修正では触れていない。
- 本書：実装・レビュー対応と検証の記録である。

レビュー修正開始時から設計文書7件とsrc/forth_test.zigの追跡変更、および本書・実装・試験を含む未追跡ファイル群があった。今回編集したのはtask_permissions.zig、task_permissions_test.zig、本書の3ファイルである。その他の既存変更は保持した。

## 設計上の選択と理由

根拠はTASK_CONTROL_AUDIT_ALLOWED_SET.md、TASK_CONTROL_DETAILED_PLAN.md、CORE_EXTENSION_DESIGN_DECISIONS.mdの2026-11-24利用者判断、TASK_CONTROL_METHOD_DECISION.md 8節、1353・1354の試作報告である。第三者コード・試作コードの複製は行っていない。

inspectは復元・specialize・inline後の専有VMを検査する内部APIであり、公開THROW値へ変換しない。検査後から実行終了までコード・辞書・設定を変更しない契約である。検査結果を別VMや別版に転用する許可証とはしない。Snapshot取得・失効・寿命管理は対象外である。

語数に比例する訪問配列と作業リストをallocatorから確保する。コロン再帰は再訪せず、ホストの再帰呼出しを用いない。synonym循環は独立した内部エラーとし、成功・失敗のいずれも作業配列を解放する。

本体は分岐の両側と到達不能スロットを含めて保守的に全走査する。分岐先は同じ本体の開始から終端までとする。DO系、動的実行、例外、PAD、ローカルOp、辞書変更、I/O、未掲載builtinは既定拒否である。BEGIN系のbranch/branch_zeroは許可する。

call_builtinはVM同様にbuiltin_count内のIDを要求し、words[id].builtinを検査する。kindをbuiltinへ限定しない。call_colonは通常形式とpacked inline guardともcolonを要求する。has_doesの語を拒否し、guardの元ID・展開範囲・深さを検査する。inlineの元本体に再解決せず、実際に実行する後続Opを検査する。primitiveと直接builtinも同じ許可表へ正規化し、除外されたbuiltinは拒否する。

通常のアドレス返却は参照権限の付与ではない。value/fvalue/two_value/string_value/two_constant等の暗黙読取り語は最小集合外として拒否する。

## レビュー対応と1384・1373への接点

1. boolの自己申告を廃止し、Options.memory_gate: ?*const MemoryGateを既定nullとした。条件付きメモリ語と文字列OpはnullならMemoryChecksRequiredで拒否する。必要な同一ポインタをRequirements.memory_gateで返し、max_native_bytesも返す。メモリ操作が不要なら返却ポインタはnullである。
2. MemoryGateはcontextと必須のcheck関数ポインタを持つ。Accessは論理アドレス・長さ・書込みの組である。permitsは総native処理量の上限を照合し、複数範囲を一括してcheckへ渡す。falseなら操作全体を読書き前に拒否する。
3. workerは返却された同一gateを全論理アクセスへ接続しなければ実行を拒否する。primitive、文字列の暗黙読取り、MOVEの両範囲、COMPARE/SEARCHの全入力、COUNT/PLACEのヘッダーも対象とする。gate/contextはVM専用で実行終了まで生存させる。未検査の通常dispatchへ戻してはならない。接続の実装は1384・1373で行う。本検査器を普通のVMへ渡すだけでは、そのVMの安全性を保証しない。
4. Region/checkAccessは負値・長さ上限・範囲越え・読取り専用への書込みを拒否する。system/block_buffer/heap_header/local_frameとの交差はpayload包含許可より優先して拒否する。許可の順序に依存しない。半開区間を端点加算なしで比較しoverflowを避ける。長さ0は空区間であるが、許可payload内の位置であることは引き続き要求する。領域分類・ヒープ生存・構造検証は後続実装が担当する。
5. runOperationsLoopのhalted早期帰還とexecuteOperationsのcounted選択条件をソースで確認した。inspectはhalted・compiling・defining・pending、return/loop/catch/frame/call/control/interpret_loop/quoteの深さ、output_error残存をDirtyVmで拒否する。step_limit・tracing・profile・keep_counting・in_counted・stepper・watchをCountedModeで拒否する。debug構成ではexecution.depthも拒否する。stepper/watch単独が常にcountedを選ぶという意味ではなく、禁止設定として保守的に拒否した。debug=falseでも存在する設定は同じく拒否する。データ・浮動小数点の入力スタックは空を要求しない。
6. 1361のcheckFreshは新規確保・初期化と復元前の健全性を担当し、1360のinspectは復元・最適化後、実行直前の実行可否を担当する。重複するhalted・スタック深さの検査もinspectから省かない。1361の実装自体は本修正の対象外であり、その全State初期化の成立を本試験では保証しない。
7. .callから実際のCREATE…DOES>の語への到達、value/fvalue/two_constant拒否とfield/constant/variable許可、S"/C"、end超過分岐、壊れたinline guard（非colon・元語has_does・範囲超過・深さ0）、範囲外execution_token、builtin経由FAST-THROW・表明系の拒否を表駆動で追加した。文字列は実際にコンパイルした本体も検査する。ABORT"はbuiltin enumではなくtext_inputがabort_stringを生成する構文であるため、生成Opとコンパイル済み本体の拒否を試験した。
8. +のkind/builtinを保存し、deferで元のWordを戻すようにした。

指摘の趣旨を誤りと判断して見送った項目はない。ABORT"だけは実際のdispatchに合わせて試験した。

max_native_bytesの64 KiBは設定可能な案であり、公開上限の確定ではない。単一範囲の長さをnative全体の処理量の代用にしない。Snapshot・新規Storage.allocate＋State.init・動的再入の防壁・検査後の設定不変性はworker構築側の責務である。

## 既存ファイルと通常経路への影響

前回実装のsrc/forth_test.zigのimport 1行は試験を登録するために必要である。今回の修正で既存ファイルは変更していない。src/forth.zig、State配置、実行入口・ループ・復帰、primitive、memoryAddressは無変更である。通常経路の変更箇所はない。

## 試験と実行結果

PowerShellからZIG_GLOBAL_CACHE_DIRをworktree内.zig-global-cacheに指定して実行した。作業ツリー外の設定変更は行っていない。以下はレビュー修正後の最終ソースの結果であり、前回の結果を置き換える。

| 検証 | 結果 |
|---|---|
| zig build test -j2 --summary all | 終了コード0、23/23 steps成功。core 1206 pass / 10 skip（1216件） |
| zig build test -Ddebug=false -j2 --summary all | 終了コード0、23/23 steps成功。core 1134 pass / 82 skip（1216件） |
| zig build test -Ddebug=false -Dfloat=false -Dfiles=false -Dimage=false -Dextension=false -Dgraphics=false -Daudio=false -j2 --summary all | 終了コード0、13/13 steps成功。core 630 pass / 560 skip（1190件） |
| zig fmt --check src/core/task_permissions.zig src/tests/task_permissions_test.zig src/forth_test.zig | 終了コード0、診断なし |
| git diff --check | 終了コード0、CRLF変換予告のみ |

host/runtime等は各構成ともcachedの成功である。計12試験は構成による試験単位のスキップを設けていない。execution.depthだけはdebug時に検査する。MemoryGateの同一ポインタ返却、callbackへの複数範囲・context・総処理量の受渡し、拒否も検査する。未追跡ファイルはgit diff --checkの対象外であるため、新規Zigはfmt、本文書は末尾空白を別検査する。

## 未確認事項と利用者判断

workerへの実接続、Snapshot復元から実行までの不変性と版寿命、実行時メモリ分類と全アクセスの防壁、取消し・並行実行・ホスト資源隔離、他OS実機は未確認である。inspectとMemoryGate単独で独立VM方式の採用・公開や全受入条件の成立を示すものではない。

64 KiB/回の値、メモリ語の実許可への切替時期、保守的に拒否した暗黙読取り語・ローカル語等の将来拡張は利用者判断または後続監査が必要である。本修正を進めるための追加判断は不要である。

## 最終git状態

開始時からの既存変更を含むgit status --shortの全文は以下である。

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
?? docs/TASK_CONTROL_IMPL_1360.md
?? docs/TASK_CONTROL_METHOD_COMPARISON.md
?? docs/TASK_CONTROL_METHOD_DECISION.md
?? docs/TASK_CONTROL_PROTO_1352.md
?? docs/TASK_CONTROL_PROTO_1353.md
?? docs/TASK_CONTROL_PROTO_1354.md
?? docs/TASK_CONTROL_PROTO_1355.md
?? docs/TASK_CONTROL_PROTO_1356.md
?? docs/TASK_CONTROL_USAGE_CONDITIONS.md
?? src/core/task_permissions.zig
?? src/tests/task_permissions_test.zig
```

