# PCM公開語の実装・Windows/Linux検証（1128 / 1129）

## Linux PCM実聴1149と親998の完了（2026-11-20）

WSL Ubuntu26.04.1へpulseaudio-utilsと依存ライブラリを導入し、静的musl版Sigmaのpacat pipe経由でWSLg PulseAudio RDPSinkへ出力した。AUDIO?=-1を確認し、レモンがmono/stereo左右・MML/SFX混合・破棄と再開・drain後停止・保存アプリ・物理Ctrl+C後の停止とhello入力の全8項目を実聴してＯＫと回答。case1〜7のunderrun0、case8はCATCH=-28/CLOSE=0、全process code0。1149・1133・998を完了した。[環境・コマンド・実聴記録](measurements/2026-11-20-linux-audio-listening.json)。これはWSL/Linux実行体からPulseAudioを経た実出力の確認で、Linux実機のALSA装置確認とは区別する。以降のLinux未確認・AUDIO?=0は当時の記録。

## Windows実聴1148の受け入れ完了（2026-11-20）

レモンがWindows実装置で8項目を順番に聞き、各項目をokで確認した。48000Hz mono、22050Hz stereo左右、MML/SFXとの混合、破棄と再open、drain後の停止、SAVESYS保存アプリの2音を確認。最後は前面のPowerShellで物理Ctrl+Cを押し、CATCH=-28/CLOSE=0、続くhelloのACCEPTとcode0を記録し、中断後の音の停止も追加確認した。case1〜7のUNDERRUNSはすべて0。Windows11 Pro 10.0.26300、waveOut既定出力（個別endpoint表示名は未取得）。[全実行記録と利用者の確認](measurements/2026-11-20-pcm-windows-listening.json)。

1148を完了。Linux1149は未完了・0%、1133は未完了・auto50%、998は未完了・auto94%。現WSLはAUDIO?=0のため、Linuxの実聴成功とは扱わない。以下の「Windows実聴未確認」はこの受け入れ以前の履歴。

## 998の残件と語群除外再確認（2026-11-20）

1159（Windows）・1160（Linux）を完了。1129の旧`[DEFINED] REQUIRE-AUDIO / PCM-OPEN`の0 0は有効版でも出るため、audio除外の根拠として撤回する。REQUIRE-AUDIOは辞書に残るparsing語なので、定義内でS" REQUIRE-AUDIO" EVALUATEしCATCHで実行した。両OSそれぞれaudio無効4構成で-275、AUDIOと全7組14語が現在の検索順で見つからないこと、stack深さ0を確認。有効4構成では成功0、ALSO AUDIO後に全7組14語が見つかりstack深さ0。1129保存版のSHAを元の記録と照合した16構成に、YM修正後の通常/audio除外の両OS4実行体も加え、計20件成功。[検査コード](../tests/scripts/verify-pcm-exclusion.py)、[全コマンドと原データ](measurements/2026-11-20-pcm-exclusion-recheck.json)。旧測定JSONは変更しない。

998は未完了・auto88%。実装1125〜1128、自動受け入れ1129、Mac1130は完了を維持。残件は1133配下のWindows実聴1148とLinux実聴1149で、どちらも未完了。[8項目の実行手順](PCM_LISTENING_ACCEPTANCE.md)と専用スクリプトを追加し、両OSでcase1〜7の無音実行、case8の専用console/PTYによる合成キーを確認した。実聴/物理入力は未確認で、スクリプトは明示した--audible時だけ生成音を出す。現WSLはAUDIO?=0、libpulse0/libasound2t64未導入。システムへの導入・設定変更はしていない。

PCM実聴1133は、Windows1148とLinux1149の子タスクに分割した。両方とも未完了・0%。OSごとに実装置の確認と実聴結果を記録し、両方が済むまで親1133を完了にしない。

以前のタスク配置変更時点：Windows/Linuxの実聴1133を998の子に移し、親998は未完了・auto85%へ戻した（現在の再確認結果は冒頭の88%を参照）。実装1125〜1128、自動受け入れ1129、Mac受け入れ1130は完了を維持する。未確認の実聴を最後の統合1057へ集約しない。

2026-11-20、Zig 0.17.1、基点main `416caf9`。1127のhost寿命差分と1128の公開語は未コミット。この記録を現在状態とする。Mac実機1130は同日9d1c528で実施し合格した（[下記](#mac実機受け入れ1130)）。

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

Windows GNU/Linux musl各11構成、計22構成をReleaseFast / cpu=baseline / strip=trueでビルドし実行した。graphics/audio/extensionの8組合せと、no-debug（graphics/extensionも除外）、no-files、no-image。audio有効では無音PCMの書込み、空き待ち、drain、停止/close、無効ID、メモリエラー回復、busyを確認。image有効ではPCM所有中SAVESYSから生成したアプリの未所有起動、SAVE/LOAD-DICTIONARYによる再openと既存所有の保持を確認した。audio無効の旧不在確認は証拠として不十分だったため撤回し、上記1159/1160の実行検査で再確認した。

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

すべての公開process試験は無音フレームであり、実際に聞こえる音・物理キーは未確認。Linuxの実PulseAudio/ALSA装置は未確認。MacのAudioQueue実行・生成アプリ・混合・待機中断・停止/再開・資源回収は1130で確認した（下記）。埋込みhostがCLOSEせずStateを破棄する場合の所有規則は1053の監査対象として残す。

## Mac実機受け入れ（1130）

2026-11-20、main `9d1c528`、macOS 27.2.1 / Apple M5 / Zig 0.17.1。`docs/measurements/2026-11-20-pcm-public.json`の`source_sha256_lf`全19ファイルと一致するソースで実施し、合格とした。作業ファイルは`.work/1130-mac/`（git管理外）。

| 対象 | 結果 |
| --- | --- |
| `zig build test` | 成功 |
| core（aarch64-macos） | 1124成功・10除外・失敗0 |
| host（aarch64-macos、リポジトリ直下で実行） | 152成功・21除外・失敗0。Windows/Linux専用の寿命試験は除外、共通の停止/join・timeout保持・時計故障・cleanup失敗・PCM ID/storage再起動は成功 |
| 阻害consumer（`verify-audio-shutdown.py`） | 3回ともstatus1と期待stdout（0.305/0.022/0.018秒） |

ReleaseFast / cpu=baseline / strip=trueで11構成を作った。audio有効の7構成（graphics/extensionの4組合せ、no-debug、no-files、no-image）は`verify-pcm-stream.py`が成功し、no-imageは画像系3ケースを除く3ケース。audio無効の4構成では`REQUIRE-AUDIO`の実行が-275で失敗し、audio有効版では成功して`ALSO AUDIO`後に`PCM-OPEN`が見つかる（`0 -1`）。（2026-11-20訂正：当初記録した`[DEFINED] REQUIRE-AUDIO . [DEFINED] PCM-OPEN .`の`0 0`は、REQUIRE語が`[DEFINED]`で見つからず、PCM-OPENも`ALSO AUDIO`前は検索順にないため、audio有効版でも同じ結果になり不在の証拠にならなかった。上の方法で確認し直した。）全機能版1,990,632 byte、audio・graphics・extension全除外版1,513,160 byte。

`verify-pcm-terminal.py`の専用PTY 5ケースを全機能版、graphics/extension除外版、debug/graphics/extension除外版で実行した。WAIT/STOPは-28、CLOSEは-516の後に再試行0、`ab`・未完成ESC列・`日`を保持し、PENDINを除いた端末設定が復元された。

実装置の確認：

- `AUDIO?`は-1で、AudioQueueの既定出力を使った。
- 1プロセス内でPCM-OPEN/WRITE/（半数はdrain STOP）/CLOSEを1000回、22050Hz monoと48000Hz stereoを交互に行った。初回open/close後のfd13・thread7は1000回後も同数で、次のIDは1002（再利用なし）。初回の増加は音声hostとAudioQueueの起動分。
- 32768フレームを書いた直後にBYEするプロセスを50回実行し、全てstatus0、stderrなし、終了時間の中央値0.077秒・最大0.090秒。再生中のAudioQueueのStop/Disposeで停止しないことを確認した（1127レビューの照合事項）。callback内部の待ち合わせをAppleの実装として観測したものではない。

レモンがGhosttyで実際に聞いて確認した（三角波、振幅4096）。下記は画面出力に加え、事前に示した聞こえ方と違うという報告がなかったものである。

1. 48000Hz monoの440Hzを2秒。
2. 22050Hz stereoで左だけ・右だけを各1.5秒（再標本化とチャンネル）。
3. PCMの220HzとMML `PLAY`のメロディの同時再生（混合）。
4. 32768フレーム書込み後150msでPCM-STOP 0（破棄）→即停止、1秒後に開き直して再開。
5. PCM-STOP 1でdrain後に`drained`表示。UNDERRUNSは0。
6. SAVESYSで作った保存アプリから523Hz→784Hzを再生、status0。
7. PCM-WAITで鳴り続ける550HzをCtrl+Cで中断：`CATCH= -28 CLOSE= 0`、音が停止、続く`ACCEPT`で`hello`を受け取りstatus0、その後のシェルの`echo`も正常。

物理キーボードからの入力はCtrl+Cと`hello`のみ。LinuxのPulseAudio/ALSA実装置とWindows waveOutでの実聴は引き続き未確認で、tque 1133に登録した。
