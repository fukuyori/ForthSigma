# CHIP-8 / SUPER-CHIP / XO-CHIPの音源モデル（1164）

2026-11-21：モデルと補助の表は`include/`へ移し、`*-DEMO-SETUP`などデモ用の語は`examples/<名前>-demo.fs`へ分けた（1185）。`*-play.fs`はデモのファイルを読む。以下の記録にある`examples/`のモデルのパスは、移す前のものである。

2026-11-21：語の名前と形をそろえた（1187）。どのモデルも`*-RESET ( -- )` `*-WRITE` `*-EVENT! ( value target tick -- )` `*-READ ( target tick -- value )` `*-RUN ( clocks -- )` `*-RENDER ( addr frames -- )`を持つ。共通の語の検査は`tests/scripts/verify-model-common-words.py`。

## Mac受け入れ1167の完了（2026-11-20）

main `c205820`、macOS 27.2.1 / Apple M5 / Zig 0.17.1。Zigソースは53ebe81から変更がなく、1154で作ったReleaseFast / cpu=baseline / strip=trueの4構成（全機能、debug/graphics/extension除外、float/debug/graphics/extension除外、audio/graphics/extension除外）を使った。作業ファイルは`.work/1167-1172-mac/`（git管理外）。

| 対象 | 結果 |
| --- | --- |
| chip8-pitches.py --check | 256項目再現（既定357913） |
| verify-chip8-audio.py（4構成） | 各13検査群成功、全検査の結果がWindowsの記録と一致 |
| verify-chip8-audio-stream.py（音声有効3構成） | 各11検査成功、Windowsと一致 |
| 論理辞書領域 | 122880→166000、差43120byte |

レモンの了承後に通常構成で測った実時間比（6負荷32768frame、各7fresh processのwall中央値、全PCM/状態をPythonと照合）：

| 負荷 | Mac | Windows | Linux/WSL |
| --- | ---: | ---: | ---: |
| classic | 96.46 | 65.03 | 76.92 |
| xo_default | 90.36 | 63.72 | 74.84 |
| xo_pitch255 | 95.56 | 64.84 | 74.42 |
| classic_60hz_gates | 95.73 | 66.96 | 77.30 |
| xo_changes128 | 120.34 | 83.21 | 91.90 |
| xo_8khz_pattern_pitch | 50.59 | 33.78 | 38.23 |

レモンがGhosttyで実際に聞いた（`.work/1167-1172-mac/chip8.fs`、Windows1165と同じ設定）。classicのブザー約1秒→無音約1秒、XOの高い音→1オクターブ低い音（各約2秒）が説明どおりに聞こえた。連続XO音で物理Ctrl+C後に`CATCH= -28 handle=0`、約3秒の再再生、status0。各回underrun0、fd13は不変、thread8→6。1167と親1163を完了にした。採否（Forth維持）は変わらない。

## Windows1165/Linux1166の受け入れ完了（2026-11-20）

レモンが他アプリを止める機会を設けて開始を確認し、ＯＫの後にWindows→WSL/Linuxの順で正式再測定した。6負荷32768frame、各7fresh processのwall中央値。全計時でA5 bufferとRESET初期状態、全PCM/semantic22値/queue件数、stack0と正常終了を照合した。事前確認なしの旧値はJSONのreports_reference_onlyに保全し、今回の採否に使わない。

| 負荷 | Windows実時間比 | Linux/WSL実時間比 | timer有効frame率 |
| --- | ---: | ---: | ---: |
| classic | 65.026 | 76.924 | 1.000 |
| xo_default | 63.724 | 74.843 | 1.000 |
| xo_pitch255 | 64.835 | 74.416 | 1.000 |
| classic_60hz_gates | 66.962 | 77.296 | 0.683 |
| xo_changes128 | 83.212 | 91.902 | 0.290 |
| xo_8khz_pattern_pitch | 33.781 | 38.232 | 1.000 |

いずれも宣言した音源単独の測定であり、clock固定や他アプリの実際の停止状態まで検証したものではない。active率が低い変更負荷を常時発音の性能とは比較しない。8kHz負荷はpattern生成/コピー/enqueue/回収/描画を含み、compactionのworst caseや即時API単独の値ではない。CPU時間は参考値で、校正した分解能を保証しない。

両OSの実聴（classicのtimer停止、XOの1オクターブ切替、物理Ctrl+C停止/再再生）も合格。測定負荷の実時間余裕・独立PCM/状態照合と実聴を根拠に、この宣言範囲はForthに維持し、新しいnative語へ移さない。全エミュレータや未測定負荷の保証はしない。[全記録](measurements/2026-11-20-chip8-os-acceptance.json)。1165/1166を完了し、親1163は未完了・auto75%、Mac1167は未完了。以下の「正式測定待ち」「未実施」は当時の履歴。

2026-11-20、基点53ebe81。レモンが原型/SUPER-CHIPのブザーに加えXO-CHIPのpattern/pitchも対象とすることを承認した。CPU/命令decode/画面/ROMは実装せず、Fx18等から呼ぶ音源側をForthで試作する。1164は仕様/実装/独立検証、Windows1165・Linux1166・Mac1167は別の受け入れであり、Macまで親1163を完了にしない。INCLUDEDの相対パスはリポジトリ直下からの起動を前提とする。

## 資料と宣言する範囲

- [RCA COSMAC VIP manualの写し](https://storage.googleapis.com/wzukusers/user-34724694/documents/130d458901764787969269f48aeeee2a/VIP_Manual.pdf)の命令表はFx18 durationを1/60秒単位で示す。原機speakerは値1に応答しないという本文の制約がある。本モデルは現代的なtimer>0ゲートを宣言し、原機speaker/Q/割込みの電気的・cycle的な再現を主張しない。
- [仕様作者のXO-CHIP文書](https://johnearnest.github.io/Octo/docs/XO-ChipSpecification.html)は16byteのコピー、pitch既定64（4000bit/s）、rate=4000*2^((pitch-64)/48)、timerが0になった時のoffset reset、正のtimerの上書きではoffsetを保つ規則を示す。今回は仕様だけを参照し、他実装/ROM/音声素材は転用しない。
- SUPER-CHIPは音源側の基本timer/gateを共通利用する範囲。全SCHIP CPU互換、XO命令decode、原機の音色、Fx0Aによる音への作用、実時間のCPU割込みは含めない。

通常ブザーは独自の440Hz/±4096方形波。XOはMSB-firstの128bit列、bit0=0/bit1=4096の点標本を宣言する。両者とも48kHz s16LE mono、anti-alias/filterなし。XOのbit順・PCMレベル・mode切替時のphase resetはモデルの宣言であり、仕様にないsiliconの規則として扱わない。高pitchの折り返し、DC、clickは残る。

## 時刻・位相・イベント

48MHzの仮想tickを使い、60Hz境界は800000tick、1PCM frameは1000tick。これはプロジェクト内の時刻単位で、CHIP-8 CPUが48MHzという意味ではない。timer境界はRESETから固定し、Fx18で境界の位置を動かさない。同tickはtimer decrement/停止reset→予定event追加順→即時write/read→標本の順。timer=0の期間も境界位相は進み、音のphaseだけ止まる。

XOの位相はQ32のbit位置をmod128（2^39）で保持し、各tickのstepをfloor(rate*2^32/48000000)とする。全256pitchのtableを高精度Decimalで独自生成し、実行時は整数だけ。通常ブザーはcycle Q32（mod2^32）、step=floor(440*2^32/48000000)。分割TO/RENDERで端数を失わない。pitch/pattern変更と正timer再設定はphaseを保持、timer=0または自然に0へ到達した時はphaseを0に戻す。MODEの値が変わる時だけphaseを0へ戻し、同じMODEの再設定では保つ。phase=0のSAMPLEはclassicが+4096、XOはpattern先頭MSBで決まる。

TO/RUN/即時writeは時刻と状態だけを進め、飛ばした区間のPCMは作らない。RENDERは現在時刻から1frameずつ1000tick進めた後の状態を出す。予定eventで連続音声を作る。SAMPLEは適用済み状態だけを見る純粋queryで、同tickの未適用予定を反映するにはRUN0またはTIMER@を使う。

queueは1024件、各40byte（tick/kind/valueの3cellと16byteの所有pattern）。kindは0timer/1pitch/2mode/3pattern、patternのvalueセルは0。patternは即時/queue受付時に16byteをコピーし、呼出し後の元buffer更新に影響されない。予定は追加tick非減少、消費済み領域を回収して継続補充できる。invalid入力は状態やqueueを変える前に-24、満杯-528、不正なForth memoryはVMが-9を返す。queueはtick/値/容量/追加順を検査してからpatternを作業bufferへ読み、最後に回収/追加する。満杯と不正pointerが重なれば先に-528。作業bufferの部分書込みは公開状態と別で、pattern読み込みは時刻進行/queue回収より前に完了する。

RENDERはframesが非負かつframes <= (MAX-CYCLE)/1000を全体の前検査とし、時刻overflowは出力bufferや状態を変更せず-24。出力先のForth memoryが不正な場合の-9だけは、それ以前に進んだ状態/出力の巻戻しを約束しない。tick0のtimer境界はRESETで処理済みとし、TOで同時刻へ止め直す/RUN0ではdecrementしない。phaseの積はtimer境界ごと最大800000tickで分けるため64bitへ収まる。

## 公開語

| 語 | stackと用途 |
| --- | --- |
| C8-RESET | ( -- ) classic/mute、pitch64、pattern0、時刻/phase/queue0 |
| C8-TIMER! / C8-TIMER-EVENT! | ( byte tick -- ) Fx18相当の即時/予定値。0..255 |
| C8-PITCH! / C8-PITCH-EVENT! | ( byte tick -- ) Fx3A相当。classicでも値を保持し、音は440Hzのまま |
| C8-MODE! / C8-MODE-EVENT! | ( mode tick -- ) 0=classic、1=XO |
| C8-PATTERN! / C8-PATTERN-EVENT! | ( addr tick -- ) F002相当の16byteコピー |
| C8-TO / C8-RUN | ( tick -- ) / ( ticks -- ) 単調な絶対/相対進行 |
| C8-WRITE / C8-EVENT! | ( value kind tick -- ) 共通の即時/予定書込み。kind 0=timer、1=pitch、2=mode、3=pattern（valueはaddr） |
| C8-READ | ( kind tick -- value ) 共通の読取り。kind 0..2はtimer/pitch/mode、3は-21、ほかは-24 |
| C8-TIMER@ | ( tick -- byte ) 時刻をtickまで進め、予定も適用してtimerを読む |
| C8-SAMPLE / C8-RENDER | ( -- s16 ) / ( addr frames -- ) 呼出側がframes*2byteの有効bufferを用意 |
| C8-DEMO-SETUP / C8-XO-DEMO-SETUP | ( -- ) 独自の通常/XOデモ設定。読むだけでは再生しない |
| C8-STREAM | ( blocks audible -- ) play.fsを読んだ場合のみ。FALSEは合成後ゼロ、TRUEだけ生成音を送る |

MODEはホスト設定でありCHIP-8命令ではない。CPU adapterがFx18/F002/Fx3Aをこれらへ変換し、CPU時刻→tickと命令アクセス位置を別に確定する。今回CPUの実行速度/ROM互換を検証したことにはしない。

## 検証計画

独立Pythonを1標本ずつ進める数理モデルとし、全256pitch table・手計算timer境界・0/再設定・同tick順・128bitのbit順/コピー所有・分割進行・queue回収・原子的失敗を照合する。Q32の丸めは独立double表とも比べ、理想rateそのものとの違いを記録する。通常/XOと変更列の全PCM/終了状態を比較する。mono送出/cleanupは既存PCM helperを使い、無音の実hostと非ゼロRAM fixtureを区別する。1165/1166の計測・実聴およびMac1167は、この実装工程の成功で代用しない。

## 実装と独立検証の結果（2026-11-20）

Windows/Linuxの通常・debug/graphics/extension除外・さらにfloat除外・audio/graphics/extension除外の計8構成で各13検査群成功。全256pitch/65536frame、変更列8192frame、8kHz pattern/pitchの2730event、512件の未処理所有patternを回収後に全PCM/状態照合した。全processで終了時のForth stack深さ0も確認する。独立double表はDecimal生成の256値と一致し、bit-rate誤差は全値で48M/2^32未満（最大約0.0111757bit/s）。classicの量子化後は約439.994037Hzで、理想440Hzそのものではない。

音声有効6構成で非ゼロRAMだけの11fixtureが成功。monoの5frame→0→507frame部分書込みで全1024byteと2byte offsetを照合し、timeout・close再試行・一次例外優先・所有handleの保持・open/drain失敗・stream時刻overflowのOPEN前拒否を検査した。別途、Windows/Linuxの実PCMでclassic/XOを各8192frame合成後にゼロ化して送出し、drain/closeとhandle0、時刻8192000、stack0を確認した。生成波形を実際に聞いた結果ではない。

純粋モデルを読んだWindowsのHEREは122880→166000、増加43120byte。logical dictionaryの値で、RSSやコード領域全体の大きさではない。既存332ファイルのnative source指紋はYM2149時点と一致しており、同じReleaseFast/baseline/stripの実行体を再利用した。本体/Builtin/ABIは変更していない。

```powershell
python scripts/chip8-pitches.py --check
python tests/scripts/verify-chip8-audio.py .work/1138/matrix/windows/bin/sigma.exe
python tests/scripts/verify-chip8-audio-stream.py .work/1138/matrix/windows/bin/sigma.exe
sigma examples/chip8-audio-play.fs -e "C8-XO-DEMO-SETUP 16 FALSE C8-STREAM BYE"
```

[全結果・コマンド・ソース本文/指紋](measurements/2026-11-20-chip8-audio.json)、[Claudeレビュー評価](reviews/1164-review-response.md)。最終レビューはHigh/Mediumなし。速度測定とOS別の生成音実聴は1165/1166/1167に残り、Forth維持/本体移行の最終採否はその測定後に判断する。

1164を完了した。Windows1165/Linux1166/Mac1167は未完了で、親1163は未完了・auto25%。実装だけで各OSの実聴・性能測定の受け入れ完了とはしない。

## Windows/Linux実聴と測定準備（1165/1166）

両OSでレモンがclassicの約1秒再生→約1秒無音、XOのpitch247→199の高低各約2秒、物理Ctrl+C後の停止と約3秒再再生を確認した。各回handle0/underrun0/code0。LinuxはWSL2の静的musl版からpacat→WSLg PulseAudio RDPSinkを経た実出力で、Linux実機ALSAの確認とは区別する。

8構成のHERE/実行体サイズを記録した。通常のHERE増加は両OS43120byte。速度は6負荷32768frame、7fresh process、warmup/RESET・A5 bufferと初期状態確認、全計時の全PCM/終了22状態とqueue件数照合、計時外の書出し、順序回転を備えた測定スクリプトを用意した。denseは生成/コピー/enqueue/回収/描画を含み、wallを主指標とする。CPUは量子化し得る参考値。中央値を使い外れ値を除外せず、全raw値を残す。実装単独の速度とCPUエミュレータ全体の性能を混同しない。

今回の計測は利用者への開始確認より前だったため、速度値は信頼性の低い参考値としてのみ保存した。正式な採否と1165/1166の完了には、他アプリを止める機会を設けた確認後の再測定を残す。[記録](measurements/2026-11-20-chip8-os-acceptance.json)、[測定/実聴レビュー](reviews/1165-1166-review-response.md)。最終レビューはコードのHigh/Mediumなし。Mac1167は引き続き未完了。
