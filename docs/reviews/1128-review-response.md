# 1128 PCM公開語：レビュー評価と採用判断

2026-11-20。Claude Codeへ読み取り専用で依頼し、原文と判断を分ける。[提案/途中実装レビュー](1128-design-claude-review.md)、[実装レビュー](1128-core-claude-review.md)、[最終レビュー](1128-final-claude-review.md)。レビューは実行確認を含まない。

- C1採用：drainingをdetach publish前に立て、停止待ち尾部を誤計上しない。
- C2採用：到達しない想定のControl.publish失敗もHostFailedへ伝え、無期限待ちへ化けさせない。
- C3はack進捗を保持する。drain取消しでphaseを過去へ強制巻戻しせず、opening/runningのどちらもwritableのままにする。未公開のdetachだけdrainingを解除する。
- C4/C5採用：実Engine.sample_rateを使い、不正な入力設定は語の入口でTHROW -24。内部hostの不正出力rateは-265。設定エラーをior -534へ混在させない。
- C6/C7は公開語で既に接続した。CLOSE入口でclosingにし、無効IDはState側を照合してからhost callbackを呼ぶ。stale mismatchはStateの非永続IDを解除する。古いIDが残るhost再起動後はPCM-CLOSE/QUERYで-521を返して回復できる。
- freeの不変条件をassertする。consumer-owned activeをproducerが読むのではなく、producer-owned pending=nullとrequest/ack一致を使い、最後のdetach完了を確認してからtransportを再初期化する。
- D1〜D5を具体化：枯渇EOVERFLOW -587、closingのSTOP -534/QUERY可、WAITのframes範囲外-24、host起動時256KiB固定確保を採用。公開IDは同一process内で再利用せず、起動をまたぐ一意性は保証しない。
- 提案レビューのfast-path案と二重pollを避ける案は一律には採用しない。待機経路はready/ms0でも明示scope/pollを通し、観測済みの中断・host復元失敗を成功に隠さない。hostのaudioWait内のpollも既存の入れ子契約を保つ。通常VM loopや通常ビルドへ暗黙のbudget/pollは追加していない。
- OPENの前に全PCM待機能力を検査し、不完全なcustom hostで新しい未解放streamを作らない。CLOSEはscope.end成功後にIDを無効化し、-516/timeoutではclosing IDを保持する。

実装レビューと最終レビューは高・中の実装欠陥なし。Medium相当とされた試験不足は、pending STOPのtimeout/ack、attach前UNDERRUNS、host再起動ID/Frame解放、実native scopeと外側中断の保持を追加して検証した。

raw入力は新しいPCM待機から既存executionRawPollを呼ぶ。最終静的レビューではPCMでの実raw確認は未確認だったため、専用Windows console/Linux PTYの公開試験を別に追加した。文字/日本語/未完成ESCを残し、WAIT/STOPは-28、CLOSEは-516、その後のCLOSE再試行を確認する。物理キーや実際に聞こえる音の確認とは区別する。

StateをCLOSEせず破棄する埋込みhost、古いIDのあるStateをhost再起動後そのまま完全復元する経路は1053の所有監査へ残す。現在のCLIでは音声停止後にStateを破棄し、LOAD-DICTIONARYの一時StateはPCMを所有しない。workerへwriter/scope/Engineを値コピーしない。
