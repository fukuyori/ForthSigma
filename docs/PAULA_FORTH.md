# Paula のForthレジスタモデル（1137）

2026-11-21：モデルと補助の表は`include/`へ移し、`*-DEMO-SETUP`などデモ用の語は`examples/<名前>-demo.fs`へ分けた（1185）。`*-play.fs`はデモのファイルを読む。以下の記録にある`examples/`のモデルのパスは、移す前のものである。

## Linux実聴1156の受け入れ完了（2026-11-20）

レモンがWSL上のLinux版→pacat→WSLg PulseAudio RDPSinkで、4声stereo約3秒、DMACON=6/9による左だけ→右だけ各約1.5秒を確認。物理Ctrl+C後の停止と約3秒の再再生も確認し、CATCH=-28/handle=0、REPLAY-OK handle=0、code0、underrun0を記録。1156と親1137を完了。[環境と全結果](measurements/2026-11-20-linux-audio-listening.json)。Linux実機ALSA・実機Amiga互換の確認ではない。以下のLinux未確認は履歴。

## Windows実聴1155の受け入れ完了（2026-11-20）

レモンがWindows11 Pro 10.0.26300、waveOut既定出力でPA-DEMO-MEMORY/PA-DEMO-SETUPの4声stereo約3秒と停止を確認した。DMACONへ6（ch1/2停止）、9（ch0/3停止）を書き、左だけ→右だけを各約1.5秒聞いて分離を確認。連続再生を前面PowerShellの物理Ctrl+Cで止め、音の停止、CATCH=-28/handle=0、その後約3秒の再再生とREPLAY-OK handle=0を確認した。全processはcode0、記録したunderrunは0。[全コマンド・ソースと実聴記録](measurements/2026-11-20-paula-ym-windows-listening.json)。1155を完了しLinux1156は未完了。以下のWindows未確認はこの受け入れ以前の履歴。実機Amiga互換は対象外。

2026-11-20、基点main1f1a67c。実装1145・Windows/Linux検証/測定1146を完了した。親1137は未完了・auto66%。Mac受け入れ1147も同日に合格し（[下記](#mac実機受け入れ1147)）た。Windows/Linuxの実聴1155/1156が1137の子として残るため、親1137は未完了。既存AMIGA-SOUND/Builtinは変更しない。

## 一次資料と独自の取り決め

[Amiga Hardware Reference Manual第5章の写し](https://www.amigarealm.com/computing/knowledge/hardref/ch5.htm)、[付録A](https://www.theflatnet.de/pub/cbm/amiga/AmigaDevDocs/hard_a.html)、[付録B](https://www.theflatnet.de/pub/cbm/amiga/AmigaDevDocs/hard_b.html)を参照した（2026-11-20）。符号付き8bitの2標本/word、0/3=L・1/2=R、PAL3546895Hz、LC/LEN、VOL bit6最大64、set/clearと割込みbit、attach先と交互制御を照合した。第5章はPAL最小123、NTSC124を記載するためPALモデルでは123を採用し、既存MML用の共通124へ変更していない。付録Aの124表記との差を隠さない。

以下は今回の独自モデル規則であり、実機のclock精度の保証ではない。512KiB/19bitのOCS想定メモリ、PER/LEN0=65536、次tickでの即時fetch、last-word fetchでのreload、DMA無効化直後の停止とDAC保持、同時期限のvoice順、word単位でのattachを宣言する。実機Agnusのscanline slot・14clock応答・初回word破棄・CPU/Copper/DMA競合や割込みpipelineは実装しない。NTSC/ECSの拡張メモリ、analog/LEDfilter・帯域制限、ROM/MOD再生や実機互換も対象外。既存AMIGA-SOUNDにはfilterやMMLのADSRがあり、今回の出力とは一致しない。

第三者のエミュレーターのコード、ROM、MODや曲のデータは取り込んでいない。サンプルは独自のbyte[i]=(37i+11)&255を最初の1024byteへ置き、残りは0にする。レジスタの事実と独自の状態遷移は分けて記録する。

## ライブラリ語と入力契約

リポジトリのルートから読み込む。読込みだけではaudioを開かない。64bitセル、48kHz stereo signed16 little-endian。

| 語 | 契約 |
| --- | --- |
| PA-RESET ( -- ) | register/内部状態/予定表/IRQ/mask/端数/統計/slow選択を初期化。サンプルメモリは保持 |
| PA-MEM! ( byte address -- ) | 0..7FFFFへ0..255を現在の時点で書く。範囲外-24。既にfetchしたwordには影響しない |
| PA-WRITE ( word offset tick -- ) | 16bit valueをcustom-chip offsetへ指定tickまで進めて書く。DFF000を含めたCPU番地ではない |
| PA-EVENT! ( word offset tick -- ) | 同じ書込みを時刻順の予定表に追加。未処理1024件、満杯-528、逆行-24、同時刻は追加順。処理済み領域を回収 |
| PA-TO ( tick -- ) / PA-RUN ( ticks -- ) | 絶対／相対時刻へ進める。逆行・負の相対値・符号付き64bitの加算overflowは-24 |
| PA-READ ( offset tick -- word ) | DMACONR002・ADKCONR010・INTENAR01C・INTREQR01Eを読む。ackしない |
| PA-IRQ? ( -- flag ) | INTENA masterとaudio enable/pendingの積が非0か。状態は変えない |
| PA-SAMPLE ( -- left right ) | 現在のDACとvolumeを左右へ混合。時間を進めない |
| PA-RENDER ( address frames -- ) | 端数を引き継いで48kHz stereoを生成。領域は呼出し側で確保。負のframe数-24。途中のoverflowは巻き戻さない |
| PA-DEMO-MEMORY ( -- ) / PA-DEMO-SETUP ( -- ) | 独自データの配置／4声設定。RESET単体ではメモリを消さない |
| PA-STREAM ( blocks audible -- ) | paula-play.fsを読んだ時だけ有効。512frame単位のstereo PCM。FALSEは合成後ゼロ化、TRUEだけ生成音を送る |

AUDxのoffsetはA0+10h*xからLCH/LCL/LEN/PER/VOL/DATの順に2byte刻み。DMACON096、ADKCON09E、INTENA09A、INTREQ09C。奇数/範囲外/未対応/readonlyへのwriteは-24。奇数・範囲外のreadは-24、対応外のreadは-21。数値は0..65535で、許可mask外のbitはset/clearどちらでも-21。DMACONは020F、ADKCONは00FF、INTENAは4780、INTREQは0780だけを扱い、他機能のbitを黙って変えない。8000単独の変更なしは受け付ける。

LCHは&7、LCLは&FFFE、VOLはbit6なら64、そうでなければlow6bitを使う。PERは0を65536と宣言し、1..122は-21で受付拒否する。このPER0の宣言を実機の保証値と扱わない。LEN0も65536words。メモリpointerは7FFFFの次に0へ折り返す。

値・offset・mask・PER・過去時刻・予定表の順序/容量は、時間/queue/状態の変更前に検査する。tick tのwrite/readは、期限t以下の遷移と予定writeを先に処理する。即時writeは同時刻の予定writeより後。PA-SLOW=TRUEは1tick版、既定FALSEは次byte期限までまとめる版。内部ヘルパーは共有するため、独立したPythonの1tickモデルと手計算を補う。

## DMA・手動出力・IRQのモデル順序

DMAEN bit9 AND AUDxENの立上りでLC/LENを内部へcopyし、最初のfetch/上位byte出力は次tick。PER tick後に下位byte、さらにPER tick後に次wordをfetchする。wordはbig-endianの2byteを一括して保持する。進行中のPER counterはCPU/attachの変更で戻さず、次byteのreloadから新値を使う。volumeはPA-SAMPLE時に使うので即反映する。

IRQ pendingは、DMA enable後の最初のfetchと、各last-word fetchで立つ。初回以外のblockの先頭では重ねて立てない。LEN1なら同じtickの初回/末尾要求は1bitへ合流する。last-wordを取得した瞬間に次block用LC/LENもcopyするため、その後のCPU書込みはさらに次のreloadから有効となる。これは実機pipelineを省いた明示的な規則であり、IRQはbyte完了位置の実測値ではない。

DMAEN/AUDxENの立下りで即停止し、最後のDAC値とIRQ pendingを保持する。再開は新しいLC/LENから。短いdisableで実機が途中再開する可能性は再現しない。

DMA無効のDAT書込みは1word latchへ置く。idleなら次tickからhigh/lowを出す。再生中なら現在のwordを切らず、次wordとして保持し、複数の書込みでは最後の1wordが残る。2PER経過してwordを出し終わるとIRQを立て、latchがあればそのtickに次wordのhighを出す。無ければidleとなり最後のDACを保持する。DMA中のCPU DATはregisterだけを更新し、fetch済みのwordとその出力を変えない。実機のIRQ ackに伴うstate-machineの分岐まで再現するものではない。

各tickはまず全声のcounterを減算して期限をsnapshotし、voice0→3順で遷移する。attachが同tickに次声のPERを変えた場合、その次声のreloadは新値を使い、期限済みかどうか自体は変更しない。

## Attachと混合

volume-onlyはfetchしたwordをVOLと同じ規則（bit6優先64、そうでなければlow6bit）で次声のvolumeへ、period-onlyはword全体を次声のPERへ渡す。bothはblock先頭をvolumeとしてwordごとにvolume/periodを交互適用する。ここでは2byteをword単位にまとめ、実機の010/011 request差は再現しない。manual開始もvolumeから。再生中のADKCON変更自体では交互位相を戻さない。attachを解除しても対象は最後の値を保持し、CPUとattachのうち最後に書いた値が有効。programmed PER/VOLの控えはCPU値を保持し、effective latchとは区別する。

attach元は自身をmuteするがDMA/IRQは止めない。ch3のattachはmuteだけでch0へwrapしない。変調でPER0なら65536、1..122なら123へ丸め、PA-PER-CLAMPSに加算する。外部PER writeの拒否と区別する。

各声のsigned8×volume×2をsideごとに加算する。最大32512、最小-32768でs16に収まり、最終clippingやfilterはない。ゼロ次holdの点標本なので折り返し雑音があり、実機の音質・音量再現とは主張しない。

## 検証・測定と残作業

```powershell
sigma examples/paula-play.fs -e "PA-DEMO-MEMORY PA-DEMO-SETUP 16 FALSE PA-STREAM BYE"
python tests/scripts/verify-paula.py zig-out/bin/sigma --benchmark
```

Pythonの1tickモデル、Forthの基準/まとめ処理/分割描画を全PCM・状態で比較する。手計算したbyte順・manual latch・IRQ mask・メモリwrap・buffer保持・PER変更遅延、全128volume値、全256attach mask、512KiB全byteの保持、不正値の状態原子性を含む。PCM自動確認は合成後にゼロを送り、実聴と区別する。Mac確認1147は下記で実施済み。

測定は32768frame、初期化/reset/warm-up/初期queueを時間外にし、6負荷で7つの新processを使う。NTIME wall nsとuser+system CPUTIME usを保存する。通常・1tick版・全4声最小周期123/LEN1・変調・8kHz volume書込み・8kHz手動DATを分け、streaming enqueue/領域回収は時間内に含める。各負荷は別の計時しないprocessで全PCMをPythonと比較してから計測する。原データ・採否は以下に記録する。

補助の`python tests/scripts/verify-paula-stream.py SIGMAのパス`は、実PCMを開かないprocess内fixtureでstereo2ch/4byte offset、partial→full→再試行時の全byteコピー、timeout、close再試行、本体/cleanup例外の優先とID保持、open失敗、drain失敗を検証する。非ゼロの生成音をメモリへコピーするだけで、装置へは送らない。both attachの64→123→32→124と交互適用の5境界と、奇数LEN3のblockでvolumeへ戻る境界も、手計算値で別に検査する。

## Windows/Linuxの結果と採否

Windows GNU/Linux musl（WSL）の通常版、debug/graphics/extension除外版、さらにfloat除外版の6構成で、各10検査群と補助10検査が成功した。32768frameの6測定負荷も、計時しないForthの全byteとIRQ/丸め/fetch数をPythonと照合した。8192frame・1365件の8kHz writeでは、予定表1024件を超える領域回収も全stereo PCMで比較した。固定2048frameのSHA256はab75b30b15c8d7f96ad1d05d57931f054d132483ad9779a07b7f8ce5560ad52d。

| 負荷 | Windows実時間倍率 | Linux実時間倍率 |
| --- | --- | --- |
| 通常まとめ版 | 9.443 | 10.463 |
| 通常1tick版 | 0.568 | 0.708 |
| 全4声PER123/LEN1 | 6.556 | 7.880 |
| volume/period変調 | 5.517 | 6.443 |
| 8kHz volume write | 8.626 | 10.289 |
| 8kHz manual DAT | 7.637 | 8.754 |

倍率は音声時間÷wall中央値。各32768frame、2421346tick（約0.683秒）を7つの新processで測った。AMD Ryzen7 7700（8core/16thread）の同じhostでWindows/Linuxを順番に測り、他アプリの停止やclock固定はしていない。6負荷とも左右に非ゼロの標本があり、変調負荷も全音量0を測ったものではない。NTIMEのwallは時計変化の影響を受け得るため、全7回のuser+system CPU時間も残した。[全結果・コマンド・ソース本文とLF指紋](measurements/2026-11-20-paula.json)を参照。

宣言したPaula単独のモデルはForthで維持し、追加のBuiltinやnative化は行わない。Agnus busやCPU/Copperを含むAmiga全体の実時間性・互換性の証明ではない。analog/LEDfilterが必要な用途は別途モデルと測定が必要で、既存MML音源と同じ音質ではない。

本体ソースはPCM1128の全19指紋と一致し、既存ReleaseFast/cpu=baseline/strip=true実行体を再使用した。通常版の実行ファイル増加は0。Windows通常版の読込みHERE差は549616byte（前122880、後672496）で、主に512KiBのmemoryと24KiBのqueue。RSSではない。audio/graphics/extension=falseでも純粋合成を両OSで実行し、512frame後は37833tick・stack深さ0。

実PCMへの自動確認は8192frameを合成後ゼロ化し、stereo open/write/wait/drain/closeと、レンダー中のtime overflow後のhandle解放を確認した。WindowsはAUDIO?=-1、WSL LinuxはAUDIO?=0の無音consumerで、Linux実装置の検証ではない。非ゼロPCMの補助fixtureも装置へ送らないため、生成音の実聴完了とは扱わない。

Mac受け入れ1147は下記で合格した。既存PCM基盤のMac1130完了とは別である。Windows/LinuxのPCM実聴1148/1149も各機能の配下に残る。

[レビュー評価・採否と設計/実装/追加/最終の原文](reviews/1137-review-response.md)を保存した。追加レビューのMediumは奇数LEN3の検査で解決し、最終ClaudeレビューはHigh/Mediumなし。tempコピーでresetを外した負の対照も、stack0で値の不一致を検出した。Mac1147は下記で確認した。

## Mac実機受け入れ（1147）

2026-11-20、main `cf080b4`、macOS 27.2.1 / Apple M5 / Zig 0.17.1。Zigソースは9d1c528から変更がなく、1130で作ったReleaseFast / cpu=baseline / strip=trueの実行体（全機能、debug/graphics/extension除外、float/debug/graphics/extension除外、audio/graphics/extension除外）を使った。作業ファイルは`.work/1147-mac/`（git管理外）。

| 対象 | 結果 |
| --- | --- |
| verify-paula.py --benchmark（全機能・debug等除外・float除外） | 各10検査群成功、全検査の結果がWindowsの記録と一致。固定2048frame ab75b30b…ad52d |
| verify-paula-stream.py（同3構成） | 各10検査成功、結果がWindowsと一致 |
| audio/graphics/extension除外 | `37833 0`、status0 |
| 論理辞書領域 | 122880→672496、差549616byte |
| 無音PCM送出 | 8192frame stereo、AUDIO?=-1、全process約0.284秒 |

合成負荷（32768frame、各7process中央値。音声時間÷wall）：

| 構成 | 通常まとめ | 1tick | PER123/LEN1 | 変調 | 8kHz volume | 8kHz DAT |
| --- | --- | --- | --- | --- | --- | --- |
| 全機能 | 14.27倍 | 0.90倍 | 9.81倍 | 7.95倍 | 12.94倍 | 11.37倍 |
| debug等除外 | 10.85倍 | 0.78倍 | 7.16倍 | 6.30倍 | 9.77倍 | 8.76倍 |
| float除外 | 11.03倍 | 0.81倍 | 7.79倍 | 6.47倍 | 10.40倍 | 9.08倍 |

左右の分離は、デモ設定の後にDMACONへ6（ch1/2停止）または9（ch0/3停止）を書いて確かめた。1秒分の描画で、左だけは右が全標本0、右だけは左が全標本0だった（左右とも鳴らすときのRMSは6795/6774）。

レモンがGhosttyで実際に聞いた（`.work/1147-mac/paula.fs`）。4声stereo約3秒、左だけ・右だけが正しく分かれて聞こえた。連続再生中のCtrl+Cで`CATCH= -28 handle=0`、その後の再再生、`ACCEPT`での入力。各回underrun0、fd13は不変、thread8→7。1回目のCtrl+Cは合成中に届いてOS終了となり、2回目で上記を確認した。NES/SIDと同じく、確認点のない計算中のCtrl+Cは既存の中断規則でOS終了になる。全機能版（extensionとdebugを含む）では、合成の呼出しをEXEC-LIMITED（予算0）で包めば合成中のCtrl+Cも-28で捕捉できる。ただし実行制御の記録どおり包んだ中の計算は約2.8倍遅くなり、Macでの試算ではSIDデモが約1.3倍、Windowsでは約0.9倍と実時間を下回るため、例には組み込まない（2026-11-20に試作し、全機能版で20回中20回-28を確認した後に取り消した）。

Windows/Linuxでの生成波形の実聴は未確認（tque 1155（Windows）・1156（Linux））。Agnus bus・analog filter・実機Amiga互換は範囲外のまま。
