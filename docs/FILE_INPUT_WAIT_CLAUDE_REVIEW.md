# 1078 Claude Codeレビュー

2026-11-19。読み取り専用、Claude自身はビルド・テスト未実行。

## 設計レビュー

方針は妥当。実装前提として次のB1〜B5を指摘した。

1. B1: Decoder保留とungetcを並存させると順序が壊れる。ready/fileUnread/行読みの押し戻しを同じ列に統一。
2. B2: 保留があればEOF判定より先に読む。FILE-EOF?はEOF観測済みかつ保留空。
3. B3: 1ms sleepだけではCtrl+Cを捕捉できない。割込み可能なホスト待機経路を使い、保留を残す。
4. B4: optional callbackの型と復号規則を確定する。msはCell相当、controls/interrupts=false。
5. B5: open/close/close-pipe/全回収のslot状態を同じ関数で初期化。

追加確認: CR後の非LF押し戻し、複数UTF-8押し戻し、途中EOF、保留満杯、無期限待機のCtrl+C。採否と具体的な実装方針はFILE_INPUT_WAIT_DESIGN.mdの「設計レビューの採否」に記録する。無保留update streamの方向切替は既存課題1091として639配下へ登録した。

## 実装レビュー

初回実装レビューで次を指摘した。

- 通常EKEYまでevent_waitへ送るとWindowsのNUL/CONで互換性を損なう。従来経路を維持する(a)を採用した。設計は既存EKEY維持を要求しており、追加の利用者判断は不要。
- READ-FILEのprefix取出し後にfreadが失敗するとprefixを失う。保留があればその分だけshort readで返し、後続OS操作に入らない形に修正した。
- 古いFileOpsのnull callback試験を要求。既存event_queue_testの「selected file timed wait rejects before reading and keeps outer decoder across THROW」が、null callbackで-21、直後のKEY-FILEでA、従来EKEYでBを確認している。追加の固定結果試験は設定済みcallbackとstack overflowを検証する。
- cleanup中断時のpeek保持とflags復旧失敗時の順序を追加検証する。mainのテスト専用fault seamで検証し、実際のOS障害とは区別する。
- LineSourceの押戻し時のdecoder.eofクリアと、tell−pendingが負の場合の防御を反映した。

初回レビューはslot初期化・EOFより保留優先・scope寿命・seek失敗時維持・write前seek・stack検査について問題なし。最終レビューは訂正後に依頼する。


## 最終レビューと訂正

再レビューでREAD-FILEの有保留short readを互換性ブロッカーとして指摘。Forth標準を一次確認し、指摘を採用した。prefixを消費せずコピーし、残りのfreadが成功／EOFとなった後だけ消費する。読取りエラーではprefixが残ることをfault seamで検証する。前段のshort read案は取り下げ。通常EKEY・待機cleanup・flags失敗時の順序・EOF・寿命・既存null callback試験については問題なしの評価。

READ-FILE訂正後の絞り込んだ再レビューで、前回ブロッカー解消・新規ブロッカーなしを確認した。Claude自身は試験未実行であり、親側のテスト結果と区別する。[再レビュー原文](reviews/1078-implementation-claude-review.md)を保存した。一般のfreadでエラー前に一部転送した場合の既存処理は今回変更していない。新しい保留prefixの維持と、実OS障害ではないfault seamの範囲を明示する。
