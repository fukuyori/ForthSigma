# C64 SID のForthモデル（1136、1141/1142）

2026-11-21：モデルと補助の表は`include/`へ移し、`*-DEMO-SETUP`などデモ用の語は`examples/<名前>-demo.fs`へ分けた（1185）。`*-play.fs`はデモのファイルを読む。以下の記録にある`examples/`のモデルのパスは、移す前のものである。

## Linux実聴1158の受け入れ完了（2026-11-20）

レモンがWSL上のLinux版→pacat→WSLg PulseAudio RDPSinkで、3声デモ約4秒と停止、物理Ctrl+C後の停止と約4秒の再再生を確認。CATCH=-28/handle=0、REPLAY-OK handle=0、code0、underrun0を記録し、1158と親1136を完了。[環境と全結果](measurements/2026-11-20-linux-audio-listening.json)。Linux実機ALSA・実機SID/ROM互換の確認ではない。以下のLinux未確認は履歴。

## Windows実聴1157の受け入れ完了（2026-11-20）

レモンがWindows11 Pro 10.0.26300、waveOut既定出力でSI-DEMO-SETUPの3声デモ約4秒と終了後の停止を確認した。続いて前面PowerShellで連続再生中に物理Ctrl+Cを押し、音の停止、CATCH=-28/handle=0、その後約4秒の再再生とREPLAY-OK handle=0を確認。全processはcode0、各回underrun0。[全ソース・コマンドと実聴記録](measurements/2026-11-20-nes-sid-windows-listening.json)。1157を完了し、Linux1158は未完了に残す。以下のWindows未確認はこの受け入れ前の履歴。6581/8580実機・ROM互換は対象外。

現行タスク状態（2026-11-20更新）：Mac受け入れ1143は合格し、親1136も完了。結果は下のMac実機受け入れ節を参照。Mac確認前の未完了・進捗表示は当時の記録として保持する。

2026-11-20、基点main8eff166。追加するのは独自に書いた決定的3声レジスタモデルと、標本領域の整数フィルター近似である。6581/8580のアナログ特性やROM互換を再現したものではない。既存C64-SOUNDやBuiltinは変更しない。実行結果と測定は下記に記録した。

## 資料と採用した範囲

参照日2026-11-20。[MOS6581データシートの写し](https://myoldcomputer.nl/Files/mos_6581_sid.pdf)でレジスタ配置、FREQ/2^24、12bit PW、波形・GATE/TEST/SYNC/RING、ADSRの公称時間とフィルター配線を確認した。データシートは内部カウンターや個体差まで規定していない。

| 根拠 | このモデルの扱い |
| --- | --- |
| データシートのレジスタと周波数式 | 24bit位相、16bit周波数、12bit幅、3声と共通フィルター経路 |
| [Asger Alstrup Nielsen の1995年の実測報告](https://groups.google.com/g/comp.sys.cbm/c/8c3qOxM6e_8) | FREQ=$8000で32clockごとのノイズ更新という報告からbit19立上りを採用。左シフト23bit、feedback22 XOR17、出力bits22,20,16,13,11,7,4,2、seed7FFFF8 |
| [著者公開のSID技術記事](https://github.com/ImreOlajos/SID-Article/blob/main/SID-Article.md) | ADSRの周期9,32,63,95,149,220,267,313,392,977,1954,3126,3907,11720,19532,31251と指数分周をモデルの宣言値として採用。メーカーの保証値とは扱わない |
| [Oxyronのレジスタ資料](https://www.oxyron.de/html/registers_sid.html) | ノイズ出力bits20,18,14,11,9,5,2,0という別表記がある。今回は1995年の直接測定報告の側を選び、相違を隠さない |
| 今回の独自の取り決め | PAL整数985248Hz、48kHz点標本、単一波形、後述の同期順序・パルス極性・即時TEST・フィルター式。実機測定ではない |

他エミュレーターのGPLソースや曲・ROMを取り込んでいない。第三者資料から参照した数学的事実と、独自に書いた実装を分ける。既存MML用sound_c64.zigの動作を変更したものではない。

## 公開するライブラリ語

リポジトリのルートから読み込む。読込みだけでは音を出さない。64bitセルを使用する。

| 語 | 契約 |
| --- | --- |
| SI-RESET ( -- ) | 時刻・位相・ADSR・フィルター・予定表・統計を初期化。LFSRは7FFFF8 |
| SI-WRITE ( value address cycle -- ) | byte0..255、D400..D418へ時刻指定で書く。現在より過去は-24。同時刻の予定書込みを先に処理 |
| SI-EVENT! ( value address cycle -- ) | 時刻順で予定表に追加。同時刻は追加順。未処理1024件、満杯-528。処理済み領域を回収 |
| SI-TO ( cycle -- ) / SI-RUN ( clocks -- ) | 指定時刻／相対clock数まで進める。負の相対値・逆行・符号付き64bit時刻の加算overflowは-24 |
| SI-READ ( address cycle -- byte ) | D41B OSC3は波形上位8bit、D41C ENV3はADSR値。POT/書込み専用レジスタのreadは-21、範囲外は-24 |
| SI-SAMPLE ( -- s16 ) | 現在の声を混合し、フィルターを1標本分進める。純粋な参照操作ではない |
| SI-RENDER ( address frames -- ) | 48kHz mono signed16 little-endianを生成。端数clockを保持。負のframesは-24。出力領域は呼出し側が確保 |
| SI-DEMO-SETUP ( -- ) | 独自の3声設定。既存の曲は使用しない |
| SI-STREAM ( blocks audible -- ) | sid-play.fsを読んだ時だけ使用可。512frame単位でPCMに送る。FALSEは合成後にゼロ化、TRUEは生成音を送る |

入力値・番地・合成波形・時刻・予定表の容量/順序は、状態や時刻を変える前に検査する。D419以降へのwriteは-24。複数波形（$51/$61等）は受付時に-21。波形なしは0。読み取り専用レジスタのbus挙動を模倣しない。レンダー途中の時刻overflowは、既に生成した標本や進んだ状態を巻き戻す契約ではない。

```powershell
sigma examples/sid-play.fs -e "SI-DEMO-SETUP 16 FALSE SI-STREAM BYE"
python scripts/sid-filter-coeffs.py --check
python tests/scripts/verify-sid.py zig-out/bin/sigma --benchmark
```

SI-TO/RUN/READはclock状態だけを進め、フィルターを進めない。連続音声が必要なら、その期間をSI-RENDERで生成する。SI-SLOWをTRUEにすると1clock版、FALSE（既定）は次のADSR/ノイズ/MSB境界までまとめる版になる。両版はヘルパーを共有するため、Pythonの独立した1clock実装と手計算の境界を別に照合する。

## 1clockの順序と波形

時刻Nの書込みはNまで進めた後、N+1より前に反映する。全声の位相を加算し、同期前のMSB/bit19立上りを求める。bit19の立上りでLFSRを更新してから、前の声（1←3、2←1、3←2）のMSB立上りに従ってSYNC先の位相を0にする。全声の立上りは同期前の同じ状態から決める。ノイズ更新は同じclockのSYNCで消さない。その後ADSRを進め、同期後の位相から波形とRINGのXORを求める。

TESTは直ちに位相0とseedへ戻し、TEST解除でもseedを設定する。実機の数千clockかかるTESTのノイズ変化や立上り遅延は含めない。パルスはPW=0で4095、PW=4095で0、それ以外は位相上位12bit>=PWで4095とする。設計レビュー案の「位相<PWでhigh」とは逆で、周波数比較器の極性をこのモデルの宣言値として固定した。公称デューティ式から実機の極性まで確定したとは扱わない。TEST中はpulseだけ4095、triangle/saw/noiseは0とする。seedからノイズ値を返す実装ではない。

ADSRは15bit rate counterをGATEでresetしない。新しい周期を越えたcounterはwrapを待つ。指数分周はレベルの関数でなく状態として保持し、255/93/54/26/14/6/0を通ると1/2/4/8/16/30/1へ切り替える。attack途中150でreleaseへ移ると分周2を保持する。sustainを現在値より上げても値を跳ね上げない。実機の内部pipeline・同clockの書込み競合までは再現しない。

## 独自フィルターと整数演算

Q16のstate-variable近似を1標本に2回、同じ入力で進める。alpha[FC]=floor(2*sin(pi*(30+5.8*FC)/96000)*65536)、damping=floor((1414-80*res)*65536/1000)。FC0..2047の表は70桁Decimalの独自生成スクリプトで作り、Pythonのdouble sinによる別計算と全項目を照合する。float語群なしで読み込める。

各substepはhp=input*65536-lp-floor(damping*bp/65536)、bp=clamp(bp+floor(alpha*hp/65536))、lp=clamp(lp+floor(alpha*bp/65536))。bp/lpはQ16で±8589934592に制限し、SI-FILTER-LIMITSへ加算する。選択LP/BP/HPを加算後floor(/65536)。符号付き除算のfloorをこの処理系で検証する。6581/8580の測定係数ではない。

声はfloor((wave12-2048)*envelope/255)で正規化する。D417の声別bitでフィルターへ送り、EXTは0入力。mode=0のrouted出力は0。3OFFは直接経路の声3だけを消し、フィルター側は残す。混合後floor((direct+filtered)*VOL/3)をs16へ制限しSI-CLIPSへ加算する。D418の電圧オフセット/デジ再生は含めず、無選択時のコンデンサー減衰、合成波形の結合、ノイズlockup、bus decay、OSC/ENV read pipeline、sync suppression、帯域制限も含めない。NTSCや実機の個体差、ROM互換・実聴は未確認。

## 検証と測定

実行結果・負荷・採否は以下に記録する。既存PCMのMac1130は完了済みだが、このSID例のMac実行は未確認として残す（追記：[1143](#mac実機受け入れ1143)で確認）。Windows自動試験は生成後にゼロをPCMへ送るため、実聴確認ではない。

## 実行結果と採否（2026-11-20）

Windows GNUとWSL Linux muslで通常版、debug/graphics/extension除外版、さらにfloatを除いた版の6構成で各12検査群が成功した。12検査群は全16attack周期48点、位相/ADSR境界14点、手計算したノイズ/パルス/リング/配線/正負フィルター値、全2048係数と64インパルス、不正入力27件、時刻順/容量回収、8192frameの8kHz連続書込みを含む。3声の2048frame固定PCMのSHA256はad597ded6f6f2c5e26d3e167ed23be3881aa25b55fef9148a3c0e842553990c7で、基準版・まとめ版・分割描画・Pythonで全byteが一致する。実機の正解値ではない。

32768frame（約0.683秒、672595clock）の5負荷を使う。通常は3声と128件の時刻指定write、referenceは同じ負荷の1clock版。重い混在条件は3声FREQ=FFFF/7FFF/5555、noise声のSYNCは無効、AD=0/SR=F0、PW=2048、SYNC/RING/noise、FC2047/res15/LP+BP+HP/VOL15と128件のGATE切替である。別に3声すべてFREQ=FFFF/SYNC/noiseの条件を設ける。混在と8kHzではRING元MSBのhighとpulseのhigh/lowがすべて出現することを数える。これは音量0の期間も含む位相の検査で、実聴の保証ではない。SYNCは主に2声目で働く。全PCMと終了ADSR/filter状態のForthとの比較は、5負荷すべてで行う。8kHz条件はsustain255を保ち、5461件の周波数writeを描画中に補充し、そのenqueueと予定表回収を時間へ含める。未来のGATEを先に並べると時刻順を壊すため、8kHz条件のcycle0以降はstreaming writeだけを使う。

各負荷は測定とは別に32768frameすべてをForthで生成し、Pythonと全byteを比較してから、新しいprocess7回を測る。各processで同じ負荷をwarm-upし、resetとcycle0/初期予定表を準備してからNTIMEとCPUTIME（user+system）を計測する。Pythonと各回の最終buffer和・clock・clipping数も照合する。全体起動時間の無音PCM確認は別欄で、合成だけの時間と混ぜない。

| 負荷 | Windows実時間倍率 | Linux実時間倍率 | clipping/frame |
| --- | --- | --- | --- |
| 通常まとめ版 | 2.525 | 2.878 | 0/32768 |
| 通常1clock版 | 0.690 | 0.813 | 0/32768 |
| 最大フィルター/同期/混在 | 1.031 | 1.173 | 2594/32768 |
| 最大フィルター/3声noise | 1.131 | 1.291 | 8525/32768 |
| sustain保持/8kHz書込み | 1.052 | 1.183 | 5737/32768 |

倍率は音声時間÷wall中央値。最も重い条件はWindows実時間倍率が小さく、C64全体を動かす余裕は立証していない。最大cutoff/resonanceかつ全mode/VOL15の人工的な負荷はclippingが多いため、出力品質を保証する設定例ではない。filter stateの制限回数は全5負荷で0。生の7回のwall/CPU時間、最終ADSR/フィルター、全出力照合のコマンド・SHA、ソース本文とLF指紋は[測定JSON](measurements/2026-11-20-sid.json)へ保存した。AMD Ryzen7 7700の同じhostでWindows/Linuxを順番に測り、他アプリ停止や固定clockは行っていない。

今回の採否は、この宣言した音源単独の試作をForthで維持し、Builtinを追加しない。重い条件の余裕は小さく、CPU/VIC/バス/装置を含むC64全体へ外挿しない。実機の忠実なフィルターが必要な場合は別モデルと測定が必要で、全機種の最終判断1140を完了した意味でもない。

本体のZigソースは変更せず、PCM1128のソース指紋を全項目照合した既存ReleaseFast/cpu=baseline/strip=true実行体を使った。通常版の実行ファイルのサイズ増加は0。Windows通常版でHEREの差は41688byte（読込み前122880、後164568）。これは論理辞書領域であり、RSSではない。主な固定表は2048cellの係数と3072cellの予定表である。audio/graphics/extension=falseでも純粋な合成例をWindows/Linuxで実行でき、512frame後は10509clock・stack深さ0だった。

Windows通常版はAUDIO?=-1、WSL LinuxはAUDIO?=0の無音consumerであり、Linux実装置の検証ではない。自動PCM試験は8192frameを合成後ゼロ化してopen/write/wait/drain/closeし、時刻overflowで中断した場合もhandleを解放した。生成音の実聴、SID例のMac実行、実機/ROMとの一致は未確認（追記：Mac実行と実聴は1143で確認、Windows/Linuxの実聴はtque 1157（Windows）・1158（Linux））。既存PCMのMac1130完了とは別に残す。親999の他機種と対象照合も継続する。

[設計・実装・追加・最終レビューと採否](reviews/1136-review-response.md)を保存した。実装Medium3件と追加N1を解決し、最終ClaudeレビューはHigh/Mediumなし。レビューは読取りだけで、ここに記録した実行結果はロクによる。

## Mac実機受け入れ（1143）

2026-11-20、main `1f1a67c`、macOS 27.2.1 / Apple M5 / Zig 0.17.1。Zigソースは9d1c528から変更がなく、1130で作ったReleaseFast / cpu=baseline / strip=trueの実行体（全機能、debug/graphics/extension除外、audio/graphics/extension除外）を使った。作業ファイルは`.work/1144-mac/`・`.work/1143-mac/`（git管理外）。 float除外版（float/debug/graphics/extension=false、audio=true）は同じ設定で新たにビルドした。

| 対象 | 結果 |
| --- | --- |
| verify-sid.py --benchmark（全機能・debug等除外・float除外） | 各12検査群成功、全検査の結果がWindowsの記録と一致。3声2048frame固定PCM ad597ded…990c7、係数2048項目09a84573… |
| audio/graphics/extension除外 | `10509 0`、status0 |
| 論理辞書領域 | 122880→164568、差41688byte |
| 無音PCM送出 | 8192frame、AUDIO?=-1、clipping0、全process約0.284秒 |
| 実行体サイズ | 全機能1,990,632、debug等除外1,497,752、float除外1,046,648byte |

合成負荷（32768frame、各7process中央値。音声時間÷wall）：

| 構成 | 通常まとめ | 1clock | 最大filter/同期/混在 | 3声noise | 8kHz書込み |
| --- | --- | --- | --- | --- | --- |
| 全機能 | 3.58倍 | 1.02倍 | 1.43倍 | 1.63倍 | 1.46倍 |
| debug等除外 | 3.19倍 | 0.86倍 | 1.31倍 | 1.41倍 | 1.34倍 |
| float除外 | 3.20倍 | 0.84倍 | 1.32倍 | 1.42倍 | 1.33倍 |

clipping数（0/2594/8525/5737）とfilter制限0はWindows/Linuxと同じ。重い条件の余裕が小さいという判断は変わらない。

レモンがGhosttyで実際に聞いた（`.work/1144-mac/sid.fs`）。3声デモ約4秒、連続再生中のCtrl+Cで`CATCH= -28 handle=0`、その後の再再生、`ACCEPT`での入力、status0。underrun0、fd13は不変、thread8→7。画面出力に加え、聞こえ方の相違の報告はなかった。

Ctrl+Cの扱い：PS-SENDはPCM-WAITと合成を交互に行う。Macで300blockを測ると3.18秒中1.02秒が合成で、待機中に届いたCtrl+Cは`-28`で捕捉されhandleを解放する。合成中に届いた場合は[既存の規則](USER_MANUAL.ja.md)どおり確認点のない計算としてOSが終了させる（SIGINTを無作為な時刻に20回送り、13回-28・7回シグナル終了）。例の不具合ではなく、現行の中断規則による。全機能版（extensionとdebugを含む）では、合成の呼出しをEXEC-LIMITED（予算0）で包めば合成中のCtrl+Cも-28で捕捉できる。ただし実行制御の記録どおり包んだ中の計算は約2.8倍遅くなり、Macでの試算ではSIDデモが約1.3倍、Windowsでは約0.9倍と実時間を下回るため、例には組み込まない（2026-11-20に試作し、全機能版で20回中20回-28を確認した後に取り消した）。

Windows/Linuxでの生成波形の実聴は未確認（tque 1157（Windows）・1158（Linux））。6581/8580実機・ROM互換は範囲外のまま。
