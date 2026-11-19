# 638 イベントキューの詳細設計

2026-11-19。採用した設計。1074仕様→1075実装→1076 Windows/Linux→1077 Mac実機。設計・実装レビューを反映し、1074〜1077および638は完了。1077の実機環境・結果・境界は[実装記録](CORE_EXTENSION_IMPLEMENTATION.md)を参照。

## 配置と公開API

coreはOS資源を持たず、標準入力の逐次デコーダと一時保留・最後に取得したマウス情報をStateへ持つ。ホストは入力をbyte/標準セル/マウス付きイベント、timeout、EOF、iorで区別する新しい差替え口を提供する。時計は900のClock/Deadlineを共用する。既存event_key_fnとmonotonic_ms_fnは古い埋込みホストとの互換用に維持する。

EXTENSIONへ次を登録する。audio/graphics/debug/filesは不要。既存EKEY/EKEY?は所属を変えない。

- `EKEY-WAIT ( ms -- event flag ior )`：固定3セル。得られた場合event true 0、期限は0 false 0、EOFはK-EOF true 0、対象の読取りエラーは0 false ior。Ctrl+Cは-28、機能不在-21、時計/ホスト基盤障害-265をTHROW。負数は無期限、0はポーリング。正数は呼出し全体で一つの単調期限。消費前に結果3セルの余地を確認。
- `EKEY-MOUSE ( -- column row buttons wheel )`：最後にEKEY/EKEY-WAITが取得したK-MOUSEの情報。未取得時はすべて0。先読み・別イベント・GRAPHICS操作では更新しない。座標は0起点、buttonsは1左/2右/4中央、wheelは+1上/-1下/0。
- `K-MOUSE`=0x80000022、`K-PASTE-BEGIN`=0x80000023、`K-PASTE-END`=0x80000024。既存の35定数を変更せずEXTENSIONへ追加。非文字としてEKEY>FKEYでtrue、名前表示も対応する。

既存EKEYは新ホスト口があれば共通デコーダで無期限読取りを行いEOFでK-EOF、対象iorは従来どおりTHROW。新ホスト口のない古い埋込みでは従来のEKEY経路を維持し、EKEY-WAITは-21。新口は通常のSigmaホストで常に提供する。EKEY?は新口では完成イベントだけを先読みし、EOFではfalse。先読みした生バイトを保持し、KEYが読める互換性を守る。

## 期限と保留

32バイトの逐次バッファと、途中バイトより後に来たネイティブイベント1個を上限とする。イベントを1つ完成させる分だけホストから読む。0msのpollは1呼出しで64入力項目までとし、無視する通知の連続でも無期限に回らない。Windowsのnative.nextは1回32レコード、外側も32回までに区切る。満杯で更に読まず、未知/過長の列は先頭ESCを返して残りを次へ保持する。外部の非同期キューは作らず、端末/パイプの未読入力へ背圧を掛ける。ウィンドウ側のキュー損失回復は1041/1042の担当。

ESCの曖昧さは最初のESCから50ms。呼出しの期限が先ならtimeoutとして途中列をそのまま保持する。次回もESCの50msを延長しない。UTF-8途中もtimeout/割込み/対象iorで保持する。不正UTF-8は既存のU+FFFD規則と同じ。EOFで途中UTF-8を確定してからEOFを返す。ESC/UTF-8の途中に完成したネイティブイベントが来れば、そのイベントを先に返し、途中の生バイトとESC時刻を保持する。次の呼出しで列を継続する。リサイズによって矢印等の列を分断しない。

時刻の加算・差分はruntime_base.Deadlineを利用し、ホストはremainingの範囲内で待つ。既に完成した保留イベントと、残り時間内でホストを呼んで完成したイベントを、期限より先に返す。期限は次のホスト呼出し前に判定する。OSの待機・スケジューリングによる超過まで実時間の上限を保証するものではない。時計の失敗をtimeoutや0時刻へ置き換えない。

## マウスと貼り付け

POSIXのSGR `ESC[<b;x;yM/m` を標準イベントにし、Windowsのコンソールマウスレコードも同じ情報にする。GRAPHICSのMOUSE-EVENTの値やキューは変更しない。buttonsはイベント後の押下集合とし、SGRは独自に追跡する。shift/alt/ctrlはK-MOUSEへ既存の修飾マスクをORする。1003の移動も返し、横ホイールと拡張ボタン（8〜11）は標準イベントとして公開せず消費する。これはEKEY?でも消費し、KEYへ戻さないプロトコル上の除外である。X10形式は解釈しない。

bracketed pasteの200~/201~を開始/終了イベントにする。paste中は終了マーカー以外のESC列を文字として渡し、値3も割込みにしない。CR/LF/TABは値を変えず、UTF-8は文字へ復号。timeoutではpaste状態を維持し、EOFで貼り付けを打ち切りK-EOFを返す（ENDは合成しない）。Windowsは637の決定どおりpaste要求を送らない。TERM-MODE!でpasteを止めたとき、raw入力へ入り直した通知、EOF、他の入力APIへの切替でもpasteを解除する。貼り付け外の201~もENDイベントで返す。

## 既存入力・復元との境界

KEY/XKEYは標準デコーダが先読みした生バイトを先に取得できる。マウス等のネイティブ非文字イベントは標準側に残す。例えばEKEY?で矢印を先読みした後にACCEPTで一行読んでも、その矢印は次のEKEYへ残る。GRAPHICSへ切り替えるときは保留した生バイトを先にその既存デコーダへ渡す。完成した各語群のイベントキューは独立で、語群を跨いだ先読み済みイベントの全順序は保証しない。KEY/XKEY/KEY-IOR/ACCEPT/標準入力のREFILLやGRAPHICSへ切り替えると貼り付け状態を解除する。切替後はそれぞれの既存の入力規則に従う。端末の行読み取りへはunread_fnで逆順に戻し、GRAPHICSは生バイトを直接先に受け取る。unread_fnを持たない埋込みホストではKEYが生バイトを直接受け取り、ACCEPTはkey_fnから残りを読み、保留した接頭辞と連結する。key_fnもないホストでは入力を保持して-21とする。

EKEY-WAITは標準入力（リダイレクトしたstdinを含む）専用。非stdinをINFILE-EXECUTEで選択中は、入力や保留へ触れず-21をTHROWする。stdinのIDを選んだ場合は許可する。選択ファイルのEKEY/EKEY?は従来経路を維持し、UTF-8だけを復号、ESCを文字として扱い、ファイルiorは元のTHROWで返す。ネイティブEKEYの読取り障害は従来どおり-265。

選択ファイルへの新しい期限付き待機は639配下1078。複数バイトungetcに依存せず、ファイルIDごとの保留・READ-FILE/KEY-FILE/位置・close・ID再利用をまとめて扱う。これを638のscope内だけの保留で代替すると、退出時に入力を失うため採用しない。

標準入力のデコーダはStateに一つ保持し、INFILE-EXECUTEでファイルを選んでいる間も保存場所を変えない。選択ファイルのKEY/EKEY/ACCEPTはこのデコーダへ触れず、stdinを内側に選べば同じデコーダを使う。stdin→ファイル→stdinの順でも先読みと順序を保持する。State.initとイメージ復元では新旧両方の一時入力状態を初期化する。SAVEへ端末イベントや時計・ホストポインタを保存しない。ワーカーState監査とイメージ復元経路を更新する。

## 検証

差替え時計・入力で、期限全体、UTF-8/ESC分割、期限後イベント保留、EOF/timeout/ior/割込み、先読みとマウス、貼付け中のESCとCtrl+C、過長列、入力切替とスタック境界を確認する。Windows独立コンソールでmouseと期限、Linux PTYで分割送信とpaste、既存NS/637入力回帰、全体・機能除外、全語英日参照、Cortex-M0+、Mac向けコンパイルを確認する。Mac実機は1077へ残す。

## 実装構造と互換性

新経路は`standard_event.zig`（pureなDecoder/Packet/Source/Result）と`event_input.zig`のmodern/sourceRead/beforeBytes、ホストのterminalStandardEvent/nextStandardPacketで接続する。Resultはイベント・timeout・EOF・対象ior・raw再開始の内部通知を区別する。新しい操作口はWriter.standard_event_fn、standard_clock、standard_interrupts、unread_byte_fn。Clockのcontextもワーカーへ直接借用しない。

既存のpending_key/pending_event_bytes/pending_standard_eventは、古い埋込みホストと既存試験の互換のため移設せず維持した。新デコーダの入力口ではそれらを先に消費する。古い口のnullからEOFとtimeoutを推測する変換は行わない。

- [設計レビュー原文](reviews/638-design-claude-review.md)
- [レビュー評価と反映判断](reviews/638-review-response.md)

- [実装レビュー原文](reviews/638-implementation-claude-review.md)
- [ファイル対応の工程再検討](reviews/638-file-scope-claude-review.md)

KEY?は保留バイトをそのまま照会し、pasteやESC時刻を変更しない。行fallbackのCR後は、保留またはkey_ready_fnが読めるときだけLFを確認する。マウス報告の明示解除やraw再開で追跡中の押下集合を初期化するが、最後に取得したマウス情報は保つ。

## ホストの押し戻しとEOF契約

unread_byte_fnは原子的操作とし、エラーならそのバイトを受理しない。旧void口は受理を契約とする。nativeホストは65バイト（先読み1+配列64）の範囲でchecked操作を提供する。途中の転送が失敗しても、coreの先頭側とホストの末尾側に元の順序で保持する。新口を持つ埋込みで旧pendingを明示STDINのファイルAPIへ渡すにはchecked口を必要とし、なければ入力を保持して-21とする。

EOFはストリームの終端状態であり、一度きりの通知ではない。押し戻したバイトを先に渡し、読み尽くしたらホストはEOFを再通知する。各バイトの転送成功時にcoreのEOFキャッシュを解除して、ホストへ戻した残りより先にEOFを返さない。転送なしの先読みEOFは消費までcoreに保持する。端末のCtrl+D/Zはrawでは文字であり、このAPIはcanonicalの一度きりのEOF通知をホスト契約にしない。

STDINを明示したKEY-FILE/READ-FILE/READ-LINE/SLURP/INCLUDEも、Decoderの生バイトと旧pendingを先にホストへ返す。KEY?-FILEとFILE-EOF?は保留を照会する。旧pendingもstdin専用の一時キャッシュで入れ子を通じて共有し、語群/入力APIを切り替えても生バイトの順を保つ。

既存EKEYが使う内部Decoderとホスト処理は共通部分として保持し、新しい公開語・定数はextensionで選択する。Builtin追加によりABI署名が変わるため、古い辞書イメージ/SAVESYSはこのビルドで作り直す。

## Mac実機1077の手順

Mac実機1077の受け入れ結果は[実装記録](CORE_EXTENSION_IMPLEMENTATION.md)に記録した。再実行手順として、同一コードでOS/Zig版・コミットと作業差分を記録し、`zig build test --summary all`、`zig build --prefix .work/638-native --summary all`、`python3 tests/scripts/verify-event-queue.py .work/638-native/bin/sigma`、637の`verify-terminal-modes.py --sigma .work/638-native/bin/sigma`とNSの`verify-p05b-ns.py --sigma .work/638-native/bin/sigma --sigma-only`を実行する。`verify-extension-matrix.py`、`scripts/word-reference.py --check --sigma .work/638-native/bin/sigma`、`scripts/check-docs.py`も実行する。クロスコンパイルだけでは実機完了にしない。

- [最終レビュー](reviews/638-final-claude-review.md)
- [最終指摘の再レビュー](reviews/638-followup-claude-review.md)
- [押し戻しのレビュー](reviews/638-pushback-claude-review.md)
- [固定スナップショットレビュー](reviews/638-frozen-claude-review.md)
- [EOF修正の評価](reviews/638-eof-claude-review.md)
