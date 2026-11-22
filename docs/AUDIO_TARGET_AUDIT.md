# 8対象の音源経路と不足の先行照合（1139）

2026-11-20、基点main53ebe81。これは対象漏れの監査で、最終採否1140とは別工程。エミュレータのCPU・描画・ROM互換はこの音源監査で完了とはしない。既存PCMの動作確認、チップの状態モデル、機種固有の時刻とI/Oを区別する。[ソース指紋/本文・資料SHA256/確認ページ・タスク出力](measurements/2026-11-20-audio-target-audit.json)を保存した。

## ソースと既存記録の照合

| 対象 | 確認できた既存経路 | 充足・不足と次の作業 |
| --- | --- | --- |
| CHIP-8 | PCM7語と独自4声PSモデル。native BEEPは40msの固定音 | 機種固有のsound timer/ゲートは未実装・未検証。既存BEEPをFx18の代用として完了にはしない。タイマー境界・0/再設定・PCM化をForthで補い、波形と拡張系の範囲を先に決めて検証/測定する |
| ZX Spectrum | native MSXのAY PSG、Forth YM2149とPCM | 48K系のULA/beeperの時刻付き出力と、128K系のAY/I/Oを満たす機種別例はない。native非同期SOUNDではCPU時刻・port select/readの契約が不足。YM32段をAY16段に読み替えただけでは充足しない。対象モデルを設計で確定し、不足をForthで検証する |
| NES | NA-WRITE/EVENT!/READ、5声/DMC・独立PCM比較・実測・3OS実聴 | 1132は完了。宣言したNTSCモデルはForthで維持する既存判断。DMAのCPU停止/bus競合・CPU/PPU・PAL等はモデル外で、実機互換を完了した意味ではない |
| Commodore 64 | SI-WRITE/EVENT!/READ、3声/ADSR/独自Q16 filter・独立比較・実測・3OS実聴 | 1136は完了。6581/8580のanalog/合成波形等はモデル外。重い混在条件のWindows約1.03倍はSID単独の値であり、C64全体の余裕を示さない |
| SNES | PCM出力のみ。nativeの6chip enumにSNESはなく、PS独自4声やMOD再生はS-DSPではない | S-DSPの8声・BRR・状態/レジスタ・envelope/noise・echo等のForthモデルと性能判断が未実装。SPC700のCPU実装とは分けて音源側を設計/検証/測定する。PCMがあることを完了理由にしない |
| Apple II | PCM出力。汎用PSモデルは波形生成だけ | speaker toggleのbus時刻・read/write副作用・波形化の例がない。機種差を先に確定してForthで補う。BEEP固定音ではC030への任意タイミングのアクセスを再現できない |
| Amiga | PA-WRITE/EVENT!/READ、4声stereo/DMA/手動DAT/IRQ/attach・独立比較・実測・3OS実聴 | 1137は完了。宣言した音源はForth維持。Agnus slot/CPU/Copper競合、実機IRQ pipeline、analog等はモデル外 |
| Atari ST | native ST-SOUND/SOUNDとForth YM register/time/read/virtual ports/ST byte bus・独立比較・実測・Windows/Linux実聴 | 1138は未完了。Mac1154を待つ。nativeは固定音量0のmute修正だけ、モデルはForth維持。virtual pin宣言・byte busの限定を実周辺機器/68000互換と混同しない |

PCM基盤998、NES1132、SID1136、Paula1137は最新tqueで完了。YM1138はMac1154未完了。Windows/Linuxの実聴は[Windows PCM](measurements/2026-11-20-pcm-windows-listening.json)、[Windows NES/SID](measurements/2026-11-20-nes-sid-windows-listening.json)、[Windows Paula/YM](measurements/2026-11-20-paula-ym-windows-listening.json)、[Linux](measurements/2026-11-20-linux-audio-listening.json)を確認した。LinuxはWSL/pacat/PulseAudio/RDPSinkで、Linux実機ALSAの受け入れとは区別する。

## 既存機能だけでは完了にできない根拠

`src/core/sound_parts.zig`のChipはmsx/atari_st/nes/c64/scc/amigaの6種類。`src/core/sound_engine.zig`のBEEPはperiod85・40ms（既定MSXでは約1316Hz、選択済みPSG clockに依存）で、reset commandは既存MMLにも作用する。一般の可変ゲートや時刻付きspeaker toggleのAPIではない。

`examples/pcm-synth.fs`は48000Hzの独自4声/Q24 oscillatorで、clock指定queue・CHIP-8 timer・ULA port・Apple soft switch・S-DSPは持たない。4声を持つことは、これらの機種の仕様を満たす証拠ではない。PCM7語は完成した標本を渡す出口として再利用できるが、機種の状態と標本の生成はアプリ側に必要。

`examples/ym2149.fs`は2MHz、32level envelope、STのbyte bus/pin宣言。`src/core/sound_psg.zig`はAY/YMでレベルと未使用bitの保持が異なる。ZXでのクロック・AYの段数/位相・port decodeは、そのまま転用せず設計で照合する。

これらはソースに基づく不足の判定で、将来のForth実装の速度や互換性の予測ではない。この監査では本体移行を決めず、新しいBuiltin/ABIも追加しない。Forthで試作して測定し、不足した機種だけ本体移行を検討する順序は、[2026-11-18の利用者決定](EMULATOR_CORE_PLAN.md#決定事項2026-11-18)に従う。今回新しく最終採否を決めたものではない。

後続の音源単独試験は、CPU実装の代わりに絶対時刻付きの合成write/read/toggle列を与え、境界直前/同時刻/直後と複数イベント・分割レンダーを別実装/手計算で照合する。CPU cycleから音源clock/標本への変換、read/writeを置く時点、丸めと同tick順序を設計で明記する。将来Z80/6502等と接続する際の命令/bus時刻の一致は別の統合検証で、この音源単独試験からCPU互換を主張しない。

PCMは1hostにつき1streamである。採用する機種に複数の音源があれば、Forthで共通の時刻・標本形式へ合わせて混合してから1本を送る。ZXのbeeper+AYや追加音源の扱い、飽和/音量、SNES等の生成rateとhostの48kHz sample hold変換を分けて設計/試験する。PCMのrate変換はDSP内の補間の代用ではなく、音源側の品質/aliasingの契約も必要。

### 機種名と変種の境界

既存機種の「完了」は各文書で宣言したモデルの完了で、全family/追加音源を網羅した意味ではない。NESのPAL/カートリッジ拡張音源、SIDのD418 digi、ST以外のSTE DMA/Falcon等は、この監査で新たに実装済みとはしない。Apple IIgsのDOCや追加音源boardも単なるspeaker toggleの変種と同一視しない。これらの主計画での対象/保留理由は1140で明示確定し、必要と選んだ不足は機種別作業と1140の依存に追加して完了を待つ。未判定を暗黙に対象外へはしない。

過去の文書に残る「未完了」は当時の履歴で、冒頭の受け入れ追記と今回の時刻付きtque snapshotを現在判定に用いる。旧記述を現在状態の根拠として引用しない。

## 一次資料と未決の範囲

メーカー名義資料の第三者掲載版を読んだ事実を短く要約し、コードやROM・資料本文を実装へ転載しない。原本の真正性/完全性や正規配布元であることを保証する意味ではない。参照したPDFのSHA256と確認ページは[監査記録](measurements/2026-11-20-audio-target-audit.json)へ保存した。資料の記載と、そこから導く設計上の不足は分ける。

- RCA COSMAC VIP Instruction ManualのCHIP-8命令表はFx18のdurationを1/60秒単位で示す（確認PDF13頁、印刷14頁）。タイマーの実装上の境界や原機の特殊動作まで、この表だけで決めない。[RCA資料の写し](https://storage.googleapis.com/wzukusers/user-34724694/documents/130d458901764787969269f48aeeee2a/VIP_Manual.pdf)。原型とSUPER-CHIP/XO-CHIP等の対象範囲、発振波形/周波数は次の設計で確定する。
- Sinclair ZX Spectrum 128 Service Manual §1.6.1/1.7はULAのport254/D4出力とPSGを別に扱う。[ULA出力](https://www.manualslib.com/manual/1322152/Sinclair-Zx-Spectrum-128.html?page=15)、[PSG](https://www.manualslib.com/manual/1322152/Sinclair-Zx-Spectrum-128.html?page=16)。今回の参照は再組版されたメーカー文書であり、基板revisionや全モデルのアナログ混合を検証したものではない。48K/128K等の対象モデルとMIC/EAR/周辺I/Oの範囲を設計で確定する。
- Apple II Reference Manual（1978）p43はC030へのアクセスによるspeaker toggleから音を作る説明を持つ（PDF51頁）。[Apple原典の写し](https://apple2history.org/dl/Apple_II_Redbook.pdf)。IIcのread/write挙動は原型と同一と仮定しない。II/II+/IIe/IIc/IIgs、追加音源board等の扱いは次の設計で確定する。未調査の変種を対象外と決めた意味ではない。
- Nintendo SNES Development Manual Book1 §2-22.5.2は8声のDSP/noise/echo/envelope等、Section3 Chapter2はBRR blockを記述する。[Nintendo資料の写し](https://floating.muncher.se/bot/manual/book1_text.pdf)。DSP機能の一覧を確認した段階で、全DSP timingやCPU/APU連携を定義したものではない。次の設計で実装範囲と保留項目を確定する。

第三者の公開mirrorであり、メーカーの再配布許諾は確認できていない。とくにSNES開発資料は任天堂公式の現行配布物とは確認していないため、今回の使用は機能を分類するための閲覧と事実の短い要約に限る。SDK/ソース/ROMの入手・転載・配布や、それらのライセンスをSigmaへ適用する判断はしていない。後続1174の資料/ライセンス確認でも、参照可能な仕様とコード利用条件を分けて記録する。

CHIP-8系では、XO-CHIPのpattern buffer/pitchは原型のduration timerと別の追加仕様である。[仕様作者の文書](https://johnearnest.github.io/Octo/docs/XO-ChipSpecification.html)も1164の対象選定の候補とし、今回実装済みや採用済みにはしない。

## 後続タスクと採否

CHIP-8、ZX Spectrum、SNES、Apple IIの4件を999直下の機種別作業として追加し、各機能の配下に仕様/実装、Windows/Linux検証・測定、Mac受け入れを置く。実聴は各OSの検証範囲へ含め、機能の最後にまとめて未確認を隠さない。Macが終わるまで機種の親を完了にしない。

既存機種は自動検査と実聴を別の子として持つが、新規はOS別の子の受け入れ条件に両方を含めた。どちらも機能配下で未確認を保持する方針で、末尾の統合へ集約する変更ではない。必要なら実行時に各OSの子をさらに分割して追跡する。

1140は従来のNES/SID/Paula/ST/1139への依存を保持し、新4件への依存も追加する。1139の完了は対象一覧と不足の追跡が揃ったことだけを表し、新4件や999/1140の完了ではない。追加なしで8対象すべてが充足するという結論は採用しない。

### 登録した機種別作業

| 機種 | 親 | 仕様/実装 | Windows | Linux | Mac |
| --- | --- | --- | --- | --- | --- |
| CHIP-8 | 1163 | 1164 | 1165 | 1166 | 1167 |
| ZX Spectrum | 1168 | 1169 | 1170 | 1171 | 1172 |
| SNES | 1173 | 1174 | 1175 | 1176 | 1177 |
| Apple II | 1178 | 1179 | 1180 | 1181 | 1182 |

2026-11-22：Apple IIの1179（仕様・実装・独立検証）は完了した。対象は内蔵スピーカーとMockingboardで、結果は[APPLE2_AUDIO_FORTH.md](APPLE2_AUDIO_FORTH.md)。同じ日に、Windows（1180）、Linux（1181）、Mac（1182）の受け入れも完了した。

全件未着手。親は1131、各OSは機種の実装へ依存し、MacはPCMのMac基盤1130も前提とする。MacをWindows/Linuxの完了待ちにする依存は加えず、実装後に独立して進められる。1140の依存先は1132/1136/1137/1138/1139/1163/1168/1173/1178で、既存依存を削っていない。

[Claudeレビューの評価と採否](reviews/1139-review-response.md)。レビューは読取りだけで、実際のCLI照合とPDF画像確認は別に行った。

1139を完了した。新4機種は未着手、1140は依存待ち。監査完了を音源全体の完了へ置き換えない。
