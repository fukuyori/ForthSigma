# NES DMCと5声のForth試作（1135）

2026-11-20、基点main816129a。[NTSC 4声1134の記録](NES_APU_FORTH.md)にDMCを加えた。1135とNES1132のモデル・実測・採否を完了した。999全体はauto28%で未完了。今回の差分は未コミット。Builtinや既存NES-SOUNDは変更しない。先行照合1139と最終採否1140、SID1136/Paula1137/ST1138は別作業として残す。

## 資料と再現範囲

NESdevの[APU DMC](https://www.nesdev.org/wiki/APU_DMC)、[メモリ読取りと出力](https://www.nesdev.org/wiki/DMC)、[status](https://www.nesdev.org/wiki/APU_Status)、[mixer](https://www.nesdev.org/wiki/APU_Mixer)を索引本文で照合した。任天堂の公式仕様ではなく、他エミュレーターのソースや市販ROMは使用していない。参照日は2026-11-20。

実装するのは、4010..4013、4015のDMC制御/status、メモリreader、1byte buffer、8bit LSB-first出力、DAC、loop/IRQと既存4声との混合。CPU/PPU、DMAのCPU停止・bus競合、mapper/open bus、電源投入時の位相、4011とtimerの同時書込みの不安定な挙動、PAL、アナログfilter/帯域制限は範囲外。ROM互換や実機と同じDMA時刻を主張しない。

## DMCの契約

- rate表はCPU単位で428,380,340,320,286,254,226,214,190,160,142,128,106,84,72,54。index13は84で、古い85の値は採用しない。偶数CPU時刻にclockするため、内部dividerはrate/2−1。
- resetはDAC=0、timer=0、period=213、bits=8、silent=1、reader/buffer/shift/IRQを0にする。timerとbitsはdisabled/silentでも進める。
- 1clockの先頭で、bufferが空かつ残りbyteが非0なら1byteを取り込む。実機のDMA待ちは実装せず、この試作ではreaderの取り込みを次のCPU clockに反映する。取り込みは同じclockの出力処理より前。fast版もこの境界で分割する。
- 開始番地はC000+64×4012、byte長は16×4013+1。読取り番地はFFFFの次を8000へ折り返す。最後のfetchで、loopならreaderを再開し、そうでなくIRQ enableならDMC IRQを立てる。最後のbitを出し終えた時刻とは区別する。
- 出力clockではsilentでなければshiftの下位bitに応じて±2する。ただし0..127を出る場合は変化しない（126+2は126のまま、1−2は1のまま）。毎回shiftとbitsを進め、8bitの区切りでbufferをshiftへ移す。bufferが空ならsilentにする。
- 4015書込みはDMC IRQをclearする。bit4=0ならreaderの残りbyteを0、bit4=1で残り0なら開始位置/長さから再開する。既にbuffer/shiftにあるbitやDACは消さない。
- 4010のIRQ enableを0にするとDMC IRQをclearする。rate変更はperiodを変え、カウント中のtimerをリセットしない。4011はbit7を無視し、readerの有効/無効に関係なくDACをmixerへ出す。

## メモリと語の変更

専用の32768byteを、エミュレートしたCPU番地8000..FFFFへ対応させる。moduleを読み込む時だけ0初期化し、NA-RESETでは消さない。bank切替やhost callbackは実装しない。

`NA-MEM! ( byte address -- )`はbyte0..255と番地範囲を検査してから、現在のNA-CYCLEの時点で直ちに書く。不正値は-24で、時刻・状態・メモリを変えない。予定表には入らず、未来の時刻へのメモリ書込みではない。先にNA-TO/NA-RENDERで時間を進めれば、その後の現在時刻で反映される。既に取り込んだbufferは変更しない。

既存のNA-WRITE/NA-EVENT!は4010..4013と4015 bit4を受け付けるようにした。従来の-21拒否はなくなる。他の事前検査、同時刻の順序、予定表の未処理1024件と領域回収は維持する。

| 語 | 1135の動作 |
| --- | --- |
| NA-STATUS ( cycle -- status ) | bit4はreaderの残りbyte非0、bit7はDMC IRQ。frame IRQだけをclearし、DMC IRQは消さない。open bus bit5は再現しない |
| NA-IRQ? ( -- flag ) | frame IRQまたはDMC IRQが立っていればtrue。どちらも消さない |
| NA-RESET ( -- ) | APUと予定表は初期化するが、専用サンプルメモリは保持する |
| NA-SAMPLE ( -- s16 ) | 5声を非線形DAC式の表で混合する。DMCがdisabledでもDAC値を含む |

## 混合と数値

pulse表31項目とtriangle/noise/DMC表32768項目を使い、index=(triangle×16+noise)×128+DMCとする。資料の近似DAC式を有理数で計算し、pulseとTNDを別々にfloor(level×32767)して加算する。大きい中間積はUM*/UM/MODの倍長演算で扱い、符号付き64bitのoverflowを避ける。最終値は32767を上限にする。表は論理メモリで256KiB、サンプルmapは32KiB。アナログ回路の実測表ではない。

DMC=0なら1134の4声の表と値が一致する。変更前の測定値・指紋を保ち、再現に必要な旧ソース本文を[1134のJSON](measurements/2026-11-20-nes-apu.json)のsource_snapshots_lfへ追加した。旧値を5声の新しい値で置き換えていない。

## 検証・測定

[verify-nes-apu.py](../tests/scripts/verify-nes-apu.py)の既存4声試験をDMC状態を含む形で回帰し、[verify-nes-dmc.py](../tests/scripts/verify-nes-dmc.py)で追加試験を行う。独立した実装はPythonのper-CPU modelであり、Forthの2版はヘルパーを共有する。Pythonも同じ資料・状態配置から書いたため共通の読み違いは残る。手計算した出力・IRQ・境界と全LUTの任意精度計算を補い、実機/ROM試験と混同しない。

```powershell
python tests/scripts/verify-nes-dmc.py zig-out/bin/sigma --benchmark
```

サンプルは独自のbyte[i]=(37i+11)&255で、市販ROMや第三者の音声を使用しない。PCM自動試験は5声を合成した後で0を渡す。生成波形の実聴、実機DMA、Macでの新しい例の実行は未確認。既存PCM基盤のMac1130は完了済み。

### 測定の比較条件

無音PCMの全process時間には、32768項目のmixer表の初期化と、32KiBのDATAパターン生成も含む。1134の256項目表の全process時間とは直接比較しない。合成専用のtimed regionからは初期化・warm-up・reset・サンプルデータ生成とcycle0設定を除く。fast_dac_8khzだけは、再生中のenqueueと領域回収も測定区間に含む。除外構成での表の読込み結果は、結果欄へ実行確認として記録する。

## 実行結果

Windows GNU/Linux musl（WSL）の通常版とdebug/graphics/extension除外版の4構成すべてで、既存APU回帰12検査群と追加DMC8検査群が成功した。4声時点の固定PCM SHA256もc63131af…d94755へ固定し、ForthとPythonを同時に変更しても旧結果を定義し直せないようにした。生成byte列の全照合、全16ratesの境界80点、loop/stop/restart/IRQ/DAC/wrapの境界36点、手計算したrate変更時のtimer保持・wrap・再有効化を含む。

予定表1024件を超える8kHz DACの連続投入で領域回収と8192frameの全byteを照合した。メモリ書込みの不正値では全32768byteと74値の状態が変わらない。全32799項目のLUTはPythonの任意精度整数計算と一致し、pulse最大8469、TND最大24297、合計32766だった。最終32767制限は現在の正しい入力範囲では効かない。

audio/graphics/extension除外版でも純粋な5声の合成例をWindows/Linuxで実行した。debug/graphics/extension除外版で256KiBの表と32KiBのサンプルmapを読み込めたことを、実行結果として記録する。今回の本体ソースは変更しておらず、以前のPCM1129のReleaseFast/cpu=baseline/strip=true実行体をソース指紋照合後に使った。

[全結果・コマンド・指紋・生データ](measurements/2026-11-20-nes-dmc.json)を保存した。変更前1134の4構成の結果は、当時の.work/1132 JSONと同一のオブジェクトであることを照合した。保存した旧ソース本文から当時のLF SHA256も再現した。

## サイズと合成負荷

本体の実行ファイルは変更しない。Windows通常版でmodule単体の読込み前後のHERE差を測ると、旧4声は27768byte、5声は320880byteで、論理辞書領域の増加は293112byteだった。これはprocess RSSや予約メモリ量の測定ではない。増加の中心は256KiBのTND表と32KiBのサンプルmapである。

各負荷32768frame（約0.683秒分、1,221,690CPU clocks）、新しいprocess7回。各processで同じ負荷をwarm-upし、RESETとcycle0の設定を済ませてから測った。4声+DMCの状態、memory readerとloop/IRQ、128件の時間指定書込みを含む。最速条件はnoise index0とDMC rate15。別のfast_dac_8khzでは5461件の直接DAC書込みを描画中に分割して登録し、そのenqueue/領域回収も測定時間へ含めた。

NTIMEのwall差とCPUTIMEのCPU差、最終バッファのbyte和、最終cycle、stack深さ0を確認した。byte和だけでは順序違いをすべて検出できないため、別試験の全byte照合で補う。時刻の正方向の跳躍を完全に検出できず、WindowsのCPU時間もwallより粗い。ホストはAMD Ryzen 7 7700（8core/16thread）で、他アプリは停止せずCPU周波数も固定していない。

| OS | 負荷/実装 | 中央値 ns/frame | 中央値 ns/CPU clock | 実時間比 |
| --- | --- | --- | --- | --- |
| windows | fast | 2398.04 | 64.31 | 8.69倍 |
| windows | reference | 20260.49 | 543.37 | 1.03倍 |
| windows | fast_max_noise_dmc | 3376.32 | 90.55 | 6.17倍 |
| windows | fast_dac_8khz | 3045.18 | 81.67 | 6.84倍 |
| linux | fast | 2062.53 | 55.32 | 10.10倍 |
| linux | reference | 17635.65 | 472.97 | 1.18倍 |
| linux | fast_max_noise_dmc | 3029.41 | 81.25 | 6.88倍 |
| linux | fast_dac_8khz | 2656.19 | 71.24 | 7.84倍 |

この5声の定義したNTSC APUモデルは、まとめ処理版をForth側で維持する。Windows/Linuxとも、最速noise/DMCと8kHz直接DACを含む測定負荷で実時間を上回ったため、今回の範囲で本体へ新しい音源を追加する必要は認めなかった。1clock版は共通ヘルパーを使う確認用として残す。

CPU/PPUやDMAの停止、アナログfilter、装置遅延を含むNES全体の性能とは異なる。SID/Paula/STなど別機種の採否も、この値からは判断しない。

## 無音PCMの送出結果

5声を8192frame合成した後で0を渡した各1回。全process時間は初期化・sample map生成・open/write/wait/drain/close/終了を含み、旧4声の全process時間とは直接比較しない。装置の再生完了時間でもない。

| 対象 | 全process 秒 | frames | AUDIO? |
| --- | --- | --- | --- |
| windows | 0.320 | 8192 | -1 |
| linux | 0.836 | 8192 | 0 |
| windows-no-debug | 0.311 | 8192 | -1 |
| linux-no-debug | 0.815 | 8192 | 0 |

LinuxのAUDIO?=0は無音の消費で、実音声装置の確認ではない。生成波形を実際に聞く確認とMac上のこの例の実行は未確認として残す。

## レビュー

[設計原文](reviews/1135-design-claude-review.md)、[実装原文](reviews/1135-implementation-claude-review.md)、[最終原文](reviews/1135-final-claude-review.md)、[評価・採否](reviews/1135-review-response.md)を分ける。Claudeは読み取り専用で、実行試験をしたという意味ではない。最終レビューはHigh/Mediumなし。固定4声ハッシュ、rate保持の手計算、全対象の最終採否の依存関係、測定条件の説明を補強した。
