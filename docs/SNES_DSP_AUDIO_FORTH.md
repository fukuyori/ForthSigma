# SNES標準S-DSPのForth音源（1174）

2026-11-21：モデルと補助の表は`include/`へ移し、`*-DEMO-SETUP`などデモ用の語は`examples/<名前>-demo.fs`へ分けた（1185）。`*-play.fs`はデモのファイルを読む。以下の記録にある`examples/`のモデルのパスは、移す前のものである。

2026-11-21：語の名前と形をそろえた（1187）。どのモデルも`*-RESET ( -- )` `*-WRITE` `*-EVENT! ( value target tick -- )` `*-READ ( target tick -- value )` `*-RUN ( clocks -- )` `*-RENDER ( addr frames -- )`を持つ。共通の語の検査は`tests/scripts/verify-model-common-words.py`。

レモンが標準S-DSPの8声/BRR・envelope/noise・pitch modulation・echo/FIRを承認した。SPC700 CPU/ROM/APU port/実機bus/アナログ回路は含めない。1174は仕様/実装/独立検証、Windows1175/Linux1176/Mac1177で速度・採否・実聴。Mac完了まで親1173は未完了。

## 資料・実装の来歴

[Nintendo開発資料の写し](https://floating.muncher.se/bot/manual/book1_text.pdf)のDSP register/BRR/ADSR/GAIN/FIR章と、[Martin Korthのfullsnesハードウェア調査](https://problemkaputt.de/fullsnes.htm)を参照した。第三者掲載版の公式再配布許諾は確認できていない。原本/本文/図/擬似コードはリポジトリに転載せず、SDK/ROM/他エミュレータのソースは使わない。実装は新規Forthと独立Pythonで記述する。fullsnesはAnomie資料を基に実機確認した旨を著者が記載しているが、そこにも不明/推測の記述があり、全境界を実機保証とは扱わない。

Gaussの512係数はfullsnes掲載のハードウェア数値をデータとして参照し、抽出元hash・個数・値域・データhashを記録する。外部コードや資料本文のライセンスを本体コードへ適用したと主張するものではない。資料再配布許諾と、技術数値/演算規則を参照して新規コードを作ることを区別し、第三者の実装は移植しない。

## 時刻と公開API

公称32000Hzのstereo s16LE、時刻は仮想1024000tick/秒（32tickで1frame）。CYCLE0/DIV0から最初のframeはtick32。最初のframeより前のSAMPLEは0 0。各境界でframe処理→同tickの予定追加順→即時操作→標本の順。tick31の書込みはtick32のframe（frame1）に作用し、tick32の書込みは次frameから作用する。CPU clock/微細なDSPアクセスslotを再現する主張ではない。

RESETは128register、64KiB所有ARAM、voice/echo/history、clock、queueを全消去。FLG=E0h、noise seed=4000h、ENVはrelease0、他register0。実機の不定RAM/初期readを模倣せず、決定的な初期状態を宣言する。

| 語 | stack/用途 |
| --- | --- |
| SD-RESET | ( -- ) 全所有state/ARAM/queueを初期化 |
| SD-REG! / SD-REG-EVENT! / SD-REG@ | ( byte reg tick -- ) / 同左 / ( reg tick -- byte ) reg0..127 |
| SD-RAM! / SD-RAM-EVENT! / SD-RAM@ | ( byte addr tick -- ) / 同左 / ( addr tick -- byte ) addr0..65535 |
| SD-WRITE / SD-EVENT! / SD-READ | ( byte target tick -- ) / 同左 / ( target tick -- byte ) 共通の語。target 0..127はreg、128+addrはARAM |
| SD-TO / SD-RUN | ( tick -- ) / ( ticks -- ) 単調絶対/相対時刻 |
| SD-SAMPLE / SD-RENDER | ( -- left right ) / ( addr frames -- ) query/生成。各frame32tick進む |
| SD-DEMO-SETUP | ( -- ) 自作BRRと独自8声設定、音声装置は開かない |
| SD-STREAM | ( blocks audible -- ) play.fsのみ、FALSEは生成後ゼロ。1block512frame |

全registerはraw byteを保持し、PitchH等の未使用bitは動作時だけmaskする。ENVX/OUTXは毎frameで上書き。ENDXの任意writeは全bit clear。KONはraw値を保持するが別pending latchが最後のwriteで置換され、poll後にpendingだけ消去。0xF2/0xF3やSPC700のI/OはAPIの対象外。

予定は1024件の(value,target,tick)3cellでreg0..127、RAM128+addr。非減少tick順、消費済みprefixを回収。値/対象/過去tick/容量/末尾tick順をすべて検査してから変更し、error -24/-528ではstateとqueueを保持する。readは指定tickまで進め、SAMPLEはpendingをflushしない。即時操作後に追加した同tick予定は次のflushで適用し、過去へ並べ替えない。RENDER/STREAMは期間全体を除算で事前検査し、MAX超過/負数-24ではstate/output不変。callerがframes*4byteのbufferを用意し、不正memory -9では途中の時刻/stateを巻き戻さない。

## sample境界モデルの宣言

1. frame番号は1から。KON/KOFFを奇数frameでpollし、FLG resetは毎frame。KOFF/soft resetでrelease（resetはENV0）、そのpollのKONがあればvoiceを再始動しENDXを消す。KON後は5frameを無音とし、最後のdelay frameで最初のBRR値をhistoryへ取り込む。read/内部処理の正確なサブframe位相は未モデル化。
2. voiceはBRR start/loopをDIR*256+SRCN*4からLE16で読み、全ARAMアクセスは16bit wrap。16nibble/9byte、MSB nibble先、signed4bit。shift0..12はfloor(nibble*2^shift/2)、13..15は負なら-2048/他0。predictorは15bitの前2値を使い、filter1=old+floor(-old/16)、2=2old+floor(-3old/32)-older+floor(older/16)、3=2old+floor(-13old/64)-older+floor(3older/16)。加算をsigned16へ飽和してからsigned15へwrapし、履歴に保存する。
3. BRRは必要sampleの消費時に逐次読む。blockの16値を消費後にENDを処理し、ENDXをset、DIR/SRCNの現在のloop addrへ移る。END=1/LOOP=0はENV0/release、LOOP=1は維持。release/ENV0/noise中もBRRを進める。これは実機の先読み/ENDX更新slotの代用ではなく、宣言した境界モデル。履歴4値はKON時0、Gaussianで使用する。
4. pitchは14bit Q12、frame出力後に加算し、整数部だけBRRを消費する。PMONはvoice1..7のみ、直前voiceのENV後15bit値をfactor=1024+floor(prev/16)へ変換し、floor(pitch*factor/1024)を0..16383に制限する。Gaussianはhistory oldest..newとphase bit4..11を使い、係数積をfloor(/1024)、最初の3項和をsigned16 wrap、最後の項を加えsigned16飽和後floor(/2)して15bitを得る。noiseはGaussianを通さない。
5. ENVは11bit。attackはrate=2A+1、+32（A15は+1024）、2016以上でdecayへ。decay rate=16+2D、sustain rate=S、減衰はceil(ENV/256)。SL=(level+1)*256以下でsustain。releaseは毎frame-8。GAIN direct=low7*16、4modeはlinear-32/exp減衰/linear+32/bent（ENV<1536なら+32、他+8）。0..2047飽和。GAIN時もattack/decay/sustain状態を更新し、境界はADSR2を使う（実機のgarbage-boundary現象は未モデル化）。
6. 32rateの期間は0停止、2048,1536,1280,1024,768,640,512,384,320,256,192,160,128,96,80,64,48,40,32,24,20,16,12,10,8,6,5,4,3,2,1frame。全声/ノイズで共通のframe番号mod期間=0で更新し、KONはこの位相をresetしない。実機rate counterの個別offsetは未モデル化。noiseはvoice処理前に1回だけ、15bit seed4000hのbit0 XOR bit1をbit14へ戻すright shift、signed15値を全NON声へ共有する。
7. ENV後はfloor(sample15*ENV/2048)、ENVX=ENV>>4、OUTX=ENV後>>7。voice左右はsigned8 volumeをfloor(/64)し、声順で各加算後signed16飽和。EONのecho入力も同じ演算。MVOL/EVOLは各floor(/128)をsigned16 wrapして最終和をsigned16飽和。analog post-ampの反転は加えない。
8. 全voice処理後、echoをARAMからLE16で読みfloor(/2)して左右各8値履歴へ置く。FIR0 oldest..FIR7 newest、積floor(/64)、先頭7項和をsigned16 wrapし最終項を加えてsigned16飽和。echo入力+floor(FIR*EFB/128)をsigned16飽和しbit0を0にして同じARAM位置へ書く。FLG bit5はwriteのみ抑止、muteは出力のみ0で内部は進行。ESAはframe時点の値、EDLはoffset0の時にmax(4,low4*2048)をlatchし、offsetを4ずつ進めlengthでwrapする。微細なESA write delay/echo RAM slot競合は未モデル化。

## 検証計画

全BRR header/nibbleと符号/飽和境界、16bit wrap、全32rate/ADSR/GAIN、Gauss全256phase、8声stereo/signed volume/PMON、noise共用、echo全tap/feedback/EDL/ESA/同ARAM競合を別表現のPythonと手計算で照合する。queue同tick/回収/満杯、error原子性、MAX成功/失敗、分割/一括の全PCM/状態も検査。通常/no-debug/no-float/no-audio各Windows/Linuxを確認し、RAM callbackで部分送出/cleanupを検査する。自動検査は非ゼロRAMと無音実PCMのみ。速度測定はレモンの開始確認後、生成音の実聴はOS子タスクで行う。


## 設計レビューで確定した順序

KON poll frame fをdelayの最初としf..f+4は無音。start addrはfで読み、delay中pitch/PMONは停止。f+4の最後に最初のBRR値を履歴へ入れる。Gaussはoldest×g[255-i]、older×g[511-i]、old×g[256+i]、new×g[i]の順（i=(phase>>4)&255）で、補間による追加の遅れがある。

通常voice frameは、更新前ENVで出力とENVX/OUTXを作る→ENVを更新しmode境界を毎frame判定→pitchを加えBRRを消費、の順。16個目を履歴へ入れた同じ消費処理でENDX set→現在のDIR/SRCNのloop addr取得→nonloopならENV0/release。次block headerはその最初のnibbleの消費時に1回だけ読む。したがってENVXと内部ENVが同じframe内でも異なり得る。

MVOL/EVOL/EFBの各floor(/128)をすべてs16 wrapしてから加算する。EFBを含む-128乗算境界、PMON上限0..16383、BRRのs16飽和→s15 wrap（+7FFF→-1、-8000→0）はモデル側の決定で、資料の未確定/不整合箇所を実測した主張ではない。GAIN bentの未clamp内部値やgarbage-boundary、ENDX先読みslotは未モデル化。

即時/read/TO/RUNも全引数を検査してから時刻を進める。reg/addr範囲→byte/target→過去tick→未処理件数1024の容量→末尾tick順で検査。RUNの負数/加算overflow、TOの過去tickは-24。容量と逆順が同時なら-528が先。正当なread/write/TO/RUNと正frame数のRENDERは現在tickの予定を次frame前にflushする。RENDER0/SAMPLEはflushしない。frame番号はCYCLE/32以下なので、公開APIのMAX時刻制約内ではsigned64をoverflowしない。

STREAMの検査順は負block -24→既存handle -528→全期間MAX -24。初回min(blocks,8)×512frameを16384byteに生成してから一括公開、以降512frame/2048byte、offsetはwritten*4。nativeは32000Hz stereo、host48000Hzへのsample-holdはDSP内Gaussianの代用ではない。


## 1174完了時の検証結果（2026-11-20）

Windows/Linuxの通常・no-debug・no-float・no-audioの8構成で各19モデル検査群が成功。全BRR header×nibble×3履歴、全Gauss位相×4履歴、全32rate、317ENV case、全128register×256byte/全65536ARAM、手計算のsigned境界/FIR8impulse/noise20値/KON delay等を含む。

10個の2048frame統合caseを一括/分割で検査し、全stereo PCM/266semantic state/全64KiB ARAMを独立Pythonと照合。nonloop/noise、最大pitch/PMON clamp、FIR負値/先頭7項wrap、echoの16bit wrapとBRR/DIR alias、ADSR/GAIN、DIV17も含む。必要なoracle分岐が実際に発生することをassertした。queue/errorの全state/ARAM/queue保持、回収/満杯、MAX成功/失敗、不正memoryの途中進行も成功。

音声有効6構成では各19stereo RAM callback検査が成功。Gaussian係数は保存元HTMLのhashを確認した別token抽出で全512値と照合し、pinned numeric hash/単調性/係数和も検査した。共有するhardware数値dataと独立した算術/heap queueの検証を区別する。

Windows/Linuxの実PCM経路で各8192frameをFALSE指定で送出し、AUDIO?=-1、handle0/underrun0/stack0/code0を確認した。Linuxで最初にAUDIO?=0だった回は参考記録に保持し、owned接続保持後の実経路を別に確認した。残留Sigma/pacatなし、保持用処理も終了済み。1174機能検査の時点では生成音の実聴と速度測定は行っていない。後続の速度測定は次節に記録する。

Windows fullのHEREは122880→218632（増分95752byte、HEREのlogical領域のみでRSSや全allocator使用量ではない）。再生wrapperの初回16384byte/通常2048byteは別。native332ソースの指紋が一致する既検証8構成を再利用し、native binaryの増加は0。[全結果/ソースと来歴](measurements/2026-11-20-snes-dsp-audio.json)、[レビュー評価](reviews/1174-review-response.md)に保存した。

1174は最終レビューHigh/Mediumなしで完了。1175/1176は初回測定後の再評価中、1177は未実施で、Mac1177を完了するまで親1173は未完了のまま。全標準機のbit一致やCPU/ROM実行、微細slotの互換を確認した主張ではない。

最終Low対応後も8構成×19モデル検査と6構成×19RAM検査を再実行し成功した。全8モデルreportで保存HTMLからの別抽出が実行されたこととcurrent source hashを確認した。親1173は未完了・auto25%。

1175/1176の測定準備では6負荷各16384frameを両OSで計時せず照合し、全PCM/状態/ARAMと初期ARAM resetも一致した。[準備データ](measurements/2026-11-20-snes-dsp-os-preparation.json)、[計画レビュー](reviews/1175-1176-review-response.md)を参照。これは初回測定前の準備記録で、現在の測定結果と候補検証は次節を参照。生成音の実聴は未実施。


## 1175/1176初回測定とARSHIFT候補

レモンの開始確認へのＯＫ後、通常構成6負荷各16384frameを7回の別processでWindows→WSL/Linuxの順に測定した。全回で全PCM/266state/queue2/fullARAM、初期ARAM reset/前状態/A5/DEPTH0が一致した。外れ値を除外せず全7値を保存し、中央値と実時間比を再計算した。[全測定値・旧source・候補検証](measurements/2026-11-20-snes-dsp-os-acceptance.json)。

| 負荷 | Windows ns/frame | Windows 実時間比 | Linux ns/frame | Linux 実時間比 |
| --- | ---: | ---: | ---: | ---: |
| one_voice | 12421.03 | 2.516倍 | 10247.19 | 3.050倍 |
| eight_voices | 29504.86 | 1.059倍 | 24337.81 | 1.284倍 |
| brr_filter3_pitchmax | 73515.50 | 0.425倍 | 62119.90 | 0.503倍 |
| adsr_shared_noise | 26645.77 | 1.173倍 | 22358.42 | 1.398倍 |
| echo_fir8 | 31794.02 | 0.983倍 | 26649.05 | 1.173倍 |
| dense_8khz_reg_ram | 30100.57 | 1.038倍 | 25247.48 | 1.238倍 |

最重負荷は両OSで実時間未達、Windowsのecho負荷も1倍未満。初回測定版を宣言全負荷の実時間再生に採用するには不足する。音源core単独の値で、SPC700/ROM/装置を含む測定ではなく、任意traceの上限保証でもない。

まずForthのSD-ASRを、倍長除算によるfloorから既存ARSHIFTへのaliasへ等価置換した候補を作成した。使用するshift1/4/5/6/7/10/11は同じfloor結果である。native/ABI/公開APIは変えていない。旧helperと候補の境界115vectorを両OSで直接比較し、新helperの64bit境界1344vectorを含む8構成×20モデル群、6構成×19送出群が成功。全6負荷の計時なし検証でもPCM/ARAM hash・全state/queueが初回測定と完全一致し、oracleのbrr/Model/demoのASTとharnessが変わっていないことを確認した。

[Claudeの候補レビュー](reviews/1175-1176-arshift-claude-review.md)も使用範囲で同値と評価し、本体移行前の評価を推奨した。改善幅は未測定。初回測定値/旧sourceを保存したまま、候補の再測定は新たな開始確認への返答待ち。結果が不足する場合の本体移行判断も残す。HEREは候補でも122880→218632、native332ソース/8binaryの指紋も不変。

1175/1176は再評価・実聴待ちで未完了、Mac1177と親1173も未完了。速度測定に使った旧版と、現在の候補sourceは結果JSONで分けてある。

## ARSHIFT測定後とnativeフレームkernel 1183

新たな開始確認へのＯＫ後、同じ6負荷・各7回をWindows→WSL/Linuxで測定し、全PCM/state/queue/ARAMと初期状態を全回照合した。旧値は前節とJSON内のbaselineへ保存した。

| 負荷 | Windows ns/frame | Windows 実時間比 | Linux ns/frame | Linux 実時間比 |
| --- | ---: | ---: | ---: | ---: |
| one_voice | 9653.31 | 3.237倍 | 8550.28 | 3.655倍 |
| eight_voices | 24517.14 | 1.275倍 | 21680.68 | 1.441倍 |
| brr_filter3_pitchmax | 62966.55 | 0.496倍 | 56192.56 | 0.556倍 |
| adsr_shared_noise | 22653.36 | 1.379倍 | 20192.02 | 1.548倍 |
| echo_fir8 | 26467.44 | 1.181倍 | 23377.65 | 1.337倍 |
| dense_8khz_reg_ram | 24944.02 | 1.253倍 | 22314.15 | 1.400倍 |

全負荷で改善したが最重BRRは1倍未満のため、宣言全負荷の実時間Forth採用は保留した。承認済みの「速度不足の音源だけ本体へ移す」方針に従い、1173直下に1183を追加し、1175/1176/1177の依存にした。Macを含むOS受け入れを完了扱いにしない。

[設計とレビュー反映](SNES_DSP_NATIVE_DESIGN.md)に従い、AUDIOへ同期語 `SNES-FRAMES`／内部語 `SND-SNES-FRAMES` を末尾追加した。時刻付きキュー・レジスタ・ARAMはForthが所有し、装置を開かずフレーム処理だけ本体で行う。既存IDは保持するが、builtinのABI署名が変わるため旧保存イメージは再作成が必要。

既定は参照Forth版のまま。以下はRAM内の処理を選ぶ読込みで、音は再生しない。

```forth
S" examples/snes-dsp-audio-native-demo.fs" INCLUDED
SD-DEMO-SETUP
CREATE OUT 4096 ALLOT
OUT 1024 SD-RENDER
SD-USE-FORTH
SD-USE-NATIVE
```

`SD-RESET`はバックエンド選択を保持する。nativeで未規定の作業用SD-MIX/SD-EMIXを参照しないこと。状態レコード内のtyped pointer登録は用途外で、各セルの完全書込み通知によりForthと分類結果が異なり得る。バイト領域は実際のENVX/OUTX/ENDX/echo書込みだけを通知する。adapterをMARKER/FORGETで消す前にForthへ戻す。

native版の機能検証結果は次節に記す。この段階では速度は未測定で、実時間の採用判定・生成音の実聴・OS別の中断再生・Mac受け入れは引き続き未完了。Forthの当初HERE値は旧ソースの履歴であり、現在のglobals連続配置・dispatcher追加後の値とは分けて記録する。

## native1183の機能検証結果

[全36report・ソース/実行体指紋・再現情報](measurements/2026-11-20-snes-dsp-native.json)、[レビュー評価](reviews/1183-review-response.md)。最終レビューHigh/Mediumなしで1183完了。8構成の参照Forth19モデル群、音声有効6構成のnative23群、両backend各19RAM群、一括frame/DIV・切替え・reset・SAVESYSを照合。通常2構成ではEXEC-LIMITED中断の完了k-frameとPython全state/ARAM、queue保持と再開も一致。6負荷は両OS・両backendで計時なしの全PCM/266state/queue2/fullARAMが一致した。

no-audioでは語が未定義でnative画像を拒否し、旧ABI画像も両OSでINVALID IMAGE/exit1。core1130/host162成功、skip10/15。通常版はWindows2161664byte（旧比+15872）、Linux2371680byte（+15328）。HEREは両OS122880→218640（logical増分95760byte）でAUDIO/adapter読込みでは増えなかった。これらはRSS/heap/code/dictionary全体の測定ではない。

1183の機能検証完了時点ではnativeの速度は未測定だった。新たな開始確認への返答後の6負荷×7回の結果は次節に記す。1175/1176/1177と親1173（auto40%）は未完了で、実聴・物理中断/再再生・Mac確認を残す。

## native候補の速度測定（1183後、2026-11-20）

レモンの新たな開始確認へのＯＫ後、Windows→WSL/Linuxで6負荷各16384frame×7processを順に測定した。全回で全PCM/266state/queue2/fullARAMと前状態/初期ARAM reset/A5が一致。既存Forth版とも全PCM/ARAM hashと最終状態が一致し、現物binary/source hashも機能検証時の記録と照合した。中央値を全7値から再計算し、外れ値は除外していない。[全7値・ソース・比較・採否](measurements/2026-11-20-snes-dsp-os-acceptance.json)のnative_candidate_timingsを参照。

| 負荷 | Windows ns/frame | Windows 実時間比 | Linux ns/frame | Linux 実時間比 | Forth比 Windows / Linux |
| --- | ---: | ---: | ---: | ---: | ---: |
| one_voice | 653.43 | 47.82倍 | 645.42 | 48.42倍 | 14.77 / 13.25倍 |
| eight_voices | 726.12 | 43.04倍 | 711.77 | 43.90倍 | 33.76 / 30.46倍 |
| brr_filter3_pitchmax | 863.01 | 36.21倍 | 846.08 | 36.94倍 | 72.96 / 66.42倍 |
| adsr_shared_noise | 743.78 | 42.02倍 | 712.26 | 43.87倍 | 30.46 / 28.35倍 |
| echo_fir8 | 759.03 | 41.17倍 | 736.91 | 42.41倍 | 34.87 / 31.72倍 |
| dense_8khz_reg_ram | 1089.35 | 28.69倍 | 1030.12 | 30.34倍 | 22.90 / 21.66倍 |

宣言6負荷のcore単独処理は両OSで実時間を満たし、次の再生受け入れにはnative候補を採用する。最小の余裕はdense8kHzでWindows28.69倍/Linux30.34倍。従来不足したBRR/filter3/maxpitchは36.21/36.94倍となった。参照Forthを既定として残し、nativeは明示adapterで選ぶ。SPC700/ROM/実装置込みの測定でも、任意traceの最悪時間保証でもない。

サイズは既検証のWindows2161664（旧比+15872）/Linux2371680（+15328）byteのままで、実行体を再ビルドしていない。1175/1176の実聴・物理Ctrl+C停止/再再生とMac1177は未完了。親1173も未完了のまま。今回は生成音を実装置へ出力していない。

## Windows1175の受け入れ（2026-11-20）

Windows11 build26300/x86_64の通常/no-debug/no-float/no-audioで機能/サイズを確認し、通常版の6負荷は全7回のPCM/state/ARAM一致、最小実時間比28.69倍。生成音の右高音は初回、元と同じ左低音は単独再試験でレモンが確認した。初回の連続LEFT LOW→RIGHT HIGHでは「右しか聞こえなかった」との報告を保存し、その連続試験は再実行して合格したわけではない。raw440HzのL/R/Bと元の左低音単独再試験がＯＫであっても、初回原因を特定した・本体/設定を修正して直したとは主張しない。

物理Ctrl+CはCATCH=-28、handle0、受理81856frameで停止。500ms後の低音98304frameはhandle0/underrun0/DEPTH0/exit0、レモンからＯＫ。終了後のsigma.exe残留なし。各試聴の実行体とincluded sourceを照合し、実際のWindows supervisorソースをハッシュとともに保存した。

確認範囲は物理Windowsホスト上のwaveOut/WAVE_MAPPER既定経路を通した人の実聴と停止・再再生。試験後の既定console/multimedia出力は `CABLE Input (VB-Audio Virtual Cable)` で、後段の物理スピーカー/ヘッドホンと、再生中のopen handleのendpointは同定していない。直接接続機器での検証完了とは扱わない。[実行/最初の失敗/後続確認/装置snapshot/全source](measurements/2026-11-20-snes-dsp-os-acceptance.json)のwindows_acceptance、[最終レビュー原文](reviews/1175-windows-final-claude-review.md)。

最終レビューはHigh0/Medium3。状態の食い違いを修正し、装置経路と最初の連続試験の制限を明記すれば、宣言したWindows範囲を完了にできるという評価に従い1175を完了。Linux1176・Mac1177と親1173（auto60%）は未完了。物理中断の確認は1回で、保護されたPCM待ちの外で信号を受けると終了し得る制限も残す。

## Linux1176の実聴準備

Ubuntu26.04.1/WSL2のPulse情報取得で初回は接続拒否、直後はPulseServer socketなし。owned接続保持中のログでsocket生成とWSLg RDPSink初回接続失敗→接続成功を確認し、その後はPulseAudio17/RDPSinkへ接続できた。元の失敗は別記録に保持。追加の同一process無音試験では前後AUDIO?=-1、各98304frame/handle0/underrun0/DEPTH0/code0。実際のpacat sink inputもs16le/2ch/48000Hz・front-left/right・balance0で記録した。OS/音声設定は変更していない。

左右の全PCM/state/ARAM proof、無音結果と全ソースhashを確認する--check-readyも成功。generated Linux音と物理Ctrl+Cは未実施で、開始確認待ち。WSLg経由の結果を物理LinuxハードウェアやALSAの合格に外挿しない。keepaliveは.work/1175-1176に両OSのPIDを記録したowned sleep1800で、Linux完了後に本人確認して回収する。[失敗/環境/同一process装置確認/準備](measurements/2026-11-20-snes-dsp-os-acceptance.json)のlinux_acceptance_preparation。

## Linux1176の受け入れ完了（2026-11-20）

Ubuntu26.04.1/WSL2、static musl実行体5054e20f…で、左低音→右高音の各98304frameと、人のＯＫを確認した。物理Ctrl+CはCATCH=-28/handle0/受理155136frame、500ms後の低音98304frameはhandle0/underrun0/DEPTH0/exit0/timeoutなしでレモンからＯＫ。受理数は先行キューを含む論理入力frameで、キーを押すまでの実時間を測った値ではない。

最初の補助無音ログではLEFT LOW表示が欠けていた。Linux上のreadline→communicate混用が先読み済み行を取りこぼすことを音なしで切り出して再現し、元の不完全ログとhelperを保存した。Windowsでは同じ再現は起きないことも記録。出力を1つの一時ファイルで全量回収する方式へ直した無音機能再試験では、両ラベル・前後AUDIO?=-1・2段階handle0/underrun0/98304frame・DEPTH0/code0を確認。pacat PID460のPPid459が試験Sigma PID459と一致することも確認した。音源本体/実行体は変更していない。

Linuxランチャーは、起動前readiness hashと実行後hashが一致するsnapshotと、実際の起動toolのpathで記録した。元のsupervisorが誤ってWindowsランチャーのhashを記録した欄は元データとして残し、Linux caller attributionを別に補った。今後のhelperはOS別launcherを選ぶ。actual-run supervisor snapshotと、後でmetadataを直した現行helperを混同しない。

確認範囲は従来のLinux受け入れと同じWSL/PulseAudio経路で、直接ALSA/物理Linux/全backendの合格にはしない。初回Pulse接続拒否・socketなし・後続のRDPSink接続成功を保持した。修正後の無音再試験はactive pacat sink入力ID1を記録したが、ID1=RDPSinkの名前対応は前のready-session情報による間接的な対応で、同じ時点の名前一覧を再照合したわけではない。この制限も全結果へ保存。Windowsで実行したcore1130/host162 unit testsを、Linux unit実行とは扱わず、Linuxは別の4構成CLI/oracle/stream/画像検査で確認する。

[初回レビュー](reviews/1176-linux-final-claude-review.md)のHigh1/Medium3を反映し、[追レビュー](reviews/1176-linux-followup-claude-review.md)は最新状態更新を条件にblocking High/Mediumなし。状態・cleanup表記をそろえ、1176を宣言WSL範囲で完了にした。[完全ログ・旧不完全ログ・再現・source/launcher snapshot](measurements/2026-11-20-snes-dsp-os-acceptance.json)のlinux_acceptance。Sigma/pacat残留なし、owned sleep1800はPID310とcmdlineを照合してSIGTERM、Windows controller29088の終了も確認。他のuser processやWSL全体は停止していない。

1174/1183/1175/1176完了、Mac1177未完了のため親1173は未完了auto80%。追加の速度測定やコミット/プッシュはしていない。Macは新しいnative builtin/ABIに対応した新ビルドが必要で、旧保存画像は再作成が必要。次の音源はApple II1179だが、対象モデル/追加音源の範囲を利用者と確定してから着手する。
