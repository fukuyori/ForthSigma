# 997 レビューの評価・採否・反映

2026-11-19。[詳細設計](../PHYSICAL_KEY_DESIGN.md)と[実装記録](../PHYSICAL_KEY_IMPLEMENTATION.md)に反映。

## 設計レビュー

[原文](997-design-claude-review.md)は読取りのみ。以下はソースと照合した上での判断。レビューで「採用」と書かれたものも、それ自体を実装済みとは扱わない。

| 指摘 | 評価・判断 | 反映 |
|---|---|---|
| 1 ワーカー用ガードは未実装 | 採用。既存WrongOwnerを語のガードと混同しない | optional opsを将来のワーカーでnull、入力/UI許可表にも禁止。ガード実行試験は1049〜1053 |
| 2 Macの復元世代handshakeは不要 | 採用。ただし保証の範囲を明記する | 復元時はTrackerだけをreset。OS／pipeに残っていて復元後に届く通知は適用する。OS発生時刻を基準に排除する保証はしない。子再起動は新しいpipeで区切る |
| 3 既存timerなし／snapshot待ちのack | 採用 | 新設NSTimerではなく命令読取りのpoll16msとdirty snapshot。Trackerにstale、transportLostを追加。最新snapshot前は要求を消さない |
| 4 Macでviewへ届かない通知 | 条件付き採用 | NSApplication.sendEvent:での観測案。Command併用の効果は仮説と明記し、一次資料と実機で検証 |
| 5 キー単位の対応可否 | 採用 | SCAN-SUPPORTED?追加。CapsLock等、両edgeが保証できないキーをfalseにする。レビュー原文の「番号は1」は根拠不明のため採用せず、公開番号はUSB HID usage、範囲外は-24 |
| 6 閉鎖時の履歴・availability | 採用 | 閉鎖は全解放してunavailable、履歴は読む。境界は復元／物理表変更。KEY-EVENTは履歴→要求→false |
| 7 overflowと共通ルールの整合 | 採用。ASYNC_COMMON_RULES4節に「新しいものを捨てる」と明記あり | 先の256件を保持し、以後edgeを抑止。読み終えてからsticky再同期。pure Trackerも修正 |
| 8 論理メモリ検査と一括書込み | 採用 | memoryAddress→非失敗host snapshot→32バイトcopy→written。検査失敗時hostも不変 |
| 9 復元reset位置 | 採用 | apply内clearImage隣の非失敗reset。preflight失敗では触らない |
| 10 ロックの簡略化 | 採用 | Windows/Linuxは既存lock、Mac親はVM単一スレッド、子はstdout_lock。新しい重複lockを増やさない |
| 11 XKB取得失敗／再読込み | 採用 | 物理機能だけunsupported、名前表が実際に変わる時だけ境界。repeatの保留release確定後に反映 |
| 12 Windows SYSKEYUPとshortcut順 | 採用 | 4種のKEY/SYSKEY先頭で物理入力を取り込む |
| 13 辞書ABI | 採用 | builtin追加によるABI不一致と旧イメージ拒否を明記。SC-*はForth定数 |
| 14 ウィンドウなし | 採用 | 自動openなし、query false、snapshot zero。ただし閉鎖前の履歴は取り出せる |

`InvalidAddress=-9`、`InvalidNumber=-24`はsrc/core/defs.zigのerror表で確認した。XKB GetNamesのwire形式もxcb-protoの定義と照合し、設計へ記載した。NamesNotifyのdetail／aliases、Windows特殊キー、AppKitの派生クラスとpoll/出力の相互作用は1084の実装時に確認する。

## Trackerの初回レビューと修正

[初回原文](997-tracker-claude-review.md)は旧版8テスト時点。ブロッキングな不具合はないという評価だが、その後の設計レビューに合わせてoverflowの履歴保持とstale待ちを変更した。availabilityをホストに持つこと、releaseAllとboundaryの名前、KEY-RESYNCが未読履歴も破棄することを設計へ反映した。

最終版は9テスト。通信の連番飛び→早過ぎるresyncを繰り返す→最新snapshot到着→改めてresyncという試験を追加した。コード変更後にWindows通常／除外構成、Linux単体実行、Mac単体コンパイルを再確認する。最終レビューは別原文に残す。

## 最終レビュー

[最終原文](997-final-claude-review.md)では、1079（詳細設計）と1083（pure Tracker）にブロッキングな問題なし、両マイルストーンを閉じてよいと評価された。レビューはコードを実行していない。実際の検証結果は実装記録を参照する。

1084への引継ぎ：復元境界でTrackerをresetしても、Mac側の期待連番とSCANSYNC再送待ちは消さない。後から来た権威あるsnapshotで要求を立て直す。全解放は一度のロック内で行う。閉鎖・EOFが確定して全0が権威ある状態になった場合は、通信snapshot待ちを終えてからunavailableへ移し、要求は利用者の再同期まで残す。

1085への引継ぎ：memoryAddress検査前にhostを呼ばない、scanの範囲検査前に整数を縮小しない、preflight失敗時はresetしない、optional opsなしと辞書ABI不一致の拒否を試験する。
