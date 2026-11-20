# Atari ST YM2149：既存対応の監査とForthモデル（1138）

## Mac実機受け入れ1154（2026-11-20）

main `53ebe81`、macOS 27.2.1 / Apple M5 / Zig 0.17.1。固定音量0の修正を含むソースからReleaseFast / cpu=baseline / strip=trueで4構成（全機能、debug/graphics/extension除外、float/debug/graphics/extension除外、audio/graphics/extension除外）を新たにビルドした。作業ファイルは`.work/1154-mac/`（git管理外）。

| 対象 | 結果 |
| --- | --- |
| native | `zig build test`成功。core 1126成功・10除外、host 152成功・21除外、失敗0。`fixed zero volume mutes every PSG channel without muting envelope level one`成功 |
| ym2149-levels.py --check | 32項目再現 |
| verify-ym2149.py --benchmark（全機能・debug等除外・float除外） | 各11検査群成功、全検査の結果がWindowsの記録と一致 |
| verify-ym2149-stream.py（同3構成） | 各12検査成功、Windowsと一致 |
| audio/graphics/extension除外 | 512frameのPCM SHA256 141e367c…がWindowsと一致、chip時刻21333 |
| 論理辞書領域 | 122880→148032、差25152byte |
| 無音PCM送出 | 8192frame、AUDIO?=-1、全process約0.30秒 |
| 実行体サイズ | 全機能1,990,632、debug等除外1,497,752、float除外1,046,648、audio除外1,513,160byte |

実時間倍率（32768frame、各7process中央値）：

| 構成 | fast | reference | period1 | staggered | 8kHz volume | 8kHz bus/I/O |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 全機能 | 14.27 | 8.05 | 4.87 | 5.93 | 13.23 | 12.70 |
| debug等除外 | 11.62 | 6.80 | 3.77 | 4.69 | 11.58 | 10.44 |
| float除外 | 12.25 | 6.74 | 4.07 | 5.06 | 12.12 | 10.94 |

レモンがGhosttyで実際に聞いた（`.work/1154-mac/ym.fs`、Windows1161と同じ設定）。3声/noise/envelopeデモ約3秒、noise単独（R7=55、音量12,0,0）約1.5秒、envelope（R7=62、音量16、period3906、shape14）で音量が周期的に増減するtone約3秒が説明どおりに聞こえた。連続再生中のCtrl+Cで`CATCH= -28 handle=0`、その後約3秒の再再生、`ACCEPT`での入力。各回underrun0、fd13は不変、thread8→7。1154と親1138を完了にした。実機Atari互換は範囲外。

## Linux実聴1162の受け入れ完了（2026-11-20）

レモンがWSL上のLinux版→pacat→WSLg PulseAudio RDPSinkで、3声/noise/envelopeデモ約3秒、noise単独約1.5秒、envelope音量変化約3秒を確認。物理Ctrl+C後の停止と約3秒の再再生も確認し、CATCH=-28/handle=0、REPLAY-OK handle=0、code0、underrun0を記録。1162を完了し、Mac1154はtodo、親1138はtodo・auto80%。[環境と全結果](measurements/2026-11-20-linux-audio-listening.json)。Linux実機ALSA・実機Atari互換の確認ではない。以下のLinux未確認は履歴。

## Windows実聴1161の受け入れ完了（2026-11-20）

レモンがWindows11 Pro 10.0.26300、waveOut既定出力でYM-DEMO-SETUPの3声/noise/envelopeデモ約3秒と停止を確認した。さらにR7=55/音量12,0,0でnoiseだけ約1.5秒、R7=62/音量16,0,0・envelope period3906/shape14で音量が周期的に増減するtone約3秒を聞いて確認。連続再生を物理Ctrl+Cで止め、音の停止、CATCH=-28/handle=0、その後約3秒の再再生とREPLAY-OK handle=0を確認した。全processはcode0、記録したunderrunは0。[全コマンド・ソースと実聴記録](measurements/2026-11-20-paula-ym-windows-listening.json)。1161を完了し、Linux1162とMac1154は未完了。以下のWindows未確認や以前の進捗は履歴。実機Atari互換は対象外。

## OS別の実聴タスク（2026-11-20追記）

1138の直下にWindows実聴1161・Linux実聴1162を追加した。ともに1153へ依存し未完了・0%。examples/ym2149-play.fsのTRUEで3声・ノイズ・envelopeを実際に聞き、物理Ctrl+C後の停止と再再生、handle解放、OS/版/出力装置と結果を記録する。無音自動検査や実機Atari互換とは区別する。Mac1154も同じ1138配下で維持し、3OSの確認が揃うまで親を完了にしない。子が増えたため1138は未完了・auto40%となった。

2026-11-20、基点maincf080b4。実装/監査1152とWindows/Linux検証・測定1153を完了した。Mac受け入れ1154は1138の子で未完了に残し、1154が済むまで親1138を完了にしない。

## 既存経路で足りる部分と不足

| 経路 | 確認した既存動作 | 今回の対応 |
| --- | --- | --- |
| ST-SOUND / CHIPS ST | sound_engine.zigがPsg.init(.ym2149,2000000,rate)を選ぶ | MMLの既存経路を維持 |
| SOUND ( reg value -- ) | words_audio.zigは0..13/0..255を検査し、audio command queueへ非同期write | MSX BASIC互換の範囲を広げない |
| native Psg | 16byte registerfile/read、3tone・noise・32level envelope。内部stepの平均をPCMへ出す | 固定音量0の消音だけ修正 |
| 時刻・read・I/O・ST bus | nativeの公開語には、指定chip時刻のwrite/readやR14/15のI/O契約がない | 独立したForthモデルとステレオではないmono PCM wrapperで補う |

nativeはST選択時もMSX向け初期レジスタ（R7=B8等）を使う。Forth RESETは全reg0であり、初期状態やPCMをそのまま比較できるモデルではない。Forthは点標本、nativeは内部step平均なので、同じレジスタ列でもPCM全体の一致を約束しない。

## 資料と確認範囲

Yamahaメーカー資料の[YM2149 PDFの写し](https://map.grauw.nl/resources/sound/yamaha_ym2149.pdf)を図表を含めて確認した。SHA256は5a6be927846ef56142a17b4223a81b830d0ff75345b2eec7abe4276169dce8cb。p7/8の32段envelope、shape、DAC図、I/O latchを照合。Atari Corporationの[Engineering Hardware Specification（1986）§4.1の写し](https://www.temlib.org/AtariForumWiki/index.php/Engineering_Hardware_Specification)で2MHzを確認した。bus番地はDan Hollisの[原著Hardware Register Listing v7（1994）の公開写し](https://raw.githubusercontent.com/ggnkua/Atari_ST_Sources/master/Docs/Hardware.txt)のFF8800/FF8802を照合し、電圧/バス遅延/鏡像までメーカー保証と扱わない。参照日2026-11-20。

tone=clock/(16TP)、noise=clock/(16NP)、envelope周期=clock/(256EP)、32段、R7 bit6/7は0input/1output、R13 writeでenvelopeを再開始すること、16regを参照した。LFSRの正確なtap/seed、period0、未使用bit読戻し、subclock位相の保証は資料から確定せず、下のモデル規則として宣言する。第三者エミュレーターのコード/ROM/YM曲データを取り込んでいない。資料の画像や表そのものも配布物へ転載しない。

## native固定音量0の回帰修正

固定音量Lを32levelの2L+1へ写す既存式は、L=0でもindex1≈0.005623413を返していた。AY側のindex0への丸めと違い、STの初期音量・MML休符/停止でPSG sourceが0にならなかった。独立した小さなZig probeでexpected0/found0.0056234132を再現した。

固定0だけindex0へ写し、非0の固定1..15とenvelopeモードを維持する。これはモデル内部で音量0を停止に使う契約の修正で、実機の厳密な0レベルの電圧を新たに測った意味ではない。回帰は2model・3声・64mixer・tone/noiseの両状態・未使用上位bit、固定1/envelope1/envelope0、ST選択と停止後のsourceを検査する。

停止後も既存のcoupling filterには減衰が残る。source=0と、減衰後のPCM=0を分けて確認し、停止のためにfilter stateを消してSFX/MOD/PCMを壊す変更は行わない。追加Builtin・native公開API・画像ABIは変更しない。

## 宣言したForthモデル

2MHz master clock、内部stepは8master clocks、48kHz mono signed16LE（非負0..32767）。tone/noise/envelope period0はすべて1相当とし、siliconのenvelope0半周期という報告は再現しない。counterはperiod writeでresetせず、短くしたperiodを既に越えていれば次の該当stepで発火する。

toneはperiod内部stepごとに反転。noiseは17bit・seed1・right shift・feedbackbit0 XORbit3で、1,3,5…番の内部stepをcountする（native既存に合わせた宣言）。envelopeはnative同様の32stepと全16shapeで、RESETではstep31/attack0/holding、R13 writeでstep31、attack/hold/alternateを設定してcount0/holding解除とする。R13 writeでは共通master dividerをresetしない。実機の電源投入時やR13のsubclock pipelineの再現とは主張しない。

mixerは(tone OR disableTone)AND(noise OR disableNoise)。両方disableならDCのlevelを出すというモデルで、メーカー本文の「音を出さない」をAC tone/noiseの説明と区別する。固定0は0、固定1..15はindex2L+1、envelopeはindex0..31。level表は理想1.5dB/stepのfloor(32767*10^(-1.5*(31-i)/20))、index0だけ0と宣言する。70桁Decimalの[生成スクリプト](../scripts/ym2149-levels.py)を使い、Python doubleによる別計算で全32項目を照合する。実機のDAC測定表ではない。

3声の出力はfloor((A+B+C)/3)で0..32767に収める。点標本・無filterで、高周波には折り返し雑音がある。非線形analog混合、DC基準電圧、個体差、STE DMA、MFP/CPU/TOS、YM曲や周辺機器のエミュレーションは対象外。

## 語の契約

リポジトリのルートから読み込む。読込みだけでは再生しない。1dictionaryで1モデルを持つ。時刻は64bit master clock数。

| 語 | 契約 |
| --- | --- |
| YM-RESET ( -- ) | reg/counter/queue/時刻/端数/slow選択を初期化。I/O pinsはFF、select rawは0 |
| YM-WRITE ( byte reg tick -- ) | 指定tickまで進め、0..15のregへbyteを書く |
| YM-EVENT! ( byte reg tick -- ) | 時刻順queueへ追加。同tickは追加順。未処理1024件、満杯-528、領域回収あり |
| YM-READ ( reg tick -- byte ) | 指定tickの読戻し。R0..13はraw8bit、R14/15は下記のpin値 |
| YM-TO ( tick -- ) / YM-RUN ( clocks -- ) | 絶対/相対master時刻へ。逆行/負の相対値/加算overflowは-24 |
| YM-INPUT! / YM-INPUT-EVENT! ( byte port tick -- ) | port0/1の外部pinを指定/予定変更する。ホストI/Oではない |
| YM-PORT@ ( port -- latch drive-mask ) | 現在のCPU出力latchと0/FFの駆動mask。時間を進めない |
| YM-PIN@ ( port -- byte ) | 現在のモデル上のpin値。時間を進めない |
| YM-BUS! / YM-BUS-EVENT! ( byte address tick -- ) | FF8800select、FF8802dataを直接/予定書込み |
| YM-BUS@ ( address tick -- byte ) | FF8800から選択regを読む。FF8802 readは-21 |
| YM-SAMPLE ( -- s16 ) | 現在の3声を混合。時間を進めない |
| YM-RENDER ( address frames -- ) | 48kHz mono s16LEを生成。領域は呼出し側が確保。負のframe数は-24 |
| YM-DEMO-SETUP ( -- ) | 独自の3声/noise/envelope設定 |
| YM-STREAM ( blocks audible -- ) | ym2149-play.fsを読んだ時だけ有効。FALSEは合成後ゼロ、TRUEだけ生成音をPCMへ送る |

不正byte/reg/port/address・過去tickは、clock/queue/stateを変える前に-24。予定表の逆行も-24、容量は-528。BUSのFF8802読取りだけ-21。内部helperは公開入力の保証を持たない。レンダー中の時刻overflowは、既に進んだ部分まで巻き戻す契約ではない。

内部stepはtick8k（k>=1）で起き、tick tのstep→queue追加順→即時write/readの順。各YM-RENDERは現在のYM-CYCLEを起点に、YM-FRACTIONを持ち越して相対的に進む。RESET以降にレンダー以外で時刻を進めなければ、n番目（1起点）の標本は時刻floor(n*2000000/48000)まで進めた状態から取る。即時write/read/TO/RUNで進んだ区間のPCMは生成しない。連続音声にはEVENT!系を使い、RENDERで時間を進める。YM-SLOW=TRUEは1master clockずつ、FALSE（既定）は次tone/noise/envelope境界までまとめる。queue/標本の時刻を越えない。R0..13の未使用bitもraw8bitを保持するが、siliconの未使用bit値の保証ではない。

## I/O latchとST bus

R7 bit6/7=0ならinput、1ならoutput。input時のCPU writeもR14/15のlatchを更新し、outputへ切り替えると使う。YM-PORT@は入力中もlatchを返し、maskは0。YM-READのR14/15とYM-PIN@は、inputなら注入pin、outputならlatch AND注入pinを返す。外部low優先というデジタルモデルの宣言で、電気的なdrive強度や実機pin readbackを新たに測ったものではない。readにackやlatch更新はない。

bus selectはraw8bitを1個保持する。0..15だけ有効、上位nibble非0ならdeselectとしてreadFF/datawrite無視。dataの予定書込みは追加時でなく適用時のselectに従う。選択アドレス以外の鏡像、68000 word accessやbus waitは扱わず、対応外addressは-24。実際のフロッピー/プリンター/RS232やホスト機器を操作しない。

## 検証と測定

```powershell
python scripts/ym2149-levels.py --check
python tests/scripts/verify-ym2149.py zig-out/bin/sigma --benchmark
sigma examples/ym2149-play.fs -e "YM-DEMO-SETUP 16 FALSE YM-STREAM BYE"
```

独立したPythonは1master clockごとの別実装で、Forth基準/まとめ版と全状態・PCMを比較する。全16shape96levelの手計算列、64mixerの真理表、全32係数、両portの3072組合せ、ST bus/read/retrigger/noise位相、queue回収、原子的な不正入力を照合する。共通仕様の読み違いは残るため、実機の正解値とは扱わない。

6負荷（通常・1clock版・全period1・ずれた短period・8kHz volume・8kHz bus/I/O）で32768frameを全byte/semantic state比較してから、各7つの新processを測る。初期化/warmup/reset/初期queueは計時外、8kHz enqueue/領域回収は計時内。NTIME wall nsとuser+system CPUTIME usを保存する。native mean rendererや実装置の時間は含めない。結果と採否は末尾に記録した。

純粋なquery（YM-SAMPLE/YM-PORT@/YM-PIN@）は適用済みの状態だけを見る。同tickへ追加した未適用eventも反映させるにはYM-RUNへ0を渡すか、YM-READ/YM-BUS@を使う。RESET直後はreg13=0でも、内部envelopeはlevel31/holdingという宣言で、shape0の終了状態0とは異なる。R13を書く前にenvelopeモードへ切り替えると最大levelとなる点も、このモデルとnative Psg型の直接resetの規則であり実機保証ではない。EngineのST-SOUND初期化はさらにMSX向け初期reg（R13 writeを含む）を適用するため、その直後の内部状態とも区別する。

補助の`python tests/scripts/verify-ym2149-stream.py SIGMAのパス`は、native PCMを開かない個別processのcallback fixtureでmono1ch/2byte offset、5frame→0→残り507frameの全1024byteの一致と非ゼロ内容、timeout・close再試行・本体とcleanup例外の優先/ID保持・open/drain失敗を検証する。相対レンダー時刻、純粋queryと未適用event、BUS経由の両port読取り、RESET envelopeの宣言も手計算値で確認する。

計時7回すべてで、warmup/reset後の最後の37項目のsemantic stateもPythonと照合して保存する。補助スクリプトは作業directoryを自分で作るため、単独でも実行できる。

## Windows/Linux結果と採否（2026-11-20）

1152（実装・監査）と1153（Windows/Linux検証）を完了。Mac1154は1138の子に残し、親1138は未完了。通常・debug/graphics/extension除外・さらにfloat除外の両OS計6構成で各11検査群と補助12検査が成功した。audio/graphics/extension除外の両OSでも512frameの全PCMと状態がPythonに一致した。native Windows全体テスト成功、Linux core1126成功/10skip、host167成功/17skip、失敗0。全8実行体はfixed-zero修正後に再ビルドした。

32768frame、各7processのwall中央値による実時間倍率（高いほど余裕がある）。CPUはAMD Ryzen 7 7700、Zig 0.17.1、ReleaseFast/baseline/strip。OS別に順番に測定し、周波数固定や他アプリの停止はしていない。

| 負荷 | Windows | Linux |
|---|---:|---:|
| fast | 9.532 | 11.431 |
| reference | 5.479 | 6.584 |
| fast_period1 | 3.212 | 3.834 |
| fast_staggered | 3.952 | 4.797 |
| fast_8khz_volume | 9.773 | 11.353 |
| fast_8khz_bus_io | 8.917 | 10.289 |

辞書HEREは122880→148032、増加25152byte（RSSではない）。通常実行体はWindows 2145792byte、Linux 2356352byte。PCM1128時点の保存済み通常実行体比はそれぞれ+512/+48byteで、Forthソースの大きさとは別である。本体にはfixed volume 0のmute修正のみ採用し、レジスタ/I/O/時刻モデルはForthで維持する。Builtin/ABIは追加しない。フィルターの停止後tailは保持する。

[全生データ・ソース指紋/本文・実行体サイズ](measurements/2026-11-20-ym2149.json)、[レビュー評価と採否](reviews/1138-review-response.md)。最終ClaudeレビューはHigh/Mediumなし。モデルの速度はST全体・native PSGの速度を示さず、独立比較も実機互換や実聴の証明ではない。Mac1154では今回のnative fixed-zero回帰も新しい実行体で確認し、通常/除外構成・サイズ/速度・生成音の実聴と中断/資源回収を記録する。
