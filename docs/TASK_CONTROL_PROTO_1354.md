# 1354：明示Snapshotの試作（レビュー修正）

本書は1357の方式判断へ渡す試作記録であり、採用記録ではない。対象はWindows、Zig 0.17.1、detached HEAD `35523f676836134c4fbaed19e3d01d2a23ec2a92` の専用worktreeである。HEADとdetached状態は今回コマンドで確認した。

## 前提と変更ファイル

G1の仮置きは、動的実行（EXECUTE・.execute Op・.local_execute・DEFER・DOES>・CATCH/THROW）を初期拒否、workerではcounted経路を選ばない、PADを許可集合から除外、である。最終仕様ではない。試験では入口を限定検査し、counted条件が偽であることを確認する（`src/tests/task_snapshot_proto_test.zig:32`、`:54`、`:185`）。

- `src/tests/task_snapshot_proto_test.zig`：従来4試験を修正し、残留の1試験を追加した（同`:81`、`:122`、`:163`、`:185`、`:207`）。
- `src/forth_test.zig:4`：前回の試作で試験集合へ登録済みである。今回の修正では変更していない。
- `docs/TASK_CONTROL_PROTO_1354.md`：本報告を更新した。

開始時から存在した `docs/TASK_CONTROL_PLAN.md` の変更と他の未追跡文書は変更していない。製品のsrc本体・build.zigは変更していない。commit・branch作成・push・tque操作、外部データへのアクセス、作業ツリー外へのファイル変更は行っていない。

## レビュー8点の確認と反映

指摘を誤りと判断した点はない。ただし残留の分類は下表のとおりであり、「Tclのresult/event以外はすべて残る」とも扱わない。

1. メインで `9 V ! : ENTRY 999 ;` と変更した後に、新規worker `late` を確保して古いbytesをrestoreFreshする試験を追加した。V=7、ENTRY=50を検査する。メインはENTRY=999である。先に復元済みのtargetだけを見る従来の検査では、変更後に古いbytesから復元できることを証明できていなかった（`src/tests/task_snapshot_proto_test.zig:101`、`:106`）。
2. workerのVを書き換えてメインがV=9のままである検査は、別Storage間の隔離の健全性確認と位置付けた。並行安全性やホスト資源全般の証拠ではない（同`:112`）。
3. sameCodeにword_countと全有効wordsのcode_start/end・kind・valueの比較を追加した。Opのkind/valueとcode_countも比較する（同`:66`）。inline_calls.restoreはkeepsCallsが真なら即座に戻り、keepsCallsはdebug有効かつplain_callsである（`src/core/inline_calls.zig:73`、`src/forth.zig:1834`）。今回のplain_calls=false条件での一致であり、plain_calls等が異なる条件では最適化後コードが一致しない可能性がある。異条件での一致は未確認である。
4. restoreによる消去の説明をmemoryとState/Storageに分け、初期化済みの非アクティブな配列要素と代表フィールドの残留試験を追加した（`src/tests/task_snapshot_proto_test.zig:207`）。詳細は次節である。
5. スレッド化の前提・所有権・寿命・スタックとallocatorの注意点を後述した。実スレッドでの実証ではない。
6. 成功試験中のstd.debug.printを削除した。今回の結果は終了コードとsummaryで判定する（同`:118`）。以前のバイト数表示およびstderrに伴うfailed command表示は今回の試験結果の根拠に使わない。
7. checkはvisited集合を持たず、循環はremaining上限だけで拒否する試作fixture専用の検査である旨をコメントに明記した（同`:28`）。
8. 指定の2構成の試験結果を後述した。

## 設計上の選択と理由

SnapshotはencodedSizeで確保しencodeImageで保存する所有バイト列である。複製との全体比較で、復元・実行・メイン変更後もbytesが変わらないことを検査する（`src/tests/task_snapshot_proto_test.zig:21`、`:87`、`:115`）。Stateの値コピーや実行中の継続の複製は行わない。

復元はcodeコピー後にspecializeCallとinline復元を行う（`src/core/image_restore.zig:47`、`:85`）。保存表現と実行時表現を直接比較せず、復元後のwordsとOpを比較する方針である。今回のfixtureではinlineガードの存在も検査する（`src/tests/task_snapshot_proto_test.zig:95`）。任意定義・異なるbuiltin配置の同一性は未確認である。

FORGET後のword ID再利用とMARKER後にも古いbytesからENTRY=42を復元できることを検査する（`src/tests/task_snapshot_proto_test.zig:163`）。これは旧版を失効させる機構の実装ではない。D03案として、Snapshot固有IDと所有参照を持ち、入口をSnapshot内の名前（必要ならwordlistも含む）で解決する。メインのword IDだけを持ち越さない。破壊的変更後の新規投入を拒否する場合は、FORGET・MARKER・完全復元の境界で専用の構造変更epochを更新する案である。通常の `!` の監視やimage_generationによる全変更検出は行わない。旧版の新規投入可否、epoch対象と枯渇は1357・1359の未決事項である（`docs/TASK_CONTROL_DETAILED_PLAN.md:203`）。

## 再利用時に消えるもの・残るもの

Storage.allocate(false)はmemory・data/return/float配列をゼロにするが、loop_stack・frames・catchesは確保するだけである（`src/forth.zig:162`、`:177`）。未初期化要素は読まず、試験で明示的に値を入れた要素だけを検査する（`src/tests/task_snapshot_proto_test.zig:205`）。State.initのデフォルト初期化と、Storageの全配列消去は別である（`src/forth.zig:483`）。

| 対象 | restore後の分類・確認範囲 | 根拠 |
|---|---|---|
| memoryの保存範囲 | Snapshotで上書きする | `src/core/image_restore.zig:55` |
| memoryの非保存範囲（block以外） | restoreはゼロ化する。data_here+64の0xa5が0になることを実測する | `src/core/image_restore.zig:50`、`src/tests/task_snapshot_proto_test.zig:138` |
| block buffer | 0xb6が残る。ホスト側block状態も維持する設計である | `src/core/image_restore.zig:49`、`src/tests/task_snapshot_proto_test.zig:140` |
| restoreFreshの非保存memory | 再利用への意図的誤用では0xa5が残る | `src/tests/task_snapshot_proto_test.zig:136` |
| data/return/floatスタック | 深さは0、深さより上の要素101/102/103は残る | `src/tests/task_snapshot_proto_test.zig:244` |
| loop_stack | loop_depthは0、非アクティブ要素のindex=104は残る | `src/tests/task_snapshot_proto_test.zig:248`、`:252` |
| frames・catches | 非アクティブ要素のpc=106・frame_depth=108は残る。全要素・全フィールド比較ではない | `src/tests/task_snapshot_proto_test.zig:253` |
| random_state | 109が残る | `src/tests/task_snapshot_proto_test.zig:255` |
| source_line/source_kind | worker所有のfixture文字列とevaluateが残る。他のsource_*全項目の実測は未確認である | `src/tests/task_snapshot_proto_test.zig:256`、`src/forth.zig:272` |
| gfx_input | mouse_x=110が残る。全フィールドの実測は未確認である | `src/tests/task_snapshot_proto_test.zig:258` |
| pending_key | nullへ戻る | `src/tests/task_snapshot_proto_test.zig:259`、`src/core/image_restore.zig:28` |
| Tcl result/error_text/event・event_count | forgetHeapで論理参照と件数を消す。試験はresult/error_text/eventのaddressとevent_countを検査する | `src/core/tcl.zig:85`、`src/tests/task_snapshot_proto_test.zig:265` |
| Tcl program/input/header | program_length=3・program[0]='x'・input_start=2・header_length=1・header[0]='R'が残る。全プロトコル状態の初期化ではない | `src/tests/task_snapshot_proto_test.zig:261` |
| Tcl partial等 | dropPartial(false)で部分メッセージを処理しskipを残す。partialがUなら入力情報にも作用する。今回のpartial経路の実測は未確認である | `src/core/tcl.zig:91`、`:96` |
| 画像slotと使用量 | worker所有の模擬画像slotと使用量は空になる。null callbackでホスト解放は呼ばない | `src/tests/task_snapshot_proto_test.zig:142`、`src/core/graphics_images.zig:316` |

したがってrestoreだけでは全非保存状態を消去できず、VM再利用の停止条件を解消していない。新規Storageであってもloop/frame/catch全域がゼロという主張はできない。1358・1362で全フィールド、成功・失敗・取消し後の回収を確認する必要がある（`docs/TASK_CONTROL_DETAILED_PLAN.md:209`）。メインのTcl件数が変わらない検査も、独立Stateの健全性確認に限定する（`src/tests/task_snapshot_proto_test.zig:156`）。

## ワーカースレッドで使用する場合の注意点

以下は設計上の必要条件であり、今回の逐次試験で成立を実証したものではない。

- State/Storage/Writerはワーカー専用に新規構築する。source_line等の借用参照をメインから値コピーしない。現在のworkerヘルパーはwrite_fnが破棄処理であり、他のcallbackを設定しない試験用構成である（`src/tests/task_snapshot_proto_test.zig:12`、`src/forth.zig:272`）。
- Snapshot取得はメインの安全な境界で行う。ワーカーへ公開後はbytesを不変とし、最後の復元・利用が終わるまで所有する。State/Storageは停止・結果コピー・回収前に解放しない（`docs/TASK_CONTROL_DETAILED_PLAN.md:165`、`:183`）。共有公開の同期・所有権移転と結果回収は未実装である。
- Planは呼出し側所有の可変workspaceであり、imageと自身のworkspaceを借用する。並行restoreで同じPlanを共用せず、prepare/apply間に対象を変更しない（`src/core/image_restore_plan.zig:11`、`:23`）。StateとPlanの大きいローカル変数をワーカースタックへ置く場合は、必要スタック量を確認する。今回のスレッドスタック上限・実起動は未確認である。
- std.testing.allocatorは本番スレッド用allocatorの選定根拠ではない（`src/tests/task_snapshot_proto_test.zig:15`、`:22`）。本番では並行alloc/freeの契約、割当・解放スレッドと寿命を確認する必要がある。専用または同期されたallocatorの具体選定は未確認である。
- ホスト画像を持つStateのcallbackだけをnullにして再利用する方式にはしない。releaseAllはcallbackとslotを使って後始末するため、先に所有資源を回収する契約が必要である（`src/core/graphics_images.zig:316`）。restoreはphysical_key_ops.resetも呼ぶため、メインのWriterを渡さない（`src/core/image_restore.zig:104`）。
- null callbackや限定fixture検査だけではスレッド安全性を保証できない。共有変数・ホスト資源への到達監査、専用許可検査、取消し・停止確認を別途行う（`docs/TASK_CONTROL_DETAILED_PLAN.md:194`、`docs/TASK_CONTROL_AUDIT_SHARED_STATE.md:562`）。実際の並行実行、競合、OS資源回収は未確認である。

## 試験コマンドと結果

PowerShellから実行する。キャッシュはこのworktree内に限定する。時間・速度の測定は行わず、buildツールの自動表示時間も判断資料に採用しない。

```powershell
$env:ZIG_GLOBAL_CACHE_DIR = "$PWD\.zig-global-cache"
zig build test --summary all
zig build test -Ddebug=false --summary all
zig fmt --check src/tests/task_snapshot_proto_test.zig
git diff --check
```

| 確認 | 実際の出力の要約 |
|---|---|
| `zig build test --summary all` 最終再確認 | 終了コード0。`Build Summary: 23/23 steps succeeded`、`test success`。run testはcachedであり、新たな非cached実行とは数えない |
| `zig build test -Ddebug=false --summary all` | 終了コード0。`Build Summary: 23/23 steps succeeded; 1127/1209 tests passed (82 skipped)`。coreは1127 pass/82 skip、host/runtimeはcachedの成功である |
| `zig fmt --check src/tests/task_snapshot_proto_test.zig` | 終了コード0、診断なし |
| `git diff --check` | 終了コード0、診断なし。未追跡ファイルはこのコマンドの検査対象に含まれない |

5件の試作試験にはdebugによるスキップ条件を置いていない。graphics無効時だけTcl関連検査を条件分岐する（`src/tests/task_snapshot_proto_test.zig:81`、`:122`、`:163`、`:185`、`:207`、`:260`）。他の語群除外構成・実スレッド構成の試験は今回実行していない。

## 詳細計画4.1の停止条件と1357への判断材料

停止条件の出典は `docs/TASK_CONTROL_DETAILED_PLAN.md:121` である。

| 停止条件 | 今回の結果 |
|---|---|
| debug=falseの無限ループ取消し不能 | 取消し実装・無限ループ試験は対象外で未確認である |
| 動的呼出し・inlineから検査を回避 | 動的実行・例外・PADのfixture拒否試験はあるが、一般の実行時防壁は未確認である（`src/tests/task_snapshot_proto_test.zig:185`） |
| メイン資源へ干渉 | 独立Storageの変数・独立Stateの件数確認までである。並行安全性とホスト実機は未確認である（同`:112`、`:156`） |
| 早期解放・再利用の残留 | 逐次試験では利用後に解放する。restoreで複数の残留を確認したため、restore単独による完全再利用は不成立である（同`:207`） |
| 起動・コピー・停止費用 | 時間・採用閾値は未確認である。費用の合格とはしない |

1357へは、旧Snapshotの新規投入可否とD03の入口・失効規則、新規初期化を基準にするか再利用の完全初期化を実装するか、plain_calls等を含む復元後コード照合の適用条件、Plan/allocator/スタックとSnapshot寿命の所有契約を渡す。今回の試験成功を方式採用・全停止条件の合格へ読み替えない。1358の再帰監査、1360の許可検査、1362の再利用、取消しと並行寿命、別途許可された費用測定が残る（`docs/TASK_CONTROL_METHOD_COMPARISON.md:140`）。
