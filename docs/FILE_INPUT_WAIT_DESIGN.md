# ファイル入力の期限待機（1078）

2026-11-19。639の先行項目。638のstdin専用EKEY-WAITを選択ファイルへ拡張する。新しい公開語・Builtin番号は追加しない。WAIT-FILES/READ-AVAILABLE、部分書込み、Windowsの汎用読取りワーカーは639の後続範囲。

## 契約

- INFILE-EXECUTEで選択した非stdinにもEKEY-WAIT ( ms -- event flag ior )を適用。0はpoll、負数は無期限、正数は呼出し全体の単調期限。完成UTF-8を返し、ESCは文字27、バイト3は文字3。マウス・paste・端末ESC復号は行わない。
- timeoutは0 false 0、EOFはK-EOF true 0、対象iorは0 false ior。UTF-8の途中はtimeout/時計障害/割込みで失わない。不正/途中EOFの復号は既存standard_eventの規則を使う。
- FileOpsにoptional event_wait(context,fid,ms) callbackを追加。古い埋込みホストで未提供なら入力を消費せず-21。スタック3セルの余地を消費前に検査。stdinは既存の経路を変更しない。
- ホストが既存の64ファイルslotごとにDecoderを持つ。State/辞書イメージへは追加しない。スコープ出入りやTHROWで破棄しない。単一VM所有、同一FILEの同時読取りは対象外。

## バイトAPIと寿命

- KEY-FILE、READ-FILE、READ-LINE、選択ファイルのKEY/XKEY/EKEY、INCLUDE/SLURPは同じホストの保留バイトを先に読む。EKEY?は従来どおりバイトreadinessを照会し、保留を消費しない。
- FILE-EOF?は保留があればfalse。KEY?-FILEは保留があればtrue。空READ-FILEは検査のみで保留を変えない。
- FILE-POSITIONはC streamの論理位置から未消費Decoderバイト数を引く。FILE-SIZEの内部seekでDecoderは破棄しない。REPOSITION-FILE成功時だけ保留とEOFをclear。失敗時は維持。
- 保留があるupdate streamへWRITE-FILEするときは、論理位置へseekし成功後に保留をclear。seek不能ならiorを返し、保留を維持。RESIZE/FLUSHは保留を維持。
- OPEN/CREATE/OPEN-PIPE成功時にslotを初期化。CLOSE/CLOSE-PIPEと全ファイル回収で破棄。ID再利用時に前回のバイトを継承しない。

## ホスト待機

- 既存C streamを使い、POSIXはO_NONBLOCKを一時的に設定してgetcしflagsを復旧する。libc内の先読みも尊重する。EAGAIN/EINTRは一時的、EOFとiorを区別。
- Windowsはdiskと、既存unbuffered pipeを対象とし、PeekNamedPipeで読取り可能/切断を調べる。console等の未対応handleはiorを返し、無期限getcへ入らない。
- 待機はClock/Deadlineを使用し、未準備時は最大1msずつsleep。pollではsleepしない。OSスケジューリングとディスク処理時間の厳密な上限保証はしない。バックグラウンドthread/新規OS資源は作らない。

## 検証とレビュー

分割UTF-8のtimeout→scope退出→KEY-FILE/READ-FILE、同一fid再入、別fid、EOF/ior、位置/size/seek失敗、close/ID再利用、空read、バイト3/ESC、古いFileOps、スタック満杯を確認する。WindowsとLinuxの実パイプで遅延送信・途中EOFを実行し、全体/機能除外とMacコンパイルを区別して記録する。設計/実装ともClaude Codeレビューを行う。Mac実行は利用可能環境で別途確認する。

## 設計レビューの採否

Claude CodeのB1〜B5を採用する。押し戻しとreadyの先読みも同じDecoderの先頭へ戻し、非stdinにはungetcを使わない。EOFより保留を優先する。beginInput/endInputで操作全体のCtrl+Cを捕捉し、readをpeekしてから終了処理を成功させ、最後に結果を消費する。終了処理失敗時もバイトを残す。slot初期化を共通関数にまとめる。

callbackのmsはCellと同じi64。期限は既存Deadlineのi128演算を使う（i64ミリ秒の加算が現在の時刻で飽和する必要はなく、算術overflowは既存エラー）。スタックは純増2セルを検査する。機能不在はiorではなくTHROW -21。

Decoderを小型の専用8バイト版へ書き換える提案は採用しない。復号と保留操作の実装を共用し、ホストの固定64slotのみで使用する。サイズを検証記録へ残す。Stateや保存イメージは増やさない。一般unreadが満杯なら既存DecoderのHostFailedを返し、バイトを失わない。

RESIZE後も保留はlibc先読みに準じて維持する。POSIXの一時O_NONBLOCKは同じopen file descriptionを共有する外部利用者へ影響しうるため、同一streamの並行利用は非対応。無保留のupdate streamで読取り→書込み時の位置付けは既存の別課題として登録する。

## 実装レビューによる訂正

通常EKEYは従来のfileKey経路を維持する。新wait経路の対象はEKEY-WAITだけで、Windows文字デバイスの既存EKEYを退行させない。READ-FILEは保留を消費せず先にコピーし、不足分を既存のfreadで読む。成功／EOF時のみprefixを消費し、読取りエラー時は保留を残す。要求長まで読む従来の契約を維持する。割込みcleanup後のcommit境界とflags復旧失敗後のバイト順は、テスト専用fault seamで検証する（実際のOS障害を起こす試験とは区別する）。

最終レビューで指摘されたREAD-FILEのshort readはForth 2012の契約に合わないため取り下げた。標準原文：https://forth-standard.org/standard/file/READ-FILE 。保留prefixのみをトランザクション化する方式に確定する。

1091のupdate stream境界は後続で実装した。保留がなくても読取り後に位置を同期し、EOF probeでCRT EOFが解除された場合も扱う。native pipeは方向切替にseekを使わず、POSIXでも生fdへ統一する。検証とレビューは[ASYNC_IO_IMPLEMENTATION.md](ASYNC_IO_IMPLEMENTATION.md)に記録する。
