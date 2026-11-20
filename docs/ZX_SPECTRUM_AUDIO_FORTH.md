# ZX Spectrum48K/128KのForth音源（1169）

2026-11-20、レモンが48K beeperと128K beeper+AYを対象とすることを承認した。1169は音源側の仕様/実装/独立検証。Windows1170/Linux1171/Mac1172の測定・実聴は別に残す。CPU/ROM/画面/keyboard/テープ/MIDIの実装ではない。

## 最新の受け入れ状況

Windows1170は実聴・物理Ctrl+C後の停止/再再生まで完了。Linux1171は再試験でCATCH=-28/handle0、replay underrun0/DEPTH0/code0となり、レモンが実聴確認し1171も完了。初回のSIGINT exit=-2は失敗として別記録に保持し、プログラム注入の診断と物理再試験を区別した。Mac1172は未確認で、親1168は未完了を維持する。

Linuxの再試験だけ非可聴B/Cとnoiseの周期を延ばした。全PCM/状態を独立モデルと照合し、旧試験の可聴PCMとも一致することを確認した。捕捉は待機scope内だけで、描画中等のCtrl+Cをcatchする変更は加えていない。LinuxのSigma/pacatは残っておらず、保持用owned sleep1800もcmdline確認後に停止した。

本書は現在の仕様と結果を記載し、各試行の履歴は[全結果](measurements/2026-11-20-zx-spectrum-os-acceptance.json)に保存する。

## 原典とモデルの宣言

[Sinclair48K service manualのOCR版](https://k1.spdns.de/Vintage/Sinclair/82/Sinclair%20ZX%20Spectrum/Repair/ZX%20Spectrum%20Service%20Manual%20%28OCRed%29.pdf)、[Sinclair128 service manualのscan](https://www.rwapsoftware.co.uk/DOC/spectrum128servicemanual.pdf)、[GI AY datasheet](https://hansotten.file-hunter.com/uploads/files/AY38910.pdf)を参照する。いずれも第三者掲載版で、正規再配布や完全性の保証ではない。本文/ROM/他実装をコピーしない。

CPU T-stateを時刻単位とし、48K=3500000Hz、128K=3546895Hzの公称値を宣言する。128KのAY clockはCPU/2=1773447.5Hzという有理比を保持し、整数Hzへ丸めない。内部PSG stepはRESET後のCPU tick16k（k>=1）で発生する。tone toggleはTP step、noise更新は2NP step、16段envelopeの1levelは2EP step。envelope内部は既存YMで検証済みの32状態を使い、出力はlevel>>1。全周期はAY clock/(256EP)。GI資料の分周説明は用語が紛らわしいため、図の16段cycleとこの実行規則を明示して検査する。noiseのtap0 xor3/seed1、period0→1、R13の再始動と共有divider位相は既存nativeから引いたモデルの宣言で、siliconの新しい測定ではない。

音量は独自理想3dB表16個（0=mute、1..15=floor(32767*10^(3*(L-15)/20))）。native AYの測定係数、YMの32段DAC、実基板の非線形混合/analog filterと一致するとは主張しない。48KはULA D4が1なら4096、0なら0。128Kは同じbeeperにfloor((AY A+B+C)/6)を加える宣言で、最大20479。MIC D3/border D0..2はraw ULA latchに保持するが音/画面/録音機器へ接続しない。点標本、48kHz s16LE mono、alias/DC/clickは残る。

AYはR0..14を扱い、未使用bitはmaskする。R14は仮想portA latchと外部pin byteを分け、R7 bit6=0ならinput pins、1ならlatch AND pinsを読む（low優先はモデル宣言）。R15/portBは未モデル化で、direct APIは-21、bus readFF/write無視とする。これは8912内部registerの有無を実測した主張ではない。RS232/MIDIの実機I/Oは操作しない。

## OUT/INと時刻

OUTは全16bit portを受ける。A0=0ならULA latchへ書く。128Kでは同時にA15=1/A1=0のAY復号も行い、A14=1はselect（正規FFFD）、A14=0はdata（BFFD）。両方に一致する偶数aliasではULAとAY双方へ同じbyteが渡る。select raw byte0..14のみ有効、15/上位nibble非0は未対応としてdata無視/readFF。unknown OUTは音源に作用せず時刻だけ進める。

INは128KのA15=1/A14=1/A1=0/A0=1のAY readだけを扱う。ULA keyboard/EAR read、BFFD read、偶数alias上のbus競合は-21として、未対応をFFの実機仕様と捏造しない。不正byte/port/model/reg、過去/逆順tickは-24、queue満杯は-528。INの未対応と入力の不正は時刻/queue/stateを変更する前に判定する。

同tickはPSG step→その時点で登録済みの予定追加順→即時OUT/direct write/IN→標本。即時操作の後で同tick予定を追加しても過去に遡って並べ替えず、次のTO/RUN時に適用する。queueは1024件の(value,target,tick)3cell、direct reg0..14/virtual input15/port OUT16+portを表し、port dataの予定は適用時のselectを使う。読み取りはtickまで進める。SAMPLEは適用済み状態を見る純粋queryで、未適用の同tick予定をflushするにはRUN0/IN/AY@を使う。

RESETはmodel0=48K/1=128Kを先に検査してから全状態を初期化する。modeは途中変更せずRESETだけ。RESETはZX-SLOWもFALSEへ戻す。R13未書込みのenvelopeは最大level15で保持し、amplitude bit4を有効にしてもそのまま。48KではAYを進めず、direct AY/PIN APIは-21。48K INは未対応、128K AYへのOUT aliasも48KではULAに一致する部分だけが作用する。

RENDERは現在CPU tickからfractionを持ち越して進み、その時刻の状態を出す。直接TO/OUT/INで飛ばした区間のPCMは作らない。fractionはRESETだけで0に戻し、TO/OUT/INでは維持する。clock増加の除算/剰余は分けて64bit overflowを避ける。RENDERとSTREAMは全出力期間がMAXを越えないか除算で先に検査し、時刻errorでは状態/出力を変えない。不正な出力memoryの-9だけは途中まで進んだ状態を巻き戻さない。callerがframes*2byteの有効bufferを用意する。

## 公開語

| 語 | stack/用途 |
| --- | --- |
| ZX-RESET | ( model -- ) 0=48K/1=128K。clock/counters/queue/latchを初期化 |
| ZX-OUT / ZX-OUT-EVENT! | ( byte port tick -- ) CPU I/O write即時/予定 |
| ZX-IN | ( port tick -- byte ) 対応AY read。tickまで進める |
| ZX-AY! / ZX-AY-EVENT! / ZX-AY@ | ( byte reg tick -- ) / 同左 / ( reg tick -- byte ) direct sound/virtualA |
| ZX-INPUT! / ZX-INPUT-EVENT! | ( byte tick -- ) 仮想portA外部pins |
| ZX-TO / ZX-RUN | ( tick -- ) / ( ticks -- ) 絶対/相対の単調時刻 |
| ZX-SAMPLE / ZX-RENDER | ( -- s16 ) / ( addr frames -- ) 1本へ混合して返す |
| ZX-SLOW | variable。TRUEは1CPU tick基準、FALSEは次PSG境界までまとめる |
| ZX-DEMO-SETUP / ZX-BEEPER-SETUP | ( -- ) 独自128K AY+beeper / 48K beeper予定 |
| ZX-STREAM | ( blocks audible -- ) play.fsだけ。FALSEは合成後ゼロ、TRUEのみ生成音 |

CPU adapterはT-stateとI/Oアクセス時点を与える。ULAのcontention/clock停止、7FFD memory paging、CPU opcode timing、full bus/keyboard/floating busや+2/+3/clone系はこの音源宣言の完了から推論しない。

## 検証方針

全65536 portのOUT復号と対応IN集合を独立bit条件で照合、全16envelopeと16段、全音量/mixer、仮想portA、period0/短縮/R13、同tickとselect/data適用順、入力の原子性、queue回収、48/128Kのclock/fractionを手計算と独立Pythonで検証する。PythonはAY16levelの別表現を使い、Forthの32状態/step経路との共通実装への依存を減らす。slow/fast/分割と全PCM/終了状態を照合する。検査は非ゼロRAMと無音実PCMを分け、速度測定はレモンの開始確認後だけ行う。

入力errorの優先順位はAPIの検査順による。OUTはport→byte/target→tick→model、direct AYはreg範囲/未対応R15→byte/target→tick→model、INはport→tick→対応集合。queueはこの共通検査後、満杯→末尾時刻順の順。複数不正がある場合も、この順に最初のerrorを返す。


## 原典の確認箇所

128K manualのPDF20頁（印刷1.17）はFFFD/BFFDとregister表、PDF21頁（印刷1.18）5.6.3はA15=1/A1=0とA14による操作の復号、5.7.2はR7 D6の入力0/出力1を記述する。48K OCR版はport254/D4と偶数portのULA選択を確認した。GI datasheetはPDF1頁の8912 portA、2頁のregister/address条件、4–5頁の分周・envelope/16段の図を確認した。clock公称値と共有divider・noise位相・理想DAC・mix・未対応R15の扱いは上記のモデル宣言として区別する。原典PDFの指紋は結果JSONに保存する。

## 検証結果（2026-11-20）

Windows/Linuxそれぞれ通常・no-debug・no-float・no-audioの8構成で、全65536 OUT port（48K/128K各々）とIN集合、15register×256byte、16shape×96levelの手書き期待列、64mixer条件、4096frameの全PCM/39状態・queueの独立CPU-tick oracle/slow/fast/分割照合が成功した。周期0/短縮・上位byte・R13/共有divider、同tick順、入力error時のstate/queue全体の原子性、1024件queue回収、MAX直前の成功/失敗境界も確認。不正bufferの-9では時刻/fractionが進む契約も検査した。[1169の全結果/ソース指紋](measurements/2026-11-20-zx-spectrum-audio.json)、[実装レビュー評価](reviews/1169-review-response.md)を参照。

初回送出の修正後、音声有効6構成で各19RAM callback検査が成功した。初回/継続のpartial/full/timeout/cleanup、短い/0block、時刻上限、4096frame境界を跨ぐ48K/128Kの全9216byteとclock/fractionの一括RENDER照合を含む。実PCMの無音送出と生成音の実聴は下記OS受け入れで区別する。

## サイズ・速度（1170/1171）

通常binaryはWindows2145792byte、Linux2356352byte。native332ソースと8binaryの現物hashが既検証ビルド記録に一致するため再利用した。native binary増加0。音源coreのみのlogical辞書HEREは122880→148040（増加25160byte）で、RSSではない。再生wrapperには別途8192byteの初回bufferがある。8構成のサイズ/hashとbuild来歴は[全結果](measurements/2026-11-20-zx-spectrum-os-acceptance.json)へ保存した。

レモンの開始確認へのＯＫ後、通常構成をWindows→WSL/Linuxの順に測定。各負荷32768frame×7回の別process、順序回転あり、wall中央値。warmup/RESET/A5・前状態確認は区間外で、毎回全PCM/39状態/queue2項目を区間外で照合した。外れ値は除外せず全7値を保存し、12組すべての中央値と実時間比を再計算した。CPU時間は参考値で粒度未校正。NTIMEは時刻補正の影響を受け得て、wall区間にCPUTIME2回の呼出しも含む。

| 負荷 | Windows ns/frame | Windows 実時間比 | Linux ns/frame | Linux 実時間比 |
| --- | ---: | ---: | ---: | ---: |
| 48k_beeper | 264.36 | 78.81倍 | 227.46 | 91.59倍 |
| 128k_tone | 5070.49 | 4.11倍 | 4253.29 | 4.90倍 |
| 128k_mix | 2085.89 | 9.99倍 | 1761.30 | 11.83倍 |
| 128k_period_zero | 5803.28 | 3.59倍 | 5033.23 | 4.14倍 |
| 128k_changes384 | 2185.60 | 9.53倍 | 1860.23 | 11.20倍 |
| 128k_8khz_bus | 5274.20 | 3.95倍 | 4625.81 | 4.50倍 |

計時は純粋合成coreの負荷で、再生wrapper/装置/CPU/ROM全体を含まない。denseは8kHzで各2件のOUTを追加し、計算/queue/compaction判定を含むが未適用データのMOVEは生じない。slow経路は未測定。LinuxはWSL2で、物理Linux/ALSA直結/Macへ外挿しない。

## 初期供給不足の修正

最初のWindows48K実聴でunderrun2、無音でも再現した。Windowsは起動時8×480frameを連続renderする一方、ZX側は初回512frameだけを公開していた。wrapperは初回だけmin(blocks,8)×512frameを専用8192byte bufferで合成し、一括PCM-WRITEで公開するよう修正した。OPEN後、最初のデータまでの無音はtransportのstarted前なのでunderrunに数えない。以降は512frame。途中error/停止では合成済み未送出分の時刻も巻き戻さない。

初回1block/8blockだけが異なる比較で、対照はunderrun1/1/1、修正は48K0/0/0・128K0/0/0。修正版の実聴でもunderrun0だった。今回再現した初期供給不足の対処であり、任意host負荷の無欠落保証ではない。[修正レビュー](reviews/1170-stream-prime-claude-review.md)はHigh/Mediumなし。

## 実聴と物理Ctrl+C

| OS | 確認した生成音/動作 | 結果 |
| --- | --- | --- |
| Windows | 48Kブザー約1秒→無音、128K AY高音→低音→低音+断続beeper、物理Ctrl+C停止→低音約3秒再生 | レモンが全件確認。修正後underrun0/handle0、CATCH=-28、replay underrun0/DEPTH0/code0。1170完了 |
| Linux WSL2 | 同じ48K/128K実聴と物理Ctrl+C停止→低音約3秒再生 | レモンが全件確認。通常再生underrun0/handle0。物理試行2回のうち、試験設定を変えた2回目でCATCH=-28/handle0、replay underrun0/DEPTH0/code0。1171完了 |
| Mac | Mac実機の構成/サイズ/速度/実聴/割込み | 未確認。1172と親1168は未完了 |

Linuxの初回はREADY後SIGINT exit=-2で終了し、CATCH/cleanup/再再生は確認できなかった。正確な命令位置は未特定。資源はプロセス終了でOSへ戻るが、その回に明示的cleanupが行われたとは主張しない。失敗source/JSONを保存した。

別の無音診断では `/proc/PID/status` のSigCgtを確認し、SIGSTOPで状態を固定後SIGINT/SIGCONTを注入した。捕捉なしではexit=-2、捕捉ありではCATCH/cleanup/replayが正常。このプログラム注入は物理受け入れの代用にしていない。

Linuxの物理2回目だけ、試験用に非可聴toneB/Cのperiodを4095、noiseを31へ変更した。R7=62なのでtoneAの音は変わらない。高/低各49152frameの全PCM/39状態を独立Pythonと照合し、Windows128K準備時の高/低音（初回interruptと同じtoneA-only設定）のPCMともhash一致を確認。これは試験負荷の変更で、元の重い設定での物理成功を主張しない。NativeScope内だけSIGINTを捕捉する契約はそのままで、押すタイミングに依存し、描画/WRITE等の外ではプロセス終了し得る。

中断streamのunderrunはclose後に照会できず未確認。再生後はLinuxのSigma/pacatが残っていないことを確認し、接続保持用owned sleep1800もcmdline確認後に停止した。Windowsタイトル設定で出たZXエラーは無音のlabel代入で引用符問題を再現し、EncodedCommandで修正・検証済み。音源テストはそのエラー後も実行され正常だった。

## 採否と残る作業

測定した宣言音源はForthを維持する。最小中央値でもWindows3.59倍/Linux4.14倍で、音源単体の測定からnative移行を要する根拠は得られなかった。任意register列の最悪時間、機種全体、実装置での無欠落、Mac性能を保証する判断ではない。

1169とWindows1170は完了。Linux1171も実聴・物理再試験の確認と最終レビューが揃い完了。Mac1172が完了するまで親1168は未完了とする。[レビュー対応と評価](reviews/1170-1171-review-response.md)に段階ごとの原文と判断を保存する。コミット/プッシュは今回行っていない。

最終追確認レビューは[High/Mediumなし](reviews/1170-1171-final-followup-claude-review.md)。親1168はMac1172待ちで未完了・auto75%。
