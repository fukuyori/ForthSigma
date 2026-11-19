# 1078 ファイル入力待機の実装記録

2026-11-19。1078を完了。基点コミット085fef2。実装と記録は未コミット。仕様は[詳細設計](FILE_INPUT_WAIT_DESIGN.md)、Claude Codeの指摘と採否は[レビュー記録](FILE_INPUT_WAIT_CLAUDE_REVIEW.md)。

## 実装

FileOpsにoptional event_waitを追加し、選択ファイルのEKEY-WAITだけをホストへ渡す。通常EKEY/EKEY?とstdinの経路は維持する。ホストは既存64slotごとにstandard_event.Decoderを持つ。State・Builtin番号・辞書画像ABIへ追加なし。押戻しも同じ保留へ一本化し、非stdinでは複数ungetcを使わない。

保留をKEY-FILE/READ-FILE/READ-LINE/選択入力のKEY/XKEY/EKEY/INCLUDE/SLURPで共有。位置は未消費prefixを差し引き、seek成功時とopen/close/回収で初期化。FILE-SIZE/空READ-FILE/失敗seekは保留を失わない。WRITE-FILEは保留があれば論理位置へ戻してから書く。READ-FILEはprefixをコピーし、残りの読取りが成功／EOFになった後だけprefixを消費する。

POSIXは既存stdioのバッファを使った非ブロッキングprobe、Windowsはdiskとunbuffered pipeを扱う。汎用threadは追加しない。通常のEKEYはWindows文字デバイスにも従来どおり使えるが、新しいファイルEKEY-WAITはdisk/pipe以外へEINVALのiorを返す。

操作全体をhost_waitの入力guardで保護し、無期限の待機でもCtrl+Cを検出する。Decoderはpeekで復号し、guard終了成功後にcommitするため、中断時も文字を失わない。flags復旧エラーで取得済みのバイトも末尾へ保持する。復旧エラー後のdescriptor状態は保証せずiorで通知する。

## 検証

- Windows全体：23/23工程成功。core1072成功/8skip、host110成功/11skip、共通runtimeは既存キャッシュ。Cortex-M0+のcompileも成功。
- Windows除外（graphics/audio/float=false）：core854成功/200skip、host109成功/10skip。最終READ-FILE訂正後にも再実行して成功。
- Linux musl：core1072成功/8skip、host123成功/5skip、runtime15成功。最終READ-FILE訂正後にもhostを実行し123成功/5skip。
- Windows/Linuxの実遅延パイプ：分割UTF-8のtimeout→再入で「あ」、scope退出→KEY-FILE/READ-FILE、途中EOFでU+FFFD→K-EOF、THROW/seek失敗後のprefix保持の4ケース成功。
- Windowsの独立コンソールで実Ctrl+C通知、LinuxでSIGINTを送信し、無期限定義が-28で戻りprefix E3をKEY-FILEで取得することを確認。人のキーボード操作ではなく、所有する検証プロセスへの制御通知。
- テスト専用fault seam：cleanup/commit境界の中断、flags復旧失敗後のprefix順、READ-FILE失敗時のprefix保持を確認。実際のカーネル障害を起こした証拠とはしない。
- 古いFileOpsのnull callbackは既存のscope/THROWテストで-21と未消費、従来EKEYを確認。追加テストはcallbackの固定結果とstack満杯時の未消費を検証。
- 英日HELP・1777語参照、8語彙のruntime照合、例28本と個別用例377本が成功。公開語追加なし。
- Mac arm64はcross build成功。実行は未確認で1092へ残す。

生ログ・実パイプの構造化結果は`.work/1078/`。実パイプ検証スクリプトは`tests/scripts/verify-file-input-wait.py`、制御通知は`verify-file-wait-interrupt.py`。

## 残り

1078完了時点では639本体の4語と汎用Windows読取りthreadは後続範囲だった。その後1091のupdate stream方向切替、1094の読取り、1095の書込みを実装した。詳細と検証は[ASYNC_IO_IMPLEMENTATION.md](ASYNC_IO_IMPLEMENTATION.md)。1078のMac実機は1092、新しい4語のMac実機は1096。通常ファイルのREAD-FILEが要求長またはEOFまで読む契約は維持する。

最終ソースと各実行体のSHA-256は`.work/1078/final-validation.json`。実装再レビューの指摘を反映し、最終のREAD-FILEレビューでブロッカー解消を確認した。
