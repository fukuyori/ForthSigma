# ForthワーカーのState隔離監査表

更新日：2026-11-24。対象：1048配下1358（タスク制御05-A State全フィールドの再帰監査）。
状態：現作業ツリーの静的監査である。方式採用・公開・実装・並行安全性の実証を完了したという意味ではない。本監査の書込みは本書と指摘6に対応する受け入れ条件の参照行だけであり、src/・tque・Gitを変更せず、ビルド・試験・測定を行っていない。

## 判断の基準と読み方

利用者判断は `docs/TASK_CONTROL_METHOD_DECISION.md:164` の8節と `docs/CORE_EXTENSION_DESIGN_DECISIONS.md:37` を正本とする。初期版はタスクごとに新規Storage.allocate＋State.initを基準とし、プール・省略初期化は保留する。動的実行（EXECUTE・.execute・.local_execute・DEFER・DOES>）、例外（CATCH/THROW）、workerのcounted（652予算・trace・profile・step）、PAD、境界未検証のDO系を許可せず、BEGIN系を許可する決定である。入力・UI・ファイル・音・コンパイル・辞書変更・同期待機・SYSTEMも初期許可に含めない（`docs/TASK_CONTROL_DETAILED_PLAN.md:135`、`docs/CORE_EXTENSION_DETAILED_DESIGN.md:802`）。

State直下176項目とWriter73項目を再列挙した。gfx_clip・gfx_displays・gfx_window_fit・gfx_window_smooth・gfx_window_keep_openを含む。件数は照合時点の結果であり、完了条件ではない（`docs/TASK_CONTROL_DETAILED_PLAN.md:64`）。既存の3列表を維持し、各条件欄へ型・再帰参照・init・復元・結論を記す。追加・削除・型変更の照合手順は付録に残す。

| 記号 | 扱い | 条件 |
|---|---|---|
| V | ホストポインター・sliceなし | optional・配列・構造体・union内部まで値だけである。Cell中の論理アドレス・xt・ID等の意味は別に検査する。任意バイト列の安全性を保証する記号ではない |
| P | ポインター・sliceあり | メインからの借用とStateの値コピーを禁止する。新規VMまたは専用contextへ結び付ける |
| H | 値で表すホスト参照あり | ファイルID・表示装置ID・音pool位置などは整数でも継承しない |
| O | ワーカー専有で条件付き | 同じState/Storageを並行操作しない。Snapshotは公開後不変で寿命を保持、Planは復元ごとに専有する。停止・結果コピー・join後に解放する。同期・寿命の実証は未確認である |
| X | ワーカーで使わない | 新規init値を基準にし、機能の語と展開後Opを拒否する。callbackのnullだけを拒否の根拠にしない。将来解除は機能ごとに別判断である |
| R0 | 成功時復元で保持 | applyと下表の呼出し先に当該フィールドの再初期化がない。新規VMならinit由来、使用済みVMなら残留し得る。失敗経路の全状態不変を意味しない |

State.initは宣言既定値を適用し、writer・sizes・Storageのslice・locals_topを指定する。続いてutimeがあればrandom_stateを設定し、論理メモリのシステム値・検索順とbuiltinを設定する（`src/forth.zig:483`〜`src/forth.zig:522`、`src/forth.zig:971`〜`src/forth.zig:1008`）。表の「宣言」はこの初期値である。undefinedは有効要素の初期化済みを意味せず、件数・深さ・kindで読取り範囲を制限する必要がある。

restoreとrestoreFreshはPCM所有中を拒否し、preflight成功後に共通applyへ進む。違いはmemory_is_freshによる論理メモリ消去の有無だけであり、State全体のinitではない（`src/core/image_restore.zig:12`、`src/core/image_restore.zig:20`、`src/core/image_restore.zig:25`）。以下の復元欄は成功時applyの分類である。R0の共通根拠は `src/core/image_restore.zig:25`〜`src/core/image_restore.zig:111` と再帰型表・後始末表の呼出し先である。

スナップショットは明示取得した辞書と保存対象データを検査・再配置して再構成する設計である。実行中のスタック・継続・入力・ホスト資源は複製しない。変数や値のワーカーからの変更はメインへ返らず、結果として明示したコピーだけを返す（`docs/CORE_EXTENSION_DETAILED_DESIGN.md:806`）。

## フィールド別の方針

| フィールド | 扱い | 条件 |
|---|---|---|
| `writer` | 新規VM・専有（O） | 型 `Writer`。再帰：P：Writer→context・関数・Ops・Clock（W表）。init：専用Writer引数を設定。復元：R0（共通applyと呼出し先）。結論：O。W表の専用構成。メインのcontext・操作口を共有してはならない。宣言 `src/forth.zig:203` |
| `sizes` | 新規VM・専有（O） | 型 `Sizes`。再帰：V：Sizes（T01）。init：given.sizesを設定。復元：R0（共通applyと呼出し先）。結論：O。自VM内だけで使用し、メインと共有してはならない。宣言 `src/forth.zig:204` |
| `memory` | 新規VM・専有（O） | 型 `[]u8`。再帰：P：VM論理メモリslice。内容中の論理参照は検査・再配置する。init：given.memoryを設定。復元：保存範囲・heapをコピー／再配置。restoreはblock buffer以外をゼロ化、Freshは消去省略（src/core/image_restore.zig:50〜74）。結論：O。自VM内だけで使用し、メインと共有してはならない。宣言 `src/forth.zig:205` |
| `words` | 新規VMから検査・再構成（O） | 型 `[max_words]Word`。再帰：V：Word/Op固定配列。Cellの論理参照あり（T02）。init：宣言既定値の適用後installBuiltinsで有効builtin・名前・索引を構築。復元：非builtin有効範囲をコピーしvalueを再配置。builtin・未使用末尾を全消去しない（src/core/image_restore.zig:43〜47、:72〜74）。結論：O。明示Snapshotから再構成し、復元後の許可・領域検査を要する。メインと共有してはならない。宣言 `src/forth.zig:206` |
| `word_count` | 新規VMから検査・再構成（O） | 型 `u16`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言既定値の適用後installBuiltinsで有効builtin・名前・索引を構築。復元：画像／Planから設定（src/core/image_restore.zig:76〜79）。結論：O。明示Snapshotから再構成し、復元後の許可・領域検査を要する。メインと共有してはならない。宣言 `src/forth.zig:207` |
| `name_heads` | 新規VMから検査・再構成（O） | 型 `[wordlists.name_buckets]u16`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言既定値の適用後installBuiltinsで有効builtin・名前・索引を構築。復元：有効語索引を再構成。name_next全域の消去ではない（src/core/wordlists.zig:88）。結論：O。明示Snapshotから再構成し、復元後の許可・領域検査を要する。メインと共有してはならない。宣言 `src/forth.zig:210` |
| `name_next` | 新規VMから検査・再構成（O） | 型 `[max_words]u16`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言既定値の適用後installBuiltinsで有効builtin・名前・索引を構築。復元：有効語索引を再構成。name_next全域の消去ではない（src/core/wordlists.zig:88）。結論：O。明示Snapshotから再構成し、復元後の許可・領域検査を要する。メインと共有してはならない。宣言 `src/forth.zig:211` |
| `builtin_count` | 新規VM・専有（O） | 型 `u16`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言既定値の適用後installBuiltinsで有効builtin・名前・索引を構築。復元：R0（共通applyと呼出し先）。結論：O。自VM内だけで使用し、メインと共有してはならない。宣言 `src/forth.zig:212` |
| `code` | 新規VMから検査・再構成（O） | 型 `[max_code]Op`。再帰：V：Word/Op固定配列。Cellの論理参照あり（T02）。init：宣言 `undefined`。復元：有効範囲コピー後specialize・inline復元。未使用末尾は消去しない（src/core/image_restore.zig:48、:86〜87）。結論：O。明示Snapshotから再構成し、復元後の許可・領域検査を要する。メインと共有してはならない。宣言 `src/forth.zig:213` |
| `code_count` | 新規VMから検査・再構成（O） | 型 `u16`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `0`。復元：画像／Planから設定（src/core/image_restore.zig:76〜79）。結論：O。明示Snapshotから再構成し、復元後の許可・領域検査を要する。メインと共有してはならない。宣言 `src/forth.zig:214` |
| `names` | 新規VMから検査・再構成（O） | 型 `[names_capacity]u8`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言既定値の適用後installBuiltinsで有効builtin・名前・索引を構築。復元：own_names以降の有効範囲コピー、未使用末尾は保持（src/core/image_restore.zig:49）。結論：O。明示Snapshotから再構成し、復元後の許可・領域検査を要する。メインと共有してはならない。宣言 `src/forth.zig:216` |
| `names_used` | 新規VMから検査・再構成（O） | 型 `u32`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言既定値の適用後installBuiltinsで有効builtin・名前・索引を構築。復元：画像／Planから設定（src/core/image_restore.zig:76〜79）。結論：O。明示Snapshotから再構成し、復元後の許可・領域検査を要する。メインと共有してはならない。宣言 `src/forth.zig:217` |
| `data_stack` | 新規VM・専有（O） | 型 `[]Cell`。再帰：P：Storageの数値slice。Cellは論理アドレス・xtを表し得る。init：given.data_stackを設定。別確保先の全要素をState.initで消去はしない。復元：slice先と非アクティブ要素を保持。深さとは別である（src/core/image_restore.zig:89〜93、docs/TASK_CONTROL_PROTO_1354.md:44）。結論：O。自VM内だけで使用し、メインと共有してはならない。宣言 `src/forth.zig:218` |
| `data_depth` | 新規VM・専有（O） | 型 `usize`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `0`。復元：0へ（src/core/image_restore.zig:89〜93）。結論：O。自VM内だけで使用し、メインと共有してはならない。宣言 `src/forth.zig:219` |
| `return_stack` | 新規VM・専有（O） | 型 `[]Cell`。再帰：P：Storageの数値slice。Cellは論理アドレス・xtを表し得る。init：given.return_stackを設定。別確保先の全要素をState.initで消去はしない。復元：slice先と非アクティブ要素を保持。深さとは別である（src/core/image_restore.zig:89〜93、docs/TASK_CONTROL_PROTO_1354.md:44）。結論：O。自VM内だけで使用し、メインと共有してはならない。宣言 `src/forth.zig:220` |
| `return_depth` | 新規VM・専有（O） | 型 `usize`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `0`。復元：0へ（src/core/image_restore.zig:89〜93）。結論：O。自VM内だけで使用し、メインと共有してはならない。宣言 `src/forth.zig:221` |
| `float_stack` | 新規VM・専有（O） | 型 `[]Float`。再帰：P：Storageの数値slice。Cellは論理アドレス・xtを表し得る。init：given.float_stackを設定。別確保先の全要素をState.initで消去はしない。復元：slice先と非アクティブ要素を保持。深さとは別である（src/core/image_restore.zig:89〜93、docs/TASK_CONTROL_PROTO_1354.md:44）。結論：O。自VM内だけで使用し、メインと共有してはならない。宣言 `src/forth.zig:222` |
| `float_depth` | 新規VM・専有（O） | 型 `usize`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `0`。復元：0へ（src/core/image_restore.zig:89〜93）。結論：O。自VM内だけで使用し、メインと共有してはならない。宣言 `src/forth.zig:223` |
| `quote_frames` | 新規初期化・初期使用禁止（X） | 型 `[16]@import("core/quotations.zig").Frame`。再帰：V：内部コンテナも値（T03）。init：宣言 `undefined`。復元：R0（共通applyと呼出し先）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:224` |
| `quote_depth` | 新規初期化・初期使用禁止（X） | 型 `usize`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `0`。復元：0へ（src/core/image_restore.zig:97）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:225` |
| `quote_closing` | 新規初期化・初期使用禁止（X） | 型 `bool`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `false`。復元：R0（共通applyと呼出し先）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:226` |
| `quote_root` | 新規初期化・初期使用禁止（X） | 型 `u16`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `0`。復元：R0（共通applyと呼出し先）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:227` |
| `image_generation` | 新規VM・専有（O） | 型 `u64`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `0`。復元：1加算（wrapping）（src/core/image_restore.zig:26）。結論：O。自VM内だけで使用し、メインと共有してはならない。宣言 `src/forth.zig:228` |
| `backtrace_suppression` | 新規初期化・初期使用禁止（X） | 型 `usize`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `0`。復元：R0（共通applyと呼出し先）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:229` |
| `throw_nobt` | 新規初期化・初期使用禁止（X） | 型 `bool`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `false`。復元：R0（共通applyと呼出し先）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:230` |
| `assert_depth` | 新規初期化・初期使用禁止（X） | 型 `usize`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `0`。復元：R0（共通applyと呼出し先）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:231` |
| `wrap_guard` | 新規初期化・初期使用禁止（X） | 型 `?*@import("core/words_value_extensions.zig").Guard`。再帰：P：Guard.previousもポインターである（T04）。init：宣言 `null`。復元：Guard連鎖をinvalidate。ポインターをnullにはしない（src/core/words_value_extensions.zig:27）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:232` |
| `colon_is_word` | 新規初期化・初期使用禁止（X） | 型 `?u16`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `null`。復元：invalidateで対象を無効化（src/core/words_value_extensions.zig:36）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:233` |
| `colon_is_target` | 新規初期化・初期使用禁止（X） | 型 `u16`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `0`。復元：R0（共通applyと呼出し先）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:234` |
| `noname_next` | 新規初期化・初期使用禁止（X） | 型 `bool`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `false`。復元：falseへ（src/core/image_restore.zig:99）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:235` |
| `next_name_len` | 新規初期化・初期使用禁止（X） | 型 `u8`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `0`。復元：0へ。next_name本体は保持（src/core/image_restore.zig:100）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:236` |
| `next_name` | 新規初期化・初期使用禁止（X） | 型 `[memory_map.max_name]u8`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `@splat(0)`。復元：R0（共通applyと呼出し先）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:237` |
| `postponing` | 新規初期化・初期使用禁止（X） | 型 `bool`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `false`。復元：falseへ（src/core/image_restore.zig:98）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:238` |
| `control_stack` | 新規初期化・初期使用禁止（X） | 型 `[max_controls]Control`。再帰：V：内部コンテナも値（T03）。init：宣言 `undefined`。復元：R0（共通applyと呼出し先）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:239` |
| `control_depth` | 新規初期化・初期使用禁止（X） | 型 `usize`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `0`。復元：0へ（src/core/image_restore.zig:89〜93）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:240` |
| `hidden_word` | 新規初期化・初期使用禁止（X） | 型 `u16`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `wordlists.no_word`。復元：R0（共通applyと呼出し先）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:242` |
| `random_state` | 新規VM・専有（O） | 型 `u64`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言0。utime_fnがあればcontext経由で取得（失敗時0）。初期Writerはnullとする。復元：R0（共通applyと呼出し先）。結論：O。自VM内だけで使用し、メインと共有してはならない。宣言 `src/forth.zig:243` |
| `addresses` | 新規VMから検査・再構成（O） | 型 `@import("core/address_registry.zig").Registry`。再帰：V：Registry→Record固定配列・索引。論理参照あり（T05）。init：宣言.{}。後続writeCell等も自VMのRegistryを使用する。復元：records/countを復元、index_dirty=true、stable_writes=0。未使用records/memory_order/memory_count全域を初期化しない（src/core/image_restore.zig:38〜40、:107〜110）。結論：O。明示Snapshotから再構成し、復元後の許可・領域検査を要する。メインと共有してはならない。宣言 `src/forth.zig:244` |
| `interpret_loops` | 新規初期化・初期使用禁止（X） | 型 `[16]InterpretLoop`。再帰：V：内部コンテナも値（T03）。init：宣言 `undefined`。復元：R0（共通applyと呼出し先）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:246` |
| `interpret_loop_depth` | 新規初期化・初期使用禁止（X） | 型 `usize`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `0`。復元：R0（共通applyと呼出し先）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:247` |
| `input_line_serial` | 新規初期化・初期使用禁止（X） | 型 `Cell`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `0`。復元：R0（共通applyと呼出し先）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:250` |
| `input_lines_read` | 新規初期化・初期使用禁止（X） | 型 `Cell`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `0`。復元：R0（共通applyと呼出し先）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:251` |
| `token_start` | 新規初期化・初期使用禁止（X） | 型 `usize`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `0`。復元：R0（共通applyと呼出し先）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:253` |
| `uses` | 新規初期化・初期使用禁止（X） | 型 `[max_uses]defs.WordUse`。再帰：V：内部コンテナも値（T03）。init：宣言 `undefined`。復元：R0（共通applyと呼出し先）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:254` |
| `use_count` | 新規初期化・初期使用禁止（X） | 型 `usize`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `0`。復元：0へ。対応配列全域の消去ではない（src/core/image_restore.zig:81）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:255` |
| `loop_stack` | 新規初期化・初期使用禁止（X） | 型 `[]Loop`。再帰：P：slice→Loop内部はV（T03）。init：given.loop_stackを設定。別確保先の全要素をState.initで消去はしない。復元：slice先と非アクティブ要素を保持。深さとは別である（src/core/image_restore.zig:89〜93、docs/TASK_CONTROL_PROTO_1354.md:44）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:256` |
| `loop_depth` | 新規初期化・初期使用禁止（X） | 型 `usize`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `0`。復元：0へ（src/core/image_restore.zig:89〜93）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:257` |
| `data_here` | 新規VMから検査・再構成（O） | 型 `Cell`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `data_start`。復元：画像／Planから設定（src/core/image_restore.zig:76〜79）。結論：O。明示Snapshotから再構成し、復元後の許可・領域検査を要する。メインと共有してはならない。宣言 `src/forth.zig:258` |
| `compiling` | 新規初期化・初期使用禁止（X） | 型 `bool`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `false`。復元：falseへ、論理STATEセルも更新（src/core/image_restore.zig:95、src/forth.zig:1402）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:259` |
| `defining` | 新規初期化・初期使用禁止（X） | 型 `bool`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `false`。復元：falseへ（src/core/image_restore.zig:96）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:260` |
| `current_word` | 新規初期化・初期使用禁止（X） | 型 `u16`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `0`。復元：R0（共通applyと呼出し先）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:261` |
| `current_data_start` | 新規初期化・初期使用禁止（X） | 型 `Cell`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `0`。復元：R0（共通applyと呼出し先）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:262` |
| `pending` | 新規初期化・初期使用禁止（X） | 型 `Pending`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `.none`。復元：noneへ（src/core/image_restore.zig:101）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:263` |
| `pending_constant` | 新規初期化・初期使用禁止（X） | 型 `Cell`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `0`。復元：R0（共通applyと呼出し先）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:264` |
| `pending_float` | 新規初期化・初期使用禁止（X） | 型 `Float`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `0`。復元：R0（共通applyと呼出し先）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:265` |
| `pending_double` | 新規初期化・初期使用禁止（X） | 型 `Double`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `0`。復元：R0（共通applyと呼出し先）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:266` |
| `pending_array_size` | 新規初期化・初期使用禁止（X） | 型 `Cell`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `0`。復元：R0（共通applyと呼出し先）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:267` |
| `hold_ptr` | 新規VM・専有（O） | 型 `Cell`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `hold_top`。復元：hold_topへ（src/core/number_io.zig:25）。結論：O。自VM内だけで使用し、メインと共有してはならない。宣言 `src/forth.zig:268` |
| `hold_end` | 新規VM・専有（O） | 型 `Cell`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `hold_top`。復元：hold_topへ（src/core/number_io.zig:25）。結論：O。自VM内だけで使用し、メインと共有してはならない。宣言 `src/forth.zig:269` |
| `hold_stack` | 新規VM・専有（O） | 型 `[max_hold_nesting]Cell`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `undefined`。復元：R0（共通applyと呼出し先）。結論：O。自VM内だけで使用し、メインと共有してはならない。宣言 `src/forth.zig:270` |
| `hold_depth` | 新規VM・専有（O） | 型 `usize`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `0`。復元：0へ（src/core/number_io.zig:25）。結論：O。自VM内だけで使用し、メインと共有してはならない。宣言 `src/forth.zig:271` |
| `source_line` | 新規初期化・初期使用禁止（X） | 型 `[]const u8`。再帰：P：借用文字列slice。init：宣言 `&.{}`。復元：R0（共通applyと呼出し先）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:272` |
| `source_kind` | 新規初期化・初期使用禁止（X） | 型 `SourceKind`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `.terminal`。復元：R0（共通applyと呼出し先）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:274` |
| `block_depth` | 新規初期化・初期使用禁止（X） | 型 `usize`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `0`。復元：R0（共通applyと呼出し先）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:275` |
| `block_source_numbers` | 新規初期化・初期使用禁止（X） | 型 `[memory_map.max_include_depth]Cell`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `@splat(0)`。復元：R0（共通applyと呼出し先）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:276` |
| `include_stack` | 新規初期化・初期使用禁止（X） | 型 `[max_include_depth]IncludeFrame`。再帰：V＋H：IncludeFrame.fileidはホストID（T03）。init：宣言 `undefined`。復元：R0（共通applyと呼出し先）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:277` |
| `include_depth` | 新規初期化・初期使用禁止（X） | 型 `usize`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `0`。復元：R0（共通applyと呼出し先）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:278` |
| `error_location` | 新規初期化・初期使用禁止（X） | 型 `?ErrorLocation`。再帰：V：内部コンテナも値（T03）。init：宣言 `null`。復元：R0（共通applyと呼出し先）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:279` |
| `source_navigation` | 新規初期化・初期使用禁止（X） | 型 `@import("core/source_navigation.zig").Navigation`。再帰：V：固定配列・数値・enum・optional（T07）。init：宣言 `.{}`。復元：R0（共通applyと呼出し先）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:280` |
| `source_search` | 新規初期化・初期使用禁止（X） | 型 `@import("core/source_search.zig").Search`。再帰：V：固定配列・数値・enum・optional（T07）。init：宣言 `.{}`。復元：R0（共通applyと呼出し先）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:281` |
| `source_editor_mode` | 新規初期化・初期使用禁止（X） | 型 `@import("core/source_editor.zig").Mode`。再帰：V：固定配列・数値・enum・optional（T07）。init：宣言 `.{}`。復元：R0（共通applyと呼出し先）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:282` |
| `source_trace` | 新規初期化・初期使用禁止（X） | 型 `@import("core/source_diagnostics.zig").History`。再帰：V：固定配列・数値・enum・optional（T07）。init：宣言 `.{}`。復元：R0（共通applyと呼出し先）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:283` |
| `name_buffer_index` | 新規VM・専有（O） | 型 `usize`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `0`。復元：R0（共通applyと呼出し先）。結論：O。自VM内だけで使用し、メインと共有してはならない。宣言 `src/forth.zig:284` |
| `last_created_word` | 新規VM・専有（O） | 型 `?u16`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `null`。復元：nullへ（src/core/image_restore.zig:102）。結論：O。自VM内だけで使用し、メインと共有してはならない。宣言 `src/forth.zig:285` |
| `halted` | 新規VM・専有（O） | 型 `bool`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `false`。復元：R0（共通applyと呼出し先）。結論：O。新規false。非atomicであり別スレッドの取消し印には使わない（docs/CORE_EXTENSION_DETAILED_DESIGN.md:824）。宣言 `src/forth.zig:286` |
| `pending_key` | 新規初期化・初期使用禁止（X） | 型 `?u8`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `null`。復元：nullへ（src/core/image_restore.zig:28〜30）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:289` |
| `pending_event_bytes` | 新規初期化・初期使用禁止（X） | 型 `[32]u8`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `undefined`。復元：R0（共通applyと呼出し先）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:290` |
| `pending_event_count` | 新規初期化・初期使用禁止（X） | 型 `usize`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `0`。復元：0へ。対応配列全域の消去ではない（src/core/image_restore.zig:29）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:291` |
| `pending_standard_event` | 新規初期化・初期使用禁止（X） | 型 `?Cell`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `null`。復元：nullへ（src/core/image_restore.zig:28〜30）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:292` |
| `standard_input` | 新規初期化・初期使用禁止（X） | 型 `@import("core/standard_event.zig").Decoder`。再帰：V：Decoder→Legacy/Packet/Mouse/Instant。Sourceは格納しない（T08）。init：宣言 `.{}`。復元：Decoder全体を.{}へ（src/core/image_restore.zig:27）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:293` |
| `block_storage` | 新規初期化・初期使用禁止（X） | 型 `@import("core/blocks.zig").Storage`。再帰：V＋H：Storage→Buffer配列、fileはホストID（T09）。init：宣言 `.{}`。復元：R0（共通applyと呼出し先）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:294` |
| `call_depth` | 新規VM・専有（O） | 型 `usize`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `0`。復元：R0（共通applyと呼出し先）。結論：O。自VM内だけで使用し、メインと共有してはならない。宣言 `src/forth.zig:295` |
| `frames` | 新規VM・専有（O） | 型 `[]CallFrame`。再帰：P：slice→CallFrame/CatchContinuation内部はV（T06）。init：given.framesを設定。別確保先の全要素をState.initで消去はしない。復元：slice先と非アクティブ要素を保持。深さとは別である（src/core/image_restore.zig:89〜93、docs/TASK_CONTROL_PROTO_1354.md:44）。結論：O。自VM内だけで使用し、メインと共有してはならない。宣言 `src/forth.zig:298` |
| `frame_depth` | 新規VM・専有（O） | 型 `usize`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `0`。復元：R0（共通applyと呼出し先）。結論：O。自VM内だけで使用し、メインと共有してはならない。宣言 `src/forth.zig:299` |
| `catches` | 新規初期化・初期使用禁止（X） | 型 `[]CatchContinuation`。再帰：P：slice→CallFrame/CatchContinuation内部はV（T06）。init：given.catchesを設定。別確保先の全要素をState.initで消去はしない。復元：slice先と非アクティブ要素を保持。深さとは別である（src/core/image_restore.zig:89〜93、docs/TASK_CONTROL_PROTO_1354.md:44）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:301` |
| `catch_depth` | 新規初期化・初期使用禁止（X） | 型 `usize`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `0`。復元：R0（共通applyと呼出し先）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:302` |
| `backtrace` | 新規VM・専有（O） | 型 `[max_backtrace]u16`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `undefined`。復元：R0（共通applyと呼出し先）。結論：O。自VM内だけで使用し、メインと共有してはならない。宣言 `src/forth.zig:307` |
| `backtrace_count` | 新規VM・専有（O） | 型 `usize`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `0`。復元：R0（共通applyと呼出し先）。結論：O。自VM内だけで使用し、メインと共有してはならない。宣言 `src/forth.zig:308` |
| `backtrace_total` | 新規VM・専有（O） | 型 `usize`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `0`。復元：R0（共通applyと呼出し先）。結論：O。自VM内だけで使用し、メインと共有してはならない。宣言 `src/forth.zig:309` |
| `backtrace_level` | 新規VM・専有（O） | 型 `usize`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `0`。復元：R0（共通applyと呼出し先）。結論：O。自VM内だけで使用し、メインと共有してはならない。宣言 `src/forth.zig:310` |
| `failed_pc` | 新規VM・専有（O） | 型 `u16`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `0`。復元：R0（共通applyと呼出し先）。結論：O。自VM内だけで使用し、メインと共有してはならない。宣言 `src/forth.zig:312` |
| `show_backtrace` | 新規VM・専有（O） | 型 `bool`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `true`。復元：R0（共通applyと呼出し先）。結論：O。自VM内だけで使用し、メインと共有してはならない。宣言 `src/forth.zig:314` |
| `code_lines` | 新規VM・専有（O） | 型 `if (defs.debug_enabled) [max_code]u32 else void`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `if (defs.debug_enabled) @splat(0) else {}`。復元：debug有効なら全配列0へ（src/core/image_restore.zig:82〜84）。結論：O。自VM内だけで使用し、メインと共有してはならない。宣言 `src/forth.zig:317` |
| `cover_blocks` | 新規初期化・初期使用禁止（X） | 型 `bool`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `false`。復元：R0（共通applyと呼出し先）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:324` |
| `code_columns` | 新規VM・専有（O） | 型 `if (defs.debug_enabled) [max_code]u16 else void`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `if (defs.debug_enabled) @splat(0) else {}`。復元：debug有効なら全配列0へ（src/core/image_restore.zig:82〜84）。結論：O。自VM内だけで使用し、メインと共有してはならない。宣言 `src/forth.zig:325` |
| `step_limit` | 新規初期化・初期使用禁止（X） | 型 `u64`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `0`。復元：R0（共通applyと呼出し先）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:328` |
| `steps_left` | 新規初期化・初期使用禁止（X） | 型 `u64`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `0`。復元：R0（共通applyと呼出し先）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:329` |
| `execution` | 新規初期化・初期使用禁止（X） | 型 `if (defs.debug_enabled) @import("core/execution_control.zig").Control else @import("core/execution_control.zig").Empty`。再帰：V：Control→Budget/Stop、またはEmpty（T10）。init：宣言 `.{}`。復元：R0（共通applyと呼出し先）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:330` |
| `tracing` | 新規初期化・初期使用禁止（X） | 型 `bool`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `false`。復元：R0（共通applyと呼出し先）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:334` |
| `trace_limit` | 新規初期化・初期使用禁止（X） | 型 `u64`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `0`。復元：R0（共通applyと呼出し先）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:335` |
| `trace_lines` | 新規初期化・初期使用禁止（X） | 型 `u64`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `0`。復元：R0（共通applyと呼出し先）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:336` |
| `trace_depth` | 新規初期化・初期使用禁止（X） | 型 `usize`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `0`。復元：R0（共通applyと呼出し先）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:337` |
| `profile` | 新規初期化・初期使用禁止（X） | 型 `?*Profile`。再帰：P：外部所有先の内部は値と固定配列（T11）。init：宣言 `null`。復元：R0（共通applyと呼出し先）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:339` |
| `lint` | 新規初期化・初期使用禁止（X） | 型 `?*Lint`。再帰：P：外部所有先の内部は値と固定配列（T11）。init：宣言 `null`。復元：R0（共通applyと呼出し先）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:341` |
| `plain_calls` | 新規VM・専有（O） | 型 `bool`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `false`。復元：R0（共通applyと呼出し先）。結論：O。新規falseを基準としメインのtrace/profile設定を継承しない。復元コードの一致条件と許可検査を確認する。宣言 `src/forth.zig:345` |
| `stepper` | 新規初期化・初期使用禁止（X） | 型 `enum { off, armed, on }`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `.off`。復元：R0（共通applyと呼出し先）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:351` |
| `step_word` | 新規初期化・初期使用禁止（X） | 型 `u16`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `0`。復元：R0（共通applyと呼出し先）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:352` |
| `step_depth` | 新規初期化・初期使用禁止（X） | 型 `usize`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `0`。復元：R0（共通applyと呼出し先）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:353` |
| `step_base` | 新規初期化・初期使用禁止（X） | 型 `usize`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `0`。復元：R0（共通applyと呼出し先）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:354` |
| `step_result` | 新規初期化・初期使用禁止（X） | 型 `bool`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `false`。復元：R0（共通applyと呼出し先）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:355` |
| `step_after_cr` | 新規初期化・初期使用禁止（X） | 型 `bool`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `false`。復元：R0（共通applyと呼出し先）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:356` |
| `step_skip_end` | 新規初期化・初期使用禁止（X） | 型 `u16`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `0`。復元：R0（共通applyと呼出し先）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:359` |
| `step_inline_ends` | 新規初期化・初期使用禁止（X） | 型 `[8]u16`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `undefined`。復元：R0（共通applyと呼出し先）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:362` |
| `step_inline_count` | 新規初期化・初期使用禁止（X） | 型 `usize`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `0`。復元：R0（共通applyと呼出し先）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:363` |
| `in_counted` | 新規初期化・初期使用禁止（X） | 型 `bool`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `false`。復元：R0（共通applyと呼出し先）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:367` |
| `keep_counting` | 新規初期化・初期使用禁止（X） | 型 `bool`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `false`。復元：通常保持。debug有効で復元コードにBREAKがあればtrueへ（src/core/image_restore.zig:88、src/core/words_debug.zig:346）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。init=falseだけでは不足し、復元後trueやBREAK到達を拒否し、worker経路をcountedから分離する。宣言 `src/forth.zig:368` |
| `report_text` | 新規VM・専有（O） | 型 `[240]u8`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `undefined`。復元：R0（共通applyと呼出し先）。結論：O。自VM内だけで使用し、メインと共有してはならない。宣言 `src/forth.zig:370` |
| `report_len` | 新規VM・専有（O） | 型 `usize`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `0`。復元：R0（共通applyと呼出し先）。結論：O。自VM内だけで使用し、メインと共有してはならない。宣言 `src/forth.zig:371` |
| `report_capturing` | 新規VM・専有（O） | 型 `bool`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `false`。復元：R0（共通applyと呼出し先）。結論：O。自VM内だけで使用し、メインと共有してはならない。宣言 `src/forth.zig:372` |
| `cell_watches` | 新規初期化・初期使用禁止（X） | 型 `[8]struct { address: Cell, value: Cell }`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `undefined`。復元：R0（共通applyと呼出し先）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:376` |
| `cell_watch_count` | 新規初期化・初期使用禁止（X） | 型 `usize`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `0`。復元：0へ。対応配列全域の消去ではない（src/core/image_restore.zig:42）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:377` |
| `line_trace` | 新規初期化・初期使用禁止（X） | 型 `bool`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `false`。復元：R0（共通applyと呼出し先）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:379` |
| `watched` | 新規初期化・初期使用禁止（X） | 型 `[32]u16`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `undefined`。復元：R0（共通applyと呼出し先）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:381` |
| `watched_count` | 新規初期化・初期使用禁止（X） | 型 `usize`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `0`。復元：0へ。対応配列全域の消去ではない（src/core/image_restore.zig:41）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:382` |
| `outer_pc` | 新規VM・専有（O） | 型 `u16`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `0`。復元：R0（共通applyと呼出し先）。結論：O。自VM内だけで使用し、メインと共有してはならない。宣言 `src/forth.zig:385` |
| `last_unknown_word` | 新規VM・専有（O） | 型 `?[]const u8`。再帰：P：借用文字列slice。init：宣言 `null`。復元：R0（共通applyと呼出し先）。結論：O。自VM内だけで使用し、メインと共有してはならない。宣言 `src/forth.zig:386` |
| `throw_code` | 新規VM・専有（O） | 型 `Cell`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `0`。復元：R0（共通applyと呼出し先）。結論：O。自VM内だけで使用し、メインと共有してはならない。宣言 `src/forth.zig:387` |
| `abort_message` | 新規VM・専有（O） | 型 `?Cell`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `null`。復元：R0（共通applyと呼出し先）。結論：O。自VM内だけで使用し、メインと共有してはならない。宣言 `src/forth.zig:389` |
| `input_file` | 新規初期化・初期使用禁止（X） | 型 `?Cell`。再帰：V＋H：optional CellのホストファイルID。init：宣言 `null`。復元：R0（共通applyと呼出し先）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:390` |
| `output_file` | 新規初期化・初期使用禁止（X） | 型 `?Cell`。再帰：V＋H：optional CellのホストファイルID。init：宣言 `null`。復元：R0（共通applyと呼出し先）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:391` |
| `output_error` | 新規初期化・初期使用禁止（X） | 型 `?Cell`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `null`。復元：R0（共通applyと呼出し先）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:392` |
| `capture_target` | 新規初期化・初期使用禁止（X） | 型 `?Cell`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `null`。復元：R0（共通applyと呼出し先）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:393` |
| `capture_sink` | 新規初期化・初期使用禁止（X） | 型 `?*@import("core/macro_substitute.zig").Captured`。再帰：P：外部Captured→VM論理buffer/件数（T12）。init：宣言 `null`。復元：R0（共通applyと呼出し先）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:395` |
| `sh_get_result` | 新規初期化・初期使用禁止（X） | 型 `?@import("core/dynamic_strings.zig").StringRef`。再帰：V：StringRef→VM論理address/length（T12）。init：宣言 `null`。復元：nullへ。旧ヒープをfreeしない（src/core/image_restore.zig:37）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:397` |
| `system_status` | 新規初期化・初期使用禁止（X） | 型 `Cell`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `0`。復元：R0（共通applyと呼出し先）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:399` |
| `capture_failed` | 新規初期化・初期使用禁止（X） | 型 `bool`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `false`。復元：R0（共通applyと呼出し先）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:400` |
| `tmp_string_index` | 新規VM・専有（O） | 型 `usize`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `0`。復元：R0（共通applyと呼出し先）。結論：O。自VM内だけで使用し、メインと共有してはならない。宣言 `src/forth.zig:401` |
| `locals` | 新規VM・専有（O） | 型 `[max_locals]Local`。再帰：V：内部コンテナも値（T03）。init：宣言 `undefined`。復元：R0（共通applyと呼出し先）。結論：O。自VM内だけで使用し、メインと共有してはならない。宣言 `src/forth.zig:402` |
| `local_count` | 新規VM・専有（O） | 型 `usize`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `0`。復元：R0（共通applyと呼出し先）。結論：O。自VM内だけで使用し、メインと共有してはならない。宣言 `src/forth.zig:403` |
| `locals_frame_size` | 新規VM・専有（O） | 型 `u16`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `0`。復元：R0（共通applyと呼出し先）。結論：O。自VM内だけで使用し、メインと共有してはならない。宣言 `src/forth.zig:405` |
| `locals_top` | 新規VM・専有（O） | 型 `Cell`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：given.sizes.localsBase()を設定。復元：R0（共通applyと呼出し先）。結論：O。自VM内だけで使用し、メインと共有してはならない。宣言 `src/forth.zig:406` |
| `gfx_pixels` | 新規初期化・初期使用禁止（X） | 型 `[]u32`。再帰：P：ホストframebufferのslice。init：宣言 `&.{}`。復元：空へ。framebufferのfreeではない（src/core/words_graphics.zig:587）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:409` |
| `gfx_width` | 新規初期化・初期使用禁止（X） | 型 `Cell`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `0`。復元：0へ（src/core/words_graphics.zig:589）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:410` |
| `gfx_height` | 新規初期化・初期使用禁止（X） | 型 `Cell`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `0`。復元：0へ（src/core/words_graphics.zig:589）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:411` |
| `gfx_images` | 新規初期化・初期使用禁止（X） | 型 `[graphics_images.max_images]graphics_images.Slot`。再帰：P：Slot固定配列→pixels slice、clipはV（T13）。init：宣言 `@splat(.{})`。復元：非空slotをreleaseし使用量を減算。空slotまで全再初期化はしない（src/core/graphics_images.zig:317〜333）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:415` |
| `gfx_images_bytes` | 新規初期化・初期使用禁止（X） | 型 `usize`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `0`。復元：非空slotをreleaseし使用量を減算。空slotまで全再初期化はしない（src/core/graphics_images.zig:317〜333）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:416` |
| `gfx_target` | 新規初期化・初期使用禁止（X） | 型 `Cell`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `graphics_images.screen`。復元：screenへ（src/core/graphics_images.zig:333）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:417` |
| `graphics_library` | 新規init本文・実行許可とは別 | 型 `[]const u8`。再帰：P：const文字列slice。initの静的本文と差替え借用本文を区別する。init：宣言 `if (defs.graphics_enabled) words_graphics.library else ""`。復元：R0（共通applyと呼出し先）。結論：O＋X。init由来の不変本文だけ共有候補、差替えsliceは継承しない。REQUIREを自動許可しない。宣言 `src/forth.zig:420` |
| `gui_library` | 新規init本文・実行許可とは別 | 型 `[]const u8`。再帰：P：const文字列slice。initの静的本文と差替え借用本文を区別する。init：宣言 `if (defs.graphics_enabled) @import("core/words_gui.zig").library else ""`。復元：R0（共通applyと呼出し先）。結論：O＋X。init由来の不変本文だけ共有候補、差替えsliceは継承しない。REQUIREを自動許可しない。宣言 `src/forth.zig:422` |
| `game_library` | 新規init本文・実行許可とは別 | 型 `[]const u8`。再帰：P：const文字列slice。initの静的本文と差替え借用本文を区別する。init：宣言 `if (defs.graphics_enabled) @import("core/words_game.zig").library else ""`。復元：R0（共通applyと呼出し先）。結論：O＋X。init由来の不変本文だけ共有候補、差替えsliceは継承しない。REQUIREを自動許可しない。宣言 `src/forth.zig:424` |
| `audio_library` | 新規init本文・実行許可とは別 | 型 `[]const u8`。再帰：P：const文字列slice。initの静的本文と差替え借用本文を区別する。init：宣言 `if (defs.audio_enabled) words_audio.library else ""`。復元：R0（共通applyと呼出し先）。結論：O＋X。init由来の不変本文だけ共有候補、差替えsliceは継承しない。REQUIREを自動許可しない。宣言 `src/forth.zig:426` |
| `extension_library` | 新規init本文・実行許可とは別 | 型 `[]const u8`。再帰：P：const文字列slice。initの静的本文と差替え借用本文を区別する。init：宣言 `if (defs.extension_enabled) @import("core/words_extension.zig").library else ""`。復元：R0（共通applyと呼出し先）。結論：O＋X。init由来の不変本文だけ共有候補、差替えsliceは継承しない。REQUIREを自動許可しない。宣言 `src/forth.zig:427` |
| `audio_voices` | 新規初期化・初期使用禁止（X） | 型 `[sound_engine.max_voices]sound_mml.Voice`。再帰：V：Voice固定配列（T14）。init：宣言 `@splat(.{})`。復元：R0（共通applyと呼出し先）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:429` |
| `audio_instruments` | 新規初期化・初期使用禁止（X） | 型 `[sound_mml.instrument_count]sound_engine.Tone`。再帰：V＋H：pool位置・sample番号・音所有ID（T14）。init：宣言 `@splat(.{})`。復元：R0（共通applyと呼出し先）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:432` |
| `audio_instrument` | 新規初期化・初期使用禁止（X） | 型 `u8`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `0`。復元：R0（共通applyと呼出し先）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:433` |
| `audio_samples` | 新規初期化・初期使用禁止（X） | 型 `[sound_engine.pcm.sample_count]sound_engine.pcm.Sample`。再帰：V＋H：pool位置・sample番号・音所有ID（T14）。init：宣言 `@splat(.{})`。復元：R0（共通applyと呼出し先）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:436` |
| `audio_pool_used` | 新規初期化・初期使用禁止（X） | 型 `u32`。再帰：V＋H：ホストの音poolの使用量である（`src/forth.zig:434`〜`src/forth.zig:437`、`src/core/sound_engine.zig:161`〜`src/core/sound_engine.zig:162`）。init：宣言 `0`。復元：R0（共通applyと呼出し先）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:437` |
| `audio_pcm_handle` | 新規初期化・初期使用禁止（X） | 型 `Cell`。再帰：V＋H：pool位置・sample番号・音所有ID（T14）。init：宣言 `0`。復元：非0ならapply前に-528で拒否、0は維持（src/core/image_restore.zig:12、:20）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:439` |
| `gfx_band` | 新規初期化・初期使用禁止（X） | 型 `if (defs.graphics_enabled) [6][graphics_terminal.max_sixel_width]u8 else void`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `undefined`。復元：R0（共通applyと呼出し先）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:442` |
| `gfx_glyph_alpha` | 新規初期化・初期使用禁止（X） | 型 `if (defs.graphics_enabled) graphics_font.Alpha else void`。再帰：V：Alpha/ColorMode/Clipは数値・bool・固定配列（T13）。init：宣言 `undefined`。復元：R0（共通applyと呼出し先）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:444` |
| `embedded_source` | 新規初期化・初期使用禁止（X） | 型 `[]const u8`。再帰：P：借用文字列slice。init：宣言 `&.{}`。復元：R0（共通applyと呼出し先）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:446` |
| `gfx_input` | 新規初期化・初期使用禁止（X） | 型 `graphics_input.InputState`。再帰：V：InputState→Shown/Key/Held/MouseEvent固定配列（T15）。init：宣言 `.{}`。復元：通常保持。Tcl partialがUならTk保持キーを処理（src/core/tcl.zig:100）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:449` |
| `tcl` | 新規初期化・初期使用禁止（X） | 型 `if (defs.graphics_enabled) tcl.TclState else void`。再帰：V＋H：TclState→Text/MessageのVM論理参照とプロセス状態（T16）。init：宣言 `if (defs.graphics_enabled) .{} else {}`。復元：graphics有効時forgetHeap。result/error_text/event・event_countとpartial/receivedを処理、他は保持（src/core/tcl.zig:85〜105）。結論：O＋X。TCL・DISPLAY-TKはUI・プロセス機能であり、利用者判断に従い初期許可集合から外す。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:451` |
| `gfx_color_mode` | 新規初期化・初期使用禁止（X） | 型 `graphics_palette.ColorMode`。再帰：V：Alpha/ColorMode/Clipは数値・bool・固定配列（T13）。init：宣言 `.{}`。復元：R0（共通applyと呼出し先）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:453` |
| `gfx_window_size` | 新規初期化・初期使用禁止（X） | 型 `[2]u32`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `.{ 0, 0 }`。復元：R0（共通applyと呼出し先）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:456` |
| `gfx_auto_display` | 新規初期化・初期使用禁止（X） | 型 `u8`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `0`。復元：R0（共通applyと呼出し先）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:459` |
| `gfx_fullscreen` | 新規初期化・初期使用禁止（X） | 型 `bool`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `false`。復元：R0（共通applyと呼出し先）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:461` |
| `gfx_cursor_visible` | 新規初期化・初期使用禁止（X） | 型 `bool`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `true`。復元：R0（共通applyと呼出し先）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:462` |
| `gfx_clip` | 新規初期化・初期使用禁止（X） | 型 `?@import("core/graphics_images.zig").Clip`。再帰：V：Alpha/ColorMode/Clipは数値・bool・固定配列（T13）。init：宣言 `null`。復元：nullへ（src/core/words_graphics.zig:591）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:465` |
| `gfx_window_fit` | 新規初期化・初期使用禁止（X） | 型 `u8`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `0`。復元：R0（共通applyと呼出し先）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:467` |
| `gfx_window_smooth` | 新規初期化・初期使用禁止（X） | 型 `bool`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `false`。復元：R0（共通applyと呼出し先）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:469` |
| `gfx_window_keep_open` | 新規初期化・初期使用禁止（X） | 型 `bool`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `false`。復元：R0（共通applyと呼出し先）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:471` |
| `gfx_displays` | 新規初期化・初期使用禁止（X） | 型 `@import("core/display_info.zig").Snapshot`。再帰：V＋H：Snapshot内部は固定配列と値、機器IDあり（T17）。init：宣言 `.{}`。復元：R0（共通applyと呼出し先）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:473` |
| `gamepads` | 新規初期化・初期使用禁止（X） | 型 `@import("core/gamepad.zig").Snapshot`。再帰：V＋H：Snapshot内部は固定配列と値、機器IDあり（T17）。init：宣言 `.{}`。復元：R0（共通applyと呼出し先）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:474` |
| `gfx_font` | 新規初期化・初期使用禁止（X） | 型 `if (defs.graphics_enabled) graphics_font.FontState else void`。再帰：P：FontState→buffer/entries/bitsのslice、またはvoid（T13）。init：宣言 `if (defs.graphics_enabled) .{} else {}`。復元：kindのみbuiltinへ。他のsliceを保持しfreeしない（src/core/graphics_font.zig:78）。結論：O＋X。新規VMで初期化し、当該機能はワーカーで使わない。メインと共有してはならない。宣言 `src/forth.zig:476` |
| `output_count` | 新規VM・専有（O） | 型 `u64`。再帰：V：数値・bool・enum・optional・固定長数値配列だけである。init：宣言 `0`。復元：R0（共通applyと呼出し先）。結論：O。自VM内だけで使用し、メインと共有してはならない。宣言 `src/forth.zig:479` |

## 再帰型の内訳

Stateが保持する型だけを辿る。同じモジュールにある別型や関数の引数型をフィールドの内包参照に数えない。DecoderはSourceを、VoiceはParserを、SampleはEngine.poolを格納しない。

| フィールド | 扱い | 条件 |
|---|---|---|
| T01 sizes | V | Sizesはm/lとstack容量のusizeだけである（`src/core/memory_map.zig:54`）。復元時は単なる容量比較でなくm/l・builtin形状の適合が必要である（`docs/CORE_EXTENSION_DETAILED_DESIGN.md:810`） |
| T02 words / code | V・論理参照 | Wordは整数・enum・bool・Cell、Opはkind/Cellでありnative関数ポインターはない（`src/core/defs.zig:1292`、`src/core/defs.zig:1447`）。valueはxt・VMアドレス・分岐先等を表すため、整数であることだけで権限・版の適合は保証されない |
| T03 quote_frames / control_stack / interpret_loops / uses / include_stack / error_location / loop_stack / locals | V、一部H | quotation Frame→Local/Control固定配列（`src/core/quotations.zig:5`）。Localはname固定配列とenum/整数/bool（`src/core/defs.zig:1438`）、Control/Loopも数値・enum・bool（同`src/core/defs.zig:1453`、`src/core/defs.zig:1455`）。InterpretLoop→InputPlaceのCell群、WordUse→語/位置、IncludeFrame→fileidと位置、ErrorLocation→位置（同`src/core/defs.zig:1230`〜`src/core/defs.zig:1243`）。includeのfileidと入力位置は継承禁止である |
| T04 wrap_guard | P | Guard.previous→?*Guardで再帰しtarget/saved_actionは語IDを表す（`src/core/words_value_extensions.zig:10`）。invalidateは連鎖を書き換える（同`src/core/words_value_extensions.zig:27`）。nullから開始し、メインのZigスタック上のGuardも借用しない |
| T05 addresses | V・論理参照 | Registry→records:[capacity]Record、memory_order:[capacity]u16、件数・dirty。Record→kind/slot/value/target/status（`src/core/address_registry.zig:13`〜`src/core/address_registry.zig:26`）。未使用要素を読まずVMごとに再構成する |
| T06 frames / catches | 外側slice、内部V | CallFrameはpc/end/defining_word/locals_frame、CatchContinuationはCatchContextと深さ・locals_top（`src/forth.zig:1640`、`src/forth.zig:1651`）。CatchContext→CatchFrameと数値（`src/core/words_system.zig:89`）、CatchFrame→深さ・フラグ・next_name固定配列（`src/core/defs.zig:1271`）。メインのZig呼出し継続を保存する型ではない。CATCHは初期禁止である |
| T07 source_* | V | Navigationはpath固定配列・数値（`src/core/source_navigation.zig:9`）、Searchはpattern固定配列・enum・数値・optional（`src/core/source_search.zig:10`）、Modeはenum/optional/世代（`src/core/source_editor.zig:10`）、History→Entry固定配列・数値・optional（`src/core/source_diagnostics.zig:11`）。空slice/nullに置換する対象ではなく新規.{}を使う |
| T08 standard_input | V | Decoder→Legacy（key/bytes/count/event）、bytes、Packet（Cell/optional Mouse/reset）、bool、Mouse、optional Instant（`src/core/standard_event.zig:9`〜`src/core/standard_event.zig:29`）。Instantは整数（`src/core/runtime_base.zig:4`）。Source.context/read_fn/clockは別型でありWriter側で遮断する |
| T09 block_storage | V＋H | Storage→optional Cellのfile、read_only、Buffer固定配列、current。Bufferはnumber/modifiedだけで実データはmemory内block bufferにある（`src/core/blocks.zig:18`、`src/core/blocks.zig:41`）。ホストファイル表は別所有である |
| T10 execution | V | Control→Budget固定配列（remaining/unlimited）・depth・Stop union（none/cli/entry:usize）・until_poll、またはEmpty（`src/core/execution_control.zig:8`〜`src/core/execution_control.zig:16`）。ホストscopeはWriter.execution_ops側であり、652をworker取消しへ転用しない |
| T11 profile / lint | 外側P、参照先V | Profile→数値配列・Entry固定配列・件数（`src/core/profiler.zig:19`〜`src/core/profiler.zig:38`）。Lint→Declared/Effect/Depths固定配列・bool配列・work・数値（`src/core/lint.zig:38`〜`src/core/lint.zig:81`）。参照先が値だけでも外部可変領域の借用は禁止し初期nullとする |
| T12 capture_sink / sh_get_result | 外側P／論理参照 | Captured→buffer:Cell・length/capacity/count（`src/core/macro_substitute.zig:42`）。StringRef→address:Cell/length（`src/core/dynamic_strings.zig:16`）。外部CapturedポインターとVMヒープ論理アドレスを分け、双方をメインから持ち越さない |
| T13 gfx_* | 一部P、他V | Slot→pixels:[]u32・数値・optional Clip、Clipは座標だけ（`src/core/graphics_images.zig:36`〜`src/core/graphics_images.zig:52`）。FontState→buffer:[]u64、entries:[]const Entry、bits:[]const u8と数値、Entryは整数だけ（`src/core/graphics_font.zig:28`〜`src/core/graphics_font.zig:61`）。Alphaは固定長u8配列（同`src/core/graphics_font.zig:65`）、ColorModeはcolors/dither（`src/core/graphics_palette.zig:12`）、gfx_bandも固定長u8配列（`src/forth.zig:442`）。画像/font sliceを共有しない |
| T14 audio_* | V＋H | Voiceは数値/bool/enumだけ（`src/core/sound_mml.zig:52`）。Tone→Sample・Envelope→Segment固定配列・数値表（`src/core/sound_voice.zig:41`〜`src/core/sound_voice.zig:118`）。Sampleはpool内start/length/rate/loop位置（`src/core/sound_pcm.zig:20`）。poolやEngineへの参照はaudio_fnの戻り先にある（`src/core/sound_engine.zig:156`）。pool位置・番号・audio_pcm_handleも継承禁止である |
| T15 gfx_input | V | InputState→pending/keys/held/mouse_events固定配列、Shown/Key/Held/MouseEventの数値・enum・optional（`src/core/graphics_input.zig:35`〜`src/core/graphics_input.zig:93`、`src/core/graphics_input.zig:135`、`src/core/graphics_input.zig:280`）。Trackerポインターはないが未読入力・押下状態の継承は禁止する |
| T16 tcl | V＋H | TclState→program/input/header/固定結果配列、Text（Cellアドレス/length）、Text配列、optional Message（kind/code/Text/closes/fixed）と制御値（`src/core/tcl.zig:28`〜`src/core/tcl.zig:76`）。プロセス/pipeはWriterとホスト側にある。論理ヒープ参照の無効化と子停止を分ける |
| T17 gfx_displays / gamepads | V＋H | Display Snapshot→Display固定配列（id/矩形/倍率/Hz/primary）でsliceはない（`src/core/display_info.zig:16`〜`src/core/display_info.zig:33`）。gamepad Snapshot→Pad固定配列（id/axes/hats/name/guid等）（`src/core/gamepad.zig:6`〜`src/core/gamepad.zig:19`）。値でもホストIDの寿命を継承しない |

## Writer全フィールドとの対応（W表）

initは渡されたWriterをそのまま設定し、restore/restoreFreshはWriterを交換しない（`src/forth.zig:484`、`src/core/image_restore.zig:25`）。以下はworker構築側が満たすべき専用構成であり、製品コードに強制済みとはしない。全行のスレッド安全性の条件はO、禁止口はXでもある。メインWriterの値コピーを基準とせず必須context/write_fnだけを指定して作る。

const操作表はcontextの排他を保証しない。ExecutionOps.begin/poll/endはStateポインターも受ける。ProcessOps/FileOps/physical_keys.Ops/gamepad.Opsもcontextへ到達し、Clockはcontext/now_fnを持つ（`src/core/host_interface.zig:13`、`src/core/host_interface.zig:22`、`src/core/host_interface.zig:48`、`src/core/physical_keys.zig:216`、`src/core/gamepad.zig:20`、`src/core/runtime_base.zig:6`）。optional nullならこれらを保持せず辿らない。将来有効にする場合は引数・戻り値のsliceやEngineの所有寿命も別途監査する。

各行は既存共有監査の同名フィールドへ1対1で対応する。null時のfallback・エラー・無操作の詳細は参照先にある。nullだけではlegacy入力・端末描画・State直接操作を禁止できない（`docs/TASK_CONTROL_AUDIT_SHARED_STATE.md:91`〜`docs/TASK_CONTROL_AUDIT_SHARED_STATE.md:102`）。

| フィールド | 扱い | 条件 |
|---|---|---|
| `Writer.execution_ops` | null（P・X） | 型 `?*const ExecutionOps`、宣言 `null`（`src/core/host_interface.zig:187`）。init：専用構成で指定、復元：保持。begin/poll/endとcontextを借用しない。メインの信号scopeへ接続しない。State対応：writer→execution・in_counted・keep_counting・step_*。共有状態対応：host_wait / host_signal_broker / mainの実行scope・時計。既存監査W01：`docs/TASK_CONTROL_AUDIT_SHARED_STATE.md:17` |
| `Writer.audio_scope_ops` | null（P・X） | 型 `?*const ExecutionOps`、宣言 `null`（`src/core/host_interface.zig:189`）。init：専用構成で指定、復元：保持。begin/poll/endとcontextを借用しない。メインの信号scopeへ接続しない。State対応：writer→audio_pcm_handle・audio_voices・audio_instruments・audio_samples。共有状態対応：host_wait / host_signal_broker / mainの実行scope・時計。既存監査W02：`docs/TASK_CONTROL_AUDIT_SHARED_STATE.md:18` |
| `Writer.process_ops` | null（P・X） | 型 `?*const ProcessOps`、宣言 `null`（`src/core/host_interface.zig:190`）。init：専用構成で指定、復元：保持。new/text/io/start/stream/status/wait/signal/free全口とcontextを借用しない。State対応：writer→system_status・sh_get_result・source_navigation・memory/data_stack。共有状態対応：host_process / mainのprocess表・Tcl pipe・OSプロセス。既存監査W03：`docs/TASK_CONTROL_AUDIT_SHARED_STATE.md:19` |
| `Writer.physical_key_ops` | null（P・X） | 型 `?*const @import("physical_keys.zig").Ops`、宣言 `null`（`src/core/host_interface.zig:191`）。init：専用構成で指定、復元：保持。available/supported/held/next/resync/resetを借用せず、復元時resetも呼ばせない。997で定めたSCAN-INPUT?・SCAN-SUPPORTED?・SCAN-HELD?・KEY-EVENT・KEY-RESYNCを入力/UI禁止語として静的・動的検査へ含め、展開後Opも初期拒否する。State対応：writer→gfx_input・standard_input（復元resetはwriterから直接）。共有状態対応：host_input / host_window / host_display / host_display_budget / host_resize / mainの端末・入力・UI。既存監査W04：`docs/TASK_CONTROL_AUDIT_SHARED_STATE.md:20` |
| `Writer.gamepad_ops` | null（P・X） | 型 `?*const @import("gamepad.zig").Ops`、宣言 `null`（`src/core/host_interface.zig:192`）。init：専用構成で指定、復元：保持。poll/mappingとcontextを借用しない。State対応：writer→gamepads。共有状態対応：host_gamepad / host_evdev。既存監査W05：`docs/TASK_CONTROL_AUDIT_SHARED_STATE.md:21` |
| `Writer.context` | 専用context（P・O） | 型 `?*anyopaque`、宣言 `必須`（`src/core/host_interface.zig:193`）。init：専用構成で指定、復元：保持。専用出力・超過記録を所有し、メインHostを渡さない。State対応：writer→output_count・report_text/report_len・capture_*・output_file。共有状態対応：mainのoutput_buffer・log（専用出力で遮断）。既存監査W06：`docs/TASK_CONTROL_AUDIT_SHARED_STATE.md:22` |
| `Writer.write_fn` | 専用上限付き出力（P・O） | 型 `*const fn (?*anyopaque, []const u8) void`、宣言 `必須`（`src/core/host_interface.zig:194`）。init：専用構成で指定、復元：保持。必須関数。超過をcontextに記録し失敗へ変換する契約が必要である。State対応：writer→output_count・report_text/report_len・capture_*・output_file。共有状態対応：mainのoutput_buffer・log（専用出力で遮断）。既存監査W07：`docs/TASK_CONTROL_AUDIT_SHARED_STATE.md:23` |
| `Writer.log_fn` | null（P・X） | 型 `?*const fn (?*anyopaque, []const u8) void`、宣言 `null`（`src/core/host_interface.zig:196`）。init：専用構成で指定、復元：保持。optional参照を保持しない。語・Opも初期拒否する。State対応：writer→output_count・report_text/report_len・capture_*・output_file。共有状態対応：mainのoutput_buffer・log（専用出力で遮断）。既存監査W08：`docs/TASK_CONTROL_AUDIT_SHARED_STATE.md:24` |
| `Writer.read_fn` | null（P・X） | 型 `?*const fn (?*anyopaque, []u8) ?[]const u8`、宣言 `null`（`src/core/host_interface.zig:197`）。init：専用構成で指定、復元：保持。optional参照を保持しない。語・Opも初期拒否する。State対応：writer→input_file/output_file・include_stack・block_storage・source_line/source_kind。共有状態対応：host_input / host_window / host_display / host_display_budget / host_resize / mainの端末・入力・UI。既存監査W09：`docs/TASK_CONTROL_AUDIT_SHARED_STATE.md:25` |
| `Writer.load_fn` | null（P・X） | 型 `?*const fn (?*anyopaque, []const u8, *State) RuntimeError!void`、宣言 `null`（`src/core/host_interface.zig:198`）。init：専用構成で指定、復元：保持。optional参照を保持しない。語・Opも初期拒否する。State対応：writer→memory・words/code/names・addresses・image_generation（復元と保存）。共有状態対応：mainのopen_files / host_directories / 画像読込み・保存。既存監査W10：`docs/TASK_CONTROL_AUDIT_SHARED_STATE.md:26` |
| `Writer.save_fn` | null（P・X） | 型 `?*const fn (?*anyopaque, []const u8, *State) RuntimeError!void`、宣言 `null`（`src/core/host_interface.zig:199`）。init：専用構成で指定、復元：保持。optional参照を保持しない。語・Opも初期拒否する。State対応：writer→memory・words/code/names・addresses・image_generation（復元と保存）。共有状態対応：mainのopen_files / host_directories / 画像読込み・保存。既存監査W11：`docs/TASK_CONTROL_AUDIT_SHARED_STATE.md:27` |
| `Writer.savesys_fn` | null（P・X） | 型 `?*const fn (?*anyopaque, []const u8, *State) RuntimeError!void`、宣言 `null`（`src/core/host_interface.zig:200`）。init：専用構成で指定、復元：保持。optional参照を保持しない。語・Opも初期拒否する。State対応：writer→memory・words/code/names・addresses・image_generation（復元と保存）。共有状態対応：mainのopen_files / host_directories / 画像読込み・保存。既存監査W12：`docs/TASK_CONTROL_AUDIT_SHARED_STATE.md:28` |
| `Writer.key_fn` | null（P・X） | 型 `?*const fn (?*anyopaque) ?u8`、宣言 `null`（`src/core/host_interface.zig:201`）。init：専用構成で指定、復元：保持。optional参照を保持しない。語・Opも初期拒否する。State対応：writer→standard_input・pending_*・gfx_input・source_line/source_kind・input_file・output_count（入力・端末・待機）。共有状態対応：host_input / host_window / host_display / host_display_budget / host_resize / mainの端末・入力・UI。既存監査W13：`docs/TASK_CONTROL_AUDIT_SHARED_STATE.md:29` |
| `Writer.key_ior_fn` | null（P・X） | 型 `?*const fn (?*anyopaque) RuntimeError!FileKeyResult`、宣言 `null`（`src/core/host_interface.zig:203`）。init：専用構成で指定、復元：保持。optional参照を保持しない。語・Opも初期拒否する。State対応：writer→standard_input・pending_*・gfx_input・source_line/source_kind・input_file・output_count（入力・端末・待機）。共有状態対応：host_input / host_window / host_display / host_display_budget / host_resize / mainの端末・入力・UI。既存監査W14：`docs/TASK_CONTROL_AUDIT_SHARED_STATE.md:30` |
| `Writer.monotonic_ms_fn` | null（P・X） | 型 `?*const fn (?*anyopaque) i64`、宣言 `null`（`src/core/host_interface.zig:205`）。init：専用構成で指定、復元：保持。optional参照を保持しない。語・Opも初期拒否する。State対応：writer→standard_input・pending_*・gfx_input・source_line/source_kind・input_file・output_count（入力・端末・待機）。共有状態対応：host_input / host_window / host_display / host_display_budget / host_resize / mainの端末・入力・UI。既存監査W15：`docs/TASK_CONTROL_AUDIT_SHARED_STATE.md:31` |
| `Writer.event_key_fn` | null（P・X） | 型 `?*const fn (?*anyopaque, i32) RuntimeError!?Cell`、宣言 `null`（`src/core/host_interface.zig:207`）。init：専用構成で指定、復元：保持。optional参照を保持しない。語・Opも初期拒否する。State対応：writer→standard_input・pending_*・gfx_input・source_line/source_kind・input_file・output_count（入力・端末・待機）。共有状態対応：host_input / host_window / host_display / host_display_budget / host_resize / mainの端末・入力・UI。既存監査W16：`docs/TASK_CONTROL_AUDIT_SHARED_STATE.md:32` |
| `Writer.standard_event_fn` | null（P・X） | 型 `?*const fn (?*anyopaque, i32) RuntimeError!@import("standard_event.zig").Result`、宣言 `null`（`src/core/host_interface.zig:210`）。init：専用構成で指定、復元：保持。optional参照を保持しない。語・Opも初期拒否する。State対応：writer→standard_input・pending_standard_event・audio_pcm_handle。共有状態対応：host_input / host_window / host_display / host_display_budget / host_resize / mainの端末・入力・UI。既存監査W17：`docs/TASK_CONTROL_AUDIT_SHARED_STATE.md:33` |
| `Writer.standard_clock` | null（P・X） | 型 `?@import("runtime_base.zig").Clock`、宣言 `null`（`src/core/host_interface.zig:211`）。init：専用構成で指定、復元：保持。Clock.context/now_fnを含め借用しない。State対応：writer→standard_input・pending_standard_event・audio_pcm_handle。共有状態対応：host_wait / host_signal_broker / mainの実行scope・時計。既存監査W18：`docs/TASK_CONTROL_AUDIT_SHARED_STATE.md:34` |
| `Writer.standard_interrupts` | false（V・X） | 型 `bool`、宣言 `false`（`src/core/host_interface.zig:212`）。init：専用構成で指定、復元：保持。boolであり入力禁止を表す値ではない。State対応：writer→standard_input・pending_standard_event・audio_pcm_handle。共有状態対応：host_input / host_window / host_display / host_display_budget / host_resize / mainの端末・入力・UI。既存監査W19：`docs/TASK_CONTROL_AUDIT_SHARED_STATE.md:35` |
| `Writer.buffered_key_fn` | null（P・X） | 型 `?*const fn (?*anyopaque) RuntimeError!?u8`、宣言 `null`（`src/core/host_interface.zig:215`）。init：専用構成で指定、復元：保持。optional参照を保持しない。語・Opも初期拒否する。State対応：writer→standard_input・pending_*・gfx_input・source_line/source_kind・input_file・output_count（入力・端末・待機）。共有状態対応：host_input / host_window / host_display / host_display_budget / host_resize / mainの端末・入力・UI。既存監査W20：`docs/TASK_CONTROL_AUDIT_SHARED_STATE.md:36` |
| `Writer.key_ready_fn` | null（P・X） | 型 `?*const fn (?*anyopaque) bool`、宣言 `null`（`src/core/host_interface.zig:216`）。init：専用構成で指定、復元：保持。optional参照を保持しない。語・Opも初期拒否する。State対応：writer→standard_input・pending_*・gfx_input・source_line/source_kind・input_file・output_count（入力・端末・待機）。共有状態対応：host_input / host_window / host_display / host_display_budget / host_resize / mainの端末・入力・UI。既存監査W21：`docs/TASK_CONTROL_AUDIT_SHARED_STATE.md:37` |
| `Writer.unread_fn` | null（P・X） | 型 `?*const fn (?*anyopaque, u8) void`、宣言 `null`（`src/core/host_interface.zig:221`）。init：専用構成で指定、復元：保持。optional参照を保持しない。語・Opも初期拒否する。State対応：writer→standard_input・pending_*・gfx_input・source_line/source_kind・input_file・output_count（入力・端末・待機）。共有状態対応：host_input / host_window / host_display / host_display_budget / host_resize / mainの端末・入力・UI。既存監査W22：`docs/TASK_CONTROL_AUDIT_SHARED_STATE.md:38` |
| `Writer.unread_byte_fn` | null（P・X） | 型 `?*const fn (?*anyopaque, u8) RuntimeError!void`、宣言 `null`（`src/core/host_interface.zig:223`）。init：専用構成で指定、復元：保持。optional参照を保持しない。語・Opも初期拒否する。State対応：writer→standard_input・pending_*・gfx_input・source_line/source_kind・input_file・output_count（入力・端末・待機）。共有状態対応：host_input / host_window / host_display / host_display_budget / host_resize / mainの端末・入力・UI。既存監査W23：`docs/TASK_CONTROL_AUDIT_SHARED_STATE.md:39` |
| `Writer.sleep_fn` | null（P・X） | 型 `?*const fn (?*anyopaque, Cell) RuntimeError!void`、宣言 `null`（`src/core/host_interface.zig:224`）。init：専用構成で指定、復元：保持。optional参照を保持しない。語・Opも初期拒否する。State対応：writer→standard_input・pending_*・gfx_input・source_line/source_kind・input_file・output_count（入力・端末・待機）。共有状態対応：host_wait / host_signal_broker / mainの実行scope・時計。既存監査W24：`docs/TASK_CONTROL_AUDIT_SHARED_STATE.md:40` |
| `Writer.sleep_ns_fn` | null（P・X） | 型 `?*const fn (?*anyopaque, Double) RuntimeError!void`、宣言 `null`（`src/core/host_interface.zig:226`）。init：専用構成で指定、復元：保持。optional参照を保持しない。語・Opも初期拒否する。State対応：writer→standard_input・pending_*・gfx_input・source_line/source_kind・input_file・output_count（入力・端末・待機）。共有状態対応：host_wait / host_signal_broker / mainの実行scope・時計。既存監査W25：`docs/TASK_CONTROL_AUDIT_SHARED_STATE.md:41` |
| `Writer.utime_fn` | null（P・X） | 型 `?*const fn (?*anyopaque) RuntimeError!Double`、宣言 `null`（`src/core/host_interface.zig:228`）。init：専用構成で指定、復元：保持。optional参照を保持しない。語・Opも初期拒否する。State対応：writer→random_state（utimeのinit）・memory/data_stack（返却値）。共有状態対応：main / C・OSの時刻・環境・errno。既存監査W26：`docs/TASK_CONTROL_AUDIT_SHARED_STATE.md:42` |
| `Writer.ntime_fn` | null（P・X） | 型 `?*const fn (?*anyopaque) RuntimeError!Double`、宣言 `null`（`src/core/host_interface.zig:230`）。init：専用構成で指定、復元：保持。optional参照を保持しない。語・Opも初期拒否する。State対応：writer→random_state（utimeのinit）・memory/data_stack（返却値）。共有状態対応：main / C・OSの時刻・環境・errno。既存監査W27：`docs/TASK_CONTROL_AUDIT_SHARED_STATE.md:43` |
| `Writer.cputime_fn` | null（P・X） | 型 `?*const fn (?*anyopaque) RuntimeError!CpuTimes`、宣言 `null`（`src/core/host_interface.zig:232`）。init：専用構成で指定、復元：保持。optional参照を保持しない。語・Opも初期拒否する。State対応：writer→random_state（utimeのinit）・memory/data_stack（返却値）。共有状態対応：main / C・OSの時刻・環境・errno。既存監査W28：`docs/TASK_CONTROL_AUDIT_SHARED_STATE.md:44` |
| `Writer.local_time_fn` | null（P・X） | 型 `?*const fn (?*anyopaque) RuntimeError!LocalTime`、宣言 `null`（`src/core/host_interface.zig:233`）。init：専用構成で指定、復元：保持。optional参照を保持しない。語・Opも初期拒否する。State対応：writer→random_state（utimeのinit）・memory/data_stack（返却値）。共有状態対応：main / C・OSの時刻・環境・errno。既存監査W29：`docs/TASK_CONTROL_AUDIT_SHARED_STATE.md:45` |
| `Writer.zoned_time_fn` | null（P・X） | 型 `?*const fn (?*anyopaque, Double, []u8) RuntimeError!ZonedTime`、宣言 `null`（`src/core/host_interface.zig:235`）。init：専用構成で指定、復元：保持。optional参照を保持しない。語・Opも初期拒否する。State対応：writer→random_state（utimeのinit）・memory/data_stack（返却値）。共有状態対応：main / C・OSの時刻・環境・errno。既存監査W30：`docs/TASK_CONTROL_AUDIT_SHARED_STATE.md:46` |
| `Writer.getenv_fn` | null（P・X） | 型 `?*const fn (?*anyopaque, []const u8, []u8) RuntimeError!?usize`、宣言 `null`（`src/core/host_interface.zig:237`）。init：専用構成で指定、復元：保持。optional参照を保持しない。語・Opも初期拒否する。State対応：writer→random_state（utimeのinit）・memory/data_stack（返却値）。共有状態対応：main / C・OSの時刻・環境・errno。既存監査W31：`docs/TASK_CONTROL_AUDIT_SHARED_STATE.md:47` |
| `Writer.errno_fn` | null（P・X） | 型 `?*const fn (?*anyopaque) Cell`、宣言 `null`（`src/core/host_interface.zig:239`）。init：専用構成で指定、復元：保持。optional参照を保持しない。語・Opも初期拒否する。State対応：writer→random_state（utimeのinit）・memory/data_stack（返却値）。共有状態対応：main / C・OSの時刻・環境・errno。既存監査W32：`docs/TASK_CONTROL_AUDIT_SHARED_STATE.md:48` |
| `Writer.system_fn` | null（P・X） | 型 `?*const fn (?*anyopaque, []const u8) RuntimeError!Cell`、宣言 `null`（`src/core/host_interface.zig:241`）。init：専用構成で指定、復元：保持。optional参照を保持しない。語・Opも初期拒否する。State対応：writer→system_status・sh_get_result・source_navigation・memory/data_stack。共有状態対応：host_process / mainのprocess表・Tcl pipe・OSプロセス。既存監査W33：`docs/TASK_CONTROL_AUDIT_SHARED_STATE.md:49` |
| `Writer.editor_fn` | null（P・X） | 型 `?*const fn (?*anyopaque, EditorRequest) RuntimeError!void`、宣言 `null`（`src/core/host_interface.zig:243`）。init：専用構成で指定、復元：保持。optional参照を保持しない。語・Opも初期拒否する。State対応：writer→system_status・sh_get_result・source_navigation・memory/data_stack。共有状態対応：mainのeditor処理・ファイル／外部プロセス。既存監査W34：`docs/TASK_CONTROL_AUDIT_SHARED_STATE.md:50` |
| `Writer.file_ops` | null（P・X） | 型 `?*const FileOps`、宣言 `null`（`src/core/host_interface.zig:244`）。init：専用構成で指定、復元：保持。全FileOps callbackを借用せず、OwnedPath.bytes等の戻りsliceも移転しない。State対応：writer→input_file/output_file・include_stack・block_storage・source_line/source_kind。共有状態対応：mainのopen_files / host_directories / 画像読込み・保存。既存監査W35：`docs/TASK_CONTROL_AUDIT_SHARED_STATE.md:51` |
| `Writer.framebuffer_fn` | null（P・X） | 型 `?*const fn (?*anyopaque, usize) ?[]u32`、宣言 `null`（`src/core/host_interface.zig:249`）。init：専用構成で指定、復元：保持。optional参照を保持しない。語・Opも初期拒否する。State対応：writer→gfx_pixels・gfx_images・gfx_images_bytes・gfx_target。共有状態対応：mainのframebuffer・画像pool。既存監査W36：`docs/TASK_CONTROL_AUDIT_SHARED_STATE.md:52` |
| `Writer.image_alloc_fn` | null（P・X） | 型 `?*const fn (?*anyopaque, usize) ?[]u32`、宣言 `null`（`src/core/host_interface.zig:253`）。init：専用構成で指定、復元：保持。optional参照を保持しない。語・Opも初期拒否する。State対応：writer→gfx_pixels・gfx_images・gfx_images_bytes・gfx_target。共有状態対応：mainのframebuffer・画像pool。既存監査W37：`docs/TASK_CONTROL_AUDIT_SHARED_STATE.md:53` |
| `Writer.image_free_fn` | null（P・X） | 型 `?*const fn (?*anyopaque, []u32) void`、宣言 `null`（`src/core/host_interface.zig:255`）。init：専用構成で指定、復元：保持。optional参照を保持しない。語・Opも初期拒否する。State対応：writer→gfx_pixels・gfx_images・gfx_images_bytes・gfx_target。共有状態対応：mainのframebuffer・画像pool。既存監査W38：`docs/TASK_CONTROL_AUDIT_SHARED_STATE.md:54` |
| `Writer.terminal_size_fn` | null（P・X） | 型 `?*const fn (?*anyopaque) ?TerminalSize`、宣言 `null`（`src/core/host_interface.zig:258`）。init：専用構成で指定、復元：保持。optional参照を保持しない。語・Opも初期拒否する。State対応：writer→standard_input・pending_*・gfx_input・source_line/source_kind・input_file・output_count（入力・端末・待機）。共有状態対応：host_input / host_window / host_display / host_display_budget / host_resize / mainの端末・入力・UI。既存監査W39：`docs/TASK_CONTROL_AUDIT_SHARED_STATE.md:55` |
| `Writer.terminal_mode_set_fn` | null（P・X） | 型 `?*const fn (?*anyopaque, u8) Cell`、宣言 `null`（`src/core/host_interface.zig:260`）。init：専用構成で指定、復元：保持。optional参照を保持しない。語・Opも初期拒否する。State対応：writer→standard_input・pending_*・gfx_input・source_line/source_kind・input_file・output_count（入力・端末・待機）。共有状態対応：host_input / host_window / host_display / host_display_budget / host_resize / mainの端末・入力・UI。既存監査W40：`docs/TASK_CONTROL_AUDIT_SHARED_STATE.md:56` |
| `Writer.terminal_mode_get_fn` | null（P・X） | 型 `?*const fn (?*anyopaque) u8`、宣言 `null`（`src/core/host_interface.zig:261`）。init：専用構成で指定、復元：保持。optional参照を保持しない。語・Opも初期拒否する。State対応：writer→standard_input・pending_*・gfx_input・source_line/source_kind・input_file・output_count（入力・端末・待機）。共有状態対応：host_input / host_window / host_display / host_display_budget / host_resize / mainの端末・入力・UI。既存監査W41：`docs/TASK_CONTROL_AUDIT_SHARED_STATE.md:57` |
| `Writer.input_error_fn` | null（P・X） | 型 `?*const fn (?*anyopaque) RuntimeError!void`、宣言 `null`（`src/core/host_interface.zig:263`）。init：専用構成で指定、復元：保持。optional参照を保持しない。語・Opも初期拒否する。State対応：writer→standard_input・pending_*・gfx_input・source_line/source_kind・input_file・output_count（入力・端末・待機）。共有状態対応：host_input / host_window / host_display / host_display_budget / host_resize / mainの端末・入力・UI。既存監査W42：`docs/TASK_CONTROL_AUDIT_SHARED_STATE.md:58` |
| `Writer.terminal_utf8_fn` | null（P・X） | 型 `?*const fn (?*anyopaque, bool) void`、宣言 `null`（`src/core/host_interface.zig:268`）。init：専用構成で指定、復元：保持。optional参照を保持しない。語・Opも初期拒否する。State対応：writer→standard_input・pending_*・gfx_input・source_line/source_kind・input_file・output_count（入力・端末・待機）。共有状態対応：host_input / host_window / host_display / host_display_budget / host_resize / mainの端末・入力・UI。既存監査W43：`docs/TASK_CONTROL_AUDIT_SHARED_STATE.md:59` |
| `Writer.display_budget_fn` | null（P・X） | 型 `?*const fn (?*anyopaque, bool) void`、宣言 `null`（`src/core/host_interface.zig:271`）。init：専用構成で指定、復元：保持。optional参照を保持しない。語・Opも初期拒否する。State対応：writer→gfx_window_*・gfx_displays・gfx_input・gfx_fullscreen・gfx_cursor_visible・tcl。共有状態対応：host_input / host_window / host_display / host_display_budget / host_resize / mainの端末・入力・UI。既存監査W44：`docs/TASK_CONTROL_AUDIT_SHARED_STATE.md:60` |
| `Writer.window_fn` | null（P・X） | 型 `?*const fn (?*anyopaque, []const u32, u32, u32, ColorMode, [2]u32) RuntimeError!void`、宣言 `null`（`src/core/host_interface.zig:278`）。init：専用構成で指定、復元：保持。optional参照を保持しない。語・Opも初期拒否する。State対応：writer→gfx_window_*・gfx_displays・gfx_input・gfx_fullscreen・gfx_cursor_visible・tcl。共有状態対応：host_input / host_window / host_display / host_display_budget / host_resize / mainの端末・入力・UI。既存監査W45：`docs/TASK_CONTROL_AUDIT_SHARED_STATE.md:61` |
| `Writer.ime_preedit_fn` | null（P・X） | 型 `?*const fn (?*anyopaque, []u8) RuntimeError!usize`、宣言 `null`（`src/core/host_interface.zig:282`）。init：専用構成で指定、復元：保持。optional参照を保持しない。語・Opも初期拒否する。State対応：writer→gfx_window_*・gfx_displays・gfx_input・gfx_fullscreen・gfx_cursor_visible・tcl。共有状態対応：host_input / host_window / host_display / host_display_budget / host_resize / mainの端末・入力・UI。既存監査W46：`docs/TASK_CONTROL_AUDIT_SHARED_STATE.md:62` |
| `Writer.ime_caret_fn` | null（P・X） | 型 `?*const fn (?*anyopaque, bool, Cell, Cell, Cell) RuntimeError!void`、宣言 `null`（`src/core/host_interface.zig:285`）。init：専用構成で指定、復元：保持。optional参照を保持しない。語・Opも初期拒否する。State対応：writer→gfx_window_*・gfx_displays・gfx_input・gfx_fullscreen・gfx_cursor_visible・tcl。共有状態対応：host_input / host_window / host_display / host_display_budget / host_resize / mainの端末・入力・UI。既存監査W47：`docs/TASK_CONTROL_AUDIT_SHARED_STATE.md:63` |
| `Writer.window_fullscreen_fn` | null（P・X） | 型 `?*const fn (?*anyopaque, i8) RuntimeError!bool`、宣言 `null`（`src/core/host_interface.zig:290`）。init：専用構成で指定、復元：保持。optional参照を保持しない。語・Opも初期拒否する。State対応：writer→gfx_window_*・gfx_displays・gfx_input・gfx_fullscreen・gfx_cursor_visible・tcl。共有状態対応：host_input / host_window / host_display / host_display_budget / host_resize / mainの端末・入力・UI。既存監査W48：`docs/TASK_CONTROL_AUDIT_SHARED_STATE.md:64` |
| `Writer.window_cursor_fn` | null（P・X） | 型 `?*const fn (?*anyopaque, bool) RuntimeError!void`、宣言 `null`（`src/core/host_interface.zig:292`）。init：専用構成で指定、復元：保持。optional参照を保持しない。語・Opも初期拒否する。State対応：writer→gfx_window_*・gfx_displays・gfx_input・gfx_fullscreen・gfx_cursor_visible・tcl。共有状態対応：host_input / host_window / host_display / host_display_budget / host_resize / mainの端末・入力・UI。既存監査W49：`docs/TASK_CONTROL_AUDIT_SHARED_STATE.md:65` |
| `Writer.displays_fn` | null（P・X） | 型 `?*const fn (?*anyopaque, *@import("display_info.zig").Snapshot) void`、宣言 `null`（`src/core/host_interface.zig:296`）。init：専用構成で指定、復元：保持。optional参照を保持しない。語・Opも初期拒否する。State対応：writer→gfx_window_*・gfx_displays・gfx_input・gfx_fullscreen・gfx_cursor_visible・tcl。共有状態対応：host_input / host_window / host_display / host_display_budget / host_resize / mainの端末・入力・UI。既存監査W50：`docs/TASK_CONTROL_AUDIT_SHARED_STATE.md:66` |
| `Writer.window_display_fn` | null（P・X） | 型 `?*const fn (?*anyopaque, u64) ?u64`、宣言 `null`（`src/core/host_interface.zig:301`）。init：専用構成で指定、復元：保持。optional参照を保持しない。語・Opも初期拒否する。State対応：writer→gfx_window_*・gfx_displays・gfx_input・gfx_fullscreen・gfx_cursor_visible・tcl。共有状態対応：host_input / host_window / host_display / host_display_budget / host_resize / mainの端末・入力・UI。既存監査W51：`docs/TASK_CONTROL_AUDIT_SHARED_STATE.md:67` |
| `Writer.window_state_fn` | null（P・X） | 型 `?*const fn (?*anyopaque) @import("display_info.zig").WindowState`、宣言 `null`（`src/core/host_interface.zig:304`）。init：専用構成で指定、復元：保持。optional参照を保持しない。語・Opも初期拒否する。State対応：writer→gfx_window_*・gfx_displays・gfx_input・gfx_fullscreen・gfx_cursor_visible・tcl。共有状態対応：host_input / host_window / host_display / host_display_budget / host_resize / mainの端末・入力・UI。既存監査W52：`docs/TASK_CONTROL_AUDIT_SHARED_STATE.md:68` |
| `Writer.window_size_fn` | null（P・X） | 型 `?*const fn (?*anyopaque, u64) ?[2]u32`、宣言 `null`（`src/core/host_interface.zig:309`）。init：専用構成で指定、復元：保持。optional参照を保持しない。語・Opも初期拒否する。State対応：writer→gfx_window_*・gfx_displays・gfx_input・gfx_fullscreen・gfx_cursor_visible・tcl。共有状態対応：host_input / host_window / host_display / host_display_budget / host_resize / mainの端末・入力・UI。既存監査W53：`docs/TASK_CONTROL_AUDIT_SHARED_STATE.md:69` |
| `Writer.window_minimized_fn` | null（P・X） | 型 `?*const fn (?*anyopaque, u64) ?bool`、宣言 `null`（`src/core/host_interface.zig:311`）。init：専用構成で指定、復元：保持。optional参照を保持しない。語・Opも初期拒否する。State対応：writer→gfx_window_*・gfx_displays・gfx_input・gfx_fullscreen・gfx_cursor_visible・tcl。共有状態対応：host_input / host_window / host_display / host_display_budget / host_resize / mainの端末・入力・UI。既存監査W54：`docs/TASK_CONTROL_AUDIT_SHARED_STATE.md:70` |
| `Writer.window_fit_fn` | null（P・X） | 型 `?*const fn (?*anyopaque, u8) void`、宣言 `null`（`src/core/host_interface.zig:315`）。init：専用構成で指定、復元：保持。optional参照を保持しない。語・Opも初期拒否する。State対応：writer→gfx_window_*・gfx_displays・gfx_input・gfx_fullscreen・gfx_cursor_visible・tcl。共有状態対応：host_input / host_window / host_display / host_display_budget / host_resize / mainの端末・入力・UI。既存監査W55：`docs/TASK_CONTROL_AUDIT_SHARED_STATE.md:71` |
| `Writer.window_place_fn` | null（P・X） | 型 `?*const fn (?*anyopaque, u64) void`、宣言 `null`（`src/core/host_interface.zig:322`）。init：専用構成で指定、復元：保持。optional参照を保持しない。語・Opも初期拒否する。State対応：writer→gfx_window_*・gfx_displays・gfx_input・gfx_fullscreen・gfx_cursor_visible・tcl。共有状態対応：host_input / host_window / host_display / host_display_budget / host_resize / mainの端末・入力・UI。既存監査W56：`docs/TASK_CONTROL_AUDIT_SHARED_STATE.md:72` |
| `Writer.window_close_fn` | null（P・X） | 型 `?*const fn (?*anyopaque, u8) u64`、宣言 `null`（`src/core/host_interface.zig:328`）。init：専用構成で指定、復元：保持。optional参照を保持しない。語・Opも初期拒否する。State対応：writer→gfx_window_*・gfx_displays・gfx_input・gfx_fullscreen・gfx_cursor_visible・tcl。共有状態対応：host_input / host_window / host_display / host_display_budget / host_resize / mainの端末・入力・UI。既存監査W57：`docs/TASK_CONTROL_AUDIT_SHARED_STATE.md:73` |
| `Writer.window_smooth_fn` | null（P・X） | 型 `?*const fn (?*anyopaque, bool) void`、宣言 `null`（`src/core/host_interface.zig:331`）。init：専用構成で指定、復元：保持。optional参照を保持しない。語・Opも初期拒否する。State対応：writer→gfx_window_*・gfx_displays・gfx_input・gfx_fullscreen・gfx_cursor_visible・tcl。共有状態対応：host_input / host_window / host_display / host_display_budget / host_resize / mainの端末・入力・UI。既存監査W58：`docs/TASK_CONTROL_AUDIT_SHARED_STATE.md:74` |
| `Writer.window_wait_fn` | null（P・X） | 型 `?*const fn (?*anyopaque, u8, u32) bool`、宣言 `null`（`src/core/host_interface.zig:338`）。init：専用構成で指定、復元：保持。optional参照を保持しない。語・Opも初期拒否する。State対応：writer→gfx_window_*・gfx_displays・gfx_input・gfx_fullscreen・gfx_cursor_visible・tcl。共有状態対応：host_input / host_window / host_display / host_display_budget / host_resize / mainの端末・入力・UI。既存監査W59：`docs/TASK_CONTROL_AUDIT_SHARED_STATE.md:75` |
| `Writer.input_fn` | null（P・X） | 型 `?*const fn (?*anyopaque) ?InputEvent`、宣言 `null`（`src/core/host_interface.zig:343`）。init：専用構成で指定、復元：保持。optional参照を保持しない。語・Opも初期拒否する。State対応：writer→standard_input・pending_*・gfx_input・source_line/source_kind・input_file・output_count（入力・端末・待機）。共有状態対応：host_input / host_window / host_display / host_display_budget / host_resize / mainの端末・入力・UI。既存監査W60：`docs/TASK_CONTROL_AUDIT_SHARED_STATE.md:76` |
| `Writer.mouse_fn` | null（P・X） | 型 `?*const fn (?*anyopaque, bool) void`、宣言 `null`（`src/core/host_interface.zig:346`）。init：専用構成で指定、復元：保持。optional参照を保持しない。語・Opも初期拒否する。State対応：writer→standard_input・pending_*・gfx_input・source_line/source_kind・input_file・output_count（入力・端末・待機）。共有状態対応：host_input / host_window / host_display / host_display_budget / host_resize / mainの端末・入力・UI。既存監査W61：`docs/TASK_CONTROL_AUDIT_SHARED_STATE.md:77` |
| `Writer.cursor_fn` | null（P・X） | 型 `?*const fn (?*anyopaque) ?CursorPosition`、宣言 `null`（`src/core/host_interface.zig:349`）。init：専用構成で指定、復元：保持。optional参照を保持しない。語・Opも初期拒否する。State対応：writer→standard_input・pending_*・gfx_input・source_line/source_kind・input_file・output_count（入力・端末・待機）。共有状態対応：host_input / host_window / host_display / host_display_budget / host_resize / mainの端末・入力・UI。既存監査W62：`docs/TASK_CONTROL_AUDIT_SHARED_STATE.md:78` |
| `Writer.font_buffer_fn` | null（P・X） | 型 `?*const fn (?*anyopaque, usize) ?[]u64`、宣言 `null`（`src/core/host_interface.zig:353`）。init：専用構成で指定、復元：保持。optional参照を保持しない。語・Opも初期拒否する。State対応：writer→gfx_font・gfx_glyph_alpha。共有状態対応：host_font / mainのfont領域。既存監査W63：`docs/TASK_CONTROL_AUDIT_SHARED_STATE.md:79` |
| `Writer.font_free_fn` | null（P・X） | 型 `?*const fn (?*anyopaque, []u64) void`、宣言 `null`（`src/core/host_interface.zig:355`）。init：専用構成で指定、復元：保持。optional参照を保持しない。語・Opも初期拒否する。State対応：writer→gfx_font・gfx_glyph_alpha。共有状態対応：host_font / mainのfont領域。既存監査W64：`docs/TASK_CONTROL_AUDIT_SHARED_STATE.md:80` |
| `Writer.process_start_fn` | null（P・X） | 型 `?*const fn (?*anyopaque, []const u8, []const u8) RuntimeError!void`、宣言 `null`（`src/core/host_interface.zig:359`）。init：専用構成で指定、復元：保持。optional参照を保持しない。語・Opも初期拒否する。State対応：writer→tcl・gfx_input。共有状態対応：host_process / mainのprocess表・Tcl pipe・OSプロセス。既存監査W65：`docs/TASK_CONTROL_AUDIT_SHARED_STATE.md:81` |
| `Writer.process_write_fn` | null（P・X） | 型 `?*const fn (?*anyopaque, []const u8) RuntimeError!void`、宣言 `null`（`src/core/host_interface.zig:361`）。init：専用構成で指定、復元：保持。optional参照を保持しない。語・Opも初期拒否する。State対応：writer→tcl・gfx_input。共有状態対応：host_process / mainのprocess表・Tcl pipe・OSプロセス。既存監査W66：`docs/TASK_CONTROL_AUDIT_SHARED_STATE.md:82` |
| `Writer.process_read_fn` | null（P・X） | 型 `?*const fn (?*anyopaque, []u8, bool) RuntimeError!usize`、宣言 `null`（`src/core/host_interface.zig:365`）。init：専用構成で指定、復元：保持。optional参照を保持しない。語・Opも初期拒否する。State対応：writer→tcl・gfx_input。共有状態対応：host_process / mainのprocess表・Tcl pipe・OSプロセス。既存監査W67：`docs/TASK_CONTROL_AUDIT_SHARED_STATE.md:83` |
| `Writer.process_stop_fn` | null（P・X） | 型 `?*const fn (?*anyopaque) bool`、宣言 `null`（`src/core/host_interface.zig:368`）。init：専用構成で指定、復元：保持。optional参照を保持しない。語・Opも初期拒否する。State対応：writer→tcl・gfx_input。共有状態対応：host_process / mainのprocess表・Tcl pipe・OSプロセス。既存監査W68：`docs/TASK_CONTROL_AUDIT_SHARED_STATE.md:84` |
| `Writer.system_font_fn` | null（P・X） | 型 `?*const fn (?*anyopaque, []const u8, u32) RuntimeError!bool`、宣言 `null`（`src/core/host_interface.zig:371`）。init：専用構成で指定、復元：保持。optional参照を保持しない。語・Opも初期拒否する。State対応：writer→gfx_font・gfx_glyph_alpha。共有状態対応：host_font / mainのfont領域。既存監査W69：`docs/TASK_CONTROL_AUDIT_SHARED_STATE.md:85` |
| `Writer.system_glyph_fn` | null（P・X） | 型 `?*const fn (?*anyopaque, u21, []u8, u32) ?SystemGlyph`、宣言 `null`（`src/core/host_interface.zig:375`）。init：専用構成で指定、復元：保持。optional参照を保持しない。語・Opも初期拒否する。State対応：writer→gfx_font・gfx_glyph_alpha。共有状態対応：host_font / mainのfont領域。既存監査W70：`docs/TASK_CONTROL_AUDIT_SHARED_STATE.md:86` |
| `Writer.audio_fn` | null（P・X） | 型 `?*const fn (?*anyopaque) ?*@import("sound_engine.zig").Engine`、宣言 `null`（`src/core/host_interface.zig:379`）。init：専用構成で指定、復元：保持。optional参照を保持しない。語・Opも初期拒否する。State対応：writer→audio_pcm_handle・audio_voices・audio_instruments・audio_samples。共有状態対応：host_audio / Engine・PCM Session。既存監査W71：`docs/TASK_CONTROL_AUDIT_SHARED_STATE.md:87` |
| `Writer.audio_device_fn` | null（P・X） | 型 `?*const fn (?*anyopaque) bool`、宣言 `null`（`src/core/host_interface.zig:381`）。init：専用構成で指定、復元：保持。optional参照を保持しない。語・Opも初期拒否する。State対応：writer→audio_pcm_handle・audio_voices・audio_instruments・audio_samples。共有状態対応：host_audio / Engine・PCM Session。既存監査W72：`docs/TASK_CONTROL_AUDIT_SHARED_STATE.md:88` |
| `Writer.audio_wait_fn` | null（P・X） | 型 `?*const fn (?*anyopaque) AudioWait`、宣言 `null`（`src/core/host_interface.zig:384`）。init：専用構成で指定、復元：保持。optional参照を保持しない。語・Opも初期拒否する。State対応：writer→audio_pcm_handle・audio_voices・audio_instruments・audio_samples。共有状態対応：host_audio / Engine・PCM Session。既存監査W73：`docs/TASK_CONTROL_AUDIT_SHARED_STATE.md:89` |


## ホスト側の監査と禁止条件

| 領域 | 初期方針と試験 |
|---|---|
| Writer.context / write_fn | 専用出力・超過記録を用いmainのoutput_buffer・ファイル表・ログを使わない。出力側と回収側の公開同期も必要である（`docs/CORE_EXTENSION_DETAILED_DESIGN.md:802`、`docs/TASK_CONTROL_AUDIT_SHARED_STATE.md:22`） |
| 入力・時計・信号 | standard_input/gfx_inputは値でもWriterの入力口・Clock・ExecutionOpsからhost_input/host_wait/host_signal_broker/mainへ到達する。全口null＋入力語拒否で遮断し独立取消しを使う。modern_depthはState外の非atomic共有変数（`src/core/event_input.zig:154`）。workerが入力を使わなくてもメインExecutionOpsを渡してはならない（`docs/TASK_CONTROL_AUDIT_SHARED_STATE.md:562`） |
| ファイル・block・プロセス | input_file/output_file/include_stack/block_storageは整数IDを含む。file_ops/process_ops/process_*からmain・host_directories・host_processの表へ接続しない。復元memory中のSTDIN等のセルも語・領域検査なしには安全としない（`docs/TASK_CONTROL_AUDIT_SHARED_STATE.md:104`、`docs/TASK_CONTROL_AUDIT_ALLOWED_SET.md:22`） |
| 画像・font・表示・機器 | gfx_pixels/gfx_images/gfx_fontのsliceを共有しない。gfx_displays/gamepadsは値でもホストIDを継承せず関連語を拒否する。host_windowの各OSとwin32.Vsync、host_display/host_resize/host_font/host_gamepad/host_evdevの共有状態はホスト所有のままである（`docs/TASK_CONTROL_AUDIT_SHARED_STATE.md:128`、`docs/TASK_CONTROL_AUDIT_SHARED_STATE.md:390`） |
| 音・PCM | Tone/Sampleは値でもpool位置を持つ。audio_fnのEngineはpool・command/ring・atomic状態とPCM Sessionを含みState専有だけでは分離されない（`src/core/sound_engine.zig:156`〜`src/core/sound_engine.zig:198`）。audio_scope_ops/audio_fn/device/waitを遮断しhost_audio・C音backendを許可しない（`docs/TASK_CONTROL_AUDIT_SHARED_STATE.md:135`） |
| Runtime・ID発行 | host_runtime.identitiesはState外である。台帳・ID発行はホスト所有としworkerの投入／待機／ID発行を許可しない（`docs/TASK_CONTROL_DETAILED_PLAN.md:86`）。Stateを別確保しても共有元は分離されない |
| C/OSのプロセス状態 | 環境・errno・signal・端末・音・window backendはState表の外である。extern environやOS別コンテナも対応対象でありvar宣言集合だけを全共有状態の証明にしない（`docs/TASK_CONTROL_AUDIT_SHARED_STATE.md:560`、`docs/TASK_CONTROL_AUDIT_SHARED_STATE.md:606`）。禁止機能への非到達とC/OS側の並行検証は別に必要である |
| 辞書・xt・論理アドレス・起動登録 | Snapshot版内で再配置・解決しメインのword ID/xtを移植可能な識別子にしない。1068のAPP登録ではappendは対象側の登録を保ち、完全復元はイメージ側の登録を検査する（`src/core/image_append.zig:59`〜`src/core/image_append.zig:128`、`src/core/image_restore_plan.zig:26`）。APP登録はsystem memory中の保存値でありhost mainの起動dispatchをworkerへ継承しない（`src/forth.zig:503`、`docs/CORE_EXTENSION_DETAILED_DESIGN.md:806`〜`docs/CORE_EXTENSION_DETAILED_DESIGN.md:812`） |
| 許可検査・取消し | 復元後specialize/inline済みの到達Opとoperandを検査する。入口だけ・null callbackだけでは不足する。動的実行・例外・counted・PAD・DO系の拒否とBEGIN系の専用取消しを結合検証する（`docs/TASK_CONTROL_AUDIT_ALLOWED_SET.md:404`、`docs/TASK_CONTROL_AUDIT_ALLOWED_SET.md:510`、`docs/TASK_CONTROL_AUDIT_REENTRY.md:159`） |

各モジュール変数の宣言・所有者・到達口は `docs/TASK_CONTROL_AUDIT_SHARED_STATE.md:128` の3.1節と同`docs/TASK_CONTROL_AUDIT_SHARED_STATE.md:390` の3.2節を正本とする。本書W表は全Writer項目を同名監査行へ対応付けた。ホスト起動・終了・UIスレッドから直接触れる状態はworker callbackをnullにしても消えない。最終許可集合から非到達であることを1360で照合する。


### モジュール変数の対応索引

以下は既存共有状態表の全モジュール領域と本書の遮断条件を結ぶ索引である。変数ごとの所有・主な参照は参照先の各行に従い、ここでその監査を並行実証済みへ格上げしない。

| フィールド | 扱い | 条件 |
|---|---|---|
| standard_input / pending_* / execution | event_input・host_wait・host_signal_broker | modern_depthはW01/W02/W17/W18と入力語拒否の組合せで遮断する。execution_machine・execution_poll等と信号所有はメイン専用である（`docs/TASK_CONTROL_AUDIT_SHARED_STATE.md:134`、`docs/TASK_CONTROL_AUDIT_SHARED_STATE.md:562`）。W01/W02のnullはState.executionの値初期化とは別条件である |
| writer / source_* / input_file / output_file / block_storage | main・host_input・host_directories | output_buffer/open_files/入力の保留・モード/slots/next_idを専用Writerから借用しない。W06/W07は専用、read/load/save/savesys/key/event/unread/sleep/file_ops/端末などの関連口はnullである（`docs/TASK_CONTROL_AUDIT_SHARED_STATE.md:145`、`docs/TASK_CONTROL_AUDIT_SHARED_STATE.md:160`、`docs/TASK_CONTROL_AUDIT_SHARED_STATE.md:128`） |
| tcl / system_status / sh_get_result | host_process・mainのprocess表 | shared/shared_id、OS別processコンテナへprocess_ops/system_fn/editor_fn/process_start_fn/process_write_fn/process_read_fn/process_stop_fnから進ませない（`docs/TASK_CONTROL_AUDIT_SHARED_STATE.md:177`、`docs/TASK_CONTROL_AUDIT_SHARED_STATE.md:390`）。StateのTclが値だけでもプロセス資源は分離されない |
| gfx_* | host_display_budget・host_display_macos・host_resize・host_window_linux・host_window_macos・main | until、executable_path/environment/parent_ready、window/UI/resize共有状態を継承しない。framebuffer/image/display/window/input/physical_key/font等の口と該当語を遮断する（`docs/TASK_CONTROL_AUDIT_SHARED_STATE.md:147`〜`docs/TASK_CONTROL_AUDIT_SHARED_STATE.md:150`、`docs/TASK_CONTROL_AUDIT_SHARED_STATE.md:128`） |
| gfx_font / gfx_displays / gfx_input / writer | OS別コンテナ | host_fontのgdi/coretext、host_display.win32、host_window.win32とVsync、main.utf8_console、host_input/host_wait等のOS別コンテナも同じ遮断対象である。関数内static相当を直下表の外として落とさない（`docs/TASK_CONTROL_AUDIT_SHARED_STATE.md:390`） |
| gamepads | host_gamepad・host_evdev | library/api/opened、slots/next_id/next_scan/denied等をW05=nullと機器入力語拒否で遮断する（`docs/TASK_CONTROL_AUDIT_SHARED_STATE.md:151`〜`docs/TASK_CONTROL_AUDIT_SHARED_STATE.md:159`） |
| audio_* | host_audio・各OS音コンテナ | engine/next_pcm_id/state/device_open/停止・終了印/音スレッドhandleをW02/W71〜W73と音語拒否で遮断する。atomic印の存在を借用許可の理由にしない（`docs/TASK_CONTROL_AUDIT_SHARED_STATE.md:135`〜`docs/TASK_CONTROL_AUDIT_SHARED_STATE.md:144`、`docs/TASK_CONTROL_AUDIT_SHARED_STATE.md:390`） |
| State外の台帳・所有ID | host_runtime | identitiesはホスト管理である。worker内のタスク投入・待機を拒否し、共有可変発行元へworkerから直接触らせない（`docs/TASK_CONTROL_DETAILED_PLAN.md:86`） |

## restore / restoreFreshと1354残留表の照合

1354は別worktreeの逐次試験記録である（`docs/TASK_CONTROL_PROTO_1354.md:3`）。試作ソースの行番号を現作業ツリーへ流用せず、同報告36〜58行の対象を現ソースで再照合した。今回は試験を再実行していない。

| フィールド | 扱い | 条件 |
|---|---|---|
| memory保存範囲 / 非保存範囲 / block buffer | 報告の分類と一致 | restoreはblock以外を消去して保存範囲・heapを再構成、Freshは消去省略（`src/core/image_restore.zig:50`〜`src/core/image_restore.zig:74`）。block_storageも全体再初期化しない。Freshにはゼロ保証済み新規memoryを使う |
| data/return/float・loop_stack・frames・catches | 非アクティブ要素は保持 | 深さを0へ戻すのはdata/return/float/control/loopでありframe_depth/catch_depth/call_depthをこのapplyが0にする処理はない（`src/core/image_restore.zig:89`〜`src/core/image_restore.zig:93`）。新規VMの深さ0を基準とする。1354の代表要素の試験を全要素消去の証拠にしない |
| random_state・source_line/source_kind | 保持 | applyと呼出し先に再初期化がない（`src/core/image_restore.zig:25`〜`src/core/image_restore.zig:111`）。新規VMならutime_fn=nullでrandom_state=0、空source_line/terminalから始める（`src/forth.zig:243`、`src/forth.zig:272`、`src/forth.zig:486`） |
| gfx_input | 原則保持・条件付き作用 | mouse等を.{}にしない。Tcl partialがUならforgetTkKeysへ進む（`src/core/tcl.zig:96`〜`src/core/tcl.zig:105`）。1354のmouse_x残留と両立する。全入力状態を復元で消せるとはしない |
| pending_key / standard_input | 初期化 | null/.{}へ（`src/core/image_restore.zig:27`〜`src/core/image_restore.zig:30`）。pending_event_bytes本体は消去せず件数だけ0へ戻す |
| Tcl result/error_text/event/event_count / program/input/header / partial | 部分無効化 | forgetHeapは論理参照と件数を捨てdropPartial(false)へ進む。program/input/header等は保持。skipを残しU部分受信はTk保持キーへ作用する（`src/core/tcl.zig:85`〜`src/core/tcl.zig:105`）。子停止callbackは呼ばない |
| gfx_images / gfx_images_bytes / gfx_target | 所有資源を処理 | releaseAllは非空slotをreleaseしtarget=screenへ（`src/core/graphics_images.zig:317`〜`src/core/graphics_images.zig:333`）。新規空slotならimage_free_fnを呼ばない。使用済み非空slotではnull callbackだけでfreeされず参照を失う。空slotのgeneration等まで全初期化はしない |
| gfx_pixels / gfx_clip / gfx_font | clearImageの範囲を明示 | 画素sliceを空、幅/高さ0、clip=null、font.kind=builtinへ（`src/core/words_graphics.zig:587`〜`src/core/words_graphics.zig:595`）。framebuffer/font.bufferの解放ではなくfontの他の参照は残る（`src/core/graphics_font.zig:78`） |
| Writer.physical_key_ops / wrap_guard | State外への作用 | resetが非nullならcontextを操作しinvalidateはGuard連鎖を書き換える（`src/core/image_restore.zig:31`、`src/core/image_restore.zig:104`、`src/core/words_value_extensions.zig:27`）。新規workerのnull設定ならこの外部操作へ進まない |
| keep_counting | 新規VMでも復元後を検査 | noteBreakpointsが復元コードを走査してtrueにし得る（`src/core/image_restore.zig:88`、`src/core/words_debug.zig:346`）。初期falseだけではcounted拒否を満たさず、復元後検査とworker経路分離が必要である |

Storage.allocate(false)の明示ゼロ化対象はmemory/data/return/floatでありloop/frame/catchは確保だけである（`src/forth.zig:163`〜`src/forth.zig:183`）。already_zero=trueはallocatorのゼロ保証が条件である。同じStorageでState.initを呼ぶだけでは保存対象外memoryや配列要素の全消去にはならない。新規VM基準でも有効深さ・件数外のundefinedを読まない契約が必要である。再利用は利用者判断どおり保留であり、通常restoreへの切替だけで承認済みとはしない。

## 証拠の限界・未確認事項・判断事項

静的結論は専有State/Storage、専用Writer、空の外部資源、復元後許可・領域検査、Snapshot/Plan/結果の所有寿命を条件とする。全行にO/Xを付けたが、データ競合・allocatorの並行契約・回収順の実証は未完了である。

1352は取消し、1353は限定隔離、1354は逐次復元の部分証拠であり結合済み製品の証拠へ合算しない（`docs/TASK_CONTROL_PROTO_1352.md:17`、`docs/TASK_CONTROL_PROTO_1353.md:29`〜`docs/TASK_CONTROL_PROTO_1353.md:35`、`docs/TASK_CONTROL_PROTO_1354.md:60`）。1355の通常経路差分と1356の費用資料も型隔離・全共有状態の証明ではない（`docs/TASK_CONTROL_PROTO_1355.md:5`〜`docs/TASK_CONTROL_PROTO_1355.md:13`、`docs/TASK_CONTROL_PROTO_1356.md:3`）。今回はこれらの測定を再実行していない。

- 未確認：1360の最終許可集合と復元後Op・operand・VM内書込み可能領域の全件照合。keep_countingを立てるコードや間接到達を含む。
- 未確認：メインとworkerの実行が重なる並行試験、差替え試験と実機での実行によるメインへの非干渉（画像の解放・出力・NS・ファイル操作・辞書の復元・タスク再利用）の確認、画像・font・Tcl・入力・出力・ファイル・音・信号所有をメインに残した隔離試験、成功・失敗・取消し後の停止・結果コピー・join・解放。C/OS内部の全状態とmemory orderingの証明。
- 未確認：本番allocator・復元workspace・workerスタックの所有と上限、Snapshot公開同期・破壊的変更後の失効、新規VM作成から終端までの結合。
- 利用者判断済み：新規VM基準・再利用保留・初期拒否範囲について再判断は求めない。方式の確定と公開は保留である。
- 利用者判断が必要になる事項：初期拒否機能の個別解除、再利用の採用、W1改良後の通常側差分の許容、利用条件案と追加測定の要否。今回の静的監査を進めるための新たな判断は不要である。
- 詳細化・実装へ渡す事項：write_fn超過記録を失敗へ変換する境界、復元後keep_counting/禁止Opの拒否条件、専用取消し・終端通知の同期、回収責任。実装済み・承認済みの数値とは扱わない。

## 付録A. 列挙・計数と追加フィールドの検出

PowerShellで次のPythonを標準入力から実行した。State 176、Writer 73、重複0、表との名前集合差なし、宣言差なしを確認した。件数が同じまま項目が置換されても集合差で検出する。内部型だけの変更は下記の再帰追跡を別に行う。

```powershell
$env:PYTHONIOENCODING = 'utf-8'
# 次のpythonコードを @' と '@ のPowerShell here-stringで囲み、python -へパイプする。
```

```python
from pathlib import Path
import re

def extract(path, begin, end):
    text = Path(path).read_text(encoding='utf-8')
    part = text.split(begin, 1)[1].split(end, 1)[0]
    return [(m[1], m[2]) for m in re.finditer(r'^    (\w+): (.+),$', part, re.M)]

state = extract('src/forth.zig', 'pub const State = struct {', '    pub fn init(')
writer = extract('src/core/host_interface.zig', 'pub const Writer = struct {', '    pub fn write(')
doc = Path('docs/CORE_EXTENSION_WORKER_STATE_AUDIT.md').read_text(encoding='utf-8')
st = doc.split('## フィールド別の方針', 1)[1].split('## 再帰型の内訳', 1)[0]
wt = doc.split('## Writer全フィールドとの対応（W表）', 1)[1].split('## ホスト側の監査と禁止条件', 1)[0]
for label, source, table, prefix in [('State', state, st, ''), ('Writer', writer, wt, 'Writer.')]:
    names = [name for name, _ in source]
    rows = re.findall(r'^\| `'+re.escape(prefix)+r'(\w+)` \|', table, re.M)
    print(label, 'source', len(names), 'table', len(rows),
          'source duplicates', len(names)-len(set(names)), 'table duplicates', len(rows)-len(set(rows)))
    print('missing', sorted(set(names)-set(rows)), 'obsolete', sorted(set(rows)-set(names)))
    for name, decl in source:
        typ, sep, default = decl.partition(' = ')
        if label == 'Writer':
            row = next(r for r in table.splitlines() if r.startswith('| `Writer.'+name+'` |'))
            assert '型 `'+typ+'`' in row
            assert '宣言 `'+(default if sep else '必須')+'`' in row
        else:
            row = next(r for r in table.splitlines() if r.startswith('| `'+name+'` |'))
            assert '型 `'+typ+'`' in row
    assert len(names)==len(set(names)) and len(rows)==len(set(rows))
    assert set(names)==set(rows)
baseline = doc.rsplit('## 付録B. State宣言の照合基準', 1)[1].split(chr(96)*3+'text', 1)[1].split(chr(96)*3, 1)[0]
expected = dict(line.split(': ', 1) for line in baseline.strip().splitlines())
actual = dict(state)
print('State changed declarations', sorted(k for k in actual.keys() & expected.keys() if actual[k] != expected[k]))
assert actual == expected
```

この正規表現は現ソースの「直下4空白・1行宣言」に対応する。複数行・別インデントへ変われば抽出器を更新する。構文解析・コンパイラ反射による完全な型検査を実行したものではない。抽出境界・列挙の目視確認には次を使う。

```powershell
rg -n '^pub const State|^pub const Writer|^    [A-Za-z_][A-Za-z_0-9]*:' src/forth.zig src/core/host_interface.zig
rg -n 'const .* = (struct|union|enum)|^    [A-Za-z_][A-Za-z_0-9]*:' src/core/defs.zig src/core/quotations.zig src/core/address_registry.zig src/core/source_navigation.zig src/core/source_search.zig src/core/source_editor.zig src/core/source_diagnostics.zig src/core/standard_event.zig src/core/blocks.zig src/core/execution_control.zig src/core/profiler.zig src/core/lint.zig src/core/macro_substitute.zig src/core/dynamic_strings.zig src/core/graphics_images.zig src/core/graphics_input.zig src/core/tcl.zig src/core/graphics_font.zig src/core/graphics_palette.zig src/core/display_info.zig src/core/gamepad.zig src/core/sound_mml.zig src/core/sound_voice.zig src/core/sound_pcm.zig src/core/runtime_base.zig src/core/physical_keys.zig src/core/host_interface.zig
rg -n 'state\.|self\.' src/core/image_restore.zig src/core/wordlists.zig src/core/inline_calls.zig src/core/words_debug.zig src/core/number_io.zig src/core/words_value_extensions.zig src/core/words_graphics.zig src/core/graphics_images.zig src/core/graphics_font.zig src/core/tcl.zig
```

T01〜T17とW表で参照した内部型の宣言を再確認し、新しい別名・コンテナを再帰的に辿る。ポインターを見つけたら指す先の所有・寿命・変更主体を追加する。復元に新しい呼出し先が増えたらR0判定から漏らさず追跡する。検索結果だけで監査完了とはしない。

共有変数の件数を本書で新たに合算しない。直下・OS別コンテナの既存計数条件と除外条件は `docs/TASK_CONTROL_AUDIT_SHARED_STATE.md:609` の付録Aを参照する。callback・直接ホスト参照・var/pub var/threadlocal/extern var追加時は同付録の抽出と全ソース検索を併用し、行番号固定範囲外の新コンテナも確認する。件数一致を安全性の証拠にしない。

## 付録B. State宣言の照合基準

本監査時の型・宣言初期値でありABIの固定や将来追加の禁止ではない。付録Aで差が出たら該当行・内部型・復元・許可範囲を再監査して更新する。

```text
writer: Writer
sizes: Sizes
memory: []u8
words: [max_words]Word = undefined
word_count: u16 = 0
name_heads: [wordlists.name_buckets]u16 = @splat(wordlists.no_word)
name_next: [max_words]u16 = undefined
builtin_count: u16 = 0
code: [max_code]Op = undefined
code_count: u16 = 0
names: [names_capacity]u8 = undefined
names_used: u32 = 0
data_stack: []Cell
data_depth: usize = 0
return_stack: []Cell
return_depth: usize = 0
float_stack: []Float
float_depth: usize = 0
quote_frames: [16]@import("core/quotations.zig").Frame = undefined
quote_depth: usize = 0
quote_closing: bool = false
quote_root: u16 = 0
image_generation: u64 = 0
backtrace_suppression: usize = 0
throw_nobt: bool = false
assert_depth: usize = 0
wrap_guard: ?*@import("core/words_value_extensions.zig").Guard = null
colon_is_word: ?u16 = null
colon_is_target: u16 = 0
noname_next: bool = false
next_name_len: u8 = 0
next_name: [memory_map.max_name]u8 = @splat(0)
postponing: bool = false
control_stack: [max_controls]Control = undefined
control_depth: usize = 0
hidden_word: u16 = wordlists.no_word
random_state: u64 = 0
addresses: @import("core/address_registry.zig").Registry = .{}
interpret_loops: [16]InterpretLoop = undefined
interpret_loop_depth: usize = 0
input_line_serial: Cell = 0
input_lines_read: Cell = 0
token_start: usize = 0
uses: [max_uses]defs.WordUse = undefined
use_count: usize = 0
loop_stack: []Loop
loop_depth: usize = 0
data_here: Cell = data_start
compiling: bool = false
defining: bool = false
current_word: u16 = 0
current_data_start: Cell = 0
pending: Pending = .none
pending_constant: Cell = 0
pending_float: Float = 0
pending_double: Double = 0
pending_array_size: Cell = 0
hold_ptr: Cell = hold_top
hold_end: Cell = hold_top
hold_stack: [max_hold_nesting]Cell = undefined
hold_depth: usize = 0
source_line: []const u8 = &.{}
source_kind: SourceKind = .terminal
block_depth: usize = 0
block_source_numbers: [memory_map.max_include_depth]Cell = @splat(0)
include_stack: [max_include_depth]IncludeFrame = undefined
include_depth: usize = 0
error_location: ?ErrorLocation = null
source_navigation: @import("core/source_navigation.zig").Navigation = .{}
source_search: @import("core/source_search.zig").Search = .{}
source_editor_mode: @import("core/source_editor.zig").Mode = .{}
source_trace: @import("core/source_diagnostics.zig").History = .{}
name_buffer_index: usize = 0
last_created_word: ?u16 = null
halted: bool = false
pending_key: ?u8 = null
pending_event_bytes: [32]u8 = undefined
pending_event_count: usize = 0
pending_standard_event: ?Cell = null
standard_input: @import("core/standard_event.zig").Decoder = .{}
block_storage: @import("core/blocks.zig").Storage = .{}
call_depth: usize = 0
frames: []CallFrame
frame_depth: usize = 0
catches: []CatchContinuation
catch_depth: usize = 0
backtrace: [max_backtrace]u16 = undefined
backtrace_count: usize = 0
backtrace_total: usize = 0
backtrace_level: usize = 0
failed_pc: u16 = 0
show_backtrace: bool = true
code_lines: if (defs.debug_enabled) [max_code]u32 else void = if (defs.debug_enabled) @splat(0) else {}
cover_blocks: bool = false
code_columns: if (defs.debug_enabled) [max_code]u16 else void = if (defs.debug_enabled) @splat(0) else {}
step_limit: u64 = 0
steps_left: u64 = 0
execution: if (defs.debug_enabled) @import("core/execution_control.zig").Control else @import("core/execution_control.zig").Empty = .{}
tracing: bool = false
trace_limit: u64 = 0
trace_lines: u64 = 0
trace_depth: usize = 0
profile: ?*Profile = null
lint: ?*Lint = null
plain_calls: bool = false
stepper: enum { off, armed, on } = .off
step_word: u16 = 0
step_depth: usize = 0
step_base: usize = 0
step_result: bool = false
step_after_cr: bool = false
step_skip_end: u16 = 0
step_inline_ends: [8]u16 = undefined
step_inline_count: usize = 0
in_counted: bool = false
keep_counting: bool = false
report_text: [240]u8 = undefined
report_len: usize = 0
report_capturing: bool = false
cell_watches: [8]struct { address: Cell, value: Cell } = undefined
cell_watch_count: usize = 0
line_trace: bool = false
watched: [32]u16 = undefined
watched_count: usize = 0
outer_pc: u16 = 0
last_unknown_word: ?[]const u8 = null
throw_code: Cell = 0
abort_message: ?Cell = null
input_file: ?Cell = null
output_file: ?Cell = null
output_error: ?Cell = null
capture_target: ?Cell = null
capture_sink: ?*@import("core/macro_substitute.zig").Captured = null
sh_get_result: ?@import("core/dynamic_strings.zig").StringRef = null
system_status: Cell = 0
capture_failed: bool = false
tmp_string_index: usize = 0
locals: [max_locals]Local = undefined
local_count: usize = 0
locals_frame_size: u16 = 0
locals_top: Cell = 0
gfx_pixels: []u32 = &.{}
gfx_width: Cell = 0
gfx_height: Cell = 0
gfx_images: [graphics_images.max_images]graphics_images.Slot = @splat(.{})
gfx_images_bytes: usize = 0
gfx_target: Cell = graphics_images.screen
graphics_library: []const u8 = if (defs.graphics_enabled) words_graphics.library else ""
gui_library: []const u8 = if (defs.graphics_enabled) @import("core/words_gui.zig").library else ""
game_library: []const u8 = if (defs.graphics_enabled) @import("core/words_game.zig").library else ""
audio_library: []const u8 = if (defs.audio_enabled) words_audio.library else ""
extension_library: []const u8 = if (defs.extension_enabled) @import("core/words_extension.zig").library else ""
audio_voices: [sound_engine.max_voices]sound_mml.Voice = @splat(.{})
audio_instruments: [sound_mml.instrument_count]sound_engine.Tone = @splat(.{})
audio_instrument: u8 = 0
audio_samples: [sound_engine.pcm.sample_count]sound_engine.pcm.Sample = @splat(.{})
audio_pool_used: u32 = 0
audio_pcm_handle: Cell = 0
gfx_band: if (defs.graphics_enabled) [6][graphics_terminal.max_sixel_width]u8 else void = undefined
gfx_glyph_alpha: if (defs.graphics_enabled) graphics_font.Alpha else void = undefined
embedded_source: []const u8 = &.{}
gfx_input: graphics_input.InputState = .{}
tcl: if (defs.graphics_enabled) tcl.TclState else void = if (defs.graphics_enabled) .{} else {}
gfx_color_mode: graphics_palette.ColorMode = .{}
gfx_window_size: [2]u32 = .{ 0, 0 }
gfx_auto_display: u8 = 0
gfx_fullscreen: bool = false
gfx_cursor_visible: bool = true
gfx_clip: ?@import("core/graphics_images.zig").Clip = null
gfx_window_fit: u8 = 0
gfx_window_smooth: bool = false
gfx_window_keep_open: bool = false
gfx_displays: @import("core/display_info.zig").Snapshot = .{}
gamepads: @import("core/gamepad.zig").Snapshot = .{}
gfx_font: if (defs.graphics_enabled) graphics_font.FontState else void = if (defs.graphics_enabled) .{} else {}
output_count: u64 = 0
```
