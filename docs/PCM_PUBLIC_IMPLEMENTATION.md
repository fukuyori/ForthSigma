# PCM公開語の実装・Windows/Linux検証（1128 / 1129）

2026-11-20、Zig 0.17.1、基点main `416caf9`。1127のhost寿命差分と1128の公開語は未コミット。この記録を現在状態とする。Mac実機1130は未実施で残す。

## 実装範囲

AUDIOにPCM-OPEN / WRITE / QUEUED / WAIT / STOP / CLOSE / UNDERRUNSの7語と対応するSND-PCM-*を追加した。[利用方法と英日スタック表](GRAPHICS_AND_SOUND.ja.md#pcmストリーム)、[採用契約](PCM_STREAM_DESIGN.md)を参照。

- 入力はs16LE mono/stereo、8000..192000Hz、2の冪256..65536入力フレーム（40ms..1秒）。音声hostにつき1ストリーム。host開始時に最大容量のFrame領域256KiBを確保し、join成功後に回収する。PCM-WRITEの受理分はコピーし、呼出し後に元のメモリを借りない。
- Stateの非永続audio_pcm_handleとSessionのowner/IDを照合する。他State・古いIDを拒否し、同一process内ではhost再起動後もIDを再利用しない。別processで同じ数値になる可能性はあり、イメージ中の数値を実行中handleとして復活させない。
- WAIT/STOP/CLOSE全体で既存のnative execution scopeを保持する。通常VMループに暗黙のbudget/pollを加えず、debug/graphics/extension=falseでも使える。raw入力は既存executionRawPollに渡す。CLOSEはscope終了成功後にのみIDを無効化し、中断・期限切れではclosingを保持して再試行できる。
- 完全復元はPCM所有中に-528。LOAD-DICTIONARYの追記は対象の所有を保つ。一時Stateと保存アプリの新しいStateは未所有。SAVE/SAVESYSには音声thread、リング、ownerを保存しない。Builtinタグ7個の追加で画像ABIが変わるため、古い画像はソースから作り直す。
- QUEUEDとdrainはengineの消費を表し、device再生位置ではない。再標本化はsample holdでアンチエイリアスなし。混合は既存音声の処理後に飽和加算する。

## Claude Codeレビュー

読み取り専用で提案/途中・実装・最終の3段階を依頼した。[原文](reviews/1128-final-claude-review.md)と[評価・採否](reviews/1128-review-response.md)を分離した。drainとdetach公開の順序、内部publish失敗、実出力rate、解放の不変条件を反映した。最終静的レビューはHigh/Mediumの実装欠陥なし。指摘された試験不足にはpending STOP、attach前UNDERRUNS、host再起動IDとstorage、実native scopeの試験を追加した。レビュー担当による実行確認は含まない。

## 実行結果

失敗0。一次データ・コマンド・バイナリSHA256・LF正規化ソース指紋は[JSON](measurements/2026-11-20-pcm-public.json)に保存した。以前の測定JSONは変更していない。

| 対象 | 成功 | 除外 | 範囲 |
| --- | --- | --- | --- |
| Windows core | 1124 | 10 | 公開語、境界、State/画像、pending detach等 |
| Linux core (WSL) | 1124 | 10 | 同上を実行 |
| Windows host | 162 | 15 | native scope、ID/storage再起動、1127寿命試験を含む |
| Linux host (WSL) | 167 | 17 | 外側scopeへの中断保持を含む |

`zig build test`成功。aarch64-macosのcore/host cross compile成功は実行確認とは区別する。

Windows GNU/Linux musl各11構成、計22構成をReleaseFast / cpu=baseline / strip=trueでビルドし実行した。graphics/audio/extensionの8組合せと、no-debug（graphics/extensionも除外）、no-files、no-image。audio有効では無音PCMの書込み、空き待ち、drain、停止/close、無効ID、メモリエラー回復、busyを確認。image有効ではPCM所有中SAVESYSから生成したアプリの未所有起動、SAVE/LOAD-DICTIONARYによる再openと既存所有の保持を確認した。audio無効ではREQUIRE-AUDIOとPCM-OPENの不在を確認した。

専用WindowsコンソールとLinux PTYで各5ケースを実行し、WAIT/STOPで-28、CLOSEで-516と再試行、ab/日本語/未完成ESC列の保持、端末設定の復元、全子processの正常終了を確認した。Windowsは通常版とdebug/graphics/extension除外版、Linuxはgraphics/extension除外版とdebug/graphics/extension除外版。利用者のコンソールには入力していない。

英日HELPは1605件、全ワード参考書1819項目、AUDIO87語。実行辞書との照合、文書例28件、個別用例415件が成功。すべての既存語も照合対象とした。資源停止・join・強制終了fixtureの詳細は[1127記録](PCM_HOST_LIFETIME_IMPLEMENTATION.md)を参照し、今回の新しいhost試験でFrame領域回収とID増加も確認した。

## サイズと処理時間

以下は同じソース・設定でのバイナリbyte数。audio除外差はPCMだけでなく音声機能全体の差であり、前版からの増加量ではない。

| target | 全機能 | audio除外 | 差 |
| --- | --- | --- | --- |
| x86_64-windows-gnu | 2,145,280 | 2,050,048 | 95,232 |
| x86_64-linux-musl | 2,356,304 | 2,251,440 | 104,864 |

新APIの初回基準値として、専用Forthループ内のUTIME差を7個の新規processで測定した。各processで同じループを1回warm-upし、起動/close時間を除外した。PCM-QUEUEDは100万回、空きのあるPCM-WAIT（1 frame、0ms）は1万回。以下は中央値で、Forthのdispatch/loopと並行音声処理を含む。

| 対象 | QUEUED ns/回 | WAIT poll ns/回 |
| --- | --- | --- |
| Windows | 26.692 | 424.7 |
| Linux WSL | 16.198 | 1048.8 |

WAITはscope/pollを含む。これを装置遅延や前版/Gforthとの速度比較には使わない。既存の一般速度測定とは分け、原データ7回分と測定コードをJSONに保存した。

## 未確認と次の作業

すべての公開process試験は無音フレームであり、実際に聞こえる音・物理キーは未確認。Linuxの実PulseAudio/ALSA装置、MacのAudioQueue実行・生成アプリ・混合・待機中断・停止/再開・資源回収は未確認。Macは1130を未完了のまま残す。埋込みhostがCLOSEせずStateを破棄する場合の所有規則は1053の監査対象として残す。
