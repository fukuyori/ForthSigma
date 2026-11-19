# 997 Claude Code最終レビュー原文

2026-11-19。詳細設計とpure Trackerのみ。native／公開語の完了を意味しない。

## 依頼

```text
Final read-only review of revised task997 design and pure Tracker milestone ONLY. Read docs/PHYSICAL_KEY_DESIGN.md, docs/reviews/997-review-response.md, src/core/physical_keys.zig and src/forth_test.zig import. Original reviews are docs/reviews/997-design-claude-review.md and 997-tracker-claude-review.md; don't re-audit all host code. Check revised overflow retains first256 until drained then sticky resync, stale ack cannot clear pending transport, snapshot replacing old history, exact nine tests. Verify accepted design defines window-close vs restore boundaries and explicitly allows OS/pipe pending messages arriving after reset; public five words; no invented worker implementation. Do not execute commands or edit files. Return concise Japanese blocking issues only (or none), separate implementation obligations for1084/1085. This is the final checkpoint for closing1079 design and1083 pure foundation; don't treat native/Forth integration as complete. If no blockers, explicitly say those two milestones may close. Be brief.

```

## 原文

レモン、最終レビューの結果です。コマンドの実行とファイルの編集はしていません。読んだのは指定の4ファイル（`docs/PHYSICAL_KEY_DESIGN.md`、`docs/reviews/997-review-response.md`、`src/core/physical_keys.zig`、`src/forth_test.zig`）です。

## ブロッキングな問題
**なし。** 1079（設計）と1083（pure Tracker）は閉じてよいと判断します。native接続とForth語の接続（1084/1085以降）は未完了で、今回の範囲に含めていません。テストは今回実行していないため、通るかどうかは未確認です。

## 確認した項目
- **overflow**：257件目で `resync_required` が立ち、先の256件は残ります（`physical_keys.zig:29-31`）。以後のedgeは記録されず、heldだけ更新されます。履歴を読み終えた後は、`next` が毎回resyncを返します（:39）。
- **古いackで要求が消えない**：`resync` は `resync_required = stale` とします（:52）。そのため通信snapshot待ちの間は要求が残ります。テスト4で、早過ぎるresyncを2回呼んでも要求が残ることを検査しています。
- **snapshotの差し替え**：`replaceSnapshot` は古い履歴を捨て、staleを解除して要求を立て直します（:83-88）。予約番号0〜3も消します。テスト9で検査しています。
- **テスト数**：ちょうど9件です（:91〜:201）。`forth_test.zig:4` でimportされています。
- **閉鎖と復元の境界**：設計:55-56で区別されています。閉鎖は全解放してからunavailableにし、履歴と再同期要求を残します。復元とXKB物理対応表の変更は `boundary` です。
- **境界の後に届く通知**：OSやpipeに残っていて境界の後に届く通知は、新しい到着として処理すると設計:59に明記されています。OS上の発生時刻で過去の通知を排除する保証はしない、とも書かれています。
- **公開語**：下位の組込み入口5語（設計:34）と、ワーカーに対する方針（設計:79）が書かれています。存在しない実行ガードを実装済みと扱っていません。

## 1084（nativeホスト／Writer Ops）で実装時に守る事項
1. `boundary` はTrackerのstaleを解除します。そのため、Macで通信が飛んでsnapshotを待っている最中に復元すると、ホストが持つ連番の期待値と `SCANSYNC` の再送待ちが残ったままになります。この2つは消さずに保ち、後からsnapshotが届いたら `replaceSnapshot` で再同期要求を立て直してください。
2. `next`、`resync`、`releaseAll` は、どれも1回のロックの中で終えてください。`update` を呼ぶたびにロックを取り直すと、全解放の途中に別の処理が割り込みます。
3. Mac親側は、連番飛びと不正な行を `transportLost` につなげてください。SCANSNAPの受信は `replaceSnapshot` です。startChildでは、新しいpipeに合わせて受信状態を初期化してください。
4. Linuxのrepeat判定で保留しているreleaseは、確定してからTrackerへ渡してください。Windowsは4種のKEY/SYSKEYメッセージの先頭で取り込みます。
5. supported bitmapとavailableはホスト側に置きます。Trackerに持たせないでください。

## 1085（GRAPHICS語・定数・検査・復元reset・語参照）で実装時に守る事項
1. KEY-RESYNCは次の順に処理します：`memoryAddress` の検査 → `ops.resync` で作業領域へ写す → 32バイトを書く → `written` で通知。アドレス検査に失敗した場合は、ホストにもメモリにも触らないでください。
2. 範囲外のscanは、値を絞り込む前に-24を返してください。
3. 物理キーのresetは、`image_restore.apply` の中で `clearImage` の隣に、失敗しない処理として置いてください。preflightが失敗したときは呼びません。
4. optional opsがない場合（ホストに物理キー機能がない場合）は、3つの判定語と `KEY-EVENT` がfalseを返し、`KEY-RESYNC` は全0を写します。
5. 組込み語は末尾に追加し、旧イメージを拒否することを確認してください。SC-*は `graphics.fs` の定数として定義し、英語版と日本語版のリファレンスを同時に更新してください。
