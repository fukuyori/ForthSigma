# NES APUのForth試作（NTSC 4声、1134）

2026-11-21：モデルと補助の表は`include/`へ移し、`*-DEMO-SETUP`などデモ用の語は`examples/<名前>-demo.fs`へ分けた（1185）。`*-play.fs`はデモのファイルを読む。以下の記録にある`examples/`のモデルのパスは、移す前のものである。

2026-11-20追記：DMCを加えた現行5声の契約は[NES DMCの記録](NES_DMC_FORTH.md)を参照。以下の4声・DMC除外・-21拒否・IRQの記述は1134時点の履歴。旧ソースは測定JSONのsource_snapshots_lfに保持している。

2026-11-20、基点main `816129a`、Zig 0.17.1。利用者が最初の対象としてNES APUを選択したため、1132の子1134として実装した。1131の汎用合成とは別のレジスタモデルである。今回の変更は未コミット。

## 範囲と判断

Forth側にNTSCのpulse 2声、triangle、noiseとenvelope/length/sweep/linear counter、フレームIRQを置く。時間指定書込み、状態の読取り、48kHzのmono s16LE出力を扱う。既存のNES-SOUND（MML用の近似音源）は変更せず、本体のBuiltinも追加しない。

DMC/DMA、CPU/PPUのバス競合、半サイクル単位のlength reload競合、PAL/Dendy、実機の電源投入状態、帯域制限・アナログフィルターは未実装。これは決定的なサブセットで、ROM互換や実機との完全一致を保証するものではない。DMCと残る互換性は1135に分け、1132と999全体は完了にしない。

## 資料とライセンス

参照したのはNESdevの技術資料の数値・動作説明で、任天堂の公式仕様ではない。他のエミュレーターのソースは使用・転記していない。Forth/Pythonは独自実装。NESdev本文は検索で索引された内容を確認した。一部ページの直接取得は403となったため、最新の全文を取得したとは扱わない。参照日2026-11-20。

| 資料 | 照合した範囲 |
| --- | --- |
| [APU registers](https://www.nesdev.org/wiki/APU_registers) | 書込み番地、enable/status、unused番地、長さ表 |
| [APU Pulse](https://www.nesdev.org/wiki/APU_Pulse) | duty列、CPU/2タイマー、high書込みの位相初期化 |
| [APU Envelope](https://www.nesdev.org/wiki/APU_Envelope) | start/divider/decay、constant/loopの独立性 |
| [APU Sweep](https://www.nesdev.org/wiki/APU_Sweep) | target/消音、2声の減算差、reloadとdivider |
| [APU Length Counter](https://www.nesdev.org/wiki/APU_Length_Counter) | 32項目の長さ、disable時の0化、halt |
| [APU Triangle](https://www.nesdev.org/wiki/APU_Triangle) | CPUタイマー、linear reload、停止時のDAC保持 |
| [APU Noise](https://www.nesdev.org/wiki/APU_Noise) | NTSCの周期表、15bit LFSRの2つのtap |
| [APU Mixer](https://www.nesdev.org/wiki/APU_Mixer) | DMC=0での非線形近似式と2種類のDAC群 |
| [Frame Counter](https://www.nesdev.org/wiki/APU_Frame_Counter) / [発生信号の調査](https://www.nesdev.org/wiki/Talk:APU_Frame_Counter) / [位相と遅延の議論](https://forums.nesdev.org/viewtopic.php?t=23803) | フレーム時計の間隔、reset遅延。位相・競合は下記の試作規則へ固定し、実機境界の確認とは分ける |

## 語と時刻の契約

[nes-apu.fs](../include/nes-apu.fs)を読むだけでは音声を起動しない。論理メモリ上の1個のモデルで、再入・複数同時インスタンスは扱わない。低水準のNA@/NA!等は例内部用で、無効なchannel/fieldを受け付ける公開インターフェイスではない。

| 語 | スタック効果 | 内容 |
| --- | --- | --- |
| NA-RESET | -- | 状態と予定表を決定的に初期化する |
| NA-WRITE | value address cycle -- | 検査後に指定時刻へ進めて即時書込み。設定・状態検査用 |
| NA-EVENT! | value address cycle -- | 時刻順の予定表に追加。時刻は進めない |
| NA-RUN | clocks -- | 予定された書込みを適用して指定CPUクロック数を進める。音を格納しない |
| NA-TO | cycle -- | 絶対CPU時刻まで進める。音を格納しない |
| NA-STATUS | cycle -- status | 指定時刻で4015相当のlength/IRQ状態を読み、frame IRQを消す |
| NA-IRQ? | -- flag | 現在のframe IRQを消さずに照会する |
| NA-RENDER | addr frames -- | 時間を進めながら48kHz、mono s16LEを格納する |
| NA-SAMPLE | -- s16 | 現在の4声のDAC値を混合して返す。時刻は進めない |

時刻Nへの書込みはtick Nの後、N+1の前。同時刻の予定書込みは受付順。同じ時刻へのNA-WRITEは先に登録した予定書込みの後。音を途切れず生成する場合は予定表とNA-RENDERを使う。NA-RUN/NA-TO/NA-WRITE/未来時刻でのNA-STATUSは出力を格納しないので、呼出し側が意図して音を捨てる状態検査用である。

予定表の未処理分は最大1024件。物理領域の末尾に達したら、すべての受付検査に成功した後で処理済み領域を回収する。APUをRESETせず継続して追加できる。最後の登録時刻未満、現在時刻未満は-24。満杯は-528。valueは0..255、番地は4000..4017のAPU範囲を検査する。4009/400Dは無視し、4014/4016は-24。DMCの4010..4013および4015のbit4有効化は-21で拒否する。4015のbit5..7は無視する。不正入力は時刻も状態も変える前に拒否する。64bitの時刻加算overflowも拒否する。

NA-RENDERは有効なframes×2byteの出力領域を呼出し側が用意する。負のframesは-24、0ならメモリを参照しない。CPU換算は1789773/48000の整数商と端数を引き継ぐ。各区間の最終tick後の点標本で、区間平均や帯域制限ではない。分割しても端数を失わない。NA-RUNはこの標本端数を変更しない。

## モデルの具体値

1CPUクロック版とまとめ処理版は同じ状態を使い、`TRUE NA-SLOW !`で前者を選ぶ。既定はまとめ処理。モデル周期の1秒は1,789,773 CPUクロックと固定する。

- resetは全レジスタ/長さ/位相を0、noise LFSRを1、noiseタイマー周期を2 APUクロック（4 CPUクロック）とする。triangleの段0のDAC値15を保持する。実機の電源投入状態を再現したとは扱わない。
- pulse/noiseは偶数CPU時刻でclock、triangleは毎CPU時刻。dividerは0ならreloadと出力clock、それ以外は1減算。noiseの表はCPUクロック単位なので2で割って使う。
- pulse high書込みはsequenceを0に戻し、envelope startを立てるが、timerのカウントは戻さない。lengthは有効なchannelだけreloadする。sweepは無効でもtarget overflowとperiod<8による消音を反映し、pulse1のnegateだけ追加で1を引く。
- triangleの段はlengthとlinearが両方非0のときだけ進む。0/1のtimer値でも進め、停止時は最後のDAC値を保持する。
- quarterはenvelope/linear、halfはlength/sweep。各CPU時刻ではtimerを先に進め、その後にframe処理を行う。
- 4stepは相対CPU時刻7457/14913/22371/29829でquarter、14913/29829でhalf、29828/29829/29830でIRQを立て、29830でwrapする。5stepは最終quarter/halfを37281とし37282でwrapする。これは試作の整数位相規則で、電源位相や半サイクル競合は保証しない。
- 4017は偶数時刻で3、奇数時刻で4クロック後にreset。mode変更とmode1のquarter/halfはその時点で適用する。inhibitは書込み時に反映しIRQを消す。旧frame eventとresetが重なればresetを優先する。この衝突規則は実機確認済みの主張ではない。
- ミキサーは資料の近似DAC式をDMC=0で有理数化し、pulse31項目とtriangle/noise256項目の表を初期化する。各表をfloor(level×32767)してから加算する。3t+2nの別の近似は使わない。出力は直流分のある正のs16で、アナログの音質は再現しない。

## 試験と測定の入口

[verify-nes-apu.py](../tests/scripts/verify-nes-apu.py)は1クロックずつ動く独立Pythonモデル、Forthの1クロック版、まとめ処理版の状態・出力を比較する。Forthの2版はNA-CLOCK/NA-FRAME-END/NA-STORE/NA-TARGETを共有し、独立した実装はPython側だけである。Pythonも同じ仕様・状態配置から書いたため、資料の共通の読み違いは検出できない。予定表は自作の合成データで、ROM/他エミュレーターのコードや出力は使っていない。手計算したpulse/envelope/sweep/IRQ、LFSRのtapとミキサー表の2点も照合する。この比較は実機・公開ROMテストへの合格とは別である。

リポジトリ直下から：

```powershell
python tests/scripts/verify-nes-apu.py zig-out/bin/sigma --benchmark
zig-out/bin/sigma examples/nes-apu-play.fs -e "NA-DEMO-SETUP 16 FALSE NA-STREAM BYE"
```

[nes-apu-play.fs](../examples/nes-apu-play.fs)は既存のPS-SEND/cleanupを再利用し、部分書込み・空き待ち・drain/closeを扱う。FALSEでは合成後のバッファを0にして渡す。自動試験は無音であり、TRUEでの生成波形の可聴確認はしていない。保存したlive handleを他processで復元する使い方や、複数ストリームの並列実行はこの例の対象外。

## レビュー

指摘を反映し、[実装の最終レビュー](reviews/1134-final-claude-review.md)と[文書の限定再レビュー](reviews/1134-doc-final-claude-review.md)まで完了した。High/Mediumの残件なし。1134完了、NESの1132は50%。SID/Paula/STと対象一覧の作業登録を補った後の999は25%（均等平均）で、DMCの1135は未着手。

[提案原文](reviews/1134-design-claude-review.md)、[実装原文](reviews/1134-implementation-claude-review.md)、[評価・採否](reviews/1134-review-response.md)を分離する。Claude自身による実行確認は含まない。

## 実行結果と一次データ

Windows GNU/Linux musl（WSL）の通常版とdebug/graphics/extension除外版、計4構成で各12検査群を実行し、失敗0。状態59値の境界照合、予定書込みを含む2048frameの完全byte列比較、分割、途中enqueue、全/部分消費後の領域回収、同時刻順、overflow/stack不足の事前拒否、unused番地、手計算値、実PCMのエラー回収を含む。audio/graphics/extension除外版でも純粋なNAの例を実行した。

[測定・試験の生データ](measurements/2026-11-20-nes-apu.json)に全試験、予定表、コマンド、7回の値、バイナリSHA256、LF正規化ソース指紋を保存した。使用した実行体は以前のPCM1129でビルドしたZig 0.17.1、ReleaseFast、cpu=baseline、strip=trueのもの。本体ソースはその測定記録と同一であることを照合した。今回の実装はForth例とPython検証で、Zig本体の変更はない。

ホストCPUはAMD Ryzen 7 7700（8core/16thread）。他アプリは停止しておらず、OSの負荷や周波数は固定していない。以前の1131やGforthとの直接比較ではない。実装・ソースの範囲が違う測定を混ぜない。

## 合成負荷の測定と採否

測定対象は32768frame（入力換算約0.683秒分）、CPU換算1,221,690クロック。新しいprocessごとに同じ負荷を1回warm-upし、RESET・予定表登録・cycle0の設定反映を済ませてから測る。4声すべての状態をclockし、測定区間全体に128件の時間指定書込みを配置する。初期設定を含むイベント列もJSONに保存した。

通常負荷と1クロック版、最速noise（period index0）を含む負荷を各7processで測った。NTIMEのwall差とCPUTIMEのCPU差を残し、非正のwall/負のCPU差は失敗とする。今回すべて正のwall/非負のCPU差だった。最後の512frameのbyte和と最終CPU時刻、stack深さ0も照合した。byte和は並び替えを完全には検出できず、別の完全byte列試験で補っている。WindowsのCPU時間はwall時間より粗く、正方向のwall時刻跳躍をこの検査だけでは検出できない。

| OS | 実装/負荷 | 中央値 ns/frame | 中央値 ns/CPU clock | 実時間比 |
| --- | --- | --- | --- | --- |
| windows | reference | 17091.65 | 458.38 | 1.22倍 |
| windows | fast | 1843.27 | 49.43 | 11.30倍 |
| windows | fast_max_noise | 2283.91 | 61.25 | 9.12倍 |
| linux | reference | 14380.18 | 385.66 | 1.45倍 |
| linux | fast | 1628.61 | 43.68 | 12.79倍 |
| linux | fast_max_noise | 2016.99 | 54.09 | 10.33倍 |

まとめ処理版を採用し、**このNTSC 4声のサブセットはForth側に維持する**。通常/最速noiseの両方で、Windows/LinuxともAPU単独の48kHz生成に必要な実時間を上回ったため、現時点では本体に新しい音源を追加しない。約37CPUクロックごとの状態処理をまとめた効果であり、Forthの2版を別の独立実装として数えない。

この比には、エミュレートする6502/PPU、DMC/DMA、帯域制限・filter、PCM書込み・待機、装置遅延を含まない。これだけでNES全体が実時間に達するとは判断しない。DMC追加後は1135で再測定して採否を更新する。

## 実PCMへの無音送出

8192frame（約0.171秒分）を合成し、0で埋めてPCMへ渡した各1回の全process時間。開始・設定・合成・無音化・open/write/wait/engine drain/close・終了を含む。装置の再生完了時間ではない。partialは0より大きく要求未満、fullは受理0の回数。追加でNA-RENDERにoverflowを起こし、-24が伝わって所有handleが0になることも確認した。

| 対象 | 全process 秒 | WRITE | partial | full | WAIT | underrun | AUDIO? |
| --- | --- | --- | --- | --- | --- | --- | --- |
| windows | 0.312 | 22 | 5 | 1 | 6 | 0 | -1 |
| linux | 0.819 | 32 | 16 | 0 | 16 | 0 | 0 |
| windows-no-debug | 0.303 | 22 | 5 | 1 | 6 | 1 | -1 |
| linux-no-debug | 0.827 | 32 | 16 | 0 | 16 | 0 | 0 |

AUDIO?が0のLinuxは無音消費であり、実音声装置での確認ではない。underrunを0へ丸めず記録している。物理キー・生成波形の実聴・MacでのこのNES例の実行は未確認（追記：Mac実行と実聴は[1144](NES_DMC_FORTH.md#mac実機受け入れ1144)で確認）。既存のPCM基盤のMac受け入れ1130はdde0547で完了済みで、今回のNES例の未確認とは区別する。

## NES以外の対象

NESを先行したことで、C64 SID・Amiga Paula・Atari ST等を対象外にはしていない。[全対象の状態表](EMULATOR_CORE_PLAN.md#音源の対象と現在状態999)で管理する。SID1136とPaula1137のレジスタ対応Forth実装・実測は未着手。Atari ST1138は既存YM2149レジスタ経路の充足と不足を先に確認する。999全体の完了には、各機種の採否と対象一覧1139の照合を含める。このNESサブセットの速度から他機種の実装・移行の要否は判断しない。
